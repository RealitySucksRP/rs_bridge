--[[
    rs_bridge -- /cashaudit (SERVER, read-only diagnostic)

    This server runs TWO cash representations at once and it is not currently
    possible to tell from code alone whether a reported "duplicate" is a real
    balance increase or the same value being visible in two places:

      1. the `money` item, which ox_inventory keeps synced BOTH ways with the
         qbx `cash` account (item count is authoritative on inventory change,
         account writes back to the item on money change), and
      2. the `cash` item, which rs_bridge uses for RS physical cash and which is
         NOT linked to any account.

    This command prints all of them side by side so the question can be answered
    by looking rather than by reasoning. Purely read-only: it never writes an
    item, a balance, or a database row.

        /cashaudit          -- inspect yourself
        /cashaudit <id>     -- inspect another player (requires the admin ace)
]]

local function itemCount(src, item)
    if GetResourceState('ox_inventory') ~= 'started' then return nil end
    local ok, count = RSBridge.safeCall(function()
        return exports.ox_inventory:Search(src, 'count', item)
    end)
    if not ok then return nil end
    return tonumber(count) or 0
end

local function accountBalance(src, account)
    local ok, value = RSBridge.safeCall(function()
        return exports.qbx_core:GetMoney(src, account)
    end)
    if not ok then return nil end
    return tonumber(value)
end

local function report(target, emit)
    local name = GetPlayerName(target) or ('source ' .. tostring(target))
    local accountsConvar = GetConvar('inventory:accounts', '["money"]')

    local cashAccount = accountBalance(target, 'cash')
    local bankAccount = accountBalance(target, 'bank')
    local moneyItem = itemCount(target, 'money')
    local cashItem = itemCount(target, 'cash')

    local bridgeCash
    local okBridge, value = RSBridge.safeCall(function() return GetCash(target) end)
    if okBridge then bridgeCash = tonumber(value) end

    emit(('--- cash audit: %s (%s) ---'):format(name, tostring(target)))
    emit(('  inventory:accounts convar : %s'):format(accountsConvar))
    emit(('  rs_bridge cash provider   : %s (item "%s")')
        :format(tostring(GetCashProvider and GetCashProvider() or '?'),
            tostring(RSBridgeConfig and RSBridgeConfig.Cash and RSBridgeConfig.Cash.Item or '?')))
    emit('')
    emit(('  qbx account "cash"        : %s'):format(cashAccount ~= nil and tostring(cashAccount) or 'unavailable'))
    emit(('  qbx account "bank"        : %s'):format(bankAccount ~= nil and tostring(bankAccount) or 'unavailable'))
    emit(('  ox item "money"           : %s'):format(moneyItem ~= nil and tostring(moneyItem) or 'unavailable'))
    emit(('  ox item "cash"            : %s'):format(cashItem ~= nil and tostring(cashItem) or 'unavailable'))
    emit(('  rs_bridge GetCash()       : %s'):format(bridgeCash ~= nil and tostring(bridgeCash) or 'unavailable'))
    emit('')

    -- The interpretation, stated explicitly, so the answer does not depend on
    -- remembering how the two systems relate.
    if cashAccount ~= nil and moneyItem ~= nil then
        if cashAccount == moneyItem then
            emit('  account vs money item     : IN SYNC (expected)')
        else
            emit(('  account vs money item     : *** DRIFT of %s *** - the two-way sync is not holding')
                :format(tostring(math.abs(cashAccount - moneyItem))))
        end
    end
    if cashItem ~= nil and cashItem > 0 then
        emit(('  NOTE: %s "cash" item(s) are held OUTSIDE the account. That value is'):format(tostring(cashItem)))
        emit('        real and spendable in RS resources but invisible to the qbx')
        emit('        balance and to any shop that reads the account.')
    end
    emit('  Run this before and after the action that appears to duplicate.')
    emit('  If the TOTAL rises, it is a real dupe. If only the split changes, it is two wallets.')
    emit('---')
end

RegisterCommand('cashaudit', function(source, args)
    local target = source

    if args and args[1] then
        local requested = tonumber(args[1])
        if not requested then return end
        -- Inspecting someone else exposes their balances, so gate that on admin
        -- while self-inspection stays open.
        if source ~= 0 and requested ~= source and not IsPlayerAceAllowed(source, 'admin') then
            if source > 0 then
                TriggerClientEvent('chat:addMessage', source,
                    { color = { 255, 100, 100 }, args = { 'cashaudit', 'You may only audit yourself.' } })
            end
            return
        end
        target = requested
    end

    if target == 0 then
        print('[cashaudit] specify a player id when running from the console.')
        return
    end
    if not GetPlayerName(target) then
        if source > 0 then
            TriggerClientEvent('chat:addMessage', source,
                { color = { 255, 100, 100 }, args = { 'cashaudit', 'That player is not online.' } })
        else
            print('[cashaudit] that player is not online.')
        end
        return
    end

    report(target, function(line)
        print(('^5[cashaudit]^7 %s'):format(line))
        if source > 0 then
            TriggerClientEvent('chat:addMessage', source,
                { color = { 120, 200, 255 }, args = { 'cashaudit', line } })
        end
    end)
end, false)
