--[[
    rs_bridge -- shared audit webhook (SERVER)

    Fifteen RS resources move money or items with no audit trail at all. Giving
    each its own webhook would mean fifteen implementations, fifteen embed
    formats, fifteen convars to find, and fifteen independent ways to trip
    Discord's rate limit. This is one implementation they all call.

    Usage from any resource:

        exports.rs_bridge:Audit('money', {
            title  = 'Chop payout',
            actor  = source,
            amount = 3000,
            reason = 'engine',
        })

    Routing, in order: a category convar, then the resource convar, then the
    global one. That lets an owner send everything to one channel by setting a
    single convar, or split money away from admin actions, without any resource
    needing to know which.

        set rs_webhook_default   "<your Discord webhook URL>"
        set rs_webhook_money     "<your category webhook URL>"   -- optional, per category
        set rs_webhook_rs-banking "<your resource webhook URL>"  -- optional, per resource

    Deliberately best-effort. Every entry point is wrapped so a webhook outage,
    a bad URL or a malformed payload can never fail or roll back the gameplay
    action that produced it -- an audit trail that can break a purchase is worse
    than no audit trail.
]]

local QUEUE_INTERVAL_MS = 1200   -- Discord tolerates ~5 req/s; stay well under.
local MAX_QUEUE = 200            -- Drop rather than grow without bound.
local MAX_FIELD = 900            -- Discord embed description cap is 4096.

local COALESCE_WINDOW = 30      -- seconds of quiet before a group is emitted
local LOUD_AMOUNT = 5000        -- at or above this, always send individually

local queue = {}
local draining = false
local urlCache = {}
local coalescing = {}

local COLORS = {
    money = 15844367,   -- gold
    item = 3447003,     -- blue
    admin = 10038562,   -- dark red
    crime = 15158332,   -- red
    job = 2123412,      -- green
    default = 9807270,  -- grey
}

local function convar(name)
    local value = GetConvar(name, '')
    if value == nil then return '' end
    return value
end

---Reads a URL out of RSBridgeConfig.Webhooks, if the owner configured it there.
local function configured(key)
    local cfg = RSBridgeConfig and RSBridgeConfig.Webhooks
    if type(cfg) ~= 'table' then return '' end
    local value = cfg[key]
    if type(value) ~= 'string' then return '' end
    return value
end

---Resolves the destination for a category, most specific first.
---
---Convars are checked BEFORE config.lua on purpose. A webhook URL is a secret,
---and config.lua ships inside the resource: anything written there travels with
---the ZIP to whoever receives it. Keeping the live URL in server.cfg means the
---shipped config can carry a harmless empty placeholder while the real endpoint
---never leaves the server. Owners who would rather configure in config.lua
---still can -- it simply loses to a convar when both are set.
local function resolveUrl(category, resource)
    local key = ('%s|%s'):format(tostring(category), tostring(resource))
    local cached = urlCache[key]
    if cached ~= nil then return cached end

    local url = convar('rs_webhook_' .. tostring(category))
    if url == '' then url = convar('rs_webhook_' .. tostring(resource)) end
    if url == '' then url = convar('rs_webhook_default') end
    if url == '' then url = configured(tostring(category)) end
    if url == '' then url = configured(tostring(resource)) end
    if url == '' then url = configured('default') end

    -- Only accept something that actually looks like a webhook endpoint, so a
    -- convar holding an unrelated value cannot cause outbound requests.
    if url ~= '' and not url:match('^https://[%w%.%-]+/api/webhooks/') then
        RSBridge.debug(('webhook: ignoring non-webhook URL in convar for %s'):format(tostring(category)))
        url = ''
    end

    urlCache[key] = url
    return url
end

---Clears the cache so convar edits apply without a restart.
function ReloadWebhooks()
    urlCache = {}
    return true
end

local function truncate(text)
    text = tostring(text or '')
    if #text <= MAX_FIELD then return text end
    return text:sub(1, MAX_FIELD - 3) .. '...'
end

local function describeActor(actor)
    local src = tonumber(actor)
    if not src or src <= 0 then
        return actor and tostring(actor) or 'system'
    end
    local name = GetPlayerName(src)
    if not name then return ('source %s (offline)'):format(src) end

    -- Identifiers make an audit line actionable after the player reconnects on
    -- a different source id.
    local license = GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
    return ('%s (%s)%s'):format(name, src, license and ('\n**License:** `%s`'):format(license) or '')
end

local function drain()
    if draining then return end
    draining = true

    CreateThread(function()
        while #queue > 0 do
            local entry = table.remove(queue, 1)
            RSBridge.safeCall(function()
                PerformHttpRequest(entry.url, function() end, 'POST', json.encode(entry.body),
                    { ['Content-Type'] = 'application/json' })
            end)
            Wait(QUEUE_INTERVAL_MS)
        end
        draining = false
    end)
end

