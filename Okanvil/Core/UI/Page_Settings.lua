-- ============================================================
-- Okanvil -- UI: Settings page
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

function Okanvil:BuildSettings()
	local fill = newFillPanel()
	local host = fill.child
	local db = self.db
	local X = Okanvil.UI.PAD_X

	-- TABS. Everything used to be stacked on one landing page -- appearance, media,
	-- branding, dev, version check, and then the raid overlays crammed into an
	-- improvised right-hand column. It was unreadable. Each concern now gets its own
	-- tab, and W.Dashboard gives every tab its own internal scroll for free.
	local dash = W.Dashboard(host, {
		title = "Settings",
		subtitle = "Shared by all your characters",
		icon = Okanvil.ICONS.settings,
		drawerWidth = 0,
		footerHeight = 0,
		-- One pill per area, and every module's settings are HERE. They used to be
		-- split: a module with a page kept its own settings tab, a module without
		-- one had them here, so configuring loot meant two places and neither was
		-- obviously the right one to look in first.
		pills = true,
		tabs = {
			-- Two columns, so this is shorter than it looks: 380 left a third of
			-- the pill empty below About.
			{ key = "general", label = "General",    height = 300,
			  build = function(pg) Okanvil:Settings_General(pg) end },
			-- loot capture, announce templates and the priority list
			-- taller for an officer: the priority-list blocks below the announce
			-- templates are only built for someone who can open that list
			{ key = "loot",    label = "Loot",
			  height = (Okanvil.U and Okanvil.U.canSeePrio and Okanvil.U.canSeePrio()) and 470 or 320,
			  build = function(pg) Okanvil:Loot_BuildSettings(pg) end },
			-- Two columns: the ready-check popup and the marks bar side by side.
			{ key = "raid",    label = "Raid",       height = 400,
			  build = function(pg) Okanvil:Settings_RaidTools(pg) end },
			-- Keyword auto-invite: three switches and a keyword list, set once --
			-- configuration, not a page of its own.
			{ key = "invite",  label = "Invite",     height = 220,
			  build = function(pg) Okanvil:Settings_Invite(pg) end },
			-- No Modules pill: Modules is not configuration, it is what the addon
			-- has, and it is its own nav entry.
			-- No Advanced pill either. It held a dev toggle (which is /okanvil tab)
			-- and one button, now under ABOUT in General.
		},
	})
	fill.dash = dash

	-- app credit -- a small badge in the bottom-right corner (anvil + wordmark),
	-- nicer than a bare line of text. Anchored to the PAGE, not dash.main: in pill
	-- mode the body it used to hang off is hidden, which took the badge with it.
	local badge = W.Frame(host, "soft")
	badge:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -12, 12)
	badge:SetHeight(48)
	local bIcon = badge:CreateTexture(nil, "ARTWORK")
	bIcon:SetSize(30, 30); bIcon:SetPoint("LEFT", 12, 0)
	bIcon:SetTexture(Okanvil.BRAND_ICON); bIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local bName = W.Text(badge, "Okanvil", "head", "accent"); bName:SetPoint("LEFT", bIcon, "RIGHT", 10, 8); bName:Color(1, 0.82, 0)
	local bVer = W.Text(badge, "v" .. (self.version or "1.0"), "note", "dim"); bVer:SetPoint("LEFT", bName, "RIGHT", 5, 0)
	local bBy = W.Text(badge, "forged by |cffe0b860Okanor|r", "note", "dim"); bBy:SetPoint("LEFT", bIcon, "RIGHT", 10, -10)
	-- size the badge to fit its contents (icon + the wider of the two text rows)
	local wName = (bName:GetStringWidth() or 60) + (bVer:GetStringWidth() or 20) + 5
	local wBy = bBy:GetStringWidth() or 80
	badge:SetWidth(30 + 10 + math.max(wName, wBy) + 18)

	fill:SetScript("OnShow", function() dash:Refresh() end)
	return fill
end

