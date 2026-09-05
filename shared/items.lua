-- Item definition lookup.
--
-- Replaces direct QBCore.Shared.Items access. Per the Qbox conversion guide
-- the item registry on Qbox is ox_inventory, not the core:
--     QBCore.Shared.Items  ->  exports.ox_inventory:Items()
--
-- Resolution order is inventory-first so an ESX or QBCore server running
-- ox_inventory also gets the authoritative list rather than a stale core copy.
--
-- Returned definitions are normalized to:
--     { name, label, weight, description, stack, close, image }

local cachedItems = nil
local cachedAt = 0
local CACHE_MS = 10000

local function normalize(name, raw)
    if type(raw) ~= 'table' then
        return { name = name, label = name, weight = 0 }
    end

    return {
        name = raw.name or name,
        label = raw.label or raw.name or name,
        weight = raw.weight or 0,
        description = raw.description or raw.desc,
        stack = raw.stack ~= false,
        close = raw.close ~= false,
        image = raw.image or raw.client and raw.client.image or nil,
        raw = raw
    }
end

local function fromOxInventory()
    if not RSBridge.resourceStarted('ox_inventory') then return nil end

    local ok, items = RSBridge.safeCall(function()
        return exports.ox_inventory:Items()
    end)

    if not ok or type(items) ~= 'table' then return nil end
    return items
end

local function fromFramework()
    if RSBridge.Framework == 'qbcore' then
        local core = GetCoreObject()
        local items = core and core.Shared and core.Shared.Items
        if type(items) == 'table' then return items end
    end

    if RSBridge.Framework == 'esx' then
        local ESX = GetCoreObject()
        if ESX and ESX.GetItems then
            local ok, items = RSBridge.safeCall(function()
                return ESX.GetItems()
            end)
            if ok and type(items) == 'table' then return items end
        end
        if ESX and type(ESX.Items) == 'table' then return ESX.Items end
    end

    return nil
end

-- Full item registry, keyed by item name. Empty table when nothing resolves,
-- never nil, so callers can iterate without guarding.
function GetItems(force)
    local now = GetGameTimer()
    if not force and cachedItems and (now - cachedAt) < CACHE_MS then
        return cachedItems
    end

    local raw = fromOxInventory() or fromFramework()
    if type(raw) ~= 'table' then
        RSBridge.debug('No item registry resolved. Supported: ox_inventory, QBCore shared items, ESX items.')
        return {}
    end

    local normalized = {}
    for name, def in pairs(raw) do
        normalized[name] = normalize(name, def)
    end

    cachedItems = normalized
    cachedAt = now
    return normalized
end

function GetItemDefinition(name)
    if not name then return nil end
    return GetItems()[name]
end

function DoesItemExist(name)
    return GetItemDefinition(name) ~= nil
end

function GetItemLabel(name)
    local def = GetItemDefinition(name)
    return def and def.label or name
end

AddEventHandler('onResourceStart', function(resource)
    if resource == 'ox_inventory' then cachedItems = nil end
end)

exports('GetItems', GetItems)
exports('GetItemDefinition', GetItemDefinition)
exports('DoesItemExist', DoesItemExist)
exports('GetItemLabel', GetItemLabel)
