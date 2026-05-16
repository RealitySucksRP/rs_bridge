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

function ProgressBar(data)
    data = data or {}
    data.label = data.label or data.text or _L('progress_default')
    data.duration = tonumber(data.duration or data.time) or 1000
    if data.canCancel == nil then data.canCancel = true end

    local provider = RSBridgeConfig.Progress.Provider or 'auto'

    if (provider == 'auto' or provider == 'ox_lib') and lib and lib.progressBar then
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

    if provider == 'auto' or provider == 'progressbar' then
        local result = runQBProgress(data)
        if result ~= nil then return result end
    end

    if (provider == 'auto' or provider == 'mythic_progbar') and RSBridge.resourceStarted('mythic_progbar') then
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

    if (provider == 'auto' or provider == 'rprogress') and RSBridge.resourceStarted('rprogress') then
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

    if (provider == 'auto' or provider == 'rs_progressbar') and RSBridge.resourceStarted('rs_progressbar') then
        local ok, result = RSBridge.safeCall(function()
            return exports.rs_progressbar:ProgressBar(data)
        end)
        if ok then return result end
    end

    Wait(data.duration)
    return true
end

exports('ProgressBar', ProgressBar)
