-- ============================================================
-- Okanvil -- Soft reserve list, docked beside the mini roll.
--
-- The master looter's view of the whole list: every reserved item, grouped by
-- the boss it drops from, with ALL its reservers (the mini roll row has room
-- for three) and what became of it tonight -- not dropped, dropped, or won by
-- whom. A reserver who is not in the raid is greyed out, so an item reserved
-- by someone who left is obvious before it is rolled.
--
-- Master looter only: opened from the SR button in the mini roll's title bar
-- or /okres. It follows the mini roll -- hidden with it, back with it.
-- ============================================================

local Okanvil = Okanvil
local W = Okanvil.W
local SR = Okanvil.SoftRes
local P = {}
Okanvil.SoftResPanel = P

local PANEL_W, PAD, ICON, GAP = 290, 8, 20, 6
local MIN_H, MAX_H, HDR_H = 140, 440, 26
local NAMES_W = PANEL_W - PAD * 2 - ICON - GAP - 10   -- 10 = the scrollbar lane

local panel

-- Open/closed is remembered, so the panel comes back with the mini roll.
local function pref()
	Okanvil.db.softres = Okanvil.db.softres or {}
	return Okanvil.db.softres
end

local function rollWin() return _G.Okanvil_RollMgr end

local function isML()
	local RM = Okanvil.RollMgr
	return RM and RM.IsML and RM.IsML() or false
end

local function classColor(token)
	local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	if not c then return "|cffdcddde" end
	return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

-- Who is in the group right now, lower-cased. `grouped` is false solo, where
-- nobody should be greyed out.
local function groupSet()
	local set = { [(UnitName("player") or ""):lower()] = true }
	local n = GetNumRaidMembers and GetNumRaidMembers() or 0
	local unit = "raid"
	if n == 0 then unit, n = "party", GetNumPartyMembers and GetNumPartyMembers() or 0 end
	for i = 1, n do
		local nm = UnitName(unit .. i)
		if nm then set[nm:lower()] = true end
	end
	return set, n > 0
end

-- What happened to each reserved item in tonight's loot: how many dropped and
-- who won them. Keyed by item id.
local function dropStatus()
	local L = Okanvil.Loot
	local st = {}
	local groups = L and L.DropsByBoss and L.DropsByBoss() or {}
	for _, g in ipairs(groups) do
		for _, dp in ipairs(g.items or {}) do
			local id = tonumber(dp.id)
			if id then
				local s = st[id] or { n = 0, won = {} }
				st[id] = s
				s.n = s.n + 1
				local wn = L.RollWinner and L.RollWinner(dp)
				local who = (wn and wn.player) or (dp.awarded and dp.receivedBy) or nil
				if who and who ~= "" then s.won[#s.won + 1] = who end
			end
		end
	end
	return st
end

local function build()
	if panel then return panel end
	local f = CreateFrame("Frame", "Okanvil_SRPanel", UIParent)
	f:SetWidth(PANEL_W); f:SetHeight(MIN_H)
	-- Same strata and level as the mini roll it sits beside.
	f:SetFrameStrata("DIALOG"); f:SetFrameLevel(10)
	Okanvil:Skin(f, "panel")
	local br, bg, bb = f:GetBackdropColor()
	if br then f:SetBackdropColor(br, bg, bb, 0.97) end
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	W.ForgeArt(f, 0.22)

	local hdr = W.Frame(f, "bare")
	hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1); hdr:SetHeight(HDR_H)
	W.Hairline(hdr, "BOTTOM", 8)
	local title = W.Text(hdr, "Soft reserves", "body", "accent")
	title:SetPoint("LEFT", PAD, 0); title:Color(1, 0.82, 0)
	local close = W.Button(hdr, "X"); close:SetSize(22, 20); close:SetPoint("RIGHT", -3, 0)
	close:SetScript("OnClick", function() P.Hide(true) end)
	f.count = W.Text(hdr, "", "note", "dim")
	f.count:SetPoint("RIGHT", close, "LEFT", -8, 0)

	-- flat scroll: plain ScrollFrame, our own thumb, the wheel moves it
	local sf = CreateFrame("ScrollFrame", nil, f)
	sf:SetPoint("TOPLEFT", PAD, -(HDR_H + 6)); sf:SetPoint("BOTTOMRIGHT", -PAD - 6, PAD)
	local child = CreateFrame("Frame", nil, sf)
	child:SetWidth(PANEL_W - PAD * 2 - 6); child:SetHeight(1)
	sf:SetScrollChild(child)
	Okanvil.Clip(sf)

	local sb = CreateFrame("Slider", nil, f)
	sb:SetPoint("TOPRIGHT", -4, -(HDR_H + 6)); sb:SetPoint("BOTTOMRIGHT", -4, PAD); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1); sb:SetMinMaxValues(0, 0); sb:SetValue(0)
	local th = sb:CreateTexture(nil, "OVERLAY")
	th:SetTexture("Interface\\Buttons\\WHITE8x8")
	local ac = Okanvil.Colors and Okanvil.Colors.accent or { 0.75, 0.58, 0.23 }
	th:SetVertexColor(ac[1], ac[2], ac[3]); th:SetSize(4, 30)
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, dz) sb:SetValue(sb:GetValue() - dz * 30) end)

	f.sf, f.child, f.sb = sf, child, sb
	f.heads, f.rows = {}, {}

	-- Items the client has never seen come in over the next second or two;
	-- repaint until they have.
	f:SetScript("OnUpdate", function(s, e)
		if not s._cold then return end
		s._acc = (s._acc or 0) + e
		if s._acc >= 1 then s._acc = 0; P.Refresh() end
	end)

	panel = f
	f:Hide()
	return f
