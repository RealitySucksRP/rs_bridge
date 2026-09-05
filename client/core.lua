--[[
    rs_bridge -- QBCore-shaped core facade (CLIENT)

    Included by consumers as '@rs_bridge/client/core.lua', so it runs inside that
    resource's own Lua VM and defines RSBridgeCore there.

    Companion to server/core.lua. See that file for the full rationale; briefly:
    several RS resources open with an unguarded

        local QBCore = exports['qb-core']:GetCoreObject()

    which is a hard error at load on any server without a literal qb-core
    resource. They swap that single line for

        local QBCore = RSBridgeCore

    and keep their existing QBCore.* calls unchanged.

    Only four members are used client-side across those resources, so only those
    are modelled: Functions.Notify, Functions.TriggerCallback,
    Functions.GetPlayerData and Shared.Items.

    Bridge calls use explicit `exports.rs_bridge:Name(...)` colon syntax --
    dynamic dispatch via exports.rs_bridge[name] is not equivalent in FiveM.
]]

RSBridgeCore = RSBridgeCore or {}

local function bridgeUp()
    return GetResourceState('rs_bridge') == 'started'
end

local function safe(fn, fallback)
    if not bridgeUp() then return fallback end
    local ok, result = pcall(fn)
    if ok and result ~= nil then return result end
    return fallback
end

local Functions = {}

--- Client signature is Notify(message, notifyType, duration) -- no source, unlike
--- the server side. Falls back to the game's own feed so a message is never lost
--- while the bridge is still resolving.
function Functions.Notify(message, notifyType, duration)
    if message == nil or message == '' then return false end

    if bridgeUp() then
        local ok = pcall(function()
            exports.rs_bridge:Notify(message, notifyType, duration)
        end)
        if ok then return true end
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message))
    EndTextCommandThefeedPostTicker(false, true)
    return true
end

--- QB: TriggerCallback(name, cb, ...) -- identical shape to the bridge's
--- TriggerServerCallback, so this is a straight pass-through.
function Functions.TriggerCallback(name, cb, ...)
    if type(name) ~= 'string' then return false end

    if not bridgeUp() then
        -- Answer the caller rather than leaving it waiting forever on a callback
        -- that can never arrive.
        if type(cb) == 'function' then cb(nil) end
        return false
    end

    local args = table.pack(...)
    local ok = pcall(function()
        exports.rs_bridge:TriggerServerCallback(name, cb, table.unpack(args, 1, args.n))
    end)

    if not ok and type(cb) == 'function' then cb(nil) end
    return ok
end

Functions.TriggerServerCallback = Functions.TriggerCallback

function Functions.GetPlayerData()
    return safe(function() return exports.rs_bridge:GetPlayerData() end, {})
end

RSBridgeCore.Functions = Functions

--- QBCore.Shared.Items keyed by item name, resolved lazily so items registered
--- after this file loads are still found.
RSBridgeCore.Shared = {
    Items = setmetatable({}, {
        __index = function(_, itemName)
            return safe(function()
                return exports.rs_bridge:GetItemDefinition(itemName)
            end, nil)
        end,
        __pairs = function()
            local items = safe(function() return exports.rs_bridge:GetItems() end, {})
            return next, items, nil
        end
    })
}
