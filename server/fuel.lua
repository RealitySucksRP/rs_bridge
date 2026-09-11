local FuelResources = {
    'LegacyFuel', 'lj-fuel', 'ps-fuel', 'cdn-fuel', 'ox_fuel', 'qb-fuel',
    'ti_fuel', 'BigDaddy-Fuel', 'x-fuel', 'lc_fuel', 'okokGasStation'
}

local FuelPreference = {
    qbox   = { 'ox_fuel', 'lc_fuel', 'LegacyFuel' },
    qbcore = { 'qb-fuel', 'LegacyFuel', 'lj-fuel', 'ps-fuel', 'cdn-fuel', 'ox_fuel' },
    esx    = { 'ox_fuel', 'LegacyFuel', 'lj-fuel', 'cdn-fuel' },
}

function GetFuelProvider()
    local forced = RSBridgeConfig.Fuel.Provider or 'auto'
    if forced ~= 'auto' then
        if forced == 'native' or RSBridge.resourceStarted(forced) then return forced end
        RSBridge.debug(('Fuel provider "%s" is not started; falling back to auto detection'):format(tostring(forced)))
    end

    local preferred = FuelPreference[RSBridge.Framework]
    local found = preferred and RSBridge.firstStarted(preferred) or nil
    if found then return found end
    return RSBridge.firstStarted(FuelResources) or 'native'
end

exports('GetFuelProvider', GetFuelProvider)
