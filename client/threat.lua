--[[
    rs_bridge -- shared stalker threat model (CLIENT)

    Included by consumers as '@rs_bridge/client/threat.lua', so it runs inside
    that resource's own Lua VM and defines RSThreat there. It deliberately holds
    state and closures, which is why this is an include rather than an export --
    FiveM exports serialise across the resource boundary and cannot carry either.

    The scalar model is extracted faithfully from rs-phantomstalkers v1.6.1
    (RS.UpdateThreat), which was tuned across many releases. Every weight is
    supplied by the caller, so adopting this module changes no behaviour on its
    own -- rs-phantomstalkers passes its existing Config.Brain values and gets
    identical arithmetic.

    Two things are new here and off by default:

      1. Capability awareness. The stock model reacts only to geometry (distance,
         facing, movement). It presses a lone player at 20% health exactly as
         hard as a squad of four with rifles. Capability modifiers scale threat
         build by what the target can actually do about it. All default to
         neutral (1.0 / 0), so they are inert until configured.

      2. Aggression that can fall. rs-phantomstalkers has no aggression tier, and
         RealitySucks-PhantomCar's only ever ratchets upward -- once a player hit
         four engagements the phantom pinned to maximum for the rest of the
         deployment, so escaping cleanly earned nothing. Escalate() still steps
         up, but aggression now bleeds back down while nothing is engaging.
]]

RSThreat = RSThreat or {}
RSThreat.__index = RSThreat

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function num(v, fallback)
    v = tonumber(v)
    if v == nil then return fallback end
    return v
end

---Counts real players near a coordinate, used to back off from groups.
---Capped so a busy server cannot turn this into a long loop every tick.
local function countNearbyPlayers(coords, radius, selfPlayer)
    local n = 0
    local r2 = radius * radius
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= selfPlayer then
            local ped = GetPlayerPed(pid)
            if ped and ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
                local d = GetEntityCoords(ped) - coords
                if (d.x * d.x + d.y * d.y + d.z * d.z) <= r2 then
                    n = n + 1
                    if n >= 8 then return n end
                end
            end
        end
    end
    return n
end

---@param cfg table weights; see rs-phantomstalkers Config.Brain for the shape
---@return table model
function RSThreat.New(cfg)
    cfg = type(cfg) == 'table' and cfg or {}

    local self = setmetatable({}, RSThreat)

    -- Core weights. Defaults match rs-phantomstalkers v1.6.1 Config.Brain so an
    -- omitted field never silently changes tuned behaviour.
    self.w = {
        decay          = num(cfg.ThreatDecayPerTick, 0.18),
        ignoreBuild    = num(cfg.IgnoreBuildPerTick, 0.95),
        closeBuild     = num(cfg.CloseBuildPerTick, 1.8),
        closeRange     = num(cfg.CloseRange, 18.0),
        fleeBuild      = num(cfg.RunningAwayBuild, 2.4),
        fleeRange      = num(cfg.RunningAwayRange, 45.0),
        approachBuild  = num(cfg.PlayerApproachBuild, 2.0),
        approachRange  = num(cfg.PlayerApproachRange, 12.0),
        aimBuild       = num(cfg.PlayerAimBuild, 8.0),
        attackBuild    = num(cfg.PlayerAttackBuild, 28.0),
        outrunDrop     = num(cfg.OutrunDrop, 9.0),
        outrunRange    = num(cfg.OutrunRange, 90.0),
        watch          = num(cfg.WatchThreat, 25),
        stalk          = num(cfg.StalkThreat, 55),
        attack         = num(cfg.AttackThreat, 85),
    }

    -- Stationary pressure. One-shot bump, re-armed once the target moves again.
    local st = type(cfg.Stationary) == 'table' and cfg.Stationary or {}
    self.stationary = {
        enabled   = st.Enabled == true,
        moveDist  = num(st.MoveDist, 1.5),
        threshold = num(st.Threshold, 8000),
        boost     = num(st.ThreatBoost, 12.0),
    }

    -- Capability modifiers. Neutral by default: multipliers 1.0, bonuses 0.
    local cap = type(cfg.Capability) == 'table' and cfg.Capability or {}
    self.cap = {
        enabled        = cap.Enabled == true,
        armedMult      = num(cap.ArmedBuildMult, 1.0),
        aimedArmedMult = num(cap.ArmedAimingBuildMult, 1.0),
        vehicleMult    = num(cap.TargetInVehicleBuildMult, 1.0),
        woundedMult    = num(cap.WoundedBuildMult, 1.0),
        woundedAt      = clamp(num(cap.WoundedHealthFraction, 0.5), 0.0, 1.0),
        isolatedBonus  = num(cap.IsolatedBuildBonus, 0.0),
        groupMult      = num(cap.GroupBuildMult, 1.0),
        groupSize      = math.max(1, math.floor(num(cap.GroupSize, 2))),
        groupRadius    = num(cap.GroupRadius, 30.0),
        scanIntervalMs = math.max(500, math.floor(num(cap.ScanIntervalMs, 2000))),
    }

    -- Aggression tier with decay -- the ratchet fix.
    local ag = type(cfg.Aggression) == 'table' and cfg.Aggression or {}
    self.ag = {
        enabled     = ag.Enabled == true,
        maxLevel    = math.max(1, math.floor(num(ag.MaxLevel, 3))),
        perEngage   = num(ag.PointsPerEngage, 1.0),
        decayPerSec = num(ag.DecayPerSecond, 0.05),
        calmAfterMs = math.max(0, math.floor(num(ag.CalmAfterMs, 20000))),
        escapeDrop  = num(ag.EscapePoints, 1.0),
    }

    self.value        = num(cfg.Start, 0.0)
    self.aggression   = 1
    self.agPoints     = 0
    self.notLooking   = false
    self.lastPos      = nil
    self.lastUpdate   = 0
    self.lastEngageAt = 0
    self.stillSince   = nil
    self.stillUsed    = false
    self.capCache     = { at = 0, mult = 1.0, bonus = 0.0 }

    return self
