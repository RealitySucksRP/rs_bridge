--[[
    rs_bridge -- QBCore-shaped core facade (SERVER)

    Included by consumers as '@rs_bridge/server/core.lua', so it runs inside that
    resource's own Lua VM and defines RSBridgeCore there.

    WHY THIS EXISTS
    ---------------
    Several RS resources open with:

        local QBCore = exports['qb-core']:GetCoreObject()

    at file scope, unguarded. On a server with no literal qb-core resource that
    is a hard error at load -- the whole file dies. This server has none; it only
    ever resolved because qbx_core declares provide 'qb-core'.

    Rather than rewrite the ~133 QBCore.* call sites inside those resources, they
    swap that one line for:

        local QBCore = RSBridgeCore

    and keep their existing code. Everything below routes to rs_bridge, which
    resolves Qbox, QBCore or ESX at runtime.

    SIGNATURES were taken from the live sources, not from memory:
      * Qbox    -- installed qbx_core/server/functions.lua
                   GetPlayer(source), GetQBPlayers(), CreateUseableItem(item, data),
                   HasPermission(source, permission), HasGroup(source, filter),
                   Notify(source, text, notifyType, duration, ...)
                   NOTE: Qbox exposes no CreateCallback/TriggerCallback -- it uses
                   ox_lib (lib.callback), which is what rs_bridge wraps.
      * QBCore  -- qbcore.net/docs/core/functions
      * ESX     -- docs.esx-framework.org (xPlayer accessors, RegisterServerCallback,
                   RegisterUsableItem, GetExtendedPlayers, GetItems)

    Every bridge call below uses explicit `exports.rs_bridge:Name(...)` colon
    syntax. Dynamic dispatch through exports.rs_bridge[name] is NOT equivalent in
    FiveM and is deliberately avoided here.
]]

RSBridgeCore = RSBridgeCore or {}

local function bridgeUp()
    return GetResourceState('rs_bridge') == 'started'
end

--- Runs a bridge call, returning `fallback` if the bridge is down or the call
--- errors. Keeps every consumer-facing function non-throwing.
local function safe(fn, fallback)
    if not bridgeUp() then return fallback end
    local ok, result = pcall(fn)
    if ok and result ~= nil then return result end
    return fallback
end

local Functions = {}

-- ---------------------------------------------------------------- players

function Functions.GetPlayer(source)
    return safe(function() return exports.rs_bridge:GetPlayer(source) end, nil)
end

function Functions.GetPlayerData(source)
    return safe(function() return exports.rs_bridge:GetPlayerData(source) end, {})
end

--- QB returns an array of player sources. GetPlayers() is a base native and
--- behaves identically on every framework, so it is used directly.
function Functions.GetPlayers()
    return GetPlayers()
end

--- QB returns a table of Player OBJECTS keyed by source, not a list of ids.
function Functions.GetQBPlayers()
    local players = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src then
            local player = Functions.GetPlayer(src)
            if player then players[src] = player end
        end
    end
    return players
end

-- ------------------------------------------------------------ notifications

--- Qbox signature is Notify(source, text, notifyType, duration, ...).
function Functions.Notify(source, text, notifyType, duration)
    if not bridgeUp() then
        print(('[rs_bridge/core] notify %s: %s'):format(tostring(source), tostring(text)))
        return false
    end
    return safe(function()
        return exports.rs_bridge:Notify(source, text, notifyType, duration)
    end, false)
end

-- ------------------------------------------------------------- usable items

--- rs_bridge parks the registration when no framework has resolved yet and
--- replays it once one does, so load order does not matter here.
function Functions.CreateUseableItem(item, cb)
    return safe(function() return exports.rs_bridge:CreateUseableItem(item, cb) end, false)
end

-- ---------------------------------------------------------------- callbacks

