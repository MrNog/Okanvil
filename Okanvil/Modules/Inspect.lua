-- ============================================================
-- Okanvil -- Inspect (native core module, no page).
-- Reads every group member's talent spec via NotifyInspect and caches it, so
-- other modules (loot roll eligibility, raid check, PuG role counts) can ask
-- "what does this player actually play?" without each one re-scanning.
--
-- Always-on service: it has no UI and never registers a plugin page. It only
-- scans when something asks it to.
-- ============================================================

local Okanvil = Okanvil
local M = {}
Okanvil.Inspect = M

-- ------------------------------------------------------------
-- Saved variables
--
-- Account-wide on purpose: a raider's spec is a property of THAT CHARACTER, not
-- of whoever inspected them, so an officer's alt should see the same answer the
-- main already gathered. Entries carry `at` so stale ones can be purged -- a spec
-- from three weeks ago is a guess, not data.
-- ------------------------------------------------------------
local STALE_DAYS = 7

local function db()
	Okanvil_DB = Okanvil_DB or {}
	Okanvil_DB.inspect = Okanvil_DB.inspect or {}
	local d = Okanvil_DB.inspect
	if type(d.specs) ~= "table" then d.specs = {} end   -- [name] = {spec=,class=,role=,at=}
	if d.staleDays == nil then d.staleDays = STALE_DAYS end
	return d
end

local function stripRealm(name)
	return name and (name:gsub("%-.*$", "")) or name
end

-- ------------------------------------------------------------
-- Talent tab -> spec name, per class.
--
-- 3.3.5a has no GetSpecialization: the only signal is which of the three talent
-- tabs holds the most points. Tab ORDER is fixed by the client, so indexing by
-- position is safe and locale-proof -- reading the tab's NAME is not, because a
-- non-enUS client returns it translated.
-- ------------------------------------------------------------
local TREES = {
	DEATHKNIGHT = { "Blood",         "Frost",        "Unholy"      },
	DRUID       = { "Balance",       "Feral",        "Restoration" },
	HUNTER      = { "Beast Mastery", "Marksmanship", "Survival"    },
	MAGE        = { "Arcane",        "Fire",         "Frost"       },
	PALADIN     = { "Holy",          "Protection",   "Retribution" },
	PRIEST      = { "Discipline",    "Holy",         "Shadow"      },
	ROGUE       = { "Assassination", "Combat",       "Subtlety"    },
	SHAMAN      = { "Elemental",     "Enhancement",  "Restoration" },
	WARLOCK     = { "Affliction",    "Demonology",   "Destruction" },
	WARRIOR     = { "Arms",          "Fury",         "Protection"  },
}

-- Spec -> role. Keyed by the ENGLISH spec names above, so it is locale-proof.
-- Feral is deliberately absent: it is resolved by talent, not by tab (below).
local ROLES = {
	DEATHKNIGHT = { Blood = "tank",   Frost = "dps",    Unholy = "dps"     },
	DRUID       = { Balance = "dps",  Restoration = "healer"               },
	PALADIN     = { Holy = "healer",  Protection = "tank", Retribution = "dps" },
	PRIEST      = { Discipline = "healer", Holy = "healer", Shadow = "dps" },
	SHAMAN      = { Elemental = "dps", Enhancement = "dps", Restoration = "healer" },
	WARRIOR     = { Arms = "dps",     Fury = "dps",     Protection = "tank" },
	-- pure DPS classes: every tab is dps, so no map is needed
	HUNTER = {}, MAGE = {}, ROGUE = {}, WARLOCK = {},
}

