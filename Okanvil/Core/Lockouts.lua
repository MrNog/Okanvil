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
		-- Raids only, and only while actually locked. `expires` is SECONDS REMAINING
		-- (not an absolute timestamp), so it must be converted to a wall-clock time
		-- or it would silently stop counting down the moment we log out.
		if iname and raid and locked and expires and expires > 0 then
			instances[#instances + 1] = {
				name     = iname,
				id       = id,
				diff     = diff,
				diffname = diffname,
				players  = players,
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
