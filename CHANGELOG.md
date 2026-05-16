# Changelog

## v2.0.0

First public multi-framework release.

### Added

- ESX framework detection.
- Modern ESX Legacy `exports['es_extended']:getSharedObject()` support.
- Old ESX `esx:getSharedObject` event-callback fallback (1.2 and below).
- `IsESX()` export, available on both client and server.
- ESX player data normalization through `normalizeESXPlayerData` helper.
- ESX money support for cash, money, and bank accounts via `addMoney`, `addAccountMoney`, etc.
- ESX job exposure with grade normalization on client and server.
- ESX usable item registration through `ESX.RegisterUsableItem`.
- ESX server-side notifications via `esx:showNotification`.
- ESX server callback registration via `ESX.RegisterServerCallback`.
- Defensive ESX char info reader that tries `xPlayer.variables`, direct keys, and the old `xPlayer.get(key)` API.
- Locale system: `LoadLocales`, `Translate`, `_L` with sandboxed loader and namespaced lookups.
- Bundled languages: English, Spanish, French, Portuguese (Brazil).
- Fuel bridge module covering LegacyFuel, lj-fuel, ps-fuel, cdn-fuel, ox_fuel (state bag), ti_fuel, BigDaddy-Fuel, x-fuel, lc_fuel, okokGasStation, with native `GetVehicleFuelLevel` / `SetVehicleFuelLevel` fallback.
- Server-side `GetFuelProvider` export so other resources can branch on the active provider.
- Inventory adapter dispatcher with table-driven providers.
- New inventory adapters: qs-inventory, codem-inventory, ps-inventory, tgiann-inventory, core_inventory, origen_inventory.
- Progress bar adapters: mythic_progbar, rprogress, rs_progressbar (in addition to ox_lib and qb progressbar).
- Provider caching with `onResourceStart` invalidation for target and fuel detection.
- Banner image (`rs_bridge.png`) included in repository for README and documentation.

### Changed

- Version bumped to v2.0.0.
- Bridge is now adapter-driven for inventory, progress, target, and fuel.
- `HasJob` accepts a single name string or a list of names; falls back through framework when needed.
- `HasGroup` now checks Qbox groups, ESX groups, and falls back to `HasJob`.
- `GetItemCount` fallback chain reads `found.amount`, `found.count`, `found.quantity`, `found.qty`.
- Client `GetJob` normalizes ESX numeric grade into the QB-style `{ level, name }` table so callers can always read `job.grade.level`.

### Fixed

- ESX charinfo reader previously only used the old `xPlayer.get(key)` API, which returns nil on most ESX Legacy forks. Now tries multiple known paths.
- Duplicate `found.count` in `GetItemCount` fallback replaced with `found.qty`.
- Restored `@ox_lib/init.lua` in `shared_scripts` and added `dependency 'ox_lib'`. The previous removal left `lib` undefined inside the bridge resource, which silently disabled every ox_lib code path even on servers that had ox_lib started. Standalone-without-ox_lib users can remove the include line manually -- the bridge falls through to framework or chat fallbacks.

### Notes

- Some third-party inventories and fuel scripts use different export names across versions. The bridge wraps every adapter call in `pcall` and falls back to framework or native paths on error. Version-specific patches are welcome via pull request.
- ESX job and gang labels use locale strings (`_L('unemployed')`, `_L('no_job')`, `_L('no_gang')`) so server admins can translate framework defaults without touching ESX itself.

## v1.1.0

- Framework detection for QBCore, Qbox, and standalone.
- Server exports for player data, citizen ID, char info, jobs, gangs, groups, money, items, usable items, notifications, and callbacks.
- Client exports for player data, jobs, gangs, notifications, progress bars, and target wrappers.
- ox_lib notify/progress support.
- ox_inventory support.
- ox_target, qb-target, qtarget, bt-target detection.
- Standalone-safe fallback values.
