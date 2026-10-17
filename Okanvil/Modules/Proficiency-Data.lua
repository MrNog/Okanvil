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
--      they wore leather at low level. CanUse() allows only that type: a
--      lighter piece is auto-passed, so the council board lists only the
--      classes the item is for.
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
-- ARMOUR. Each class takes only its own type at raid level: a plate wearer is
-- never asked about a cloth robe, it would only add a Pass to the board. A cloak
-- is never gated -- every class wears one (RCLoot carries the
-- same override, and it is the single most common false filter).
-- ------------------------------------------------------------
local CLOTH, LEATHER, MAIL, PLATE = 1, 2, 3, 4

local ARMOR_RANK = {
	["Cloth"] = CLOTH, ["Leather"] = LEATHER, ["Mail"] = MAIL, ["Plate"] = PLATE,
}

-- class -> the armour type it wears
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
		["Bows"] = true, ["Crossbows"] = true, ["Guns"] = true, ["Thrown"] = true,
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
		["Bows"] = true, ["Crossbows"] = true, ["Guns"] = true, ["Thrown"] = true,
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
		["Bows"] = true, ["Crossbows"] = true, ["Guns"] = true, ["Thrown"] = true,
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
	["Thrown"] = 50999,
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

	-- 3. Armour: the class's own type only.
	local rank = ARMOR_RANK[eng]
	if rank then
		local maxRank = ARMOR_MAX[class]
		if not maxRank then return true end
		if rank == maxRank then return true end
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

-- Looser than CanUse, for what a raider may soft-reserve: any armour
-- the class can put on, lighter types included (a Holy Paladin's BiS can be
-- cloth). Returns ok, and the armour type when it is lighter than the class's
-- own ("Cloth"), so the picker can say so. Heavier armour and weapons the class
-- cannot hold are still refused.
function P.CanEquip(link, class)
	class = class or (select(2, UnitClass("player")))
	if not link or not class then return true end
	local _, _, _, _, _, itemType, itemSub, _, equipSlot = GetItemInfo(link)
	if not itemType or equipSlot == "INVTYPE_CLOAK" then return P.CanUse(link, class) end
	local eng = P.Subtype(itemSub)
	local rank = eng and ARMOR_RANK[eng]
	if rank then
		local maxRank = ARMOR_MAX[class]
		if not maxRank or rank == maxRank then return true end
		if rank < maxRank then return true, eng end
		return false, "armor"
	end
	return P.CanUse(link, class)
end

-- The armour type of this item when it is lighter than what the class wears
-- ("Cloth"), else nil. The council board uses it to label such an answer.
function P.LighterArmor(link, class)
	if not (link and class) then return nil end
	local _, _, _, _, _, itemType, itemSub, _, equipSlot = GetItemInfo(link)
	if not itemType or equipSlot == "INVTYPE_CLOAK" then return nil end
	local eng = P.Subtype(itemSub)
	local rank, maxRank = eng and ARMOR_RANK[eng], ARMOR_MAX[class]
	if rank and maxRank and rank < maxRank then return eng end
	return nil
end

