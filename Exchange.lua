-- RUIN Exchange
-- Prices you see while browsing the auction house are shared with RUIN
-- when you close it, so everyone has fresh prices without scanning; a daily
-- history gives each price a 7-day trend. Opening a profession window
-- shares your recipes ("who in RUIN can craft this") and works out the
-- cheapest next skill-up from RUIN prices. Members post craft requests, and
-- a bag sweep labels every item keep, sell or vendor.
local ADDON, ns = ...
local R = RUIN_API
if not R or (R.apiLevel or 1) < 9 then
    print("|cff54b7d9[RUIN]|r Exchange needs a newer RUIN Core (0.3.16 or later).")
    return
end
local W = R.Widgets
local C = W.COLORS

local M = R:RegisterModule("Exchange", { version = "0.4.0" })

local DEFAULTS = { prices = {}, crafters = {}, tooltip = true, history = {}, requests = {}, plans = {} }
local PRICE_BATCH = 40
local HISTORY_DAYS = 14
local REQUEST_HOURS = 24
local SELL_MARGIN = 1.3         -- the AH must beat the vendor by this much to be worth it
local SKILLUP_CHANCE = { [0] = 1, [1] = 0.75, [2] = 0.25 }        -- orange, yellow, green
local DIFFICULTY_NAME = { [0] = "|cffff8040orange|r", [1] = "|cffffff00yellow|r", [2] = "|cff40c040green|r" }
local CLASSIC_DIFFICULTY = { optimal = 0, medium = 1, easy = 2, trivial = 3 }

local db
local session = {}       -- itemID -> lowest unit price seen during this AH visit
local ui = { mode = "Crafters", query = "", prof = "All professions" }
local refreshPage = function() end

local function dayKey(t) return math.floor((t or GetServerTime()) / 86400) end

local function itemInfo(id)
    if not GetItemInfo then return nil end
    local name, link, quality, _, _, class, _, _, equip, _, sell = GetItemInfo(id)
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return name, link, quality, sell, class, equip
end

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

local function notePrice(id, unit)
    id, unit = tonumber(id), tonumber(unit)
    if not id or not unit or unit <= 0 then return end
    unit = math.floor(unit)
    if not session[id] or unit < session[id] then session[id] = unit end
    local now = GetServerTime()
    db.prices[id] = { p = session[id], t = now, by = UnitName("player") }
    noteHistory(id, session[id], now)
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

-- Classic-style auction list
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
        if r.itemKey then notePrice(r.itemKey.itemID, r.minPrice) end
    end
end

local function shareSession()
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
    if count > 0 then M:Print(("Shared %d prices with RUIN."):format(count)) end
    session = {}
end

function M:OnPrices(d, sender)
    if type(d.l) ~= "table" or type(d.t) ~= "number" then return end
    for i = 1, #d.l - 1, 2 do
        local id, p = tonumber(d.l[i]), tonumber(d.l[i + 1])
        if id and p then
            local cur = db.prices[id]
            if not cur or (cur.t or 0) < d.t then db.prices[id] = { p = p, t = d.t, by = sender } end
            noteHistory(id, p, d.t)
        end
    end
end

