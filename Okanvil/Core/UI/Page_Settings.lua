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
		icon = Okanvil.ICONS.settings,
		drawerWidth = 0,
		footerHeight = 0,
		-- One pill per area, and every module's settings are HERE. They used to be
		-- split: a module with a page kept its own settings tab, a module without
		-- one had them here, so configuring loot meant two places and neither was
		-- obviously the right one to look in first.
		pills = true,
		tabs = {
			{ key = "general", label = "General",    height = 380,
			  build = function(pg) Okanvil:Settings_General(pg) end },
			-- loot capture, announce templates and the priority list
			-- taller for an officer: the priority-list blocks below the announce
			-- templates are only built for someone who can open that list
			{ key = "loot",    label = "Loot",
			  height = (Okanvil.U and Okanvil.U.canSeePrio and Okanvil.U.canSeePrio()) and 470 or 320,
			  build = function(pg) Okanvil:Loot_BuildSettings(pg) end },
			-- Auto-invite is two toggles and a keyword box. It had a whole nav page
			-- to itself, next to Loot and Raid Finder, for something you set once.
			{ key = "invite",  label = "Invite",     height = 360,
			  build = function(pg) Okanvil:Settings_Invite(pg) end },
			{ key = "raid",    label = "Raid",       height = 470,
			  build = function(pg) Okanvil:Settings_RaidTools(pg) end },
			-- No Advanced pill. It held a dev toggle (which is /okanvil tab) and one
			-- button, now under ABOUT in General.
			{ key = "modules", label = "Modules",    height = 600,
			  build = function(pg) Okanvil:Settings_Modules(pg) end },
		},
	})
	fill.dash = dash

	-- app credit -- a small badge in the bottom-right corner (anvil + wordmark),
	-- nicer than a bare line of text. Anchored to the PAGE, not dash.main: in pill
	-- mode the body it used to hang off is hidden, which took the badge with it.
	local badge = W.Frame(host, "panel")
	badge:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -12, 12)
	badge:SetHeight(48)
	local bIcon = badge:CreateTexture(nil, "ARTWORK")
	bIcon:SetSize(30, 30); bIcon:SetPoint("LEFT", 12, 0)
	bIcon:SetTexture("Interface\\Icons\\Trade_BlackSmithing"); bIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
	local y = -8
	local function head(text)
		local t = W.Text(p, text, "note", "dim"); t:SetPoint("TOPLEFT", X, y)
		y = y - 26
		return t
	end
	local function hint(text, indent)
		local t = W.Text(p, "|cff6f7176" .. text .. "|r", "note", "dim")
		t:SetPoint("TOPLEFT", X + (indent or 0), y); y = y - 20
		return t
	end

	head("APPEARANCE")
	-- Scale is the ONE size control. It scales text, icons, spacing and padding
	-- together, which is what "make it bigger" actually means -- a font slider
	-- next to it only stretched text inside boxes that stayed put.
	-- Up to 1.8: at 1.4 the window was still small on a modern monitor.
	y = y - 12
	W.Slider(p, "Window scale", 0.6, 1.8, 0.05, function() return db.scale end,
		function(v) db.scale = v; Okanvil.win:SetScale(v) end, true):SetPoint("TOPLEFT", X, y)
	y = y - 24
	hint("text, icons and spacing together", 2)

	-- The art toggle and the art's opacity, together. They were separated by a
	-- toggle about closing windows, which has nothing to do with either -- and the
	-- slider does nothing at all while the toggle is off.
	y = y - 6
	local showChk = W.Check(p, "Background art",
		function() return (db.ratArt or "on") ~= "off" end,
		function(v) db.ratArt = v and "on" or "off"; Okanvil:RefreshRatArt() end)
	showChk:SetPoint("TOPLEFT", X, y); y = y - 34
	W.Slider(p, "Art opacity", 0.0, 0.8, 0.05, function() return db.ratAlpha end,
		function(v) db.ratAlpha = v; Okanvil:RefreshRatArt() end):SetPoint("TOPLEFT", X, y)
	y = y - 34

	local pullChk = W.Check(p, "Close all windows on a DBM pull",
		function() return db.closeOnPull ~= false end,
		function(v) db.closeOnPull = v end)
	pullChk:SetPoint("TOPLEFT", X, y); y = y - 22

	-- Background opacity and Bar texture used to be here. Both are set once and
	-- never touched again -- and the addon has almost no status bars for a texture
	-- to apply to. db.bgAlpha and db.statusbar still drive the panels and
	-- Okanvil:Texture(); they are just no longer worth a row each.
	y = y - 20
	head("FONT")
	W.DropDown(p, function() return (LSM and LSM:List("font")) or { db.font } end,
		function() return db.font end, function(v) db.font = v; Okanvil:ApplyFonts() end, "font")
		:Size(200, 22):Point("TOPLEFT", X, y)
	y = y - 30

	-- Guild skin and Web hub URL used to sit here too. Both are set on the day a
	-- guild installs Okanvil and then never again, so they live on /okanvil brand
	-- and /okanvil hub instead of taking a third of this page.
	y = y - 20
	head("ABOUT")
	local vbtn = W.Button(p, "Version check", "secondary")
	vbtn:SetSize(140, 24); vbtn:SetPoint("TOPLEFT", X, y)
	vbtn:SetScript("OnClick", function() Okanvil:ShowVersionChecker() end)
	local vh = W.Text(p, "|cff6f7176who in your group or guild runs which Okanvil|r", "note", "dim")
	vh:SetPoint("LEFT", vbtn, "RIGHT", 10, 0)
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
	local y = -8
	local function head(text)
		local t = W.Text(p, text, "note", "dim"); t:SetPoint("TOPLEFT", X, y)
		y = y - 26
		return t
	end
	local function chk(label, getFn, setFn, tip)
		local c = W.Check(p, label, getFn, setFn)
		c:SetPoint("TOPLEFT", X, y); y = y - 24
		if tip then c:Tooltip(tip) end
		return c
	end
	local function hint(text)
		local t = W.Text(p, "|cff6f7176" .. text .. "|r", "note", "dim")
		t:SetPoint("TOPLEFT", X + 21, y); t:SetWidth(360); t:SetJustifyH("LEFT")
		y = y - 20
		return t
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

		y = y - 6
		local rcSortL = W.Text(p, "Sort by", "label", "dim")
		rcSortL:SetPoint("TOPLEFT", X, y + 4)
		W.DropDown(p,
			function() return RC.SORTS or { "group", "class", "name" } end,
			function() return rcdb().sort or "group" end,
			function(v) rcdb().sort = v; if RC.RenderToast then RC:RenderToast() end end)
			:Size(130, 22):Point("TOPLEFT", X + 60, y + 6)
		y = y - 32

		-- W.Slider anchors at its BAR and prints its label ABOVE -- hence the gap.
		y = y - 14
		W.Slider(p, "Size", 70, 160, 5,
			function() return rcdb().scale or 100 end,
			function(v)
				rcdb().scale = v
				if RC.SetToastScale then RC:SetToastScale(v) end
			end):SetPoint("TOPLEFT", X, y)
		local rcTest = W.Button(p, "Preview")
		rcTest:SetSize(90, 22); rcTest:SetPoint("TOPLEFT", X + 250, y - 2)
		rcTest:SetScript("OnClick", function() if RC.ShowToast then RC:ShowToast(true) end end)
		y = y - 26
	end

	local MB = Okanvil.MarksBar
	if MB then
		local mbdb = function()
			db.marksbar = db.marksbar or {}
			return db.marksbar
		end

		y = y - 20
		head("MARKS BAR")
		chk("Show the marks bar",
			function() return mbdb().enabled and true or false end,
			function(v) if MB.Toggle then MB:Toggle(v and true or false) end end)
		hint("marks, ready check and pull -- only while you are leader or assist")

		y = y - 14
		W.Slider(p, "Size", 70, 160, 5,
			function() return mbdb().scale or 100 end,
			function(v)
				mbdb().scale = v
				if MB.Refresh then MB:Refresh() end
			end):SetPoint("TOPLEFT", X, y)
		y = y - 46
		W.Slider(p, "Pull timer (seconds)", 3, 30, 1,
			function() return mbdb().pullTime or 10 end,
			function(v) mbdb().pullTime = v end):SetPoint("TOPLEFT", X, y)
	end

	-- No COMBAT LOG block. Logging starts by itself at the first pull and the REC
	-- timer on screen says when it is running, so the only switch here was one that
	-- asked a question you always answered the same way -- it is off for good now.
