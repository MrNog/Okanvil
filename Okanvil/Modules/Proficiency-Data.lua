-- ============================================================
-- Okanvil -- Proficiency data (what a class can physically equip).
--
-- This answers ONE question, asked by the loot council: when an item drops,
-- whose client should be shown a popup about it? A rogue is never asked about
-- a plate helm; a priest is never asked about an axe.
--
-- It is NOT the priority list. The prio ladder (LootPrio.lua) is the guild's
-- DECISION about who should get an item. This file is a GAME RULE about who can
-- wear it at all. They never mix: an item passes proficiency and is then ranked
-- by prio, or it never reaches the question.
--
-- Ported from RCLootCouncil (Utils/tokenData.lua and its autopass table), which
-- has run on this client for years. Two changes made deliberately on the way in:
--
--   1. RCLoot stores a DENY list ("which classes auto-pass this subtype").
--      That encoding reads backwards -- ["Leather"] = {PRIEST, MAGE, WARLOCK}
--      means leather is FOR rogues and druids -- and it is easy to misread when
--      adding a class later. Here it is an ALLOW list, per class. The inversion
--      was done by hand against the WotLK rules, not mechanically: the deny list
--      omits entries on purpose (every class CAN wear cloth, so only the four
--      pure-armour classes deny it), and a blind flip would have lost that.
--
--   2. Armour is stored as the HIGHEST type a class wears. On 3.3.5a every
--      class is past level 40, so a hunter is mail-only in practice even though
--      they wore leather at low level. isArmorUsable() still allows lighter
--      types, because an off-set piece in a lower armour class is a real choice
--      a raider may want (and guessing at intent is not this file's job).
--
-- 3.3.5a: GetItemInfo returns LOCALISED type/subtype strings, so the English
-- keys below cannot be compared directly on a non-English client. P.Subtype()
-- resolves the local string once per subtype via a known item id, exactly the
-- way RCLoot does it. On an English client the lookup is a no-op.
-- ============================================================

local Okanvil = Okanvil
local P = {}
Okanvil.Prof = P

-- ------------------------------------------------------------
-- ARMOUR. The heaviest type each class wears at raid level, plus everything
-- lighter. A cloak is never gated -- every class wears one (RCLoot carries the
-- same override, and it is the single most common false filter).
-- ------------------------------------------------------------
local CLOTH, LEATHER, MAIL, PLATE = 1, 2, 3, 4

local ARMOR_RANK = {
	["Cloth"] = CLOTH, ["Leather"] = LEATHER, ["Mail"] = MAIL, ["Plate"] = PLATE,
}

-- class -> heaviest armour worn (everything at or below is equippable)
local ARMOR_MAX = {
	WARRIOR     = PLATE,
	PALADIN     = PLATE,
	DEATHKNIGHT = PLATE,
	HUNTER      = MAIL,
	SHAMAN      = MAIL,
	ROGUE       = LEATHER,
	DRUID       = LEATHER,
	PRIEST      = CLOTH,
	MAGE        = CLOTH,
	WARLOCK     = CLOTH,
}

-- ------------------------------------------------------------
-- WEAPONS. Allow list per class: the subtypes that class can hold.
-- Inverted from RCLootCouncil's autopass table (core.lua) -- read it as "these
-- are the ten classes minus the ones that auto-pass".
--
-- Relics (Totems/Sigils/Idols/Librams) are single-class by design and are
-- listed with their owner, which is why they look lonely here.
-- ------------------------------------------------------------
local WEAPON = {
	WARRIOR = {
		["One-Handed Axes"] = true, ["Two-Handed Axes"] = true,
		["One-Handed Maces"] = true, ["Two-Handed Maces"] = true,
		["One-Handed Swords"] = true, ["Two-Handed Swords"] = true,
		["Daggers"] = true, ["Fist Weapons"] = true, ["Polearms"] = true,
		["Staves"] = true, ["Shields"] = true,
		["Bows"] = true, ["Crossbows"] = true, ["Guns"] = true,
	},
	PALADIN = {
		["One-Handed Axes"] = true, ["Two-Handed Axes"] = true,
		["One-Handed Maces"] = true, ["Two-Handed Maces"] = true,
		["One-Handed Swords"] = true, ["Two-Handed Swords"] = true,
		["Polearms"] = true, ["Shields"] = true, ["Librams"] = true,
	},
	DEATHKNIGHT = {
		["One-Handed Axes"] = true, ["Two-Handed Axes"] = true,
		["One-Handed Maces"] = true, ["Two-Handed Maces"] = true,
		["One-Handed Swords"] = true, ["Two-Handed Swords"] = true,
		["Polearms"] = true, ["Sigils"] = true,
	},
	HUNTER = {
		["One-Handed Axes"] = true, ["Two-Handed Axes"] = true,
		["One-Handed Swords"] = true, ["Two-Handed Swords"] = true,
		["Daggers"] = true, ["Fist Weapons"] = true, ["Polearms"] = true,
		["Staves"] = true,
		["Bows"] = true, ["Crossbows"] = true, ["Guns"] = true,
	},
	SHAMAN = {
		["One-Handed Axes"] = true, ["Two-Handed Axes"] = true,
		["One-Handed Maces"] = true, ["Two-Handed Maces"] = true,
		["Daggers"] = true, ["Fist Weapons"] = true, ["Staves"] = true,
		["Shields"] = true, ["Totems"] = true,
	},
	ROGUE = {
		["One-Handed Axes"] = true, ["One-Handed Maces"] = true,
		["One-Handed Swords"] = true, ["Daggers"] = true,
		["Fist Weapons"] = true,
		["Bows"] = true, ["Crossbows"] = true, ["Guns"] = true,
	},
	DRUID = {
		["One-Handed Maces"] = true, ["Two-Handed Maces"] = true,
		["Daggers"] = true, ["Fist Weapons"] = true, ["Polearms"] = true,
		["Staves"] = true, ["Idols"] = true,
	},
	PRIEST = {
		["One-Handed Maces"] = true, ["Daggers"] = true,
		["Staves"] = true, ["Wands"] = true,
	},
	MAGE = {
		["One-Handed Swords"] = true, ["Daggers"] = true,
		["Staves"] = true, ["Wands"] = true,
	},
	WARLOCK = {
		["One-Handed Swords"] = true, ["Daggers"] = true,
		["Staves"] = true, ["Wands"] = true,
	},
}

-- ------------------------------------------------------------
-- TIER TOKENS. A token is not armour or a weapon -- GetItemInfo calls it a
-- Miscellaneous/Junk item -- so the subtype checks above can never rule on one.
-- The three WotLK groups, keyed by the token's item id.
-- ------------------------------------------------------------
local VANQUISHER = { DEATHKNIGHT = true, DRUID = true, MAGE = true, ROGUE = true }
local CONQUEROR  = { PALADIN = true, PRIEST = true, WARLOCK = true }
local PROTECTOR  = { HUNTER = true, SHAMAN = true, WARRIOR = true }

local TOKEN = {}
do
	-- T7 (Naxx / OS / EoE) -- 10 and 25 man ids interleaved
	local t7 = {
		[40616] = CONQUEROR, [40631] = CONQUEROR, [40617] = PROTECTOR, [40632] = PROTECTOR,
		[40618] = VANQUISHER, [40633] = VANQUISHER,
		[40610] = CONQUEROR, [40625] = CONQUEROR, [40611] = PROTECTOR, [40626] = PROTECTOR,
		[40612] = VANQUISHER, [40627] = VANQUISHER,
		[40622] = CONQUEROR, [40637] = CONQUEROR, [40623] = PROTECTOR, [40638] = PROTECTOR,
		[40624] = VANQUISHER, [40639] = VANQUISHER,
		[40619] = CONQUEROR, [40634] = CONQUEROR, [40620] = PROTECTOR, [40635] = PROTECTOR,
		[40621] = VANQUISHER, [40636] = VANQUISHER,
		[40613] = CONQUEROR, [40628] = CONQUEROR, [40614] = PROTECTOR, [40629] = PROTECTOR,
		[40615] = VANQUISHER, [40630] = VANQUISHER,
	}
	-- T8 (Ulduar) normal + hardmode
	local t8 = {
		[45635] = CONQUEROR, [45636] = PROTECTOR, [45637] = VANQUISHER,
		[45647] = CONQUEROR, [45648] = PROTECTOR, [45649] = VANQUISHER,
		[45644] = CONQUEROR, [45645] = PROTECTOR, [45646] = VANQUISHER,
		[45650] = CONQUEROR, [45651] = PROTECTOR, [45652] = VANQUISHER,
		[45659] = CONQUEROR, [45660] = PROTECTOR, [45661] = VANQUISHER,
		[45632] = CONQUEROR, [45633] = PROTECTOR, [45634] = VANQUISHER,
		[45638] = CONQUEROR, [45639] = PROTECTOR, [45640] = VANQUISHER,
		[45641] = CONQUEROR, [45642] = PROTECTOR, [45643] = VANQUISHER,
		[45653] = CONQUEROR, [45654] = PROTECTOR, [45655] = VANQUISHER,
		[45656] = CONQUEROR, [45657] = PROTECTOR, [45658] = VANQUISHER,
	}
	-- T9 (ToC) and T10 (ICC)
	local t910 = {
		[47557] = CONQUEROR, [47558] = PROTECTOR, [47559] = VANQUISHER,
		[52025] = VANQUISHER, [52028] = VANQUISHER,
		[52026] = PROTECTOR,  [52029] = PROTECTOR,
		[52027] = CONQUEROR,  [52030] = CONQUEROR,
	}
	for _, t in ipairs({ t7, t8, t910 }) do
		for id, grp in pairs(t) do TOKEN[id] = grp end
	end
end

-- ------------------------------------------------------------
-- LOCALISED SUBTYPES. GetItemInfo hands back the client's language, so on a
-- non-English realm "Plate" arrives as "Plattenpanzer" and every key above
-- misses. One known item id per subtype lets us learn the local string.
--
-- Built lazily and cached: at load time the item cache is usually cold, and a
-- GetItemInfo miss here would poison the map with nils. Callers that get a nil
-- back simply do not filter, which is the safe direction -- showing a popup to
-- someone who cannot use an item is a nuisance; hiding it from someone who can
-- is the bug that makes people distrust the feature.
-- ------------------------------------------------------------
local SUBTYPE_PROBE = {
	["Cloth"] = 39252, ["Leather"] = 39275, ["Mail"] = 39274, ["Plate"] = 39262,
	["Shields"] = 40400, ["Bows"] = 40265, ["Crossbows"] = 40346, ["Daggers"] = 39714,
	["Guns"] = 40385, ["Fist Weapons"] = 40239, ["One-Handed Axes"] = 40402,
	["One-Handed Maces"] = 40395, ["One-Handed Swords"] = 40407, ["Polearms"] = 40208,
	["Staves"] = 40300, ["Two-Handed Axes"] = 40384, ["Two-Handed Maces"] = 39758,
	["Two-Handed Swords"] = 40343, ["Wands"] = 40335, ["Totems"] = 51507,
	["Sigils"] = 51417, ["Idols"] = 51429, ["Librams"] = 40707,
}

local localToEnglish = nil   -- localised subtype -> English key

local function buildSubtypeMap()
	local map, missing = {}, 0
	for eng, id in pairs(SUBTYPE_PROBE) do
		local sub = select(7, GetItemInfo(id))
		if sub and sub ~= "" then map[sub] = eng else missing = missing + 1 end
	end
	-- Always accept the English keys too: on an enUS client the probe and the key
	-- are the same string, and if the cache was cold we still want SOMETHING.
	for eng in pairs(SUBTYPE_PROBE) do map[eng] = map[eng] or eng end
	-- Only cache once every probe resolved; a partial map would permanently
	-- mis-filter the subtypes that happened to be uncached on this login.
	if missing == 0 then localToEnglish = map end
	return map
end

-- Translate a (possibly localised) subtype into the English key used above.
function P.Subtype(sub)
	if not sub or sub == "" then return nil end
	local map = localToEnglish or buildSubtypeMap()
	return map[sub]
end

-- ------------------------------------------------------------
-- PUBLIC CHECK
-- ------------------------------------------------------------

-- Is this a tier token, and can `class` use it?  Returns nil when the id is not
-- a token at all (so the caller can fall through to the subtype checks).
function P.TokenUsable(itemID, class)
	local grp = itemID and TOKEN[tonumber(itemID) or 0]
	if not grp then return nil end
	return grp[class] and true or false
end

-- The real entry point. Can `class` equip this item?
--
-- Returns true / false, plus a short reason string for the false case (the
-- council board shows WHO was skipped and why -- a filter mistake has to be
-- visible, not silent).
--
-- Deliberately permissive: anything we cannot classify returns true. See the
-- note on the subtype map above.
function P.CanUse(link, class)
	class = class or (select(2, UnitClass("player")))
	if not link or not class then return true end

	local itemID = tonumber(link) or tonumber(tostring(link):match("item:(%d+)"))

	-- 1. Tokens first: they are Miscellaneous items, so no subtype test can rule.
	local tok = P.TokenUsable(itemID, class)
	if tok ~= nil then return tok, (not tok) and "token" or nil end

	local _, _, _, _, _, itemType, itemSub, _, equipSlot = GetItemInfo(link)
	if not itemType then return true end              -- not cached -> never filter

	-- 2. Cloaks: every class wears one, whatever the armour subtype says.
	if equipSlot == "INVTYPE_CLOAK" then return true end

	local eng = P.Subtype(itemSub)
	if not eng then return true end                   -- unknown subtype -> never filter

	-- 3. Armour: allow the class's own type and anything lighter.
	local rank = ARMOR_RANK[eng]
	if rank then
		local maxRank = ARMOR_MAX[class]
		if not maxRank then return true end
		if rank <= maxRank then return true end
		return false, "armor"
	end

	-- 4. Weapons / relics: a straight allow-list lookup.
	local w = WEAPON[class]
	if w and w[eng] ~= nil then return true end
	-- The subtype is one we know about (it resolved) but is not in the class's
	-- list -> genuinely unusable. Anything outside SUBTYPE_PROBE never gets here.
	if w then return false, "weapon" end

	return true
end

-- Convenience for the raider's own client, which is where the filter runs.
function P.CanIUse(link)
	return P.CanUse(link, (select(2, UnitClass("player"))))
end

-- ------------------------------------------------------------
-- RELEASE. The Modules list promises that switching the council off stops it
-- using memory, so that has to be literally true rather than just hiding a nav
-- row: these tables are a few KB of data that a guild without a council never
-- reads. Dropping the references lets the GC take them.
--
-- P.Rebuild() puts them back, so the switch is not one-way. The token map is the
-- only one worth rebuilding lazily -- the rest are small literals -- but they go
-- together so the module is either wholly present or wholly gone.
-- ------------------------------------------------------------
local function snapshot()
	return { ARMOR_RANK = ARMOR_RANK, ARMOR_MAX = ARMOR_MAX, WEAPON = WEAPON, TOKEN = TOKEN }
end
local FULL = snapshot()

function P.Release()
	ARMOR_RANK, ARMOR_MAX, WEAPON, TOKEN = {}, {}, {}, {}
	localToEnglish = nil
	P.released = true
end

function P.Rebuild()
	ARMOR_RANK, ARMOR_MAX = FULL.ARMOR_RANK, FULL.ARMOR_MAX
	WEAPON, TOKEN = FULL.WEAPON, FULL.TOKEN
	localToEnglish = nil        -- re-resolve subtypes on next use
	P.released = false
end

-- Follow the module switch. Checked on login and whenever the switch is flipped
-- (Core:SetModuleEnabled repaints, and the council module hooks that) -- a
-- released table answers "true" from CanUse, which is the permissive direction
-- and harmless for a guild that switched the feature off.
function P.SyncEnabled()
	local on = not Okanvil.ModuleActive or Okanvil:ModuleActive("__council")
	if on and P.released then P.Rebuild()
	elseif not on and not P.released then P.Release() end
	return on
end
