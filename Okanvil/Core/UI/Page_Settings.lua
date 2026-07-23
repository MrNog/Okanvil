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
	local X = 12

	-- TABS. Everything used to be stacked on one landing page -- appearance, media,
	-- branding, dev, version check, and then the raid overlays crammed into an
	-- improvised right-hand column. It was unreadable. Each concern now gets its own
	-- tab, and W.Dashboard gives every tab its own internal scroll for free.
	local dash = W.Dashboard(host, {
		title = "Settings",
		icon = Okanvil.ICONS.settings,
		drawerWidth = 0,
		footerHeight = 0,
		tabs = {
			{ key = "general", label = "General",    height = 500,
			  build = function(pg) Okanvil:Settings_General(pg) end },
			{ key = "raid",    label = "Raid Tools", height = 470,
			  build = function(pg) Okanvil:Settings_RaidTools(pg) end },
			{ key = "adv",     label = "Advanced",   height = 460,
			  build = function(pg) Okanvil:Settings_Advanced(pg) end },
		},
	})
	fill.dash = dash
	local main = dash.main   -- the badge below anchors to it

	-- app credit -- a small badge in the bottom-right corner (anvil + wordmark),
	-- nicer than a bare line of text.
	local badge = W.Frame(main, "panel")
	badge:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -12, 12)
	badge:SetHeight(48)
	local bIcon = badge:CreateTexture(nil, "ARTWORK")
	bIcon:SetSize(30, 30); bIcon:SetPoint("LEFT", 12, 0)
	bIcon:SetTexture("Interface\\Icons\\Trade_BlackSmithing"); bIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local bName = W.Text(badge, "Okanvil", 14, "accent"); bName:SetPoint("LEFT", bIcon, "RIGHT", 10, 8); bName:Color(1, 0.82, 0)
	local bVer = W.Text(badge, "v" .. (self.version or "1.0"), 10, "dim"); bVer:SetPoint("LEFT", bName, "RIGHT", 5, 0)
	local bBy = W.Text(badge, "forged by |cffe0b860Okanor|r", 10, "dim"); bBy:SetPoint("LEFT", bIcon, "RIGHT", 10, -10)
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

	-- NOTE: W.Slider anchors at its BAR; its own label sits ~5px ABOVE that anchor,
	-- so each slider needs ~46px of vertical room.
	-- APPEARANCE
	local a = W.Text(p, "APPEARANCE", 10, "dim"); a:SetPoint("TOPLEFT", X, -8)
	W.Slider(p, "Window scale", 0.6, 1.4, 0.05, function() return db.scale end,
		function(v) db.scale = v; Okanvil.win:SetScale(v) end, true):SetPoint("TOPLEFT", X, -46)
	W.Slider(p, "Background opacity", 0.3, 1.0, 0.05, function() return db.bgAlpha end,
		function(v) db.bgAlpha = v; Okanvil:ReskinAll(v); Okanvil:RefreshRatArt() end):SetPoint("TOPLEFT", X, -92)
	W.Slider(p, "Font size", 8, 20, 1, function() return db.fontSize end,
		function(v) db.fontSize = v; Okanvil:ApplyFonts() end):SetPoint("TOPLEFT", X, -138)
	local showChk = W.Check(p, "Show rat art on pages",
		function() return (db.ratArt or "on") ~= "off" end,
		function(v) db.ratArt = v and "on" or "off"; Okanvil:RefreshRatArt() end)
	showChk:SetPoint("TOPLEFT", X, -170)
	local pullChk = W.Check(p, "Close all windows on a DBM pull",
		function() return db.closeOnPull ~= false end,
		function(v) db.closeOnPull = v end)
	pullChk:SetPoint("TOPLEFT", X + 200, -170)
	-- rat watermark intensity -- its OWN slider, independent of panel opacity.
	W.Slider(p, "Rat art opacity", 0.0, 0.8, 0.05, function() return db.ratAlpha end,
		function(v) db.ratAlpha = v; Okanvil:RefreshRatArt() end):SetPoint("TOPLEFT", X, -212)

	-- MEDIA
	local m = W.Text(p, "MEDIA", 10, "dim"); m:SetPoint("TOPLEFT", X, -252)
	local fl = W.Text(p, "Font", 11, "dim"); fl:SetPoint("TOPLEFT", X, -274)
	W.DropDown(p, function() return (LSM and LSM:List("font")) or { db.font } end,
		function() return db.font end, function(v) db.font = v; Okanvil:ApplyFonts() end, "font")
		:Size(200, 22):Point("TOPLEFT", X + 90, -272)
	local tl = W.Text(p, "Bar texture", 11, "dim"); tl:SetPoint("TOPLEFT", X, -304)
	W.DropDown(p, function() return (LSM and LSM:List("statusbar")) or { db.statusbar } end,
		function() return db.statusbar end, function(v) db.statusbar = v end, "statusbar")
		:Size(200, 22):Point("TOPLEFT", X + 90, -302)

	-- BRANDING (product name is FIXED -- guilds only set their own skin)
	local b = W.Text(p, "BRANDING", 10, "dim"); b:SetPoint("TOPLEFT", X, -344)
	local nl = W.Text(p, "Guild skin (shown after Okanvil)", 11, "dim"); nl:SetPoint("TOPLEFT", X, -366)
	local nameBox = W.EditBox(p, function(txt)
		db.brand = txt or ""
		if Okanvil.headerPaintBrand then Okanvil.headerPaintBrand() end
		Okanvil.panels["__home"] = nil
	end)
	nameBox:SetSize(320, 22); nameBox:SetPoint("TOPLEFT", X, -384)
	nameBox.edit:SetText((db.brand ~= "Okanvil" and db.brand) or "")
	local nh = W.Text(p, "e.g. RATS Guild Hub -- leave empty for just \"Okanvil\".", 10, "dim")
	nh:SetPoint("TOPLEFT", X, -410)
	local ul = W.Text(p, "Web hub URL", 11, "dim"); ul:SetPoint("TOPLEFT", X, -434)
	local urlBox = W.EditBox(p, function(txt)
		db.hubURL = txt
		if Okanvil.footerPaintHub then Okanvil.footerPaintHub() end   -- live-update footer link
	end)
	urlBox:SetSize(320, 22); urlBox:SetPoint("TOPLEFT", X, -452)
	urlBox.edit:SetText(db.hubURL or "")

