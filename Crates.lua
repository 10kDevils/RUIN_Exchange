-- RUIN Exchange: Waylaid Crates on the auction house
-- A "Waylaid Crates" category in the auction house's Buy list, after
-- Miscellaneous, with Apprentice, Journeyman, Expert and Artisan under it and
-- each crate under the tier its name carries. Clicking a crate lists every
-- reagent that fills it in the auction house's results and opens a card
-- beside it with what each bundle costs, a mark by the cheapest (any one
-- bundle fills the crate); clicking a bundle searches for just that item.
-- Crates you hover are learned, so a new kind shows up too. Where the game's
-- category list can't take it, a dropdown under the Buy page does the same.
local ADDON, ns = ...
local R = RUIN_API
if not R then return end
local W = R.Widgets
local C = W.COLORS

local Crates = {}
ns.Crates = Crates
local M, db
local ui = {}
local fillCategory

local PREFIX = "Waylaid Crate: "
local CHEAPEST = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t "
Crates.TIERS = { "Apprentice", "Journeyman", "Expert", "Artisan" }

-- the tier a crate's name carries ("Earthly Artisan Herbs" -> Artisan), or nil
function Crates.Tier(short)
    for _, t in ipairs(Crates.TIERS) do
        if type(short) == "string" and short:find("%f[%a]" .. t .. "%f[%A]") then return t end
    end
end
local ROW_H, CARD_W, PAD, TOP = 24, 290, 14, 62   -- TOP: where the first row starts

-- the crates known before any is hovered: short name -> { { n, name }, ... }
Crates.KNOWN = {
    ["Artisan Curiosities"] = { { 20, "Dream Dust" }, { 4, "Greater Nether Essence" }, { 6, "Small Brilliant Shard" }, { 2, "Large Brilliant Shard" } },
    ["Artisan Ore"] = { { 10, "Truesilver Ore" }, { 20, "Thorium Ore" }, { 20, "Dark Iron Ore" } },
    ["Flowering Artisan Herbs"] = { { 20, "Dreamfoil" }, { 20, "Mountain Silversage" }, { 20, "Plaguebloom" }, { 20, "Icecap" } },
}

local function learned() db.crates = db.crates or {}; return db.crates end

-- every crate, learned ones over the known ones, by name
function Crates.All()
    local out = {}
    for k, v in pairs(Crates.KNOWN) do out[k] = v end
    if db then for k, v in pairs(learned()) do out[k] = v end end
    return out
end

