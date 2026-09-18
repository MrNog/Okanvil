-- ============================================================
-- Okanvil -- Farm window.
--
-- A small always-on-top panel you leave open while farming, like the mini roll
-- manager: gold/hr big at the top, then the breakdown, then what dropped.
-- Collapsible to just the rate, because most of the time that is all you want on
-- screen.
-- ============================================================

local Okanvil = Okanvil
local M = Okanvil.Farm
local W = Okanvil.W
local C = Okanvil.Colors

local ADDON = "Okanvil-Farm"
local WIN_W = 270
local ROW_H = 17
local MAX_ROWS = 8
-- Where the loot list starts, and the two heights that depend on it. Named because
-- three places have to agree -- the row anchors, the collapsed height and the
-- expanded one -- and a loose number in each was how they drifted apart.
local LIST_TOP   = 186    -- first loot row (clears the 4-row breakdown)
local COLLAPSED_H = 120   -- rate + clock + buttons only
local EMPTY_H     = 210   -- ...plus the breakdown and "nothing looted yet"

local win        -- built lazily

local function db() return M.DB() end

-- Green when the run is paying, amber when it is ordinary, red when it is not
-- worth the time. Thresholds in GOLD/hr; the numbers are the ones a WotLK farmer
-- actually thinks in.
local function rateColor(copperPerHour)
	local g = (copperPerHour or 0) / 10000
	if g >= 1000 then return "|cff00ff44" end
	if g >= 400  then return "|cffffd700" end
	return "|cffff5555"
end