-- What each spec looks for on gear: `want` lists the stats that make an item
-- theirs (any one is enough), `never` the stats that make it someone else's.
-- Keyed by class, then talent tree (1-3). Physical specs take any physical
-- stat -- a Retribution alt can be agility mail, hunter mail always carries
-- Intellect -- and only refuse Spirit and spell power. Enhancement also takes
-- Intellect (spellhancement). Only classes that can wear lighter armour need
-- a row.
local STAT = {
	INT = "ITEM_MOD_INTELLECT_SHORT", SPI = "ITEM_MOD_SPIRIT_SHORT",
	STR = "ITEM_MOD_STRENGTH_SHORT", AGI = "ITEM_MOD_AGILITY_SHORT",
	AP = "ITEM_MOD_ATTACK_POWER_SHORT", SP = "ITEM_MOD_SPELL_POWER_SHORT",
	-- mana per 5: a healer's stat even on a trinket with no main stat at all
	MP5 = "ITEM_MOD_POWER_REGEN0_SHORT", MP5B = "ITEM_MOD_MANA_REGENERATION_SHORT",
	-- tank stats: a dps spec has no use for them even on a strength item
	DEF = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", DODGE = "ITEM_MOD_DODGE_RATING_SHORT",
	PARRY = "ITEM_MOD_PARRY_RATING_SHORT", BLOCK = "ITEM_MOD_BLOCK_RATING_SHORT",
	BLOCKV = "ITEM_MOD_BLOCK_VALUE_SHORT",
}
local TANK_STATS = { "DEF", "DODGE", "PARRY", "BLOCK", "BLOCKV" }
-- the stats that make an item "about" a role; MP5 is not one of them
local MAIN = { "INT", "SPI", "STR", "AGI", "AP", "SP" }
local PHYSICAL = { want = { "STR", "AGI", "AP" }, never = { "SPI", "SP", "MP5", "MP5B" } }
-- melee without a use for Intellect: Intellect plate is a holy paladin's
local MELEE = { want = { "STR", "AGI", "AP" }, never = { "SPI", "SP", "INT", "MP5", "MP5B" } }
local HEALER_NO_SPIRIT = { want = { "INT" }, never = { "SPI", "STR", "AGI" } }
local CASTER = { want = { "INT", "SP" }, never = { "STR", "AGI", "AP" } }
local SPEC_STATS = {
	PALADIN     = { HEALER_NO_SPIRIT, MELEE, MELEE },                      -- Holy, Prot, Ret
	SHAMAN      = { CASTER,                                                -- Elemental
	                { want = { "STR", "AGI", "AP", "INT" }, never = { "SPI" } }, -- Enhancement
	                CASTER },                                              -- Restoration
	HUNTER      = { PHYSICAL, PHYSICAL, PHYSICAL },
	DRUID       = { CASTER, MELEE, CASTER },                               -- Balance, Feral, Resto
	WARRIOR     = { MELEE, MELEE, MELEE },
	DEATHKNIGHT = { MELEE, MELEE, MELEE },
	ROGUE       = { MELEE, MELEE, MELEE },
	PRIEST      = { CASTER, CASTER, CASTER },
	MAGE        = { CASTER, CASTER, CASTER },
	WARLOCK     = { CASTER, CASTER, CASTER },
}

-- The talent tree with the most points, in the active spec.
-- The talent group the spec checks read: the active one, or the other dual
-- spec while P.FitsEitherSpec asks about it.
local readGroup
local function activeGroup() return GetActiveTalentGroup and GetActiveTalentGroup(false) or 1 end
local function specGroup() return readGroup or activeGroup() end

local function myTree()
	local group = specGroup()
	local best, bestPts = nil, -1
	for i = 1, (GetNumTalentTabs and GetNumTalentTabs() or 3) do
		local _, _, pts = GetTalentTabInfo(i, false, false, group)
		if (pts or 0) > bestPts then best, bestPts = i, pts or 0 end
	end
	return best
end

-- equip slot -> inventory slots it goes in
local INV_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
}

-- A lighter-armour item is still worth asking this raider about when it
-- carries their spec's stat, none of the stats their spec never uses, and is
-- a higher item level than what they wear in that slot. A Holy Paladin is
-- asked about cloth Intellect boots that beat their own; never about Spirit
-- gear, and a Retribution Paladin never about caster cloth.
function P.LighterWorthAsking(link)
	local _, class = UnitClass("player")
	if not P.LighterArmor(link, class) then return false end
	local spec = SPEC_STATS[class] and SPEC_STATS[class][myTree() or 0]
	if not (spec and GetItemStats) then return false end
	local stats = GetItemStats(link) or {}
	local wanted = false
	for _, st in ipairs(spec.want) do if stats[STAT[st]] then wanted = true end end
	if not wanted then return false end
	for _, s in ipairs(spec.never or {}) do
		if stats[STAT[s]] then return false end
	end
	local ilvl = select(4, GetItemInfo(link)) or 0
	local slots = INV_SLOTS[select(9, GetItemInfo(link)) or ""]
	if not slots then return false end
	for _, slot in ipairs(slots) do
		local worn = GetInventoryItemLink("player", slot)
		local wornLvl = worn and select(4, GetItemInfo(worn)) or 0
		if ilvl > wornLvl then return true end
	end
	return false
end

