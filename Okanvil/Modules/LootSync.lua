-- ============================================================
-- Okanvil -- Loot sync between officers.
--
-- Loot history is per character: only whoever was in the raid recorded it. A
-- raid ID played over two nights leaves the second night's master looter blind
-- to the first unless they were there, and the council's "already won" icons
-- come up empty for everyone who won gear that first night.
--
-- So officers share what they saw. Whenever an officer's client lands in a raid
-- (zoning in, or joining the group while inside) it offers its winners for this
-- run to the raid and asks for theirs; every other officer merges the offer and
-- answers with their own. Whoever was there the first night fills in the rest.
--
-- Silent, like the rest of loot capture: no popup, nothing asked of anyone.
--
-- WHO TAKES PART. Only officers (and an officer's alt) send and merge. The
-- master looter is let in to ask and merge even when not an officer, since the
-- council runs on their screen. A plain raider's client ignores all of it.
--
-- WHAT IS SENT. Only rows with a winner (receivedBy). A row still in the ML's
-- bags (heldBy) is not anyone's loot yet. One line per row:
--     id <TAB> boss <TAB> winner <TAB> de <TAB> corpse <TAB> slot <TAB> t <TAB> link
-- after a header naming the run: version, mode (O = offer, answer me; R = reply),
-- zone, difficulty, and the start of the lockout week.
--
-- SAME RUN. Two clients can key one run differently ("lock|" vs the "week|"
-- fallback), so the run is matched by zone + difficulty + lockout week instead,
-- and every row must be from inside that week.
-- ============================================================

local Okanvil = Okanvil
local S = {}
Okanvil.LootSync = S

local TAG         = "LSYNC"
local PROTO       = "1"
local OFFER_GAP   = 60          -- seconds between two offers from this client
local ZONE_DELAY  = 15          -- after zoning in: let the lockout answer arrive first
local WEEK_SLACK  = 2 * 86400   -- two clients may place the week boundary a little apart

local lastOfferAt = -OFFER_GAP
local queued = {}               -- sends held back while in combat: fn()

local function trace(line)
	if Okanvil.Trace then Okanvil:Trace("LSYNC", line) end
end

local function me() return (UnitName and UnitName("player")) or "" end
local function short(n) return n and (n:gsub("%-.*$", "")) or n end

local function isOfficer(name)
	local U = Okanvil.U
	return U and name and (U.isOfficer(name) or U.isOfficerAlt(name)) or false
end

local function isML(name)
	local L = Okanvil.Loot
	local ml = L and L.MasterLooterName and L.MasterLooterName()
	return ml ~= nil and name ~= nil and short(ml):lower() == short(name):lower()
end

local function inMyRaid(name)
	return UnitInRaid and UnitInRaid(name) ~= nil
end

local function enabled()
	return not (Okanvil.ModuleActive and not Okanvil:ModuleActive("__loot"))
end

-- Passive work never runs in combat: held until it ends.
local function whenCalm(fn)
	if (UnitAffectingCombat and UnitAffectingCombat("player")) then
		queued[#queued + 1] = fn
	else
		fn()
	end
end

-- ------------------------------------------------------------
-- Encode / decode
-- ------------------------------------------------------------
local function encode(mode, s)
	local L = Okanvil.Loot
	local out = { PROTO, mode, s.zone or "", tostring(s.difficulty or 0), tostring(L.WeekStart()) }
	local rows = 0
	for _, d in ipairs(s.drops or {}) do
		if d.receivedBy and d.receivedBy ~= "" and d.id then
			out[#out + 1] = table.concat({
				d.id, d.boss or "", d.receivedBy, d.de and "1" or "0",
				d.corpse or "", d.slot or 0, d.t or 0, d.item or "",
			}, "\t")
			rows = rows + 1
		end
	end
	return table.concat(out, "\n"), rows
end

local function decode(text)
	local lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
	if lines[1] ~= PROTO then return nil end
	local h = { mode = lines[2], zone = lines[3], diff = tonumber(lines[4]) or 0,
		week = tonumber(lines[5]) or 0, rows = {} }
	for i = 6, #lines do
		local f = {}
		for v in (lines[i] .. "\t"):gmatch("(.-)\t") do f[#f + 1] = v end
		local id = tonumber(f[1])
		if id and f[3] and f[3] ~= "" then
			h.rows[#h.rows + 1] = {
				id = id, boss = f[2] or "", who = f[3], de = f[4] == "1",
				corpse = f[5] or "", slot = tonumber(f[6]) or 0, t = tonumber(f[7]) or 0,
				link = f[8] or "",
			}
		end
	end
	return h
end

-- ------------------------------------------------------------
-- Merge one incoming row into the session. Returns true when something changed.
--   1. same corpse + slot          -> the same physical item: fill its winner if open
--   2. same item, boss and winner  -> already known
--   3. same item and boss, no winner yet -> that copy: give it this winner
--   4. otherwise                   -> a drop we never saw: add it
-- `used` marks local rows already matched, so two copies won by one raider
-- (two trophies) stay two rows.
-- ------------------------------------------------------------
local function merge(s, r, used, sender)
	local drops = s.drops
	local function claim(d)
		used[d] = true
		if d.receivedBy and d.receivedBy ~= "" then return false end
		d.receivedBy, d.heldBy, d.passed = r.who, nil, nil
		if r.de then d.de = true; d.disenchanted = true end
		return true
	end
	if r.corpse ~= "" and r.slot > 0 then
		for _, d in ipairs(drops) do
			if not used[d] and d.corpse == r.corpse and d.slot == r.slot then return claim(d) end
		end
	end
	for _, d in ipairs(drops) do
		if not used[d] and d.id == r.id and d.boss == r.boss and d.receivedBy == r.who then
			used[d] = true
			return false
		end
	end
	for _, d in ipairs(drops) do
		if not used[d] and d.id == r.id and d.boss == r.boss
			and (not d.receivedBy or d.receivedBy == "") then
			return claim(d)
		end
	end
	local name, _, rarity = GetItemInfo(r.link ~= "" and r.link or r.id)
	local icon = (GetItemIcon and GetItemIcon(r.id)) or nil
	local d = {
		t = r.t > 0 and r.t or time(), boss = r.boss ~= "" and r.boss or "Trash", id = r.id,
		item = r.link, name = name or "", rarity = rarity or 4, qty = 1, boe = false,
		icon = icon and (icon:gsub(".*\\", "")) or nil,
		receivedBy = r.who, syncFrom = sender,
	}
	if r.corpse ~= "" and r.slot > 0 then d.corpse, d.slot = r.corpse, r.slot end
	if r.de then d.de = true; d.disenchanted = true end
	drops[#drops + 1] = d
	used[d] = true
	return true
end

-- ------------------------------------------------------------
-- Send
-- ------------------------------------------------------------
local function send(mode, target)
	local L, C = Okanvil.Loot, Okanvil.Comms
	if not (L and C and L.RaidRunSession) then return end
	local s = L.RaidRunSession(false)
	-- An offer goes out even with nothing to give: it is also the question.
	if not s then
		if mode ~= "O" then return end
		s = { zone = (GetInstanceInfo and (GetInstanceInfo())) or "",
			difficulty = select(3, GetInstanceInfo()) or 0, drops = {} }
	end
	local text, rows = encode(mode, s)
	if mode == "R" and rows == 0 then return end
	if target then
		C.SendBig(TAG, text, "WHISPER", target)
	else
		C.SendBig(TAG, text)
	end
	trace(("%s %d winners of %s%s"):format(mode == "O" and "offered" or "replied",
		rows, tostring(s.zone), target and (" to " .. target) or ""))
end

-- Offer this run's winners to the raid and ask for theirs.
function S.Offer(why)
	if not enabled() then return end
	local L = Okanvil.Loot
	if not (L and L.RaidRunSession) or not (GetNumRaidMembers and GetNumRaidMembers() > 0) then return end
	local name = me()
	if not (isOfficer(name) or isML(name)) then return end
	-- Not in a recorded raid instance: there is no run to talk about.
	if not (IsInInstance and select(2, IsInInstance()) == "raid") then return end
	local now = (GetTime and GetTime()) or 0
	if now - lastOfferAt < OFFER_GAP then return end
	lastOfferAt = now
	trace("offer (" .. tostring(why) .. ")")
	whenCalm(function() send("O") end)
end

-- ------------------------------------------------------------
-- Receive
-- ------------------------------------------------------------
local function onSync(sender, text)
	if not enabled() then return end
	sender = short(sender)
	local name = me()
	if sender == "" or sender == name then return end
	if not (isOfficer(name) or isML(name)) then return end
	if not inMyRaid(sender) then
		trace("ignored " .. sender .. ": not in this raid")
		return
	end
	local h = decode(text or "")
	if not h then return end
	local L = Okanvil.Loot
	if not (L and L.RaidRunSession) then return end

	-- Only an officer's rows are merged. The ML may ask without being one.
	local trusted = isOfficer(sender)
	if trusted and #h.rows > 0 then
		local s = L.RaidRunSession(true)
		local week = L.WeekStart()
		if not s then
			trace("ignored " .. sender .. "'s rows: not in a raid run")
		elseif (s.zone or "") ~= h.zone or (s.difficulty or 0) ~= h.diff
			or math.abs(week - h.week) > WEEK_SLACK then
			trace(("ignored %s's rows: %s/%d is not this run (%s/%d)"):format(
				sender, tostring(h.zone), h.diff, tostring(s.zone), s.difficulty or 0))
		else
			local used, added = {}, 0
			for _, r in ipairs(h.rows) do
				if r.t >= week - 3600 and merge(s, r, used, sender) then added = added + 1 end
			end
			trace(("merged %d of %d winners from %s"):format(added, #h.rows, sender))
			if added > 0 and L.onLoot then L.onLoot() end
		end
	end

	if h.mode == "O" and isOfficer(name) and (trusted or isML(sender)) then
		whenCalm(function() send("R", sender) end)
	end
end

if Okanvil.Comms then Okanvil.Comms.OnBig(TAG, onSync) end

-- ------------------------------------------------------------
-- Triggers: zoning into a raid, and joining a raid group while already inside.
-- ------------------------------------------------------------
local wasInRaid = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
	local C = Okanvil.Comms
	if event == "PLAYER_REGEN_ENABLED" then
		local list = queued
		queued = {}
		for _, fn in ipairs(list) do fn() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if C and IsInInstance and select(2, IsInInstance()) == "raid" then
			C.After(ZONE_DELAY, function() S.Offer("zone in") end)
		end
	elseif event == "RAID_ROSTER_UPDATE" then
		local inRaid = (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0
		if inRaid and not wasInRaid and C then
			C.After(ZONE_DELAY, function() S.Offer("joined raid") end)
		end
		wasInRaid = inRaid
	end
end)
