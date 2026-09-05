RSBridge = RSBridge or {}

-- ===========================================================================
-- VERSION NEGOTIATION
--
-- Why this exists.
--
-- rs_bridge ships free so a customer can drop in any RS resource and have its
-- framework, inventory, fuel and target resolved for them. The cost of that is
-- version skew: a customer updates one paid resource, leaves rs_bridge at
-- whatever they installed months ago, and the new resource calls an export the
-- old bridge never registered.
--
-- FiveM's failure mode for that is silent-ish and deeply unhelpful. An
-- unguarded call raises "No such export", which kills the calling thread at
-- that line. A menu simply never opens; a shop ped is simply never targetable.
-- Nothing in the console says "your bridge is old", so the customer reports a
-- broken resource and the author debugs a bug that does not exist.
--
-- This turns that into one line naming the resource, the version it needs and
-- the version installed.
--
-- The version is read from the manifest rather than hardcoded here, so there is
-- exactly one place to bump it and it can never disagree with the ZIP.
-- ===========================================================================

local function parse(value)
    local text = tostring(value or '')
    local major, minor, patch = text:match('^%s*v?(%d+)%.(%d+)%.?(%d*)')
    if not major then return nil end
    return {
        major = tonumber(major) or 0,
        minor = tonumber(minor) or 0,
        -- A two-part version ("2.4") is a legitimate way to say "any patch".
        patch = tonumber(patch) or 0,
        text = text
    }
end

--- Compare two parsed versions. -1 a<b, 0 equal, 1 a>b.
local function compare(a, b)
    if a.major ~= b.major then return a.major < b.major and -1 or 1 end
    if a.minor ~= b.minor then return a.minor < b.minor and -1 or 1 end
    if a.patch ~= b.patch then return a.patch < b.patch and -1 or 1 end
    return 0
end

local installedText = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '0.0.0'
local installed = parse(installedText) or { major = 0, minor = 0, patch = 0, text = installedText }

--- The running rs_bridge version, as written in its manifest.
function GetVersion()
    return installed.text
end

--- Does the running bridge satisfy `required` ("2.4.0" or "2.4")?
---
--- Returns a TABLE rather than multiple values: exports flatten multiple
--- returns inconsistently across FiveM builds, and a caller silently reading
--- only the first value is exactly the class of bug this module exists to stop.
---
--- @return table { ok, installed, required, message }
function RequireVersion(required)
    local want = parse(required)
    local caller = GetInvokingResource() or 'unknown resource'

    if not want then
        return {
            ok = true, -- never block on a malformed request from a consumer
            installed = installed.text,
            required = tostring(required),
            message = ('^3[rs_bridge] %s asked for version "%s", which is not a version number. Skipping the check.^7')
                :format(caller, tostring(required))
        }
    end

    local ok = compare(installed, want) >= 0
    return {
        ok = ok,
        installed = installed.text,
        required = want.text,
        message = ok
            and ('[rs_bridge] %s: version check passed (needs %s, running %s).'):format(caller, want.text, installed.text)
            or ('^1[rs_bridge] %s REQUIRES rs_bridge >= %s but %s is installed. Update rs_bridge -- until you do, parts of %s will fail with "No such export" and may simply not respond.^7')
                :format(caller, want.text, installed.text, caller)
    }
end

exports('GetVersion', GetVersion)
exports('RequireVersion', RequireVersion)

-- ---------------------------------------------------------------------------
-- Declarative check.
--
-- A resource states its need in its own manifest:
--
--     rs_bridge_version '2.4.0'
--
-- and needs no Lua at all. This sweep reads that field from every started
-- resource and reports the ones this bridge cannot satisfy.
--
-- Server side only: this is for whoever is reading the console on boot, and
-- printing it once per connected client would bury it.
--
-- NOTE the deliberate gap. If the INSTALLED bridge is older than this file,
-- none of this runs -- an old bridge cannot know to check itself. Resources
-- that require newer exports should also use a consumer-side guard before
-- calling them, treating a missing RequireVersion export as an outdated bridge.
-- ---------------------------------------------------------------------------

if IsDuplicityVersion() then
    local function sweep()
        local unmet, checked = {}, 0

        for index = 0, GetNumResources() - 1 do
            local name = GetResourceByFindIndex(index)
            if name and GetResourceState(name) == 'started' then
                local need = GetResourceMetadata(name, 'rs_bridge_version', 0)
                if need and need ~= '' then
                    checked = checked + 1
                    local want = parse(need)
                    if want and compare(installed, want) < 0 then
                        unmet[#unmet + 1] = ('    %s needs >= %s'):format(name, want.text)
                    end
                end
            end
        end

        if #unmet > 0 then
            print(('^1[rs_bridge] %s is installed, but %d resource(s) need a newer bridge:^7')
                :format(installed.text, #unmet))
            for _, line in ipairs(unmet) do print('^1' .. line .. '^7') end
            print('^1[rs_bridge] Update rs_bridge. Until then those resources will fail in ways that do not name the bridge.^7')
        elseif checked > 0 then
            RSBridge.debug(('version sweep: %d resource(s) checked, all satisfied by %s')
                :format(checked, installed.text))
        end
    end

    -- Late enough that resources ensured after rs_bridge have registered.
    CreateThread(function()
        Wait(5000)
        RSBridge.safeCall(sweep)
    end)

    -- A resource started by hand later is the exact moment skew appears, so
    -- check that one on its own rather than re-sweeping everything.
    AddEventHandler('onResourceStart', function(name)
        if not name or name == GetCurrentResourceName() then return end
        RSBridge.safeCall(function()
            local need = GetResourceMetadata(name, 'rs_bridge_version', 0)
            if not need or need == '' then return end
            local want = parse(need)
            if want and compare(installed, want) < 0 then
                print(('^1[rs_bridge] %s needs rs_bridge >= %s but %s is installed. Update rs_bridge.^7')
                    :format(name, want.text, installed.text))
            end
        end)
    end)
end
