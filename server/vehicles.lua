-- Vehicle ownership + keys abstraction.
-- Ownership schemas differ per ecosystem, so resources should never hardcode
-- a table name. Ask the bridge for the schema, or use the helpers below.

local keysOrder = {
    'qbx_vehiclekeys',
    'qb-vehiclekeys',
    'wasabi_carlock',
    'mk_vehiclekeys',
    'cd_garage'
}

local cachedKeysProvider = nil

local function resolveKeysProvider()
    local forced = RSBridgeConfig.Vehicles and RSBridgeConfig.Vehicles.KeysProvider or 'auto'
    if forced ~= 'auto' then return forced end

    if cachedKeysProvider and (cachedKeysProvider == 'none' or RSBridge.resourceStarted(cachedKeysProvider)) then
        return cachedKeysProvider
    end

    cachedKeysProvider = RSBridge.firstStarted(keysOrder) or 'none'
    return cachedKeysProvider
end

AddEventHandler('onResourceStart', function(resource)
    for _, name in ipairs(keysOrder) do
        if resource == name then cachedKeysProvider = nil return end
    end
end)

-- Returns the ownership schema for the running framework.
-- Resources build their queries from this instead of assuming a layout.
function GetVehicleSchema()
    local cfg = RSBridgeConfig.Vehicles or {}
    local isESX = RSBridge.Framework == 'esx'

    local table_ = cfg.OwnershipTable
    if not table_ or table_ == 'auto' then
        table_ = isESX and 'owned_vehicles' or 'player_vehicles'
    end

    local idColumn = cfg.IdentifierColumn
    if not idColumn or idColumn == 'auto' then
        idColumn = isESX and 'owner' or 'citizenid'
    end

    local propsColumn = cfg.PropsColumn
    if not propsColumn or propsColumn == 'auto' then
        propsColumn = isESX and 'vehicle' or 'mods'
    end

    return {
        table = table_,
        identifier = idColumn,
        plate = cfg.PlateColumn or 'plate',
        props = propsColumn,
        framework = RSBridge.Framework
    }
end

local function qbxVehiclesAvailable()
    return RSBridge.Framework == 'qbox' and RSBridge.resourceStarted('qbx_vehicles')
end

-- true when the given source owns the plate.
--
-- On Qbox this goes through qbx_vehicles exports. The Qbox developer guide is
-- explicit that resources must not query core-owned tables directly, and
-- qbx_vehicles is the owner of player_vehicles. QBCore and ESX have no
-- equivalent export layer, so those fall back to a direct query.
function DoesPlayerOwnVehicle(src, plate)
    if not plate then return false end
    plate = tostring(plate):gsub('^%s*(.-)%s*$', '%1')

    local identifier = GetCitizenId(src)
    if not identifier then return false end

    if qbxVehiclesAvailable() then
        local ok, owned = RSBridge.safeCall(function()
            local vehicleId = exports.qbx_vehicles:GetVehicleIdByPlate(plate)
            if not vehicleId then return false end
            local vehicle = exports.qbx_vehicles:GetPlayerVehicle(vehicleId, { citizenid = identifier })
            return vehicle ~= nil
        end)
        if ok then return owned == true end

    -- Qbox: qbx_vehicles OWNS player_vehicles. If its API is installed but the
    -- call failed, reading that table directly would mean silently depending on
    -- another resource's schema -- which the Qbox developer guide explicitly
    -- warns against. Report the capability as unavailable instead of guessing.
        RSBridge.debug('DoesPlayerOwnVehicle: qbx_vehicles call failed; refusing raw player_vehicles read')
        return false
    end

    local schema = GetVehicleSchema()
    local query = ('SELECT 1 FROM `%s` WHERE `%s` = ? AND TRIM(`%s`) = ? LIMIT 1')
        :format(schema.table, schema.identifier, schema.plate)

    local ok, result = RSBridge.safeCall(function()
        return MySQL.scalar.await(query, { identifier, plate })
    end)

    return ok and result ~= nil
end

