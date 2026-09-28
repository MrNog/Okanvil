-- ============================================================
-- Okanvil -- Attendance (officer page + main-run recorder).
-- Guild rule: the officers pick the mandatory raids on the Rules pill (no default --
-- it depends on the patch) and a main must be saved to OUR ID of them each week. A main saved to
-- another ID of a mandatory raid without an officer's OK goes to the bottom of loot
-- prio; a main who simply did not raid only loses attendance %. The addon is the
-- sensor, the site is the brain: this page shows what this client knows and exports it.
--
-- Two sources, both passive (no popups):
--   * the run: one client records each night -- the master looter, or the raid
--     leader when there is no ML -- from the Guild module's first-pull snapshot;
--     nights that share a lockout ID are one lockout.
--   * the letters (AttendanceLetters.lua): every Okanvil reports, once per
--     lockout, which raid ID its character is saved to.
-- ============================================================

local Okanvil = Okanvil
local A = {}
Okanvil.Attendance = A

local ADDON = "Okanvil-Attendance"
local W = Okanvil.W
local C = Okanvil.Colors

local MAX_RUNS = 40          -- ~2-3 months of guild runs, every raid and size
local SHOW_LOCKOUTS = 4      -- columns in the mains table

function A.DB()
	local db = Okanvil.db
	db.attendance = db.attendance or {}
	local a = db.attendance
	a.runs = a.runs or {}
	return a
end

local function stripRealm(n) return (n or ""):gsub("%-.*$", "") end

-- ------------------------------------------------------------
-- The guild's rules: which raids a main must do in OUR ID, and which count as
-- extra effort. A raid is "<short><size>" from the shared catalogue (OkanvilRaids):
-- "ICC25", "Naxx10". Officers pick them on the Rules pill. The newest pick wins
-- when officers sync, so every officer's page reads the same rule.
--   all = false -> one mandatory raid in our ID is enough; true -> every one of them.
-- ------------------------------------------------------------
-- No default: which raids count depends on the guild and the patch (Naxx in the
-- first tier, ICC in the last). Until an officer picks, the pages say so.
local DEFAULT_MUST, DEFAULT_EXTRA = {}, {}

local function copy(list) local out = {}; for i, v in ipairs(list) do out[i] = v end; return out end

