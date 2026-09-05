local PlayerData = {}

local function getESX()
    if RSBridge.Framework ~= 'esx' then return nil end
    if RSBridge.Core then return RSBridge.Core end

    if RSBridge.resourceStarted('es_extended') then
        local ok, esx = RSBridge.safeCall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok and esx then
            RSBridge.Core = esx
            return esx
        end
    end

    return nil
end

-- ESX exposes money as an `accounts` array and the job grade as a number plus
-- a separate grade_label. Every consumer of this bridge reads the normalized
-- shape (money.cash / money.bank, job.grade.name) that server/main.lua already
-- returns, so mirror that here instead of leaking the raw ESX layout.
--
-- Normalization is additive: the original ESX fields are left untouched, so
-- anything that genuinely wants `accounts` or `grade_label` still finds them.
local function normalizeESX(data)
    if type(data) ~= 'table' then return data end

    if type(data.accounts) == 'table' and not data.money then
        local money = {}
        for _, account in pairs(data.accounts) do
            if type(account) == 'table' and account.name then
                money[account.name] = account.money or 0
            end
        end
        -- ESX calls the cash account 'money'; the rest of the bridge calls it 'cash'.
        money.cash = money.cash or money.money or 0
        money.bank = money.bank or 0
        data.money = money
    end

    if type(data.job) == 'table' and type(data.job.grade) ~= 'table' then
        data.job.grade = {
            level = tonumber(data.job.grade) or 0,
            name = data.job.grade_label or data.job.grade_name or _L('no_job')
        }
    end

    return data
end

--- When the Qbox cache was last filled from the server.
---
--- The callback below used to run on EVERY call, synchronously. GetPlayerData,
--- GetJob and GetGang all route through here, and the 500ms medical loop calls
--- them more than once a cycle -- roughly six server round trips per player per
--- second, about 600/s at a hundred players, for data that only changes on
--- discrete lifecycle events.
---
--- Those events are already handled further down and patch PlayerData in place,
--- so they remain the mechanism. This TTL is only the safety net for anything
--- they miss.
local PlayerDataFetchedAt = 0
local PLAYER_DATA_TTL_MS = 2000

--- Forces the next read to go back to the server.
local function invalidatePlayerData()
    PlayerDataFetchedAt = 0
end

local function refreshPlayerData()
    if RSBridge.Framework == 'qbox' then
        -- qbx_core does not expose a client GetPlayerData export. Prefer the
        -- optional QBX module when a Qbox resource imported it; otherwise seed
        -- our local cache from the bridge's own server callback.
        if QBX and type(QBX.PlayerData) == 'table' and next(QBX.PlayerData) then
            PlayerData = QBX.PlayerData
            return PlayerData
        end

        local now = GetGameTimer()
        if next(PlayerData) ~= nil and (now - PlayerDataFetchedAt) < PLAYER_DATA_TTL_MS then
            return PlayerData
        end

        if lib and lib.callback then
            local ok, data = RSBridge.safeCall(function()
                return lib.callback.await('rs_bridge:server:getPlayerData', false)
            end)
            if ok and type(data) == 'table' then
                PlayerData = data
                PlayerDataFetchedAt = now
            end
        end
        return PlayerData
    end

    if RSBridge.Framework == 'qbcore' and RSBridge.Core and RSBridge.Core.Functions then
        local ok, data = RSBridge.safeCall(function()
            return RSBridge.Core.Functions.GetPlayerData()
        end)
        PlayerData = ok and data or PlayerData
        return PlayerData
    end

    if RSBridge.Framework == 'esx' then
        local ESX = getESX()
        if ESX and ESX.GetPlayerData then
            local ok, data = RSBridge.safeCall(function()
                return ESX.GetPlayerData()
            end)
            PlayerData = ok and normalizeESX(data) or PlayerData
        end
        return PlayerData
    end

    return PlayerData
end

function GetPlayerData()
    return refreshPlayerData()
end

function GetJob()
    local data = refreshPlayerData()
    local job = data.job or {}
    return {
        name = job.name or 'unemployed',
        label = job.label or _L('unemployed'),
        grade = job.grade or { level = job.grade or 0, name = job.grade_label or _L('no_job') },
        onduty = job.onduty ~= false
    }
end

function GetGang()
    local data = refreshPlayerData()
    return data.gang or { name = 'none', label = _L('no_gang'), grade = { level = 0, name = _L('no_gang') } }
end

