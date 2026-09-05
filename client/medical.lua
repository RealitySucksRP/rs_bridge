local MedicalResources = {
    'qbx_medical',
    'qb-ambulancejob',
    'esx_ambulancejob',
    'wasabi_ambulance',
    'ak47_ambulancejob',
    'ars_ambulancejob'
}

local cachedMedicalProvider = nil
local lastKnownDead = false
local lastKnownDown = false

local function resolveMedicalProvider()
    local forced = RSBridgeConfig.Medical and RSBridgeConfig.Medical.Provider or 'auto'
    if forced ~= 'auto' then return forced end

    if cachedMedicalProvider and (cachedMedicalProvider == 'native' or RSBridge.resourceStarted(cachedMedicalProvider)) then
        return cachedMedicalProvider
    end

    -- Prefer the medical resource native to the detected framework. This
    -- prevents a compatibility shim or an unrelated installed ambulance
    -- resource from winning purely because of list order.
    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_medical') then
        cachedMedicalProvider = 'qbx_medical'
        return cachedMedicalProvider
    end

    if RSBridge.Framework == 'qbcore' and RSBridge.resourceStarted('qb-ambulancejob') then
        cachedMedicalProvider = 'qb-ambulancejob'
        return cachedMedicalProvider
    end

    if RSBridge.Framework == 'esx' and RSBridge.resourceStarted('esx_ambulancejob') then
        cachedMedicalProvider = 'esx_ambulancejob'
        return cachedMedicalProvider
    end

    cachedMedicalProvider = RSBridge.firstStarted(MedicalResources) or 'native'
    return cachedMedicalProvider
end

AddEventHandler('onResourceStart', function(resource)
    for _, name in ipairs(MedicalResources) do
        if resource == name then
            cachedMedicalProvider = nil
            return
        end
    end
end)

-- Framework status events. These come from server -> client and tell us
-- when the framework's own ambulance flow flipped the death/last-stand flag.
RegisterNetEvent('hospital:client:SetDeathStatus', function(isDead)
    lastKnownDead = isDead == true
end)

RegisterNetEvent('hospital:client:SetLaststandStatus', function(isLastStand)
    lastKnownDown = isLastStand == true
end)

RegisterNetEvent('esx_ambulancejob:setDeathStatus', function(isDead)
    lastKnownDead = isDead == true
end)

local function ped()
    return PlayerPedId()
end

local function nativeRevive()
    local p = ped()
    local coords = GetEntityCoords(p)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(p), true, false)
    ClearPedBloodDamage(p)
    ClearPedTasksImmediately(p)
    ClearPedSecondaryTask(p)
    SetEntityInvincible(p, false)
    SetEntityHealth(p, RSBridgeConfig.Medical.ReviveHealth or 200)
    lastKnownDead = false
    lastKnownDown = false
    return true
end

local function nativeHeal()
    local p = ped()
    ClearPedBloodDamage(p)
    ClearPedTasks(p)
    SetEntityHealth(p, RSBridgeConfig.Medical.HealHealth or GetEntityMaxHealth(p))
    lastKnownDead = false
    lastKnownDown = false
    return true
end

function GetHealth()
    return GetEntityHealth(ped())
end

function SetHealth(health)
    health = tonumber(health) or 200
    SetEntityHealth(ped(), health)
    return true
end

function SetArmor(armor)
    armor = tonumber(armor) or RSBridgeConfig.Medical.DefaultArmor or 100
    SetPedArmour(ped(), armor)
    return true
end

function IsPlayerDead()
    if RSBridge.resourceStarted('qbx_medical') then
        local ok, dead = RSBridge.safeCall(function()
            return exports.qbx_medical:IsDead()
        end)
        if ok and dead then return true end
    end

    local data = GetPlayerData and GetPlayerData() or nil
    local metadata = data and data.metadata
    if metadata and (metadata.isdead == true or metadata.dead == true) then return true end
    if data and data.dead == true then return true end

    local p = ped()
    return lastKnownDead or IsEntityDead(p) or GetEntityHealth(p) <= 0
end