-- The raids a rule can name: the catalogue, plus the heroic of a raid whose heroic
-- has its own lockout (ToGC is not ToC: another ID). { short, name, zone, hc }
local ruleRaids
function A.RuleRaids()
	if ruleRaids then return ruleRaids end
	ruleRaids = {}
	for _, r in ipairs(OkanvilRaids or {}) do
		ruleRaids[#ruleRaids + 1] = { short = r.short, name = r.name, zone = r.name, raid = r }
		if r.hcLockout then
			local hs = (OkanvilRaidHCName and OkanvilRaidHCName[r.key]) or (r.short .. "H")
			ruleRaids[#ruleRaids + 1] = { short = hs, name = r.name .. " (heroic)", zone = r.name, raid = r, hc = true }
		end
	end
	return ruleRaids
end
function A.RaidByShort(short)
	for _, r in ipairs(A.RuleRaids()) do if r.short == short then return r end end
end
function A.RaidOfZone(zone)
	for _, r in ipairs(OkanvilRaids or {}) do if r.name == zone then return r end end
end
-- The rule raid of a lockout / snapshot: difficulty 3 and 4 are heroic on 3.3.5a,
-- and only a raid with its own heroic lockout becomes a different raid for it.
function A.RuleRaidOf(zone, diff)
	local raid = A.RaidOfZone(zone)
	if not raid then return nil end
	local hc = raid.hcLockout and (diff == 3 or diff == 4)
	for _, r in ipairs(A.RuleRaids()) do
		if r.raid == raid and (r.hc or false) == (hc or false) then return r end
	end
end

-- "Naxx25" -> "Naxx", 25 (nil when the raid is not in the catalogue)
function A.ParseRef(ref)
	local short, size = (ref or ""):match("^(.-)(%d+)$")
	size = tonumber(size)
	if short and A.RaidByShort(short) and (size == 10 or size == 25) then return short, size end
end
function A.RefLabel(ref)
	local short, size = A.ParseRef(ref)
	return short and (short .. " " .. size) or tostring(ref)
end

function A.Rules()
	local a = A.DB()
	if not a.rules then a.rules = { must = copy(DEFAULT_MUST), extra = copy(DEFAULT_EXTRA), all = false, t = 0 } end
	return a.rules
end

local function inList(list, ref)
	for i, v in ipairs(list) do if v == ref then return i end end
end
function A.IsMust(ref) return inList(A.Rules().must, ref) ~= nil end
function A.IsExtra(ref) return inList(A.Rules().extra, ref) ~= nil end

-- "ICC 25", "ICC 25 + Naxx 25" (all of them) or "ICC 25 or Naxx 25" (any one)
function A.MustLabel()
	local r, out = A.Rules(), {}
	for _, ref in ipairs(r.must) do out[#out + 1] = A.RefLabel(ref) end
	if #out == 0 then return "no raid chosen" end
	return table.concat(out, r.all and " + " or " or ")
end
function A.ExtraLabel()
	local out = {}
	for _, ref in ipairs(A.Rules().extra) do out[#out + 1] = A.RefLabel(ref) end
	return #out > 0 and table.concat(out, ", ") or "none"
end

local function rulesChanged()
	local r = A.Rules()
	r.t, r.by = time(), UnitName("player") or ""
	Okanvil:Trace("ATT", ("rules: must %s (%s), extra %s"):format(table.concat(r.must, "+"),
		r.all and "all" or "any", table.concat(r.extra, "+")))
	if A.Letters and A.Letters.ShareRules then A.Letters.ShareRules() end
	if A.onChange then A.onChange() end
end

-- kind = "must", "extra" or nil (not counted). A raid sits in one list at most.
function A.SetRule(ref, kind)
	if not A.ParseRef(ref) then return end
	local r = A.Rules()
	local i = inList(r.must, ref); if i then table.remove(r.must, i) end
	i = inList(r.extra, ref); if i then table.remove(r.extra, i) end
	if kind == "must" then r.must[#r.must + 1] = ref elseif kind == "extra" then r.extra[#r.extra + 1] = ref end
	rulesChanged()
end
function A.SetMustAll(all)
	A.Rules().all = all and true or false
	rulesChanged()
end

-- Another officer's rules, from the sync: taken only when newer than ours.
function A.ApplyRules(t, by, all, must, extra)
	local r = A.Rules()
	if (t or 0) <= (r.t or 0) then return false end
	local function clean(list)
		local out = {}
		for _, ref in ipairs(list) do if A.ParseRef(ref) then out[#out + 1] = ref end end
		return out
	end
	r.t, r.by, r.all, r.must, r.extra = t, by, all and true or false, clean(must), clean(extra)
	if A.onChange then A.onChange() end
	return true
end

-- The rule raid + size of a snapshot or run: "ICC25", "ToGC25", or nil for anything else.
local function refOf(zone, size, diff)
	local raid = A.RuleRaidOf(zone, diff)
	return raid and (size == 10 or size == 25) and (raid.short .. size) or nil
end
A.RefOf = refOf

-- ------------------------------------------------------------
-- Lockout week: the Wednesday on or before t, as "YYYY-MM-DD" (same rule as the site).
-- ------------------------------------------------------------
local function weekOf(t)
	local d = date("*t", t)
	local back = (d.wday - 4) % 7            -- wday: 1 = Sunday, 4 = Wednesday
	return date("%Y-%m-%d", time({ year = d.year, month = d.month, day = d.day - back, hour = 12 }))
end
A.WeekOf = weekOf

-- ------------------------------------------------------------
-- Who records: the master looter; with no master loot, the raid leader.
-- ------------------------------------------------------------
function A.IsRecorder()
	local L = Okanvil.Loot
	local ml = L and L.MasterLooterName and L.MasterLooterName()
	if ml then return L.IsMasterLooter() end
	return (IsRaidLeader and IsRaidLeader()) and true or false
end

-- Every raid of the catalogue is recorded, not only today's mandatory ones: the
-- Rules decide what the page SHOWS, so a recorder who has not received the rules
-- yet, or a rule changed mid-week, never loses a night.
local function isMainRaid(snap)
	return refOf(snap.zone, snap.groupSize, snap.difficulty) ~= nil
end

-- Share of the raid that is in our guild (alts included). A pug on the same raid is
-- not the main run, however it was formed.
local function guildShare(snap)
	local n, g = 0, 0
	for _, pl in ipairs(snap.players or {}) do
		n = n + 1
		if Okanvil.U.guildRankOf(pl.name) then g = g + 1 end
	end
	return n > 0 and g / n or 0
end

local function isMainRun(snap)
	return isMainRaid(snap) and guildShare(snap) >= 0.5
end

-- ------------------------------------------------------------
-- Runs: one per lockout. Keyed by the lockout ID once the game reports it; before
-- the first boss dies there is no ID yet, so the night waits under zone+size+week
-- and moves over when the ID arrives.
-- ------------------------------------------------------------
local function tempKey(snap)
	return "w:" .. (snap.zone or "") .. "|" .. (snap.groupSize or 0) .. "|" .. weekOf(snap.t)
end
local function idKey(id) return "id:" .. tostring(id) end

local function trimRuns(runs)
	local list = {}
	for k, r in pairs(runs) do list[#list + 1] = { k = k, t = r.first or 0 } end
	if #list <= MAX_RUNS then return end
	table.sort(list, function(a, b) return a.t > b.t end)
	for i = MAX_RUNS + 1, #list do runs[list[i].k] = nil end
end

-- Move a night-in-waiting under its lockout ID, merging into the run that already
-- holds that ID (night 2 recorded before night 1's ID was known, or the reverse).
local function adoptId(fromKey, id)
	local runs = A.DB().runs
	local r = runs[fromKey]
	if not r then return end
	local to = idKey(id)
	runs[fromKey] = nil
	local dest = runs[to]
	if not dest then
		r.lockoutId = id
		runs[to] = r
		return
	end
	for _, n in ipairs(r.nights) do
		local dup = false
		for _, m in ipairs(dest.nights) do if m.date == n.date then dup = true end end
		if not dup then dest.nights[#dest.nights + 1] = n end
	end
	table.sort(dest.nights, function(a, b) return a.t < b.t end)
	dest.first = math.min(dest.first or r.first or 0, r.first or dest.first or 0)
end

-- File a snapshot as a night of its run. A second snapshot of the same night (a
-- /reload re-pull) adds whoever the first one missed, so a late arrival still counts.
local function addNight(snap, id)
	local runs = A.DB().runs
	local key = id and idKey(id) or tempKey(snap)
	local r = runs[key]
	if not r then
		r = { zone = snap.zone, size = snap.groupSize, difficulty = snap.difficulty,
			lockoutId = id, week = weekOf(snap.t), first = snap.t, nights = {} }
		runs[key] = r
	end
	local day = date("%Y-%m-%d", snap.t)
	local night
	for _, n in ipairs(r.nights) do
		if n.date == day then night = n end
	end
	if not night then
		night = { t = snap.t, date = day, recorder = UnitName("player") or "", players = {} }
		r.nights[#r.nights + 1] = night
		table.sort(r.nights, function(a, b) return a.t < b.t end)
	end
	-- g = raid group, s = spec (from the Inspect scan; empty until it answers)
	local have = {}
	for _, pl in ipairs(night.players) do have[pl.n] = pl end
	local added = 0
	for _, pl in ipairs(snap.players or {}) do
		local n = stripRealm(pl.name)
		if n ~= "" and not have[n] then
			local e = { n = n, c = pl.class or "", g = pl.group or 0, s = pl.spec or "" }
			night.players[#night.players + 1] = e
			have[n] = e
			added = added + 1
		elseif n ~= "" and pl.spec and pl.spec ~= "" and (have[n].s or "") == "" then
			have[n].s = pl.spec
			added = added + 1
		end
	end
	if added > 0 then night.exportedAt = nil end
	r.first = math.min(r.first or snap.t, snap.t)
	snap.attKey, snap.attSeen = key, true
	trimRuns(runs)
	Okanvil:Trace("ATT", ("night %s %s|%s: +%d players (%d), key %s"):format(day, tostring(snap.zone),
		tostring(snap.groupSize), added, #night.players, key))
	return key
end

-- The Guild module calls this when the Inspect scan after a snapshot has read the
-- specs: fill them into the night that snapshot became (it was filed before the scan).
function A.OnSpecs(snap)
	local r = snap and snap.attKey and A.DB().runs[snap.attKey]
	if not r then return end
	local day = date("%Y-%m-%d", snap.t)
	local spec = {}
	for _, pl in ipairs(snap.players or {}) do
		if pl.spec and pl.spec ~= "" then spec[stripRealm(pl.name)] = pl.spec end
	end
	for _, n in ipairs(r.nights) do
		if n.date == day then
			local changed = false
			for _, p in ipairs(n.players) do
				if spec[p.n] and p.s ~= spec[p.n] then p.s = spec[p.n]; changed = true end
			end
			if changed then n.exportedAt = nil end
		end
	end
end

-- The Guild module calls this after every snapshot it saves.
function A.OnSnapshot(snap)
	if not snap or not isMainRun(snap) then return end
	snap.attSeen = true
	if not A.IsRecorder() then
		Okanvil:Trace("ATT", "skip night: not the recorder (" .. tostring(snap.zone) .. ")")
		return
	end
	addNight(snap, snap.lockoutId)
	if A.onChange then A.onChange() end
end

-- ------------------------------------------------------------
-- One-time backfill from the snapshots this client already holds (taken before the
-- module existed). The lockout ID of a snapshot from THIS week is read from our own
-- saved lockout: the character who was in that raid is saved to that ID. Older weeks
-- keep the ID the snapshot carried, or wait under their week.
-- ------------------------------------------------------------
function A.Backfill()
	local a = A.DB()
	if a.backfilled then return end
	local G = Okanvil.Guild
	local list = (Okanvil.db.guild and Okanvil.db.guild.snapshots) or {}
	local nowWeek = weekOf(time())
	local n = 0
	for i = #list, 1, -1 do                 -- oldest first, so night order is natural
		local snap = list[i]
		if not snap.attSeen and isMainRaid(snap) and not isMainRun(snap) then
			Okanvil:Trace("ATT", ("backfill skip %s: %d%% guild"):format(date("%Y-%m-%d", snap.t),
				math.floor(guildShare(snap) * 100)))
		elseif not snap.attSeen and isMainRun(snap) then
			local id = snap.lockoutId
			if not id and weekOf(snap.t) == nowWeek and G and G.MyLockoutId then
				id = G.MyLockoutId(snap.zone, snap.difficulty)
			end
			addNight(snap, id)
			n = n + 1
		end
	end
	a.backfilled = time()
	Okanvil:Trace("ATT", "backfill: " .. n .. " snapshot(s)")
	if n > 0 then
		Okanvil:Print("Attendance: filed " .. n .. " earlier main-run snapshot(s).")
		if A.onChange then A.onChange() end
	end
end

-- An officer who raided with the guild this week sets our IDs with one click: the
-- lockouts their own character holds for the mandatory raids. For weeks the master
-- looter did not record, before 3 raiders' letters agree on it.
function A.SetOurIdFromMine()
	local G = Okanvil.Guild
	local me = UnitName("player") or ""
	local a = A.DB()
	a.ourIds = a.ourIds or {}
	local week = weekOf(time())
	if #A.Rules().must == 0 then
		Okanvil:Print("Attendance: no mandatory raid chosen yet -- pick one on the Rules pill.")
		return
	end
	local set = 0
	for _, ref in ipairs(A.Rules().must) do
		local short, size = A.ParseRef(ref)
		local raid = short and A.RaidByShort(short)
		-- raid difficulty on 3.3.5a: 1 = 10, 2 = 25, 3 = 10 heroic, 4 = 25 heroic
		-- ToC and ToGC are two lockouts: each looks at its own difficulty only
		local nd, hd = (size == 10) and 1 or 2, (size == 10) and 3 or 4
		local id
		if raid and G and G.MyLockoutId then
			if raid.hc then id = G.MyLockoutId(raid.zone, hd)
			elseif raid.raid.hcLockout then id = G.MyLockoutId(raid.zone, nd)
			else id = G.MyLockoutId(raid.zone, nd) or G.MyLockoutId(raid.zone, hd) end
		end
		if id then
			a.ourIds[week .. "|" .. ref] = { id = id, by = me, t = time(), week = week, raid = ref }
			Okanvil:Print(("Attendance: our %s ID for the week of %s is now %s (%s)."):format(
				A.RefLabel(ref), week, tostring(id), me))
			set = set + 1
		end
	end
	if set == 0 then
		Okanvil:Print("Attendance: " .. me .. " is not saved to " .. A.MustLabel() .. " this week.")
		return
	end
	if A.onChange then A.onChange() end
end

-- Run it once the server has answered with our lockouts, so this week's ID is known.
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:RegisterEvent("UPDATE_INSTANCE_INFO")
	f:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_LOGIN" then
			if RequestRaidInfo then RequestRaidInfo() end
			return
		end
		self:UnregisterEvent("UPDATE_INSTANCE_INFO")
		local ok, err = pcall(A.Backfill)
		if not ok then Okanvil:Err("Attendance backfill", err) end
	end)
end

-- The Guild module calls this when a snapshot learns its lockout ID.
function A.OnLockout(snap)
	if not (snap and snap.attKey and snap.lockoutId) then return end
	if snap.attKey:sub(1, 2) ~= "w:" then return end
	adoptId(snap.attKey, snap.lockoutId)
	Okanvil:Trace("ATT", "lockout id " .. tostring(snap.lockoutId) .. " for " .. snap.attKey)
	snap.attKey = idKey(snap.lockoutId)
	if A.onChange then A.onChange() end
end

-- Runs, newest first.
function A.Runs()
	local list = {}
	for _, r in pairs(A.DB().runs) do list[#list + 1] = r end
	table.sort(list, function(a, b) return (a.first or 0) > (b.first or 0) end)
	return list
end

-- ------------------------------------------------------------
-- Mains: the guild roster with alts folded away (rank index 4, "alt" in the rank
-- name, or a "<Main> alt" note -- the same rule the site uses). Level 80 only.
-- ------------------------------------------------------------
function A.Mains()
	local out = {}
	if not (IsInGuild and IsInGuild()) then return out end
	Okanvil:WithFullRoster(function(total)
		for i = 1, total do
			local name, rankName, rankIndex, level, _, _, _, _, _, _, classToken = GetGuildRosterInfo(i)
			if name and (level or 0) >= 80 then
				name = stripRealm(name)
				local alt = rankIndex == 4 or (rankName or ""):lower():find("alt", 1, true)
					or Okanvil.U.mainOf(name)
				if not alt then
					out[#out + 1] = { name = name, rankIndex = rankIndex or 99, rankName = rankName or "",
						class = classToken or "" }
				end
			end
		end
	end)
	table.sort(out, function(a, b)
		if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
		return a.name < b.name
	end)
	return out
end

-- The main a raider counts for: their main when they are on an alt.
local function mainKey(n)
	return (Okanvil.U.mainOf(n) or n):lower()
end

-- Nights of a run that each main was in: { [mainLower] = count }.
function A.Presence(run)
	local seen = {}
	for _, night in ipairs(run.nights or {}) do
		local here = {}
		for _, p in ipairs(night.players or {}) do here[mainKey(p.n)] = true end
		for k in pairs(here) do seen[k] = (seen[k] or 0) + 1 end
	end
	return seen
end

-- ------------------------------------------------------------
-- Export for the site: one line, only nights not exported yet (all of them when
-- nothing is new, so it can always be re-sent -- the site skips what it has).
-- ------------------------------------------------------------
function A.ExportLine()
	local esc = Okanvil.U.esc
	local runs = A.Runs()
	local anyNew = false
	for _, r in ipairs(runs) do
		for _, n in ipairs(r.nights) do if not n.exportedAt then anyNew = true end end
	end
	-- every recorded run goes: the site's Raids tab lists them all, and its
	-- attendance picks the mandatory ones by the rules
	local out, count = {}, 0
	for _, r in ipairs(runs) do
		local nights = {}
		for _, n in ipairs(r.nights) do
			if not anyNew or not n.exportedAt then
				local ps = {}
				for _, p in ipairs(n.players) do
					ps[#ps + 1] = ('{"n":"%s","c":"%s","g":%d,"s":"%s"}'):format(esc(p.n), esc(p.c),
						tonumber(p.g) or 0, esc(p.s or ""))
				end
				nights[#nights + 1] = ('{"date":"%s","t":%d,"recorder":"%s","players":[%s]}')
					:format(n.date, n.t or 0, esc(n.recorder or ""), table.concat(ps, ","))
				n.exportedAt = time()
				count = count + 1
			end
		end
		if #nights > 0 then
			out[#out + 1] = ('{"lockoutId":%s,"zone":"%s","size":%d,"difficulty":%d,"week":"%s","test":%s,"nights":[%s]}')
				:format(r.lockoutId and tostring(r.lockoutId) or "null", esc(r.zone or ""), r.size or 0,
					r.difficulty or 0, r.week or "", r.test and "true" or "false", table.concat(nights, ","))
		end
	end
	-- every letter still kept: small, and the site keeps each only once
	local letters, nl = {}, 0
	for _, l in pairs(A.Letters.Inbox()) do
		letters[#letters + 1] = ('{"n":"%s","z":"%s","size":%d,"id":%s,"week":"%s"}')
			:format(esc(l.n), esc(l.z), l.size or 0, tostring(l.id), l.week or "")
		nl = nl + 1
	end
	local clears = {}
	for _, c in pairs(A.DB().cleared or {}) do
		clears[#clears + 1] = ('{"week":"%s","n":"%s","reason":"%s","by":"%s","on":%s}')
			:format(c.week, esc(c.n), esc(c.reason or ""), esc(c.by or ""), c.on and "true" or "false")
	end
	local ours = {}
	local ids = A.DB().ourIds or {}
	for key, o in pairs(ids) do
		-- keyed "week|raid"; older entries were keyed by the week alone and meant ICC 25
		-- (skipped once the same week has its new-style entry: one ID, not two lines)
		local week, ref = key:match("^([^|]+)|?(.*)$")
		if ref == "" and ids[week .. "|ICC25"] then ref = nil end
		if ref then ours[#ours + 1] = ('{"week":"%s","raid":"%s","id":%s,"by":"%s"}'):format(week, esc(ref ~= "" and ref or "ICC25"),
			tostring(o.id), esc(o.by or "")) end
	end
	-- the Rules ride along, so the site counts the raids the officers picked in game
	local r = A.Rules()
	local function refs(list)
		local q = {}
		for i, ref in ipairs(list) do q[i] = '"' .. esc(ref) .. '"' end
		return "[" .. table.concat(q, ",") .. "]"
	end
	local rules = ('{"must":%s,"extra":%s,"all":%s,"t":%d,"by":"%s"}'):format(refs(r.must), refs(r.extra),
		r.all and "true" or "false", r.t or 0, esc(r.by or ""))
	return "OKV1:ATT:{\"runs\":[" .. table.concat(out, ",") .. "],\"letters\":[" .. table.concat(letters, ",")
		.. "],\"ours\":[" .. table.concat(ours, ",") .. "],\"clears\":[" .. table.concat(clears, ",") .. "],\"rules\":"
		.. rules .. "}",
		count, anyNew, nl
end

-- ------------------------------------------------------------
-- What this client knows about one lockout week: who was in our runs, which IDs are
-- ours, and what each main's letters say. Per mandatory raid, then combined by the
-- rule (any one of them, or all of them):
--   present   -- in our run, or a toon of theirs is saved to our ID
--   elsewhere -- their MAIN is saved to another ID of a mandatory raid (the rule broken)
--   ten       -- their MAIN did an extra raid that week (guild or pug) = its size
-- A main in none of these is "no word": absent, or no Okanvil. That only lowers
-- the attendance %, it is not the list.
-- ------------------------------------------------------------
function A.Weeks(n)
	local out = {}
	for i = 0, n - 1 do out[#out + 1] = weekOf(time() - i * 7 * 86400) end
	return out
end

function A.RunOfWeek(week, ref)
	for _, r in ipairs(A.Runs()) do
		if r.week == week and not r.test and refOf(r.zone, r.size, r.difficulty) == ref then return r end
	end
end

-- Our ID of one mandatory raid for a week: the recorded run's, else the one an
-- officer set, else the one most mains' letters agree on (3 at least, so two
-- friends in the same pug are not "the guild").
function A.OurId(week, ref)
	local r = A.RunOfWeek(week, ref)
	if r and r.lockoutId then return r.lockoutId, "run" end
	local ids = A.DB().ourIds or {}
	local set = ids[week .. "|" .. ref] or (ref == "ICC25" and ids[week])
	if set then return set.id, "officer", set.by end
	local short, size = A.ParseRef(ref)
	local votes, best, bestN = {}, nil, 0
	for _, l in pairs(A.Letters.Inbox()) do
		if l.week == week and l.z == short and l.size == size then
			votes[l.id] = (votes[l.id] or 0) + 1
			if votes[l.id] > bestN then best, bestN = l.id, votes[l.id] end
		end
	end
	if bestN >= 3 then return best, "letters" end
end

-- ------------------------------------------------------------
-- Clearances: an officer's OK for a main saved elsewhere (real life, sick, told us
-- before). Kept per week; an undo is stored too (on = false) so it syncs like a
-- change, and the newer word wins when officers merge.
-- ------------------------------------------------------------
local function clearKey(week, name) return week .. "|" .. name:lower() end

function A.Clearance(week, name)
	local c = A.DB().cleared and A.DB().cleared[clearKey(week, name)]
	return (c and c.on) and c or nil
end

function A.SetClearance(week, name, reason)
	local a = A.DB()
	a.cleared = a.cleared or {}
	a.cleared[clearKey(week, name)] = { week = week, n = name, reason = reason or "", by = UnitName("player") or "",
		t = time(), on = reason ~= nil }
	Okanvil:Trace("ATT", ("clear %s %s: %s"):format(week, name, tostring(reason)))
	if A.Letters and A.Letters.ShareClear then A.Letters.ShareClear(a.cleared[clearKey(week, name)]) end
	if A.onChange then A.onChange() end
end

function A.WeekView(week)
	local rules = A.Rules()
	local v = { week = week, present = {}, elsewhere = {}, awayRef = {}, hits = {}, ten = {}, heard = {},
		letter = {}, raids = {} }
	local byRef = {}
	for i, ref in ipairs(rules.must) do
		local R = { ref = ref, run = A.RunOfWeek(week, ref), present = {}, away = {} }
		R.ours, R.source, R.setBy = A.OurId(week, ref)
		if R.run then for k in pairs(A.Presence(R.run)) do R.present[k] = true end end
		v.raids[i], byRef[ref] = R, R
		if R.run or R.ours then v.known = true end
	end
	for _, l in pairs(A.Letters.Inbox()) do
		if l.week == week then
			local main = mainKey(l.n)
			local onMain = main == l.n:lower()
			local ref = (l.z or "") .. (l.size or "")
			local R = byRef[ref]
			v.heard[main] = true
			if R then
				if R.ours and l.id == R.ours then R.present[main] = true
				elseif R.ours and onMain then R.away[main] = l.id; v.letter[main] = l end
			elseif onMain and inList(rules.extra, ref) then
				v.ten[main] = l.size
			end
		end
	end
	-- The extra-raid snapshots this client took itself: a guild run you were in
	-- counts for every main in it, with a letter or without (no Okanvil).
	for _, s in ipairs((Okanvil.db.guild and Okanvil.db.guild.snapshots) or {}) do
		local ref = refOf(s.zone, s.groupSize, s.difficulty)
		if ref and inList(rules.extra, ref) and s.t and weekOf(s.t) == week then
			for _, pl in ipairs(s.players or {}) do
				local n = stripRealm(pl.name)
				local main = n ~= "" and mainKey(n)
				if main and main == n:lower() then v.ten[main] = s.groupSize end
			end
		end
	end
	-- combine by the rule: in with us once they are in enough of the mandatory raids
	for _, R in ipairs(v.raids) do
		for k in pairs(R.present) do v.hits[k] = (v.hits[k] or 0) + 1; R.away[k] = nil end
	end
	local need = rules.all and #v.raids or 1
	for k, n in pairs(v.hits) do if n >= need then v.present[k] = true end end
	for _, R in ipairs(v.raids) do
		for k, id in pairs(R.away) do
			if not v.present[k] and not v.elsewhere[k] then v.elsewhere[k], v.awayRef[k] = id, R.ref end
		end
	end
	return v
end

-- ------------------------------------------------------------
-- Page: three pills. "Main run" is the rule (the mandatory raids); "Extra raids" is
-- the effort report; "Rules" is where the officers pick both.
-- Laid out like the approved mock: soft boxes with a header strip, the Saved Raids
-- chips ("25" / "10" in a thin gold frame) for each week, mains grouped by rank
-- with a coloured [tag].
-- ------------------------------------------------------------
local function classHex(token)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	if c then return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
	return "|cffdcddde"
end

local WEEKS = 4
local NAME_X, CELL_X, CELL_W = 44, 190, 84
local PAD = 10
local FLAT = "Interface\\Buttons\\WHITE8X8"
local MORE_NAMES = 24

-- chip looks (the approved mock): border rgb + text colour on a dark well. Came =
-- the Saved Raids gold frame; didn't come = a faint empty box with a dash.
local CHIP = {
	with  = { 0.75, 0.58, 0.23, "|cffdcddde" },   -- came
	empty = { 0.24, 0.22, 0.19, "|cff5e6166" },   -- didn't come / not yet (open week)
	away  = { 0.70, 0.24, 0.24, "|cffff6b6b" },   -- saved elsewhere
	clear = { 0.24, 0.52, 0.30, "|cff7cfc8a" },   -- saved elsewhere, cleared by an officer
	ten   = { 0.24, 0.52, 0.30, "|cff7cfc8a" },   -- 10-man on the main
}

local CLEAR_REASONS = { "Told us before", "Real life", "Sick", "Other" }

local function weekLabel(w)
	local y, m, d = w:match("(%d+)-(%d+)-(%d+)")
	return y and date("%d %b", time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })) or w
end

local function rankHex(idx)
	return "|c" .. (Okanvil.U.rankColor and Okanvil.U.rankColor(idx) or "ff8a8d93")
end
-- "Warchief Rat" -> "[WR]", in the rank's own colour (the same scale Home uses)
local function rankTag(m)
	local ab = (m.rankName or ""):gsub("(%a)%a*[%s%p]*", "%1"):upper():sub(1, 2)
	if ab == "" then ab = "?" end
	return rankHex(m.rankIndex) .. "[" .. ab .. "]|r"
end
local function nameOf(m) return classHex(m.class) .. m.name .. "|r" end
local function tagName(m) return rankTag(m) .. " " .. nameOf(m) end

-- one Saved-Raids chip
local function newChip(parent)
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(34, 20)
	c:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
	c:SetBackdropColor(0, 0, 0, 0.25)
	c.t = W.FixedText(c, "", "note")
	c.t:SetPoint("CENTER", 0, 0)
	return c
end
local function setChip(c, kind, label)
	if not kind then c:Hide(); return end
	local k = CHIP[kind]
	c:SetBackdropBorderColor(k[1], k[2], k[3], 1)
	c:SetBackdropColor(0, 0, 0, 0.35)
	c.t:SetText(k[4] .. label .. "|r")
	c:Show()
end

-- A tab page: boxes, texts and row pools laid top-down. Everything is re-anchored
-- on each refresh, so the pools only ever grow.
local function newPage(page)
	local P = { page = page, texts = {}, rows = {}, boxes = {}, heads = {}, tiles = {}, y = 0, w = 400, nRow = 0 }
	local base = page:GetFrameLevel()

	function P:Text(key, x, size, role)
		local t = self.texts[key]
		if not t then
			t = W.Text(page, "", size or "body", role)
			t:SetJustifyH("LEFT")
			if t.SetWordWrap then t:SetWordWrap(true) end
			self.texts[key] = t
		end
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", x, -self.y)
		t:SetWidth(self.w - x - PAD)
		t:Show()
		return t
	end
	-- wrapped text that takes exactly the height it needs (no "..." cut-off)
	function P:Para(key, text, size, role, gap)
		local t = self:Text(key, PAD, size, role)
		t:SetText(text)
		local h = t:GetStringHeight()
		t:SetHeight(h + 2)
		self.y = self.y + h + (gap or 10)
		return t
	end
	-- a section: no box, the pages' own heading (W.Section's look) -- a small dim
	-- title, a hairline running to the dim meta on the right
	function P:BoxStart(key, title, meta)
		local b = self.boxes[key]
		if not b then
			b = W.Frame(page, "bare")
			b:SetFrameLevel(base)
			b.title = W.Text(b, "", "note", "dim")
			b.title:SetPoint("TOPLEFT", PAD, -4)
			b.meta = W.Text(b, "", "note", "dim")
			b.meta:SetPoint("TOPRIGHT", -PAD, -4)
			local rule = b:CreateTexture(nil, "ARTWORK")
			rule:SetTexture(FLAT); rule:SetVertexColor(C.border[1], C.border[2], C.border[3], 1)
			rule:SetHeight(1)
			rule:SetPoint("LEFT", b.title, "RIGHT", 8, 0); rule:SetPoint("RIGHT", b.meta, "LEFT", -8, 0)
			self.boxes[key] = b
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 0, -self.y); b:SetPoint("RIGHT", page, "RIGHT", 0, 0)
		b.title:SetText(title)
		b.meta:SetText(meta or "")
		b.top = self.y
		b:Show()
		self.y = self.y + 26
		return b
	end
	function P:BoxEnd(key)
		local b = self.boxes[key]
		b:SetHeight(self.y - b.top + 4)
		self.y = self.y + 18
	end
	-- the week tally: four framed numbers across the box
	function P:Tally(items)
		local n = #items
		local gap = 8
		local w = (self.w - 2 * PAD - (n - 1) * gap) / n
		for i, it in ipairs(items) do
			local t = self.tiles[i]
			if not t then
				t = CreateFrame("Frame", nil, page)
				t:SetFrameLevel(base + 2)
				t:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
				t:SetBackdropColor(0, 0, 0, 0.2)
				t:SetBackdropBorderColor(0.18, 0.17, 0.15, 1)
				t.num = W.Text(t, "", "title"); t.num:SetPoint("LEFT", 10, 0)
				t.lbl = W.Text(t, "", "note", "dim"); t.lbl:SetPoint("LEFT", t.num, "RIGHT", 8, -1)
				self.tiles[i] = t
			end
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", PAD + (i - 1) * (w + gap), -self.y)
			t:SetSize(w, 30)
			t.num:SetText(it[1]); t.lbl:SetText(it[2])
			t:Show()
		end
		self.y = self.y + 40
	end
	function P:Row()
		self.nRow = self.nRow + 1
		local row = self.rows[self.nRow]
		if not row then
			row = W.Frame(page, "row"); row:SetHeight(26)
			row:SetFrameLevel(base + 2)
			row.tag = W.Text(row, "", "note"); row.tag:SetPoint("LEFT", PAD, 0)
			row.nm = W.Text(row, "", "label"); row.nm:SetPoint("LEFT", NAME_X, 0)
			row.mid = W.Text(row, "", "label"); row.mid:SetPoint("LEFT", CELL_X, 0)
			row.cells = {}
			for c = 1, WEEKS do
				row.cells[c] = { a = newChip(row), b = newChip(row), dot = W.Text(row, "", "label") }
			end
			row.last = W.Text(row, "", "label"); row.last:SetPoint("RIGHT", -PAD, 0)
			row.btn = W.Button(row, "Clear"):Size(64, 18)
			row.btn:SetPoint("RIGHT", -PAD, 0)
			self.rows[self.nRow] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PAD - 4, -self.y); row:SetPoint("RIGHT", page, "RIGHT", -(PAD - 4), 0)
		row.tag:SetText(""); row.nm:SetText(""); row.mid:SetText(""); row.last:SetText("")
		row.last:ClearAllPoints(); row.last:SetPoint("RIGHT", -PAD, 0)
		-- the week columns spread over the width the page has (see P:Begin)
		for i, c in ipairs(row.cells) do
			local x = CELL_X + (i - 1) * self.cellW
			c.a:ClearAllPoints(); c.a:SetPoint("LEFT", x, 0)
			c.b:ClearAllPoints(); c.b:SetPoint("LEFT", x + 38, 0)
			c.dot:ClearAllPoints(); c.dot:SetPoint("LEFT", x + 14, 0)
			c.a:Hide(); c.b:Hide(); c.dot:SetText("")
		end
		row.btn:Hide()
		row:Show()
		self.y = self.y + 27
		return row
	end
	-- column heads: one per week + the last column's label
	function P:Heads(key, labels, last)
		local h = self.heads[key]
		if not h then
			h = { cells = {} }
			for c = 1, WEEKS do h.cells[c] = W.Text(page, "", "note", "dim") end
			h.last = W.Text(page, "", "note", "dim")
			self.heads[key] = h
		end
		for c = 1, WEEKS do
			h.cells[c]:ClearAllPoints()
			h.cells[c]:SetPoint("TOPLEFT", PAD - 4 + CELL_X + (c - 1) * self.cellW, -self.y)
			h.cells[c]:SetText(labels[c] or "")
			h.cells[c]:Show()
		end
		h.last:ClearAllPoints(); h.last:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD - 6, -self.y)
		h.last:SetText(last or ""); h.last:Show()
		self.y = self.y + 18
	end
	function P:Begin(width)
		for _, r in ipairs(self.rows) do r:Hide() end
		for _, b in pairs(self.boxes) do b:Hide() end
		for _, t in pairs(self.texts) do t:Hide() end
		for _, t in ipairs(self.tiles) do t:Hide() end
		for _, set in pairs(self.sortBtns or {}) do for _, b in ipairs(set) do b:Hide() end end
		for _, r in ipairs(self.ruleRows or {}) do r:Hide() end
		if self.allRow then self.allRow:Hide() end
		for _, h in pairs(self.heads) do
			for _, c in ipairs(h.cells) do c:Hide() end
			h.last:Hide()
		end
		self.nRow = 0
		self.w = math.max(width or 400, 300)
		-- week columns share what is left between the names and the last column
		-- (the % / verdict), instead of bunching up on the left of a wide page
		self.cellW = math.max(CELL_W, math.floor((self.w - CELL_X - 110) / WEEKS))
		self.y = 4
	end
	return P
end

-- mains in rank order, then class, then name
local function sortMains(list)
	table.sort(list, function(a, b)
		if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
		if (a.class or "") ~= (b.class or "") then return (a.class or "") < (b.class or "") end
		return a.name < b.name
	end)
	return list
end

-- rows with a rank heading at each change of rank
-- flat = one list with no rank headings (sorted by something other than rank)
local function rankedRows(P, key, mains, fill, flat)
	local lastRank
	local counts = {}
	for _, m in ipairs(mains) do counts[m.rankIndex] = (counts[m.rankIndex] or 0) + 1 end
	for i, m in ipairs(mains) do
		if not flat and m.rankIndex ~= lastRank then
			lastRank = m.rankIndex
			P:Para(key .. "rk" .. i, rankHex(m.rankIndex) .. (m.rankName or "?"):upper() .. "|r  |cff5e6166"
				.. counts[m.rankIndex] .. "|r", "note", nil, 4)
		end
		local row = P:Row()
		row.tag:SetText(rankTag(m))
		row.nm:SetText(nameOf(m))
		fill(row, m)
	end
end

-- The order of a grid: by rank (the default, with rank headings), by the grid's own
-- number -- most active first, so a busy Sewer Rat is not at the bottom of a long
-- list -- or by name. The pick is remembered per grid.
local SORTS = {
	main = { { "rank", "Rank" }, { "num", "Attendance" }, { "name", "Name" } },
	ten  = { { "rank", "Rank" }, { "num", "Effort" },     { "name", "Name" } },
}
local function sortOf(key)
	local s = A.DB().sort
	return (s and s[key]) or "rank"
end

-- The sort buttons, on their own line inside the box.
local function sortBar(P, key)
	P.sortBtns = P.sortBtns or {}
	local set = P.sortBtns[key]
	if not set then
		set = {}
		for i, o in ipairs(SORTS[key]) do
			local b = W.Button(P.page, o[2], "tab"):Size(84, 20)
			b:SetFrameLevel(P.page:GetFrameLevel() + 3)
			b:SetScript("OnClick", function()
				local a = A.DB()
				a.sort = a.sort or {}
				a.sort[key] = o[1]
				if A.onChange then A.onChange() end
			end)
			set[i] = b
		end
		P.sortBtns[key] = set
	end
	local cur = sortOf(key)
	local lbl = P:Text(key .. "sortL", PAD, "note", "dim")
	lbl:SetText("Sort"); lbl:SetHeight(20)
	for i, o in ipairs(SORTS[key]) do
		local b = set[i]
		b:ClearAllPoints(); b:SetPoint("TOPLEFT", PAD + 34 + (i - 1) * 90, -P.y)
		if b.SetKind then b:SetKind(cur == o[1] and "tabOn" or "tab") end
		b:Show()
	end
	P.y = P.y + 28
end

-- Sort mains by the pick. num(m) is the grid's number (higher = more active); ties
-- fall back to rank, then name. Returns flat = true when rank headings do not apply.
local function sortBy(key, list, num)
	local how = sortOf(key)
	if how == "rank" then return list, false end
	table.sort(list, function(a, b)
		if how == "num" then
			local x, y = num(a), num(b)
			if x ~= y then return x > y end
			if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
		end
		return a.name < b.name
	end)
	return list, true
end

-- the first names in full, the rest as "+ N more"
local function someNames(list)
	local out = {}
	for i = 1, math.min(#list, MORE_NAMES) do out[#out + 1] = tagName(list[i]) end
	local s = table.concat(out, "|cff5e6166 · |r")
	if #list > MORE_NAMES then s = s .. "|cff8a8d93  + " .. (#list - MORE_NAMES) .. " more|r" end
	return s
end

-- The text in a week's chip: the mandatory raid's size ("25"), or with more than
-- one mandatory raid, how many of them the main was in with us ("1/2").
local function mustChip(v, k)
	local n = #v.raids
	if n == 1 then local _, size = A.ParseRef(v.raids[1].ref); return tostring(size or "") end
	return (v.hits[k] or 0) .. "/" .. n
end

local function buildMainTab(P, width)
	P:Begin(width)
	if #A.Rules().must == 0 then
		P:BoxStart("this", "NO MANDATORY RAID YET", "")
		P:Para("thisB", "|cff8a8d93Nothing is mandatory until an officer picks the raid(s) a main has to do in our ID, on the Rules pill.|r", "body", nil, 8)
		P:BoxEnd("this")
		return P.y + 6
	end
	local weeks = A.Weeks(WEEKS)
	local views = {}
	for i, w in ipairs(weeks) do views[i] = A.WeekView(w) end
	local cur = views[1]
	local mains = sortMains(A.Mains())
	local known = cur.known
	local multi = #cur.raids > 1

	-- who is where this week
	local nWith, away, nOpen, quiet = 0, {}, 0, {}
	for _, m in ipairs(mains) do
		local k = m.name:lower()
		if cur.present[k] then nWith = nWith + 1
		elseif cur.elsewhere[k] then away[#away + 1] = m
		elseif known then nOpen = nOpen + 1; quiet[#quiet + 1] = m end
	end

	-- this lockout
	local function idText(R)
		return R.ours and ("ID " .. R.ours .. (R.setBy and ("  ·  set by " .. R.setBy) or "")) or "no ID yet"
	end
	local meta = multi and A.MustLabel() or (A.RefLabel(cur.raids[1].ref) .. "  ·  " .. idText(cur.raids[1]))
	P:BoxStart("this", "THIS LOCKOUT  |cff8a8d93week of " .. weekLabel(cur.week) .. "|r", meta)
	local lines, noId = {}, false
	for _, R in ipairs(cur.raids) do
		if multi then
			lines[#lines + 1] = "|cffe0b860" .. A.RefLabel(R.ref) .. "|r   |cff8a8d93" .. idText(R) .. "|r"
		end
		if R.run then
			for _, n in ipairs(R.run.nights) do
				lines[#lines + 1] = "|cffdcddde" .. date("%a %d %b", n.t) .. "|r   |cff8a8d93" .. #n.players
					.. " players  ·  recorded by " .. (n.recorder or "?") .. "  ·  "
					.. (n.exportedAt and "exported" or "|cffe0b860not exported|r") .. "|r"
			end
		end
		if not R.ours then
			noId = true
		elseif R.source ~= "run" then
			lines[#lines + 1] = "|cff6f7176" .. (multi and (A.RefLabel(R.ref) .. ": ") or "") .. "our ID comes from the "
				.. (R.source == "officer" and "officer's own lockout." or "raiders' letters (3+ agree).") .. "|r"
		end
	end
	if noId then
		lines[#lines + 1] = "|cff8a8d93Our ID is known after the first kill, when an officer who raided with us presses "
			.. "Our ID = mine, or once 3 raiders' letters agree.|r"
	end
	if #lines > 0 then P:Para("thisB", table.concat(lines, "\n"), "body", nil, 8) end
	-- the open week can still fill up on night 2: "no word" only once it's over
	local isOpen = true
	P:Tally({
		{ "|cffe0b860" .. nWith .. "|r", "with us" },
		{ "|cffff6b6b" .. #away .. "|r", "saved elsewhere" },
		{ "|cffe6b866" .. (isOpen and nOpen or 0) .. "|r", known and "open · can still come" or "open" },
		{ "|cff5e6166" .. (known and 0 or #mains) .. "|r", known and "no word" or "no data yet" },
	})
	P:BoxEnd("this")

	-- saved elsewhere, each with the officer's Clear
	P:BoxStart("away", "|cffff6b6bSAVED ELSEWHERE|r", "bottom of loot prio unless an officer clears it")
	if #away == 0 then
		P:Para("awayE", "|cff7cfc8aNobody, as far as the letters say.|r", "body", nil, 6)
	else
		for _, m in ipairs(away) do
			local k = m.name:lower()
			local row = P:Row()
			row.tag:SetText(rankTag(m)); row.nm:SetText(nameOf(m))
			local cl = A.Clearance(cur.week, m.name)
			if cl then
				row.mid:SetText("|cff7cfc8aCleared|r |cff8a8d93· " .. (cl.reason or "") .. " · by " .. (cl.by or "?") .. "|r")
			else
				row.mid:SetText("|cffdcdddelocked to " .. (multi and (A.RefLabel(cur.awayRef[k]) .. " ") or "")
					.. "ID |r|cffff6b6b" .. tostring(cur.elsewhere[k]) .. "|r")
			end
			local l = cur.letter and cur.letter[k]
			row.last:ClearAllPoints(); row.last:SetPoint("RIGHT", row.btn, "LEFT", -12, 0)
			row.last:SetText(l and ("|cff8a8d93letter · " .. date("%a %d %b", l.t or time()) .. "|r") or "")
			row.btn:SetText(cl and "Undo" or "Clear")
			row.btn.listFn = function()
				local items = {}
				for _, r in ipairs(CLEAR_REASONS) do items[#items + 1] = { text = r, value = r } end
				return items
			end
			row.btn.setFn = function(reason) A.SetClearance(cur.week, m.name, reason) end
			row.btn:SetScript("OnClick", function(b)
				if A.Clearance(cur.week, m.name) then A.SetClearance(cur.week, m.name, nil)
				elseif W.OpenMenu then W.OpenMenu(b) end
			end)
			row.btn:Tooltip(cl and "Put them back on the list" or "They talked to an officer (real life, sick...): no penalty")
			row.btn:Show()
		end
	end
	P:BoxEnd("away")

	-- the grid: every main, once any week has data
	local anyData = false
	for _, v in ipairs(views) do if v.known then anyData = true end end
	local ch = multi and ("1/" .. #cur.raids) or mustChip(cur, "")
	P:BoxStart("grid", "MAINS  ·  LAST " .. WEEKS .. " WEEKS",
		"|cffdcddde" .. ch .. "|r came   |cff5e6166–|r didn't come   |cffff6b6b" .. ch .. "|r saved elsewhere   |cff7cfc8a"
		.. ch .. "|r cleared")
	if not anyData then
		P:Para("gridB", "|cff8a8d93No main run or letters in the last " .. WEEKS .. " weeks yet: "
			.. #mains .. " mains waiting for data.|r", "body", nil, 6)
	else
		local labels = {}
		for c, v in ipairs(views) do
			labels[c] = v.known and weekLabel(v.week) or ("|cff5e6166" .. weekLabel(v.week) .. "|r")
		end
		-- % with us: every week with data counts, except the open week unless they came
		local function pctOf(m)
			local k = m.name:lower()
			local came, counted = 0, 0
			for c, v in ipairs(views) do
				if v.present[k] then came = came + 1; counted = counted + 1
				elseif v.elsewhere[k] then counted = counted + 1
				elseif v.known and c ~= 1 then counted = counted + 1 end
			end
			return counted > 0 and math.floor(100 * came / counted + 0.5) or nil
		end
		sortBar(P, "main")
		local list, flat = sortBy("main", mains, function(m) return pctOf(m) or -1 end)
		P:Heads("gridH", labels, "with us")
		rankedRows(P, "grid", list, function(row, m)
			local k = m.name:lower()
			for c, v in ipairs(views) do
				local cell = row.cells[c]
				local cleared = A.Clearance(v.week, m.name)
				if v.present[k] then setChip(cell.a, "with", mustChip(v, k))
				elseif v.elsewhere[k] then setChip(cell.a, cleared and "clear" or "away", mustChip(v, k))
				elseif v.known then
					-- "all of them" and in only some: the count, dim, instead of a bare dash
					setChip(cell.a, "empty", (v.hits[k] or 0) > 0 and mustChip(v, k) or "–")
				end
			end
			local pct = pctOf(m)
			row.last:SetText(not pct and "|cff5e6166--|r"
				or ((pct >= 75 and "|cff7cfc8a" or pct >= 50 and "|cffe0b860" or "|cffff6b6b") .. pct .. "%|r"))
		end, flat)
	end
	P:BoxEnd("grid")
	return P.y + 6
end

local function buildTenTab(P, width)
	P:Begin(width)
	local weeks = A.Weeks(WEEKS)
	local views = {}
	for i, w in ipairs(weeks) do views[i] = A.WeekView(w) end
	local mains = sortMains(A.Mains())
	local shown, nHeard = {}, 0
	for _, m in ipairs(mains) do
		local k = m.name:lower()
		local w25, w10, heard = 0, 0, false
		for _, v in ipairs(views) do
			if v.heard[k] then heard = true end
			if v.present[k] then w25 = w25 + 1 end
			if v.ten[k] then w10 = w10 + 1 end
		end
		m._w25, m._w10 = w25, w10
		if heard then nHeard = nHeard + 1 end
		if heard or w25 > 0 or w10 > 0 then shown[#shown + 1] = m end
	end
	local n25 = 0
	for _, m in ipairs(shown) do if m._w10 == 0 and m._w25 >= 2 then n25 = n25 + 1 end end

	local rules = A.Rules()
	local ours = A.MustLabel()
	local hasExtra = #rules.extra > 0
	-- Title + one number. The chips say the rest (gold = ours, green = extra), and
	-- how many mains the page can see is the only thing worth a line.
	P:BoxStart("ten", "EXTRA RAIDS  |cff8a8d93last " .. WEEKS .. " weeks|r",
		nHeard .. "/" .. #mains .. " mains with Okanvil")
	if not hasExtra then
		P:Para("tenE", "|cff8a8d93No extra raids chosen yet: pick them on the Rules pill.|r", "body", nil, 6)
	elseif #shown == 0 then
		P:Para("tenE", "|cff8a8d93Nothing yet.|r", "body", nil, 6)
	else
		local labels = {}
		for c, v in ipairs(views) do labels[c] = weekLabel(v.week) end
		sortBar(P, "ten")
		-- effort = weeks with an extra raid, then weeks with us
		local list, flat = sortBy("ten", shown, function(m) return m._w10 * 10 + m._w25 end)
		P:Heads("tenH", labels, "verdict")
		rankedRows(P, "ten", list, function(row, m)
			local k = m.name:lower()
			for c, v in ipairs(views) do
				local cell = row.cells[c]
				if v.present[k] then setChip(cell.a, "with", mustChip(v, k)) end
				if v.ten[k] then
					local size = tostring(v.ten[k])
					if v.present[k] then setChip(cell.b, "ten", size) else setChip(cell.a, "ten", size) end
				end
			end
			row.last:SetText(m._w10 > 0 and "|cff7cfc8aeffort|r"
				or m._w25 >= 2 and "|cffff6b6bours only|r" or "|cff8a8d93little data|r")
		end, flat)
	end
	P:BoxEnd("ten")

	return P.y + 6
end

-- The Rules pill: one row per raid, a 10 and a 25 button each saying what that
-- raid counts as (Our ID / Extra / -); a click opens the menu to change it. Then
-- the "every mandatory raid" switch.
local KIND_TEXT = { must = "|cffe0b860Our ID|r", extra = "|cff7cfc8aExtra|r" }
local RULE_MENU = {
	{ text = "Not counted",        value = "none" },
	{ text = "Our ID (mandatory)", value = "must" },
	{ text = "Extra effort",       value = "extra" },
}
local RULE_X, RULE_W = 260, 110

local function ruleRows(P)
	P.ruleRows = P.ruleRows or {}
	local level = P.page:GetFrameLevel() + 2
	-- column heads
	local h10 = P:Text("rh10", RULE_X + PAD - 4, "note", "dim"); h10:SetText("10-man"); h10:SetWidth(RULE_W - 10)
	h10:SetJustifyH("CENTER")
	local h25 = P:Text("rh25", RULE_X + RULE_W + PAD - 4, "note", "dim"); h25:SetText("25-man"); h25:SetWidth(RULE_W - 10)
	h25:SetJustifyH("CENTER")
	P.y = P.y + 18
	for i, raid in ipairs(A.RuleRaids()) do
		local row = P.ruleRows[i]
		if not row then
			row = W.Frame(P.page, "row"); row:SetHeight(26); row:SetFrameLevel(level)
			row.nm = W.Text(row, "", "label"); row.nm:SetPoint("LEFT", PAD, 0)
			row.btns = {}
			for s, size in ipairs({ 10, 25 }) do
				local b = W.Button(row, ""):Size(RULE_W - 10, 20)
				b:SetPoint("LEFT", RULE_X + (s - 1) * RULE_W, 0)
				b.listFn = function() return RULE_MENU end
				b:SetScript("OnClick", function(self) if W.OpenMenu then W.OpenMenu(self) end end)
				row.btns[size] = b
			end
			P.ruleRows[i] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PAD - 4, -P.y); row:SetPoint("RIGHT", P.page, "RIGHT", -(PAD - 4), 0)
		row.nm:SetText("|cffdcddde" .. raid.name .. "|r")
		for _, size in ipairs({ 10, 25 }) do
			local b, ref = row.btns[size], raid.short .. size
			local kind = A.IsMust(ref) and "must" or A.IsExtra(ref) and "extra" or nil
			b.text:SetText(KIND_TEXT[kind] or "|cff5e6166–|r")
			b.setFn = function(v) A.SetRule(ref, v ~= "none" and v or nil) end
			b:Show()
		end
		row:Show()
		P.y = P.y + 27
	end
	P.y = P.y + 4
end

local function buildRulesTab(P, width)
	P:Begin(width)
	local rules = A.Rules()
	P:BoxStart("rules", "WHAT COUNTS", (rules.t or 0) > 0
		and ("set by " .. (rules.by or "?") .. "  ·  " .. date("%d %b %H:%M", rules.t)) or "not set yet")
	P:Para("rulesB", "|cffe0b860Our ID|r |cff8a8d93= mandatory.|r   |cff7cfc8aExtra|r |cff8a8d93= effort, "
		.. "information only.|r", "note", nil, 8)
	ruleRows(P)

	-- one line, one switch: only matters once two raids are mandatory
	local level = P.page:GetFrameLevel() + 2
	local all = P.allRow
	if not all then
		all = W.ToggleRow(P.page, "Require every mandatory raid",
			"Off: one of them in our ID is enough for the week. On: all of them.",
			function() return A.Rules().all end, function(v) A.SetMustAll(v) end)
		all:SetFrameLevel(level)
		P.allRow = all
	end
	P.y = P.y + 8
	all:ClearAllPoints()
	all:SetPoint("TOPLEFT", PAD, -P.y); all:SetPoint("RIGHT", P.page, "RIGHT", -PAD, 0)
	all.refresh()
	all:Show()
	P.y = P.y + all:GetHeight() + 4
	P:BoxEnd("rules")
	return P.y + 6
end

local BUILDERS = { main = buildMainTab, ten = buildTenTab, rules = buildRulesTab }

function Okanvil:BuildAttendance(host)
	local pages, dash = {}, nil
	local function refreshTab(key)
		local P = pages[key]
		local sf = P and dash and dash.pages[key]
		if not sf then return end
		local width = sf:GetWidth()
		if not width or width < 50 then width = host:GetWidth() - 30 end
		P.page:SetWidth(width)
		local h = BUILDERS[key](P, width)
		P.page:SetHeight(math.max(h, 50))
		sf._relayout()
	end
	dash = W.Dashboard(host, {
		title = "Attendance",
		subtitle = "Who raids in our ID, and who puts in extra effort",
		icon = (Okanvil.ICONS and Okanvil.ICONS.attendance) or "Interface\\Icons\\INV_Misc_PocketWatch_01",
		pills = true,
		drawerWidth = 0,
		footerHeight = 0,
		primaryText = function() return "Export for site" end,
		onPrimary = function()
			local line, n, fresh, nl = A.ExportLine()
			Okanvil:ShowCopyLine(line, "Attendance export",
				n .. (fresh and " new" or "") .. " nights  ·  " .. nl .. " letters  --  Ctrl+C, then Import on the "
				.. "site's Attendance page")
			if A.onChange then A.onChange() end
		end,
		onTertiary = function() A.SetOurIdFromMine() end,
		tertiaryText = function() return "Our ID = mine" end,
		tertiaryWidth = 120,
		tertiaryTip = "You raided with the guild this week: use this character's lockouts of the mandatory "
			.. "raids as the guild's IDs for the week.",
		statusText = function()
			local n = 0
			for _ in pairs(A.Letters.Inbox()) do n = n + 1 end
			return "|cff8a8d93" .. n .. " letter" .. (n == 1 and "" or "s") .. "|r"
		end,
		tabs = {
			{ key = "main", label = "Main run", height = 400,
			  build = function(page) pages.main = newPage(page) end },
			{ key = "ten", label = "Extra raids", height = 400,
			  build = function(page) pages.ten = newPage(page) end },
			{ key = "rules", label = "Rules", height = 400,
			  build = function(page) pages.rules = newPage(page) end },
		},
	})
	local shown = "main"
	local open = dash.OpenPage
	dash.OpenPage = function(key) shown = key; open(key); refreshTab(key) end
	for key, b in pairs(dash.tabBtns) do
		b:SetScript("OnClick", function() dash.OpenPage(key) end)
	end
	A.onChange = function()
		if host:IsVisible() then refreshTab(shown); dash:Refresh() end
	end
	host:HookScript("OnShow", function() refreshTab(shown); dash:Refresh() end)
	host:HookScript("OnSizeChanged", function() if host:IsVisible() then refreshTab(shown) end end)
	dash.OpenPage("main")
end

-- ------------------------------------------------------------
-- Register (officer-only page)
-- ------------------------------------------------------------
Okanvil_Plugins = Okanvil_Plugins or {}
Okanvil_Plugins[ADDON] = {
	title = "Attendance",
	desc  = "The guild's mandatory raids: who is in our ID, who got saved elsewhere, who does extra raids. "
		.. "Export for the web hub. Officers only.",
	icon  = (Okanvil.ICONS and Okanvil.ICONS.attendance) or "Interface\\Icons\\INV_Misc_PocketWatch_01",
	officerOnly = true,
	build = function(panel) Okanvil:BuildAttendance(panel) end,
}
if Okanvil and Okanvil.Register then
	Okanvil:Register(ADDON)
end
