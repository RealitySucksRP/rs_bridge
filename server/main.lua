local function ensureQB()
    if RSBridge.Framework ~= 'qbcore' then return nil end
    if not RSBridge.Core and RSBridge.resourceStarted('qb-core') then
        local ok, core = RSBridge.safeCall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok then RSBridge.Core = core end
    end
    return RSBridge.Core
end

local function ensureESX()
    if RSBridge.Framework ~= 'esx' then return nil end
    if RSBridge.Core then return RSBridge.Core end

    if RSBridge.resourceStarted('es_extended') then
        local ok, esx = RSBridge.safeCall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok and esx then RSBridge.Core = esx end
    end

    return RSBridge.Core
end

function GetPlayer(src)
    src = tonumber(src)
    if not src then return nil end

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local ok, player = RSBridge.safeCall(function()
            return exports.qbx_core:GetPlayer(src)
        end)
        if ok then return player end
    end

    if RSBridge.Framework == 'qbcore' then
        local QBCore = ensureQB()
        if QBCore and QBCore.Functions then
            return QBCore.Functions.GetPlayer(src)
        end
    end

    if RSBridge.Framework == 'esx' then
        local ESX = ensureESX()
        if ESX and ESX.GetPlayerFromId then
            return ESX.GetPlayerFromId(src)
        end
    end

    return nil
end

local function esxGet(xPlayer, key)
    if not xPlayer then return nil end
    -- ESX Legacy stores some fields in xPlayer.variables
    if xPlayer.variables and xPlayer.variables[key] ~= nil then
        return xPlayer.variables[key]
    end
    -- Some forks expose fields as direct keys on xPlayer
    if xPlayer[key] ~= nil and type(xPlayer[key]) ~= 'function' then
        return xPlayer[key]
    end
    -- Old ESX 1.2 and below had a generic get(key) function
    if type(xPlayer.get) == 'function' then
        local ok, value = pcall(xPlayer.get, xPlayer, key)
        if ok then return value end
    end
    return nil
end

local function normalizeESXPlayerData(src, xPlayer)
    local job = xPlayer and xPlayer.job or {}
    local identifier = nil
    if xPlayer then
        identifier = xPlayer.identifier
        if not identifier and type(xPlayer.getIdentifier) == 'function' then
            local ok, value = pcall(xPlayer.getIdentifier, xPlayer)
            if ok then identifier = value end
        end
    end

    return {
        source = src,
        citizenid = identifier,
        identifier = identifier,
        charinfo = {
            firstname = esxGet(xPlayer, 'firstName') or esxGet(xPlayer, 'firstname'),
            lastname = esxGet(xPlayer, 'lastName') or esxGet(xPlayer, 'lastname')
        },
        job = {
            name = job.name or 'unemployed',
            label = job.label or _L('unemployed'),
            grade = {
                level = job.grade or 0,
                name = job.grade_label or job.grade_name or _L('no_job')
            },
            onduty = true
        },
        gang = { name = 'none', label = _L('no_gang'), grade = { level = 0, name = _L('no_gang') } },
        money = {
            cash = xPlayer and xPlayer.getMoney and xPlayer.getMoney() or 0,
            bank = xPlayer and xPlayer.getAccount and ((xPlayer.getAccount('bank') or {}).money or 0) or 0
        },
        metadata = {}
    }
end

function GetPlayerData(src)
    local player = GetPlayer(src)

    if RSBridge.Framework == 'esx' then
        return normalizeESXPlayerData(src, player)
    end

    if player and player.PlayerData then return player.PlayerData end

    return {
        source = src,
        citizenid = nil,
        charinfo = {},
        job = { name = 'unemployed', label = _L('unemployed'), grade = { level = 0, name = _L('no_job') }, onduty = false },
        gang = { name = 'none', label = _L('no_gang'), grade = { level = 0, name = _L('no_gang') } },
        money = { cash = 0, bank = 0, crypto = 0 },
        metadata = {}
    }
end

function GetCitizenId(src)
    local data = GetPlayerData(src)
    return data.citizenid or data.citizenId or data.identifier
end

function GetCharInfo(src)
    return GetPlayerData(src).charinfo or {}
end

function GetJob(src)
    return GetPlayerData(src).job or { name = 'unemployed', grade = { level = 0 } }
end

function GetGang(src)
    return GetPlayerData(src).gang or { name = 'none', grade = { level = 0 } }
end

function HasJob(src, jobNames, minGrade)
    local job = GetJob(src)
    local names = RSBridge.toNameList(jobNames)
    if #names > 0 and not RSBridge.tableHasValue(names, job.name) then return false end

    minGrade = tonumber(minGrade or 0) or 0
    return RSBridge.gradeLevel(job.grade) >= minGrade
