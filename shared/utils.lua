RSBridge = RSBridge or {}

function RSBridge.resourceStarted(name)
    return type(name) == 'string' and GetResourceState(name) == 'started'
end

function RSBridge.debug(message)
    if RSBridgeConfig and RSBridgeConfig.Debug then
        print(('[rs_bridge] %s'):format(tostring(message)))
    end
end

function RSBridge.safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        RSBridge.debug(('safeCall failed: %s'):format(tostring(result)))
        return false, result
    end
    return true, result
end

function RSBridge.normalizeAmount(amount)
    amount = tonumber(amount)
    if not amount or amount < 1 then return 1 end
    return math.floor(amount)
end

function RSBridge.clamp(num, min, max)
    num = tonumber(num) or min
    if num < min then return min end
    if num > max then return max end
    return num
end

function RSBridge.tableHasValue(tbl, value)
    if type(tbl) ~= 'table' then return false end
    for _, v in pairs(tbl) do
        if v == value then return true end
    end
    return false
end

function RSBridge.toNameList(value)
    if type(value) == 'table' then return value end
    if value == nil then return {} end
    return { value }
end

function RSBridge.firstStarted(list)
    for _, name in ipairs(list or {}) do
        if RSBridge.resourceStarted(name) then return name end
    end
    return nil
end

function RSBridge.gradeLevel(grade)
    if type(grade) == 'table' then
        return tonumber(grade.level or grade.grade or grade.id or grade.value or 0) or 0
    end
    return tonumber(grade) or 0
end
