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
--   Okanvil.U.isOfficer(n)      -> on a rank with officer chat (guild master included)
--   Okanvil.U.isOfficerRank(i)  -> that rank index is an officer rank
--   Okanvil.U.raiderRank()      -> the raider rank: first non-alt rank below the officers
--   Okanvil.U.mainOf(n)         -> the main an alt belongs to (from guild notes)
--   Okanvil.U.toonsOf(n)        -> that person's main and alts, main first
--   Okanvil.U.isOfficerAlt(n)   -> an alt whose main is an officer
--   Okanvil.U.canSeePrio(n)     -> may see the loot priority list
--   Okanvil.U.raidMode()        -> "10n" / "25n" / "10h" / "25h" in a raid, else nil
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

-- Break text into lines of at most `width` characters, splitting on spaces.
-- GameTooltip's own wrap cuts a long line off with "..." after a few rows, so
-- callers that need the whole text add these lines one by one, unwrapped.
-- A single word longer than `width` gets a line to itself, uncut.
-- A chat link ("|c..|H..|h[The Light of Dawn]|h|r") is one unbreakable word:
-- split across lines its escape codes break and the name shows half-coloured
-- or not at all. Width counts visible characters, not the hidden codes.
local function visibleLen(s)
	return #(s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""))
end

function U.wrapLines(text, width)
	text = tostring(text or "")
	-- protect spaces inside links so the word split below keeps each link whole
	text = text:gsub("|H.-|h.-|h", function(link) return (link:gsub(" ", "\1")) end)
	local lines, cur, curLen = {}, "", 0
	for word in text:gmatch("%S+") do
		word = word:gsub("\1", " ")
		local len = visibleLen(word)
		if cur == "" then
			cur, curLen = word, len
		elseif curLen + 1 + len <= width then
			cur, curLen = cur .. " " .. word, curLen + 1 + len
		else
			lines[#lines + 1] = cur
			cur, curLen = word, len
		end
	end
	if cur ~= "" then lines[#lines + 1] = cur end
	return lines
end

-- Class words in LFM spam ("Ppala", "BOOMIE", "Resto Sham") painted in their
-- class colour, so a long message reads by role at a glance. Only whole letter
-- runs match, and words carrying escape codes (links, colours) are left alone.
local CLASS_WORD_HEX = {}
local function classWords(hex, list)
	for w in list:gmatch("%S+") do CLASS_WORD_HEX[w] = hex end
end
classWords("c41f3b", "dk dks bdk fdk udk deathknight deathknights")
classWords("ff7d0a", "druid druids dudu rdudu rdruid boomie boomies boomy boomkin boomkins moonkin feral ferals bear kitty")
classWords("abd473", "hunter hunters hunt hunts")
classWords("69ccf0", "mage mages fmage amage")
classWords("f58cba", "pala palas pal paladin paladins pally pallies ppala ppal hpala hpal hpally ppally ret rets retri")
classWords("ffffff", "priest priests spriest spriests hpriest dpriest disc")
classWords("fff569", "rogue rogues rog")
classWords("0070de", "sham shams shaman shamans shammy rsham esham ele enh enha")
classWords("9482c9", "lock locks warlock warlocks wl demo affli")
classWords("c79c6e", "warr warrs warrior warriors fwarr pwarr fury arms")

-- One letter run. Spam glues a count and a spec letter on: "1xHpala" reaches here
-- as "xHpala", "1xRshaman" as "xRshaman". So the run is tried as it is, then
-- without a leading "x" (the count's), then -- only after such an "x", where it is
-- surely spam -- without the spec's letter too (R-shaman, C-rog). A plain word
-- is never cut down into a class ("warms" stays "warms").
local function paintRun(run)
	local low = run:lower()
	local hex = CLASS_WORD_HEX[low]
	local lead = ""
	if not hex and low:sub(1, 1) == "x" and #low > 2 then
		lead, low = run:sub(1, 1), low:sub(2)
		hex = CLASS_WORD_HEX[low]
	end
	if not hex and lead ~= "" and #low >= 4 then
		hex = CLASS_WORD_HEX[low:sub(2)]
	end
	if not hex then return run end
	-- the count's "x" stays uncoloured; the spec letter is painted with its class
	return lead .. "|cff" .. hex .. run:sub(#lead + 1) .. "|r"
end

function U.paintClasses(text)
	text = tostring(text or "")
	return (text:gsub("%S+", function(word)
		if word:find("|", 1, true) then return word end
		return (word:gsub("%a+", function(run)
			return paintRun(run)
		end))
	end))
end

-- Accepts a link, a bare "item:50735", or a plain item ID (string or number).
-- The number case is not hypothetical: GetInventoryItemID and the council's wire
-- both hand IDs straight over, and `link:match` on a number throws "attempt to
-- index local 'link' (a number value)" -- the same shape as the guidIsNPC bug
-- documented below. tostring() first and every form works.
function U.itemIDFromLink(link)
	if not link then return 0 end
	if type(link) == "number" then return link end
	link = tostring(link)
	return tonumber(link:match("item:(%d+)")) or tonumber(link) or 0
end

-- Is this GUID an NPC -- a creature or a vehicle -- rather than a player?
--
-- A 3.3.5a GUID is "0xF130..." and the nibble at position 5 carries the unit
-- type: 3 (mod 8) is a creature, 5 a vehicle. Vehicles count because several
-- bosses are one to the client (Putricide, the Gunship): taking the creature type
-- alone made a dead Putricide "not an NPC", so opening his corpse recorded
-- nothing. The catch is that the GUID does not always arrive as
-- a STRING: some cores hand COMBAT_LOG_EVENT_UNFILTERED a number, and calling
-- :sub() on that throws "attempt to index local 'destGUID' (a number value)" --
-- which is exactly what the farm tracker's kill counter did, 42 times in one
-- dungeon, leaving it stuck at zero. tostring() first and both shapes work.
function U.guidIsNPC(guid)
	if not guid then return false end
	guid = tostring(guid)
	-- a numeric GUID loses the "0x" and may be shorter, so read the type nibble
	-- from a normalised 16-digit hex string rather than a fixed offset
	local hex = guid:match("^0[xX](%x+)$") or guid:match("^(%x+)$")
	if not hex then return false end
	if #hex < 16 then hex = string.rep("0", 16 - #hex) .. hex end
	local b = tonumber(hex:sub(3, 3), 16)
	return b ~= nil and ((b % 8) == 3 or (b % 8) == 5)
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
	-- The Burning Crusade and Classic raids: people run them for transmog and
	-- mounts, and their lockouts show up beside the current tier.
	{ "sunwell",                     "SWP"  },
	{ "black temple",                "BT"   },
	{ "hyjal",                       "Hyjal" },
	{ "zul'aman",                    "ZA"   },
	{ "serpentshrine",               "SSC"  },
	{ "tempest keep",                "TK"   },
	{ "magtheridon",                 "Mag"  },
	{ "gruul",                       "Gruul" },
	{ "karazhan",                    "Kara" },
	{ "ruins of ahn'qiraj",          "AQ20" },   -- before the temple, which also says "ahn'qiraj"
	{ "ahn'qiraj",                   "AQ40" },
	{ "blackwing lair",              "BWL"  },
	{ "zul'gurub",                   "ZG"   },
	{ "molten core",                 "MC"   },
}

-- Raids in the order a lockout list shows them: the current tier first, then
-- back through the expansion, then The Burning Crusade, then Classic. Matched
-- on the same lowercased substrings as RAID_SHORT. A raid missing from here
-- still shows -- it sorts after every listed one, by name.
local RAID_ORDER = {
	"ruby sanctum", "icecrown citadel", "trial of the grand crusader", "trial of the crusader",
	"onyxia", "ulduar", "naxxramas", "obsidian sanctum", "eye of eternity", "vault of archavon",
	"sunwell", "black temple", "hyjal", "zul'aman", "serpentshrine", "tempest keep",
	"magtheridon", "gruul", "karazhan",
	"ruins of ahn'qiraj", "ahn'qiraj", "blackwing lair", "zul'gurub", "molten core",
}

-- Where a raid sits in RAID_ORDER; unknown raids get a number past the end.
function U.raidRank(name)
	local low = (name or ""):lower()
	for i, key in ipairs(RAID_ORDER) do
		if low:find(key, 1, true) then return i end
	end
	return #RAID_ORDER + 1
end

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
-- An officer rank is one the guild itself gave officer chat to, read from the
-- rank's own permissions. Not by name and not by a fixed index: a guild can add,
-- rename or reorder ranks in game and the answer follows with no code change.
-- When the client cannot give the permissions, the top two ranks (guild master
-- and the rank below) stand in.
--
-- This hides material from people who have no use for it, and stops a stale list
-- overwriting a good one. It is NOT a security boundary: the roster comes from
-- the player's own client and an addon on someone's disk can be edited. Anything
-- that truly must not leak belongs behind the website's login, not in here.
-- ------------------------------------------------------------
local FALLBACK_OFFICER_MAX_RANK = 1
-- GuildControlGetRankFlags order: 1 guild chat listen, 3 officer chat listen
local FLAG_GCHAT_LISTEN, FLAG_OCHAT_LISTEN = 1, 3

-- { [rankIndex] = true } for every officer rank, or nil when the permissions
-- could not be read. Ranks are numbered from 1 (guild master) in the
-- guild-control calls and from 0 in the roster.
local officerRanksCache
local function officerRanks()
	if officerRanksCache then return officerRanksCache end
	if not (GuildControlGetNumRanks and GuildControlSetRank and GuildControlGetRankFlags) then return nil end
	-- Selecting a rank moves the guild-control frame's own selection: leave it alone
	-- while the guild master has it open.
	if GuildControlPopupFrame and GuildControlPopupFrame:IsShown() then return nil end
	local n = GuildControlGetNumRanks() or 0
	if n <= 0 then return nil end
	local set = {}
	for order = 1, n do
		GuildControlSetRank(order)
		local flags = { GuildControlGetRankFlags() }
		-- the guild master always hears guild chat; if not, nothing was read
		if order == 1 and not flags[FLAG_GCHAT_LISTEN] then return nil end
		if order == 1 or flags[FLAG_OCHAT_LISTEN] then set[order - 1] = true end
	end
	officerRanksCache = set
	return set
end
do
	local f = CreateFrame("Frame")
	-- rank permissions arrive with the roster, so a change in game shows up here
	f:RegisterEvent("GUILD_ROSTER_UPDATE")
	f:RegisterEvent("PLAYER_GUILD_UPDATE")
	f:SetScript("OnEvent", function() officerRanksCache = nil end)
end

-- Is this rank index an officer rank?
function U.isOfficerRank(idx)
	if idx == nil then return false end
	local set = officerRanks()
	if set then return set[idx] == true end
	return idx <= FALLBACK_OFFICER_MAX_RANK
end

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
-- call outside the guild-control frame. From the FULL roster (see roster()):
-- walking only the online members made the highest online rank look like the
-- bottom one, so every rank colour and the "newest members" tile came out wrong
-- whenever few people were on.
local roster
function U.guildRanks()
	local names, maxIdx = {}, -1
	if not (IsInGuild and IsInGuild()) then return names, maxIdx end
	for _, m in pairs(roster()) do
		if m.rank and m.rankName and m.rankName ~= "" then
			names[m.rank] = m.rankName
			if m.rank > maxIdx then maxIdx = m.rank end
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

-- Rank and notes per member, read from the roster in ONE walk and remembered
-- until the roster changes. The officer / alt checks used to walk the whole
-- guild for every question, several times per raid roster event.
local rosterCache
-- The FULL roster, offline members included. An officer playing an alt has their
-- main offline, and an online-only walk could not find the main behind the alt's
-- "<Main> alt" note -- so every officer alt was treated as a plain raider.
function roster()
	if rosterCache then return rosterCache end
	local cache = {}
	local function walk(total)
		for i = 1, total do
			local n, rankName, rankIndex, _, _, _, publicnote, officernote = GetGuildRosterInfo(i)
			if n then
				cache[(n:gsub("%-.*$", ""))] =
					{ rank = rankIndex, rankName = rankName, pub = publicnote, off = officernote }
			end
		end
	end
	if Okanvil.WithFullRoster then
		Okanvil:WithFullRoster(walk)
	else
		walk(GetNumGuildMembers and GetNumGuildMembers() or 0)
	end
	rosterCache = cache
	return rosterCache
end
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("GUILD_ROSTER_UPDATE")
	f:RegisterEvent("PLAYER_GUILD_UPDATE")
	-- Re-read on the next ask -- except for the roster events our own full walk
	-- causes, or every read would throw away the cache it just built.
	f:SetScript("OnEvent", function()
		if not Okanvil.rosterBusy then rosterCache = nil end
	end)
end

-- rankIndex for a guild member by name, or nil when not in the guild / not found.
function U.guildRankOf(name)
	if not name or name == "" or not IsInGuild or not IsInGuild() then return nil end
	local m = roster()[(name:gsub("%-.*$", ""))]
	return m and m.rank
end

-- Is this name an officer (GM included)? Used both to gate the UI and to decide
-- whether an incoming priority list may be trusted.
function U.isOfficer(name)
	local idx = U.guildRankOf(name)
	return U.isOfficerRank(idx)
end

-- The MAIN an alt belongs to, from its guild notes -- "<Main> alt" in the officer
-- note, or the same form in the public note. nil when the notes do not say.
-- (The Home page reads alts the same way; this is the shared copy.)
function U.mainOf(name)
	if not (name and name ~= "" and IsInGuild and IsInGuild()) then return nil end
	local mem = roster()[(name:gsub("%-.*$", ""))]
	if not mem then return nil end
	for _, note in ipairs({ mem.off, mem.pub }) do
		if note and note ~= "" then
			local m = note:match("^(.-)%s+[Aa][Ll][Tt]%f[%A]")
			if m and m ~= "" then return (m:gsub("^%s+", ""):gsub("%s+$", "")) end
		end
	end
	return nil
end

-- One person's toons: their main, then every alt whose notes name that main.
-- Outside a guild (or with no notes), just the name given.
function U.toonsOf(name)
	name = name and (name:gsub("%-.*$", ""))
	if not (name and name ~= "") then return {} end
	local main = U.mainOf(name) or name
	local out = { main }
	if IsInGuild and IsInGuild() then
		local alts = {}
		for n in pairs(roster()) do
			if n ~= main and U.mainOf(n) == main then alts[#alts + 1] = n end
		end
		table.sort(alts)
		for _, n in ipairs(alts) do out[#out + 1] = n end
	end
	if name ~= main then
		local found = false
		for _, n in ipairs(out) do if n == name then found = true end end
		if not found then out[#out + 1] = name end
	end
	return out
end

-- An officer's alt is ranked as an alt, so rank alone would lock the owner of the
-- list out of it on every toon but one. The guild already records who an alt
-- belongs to -- an officer note reading "<Main> alt" -- so the answer is in the
-- roster and nobody has to maintain a second list by hand.
function U.isOfficerAlt(name)
	local main = U.mainOf(name)
	return main ~= nil and U.isOfficer(main)
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

-- The raider rank: the first rank below the officers that is not an alt rank
-- ("alt" in its name), never the bottom rank. Members at or above it count as
-- raiders. nil outside a guild.
function U.raiderRank()
	local names, maxIdx = U.guildRanks()
	if maxIdx < 0 then return nil end
	local top = 0
	for i = 0, maxIdx do if U.isOfficerRank(i) then top = i end end
	local r = top + 1
	while r < maxIdx and names[r] and names[r]:lower():find("alt", 1, true) do r = r + 1 end
	if maxIdx >= 2 and r >= maxIdx then r = maxIdx - 1 end
	return math.min(r, maxIdx)
end

-- The gate the loot-priority UI asks: an officer, or an officer's alt.
function U.canSeePrio(name)
	name = name or UnitName("player") or ""
	return U.isOfficer(name) or U.isOfficerAlt(name)
end

-- The raid difficulty we are in, as the loot tables write it ("25h"), or nil
-- outside a raid. ICC and the Ruby Sanctum switch to heroic inside the instance:
-- there GetInstanceInfo gives the size in `difficulty` (1 = 10, 2 = 25) and the
-- heroic switch apart (dynamicDifficulty 1), as DBM reads it. The raid difficulty
-- set on the portrait counts as well, so heroic shows as soon as it is set.
function U.raidMode()
	if not GetInstanceInfo then return nil end
	local _, itype, diff, _, maxPlayers, dyn, isDyn = GetInstanceInfo()
	if itype ~= "raid" then return nil end
	local size = (maxPlayers == 25 or diff == 2 or diff == 4) and 25 or 10
	local hc = diff == 3 or diff == 4
	if isDyn then
		local set = GetRaidDifficulty and GetRaidDifficulty()
		hc = dyn == 1 or set == 3 or set == 4
	end
	return size .. (hc and "h" or "n")
end
