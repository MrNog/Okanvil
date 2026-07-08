-- ============================================================
--  Okanvil-RaidFinder :: Parser  (Okanvil.RF)
--
--  Turns a chat line ("LFM ICC10 hc 2heal 5.8k gs wsp me") into a
--  listing table, and rejects recruit / WTS / LFG spam.
--
--  TECHNIQUE is based on RaidBrowser (Act/Horsebreed@Warmane) -- see
--  docs/PARSER-REFERENCE.md for how the meta-token pipeline works and
--  which parts are solid vs fragile. This is OUR OWN implementation of
--  that idea, scoped to the raids we care about (Naxx/Ulduar/ToC/ICC/RS)
--  and with our own (simpler, clamped) GS/role/reserved logic -- NOT a
--  verbatim copy. Tune the pattern tables as we test against real spam.
-- ============================================================

Okanvil = Okanvil or {}
local RF = {}
Okanvil.RF = RF

-- rare marker byte so meta-tokens can't collide with real text (¿)
local META = "\194\191"
local T_RAID, T_ROLE, T_GS = META.."raid"..META, META.."role"..META, META.."gs"..META

-- ------------------------------------------------------------
-- STAGE 0 helpers
-- ------------------------------------------------------------
local function strip_links(msg)
	-- kill http(s) urls (streaming sites in spam)
	return (msg:gsub("https?://%S+", ""))
end

-- Loot-priority idiom cleanup (run on the lowercased msg BEFORE raid lexing).
-- "SR > MS > OS", "2xSR>MS>OS", "BiS > MS > OS" are LOOT RULES, not raids -- but
-- the raid lexer would grab the "OS" as Obsidian Sanctum (and mark the line as a
-- 2-raid recruit ad -> false REJECT). We blank out the whole priority chain and
-- any standalone ms/os/bis spec words so they can't be misread as instances.
--   Order matters: kill the chain first, then leftover bare tokens.
local function strip_loot_lingo(msg)
	-- A spec-priority chain joined by > or / (optionally "NxSR" prefixed), e.g.
	-- "2xsr>ms>os", "bis > ms > os", "sr/ms/os". Each token is a 2-letter spec
	-- word (sr/ms/os/bis-ish). Kill the ENTIRE chain -- including the trailing
	-- "os" -- so the raid lexer can't read it as Obsidian Sanctum.
	local spec = "[bmos][rsi]s?"       -- sr, ms, os, bis
	msg = msg:gsub("%d*%s*x?%s*"..spec.."%s*[>/]%s*"..spec.."%s*[>/]%s*"..spec, " ")
	msg = msg:gsub(spec.."%s*[>/]%s*"..spec, " ")   -- 2-token chains (ms>os / sr>ms)
	-- bare loot-spec words that are unambiguous (ms/bis are never instances)
	msg = msg:gsub("%f[%w]bis%f[%W]", " ")
	msg = msg:gsub("%f[%w]ms%f[%W]", " ")
	-- NOTE: a *lone* "os" is left alone -- standalone "OS" almost always means
	-- Obsidian Sanctum; only the >-chain form above is treated as offspec.
	return msg
end

-- collapse a paste of an achievement/item hyperlink down to its [Name] text,
-- and remember the raw had a link (for wantsAchiev). Returns cleaned, hadAchiev.
local function simplify_links(msg)
	local hadAchiev = msg:find("achievement:") ~= nil
	-- |cff...|Hachievement:...|h[Name]|h|r  ->  [Name]
	msg = msg:gsub("|c%x-|H.-|h(%[.-%])|h|r", "%1")
	return msg, hadAchiev
end

-- ------------------------------------------------------------
-- STAGE 1  early reject: recruit ads and trade spam are not raids
--   SOLID (reuse). Keep this list short and obvious; expand as we see
--   false listings slip through.
-- ------------------------------------------------------------
local recruit_words = {
	"recruit", "we raid", "we are raiding", "raid time", "active raider",
	"is a pve", "is a pvp", "is a pvep", "looking for members", "auto%s?recruit",
}
local trade_words = { "wts ", "wtb ", "selling ", "buying " }

local function matches_any(msg, list)
	for _, p in ipairs(list) do
		if msg:find(p) then return true end
	end
	return false
end

