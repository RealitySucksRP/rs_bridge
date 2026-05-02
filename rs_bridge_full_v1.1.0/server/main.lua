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

    return nil
end

function GetPlayerData(src)
    local player = GetPlayer(src)
    if player and player.PlayerData then return player.PlayerData end

    return {
        source = src,
        citizenid = nil,
        charinfo = {},
        job = { name = 'unemployed', label = 'Unemployed', grade = { level = 0, name = 'None' }, onduty = false },
        gang = { name = 'none', label = 'None', grade = { level = 0, name = 'None' } },
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
    if type(jobNames) == 'string' then jobNames = { jobNames } end
    if not RSBridge.tableHasValue(jobNames, job.name) then return false end

    minGrade = tonumber(minGrade or 0) or 0
    local grade = job.grade
    local level = type(grade) == 'table' and (grade.level or grade.grade or 0) or tonumber(grade) or 0
    return level >= minGrade
end

function HasGroup(src, groupNames, minGrade)
    -- For Qbox admin/group checks first
    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local names = type(groupNames) == 'table' and groupNames or { groupNames }
        for _, group in ipairs(names) do
            local ok, result = RSBridge.safeCall(function()
                return exports.qbx_core:HasGroup(src, group, minGrade or 0)
            end)
            if ok and result then return true end
        end
    end

    return HasJob(src, groupNames, minGrade)
end

function GetMoney(src, account)
    account = account or 'cash'
    local player = GetPlayer(src)
    if not player then return 0 end

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