local function build()
	if win then return win end

	local d = db()
	local f = CreateFrame("Frame", "OkanvilFarmWindow", UIParent)
	f:SetFrameStrata("MEDIUM")
	f:SetSize(WIN_W, 200)
	Okanvil:Skin(f)
	f:SetClampedToScreen(true)
	f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(s)
		s:StopMovingOrSizing()
		local p, _, _, x, y = s:GetPoint(1)
		d.point, d.x, d.y = p, x, y
	end)
	if d.point then f:SetPoint(d.point, UIParent, d.point, d.x or 0, d.y or 0)
	else f:SetPoint("CENTER", UIParent, "CENTER", 300, 0) end
	f:SetScale((d.scale or 100) / 100)

	-- ---- header ----
	local hdr = W.Frame(f, "raise")
	hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1); hdr:SetHeight(22)
	local ico = hdr:CreateTexture(nil, "OVERLAY")
	ico:SetSize(14, 14); ico:SetPoint("LEFT", 6, 0)
	ico:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
	ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local title = W.Text(hdr, "Farm", 12, "accent"); title:SetPoint("LEFT", ico, "RIGHT", 6, 0)

	local close = W.Button(hdr, "X"); close:SetSize(18, 16); close:SetPoint("RIGHT", -2, 0)
	close:SetScript("OnClick", function() f:Hide() end)
	local collapse = W.Button(hdr, "v"); collapse:SetSize(18, 16)
	collapse:SetPoint("RIGHT", close, "LEFT", -2, 0)
	collapse:SetScript("OnClick", function()
		d.collapsed = not d.collapsed
		M.RefreshWindow()
	end)
	f.collapseBtn = collapse

	-- ---- the number ----
	f.rate = W.Text(f, "0g", 24, "accent")
	f.rate:SetPoint("TOPLEFT", 12, -34)
	f.rateLbl = W.Text(f, "|cff8a8d93gold / hour|r", 10, "dim")
	f.rateLbl:SetPoint("TOPLEFT", 12, -64)

	f.clock = W.Text(f, "0:00", 15)
	f.clock:SetPoint("TOPRIGHT", -12, -36)
	f.zone = W.Text(f, "", 10, "dim")
	f.zone:SetPoint("TOPRIGHT", -12, -60)

	-- ---- buttons ----
	f.startBtn = W.Button(f, "Start", "primary"):Size(72, 22)
	f.startBtn:SetPoint("TOPLEFT", 12, -88)
	f.startBtn:SetScript("OnClick", function() M.Toggle(); M.RefreshWindow() end)

	f.stopBtn = W.Button(f, "Finish"):Size(72, 22)
	f.stopBtn:SetPoint("LEFT", f.startBtn, "RIGHT", 8, 0)
	f.stopBtn:SetScript("OnClick", function() M.Stop(); M.RefreshWindow() end)
	f.stopBtn:Tooltip("Bank this run into the history and clear the counters.")

	f.resetBtn = W.Button(f, "x", "danger"):Size(22, 22)
	f.resetBtn:SetPoint("LEFT", f.stopBtn, "RIGHT", 8, 0)
	f.resetBtn:SetScript("OnClick", function() M.Reset(); M.RefreshWindow() end)
	f.resetBtn:Tooltip("Throw this run away without saving it.")

	-- ---- breakdown ----
	-- One label per line, value right-aligned to the window edge. Two columns put
	-- "coin drops" in 92px with its label eating 55 of them, so a four-figure sum
	-- would have run into its own label. Full width gives every value the whole
	-- row, and the four values stack in one column the eye can read straight down.
	local GRID_Y = -118
	local GRID_ROW = 15
	f.cells = {}
	local function cell(row, label)
		local c = {}
		local y = GRID_Y - (row - 1) * GRID_ROW
		c.lbl = W.Text(f, label, 11, "dim")
		c.lbl:SetPoint("TOPLEFT", 12, y)
		c.val = W.Text(f, "", 11)
		c.val:SetPoint("TOPRIGHT", -12, y)
		c.val:SetJustifyH("RIGHT")
		f.cells[#f.cells + 1] = c
		return c
	end
	f.cVendor = cell(1, "vendor")
	f.cAH     = cell(2, "AH")
	f.cCoin   = cell(3, "coin drops")
	f.cKills  = cell(4, "kills")
	-- per-kill sits beside the "kills" label rather than on a fifth row: it is a
	-- footnote to that number, and the value column is already taken.
	f.perKill = W.Text(f, "", 10, "dim")
	f.perKill:SetPoint("LEFT", f.cKills.lbl, "RIGHT", 8, 0)

	-- ---- loot rows ----
	f.rows = {}
	for i = 1, MAX_ROWS do
		local r = W.Frame(f, "bare")
		r:SetHeight(ROW_H)
		r:SetPoint("TOPLEFT", 12, -(LIST_TOP + (i - 1) * ROW_H))
		r:SetPoint("RIGHT", f, "RIGHT", -12, 0)
		r:Hide()

		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(12, 12); r.icon:SetPoint("LEFT", 0, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		r.text = W.Text(r, "", 11)
		r.text:SetPoint("LEFT", 17, 0); r.text:SetPoint("RIGHT", -62, 0)
		r.text:SetJustifyH("LEFT")
		if r.text.SetWordWrap then r.text:SetWordWrap(false) end

		r.val = W.Text(r, "", 11, "dim")
		r.val:SetPoint("RIGHT", 0, 0); r.val:SetJustifyH("RIGHT")

		r:EnableMouse(true)
		r:SetScript("OnEnter", function(self)
			if not self._link then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self._link); GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)

		f.rows[i] = r
	end

	f.empty = W.Text(f, "", 11, "dim")
	f.empty:SetPoint("TOPLEFT", 12, -LIST_TOP)

	-- "2 more v" under the last row, so a long list is visibly longer than the
	-- window rather than silently truncated.
	f.more = W.Text(f, "", 10, "dim")
	f.more:SetPoint("BOTTOMLEFT", 12, 8)
	f.more:Hide()

	-- wheel anywhere over the window moves the list window
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(self, dz)
		self.lootOff = math.max(0, (self.lootOff or 0) - dz)
		M.RefreshWindow()
	end)

	-- One ticker while the window is open: the clock and the rate both move on
	-- their own, so they cannot wait for an event. Half-second is smooth enough
	-- and costs nothing.
	local acc = 0
	f:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.5 then return end
		acc = 0
		if M.IsRunning() then M.RefreshWindow() end
	end)

	win = f
	return f
end

