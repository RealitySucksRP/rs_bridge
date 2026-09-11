-- ===========================================================================
-- HUD VISIBILITY PROVIDER
--
--     exports.rs_bridge:SetHudVisible(false)  -- hide, opening a full-screen UI
--     exports.rs_bridge:SetHudVisible(true)   -- show, closing it
--
-- Every provider in this bridge resolves "the server has one of N
-- implementations" the same way: ordered list, config override, firstStarted().
-- HUDs need one extra dimension the others do not.
--
-- ox_target and qb-target both expose exports, so target.lua only has to
-- translate argument shapes. HUDs disagree about something more basic: whether
-- there is an export at all. Plenty ship only an event. So each registry entry
-- carries a `kind` ('export' or 'event') alongside its name, and the dispatcher
-- branches on that.
--
-- Nothing here is allowed to throw. A resource asking to hide the HUD is about
-- to open its own UI; if the HUD cannot be hidden that is cosmetic, and it must
-- never stop the caller. Every call path ends in a silent false, never an error.
-- ===========================================================================

-- Ordered by detection priority. First started wins.
--
-- `kind = 'export'` -> RSBridge.callExport(resource, name, visible)
-- `kind = 'event'`  -> TriggerEvent(name, visible)
--
-- `invert = true` marks a HUD whose toggle takes "hidden" rather than "visible",
-- so the boolean is flipped before the call. Getting this backwards means the
-- HUD appears exactly when it should disappear, which is worse than doing
-- nothing at all -- verify against the HUD's own source before adding an entry.
local registry = {
    {
        resource = 'rs-lilhudlife',
        kind = 'export',
        name = 'SetHUDLifeVisible',
    },
}

-- ADDING A HUD
--
-- Deliberately short. Entries are only added once the toggle has been read in
-- that HUD's own source -- a guessed event name is worse than no entry: an
-- unknown HUD is a silent no-op, but a WRONG event name fires something real
-- with a boolean it never expected. qb-hud and ps-hud are the obvious next
-- candidates and are absent for exactly that reason: neither was installed
-- where this was written, so neither could be checked.
--
-- To add one:
--   1. Find its toggle. `grep -rn "exports(" <hud>` for an export, or
--      `grep -rn "RegisterNetEvent" <hud>` for an event.
--   2. Confirm the argument means VISIBLE, not HIDDEN. If it means hidden,
--      set invert = true.
--   3. Append { resource = ..., kind = 'export'|'event', name = ... }.
--
-- Until then, any server can reach its own HUD through RSBridgeConfig.Hud.Custom
-- without touching this file.

local cachedProvider = nil

-- Resolve to a registry entry, a Custom table, or nil.
local function resolveHudProvider()
    local cfg = RSBridgeConfig.Hud or {}
    local forced = cfg.Provider or 'auto'

    if forced == 'none' then return nil end

    -- A Custom entry outranks the registry whatever Provider says: it is the
    -- only way to reach a HUD the registry has never heard of, which is the
    -- common case for a server running something in-house.
    local custom = cfg.Custom
    if type(custom) == 'table' then
        if type(custom.event) == 'string' and custom.event ~= '' then
            return { kind = 'event', name = custom.event, invert = custom.invert == true }
        end
        if type(custom.resource) == 'string' and type(custom.export) == 'string'
            and custom.resource ~= '' and custom.export ~= '' then
            if RSBridge.resourceStarted(custom.resource) then
                return {
                    resource = custom.resource,
                    kind = 'export',
                    name = custom.export,
                    invert = custom.invert == true
                }
            end
            -- Named but not running: fall through to detection rather than
            -- giving up, so a typo'd Custom does not disable a HUD the
            -- registry would have found on its own.
        end
    end

    if forced ~= 'auto' then
        for _, entry in ipairs(registry) do
            if entry.resource == forced then
                return RSBridge.resourceStarted(entry.resource) and entry or nil
            end
        end
        RSBridge.debug(('HUD provider "%s" is unavailable; falling back to auto detection'):format(tostring(forced)))
        -- continue into auto detection instead of making a stale config a dead end
    end

    if cachedProvider ~= nil then
        -- Revalidate: a HUD stopped since we cached is no longer a provider.
        if cachedProvider == false then return nil end
        if RSBridge.resourceStarted(cachedProvider.resource) then return cachedProvider end
        cachedProvider = nil
    end

    for _, entry in ipairs(registry) do
        if RSBridge.resourceStarted(entry.resource) then
            cachedProvider = entry
            return entry
        end
    end

    cachedProvider = false
    return nil
end

-- A HUD starting or stopping changes the answer, so drop the cache and let the
-- next call re-resolve rather than holding a stale provider.
AddEventHandler('onResourceStart', function(resource)
    for _, entry in ipairs(registry) do
        if entry.resource == resource then cachedProvider = nil return end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    for _, entry in ipairs(registry) do
        if entry.resource == resource then cachedProvider = nil return end
    end
end)

--- Name of the resolved HUD provider, or 'none'. Mostly for diagnostics --
--- a server owner asking why SetHudVisible does nothing wants this answer.
function GetHudProvider()
    local entry = resolveHudProvider()
    if not entry then return 'none' end
    return entry.resource or ('custom:' .. tostring(entry.name))
end

--- Show or hide the server's HUD.
--- @param visible boolean true to show, false to hide
--- @return boolean true if a provider was called, false if none matched
function SetHudVisible(visible)
    visible = visible ~= false

    local entry = resolveHudProvider()
    if not entry then return false end

    local value = entry.invert and (not visible) or visible

    local ok, err = pcall(function()
        if entry.kind == 'event' then
            TriggerEvent(entry.name, value)
        else
            local called, result = RSBridge.callExport(entry.resource, entry.name, value)
            if not called then error(result) end
        end
    end)

    if not ok then
        -- Logged, not raised. The caller is mid-way through opening its own UI
        -- and a HUD that refuses to hide is not a reason to abort that.
        RSBridge.debug(('HUD provider %s (%s:%s) failed: %s'):format(
            tostring(entry.resource or 'custom'), tostring(entry.kind),
            tostring(entry.name), tostring(err)))
        return false
    end

    return true
end

exports('SetHudVisible', SetHudVisible)
exports('GetHudProvider', GetHudProvider)