end

-- ---- Version checker popup (RCLootCouncil-style) -------------------------
-- Its own window, so it can stay open while replies trickle in and the Settings
-- page can be closed. One shared frame, rebuilt rows on every repaint.
local verDlg
function Okanvil:ShowVersionChecker()
	local f = verDlg
	if not f then
		f = Okanvil:Popup("Okanvil version check")
		f:SetSize(320, 380)

		-- scope buttons, RCLoot-style: Group | Guild
		local bGroup = W.Button(f, "Group", "primary")
		bGroup:SetSize(90, 22); bGroup:SetPoint("TOPLEFT", 10, -32)
		local bGuild = W.Button(f, "Guild")
		bGuild:SetSize(90, 22); bGuild:SetPoint("LEFT", bGroup, "RIGHT", 8, 0)

		local status = W.Text(f, "", "note", "dim")
		status:SetPoint("LEFT", bGuild, "RIGHT", 10, 0)
		f.status = status

		-- results list inside a clipped scroll (long guild rosters must not spill)
		local box = W.Frame(f, "dark")
		box:SetPoint("TOPLEFT", 10, -62); box:SetPoint("BOTTOMRIGHT", -10, 10)
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

		local out = W.Text(child, "", "label")
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
			for _, name in ipairs(roster) do
				local v = replies[name]
				if not v then
					none = none + 1
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

	local hdr = W.Text(p, "AUTO-INVITE", "note", "dim"); hdr:SetPoint("TOPLEFT", X, -10)

	-- master switch: OFF means nobody is pulled in by a keyword, whatever the
	-- channel toggles below say
	local master = W.Button(p, "", "primary")
	master:SetSize(150, 24); master:SetPoint("TOPLEFT", X, -28)
	local function syncMaster()
		local on = I.KeywordEnabled()
		if master.text then master.text:SetText(on and "Auto-Invite: ON" or "Auto-Invite: OFF") end
		master:SetKind(on and "primary" or nil)
	end
	master:SetScript("OnClick", function()
		I.SetKeywordEnabled(not I.KeywordEnabled())
		syncMaster()
	end)
	syncMaster()

	local warn = W.Text(p, "|cff8a8d93Can't run with Recruit (shared keyword) -- enabling one disables the other.|r", "note", "dim")
	warn:SetPoint("TOPLEFT", X, -58); warn:SetWidth(420); warn:SetJustifyH("LEFT")

	local wChk = W.Check(p, "On whisper", function() return I.db().whisperInvite end,
		function(v) I.db().whisperInvite = v end)
	wChk:SetPoint("TOPLEFT", X, -80)
	local gChk = W.Check(p, "On guild chat", function() return I.db().guildInvite end,
		function(v) I.db().guildInvite = v end)
	gChk:SetPoint("LEFT", wChk, "LEFT", 165, 0)

	local kwLbl = W.Text(p, "KEYWORDS", "note", "dim"); kwLbl:SetPoint("TOPLEFT", X, -114)

	-- Live preview. Matching is WHOLE WORD, which is right ("reinvite" must not
	-- trigger) but not obvious: "inv" alone does NOT match "invite", so the most
	-- natural thing a person types was being ignored. Showing what does and does
	-- not match means never having to guess again.
	local preview = W.Text(p, "", "note", "dim")
	preview:SetPoint("TOPLEFT", X, -168); preview:SetWidth(430); preview:SetJustifyH("LEFT")

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
	kwBox:Size(300, 22); kwBox:SetPoint("TOPLEFT", X, -134)
	kwBox.edit:SetText(I.db().keyword or "inv, invite, +")
	kwBox.edit:SetScript("OnTextChanged", function(s) refreshPreview(s:GetText()) end)

	local kwHint = W.Text(p, "comma-separated -- any of them triggers an invite", "note", "dim")
	kwHint:SetPoint("LEFT", kwBox, "RIGHT", 10, 0)

	refreshPreview(kwBox.edit:GetText())

	-- ---- login toast ----
	local ltLbl = W.Text(p, "LOGIN TOAST", "note", "dim"); ltLbl:SetPoint("TOPLEFT", X, -206)
	local ltChk = W.Check(p, "Pop a toast when someone logs in, with an Invite button",
		function() return I.db().loginToast ~= false end,
		function(v) I.db().loginToast = v and true or false end)
	ltChk:SetPoint("TOPLEFT", X, -226)

	local ltRanks = W.EditBox(p, function(t) I.db().loginToastRanks = t or "" end)
	ltRanks:Size(200, 22); ltRanks:SetPoint("TOPLEFT", X, -252)
	ltRanks.edit:SetText(I.db().loginToastRanks or "")
	-- The example uses THIS guild's lowest rank, read from the roster. It used to
	-- name ours ("sewer", "raider"), which is meaningless in any other guild.
	local egRank = "the rank name"
	if Okanvil.U and Okanvil.U.lowestRankIndex then
		local low = Okanvil.U.lowestRankIndex()
		local nm = low and Okanvil.U.rankName(low)
		if nm and nm ~= "" and not nm:find("^Rank %d") then egRank = "\"" .. nm .. "\"" end
	end
	local ltHint = W.Text(p, "which ranks to toast -- part of the rank name, comma-separated\n(e.g. "
		.. egRank .. "). Empty = nobody.", "note", "dim")
	ltHint:SetPoint("LEFT", ltRanks, "RIGHT", 10, 0); ltHint:SetJustifyH("LEFT")
end