-- ---- Settings: Options (single tab -- Appearance + Media + Branding stacked) ----
-- Loot capture/threshold settings live in the Loot module now (Okanvil:Loot_BuildSettings).
-- ---- Settings tabs -------------------------------------------------------
-- Split out of one giant stacked page. Each tab gets its own scroll from
-- W.Dashboard, so nothing overlaps and nothing spills off the window.

function Okanvil:Settings_General(p)
	local db = self.db
	local X = 4

	-- Spacing carries the grouping: a section header gets GAP above it, the controls
	-- under it get ROW. Everything used to sit the same distance apart, so nothing
	-- looked like it belonged to anything.
	-- NOTE: W.Slider anchors at its BAR, with its label ~5px ABOVE that anchor, so a
	-- slider needs more room above it than a checkbox does.
	-- Two columns. Every control here is narrow -- a slider, a checkbox, a
	-- dropdown -- so a single column left the right half of the page empty and
	-- pushed About below the fold.
	--
	-- A section header spans both columns and resets them to the same line, so a
	-- group never straddles a heading.
	local COL_W = 250
	local C1, C2 = X, X + COL_W + 30
	local y1, y2 = -8, -8

	-- A section spans both columns and resets them to the same line, so a group
	-- never straddles a heading.
	local function head(text)
		local top = math.min(y1, y2) - 14
		y1 = (W.Section(p, text, C1, top))
		y2 = y1
	end
	local function hint(text, col)
		if col == 2 then
			y2 = W.Hint(p, text, C2 + 2, y2, COL_W - 10)
		else
			y1 = W.Hint(p, text, C1 + 2, y1, COL_W - 10)
		end
	end

	head("APPEARANCE")

	local SLIDER_TOP = W.SLIDER_TOP

	-- LEFT: size. Scale is the ONE size control -- it scales text, icons, spacing
	-- and padding together, which is what "make it bigger" actually means.
	y1 = y1 - SLIDER_TOP
	W.Slider(p, "Window scale", 0.6, 1.8, 0.05, function() return db.scale end,
		function(v) db.scale = v; Okanvil.win:SetScale(v) end, true):SetPoint("TOPLEFT", C1, y1)
	y1 = y1 - 22
	hint("text, icons and spacing together", 1)

	-- How solid the window is. With the panels inside it see-through, this is
	-- what stands between the page and the game behind it.
	y1 = y1 - SLIDER_TOP
	W.Slider(p, "Window opacity", 0.3, 1.0, 0.05, function() return db.bgAlpha or 0.95 end,
		function(v) db.bgAlpha = v; Okanvil:ReskinAll(v) end):SetPoint("TOPLEFT", C1, y1)
	y1 = y1 - 22
	hint("1 = solid, lower = see the game through it", 1)

	-- Text only; buttons keep their size. Applied on release.
	y1 = y1 - SLIDER_TOP
	W.Slider(p, "Text size", 0.85, 1.3, 0.05, function() return db.textScale or 1 end,
		function(v) db.textScale = v; Okanvil:ApplyFonts() end, true):SetPoint("TOPLEFT", C1, y1)
	y1 = y1 - 22
	hint("page text only -- some lists fit best after a /reload", 1)

	-- RIGHT: the art, its toggle and its opacity as one block. The slider does
	-- nothing while the toggle is off, so they have to be read together.
	local showChk = W.ToggleRow(p, "Forge wallpaper", nil,
		function() return (db.ratArt or "on") ~= "off" end,
		function(v) db.ratArt = v and "on" or "off"; Okanvil:RefreshRatArt() end)
	showChk:SetHeight(26); showChk.btn:SetSize(46, 18); showChk:SetWidth(260)
	showChk:SetPoint("TOPLEFT", C2, y2)
	y2 = y2 - 24 - SLIDER_TOP
	W.Slider(p, "Wallpaper strength", 0.0, 0.8, 0.05, function() return db.ratAlpha end,
		function(v) db.ratAlpha = v; Okanvil:RefreshRatArt() end):SetPoint("TOPLEFT", C2, y2)
	y2 = y2 - 22

	head("BEHAVIOUR")
	local pullChk = W.ToggleRow(p, "Close all windows on a DBM pull", nil,
		function() return db.closeOnPull ~= false end,
		function(v) db.closeOnPull = v end)
	pullChk:SetHeight(26); pullChk.btn:SetSize(46, 18); pullChk:SetWidth(300)
	pullChk:SetPoint("TOPLEFT", C1, y1); y1 = y1 - 26

	-- db.statusbar still drives Okanvil:Texture(); the addon has almost no status
	-- bars for a texture to apply to, so it has no row of its own.
	head("FONT")
	W.DropDown(p, function() return (LSM and LSM:List("font")) or { db.font } end,
		function() return db.font end, function(v) db.font = v; Okanvil:ApplyFonts() end, "font")
		:Size(220, 22):Point("TOPLEFT", C1, y1)
	y1 = y1 - 30

	-- Guild skin and Web hub URL used to sit here too. Both are set on the day a
	-- guild installs Okanvil and then never again, so they live on /okanvil brand
	-- and /okanvil hub instead of taking a third of this page.
	head("ABOUT")
	local vbtn = W.Button(p, "Version check", "secondary")
	vbtn:SetSize(140, 24); vbtn:SetPoint("TOPLEFT", C1, y1)
	vbtn:SetScript("OnClick", function() Okanvil:ShowVersionChecker() end)
	local vh = W.Text(p, "|cff6f7176who in your group or guild runs which Okanvil|r", "note", "dim")
	vh:SetPoint("LEFT", vbtn, "RIGHT", 10, 0)
	y1 = y1 - 32

	local sbtn = W.Button(p, "Run setup again", "secondary")
	sbtn:SetSize(140, 24); sbtn:SetPoint("TOPLEFT", C1, y1)
	sbtn:SetScript("OnClick", function() Okanvil:ShowSetup() end)
	local sh = W.Text(p, "|cff6f7176the welcome window: modules and the marks bar|r", "note", "dim")
	sh:SetPoint("LEFT", sbtn, "RIGHT", 10, 0)
