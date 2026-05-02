local framework = 'standalone'

CreateThread(function()
    Wait(200)
    if GetResourceState('qbx_core') == 'started' then
        framework = 'qbox'
    elseif GetResourceState('qb-core') == 'started' then
        framework = 'qbcore'
    end
end)

function Notify(msg, type, time)
    type = type or 'primary'
    time = time or 5000

    if framework == 'qbox' then
        exports.qbx_core:Notify(msg, type, time)
        return
    end

    if framework == 'qbcore' then
        local QBCore = exports['qb-core']:GetCoreObject()
        QBCore.Functions.Notify(msg, type, time)
        return
    end

    TriggerEvent('chat:addMessage', { args = { 'RS', msg } })
end

exports('Notify', Notify)