-- Do this item's stats suit the spec you are in? A death knight is not asked
-- about a spell-power neck or Intellect plate. An item with no main stat at all
-- (a crit trinket, a tier token) passes, and so does one the client has not
-- cached yet -- that is decided once it is.
-- Tanking right now? A prot paladin or warrior by tree, a DK by Frost
-- Presence (Blood and Frost both tank in it), a druid in bear form.
-- talents only a tank takes: a feral tank out of bear form, a DK tank in any presence
local BEAR_TALENTS = { ["Protector of the Pack"] = true, ["Natural Reaction"] = true }
local DK_TANK_TALENTS = { ["Anticipation"] = true, ["Frigid Dreadplate"] = true,
	["Will of the Necropolis"] = true }
local function hasTalent(tab, wanted)
	local group = specGroup()
	for i = 1, (GetNumTalents and GetNumTalents(tab, false, false) or 0) do
		local name, _, _, _, rank = GetTalentInfo(tab, i, false, false, group)
		if name and wanted[name] and (rank or 0) > 0 then return true end
	end
	return false
end

local function tankingNow(class, tree)
	if class == "PALADIN" then return tree == 2 end
	if class == "WARRIOR" then return tree == 3 end
	if class == "DEATHKNIGHT" then
		-- the other dual spec has no presence up: its talents alone decide
		if specGroup() ~= activeGroup() then
			return hasTalent(1, DK_TANK_TALENTS) or hasTalent(2, DK_TANK_TALENTS)
		end
		-- tank talents or Frost Presence (RaidFinder reads both)
		if Okanvil.RaidFinder_BloodRole then return Okanvil.RaidFinder_BloodRole() == "Tank" end
		local frost = GetSpellInfo(48263)
		return frost ~= nil and UnitBuff("player", frost) ~= nil
	end
	if class == "DRUID" and tree == 2 then
		if hasTalent(2, BEAR_TALENTS) then return true end
		if specGroup() ~= activeGroup() then return false end   -- no form on the other spec
		local form = GetShapeshiftForm and GetShapeshiftForm() or 0
		if form == 0 or not GetShapeshiftFormInfo then return false end
		local _, name = GetShapeshiftFormInfo(form)
		return name ~= nil and (name == GetSpellInfo(5487) or name == GetSpellInfo(9634))
	end
	return false
end

-- What an item's Equip / Use / proc lines are for, read off its tooltip once:
-- "caster" (spells, spell power, mana, healing), "melee" (attack power, melee
-- or ranged attacks), or false. A haste-only trinket whose proc grants spell
-- power is a caster's, whatever its one stat says.
local effectTip, effectOf = nil, {}
local CASTER_WORDS = { "spell power", "harmful spells", "healing spells", "your spells", "spell critical",
	"mana", "your heals", "healing done" }
local MELEE_WORDS = { "attack power", "melee attacks", "ranged attacks", "melee and ranged" }
-- a tank's: it works when you are hit
local TANK_WORDS = { "struck by", "you are hit", "damage taken", "you take damage",
	"armor by", "armor value", "maximum health",
	"dodge", "parry", "block", "defense" }
local function effectKind(link)
	local id = tonumber(link:match("item:(%d+)"))
	if not id then return false end
	if effectOf[id] ~= nil then return effectOf[id] end
	effectTip = effectTip or CreateFrame("GameTooltip", "OkanvilProfEffectTip", nil, "GameTooltipTemplate")
	effectTip:SetOwner(UIParent, "ANCHOR_NONE")
	effectTip:SetHyperlink("item:" .. id)
	if effectTip:NumLines() < 2 then effectTip:Hide(); return false end   -- not cached yet: ask again later
	local kind = false
	for i = 2, effectTip:NumLines() do
		local fs = _G["OkanvilProfEffectTipTextLeft" .. i]
		local t = fs and (fs:GetText() or ""):lower() or ""
		if t:find("^equip:") or t:find("^use:") or t:find("^chance on hit:") then
			for _, w in ipairs(TANK_WORDS) do if t:find(w, 1, true) then kind = "tank" end end
			if kind then break end
			for _, w in ipairs(CASTER_WORDS) do if t:find(w, 1, true) then kind = "caster" end end
			if not kind then
				for _, w in ipairs(MELEE_WORDS) do if t:find(w, 1, true) then kind = "melee" end end
			end
		end
	end
	effectTip:Hide()
	effectOf[id] = kind
	return kind
end

