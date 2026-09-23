-- ============================================================
-- Okanvil -- Marks Bar (native core module).
-- The little floating strip every raid leader wants: the 8 raid target icons,
-- a Clear, a Ready Check and a Pull.
--
-- 3.3.5a API:
--   SetRaidTargetIcon(unit, i)   i = 1..8 to mark, 0 to clear
--   GetRaidTargetIndex(unit)     what is currently on the target
--   DoReadyCheck()               the ready check itself
-- Marking requires being leader or assist -- the server silently ignores it
-- otherwise, so the leader half of the bar (the 8 marks, Clear, Ready Check and
-- Pull) hides itself when you have no such rights rather than letting you click
-- buttons that do nothing. The shortcuts stay: they open your own windows and
-- have nothing to do with rank.
--
-- PULL: delegated to DBM on purpose. DBM already owns the pull timer the raid
-- knows and hears (countdown, raid warning, cancel). Re-implementing it here
-- would put TWO competing countdowns on screen for anyone running both.
-- ============================================================

local Okanvil = Okanvil
local MB = {}
Okanvil.MarksBar = MB

local ICON_N   = 8
local BTN      = 22
local GAP      = 2
local PAD      = 4
local SEP      = 16   -- the gap at a group boundary (twice the old 8)

local bar

-- The shortcuts, in bar order. Each is an ICON, not a word: eight text buttons made
-- the bar longer than the mark strip itself. `gate` decides whether the shortcut is
-- shown at all -- a button into a module you switched off would do nothing.
local SHORTCUTS = {
	{
		-- The addon itself, first on the bar. Every other shortcut here opens one
		-- particular tool; this one opens the window they all live in, so it does
		-- not need a gate -- there is nothing to switch it off.
		key  = "okanvil",
		icon = "Interface\\Icons\\Trade_BlackSmithing",   -- the anvil, same as the minimap
		run  = function() Okanvil:Toggle() end,
	},
	{
		key  = "loot",
		icon = (Okanvil.ICONS and Okanvil.ICONS.loot) or "Interface\\Icons\\INV_Misc_Coin_02",
		gate = function() return Okanvil:IsModuleEnabled("__loot") end,
		run  = function()
			if Okanvil.RollMgr and Okanvil.RollMgr.Toggle then Okanvil.RollMgr.Toggle() end
		end,
	},
	{
		key  = "prio",
		icon = (Okanvil.ICONS and Okanvil.ICONS.council) or "Interface\\Icons\\INV_Misc_Book_11",
		-- officer material: no button for anyone who could not open the list anyway
		gate = function()
			if not (Okanvil.LootPrio ~= nil and Okanvil:IsModuleEnabled("__loot")) then return false end
			return not (Okanvil.U and Okanvil.U.canSeePrio) or Okanvil.U.canSeePrio()
		end,
		run  = function()
			if Okanvil.LootPrio and Okanvil.LootPrio.Toggle then Okanvil.LootPrio.Toggle() end
		end,
	},
	{
		key  = "finder",
		icon = (Okanvil.ICONS and Okanvil.ICONS.raidfinder) or "Interface\\Icons\\INV_Misc_GroupLooking",
		-- Gate on the MODULE, not on the function existing. The file loads either
		-- way, so the function is always there -- switching the module off in
		-- Modules left its button on the bar, still working.
		gate = function()
			return Okanvil.RaidFinderMini_Toggle ~= nil
				and Okanvil:IsModuleEnabled("Okanvil-RaidFinder")
		end,
		run  = function() Okanvil.RaidFinderMini_Toggle() end,
	},
	{
		key  = "pug",
		-- Same texture as the PuG nav entry and page header, so the shortcut and the
		-- page it opens read as one thing.
		icon = (Okanvil.ICONS and Okanvil.ICONS.pug) or "Interface\\Icons\\Ability_Warrior_RallyingCry",
		gate = function() return Okanvil:IsModuleEnabled("Okanvil-PuG") end,
		-- The only shortcut that opens a PAGE rather than a floating window, so it
		-- has to raise the main window first -- ShowPanel on a hidden window would
		-- switch the page behind it and look like nothing happened.
		run  = function()
			if not Okanvil.win or not Okanvil.win:IsShown() then Okanvil:Toggle() end
			Okanvil:ShowPanel("Okanvil-PuG")
		end,
	},
	{
		key  = "notes",
		icon = (Okanvil.ICONS and Okanvil.ICONS.notes) or "Interface\\Icons\\INV_Misc_Note_01",
		gate = function() return Okanvil:IsModuleEnabled("Okanvil-Notes") end,
		run  = function()
			if not Okanvil.win or not Okanvil.win:IsShown() then Okanvil:Toggle() end
			Okanvil:ShowPanel("Okanvil-Notes")
		end,
	},
	{
		key  = "recruit",
		icon = (Okanvil.ICONS and Okanvil.ICONS.recruit) or "Interface\\Icons\\Ability_Warrior_RallyingCry",
		gate = function() return Okanvil:IsModuleEnabled("Okanvil-Recruit") end,
		run  = function()
			if not Okanvil.win or not Okanvil.win:IsShown() then Okanvil:Toggle() end
			Okanvil:ShowPanel("Okanvil-Recruit")
		end,
	},
	{
		key  = "invite",
		icon = (Okanvil.ICONS and Okanvil.ICONS.invite) or "Interface\\Icons\\Spell_ChargePositive",
		gate = function() return Okanvil:IsModuleEnabled("__invite") end,
		-- Invite has no page of its own: its switches are on the Settings tab.
		run  = function() Okanvil:OpenSettingsTab("invite") end,
	},
	{
		key  = "ids",
		icon = (Okanvil.ICONS and Okanvil.ICONS.ids) or "Interface\\Icons\\INV_Misc_Spyglass_02",
		gate = function() return Okanvil:IsModuleEnabled("Okanvil-IDs") end,
		run  = function()
			if not Okanvil.win or not Okanvil.win:IsShown() then Okanvil:Toggle() end
			Okanvil:ShowPanel("Okanvil-IDs")
		end,
	},
	{
		key  = "buffs",
		-- Resolved at build time from the Well Fed spell itself, so it is the texture
		-- the client really ships. At file scope GetSpellInfo can still be empty.
		iconFn = function() return select(3, GetSpellInfo(57288)) end,
		icon = (Okanvil.ICONS and Okanvil.ICONS.raidcheck) or "Interface\\Icons\\INV_Misc_Food_15",
		gate = function() return Okanvil.RaidCheck ~= nil end,
		run  = function()
			local RC = Okanvil.RaidCheck
			if RC:IsToastShown() then RC:HideToast() else RC:ShowToast(true) end
		end,
	},
	{
		key  = "farm",
		icon = (Okanvil.ICONS and Okanvil.ICONS.farm) or "Interface\\Icons\\INV_Misc_Bag_10",
		gate = function()
			return Okanvil.Farm_Toggle ~= nil and Okanvil:IsModuleEnabled("Okanvil-Farm")
		end,
		run  = function() Okanvil.Farm_Toggle() end,
	},
	{
		key  = "ready",
		icon = "Interface\\RaidFrame\\ReadyCheck-Ready",
		lead = true,            -- a raid command, not a window of your own
		run  = function() DoReadyCheck() end,
	},
	{
		key  = "pull",
		icon = "Interface\\Icons\\Ability_Warrior_OffensiveStance",
		accent = true,          -- the one call to action on the bar
		lead = true,
		run  = function(button)
			if button == "RightButton" then MB:Pull(0) else MB:Pull() end
		end,
	},
}

