# rs_bridge Changelog

## 2.4.0 - Version negotiation and centralized auditing

- Adds `GetVersion()` and `RequireVersion()` on client and server.
- Adds declarative `rs_bridge_version` checks for started resources.
- Adds centralized audit/webhook routing with blank-by-default endpoints and server.cfg convar support.
- Keeps webhook delivery best-effort so logging failures do not interrupt gameplay operations.
- Expands compatibility exports used by current RS resources.

## 2.3.0 - Shared stalker threat model

- Adds `client/threat.lua`, consumed as `@rs_bridge/client/threat.lua`. It is an
  include rather than an export because it holds state and closures, neither of
  which survive FiveM's export serialisation boundary.
- The scalar is extracted faithfully from rs-phantomstalkers v1.6.1
  `RS.UpdateThreat`; every weight is caller-supplied, so that resource passes its
  existing `Config.Brain` values and the arithmetic is unchanged.
- Adds capability awareness: threat BUILD (never decay) scales by whether the
  target is armed, aiming, in a vehicle, wounded, isolated or in a group. The
  group scan is throttled. Off by default.
- Adds an aggression tier that decays. `Engage()` steps up, `Escaped()` steps
  down, and points bleed off once un-engaged for `CalmAfterMs`.
- The decay clock is refreshed while engaged, so the first calm tick after a long
  engagement bleeds aggression off gradually instead of wiping it in one step.

## 2.2.3 - Minigame provider bridge

- Adds `client/minigame.lua`: a provider-neutral minigame layer with the client
  exports `Minigame(intent, opts)` and `GetMinigameProvider()`.
- Callers request a semantic intent (`lockpick`, `hotwire`, `hack`, `generic`)
  rather than a game name, so gameplay code never couples to a provider.
- Resolves `custom` -> `qbx_vehiclekeys` -> `ps-ui` -> `ox_lib` on `auto`, with
  `lib.skillCheck` as a guaranteed floor since ox_lib is already a hard
  dependency. A configured provider that is missing falls through instead of
  failing every attempt.
- Adds `RSBridgeConfig.Minigame`, including a `Custom` escape hatch for minigame
  resources the bridge does not know about, and `Provider = 'none'` to disable
  minigames server-wide.
- Bounds callback-style providers with a timeout so one that never answers fails
  the check instead of hanging the calling thread.
- A refusal caused by a skillcheck already being on screen fails the attempt
  rather than passing it, so overlapping checks cannot grant a free success.
- Adds the `minigame_no_resource` string to en, es, fr and pt-br locales.

## 2.2.2 - Full banking + compatibility merge

- Consolidates the banking and provider updates into the current bridge baseline.
- Adds configurable physical-cash and banking providers.
- Adds `server/cash.lua` and `server/banking.lua`.
- Adds cash, bank-balance, charge, and credit server exports for `rs-banking` integration.
- Preserves the latest ACE permissions, Qbox grade-aware groups, callback multi-return fixes, inventory/useable-item fixes, medical fixes, and vehicle fixes.
- Adds Qbox client PlayerData seed/cache updates without a nonexistent client export.
- Uses ESX account APIs as the preferred money path while retaining fallback compatibility.
- Explicitly packages `client/core.lua`, `client/uiguard.lua`, and `server/core.lua` for `@rs_bridge/...` include compatibility.

## 2.1.4
- Framework bridge hardening for rs-aidoc.

# 2.1.4

- Qbox medical revive now uses the current `qbx_medical` server `Revive` export.
- Qbox money operations prefer current `qbx_core` money exports.
- Dead/down detection reads current Qbox medical state and ESX/QB player state.
- Notification types normalize between ox_lib/Qbox (`inform`) and QBCore (`primary`).
- Preserves single-dispatch revive behavior to prevent double revive/flicker.

# Changelog

## v2.1.3

### Fixed

- Forced medical providers that were not actually running silently claimed success on revive and heal. Every provider branch now gates on `RSBridge.resourceStarted(name)` before attempting its event or export. If the forced resource is not running, the branch falls through to native instead of pretending the call worked.
- Specifically, the previous `qbx_medical` fallback to `TriggerEvent('hospital:client:Revive')` always returned ok = true (TriggerEvent never errors even with zero handlers), masking the case where qbx_medical was forced in config but not started. Same shape applied to every event-based branch (qb-ambulancejob, esx_ambulancejob, ak47_ambulancejob, ars_ambulancejob). All gated now.

### Changed

- Heal is now uniformly belt-and-suspenders: every provider branch runs the provider heal then `nativeHeal()`. This was inconsistent before -- some branches called native, some did not. nativeHeal on an already-healthy ped is invisible (no camera flash, no ped reset), so doubling has zero player-visible cost and guarantees stamina, bleeding flags, and secondary tasks are cleared even when a provider heal misses one of them.
- Revive remains trust-provider-only and does NOT call nativeRevive on success. nativeRevive runs NetworkResurrectLocalPlayer which IS visible, so doubling causes the resurrect flicker bug that v2.1.1 fixed.
- Extracted a single `providerActive(provider, resourceName)` helper used by every branch in both RevivePlayer and HealPlayer. One source of truth for "is this provider both selected and actually running."