function Notify(message, notifyType, duration, title)
    notifyType = notifyType or RSBridgeConfig.Notify.DefaultType
    duration = duration or RSBridgeConfig.Notify.DefaultDuration
    title = title or _L('default_notify_title')

    if (RSBridgeConfig.Notify.Provider == 'auto' or RSBridgeConfig.Notify.Provider == 'ox_lib') and lib and lib.notify then
        local oxType = notifyType == 'primary' and 'inform' or notifyType
        lib.notify({
            title = title,
            description = message,
            type = oxType,
            duration = duration
        })
        return true
    end

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local ok = RSBridge.safeCall(function()
            local qboxType = notifyType == 'primary' and 'inform' or notifyType
            exports.qbx_core:Notify(message, qboxType, duration)
        end)
        if ok then return true end
    end

    if RSBridge.Framework == 'qbcore' and RSBridge.Core and RSBridge.Core.Functions and RSBridge.Core.Functions.Notify then
        local qbType = notifyType == 'inform' and 'primary' or notifyType
        RSBridge.Core.Functions.Notify(message, qbType, duration)
        return true
    end

    if RSBridge.Framework == 'esx' then
        TriggerEvent('esx:showNotification', message)
        return true
    end

    TriggerEvent('chat:addMessage', { args = { title, message } })
    return true
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', refreshPlayerData)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PlayerData = {}
    invalidatePlayerData()
end)
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerData.job = job
    invalidatePlayerData()
end)
RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang)
    PlayerData.gang = gang
    invalidatePlayerData()
end)
RegisterNetEvent('qbx_core:client:playerLoggedOut', function() PlayerData = {} end)
RegisterNetEvent('qbx_core:client:onGroupUpdate', function(groupName, groupGrade)
    PlayerData.groups = PlayerData.groups or {}
    if groupGrade == nil then PlayerData.groups[groupName] = nil else PlayerData.groups[groupName] = groupGrade end
end)
RegisterNetEvent('QBCore:Client:OnMoneyChange', function(moneyType, amount)
    PlayerData.money = PlayerData.money or {}
    PlayerData.money[moneyType] = amount
end)

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    PlayerData = xPlayer and normalizeESX(xPlayer) or refreshPlayerData()
end)

-- Keeps money.cash / money.bank current on ESX, which otherwise only changes
-- the underlying accounts array.
RegisterNetEvent('esx:setAccountMoney', function(account)
    if type(account) ~= 'table' or not account.name then return end
    PlayerData.money = PlayerData.money or {}
    PlayerData.money[account.name] = account.money or 0
    if account.name == 'money' then
        PlayerData.money.cash = account.money or 0
    end
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    PlayerData = {}
end)

RegisterNetEvent('esx:setJob', function(job)
    if type(job) == 'table' and type(job.grade) ~= 'table' then
        job.grade = {
            level = tonumber(job.grade) or 0,
            name = job.grade_label or job.grade_name or _L('no_job')
        }
    end
    PlayerData.job = job
end)

RegisterNetEvent('rs_bridge:client:notify', function(message, notifyType, duration, title)
    Notify(message, notifyType, duration, title)
end)

-- =====================================================================
-- Vehicle spawn-name resolution
--
-- Resources that key artwork or data by spawn name cannot get it reliably
-- from the game on GTA V Enhanced:
--   * GetEntityArchetypeName frequently answers empty for DLC/addon vehicles
--   * GetDisplayNameFromVehicleModel returns a GXT LABEL, not the spawn code
--     -- 'polcoquette4' reports as 'COQUET4', which matches no asset
--
-- GetAllVehicleModels() is the authoritative list of every vehicle model the
-- client knows, addons and DLC included. Hashing it once gives an exact
-- reverse map. The framework registry is consulted as a fallback for anything
-- the server registered but the client has not enumerated.
-- =====================================================================

local vehicleNameCache
local vehicleCacheRebuilt = false

--- Model hashes arrive as signed ints from some natives and unsigned from
--- others. Normalise so both index the same bucket.
local function normalizeHash(value)
    local hash = tonumber(value)
    if not hash then return nil end
    hash = math.floor(hash)
    if hash < 0 then hash = hash + 4294967296 end
    return hash
end

local function buildVehicleNameCache()
    local map, count = {}, 0
    local ok, models = pcall(GetAllVehicleModels)
    if ok and type(models) == 'table' then
        for i = 1, #models do
            local name = models[i]
            if type(name) == 'string' and name ~= '' then
                local key = normalizeHash(joaat(name))
                if key then
                    map[key] = name:lower()
                    count = count + 1
                end
            end
        end
    end
    vehicleNameCache = map
    RSBridge.debug(('vehicle name cache built: %d models'):format(count))
    return map