local function price(id) return db.prices[id] and db.prices[id].p end

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
    for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
        local r = slot.reagents and slot.reagents[1]
        if r and r.itemID and (slot.required ~= false) then out[#out + 1] = { r.itemID, slot.quantityRequired or 1 } end
    end
    return out
end

local function reagentsClassic(index)
    local out = {}
    if not (GetTradeSkillNumReagents and GetTradeSkillReagentItemLink) then return out end
    for j = 1, GetTradeSkillNumReagents(index) or 0 do
        local link = GetTradeSkillReagentItemLink(index, j)
        local _, _, count = GetTradeSkillReagentInfo(index, j)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then out[#out + 1] = { id, count or 1 } end
    end
    return out
end

-- Cost of one craft from RUIN prices; nil parts are reagents nobody has priced.
local function craftCost(reagents)
    local cost, missing = 0, {}
    for _, r in ipairs(reagents) do
        local p = price(r[1])
        if p then cost = cost + p * r[2] else missing[#missing + 1] = r[1] end
    end
    return cost, missing
end

-- Rank recipes that can still raise your skill by expected cost per point.
local function planLeveling(prof, skill, maxSkill, recipes)
    local list = {}
    for _, r in ipairs(recipes) do
        local chance = SKILLUP_CHANCE[r.diff]
        if chance then
            local cost, missing = craftCost(r.reagents)
            list[#list + 1] = { name = r.name, diff = r.diff, cost = cost, missing = #missing, perPoint = cost / chance,
                                reagents = r.reagents }
        end
    end
    table.sort(list, function(a, b)
        if (a.missing == 0) ~= (b.missing == 0) then return a.missing == 0 end
        if a.perPoint ~= b.perPoint then return a.perPoint < b.perPoint end
        return a.diff < b.diff
    end)
    db.plans[prof] = { skill = skill, max = maxSkill, list = list, t = GetServerTime() }
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
                local iid, q = madeItem(GetCraftItemLink and GetCraftItemLink(i))
                if iid then made[name] = { iid, q } end
            end
        end
    elseif C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
        prof = info and info.professionName
        skill, maxSkill = info and info.skillLevel, info and info.maxSkillLevel
        for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
            local r = C_TradeSkillUI.GetRecipeInfo(id)
            if r and r.learned and r.name then
                list[#list + 1] = r.name
                local iid, q = madeItem(recipeLinkModern(id))
                if iid then made[r.name] = { iid, q } end
                if r.relativeDifficulty and r.relativeDifficulty < 3 then
                    recipes[#recipes + 1] = { name = r.name, diff = r.relativeDifficulty, reagents = reagentsModern(id) }
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
                if iid then made[name] = { iid, q } end
                local diff = CLASSIC_DIFFICULTY[kind]
                if diff and diff < 3 then recipes[#recipes + 1] = { name = name, diff = diff, reagents = reagentsClassic(i) } end
            end
        end
    end
    if not prof or prof == "" or #list == 0 then return end
    closeScannedWindow()
    if #recipes > 0 then planLeveling(prof, skill, maxSkill, recipes) end
    table.sort(list)
    local me = R:GetPlayer()
    -- the made item's id and quality travel beside the names (i, q), so
    -- older RUIN versions still read the list of names
    local ids, qs = {}, {}
    for n, name in ipairs(list) do
        local m = made[name]
        ids[n], qs[n] = m and m[1] or 0, m and m[2] or -1
    end
    local e = db.crafters[me.guid] or { name = me.name, guild = me.guild, profs = {} }
    e.profs[prof] = list
    e.made = e.made or {}
    e.made[prof] = { i = ids, q = qs }
    e.skill = e.skill or {}
    e.skill[prof] = tonumber(skill)
    e.t = GetServerTime()
    db.crafters[me.guid] = e
    refreshPage()
    if M.RefreshScanPrompt then M.RefreshScanPrompt() end
    local sig = #list .. ":" .. table.concat(list, "|"):len()
    if lastCraftSig[prof] == sig then return end
    lastCraftSig[prof] = sig
    M:Send("CRAFTS", { g = me.guid, gu = me.guild, p = prof, l = list, i = ids, q = qs }, "ORG", nil, R.PRIORITY.BULK)
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
    for prof, list in pairs(e.profs) do
        local m = e.made and e.made[prof]
        M:Send("CRAFTS", { g = me.guid, gu = me.guild, p = prof, l = list, i = m and m.i, q = m and m.q }, "ORG", nil, R.PRIORITY.BULK)
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
    local e = db.crafters[d.g] or { profs = {} }
    e.name, e.guild, e.t = sender, d.gu, GetServerTime()
    e.profs[d.p] = d.l
    if type(d.i) == "table" then
        local ids, qs = {}, {}
        for n = 1, #d.l do
            ids[n] = tonumber(d.i[n]) or 0
            qs[n] = type(d.q) == "table" and tonumber(d.q[n]) or -1
        end
        e.made = e.made or {}
        e.made[d.p] = { i = ids, q = qs }
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

function M:OnRequestDelete(d)
    if type(d.id) == "string" and db.requests[d.id] then db.requests[d.id] = nil; refreshPage() end
end

function M:OnAsk()
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
}

local function bagItems()
    local items = {}
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if not numSlots then return items end
    for bag = 0, 4 do
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
    if it.bound then
        return (it.sell > 0) and "vendor" or "keep", "soulbound"
    end
    if p and p > it.sell * SELL_MARGIN then return "ah", "RUIN price " .. W.Money(p) end
    if p then return "vendor", "vendor pays about the same as the AH" end
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
    local order = { ah = 1, vendor = 2, check = 3, keep = 4 }
    table.sort(out, function(a, b)
        if a.label ~= b.label then return order[a.label] < order[b.label] end
        return (a.name or "") < (b.name or "")
    end)
    return out, ahTotal, vendorTotal
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function priceLines(link)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    if not id then return nil end
    local p = db.prices[id]
    local _, _, _, vendor = itemInfo(id)
    local lines = {}
    if p then
        lines[1] = ("%sRUIN price: %s|r %s%s|r"):format(C.gold, W.Money(p.p), C.dim, W.Ago(GetServerTime() - (p.t or 0)))
        local avg, pct, days = M:Trend(id)
        if avg and days >= 2 then
            lines[#lines + 1] = ("%sRUIN 7-day: avg %s  %s|r"):format(C.dim, W.Money(avg), trendText(pct))
        end
        if vendor and vendor > 0 then
            lines[#lines + 1] = (p.p > vendor * SELL_MARGIN) and (C.good .. "Exchange: sell on the auction house|r")
                or (C.dim .. "Exchange: vendor it (" .. W.Money(vendor) .. ")|r")
        end
    end
    return lines
end

local function onTooltip(tooltip)
    if not db or not db.tooltip then return end
    local link
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        link = select(2, TooltipUtil.GetDisplayedItem(tooltip))
    elseif tooltip.GetItem then
        link = select(2, tooltip:GetItem())
    end
    if not link or (issecretvalue and issecretvalue(link)) then return end
    local ok, lines = pcall(priceLines, link)
    if ok and lines then for _, l in ipairs(lines) do tooltip:AddLine(l) end end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onTooltip)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", onTooltip)
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local function whisper(name)
    local send = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
    if send then send(name) end
end

local function search()
    local q = ui.query:lower()
    local items = {}
    if ui.mode == "Crafters" then
        -- by profession, then recipe, then crafter; each row shows the item's quality
        local byProf = {}
        for _, e in pairs(db.crafters) do
            for prof, list in pairs(e.profs or {}) do
                if not ui.findProf or ui.findProf == "All professions" or ui.findProf == prof then
                    local made = e.made and e.made[prof]
                    for n, recipe in ipairs(list) do
                        if q == "" or recipe:lower():find(q, 1, true) then
                            local iid = made and tonumber(made.i[n]) or 0
                            local quality = made and tonumber(made.q[n]) or -1
                            byProf[prof] = byProf[prof] or {}
                            table.insert(byProf[prof], { recipe = recipe, who = e.name, guild = e.guild,
                                id = iid > 0 and iid or nil, quality = quality >= 0 and quality or nil })
                        end
                    end
                end
            end
        end
        local profs = {}
        for prof in pairs(byProf) do profs[#profs + 1] = prof end
        table.sort(profs)
        for _, prof in ipairs(profs) do
            local rows = byProf[prof]
            table.sort(rows, function(a, b)
                if a.recipe ~= b.recipe then return a.recipe < b.recipe end
                return tostring(a.who) < tostring(b.who)
            end)
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
        return items
    else
        local now = GetServerTime()
        for id, p in pairs(db.prices) do
            local name, link = R.Items.Info(id)
            local label = R.Items.Text(id)
            if q == "" or (name and name:lower():find(q, 1, true)) then
                local _, pct = M:Trend(id)
                items[#items + 1] = { text = ("%s  %s%s|r  %s  %s%s|r"):format(label, C.gold, W.Money(p.p), trendText(pct), C.dim,
                    W.Ago(now - (p.t or 0))), t = p.t or 0, link = link }
                if #items >= 200 then break end
            end
        end
        table.sort(items, function(a, b) return a.t > b.t end)
    end
    return items
end

local function buildSearch(page)
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
    for _, h in ipairs({ { "Profession / recipe", 4 }, { "Crafter", 330 }, { "Quality", 536 } }) do
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
        row.quality = W.Label(row, "", "GameFontHighlightSmall")
        row.quality:SetPoint("LEFT", 536, 0)
        row.quality:SetWidth(90)
        row.quality:SetWordWrap(false)
        row.btn = W.Button(row, "Whisper", 70)
        row.btn:SetPoint("RIGHT", 0, 0)
    end, function(row, item)
        row.btn:SetShown(item.who ~= nil)
        row.btn:SetScript("OnClick", function() if item.who then whisper(item.who) end end)
        row.link = item.link
        if item.header then                        -- a profession heading
            row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.text:SetText(C.gold .. item.header .. "|r  " .. C.dim .. item.count .. (item.count == 1 and " recipe" or " recipes") .. "|r")
            row.crafter:SetText(""); row.quality:SetText("")
        elseif item.recipe then                    -- recipe, crafter, quality
            row.text:SetPoint("RIGHT", row, "LEFT", 324, 0)
            row.text:SetText("   " .. (item.id and R.Items.Text(item.id, item.recipe, item.quality) or (C.white .. item.recipe .. "|r")))
            row.crafter:SetText(W.ClassName(item.who) .. C.dim .. ((item.guild and item.guild ~= "") and ("  " .. item.guild) or "") .. "|r")
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
    ui.profPick = W.Button(page, "", 160, function()
        local names = {}
        for prof in pairs(db.plans) do names[#names + 1] = prof end
        table.sort(names)
        if #names == 0 then return end
        local idx = 1
        for i, n in ipairs(names) do if n == ui.prof then idx = i end end
        ui.prof = names[idx % #names + 1]
        refreshPage()
    end)
    W.MarkChoice(ui.profPick)
    ui.profPick:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 2)
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
            or (C.gold .. W.Money(r.perPoint) .. "|r" .. C.dim .. " per point|r")
        row.text:SetText(("%s%d.|r %s%s|r  %s  %s"):format(C.dim, i, C.white, r.name, DIFFICULTY_NAME[r.diff] or "", cost))
        row.tip = function(tip)
            tip:AddLine(r.name, 1, 0.82, 0)
            tip:AddLine(("One craft: %s from RUIN prices"):format(W.Money(r.cost)), 1, 1, 1)
            for _, rg in ipairs(r.reagents or {}) do
                local p = price(rg[1])
                tip:AddLine(("%d x %s  %s"):format(rg[2], R.Items.Text(rg[1]), p and W.Money(p * rg[2]) or "no price"), 0.8, 0.8, 0.8)
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

local function buildPage(panel)
    ui.panel = panel
    ui.tabs = W.SubTabs(panel, { "Search", "Requests", "Leveling", "Bags" }, function() refreshPage() end)
    buildSearch(ui.tabs.pages[1])
    buildRequests(ui.tabs.pages[2])
    buildLeveling(ui.tabs.pages[3])
    buildBags(ui.tabs.pages[4])

    refreshPage = function()
        if not ui.panel:IsVisible() then return end
        local reqs = openRequests()
        local mineToMake = 0
        for _, r in ipairs(reqs) do if canICraft(r.name) and r.by ~= UnitName("player") then mineToMake = mineToMake + 1 end end
        ui.tabs:SetLabel(2, mineToMake > 0 and ("Requests " .. C.good .. "(" .. mineToMake .. ")|r")
            or (#reqs > 0 and ("Requests (" .. #reqs .. ")") or "Requests"))
        local tab = ui.tabs.selected
        if tab == 1 then
            local prices, crafters, newest = 0, 0, 0
            for _, p in pairs(db.prices) do prices = prices + 1; newest = math.max(newest, p.t or 0) end
            for _ in pairs(db.crafters) do crafters = crafters + 1 end
            ui.summary:SetWordWrap(false)
            ui.summary:SetText(("%s%d prices known (newest %s) · %d crafters listed. Browse the auction house or open a profession to add yours.|r")
                :format(C.dim, prices, newest > 0 and W.Ago(GetServerTime() - newest) or "never", crafters))
            ui.profBtn:SetShown(ui.mode == "Crafters")
            ui.heads:SetShown(ui.mode == "Crafters")
            local need = (ui.mode == "Crafters") and M.NeedsScan() or {}
            ui.addMine:SetShown(#need > 0)
            ui.summary:SetPoint("RIGHT", ui.tabs.pages[1], "RIGHT", #need > 0 and -150 or -6, 0)
            ui.profBtn:Refresh()
            ui.list:SetItems(search())
        elseif tab == 2 then
            ui.reqList:SetItems(reqs)
        elseif tab == 3 then
            if not ui.prof or not db.plans[ui.prof] then ui.prof = next(db.plans) end
            local plan = ui.prof and db.plans[ui.prof]
            ui.profPick:SetText(ui.prof or "No profession yet")
            ui.levelInfo:SetText(plan and (C.dim .. ("%s %s/%s · worked out %s from RUIN prices. Orange always gives a point, yellow usually, green sometimes.")
                :format(ui.prof, tostring(plan.skill or "?"), tostring(plan.max or "?"), W.Ago(GetServerTime() - plan.t)) .. "|r") or "")
            local list = {}
            for i, r in ipairs(plan and plan.list or {}) do if i <= 25 then list[i] = r end end
            ui.levelList:SetItems(list)
        elseif tab == 4 then
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

    self:Listen("PRICES", "OnPrices")
    self:Listen("CRAFTS", "OnCrafts")
    self:Listen("REQ", "OnRequest")
    self:Listen("REQDEL", "OnRequestDelete")
    self:Listen("ASK", "OnAsk")
    self:AddTab("Exchange", buildPage)
    R:Subscribe("CHANNELS_CHANGED", function()
        C_Timer.After(9, function() if R:IsConnected() then self:Send("ASK", {}, "ORG"); M.ShareMine(false) end end)
    end)

    self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE", onClassicList)
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", onBrowse)
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", onBrowse)
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", shareSession)
    R:Subscribe("ITEMS_LOADED", function() refreshPage() end)
    self:RegisterEvent("TRADE_SKILL_SHOW", function() craftWindow = false; scheduleCraftScan() end)
    self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", function() craftWindow = false; scheduleCraftScan() end)
    self:RegisterEvent("CRAFT_SHOW", function() craftWindow = true; scheduleCraftScan() end)
    self:RegisterEvent("CRAFT_UPDATE", function() craftWindow = true; scheduleCraftScan() end)
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
    self:RegisterEvent("BAG_UPDATE_DELAYED", function() if ui.swept and ui.tabs and ui.tabs.selected == 4 then refreshPage() end end)
end

function RUIN_Exchange_Open() M:OpenTab() end
BINDING_HEADER_RUIN_EXCHANGE = "RUIN Exchange"
BINDING_NAME_RUIN_EXCHANGE_OPEN = "Open Exchange"

-- /ex [search] | /ex request <item> [-- note] | /ex bags
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
    M:OpenTab()
    if cmd:lower() == "bags" then
        ui.swept = true
        ui.tabs:Select(4)
    elseif msg ~= "" then
        ui.query, ui.mode = msg, "Crafters"
        ui.tabs:Select(1)
        if ui.searchBox then ui.searchBox:SetText(msg) end
    end
    refreshPage()
end
