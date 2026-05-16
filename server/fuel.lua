function GetFuelProvider()
    local forced = RSBridgeConfig.Fuel.Provider or 'auto'
    if forced ~= 'auto' then return forced end

    local found = RSBridge.firstStarted({
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
    })

    return found or 'native'
end

exports('GetFuelProvider', GetFuelProvider)
