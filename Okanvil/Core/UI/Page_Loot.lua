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

-- Three pills, and the first one IS the page you land on -- the same switch the
-- Home page uses for Online/Snapshots. What used to be here as well, and is not
-- any more: Messages and the capture settings, which are configuration and now
-- live in Settings > Loot, where every other module's settings are.
--
-- The Prio pill is officer material, so for everyone else it is not built at all
-- rather than built and refused: a tab that only exists to say "not for you" is a
-- worse page for the raider and tells them nothing they can act on.
-- ONE page, no pills. Collectors is three fields armed at the start of a raid
-- and the history is the list you read for the rest of it -- two clicks apart
-- for no reason. The fields go on top, the list takes the rest of the window.
--
-- The Prio ladder moved to Loot Council: that is the council's decision about
-- who SHOULD get an item, while this page records who DID.
function Okanvil:BuildLoot()
	local L = Okanvil.Loot
	local fill = newFillPanel()
	local host = fill.child
	Okanvil._lootFill = fill   -- set BEFORE the tab builders run (they read it)

	-- Dashboard shell: header (icon + title + ML status + CTA), three pills, no
	-- drawer and no footer -- so a page gets the window's full width.
	local dash = W.Dashboard(host, {
		title = "Loot",
		icon = Okanvil.ICONS.loot,
		-- No COLLECTED drawer. It was a per-person tally of what the speed-run had
		-- handed out, in a column beside the page with a Show/Hide button on the
		-- toolbar -- a column of numbers nobody opened, costing every page 200px of
		-- width and the toolbar a button.
		drawerWidth = 0,
		footerHeight = 0,
		primaryText = function() return "Mini Roll Manager" end,
		onPrimary = function()
			if Okanvil.RollMgr and Okanvil.RollMgr.Toggle then Okanvil.RollMgr.Toggle()
			else Okanvil:Print("Roll manager not loaded.") end
		end,
		-- "Set me as ML" -- only shown when you're the leader and NOT already ML.
		secondaryText = function() return "Set me as ML" end,
		secondaryWidth = 110,
		secondaryShown = function()
			if not (L and L.CanSetLootMethod and L.CanSetLootMethod()) then return false end
			return not (L.IsMasterLooter and L.IsMasterLooter())
		end,
		onSecondary = function()
			if not (L and L.SetMeAsMasterLooter) then return end
			local r = L.SetMeAsMasterLooter()
			if r == "nogroup" then
				Okanvil:Print("|cffff5555You're not in a party or raid -- nothing to set.|r")
			elseif r == "notleader" then
				Okanvil:Print("|cffff5555Only the group leader can set the loot method.|r")
			elseif r == "noapi" then
				Okanvil:Print("|cffff5555SetLootMethod unavailable.|r")
			else
				Okanvil:Print("Loot method set to |cff7cfc8amaster|r -- you are the Master Looter.")
			end
			if fill and fill.refreshAll then fill.refreshAll() end
		end,
		statusText = function()
			if L and L.IsMasterLooter and L.IsMasterLooter() then
				return "|cff7cfc8aMaster Looter|r"
			end
			-- name WHO the ML is, instead of only saying it isn't you -- that's the
			-- useful half of the answer when loot won't auto-give.
			local who = L and L.MasterLooterName and L.MasterLooterName()
			if who and who ~= "" then
				return "|cff8a8d93ML:|r |cffffd200" .. who .. "|r"
			end
			return "|cffff5555not master loot|r"
		end,
		-- pills: the tabs switch one shared body instead of covering a landing page,
		-- so there is no "< Back" and the switch never leaves the screen
		-- No tabs: the page is one body now (see below).
	})
	fill.dash = dash

	-- ONE body: collectors on top, then the history list filling what is left.
	-- The collectors block is a fixed height, so the history can anchor to its
	-- bottom and still track the window.
	local main = dash.main
	local top = W.Frame(main, "page")
	top:SetPoint("TOPLEFT", 0, 0)
	top:SetPoint("TOPRIGHT", 0, 0)
	top:SetHeight(128)
	Okanvil:Loot_BuildCollectors(top)

	local hist = W.Frame(main, "page")
	hist:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -4)
	hist:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, 0)
	Okanvil:Loot_BuildHistory(hist)

	-- refresh when loot changes / the page shows / loot method changes
	local function refreshAll()
		dash:Refresh()
		if fill._rebuildHistory then fill._rebuildHistory() end
	end
	fill.refreshAll = refreshAll
	L.onLoot = function() if fill:IsShown() then refreshAll() end end
	if not fill._mlEv then
		fill._mlEv = CreateFrame("Frame")
		fill._mlEv:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
		fill._mlEv:RegisterEvent("RAID_ROSTER_UPDATE")
		fill._mlEv:RegisterEvent("PARTY_LEADER_CHANGED")
		fill._mlEv:RegisterEvent("PARTY_MEMBERS_CHANGED")
		fill._mlEv:SetScript("OnEvent", function() if fill:IsShown() then dash:Refresh() end end)
	end
	fill:SetScript("OnShow", refreshAll)
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
-- to say so -- but on the (?) beside the switch and in the greyed placeholder of
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

	local en = W.Check(p, "Speed-run auto master-loot",
		function() return L.CollectorsEnabled() end,
		function(v) L.SetCollectorsEnabled(v) end)
	en:SetPoint("TOPLEFT", X + 2, -10)
	en:Tooltip(TIP)

	-- The whole explanation now hangs off this one mark. The header already says
	-- whether you are the Master Looter, so the state line that used to sit here
	-- was saying it a second time.
	local qual = W.Text(p, "|cff8a8d93-- only when you are ML|r  |cffe0b860(?)|r", "note", "dim")
	-- anchored to the checkbox's LABEL, not the checkbox: W.Check's frame is the
	-- 18px box alone and its text hangs outside it, so "RIGHT of en" lands on top
	-- of that text instead of after it
	qual:SetPoint("LEFT", en.text, "RIGHT", 10, 0)
	local qhit = CreateFrame("Frame", nil, p)
	qhit:SetPoint("TOPLEFT", qual, "TOPLEFT", -2, 2)
	qhit:SetPoint("BOTTOMRIGHT", qual, "BOTTOMRIGHT", 2, -2)
	qhit:EnableMouse(true)
	qhit:SetScript("OnEnter", function(s)
		GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
		for line in (TIP .. "\n"):gmatch("(.-)\n") do
			if line == "" then GameTooltip:AddLine(" ")
			else GameTooltip:AddLine(line, 1, 1, 1, true) end
		end
		GameTooltip:Show()
	end)
	qhit:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local col = L.Collectors()
	-- The three buttons sit at the RIGHT edge and the field stretches to meet them,
	-- so the name has room and the row reads as one control instead of a short box
	-- adrift in empty space.
	local function row(bucket, label, y, emptyNote)
		local lb = W.Text(p, label, "label"); lb:SetPoint("TOPLEFT", X, y - 4); lb:SetWidth(112); lb:SetJustifyH("LEFT")
		if lb.SetWordWrap then lb:SetWordWrap(false) end

		local cl = W.Button(p, "Clear", "danger"); cl:SetSize(48, 24)
		cl:SetPoint("TOPRIGHT", p, "TOPRIGHT", -X, y)
		local tg = W.Button(p, "Target"); tg:SetSize(56, 24); tg:SetPoint("RIGHT", cl, "LEFT", -6, 0)
		local sf = W.Button(p, "Self"); sf:SetSize(48, 24); sf:SetPoint("RIGHT", tg, "LEFT", -4, 0)

		local eb = W.EditBox(p, function(t) L.SetCollector(bucket, t) end)
		eb:SetHeight(24)
		eb:SetPoint("LEFT", lb, "RIGHT", 8, 0)
		eb:SetPoint("RIGHT", sf, "LEFT", -6, 0)
		eb.edit:SetText(col[bucket] or "")

		-- An empty field says what an empty field DOES, inside the field itself --
		-- greyed, and gone the moment there is a real name in it. That sentence used
		-- to live in a paragraph above the rows, which is where nobody read it.
		local ph = W.Text(p, "|cff6f7176" .. emptyNote .. "|r", "note", "dim")
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

		if sf.text then sf.text:SetText("|cff7cfc8aSelf|r") end
		sf:SetScript("OnClick", function() setName(UnitName("player")) end)
		tg:SetScript("OnClick", function()
			local n = UnitName("target")
			if n and UnitIsPlayer("target") then setName(n) else Okanvil:Print("Target a player first.") end
		end)
		cl:SetScript("OnClick", function() eb.edit:SetText(""); L.SetCollector(bucket, ""); paintPH() end)
		paintPH()
	end
	row("main", "Main loot (BoP)", -44, "-- stays on the corpse --")
	row("frag", "Fragments",       -76, "-- stays on the corpse --")
	row("boe",  "BoE / orbs",      -108, "-- falls back to Main loot --")

	-- The "whisper the winner" toggle used to sit here, with the message it sends
	-- on a different page entirely -- so neither half said anything about the
	-- other. Both are in Settings > Loot now, as one control.
