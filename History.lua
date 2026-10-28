-- RUIN Exchange: crafting history
-- Who crafted what for whom, confirmed by both. When you trade someone an
-- item you can craft, or put an enchant on their item in the trade window,
-- RUIN asks them to confirm the craft (they can also log one by hand on this
-- tab). Once the customer confirms, every RUIN member's history has it, and
-- the crafters with the most confirmed crafts this month top the list.
local ADDON, ns = ...
local R = RUIN_API
if not R or (R.apiLevel or 1) < 9 then return end
local W = R.Widgets
local C = W.COLORS

local History = {}
ns.History = History

local MONTH = 30 * 86400
local KEEP = 180 * 86400
local PENDING_FOR = 3 * 86400
local MAX = 800

local M, db, EI
local ui = { view = "Crafters" }

local function now() return GetServerTime() end
local function short(n) return R.Util.ShortName(n or "?") end
local function me() return R:GetPlayer().name end

local function store()
    db.crafts = type(db.crafts) == "table" and db.crafts or {}
    db.crafts.done = type(db.crafts.done) == "table" and db.crafts.done or {}        -- id -> confirmed craft
    db.crafts.pending = type(db.crafts.pending) == "table" and db.crafts.pending or {} -- id -> waiting for you (or them)
    return db.crafts
end

local function newId() return tostring(R:GetPlayerGUID() or "x"):sub(-4) .. now() % 1000000 .. math.random(10, 99) end

local function clean(d)
    if type(d) ~= "table" or type(d.id) ~= "string" or type(d.item) ~= "string" or type(d.cr) ~= "string" or type(d.cu) ~= "string" then return nil end
    return { id = d.id:sub(1, 24), item = d.item:gsub("|", "/"):sub(1, 120), link = type(d.link) == "string" and d.link:sub(1, 200) or nil,
             cr = d.cr:sub(1, 48), cu = d.cu:sub(1, 48), prof = type(d.prof) == "string" and d.prof:sub(1, 30) or nil,
             t = (R.SaneTime and R:SaneTime(d.t)) or now() }
end

-- The crafter logs a craft; the customer confirms it.
function History.Log(item, customer, prof, link)
    item, customer = R.Util.Trim(item or ""), R.Util.Trim(customer or "")
    if item == "" or customer == "" then return false, "Which item, and for whom?" end
    if short(customer):lower() == short(me()):lower() then return false, "Crafts for yourself don't count." end
    local c = clean({ id = newId(), item = item, link = link, cr = me(), cu = customer, prof = prof, t = now() })
    c.mine = true
    store().pending[c.id] = c
    M:Send("CDONE", c, "PEER", customer, R.PRIORITY.NORMAL)
    History.Refresh()
    return true
end

local function onDone(_, d, sender)
    local c = clean(d)
    if not c or short(c.cr):lower() ~= short(sender):lower() then return end
    if short(c.cu):lower() ~= short(me()):lower() then return end
    c.cr = sender
    store().pending[c.id] = c
    M:Toast(("%s says they crafted %s for you. Confirm it on Exchange > History."):format(W.ClassName(sender), c.item))
    History.Refresh()
end

-- The customer confirms (or declines) a craft that's waiting.
function History.Confirm(id, yes)
    local c = store().pending[id]
    if not c or c.mine then return false end
    store().pending[id] = nil
    if yes then
        store().done[c.id] = c
        M:Send("CCONF", c, "ORG", nil, R.PRIORITY.NORMAL)
    end
    History.Refresh()
    return true
end

local function onConfirm(_, d, sender)
    local c = clean(d)
    if not c or short(c.cu):lower() ~= short(sender):lower() then return end    -- only the customer confirms
    store().done[c.id] = c
    if store().pending[c.id] then
        store().pending[c.id] = nil
        if short(c.cr):lower() == short(me()):lower() then M:Print(("%s confirmed your craft of %s."):format(short(sender), c.item)) end
    end
    local n, oldest, oldestId = 0, math.huge, nil
    for id, x in pairs(store().done) do
        n = n + 1
        if now() - x.t > KEEP then store().done[id] = nil elseif x.t < oldest then oldest, oldestId = x.t, id end
    end
    if n > MAX and oldestId then store().done[oldestId] = nil end
    History.Refresh()
end

-- A trade finished (Treasury.lua): items you can craft that you gave, and an enchant you put on their item.
function History.AfterTrade(t)
    if not t.who then return end
    for _, link in ipairs(t.items or {}) do
        local name = link:match("%[(.-)%]")
        local prof = name and EI.canICraft(name)
        if prof then History.Log(name, t.who, prof, link) end
    end
    if t.enchant then History.Log(t.enchant.enchant .. " (on " .. t.enchant.item .. ")", t.who, "Enchanting") end
