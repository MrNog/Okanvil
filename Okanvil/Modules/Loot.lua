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
-- Storage: db.loot.sessions = { {t, zone, difficulty, drops={...}, rolls={...}}, ... }
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

local function db()
	Okanvil.db.loot = Okanvil.db.loot or {}
	Okanvil.db.loot.sessions = Okanvil.db.loot.sessions or {}
	return Okanvil.db.loot
end

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

function L.DeleteSession(sess)
	local list = Okanvil.db.loot and Okanvil.db.loot.sessions
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == sess then table.remove(list, i); break end
	end
	if L.onLoot then L.onLoot() end
end

-- current session = the newest one if it's from today, else start a new one
local function currentSession()
	local d = db()
	local s = d.sessions[1]
	local today = date("%Y-%m-%d")
	if s and s.day == today then return s end
	s = { t = time(), day = today, zone = "", difficulty = 0, mapID = 0, drops = {}, rolls = {} }
	if GetInstanceInfo then
		-- 3.3.5a: name, type, difficulty, difficultyName, maxPlayers, dynDiff, isDyn, mapID
		local name, _, diff, _, _, _, _, mapID = GetInstanceInfo()
		s.zone, s.difficulty, s.mapID = name or "", diff or 0, mapID or 0
	end
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
	for i = 1, n do
		if LootSlotIsItem and LootSlotIsItem(i) then
			local _, lootName, qty, rarity = GetLootSlotInfo(i)
			local link = GetLootSlotLink(i)
			-- GetLootSlotInfo's rarity can be unreliable; fall back to GetItemInfo.
			local r = rarity
			if (not r or r == 0) and link then r = select(3, GetItemInfo(link)) end
			r = r or 0
			if link and r >= (Okanvil.db.lootThreshold or 3) and not isIgnoredItem(link, lootName) then
				local id = itemIDFromLink(link)
				-- de-dupe: two people opening the same corpse fires LOOT_OPENED twice.
				-- If we already logged this exact itemID very recently (same corpse,
				-- different loot window), skip it instead of double-recording.
				if not recentlyLogged(id) then
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

-- record a /roll result (extra context; winner decided on the hub)
local ROLL_PATTERN = (RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)")
	:gsub("([%(%)%-])", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
local function captureRoll(msg)
	local who, roll, lo, hi = msg:match(ROLL_PATTERN)
	if not who then return end
	local s = currentSession()
	s.rolls[#s.rolls + 1] = {
		t = time(), player = who, roll = tonumber(roll) or 0,
		min = tonumber(lo) or 1, max = tonumber(hi) or 100,
	}
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
			'{"time":%d,"boss":"%s","itemID":%d,"name":"%s","rarity":%d,"qty":%d,"receivedBy":"%s","de":%s,"link":"%s"}',
			d.t, esc(d.boss), d.id, esc(d.name), d.rarity, d.qty, esc(d.receivedBy or ""),
			d.de and "true" or "false", esc(d.item)
		)
	end
	local rolls = {}
	for _, r in ipairs(s.rolls) do
		rolls[#rolls + 1] = string.format(
			'{"time":%d,"player":"%s","roll":%d,"min":%d,"max":%d}',
			r.t, esc(r.player), r.roll, r.min, r.max
		)
	end
	return string.format(
		'{"type":"loot","guildName":"%s","realm":"%s","capturedAt":%d,"day":"%s",'
		.. '"zone":"%s","mapID":%d,"difficulty":%d,"drops":[%s],"rolls":[%s]}',
		esc(guildName), esc(realm), s.t, esc(s.day or ""),
		esc(s.zone), s.mapID or 0, s.difficulty, table.concat(drops, ","), table.concat(rolls, ",")
	)
end

-- ------------------------------------------------------------
-- Inline session renderer -- draws a session's drops (grouped by boss) + rolls
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
	if #s.rolls > 0 then
		y = y + 4
		idx = idx + 1
		local hr = rowFn(idx, y)
		hr.txt:ClearAllPoints(); hr.txt:SetPoint("LEFT", hr, "LEFT", 0, 0)
		hr.txt:SetText("|cff8a8d93Rolls|r")
		y = y + 20
		for _, roll in ipairs(s.rolls) do
			idx = idx + 1
			local r = rowFn(idx, y)
			r.txt:ClearAllPoints(); r.txt:SetPoint("LEFT", r, "LEFT", 4, 0); r.txt:SetPoint("RIGHT", r, "RIGHT", -4, 0)
			r.txt:SetText(roll.player .. "  |cffffd200" .. roll.roll .. "|r |cff5e6166(" .. roll.min .. "-" .. roll.max .. ")|r")
			y = y + 20
		end
	end
	return idx, y
end

-- (The old popup viewer L.ShowSession was removed -- the Loot tab now renders
-- each session inline via L.RenderInline, so no separate window opens.)

-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("LOOT_OPENED")
ev:RegisterEvent("CHAT_MSG_SYSTEM")   -- /roll results
ev:RegisterEvent("CHAT_MSG_LOOT")     -- who received which item
ev:RegisterEvent("PLAYER_LEAVING_WORLD")
ev:SetScript("OnEvent", function(_, event, arg1)
	if event == "LOOT_OPENED" then
		captureLoot()
	elseif event == "CHAT_MSG_LOOT" then
		captureReceive(arg1 or "")
	elseif event == "CHAT_MSG_SYSTEM" then
		captureRoll(arg1 or "")
		captureReceive(arg1 or "")   -- some servers send "X won: [item]" here
	elseif event == "PLAYER_LEAVING_WORLD" then
		-- new instance next time -> allow the same corpse GUIDs to be seen again
		-- and forget the last boss + dedup window so they can't leak forward.
		wipe(seenCorpses)
		wipe(lastLoggedAt)
		lastBossName = nil
	end
end)
