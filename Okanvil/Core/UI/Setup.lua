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

local WIN_W, WIN_H = 540, 450
local X = 20                      -- side gutter
local CONTENT_TOP = -76           -- below the header rule
local ROW_H = 28                  -- one extra per row

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

-- Optional for everyone. One line each; the tooltip has the rest.
-- `officer` = on by default for an officer; `all` = on by default for everyone.
local EXTRAS = {
	{ key = "__loot",             line = "Loot history -- drops per boss, Mini Roll",  officer = true },
	{ key = "__guild",            line = "Raid snapshots -- who was in each raid",     all = true },
	{ key = "Okanvil-RaidFinder", line = "Raid Finder -- find pug raids in chat",      all = true },
	{ key = "Okanvil-PuG",        line = "PuG -- build a raid and spam the LFM line",  officer = true },
	{ key = "Okanvil-Recruit",    line = "Recruit -- recruitment ads, auto-invite",    officer = true },
	{ key = "Okanvil-Logs",       line = "Combat Logs -- auto-log each raid",          officer = true },
	{ key = "Okanvil-IDs",        line = "ID Finder -- spell and item IDs for WAs" },
	{ key = "Okanvil-Farm",       line = "Farm -- gold per hour while farming" },
}

local setupF

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

function Okanvil:ShowSetup()
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
						"Loot Council setup -- the Round and Priority tabs",
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
		{
			name = "Extras", icon = I.modules,
			build = function(host)
				para(host, "All optional. Hover a row for details.", 0, 0, CW, "body", "dim")
				local y = -24
				local paints = {}
				local function row(ic, line, tip, get, set)
					local fr = CreateFrame("Frame", nil, host)
					fr:SetPoint("TOPLEFT", 0, y)
					fr:SetPoint("TOPRIGHT", 0, y)
					fr:SetHeight(ROW_H - 4)
					fr:EnableMouse(true)
					local t = icon(fr, ic, 20); t:SetPoint("LEFT", 0, 0)
					local txt = W.Text(fr, line, "body")
					txt:SetPoint("LEFT", t, "RIGHT", 8, 0)
					local btn, paint = toggle(fr, get, set)
					btn:SetPoint("RIGHT", 0, 0)
					if tip then
						fr:SetScript("OnEnter", function(s)
							GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
							GameTooltip:SetText(tip, 1, 1, 1, 1, true)
							GameTooltip:Show()
						end)
						fr:SetScript("OnLeave", function() GameTooltip:Hide() end)
					end
					paints[#paints + 1] = paint
					y = y - ROW_H
				end
				for _, e in ipairs(EXTRAS) do
					local it = byKey[e.key]
					if it then
						local key = e.key
						row(it.icon, e.line, it.desc,
							function() return want[key] end, function(v) want[key] = v end)
					end
				end
				if MB then
					row("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
						"Marks bar -- marks, pull timer, shortcuts",
						"Raid marks, ready check and pull timer while you lead or assist, "
						.. "plus shortcuts into Okanvil.",
						function() return wantBar end, function(v) wantBar = v end)
				end
				row("Interface\\Icons\\Trade_BlackSmithing",
					"Forge wallpaper -- the art behind the window",
					"The smith at the anvil behind every page. Off = plain dark panels. "
					.. "Its strength is in Settings.",
					function() return wantWall end, function(v) wantWall = v end)
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
						.. "|cff00ff00/okanvil setup|r.")
				end
			end,
		},
	}

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
		for _, it in ipairs(items) do
			if want[it.key] ~= self_:IsModuleEnabled(it.key) then
				self_:SetModuleEnabled(it.key, want[it.key])
			end
		end
		if MB and MB.Toggle then MB:Toggle(wantBar) end
		self_.db.ratArt = wantWall and "on" or "off"
		if self_.RefreshRatArt then self_:RefreshRatArt() end
		finish()
		self_:Print("setup saved. |cff8a8d93Run it again any time with|r |cff00ff00/okanvil setup|r.")
	end)

	f:Show()
	show(1)
end