end

function Okanvil:Settings_RaidTools(p)
	local db = self.db
	local X = 4

	-- RAID TOOLS -- the two in-raid overlays. Neither owns a nav page: a handful of
	-- switches never justified a Dashboard with an empty footer, and both features
	-- ARE their on-screen overlay. Right-hand column; this space was empty.
	--
	-- The setters below must store a REAL boolean, never nil: W.Check toggles by
	-- inverting what getFn reads, so deleting the key leaves the tick stuck on.
	local RX = X
	local rt = W.Text(p, "RAID CHECK -- the ready-check popup", 10, "dim")
	rt:SetPoint("TOPLEFT", RX, -8)

	local RC = Okanvil.RaidCheck
	if RC then
		local rcdb = function()
			db.raidcheck = db.raidcheck or {}
			return db.raidcheck
		end

		local rcOn = W.Check(p, "Raid check popup on a ready check",
			function() return rcdb().onReadyCheck ~= false end,
			function(v) rcdb().onReadyCheck = v and true or false end)
		rcOn:SetPoint("TOPLEFT", RX + 2, -30)

		local rcHint = W.Text(p, "Who is missing a flask, food or a buff. Leader/assist only.", 10, "dim")
		rcHint:SetPoint("TOPLEFT", RX + 20, -50); rcHint:SetWidth(270); rcHint:SetJustifyH("LEFT")

		local rcNum = W.Check(p, "Show minutes left on each icon",
			function() return rcdb().hideNumbers ~= true end,
			function(v)
				rcdb().hideNumbers = not v
				if RC.RenderToast then RC:RenderToast() end
			end)
		rcNum:SetPoint("TOPLEFT", RX + 2, -74)

		local rcGrey = W.Check(p, "Grey out missing buffs",
			function() return rcdb().hideMissing ~= true end,
			function(v)
				rcdb().hideMissing = not v
				if RC.RenderToast then RC:RenderToast() end
			end)
		rcGrey:SetPoint("TOPLEFT", RX + 2, -100)

		local rcGreyHint = W.Text(p, "Off: only buffs people actually have are drawn.", 10, "dim")
		rcGreyHint:SetPoint("TOPLEFT", RX + 20, -120); rcGreyHint:SetWidth(300); rcGreyHint:SetJustifyH("LEFT")

		local rcSortL = W.Text(p, "Sort by", 11, "dim")
		rcSortL:SetPoint("TOPLEFT", RX + 2, -146)
		W.DropDown(p,
			function() return RC.SORTS or { "group", "class", "name" } end,
			function() return rcdb().sort or "group" end,
			function(v) rcdb().sort = v; if RC.RenderToast then RC:RenderToast() end end)
			:Size(130, 22):Point("TOPLEFT", RX + 60, -144)

		-- W.Slider anchors at its BAR and prints its label ABOVE -- hence the gap.
		W.Slider(p, "Popup size", 70, 160, 5,
			function() return rcdb().scale or 100 end,
			function(v)
				rcdb().scale = v
				if RC.SetToastScale then RC:SetToastScale(v) end
			end):SetPoint("TOPLEFT", RX + 2, -200)

		local rcTest = W.Button(p, "Show it now")
		rcTest:SetSize(110, 22); rcTest:SetPoint("TOPLEFT", RX + 2, -228)
		rcTest:SetScript("OnClick", function() if RC.ShowToast then RC:ShowToast(true) end end)
	end

	-- RAID UTILS -- the floating marks bar (8 raid icons + clear + ready check + a
	-- DBM pull). Same deal: an overlay, not a page.
	local MB = Okanvil.MarksBar
	if MB then
		local ut = W.Text(p, "RAID UTILS -- the floating marks bar", 10, "dim")
		ut:SetPoint("TOPLEFT", RX, -262)
		local mbdb = function()
			db.marksbar = db.marksbar or {}
			return db.marksbar
		end

		local mbOn = W.Check(p, "Raid utils bar (marks, ready check, pull)",
			function() return mbdb().enabled and true or false end,
			function(v) if MB.Toggle then MB:Toggle(v and true or false) end end)
		mbOn:SetPoint("TOPLEFT", RX + 2, -284)

		local mbHint = W.Text(p, "Only visible while you are raid leader or assist.", 10, "dim")
		mbHint:SetPoint("TOPLEFT", RX + 20, -304); mbHint:SetWidth(320); mbHint:SetJustifyH("LEFT")

		W.Slider(p, "Bar size", 70, 160, 5,
			function() return mbdb().scale or 100 end,
			function(v)
				mbdb().scale = v
				if MB.Refresh then MB:Refresh() end
			end):SetPoint("TOPLEFT", RX + 2, -352)

		W.Slider(p, "Pull timer (seconds)", 3, 30, 1,
			function() return mbdb().pullTime or 10 end,
			function(v) mbdb().pullTime = v end):SetPoint("TOPLEFT", RX + 2, -398)
	end