-- Owned vehicles for a player, normalized to:
--   { id, plate, model, garage, state, props }
-- props is a decoded ox_lib properties table where the source provides one.
function GetOwnedVehicles(src)
    local identifier = GetCitizenId(src)
    if not identifier then return {} end

    if qbxVehiclesAvailable() then
        local ok, rows = RSBridge.safeCall(function()
            return exports.qbx_vehicles:GetPlayerVehicles({ citizenid = identifier })
        end)

        if ok and type(rows) == 'table' then
            local out = {}
            for i = 1, #rows do
                local row = rows[i]
                local props = row.props or {}
                out[i] = {
                    id = row.id,
                    -- qbx_vehicles does not return a plate column; the plate
                    -- lives inside the ox_lib properties table.
                    plate = props.plate,
                    model = row.modelName,
                    garage = row.garage,
                    state = row.state,
                    props = props
                }
            end
            return out
        end
    end

    local schema = GetVehicleSchema()
    local query = ('SELECT * FROM `%s` WHERE `%s` = ?')
        :format(schema.table, schema.identifier)

    local ok, rows = RSBridge.safeCall(function()
        return MySQL.query.await(query, { identifier })
    end)

    if not ok or type(rows) ~= 'table' then return {} end

    local out = {}
    for i = 1, #rows do
        local row = rows[i]
        local props = row[schema.props]
        if type(props) == 'string' then
            local decodeOk, decoded = pcall(json.decode, props)
            props = (decodeOk and type(decoded) == 'table') and decoded or {}
        end

        out[i] = {
            id = row.id,
            plate = row[schema.plate],
            model = row.vehicle or row.model,
            garage = row.garage,
            state = row.state,
            props = props or {},
            raw = row
        }
    end

    return out
end

-- qbx_vehiclekeys exposes two distinct signatures:
--   exports.qbx_vehiclekeys:GiveKeys(source, entity, skipNotification)
--   exports['qb-vehiclekeys']:GiveKeys(source, plate)   -- QB compat namespace
-- The compat namespace is registered by qbx_vehiclekeys itself through
-- __cfx_export_qb-vehiclekeys_* handlers (convar qbx_vehiclekeys:enableBridge,
-- default true), so it resolves even with no qb-vehiclekeys resource present.
-- The entity path is preferred: the plate path scans all vehicles behind a
-- 500ms wait.
--- Resolve a vehicle ENTITY for the Qbox key API.
---
--- qbx_vehiclekeys is entity-based on every call:
---     GiveKeys(source, vehicle, skipNotification?)
---     RemoveKeys(source, vehicle, skipNotification?)
---     HasKeys(src, vehicle) -> boolean
--- The plate-based qb-vehiclekeys namespace is only a compatibility shim, so it
--- is used strictly as a last resort after the entity path cannot be resolved.
local function resolveKeyEntity(plate, vehicleNetId)
    if vehicleNetId then
        local entity = NetworkGetEntityFromNetworkId(vehicleNetId)
        if entity and entity ~= 0 and DoesEntityExist(entity) then return entity end
    end

    if not plate or plate == '' then return nil end

    local wanted = tostring(plate):gsub('%s+', ''):upper()
    for _, entity in ipairs(GetAllVehicles() or {}) do
        local text = GetVehicleNumberPlateText(entity)
        if text and tostring(text):gsub('%s+', ''):upper() == wanted then return entity end
    end

    return nil
end

local function giveQbxKeys(src, plate, vehicleNetId)
    local entity = resolveKeyEntity(plate, vehicleNetId)

    if entity then
        local ok, result = RSBridge.safeCall(function()
            return exports.qbx_vehiclekeys:GiveKeys(src, entity, true)
        end)
        if ok and result ~= false then return true end
    end

    if not plate then return false end

    -- Compatibility shim only; entity path above is canonical.
    local ok, result = RSBridge.safeCall(function()
        return exports['qb-vehiclekeys']:GiveKeys(src, plate)
    end)
    return ok and result ~= false
end

local function removeQbxKeys(src, plate, vehicleNetId)
    local entity = resolveKeyEntity(plate, vehicleNetId)

    if entity then
        local ok, result = RSBridge.safeCall(function()
            return exports.qbx_vehiclekeys:RemoveKeys(src, entity, true)
        end)
        if ok and result ~= false then return true end
    end

    if not plate then return false end

    local ok, result = RSBridge.safeCall(function()
        return exports['qb-vehiclekeys']:RemoveKeys(src, plate)
    end)
    return ok and result ~= false
end

