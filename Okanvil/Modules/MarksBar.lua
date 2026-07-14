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
-- otherwise, so the bar hides itself when you have no such rights rather than
-- letting you click buttons that do nothing.
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
local SEP      = 8    -- divider between the marks and the shortcuts

local bar

-- The shortcuts, in bar order. Each is an ICON, not a word: eight text buttons made
-- the bar longer than the mark strip itself. `gate` decides whether the shortcut is
-- shown at all -- a button into a module you switched off would do nothing.
local SHORTCUTS = {
	{
		key  = "loot",
		icon = "Interface\\Icons\\INV_Misc_Coin_02",
		gate = function() return Okanvil:IsModuleEnabled("__loot") end,
		run  = function()
			if Okanvil.RollMgr and Okanvil.RollMgr.Toggle then Okanvil.RollMgr.Toggle() end
		end,
	},
	{
		key  = "finder",
		icon = "Interface\\Icons\\INV_Misc_GroupLooking",   -- the Raid Finder's own icon
		gate = function() return Okanvil.RaidFinderMini_Toggle ~= nil end,
		run  = function() Okanvil.RaidFinderMini_Toggle() end,
	},
	{
		key  = "buffs",
		-- Resolved at build time from the Well Fed spell itself, so it is the texture
		-- the client really ships. At file scope GetSpellInfo can still be empty.
		iconFn = function() return select(3, GetSpellInfo(57288)) end,
		icon = "Interface\\Icons\\INV_Misc_Food_15",
		gate = function() return Okanvil.RaidCheck ~= nil end,
		run  = function()
			local RC = Okanvil.RaidCheck
			if RC:IsToastShown() then RC:HideToast() else RC:ShowToast(true) end
		end,
	},
	{
		key  = "ready",
		icon = "Interface\\RaidFrame\\ReadyCheck-Ready",
		run  = function() DoReadyCheck() end,
	},
	{
		key  = "pull",
		icon = "Interface\\Icons\\Ability_Warrior_OffensiveStance",
		accent = true,          -- the one call to action on the bar
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
-- Lay out everything past the mark icons. A shortcut whose module is switched off is
-- hidden and the rest slide left to close the gap, so the bar is never wider than
-- the buttons that actually do something.
local function layoutTail(f)
	local x = f.tailX

	f.clear:SetPoint("LEFT", x, 0)
	x = x + BTN + SEP

	f.divider:SetPoint("LEFT", x - SEP / 2, 0)

	for _, sc in ipairs(SHORTCUTS) do
		local b = f.short[sc.key]
		if (not sc.gate) or sc.gate() then
			b:SetPoint("LEFT", x, 0)
			b:Show()
			x = x + BTN + GAP
		else
			b:Hide()
		end
	end

	f:SetWidth(x - GAP + PAD)
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

	local x = PAD

	-- the 8 raid target icons
	f.marks = {}
	for i = 1, ICON_N do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(BTN, BTN)
		b:SetPoint("LEFT", x, 0)

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
		x = x + BTN + GAP
	end

	-- Everything past the mark icons is positioned by layoutTail(), because the Loot
	-- button comes and goes with the Loot module and the rest has to close the gap.
	f.tailX = x

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
	-- Only useful to someone who can actually mark: a plain raider clicking these
	-- would be sending commands the server throws away.
	if d.enabled and canMark() then bar:Show() else bar:Hide() end
	bar:SetScale((d.scale or 100) / 100)
end


-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("RAID_ROSTER_UPDATE")      -- promotion/demotion changes canMark()
ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
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
