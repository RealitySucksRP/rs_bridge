RSBridge = RSBridge or {}
RSBridge.Framework = 'standalone'
RSBridge.Core = nil
RSBridge.Ready = false

local function detectFramework()
    local forced = RSBridgeConfig.Framework or 'auto'

    if forced == 'standalone' then
        RSBridge.Framework = 'standalone'
        RSBridge.Core = nil
        return
    end

    if (forced == 'auto' or forced == 'qbox') and RSBridge.resourceStarted('qbx_core') then
        RSBridge.Framework = 'qbox'
        RSBridge.Core = nil
        return
    end

    if (forced == 'auto' or forced == 'qbcore') and RSBridge.resourceStarted('qb-core') then
        RSBridge.Framework = 'qbcore'
        local ok, core = RSBridge.safeCall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok then RSBridge.Core = core end
        return
    end

    RSBridge.Framework = 'standalone'
    RSBridge.Core = nil
end

CreateThread(function()
    Wait(250)
    detectFramework()
    RSBridge.Ready = true
    RSBridge.debug(('Framework detected: %s'):format(RSBridge.Framework))
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'qbx_core' or resource == 'qb-core' or resource == GetCurrentResourceName() then
        Wait(250)
        detectFramework()
        RSBridge.Ready = true
        RSBridge.debug(('Framework refreshed: %s'):format(RSBridge.Framework))
    end
end)

function GetFramework()
    return RSBridge.Framework
end

function IsQBCore()
    return RSBridge.Framework == 'qbcore'
end

function IsQbox()
    return RSBridge.Framework == 'qbox'
end

function IsStandalone()
    return RSBridge.Framework == 'standalone'
end

function GetCoreObject()
    return RSBridge.Core
end

exports('GetFramework', GetFramework)
exports('IsQBCore', IsQBCore)
exports('IsQbox', IsQbox)
exports('IsStandalone', IsStandalone)
exports('GetCoreObject', GetCoreObject)
