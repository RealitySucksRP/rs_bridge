<p align="center">
  <a href="https://reality-sucks-rp-webstore.tebex.io/package/7449324"><img src="https://img.shields.io/badge/GET%20RS%20BRIDGE-FREE%20ON%20TEBEX-ff6a00?style=for-the-badge" alt="Get RS Bridge free on Tebex"></a>
  <a href="https://reality-sucks-rp-webstore.tebex.io/"><img src="https://img.shields.io/badge/BROWSE-REALITYSUCKSRP%20STORE-111111?style=for-the-badge" alt="Browse RealitySucksRP Tebex Store"></a>
  <a href="https://discord.gg/e9V3rPHySx"><img src="https://img.shields.io/badge/JOIN-DISCORD-5865F2?style=for-the-badge" alt="Join RealitySucksRP Discord"></a>
</p>

> I build my own FiveM scripts and complete server setups: shops, weapons, phones, racing, customs, garages, dealerships, zombie apocalypse systems, warfare, Phantom encounters, UI and more. `rs_bridge` is the free compatibility layer behind many of those systems.

# rs_bridge v2.4.0

Universal bridge for Reality Sucks RP resources.

Your resources call `rs_bridge`.  
`rs_bridge` talks to the framework, inventory, target, fuel, progress bar, and locale system.

## Supported framework modes

- QBCore / `qb-core`
- Qbox / `qbx_core`
- ESX Legacy / `es_extended`
- Old ESX shared object fallback
- Standalone safe fallback

## Supported modules

### Inventory

Auto-detects or can be forced in `config.lua`.

- `ox_inventory`
- `qs-inventory`
- `codem-inventory`
- `ps-inventory`
- `tgiann-inventory`
- `core_inventory`
- `origen_inventory`
- framework inventory fallback


### Client medical

```lua
exports.rs_bridge:HealPlayer()
exports.rs_bridge:RevivePlayer()
exports.rs_bridge:SetArmor(100)
exports.rs_bridge:SetHealth(200)

local health = exports.rs_bridge:GetHealth()
local dead = exports.rs_bridge:IsPlayerDead()
local down = exports.rs_bridge:IsPlayerDown()
```

### Fuel

- `LegacyFuel`
- `lj-fuel`
- `ps-fuel`
- `cdn-fuel`
- `ox_fuel`
- `ti_fuel`
- `BigDaddy-Fuel`
- `x-fuel`
- `lc_fuel`
- `okokGasStation`
- native GTA fallback

### Target

- `ox_target`
- `qb-target`
- `qtarget`
- `bt-target`

### Progress

- `ox_lib`
- `progressbar`
- `mythic_progbar`
- `rprogress`
- `rs_progressbar`
- timer fallback


### Medical / ambulance

- `qb-ambulancejob`
- `qbx_medical`
- `esx_ambulancejob`

Auto medical selection is framework-aware: Qbox prefers `qbx_medical`, QBCore prefers `qb-ambulancejob`, and ESX prefers `esx_ambulancejob`. Qbox revive uses the current server-side `qbx_medical:Revive` export. Standard ESX Legacy server-owned revives also clear its persisted `users.is_dead` flag.
- `wasabi_ambulance`
- `ak47_ambulancejob`
- `ars_ambulancejob`
- native fallback

Exports:

```lua
exports.rs_bridge:RevivePlayer(src)
exports.rs_bridge:HealPlayer(src)
exports.rs_bridge:SetArmor(src, 100)
exports.rs_bridge:SetHealth(src, 200)
exports.rs_bridge:KillPlayer(src)
exports.rs_bridge:IsPlayerDead(src)
exports.rs_bridge:IsPlayerDown(src)
```

Client exports:

```lua
exports.rs_bridge:RevivePlayer()
exports.rs_bridge:HealPlayer()
exports.rs_bridge:SetArmor(100)
exports.rs_bridge:SetHealth(200)
exports.rs_bridge:GetHealth()
exports.rs_bridge:IsPlayerDead()
exports.rs_bridge:IsPlayerDown()
```

### Languages

Included:

- English: `en`
- Spanish: `es`
- French: `fr`
- Portuguese Brazil: `pt-br`

Set language in `config.lua`:

```lua
RSBridgeConfig.Locale = 'en'
```

## Install

