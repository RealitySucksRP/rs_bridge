local function useOx()
    if RSBridgeConfig.Inventory.Provider == 'ox_inventory' then return true end
    return RSBridgeConfig.Inventory.Provider == 'auto' and RSBridge.resourceStarted('ox_inventory')
end

function AddItem(src, item, amount, metadata, slot)
    amount = RSBridge.normalizeAmount(amount)

    if useOx() then
        local ok, result = RSBridge.safeCall(function()
            return exports.ox_inventory:AddItem(src, item, amount, metadata, slot)
        end)
        if ok then return result end
    end

    local player = GetPlayer(src)
    if player and player.Functions and player.Functions.AddItem then
        return player.Functions.AddItem(item, amount, slot or false, metadata)
    end

    return false
end

function RemoveItem(src, item, amount, slot, metadata)
    amount = RSBridge.normalizeAmount(amount)

    if useOx() then
        local ok, result = RSBridge.safeCall(function()
            return exports.ox_inventory:RemoveItem(src, item, amount, metadata, slot)
        end)
        if ok then return result end
    end

    local player = GetPlayer(src)
    if player and player.Functions and player.Functions.RemoveItem then
        return player.Functions.RemoveItem(item, amount, slot)
    end

    return false
end

function GetItem(src, item)
    if useOx() then
        local ok, result = RSBridge.safeCall(function()
            return exports.ox_inventory:GetItem(src, item, nil, false)
        end)
        if ok then return result end
    end

    local player = GetPlayer(src)
    if player and player.Functions and player.Functions.GetItemByName then
        return player.Functions.GetItemByName(item)
    end

    return nil
end

function GetItemCount(src, item)
    if useOx() then
        local ok, result = RSBridge.safeCall(function()
            return exports.ox_inventory:Search(src, 'count', item)
        end)
        if ok then return result or 0 end
    end

    local found = GetItem(src, item)
    if not found then return 0 end
    return found.amount or found.count or 0
end

function HasItem(src, item, amount)
    amount = RSBridge.normalizeAmount(amount)
    return GetItemCount(src, item) >= amount
end

function CanCarryItem(src, item, amount, metadata)
    amount = RSBridge.normalizeAmount(amount)

    if useOx() then
        local ok, result = RSBridge.safeCall(function()
            return exports.ox_inventory:CanCarryItem(src, item, amount, metadata)
        end)
        if ok then return result end
    end

    -- qb-inventory generally handles weight inside AddItem; assume true unless custom check exists.
    return true
end

function CreateUseableItem(item, cb)
    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local ok = RSBridge.safeCall(function()
            exports.qbx_core:CreateUseableItem(item, cb)
        end)
        if ok then return true end
    end

    if RSBridge.Framework == 'qbcore' then
        local core = GetCoreObject()
        if core and core.Functions and core.Functions.CreateUseableItem then
            core.Functions.CreateUseableItem(item, cb)
            return true
        end
    end

    RSBridge.debug(('CreateUseableItem skipped for %s; no framework support'):format(item))
    return false
end

exports('AddItem', AddItem)
exports('RemoveItem', RemoveItem)
exports('GetItem', GetItem)
exports('GetItemCount', GetItemCount)
exports('HasItem', HasItem)
exports('CanCarryItem', CanCarryItem)
exports('CreateUseableItem', CreateUseableItem)
