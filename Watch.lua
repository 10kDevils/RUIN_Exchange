-- RUIN Exchange: the auction watch list
-- Items you want to buy, each with the most you'll pay. Add your Best in Slot
-- pieces from RUIN Codex in one click (the ones that can be traded), or any
-- item with /exchange watch <item> <gold>. Whenever a price for one comes in
-- at or under your limit, from your own auction house visit or one shared by
-- another RUIN member, Exchange tells you (once an hour per item).
local ADDON, ns = ...
local R = RUIN_API
if not R then return end
local W = R.Widgets
local C = W.COLORS

local Watch = {}
ns.Watch = Watch
local M, db
local ui = {}

local ALERT_EVERY = 3600

local function list() db.watch = db.watch or {}; return db.watch end
local function nameOf(id, fallback)
    local n = GetItemInfo and GetItemInfo(id)
    return n or fallback or ("item " .. id)
end
local function linkOf(id)
    local _, l = GetItemInfo and GetItemInfo(id)
    return l or ("[" .. nameOf(id) .. "]")
end

-- add or change an item; max in copper (nil: tell me at any price)
function Watch.Add(id, max, from)
    id = tonumber(id)
    if not id then return false end
    local w = list()[id] or {}
    w.max = tonumber(max) or w.max
    w.from = from or w.from or "you"
    w.name = nameOf(id, w.name)
    list()[id] = w
    Watch.Refresh()
    return true
end
function Watch.Remove(id) list()[tonumber(id) or 0] = nil; Watch.Refresh() end
function Watch.Get(id) return list()[tonumber(id) or 0] end

-- Codex's Best in Slot pieces you can buy, each with a limit of the price
-- known now (or none). Returns how many were added.
function Watch.AddBis()
    local cx = R:GetModule("Codex")
    if not (cx and cx.BisBuyable) then return 0, "RUIN Codex isn't installed." end
    local n = 0
    for _, e in ipairs(cx:BisBuyable()) do
        if not list()[e.id] then
            local known = M.PriceOf and M.PriceOf(e.id)
            Watch.Add(e.id, known, "Best in Slot")
            n = n + 1
        end
    end
    if n == 0 then return 0, "Your Best in Slot list has nothing new that can be bought (open Codex > Best in Slot to work it out)." end
    return n
end

