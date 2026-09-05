fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rs_bridge'
author 'Reality Sucks RP'
description 'Universal bridge for QBCore, Qbox, ESX, standalone, inventories, fuel, progress, target, callbacks, and locales.'
version '2.4.0'

-- ox_lib is framework-neutral and runs on Qbox, QBCore and ESX alike.
-- The callback, notification and progress providers all resolve through it
-- first, so it is loaded here rather than assumed to exist.
shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/utils.lua',
    'shared/version.lua',
    'shared/locale.lua',
    'shared/main.lua',
    'shared/items.lua',
    'shared/vehicledata.lua'
}

client_scripts {
    'client/main.lua',
    'client/callbacks.lua',
    'client/events.lua',
    'client/entities.lua',
    'client/progress.lua',
    'client/target.lua',
    'client/fuel.lua',
    'client/medical.lua',
    'client/minigame.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/inventory.lua',
    'server/cash.lua',
    'server/banking.lua',
    'server/callbacks.lua',
    'server/events.lua',
    'server/fuel.lua',
    'server/medical.lua',
    'server/vehicles.lua',
    'server/webhook.lua',
    'server/cashaudit.lua'
}

files {
    -- Compatibility include files consumed through @rs_bridge/...
    'client/core.lua',
    'client/uiguard.lua',
    'client/threat.lua',
    'server/core.lua',
    'README.md',
    'CHANGELOG.md',
    'locales/*.lua',
    'examples/*.lua'
}

-- Framework-neutral only. The framework itself, plus inventory, target, fuel,
-- keys and medical providers are all resolved at runtime.
dependencies {
    'ox_lib',
    'oxmysql'
}

exports {
    'GetVersion',
    'RequireVersion',
    'GetFramework',
    'IsQBCore',
    'IsQbox',
    'IsESX',
    'IsStandalone',
    'GetCoreObject',
    'GetPlayerData',
    'GetJob',
    'GetGang',
    'GetItems',
    'GetItemDefinition',
    'DoesItemExist',
    'GetItemLabel',
    'Notify',
    'ProgressBar',
    'Minigame',
    'GetMinigameProvider',
    'AddTargetEntity',
    'AddTargetModel',
    'AddTargetZone',
    'AddTargetCircleZone',
    'AddTargetPolyZone',
    'RemoveTargetEntity',
    'RemoveTargetModel',
    'RemoveTargetZone',
    'GetTargetProvider',
    'TriggerServerCallback',
    'RegisterClientCallback',
    'GetFuel',
    'SetFuel',
    'GetHealth',
    'SetHealth',
    'SetArmor',
    'HealPlayer',
    'RevivePlayer',
    'KillPlayer',
    'IsPlayerDead',
    'IsPlayerDown',
    'LoadLocales',
    'Translate',
    '_L'
}

server_exports {
    'Audit',
    'ReloadWebhooks',
    'GetVersion',
    'RequireVersion',
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
    'GetJobs',
    'GetGangs',
    'GetItems',
    'GetItemDefinition',
    'DoesItemExist',
    'GetItemLabel',
    'HasJob',
    'HasGroup',
    'HasPermission',
    'HasAnyPermission',
    'GetPermission',
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
    'GetInventoryProvider',
    'GetCashProvider',
    'GetCash',
    'CanReceiveCash',
    'AddCash',
    'RemoveCash',
    'GetBankingProvider',
    'GetBankBalance',
    'AddBankMoney',
    'RemoveBankMoney',
    'ChargePlayer',
    'CreditPlayer',
    'Notify',
    'RegisterCallback',
    'TriggerClientCallback',
    'GetFuelProvider',
    'GetVehicleSchema',
    'DoesPlayerOwnVehicle',
    'GetOwnedVehicles',
    'GiveVehicleKeys',
    'RemoveVehicleKeys',
    'HasVehicleKeys',
    'GetVehicleClassByModel',
    'GetPlayerVehicle',
    'GetVehicleIdByPlate',
    'DoesPlayerVehiclePlateExist',
    'GetPlayerSourceByCitizenId',
    'CreateSessionId',
    'DeleteVehicleSafe',
    'SetVehicleLockState',
    'GetVehicleByName',
    'GetVehicleKeysProvider',
    'RevivePlayer',
    'HealPlayer',
    'HealPlayerPartial',
    'GetMedicalStatus',
    'SetArmor',
    'SetHealth',
    'KillPlayer',
    'GetHealth',
    'IsPlayerDead',
    'IsPlayerDown',
    'LoadLocales',
    'Translate',
    '_L'
}
