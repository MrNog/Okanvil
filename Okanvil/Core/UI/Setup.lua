-- ============================================================
-- Okanvil -- UI: first-run setup
--
-- A short step-by-step setup in the style of ElvUI's installer: one page per
-- step, Back / Next, progress pips. Shown once, on the first login of an
-- install that has never run Okanvil (db.setupPending, set in Core.lua when
-- Okanvil_DB is created). /okanvil setup and the Settings button bring it back.
--
-- The guild rank is read, not asked: officer tools (exports, the master-loot
-- section, the council's Round and Priority tabs) follow the rank on their own,
-- so the setup only has to say so. What is left to choose is small -- the two
-- essentials, and which optional extras this character wants.
--
-- Nothing applies until Finish: every choice is a draft, so closing the window
-- half way through leaves the install exactly as it was.
-- ============================================================

local Okanvil = Okanvil
local W = Okanvil.W

local WIN_W, WIN_H = 540, 520
local X = 20                      -- side gutter
local CONTENT_TOP = -76           -- below the header rule

local WALLPAPER = "Interface\\AddOns\\Okanvil\\Media\\setup-bg"

local GREEN, DIM, GOLD = "|cff7cfc8a", "|cff8a8d93", "|cffe0b860"
local ICON_OK = "Interface\\RaidFrame\\ReadyCheck-Ready"

-- The two things every raider needs. Plain ON / OFF lines, because turning
-- either off has a cost the raider should see before doing it.
local ESSENTIALS = {
	{ key = "__council",
	  on  = "A popup asks what each item is worth to you. Your answer shows on the council board.",
	  off = "No popup -- the council cannot see you and decides without you." },
	{ key = "Okanvil-Notes",
	  on  = "Boss notes switch on as you enter each room; guild WeakAuras read your assignment.",
	  off = "No notes, and note-driven WeakAuras show nothing." },
}

-- Optional for everyone, on two pages: a name and one line of what it does.
-- `officer` = on by default for an officer; `all` = on by default for everyone.
local EXTRAS = {
	{ key = "__loot", page = "raid", name = "Loot", officer = true,
	  line = "Every drop per boss, who won it, and the mini roll for the master looter." },
	{ key = "Okanvil-Upgrades", page = "raid", name = "Upgrades", all = true,
	  line = "Which drops beat your gear, BiS lists for every spec, a toast when one drops." },
	{ key = "Okanvil-RaidFinder", page = "raid", name = "Raid Finder", all = true,
	  line = "LFM spam from chat turned into one list of raids you can join." },
	{ key = "Okanvil-PuG", page = "raid", name = "PuG", officer = true,
	  line = "Build your own raid: LFM line, spam, whispers caught and invited." },
	{ key = "Okanvil-Ranking", page = "guild", name = "Ranking", all = true,
	  line = "The guild's log rankings, and each raider's rank on their tooltip." },
	{ key = "__guild", page = "guild", name = "Raid snapshots", all = true,
	  line = "Who was in each raid, saved quietly for attendance." },
	{ key = "Okanvil-Recruit", page = "guild", name = "Recruit", officer = true,
	  line = "Recruitment ads on a timer, and invites for whoever answers." },
	{ key = "Okanvil-Logs", page = "guild", name = "Combat Logs", officer = true,
	  line = "Combat logging starts and stops by itself in every raid." },
	{ key = "Okanvil-IDs", page = "guild", name = "ID Finder",
	  line = "Spell and item IDs for WeakAuras, searchable, and on tooltips." },
	{ key = "Okanvil-Farm", page = "guild", name = "Farm",
	  line = "Gold per hour while you farm." },
}

-- Raised when an update adds a step every install should see: an install that
-- finished an older setup gets it again once, opened on the first new step.
Okanvil.SETUP_VERSION = 2

local setupF

-- Jobs Okanvil and another addon both do. Like ElvUI's incompatible-addon check:
-- an addon counts when it is ENABLED in the addon list (loaded or not yet), and
-- the player keeps one of the two. The setup asks on its Addons page; after
-- that the login check asks again only if one comes back on.
--   on / off / reset: is Okanvil's version on, turn it off, back to its default
--   module:   the Okanvil module behind it, switched on with Okanvil's pick
local function upgDB() Okanvil.db.upgrades = Okanvil.db.upgrades or {}; return Okanvil.db.upgrades end
local function idsDB() OkanvilIDsDB = OkanvilIDsDB or {}; return OkanvilIDsDB end
local RIVALS = {
	{ addon = "Bistooltip", line = "BiS lists on item tooltips", sub = "Which specs want the item, BIS / alt 2 / ...",
	  module = "Okanvil-Upgrades",
	  on = function() return upgDB().bisTip ~= false end, off = function() upgDB().bisTip = false end,
	  reset = function() upgDB().bisTip = nil end },
	{ addon = "ClassLoot", line = "Who an item fits", sub = "Stars per class and spec, on every raid item",
	  module = "Okanvil-Upgrades",
	  on = function() return upgDB().fitTip ~= false end, off = function() upgDB().fitTip = false end,
	  reset = function() upgDB().fitTip = nil end },
	{ addon = "RCLootCouncil", line = "Loot council", sub = "The popup raiders answer, the officers' board",
	  module = "__council" },
	{ addon = "WoWPuG", line = "Build a PuG", sub = "LFM line, spam, whisper invites", module = "Okanvil-PuG" },
	{ addon = "RaidBrowser", line = "Raid finder", sub = "Raids advertised in chat, in one list",
	  module = "Okanvil-RaidFinder" },
	{ addon = "SpellID", line = "IDs on tooltips", sub = "Spell and item IDs, for WeakAuras", module = "Okanvil-IDs",
	  on = function() return idsDB().tipIDs ~= false end, off = function() idsDB().tipIDs = false end,
	  reset = function() idsDB().tipIDs = nil end },
}
Okanvil.RIVALS = RIVALS

local function addonEnabled(name)
	local _, _, _, enabled, _, reason = GetAddOnInfo(name)
	return enabled and reason ~= "MISSING"
end
-- installed, on or off
local function addonInstalled(name)
	local _, _, _, _, _, reason = GetAddOnInfo(name)
	return reason ~= "MISSING"
end
-- the rivals this install has: enabled ones only (the login check), or every
-- installed one, on or off (the setup's page, so a turned-off one can come back)
local function rivalsHere(installed)
	local out = {}
	for _, r in ipairs(RIVALS) do
		if (installed and addonInstalled(r.addon)) or addonEnabled(r.addon) then out[#out + 1] = r end
	end
	return out
end
local function oursOn(r)
	if r.module and not Okanvil:IsModuleEnabled(r.module) then return false end
	return not r.on or r.on()
end
-- Keep Okanvil's: the other addon is turned off (a reload follows). Keep theirs:
-- Okanvil's version goes off (the whole module when it is nothing else).
local function keepOkanvil(r) DisableAddOn(r.addon) end
local function keepTheirs(r)
	if r.off then r.off() elseif r.module then Okanvil:SetModuleEnabled(r.module, false) end
end

-- After login: any rival on while Okanvil's version is on too -> one dialog.
StaticPopupDialogs.OKANVIL_RIVALS = {
	text = "These addons do a job Okanvil already does:\n\n%s\n\nKeep Okanvil's, or yours?",
	button1 = "Okanvil",
	button2 = "Keep mine",
	OnAccept = function(_, list)
		for _, r in ipairs(list or {}) do keepOkanvil(r) end
		ReloadUI()
	end,
	OnCancel = function(_, list, reason)
		if reason ~= "clicked" then return end
		for _, r in ipairs(list or {}) do keepTheirs(r) end
		Okanvil:Print("kept your addons; Okanvil's versions are off. /okanvil setup to change it.")
	end,
	timeout = 0, whileDead = 1, hideOnEscape = false,
}
function Okanvil:CheckRivals()
	if self.db.setupPending or InCombatLockdown() then return end
	local list, names = {}, {}
	for _, r in ipairs(rivalsHere()) do
		if IsAddOnLoaded(r.addon) and oursOn(r) then
			list[#list + 1] = r
			names[#names + 1] = GOLD .. r.addon .. "|r -- " .. r.line
		end
	end
	if #list == 0 then return end
	local dlg = StaticPopup_Show("OKANVIL_RIVALS", table.concat(names, "\n"))
	if dlg then dlg.data = list end
end
do
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_LOGIN")
	ev:SetScript("OnEvent", function()
		if Okanvil.Comms and Okanvil.Comms.After then
			Okanvil.Comms.After(8, function() Okanvil:CheckRivals() end)
		end
	end)
end

local function finish()
	Okanvil.db.setupPending = nil
	if setupF then setupF:Hide() end
end

-- A wrapped paragraph at (x, y); returns the y just below it.
local function para(parent, text, x, y, width, size, role)
	local fs = W.Text(parent, text, size or "body", role)
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetWidth(width)
	fs:SetJustifyH("LEFT")
	return y - fs:GetStringHeight() - 8, fs
end

local function icon(parent, path, size)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetSize(size, size)
	if path then t:SetTexture(path); t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	return t
end

function Okanvil:ShowSetup(fromVersion)
	local applyAll, tourB
	if setupF then setupF:Hide() end
	local self_ = self
	local C = self.Colors
	local U = self.U
	local I = self.ICONS or {}

	local f = CreateFrame("Frame", "Okanvil_Setup", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetPoint("CENTER")
	f:SetSize(WIN_W, WIN_H)
	self:Skin(f)
	f:SetBackdropColor(C.panelD[1], C.panelD[2], C.panelD[3], 0.97)
	setupF = f

	-- Wallpaper, faded so text on top stays readable; cropped top and bottom so
	-- the square image fills the wider window without stretching. A missing file
	-- simply draws nothing (SetTexture's return value is not reliable on 3.3.5a).
	local wall = f:CreateTexture(nil, "BORDER")
	wall:SetPoint("TOPLEFT", 1, -1)
	wall:SetPoint("BOTTOMRIGHT", -1, 1)
	wall:SetTexture(WALLPAPER)
	local span = WIN_H / WIN_W
	wall:SetTexCoord(0, 1, 0.5 - span / 2, 0.5 + span / 2)
	wall:SetAlpha(0.45)

	-- ---- who is this: rank decides the defaults ----
	local me = UnitName("player") or ""
	-- No guild = a pugger: the guild tools (council, notes, snapshots, recruiting)
	-- have nothing to talk to, so they start off.
	local guilded = IsInGuild and IsInGuild() and true or false
	local officer = guilded and U and U.canSeePrio and U.canSeePrio(me) or false
	local rankIdx = U and U.guildRankOf and U.guildRankOf(me)
	local rankName = rankIdx and U.rankName and U.rankName(rankIdx) or nil

	-- ---- draft state: nothing touches the real settings until Finish ----
	local items = self:ModuleItems()
	local byKey, want = {}, {}
	for _, it in ipairs(items) do
		byKey[it.key] = it
		want[it.key] = self:IsModuleEnabled(it.key)
	end
	local MB = self.MarksBar
	local wantBar = not (self.db.marksbar and self.db.marksbar.enabled == false)
	-- the Addons page: Okanvil's pick by default
	local rivals = rivalsHere(true)
	-- what is in use now: the other addon when it is on and Okanvil's is off,
	-- else Okanvil's
	local pick = {}
	for _, r in ipairs(rivals) do
		pick[r.addon] = (addonEnabled(r.addon) and not oursOn(r)) and "theirs" or "okanvil"
	end
	local wantWall = (self.db.ratArt or "on") ~= "off"

	-- First run: fill the draft from the rank. A re-run keeps what is set now.
	if self.db.setupPending then
		if guilded then
			for _, e in ipairs(ESSENTIALS) do want[e.key] = true end
			for _, e in ipairs(EXTRAS) do
				want[e.key] = e.all or (officer and e.officer) or false
			end
			wantBar = officer
		else
			-- Pug setup: find raids and build them, nothing else.
			for key in pairs(want) do want[key] = false end
			want["Okanvil-RaidFinder"] = byKey["Okanvil-RaidFinder"] and true or nil
			want["Okanvil-PuG"] = byKey["Okanvil-PuG"] and true or nil
			wantBar = false
		end
	end

	-- ---- chrome: step icon + title, close, footer ----
	local stepIcon = icon(f, nil, 30)
	stepIcon:SetPoint("TOPLEFT", X, -16)
	local title = W.Text(f, "Okanvil setup", "title", "accent")
	title:SetPoint("TOPLEFT", stepIcon, "TOPRIGHT", 10, 0)
	local step = W.Text(f, "", "head")
	step:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

	local close = W.Button(f, "X")
	close:SetSize(24, 22)
	close:SetPoint("TOPRIGHT", -10, -10)
	close:Tooltip("Close without changing anything. /okanvil setup brings this back.")
	close:SetScript("OnClick", finish)

	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetTexture("Interface\\Buttons\\WHITE8x8")
	rule:SetVertexColor(C.border[1], C.border[2], C.border[3], 1)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", X, -60)
	rule:SetPoint("TOPRIGHT", -X, -60)

	local prev = W.Button(f, "< Back")
	prev:SetSize(90, 24)
	prev:SetPoint("BOTTOMLEFT", X, 14)
	local nxt = W.Button(f, "Next >", "primary")
	nxt:SetSize(90, 24)
	nxt:SetPoint("BOTTOMRIGHT", -X, 14)

	local CW = WIN_W - X * 2          -- content width

	-- ON / OFF toggle over a draft value.
	local function toggle(parent, get, set)
		local btn = W.Button(parent, "")
		btn:SetSize(52, 20)
		local function paint()
			btn:SetKind(get() and "primary" or nil)
			btn.text:SetText(get() and "ON" or "OFF")
		end
		btn:SetScript("OnClick", function() set(not get()); paint() end)
		return btn, paint
	end

	-- One page of extras: icon, name, what it does in a line, ON / OFF. The raid
	-- page also carries the marks bar, the other one the forge wallpaper.
	local function extrasPage(host, which)
		para(host, "What each one does. Change any of them later on the Modules page.", 0, 0, CW, "body", "dim")
		local y = -24
		local paints = {}
		local function row(ic, name, line, get, set)
			local fr = CreateFrame("Frame", nil, host)
			fr:SetPoint("TOPLEFT", 0, y); fr:SetPoint("TOPRIGHT", 0, y)
			fr:SetHeight(40)
			local t = icon(fr, ic, 22); t:SetPoint("TOPLEFT", 0, -4)
			local nm = W.Text(fr, name, "body"); nm:SetPoint("TOPLEFT", t, "TOPRIGHT", 10, 2)
			local btn, paint = toggle(fr, get, set)
			btn:SetPoint("TOPRIGHT", 0, -4)
			local ds = W.Text(fr, line, "note", "dim")
			ds:SetPoint("TOPLEFT", nm, "BOTTOMLEFT", 0, -2)
			ds:SetPoint("RIGHT", btn, "LEFT", -10, 0); ds:SetJustifyH("LEFT")
			local hair = fr:CreateTexture(nil, "ARTWORK")
			hair:SetTexture("Interface\\Buttons\\WHITE8x8"); hair:SetHeight(1)
			hair:SetVertexColor(C.border[1], C.border[2], C.border[3], 0.6)
			hair:SetPoint("BOTTOMLEFT", 0, 0); hair:SetPoint("BOTTOMRIGHT", 0, 0)
			paints[#paints + 1] = paint
			y = y - 44
		end
		for _, e in ipairs(EXTRAS) do
			local it = byKey[e.key]
			if it and e.page == which then
				local key = e.key
				row(it.icon, e.name, e.line, function() return want[key] end, function(v) want[key] = v end)
			end
		end
		if which == "raid" and MB then
			row("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", "Marks bar",
				"Raid marks, ready check and pull timer while you lead or assist.",
				function() return wantBar end, function(v) wantBar = v end)
		elseif which == "guild" then
			row("Interface\\Icons\\Trade_BlackSmithing", "Forge wallpaper",
				"The smith at the anvil behind every page. Off: plain dark panels.",
				function() return wantWall end, function(v) wantWall = v end)
		end
		return function() for _, p in ipairs(paints) do p() end end
	end

	-- ---- pages ----
	local PAGES = {
		{
			name = "Welcome", icon = Okanvil.BRAND_ICON,
			build = function(host)
				local y = para(host, "Okanvil is the RATS raid toolkit.", 0, 0, CW, "head")
				y = para(host, "Three quick steps: your rank, the essentials, and any extras "
					.. "you want. Nothing changes until you press Finish.", 0, y, CW, "body", "dim")
				para(host, "Change anything later on the Modules page.", 0, y - 4, CW, "note", "dim")
			end,
		},
		{
			name = "Your rank", icon = I.guild,
			build = function(host)
				local who = W.Text(host, GOLD .. me .. "|r  --  "
					.. (not guilded and "no guild" or rankName or (officer and "officer" or "raider")), "head")
				who:SetPoint("TOPLEFT", 0, 0)
				local y = -26
				if not guilded then
					y = para(host, "You are not in a guild, so you get the pug setup: Raid Finder "
						.. "to find raids and PuG to build your own. The guild tools (loot council, "
						.. "notes, raid snapshots, recruiting) start off -- they need a guild to "
						.. "talk to.", 0, y, CW, "body", "dim")
					para(host, "Joined a guild later? Run /okanvil setup again.", 0, y - 6, CW, "note", "dim")
					return
				end
				if officer then
					y = para(host, "You are an officer, so these show up for you automatically:",
						0, y, CW, "body", "dim")
					for _, line in ipairs({
						"Loot Council setup -- the Council and Priority tabs of Loot",
						"Export buttons -- loot runs and raid snapshots, for the website",
						"Master-loot tools -- speed-run auto loot on the Loot page",
					}) do
						local ok = host:CreateTexture(nil, "ARTWORK")
						ok:SetSize(14, 14); ok:SetTexture(ICON_OK)
						ok:SetPoint("TOPLEFT", 4, y + 1)
						y = para(host, line, 24, y, CW - 24) - 2
					end
				else
					y = para(host, "You get the raider setup. Officer tools (council setup, exports, "
						.. "master-loot tools) stay hidden -- they appear by themselves if you are "
						.. "promoted.", 0, y, CW, "body", "dim")
				end
				para(host, "Your rank is read from the guild roster.", 0, y - 6, CW, "note", "dim")
			end,
		},
		{
			name = "Essentials", icon = I.council,
			build = function(host)
				local y = para(host, guilded and "Every raider should keep these two on."
					or "These two are for raiding with a guild, so they start off. Turn them on "
					.. "if your group uses them.", 0, 0, CW, "body", "dim") - 4
				local paints = {}
				for _, e in ipairs(ESSENTIALS) do
					local it = byKey[e.key]
					if it then
						local ic = icon(host, it.icon, 22); ic:SetPoint("TOPLEFT", 0, y)
						local nm = W.Text(host, it.title or e.key, "head", "accent")
						nm:SetPoint("LEFT", ic, "RIGHT", 8, 0)
						local key = e.key
						local btn, paint = toggle(host, function() return want[key] end,
							function(v) want[key] = v end)
						btn:SetPoint("TOPRIGHT", 0, y)
						paints[#paints + 1] = paint
						y = para(host, GREEN .. "ON|r  " .. e.on, 30, y - 28, CW - 30)
						y = para(host, DIM .. "OFF|r  " .. e.off, 30, y + 4, CW - 30, "body", "dim") - 8
					end
				end
				return function() for _, p in ipairs(paints) do p() end end
			end,
		},
		{ name = "Raid tools", icon = I.loot, since = 2, build = function(host) return extrasPage(host, "raid") end },
		{ name = "Guild and tools", icon = I.modules, since = 2, build = function(host) return extrasPage(host, "guild") end },
		{
			name = "Addons", icon = "Interface\\Icons\\INV_Misc_Gear_01", rivals = true, since = 2,
			build = function(host)
				local y = para(host, "You have addons that do the same job as Okanvil. Pick one for each, "
					.. "or tooltips and loot windows show things twice.", 0, 0, CW, "body", "dim") - 2
				local paints = {}
				for _, r in ipairs(rivals) do
					local fr = CreateFrame("Frame", nil, host)
					fr:SetPoint("TOPLEFT", 0, y); fr:SetPoint("TOPRIGHT", 0, y)
					fr:SetHeight(34)
					local nm = W.Text(fr, r.line, "body"); nm:SetPoint("TOPLEFT", 0, -2)
					local sb = W.Text(fr, r.sub, "note", "dim"); sb:SetPoint("TOPLEFT", nm, "BOTTOMLEFT", 0, -2)
					local theirs = W.Button(fr, r.addon); theirs:SetSize(110, 22); theirs:SetPoint("RIGHT", 0, 0)
					local ours = W.Button(fr, "Okanvil"); ours:SetSize(80, 22); ours:SetPoint("RIGHT", theirs, "LEFT", -2, 0)
					local function paint()
						ours:SetKind(pick[r.addon] == "okanvil" and "primary" or nil)
						theirs:SetKind(pick[r.addon] == "theirs" and "primary" or nil)
					end
					ours:SetScript("OnClick", function() pick[r.addon] = "okanvil"; paint() end)
					theirs:SetScript("OnClick", function() pick[r.addon] = "theirs"; paint() end)
					paints[#paints + 1] = paint
					y = y - 38
				end
				local mrt = addonEnabled("MRT")
				local note = (mrt and (GOLD .. "MRT|r also has Invite, Note and Raid Check. It is one addon, so "
					.. "Okanvil does not turn it off: switch those parts off in MRT's own options.\n\n") or "")
					.. "Finish turns off the ones you did not pick and reloads the UI."
				para(host, note, 0, y - 4, CW, "note", "dim")
				return function() for _, p in ipairs(paints) do p() end end
			end,
		},
		{
			name = "All set", icon = ICON_OK,
			build = function(host)
				local summary = W.Text(host, "", "body")
				summary:SetPoint("TOPLEFT", 0, 0)
				summary:SetWidth(CW)
				summary:SetJustifyH("LEFT")
				local howto = W.Text(host, "", "body", "dim")
				howto:SetWidth(CW)
				howto:SetJustifyH("LEFT")
				-- Finish, then the tour (after the reload, when the setup needs one)
				tourB = W.Button(host, "Finish and take the tour", "primary")
				tourB:SetSize(200, 24)
				tourB:SetScript("OnClick", function() applyAll(true) end)
				return function()
					local on = {}
					for _, it in ipairs(items) do
						if want[it.key] then on[#on + 1] = it.title or it.key end
					end
					if MB and wantBar then on[#on + 1] = "Marks bar" end
					summary:SetText(GREEN .. "Turned on:|r  "
						.. (#on > 0 and table.concat(on, ", ") or "nothing"))
					howto:ClearAllPoints()
					howto:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -18)
					howto:SetText(GOLD .. "Open Okanvil|r with |cff00ff00/okanvil|r or the anvil "
						.. "on the minimap.\n\n" .. GOLD .. "Run this again|r with "
						.. "|cff00ff00/okanvil setup|r.\n\n" .. GOLD .. "New to Okanvil?|r The tour shows "
						.. "what each part does, one page each.")
					tourB:ClearAllPoints()
					tourB:SetPoint("TOP", howto, "BOTTOM", 0, -18)
				end
			end,
		},
	}

	-- no rival addons: no Addons page
	if #rivals == 0 then
		for i = #PAGES, 1, -1 do if PAGES[i].rivals then table.remove(PAGES, i) end end
	end

	-- Build every page once into its own host; paging only shows / hides.
	for _, pg in ipairs(PAGES) do
		local host = CreateFrame("Frame", nil, f)
		host:SetPoint("TOPLEFT", X, CONTENT_TOP)
		host:SetPoint("BOTTOMRIGHT", -X, 50)
		pg.host = host
		pg.refresh = pg.build(host)
		host:Hide()
	end

	-- progress: one pip per step, centred between Back and Next
	local pips = {}
	local PIP_W, PIP_GAP = 26, 6
	local pipsW = #PAGES * PIP_W + (#PAGES - 1) * PIP_GAP
	for i = 1, #PAGES do
		local p = f:CreateTexture(nil, "ARTWORK")
		p:SetTexture("Interface\\Buttons\\WHITE8x8")
		p:SetSize(PIP_W, 4)
		p:SetPoint("BOTTOMLEFT", (WIN_W - pipsW) / 2 + (i - 1) * (PIP_W + PIP_GAP), 24)
		pips[i] = p
	end

	local cur = 1
	local function show(n)
		cur = n
		for i, pg in ipairs(PAGES) do
			if i == n then pg.host:Show() else pg.host:Hide() end
		end
		local pg = PAGES[n]
		if pg.refresh then pg.refresh() end
		stepIcon:SetTexture(pg.icon)
		step:SetText(("Step %d of %d -- %s"):format(n, #PAGES, pg.name))
		for i, p in ipairs(pips) do
			local c = (i <= n) and C.accent or C.border
			p:SetVertexColor(c[1], c[2], c[3], 1)
		end
		if n == 1 then prev:Hide() else prev:Show() end
		nxt.text:SetText(n == #PAGES and "Finish" or "Next >")
	end

	prev:SetScript("OnClick", function() if cur > 1 then show(cur - 1) end end)
	nxt:SetScript("OnClick", function()
		if cur < #PAGES then show(cur + 1); return end
		applyAll(false)
	end)
	applyAll = function(tour)
		-- the Addons page: Okanvil's pick switches its module on; theirs, ours off
		local reload = false
		for _, r in ipairs(rivals) do
			if pick[r.addon] == "okanvil" then
				if r.module and byKey[r.module] then want[r.module] = true end
			elseif r.module and byKey[r.module] and not r.off then
				want[r.module] = false
			end
		end
		for _, it in ipairs(items) do
			if want[it.key] ~= self_:IsModuleEnabled(it.key) then
				self_:SetModuleEnabled(it.key, want[it.key])
			end
		end
		if MB and MB.Toggle then MB:Toggle(wantBar) end
		self_.db.ratArt = wantWall and "on" or "off"
		if self_.RefreshRatArt then self_:RefreshRatArt() end
		for _, r in ipairs(rivals) do
			if pick[r.addon] == "okanvil" then
				-- its own switch back on (a "Keep mine" earlier turned it off)
				if r.reset then r.reset() end
				if addonEnabled(r.addon) then keepOkanvil(r); reload = true end
			else
				if r.off then r.off() end
				-- theirs, turned off earlier: back on (the UI reloads to load it)
				if not addonEnabled(r.addon) then EnableAddOn(r.addon); reload = true end
			end
		end
		self_.db.setupVersion = Okanvil.SETUP_VERSION
		finish()
		self_:Print("setup saved. |cff8a8d93Run it again any time with|r |cff00ff00/okanvil setup|r.")
		if reload then
			if tour then self_.db.tourPending = true end
			ReloadUI()
		elseif tour then
			self_:ShowTour()
		end
	end

	f:Show()
	-- an update with new steps opens on the first of them; Back still shows the rest
	local start = 1
	if fromVersion then
		for i, pg in ipairs(PAGES) do
			if (pg.since or 1) > fromVersion then start = i; break end
		end
	end
	show(start)
end

-- ============================================================
-- The tour: after the setup (or /okanvil tour), one page per part of Okanvil
-- this character has on -- what it does in a line, three things it does, and
-- where to open it. Nothing to choose; Back / Next / Done.
-- ============================================================
local TOUR = {
	{ key = "__loot", title = "Loot",
	  what = "Every drop in the raid, per boss, and who it went to.",
	  points = { "The mini roll: the master looter puts an item up, the raid rolls MS / OS in one window.",
		"History: every drop of every raid, searchable, kept per character.",
		"Soft reserves (SR) and the loot mode for the night, on the Loot page." },
	  where = "RAID > Loot, or /okroll for the mini roll" },
	{ key = "__council", title = "Loot Council",
	  what = "On a council night the officers decide, and the raid tells them what it wants.",
	  points = { "An item up: a popup asks what it is worth to you; your answer shows on the board.",
		"Wishlist: one item per raid ID that you are after, marked WISH on the board.",
		"The officers see the board, the votes and the loot priority ladder." },
	  where = "RAID > Loot, the Council tile" },
	{ key = "Okanvil-Upgrades", title = "Upgrades",
	  what = "Which raid drops beat what you wear, for the spec you are in.",
	  points = { "Each boss lists its drops that are an upgrade: BiS, #2 on your list, +13 ilvl.",
		"BiS lists: any class, spec and phase, gems and enchants included.",
		"Hover a boss for its upgrades; when one drops, a toast and the rat sound." },
	  where = "RAID > Upgrades, or /okup" },
	{ key = "Okanvil-Upgrades", title = "Item tooltips",
	  what = "Every item tooltip says who it is for and where it drops.",
	  points = { "BiS lists: each spec that has it, BIS or alt 2..6, phase by phase.",
		"Stars for the items no list names: who it fits by class and spec.",
		"Boss and instance: which boss drops it, 10 or 25, normal or heroic." },
	  where = "Hover any item. /okup bis, /okup fits, /okup drops turn each off" },
	{ key = "Okanvil-Notes", title = "Notes",
	  what = "Boss notes that open by themselves in each room.",
	  points = { "Your assignment for each boss, on screen as you walk in.",
		"The guild's WeakAuras read your name from the note.",
		"Timed lines count from DBM's pull." },
	  where = "RAID > Notes" },
	{ key = "Okanvil-RaidFinder", title = "Raid Finder",
	  what = "The LFM spam in chat, turned into one list of raids you can join.",
	  points = { "Raid, size, roles wanted, GS asked and reserved loot, read from each message.",
		"Raids you are already saved to are marked, so you do not whisper for nothing.",
		"Whisper the leader in one click." },
	  where = "RAID > Raid Finder" },
	{ key = "Okanvil-PuG", title = "PuG",
	  what = "Build your own raid.",
	  points = { "The LFM line written for you: raid, size, roles, GS, reserved loot.",
		"It spams the line for you, and catches the whispers that answer it.",
		"Invite and seat people by role, and check their gear." },
	  where = "RAID > PuG" },
	{ key = "Okanvil-Ranking", title = "Ranking",
	  what = "The guild's log rankings, inside the game.",
	  points = { "Every raider's best, per board, from the RATS site.",
		"A raider's rank on their tooltip.",
		"Kept in sync across the guild." },
	  where = "GUILD > Ranking" },
	{ key = "__guild", title = "Raid snapshots",
	  what = "Who was in each raid, saved quietly.",
	  points = { "Attendance for the loot priority, without anyone taking notes.",
		"Lockouts saved when a raid is done.",
		"Officers export it for the website." },
	  where = "GUILD (officers)" },
	{ key = "Okanvil-Recruit", title = "Recruit",
	  what = "Recruitment ads, on a timer.",
	  points = { "Your ad in the right channels, every few minutes.",
		"Whoever answers can be invited in one click.",
		"Officers share one ad." },
	  where = "GUILD > Recruit" },
	{ key = "Okanvil-Logs", title = "Combat Logs",
	  what = "Combat logging that starts and stops by itself.",
	  points = { "On when you enter a raid, off when you leave.",
		"Each raid's boss kills kept as a session.",
		"Nothing to remember before the pull." },
	  where = "TOOLS > Logs" },
	{ key = "Okanvil-IDs", title = "ID Finder",
	  what = "Spell and item IDs, for WeakAuras.",
	  points = { "Search any spell or item by name.",
		"The ID on every spell, buff, debuff and item tooltip.",
		"/okids tips turns the tooltip line off." },
	  where = "TOOLS > ID Finder" },
	{ key = "Okanvil-Farm", title = "Farm",
	  what = "Gold per hour while you farm.",
	  points = { "Loot and gold counted as you go.",
		"Per hour, per session.",
		"Start and stop when you like." },
	  where = "TOOLS > Farm" },
}

local tourF
function Okanvil:ShowTour()
	if tourF then tourF:Hide() end
	local C = self.Colors
	local self_ = self
	local items = self:ModuleItems()
	local byKey = {}
	for _, it in ipairs(items) do byKey[it.key] = it end
	-- only what this character has on
	local pages = {}
	for _, t in ipairs(TOUR) do
		if byKey[t.key] and self:IsModuleEnabled(t.key) then pages[#pages + 1] = t end
	end
	if #pages == 0 then self:Print("nothing to show: every module is off."); return end

	local f = CreateFrame("Frame", "Okanvil_Tour", UIParent)
	f:SetFrameStrata("DIALOG"); f:SetToplevel(true); f:SetClampedToScreen(true)
	f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetPoint("CENTER"); f:SetSize(WIN_W, 400)
	self:Skin(f)
	f:SetBackdropColor(C.panelD[1], C.panelD[2], C.panelD[3], 0.97)
	tourF = f
	local wall = f:CreateTexture(nil, "BORDER")
	wall:SetPoint("TOPLEFT", 1, -1); wall:SetPoint("BOTTOMRIGHT", -1, 1)
	wall:SetTexture(WALLPAPER)
	local span = 400 / WIN_W
	wall:SetTexCoord(0, 1, 0.5 - span / 2, 0.5 + span / 2)
	wall:SetAlpha(0.35)

	local ic = icon(f, nil, 30); ic:SetPoint("TOPLEFT", X, -16)
	local title = W.Text(f, "", "title", "accent"); title:SetPoint("TOPLEFT", ic, "TOPRIGHT", 10, 0)
	local step = W.Text(f, "", "head"); step:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	local close = W.Button(f, "X"); close:SetSize(24, 22); close:SetPoint("TOPRIGHT", -10, -10)
	close:SetScript("OnClick", function() f:Hide() end)
	local rule = f:CreateTexture(nil, "ARTWORK")
	rule:SetTexture("Interface\\Buttons\\WHITE8x8"); rule:SetHeight(1)
	rule:SetVertexColor(C.border[1], C.border[2], C.border[3], 1)
	rule:SetPoint("TOPLEFT", X, -60); rule:SetPoint("TOPRIGHT", -X, -60)

	local CW = WIN_W - X * 2
	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", X, CONTENT_TOP); body:SetPoint("BOTTOMRIGHT", -X, 50)
	local what = W.Text(body, "", "head"); what:SetPoint("TOPLEFT", 0, 0); what:SetWidth(CW); what:SetJustifyH("LEFT")
	local lines, dots = {}, {}
	for i = 1, 3 do
		dots[i] = body:CreateTexture(nil, "ARTWORK")
		dots[i]:SetTexture("Interface\\Buttons\\WHITE8x8"); dots[i]:SetSize(6, 6)
		dots[i]:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
		lines[i] = W.Text(body, "", "body"); lines[i]:SetWidth(CW - 18); lines[i]:SetJustifyH("LEFT")
	end
	local where = W.Text(body, "", "note", "dim"); where:SetWidth(CW); where:SetJustifyH("LEFT")

	local prev = W.Button(f, "< Back"); prev:SetSize(90, 24); prev:SetPoint("BOTTOMLEFT", X, 14)
	local nxt = W.Button(f, "Next >", "primary"); nxt:SetSize(90, 24); nxt:SetPoint("BOTTOMRIGHT", -X, 14)

	local cur = 1
	local function show(n)
		cur = n
		local t = pages[n]
		ic:SetTexture(byKey[t.key].icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		title:SetText(t.title)
		step:SetText(("Tour  %d of %d"):format(n, #pages))
		what:SetText(t.what)
		local below = what
		for i = 1, 3 do
			lines[i]:ClearAllPoints()
			lines[i]:SetPoint("TOPLEFT", below, "BOTTOMLEFT", i == 1 and 18 or 0, i == 1 and -14 or -9)
			lines[i]:SetText(t.points[i] or "")
			dots[i]:ClearAllPoints(); dots[i]:SetPoint("TOPRIGHT", lines[i], "TOPLEFT", -8, -4)
			below = lines[i]
		end
		where:ClearAllPoints(); where:SetPoint("TOPLEFT", below, "BOTTOMLEFT", -18, -16)
		where:SetText("|cffe0b860Open it:|r " .. t.where)
		if n == 1 then prev:Hide() else prev:Show() end
		nxt.text:SetText(n == #pages and "Done" or "Next >")
	end
	prev:SetScript("OnClick", function() if cur > 1 then show(cur - 1) end end)
	nxt:SetScript("OnClick", function() if cur < #pages then show(cur + 1) else f:Hide() end end)
	f:Show()
	show(1)
end