end

local function headAt(i)
	local h = panel.heads[i]
	if h then return h end
	h = CreateFrame("Frame", nil, panel.child)
	h:SetHeight(18)
	h.txt = W.Text(h, "", "note", "accent")
	h.txt:SetPoint("BOTTOMLEFT", 0, 3)
	W.Hairline(h, "BOTTOM", 0)
	panel.heads[i] = h
	return h
end

local function rowAt(i)
	local r = panel.rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, panel.child)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(ICON, ICON); r.icon:SetPoint("TOPLEFT", 0, -3)
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	r.status = W.Text(r, "", "note")
	r.status:SetPoint("TOPRIGHT", 0, -3)
	r.status:SetJustifyH("RIGHT")
	r.name = W.Text(r, "", 11)
	r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", GAP, 0)
	r.name:SetPoint("RIGHT", r.status, "LEFT", -6, 0)
	r.name:SetJustifyH("LEFT")
	if r.name.SetWordWrap then r.name:SetWordWrap(false) end
	-- the whole list, wrapped: this is what the panel is for
	r.who = W.Text(r, "", "note")
	r.who:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
	r.who:SetWidth(NAMES_W)
	r.who:SetJustifyH("LEFT")
	panel.rows[i] = r
	return r
end

-- Beside the mini roll, on whichever side has room: left of it when it sits on
-- the right half of the screen, right of it otherwise.
local function dock()
	local rm = rollWin()
	if not (panel and rm) then return end
	panel:ClearAllPoints()
	local cx = rm:GetCenter()
	if cx and cx > (UIParent:GetWidth() / 2) then
		panel:SetPoint("TOPRIGHT", rm, "TOPLEFT", -4, 0)
	else
		panel:SetPoint("TOPLEFT", rm, "TOPRIGHT", 4, 0)
	end
end

