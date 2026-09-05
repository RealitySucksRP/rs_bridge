-- ===========================================================================
-- rs_bridge -- YOUR server's settings
-- ===========================================================================
--
-- THIS FILE IS YOURS. Set it once for your server and keep it.
--
-- When you update rs_bridge, replace every file EXCEPT this one. A bridge
-- update that overwrites config.lua silently reverts your stack settings, and
-- the symptoms do not point anywhere near a file copy -- see Cash.Provider
-- below for the one that costs the most time.
--
--   robocopy <new bridge> <your rs_bridge> /E /XF config.lua
--
-- MOST OF THIS NEEDS NO EDITING. Framework, inventory, target, fuel and
-- progress all default to 'auto' and are detected at runtime, which is the
-- whole point of the bridge. Change something only when detection is wrong or
-- you want to force a specific provider.
--
-- The settings that actually depend on YOUR stack, in the order they bite:
--
--   Cash.Provider   how physical cash is stored. Wrong = every balance reads
--                   zero and every charge fails.
--   Cash.Item       which item IS the cash account, when cash is an item.
--   Webhooks        blank by default. Yours, if you want them.
--
-- ===========================================================================

RSBridgeConfig = {}

-- auto order: qbox -> qbcore -> esx -> standalone
-- valid: auto, qbox, qbcore, esx, standalone
--
-- Leave this on 'auto' unless detection is ambiguous (custom forks, or a
-- compatibility shim that makes two frameworks look present at once).
-- If qbx_core is running, Qbox always wins detection; the QBCore layer is
-- never initialised alongside it.
RSBridgeConfig.Framework = 'auto'

RSBridgeConfig.Debug = false

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
    -- 'framework' falls back to the core's own player inventory functions.
    Provider = 'auto'
}

RSBridgeConfig.Target = {
    -- auto, ox_target, qb-target, qtarget, bt-target, none
    Provider = 'auto',
    DefaultDistance = 2.0
}

RSBridgeConfig.Progress = {
    -- auto, ox_lib, progressbar, mythic_progbar, rprogress, rs_progressbar, none
    --
    -- Set to 'progressbar' for the RS Pip-Boi bar. On 'auto' the RS bar is
    -- preferred when installed and ox_lib is used otherwise, so 'auto' is a
    -- safe choice too; naming it explicitly just makes the intent obvious.
    --
    -- A configured provider that turns out to be missing falls through to the
    -- others rather than silently running with no bar at all.
    Provider = 'progressbar'
}

RSBridgeConfig.Minigame = {
    -- auto, qbx_vehiclekeys, ps-ui, ox_lib, custom, none
    --
    -- Callers request an intent ('lockpick', 'hotwire', 'hack', 'generic') and
    -- the bridge maps it onto the installed provider, so gameplay code never
    -- names a specific minigame. 'none' skips the check and lets the gated
    -- action through; use it to disable minigames server-wide.
    --
    -- ox_lib is the guaranteed floor: it is already a hard dependency, so a
    -- configured provider that goes missing still degrades to a real check.
    Provider = 'auto',

    DefaultDifficulty = 'medium',
    DefaultInputs = { 'w', 'a', 's', 'd' },

    -- Bounds callback-style providers so one that never answers fails the
    -- check instead of hanging the calling thread forever.
    TimeoutMs = 60000,

    -- Only consulted if every provider is missing, which cannot happen while
    -- ox_lib is installed. true keeps gated actions usable on a broken install;
    -- false refuses them.
    FallbackResult = true,

    -- Escape hatch for a minigame resource the bridge does not know about.
    -- The export is called as export(intent, options) and must return a boolean.
    -- Custom = { resource = 'my_minigames', export = 'Play' },
    Custom = nil
}

RSBridgeConfig.Fuel = {
    -- auto, LegacyFuel, lj-fuel, ps-fuel, cdn-fuel, ox_fuel, ti_fuel,
    -- BigDaddy-Fuel, x-fuel, lc_fuel, okokGasStation, native
    Provider = 'auto'
}


