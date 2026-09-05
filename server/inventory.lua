local inventoryOrder = {
    'ox_inventory',
    'qb-inventory',
    'qs-inventory',
    'codem-inventory',
    'ps-inventory',
    'tgiann-inventory',
    'core_inventory',
    'origen_inventory',
    'framework'
}

local function resolveInventoryProvider()
    local forced = RSBridgeConfig.Inventory.Provider or 'auto'
    if forced ~= 'auto' then return forced end

    for _, provider in ipairs(inventoryOrder) do
        if provider == 'framework' or RSBridge.resourceStarted(provider) then
            return provider
        end
    end

    return 'framework'
end

local function frameworkAdd(src, item, amount, metadata, slot)
    local player = GetPlayer(src)
    if not player then return false end

    if RSBridge.Framework == 'esx' then
        if player.addInventoryItem then
            player.addInventoryItem(item, amount)
            return true
        end
        return false
    end

    if player.Functions and player.Functions.AddItem then
        return player.Functions.AddItem(item, amount, slot or false, metadata)
    end

    return false
end

local function frameworkRemove(src, item, amount, slot, metadata)
    local player = GetPlayer(src)
    if not player then return false end

    if RSBridge.Framework == 'esx' then
        if player.removeInventoryItem then
            player.removeInventoryItem(item, amount)
            return true
        end
        return false
    end

    if player.Functions and player.Functions.RemoveItem then
        return player.Functions.RemoveItem(item, amount, slot)
    end

    return false
end

local function frameworkGetItem(src, item)
    local player = GetPlayer(src)
    if not player then return nil end

    if RSBridge.Framework == 'esx' then
        if player.getInventoryItem then return player.getInventoryItem(item) end
        return nil
    end

    if player.Functions and player.Functions.GetItemByName then
        return player.Functions.GetItemByName(item)
    end

    return nil
end

local Adapters = {}

Adapters['ox_inventory'] = {
    AddItem = function(src, item, amount, metadata, slot)
        return exports.ox_inventory:AddItem(src, item, amount, metadata, slot)
    end,
    RemoveItem = function(src, item, amount, slot, metadata)
        return exports.ox_inventory:RemoveItem(src, item, amount, metadata, slot)
    end,
    GetItem = function(src, item)
        return exports.ox_inventory:GetItem(src, item, nil, false)
    end,
    GetItemCount = function(src, item)
        return exports.ox_inventory:Search(src, 'count', item) or 0
    end,
    CanCarryItem = function(src, item, amount, metadata)
        return exports.ox_inventory:CanCarryItem(src, item, amount, metadata)
    end
}

-- qb-inventory, including the RealitySucksRP fork
-- ('2.6.3-rs-punk-cash-authority'), which keeps these signatures:
--   AddItem(identifier, item, amount, slot, info, reason)
--   RemoveItem(identifier, item, amount, slot, reason)
--   GetItemByName(source, item) / GetItemCount(source, items)
--   CanAddItem(identifier, item, amount)
Adapters['qb-inventory'] = {
    AddItem = function(src, item, amount, metadata, slot)
        return exports['qb-inventory']:AddItem(src, item, amount, slot, metadata, 'rs_bridge')
    end,
    RemoveItem = function(src, item, amount, slot, metadata)
        return exports['qb-inventory']:RemoveItem(src, item, amount, slot, 'rs_bridge')
    end,
    GetItem = function(src, item)
        return exports['qb-inventory']:GetItemByName(src, item)
    end,
    GetItemCount = function(src, item)
        return exports['qb-inventory']:GetItemCount(src, item) or 0
    end,
    CanCarryItem = function(src, item, amount, metadata)
        return exports['qb-inventory']:CanAddItem(src, item, amount)
    end
}

Adapters['qs-inventory'] = {
    AddItem = function(src, item, amount, metadata, slot) return exports['qs-inventory']:AddItem(src, item, amount, slot, metadata) end,
    RemoveItem = function(src, item, amount, slot, metadata) return exports['qs-inventory']:RemoveItem(src, item, amount, slot, metadata) end,
    GetItem = function(src, item) return exports['qs-inventory']:GetItemByName(src, item) end,
    GetItemCount = function(src, item)
        local found = exports['qs-inventory']:GetItemByName(src, item)
        return found and (found.amount or found.count or 0) or 0
    end
}