function P.Refresh()
	if not (panel and panel:IsShown()) then return end
	local f = panel
	local items = SR.All()
	local st = dropStatus()
	local here, grouped = groupSet()
	local _, nPlayers = SR.Summary()
	for _, h in ipairs(f.heads) do h:Hide() end
	for _, r in ipairs(f.rows) do r:Hide() end

	local y, hi, ri, missing, cold = 0, 0, 0, {}, false
	local lastBoss
	local width = f.child:GetWidth()
	for _, it in ipairs(items) do
		local boss = it.boss or "Other"
		if boss ~= lastBoss then
			lastBoss = boss
			hi = hi + 1
			local h = headAt(hi)
			h:SetPoint("TOPLEFT", 0, -y); h:SetWidth(width)
			h.txt:SetText(boss)
			h:Show()
			y = y + 18 + 4
		end

		ri = ri + 1
		local r = rowAt(ri)
		local iname, _, rarity, _, _, _, _, _, _, tex = GetItemInfo(it.id)
		if not iname then
			cold = true
			if Okanvil.WarmItem then Okanvil:WarmItem(it.id) end
		end
		r.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
		local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[rarity or 4]
		local code = qc and qc.hex or "|cffa335ee"
		r.name:SetText(code .. (iname or it.name or ("item " .. it.id)) .. "|r")

		-- tonight: won by whom / dropped / nothing yet
		local s = st[it.id]
		if s and #s.won > 0 then
			local w = {}
			for _, who in ipairs(s.won) do
				local e
				for _, x in ipairs(SR.For(it.id)) do if x.key == who:lower() then e = x end end
				w[#w + 1] = classColor(e and e.class) .. who .. "|r"
			end
			r.status:SetText("|cff7cfc8awon|r " .. table.concat(w, ", "))
		elseif s then
			r.status:SetText("|cffffd200dropped" .. (s.n > 1 and (" x" .. s.n) or "") .. "|r")
		else
			r.status:SetText("")
		end

		local names = {}
		for _, e in ipairs(SR.For(it.id)) do
			local n = e.name .. (e.count > 1 and (" x" .. e.count) or "")
			if grouped and not here[e.key] then
				names[#names + 1] = "|cff5e6166" .. n .. "|r"
				missing[e.key] = true
			else
				names[#names + 1] = classColor(e.class) .. n .. "|r"
			end
		end
		r.who:SetText(table.concat(names, "|cff6f7176, |r"))

		local rh = math.max(ICON + 6, 3 + (r.name:GetStringHeight() or 12) + 3 + (r.who:GetStringHeight() or 10) + 6)
		r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(width); r:SetHeight(rh)
		r:Show()
		y = y + rh + 2
	end
	f._cold = cold

	local nMissing = 0
	for _ in pairs(missing) do nMissing = nMissing + 1 end
	local ni, np = #items, nPlayers or 0
	f.count:SetText(("%d item%s, %d raider%s"):format(ni, ni == 1 and "" or "s", np, np == 1 and "" or "s")
		.. (nMissing > 0 and (" |cffff7070(" .. nMissing .. " not here)|r") or ""))

	f.child:SetHeight(math.max(1, y))
	local h = math.min(MAX_H, math.max(MIN_H, HDR_H + 6 + y + PAD))
	f:SetHeight(h)
	local view = h - (HDR_H + 6) - PAD
	local maxScroll = math.max(0, y - view)
	f.sb:SetMinMaxValues(0, maxScroll)
	if f.sb:GetValue() > maxScroll then f.sb:SetValue(maxScroll) end
	if maxScroll > 0 then f.sb:Show() else f.sb:Hide(); f.sf:SetVerticalScroll(0) end
end

-- Whether the panel may show at all: master looter, a list loaded, and the
-- mini roll on screen to sit beside.
local function allowed()
	local rm = rollWin()
	return isML() and SR.Summary() ~= nil and rm and rm:IsShown()
end

function P.Show()
	pref().panel = true
	if not allowed() then return end
	build()
	dock()
	panel:Show()
	P.Refresh()
end

-- `forget`: closed by the user, so it stays closed next time. Hidden because
-- the mini roll went away, it comes back with it.
function P.Hide(forget)
	if forget then pref().panel = nil end
	if panel then panel:Hide() end
end

function P.Toggle()
	if panel and panel:IsShown() then P.Hide(true) else P.Show() end
end

function P.IsOpen() return panel and panel:IsShown() or false end

-- Put the panel where the preference and the state say it should be. The mini
-- roll calls this whenever it shows or rebuilds.
function P.Sync()
	if pref().panel and allowed() then P.Show() else P.Hide(false) end
end

SR.onPanel = function()
	local RM = Okanvil.RollMgr
	if RM and RM.SyncSRButton then RM.SyncSRButton() end
	P.Sync()
end

-- Every repaint of the mini roll is a moment the loot changed (a drop, a
-- roll, an award), so this repaints with it.
do
	local RM = Okanvil.RollMgr
	if RM and RM.Refresh then
		local base = RM.Refresh
		RM.Refresh = function(...)
			base(...)
			P.Refresh()
		end
	end
end

SLASH_OKRES1 = "/okres"
SlashCmdList["OKRES"] = function()
	if not isML() then Okanvil:Print("Soft reserves: only the master looter has this list."); return end
	if not SR.Summary() then Okanvil:Print("Soft reserves: none loaded -- paste the CSV on the Loot page."); return end
	local rm = rollWin()
	if not (rm and rm:IsShown()) and Okanvil.RollMgr and Okanvil.RollMgr.Toggle then Okanvil.RollMgr.Toggle() end
	P.Toggle()
end