end

---Recomputes capability scaling. Throttled: the group scan walks the player
---list, which is not something to do on every tick of every stalker.
function RSThreat:_capability(targetPed, now)
    if not self.cap.enabled then return 1.0, 0.0 end
    if (now - (self.capCache.at or 0)) < self.cap.scanIntervalMs then
        return self.capCache.mult, self.capCache.bonus
    end

    local mult, bonus = 1.0, 0.0
    local c = self.cap

    -- An armed target is a harder target: build slower, hang back longer.
    if IsPedArmed(targetPed, 6) then
        mult = mult * c.armedMult
        if IsPlayerFreeAiming(PlayerId()) then
            mult = mult * c.aimedArmedMult
        end
    end

    if IsPedInAnyVehicle(targetPed, false) then
        mult = mult * c.vehicleMult
    end

    local maxHp = GetEntityMaxHealth(targetPed)
    if maxHp > 0 then
        local frac = GetEntityHealth(targetPed) / maxHp
        if frac <= c.woundedAt then
            mult = mult * c.woundedMult
        end
    end

    local nearby = countNearbyPlayers(GetEntityCoords(targetPed), c.groupRadius, PlayerId())
    if nearby >= (c.groupSize - 1) and nearby > 0 then
        mult = mult * c.groupMult
    elseif nearby == 0 then
        bonus = bonus + c.isolatedBonus
    end

    self.capCache.at, self.capCache.mult, self.capCache.bonus = now, mult, bonus
    return mult, bonus
end

