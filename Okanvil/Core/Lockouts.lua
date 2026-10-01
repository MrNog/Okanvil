-- ------------------------------------------------------------
-- LOCKOUTS  --  "which of my toons is already saved to what?"
--
-- The 3.3.5a API (GetNumSavedInstances / GetSavedInstanceInfo) only ever reports
-- the lockouts of the character you are CURRENTLY logged in as. There is no call
-- that asks the server about another toon. So the only way to answer "is my alt
-- still free for ToC?" without logging that alt in is the one SavedInstances uses:
--
--   every toon, on login, scans its OWN lockouts and writes them into an
--   ACCOUNT-WIDE table keyed by character name. Any toon can then read the cache
--   that every other toon left behind.
--
-- That means a toon's row is only as fresh as the last time you logged it in --
-- which is fine, because a raid lockout can't appear on a toon you never played.
-- Rows are stamped with `updated` so the tooltip can be honest about staleness.
--
-- RequestRaidInfo() is asynchronous: it does NOT fill the API in time for the
-- call that follows it. The data lands on UPDATE_INSTANCE_INFO, so that event is
-- what actually drives a rescan.
-- ------------------------------------------------------------
local _G = _G
local Okanvil = _G.Okanvil
if not Okanvil then return end

local GetNumSavedInstances = GetNumSavedInstances
local GetSavedInstanceInfo = GetSavedInstanceInfo
local RequestRaidInfo      = RequestRaidInfo

local L = {}
Okanvil.Lockouts = L

-- ------------------------------------------------------------
-- Scan: write THIS character's raid lockouts into the account-wide cache
-- ------------------------------------------------------------
function L:Scan()
	local db = Okanvil.db
	if not db then return end
	db.lockouts = db.lockouts or {}

	local name = UnitName("player")
	if not name then return end
	local _, class = UnitClass("player")

	local instances = {}
	local n = GetNumSavedInstances() or 0
	for i = 1, n do
		-- 3.3.5a signature: name, id, expires, diff, locked, extended, mostsig, raid, players, diffname
		local iname, id, expires, diff, locked, extended, _, raid, players, diffname = GetSavedInstanceInfo(i)
		-- Every RAID lockout, all four WotLK flavours (10N, 10H, 25N, 25H). Any of them
		-- stops you re-entering, so all of them are worth seeing. Heroic 5-man dungeons
		-- are excluded by the `raid` flag -- those are a different question.
		--
		-- `expires` is SECONDS REMAINING, not a timestamp, so it is converted to a
		-- wall-clock time or it would silently stop counting down once we log out.
		if iname and raid and locked and expires and expires > 0 then
			instances[#instances + 1] = {
				name     = iname,
				id       = id,
				diff     = diff,
				diffname = diffname,
				players  = players,
				heroic   = (diff == 3 or diff == 4),
				-- An EXTENDED lockout was deliberately held over by the player, so it
				-- outlives the normal reset.
				extended = extended and true or false,
				resets   = time() + expires,   -- absolute: survives logout
			}
		end
	end

	if #instances > 0 then
		db.lockouts[name] = {
			class     = class,
			realm     = GetRealmName(),
			updated   = time(),
			instances = instances,
		}
	else
		-- No lockouts left on this toon -> drop the row entirely, so a toon that
		-- reset never lingers in the tooltip as a ghost.
		db.lockouts[name] = nil
	end
end

