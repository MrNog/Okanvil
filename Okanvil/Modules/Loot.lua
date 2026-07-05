-- ============================================================
-- Okanvil -- Loot (native core module).
-- Records WHAT dropped and from WHICH boss, the moment you open a corpse.
-- Goal for now: just capture the data. WHO gets an item (rolls / master
-- loot / passes) is decided later on the RATS web hub -- so we also log
-- /roll results and "receives loot" lines as extra context, but we don't
-- assign winners here.
--
-- 3.3.5a capture model (from RaidRoll): LOOT_OPENED -> UnitName/UnitGUID
-- "target" for the boss (verify it's an NPC via the GUID), then walk the
-- loot slots with GetNumLootItems / LootSlotIsItem / GetLootSlotInfo /
-- GetLootSlotLink. No retail C_LootHistory / ENCOUNTER_LOOT_RECEIVED here.
-- ============================================================

local Okanvil = Okanvil
local L = {}
Okanvil.Loot = L

local esc = function(s)  -- reuse the Guild escaper if present, else local
	if Okanvil.Guild and Okanvil.Guild.esc then return Okanvil.Guild.esc(s) end
	s = tostring(s or "")
	return (s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t"))
end

local function itemIDFromLink(link)
	return link and tonumber(link:match("item:(%d+)")) or 0
end

-- ------------------------------------------------------------
-- Items we NEVER record: emblems, PvP tokens, gems, enchanting mats/shards,
-- and other currency-like drops. These aren't "guild loot" -- everyone gets
-- their own, so counting them pollutes loot history / priority. Matched by
-- itemID first (exact), then by item CLASS as a fallback (Gem / Trade Goods)
-- so future emblems/gems are caught without a hardcode.
-- ------------------------------------------------------------
local IGNORE_IDS = {
	-- Emblems (Heroism/Valor/Conquest/Triumph/Frost) + Stone Keeper's Shard
	[40752]=true, [40753]=true, [45624]=true, [47241]=true, [49426]=true,
	[43228]=true,
	-- Frozen Orb + common enchanting shards/dusts/essences (DE byproducts)
	[43102]=true,
	[34057]=true, [22450]=true, [22449]=true, [11135]=true, [10938]=true,
	[10940]=true, [10978]=true, [10998]=true, [11082]=true, [11083]=true,
	[11084]=true, [11134]=true, [11137]=true, [11139]=true, [11174]=true,
	[11175]=true, [11176]=true, [11177]=true, [11178]=true, [14343]=true,
	[14344]=true, [16202]=true, [16203]=true, [16204]=true, [20725]=true,
	[22445]=true, [22446]=true, [22447]=true, [22448]=true, [34052]=true,
	[34053]=true, [34054]=true, [34055]=true, [34056]=true,
}
-- Localized item CLASS names that are never guild loot. GetItemInfo returns the
-- class as a localized string; on enUS these are "Gem" and "Trade Goods" (which
-- covers gems, enchanting mats, orbs). We match case-insensitively on substrings.
local IGNORE_CLASS_HINTS = { "gem", "trade goods" }

local function isIgnoredItem(link, itemName)
	local id = itemIDFromLink(link)
	if id ~= 0 and IGNORE_IDS[id] then return true end
	if not link then return false end
	-- class-based catch-all (localized). 3.3.5a: name, link, rarity, level, minL,
	-- itemType(class), subType, ... -> the 6th return is the class string.
	local _, _, _, _, _, itemClass = GetItemInfo(link)
	if itemClass then
		local lc = itemClass:lower()
		for _, hint in ipairs(IGNORE_CLASS_HINTS) do
			if lc:find(hint, 1, true) then return true end
		end
	end
	-- name fallback: anything called "Emblem of ..." (currency tokens)
	local nm = (itemName or ""):lower()
	if nm:find("emblem of", 1, true) then return true end
	return false
end


-- Is this GUID an NPC? 3.3.5a GUID type nibble (5th hex char) & 0x7 == 3.
local function guidIsNPC(guid)
	if not guid then return false end
	local b = tonumber(guid:sub(5, 5), 16)
	return b and (b % 8) == 3
end

-- ------------------------------------------------------------
-- Collectors: when YOU are the Master Looter of a run, some drops always go to a
-- fixed person -- legendary FRAGMENTS to the fragment collector, and BoE items /
-- crafting ORBS / BoE patterns to the BoE collector. Classified by a fixed ID
-- table (reliable) + a name/BoE fallback (catches anything missed).
-- Config lives in Okanvil.db.loot.collectors = { frag="Name", boe="Name", ... }.
-- ------------------------------------------------------------
-- IDs CONFIRMED against the ID Finder's item DB (OkanvilIDsDB). Only ids I could
-- verify are hardcoded; everything else is caught by the NAME fallback below,
-- which is more robust (no wrong-id auto-loot -- learned the hard way: 36913 is
-- "Saronite Bar", NOT Runed Orb).
local FRAGMENT_IDS = {          -- legendary fragments -> fragment collector
	[45038] = true,  -- Fragment of Val'anyr           (confirmed)
	[45039] = true,  -- Shattered Fragments of Val'anyr (confirmed)
	[45896] = true,  -- Unbound Fragments of Val'anyr   (confirmed)
	[49869] = true,  -- Shadowfrost Shard (Shadowmourne) -- name-fallback backup
}
local ORB_IDS = {               -- crafting orbs -> BoE collector
	[45087] = true,  -- Runed Orb              (confirmed; was wrongly 36913 before)
	[47556] = true,  -- Crusader Orb           -- name-fallback backup
	[49908] = true,  -- Primordial Saronite    -- name-fallback backup
}
-- NAME fallbacks (lowercase substring) -- the reliable path, ID-independent.
-- Catches the collector items even when they're not in the ID DB / the id is off.
local FRAG_NAME_HINTS = { "shadowfrost shard", "fragment of val'anyr",
	"fragments of val'anyr" }
local ORB_NAME_HINTS  = { "runed orb", "crusader orb", "primordial saronite" }

-- 3.3.5a: is an item Bind-on-Equip? Scan its tooltip for the BoP/BoE line. We
-- read the item tooltip via a hidden scanner (GetItemInfo has no bind field here).
local scanTip
local function isBoE(link)
	if not link then return false end
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "OkanvilLootScanTip", nil, "GameTooltipTemplate")
		scanTip:SetOwner(UIParent, "ANCHOR_NONE")
	end
	scanTip:ClearLines()
	scanTip:SetHyperlink(link)
	-- BoP shows "Binds when picked up" on line 2; BoE shows "Binds when equipped".
	for i = 2, math.min(6, scanTip:NumLines()) do
		local t = _G["OkanvilLootScanTipTextLeft" .. i]
		local s = t and t:GetText()
		if s then
			if s == ITEM_BIND_ON_PICKUP then return false end       -- BoP
			if s == ITEM_BIND_ON_EQUIP then return true end          -- BoE
		end
	end
	return false
end

local function nameHas(name, hints)
	if not name then return false end
	local lc = name:lower()
	for _, h in ipairs(hints) do if lc:find(h, 1, true) then return true end end
	return false
end

-- Which collector should get this item? Returns "frag", "boe", or nil.
-- Called on the loot slot BEFORE the ignore filter, so shards still route.
local function collectorFor(link, name)
	local id = itemIDFromLink(link)
	if id ~= 0 and FRAGMENT_IDS[id] then return "frag" end
	if nameHas(name, FRAG_NAME_HINTS) then return "frag" end
	if id ~= 0 and ORB_IDS[id] then return "boe" end
	if nameHas(name, ORB_NAME_HINTS) then return "boe" end
	-- BoE items (incl. BoE patterns/recipes) -> BoE collector. Patterns that are
	-- BoP are intentionally NOT routed (they bind to whoever needs the recipe).
	if isBoE(link) then return "boe" end
	return nil
end

-- Are WE the master looter right now? Only then can we auto-give.
local function iAmMasterLooter()
	if not GetLootMethod then return false end
	local method, partyML, raidML = GetLootMethod()
	if method ~= "master" then return false end
	-- partyML is the party member index (0 = player); raidML is the raid index.
	if partyML == 0 then return true end
	if raidML and GetRaidRosterInfo then
		local n = GetRaidRosterInfo(raidML)
		return n and n == UnitName("player")
	end
	return false
end
-- public: is the PLAYER the game's real Master Looter right now? The UI uses this
-- to lock the collector controls so nobody can ninja by pretending to be the ML.
function L.IsMasterLooter() return iAmMasterLooter() end

-- Find the master-loot candidate index for a player name on a given loot slot.
local function mlCandidate(slot, playerName)
	if not (GetMasterLootCandidate and playerName) then return nil end
	for c = 1, 40 do
		local cand = GetMasterLootCandidate(slot, c) or GetMasterLootCandidate(c)
		if cand == playerName then return c end
		if not cand and c > (GetNumRaidMembers and GetNumRaidMembers() or 5) then break end
	end
	return nil
end

-- ------------------------------------------------------------
-- Storage: db.loot.sessions = { {t, zone, difficulty, drops={...}}, ... }
-- (rolls are transient/in-memory only -- the session records who RECEIVED items)
-- One "session" per game session/day; drops keyed to avoid dupes per corpse.
-- ------------------------------------------------------------
local MAX_SESSIONS = 20
local seenCorpses = {}  -- guid -> true, so reopening a body doesn't double-log

-- Cross-corpse de-dupe: when two raiders open the SAME boss corpse, LOOT_OPENED
-- fires for each of them and the same items get walked twice (often with a
-- different/"Unknown" boss name the 2nd time). We remember each itemID's last
-- log time and treat a re-log within DEDUP_WINDOW as the same physical drop.
local DEDUP_WINDOW = 40   -- seconds
local lastLoggedAt = {}   -- itemID -> GetTime() when last recorded
local function recentlyLogged(id)
	if not id or id == 0 then return false end
	local now = GetTime and GetTime() or 0
	local prev = lastLoggedAt[id]
	lastLoggedAt[id] = now
	return prev and (now - prev) < DEDUP_WINDOW
end

-- Loot config (collectors, messages, thresholds) stays ACCOUNT-WIDE (an officer
-- sets collectors once for all toons). But the SESSION LOG is PER CHARACTER -- you
-- only care about YOUR runs, not another toon's. So sessions live in the
-- per-character DB (Okanvil.cdb) and we alias db().sessions onto it.
local function db()
	Okanvil.db.loot = Okanvil.db.loot or {}
	local cdb = Okanvil.cdb or Okanvil.db          -- fall back to account DB pre-login
	cdb.lootSessions = cdb.lootSessions or {}
	-- one-time migration: move any old account-wide sessions to this character the
	-- first time (so existing logs aren't lost), then stop sharing them.
	if Okanvil.db.loot.sessions and not cdb._lootMigrated then
		if #cdb.lootSessions == 0 and #Okanvil.db.loot.sessions > 0 then
			for _, s in ipairs(Okanvil.db.loot.sessions) do cdb.lootSessions[#cdb.lootSessions + 1] = s end
		end
		Okanvil.db.loot.sessions = nil            -- drop the shared copy
		cdb._lootMigrated = true
	end
	Okanvil.db.loot.sessions = cdb.lootSessions   -- alias: all existing code keeps working
	return Okanvil.db.loot
end

-- public accessor for the UI so it always reads the PER-CHARACTER session list
-- (calling db() first guarantees the alias/migration has run).
function L.Sessions() return db().sessions end

-- Did the current loot session record a drop from a boss of this name? The Logs
-- module uses this to recognise dungeon bosses (which drop loot) without needing
-- a hardcoded 5-man boss list -- "what dropped loot = what you killed".
function L.SessionHasBoss(name)
	if not name or name == "" then return false end
	local d = Okanvil.db and Okanvil.db.loot
	local s = d and d.sessions and d.sessions[1]
	if not s then return false end
	for i = 1, #s.drops do
		if s.drops[i].boss == name then return true end
	end
	return false
end

-- Recent drops of the current session (for the mini roll manager's item list),
-- newest first, capped. Returns the live drop tables so edits reflect back.
function L.RecentDrops(limit)
	local d = Okanvil.db and Okanvil.db.loot
	local s = d and d.sessions and d.sessions[1]
	if not s then return {} end
	local out = {}
	for i = #s.drops, 1, -1 do
		out[#out + 1] = s.drops[i]
		if limit and #out >= limit then break end
	end
	return out
end

-- The newest session that actually HAS drops (today's may be empty). Used by the
-- Mini Roll Manager so its list isn't blank just because today logged nothing yet.
local function newestSessionWithDrops()
	local d = Okanvil.db and Okanvil.db.loot
	local list = d and d.sessions
	if not list then return nil end
	for i = 1, #list do
		if list[i].drops and #list[i].drops > 0 then return list[i] end
	end
	return list[1]
end

-- Drops grouped by boss, preserving first-seen order, for the manager's per-boss
-- pager. Returns { {boss=name, items={drop,...}}, ... }.
function L.DropsByBoss()
	local s = newestSessionWithDrops()
	if not s then return {} end
	local order, byBoss = {}, {}
	for _, dp in ipairs(s.drops) do
		local b = (dp.boss ~= "" and dp.boss) or "Need / Greed"
		if not byBoss[b] then byBoss[b] = { boss = b, items = {} }; order[#order + 1] = byBoss[b] end
		table.insert(byBoss[b].items, dp)
	end
	return order
end

function L.DeleteSession(sess)
	local list = db().sessions
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == sess then table.remove(list, i); break end
	end
	if L.onLoot then L.onLoot() end
end

-- Build a LOCKOUT key for the current instance. Two raid days on the SAME save
-- share it (until reset), so their loot lands in ONE session. We match the current
-- zone against the player's saved-instance list to grab its reset time; the key is
-- name|difficulty|resetDay. Outside a saved raid (5-mans/world) we fall back to a
-- per-day key so those still group by day.
-- A "run token" that bumps every time you ENTER a fresh dungeon instance. Dungeons
-- aren't lockout-saved, so two runs of the SAME dungeon on the same day would
-- otherwise share one loot session (the Okanor/Okanath bug). Keying dungeons by
-- this token makes every entry its own session. Raids still key by lockout (their
-- loot really is shared per reset).
local wasInInstance = false
-- runToken persists in the DB so a /reload mid-dungeon resumes the SAME session
-- key instead of orphaning the run's drops.
local function runToken(bump)
	local d = db()
	d._runToken = d._runToken or 0
	if bump then d._runToken = d._runToken + 1 end
	return d._runToken
end

local function lockoutKey()
	local name, itype, diff, _, _, _, _, mapID = "", "none", 0, nil, nil, nil, nil, 0
	if GetInstanceInfo then name, itype, diff, _, _, _, _, mapID = GetInstanceInfo() end
	name = name or ""
	-- RAID: try to find this instance in the saved (locked) list -> use its reset
	-- time, so both raid days on the same save land in ONE session.
	if itype == "raid" and GetNumSavedInstances and GetSavedInstanceInfo then
		for i = 1, GetNumSavedInstances() do
			local sname, _, reset, sdiff = GetSavedInstanceInfo(i)
			if sname == name and (not sdiff or sdiff == diff) and reset and reset > 0 then
				-- reset is seconds-until-reset; the absolute reset day identifies the lockout
				local resetDay = date("%Y-%m-%d", time() + reset)
				return "lock|" .. name .. "|" .. diff .. "|" .. resetDay, name, diff, mapID or 0
			end
		end
	end
	-- DUNGEON (or any non-locked instance): key by the per-ENTRY run token so each
	-- separate run is its own session, even the same dungeon twice in a day.
	if itype == "party" then
		return "run|" .. runToken() .. "|" .. name, name, diff, mapID or 0
	end
	-- world / unlocked raid fallback: group by day + zone
	return "day|" .. date("%Y-%m-%d") .. "|" .. name, name, diff, mapID or 0
end

-- current session = the one matching this lockout key, else start a new one
local function currentSession()
	local d = db()
	local key, name, diff, mapID = lockoutKey()
	local s = d.sessions[1]
	if s and s.key == key then return s end
	-- also match a non-newest session with the same key (e.g. you re-entered the
	-- same locked raid after logging something elsewhere in between)
	for i = 1, #d.sessions do
		if d.sessions[i].key == key then
			-- move it to the front so it's the "current" one
			local found = table.remove(d.sessions, i)
			table.insert(d.sessions, 1, found)
			return found
		end
	end
	s = { t = time(), day = date("%Y-%m-%d"), key = key,
		zone = name or "", difficulty = diff or 0, mapID = mapID or 0, drops = {} }
	table.insert(d.sessions, 1, s)
	while #d.sessions > MAX_SESSIONS do table.remove(d.sessions) end
	return s
end

-- Last boss we captured a corpse from, so chat-only need/greed drops (which
-- carry no boss of their own) can inherit it instead of showing "Unknown".
local lastBossName = nil

-- record all items on the currently-open corpse
local function captureLoot()
	if not Okanvil:ShouldRecord() then return end   -- dungeon/raid toggle
	local guid = UnitGUID("target")
	local tname = UnitName("target")
	-- Trust the target's NAME when we have one (guidIsNPC is unreliable on this
	-- server, so it only *upgrades* confidence, never discards a real name). If the
	-- corpse has NO name (target got cleared when a second looter opened it), fall
	-- back to the last real boss instead of writing "Unknown".
	local boss = (tname and tname ~= "") and tname or (lastBossName or "Unknown")
	if boss ~= "Unknown" then lastBossName = boss end
	if guid and seenCorpses[guid] then return end     -- already logged this corpse
	if guid then seenCorpses[guid] = true end

	local n = GetNumLootItems and GetNumLootItems() or 0
	if n == 0 then return end
	local s = currentSession()
	local added = 0
	-- auto-collect only when the toggle is ON and we're actually the ML
	local ml = L.CollectorsEnabled() and iAmMasterLooter()
	for i = 1, n do
		if LootSlotIsItem and LootSlotIsItem(i) then
			local _, lootName, qty, rarity = GetLootSlotInfo(i)
			local link = GetLootSlotLink(i)
			-- GetLootSlotInfo's rarity can be unreliable; fall back to GetItemInfo.
			local r = rarity
			if (not r or r == 0) and link then r = select(3, GetItemInfo(link)) end
			r = r or 0
			-- COLLECTOR auto master-loot: runs BEFORE the ignore filter, so shards/
			-- fragments (normally ignored) still route to their collector. Only when
			-- we're actually the ML and a collector is configured for that bucket.
			if ml and link then
				local bucket = collectorFor(link, lootName)   -- "frag" | "boe" | nil
				if bucket then
					-- fragment / BoE bucket: only auto-give if that collector HAS a name
					if L.CollectorName(bucket) ~= "" then
						L.AutoGive(i, bucket, link, lootName, qty or 1)
					end
				elseif not isIgnoredItem(link, lootName) then
					-- everything else = MAIN loot. ONLY auto-give if a "Main loot" name
					-- is set. Empty main = LEAVE IT ON THE CORPSE (roll it normally) --
					-- never silently sweep the whole boss to the ML. (User's rule.)
					if L.CollectorName("main") ~= "" then
						L.AutoGive(i, "main", link, lootName, qty or 1)
					end
				end
			end
			if link and r >= (Okanvil.db.lootThreshold or 3) and not isIgnoredItem(link, lootName) then
				local id = itemIDFromLink(link)
				-- DE-DUPE, done right:
				--  * If this corpse has a GUID, seenCorpses[guid] already blocked a
				--    repeat open above -- so EVERY slot here is a genuine drop, even
				--    two of the same item (boss really dropped 2x Scarlet Ruby). We
				--    must NOT drop the second one. So skip the itemID de-dupe entirely.
				--  * Only when the corpse has NO guid (target was cleared because a 2nd
				--    looter opened it) do we fall back to the 40s itemID window to avoid
				--    double-recording the same physical drop.
				local dup = (not guid) and recentlyLogged(id)
				if not dup then
					s.drops[#s.drops + 1] = {
						t = time(), boss = boss, item = link, id = id,
						name = lootName or "", rarity = r, qty = qty or 1,
					}
					added = added + 1
				end
			end
		end
	end
	if added > 0 then
		Okanvil:Print("Loot logged: " .. added .. " item(s) from " .. boss .. ".")
		if L.onLoot then L.onLoot() end
		-- tell the Logs module this boss dropped loot, so it can name a dungeon
		-- boss kill it saw die but couldn't identify from the raid list.
		if OkanvilLogs and OkanvilLogs.NoteBossFromLoot then OkanvilLogs.NoteBossFromLoot(boss) end
	end
end
L.CaptureLoot = captureLoot

-- START_LOOT_ROLL: the Blizzard need/greed/pass prompt just opened for `rollID`.
-- This is the RIGHT moment to pop the mini roll (RCLoot/RaidRoll do the same) --
-- record the item into the current session so DropsByBoss() shows it immediately,
-- instead of waiting for the win to be logged. Deduped by itemID (a roll can fire
-- alongside LOOT_OPENED for the same drop).
local function captureRollStart(rollID)
	if not Okanvil:ShouldRecord() then return end
	if not (rollID and GetLootRollItemLink) then return end
	local link = GetLootRollItemLink(rollID)
	if not link then return end
	local _, _, qty, quality = GetLootRollItemInfo(rollID)
	local r = quality or select(3, GetItemInfo(link)) or 0
	if r < (Okanvil.db.lootThreshold or 3) then return end
	if isIgnoredItem(link, nil) then return end
	local id = itemIDFromLink(link)
	local boss = lastBossName or "Need / Greed"
	-- Dedup only the RECORDING (don't add the same physical drop twice). But ALWAYS
	-- fire onLoot so the mini roll pops/refreshes for this roll -- otherwise closing
	-- the window on boss 1 and killing boss 2 wouldn't re-open it when the 2nd item
	-- happens to share an itemID with a recent one.
	if not recentlyLogged(id) then
		local s = currentSession()
		s.drops[#s.drops + 1] = {
			t = time(), boss = boss, item = link, id = id,
			name = (GetItemInfo(link)) or "", rarity = r, qty = qty or 1,
		}
	end
	-- no chat spam here -- the mini roll window IS the feedback (it pops with the item)
	if L.onLoot then L.onLoot() end
	if OkanvilLogs and OkanvilLogs.NoteBossFromLoot and boss ~= "Need / Greed" then
		OkanvilLogs.NoteBossFromLoot(boss)
	end
end

-- ------------------------------------------------------------
-- Collector config + counters (per collector: name + how many items auto-given).
-- Stored account-wide so an officer sets it once. counts = { [name] = n }.
-- ------------------------------------------------------------
function L.Collectors()
	local d = db()
	d.collectors = d.collectors or {}
	local c = d.collectors
	if c.main == nil then c.main = "" end        -- normal loot target ("" = nobody -> left on corpse)
	if c.frag == nil then c.frag = "" end
	if c.boe == nil then c.boe = "" end
	if c.enabled == nil then c.enabled = false end
	if c.whisper == nil then c.whisper = false end
	c.counts = c.counts or {}
	c.counts.main = c.counts.main or {}
	c.counts.frag = c.counts.frag or {}
	c.counts.boe = c.counts.boe or {}
	return c
end

-- whisper the winner on Award? (toggle on the Loot page)
function L.WhisperWinner() return L.Collectors().whisper and true or false end
function L.SetWhisperWinner(on)
	L.Collectors().whisper = on and true or false
	if L.onLoot then L.onLoot() end
end

-- editable whisper template ([item] = the itemlink). Like the MS/OS/Free messages.
local WHISPER_MSG_DEFAULT = "You won [item] -- gratz! Trade me when ready."
function L.WhisperMsg()
	local c = L.Collectors()
	return (c.whisperMsg and c.whisperMsg ~= "") and c.whisperMsg or WHISPER_MSG_DEFAULT
end
function L.SetWhisperMsg(text)
	L.Collectors().whisperMsg = (text and text ~= "") and text or nil
end

function L.SetCollector(bucket, name)
	local c = L.Collectors()
	c[bucket] = name or ""
	if L.onLoot then L.onLoot() end
end

-- the configured name for a bucket (main|frag|boe), trimmed. "" = nobody set ->
-- that bucket is NOT auto-given; the loot stays on the corpse for a normal roll.
function L.CollectorName(bucket)
	local n = L.Collectors()[bucket] or ""
	return (n:gsub("^%s*(.-)%s*$", "%1"))
end

-- master toggle for auto master-loot (off by default). When off, nothing is
-- auto-given even if you're the ML.
function L.CollectorsEnabled() return L.Collectors().enabled and true or false end
function L.SetCollectorsEnabled(on)
	L.Collectors().enabled = on and true or false
	if L.onLoot then L.onLoot() end
end

-- give loot slot `slot` to the configured collector for `bucket` (main|frag|boe)
-- and bump that person's counter. ALL THREE buckets: an empty name means "do
-- nothing" -- the loot is left on the corpse (never swept to the ML by default).
-- Safe: no-ops if no target set or the target can't receive the slot.
function L.AutoGive(slot, bucket, link, name, qty)
	local c = L.Collectors()
	local who = L.CollectorName(bucket)          -- trimmed; "" = nobody -> skip
	if who == "" then return false end
	local cand = mlCandidate(slot, who)
	if not cand then return false end       -- collector not eligible for this slot
	if GiveMasterLoot then GiveMasterLoot(slot, cand) end
	c.counts[bucket] = c.counts[bucket] or {}
	c.counts[bucket][who] = (c.counts[bucket][who] or 0) + (qty or 1)
	Okanvil:Print("Auto-loot: " .. (name or "item") .. " -> " .. who
		.. " (" .. bucket .. " #" .. c.counts[bucket][who] .. ").")
	if L.onLoot then L.onLoot() end
	return true
end

-- ------------------------------------------------------------
-- Roll-off tracker (free-for-all runs). Normal capture stands: whoever the game
-- gives an item keeps it. But on FFA runs an officer LINKS an item in raid /
-- raid-warning ("roll for this") and people /roll -- the highest roll is the real
-- winner. So: when an item is linked in raid/RW we open a short roll window for
-- that itemID; /rolls during it are collected; when it closes we reassign that
-- item's drop.receivedBy to the top roller (and mark it .rolledBy).
-- ------------------------------------------------------------
local ROLL_WINDOW = 120         -- seconds a roll-off stays open after the link
local activeRoll = nil          -- { id=, name=, link=, opened=, best={player,roll} }

-- Reassign the most recent drop of this itemID to `winner`. Prefers a drop that
-- has no roll-winner yet; falls back to the last drop with that id.
local function assignRollWinner(id, winner, topRoll, spec)
	if not id or not winner then return end
	local s = currentSession()
	local target
	for i = #s.drops, 1, -1 do
		if s.drops[i].id == id then target = target or s.drops[i]; if not s.drops[i].rolledBy then target = s.drops[i]; break end end
	end
	if not target then return end   -- item was never captured as a drop; nothing to fix
	target.receivedBy = winner
	target.rolledBy = winner
	target.rollValue = topRoll
	target.rollSpec = spec          -- "main" | "off"
	Okanvil:Print("Roll-off: " .. (target.name ~= "" and target.name or "item") .. " -> "
		.. winner .. " (" .. tostring(topRoll) .. (spec == "off" and ", offspec" or "") .. ").")
	if L.onLoot then L.onLoot() end
end

-- close the current roll-off and commit its winner (if anyone rolled)
local function closeRoll()
	if not activeRoll then return end
	local ar = activeRoll
	activeRoll = nil
	if ar.best then assignRollWinner(ar.id, ar.best.player, ar.best.roll, ar.best.spec) end
end

-- an item was linked in raid / raid-warning -> open a roll window for it.
-- `names` (optional) = the candidate list typed after the link ("roll [item]
-- okanor, grunho, rellik"); if present, only those players' rolls count.
local function openRoll(link, names, mode)
	if not Okanvil:ShouldRecord() then return end
	local id = itemIDFromLink(link)
	if id == 0 or isIgnoredItem(link, (GetItemInfo(link))) then return end
	closeRoll()                                   -- commit any previous roll-off first
	activeRoll = { id = id, link = link, name = (GetItemInfo(link)) or "",
		opened = GetTime(), best = nil, candidates = names, mode = mode or "free",
		list = {}, seen = {} }
	if L.onRoll then L.onRoll() end               -- mini-window refresh hook
end
L.OpenRoll = openRoll

-- current active roll-off (for the mini roll manager to read). nil = none open.
function L.ActiveRoll() return activeRoll end

-- Clear the drops the mini roll is showing (the newest session with drops). Used
-- by the mini roll's "Clear session" button -- wipe the current run's loot list
-- without deleting the whole session record. Also cancels any open roll-off.
function L.ClearActiveDrops()
	local s = newestSessionWithDrops()
	if not s then return false end
	closeRoll()                 -- commit/cancel any open roll-off
	wipe(s.drops)
	wipe(lastLoggedAt)          -- forget the de-dupe window so re-loot logs again
	if L.onLoot then L.onLoot() end
	return true
end

-- pick the channel for announcements (RW if we can, else raid/party). When SOLO
-- (not in a group) fall back to SAY so you can still test the whole flow alone.
local function announceChannel()
	if GetNumRaidMembers and GetNumRaidMembers() > 0 then
		return (IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer())
			and "RAID_WARNING" or "RAID"
	end
	if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
	return "SAY"   -- solo test bypass
end

-- Configurable announce templates. Use [item] as the itemlink placeholder.
-- Stored account-wide (officer sets once). Editable on the Loot page.
local ROLL_MSG_DEFAULTS = {
	ms   = "Roll [item]  --  MAIN SPEC  /roll (1-100)",
	os   = "Roll [item]  --  OFF SPEC  /roll 99 (1-99)",
	free = "Roll [item]  --  FREE  /roll (1-100)",
}
function L.RollMsg(mode)
	local d = db()
	d.rollMsg = d.rollMsg or {}
	return d.rollMsg[mode] or ROLL_MSG_DEFAULTS[mode] or ROLL_MSG_DEFAULTS.free
end
function L.SetRollMsg(mode, text)
	local d = db()
	d.rollMsg = d.rollMsg or {}
	-- empty -> fall back to the default
	d.rollMsg[mode] = (text and text ~= "") and text or nil
end

-- START a roll from the mini manager: announce the item + mode in raid/RW and
-- open the roll window. mode = "ms" | "os" | "free".
function L.StartRoll(link, mode)
	if not link then return end
	mode = mode or "free"
	openRoll(link, nil, mode)
	local chan = announceChannel()
	if chan then
		local msg = L.RollMsg(mode):gsub("%[item%]", link)
		SendChatMessage(msg, chan)
	end
	if L.onRoll then L.onRoll() end
end

-- STOP the current roll without awarding (manager "Stop Roll" button).
function L.StopRoll()
	activeRoll = nil
	if L.onRoll then L.onRoll() end
end

-- ROLL FOR YOURSELF -- a raider (or the loot master) hits Roll MS / Roll OS and
-- we fire the actual /roll for them: MS = /roll (1-100), OS = /roll 99 (1-99).
-- The result comes back as CHAT_MSG_SYSTEM and feeds the active roll like any other.
function L.SelfRoll(mode)
	if mode == "os" then RandomRoll(1, 99) else RandomRoll(1, 100) end
end

-- Try to hand the item to `winner` RIGHT NOW via master loot -- only works if a
-- loot window is open and still has that itemID in a slot the winner can take.
-- Returns true if the game accepted the give.
local function tryGiveNow(id, winner)
	if not (id and winner and GetNumLootItems and GiveMasterLoot) then return false end
	if (GetLootMethod and GetLootMethod()) ~= "master" then return false end
	for slot = 1, GetNumLootItems() do
		if LootSlotIsItem and LootSlotIsItem(slot) then
			local link = GetLootSlotLink(slot)
			if link and itemIDFromLink(link) == id then
				local cand = mlCandidate(slot, (winner:gsub("%-.*$", "")))
				if cand then GiveMasterLoot(slot, cand); return true end
			end
		end
	end
	return false
end

-- AWARD the item to `winner`. Marks the drop's owner, and:
--   * if the boss loot window is still OPEN with this item -> GIVE it now (master
--     loot straight to the winner -- no manual menu hunting);
--   * else -> optionally whisper "you won, trade me" (Whisper Winner toggle).
function L.AwardWinner(id, winner, topRoll, spec)
	if not (id and winner and winner ~= "") then return end
	assignRollWinner(id, winner, topRoll or 0, spec)
	local name = (GetItemInfo(id))
	local link
	local ar = activeRoll
	if ar and ar.id == id then link = ar.link end
	local itemStr = link or ("[" .. (name or "item") .. "]")

	local gave = tryGiveNow(id, winner)
	if gave then
		Okanvil:Print("Awarded (master loot): " .. itemStr .. " -> " .. winner .. ".")
	elseif L.WhisperWinner() then
		-- no open loot window -> the item is already in the ML's bags; ask for a trade.
		-- Uses the editable whisper template ([item] -> the link, [spec] -> off tag).
		local msg = L.WhisperMsg():gsub("%[item%]", itemStr)
			:gsub("%[spec%]", spec == "off" and "(offspec)" or "")
		SendChatMessage(msg, "WHISPER", nil, winner)
	end
	activeRoll = nil
	if L.onRoll then L.onRoll() end
end

-- Pull candidate names out of the text AFTER the item link. People are listed
-- like "okanor, grunho, rellik" (comma/space separated). Returns a lowercase
-- set { [name]=true } or nil if none were listed. Strips realm suffixes.
-- Words that are part of OUR announce templates, never candidate names. Stops
-- the manager's own "Roll [item] MAIN SPEC /roll 100" echo from being parsed as a
-- candidate list ("main","spec","roll" -> fake candidates that reject everyone).
local TEMPLATE_WORDS = {
	roll = true, main = true, spec = true, off = true, free = true, ["for"] = true,
	ms = true, os = true, pls = true, please = true,
}

local function parseCandidates(tail)
	if not tail or tail:find("%S") == nil then return nil end
	local set, n = {}, 0
	for word in tail:gmatch("[^%s,;/|]+") do
		local nm = word:gsub("%-.*$", "")               -- drop "-Realm"
		nm = nm:gsub("[^%a]", "")                        -- letters only
		local low = nm:lower()
		if #nm >= 2 and not TEMPLATE_WORDS[low] then set[low] = true; n = n + 1 end
	end
	return (n > 0) and set or nil
end

-- scan a raid / raid-warning message for item links and open a roll-off for each
-- (usually one). Candidate names typed after the link restrict who can win.
local function scanForLinkedItem(msg)
	if not msg then return end
	for link, tail in msg:gmatch("(|c%x+|Hitem:.-|h.-|h|r)(.*)") do
		-- IGNORE the manager's own announce echo: if we just opened a roll for this
		-- exact item (StartRoll), don't re-open it with a bogus candidate list.
		local id = itemIDFromLink(link)
		if activeRoll and activeRoll.id == id and (GetTime() - activeRoll.opened) < 5 then
			-- same item we just started -> skip
		else
			openRoll(link, parseCandidates(tail))
		end
	end
end

-- react to a /roll result. Rolls are TRANSIENT -- they only feed the active
-- roll-off so the Mini Roll Manager can pick a winner. We do NOT persist them in
-- the session (the session just records who RECEIVED each item, for export).
local ROLL_PATTERN = (RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)")
	:gsub("([%(%)%-])", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
local function captureRoll(msg)
	local who, roll, lo, hi = msg:match(ROLL_PATTERN)
	if not who then return end
	roll = tonumber(roll) or 0
	-- feed the active roll-off while its window is open. Guild convention:
	--   /roll  (1-100) = MAIN spec      /roll 99 (1-99) = OFF spec
	-- Main spec always beats off spec, even on a lower number; among the same
	-- spec the higher roll wins. Rolls with a max above 100 (custom /roll 1000
	-- etc.) aren't valid loot rolls -> ignored.
	local hiN = tonumber(hi) or 100
	local inWindow = activeRoll and (GetTime() - activeRoll.opened) <= ROLL_WINDOW
	-- if the RW listed candidates, only those players' rolls are eligible
	local eligible = true
	if inWindow and activeRoll.candidates then
		local key = who:gsub("%-.*$", ""):lower()
		eligible = activeRoll.candidates[key] == true
	end
	if inWindow and eligible and hiN <= 100 and roll <= 100 then
		local spec = (hiN >= 100) and "main" or "off"   -- 1-100 = main, 1-99 = off
		-- record the roll in the manager's list (one entry per player: first roll
		-- counts, extra rolls from the same person are ignored so nobody re-rolls).
		local key = who:gsub("%-.*$", "")
		if not activeRoll.seen[key] then
			activeRoll.seen[key] = true
			activeRoll.list[#activeRoll.list + 1] = { player = key, roll = roll, spec = spec }
		end
		local b = activeRoll.best
		-- new roll wins if: no best yet, OR it's main and best is off, OR same spec
		-- and a higher number (an off roll never overtakes a main).
		local better = (not b)
			or (spec == "main" and b.spec == "off")
			or (spec == b.spec and roll > b.roll)
		if better then
			activeRoll.best = { player = who, roll = roll, spec = spec }
		end
		if L.onRoll then L.onRoll() end
	end
	if L.onLoot then L.onLoot() end
end

-- ------------------------------------------------------------
-- Who received/won an item (CHAT_MSG_LOOT). Builds Lua patterns from the WoW
-- global strings so it works in any locale. Shapes we handle:
--   LOOT_ITEM_SELF   "You receive loot: %s."     -> item only (=you)
--   LOOT_ITEM        "%s receives loot: %s."      -> player, item
--   LOOT_ROLL_WON    "%s won: %s"                 -> player, item  (need/greed)
-- We tag the matching drop in the session with receivedBy, matched by itemID
-- (robust: the chat link and the loot-slot link can differ in formatting).
-- ------------------------------------------------------------
local function toPattern(globalStr, fallback)
	local s = globalStr or fallback
	s = s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", function(ch)
		return ch == "%" and "\1" or ("%" .. ch)   -- protect the %s/%d markers
	end)
	s = s:gsub("\1s", "(.+)"):gsub("\1d", "%%d+")
	return s
end
-- Patterns matched against CHAT_MSG_LOOT, mirroring MRT's LootHistory set.
-- Each entry: { pattern, selfPlayer, isDE } -- selfPlayer=true means the capture
-- is just the item (the player is you); false means (player, item). isDE=true
-- marks a "won ... (Disenchant)" line: the winner really won the ITEM, then chose
-- to disenchant it -- so we tag the item (de=true) and MUST NOT let the shard
-- byproduct that follows be logged as a second, phantom drop.
--
-- The DE patterns are listed FIRST because the plain "%s won: %s" pattern's (.+)
-- item capture would otherwise greedily swallow the " (Disenchant)" suffix and
-- mis-classify a disenchant as a normal win.
local PATTERNS = {
	{ toPattern(LOOT_ROLL_DISENCHANT_SELF, "You won: %s (Disenchant)"), true, true },
	{ toPattern(LOOT_ROLL_DISENCHANT, "%s won: %s (Disenchant)"), false, true },
	{ toPattern(LOOT_ROLL_YOU_WON, "You won: %s"), true },
	{ toPattern(LOOT_ROLL_WON, "%s won: %s"), false },
	{ toPattern(LOOT_ITEM_SELF_MULTIPLE, "You receive loot: %sx%d."), true },
	{ toPattern(LOOT_ITEM_MULTIPLE, "%s receives loot: %sx%d."), false },
	{ toPattern(LOOT_ITEM_SELF, "You receive loot: %s."), true },
	{ toPattern(LOOT_ITEM, "%s receives loot: %s."), false },
	{ toPattern(LOOT_ITEM_PUSHED_SELF, "You receive item: %s."), true },
	{ toPattern(LOOT_ITEM_PUSHED, "%s receives item: %s."), false },
}

-- Disenchant byproducts to swallow: after a "won ... (Disenchant)" line we record
-- (player -> expiry time) here; the next "receives loot: [Dream Shard]" style line
-- for that player within the window is the shard from the DE and is suppressed.
local DE_SHARD_IDS = { [34057]=true, [22450]=true, [22449]=true, [11135]=true,
	[10938]=true, [10940]=true, [10978]=true, [10998]=true, [11082]=true,
	[11083]=true, [11084]=true, [11134]=true, [11137]=true, [11139]=true,
	[11174]=true, [11175]=true, [11176]=true, [11177]=true, [11178]=true,
	[14343]=true, [14344]=true, [16202]=true, [16203]=true, [16204]=true,
	[20725]=true, [22445]=true, [22446]=true, [22447]=true, [22448]=true,
	[34052]=true, [34053]=true, [34054]=true, [34055]=true, [34056]=true }
local pendingDE = {}   -- player -> expiry (GetTime seconds)

-- tag the newest untagged drop with this itemID as received by player.
-- If no such drop exists (need/greed items you never open on the corpse),
-- create the drop from the chat link so nothing is missed. Honors the
-- rarity threshold.
local function tagReceiver(player, itemLink, isDE)
	if not itemLink or not player then return end
	local id = itemIDFromLink(itemLink)
	if id == 0 then return end
	local s = currentSession()
	local sawID = false
	for i = #s.drops, 1, -1 do
		local d = s.drops[i]
		if d.id == id then
			sawID = true
			if not d.receivedBy then
				d.receivedBy = player
				if isDE then d.de = true end
				if L.onLoot then L.onLoot() end
				return
			end
		end
	end
	-- The item was captured on a corpse (a drop with this ID exists) but every
	-- copy is already tagged -> this is a duplicate/echoed loot line, NOT a new
	-- drop. Bailing here is what prevents the phantom boss="" ("Unknown") rows.
	if sawID then return end
	-- never record ignored items (emblems/gems/mats) even if won via need/greed
	if isIgnoredItem(itemLink) then return end
	-- de-dupe: same item logged very recently on a corpse -> this chat line is the
	-- echo of that same drop from a second looter, not a new one.
	if recentlyLogged(id) then return end
	-- genuinely never seen on a corpse (need/greed you never opened) -> add it
	local name, _, rarity = GetItemInfo(itemLink)
	rarity = rarity or 0
	if rarity < (Okanvil.db.lootThreshold or 3) then return end
	-- inherit the last real corpse boss so a won-but-never-opened item groups under
	-- the right encounter. Prefer lastBossName over the live target: a "won/receives"
	-- chat line usually follows the kill, and the target might now be a PLAYER (a
	-- mate you're looting) -- which must NOT become the boss name.
	local boss = lastBossName
	if not boss or boss == "" then
		local tname = UnitName("target")
		if tname and tname ~= "" and guidIsNPC(UnitGUID("target")) then boss = tname else boss = "" end
	end
	s.drops[#s.drops + 1] = {
		t = time(), boss = boss, item = itemLink, id = id,
		name = name or "", rarity = rarity, qty = 1, receivedBy = player,
		de = isDE or nil,
	}
	if L.onLoot then L.onLoot() end
end

-- Some servers emit the same "X receives loot" / "X won" line on BOTH
-- CHAT_MSG_LOOT and CHAT_MSG_SYSTEM. Without this guard the line is processed
-- twice, and the 2nd pass (no untagged drop left) invents a phantom drop.
local lastReceiveMsg, lastReceiveT = nil, 0
local function captureReceive(msg)
	if not msg or msg == "" then return end
	if not Okanvil:ShouldRecord() then return end   -- dungeon/raid toggle
	local now = GetTime and GetTime() or 0
	if msg == lastReceiveMsg and (now - lastReceiveT) < 0.5 then return end
	lastReceiveMsg, lastReceiveT = msg, now
	for _, p in ipairs(PATTERNS) do
		local player, item
		if p[2] then                       -- self: capture is the item link
			item = msg:match(p[1])
			if item then player = UnitName("player") end
		else                               -- other: player then item
			player, item = msg:match(p[1])
		end
		if player and item then
			-- A DE byproduct (Dream Shard etc.) arrives as a plain "receives loot"
			-- line right after the winner's "(Disenchant)" line. If this player just
			-- disenchanted something and this is a known shard, swallow it so the one
			-- physical drop isn't logged twice (the real item + its shard).
			if not p[3] then
				local exp = pendingDE[player]
				if exp and now < exp and DE_SHARD_IDS[itemIDFromLink(item)] then
					pendingDE[player] = nil
					return
				end
			end
			tagReceiver(player, item, p[3])
			if p[3] then pendingDE[player] = now + 5 end   -- open shard-suppress window
			return
		end
	end
end

-- ------------------------------------------------------------
-- JSON export (type:"loot") -- separate from attendance
-- ------------------------------------------------------------
function L.SessionJSON(s)
	if not s then return "{}" end
	local guildName = GetGuildInfo("player") or "Guild"
	local realm = GetRealmName() or ""
	local drops = {}
	for _, d in ipairs(s.drops) do
		drops[#drops + 1] = string.format(
			'{"time":%d,"boss":"%s","itemID":%d,"name":"%s","rarity":%d,"qty":%d,"receivedBy":"%s",'
			.. '"rolledBy":"%s","rollValue":%d,"rollSpec":"%s","de":%s,"link":"%s"}',
			d.t, esc(d.boss), d.id, esc(d.name), d.rarity, d.qty, esc(d.receivedBy or ""),
			esc(d.rolledBy or ""), d.rollValue or 0, esc(d.rollSpec or ""),
			d.de and "true" or "false", esc(d.item)
		)
	end
	return string.format(
		'{"type":"loot","guildName":"%s","realm":"%s","capturedAt":%d,"day":"%s",'
		.. '"zone":"%s","mapID":%d,"difficulty":%d,"drops":[%s]}',
		esc(guildName), esc(realm), s.t, esc(s.day or ""),
		esc(s.zone), s.mapID or 0, s.difficulty, table.concat(drops, ",")
	)
end

-- ------------------------------------------------------------
-- Inline session renderer -- draws a session's drops (grouped by boss)
-- into caller-supplied pooled rows, so the Loot tab can expand a session in
-- place (no popup). `rowFn(idx, yTop)` must return a reusable Button row with
-- .icon and .txt (see UI.lua detailRow). Returns the advanced (idx, y).
-- Each item row gets a real item tooltip on hover + shift-click to link.
-- ------------------------------------------------------------
function L.RenderInline(s, rowFn, idx, y)
	local lastBoss = nil
	for _, d in ipairs(s.drops) do
		local header = (d.boss ~= "" and d.boss) or "Need / Greed"
		if header ~= lastBoss then
			lastBoss = header
			idx = idx + 1
			local hr = rowFn(idx, y)
			hr.txt:ClearAllPoints(); hr.txt:SetPoint("LEFT", hr, "LEFT", 0, 0)
			hr.txt:SetText("|cffffd200" .. header .. "|r")
			y = y + 20
		end
		idx = idx + 1
		local r = rowFn(idx, y)
		r.icon:Show()
		local tex = select(10, GetItemInfo(d.item)) or "Interface\\Icons\\INV_Misc_QuestionMark"
		r.icon:SetTexture(tex); r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
		r.txt:ClearAllPoints(); r.txt:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.txt:SetPoint("RIGHT", r, "RIGHT", -4, 0)
		local qty = (d.qty and d.qty > 1) and ("  |cff8a8d93x" .. d.qty .. "|r") or ""
		local who = d.receivedBy and d.receivedBy ~= ""
			and ("  |cff5e6166->|r |cffffd200" .. d.receivedBy .. "|r") or ""
		-- roll-off winner marker: a dice + the roll, and "(off)" for an offspec roll
		if d.rolledBy then
			who = who .. "  |cff7cfc8a[roll " .. tostring(d.rollValue or "?")
				.. (d.rollSpec == "off" and " off" or "") .. "]|r"
		end
		local de = d.de and "  |cff8a5ad9(DE)|r" or ""
		r.txt:SetText((d.item or ("[" .. (d.name or "?") .. "]")) .. qty .. who .. de)
		local link = d.item
		r:SetScript("OnEnter", function(self)
			if not link then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(link); GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		r:SetScript("OnClick", function()
			if link and IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
		end)
		y = y + 20
	end
	if #s.drops == 0 then
		idx = idx + 1
		local r = rowFn(idx, y)
		r.txt:ClearAllPoints(); r.txt:SetPoint("LEFT", r, "LEFT", 0, 0)
		r.txt:SetText("|cff888888No drops recorded.|r")
		y = y + 20
	end
	return idx, y
end

-- (The old popup viewer L.ShowSession was removed -- the Loot tab now renders
-- each session inline via L.RenderInline, so no separate window opens.)

-- ------------------------------------------------------------
-- Master-loot confirmation popup: when you zone into an instance AS the master
-- looter with auto-collect enabled, confirm (or open the Loot page to edit) the
-- fragment/BoE collector names before the run starts.
-- ------------------------------------------------------------
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["OKANVIL_ML_CONFIRM"] = {
	text = "",  -- filled per-show
	button1 = "Confirm",
	button2 = "Edit",
	OnAccept = function() Okanvil:Print("Auto master-loot ON for this run.") end,
	OnCancel = function()  -- "Edit" -> open the Loot page
		if Okanvil.Toggle then Okanvil:Toggle() end
		if Okanvil.ShowPanel then Okanvil:ShowPanel("__loot") end
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
}
local askedMLZone
local function maybeAskML()
	if not (L.CollectorsEnabled() and iAmMasterLooter()) then return end
	if not (IsInInstance and IsInInstance()) then return end
	local zone = (GetRealZoneText and GetRealZoneText()) or ""
	if zone == "" or zone == askedMLZone then return end
	askedMLZone = zone
	local c = L.Collectors()
	local frag = (c.frag ~= "" and c.frag) or "|cffff5555(none)|r"
	local boe = (c.boe ~= "" and c.boe) or "|cffff5555(none)|r"
	StaticPopupDialogs["OKANVIL_ML_CONFIRM"].text =
		"You are Master Looter in " .. zone .. ".\n\nAuto-loot:\n"
		.. "Fragments -> |cffffd200" .. frag .. "|r\n"
		.. "BoE / orbs -> |cffffd200" .. boe .. "|r\n\nConfirm these, or Edit to change."
	StaticPopup_Show("OKANVIL_ML_CONFIRM")
end

-- ============================================================
-- ML RE-SYNC AUTO-FLIP (the "RCLootCouncil master-loot bug").
--
-- On 3.3.5a the master-loot CANDIDATE LIST is server-populated only at the
-- moment you BECOME the ML. If the ML then DCs or uses a teleport (e.g. the
-- Ulduar port), they KEEP the ML title but their client LOSES the candidate
-- list -- GetMasterLootCandidate() returns nothing, so GiveMasterLoot finds no
-- one ("player offline?"). There is NO client API to re-request the list. The
-- only real fix is a fresh SetLootMethod, which ONLY the raid leader can call.
--
-- So the fix is split across two clients, over Okanvil.Comms:
--   * BROKEN ML (e.g. Kobe): detects "I'm the ML but my candidate list is
--     empty" and asks the group to re-sync   -> Comms.Send("MLFIX").
--   * RAID LEADER (e.g. Rellik): receives MLFIX, verifies the sender really IS
--     the current ML, then flips loot method to himself and back to that ML on
--     the next frame -> the server re-sends the candidate list. ACKs "MLFIXED".
--
-- Trust is by ROLE, not by the message: the leader re-checks live game state
-- before flipping (a spoofed MLFIX from a non-ML is ignored).
-- ============================================================

-- raid index of a player by name (1..MAX_RAID_MEMBERS), or nil. Used to build
-- the "raidN" unit token SetLootMethod wants.
local function raidIndexOf(name)
	if not (name and GetNumRaidMembers and GetRaidRosterInfo) then return nil end
	local short = name:gsub("%-.*$", "")
	for i = 1, GetNumRaidMembers() do
		local n = GetRaidRosterInfo(i)
		if n and n:gsub("%-.*$", "") == short then return i end
	end
	return nil
end

-- Is the master-loot candidate list HEALTHY for us right now? We're the ML but
-- can the game name at least one candidate? One hit = healthy.
--
-- CAVEAT (3.3.5a): GetMasterLootCandidate is only RELIABLE while a loot window is
-- open -- with no corpse open it can legitimately return nothing even when the
-- list is fine. So an empty result is only TRUSTWORTHY as "broken" when a loot
-- window is actually open (GetNumLootItems > 0). Callers that probe while idle
-- must treat a "false" as INCONCLUSIVE, not proof of breakage -- otherwise we'd
-- flip the ML needlessly. This function only reports raw list emptiness; the
-- `lootWindowOpen` helper below is what makes the signal trustworthy.
local function mlCandidateListOK()
	if not GetMasterLootCandidate then return true end   -- API missing -> don't cry wolf
	-- a live raid always has the player themself as a candidate; one hit = healthy
	for c = 1, 40 do
		if GetMasterLootCandidate(c) then return true end
	end
	return false
end

-- Is a loot window open right now? Only then is an empty candidate list a
-- RELIABLE "broken" signal (see the caveat above).
local function lootWindowOpen()
	return GetNumLootItems and GetNumLootItems() > 0
end

-- Who is the current master looter (name), or nil if loot method isn't master.
local function currentMasterLooterName()
	if not GetLootMethod then return nil end
	local method, partyML, raidML = GetLootMethod()
	if method ~= "master" then return nil end
	if raidML and raidML > 0 and GetRaidRosterInfo then
		return (GetRaidRosterInfo(raidML))
	end
	if partyML == 0 then return UnitName("player") end
	if partyML and partyML > 0 then
		return UnitName("party" .. partyML)
	end
	return nil
end

-- ----- BROKEN-ML side: detect + ask for a re-sync ----------------------------
local MLFIX_COOLDOWN = 15    -- seconds between our own re-sync requests (anti-flood)
local lastFixRequest = 0
local resyncPending = false  -- waiting for a leader ACK / a healthy list

-- Probe our ML health and, if RELIABLY broken, ask the group to re-sync us.
-- `requireWindow` (default true) makes us only ACT on the trustworthy signal --
-- an empty candidate list WHILE a loot window is open. When called on a zone-in
-- (requireWindow=false) with no loot open, an empty list is inconclusive, so we
-- don't request a flip; we just wait for the next LOOT_OPENED to confirm.
-- Debounced so a zone-in storm of events can't spam the request.
local function checkMLHealth(requireWindow)
	if requireWindow == nil then requireWindow = true end
	if not iAmMasterLooter() then resyncPending = false; return end
	if not (GetNumRaidMembers and GetNumRaidMembers() > 0) then return end  -- flip needs a raid leader
	if mlCandidateListOK() then
		-- healthy (maybe the leader just fixed us): clear any pending state
		if resyncPending then
			resyncPending = false
			Okanvil:Print("|cff7cfc8aMaster-loot re-synced.|r Candidate list restored.")
		end
		return
	end
	-- Empty list. Only TRUST it as "broken" when a loot window is open; otherwise
	-- it's just the API being quiet with no corpse open -> don't flip needlessly.
	if requireWindow and not lootWindowOpen() then return end
	-- BROKEN: we're ML but have no candidates. Ask the leader to flip us.
	local now = GetTime() or 0
	if now - lastFixRequest < MLFIX_COOLDOWN then return end
	lastFixRequest = now
	resyncPending = true
	local me = UnitName("player")
	if Okanvil.Comms and Okanvil.Comms.Send("MLFIX", me) then
		Okanvil:Print("|cffffd200Master-loot desynced|r (lost candidate list after DC/teleport). "
			.. "Asking the raid leader's Okanvil to re-sync...")
	else
		-- no comms channel or send failed -> degrade to the old social workaround
		Okanvil:Print("|cffff5555Master-loot desynced|r and no Okanvil leader answered -- "
			.. "ask the raid leader to reassign you as master looter.")
	end
end

-- ----- LEADER side: receive MLFIX, verify, flip, ACK -------------------------
local FLIP_COOLDOWN = 8     -- seconds we won't re-flip the SAME target (dedupe bursts)
local lastFlipFor = {}      -- name -> GetTime() of last flip we did for them

local function doMLFlip(mlName)
	-- ONLY the raid leader can SetLootMethod. Gate hard on role -- this is the
	-- anti-spoof check: a MLFIX from anyone is worthless unless WE are the leader.
	if not (IsRaidLeader and IsRaidLeader()) then return end
	if (GetLootMethod and GetLootMethod()) ~= "master" then return end   -- not on master loot; nothing to fix
	-- Verify the requester REALLY is the current ML (don't hand loot control to a
	-- random spoofer). If they aren't the ML the server reports, ignore.
	local realML = currentMasterLooterName()
	if not realML or realML:gsub("%-.*$", "") ~= mlName:gsub("%-.*$", "") then return end
	-- dedupe: don't re-flip the same person within the cooldown (MLFIX may repeat)
	local now = GetTime() or 0
	if lastFlipFor[mlName] and now - lastFlipFor[mlName] < FLIP_COOLDOWN then return end
	lastFlipFor[mlName] = now

	local myIdx = raidIndexOf(UnitName("player"))
	local mlIdx = raidIndexOf(mlName)
	if not (myIdx and mlIdx) then return end
	if myIdx == mlIdx then return end   -- the ML asking is us? nothing to flip against

	-- Flip: take ML for an instant, then give it back on a LATER frame so the
	-- server registers two distinct "set master looter" events and re-sends the
	-- candidate list to the original ML.
	SetLootMethod("master", "raid" .. myIdx)
	Okanvil.Comms.After(0.4, function()
		-- re-check we're still leader & still on master loot before handing back
		if not (IsRaidLeader and IsRaidLeader()) then return end
		SetLootMethod("master", "raid" .. mlIdx)
		Okanvil:Print("Re-synced master loot for |cffffd200" .. mlName .. "|r "
			.. "(ML flipped and restored).")
		-- tell their client we did it, so it re-probes and clears its warning
		Okanvil.Comms.Whisper("MLFIXED", mlName, UnitName("player"))
	end)
end

-- register the Comms handlers (load-order safe: Comms loaded before Modules)
if Okanvil.Comms then
	-- a broken ML asks us (the group) to re-sync them
	Okanvil.Comms.On("MLFIX", function(sender, mlName)
		-- The SENDER name comes from the server (CHAT_MSG_ADDON) and can't be forged,
		-- so trust it as the identity -- not the self-claimed mlName in the payload.
		-- doMLFlip still re-checks that this player really IS the current ML.
		doMLFlip(sender)
	end)
	-- the leader tells us they re-synced us -> re-probe our own list
	Okanvil.Comms.On("MLFIXED", function(sender)
		checkMLHealth()
	end)
end

-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("LOOT_OPENED")
ev:RegisterEvent("START_LOOT_ROLL")   -- Blizzard need/greed/pass prompt just opened
ev:RegisterEvent("CHAT_MSG_SYSTEM")   -- /roll results
ev:RegisterEvent("CHAT_MSG_LOOT")     -- who received which item
ev:RegisterEvent("CHAT_MSG_RAID_WARNING")  -- officer links "roll for [item]"
ev:RegisterEvent("CHAT_MSG_RAID")          -- item linked in raid chat
ev:RegisterEvent("CHAT_MSG_RAID_LEADER")
ev:RegisterEvent("CHAT_MSG_PARTY")         -- 5-man: item linked in party chat
ev:RegisterEvent("CHAT_MSG_PARTY_LEADER")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")  -- zoned in -> maybe confirm ML collectors
ev:RegisterEvent("PARTY_LOOT_METHOD_CHANGED") -- became ML mid-run -> re-check
ev:RegisterEvent("PLAYER_LEAVING_WORLD")
ev:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "LOOT_OPENED" then
		captureLoot()
		-- if we're the ML and the candidate list is empty right when a corpse is
		-- open, giving would fail HERE -- request a re-sync immediately (debounced).
		if iAmMasterLooter() and not mlCandidateListOK() then checkMLHealth() end
	elseif event == "START_LOOT_ROLL" then
		captureRollStart(arg1)   -- arg1 = rollID; record the item + pop the mini roll NOW
	elseif event == "CHAT_MSG_LOOT" then
		captureReceive(arg1 or "")
	elseif event == "CHAT_MSG_SYSTEM" then
		captureRoll(arg1 or "")
		captureReceive(arg1 or "")   -- some servers send "X won: [item]" here
	elseif event == "CHAT_MSG_RAID_WARNING" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER"
		or event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
		scanForLinkedItem(arg1 or "")   -- open a roll-off if an item was linked
	elseif event == "PLAYER_ENTERING_WORLD" or event == "PARTY_LOOT_METHOD_CHANGED" then
		-- Detect a FRESH dungeon entry: if we're now inside a party instance and
		-- weren't a moment ago, bump the run token so this run gets its own session
		-- (fixes two runs of the same dungeon on one day sharing a loot entry).
		-- A /reload or login (arg1=isInitialLogin, arg2=isReloadingUi) is NOT a fresh
		-- entry -- we're resuming, so don't bump (that would split an ongoing run).
		if event == "PLAYER_ENTERING_WORLD" then
			local isLogin, isReload = arg1, arg2
			local inInst, itype = IsInInstance and IsInInstance()
			if inInst and itype == "party" then
				if not wasInInstance and not isLogin and not isReload then
					runToken(true)   -- fresh entry -> new session key
				end
				wasInInstance = true
			elseif not inInst then
				wasInInstance = false
			end
		end
		maybeAskML()
		-- NOTE: we DON'T probe ML health on zone-in -- with no loot window open the
		-- candidate list reads empty even when it's fine (see mlCandidateListOK's
		-- caveat), so it can't be trusted yet. The reliable detection happens on the
		-- next LOOT_OPENED (ML + open corpse + empty list = genuinely broken).
	elseif event == "PLAYER_LEAVING_WORLD" then
		askedMLZone = nil   -- ask again next instance
		closeRoll()   -- commit any open roll-off before we lose the session context
		-- new instance next time -> allow the same corpse GUIDs to be seen again
		-- and forget the last boss + dedup window so they can't leak forward.
		wipe(seenCorpses)
		wipe(lastLoggedAt)
		lastBossName = nil
		-- reset ML re-sync state so a pending request / cooldown can't leak into the
		-- next instance (fresh ML context each time we zone).
		resyncPending = false
		lastFixRequest = 0
	end
end)

-- auto-close a roll-off once its window elapses (so the winner is committed even
-- if nobody links a new item afterwards). Cheap: only ticks while one is open.
ev:SetScript("OnUpdate", function(_, elapsed)
	if not activeRoll then return end
	if (GetTime() - activeRoll.opened) > ROLL_WINDOW then closeRoll() end
end)

-- FALLBACK trigger: some servers don't deliver START_LOOT_ROLL cleanly, but the
-- Blizzard need/greed dialog (GroupLootFrame1..4) always shows for a group-loot
-- roll. Hook its OnShow -> read its rollID -> run the same capture. This guarantees
-- the mini roll pops the moment the need/greed prompt appears.
do
	local function hookGLF(frame)
		if not frame or frame._okvHooked then return end
		frame._okvHooked = true
		frame:HookScript("OnShow", function(self)
			local rid = self.rollID or (self:GetID())
			if rid then captureRollStart(rid) end
		end)
	end
	-- hook the ones that exist now...
	for i = 1, 4 do hookGLF(_G["GroupLootFrame" .. i]) end
	-- ...and any created later (Blizzard makes them lazily) via the global creator.
	if type(GroupLootFrame_OpenNewFrame) == "function" then
		hooksecurefunc("GroupLootFrame_OpenNewFrame", function()
			for i = 1, 4 do hookGLF(_G["GroupLootFrame" .. i]) end
		end)
	end
end
