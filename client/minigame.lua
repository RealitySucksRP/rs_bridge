-- Minigame provider bridge.
--
-- A minigame gates an action: pick a lock, hotwire an ignition, hack a panel.
-- Every ecosystem ships a different one, so RS resources ask for an *intent*
-- and this layer maps it onto whichever provider the server actually runs.
--
-- Intents are deliberately semantic ('lockpick') rather than game names
-- ('skill_circle'). Naming a specific game here would reintroduce exactly the
-- provider coupling this module exists to remove, and no two providers share a
-- game list. Per-game tuning belongs in the provider's own config, not here.

local VALID_INTENTS = {
    lockpick = true,
    hotwire = true,
    hack = true,
    generic = true,
}

local function normalizeIntent(intent)
    intent = type(intent) == 'string' and string.lower(intent) or 'generic'
    if not VALID_INTENTS[intent] then return 'generic' end
    return intent
end

local function normalizeOptions(opts)
    opts = type(opts) == 'table' and opts or {}
    local cfg = RSBridgeConfig.Minigame or {}

    local difficulty = opts.difficulty
    if difficulty ~= 'easy' and difficulty ~= 'medium' and difficulty ~= 'hard' then
        difficulty = cfg.DefaultDifficulty or 'medium'
    end

    -- 'advanced' means the player brought better tools, so it should be the
    -- easier path, matching how qbx_vehiclekeys balances its own advanced tier.
    local advanced = opts.advanced
    if advanced == nil then advanced = difficulty == 'easy' end

    return {
        difficulty = difficulty,
        advanced = advanced == true,
        inputs = type(opts.inputs) == 'table' and opts.inputs or cfg.DefaultInputs or { 'w', 'a', 's', 'd' },
    }
end

-- Callback-style providers are wrapped so the caller still gets a plain return.
-- A provider that never fires its callback would otherwise hang the calling
-- thread forever, so the wait is bounded and a silent provider fails the check.
local function awaitCallback(invoke)
    local resultPromise = promise.new()
    local settled = false

    local function settle(success)
        if settled then return end
        settled = true
        resultPromise:resolve(success == true)
    end

    local invoked = RSBridge.safeCall(invoke, settle)
    if not invoked then return nil end

    SetTimeout((RSBridgeConfig.Minigame and RSBridgeConfig.Minigame.TimeoutMs) or 60000, function()
        settle(false)
    end)

    return Citizen.Await(resultPromise)
end

-- Verified against the installed qbx_vehiclekeys source: PlayMinigame accepts
-- only 'lockpick' or 'hotwire' (anything else is coerced to 'hotwire') and
-- returns a plain boolean. It draws from that resource's embedded 20-game
-- library, so randomisation and per-game balancing stay in its own config.
local function runQbxVehicleKeys(intent, opts)
    if not RSBridge.resourceStarted('qbx_vehiclekeys') then return nil end

    local challengeType = intent == 'lockpick' and 'lockpick' or 'hotwire'

    local ok, result = RSBridge.safeCall(function()
        return exports.qbx_vehiclekeys:PlayMinigame(challengeType, opts.advanced)
    end)
    if not ok then return nil end

    return result == true
end

-- ps-ui is mapped from its published export signatures rather than from source
-- present on this server. Every call goes through safeCall, so a signature that
-- does not match simply falls through to the next provider instead of erroring.
local function runPsUi(intent, opts)
    if not RSBridge.resourceStarted('ps-ui') then return nil end

    if intent == 'lockpick' then
        return awaitCallback(function(cb)
            exports['ps-ui']:Circle(cb, opts.advanced and 2 or 3, opts.advanced and 12 or 10)
        end)
    end

    return awaitCallback(function(cb)
        exports['ps-ui']:Thermite(cb, opts.advanced and 12 or 10, opts.advanced and 4 or 5, opts.advanced and 2 or 3)
    end)
end

-- Guaranteed floor. ox_lib is a hard dependency of rs_bridge, so this provider
-- is always installed and the chain below effectively cannot run dry.
local function runOxLib(intent, opts)
    if not (lib and lib.skillCheck) then return nil end

    -- lib.skillCheck early-returns nil when another skillcheck is already on
    -- screen. That is "provider busy", not a failed attempt, so report it as
    -- unavailable rather than recording a loss the player never played.
    if lib.skillCheckActive and lib.skillCheckActive() then return nil end

    -- Ignition/security work reads as meaningfully harder than a door without
    -- pulling in another dependency: require two consecutive checks.
    local difficulty = opts.difficulty
    if (intent == 'hotwire' or intent == 'hack') and not opts.advanced then
        difficulty = { opts.difficulty, opts.difficulty }
    end

    local ok, result = RSBridge.safeCall(function()
        return lib.skillCheck(difficulty, opts.inputs)
    end)
    if not ok or result == nil then return nil end

    return result == true
