-- ============================================================
-- Okanvil -- Notes: parsing and timers.
--
-- Reads the community ICC note format (MRT's syntax, byte for byte) and turns
-- each line into something with a countdown. Pure-ish: no UI, no frames beyond
-- one combat-log listener.
--
-- Syntax reference: docs/MRT_NOTE_FORMAT.md
--   {time:00:52}                 52s after the pull
--   {time:00:22,SAA:74792:3}     22s after the 3rd application of 74792
--   {spell:64205}                inline icon
--   {item:36892}                inline icon for an ITEM (healthstone)
--   {skull} {star} ...           raid target icons
--   {room:The Spire}             the room(s) this note runs in; never drawn
-- ============================================================

local P = {}
Okanvil.NotesParse = P

-- Combat-log prefixes, exactly MRT's four.
local CLEU_PREFIX = {
	SPELL_CAST_SUCCESS  = "SCC",
	SPELL_CAST_START    = "SCS",
	SPELL_AURA_APPLIED  = "SAA",
	SPELL_AURA_REMOVED  = "SAR",
}

-- Raid target icons, the subset the ICC notes actually use.
local ICONS = {
	star = 1, circle = 2, diamond = 3, triangle = 4,
	moon = 5, square = 6, cross = 7, skull = 8,
	rt1 = 1, rt2 = 2, rt3 = 3, rt4 = 4, rt5 = 5, rt6 = 6, rt7 = 7, rt8 = 8,
}

-- ------------------------------------------------------------
-- Encounter state
--
-- Counters are per encounter and keyed the way a note line refers to them --
-- "SCC:72905:3" is the third cast-success of 72905. The VALUE is the moment it
-- happened, which is all a line needs to work out its own countdown.
-- ------------------------------------------------------------
local pullAt = nil        -- GetTime() at pull, nil out of combat
local counters = {}       -- ["SCC:72905"] = 3
local reached  = {}       -- ["SCC:72905:3"] = GetTime() when it hit 3
local phase = 1
local phaseAt = nil
local dbmLive = false     -- a DBM-engaged boss fight is running
local fightId, fightName = nil, nil   -- the DBM mod being fought: id ("Rotface") and its local name
-- In combat this much longer than DBM's engage = trash ran into the boss.
local DBM_GRACE = 3
local DBM_STALE = 20 * 60

function P.InCombat() return pullAt ~= nil end
function P.Phase() return phase end

-- Record every anchorable event a pull produces. Off by default.
--
-- Exists because "the line never counted down" has causes that look identical
-- from the outside -- out of combat, the wrong spell id for this core, or the
-- id arriving in a different argument slot -- and no way to tell them apart
-- without seeing what the log actually hands over.
--
-- WRITTEN DOWN, not printed. A boss fight produces more lines than a chat frame
-- keeps, so by the time the pull is over the start of it has scrolled away and
-- cannot be copied out -- which is the half that matters, since the anchors a
-- note waits on are the early ones. This goes to the same SavedVariables file
-- the error log uses, so it survives the wipe and can be read out of the file
-- afterwards.
-- The saved record. Declared in the .toc beside OkanvilBugDB. Enough pulls for a
-- whole raid night with its wipes, so every boss of the night can be measured.
-- What keeps the file small is the per-spell cap below, not the pull count: the
-- first occurrences of each ability are what a note is timed from, and an aura
-- landing on 25 raiders or an add's spam would otherwise fill a pull on its own.
local LOG_PULLS = 30
local LOG_PER_SPELL = 12      -- occurrences kept per prefix:spell in one pull
local LOG_PER_PULL = 1500

-- Created at load, not at the pull. The table only ever appeared in the file
-- once recording had caught a fight, so a run that recorded nothing -- watch
-- left off, or the pull never registering -- was indistinguishable from the
-- addon never having loaded at all. An empty table in the file at least says
-- which of those it was.
--
-- Declared before anything that calls it: a local is only in scope from its own
-- line down, so the switch below referred to a global that did not exist.
--
-- Lives INSIDE OkanvilNotesDB rather than in a table of its own. A new
-- SavedVariable has to be named in the .toc, and the client reads the .toc only
-- when it starts -- never on /reload -- so a table added while the game is
-- running is simply never written, and the log looked broken when it was only
-- undeclared. Hanging it off a variable that is already saved means it records
-- from the next /reload, with no restart.
local function logDB()
	OkanvilNotesDB = OkanvilNotesDB or {}
	OkanvilNotesDB.log = OkanvilNotesDB.log or {}
	OkanvilNotesDB.log.pulls = OkanvilNotesDB.log.pulls or {}
	return OkanvilNotesDB.log
end

-- Kept in the saved file, not just in memory: /reload is how the file gets
-- written, so a switch that forgot itself on reload could never survive long
-- enough to record the pull it was turned on for.
function P.SetDebug(on)
	logDB().watching = on and true or false
	P.debug = on and true or false
end

function P.Debug()
	local d = OkanvilNotesDB and OkanvilNotesDB.log
	if d and d.watching then return true end
	return P.debug and true or false
end

P.debug = false

-- This pull's events, in order: { key =, at =, name = }. Also mirrored into
-- OkanvilNotesDB.log, which is what actually reaches disk.
local seenKeys = {}
function P.SeenAnchors() return seenKeys end

-- ------------------------------------------------------------
-- The spell catalogue: what each boss was actually SEEN casting.
--
-- Written for the one question a note cannot answer on its own -- "does this
-- id exist HERE". The ID Finder says a spell exists, because the client ships
-- every difficulty's variant in its spell table; it cannot say whether this
-- core's boss ever casts it. A note anchored to a spell the boss never uses
-- waits for ever and looks exactly like a broken addon.
--
-- One library per raid AND difficulty, because heroic and 25-man abilities
-- carry their own spell ids:
--
--   log.lib[zone][diff][source] = { spells = { [prefix:id] = row }, killed = time }
--   diff = "10N" | "10H" | "25N" | "25H" | "?" (difficulty not known)
--
-- Recorded ONCE. Pulls count a source's casts until it is seen dying; a wipe at
-- 30% keeps what it saw and the next pull carries on from there. After the kill
-- the counts are frozen, but a spell never seen before is still added: a phase
-- skipped by a fast kill turns up the first time a later pull reaches it.
-- "redo" on the panel throws a source away to record it from scratch.
--
-- Only pulls inside a raid instance are catalogued, so a fight in Dalaran or a
-- dungeon never lands next to the bosses a note is written for.
--
-- Silent by design. Nothing prints, nothing warns, nothing asks -- you read it
-- when you sit down to write a note, not while you are tanking.
-- ------------------------------------------------------------

-- Boss NPCs of each raid, by name. Used only to carry a catalogue that was
-- recorded without a zone (a flat source table) into the right library; any
-- source not listed here has no raid to go to and is dropped with it.
local LEGACY_BOSSES = {
	["Trial of the Crusader"] = {
		"Gormok the Impaler", "Acidmaw", "Dreadscale", "Icehowl",
		"Lord Jaraxxus", "Fjola Lightbane", "Eydis Darkbane", "Anub'arak",
	},
	["Icecrown Citadel"] = {
		"Lord Marrowgar", "Lady Deathwhisper", "Deathbringer Saurfang",
		"Festergut", "Rotface", "Professor Putricide", "Prince Valanar",
		"Prince Keleseth", "Prince Taldaram", "Blood-Queen Lana'thel",
		"Valithria Dreamwalker", "Sindragosa", "The Lich King",
	},
	["The Ruby Sanctum"] = {
		"Halion", "Baltharus the Warborn", "Saviana Ragefire", "General Zarithrian",
	},
}

local UNKNOWN_DIFF = "?"
P.UNKNOWN_DIFF = UNKNOWN_DIFF

local function libraries()
	local d = logDB()
	d.lib = d.lib or {}
	local function carry(zone, name, spells)
		d.lib[zone] = d.lib[zone] or {}
		local bucket = d.lib[zone][UNKNOWN_DIFF] or {}
		d.lib[zone][UNKNOWN_DIFF] = bucket
		bucket[name] = bucket[name] or { spells = spells }
	end
	-- Flat { [source] = spells }: bosses whose raid is certain move over.
	if d.seen then
		for zone, bosses in pairs(LEGACY_BOSSES) do
			for _, name in ipairs(bosses) do
				if d.seen[name] then carry(zone, name, d.seen[name]) end
			end
		end
		d.seen = nil
	end
	-- Per raid with no difficulty: { [zone] = { [source] = spells } }.
	if d.raids then
		for zone, sources in pairs(d.raids) do
			for name, spells in pairs(sources) do carry(zone, name, spells) end
		end
		d.raids = nil
	end
	return d.lib
end

-- The raid and difficulty this pull is in, or nil outside a raid instance.
-- Read once per pull: neither changes mid-fight, and the combat log fires
-- thousands of times.
local catZone, catDiff
local function raidZone()
	local inInstance, itype = IsInInstance()
	if not inInstance or itype ~= "raid" then return nil end
	local zone = (GetZoneText and GetZoneText()) or ""
	return zone ~= "" and zone or nil
end

local function raidDiff()
	local N = Okanvil.Notes
	local size = N and N.RaidSize and N.RaidSize()
	local heroic = N and N.RaidHeroic and N.RaidHeroic()
	if not size or heroic == nil then return UNKNOWN_DIFF end
	return size .. (heroic and "H" or "N")
end

function P.DiffKey(size, heroic)
	return (size or 25) .. (heroic and "H" or "N")
end

local function entryFor(zone, diff, srcName)
	local libs = libraries()
	libs[zone] = libs[zone] or {}
	local bucket = libs[zone][diff]
	if not bucket then
		bucket = {}
		libs[zone][diff] = bucket
	end
	local e = bucket[srcName]
	if not e then
		e = { spells = {} }
		bucket[srcName] = e
	end
	return e
end

-- The boss this cast belongs to. The source NAME, not the note or the room: a
-- room can hold two bosses (the Plagueworks) and the note is whatever happens
-- to be selected, which may be the wrong one or none at all.
local function noteSpell(zone, diff, srcName, prefix, spellID, spellName)
	if not srcName or srcName == "" then return end
	local e = entryFor(zone, diff, srcName)
	local key = prefix .. ":" .. spellID
	local row = e.spells[key]
	if row then
		if not e.killed then row.n = row.n + 1 end
		return
	end
	-- Bounded per source, so a boss with a long tail of trash abilities cannot
	-- grow the file without limit.
	local count = 0
	for _ in pairs(e.spells) do count = count + 1 end
	if count >= 60 then return end
	e.spells[key] = {
		id = spellID,
		name = (type(spellName) == "string" and spellName) or "?",
		prefix = prefix,
		n = 1,
	}
end

-- A source seen dying is complete. Only one that has cast something has an
-- entry to mark, so trash killed before it did anything leaves nothing behind.
local function markKilled(zone, diff, name)
	local lib = libraries()[zone]
	local e = lib and lib[diff] and lib[diff][name]
	if e and not e.killed then e.killed = time() end
end

local function bucketOf(zone, diff)
	local lib = libraries()[zone]
	return lib and lib[diff]
end

-- Every spell recorded against one source, most cast first.
function P.SpellsSeen(zone, diff, srcName)
	local b = bucketOf(zone, diff)
	local e = b and b[srcName]
	if not e then return {} end
	local out = {}
	for _, row in pairs(e.spells) do out[#out + 1] = row end
	table.sort(out, function(x, y) return (x.n or 0) > (y.n or 0) end)
	return out
end

-- When the source was seen dying, or nil while it is still being recorded.
function P.KilledAt(zone, diff, srcName)
	local b = bucketOf(zone, diff)
	return b and b[srcName] and b[srcName].killed
end

-- Everyone seen casting in one raid and difficulty, busiest first: a boss
-- casts far more than the trash around it, so the bosses rise to the top.
function P.SourcesSeen(zone, diff)
	local b = bucketOf(zone, diff)
	if not b then return {} end
	local out, total = {}, {}
	for name, e in pairs(b) do
		local n = 0
		for _, row in pairs(e.spells) do n = n + (row.n or 0) end
		if n > 0 then
			out[#out + 1] = name
			total[name] = n
		end
	end
	table.sort(out, function(x, y)
		if total[x] ~= total[y] then return total[x] > total[y] end
		return x < y
	end)
	return out
end

-- Throws one source's record away so the next pull records it from scratch.
function P.ResetSource(zone, diff, srcName)
	local b = bucketOf(zone, diff)
	if b then b[srcName] = nil end
end

-- Wipes one raid's library, or every library when no zone is given.
function P.ClearCatalogue(zone)
	local libs = libraries()
	if zone then libs[zone] = nil else logDB().lib = {} end
end

local function logPull()
	local pulls = logDB().pulls
	local rec = {
		start = time(),
		zone = (GetZoneText and GetZoneText()) or "?",
		room = (GetSubZoneText and GetSubZoneText()) or "?",
		-- The minimap's name as well: it is what picks the note (NoteForHere),
		-- and the two differ where a subzone spans a whole wing.
		mini = (GetMinimapZoneText and GetMinimapZoneText()) or "?",
		note = (OkanvilNotesDB and OkanvilNotesDB.selected) or "?",
		events = {},
	}
	pulls[#pulls + 1] = rec
	while #pulls > LOG_PULLS do table.remove(pulls, 1) end
	return rec
end

local pullRec = nil

local function resetEncounter()
	pullAt = nil
	phase, phaseAt = 1, nil
	counters = {}
	reached = {}
	fightId, fightName = nil, nil
end

-- ------------------------------------------------------------
-- Two bosses, one note
--
-- Rotface and Festergut share one subzone, so they share one note, split by a
-- header line per boss ("Rotface - Right" / "Festergut - Left"). Run whole, the
-- Festergut timers counted down on the Rotface pull too, and the other way round.
--
-- During a DBM fight only the section of the boss being fought is kept, plus
-- whatever sits above the first header (shared by both). Out of a fight the
-- whole note shows, so it still reads as one plan.
--
-- A header is a line that STARTS with one of the names in the note's own name
-- ("Rotface & Festergut"), colour codes ignored. The boss is matched on DBM's
-- mod id ("Rotface"), which is the same in every client language, or on its
-- localised name.
-- ------------------------------------------------------------
local function plainLower(s)
	return (s:gsub("||", "|"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		:gsub("{[^}]*}", ""):match("^%s*(.-)%s*$") or ""):lower()
end

function P.FightBoss() return fightId, fightName end

-- When DBM engaged the boss being fought (GetTime() clock), or nil. The Timers
-- aura reads it on entering combat: a healer who gets into combat seconds after
-- the tank pulled would otherwise start every pull-timed line that late.
function P.PullAt() return dbmLive and pullAt or nil end

function P.Section(noteName, text)
	if not (fightId or fightName) or type(text) ~= "string" or type(noteName) ~= "string" then
		return text
	end
	local base = noteName:gsub("%s*%(10%)", ""):gsub("%s*%(HC%)", "")
	if not base:find("&", 1, true) then return text end
	local parts = {}
	for part in base:gmatch("[^&]+") do
		part = part:match("^%s*(.-)%s*$"):lower()
		if part ~= "" then parts[#parts + 1] = part end
	end
	local want
	local id, loc = (fightId or ""):lower(), (fightName or ""):lower()
	for _, part in ipairs(parts) do
		if part == id or part == loc or (id ~= "" and part:find(id, 1, true))
			or (loc ~= "" and part:find(loc, 1, true)) then
			want = part
		end
	end
	if not want then return text end   -- a fight this note has no section for

	local out, current = {}, nil
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local low = plainLower(line)
		for _, part in ipairs(parts) do
			if low:sub(1, #part) == part then current = part; break end
		end
		if current == nil or current == want then out[#out + 1] = line end
	end
	return table.concat(out, "\n")
end

-- ------------------------------------------------------------
-- Parsing
--
-- One note line becomes one entry. Lines without a {time:} tag are kept as
-- plain text -- the ICC notes carry marker assignments and headers that have no
-- timer and must still show.
-- ------------------------------------------------------------

-- "{time:01:04,SCC:72905:3}rest" -> 64, "SCC:72905:3", "rest"
local function parseTime(line)
	local mm, ss, opts = line:match("^%s*{time:(%d+)[:%.]?(%d*),?([^{}]*)}")
	if not mm then return nil end
	local secs
	if ss == nil or ss == "" then
		secs = tonumber(mm) or 0          -- {time:65} is 65 seconds, not 65 minutes
	else
		secs = (tonumber(mm) or 0) * 60 + (tonumber(ss) or 0)
	end
	local rest = line:gsub("^%s*{time:[^}]*}", "", 1)
	return secs, (opts ~= "" and opts or nil), rest
end

-- The anchor decides what the offset counts FROM. A bare {time:} counts from
-- the pull; anything else names an occurrence of a combat-log event.
local function parseAnchor(opts)
	if not opts then return nil end
	for opt in opts:gmatch("[^,]+") do
		local prefix, spellID, count = opt:match("^(%a+):(%d+):?(%d*)$")
		if prefix and (prefix == "SCC" or prefix == "SCS" or prefix == "SAA" or prefix == "SAR") then
			-- The key is matched exactly as typed. Most Icecrown abilities carry a
			-- different id per difficulty (Infest 70541/73779/73780/73781), and
			-- nothing translates between them: a note must name the id of its own
			-- difficulty, or the line waits for an event that never comes.
			return {
				kind   = "event",
				prefix = prefix,
				spell  = tonumber(spellID),
				count  = (count ~= "" and count) or "1",
				key    = prefix .. ":" .. spellID .. ":" .. ((count ~= "" and count) or "1"),
			}
		end
		local ph = opt:match("^p(%d+)$")
		if ph then return { kind = "phase", phase = tonumber(ph) } end
	end
	return nil
end

-- Turn the display half of a line into something readable: spell icons inline,
-- raid markers as textures, colour codes left alone (the UI honours them).
-- ROLE SLOTS. A note written with {Holy1} instead of a name is a note that
-- survives a roster change: set the slot once in Settings and every boss updates
-- at the same time. Writing the names in by hand meant a paladin leaving the
-- guild was eleven separate edits, and any you missed called the wrong person.
--
-- Slots live in Okanvil.db.notes.slots as { Holy1 = "Okanor", ... }. Unknown
-- slots are left as written, so a typo shows up as {Hooly1} rather than
-- silently vanishing from the line.
--
-- Applied here, in the ONE place every reader goes through: the display, the
-- fight window, and IsMine (which decides whether a line is about you) all call
-- Render, so all three see the same substituted text.
-- Notes live in their OWN SavedVariable (OkanvilNotesDB), not under Okanvil.db
-- like most modules -- reading Okanvil.db.notes found nothing, so a slot you
-- filled in changed nothing on screen.
function P.Slots()
	return (OkanvilNotesDB and OkanvilNotesDB.slots) or {}
end

function P.FillSlots(text)
	if not text or text == "" then return text end
	local slots = P.Slots()
	if not next(slots) then return text end
	return (text:gsub("{(%a+%d*)}", function(tag)
		-- Raid-target icons win. {skull} and friends are drawn as icons further
		-- down Render, so a slot that happened to be named "star" would have
		-- eaten the marker before it ever got there.
		if ICONS[tag:lower()] then return "{" .. tag .. "}" end
		local who = slots[tag] or slots[tag:lower()]
		-- Class-coloured the same way a hand-written name is, so a filled slot is
		-- indistinguishable from a name typed in.
		if who and who ~= "" then return "|cfff58cba" .. who .. "|r" end
		return "{" .. tag .. "}"
	end))
end

-- How big an inline icon is drawn. The window owns the number (it is a
-- setting beside the text size) and pushes it here, so the parser stays
-- free of the window and a note rendered anywhere else still has a size.
P.iconSize = 18
function P.SetIconSize(px)
	P.iconSize = tonumber(px) or 18
end

function P.Render(text)
	if not text or text == "" then return "" end
	local S = ":" .. (P.iconSize or 18) .. "|t"
	-- Notes copied out of MRT carry escaped pipes (||cff...), which a FontString
	-- prints literally instead of colouring. Unescape first.
	text = text:gsub("||", "|")
	-- Where the note runs, not something to read (Notes.lua reads it).
	text = text:gsub("{room:[^}]*}", "")
	text = P.FillSlots(text)
	text = text:gsub("{spell:(%d+):?%d*}", function(id)
		return "|T" .. P.SpellIcon(id) .. S
	end)
	-- Items too, for the lines that call for a healthstone or a potion: those
	-- are things in your bags, and asking for a spell id would mean naming the
	-- warlock spell that makes the stone rather than the stone you click.
	--
	-- NOT MRT syntax. A note written with this and sent to someone reading it
	-- in MRT shows the tag as plain text there.
	text = text:gsub("{item:(%d+):?%d*}", function(id)
		return "|T" .. P.ItemIcon(id) .. S
	end)
	text = text:gsub("{(%a+%d?)}", function(tag)
		local n = ICONS[tag:lower()]
		if not n then return "{" .. tag .. "}" end
		return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. n .. S
	end)
	return text
end

-- An item icon. Same problem as a boss spell: an item the client has not seen
-- this session answers nil to everything, so the tooltip is asked for it
-- first to pull it into the cache. Without that, an id nobody in the group
-- happens to be carrying renders as nothing at all.
local itemIconCache = {}
function P.ItemIcon(id)
	id = tonumber(id)
	if not id then return "Interface\\Icons\\INV_Misc_QuestionMark" end
	if itemIconCache[id] then return itemIconCache[id] end

	local icon = GetItemIcon and GetItemIcon(id)
	if not icon then
		local tip = _G.OkanvilNotesTip
		if not tip then
			tip = CreateFrame("GameTooltip", "OkanvilNotesTip", UIParent, "GameTooltipTemplate")
		end
		pcall(function()
			tip:SetOwner(UIParent, "ANCHOR_NONE")
			tip:SetHyperlink("item:" .. id)
			tip:Hide()
		end)
		icon = (GetItemIcon and GetItemIcon(id)) or select(10, GetItemInfo(id))
	end

	icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
	-- Only cache a real answer: the server may still be sending the item.
	if icon ~= "Interface\\Icons\\INV_Misc_QuestionMark" then itemIconCache[id] = icon end
	return icon
end

-- A spell outside your own spellbook -- every boss ability in these notes --
-- returns nil from GetSpellInfo on 3.3.5a until the client has seen it. Asking
-- the tooltip for it warms the cache, which is the trick the Kaze aura uses.
local iconCache = {}
function P.SpellIcon(id)
	id = tonumber(id)
	if not id then return "Interface\\Icons\\INV_Misc_QuestionMark" end
	if iconCache[id] then return iconCache[id] end

	local icon = GetSpellTexture and GetSpellTexture(id)
	if not icon then icon = select(3, GetSpellInfo(id)) end
	if not icon then
		local tip = _G.OkanvilNotesTip
		if not tip then
			tip = CreateFrame("GameTooltip", "OkanvilNotesTip", UIParent, "GameTooltipTemplate")
		end
		pcall(function()
			tip:SetOwner(UIParent, "ANCHOR_NONE")
			tip:SetHyperlink("spell:" .. id)
			tip:Hide()
		end)
		icon = (GetSpellTexture and GetSpellTexture(id)) or select(3, GetSpellInfo(id))
	end

	icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
	-- Only cache a real answer: a question mark now may resolve later.
	if icon ~= "Interface\\Icons\\INV_Misc_QuestionMark" then iconCache[id] = icon end
	return icon
end

-- ------------------------------------------------------------
-- Is this line mine?
--
-- Same rule the Kaze aura uses: a line is yours if it contains your name, or
-- your class, spec or role. Matching text rather than a slot table is what lets
-- one note work for everyone -- each client asks the question about itself.
-- ------------------------------------------------------------
local myKeys
local function keysForMe()
	if myKeys then return myKeys end
	myKeys = {}
	local name = UnitName("player")
	if name then myKeys[#myKeys + 1] = name:lower() end
	local _, class = UnitClass("player")
	if class then myKeys[#myKeys + 1] = class:lower() end
	local I = Okanvil.Inspect
	if I and I.Get and name then
		local spec, _, role = I.Get(name)
		if spec then myKeys[#myKeys + 1] = spec:lower() end
		if role then myKeys[#myKeys + 1] = role:lower() end
	end
	return myKeys
end

-- Talents change; drop the cache so the next line re-asks.
local specWatch = CreateFrame("Frame")
specWatch:RegisterEvent("PLAYER_TALENT_UPDATE")
specWatch:RegisterEvent("CHARACTER_POINTS_CHANGED")
specWatch:SetScript("OnEvent", function() myKeys = nil end)

function P.IsMine(text)
	if not text or text == "" then return false end
	-- Strip colour codes first, or "|cfff58cbaOkanor|r" hides the name inside a
	-- hex run and a short name could match the colour itself.
	local plain = text:gsub("||", "|"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
	for _, k in ipairs(keysForMe()) do
		if k ~= "" and plain:find(k, 1, true) then return true end
	end
	return false
end

-- Parse a whole note into a list of entries, in the order written.
--   { time=, anchor=, text=, raw=, spellID=, mine= }
function P.Parse(note)
	local out = {}
	if not note or note == "" then return out end
	-- Split on the newline itself, not on runs of non-newline characters.
	-- "[^\r\n]+" needs at least one character to match, so a blank line
	-- produced nothing at all and the gap a note used to separate two fights
	-- -- Rotface above, Festergut below -- silently closed up.
	-- The extra parentheses matter: gsub returns the string AND a count, and
	-- the count would land in the concatenation.
	local body = (note:gsub("\r?\n$", "")) .. "\n"
	for line in body:gmatch("([^\r\n]*)\r?\n") do
		local secs, opts, rest = parseTime(line)
		-- A line that only says which room the note runs in is not a row: left in,
		-- it would draw as a blank gap at the top of every note that uses it.
		if line:find("{room:", 1, true) and not line:gsub("{room:[^}]*}", ""):match("%S") then
			-- skipped
		elseif secs then
			out[#out + 1] = {
				time    = secs,
				anchor  = parseAnchor(opts),
				text    = rest,
				raw     = line,
				spellID = tonumber(line:match("{spell:(%d+)")),
				mine    = P.IsMine(rest),
			}
		else
			-- A blank line is kept, as a blank row: it is spacing the author put
			-- there on purpose, and dropping it ran two sections together.
			out[#out + 1] = { text = line, raw = line, plain = true,
			                  blank = not line:match("%S") }
		end
	end
	return out
end

-- ------------------------------------------------------------
-- Countdown
--
-- The whole timing model, and the reason a line slides when the raid pushes
-- harder: an event-anchored line hangs off the moment that occurrence happened,
-- so if the cast comes early, everything after it comes early too.
--
-- Returns seconds remaining, or nil when the line has no countdown yet (out of
-- combat, or waiting on an occurrence that has not happened).
-- ------------------------------------------------------------
function P.Remaining(entry, now)
	if entry.plain or not entry.time then return nil end
	now = now or GetTime()

	if not entry.anchor then
		if not pullAt then return nil end
		return entry.time - (now - pullAt)
	end

	if entry.anchor.kind == "phase" then
		if not phaseAt or entry.anchor.phase ~= phase then return nil end
		return entry.time - (now - phaseAt)
	end

	local at = reached[entry.anchor.key]
	if not at then return nil end
	return entry.time - (now - at)
end

-- ------------------------------------------------------------
-- Watching the fight
-- ------------------------------------------------------------

-- Did an NPC cast this -- a creature OR a vehicle?
--
-- U.guidIsNPC answers for the creature type alone, which is not enough here:
-- several encounters do their work through something the client files as a
-- vehicle (the Gunship, Halion's twilight realm, Putricide's oozes), and
-- dropping those threw away the very casts those notes anchor to.
--
-- Reads the type nibble out of a normalised 16-digit hex string rather than a
-- fixed offset, because a GUID can arrive as a number on some cores -- the same
-- trap that left the farm tracker's kill counter stuck at zero.
local function isNPCsrc(guid)
	if not guid then return false end
	local hex = tostring(guid):match("^0[xX](%x+)$") or tostring(guid):match("^(%x+)$")
	if not hex then return false end
	if #hex < 16 then hex = string.rep("0", 16 - #hex) .. hex end
	local b = tonumber(hex:sub(3, 3), 16)
	if not b then return false end
	b = b % 8
	return b == 3 or b == 5          -- 3 creature, 5 vehicle
end

local watch = CreateFrame("Frame")
watch:RegisterEvent("PLAYER_REGEN_DISABLED")
watch:RegisterEvent("PLAYER_REGEN_ENABLED")
watch:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

-- Switched off in Modules means off, not hidden. This one matters more than
-- most: without it the combat-log handler below runs on every swing of every
-- fight, counting spells for a module you told the addon to stop using.
local function moduleOn()
	return not Okanvil.ModuleActive or Okanvil:ModuleActive("Okanvil-Notes")
end

-- A fresh pull, counted from `at`.
local function startEncounter(at)
	resetEncounter()
	pullAt = at
	phaseAt = at
	-- A fresh pull starts a fresh record. Kept past the end of the fight,
	-- unlike the counters, so a wipe can still be read back afterwards.
	seenKeys = {}
	catZone = raidZone()
	catDiff = catZone and raidDiff() or nil
	-- Raid pulls only, like the catalogue: notes are for raid bosses, and a
	-- watch left on would otherwise log (and announce) every dungeon pack.
	pullRec = (P.Debug() and catZone) and logPull() or nil
	if pullRec then
		Okanvil:Print("|cff7cfc8a[notes]|r recording this pull -- /reload when done.")
	end
end

watch:SetScript("OnEvent", function(_, event, ...)
	if not moduleOn() then return end

	if event == "PLAYER_REGEN_DISABLED" then
		-- DBM already started this fight (see P.HookDBM): its clock stands, and
		-- the casts counted while you were still out of combat stay counted.
		-- A DBM fight older than any boss lasts lost its kill/wipe: not this one.
		if dbmLive and pullAt and GetTime() - pullAt < DBM_STALE then return end
		dbmLive = false
		-- No ENCOUNTER_START on 3.3.5a and no DBM fight: entering combat is the pull.
		startEncounter(GetTime())
		Okanvil:Trace("NOTES", "clock: combat start (no DBM pull yet)")
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		-- In a DBM fight, leaving combat is YOU (dead, feigned, vanished), not the
		-- boss: the fight ends on DBM's kill or wipe.
		if dbmLive then return end
		resetEncounter()
		return
	end

	if not pullAt then return end

	-- 3.3.5a's combat log has no raid-flag fields, so spellID sits two slots
	-- earlier than on retail. Signature:
	--   timestamp, event, sourceGUID, sourceName, sourceFlags,
	--   destGUID, destName, destFlags, spellID, spellName, spellSchool
	-- Reading the retail position silently counted spellName as the id, so
	-- every {time:...,SCC:nnn:k} anchor waited for an occurrence that never came.
	local _, sub, srcGUID, srcName, srcFlags, _, dstName, _, spellID = ...

	-- A catalogued NPC dying closes its record for this difficulty.
	if sub == "UNIT_DIED" then
		if catZone and isNPCsrc((select(6, ...))) then markKilled(catZone, catDiff, dstName) end
		return
	end
	local prefix = CLEU_PREFIX[sub]
	if not prefix then return end

	-- ONLY what an NPC did. Every note anchor names a boss ability, and counting
	-- anything else is not merely noise: leaving combat drops every buff in the
	-- raid at once, so a whole raid's worth of SPELL_AURA_REMOVED lands in one
	-- frame and bumps counters a note is waiting on. "The 3rd Frostbolt Volley"
	-- has to mean the boss's third, not the third aura to fall off a raider.
	--
	-- Creatures AND vehicles. U.guidIsNPC answers only for the creature type,
	-- and several encounters do their work through something the client counts
	-- as a vehicle -- the Gunship, Halion's twilight realm, Putricide's oozes --
	-- so asking it alone threw away the very casts those notes are anchored to.
	if not isNPCsrc(srcGUID) then return end

	-- ...and not one a PLAYER controls. A mage's Mirror Images, a shaman's
	-- wolves, a priest's Shadowfiend are creatures by GUID too, and their
	-- Frostbolts and Bashes filled the pull record and the catalogue. The log
	-- marks them: COMBATLOG_OBJECT_CONTROL_PLAYER (0x100) in the source flags.
	if srcFlags and bit and bit.band(srcFlags, 0x100) ~= 0 then return end

	-- The id must be a number in slot 9. When it is not, the core is laying the
	-- log out differently and EVERY anchored line in every note will wait for
	-- something that never arrives -- so say so once rather than fail in silence
	-- for a whole fight.
	if type(spellID) ~= "number" then
		if pullRec and not pullRec.badSlot then
			pullRec.badSlot = ("%s -> %s (%s)"):format(sub, tostring(spellID), type(spellID))
		end
		return
	end

	local base = prefix .. ":" .. spellID
	local n = (counters[base] or 0) + 1
	counters[base] = n
	local key = base .. ":" .. n
	reached[key] = GetTime()
	local at = GetTime() - (pullAt or 0)
	seenKeys[key] = at

	local spellName = select(10, ...)

	-- The catalogue runs on every raid pull, with nothing switched on. One row per spell
	-- per boss, so it costs a counter bump for everything after the first
	-- sighting -- cheap enough to leave on for every pull of every night, which
	-- is the point: the answer is already there when you sit down to write.
	if catZone then noteSpell(catZone, catDiff, srcName, prefix, spellID, spellName) end

	-- The full ordered trace is the opt-in half (/oknotes watch), because that
	-- one IS per occurrence and would grow without bound.
	if pullRec and #pullRec.events < LOG_PER_PULL and n <= LOG_PER_SPELL then
		pullRec.events[#pullRec.events + 1] = {
			key = key, at = at, name = tostring(spellName or "?"),
		}
	end
end)

-- DBM already tracks phases and fires a callback for them (DBM-Core.lua:6926),
-- so there is nothing to infer here. Registered once, lazily -- DBM loads after
-- this file.
--
-- The pull too. Entering combat is only when YOU got into it: a healer standing
-- back, a pre-pot, or trash running into the boss puts that seconds away from
-- the engage, and every {time:} line drifted off DBM's bars by the same amount.
-- DBM_Pull is the engage DBM starts its own timers from, with how late it
-- noticed (delay), so the notes count from the same moment DBM does.
--
-- DBM builds its callback API across its own load steps and may not have it at
-- PLAYER_LOGIN, so this retries like Core's pull hook.
local hooked = false
local HOOK_TRIES, HOOK_EVERY = 20, 1.5
function P.HookDBM(attempt)
	if hooked then return end
	if not (DBM and DBM.RegisterCallback) then
		attempt = attempt or 1
		local After = Okanvil.Comms and Okanvil.Comms.After
		if attempt < HOOK_TRIES and After then
			After(HOOK_EVERY, function() P.HookDBM(attempt + 1) end)
		else
			Okanvil:Trace("NOTES", "DBM not found: notes count from entering combat")
		end
		return
	end
	hooked = true
	Okanvil:Trace("NOTES", "DBM hooked: notes count from DBM's pull")
	DBM:RegisterCallback("DBM_Pull", function(_, mod, delay)
		if not moduleOn() then return end
		local at = GetTime() - (tonumber(delay) or 0)
		dbmLive = true
		-- Set after startEncounter below would wipe it; see the end of this function.
		local id = mod and mod.id
		local loc = mod and mod.localization and mod.localization.general
			and mod.localization.general.name
		local modName = tostring(id or "?")
		if not pullAt or at - pullAt > DBM_GRACE then
			-- Not in combat yet (the tank has the boss, you have not acted), or in
			-- combat since the trash before it: either way the boss starts now,
			-- and what trash did is not counted against its note.
			Okanvil:Trace("NOTES", ("clock: DBM pull %s (DBM %.1fs late) -- new fight%s"):format(modName,
				tonumber(delay) or 0, pullAt and (", combat was %.1fs earlier"):format(at - pullAt) or ""))
			startEncounter(at)
		else
			-- Entered combat within a moment of the engage: same pull, DBM's clock.
			Okanvil:Trace("NOTES", ("clock: DBM pull %s (DBM %.1fs late) -- moved %.1fs from combat start"):format(
				modName, tonumber(delay) or 0, at - pullAt))
			pullAt = at
			phase, phaseAt = 1, at
		end
		fightId = type(id) == "string" and id or nil
		fightName = type(loc) == "string" and loc or nil
		-- The Timers aura keeps its own clock. Tell it where the pull really was,
		-- after the boss is known, so a note shared by two bosses is re-read as
		-- this boss's section when the aura restarts its timers.
		if WeakAuras and WeakAuras.ScanEvents then
			WeakAuras.ScanEvents("OKANVIL_PULL", at)
		end
	end)
	-- The fight ends when DBM says so, not when you leave combat.
	local function fightOver()
		if not dbmLive then return end
		dbmLive = false
		Okanvil:Trace("NOTES", ("DBM fight over at %.1fs"):format(pullAt and (GetTime() - pullAt) or -1))
		if not (InCombatLockdown and InCombatLockdown()) then resetEncounter() end
	end
	DBM:RegisterCallback("DBM_Kill", fightOver)
	DBM:RegisterCallback("DBM_Wipe", fightOver)
	-- The gate goes INSIDE the callback, not around the registration: DBM offers
	-- no way to unregister, so a hook installed at login is permanent. Checking
	-- here means a disabled Notes module stops tracking phases without leaving a
	-- dead hook that can never be removed.
	DBM:RegisterCallback("DBM_SetStage", function(_, _, _, stage)
		if not stage then return end
		if Okanvil.ModuleActive and not Okanvil:ModuleActive("Okanvil-Notes") then return end
		phase = stage
		phaseAt = GetTime()
		Okanvil:Trace("NOTES", ("DBM stage %s at %.1fs"):format(tostring(stage),
			pullAt and (phaseAt - pullAt) or -1))
	end)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
	P.HookDBM()
	-- Bring the switch back across the /reload that saved the file, and make
	-- sure the table exists either way: an absent table says the addon never
	-- loaded, an empty one says it loaded and caught nothing. Those needed
	-- telling apart.
	local d = logDB()
	P.debug = d.watching and true or false
	d.lastLogin = time()
end)
