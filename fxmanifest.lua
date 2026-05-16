fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rs_bridge'
author 'Reality Sucks RP'
description 'Universal bridge for QBCore, Qbox, ESX, standalone, inventories, fuel, progress, target, callbacks, and locales.'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/utils.lua',
    'shared/locale.lua',
    'shared/main.lua'
}

client_scripts {
    'client/main.lua',
    'client/progress.lua',
    'client/target.lua',
    'client/fuel.lua'
}

server_scripts {
    'server/main.lua',
    'server/inventory.lua',
    'server/callbacks.lua',
    'server/fuel.lua'
}

files {
    'README.md',
    'CHANGELOG.md',
    'rs_bridge.png',
    'locales/*.lua',
    'examples/*.lua'
}

dependency 'ox_lib'

exports {
    'GetFramework',
    'IsQBCore',
    'IsQbox',
    'IsESX',
    'IsStandalone',
    'GetCoreObject',
    'GetPlayerData',
    'GetJob',
    'GetGang',
    'Notify',
    'ProgressBar',
    'AddTargetEntity',
    'AddTargetModel',
    'AddTargetZone',
    'RemoveTargetZone',
    'GetFuel',
    'SetFuel',
    'LoadLocales',
    'Translate',
    '_L'
}

server_exports {
    'GetFramework',
    'IsQBCore',
    'IsQbox',
    'IsESX',
    'IsStandalone',
    'GetCoreObject',
    'GetPlayer',
    'GetPlayerData',
    'GetCitizenId',
    'GetCharInfo',
    'GetJob',
    'GetGang',
    'HasJob',
    'HasGroup',
    'GetMoney',
    'AddMoney',
    'RemoveMoney',
    'SetMoney',
    'AddItem',
    'RemoveItem',
    'HasItem',
    'GetItemCount',
    'GetItem',
    'CanCarryItem',
    'CreateUseableItem',
    'Notify',
    'RegisterCallback',
    'TriggerClientCallback',
    'GetFuelProvider',
    'LoadLocales',
    'Translate',
    '_L'
}
