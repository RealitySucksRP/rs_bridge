-- Normalized player lifecycle events (server).
--
-- Qbox fires most QBCore:Server:* names natively, so those handlers cover both
-- Qbox and QBCore. ESX uses entirely different names, which is the gap this
-- closes.
--
-- ONE name differs between the two and it is the important one:
--   qb-core fires  QBCore:Server:OnPlayerLoaded()   -- id comes from `source`
--   Qbox    fires  QBCore:Server:PlayerLoaded(player) -- no "On", passes the object
-- Verified against the installed qbx_core: it never fires OnPlayerLoaded. Only
-- listening for the qb-core name meant playerLoaded never emitted on Qbox at
-- all. Both are handled below.
--
-- Resources should listen to the rs_bridge:server:* events below instead of
-- any framework's names:
--
--   rs_bridge:server:playerLoaded    (src)
--   rs_bridge:server:playerUnloaded  (src)
--   rs_bridge:server:jobUpdate       (src, job)
--   rs_bridge:server:gangUpdate      (src, gang)
--   rs_bridge:server:dutyChange      (src, onDuty)
--   rs_bridge:server:moneyChange     (src, moneyType, amount, operation, reason)
--   rs_bridge:server:groupUpdate     (src, groupName, groupGrade)   Qbox only
--   rs_bridge:server:metadataChange  (src, key, oldValue, newValue)  Qbox only

local function emit(name, ...)
    TriggerEvent('rs_bridge:server:' .. name, ...)
end

-- ---------- Qbox / QBCore ----------

-- BOTH names fire on Qbox, which is why this is debounced:
--   QBCore:Server:OnPlayerLoaded  -- NET event, sent by qbx_core/client/character.lua
--                                    via TriggerServerEvent (also the qb-core name)
--   QBCore:Server:PlayerLoaded    -- LOCAL server event carrying the player object,
--                                    raised by qbx_core/server/player.lua
-- Listening to both without a guard emitted rs_bridge:server:playerLoaded twice
-- per spawn on Qbox, double-firing every consumer.
local recentPlayerLoaded = {}
local PLAYER_LOADED_DEBOUNCE_MS = 2000

local function emitPlayerLoaded(src)
    src = tonumber(src)
    if not src or src <= 0 then return end

    local now = GetGameTimer()
    local last = recentPlayerLoaded[src]
    if last and (now - last) < PLAYER_LOADED_DEBOUNCE_MS then return end

    recentPlayerLoaded[src] = now
    emit('playerLoaded', src)
end

AddEventHandler('playerDropped', function()
    recentPlayerLoaded[source] = nil
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    emitPlayerLoaded(source)
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    emitPlayerLoaded(player and player.PlayerData and player.PlayerData.source or source)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    emit('playerUnloaded', src or source)
end)

AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job)
    emit('jobUpdate', src, job)
end)

AddEventHandler('QBCore:Server:OnGangUpdate', function(src, gang)
    emit('gangUpdate', src, gang)
end)

AddEventHandler('QBCore:Server:SetDuty', function(src, onDuty)
    emit('dutyChange', src, onDuty)
end)

AddEventHandler('QBCore:Server:OnMoneyChange', function(src, moneyType, amount, operation, reason)
    emit('moneyChange', src, moneyType, amount, operation, reason)
end)

-- ---------- Qbox-native names ----------
-- No QBCore equivalent exists for either of these.

AddEventHandler('qbx_core:server:onGroupUpdate', function(src, groupName, groupGrade)
    emit('groupUpdate', src, groupName, groupGrade)
end)

AddEventHandler('qbx_core:server:onSetMetaData', function(key, oldValue, newValue, src)
    emit('metadataChange', src, key, oldValue, newValue)
end)

-- ---------- ESX ----------

AddEventHandler('esx:playerLoaded', function(src)
    emit('playerLoaded', src)
end)

AddEventHandler('esx:playerDropped', function(src)
    emit('playerUnloaded', src)
end)

AddEventHandler('esx:setJob', function(src, job)
    -- Normalize the ESX job shape onto the grade table the rest of the
    -- bridge exposes, so listeners do not have to branch per framework.
    emit('jobUpdate', src, job and {
        name = job.name,
        label = job.label,
        grade = { level = job.grade, name = job.grade_label or job.grade_name },
        onduty = true
    } or nil)
end)
