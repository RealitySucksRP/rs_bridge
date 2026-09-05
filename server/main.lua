local function ensureQB()
    if RSBridge.Framework ~= 'qbcore' then return nil end
    if not RSBridge.Core and RSBridge.resourceStarted('qb-core') then
        local ok, core = RSBridge.safeCall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok then RSBridge.Core = core end
    end
    return RSBridge.Core
end

local function ensureESX()
    if RSBridge.Framework ~= 'esx' then return nil end
    if RSBridge.Core then return RSBridge.Core end

    if RSBridge.resourceStarted('es_extended') then
        local ok, esx = RSBridge.safeCall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok and esx then RSBridge.Core = esx end
    end

    return RSBridge.Core
end

function GetPlayer(src)
    src = tonumber(src)
    if not src then return nil end

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local ok, player = RSBridge.safeCall(function()
            return exports.qbx_core:GetPlayer(src)
        end)
        if ok then return player end
    end

    if RSBridge.Framework == 'qbcore' then
        local QBCore = ensureQB()
        if QBCore and QBCore.Functions then
            return QBCore.Functions.GetPlayer(src)
        end
    end

    if RSBridge.Framework == 'esx' then
        local ESX = ensureESX()
        if ESX and ESX.GetPlayerFromId then
            -- Handed back in the QB player shape; see wrapESXPlayer below.
            return RSBridge.wrapESXPlayer(src, ESX.GetPlayerFromId(src))
        end
    end

    return nil
end

--- Player inventory in the QB slot shape.
---
--- Consumers read Player.PlayerData.items and iterate it looking for a name plus
--- a quantity. ESX has no PlayerData table at all, so this rebuilds the list from
--- whichever inventory is actually running. Both `amount` (QB) and `count` (ox)
--- are populated, because callers check either -- rs-doctor-agent literally
--- probes both keys.
local function esxPlayerItems(src, xPlayer)
    if GetResourceState('ox_inventory') == 'started' then
        local ok, items = RSBridge.safeCall(function()
            return exports.ox_inventory:GetInventoryItems(src)
        end)
        if ok and type(items) == 'table' then return items end
    end

    if xPlayer and xPlayer.getInventory then
        local ok, inv = RSBridge.safeCall(function() return xPlayer.getInventory() end)
        if ok and type(inv) == 'table' then
            local out = {}
            for i, item in ipairs(inv) do
                local qty = tonumber(item.count) or tonumber(item.amount) or 0
                out[i] = {
                    name = item.name,
                    label = item.label,
                    amount = qty,
                    count = qty,
                    slot = item.slot or i,
                    metadata = item.metadata,
                    info = item.metadata or {}
                }
            end
            return out
        end
    end

    return {}
end

local function normalizeESXPlayerData(src, xPlayer)
    -- ESX docs give getJob() as the accessor; xPlayer.job is the legacy field and
    -- is not guaranteed on newer builds. Prefer the accessor, fall back to the
    -- field, so both old and current ESX resolve.
    local job = {}
    if xPlayer then
        if xPlayer.getJob then
            local ok, result = RSBridge.safeCall(function() return xPlayer.getJob() end)
            if ok and type(result) == 'table' then job = result end
        end
        if not next(job) and type(xPlayer.job) == 'table' then job = xPlayer.job end
    end
    local identifier = nil
    local fullName = nil
    local firstName = nil
    local lastName = nil

    if xPlayer then
        identifier = xPlayer.identifier
        if not identifier and xPlayer.getIdentifier then
            local ok, result = RSBridge.safeCall(function()
                return xPlayer.getIdentifier()
            end)
            if ok then identifier = result end
        end

        if xPlayer.getName then
            local ok, result = RSBridge.safeCall(function()
                return xPlayer.getName()
            end)
            if ok then fullName = result end
        end

        if xPlayer.variables then
            firstName = xPlayer.variables.firstName or xPlayer.variables.firstname
            lastName = xPlayer.variables.lastName or xPlayer.variables.lastname
        end

        if (not firstName or not lastName) and type(fullName) == 'string' then
            firstName, lastName = fullName:match('^(%S+)%s+(.+)$')
            firstName = firstName or fullName
            lastName = lastName or ''
        end
    end

    local state = Player(src) and Player(src).state
    local dead = state and state.isDead == true or false

    return {
        source = src,
        citizenid = identifier,
        identifier = identifier,
        dead = dead,
        charinfo = {
            firstname = firstName,
            lastname = lastName,
            name = fullName
        },
        job = {
            name = job.name or 'unemployed',
            label = job.label or _L('unemployed'),
            grade = {
                level = job.grade or 0,
                name = job.grade_label or job.grade_name or _L('no_job')
            },
            onduty = true
        },
        gang = { name = 'none', label = _L('no_gang'), grade = { level = 0, name = _L('no_gang') } },
        money = {
            cash = xPlayer and xPlayer.getMoney and xPlayer.getMoney() or 0,
            bank = xPlayer and xPlayer.getAccount and ((xPlayer.getAccount('bank') or {}).money or 0) or 0
        },
        metadata = { dead = dead, isdead = dead },
        items = esxPlayerItems(src, xPlayer)
    }
