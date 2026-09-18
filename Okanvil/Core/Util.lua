-- ============================================================
-- Okanvil -- shared utilities (Okanvil.U).
--
-- A home for the small string/link helpers that several modules need, so the
-- same code stops living copied in two places. Loads right after Core.lua and
-- before any module, so `Okanvil.U.*` is ready by the time modules run.
--
--   Okanvil.U.esc(s)            -> JSON string escape (WoW strings are UTF-8)
--   Okanvil.U.escPattern(s)     -> escape Lua-pattern magic chars, for building
--                                  runtime patterns from chat-message templates
--   Okanvil.U.itemIDFromLink(l) -> numeric item id from a link (0 if none)
--   Okanvil.U.shortLink(l)      -> the "item:1234:..." span of a link (nil if none)
--   Okanvil.U.guildRankOf(n)    -> that member's rankIndex (nil if not in guild)
--   Okanvil.U.isOfficer(n)      -> rankIndex <= 1 (guild master or officer)
--   Okanvil.U.isMyChar(n)       -> one of the owner's own characters
--   Okanvil.U.canSeePrio(n)     -> may see the loot priority list
-- ============================================================

local Okanvil = Okanvil
local U = {}
Okanvil.U = U

-- JSON string escape. WoW strings are already UTF-8, so raw bytes are valid
-- JSON; we only need to escape the structural characters.
function U.esc(s)
	s = tostring(s or "")
	return (s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t"))
end

-- Escape the magic characters so an arbitrary literal string can be dropped into
-- a Lua pattern. Used when a chat-message template ("%s rolled Need") is turned
-- into a matcher at runtime.
function U.escPattern(t)
	return (tostring(t or ""):gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"))
end

function U.itemIDFromLink(link)
	return link and tonumber(link:match("item:(%d+)")) or 0
end

function U.shortLink(link)
	return link and link:match("(item:[%-%d:]+)") or nil
end

-- Instance name -> the short form the raid actually says ("Trial of the Crusader"
-- -> "ToC"). Long names wrap and overlap the line beneath them in the tooltip and
-- eat the whole column in a list, so anywhere a raid is named in a tight space it
-- goes through here.
--
-- Keyed on a lowercased SUBSTRING, not the full name: the server spells the same
-- instance differently across locales and lockout APIs ("Trial of the Crusader",
-- "Trial of the Grand Crusader"), and matching a fragment survives that.
--
-- ORDER MATTERS -- "grand crusader" must be tested before "crusader", or ToGC
-- would match the ToC rule first and both would read "ToC".
local RAID_SHORT = {
	{ "trial of the grand crusader", "ToGC" },
	{ "trial of the crusader",       "ToC"  },
	{ "trial of the champion",       "ToC5" },   -- the 5-man, not the raid
	{ "icecrown citadel",            "ICC"  },
	{ "ruby sanctum",                "RS"   },
	{ "onyxia",                      "Ony"  },
	{ "ulduar",                      "Uld"  },
	{ "naxxramas",                   "Naxx" },
	{ "obsidian sanctum",            "OS"   },
	{ "eye of eternity",             "EoE"  },
	{ "vault of archavon",           "VoA"  },
	{ "halls of reflection",         "HoR"  },
	{ "pit of saron",                "PoS"  },
	{ "forge of souls",              "FoS"  },
	{ "ahn'kahet",                   "AK"   },
	{ "violet hold",                 "VH"   },
	{ "the oculus",                  "Oculus" },
}

-- maxLen: only shorten when the name is actually too long for the space (nil = always).
function U.raidShort(name, maxLen)
	if not name or name == "" then return name end
	if maxLen and #name <= maxLen then return name end
	local low = name:lower()
	for _, e in ipairs(RAID_SHORT) do
		if low:find(e[1], 1, true) then return e[2] end
	end
	-- No abbreviation known: cut it rather than let it wrap over the next line.
	if maxLen and #name > maxLen then return name:sub(1, maxLen - 2) .. ".." end
	return name
end

-- ------------------------------------------------------------
-- Who is allowed to see officer-only material (the loot priority list).
--
-- By rank INDEX, not rank name: 0 is the guild master and 1 the officer rank
-- below him, whatever the guild has called them this month. Matching on names
-- would break the day someone renames a rank.
--
-- This hides material from people who have no use for it, and stops a stale list
-- overwriting a good one. It is NOT a security boundary: the roster comes from
-- the player's own client and an addon on someone's disk can be edited. Anything
-- that truly must not leak belongs behind the website's login, not in here.
-- ------------------------------------------------------------
local OFFICER_MAX_RANK = 1

-- ------------------------------------------------------------
-- Guild ranks, read from the guild -- never assumed.
--
-- Okanvil ships to whatever guild installs it, so nothing may be keyed to one
-- guild's rank NAMES. What is universal is the shape: index 0 is the guild
-- master, indices count down in authority, and the last index is the bottom
-- rank. The names are discovered from the roster and used for DISPLAY only.
-- ------------------------------------------------------------

-- Every rank the guild actually has, as { [index] = "Name" }, plus the highest
-- index seen. Built from the roster because 3.3.5a has no reliable rank-name
-- call outside the guild-control frame.
function U.guildRanks()
	local names, maxIdx = {}, -1
	if not (IsInGuild and IsInGuild()) then return names, maxIdx end
	for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
		local _, rank, rankIndex = GetGuildRosterInfo(i)
		if rankIndex and rank and rank ~= "" then
			names[rankIndex] = rank
			if rankIndex > maxIdx then maxIdx = rankIndex end
		end
	end
	return names, maxIdx
end

-- A rank's own name, for labels and dropdowns. Falls back to "Rank N" so a UI
-- built before the roster arrives still reads sensibly.
function U.rankName(idx)
	if not idx then return "" end
	local names = U.guildRanks()
	return names[idx] or ("Rank " .. idx)
end

-- rankIndex for a guild member by name, or nil when not in the guild / not found.
function U.guildRankOf(name)
	if not name or name == "" or not IsInGuild or not IsInGuild() then return nil end
	name = name:gsub("%-.*$", "")
	for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
		local n, _, rankIndex = GetGuildRosterInfo(i)
		if n and n:gsub("%-.*$", "") == name then return rankIndex end
	end
	return nil
end

-- Is this name an officer (GM included)? Used both to gate the UI and to decide
-- whether an incoming priority list may be trusted.
function U.isOfficer(name)
	local idx = U.guildRankOf(name)
	return idx ~= nil and idx <= OFFICER_MAX_RANK
end

-- "One of my characters." Account-wide, so an alt on a low rank still sees the
-- list the main imported -- the alternative was locking the owner out of his own
-- data because this toon happens to be ranked as an alt.
function U.isMyChar(name)
	if not name or name == "" then return false end
	name = name:gsub("%-.*$", "")
	if name == (UnitName("player") or "") then return true end
	local mine = Okanvil.db and Okanvil.db.myChars
	return (mine and mine[name]) and true or false
end

-- Colour for a rank, by POSITION rather than by name. Index 0 is the guild
-- master and gets the top colour; the rest step down the scale toward the
-- bottom rank. This used to match on one guild's rank names ("warchief rat",
-- "sewer"), which meant every other guild fell through to the default grey.
--
-- Alts are handled by the caller: an alt keeps its own muted colour whatever
-- rank it sits on.
local RANK_COLORS = {
	"ffc659ff",   -- guild master: purple
	"ffff4d4d",   -- officers: red
	"ffffa030",   -- orange
	"ffffe049",   -- yellow
	"ff9fd45a",   -- green
	"ff8a8d93",   -- anything deeper: grey
}
function U.rankColor(idx)
	if not idx then return RANK_COLORS[#RANK_COLORS] end
	local _, maxIdx = U.guildRanks()
	if not maxIdx or maxIdx <= 0 then return RANK_COLORS[1] end
	-- Spread this guild's ranks across the whole scale, whether it has four ranks
	-- or ten. Clamping instead (idx+1) left every rank past the fifth on the same
	-- grey, so a ten-rank guild could not tell its lower half apart.
	local step = math.floor(idx * (#RANK_COLORS - 1) / maxIdx + 0.5) + 1
	return RANK_COLORS[math.max(1, math.min(step, #RANK_COLORS))]
end

-- The bottom rank, whatever it is called. What "the newest members" means in a
-- guild that never renamed anything, and the sensible default for a welcome
-- toast -- rather than hardcoding one guild's word for it.
function U.lowestRankIndex()
	local _, maxIdx = U.guildRanks()
	return (maxIdx >= 0) and maxIdx or nil
end

-- The gate the loot-priority UI asks. Officer by rank, or a character the owner
-- has claimed as their own.
function U.canSeePrio(name)
	name = name or UnitName("player") or ""
	return U.isOfficer(name) or U.isMyChar(name)
end