end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------
function History.Done()
    local out = {}
    for _, c in pairs(store().done) do out[#out + 1] = c end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end

-- Crafters by confirmed crafts this month: { name, month, total, customers }
function History.Crafters()
    local by = {}
    for _, c in pairs(store().done) do
        local k = short(c.cr):lower()
        local r = by[k] or { name = c.cr, month = 0, total = 0, customers = {}, profs = {} }
        r.total = r.total + 1
        if now() - c.t <= MONTH then r.month = r.month + 1 end
        r.customers[short(c.cu)] = true
        if c.prof then r.profs[c.prof] = true end
        by[k] = r
    end
    local out = {}
    for _, r in pairs(by) do
        local n, ps = 0, {}
        for _ in pairs(r.customers) do n = n + 1 end
        for p in pairs(r.profs) do ps[#ps + 1] = p end
        table.sort(ps)
        r.customerCount, r.profList = n, table.concat(ps, ", ")
        out[#out + 1] = r
    end
    table.sort(out, function(a, b) if a.month ~= b.month then return a.month > b.month end return a.total > b.total end)
    return out
end

function History.Pending()
    local out = {}
    for id, c in pairs(store().pending) do
        if now() - c.t > PENDING_FOR then store().pending[id] = nil else out[#out + 1] = c end
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end

---------------------------------------------------------------------------
-- The History tab
---------------------------------------------------------------------------
function History.Build(page)
    ui.page = page
    ui.viewBtn = W.Dropdown(page, 150, { "Crafters", "Crafts", "Waiting" }, function() return ui.view end,
        function(v) ui.view = v; History.Refresh() end, "Show: ")
    ui.viewBtn:SetPoint("TOPLEFT", 0, 0)
    ui.info = W.Label(page, "", "GameFontHighlightSmall")
    ui.info:SetPoint("LEFT", ui.viewBtn, "RIGHT", 10, 0)
    ui.info:SetWidth(470)
    ui.info:SetJustifyH("LEFT")
    ui.info:SetWordWrap(false)
    ui.logBtn = W.Button(page, "Log a craft", 100, function()
        R:ShowText("Log a craft", "What you made and for whom: Robe of Power, Grimlock. They confirm it.", "", function(text)
            local item, who = text:match("^(.-),%s*(.+)$")
            local ok, err = History.Log(item, who)
            M:Print(ok and ("Sent to " .. short(who) .. " to confirm.") or err)
        end)
    end)
    ui.logBtn:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    ui.list = W.List(page, 22, function(row)
        row.a = W.Label(row, "")
        row.a:SetPoint("LEFT", 6, 0); row.a:SetWidth(220); row.a:SetWordWrap(false)
        row.b = W.Label(row, "", "GameFontHighlightSmall")
        row.b:SetPoint("LEFT", 232, 0); row.b:SetPoint("RIGHT", row, "RIGHT", -150, 0); row.b:SetWordWrap(false)
        row.no = W.Button(row, "No", 50)
        row.no:SetPoint("RIGHT", -2, 0)
        row.yes = W.Button(row, "Confirm", 76)
        row.yes:SetPoint("RIGHT", row.no, "LEFT", -4, 0)
    end, function(row, e)
        row.yes:Hide(); row.no:Hide()
        if e.crafter then
            local r = e.crafter
            row.a:SetText(("%s%d.|r %s"):format(C.dim, e.i, W.ClassName(r.name)))
            row.b:SetText(("%s%d|r this month  ·  %d in all  ·  %d customers%s"):format(C.white, r.month, r.total, r.customerCount,
                r.profList ~= "" and (C.dim .. "  ·  " .. r.profList .. "|r") or ""))
        else
            local c = e.craft
            row.a:SetText(c.link or (C.white .. c.item .. "|r"))
            row.link = c.link and c.link:match("|H(item:[^|]+)|h")
            if e.pending then
                row.b:SetText(c.mine and (C.dim .. "for " .. short(c.cu) .. ", waiting for them to confirm|r")
                    or (W.ClassName(c.cr) .. C.dim .. " made it for you?|r"))
                if not c.mine then
                    row.yes:SetScript("OnClick", function() History.Confirm(c.id, true) end)
                    row.no:SetScript("OnClick", function() History.Confirm(c.id, false) end)
                    row.yes:Show(); row.no:Show()
                end
            else
                row.b:SetText(("%s %sfor|r %s  %s%s|r"):format(W.ClassName(c.cr), C.dim, short(c.cu), C.dim, W.Ago(math.max(60, now() - c.t))))
            end
        end
    end)
    ui.list.frame:SetPoint("TOPLEFT", 0, -32)
    ui.list.frame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 0)
    page:SetScript("OnShow", History.Refresh)
end

function History.Refresh()
    if not (ui.page and ui.page:IsVisible()) then return end
    local items = {}
    local pending = History.Pending()
    if ui.view == "Waiting" then
        for _, c in ipairs(pending) do items[#items + 1] = { craft = c, pending = true } end
        ui.info:SetText(C.dim .. "Crafts waiting to be confirmed, by you or your customer.|r")
        ui.list:SetEmptyText("Nothing waiting.")
    elseif ui.view == "Crafts" then
        for _, c in ipairs(History.Done()) do items[#items + 1] = { craft = c } end
        ui.info:SetText(C.dim .. "Confirmed crafts across RUIN, newest first.|r")
        ui.list:SetEmptyText("No confirmed crafts yet.")
    else
        for i, r in ipairs(History.Crafters()) do items[#items + 1] = { crafter = r, i = i } end
        local mineWaiting = 0
        for _, c in ipairs(pending) do if not c.mine then mineWaiting = mineWaiting + 1 end end
        ui.info:SetText(mineWaiting > 0 and (C.gold .. mineWaiting .. " craft" .. (mineWaiting == 1 and "" or "s") .. " for you to confirm (Show: Waiting).|r")
            or (C.dim .. "Crafters by confirmed crafts this month. Trading a crafted item asks your customer to confirm.|r"))
        ui.list:SetEmptyText("No confirmed crafts yet.")
    end
    ui.list:SetItems(items)
end

function History.WaitingForMe()
    local n = 0
    for _, c in ipairs(History.Pending()) do if not c.mine then n = n + 1 end end
    return n
end

function History.Init(module, edb, internals)
    M, db, EI = module, edb, internals
    store()
    M:Listen("CDONE", onDone)
    M:Listen("CCONF", onConfirm)
end
