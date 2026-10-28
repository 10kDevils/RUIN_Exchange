-- RUIN Exchange: the treasury book
-- The guild's treasurer (the guild master, or whoever holds the Treasurer
-- office on Guild > People) keeps a book of the gold members give: gold
-- traded or mailed to the treasurer is written down by itself, and the
-- treasurer adds anything else by hand (a deposit, an expense). The book is
-- shared with the guild, so everyone sees who gave what, this week's
-- totals, and the guild bank's gold as last seen. Mail from the auction
-- house isn't counted.
local ADDON, ns = ...
local R = RUIN_API
if not R or (R.apiLevel or 1) < 9 then return end
local W = R.Widgets
local C = W.COLORS

local Treasury = {}
ns.Treasury = Treasury

local WEEK = 7 * 86400
local KEEP = 180 * 86400
local MAX_ENTRIES = 600

local M, db
local ui = { view = "Book" }
local trade = {}

local function now() return GetServerTime() end
local function short(n) return R.Util.ShortName(n or "?") end

local function book()
    db.treasury = type(db.treasury) == "table" and db.treasury or {}
    local guild = R:GetPlayer().guild or "-"
    db.treasury[guild] = type(db.treasury[guild]) == "table" and db.treasury[guild] or {}
    return db.treasury[guild]
end

-- Are you the keeper of your guild's book?
function Treasury.IsKeeper()
    local p = R:GetPlayer()
    if not p.guild then return false end
    if R.HasOffice and R:HasOffice(p.name, "Treasurer") then return true end
    if not GetGuildInfo then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex == 0
end

local function newId() return tostring(R:GetPlayerGUID() or "x"):sub(-4) .. now() % 1000000 .. math.random(10, 99) end

local function clean(e)
    if type(e) ~= "table" or type(e.id) ~= "string" or not tonumber(e.c) then return nil end
    local via = ({ trade = true, mail = true, hand = true })[e.via] and e.via or "hand"
    return { id = e.id:sub(1, 24), c = math.floor(tonumber(e.c)), who = tostring(e.who or "?"):sub(1, 48), via = via,
             note = tostring(e.note or ""):gsub("|", "/"):sub(1, 80), t = tonumber(e.t) or now(), by = tostring(e.by or "?"):sub(1, 48),
             del = e.del and true or nil }
end

local function add(e, share)
    local b = book()
    b[e.id] = e
    -- keep the book a sensible size
    local n, oldest, oldestId = 0, math.huge, nil
    for id, x in pairs(b) do
        n = n + 1
        if now() - (x.t or 0) > KEEP then b[id] = nil elseif x.t < oldest then oldest, oldestId = x.t, id end
    end
    if n > MAX_ENTRIES and oldestId then b[oldestId] = nil end
    if share then M:Send("TBOOK", e, "GUILD", nil, R.PRIORITY.NORMAL) end
    Treasury.Refresh()
end

-- copper > 0: gold in; copper < 0: gold out.
function Treasury.Record(copper, who, via, note)
    if not Treasury.IsKeeper() then return false, "Only your guild's treasurer (or guild master) keeps the book." end
    copper = math.floor(tonumber(copper) or 0)
    if copper == 0 then return false, "How much?" end
    local e = clean({ id = newId(), c = copper, who = who, via = via, note = note, t = now(), by = R:GetPlayer().name })
    add(e, true)
    return true, e
end

function Treasury.Remove(id)
    if not Treasury.IsKeeper() then return false end
    local e = book()[id]
    if not e then return false end
    e.del, e.t = true, now()
    add(e, true)
    return true
end

-- Is this guildmate the keeper of your guild's book (guild master, or the
-- Treasurer office of your guild)? Checked by who sent the entry.
local function senderIsKeeper(sender)
    if not R.GuildRankOf then return true end              -- an older RUIN Core can't tell
    local rank = R:GuildRankOf(sender)
    if rank == nil then return false end                   -- not in your guild
    if rank == 0 then return true end
    for _, o in ipairs(R.GetOffices and R:GetOffices() or {}) do
        if type(o) == "table" and type(o.title) == "string" and o.title:lower():find("treasurer", 1, true)
            and R:SameName(o.name, sender) then return true end
    end
    return false
end

local function onBook(_, d, sender, scope)
    if scope ~= "GUILD" or not senderIsKeeper(sender) then return end
    local e = clean(d)
    if not e then return end
    if R.SaneTime and not R:SaneTime(e.t) then return end
    local cur = book()[e.id]
    if cur and (cur.t or 0) >= e.t and not (e.del and not cur.del) then return end
    e.by = sender
    add(e, false)
end