Start the bridge after your framework and before your custom resources.

### QBCore

```cfg
ensure qb-core
ensure rs_bridge
ensure your_resource
```

### Qbox

```cfg
ensure qbx_core
ensure rs_bridge
ensure your_resource
```

### ESX

```cfg
ensure es_extended
ensure rs_bridge
ensure your_resource
```

### Standalone

```cfg
ensure rs_bridge
ensure your_resource
```

## Version negotiation (v2.4.0)

rs_bridge is distributed as a shared dependency for RS resources. Because the
bridge can be updated independently from the resources that use it, version
checks help prevent mismatches between a newer resource and an older bridge.

An unguarded call to an export that an older bridge does not provide can stop
the calling thread at that line. Version negotiation turns that failure into a
clear console message naming the resource, required version, and installed
version.

### Declare the minimum (no Lua needed)

Add one line to the resource's `fxmanifest.lua`:

```lua
rs_bridge_version '2.4.0'
```

rs_bridge reads that field from every started resource and names any it cannot
satisfy:

```
[rs_bridge] 2.1.3 is installed, but 2 resource(s) need a newer bridge:
    rs-zombiegunz needs >= 2.4.0
    rs-zombielscustoms needs >= 2.4.0
[rs_bridge] Update rs_bridge. Until then those resources will fail in ways
that do not name the bridge.
```

It runs once ~5s after start, and again for any resource started later by hand.

### Check it in code

```lua
local check = exports.rs_bridge:RequireVersion('2.4.0')
if not check.ok then print(check.message) end
```

`RequireVersion` returns a **table** (`ok`, `installed`, `required`, `message`),
not multiple values — exports flatten multiple returns inconsistently across
builds, and a caller reading only the first value is the same class of silent
bug this feature exists to prevent. `GetVersion()` returns the version string.

A malformed requirement never blocks: it warns and passes.

### What each mechanism can and cannot catch

| Situation | Caught by |
|---|---|
| Bridge new enough, resource needs less | nothing to report |
| Bridge new, resource needs newer | the manifest sweep, by name |
| Bridge **old**, resource needs a newer **export** | `RequireVersion` — but only if the resource calls it, since an old bridge has no sweep |
| Bridge **old**, resource includes a newer `@rs_bridge/...` **file** | FiveM's own script-load error, which does name the missing path |

The last row is why the sweep alone is not enough, and the third row is why the
export exists. A bridge older than this feature cannot report on itself — that
is the gap `RequireVersion` fills from the consumer side.

## Server API

```lua
local src = source

local framework = exports.rs_bridge:GetFramework()
local Player = exports.rs_bridge:GetPlayer(src)
local PlayerData = exports.rs_bridge:GetPlayerData(src)
local citizenid = exports.rs_bridge:GetCitizenId(src)
local charinfo = exports.rs_bridge:GetCharInfo(src)
local job = exports.rs_bridge:GetJob(src)
local gang = exports.rs_bridge:GetGang(src)
```

### Money

```lua
exports.rs_bridge:AddMoney(src, 'bank', 500, 'mission_reward')
exports.rs_bridge:RemoveMoney(src, 'cash', 50, 'shop_purchase')
exports.rs_bridge:SetMoney(src, 'cash', 250, 'admin_set')

local cash = exports.rs_bridge:GetMoney(src, 'cash')
```

ESX cash can use `cash` or `money`. ESX bank uses `bank`.

### Inventory

```lua
exports.rs_bridge:AddItem(src, 'water_bottle', 1)
exports.rs_bridge:RemoveItem(src, 'water_bottle', 1)

if exports.rs_bridge:HasItem(src, 'lockpick', 1) then
    print('Has lockpick')
end

local count = exports.rs_bridge:GetItemCount(src, 'water_bottle')
local item = exports.rs_bridge:GetItem(src, 'water_bottle')
```

### Usable items

```lua
exports.rs_bridge:CreateUseableItem('mystery_box', function(source, item)
    exports.rs_bridge:Notify(source, 'You opened the box.', 'success')
end)
```

### Notifications

```lua
exports.rs_bridge:Notify(src, 'You got paid.', 'success', 5000)
```

### Jobs / groups

```lua
if exports.rs_bridge:HasJob(src, 'police', 2) then
    print('Police grade 2+')
end

if exports.rs_bridge:HasGroup(src, {'admin', 'god'}, 0) then
    print('Admin or god group')
end
```


