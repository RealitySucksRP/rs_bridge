local function runQBProgress(data)
    if not RSBridge.resourceStarted('progressbar') then return nil end

    local finished = nil
    exports['progressbar']:Progress({
        name = data.name or ('rs_bridge_%s'):format(GetGameTimer()),
        duration = data.duration,
        label = data.label,
        useWhileDead = data.useWhileDead or false,
        canCancel = data.canCancel,
        controlDisables = data.controlDisables or {
            disableMovement = data.disableMove or false,
            disableCarMovement = data.disableCar or false,
            disableMouse = false,
            disableCombat = data.disableCombat ~= false
        },
        animation = data.animation or data.anim or {},
        prop = data.prop or {},
        propTwo = data.propTwo or {}
    }, function(cancelled)
        finished = not cancelled
    end)

    while finished == nil do Wait(50) end
    return finished
end

-- Each entry returns nil when its provider is unavailable, so the caller can
-- keep walking the chain. Order is the 'auto' preference order.
local providerOrder = { 'progressbar', 'ox_lib', 'mythic_progbar', 'rprogress', 'rs_progressbar' }

local function runProvider(name, data)
    if name == 'ox_lib' then
        if not (lib and lib.progressBar) then return nil end
        return lib.progressBar({
            duration = data.duration,
            label = data.label,
            useWhileDead = data.useWhileDead or false,
            canCancel = data.canCancel,
            disable = data.disable or {
                car = data.disableCar or false,
                move = data.disableMove or false,
                combat = data.disableCombat ~= false
            },
            anim = data.anim,
            prop = data.prop
        })
    end

    if name == 'progressbar' then
        return runQBProgress(data)
    end

    if name == 'mythic_progbar' then
        if not RSBridge.resourceStarted('mythic_progbar') then return nil end
        local finished = nil
        exports['mythic_progbar']:Progress({
            name = data.name or 'rs_bridge',
            duration = data.duration,
            label = data.label,
            useWhileDead = data.useWhileDead or false,
            canCancel = data.canCancel,
            controlDisables = data.controlDisables or {}
        }, function(cancelled)
            finished = not cancelled
        end)
        while finished == nil do Wait(50) end
        return finished
    end

    if name == 'rprogress' then
        if not RSBridge.resourceStarted('rprogress') then return nil end
        local finished = nil
        exports.rprogress:Custom({
            Duration = data.duration,
            Label = data.label,
            DisableControls = data.disableControls or {},
            onComplete = function(cancelled)
                finished = not cancelled
            end
        })
        while finished == nil do Wait(50) end
        return finished
    end

    if name == 'rs_progressbar' then
        if not RSBridge.resourceStarted('rs_progressbar') then return nil end
        local ok, result = RSBridge.safeCall(function()
            return exports.rs_progressbar:ProgressBar(data)
        end)
        if ok then return result end
        return nil
    end

    return nil
end

function ProgressBar(data)
    data = data or {}
    data.label = data.label or data.text or _L('progress_default')
    data.duration = tonumber(data.duration or data.time) or 1000
    if data.canCancel == nil then data.canCancel = true end

    local provider = RSBridgeConfig.Progress.Provider or 'auto'

    -- An explicitly configured provider is preferred, but never a dead end:
    -- if it is not installed, fall through the rest rather than dropping to a
    -- blind Wait() with no visible bar. A customer who configures a provider
    -- they later remove still sees *a* progress bar.
    if provider ~= 'auto' and provider ~= 'none' then
        local result = runProvider(provider, data)
        if result ~= nil then return result end
        RSBridge.debug(('Progress provider "%s" unavailable, falling back'):format(provider))
    end

    if provider ~= 'none' then
        for _, name in ipairs(providerOrder) do
            if name ~= provider then
                local result = runProvider(name, data)
                if result ~= nil then return result end
            end
        end
    end

    Wait(data.duration)
    return true
end

exports('ProgressBar', ProgressBar)
