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
local PAD      = 8
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
		icon = Okanvil.BRAND_ICON,   -- the addon icon, same as the minimap
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
		gate = function() return Okanvil:IsModuleEnabled("Okanvil-RaidFinder") end,
		-- Opens the full Raid Finder page; the floating Mini Browser stays one
		-- click away on that page's header button.
		run  = function()
			if not Okanvil.win or not Okanvil.win:IsShown() then Okanvil:Toggle() end
			Okanvil:ShowPanel("Okanvil-RaidFinder")
		end,
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
		key  = "upgrades",
		icon = (Okanvil.ICONS and Okanvil.ICONS.upgrades) or "Interface\\Icons\\INV_Sword_39",
		gate = function() return Okanvil:IsModuleEnabled("Okanvil-Upgrades") end,
		run  = function()
			if not Okanvil.win or not Okanvil.win:IsShown() then Okanvil:Toggle() end
			Okanvil:ShowPanel("Okanvil-Upgrades")
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
		key  = "ranking",
		icon = (Okanvil.ICONS and Okanvil.ICONS.ranking) or "Interface\\Icons\\Ability_Marksmanship",
		gate = function() return Okanvil:IsModuleEnabled("Okanvil-Ranking") end,
		run  = function()
			if not Okanvil.win or not Okanvil.win:IsShown() then Okanvil:Toggle() end
			Okanvil:ShowPanel("Okanvil-Ranking")
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
--   solo   -- nobody to mark for, so the marks, Ready Check and Pull stay hidden.
local function canMark()
	if (GetNumRaidMembers() or 0) > 0 then
		if IsRaidLeader and IsRaidLeader() then return true end
		if IsRaidOfficer and IsRaidOfficer() then return true end
		return false
	end
	return (GetNumPartyMembers() or 0) > 0
end

-- ------------------------------------------------------------
-- LFG slot -- the dungeon finder queue, live on the bar.
-- Five role icons (tank, healer, 3 dps) and the time in queue: a gold role is
-- filled, a grey one is still missing. Shown only while queued, so the bar is
-- unchanged the rest of the time.
--
-- 3.3.5a API:
--   GetLFGMode()        "queued" / "proposal" / "rolecheck" / "lfgparty" / ...
--   GetLFGQueueStats()  hasData, leaderNeeds, tankNeeds, healerNeeds, dpsNeeds,
--                       instanceType, instanceName, averageWait, tankWait,
--                       healerWait, damageWait, myWait, queuedTime
-- ------------------------------------------------------------
local LFG_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }
local LFG_TEXT_GAP = 4   -- between the last role icon and the clock

local function lfgMode()
	local mode = GetLFGMode and GetLFGMode()
	if mode == "queued" or mode == "proposal" then return mode end
	if not GetLFGMode and GetLFGInfoServer and select(3, GetLFGInfoServer()) then
		return "queued"
	end
end

-- Queued, and the slot not switched off in Settings.
local function lfgWanted()
	return cfg().lfg ~= false and lfgMode()
end

local function fmtTime(secs)
	secs = math.max(0, math.floor(secs or 0))
	if secs >= 3600 then
		return ("%d:%02d:%02d"):format(secs / 3600, (secs % 3600) / 60, secs % 60)
	end
	return ("%d:%02d"):format(secs / 60, secs % 60)
end

-- Which of the five icons are filled, from what the queue still needs.
-- No data yet (the first second of a queue) reads as nothing filled.
local function lfgFilled(t, h, d)
	return {
		t == 0,
		h == 0,
		d ~= nil and d <= 2,
		d ~= nil and d <= 1,
		d == 0,
	}
end