end

--- Wraps an ESX xPlayer in the QBCore player shape.
---
--- Resources across the RS suite call GetPlayer(src) and then use the QB object
--- shape on the result -- Player.PlayerData.citizenid, Player.Functions.AddItem,
--- Player.Functions.AddMoney and so on. An ESX xPlayer has neither a PlayerData
--- table nor a Functions table, so every one of those calls was a hard error the
--- moment the resource ran on ESX.
---
--- The shape is normalised HERE, on the ESX branch only, rather than by editing
--- the ~99 call sites spread across those resources. That matters for two
--- reasons: the Qbox and QBCore paths in GetPlayer are left completely
--- untouched, so nothing that works today can regress; and any resource added
--- later gets ESX support for free without knowing this shim exists.
---
--- PlayerData is resolved through __index on every access rather than captured
--- once, so a caller that reads money or job after a transaction sees current
--- values instead of a stale snapshot.
---
--- `__esx` exposes the real xPlayer for anything that genuinely needs ESX-native
--- calls.
local function wrapESXPlayer(src, xPlayer)
    if not xPlayer then return nil end

    local Functions = {}

    function Functions.AddMoney(account, amount, reason)
        return AddMoney(src, account, amount, reason)
    end

    function Functions.RemoveMoney(account, amount, reason)
        return RemoveMoney(src, account, amount, reason)
    end

    function Functions.SetMoney(account, amount, reason)
        return SetMoney(src, account, amount, reason)
    end

    -- QB order is (item, amount, slot, metadata); the bridge takes
    -- (src, item, amount, metadata, slot). Do not "tidy" these into the same
    -- order -- the mismatch is deliberate and load-bearing.
    function Functions.AddItem(item, amount, slot, metadata)
        return AddItem(src, item, amount, metadata, slot)
    end

    function Functions.RemoveItem(item, amount, slot)
        return RemoveItem(src, item, amount, slot)
    end

    --- QB returns the item table (or nil). GetItem already returns that shape.
    function Functions.GetItemByName(item)
        return GetItem(src, item)
    end

    function Functions.SetMetaData(key, value)
        if not key then return false end

        if xPlayer.setMeta then
            local ok = RSBridge.safeCall(function() return xPlayer.setMeta(key, value) end)
            if ok then return true end
        end

        -- Older ESX builds have no metadata store; fall back to the player
        -- statebag so the value at least persists for the session.
        local ply = Player(src)
        if ply and ply.state then
            ply.state:set(key, value, true)
            return true
        end

        return false
    end

    function Functions.GetMetaData(key)
        if xPlayer.getMeta then
            local ok, result = RSBridge.safeCall(function() return xPlayer.getMeta(key) end)
            if ok then return result end
        end

        local ply = Player(src)
        if ply and ply.state then return ply.state[key] end
        return nil
    end

    return setmetatable({ __esx = xPlayer, Functions = Functions }, {
        __index = function(_, key)
            if key == 'PlayerData' then
                return normalizeESXPlayerData(src, xPlayer)
            end
            -- Anything the shim does not model falls through to the real
            -- xPlayer, so ESX-native fields still resolve.
            return xPlayer[key]
        end
    })
end

RSBridge.wrapESXPlayer = wrapESXPlayer

