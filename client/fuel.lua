local FuelResources = {
    'LegacyFuel',
    'lj-fuel',
    'ps-fuel',
    'cdn-fuel',
    'ox_fuel',
    'ti_fuel',
    'BigDaddy-Fuel',
    'x-fuel',
    'lc_fuel',
    'okokGasStation'
}

local cachedFuelProvider = nil

local function resolveFuelProvider()
    local forced = RSBridgeConfig.Fuel.Provider or 'auto'
    if forced ~= 'auto' then return forced end

    if cachedFuelProvider and (cachedFuelProvider == 'native' or RSBridge.resourceStarted(cachedFuelProvider)) then
        return cachedFuelProvider
    end

    cachedFuelProvider = RSBridge.firstStarted(FuelResources) or 'native'
    return cachedFuelProvider
end

AddEventHandler('onResourceStart', function(resource)
    for _, name in ipairs(FuelResources) do
        if resource == name then cachedFuelProvider = nil return end
    end
end)

function GetFuel(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0.0 end

    local provider = resolveFuelProvider()

    if provider == 'LegacyFuel' or provider == 'lj-fuel' or provider == 'ps-fuel' then
        local ok, result = RSBridge.safeCall(function()
            return exports[provider]:GetFuel(vehicle)
        end)
        if ok and result then return tonumber(result) or 0.0 end
    end

    if provider == 'cdn-fuel' then
        local ok, result = RSBridge.safeCall(function()
            return exports['cdn-fuel']:GetFuel(vehicle)
        end)
        if ok and result then return tonumber(result) or 0.0 end
    end

    if provider == 'ox_fuel' then
        local stateFuel = Entity(vehicle).state and Entity(vehicle).state.fuel
        if stateFuel then return tonumber(stateFuel) or 0.0 end
    end

    if provider == 'ti_fuel' then
        local ok, result = RSBridge.safeCall(function()
            return exports.ti_fuel:getFuel(vehicle)
        end)
        if ok and result then return tonumber(result) or 0.0 end
    end

    if provider == 'BigDaddy-Fuel' then
        local ok, result = RSBridge.safeCall(function()
            return exports['BigDaddy-Fuel']:GetFuel(vehicle)
        end)
        if ok and result then return tonumber(result) or 0.0 end
    end

    if provider == 'x-fuel' then
        local ok, result = RSBridge.safeCall(function()
            return exports['x-fuel']:GetFuel(vehicle)
        end)
        if ok and result then return tonumber(result) or 0.0 end
    end

    if provider == 'lc_fuel' then
        local ok, result = RSBridge.safeCall(function()
            return exports['lc_fuel']:GetFuel(vehicle)
        end)
        if ok and result then return tonumber(result) or 0.0 end
    end

    if provider == 'okokGasStation' then
        local ok, result = RSBridge.safeCall(function()
            return exports['okokGasStation']:GetFuel(vehicle)
        end)
        if ok and result then return tonumber(result) or 0.0 end
    end

    return GetVehicleFuelLevel(vehicle)
end

function SetFuel(vehicle, level)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end

    level = RSBridge.clamp(level, 0.0, 100.0)
    local provider = resolveFuelProvider()

    if provider == 'LegacyFuel' or provider == 'lj-fuel' or provider == 'ps-fuel' then
        local ok = RSBridge.safeCall(function()
            exports[provider]:SetFuel(vehicle, level)
        end)
        if ok then return true end
    end

    if provider == 'cdn-fuel' then
        local ok = RSBridge.safeCall(function()
            exports['cdn-fuel']:SetFuel(vehicle, level)
        end)
        if ok then return true end
    end

    if provider == 'ox_fuel' then
        Entity(vehicle).state:set('fuel', level, true)
        SetVehicleFuelLevel(vehicle, level)
        return true
    end

    if provider == 'ti_fuel' then
        local ok = RSBridge.safeCall(function()
            exports.ti_fuel:setFuel(vehicle, level)
        end)
        if ok then return true end
    end

    if provider == 'BigDaddy-Fuel' then
        local ok = RSBridge.safeCall(function()
            exports['BigDaddy-Fuel']:SetFuel(vehicle, level)
        end)
        if ok then return true end
    end

    if provider == 'x-fuel' then
        local ok = RSBridge.safeCall(function()
            exports['x-fuel']:SetFuel(vehicle, level)
        end)
        if ok then return true end
    end

    if provider == 'lc_fuel' then
        local ok = RSBridge.safeCall(function()
            exports['lc_fuel']:SetFuel(vehicle, level)
        end)
        if ok then return true end
    end

    if provider == 'okokGasStation' then
        local ok = RSBridge.safeCall(function()
            exports['okokGasStation']:SetFuel(vehicle, level)
        end)
        if ok then return true end
    end

    SetVehicleFuelLevel(vehicle, level)
    return true
end

exports('GetFuel', GetFuel)
exports('SetFuel', SetFuel)
