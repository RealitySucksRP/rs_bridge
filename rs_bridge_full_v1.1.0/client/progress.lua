function ProgressBar(data)
    data = data or {}
    local label = data.label or data.text or 'Working...'
    local duration = tonumber(data.duration or data.time) or 1000
    local canCancel = data.canCancel
    if canCancel == nil then canCancel = true end

    if (RSBridgeConfig.Progress.Provider == 'auto' or RSBridgeConfig.Progress.Provider == 'ox_lib') and lib and lib.progressBar then
        return lib.progressBar({
            duration = duration,
            label = label,
            useWhileDead = data.useWhileDead or false,
            canCancel = canCancel,
            disable = data.disable or {
                car = data.disableCar or false,
                move = data.disableMove or false,
                combat = data.disableCombat or true
            },
            anim = data.anim,
            prop = data.prop
        })
    end

    if (RSBridgeConfig.Progress.Provider == 'auto' or RSBridgeConfig.Progress.Provider == 'qb') and RSBridge.resourceStarted('progressbar') then
        local finished = nil
        exports['progressbar']:Progress({
            name = data.name or ('rs_bridge_%s'):format(GetGameTimer()),
            duration = duration,
            label = label,
            useWhileDead = data.useWhileDead or false,
            canCancel = canCancel,
            controlDisables = data.controlDisables or {
                disableMovement = data.disableMove or false,
                disableCarMovement = data.disableCar or false,
                disableMouse = false,
                disableCombat = data.disableCombat ~= false
            },
            animation = data.animation or {},
            prop = data.prop or {},
            propTwo = data.propTwo or {}
        }, function(cancelled)
            finished = not cancelled
        end)

        while finished == nil do Wait(50) end
        return finished
    end

    Wait(duration)
    return true
end

exports('ProgressBar', ProgressBar)
