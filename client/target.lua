local createdZones = {}
local cachedProvider = nil

local function getTargetProvider()
    local forced = RSBridgeConfig.Target.Provider or 'auto'
    if forced ~= 'auto' then return forced end

    if cachedProvider and (cachedProvider == 'none' or RSBridge.resourceStarted(cachedProvider)) then
        return cachedProvider
    end

    cachedProvider = RSBridge.firstStarted({ 'ox_target', 'qb-target', 'qtarget', 'bt-target' }) or 'none'
    return cachedProvider
end

AddEventHandler('onResourceStart', function(resource)
    if resource == 'ox_target' or resource == 'qb-target' or resource == 'qtarget' or resource == 'bt-target' then
        cachedProvider = nil
    end
end)

-- Option callbacks are spelled differently per provider: qb-target/qtarget use
-- `action`, ox_target uses `onSelect`. Accept either from callers and emit
-- whichever the resolved provider expects, so gameplay code stays neutral.
-- Job/gang gating keys differ too (`job`/`gang` vs ox_target's `groups`).
local function translateOption(option, provider)
    if type(option) ~= 'table' then return option end

    local out = {}
    for k, v in pairs(option) do out[k] = v end

    -- The KEY the caller used tells us which signature they wrote for, and the
    -- two providers do not agree on it:
    --
    --   qb-target / qtarget   action(entity)    a raw entity handle
    --   ox_target             onSelect(data)    a table, entity at data.entity
    --
    -- Moving the function between keys without adapting the ARGUMENT -- which is
    -- all this used to do -- breaks both directions. A QB-style consumer running
    -- on ox_target received the whole data table where it expected a handle, so
    -- DoesEntityExist() and GetEntityCoords() silently failed on it; an ox-style
    -- consumer running on qb-target received a bare handle and read nil from
    -- data.entity.
    local handler = out.onSelect or out.action
    local wroteOxStyle = out.onSelect ~= nil

    if provider == 'ox_target' then
        if handler and not wroteOxStyle then
            -- Caller wrote action(entity); hand them the entity out of the table.
            out.onSelect = function(data)
                return handler(type(data) == 'table' and data.entity or data)
            end
        else
            out.onSelect = handler
        end
        out.action = nil

        if out.job or out.gang then
            out.groups = out.groups or out.job or out.gang
            out.job = nil
            out.gang = nil
        end
    else
        if handler and wroteOxStyle then
            -- Caller wrote onSelect(data); synthesise the shape they expect.
            -- Only `entity` can be recovered here -- qb-target does not supply
            -- ox's coords or distance -- so an ox consumer must treat those as
            -- optional, which the ox docs already require.
            out.action = function(entity)
                return handler({ entity = entity })
            end
        else
            out.action = handler
        end
        out.onSelect = nil
    end

    return out
end

local function normalizeOptions(options, provider)
    if not options then return {} end

    local list = options.options or options
    if type(list) ~= 'table' then return {} end

    local out = {}
    for i = 1, #list do
        out[i] = translateOption(list[i], provider)
    end

    return out
end

function AddTargetEntity(entity, options)
    local provider = getTargetProvider()
    options = normalizeOptions(options, provider)

    if provider == 'ox_target' then
        return exports.ox_target:addLocalEntity(entity, options)
    end

    if provider == 'qb-target' then
        return exports['qb-target']:AddTargetEntity(entity, {
            options = options,
            distance = RSBridgeConfig.Target.DefaultDistance
        })
    end

    if provider == 'qtarget' then
        return exports.qtarget:AddTargetEntity(entity, {
            options = options,
            distance = RSBridgeConfig.Target.DefaultDistance
        })
    end

    if provider == 'bt-target' then
        return exports['bt-target']:AddTargetEntity(entity, {
            options = options,
            distance = RSBridgeConfig.Target.DefaultDistance
        })
    end

    RSBridge.debug(_L('no_target_resource'))
    return false
end

function AddTargetModel(models, options)
    local provider = getTargetProvider()
    options = normalizeOptions(options, provider)

    if provider == 'ox_target' then
        return exports.ox_target:addModel(models, options)
    end

    if provider == 'qb-target' then
        return exports['qb-target']:AddTargetModel(models, {
            options = options,
            distance = RSBridgeConfig.Target.DefaultDistance
        })
    end

    if provider == 'qtarget' then
        return exports.qtarget:AddTargetModel(models, {
            options = options,
            distance = RSBridgeConfig.Target.DefaultDistance
        })
    end

    RSBridge.debug(_L('no_target_resource'))
    return false
end

function AddTargetZone(name, coords, size, options)
    local provider = getTargetProvider()
    options = options or {}
    size = size or vec3(2.0, 2.0, 2.0)

    if provider == 'ox_target' then
        local zoneId = exports.ox_target:addBoxZone({
            coords = coords,
            size = size,
            rotation = options.rotation or options.heading or 0.0,
            debug = options.debug or false,
            options = normalizeOptions(options, provider)
        })
        createdZones[name] = zoneId
        return zoneId
    end

    if provider == 'qb-target' then
        exports['qb-target']:AddBoxZone(name, coords, size.x or size[1] or 2.0, size.y or size[2] or 2.0, {
            name = name,
            heading = options.heading or options.rotation or 0.0,
            debugPoly = options.debug or false,
            minZ = options.minZ,
            maxZ = options.maxZ
        }, {
            options = normalizeOptions(options, provider),
            distance = options.distance or RSBridgeConfig.Target.DefaultDistance
        })
        createdZones[name] = name
        return name
    end

    RSBridge.debug(_L('no_target_resource'))
    return false
end

-- Circle/sphere zone.
--   ox_target: addSphereZone{ coords, radius, options } -> numeric id
--   qb-target: AddCircleZone(name, coords, radius, opts, targetOpts)
-- Both are stored under `name` so RemoveTargetZone(name) works either way.
function AddTargetCircleZone(name, coords, radius, options)
    local provider = getTargetProvider()
    options = options or {}
    radius = tonumber(radius) or 2.0

    if provider == 'ox_target' then
        local zoneId = exports.ox_target:addSphereZone({
            coords = coords,
            radius = radius,
            debug = options.debug or false,
            options = normalizeOptions(options, provider)
        })
        createdZones[name] = zoneId
        return zoneId
    end

    if provider == 'qb-target' or provider == 'qtarget' then
        local resourceName = provider == 'qtarget' and 'qtarget' or 'qb-target'
        exports[resourceName]:AddCircleZone(name, coords, radius, {
            name = name,
            useZ = options.useZ ~= false,
            debugPoly = options.debug or false
        }, {
            options = normalizeOptions(options, provider),
            distance = options.distance or RSBridgeConfig.Target.DefaultDistance
        })
        createdZones[name] = name
        return name
    end

    RSBridge.debug(_L('no_target_resource'))
    return false
end

-- Polygon zone.
--   ox_target: addPolyZone{ points, thickness, options } -> numeric id
--   qb-target: AddPolyZone(name, points, opts, targetOpts)
function AddTargetPolyZone(name, points, options)
    local provider = getTargetProvider()
    options = options or {}

    if provider == 'ox_target' then
        -- ox_target wants vec3 points; qb-target style callers pass vec2.
        local converted = {}
        for i = 1, #points do
            local p = points[i]
            if p.z then
                converted[i] = vec3(p.x, p.y, p.z)
            else
                converted[i] = vec3(p.x, p.y, options.minZ or 0.0)
            end
        end

        local zoneId = exports.ox_target:addPolyZone({
            points = converted,
            thickness = options.thickness
                or (options.maxZ and options.minZ and (options.maxZ - options.minZ))
                or 4.0,
            debug = options.debug or false,
            options = normalizeOptions(options, provider)
        })
        createdZones[name] = zoneId
        return zoneId
    end

    if provider == 'qb-target' or provider == 'qtarget' then
        local resourceName = provider == 'qtarget' and 'qtarget' or 'qb-target'
        exports[resourceName]:AddPolyZone(name, points, {
            name = name,
            minZ = options.minZ,
            maxZ = options.maxZ,
            debugPoly = options.debug or false
        }, {
            options = normalizeOptions(options, provider),
            distance = options.distance or RSBridgeConfig.Target.DefaultDistance
        })
        createdZones[name] = name
        return name
    end

    RSBridge.debug(_L('no_target_resource'))
    return false
end

function RemoveTargetEntity(entity, labels)
    local provider = getTargetProvider()

    if provider == 'ox_target' then
        return exports.ox_target:removeLocalEntity(entity, labels)
    end

    if provider == 'qb-target' then
        return exports['qb-target']:RemoveTargetEntity(entity, labels)
    end

    if provider == 'qtarget' then
        return exports.qtarget:RemoveTargetEntity(entity, labels)
    end

    if provider == 'bt-target' then
        return exports['bt-target']:RemoveTargetEntity(entity, labels)
    end

    return false
end

function RemoveTargetModel(models, labels)
    local provider = getTargetProvider()

    if provider == 'ox_target' then
        return exports.ox_target:removeModel(models, labels)
    end

    if provider == 'qb-target' then
        return exports['qb-target']:RemoveTargetModel(models, labels)
    end

    if provider == 'qtarget' then
        return exports.qtarget:RemoveTargetModel(models, labels)
    end

    return false
end

-- Reports the resolved provider so callers can degrade gracefully instead of
-- assuming a target system exists. Returns 'none' when nothing is installed.
function GetTargetProvider()
    return getTargetProvider()
end

function RemoveTargetZone(name)
    local provider = getTargetProvider()
    local zone = createdZones[name] or name

    if provider == 'ox_target' then
        exports.ox_target:removeZone(zone)
        createdZones[name] = nil
        return true
    end

    if provider == 'qb-target' then
        exports['qb-target']:RemoveZone(zone)
        createdZones[name] = nil
        return true
    end

    return false
end

exports('AddTargetEntity', AddTargetEntity)
exports('AddTargetModel', AddTargetModel)
exports('AddTargetZone', AddTargetZone)
exports('AddTargetCircleZone', AddTargetCircleZone)
exports('AddTargetPolyZone', AddTargetPolyZone)
exports('RemoveTargetEntity', RemoveTargetEntity)
exports('RemoveTargetModel', RemoveTargetModel)
exports('RemoveTargetZone', RemoveTargetZone)
exports('GetTargetProvider', GetTargetProvider)