-- ------------------------------------------------------------
-- Is this item meant for the spec you are in? The same answer RatStash gives
-- (Upgrade.lua MeantFor), for every class and spec:
--   1. weapon type and hands the spec fights with (Blood swings a two-hander,
--      Frost dual-wields, a prot tank holds a one-hander and a shield...);
--   2. ClassLoot, when installed: no stars at all for the spec = not its;
--   3. the stats and Equip/Use effects, by the spec's role (Fit-Specs.lua).
-- ------------------------------------------------------------

-- class, talent tree, tanking -> the spec key Fit-Specs.lua and ClassLoot use
local SPEC_KEY = {
	WARRIOR     = { "WarriorArms", "WarriorFury", "WarriorTank" },
	PALADIN     = { "PaladinHoly", "PaladinTank", "PaladinRetribution" },
	HUNTER      = { "HunterBeastMastery", "HunterMarksman", "HunterSurvival" },
	ROGUE       = { "RogueAssassination", "RogueCombat", "RogueSubtlety" },
	PRIEST      = { "PriestDiscipline", "PriestHoly", "PriestShadow" },
	DEATHKNIGHT = { "DeathKnightBloodDps", "DeathKnightFrostDps", "DeathKnightUnholyDps" },
	SHAMAN      = { "ShamanElemental", "ShamanEnhancement", "ShamanRestoration" },
	MAGE        = { "MageArcane", "MageFire", "MageFrost" },
	WARLOCK     = { "WarlockAffliction", "WarlockDemonology", "WarlockDestruction" },
	DRUID       = { "DruidBalance", "DruidFeralDps", "DruidRestoration" },
}
local TANK_KEY = {
	DeathKnightBloodDps = "DeathKnightBloodTank", DeathKnightFrostDps = "DeathKnightFrostTank",
	DruidFeralDps = "DruidFeralTank",
}

local function mySpecKey()
	local _, class = UnitClass("player")
	local tree = myTree() or 0
	local key = SPEC_KEY[class] and SPEC_KEY[class][tree]
	if key and TANK_KEY[key] and tankingNow(class, tree) then key = TANK_KEY[key] end
	return key
end
P.MySpecKey = mySpecKey
-- Tanking right now (tree, talents, presence or bear form)?
function P.Tanking()
	local _, class = UnitClass("player")
	return tankingNow(class, myTree() or 0)
end

local fitByKey
local function fitSpec(key)
	if not fitByKey then
		fitByKey = {}
		for _, s in ipairs(OkanvilFitSpecs or {}) do fitByKey[s.key] = s end
	end
	return key and fitByKey[key]
end

-- melee weapon hands a spec fights with; absent = any it can equip
local ONE = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true }
local TWO = { INVTYPE_2HWEAPON = true }
local HANDS = {
	DeathKnightBloodDps = TWO, DeathKnightBloodTank = TWO, DeathKnightFrostDps = ONE,
	PaladinRetribution = TWO, WarriorArms = TWO,
	WarriorTank = ONE, PaladinTank = ONE,          -- with a shield
	ShamanEnhancement = ONE, DruidFeralDps = TWO, DruidFeralTank = TWO,
	RogueAssassination = ONE, RogueCombat = ONE, RogueSubtlety = ONE,
}
local MELEE_LOC = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_2HWEAPON = true }

-- item subtype -> the type names the weight tables' "bad" lists use
local KIND = {
	Plate = "Plate", Mail = "Mail", Leather = "Leather", Shields = "Shield",
	Daggers = "Dagger", ["Fist Weapons"] = "Fist", Staves = "Staff", Bows = "Bow", Crossbows = "Crossbow",
	Guns = "Gun", Thrown = "Thrown", Wands = "Wand", Polearms = "Polearm",
	["One-Handed Swords"] = "Sword", ["Two-Handed Swords"] = "2HSword", ["One-Handed Axes"] = "Axe",
	["Two-Handed Axes"] = "2HAxe", ["One-Handed Maces"] = "Mace", ["Two-Handed Maces"] = "2HMace",
}
-- Mutilate needs daggers, Combat anything but
local SPEC_WEAPONS = {
	RogueAssassination = { Dagger = true },
	RogueCombat = { Sword = true, Fist = true, Axe = true, Mace = true },
}

