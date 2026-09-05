local cachedProvider

local function resolveCashProvider()
    local configured = (RSBridgeConfig.Cash and RSBridgeConfig.Cash.Provider) or 'auto'
    if configured ~= 'auto' then return configured end

    -- Do not infer cash-as-item merely from the inventory provider. Many servers
    -- use ox_inventory while keeping physical cash in framework money.
    return RSBridge.Framework == 'standalone' and 'none' or 'framework'
end

local function cashItemName()
    -- Qbox calls the account "cash", while ox_inventory exposes that same
    -- synchronized balance as the "money" item.
    return (RSBridgeConfig.Cash and RSBridgeConfig.Cash.Item) or 'money'
end

function GetCashProvider()
    cachedProvider = cachedProvider or resolveCashProvider()
    return cachedProvider
end

function GetCash(src)
    local provider = GetCashProvider()

    if provider == 'inventory_item' then
        return tonumber(GetItemCount(src, cashItemName())) or 0
    end

    if provider == 'framework' then
        return tonumber(GetMoney(src, 'cash')) or 0
    end

    return 0
end

function CanReceiveCash(src, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end

    local provider = GetCashProvider()
    if provider == 'inventory_item' then
        return CanCarryItem(src, cashItemName(), amount) == true
    end

    return provider == 'framework'
end

function AddCash(src, amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end

    local provider = GetCashProvider()
    if provider == 'inventory_item' then
        if not CanReceiveCash(src, amount) then return false end

        -- Cash must remain metadata-free. The transaction reason belongs in the
        -- banking ledger; putting it on the item can split stacks and make later
        -- removals fail metadata matching in inventories such as ox_inventory.
        local added = AddItem(src, cashItemName(), amount, nil, nil) == true
        -- Only the item path is audited here. The framework path below routes
        -- through AddMoney, which audits itself, so logging both would double up.
        RSBridge.safeCall(function()
            Audit('money', { title = 'Cash added (item)', actor = src, amount = amount,
                account = cashItemName(), reason = reason or 'rs_bridge:cash', ok = added,
                resource = GetInvokingResource() or 'rs_bridge' })
        end)
        return added
    end

    if provider == 'framework' then
        return AddMoney(src, 'cash', amount, reason or 'rs_bridge:cash') == true
    end

    return false
end

function RemoveCash(src, amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 or GetCash(src) < amount then return false end

    local provider = GetCashProvider()
    if provider == 'inventory_item' then
        local removed = RemoveItem(src, cashItemName(), amount, nil, nil) == true
        RSBridge.safeCall(function()
            Audit('money', { title = 'Cash removed (item)', actor = src, amount = amount,
                account = cashItemName(), reason = reason or 'rs_bridge:cash', ok = removed,
                resource = GetInvokingResource() or 'rs_bridge' })
        end)
        return removed
    end

    if provider == 'framework' then
        return RemoveMoney(src, 'cash', amount, reason or 'rs_bridge:cash') == true
    end

    return false
end

exports('GetCashProvider', GetCashProvider)
exports('GetCash', GetCash)
exports('CanReceiveCash', CanReceiveCash)
exports('AddCash', AddCash)
exports('RemoveCash', RemoveCash)
