-- ============================================================
-- Okanvil -- Raid Check (native core module).
-- "Is everyone actually ready?" -- who is missing a flask, food, or a raid buff,
-- at a glance, with one button to call it out in raid chat.
--
-- WHY THIS WORKS WITHOUT ADDON COMMS (the important bit):
-- UnitAura("raid7", i, "HELPFUL") reads the buffs of ANY raid member on 3.3.5a --
-- they do not need Okanvil, or any addon at all. So flask/food/buff checking is a
-- purely LOCAL read: instant, reliable, and it covers the pug who installed nothing.
-- WHAT THIS DELIBERATELY DOES NOT DO:
-- gems / enchants / durability. Those need NotifyInspect -- asynchronous, range
-- limited (CheckInteractDistance), and requiring a throttled queue -- a lot of
-- fragile machinery for very little gain.
--
-- 3.3.5a API: UnitAura, GetRaidRosterInfo, GetNumRaidMembers, GetSpellInfo,
-- SendChatMessage. No C_UnitAuras, no NotifyInspect used here.
-- ============================================================

local Okanvil = Okanvil
local RC = {}
Okanvil.RaidCheck = RC

-- NOTE: do NOT hoist `local W = Okanvil.W` to file scope. Every other module
-- resolves the widget layer at CALL time (see Logs.lua), because file-scope
-- upvalues freeze whatever was set when this file was parsed.

-- ------------------------------------------------------------
-- WHAT COUNTS AS A FLASK  (WotLK)
-- ------------------------------------------------------------
-- A raider is "flasked" if they have a FLASK, or -- equally valid in WotLK -- the
-- two-elixir combination (one Battle + one Guardian). So this is not a boolean on
-- one aura: it counts consumables. The game already stops you holding two battle
-- elixirs at once, so "2 elixirs" cannot be cheated by double-stacking one type.

local FLASKS = {
	[53760] = "Endless Rage",
	[53758] = "Stoneblood",
	[54212] = "Pure Mojo",
	[53755] = "Frost Wyrm",
	[53749] = "Distilled Wisdom",
	[53751] = "Mighty Restoration",
	[62380] = "Guru's Elixir",      -- battle+guardian in one; counts as a flask
}

-- Battle / Guardian elixirs.
local BATTLE_ELIXIRS = {
	[60340] = "Accuracy",
	[53746] = "Mighty Agility",
	[60341] = "Deadly Strikes",
	[60343] = "Mighty Strength",
	[60347] = "Mighty Thoughts",
	[60346] = "Lightning Speed",
	[53748] = "Mighty Strength",
	[28497] = "Major Agility",
}
local GUARDIAN_ELIXIRS = {
	[60344] = "Mighty Defense",
	[53764] = "Mighty Fortitude",
	[60345] = "Protection from Shadow",
	[53763] = "Protection from Magic",
	[39625] = "Major Fortitude",
}

-- ------------------------------------------------------------
-- WHAT COUNTS AS FOOD
-- Every food buff in the game surfaces as the SAME aura: "Well Fed". Rather than
-- cataloguing hundreds of foods, resolve that ONE name at runtime from a reference
-- spell id -- GetSpellInfo returns it already localized, so this works on any client
-- language.
-- ------------------------------------------------------------
local WELLFED_REF = { 57288, 33256, 25661, 65410 }
local wellFedName

local function WellFed()
	if wellFedName then return wellFedName end
	for i = 1, #WELLFED_REF do
		local n = GetSpellInfo(WELLFED_REF[i])
		if n and n ~= "" then wellFedName = n; return n end
	end
end

