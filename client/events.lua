-- Normalized player lifecycle events (client).
-- Mirrors server/events.lua. Listen to these instead of framework names:
--
--   rs_bridge:client:playerLoaded    ()
--   rs_bridge:client:playerUnloaded  ()
--   rs_bridge:client:jobUpdate       (job)
--   rs_bridge:client:gangUpdate      (gang)
--   rs_bridge:client:dutyChange      (onDuty)
--   rs_bridge:client:moneyChange     (account, amount, operation)
--   rs_bridge:client:groupUpdate     (groupName, groupGrade)   Qbox only
--   rs_bridge:client:metadataChange  (key, oldValue, newValue)  Qbox only
--
-- moneyChange normalizes to account = 'cash' | 'bank', and operation =
-- 'set' | 'add' | 'remove'. ESX only ever reports absolute balances, so it
-- always arrives as 'set'.

local function emit(name, ...)
    TriggerEvent('rs_bridge:client:' .. name, ...)
end

-- ---------- Qbox / QBCore ----------

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    emit('playerLoaded')
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    emit('playerUnloaded')
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    emit('jobUpdate', job)
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang)
    emit('gangUpdate', gang)
end)

RegisterNetEvent('QBCore:Client:SetDuty', function(onDuty)
    emit('dutyChange', onDuty)
end)

RegisterNetEvent('QBCore:Client:OnMoneyChange', function(moneyType, amount, operation)
    -- Older QB forks pass a boolean isMinus rather than an operation string.
    if type(operation) == 'boolean' then
        operation = operation and 'remove' or 'add'
    end
    emit('moneyChange', moneyType, tonumber(amount) or 0, operation or 'set')
end)

-- ---------- Qbox-native names ----------
--
-- Qbox fires these in addition to the QBCore-named events above. They are not
-- aliases: playerLoggedOut fires when the player leaves qbx_core's memory,
-- which is later than OnPlayerUnload, and group updates have no QBCore
-- equivalent at all.

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    emit('playerUnloaded')
end)

-- groupGrade is nil when the group was removed, set when added.
RegisterNetEvent('qbx_core:client:onGroupUpdate', function(groupName, groupGrade)
    emit('groupUpdate', groupName, groupGrade)
end)

RegisterNetEvent('qbx_core:client:onSetMetaData', function(key, oldValue, newValue)
    emit('metadataChange', key, oldValue, newValue)
end)

-- ---------- ESX ----------

RegisterNetEvent('esx:playerLoaded', function()
    emit('playerLoaded')
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    emit('playerUnloaded')
end)

-- ESX reports the new absolute balance for one account.
RegisterNetEvent('esx:setAccountMoney', function(account)
    if type(account) ~= 'table' or not account.name then return end
    local name = account.name == 'money' and 'cash' or account.name
    emit('moneyChange', name, tonumber(account.money) or 0, 'set')
end)

RegisterNetEvent('esx:setJob', function(job)
    emit('jobUpdate', job and {
        name = job.name,
        label = job.label,
        grade = { level = job.grade, name = job.grade_label or job.grade_name },
        onduty = true
    } or nil)
end)