-- ------------------------------------------------------------
-- STAGE 2  raid table  (ONLY the raids we care about)
--   SOLID data (reuse the pattern shapes, re-typed & understood).
--   Order: heroic BEFORE normal (a normal pattern would also match a
--   "hc" line). weekly entries flagged so we can label/filter them.
--
--   Each pattern is a plain Lua pattern tested against the lowercased
--   message. `%f[%w]x%f[%W]` = word-boundary around x (avoids matching
--   'icc' inside a bigger word).
-- ------------------------------------------------------------
local raids = {
	-- ICC
	{ id="icc25hc", instance="Icecrown Citadel", size=25, hc=true,
	  pats={ "icc%s*25%s*hc", "icc%s*hc%s*25", "the light of dawn" } },
	{ id="icc10hc", instance="Icecrown Citadel", size=10, hc=true,
	  pats={ "icc%s*10%s*hc", "icc%s*hc%s*10", "bane of the fallen king" } },
	{ id="icc25nm", instance="Icecrown Citadel", size=25,
	  pats={ "icc%s*25", "fall of the lich king %(25" } },
	{ id="icc10nm", instance="Icecrown Citadel", size=10,
	  pats={ "icc%s*10", "%f[%w]icc%f[%W]", "fall of the lich king %(10" } },
	{ id="icc10wq", instance="Icecrown Citadel", size=10, weekly=true,
	  pats={ "icc%s*1?0?%s*weekly", "lord marrowgar" } },

	-- ToC / ToGC
	{ id="toc25hc", instance="Trial of the Crusader", size=25, hc=true,
	  pats={ "togc%s*25", "toc%s*25%s*hc" } },
	{ id="toc10hc", instance="Trial of the Crusader", size=10, hc=true,
	  pats={ "togc%s*10", "toc%s*10%s*hc" } },
	{ id="toc25nm", instance="Trial of the Crusader", size=25,
	  pats={ "toc%s*25" } },
	{ id="toc10nm", instance="Trial of the Crusader", size=10,
	  pats={ "toc%s*10", "%f[%w]toc%f[%W]" } },

	-- Ulduar  (HM/hard-mode + Algalon variants BEFORE normal so they win the
	-- earliest-match tie; Ulduar "hard mode" is per-boss, but pug spam labels the
	-- whole run "Uld25 HM" so we treat it as the heroic tier for filtering.)
	{ id="ulduar25hc", instance="Ulduar", size=25, hc=true,
	  pats={ "uld?u?a?r%s*25%s*hm", "uld?u?a?r%s*25%s*hc",
	         "uld?u?a?r%s*25.-%f[%w]alga%a*", "algalon%s*25" } },
	{ id="ulduar10hc", instance="Ulduar", size=10, hc=true,
	  pats={ "uld?u?a?r%s*10%s*hm", "uld?u?a?r%s*10%s*hc",
	         "uld?u?a?r%s*10.-%f[%w]alga%a*", "algalon%s*10" } },
	{ id="ulduar25", instance="Ulduar", size=25,
	  pats={ "uld?u?a?r%s*25", "ulduar%s*25" } },
	{ id="ulduar10", instance="Ulduar", size=10,
	  pats={ "uld?u?a?r%s*10", "%f[%w]ulduar%f[%W]", "%f[%w]uld%f[%W]" } },
	{ id="ulduar10wq", instance="Ulduar", size=10, weekly=true,
	  pats={ "ulduar%s*1?0?%s*weekly", "flame leviathan", "razorscale", "xt%-002", "ignis" } },

	-- Naxxramas
	{ id="naxx25", instance="Naxxramas", size=25,
	  pats={ "naxx?%s*25", "naxxramas%s*25" } },
	{ id="naxx10", instance="Naxxramas", size=10,
	  pats={ "naxx?%s*10", "%f[%w]naxx?%f[%W]" } },
	{ id="naxx10wq", instance="Naxxramas", size=10, weekly=true,
	  pats={ "naxx?%s*1?0?%s*weekly", "patchwerk", "noth", "razuvious", "anub'rekhan" } },

	-- Ruby Sanctum (optional; keep since it's current-tier gate content)
	{ id="rs25hc", instance="The Ruby Sanctum", size=25, hc=true,
	  pats={ "rs%s*25%s*hc", "ruby%s*sanctum%s*25%s*hc" } },
	{ id="rs10hc", instance="The Ruby Sanctum", size=10, hc=true,
	  pats={ "rs%s*10%s*hc", "ruby%s*sanctum%s*10%s*hc" } },
	{ id="rs25nm", instance="The Ruby Sanctum", size=25,
	  pats={ "rs%s*25", "ruby%s*sanctum%s*25" } },
	{ id="rs10nm", instance="The Ruby Sanctum", size=10,
	  pats={ "rs%s*10", "ruby%s*sanctum" } },

	-- Vault of Archavon (common weekly pug: Archavon/Emalon/Koralon/Toravon)
	-- NOTE: "voa 18" means the 25-man instance done with only 18 toons (headcount,
	-- not raid size). So ANY "voa <11-25>" is the 25-man. Only "voa 10" (or a bare
	-- "voa"/boss name with no number) falls to the 10-man. These 11-25 patterns
	-- match at the SAME position as the bare "voa", and voa25 is listed first, so it
	-- wins the earliest-match tie over the generic voa10 entry.
	{ id="voa25", instance="Vault of Archavon", size=25,
	  pats={ "voa%s*25", "voa%s*2[0-4]", "voa%s*1[1-9]",
	         "vault%s*of%s*archavon%s*25", "vault%s*of%s*archavon%s*2[0-4]",
	         "vault%s*of%s*archavon%s*1[1-9]" } },
	{ id="voa10", instance="Vault of Archavon", size=10,
	  pats={ "voa%s*10", "%f[%w]voa%f[%W]", "vault%s*of%s*archavon",
	         "%f[%w]archavon%f[%W]", "%f[%w]emalon%f[%W]", "%f[%w]koralon%f[%W]", "%f[%w]toravon%f[%W]" } },

	-- Obsidian Sanctum
	{ id="os25", instance="The Obsidian Sanctum", size=25,
	  pats={ "os%s*25", "obsidian%s*sanctum%s*25" } },
	{ id="os10", instance="The Obsidian Sanctum", size=10,
	  pats={ "os%s*10", "%f[%w]os%f[%W]", "obsidian%s*sanctum", "%f[%w]sarth%f[%W]", "sartharion" } },

	-- Eye of Eternity (Malygos)
	{ id="eoe25", instance="The Eye of Eternity", size=25,
	  pats={ "eoe%s*25", "eye%s*of%s*eternity%s*25", "malygos%s*25" } },
	{ id="eoe10", instance="The Eye of Eternity", size=10,
	  pats={ "eoe%s*10", "%f[%w]eoe%f[%W]", "eye%s*of%s*eternity", "%f[%w]malygos%f[%W]" } },

	-- Onyxia's Lair
	{ id="ony25", instance="Onyxia's Lair", size=25,
	  pats={ "ony%s*25", "onyxia%s*25", "ony'?s%s*lair%s*25" } },
	{ id="ony10", instance="Onyxia's Lair", size=10,
	  pats={ "ony%s*10", "%f[%w]ony%f[%W]", "%f[%w]onyxia%f[%W]", "ony'?s%s*lair" } },

	-- ==== TBC raids (25 unless noted) ====
	-- NOTE: short abbreviations (mh/tk/za/mc/mag/bt/gl) false-match inside common
	-- words, and ANY match inflates the multi-raid reject. So we keep FULL names +
	-- size-qualified abbreviations only (e.g. "bt 25", "mc 40"), not bare "bt"/"mc".
	{ id="bt25", instance="Black Temple", size=25,
	  pats={ "black%s*temple", "%f[%w]bt%s*25%f[%W]" } },
	{ id="swp25", instance="Sunwell Plateau", size=25,
	  pats={ "sunwell%s*plateau", "%f[%w]sunwell%f[%W]", "%f[%w]swp%f[%W]" } },
	{ id="mh25", instance="Hyjal Summit", size=25,
	  pats={ "mount%s*hyjal", "hyjal%s*summit", "%f[%w]hyjal%f[%W]" } },
	{ id="ssc25", instance="Serpentshrine Cavern", size=25,
	  pats={ "serpentshrine%s*cavern", "serpent%s*shrine", "%f[%w]ssc%f[%W]" } },
	{ id="tk25", instance="Tempest Keep", size=25,
	  pats={ "tempest%s*keep", "%f[%w]tk%s*25%f[%W]" } },
	{ id="gruul25", instance="Gruul's Lair", size=25,
	  pats={ "gruul'?s?%s*lair", "%f[%w]gruul%f[%W]" } },
	{ id="mag25", instance="Magtheridon's Lair", size=25,
	  pats={ "magtheridon'?s?%s*lair", "%f[%w]magtheridon%f[%W]" } },
	{ id="za10", instance="Zul'Aman", size=10,
	  pats={ "zul'?%s*aman", "%f[%w]za%s*10%f[%W]" } },
	{ id="kara10", instance="Karazhan", size=10,
	  pats={ "karazhan", "%f[%w]kara%f[%W]" } },

	-- ==== Classic raids ====
	{ id="mc40", instance="Molten Core", size=40,
	  pats={ "molten%s*core", "%f[%w]mc%s*40%f[%W]" } },
	{ id="bwl40", instance="Blackwing Lair", size=40,
	  pats={ "blackwing%s*lair", "%f[%w]bwl%f[%W]" } },
	{ id="aq40", instance="Temple of Ahn'Qiraj", size=40,
	  pats={ "temple%s*of%s*ahn'?qiraj", "ahn'?qiraj%s*temple", "%f[%w]aq%s*40%f[%W]", "%f[%w]aq40%f[%W]" } },
	{ id="aq20", instance="Ruins of Ahn'Qiraj", size=20,
	  pats={ "ruins%s*of%s*ahn'?qiraj", "%f[%w]aq%s*20%f[%W]", "%f[%w]aq20%f[%W]" } },
}

-- strip size/difficulty to compare "same instance" for the multi-raid check
local function short_id(id) return (id:gsub("%d.*$", "")) end

-- Lex the raid: replace the matched raid text with T_RAID, return the winning
-- raid entry + how many DISTINCT instances were mentioned (>1 => recruit ad).
local function lex_raid(msg)
	local best, best_pos, seen = nil, math.huge, {}
	local out = msg
	for _, r in ipairs(raids) do
		for _, p in ipairs(r.pats) do
			local s = msg:find(p)
			if s then
				seen[short_id(r.id)] = true
				-- earliest match wins; weekly overrides a same-position normal
				if s < best_pos or (best and r.weekly and not best.weekly and s <= best_pos) then
					best, best_pos = r, s
				end
				break
			end
		end
	end
	if not best then return nil, out, 0 end
	-- consume the winning raid's first matching pattern
	for _, p in ipairs(best.pats) do
		local m, n = out:gsub(p, T_RAID)
		if n > 0 then out = m; break end
	end
	local distinct = 0
	for _ in pairs(seen) do distinct = distinct + 1 end
	return best, out, distinct
end

-- ------------------------------------------------------------
-- STAGE 3  roles
--   The original was a regex soup; this is a clean, minimal nickname
--   table. We add specs as testing turns up spam that misses.
--   Returns the roles found + message with role words -> T_ROLE.
-- ------------------------------------------------------------
local role_words = {
	tank   = { "%f[%w]tanks?%f[%W]", "%f[%w][mo]t%f[%W]", "%f[%w]bear%f[%W]", "prot%f[%W]", "protection" },
	healer = { "%f[%w]heals?%f[%W]", "%f[%w]healers?%f[%W]",
	           "%f[%w]hpal%a*", "%f[%w]hpaly?%a*", "holy%s?pala",   -- hpala/hpaladin/hpally
	           "%f[%w]rdru?id%f[%W]", "%f[%w]rsham%f[%W]", "%f[%w]tree%f[%W]",
	           "%f[%w]disc%f[%W]", "%f[%w]resto%f[%W]" },
	dps    = { "%f[%w]dps%f[%W]", "%f[%w]rdps%f[%W]", "%f[%w]mdps%f[%W]",
	           "%f[%w]boom%a*", "%f[%w]moonkin%f[%W]",              -- boomy/boomie/boomkin/moonkin
	           "%f[%w]spriest%f[%W]", "shadow%s?priest", "%f[%w]spri%a*",
	           "%f[%w]ele%f[%W]", "%f[%w]elem%a*",                 -- ele / elemental
	           "%f[%w]mage%a*", "%f[%w]lock%a*", "%f[%w]hunt%a*",
	           "%f[%w]rogue%a*", "%f[%w]fury%a*",
	           "%f[%w]ret%f[%W]", "%f[%w]retri%a*", "%f[%w]retro?%a*" },  -- ret / retri / retro(typo)
}

local function lex_roles(msg)
	local found = {}
	for role, pats in pairs(role_words) do
		for _, p in ipairs(pats) do
			local m, n = msg:gsub(p, T_ROLE)
			if n > 0 then msg = m; found[role] = true end
		end
	end
	-- normalize to an ordered list
	local list = {}
	if found.tank then list[#list+1] = "tank" end
	if found.dps then list[#list+1] = "dps" end
	if found.healer then list[#list+1] = "healer" end
	return list, msg
end

-- ------------------------------------------------------------
-- STAGE 3b  SPECIFIC classes/specs needed  (for the Roles tooltip)
--   Roles say "we need a healer"; leaders often name the EXACT spec they
--   want ("need Hpala + Boomie", "LF Spriest"). We scan the raw text for
--   spec nicknames and return a readable, de-duped list grouped by role,
--   e.g. { {role="healer", label="Holy Paladin"}, {role="dps", label="Boomkin"} }.
--   The MODULE renders this as a tooltip on the Roles column. Non-mutating;
--   a miss just means the tooltip shows the generic role only.
--   Patterns are matched against the lowercased raw message.
-- ------------------------------------------------------------
--   `class` is the WoW class token (PALADIN/DRUID/...) so the MODULE can color
--   each spec label in its class color in the tooltip.
local class_specs = {
	-- healer specs
	{ role="healer", class="PALADIN", label="Holy Paladin",  pats={ "%f[%w]hpal%a*", "holy%s?pala%a*" } },
	{ role="healer", class="DRUID",   label="Resto Druid",   pats={ "%f[%w]rdru?id%a*", "%f[%w]resto%s?dru%a*", "%f[%w]tree%f[%W]" } },
	{ role="healer", class="SHAMAN",  label="Resto Shaman",  pats={ "%f[%w]rsham%a*", "%f[%w]resto%s?sham%a*" } },
	{ role="healer", class="PRIEST",  label="Disc Priest",   pats={ "%f[%w]disc%f[%W]", "%f[%w]dpriest%a*" } },
	{ role="healer", class="PRIEST",  label="Holy Priest",   pats={ "%f[%w]hpriest%a*", "holy%s?priest" } },
	-- dps specs
	{ role="dps", class="PRIEST", label="Shadow Priest", pats={ "%f[%w]spriest%a*", "shadow%s?priest", "%f[%w]spri%a*" } },
	{ role="dps", class="DRUID",  label="Boomkin",       pats={ "%f[%w]boom%a*", "%f[%w]moonkin%f[%W]", "%f[%w]owl%f[%W]", "balance%s?dru%a*" } },
	{ role="dps", class="SHAMAN", label="Ele Shaman",    pats={ "%f[%w]ele%f[%W]", "%f[%w]elem%a*", "elemental%s?sham%a*", "%f[%w]esham%a*" } },
	{ role="dps", class="MAGE",   label="Mage",          pats={ "%f[%w]mage%a*" } },
	{ role="dps", class="WARLOCK",label="Warlock",       pats={ "%f[%w]lock%a*", "%f[%w]warlock%a*" } },
	{ role="dps", class="HUNTER", label="Hunter",        pats={ "%f[%w]hunters?%f[%W]", "%f[%w]hunt%f[%W]" } },
	{ role="dps", class="ROGUE",  label="Rogue",         pats={ "%f[%w]rogue%a*" } },
	{ role="dps", class="PALADIN",label="Ret Paladin",   pats={ "%f[%w]ret%f[%W]", "%f[%w]retri%a*" } },
	{ role="dps", class="WARRIOR",label="Fury Warrior",  pats={ "%f[%w]fury%a*" } },
	{ role="dps", class="DRUID",  label="Feral Cat",     pats={ "%f[%w]kitty%f[%W]", "%f[%w]feral%s?cat%a*" } },
	-- tank specs
	{ role="tank", class="PALADIN",    label="Prot Paladin", pats={ "prot%s?pala%a*", "%f[%w]ptal%a*" } },
	{ role="tank", class="WARRIOR",    label="Prot Warrior", pats={ "prot%s?war%a*" } },
	{ role="tank", class="DRUID",      label="Bear Tank",    pats={ "%f[%w]bear%a*", "feral%s?tank" } },
	{ role="tank", class="DEATHKNIGHT",label="Blood DK",     pats={ "blood%s?dk", "%f[%w]bdk%f[%W]" } },
}

local function lex_classes(raw)
	local out, seen = {}, {}
	for _, cs in ipairs(class_specs) do
		if not seen[cs.label] then
			for _, p in ipairs(cs.pats) do
				if raw:find(p) then
					seen[cs.label] = true
					out[#out + 1] = { role = cs.role, label = cs.label, class = cs.class }
					break
				end
			end
		end
	end
	return out
end

-- ------------------------------------------------------------
-- STAGE 4  gearscore
--   Our own version (the original's magnitude-guessing was hacky).
--   Rules: find "N.Nk" / "NNNN" / "N.N" forms, normalize to a
--   number, CLAMP to a sane WotLK GS window (1500..7000) or reject.
--   Returns display string ("5.8") or nil, and message with T_GS.
-- ------------------------------------------------------------
local function lex_gs(msg)
	-- try "5.8k" / "5,8k" / "5.8kgs"
	local d = msg:match("([1-7][.,]%d)%s*k?g?s?")
	local num
	if d then
		num = tonumber((d:gsub(",", "."))) * 1000
	else
		-- try "5800" / "5800gs"
		local n = msg:match("([1-7]%d%d%d)%s*g?s?")
		if n then num = tonumber(n) end
	end
	if not num then
		-- try "5k" / "6k+"
		local k = msg:match("([1-7])%s*k%+?")
		if k then num = tonumber(k) * 1000 end
	end
	if not num or num < 1500 or num > 7000 then return nil, msg end

	-- consume the matched gs text (best-effort) and return display like "5.8"
	msg = msg:gsub("[1-7][.,]%d%s*k?g?s?", T_GS, 1)
	msg = msg:gsub("[1-7]%d%d%d%s*g?s?", T_GS, 1)
	msg = msg:gsub("[1-7]%s*k%+?", T_GS, 1)
	return string.format("%.1f", num / 1000), msg
end

-- ------------------------------------------------------------
-- STAGE 5  reserved items  (NEW -- not in RaidBrowser)
--   nil = unknown, false = explicitly none, string = readable label.
--
--   Raid LFM spam reserves loot by CATEGORY, usually as single letters
--   joined with + inside "( ... res)":  e.g. "(P+O RES)", "B+O+P+Frags res".
--     B = BoE   O = Orb   P = Patterns   F/Frags = Fragments
--     + explicit words: EV, STS, SR/softres, achiev, mount, and item links.
--   We DETECT the categories and build a clean label ("BoE, Orb, Patterns")
--   instead of slicing a raw substring (which produced garbage like
--   "+o res) whisper gs spec").
-- ------------------------------------------------------------
local none_tokens = { "no%s?res", "no%s?ress", "nothing%s?res", "none%s?res",
	"nr%f[%W]", "all%s?free", "/roll" }

-- word-level reserve categories (checked anywhere in the message, lowercased)
local word_cats = {
	{ "boe",              "BoE" },
	{ "orbs?",            "Orb" },
	{ "patterns?",        "Patterns" },
	{ "frags?",           "Fragments" },
	{ "fragments?",       "Fragments" },
	{ "shards?",          "Shards" },
	{ "%f[%w]keys?%f[%W]","Key" },      -- e.g. EoE "Key to the Focusing Iris"
	{ "%f[%w]quests?%f[%W]", "Quest" }, -- "QUEST RESS" -> Onyxia's Head, etc.
	{ "%f[%w]heads?%f[%W]",  "Quest" }, -- "head res" -> Head of Onyxia (Quest turn-in;
	                                    -- cat_valid_for_raid limits Quest to Onyxia)
	{ "%f[%w]ev%f[%W]",   "EV" },
	{ "%f[%w]sts%f[%W]",  "STS" },
	{ "%f[%w]sr%f[%W]",   "SoftRes" },
	{ "soft%s?res",       "SoftRes" },
	-- NOTE: "achiev" is NOT a loot reserve. A pasted achievement link (e.g.
	-- "[Call of the Grand Crusade]") is the achievement the leader ASKS FOR as
	-- proof, tracked separately as wantsAchiev -- not something they reserve. It
	-- was polluting the reserved tooltip with a bogus "Achievement" pill.
	--
	-- "mount" CAN be reserved (VoA drops mounts), so we keep it -- BUT NOT when it's
	-- part of "mount ress"/"mount res"/"mount rez" (a COMBAT-REZ type: battle rez /
	-- DK raise ally / pala hand). is_mount_reserve() below rejects that phrasing so
	-- "(mount+hand ress)" no longer shows a bogus "Reserved loot: Mount".
	{ "mounts?",          "Mount" },
}
-- Guard: does "mount" here mean a RESERVED MOUNT (loot), or a combat-rez type?
-- "mount" is a combat-rez when it sits in a rez-listing group, e.g.
--   "(mount+Ppal hand ress)"  "(mount res + brez)"  "mount ress".
-- We reject if the SAME parenthesised group (or, if none, the whole message) that
-- contains "mount" also mentions a rez word (ress/res/rez/brez/battle rez/hand).
-- Otherwise "mount" is a reserved drop (VoA mounts) and counts.
local function is_mount_reserve(lower)
	if not lower:find("mount") then return false end
	-- gather the parenthesised group(s) that contain "mount"; if none, use whole msg
	local groups = {}
	for g in lower:gmatch("%b()") do groups[#groups + 1] = g end
	local ctx
	for _, g in ipairs(groups) do
		if g:find("mount") then ctx = g; break end
	end
	ctx = ctx or lower
	-- rez words in the same context -> it's a rez type, not reserved loot
	if ctx:find("%f[%w]ress?%f[%W]") or ctx:find("%f[%w]re?z%f[%W]")
		or ctx:find("brez") or ctx:find("battle%s*re") or ctx:find("hand%s*res")
		or ctx:find("combat%s*re") then
		return false
	end
	return true
end
-- single-letter categories, ONLY read inside a "(...res)" group like (P+O RES)
local letter_cats = { b = "BoE", o = "Orb", p = "Patterns", f = "Fragments" }

-- is there any reserve signal at all?
local function has_reserve_signal(lower)
	return lower:find("reserved") or lower:find("%f[%w]ress?%f[%W]")
		or lower:find("%f[%w]sr%f[%W]") or lower:find("soft%s?res")
		or lower:find("%f[%w]hr%f[%W]")            -- "HR" = hard reserve
end

-- Named-item shortcuts. Leaders reserve trophy items by nickname or a typo'd
-- name; we canonicalize to the REAL item name so the module's ID Finder can
-- resolve a live [item link]. Keys are matched case-insensitively against the
-- bracketed / whispered item text; value is the exact WotLK item name.
--   Small curated set (per user) -- the items people actually hard-reserve.
--   Extend freely; a miss just leaves the typed text as-is (still shown).
local item_aliases = {
	-- ToC / ToGC trinkets (Death's Choice = Horde, Death's Verdict = Alliance;
	-- both drop as the same reserve slot, leaders use either name/typo)
	["death's choice"]      = "Death's Choice",
	["deaths choice"]       = "Death's Choice",
	["death's verdict"]     = "Death's Verdict",
	["deaths verdict"]      = "Death's Verdict",
	["death verdict"]       = "Death's Verdict",
	["death verdicts"]      = "Death's Verdict",
	["death choice"]        = "Death's Choice",
	-- ICC weapons/trinkets commonly hard-reserved
	["dbw"]                 = "Deathbringer's Will",
	["deathbringer's will"] = "Deathbringer's Will",
	["deathbringers will"]  = "Deathbringer's Will",
	["reign of the dead"]   = "Reign of the Dead",
	["reign of the unliving"]= "Reign of the Unliving",
	-- RS / ToC / classic named drops
	["gts"]                 = "Glowing Twilight Scale",
	["glowing twilight scale"] = "Glowing Twilight Scale",
}

-- Resolve a raw item phrase (already lowercased, no brackets) to its canonical
-- name, or nil if we don't recognize it.
local function alias_item(raw)
	if not raw then return nil end
	raw = raw:gsub("^%s+", ""):gsub("%s+$", ""):lower()
	return item_aliases[raw]
end

-- collapse WoW hyperlinks to just their [Name] so item reserves read cleanly.
local function clean_links(s)
	s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
	s = s:gsub("|r", "")
	s = s:gsub("|H.-|h(%[.-%])|h", "%1")
	s = s:gsub("|T.-|t", "")
	return s
end

-- Returns:
--   false                     -> explicitly no reserves
--   nil                       -> no reserve signal at all (unknown)
--   { cats = { "BoE", "Orb", ... }, link = "[Item]" or nil }
--     `cats` are generic category keys; the MODULE resolves tier-specific
--     items (Ulduar Orb = Runed Orb, ICC Frags = Shadowfrost Shard, ...)
--     because it knows the raid. `link` is an explicit item the leader pasted.
function RF.lex_reserved(message)
	local lower = message:lower()
	for _, t in ipairs(none_tokens) do
		if lower:find(t) then return false end
	end

	local cats, seen = {}, {}
	local function add(cat)
		if not seen[cat] then seen[cat] = true; cats[#cats + 1] = cat end
	end

	-- 1. explicit words
	for _, c in ipairs(word_cats) do
		if lower:find(c[1]) then
			-- "Mount" needs the rez-vs-loot guard ("mount ress" != reserved mount).
			if c[2] == "Mount" then
				if is_mount_reserve(lower) then add(c[2]) end
			else
				add(c[2])
			end
		end
	end

	-- 2. category clusters. Leaders write them many ways, joined by + . / - or
	--    nothing:  (P+O RES) / B+O+P / B.O.P / B/O/P / B-O-P-RAG / "bop res".
	--    A cluster is a run of TOKENS separated by [+./-]; each token is either a
	--    single reserve letter (b/o/p/f) OR a short word (frag/rag/orb/pat/boe).
	--    We only accept a cluster if EVERY token is a known reserve token (so we
	--    don't misread real initials / words).
	local token_cat = {
		b = "BoE", o = "Orb", p = "Patterns", f = "Fragments",
		boe = "BoE", orb = "Orb", pat = "Patterns", pats = "Patterns", pattern = "Patterns",
		frag = "Fragments", frags = "Fragments",
		shard = "Fragments", shards = "Fragments",
		key = "Key", keys = "Key",
		-- NOTE: "rag" intentionally NOT mapped -- unknown realm slang (asked user).
	}
	local function scan_cluster(s)
		-- split into tokens; count how many are KNOWN reserve tokens vs unknown.
		-- Trust the cluster if >=2 tokens are known (mostly-reserve); keep the
		-- known ones and show any unknown token verbatim (e.g. "RAG") so the user
		-- still sees it instead of losing the whole cluster.
		-- filler words that appear INSIDE a reserve cluster but aren't categories
		-- (so "(KEY + BOE RESS)" doesn't surface a bogus "RESS" pill)
		local filler = { res = true, ress = true, reserved = true, reserve = true,
		                 hr = true, sr = true, and_ = true, ["and"] = true, ["only"] = true }
		local known, unknown = {}, {}
		for tok in s:gmatch("[%a]+") do
			if token_cat[tok] then known[#known + 1] = token_cat[tok]
			elseif not filler[tok] then unknown[#unknown + 1] = tok:upper() end
		end
		-- reject if there's more junk than reserve tokens (not a real cluster)
		if #known >= 2 and #known >= #unknown then
			for _, cat in ipairs(known) do add(cat) end
			for _, u in ipairs(unknown) do add(u) end   -- verbatim unknown (e.g. RAG)
			return true
		end
		return false
	end
	-- separated groups: 2+ tokens joined by + . / - , e.g. b-o-p-rag / p+o / b.o.p
	for grp in lower:gmatch("%f[%a]([%a]+[%+%.%/%-][%a%+%.%/%-]*[%a])%f[%A]") do
		scan_cluster(grp)
	end
	-- bare run like "bop res" -- ONLY when it directly touches a reserve marker.
	-- DANGER: short runs of b/o/p/f are also real English words -- "of", "op",
	-- "bo" -- so a loose scan turned "call OF the grand crusade" into Orb+Fragments.
	-- Guard: (a) blacklist common words; (b) the run must sit immediately before a
	-- reserve marker ("<run> res/hr/sr"), which is where a genuine cluster lives --
	-- NOT anywhere in the sentence.
	local common_words = { of=true, op=true, bo=true, pf=true, po=true, ob=true,
	                       fo=true, fb=true, bf=true }
	-- run must be IMMEDIATELY followed by a reserve marker word (res/ress/hr/sr).
	for grp, marker in lower:gmatch("%f[%a]([bopf][bopf][bopf]?[bopf]?)%s*(%a+)") do
		if (marker == "res" or marker == "ress" or marker == "hr" or marker == "sr")
		   and grp:find("^[bopf]+$") and not common_words[grp] then
			for L in grp:gmatch("%a") do if letter_cats[L] then add(letter_cats[L]) end end
		end
	end
	-- parenthesized groups are always trusted
	for grp in lower:gmatch("%(([%a%+%.%/%-%s]-)%)") do
		scan_cluster(grp)
	end

	-- 3. explicit item the leader named. Priority:
	--   a) a real pasted hyperlink  |H..|h[Name]|h  (keep verbatim link text)
	--   b) a TYPED bracketed name  [Death's Choice]  -> canonicalize via aliases
	--   c) a bare nickname (GTS / DBW) anywhere, only in a reserve context
	-- `link` is the display text; `itemName` (if set) is the canonical name the
	-- MODULE feeds to the ID Finder to render a real live link.
	local link = message:match("|H.-|h(%[.-%])|h")
	if link then link = clean_links(link) end
	local itemName
	if not link then
		-- typed [Name] that is NOT a hyperlink (no |H before it)
		local typed = message:match("%[([^%[%]|]+)%]")
		if typed then
			local canon = alias_item(typed)
			itemName = canon
			link = "[" .. (canon or typed:gsub("^%s+",""):gsub("%s+$","")) .. "]"
		end
	end
	if not itemName then
		-- bare nickname anywhere (GTS/DBW/etc.), require a reserve signal so a
		-- stray word in chatter can't invent a reserved item.
		if has_reserve_signal(lower) then
			for alias, canon in pairs(item_aliases) do
				-- word-boundary match so "gts" doesn't fire inside "widgets"
				if lower:find("%f[%w]"..alias:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]","%%%0").."%f[%W]") then
					itemName = canon
					link = link or ("[" .. canon .. "]")
					break
				end
			end
		end
	end

	if #cats > 0 or link then
		return { cats = cats, link = link, itemName = itemName }
	end
	-- bare "reserved/SR/HR" with no parsed detail -> still YES, generic
	if has_reserve_signal(lower) then return { cats = {}, link = nil, unspecified = true } end
	return nil
end

-- ------------------------------------------------------------
-- STAGE 6  LFM-skeleton validation
--   SOLID idea (reuse). After reduction the message should look like an
--   LFM sentence made of ¿raid¿ / ¿role¿ / ¿gs¿ tokens + glue words.
--   Reject LFG (someone looking FOR a group).
--   lfm_shapes / lfg_shapes grow as we test.
-- ------------------------------------------------------------
-- LFM sentence shapes. Broadened to match RaidBrowser's coverage (its list is
-- ~30 shapes; ours was too strict and dropped valid ToC/VoA listings that show
-- as reserved-loot or "need all" spam without our exact role/gs/whisper token).
-- Each entry is a Lua pattern over the reduced message (raid/role/gs replaced by
-- meta-tokens). Order doesn't matter -- ANY match => it's an LFM.
local lfm_shapes = {
	"lf%d*m",                       -- "lfm" / "lf2m" anywhere
	"need%s+"..T_ROLE,              -- "need <role>"
	"nee?d%s+all",                  -- "need all"
	"lf%d*m%s+all",                 -- "lfm all"
	"%f[%w]all%s+welcome",          -- "all welcome"
	T_RAID..".*whisper",            -- "<raid> ... whisper me"
	T_RAID..".*wsp",
	T_RAID..".*wisp",
	T_RAID..".*%f[%w]w%f[%W]",      -- "<raid> ... /w"  (bare w after the raid)
	T_RAID..".*pst",                -- "<raid> ... pst" (please send tell)
	T_RAID..".*msg%s*me",
	T_RAID..".*"..T_ROLE,           -- "<raid> ... <role>"
	T_RAID..".*"..T_GS,             -- "<raid> ... <gs>"
	T_ROLE..".*"..T_RAID,           -- "<role> ... <raid>"  (roles named first)
	T_GS..".*"..T_RAID,             -- "<gs> ... <raid>"
	T_RAID..".*reserved",           -- "<raid> ... reserved"  (HR loot spam)
	T_RAID..".*%f[%w]hr%f[%W]",     -- "<raid> ... HR"
	T_RAID..".*%f[%w]sr%f[%W]",     -- "<raid> ... SR"
	T_RAID..".*%f[%w]res%f[%W]",    -- "<raid> ... res"
	T_RAID..".*%f[%w]ress%f[%W]",
	T_RAID..".-%f[%w]run%f[%W]",    -- "<raid> ... run"  (e.g. "ToC25 fast run")
	T_RAID..".-%f[%w]going%f[%W]",  -- "<raid> ... going now"
	T_RAID..".-%f[%w]full%f[%W]",   -- "<raid> full clear"
	"new%s+run.*"..T_RAID,          -- "new run <raid>"
	T_RAID..".*need",               -- "<raid> ... need ..."
	"inv%f[%W].*"..T_RAID,
	-- role-BEFORE-raid listings: "LF Hpaladin and Spriest for Uld10 HM ..."
	-- (a leader naming the roles they still need, then the raid). Requires the
	-- role token to sit before the raid token, which an LFG "5.8 dps lf raid"
	-- line does NOT do the same way (its lf is caught by lfg_shapes first).
	"%f[%w]lf%f[%W].*"..T_ROLE..".*"..T_RAID,
	T_ROLE..".-%f[%w]for%f[%W].*"..T_RAID,
}
local lfg_shapes = {
	"%f[%w]lfg%f[%W]",              -- explicit LFG
	T_GS.."%s*"..T_ROLE.."%s*lf",  -- "5.8 dps lf raid"
	"%f[%w]lf%f[%W]%s*"..T_RAID.."%s*group",   -- "lf <raid> group" (self)
	"looking%s+for%s+"..T_RAID.."%s*group",
}

local function is_lfm_shape(msg) return matches_any(msg, lfm_shapes) end
local function is_lfg_shape(msg) return matches_any(msg, lfg_shapes) end

-- ------------------------------------------------------------
--  PUBLIC: RF.parse(message) -> listing table or nil
-- ------------------------------------------------------------
function RF.parse(message)
	if not message or message == "" then return end
	local raw = strip_links(message:lower())

	-- 1. early reject
	if matches_any(raw, recruit_words) or matches_any(raw, trade_words) then return end

	-- 5. reserved scan on the ORIGINAL message (case + item links preserved, so
	-- the tooltip can show real [Item Name] text instead of "item:45518:..").
	-- The token match itself is case-insensitive.
	local reserved = RF.lex_reserved(message)

	local msg, hadAchiev = simplify_links(raw)
	-- neutralize loot-priority lingo (SR>MS>OS etc.) so "OS" isn't misread as a
	-- second raid (Obsidian Sanctum) and the line falsely rejected as multi-raid.
	msg = strip_loot_lingo(msg)

	-- 2. raid
	local raid, m1, distinct = lex_raid(msg)
	if not raid then return end
	if distinct > 1 then return end          -- multiple raids => recruit ad
	msg = m1

	-- 3. roles (default: all).  Detect SPECIFIC specs from the raw text BEFORE
	-- lex_roles rewrites the role words (so "hpala"/"spriest" are still readable).
	local classNeeds = lex_classes(raw)
	local roles
	roles, msg = lex_roles(msg)
	if #roles == 0 then roles = { "tank", "dps", "healer" } end

	-- 4. gs
	local gs
	gs, msg = lex_gs(msg)

	-- 6. validate skeleton
	if is_lfg_shape(msg) then return end
	if not is_lfm_shape(msg) then return end

	return {
		raid     = raid.id,
		instance = raid.instance,
		size     = raid.size,
		hc       = raid.hc and true or false,
		weekly   = raid.weekly and true or false,
		roles    = roles,
		classNeeds = classNeeds,      -- [] or { {role,label}, ... } specific specs asked for
		gs       = gs,               -- "5.8" or nil (unknown)
		reserved = reserved,          -- nil (unknown) / false (none) / {cats,link}
		wantsAchiev = hadAchiev,
	}
end

-- ------------------------------------------------------------
--  TEST HARNESS -- run in-game:  /script Okanvil.RF.test()
--  Prints each sample and what parsed (or REJECTED). Use while tuning.
-- ------------------------------------------------------------
local samples = {
	-- should PARSE
	"LFM ICC 10 hc need 2 heal 1 tank 5.8k gs whisper me",
	"lf3m icc25 5.5k+ gs, tank + heals, EV reserved",
	"LFM Ulduar 25 dps only 6k gs wsp",
	"lfm naxx 10 all welcome 4k gs",
	"togc 25 selling? no -- lfm 2 dps whisper me",   -- tricky: has "selling?" but is LFM
	"new run toc 10, need healer, no res /roll everything",
	"LFM OS 25 2D BOE HR, need all, min gs 3.7k",
	"lfm eoe10 need 2 dps + heal 4k gs whisper me",
	"VoA 25 quick run, need tank, wsp",
	"LFM TOC10N into HC need all 4.6+ (P+O RES) whisper gs spec",
	"LFM Ulduar25 full run + Alga 4.5k min. 3xSR>MS>OS. B+O+P+Frags res HR whisper",
	"LFM TOC 25 NM RUN Need ONLY BIG DPS 4,4+ B.O.P HR Wisp Class/GS Going Now 12/25",
	"lfm icc 25 bop res, need heals wsp",
	"ULD 25 >> 14:30 ST << be online rdy - 4.2k+ GS B-O-P-RAG HR whisper",
	"LFM EOE 25 need dps, mount reserved, 5k gs wsp",
	"lfm ony 25 mount + boe res, need all wsp me",
	"LFM Black Temple need 3 dps 5k gs whisper",
	"lfm mc 40 old raid transmog run, need all wsp",
	-- new real-spam shapes (KEY reserve, Uld HM+Alga, typed [item], nicknames)
	"NAXX 10 FAST RUN NEED MT heals and Boomie (KEY + BOE RESS) 3,8+ /w me speck gs and achi if u have it",
	"LF Hpaladin and Spriest for Uld10 HM + Algalon. BiS > MS > OS, Nothing reserved",
	"LFM Toc25nm need Dps + Heal. 4.5k min. [Death's Choice] HR. 2xSR>MS>OS. Discord req. BoE's, Orbs & Patterns res. /w Kettamine",
	"@everyone LFM Toc25nm need 4 Dps 4.4k min. [Death's Choice] hard res. (highest roll wins 10k gold). 2xSR>MS>OS. Discord req. BoE's, Orbs & Patterns res.",
	"LFM EOE 25 need dps, GTS reserved, 5k gs wsp",
	"lfm togc 25 death verdicts HR, need 2 dps wsp gs",
	-- must NOT invent Fragments (from "of") or Achievement (from the pasted link):
	"LFM TOC 25 NM 4.4 + /w 1Tank(DK) 2Heal(Hpal/disco) DPS(War/rog/sp/bomy/Demo)(B+O+P Res)[Call of the Grand Crusade (25 player)]",
	-- "retri"/"elemental" must map to DPS specs, NOT default to tank/dps/heal:
	"LFM toc25 need retri and elemental dps 4.5k wsp",
	"lfm onyxia 25 need all gs + spec /w head res",   -- "head res" -> Quest (Onyxia head)
	-- terse ToC/VoA forms RaidBrowser catches but we used to drop (broadened shapes)
	"ToC 25 HR [Death's Choice] pst",
	"toc25 reserved boe pst me",
	"ToGC 25 fast run going now",
	"VoA 25 need all pst",
	"toc 10 nm full clear, hr trinkets",
	"ToC25 3 dps 2 heal SR>MS>OS msg me",
	"LFM ONYXIA 25 NEED 1 RSHAM AND 7 DPS 4,2++ /w GS+SPEC ONLY QUEST RESS",
	-- should REJECT
	"<Rats> is a pve guild recruiting all classes, we raid icc 25 and toc",
	"WTS [Shadowmourne] cheap",
	"5.8k dps rogue looking for icc 25 group",
}

local function ress_str(rv)
	if rv == nil then return "unknown" end
	if rv == false then return "NO" end
	local bits = {}
	for _, c in ipairs(rv.cats or {}) do bits[#bits + 1] = c end
	if rv.itemName then bits[#bits + 1] = "="..rv.itemName
	elseif rv.link then bits[#bits + 1] = rv.link end
	if #bits == 0 then return "YES(unspec)" end
	return "YES[" .. table.concat(bits, "+") .. "]"
end

function RF.test()
	for _, s in ipairs(samples) do
		local r = RF.parse(s)
		if r then
			local needs = {}
			for _, n in ipairs(r.classNeeds or {}) do needs[#needs + 1] = n.label end
			local needStr = #needs > 0 and (" needs=" .. table.concat(needs, ",")) or ""
			DEFAULT_CHAT_FRAME:AddMessage(("|cff55ff55PARSE|r %s -> %s %s gs=%s ress=%s roles=%s%s"):format(
				s, r.raid, r.hc and "HC" or "", tostring(r.gs),
				ress_str(r.reserved), table.concat(r.roles, "/"), needStr))
		else
			DEFAULT_CHAT_FRAME:AddMessage(("|cffff5555REJECT|r %s"):format(s))
		end
	end
end