### Medical

```lua
exports.rs_bridge:RevivePlayer(src)
exports.rs_bridge:HealPlayer(src)
exports.rs_bridge:SetArmor(src, 100)
exports.rs_bridge:SetHealth(src, 200)
exports.rs_bridge:KillPlayer(src)

local health = exports.rs_bridge:GetHealth(src)
local dead = exports.rs_bridge:IsPlayerDead(src)
local down = exports.rs_bridge:IsPlayerDown(src)
```

Server-side `GetHealth`, `IsPlayerDead`, and `IsPlayerDown` are best-effort.
They read framework metadata first (qb-ambulancejob, qbx_medical, esx
ambulancejob all stash isdead / inlaststand on the player) and fall back to
a client sync that pushes state every 500ms when it changes. `GetHealth`
defaults to 200 until the first sync arrives.

## Client API

### Notify

```lua
exports.rs_bridge:Notify('Hello world.', 'success', 5000)
```

### Progress

```lua
local success = exports.rs_bridge:ProgressBar({
    label = 'Searching...',
    duration = 5000,
    canCancel = true,
    disableCombat = true
})
```


### Client medical

```lua
exports.rs_bridge:HealPlayer()
exports.rs_bridge:RevivePlayer()
exports.rs_bridge:SetArmor(100)
exports.rs_bridge:SetHealth(200)

local health = exports.rs_bridge:GetHealth()
local dead = exports.rs_bridge:IsPlayerDead()
local down = exports.rs_bridge:IsPlayerDown()
```

### Fuel

```lua
local veh = GetVehiclePedIsIn(PlayerPedId(), false)
local fuel = exports.rs_bridge:GetFuel(veh)
exports.rs_bridge:SetFuel(veh, 100.0)
```

### Target

```lua
exports.rs_bridge:AddTargetEntity(entity, {
    {
        label = 'Talk',
        icon = 'fa-solid fa-comment',
        action = function()
            print('talking')
        end
    }
})
```

## Locale API

Each resource can load its own locale files:

```lua
exports.rs_bridge:LoadLocales(GetCurrentResourceName())
```

Then use:

```lua
local text = exports.rs_bridge:_L('my_resource.some_key')
```

Resource locale file example:

```lua
-- locales/en.lua
return {
    some_key = 'Hello world',
    found_items = 'You found %d items.'
}
```

Formatted usage:

```lua
exports.rs_bridge:_L('my_resource.found_items', 3)
```

## Recommended pattern for all Reality Sucks RP resources

Do this:

```lua
exports.rs_bridge:GetPlayer(source)
exports.rs_bridge:AddItem(source, item, amount, metadata)
exports.rs_bridge:Notify(source, 'Done.', 'success')
```

Avoid direct framework calls inside your normal resources:

```lua
exports['qb-core']:GetCoreObject()
exports.qbx_core:GetPlayer(source)
ESX.GetPlayerFromId(source)
```

Keep those inside the bridge.

## Important note

This bridge is defensive and fail-soft. Some third-party inventories and fuel scripts use different export names depending on version. The bridge tries common exports first and falls back when possible. Community testing may require small adapter patches for specific versions.


## Banking and cash providers (v2.2.2)

Physical cash and bank money are separate providers.

- `RSBridgeConfig.Cash.Provider = 'inventory_item'` routes physical cash through the configured inventory item. With Qbox and ox_inventory, RealitySucksRP uses the synchronized `money` item (the Qbox account is still named `cash`).
- `RSBridgeConfig.Cash.Provider = 'framework'` supports servers whose framework owns physical cash.
- `RSBridgeConfig.Banking.Provider = 'auto'` prefers `rs-banking` when it is started and otherwise falls back to framework bank money.

Banking server exports: `GetCashProvider`, `GetCash`, `CanReceiveCash`, `AddCash`, `RemoveCash`, `GetBankingProvider`, `GetBankBalance`, `AddBankMoney`, `RemoveBankMoney`, `ChargePlayer`, and `CreditPlayer`.

`client/core.lua`, `client/uiguard.lua`, and `server/core.lua` are explicitly packaged for resources using `@rs_bridge/...` compatibility includes.
## License

MIT License. See `LICENSE` for the full terms.

