-- RUIN Exchange
-- Auction prices (a full scan when the auction house opens, plus what you
-- browse) are shared with RUIN
-- when you close it, so everyone has fresh prices without scanning; a daily
-- history gives each price a 7-day trend. Opening a profession window
-- shares your recipes ("who in RUIN can craft this") and works out the
-- cheapest next skill-up from RUIN prices. Members post craft requests, and
-- a bag sweep labels every item keep, sell or vendor. The guild's treasurer
-- keeps a treasury book (Treasury.lua), and crafts confirmed by both sides
-- make a crafting history (History.lua).
local ADDON, ns = ...

-- WoW Forever runs on the Retail 12 client, where the old global item
-- functions may be gone; these ask C_Item when they are. (Inside each
-- function the name still means the global, so tests and older clients work.)
local GetItemInfo = function(...)
    local f = GetItemInfo or (C_Item and C_Item.GetItemInfo)
    if f then return f(...) end
end
local GetItemInfoInstant = function(...)
    local f = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
    if f then return f(...) end
end
local R = RUIN_API
if not R or (R.apiLevel or 1) < 9 then
    print("|cff54b7d9[RUIN]|r Exchange needs a newer RUIN Core (0.3.16 or later).")
    return
end
local W = R.Widgets
local C = W.COLORS

-- What the player lets RUIN share about them (RUIN Core: Settings > Display)
local function shares(kind) return not (R.Shares and not R:Shares(kind)) end

local M = R:RegisterModule("Exchange", { version = "0.9.1" })

local DEFAULTS = { prices = {}, vendor = {}, rskill = {}, recipeBook = {}, crafters = {}, tooltip = true, history = {}, requests = {}, plans = {} }
local PRICE_BATCH = 40
local HISTORY_DAYS = 14
local REQUEST_HOURS = 24
local AH_DEPOSIT = 0.15         -- listing costs 15% of what a vendor pays (12 hours), at least 1 copper; lost whether it sells or not
local AH_CUT = 0.05             -- the auction house keeps 5% of the sale

-- What selling on the auction house actually brings in: the price less the
-- house's cut and the deposit (from the vendor price, at least 1 copper).
local function ahNet(unit, count, sell)
    if not unit then return nil end
    count = count or 1
    return math.floor(unit * count * (1 - AH_CUT)) - math.max(1, math.floor((tonumber(sell) or 0) * count * AH_DEPOSIT))
end
local SKILLUP_CHANCE = { [0] = 1, [1] = 0.75, [2] = 0.25 }        -- orange, yellow, green
local OVERTIME_PER_RANK = 0.04      -- Working Overtime (Legacy): +4% skill-up chance a rank, 5 ranks
local DIFFICULTY_NAME = { [0] = "|cffff8040orange|r", [1] = "|cffffff00yellow|r", [2] = "|cff40c040green|r" }
local CLASSIC_DIFFICULTY = { optimal = 0, medium = 1, easy = 2, trivial = 3 }

local db
local session = {}       -- itemID -> lowest unit price seen during this AH visit
local ui = { mode = "Crafters", query = "", prof = "All professions" }
local refreshPage = function() end

local function dayKey(t) return math.floor((t or GetServerTime()) / 86400) end

local function itemInfo(id)
    if not GetItemInfo then return nil end
    if R.Items.IsCached and not R.Items.IsCached(tonumber(id) or id) then R.Items.Request(tonumber(id) or id); return nil end
    local name, link, quality, _, _, class, _, _, equip, _, sell = GetItemInfo(id)
    if not name then R.Items.Request(tonumber(id) or id) end
    return name, link, quality, sell, class, equip
end

-- Whether an item can never go on the auction house: it binds when picked up
-- (so it's soulbound once it's yours) or it's a quest item.
local function cannotTrade(id)
    if not (GetItemInfo and id) then return false end
    local bind = select(14, GetItemInfo(id))
    return bind == 1 or bind == 4
end
M.CannotTrade = cannotTrade

---------------------------------------------------------------------------
-- Prices and history
---------------------------------------------------------------------------
local function noteHistory(id, price, t)
    local h = db.history[id] or {}
    local d = dayKey(t)
    if not h[d] or price < h[d] then h[d] = price end
    for k in pairs(h) do if k < d - HISTORY_DAYS then h[k] = nil end end
    db.history[id] = h
end

-- The price RUIN keeps is the lowest buyout: a sighting that isn't the whole
-- auction house (a page of results, another player's share) only replaces a
-- lower price once that price is older than FRESH_LOW. Only a full scan,
-- which sees every listing, replaces a lower price right away.
local FRESH_LOW = 6 * 3600
local function keepsLower(cur, p, t)
    return cur and cur.p and cur.p > 0 and cur.p < p and (t - (cur.t or 0)) < FRESH_LOW
end
M.KeepsLower = keepsLower

-- `whole`: the sighting is the auction house's whole answer for that item (a
-- search of it, its browse row, its commodity list), so it replaces the price
-- even when it's higher. A page of a list isn't, so it only replaces a lower
-- price once that one is old (keepsLower).
local function notePrice(id, unit, whole)
    id, unit = tonumber(id), tonumber(unit)
    if not id or not unit or unit <= 0 then return end
    M.priceGen = (M.priceGen or 0) + 1      -- remembered tooltip sums are stale now
    unit = math.floor(unit)
    -- the visit's lowest is what gets shared when the auction house closes
    if not session[id] or unit < session[id] then session[id] = unit end
    local now = GetServerTime()
    noteHistory(id, unit, now)
    if ns.Watch then ns.Watch.Seen(id, unit, UnitName("player")) end
    if not whole and keepsLower(db.prices[id], unit, now) then return end
    db.prices[id] = { p = unit, t = now, by = UnitName("player") }
end

-- Price history only trims an item's old days when it's seen again: at login,
-- drop the old days of everything (and items with none left), so items you
-- stopped seeing don't sit in memory and the saved file for good.
function M.PruneHistory()
    if type(db.history) ~= "table" then return 0 end
    local oldest, dropped = dayKey(GetServerTime()) - HISTORY_DAYS, 0
    for id, h in pairs(db.history) do
        if type(h) ~= "table" then db.history[id] = nil
        else
            for d in pairs(h) do if type(d) ~= "number" or d < oldest then h[d] = nil end end
            if next(h) == nil then db.history[id] = nil; dropped = dropped + 1 end
        end
    end
    return dropped
end

-- The price Exchange uses for an item: the lowest listing last seen on the
-- auction house (yours or one shared by RUIN). Only when it has never been
-- seen does the low end of the last week's prices stand in.
-- Returns that and the current lowest listing.
function M.ExpectedPrice(id)
    local cur = db.prices[id]
    local now = cur and cur.p and cur.p > 0 and cur.p or nil
    if now then return now, now end
    local low
    local h = db.history[id]
    if type(h) == "table" then
        local today = dayKey()
        for d, v in pairs(h) do
            if type(d) == "number" and d > today - 7 and type(v) == "number" and v > 0 and (not low or v < low) then low = v end
        end
    end
    return low, nil
end

-- Average of the last 7 days and the trend against the 7 days before.
function M:Trend(id)
    local h = db.history[id]
    if not h then return nil end
    local today = dayKey()
    local recent, rn, older, on = 0, 0, 0, 0
    for d, p in pairs(h) do
        if d > today - 7 then recent, rn = recent + p, rn + 1
        elseif d > today - 14 then older, on = older + p, on + 1 end
    end
    if rn == 0 then return nil end
    local avg = recent / rn
    local pct = (on > 0 and older > 0) and ((avg - older / on) / (older / on) * 100) or nil
    return avg, pct, rn
end

local function trendText(pct)
    if not pct then return "" end
    if pct >= 3 then return ("|cff40ff40+%d%%|r"):format(pct) end
    if pct <= -3 then return ("|cffff6060%d%%|r"):format(pct) end
    return C.dim .. "steady|r"
end

-- Classic-style auction list (one page at a time)
local function onClassicList()
    if not (GetNumAuctionItems and GetAuctionItemInfo) then return end
    for i = 1, GetNumAuctionItems("list") or 0 do
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemId = GetAuctionItemInfo("list", i)
        if buyout and buyout > 0 and count and count > 0 then notePrice(itemId, buyout / count) end
    end
end

-- Retail-style browse results
local function onBrowse()
    if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return end
    for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        if r.itemKey then notePrice(r.itemKey.itemID, r.minPrice, true) end
    end
end

-- Clicking into an item: the cheapest listings of a commodity or of one item
local function onCommodity(_, itemID)
    local AH = C_AuctionHouse
    if not (AH and AH.GetCommoditySearchResultInfo and itemID) then return end
    -- every listing read, not just the first: the list can be sorted either way
    local n = AH.GetNumCommoditySearchResults and AH.GetNumCommoditySearchResults(itemID) or 1
    local best
    for i = 1, math.max(n or 0, 1) do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r and r.unitPrice and r.unitPrice > 0 and (not best or r.unitPrice < best) then best = r.unitPrice end
    end
    if best then notePrice(itemID, best, true) end
end

local function onItemSearch(_, itemKey)
    local AH = C_AuctionHouse
    if not (AH and AH.GetNumItemSearchResults and type(itemKey) == "table") then return end
    local best
    for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do      -- all of them: the list can be sorted dearest first
        local r = AH.GetItemSearchResultInfo(itemKey, i)
        local each = r and r.buyoutAmount and r.quantity and r.quantity > 0 and r.buyoutAmount / r.quantity
        if each and each > 0 and (not best or each < best) then best = each end
    end
    if best then notePrice(itemKey.itemID, best, true) end
end

-- Full scan: the whole auction house at once (the game allows one every
-- 15 minutes). It runs by itself when you open the auction house and the
-- last one is old enough; `/ex scan` asks for one.
local FULL_SCAN_GAP = 15 * 60
local SCAN_CHUNK = 1500
local SCAN_BUDGET = 3           -- milliseconds a frame for reading a full scan's listings
local scanning, ahOpen

-- The items in your bags: their prices come first in a scan.
local function bagItemIds()
    local out = {}
    local CC = rawget(_G, "C_Container")
    if not (CC and CC.GetContainerNumSlots and CC.GetContainerItemInfo) then return out end
    for bag = 0, (rawget(_G, "NUM_BAG_SLOTS") or 4) do
        for slot = 1, CC.GetContainerNumSlots(bag) or 0 do
            local info = CC.GetContainerItemInfo(bag, slot)
            if type(info) == "table" and info.itemID then out[info.itemID] = true end
        end
    end
    return out
end
M.BagItemIds = bagItemIds

local function finishFullScan(found)
    local now, n = GetServerTime(), 0
    for id, p in pairs(found) do
        n = n + 1
        db.prices[id] = { p = p, t = now, by = UnitName("player") }
        noteHistory(id, p, now)
        -- every price read goes to the org (in the background, behind chat)
        if not session[id] or p < session[id] then session[id] = p end
    end
    db.lastFullScan = now
    M.lastScan = { t = now, found = found }
    scanning = nil
    M.RepaintRecipeCosts()
    M:Print(("Full scan done: %d prices read; sharing them with the org in the background."):format(n))
    refreshPage()
    if M.StartQueue then M.StartQueue() end
end

local function readReplicate()
    local AH = C_AuctionHouse
    if not scanning or not (AH and AH.GetNumReplicateItems and AH.GetReplicateItemInfo) then return end
    scanning.total = AH.GetNumReplicateItems() or 0
    if scanning.reading then return end
    scanning.reading = true
    local found, i = {}, 0
    -- first pass: your bag items, recorded as soon as they're read, so their
    -- prices are the first to be up to date; then everything else
    local bags = scanning.bags or {}
    local mine = {}
    local function recordMine()
        local now = GetServerTime()
        scanning.before = scanning.before or {}
        for id, each in pairs(mine) do
            if scanning.before[id] == nil then scanning.before[id] = db.prices[id] or false end
            db.prices[id] = { p = each, t = now, by = UnitName("player") }
        end
    end
    local clock = rawget(_G, "debugprofilestop")
    local function step()
        if not scanning then return end
        local stop = math.min(i + SCAN_CHUNK, scanning.total)
        local t0 = clock and clock()
        if t0 then stop = scanning.total end
        while i < stop do
            if t0 and clock() - t0 > SCAN_BUDGET then break end
            -- index 0 based; count is the 3rd value, buyout the 10th, item id the 17th
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = AH.GetReplicateItemInfo(i)
            i = i + 1
            if id and buyout and buyout > 0 and count and count > 0 then
                local each = math.floor(buyout / count)
                if not found[id] or each < found[id] then found[id] = each end
                if bags[id] and (not mine[id] or each < mine[id]) then mine[id] = each end
            end
        end
        recordMine()
        scanning.read = i
        if i < scanning.total then C_Timer.After(0, step) else finishFullScan(found) end
    end
    step()
end

function M.FullScan(quiet)
    local AH = C_AuctionHouse
    if not (AH and AH.ReplicateItems) then
        if not quiet then M:Print("This client has no full auction house scan.") end
        return false
    end
    if scanning then return false end
    local wait = (db.lastFullScan or 0) + FULL_SCAN_GAP - GetServerTime()
    if wait > 0 then
        if not quiet then M:Print(("The game allows one full scan every 15 minutes; next in %d min."):format(math.ceil(wait / 60))) end
        return false
    end
    if not ahOpen then
        if not quiet then M:Print("Open the auction house first.") end
        return false
    end
    scanning = { started = GetServerTime(), bags = bagItemIds() }
    M:Print("Scanning the whole auction house...")
    AH.ReplicateItems()
    -- some clients only answer through the event; read it in a moment anyway
    C_Timer.After(5, function() if scanning and not scanning.reading then readReplicate() end end)
    return true
end

---------------------------------------------------------------------------
-- Scanning the whole time the auction house is open: after the full scan
-- (when the game allows one), one item at a time, in this order: the
-- reagents of crafts you know, then gear you can use, then everything else
-- RUIN has seen; then round again. Paced to the game's own query throttle
-- and no faster than one every QUERY_GAP seconds, only while you're on the
-- browse list, and never right after a search of your own, so your results
-- are never swapped for RUIN's.
---------------------------------------------------------------------------
local QUERY_GAP = 1.5          -- seconds between RUIN's searches, at the fastest
local USER_QUIET = 6           -- seconds to wait after a search of yours
local FRESH_SKIP = 15 * 60     -- an item you priced this recently waits for the next round
local SHARE_EVERY = 60         -- new prices go to the org this often while you scan
local queue = { list = {}, pos = 1, tier = 0, lastQuery = -999, lastUser = -999, ours = false, lastShare = 0 }
M.scanQueue = queue

-- the reagents in your recipes
local function craftReagents()
    local out = {}
    for _, book in pairs(db.recipeBook or {}) do
        for _, reagents in pairs(book) do
            if type(reagents) == "table" then
                for _, r in ipairs(reagents) do if type(r) == "table" and tonumber(r[1]) then out[tonumber(r[1])] = true end end
            end
        end
    end
    return out
end

-- gear you could wear: equippable, your level or under, and (with Codex)
-- of a kind your class uses
local function usableGear(id)
    local CI = rawget(_G, "C_Item")
    local equip = (CI and CI.IsEquippableItem and CI.IsEquippableItem(id)) or (rawget(_G, "IsEquippableItem") and IsEquippableItem(id))
    if not equip then return false end
    local _, _, _, _, minLevel = GetItemInfo(id)
    if (tonumber(minLevel) or 0) > ((UnitLevel and UnitLevel("player")) or 60) then return false end
    local cx = R.GetModule and R:GetModule("Codex")
    if cx and cx.CanUse then return cx.CanUse(id) ~= false end
    return true
end