---------------------------------------------------------------------------
-- Gold given by trade and mail (only the keeper's RUIN writes these down)
---------------------------------------------------------------------------
local function tradeShow()
    trade = { who = UnitName("NPC") or UnitName("target"), inC = 0, outC = 0, items = {}, theirs = {} }
end

local function tradeUpdate()
    if not trade.who then return end
    trade.inC = tonumber(GetTargetTradeMoney and GetTargetTradeMoney()) or 0
    trade.outC = tonumber(GetPlayerTradeMoney and GetPlayerTradeMoney()) or 0
    trade.items, trade.enchant = {}, nil
    for i = 1, 6 do
        local link = GetTradePlayerItemLink and GetTradePlayerItemLink(i)
        if link then trade.items[#trade.items + 1] = link end
    end
    -- "Will not be traded": an enchant you put on their item
    if GetTradeTargetItemInfo then
        local name, _, _, _, _, enchantment = GetTradeTargetItemInfo(7)
        if name and type(enchantment) == "string" and enchantment ~= "" then trade.enchant = { item = name, enchant = enchantment } end
    end
end

local function tradeDone()
    local t = trade
    trade = {}
    if not t.who or (issecretvalue and issecretvalue(t.who)) then return end
    if Treasury.IsKeeper() then
        if t.inC > 0 then Treasury.Record(t.inC, t.who, "trade") end
        if t.outC > 0 then Treasury.Record(-t.outC, t.who, "trade") end
    end
    if ns.History then ns.History.AfterTrade(t) end
end

local function onInfo(_, msgType, msg)
    local done = (msg == ERR_TRADE_COMPLETE) or (msgType == (LE_GAME_ERR_TRADE_COMPLETE or -1))
    if done then tradeDone() end
end

local function fromAuctionHouse(sender, subject)
    if not sender then return true end
    if sender == (AUCTION_HOUSE_MAIL_SENDER or "Auction House") or sender:find("Auction", 1, true) then return true end
    for _, g in ipairs({ AUCTION_SOLD_MAIL_SUBJECT, AUCTION_OUTBID_MAIL_SUBJECT, AUCTION_EXPIRED_MAIL_SUBJECT, AUCTION_REMOVED_MAIL_SUBJECT }) do
        if type(g) == "string" and subject and subject:find((g:gsub("%%s", "")), 1, true) then return true end
    end
    return false
end

local lastMail = {}
local function mailTaken(index)
    if not (Treasury.IsKeeper() and GetInboxHeaderInfo) then return end
    local _, _, sender, subject, money, _, _, _, _, _, _, _, isGM = GetInboxHeaderInfo(index)
    money = tonumber(money) or 0
    if money <= 0 or isGM or fromAuctionHouse(sender, subject) then return end
    -- taking the gold and looting the whole mail can both report the same mail
    local key = tostring(sender) .. "|" .. tostring(subject) .. "|" .. money
    if lastMail[key] and GetTime() - lastMail[key] < 5 then return end
    lastMail[key] = GetTime()
    Treasury.Record(money, sender, "mail", subject)
end

---------------------------------------------------------------------------
-- Totals
---------------------------------------------------------------------------
function Treasury.Entries()
    local out = {}
    for _, e in pairs(book()) do if not e.del then out[#out + 1] = e end end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end

-- { weekIn, weekOut, allIn, allOut, givers = { { name, total, week, count } } }
function Treasury.Totals()
    local t = { weekIn = 0, weekOut = 0, allIn = 0, allOut = 0, givers = {} }
    local by = {}
    for _, e in ipairs(Treasury.Entries()) do
        local week = now() - e.t <= WEEK
        if e.c > 0 then
            t.allIn = t.allIn + e.c
            if week then t.weekIn = t.weekIn + e.c end
            local k = short(e.who):lower()
            local g = by[k] or { name = e.who, total = 0, week = 0, count = 0 }
            g.total, g.count = g.total + e.c, g.count + 1
            if week then g.week = g.week + e.c end
            by[k] = g
        else
            t.allOut = t.allOut - e.c
            if week then t.weekOut = t.weekOut - e.c end
        end
    end
    for _, g in pairs(by) do t.givers[#t.givers + 1] = g end
    table.sort(t.givers, function(a, b) return a.total > b.total end)
    return t
end

---------------------------------------------------------------------------
-- The Treasury tab
---------------------------------------------------------------------------
function Treasury.Build(page)
    ui.page = page
    ui.viewBtn = W.Dropdown(page, 150, { "Book", "Givers" }, function() return ui.view end, function(v) ui.view = v; Treasury.Refresh() end, "Show: ")
    ui.viewBtn:SetPoint("TOPLEFT", 0, 0)
    ui.totals = W.Label(page, "", "GameFontHighlightSmall")
    ui.totals:SetPoint("LEFT", ui.viewBtn, "RIGHT", 10, 0)
    ui.totals:SetWidth(470)
    ui.totals:SetJustifyH("LEFT")
    ui.totals:SetWordWrap(false)
    ui.addBtn = W.Button(page, "Add entry", 100, function()
        R:ShowText("Add to the treasury book", "Gold in or out, who, and a note: 50, Grimlock, raid repairs  (-20 for gold paid out)", "", function(text)
            local amount, rest = text:match("^%s*([%-%d%.]+)%s*,?%s*(.*)$")
            local who, note = (rest or ""):match("^([^,]*),?%s*(.*)$")
            local ok, err = Treasury.Record((tonumber(amount) or 0) * 10000, R.Util.Trim(who or ""), "hand", note)
            if not ok then M:Print(err) end
        end)
    end)
    ui.addBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    ui.sub = W.Label(page, "", "GameFontHighlightSmall")
    ui.sub:SetPoint("TOPLEFT", 2, -30)
    ui.sub:SetPoint("RIGHT", page, "RIGHT", -4, 0)
    ui.sub:SetWordWrap(false)
    ui.list = W.List(page, 22, function(row)
        row.a = W.Label(row, "")
        row.a:SetPoint("LEFT", 6, 0); row.a:SetWidth(150); row.a:SetJustifyH("RIGHT")
        row.b = W.Label(row, "", "GameFontHighlightSmall")
        row.b:SetPoint("LEFT", 170, 0); row.b:SetPoint("RIGHT", row, "RIGHT", -40, 0); row.b:SetWordWrap(false)
        row.del = W.Button(row, "X", 24)
        row.del:SetPoint("RIGHT", -2, 0)
    end, function(row, e)
        row.del:Hide()
        if e.giver then
            local g = e.giver
            row.a:SetText(C.gold .. W.Money(g.total) .. "|r")
            row.b:SetText(("%s  %s%d gift%s  ·  this week %s|r"):format(W.ClassName(g.name), C.dim, g.count, g.count == 1 and "" or "s", W.Money(g.week)))
        else
            local x = e.entry
            row.a:SetText((x.c > 0 and C.good or C.bad) .. (x.c > 0 and "+" or "-") .. W.Money(math.abs(x.c)) .. "|r")
            row.b:SetText(("%s  %s%s  ·  %s%s|r"):format(W.ClassName(x.who), C.dim, x.via, W.Ago(math.max(60, now() - x.t)),
                x.note ~= "" and ("  ·  " .. x.note) or ""))
            row.del:SetScript("OnClick", function() Treasury.Remove(x.id) end)
            row.del:SetShown(Treasury.IsKeeper())
        end
    end)
    ui.list.frame:SetPoint("TOPLEFT", 0, -50)
    ui.list.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 0)
    page:SetScript("OnShow", Treasury.Refresh)
end

function Treasury.Refresh()
    if not (ui.page and ui.page:IsVisible()) then return end
    local t = Treasury.Totals()
    ui.totals:SetText(("This week %s+%s|r %s-%s|r  ·  all %s+%s|r %s-%s|r"):format(C.good, W.Money(t.weekIn), C.bad, W.Money(t.weekOut),
        C.good, W.Money(t.allIn), C.bad, W.Money(t.allOut)))
    ui.addBtn:SetShown(Treasury.IsKeeper())
    local bank = R.GetGuildBank and R:GetGuildBank()
    local p = R:GetPlayer()
    ui.sub:SetText(C.dim .. (not p.guild and "You're not in a guild." or
        ((Treasury.IsKeeper() and "You keep this book: gold traded or mailed to you is written down by itself." or
          "Kept by your guild's treasurer (the Treasurer office on Guild > People, or the guild master).")
        .. (bank and bank.money and ("  Guild bank: " .. W.Money(bank.money) .. ", seen " .. W.Ago(math.max(60, now() - (bank.t or now()))) .. ".") or ""))) .. "|r")
    local items = {}
    if ui.view == "Givers" then
        for _, g in ipairs(t.givers) do items[#items + 1] = { giver = g } end
        ui.list:SetEmptyText("No gifts written down yet.")
    else
        for _, e in ipairs(Treasury.Entries()) do items[#items + 1] = { entry = e } end
        ui.list:SetEmptyText("The book is empty.")
    end
    ui.list:SetItems(items)
end

-- A member who connected asks (Exchange's ASK); the keeper shares the last weeks.
function Treasury.Share()
    if not Treasury.IsKeeper() then return end
    C_Timer.After(4 + math.random() * 6, function()
        local n = 0
        for _, e in pairs(book()) do
            if now() - e.t <= 28 * 86400 and n < 120 then n = n + 1; M:Send("TBOOK", e, "GUILD", nil, R.PRIORITY.BULK) end
        end
    end)
end

function Treasury.Init(module, edb)
    M, db = module, edb
    M:Listen("TBOOK", onBook)
    M:RegisterEvent("TRADE_SHOW", tradeShow)
    M:RegisterEvent("TRADE_MONEY_CHANGED", tradeUpdate)
    M:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED", tradeUpdate)
    M:RegisterEvent("TRADE_TARGET_ITEM_CHANGED", tradeUpdate)
    M:RegisterEvent("TRADE_ACCEPT_UPDATE", tradeUpdate)
    M:RegisterEvent("UI_INFO_MESSAGE", onInfo)
    if hooksecurefunc then
        if TakeInboxMoney then pcall(hooksecurefunc, "TakeInboxMoney", mailTaken) end
        if AutoLootMailItem then pcall(hooksecurefunc, "AutoLootMailItem", mailTaken) end
    end
end
