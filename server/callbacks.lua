local registeredCallbacks = {}

function RegisterCallback(name, cb)
    registeredCallbacks[name] = cb

    if lib and lib.callback and lib.callback.register then
        -- ox_lib responds with TriggerClientEvent(..., callbackResponse(pcall(cb, ...))).
        -- A handler that returns NOTHING puts a nil into that response, which the
        -- transport cannot serialise -- surfacing as the msgpack_unpack "string
        -- expected, got nil" flood with no indication of which callback did it.
        --
        -- Guarantee a non-nil first return, and name the offender so it is
        -- identifiable instead of anonymous.
        lib.callback.register(name, function(...)
            local returns = table.pack(pcall(cb, ...))
            local ok = returns[1]

            if not ok then
                print(('^1[rs_bridge] callback "%s" errored: %s^7'):format(name, tostring(returns[2])))
                return false
            end

            if returns.n < 2 or returns[2] == nil then
                if RSBridge and RSBridge.debug then
                    RSBridge.debug(('callback "%s" returned nil; sending false instead'):format(name))
                end
                return false
            end

            return table.unpack(returns, 2, returns.n)
        end)
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

--- Preserves ALL return values; see the client-side note in client/callbacks.lua.
function TriggerClientCallback(name, src, cb, ...)
    if lib and lib.callback then
        local returns = table.pack(lib.callback.await(name, src, ...))
        if cb then cb(table.unpack(returns, 1, returns.n)) end
        return table.unpack(returns, 1, returns.n)
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


-- Qbox client PlayerData seed without requiring a qbx_core client export/module.
RegisterCallback('rs_bridge:server:getPlayerData', function(source)
    return GetPlayerData(source)
end)
