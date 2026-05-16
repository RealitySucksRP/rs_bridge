local registeredCallbacks = {}

function RegisterCallback(name, cb)
    registeredCallbacks[name] = cb

    if lib and lib.callback and lib.callback.register then
        lib.callback.register(name, cb)
        return true
    end

    if RSBridge.Framework == 'qbcore' then
        local core = GetCoreObject()
        if core and core.Functions and core.Functions.CreateCallback then
            core.Functions.CreateCallback(name, cb)
            return true
        end
    end

    if RSBridge.Framework == 'esx' then
        local ESX = GetCoreObject()
        if ESX and ESX.RegisterServerCallback then
            ESX.RegisterServerCallback(name, cb)
            return true
        end
    end

    RegisterNetEvent(name, function(requestId, ...)
        local src = source
        local result = cb(src, ...)
        TriggerClientEvent('rs_bridge:client:callbackResponse', src, requestId, result)
    end)

    return true
end

function TriggerClientCallback(name, src, cb, ...)
    if lib and lib.callback then
        local result = lib.callback.await(name, src, ...)
        if cb then cb(result) end
        return result
    end

    if RSBridge.Framework == 'qbcore' then
        local core = GetCoreObject()
        if core and core.Functions and core.Functions.TriggerClientCallback then
            return core.Functions.TriggerClientCallback(name, src, cb, ...)
        end
    end

    TriggerClientEvent(name, src, ...)
    if cb then cb(nil) end
    return nil
end

exports('RegisterCallback', RegisterCallback)
exports('TriggerClientCallback', TriggerClientCallback)
