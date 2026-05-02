local PlayerData = {}

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

    return PlayerData
end

function GetPlayerData()
    return refreshPlayerData()
end

function GetJob()
    local data = refreshPlayerData()
    return data.job or { name = 'unemployed', label = 'Unemployed', grade = { level = 0, name = 'None' }, onduty = false }
end

function GetGang()
    local data = refreshPlayerData()
    return data.gang or { name = 'none', label = 'None', grade = { level = 0, name = 'None' } }
end

function Notify(message, notifyType, duration, title)
    notifyType = notifyType or RSBridgeConfig.Notify.DefaultType
    duration = duration or RSBridgeConfig.Notify.DefaultDuration
    title = title or RSBridgeConfig.Notify.DefaultTitle

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

    TriggerEvent('chat:addMessage', {
        args = { title, message }
    })
    return true
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    refreshPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PlayerData = {}
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerData.job = job
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang)
    PlayerData.gang = gang
end)

RegisterNetEvent('rs_bridge:client:notify', function(message, notifyType, duration, title)
    Notify(message, notifyType, duration, title)
end)

exports('GetPlayerData', GetPlayerData)
exports('GetJob', GetJob)
exports('GetGang', GetGang)
exports('Notify', Notify)