local function cfg()
	Okanvil.db.marksbar = Okanvil.db.marksbar or {}
	return Okanvil.db.marksbar
end

-- Who is allowed to mark differs between a party and a raid:
--   party  -- ANY member may set a raid target icon, not just the leader.
--   raid   -- only the leader and assists; the server drops it from anyone else.
-- Solo counts as allowed so the bar can be set up and tried out of a group.
local function canMark()
	if (GetNumRaidMembers() or 0) > 0 then
		if IsRaidLeader and IsRaidLeader() then return true end
		if IsRaidOfficer and IsRaidOfficer() then return true end
		return false
	end
	return true    -- party (5-man dungeon) or solo
end
-- Lay out the whole bar. A shortcut whose module is switched off is hidden and the
-- rest slide left to close the gap, so the bar is never wider than the buttons that
-- actually do something -- and the same is true of the marks: a plain raider gets a
-- bar of shortcuts alone, with nothing left behind where the icons used to be.
local function layoutTail(f)
	local lead = canMark()
	local x = PAD

	-- The 8 raid target icons and their Clear, drawn only for someone the server
	-- would obey. Their width is part of the layout, not a fixed offset, so the
	-- shortcuts start at the left edge when the marks are gone.
	for i = 1, ICON_N do
		local b = f.marks[i]
		if lead then
			b:ClearAllPoints()
			b:SetPoint("LEFT", x, 0)
			b:Show()
			x = x + BTN + GAP
		else
			b:Hide()
		end
	end

	if lead then
		f.clear:ClearAllPoints()
		f.clear:SetPoint("LEFT", x, 0)
		f.clear:Show()
		x = x + BTN + SEP

		f.divider:ClearAllPoints()
		f.divider:SetPoint("LEFT", x - SEP / 2, 0)
		f.divider:Show()
	else
		f.clear:Hide()
		f.divider:Hide()
	end

	-- The bar's own short keys, mapped to the module a Shortcut switch names.
	-- Anything absent here is not a module page (the anvil, ready check, pull)
	-- and is never hidden by that switch.
	--
	-- The same map orders the bar: a key listed here is placed in NAV order, so
	-- the icons run left to right exactly as the menu reads top to bottom. The
	-- bar used to have an order of its own, which meant learning it twice.
	local PANEL_OF = {
		loot   = "__loot",
		prio   = "__council",
		finder = "Okanvil-RaidFinder",   -- the bar's "finder" is the RAID finder
		pug    = "Okanvil-PuG",
		notes  = "Okanvil-Notes",
		recruit = "Okanvil-Recruit",
		invite = "__invite",
		ids    = "Okanvil-IDs",
		farm   = "Okanvil-Farm",
	}

	-- Sorted before drawing: module pages in NAV order first, then the tools that
	-- belong to no page (ready check, pull) in the order they are declared.
	local rank = {}
	do
		local i = 0
		for _, group in ipairs(Okanvil.NAV_GROUPS or {}) do
			for _, title in ipairs(group.items) do
				i = i + 1
				local panel = Okanvil.PANEL_KEY and Okanvil.PANEL_KEY[title]
				if panel then rank[panel] = i end
			end
		end
	end

	-- Which group each shortcut sits in. The marks are group 1 (drawn above,
	-- before any of this), the anvil gets one to itself because it opens the
	-- window the page shortcuts live inside, then the pages follow the menu
	-- sections, and the things that act on the raid rather than opening a
	-- window come last. A boundary is drawn wherever this number changes.
	local GROUP_OF = {
		okanvil = 2,
		loot = 3, notes = 3, finder = 3, pug = 3,   -- RAID
		invite = 4, recruit = 4, prio = 4,          -- GUILD
		ids = 5, farm = 5,                          -- TOOLS
		buffs = 6, ready = 6, pull = 6,             -- acts on the raid
	}

	local ordered = {}
	for i, sc in ipairs(SHORTCUTS) do
		ordered[#ordered + 1] = {
			sc = sc, i = i, g = GROUP_OF[sc.key], r = rank[PANEL_OF[sc.key] or ""],
		}
	end
	-- Group first, so the bar never puts a boundary in the middle of one; then
	-- NAV order inside a group, so the icons read left to right the way the
	-- menu reads top to bottom; then the declared order for anything with no
	-- nav row of its own (ready check, pull).
	table.sort(ordered, function(a, b)
		local ga, gb = a.g or 99, b.g or 99
		if ga ~= gb then return ga < gb end
		if a.r and b.r then return a.r < b.r end
		if a.r then return true end
		if b.r then return false end
		return a.i < b.i
	end)

	local nDiv, lastGroup = 0, nil

	for _, entry in ipairs(ordered) do
		local sc = entry.sc
		local b = f.short[sc.key]
		-- Two gates: the module has to be ON, and you have to have kept its
		-- shortcut. The second was missing here entirely, so switching a shortcut
		-- off on the Modules page changed the Raid Check strip and left this bar
		-- exactly as it was.
		local wanted = true
		local panel = PANEL_OF[sc.key]
		if panel and Okanvil.IsShortcutEnabled then
			wanted = Okanvil:IsShortcutEnabled(panel)
		end
		-- A third gate for the two that command the raid rather than opening a
		-- window: no rank, no button, the same rule the marks follow.
		if sc.lead and not lead then wanted = false end
		if wanted and ((not sc.gate) or sc.gate()) then
			-- A boundary only where a group actually changes between two drawn
			-- buttons: hide every shortcut in a group and its divider never
			-- appears, instead of a hairline floating with nothing beside it.
			local g = GROUP_OF[sc.key]
			if lastGroup and g and g ~= lastGroup then
				nDiv = nDiv + 1
				local d = f.divs[nDiv]
				if not d then
					d = f:CreateTexture(nil, "ARTWORK")
					d:SetTexture("Interface\\Buttons\\WHITE8X8")
					d:SetVertexColor(1, 1, 1, 0.12)
					d:SetSize(1, BTN - 2)
					f.divs[nDiv] = d
				end
				x = x + SEP - GAP
				d:ClearAllPoints()
				d:SetPoint("LEFT", f, "LEFT", x - SEP / 2, 0)
				d:Show()
			end
			if g then lastGroup = g end
			-- Cleared first: a shortcut moves now that the marks come and go, and
			-- a second SetPoint on top of the old one anchors it to both.
			b:ClearAllPoints()
			b:SetPoint("LEFT", x, 0)
			b:Show()
			x = x + BTN + GAP
		else
			b:Hide()
		end
	end
	-- Anything left over from a wider bar last time round.
	for i = nDiv + 1, #f.divs do f.divs[i]:Hide() end

	-- max(): with no rank and every shortcut switched off there is nothing left to
	-- measure, and a width of PAD*2 - GAP is a frame the game will not accept.
	f:SetWidth(math.max(x - GAP + PAD, BTN + PAD * 2))