local function lfgMissingText(t, h, d)
	local miss = {}
	if (t or 1) > 0 then miss[#miss + 1] = "Tank" end
	if (h or 1) > 0 then miss[#miss + 1] = "Healer" end
	if (d or 3) > 0 then miss[#miss + 1] = (d or 3) .. " DPS" end
	return #miss > 0 and table.concat(miss, ", ") or "nobody"
end

-- The slot is as wide as its text, so the bar ends right after the clock. The
-- slot is the bar's last item: its left edge (leftX, set by layoutTail) plus its
-- width is the whole bar, and resizing it needs no full relayout.
-- Measured with every digit as an 8, the widest one, and never shrinking while
-- queued: a clock sized to its exact digits made the bar's edge twitch each second.
local function fitLfg(s)
	local wide = (s.time:GetText() or ""):gsub("%d", "8")
	s.measure:SetText(wide)
	local w = #LFG_ROLES * (BTN + GAP) - GAP + LFG_TEXT_GAP
		+ math.ceil(s.measure:GetStringWidth() or 0)
	w = math.max(w, s.minW or 0)
	s.minW = w
	if math.abs(s:GetWidth() - w) < 1 then return end
	s:SetWidth(w)
	if s.leftX then s:GetParent():SetWidth(s.leftX + w + PAD) end
end

local function updateLfg(s)
	local mode = lfgMode()
	if not mode then return end
	local C = Okanvil.Colors

	if mode == "proposal" then
		for i = 1, #LFG_ROLES do
			Okanvil.W.SetFramedIconUsable(s.roles[i], true)
			s.roles[i].on = true
		end
		s.time:SetText("READY")
		s.time:SetTextColor(C.accentText[1], C.accentText[2], C.accentText[3])
		s.pulseUntil = math.huge
		fitLfg(s)
		return
	end

	local _, _, t, h, d, _, _, _, _, _, _, _, queuedTime = GetLFGQueueStats()
	local filled = lfgFilled(t, h, d)
	for i = 1, #LFG_ROLES do
		Okanvil.W.SetFramedIconUsable(s.roles[i], filled[i])
		s.roles[i].on = filled[i]
	end

	-- The two roles a dungeon queue actually waits on: a short glow when one lands.
	if (s.lastT and s.lastT > 0 and t == 0) or (s.lastH and s.lastH > 0 and h == 0) then
		s.pulseUntil = GetTime() + 3
	elseif s.pulseUntil == math.huge then
		s.pulseUntil = nil   -- a declined proposal drops back to the queue
	end
	s.lastT, s.lastH = t, h

	-- The server's queue time arrives with its first status packet, which can take
	-- a while; until then the clock counts from when the slot first saw the queue.
	s.startedAt = s.startedAt or GetTime()
	s.time:SetText(fmtTime(GetTime() - (queuedTime or s.startedAt)))
	s.time:SetTextColor(C.text[1], C.text[2], C.text[3])
	fitLfg(s)
end

local function buildLfg(f)
	local W = Okanvil.W
	local C = Okanvil.Colors

	local s = CreateFrame("Button", nil, f)
	s:SetSize(#LFG_ROLES * (BTN + GAP), BTN)

	s.roles = {}
	for i, role in ipairs(LFG_ROLES) do
		local r = W.FramedIcon(s, "Interface\\LFGFrame\\UI-LFG-ICON-ROLES", BTN)
		r:SetPoint("LEFT", (i - 1) * (BTN + GAP), 0)
		if GetTexCoordsForRole then r.icon:SetTexCoord(GetTexCoordsForRole(role)) end
		-- the soft action-button glow round each filled role when a tank/healer
		-- lands or the group is ready; it has no edges, so nothing squares the frame
		local glow = r:CreateTexture(nil, "OVERLAY")
		glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		glow:SetBlendMode("ADD")
		glow:SetSize(BTN * 1.9, BTN * 1.9)
		glow:SetPoint("CENTER")
		glow:SetAlpha(0)
		r.glow = glow
		s.roles[i] = r
	end

	local time = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	time:SetPoint("LEFT", s.roles[#LFG_ROLES], "RIGHT", 4, 0)
	time:SetJustifyH("LEFT")
	s.time = time

	-- never shown: sizes the slot for fitLfg
	local measure = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	measure:Hide()
	s.measure = measure

	-- Once a second: the clock, and the queue stats read again -- they change
	-- without always firing an event. The glow runs every frame while it lasts.
	local tick = 0
	s:SetScript("OnUpdate", function(self, elapsed)
		tick = tick + elapsed
		if tick >= 1 then
			tick = 0
			updateLfg(self)
		end
		local a = 0
		if self.pulseUntil and GetTime() < self.pulseUntil then
			a = 0.35 + 0.45 * (0.5 + 0.5 * math.sin(GetTime() * 6))
		else
			self.pulseUntil = nil
		end
		for _, r in ipairs(self.roles) do r.glow:SetAlpha(r.on and a or 0) end
	end)

	s:RegisterForClicks("LeftButtonUp")
	s:SetScript("OnClick", function()
		if ToggleLFDParentFrame then ToggleLFDParentFrame() end
	end)
	s:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint("TOP", self, "BOTTOM", 0, -(PAD + 3))
		local _, _, t, h, d, _, name, avg, _, _, _, myWait, queuedTime = GetLFGQueueStats()
		GameTooltip:SetText(name or "Dungeon Finder", 1, 0.82, 0)
		if lfgMode() == "proposal" then
			GameTooltip:AddLine("Group ready", C.ok[1], C.ok[2], C.ok[3])
		else
			GameTooltip:AddDoubleLine("Missing", lfgMissingText(t, h, d), 0.8, 0.8, 0.8, 1, 1, 1)
			if queuedTime then
				GameTooltip:AddDoubleLine("In queue", fmtTime(GetTime() - queuedTime), 0.8, 0.8, 0.8, 1, 1, 1)
			end
			if avg and avg > 0 then
				GameTooltip:AddDoubleLine("Average wait", fmtTime(avg), 0.8, 0.8, 0.8, 1, 1, 1)
			end
			if myWait and myWait > 0 then
				GameTooltip:AddDoubleLine("Your wait", fmtTime(myWait), 0.8, 0.8, 0.8, 1, 1, 1)
			end
		end
		GameTooltip:AddLine("Click: Dungeon Finder", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	s:SetScript("OnLeave", function() GameTooltip:Hide() end)

	s:Hide()
	return s
end

-- ------------------------------------------------------------
-- XP / reputation strip under the bar.
-- XP while there is XP to gain, else the watched faction, else nothing. It hangs
-- off the bar's bottom edge at the bar's width, so it follows every relayout.
--
-- 3.3.5a API:
--   UnitXP / UnitXPMax / GetXPExhaustion   current, needed, rested pool
--   GetRestState()                         1 = rested, 2 = normal
--   GetWatchedFactionInfo()                name, standing, min, max, value
-- No level-cap test: custom servers report XP oddly at the cap, so "is there XP
-- to gain" is read from the numbers themselves.
-- ------------------------------------------------------------
-- The art is DragonUI's XP bar (MIT, see Media\XP\LICENSE.txt): a background, the
-- fill sheets and a framed overlay with the 10% marks drawn in.
local XP_H   = 14
local XP_ART = "Interface\\AddOns\\Okanvil\\Media\\XP\\"

-- reputation fill by standing: hated/hostile, unfriendly, neutral, friendly and up
local function repSheet(standing)
	if standing <= 2 then return XP_ART .. "rep-red" end
	if standing == 3 then return XP_ART .. "rep-orange" end
	if standing == 4 then return XP_ART .. "rep-yellow" end
	return XP_ART .. "rep-green"
end

local function xpToGain()
	local maxXP = UnitXPMax("player")
	if not maxXP or maxXP <= 0 then return false end
	return (UnitXP("player") or 0) < maxXP
end

local function fmtNum(n)
	n = math.floor(n or 0)
	local s = tostring(n)
	while true do
		local k
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then return s end
	end
end

-- What the strip shows now: "xp", "rep" or nil.
local function xpKind()
	if cfg().xp == false then return nil end
	if xpToGain() then return "xp" end
	if GetWatchedFactionInfo() then return "rep" end
	return nil
end

-- 3.3.5a stretches the whole texture into the fill; crop it to the filled part
-- so the sheet's capped end keeps its shape at any value.
local function cropFill(bar)
	local lo, hi = bar:GetMinMaxValues()
	if not hi or hi <= lo then return end
	local pct = (bar:GetValue() - lo) / (hi - lo)
	bar:GetStatusBarTexture():SetTexCoord(0, math.max(0, math.min(pct, 1)), 0, 1)
end

local function newFill(parent, level, sheet)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetAllPoints(parent)
	b:SetStatusBarTexture(sheet)
	b.sheet = sheet
	b:SetFrameLevel(level)
	hooksecurefunc(b, "SetValue", cropFill)
	return b
end

-- Swapping the sheet resets its crop, so this runs before SetValue.
local function setSheet(b, sheet)
	if b.sheet == sheet then return end
	b:SetStatusBarTexture(sheet)
	b.sheet = sheet
end

-- The longest of `texts` that fits inside the frame's ends; a short bar (a raider
-- with few shortcuts) drops to a shorter line, down to the bare percentage.
local function fitXpText(x, texts)
	local room = (x:GetWidth() or 0) - 16
	for i = 1, #texts do
		x.text:SetText(texts[i])
		if i == #texts or x.text:GetStringWidth() <= room then return end
	end
end

local function updateXp(x)
	local kind = xpKind()
	if not kind then x:Hide(); return end
	x.kind = kind
	local fill, rested = x.fill, x.rested

	if kind == "xp" then
		local cur, max = UnitXP("player") or 0, UnitXPMax("player")
		local pool = GetXPExhaustion() or 0
		setSheet(fill, XP_ART .. ((GetRestState() == 1) and "rested" or "main"))
		fill:SetMinMaxValues(0, max)
		fill:SetValue(cur)
		if pool > 0 then
			rested:SetMinMaxValues(0, max)
			rested:SetValue(math.min(cur + pool, max))
			rested:Show()
		else
			rested:Hide()
		end
		x.value = cur / max
		local lv, pct = UnitLevel("player"), ("%.1f%%"):format(100 * x.value)
		local texts = {}
		if pool > 0 then
			texts[1] = ("Lv %d  %s  |cff8fb8ff+%.0f%% rested|r"):format(lv, pct, 100 * pool / max)
		end
		texts[#texts + 1] = ("Lv %d  %s"):format(lv, pct)
		texts[#texts + 1] = pct
		fitXpText(x, texts)
	else
		local name, standing, lo, hi, value = GetWatchedFactionInfo()
		setSheet(fill, repSheet(standing))
		local span = math.max(1, hi - lo)
		fill:SetMinMaxValues(0, span)
		fill:SetValue(value - lo)
		rested:Hide()
		x.value = (value - lo) / span
		local label, pct = _G["FACTION_STANDING_LABEL" .. standing] or "", ("%.0f%%"):format(100 * x.value)
		fitXpText(x, {
			("%s  %s  %s"):format(name, label, pct),
			("%s  %s"):format(name, pct),
			("%s  %s"):format(label, pct),
			pct,
		})
	end
	x:Show()
end

local function showXpTooltip(x)
	GameTooltip:SetOwner(x, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("TOP", x, "BOTTOM", 0, -4)
	if x.kind == "xp" then
		local cur, max = UnitXP("player") or 0, UnitXPMax("player")
		local pool = GetXPExhaustion() or 0
		GameTooltip:SetText(("Level %d  -  %.1f%%"):format(UnitLevel("player"), 100 * cur / max), 1, 0.82, 0)
		GameTooltip:AddDoubleLine("XP", fmtNum(cur) .. " / " .. fmtNum(max), 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine("To level", fmtNum(max - cur), 0.8, 0.8, 0.8, 1, 1, 1)
		if pool > 0 then
			GameTooltip:AddDoubleLine("Rested", ("%s (%.0f%%)"):format(fmtNum(pool), 100 * pool / max),
				0.8, 0.8, 0.8, 0.56, 0.72, 1)
		end
	else
		local name, standing, lo, hi, value = GetWatchedFactionInfo()
		if not name then return end
		local label = _G["FACTION_STANDING_LABEL" .. standing] or ""
		local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing] or { r = 1, g = 1, b = 1 }
		GameTooltip:SetText(name, 1, 0.82, 0)
		GameTooltip:AddDoubleLine(label, fmtNum(value - lo) .. " / " .. fmtNum(hi - lo),
			c.r, c.g, c.b, 1, 1, 1)
		GameTooltip:AddDoubleLine("To next", fmtNum(hi - value), 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddLine("Click: Reputation", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function buildXp(f)
	local x = CreateFrame("Button", nil, f)
	x:SetHeight(XP_H)
	x:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -3)
	x:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -3)

	local bg = x:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(XP_ART .. "bg")

	-- the rested pool, faint behind the fill
	x.rested = newFill(x, x:GetFrameLevel() + 1, XP_ART .. "restedbg")
	x.rested:SetAlpha(0.69)
	x.fill = newFill(x, x:GetFrameLevel() + 2, XP_ART .. "main")

	-- the frame and its 10% marks, a pixel taller than the bar so it caps the fill
	local over = CreateFrame("Frame", nil, x)
	over:SetAllPoints()
	over:SetFrameLevel(x:GetFrameLevel() + 3)
	local frame = over:CreateTexture(nil, "ARTWORK")
	frame:SetTexture(XP_ART .. "overlay")
	frame:SetPoint("TOPLEFT", 0, 1)
	frame:SetPoint("BOTTOMRIGHT", 0, -1)

	local text = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER", 0, 1)
	local font, size = text:GetFont()
	text:SetFont(font, (size or 10) - 1, "OUTLINE")
	x.text = text
	-- the bar's width moves with its shortcuts and the LFG slot: re-fit the text
	x:SetScript("OnSizeChanged", function(self) if self:IsShown() then updateXp(self) end end)

	-- drags the bar like the bar itself does
	x:RegisterForDrag("LeftButton")
	x:SetScript("OnDragStart", function() if f:IsMovable() then f:StartMoving() end end)
	x:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)

	x:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	x:SetScript("OnClick", function(self, button)
		if self.kind == "rep" and button == "LeftButton" then
			ToggleCharacter("ReputationFrame")
		elseif button == "RightButton" and MainMenuExpBar then
			-- server-side XP rate menus hang off the stock bar's right-click
			local h = MainMenuExpBar:GetScript("OnMouseDown")
			if h then h(MainMenuExpBar, button) end
		end
	end)
	x:SetScript("OnEnter", showXpTooltip)
	x:SetScript("OnLeave", function() GameTooltip:Hide() end)

	x:Hide()
	return x
end

-- A hairline at a group boundary, one texture per boundary, reused.
local function placeDivider(f, n, x)
	local d = f.divs[n]
	if not d then
		d = f:CreateTexture(nil, "ARTWORK")
		d:SetTexture("Interface\\Buttons\\WHITE8X8")
		d:SetVertexColor(1, 1, 1, 0.12)
		d:SetSize(1, BTN - 2)
		f.divs[n] = d
	end
	d:ClearAllPoints()
	d:SetPoint("LEFT", f, "LEFT", x - SEP / 2, 0)
	d:Show()
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
		x = x - GAP + SEP

		f.divider:ClearAllPoints()
		f.divider:SetPoint("LEFT", x - SEP / 2, 0)
		f.divider:Show()
	else
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
		upgrades = "Okanvil-Upgrades",
		notes  = "Okanvil-Notes",
		recruit = "Okanvil-Recruit",
		ranking = "Okanvil-Ranking",
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
		loot = 3, upgrades = 3, notes = 3, finder = 3, pug = 3,   -- RAID
		invite = 4, recruit = 4, prio = 4, ranking = 4,   -- GUILD
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
				x = x + SEP - GAP
				placeDivider(f, nDiv, x)
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
	-- The LFG slot, last and in a group of its own, only while queued.
	if f.lfg then
		if lfgWanted() then
			if x > PAD then
				nDiv = nDiv + 1
				x = x + SEP - GAP
				placeDivider(f, nDiv, x)
			end
			f.lfg:ClearAllPoints()
			f.lfg:SetPoint("LEFT", x, 0)
			f.lfg.leftX = x
			updateLfg(f.lfg)
			f.lfg:Show()
			x = x + f.lfg:GetWidth() + GAP
		else
			f.lfg:Hide()
			f.lfg.startedAt = nil
			f.lfg.leftX = nil
			f.lfg.minW = nil
		end
		f.lfgShown = f.lfg:IsShown()
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

	local f = W.Frame(UIParent, "input")
	f._okKeepCut = true
	f:SetFrameStrata("MEDIUM")
	f:SetBackdropColor(0.05, 0.05, 0.06, 0.92)
	f:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], 1)
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

		-- Left-click puts the mark on the target (again = take it off); right-click
		-- on any mark clears the target's mark.
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(_, button)
			if button == "RightButton" then SetRaidTargetIcon("target", 0); return end
			if GetRaidTargetIndex("target") == i then
				SetRaidTargetIcon("target", 0)
			else
				SetRaidTargetIcon("target", i)
			end
		end)
		f.marks[i] = b
	end

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

	-- What each icon is, for the hover tooltip. Obvious to whoever built the bar,
	-- not to a raider seeing it for the first time.
	local TIPS = {
		okanvil = "Okanvil",
		loot    = "Mini roll",
		prio    = "Loot priority",
		finder  = "Raid Finder",
		pug     = "PuG",
		upgrades = "Upgrades",
		notes   = "Notes",
		recruit = "Recruit",
		invite  = "Invite",
		ids     = "ID Finder",
		buffs   = "Raid check",
		farm    = "Farm",
		ready   = "Ready check",
		pull    = "Pull timer (right-click: cancel)",
	}

	-- Shortcut buttons: an icon each, built from the SHORTCUTS table.
	f.short = {}
	for _, sc in ipairs(SHORTCUTS) do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(BTN, BTN)

		-- the icon in the kit's octagon frame, like the nav's; the one call to
		-- action (pull) wears the gold frame, the rest the grey one
		W.DressFramedIcon(b, (sc.iconFn and sc.iconFn()) or sc.icon, BTN)
		W.SetFramedIconGold(b, sc.accent and true or false)
		local t = b.icon
		if not sc.accent then t:SetVertexColor(0.82, 0.82, 0.85, 1) end

		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(t)
		hl:SetTexture("Interface\\Buttons\\WHITE8X8")
		hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.25)

		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(_, button) sc.run(button) end)
		b:SetScript("OnEnter", function(self)
			t:SetVertexColor(1, 1, 1, 1)
			local tip = TIPS[sc.key]
			if tip then
				-- Always BELOW the bar, clear of its border: above (or on top of) the
				-- bar it covered the neighbouring icons you were about to click.
				GameTooltip:SetOwner(self, "ANCHOR_NONE")
				GameTooltip:ClearAllPoints()
				GameTooltip:SetPoint("TOP", self, "BOTTOM", 0, -(PAD + 3))
				GameTooltip:SetText(tip, 1, 0.82, 0)
				GameTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function()
			if not sc.accent then t:SetVertexColor(0.82, 0.82, 0.85, 1) end
			GameTooltip:Hide()
		end)

		f.short[sc.key] = b
	end

	f.lfg = buildLfg(f)
	f.xp = buildXp(f)

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
	if bar.xp then updateXp(bar.xp) end
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
-- Roster changes wait out combat (Okanvil:CombatSafe): the relayout walks the
-- guild roster for the prio gate. PLAYER_LOGIN is never in combat, so it is
-- unaffected.
ev:SetScript("OnEvent", Okanvil:CombatSafe("marksbar.roster", function(_, event)
	if event == "PLAYER_LOGIN" then
		build()
		MB:Refresh()

		-- No module page: the bar IS the feature, and its switches live in the host's
		-- Settings page under RAID TOOLS.
		return
	end
	MB:Refresh()
end))

-- The LFG slot. Its contents update on every queue event; the bar is only laid
-- out again when the slot comes or goes, and that waits out combat like the
-- roster relayout above.
-- The XP / reputation strip: a redraw per event, no relayout (it hangs off the
-- bar's edge, so the bar's width is all it needs).
local xpEv = CreateFrame("Frame")
xpEv:RegisterEvent("PLAYER_XP_UPDATE")
xpEv:RegisterEvent("PLAYER_LEVEL_UP")
xpEv:RegisterEvent("UPDATE_EXHAUSTION")
xpEv:RegisterEvent("PLAYER_UPDATE_RESTING")
xpEv:RegisterEvent("UPDATE_FACTION")
xpEv:RegisterEvent("PLAYER_ENTERING_WORLD")
xpEv:SetScript("OnEvent", function()
	if bar and bar.xp then updateXp(bar.xp) end
end)

local lfgEv = CreateFrame("Frame")
lfgEv:RegisterEvent("LFG_UPDATE")
lfgEv:RegisterEvent("LFG_QUEUE_STATUS_UPDATE")
lfgEv:RegisterEvent("LFG_PROPOSAL_SHOW")
lfgEv:RegisterEvent("LFG_PROPOSAL_FAILED")
lfgEv:RegisterEvent("LFG_PROPOSAL_SUCCEEDED")
lfgEv:RegisterEvent("LFG_PROPOSAL_UPDATE")
local lfgRelayout = Okanvil:CombatSafe("marksbar.lfg", function() MB:Refresh() end)
lfgEv:SetScript("OnEvent", function()
	if not bar then return end
	if (lfgWanted() and true or false) ~= (bar.lfgShown and true or false) then
		lfgRelayout()
	elseif bar.lfgShown then
		updateLfg(bar.lfg)
	end
end)