--- Does this player already hold keys for the vehicle?
--- Returns nil when no provider can answer, so callers can tell
--- "no keys" apart from "cannot determine".
local function hasQbxKeys(src, plate, vehicleNetId)
    local entity = resolveKeyEntity(plate, vehicleNetId)
    if not entity then return nil end

    local ok, result = RSBridge.safeCall(function()
        return exports.qbx_vehiclekeys:HasKeys(src, entity)
    end)
    if ok then return result == true end
    return nil
end

function GiveVehicleKeys(src, plate, vehicleNetId)
    local provider = resolveKeysProvider()
    if provider == 'none' then
        RSBridge.debug('GiveVehicleKeys skipped; no keys provider installed')
        return false
    end

    -- `ok` only means "nothing threw". Keep it separate from the provider's own
    -- answer so a provider that legitimately refused is not reported as success.
    local ok, result = RSBridge.safeCall(function()
        if provider == 'qbx_vehiclekeys' then
            return giveQbxKeys(src, plate, vehicleNetId)
        elseif provider == 'qb-vehiclekeys' then
            -- qb-vehiclekeys exposes authoritative SERVER functions; prefer them
            -- over firing a client event the player could simply never handle.
            local sok, sresult = RSBridge.safeCall(function()
                return exports['qb-vehiclekeys']:GiveKeys(src, plate)
            end)
            if sok and sresult ~= false then return true end
            TriggerClientEvent('qb-vehiclekeys:client:AddKeys', src, plate)
            return true
        elseif provider == 'wasabi_carlock' then
            exports.wasabi_carlock:GiveKey(src, plate)
            return true
        elseif provider == 'mk_vehiclekeys' then
            TriggerClientEvent('mk_vehiclekeys:addKey', src, plate)
            return true
        elseif provider == 'cd_garage' then
            TriggerEvent('cd_garage:AddKeys', src, plate)
            return true
        end
        return false
    end)

    return ok and result ~= false
end

--- vehicleNetId is optional and additive: existing (src, plate) callers keep
--- working, but passing it lets the canonical entity path be used.
function RemoveVehicleKeys(src, plate, vehicleNetId)
    local provider = resolveKeysProvider()
    if provider == 'none' then return false end

    local ok, result = RSBridge.safeCall(function()
        if provider == 'qbx_vehiclekeys' then
            return removeQbxKeys(src, plate, vehicleNetId)
        elseif provider == 'qb-vehiclekeys' then
            local sok, sresult = RSBridge.safeCall(function()
                return exports['qb-vehiclekeys']:RemoveKeys(src, plate)
            end)
            if sok and sresult ~= false then return true end
            TriggerClientEvent('qb-vehiclekeys:client:RemoveKeys', src, plate)
            return true
        elseif provider == 'wasabi_carlock' then
            exports.wasabi_carlock:RemoveKey(src, plate)
            return true
        elseif provider == 'mk_vehiclekeys' then
            TriggerClientEvent('mk_vehiclekeys:removeKey', src, plate)
            return true
        end
        return false
    end)

    return ok and result ~= false
end

--- Does the player hold keys for this vehicle?
--- @return boolean|nil  nil when no provider can answer.
function HasVehicleKeys(src, plate, vehicleNetId)
    local provider = resolveKeysProvider()
    if provider == 'none' then return nil end

    if provider == 'qbx_vehiclekeys' then
        return hasQbxKeys(src, plate, vehicleNetId)
    end

    if provider == 'qb-vehiclekeys' then
        local ok, result = RSBridge.safeCall(function()
            return exports['qb-vehiclekeys']:HasKeys(src, plate)
        end)
        if ok then return result == true end
    end

    return nil
end

function GetVehicleKeysProvider()
    return resolveKeysProvider()
end

exports('GetVehicleSchema', GetVehicleSchema)
exports('DoesPlayerOwnVehicle', DoesPlayerOwnVehicle)
exports('GetOwnedVehicles', GetOwnedVehicles)
exports('GiveVehicleKeys', GiveVehicleKeys)
exports('RemoveVehicleKeys', RemoveVehicleKeys)
exports('HasVehicleKeys', HasVehicleKeys)
exports('GetVehicleKeysProvider', GetVehicleKeysProvider)