-- Read the spec out of the INSPECT CACHE. Every talent call takes the inspect
-- flag `true` -- without it the API answers about YOUR OWN talents and every
-- player in the raid comes back as your spec.
local function readSpec(unit)
	local _, class = UnitClass(unit)
	if not class then return nil end

	local bestPts, bestIdx = -1, 0
	for i = 1, 3 do
		local _, _, pts = GetTalentTabInfo(i, true)
		if pts and pts > bestPts then bestPts, bestIdx = pts, i end
	end
	-- A fresh character with no points spent has no spec to report. Returning
	-- "Blood" for every talentless alt would poison the cache, so say nothing.
	if bestIdx == 0 or bestPts <= 0 then return nil, class end

	local spec = (TREES[class] and TREES[class][bestIdx]) or ("Tree " .. bestIdx)

	-- Feral druid: the tab cannot tell bear from cat, and the difference decides
	-- both loot eligibility and whether the raid has a tank. "Protector of the
	-- Pack" (Feral tab, talent 22) is tank-only, so any point in it means bear.
	if class == "DRUID" and bestIdx == 2 then
		local _, _, _, _, pts = GetTalentInfo(2, 22, true)
		spec = (pts and pts > 0) and "Feral (Bear)" or "Feral (Cat)"
	end

	local role
	if spec == "Feral (Bear)" then
		role = "tank"
	elseif spec == "Feral (Cat)" then
		role = "dps"
	else
		local map = ROLES[class]
		role = (map and map[spec]) or "dps"
	end

	return spec, class, role
end

-- ------------------------------------------------------------
-- GEAR: gearscore, average item level, and how much of it is PvP gear.
--
-- Read in the SAME inspect window as the spec, so it costs no extra request --
-- the unit's inventory is already in the client's cache by the time
-- INSPECT_TALENT_READY fires.
--
-- Why PvP pieces are counted: an applicant whispering "5.8k gs" is self-reported
-- and arena gear inflates the number badly. "5.8k, 4 PvP pieces" is the honest
-- version of the same claim, and it is the question a pug lead actually has.
-- ------------------------------------------------------------

-- The inventory slots worth scoring, and what to call each one when it turns out
-- to be PvP gear. 4 (shirt) and 19 (tabard) carry no stats, so they are skipped.
local GEAR_SLOTS = {
	{  1, "Head"     }, {  2, "Neck"    }, {  3, "Shoulder" }, {  5, "Chest"  },
	{  6, "Waist"    }, {  7, "Legs"    }, {  8, "Feet"     }, {  9, "Wrist"  },
	{ 10, "Hands"    }, { 11, "Ring 1"  }, { 12, "Ring 2"   }, { 13, "Trinket 1" },
	{ 14, "Trinket 2"}, { 15, "Back"    }, { 16, "Main Hand"}, { 17, "Off Hand" },
	{ 18, "Ranged"   },
}