--- QB style is handler(source, cb, ...) where the handler CALLS cb with results.
--- rs_bridge (ox_lib underneath) expects handler(source, ...) to RETURN them.
--- This adapts between the two and tolerates a handler that resolves
--- asynchronously -- a DB round trip, say -- by waiting for cb rather than
--- assuming it fired before the handler returned.
---
--- Multiple return values are preserved: consumers rely on callbacks such as
--- cb(success, status, stage, index, state) arriving intact.
function Functions.CreateCallback(name, handler)
    if type(name) ~= 'string' or type(handler) ~= 'function' then return false end

    return safe(function()
        return exports.rs_bridge:RegisterCallback(name, function(source, ...)
            local resolved, packed = false, nil

            local function resolve(...)
                if resolved then return end
                resolved = true
                packed = table.pack(...)
            end

            handler(source, resolve, ...)

            if not resolved then
                local deadline = GetGameTimer() + 10000
                while not resolved and GetGameTimer() < deadline do
                    Wait(0)
                end
            end

            if packed then return table.unpack(packed, 1, packed.n) end

            -- rs_bridge turns a nil first return into false, so a handler that
            -- never resolves cannot produce the msgpack nil-response error.
            return false
        end)
    end, false)
end

--- Server-side TriggerCallback targets a CLIENT callback in QB.
function Functions.TriggerCallback(name, source, cb, ...)
    local args = table.pack(...)
    return safe(function()
        return exports.rs_bridge:TriggerClientCallback(name, source, cb, table.unpack(args, 1, args.n))
    end, false)
end

Functions.TriggerClientCallback = Functions.TriggerCallback

-- -------------------------------------------------------------- permissions

--- QB and Qbox both expose HasPermission(source, permission). ESX has no
--- permission system, so ACE and the bridge group check stand in for it.
function Functions.HasPermission(source, permission)
    local result = safe(function()
        return exports.rs_bridge:HasPermission(source, permission)
    end, nil)
    if result ~= nil then return result == true end

    if IsPlayerAceAllowed(source, tostring(permission or 'command')) then return true end

    return safe(function()
        return exports.rs_bridge:HasGroup(source, { 'admin', 'god' })
    end, false) == true
end

function Functions.GetPermission(source)
    local result = safe(function() return exports.rs_bridge:GetPermission(source) end, nil)
    if result ~= nil then return result end
    return Functions.HasPermission(source, 'admin') and 'admin' or 'user'
end

function Functions.HasGroup(source, groups, minGrade)
    return safe(function()
        return exports.rs_bridge:HasGroup(source, groups, minGrade)
    end, false) == true
end

-- ------------------------------------------------------------------ money

function Functions.AddMoney(source, account, amount, reason)
    return safe(function()
        return exports.rs_bridge:AddMoney(source, account, amount, reason)
    end, false)
end

function Functions.RemoveMoney(source, account, amount, reason)
    return safe(function()
        return exports.rs_bridge:RemoveMoney(source, account, amount, reason)
    end, false)
end

function Functions.GetMoney(source, account)
    return safe(function() return exports.rs_bridge:GetMoney(source, account) end, 0)
end

RSBridgeCore.Functions = Functions

-- ----------------------------------------------------------------- shared

--- QBCore.Shared.Items is read as a plain table keyed by item name. Lookups are
--- resolved lazily so items registered after this file loads are still found.
local SharedItems = setmetatable({}, {
    __index = function(_, itemName)
        return safe(function()
            return exports.rs_bridge:GetItemDefinition(itemName)
        end, nil)
    end,
    __pairs = function(t)
        local items = safe(function() return exports.rs_bridge:GetItems() end, {})
        return next, items, nil
    end
})

RSBridgeCore.Shared = { Items = SharedItems }

-- ---------------------------------------------------------------- commands

--- QB: Commands.Add(name, help, arguments, argsrequired, callback, permission)
--- No framework-neutral command registry exists, so this is RegisterCommand plus
--- a permission gate. ACE is checked first because it behaves identically on
--- every framework and covers txAdmin and server.cfg grants.
RSBridgeCore.Commands = {
    Add = function(name, help, arguments, argsrequired, callback, permission)
        if type(name) ~= 'string' or type(callback) ~= 'function' then return false end

        RegisterCommand(name, function(source, args, raw)
            -- source 0 is the server console; never gate it.
            if source > 0 and permission and permission ~= '' and permission ~= 'user' then
                if not Functions.HasPermission(source, permission) then
                    Functions.Notify(source, 'You do not have permission to use that.', 'error')
                    return
                end
            end

            if argsrequired and type(arguments) == 'table' and #args < #arguments then
                Functions.Notify(source, ('Missing arguments for /%s'):format(name), 'error')
                return
            end

            callback(source, args, raw)
        end, false)

        if help and help ~= '' then
            TriggerEvent('chat:addSuggestion', '/' .. name, help, arguments or {})
        end

        return true
    end
}
