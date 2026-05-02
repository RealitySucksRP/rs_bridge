fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rs_bridge'
author 'Reality Sucks RP'
description 'Universal bridge for QBCore, Qbox/qbx_core, ox_lib, inventories, targets, and standalone Reality Sucks resources.'
version '1.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/utils.lua',
    'shared/main.lua'
}

client_scripts {
    'client/main.lua',
    'client/target.lua',
    'client/progress.lua'
}

server_scripts {
    'server/main.lua',
    'server/inventory.lua',
    'server/callbacks.lua'
}

files {
    'README.md',
    'CHANGELOG.md'
}

exports {
    'GetFramework',
    'IsQBCore',
    'IsQbox',
    'IsStandalone',
    'GetPlayerData',
    'GetJob',
    'GetGang',
    'Notify',
    'ProgressBar',
    'AddTargetEntity',
    'AddTargetModel',
    'AddTargetZone',
    'RemoveTargetZone'
}

server_exports {
    'GetFramework',
    'IsQBCore',
    'IsQbox',
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
    'TriggerClientCallback'
}

dependencies {
}