-- ------------------------------------------------------------
-- Read: every toon with at least one UNEXPIRED raid lockout.
-- Expiry is decided here, at read time, against the stored absolute reset --
-- a cached row from a toon you haven't logged in for a week self-cleans.
-- ------------------------------------------------------------
function L:Get()
	local db = Okanvil.db
	if not db or not db.lockouts then return {} end

	local now = time()
	local out = {}
	for charName, row in pairs(db.lockouts) do
		local live = {}
		for _, inst in ipairs(row.instances or {}) do
			if inst.resets and inst.resets > now then
				live[#live + 1] = inst
			end
		end
		if #live > 0 then
			table.sort(live, function(a, b) return (a.resets or 0) < (b.resets or 0) end)
			out[#out + 1] = {
				name      = charName,
				class     = row.class,
				updated   = row.updated,
				instances = live,
			}
		end
	end

	-- current character first, then alphabetical -- your own lockouts are what you
	-- check most, so they shouldn't move around as alts come and go.
	local me = UnitName("player")
	table.sort(out, function(a, b)
		if a.name == me then return true end
		if b.name == me then return false end
		return a.name < b.name
	end)
	return out
end

-- ------------------------------------------------------------
-- Grid: the lockouts as a raid-by-toon table, for the minimap tooltip and the
-- Home page's Saved raids tab.
--   toons     -- L:Get(), current character first
--   raids     -- raid names, current tier first (see U.raidRank)
--   cell      -- cell[raid][toon][size] = true; a toon can hold the same raid
--                at two sizes, so size is a dimension, not a string
--   sizes     -- every size label in use, ascending: "10", "10H", "25", "25H"
--   soonest   -- the earliest reset, as a time() value
-- The label carries the difficulty, not just the size: a 25 normal and a 25
-- heroic are different lockouts and must not share a cell.
-- ------------------------------------------------------------
function L:Grid()
	local toons = self:Get()
	local raids, cell, sizeSeen, soonest = {}, {}, {}, nil
	for _, toon in ipairs(toons) do
		for _, inst in ipairs(toon.instances) do
			if not cell[inst.name] then
				cell[inst.name] = {}
				raids[#raids + 1] = inst.name
			end
			local n = (inst.players and inst.players > 0) and inst.players or 0
			local size = inst.heroic and (n .. "H") or tostring(n)
			cell[inst.name][toon.name] = cell[inst.name][toon.name] or {}
			cell[inst.name][toon.name][size] = true
			sizeSeen[size] = true
			if not soonest or inst.resets < soonest then soonest = inst.resets end
		end
	end
	-- current tier first (Okanvil.U.raidRank), then by name for raids it does not know
	local U = Okanvil.U
	table.sort(raids, function(a, b)
		local ra = U and U.raidRank and U.raidRank(a) or 0
		local rb = U and U.raidRank and U.raidRank(b) or 0
		if ra ~= rb then return ra < rb end
		return a < b
	end)
	-- By the NUMBER first, then normal before heroic. A plain string sort puts
	-- "10H" before "10" and breaks once a label reaches two digits.
	local sizes = {}
	for s in pairs(sizeSeen) do sizes[#sizes + 1] = s end
	table.sort(sizes, function(a, b)
		local na = tonumber(a:match("%d+")) or 0
		local nb = tonumber(b:match("%d+")) or 0
		if na ~= nb then return na < nb end
		return (a:find("H") == nil) and (b:find("H") ~= nil)
	end)
	return toons, raids, cell, sizes, soonest
end

-- "4d 12h" / "12h 30m" / "45m" -- raid lockouts are long, so seconds are noise.
function L:FormatTime(remaining)
	if not remaining or remaining <= 0 then return "expired" end
	local d = math.floor(remaining / 86400)
	local h = math.floor((remaining % 86400) / 3600)
	local m = math.floor((remaining % 3600) / 60)
	if d > 0 then return string.format("%dd %dh", d, h) end
	if h > 0 then return string.format("%dh %dm", h, m) end
	return string.format("%dm", m)
end

-- A short label for one lockout: "Trial of the Crusader (25 Heroic)".
-- diffname is the server's own string when present; players/diff are the fallback.
function L:Label(inst)
	local diff = inst.diffname
	if not diff or diff == "" then
		diff = (inst.players and inst.players > 0) and (inst.players .. " Player") or nil
	end
	if diff and diff ~= "" then
		return inst.name .. " |cff8a8d93(" .. diff .. ")|r"
	end
	return inst.name
end

-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("UPDATE_INSTANCE_INFO")   -- the async answer to RequestRaidInfo
ev:RegisterEvent("RAID_INSTANCE_WELCOME")  -- zoned into an instance that saves you
ev:RegisterEvent("PLAYER_ENTERING_WORLD")  -- covers zoning out of the raid too

ev:SetScript("OnEvent", function(_, event)
	if event == "UPDATE_INSTANCE_INFO" then
		L:Scan()
		return
	end
	-- Everything else only ASKS the server; the scan happens when the reply lands
	-- on UPDATE_INSTANCE_INFO above. Delayed on login because the instance data is
	-- not populated at PLAYER_LOGIN yet.
	if event == "PLAYER_LOGIN" then
		if Okanvil.Comms and Okanvil.Comms.After then
			Okanvil.Comms.After(5, function() RequestRaidInfo() end)
		else
			RequestRaidInfo()
		end
	else
		RequestRaidInfo()
	end
end)

-- ------------------------------------------------------------
-- WINTERGRASP  --  "does our faction hold VoA right now?"
--
-- 3.3.5a has no call that names Wintergrasp's owner. What it does have is the
-- "Essence of Wintergrasp" buff, which the game puts on every player of the
-- controlling faction while they are in Northrend. So in Northrend, outside an
-- instance and outside a battle: buff = our faction holds it, no buff = theirs.
--
-- Anywhere else we cannot see it, so the last reading is kept account-wide in
-- db.wg with the time it was taken. GetWintergraspWaitTime works everywhere and
-- gives the next battle; a reading from before a battle that has since happened
-- may no longer be true, and the Home tile says so.
-- ------------------------------------------------------------
local WG = {}
Okanvil.WG = WG

local ESSENCE = { 57940, 58045 }   -- Essence of Wintergrasp (Northrend / the zone)
local NORTHREND = 4                -- GetCurrentMapContinent()
local BATTLE_LEN = 30 * 60

local inNorthrend = false

local function hasEssence()
	for _, id in ipairs(ESSENCE) do
		local n = GetSpellInfo(id)
		if n and UnitAura("player", n) then return true end
	end
	return false
end

-- SetMapToCurrentZone moves the world map, so never while someone is reading it.
local function checkZone()
	if IsInInstance() then inNorthrend = false; return end
	if WorldMapFrame and WorldMapFrame:IsShown() then return end
	SetMapToCurrentZone()
	inNorthrend = (GetCurrentMapContinent() == NORTHREND)
end

local function wgDB()
	local db = Okanvil.db
	if not db then return nil end
	db.wg = db.wg or {}
	return db.wg
end

function WG.Read()
	local d = wgDB()
	if not d then return end
	local wait = GetWintergraspWaitTime and GetWintergraspWaitTime()
	if wait and wait > 0 then
		-- the battle we were counting down to has been fought: remember when, so a
		-- holder read before it is known to be out of date
		if d.nextAt and d.nextAt <= time() then d.lastBattle = d.nextAt end
		d.nextAt = time() + wait
	end
	-- nil wait = the battle is on: nobody holds it until it ends
	if inNorthrend and wait and wait > 0 then
		local mine = UnitFactionGroup("player")
		local other = (mine == "Horde") and "Alliance" or "Horde"
		local holder = hasEssence() and mine or other
		-- The buff drops for a moment when crossing zones (leaving Dalaran), so its
		-- absence is weak evidence. Only a battle changes the holder: with a reading
		-- taken since the last battle, a missing buff does not overturn it.
		if holder == other and d.faction == mine and (d.at or 0) >= (d.lastBattle or 0) then
			if WG.onChange then pcall(WG.onChange) end
			return
		end
		if d.faction ~= holder and Okanvil.Trace then
			Okanvil:Trace("WG", "holder " .. tostring(holder))
		end
		d.faction, d.at = holder, time()
	end
	if WG.onChange then pcall(WG.onChange) end
end

-- faction or nil, state: "ok" | "old" (read before the last battle) | "battle" | "unknown";
-- plus seconds to the next battle (nil when not known)
function WG.State()
	local d = wgDB() or {}
	local now = time()
	-- A nextAt in the past is a battle that has started since the last read. The
	-- next one is only known once the game reports it again (WG.Read).
	local nextAt, lastBattle = d.nextAt, d.lastBattle
	if nextAt and nextAt <= now then
		if now < nextAt + BATTLE_LEN then return d.faction, "battle", nil end
		lastBattle, nextAt = nextAt, nil
	end
	local toNext = nextAt and (nextAt - now) or nil
	if not d.faction then return nil, "unknown", toNext end
	if lastBattle and (d.at or 0) < lastBattle then return d.faction, "old", toNext end
	return d.faction, "ok", toNext
end

local wgEv = CreateFrame("Frame")
wgEv:RegisterEvent("PLAYER_ENTERING_WORLD")
wgEv:RegisterEvent("ZONE_CHANGED_NEW_AREA")
wgEv:RegisterEvent("UNIT_AURA")
local auraWait = 0
wgEv:SetScript("OnEvent", function(_, event, unit)
	if event == "UNIT_AURA" then
		-- cheap: only in Northrend, and at most every 2 seconds
		if unit ~= "player" or not inNorthrend or GetTime() < auraWait then return end
		auraWait = GetTime() + 2
		WG.Read()
		return
	end
	-- the buff lands a moment after the zone-in
	local After = Okanvil.Comms and Okanvil.Comms.After
	local function go() checkZone(); WG.Read() end
	if After then After(3, go) else go() end
end)