end

function Okanvil:Settings_RaidTools(p)
	local db = self.db
	local X = 4

	-- Two in-raid overlays, each its own group with real space above it. They used
	-- to run down the page with the same gap between two checkboxes as between two
	-- tools, so twelve controls read as one undifferentiated list.
	--
	-- Labels are short because the group header carries the rest: under
	-- "READY-CHECK POPUP", a checkbox only has to say "Show on a ready check".
	--
	-- The setters below must store a REAL boolean, never nil: W.Check toggles by
	-- inverting what getFn reads, so deleting the key leaves the tick stuck on.
	-- Two columns, one per tool. The ready-check popup and the marks bar are
	-- independent things you configure once each; stacked they ran off the bottom
	-- of the pill while the right half of the page stayed empty.
	-- Wide enough that the explanatory lines fit on ONE line: at 300 every hint
	-- wrapped, which is what made the left column feel cramped.
	local COL_W = 380
	local C1, C2 = X, X + COL_W + 30
	local col, y1, y2 = 1, -8, -8

	local SLIDER_TOP = W.SLIDER_TOP

	local function cx() return (col == 1) and C1 or C2 end
	local function cy() return (col == 1) and y1 or y2 end
	local function setY(v)
		if col == 1 then y1 = v else y2 = v end
	end
	local function step(n) setY(cy() - n) end

	local function head(text)
		-- The left column's rule stops where the right column starts; the right
		-- one runs to the page edge.
		local reach = (col == 1) and (C2 - C1 - 100) or nil
		setY((W.Section(p, text, cx(), cy(), reach)))
	end
	-- A setting row (label, ON / OFF, hairline -- W.ToggleRow), one column wide.
	local function chk(label, getFn, setFn, tip)
		local c = W.ToggleRow(p, label, nil, getFn, setFn)
		c:SetHeight(26); c.btn:SetSize(46, 18); c:SetWidth(COL_W - 20)
		c:SetPoint("TOPLEFT", cx(), cy()); step(28)
		if tip then c:Tooltip(tip) end
		return c
	end
	local function hint(text)
		setY(W.Hint(p, text, cx() + 21, cy(), COL_W - 30, 8))
	end

	local RC = Okanvil.RaidCheck
	if RC then
		local rcdb = function()
			db.raidcheck = db.raidcheck or {}
			return db.raidcheck
		end

		head("READY-CHECK POPUP")
		chk("Show on a ready check",
			function() return rcdb().onReadyCheck ~= false end,
			function(v) rcdb().onReadyCheck = v and true or false end)
		hint("who is missing a flask, food or a buff -- leader/assist only")
		chk("Close once everyone is ready",
			function() return rcdb().closeWhenClear ~= false end,
			function(v) rcdb().closeWhenClear = v and true or false end,
			"Everyone answered READY and nobody is missing a flask or food -> the "
			.. "popup has nothing left to show, so it closes itself.\n\n"
			.. "Someone answering NOT ready keeps it open -- that is the case you "
			.. "want to be looking at.")
		chk("Minutes left on each icon",
			function() return rcdb().hideNumbers ~= true end,
			function(v)
				rcdb().hideNumbers = not v
				if RC.RenderToast then RC:RenderToast() end
			end)
		chk("Grey out missing buffs",
			function() return rcdb().hideMissing ~= true end,
			function(v)
				rcdb().hideMissing = not v
				if RC.RenderToast then RC:RenderToast() end
			end)
		hint("off: only buffs people actually have are drawn")

		step(6)
		local rcSortL = W.Text(p, "Sort by", "label", "dim")
		rcSortL:SetPoint("TOPLEFT", cx(), cy() + 4)
		W.DropDown(p,
			function() return RC.SORTS or { "group", "class", "name" } end,
			function() return rcdb().sort or "group" end,
			function(v) rcdb().sort = v; if RC.RenderToast then RC:RenderToast() end end)
			:Size(130, 22):Point("TOPLEFT", cx() + 60, cy() + 6)
		step(30 + SLIDER_TOP)

		W.Slider(p, "Size", 70, 160, 5,
			function() return rcdb().scale or 100 end,
			function(v)
				rcdb().scale = v
				if RC.SetToastScale then RC:SetToastScale(v) end
			end):SetPoint("TOPLEFT", cx(), cy())
		local rcTest = W.Button(p, "Preview")
		rcTest:SetSize(90, 22); rcTest:SetPoint("TOPLEFT", cx() + 210, cy() - 4)
		rcTest:SetScript("OnClick", function() if RC.ShowToast then RC:ShowToast(true) end end)
		step(26)
	end

	local MB = Okanvil.MarksBar
	if MB then
		local mbdb = function()
			db.marksbar = db.marksbar or {}
			return db.marksbar
		end

		-- Second column: a separate tool, not a continuation of the one above.
		col = 2
		head("MARKS BAR")
		chk("Show the marks bar",
			function() return mbdb().enabled and true or false end,
			function(v) if MB.Toggle then MB:Toggle(v and true or false) end end)
		hint("marks, ready check and pull -- only while you are leader or assist")

		step(SLIDER_TOP)
		W.Slider(p, "Size", 70, 160, 5,
			function() return mbdb().scale or 100 end,
			function(v)
				mbdb().scale = v
				if MB.Refresh then MB:Refresh() end
			end):SetPoint("TOPLEFT", cx(), cy())
		step(24 + SLIDER_TOP)
		W.Slider(p, "Pull timer (seconds)", 3, 30, 1,
			function() return mbdb().pullTime or 10 end,
			function(v) mbdb().pullTime = v end):SetPoint("TOPLEFT", cx(), cy())
		step(24)
	end

	-- The Combat Logs module has no page of its own, so its switches live here or
	-- nowhere. Without them a saved "ask on entering" from an older version could
	-- never be turned off, and nothing could stop the first pull starting a log.
	local LDB = OkanvilLogs and OkanvilLogs.DB and OkanvilLogs.DB()
	if LDB then
		col = 2
		step(14)
		head("COMBAT LOG")
		chk("Ask when entering a raid",
			function() return LDB.askOnEnter and true or false end,
			function(v) LDB.askOnEnter = v and true or false end)
		hint("a Start log / No prompt on the raid zone-in; No = no log this raid")
		chk("Start logging at the first pull",
			function() return LDB.autoOnPull ~= false end,
			function(v) LDB.autoOnPull = v and true or false end)
		hint("off: the log only starts when you press Start (REC)")
		chk("Lock the REC timer",
			function() return LDB.recLocked and true or false end,
			function(v)
				LDB.recLocked = v and true or false
				if OkanvilLogs.ApplyRecLock then OkanvilLogs.ApplyRecLock() end
			end)
		hint("click-through, so a mid-fight drag cannot move it")
	end
