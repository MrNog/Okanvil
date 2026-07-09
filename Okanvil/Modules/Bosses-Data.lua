-- ============================================================
--  Okanvil-Bosses-Data -- shared boss creatureID table.
--
--  WHY THIS FILE EXISTS
--  Both Loot.lua (to label a drop with the boss that dropped it) and Logs.lua (to
--  log a kill) need to answer "is this NPC a boss?". Logs.lua had its own `local
--  BOSS_IDS`, invisible to Loot.lua -- `local` scopes a name to ONE file. Worse,
--  Loot.lua loads BEFORE Logs.lua, so even a global would not have been set yet.
--  Hence a data file, loaded first, exposing plain globals -- the same pattern
--  IDs-Data.lua uses for OkanvilIDs_Seed.
--
--  Without a list, boss detection falls back to an HP heuristic (isBossLike): in a
--  dungeon, "elite with >80k HP". That guess promotes beefy trash (a Drakkari Rhino)
--  and would miss a low-HP boss. An id is exact and locale-proof.
--
--  SOURCE -- do not hand-edit; regenerate with scratchpad/gen_bosses.py.
--  Merged from two verified lists, no id invented:
--    * WA/BossHP/BossHP.lua -- all WotLK raids AND 5-man dungeons. Battle-tested:
--      it drives an in-combat HP bar, so a wrong id would show no bar.
--    * Logs.lua's BOSS_IDS -- only the 6 encounter ids BossHP lacks (it tracks HP
--      phases, e.g. Mimiron's three, rather than the encounter).
--  Where they disagreed, BossHP won: Logs.lua was mis-keyed across ICC (it called
--  37813 "Deathbringer Saurfang", but that id is the Alliance Gunship; the real
--  Saurfang is 37215, which Logs.lua lacked entirely).
--
--  FORMAT: [creatureID] = "Boss Name"   (matching is by id; the name is the label)
-- ============================================================

