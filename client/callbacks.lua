-- Client half of the callback abstraction.
-- ox_lib is preferred on every framework; the framework paths exist so a
-- server without ox_lib still resolves rather than hanging forever.

local pendingRequests = {}
local requestCounter = 0

-- Client -> server request. Blocks the calling thread and returns the value,
-- and also invokes cb when supplied, so both styles work.
--- Every path below preserves ALL return values.
---
--- ox_lib callbacks, QBCore callbacks and ESX callbacks can each resolve with
--- more than one value, e.g. cb(success, reason, data). Capturing them into a
--- single `result` silently dropped everything after the first, which turns a
--- (false, 'not enough money') answer into a bare `false` with no reason.
function TriggerServerCallback(name, cb, ...)
    if lib and lib.callback then
        local returns = table.pack(lib.callback.await(name, false, ...))
        if cb then cb(table.unpack(returns, 1, returns.n)) end
        return table.unpack(returns, 1, returns.n)
    end

    if RSBridge.Framework == 'qbcore' then
        local core = GetCoreObject()
        if core and core.Functions and core.Functions.TriggerCallback then
            if cb then
                core.Functions.TriggerCallback(name, cb, ...)
                return nil
            end

            local returns, done = nil, false
            core.Functions.TriggerCallback(name, function(...)
                returns = table.pack(...)
                done = true
            end, ...)

            local deadline = GetGameTimer() + 10000
            while not done and GetGameTimer() < deadline do Wait(0) end
            if returns then return table.unpack(returns, 1, returns.n) end
            return nil
        end
    end

    if RSBridge.Framework == 'esx' then
        local ESX = GetCoreObject()
        if ESX and ESX.TriggerServerCallback then
            if cb then
                ESX.TriggerServerCallback(name, cb, ...)
                return nil
            end

            local returns, done = nil, false
            ESX.TriggerServerCallback(name, function(...)
                returns = table.pack(...)
                done = true
            end, ...)

            local deadline = GetGameTimer() + 10000
            while not done and GetGameTimer() < deadline do Wait(0) end
            if returns then return table.unpack(returns, 1, returns.n) end
            return nil
        end
    end

    -- Last resort: paired with the server's RegisterNetEvent fallback.
    requestCounter = requestCounter + 1
    local requestId = ('%s:%d'):format(GetCurrentResourceName(), requestCounter)

    local returns, done = nil, false
    pendingRequests[requestId] = function(...)
        returns = table.pack(...)
        done = true
    end

    TriggerServerEvent(name, requestId, ...)

    local deadline = GetGameTimer() + 10000
    while not done and GetGameTimer() < deadline do Wait(0) end
    pendingRequests[requestId] = nil

    if returns then
        if cb then cb(table.unpack(returns, 1, returns.n)) end
        return table.unpack(returns, 1, returns.n)
    end

    if cb then cb(nil) end
    return nil
end

-- Server -> client request handler.
function RegisterClientCallback(name, fn)
    if lib and lib.callback and lib.callback.register then
        lib.callback.register(name, fn)
        return true
    end

    if RSBridge.Framework == 'qbcore' then
        local core = GetCoreObject()
        if core and core.Functions and core.Functions.CreateClientCallback then
            core.Functions.CreateClientCallback(name, fn)
            return true
        end
    end

    RegisterNetEvent(name, function(...)
        fn(...)
    end)

    return true
end

RegisterNetEvent('rs_bridge:client:callbackResponse', function(requestId, result)
    local resolver = pendingRequests[requestId]
    if resolver then resolver(result) end
end)

exports('TriggerServerCallback', TriggerServerCallback)
exports('RegisterClientCallback', RegisterClientCallback)