end

function Okanvil:Settings_Advanced(p)
	local db = self.db
	local X = 4

	-- DEV MODE -- routes debug output to a dedicated "Okanvil" chat tab (next to
	-- General / Combat Log) instead of spamming the default chat. Off by default,
	-- so raiders never see it; the tab is only created when this is switched on.
	local dv = W.Text(p, "DEV", 10, "dim"); dv:SetPoint("TOPLEFT", X, -8)
	local devChk = W.Check(p, "Dev mode -- debug output to its own \"Okanvil\" chat tab",
		function() return db.devMode and true or false end,
		function(v) Okanvil:SetDevMode(v) end)
	devChk:SetPoint("TOPLEFT", X + 2, -28)

	-- VERSION CHECK -- opens the RCLootCouncil-style checker popup. A stale client
	-- is what makes "phantom" bugs (e.g. an old build showing the ML layout to a
	-- plain raider), so this is the first thing to check on a bug report.
	local vc = W.Text(p, "VERSION CHECK", 10, "dim"); vc:SetPoint("TOPLEFT", X, -62)
	local vhint = W.Text(p, "Ask your group or the guild which Okanvil they run.", 10, "dim")
	vhint:SetPoint("TOPLEFT", X, -82)

	local vbtn = W.Button(p, "Open version checker", "primary")
	vbtn:SetSize(170, 24); vbtn:SetPoint("TOPLEFT", X, -104)
	vbtn:SetScript("OnClick", function() Okanvil:ShowVersionChecker() end)
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

		local status = W.Text(f, "", 10, "dim")
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

		local out = W.Text(child, "", 11)
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