end


-- ------------------------------------------------------------
-- Build
-- ------------------------------------------------------------
local function build()
	if bar then return bar end
	local W = Okanvil.W
	local C = Okanvil.Colors

	local f = W.Frame(UIParent, "dark")
	f:SetFrameStrata("MEDIUM")
	f:SetBackdropColor(0.05, 0.05, 0.06, 0.92)
	f:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.75)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(s) s:StartMoving() end)
	f:SetScript("OnDragStop", function(s)
		s:StopMovingOrSizing()
		local p, _, _, x, y = s:GetPoint(1)
		local d = cfg()
		d.point, d.x, d.y = p, x, y
	end)

	-- the 8 raid target icons. Placed by layoutTail(), not here: they come and go
	-- with your rank, and the shortcuts have to close the gap when they go.
	f.marks = {}
	for i = 1, ICON_N do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(BTN, BTN)

		local t = b:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints()
		-- The stock raid-target sheet: SetRaidTargetIconTexture picks the right
		-- quadrant for index i, so we never hand-crop TexCoords.
		t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		SetRaidTargetIconTexture(t, i)
		b.tex = t

		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetTexture("Interface\\Buttons\\WHITE8X8")
		hl:SetVertexColor(1, 1, 1, 0.18)

		b:SetScript("OnClick", function()
			-- Toggle: clicking the icon already on the target removes it.
			if GetRaidTargetIndex("target") == i then
				SetRaidTargetIcon("target", 0)
			else
				SetRaidTargetIcon("target", i)
			end
		end)
		f.marks[i] = b
	end

	-- Clear: strip the icon off the current target
	local clear = W.Button(f, "X", "danger")
	clear:SetSize(BTN, BTN)
	clear:SetScript("OnClick", function() SetRaidTargetIcon("target", 0) end)
	f.clear = clear

	-- A hairline between the marks and the shortcuts: two different kinds of action.
	local div = f:CreateTexture(nil, "ARTWORK")
	div:SetTexture("Interface\\Buttons\\WHITE8X8")
	div:SetVertexColor(1, 1, 1, 0.12)
	div:SetSize(1, BTN - 2)
	f.divider = div

	-- The rest of the hairlines are made on demand: the bar splits into as many
	-- groups as GROUP_OF names, and how many are actually drawn depends on
	-- which shortcuts survive their gates. One texture per boundary, reused.
	f.divs = {}

	-- Shortcut buttons: an icon each, built from the SHORTCUTS table.
	f.short = {}
	for _, sc in ipairs(SHORTCUTS) do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(BTN, BTN)

		local t = b:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints()
		t:SetTexture((sc.iconFn and sc.iconFn()) or sc.icon)
		t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		if not sc.accent then t:SetVertexColor(0.82, 0.82, 0.85, 1) end

		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetTexture("Interface\\Buttons\\WHITE8X8")
		hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.25)

		if sc.accent then
			local glow = b:CreateTexture(nil, "BACKGROUND")
			glow:SetAllPoints()
			glow:SetTexture("Interface\\Buttons\\WHITE8X8")
			glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.30)
		end

		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(_, button) sc.run(button) end)
		-- No tooltip: the icons are self-evident and a popup over a raid frame is
		-- more in the way than it is worth. Hover just brightens the icon.
		b:SetScript("OnEnter", function() t:SetVertexColor(1, 1, 1, 1) end)
		b:SetScript("OnLeave", function()
			if not sc.accent then t:SetVertexColor(0.82, 0.82, 0.85, 1) end
		end)

		f.short[sc.key] = b
	end

	f:SetHeight(BTN + PAD * 2)
	layoutTail(f)

	local d = cfg()
	f:ClearAllPoints()
	if d.point then
		f:SetPoint(d.point, UIParent, d.point, d.x or 0, d.y or 0)
	else
		f:SetPoint("TOP", UIParent, "TOP", 0, -180)
	end
	f:SetScale((d.scale or 100) / 100)
	f:Hide()

	bar = f
	return f