-- a price came in (yours or a member's): tell once an hour when it's in reach
function Watch.Seen(id, unit, who)
    if not db then return end
    id, unit = tonumber(id), tonumber(unit)
    local w = id and list()[id]
    if not (w and unit and unit > 0) then return end
    w.last, w.lastT, w.lastBy = unit, GetServerTime(), who
    if w.max and unit > w.max then return end
    if w.told and GetServerTime() - w.told < ALERT_EVERY then return end
    w.told = GetServerTime()
    local mine = who == UnitName("player")
    M:Toast(("Watch list: %s at %s%s"):format(nameOf(id, w.name), W.Money(unit), mine and "" or (" (seen by " .. R.Util.ShortName(who or "?") .. ")")),
        { sound = true })
    M:Print(("%s is on the auction house for %s%s%s."):format(linkOf(id), W.Money(unit),
        w.max and (", within your limit of " .. W.Money(w.max)) or "", mine and "" or (", seen by " .. R.Util.ShortName(who or "?"))))
end

---------------------------------------------------------------------------
-- The Watch tab
---------------------------------------------------------------------------
local function rows()
    local out = {}
    for id, w in pairs(list()) do out[#out + 1] = { id = id, w = w } end
    table.sort(out, function(a, b) return (a.w.name or "") < (b.w.name or "") end)
    return out
end

function Watch.Build(page)
    local h = W.Header(page, "Watch list")
    h:SetPoint("TOPLEFT", 0, -2)
    ui.sub = W.Label(page, C.dim .. "Told when one comes up at or under your limit.|r",
        "GameFontHighlightSmall")
    ui.sub:SetPoint("TOPLEFT", 0, -24)
    ui.sub:SetPoint("RIGHT", page, "RIGHT", -300, 0)
    ui.sub:SetWordWrap(false)
    local bis = W.Button(page, "Add my Best in Slot", 150, function()
        local n, err = Watch.AddBis()
        M:Print(n > 0 and ("Added %d Best in Slot pieces to your watch list."):format(n) or err)
    end)
    bis:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -18)
    bis.tip = "Your Best in Slot pieces from RUIN Codex that can be traded, each with today's price as its limit."
    ui.add = W.EditBox(page, 140)
    ui.add:SetPoint("RIGHT", bis, "LEFT", -8, 0)
    ui.add.tip = "Shift-click an item into this box (or type its ID) and press Enter to watch it."
    ui.add:SetScript("OnEnterPressed", function(self)
        local t = self:GetText() or ""
        local id = tonumber(t:match("item:(%d+)") or t:match("^%s*(%d+)%s*$"))
        if id then Watch.Add(id, M.PriceOf and M.PriceOf(id), "you") end
        self:SetText("")
        self:ClearFocus()
    end)
    ui.list = W.List(page, 28, function(row)
        row.name = W.Label(row, "")
        row.name:SetPoint("LEFT", 6, 0)
        row.name:SetWidth(240)
        row.name:SetWordWrap(false)
        row.seen = W.Label(row, "", "GameFontHighlightSmall")
        row.seen:SetPoint("LEFT", 252, 0)
        row.seen:SetWidth(220)
        row.seen:SetWordWrap(false)
        row.limitLabel = W.Label(row, C.dim .. "Limit (g)|r", "GameFontHighlightSmall")
        row.limitLabel:SetPoint("RIGHT", -210, 0)
        row.limit = W.EditBox(row, 70)
        row.limit:SetPoint("RIGHT", -134, 0)
        row.remove = W.Button(row, "Remove", 70)
        row.remove:SetPoint("RIGHT", -4, 0)
        row.from = W.Label(row, "", "GameFontHighlightSmall")
        row.from:SetPoint("RIGHT", -80, 0)
    end, function(row, e)
        local w = e.w
        row.name:SetText(linkOf(e.id))
        row.seen:SetText(w.last and (C.dim .. "seen " .. W.Money(w.last) .. " " .. W.Ago(GetServerTime() - (w.lastT or 0)) .. "|r")
            or (C.dim .. "not seen yet|r"))
        row.from:SetText(C.dim .. (w.from == "Best in Slot" and "BiS" or "") .. "|r")
        if not row.limit:HasFocus() then row.limit:SetText(w.max and tostring(math.floor(w.max / 10000 + 0.5)) or "") end
        row.limit:SetScript("OnEnterPressed", function(self)
            local g = tonumber(self:GetText())
            w.max = g and math.floor(g * 10000) or nil
            self:ClearFocus()
            Watch.Refresh()
        end)
        row.remove:SetScript("OnClick", function() Watch.Remove(e.id) end)
        row.tip = function(tip)
            tip:SetHyperlink(("item:%d"):format(e.id))
        end
    end)
    ui.list:SetEmptyText("Nothing watched yet. Add your Best in Slot pieces, or shift-click an item into the box above.")
    ui.list.frame:SetPoint("TOPLEFT", 0, -50)
    ui.list.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
end

function Watch.Refresh()
    if ui.list and ui.list.frame:IsVisible() then ui.list:SetItems(rows()) end
end

-- /exchange watch <item link or ID> [gold]
function Watch.Slash(rest)
    local id = tonumber((rest or ""):match("item:(%d+)") or (rest or ""):match("^%s*(%d+)"))
    if not id then return M:Print("Usage: /exchange watch <item link or ID> [most you'll pay, in gold]") end
    local g = tonumber((rest or ""):match("([%d%.]+)%s*g?%s*$"))
    if g and g == id then g = nil end
    Watch.Add(id, g and math.floor(g * 10000) or (M.PriceOf and M.PriceOf(id)), "you")
    local w = Watch.Get(id)
    M:Print(("Watching %s%s."):format(linkOf(id), w.max and (" up to " .. W.Money(w.max)) or " at any price"))
end

function Watch.Init(module, cdb)
    M, db = module, cdb
    list()
end
