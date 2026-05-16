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

local function refreshPlayerData()
    if RSBridge.Framework == 'qbox' then
        local ok, data = RSBridge.safeCall(function()
            if exports.qbx_core and exports.qbx_core.GetPlayerData then
                return exports.qbx_core:GetPlayerData()
            end
            return QBX and QBX.PlayerData or {}
        end)
        PlayerData = ok and data or PlayerData
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
            PlayerData = ok and data or PlayerData
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
    local grade = job.grade

    -- QB and Qbox return grade as a table { level, name }. ESX returns a bare number.
    -- Normalize so callers can always read job.grade.level safely.
    if type(grade) ~= 'table' then
        grade = {
            level = tonumber(grade) or 0,
            name = job.grade_label or job.grade_name or _L('no_job')
        }
    end

    return {
        name = job.name or 'unemployed',
        label = job.label or _L('unemployed'),
        grade = grade,
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
        lib.notify({
            title = title,
            description = message,
            type = notifyType,
            duration = duration
        })
        return true
    end

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local ok = RSBridge.safeCall(function()
            exports.qbx_core:Notify(message, notifyType, duration)
        end)
        if ok then return true end
    end

    if RSBridge.Framework == 'qbcore' and RSBridge.Core and RSBridge.Core.Functions and RSBridge.Core.Functions.Notify then
        RSBridge.Core.Functions.Notify(message, notifyType, duration)
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
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() PlayerData = {} end)
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) PlayerData.job = job end)
RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang) PlayerData.gang = gang end)

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    PlayerData = xPlayer or refreshPlayerData()
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    PlayerData = {}
end)

RegisterNetEvent('esx:setJob', function(job)
    PlayerData.job = job
end)

RegisterNetEvent('rs_bridge:client:notify', function(message, notifyType, duration, title)
    Notify(message, notifyType, duration, title)
end)

exports('GetPlayerData', GetPlayerData)
exports('GetJob', GetJob)
exports('GetGang', GetGang)
exports('Notify', Notify)
