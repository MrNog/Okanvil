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

function Okanvil:BuildLoot()
	local L = Okanvil.Loot
	local fill = newFillPanel()
	local host = fill.child
	Okanvil._lootFill = fill   -- set BEFORE the tab builders run (they read it)

	-- Dashboard shell (MRT/Recruit-style): header (icon + title + ML status + CTA),
	-- tabs (History = landing / Collectors / Messages as overlays), a COLLECTED
	-- drawer, no footer. History gets the whole main area so it scales as loot grows.
	local dash = W.Dashboard(host, {
		title = "Loot",
		icon = Okanvil.ICONS.loot,
		drawerWidth = 200,
		drawerLabel = "collected",
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
		tabs = {
			{ key = "collectors", label = "Collectors", height = 330, build = function(pg) Okanvil:Loot_BuildCollectors(pg) end },
			{ key = "messages",   label = "Messages",   height = 260, build = function(pg) Okanvil:Loot_BuildMessages(pg) end },
			{ key = "settings",   label = "Settings",   height = 160, build = function(pg) Okanvil:Loot_BuildSettings(pg) end },
		},
	})
	fill.dash = dash

	Okanvil:Loot_BuildHistory(dash.main)     -- sessions accordion (landing)
	Okanvil:Loot_BuildTally(dash.drawer)     -- COLLECTED tally (drawer)

	-- refresh both when loot changes / the page shows / loot method changes
	local function refreshAll()
		dash:Refresh()
		if fill._refreshTally then fill._refreshTally() end
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

-- ---- Collectors tab: Main/Frag/BoE targets + auto toggle + whisper toggle ----
--
-- Okanvil handles loot three ways; only the THIRD one lives on this tab:
--   1. Need/Greed  -- the game's own roll. Okanvil just records what dropped.
--   2. Master loot -- the normal flow: the Mini Roll Manager runs an MS/OS/Free
--      roll-off, you press Award, confirm the popup, the item goes to the winner.
--   3. Speed-run   -- THIS TAB. Skips rolling at the pull: the boss is swept into
--      one bag so the raid keeps moving, and loot is settled afterwards by roll or
--      loot council. Every drop is still recorded and broadcast to the raid.
--
-- The header below says this in-game, because arming the toggle silently ships
-- every BoP drop to one player and that must never be a surprise.
function Okanvil:Loot_BuildCollectors(p)
	local L = Okanvil.Loot
	local X = 8
	if not (L and L.Collectors) then return end

	-- One line: what this tab is, and that it is not the normal flow. Details on hover.
	local intro = W.Text(p, "|cffe0b860Speed-run loot|r -- sweep the boss into one bag, settle it later. |cff8a8d93Off = normal roll + Award.|r", 10, "dim")
	intro:SetPoint("TOPLEFT", X, -6); intro:SetPoint("RIGHT", -X, 0); intro:SetJustifyH("LEFT")

	local warn = W.Text(p, "", 11); warn:SetPoint("TOPLEFT", X, -26); warn:SetPoint("RIGHT", -X, 0); warn:SetJustifyH("LEFT")
	local function paintWarn()
		if L.IsMasterLooter and L.IsMasterLooter() then
			warn:SetText("|cff7cfc8aYou are the Master Looter -- these apply.|r")
		else
			local who = L.MasterLooterName and L.MasterLooterName()
			warn:SetText("|cffff5555Auto-loot inactive (safe) -- the Master Looter is "
				.. (who and who ~= "" and ("|r|cffffd200" .. who .. "|r") or "|cff8a8d93nobody (not master loot)|r") .. ".")
		end
	end
	paintWarn()
	local en = W.Check(p, "Speed-run auto master-loot (only when you're the Master Looter)",
		function() return L.CollectorsEnabled() end,
		function(v) L.SetCollectorsEnabled(v) end)
	en:SetPoint("TOPLEFT", X + 2, -46)
	en:Tooltip("Skips rolling at the pull: the boss is swept into one bag, settled later by "
		.. "roll or loot council. Every drop is still recorded.\n"
		.. "Only works while YOU are the Master Looter.")

	-- Exactly what each row does. Kept next to the rows it describes.
	local hint = W.Text(p, "|cffff8000BoP gear|r -> Main loot.   |cffffd200Orbs / patterns / BoE|r -> BoE (or Main, if BoE is empty).   |cffff5555Legendary fragments always ask first.|r\n"
		.. "Leave a field |cffffd200EMPTY|r and that loot stays on the corpse to be rolled normally -- nothing is ever swept to anyone you did not name. "
		.. "|cff7cfc8aEvery drop is still recorded in the history and shown to the raid.|r", 10, "dim")
	hint:SetPoint("TOPLEFT", X, -70); hint:SetPoint("RIGHT", -X, 0); hint:SetJustifyH("LEFT")

	local col = L.Collectors()
	local function row(bucket, label, y)
		local lb = W.Text(p, label, 11); lb:SetPoint("TOPLEFT", X, y - 4); lb:SetWidth(112); lb:SetJustifyH("LEFT")
		if lb.SetWordWrap then lb:SetWordWrap(false) end
		local eb = W.EditBox(p, function(t) L.SetCollector(bucket, t) end)
		eb:SetSize(150, 24); eb:SetPoint("LEFT", lb, "RIGHT", 8, 0); eb.edit:SetText(col[bucket] or "")
		local function setName(n)
			if not n or n == "" then return end
			n = n:gsub("%-.*$", ""); eb.edit:SetText(n); L.SetCollector(bucket, n)
		end
		local sf = W.Button(p, "Self"); sf:SetSize(48, 24); sf:SetPoint("LEFT", eb, "RIGHT", 6, 0)
		if sf.text then sf.text:SetText("|cff7cfc8aSelf|r") end
		sf:SetScript("OnClick", function() setName(UnitName("player")) end)
		local tg = W.Button(p, "Target"); tg:SetSize(56, 24); tg:SetPoint("LEFT", sf, "RIGHT", 4, 0)
		tg:SetScript("OnClick", function()
			local n = UnitName("target")
			if n and UnitIsPlayer("target") then setName(n) else Okanvil:Print("Target a player first.") end
		end)
		local cl = W.Button(p, "Clear", "danger"); cl:SetSize(48, 24); cl:SetPoint("LEFT", tg, "RIGHT", 6, 0)
		cl:SetScript("OnClick", function() eb.edit:SetText(""); L.SetCollector(bucket, "") end)
	end
	-- vertical stack: intro (-6) / warn (-26) / toggle (-46) / hint (-70, 2 lines)
	row("main", "Main loot (BoP)", -116)
	row("frag", "Fragments", -146)
	row("boe", "BoE / orbs", -176)
	local wc = W.Check(p, "Whisper winner on Award (\"you won, trade me\")",
		function() return L.WhisperWinner() end, function(v) L.SetWhisperWinner(v) end)
	wc:SetPoint("TOPLEFT", X + 2, -212)