OkanvilBosses = {
	-- NAXXRAMAS  (raid)
	[15956] = "Anub'Rekhan",
	[15953] = "Grand Widow Faerlina",
	[15952] = "Maexxna",
	[15954] = "Noth The Plaguebringer",
	[15936] = "Heigan The Unclean",
	[16011] = "Loatheb",
	[16061] = "Instructor Razuvious",
	[16060] = "Gothik The Harvester",
	[16062] = "Baron Rivendare",
	[16063] = "Highlord Mograine",
	[16064] = "Lady Blaumeux",
	[16065] = "Thane Kol'Varas",
	[16028] = "Patchwerk",
	[15931] = "Grobbulus",
	[15932] = "Gluth",
	[15928] = "Thaddius",
	[15989] = "Sapphiron",
	[15990] = "Kel'Thuzad",

	-- OBSIDIAN SANCTUM  (raid)
	[28860] = "Sartharion",
	[30349] = "Tenebron",
	[30351] = "Shadron",
	[30550] = "Vesperon",

	-- EYE OF ETERNITY  (raid)
	[28859] = "Malygos",

	-- VAULT OF ARCHAVON  (raid)
	[31125] = "Archavon",
	[33993] = "Emalon",
	[35013] = "Koralon",
	[38433] = "Toravon",

	-- ULDUAR  (raid)
	[33113] = "Flame Leviathan",
	[33118] = "Ignis",
	[33186] = "Razorscale",
	[33293] = "XT-002",
	[32867] = "Steelbreaker",
	[32930] = "Kologarn",
	[33515] = "Auriaya",
	[32845] = "Hodir",
	[32865] = "Thorim",
	[32906] = "Freya",
	[33432] = "Leviathan Mk II",
	[33651] = "VX-001",
	[33670] = "Aerial Command Unit",
	[33271] = "General Vezax",
	[33288] = "Yogg-Saron",
	[32871] = "Algalon",
	[32927] = "Runemaster Molgeim",
	[32857] = "Stormcaller Brundir",
	[33350] = "Mimiron",

	-- TRIAL OF THE CRUSADER  (raid)
	[34796] = "Gormok",
	[35144] = "Acidmaw",
	[34799] = "Dreadscale",
	[34797] = "Icehowl",
	[34780] = "Lord Jaraxxus",
	[34497] = "Fjola Lightbane",
	[34496] = "Eydis Darkbane",
	[34564] = "Anub'Arak",

	-- ONYXIA'S LAIR  (raid)
	[10184] = "Onyxia",

	-- ICECROWN CITADEL  (raid)
	[36612] = "Lord Marrowgar",
	[36855] = "Lady Deathwhisper",
	[37813] = "Alliance Gunship",
	[37960] = "Horde Gunship",
	[37215] = "Deathbringer Saurfang",
	[36626] = "Festergut",
	[36627] = "Rotface",
	[36678] = "Professor Putricide",
	[37955] = "Prince Keleseth",
	[37972] = "Prince Taldaram",
	[37970] = "Prince Valanar",
	[37973] = "Blood Queen Lan'Athel",
	[36789] = "Valithria Dreamwalker",
	[36853] = "Sindragosa",
	[36597] = "The Lich King",

	-- RUBY SANCTUM  (raid)
	[39863] = "Halion",
	[40142] = "Twilight Halion",
	[39751] = "Baltharus the Warborn",
	[39746] = "General Zarithrian",
	[39747] = "Saviana Ragefire",

	-- UTGARDE KEEP  (5-man)
	[23953] = "Prince Keleseth",
	[24200] = "Skarvald",
	[23954] = "Ingvar",

	-- UTGARDE PINNACLE  (5-man)
	[26668] = "Svala Sorrowgrave",
	[26687] = "Gortok Palehoof",
	[26693] = "Skadi The Ruthless",
	[26861] = "King Ymiron",

	-- THE NEXUS  (5-man)
	[26731] = "Commander Kolurg",
	[26798] = "Commander Stoutbeard",
	[26763] = "Anomalus",
	[26794] = "Ormorok",
	[26723] = "Keristrasza",

	-- THE OCULUS  (5-man)
	[27654] = "Drakos",
	[27447] = "Mage-Lord Urom",
	[27655] = "Ley-Guardian Eregos",
	[27656] = "Varos Cloudstrider",

	-- AZJOL-NERUB  (5-man)
	[28684] = "Krik'Thir",
	[28921] = "Hadronox",
	[29120] = "Anub'Arak",

	-- AHN'KAHET: THE OLD KINGDOM  (5-man)
	[29309] = "Elder Nadox",
	[29308] = "Prince Taldaram",
	[30258] = "Amanitar",
	[29310] = "Jedoga Shadowseeker",
	[29311] = "Herald Volazj",

	-- DRAK'THARON KEEP  (5-man)
	[26630] = "Trollgore",
	[26631] = "Novos The Summoner",
	[27483] = "King Dred",
	[26632] = "The Prophet Tharon'Ja",

	-- GUNDRAK  (5-man)
	[29304] = "Slad'Ran",
	[29305] = "Moorabi",
	[29306] = "Drakkari Colossus",
	[29307] = "Gal'Darah",
	[31723] = "Eck The Ferocious",

	-- HALLS OF STONE  (5-man)
	[27977] = "Krystallus",
	[27975] = "Maiden Of Grief",
	[27978] = "Sjonnir The Ironshaper",

	-- HALLS OF LIGHTNING  (5-man)
	[28586] = "General Bjarngrim",
	[28587] = "Volkhan",
	[28546] = "Ionar",
	[28588] = "Loken",

	-- THE VIOLET HOLD  (5-man)
	[31134] = "Cyanigosa",
	[29315] = "Erekem",
	[29313] = "Ichoron",
	[29312] = "Lavanthor",
	[29316] = "Moragg",
	[29266] = "Xevozz",
	[29314] = "Zuramat",

	-- CULLING OF STRATHOLME  (5-man)
	[26529] = "Meathook",
	[26530] = "Salramm",
	[26532] = "Chrono-Lord Epoch",
	[26533] = "Mal'Ganis",
	[32273] = "Infinite Corruptor",

	-- TRIAL OF THE CHAMPION  (5-man)
	[35617] = "Argent Confessor",
	[35610] = "Eadric The Pure",
	[35451] = "The Black Knight",

	-- FORGE OF SOULS  (5-man)
	[36497] = "Bronjahm",
	[36502] = "Devourer Of Souls",

	-- PIT OF SARON  (5-man)
	[36494] = "Forgemaster Garfrost",
	[36476] = "Krik'Ir The Gatewatcher",
	[36658] = "Scourgelord Tyrannus",

	-- HALLS OF REFLECTION  (5-man)
	[38112] = "Falric",
	[38113] = "Marwyn",
	[37226] = "The Lich King",

}

