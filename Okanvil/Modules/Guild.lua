-- ============================================================
-- Okanvil -- Guild (native core module, not a plugin).
-- Two exports for the RATS web hub:
--   * Roster export   -- the full guild roster as JSON (comp/guild importer).
--   * Attendance      -- a snapshot of the raid group at the first pull of the
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
-- and wait until the roster reports MORE members than are online (offline loaded) before
-- building. cb(json, count) fires once the full list is ready (or after a timeout, so a
-- guild that really is all-online still exports).
function G.ExportRoster(cb)
	if not (IsInGuild and IsInGuild()) then
		local json, count = G.BuildRosterJSON()
		if cb then cb(json, count) end
		return
	end
	-- turn on Show Offline + request a fresh roster from the server
	if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
	if GuildRoster then GuildRoster() end

	local After = Okanvil.Comms and Okanvil.Comms.After
	local attempts = 0
	local MAX_ATTEMPTS = 12          -- ~3s at 0.25s spacing
	local function ready()
		-- GetNumGuildMembers() -> (total, online). total counts offline only when the
		-- show-offline flag is on AND the offline list has arrived. When they match we
		-- either have everyone loaded or the guild really is all online.
		local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
		local online = (GetNumGuildMembers and select(2, GetNumGuildMembers())) or 0
		return total > online or online == 0
	end
	local function finish()
		local json, count = G.BuildRosterJSON()
		if cb then cb(json, count) end
	end
	local function poll()
		attempts = attempts + 1
		if ready() or attempts >= MAX_ATTEMPTS or not After then
			finish()
			return
		end
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
-- (zone, difficulty, boss, trigger, time). Stored in the guild SavedVariables
-- so the hub can be fed later even after a /reload.
local function snapshotRaid(trigger, bossName)
	local raidN = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	local partyN = (GetNumPartyMembers and GetNumPartyMembers()) or 0
	if raidN == 0 and partyN == 0 then
		return nil, "not in a group"
	end
	local zone, difficultyID, groupSize, mapID
	if GetInstanceInfo then
		-- 3.3.5a: name, type, difficulty, difficultyName, maxPlayers, dynDiff, isDyn, mapID
		local name, _, diff, _, maxPlayers, _, _, mid = GetInstanceInfo()
		zone, difficultyID, groupSize, mapID = name, diff, maxPlayers, mid
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

	table.sort(players, function(a, b)
		if a.group ~= b.group then return a.group < b.group end
		return a.name < b.name
	end)
	return {
		t = time(), zone = zone or "", difficulty = difficultyID or 0, mapID = mapID or 0,
		groupSize = groupSize or (raidN > 0 and raidN or (partyN + 1)),
		boss = bossName or "", trigger = trigger,
		count = #players, players = players,
	}
end

-- persist a snapshot into the guild DB (keeps the last N)
local MAX_SNAPSHOTS = 20
function G.SaveSnapshot(trigger, bossName)
	local snap, err = snapshotRaid(trigger, bossName)
	if not snap then return nil, err end
	local db = Okanvil.db
	db.guild = db.guild or {}
	db.guild.snapshots = db.guild.snapshots or {}
	table.insert(db.guild.snapshots, 1, snap)   -- newest first
	while #db.guild.snapshots > MAX_SNAPSHOTS do
		table.remove(db.guild.snapshots)
	end
	if G.onSnapshot then G.onSnapshot() end       -- refresh the tab if open
	return snap
end

function G.DeleteSnapshot(snap)
	local list = Okanvil.db.guild and Okanvil.db.guild.snapshots
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == snap then table.remove(list, i); break end
	end
	if G.onSnapshot then G.onSnapshot() end
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
		.. '"mapID":%d,"difficulty":%d,"groupSize":%d,"boss":"%s","trigger":"%s","players":[%s]}',
		esc(guildName), esc(realm), snap.t, esc(snap.zone),
		snap.mapID or 0, snap.difficulty, snap.groupSize, esc(snap.boss), esc(snap.trigger),
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
		f.meta = W.Text(f, "", 11, "dim"); f.meta:SetPoint("TOPLEFT", 12, -30)
		f.meta:SetPoint("RIGHT", f, "RIGHT", -12, 0); f.meta:SetJustifyH("LEFT")

		local box = Okanvil.W.Frame(f, "input")
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
		sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 24) end)
		f.sf, f.child, f.sb, f.body = sf, child, sb, W.Text(child, "", 12)
		f.body:SetPoint("TOPLEFT", 6, -6); f.body:SetPoint("TOPRIGHT", -6, -6); f.body:SetJustifyH("LEFT")
		viewer = f
	end

	local dateStr = date("%b %d  %H:%M", snap.t)
	local where = (snap.zone ~= "" and snap.zone) or "Unknown"
	f.title:SetText("|cffffd200" .. where .. "|r")
	f.meta:SetText(dateStr .. "   |cff8a8d93" .. (snap.count or 0) .. " players  |  "
		.. (snap.boss ~= "" and (snap.boss .. "  |  ") or "") .. (snap.trigger or "") .. "|r")

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
-- Auto-capture at the first pull of the raid (MRT-style).
-- Prefer ENCOUNTER_START (some 3.3.5a private servers backport it);
-- fall back to entering combat (PLAYER_REGEN_DISABLED) inside a raid instance.
-- One auto-snapshot per raid lockout session (reset when the raid empties).
-- ------------------------------------------------------------
local firstPullDone = false
local haveEncounterEvent = false

local function inGroup()
	local raidN = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	local partyN = (GetNumPartyMembers and GetNumPartyMembers()) or 0
	return raidN > 0 or partyN > 0
end

local function tryFirstPull(bossName, trigger)
	if firstPullDone then return end
	if not inGroup() then return end
	if not Okanvil:ShouldRecord() then return end   -- dungeon/raid toggle
	local snap = G.SaveSnapshot(trigger, bossName)
	if snap then
		firstPullDone = true
		Okanvil:Print("Attendance snapshot saved (" .. (snap.count or 0) .. " players).")
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")   -- entered combat
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
-- ENCOUNTER_START may not exist on 3.3.5a; RegisterEvent errors on unknown
-- events, so guard it in pcall.
pcall(function() ev:RegisterEvent("ENCOUNTER_START"); haveEncounterEvent = true end)

ev:SetScript("OnEvent", function(_, event, a1, a2)
	-- Modulo Guild DESLIGADO = nao faz first-pull announce nem reage a grupo.
	if Okanvil.ModuleActive and not Okanvil:ModuleActive("__guild") then return end
	if event == "ENCOUNTER_START" then
		-- a1 = encounterID, a2 = encounterName
		tryFirstPull(a2, "encounter-start")
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- only use combat as a fallback when the encounter event isn't available
		if not haveEncounterEvent then tryFirstPull(nil, "combat") end
	else
		-- group emptied -> arm the next session's first-pull capture again
		if not inGroup() then firstPullDone = false end
	end
end)
