RSBridge = RSBridge or {}

function RSBridge.resourceStarted(name)
    return GetResourceState(name) == 'started'
end

function RSBridge.debug(message)
    if RSBridgeConfig and RSBridgeConfig.Debug then
        print(('[rs_bridge] %s'):format(tostring(message)))
    end
end

function RSBridge.safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        RSBridge.debug(('safeCall failed: %s'):format(result))
        return false, result
    end
    return true, result
end

function RSBridge.tableHasValue(tbl, value)
    if type(tbl) ~= 'table' then return false end
    for _, v in pairs(tbl) do
        if v == value then return true end
    end
    return false
end

function RSBridge.normalizeAmount(amount)
    amount = tonumber(amount)
    if not amount or amount < 1 then return 1 end
    return amount
end