end

-- ------------------------------------------------------------
-- Pull -- delegate to DBM.
-- DBM does not export a clean public pull function on 3.3.5a (the timer lives
-- inside its own slash handler), so drive it exactly the way a user would: run
-- the slash command. That is the one entry point DBM guarantees.
-- ------------------------------------------------------------
-- Two things are needed, not one:
--   1. drive whichever boss mod registered a /pull slash (DBM or BigWigs), AND
--   2. broadcast the addon message, so raiders running the OTHER boss mod (or no
--      Okanvil at all) still get the countdown on their screen.
-- Doing only (1) starts a timer that only YOU can see. Doing only (2) misses your
-- own client. Both are required.
function MB:Pull(secs)
	-- A pull timer shouts at the whole group, so unlike marking it stays a
	-- leader/assist action even in a party.
	local lead = (IsRaidLeader and IsRaidLeader())
		or (IsRaidOfficer and IsRaidOfficer())
		or ((GetNumRaidMembers() or 0) == 0 and IsPartyLeader and IsPartyLeader())
	if not lead then
		Okanvil:Print("Pull: you need to be the leader or an assist.")
		return
	end
	secs = secs or (cfg().pullTime or 10)

	local chan = (GetNumRaidMembers() or 0) > 0 and "RAID"
		or ((GetNumPartyMembers() or 0) > 0 and "PARTY")
	if not chan then
		Okanvil:Print("Pull: you are not in a group.")
		return
	end

	local S = SlashCmdList
	if S then
		if S["pull"] then S["pull"](tostring(secs))
		elseif S["BIGWIGSPULL"] then S["BIGWIGSPULL"](tostring(secs))
		elseif S["DEADLYBOSSMODSPULL"] then S["DEADLYBOSSMODSPULL"](tostring(secs))
		end
	end

	SendAddonMessage("BigWigs", "P^Pull^" .. secs, chan)

	-- DBM's pull sync. The addon-message PREFIX is "D5" even though the handler is
	-- named "DBMv4-PT" -- do not infer the prefix from the handler name. Sender is
	-- "<name>-<realm, spaces stripped>".
	local realm = (GetRealmName() or ""):gsub("[%s%-]+", "")
	local me = (UnitName("player") or "") .. "-" .. realm .. "\t"
	SendAddonMessage("D5", ("%s1\tPT\t%d\t%d"):format(me, secs, 0), chan)