function GetPlayerData(src)
    local player = GetPlayer(src)

    if RSBridge.Framework == 'esx' then
        -- GetPlayer now hands back the QB-shaped wrapper, so unwrap to the real
        -- xPlayer first: normalizeESXPlayerData reads ESX-native fields
        -- (identifier, getName, variables, job) off it directly.
        return normalizeESXPlayerData(src, player and player.__esx or player)
    end

    if player and player.PlayerData then return player.PlayerData end

    return {
        source = src,
        citizenid = nil,
        charinfo = {},
        job = { name = 'unemployed', label = _L('unemployed'), grade = { level = 0, name = _L('no_job') }, onduty = false },
        gang = { name = 'none', label = _L('no_gang'), grade = { level = 0, name = _L('no_gang') } },
        money = { cash = 0, bank = 0, crypto = 0 },
        metadata = {}
    }
end

function GetCitizenId(src)
    local data = GetPlayerData(src)
    return data.citizenid or data.citizenId or data.identifier
end

function GetCharInfo(src)
    return GetPlayerData(src).charinfo or {}
end

function GetJob(src)
    return GetPlayerData(src).job or { name = 'unemployed', grade = { level = 0 } }
end

function GetGang(src)
    return GetPlayerData(src).gang or { name = 'none', grade = { level = 0 } }
end

function HasJob(src, jobNames, minGrade)
    local job = GetJob(src)
    local names = RSBridge.toNameList(jobNames)
    if #names > 0 and not RSBridge.tableHasValue(names, job.name) then return false end

    minGrade = tonumber(minGrade or 0) or 0
    return RSBridge.gradeLevel(job.grade) >= minGrade
end

--- Framework-neutral permission check, ACE-first.
---
--- Current Qbox marks its own HasPermission/GetPermission/AddPermission/
--- RemovePermission as DEPRECATED and directs servers to ACE permissions, so ACE
--- is the canonical path here rather than a per-framework special case. It also
--- works identically on QBCore, ESX and standalone, and covers txAdmin plus any
--- server.cfg grant.
---
--- The framework check is kept as a secondary source so existing QB/Qbox
--- permission grants still resolve while a server migrates to ACE.
local function aceAllows(src, permission)
    if src == 0 then return true end -- server console
    local name = tostring(permission or '')
    if name == '' then return false end

    if IsPlayerAceAllowed(src, name) then return true end
    -- Accept both bare and namespaced spellings: "admin" / "rs.admin" / "command.admin"
    if IsPlayerAceAllowed(src, 'rs.' .. name) then return true end
    if IsPlayerAceAllowed(src, 'command.' .. name) then return true end

    -- Qbox's canonical administration principal is the GROUP itself. A server
    -- that only writes `add_principal <id> group.admin`, without also granting
    -- `add_ace group.admin admin allow`, would fail every check above even
    -- though its owner is plainly an admin. Purely additive: this can let a
    -- check pass, never make one fail.
    if IsPlayerAceAllowed(src, 'group.' .. name) then return true end
    return false
end

function HasPermission(src, permission)
    src = tonumber(src)
    if not src then return false end
    if aceAllows(src, permission) then return true end

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local ok, result = RSBridge.safeCall(function()
            return exports.qbx_core:HasPermission(src, permission)
        end)
        if ok and result == true then return true end
    end

    if RSBridge.Framework == 'qbcore' then
        local QBCore = ensureQB()
        if QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
            local ok, result = RSBridge.safeCall(function()
                return QBCore.Functions.HasPermission(src, permission)
            end)
            if ok and result == true then return true end
        end
    end

    -- ESX has no permission system; its group is the closest equivalent.
    if RSBridge.Framework == 'esx' then
        return HasGroup(src, permission) == true
    end

    return false
end

--- True when the player satisfies ANY of the supplied permissions.
function HasAnyPermission(src, permissions)
    if type(permissions) ~= 'table' then return HasPermission(src, permissions) end
    for _, permission in ipairs(permissions) do
        if HasPermission(src, permission) then return true end
    end
    return false
end

--- Coarse label for UI. Returns the highest matching tier, or 'user'.
function GetPermission(src)
    for _, level in ipairs({ 'god', 'superadmin', 'admin', 'mod' }) do
        if HasPermission(src, level) then return level end
    end
    return 'user'