-- Multi-NPC encounters -> the one name the whole fight is filed under, so their loot
-- lands on a single page instead of three. Keyed by creatureID AND by name: the death
-- path knows the id, the loot path may only have a name.
OkanvilBossGroups = {
	-- Assembly of Iron (Ulduar)
	[32867] = "Iron Council", [32927] = "Iron Council", [32857] = "Iron Council",
	["Steelbreaker"] = "Iron Council",
	["Runemaster Molgeim"] = "Iron Council",
	["Stormcaller Brundir"] = "Iron Council",

	-- Blood Prince Council (ICC).  NOTE the ids: 37955 Keleseth, 37972 Taldaram,
	-- 37970 Valanar.  (Lana'thel is 37973 and is NOT part of the council.)
	[37955] = "Blood Prince Council", [37972] = "Blood Prince Council", [37970] = "Blood Prince Council",
	["Prince Keleseth"] = "Blood Prince Council",
	["Prince Taldaram"] = "Blood Prince Council",
	["Prince Valanar"] = "Blood Prince Council",

	-- Gunships (ICC) -- one encounter, two faction NPCs
	[37813] = "Gunship Battle", [37960] = "Gunship Battle",
	["Alliance Gunship"] = "Gunship Battle",
	["Horde Gunship"] = "Gunship Battle",

	-- Twin Val'kyr (ToC)
	[34496] = "Twin Val'kyr", [34497] = "Twin Val'kyr",
	["Eydis Darkbane"] = "Twin Val'kyr",
	["Fjola Lightbane"] = "Twin Val'kyr",

	-- Northrend Beasts (ToC)
	[34796] = "Northrend Beasts", [35144] = "Northrend Beasts",
	[34799] = "Northrend Beasts", [34797] = "Northrend Beasts",
	["Gormok"] = "Northrend Beasts",
	["Gormok the Impaler"] = "Northrend Beasts",
	["Acidmaw"] = "Northrend Beasts",
	["Dreadscale"] = "Northrend Beasts",
	["Icehowl"] = "Northrend Beasts",

	-- Mimiron (Ulduar) -- three HP phases, one encounter
	[33432] = "Mimiron", [33651] = "Mimiron", [33670] = "Mimiron",
	["Leviathan Mk II"] = "Mimiron",
	["VX-001"] = "Mimiron",
	["Aerial Command Unit"] = "Mimiron",

	-- Halion (Ruby Sanctum) -- physical + twilight realm
	[40142] = "Halion",
	["Twilight Halion"] = "Halion",

	-- Sartharion's drakes (OS) count as the Sartharion encounter
	[30349] = "Sartharion", [30351] = "Sartharion", [30550] = "Sartharion",
	["Tenebron"] = "Sartharion",
	["Shadron"] = "Sartharion",
	["Vesperon"] = "Sartharion",
}