end

-- ------------------------------------------------------------
-- Show / hide
-- ------------------------------------------------------------
function MB:Toggle(on)
	build()
	local d = cfg()
	if on == nil then on = not d.enabled end
	d.enabled = on and true or false
	self:Refresh()
end

function MB:Refresh()
	if not bar then return end
	local d = cfg()
	layoutTail(bar)
	-- The bar itself follows its own switch only. Rank decides what is ON it --
	-- layoutTail drops the marks, Clear, Ready Check and Pull for a plain raider --
	-- but the shortcuts into your own windows are yours whatever your rank, and
	-- hiding the lot took them away in the middle of a raid.
	if d.enabled then bar:Show() else bar:Hide() end
	bar:SetScale((d.scale or 100) / 100)
end


-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("RAID_ROSTER_UPDATE")      -- promotion/demotion changes canMark()
ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
-- The GUILD roster decides whether the priority shortcut is shown, and it arrives
-- well after PLAYER_LOGIN -- so the bar was laid out while the answer was still
-- "no guild, no ranks", and an officer (or an officer's alt) had no prio button
-- until something raid-related happened to refresh it.
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		build()
		MB:Refresh()

		-- No module page: the bar IS the feature, and its switches live in the host's
		-- Settings page under RAID TOOLS.
		return
	end
	MB:Refresh()
end)