end

-- ---- Announce templates: MS/OS/Free/Whisper ([item] placeholder) ----
-- Drawn as part of Settings > Loot (below), not a page of its own: four text
-- boxes you fill in once were never worth a tab in front of the loot history.
local function buildMessages(p, y0)
	local L = Okanvil.Loot
	local X = 8
	if not (L and L.RollMsg) then return y0 end
	local hd = W.Text(p, "ANNOUNCE TEMPLATES", "note", "dim")
	hd:SetPoint("TOPLEFT", X, y0)
	local sub = W.Text(p, "|cffffd200[item]|r = the itemlink.", "note", "dim")
	sub:SetPoint("TOPLEFT", X, y0 - 16)

	local function row(label, y, getFn, setFn)
		local lb = W.Text(p, label, "label"); lb:SetPoint("TOPLEFT", X, y - 4); lb:SetWidth(58); lb:SetJustifyH("LEFT")
		if lb.SetWordWrap then lb:SetWordWrap(false) end
		local eb = W.EditBox(p, function(t) setFn(t) end)
		eb:SetSize(360, 24); eb:SetPoint("LEFT", lb, "RIGHT", 8, 0); eb.edit:SetText(getFn())
	end
	-- MS and OS only. The Free button is gone from the mini roll (four buttons in
	-- a 270px row were unreadable), so a box to word a message nothing sends was
	-- a setting for a feature that no longer exists. The "free" mode itself stays
	-- as StartRoll's fallback, and its default wording with it.
	row("MS",      y0 - 40, function() return L.RollMsg("ms") end,   function(t) L.SetRollMsg("ms", t) end)
	row("OS",      y0 - 70, function() return L.RollMsg("os") end,   function(t) L.SetRollMsg("os", t) end)
	-- ON AWARD: the switch and the message it sends, as one control. They used to
	-- be on separate pages -- the toggle under Collectors, the text here -- so
	-- neither half said anything about the other, and the box sat empty with the
	-- switch on and nothing to explain why nothing was sent.
	-- 30px higher than it used to be: the Free template above is gone, and the
	-- gap it left read as a missing control.
	local wy = y0 - 118
	local wh = W.Text(p, "ON AWARD", "note", "dim"); wh:SetPoint("TOPLEFT", X, wy)
	wy = wy - 24

	local wc = W.Check(p, "Whisper the winner",
		function() return L.WhisperWinner() end,
		function(v) L.SetWhisperWinner(v); if p._paintWhisper then p._paintWhisper() end end)
	wc:SetPoint("TOPLEFT", X, wy)
	wy = wy - 26

	-- Same width as the three announce templates above it, rather than stretched
	-- to the panel's right edge. A box twice the length of anything anyone types
	-- into it reads as asking for a paragraph.
	local web = W.EditBox(p, function(t) L.SetWhisperMsg(t) end)
	web:SetHeight(24)
	web:SetPoint("TOPLEFT", X + 21, wy)
	-- Ends where the announce boxes above it end (they start at X+66 and run 360),
	-- so the right edges of every text field on this page line up.
	web:SetWidth(405)
	web.edit:SetText(L.WhisperMsg() or "")

	-- The "nothing to send" warning sits BESIDE the box, not over it. Printed
	-- inside the edit area it looked like text already typed in -- red characters
	-- sharing the line with the cursor, which reads as a bad value rather than an
	-- empty one.
	local wph = W.Text(p, "", "note", "dim")
	wph:SetPoint("LEFT", web, "RIGHT", 10, 0)
	p._paintWhisper = function()
		local on = L.WhisperWinner()
		local txt = web.edit:GetText() or ""
		web:SetAlpha(on and 1 or 0.4)
		if on and txt == "" then
			wph:SetText("|cffff5555nothing to send|r")
		else
			wph:SetText("")
		end
	end
	web.edit:HookScript("OnTextChanged", function() p._paintWhisper() end)
	p._paintWhisper()

	-- Room between the box and its note: at 22 they touched, and the hint read as
	-- part of the field.
	wy = wy - 32
	local whh = W.Text(p, "|cff6f7176sent when the boss loot window has already closed|r", "note", "dim")
	whh:SetPoint("TOPLEFT", X + 21, wy)

	return wy - 30
