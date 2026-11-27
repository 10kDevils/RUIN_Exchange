-- RUIN Exchange: Waylaid Crates on the auction house
-- A "Waylaid Crates" list under the auction house's Buy page. Pick a crate
-- and a card beside the auction house lists what fills it, each bundle with
-- what it costs; Exchange searches for the first one, and a click on any row
-- searches for that one. Crates you hover are learned, so a new kind shows up
-- in the list too.
local ADDON, ns = ...
local R = RUIN_API
if not R then return end
local W = R.Widgets
local C = W.COLORS

local Crates = {}
ns.Crates = Crates
local M, db
local ui = {}

local PREFIX = "Waylaid Crate: "
local ROW_H, CARD_W = 22, 250

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
end

local function unitPrice(name)
    local id = M.CrateItem and M.CrateItem(name)
    if not id then return nil end
    return (M.ExpectedPrice and M.ExpectedPrice(id)) or (db.prices and db.prices[id] and db.prices[id].p)
end

-- one crate's bundles with prices: { { n, name, unit, total } ... }, crate total (nil when any is missing)
function Crates.Costs(short)
    local list = Crates.All()[short]
    if not list then return nil end
    local out, sum, missing = {}, 0, false
    for i, e in ipairs(list) do
        local unit = unitPrice(e[2])
        out[i] = { n = e[1], name = e[2], unit = unit, total = unit and unit * e[1] }
        if unit then sum = sum + unit * e[1] else missing = true end
    end
    return out, (not missing) and sum or nil
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
-- The dropdown and the card
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
    local costs, sum = Crates.Costs(short or "")
    if not costs then card:Hide(); return end
    card.title:SetText(C.gold .. PREFIX .. "|r" .. C.white .. short .. "|r")
    for i, c in ipairs(costs) do
        local row = ui.rows[i]
        if not row then
            row = W.MenuRow(card, CARD_W - 16)
            row.price = W.Label(row, "", "GameFontHighlightSmall")
            row.price:SetPoint("RIGHT", -6, 0)
            row:SetScript("OnClick", function(self) Crates.Search(self.item) end)
            ui.rows[i] = row
        end
        row.item = c.name
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, -30 - (i - 1) * ROW_H)
        row:SetText(("%d %s"):format(c.n, c.name))
        row.price:SetText(c.total and W.Money(c.total) or (C.dim .. "none yet|r"))
        if Crates.lastSearch == c.name then row:LockHighlight() else row:UnlockHighlight() end
        row:Show()
    end
    for i = #costs + 1, #ui.rows do ui.rows[i]:Hide() end
    card.total:ClearAllPoints()
    card.total:SetPoint("TOPLEFT", 12, -36 - #costs * ROW_H)
    card.total:SetText(C.white .. "Whole crate:|r " .. (sum and W.Money(sum) or (C.dim .. "some prices missing|r")))
    card:SetHeight(58 + #costs * ROW_H)
    card:Show()
end
Crates.Draw = drawCard

function Crates.Pick(short)
    if not Crates.All()[short] then return end
    db.crateSel = short
    local first = Crates.All()[short][1]
    if first then Crates.Search(first[2]) end
    if ui.dropdown then ui.dropdown.Refresh() end
    drawCard()
end

-- shown on the Buy page only
function Crates.Update()
    if not ui.dropdown then return end
    local buy = onBuyPage()
    if buy then ui.dropdown:Show() else ui.dropdown:Hide() end
    if buy and db.crateSel then drawCard() elseif ui.card then ui.card:Hide() end
end

function Crates.Build()
    local f = rawget(_G, "AuctionHouseFrame")
    if not f or ui.dropdown then return ui.dropdown ~= nil end
    local dd = W.Dropdown(f, 210, Crates.Names, function() return db.crateSel end, Crates.Pick)
    dd.Refresh = function()
        local v = db.crateSel
        dd:SetText(v and Crates.All()[v] and (PREFIX .. v) or "Waylaid Crates")
    end
    dd:ClearAllPoints()
    dd:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
    W.MarkChoice(dd, "Pick a Waylaid Crate to find what fills it.")
    ui.dropdown = dd
    local card = W.Card(f)
    card:SetSize(CARD_W, 120)
    card:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
    card.title = W.Label(card, "", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", 12, -10)
    card.total = W.Label(card, "", "GameFontHighlightSmall")
    card:Hide()
    ui.card, ui.rows = card, {}
    dd.Refresh()
    if hooksecurefunc and f.SetDisplayMode then pcall(hooksecurefunc, f, "SetDisplayMode", Crates.Update) end
    if f.HookScript then f:HookScript("OnHide", function() if ui.card then ui.card:Hide() end end) end
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
