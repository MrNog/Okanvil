-- ============================================================
-- Okanvil -- UI: Loot page
-- Split out of the old monolithic Core/UI.lua. Loads after Core/UI/Shell.lua,
-- which publishes the shared helpers on Okanvil.UI (see that file).
-- ============================================================

local Okanvil = Okanvil
local W   = Okanvil.W
local C   = Okanvil.Colors
local LSM = Okanvil.LSM
local FLAT           = Okanvil.UI.FLAT
local u3             = Okanvil.UI.u3
local newFillPanel   = Okanvil.UI.newFillPanel
local newScrollPanel = Okanvil.UI.newScrollPanel

-- ONE page for loot, three tabs:
--   Loot      tonight's setup: your picks, the loot mode tiles and what the
--             picked mode needs (the council's panel under Council), the
--             master looter's speed-run fields
--   History   what dropped and who got it
--   Priority  the ladder pasted from the site (officers)
-- None of it is used DURING the raid: that is the mini roll, which the header
-- opens.
--
-- Officer or not is read once, at build: the shell rebuilds this page when the
-- guild roster changes the answer (InvalidatePanel(LOOT)).
function Okanvil:BuildLoot()
	local L = Okanvil.Loot
	local CC = Okanvil.Council
	local fill = newFillPanel()
	local host = fill.child
	Okanvil._lootFill = fill   -- set BEFORE the tab builders run (they read it)
	local officer = Okanvil.U and Okanvil.U.canSeePrio and Okanvil.U.canSeePrio() and true or false

	-- Tonight's setup: the speed-run block (officers / ML), the loot mode tiles,
	-- and what the picked mode needs below them.
	local function buildBody(main)
		-- a section heading: dim caps and a hairline, like the settings pages
		local function heading(anchor, text, gap)
			local h = CreateFrame("Frame", nil, main)
			h:SetPoint("TOPLEFT", anchor, anchor == main and "TOPLEFT" or "BOTTOMLEFT", 0, -(gap or 0))
			h:SetPoint("TOPRIGHT", anchor, anchor == main and "TOPRIGHT" or "BOTTOMRIGHT", 0, -(gap or 0))
			h:SetHeight(26)
			W.Section(h, text, 12, -6)
			return h
		end

		-- ---- YOUR PICKS: the soft reserves and the wish you sent, as item cards.
		-- Shown to everyone; folds away when you have sent nothing.
		local picksHead = heading(main, "YOUR PICKS", 4)
		local picks = CreateFrame("Frame", nil, main)
		picks:SetPoint("TOPLEFT", picksHead, "BOTTOMLEFT", 0, 0)
		picks:SetPoint("TOPRIGHT", picksHead, "BOTTOMRIGHT", 0, 0)
		picks.cards = {}
		local CARD_H, GAP = 64, 8

		local function bossOf(id)
			for _, raid in pairs(OkanvilRaidLoot or {}) do
				for _, bb in ipairs(raid) do
					for _, it in ipairs(bb.items or {}) do if it.id == id then return bb.boss end end
				end
			end
		end

		local function card(i)
			local c = picks.cards[i]
			if c then return c end
			c = W.Frame(picks, "soft")
			c:SetHeight(CARD_H)
			c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(38, 38); c.icon:SetPoint("LEFT", 9, 0)
			c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			c.kind = W.Text(c, "", "note"); c.kind:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, 1)
			c.name = W.Text(c, "", "body"); c.name:SetPoint("TOPLEFT", c.kind, "BOTTOMLEFT", 0, -3)
			c.name:SetPoint("RIGHT", c, "RIGHT", -8, 0); c.name:SetJustifyH("LEFT")
			c.sub = W.Text(c, "", "note", "dim"); c.sub:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -3)
			c.sub:SetPoint("RIGHT", c, "RIGHT", -8, 0); c.sub:SetJustifyH("LEFT")
			for _, fs in ipairs({ c.name, c.sub }) do if fs.SetWordWrap then fs:SetWordWrap(false) end end
			-- your wish on this raid ID opens the wish window again, until the list is locked
			c:EnableMouse(true)
			c:SetScript("OnMouseUp", function(s)
				local Wi = Okanvil.Wish
				if s._changeable and Wi and Wi.OpenMine then Wi.OpenMine() end
			end)
			picks.cards[i] = c
			return c
		end

		-- "ICC 10 · ID 48213", or "ICC 10 · no ID yet" before the first kill
		local function idLabel(set)
			local SR = Okanvil.SoftRes
			local key, size = set.lockKey:match("^(%a+)(%d+):")
			local raid = (key and SR and SR.RaidLabel) and SR.RaidLabel({ key = key, size = tonumber(size) }) or ""
			return raid .. "  ·  " .. (set.id and ("ID " .. set.id) or "no ID yet")
		end

		-- what the picked loot mode uses: Council your wish, SR your soft
		-- reserves (one row per raid ID), Roll nothing
		local function paintMine()
			local SR = Okanvil.SoftRes
			local mode = SR and SR.Mode and SR.Mode()
			local want = (mode == "council" and "wish") or (mode == "sr" and "sr") or nil
			-- a wish sent before the first kill moves to the raid ID first
			if Okanvil.Wish and Okanvil.Wish.Key then Okanvil.Wish.Key() end
			local sets = {}
			for _, set in ipairs(want and SR.MyPickSets and SR.MyPickSets() or {}) do
				if set.kind == want then sets[#sets + 1] = set end
			end
			local list = {}
			local w = picks:GetWidth() or 0
			for rowI, set in ipairs(sets) do
				local n = #set.list
				local cw = math.floor((w - 24 - GAP * (n - 1)) / n)
				for j, id in ipairs(set.list) do
					list[#list + 1] = { id = id, wish = set.kind == "wish", set = set, row = rowI, col = j, cw = cw }
				end
			end
			local nRows = #sets
			for i = 1, math.max(#list, #picks.cards) do
				local e, c = list[i], picks.cards[i]
				if e then
					c = card(i)
					c:ClearAllPoints()
					c:SetPoint("TOPLEFT", 12 + (e.col - 1) * (e.cw + GAP), -4 - (e.row - 1) * (CARD_H + GAP))
					c:SetWidth(e.cw)
					local name, _, q, _, _, _, _, _, _, tex = GetItemInfo(e.id)
					c.icon:SetTexture(tex or (GetItemIcon and GetItemIcon(e.id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
					local r, g, bl = GetItemQualityColor(q or 4)
					c.name:SetText(name or ("item " .. e.id)); c.name:SetTextColor(r, g, bl)
					c.kind:SetText((e.wish and "|cffe0b860WISH|r" or "|cff8a8d93SOFT RESERVE|r")
						.. "  |cff6f7176" .. idLabel(e.set) .. "|r")
					local Wi = Okanvil.Wish
					c._changeable = e.wish and Wi and Wi.Accepting() and e.set.lockKey == Wi.Key() or false
					c.sub:SetText((bossOf(e.id) or "") .. (c._changeable and "  |cff8a8d93·  click to change|r" or ""))
					-- the wish wears the gold edge it has on the council board
					if e.wish then c:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
					else c:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end
					c:Show()
				elseif c then
					c:Hide()
				end
			end
			if nRows > 0 then
				picksHead:Show(); picksHead:SetHeight(26); picks:SetHeight(nRows * (CARD_H + GAP) + 2)
			else
				picksHead:Hide(); picksHead:SetHeight(1); picks:SetHeight(1)
			end
		end
		picks:SetScript("OnShow", paintMine)
		picks:SetScript("OnSizeChanged", paintMine)
		paintMine()
		Okanvil.Loot_PaintMine = paintMine

		-- ---- LOOT MODE: three tiles, one lit, and what the lit mode needs
		local modesHead = heading(picks, "LOOT MODE", 8)
		local modes = CreateFrame("Frame", nil, main)
		modes:SetPoint("TOPLEFT", modesHead, "BOTTOMLEFT", 12, -2)
		modes:SetPoint("TOPRIGHT", modesHead, "BOTTOMRIGHT", -12, -2)
		Okanvil:Loot_BuildModes(modes)

		local srp = W.Frame(main, "page")
		srp:SetPoint("TOPLEFT", modes, "BOTTOMLEFT", -12, -10)
		srp:SetPoint("TOPRIGHT", modes, "BOTTOMRIGHT", 12, -10)
		Okanvil:Loot_BuildSoftRes(srp)

		-- ---- MASTER LOOT: the speed-run block, for whoever is master looter right
		-- now (an officer or a pug leader sweeping loot)
		local mlHead = heading(srp, "MASTER LOOT", 14)
		local top = W.Frame(main, "page")
		top:SetPoint("TOPLEFT", mlHead, "BOTTOMLEFT", 0, 0)
		top:SetPoint("TOPRIGHT", mlHead, "BOTTOMRIGHT", 0, 0)
		top:SetHeight(128)
		Okanvil:Loot_BuildCollectors(top)

		-- The page scrolls: its height is wherever the last block ends, measured
		-- a frame after anything grows or shrinks (the speed-run fields, the SR
		-- list, the picks), when the anchors have settled.
		local measurer = CreateFrame("Frame", nil, main)
		measurer:Hide()
		measurer:SetScript("OnUpdate", function(self)
			self:Hide()
			local t, b = main:GetTop(), top:GetBottom()
			if not (t and b) then return end
			local sf = main:GetParent()
			local view = sf and sf.GetHeight and sf:GetHeight() or 0
			main:SetHeight(math.max(t - b + 16, view))
			if sf and sf._relayout then sf._relayout() end
		end)
		local function remeasure() measurer:Show() end
		Okanvil.Loot_Remeasure = remeasure

		local function applyTop()
			-- only the master looter sweeps loot: an officer who is not ML has nothing to set here
			local show = L.IsMasterLooter and L.IsMasterLooter()
			local on = L.CollectorsEnabled and L.CollectorsEnabled()
			if top.fields then if on then top.fields:Show() else top.fields:Hide() end end
			if show then
				mlHead:Show(); top:Show(); top:SetHeight(on and 148 or 50)
			else
				mlHead:Hide(); top:Hide(); top:SetHeight(1)
			end
			remeasure()
		end
		applyTop()
		fill.applyTop = applyTop
		top.onToggle = applyTop
		main:HookScript("OnShow", remeasure)
		local basePaint = Okanvil.Loot_PaintMine
		Okanvil.Loot_PaintMine = function() basePaint(); remeasure() end
	end

	-- What dropped and who got it, on its own tab.
	local function buildHistory(main)
		local hist = W.Frame(main, "page")
		hist:SetPoint("TOPLEFT", 0, 0)
		hist:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, 0)
		Okanvil:Loot_BuildHistory(hist)
	end

	-- Loot (tonight's setup) and History for everyone; Priority for officers.
	local tabs = {
		{ key = "loot", label = "Loot mode", icon = "Interface\\Icons\\INV_Misc_Bag_08", height = 400, build = buildBody },
		{ key = "history", label = "History", icon = "Interface\\Icons\\INV_Scroll_03", height = 400, fill = true, build = buildHistory },
	}
	if officer then
		tabs[#tabs + 1] = { key = "prio", label = "Priority", icon = "Interface\\Icons\\INV_Misc_Book_09", height = 400, fill = true,
			build = function(pg) Okanvil:Loot_BuildPrio(pg) end }
	end

	local function takeML()
		if not (L and L.SetMeAsMasterLooter) then return end
		local function take()
			local r = L.SetMeAsMasterLooter()
			if r == "nogroup" then
				Okanvil:Print("|cffff5555You're not in a party or raid -- nothing to set.|r")
			elseif r == "notleader" then
				Okanvil:Print("|cffff5555Only the group leader can set the loot method.|r")
			elseif r == "noapi" then
				Okanvil:Print("|cffff5555SetLootMethod unavailable.|r")
			else
				Okanvil:Print("Loot method set to |cffffd200master|r -- you are the Master Looter.")
			end
			if fill and fill.refreshAll then fill.refreshAll() end
		end
		-- Someone else already holds master loot: taking it mid-raid is almost
		-- always a misclick by a second officer, so it asks first.
		local who = L.MasterLooterName and L.MasterLooterName()
		if who and who ~= "" then
			Okanvil:Confirm("|cffffd200" .. who .. "|r is the master looter.\n"
				.. "Take master loot from them?", "Take master loot", take)
		else
			take()
		end
	end

	-- Dashboard shell: header (icon + title + ML status + buttons), no drawer and
	-- no footer -- so a page gets the window's full width.
	local dash = W.Dashboard(host, {
		title = "Loot",
		settingsTab = "loot",
		subtitle = "Set up before the raid. During it, use the mini roll.",
		icon = Okanvil.ICONS.loot,
		drawerWidth = 0,
		footerHeight = 0,
		primaryText = function() return "Open mini roll" end,
		onPrimary = function()
			if Okanvil.RollMgr and Okanvil.RollMgr.Toggle then Okanvil.RollMgr.Toggle()
			else Okanvil:Print("Roll manager not loaded.") end
		end,
		-- "Set me as ML" -- only shown when you're the leader and NOT already ML.
		tertiaryText = function() return "Set me as ML" end,
		tertiaryShown = function()
			if not (L and L.CanSetLootMethod and L.CanSetLootMethod()) then return false end
			return not (L.IsMasterLooter and L.IsMasterLooter())
		end,
		onTertiary = takeML,
		statusText = function()
			if L and L.IsMasterLooter and L.IsMasterLooter() then
				return "|cffffd200Master Looter|r"
			end
			-- name WHO the ML is, instead of only saying it isn't you -- that's the
			-- useful half of the answer when loot won't auto-give.
			local who = L and L.MasterLooterName and L.MasterLooterName()
			if who and who ~= "" then
				return "|cff8a8d93ML:|r |cffffd200" .. who .. "|r"
			end
			-- Solo there is no loot method to speak of: say nothing rather than a
			-- red warning about a normal state.
			local grouped = (GetNumRaidMembers and GetNumRaidMembers() > 0)
				or (GetNumPartyMembers and GetNumPartyMembers() > 0)
			return grouped and "|cff8a8d93not master loot|r" or ""
		end,
		-- the tabs are pills over one body
		pills = true,
		tabs = tabs,
		-- the council's panel repaints the header while the tabs are being built
		onReady = function(d) fill.dash = d end,
	})
	fill.dash = dash

	-- refresh when loot changes / the page shows / loot method changes
	local function refreshAll()
		if fill.applyTop then fill.applyTop() end
		dash:Refresh()
		if fill._rebuildHistory then fill._rebuildHistory() end
	end
	fill.refreshAll = refreshAll
	-- CHAINED, never replaced: the mini roll hooks onLoot at login, and this page
	-- is built later, the first time it is opened. Assigning over it cut the mini
	-- roll off from every loot change for the rest of the session. The page can be
	-- rebuilt, so the chain is installed once and calls whichever page is current.
	Okanvil._lootPageRefresh = function() if fill:IsShown() then refreshAll() end end
	if not Okanvil._lootPageHooked then
		Okanvil._lootPageHooked = true
		local prev = L.onLoot
		L.onLoot = function()
			if prev then prev() end
			if Okanvil._lootPageRefresh then Okanvil._lootPageRefresh() end
		end
	end
	if not fill._mlEv then
		fill._mlEv = CreateFrame("Frame")
		fill._mlEv:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
		fill._mlEv:RegisterEvent("RAID_ROSTER_UPDATE")
		fill._mlEv:RegisterEvent("PARTY_LEADER_CHANGED")
		fill._mlEv:RegisterEvent("PARTY_MEMBERS_CHANGED")
		fill._mlEv:SetScript("OnEvent", function()
			if fill:IsShown() then
				if fill.applyTop then fill.applyTop() end
				dash:Refresh()
			end
		end)
	end
	fill:SetScript("OnShow", function()
		-- An officer who is not the ML asks the ML for the council-night state,
		-- so joining late does not read OFF on a council night.
		if officer and CC and CC.MayRun and not CC.MayRun() and CC.QueryNight then CC.QueryNight() end
		refreshAll()
	end)
	Okanvil._lootFill = fill
	return fill
end

-- ---- Collectors: Main/Frag/BoE targets + the speed-run toggle ----
--
-- Okanvil handles loot three ways; only the THIRD one lives here:
--   1. Need/Greed  -- the game's own roll. Okanvil just records what dropped.
--   2. Master loot -- the normal flow: the Mini Roll Manager runs an MS/OS/Free
--      roll-off, you press Award, confirm the popup, the item goes to the winner.
--   3. Speed-run   -- THIS PAGE. Skips rolling at the pull: the boss is swept into
--      one bag so the raid keeps moving, and loot is settled afterwards by roll or
--      loot council. Every drop is still recorded and broadcast to the raid.
--
-- Arming the toggle silently ships every BoP drop to one player, so the page has
-- to say so -- but in the row's tooltip and in the greyed placeholder of
-- an empty field, not in four paragraphs stacked above the controls.
function Okanvil:Loot_BuildCollectors(p)
	local L = Okanvil.Loot
	local X = 8
	if not (L and L.Collectors) then return end

	local TIP = "Sweeps each boss into one bag so the raid keeps moving, and the loot is "
		.. "settled afterwards by roll or loot council.\n"
		.. "Off: the normal flow -- roll, then Award.\n\n"
		.. "|cffff8000BoP gear|r goes to Main loot.\n"
		.. "|cffffd200Orbs, patterns and BoEs|r go to BoE (or Main, if BoE is empty).\n"
		.. "|cffff5555Legendary fragments|r always ask first.\n\n"
		.. "Leave a field empty and that loot stays on the corpse to be rolled\n"
		.. "normally -- nothing is ever swept to anyone you did not name.\n"
		.. "Every drop is recorded in the history and shown to the raid either way."

	-- One setting row; the three name fields only appear while it is ON, so a
	-- page with speed-run off is just the history.
	local en = W.ToggleRow(p, "Speed-run auto master-loot",
		"Sweeps each boss into one bag -- only while you are master looter",
		function() return L.CollectorsEnabled() end,
		function(v) L.SetCollectorsEnabled(v); if p.onToggle then p.onToggle() end end)
	en:SetPoint("TOPLEFT", X, -2)
	en:SetPoint("RIGHT", p, "RIGHT", -X, 0)
	en:Tooltip(TIP)
	-- the fields hang off one host, so hiding it hides all three rows
	local fields = CreateFrame("Frame", nil, p)
	fields:SetAllPoints(p)
	p.fields = fields

	local col = L.Collectors()
	-- The three buttons sit at the RIGHT edge and the field stretches to meet them,
	-- so the name has room and the row reads as one control instead of a short box
	-- adrift in empty space.
	local function row(bucket, label, y, emptyNote)
		local lb = W.Text(fields, label, "label"); lb:SetPoint("TOPLEFT", X, y - 4); lb:SetWidth(112); lb:SetJustifyH("LEFT")
		if lb.SetWordWrap then lb:SetWordWrap(false) end

		local cl = W.Button(fields, "Clear", "danger"); cl:SetSize(48, 24)
		cl:SetPoint("TOPRIGHT", p, "TOPRIGHT", -X, y)
		local tg = W.Button(fields, "Target"); tg:SetSize(56, 24); tg:SetPoint("RIGHT", cl, "LEFT", -6, 0)
		local sf = W.Button(fields, "Self"); sf:SetSize(48, 24); sf:SetPoint("RIGHT", tg, "LEFT", -4, 0)

		local eb = W.EditBox(fields, function(t) L.SetCollector(bucket, t) end)
		eb:SetHeight(24)
		eb:SetPoint("LEFT", lb, "RIGHT", 8, 0)
		eb:SetPoint("RIGHT", sf, "LEFT", -6, 0)
		eb.edit:SetText(col[bucket] or "")

		-- An empty field says what an empty field DOES, inside the field itself --
		-- greyed, and gone the moment there is a real name in it. That sentence used
		-- to live in a paragraph above the rows, which is where nobody read it.
		local ph = W.Text(fields, "|cff6f7176" .. emptyNote .. "|r", "note", "dim")
		ph:SetPoint("LEFT", eb, "LEFT", 8, 0)
		local function paintPH()
			local v = eb.edit:GetText() or ""
			if v == "" and not eb.edit:HasFocus() then ph:Show() else ph:Hide() end
		end

		local function setName(n)
			if not n or n == "" then return end
			n = n:gsub("%-.*$", ""); eb.edit:SetText(n); L.SetCollector(bucket, n); paintPH()
		end
		eb.edit:HookScript("OnTextChanged", paintPH)
		eb.edit:HookScript("OnEditFocusGained", paintPH)
		eb.edit:HookScript("OnEditFocusLost", paintPH)

		if sf.text then sf.text:SetText("|cffffd200Self|r") end
		sf:SetScript("OnClick", function() setName(UnitName("player")) end)
		tg:SetScript("OnClick", function()
			local n = UnitName("target")
			if n and UnitIsPlayer("target") then setName(n) else Okanvil:Print("Target a player first.") end
		end)
		cl:SetScript("OnClick", function() eb.edit:SetText(""); L.SetCollector(bucket, ""); paintPH() end)
		paintPH()
	end
	row("main", "Main loot (BoP)", -52, "-- stays on the corpse --")
	row("frag", "Fragments",       -84, "-- stays on the corpse --")
	row("boe",  "BoE / orbs",      -116, "-- falls back to Main loot --")

	-- The "whisper the winner" toggle used to sit here, with the message it sends
	-- on a different page entirely -- so neither half said anything about the
	-- other. Both are in Settings > Loot now, as one control.
end

-- ---- Loot mode: three big tiles ----
--
-- One click picks how tonight's loot is shared out (SoftRes.lua, SR.Mode).
-- The lit tile is the mode; with none picked it is Roll.
local MODE_TILES = {
	{ mode = "council", title = "Council", sub = "Officers decide" },
	{ mode = "sr",      title = "SR",      sub = "Soft reserves" },
	{ mode = "roll",    title = "Roll",    sub = "MS / OS" },
}
local MODE_TILE_H, MODE_TILE_GAP = 54, 8

function Okanvil:Loot_BuildModes(p)
	local SR = Okanvil.SoftRes
	p:SetHeight(MODE_TILE_H)
	if not (SR and SR.SetMode) then p:SetHeight(1); return end
	local C = Okanvil.Colors
	local tiles = {}

	local function paint()
		local cur = SR.Mode()
		local can = not SR.CanSetMode or SR.CanSetMode()
		local setter = SR.ModeSetter and SR.ModeSetter()
		-- who set it, for everyone who cannot: on the lit tile, under its name
		local by = (not can and setter) and ("  |cff8a8d93·  set by|r |cffe0b860" .. setter .. "|r") or ""
		for _, t in ipairs(tiles) do
			t.sub:SetText(t._sub .. (t._mode == cur and by or ""))
			t:EnableMouse(can)
			t:SetAlpha((can or t._mode == cur) and 1 or 0.55)
			local on = t._mode == cur
			-- the picked tile: a gold edge all the way round and a warm fill
			if on then
				t:SetBackdropColor(C.accentD[1], C.accentD[2], C.accentD[3], 0.55)
				t:SetBackdropBorderColor(1, 0.82, 0, 0.9)
				t.title:SetTextColor(C.accentText[1], C.accentText[2], C.accentText[3])
				t.sub:SetTextColor(C.text[1], C.text[2], C.text[3])
			else
				t:SetBackdropColor(C.panelD[1], C.panelD[2], C.panelD[3], 0.85)
				t:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1)
				t.title:SetTextColor(C.text[1], C.text[2], C.text[3])
				t.sub:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
			end
		end
	end

	for i, def in ipairs(MODE_TILES) do
		local t = CreateFrame("Button", nil, p)
		t._mode, t._sub = def.mode, def.sub
		t:SetHeight(MODE_TILE_H)
		Okanvil:Skin(t, "dark")
		t.title = W.Text(t, def.title, "head")
		t.title:SetPoint("TOPLEFT", 16, -11)
		t.sub = W.Text(t, def.sub, "note")
		t.sub:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -4)
		t:SetScript("OnClick", function(s) SR.SetMode(s._mode) end)
		tiles[i] = t
	end

	-- Equal columns; re-laid out whenever the page width changes.
	local function layout()
		local w = p:GetWidth() or 0
		if w <= 0 then return end
		local tw = (w - MODE_TILE_GAP * (#tiles - 1)) / #tiles
		for i, t in ipairs(tiles) do
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", p, "TOPLEFT", (i - 1) * (tw + MODE_TILE_GAP), 0)
			t:SetWidth(tw)
		end
	end
	p:SetScript("OnSizeChanged", layout)
	p:SetScript("OnShow", function() layout(); paint() end)
	layout()
	paint()

	Okanvil._paintModes = paint
end

-- ---- Soft reserves: what the picked mode needs, nothing else ----
--
-- SR: the counts and whether whispers are taken, then reserves per player and
-- the actions. The list itself is in the mini roll's SR panel; Import CSV opens
-- the paste box here until the import is done.
-- Council: the council's own panel. Roll: one quiet line -- nothing to set.
-- The roll call's wording lives in Settings > Loot with the other templates.
local SR_LINE1_H, SR_LINE2_H, SR_PASTE_H = 42, 40, 118
function Okanvil:Loot_BuildSoftRes(p)
	local SR = Okanvil.SoftRes
	p:SetHeight(40)
	if not SR then return end
	local C = Okanvil.Colors
	local X = 12

	local quiet = W.Text(p, "", "body", "dim")
	quiet:SetPoint("TOPLEFT", X, -13)

	-- Council: the council's own panel, built the first time it is needed.
	local cn = CreateFrame("Frame", nil, p)
	cn:SetPoint("TOPLEFT"); cn:SetPoint("TOPRIGHT")
	cn:Hide()

	-- Which raid the window shows raiders: the one you are in, or picked here.
	local function raidButton(parent)
		local b = W.Button(parent, "ICC 25"); b:SetSize(96, 22)
		b.listFn = function()
			local out = {}
			for _, r in ipairs(OkanvilRaids or {}) do
				for _, size in ipairs(r.sizes or { 10, 25 }) do
					out[#out + 1] = { text = SR.RaidLabel({ key = r.key, size = size }), value = r.key .. ":" .. size .. ":0" }
				end
			end
			return out
		end
		b.setFn = function(v)
			local key, size, hc = v:match("^(%w+):(%d+):(%d)$")
			if not key then return end
			size, hc = tonumber(size), hc == "1"
			local cur = SR.Raid()
			if cur.key == key and cur.size == size and (cur.hc and true or false) == hc then return end
			-- a reserve list belongs to one raid: another raid starts from nothing
			if SR.Summary() then
				Okanvil:Confirm("Change to " .. SR.RaidLabel({ key = key, size = size, hc = hc })
					.. "?\n|cff8a8d93The current soft-reserve list is cleared.|r", "Change raid",
					function() SR.Clear(); SR.SetRaid(key, size, hc) end)
			else
				SR.SetRaid(key, size, hc)
			end
		end
		b:SetScript("OnClick", function(s)
			if SR.RaidHere and SR.RaidHere() then return end   -- inside, it is the raid you are in
			if W.OpenMenu then W.OpenMenu(s) end
		end)
		b:Tooltip("The raid whose loot raiders pick from.\nInside a raid it is always that raid.")
		b.Sync = function() if SR.RaidLabel then b.text:SetText(SR.RaidLabel()) end end
		return b
	end

	local sr = CreateFrame("Frame", nil, p)
	sr:SetPoint("TOPLEFT"); sr:SetPoint("BOTTOMRIGHT")

	local function hair(y)
		local t = sr:CreateTexture(nil, "BORDER")
		t:SetTexture(FLAT); t:SetVertexColor(1, 1, 1, 0.06); t:SetHeight(1)
		t:SetPoint("TOPLEFT", 1, y); t:SetPoint("TOPRIGHT", -1, y)
		return t
	end

	-- line 1: counts, whisper state
	local nItems = W.Text(sr, "0", 20); nItems:SetPoint("TOPLEFT", X, -10)
	nItems:SetTextColor(C.accentText[1], C.accentText[2], C.accentText[3])
	local lItems = W.Text(sr, "items", "label", "dim"); lItems:SetPoint("BOTTOMLEFT", nItems, "BOTTOMRIGHT", 5, 2)
	local nRaid = W.Text(sr, "0", 20); nRaid:SetPoint("BOTTOMLEFT", lItems, "BOTTOMRIGHT", 16, -2)
	nRaid:SetTextColor(C.accentText[1], C.accentText[2], C.accentText[3])
	local lRaid = W.Text(sr, "raiders", "label", "dim"); lRaid:SetPoint("BOTTOMLEFT", nRaid, "BOTTOMRIGHT", 5, 2)
	local lockB = W.Button(sr, "Lock"); lockB:SetSize(70, 22); lockB:SetPoint("TOPRIGHT", -X, -10)
	lockB:SetScript("OnClick", function() SR.SetIntake(not SR.IntakeOpen()) end)
	lockB:Tooltip("Open: \"sr [item]\" whispers are saved and answered.\nLocks by itself at the first pull in a raid.")
	local wState = W.Text(sr, "", "label"); wState:SetPoint("RIGHT", lockB, "LEFT", -10, 0)
	hair(-SR_LINE1_H)

	-- line 2: per player, actions
	local y2 = -SR_LINE1_H - 9
	local pp = W.Text(sr, "Per player", "label", "dim"); pp:SetPoint("TOPLEFT", X, y2 - 4)
	local seg = {}
	for n = 1, 3 do
		local b = W.Button(sr, tostring(n)); b:SetSize(26, 22)
		b:SetPoint("LEFT", n == 1 and pp or seg[n - 1], "RIGHT", n == 1 and 10 or 2, 0)
		b:SetScript("OnClick", function() SR.SetLimit(n) end)
		seg[n] = b
	end
	local srRaidB = raidButton(sr); srRaidB:SetPoint("LEFT", seg[3], "RIGHT", 14, 0)
	-- no "post the list" button: a whole list in raid chat is spam; it lives in the mini roll
	local postB = W.Button(sr, "Post rules", "primary"); postB:SetSize(84, 22); postB:SetPoint("TOPRIGHT", -X, y2)
	postB:SetScript("OnClick", function()
		-- the rules go to raid chat for everyone; raiders with Okanvil also get
		-- the pick window, so they do not have to whisper
		if SR.PostPick then SR.PostPick() end
		SR.PostOpen()
	end)
	postB:Tooltip("Tells the raid how to reserve (\"whisper me sr [item]\")\nand opens the pick window for raiders with Okanvil.")
	local impB = W.Button(sr, "Import CSV"); impB:SetSize(84, 22); impB:SetPoint("RIGHT", postB, "LEFT", -6, 0)
	impB:Tooltip("Load the list from softres.it:\nExport > CSV > Copy to Clipboard, then paste.")
	local clrB = W.Button(sr, "Clear"); clrB:SetSize(56, 22); clrB:SetPoint("RIGHT", impB, "LEFT", -6, 0)
	clrB:SetScript("OnClick", function()
		Okanvil:Confirm("Clear the soft reserves?", "Clear", function() SR.Clear() end)
	end)
	hair(-SR_LINE1_H - SR_LINE2_H)

	-- a pointer to the list, or the paste box in its place
	local top = -SR_LINE1_H - SR_LINE2_H
	local more = W.Text(sr, "", "note", "dim")

	local paste = CreateFrame("Frame", nil, sr)
	paste:SetPoint("TOPLEFT", 0, top); paste:SetPoint("TOPRIGHT", 0, top); paste:SetHeight(SR_PASTE_H)
	local box = W.MultiEdit(paste)
	box:SetPoint("TOPLEFT", X, -8); box:SetPoint("TOPRIGHT", -X, -8); box:SetHeight(76)
	local doImp = W.Button(paste, "Import", "primary"); doImp:SetSize(80, 22)
	doImp:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -6)
	local cancel = W.Button(paste, "Cancel"); cancel:SetSize(70, 22); cancel:SetPoint("RIGHT", doImp, "LEFT", -6, 0)
	paste:Hide()

	local pasting = false
	local paint
	impB:SetScript("OnClick", function() pasting = not pasting; paint() end)
	cancel:SetScript("OnClick", function() pasting = false; box:SetText(""); box.edit:ClearFocus(); paint() end)
	doImp:SetScript("OnClick", function()
		local ni, np = SR.Import(box:GetText())
		if not ni then Okanvil:Print("|cffff5555" .. tostring(np) .. "|r"); return end
		Okanvil:Print(("Soft reserves loaded: %d items, %d raiders."):format(ni, np)
			.. (SR.CanShare() and " Sent to the raid." or ""))
		box:SetText(""); box.edit:ClearFocus()
		pasting = false
		paint()
	end)

	paint = function()
		local mode = SR.Mode()
		local srMode = SR.WhisperMode and SR.WhisperMode()
		local CC = Okanvil.Council
		if mode == "council" and CC and CC.BuildRunTab and CC.Enabled and CC.Enabled() then
			sr:Hide(); quiet:Hide()
			if not cn.built then CC.BuildRunTab(cn); cn.built = true end
			if cn.refresh then cn.refresh() end
			cn:SetHeight(cn.needH or 140)
			cn:Show()
			p:SetHeight(cn.needH or 140)
			return
		end
		cn:Hide()
		if not srMode then
			sr:Hide(); quiet:Show()
			quiet:SetText(mode == "council" and "Loot council is off for this character (Modules)."
				or "MS / OS for everything. Nothing to set here.")
			p:SetHeight(40)
			return
		end
		quiet:Hide(); sr:Show()

		local ni, np = SR.Summary()
		nItems:SetText(tostring(ni or 0)); nRaid:SetText(tostring(np or 0))
		local open = SR.IntakeOpen()
		wState:SetText(open and "|cffffd200Whispers open|r" or "|cff8a8d93Whispers locked|r")
		lockB.text:SetText(open and "|cffff5555Lock|r" or "Open")
		for n, b in ipairs(seg) do b:SetKind(n == SR.Limit() and "primary" or nil) end
		srRaidB.Sync()
		if ni then clrB:Show() else clrB:Hide() end

		local h = SR_LINE1_H + SR_LINE2_H
		if pasting then
			more:Hide()
			paste:Show()
			impB.text:SetText("Close")
			h = h + SR_PASTE_H
		else
			paste:Hide()
			impB.text:SetText("Import CSV")
			more:ClearAllPoints()
			more:SetPoint("TOPLEFT", X, -h - 6)
			more:SetText(ni and "The list is in the mini roll: SR button."
				or "Nothing reserved yet. Raiders whisper you:  sr [item]")
			more:Show()
			h = h + 24
		end
		p:SetHeight(h + 4)
	end

	SR.onChange = function()
		paint()
		-- your own reserves show in YOUR PICKS
		if Okanvil.Loot_PaintMine then pcall(Okanvil.Loot_PaintMine) end
		if Okanvil._paintModes then Okanvil._paintModes() end
		if Okanvil.RollMgr and Okanvil.RollMgr.Refresh then Okanvil.RollMgr.Refresh() end
		-- the mini roll's SR button and panel follow the mode
		if Okanvil.RollMgr and Okanvil.RollMgr.SyncSRButton then Okanvil.RollMgr.SyncSRButton() end
		if Okanvil.SoftResPanel and Okanvil.SoftResPanel.Sync then Okanvil.SoftResPanel.Sync() end
		if Okanvil.Loot_Remeasure then Okanvil.Loot_Remeasure() end
	end
	p:SetScript("OnShow", paint)
	paint()
end

-- ---- History (landing/main): one row per session; clicking it opens it in place
-- into one card per boss, one tile per drop -- the same shape as an expanded
-- snapshot on Home. The page itself scrolls; there is no box inside it with a
-- scrollbar of its own.
local CARD_MIN_W, CARD_GAP, CARD_HEAD_H, TILE_H = 310, 8, 24, 24
local MOSAIC_N = 8

-- What a drop's line under the item says: who has it, and how it got there.
local function dropOutcome(L, d)
	if d.de then return "|cff8a5ad9Disenchanted|r" end
	if d.receivedBy and d.receivedBy ~= "" then
		local how = ""
		if d.council then
			how = "council" .. ((d.councilResponse and d.councilResponse ~= "")
				and (" " .. tostring(d.councilResponse):upper()) or "")
		elseif d.rollValue then
			how = (d.rollSpec == "off" and "OS " or "MS ") .. tostring(d.rollValue)
		end
		return L.ClassColorName(d.receivedBy)
			.. (how ~= "" and ("  |cff6f7176" .. how .. "|r") or "")
	end
	-- Under master loot someone carries the drop until it is rolled for; that is
	-- unfinished business, not an award, so it reads in amber.
	if d.heldBy and d.heldBy ~= "" then
		return "|cffe0b860held|r |cffdcddde" .. d.heldBy .. "|r"
	end
	return "|cff5e6166not given yet|r"
end

-- One line for the closed row: how big the night was and what is left to do.
local function sessionSummary(s)
	local bosses, seen, epics, open = 0, {}, 0, 0
	for _, d in ipairs(s.drops or {}) do
		local b = (d.boss and d.boss ~= "") and d.boss or "Trash"
		if not seen[b] then seen[b] = true; bosses = bosses + 1 end
		if (d.rarity or 0) >= 4 then epics = epics + 1 end
		if not d.de and not (d.receivedBy and d.receivedBy ~= "") then open = open + 1 end
	end
	local n = #(s.drops or {})
	if n == 0 then return "|cff8a8d93no drops|r" end
	local parts = {
		("%d boss%s"):format(bosses, bosses == 1 and "" or "es"),
		("%d drop%s"):format(n, n == 1 and "" or "s"),
	}
	if epics > 0 then parts[#parts + 1] = ("|cffa335ee%d epic%s|r|cff8a8d93"):format(epics, epics == 1 and "" or "s") end
	local line = "|cff8a8d93" .. table.concat(parts, "  ·  ") .. "|r"
	if open > 0 then line = line .. ("  |cff8a8d93·|r  |cffe0b860%d not given|r"):format(open) end
	return line
end

function Okanvil:Loot_BuildHistory(main)
	local L = Okanvil.Loot
	local fill = Okanvil._lootFill
	local X = Okanvil.UI.PAD_X

	-- a scroll panel INSIDE main so the sessions list scrolls without resizing
	local p, _, sf, sb = Okanvil.UI.DashScroll(main, X)

	local rows, cards = {}, {}
	local expanded = nil

	local function dropTile(card, i)
		card.tiles = card.tiles or {}
		local t = card.tiles[i]
		if t then return t end
		t = CreateFrame("Button", nil, card)
		t.icon = t:CreateTexture(nil, "ARTWORK")
		t.icon:SetSize(18, 18); t.icon:SetPoint("LEFT", 8, 0)
		t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		-- Winner first, anchored right, so the item name takes whatever is left
		-- and is the one that truncates.
		t.who = W.Text(t, "", "label")
		t.who:SetPoint("RIGHT", t, "RIGHT", -8, 0)
		t.who:SetJustifyH("RIGHT")
		if t.who.SetWordWrap then t.who:SetWordWrap(false) end
		t.name = W.Text(t, "", "label")
		t.name:SetPoint("LEFT", t.icon, "RIGHT", 6, 0)
		t.name:SetPoint("RIGHT", t.who, "LEFT", -8, 0)
		t.name:SetJustifyH("LEFT")
		if t.name.SetWordWrap then t.name:SetWordWrap(false) end
		local hl = t:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(); hl:SetTexture(FLAT)
		hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.08)
		-- Hover for the item, shift-click to link it -- the old list did both.
		t:SetScript("OnEnter", function(self)
			if not self._link then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self._link)
			GameTooltip:Show()
		end)
		t:SetScript("OnLeave", function() GameTooltip:Hide() end)
		t:SetScript("OnClick", function(self)
			if self._link and IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(self._link) end
		end)
		card.tiles[i] = t
		return t
	end

	local function fillTile(t, d)
		t._link = (d.item and d.item ~= "") and d.item or nil
		t.icon:SetTexture(Okanvil:ItemIcon(d.item) or "Interface\\Icons\\INV_Misc_QuestionMark")
		-- The name in its rarity colour without the link's brackets.
		local q = d.rarity and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[d.rarity]
		local hex = q and q.hex or "|cffa335ee"
		local name = (d.name and d.name ~= "") and d.name
			or (t._link and t._link:match("%[(.-)%]")) or "?"
		local qty = (d.qty and d.qty > 1) and ("  |cff8a8d93x" .. d.qty .. "|r") or ""
		t.name:SetText(hex .. name .. "|r" .. qty)
		t.who:SetText(dropOutcome(L, d))
	end

	-- Lays the session's boss cards out below y; returns the y under them.
	local function drawCards(s, y)
		local groups, order = {}, {}
		for _, d in ipairs(s.drops or {}) do
			local b = (d.boss and d.boss ~= "") and d.boss or "Trash"
			if not groups[b] then groups[b] = {}; order[#order + 1] = b end
			local list = groups[b]
			list[#list + 1] = d
		end
		if #order == 0 then return y end
		-- The bosses in the order they died, and whatever came off trash after them.
		for k, b in ipairs(order) do
			if b == "Trash" then
				table.remove(order, k)
				order[#order + 1] = "Trash"
				break
			end
		end

		local width = math.max(CARD_MIN_W, p:GetWidth() - X * 2)
		local cols = math.max(1, math.min(#order,
			math.floor((width + CARD_GAP) / (CARD_MIN_W + CARD_GAP))))
		local cardW = (width - (cols - 1) * CARD_GAP) / cols

		-- Masonry, not rows: each card drops into whichever column is shortest
		-- so far, straight under the card above it. In rows every card waited for
		-- the tallest one beside it, and a 2-drop boss next to a 4-drop one left a
		-- hole the height of the difference. Ties go left, so the kill order still
		-- reads left to right, top to bottom.
		local colY = {}
		for c = 1, cols do colY[c] = y end
		for idx, b in ipairs(order) do
			local col = 1
			for c = 2, cols do
				if colY[c] < colY[col] then col = c end
			end
			local top = colY[col]
			col = col - 1
			local card = cards[idx]
			if not card then
				card = W.Frame(p, "soft")
				card.head = W.Text(card, "", "note", "accent")
				card.head:SetPoint("TOPLEFT", 10, -7)
				card.count = W.Text(card, "", "note", "dim")
				card.count:SetPoint("TOPRIGHT", -10, -7)
				cards[idx] = card
			end
			local list = groups[b]
			local h = CARD_HEAD_H + #list * TILE_H + 4
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", X + col * (cardW + CARD_GAP), -top)
			card:SetSize(cardW, h)
			card.head:SetText(b:upper())
			card.count:SetText(#list .. (#list == 1 and " drop" or " drops"))
			for _, t in ipairs(card.tiles or {}) do t:Hide() end
			for i, d in ipairs(list) do
				local t = dropTile(card, i)
				t:ClearAllPoints()
				t:SetPoint("TOPLEFT", 0, -(CARD_HEAD_H + (i - 1) * TILE_H))
				t:SetSize(cardW, TILE_H)
				fillTile(t, d)
				t:Show()
			end
			card:Show()
			colY[col + 1] = top + h + CARD_GAP
		end
		local bottom = y
		for c = 1, cols do
			if colY[c] > bottom then bottom = colY[c] end
		end
		return bottom + 10 - CARD_GAP
	end

	local function rebuild()
		for _, r in ipairs(rows) do r:Hide() end
		for _, c in ipairs(cards) do c:Hide() end
		-- Runs that never dropped anything (walking through open world, a zone
		-- visited and left) are not listed; a raid shows up with its first drop.
		-- A run with "Keep in history" off is never listed; the mini roll still has
		-- it until the next run starts.
		local sessions = {}
		for _, sess in ipairs((L.Sessions and L.Sessions()) or {}) do
			if sess.drops and #sess.drops > 0 and (not L.IsKept or L.IsKept(sess)) then
				sessions[#sessions + 1] = sess
			end
		end
		local RH = Okanvil.UI.RECORD_ROW_H
		if #sessions == 0 then
			p._empty = p._empty or W.Text(p, "", "body", "dim")
			p._empty:SetPoint("TOPLEFT", X, -4)
			p._empty:SetText("|cff888888No loot logged yet. Kill a boss and open the corpse.|r")
			p._empty:Show(); p:SetHeight(math.max(sf:GetHeight(), 40)); return
		end
		if p._empty then p._empty:Hide() end
		local y = 0
		for i, s in ipairs(sessions) do
			local r = rows[i]
			if not r then
				r = Okanvil.UI.RecordRow(p, function(row)
					if row._s then
						if expanded == row._s then expanded = nil else expanded = row._s end
						rebuild()
					end
				end)
				r.del = W.Button(r, "X", "danger"); r.del:SetSize(24, 22); r.del:SetPoint("RIGHT", -8, 0)
				r.export = W.Button(r, "Export"); r.export:SetSize(72, 22); r.export:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
				-- What dropped, at a glance: the night's items as a strip of
				-- icons, best first, beside the buttons.
				r.mosaic = {}
				for k = 1, MOSAIC_N do
					local m = r:CreateTexture(nil, "ARTWORK")
					m:SetSize(24, 24)
					m:SetTexCoord(0.08, 0.92, 0.08, 0.92)
					if k == 1 then
						m:SetPoint("RIGHT", r.export, "LEFT", -14, 0)
					else
						m:SetPoint("RIGHT", r.mosaic[k - 1], "LEFT", -3, 0)
					end
					r.mosaic[k] = m
				end
				r.more = W.Text(r, "", "note", "dim")
				r.more:SetPoint("RIGHT", r.mosaic[MOSAIC_N], "LEFT", -6, 0)
				Okanvil.UI.HoverReveal(r, { r.export, r.del })
				rows[i] = r
			end
			r._s = s
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", X, -y); r:SetPoint("RIGHT", p, "RIGHT", -X, 0); r:SetHeight(RH)
			local where = (s.zone ~= "" and s.zone) or "World"
			local isOpen = (expanded == s)
			local size, heroic = Okanvil.UI.RaidDifficulty(s.difficulty)
			Okanvil.UI.PaintRecordRow(r, {
				size = size, heroic = heroic,
				dungeon = s.key and s.key:find("^run|") ~= nil,
				title = where .. "   |cff8a8d93" .. Okanvil.UI.NightStamp(s.t) .. "|r",
				sub = sessionSummary(s),
				open = isOpen,
			})
			-- Rarest first, so an epic or a legendary is what the strip shows.
			local pics = {}
			for _, d in ipairs(s.drops or {}) do pics[#pics + 1] = d end
			table.sort(pics, function(a, b) return (a.rarity or 0) > (b.rarity or 0) end)
			for k = 1, MOSAIC_N do
				local d = pics[k]
				local m = r.mosaic[k]
				if d then
					m:SetTexture(Okanvil:ItemIcon(d.item) or "Interface\\Icons\\INV_Misc_QuestionMark")
					m:Show()
				else
					m:Hide()
				end
			end
			r.more:SetText(#pics > MOSAIC_N and ("+" .. (#pics - MOSAIC_N)) or "")
			r.export:SetScript("OnClick", function() Okanvil:ShowExport(L.SessionJSON(s), "Loot -- " .. (s.day or where)) end)
			-- Exports feed the website, which is officer work: no button for anyone else.
			r.export._allowed = (Okanvil.U and Okanvil.U.canSeePrio and Okanvil.U.canSeePrio()) and true or false
			r._revealUpdate()
			r.del:SetScript("OnClick", function() if expanded == s then expanded = nil end; L.DeleteSession(s) end)
			r:Show()
			y = y + RH + 6
			if isOpen then
				if #(s.drops or {}) == 0 then
					p._none = p._none or W.Text(p, "", "body", "dim")
					p._none:ClearAllPoints(); p._none:SetPoint("TOPLEFT", X + 10, -y)
					p._none:SetText("|cff888888No drops recorded.|r")
					p._none:Show()
					y = y + 26
				else
					if p._none then p._none:Hide() end
					y = drawCards(s, y)
				end
			end
		end
		if not expanded and p._none then p._none:Hide() end
		p:SetHeight(math.max(y + 6, sf:GetHeight()))
		local maxs = math.max(0, p:GetHeight() - sf:GetHeight())
		sb:SetMinMaxValues(0, maxs); sb:SetShown(maxs > 4)
	end

	-- A wider or narrower window changes how many boss cards fit in a row, so an
	-- open session is laid out again when the WIDTH changes (not the height: that
	-- is this function's own doing).
	local lastW = 0
	p:SetScript("OnSizeChanged", function(self, w)
		w = math.floor(w or 0)
		if expanded and w > 0 and math.abs(w - lastW) > 2 then
			lastW = w
			rebuild()
		end
	end)

	if fill then fill._rebuildHistory = rebuild end
	rebuild()
end

-- ---- Prio tab: the officer page's ladder, pasted in and readable in-game ----
--
-- The website works the order out live from the roster, our logs and the loot
-- history; a 3.3.5a client cannot reach it, so the page's export is pasted here
-- and kept. This tab is both the paste box and the read-only copy of the list,
-- so mid-raid you can check an item without alt-tabbing to the site.
function Okanvil:Loot_BuildPrio(p)
	if Okanvil.LootPrio and Okanvil.LootPrio.BuildTab then
		Okanvil.LootPrio.BuildTab(p)
	else
		local t = W.Text(p, "Loot priority module not loaded.", "label", "dim")
		t:SetPoint("TOPLEFT", 8, -8)
	end
end

-- ------------------------------------------------------------
-- Modules -- enable/disable each registered plugin (no /reload for
-- show/hide in the nav; deeper event-gating is opt-in per plugin later)
-- ------------------------------------------------------------