end

function HasGroup(src, groupNames, minGrade)
    local names = RSBridge.toNameList(groupNames)

    -- An empty filter is a MISSING filter, not "any group".
    --
    -- This used to fall through to HasJob with no names, and HasJob skips its
    -- name check entirely when the list is empty -- leaving `grade >= 0`, which
    -- is true for essentially every player. A mistyped or absent config value
    -- therefore authorised everyone, silently, on an authorisation call.
    if #names == 0 then
        RSBridge.debug('HasGroup called with an empty group filter; refusing')
        return false
    end

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        -- Qbox takes HasGroup(source, filter) -- TWO arguments. The grade is
        -- encoded INSIDE the filter as { groupName = minGrade }, not passed as a
        -- third argument. Passing a third argument meant the grade restriction
        -- was silently ignored, so a grade-0 member passed a "boss only" check.
        local grade = tonumber(minGrade)
        for _, group in ipairs(names) do
            local filter = group
            if grade and grade > 0 then filter = { [group] = grade } end

            local ok, result = RSBridge.safeCall(function()
                return exports.qbx_core:HasGroup(src, filter)
            end)
            if ok and result == true then return true end
        end
    end

    if RSBridge.Framework == 'esx' then
        local xPlayer = GetPlayer(src)
        local group = xPlayer and xPlayer.getGroup and xPlayer.getGroup() or nil
        if group and RSBridge.tableHasValue(names, group) then return true end
    end

    -- On QBCore a gang is a separate structure from a job, and only jobs were
    -- ever checked here -- so a gang-owned account rejected its own members and
    -- gang permissions did not behave as advertised. Qbox needs no equivalent
    -- branch: qbx_core's own HasGroup already merges jobs and gangs.
    if RSBridge.Framework == 'qbcore' then
        local gang = GetGang(src)
        if gang and gang.name and gang.name ~= 'none'
            and RSBridge.tableHasValue(names, gang.name)
            and RSBridge.gradeLevel(gang.grade) >= (tonumber(minGrade) or 0) then
            return true
        end
    end

    -- `names` rather than groupNames: already normalised, and never empty by
    -- the guard above.
    return HasJob(src, names, minGrade)
end

function GetMoney(src, account)
    account = account or 'cash'

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local ok, amount = RSBridge.safeCall(function()
            return exports.qbx_core:GetMoney(src, account)
        end)
        if ok and amount ~= false then return tonumber(amount) or 0 end
    end

    local player = GetPlayer(src)
    if not player then return 0 end

    if RSBridge.Framework == 'esx' then
        local esxAccount = (account == 'cash') and 'money' or account
        local acc = player.getAccount and player.getAccount(esxAccount)
        if acc then return tonumber(acc.money) or 0 end
        if esxAccount == 'money' and player.getMoney then return player.getMoney() or 0 end
        return 0
    end

    if player.Functions and player.Functions.GetMoney then
        return player.Functions.GetMoney(account) or 0
    end

    local data = player.PlayerData or {}
    return data.money and data.money[account] or 0
end

local function addMoneyInternal(src, account, amount, reason)
    account = account or 'cash'
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local ok, result = RSBridge.safeCall(function()
            return exports.qbx_core:AddMoney(src, account, amount, reason or 'rs_bridge')
        end)
        if ok then return result == true end
    end

    local player = GetPlayer(src)
    if not player then return false end

    if RSBridge.Framework == 'esx' then
        local esxAccount = (account == 'cash') and 'money' or account
        if player.addAccountMoney then
            player.addAccountMoney(esxAccount, amount, reason or 'rs_bridge')
            return true
        end
        if esxAccount == 'money' and player.addMoney then player.addMoney(amount) return true end
        return false
    end

    if player.Functions and player.Functions.AddMoney then
        return player.Functions.AddMoney(account, amount, reason or 'rs_bridge')
    end

    return false
end