-- RatStash's map from its spec keys to ClassLoot's
local CLASSLOOT = {
	WarriorArms = { "WarriorDPS", "WarriorArms" }, WarriorFury = { "WarriorDPS", "WarriorFury" },
	WarriorTank = { "WarriorProt", "WarriorTanking" },
	PaladinHoly = { "PaladinHoly", "PaladinHealing" }, PaladinTank = { "PaladinProt" },
	PaladinRetribution = { "PaladinRet", "PaladinDPS" },
	HunterBeastMastery = { "Hunter" }, HunterMarksman = { "Hunter" }, HunterSurvival = { "Hunter" },
	RogueAssassination = { "Rogue" }, RogueCombat = { "Rogue" }, RogueSubtlety = { "Rogue" },
	PriestDiscipline = { "PriestHeal", "Priest" }, PriestHoly = { "PriestHeal", "Priest" },
	PriestShadow = { "PriestDPS", "Priest" },
	DeathKnightBloodDps = { "DeathknightDPS" }, DeathKnightFrostDps = { "DeathknightDPS" },
	DeathKnightUnholyDps = { "DeathknightDPS" },
	DeathKnightBloodTank = { "DeathknightTank" }, DeathKnightFrostTank = { "DeathknightTank" },
	ShamanElemental = { "ShamanElemental", "ShamanDPS" }, ShamanEnhancement = { "ShamanEnhance", "ShamanDPS" },
	ShamanRestoration = { "ShamanResto", "ShamanHealing" },
	MageArcane = { "Mage" }, MageFire = { "Mage" }, MageFrost = { "Mage" },
	WarlockAffliction = { "Warlock" }, WarlockDemonology = { "Warlock" }, WarlockDestruction = { "Warlock" },
	DruidBalance = { "DruidBalance" }, DruidFeralDps = { "DruidFeral" }, DruidFeralTank = { "DruidFeral" },
	DruidRestoration = { "DruidResto", "DruidHealing" },
}
local function classLoot()
	local ace = LibStub and LibStub("AceAddon-3.0", true)
	local cl = ace and ace:GetAddon("ClassLoot", true)
	return cl and cl.CD
end

-- the stats that say whose an item is
local TANK_STAT = { ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = true, ITEM_MOD_DODGE_RATING_SHORT = true,
	ITEM_MOD_PARRY_RATING_SHORT = true, ITEM_MOD_BLOCK_RATING_SHORT = true, ITEM_MOD_BLOCK_VALUE_SHORT = true }
local PHYS_STAT = { ITEM_MOD_STRENGTH_SHORT = true, ITEM_MOD_AGILITY_SHORT = true, ITEM_MOD_ATTACK_POWER_SHORT = true,
	ITEM_MOD_RANGED_ATTACK_POWER_SHORT = true, ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = true,
	ITEM_MOD_EXPERTISE_RATING_SHORT = true }
local SPELL_STAT = { ITEM_MOD_SPELL_POWER_SHORT = true, ITEM_MOD_INTELLECT_SHORT = true, ITEM_MOD_SPIRIT_SHORT = true,
	ITEM_MOD_MANA_REGENERATION_SHORT = true, ITEM_MOD_POWER_REGEN0_SHORT = true }
-- a bear has no parry and no shield
local NO_BEAR = { ITEM_MOD_PARRY_RATING_SHORT = true, ITEM_MOD_BLOCK_RATING_SHORT = true,
	ITEM_MOD_BLOCK_VALUE_SHORT = true }
local WEAPON_LOC = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_2HWEAPON = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
	INVTYPE_RELIC = true }
local SLOT_JEWEL = { INVTYPE_TRINKET = true, INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_CLOAK = true }