function IsPlayerDown()
    if RSBridge.resourceStarted('qbx_medical') then
        local ok, laststand = RSBridge.safeCall(function()
            return exports.qbx_medical:IsLaststand()
        end)
        if ok and laststand then return true end
    end

    local data = GetPlayerData and GetPlayerData() or nil
    local metadata = data and data.metadata
    if metadata and (metadata.inlaststand == true or metadata.laststand == true) then return true end

    return lastKnownDown or IsPlayerDead()
end

-- Provider branch gate. Returns true only if the provider is configured AND
-- the corresponding resource is actually running. Forced providers that are
-- not running fall through to native instead of silently claiming success.
local function providerActive(provider, resourceName)
    if provider ~= resourceName then return false end
    return RSBridge.resourceStarted(resourceName)
end

function RevivePlayer()
    local provider = resolveMedicalProvider()
    local useEvents = RSBridgeConfig.Medical.UseResourceEvents ~= false

    -- Revive intentionally trusts the provider and does NOT call nativeRevive
    -- on success. nativeRevive runs NetworkResurrectLocalPlayer which is
    -- visible (camera flash, ped reset) -- doubling it causes the flicker
    -- bug that v2.1.1 fixed. Heal is different (see HealPlayer below).

    if useEvents then
        if providerActive(provider, 'qb-ambulancejob') then
            TriggerEvent('hospital:client:Revive')
            lastKnownDead = false
            lastKnownDown = false
            Notify(_L('medical_revived'), 'success')
            return true
        end

        if providerActive(provider, 'qbx_medical') then
            -- qbx_medical's public Revive export is server-side. Its client
            -- revive event is the provider-owned local equivalent.
            local ok = RSBridge.safeCall(function()
                TriggerEvent('qbx_medical:client:playerRevived')
            end)

            if ok then
                lastKnownDead = false
                lastKnownDown = false
                Notify(_L('medical_revived'), 'success')
                return true
            end
        end

        if providerActive(provider, 'esx_ambulancejob') then
            TriggerEvent('esx_ambulancejob:revive')
            lastKnownDead = false
            lastKnownDown = false
            Notify(_L('medical_revived'), 'success')
            return true
        end

        if providerActive(provider, 'wasabi_ambulance') then
            local ok = RSBridge.safeCall(function()
                exports.wasabi_ambulance:revivePlayer()
            end)
            if ok then
                lastKnownDead = false
                lastKnownDown = false
                Notify(_L('medical_revived'), 'success')
                return true
            end
        end

        if providerActive(provider, 'ak47_ambulancejob') then
            TriggerEvent('ak47_ambulancejob:revive')
            lastKnownDead = false
            lastKnownDown = false
            Notify(_L('medical_revived'), 'success')
            return true
        end

        if providerActive(provider, 'ars_ambulancejob') then
            TriggerEvent('ars_ambulancejob:healPlayer', { revive = true })
            lastKnownDead = false
            lastKnownDown = false
            Notify(_L('medical_revived'), 'success')
            return true
        end
    end

    if provider == 'native' then
        nativeRevive()
        Notify(_L('medical_revived'), 'success')
        return true
    end

    -- Fell through. Either provider was unknown, the forced resource is not
    -- running, or its export call failed.
    RSBridge.debug(_L('medical_no_resource'))
    nativeRevive()
    Notify(_L('medical_revived'), 'success')
    return true
end