local function removeMoneyInternal(src, account, amount, reason)
    account = account or 'cash'
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local ok, result = RSBridge.safeCall(function()
            return exports.qbx_core:RemoveMoney(src, account, amount, reason or 'rs_bridge')
        end)
        if ok then return result == true end
    end

    local player = GetPlayer(src)
    if not player then return false end

    if RSBridge.Framework == 'esx' then
        local esxAccount = (account == 'cash') and 'money' or account
        if player.removeAccountMoney then
            player.removeAccountMoney(esxAccount, amount, reason or 'rs_bridge')
            return true
        end
        if esxAccount == 'money' and player.removeMoney then player.removeMoney(amount) return true end
        return false
    end

    if player.Functions and player.Functions.RemoveMoney then
        return player.Functions.RemoveMoney(account, amount, reason or 'rs_bridge')
    end

    return false
end

-- ============================================================
-- MONEY AUDIT
--
-- Fifteen RS resources moved money with no trail whatsoever. Rather than edit
-- every call site in every one of them, the trail is taken HERE, at the single
-- boundary they all cross. GetInvokingResource() inside the audit layer names
-- whichever resource made the call, so attribution is automatic and any
-- resource added later is covered without touching it.
--
-- Audit is best-effort and wrapped, so a webhook problem can never fail or roll
-- back a money movement that already happened.
-- ============================================================
local function auditMoney(direction, src, account, amount, reason, ok)
    RSBridge.safeCall(function()
        Audit(direction == 'add' and 'money' or 'money', {
            title   = direction == 'add' and 'Money added' or 'Money removed',
            actor   = src,
            amount  = amount,
            account = account,
            reason  = reason or 'rs_bridge',
            ok      = ok,
            resource = GetInvokingResource() or 'rs_bridge',
        })
    end)
end

-- Every return value is preserved with table.pack/unpack, NOT captured into a
-- single local. Callers in this catalog do rely on multi-return -- rs-garage's
-- Bridge.RemoveMoney answers `true, 'free'` -- and quietly dropping the second
-- value would change money behaviour while looking harmless. Auditing must be
-- observation only: same returns, same order, same count.
function AddMoney(src, account, amount, reason)
    local returns = table.pack(addMoneyInternal(src, account, amount, reason))
    auditMoney('add', src, account or 'cash', tonumber(amount) or 0, reason, returns[1])
    return table.unpack(returns, 1, returns.n)
end

function RemoveMoney(src, account, amount, reason)
    local returns = table.pack(removeMoneyInternal(src, account, amount, reason))
    auditMoney('remove', src, account or 'cash', tonumber(amount) or 0, reason, returns[1])
    return table.unpack(returns, 1, returns.n)
end


function SetMoney(src, account, amount, reason)
    account = account or 'cash'
    amount = tonumber(amount) or 0
    if amount < 0 then return false end

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local ok, result = RSBridge.safeCall(function()
            return exports.qbx_core:SetMoney(src, account, amount, reason or 'rs_bridge')
        end)
        if ok then return result == true end
    end

    local player = GetPlayer(src)
    if not player then return false end

    if RSBridge.Framework == 'esx' then
        local esxAccount = (account == 'cash') and 'money' or account
        if player.setAccountMoney then
            player.setAccountMoney(esxAccount, amount, reason or 'rs_bridge')
            return true
        end
        if esxAccount == 'money' and player.setMoney then player.setMoney(amount) return true end
        return false
    end

    if player.Functions and player.Functions.SetMoney then
        return player.Functions.SetMoney(account, amount, reason or 'rs_bridge')
    end

    return false
end

function Notify(src, message, notifyType, duration, title)
    src = tonumber(src)
    if not src then return false end

    notifyType = notifyType or RSBridgeConfig.Notify.DefaultType
    duration = duration or RSBridgeConfig.Notify.DefaultDuration

    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local qboxType = notifyType == 'primary' and 'inform' or notifyType
        local ok = RSBridge.safeCall(function()
            exports.qbx_core:Notify(src, message, qboxType, duration)
        end)
        if ok then return true end
    end

    if RSBridge.Framework == 'qbcore' then
        local qbType = notifyType == 'inform' and 'primary' or notifyType
        TriggerClientEvent('QBCore:Notify', src, message, qbType, duration)
        return true
    end

    if RSBridge.Framework == 'esx' then
        TriggerClientEvent('esx:showNotification', src, message)
        return true
    end

    TriggerClientEvent('rs_bridge:client:notify', src, message, notifyType, duration, title)
    return true
end