end

-- Escape hatch for any minigame resource this bridge does not know about.
-- The configured export receives (intent, options) and must return a boolean.
local function runCustom(intent, opts)
    local custom = RSBridgeConfig.Minigame and RSBridgeConfig.Minigame.Custom
    if type(custom) ~= 'table' then return nil end
    if type(custom.resource) ~= 'string' or type(custom.export) ~= 'string' then return nil end
    if not RSBridge.resourceStarted(custom.resource) then return nil end

    local ok, result = RSBridge.safeCall(function()
        return exports[custom.resource][custom.export](exports[custom.resource], intent, opts)
    end)
    if not ok then return nil end

    return result == true
end

-- Each entry returns nil when its provider is unavailable, so the caller can
-- keep walking the chain. Order is the 'auto' preference order.
local providerOrder = { 'custom', 'qbx_vehiclekeys', 'ps-ui', 'ox_lib' }

local function runProvider(name, intent, opts)
    if name == 'custom' then return runCustom(intent, opts) end
    if name == 'qbx_vehiclekeys' then return runQbxVehicleKeys(intent, opts) end
    if name == 'ps-ui' then return runPsUi(intent, opts) end
    if name == 'ox_lib' then return runOxLib(intent, opts) end
    return nil
end

---Runs a minigame for a semantic intent and reports whether the player passed.
---@param intent 'lockpick'|'hotwire'|'hack'|'generic'
---@param opts table? { advanced = boolean, difficulty = 'easy'|'medium'|'hard', inputs = string[] }
---@return boolean passed
function Minigame(intent, opts)
    intent = normalizeIntent(intent)
    opts = normalizeOptions(opts)

    local cfg = RSBridgeConfig.Minigame or {}
    local provider = cfg.Provider or 'auto'

    -- 'none' is an explicit choice to run without minigames, so the gated
    -- action is allowed through rather than being made impossible.
    if provider == 'none' then return true end

    -- A configured provider is preferred, but never a dead end: if it is not
    -- installed, fall through the rest instead of failing every attempt. A
    -- customer who names a provider they later remove still gets a minigame.
    if provider ~= 'auto' then
        local result = runProvider(provider, intent, opts)
        if result ~= nil then return result end
        RSBridge.debug(('Minigame provider "%s" unavailable, falling back'):format(provider))
    end

    for _, name in ipairs(providerOrder) do
        if name ~= provider then
            local result = runProvider(name, intent, opts)
            if result ~= nil then return result end
        end
    end

    -- Reaching here means nothing returned a verdict. Separate the two causes,
    -- because they deserve opposite answers. If ox_lib is present the install
    -- is fine and this was a transient refusal -- almost always a skillcheck
    -- already on screen -- so fail the attempt. Passing it would hand out a
    -- free lockpick to anyone who can trigger two checks at once.
    if lib and lib.skillCheck then
        RSBridge.debug('Minigame: no provider returned a verdict (a check may already be active)')
        return false
    end

    -- Only a genuinely broken install gets this far, since ox_lib is a hard
    -- dependency. Configurable: true keeps gated actions usable, false refuses.
    RSBridge.debug(_L('minigame_no_resource'))
    return cfg.FallbackResult ~= false
end

---Reports the provider that would run, so callers can degrade gracefully
---instead of assuming a minigame system exists. Returns 'none' when the
---feature is switched off and 'unavailable' when nothing is installed.
---@return string provider
function GetMinigameProvider()
    local cfg = RSBridgeConfig.Minigame or {}
    local provider = cfg.Provider or 'auto'

    if provider == 'none' then return 'none' end

    local function available(name)
        if name == 'ox_lib' then return lib ~= nil and lib.skillCheck ~= nil end
        if name == 'custom' then
            return type(cfg.Custom) == 'table' and RSBridge.resourceStarted(cfg.Custom.resource)
        end
        return RSBridge.resourceStarted(name)
    end

    if provider ~= 'auto' and available(provider) then return provider end

    for _, name in ipairs(providerOrder) do
        if available(name) then return name end
    end

    return 'unavailable'
end

exports('Minigame', Minigame)
exports('GetMinigameProvider', GetMinigameProvider)