-- the next round's list: the three tiers, in order, each without what came before
function M.BuildScanQueue()
    local now, me = GetServerTime(), UnitName("player")
    local seen, list, tiers = {}, {}, { 0, 0, 0 }
    local function fresh(id)
        local e = db.prices[id]
        return e and e.by == me and (now - (e.t or 0)) < FRESH_SKIP
    end
    local function add(id, tier)
        if seen[id] or fresh(id) then return end
        seen[id] = true
        list[#list + 1] = id
        tiers[tier] = tiers[tier] + 1
    end
    for id in pairs(craftReagents()) do add(id, 1) end
    local all = {}
    for id in pairs(db.prices) do all[#all + 1] = id end
    if M.lastScan and M.lastScan.found then for id in pairs(M.lastScan.found) do if not db.prices[id] then all[#all + 1] = id end end end
    table.sort(all)
    for _, id in ipairs(all) do if not seen[id] and usableGear(id) then add(id, 2) end end
    for _, id in ipairs(all) do add(id, 3) end
    queue.list, queue.pos, queue.tiers = list, 1, tiers
    return list, tiers
end

local function onBrowseList()
    local f = rawget(_G, "AuctionHouseFrame")
    if not (f and f.IsShown and f:IsShown()) then return false end
    local modes = rawget(_G, "AuctionHouseFrameDisplayMode")
    if f.GetDisplayMode and modes and modes.Buy then return f:GetDisplayMode() == modes.Buy end
    return true
end

-- one step: send the next search if the game, you and the clock all allow
function M.QueueStep()
    local AH = C_AuctionHouse
    if not (ahOpen and AH and AH.SendSearchQuery and AH.MakeItemKey) or scanning then return end
    local now = GetTime()
    if now - queue.lastQuery < QUERY_GAP or now - queue.lastUser < USER_QUIET then return end
    if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then return end
    if not onBrowseList() then return end
    if queue.pos > #queue.list then M.BuildScanQueue() end
    local id = queue.list[queue.pos]
    if not id then return end
    queue.pos = queue.pos + 1
    local ok, key = pcall(AH.MakeItemKey, id)
    if not ok or not key then return end
    queue.lastQuery = now
    queue.ours = true
    pcall(AH.SendSearchQuery, key, {}, false)
    queue.ours = false
    queue.sent = (queue.sent or 0) + 1
end

-- while the auction house is open: a step a little faster than the gap,
-- and what's new shared every minute
local ticker
function M.StartQueue()
    if ticker or not C_Timer then return end
    queue.lastShare = GetTime()
    local function tick()
        if not ahOpen then ticker = nil; return end
        M.QueueStep()
        if GetTime() - queue.lastShare >= SHARE_EVERY then
            queue.lastShare = GetTime()
            if M.ShareSession then M.ShareSession(true) end
        end
        C_Timer.After(0.5, tick)
    end
    ticker = true
    C_Timer.After(0.5, tick)
end

-- a search of yours pauses RUIN's for a few seconds
local hookedAH = {}
local function hookUserSearches()
    local AH = C_AuctionHouse
    if not (AH and hooksecurefunc) then return end
    for _, fn in ipairs({ "SendBrowseQuery", "SendSearchQuery", "SendSellSearchQuery", "RefreshCommoditySearchResults", "RefreshItemSearchResults", "SearchForItemKeys" }) do
        local f = AH[fn]
        if type(f) == "function" and hookedAH[fn] ~= f then
            hookedAH[fn] = f
            pcall(hooksecurefunc, AH, fn, function() if not queue.ours then queue.lastUser = GetTime() end end)
            hookedAH[fn] = AH[fn]
        end
    end
end

local function onAuctionShow()
    ahOpen = true
    hookUserSearches()
    queue.pos, queue.list = 1, {}
    if db.autoScan ~= false then
        C_Timer.After(1, function()
            -- the full scan when the game allows one; the item by item scan either way
            if not M.FullScan(true) then M.StartQueue() end
        end)
    end
end

local function shareSession(quiet)
    if not shares("prices") then session = {}; return end
    local flat, n = {}, 0
    local now = GetServerTime()
    for id, p in pairs(session) do
        flat[#flat + 1] = id
        flat[#flat + 1] = p
        n = n + 1
        if n >= PRICE_BATCH then
            M:Send("PRICES", { t = now, l = flat }, "ORG", nil, R.PRIORITY.BULK)
            flat, n = {}, 0
        end
    end
    if n > 0 then M:Send("PRICES", { t = now, l = flat }, "ORG", nil, R.PRIORITY.BULK) end
    local count = 0
    for _ in pairs(session) do count = count + 1 end
    if count > 0 and not quiet then M:Print(("Shared %d prices with RUIN."):format(count)) end
    session = {}
end
M.ShareSession = shareSession

function M:OnPrices(d, sender)
    if type(d.l) ~= "table" or type(d.t) ~= "number" then return end
    if R.SaneTime and not R:SaneTime(d.t) then return end         -- a future time would win forever
    local me = UnitName("player")
    for i = 1, math.min(#d.l, 400) - 1, 2 do
        local id, p = tonumber(d.l[i]), tonumber(d.l[i + 1])
        if id and p and p > 0 and p < 1e11 and id > 0 and id == math.floor(id) then
            local cur = db.prices[id]
            local age = cur and (d.t - (cur.t or 0)) or math.huge
            -- another player's share never beats what you saw yourself lately,
            -- and a price far off a recent one (a quarter of it, or four
            -- times it) is taken for a mistake or a prank and ignored
            local mine = cur and cur.by == me and age < FRESH_LOW
            local wild = cur and cur.p and cur.p > 0 and age < 86400 and (p < cur.p / 4 or p > cur.p * 4)
            if not wild then
                if (not cur or (cur.t or 0) < d.t) and not mine and not keepsLower(cur, p, d.t) then db.prices[id] = { p = p, t = d.t, by = sender } end
                noteHistory(id, p, d.t)
                if ns.Watch then ns.Watch.Seen(id, p, sender) end
            end
        end
    end
    if M.RepaintRecipeCosts then M.RepaintRecipeCosts() end
end

local function price(id) return db.prices[id] and db.prices[id].p end

---------------------------------------------------------------------------
-- Vendor prices: what a merchant sells an item for, seen when you open one
-- and shared with RUIN. A vendor price counts only when it's cheaper than
-- the auction house (or the auction house has none), and every place that
-- uses it says so.
---------------------------------------------------------------------------
local VENDOR_SHARE_MAX = 200
local vendorSeen = {}          -- this visit: id -> price, to share on close

-- the cheapest way to buy one: price, "vendor" or nil, and the vendor's name
local function buyPrice(id)
    local ah = price(id)
    local v = db.vendor and db.vendor[id]
    if v and v.p and (not ah or v.p < ah) then return v.p, "vendor", v.by, v.kind end
    return ah, nil, nil
end
M.BuyPrice = function(id) id = tonumber(id); if id then return buyPrice(id) end end

-- "12s" or "5c (vendor)" for lists and tooltips
local function buyText(id, count)
    local p, src = buyPrice(id)
    if not p then return nil end
    return W.Money(p * (count or 1)) .. (src == "vendor" and (" " .. C.good .. "(vendor)|r") or "")
end

local function noteVendor(id, p, by, t, kind, shared)
    if not (id and p and p > 0 and p < 1e11) then return false end
    local cur = db.vendor[id]
    -- another player's share never replaces a price you saw at a merchant
    -- yourself, nor one it undercuts by more than reputation could (30%)
    if shared and cur and cur.p and (cur.mine or p < cur.p * 0.7) then return false end
    if cur and cur.p and cur.p < p then return false end     -- keep the cheapest (reputation discounts vary)
    if cur and cur.p == p and (cur.kind or not kind) then return false end
    db.vendor[id] = { p = p, by = by, kind = kind, t = t or GetServerTime(), mine = (not shared) or nil }
    return true
end

-- The merchant's title, the line under its name ("Trade Goods"), or nil.
local function npcTitle()
    local TI = rawget(_G, "C_TooltipInfo")
    if not (TI and TI.GetUnit) then return nil end
    local ok, data = pcall(TI.GetUnit, "npc")
    local lines = ok and type(data) == "table" and data.lines
    local line = lines and lines[2] and lines[2].leftText
    if type(line) ~= "string" or line == "" then return nil end
    if line:find("^" .. (rawget(_G, "LEVEL") or "Level")) or line:find("^Level ") then return nil end
    return line:sub(1, 40)
end
M.NpcTitle = npcTitle

local function merchantItem(i)
    local CM = rawget(_G, "C_MerchantFrame")
    local id = GetMerchantItemID and GetMerchantItemID(i)
    if CM and CM.GetItemInfo then
        local info = CM.GetItemInfo(i)
        if type(info) == "table" then
            return id, info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
        end
    end
    if GetMerchantItemInfo then
        local _, _, cost, quantity, available, _, _, extended = GetMerchantItemInfo(i)
        return id, cost, quantity, available, extended
    end
end

function M.ScanMerchant()
    if not (GetMerchantNumItems and GetMerchantItemID) then return 0 end
    local who = UnitName and UnitName("npc") or "a vendor"
    local kind = npcTitle()
    db.lastVendorKind = kind
    local n = 0
    for i = 1, GetMerchantNumItems() or 0 do
        local id, cost, quantity, available, extended = merchantItem(i)
        -- gold only, and only stock that doesn't run out
        if id and cost and cost > 0 and not extended and (available == nil or available < 0) then
            local each = cost / math.max(quantity or 1, 1)
            if noteVendor(id, each, who, nil, kind) then vendorSeen[id] = each end
            n = n + 1
        end
    end
    if M.RepaintRecipeCosts then M.RepaintRecipeCosts() end
    return n
end

local function shareVendor()
    local flat, n = {}, 0
    local who = UnitName and UnitName("npc")
    for id, p in pairs(vendorSeen) do
        flat[#flat + 1] = id; flat[#flat + 1] = math.floor(p * 100 + 0.5) / 100
        n = n + 1
        if n >= VENDOR_SHARE_MAX then break end
    end
    vendorSeen = {}
    if n > 0 and shares("prices") then M:Send("VPRICES", { l = flat, w = db.lastVendor or who, k = db.lastVendorKind }, "ORG", nil, R.PRIORITY.BULK) end
end

function M:OnVendorPrices(d, sender)
    if type(d.l) ~= "table" then return end
    local who = type(d.w) == "string" and d.w:sub(1, 40) or ("a vendor (" .. tostring(sender) .. ")")
    local kind = type(d.k) == "string" and d.k ~= "" and d.k:gsub("|", ""):sub(1, 40) or nil
    for i = 1, math.min(#d.l, VENDOR_SHARE_MAX * 2) - 1, 2 do
        local id, p = tonumber(d.l[i]), tonumber(d.l[i + 1])
        if id and id > 0 and id == math.floor(id) then noteVendor(id, p, who, nil, kind, true) end
    end
    if M.RepaintRecipeCosts then M.RepaintRecipeCosts() end
end

-- Item names the game hasn't sent yet, asked for a few at a time so a full
-- scan's thousands of items don't flood the server. Pages redraw as they
-- arrive (ITEMS_LOADED).
local NAME_BATCH, NAME_GAP = 8, 0.5
local wantNames, wantQueue, warming = {}, {}, false
local function warmNames()
    local n = 0
    while n < NAME_BATCH and #wantQueue > 0 do
        local id = table.remove(wantQueue, 1)
        wantNames[id] = nil
        if not R.Items.Info(id) then n = n + 1 end    -- Info asks the game for it
    end
    if #wantQueue > 0 then C_Timer.After(NAME_GAP, warmNames) else warming = false end
end
local WANT_MAX = 300          -- names waiting at once; more just wait for the next search
function M.WantName(id)
    if not id or wantNames[id] or #wantQueue >= WANT_MAX then return end
    wantNames[id] = true
    wantQueue[#wantQueue + 1] = id
    if not warming and C_Timer then warming = true; C_Timer.After(NAME_GAP, warmNames) end
end

---------------------------------------------------------------------------
-- Crafter directory and profession leveling
---------------------------------------------------------------------------
local lastCraftSig = {}

-- Reagents for a recipe: { { id, qty }, ... } on modern and classic clients.
local function reagentsModern(recipeID)
    local out = {}
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return out end
    local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(sch) ~= "table" then return out end
    local complete = true
    for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
        local r = slot.reagents and slot.reagents[1]
        if slot.required ~= false then
            if r and r.itemID then out[#out + 1] = { r.itemID, slot.quantityRequired or 1 } else complete = false end
        end
    end
    return out, complete
end

local function reagentsClassic(index)
    local out = {}
    if not (GetTradeSkillNumReagents and GetTradeSkillReagentItemLink) then return out end
    -- a reagent the game hasn't loaded yet has no link: the list is then
    -- incomplete, and isn't kept (a recipe missing a reagent looks cheap)
    local complete = true
    for j = 1, GetTradeSkillNumReagents(index) or 0 do
        local link = GetTradeSkillReagentItemLink(index, j)
        local _, _, count = GetTradeSkillReagentInfo(index, j)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then out[#out + 1] = { id, count or 1 } else complete = false end
    end
    return out, complete
end

-- What one reagent costs to buy for crafting: the lowest listing last seen
-- on the auction house, or a merchant's when cheaper. Returns the price and where it's from: "vendor", "ah" (the lowest
-- listing seen lately) or "week" (the low end of the week).
local function reagentPrice(id)
    local expect, now = M.ExpectedPrice(id)
    local ah = expect or price(id)
    local v = db.vendor and db.vendor[id]
    if v and v.p and (not ah or v.p < ah) then return v.p, "vendor", v.by end
    if not ah then return nil end
    return ah, (now and ah == now) and "ah" or "week"
end
M.ReagentPrice = reagentPrice

-- Cost of one craft from RUIN prices; nil parts are reagents nobody has priced.
local function craftCost(reagents)
    local cost, missing = 0, {}
    for _, r in ipairs(reagents) do
        local p = reagentPrice(r[1])
        if p then cost = cost + p * r[2] else missing[#missing + 1] = r[1] end
    end
    return cost, missing
end

---------------------------------------------------------------------------
-- Skill-up chance. A recipe has four skill levels where its color changes:
-- orange from the skill you learn it at, then yellow, green, and grey. Orange
-- always gives a point and grey never does; between yellow and grey the
-- chance falls in a straight line from 100% to nothing:
--     chance = (grey - your skill) / (grey - yellow)
-- (the Classic rule the WoW Forever leveling calculators use). The game
-- only tells you a recipe's color, not where the colors change, so RUIN
-- learns those levels from what everyone in the org sees: the highest skill
-- anyone saw a recipe orange at, and the lowest they saw it yellow, green or
-- grey at. Until it knows yellow and grey for a recipe it assumes 3 in 4 for
-- yellow and 1 in 4 for green.
---------------------------------------------------------------------------
local RSKILL_SHARE_MAX = 40
local rskillChanged = {}       -- prof -> { name = true } since the last share

local function thresholds(prof, name)
    local p = prof and db.rskill[prof]
    return p and p[name]
end

-- remember the color a recipe showed at a skill level
local function noteColor(prof, name, diff, skill)
    skill = tonumber(skill)
    if not (prof and name and diff and skill and skill > 0 and skill < 1000) then return false end
    db.rskill[prof] = db.rskill[prof] or {}
    local t = db.rskill[prof][name] or {}
    local before = (t.o or -1) .. ":" .. (t.y or -1) .. ":" .. (t.g or -1) .. ":" .. (t.x or -1)
    if diff == 0 then t.o = math.max(t.o or 0, skill)
    elseif diff == 1 then t.y = math.min(t.y or 9999, skill)
    elseif diff == 2 then t.g = math.min(t.g or 9999, skill)
    elseif diff == 3 then t.x = math.min(t.x or 9999, skill) end
    -- a green or grey level also puts yellow below it
    if t.g and t.y and t.y > t.g then t.y = t.g end
    db.rskill[prof][name] = t
    local after = (t.o or -1) .. ":" .. (t.y or -1) .. ":" .. (t.g or -1) .. ":" .. (t.x or -1)
    if before ~= after then
        rskillChanged[prof] = rskillChanged[prof] or {}
        rskillChanged[prof][name] = true
        return true
    end
    return false
end
M.NoteColor = noteColor

-- Working Overtime (a Legacy talent, set in Exchange: RUIN can't read
-- Legacy talents): its +4% a rank is added on top of a yellow or green
-- recipe's chance.
local function overtime(c, diff)
    local rank = tonumber(db and db.overtime) or 0
    if rank <= 0 or not c or (diff ~= 1 and diff ~= 2) then return c end
    return math.min(1, c + OVERTIME_PER_RANK * math.min(rank, 5))
end
M.Overtime = overtime

-- Chance of a point: the recipe's own chance plus Working Overtime's bonus,
-- at most 100%. Returns that, whether the recipe's chance is worked out from
-- known color levels (not the 3-in-4 / 1-in-4 guess), and the recipe's own
-- chance before the bonus.
local function chanceFor(prof, name, diff, skill)
    if diff == 0 then return 1, true, 1 end
    if diff == 3 or diff == nil then return 0, true, 0 end
    local t = thresholds(prof, name)
    skill = tonumber(skill)
    local yellow = t and (t.y or (t.o and t.o + 1))
    local grey = t and t.x
    local base, exact = SKILLUP_CHANCE[diff], false
    if skill and yellow and grey and grey > yellow then
        local c = (grey - skill) / (grey - yellow)
        if c > 1 then c = 1 end
        if c > 0 then base, exact = c, true end
    end
    return overtime(base, diff), exact, base
end
M.ChanceFor = chanceFor

-- the color an unlearned recipe would show at your skill, from the levels
-- the org has seen; nil when RUIN doesn't know enough yet
local function predictDiff(prof, name, skill)
    local t = thresholds(prof, name)
    skill = tonumber(skill)
    if not (t and skill) then return nil end
    if t.x and skill >= t.x then return 3 end
    if t.g and skill >= t.g then return 2 end
    if t.y and skill >= t.y then return 1 end
    if t.o and skill <= t.o then return 0 end
    if t.y and skill < t.y and t.o and skill > t.o then return 0 end
    return nil
end
M.PredictDiff = predictDiff

function M.ShareRecipeSkill()
    for prof, names in pairs(rskillChanged) do
        local flat, n = {}, 0
        for name in pairs(names) do
            local t = thresholds(prof, name)
            if t then
                flat[#flat + 1] = name
                flat[#flat + 1] = t.o or 0; flat[#flat + 1] = t.y or 0; flat[#flat + 1] = t.g or 0; flat[#flat + 1] = t.x or 0
                n = n + 1
                if n >= RSKILL_SHARE_MAX then break end
            end
        end
        if n > 0 and shares("recipes") then M:Send("RSKILL", { p = prof, l = flat }, "ORG", nil, R.PRIORITY.BULK) end
    end
    rskillChanged = {}
end

function M:OnRecipeSkill(d)
    if type(d.p) ~= "string" or #d.p > 40 or type(d.l) ~= "table" then return end
    for i = 1, math.min(#d.l, RSKILL_SHARE_MAX * 5) - 4, 5 do
        local name = d.l[i]
        if type(name) == "string" and #name > 0 and #name <= 80 then
            local o, y, g, x = tonumber(d.l[i + 1]), tonumber(d.l[i + 2]), tonumber(d.l[i + 3]), tonumber(d.l[i + 4])
            if o and o > 0 then noteColor(d.p, name, 0, o) end
            if y and y > 0 then noteColor(d.p, name, 1, y) end
            if g and g > 0 then noteColor(d.p, name, 2, g) end
            if x and x > 0 then noteColor(d.p, name, 3, x) end
        end
    end
    rskillChanged[d.p] = nil      -- heard from someone else: no need to pass it on
    if M.RepaintRecipeCosts then M.RepaintRecipeCosts() end
end

-- Rank recipes that can still raise your skill by expected cost per point.
local function planLeveling(prof, skill, maxSkill, recipes)
    local list = {}
    for _, r in ipairs(recipes) do
        local chance, exact = chanceFor(prof, r.name, r.diff, skill)
        if chance and chance > 0 then
            local cost, missing = craftCost(r.reagents)
            list[#list + 1] = { name = r.name, diff = r.diff, cost = cost, missing = #missing, perPoint = cost / chance,
                                reagents = r.reagents, chance = chance, exact = exact, unlearned = r.unlearned }
        end
    end
    table.sort(list, function(a, b)
        if (a.missing == 0) ~= (b.missing == 0) then return a.missing == 0 end
        if a.perPoint ~= b.perPoint then return a.perPoint < b.perPoint end
        return a.diff < b.diff
    end)
    db.plans[prof] = { prof = prof, skill = skill, max = maxSkill, list = list, t = GetServerTime() }
end

-- A saved plan priced again from today's RUIN prices: the recipes and your
-- skill come from the last time the profession window was open, the costs
-- from whatever prices RUIN has now.
function M.LivePlan(plan)
    if not plan then return nil end
    local list = {}
    for _, r in ipairs(plan.list or {}) do
        local cost, missing = craftCost(r.reagents or {})
        local chance, exact = chanceFor(plan.prof, r.name, r.diff, plan.skill)
        if not chance or chance <= 0 then chance = overtime(SKILLUP_CHANCE[r.diff], r.diff) or 1 end
        list[#list + 1] = { name = r.name, diff = r.diff, cost = cost, missing = #missing, perPoint = cost / chance,
                            reagents = r.reagents, chance = chance, exact = exact, unlearned = r.unlearned }
        for _, rg in ipairs(r.reagents or {}) do if not R.Items.Info(rg[1]) then M.WantName(rg[1]) end end
    end
    table.sort(list, function(a, b)
        if (a.missing == 0) ~= (b.missing == 0) then return a.missing == 0 end
        if a.perPoint ~= b.perPoint then return a.perPoint < b.perPoint end
        return a.diff < b.diff
    end)
    return list
end

-- How many of its item one craft of a recipe makes (the middle of a range).
local function middle(lo, hi)
    lo, hi = tonumber(lo), tonumber(hi)
    if not (lo and lo > 0) then return 1 end
    if not (hi and hi >= lo) then hi = lo end
    return (lo + hi) / 2
end
local function madeCountClassic(i)
    if not GetTradeSkillNumMade then return 1 end
    local ok, lo, hi = pcall(GetTradeSkillNumMade, i)
    return ok and middle(lo, hi) or 1
end
local function madeCountModern(id)
    local S = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
    if not S then return 1 end
    local ok, sch = pcall(S, id, false)
    if ok and type(sch) == "table" then return middle(sch.quantityMin, sch.quantityMax) end
    return 1
end

-- The item a recipe makes: id and quality from its link (nil for enchants).
local function madeItem(link)
    if type(link) ~= "string" then return nil end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return nil end
    R.Items.RememberLinks(link)
    local _, _, q = R.Items.Info(id)
    return id, q
end

local function recipeLinkModern(recipeID)
    if C_TradeSkillUI.GetRecipeItemLink then
        local ok, link = pcall(C_TradeSkillUI.GetRecipeItemLink, recipeID)
        if ok and link then return link end
    end
    if C_TradeSkillUI.GetRecipeOutputItemData then
        local ok, out = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
        if ok and type(out) == "table" then return out.hyperlink end
    end
end

-- Set when RUIN's own Scan button opened the window: close it after the scan.
local closeAfterScan = 0
local craftWindow = false   -- the classic Craft window (Enchanting) is open

local function closeScannedWindow()
    if GetTime() - closeAfterScan > 20 then return end
    closeAfterScan = 0
    if C_TradeSkillUI and C_TradeSkillUI.CloseTradeSkill then pcall(C_TradeSkillUI.CloseTradeSkill)
    elseif CloseTradeSkill then pcall(CloseTradeSkill) end
    if CloseCraft then pcall(CloseCraft) end
end

-- What every recipe takes, learned or not, by profession and name, so a
-- trainer's list (which doesn't say) can be priced.
local function rememberReagents(prof, name, reagents, complete)
    if not (prof and name and reagents and #reagents > 0) or complete == false then return end
    db.recipeBook[prof] = db.recipeBook[prof] or {}
    local had = db.recipeBook[prof][name]
    -- a whole list replaces one that was missing reagents, never the other way
    if had and had.ok and #had > #reagents then return end
    local flat = { ok = complete and true or nil }
    for _, r in ipairs(reagents) do flat[#flat + 1] = { r[1], r[2] } end
    db.recipeBook[prof][name] = flat
    if M.ForgetRecipes then M.ForgetRecipes() end
end
local function rememberRecipe(prof, name, recipeID)
    local had = db.recipeBook[prof] and db.recipeBook[prof][name]
    if had and had.ok then return end
    rememberReagents(prof, name, reagentsModern(recipeID))
end
M.RememberReagents = rememberReagents

local function scanCrafts()
    local prof, list, recipes, skill, maxSkill = nil, {}, {}, nil, nil
    local made = {}            -- recipe name -> { id, quality }
    if craftWindow and GetNumCrafts and GetCraftInfo then
        -- classic clients show Enchanting in a separate Craft window
        local rank, maxRank
        prof, rank, maxRank = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()
        skill, maxSkill = rank, maxRank
        for i = 1, GetNumCrafts() or 0 do
            local name, _, kind = GetCraftInfo(i)
            if name and kind ~= "header" then
                list[#list + 1] = name
                if CLASSIC_DIFFICULTY[kind] then noteColor(prof, name, CLASSIC_DIFFICULTY[kind], skill) end
                local iid, q = madeItem(GetCraftItemLink and GetCraftItemLink(i))
                if iid then made[name] = { iid, q, 1 } end
            end
        end
    elseif C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
        prof = info and info.professionName
        skill, maxSkill = info and info.skillLevel, info and info.maxSkillLevel
        for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
            local r = C_TradeSkillUI.GetRecipeInfo(id)
            if r and r.name then rememberRecipe(prof, r.name, id) end
            if r and r.learned and r.name then
                list[#list + 1] = r.name
                local iid, q = madeItem(recipeLinkModern(id))
                if iid then made[r.name] = { iid, q, madeCountModern(id) } end
                if r.relativeDifficulty then noteColor(prof, r.name, r.relativeDifficulty, skill) end
                if r.relativeDifficulty and r.relativeDifficulty < 3 then
                    recipes[#recipes + 1] = { name = r.name, diff = r.relativeDifficulty, reagents = reagentsModern(id) }
                end
            elseif r and r.name and not r.learned then
                -- not learned yet: worth training if it would give points at your skill
                local diff = predictDiff(prof, r.name, skill)
                if diff and diff < 3 then
                    recipes[#recipes + 1] = { name = r.name, diff = diff, reagents = reagentsModern(id), unlearned = true }
                end
            end
        end
    elseif GetNumTradeSkills and GetTradeSkillInfo then
        local rank, maxRank
        prof, rank, maxRank = GetTradeSkillLine and GetTradeSkillLine()
        skill, maxSkill = rank, maxRank
        for i = 1, GetNumTradeSkills() or 0 do
            local name, kind = GetTradeSkillInfo(i)
            if name and kind ~= "header" then
                list[#list + 1] = name
                local iid, q = madeItem(GetTradeSkillItemLink and GetTradeSkillItemLink(i))
                if iid then made[name] = { iid, q, madeCountClassic(i) } end
                local diff = CLASSIC_DIFFICULTY[kind]
                if diff then noteColor(prof, name, diff, skill) end
                rememberReagents(prof, name, reagentsClassic(i))     -- (the list, and whether it's whole)
                if diff and diff < 3 then recipes[#recipes + 1] = { name = name, diff = diff, reagents = reagentsClassic(i) } end
            end
        end
    end
    if not prof or prof == "" or #list == 0 then return end
    closeScannedWindow()
    if #recipes > 0 then planLeveling(prof, skill, maxSkill, recipes) end
    M.ShareRecipeSkill()
    table.sort(list)
    local me = R:GetPlayer()
    -- the made item's id and quality travel beside the names (i, q), so
    -- older RUIN versions still read the list of names
    local ids, qs, ns = {}, {}, {}
    for n, name in ipairs(list) do
        local m = made[name]
        ids[n], qs[n], ns[n] = m and m[1] or 0, m and m[2] or -1, m and m[3] or 1
    end
    local e = db.crafters[me.guid] or { name = me.name, guild = me.guild, profs = {} }
    e.profs[prof] = list
    e.made = e.made or {}
    e.made[prof] = { i = ids, q = qs, n = ns }
    e.skill = e.skill or {}
    e.skill[prof] = tonumber(skill)
    e.t = GetServerTime()
    db.crafters[me.guid] = e
    if M.ForgetRecipes then M.ForgetRecipes() end
    refreshPage()
    if M.RefreshScanPrompt then M.RefreshScanPrompt() end
    local sig = #list .. ":" .. table.concat(list, "|"):len()
    if lastCraftSig[prof] == sig then return end
    lastCraftSig[prof] = sig
    if shares("recipes") then M:Send("CRAFTS", { g = me.guid, gu = me.guild, p = prof, l = list, i = ids, q = qs, s = tonumber(skill) }, "ORG", nil, R.PRIORITY.BULK) end
    M:Print(("Shared %d %s recipes with RUIN."):format(#list, prof))
end

local craftScanPending = false
local function scheduleCraftScan()
    if craftScanPending then return end
    craftScanPending = true
    C_Timer.After(3, function()
        craftScanPending = false
        scanCrafts()
    end)
end

---------------------------------------------------------------------------
-- Price per Point beside each recipe in the profession window, from current
-- RUIN prices: one craft's reagents divided by the chance it gives a skill
-- point (see the skill-up chance notes above), for every recipe listed,
-- learned or not.
---------------------------------------------------------------------------
local function reagentsCraft(index)
    local out = {}
    if not (GetCraftNumReagents and GetCraftReagentItemLink) then return out end
    for j = 1, GetCraftNumReagents(index) or 0 do
        local link = GetCraftReagentItemLink(index, j)
        local _, _, count = GetCraftReagentInfo(index, j)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then out[#out + 1] = { id, count or 1 } end
    end
    return out
end

-- short money for tight spots: "36c", "18s", "1g 20s" (copper dropped once
-- there's silver, silver dropped from 10 gold up)
function M.ShortMoney(copper)
    copper = math.floor((copper or 0) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local COIN = W.COIN
    if g >= 10 then return g .. COIN.g end
    if g > 0 then return s > 0 and (g .. COIN.g .. " " .. s .. COIN.s) or (g .. COIN.g) end
    if s > 0 then return s .. COIN.s end
    return c .. COIN.c
end

-- One craft's reagents at the cheapest RUIN price: "1s 20c/craft", "?/craft"
function M.CraftText(reagents)
    if not reagents or #reagents == 0 then return nil end
    local cost, missing = craftCost(reagents)
    if #missing > 0 then return C.dim .. "?/craft|r" end
    return C.gold .. M.ShortMoney(cost) .. "|r" .. C.dim .. "/craft|r"
end

-- Price per Point: one craft divided by the chance of a skill point.
-- "1s 20c/pt" when the chance is worked out from the recipe's color levels,
-- "~1s 20c/pt" when it's the 3-in-4 / 1-in-4 guess, "?/pt" when a reagent
-- has no price, nothing for grey (no points), and "18s/craft" when RUIN can't tell
-- what color an unlearned recipe would be.
function M.PointText(diff, reagents, prof, name, skill)
    if not reagents or #reagents == 0 then return nil end
    if diff == nil then return M.CraftText(reagents) end
    if diff == 3 then return nil end                 -- grey: no points, nothing to show
    local chance, exact = chanceFor(prof, name, diff, skill)
    if not chance or chance <= 0 then return nil end
    local cost, missing = craftCost(reagents)
    if #missing > 0 then return C.dim .. "?/pt|r" end
    return C.gold .. (exact and "" or "~") .. M.ShortMoney(cost / chance) .. "|r" .. C.dim .. "/pt|r"
end

-- How a recipe's Price per Point is worked out, as tooltip rows: each
-- reagent and its price, the cost of one craft, the chance of a point (with
-- Working Overtime) and the cost divided by it. { { left, right }, ... }
function M.PointBreakdown(diff, reagents, prof, name, skill)
    if not reagents or #reagents == 0 then return nil end
    local rows = {}
    local now = GetServerTime()
    local total, missing = 0, false
    for _, r in ipairs(reagents) do
        local id, n = r[1], r[2] or 1
        local iname = (GetItemInfo and GetItemInfo(id)) or ("item " .. id)
        if not (GetItemInfo and GetItemInfo(id)) then M.WantName(id) end
        local p, src, by = reagentPrice(id)
        local left = ("%s%d x %s|r"):format(C.white, n, iname)
        if p then
            total = total + p * n
            local where
            if src == "vendor" then where = "merchant" .. (by and (" (" .. tostring(by) .. ")") or "")
            elseif src == "ah" then
                local t = db.prices[id] and db.prices[id].t
                local age = t and math.max(0, now - t)
                local ago = not age and "" or (age < 3600 and (math.floor(age / 60) .. " min ago"))
                    or (age < 86400 and (math.floor(age / 3600) .. " h ago")) or (math.floor(age / 86400) .. " days ago")
                where = "AH lowest" .. (ago ~= "" and (", " .. ago) or "")
            else where = "AH, low end of the week" end
            rows[#rows + 1] = { left, W.Money(p * n) .. " " .. C.dim .. "(" .. where .. ")|r" }
        else
            missing = true
            rows[#rows + 1] = { left, C.dim .. "no price yet|r" }
        end
    end
    rows[#rows + 1] = { C.gold .. "Cost of one craft|r", missing and (C.dim .. "unknown|r") or W.Money(total) }
    if diff == nil or diff == 3 then return rows end
    local chance, exact, base = chanceFor(prof, name, diff, skill)
    if not chance or chance <= 0 then return rows end
    local bonus = chance - (base or chance)
    local pct = function(x) return math.floor(x * 100 + 0.5) .. "%" end
    local how = exact and "from its color levels" or "the usual guess for its color"
    if bonus > 0.0001 then
        rows[#rows + 1] = { C.gold .. "Chance of a point|r", ("%s + %s Working Overtime = %s"):format(pct(base), pct(bonus), pct(chance)) }
    else
        rows[#rows + 1] = { C.gold .. "Chance of a point|r", pct(chance) }
    end
    rows[#rows + 1] = { C.dim .. "(" .. how .. ")|r", "" }
    if not missing then
        rows[#rows + 1] = { C.gold .. "Price per Point|r", ("%s / %s = %s"):format(W.Money(total), pct(chance), W.Money(math.floor(total / chance + 0.5))) }
    end
    return rows
end

-- the open profession and your skill in it
function M.CurrentProfession(craft)
    if craft and GetCraftDisplaySkillLine then
        local prof, rank = GetCraftDisplaySkillLine()
        return prof, rank
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local info = C_TradeSkillUI.GetBaseProfessionInfo()
        if info and info.professionName then return info.professionName, info.skillLevel end
    end
    if GetTradeSkillLine then
        local prof, rank = GetTradeSkillLine()
        return prof, rank
    end
end

local function pointFor(diff, reagents, name, craft)
    local prof, skill = M.CurrentProfession(craft)
    return M.PointText(diff, reagents, prof, name, skill), { diff, reagents, prof, name, skill }
end

local function costLabel(row)
    if not row.ruinCost then
        row.ruinCost = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.ruinCost:SetJustifyH("RIGHT")
    end
    return row.ruinCost
end

-- the recipe's name: Blizzard's Label (modern rows) or the button's text
local function nameText(row)
    local fs = rawget(row, "Label")
    if type(fs) ~= "table" and row.GetFontString then fs = row:GetFontString() end
    if type(fs) ~= "table" and row.GetName and row:GetName() then fs = _G[row:GetName() .. "Text"] end
    return type(fs) == "table" and fs or nil
end

-- Hovering a cost shows how it's worked out (M.PointBreakdown). The hover
-- area passes clicks through to the recipe row.
local function costHover(row, fs)
    local hit = row.ruinCostHit
    if hit or not CreateFrame then return hit end
    hit = CreateFrame("Frame", nil, row)
    hit:SetAllPoints(fs)
    hit:EnableMouse(true)
    if hit.SetPropagateMouseClicks then hit:SetPropagateMouseClicks(true) end
    if hit.SetPropagateMouseMotion then hit:SetPropagateMouseMotion(true) end
    hit:SetScript("OnEnter", function(self)
        local info = row.ruinCostInfo
        local rows = info and M.PointBreakdown(info[1], info[2], info[3], info[4], info[5])
        if not (rows and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tostring(info[4] or "Recipe"), 1, 0.82, 0)
        for _, r in ipairs(rows) do GameTooltip:AddDoubleLine(r[1], r[2], 1, 1, 1, 1, 1, 1) end
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.ruinCostHit = hit
    return hit
end

local function paintCost(row, text, right, info)
    local fs = costLabel(row)
    local shown = text ~= nil and db.pointCosts ~= false
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", row, "RIGHT", right or -4, 0)
    fs:SetText(shown and text or "")
    if shown then fs:Show() else fs:Hide() end
    row.ruinCostInfo = shown and info or nil
    local hit = costHover(row, fs)
    if hit then if shown and info then hit:Show() else hit:Hide() end end
    -- the name (and the "[2]" craftable count after it) end before the cost,
    -- so a long name is cut short ("Enchant Chest - Minor Abso...") instead
    -- of running under it
    local name = nameText(row)
    if not (shown and name and name.SetWidth and name.GetStringWidth) then return end
    local count = rawget(row, "Count")
    local countW = (type(count) == "table" and count.IsShown and count:IsShown() and count.GetStringWidth and (count:GetStringWidth() or 0) + 6) or 0
    local avail
    local fl, nl = fs.GetLeft and fs:GetLeft(), name.GetLeft and name:GetLeft()
    if fl and nl then
        avail = fl - nl - countW - 8
    else
        local _, _, _, x = name:GetPoint(1)
        avail = (row:GetWidth() or 0) - (tonumber(x) or 0) - (fs:GetStringWidth() or 0) - math.abs(right or 4) - countW - 8
    end
    local want = (name.GetUnboundedStringWidth and name:GetUnboundedStringWidth()) or name:GetStringWidth() or 0
    if avail and avail > 20 then
        if name.SetWordWrap then name:SetWordWrap(false) end
        name:SetWidth(math.min(want + 2, avail))
    end
end

-- modern window: rows of ProfessionsFrame's recipe list
local function paintModernRow(frame)
    local ed = frame and frame.GetElementData and frame:GetElementData()
    local data = ed and ed.GetData and ed:GetData()
    local info = data and data.recipeInfo
    if not (info and info.recipeID) then
        if frame and frame.ruinCost then frame.ruinCost:Hide() end
        return
    end
    local prof, skill = M.CurrentProfession()
    local diff = info.relativeDifficulty
    if not info.learned and diff == nil then diff = predictDiff(prof, info.name, skill) end
    local reagents = reagentsModern(info.recipeID)
    local text = M.PointText(diff, reagents, prof, info.name, skill)
    paintCost(frame, text or nil, -28, { diff, reagents, prof, info.name, skill })     -- clear of the skill-up number on the right
end

local function paintModern()
    local list = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
    local box = list and list.ScrollBox
    if box and box.ForEachFrame then box:ForEachFrame(paintModernRow) end
end

-- classic windows: TradeSkillSkill1..n and Craft1..n, each button's ID is its recipe index
local function paintClassic()
    if TradeSkillFrame and TradeSkillFrame:IsShown() and GetTradeSkillInfo then
        for i = 1, TRADE_SKILLS_DISPLAYED or 8 do
            local b = _G["TradeSkillSkill" .. i]
            if b then
                local index = b:GetID()
                local name, kind = GetTradeSkillInfo(index)
                local text, info
                if name and kind ~= "header" then text, info = pointFor(CLASSIC_DIFFICULTY[kind], reagentsClassic(index), name, false) end
                paintCost(b, b:IsShown() and text or nil, -4, info)
            end
        end
    end
    if CraftFrame and CraftFrame:IsShown() and GetCraftInfo then
        for i = 1, CRAFTS_DISPLAYED or 8 do
            local b = _G["Craft" .. i]
            if b then
                local index = b:GetID()
                local name, _, kind = GetCraftInfo(index)
                local text, info
                if name and kind ~= "header" then text, info = pointFor(CLASSIC_DIFFICULTY[kind], reagentsCraft(index), name, true) end
                paintCost(b, b:IsShown() and text or nil, -4, info)
            end
        end
    end
end

local hooked = {}
function M.HookRecipeCosts()
    local list = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
    local box = list and list.ScrollBox
    if box and not hooked.modern then
        hooked.modern = true
        if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
            ScrollUtil.AddInitializedFrameCallback(box, function(_, frame) paintModernRow(frame) end, M, true)
        elseif box.RegisterCallback and box.Event and box.Event.OnDataRangeChanged then
            box:RegisterCallback(box.Event.OnDataRangeChanged, paintModern, M)
        end
    end
    if TradeSkillFrame_Update and not hooked.trade then
        hooked.trade = true
        hooksecurefunc("TradeSkillFrame_Update", paintClassic)
    end
    if CraftFrame_Update and not hooked.craft then
        hooked.craft = true
        hooksecurefunc("CraftFrame_Update", paintClassic)
    end
    paintModern()
    paintClassic()
end

---------------------------------------------------------------------------
-- Price per Point at a profession trainer. A trainer's recipe needs a
-- skill to learn ("Requires: Cooking (80)"), and that's where it starts
-- orange. Its reagents come from your profession window (RUIN remembers
-- every recipe it lists there, learned or not). If RUIN knows where the
-- recipe turns yellow and grey it shows the Price per Point at your skill,
-- otherwise the Price per Craft; nothing for a recipe that would be grey.
---------------------------------------------------------------------------
local function profSkill(prof)
    if not prof then return nil end
    if GetProfessions and GetProfessionInfo then
        for _, idx in ipairs({ GetProfessions() }) do
            if idx then
                local name, _, rank = GetProfessionInfo(idx)
                if name == prof then return rank end
            end
        end
    end
    local me = R:GetPlayer()
    local e = me and db.crafters[me.guid]
    return e and e.skill and e.skill[prof]
end

-- name -> { profession, required skill } for the open trainer
local function trainerServices()
    local out = {}
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return out end
    for i = 1, GetNumTrainerServices() or 0 do
        local name, _, category = GetTrainerServiceInfo(i)
        if name and category ~= "header" then
            local prof, req = nil, nil
            if GetTrainerServiceSkillReq then prof, req = GetTrainerServiceSkillReq(i) end
            out[name] = { prof = prof, req = tonumber(req), index = i }
        end
    end
    return out
end

-- a trainer's tooltip lists reagents by name: "Reagents: Boar Ribs, Mild Spices (2)"
local function trainerReagents(index)
    local CT = rawget(_G, "C_TooltipInfo")
    if not (index and CT and CT.GetTrainerService) then return nil end
    local ok, data = pcall(CT.GetTrainerService, index)
    if not (ok and type(data) == "table" and data.lines) then return nil end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        local list = type(text) == "string" and text:match("^[^:]-[Rr]eagents?:%s*(.+)$")
        if list then
            list = list:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local out = {}
            for part in list:gmatch("[^,]+") do
                part = part:gsub("^%s+", ""):gsub("%s+$", "")
                local item, count = part:match("^(.-)%s*%((%d+)%)$")
                item = item or part
                local id = R.Items.IdByName and R.Items.IdByName(item)
                if not id then return nil end            -- one we can't place: don't guess
                out[#out + 1] = { id, tonumber(count) or 1 }
            end
            return #out > 0 and out or nil
        end
    end
end

function M.TrainerText(name, services)
    local sv = services and services[name]
    if not (sv and sv.prof) then return nil end
    local reagents = db.recipeBook[sv.prof] and db.recipeBook[sv.prof][name]
    if not reagents then
        reagents = trainerReagents(sv.index)
        if reagents then rememberReagents(sv.prof, name, reagents, true) end
    end
    if not reagents then return nil end
    local skill = profSkill(sv.prof)
    if sv.req and sv.req > 0 then noteColor(sv.prof, name, 0, sv.req) end   -- it's orange from the skill it needs
    if not skill or (sv.req and skill < sv.req) then return M.CraftText(reagents) end
    local diff = predictDiff(sv.prof, name, skill)
    if diff == 3 then return nil end
    return M.PointText(diff, reagents, sv.prof, name, skill)
end

local function trainerRowName(row)
    local fs = rawget(row, "name") or rawget(row, "Name")
    if type(fs) == "table" and fs.GetText then return fs:GetText() end
    if row.GetText then return row:GetText() end
end

local function paintTrainer()
    if not (ClassTrainerFrame and ClassTrainerFrame:IsShown()) then return end
    local services = trainerServices()
    local function paint(row)
        local name = trainerRowName(row)
        local text = name and M.TrainerText(name, services)
        local fs = costLabel(row)
        fs:ClearAllPoints()
        fs:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 6)
        fs:SetText(text or "")
        if text and db.pointCosts ~= false then fs:Show() else fs:Hide() end
    end
    local box = ClassTrainerFrame.ScrollBox
    if box and box.ForEachFrame then box:ForEachFrame(paint) end
    for i = 1, CLASS_TRAINER_SKILLS_DISPLAYED or 0 do
        local b = _G["ClassTrainerSkill" .. i]
        if b and b:IsShown() then paint(b) end
    end
end
M.PaintTrainer = paintTrainer

function M.HookTrainer()
    local box = ClassTrainerFrame and ClassTrainerFrame.ScrollBox
    if box and not hooked.trainer then
        hooked.trainer = true
        if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
            ScrollUtil.AddInitializedFrameCallback(box, function() C_Timer.After(0, paintTrainer) end, M, true)
        end
    end
    if ClassTrainerFrame_Update and not hooked.trainerClassic then
        hooked.trainerClassic = true
        hooksecurefunc("ClassTrainerFrame_Update", paintTrainer)
    end
    paintTrainer()
end

-- prices that change while the window is open repaint the costs
function M.RepaintRecipeCosts()
    paintModern()
    paintClassic()
    paintTrainer()
end

---------------------------------------------------------------------------
-- Your professions at login. The game lists a profession's recipes only
-- while its window is open, so at login Exchange checks which professions
-- you have (and their skill), shares the recipes it already knows, and asks
-- you to open any profession that is new or has gone up since its last scan
-- (one click each in the "Add your recipes" window).
---------------------------------------------------------------------------
local NO_WINDOW = { Herbalism = true, Skinning = true, Fishing = true, Archaeology = true }
local OPEN_SPELL = { Mining = "Smelting" }   -- the spell that opens a profession's window

-- { { name, skill, max } } for your crafting professions, or nil if the client can't tell.
function M.Professions()
    local out = {}
    if GetProfessions and GetProfessionInfo then
        local list = { GetProfessions() }
        for i = 1, 6 do
            local idx = list[i]
            if idx then
                local name, _, rank, maxRank = GetProfessionInfo(idx)
                if name and not NO_WINDOW[name] then out[#out + 1] = { name = name, skill = rank, max = maxRank } end
            end
        end
        return out
    end
    if GetNumSkillLines and GetSkillLineInfo then
        local section
        local profHeaders = { [TRADE_SKILLS or "Professions"] = true, ["Professions"] = true,
                              [(SECONDARY_SKILLS or "Secondary Skills"):gsub(":$", "")] = true, ["Secondary Skills"] = true }
        for i = 1, GetNumSkillLines() or 0 do
            local name, header, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if header then section = name
            elseif name and section and profHeaders[section] and not NO_WINDOW[name] then
                out[#out + 1] = { name = name, skill = rank, max = maxRank }
            end
        end
        return out
    end
    return nil
end

-- Professions whose recipes Exchange should (re)read: never scanned, or skill went up.
function M.NeedsScan()
    local profs = M.Professions()
    if not profs then return {} end
    local me = db and db.crafters[R:GetPlayerGUID() or ""]
    local out = {}
    for _, p in ipairs(profs) do
        local known = me and me.profs and me.profs[p.name]
        local was = me and me.skill and me.skill[p.name]
        if not known or #known == 0 or (tonumber(p.skill) and tonumber(was) and p.skill > was) then out[#out + 1] = p end
    end
    return out
end

-- Share the recipes you already have on record (each profession once per session,
-- and again when someone asks). Professions you no longer have are dropped.
local sharedAt = -999
function M.ShareMine(force)
    if not R:IsConnected() then return end
    if not force and GetTime() - sharedAt < 600 then return end
    if GetTime() - sharedAt < 60 then return end
    local me = R:GetPlayer()
    local e = db.crafters[me.guid]
    if not e or not e.profs then return end
    local profs = M.Professions()
    if profs then
        local have = {}
        for _, p in ipairs(profs) do have[p.name] = true end
        for prof in pairs(e.profs) do
            -- the craft window's name can differ (Mining's window is Smelting); keep those
            local alias = (prof == "Smelting" and have.Mining) or (prof == "Mining" and have.Mining)
            if not have[prof] and not alias and next(have) then
                e.profs[prof] = nil
                if e.made then e.made[prof] = nil end
                M:Send("CRAFTS", { g = me.guid, gu = me.guild, p = prof, l = {} }, "ORG", nil, R.PRIORITY.BULK)
            end
        end
    end
    sharedAt = GetTime()
    -- your skill now (it may have gone up since the recipes were read)
    e.skill = e.skill or {}
    for _, p in ipairs(profs or {}) do
        if tonumber(p.skill) then e.skill[p.name] = tonumber(p.skill) end
    end
    if e.skill.Mining and e.profs.Smelting then e.skill.Smelting = e.skill.Mining end
    for prof, list in pairs(e.profs) do
        local m = e.made and e.made[prof]
        -- recipes not shared: tell everyone to forget yours
        if shares("recipes") then M:Send("CRAFTS", { g = me.guid, gu = me.guild, p = prof, l = list, i = m and m.i, q = m and m.q, n = m and m.n, s = e.skill[prof] }, "ORG", nil, R.PRIORITY.BULK)
        else M:Send("CRAFTS", { g = me.guid, gu = me.guild, p = prof, l = {} }, "ORG", nil, R.PRIORITY.BULK) end
    end
end

-- The small "Add your recipes" window: one button per profession that opens
-- it (a click from you, as the game requires), Exchange reads it and closes it.
local prompt
local function buildPrompt()
    prompt = CreateFrame("Frame", "RUIN_ExchangeScan", UIParent)
    prompt:SetSize(360, 112)
    prompt:SetPoint("TOP", UIParent, "TOP", 0, -140)
    prompt:SetFrameStrata("DIALOG")
    prompt:SetClampedToScreen(true)
    if W.Themed then W.Themed(prompt, "Exchange") end
    W.Skin(prompt, "panel", 0.97, "glow")
    prompt:EnableMouse(true)
    prompt:SetMovable(true)
    prompt:RegisterForDrag("LeftButton")
    prompt:SetScript("OnDragStart", prompt.StartMoving)
    prompt:SetScript("OnDragStop", prompt.StopMovingOrSizing)
    local t = W.Label(prompt, C.gold .. "RUIN Exchange|r  Add your recipes", "GameFontNormal")
    t:SetPoint("TOPLEFT", 12, -10)
    prompt.text = W.Label(prompt, "", "GameFontHighlightSmall")
    prompt.text:SetPoint("TOPLEFT", 12, -30)
    prompt.text:SetPoint("RIGHT", prompt, "RIGHT", -12, 0)
    prompt.text:SetJustifyH("LEFT")
    prompt.later = W.Button(prompt, "Later", 64, function() if not InCombatLockdown() then prompt:Hide() end end)
    prompt.later:SetPoint("BOTTOMRIGHT", -10, 10)
    prompt.buttons = {}
    for i = 1, 4 do
        -- the game only lets a click of yours open a profession, so these
        -- are the game's own secure spell buttons
        local b = CreateFrame("Button", "RUIN_ExchangeScan" .. i, prompt, "SecureActionButtonTemplate")
        b:SetSize(64, 22)
        W.Skin(b, "panel", 1, "border")
        b.label = W.Label(b, "", "GameFontHighlightSmall")
        b.label:SetPoint("CENTER", 0, 0)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "spell")
        b:SetScript("PreClick", function() closeAfterScan = GetTime() end)
        b:Hide()
        prompt.buttons[i] = b
    end
    prompt:SetScript("OnHide", function() prompt.dismissed = true end)
    prompt:RegisterEvent("PLAYER_REGEN_ENABLED")
    prompt:SetScript("OnEvent", function() if prompt.pending then M.RefreshScanPrompt(prompt.pending == "show") end end)
    prompt:Hide()
end

-- show: true to open the window (it stays closed after "Later" until asked)
function M.RefreshScanPrompt(show)
    if not db then return end
    local need = M.NeedsScan()
    if not prompt then
        if #need == 0 or not show then return end
        buildPrompt()
    end
    if InCombatLockdown() then prompt.pending = show and "show" or "refresh"; return end
    prompt.pending = nil
    if #need == 0 then prompt:Hide(); return end
    if not show and not prompt:IsShown() then return end
    local names = {}
    local x = 12
    for i, b in ipairs(prompt.buttons) do
        local p = need[i]
        if p then
            names[#names + 1] = p.name
            b:SetAttribute("spell", OPEN_SPELL[p.name] or p.name)
            b.label:SetText(p.name)
            b:SetWidth(math.max(64, (b.label:GetStringWidth() or 50) + 18))
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", prompt, "BOTTOMLEFT", x, 10)
            x = x + b:GetWidth() + 6
            b:Show()
        else
            b:Hide()
        end
    end
    prompt.text:SetText(("The game shows recipes only while a profession's window is open. Click each one to let RUIN list what you can make (%s). The window opens and closes by itself.")
        :format(table.concat(names, ", ")))
    prompt.dismissed = false
    prompt:Show()
end

function M:OnCrafts(d, sender)
    if type(d.g) ~= "string" or type(d.p) ~= "string" or type(d.l) ~= "table" then return end
    -- a crafter's entry is theirs alone: same GUID, same name
    if R.GUIDMatches and not R:GUIDMatches(sender, d.g) then return end
    local had = db.crafters[d.g]
    if had and type(had.name) == "string" and R.SameName and not R:SameName(had.name, sender) then return end
    local e = db.crafters[d.g] or { profs = {} }
    e.name, e.guild, e.t = sender, d.gu, GetServerTime()
    e.profs[d.p] = d.l
    -- their skill in it (older RUIN versions don't send one)
    local skill = tonumber(d.s)
    e.skill = e.skill or {}
    if #d.l == 0 then e.skill[d.p] = nil
    elseif skill and skill >= 0 and skill <= 1000 then e.skill[d.p] = math.floor(skill) end
    if type(d.i) == "table" then
        local ids, qs, ns = {}, {}, {}
        for n = 1, #d.l do
            ids[n] = tonumber(d.i[n]) or 0
            qs[n] = type(d.q) == "table" and tonumber(d.q[n]) or -1
            local c = type(d.n) == "table" and tonumber(d.n[n]) or 1
            ns[n] = (c >= 1 and c <= 100) and c or 1
        end
        e.made = e.made or {}
        e.made[d.p] = { i = ids, q = qs, n = ns }
    end
    db.crafters[d.g] = e
end

local function canICraft(itemName)
    local me = db.crafters[R:GetPlayerGUID() or ""]
    if not me or not itemName then return false end
    local q = itemName:lower()
    for prof, list in pairs(me.profs or {}) do
        for _, recipe in ipairs(list) do
            if recipe:lower() == q then return prof end
        end
    end
    return false
end

local function craftersOf(itemName)
    local out = {}
    if not itemName then return out end
    local q = itemName:lower()
    for _, e in pairs(db.crafters) do
        for _, list in pairs(e.profs or {}) do
            for _, recipe in ipairs(list) do
                if recipe:lower() == q then out[#out + 1] = e.name; break end
            end
        end
    end
    return out
end

-- For other parts of RUIN (the Planner page): who in RUIN can craft an item,
-- and the auction price RUIN knows for one (copper per item), or nil.
function M.CraftersOf(itemName) return craftersOf(itemName) end
function M.PriceOf(id) id = tonumber(id); return id and db and db.prices[id] and db.prices[id].p or nil end

---------------------------------------------------------------------------
-- Craft requests
---------------------------------------------------------------------------
local function requestName(r) return r.name or (r.item and r.item:match("%[(.-)%]")) or r.item end

function M:Request(item, note)
    item = R.Util.Trim(item or "")
    if item == "" then return self:Print("Name the item, or shift-click it into the box.") end
    local p = R:GetPlayer()
    local now = GetServerTime()
    local r = { id = tostring(p.guid or "x"):sub(-5) .. now % 100000 .. math.random(10, 99), item = item:sub(1, 120),
                note = R.Util.Trim(note or ""):sub(1, 60), by = p.name, gu = p.guild, t = now, exp = now + REQUEST_HOURS * 3600 }
    r.name = requestName(r)
    db.requests[r.id] = r
    self:Send("REQ", r, "ORG")
    local who = craftersOf(r.name)
    self:Print(("Request posted: %s.%s"):format(r.name, #who > 0 and (" Known crafters: " .. table.concat(who, ", ")) or ""))
    refreshPage()
end

function M:CloseRequest(id)
    local r = db.requests[id]
    if not r then return end
    db.requests[id] = nil
    self:Send("REQDEL", { id = id }, "ORG")
    refreshPage()
end

function M:OnRequest(r, sender)
    if type(r) ~= "table" or type(r.id) ~= "string" or type(r.item) ~= "string" or type(r.exp) ~= "number" then return end
    if db.requests[r.id] then return end
    local now = GetServerTime()
    if r.exp > now + REQUEST_HOURS * 3600 + 600 then return end
    r.t = (R.SaneTime and R:SaneTime(r.t)) or now
    r.id, r.item = r.id:sub(1, 24), r.item:sub(1, 200)
    r.note = type(r.note) == "string" and r.note:sub(1, 60) or ""
    r.by = sender
    r.name = type(r.name) == "string" and r.name or requestName(r)
    db.requests[r.id] = r
    local prof = canICraft(r.name)
    if prof then
        self:Toast(("%s needs %s, and you can make it (%s)%s."):format(W.ClassName(sender), r.name, prof,
            (r.note or "") ~= "" and (": " .. r.note) or ""), { sound = true })
    end
    refreshPage()
end

function M:OnRequestDelete(d, sender)
    -- only whoever posted the request closes it
    local r = type(d.id) == "string" and db.requests[d.id]
    if r and R.SameName and R:SameName(r.by, sender) then db.requests[d.id] = nil; refreshPage() end
end

function M:OnAsk()
    if ns.Treasury then ns.Treasury.Share() end
    C_Timer.After(3 + math.random() * 8, function()
        M.ShareMine(true)
        local now = GetServerTime()
        for _, r in pairs(db.requests) do
            if r.exp > now and r.by == UnitName("player") then self:Send("REQ", r, "ORG", nil, R.PRIORITY.BULK) end
        end
    end)
end

local function openRequests()
    local list, now = {}, GetServerTime()
    for id, r in pairs(db.requests) do
        if r.exp < now then db.requests[id] = nil else list[#list + 1] = r end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end

---------------------------------------------------------------------------
-- Bag sweep: keep, sell on the AH, or vendor
---------------------------------------------------------------------------
local LABELS = {
    keep   = { "Keep", C.good },
    ah     = { "Sell (AH)", C.gold },
    vendor = { "Vendor", C.dim },
    check  = { "Check AH", "|cff8ec8ff" },
    disenchant = { "Disenchant", C.bad },
    craft  = { "Craft", C.bad },
}

local function bagItems()
    local items = {}
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if not numSlots then return items end
    for bag = 0, 5 do   -- 5: the reagent bag
        for slot = 1, numSlots(bag) or 0 do
            local link, count, bound
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then link, count, bound = info.hyperlink, info.stackCount, info.isBound end
            elseif GetContainerItemInfo then
                local _, c, _, _, _, _, l, _, _, _, b = GetContainerItemInfo(bag, slot)
                link, count, bound = l, c, b
            end
            if link and not (issecretvalue and issecretvalue(link)) then
                items[#items + 1] = { link = link, count = count or 1, bound = bound, id = tonumber(link:match("item:(%d+)")) }
            end
        end
    end
    return items
end

local function classify(it)
    local name, _, quality, sell, class, equip = itemInfo(it.id)
    it.name, it.sell = name, sell or 0
    if class == "Quest" or quality == 7 then return "keep", "quest or heirloom item" end
    local codex = R:GetModule("Codex")
    if equip and equip ~= "" and codex and codex.Compare then
        local pct = codex:Compare(it.link)
        if pct == "empty" or pct == "noscore" or (type(pct) == "number" and pct >= 1) then return "keep", "an upgrade for you (Codex)" end
    end
    if quality == 0 then return "vendor", "junk" end
    local p = it.id and price(it.id)
    if it.bound or cannotTrade(it.id) then
        -- soulbound: the auction house is out, so disenchant, craft or vendor
        local best, why = M.BoundChoice(it.id, it.count, it.sell)
        if best == "disenchant" then return "disenchant", "soulbound: the mats are worth " .. why end
        if best == "craft" then return "craft", "soulbound: craft " .. why end
        return (it.sell > 0) and "vendor" or "keep", "soulbound"
    end
    local n = math.max(1, tonumber(it.count) or 1)
    if p and ahNet(p, n, it.sell) > it.sell * n then return "ah", "RUIN price " .. W.Money(p) end
    if p then return "vendor", "after the AH deposit and cut, the vendor pays more" end
    if it.sell > 0 then return "check", "no RUIN price yet" end
    return "keep", "can't be sold to a vendor"
end

function M:SweepBags()
    local out, ahTotal, vendorTotal = {}, 0, 0
    for _, it in ipairs(bagItems()) do
        if it.id then
            local label, why = classify(it)
            it.label, it.why = label, why
            local p = price(it.id)
            if label == "ah" and p then ahTotal = ahTotal + p * it.count end
            if label == "vendor" then vendorTotal = vendorTotal + it.sell * it.count end
            out[#out + 1] = it
        end
    end
    local order = { ah = 1, disenchant = 2, craft = 3, vendor = 4, check = 5, keep = 6 }
    table.sort(out, function(a, b)
        if a.label ~= b.label then return order[a.label] < order[b.label] end
        return (a.name or "") < (b.name or "")
    end)
    return out, ahTotal, vendorTotal
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Disenchanting: what an item is expected to break into, and what that's
-- worth on the auction house. The classic disenchanting tables, by the
-- item's quality and level (weapons swap the dust and essence chances).
---------------------------------------------------------------------------
local MAT = {
    strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204,
    lmagic = 10938, gmagic = 10939, lastral = 10998, gastral = 11082, lmystic = 11134, gmystic = 11135,
    lnether = 11174, gnether = 11175, leternal = 16202, geternal = 16203,
    sglim = 10978, lglim = 11084, sglow = 11138, lglow = 11139, srad = 11177, lrad = 11178,
    sbril = 14343, lbril = 14344, nexus = 20725,
}
-- mats' quality: dust white, essences green, shards blue, the crystal epic
local MAT_QUALITY = {}
for _, k in ipairs({ "strange", "soul", "vision", "dream", "illusion" }) do MAT_QUALITY[MAT[k]] = 1 end
for _, k in ipairs({ "lmagic", "gmagic", "lastral", "gastral", "lmystic", "gmystic", "lnether", "gnether", "leternal", "geternal" }) do MAT_QUALITY[MAT[k]] = 2 end
for _, k in ipairs({ "sglim", "lglim", "sglow", "lglow", "srad", "lrad", "sbril", "lbril" }) do MAT_QUALITY[MAT[k]] = 3 end
MAT_QUALITY[MAT.nexus] = 4
-- uncommon: { max level, dust, dust count, essence, essence count, shard }
local DE_GREEN = {
    { 15, "strange", 1.5, "lmagic", 1.5, nil },
    { 20, "strange", 2.5, "gmagic", 1.5, "sglim" },
    { 25, "strange", 5, "lastral", 1.5, "sglim" },
    { 30, "soul", 1.5, "gastral", 1.5, "lglim" },
    { 35, "soul", 3.5, "lmystic", 1.5, "sglow" },
    { 40, "vision", 1.5, "gmystic", 1.5, "lglow" },
    { 45, "vision", 3.5, "lnether", 1.5, "srad" },
    { 50, "dream", 1.5, "gnether", 1.5, "lrad" },
    { 55, "dream", 3.5, "leternal", 1.5, "sbril" },
    { 60, "illusion", 1.5, "geternal", 1.5, "lbril" },
    { 999, "illusion", 3.5, "geternal", 2.5, "lbril" },
}
-- rare: one shard (a sliver of a chance at a Nexus Crystal at the top)
local DE_BLUE = { { 25, "sglim" }, { 30, "lglim" }, { 35, "sglow" }, { 40, "lglow" }, { 45, "srad" }, { 50, "lrad" }, { 55, "sbril" }, { 999, "lbril" } }
-- epic: shards, then crystals
local DE_PURPLE = { { 45, "srad", 3 }, { 50, "lrad", 3 }, { 55, "sbril", 3 }, { 60, "nexus", 1 }, { 999, "nexus", 1.5 } }

-- { { id, chance, count }, ... } for an item, or nil when it can't be disenchanted
local function deYield(id)
    if not GetItemInfo then return nil end
    local name, _, quality, ilvl, _, _, _, _, equip, _, _, classID = GetItemInfo(id)
    if not name or not quality or quality < 2 or quality > 4 then return nil end
    if classID ~= 2 and classID ~= 4 then return nil end           -- weapons and armor only
    if not equip or equip == "" or equip == "INVTYPE_BAG" or equip == "INVTYPE_TABARD" or equip == "INVTYPE_BODY" then return nil end
    ilvl = tonumber(ilvl) or 0
    if ilvl < 5 then return nil end
    if quality == 2 then
        for _, row in ipairs(DE_GREEN) do
            if ilvl <= row[1] then
                local weapon = classID == 2
                local dustP, essP = weapon and 0.20 or 0.75, weapon and 0.75 or 0.20
                if not row[6] then dustP, essP = weapon and 0.20 or 0.80, weapon and 0.80 or 0.20 end
                local out = { { MAT[row[2]], dustP, row[3] }, { MAT[row[4]], essP, row[5] } }
                if row[6] then out[3] = { MAT[row[6]], 0.05, 1 } end
                return out
            end
        end
    elseif quality == 3 then
        if ilvl < 11 then return nil end
        for _, row in ipairs(DE_BLUE) do
            if ilvl <= row[1] then
                if row[2] == "lbril" and ilvl > 55 then return { { MAT.lbril, 0.995, 1 }, { MAT.nexus, 0.005, 1 } } end
                return { { MAT[row[2]], 1, 1 } }
            end
        end
    else
        if ilvl < 40 then return nil end
        for _, row in ipairs(DE_PURPLE) do
            if ilvl <= row[1] then return { { MAT[row[2]], 1, row[3] } } end
        end
    end
end
M.DisenchantYield = deYield

-- Expected value of disenchanting (copper), the most likely mat, whether
-- that mat is blue or better, and whether some mats had no price yet.
local deValueNow
local deMemo, deCount = {}, 0
local function deValue(id)
    local now = GetTime and GetTime() or 0
    local m = deMemo[id]
    if m and now - m.t < 3 and m.g == M.priceGen then return m[1], m[2], m[3], m[4] end
    local a, b, c, d = deValueNow(id)
    deCount = deCount + 1
    if deCount > 500 then deMemo, deCount = {}, 0 end
    deMemo[id] = { a, b, c, d, t = now, g = M.priceGen }
    return a, b, c, d
end
function deValueNow(id)
    local yield = deYield(id)
    if not yield then return nil end
    local total, missing, best, bestP = 0, false, nil, -1
    for _, y in ipairs(yield) do
        local p = M.ExpectedPrice(y[1]) or price(y[1])
        if p then total = total + p * y[2] * y[3] else missing = true end
        if y[2] > bestP then best, bestP = y[1], y[2] end
    end
    return total, best, (MAT_QUALITY[best] or 1) >= 3, missing
end
M.DisenchantValue = deValue

-- Crafting: what a reagent could be made into with your recipes, and
-- whether that sells for more than the reagents would. The best one wins.
local function saleValue(id, n)
    n = n or 1
    local _, _, _, sell = itemInfo(id)
    local p = not cannotTrade(id) and price(id) or nil
    local net = p and ahNet(p, n, sell) or nil
    local vend = sell and sell > 0 and sell * n or nil
    if not (net or vend) then return nil end
    return math.max(net or 0, vend or 0)
end
local function reagentValue(id, n, bound)
    -- what the reagents would fetch: the AH less its cut, or the vendor (only
    -- the vendor for a soulbound one)
    local _, _, _, sell = itemInfo(id)
    local p = not (bound or cannotTrade(id)) and price(id) or nil
    local ah = p and math.floor(p * n * (1 - AH_CUT)) or nil
    local vend = sell and sell > 0 and sell * n or nil
    if not (ah or vend) then return nil end
    return math.max(ah or 0, vend or 0)
end
-- Which of your recipes use each reagent: built once and rebuilt when your
-- recipes change (or every minute), so a tooltip only looks at the few
-- recipes that use its item instead of every recipe you know.
local craftIndex = { t = -1e9 }
local function recipesUsing(id)
    local me = R.GetPlayerGUID and db.crafters[R:GetPlayerGUID() or ""]
    if not (me and me.profs) then return nil end
    local now = GetTime and GetTime() or 0
    if craftIndex.me ~= me or craftIndex.book ~= db.recipeBook or now - craftIndex.t > 60 then
        local idx = {}
        for prof, list in pairs(me.profs) do
            local made = me.made and me.made[prof] and me.made[prof].i or {}
            local makes = me.made and me.made[prof] and me.made[prof].n or {}
            local book = db.recipeBook[prof] or {}
            for n, name in ipairs(list) do
                local product, reagents = made[n], book[name]
                if product and product > 0 and type(reagents) == "table" then
                    for _, r in ipairs(reagents) do
                        if r[1] ~= product then
                            idx[r[1]] = idx[r[1]] or {}
                            table.insert(idx[r[1]], { product = product, makes = math.max(1, tonumber(makes[n]) or 1), reagents = reagents })
                        end
                    end
                end
            end
        end
        craftIndex = { t = now, me = me, book = db.recipeBook, idx = idx }
    end
    return craftIndex.idx[id]
end
M.ForgetRecipes = function() craftIndex.t = -1e9 end

-- What one of an item is worth crafted, at its best: the most valuable thing
-- your recipes make from it, through as many as three crafting steps (Wool
-- Cloth into Bolts of Woolen Cloth into Greater Adept's Robes). A recipe is
-- charged everything it takes: all of this item it uses (two cloth for a
-- bolt), and the other reagents at what they cost to buy. What the product
-- is worth is the more of selling it and crafting it on. Returns the worth of
-- one, and the chain of products, or nil when no craft beats selling it.
-- Every price here is the market's: the low end of the last week on the
-- auction house (not one odd listing), the same price the tooltip's AH line
-- shows. So a craft is only worth it when what it makes sells for more than
-- everything that goes into it would.
local CRAFT_DEPTH = 3
local function market(id)
    return M.ExpectedPrice(id) or price(id)
end
-- what one is worth as it is: the market, or the vendor if he pays more
local function worthAsIs(id, bound)
    local _, _, _, sell = itemInfo(id)
    local p = not (bound or cannotTrade(id)) and market(id) or nil
    local v = sell and sell > 0 and sell or nil
    if not (p or v) then return nil end
    return math.max(p or 0, v or 0)
end
-- what the other reagents cost: a merchant or the market, whichever is cheaper
local function buyCost(id, n)
    local p = market(id)
    local v = db.vendor and db.vendor[id] and db.vendor[id].p
    if v and (not p or v < p) then p = v end
    if p then return p * n end
    local w = worthAsIs(id)
    return w and w * n or nil
end
local function unitWorth(id, bound, depth, seen)
    local base = worthAsIs(id, bound) or 0
    if depth >= CRAFT_DEPTH or seen[id] then return base, nil end
    local list = recipesUsing(id)
    if not list then return base, nil end
    seen[id] = true
    local best, chain = base, nil
    for _, rec in ipairs(list) do
        if not seen[rec.product] then
            local uses, others, ok = 0, 0, true
            for _, r in ipairs(rec.reagents) do
                if r[1] == id then uses = uses + r[2]
                else
                    local c = buyCost(r[1], r[2])
                    if not c then ok = false; break end
                    others = others + c
                end
            end
            if ok and uses > 0 then
                local pw, sub = unitWorth(rec.product, false, depth + 1, seen)
                local per = (pw * rec.makes - others) / uses
                if pw > 0 and per > best then
                    best, chain = per, { rec.product }
                    for _, x in ipairs(sub or {}) do chain[#chain + 1] = x end
                    chain.uses, chain.makes, chain.sale, chain.others = uses, rec.makes, pw * rec.makes, others
                end
            end
        end
    end
    seen[id] = nil
    return best, chain
end
local function bestCraftNow(id, bound)
    local base = worthAsIs(id, bound) or 0
    local worth, chain = unitWorth(id, bound, 0, {})
    if not chain then return nil end
    -- the margin of one craft: what it sells for, less everything it takes
    -- (this item too, at what it would sell for as it is)
    local cost = chain.others + base * chain.uses
    return { product = chain[1], chain = chain, uses = chain.uses, unit = worth, profit = (worth - base) * chain.uses,
             sale = chain.sale, cost = cost }
end

-- Tooltips ask again and again for the same item while it's shown: the
-- answer is kept for a few seconds.
local MEMO_SECONDS = 3
local memo = {}
local function memoized(kind, id, bound, fn)
    local now = GetTime and GetTime() or 0
    local key = kind .. tostring(id) .. (bound and "b" or "")
    local m = memo[key]
    if m and now - m.t < MEMO_SECONDS and m.g == M.priceGen then return m.v end
    local v = fn(id, bound)
    -- don't let the memo grow: start over now and then
    memo.count = (memo.count or 0) + 1
    if memo.count > 500 then memo = { count = 0 } end
    memo[key] = { v = v, t = now, g = M.priceGen }
    return v
end
local function bestCraft(id, bound) return memoized("c", id, bound, bestCraftNow) end
M.ForgetMemo = function() memo = {}; deMemo, deCount = {}, 0 end
M.BestCraft = bestCraft

-- "Bolt of Woolen Cloth > Greater Adept's Robe": what to make, step by step
function M.ChainText(chain)
    local t = {}
    for _, pid in ipairs(chain or {}) do
        t[#t + 1] = tostring(GetItemInfo and GetItemInfo(pid) or ("item " .. pid))
    end
    local s = table.concat(t, " > ")
    if chain and (chain.uses or 1) > 1 then s = chain.uses .. " per " .. s end
    return s
end

-- A soulbound item can only be disenchanted, crafted into something or sold
-- to a vendor. The one worth most for the stack: "disenchant", "craft",
-- "vendor" or nil, with a short note (the mats' worth, or what to craft).
function M.BoundChoice(id, count, sell)
    count = math.max(1, tonumber(count) or 1)
    sell = (tonumber(sell) or 0) * count
    local deTotal, deMat, _, deMissing = deValue(id)
    local de = (deTotal and not deMissing) and deTotal * count or 0
    local craft = bestCraft(id, true)
    local craftWorth = craft and math.floor(craft.unit * count) or 0
    if de > 0 and de > sell and de >= craftWorth then
        return "disenchant", W.Money(de), de, deMat
    elseif craft and craftWorth > sell then
        return "craft", M.ChainText(craft.chain), craftWorth, craft
    elseif sell > 0 then
        return "vendor", W.Money(sell), sell
    end
end

-- The RUIN: Exchange section of an item's tooltip, for the stack you're
-- looking at (count): a cheaper merchant, then what the stack is worth to a
-- vendor, disenchanted or crafted, and on the auction house after its fees,
-- the most in green, the least in red and the one between in amber.
local GREEN, AMBER, RED = "|cff5cd973", "|cffffb030", "|cfff26659"
local function priceLines(link, count, bound)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    if not id then return nil end
    count = math.max(1, math.floor(tonumber(count) or 1))
    bound = bound or cannotTrade(id)
    local p = db.prices[id]
    local _, _, _, vendor = itemInfo(id)
    local vp, src, by, kind = buyPrice(id)
    local canVendor = vendor and vendor > 0
    local lines = { C.gold .. "RUIN: Exchange|r" }
    -- a merchant who sells it for less than the auction house
    if src == "vendor" then
        local each = count > 1 and (" " .. C.dim .. "(" .. W.Money(vp) .. " each)|r") or ""
        lines[#lines + 1] = ("%sBuy from vendor:|r %s%s %sfrom %s|r"):format(C.white, W.Money(vp * count), each, C.dim, kind and (kind .. " NPC") or tostring(by))
    end
    if bound then lines[#lines + 1] = C.dim .. "Soulbound: can't be auctioned|r" end

    -- what the stack is worth each way: the vendor, disenchanting or crafting
    -- (whichever is worth more) and the auction house after its fees
    local rows = {}
    if canVendor then rows[#rows + 1] = { label = "Vendor", value = vendor * count } end
    local deTotal, deMat, _, deMissing = deValue(id)
    local de = (deTotal and not deMissing) and deTotal * count or nil
    local craft = bestCraft(id, bound)
    -- the stack's share of what its best craft (or chain of crafts) is worth,
    -- after every other reagent it takes
    local craftValue = craft and math.floor(craft.unit * count) or nil
    if de and (not craftValue or de >= craftValue) then
        local matName = deMat and (GetItemInfo and GetItemInfo(deMat)) or "enchanting mats"
        rows[#rows + 1] = { label = "Disenchant", value = de, note = tostring(matName), approx = true }
    elseif craftValue then
        rows[#rows + 1] = { label = "Craft", value = craftValue, note = M.ChainText(craft.chain), approx = true }
    end
    local ahRow
    if not bound then
        local expect = p and M.ExpectedPrice(id) or nil
        if expect then
            -- what the stack nets after the deposit and cut, at the low end of
            -- the week's prices
            ahRow = { label = "AH", value = math.max(0, ahNet(expect, count, vendor)) }
            rows[#rows + 1] = ahRow
        end
    end
    -- the most is green, the least red, the one between amber
    local sorted = {}
    for _, r in ipairs(rows) do sorted[#sorted + 1] = r.value end
    table.sort(sorted)
    local lo, hi = sorted[1], sorted[#sorted]
    for _, r in ipairs(rows) do
        local col = (r.value == hi and GREEN) or (r.value == lo and RED) or AMBER
        local each = count > 1 and ("  " .. C.dim .. "(" .. W.Money(math.floor(r.value / count + 0.5)) .. " each)|r") or ""
        -- what disenchanting gives, on the same line as what it's worth
        local into = (r.label == "Disenchant" and r.note) and ("  " .. C.dim .. "· " .. r.note .. "|r") or ""
        r.text = ("%s%s:|r %s%s%s|r%s%s"):format(C.white, r.label, col, r.approx and "~" or "", W.Money(r.value), each, into)
    end
    for _, r in ipairs(rows) do
        lines[#lines + 1] = r.text
        if r.label == "Craft" and craft then
            -- what to make, and the margin of crafting it and selling it
            lines[#lines + 1] = ("   %s%s|r"):format(C.dim, M.ChainText(craft.chain))
            local pct = craft.cost > 0 and math.floor((craft.sale - craft.cost) / craft.cost * 100 + 0.5) or nil
            lines[#lines + 1] = ("   %sMargin:|r %s+%s|r %sa craft%s: sells for %s, takes %s|r"):format(C.white, GREEN,
                W.Money(math.floor(craft.sale - craft.cost + 0.5)), C.dim,
                pct and (" (" .. pct .. "%)") or "", W.Money(math.floor(craft.sale + 0.5)), W.Money(math.floor(craft.cost + 0.5)))
        end
    end
    if not bound and not ahRow then lines[#lines + 1] = ("%sAH:|r %snone yet|r"):format(C.white, C.dim) end
    if #rows == 0 and not src and bound then return nil end
    if #rows == 0 and not src and not p and not canVendor then return nil end
    return lines
end
M.PriceLines = priceLines

-- How many are in the stack the tooltip shows: from the item's place in your
-- bags when the game says, else the bag slot the mouse is over.
local function tooltipCount(tooltip, data)
    local CI = rawget(_G, "C_Item")
    if type(data) == "table" and data.guid and CI and CI.GetItemLocation and CI.GetStackCount then
        local ok, loc = pcall(CI.GetItemLocation, data.guid)
        if ok and loc then
            local ok2, n = pcall(CI.GetStackCount, loc)
            if ok2 and tonumber(n) then return n end
        end
    end
    local owner = tooltip and tooltip.GetOwner and tooltip:GetOwner()
    local CC = rawget(_G, "C_Container")
    if owner and owner.GetBagID and owner.GetID and CC and CC.GetContainerItemInfo then
        local okb, bag = pcall(owner.GetBagID, owner)
        local info = okb and bag and CC.GetContainerItemInfo(bag, owner:GetID())
        if type(info) == "table" and tonumber(info.stackCount) then return info.stackCount end
    end
    return 1
end
M.TooltipCount = tooltipCount

-- Whether the item the tooltip shows is soulbound (or bound to the account):
-- from its place in your bags when the game says, else the tooltip's lines.
local BOUND_TEXT = {}
for _, k in ipairs({ "ITEM_SOULBOUND", "ITEM_ACCOUNTBOUND", "ITEM_BNETACCOUNTBOUND", "ITEM_ACCOUNTBOUND_UNTIL_EQUIP" }) do
    local v = rawget(_G, k)
    if type(v) == "string" then BOUND_TEXT[v] = true end
end
local function tooltipBound(tooltip, data)
    local CI = rawget(_G, "C_Item")
    if type(data) == "table" and data.guid and CI and CI.GetItemLocation and CI.IsBound then
        local ok, loc = pcall(CI.GetItemLocation, data.guid)
        if ok and loc then
            local ok2, b = pcall(CI.IsBound, loc)
            if ok2 and b ~= nil and not (issecretvalue and issecretvalue(b)) then return b and true or false end
        end
    end
    if type(data) == "table" and type(data.lines) == "table" then
        for _, l in ipairs(data.lines) do
            local t = type(l) == "table" and l.leftText
            if type(t) == "string" and not (issecretvalue and issecretvalue(t)) and BOUND_TEXT[t] then return true end
        end
    end
    local name = tooltip and tooltip.GetName and tooltip:GetName()
    if name then
        for i = 2, 6 do
            local fs = _G[name .. "TextLeft" .. i]
            local t = type(fs) == "table" and fs.GetText and fs:GetText()
            if type(t) == "string" and not (issecretvalue and issecretvalue(t)) and BOUND_TEXT[t] then return true end
        end
    end
    return false
end
M.TooltipBound = tooltipBound

-- The section sits in a box: a faint gold border with the inside a touch
-- darker. It's drawn on the tooltip under its text and follows the lines.
M.spacerKnown = {}      -- item link -> true (others add lines under the box) / false (nobody does)
local GOLD_EDGE = { 0.90, 0.72, 0.38, 0.40 }
local function boxFor(tooltip)
    local b = tooltip.ruinBox
    if b then return b end
    b = {}
    b.fill = tooltip:CreateTexture(nil, "BORDER", nil, 1)
    b.fill:SetColorTexture(0, 0, 0, 0.32)
    local function edge() local t = tooltip:CreateTexture(nil, "BORDER", nil, 2); t:SetColorTexture(unpack(GOLD_EDGE)); return t end
    b.top, b.bottom, b.left, b.right = edge(), edge(), edge(), edge()
    b.Hide = function(self) for _, t in ipairs({ self.fill, self.top, self.bottom, self.left, self.right }) do t:Hide() end end
    b.Show = function(self) for _, t in ipairs({ self.fill, self.top, self.bottom, self.left, self.right }) do t:Show() end end
    tooltip.ruinBox = b
    if tooltip.HookScript then
        tooltip:HookScript("OnTooltipCleared", function(self)
            if self.ruinBox then self.ruinBox:Hide() end
            self.ruinSpacer = nil
        end)
        tooltip:HookScript("OnHide", function(self) if self.ruinBox then self.ruinBox:Hide() end end)
        -- the blank line under the section is only for what another addon
        -- adds after it. When nothing did, it is emptied a frame later so it
        -- takes no room (a window that sets an item and then adds its own
        -- lines, like Codex's best-in-slot panel, does so after the show).
        -- What was learnt is remembered per item (spacerKnown), so a list
        -- that rebuilds its tooltip every frame, like the auction house,
        -- builds it the same size each time instead of growing and
        -- shrinking, and the tooltip is resized in place, not shown again
        -- (a second Show re-anchors it, which made it jump).
        local function trimSpacer(self)
            local n = self.ruinSpacer
            if not (n and self.NumLines and self:IsShown()) then return end
            local link = self.ruinSpacerLink
            if n ~= self:NumLines() then
                if link then M.spacerKnown[link] = true end      -- another addon added lines: keep the gap
                return
            end
            local name = self.GetName and self:GetName()
            local fs = name and _G[name .. "TextLeft" .. n]
            if fs and fs:GetText() == " " then
                local h = fs.GetHeight and fs:GetHeight() or 0
                fs:SetText("")
                self.ruinSpacer = nil
                if link then M.spacerKnown[link] = false end
                if h > 0 and self.GetHeight and self.SetHeight then
                    self:SetHeight(math.max(1, self:GetHeight() - h - 2))
                else
                    self:Show()
                end
            end
        end
        M.TrimSpacer = trimSpacer
        tooltip:HookScript("OnShow", function(self)
            if not self.ruinSpacer then return end
            if C_Timer and C_Timer.After then C_Timer.After(0, function() trimSpacer(self) end)
            else trimSpacer(self) end
        end)
    end
    return b
end

local function boxLines(tooltip, first, last)
    local name = tooltip.GetName and tooltip:GetName()
    local a, z = name and _G[name .. "TextLeft" .. first], name and _G[name .. "TextLeft" .. last]
    if not (a and z) then return end
    local b = boxFor(tooltip)
    b.fill:ClearAllPoints()
    b.fill:SetPoint("TOPLEFT", a, "TOPLEFT", -5, 5)
    b.fill:SetPoint("BOTTOMLEFT", z, "BOTTOMLEFT", -5, -5)
    b.fill:SetPoint("RIGHT", tooltip, "RIGHT", -6, 0)
    b.top:ClearAllPoints(); b.top:SetPoint("TOPLEFT", b.fill, "TOPLEFT"); b.top:SetPoint("TOPRIGHT", b.fill, "TOPRIGHT"); b.top:SetHeight(1)
    b.bottom:ClearAllPoints(); b.bottom:SetPoint("BOTTOMLEFT", b.fill, "BOTTOMLEFT"); b.bottom:SetPoint("BOTTOMRIGHT", b.fill, "BOTTOMRIGHT"); b.bottom:SetHeight(1)
    b.left:ClearAllPoints(); b.left:SetPoint("TOPLEFT", b.fill, "TOPLEFT"); b.left:SetPoint("BOTTOMLEFT", b.fill, "BOTTOMLEFT"); b.left:SetWidth(1)
    b.right:ClearAllPoints(); b.right:SetPoint("TOPRIGHT", b.fill, "TOPRIGHT"); b.right:SetPoint("BOTTOMRIGHT", b.fill, "BOTTOMRIGHT"); b.right:SetWidth(1)
    b:Show()
    tooltip.ruinBoxLines = { first, last }
end
M.BoxLines = boxLines

-- A recipe item ("Recipe: Tasty Lion Steak"): what one craft costs, and the
-- Price per Point at your skill when RUIN can tell. The reagents come from
-- RUIN's recipe book, or the tooltip's own reagent line ("Lion Meat (2),
-- Soothing Spices") just above "Requires Cooking (150)".
local function plain(t)
    if type(t) ~= "string" or (issecretvalue and issecretvalue(t)) then return nil end
    return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " "))
end

-- the tooltip's lines as plain text: from the tooltip data when the game
-- passes it, else from the tooltip's own text lines
local function tooltipTexts(tooltip, data)
    local out = {}
    if type(data) == "table" and type(data.lines) == "table" then
        for _, line in ipairs(data.lines) do
            local t = plain(line.leftText)
            if t then out[#out + 1] = t end
        end
        if #out > 0 then return out end
    end
    local name = tooltip and tooltip.GetName and tooltip:GetName()
    if not name then return out end
    for i = 1, (tooltip.NumLines and tooltip:NumLines()) or 30 do
        local fs = _G[name .. "TextLeft" .. i]
        local t = plain(fs and fs.GetText and fs:GetText())
        if t then out[#out + 1] = t end
    end
    return out
end

-- an item's id from its name: RUIN's item names, the game's cache, then the
-- names of items RUIN has prices for
local function idByName(nm)
    local id = R.Items.IdByName and R.Items.IdByName(nm)
    if not id then id = tonumber((GetItemInfoInstant(nm))) end
    if id and id <= 0 then id = nil end
    if not id and GetItemInfo then
        local _, link = GetItemInfo(nm)
        id = link and tonumber(link:match("item:(%d+)"))
    end
    if not id then
        for pid in pairs(db.prices) do
            if R.Items.Info(pid, true) == nm then id = pid; break end
        end
    end
    return id
end

local function parseReagents(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^[^:]-[Rr]eagents?:%s*", "")
    local out = {}
    for part in text:gmatch("[^,]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        local item, count = part:match("^(.-)%s*%((%d+)%)$")
        local id = idByName(item or part)
        if not id then return nil, item or part end
        out[#out + 1] = { id, tonumber(count) or 1 }
    end
    return #out > 0 and out or nil
end

function M.RecipeLines(itemName, texts)
    local recipe = type(itemName) == "string" and itemName:match("^[^:]+:%s*(.+)$")
    if not recipe then return nil end
    local prof, req, reagents, unknown
    local clean = {}
    for _, t in ipairs(texts or {}) do clean[#clean + 1] = plain(t) or "" end
    texts = clean
    for i, t in ipairs(texts) do
        local p, r = t:match("^%S+%s+(.-)%s*%((%d+)%)%s*$")
        if p and r and i > 1 and t:find("Requires", 1, true) then
            prof, req = p, tonumber(r)
            reagents, unknown = parseReagents(texts[i - 1])
        end
    end
    -- the book knows the counts even when the tooltip's line can't be read
    for p, book in pairs(db.recipeBook) do
        if book[recipe] and (not prof or p == prof) then prof = prof or p; reagents = book[recipe]; break end
    end
    if not reagents then
        if unknown then return { ("%sPrice per Craft: RUIN doesn't know %s yet (see it once, in your bags or the auction house).|r"):format(C.dim, unknown) } end
        return nil
    end
    if prof then rememberReagents(prof, recipe, reagents) end
    local lines = {}
    local cost, missing = craftCost(reagents)
    lines[1] = #missing > 0 and (C.dim .. "Price per Craft: some reagents have no RUIN price yet|r")
        or ("%sPrice per Craft: %s|r"):format(C.gold, W.Money(cost))
    if prof and #missing == 0 then
        if req and req > 0 then noteColor(prof, recipe, 0, req) end
        local skill = profSkill and profSkill(prof)
        if skill and req and skill < req then
            lines[#lines + 1] = ("%sYou need %d %s to learn it (you have %d).|r"):format(C.dim, req, prof, skill)
        elseif skill then
            local diff = predictDiff(prof, recipe, skill)
            local pt = diff and M.PointText(diff, reagents, prof, recipe, skill)
            if diff == 3 then
                lines[#lines + 1] = C.dim .. "Grey at your skill: no skill points.|r"
            elseif pt then
                lines[#lines + 1] = ("%sPrice per Point at your skill: %s"):format(C.gold, pt)
            else
                -- RUIN hasn't seen what color it is at your skill: give each
                lines[#lines + 1] = ("%sPrice per Point:|r %s%s|r orange, %s~%s|r yellow, %s~%s|r green"):format(C.gold,
                    C.gold, M.ShortMoney(cost), C.gold, M.ShortMoney(cost / overtime(SKILLUP_CHANCE[1], 1)), C.gold, M.ShortMoney(cost / overtime(SKILLUP_CHANCE[2], 2)))
            end
        end
    end
    return lines
end

-- A Waylaid Crate lists the bundles that fill it ("- 20 Dream Dust"): each
-- line gets what that bundle costs to buy, in coins. The lines can sit in one
-- text line (the Use: text) or one each; a line already priced is left alone.
local CRATE_LINE = "^(%s*%-%s*)(%d+)%s+([^|\n]-)%s*$"
-- Trade goods the crates ask for, by name, for when the game hasn't shown
-- you the item yet (a name the game can't place has no price). Checked
-- against the game's own name for the id whenever it knows it.
M.CrateGoods = {
    ["Peacebloom"] = 2447, ["Silverleaf"] = 765, ["Earthroot"] = 2449, ["Mageroyal"] = 785, ["Briarthorn"] = 2450,
    ["Stranglekelp"] = 3820, ["Bruiseweed"] = 2453, ["Wild Steelbloom"] = 3355, ["Grave Moss"] = 3369,
    ["Kingsblood"] = 3356, ["Liferoot"] = 3357, ["Fadeleaf"] = 3818, ["Goldthorn"] = 3821, ["Khadgar's Whisker"] = 3358,
    ["Wintersbite"] = 3819, ["Firebloom"] = 4625, ["Purple Lotus"] = 8831, ["Arthas' Tears"] = 8836, ["Sungrass"] = 8838,
    ["Blindweed"] = 8839, ["Ghost Mushroom"] = 8845, ["Gromsblood"] = 8846, ["Dreamfoil"] = 13463,
    ["Golden Sansam"] = 13464, ["Mountain Silversage"] = 13465, ["Plaguebloom"] = 13466, ["Icecap"] = 13467,
    ["Black Lotus"] = 13468,
    ["Copper Ore"] = 2770, ["Tin Ore"] = 2771, ["Iron Ore"] = 2772, ["Silver Ore"] = 2775, ["Gold Ore"] = 2776,
    ["Mithril Ore"] = 3858, ["Truesilver Ore"] = 7911, ["Thorium Ore"] = 10620, ["Dark Iron Ore"] = 11370,
    ["Copper Bar"] = 2840, ["Bronze Bar"] = 2841, ["Iron Bar"] = 3575, ["Steel Bar"] = 3859, ["Mithril Bar"] = 3860,
    ["Truesilver Bar"] = 6037, ["Thorium Bar"] = 12359, ["Dark Iron Bar"] = 11371, ["Arcanite Bar"] = 12360,
    ["Light Leather"] = 2318, ["Medium Leather"] = 2319, ["Heavy Leather"] = 4234, ["Thick Leather"] = 4304,
    ["Rugged Leather"] = 8170, ["Thick Hide"] = 8169, ["Rugged Hide"] = 8171,
    ["Linen Cloth"] = 2589, ["Wool Cloth"] = 2592, ["Silk Cloth"] = 4306, ["Mageweave Cloth"] = 4338,
    ["Runecloth"] = 14047, ["Felcloth"] = 14256, ["Bolt of Silk Cloth"] = 4305, ["Bolt of Mageweave"] = 4339,
    ["Bolt of Runecloth"] = 14048,
    ["Strange Dust"] = 10940, ["Soul Dust"] = 11083, ["Vision Dust"] = 11137, ["Dream Dust"] = 11176,
    ["Illusion Dust"] = 16204, ["Lesser Nether Essence"] = 11174, ["Greater Nether Essence"] = 11175,
    ["Lesser Eternal Essence"] = 16202, ["Greater Eternal Essence"] = 16203, ["Small Radiant Shard"] = 11177,
    ["Large Radiant Shard"] = 11178, ["Small Brilliant Shard"] = 14343, ["Large Brilliant Shard"] = 14344,
    ["Essence of Fire"] = 7078, ["Essence of Earth"] = 7076, ["Essence of Water"] = 7080, ["Essence of Air"] = 7082,
    ["Essence of Undeath"] = 12808, ["Elemental Fire"] = 7068, ["Heart of Fire"] = 7077, ["Core of Earth"] = 7075,
    ["Globe of Water"] = 7079, ["Breath of Wind"] = 7081,
}
function M.CrateItem(name)
    local id = M.CrateGoods[name]
    if id then
        local known = GetItemInfo and GetItemInfo(id)
        if not known then
            if R.Items.Request then R.Items.Request(id) end
            return id
        end
        if known == name then return id end                 -- else not the item this realm calls that
    end
    return idByName(name)
end
-- The bundles a Waylaid Crate's tooltip lists ("- 20 Dreamfoil"), read from
-- its lines: { { n = 20, name = "Dreamfoil", id = 13463 }, ... }, or nil when
-- the tooltip isn't a crate's.
function M.CrateBundles(tooltip)
    local tname = tooltip and tooltip.GetName and tooltip:GetName()
    local first = tname and _G[tname .. "TextLeft1"]
    local title = plain(first and first.GetText and first:GetText())
    if not (type(title) == "string" and title:find("^Waylaid Crate")) then return nil end
    local out = {}
    for i = 2, (tooltip.NumLines and tooltip:NumLines()) or 0 do
        local fs = _G[tname .. "TextLeft" .. i]
        local text = fs and fs.GetText and fs:GetText()
        for line in tostring(text or ""):gmatch("[^\n]+") do
            local clean = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local _, n, item = clean:match(CRATE_LINE)
            if item then out[#out + 1] = { n = tonumber(n), name = item, id = M.CrateItem(item) } end
        end
    end
    return #out > 0 and out or nil
end

-- The crate's bundles as lines for the RUIN: Exchange box: each bundle with
-- what it costs on the auction house (the low end of the week, as the AH row).
function M.CrateLines(bundles)
    local lines = { C.white .. "Fill it with:|r" }
    for _, b in ipairs(bundles or {}) do
        local unit = b.id and (M.ExpectedPrice(b.id) or price(b.id))
        local cost = unit and (W.Money(unit * b.n) .. "  " .. C.dim .. "(" .. W.Money(unit) .. " each)|r") or (C.dim .. "none yet|r")
        lines[#lines + 1] = ("   %s%d %s:|r %s"):format(C.white, b.n, b.name, cost)
    end
    return lines
end

-- /exchange tipdebug, then hover a crate: what Exchange reads from each bundle line
function M.CrateDebug(bundles)
    M.tipDebug = false
    for _, b in ipairs(bundles or {}) do
        local unit = b.id and (M.ExpectedPrice(b.id) or price(b.id))
        M:Print(("crate: %d x [%s] name id %s, list id %s, used id %s, game name %s, AH %s"):format(b.n, b.name,
            tostring(idByName(b.name)), tostring(M.CrateGoods[b.name]), tostring(b.id),
            tostring(b.id and GetItemInfo and GetItemInfo(b.id)), unit and W.PlainMoney(W.Money(unit)) or "none"))
    end
end

local function onTooltip(tooltip, data)
    if not db or not db.tooltip then return end
    local link
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        link = select(2, TooltipUtil.GetDisplayedItem(tooltip))
    elseif tooltip.GetItem then
        link = select(2, tooltip:GetItem())
    end
    if not link or (issecretvalue and issecretvalue(link)) then return end
    if tooltip.ruinBox then tooltip.ruinBox:Hide() end
    local ok, lines = pcall(priceLines, link, tooltipCount(tooltip, data), M.TooltipBound(tooltip, data))
    -- a Waylaid Crate: each bundle it takes and its auction house cost, in the box
    local okc, bundles = pcall(M.CrateBundles, tooltip)
    if okc and bundles then
        if M.tipDebug then pcall(M.CrateDebug, bundles) end
        -- protected too, so one bad price can't raise an error on every crate hover
        local okl, crate = pcall(M.CrateLines, bundles)
        if okl and type(crate) == "table" then
            if not (ok and lines) then ok, lines = true, { C.gold .. "RUIN: Exchange|r" } end
            for _, l in ipairs(crate) do lines[#lines + 1] = l end
        end
    end

    local ok3, err = pcall(function()
        local id = tonumber(tostring(link):match("item:(%d+)"))
        local name, _, _, _, class = itemInfo(id)
        if not name and GetItemInfo then name, _, _, _, _, class = GetItemInfo(link) end
        local classID = GetItemInfoInstant and select(6, GetItemInfoInstant(id))
        -- a recipe's tooltip reports the item it makes (Tasty Lion Steak), so
        -- the recipe itself is read from the tooltip's title line
        local title
        local tname = tooltip and tooltip.GetName and tooltip:GetName()
        local first = tname and _G[tname .. "TextLeft1"]
        title = plain(first and first.GetText and first:GetText())
        local function recipeName(n)
            return type(n) == "string" and (n:match("^Recipe:") or n:match("^Pattern:") or n:match("^Formula:") or n:match("^Plans:")
                or n:match("^Schematic:") or n:match("^Manual:") or n:match("^Design:")) and n or nil
        end
        if recipeName(title) then name = title end
        local isRecipe = name and (class == "Recipe" or classID == 9 or recipeName(name))
        local texts = {}
        if isRecipe then
            -- the tooltip's own lines hold the reagents and the skill; the data may only describe the made item
            texts = tooltipTexts(tooltip, nil)
            if #texts == 0 then texts = tooltipTexts(tooltip, data) end
        end
        for _, t in ipairs(texts) do if t:find("Price per Craft", 1, true) then isRecipe = false end end   -- already added
        local extra = isRecipe and M.RecipeLines(name, texts) or nil
        if M.tipDebug then
            M.tipDebug = false
            M:Print(("tip debug: id %s, name %s, class %s (%s), recipe %s, %d lines, result %s"):format(tostring(id), tostring(name),
                tostring(class), tostring(classID), tostring(isRecipe and true or false), #texts, extra and #extra or "nil"))
            for i, t in ipairs(texts) do M:Print(("  %d: %s"):format(i, t)) end
            for _, l in ipairs(extra or {}) do M:Print("  -> " .. l) end
        end
        if extra then for _, l in ipairs(extra) do tooltip:AddLine(l) end end
    end)
    -- the Exchange section last, in its box
    if ok and lines and #lines > 0 then
        tooltip:AddLine(" ")
        local boxFrom = (tooltip.NumLines and tooltip:NumLines() or 0) + 1
        for _, l in ipairs(lines) do tooltip:AddLine(l) end
        local boxTo = tooltip.NumLines and tooltip:NumLines() or 0
        if boxTo >= boxFrom then pcall(boxLines, tooltip, boxFrom, boxTo) end
        -- room under the box for lines other addons add after it (a drop location),
        -- unless this item's tooltip was seen to get none
        if M.spacerKnown[link] ~= false then
            tooltip:AddLine(" ")
            tooltip.ruinSpacer = tooltip.NumLines and tooltip:NumLines() or nil
            tooltip.ruinSpacerLink = link
        else
            tooltip.ruinSpacer = nil
        end
    end
    if not ok3 and M.tipDebug then M.tipDebug = false; M:Print("tip debug error: " .. tostring(err)) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltip)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", onTooltip)
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
-- Opens a whisper to the full name. The game's own helper types
-- "/cw Name Surname" into the chat box, and the chat box then guesses where a
-- WoW Forever name ends (often after the first name), so set the target directly.
local function whisper(name)
    if type(name) ~= "string" or name == "" then return end
    local CF = rawget(_G, "ChatFrameUtil")
    local choose = (CF and CF.ChooseBoxForSend) or rawget(_G, "ChatEdit_ChooseBoxForSend")
    local open = (CF and CF.OpenChat) or rawget(_G, "ChatFrame_OpenChat")
    local box = choose and choose()
    if box and open then
        open("")
        box:SetAttribute("chatType", "WHISPER")
        box:SetAttribute("tellTarget", name)
        if box.UpdateHeader then box:UpdateHeader()
        elseif rawget(_G, "ChatEdit_UpdateHeader") then ChatEdit_UpdateHeader(box) end
        return
    end
    local send = rawget(_G, "ChatFrame_SendTell") or (CF and CF.SendTell)
    if send then send(name) end
end
M.Whisper = whisper

-- Who in RUIN is online right now, by GUID.
local function onlineSet()
    local set = {}
    for _, p in ipairs((R.GetOnlineMembers and R:GetOnlineMembers()) or {}) do
        if p.guid then set[p.guid] = true end
    end
    return set
end

-- Everyone who can craft a recipe, best pick first: online members with the
-- lowest skill in the profession (they gain the most from crafting it), then
-- you, then (with "Offline crafters") offline members, lowest skill first.
-- Unknown skill (older RUIN versions) sorts after known skill.
local function rankCrafters(list)
    table.sort(list, function(a, b)
        local ga = a.online and (a.self and 1 or 0) or 2
        local gb = b.online and (b.self and 1 or 0) or 2
        if ga ~= gb then return ga < gb end
        local sa, sb = a.skill or 100000, b.skill or 100000
        if sa ~= sb then return sa < sb end
        return tostring(a.name) < tostring(b.name)
    end)
    return list
end

local function search()
    local q = ui.query:lower()
    local items = {}
    if ui.mode == "Crafters" then
        -- by profession, then recipe; each recipe shows one crafter (pick another from the list on the name)
        local online, me = onlineSet(), R:GetPlayerGUID()
        local byProf = {}
        for guid, e in pairs(db.crafters) do
            local isOnline = online[guid] == true or guid == me
            for prof, list in pairs(e.profs or {}) do
                if not ui.findProf or ui.findProf == "All professions" or ui.findProf == prof then
                    local made = e.made and e.made[prof]
                    local skill = e.skill and tonumber(e.skill[prof])
                    for n, recipe in ipairs(list) do
                        if q == "" or recipe:lower():find(q, 1, true) then
                            local iid = made and tonumber(made.i[n]) or 0
                            local quality = made and tonumber(made.q[n]) or -1
                            byProf[prof] = byProf[prof] or {}
                            local rec = byProf[prof][recipe]
                            if not rec then
                                rec = { recipe = recipe, prof = prof, key = prof .. "\001" .. recipe, crafters = {} }
                                byProf[prof][recipe] = rec
                            end
                            if iid > 0 and not rec.id then rec.id = iid end
                            if quality >= 0 and not rec.quality then rec.quality = quality end
                            rec.crafters[#rec.crafters + 1] = { guid = guid, name = e.name, guild = e.guild, skill = skill,
                                online = isOnline, self = guid == me }
                        end
                    end
                end
            end
        end
        local profs = {}
        for prof in pairs(byProf) do profs[#profs + 1] = prof end
        table.sort(profs)
        for _, prof in ipairs(profs) do
            local rows = {}
            for _, rec in pairs(byProf[prof]) do
                rankCrafters(rec.crafters)
                -- without "Offline crafters", only online ones count
                if not db.showOffline then
                    local on = {}
                    for _, c in ipairs(rec.crafters) do if c.online then on[#on + 1] = c end end
                    rec.crafters = on
                end
                if #rec.crafters > 0 then
                    -- the one you picked from the list, while they still can
                    local picked = ui.picked and ui.picked[rec.key]
                    rec.who = rec.crafters[1]
                    for _, c in ipairs(rec.crafters) do if c.guid == picked then rec.who = c end end
                    rows[#rows + 1] = rec
                end
            end
            table.sort(rows, function(a, b) return a.recipe < b.recipe end)
            if #rows > 0 then
                items[#items + 1] = { header = prof, count = #rows }
                for _, r in ipairs(rows) do
                    if #items >= 300 then return items end
                    local _, link, iq = nil, nil, nil
                    if r.id then _, link, iq = R.Items.Info(r.id) end
                    r.quality = r.quality or iq
                    r.link = link
                    items[#items + 1] = r
                end
            end
        end
        return items
    else
        -- every match first, newest first, then the top 200 (a full scan
        -- brings thousands; stopping early showed a random 200)
        local now, hits, unnamed = GetServerTime(), {}, 0
        for id, p in pairs(db.prices) do
            local name = R.Items.Info(id, true)
            -- names only matter for matching a search; the rows shown ask for their own
            if not name then unnamed = unnamed + 1; if q ~= "" then M.WantName(id) end end
            if q == "" or (name and name:lower():find(q, 1, true)) then
                hits[#hits + 1] = { id = id, p = p, t = p.t or 0 }
            end
        end
        table.sort(hits, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.id < b.id end)
        for i = 1, math.min(#hits, 200) do
            local h = hits[i]
            local _, link = R.Items.Info(h.id)
            local _, pct = M:Trend(h.id)
            local vp, src, by, kind = buyPrice(h.id)
            local vend = src == "vendor" and ("  " .. C.good .. W.Money(vp) .. " from " .. (kind and (kind .. " NPC") or tostring(by)) .. "|r") or ""
            items[#items + 1] = { text = ("%s  %s%s|r  %s  %s%s|r%s"):format(R.Items.Text(h.id), C.gold, W.Money(h.p.p), trendText(pct), C.dim,
                W.Ago(now - h.t), vend), t = h.t, link = link }
        end
        ui.unnamed = (q ~= "" and unnamed > 0) and unnamed or nil
    end
    return items
end

-- "Brin Stone  112", "You  75", "Kell Dawn  140  offline".
function M.CrafterLabel(c)
    if type(c) ~= "table" then return tostring(c or "") end
    local name = c.self and (C.gold .. "You|r") or W.ClassName(c.name)
    local skill = c.skill and ("  " .. C.white .. c.skill .. "|r") or (C.dim .. "  skill ?|r")
    return name .. skill .. (c.online and "" or (C.dim .. "  offline|r"))
end

-- One list for the whole page (rows scroll, and a menu inside the list would be clipped).
function M.OpenCrafterList(anchor, rec)
    local pick = ui.crafterList
    if not (pick and rec) then return end
    if pick:IsShown() and pick.rec == rec.key then pick:Hide(); return end
    pick.rec = rec.key
    local width = 300
    for i, c in ipairs(rec.crafters) do
        local b = pick.items[i]
        if not b then
            b = W.Button(pick, "", width - 8)
            b:SetHeight(20)
            if b.label then b.label:SetJustifyH("LEFT") end
            pick.items[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 4, -24 - (i - 1) * 21)
        b:SetText(M.CrafterLabel(c) .. ((c.guild and c.guild ~= "") and (C.dim .. "  " .. c.guild .. "|r") or ""))
        if rec.who and c.guid == rec.who.guid then b:LockHighlight() else b:UnlockHighlight() end
        b:SetScript("OnClick", function()
            ui.picked = ui.picked or {}
            ui.picked[rec.key] = c.guid
            pick:Hide()
            refreshPage()
        end)
        b:Show()
    end
    for i = #rec.crafters + 1, #pick.items do pick.items[i]:Hide() end
    pick.title:SetText(C.gold .. rec.recipe .. "|r  " .. C.dim .. "who can craft it|r")
    pick:SetSize(width, 28 + #rec.crafters * 21)
    pick:ClearAllPoints()
    pick:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    pick:Show()
end

-- The Find list for a query, as the page shows it (for tests and other modules).
function M.SearchRows(query, prof, mode)
    local q, p, m = ui.query, ui.findProf, ui.mode
    ui.query, ui.findProf, ui.mode = query or "", prof or "All professions", mode or "Crafters"
    local ok, rows = pcall(search)
    ui.query, ui.findProf, ui.mode = q, p, m
    return ok and rows or {}
end
M.UI = ui

local function buildSearch(page)
    local pick = W.Card(page)
    W.Skin(pick, "panel", 1, "glow")
    if pick.SetFrameStrata then pick:SetFrameStrata("DIALOG") end
    pick:EnableMouse(true)
    pick.items = {}
    pick.title = W.Label(pick, "", "GameFontHighlightSmall")
    pick.title:SetPoint("TOPLEFT", 8, -6)
    pick:Hide()
    page:HookScript("OnHide", function() pick:Hide() end)
    ui.crafterList = pick

    local mode = W.Cycle(page, 150, { "Crafters", "Prices" }, function() return ui.mode end,
        function(v) ui.mode = v; ui.searchBox:SetPlaceholder(v == "Crafters" and "Recipe, e.g. Flask" or "Item name, e.g. Linen Cloth"); refreshPage() end, "Find: ")
    mode.tipTitle = "Search who can craft something, or what it sells for"
    mode:SetPoint("TOPLEFT", 0, -2)
    local box = W.EditBox(page, 210, function(t) ui.query = t; refreshPage() end, "Recipe, e.g. Flask")
    box:SetPoint("LEFT", mode, "RIGHT", 12, 0)
    box:SetScript("OnTextChanged", function(self, user) if user then ui.query = self:GetText(); refreshPage() end end)
    ui.searchBox = box
    ui.profBtn = W.Dropdown(page, 170, function()
        local set, list = {}, { "All professions" }
        for _, e in pairs(db.crafters) do for prof in pairs(e.profs or {}) do set[prof] = true end end
        local names = {}
        for prof in pairs(set) do names[#names + 1] = prof end
        table.sort(names)
        for _, n in ipairs(names) do list[#list + 1] = n end
        return list
    end, function() return ui.findProf end, function(v) ui.findProf = v; refreshPage() end)
    ui.profBtn.tipTitle = "Show one profession"
    ui.profBtn:SetPoint("LEFT", box, "RIGHT", 8, 0)
    local tip = W.Check(page, "Tooltip prices", function() return db.tooltip end, function(v) db.tooltip = v end)
    tip:SetPoint("TOPRIGHT", page, "TOPRIGHT", -96, 0)
    ui.offlineCheck = W.Check(page, "Offline crafters", function() return db.showOffline end,
        function(v) db.showOffline = v; refreshPage() end)
    ui.offlineCheck:SetPoint("TOPRIGHT", page, "TOPRIGHT", -290, -26)
    ui.offlineCheck.tip = "Also show recipes only offline members know, and offline crafters in each recipe's list"

    ui.addMine = W.Button(page, "Add my recipes", 118, function()
        if InCombatLockdown() then return M:Print("After combat.") end
        M.RefreshScanPrompt(true)
    end)
    ui.addMine.tip = "Open your professions once so RUIN can list your recipes"
    ui.addMine:SetPoint("TOPRIGHT", page, "TOPRIGHT", -24, -26)
    ui.addMine:SetHeight(20)
    ui.summary = W.Label(page, "", "GameFontHighlightSmall")
    ui.summary:SetPoint("TOPLEFT", 0, -30)
    ui.summary:SetPoint("RIGHT", page, "RIGHT", -6, 0)
    -- column heads for the crafter list
    ui.heads = CreateFrame("Frame", nil, page)
    ui.heads:SetPoint("TOPLEFT", 0, -46)
    ui.heads:SetPoint("RIGHT", page, "RIGHT", -24, 0)
    ui.heads:SetHeight(14)
    for _, h in ipairs({ { "Profession / recipe", 4 }, { "Crafter (lowest skill online first)", 330 }, { "Quality", 536 } }) do
        local fs = W.Label(ui.heads, h[1], "GameFontHighlightSmall")
        fs:SetTextColor(W.PALETTE.sub[1], W.PALETTE.sub[2], W.PALETTE.sub[3])
        fs:SetPoint("LEFT", h[2], 0)
    end

    ui.list = W.List(page, 24, function(row)
        row.text = W.Label(row, "")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -74, 0)
        row.text:SetWordWrap(false)
        row.crafter = W.Label(row, "")
        row.crafter:SetPoint("LEFT", 330, 0)
        row.crafter:SetWidth(200)
        row.crafter:SetWordWrap(false)
        -- the crafter's name is a button: it opens everyone else who can craft it
        row.pick = W.Button(row, "", 200, function(self) M.OpenCrafterList(self, self.rec) end)
        row.pick:SetPoint("LEFT", 326, 0)
        row.pick:SetHeight(20)
        if row.pick.label then row.pick.label:SetJustifyH("LEFT"); row.pick.label:SetWordWrap(false) end
        W.MarkChoice(row.pick, "Everyone who can craft it")
        row.quality = W.Label(row, "", "GameFontHighlightSmall")
        row.quality:SetPoint("LEFT", 536, 0)
        row.quality:SetWidth(90)
        row.quality:SetWordWrap(false)
        row.btn = W.Button(row, "Whisper", 70)
        row.btn:SetPoint("RIGHT", 0, 0)
    end, function(row, item)
        local who = item.who
        local whoName = type(who) == "table" and who.name or who
        local canWhisper = whoName ~= nil and not (type(who) == "table" and (who.self or not who.online))
        row.btn:SetShown(canWhisper)
        row.btn:SetScript("OnClick", function() if canWhisper then whisper(whoName) end end)
        row.pick:Hide()
        row.link = item.link
        if item.header then                        -- a profession heading
            row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.text:SetText(C.gold .. item.header .. "|r  " .. C.dim .. item.count .. (item.count == 1 and " recipe" or " recipes") .. "|r")
            row.crafter:SetText(""); row.quality:SetText("")
        elseif item.recipe then                    -- recipe, crafter, quality
            row.text:SetPoint("RIGHT", row, "LEFT", 324, 0)
            row.text:SetText("   " .. (item.id and R.Items.Text(item.id, item.recipe, item.quality) or (C.white .. item.recipe .. "|r")))
            row.crafter:SetText("")
            row.pick.rec = item
            row.pick:SetText(M.CrafterLabel(who) .. (#item.crafters > 1 and (C.dim .. "  +" .. (#item.crafters - 1) .. "|r") or ""))
            row.pick:Show()
            row.quality:SetText(item.quality and (R.Items.QualityHex(item.quality) .. R.Items.QualityName(item.quality) .. "|r")
                or (C.dim .. (item.id and "?" or "no item") .. "|r"))
        else                                       -- a price line
            row.text:SetPoint("RIGHT", row, "RIGHT", -74, 0)
            row.text:SetText(item.text)
            row.crafter:SetText(""); row.quality:SetText("")
        end
    end)
    ui.list:SetEmptyText("Nothing found. Prices arrive as RUIN members browse the auction house; recipes as they open a profession.")
    ui.list.frame:SetPoint("TOPLEFT", 0, -62)
    ui.list.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 0)
end

local function buildRequests(page)
    local card = W.Card(page)
    card:SetPoint("TOPLEFT", 0, 0)
    card:SetPoint("RIGHT", page, "RIGHT", -4, 0)
    card:SetHeight(60)
    local h = W.Header(card, "Ask RUIN to craft something")
    h:SetPoint("TOPLEFT", 8, -6)
    ui.reqItem = W.EditBox(card, 240, nil, "Item to craft (shift-click or type)")
    ui.reqItem:SetPoint("TOPLEFT", 10, -28)
    local note = W.EditBox(card, 220, nil, "Note, e.g. I bring the mats")
    note:SetPoint("LEFT", ui.reqItem, "RIGHT", 8, 0)
    local post = W.Button(card, "Post", 64, function()
        M:Request(ui.reqItem:GetText(), note:GetText())
        ui.reqItem:SetText(""); note:SetText("")
    end)
    post:SetPoint("LEFT", note, "RIGHT", 8, 0)

    local h2 = W.Header(page, "Open requests")
    h2:SetPoint("TOPLEFT", 0, -72)
    local sub = W.Label(page, C.dim .. "Crafters who know the recipe get an alert. Requests close after a day.|r", "GameFontHighlightSmall")
    sub:SetPoint("LEFT", h2, "RIGHT", 10, 0)
    ui.reqList = W.List(page, 28, function(row)
        row.text = W.Label(row, "")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -76, 0)
        row.text:SetWordWrap(false)
        row.btn = W.Button(row, "Whisper", 72)
        row.btn:SetPoint("RIGHT", 0, 0)
    end, function(row, r)
        local mine = r.by == UnitName("player")
        local can = canICraft(r.name)
        local who = craftersOf(r.name)
        row.text:SetText(("%s  %s%s|r  %s%s%s|r"):format(r.item, C.dim, (r.note or "") ~= "" and ("\"" .. r.note .. "\"  ") or "",
            mine and (C.gold .. "yours") or W.ClassName(r.by), can and (C.good .. "  ·  you can make this|r") or
            (#who > 0 and (C.dim .. "  ·  " .. #who .. " crafter" .. (#who == 1 and "" or "s") .. "|r") or ""), ""))
        row.link = r.item:match("|H(item:[^|]+)|h")
        row.btn:SetText(mine and "Done" or "Whisper")
        row.btn:SetScript("OnClick", function() if mine then M:CloseRequest(r.id) else whisper(r.by) end end)
    end)
    ui.reqList:SetEmptyText("No open requests. Need a flask or a bag made? Ask above.")
    ui.reqList.frame:SetPoint("TOPLEFT", 0, -84)
    ui.reqList.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 0)

    local function insert(link)
        if type(link) == "string" and ui.reqItem and ui.reqItem:HasFocus() then ui.reqItem:SetText(link) end
    end
    if ChatEdit_InsertLink then pcall(hooksecurefunc, "ChatEdit_InsertLink", insert) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then pcall(hooksecurefunc, ChatFrameUtil, "InsertLink", insert) end
end

local function buildLeveling(page)
    local h = W.Header(page, "Cheapest next skill-ups")
    h:SetPoint("TOPLEFT", 0, -2)
    ui.profs = {}
    ui.profPick = W.Button(page, "", 160, nil)
    W.MarkChoice(ui.profPick)
    W.AttachMenu(ui.profPick, { width = 160,
        items = function()
            local names = {}
            for prof in pairs(db.plans) do names[#names + 1] = prof end
            table.sort(names)
            return names
        end,
        current = function() return ui.prof end, pick = function(v) ui.prof = v; refreshPage() end })
    ui.profPick:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 2)
    ui.overtimeBtn = W.Cycle(page, 172, { 0, 1, 2, 3, 4, 5 }, function() return tonumber(db.overtime) or 0 end,
        function(v) db.overtime = v; M.RepaintRecipeCosts(); refreshPage() end, "Working Overtime: ")
    ui.overtimeBtn.format = function(v) return v .. "/5" end
    ui.overtimeBtn.tipTitle = "Your Working Overtime rank (Legacy talent): +4% skill-up chance a rank on yellow and green recipes, in Price per Point"
    ui.overtimeBtn:SetPoint("TOPRIGHT", ui.profPick, "TOPLEFT", -8, 0)
    ui.levelInfo = W.Label(page, "", "GameFontHighlightSmall")
    ui.levelInfo:SetPoint("TOPLEFT", 0, -22)
    ui.levelInfo:SetPoint("RIGHT", page, "RIGHT", -6, 0)
    ui.levelList = W.List(page, 26, function(row)
        row.text = W.Label(row, "")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetWordWrap(false)
    end, function(row, r, i)
        local cost = r.missing > 0 and (C.dim .. "needs prices for " .. r.missing .. " reagent" .. (r.missing == 1 and "" or "s") .. "|r")
            or (C.gold .. (r.exact and "" or "~") .. W.Money(r.perPoint) .. "|r" .. C.dim .. " per point|r")
        row.text:SetText(("%s%d.|r %s%s|r%s  %s  %s"):format(C.dim, i, C.white, r.name, r.unlearned and (C.dim .. " (not learned)|r") or "",
            DIFFICULTY_NAME[r.diff] or "", cost))
        row.tip = function(tip)
            tip:AddLine(r.name, 1, 0.82, 0)
            if r.unlearned then tip:AddLine("Not learned yet. At your skill it would be " .. (DIFFICULTY_NAME[r.diff] or "?") .. ", so it's worth training.", 0.6, 0.85, 1, true) end
            local plan = db.plans[ui.prof]
            local t = thresholds(ui.prof, r.name)
            if r.exact and t then
                tip:AddLine(("Skill-up chance %d%%: yellow from %s, grey from %s (your skill %s)"):format(math.floor((r.chance or 1) * 100 + 0.5),
                    tostring(t.y or ((t.o or 0) + 1)), tostring(t.x or "?"), tostring(plan and plan.skill or "?")), 0.8, 0.85, 0.95, true)
            elseif r.diff ~= 0 then
                tip:AddLine(("Skill-up chance about %d%% (a guess: RUIN hasn't seen where this recipe turns yellow and grey yet)"):format(
                    math.floor((r.chance or 1) * 100 + 0.5)), 0.6, 0.6, 0.6, true)
            end
            tip:AddLine(("One craft: %s from RUIN prices"):format(W.Money(r.cost)), 1, 1, 1)
            for _, rg in ipairs(r.reagents or {}) do
                local _, src, by = buyPrice(rg[1])
                tip:AddLine(("%d x %s  %s"):format(rg[2], R.Items.Text(rg[1]), buyText(rg[1], rg[2]) or "no price"), 0.8, 0.8, 0.8)
                if src == "vendor" then tip:AddLine("    from " .. tostring(by) .. ", cheaper than the auction house", 0.5, 0.8, 0.5) end
            end
        end
    end)
    ui.levelList:SetEmptyText("Open a profession window and Exchange works out which of your recipes raise your skill for the least gold.")
    ui.levelList.frame:SetPoint("TOPLEFT", 0, -40)
    ui.levelList.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 0)
end

local function buildBags(page)
    local h = W.Header(page, "Bag sweep")
    h:SetPoint("TOPLEFT", 0, -2)
    local sweep = W.Button(page, "Sweep bags", 110, function() ui.swept = true; refreshPage() end)
    sweep:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 2)
    ui.bagTotals = W.Label(page, "", "GameFontHighlightSmall")
    ui.bagTotals:SetPoint("TOPLEFT", 0, -22)
    ui.bagTotals:SetPoint("RIGHT", page, "RIGHT", -6, 0)
    ui.bagList = W.List(page, 24, function(row)
        row.tag = W.Label(row, "", "GameFontNormalSmall")
        row.tag:SetPoint("LEFT", 6, 0)
        row.tag:SetWidth(70)
        row.text = W.Label(row, "")
        row.text:SetPoint("LEFT", 80, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.text:SetWordWrap(false)
    end, function(row, it)
        local l = LABELS[it.label]
        row.tag:SetText(l[2] .. l[1] .. "|r")
        row.text:SetText(("%s%s  %s%s|r"):format(it.link, it.count > 1 and (" x" .. it.count) or "", C.dim, it.why or ""))
        row.link = it.link
    end)
    ui.bagList:SetEmptyText("Press Sweep bags: every item is labeled keep, sell on the auction house, or vendor, using RUIN prices.")
    ui.bagList.frame:SetPoint("TOPLEFT", 0, -40)
    ui.bagList.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 0)
end

-- For the Treasury and History tabs (Treasury.lua, History.lua).
ns.ExchangeInternals = { canICraft = function(name) return canICraft(name) end, refresh = function() refreshPage() end }

local TAB_NAMES = { "Search", "Watch", "Requests", "History", "Leveling", "Bags", "Treasury" }
local TAB = {}
for i, n in ipairs(TAB_NAMES) do TAB[n] = i end

local function buildPage(panel)
    ui.panel = panel
    ui.tabs = W.SubTabs(panel, TAB_NAMES, function() refreshPage() end)
    buildSearch(ui.tabs.pages[TAB.Search])
    ns.Watch.Build(ui.tabs.pages[TAB.Watch])
    buildRequests(ui.tabs.pages[TAB.Requests])
    ns.History.Build(ui.tabs.pages[TAB.History])
    buildLeveling(ui.tabs.pages[TAB.Leveling])
    buildBags(ui.tabs.pages[TAB.Bags])
    ns.Treasury.Build(ui.tabs.pages[TAB.Treasury])
    refreshPage = function()
        if not ui.panel:IsVisible() then return end
        local reqs = openRequests()
        local mineToMake = 0
        for _, r in ipairs(reqs) do if canICraft(r.name) and r.by ~= UnitName("player") then mineToMake = mineToMake + 1 end end
        ui.tabs:SetLabel(TAB.Requests, mineToMake > 0 and ("Requests " .. C.good .. "(" .. mineToMake .. ")|r")
            or (#reqs > 0 and ("Requests (" .. #reqs .. ")") or "Requests"))
        local waiting = ns.History.WaitingForMe()
        ui.tabs:SetLabel(TAB.History, waiting > 0 and ("History " .. C.gold .. "(" .. waiting .. ")|r") or "History")
        local tab = ui.tabs.selected
        if tab == TAB.Search then
            local prices, crafters, newest = 0, 0, 0
            for _, p in pairs(db.prices) do prices = prices + 1; newest = math.max(newest, p.t or 0) end
            for _ in pairs(db.crafters) do crafters = crafters + 1 end
            ui.summary:SetWordWrap(false)
            -- in Crafters mode the line shares its row with Offline crafters / Add my recipes,
            -- so it keeps just the counts there (the empty list says how to add yours)
            ui.summary:SetText(("%s%d prices known (newest %s) · %d crafters listed.%s|r")
                :format(C.dim, prices, newest > 0 and W.Ago(GetServerTime() - newest) or "never", crafters,
                    ui.mode == "Crafters" and "" or " Browse the auction house or open a profession to add yours."))
            ui.profBtn:SetShown(ui.mode == "Crafters")
            ui.heads:SetShown(ui.mode == "Crafters")
            local need = (ui.mode == "Crafters") and M.NeedsScan() or {}
            ui.addMine:SetShown(#need > 0)
            ui.offlineCheck:SetShown(ui.mode == "Crafters")
            if ui.offlineCheck.Refresh then ui.offlineCheck:Refresh() end
            ui.summary:SetPoint("RIGHT", ui.tabs.pages[TAB.Search], "RIGHT", ui.mode == "Crafters" and -405 or (#need > 0 and -150 or -6), 0)
            ui.profBtn:Refresh()
            ui.list:SetItems(search())
            if ui.mode ~= "Crafters" and ui.unnamed then
                ui.summary:SetText(("%s%d prices known · %d item names still loading, so a search may miss them for a moment.|r")
                    :format(C.dim, prices, ui.unnamed))
            end
        elseif tab == TAB.Watch then
            ns.Watch.Refresh()
        elseif tab == TAB.Requests then
            ui.reqList:SetItems(reqs)
        elseif tab == TAB.Leveling then
            if not ui.prof or not db.plans[ui.prof] then ui.prof = next(db.plans) end
            local plan = ui.prof and db.plans[ui.prof]
            ui.profPick:SetText(ui.prof or "No profession yet")
            ui.levelInfo:SetText(plan and (C.dim .. ("%s %s/%s"):format(ui.prof, tostring(plan.skill or "?"), tostring(plan.max or "?")) .. "|r") or "")
            local list = {}
            for i, r in ipairs(M.LivePlan(plan and (plan.prof and plan or setmetatable({ prof = ui.prof }, { __index = plan }))) or {}) do if i <= 25 then list[i] = r end end
            ui.levelList:SetItems(list)
        elseif tab == TAB.Treasury then
            ns.Treasury.Refresh()
        elseif tab == TAB.History then
            ns.History.Refresh()
        elseif tab == TAB.Bags then
            if ui.swept then
                local items, ah, vendor = M:SweepBags()
                ui.bagTotals:SetText(("%sAuction house: about %s   ·   Vendor: %s   ·   %d items|r"):format(C.dim,
                    C.gold .. W.Money(ah) .. C.dim, C.white .. W.Money(vendor) .. C.dim, #items))
                ui.bagList:SetItems(items)
            else
                ui.bagTotals:SetText("")
                ui.bagList:SetItems({})
            end
        end
    end
    panel:SetScript("OnShow", function() refreshPage() end)
    ui.tabs:Select(1)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
function M:OnEnable()
    if type(RUIN_ExchangeDB) ~= "table" then RUIN_ExchangeDB = {} end
    db = RUIN_ExchangeDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    M.PruneHistory()

    self:Listen("PRICES", "OnPrices")
    self:Listen("VPRICES", "OnVendorPrices")
    self:Listen("RSKILL", "OnRecipeSkill")
    self:Listen("CRAFTS", "OnCrafts")
    self:Listen("REQ", "OnRequest")
    self:Listen("REQDEL", "OnRequestDelete")
    self:Listen("ASK", "OnAsk")
    self:AddTab("Exchange", buildPage)
    ns.Treasury.Init(self, db)
    ns.Watch.Init(self, db)
    if ns.Crates then ns.Crates.Init(self, db) end
    ns.History.Init(self, db, ns.ExchangeInternals)
    -- Guild > People "By profession" (RUIN Core 0.4.3)
    if R.AddProfessionSource then
        R:AddProfessionSource(function(name)
            local short = R.Util.ShortName(name or ""):lower()
            for _, e in pairs(db.crafters) do
                if e.name and R.Util.ShortName(e.name):lower() == short then
                    local out = {}
                    for prof, list in pairs(e.profs or {}) do
                        if #list > 0 then out[#out + 1] = prof end
                    end
                    table.sort(out)
                    return #out > 0 and out or nil
                end
            end
        end)
    end
    R:Subscribe("CHANNELS_CHANGED", function()
        C_Timer.After(9, function() if R:IsConnected() then self:Send("ASK", {}, "ORG"); M.ShareMine(false) end end)
    end)

    self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE", onClassicList)
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", onBrowse)
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", onBrowse)
    self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", onCommodity)
    self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", onItemSearch)
    self:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE", readReplicate)
    self:RegisterEvent("AUCTION_HOUSE_SHOW", onAuctionShow)
    self:RegisterEvent("TRAINER_SHOW", function() C_Timer.After(0, M.HookTrainer) end)
    self:RegisterEvent("TRAINER_UPDATE", function() C_Timer.After(0, M.PaintTrainer) end)
    self:RegisterEvent("MERCHANT_SHOW", function() db.lastVendor = UnitName and UnitName("npc"); C_Timer.After(0.5, M.ScanMerchant) end)
    self:RegisterEvent("MERCHANT_UPDATE", function() C_Timer.After(0.2, M.ScanMerchant) end)
    self:RegisterEvent("MERCHANT_CLOSED", shareVendor)
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", function() scanning, ahOpen = nil, nil; shareSession() end)
    R:Subscribe("ITEMS_LOADED", function() refreshPage() end)
    self:RegisterEvent("TRADE_SKILL_SHOW", function() craftWindow = false; scheduleCraftScan(); C_Timer.After(0, M.HookRecipeCosts) end)
    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", function() craftWindow = false; scheduleCraftScan(); C_Timer.After(0, M.RepaintRecipeCosts) end)
    self:RegisterEvent("CRAFT_SHOW", function() craftWindow = true; scheduleCraftScan(); C_Timer.After(0, M.HookRecipeCosts) end)
    self:RegisterEvent("CRAFT_UPDATE", function() craftWindow = true; scheduleCraftScan(); C_Timer.After(0, M.RepaintRecipeCosts) end)
    self:RegisterEvent("CRAFT_CLOSE", function() craftWindow = false end)
    -- at login: share what we know, and ask for the professions that need a look
    C_Timer.After(20, function()
        M.ShareMine(false)
        local need = M.NeedsScan()
        if #need > 0 then
            local names = {}
            for _, p in ipairs(need) do names[#names + 1] = p.name end
            self:Print(("To list your recipes in RUIN, open %s once (or click them in the Add your recipes window)."):format(table.concat(names, ", ")))
            M.RefreshScanPrompt(true)
        end
    end)
    self:RegisterEvent("SKILL_LINES_CHANGED", function() M.RefreshScanPrompt(false); refreshPage() end)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function() if ui.swept and ui.tabs and ui.tabs.selected == TAB.Bags then refreshPage() end end)
end

function RUIN_Exchange_Open() M:OpenTab() end
BINDING_HEADER_RUIN_EXCHANGE = "RUIN Exchange"
BINDING_NAME_RUIN_EXCHANGE_OPEN = "Open Exchange"
_G["BINDING_NAME_CLICK RUIN_ExchangeCrateFill:LeftButton"] = "Fill Waylaid Crate"

-- /ex [search] | /ex request <item> [-- note] | /ex bags | treasury | history | scan | autoscan | costs
SLASH_RUINEXCHANGE1 = "/ex"
SLASH_RUINEXCHANGE2 = "/exchange"
SlashCmdList.RUINEXCHANGE = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    if cmd:lower() == "request" then
        local item, note = rest:match("^(.-)%s*%-%-%s*(.*)$")
        M:Request(item or rest, note)
        return
    end
    if cmd:lower() == "scan" then
        M.FullScan(false)
        return
    elseif cmd:lower() == "crates" and ns.Crates then
        ns.Crates.Report()
        return
    elseif cmd:lower() == "tipdebug" then
        M.tipDebug = true
        M:Print("Hover a recipe or a Waylaid Crate: Exchange prints what it reads from the tooltip (once).")
        return
    elseif cmd:lower() == "costs" then
        db.pointCosts = db.pointCosts == false
        M:Print("Price per Point in the profession window: " .. (db.pointCosts and "on" or "off"))
        M.RepaintRecipeCosts()
        return
    elseif cmd:lower() == "overtime" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 5 then db.overtime = math.floor(n) end
        M:Print(("Working Overtime: %d/5 (+%d%% skill-up chance on yellow and green recipes)."):format(tonumber(db.overtime) or 0, (tonumber(db.overtime) or 0) * 4))
        M.RepaintRecipeCosts()
        return
    elseif cmd:lower() == "watch" then
        ns.Watch.Slash(rest)
        return
    elseif cmd:lower() == "autoscan" then
        db.autoScan = db.autoScan == false
        M:Print("Full scan when you open the auction house: " .. (db.autoScan and "on" or "off"))
        return
    end
    M:OpenTab()
    if cmd:lower() == "bags" then
        ui.swept = true
        ui.tabs:Select(TAB.Bags)
    elseif cmd:lower() == "treasury" then
        ui.tabs:Select(TAB.Treasury)
    elseif cmd:lower() == "history" then
        ui.tabs:Select(TAB.History)
    elseif msg ~= "" then
        ui.query, ui.mode = msg, "Crafters"
        ui.tabs:Select(TAB.Search)
        if ui.searchBox then ui.searchBox:SetText(msg) end
    end
    refreshPage()
end