-- Job / gang registries.
--   QBCore.Shared.Jobs  -> exports.qbx_core:GetJobs()
--   QBCore.Shared.Gangs -> exports.qbx_core:GetGangs()
-- Note that Qbox grade keys are numbers where QBCore used strings, so callers
-- must not assume the key type; use RSBridge.gradeLevel on grade values.
local function registryFor(qbxFetch, qbSharedKey)
    if RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_core') then
        local ok, result = RSBridge.safeCall(qbxFetch)
        if ok and type(result) == 'table' then return result end
    end

    if RSBridge.Framework == 'qbcore' then
        local core = GetCoreObject()
        local shared = core and core.Shared and core.Shared[qbSharedKey]
        if type(shared) == 'table' then return shared end
    end

    if RSBridge.Framework == 'esx' and qbSharedKey == 'Jobs' then
        local ESX = GetCoreObject()
        if ESX and ESX.GetJobs then
            local ok, result = RSBridge.safeCall(function() return ESX.GetJobs() end)
            if ok and type(result) == 'table' then return result end
        end
    end

    return {}
end

function GetJobs()
    return registryFor(function() return exports.qbx_core:GetJobs() end, 'Jobs')
end

function GetGangs()
    return registryFor(function() return exports.qbx_core:GetGangs() end, 'Gangs')
end

-- Startup diagnostics. A missing optional provider must read as a clear
-- message, never as a nil index later in a gameplay call.
CreateThread(function()
    Wait(2500)

    local framework = RSBridge.Framework
    print(('[rs_bridge] framework: %s'):format(framework))

    -- qbx_core's qb-core compatibility shim is convar-gated (qbx:enableBridge,
    -- default true). Any resource still reaching for exports['qb-core'] works
    -- only while that stays enabled, so surface its state rather than letting
    -- a future config change turn into a pile of nil-index errors.
    if framework == 'qbox' then
        local enabled = GetConvar('qbx:enableBridge', 'true')
        print(('[rs_bridge] qbx:enableBridge = %s'):format(enabled))
        if enabled ~= 'true' then
            print('[rs_bridge] The qb-core compatibility shim is DISABLED. Any resource calling exports[\'qb-core\'] directly will fail.')
            print('[rs_bridge] rs_bridge itself does not need the shim; it uses native qbx_core exports.')
        end
    end

    if framework == 'standalone' then
        print('[rs_bridge] No supported framework detected. Supported: qbx_core (Qbox), qb-core (QBCore), es_extended (ESX).')
        print('[rs_bridge] Framework-dependent features will be inactive until one is installed, or set RSBridgeConfig.Framework manually.')
    end

    local inventory = GetInventoryProvider and GetInventoryProvider() or 'unknown'
    print(('[rs_bridge] inventory: %s'):format(inventory))
    if inventory == 'framework' and framework == 'standalone' then
        print('[rs_bridge] No supported inventory provider detected. Supported: ox_inventory, qs-inventory, codem-inventory, ps-inventory, tgiann-inventory, core_inventory, origen_inventory.')
        print('[rs_bridge] Set RSBridgeConfig.Inventory.Provider manually if you use a custom inventory.')
    end

    local keys = GetVehicleKeysProvider and GetVehicleKeysProvider() or 'none'
    print(('[rs_bridge] vehicle keys: %s'):format(keys))

    local schema = GetVehicleSchema and GetVehicleSchema() or nil
    if schema then
        print(('[rs_bridge] vehicle ownership: %s (%s / %s)'):format(schema.table, schema.identifier, schema.plate))
    end
end)

exports('GetPlayer', GetPlayer)
exports('GetPlayerData', GetPlayerData)
exports('GetCitizenId', GetCitizenId)
exports('GetCharInfo', GetCharInfo)
exports('GetJob', GetJob)
exports('GetGang', GetGang)
exports('GetJobs', GetJobs)
exports('GetGangs', GetGangs)
exports('HasJob', HasJob)
exports('HasGroup', HasGroup)
exports('HasPermission', HasPermission)
exports('HasAnyPermission', HasAnyPermission)
exports('GetPermission', GetPermission)
exports('GetMoney', GetMoney)
exports('AddMoney', AddMoney)
exports('RemoveMoney', RemoveMoney)
exports('SetMoney', SetMoney)
exports('Notify', Notify)
