# rs_bridge v1.1.0

Universal bridge for Reality Sucks RP resources.

Your resources call **rs_bridge only**.  
The bridge decides whether the server is running:

- QBCore / `qb-core`
- Qbox / `qbx_core`
- ox_lib / ox_inventory / ox_target
- qb-target / qtarget
- standalone fallback

## Why this exists

Instead of writing this in every resource:

```lua
local QBCore = exports['qb-core']:GetCoreObject()
local Player = QBCore.Functions.GetPlayer(source)
```

or this:

```lua
local Player = exports.qbx_core:GetPlayer(source)
```

You write:

```lua
local Player = exports.rs_bridge:GetPlayer(source)
```

That makes your scripts easier to sell, easier to support, and easier to use on both QBCore and Qbox.

---

## Install

Start it before your custom resources.

### QBCore

```cfg
ensure ox_lib
ensure qb-core
ensure rs_bridge

ensure your_resource
```

### Qbox

```cfg
ensure ox_lib
ensure qbx_core
ensure rs_bridge

ensure your_resource
```

### Standalone

```cfg
ensure ox_lib
ensure rs_bridge

ensure your_resource
```

`ox_lib` is strongly recommended but not hard-required for every feature.

---

## Server API

### Framework

```lua
local framework = exports.rs_bridge:GetFramework()

if exports.rs_bridge:IsQBCore() then
    print('QBCore')
elseif exports.rs_bridge:IsQbox() then
    print('Qbox')
elseif exports.rs_bridge:IsStandalone() then
    print('Standalone')
end
```

### Player

```lua
local src = source

local Player = exports.rs_bridge:GetPlayer(src)
local PlayerData = exports.rs_bridge:GetPlayerData(src)
local citizenid = exports.rs_bridge:GetCitizenId(src)
local charinfo = exports.rs_bridge:GetCharInfo(src)
local job = exports.rs_bridge:GetJob(src)
local gang = exports.rs_bridge:GetGang(src)
```

### Jobs / groups

```lua
if exports.rs_bridge:HasJob(src, 'police', 2) then
    print('Police grade 2+')
end

if exports.rs_bridge:HasGroup(src, {'admin', 'god'}, 0) then
    print('Admin-ish')
end
```

### Money

```lua
exports.rs_bridge:AddMoney(src, 'bank', 500, 'mission_reward')
exports.rs_bridge:RemoveMoney(src, 'cash', 100, 'shop_purchase')
exports.rs_bridge:SetMoney(src, 'cash', 250, 'admin_set')

local cash = exports.rs_bridge:GetMoney(src, 'cash')
```

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

### Callbacks

```lua
exports.rs_bridge:RegisterCallback('my_resource:getSomething', function(source, data)
    return {
        ok = true,
        citizenid = exports.rs_bridge:GetCitizenId(source)
    }
end)
```

---

## Client API

### Player data

```lua
local data = exports.rs_bridge:GetPlayerData()
local job = exports.rs_bridge:GetJob()
local gang = exports.rs_bridge:GetGang()
```

### Notify

```lua
exports.rs_bridge:Notify('Hello world.', 'success', 5000)
```

### Progress bar

```lua
local success = exports.rs_bridge:ProgressBar({
    label = 'Searching...',
    duration = 5000,
    canCancel = true,
    disableCombat = true
})

if success then
    print('Done')
end
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

```lua
exports.rs_bridge:AddTargetModel(`prop_atm_01`, {
    {
        label = 'Use ATM',
        icon = 'fa-solid fa-credit-card',
        action = function()
            print('ATM')
        end
    }
})
```

```lua
exports.rs_bridge:AddTargetZone('test_zone', vec3(0.0, 0.0, 72.0), vec3(2.0, 2.0, 2.0), {
    distance = 2.0,
    options = {
        {
            label = 'Use Zone',
            icon = 'fa-solid fa-circle',
            action = function()
                print('zone')
            end
        }
    }
})
```

---

## Recommended pattern for every Reality Sucks resource

At the top of your resource docs, tell buyers:

```cfg
ensure ox_lib
ensure qb-core # or qbx_core
ensure rs_bridge
ensure your_resource
```

Inside your resource code, avoid direct framework calls.

Do this:

```lua
exports.rs_bridge:GetPlayer(source)
exports.rs_bridge:AddItem(source, item, amount, metadata)
exports.rs_bridge:Notify(source, 'Done.', 'success')
```

Avoid this:

```lua
exports['qb-core']:GetCoreObject()
exports.qbx_core:GetPlayer(source)
```

---

## Current coverage

- Framework detection
- QBCore support
- Qbox support
- Standalone fallback
- Player data
- Citizen ID
- Char info
- Job/gang
- Money
- Inventory
- Usable items
- Notifications
- Server callbacks
- Client progress bar
- Target wrappers
- ox_lib support
- ox_inventory support
- ox_target/qb-target/qtarget support

---

## Notes

Standalone mode cannot magically create framework data. It returns safe fallback values so your script does not crash.

For paid releases, keep framework-specific logic inside this bridge or inside small adapter files. Do not scatter QBCore/Qbox checks throughout the whole script.