end

-- ---- Version checker popup (RCLootCouncil-style) -------------------------
-- Its own window, so it can stay open while replies trickle in and the Settings
-- page can be closed. One shared frame, rebuilt rows on every repaint.
local verDlg
local DOWNLOAD_URL = "github.com/MrNog/Okanvil/releases/latest"
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

		-- Whispers the download link to everyone who did not reply. Only shown once
		-- the check has finished: while it runs, "no reply" still means "not yet".
		local bLink = W.Button(f, "Whisper download link")
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
			local nxt = cur - delta * 30
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

		local function paint()
			local Comms = Okanvil.Comms
			if not Comms then f.out:SetText("|cffff5555Comms unavailable.|r"); return end
			local replies = Comms.VersionReplies and Comms.VersionReplies() or {}
			local roster = Comms.GroupRoster and Comms.GroupRoster(f._scope) or {}
			local mine = tostring(Okanvil.version or "?")
			local waiting = Comms.VersionCheckRunning and Comms.VersionCheckRunning()
			local lines, ok, old, none = {}, 0, 0, 0
			local missing = {}
			for _, name in ipairs(roster) do
				local v = replies[name]
				if not v then
					none = none + 1
					missing[#missing + 1] = name
					lines[#lines + 1] = "|cff8a8d93" .. name .. "|r  "
						.. (waiting and "|cff8a8d93waiting...|r" or "|cffff5555no reply|r")
				elseif v == mine then
					ok = ok + 1
					lines[#lines + 1] = name .. "  |cff7cfc8a" .. v .. "|r"
				else
					old = old + 1
					lines[#lines + 1] = name .. "  |cffffd200" .. v .. "|r"
				end
			end
			if #lines == 0 then
				f.out:SetText("|cff8a8d93Nobody to ask.|r")
			else
				f.out:SetText(table.concat(lines, "\n"))
			end
			f.status:SetText("|cff7cfc8a" .. ok .. "|r / |cffffd200" .. old
				.. "|r / |cffff5555" .. none .. "|r"
				.. (waiting and "  |cff8a8d93asking...|r" or ""))
			f._missing = missing
			if not waiting and #missing > 0 then
				f.bLink.text:SetText(("Whisper download link (%d)"):format(#missing))
				f.bLink:Show()
			else
				f.bLink:Hide()
			end
			-- size the scroll child to the text so the wheel range is right
			local w = f.scroll:GetWidth() or 0
			if w < 10 then w = 288 end            -- first paint runs before layout
			f.out:SetWidth(w)
			f.child:SetWidth(w)
			f.child:SetHeight(math.max(f.out:GetStringHeight() + 8, 1))
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
		-- Spaced out so a long guild list does not trip the server's chat throttle.
		bLink:SetScript("OnClick", function()
			local list = f._missing or {}
			if #list == 0 then return end
			local msg = "[Okanvil] You don't seem to have Okanvil (the RATS raid addon). "
				.. "Download: " .. DOWNLOAD_URL .. " -- unzip into Interface\\AddOns and restart WoW."
			for i, name in ipairs(list) do
				Okanvil.Comms.After((i - 1) * 0.4, function()
					SendChatMessage(msg, "WHISPER", nil, name)
				end)
			end
			Okanvil:Print(("Whispered the download link to %d player(s)."):format(#list))
			f._missing = {}
			bLink:Hide()
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

-- ---- Loot capture settings (used as a tab INSIDE the Loot module) ----

-- ------------------------------------------------------------
-- Invite -- auto-invite master switch, the two channels, and the keywords.
--
-- This was a whole nav page. What it actually held was these three settings
-- plus a mass-invite-by-rank block that went unused, because inviting is faster
-- from the per-row buttons on Home.
-- ------------------------------------------------------------
function Okanvil:Settings_Invite(p)
	local I = Okanvil.Invite
	local X = 14
	if not I then
		local t = W.Text(p, "Invite engine not loaded.", "label", "dim")
		t:SetPoint("TOPLEFT", X, -12)
		return
	end

	-- The master switch, first: is keyword auto-invite running at all.
	local onChk = W.Check(p, "Auto-invite on a keyword",
		function() return I.KeywordEnabled() end,
		function(v) I.SetKeywordEnabled(v and true or false) end)
	onChk:SetPoint("TOPLEFT", X, -10)
	onChk:Tooltip("Invite whoever whispers or says one of the keywords below.")
	local warn = W.Text(p, "|cff8a8d93Can't run with Recruit (shared keyword) -- enabling one disables the other.|r", "note", "dim")
	warn:SetPoint("LEFT", onChk, "LEFT", 220, 0); warn:SetWidth(460); warn:SetJustifyH("LEFT")

	local Y0 = -24   -- everything below sits under the switch
	local wChk = W.Check(p, "On whisper", function() return I.db().whisperInvite end,
		function(v) I.db().whisperInvite = v end)
	wChk:SetPoint("TOPLEFT", X, -32 + Y0)
	local gChk = W.Check(p, "On guild chat", function() return I.db().guildInvite end,
		function(v) I.db().guildInvite = v end)
	gChk:SetPoint("LEFT", wChk, "LEFT", 165, 0)

	local kwLbl = W.Text(p, "KEYWORDS", "note", "dim"); kwLbl:SetPoint("TOPLEFT", X, -66 + Y0)

	-- Live preview. Matching is WHOLE WORD, which is right ("reinvite" must not
	-- trigger) but not obvious: "inv" alone does NOT match "invite", so the most
	-- natural thing a person types was being ignored. Showing what does and does
	-- not match means never having to guess again.
	local preview = W.Text(p, "", "note", "dim")
	preview:SetPoint("TOPLEFT", X, -120 + Y0); preview:SetWidth(430); preview:SetJustifyH("LEFT")

	local SAMPLES = { "inv", "invite", "+", "inv pls", "invite me", "reinvite" }
	local function refreshPreview(text)
		local kws = {}
		for w in (text or ""):lower():gmatch("[^%s,;]+") do kws[#kws + 1] = w end
		local yes, no = {}, {}
		for _, sample in ipairs(SAMPLES) do
			local hit = false
			for _, kw in ipairs(kws) do
				if kw ~= "" and sample:find("%f[%w]" .. kw:gsub("(%W)", "%%%1") .. "%f[%W]") then
					hit = true; break
				end
			end
			if hit then yes[#yes + 1] = '"' .. sample .. '"' else no[#no + 1] = '"' .. sample .. '"' end
		end
		preview:SetText("|cff7cfc8amatches|r " .. (table.concat(yes, ", ") ~= "" and table.concat(yes, ", ") or "nothing")
			.. (#no > 0 and ("\n|cffff5555ignores|r " .. table.concat(no, ", ")) or ""))
	end

	local kwBox = W.EditBox(p, function(t) I.db().keyword = t or ""; refreshPreview(t) end)
	kwBox:Size(300, 22); kwBox:SetPoint("TOPLEFT", X, -86 + Y0)
	kwBox.edit:SetText(I.db().keyword or "inv, invite, +")
	kwBox.edit:SetScript("OnTextChanged", function(s) refreshPreview(s:GetText()) end)

	local kwHint = W.Text(p, "comma-separated -- any of them triggers an invite", "note", "dim")
	kwHint:SetPoint("LEFT", kwBox, "RIGHT", 10, 0)

	refreshPreview(kwBox.edit:GetText())

	-- The login toast and its switch are gone: it double-counted one person into
	-- (+1)(+2)(+4) as the roster refreshed, and arrived late regardless. Home's
	-- guild list answers "who is on" without guessing.
end