end

local function frameworkVehicleName(hash)
    if RSBridge.Framework == 'qbox' then
        local ok, list = pcall(function() return exports.qbx_core:GetVehiclesByHash() end)
        if ok and type(list) == 'table' then
            for key, entry in pairs(list) do
                if normalizeHash(key) == hash and type(entry) == 'table' then
                    local model = entry.model or entry.spawncode or entry.name
                    if type(model) == 'string' and model ~= '' then return model:lower() end
                end
            end
        end
    elseif RSBridge.Framework == 'qbcore' and RSBridge.Core and RSBridge.Core.Shared then
        local vehicles = RSBridge.Core.Shared.Vehicles
        if type(vehicles) == 'table' then
            for spawn, data in pairs(vehicles) do
                if type(spawn) == 'string' and normalizeHash(joaat(spawn)) == hash then
                    return spawn:lower()
                end
                if type(data) == 'table' and normalizeHash(data.hash) == hash then
                    return tostring(data.model or spawn):lower()
                end
            end
        end
    end
    return nil
end

--- Resolve a vehicle model hash to its spawn name (e.g. 'polcoquette4').
--- @param hash number model hash, signed or unsigned
--- @return string|nil spawnName lowercase, or nil if unknown
local function GetVehicleModelName(hash)
    local key = normalizeHash(hash)
    if not key then return nil end

    local map = vehicleNameCache or buildVehicleNameCache()
    local name = map[key]
    if name then return name end

    -- The very first call can land before every archetype has registered.
    -- Allow exactly one rebuild for the session, so an unknown hash queried
    -- repeatedly does not re-hash the whole model list every frame.
    if not vehicleCacheRebuilt then
        vehicleCacheRebuilt = true
        name = buildVehicleNameCache()[key]
        if name then return name end
    end

    return frameworkVehicleName(key)
end

RSBridge.GetVehicleModelName = GetVehicleModelName

exports('GetPlayerData', GetPlayerData)
exports('GetJob', GetJob)
exports('GetGang', GetGang)
exports('Notify', Notify)
exports('GetVehicleModelName', GetVehicleModelName)

-- QBCore:Notify compatibility forwarder.
--
-- Qbox registers this event itself (qbx_core/client/events.lua) and qb-core
-- does too, so on those frameworks it already works. ESX and standalone do NOT,
-- which means any resource that fires TriggerEvent('QBCore:Notify', ...) or
-- TriggerClientEvent('QBCore:Notify', src, ...) shows the player nothing at all.
-- Several RS resources still do exactly that as their fallback path.
--
-- Registering a forwarder ONLY when no framework owns the event keeps those
-- notifications working everywhere without editing a single call site -- and
-- avoids a double notification on Qbox/QBCore, where registering it here as
-- well would fire the handler twice.
--- Registered lazily, and only while no framework owns the event.
---
--- The first version of this waited for `RSBridge.Framework == nil`, but that is
--- never nil -- shared/main.lua seeds it to 'standalone' at load. The loop
--- therefore exited immediately, saw 'standalone', and claimed the event about a
--- second BEFORE Qbox was detected, so qbx_core and this both handled it and
--- every notification fired twice.
---
--- Detection is asynchronous, so instead of guessing a settle time the handler
--- itself re-checks the CURRENT framework each time it fires. If a framework has
--- since resolved and owns the event, this forwarder does nothing and the
--- framework's own handler is left to do the work.
local qbNotifyForwarderReady = false

local function frameworkOwnsQBNotify()
    return RSBridge.Framework == 'qbox' or RSBridge.Framework == 'qbcore'
end

CreateThread(function()
    -- Give detection a chance to finish before registering at all, so the common
    -- case never installs a handler it does not need.
    local deadline = GetGameTimer() + 15000
    while not frameworkOwnsQBNotify() and GetGameTimer() < deadline do
        Wait(250)
    end

    if frameworkOwnsQBNotify() then
        RSBridge.debug('QBCore:Notify forwarder not needed; framework owns the event')
        return
    end

    qbNotifyForwarderReady = true

    RegisterNetEvent('QBCore:Notify', function(text, notifyType, duration)
        -- Re-check at fire time: a framework may have resolved after this was
        -- registered, and a duplicate notification is worse than none.
        if not qbNotifyForwarderReady or frameworkOwnsQBNotify() then return end
        if text == nil or text == '' then return end
        Notify(text, notifyType, duration)
    end)

    RSBridge.debug('QBCore:Notify forwarder active (no framework owns the event)')
end)
