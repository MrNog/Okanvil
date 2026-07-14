-- ============================================================
--  Okanvil-RaidFinder :: Mini Raid Browser  (floating window)
--
--  A compact, draggable window (like the classic "Mini Raid Browser"): a tight
--  list of live LFM listings with Raid / GS / Sender / Ress / /W / Join columns,
--  clickable sort headers, and an ON/OFF toggle at the bottom that starts/stops
--  the chat scan.
--
--  This is a THIN VIEW: it reuses ALL of RaidFinder.lua's logic via
--  Okanvil.RaidFinder_Shared (parse store, sort, labels, tooltips, lockout) and
--  the existing Join / /w / reserved helpers. No parsing or storage lives here.
--
--  3.3.5a-safe: Show/Hide only (no SetShown), Okanvil:Popup for the movable frame.
-- ============================================================

Okanvil = Okanvil or {}
local W = Okanvil.W

-- module toggle shared with the Dashboard page (same ADDON id -> same on/off)
local ADDON = "Okanvil-RaidFinder"

local S            -- Okanvil.RaidFinder_Shared (resolved on first open)
local win          -- the floating window (built lazily)
local ROW_H = 18   -- tight rows to match the reference image
local MAX_ROWS = 16
local WIN_W = 360

-- mini-window column x-offsets (inside the row). Kept compact.
-- Rows are clipped to the scroll interior (WIN_W - 12px well pad - 12px scrollbar
-- gutter ~= 336px), so the last column (Join, +32w) must end before that edge or it
-- gets cut off. Join right edge = 278 + 32 = 310, leaving ~22px clearance.
-- Raid slot = gs - raid - 4 = 60px, which still fits the widest label ("Naxx10 Wk").
local M = {
	raid   = 6,
	gs     = 70,
	sender = 108,
	ress   = 200,
	wsp    = 250,
	join   = 278,
}
local RESS_W = 40

local function C() return Okanvil.Colors end

-- Is the mini window currently open (shown)?
local function is_open() return win and win:IsShown() end

-- Turn background scanning on/off for the mini window. When open we force the
-- RaidFinder scan gate on (via the flag RaidFinder.lua checks in should_scan).
local function set_scanning(on)
	Okanvil.RaidFinder_MiniWantsScan = on and true or false
end