function HealPlayer()
    local provider = resolveMedicalProvider()
    local useEvents = RSBridgeConfig.Medical.UseResourceEvents ~= false

    -- Heal is uniformly belt-and-suspenders across all providers: run the
    -- provider's heal then nativeHeal. nativeHeal on an already-healthy ped
    -- is invisible (no camera flash, no ped reset), so doubling has zero
    -- player-visible cost and guarantees stamina, bleeding flags, and
    -- secondary tasks are cleared even if a provider's heal event misses
    -- one of them.

    if useEvents then
        if providerActive(provider, 'qb-ambulancejob') then
            TriggerEvent('hospital:client:HealInjuries', 'full')
            nativeHeal()
            Notify(_L('medical_healed'), 'success')
            return true
        end

        if providerActive(provider, 'qbx_medical') then
            local ok = RSBridge.safeCall(function()
                -- qbx_medical has no ResetMinor/ResetMajor export, and its
                -- Heal/Revive exports are SERVER side. The client-side heal is
                -- this event, which qbx_medical registers in client/main.lua
                -- and its own server Heal() triggers.
                TriggerEvent('qbx_medical:client:heal', 'full')
            end)

            if not ok then
                ok = RSBridge.safeCall(function()
                    TriggerEvent('hospital:client:HealInjuries', 'full')
                end)
            end

            if ok then
                nativeHeal()
                Notify(_L('medical_healed'), 'success')
                return true
            end
        end

        if providerActive(provider, 'esx_ambulancejob') then
            TriggerEvent('esx_basicneeds:healPlayer')
            nativeHeal()
            Notify(_L('medical_healed'), 'success')
            return true
        end

        if providerActive(provider, 'wasabi_ambulance') then
            local ok = RSBridge.safeCall(function()
                exports.wasabi_ambulance:healPlayer()
            end)
            if ok then
                nativeHeal()
                Notify(_L('medical_healed'), 'success')
                return true
            end
        end

        if providerActive(provider, 'ars_ambulancejob') then
            TriggerEvent('ars_ambulancejob:healPlayer', { revive = false })
            nativeHeal()
            Notify(_L('medical_healed'), 'success')
            return true
        end
    end

    nativeHeal()
    Notify(_L('medical_healed'), 'success')
    return true
end

function KillPlayer()
    SetEntityHealth(ped(), 0)
    lastKnownDead = true
    return true
end

-- Server -> client triggers
--- Only the server may drive these.
---
--- A handler registered with RegisterNetEvent is ALSO an ordinary local
--- handler, so these were previously reachable from the client itself: a
--- modified client could TriggerEvent('rs_bridge:client:revive') and stand
--- straight back up, or heal and armour at will. On the client, `source` is
--- 65535 only when the event genuinely arrived from the server.
---
--- The exports below are deliberately NOT wrapped. Another resource calling
--- exports.rs_bridge:SetHealth() is a legitimate local call and must keep
--- working -- it is the NET EVENT that was the open door, not the function.
---@param handler function
---@return function guarded
local function fromServer(handler)
    return function(...)
        -- Captured immediately: `source` is a shared global and any yield in
        -- the handler could see it change underneath.
        if source ~= 65535 then return end
        return handler(...)
    end
end

RegisterNetEvent('rs_bridge:client:revive', fromServer(RevivePlayer))
RegisterNetEvent('rs_bridge:client:heal', fromServer(HealPlayer))
RegisterNetEvent('rs_bridge:client:setArmor', fromServer(SetArmor))
RegisterNetEvent('rs_bridge:client:setHealth', fromServer(SetHealth))
RegisterNetEvent('rs_bridge:client:kill', fromServer(KillPlayer))

-- Client -> server medical state sync.
-- Server uses this to answer GetHealth, IsPlayerDead, IsPlayerDown
-- for any cause of death, not just bridge-initiated ones.
local syncedHealth = -1
local syncedDead = false
local syncedDown = false
local SYNC_HEALTH_THRESHOLD = 5

CreateThread(function()
    while true do
        Wait(500)
        local p = ped()
        if p and p ~= 0 and p ~= -1 then
            local health = GetEntityHealth(p)
            local dead = IsPlayerDead()
            local down = IsPlayerDown()

            local crossedZero = (health <= 0) ~= (syncedHealth <= 0)
            local healthMoved = math.abs(health - syncedHealth) >= SYNC_HEALTH_THRESHOLD

            if dead ~= syncedDead or down ~= syncedDown or crossedZero or healthMoved then
                syncedHealth = health
                syncedDead = dead
                syncedDown = down
                TriggerServerEvent('rs_bridge:server:setMedicalState', dead, down, health)
            end
        end
    end
end)

exports('GetHealth', GetHealth)
exports('SetHealth', SetHealth)
exports('SetArmor', SetArmor)
exports('HealPlayer', HealPlayer)
exports('RevivePlayer', RevivePlayer)
exports('KillPlayer', KillPlayer)
exports('IsPlayerDead', IsPlayerDead)
exports('IsPlayerDown', IsPlayerDown)