Adapters['codem-inventory'] = {
    AddItem = function(src, item, amount, metadata, slot) return exports['codem-inventory']:AddItem(src, item, amount, slot, metadata) end,
    RemoveItem = function(src, item, amount, slot, metadata) return exports['codem-inventory']:RemoveItem(src, item, amount, slot) end,
    GetItem = function(src, item) return exports['codem-inventory']:GetItemByName(src, item) end
}

Adapters['ps-inventory'] = {
    AddItem = function(src, item, amount, metadata, slot) return exports['ps-inventory']:AddItem(src, item, amount, slot, metadata) end,
    RemoveItem = function(src, item, amount, slot, metadata) return exports['ps-inventory']:RemoveItem(src, item, amount, slot) end,
    GetItem = function(src, item) return exports['ps-inventory']:GetItemByName(src, item) end
}

Adapters['tgiann-inventory'] = {
    AddItem = function(src, item, amount, metadata, slot) return exports['tgiann-inventory']:AddItem(src, item, amount, slot, metadata) end,
    RemoveItem = function(src, item, amount, slot, metadata) return exports['tgiann-inventory']:RemoveItem(src, item, amount, slot, metadata) end,
    GetItem = function(src, item) return exports['tgiann-inventory']:GetItemByName(src, item) end
}

Adapters['core_inventory'] = {
    AddItem = function(src, item, amount, metadata, slot) return exports.core_inventory:addItem(src, item, amount, metadata) end,
    RemoveItem = function(src, item, amount, slot, metadata) return exports.core_inventory:removeItem(src, item, amount) end
}

Adapters['origen_inventory'] = {
    AddItem = function(src, item, amount, metadata, slot) return exports.origen_inventory:AddItem(src, item, amount, metadata, slot) end,
    RemoveItem = function(src, item, amount, slot, metadata) return exports.origen_inventory:RemoveItem(src, item, amount, slot, metadata) end,
    GetItem = function(src, item) return exports.origen_inventory:GetItem(src, item) end
}

local function callAdapter(method, ...)
    local provider = resolveInventoryProvider()

    if provider == 'framework' then
        if method == 'AddItem' then return frameworkAdd(...) end
        if method == 'RemoveItem' then return frameworkRemove(...) end
        if method == 'GetItem' then return frameworkGetItem(...) end
        return nil
    end

    local adapter = Adapters[provider]
    local fn = adapter and adapter[method]
    if not fn then
        if method == 'AddItem' then return frameworkAdd(...) end
        if method == 'RemoveItem' then return frameworkRemove(...) end
        if method == 'GetItem' then return frameworkGetItem(...) end
        return nil
    end

    local ok, result = RSBridge.safeCall(fn, ...)
    if ok then return result end

    if method == 'AddItem' then return frameworkAdd(...) end
    if method == 'RemoveItem' then return frameworkRemove(...) end
    if method == 'GetItem' then return frameworkGetItem(...) end
    return nil
end

function AddItem(src, item, amount, metadata, slot)
    -- Refused rather than coerced: turning a malformed amount into 1 makes an
    -- invalid mutation look like a successful one to the caller.
    local valid, reason = RSBridge.validateAmount(amount)
    if not valid then
        RSBridge.debug(('AddItem refused for %s: %s'):format(tostring(item), reason))
        return false, reason
    end
    return callAdapter('AddItem', src, item, valid, metadata, slot)
end

function RemoveItem(src, item, amount, slot, metadata)
    local valid, reason = RSBridge.validateAmount(amount)
    if not valid then
        RSBridge.debug(('RemoveItem refused for %s: %s'):format(tostring(item), reason))
        return false, reason
    end
    return callAdapter('RemoveItem', src, item, valid, slot, metadata)
end

function GetItem(src, item)
    return callAdapter('GetItem', src, item)
end

function GetItemCount(src, item)
    local provider = resolveInventoryProvider()
    local adapter = Adapters[provider]
    if adapter and adapter.GetItemCount then
        local ok, result = RSBridge.safeCall(adapter.GetItemCount, src, item)
        if ok then return result or 0 end
    end

    local found = GetItem(src, item)
    if not found then return 0 end
    return found.amount or found.count or found.quantity or found.count or 0