---Vehicle class WITHOUT the vehicle needing to exist or be spawned.
---
---GetVehicleClass is a client native, so every server-side check written against
---it silently does nothing -- the pcall fails and the caller quietly treats the
---vehicle as having no class. Callers that fail OPEN on that (a garage blacklist,
---for instance) stop blocking anything at all. This answers from static data
---instead, generated from the GTA V dumps into shared/vehicledata.lua.
---@param model string|number model name or hash
---@return number? class
function GetVehicleClassByModel(model)
    if not RSVehicleData then return nil end
    return RSVehicleData.GetClass(model)
end

exports('GetVehicleClassByModel', GetVehicleClassByModel)

--------------------------------------------------------------------------------
-- Owned-vehicle access
--------------------------------------------------------------------------------
--[[
    These exist so a resource does not have to call qbx_vehicles / qbx_core
    directly and hard-depend on Qbox. Each resolves through GetVehicleSchema(),
    which already knows the per-framework table and column names, so the same
    call works on Qbox, QBCore and ESX.

    Return shapes match what qbx_vehicles gives, so a caller migrating off the
    direct export does not have to change how it reads the result. In particular
    `props` is the DECODED props table, not the raw column.
]]

---@param vehicleId number|string
---@return table? { id, citizenid, modelName, plate, props, garage, state }
function GetPlayerVehicle(vehicleId)
    if not vehicleId then return nil end

    -- Native path first. Qbox owns player_vehicles and documents these exports as
    -- the supported way in; reading the table directly is unsupported and would
    -- miss anything qbx_vehicles normalises on the way out.
    if qbxVehiclesAvailable() then
        local ok, row = RSBridge.safeCall(function()
            return exports.qbx_vehicles:GetPlayerVehicle(vehicleId)
        end)
        if ok and type(row) == 'table' then
            -- qbx carries the plate inside props rather than at the top level;
            -- surface it either way so callers do not need to know which.
            row.plate = row.plate or (type(row.props) == 'table' and row.props.plate) or nil
            return row
        end
    end

    local schema = GetVehicleSchema()
    local ok, row = RSBridge.safeCall(function()
        return MySQL.single.await(
            ('SELECT * FROM `%s` WHERE `id` = ? LIMIT 1'):format(schema.table),
            { vehicleId })
    end)
    if not ok or type(row) ~= 'table' then return nil end

    local props = row[schema.props]
    if type(props) == 'string' then
        local decoded, value = pcall(json.decode, props)
        props = (decoded and type(value) == 'table') and value or {}
    end

    return {
        id = row.id,
        citizenid = row[schema.identifier],
        modelName = row.vehicle or row.model,
        plate = row.plate,
        props = type(props) == 'table' and props or {},
        garage = row.garage,
        state = row.state,
    }
end

---@param plate string
---@return number? vehicleId
function GetVehicleIdByPlate(plate)
    if type(plate) ~= 'string' or plate == '' then return nil end

    if qbxVehiclesAvailable() then
        local ok, id = RSBridge.safeCall(function()
            return exports.qbx_vehicles:GetVehicleIdByPlate(plate)
        end)
        if ok and id then return tonumber(id) end
    end

    local schema = GetVehicleSchema()
    local ok, id = RSBridge.safeCall(function()
        -- Plates are stored space-padded on some frameworks, so compare trimmed
        -- on both sides rather than making every caller know which.
        return MySQL.scalar.await(
            ('SELECT `id` FROM `%s` WHERE TRIM(`%s`) = TRIM(?) LIMIT 1')
                :format(schema.table, schema.plate),
            { plate })
    end)
    return ok and tonumber(id) or nil
end

---@param plate string
---@return boolean
function DoesPlayerVehiclePlateExist(plate)
    if qbxVehiclesAvailable() then
        local ok, exists = RSBridge.safeCall(function()
            return exports.qbx_vehicles:DoesPlayerVehiclePlateExist(plate)
        end)
        if ok and exists ~= nil then return exists == true end
    end

    return GetVehicleIdByPlate(plate) ~= nil
end

