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
