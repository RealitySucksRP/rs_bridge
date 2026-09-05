local pendingState = {}

local function setPending(src, key, value)
    pendingState[src] = pendingState[src] or {}
    pendingState[src][key] = value
end

local function readMetadata(src)
    local data = GetPlayerData(src)
    if type(data) == 'table' and type(data.metadata) == 'table' then
        return data.metadata
    end
    return nil
end

local function clearESXDeathPersistence(src)
    if RSBridge.Framework ~= 'esx' or not RSBridge.resourceStarted('esx_ambulancejob') then
        return true
    end

    local player = GetPlayer(src)
    if not player then return false end

    local identifier = player.identifier
    if not identifier and player.getIdentifier then
        local ok, value = RSBridge.safeCall(function()
            return player.getIdentifier()
        end)
        if ok then identifier = value end
    end
    if not identifier then return false end

    -- Current ESX Legacy Ambulance Job persists death in users.is_dead.
    -- Its public client revive path triggers esx:onPlayerSpawn, which clears
    -- the live state bag, but an AI/server-owned revive also needs to clear
    -- the persistent database flag so the player does not return dead after
    -- reconnecting. oxmysql is already part of rs_bridge's server runtime.
    local ok = RSBridge.safeCall(function()
        if MySQL and MySQL.update and MySQL.update.await then
            MySQL.update.await('UPDATE users SET is_dead = 0 WHERE identifier = ?', { identifier })
        elseif MySQL and MySQL.update then
            MySQL.update('UPDATE users SET is_dead = 0 WHERE identifier = ?', { identifier })
        end

        local state = Player(src) and Player(src).state
        if state then state:set('isDead', false, true) end

        if player.getMeta and player.clearMeta then
            local meta = player.getMeta()
            if type(meta) == 'table' and meta.deathTime ~= nil then
                player.clearMeta('deathTime')
            end
        end
    end)

    return ok == true
end

function RevivePlayer(src)
    src = tonumber(src)
    if not src then return false end

    setPending(src, 'dead', false)
    setPending(src, 'down', false)

    -- Current qbx_medical exposes Revive on the SERVER. Use that official
    -- path so Qbox death-state bags and metadata are cleared by qbx_medical.
    if RSBridge.Framework == 'qbox'
        and RSBridgeConfig.Medical.UseResourceEvents ~= false
        and RSBridge.resourceStarted('qbx_medical')
    then
        local ok = RSBridge.safeCall(function()
            exports.qbx_medical:Revive(src)
        end)
        if ok then return true end
    end

    -- ESX Legacy keeps an additional persistent users.is_dead flag. Clear it
    -- before dispatching the provider's client revive so reconnect state stays
    -- consistent with the successful Dr. Graves treatment.
    if RSBridge.Framework == 'esx'
        and RSBridgeConfig.Medical.UseResourceEvents ~= false
        and RSBridge.resourceStarted('esx_ambulancejob')
    then
        if not clearESXDeathPersistence(src) then return false end
    end

    -- QBCore, ESX, custom providers, and native fallback are dispatched once
    -- to the client medical module. Never dispatch both paths.
    TriggerClientEvent('rs_bridge:client:revive', src)
    return true
end

--- True when qbx_medical's authoritative SERVER API is usable.
local function qbxMedicalAvailable()
    return RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_medical')
end

function HealPlayer(src)
    src = tonumber(src)
    if not src then return false end

    -- Heal should also clear pending dead/down so a heal-after-kill leaves
    -- the player in a clean state.
    setPending(src, 'dead', false)
    setPending(src, 'down', false)

    -- qbx_medical exposes Heal on the SERVER. Prefer it so injuries, bleeding
    -- and the death statebags are cleared by the system that owns them, instead
    -- of asking the client to approximate it.
    if qbxMedicalAvailable() then
        local ok, result = RSBridge.safeCall(function()
            return exports.qbx_medical:Heal(src)
        end)
        if ok and result ~= false then return true end
    end

    -- Single-dispatch rule:
    -- The client medical module owns provider-specific heal logic.
    TriggerClientEvent('rs_bridge:client:heal', src)
    return true
end

--- Partial heal. qbx_medical models this natively; other frameworks have no
--- equivalent, so this reports unsupported rather than silently full-healing.
--- @return boolean|nil  nil = capability unsupported here.
function HealPlayerPartial(src)
    src = tonumber(src)
    if not src then return false end

    if qbxMedicalAvailable() then
        local ok, result = RSBridge.safeCall(function()
            return exports.qbx_medical:HealPartially(src)
        end)
        if ok and result ~= false then
            setPending(src, 'down', false)
            return true
        end
    end

    return nil