end

-- ---- Messages tab: editable MS/OS/Free/Whisper templates ([item] placeholder) --
function Okanvil:Loot_BuildMessages(p)
	local L = Okanvil.Loot
	local X = 8
	if not (L and L.RollMsg) then return end
	local hd = W.Text(p, "Announce templates -- |cffffd200[item]|r = the itemlink.", 11, "dim")
	hd:SetPoint("TOPLEFT", X, -6); hd:SetPoint("RIGHT", -X, 0); hd:SetJustifyH("LEFT")
	local function row(label, y, getFn, setFn)
		local lb = W.Text(p, label, 11); lb:SetPoint("TOPLEFT", X, y - 4); lb:SetWidth(58); lb:SetJustifyH("LEFT")
		if lb.SetWordWrap then lb:SetWordWrap(false) end
		local eb = W.EditBox(p, function(t) setFn(t) end)
		eb:SetSize(360, 24); eb:SetPoint("LEFT", lb, "RIGHT", 8, 0); eb.edit:SetText(getFn())
	end
	row("MS", -30, function() return L.RollMsg("ms") end, function(t) L.SetRollMsg("ms", t) end)
	row("OS", -60, function() return L.RollMsg("os") end, function(t) L.SetRollMsg("os", t) end)
	row("Free", -90, function() return L.RollMsg("free") end, function(t) L.SetRollMsg("free", t) end)
	row("Whisper", -128, function() return L.WhisperMsg() end, function(t) L.SetWhisperMsg(t) end)
	local wh = W.Text(p, "Whisper is sent on Award when the boss loot window is already closed.", 10, "dim")
	wh:SetPoint("TOPLEFT", X, -156); wh:SetPoint("RIGHT", -X, 0); wh:SetJustifyH("LEFT")
end

