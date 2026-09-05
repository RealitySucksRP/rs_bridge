local function resolveBankingProvider()
    local configured = (RSBridgeConfig.Banking and RSBridgeConfig.Banking.Provider) or 'auto'
    if configured ~= 'auto' then return configured end
    return RSBridge.resourceStarted('rs-banking') and 'rs-banking' or 'framework'
end

function GetBankingProvider()
    -- Re-resolve so starting/stopping rs-banking switches cleanly without a bridge restart.
    return resolveBankingProvider()
end

local function providerSuccess(value)
    return value == true or (type(value) == 'table' and value.success == true)
end

local function bankingUnavailable(operation, err)
    RSBridge.debug(('banking provider failed during %s: %s'):format(operation, tostring(err or 'unknown error')))
end

--[[
    RE-ENTRANCY GUARD

    Every function below can hand a call to the configured banking provider. If
    that call ORIGINATED inside the provider, handing it back re-enters the
    provider, which calls the bridge, which calls the provider, until the server
    runs out of stack. The player sees a hang rather than an error, and the
    stack trace names the bridge instead of whoever actually started it.

    rs-banking as shipped never calls back into these -- RSBanking.addBank goes
    to AddMoney, not AddBankMoney -- so on this server the guard never fires.
    It exists for the servers this ships to: a different banking provider, or a
    future rs-banking that routes an internal credit through the bridge, must
    not be able to lock up a server whose owner has no way to diagnose it.

    On re-entry the call falls through to the framework path, which cannot
    re-enter and therefore always terminates.

    The flag is keyed PER COROUTINE rather than being one module-level boolean.
    Provider calls yield -- rs-banking awaits MySQL on every write -- and during
    that yield FiveM will run another player's call on a different coroutine. A
    shared flag would still be set, so that unrelated player would be silently
    diverted to the framework path and their money written through the wrong
    system. Keying by coroutine scopes the guard to a single call stack, which
    is the only thing that can actually recurse.
]]
local providerDispatch = setmetatable({}, { __mode = 'k' })

local function dispatchKey()
    local co = coroutine.running()
    return co or 'main'
end

local function beginDispatch(operation, provider)
    local key = dispatchKey()
    if providerDispatch[key] then
        RSBridge.debug(('banking: refusing re-entrant %s into %s (called from %s); using framework path')
            :format(operation, tostring(provider), tostring(GetInvokingResource() or 'unknown')))
        return false
    end
    providerDispatch[key] = true
    return true
end

local function endDispatch()
    providerDispatch[dispatchKey()] = nil
end

function GetBankBalance(src)
    local provider = GetBankingProvider()
    if provider == 'rs-banking' and beginDispatch('GetBankBalance', provider) then
        local ok, value = RSBridge.safeCall(function()
            return exports['rs-banking']:GetBankBalance(src)
        end)
        endDispatch()

        if ok and value ~= nil then return tonumber(value) or 0 end
        bankingUnavailable('GetBankBalance', value)
        return 0
    end

    return tonumber(GetMoney(src, 'bank')) or 0
end

function AddBankMoney(src, amount, reason, context)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end

    local provider = GetBankingProvider()
    if provider == 'rs-banking' and beginDispatch('AddBankMoney', provider) then
        -- Resolved out here rather than inside the closure: this is the resource
        -- that called the export, and reading it at entry keeps it accurate no
        -- matter how the call below is wrapped.
        local invoker = GetInvokingResource() or 'unknown'
        local ok, value = RSBridge.safeCall(function()
            return exports['rs-banking']:CreditPlayer(src, {
                amount = amount,
                reason = reason or 'External credit',
                category = context and context.category,
                metadata = context,
                sourceResource = invoker
            })
        end)
        endDispatch()

        if not ok then bankingUnavailable('AddBankMoney', value) return false end
        return providerSuccess(value)
    end

    return AddMoney(src, 'bank', amount, reason or 'rs_bridge:bank') == true
end

function RemoveBankMoney(src, amount, reason, context)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end

    local provider = GetBankingProvider()
    if provider == 'rs-banking' and beginDispatch('RemoveBankMoney', provider) then
        local invoker = GetInvokingResource() or 'unknown'
        local ok, value = RSBridge.safeCall(function()
            return exports['rs-banking']:ChargePlayer(src, {
                amount = amount,
                paymentMethod = 'bank',
                description = reason or 'External charge',
                category = context and context.category,
                metadata = context,
                sourceResource = invoker
            })
        end)
        endDispatch()

        if not ok then bankingUnavailable('RemoveBankMoney', value) return false end
        return providerSuccess(value)
    end

    return RemoveMoney(src, 'bank', amount, reason or 'rs_bridge:bank') == true
end

function ChargePlayer(src, payload)
    payload = type(payload) == 'table' and payload or { amount = payload }

    local provider = GetBankingProvider()
    if provider == 'rs-banking' and beginDispatch('ChargePlayer', provider) then
        local ok, value = RSBridge.safeCall(function()
            return exports['rs-banking']:ChargePlayer(src, payload)
        end)
        endDispatch()

        if ok then return value end
        bankingUnavailable('ChargePlayer', value)
        return { success = false, error = 'Banking provider unavailable.' }
    end

    local amount = tonumber(payload.amount) or 0
    if amount <= 0 then return { success = false, error = 'Invalid amount.' } end

    if payload.paymentMethod == 'cash' then
        return { success = RemoveCash(src, amount, payload.description or 'purchase') == true }
    end

    return { success = RemoveMoney(src, 'bank', amount, payload.description or 'purchase') == true }
end

function CreditPlayer(src, payload)
    payload = type(payload) == 'table' and payload or { amount = payload }

    local provider = GetBankingProvider()
    if provider == 'rs-banking' and beginDispatch('CreditPlayer', provider) then
        local ok, value = RSBridge.safeCall(function()
            return exports['rs-banking']:CreditPlayer(src, payload)
        end)
        endDispatch()

        if ok then return value end
        bankingUnavailable('CreditPlayer', value)
        return { success = false, error = 'Banking provider unavailable.' }
    end

    local amount = tonumber(payload.amount) or 0
    if amount <= 0 then return { success = false, error = 'Invalid amount.' } end

    return {
        success = AddMoney(src, 'bank', amount, payload.reason or 'credit') == true
    }
end

exports('GetBankingProvider', GetBankingProvider)
exports('GetBankBalance', GetBankBalance)
exports('AddBankMoney', AddBankMoney)
exports('RemoveBankMoney', RemoveBankMoney)
exports('ChargePlayer', ChargePlayer)
exports('CreditPlayer', CreditPlayer)
