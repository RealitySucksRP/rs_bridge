RSBridge = RSBridge or {}
RSBridge.Framework = 'standalone'
RSBridge.Core = nil
RSBridge.Ready = false

local function tryESXLegacy()
    if not RSBridge.resourceStarted('es_extended') then return nil end
    local ok, esx = RSBridge.safeCall(function()
        return exports['es_extended']:getSharedObject()
    end)
    if ok and esx then return esx end
    return nil
end

local function tryESXOld()
    if not RSBridge.resourceStarted('es_extended') then return nil end
    local resolved = nil
    TriggerEvent('esx:getSharedObject', function(obj) resolved = obj end)

    local deadline = GetGameTimer() + 1000
    while not resolved and GetGameTimer() < deadline do Wait(25) end

    return resolved
end

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
        RSBridge.Core = ok and core or nil
        return
    end

    if (forced == 'auto' or forced == 'esx') and RSBridge.resourceStarted('es_extended') then
        RSBridge.Framework = 'esx'
        RSBridge.Core = tryESXLegacy() or tryESXOld()
        if RSBridge.Core then
            RSBridge.debug('ESX shared object resolved')
        else
            RSBridge.debug('ESX detected but shared object was not resolved')
        end
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
    if resource == 'qbx_core'
        or resource == 'qb-core'
        or resource == 'es_extended'
        or resource == GetCurrentResourceName()
    then
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

function IsESX()
    return RSBridge.Framework == 'esx'
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
exports('IsESX', IsESX)
exports('IsStandalone', IsStandalone)
exports('GetCoreObject', GetCoreObject)