end

function HasGroup(src, groupNames, minGrade)
    local names = RSBridge.toNameList(groupNames)

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        for _, group in ipairs(names) do
            local ok, result = RSBridge.safeCall(function()
                return exports.qbx_core:HasGroup(src, group, minGrade or 0)
            end)
            if ok and result then return true end
        end
    end

    if RSBridge.Framework == 'esx' then
        local xPlayer = GetPlayer(src)
        local group = xPlayer and xPlayer.getGroup and xPlayer.getGroup() or nil
        if group and RSBridge.tableHasValue(names, group) then return true end
    end

    return HasJob(src, groupNames, minGrade)
end

function GetMoney(src, account)
    account = account or 'cash'
    local player = GetPlayer(src)
    if not player then return 0 end

    if RSBridge.Framework == 'esx' then
        if account == 'cash' or account == 'money' then
            return player.getMoney and player.getMoney() or 0
        end
        local acc = player.getAccount and player.getAccount(account)
        return acc and acc.money or 0
    end

    if player.Functions and player.Functions.GetMoney then
        return player.Functions.GetMoney(account) or 0
    end

    local data = player.PlayerData or {}
    return data.money and data.money[account] or 0
end

function AddMoney(src, account, amount, reason)
    account = account or 'cash'
    amount = tonumber(amount) or 0
    local player = GetPlayer(src)
    if not player or amount <= 0 then return false end

    if RSBridge.Framework == 'esx' then
        if account == 'cash' or account == 'money' then
            if player.addMoney then player.addMoney(amount) return true end
        elseif player.addAccountMoney then
            player.addAccountMoney(account, amount, reason or 'rs_bridge')
            return true
        end
        return false
    end

    if player.Functions and player.Functions.AddMoney then
        return player.Functions.AddMoney(account, amount, reason or 'rs_bridge')
    end

    return false
end

function RemoveMoney(src, account, amount, reason)
    account = account or 'cash'
    amount = tonumber(amount) or 0
    local player = GetPlayer(src)
    if not player or amount <= 0 then return false end

    if RSBridge.Framework == 'esx' then
        if account == 'cash' or account == 'money' then
            if player.removeMoney then player.removeMoney(amount) return true end
        elseif player.removeAccountMoney then
            player.removeAccountMoney(account, amount, reason or 'rs_bridge')
            return true
        end
        return false
    end

    if player.Functions and player.Functions.RemoveMoney then
        return player.Functions.RemoveMoney(account, amount, reason or 'rs_bridge')
    end

    return false
end

function SetMoney(src, account, amount, reason)
    account = account or 'cash'
    amount = tonumber(amount) or 0
    local player = GetPlayer(src)
    if not player or amount < 0 then return false end

    if RSBridge.Framework == 'esx' then
        if account == 'cash' or account == 'money' then
            if player.setMoney then player.setMoney(amount) return true end
        elseif player.setAccountMoney then
            player.setAccountMoney(account, amount, reason or 'rs_bridge')
            return true
        end
        return false
    end

    if player.Functions and player.Functions.SetMoney then
        return player.Functions.SetMoney(account, amount, reason or 'rs_bridge')
    end

    return false
end

function Notify(src, message, notifyType, duration, title)
    src = tonumber(src)
    if not src then return false end

    notifyType = notifyType or RSBridgeConfig.Notify.DefaultType
    duration = duration or RSBridgeConfig.Notify.DefaultDuration

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local ok = RSBridge.safeCall(function()
            exports.qbx_core:Notify(src, message, notifyType, duration)
        end)
        if ok then return true end
    end

    if RSBridge.Framework == 'qbcore' then
        TriggerClientEvent('QBCore:Notify', src, message, notifyType, duration)
        return true
    end

    if RSBridge.Framework == 'esx' then
        TriggerClientEvent('esx:showNotification', src, message)
        return true
    end

    TriggerClientEvent('rs_bridge:client:notify', src, message, notifyType, duration, title)
    return true
end

exports('GetPlayer', GetPlayer)
exports('GetPlayerData', GetPlayerData)
exports('GetCitizenId', GetCitizenId)
exports('GetCharInfo', GetCharInfo)
exports('GetJob', GetJob)
exports('GetGang', GetGang)
exports('HasJob', HasJob)
exports('HasGroup', HasGroup)
exports('GetMoney', GetMoney)
exports('AddMoney', AddMoney)
exports('RemoveMoney', RemoveMoney)
exports('SetMoney', SetMoney)
exports('Notify', Notify)