---Sends one audit record.
---@param category string 'money' | 'item' | 'admin' | 'crime' | 'job' | any
---@param data table { title, actor, target, amount, account, item, count, reason, detail, ok, resource }
---@return boolean queued
function Audit(category, data)
    category = tostring(category or 'default')
    data = type(data) == 'table' and data or {}

    local resource = data.resource or GetInvokingResource() or GetCurrentResourceName()
    local url = resolveUrl(category, resource)
    if url == '' then return false end

    if #queue >= MAX_QUEUE then
        RSBridge.debug('webhook: queue full, dropping audit record')
        return false
    end

    local lines = { ('**Actor:** %s'):format(describeActor(data.actor)) }
    if data.target ~= nil then
        lines[#lines + 1] = ('**Target:** %s'):format(describeActor(data.target))
    end
    if tonumber(data.amount) then
        lines[#lines + 1] = ('**Amount:** $%s%s'):format(
            tostring(math.floor(tonumber(data.amount))),
            data.account and (' (' .. tostring(data.account) .. ')') or '')
    end
    if data.item then
        lines[#lines + 1] = ('**Item:** %s x%s'):format(tostring(data.item), tostring(data.count or 1))
    end
    if data.reason then lines[#lines + 1] = ('**Reason:** %s'):format(tostring(data.reason)) end
    if data.detail then lines[#lines + 1] = truncate(data.detail) end
    if data.ok ~= nil then
        lines[#lines + 1] = ('**Result:** %s'):format(data.ok and 'applied' or 'refused')
    end

    -- COALESCING
    --
    -- Repetitive small payouts are the normal case, not the exception: killing
    -- zombies pays roughly $50 a time, so a busy player would generate a webhook
    -- per kill and hit Discord's rate limit within seconds, burying every record
    -- that actually matters. Identical records from the same actor, resource and
    -- title are merged inside a short window and emitted once as a summary.
    --
    -- Anything at or above LOUD_AMOUNT bypasses this and is always sent on its
    -- own, so a single large movement is never hidden inside a summary line.
    local amountValue = tonumber(data.amount) or 0
    if amountValue < LOUD_AMOUNT then
        local key = ('%s|%s|%s|%s'):format(resource, category, tostring(data.actor), tostring(data.title))
        local group = coalescing[key]
        if group then
            group.count = group.count + 1
            group.total = group.total + amountValue
            group.last = os.time()
            return true
        end
        coalescing[key] = {
            count = 1, total = amountValue, first = os.time(), last = os.time(),
            url = url, category = category, resource = resource,
            title = data.title or category, actor = data.actor,
            account = data.account, reason = data.reason,
        }
        return true
    end

    queue[#queue + 1] = {
        url = url,
        body = {
            username = ('RS Audit - %s'):format(tostring(resource)),
            embeds = { {
                title = truncate(data.title or category),
                color = COLORS[category] or COLORS.default,
                description = truncate(table.concat(lines, '\n')),
                footer = { text = ('%s | %s'):format(tostring(resource), tostring(category)) },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            } },
        },
    }

    drain()
    return true
end

-- Emits each coalesced group once it has been quiet for COALESCE_WINDOW, so a
-- burst of repeated payouts lands as one line instead of hundreds. A group of
-- exactly one is reported as a plain record rather than a summary.
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for key, group in pairs(coalescing) do
            if now - group.last >= COALESCE_WINDOW then
                coalescing[key] = nil
                if #queue < MAX_QUEUE then
                    local lines = { ('**Actor:** %s'):format(describeActor(group.actor)) }
                    if group.count > 1 then
                        lines[#lines + 1] = ('**Occurrences:** %s over %ss')
                            :format(group.count, math.max(1, group.last - group.first))
                        lines[#lines + 1] = ('**Total:** $%s'):format(math.floor(group.total))
                        lines[#lines + 1] = ('**Average:** $%s'):format(math.floor(group.total / group.count))
                    else
                        lines[#lines + 1] = ('**Amount:** $%s'):format(math.floor(group.total))
                    end
                    if group.account then lines[#lines + 1] = ('**Account:** %s'):format(tostring(group.account)) end
                    if group.reason then lines[#lines + 1] = ('**Reason:** %s'):format(tostring(group.reason)) end

                    queue[#queue + 1] = {
                        url = group.url,
                        body = {
                            username = ('RS Audit - %s'):format(tostring(group.resource)),
                            embeds = { {
                                title = group.count > 1
                                    and ('%s (x%s)'):format(tostring(group.title), group.count)
                                    or tostring(group.title),
                                color = COLORS[group.category] or COLORS.default,
                                description = truncate(table.concat(lines, '\n')),
                                footer = { text = ('%s | %s%s'):format(tostring(group.resource),
                                    tostring(group.category), group.count > 1 and ' | summarised' or '') },
                                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                            } },
                        },
                    }
                    drain()
                end
            end
        end
    end
end)

---Never lets an audit failure reach the caller.
local function safeAudit(category, data)
    local ok = RSBridge.safeCall(Audit, category, data)
    return ok == true
end

exports('Audit', safeAudit)
exports('ReloadWebhooks', ReloadWebhooks)