RSBridgeConfig.Vehicles = {
    -- Ownership table. 'auto' picks by framework:
    --   qbox / qbcore -> player_vehicles
    --   esx           -> owned_vehicles
    -- Override only if you run a custom ownership schema.
    OwnershipTable = 'auto',

    -- Column names differ between ecosystems. 'auto' resolves per framework.
    -- qbox/qbcore: citizenid + plate + mods
    -- esx:         owner + plate + vehicle
    IdentifierColumn = 'auto',
    PlateColumn = 'plate',
    PropsColumn = 'auto',

    -- auto, qbx_vehiclekeys, qb-vehiclekeys, wasabi_carlock,
    -- cd_garage, mk_vehiclekeys, none
    -- 'none' disables key handling entirely; resources that treat keys as
    -- optional will keep working.
    KeysProvider = 'auto'
}

-- ============================================================
-- AUDIT WEBHOOKS (v2.4)
--
-- Resolution order, most specific first:
--   1. convar  set rs_webhook_<category>     e.g. rs_webhook_money
--   2. convar  set rs_webhook_<resource>     e.g. rs_webhook_rs-banking
--   3. convar  set rs_webhook_default
--   4. this table, same three keys
--
-- Convars win deliberately. A webhook URL is a secret and config.lua ships
-- inside the resource, so anything written below travels with the ZIP to
-- whoever receives it. Leave these empty and set the real endpoints in
-- server.cfg; they exist so a server owner who prefers configuring here can,
-- and so the resource works out of the box for someone who never touches cfg.
--
-- Categories currently emitted: money, item, admin, crime, job.
-- ============================================================
RSBridgeConfig.Webhooks = {
    default = '',
    money   = '',
    item    = '',
    admin   = '',
    crime   = '',
    job     = '',
}

RSBridgeConfig.Cash = {
    -- ---------------------------------------------------------------------
    -- THE ONE SETTING MOST WORTH GETTING RIGHT. Where does physical cash live?
    --
    --   'auto'            framework accounts (Player.PlayerData.money.cash).
    --                     Correct for QBCore + qb-inventory, and for any stack
    --                     where cash is NOT an inventory item.
    --   'inventory_item'  cash is an item in the inventory. Correct for Qbox +
    --                     ox_inventory, where ox syncs the `money` item count
    --                     to the cash balance both ways.
    --
    -- Getting this wrong is not subtle, but it does not name itself. On QBCore
    -- with 'inventory_item', GetCash counts a `money` item that does not exist,
    -- so every balance reads 0 and every RemoveCash fails -- while the HUD keeps
    -- showing the real account. It looks like a broken shop, not a config line.
    --
    -- If you are unsure: 'auto' is the safe default. Set 'inventory_item' only
    -- when you know cash is an item on your inventory.
    -- ---------------------------------------------------------------------
    Provider = 'auto',
    -- 'money', NOT 'cash'. With ox_inventory + Qbox the `money` item IS the cash
    -- account -- ox syncs the item count to the balance both ways. Pointing at a
    -- separate `cash` item created a second wallet that nothing else could see:
    -- the HUD showed the account while rs-banking's ATM read the `cash` item and
    -- reported "Not enough physical cash" against a multi-million balance.
    Item = 'money'
}

RSBridgeConfig.Banking = {
    -- auto prefers rs-banking when started, otherwise framework bank money.
    Provider = 'auto'
}

RSBridgeConfig.Medical = {
    -- auto, qb-ambulancejob, qbx_medical, esx_ambulancejob,
    -- wasabi_ambulance, ak47_ambulancejob, ars_ambulancejob, native
    Provider = 'auto',

    -- true = try resource-specific revive/heal events first
    -- false = use native fallback only
    UseResourceEvents = true,

    -- fallback values
    ReviveHealth = 200,
    HealHealth = 200,
    DefaultArmor = 100
}