-- ------------------------------------------------------------
-- RAID BUFFS -- grouped, because any ONE of a group satisfies it.
-- Resolved to localized names via GetSpellInfo at first use, so a Horde/Alliance
-- or non-English client still matches (the user is Horde: Kings comes from a pally,
-- but the aura name is what we compare).
-- ------------------------------------------------------------
-- The FIRST id in each group is the one whose icon heads the column, so the
-- raid-wide ("Greater" / group) version leads: Greater Blessing of Kings, not the
-- single-target Blessing.
-- GROUPING RULE: several spell ids share a column ONLY when they are mutually
-- EXCLUSIVE -- i.e. you cannot benefit from both at once, so having either one is
-- the whole answer. Anything that STACKS gets its own column, because a raid can
-- and should have both.
--
--   Fortitude / Commanding Shout   do not stack -> one "Stamina" column
--   Arcane / Dalaran Brilliance    do not stack -> one "Int" column
--
-- Column ORDER matters too: the paladin blessings sit side by side as one block.
--
-- ALL RANKS ARE LISTED, not just the level-80 one. A buff aura carries the spell
-- id OF ITS RANK, so a warrior shouting an older rank, or a low-level alt's
-- Fortitude, would read as "missing" if only the max rank were listed.
-- COLUMNS ARE ORDERED BY THE CLASS THAT PROVIDES THEM: priest, druid, mage,
-- warrior, then the paladin blessings as one block. You buff by class, so you read
-- the grid by class -- a missing column tells you immediately who to poke.
--
-- Buffs that do not STACK still get separate columns when they come from DIFFERENT
-- classes (Fortitude vs Commanding Shout; Blessing of Might vs Battle Shout). You
-- can hold both; only the larger one applies. Merging them would light a single
-- cell and hide WHICH source you are relying on -- and with no priest in the raid,
-- Commanding Shout is the only stamina in the room.
local BUFF_GROUPS = {
	-- PRIEST
	{ label = "Stam",     ids = {
		48162, 48161, 25392, 25389, 21562, 21564, 10937, 10938, 2791, 1243, 1244, 1245,  -- PW: Fortitude (all ranks)
	} },
	-- DRUID
	{ label = "Mark",     ids = {
		48470, 48469, 26991, 26990, 21850, 21849, 9884, 9885, 8907, 6756, 5232, 5234, 1126,  -- Mark / Gift of the Wild
	} },
	-- MAGE
	{ label = "Int",      ids = {
		43002, 42995, 27126, 27127, 23028, 10156, 10157, 1459, 1460, 1461, 61316, 61024,     -- Arcane Brilliance / Intellect
	} },
	-- WARRIOR
	{ label = "Shout",    ids = { 47436, 2048, 25289, 11551, 11550, 11549, 6192, 5242, 6673 } },  -- Battle Shout (all ranks)
	{ label = "CmdShout", ids = { 47440, 469 } },                  -- Commanding Shout
	-- PALADIN -- the four blessings, kept adjacent as one block
	{ label = "Sanct",    ids = { 25899, 20911 } },                -- (Greater) Blessing of Sanctuary (tank)
	{ label = "Kings",    ids = { 25898, 20217 } },                -- (Greater) Blessing of Kings
	{ label = "Might",    ids = { 48934, 48932 } },                -- (Greater) Blessing of Might
	{ label = "Wisdom",   ids = { 48938, 48936 } },                -- (Greater) Blessing of Wisdom
	--
	-- NOT CHECKED: Abomination's Might. It is a passive TALENT an Unholy DK simply
	-- has -- nobody casts it, nobody forgets it, and it cannot be "fixed" mid-raid.
	-- A column for it would sit permanently grey whenever the roster has no Unholy
	-- DK, which is noise, not a finding. This grid only shows things a raider can
	-- actually do something about.
}

-- ------------------------------------------------------------
-- READY CHECK STATE
-- The toast fires ON the ready check, so the obvious thing to also show is who has
-- actually answered. READY_CHECK_CONFIRM arrives once per player as they click;
-- nobody who has not clicked yet appears, which is exactly the "waiting" state.
--   ReadyCheck-Waiting / -Ready / -NotReady are the stock game textures.
-- ------------------------------------------------------------
local READY_TEX = {
	waiting  = "Interface\\RaidFrame\\ReadyCheck-Waiting",
	ready    = "Interface\\RaidFrame\\ReadyCheck-Ready",
	notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}
local readyState   -- [playerName] = "ready" | "notready"; nil = still waiting
local readyActive  -- true while a ready check is running

local buffNames   -- [groupIndex] = { name = true, ... }

local function resolveBuffNames()
	if buffNames then return buffNames end
	buffNames = {}
	for gi, g in ipairs(BUFF_GROUPS) do
		buffNames[gi] = {}
		for _, id in ipairs(g.ids) do
			local n = GetSpellInfo(id)
			if n and n ~= "" then buffNames[gi][n] = true end
		end
	end
	return buffNames
end

