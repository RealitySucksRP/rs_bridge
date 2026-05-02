local createdZones = {}

local function getTargetProvider()
    local forced = RSBridgeConfig.Target.Provider or 'auto'
    if forced ~= 'auto' then return forced end

    if RSBridge.resourceStarted('ox_target') then return 'ox_target' end
    if RSBridge.resourceStarted('qb-target') then return 'qb-target' end
    if RSBridge.resourceStarted('qtarget') then return 'qtarget' end
    if RSBridge.resourceStarted('bt-target') then return 'bt-target' end

    return 'none'
end

local function normalizeOptions(options)
    if not options then return {} end
    if options.options then return options.options end
    return options
end

function AddTargetEntity(entity, options)
    local provider = getTargetProvider()
    options = normalizeOptions(options)

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

    RSBridge.debug('No target resource found for AddTargetEntity')
    return false
end

function AddTargetModel(models, options)
    local provider = getTargetProvider()
    options = normalizeOptions(options)

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

    RSBridge.debug('No target resource found for AddTargetModel')
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
            options = normalizeOptions(options)
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
            options = normalizeOptions(options),
            distance = options.distance or RSBridgeConfig.Target.DefaultDistance
        })
        createdZones[name] = name
        return name
    end

    RSBridge.debug('No target resource found for AddTargetZone')
    return false
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
exports('RemoveTargetZone', RemoveTargetZone)
