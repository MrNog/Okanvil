-- ============================================================
-- Okanvil -- Guild (native core module, not a plugin).
-- Two exports for the RATS web hub:
--   * Roster export   -- the full guild roster as JSON (comp/guild importer).
--   * Attendance      -- a snapshot of the raid group at the first boss kill of the
--                        night (auto, MRT-style) or on demand, as JSON.
-- Attendance capture runs ALWAYS (core), so a raid is recorded even if you
-- never open the window.
-- ============================================================

local Okanvil = Okanvil
local G = {}
Okanvil.Guild = G

-- ------------------------------------------------------------
-- minimal JSON string escaper (WoW strings are UTF-8 -> raw is valid JSON)
-- ------------------------------------------------------------
local esc = Okanvil.U.esc
G.esc = esc

local function stripRealm(name)
	return (name or ""):gsub("%-.*$", "")
end

-- ------------------------------------------------------------
-- Roster export (absorbed from the old Okanvil-Guild plugin)
-- matches officer/guild importer:
--   { guildName, realm, exportedAt, ranks:[{name,rankIndex}], roster:[{...}] }
-- ------------------------------------------------------------
function G.BuildRosterJSON()
	local guildName = GetGuildInfo("player") or "Guild"
	local realm = GetRealmName() or ""
	local ranksSeen, ranks, members = {}, {}, {}
	-- Walk the FULL roster (online AND offline). GetNumGuildMembers() only counts ONLINE
	-- members unless "Show Offline" is forced on -- without this the export dropped every
	-- offline main (238 of them showed up as "Left the guild" on the hub). WithFullRoster
	-- toggles SetGuildRosterShowOffline for the duration and restores it after.
	Okanvil:WithFullRoster(function(total)
		for i = 1, total do
			-- 3.3.5 signature: name, rank, rankIndex, level, class, zone, note, officernote, online, status
			local name, rankName, rankIndex, level, class, _, note, officernote = GetGuildRosterInfo(i)
			if name then
				name = stripRealm(name)
				rankIndex = rankIndex or 0
				if not ranksSeen[rankIndex] then
					ranksSeen[rankIndex] = true
					table.insert(ranks, { idx = rankIndex, name = rankName or ("Rank " .. rankIndex) })
				end
				table.insert(members, string.format(
					'{"name":"%s","class":"%s","level":%d,"rankName":"%s","rankIndex":%d,"publicNote":"%s","officerNote":"%s"}',
					esc(name), esc(class), level or 0, esc(rankName), rankIndex, esc(note), esc(officernote)
				))
			end
		end
	end)
	table.sort(ranks, function(a, b) return a.idx < b.idx end)
	local ranksJson = {}
	for _, r in ipairs(ranks) do
		table.insert(ranksJson, string.format('{"name":"%s","rankIndex":%d}', esc(r.name), r.idx))
	end
	return string.format(
		'{"guildName":"%s","realm":"%s","exportedAt":%d,"ranks":[%s],"roster":[%s]}',
		esc(guildName), esc(realm), time(),
		table.concat(ranksJson, ","), table.concat(members, ",")
	), #members
end

-- Async roster export. The offline members are NOT in the client's cache until we ask
-- for them: SetGuildRosterShowOffline(true) + GuildRoster() kicks off a SERVER fetch,
-- and the full list only lands a few frames later on GUILD_ROSTER_UPDATE. A synchronous
-- BuildRosterJSON() therefore caught only the online members (12 of 250 -> the hub
-- read the missing 238 as "Left the guild"). So we force offline on, request a refresh,
-- and wait until at least one OFFLINE member shows up in the list before building.
-- cb(json, count) fires once the full list is ready (or after a timeout, so a guild that
-- really is all-online still exports).
function G.ExportRoster(cb)
	if not (IsInGuild and IsInGuild()) then
		local json, count = G.BuildRosterJSON()
		if cb then cb(json, count) end
		return
	end
	-- turn on Show Offline + request a fresh roster from the server; the player's
	-- own setting comes back in finish()
	Okanvil:ForceShowOffline()
	if GuildRoster then GuildRoster() end

	local After = Okanvil.Comms and Okanvil.Comms.After
	local attempts = 0
	local MAX_ATTEMPTS = 24          -- ~6s at 0.25s spacing
	-- 3.3.5a GetNumGuildMembers() returns ONE number (no online count), so "loaded" is
	-- read off the rows: the offline list has arrived once any row is not online.
	local function ready()
		local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
		for i = 1, total do
			local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
			if name and not online then return true end
		end
		return false
	end
	local function finish(loaded)
		local json, count = G.BuildRosterJSON()
		Okanvil:RestoreShowOffline()
		if not loaded then
			Okanvil:Print("Roster export: the offline members never loaded, so only " .. count
				.. " members are in it. /reload and export again.")
		end
		if cb then cb(json, count) end
	end
	local function poll()
		attempts = attempts + 1
		local ok = ready()
		if ok or attempts >= MAX_ATTEMPTS or not After then
			finish(ok)
			return
		end
		-- ask again until the offline members arrive (the flag stays forced on
		-- until finish(), however many quick roster walks run in between)
		if GuildRoster then GuildRoster() end
		After(0.25, poll)
	end
	-- give the first request a beat to answer, then poll
	if After then After(0.25, poll) else finish() end
