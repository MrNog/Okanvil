-- ============================================================
--  Okanvil-Raids-Data -- shared raid catalogue (the "what can I form?" list).
--
--  WHY THIS FILE EXISTS
--  RaidFinder-Parser has a raid table, but it is a LEXICON: patterns for READING
--  someone else's spam ("icc%s*25%s*hc"). It cannot be walked to build a picker --
--  it has no clean names, no per-size split, no "does this raid have a heroic
--  mode" flag, and its entries exist per (size x difficulty) combination.
--  PuG needs the opposite: an ordered, human-labelled catalogue to OFFER.
--
--  Kept as a plain global (like OkanvilBosses) so any module can read it without
--  a load-order dance.
--
--  FORMAT
--    { key, name, short, sizes = {10,25}, hc = true/false, wq = true/false }
--      key    stable id used in SavedVariables (never shown to the user)
--      name   full instance name (tooltips, headers)
--      short  what goes in the LFM line ("ICC", "ToC") -- this is the token
--             other people's parsers expect to see, so keep it conventional
--      sizes  raid sizes that exist for this instance
--      hc     instance has a heroic/hard mode worth advertising
--      wq     instance is commonly run as a weekly quest
-- ============================================================

OkanvilRaids = {
	{ key = "icc",     name = "Icecrown Citadel",       short = "ICC",    sizes = { 10, 25 }, hc = true,  wq = true  },
	{ key = "rs",      name = "The Ruby Sanctum",       short = "RS",     sizes = { 10, 25 }, hc = true              },
	{ key = "toc",     name = "Trial of the Crusader",  short = "ToC",    sizes = { 10, 25 }, hc = true              },
	{ key = "ulduar",  name = "Ulduar",                 short = "Ulduar", sizes = { 10, 25 }, hc = true,  wq = true  },
	{ key = "naxx",    name = "Naxxramas",              short = "Naxx",   sizes = { 10, 25 },             wq = true  },
	{ key = "os",      name = "The Obsidian Sanctum",   short = "OS",     sizes = { 10, 25 },             wq = true  },
	{ key = "eoe",     name = "The Eye of Eternity",    short = "EoE",    sizes = { 10, 25 },             wq = true  },
	{ key = "voa",     name = "Vault of Archavon",      short = "VoA",    sizes = { 10, 25 }                         },
	{ key = "ony",     name = "Onyxia's Lair",          short = "Ony",    sizes = { 10, 25 },             wq = true  },
}

-- ToC's heroic mode is advertised under its OWN name ("ToGC"), not as "ToC hc" --
-- a leader who spams "ToC 25 hc" gets asked "togc?" every time. Anything not listed
-- here just takes the generic " HC" suffix.
OkanvilRaidHCName = {
	toc = "ToGC",
}

-- The nine classes, in the order the picker shows them. Tokens match UnitClass's
-- second return (and RAID_CLASS_COLORS keys), so a picked class can be compared to
-- a whispering player's class with no translation layer.
OkanvilClasses = {
	{ token = "DEATHKNIGHT", name = "Death Knight", short = "DK"      },
	{ token = "DRUID",       name = "Druid",        short = "Druid"   },
	{ token = "HUNTER",      name = "Hunter",       short = "Hunter"  },
	{ token = "MAGE",        name = "Mage",         short = "Mage"    },
	{ token = "PALADIN",     name = "Paladin",      short = "Pala"    },
	{ token = "PRIEST",      name = "Priest",       short = "Priest"  },
	{ token = "ROGUE",       name = "Rogue",        short = "Rogue"   },
	{ token = "SHAMAN",      name = "Shaman",       short = "Shaman"  },
	{ token = "WARLOCK",     name = "Warlock",      short = "Lock"    },
	{ token = "WARRIOR",     name = "Warrior",      short = "Warr"    },
}

-- SPEC variants, for when the class alone doesn't say what you need. A raid short
-- a healer asks for "hpala", not "pala" -- ask for the class and you get three ret
-- whispers. Only the specs a leader actually calls for by name are here: nobody
-- advertises for a "fire mage", they just say "mage".
--
-- `token` is what the picker stores in db.wantClasses, so these live in the SAME
-- table as the plain classes -- a pick is a pick. `class` ties the variant back to
-- its class token for anything that needs to match a real player later.
-- `short` is exactly the word that goes in the LFM line.
OkanvilClassSpecs = {
	{ token = "PALADIN_HOLY",   class = "PALADIN",     name = "Holy Paladin",  short = "hpala"  },
	{ token = "PALADIN_PROT",   class = "PALADIN",     name = "Prot Paladin",  short = "prot pala" },
	{ token = "PRIEST_DISC",    class = "PRIEST",      name = "Disc Priest",   short = "disc"   },
	{ token = "PRIEST_HOLY",    class = "PRIEST",      name = "Holy Priest",   short = "hpriest" },
	{ token = "SHAMAN_RESTO",   class = "SHAMAN",      name = "Resto Shaman",  short = "rsham"  },
	{ token = "SHAMAN_ELE",     class = "SHAMAN",      name = "Ele Shaman",    short = "ele"    },
	{ token = "SHAMAN_ENH",     class = "SHAMAN",      name = "Enh Shaman",    short = "enh"    },
	{ token = "DRUID_RESTO",    class = "DRUID",       name = "Resto Druid",   short = "rdruid" },
	{ token = "DRUID_BALANCE",  class = "DRUID",       name = "Boomkin",       short = "boomkin" },
	{ token = "DRUID_BEAR",     class = "DRUID",       name = "Bear Druid",    short = "bear"   },
	{ token = "WARRIOR_PROT",   class = "WARRIOR",     name = "Prot Warrior",  short = "prot warr" },
	{ token = "DEATHKNIGHT_TANK", class = "DEATHKNIGHT", name = "Blood DK",    short = "bdk"    },
}