-- Resilience is the giveaway: no PvE item in 3.3.5a carries it, and every piece of
-- arena/honor gear does. Matching the tooltip line is more reliable than keeping a
-- list of item ids, but it IS locale-dependent -- ITEM_MOD_RESILIENCE_RATING is the
-- client's own localized string, so we match against that rather than "Resilience".
local resilPattern
local function resilienceMatcher()
	if resilPattern ~= nil then return resilPattern end
	local s = _G.ITEM_MOD_RESILIENCE_RATING or "Resilience Rating"
	-- The global is a format string ("+%s Resilience Rating"); keep the literal tail.
	s = s:gsub("%%[sd]", ""):gsub("^%+%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then s = "Resilience" end
	resilPattern = Okanvil.U and Okanvil.U.escPattern and Okanvil.U.escPattern(s) or s
	return resilPattern
end

local gearTip
local function isPvPItem(link)
	if not link then return false end
	if not gearTip then
		gearTip = CreateFrame("GameTooltip", "OkanvilInspectGearTip", nil, "GameTooltipTemplate")
		gearTip:SetOwner(UIParent, "ANCHOR_NONE")
	end
	gearTip:ClearLines()
	gearTip:SetOwner(UIParent, "ANCHOR_NONE")
	local ok = pcall(gearTip.SetHyperlink, gearTip, link)
	if not ok then return false end
	local pat = resilienceMatcher()
	for i = 2, 20 do
		local fs = _G["OkanvilInspectGearTipTextLeft" .. i]
		local t = fs and fs:GetText()
		if t and t:find(pat) then return true end
	end
	return false
end

-- gs, avgIlvl, pvpCount, pvpSlots  (pvpSlots = { "Hands", "Legs" })
local function readGear(unit)
	local gs, avg

	-- Prefer an installed GearScore addon so our number matches what everyone else
	-- in the raid sees -- a second opinion that disagrees is worse than none.
	if GearScore_GetScore then
		local name = UnitName(unit)
		local okCall, a, b = pcall(GearScore_GetScore, name, unit)
		if okCall and a and a > 0 then gs, avg = a, b end
	end

	local ilvlSum, ilvlCount, pvpCount = 0, 0, 0
	local pvpSlots = {}
	for _, entry in ipairs(GEAR_SLOTS) do
		local slot, slotName = entry[1], entry[2]
		local link = GetInventoryItemLink(unit, slot)
		if link then
			local _, _, _, ilvl = GetItemInfo(link)
			if ilvl and ilvl > 0 then
				ilvlSum = ilvlSum + ilvl
				ilvlCount = ilvlCount + 1
			end
			if isPvPItem(link) then
				pvpCount = pvpCount + 1
				pvpSlots[#pvpSlots + 1] = slotName
			end
		end
	end

	-- No GearScore addon installed: average item level is the honest fallback. It is
	-- NOT a gearscore and must not be shown as one, so it is returned separately.
	if not avg and ilvlCount > 0 then avg = math.floor(ilvlSum / ilvlCount) end

	return gs, avg, pvpCount, pvpSlots
end

-- ------------------------------------------------------------
-- The scan queue.
--
-- The queue holds player NAMES, never unit tokens. A raid reshuffles mid-scan
-- (someone leaves, groups get rearranged) and "raid17" then points at a
-- different person than when it was queued -- which silently files one player's
-- spec under another's name. Names are resolved to a unit at FIRE time instead.
-- ------------------------------------------------------------
local queue    = {}      -- names still to inspect
local curName  = nil     -- who is in flight right now (nil = idle)
local curUnit  = nil
local waited   = 0       -- seconds the in-flight request has been outstanding
local total, done = 0, 0
local active   = false
local onDone   = nil

-- The server silently drops inspect requests for players who are out of range or
-- zoning. Without a timeout the whole queue stalls on one missing answer.
local TIMEOUT = 3.0

local function progress()
	if M.onProgress then
		local ok, err = pcall(M.onProgress, done, total, curName)
		if not ok and Okanvil.Err then Okanvil:Err("Inspect.onProgress", err) end
	end
end

local function unitFor(name)
	local raidN = GetNumRaidMembers() or 0
	if raidN > 0 then
		for i = 1, raidN do
			if stripRealm(UnitName("raid" .. i)) == name then return "raid" .. i end
		end
		return nil
	end
	if stripRealm(UnitName("player")) == name then return "player" end
	local partyN = GetNumPartyMembers() or 0
	for i = 1, partyN do
		if stripRealm(UnitName("party" .. i)) == name then return "party" .. i end
	end
	return nil
end

-- Merge, never replace: a scan that read the spec but whose gear came back empty
-- (inventory not cached yet) must not wipe a good gearscore from a previous scan.
local function store(name, fields)
	local d = db().specs
	local e = d[name] or {}
	for k, v in pairs(fields) do
		if v ~= nil then e[k] = v end
	end
	e.at = time()
	d[name] = e
end

local finish, fireNext

-- Fire the next request immediately, skipping anyone who has gone offline or
-- left. A skip costs nothing -- only a player we actually ask for can time out.
function fireNext()
	curName, curUnit, waited = nil, nil, 0

	while #queue > 0 do
		local name = table.remove(queue, 1)
		local unit = unitFor(name)
		if unit and UnitIsConnected(unit) then
			-- You cannot inspect yourself: the inspect cache is never populated
			-- for your own unit. Read your live talents directly instead.
			if unit == "player" then
				local _, class = UnitClass("player")
				local bestPts, bestIdx = -1, 0
				for i = 1, 3 do
					local _, _, pts = GetTalentTabInfo(i)
					if pts and pts > bestPts then bestPts, bestIdx = pts, i end
				end
				if bestIdx > 0 and bestPts > 0 and class then
					local spec = (TREES[class] and TREES[class][bestIdx]) or ("Tree " .. bestIdx)
					if class == "DRUID" and bestIdx == 2 then
						local _, _, _, _, pts = GetTalentInfo(2, 22)
						spec = (pts and pts > 0) and "Feral (Bear)" or "Feral (Cat)"
					end
					local role
					if spec == "Feral (Bear)" then role = "tank"
					elseif spec == "Feral (Cat)" then role = "dps"
					else role = (ROLES[class] and ROLES[class][spec]) or "dps" end
					local gs, avg, pvp, pvpSlots = readGear("player")
					store(name, { spec = spec, class = class, role = role,
						gs = gs, ilvl = avg, pvp = pvp, pvpSlots = pvpSlots })
				end
				done = done + 1
				progress()
			else
				curName, curUnit = name, unit
				progress()
				NotifyInspect(unit)
				return            -- wait for INSPECT_TALENT_READY, or the timeout
			end
		else
			done = done + 1       -- gone: skip without burning a timeout
			progress()
		end
	end

	finish()
end

function finish()
	active, curName, curUnit = false, nil, nil
	progress()
	if onDone then
		local cb = onDone
		onDone = nil
		local ok, err = pcall(cb, done, total)
		if not ok and Okanvil.Err then Okanvil:Err("Inspect.onDone", err) end
	end
end

-- ------------------------------------------------------------
-- Events
--
-- The next request fires from INSIDE the ready handler, so the chain runs as
-- fast as the server answers instead of on a fixed timer. A 25-man scan lands in
-- a couple of seconds rather than the ~25s a 1s-per-player timer would take.
-- ------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("INSPECT_TALENT_READY")
ev:SetScript("OnEvent", function()
	-- 3.3.5a fires this with no GUID argument, so the only way to know who it is
	-- about is that we asked for exactly one player and are waiting on them.
	if not (active and curUnit) then return end

	-- Confirm the unit still holds the player we asked about. If the roster moved
	-- under us between request and answer, the cache now describes someone else --
	-- storing it would file the wrong spec under curName.
	if stripRealm(UnitName(curUnit)) == curName then
		local spec, class, role = readSpec(curUnit)
		-- Gear is read even when the talents came back empty: the two are cached
		-- separately by the client, and a player with no spec still has a gearscore
		-- worth knowing.
		local gs, avg, pvp, pvpSlots = readGear(curUnit)
		if (spec and class) or gs or avg then
			store(curName, { spec = spec, class = class, role = role,
				gs = gs, ilvl = avg, pvp = pvp, pvpSlots = pvpSlots })
		end
	end

	done = done + 1
	fireNext()
end)

-- Rescue ticker. It only accumulates while a request is genuinely in flight, so
-- it costs nothing between scans and nothing at all when idle.
local tick = CreateFrame("Frame")
tick:SetScript("OnUpdate", function(_, elapsed)
	if not (active and curUnit) then return end
	waited = waited + elapsed
	if waited < TIMEOUT then return end
	done = done + 1
	fireNext()
end)

-- ------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------

-- Cached spec for a player: spec, class, role, age-in-seconds. Nil when unknown.
function M.Get(name)
	name = stripRealm(name)
	local e = name and db().specs[name]
	if not e then return nil end
	return e.spec, e.class, e.role, (time() - (e.at or 0))
end

function M.SpecOf(name)  local s = M.Get(name); return s end
function M.RoleOf(name)  local _, _, r = M.Get(name); return r end

-- The whole cached row, for a caller that wants several fields at once (the PuG
-- applicant list wants gs + pvp + spec together). Never hand out the stored table
-- itself -- a caller that edited it would silently corrupt the cache.
function M.Info(name)
	local e = name and db().specs[stripRealm(name)]
	if not e then return nil end
	return {
		name  = stripRealm(name),
		spec  = e.spec,  class = e.class, role = e.role,
		gs    = e.gs,    ilvl  = e.ilvl,
		pvp   = e.pvp or 0,
		pvpSlots = e.pvpSlots,
		at    = e.at,
		age   = time() - (e.at or 0),
	}
end

-- gs, avgIlvl, pvpCount. `gs` is nil when no GearScore addon is installed -- then
-- avgIlvl is the honest number to show, and callers must not label it "GS".
function M.GearOf(name)
	local e = name and db().specs[stripRealm(name)]
	if not e then return nil end
	return e.gs, e.ilvl, e.pvp or 0
end

-- "5807" / "5807 (4 PvP)" / "ilvl 245" -- one short string for a list cell.
function M.GearLabel(name)
	local gs, ilvl, pvp = M.GearOf(name)
	local base
	if gs and gs > 0 then base = tostring(gs)
	elseif ilvl and ilvl > 0 then base = "ilvl " .. ilvl
	else return nil end
	if pvp and pvp > 0 then base = base .. " |cffff5555(" .. pvp .. " PvP)|r" end
	return base
end

-- Inspect ONE player by name -- the pug case: someone whispers, you want their
-- real gear before inviting. Same queue as a group scan, so the two cannot
-- overlap and fight over the single in-flight inspect slot.
function M.ScanOne(name, callback)
	if active then return false, "busy" end
	name = stripRealm(name)
	if not name or name == "" then return false, "noname" end
	if not unitFor(name) then return false, "notingroup" end

	queue = { name }
	total, done = 1, 0
	active, onDone = true, callback
	fireNext()
	return true
end

-- Is this player's cached spec still trustworthy? Callers that gate loot on a
-- spec should prefer a fresh answer over a month-old one.
function M.IsFresh(name, maxDays)
	local _, _, _, age = M.Get(name)
	if not age then return false end
	return age <= (tonumber(maxDays) or db().staleDays or STALE_DAYS) * 86400
end

-- Scan the group. `force` re-inspects players we already know; without it only
-- the unknown and the stale are queued, which on a re-scan is usually a handful.
-- `callback(done, total)` fires once the queue drains.
function M.ScanGroup(force, callback)
	if active then return false, "busy" end

	local raidN  = GetNumRaidMembers() or 0
	local partyN = GetNumPartyMembers() or 0

	local names = {}
	if raidN > 0 then
		for i = 1, raidN do
			local n = stripRealm(GetRaidRosterInfo(i))
			if n then names[#names + 1] = n end
		end
	else
		names[1] = stripRealm(UnitName("player"))
		for i = 1, partyN do
			local n = stripRealm(UnitName("party" .. i))
			if n then names[#names + 1] = n end
		end
	end

	queue = {}
	for _, n in ipairs(names) do
		if force or not M.IsFresh(n) then queue[#queue + 1] = n end
	end

	total, done = #queue, 0
	if total == 0 then
		if callback then callback(0, 0) end
		return true, 0
	end

	active, onDone = true, callback
	fireNext()
	return true, total
end

function M.IsScanning() return active end

function M.Stop()
	queue = {}
	if active then finish() end
end

-- Drop entries older than `days`. Returns how many went.
function M.Purge(days)
	days = tonumber(days) or db().staleDays or STALE_DAYS
	if days <= 0 then return 0 end
	local cutoff, gone = time() - days * 86400, 0
	for name, e in pairs(db().specs) do
		if (e.at or 0) < cutoff then db().specs[name] = nil; gone = gone + 1 end
	end
	return gone
end

function M.Clear()
	db().specs = {}
end

-- Everyone we know about, as a plain array sorted by name -- for a settings list
-- or a debug dump.
function M.All()
	local out = {}
	for name, e in pairs(db().specs) do
		out[#out + 1] = { name = name, spec = e.spec, class = e.class, role = e.role, at = e.at }
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- ------------------------------------------------------------
-- Login: purge what has gone stale so the file does not grow forever with
-- players from pugs months ago.
-- ------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	M.Purge()
end)