## v2.1.2

### Fixed

- Server-side `RevivePlayer(src)` and `HealPlayer(src)` no longer fire framework medical events directly before triggering the bridge client medical handler. The client medical module is now the single provider dispatcher, which prevents qb/qbx/esx revive or heal events from double-firing.
- `qbx_medical` revive and heal calls now attempt direct exports first and fall back to legacy hospital events only if the export call fails. This avoids unreliable export-proxy existence checks.

### Changed

- README title/version updated to v2.1.2.


## v2.1.1

### Fixed

- Locale files had a stray double comma on line 10 that prevented all four built-in language files (en, es, fr, pt-br) from parsing. Every bridge `_L` call returned the raw key string instead of localized text. Single character fix per file.
- Server `IsPlayerDead` / `IsPlayerDown` never received client state because the client never emitted the sync event. Client now pushes dead, last-stand, and current health to the server on meaningful change (every 500ms while changes occur). Server `IsPlayerDead` and `IsPlayerDown` also check framework metadata (`PlayerData.metadata.isdead`, `inlaststand`) first, which is the real source of truth on qb / qbx / esx ambulance jobs.
- `qbx_medical` revive used the wrong event (`qbx_medical:client:playerRevived` is emitted **after** a revive, not used to cause one). Now calls `exports.qbx_medical:Revive()` with a `hospital:client:Revive` legacy fallback.
- `wasabi_ambulance` export casing corrected from `:RevivePlayer()` / `:HealPlayer()` to `:revivePlayer()` / `:healPlayer()`.
- Server `HealPlayer` now clears pending dead and last-stand state so a heal-after-kill leaves the player in a clean state.
- Provider events no longer always double up with `nativeRevive` / `nativeHeal` on success. The native call only runs on `provider = 'native'`, when `UseResourceEvents = false`, or when the provider export call returned an error. Removes the resurrect flicker on qb-ambulancejob and qbx_medical.

### Added

- Server `GetHealth(src)` returns the last health value the client synced (defaults to 200 until first sync).
- Client medical sync loop fires `rs_bridge:server:setMedicalState` with dead, down, and health on meaningful change.

### Changed

- Renamed the server net event `rs_bridge:server:setDeathState` to `rs_bridge:server:setMedicalState` to reflect the expanded payload. The old event name was never emitted from anywhere, so this is a safe rename.
- Server `SetHealth` and `KillPlayer` now also cache the value in pendingState so `GetHealth` is correct immediately, even before the next client sync round-trip.


## v2.1.0

### Added

- Medical / ambulance bridge module.
- Client exports: GetHealth, SetHealth, SetArmor, HealPlayer, RevivePlayer, KillPlayer, IsPlayerDead, IsPlayerDown.
- Server exports: RevivePlayer, HealPlayer, SetArmor, SetHealth, KillPlayer, IsPlayerDead, IsPlayerDown.
- Medical provider config with support targets for qb-ambulancejob, qbx_medical, esx_ambulancejob, wasabi_ambulance, ak47_ambulancejob, ars_ambulancejob, and native fallback.
- Medical locale strings in en, es, fr, and pt-br.

### Fixed

- ESX charinfo normalization no longer calls xPlayer.get('firstName') / xPlayer.get('lastName') directly.
- ESX charinfo now tries identifier, getIdentifier, getName, and xPlayer.variables safely.


## v2.0.0

### Added

- ESX framework detection.
- Modern ESX Legacy `exports['es_extended']:getSharedObject()` support.
- Old ESX `esx:getSharedObject` fallback support.
- `IsESX()` export.
- ESX player data normalization.
- ESX money support.
- ESX job support.
- ESX usable item support.
- ESX notification support.
- Locale system with `LoadLocales`, `Translate`, and `_L`.
- Built-in languages: English, Spanish, French, Portuguese Brazil.
- Fuel bridge with LegacyFuel, lj-fuel, ps-fuel, cdn-fuel, ox_fuel, ti_fuel, BigDaddy-Fuel, x-fuel, lc_fuel, okokGasStation, and native fallback.
- Inventory adapter dispatcher.
- Additional inventory adapter attempts for qs, codem, ps, tgiann, core, and origen inventories.
- Extra progress adapters for mythic_progbar, rprogress, and rs_progressbar.
- Server fuel provider export.
- More defensive safe-call fallbacks.

### Changed

- Version bumped to v2.0.0.
- Internal structure expanded for public multi-framework releases.
- Progress, inventory, and target handling are more adapter-driven.

### Removed

- Hard dependency on `@ox_lib/init.lua` so standalone users without ox_lib do not crash on load.
