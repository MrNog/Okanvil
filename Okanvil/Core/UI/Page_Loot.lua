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
		subtitle = "What dropped, per boss, and who got it",
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

	-- The speed-run master-loot block is for officers, and for whoever is master
	-- looter right now (a pug leader sweeping loot). Everyone else sees only the
	-- history, which moves up to take the space.
	local function applyTop()
		local show = (Okanvil.U and Okanvil.U.canSeePrio and Okanvil.U.canSeePrio())
			or (L.IsMasterLooter and L.IsMasterLooter())
		local on = L.CollectorsEnabled and L.CollectorsEnabled()
		if top.fields then if on then top.fields:Show() else top.fields:Hide() end end
		if show then top:Show(); top:SetHeight(on and 148 or 50) else top:Hide(); top:SetHeight(1) end
	end
	applyTop()
	fill.applyTop = applyTop
	top.onToggle = applyTop

	-- Soft reserves: one line when closed, the paste box when open. Shown to
	-- everyone -- in a pug the master looter is whoever the leader picked.
	local srp = W.Frame(main, "page")
	srp:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -4)
	srp:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, -4)
	Okanvil:Loot_BuildSoftRes(srp)

	local hist = W.Frame(main, "page")
	hist:SetPoint("TOPLEFT", srp, "BOTTOMLEFT", 0, -4)
	hist:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, 0)
	Okanvil:Loot_BuildHistory(hist)

	-- refresh when loot changes / the page shows / loot method changes
	local function refreshAll()
		applyTop()
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
		fill._mlEv:SetScript("OnEvent", function()
			if fill:IsShown() then
				if fill.applyTop then fill.applyTop() end
				dash:Refresh()
			end
		end)
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

		if sf.text then sf.text:SetText("|cff7cfc8aSelf|r") end
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

-- ---- Soft reserves: the softres.it CSV, pasted in ----
--
-- Closed, the strip is one line saying what is loaded. Open, it is the paste
-- box and the wording of the roll call for a reserved item. The list itself is
-- read by the roll manager (who reserved what, whose rolls count).
local SR_CLOSED_H, SR_OPEN_H = 32, 196
function Okanvil:Loot_BuildSoftRes(p)
	local SR = Okanvil.SoftRes
	p:SetHeight(SR_CLOSED_H)
	if not SR then return end
	local X = 8

	local hd = W.Text(p, "SOFT RESERVES", "note", "dim")
	hd:SetPoint("TOPLEFT", X, -10)
	local status = W.Text(p, "", "label")
	status:SetPoint("LEFT", hd, "RIGHT", 10, 0)

	local clr = W.Button(p, "Clear"); clr:SetSize(60, 22); clr:SetPoint("TOPRIGHT", -8, -5)
	local tog = W.Button(p, "Paste SR"); tog:SetSize(80, 22); tog:SetPoint("RIGHT", clr, "LEFT", -6, 0)

	local body = CreateFrame("Frame", nil, p)
	body:SetPoint("TOPLEFT", 0, -SR_CLOSED_H)
	body:SetPoint("BOTTOMRIGHT", 0, 0)
	body:Hide()

	local hint = W.Text(body, "softres.it > Export > CSV > Copy to Clipboard, then paste here (Ctrl+V).", "note", "dim")
	hint:SetPoint("TOPLEFT", X, -2)
	local box = W.MultiEdit(body)
	box:SetPoint("TOPLEFT", X, -18)
	box:SetPoint("TOPRIGHT", -8, -18)
	box:SetHeight(92)

	local imp = W.Button(body, "Import", "primary"); imp:SetSize(80, 22)
	imp:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -6)

	local ml = W.Text(body, "MS call", "label"); ml:SetPoint("TOPLEFT", X, -148)
	local msg = W.EditBox(body, function(t) SR.SetMsg(t) end)
	msg:SetHeight(24)
	msg:SetPoint("LEFT", ml, "RIGHT", 8, 0)
	msg:SetPoint("RIGHT", body, "RIGHT", -8, 0)
	msg.edit:SetText(SR.Msg())
	local mh = W.Text(body, "|cffffd200[item]|r = the item, |cffffd200[names]|r = who reserved it. Only their rolls count.", "note", "dim")
	mh:SetPoint("TOPLEFT", X + 66, -174)

	local function paint()
		local ni, np, at = SR.Summary()
		if ni then
			status:SetText(("|cffdcddde%d|r |cff8a8d93items,|r |cffdcddde%d|r |cff8a8d93raiders  -- imported %s|r")
				:format(ni, np, date("%d/%m %H:%M", at)))
			clr:Show()
		else
			status:SetText("|cff6f7176none loaded -- MS rolls are open to everyone|r")
			clr:Hide()
		end
	end

	local function setOpen(open)
		p._open = open
		if open then body:Show(); p:SetHeight(SR_OPEN_H); tog.text:SetText("Close")
		else body:Hide(); p:SetHeight(SR_CLOSED_H); tog.text:SetText("Paste SR"); box.edit:ClearFocus() end
	end

	tog:SetScript("OnClick", function() setOpen(not p._open) end)
	imp:SetScript("OnClick", function()
		local ni, np = SR.Import(box:GetText())
		if not ni then Okanvil:Print("|cffff5555" .. tostring(np) .. "|r"); return end
		Okanvil:Print(("Soft reserves loaded: %d items, %d raiders."):format(ni, np))
		box:SetText("")
		setOpen(false)
	end)
	clr:SetScript("OnClick", function()
		Okanvil:Confirm("Clear the soft reserves?\n|cff8a8d93MS rolls go back to being open to everyone.|r",
			"Clear", function() SR.Clear(); Okanvil:Print("Soft reserves cleared.") end)
	end)
	clr:Tooltip("Remove the loaded list, e.g. before the next raid.")

	SR.onChange = function()
		paint()
		if Okanvil.RollMgr and Okanvil.RollMgr.Refresh then Okanvil.RollMgr.Refresh() end
	end
	p:SetScript("OnShow", paint)
	paint()
	setOpen(false)
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
		return eb
	end
	-- MS and OS only. The Free button is gone from the mini roll (four buttons in
	-- a 270px row were unreadable), so a box to word a message nothing sends was
	-- a setting for a feature that no longer exists. The "free" mode itself stays
	-- as StartRoll's fallback, and its default wording with it.
	row("MS",      y0 - 40, function() return L.RollMsg("ms") end,   function(t) L.SetRollMsg("ms", t) end)
	local osBox = row("OS", y0 - 70, function() return L.RollMsg("os") end, function(t) L.SetRollMsg("os", t) end)
	-- ROLL TIMER: seconds before an MS/OS roll ends itself. Beside the templates
	-- it applies to; the loot council has no clock and is not affected.
	if L.RollTimer then
		local tl = W.Text(p, "Timer", "label")
		tl:SetPoint("LEFT", osBox, "RIGHT", 14, 0)
		local tb = W.EditBox(p, function(t)
			L.SetRollTimer(t)
			if p._timerBox then p._timerBox.edit:SetText(tostring(L.RollTimer())) end
		end)
		tb:SetSize(40, 24); tb:SetPoint("LEFT", tl, "RIGHT", 6, 0)
		tb.edit:SetText(tostring(L.RollTimer()))
		p._timerBox = tb
		local tn = W.Text(p, "s  (0 = off)", "note", "dim")
		tn:SetPoint("LEFT", tb, "RIGHT", 6, 0)
	end
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
		local sessions = {}
		for _, sess in ipairs((L.Sessions and L.Sessions()) or {}) do
			if sess.drops and #sess.drops > 0 then sessions[#sessions + 1] = sess end
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