end

function HasItem(src, item, amount)
    local valid = RSBridge.validateAmount(amount)
    -- A nonsense quantity is not 'has', so answer false rather than guessing.
    if not valid then return false end
    return GetItemCount(src, item) >= valid
end

function CanCarryItem(src, item, amount, metadata)
    local valid = RSBridge.validateAmount(amount)
    if not valid then return false end
    amount = valid
    local provider = resolveInventoryProvider()
    local adapter = Adapters[provider]

    if adapter and adapter.CanCarryItem then
        local ok, result = RSBridge.safeCall(adapter.CanCarryItem, src, item, amount, metadata)
        if ok and result ~= nil then return result == true end
    end

    -- No provider could answer. Do NOT default to true: shops, rewards, crafting
    -- and admin-give all gate on this, and a false "yes" hands out an item the
    -- player cannot hold, which destroys it. Unknown capacity is not permission.
    -- Set Config.Inventory.AssumeCanCarryWhenUnknown = true to restore the old
    -- permissive behaviour on a server with no supported inventory.
    local cfg = RSBridgeConfig and RSBridgeConfig.Inventory or nil
    if cfg and cfg.AssumeCanCarryWhenUnknown == true then return true end

    RSBridge.debug(('CanCarryItem: no provider could answer for %s; refusing'):format(tostring(item)))
    return false
end

-- Resources register their useable items on their own start, which for most of
-- them happens BEFORE this bridge has finished detecting the framework
-- (detection waits 250ms and runs on a thread). Without somewhere to park those
-- calls, every early registration fell through every branch and was dropped with
-- a "skipped" line -- rs-tunerchip's rs_driftchip was doing exactly that,
-- leaving the item non-useable from the inventory.
--
-- Park them instead, and replay once a framework is known.
local pendingUseableItems = {}
local pendingFlushQueued = false

local function flushPendingUseableItems()
    if RSBridge.Framework == 'standalone' then return end
    if #pendingUseableItems == 0 then return end

    local queue = pendingUseableItems
    pendingUseableItems = {}

    for _, entry in ipairs(queue) do
        -- CreateUseableItem is redefined below; call through the global so the
        -- replay takes the now-resolved framework path.
        CreateUseableItem(entry.item, entry.cb)
    end
end

local function deferUseableItem(item, cb)
    pendingUseableItems[#pendingUseableItems + 1] = { item = item, cb = cb }
    RSBridge.debug(('CreateUseableItem deferred for %s until framework resolves'):format(item))

    if pendingFlushQueued then return end
    pendingFlushQueued = true

    CreateThread(function()
        -- Detection settles within a second; keep checking a little past that in
        -- case the core itself started late.
        local deadline = GetGameTimer() + 30000
        while GetGameTimer() < deadline do
            Wait(500)
            if RSBridge.Framework ~= 'standalone' then
                flushPendingUseableItems()
                pendingFlushQueued = false
                return
            end
        end

        pendingFlushQueued = false
        for _, entry in ipairs(pendingUseableItems) do
            RSBridge.debug(('CreateUseableItem skipped for %s; no framework resolved in time'):format(entry.item))
        end
        pendingUseableItems = {}
    end)
end

function CreateUseableItem(item, cb)
    -- Nothing can be registered until we know which core owns the item registry.
    if RSBridge.Framework == 'standalone' then
        deferUseableItem(item, cb)
        return false
    end

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

    if RSBridge.Framework == 'esx' then
        local ESX = GetCoreObject()
        if ESX and ESX.RegisterUsableItem then
            ESX.RegisterUsableItem(item, cb)
            return true
        end
    end

    RSBridge.debug(('CreateUseableItem skipped for %s; no supported framework function'):format(item))
    return false
end

-- Lets resources report or degrade instead of guessing which inventory is live.
function GetInventoryProvider()
    return resolveInventoryProvider()
end

exports('GetInventoryProvider', GetInventoryProvider)
exports('AddItem', AddItem)
exports('RemoveItem', RemoveItem)
exports('GetItem', GetItem)
exports('GetItemCount', GetItemCount)
exports('HasItem', HasItem)
exports('CanCarryItem', CanCarryItem)
exports('CreateUseableItem', CreateUseableItem)