function M.RefreshWindow()
	if not win or not win:IsShown() then return end
	local d = db()

	local running = M.IsRunning()
	local gph = M.GoldPerHour()

	win.rate:SetText(rateColor(gph) .. M.Money(gph, true) .. "|r")
	win.clock:SetText((running and "|cff7cfc8a" or "|cff8a8d93") .. M.Clock(M.Duration()) .. "|r")
	win.zone:SetText("|cff6f7176" .. (M.S.zone or "") .. "|r")
	if win.startBtn.text then
		win.startBtn.text:SetText(running and "Pause" or "Start")
	end
	-- not "running and nil or primary": nil is falsy, so that expression is
	-- always "primary" and the button never dimmed while a run was going
	if running then win.startBtn:SetKind(nil) else win.startBtn:SetKind("primary") end

	-- Collapsed = the rate, the clock and the buttons. Everything that answers
	-- "how is this run going" stays; the detail goes.
	local collapsed = d.collapsed and true or false
	if win.collapseBtn.text then win.collapseBtn.text:SetText(collapsed and "^" or "v") end

	if collapsed then
		for _, c in ipairs(win.cells) do c.lbl:Hide(); c.val:Hide() end
		win.perKill:Hide(); win.empty:Hide()
		for _, r in ipairs(win.rows) do r:Hide() end
		win:SetHeight(COLLAPSED_H)
		return
	end
	for _, c in ipairs(win.cells) do c.lbl:Show(); c.val:Show() end
	win.perKill:Show()

	local S = M.S
	-- "total 6g 24s / items 6g 24s" read as two numbers that happened to match:
	-- with almost no coin looted the item value IS the total, and nothing said so.
	-- The useful comparison is the same bag priced two ways, so that is what the
	-- two lines carry now -- what a vendor pays today, and what the AH would.
	local vend, ah = M.TotalVendor(), M.TotalAH()
	win.cVendor.val:SetText(M.Money(vend, true))
	win.cAH.val:SetText("|cffffd200" .. M.Money(ah, true) .. "|r")
	win.cCoin.val:SetText(M.Money(S.cash, true))
	win.cKills.val:SetText(tostring(S.kills))
	win.perKill:SetText(S.kills > 0
		and ("|cff6f7176" .. M.Money(math.floor(ah / S.kills), true) .. " / kill|r") or "")

	local list = M.LootList()
	if #list == 0 then
		for _, r in ipairs(win.rows) do r:Hide() end
		win.empty:SetText("|cff6f7176Nothing looted yet.|r")
		win.empty:Show()
		win.more:Hide()          -- or a stale "3 more" survives a Finish
		win.lootOff = 0
		win:SetHeight(EMPTY_H)
		return
	end
	win.empty:Hide()

	-- The 8 rows are a WINDOW onto the sorted list, not the whole of it: a long
	-- farm loots far more than 8 distinct items, and everything past the 8th most
	-- valuable simply vanished with nothing saying so. Wheel over the list to move
	-- the window; the footer says what is off-screen.
	local maxOff = math.max(0, #list - MAX_ROWS)
	win.lootOff = math.max(0, math.min(win.lootOff or 0, maxOff))
	local off = win.lootOff

	local shown = 0
	for i, r in ipairs(win.rows) do
		local e = list[i + off]
		if not e then r:Hide() else
			shown = i
			r:Show()
			r._link = e.link
			local icon = select(10, GetItemInfo(e.link))
			if icon then r.icon:SetTexture(icon); r.icon:Show() else r.icon:Hide() end
			local nm = e.link:match("|h%[(.-)%]|h") or "?"
			r.text:SetText(e.link:match("|c%x+") and (e.link:match("(|c%x+)") .. nm .. "|r") or nm)
			r.val:SetText("|cff8a8d93" .. (e.count > 1 and (e.count .. "x  ") or "")
				.. "|r" .. M.Money(e.value, true))
		end
	end
	local more = #list - shown - off
	if more > 0 or off > 0 then
		win.more:SetText("|cff6f7176" .. (off > 0 and ("^ " .. off .. " above") or "")
			.. ((off > 0 and more > 0) and "   " or "")
			.. (more > 0 and (more .. " more v") or "") .. "|r")
		win.more:Show()
		win:SetHeight(LIST_TOP + shown * ROW_H + 24)
	else
		win.more:Hide()
		win:SetHeight(LIST_TOP + shown * ROW_H + 10)
	end
end

function Okanvil.Farm_Toggle()
	local f = build()
	if f:IsShown() then f:Hide() else f:Show(); M.RefreshWindow() end
end
M.Toggle_Window = Okanvil.Farm_Toggle

-- capture updates repaint the window
M.onChange = function() M.RefreshWindow() end

-- ------------------------------------------------------------
-- Page: history + settings. The WINDOW is the tool; this is where you look back
-- at what past runs made and set the price source.
-- ------------------------------------------------------------
function Okanvil:BuildFarm(host)
	local fill = Okanvil.UI.newFillPanel()
	local dash = W.Dashboard(host, {
		title = "Farm",
		icon = "Interface\\Icons\\INV_Misc_Bag_10",
		drawerWidth = 0,
		footerHeight = 0,
		primaryText = function() return "Open the farm window" end,
		onPrimary = function() Okanvil.Farm_Toggle() end,
		statusText = function()
			if M.IsRunning() then
				return "|cff7cfc8arunning|r |cff8a8d93" .. M.Clock(M.Duration()) .. "|r"
			end
			return "|cff8a8d93idle|r"
		end,
	})
	fill.dash = dash

	local main = dash.main
	local X = Okanvil.UI.PAD_X
	local p, relayout, sf = Okanvil.UI.DashScroll(main, X)
	local wrap = { relayout = relayout }

	local hint = W.Text(p, "Open the window, hit Start, farm. It counts cash, what your loot is "
		.. "worth and quest gold, and divides by the time the timer was actually running.", 10, "dim")
	hint:SetPoint("TOPLEFT", X, -6); hint:SetPoint("RIGHT", -X, 0); hint:SetJustifyH("LEFT")

	local pv = W.Check(p, "Value loot at vendor price (off = use an auction addon)",
		function() return M.DB().price == "vendor" end,
		function(v) M.DB().price = v and "vendor" or "auto"; M.RefreshWindow() end)
	pv:SetPoint("TOPLEFT", X + 2, -40)
	pv:Tooltip("On: what a vendor pays -- matches what you get if you vendor everything.\n"
		.. "Off: Auctionator / TSM price when installed, vendor price when not.")

	local hh = W.Text(p, "PAST RUNS", 11, "accent"); hh:SetPoint("TOPLEFT", X, -72)
	local clr = W.Button(p, "Clear"):Size(60, 18)
	clr:SetPoint("TOPLEFT", X + 90, -72)
	clr:SetScript("OnClick", function() M.ClearHistory(); if wrap._rebuild then wrap._rebuild() end end)

	wrap.rows = {}
	local function rebuild()
		for _, r in ipairs(wrap.rows) do r:Hide() end
		local h = M.History()
		local y = 96
		for i, e in ipairs(h) do
			local r = wrap.rows[i]
			if not r then
				r = W.Frame(p, "input"); r:SetHeight(34)
				r.top = W.Text(r, "", 11); r.top:SetPoint("TOPLEFT", 8, -5)
				r.sub = W.Text(r, "", 10, "dim"); r.sub:SetPoint("TOPLEFT", 8, -19)
				r.rate = W.Text(r, "", 13, "accent"); r.rate:SetPoint("RIGHT", -10, 0)
				wrap.rows[i] = r
			end
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", X, -y); r:SetPoint("RIGHT", p, "RIGHT", -X, 0)
			r:Show()
			local gph = (e.dur > 0) and math.floor(e.total / e.dur * 3600) or 0
			r.top:SetText("|cffdcddde" .. (e.zone ~= "" and e.zone or "Somewhere") .. "|r"
				.. "  |cff6f7176" .. date("%d %b %H:%M", e.at) .. "|r")
			r.sub:SetText("|cff8a8d93" .. M.Clock(e.dur) .. "  ·  " .. M.Money(e.total, true)
				.. "  ·  " .. (e.kills or 0) .. " kills|r")
			r.rate:SetText(rateColor(gph) .. M.Money(gph, true) .. "|r")
			y = y + 38
		end
		if #h == 0 then
			p:SetHeight(math.max(140, sf:GetHeight()))
		else
			p:SetHeight(math.max(y + 10, sf:GetHeight()))
		end
		wrap.relayout()
		dash:Refresh()
	end
	wrap._rebuild = rebuild

	fill:SetScript("OnShow", rebuild)
	rebuild()
	return fill
end

-- ------------------------------------------------------------
-- Register
-- ------------------------------------------------------------
Okanvil_Plugins = Okanvil_Plugins or {}
Okanvil_Plugins[ADDON] = {
	title = "Farm",
	-- The tool IS the floating window; the page only held a button that opened it
	-- and a single checkbox. No nav row -- the marks bar opens it.
	noNav = true,
	desc  = "Gold per hour while you farm. Opens from the marks bar.",
	icon  = "Interface\\Icons\\INV_Misc_Bag_10",
	build = function(panel) Okanvil:BuildFarm(panel) end,
	navAction = function() Okanvil.Farm_Toggle() end,
}
if Okanvil and Okanvil.Register then
	Okanvil:Register(ADDON)
end