---Advances the model one tick.
---@param selfEntity number the stalker entity (ped or vehicle)
---@param targetPed number usually PlayerPedId()
---@param dist number cached distance between them
---@param notLooking boolean caller-supplied line-of-sight verdict
---@return number threat, boolean notLooking
function RSThreat:Update(selfEntity, targetPed, dist, notLooking)
    local now = GetGameTimer()
    local pos = GetEntityCoords(targetPed)
    local moved = self.lastPos and #(pos - self.lastPos) or 0.0
    local w = self.w

    self.notLooking = notLooking == true

    local capMult, capBonus = self:_capability(targetPed, now)

    -- Decay is not scaled by capability: threat should always bleed off at the
    -- same rate, otherwise a wounded target could never lose a pursuer at all.
    local v = self.value - w.decay

    local build = 0.0
    if self.notLooking then build = build + w.ignoreBuild end
    if dist < w.closeRange then build = build + w.closeBuild end
    if moved > 2.2 and dist < w.fleeRange then build = build + w.fleeBuild end
    if moved > 0.8 and dist < w.approachRange then build = build + w.approachBuild end
    if IsPlayerFreeAiming(PlayerId()) then build = build + w.aimBuild end

    if selfEntity and selfEntity ~= 0 and DoesEntityExist(selfEntity)
       and HasEntityBeenDamagedByEntity(selfEntity, targetPed, true) then
        build = build + w.attackBuild
        ClearEntityLastDamageEntity(selfEntity)
        self:Engage()
    end

    v = v + (build * capMult) + capBonus

    if dist > w.outrunRange then v = v - w.outrunDrop end

    -- Stationary pressure: standing still should feel like being found.
    if self.stationary.enabled then
        if moved > self.stationary.moveDist then
            self.stillSince = now
            self.stillUsed = false
        elseif not self.stillUsed then
            if (now - (self.stillSince or now)) >= self.stationary.threshold then
                v = v + self.stationary.boost
                self.stillUsed = true
                self.stationaryFired = true
            end
        end
    end

    self:_decayAggression(now)

    self.value = clamp(v, 0.0, 100.0)
    self.lastPos = pos
    self.lastUpdate = now
    return self.value, self.notLooking
end

---Band the current threat falls into. Callers map these onto their own states.
---@return 'idle'|'watch'|'stalk'|'attack'
function RSThreat:Level()
    local v = self.value
    if v >= self.w.attack then return 'attack' end
    if v >= self.w.stalk then return 'stalk' end
    if v >= self.w.watch then return 'watch' end
    return 'idle'
end

function RSThreat:Value() return self.value end
function RSThreat:Aggression() return self.aggression end

---True exactly once per stationary trigger, so callers can accelerate a
---decision without re-deriving the condition.
function RSThreat:ConsumeStationary()
    if not self.stationaryFired then return false end
    self.stationaryFired = false
    return true
end

---Steps aggression up. Call when an encounter actually begins.
function RSThreat:Engage()
    if not self.ag.enabled then return self.aggression end
    self.lastEngageAt = GetGameTimer()
    self.agPoints = self.agPoints + self.ag.perEngage
    self.aggression = clamp(1 + math.floor(self.agPoints), 1, self.ag.maxLevel)
    return self.aggression
end

---Steps aggression down. Call when the target legitimately escapes, so that
---getting away is rewarded instead of being irrelevant.
function RSThreat:Escaped()
    if not self.ag.enabled then return self.aggression end
    self.agPoints = math.max(0, self.agPoints - self.ag.escapeDrop)
    self.aggression = clamp(1 + math.floor(self.agPoints), 1, self.ag.maxLevel)
    return self.aggression
end

function RSThreat:_decayAggression(now)
    local ag = self.ag
    if not ag.enabled or ag.decayPerSec <= 0 or self.agPoints <= 0 then
        self._lastAgDecay = now
        return
    end
    -- The decay clock must be kept current while still engaged. Returning here
    -- without touching it would leave a stale timestamp, so the first calm tick
    -- after a long engagement would compute a huge elapsed and wipe aggression
    -- to zero in one step instead of bleeding it off.
    if (now - (self.lastEngageAt or 0)) < ag.calmAfterMs then
        self._lastAgDecay = now
        return
    end
    local elapsed = (now - (self._lastAgDecay or now)) / 1000.0
    self._lastAgDecay = now
    if elapsed <= 0 then return end
    self.agPoints = math.max(0, self.agPoints - (ag.decayPerSec * elapsed))
    self.aggression = clamp(1 + math.floor(self.agPoints), 1, ag.maxLevel)
end

---Forces the scalar, e.g. after a scripted beat.
function RSThreat:Set(v)
    self.value = clamp(num(v, self.value), 0.0, 100.0)
    return self.value
end

---Full reset for despawn/redeploy.
function RSThreat:Reset(startValue)
    self.value = clamp(num(startValue, 0.0), 0.0, 100.0)
    self.aggression = 1
    self.agPoints = 0
    self.lastPos = nil
    self.stillSince = nil
    self.stillUsed = false
    self.stationaryFired = false
    self.lastEngageAt = 0
    self._lastAgDecay = nil
    self.capCache = { at = 0, mult = 1.0, bonus = 0.0 }
end