function Crates.Names()
    local names = {}
    for k in pairs(Crates.All()) do names[#names + 1] = k end
    table.sort(names)
    return names
end

-- remember a crate seen in a tooltip (title "Waylaid Crate: X", bundles from M.CrateBundles)
function Crates.Learn(title, bundles)
    if not (db and type(title) == "string" and bundles and #bundles > 0) then return end
    local short = title:match("^Waylaid Crate:%s*(.-)%s*$")
    if not short or short == "" then return end
    local list = {}
    for i, b in ipairs(bundles) do list[i] = { b.n, b.name } end
    local old = learned()[short] or Crates.KNOWN[short]
    local same = old and #old == #list
    if same then
        for i, e in ipairs(list) do
            if old[i][1] ~= e[1] or old[i][2] ~= e[2] then same = false; break end
        end
    end
    if same then return end
    learned()[short] = list
    if ui.dropdown then ui.dropdown.Refresh() end
    if ui.category then fillCategory(); Crates.RefreshList() end
end

local function unitPrice(name)
    local id = M.CrateItem and M.CrateItem(name)
    if not id then return nil end
    return (M.ExpectedPrice and M.ExpectedPrice(id)) or (db.prices and db.prices[id] and db.prices[id].p)
end

-- one crate's bundles with prices: { { n, name, unit, total } ... }, and the
-- cheapest priced bundle (any one bundle fills the crate)
function Crates.Costs(short)
    local list = Crates.All()[short]
    if not list then return nil end
    local out, best = {}, nil
    for i, e in ipairs(list) do
        local unit = unitPrice(e[2])
        out[i] = { n = e[1], name = e[2], unit = unit, total = unit and unit * e[1] }
        if out[i].total and (not best or out[i].total < best.total) then best = out[i] end
    end
    return out, best
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------
-- Searches the auction house for one item, as if typed into its search box
-- (in quotes, so only that item comes back). The game's own throttle applies;
-- RUIN's price scan sees it as your search and waits.
function Crates.Search(name)
    if type(name) ~= "string" or name == "" then return false end
    local text = '"' .. name .. '"'
    local f = rawget(_G, "AuctionHouseFrame")
    local sb = type(f) == "table" and f.SearchBar
    local box = type(sb) == "table" and sb.SearchBox
    if type(box) == "table" and box.SetText and sb.StartSearch then
        sb.SearchBox:SetText(text)
        local ok = pcall(sb.StartSearch, sb)
        if ok then Crates.lastSearch = name; return true end
    end
    local AH = rawget(_G, "C_AuctionHouse")
    if AH and AH.SendBrowseQuery then
        local ok = pcall(AH.SendBrowseQuery, { searchString = text, sorts = {}, filters = {} })
        if ok then Crates.lastSearch = name; return true end
    end
    return false
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------
local function onBuyPage()
    local f = rawget(_G, "AuctionHouseFrame")
    if not (f and f.IsShown and f:IsShown()) then return false end
    local modes = rawget(_G, "AuctionHouseFrameDisplayMode")
    if f.GetDisplayMode and modes and modes.Buy then return f:GetDisplayMode() == modes.Buy end
    return true
end

local function drawCard()
    local card = ui.card
    if not card then return end
    local short = db.crateSel
    local costs, best = Crates.Costs(short or "")
    if not costs then card:Hide(); return end
    card.title:SetText(C.gold .. PREFIX .. "|r" .. C.white .. short .. "|r")
    for i, c in ipairs(costs) do
        local row = ui.rows[i]
        if not row then
            row = W.MenuRow(card, CARD_W - 2 * (PAD - 6))
            row.price = W.Label(row, "", "GameFontHighlightSmall")
            row.price:SetPoint("RIGHT", -8, 0)
            row:SetScript("OnClick", function(self) Crates.Search(self.item); drawCard() end)
            ui.rows[i] = row
        end
        row.item = c.name
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD - 6, -TOP - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", -(PAD - 6), -TOP - (i - 1) * ROW_H)
        row:SetHeight(ROW_H - 2)
        row:SetText(((best and best == c) and CHEAPEST or "") .. ("%d %s"):format(c.n, c.name))
        row.price:SetText(c.total and W.Money(c.total) or (C.dim .. "none yet|r"))
        if Crates.lastSearch == c.name then row:LockHighlight() else row:UnlockHighlight() end
        row:Show()
    end
    for i = #costs + 1, #ui.rows do ui.rows[i]:Hide() end
    local y = -TOP - #costs * ROW_H - 6
    card.rule2:ClearAllPoints()
    card.rule2:SetPoint("TOPLEFT", PAD, y)
    card.rule2:SetPoint("TOPRIGHT", -PAD, y)
    card.total:ClearAllPoints()
    card.total:SetPoint("TOPLEFT", PAD, y - 10)
    card.totalPrice:ClearAllPoints()
    card.totalPrice:SetPoint("TOPRIGHT", -PAD, y - 10)
    if best then
        card.total:SetText(C.white .. "Cheapest fill:|r " .. best.n .. " " .. best.name)
        card.totalPrice:SetText(W.Money(best.total))
    else
        card.total:SetText(C.dim .. "No prices yet|r")
        card.totalPrice:SetText("")
    end
    card:SetHeight(TOP + #costs * ROW_H + 6 + 10 + 14 + PAD)
    card:Show()
end
Crates.Draw = drawCard

-- open a crate: its card, and a search for its cheapest bundle (the first if none is priced)
-- Lists every reagent that fills the crate in the auction house's results
-- (one search for all of them). False when the game can't search by a list.
function Crates.ListAll(short)
    local AH = rawget(_G, "C_AuctionHouse")
    local list = Crates.All()[short]
    if not (list and AH and AH.SearchForItemKeys and AH.MakeItemKey) then return false end
    local keys = {}
    for _, e in ipairs(list) do
        local id = M.CrateItem and M.CrateItem(e[2])
        local ok, key = pcall(AH.MakeItemKey, id or 0)
        if id and ok and key then keys[#keys + 1] = key end
    end
    if #keys == 0 then return false end
    -- a crate name left in the search box would narrow the next search of yours
    local f = rawget(_G, "AuctionHouseFrame")
    local sb = type(f) == "table" and f.SearchBar
    local box = type(sb) == "table" and sb.SearchBox
    if Crates.lastSearch and type(box) == "table" and box.GetText and box:GetText() == ('"' .. Crates.lastSearch .. '"') then box:SetText("") end
    local sortOrder = rawget(_G, "Enum") and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
    local ok = pcall(AH.SearchForItemKeys, keys, { { sortOrder = sortOrder, reverseSort = false } })
    if ok then Crates.lastSearch = nil end
    return ok
end

-- open a crate: its card, and every reagent that fills it in the results
-- (or, if the game can't list several, a search for the cheapest)
function Crates.Pick(short)
    if not Crates.All()[short] then return end
    db.crateSel = short
    if not Crates.ListAll(short) then
        local _, best = Crates.Costs(short)
        local first = Crates.All()[short][1]
        local item = (best and best.name) or (first and first[2])
        if item then Crates.Search(item) end
    end
    if ui.dropdown then ui.dropdown.Refresh() end
    drawCard()
end

---------------------------------------------------------------------------
-- The category in the auction house's Buy list
---------------------------------------------------------------------------
local function newCategory(name)
    local mixin = rawget(_G, "AuctionCategoryMixin")
    local c = (mixin and CreateFromMixins and CreateFromMixins(mixin)) or {}
    c.name, c.filters, c.ruinCrates = name, {}, true
    c.HasFlag = c.HasFlag or function(self, flag) return self.flags and self.flags[flag] end
    c.SetFlag = c.SetFlag or function(self, flag) self.flags = self.flags or {}; self.flags[flag] = true end
    return c
end

-- (re)fill the category: a crate per sub-category, its bundles under it
function fillCategory()
    local top = ui.category
    if not top then return end
    -- the game's list goes three deep: Waylaid Crates > tier > crate
    top.subCategories = {}
    local byTier = {}
    for _, t in ipairs(Crates.TIERS) do
        byTier[t] = newCategory(t)
        byTier[t].subCategories = {}
        top.subCategories[#top.subCategories + 1] = byTier[t]
    end
    for _, short in ipairs(Crates.Names()) do
        local t = Crates.Tier(short) or "Other"
        if not byTier[t] then
            byTier[t] = newCategory(t)
            byTier[t].subCategories = {}
            top.subCategories[#top.subCategories + 1] = byTier[t]
        end
        local leaf = newCategory(short)
        leaf.ruinCrate = short
        byTier[t].subCategories[#byTier[t].subCategories + 1] = leaf
    end
end

local function categoryIndex()
    local cats = rawget(_G, "AuctionCategories")
    if type(cats) ~= "table" then return nil end
    for i, c in ipairs(cats) do if c == ui.category then return i end end
end

local function selection(list)
    if type(list) ~= "table" then return nil end
    if type(list.GetSelectedCategory) == "function" then
        local ok, a, b, c = pcall(list.GetSelectedCategory, list)
        if ok and a then return a, b, c end
    end
    return list.selectedCategoryIndex, list.selectedSubCategoryIndex, list.selectedSubSubCategoryIndex
end

-- after any click in the category list: act on ours, tidy up after leaving it
local function onCategoryClick()
    local f = rawget(_G, "AuctionHouseFrame")
    local list = f and f.CategoriesList
    local a, b, c = selection(list)
    local mine = a and a == categoryIndex()
    if mine then
        local tier = b and ui.category.subCategories[b]
        local crate = tier and c and tier.subCategories[c]
        if crate then
            C_Timer.After(0, function() Crates.Pick(crate.ruinCrate) end)
        elseif ui.card then
            ui.card:Hide()
            db.crateSel = nil
        end
    else
        if ui.card then ui.card:Hide() end
        db.crateSel = nil
        -- our quoted name left in the search box would narrow the game's own category search
        local sb = type(f) == "table" and f.SearchBar
        local box = type(sb) == "table" and sb.SearchBox
        if Crates.lastSearch and type(box) == "table" and box.GetText and box:GetText() == ('"' .. Crates.lastSearch .. '"') then
            box:SetText("")
            Crates.lastSearch = nil
            if sb.StartSearch then C_Timer.After(0, function() pcall(sb.StartSearch, sb) end) end
        end
    end
end
Crates.OnCategoryClick = onCategoryClick

-- adds the category after Miscellaneous (or last); false when the game's list isn't there
function Crates.AddCategory()
    if ui.category then return true end
    local cats = rawget(_G, "AuctionCategories")
    local f = rawget(_G, "AuctionHouseFrame")
    local list = f and f.CategoriesList
    if type(cats) ~= "table" or #cats == 0 or type(list) ~= "table" then return false end
    local hooked = false
    for _, fn in ipairs({ "OnFilterClicked", "SetSelectedCategory" }) do
        if type(list[fn]) == "function" and hooksecurefunc then
            hooked = pcall(hooksecurefunc, list, fn, function() C_Timer.After(0, onCategoryClick) end) or hooked
            if hooked then break end
        end
    end
    if not hooked and type(rawget(_G, "AuctionFrameFilter_OnClick")) == "function" and hooksecurefunc then
        hooked = pcall(hooksecurefunc, "AuctionFrameFilter_OnClick", function() C_Timer.After(0, onCategoryClick) end)
    end
    if not hooked then return false end
    ui.category = newCategory("Waylaid Crates")
    fillCategory()
    local at = #cats + 1
    for i, c in ipairs(cats) do
        if c.name == "Miscellaneous" or c.name == rawget(_G, "AUCTION_CATEGORY_MISCELLANEOUS") then at = i + 1 end
    end
    table.insert(cats, at, ui.category)
    Crates.RefreshList()
    return true
end

function Crates.RefreshList()
    local f = rawget(_G, "AuctionHouseFrame")
    local list = f and f.CategoriesList
    if type(list) ~= "table" then return end
    for _, fn in ipairs({ "UpdateCategories", "Refresh" }) do
        if type(list[fn]) == "function" then pcall(list[fn], list); return end
    end
end

---------------------------------------------------------------------------
-- Building it, the fallback dropdown, and what's shown where
---------------------------------------------------------------------------
-- shown on the Buy page only
function Crates.Update()
    local buy = onBuyPage()
    if ui.dropdown then
        if buy then ui.dropdown:Show() else ui.dropdown:Hide() end
    end
    if buy and db.crateSel then drawCard() elseif ui.card then ui.card:Hide() end
end

function Crates.Build()
    local f = rawget(_G, "AuctionHouseFrame")
    if not f then return false end
    if not ui.card then
        local card = W.Card(f)
        card:SetSize(CARD_W, 120)
        card:SetPoint("TOPLEFT", f, "TOPRIGHT", 6, -2)
        card.title = W.Label(card, "", "GameFontNormal")
        card.title:SetPoint("TOPLEFT", PAD, -PAD)
        card.title:SetPoint("RIGHT", -PAD, 0)
        card.title:SetJustifyH("LEFT")
        card.hint = W.Label(card, C.dim .. "Any one bundle fills it. Click one to search.|r", "GameFontDisableSmall")
        card.hint:SetPoint("TOPLEFT", PAD, -PAD - 20)
        local function rule()
            local t = card:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(1, 1, 1, 0.1)
            t:SetHeight(1)
            return t
        end
        card.rule1 = rule()
        card.rule1:SetPoint("TOPLEFT", PAD, -TOP + 8)
        card.rule1:SetPoint("TOPRIGHT", -PAD, -TOP + 8)
        card.rule2 = rule()
        card.total = W.Label(card, "", "GameFontHighlightSmall")
        card.totalPrice = W.Label(card, "", "GameFontHighlightSmall")
        card:Hide()
        ui.card, ui.rows = card, {}
        if hooksecurefunc and f.SetDisplayMode then pcall(hooksecurefunc, f, "SetDisplayMode", Crates.Update) end
        if f.HookScript then f:HookScript("OnHide", function() if ui.card then ui.card:Hide() end end) end
    end
    if ui.category or ui.dropdown then return true end
    if Crates.AddCategory() then return true end
    local dd = W.Dropdown(f, 210, Crates.Names, function() return db.crateSel end, Crates.Pick)
    dd.Refresh = function()
        local v = db.crateSel
        dd:SetText(v and Crates.All()[v] and (PREFIX .. v) or "Waylaid Crates")
    end
    dd:ClearAllPoints()
    dd:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
    W.MarkChoice(dd, "Pick a Waylaid Crate to find what fills it.")
    ui.dropdown = dd
    dd.Refresh()
    return true
end

local function onEvent(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        Crates.Build()
        Crates.Update()
    elseif (event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED"
            or event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") and ui.card and ui.card:IsShown() then
        C_Timer.After(0.2, drawCard)   -- after Exchange reads the new prices
    end
end

function Crates.Init(module, savedDb)
    M, db = module, savedDb
    -- crates hovered are learned (M.CrateBundles reads them from the tooltip)
    local read = M.CrateBundles
    if read then
        M.CrateBundles = function(tooltip, ...)
            local bundles = read(tooltip, ...)
            if bundles then
                local tname = tooltip and tooltip.GetName and tooltip:GetName()
                local first = tname and _G[tname .. "TextLeft1"]
                local title = first and first.GetText and first:GetText()
                if title then pcall(Crates.Learn, (title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), bundles) end
            end
            return bundles
        end
    end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", onEvent)
    Crates.ui = ui
    M.Crates = Crates
end
