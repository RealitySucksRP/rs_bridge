RSBridge = RSBridge or {}

-- ---------------------------------------------------------------------------
-- Config normalization
--
-- config.lua is customer-editable and ships unencrypted, so a deleted section
-- or a typo must not take the bridge down. Provider code reads nested values
-- like RSBridgeConfig.Target.DefaultDistance directly; without the section
-- present that is an "attempt to index a nil value" at the first call, which
-- is exactly the hard failure the bridge exists to prevent.
--
-- Fill in anything missing, and never overwrite a value the customer set.
-- This runs immediately after config.lua, before any provider is resolved.
-- ---------------------------------------------------------------------------

RSBridgeConfig = RSBridgeConfig or {}

local configDefaults = {
    Framework = 'auto',
    Debug = true,
    Locale = 'en',
    Notify = {
        Provider = 'auto',
        DefaultType = 'primary',
        DefaultDuration = 5000,
        DefaultTitle = 'Reality Sucks RP'
    },
    Inventory = {
        Provider = 'auto'
    },
    Target = {
        Provider = 'auto',
        DefaultDistance = 2.0
    },
    Progress = {
        Provider = 'auto'
    },
    Fuel = {
        Provider = 'auto'
    },
    Cash = {
        Provider = 'auto',
        Item = 'money'
    },
    Banking = {
        Provider = 'auto'
    },
    Vehicles = {
        OwnershipTable = 'auto',
        IdentifierColumn = 'auto',
        PlateColumn = 'plate',
        PropsColumn = 'auto',
        KeysProvider = 'auto'
    },
    Medical = {
        Provider = 'auto',
        UseResourceEvents = true,
        ReviveHealth = 200,
        HealHealth = 200,
        DefaultArmor = 100
    }
}

for key, value in pairs(configDefaults) do
    if type(value) == 'table' then
        if type(RSBridgeConfig[key]) ~= 'table' then
            RSBridgeConfig[key] = {}
        end
        for subKey, subValue in pairs(value) do
            if RSBridgeConfig[key][subKey] == nil then
                RSBridgeConfig[key][subKey] = subValue
            end
        end
    elseif RSBridgeConfig[key] == nil then
        RSBridgeConfig[key] = value
    end
end

function RSBridge.resourceStarted(name)
    return type(name) == 'string' and GetResourceState(name) == 'started'
end

function RSBridge.debug(message)
    if RSBridgeConfig and RSBridgeConfig.Debug then
        print(('[rs_bridge] %s'):format(tostring(message)))
    end
end

--- Protected call that preserves EVERY return value.
---
--- The old version captured only the first result, so a provider returning
--- (value, extra) silently lost `extra`. Worse, callers writing
---     local ok = RSBridge.safeCall(fn)
--- read `ok` as "the operation succeeded" when it only means "nothing threw" --
--- a provider that legitimately returned false looked like success.
---
--- Returns: didNotThrow, ...providerReturnValues
--- Always distinguish the two: `ok` is transport, the rest is the answer.
function RSBridge.safeCall(fn, ...)
    local returns = table.pack(pcall(fn, ...))

    if not returns[1] then
        RSBridge.debug(('safeCall failed: %s'):format(tostring(returns[2])))
        return false, returns[2]
    end

    return true, table.unpack(returns, 2, returns.n)
end

function RSBridge.normalizeAmount(amount)
    amount = tonumber(amount)
    if not amount or amount < 1 then return 1 end
    return math.floor(amount)
end

---Validates an inventory amount instead of silently coercing it.
---
---normalizeAmount above turns nil, 0, -100 and 'abc' all into 1, so a malformed
---request quietly became a valid one-item mutation rather than being refused.
---That is fine for a display helper and wrong for AddItem/RemoveItem.
---
---nil still means one, because omitting the amount is the idiomatic 'give one'
---form used throughout this catalog and changing it would break every such call.
---Everything else must be a whole number of at least one.
---@param amount any
---@return number? amount, string? reason
function RSBridge.validateAmount(amount)
    if amount == nil then return 1 end

    local n = tonumber(amount)
    if not n then return nil, 'amount is not a number' end
    if n ~= n then return nil, 'amount is NaN' end
    if n < 1 then return nil, 'amount must be at least 1' end
    if n ~= math.floor(n) then return nil, 'amount must be a whole number' end

    return math.floor(n)
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