-- ---- COLLECTED drawer: per-person tally of main/frag/boe given ----
function Okanvil:Loot_BuildTally(drawer)
	local L = Okanvil.Loot
	local fill = Okanvil._lootFill
	local hd = W.Text(drawer, "COLLECTED", 11, "accent"); hd:SetPoint("TOPLEFT", 10, -8); hd:Color(1, 0.82, 0)
	local ICON = {
		main = "Interface\\Icons\\INV_Misc_Coin_01",
		frag = "Interface\\Icons\\INV_Misc_Gem_Diamond_07",
		boe  = "Interface\\Icons\\INV_Misc_Orb_04",
	}
	local rows = {}
	local function refresh()
		for _, r in ipairs(rows) do r:Hide() end
		if not (L and L.Collectors) then return end
		local c = L.Collectors()
		local list = {}
		for _, bkt in ipairs({ "main", "frag", "boe" }) do
			for name, n in pairs(c.counts[bkt] or {}) do
				if n and n > 0 then list[#list + 1] = { name = name, n = n, icon = ICON[bkt] } end
			end
		end
		table.sort(list, function(a, b) return a.n > b.n end)
		local y = 28
		if #list == 0 then
			local r = rows[1]
			if not r then r = CreateFrame("Frame", nil, drawer); r:SetSize(180, 18)
				r.name = W.Text(r, "", 10, "dim"); r.name:SetPoint("LEFT", 10, 0); rows[1] = r end
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", 8, -y)
			if r.icon then r.icon:Hide() end; if r.cnt then r.cnt:SetText("") end
			r.name:SetText("|cff888888Nothing collected yet.|r"); r:Show()
			return
		end
		for i, e in ipairs(list) do
			local r = rows[i]
			if not r then
				r = CreateFrame("Frame", nil, drawer); r:SetSize(184, 20)
				r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 4, 0)
				r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				r.name = W.Text(r, "", 12); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
				r.cnt = W.Text(r, "", 12, "accent"); r.cnt:SetPoint("RIGHT", -6, 0); r.cnt:Color(1, 0.82, 0)
				rows[i] = r
			end
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", 8, -y)
			r.icon:Show(); r.icon:SetTexture(e.icon); r.name:SetText(e.name); r.cnt:SetText(e.n .. "x")
			r:Show(); y = y + 22
		end
	end
	if fill then fill._refreshTally = refresh end
	refresh()
end

-- ---- History (landing/main): sessions accordion with an internal-scroll detail
-- box, drawn into the Dashboard's main area. Full width now (tally is in the drawer).
function Okanvil:Loot_BuildHistory(main)
	local L = Okanvil.Loot
	local fill = Okanvil._lootFill
	local X = 8

	-- a scroll panel INSIDE main so the sessions list scrolls without resizing
	local sf = CreateFrame("ScrollFrame", nil, main)
	sf:SetPoint("TOPLEFT", X, -8); sf:SetPoint("BOTTOMRIGHT", -14, 8)
	local p = CreateFrame("Frame", nil, sf); p:SetSize(10, 1); sf:SetScrollChild(p)
	local sb = CreateFrame("Slider", nil, main)
	sb:SetPoint("TOPRIGHT", -4, -8); sb:SetPoint("BOTTOMRIGHT", -4, 8); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
	local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetVertexColor(u3(C.accent)); th:SetSize(4, 40)
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 30) end)
	sf:SetScript("OnSizeChanged", function() p:SetWidth(sf:GetWidth()) end)

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
			p._empty = p._empty or W.Text(p, "", 12, "dim")
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
				r.title = W.Text(r, "", 13); r.title:SetPoint("TOPLEFT", 10, -6)
				r.sub = W.Text(r, "", 10, "dim"); r.sub:SetPoint("BOTTOMLEFT", 10, 6)
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
	local ll = W.Text(p, "Log items of quality", 11, "dim"); ll:SetPoint("TOPLEFT", 8, -8)
	local RARITY = {
		{ text = "|cff9d9d9dPoor+|r", value = 0 }, { text = "|cffffffffCommon+|r", value = 1 },
		{ text = "|cff1eff00Uncommon+|r", value = 2 }, { text = "|cff0070ddRare+|r", value = 3 },
		{ text = "|cffa335eeEpic|r", value = 4 },
	}
	local lootDD = W.DropDown(p, function() return RARITY end,
		function() return db.lootThreshold or 3 end, function(v) db.lootThreshold = v end)
	lootDD:Size(160, 22):Point("TOPLEFT", 8, -26)
	lootDD.refreshText = function(self)
		local cur = db.lootThreshold or 3
		for _, o in ipairs(RARITY) do
			if o.value == cur then self.textFS:SetText(o.text); return end
		end
	end
	lootDD:refreshText()
	local rhint = W.Text(p, "Auto-capture in:", 11, "dim"); rhint:SetPoint("TOPLEFT", 8, -66)
	local cDun = W.Check(p, "Dungeons",
		function() return db.recordDungeon ~= false end, function(v) db.recordDungeon = v end)
	cDun:SetPoint("TOPLEFT", 8, -86)
	local cRaid = W.Check(p, "Raids",
		function() return db.recordRaid ~= false end, function(v) db.recordRaid = v end)
	cRaid:SetPoint("TOPLEFT", 160, -86)
end

-- ------------------------------------------------------------
-- Modules -- enable/disable each registered plugin (no /reload for
-- show/hide in the nav; deeper event-gating is opt-in per plugin later)
-- ------------------------------------------------------------