end

--- Injury/death status from the medical provider.
--- @return table|nil  nil = no provider could answer.
function GetMedicalStatus(src)
    src = tonumber(src)
    if not src then return nil end

    if qbxMedicalAvailable() then
        local ok, result = RSBridge.safeCall(function()
            return exports.qbx_medical:GetPlayerStatus(src)
        end)
        if ok and type(result) == 'table' then return result end
    end

    return nil
end

function SetArmor(src, armor)
    src = tonumber(src)
    if not src then return false end
    armor = tonumber(armor) or RSBridgeConfig.Medical.DefaultArmor or 100
    TriggerClientEvent('rs_bridge:client:setArmor', src, armor)
    return true
end

function SetHealth(src, health)
    src = tonumber(src)
    if not src then return false end
    health = tonumber(health) or RSBridgeConfig.Medical.HealHealth or 200
    setPending(src, 'health', health)
    TriggerClientEvent('rs_bridge:client:setHealth', src, health)
    return true
end

function KillPlayer(src)
    src = tonumber(src)
    if not src then return false end
    setPending(src, 'dead', true)
    setPending(src, 'health', 0)
    TriggerClientEvent('rs_bridge:client:kill', src)
    return true
end

-- Returns the most recent health value reported by the client sync loop.
-- Defaults to 200 until the first sync arrives.
function GetHealth(src)
    src = tonumber(src)
    if not src then return 0 end

    -- The SERVER's own view of the ped comes first.
    --
    -- This used to return the client's last reported number directly, so every
    -- resource asking the bridge for a player's health was reading a value the
    -- client chose. IsPlayerDead and IsPlayerDown below already layer their
    -- authoritative sources ahead of the client report; health did not.
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        local health = GetEntityHealth(ped)
        -- 0 means the ped has not streamed in yet as often as it means death,
        -- and returning 0 here would read as a corpse to every caller.
        if health and health > 0 then return health end
    end

    -- Client report, kept only as the fallback it always should have been.
    local entry = pendingState[src]
    if entry and entry.health then return entry.health end
    return 200
end

function IsPlayerDead(src)
    src = tonumber(src)
    if not src then return false end

    -- Qbox and current ESX Ambulance Job publish replicated isDead state.
    local playerState = Player(src) and Player(src).state
    if playerState and playerState.isDead == true then return true end

    -- Framework metadata is source of truth when available (qb/qbx).
    local meta = readMetadata(src)
    if meta then
        if meta.isdead == true then return true end
        if meta.dead == true then return true end
    end

    -- Fallback to client-synced state.
    local entry = pendingState[src]
    return entry and entry.dead == true or false
end

function IsPlayerDown(src)
    src = tonumber(src)
    if not src then return false end

    local playerState = Player(src) and Player(src).state
    if playerState and playerState.isDead == true then return true end

    local meta = readMetadata(src)
    if meta then
        if meta.isdead == true or meta.dead == true then return true end
        if meta.inlaststand == true or meta.laststand == true then return true end
    end

    local entry = pendingState[src]
    if not entry then return false end
    return entry.down == true or entry.dead == true
end

-- Client -> server sync. Fires on meaningful change of dead/down/health.
--
-- INFORMATIONAL ONLY. Everything written here is a client report, and every
-- accessor above consults an authoritative source first -- the entity, the
-- statebag, framework metadata -- before falling back to it. Nothing that moves
-- money or makes a gameplay decision should read these values directly.
RegisterNetEvent('rs_bridge:server:setMedicalState', function(isDead, isDown, health)
    local src = source
    setPending(src, 'dead', isDead == true)
    setPending(src, 'down', isDown == true)
    if health ~= nil then
        setPending(src, 'health', tonumber(health) or 0)
    end
end)

AddEventHandler('playerDropped', function()
    pendingState[source] = nil
end)

exports('RevivePlayer', RevivePlayer)
exports('HealPlayer', HealPlayer)
exports('HealPlayerPartial', HealPlayerPartial)
exports('GetMedicalStatus', GetMedicalStatus)
exports('SetArmor', SetArmor)
exports('SetHealth', SetHealth)
exports('KillPlayer', KillPlayer)
exports('GetHealth', GetHealth)
exports('IsPlayerDead', IsPlayerDead)
exports('IsPlayerDown', IsPlayerDown)
