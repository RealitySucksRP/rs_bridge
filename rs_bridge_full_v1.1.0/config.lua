RSBridgeConfig = {}

-- auto = qbox first, qbcore second, standalone last
-- qbox = force qbx_core
-- qbcore = force qb-core
-- standalone = no framework
RSBridgeConfig.Framework = 'auto'

RSBridgeConfig.Debug = true

RSBridgeConfig.Notify = {
    -- auto = ox_lib first, then qbx_core/qb-core, then chat fallback
    Provider = 'auto',
    DefaultType = 'primary',
    DefaultDuration = 5000,
    DefaultTitle = 'Reality Sucks RP'
}

RSBridgeConfig.Inventory = {
    -- auto = ox_inventory first if started, otherwise framework inventory
    Provider = 'auto'
}

RSBridgeConfig.Target = {
    -- auto = ox_target, qb-target, qtarget, bt-target, fallback false
    Provider = 'auto',
    DefaultDistance = 2.0
}

RSBridgeConfig.Progress = {
    -- auto = ox_lib progress first, then qb progressbar, then timer fallback
    Provider = 'auto'
}
