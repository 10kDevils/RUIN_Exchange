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

---------------------------------------------------------------------------
-- Filling crates from your bags
---------------------------------------------------------------------------
-- The game only lets a click of yours use an item, so filling is a button:
-- each click uses the next crate you can fill, and when the crate's choice
-- window opens Exchange picks the bundle worth the least on the auction house
-- among those you carry enough of. Keep clicking (or press its key) until it
-- reads Nothing to fill.
local FILL_WAIT = 15            -- seconds a crate's choice window is waited for

local function strip(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function slotItem(bag, slot)
    local CC = rawget(_G, "C_Container")
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        if info then return info.itemID or (info.hyperlink and tonumber(info.hyperlink:match("item:(%d+)"))), info.hyperlink, info.stackCount end
    elseif GetContainerItemInfo then
        local _, count, _, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
        return id or (link and tonumber(link:match("item:(%d+)"))), link, count
    end
end

local scanTip
-- what a crate in your bags asks for, read from its tooltip when Exchange hasn't met it
local function learnFromBag(bag, slot)
    if not (CreateFrame and M.CrateBundles) then return end
    if not scanTip then
        local ok, t = pcall(CreateFrame, "GameTooltip", "RUIN_CrateScanTip", UIParent, "GameTooltipTemplate")
        if not ok or not t then return end
        scanTip = t
    end
    if not scanTip.SetBagItem then return end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    pcall(scanTip.SetBagItem, scanTip, bag, slot)
    pcall(M.CrateBundles, scanTip)
    scanTip:Hide()
end

-- what your bags hold (the reagent bag too), by item and by name; read once
-- per look (the game's own count can leave the reagent bag out)
local held, heldAt
local function countBags()
    local now = GetTime()
    if held and heldAt == now then return held end
    held, heldAt = { byId = {}, byName = {} }, now
    local CC = rawget(_G, "C_Container")
    local numSlots = (CC and CC.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
    if not numSlots then return held end
    for bag = 0, 5 do   -- 5: the reagent bag
        for slot = 1, numSlots(bag) or 0 do
            local id, link, count = slotItem(bag, slot)
            if id then
                held.byId[id] = (held.byId[id] or 0) + (count or 1)
                local name = GetItemInfo and GetItemInfo(id) or (link and link:match("%[(.-)%]"))
                if name then held.byName[name] = (held.byName[name] or 0) + (count or 1) end
            end
        end
    end
    return held
end

local function have(name)
    local h = countBags()
    local id = M.CrateItem and M.CrateItem(name)
    local mine = math.max(id and h.byId[id] or 0, h.byName[name] or 0)
    local game = GetItemCount and ((id and GetItemCount(id)) or GetItemCount(name)) or 0
    return math.max(mine, tonumber(game) or 0)
end

-- the bundle to fill a crate with: of those you carry enough of, the one worth
-- the least on the auction house (unpriced ones last). nil when none fits.
function Crates.FillChoice(short)
    local list = Crates.All()[short]
    if not list then return nil end
    local pick, pickCost
    for _, e in ipairs(list) do
        if have(e[2]) >= e[1] then
            local unit = unitPrice(e[2])
            local cost = unit and unit * e[1] or math.huge
            if not pick or cost < pickCost then pick, pickCost = { n = e[1], name = e[2], cost = unit and cost }, cost end
        end
    end
    return pick
end

-- the crates in your bags you can fill now: { { bag, slot, short } ... },
-- and every unfilled crate in them
function Crates.Fillable()
    local out, all = {}, {}
    local CC = rawget(_G, "C_Container")
    local numSlots = (CC and CC.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
    if not numSlots then return out end
    for bag = 0, 5 do   -- 5: the reagent bag
        for slot = 1, numSlots(bag) or 0 do
            local id, link = slotItem(bag, slot)
            local name = id and GetItemInfo and GetItemInfo(id) or (link and link:match("%[(.-)%]"))
            local short = type(name) == "string" and name:match("^Waylaid Crate:%s*(.-)%s*$")
            if short then
                if not Crates.All()[short] then learnFromBag(bag, slot) end
                local e = { bag = bag, slot = slot, short = short }
                all[#all + 1] = e
                if Crates.FillChoice(short) then out[#out + 1] = e end
            end
        end
    end
    return out, all
end

local fillButtons = {}

local function fillText(n) return n > 0 and ("Fill crates (%d)"):format(n) or "Nothing to fill" end

local bagHooks = {}

-- the game's bag windows, then the bag addons people use
local BAG_FRAMES = { "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3", "ContainerFrame4",
    "ContainerFrame5", "ElvUI_ContainerFrame", "BagnonInventoryFrame1", "BagnonInventory1", "AdiBagsContainer1",
    "ARKINV_Frame1", "Baganator_SingleViewBackpackViewFrame", "Baganator_CategoryViewBackpackViewFrame",
    "BetterBagsBagBackpack", "CombuctorFrame1", "OneBagFrame" }

-- bag addons that name their windows after a skin or a view
-- (Baganator: "Baganator_CategoryViewBackpackViewFrame" .. skin), found once by name
local ADDON_BAGS = { "^Baganator_.*Backpack.*Frame", "^Bagnon.*Inventory", "^BetterBags.*Backpack", "^AdiBags.*Container" }
local found, lastLook = {}, -999

-- only right after you open your bags (a look through every global is too dear to do often)
local function lookForAddonBags()
    local now = GetTime()
    if not Crates.bagsOpened or now - lastLook < 2 then return end
    lastLook, Crates.bagsOpened = now, nil
    for name, v in pairs(_G) do
        if type(name) == "string" and type(v) == "table" and not found[name] and name:find("Bag", 1, true) then
            for _, pat in ipairs(ADDON_BAGS) do
                if name:find(pat) and type(v.IsVisible) == "function" then found[name] = true; break end
            end
        end
    end
end

local function visible(n)
    local f = rawget(_G, n)
    return type(f) == "table" and type(f.IsVisible) == "function" and f:IsVisible() and f or nil
end

-- the open bag window the button sits beside, and its name
local function openBags()
    for _, n in ipairs(BAG_FRAMES) do
        local f = visible(n)
        if f then return f, n end
    end
    for n in pairs(found) do
        local f = visible(n)
        if f then return f, n end
    end
    lookForAddonBags()
    for n in pairs(found) do
        local f = visible(n)
        if f then return f, n end
    end
end
Crates.OpenBags = openBags

-- beside your bags while they're open and a crate can be filled (the
-- button can't move or hide in combat, so that waits for combat to end)
function Crates.PlaceBagButton(n)
    local b = ui.bagButton
    if not b or (InCombatLockdown and InCombatLockdown()) then return end
    local bags, bagName = openBags()
    local _, all = Crates.Fillable()
    if bags and bagName and not bagHooks[bagName] and bags.HookScript then
        bagHooks[bagName] = true
        bags:HookScript("OnHide", function() C_Timer.After(0, function() Crates.PlaceBagButton() end) end)
        bags:HookScript("OnShow", function() C_Timer.After(0, Crates.RefreshFill) end)
    end
    if bags and #all > 0 then
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", bags, "TOPLEFT", -4, -6)
        b:Show()
    else
        b:Hide()
    end
end

-- what /exchange crates prints: where the button would go and each crate in your bags
function Crates.Report()
    Crates.bagsOpened = true
    local bags, name = openBags()
    M:Print("Bags open: " .. (name or "none Exchange knows (open your bags and try again)"))
    local _, all = Crates.Fillable()
    if #all == 0 then
        M:Print("No unfilled Waylaid Crate in your bags.")
        -- anything crate-like, by its full name, to see what the game calls it
        local CC = rawget(_G, "C_Container")
        local numSlots = (CC and CC.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
        for bag = 0, 5 do   -- 5: the reagent bag
            for slot = 1, (numSlots and numSlots(bag)) or 0 do
                local id, link = slotItem(bag, slot)
                local name = id and GetItemInfo and GetItemInfo(id) or (link and link:match("%[(.-)%]"))
                if type(name) == "string" and (name:find("Crate") or name:find("Waylaid")) then
                    M:Print(("  bag %d slot %d: [%s] (item %s)"):format(bag, slot, name, tostring(id)))
                end
            end
        end
    end
    for _, e in ipairs(all) do
        local c = Crates.FillChoice(e.short)
        local parts = {}
        for _, b in ipairs(Crates.All()[e.short] or {}) do parts[#parts + 1] = ("%d %s (have %d)"):format(b[1], b[2], have(b[2])) end
        M:Print(("%s%s in bag %d slot %d: %s"):format(PREFIX, e.short, e.bag, e.slot,
            c and ("fill with " .. c.n .. " " .. c.name) or (#parts > 0 and ("not enough of: " .. table.concat(parts, ", ")) or "its bundles aren't known yet (hover it)")))
    end
    local b = ui.bagButton
    M:Print("Button: " .. (b and (b:IsShown() and "shown" or "hidden") or "not made") .. (InCombatLockdown and InCombatLockdown() and " (in combat)" or ""))
end

function Crates.RefreshFill()
    local n = #Crates.Fillable()
    for _, b in ipairs(fillButtons) do
        if b.SetText then b:SetText(fillText(n)) end
        if b.SetEnabled then b:SetEnabled(n > 0) end
    end
    Crates.PlaceBagButton(n)
    return n
end

function Crates.HookBags()
    if not ui.bagButton then
        ui.bagButton = Crates.FillButton(UIParent, 130)
        if ui.bagButton.SetFrameStrata then ui.bagButton:SetFrameStrata("HIGH") end
        ui.bagButton:Hide()
    end
    for _, n in ipairs(BAG_FRAMES) do
        local f = rawget(_G, n)
        if type(f) == "table" and f.HookScript and not bagHooks[n] then
            bagHooks[n] = true
            f:HookScript("OnShow", function() C_Timer.After(0, Crates.RefreshFill) end)
            f:HookScript("OnHide", function() C_Timer.After(0, function() Crates.PlaceBagButton() end) end)
        end
    end
    -- the game's bag keys, for windows made later or not hooked above
    if hooksecurefunc and not bagHooks.keys then
        bagHooks.keys = true
        for _, fn in ipairs({ "ToggleBackpack", "OpenBackpack", "ToggleAllBags", "OpenAllBags", "CloseAllBags", "ToggleBag", "CloseBackpack" }) do
            if type(rawget(_G, fn)) == "function" then
                pcall(hooksecurefunc, fn, function()
                    Crates.bagsOpened = true
                    C_Timer.After(0.1, function() Crates.HookBags(); Crates.RefreshFill() end)
                end)
            end
        end
    end
end

-- before the click goes to the game: aim the button at the next crate
local function aim(s)
    if InCombatLockdown and InCombatLockdown() then return end
    local now = GetTime()
    if Crates.fillingAt and now - Crates.fillingAt < 0.5 then return end   -- already aimed for this press
    local next1 = Crates.Fillable()[1]
    if not next1 then
        s:SetAttribute("type", nil)
        M:Print("No Waylaid Crate in your bags can be filled with what you carry.")
        return
    end
    local choice = Crates.FillChoice(next1.short)
    s:SetAttribute("type", "item")
    s:SetAttribute("item", next1.bag .. " " .. next1.slot)
    Crates.filling = { short = next1.short, choice = choice, bag = next1.bag, slot = next1.slot, at = now }
    if choice then M:Print(("Filling %s%s with %d %s."):format(PREFIX, next1.short, choice.n, choice.name)) end
    Crates.fillingAt = now
    -- a crate still unfilled after a while: its window wasn't one Exchange could answer
    C_Timer.After(4, function()
        local f = Crates.filling
        if not f or f.at ~= now then return end
        local id, link = slotItem(f.bag, f.slot)
        local name = id and GetItemInfo and GetItemInfo(id) or (link and link:match("%[(.-)%]"))
        if name == PREFIX .. f.short and f.choice and not f.answered then
            M:Print(("Pick %d %s in the crate's window (the cheapest you carry)."):format(f.choice.n, f.choice.name))
        end
    end)
end

local function makeSecure(parent, name)
    local ok, s = pcall(CreateFrame, "Button", name, parent, "SecureActionButtonTemplate")
    if not ok or not s then return nil end
    -- one use per press: the game acts on the key's down or up as its "cast on key down" option says
    if s.RegisterForClicks then
        local down = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
        s:RegisterForClicks(down and "AnyDown" or "AnyUp")
    end
    s:SetScript("PreClick", aim)
    s:SetScript("PostClick", function() C_Timer.After(1, Crates.RefreshFill) end)
    return s
end

-- a Fill crates button: RUIN's look with the game's secure button laid over it
function Crates.FillButton(parent, width)
    local b = W.Button(parent, fillText(0), width or 130)
    local s = makeSecure(b)
    if s then
        s:SetAllPoints(b)
        s:SetFrameLevel((b:GetFrameLevel() or 1) + 5)
        s:SetScript("OnEnter", function()
            if b.LockHighlight then b:LockHighlight() end
            if GameTooltip then
                W.TipOwner(s, GameTooltip)
                GameTooltip:SetText("Fill Waylaid Crates")
                GameTooltip:AddLine("Each click fills the next crate in your bags with the bundle worth the least on the auction house among those you carry. Also on a key: Key Bindings > RUIN Exchange.", 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        s:SetScript("OnLeave", function() if b.UnlockHighlight then b:UnlockHighlight() end; if GameTooltip then GameTooltip:Hide() end end)
        b.secure = s
    end
    fillButtons[#fillButtons + 1] = b
    return b
end

-- the crate's choice window: answer it with the chosen bundle
local function optionText(o)
    local parts = { o.header, o.description, o.name, o.text, o.title }
    for _, bt in ipairs(o.buttons or {}) do parts[#parts + 1] = bt.text end
    local out = {}
    for _, p in ipairs(parts) do if type(p) == "string" then out[#out + 1] = strip(p) end end
    return table.concat(out, " "):lower()
end

-- options: { { text = "...", pick = function() end } ... }; true when one was picked
function Crates.Answer(options)
    local f = Crates.filling
    if not (f and f.choice and GetTime() - f.at < FILL_WAIT) or f.answered then return false end
    local best, bestCost
    for _, o in ipairs(options) do
        for _, e in ipairs(Crates.All()[f.short] or {}) do
            if o.text:find(e[2]:lower(), 1, true) and have(e[2]) >= e[1] then
                local unit = unitPrice(e[2])
                local cost = unit and unit * e[1] or math.huge
                if e[2] == f.choice.name then cost = -1 end           -- the one chosen when the button was pressed
                if not best or cost < bestCost then best, bestCost = o, cost end
            end
        end
    end
    if not best then
        if M.tipDebug or #options > 0 then
            local seen = {}
            for i, o in ipairs(options) do seen[i] = o.text end
            M:Print("crate window options: " .. table.concat(seen, " | "))
        end
        return false
    end
    f.answered = true
    pcall(best.pick)
    C_Timer.After(1, Crates.RefreshFill)
    return true
end

local function answerChoice()
    local PC = rawget(_G, "C_PlayerChoice")
    local info = PC and PC.GetCurrentPlayerChoiceInfo and PC.GetCurrentPlayerChoiceInfo()
    if not (info and info.options) then return end
    local opts = {}
    for _, o in ipairs(info.options) do
        local bt = o.buttons and o.buttons[1]
        local id = (bt and bt.id) or o.responseID or o.id
        if id then opts[#opts + 1] = { text = optionText(o), pick = function() PC.SendPlayerChoiceResponse(id) end } end
    end
    if Crates.Answer(opts) and rawget(_G, "PlayerChoiceFrame") and PlayerChoiceFrame.Hide then
        C_Timer.After(0.2, function() if PlayerChoiceFrame:IsShown() then pcall(HideUIPanel or PlayerChoiceFrame.Hide, PlayerChoiceFrame) end end)
    end
end

local function answerGossip()
    local G = rawget(_G, "C_GossipInfo")
    local opts = {}
    if G and G.GetOptions then
        for _, o in ipairs(G.GetOptions() or {}) do
            local id = o.gossipOptionID
            if id then opts[#opts + 1] = { text = optionText(o), pick = function() G.SelectOption(id) end } end
        end
    end
    Crates.Answer(opts)
end

local fillQueued
local function onEvent(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        Crates.Build()
        Crates.Update()
    elseif (event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_UPDATED"
            or event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") and ui.card and ui.card:IsShown() then
        C_Timer.After(0.2, drawCard)   -- after Exchange reads the new prices
    elseif event == "PLAYER_CHOICE_UPDATE" then
        answerChoice()
    elseif event == "GOSSIP_SHOW" then
        answerGossip()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Crates.PlaceBagButton()
    elseif event == "PLAYER_LOGIN" then
        Crates.HookBags()
    elseif event == "BAG_UPDATE_DELAYED" and #fillButtons > 0 and not fillQueued then
        fillQueued = true
        C_Timer.After(0.5, function() fillQueued = nil; Crates.RefreshFill() end)
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
    for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
                          "PLAYER_CHOICE_UPDATE", "GOSSIP_SHOW", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGIN" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    -- the key binding (Key Bindings > RUIN Exchange) clicks this hidden one
    local key = makeSecure(UIParent, "RUIN_ExchangeCrateFill")
    if key then key:Hide(); Crates.keyButton = key end
    Crates.HookBags()
    ev:SetScript("OnEvent", onEvent)
    Crates.ui = ui
    M.Crates = Crates
end
