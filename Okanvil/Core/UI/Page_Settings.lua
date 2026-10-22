-- ============================================================
-- Okanvil -- UI: Settings page
-- Loads after Core/UI/Shell.lua, which publishes the shared helpers on
-- Okanvil.UI (see that file).
--
-- The UI kit's settings layout (wow-addons/UI-KIT.md), widened to fill the
-- page: two columns 380 wide, 36 apart, each section in the shorter column; a section is 11px uppercase gold with a hairline to the column's
-- end; a row is 30 tall with its name on the left and its control on the right
-- edge. No hint lines, no tooltips: a label says what the setting does.
-- ============================================================

local Okanvil = Okanvil
local W   = Okanvil.W
local C   = Okanvil.Colors
local LSM = Okanvil.LSM
local FLAT           = Okanvil.UI.FLAT
local u3             = Okanvil.UI.u3
local newFillPanel   = Okanvil.UI.newFillPanel

local COL_W, COL_GAP, MARGIN = 380, 36, 26
local TOP = -14

-- ------------------------------------------------------------
-- Column layout. Each L:Section goes to the shorter column (L:Col(i) pins
-- one); every row helper draws at the current spot and steps down.
-- ------------------------------------------------------------
local function Layout(p)
	local L = { p = p, i = 1, ys = { TOP, TOP }, refreshers = {} }
	function L:Col(i) self.i = i end
	function L:X() return MARGIN + (self.i - 1) * (COL_W + COL_GAP) end
	function L:Y() return self.ys[self.i] end
	function L:Step(n) self.ys[self.i] = self.ys[self.i] - n end
	function L:Height() return -math.min(self.ys[1], self.ys[2]) + 16 end

	function L:Section(text, pinned)
		if not pinned then self.i = (self.ys[2] > self.ys[1]) and 2 or 1 end
		if self:Y() ~= TOP then self:Step(10) end
		local t = W.FixedText(p, text:upper(), 13)
		t:SetTextColor(u3(C.accentText))
		t:SetPoint("TOPLEFT", self:X(), self:Y())
		local rule = p:CreateTexture(nil, "ARTWORK")
		rule:SetTexture(FLAT); rule:SetVertexColor(u3(C.edge)); rule:SetHeight(1)
		rule:SetPoint("LEFT", t, "RIGHT", 8, 0)
		rule:SetWidth(math.max(1, COL_W - (t:GetStringWidth() or 60) - 8))
		W.ResetStripes(p)
		self:Step(20)
	end

	local function place(row)
		row:SetPoint("TOPLEFT", L:X() - 6, L:Y())
		row:SetWidth(COL_W + 12)
		L:Step(W.ROW_H)
		return row
	end

	-- a checkbox; the whole row toggles it
	function L:Check(label, getFn, setFn)
		local r = W.ToggleRow(p, label, nil, getFn, setFn)
		self.refreshers[#self.refreshers + 1] = r.refresh
		return place(r)
	end

	-- a dropdown on the right of its row; items = { { text =, value = }, ... }
	function L:Choice(label, items, getFn, setFn, width, preview)
		local r = place(W.SettingsRow(p, label))
		local list = type(items) == "function" and items or function() return items end
		local dd = W.DropDown(r, list, getFn, function(v) setFn(v) end, preview)
		dd:SetSize(width or 170, 24); dd:SetPoint("RIGHT", -4, 0)
		-- show the choice's label, not its stored value
		local plain = dd.refreshText
		dd.refreshText = function(self)
			local cur = getFn()
			for _, o in ipairs(list()) do
				if type(o) == "table" and o.value == cur then self.textFS:SetText(o.text); return end
			end
			plain(self)
		end
		dd:refreshText()
		r:SetScript("OnClick", function() dd:Click() end)
		return r, dd
	end

	-- [-] value [+] on the right of its row
	function L:Stepper(label, lo, hi, step, getFn, setFn)
		local r = place(W.SettingsRow(p, label))
		local s = W.Slider(r, "", lo, hi, step, getFn, setFn)
		s:SetWidth(110); s:SetPoint("RIGHT", -4, 0)
		return r, s
	end

	-- a one-line text box on the right of its row
	function L:Field(label, getFn, setFn, width)
		local r = place(W.SettingsRow(p, label))
		local box = W.EditBox(r, function(t) setFn(t or "") end)
		box:SetSize(width or 200, 24); box:SetPoint("RIGHT", -4, 0)
		box:SetTextSize(14)
		box.edit:SetText(getFn() or "")
		r:SetScript("OnClick", function() box.edit:SetFocus() end)
		return r, box
	end

	-- a button on the right of its row; the row runs it too
	function L:Button(label, text, onClick)
		local r = place(W.SettingsRow(p, label))
		local b = W.Button(r, text)
		b:SetSize(110, 22); b:SetPoint("RIGHT", -4, 0)
		b:SetScript("OnClick", onClick)
		r:SetScript("OnClick", onClick)
		return r, b
	end

	-- a read-only value on the right of its row
	function L:Value(label, getFn)
		local r = place(W.SettingsRow(p, label))
		local v = W.FixedText(r, "", 15)
		v:SetPoint("RIGHT", -8, 0); v:SetJustifyH("RIGHT")
		local function paint() v:SetText(getFn() or "") end
		paint()
		self.refreshers[#self.refreshers + 1] = paint
		return r, paint
	end

	-- the page is as tall as its longer column
	function L:Done()
		p:SetHeight(self:Height())
		local sf = p:GetParent()
		if sf and sf._relayout then sf._relayout() end
		p:HookScript("OnShow", function() for _, fn in ipairs(self.refreshers) do fn() end end)
	end
	return L
end

-- ------------------------------------------------------------
-- The page: one pill per area, every option of the addon in one place.
-- Work you do during a raid (loot mode, council night, soft reserves, the
-- wishlist) stays on its own page.
-- ------------------------------------------------------------
function Okanvil:BuildSettings()
	local fill = newFillPanel()
	local host = fill.child

	local tabs = {
		{ key = "general", label = "General", icon = "Interface\\Icons\\INV_Misc_Gear_01", height = 400,
		  build = function(pg) Okanvil:Settings_General(pg) end },
		{ key = "loot",    label = "Loot",    icon = "Interface\\Icons\\INV_Misc_Coin_02", height = 360,
		  build = function(pg) Okanvil:Settings_Loot(pg) end },
		{ key = "raid",    label = "Raid",    icon = "Interface\\Icons\\Achievement_Dungeon_Icecrown_IcecrownEntrance", height = 460,
		  build = function(pg) Okanvil:Settings_RaidTools(pg) end },
		-- the key stays "invite": the marks bar and old shortcuts open it by that name
		{ key = "invite",  label = "Groups",  icon = "Interface\\Icons\\Spell_ChargePositive", height = 460,
		  build = function(pg) Okanvil:Settings_Invite(pg) end },
	}

	local dash = W.Dashboard(host, {
		title = "Settings",
		subtitle = "Shared by all your characters",
		icon = Okanvil.ICONS.settings,
		drawerWidth = 0,
		footerHeight = 0,
		pills = true,
		tabs = tabs,
	})
	fill.dash = dash
	fill:SetScript("OnShow", function() dash:Refresh() end)
	return fill
end

local RARITY = {
	{ text = "|cff9d9d9dPoor and up|r", value = 0 }, { text = "|cffffffffCommon and up|r", value = 1 },
	{ text = "|cff1eff00Uncommon and up|r", value = 2 }, { text = "|cff0070ddRare and up|r", value = 3 },
	{ text = "|cffa335eeEpic|r", value = 4 },
}

-- ---- General ----------------------------------------------------------------
function Okanvil:Settings_General(p)
	local db = self.db
	local L = Layout(p)

	L:Col(1)
	L:Section("Window")
	L:Stepper("Scale", 0.6, 1.8, 0.05, function() return db.scale or 1 end,
		function(v) db.scale = v; db.scaleSetByUser = true; Okanvil.win:SetScale(v) end)
	L:Stepper("Opacity", 0.3, 1.0, 0.05, function() return db.bgAlpha or 0.95 end,
		function(v) db.bgAlpha = v; Okanvil:ReskinAll(v) end)
	L:Stepper("Text size", 0.85, 1.5, 0.05, function() return db.textScale or 1 end,
		function(v) db.textScale = v; Okanvil:ApplyFonts() end)
	L:Choice("Font", function()
			local out = {}
			for _, f in ipairs((LSM and LSM:List("font")) or { db.font }) do out[#out + 1] = { text = f, value = f } end
			return out
		end,
		function() return db.font end, function(v) db.font = v; Okanvil:ApplyFonts() end, 170, "font")
	L:Section("Behaviour")
	L:Check("Close windows on a DBM pull", function() return db.closeOnPull ~= false end,
		function(v) db.closeOnPull = v and true or false end)

	L:Col(2)
	L:Section("Background")
	L:Check("Background art", function() return (db.ratArt or "on") ~= "off" end,
		function(v) db.ratArt = v and "on" or "off"; Okanvil:RefreshRatArt() end)
	L:Stepper("Art strength", 0.0, 0.8, 0.05, function() return db.ratAlpha or 0.45 end,
		function(v) db.ratAlpha = v; Okanvil:RefreshRatArt() end)
	L:Section("About")
	L:Button("Version check", "Check", function() Okanvil:ShowVersionChecker() end)
	L:Button("Run setup again", "Open setup", function() Okanvil:ShowSetup() end)
	self:Settings_Tools(p, L)
	L:Done()
end

-- ---- Loot -------------------------------------------------------------------
function Okanvil:Settings_Loot(p)
	local db = self.db
	local Lo = Okanvil.Loot
	local L = Layout(p)

	local function keep(key, def)
		return function()
			if db[key] == nil then return def end
			return db[key] and true or false
		end, function(v) db[key] = v and true or false end
	end

	L:Col(1)
	L:Section("Record loot")
	L:Check("Record dungeon loot", function() return db.recordDungeon ~= false end,
		function(v) db.recordDungeon = v and true or false end)
	L:Choice("Dungeon quality", RARITY, function() return db.lootThresholdDungeon or 3 end,
		function(v) db.lootThresholdDungeon = v end)
	L:Check("Keep dungeon runs", keep("lootKeepDungeon", false))
	L:Check("Record raid loot", function() return db.recordRaid ~= false end,
		function(v) db.recordRaid = v and true or false end)
	L:Choice("Raid quality", RARITY, function() return db.lootThresholdRaid or 4 end,
		function(v) db.lootThresholdRaid = v end)
	L:Check("Keep raid runs", keep("lootKeepRaid", true))
	L:Section("Council")
	L:Check("Ask when a corpse opens", function()
			return db.council and db.council.autoAsk and true or false
		end, function(v)
			db.council = db.council or {}
			db.council.autoAsk = v and true or false
		end)

	L:Col(2)
	if Lo and Lo.RollMsg then
		L:Section("Rolls")
		L:Field("Main spec message", function() return Lo.RollMsg("ms") end, function(t) Lo.SetRollMsg("ms", t) end)
		L:Field("Off spec message", function() return Lo.RollMsg("os") end, function(t) Lo.SetRollMsg("os", t) end)
		local SR = Okanvil.SoftRes
		if SR and SR.Msg then
			L:Field("Reserve message", function() return SR.Msg() end, function(t) SR.SetMsg(t) end)
		end
		if Lo.RollTimer then
			L:Stepper("Roll timer (seconds)", 0, 120, 1, function() return Lo.RollTimer() end,
				function(v) Lo.SetRollTimer(v) end)
		end
		L:Section("Award")
		L:Check("Whisper the winner", function() return Lo.WhisperWinner() end,
			function(v) Lo.SetWhisperWinner(v and true or false) end)
		L:Field("Winner message", function() return Lo.WhisperMsg() or "" end, function(t) Lo.SetWhisperMsg(t) end)
	end
	-- the priority list is an officer page; its option is only there for them
	if Okanvil.U and Okanvil.U.canSeePrio and Okanvil.U.canSeePrio() and Okanvil.LootPrio then
		L:Section("Priority")
		L:Check("One name per line", function() return Okanvil.LootPrio.MultiLine() end,
			function() Okanvil.LootPrio.ToggleMultiLine() end)
	end
	L:Done()
end

-- ---- Raid -------------------------------------------------------------------
function Okanvil:Settings_RaidTools(p)
	local db = self.db
	local L = Layout(p)

	L:Col(1)
	local RC = Okanvil.RaidCheck
	if RC then
		local function rc()
			db.raidcheck = db.raidcheck or {}
			return db.raidcheck
		end
		local function redraw() if RC.RenderToast then RC:RenderToast() end end
		L:Section("Ready check")
		L:Check("Show on a ready check", function() return rc().onReadyCheck ~= false end,
			function(v) rc().onReadyCheck = v and true or false end)
		L:Check("Close when everyone is ready", function() return rc().closeWhenClear ~= false end,
			function(v) rc().closeWhenClear = v and true or false end)
		L:Check("Minutes on icons", function() return rc().hideNumbers ~= true end,
			function(v) rc().hideNumbers = not v; redraw() end)
		L:Check("Show missing buffs", function() return rc().hideMissing ~= true end,
			function(v) rc().hideMissing = not v; redraw() end)
		L:Choice("Sort by", { { text = "Group", value = "group" }, { text = "Class", value = "class" }, { text = "Name", value = "name" } },
			function() return rc().sort or "group" end, function(v) rc().sort = v; redraw() end)
		L:Stepper("Size", 70, 160, 5, function() return rc().scale or 100 end,
			function(v) rc().scale = v; if RC.SetToastScale then RC:SetToastScale(v) end end)
		L:Button("Preview", "Show", function() if RC.ShowToast then RC:ShowToast(true) end end)
	end

	local MB = Okanvil.MarksBar
	if MB then
		local function mb()
			db.marksbar = db.marksbar or {}
			return db.marksbar
		end
		L:Section("Marks bar")
		L:Check("Show the marks bar", function() return mb().enabled and true or false end,
			function(v) if MB.Toggle then MB:Toggle(v and true or false) end end)
		L:Stepper("Size", 70, 160, 5, function() return mb().scale or 100 end,
			function(v) mb().scale = v; if MB.Refresh then MB:Refresh() end end)
		L:Stepper("Pull timer (seconds)", 3, 30, 1, function() return mb().pullTime or 10 end,
			function(v) mb().pullTime = v end)
	end

	L:Col(2)
	-- the boss notes' fight window
	local WIN = Okanvil.NotesWindow
	if WIN and Okanvil:IsModuleEnabled("Okanvil-Notes") then
		L:Section("Fight notes")
		local N = Okanvil.Notes
		if N and N.SetAutoZone then
			L:Check("Follow the room", function() return N.AutoZone() end,
				function(v) N.SetAutoZone(v and true or false) end)
		end
		L:Check("Only in the boss room", function() return WIN.OnlyInRoom() end,
			function(v) WIN.SetOnlyInRoom(v and true or false) end)
		L:Check("Only my lines", function() return WIN.OnlyMine() end,
			function(v) WIN.SetOnlyMine(v and true or false) end)
		L:Stepper("Background", 0, 100, 5, function() return WIN.GetAlpha() end, function(v) WIN.SetAlpha(v) end)
		L:Stepper("Text size", 10, 20, 1, function() return WIN.GetSize() end, function(v) WIN.SetSize(v) end)
		L:Stepper("Icon size", 12, 32, 2, function() return WIN.GetIconSize() end, function(v) WIN.SetIconSize(v) end)
		L:Check("Sync notes with officers", function() return not OkanvilNotesDB or OkanvilNotesDB.share ~= false end,
			function(v) if OkanvilNotesDB then OkanvilNotesDB.share = v and true or false end end)
	end

	-- Combat Logs has no page of its own, so its switches live here
	local LDB = OkanvilLogs and OkanvilLogs.DB and OkanvilLogs.DB()
	if LDB then
		L:Section("Combat log")
		L:Check("Ask when entering a raid", function() return LDB.askOnEnter and true or false end,
			function(v) LDB.askOnEnter = v and true or false end)
		L:Check("Start at the first pull", function() return LDB.autoOnPull == true end,
			function(v) LDB.autoOnPull = v and true or false end)
		L:Check("Lock the recording timer", function() return LDB.recLocked and true or false end,
			function(v)
				LDB.recLocked = v and true or false
				if OkanvilLogs.ApplyRecLock then OkanvilLogs.ApplyRecLock() end
			end)
	end
	L:Done()
end

-- ---- Groups: keyword auto-invite, and the PuG options ------------------------
function Okanvil:Settings_Invite(p)
	local I = Okanvil.Invite
	local L = Layout(p)
	L:Col(1)
	if I then
		L:Section("Invite")
		L:Check("Invite on a keyword", function() return I.KeywordEnabled() end,
			function(v) I.SetKeywordEnabled(v and true or false) end)
		L:Check("From whispers", function() return I.db().whisperInvite and true or false end,
			function(v) I.db().whisperInvite = v and true or false end)
		L:Check("From guild chat", function() return I.db().guildInvite and true or false end,
			function(v) I.db().guildInvite = v and true or false end)
		L:Field("Keywords", function() return I.db().keyword or "inv" end, function(t) I.db().keyword = t end)
	end

	L:Col(2)
	local P = Okanvil.PuG
	if P and P.DB and P.DB() then
		L:Section("PuG")
		L:Check("Sort joiners by role", function() return P.DB().sortGroups and true or false end,
			function(v) P.DB().sortGroups = v and true or false end)
		L:Check("Also /yell the LFM", function() return P.DB().toYell and true or false end,
			function(v) P.DB().toYell = v and true or false end)
	end
	if Okanvil:IsModuleEnabled("Okanvil-RaidFinder") and OkanvilRaidFinderDB then
		self:Settings_RaidFinder(p, L)
	end
	L:Done()
end

-- ---- Raid Finder --------------------------------------------------------------
-- drawn into another pill's layout (Groups)
function Okanvil:Settings_RaidFinder(p, L)
	local db = OkanvilRaidFinderDB
	local function render()
		if Okanvil.RaidFinder_Render then pcall(Okanvil.RaidFinder_Render) end
	end

	L:Section("Raid Finder")
	-- your spec and gear score, as /w and Join send them
	local _, paintSpec = L:Value("Spec", function()
		local spec = Okanvil.RaidFinder_MySpec and Okanvil.RaidFinder_MySpec()
		local _, token = UnitClass("player")
		local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
		local hex = c and ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) or "|cffdcddde"
		return hex .. (spec or "?") .. "|r"
	end)
	local _, paintGS = L:Value("Gear score", function()
		local det = Okanvil.RaidFinder_DetectedGS and Okanvil.RaidFinder_DetectedGS()
		return "|cffffd200" .. (det and string.format("%.1fk", det / 1000) or "n/a") .. "|r"
	end)
	Okanvil.RaidFinder_RefreshGear = function() paintSpec(); paintGS() end
	L:Field("Gear score override", function()
			return (db.gsOverride and db.gsOverride > 0) and tostring(db.gsOverride) or ""
		end, function(text)
			local n = tonumber(((text or ""):gsub("[^%d.]", "")))
			if n and n < 100 then n = n * 1000 end          -- "6.2" means 6200
			db.gsOverride = n and math.floor(n) or 0
			paintGS()
		end, 80)
	L:Check("Short spec names", function() return db.shortSpec and true or false end,
		function(v) db.shortSpec = v and true or false; paintSpec() end)
	L:Section("Raid Finder scanning")
	L:Check("Chat channels", function() return db.scanChannels and true or false end,
		function(v) db.scanChannels = v and true or false end)
	L:Check("Yell", function() return db.scanYell and true or false end,
		function(v) db.scanYell = v and true or false end)
	L:Check("Keep scanning in the background", function() return db.background and true or false end,
		function(v) db.background = v and true or false end)

	L:Section("Raid Finder list")
	L:Check("Show raids I'm saved to", function() return db.showSaved and true or false end,
		function(v) db.showSaved = v and true or false; render() end)
	L:Stepper("Hide listings after (s)", 20, 300, 5, function() return db.expiry or 60 end,
		function(v) db.expiry = v end)
	L:Stepper("Minimum gear score", 0, 7000, 100, function() return db.minGS or 0 end,
		function(v) db.minGS = v; render() end)
	L:Button("Verify achievement IDs", "Verify", function()
		if Okanvil.RaidFinder_VerifyAchievements then Okanvil.RaidFinder_VerifyAchievements() end
	end)
end

-- ---- Tools: the farm's price, and what item tooltips show ----------------------
-- drawn into another pill's layout (General)
function Okanvil:Settings_Tools(p, L)
	local F = Okanvil.Farm
	if F and F.DB and Okanvil:IsModuleEnabled("Okanvil-Farm") then
		L:Section("Farm")
		L:Check("Value loot at vendor price", function() return F.DB().price == "vendor" end,
			function(v)
				F.DB().price = v and "vendor" or "auto"
				if F.RefreshWindow then F.RefreshWindow() end
			end)
	end

	L:Section("Tooltips")
	-- nil = on: these were switched only by /okup and /okids until now
	local function up(key)
		return function() return not (self.db.upgrades and self.db.upgrades[key] == false) end,
			function(v)
				self.db.upgrades = self.db.upgrades or {}
				self.db.upgrades[key] = v and true or false
			end
	end
	if Okanvil:IsModuleEnabled("Okanvil-Upgrades") then
		L:Check("Upgrade sound", up("sound"))
		L:Check("BiS rank", up("bisTip"))
		L:Check("Fits your spec", up("fitTip"))
		L:Check("Drops from", up("dropTip"))
	end
	if OkanvilIDsDB then
		L:Check("Spell and item IDs", function() return OkanvilIDsDB.tipIDs ~= false end,
			function(v) OkanvilIDsDB.tipIDs = v and true or false end)
	end
end

-- ---- Version checker popup (RCLootCouncil-style) -------------------------
-- Its own window, so it can stay open while replies trickle in and the Settings
-- page can be closed. One shared frame, rebuilt rows on every repaint.
local verDlg
local DOWNLOAD_URL = Okanvil.DOWNLOAD_URL
function Okanvil:ShowVersionChecker()
	local f = verDlg
	if not f then
		f = Okanvil:Popup("Okanvil version check")
		-- Wider and taller: this is a list you read across a raid, and at 320px
		-- the names sat in a narrow column with most of the window empty.
		f:SetSize(420, 460)

		-- scope buttons, RCLoot-style: Group | Guild
		local bGroup = W.Button(f, "Group", "primary")
		bGroup:SetSize(110, 26); bGroup:SetPoint("TOPLEFT", 12, -34)
		local bGuild = W.Button(f, "Guild")
		bGuild:SetSize(110, 26); bGuild:SetPoint("LEFT", bGroup, "RIGHT", 8, 0)

		local status = W.Text(f, "", "body", "dim")
		status:SetPoint("LEFT", bGuild, "RIGHT", 12, 0)
		f.status = status

		-- results list inside a clipped scroll (long guild rosters must not spill)
		local box = W.Frame(f, "soft")
		box:SetPoint("TOPLEFT", 10, -62); box:SetPoint("BOTTOMRIGHT", -10, 44)

		-- The download link, to copy and paste wherever you choose. Never whispered
		-- to the list: a line to every name that did not answer reads as spam.
		-- Only shown once the check has finished: while it runs, "no reply" still
		-- means "not yet".
		local bLink = W.Button(f, "Copy download link")
		bLink:SetSize(260, 26); bLink:SetPoint("BOTTOMLEFT", 12, 10)
		bLink:Hide()
		f.bLink = bLink
		local scroll = CreateFrame("ScrollFrame", nil, box)
		scroll:SetPoint("TOPLEFT", 6, -6); scroll:SetPoint("BOTTOMRIGHT", -6, 6)
		Okanvil.Clip(scroll)
		local child = CreateFrame("Frame", nil, scroll)
		child:SetWidth(1); child:SetHeight(1)
		scroll:SetScrollChild(child)
		scroll:EnableMouseWheel(true)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local cur = self:GetVerticalScroll()
			local max = math.max(0, child:GetHeight() - self:GetHeight())
			local nxt = cur - delta * 60
			if nxt < 0 then nxt = 0 elseif nxt > max then nxt = max end
			self:SetVerticalScroll(nxt)
		end)
		f.scroll, f.child = scroll, child

		-- Body size, not "label": this is the content of the window, read at a
		-- glance while a raid waits, not a field caption.
		local out = W.Text(child, "", "body")
		out:SetPoint("TOPLEFT", 0, 0)
		out:SetJustifyH("LEFT")
		if out.SetJustifyV then out:SetJustifyV("TOP") end
		f.out = out

		-- One row per player: name, "Patch-Y" in green with it, red without (grey
		-- while it is asking), then the Okanvil version.
		local ROW_H, PY_X, VER_X = 18, 150, 240
		f.rows = {}
		local head = CreateFrame("Frame", nil, child)
		head:SetHeight(ROW_H); head:SetPoint("TOPLEFT", 0, 0); head:SetPoint("RIGHT", child, "RIGHT", 0, 0)
		for _, col in ipairs({ { "Player", 0 }, { "Patch", PY_X }, { "Okanvil", VER_X } }) do
			local t = W.Text(head, col[1], "note", "dim"); t:SetPoint("LEFT", col[2], 0)
		end
		W.Hairline(head, "BOTTOM", 0)
		local function row(i)
			local r = f.rows[i]
			if r then return r end
			r = CreateFrame("Frame", nil, child)
			r:SetHeight(ROW_H)
			r.name = W.Text(r, "", "body"); r.name:SetPoint("LEFT", 0, 0)
			r.py = W.Text(r, "Patch-Y", "body"); r.py:SetPoint("LEFT", PY_X, 0)
			r.ver = W.Text(r, "", "body"); r.ver:SetPoint("LEFT", VER_X, 0)
			f.rows[i] = r
			return r
		end

		local function paint()
			local Comms = Okanvil.Comms
			if not Comms then f.out:SetText("|cffff5555Comms unavailable.|r"); return end
			local replies = Comms.VersionReplies and Comms.VersionReplies() or {}
			local roster = Comms.GroupRoster and Comms.GroupRoster(f._scope) or {}
			local mine = tostring(Okanvil.version or "?")
			local waiting = Comms.VersionCheckRunning and Comms.VersionCheckRunning()
			local py = Comms.PatchYReplies and Comms.PatchYReplies() or {}
			local ok, old, none, pyN = 0, 0, 0, 0
			local missing = {}
			for _, r in ipairs(f.rows) do r:Hide() end
			for i, name in ipairs(roster) do
				local v = replies[name]
				local r = row(i)
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", 0, -(ROW_H + 4) - (i - 1) * ROW_H)
				r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
				if not v then
					none = none + 1
					missing[#missing + 1] = name
					r.ver:SetText(waiting and "|cff8a8d93...|r" or "|cffff5555no reply|r")
				elseif v == mine then
					ok = ok + 1
					r.ver:SetText("|cffffd200" .. v .. "|r")
				else
					old = old + 1
					r.ver:SetText("|cffff8040" .. v .. "|r")
				end
				-- the guild's client patch, asked in the same check
				if py[name] then pyN = pyN + 1 end
				r.name:SetText(name)
				r.py:SetText((py[name] and "|cff40c040" or waiting and "|cff8a8d93" or "|cffff5555") .. "Patch-Y|r")
				r:Show()
			end
			if #roster == 0 then
				head:Hide()
				f.out:SetText("|cff8a8d93Nobody to ask.|r"); f.out:Show()
			else
				head:Show(); f.out:Hide()
			end
			f.status:SetText("|cffffd200" .. ok .. "|r / |cffff8040" .. old
				.. "|r / |cffff5555" .. none .. "|r"
				.. "   |cff8a8d93Patch-Y|r " .. pyN .. "/" .. #roster
				.. (waiting and "  |cff8a8d93asking...|r" or ""))
			f._missing = missing
			if not waiting and #missing > 0 then
				f.bLink:Show()
			else
				f.bLink:Hide()
			end
			-- size the scroll child to the rows so the wheel range is right
			local w = f.scroll:GetWidth() or 0
			if w < 10 then w = 388 end            -- first paint runs before layout
			f.out:SetWidth(w)
			f.child:SetWidth(w)
			f.child:SetHeight(math.max((#roster + 1) * ROW_H + 12, f.out:GetStringHeight() + 8, 1))
		end
		f.paint = paint

		local function ask(scope)
			local Comms = Okanvil.Comms
			if not (Comms and Comms.RequestVersions) then
				f.out:SetText("|cffff5555Comms unavailable.|r"); return
			end
			if Comms.VersionCheckRunning and Comms.VersionCheckRunning() then return end
			f._scope = scope
			local sent = Comms.RequestVersions(scope, function() paint() end, 5)
			if not sent then
				f.out:SetText(scope == "guild"
					and "|cffff5555You're not in a guild.|r"
					or "|cffff5555You're not in a party or raid.|r")
				f.status:SetText("")
				return
			end
			paint()
		end
		bLink:SetScript("OnClick", function()
			Okanvil:ShowExport(DOWNLOAD_URL, "Okanvil download link", "Ctrl+C to copy, then paste it where you want.")
		end)
		bGroup:SetScript("OnClick", function() ask("group") end)
		bGuild:SetScript("OnClick", function() ask("guild") end)

		verDlg = f
	end
	-- repaint live as whispers trickle in (rebound on every open: last opener wins)
	if Okanvil.Comms then Okanvil.Comms.onVersionReply = function() if f:IsShown() then f.paint() end end end
	f._scope = f._scope or "group"
	f.paint()
	f:Show()
end
