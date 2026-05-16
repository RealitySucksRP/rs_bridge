RSBridgeConfig = {}

-- auto order: qbox -> qbcore -> esx -> standalone
-- valid: auto, qbox, qbcore, esx, standalone
RSBridgeConfig.Framework = 'auto'

RSBridgeConfig.Debug = true

-- Supported out of the box: en, es, fr, pt-br
RSBridgeConfig.Locale = 'en'

RSBridgeConfig.Notify = {
    -- auto = ox_lib, qbox/qbcore/esx, chat fallback
    Provider = 'auto',
    DefaultType = 'primary',
    DefaultDuration = 5000,
    DefaultTitle = 'Reality Sucks RP'
}

RSBridgeConfig.Inventory = {
    -- auto, ox_inventory, qs-inventory, codem-inventory, ps-inventory,
    -- tgiann-inventory, core_inventory, origen_inventory, framework
    Provider = 'auto'
}

RSBridgeConfig.Target = {
    -- auto, ox_target, qb-target, qtarget, bt-target, none
    Provider = 'auto',
    DefaultDistance = 2.0
}

RSBridgeConfig.Progress = {
    -- auto, ox_lib, progressbar, mythic_progbar, rprogress, rs_progressbar, none
    Provider = 'auto'
}

RSBridgeConfig.Fuel = {
    -- auto, LegacyFuel, lj-fuel, ps-fuel, cdn-fuel, ox_fuel, ti_fuel,
    -- BigDaddy-Fuel, x-fuel, lc_fuel, okokGasStation, native
    Provider = 'auto'
}
