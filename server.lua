local framework = 'standalone'
local QBCore = nil

CreateThread(function()
    Wait(200)
    if GetResourceState('qbx_core') == 'started' then
        framework = 'qbox'
    elseif GetResourceState('qb-core') == 'started' then
        framework = 'qbcore'
        QBCore = exports['qb-core']:GetCoreObject()
    end
end)

function GetPlayer(src)
    if framework == 'qbox' then
        return exports.qbx_core:GetPlayer(src)
    end
    if framework == 'qbcore' then
        return QBCore.Functions.GetPlayer(src)
    end
    return nil
end

function AddMoney(src, type, amount)
    local Player = GetPlayer(src)
    if Player and Player.Functions then
        return Player.Functions.AddMoney(type or 'cash', amount)
    end
end

function AddItem(src, item, amount)
    local Player = GetPlayer(src)
    if Player and Player.Functions then
        return Player.Functions.AddItem(item, amount or 1)
    end
end