-- Is the item meant for this spec (a Fit-Specs.lua key)? By the spec's role:
--   tank   needs a tank stat or effect on anything but a weapon (dps rings are
--          someone else's); no caster gear
--   bear   the same on rings, neck, trinkets and cloak (dodge, defense, armour);
--          agility leather and weapons are fine; no parry or block
--   str / agi / cat   no tank stat or effect, no caster-only gear; agi specs
--          (rogue, hunter, enhancement) also no strength-only gear
--   caster / healer   nothing with strength, agility or attack power, no tank
--          or melee effect
-- listed: the item is on the spec's BiS list, so only the hard rules apply.
-- noClassLoot skips ClassLoot (/okup audit checks the rules against it).
function P.FitsSpec(link, key, noClassLoot, listed)
	if not (link and GetItemStats and key) then return true end
	local fit = fitSpec(key)
	local _, _, _, _, _, _, subType, _, equip = GetItemInfo(link)
	if not equip then return true end                 -- not cached: decided once it is
	local kind = P.Subtype(subType) and KIND[P.Subtype(subType)]

	-- 1. weapon type and hands
	if fit and kind then
		for _, b in ipairs(fit.bad or {}) do if b == kind then return false end end
	end
	local hands = key and HANDS[key]
	if hands and MELEE_LOC[equip] and not hands[equip] then return false end
	local allowed = key and SPEC_WEAPONS[key]
	if allowed and MELEE_LOC[equip] and kind and not allowed[kind] then return false end

	-- 2. ClassLoot, when it knows the item: no stars for the spec at all = not for it
	--    (its 4 stars are "can wear": tank plate for a dps, so it never says yes alone)
	local id = tonumber(link:match("item:(%d+)"))
	if not noClassLoot and id and P.ClassLootSays(id, key) == false then return false end

	-- 3. the stats and effects, by role
	local stats = GetItemStats(link)
	local role = fit and fit.role
	if not (stats and role) then return true end
	local tankS, phys, spell, str, agiAp, noBear
	for k in pairs(stats) do
		if TANK_STAT[k] then tankS = true end
		if PHYS_STAT[k] then phys = true end
		if SPELL_STAT[k] then spell = true end
		if NO_BEAR[k] then noBear = true end
		if k == "ITEM_MOD_STRENGTH_SHORT" then str = true end
		if k == "ITEM_MOD_AGILITY_SHORT" or k == "ITEM_MOD_ATTACK_POWER_SHORT"
			or k == "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" then agiAp = true end
	end
	local eff = effectKind(link)
	local jewel = equip == "INVTYPE_TRINKET" or equip == "INVTYPE_NECK" or equip == "INVTYPE_FINGER"
	local tanky = tankS or eff == "tank" or (jewel and stats.RESISTANCE0_NAME ~= nil)
	local casterOnly = spell and not phys and not tankS

	if role == "tank" then
		if eff == "caster" or casterOnly then return false end
		if not listed and not WEAPON_LOC[equip] and not tanky then return false end
		return true
	elseif role == "bear" then
		if noBear or eff == "caster" or casterOnly then return false end
		if not listed and SLOT_JEWEL[equip] and not tanky then return false end
		return true
	elseif role == "str" or role == "agi" or role == "cat" then
		if tanky or eff == "caster" or casterOnly then return false end
		if role == "agi" and not listed and str and not agiAp then return false end
		return true
	end
	-- caster, healer
	if tanky or phys or eff == "melee" then return false end
	return true
end

-- the spec you are in right now
function P.StatsFitMe(link, listed)
	return P.FitsSpec(link, mySpecKey(), nil, listed)
end

-- every spec key with its class, for /okup audit
function P.SpecKeys()
	local out = {}
	for _, sp in ipairs(OkanvilFitSpecs or {}) do out[#out + 1] = { key = sp.key, class = sp.class, label = sp.label } end
	return out
end
-- What ClassLoot says about an item for a spec: true / false, nil when it does not know it.
function P.ClassLootSays(id, key)
	local cd = classLoot()
	local entry = cd and cd[id]
	if not entry then return nil end
	for _, k in ipairs(CLASSLOOT[key] or {}) do if entry[k] then return true end end
	return false
end
-- ClassLoot's stars for the spec (0 = none), nil when it does not know the item
function P.ClassLootStars(id, key)
	local cd = classLoot()
	local entry = cd and cd[id]
	if not entry then return nil end
	local best = 0
	for _, k in ipairs(CLASSLOOT[key] or {}) do best = math.max(best, entry[k] or 0) end
	return best
end

-- For the council: does the item suit EITHER of your dual specs? An item for
-- your off spec is still yours to ask for.
function P.FitsEitherSpec(link)
	if P.StatsFitMe(link) then return true end
	local n = GetNumTalentGroups and GetNumTalentGroups(false, false) or 1
	for g = 1, n do
		if g ~= activeGroup() then
			readGroup = g
			local ok, fits = pcall(P.StatsFitMe, link)
			readGroup = nil
			if ok and fits then return true end
		end
	end
	return false
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