end

-- ---- History (landing/main): sessions accordion with an internal-scroll detail
-- box. Full width: the page has no drawer beside it.
function Okanvil:Loot_BuildHistory(main)
	local L = Okanvil.Loot
	local fill = Okanvil._lootFill
	local X = Okanvil.UI.PAD_X

	-- a scroll panel INSIDE main so the sessions list scrolls without resizing
	local p, _, sf, sb = Okanvil.UI.DashScroll(main, X)

	local rows, detailRows = {}, {}
	local expanded = nil

	-- one reusable fixed-height detail box (internal scroll) for the open session
	local DETAIL_H = 260
	local dbox = W.Frame(p, "dark")
	local dsf = CreateFrame("ScrollFrame", nil, dbox)
	dsf:SetPoint("TOPLEFT", 4, -4); dsf:SetPoint("BOTTOMRIGHT", -10, 4)
	local dchild = CreateFrame("Frame", nil, dsf); dchild:SetSize(10, 1); dsf:SetScrollChild(dchild)
	local dsb = CreateFrame("Slider", nil, dbox)
	dsb:SetPoint("TOPRIGHT", -3, -4); dsb:SetPoint("BOTTOMRIGHT", -3, 4); dsb:SetWidth(4)
	dsb:SetOrientation("VERTICAL"); dsb:SetValueStep(1)
	local dth = dsb:CreateTexture(nil, "OVERLAY"); dth:SetTexture(FLAT); dth:SetVertexColor(u3(C.accent)); dth:SetSize(4, 40)
	dsb:SetThumbTexture(dth)
	dsb:SetScript("OnValueChanged", function(_, v) dsf:SetVerticalScroll(v) end)
	dsf:EnableMouseWheel(true)
	dsf:SetScript("OnMouseWheel", function(_, d) dsb:SetValue(dsb:GetValue() - d * 28) end)
	dsf:SetScript("OnSizeChanged", function() dchild:SetWidth(dsf:GetWidth()) end)
	dbox:Hide()

	local function detailRow(idx, yTop)
		local r = detailRows[idx]
		if not r then
			r = CreateFrame("Button", nil, dchild); r:SetHeight(18)
			r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); r.icon:Hide()
			r.txt = r:CreateFontString(nil, "OVERLAY"); r.txt:SetFont(Okanvil:Font()); r.txt:SetJustifyH("LEFT")
			local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(FLAT); hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.10)
			detailRows[idx] = r
		end
		r:ClearAllPoints(); r:SetPoint("TOPLEFT", 8, -yTop); r:SetPoint("RIGHT", dchild, "RIGHT", -6, 0)
		r:SetScript("OnEnter", nil); r:SetScript("OnLeave", nil); r:SetScript("OnClick", nil)
		r.icon:Hide(); r:Show()
		return r
	end

	local function rebuild()
		for _, r in ipairs(rows) do r:Hide() end
		for _, r in ipairs(detailRows) do r:Hide() end
		dbox:Hide()
		local sessions = (L.Sessions and L.Sessions()) or {}
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
				r = W.Frame(p, "input")
				r.title = W.Text(r, "", "body"); r.title:SetPoint("TOPLEFT", 10, -6)
				r.sub = W.Text(r, "", "note", "dim"); r.sub:SetPoint("BOTTOMLEFT", 10, 6)
				r.del = W.Button(r, "X", "danger"); r.del:SetSize(24, 22); r.del:SetPoint("RIGHT", -8, 0)
				r.export = W.Button(r, "Export"); r.export:SetSize(72, 22); r.export:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
				r.view = W.Button(r, "View"); r.view:SetSize(60, 22); r.view:SetPoint("RIGHT", r.export, "LEFT", -6, 0)
				r:EnableMouse(true)
				rows[i] = r
			end
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", X, -y); r:SetPoint("RIGHT", p, "RIGHT", -X, 0); r:SetHeight(40)
			local where = (s.zone ~= "" and s.zone) or "World"
			local isOpen = (expanded == s)
			r.title:SetText((isOpen and "|cffffd200v|r  " or "|cff8a8d93>|r  ") .. where .. "  |cff8a8d93" .. (s.day or "") .. "|r")
			r.sub:SetText("|cff8a8d93" .. #s.drops .. " drops|r")
			r.view.text:SetText(isOpen and "Close" or "View")
			r.view:SetScript("OnClick", function() if expanded == s then expanded = nil else expanded = s end; rebuild() end)
			r.export:SetScript("OnClick", function() Okanvil:ShowExport(L.SessionJSON(s), "Loot -- " .. (s.day or where)) end)
			r.del:SetScript("OnClick", function() if expanded == s then expanded = nil end; L.DeleteSession(s) end)
			r:Show()
			y = y + 46
			if isOpen then
				dbox:ClearAllPoints(); dbox:SetPoint("TOPLEFT", X, -y); dbox:SetPoint("RIGHT", p, "RIGHT", -X, 0)
				dbox:SetHeight(DETAIL_H); dbox:Show()
				dchild:SetWidth(dsf:GetWidth())
				local dy = select(2, L.RenderInline(s, detailRow, 0, 4))
				dchild:SetHeight(math.max(1, dy))
				local maxs = math.max(0, dy - (DETAIL_H - 8))
				dsb:SetMinMaxValues(0, maxs); dsb:SetValue(0); dsb:SetShown(maxs > 4)
				y = y + DETAIL_H + 6
			end
		end
		p:SetHeight(math.max(y + 6, sf:GetHeight()))
		local maxs = math.max(0, p:GetHeight() - sf:GetHeight())
		sb:SetMinMaxValues(0, maxs); sb:SetShown(maxs > 4)
	end
	if fill then fill._rebuildHistory = rebuild end
	rebuild()
end

-- ------------------------------------------------------------
-- Invite (native) -- form a raid/party fast: mass-invite, by rank, saved lists
-- with comp-group import + auto-assign, keyword whisper invite, on-login invite.
-- ------------------------------------------------------------

function Okanvil:Loot_BuildSettings(p)
	local db = self.db
	-- Section headings on this page are dim all-caps notes, the same as
	-- ANNOUNCE TEMPLATES and ON AWARD below. Three of them were normal-case
	-- "label" text, so half the page's headings looked like control labels.
	-- Section headings on this page are dim all-caps notes, the same as
	-- ANNOUNCE TEMPLATES and ON AWARD below. This block's headings were
	-- normal-case "label" text, so half the page's headings looked like the
	-- label of a control rather than the name of a group.
	--
	-- The quality dropdown and the two capture checkboxes sit side by side: both
	-- are narrow, and stacked they used 90px of height for two short controls.
	local ll = W.Text(p, "CAPTURE", "note", "dim"); ll:SetPoint("TOPLEFT", 8, -8)

	local llx = W.Text(p, "Log items of quality", "label", "dim")
	llx:SetPoint("TOPLEFT", 8, -32)
	local RARITY = {
		{ text = "|cff9d9d9dPoor+|r", value = 0 }, { text = "|cffffffffCommon+|r", value = 1 },
		{ text = "|cff1eff00Uncommon+|r", value = 2 }, { text = "|cff0070ddRare+|r", value = 3 },
		{ text = "|cffa335eeEpic|r", value = 4 },
	}
	local lootDD = W.DropDown(p, function() return RARITY end,
		function() return db.lootThreshold or 3 end, function(v) db.lootThreshold = v end)
	lootDD:Size(160, 22):Point("TOPLEFT", 8, -50)
	lootDD.refreshText = function(self)
		local cur = db.lootThreshold or 3
		for _, o in ipairs(RARITY) do
			if o.value == cur then self.textFS:SetText(o.text); return end
		end
	end
	lootDD:refreshText()

	local rhint = W.Text(p, "Auto-capture in", "label", "dim")
	rhint:SetPoint("TOPLEFT", 220, -32)
	local cDun = W.Check(p, "Dungeons",
		function() return db.recordDungeon ~= false end, function(v) db.recordDungeon = v end)
	cDun:SetPoint("TOPLEFT", 220, -52)
	local cRaid = W.Check(p, "Raids",
		function() return db.recordRaid ~= false end, function(v) db.recordRaid = v end)
	cRaid:SetPoint("TOPLEFT", 340, -52)

	-- announce templates: everyone who awards loot needs these. It reports where
	-- it ended, and the next block starts there -- a hard -330 below drifts the
	-- moment anything above changes height, which is how the whisper box came to
	-- sit on top of the priority toggle.
	local y = buildMessages(p, -96)

	-- Everything below is about the priority list, so it is only built for someone
	-- who can see that list -- to anyone else these are controls for a thing they
	-- cannot open.
	if not (Okanvil.U and Okanvil.U.canSeePrio and Okanvil.U.canSeePrio()) then return end

	-- ---- Priority list ----------------------------------------------------
	-- Lived as a button on the Prio tab's toolbar, which put a choice nobody
	-- revisits after the first time in front of the list every single visit.
	local ph = W.Text(p, "Priority list", "label", "dim"); ph:SetPoint("TOPLEFT", 8, y)
	local cMulti = W.Check(p, "Send each name on its own line",
		function() return Okanvil.LootPrio and Okanvil.LootPrio.MultiLine() end,
		function() if Okanvil.LootPrio then Okanvil.LootPrio.ToggleMultiLine() end end)
	cMulti:SetPoint("TOPLEFT", 8, y - 20)
	cMulti:Tooltip("Off: the item and its ladder go out as one line.\n"
		.. "On: the item first, then its top names one per line.")

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