end

-- ------------------------------------------------------------
-- Attendance snapshot
-- ------------------------------------------------------------
-- A snapshot = the raid roster (name/class/group/role/rank) plus raid meta
-- (zone, difficulty, boss, trigger, time, lockout id). Stored in the guild
-- SavedVariables so the hub can be fed later even after a /reload.

-- Our own lockout id for this instance and difficulty, or nil when we are not
-- saved yet. 3.3.5a only reports the lockouts of the character logged in.
local function myLockoutId(zone, diff)
	if not (zone and GetNumSavedInstances and GetSavedInstanceInfo) then return nil end
	for i = 1, (GetNumSavedInstances() or 0) do
		local iname, id, expires, idiff, locked, _, _, raid = GetSavedInstanceInfo(i)
		if iname == zone and idiff == diff and raid and locked and (expires or 0) > 0 then
			return id
		end
	end
	return nil
end
G.MyLockoutId = myLockoutId

local function snapshotRaid(trigger, bossName)
	local raidN = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	local partyN = (GetNumPartyMembers and GetNumPartyMembers()) or 0
	if raidN == 0 and partyN == 0 then
		return nil, "not in a group"
	end
	local zone, difficultyID, groupSize, mapID, itype
	if GetInstanceInfo then
		-- 3.3.5a: name, type, difficulty, difficultyName, maxPlayers, dynDiff, isDyn, mapID
		local name, t, diff, _, maxPlayers, _, _, mid = GetInstanceInfo()
		zone, difficultyID, groupSize, mapID, itype = name, diff, maxPlayers, mid, t
	end

	-- Attendance is a RAID record. A 5-man is not a raid night, and letting dungeons
	-- in buried the real raids under Violet Hold runs. Only 10/25-man raid instances
	-- are worth a snapshot.
	if itype ~= "raid" or not (groupSize == 10 or groupSize == 25) then
		return nil, "not in a 10 or 25 man raid"
	end

	local players = {}
	if raidN > 0 then
		-- raid: rich per-player info incl. subgroup and role
		for i = 1, 40 do
			local name, rank, subgroup, level, _, class, _, online, _, role = GetRaidRosterInfo(i)
			if name then
				players[#players + 1] = {
					name = stripRealm(name), class = class or "", level = level or 0,
					group = subgroup or 0, role = role or "", rankName = rank or "",
					online = online and true or false,
				}
			end
		end
	else
		-- party (incl. dungeons): GetRaidRosterInfo is empty, so walk the units.
		-- No subgroups in a party -> everyone is group 1; everyone shown is online.
		local units = { "player" }
		for i = 1, partyN do units[#units + 1] = "party" .. i end
		for _, u in ipairs(units) do
			if UnitExists(u) then
				local _, classToken = UnitClass(u)
				players[#players + 1] = {
					name = stripRealm(UnitName(u)), class = classToken or "",
					level = UnitLevel(u) or 0, group = 1, role = "",
					rankName = "", online = true,
				}
			end
		end
	end

	-- A first guess from the Inspect cache, RECENT entries only: a spec read weeks
	-- ago survives a respec or a dual-spec swap, and showing it as tonight's is
	-- worse than showing none. G.ScanSnapshotSpecs replaces these with a fresh
	-- scan right after the snapshot is saved.
	local I = Okanvil.Inspect
	if I and I.Info and I.IsFresh then
		for _, p in ipairs(players) do
			local info = I.Info(p.name)
			if info and info.spec and I.IsFresh(p.name, 1) then
				p.spec, p.specIcon = info.spec, info.icon
			end
		end
	end

	table.sort(players, function(a, b)
		if a.group ~= b.group then return a.group < b.group end
		return a.name < b.name
	end)
	return {
		t = time(), zone = zone or "", difficulty = difficultyID or 0, mapID = mapID or 0,
		groupSize = groupSize or (raidN > 0 and raidN or (partyN + 1)),
		boss = bossName or "", trigger = trigger,
		char = UnitName("player") or "",   -- which toon took it: lockout IDs are per character
		count = #players, players = players,
		-- set: the auto snapshot waits until we are saved. One taken by hand before the
		-- first kill has none yet; G.FillLockout fills it in.
		lockoutId = myLockoutId(zone, difficultyID),
	}
end

-- persist a snapshot into the guild DB. The list is shared by every toon on the
-- account, but the cap is PER TOON: each keeps its newest 10. One cap for the
-- whole list let a few alt raids push a main's ICC out of it.
local MAX_SNAPSHOTS = 10

-- Drop each toon's snapshots past its newest MAX_SNAPSHOTS. The list is newest
-- first, so counting from the top keeps the right ones.
local function trimSnapshots(list)
	if not list then return end
	local count = {}
	local keep = {}
	for _, snap in ipairs(list) do
		local who = snap.char or ""
		count[who] = (count[who] or 0) + 1
		if count[who] <= MAX_SNAPSHOTS then keep[#keep + 1] = snap end
	end
	for i = #list, 1, -1 do list[i] = nil end
	for i, snap in ipairs(keep) do list[i] = snap end
end

do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function()
		trimSnapshots(Okanvil.db and Okanvil.db.guild and Okanvil.db.guild.snapshots)
	end)
end
function G.SaveSnapshot(trigger, bossName)
	local snap, err = snapshotRaid(trigger, bossName)
	if not snap then return nil, err end
	local db = Okanvil.db
	db.guild = db.guild or {}
	db.guild.snapshots = db.guild.snapshots or {}
	table.insert(db.guild.snapshots, 1, snap)   -- newest first
	trimSnapshots(db.guild.snapshots)
	if G.onSnapshot then G.onSnapshot() end       -- refresh the tab if open
	local A = Okanvil.Attendance
	if A and A.OnSnapshot then
		local ok, e = pcall(A.OnSnapshot, snap)
		if not ok then Okanvil:Err("Attendance", e) end
	end
	G.ScanSnapshotSpecs(snap)
	return snap
end

-- ------------------------------------------------------------
-- Specs as they are TONIGHT, from a forced inspect scan of the group.
--
-- The snapshot is the attendance record, so the spec beside each name has to be
-- what that player is actually running -- not the cache's memory of them, and
-- not what an officer note said months ago. The scan reads every talent tree
-- again and overwrites the snapshot's spec with whatever it just read; anyone
-- it could not reach (offline, out of range) keeps the recent guess or none.
--
-- In combat it waits: a snapshot can be taken mid-fight, and an inspect round
-- in the middle of a boss both misses whoever is out of range and is the last
-- thing anyone wants running then. Busy (another module is already
-- scanning) it tries again a few times.
-- ------------------------------------------------------------
local afterCombat = {}
local combatWatch = CreateFrame("Frame")
combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatch:SetScript("OnEvent", function()
	local pending = afterCombat
	afterCombat = {}
	for _, fn in ipairs(pending) do pcall(fn) end
end)

function G.ScanSnapshotSpecs(snap, tries)
	local I = Okanvil.Inspect
	if not (snap and I and I.ScanGroup and I.Info) then return end
	tries = tries or 0
	if InCombatLockdown and InCombatLockdown() then
		afterCombat[#afterCombat + 1] = function() G.ScanSnapshotSpecs(snap, tries) end
		return
	end
	local started = time()
	local ok = I.ScanGroup(true, function()
		for _, p in ipairs(snap.players or {}) do
			local info = I.Info(p.name)
			-- Only what THIS scan read: an entry older than the scan's start is
			-- someone it could not reach, and their old spec is not tonight's.
			if info and info.spec and (info.at or 0) >= started then
				p.spec, p.specIcon = info.spec, info.icon
			end
		end
		snap.specsAt = time()
		-- the attendance night was filed before the scan answered: give it the specs
		local A = Okanvil.Attendance
		if A and A.OnSpecs then
			local okS, eS = pcall(A.OnSpecs, snap)
			if not okS and Okanvil.Err then Okanvil:Err("Attendance.OnSpecs", eS) end
		end
		if G.onSnapshot then G.onSnapshot() end
	end)
	if not ok and tries < 6 and Okanvil.Comms and Okanvil.Comms.After then
		Okanvil.Comms.After(10, function() G.ScanSnapshotSpecs(snap, tries + 1) end)
	end
end

-- ------------------------------------------------------------
-- The LOCKOUT ID of a snapshot taken before anyone was saved.
--
-- A snapshot taken before the first kill (by hand, or by an older version at the
-- first pull) has no lockout yet: it only exists once the first boss is dead.
-- So after each fight in a raid we ask the server for our
-- lockouts (RequestRaidInfo is async: the answer is UPDATE_INSTANCE_INFO) and fill
-- the newest snapshot of this instance that is still missing its id -- only one
-- taken in the last 12 hours, so an old snapshot never picks up a new lockout.
-- ------------------------------------------------------------
-- This toon's snapshots, newest first. The list is shared by the account, but a
-- toon's own raids are what its Snapshots tab shows, and lockouts are per toon.
function G.MySnapshots()
	local me = UnitName("player") or ""
	local out = {}
	for _, snap in ipairs((Okanvil.db and Okanvil.db.guild and Okanvil.db.guild.snapshots) or {}) do
		if (snap.char or "") == me then out[#out + 1] = snap end
	end
	return out
end

function G.FillLockout()
	local snap = G.MySnapshots()[1]
	if not snap or snap.lockoutId or (time() - (snap.t or 0)) > 12 * 3600 then return end
	local id = myLockoutId(snap.zone, snap.difficulty)
	if id then
		snap.lockoutId = id
		if G.onSnapshot then G.onSnapshot() end
		local A = Okanvil.Attendance
		if A and A.OnLockout then
			local ok, e = pcall(A.OnLockout, snap)
			if not ok then Okanvil:Err("Attendance", e) end
		end
	end
end

do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:RegisterEvent("UPDATE_INSTANCE_INFO")
	f:SetScript("OnEvent", function(_, event)
		local snap = G.MySnapshots()[1]
		if not snap or snap.lockoutId then return end
		if event == "PLAYER_REGEN_ENABLED" then
			local inInstance, itype = IsInInstance()
			if inInstance and itype == "raid" and RequestRaidInfo then RequestRaidInfo() end
		else
			G.FillLockout()
		end
	end)
end

function G.DeleteSnapshot(snap)
	local list = Okanvil.db.guild and Okanvil.db.guild.snapshots
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == snap then table.remove(list, i); break end
	end
	if G.onSnapshot then G.onSnapshot() end
end

-- ------------------------------------------------------------
-- Re-invite everyone from a saved snapshot.
--
-- The point: last week's roster IS next week's invite list. Rebuilding it by hand
-- from the attendance record is the tedious part of forming a raid.
--
-- The Invite module owns the actual sending -- it already strips realms, skips
-- yourself and anyone already in the group, and converts party -> raid before the
-- 6th invite. We only supply the names.
-- ------------------------------------------------------------
function G.SnapshotNames(snap)
	local out = {}
	if not (snap and snap.players) then return out end
	for _, p in ipairs(snap.players) do
		if p.name and p.name ~= "" then out[#out + 1] = p.name end
	end
	return out
end

-- Returns invitesSent, total.
function G.InviteSnapshot(snap)
	local names = G.SnapshotNames(snap)
	if #names == 0 then
		Okanvil:Print("|cffff5555Nothing to invite|r -- that snapshot has no players.")
		return 0, 0
	end
	local I = Okanvil.Invite
	if not (I and I.InviteNames) then
		Okanvil:Print("|cffff5555Invite module is off|r -- turn it on in Modules.")
		return 0, #names
	end
	return I.InviteNames(names), #names
end

-- ------------------------------------------------------------
-- Who from a snapshot is online RIGHT NOW (checked when the snapshot is opened).
--
-- Guild members and the current group are answered at once from the roster.
-- Everyone else (pugs) goes through /who, one name at a time. Servers differ in
-- how soon they answer the next /who: the queue starts fast and, each time an
-- answer never comes, doubles the wait and asks that name once more. The query
-- runs silently -- results go to the event, not the Who window or chat -- and
-- steps aside whenever the player runs a /who themselves.
-- ------------------------------------------------------------
local WHO_GAP_MIN, WHO_GAP_MAX, WHO_TIMEOUT = 1, 6, 4
local whoGap = WHO_GAP_MIN   -- learned for the session
local whoRetried = {}

G.live = G.live or {}     -- [name] = { on = bool, zone = string|nil, at = time() }
local whoQ, whoName, whoSentAt, whoSnap, whoDone, whoTotal, whoCb = {}, nil, 0, nil, 0, 0, nil
local whoOurs = false     -- the SendWho in flight is ours
local whoNextAt = 0

local function setLive(name, on, zone)
	G.live[name] = { on = on, zone = zone, at = time() }
end

-- [name] = { online, zone } for every guild member, offline ones included.
local function guildRoster()
	local out = {}
	if not IsInGuild() then return out end
	for i = 1, (GetNumGuildMembers(true) or 0) do
		local n, _, _, _, _, zone, _, _, online = GetGuildRosterInfo(i)
		if n then out[n:gsub("%-.*$", "")] = { online and true or false, zone } end
	end
	return out
end

-- Guild and group answers, no server round trip. Returns true when answered.
local function liveFromRoster(name, roster)
	if UnitInRaid(name) or UnitInParty(name) or UnitName("player") == name then
		setLive(name, UnitIsConnected(name) and true or false, nil)
		return true
	end
	local g = roster[name]
	if g then
		setLive(name, g[1], g[1] and g[2] or nil)
		return true
	end
	return false
end

local function whoFinish()
	whoName, whoOurs = nil, false
	if FriendsFrame and not FriendsFrame:IsEventRegistered("WHO_LIST_UPDATE") then
		FriendsFrame:RegisterEvent("WHO_LIST_UPDATE")
	end
	if SetWhoToUI then SetWhoToUI(0) end
end

local function whoProgress()
	if whoCb then pcall(whoCb, whoDone, whoTotal) end
end

local function whoSend()
	local name = table.remove(whoQ, 1)
	if not name then whoFinish(); whoSnap = nil; whoProgress(); return end
	whoName, whoSentAt, whoOurs = name, GetTime(), true
	if SetWhoToUI then SetWhoToUI(1) end
	-- the Friends frame would draw our result in the Who tab
	if FriendsFrame then FriendsFrame:UnregisterEvent("WHO_LIST_UPDATE") end
	SendWho('n-"' .. name .. '"')
end

-- A /who the player typed: hand the server back to them, ask ours again later.
hooksecurefunc("SendWho", function()
	if whoOurs then whoOurs = false; return end
	if whoName then
		table.insert(whoQ, 1, whoName)
		whoFinish()
	end
	whoNextAt = GetTime() + WHO_GAP_MAX
end)

local whoEv = CreateFrame("Frame")
whoEv:RegisterEvent("WHO_LIST_UPDATE")
whoEv:SetScript("OnEvent", function()
	if not whoName then return end
	local name, found, zone = whoName, false, nil
	for i = 1, (GetNumWhoResults() or 0) do
		local n, _, _, _, _, z = GetWhoInfo(i)
		if n and n:gsub("%-.*$", "") == name then found, zone = true, z; break end
	end
	setLive(name, found, zone)
	whoFinish()
	whoDone = whoDone + 1
	whoNextAt = GetTime() + whoGap
	whoProgress()
end)

whoEv:SetScript("OnUpdate", function()
	if not whoSnap then return end
	local now = GetTime()
	if whoName then
		-- no answer: leave them unknown rather than call them offline
		if now - whoSentAt > WHO_TIMEOUT then
			local name = whoName
			whoFinish()
			whoGap = math.min(whoGap * 2, WHO_GAP_MAX)
			if not whoRetried[name] then
				whoRetried[name] = true
				table.insert(whoQ, 1, name)
			else
				whoDone = whoDone + 1
				whoProgress()
			end
			whoNextAt = now + whoGap
		end
		return
	end
	if now < whoNextAt then return end
	if InCombatLockdown() then return end
	if WhoFrame and WhoFrame:IsVisible() then return end
	whoSend()
end)

-- Live status for one player: on (bool), zone, checking (still queued).
function G.LiveOf(name, snap)
	local l = G.live[name]
	if whoSnap and whoSnap == snap then
		if whoName == name then return nil, nil, true end
		for _, n in ipairs(whoQ) do if n == name then return nil, nil, true end end
	end
	if l then return l.on, l.zone, false end
	return nil, nil, false
end

-- done, total while a check runs for this snapshot; nil otherwise.
function G.OnlineCheckProgress(snap)
	if whoSnap and whoSnap == snap then return whoDone, whoTotal end
end

-- Start a check of every player in `snap`. `cb(done, total)` repaints the page.
function G.CheckSnapshotOnline(snap, cb)
	if not (snap and snap.players) then return end
	G.StopOnlineCheck()
	whoQ, whoDone, whoCb, whoRetried = {}, 0, cb, {}
	local roster = guildRoster()
	for _, p in ipairs(snap.players) do
		if p.name and p.name ~= "" and not liveFromRoster(p.name, roster) then
			whoQ[#whoQ + 1] = p.name
		end
	end
	whoTotal = #whoQ
	if whoTotal > 0 then whoSnap = snap end
	whoProgress()
end

function G.StopOnlineCheck()
	whoQ, whoSnap, whoCb = {}, nil, nil
	if whoName then whoFinish() end
end

-- JSON for one snapshot (fed to the hub attendance importer)
function G.SnapshotJSON(snap)
	if not snap then return "{}" end
	local guildName = GetGuildInfo("player") or "Guild"
	local realm = GetRealmName() or ""
	local rows = {}
	for _, p in ipairs(snap.players) do
		rows[#rows + 1] = string.format(
			'{"name":"%s","class":"%s","level":%d,"group":%d,"role":"%s","rankName":"%s","online":%s}',
			esc(p.name), esc(p.class), p.level, p.group, esc(p.role), esc(p.rankName),
			p.online and "true" or "false"
		)
	end
	return string.format(
		'{"type":"attendance","guildName":"%s","realm":"%s","capturedAt":%d,"zone":"%s",'
		.. '"mapID":%d,"difficulty":%d,"groupSize":%d,"boss":"%s","trigger":"%s",'
		.. '"lockoutId":%s,"players":[%s]}',
		esc(guildName), esc(realm), snap.t, esc(snap.zone),
		snap.mapID or 0, snap.difficulty, snap.groupSize, esc(snap.boss), esc(snap.trigger),
		snap.lockoutId and tostring(snap.lockoutId) or "null",
		table.concat(rows, ",")
	)
end

-- class color as |cffRRGGBB (RAID_CLASS_COLORS is a global on 3.3.5a)
local function classHex(classToken)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
	if c then
		return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
	end
	return "|cffffd200"
end

-- ------------------------------------------------------------
-- Snapshot body as a single formatted string: group headers + class-coloured
-- names. Shared by the inline Guild-tab expansion and the (legacy) popup.
-- ------------------------------------------------------------
function G.SnapshotBodyText(snap)
	if not snap or not snap.players then return "" end
	local lines, lastGroup = {}, nil
	for _, p in ipairs(snap.players) do
		if p.group ~= lastGroup then
			lastGroup = p.group
			lines[#lines + 1] = "|cff8a8d93Group " .. p.group .. "|r"
		end
		local role = (p.role and p.role ~= "") and ("  |cff5e6166(" .. p.role .. ")|r") or ""
		local off = p.online and "" or "  |cff5e6166[offline]|r"
		lines[#lines + 1] = "  " .. classHex(p.class) .. p.name .. "|r"
			.. "  |cff5e6166" .. (p.level > 0 and p.level or "") .. "|r" .. role .. off
	end
	return table.concat(lines, "\n")
end

-- The same body, split into N columns for a wide panel. A 25-man snapshot is
-- five groups of five: stacked in one column it runs off the bottom of the card
-- and leaves the right half empty. Split by GROUP, never mid-group, so a column
-- is always whole groups and a name never separates from its heading.
function G.SnapshotColumns(snap, cols)
	cols = cols or 2
	if not snap or not snap.players then return {} end

	-- gather the groups in order, each already rendered as its own block
	local groups, order = {}, {}
	for _, p in ipairs(snap.players) do
		local g = p.group or 0
		if not groups[g] then groups[g] = {}; order[#order + 1] = g end
		local role = (p.role and p.role ~= "") and ("  |cff5e6166(" .. p.role .. ")|r") or ""
		local off = p.online and "" or "  |cff5e6166[offline]|r"
		local t = groups[g]
		t[#t + 1] = "  " .. classHex(p.class) .. p.name .. "|r"
			.. "  |cff5e6166" .. ((p.level or 0) > 0 and p.level or "") .. "|r" .. role .. off
	end

	-- deal the groups into columns, keeping each column's line count even
	local out, counts = {}, {}
	for i = 1, cols do out[i] = {}; counts[i] = 0 end
	for _, g in ipairs(order) do
		-- shortest column takes the next group
		local pick, best = 1, counts[1]
		for i = 2, cols do
			if counts[i] < best then pick, best = i, counts[i] end
		end
		local col = out[pick]
		col[#col + 1] = "|cff8a8d93Group " .. g .. "|r"
		for _, line in ipairs(groups[g]) do col[#col + 1] = line end
		counts[pick] = counts[pick] + #groups[g] + 1
	end

	local res = {}
	for i = 1, cols do res[i] = table.concat(out[i], "\n") end
	return res
end

-- Visual snapshot viewer -- see exactly who was captured, in-game,
-- names colored by class and split by group. Reuses one flat popup.
-- ------------------------------------------------------------
local viewer
function G.ShowSnapshot(snap)
	if not snap then return end
	local W = Okanvil.W
	local f = viewer
	if not f then
		f = Okanvil:Popup("Snapshot")
		f:SetSize(360, 440)
		f.meta = W.Text(f, "", "label", "dim"); f.meta:SetPoint("TOPLEFT", 12, -30)
		f.meta:SetPoint("RIGHT", f, "RIGHT", -12, 0); f.meta:SetJustifyH("LEFT")

		local box = Okanvil.W.Frame(f, "soft")
		box:SetPoint("TOPLEFT", 8, -64); box:SetPoint("BOTTOMRIGHT", -8, 8)
		local sf = CreateFrame("ScrollFrame", nil, box)
		sf:SetPoint("TOPLEFT", 4, -4); sf:SetPoint("BOTTOMRIGHT", -10, 4)
		Okanvil.Clip(sf)
		local child = CreateFrame("Frame", nil, sf); child:SetSize(320, 10); sf:SetScrollChild(child)
		local sb = CreateFrame("Slider", nil, box)
		sb:SetPoint("TOPRIGHT", -3, -4); sb:SetPoint("BOTTOMRIGHT", -3, 4); sb:SetWidth(4)
		sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
		local th = sb:CreateTexture(nil, "OVERLAY")
		th:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
		local ac = Okanvil.Colors.accent; th:SetVertexColor(ac[1], ac[2], ac[3], 1); th:SetSize(4, 40)
		sb:SetThumbTexture(th)
		sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
		sf:EnableMouseWheel(true)
		sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 60) end)
		f.sf, f.child, f.sb, f.body = sf, child, sb, W.Text(child, "", "body")
		f.body:SetPoint("TOPLEFT", 6, -6); f.body:SetPoint("TOPRIGHT", -6, -6); f.body:SetJustifyH("LEFT")
		viewer = f
	end

	local dateStr = date("%b %d  %H:%M", snap.t)
	local where = (snap.zone ~= "" and snap.zone) or "Unknown"
	f.title:SetText("|cffffd200" .. where .. "|r")
	f.meta:SetText(dateStr .. "   |cff8a8d93" .. (snap.count or 0) .. " players  |  "
		.. (snap.boss ~= "" and (snap.boss .. "  |  ") or "")
		.. (snap.lockoutId and ("ID " .. snap.lockoutId .. "  |  ") or "")
		.. (snap.trigger or "") .. "|r")

	f.body:SetText(G.SnapshotBodyText(snap))
	-- size the scroll child to the text so the slider range is right
	local h = f.body:GetStringHeight() + 16
	f.child:SetHeight(h)
	f.child:SetWidth(f.sf:GetWidth())
	local maxS = math.max(0, h - f.sf:GetHeight())
	f.sb:SetMinMaxValues(0, maxS); f.sb:SetValue(0); f.sb:SetShown(maxS > 0)
	f:Show()
end

-- ------------------------------------------------------------
-- Auto-capture when this toon becomes saved to the raid, i.e. at the first boss
-- kill: the first pull is usually trash, while the raid is still filling.
-- 3.3.5a has no kill event, so after each
-- fight in a raid we ask for our lockouts, and the answer that shows us saved to
-- this instance takes the snapshot. On a raid continued from an earlier night we
-- are already saved, so it is taken after the first fight instead.
-- One auto-snapshot per raid lockout session (reset when the raid empties).
--
-- "Already taken" lives in the SavedVariables, not a local: a local resets on
-- /reload, and every reload mid-raid then saved another snapshot at the next pull
-- (and pushed real raids out of the 10-slot list). The mark names the instance it
-- was taken in and goes stale after a raid night, so a new raid -- or a group that
-- disbanded while you were logged out -- still gets its snapshot.
-- ------------------------------------------------------------
local AUTO_SNAP_STALE = 6 * 3600

local function instanceKey()
	if not GetInstanceInfo then return "" end
	local name, _, diff, _, maxPlayers = GetInstanceInfo()
	return (name or "") .. "|" .. (diff or 0) .. "|" .. (maxPlayers or 0)
end

local function autoSnapTaken()
	local g = Okanvil.db and Okanvil.db.guild
	local m = g and g.autoSnap
	if not m then return false end
	if time() - (m.t or 0) > AUTO_SNAP_STALE then return false end
	return m.key == instanceKey()
end

local function setAutoSnap(taken)
	local db = Okanvil.db
	if not db then return end
	db.guild = db.guild or {}
	db.guild.autoSnap = taken and { key = instanceKey(), t = time() } or nil
end
local function inGroup()
	local raidN = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	local partyN = (GetNumPartyMembers and GetNumPartyMembers()) or 0
	return raidN > 0 or partyN > 0
end

local function trySavedSnapshot()
	if autoSnapTaken() then return end
	if not inGroup() then return end
	if not Okanvil:ShouldRecord() then return end   -- dungeon/raid toggle
	local zone, _, diff = GetInstanceInfo()
	if not myLockoutId(zone, diff) then return end  -- no boss down yet
	local snap = G.SaveSnapshot("saved")
	if snap then
		setAutoSnap(true)
		Okanvil:Print("Attendance snapshot saved (" .. (snap.count or 0) .. " players).")
	end
end

-- The snapshot is the roster at the first kill, so whoever joins after it would
-- be missing. After each later fight, add the latecomers to this raid's
-- snapshot, keeping the raid group they are in now. Attendance then
-- gets them too: its night merges in names it does not have yet.
local topUpQueued = false
local function topUpSnapshot()
	topUpQueued = false
	local snap = G.MySnapshots()[1]
	if not snap or time() - (snap.t or 0) > AUTO_SNAP_STALE then return end
	local now = snapshotRaid("topup")
	if not now or now.zone ~= snap.zone or now.difficulty ~= snap.difficulty
		or now.groupSize ~= snap.groupSize then return end
	local have = {}
	for _, p in ipairs(snap.players or {}) do have[p.name] = true end
	local added = 0
	snap.players = snap.players or {}
	for _, p in ipairs(now.players) do
		if not have[p.name] then
			snap.players[#snap.players + 1] = p
			added = added + 1
		end
	end
	if added == 0 then return end
	table.sort(snap.players, function(a, b)
		if a.group ~= b.group then return a.group < b.group end
		return a.name < b.name
	end)
	snap.count = #snap.players
	Okanvil:Trace("GUILD", ("snapshot top-up: +%d (%d)"):format(added, snap.count))
	local A = Okanvil.Attendance
	if A and A.OnSnapshot then
		local ok, e = pcall(A.OnSnapshot, snap)
		if not ok and Okanvil.Err then Okanvil:Err("Attendance.OnSnapshot", e) end
	end
	G.ScanSnapshotSpecs(snap)
	if G.onSnapshot then G.onSnapshot() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")   -- entered combat
ev:RegisterEvent("UPDATE_INSTANCE_INFO")    -- the lockout list asked for after a fight
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:RegisterEvent("PARTY_MEMBERS_CHANGED")

-- Set when a fight ends in a raid and we asked for the lockouts, so only that
-- answer can take the snapshot -- not the one the zone-in asks for.
local savedCheck = false

local function afterRaidFight()
	local inInstance, itype = IsInInstance()
	if not (inInstance and itype == "raid" and RequestRaidInfo) then return end
	savedCheck = true
	RequestRaidInfo()
end

ev:SetScript("OnEvent", function(_, event)
	-- Guild module off: no snapshot, no reacting to the group.
	if Okanvil.ModuleActive and not Okanvil:ModuleActive("__guild") then return end
	if event == "PLAYER_REGEN_DISABLED" then
		-- passive work: wait for the fight to end
		if not autoSnapTaken() then
			afterCombat[#afterCombat + 1] = afterRaidFight
		elseif not topUpQueued then
			topUpQueued = true
			afterCombat[#afterCombat + 1] = topUpSnapshot
		end
	elseif event == "UPDATE_INSTANCE_INFO" then
		if not savedCheck then return end
		savedCheck = false
		trySavedSnapshot()
	else
		-- group emptied -> arm the next session's capture again.
		-- Not watched on PLAYER_ENTERING_WORLD: at login the roster can read empty
		-- for a moment, and that would re-arm the capture on every login.
		if not inGroup() then setAutoSnap(false) end
	end
end)