-- ------------------------------------------------------------
-- SCAN
-- Returns an array of { name, class, flask, food, missing = {"Kings", ...} }
-- ------------------------------------------------------------
-- Scan whatever group we are in -- RAID, PARTY, or just yourself. Working solo
-- matters: it is the only way to test the check (and to sanity-check your own
-- consumables before the raid starts). GetRaidRosterInfo is empty outside a raid,
-- so the roster is built out of UNIT ids instead, exactly as Guild.lua does.
local function unitList()
	local units = {}
	local raidN  = GetNumRaidMembers() or 0
	local partyN = GetNumPartyMembers() or 0
	if raidN > 0 then
		-- subgroup (1..8) comes from the roster, not from the unit id -- needed to
		-- sort the grid by raid group.
		for i = 1, raidN do
			local _, _, subgroup = GetRaidRosterInfo(i)
			units[#units + 1] = { unit = "raid" .. i, group = subgroup or 0 }
		end
	elseif partyN > 0 then
		units[#units + 1] = { unit = "player" }
		for i = 1, partyN do units[#units + 1] = { unit = "party" .. i } end
	else
		units[#units + 1] = { unit = "player" }     -- solo: check yourself
	end
	return units
end

function RC:Scan()
	local out = {}
	local fed = WellFed()
	local bn  = resolveBuffNames()

	for _, entry in ipairs(unitList()) do
		local unit = entry.unit
		if UnitExists(unit) then
			local pname = UnitName(unit)
			local _, class = UnitClass(unit)
			local hasFlask, hasFood = false, false
			local hasGroup  = {}
			-- What the player ACTUALLY has, per column: its real icon and its own
			-- timer. A column's header icon is only a placeholder -- Blessing of Kings
			-- and GREATER Blessing of Kings are different textures AND different
			-- durations (10 min vs 30), so painting the group's first icon on every
			-- cell would hide the fact that someone is running the short one.
			local gIcon, gEnds, gDur = {}, {}, {}

			-- One pass over the unit's buffs. UnitAura returns nil at the first empty
			-- index, so break there rather than always looping to 40.
			local flasks = {}      -- every flask/elixir the player has, in aura order
			local foodEnds, foodDur, foodIcon
			for a = 1, 40 do
				-- slot 7 is `duration`, slot 8 is `expirationTime` (absolute GetTime()
				-- when the aura drops). We keep the expiry so the grid can show how
				-- long a flask has left, and shout when it is about to run out.
				-- A Cooldown frame needs BOTH the duration and the expiry: it draws the
				-- sweep from (expirationTime - duration) over `duration` seconds.
				local aname, _, aicon, _, _, dur, expires, _, _, _, spellId = UnitAura(unit, a, "HELPFUL")
				if not aname then break end
				if spellId then
					-- Any flask OR elixir counts as covered -- a plain yes/no.
					--
					-- Collect EVERY match rather than the first: two elixirs are two
					-- separate auras with their own icons and timers, and showing one of
					-- them silently hides the other. The cell stacks whatever it gets.
					if FLASKS[spellId] or BATTLE_ELIXIRS[spellId] or GUARDIAN_ELIXIRS[spellId] then
						hasFlask = true
						flasks[#flasks + 1] = { icon = aicon, ends = expires, dur = dur }
					end
				end
				if fed and aname == fed then
					hasFood = true
					foodEnds, foodDur, foodIcon = expires, dur, aicon
				end
				for gi = 1, #BUFF_GROUPS do
					if bn[gi][aname] then
						hasGroup[gi] = true
						-- keep the aura's OWN icon and timer, not the column's default
						gIcon[gi], gEnds[gi], gDur[gi] = aicon, expires, dur
					end
				end
			end
			local missing = {}
			for gi, g in ipairs(BUFF_GROUPS) do
				if not hasGroup[gi] then missing[#missing + 1] = g.label end
			end

			out[#out + 1] = {
				name    = pname,
				class   = class,
				online  = UnitIsConnected(unit) and true or false,
				dead    = UnitIsDeadOrGhost(unit) and true or false,
				flask     = hasFlask,
				flasks    = flasks,      -- { {icon,ends,dur}, ... } -- one per consumable
				food      = hasFood,
				foodEnds  = foodEnds,
				foodDur   = foodDur,
				foodIcon  = foodIcon,
				missing   = missing,
				has       = hasGroup,    -- [groupIndex] = true -- for the icon grid
				gIcon     = gIcon,       -- the aura's REAL icon (Kings vs Greater Kings)
				gEnds     = gEnds,       -- and its own expiry / duration, which differ
				gDur      = gDur,        -- between the single-target and greater versions
				group     = entry.group, -- raid subgroup 1..8 (nil in a party)
			}
		end
	end
	return out
end

-- Only the people who are actually a problem: offline and dead are excluded,
-- because "the corpse has no flask" is noise, not a finding.
function RC:Problems()
	local bad = {}
	for _, p in ipairs(self:Scan()) do
		if p.online and not p.dead and (not p.flask or not p.food) then
			bad[#bad + 1] = p
		end
	end
	return bad
end

-- ------------------------------------------------------------
-- ANNOUNCE -- one line per offender, in raid chat.
-- Capped so a 25-man with nobody buffed cannot spam 25 lines into chat.
-- ------------------------------------------------------------
local MAX_ANNOUNCE = 8

function RC:Announce()
	-- Pick the channel that actually exists. Announcing solo would just be talking
	-- to yourself, so that prints locally instead of hitting a chat channel.
	local raidN  = GetNumRaidMembers() or 0
	local partyN = GetNumPartyMembers() or 0
	local chan = (raidN > 0 and "RAID") or (partyN > 0 and "PARTY") or nil
	if not chan then
		Okanvil:Print("Raid Check: not in a group -- use |cff00ff00/okrc|r to check yourself.")
		return
	end

	local bad = self:Problems()

	if #bad == 0 then
		SendChatMessage("Raid Check: everyone is flasked and fed.", chan)
		return
	end

	SendChatMessage("Raid Check -- missing consumables:", chan)
	for i = 1, math.min(#bad, MAX_ANNOUNCE) do
		local p = bad[i]
		local lack = {}
		if not p.flask then lack[#lack + 1] = "flask" end
		if not p.food  then lack[#lack + 1] = "food" end
		SendChatMessage(("  %s -- no %s"):format(p.name, table.concat(lack, ", ")), chan)
	end
	if #bad > MAX_ANNOUNCE then
		SendChatMessage(("  ... and %d more"):format(#bad - MAX_ANNOUNCE), chan)
	end
end

-- ------------------------------------------------------------
-- UI
-- ------------------------------------------------------------
local function classHex(token)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	if c then return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
	return "|cffffd200"
end

local YES = "|cff7cfc8a+|r"     -- ok green
local NO  = "|cffff5555-|r"     -- missing

-- Under 10 minutes a buff counts as "about to run out": one that dies mid-fight is
-- as useless as none at all.
local EXPIRING = 600

-- Corner text is tiny, so keep it tiny: "58m", "9m", "45s". No ticking seconds
-- above a minute -- 25 rows of live-counting digits is noise nobody can read.
local function fmtLeft(secs)
	if secs >= 60 then return string.format("%dm", math.floor(secs / 60)) end
	return string.format("%ds", math.floor(secs))
end

-- Fallback for the food column, if the Well Fed spell lookup ever fails.
local ICON_FALLBACK = "Interface\\Icons\\INV_Misc_Food_15"

-- ------------------------------------------------------------
-- THE TOAST  --  an icon grid.
--
-- Nobody opens a panel to find out they forgot their flask, so this fires itself
-- on READY CHECK -- the one moment the raid is about to pull and a missing
-- consumable can still be fixed.
--
-- Layout:
--   [class bar][name .............][flask][food][buff][buff][buff][buff][buff]
-- One row per raider, one COLUMN per thing checked, each column headed by that
-- thing's real spell icon. A cell shows the icon lit when the player has it, and
-- dimmed-red when they do not -- so a bad column reads as a vertical red streak.
-- Alternating rows are tinted.
-- ------------------------------------------------------------
-- ROW_H is deliberately taller than ICON_S: the difference is the vertical gutter
-- between rows. With ROW_H == ICON_S the icons touch top-to-bottom and the grid
-- reads as one solid block of art.
local ICON_S    = 18
local ROW_GAP   = 6                  -- vertical breathing room between rows
local ROW_H     = ICON_S + ROW_GAP   -- 24
local NAME_W    = 110
local READY_S   = 14                 -- ready-check tick, sits left of the name
-- A raider holds either a flask (one icon) or two elixirs. Two slots is the most
-- that can ever be shown, which is why the flask column is double width.
local MAX_FLASK_ICONS = 2
-- Everything left of the icon grid: class bar + ready tick + name. Derived once,
-- so the three places that need to know where the columns start cannot drift.
local LEFT_W    = 7 + READY_S + 4 + NAME_W
local COL_GAP   = 8                  -- horizontal breathing room between columns
local COL_W     = ICON_S + COL_GAP
-- Every column is COL_W wide. The FLASK column is the one exception: it is DOUBLE
-- width, because it may hold two elixirs instead of one flask.
local function colWidth(col)
	if col and col.key == "flask" then return COL_W * 2 end
	return COL_W
end

-- Left edge of column i.
local function colX(cols, i)
	local x = 0
	for c = 1, i - 1 do x = x + colWidth(cols[c]) end
	return x
end

-- CENTRE of column i. Header icons, cells and the flask anchor all place themselves
-- against this one number, so they cannot drift apart.
local function colCentre(cols, i)
	return colX(cols, i) + colWidth(cols[i]) / 2
end
local PAD       = 10
local TOAST_LIFE = 30   -- seconds on screen; the DBM pull closes it sooner

-- Vertical rhythm of the toast head. FIRST_ROW_Y is DERIVED from HEAD_Y so the
-- header icons and the first row can never overlap, whatever ICON_S becomes.
local HEAD_Y      = -28              -- top of the column-icon strip
local HEAD_GAP    = 10               -- clear space under the header icons
local FIRST_ROW_Y = HEAD_Y - ICON_S - HEAD_GAP

-- The columns, in order. Icons are pulled from the SPELL, never guessed by path:
-- GetSpellInfo returns the texture the client actually ships, so these cannot
-- point at a missing file.
local COLUMNS
local function buildColumns()
	if COLUMNS then return COLUMNS end
	local function spellIcon(id, fallback)
		local _, _, icon = GetSpellInfo(id)
		return icon or fallback
	end
	-- These icons are the column HEADERS (and the fallback for an empty cell). A
	-- filled cell overrides them with the aura the player actually has.
	COLUMNS = {
		{ key = "flask", label = "Flask", icon = spellIcon(53760, "Interface\\Icons\\INV_Potion_137") },
		{ key = "food",  label = "Food",  icon = spellIcon(WELLFED_REF[1], ICON_FALLBACK) },
	}
	-- one column per raid-buff group, using the first resolvable spell's icon
	for gi, g in ipairs(BUFF_GROUPS) do
		local icon
		for _, id in ipairs(g.ids) do
			icon = select(3, GetSpellInfo(id))
			if icon then break end
		end
		COLUMNS[#COLUMNS + 1] = {
			key = "buff", group = gi, label = g.label,
			icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
		}
	end
	return COLUMNS
end

local toast

local function buildToast()
	if toast then return toast end
	local W = Okanvil.W
	local C = Okanvil.Colors
	local cols = buildColumns()

	-- Named on purpose: ESC-to-close works through UISpecialFrames, which holds
	-- GLOBAL FRAME NAMES -- an anonymous frame can never be closed with Escape.
	local f = CreateFrame("Frame", "Okanvil_RaidCheckToast", UIParent)
	Okanvil:Skin(f, "dark")
	Okanvil.Mod(f)
	tinsert(UISpecialFrames, "Okanvil_RaidCheckToast")

	f:SetFrameStrata("DIALOG")
	f:SetBackdropColor(0.05, 0.05, 0.06, 0.95)
	f:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(s) s:StartMoving() end)
	f:SetScript("OnDragStop", function(s)
		s:StopMovingOrSizing()
		local p, _, _, x, y = s:GetPoint(1)
		local d = Okanvil.db
		d.raidcheck = d.raidcheck or {}
		d.raidcheck.point, d.raidcheck.x, d.raidcheck.y = p, x, y
	end)

	local gridW = 0
	for i = 1, #cols do gridW = gridW + colWidth(cols[i]) end
	f:SetWidth(PAD * 2 + LEFT_W + gridW + 8)

	f.title = W.Text(f, "Raid Check", 15, "accent")
	f.title:SetPoint("TOPLEFT", PAD, -7)

	local close = W.Button(f, "X")
	close:SetSize(16, 15)
	close:SetPoint("TOPRIGHT", -5, -5)
	close:SetScript("OnClick", function() f:Hide() end)

	-- Column header. Each is a real button so it can carry a TOOLTIP -- an icon strip
	-- with no labels is a guessing game, and rotated text is not worth the trouble at
	-- this size. Hover a header to see what the column checks.
	f.heads = {}
	local x0 = PAD + LEFT_W
	for i, col in ipairs(cols) do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(ICON_S, ICON_S)
		b:SetPoint("TOPLEFT", x0 + colCentre(cols, i) - ICON_S / 2, HEAD_Y)

		local t = b:CreateTexture(nil, "OVERLAY")
		t:SetAllPoints()
		t:SetTexture(col.icon)
		t:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- crop the stock icon border

		b:SetScript("OnEnter", function(s)
			GameTooltip:SetOwner(s, "ANCHOR_TOP")
			GameTooltip:AddLine(col.label)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)

		f.heads[i] = b
	end

	f.rows = {}
	f:Hide()          -- built warm at login, but never shown until asked for
	toast = f
	return f
end

-- One row = class bar + name + a cell per column.
local function getRow(f, i)
	local row = f.rows[i]
	if row then return row end
	local W = Okanvil.W
	local cols = buildColumns()

	row = CreateFrame("Frame", nil, f)
	row:SetSize(f:GetWidth() - PAD * 2, ROW_H)

	-- Zebra striping. Both parities get a fill (not just the even ones) so the
	-- alternation actually reads -- a single 4% wash on every other row was too
	-- faint to separate anything.
	-- 3.3.5a has no SetColorTexture: a solid fill is WHITE8X8 + SetVertexColor
	row.back = row:CreateTexture(nil, "BACKGROUND")
	-- Inset the stripe by half the gutter top and bottom, so consecutive stripes do
	-- NOT touch -- that gap is what actually separates one raider from the next.
	row.back:SetPoint("TOPLEFT", 0, -ROW_GAP / 2)
	row.back:SetPoint("BOTTOMRIGHT", 0, ROW_GAP / 2)
	row.back:SetTexture("Interface\\Buttons\\WHITE8X8")
	if i % 2 == 0 then
		row.back:SetVertexColor(1, 1, 1, 0.06)
	else
		row.back:SetVertexColor(0, 0, 0, 0.25)
	end

	-- class-coloured bar down the left edge
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetSize(3, ICON_S)          -- matches the icon band, not the whole row
	row.bar:SetPoint("LEFT", row, "LEFT", 0, 0)

	-- ready-check state, immediately left of the name
	row.ready = row:CreateTexture(nil, "ARTWORK")
	row.ready:SetSize(READY_S, READY_S)
	row.ready:SetPoint("LEFT", row, "LEFT", 7, 0)

	row.name = W.Text(row, nil, 13)
	row.name:SetPoint("LEFT", row, "LEFT", 7 + READY_S + 4, 0)
	row.name:SetWidth(NAME_W)
	row.name:SetJustifyH("LEFT")

	row.cells    = {}
	row.times    = {}
	row.timeText = {}
	row.flaskExtra = {}   -- 2nd/3rd consumable, stacked beside the flask cell
	local x0 = LEFT_W
	for c = 1, #cols do
		local t = row:CreateTexture(nil, "ARTWORK")
		t:SetSize(ICON_S, ICON_S)
		t:SetTexture(cols[c].icon)
		t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		t:SetPoint("LEFT", row, "LEFT", x0 + colCentre(cols, c) - ICON_S / 2, 0)
		row.cells[c] = t

		-- The Cooldown draws only the radial SWEEP: its built-in numbers are switched
		-- OFF and the minutes are a small FontString in the icon's bottom-right corner,
		-- because the native countdown text is centred and far too big at this size.
		local cd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
		cd:SetAllPoints(t)
		cd:SetReverse(true)          -- sweep DRAINS as it runs out, rather than filling
		if cd.SetDrawEdge then cd:SetDrawEdge(false) end
		if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
		cd.noCooldownCount = true    -- and tell OmniCC to keep its hands off
		cd.noOCC = true
		cd:Hide()
		row.times[c] = cd

		local txt = row:CreateFontString(nil, "OVERLAY")
		txt:SetFont(Okanvil:Font(), 9, "OUTLINE")
		txt:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 2, -1)
		txt:SetJustifyH("RIGHT")
		row.timeText[c] = txt
	end

	-- An invisible anchor pinned to the CENTRE of the flask column. Icons position
	-- themselves against it, so the set stays centred however many there are.
	local anchor = CreateFrame("Frame", nil, row)
	anchor:SetSize(1, ROW_H)
	anchor:SetPoint("LEFT", row, "LEFT", x0 + colCentre(cols, 1), 0)
	row.flaskAnchor = anchor

	-- Extra consumable slots: two elixirs are two auras, so the flask column must be
	-- able to draw more than one icon. Same size as every other icon in the grid --
	-- a shrunken icon reads as a different KIND of thing, which it is not.
	for k = 2, MAX_FLASK_ICONS do
		local x = row:CreateTexture(nil, "OVERLAY")
		x:SetSize(ICON_S, ICON_S)
		x:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		x:Hide()
		row.flaskExtra[k] = x
	end

	f.rows[i] = row
	return row
end

-- ------------------------------------------------------------
-- WHO SEES THE TOAST
--
-- READY_CHECK fires on EVERY raid member's client, so no addon comms are needed to
-- "notify the officers" -- the event is already there for all of them. What is
-- needed is a filter: the check is an officer's tool, so by default only the raid
-- LEADER and ASSISTS get the popup -- a normal raider should not be nagged about
-- the other 24 people's flasks. Both switches live on the module's settings page.
--
-- ------------------------------------------------------------
local function isOfficer()
	if (IsRaidLeader and IsRaidLeader()) then return true end
	if (IsRaidOfficer and IsRaidOfficer()) then return true end
	if (GetNumRaidMembers() or 0) == 0 and (IsPartyLeader and IsPartyLeader()) then return true end
	return false
end

function RC:ToastEnabled()
	local d = (Okanvil.db and Okanvil.db.raidcheck) or {}
	if d.onReadyCheck == false then return false end     -- the one real preference
	-- Officer-only is NOT a preference: being leader/assist is a fact about the
	-- group, not a taste. A plain raider has no use for the other 24 people's
	-- flasks, so the rule is fixed rather than offered as a checkbox.
	return isOfficer()
end

-- ------------------------------------------------------------
-- SORTING
-- "group" is the default because that is how a raid leader thinks -- you fix a
-- whole group's buffs at once, and a paladin buffs by group. Inside a group the
-- order is by class then name, so the same person never jumps around between
-- refreshes (an unstable sort on a live-updating grid is maddening to read).
-- ------------------------------------------------------------
local SORTS = { "group", "class", "name" }
RC.SORTS = SORTS      -- the Settings page builds its dropdown from this

-- Class order for the grid: MELEE first, then hybrids, then the pure casters.
-- Alphabetical would scatter them (Deathknight, Druid, Hunter, Mage...) and the
-- casters' empty Might column would appear as gaps sprinkled down the grid rather
-- than as one obvious block. Grouped like this, a caster with no Might reads as
-- "casters do not take Might", not as "this person is missing a buff".
local CLASS_ORDER = {
	DEATHKNIGHT = 1,
	WARRIOR     = 2,
	ROGUE       = 3,
	DRUID       = 4,
	PALADIN     = 5,
	SHAMAN      = 6,
	HUNTER      = 7,
	PRIEST      = 8,
	WARLOCK     = 9,
	MAGE        = 10,
}

local function sortList(list, mode)
	local function byName(a, b) return (a.name or "") < (b.name or "") end
	local function byClass(a, b)
		local ca = CLASS_ORDER[a.class or ""] or 99
		local cb = CLASS_ORDER[b.class or ""] or 99
		if ca ~= cb then return ca < cb end
		return byName(a, b)
	end

	if mode == "name" then
		table.sort(list, byName)
	elseif mode == "class" then
		table.sort(list, byClass)
	else   -- "group"
		table.sort(list, function(a, b)
			local ga, gb = a.group or 99, b.group or 99
			if ga ~= gb then return ga < gb end
			return byClass(a, b)
		end)
	end
	return list
end

-- Redraw the grid in place. Split out from ShowToast so a live UNIT_AURA can
-- refresh the open toast without re-showing it (and without resetting the fade).
function RC:RenderToast()
	local f = buildToast()
	local cols = buildColumns()

	for _, r in ipairs(f.rows) do r:Hide() end

	local d        = Okanvil.db.raidcheck or {}
	local sortMode = d.sort or "group"
	local showNums = d.hideNumbers ~= true      -- numbers on by default
	local showGrey = d.hideMissing ~= true      -- grey "missing" icons on by default
	local list     = sortList(self:Scan(), sortMode)
	local y = FIRST_ROW_Y
	local shown = 0

	for _, p in ipairs(list) do
		-- A corpse with no flask is noise, not a finding.
		if p.online and not p.dead then
			shown = shown + 1
			local row = getRow(f, shown)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", PAD, y)

			local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
			row.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
			if cc then row.bar:SetVertexColor(cc.r, cc.g, cc.b, 1)
			else row.bar:SetVertexColor(0.6, 0.6, 0.6, 1) end

			-- When sorted by group, prefix the group number -- without it you cannot
			-- see where one group ends and the next begins.
			local label = classHex(p.class) .. p.name .. "|r"
			if sortMode == "group" and p.group then
				label = "|cff5e6166" .. p.group .. "|r " .. label
			end
			row.name:SetText(label)

			-- ready-check state: green tick / red cross / hourglass while waiting.
			-- Outside a ready check there is nothing to say, so the slot is empty.
			if readyActive then
				local st = readyState and readyState[p.name]
				row.ready:SetTexture(READY_TEX[st or "waiting"])
				row.ready:Show()
			else
				row.ready:Hide()
			end

			for c, col in ipairs(cols) do
				local ok, ends, dur, icon

				if col.key == "flask" then
					-- A flask is one aura; two elixirs are two. Take the first one for the
					-- cell itself and let the extras stack beside it (see below), rather
					-- than silently showing one and hiding the other.
					local first = (p.flasks or {})[1]
					ok = p.flask
					if first then ends, dur, icon = first.ends, first.dur, first.icon end
				elseif col.key == "food" then
					ok, ends, dur, icon = p.food, p.foodEnds, p.foodDur, p.foodIcon
				else
					local gi = col.group
					ok = p.has and p.has[gi]
					ends, dur = p.gEnds and p.gEnds[gi], p.gDur and p.gDur[gi]
					-- The icon the player ACTUALLY has. Blessing of Kings and GREATER
					-- Blessing of Kings are different textures and different durations
					-- (10 min vs 30) -- painting the column's header icon on the cell
					-- would quietly hide that someone is on the short one.
					icon = p.gIcon and p.gIcon[gi]
				end

				local t = row.cells[c]
				t:SetTexture(icon or col.icon)   -- fall back to the column's own icon

				-- Sweep + corner minutes, on every column. Raid buffs run out too, and a
				-- blessing about to drop is the single most useful thing on this grid.
				local cd, txt = row.times[c], row.timeText[c]
				local left = (ok and ends) and (ends - GetTime()) or nil

				-- The flask cell's texture gets re-anchored below, so the sweep and the
				-- corner text have to follow it every time rather than once at build.
				if cd then cd:SetAllPoints(t) end
				if txt then
					txt:ClearAllPoints()
					txt:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 2, -1)
				end

				if cd then
					if left and left > 0 and dur and dur > 0 then
						cd:SetCooldown(ends - dur, dur)
						cd:Show()
					else
						cd:Hide()          -- no buff, or an aura the server gave no timer
					end
				end

				-- The corner minutes are optional: with them off you still get the sweep,
				-- which is the cleaner read at a glance.
				if txt then
					if showNums and left and left > 0 then
						txt:SetText(fmtLeft(left))
						-- Red under 10 minutes -- a buff that dies mid-fight is as good
						-- as no buff at all.
						if left < EXPIRING then txt:SetTextColor(1, 0.35, 0.35)
						else txt:SetTextColor(0.45, 0.95, 0.5) end
						txt:Show()
					else
						txt:Hide()
					end
				end

				if ok then
					t:SetVertexColor(1, 1, 1, 1)              -- full colour: they have it
					t:SetDesaturated(nil)                     -- 3.3.5a wants nil here, not false
					t:Show()
				elseif showGrey then
					-- Missing, greyed out: desaturated and dim, so you can still tell WHICH
					-- buff is absent.
					t:SetDesaturated(true)
					t:SetVertexColor(0.35, 0.35, 0.35, 0.55)
					t:Show()
				else
					-- Missing, hidden entirely: a much sparser grid where only what people
					-- actually HAVE is drawn, and a gap is the absence.
					t:Hide()
				end

				-- The flask column holds one icon (a flask) or two (elixirs). The set is
				-- centred in the column: a lone flask sits dead centre, and two elixirs
				-- straddle that same centre. Every icon is placed against the column's
				-- centre anchor, so none of them depends on where another one landed.
				if col.key == "flask" then
					local list = p.flasks or {}
					local n    = math.max(1, math.min(#list, MAX_FLASK_ICONS))
					local step = ICON_S + 2
					local first = -step * (n - 1) / 2      -- centre of the first icon

					t:ClearAllPoints()
					t:SetPoint("CENTER", row.flaskAnchor, "CENTER", first, 0)

					for k = 2, MAX_FLASK_ICONS do
						local x = row.flaskExtra[k]
						local e = list[k]
						if e then
							x:SetTexture(e.icon or col.icon)
							x:SetVertexColor(1, 1, 1, 1)
							x:SetDesaturated(nil)
							x:ClearAllPoints()
							x:SetPoint("CENTER", row.flaskAnchor, "CENTER", first + (k - 1) * step, 0)
							x:Show()
						else
							x:Hide()
						end
					end
				end
			end

			row:Show()
			y = y - ROW_H
		end
	end

	f:SetHeight(-y + 8)
	return f
end

-- Live-apply the size slider without reopening anything.
function RC:SetToastScale(pct)
	if toast then toast:SetScale((pct or 100) / 100) end
	if toast and not toast:IsShown() then self:ShowToast(true) end
end

-- `manual` = opened by hand (the Settings button), not by a ready check. Stale
-- ready ticks from the last pull would be a lie, so they are cleared.
function RC:ShowToast(manual)
	if manual then readyActive = false end
	local f = self:RenderToast()

	local d = (Okanvil.db and Okanvil.db.raidcheck) or {}
	f:SetScale((d.scale or 100) / 100)
	f:ClearAllPoints()
	if d.point then
		f:SetPoint(d.point, UIParent, d.point, d.x or 0, d.y or 0)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 260, 100)
	end
	f:Show()

	-- Auto-close after TOAST_LIFE. The other way it goes away is the DBM pull --
	-- Core's DBM_Pull hook calls Okanvil:CloseAll(), which calls HideToast() below.
	-- Both are hard hides; there is no fade (a half-faded grid is just unreadable).
	if Okanvil.Comms and Okanvil.Comms.After then
		f._token = (f._token or 0) + 1
		local mine = f._token
		Okanvil.Comms.After(TOAST_LIFE, function()
			if f._token == mine and f:IsShown() then f:Hide() end
		end)
	end
end

function RC:IsToastShown()
	return toast and toast:IsShown() and true or false
end

function RC:HideToast()
	if toast then
		toast._token = (toast._token or 0) + 1   -- invalidate any pending auto-close
		toast:Hide()
	end
end


-- ------------------------------------------------------------
-- /okrc -- manual trigger + a plain-text dump for debugging.
--   /okrc         -> show the toast
--   /okrc list    -> print every raider to YOUR chat frame
--   /okrc say     -> announce the offenders to raid chat
-- ------------------------------------------------------------
SLASH_OKANVILRC1 = "/okrc"
SlashCmdList["OKANVILRC"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

	if msg == "say" or msg == "announce" then
		RC:Announce()
		return
	end

	-- A MANUAL check is not a ready check: stale ticks from the last pull would be
	-- a lie. Only the READY_CHECK event turns the ready column on.
	readyActive = false

	-- /okrc aura -- dump YOUR raw buffs: spell id, name, and whether Raid Check
	-- recognises each one. This is the only way to tell "the icon logic is broken"
	-- apart from "that flask's spell id is not in the table".
	if msg == "aura" then
		Okanvil:Print("Your buffs (spellId -- name -- recognised as):")
		for a = 1, 40 do
			local aname, _, aicon, _, _, _, _, _, _, _, spellId = UnitAura("player", a, "HELPFUL")
			if not aname then break end
			local tag = ""
			if spellId and FLASKS[spellId] then tag = "|cff7cfc8aFLASK|r"
			elseif spellId and BATTLE_ELIXIRS[spellId] then tag = "|cff7cfc8aBATTLE ELIXIR|r"
			elseif spellId and GUARDIAN_ELIXIRS[spellId] then tag = "|cff7cfc8aGUARDIAN ELIXIR|r"
			elseif WellFed() and aname == WellFed() then tag = "|cff7cfc8aFOOD|r"
			end
			if tag ~= "" then
				Okanvil:Print(("  |cffffd200%s|r  %s  -> %s  (icon: %s)")
					:format(tostring(spellId), aname, tag, tostring(aicon)))
			end
		end
		Okanvil:Print("If your flask is NOT listed above, its spell id is missing from the table.")
		return
	end

	if msg == "list" then
		local list = RC:Scan()
		local raidN, partyN = GetNumRaidMembers() or 0, GetNumPartyMembers() or 0
		local where = (raidN > 0 and ("raid, %d"):format(raidN))
			or (partyN > 0 and ("party, %d"):format(partyN + 1))
			or "solo"
		if not WellFed() then
			Okanvil:Print("|cffff5555Warning:|r 'Well Fed' did not resolve -- food will always read missing.")
		end
		Okanvil:Print(("Raid Check -- %s"):format(where))
		for _, p in ipairs(list) do
			local bits = {}
			bits[#bits + 1] = p.flask and "|cff7cfc8aflask|r" or "|cffff5555NO FLASK|r"
			bits[#bits + 1] = p.food  and "|cff7cfc8afood|r"  or "|cffff5555NO FOOD|r"
			if #p.missing > 0 then
				bits[#bits + 1] = "|cffffd200missing:|r " .. table.concat(p.missing, ",")
			end
			Okanvil:Print(("  %s%s|r  %s"):format(classHex(p.class), p.name, table.concat(bits, "  ")))
		end
		return
	end

	RC:ShowToast()
end

-- ------------------------------------------------------------
-- Events -- the toast fires on READY CHECK, which is the one moment the raid is
-- about to pull and a missing flask can still be fixed.
-- ------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("READY_CHECK")
ev:RegisterEvent("PLAYER_LOGIN")

-- The open toast must stay LIVE: someone eats, the buff lands, the icon has to go
-- from grey to lit without you reopening anything. UNIT_AURA fires constantly in a
-- raid (every HoT tick, every unit), so coalesce into at most one redraw per second.
local auraPending
ev:RegisterEvent("UNIT_AURA")
ev:RegisterEvent("READY_CHECK_CONFIRM")    -- one per player, as they answer
ev:RegisterEvent("READY_CHECK_FINISHED")

ev:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "READY_CHECK_CONFIRM" then
		-- arg1 = unit (or name), arg2 = true if READY. Resolve to a plain name so it
		-- matches what Scan() keys on.
		local who = (UnitExists(arg1) and UnitName(arg1)) or arg1
		if who then
			readyState = readyState or {}
			readyState[who] = arg2 and "ready" or "notready"
			if toast and toast:IsShown() then RC:RenderToast() end
		end
		return
	end

	if event == "READY_CHECK_FINISHED" then
		-- Keep the answers on screen -- the toast is still up and the whole point is
		-- to see who never replied. Cleared when the NEXT check starts.
		return
	end

	if event == "PLAYER_LOGIN" then
		-- Warm the frame + the spell-icon lookups NOW, while nothing is happening.
		-- Otherwise the very first toast pays for building every frame and texture
		-- mid-ready-check, which is exactly when it must not stutter.
		-- NOTE: this registers NO module page. Raid Check is not a nav entry -- three
		-- switches never justified a Dashboard with an empty footer, and the grid
		-- itself IS the toast. Its settings live in the host's Settings page.
		buildToast()
		return
	end

	if event == "UNIT_AURA" then
		if not (toast and toast:IsShown()) then return end
		if auraPending then return end
		auraPending = true
		Okanvil.Comms.After(0.5, function()
			auraPending = nil
			if toast and toast:IsShown() then RC:RenderToast() end
		end)
		return
	end

	if event == "READY_CHECK" then
		-- New check -> wipe last check's answers, or everyone would show as already
		-- ready from the previous pull.
		readyState  = {}
		readyActive = true
		if not RC:ToastEnabled() then return end
		-- Show it IMMEDIATELY -- do not delay. UnitAura is a local read with no server
		-- round-trip, so everyone's buffs are already known the moment READY_CHECK fires.
		RC:ShowToast()
	end
end)