---@param citizenid string
---@return number? source
function GetPlayerSourceByCitizenId(citizenid)
    if not citizenid or citizenid == '' then return nil end

    local framework = RSBridge.Framework
    local ok, result

    if framework == 'qbox' then
        ok, result = RSBridge.safeCall(function()
            return exports.qbx_core:GetPlayerByCitizenId(citizenid)
        end)
    elseif framework == 'qbcore' then
        ok, result = RSBridge.safeCall(function()
            return exports['qb-core']:GetCoreObject().Functions.GetPlayerByCitizenId(citizenid)
        end)
    elseif framework == 'esx' then
        ok, result = RSBridge.safeCall(function()
            return exports['es_extended']:getSharedObject().GetPlayerFromIdentifier(citizenid)
        end)
    end

    if not ok or type(result) ~= 'table' then return nil end
    return (result.PlayerData and result.PlayerData.source) or result.source
end

--------------------------------------------------------------------------------
-- Entity identity and lifecycle
--------------------------------------------------------------------------------
local sessionCounter = 0

---A stable per-entity id lasting the life of that entity.
---
---Qbox provides this natively and nothing else does. Implemented here on a plain
---statebag so a resource needing per-spawn identity is not tied to Qbox for it.
---Returns any existing id rather than overwriting, matching qbx behaviour.
---@param entity number
---@return integer? sessionId
function CreateSessionId(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end

    if RSBridge.Framework == 'qbox' and GetResourceState('qbx_core') == 'started' then
        local ok, id = RSBridge.safeCall(function()
            return exports.qbx_core:CreateSessionId(entity)
        end)
        if ok and id then return id end
    end

    local existing = Entity(entity).state.sessionId
    if existing then return existing end

    sessionCounter = sessionCounter + 1
    Entity(entity).state:set('sessionId', sessionCounter, true)
    return sessionCounter
end

---@param entity number
---@return boolean
function DeleteVehicleSafe(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end

    if RSBridge.Framework == 'qbox' and GetResourceState('qbx_core') == 'started' then
        local ok = RSBridge.safeCall(function() return exports.qbx_core:DeleteVehicle(entity) end)
        if ok then return true end
    end

    local ok = RSBridge.safeCall(function() DeleteEntity(entity) end)
    return ok == true
end

---Routes to whichever key provider is installed, so a caller never has to know
---whether this server runs qbx_vehiclekeys or qb-vehiclekeys.
---@param vehicle number
---@param state 'lock'|'unlock'|number
---@return boolean
function SetVehicleLockState(vehicle, state)
    if not vehicle or vehicle == 0 then return false end

    if GetVehicleKeysProvider() == 'qbx_vehiclekeys' then
        local ok = RSBridge.safeCall(function()
            return exports.qbx_vehiclekeys:SetLockState(vehicle, state)
        end)
        if ok then return true end
    end

    -- Fallback works on any framework: lock state is an entity statebag.
    local numeric = state
    if type(state) == 'string' then numeric = (state == 'lock') and 2 or 1 end

    local ok = RSBridge.safeCall(function()
        Entity(vehicle).state:set('doorslockstate', numeric, true)
    end)
    return ok == true
end

---@param model string|number model name or hash
---@return table? shared vehicle definition
function GetVehicleByName(model)
    if not model then return nil end

    if RSBridge.Framework == 'qbox' and GetResourceState('qbx_core') == 'started' then
        local ok, result = RSBridge.safeCall(function()
            if type(model) == 'number' then
                return exports.qbx_core:GetVehiclesByHash()[model]
            end
            return exports.qbx_core:GetVehiclesByName()[model]
        end)
        if ok and type(result) == 'table' then return result end
    end

    -- Static fallback carries class/seats/type but NOT price or brand, so a
    -- caller must treat those as optional rather than assuming Qbox's shape.
    if RSVehicleData then
        local entry = RSVehicleData.Find(model)
        if entry then
            return {
                name = type(model) == 'string' and model or nil,
                class = entry.class,
                seats = entry.seats,
                type = entry.type,
            }
        end
    end

    return nil
end

exports('GetPlayerVehicle', GetPlayerVehicle)
exports('GetVehicleIdByPlate', GetVehicleIdByPlate)
exports('DoesPlayerVehiclePlateExist', DoesPlayerVehiclePlateExist)
exports('GetPlayerSourceByCitizenId', GetPlayerSourceByCitizenId)
exports('CreateSessionId', CreateSessionId)
exports('DeleteVehicleSafe', DeleteVehicleSafe)
exports('SetVehicleLockState', SetVehicleLockState)
exports('GetVehicleByName', GetVehicleByName)