-- ------------------------------------------------------------
-- ROW
-- ------------------------------------------------------------
local function make_row(parent)
	local r = CreateFrame("Button", nil, parent)
	r:SetHeight(ROW_H)

	-- zebra base + hover highlight
	local base = r:CreateTexture(nil, "BACKGROUND")
	base:SetAllPoints(); base:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	base:SetVertexColor(1, 1, 1, 0); r._base = base
	local hl = r:CreateTexture(nil, "BORDER")
	hl:SetAllPoints(); hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	hl:SetVertexColor(1, 1, 1, 0); r._hl = hl

	r:SetScript("OnEnter", function(s)
		s._hl:SetVertexColor(1, 1, 1, 0.06)
		if s._info and s._info.message then
			GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
			GameTooltip:AddLine(s._info.message, 1, 1, 1, true)
			GameTooltip:AddLine("Last spam: " .. (time() - s._info.lastSeen) .. "s ago", 0.6, 0.6, 0.6)
			if s._info.locked then GameTooltip:AddLine("|cffff5555You are saved to this raid|r") end
			GameTooltip:Show()
			GameTooltip:SetBackdropColor(0, 0, 0, 1)
			GameTooltip:SetBackdropBorderColor(0.88, 0.72, 0.38, 1)
		end
	end)
	r:SetScript("OnLeave", function(s) s._hl:SetVertexColor(1, 1, 1, 0); S.hide_tip() end)

	local function fs(x, size, w)
		local t = W.Text(r, "", size or 11)
		t:SetPoint("LEFT", x, 0); t:SetJustifyH("LEFT")
		if w then t:SetWidth(w) end
		return t
	end
	r.raid   = fs(M.raid, 11, M.gs - M.raid - 4)
	r.gs     = fs(M.gs, 11)
	r.sender = fs(M.sender, 11, M.ress - M.sender - 4)

	-- Ress chip (bordered YES/NO) with the shared reserved-loot tooltip
	r.ress = CreateFrame("Button", nil, r)
	r.ress:SetSize(RESS_W, 15); r.ress:SetPoint("LEFT", M.ress, 0)
	Okanvil:Skin(r.ress, "input")
	r.ress.txt = W.Text(r.ress, "", 10); r.ress.txt:SetAllPoints(); r.ress.txt:SetJustifyH("CENTER")
	r.ress:SetScript("OnEnter", function(s) S.show_tip(s, s._res) end)
	r.ress:SetScript("OnLeave", function() S.hide_tip() end)

	-- /W  +  Join (reuse the module's whisper/join)
	r.wsp = W.Button(r, "/W"); r.wsp:SetSize(24, 15); r.wsp:SetPoint("LEFT", M.wsp, 0)
	r.wsp:SetScript("OnClick", function(s)
		if s._info then Okanvil.RaidFinder_Whisper(s._info) end
	end)
	r.join = W.Button(r, "Join", "primary"); r.join:SetSize(32, 15)
	r.join:SetPoint("LEFT", M.join, 0)
	r.join:SetScript("OnClick", function(s)
		if s._info then Okanvil.RaidFinder_Join(s._info) end
	end)

	return r
end

-- ------------------------------------------------------------
-- RENDER  (public -- RaidFinder.lua pokes this on every listing change)
-- ------------------------------------------------------------
function Okanvil.RaidFinderMini_Render()
	if not (win and win:IsShown() and S) then return end
	local view = S.get_view()
	win.count:SetText((#view) .. " listing" .. (#view == 1 and "" or "s")
		.. "  |cff8a8d93-- hover = saved status + full msg|r")

	win.rows = win.rows or {}
	local now = time()
	local shown = math.min(#view, MAX_ROWS)

	for i = 1, shown do
		local info = view[i]
		local r = win.rows[i]
		if not r then r = make_row(win.child); win.rows[i] = r end
		r._info = info
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
		r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)

		-- Raid (red if you're saved to it)
		r.raid:SetText(S.raid_label(info))
		if info.locked then r.raid:Color(1, 0.33, 0.33) else r.raid:Color(0.86, 0.86, 0.86) end

		-- GS
		r.gs:SetText(info.gs and (info.gs .. "k") or "|cff8a8d93--|r")

		-- Sender (class-colored via the leader's name? we only have the name -> gold)
		r.sender:SetText("|cffe0b860" .. (info.sender or "?") .. "|r")

		-- Ress chip
		if info.reserved == nil then
			r.ress:Hide(); r.ress._res = nil
		elseif info.reserved == false then
			r.ress:Show(); r.ress.txt:SetText("|cff8a8d93NO|r")
			r.ress:SetBackdropBorderColor(0.54, 0.55, 0.58, 1); r.ress._res = false
		else
			r.ress:Show(); r.ress.txt:SetText("|cffe0b860YES|r")
			r.ress:SetBackdropBorderColor(0.88, 0.72, 0.38, 1)
			r.ress._res = S.reserved_tooltip(info)
		end

		r.wsp._info = info
		r.join._info = info

		-- zebra
		if i % 2 == 0 then r._base:SetVertexColor(1, 1, 1, 0) else r._base:SetVertexColor(1, 1, 1, 0.03) end
		-- flash on fresh re-spam
		if info._flash and now - info._flash < 3 then
			r._hl:SetVertexColor(1, 0.82, 0, 0.10)
		else
			r._hl:SetVertexColor(1, 1, 1, 0)
		end
		r:Show()
	end
	for i = shown + 1, #win.rows do win.rows[i]:Hide() end

	win.child:SetHeight(math.max(1, shown * ROW_H))
	if win.sb and win.sf then
		local maxS = math.max(0, (shown * ROW_H) - win.sf:GetHeight())
		win.sb:SetMinMaxValues(0, maxS)
		if win.sb:GetValue() > maxS then win.sb:SetValue(maxS) end
	end
end

-- ------------------------------------------------------------
-- sort header repaint (mini shares RaidFinder's sortState)
-- ------------------------------------------------------------
local function update_headers()
	if not (win and win.sortHeaders) then return end
	local st = S.sortState
	for _, b in ipairs(win.sortHeaders) do
		if b.key == st.key then
			local arrow = st.asc and " |cffe0b860\226\150\178|r" or " |cffe0b860\226\150\188|r"  -- up/down
			b.fs:SetText(b.label .. arrow)
			b.fs:Color(1, 1, 1)
		else
			b.fs:SetText(b.label)
			local a = C().accent
			b.fs:Color(a[1], a[2], a[3])
		end
	end
end

-- ------------------------------------------------------------
-- BUILD the floating window (once)
-- ------------------------------------------------------------
local function build()
	S = Okanvil.RaidFinder_Shared
	if not S then return nil end

	local f = Okanvil:Popup("Mini Raid Browser")
	local rows = MAX_ROWS
	f:SetSize(WIN_W, 44 + 16 + rows * ROW_H + 12)  -- titlebar+count + colhdr + rows + pad

	-- count / hint line under the title bar
	f.count = W.Text(f, "", 10, "dim")
	f.count:SetPoint("TOPLEFT", 8, -30)

	-- Straight through to the Raid Finder page, where the filters live. The mini list
	-- has no room for them, and hunting for the module in the nav to change one filter
	-- is friction you feel every single raid night.
	f.filters = W.Button(f, "Filters")
	f.filters:SetSize(52, 16)
	f.filters:SetPoint("TOPRIGHT", -28, -28)
	f.filters:SetScript("OnClick", function()
		-- Toggle() would CLOSE the window if it happened to be open already, so build
		-- and show it directly, then jump to the page.
		if not Okanvil.win then Okanvil:BuildShell() end
		if Okanvil.puck then Okanvil.puck:Hide() end
		Okanvil:RefreshNav()
		Okanvil.win:Show()
		Okanvil:ShowPanel("Okanvil-RaidFinder")
	end)

	-- dark well holding the list
	local well = W.Frame(f, "dark")
	well:SetPoint("TOPLEFT", 6, -44)
	well:SetPoint("TOPRIGHT", -6, -44)
	well:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)

	-- column header strip (with clickable sort headers)
	local hdr = W.Frame(well, "input")
	hdr:SetPoint("TOPLEFT", 2, -2); hdr:SetPoint("TOPRIGHT", -2, 0); hdr:SetHeight(16)
	local function colhC(x, w, t)
		local fsx = W.Text(hdr, t, 10, "accent"); fsx:SetJustifyH("CENTER")
		fsx:SetPoint("LEFT", x, 0); fsx:SetWidth(w)
	end

	f.sortHeaders = {}
	local function sortHeader(x, t, key)
		local b = CreateFrame("Button", nil, hdr)
		b:SetHeight(16); b:SetPoint("LEFT", x, 0)
		local fsx = W.Text(b, t, 10, "accent"); fsx:SetPoint("LEFT", 2, 0)
		b:SetWidth(fsx:GetStringWidth() + 16)
		b.label, b.key, b.fs = t, key, fsx
		b:SetScript("OnClick", function()
			local st = S.sortState
			if st.key ~= key then
				st.key, st.asc = key, true
			elseif st.asc then
				st.asc = false
			else
				st.key, st.asc = "seen", true   -- 3rd click -> default stable order
			end
			update_headers()
			Okanvil.RaidFinderMini_Render()
			if Okanvil.RaidFinder_UpdateSortHeaders then Okanvil.RaidFinder_UpdateSortHeaders() end
			if Okanvil.RaidFinder_Render then Okanvil.RaidFinder_Render() end
		end)
		b:SetScript("OnEnter", function() fsx:Color(1, 1, 1) end)
		b:SetScript("OnLeave", function() update_headers() end)
		f.sortHeaders[#f.sortHeaders + 1] = b
		return b
	end

	sortHeader(M.raid, "Raid", "instance")
	sortHeader(M.gs, "GS", "gs")
	sortHeader(M.sender, "Sender", "leader")
	colhC(M.ress, RESS_W, "Ress")
	colhC(M.wsp, 24, "/W")
	colhC(M.join, 32, "Join")

	-- flat scroll list (plain ScrollFrame + our slider), same idiom as the page
	local sf = CreateFrame("ScrollFrame", nil, well)
	sf:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -2)
	sf:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -12, 4)
	Okanvil.Clip(sf)
	local child = CreateFrame("Frame", nil, sf); child:SetSize(10, 1); sf:SetScrollChild(child)
	local sb = CreateFrame("Slider", nil, well)
	sb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 8, 0); sb:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 8, 0); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1); sb:SetMinMaxValues(0, 0); sb:SetValue(0)
	local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture("Interface\\ChatFrame\\ChatFrameBackground"); th:SetSize(4, 30)
	do local a = C().accent; th:SetVertexColor(a[1], a[2], a[3], 1) end
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 30) end)
	sf:SetScript("OnSizeChanged", function() child:SetWidth(sf:GetWidth()) end)
	f.sf, f.child, f.sb = sf, child, sb

	-- Scanning is tied to the window's visibility: opening it starts the scan,
	-- closing it (title-bar X) stops it. No separate ON/OFF button -- the Raid
	-- Finder Settings page owns background scanning; this window just needs live
	-- data while you're looking at it.
	f:SetScript("OnHide", function() set_scanning(false) end)

	win = f
	update_headers()
	return f
end

-- ------------------------------------------------------------
-- PUBLIC toggle: open the mini window + start scanning (or close it)
-- ------------------------------------------------------------
function Okanvil.RaidFinderMini_Toggle()
	-- module OFF -> behave as if it doesn't exist
	if Okanvil.RaidFinder_Shared and not Okanvil.RaidFinder_Shared.module_on() then
		DEFAULT_CHAT_FRAME:AddMessage("|cffe0b860[Okanvil-RaidFinder]|r module is disabled in the Modules list.")
		return
	end
	if not win then build() end
	if not win then return end   -- shared API not ready yet
	if win:IsShown() then
		win:Hide()               -- OnHide stops scanning
	else
		win:Show()
		set_scanning(true)       -- opening the mini browser starts the scan
		Okanvil.RaidFinderMini_Render()
	end
end

-- No slash command: the Mini Raid Browser opens from the Raid Finder page's
-- "Mini Browser" header button (Okanvil.RaidFinderMini_Toggle).
