-- ============================================================
-- Okanvil -- Notes  (WotLK 3.3.5a)
--
-- Raid notes in the community ICC format, without MRT. Phase 1: hold them,
-- edit them, and switch to the right one when you walk into a boss room.
--
-- The timer syntax ({time:...}, role slots, the WeakAuras bridge) is parsed in
-- later phases; this file treats a note as text and never rewrites it. Format
-- reference: docs/MRT_NOTE_FORMAT.md, plan: docs/NOTES_MODULE.md.
-- ============================================================

local ADDON = "Okanvil-Notes"
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

local N = {}
Okanvil.Notes = N

local W = Okanvil.W
local db          -- OkanvilNotesDB
local F           -- the built UI

-- ------------------------------------------------------------
-- Which note belongs to which room.
--
-- ICC gives every boss its own subzone, so walking in is enough to pick the
-- note. Keyed by subzone because GetZoneText() is "Icecrown Citadel" for the
-- whole instance.
--
-- The Plagueworks holds BOTH Rotface and Festergut, which is why the community
-- notes ship them combined -- a subzone cannot tell them apart.
-- ------------------------------------------------------------
-- Both the room a boss is IN and the older names are listed. Subzone strings
-- vary between cores -- a private server may report "The Spire" where retail
-- says "Light's Hammer" -- and an entry that matches nothing simply never
-- fires, so carrying both costs nothing and fixes the room that did not switch.
local ZONE_NOTE = {
	-- Lower Spire
	["Light's Hammer"]               = "Lord Marrowgar",
	["The Spire"]                    = "Lord Marrowgar",
	["The Oratory of the Damned"]    = "Lady Deathwhisper",
	["Oratory of the Damned"]        = "Lady Deathwhisper",
	["The Colossal Forge"]           = "Gunship Battle",
	["Rampart of Skulls"]            = "Gunship Battle",
	["The Skybreaker"]               = "Gunship Battle",
	["Orgrim's Hammer"]              = "Gunship Battle",
	["The Deathbringer's Rise"]      = "Deathbringer Saurfang",
	["Deathbringer's Rise"]          = "Deathbringer Saurfang",

	-- Plagueworks: one subzone for both side rooms, which is why the shipped
	-- pack combines them into a single note.
	["The Plagueworks"]              = "Rotface & Festergut",
	["The Laboratory of the Alchemist"] = "Professor Putricide",
	["Putricide's Laboratory of Alchemical Horrors and Fun"] = "Professor Putricide",

	-- Crimson Hall: the Blood Council and Lana'thel share the hall on some
	-- cores, so the inner sanctum is listed separately where it is reported.
	["The Crimson Hall"]             = "Blood Council",
	["The Sanctum of Blood"]         = "Queen Lana'thel",
	["Crimson Hall Inner Sanctum"]   = "Queen Lana'thel",

	-- Frostwing Halls
	["The Frostwing Halls"]          = "Valithria Dreamwalker",
	["Sindragosa's Lair"]            = "Sindragosa",
	["The Frost Queen's Lair"]       = "Sindragosa",
	["The Frozen Throne"]            = "The Lich King",

	["The Ruby Sanctum"]             = "Halion",

	-- The practice rooms: the target dummies in the capitals. A note named after
	-- one of these runs there through this same lookup, which is the whole
	-- reason there is no test-mode bypass any more -- you test on the real path
	-- rather than on a flag that answers yes everywhere and then follows you
	-- into a dungeon.
	--
	-- Both factions, because the note list is account-wide and an alt on the
	-- other side would otherwise have nowhere to practise.
	["Valley of Honor"]              = "Valley of Honor",
	["Valley of Wisdom"]             = "Valley of Honor",
	["The Great Forge"]              = "Valley of Honor",
	["Hall of Arms"]                 = "Valley of Honor",
}

-- The order the list shows them in: the order you meet them, not alphabetical.
-- The raids, in pull order within each.
--
-- One flat list of every boss in the game is a list you scroll rather than read:
-- ICC alone is twelve, and a Trial note sat under them where nobody looked. A
-- tab per raid keeps each list to what one night actually needs.
local RAIDS = {
	{ key = "icc", label = "ICC", zone = "Icecrown Citadel", bosses = {
		"Lord Marrowgar", "Lady Deathwhisper", "Gunship Battle",
		"Deathbringer Saurfang", "Rotface & Festergut", "Professor Putricide",
		"Blood Council", "Queen Lana'thel", "Valithria Dreamwalker",
		"Sindragosa", "The Lich King",
	} },
	{ key = "toc", label = "ToC", zone = "Trial of the Crusader",
		altZone = "Trial of the Grand Crusader", bosses = {
		"Northrend Beasts", "Lord Jaraxxus", "Faction Champions",
		"Val'kyr Twins", "Anub'arak",
	} },
	{ key = "rs", label = "RS", zone = "The Ruby Sanctum", bosses = {
		"Halion",
	} },
}

-- Flat, still: the zone lookup and anything else that asks "is this a boss we
-- know?" wants one list, not three.
local NOTE_ORDER = {}
for _, raid in ipairs(RAIDS) do
	for _, boss in ipairs(raid.bosses) do
		NOTE_ORDER[#NOTE_ORDER + 1] = boss
	end
end

local defaults = {
	notes = {},        -- [name] = text
	autoZone = true,   -- switch note on entering a boss room
	selected = nil,    -- which note the page is showing
	share = true,      -- swap notes with other officers automatically
	stamps = {},       -- [name] = time() of the last edit, for the sync
	-- [name] = who last wrote the text we hold. Your own name for a note you
	-- typed, the sender's for one that arrived from an officer.
	--
	-- Needed because the notes table is ACCOUNT-WIDE while "did I write this?"
	-- is not: an alt shares every note the main ever stored, so asking whether
	-- a row exists -- which is all there used to be -- marked the whole list as
	-- the alt's own work the first time it opened the page.
	authors = {},
	-- Role slots -> names, for the {Holy1} style tags the shipped pack uses.
	-- EMPTY by default: they are a roster, and a roster belongs to whoever
	-- installs this. An unset slot renders as "{Holy1}" in the note, which says
	-- "nobody assigned" far better than someone else's guild's paladin would.
	slots = {},
	slotStamp = 0,     -- when the slots last changed, for the sync
	viewSize = nil,    -- 10/25 tab; nil = follow the raid you are in
	viewHeroic = nil,  -- normal/heroic tab; nil = follow the raid you are in
	viewRaid = nil,    -- ICC/ToC/RS tab; nil = follow the zone you are in
}

-- ------------------------------------------------------------
-- Data
-- ------------------------------------------------------------
-- A note you have never written falls back to the shipped ICC pack, so the tab
-- is useful before you have typed anything. Writing one makes it yours and the
-- pack is never consulted for it again.
-- ------------------------------------------------------------
-- Raid size
--
-- A 10 and a 25 are different fights with the same boss names: fewer cooldowns,
-- a different order, sometimes a mechanic that only exists in one of them. One
-- note cannot serve both, and picking the wrong one is not obvious while you
-- read it -- the names are all real people either way.
--
-- Stored as a SUFFIX on the note name ("Sindragosa (10)"), not as a second
-- table, so everything that already works on a note by name -- the editor, the
-- sync, Clear, Delete -- keeps working with nothing changed.
--
-- The bare name stays the 25: it is what the notes already in your database are,
-- and re-keying them to say so would break the zone lookup for no gain.
-- ------------------------------------------------------------
local SIZE_SUFFIX = " (10)"

-- Heroic gets its own note, because it is a different fight with the same boss
-- name -- and, more sharply than the 10/25 split, a different set of SPELL IDS.
-- Eighty ICC abilities are numbered per difficulty: Putricide's Unstable
-- Experiment is 70351 on 10N, 71966 on 25N and 71967 on 10HC. A note written
-- for one difficulty does not merely read oddly at another, its anchors wait
-- for casts that never come, and nothing on screen says why.
local HC_SUFFIX = " (HC)"

-- The KEY a note is stored under, for a boss, a size and a difficulty. The 25
-- normal keeps the bare name, so every note written before either split already
-- is the 25 normal.
--
--   Professor Putricide             25 normal
--   Professor Putricide (10)        10 normal
--   Professor Putricide (HC)        25 heroic
--   Professor Putricide (10) (HC)   10 heroic
--
-- Suffixes in a fixed order, size then difficulty, so a key can be taken apart
-- again by stripping from the end.
function N.KeyFor(boss, size, heroic)
	if not boss or boss == "" then return boss end
	local key = (size == 10) and (boss .. SIZE_SUFFIX) or boss
	if heroic then key = key .. HC_SUFFIX end
	return key
end

local function esc(s) return (s:gsub("[%(%)]", "%%%0")) end

-- The boss, with any marker taken back off. What the list shows.
function N.BossOf(key)
	if not key then return key end
	local bare = key:match("^(.-)" .. esc(HC_SUFFIX) .. "$") or key
	bare = bare:match("^(.-)" .. esc(SIZE_SUFFIX) .. "$") or bare
	return bare
end

function N.SizeOf(key)
	if not key then return 25 end
	local noHC = key:match("^(.-)" .. esc(HC_SUFFIX) .. "$") or key
	return noHC:match(esc(SIZE_SUFFIX) .. "$") and 10 or 25
end

function N.IsHeroic(key)
	return key ~= nil and key:match(esc(HC_SUFFIX) .. "$") ~= nil
end

-- 10 or 25, from the group we are actually in.
--
-- GetRaidDifficulty is the honest answer where it exists: a 25 that has not
-- filled up yet still IS a 25, and counting heads would call it a 10 right up
-- until the last invite. Falling back to the head count is for a group that has
-- no difficulty yet, where anything above ten cannot be a ten.
function N.RaidSize()
	local n = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	if n == 0 then return nil end          -- not in a raid: no opinion
	if GetRaidDifficulty then
		local d = GetRaidDifficulty()
		-- 1 = 10 normal, 2 = 25 normal, 3 = 10 heroic, 4 = 25 heroic
		if d == 1 or d == 3 then return 10 end
		if d == 2 or d == 4 then return 25 end
	end
	return (n > 10) and 25 or 10
end

-- Heroic or not, from the group we are actually in. The same call that gives
-- the size already says this; it was simply thrown away before.
--
-- Returns nil outside a raid -- no opinion -- rather than false, so the page
-- can tell "we are in a normal raid" from "we are in Dalaran".
function N.RaidHeroic()
	if (GetNumRaidMembers and GetNumRaidMembers() or 0) == 0 then return nil end
	if not GetRaidDifficulty then return nil end
	local d = GetRaidDifficulty()
	if d == 3 or d == 4 then return true end
	if d == 1 or d == 2 then return false end
	return nil
end

-- Which size the PAGE is showing. Follows the raid you are in, until you press
-- a tab yourself -- reading the 10 plan while sat in town is a normal thing to
-- want, and a page that fights you about it is worse than one that guesses.
function N.ViewSize()
	if db and db.viewSize then return db.viewSize end
	return N.RaidSize() or 25
end

-- Which difficulty the PAGE is showing, on the same terms as the size: follows
-- the raid until a tab is pressed.
function N.ViewHeroic()
	if db and db.viewHeroic ~= nil then return db.viewHeroic end
	return N.RaidHeroic() or false
end

-- Both tabs land here, because they do the same thing to the selection: keep
-- the boss, change which of its versions is live.
local function reselect()
	local boss = N.BossOf(db.selected)
	if boss then
		-- Empty on purpose when that version is unwritten: the note you have yet
		-- to write is still the one this tab is about.
		db.selected = N.KeyFor(boss, N.ViewSize(), N.ViewHeroic())
	end
	N.Broadcast()
	if N.Refresh then N.Refresh() end
end

function N.SetViewSize(size)
	if not db then return end
	db.viewSize = (size == 10) and 10 or 25
	reselect()
end

function N.SetViewHeroic(on)
	if not db then return end
	db.viewHeroic = on and true or false
	reselect()
end

-- The note name for this boss at the size and difficulty we are raiding.
--
-- SIZE falls back, DIFFICULTY does not, and the asymmetry is deliberate.
--
-- A 10 and a 25 are the same fight with fewer people, so a guild that keeps one
-- note per boss should not have the window go blank the moment they run a 10 --
-- the 25 plan is still broadly right. Heroic is not like that: its abilities
-- carry DIFFERENT SPELL IDS, so a normal note shown in a heroic raid is not
-- merely approximate, its anchors wait for casts that never come. Showing it
-- would be worse than showing nothing, because nothing is at least obvious.
function N.SizedName(name)
	if not name or name == "" then return name end

	local heroic = N.RaidHeroic()
	local size = N.RaidSize()

	-- Outside a raid the group has no size, and reading that as "25" sent a solo
	-- player standing in a note's room to the 25 note while the 10 was the one
	-- selected -- so the room check said "not here" and nothing ran on a dummy.
	-- With no raid to decide, the variant already chosen for this boss stands,
	-- and failing that the size and difficulty the page is showing.
	if size == nil then
		local sel = db and db.selected
		if sel and N.BossOf(sel) == name then return sel end
		size, heroic = N.ViewSize(), N.ViewHeroic()
	end

	-- Heroic: exact match or nothing.
	if heroic then
		local want = N.KeyFor(name, size, true)
		local t = db and db.notes and db.notes[want]
		if t and t ~= "" then return want end
		-- The 25 heroic note, for a 10 heroic raid that has not written its own.
		if size == 10 then
			local wide = N.KeyFor(name, 25, true)
			local w = db and db.notes and db.notes[wide]
			if w and w ~= "" then return wide end
		end
		return want          -- unwritten: the page shows it empty, and says so
	end

	if size ~= 10 then return name end
	local ten = N.KeyFor(name, 10)
	local t = db and db.notes and db.notes[ten]
	if t and t ~= "" then return ten end
	return name
end

function N.Get(name)
	if not name then return nil end
	-- db is nil until ADDON_LOADED. A WeakAura's init runs on its own schedule
	-- and can reach this first -- `db.notes` then errors inside the aura, which
	-- takes the rest of ITS init down with it.
	local own = db and db.notes and db.notes[name]
	if own and own ~= "" then return own end
	return Okanvil.NotesPack and Okanvil.NotesPack[name] or nil
end

-- Is there text of our own stored for this note, as opposed to the shipped one?
-- Says nothing about WHO wrote it -- see N.IsOwn.
function N.HasStored(name)
	local t = name and db and db.notes and db.notes[name]
	return t ~= nil and t ~= ""
end

-- Did THIS character write the note we hold?
--
-- Not the same question as "is there a stored note", because the notes table is
-- account-wide and a note sent by an officer is stored exactly like one you
-- typed. Both of those made a fresh alt show "edited" against a list it had
-- never touched.
--
-- Notes stored before authors were tracked have no entry. They are reported as
-- NOT ours: the tag is there to point out the few notes you changed, and
-- guessing yes on every old note would bring back the wall of green it is
-- meant to replace.
function N.IsOwn(name)
	if not N.HasStored(name) then return false end
	local by = db and db.authors and db.authors[name]
	return by ~= nil and by == (UnitName("player") or "")
end

-- Who wrote the note we hold, or nil when it predates author tracking.
function N.AuthorOf(name)
	if not N.HasStored(name) then return nil end
	return db and db.authors and db.authors[name]
end

-- Does the pack carry this note, regardless of what the user has written over
-- it? Decides whether Clear is an undo or a delete.
function N.HasPacked(name)
	return (Okanvil.NotesPack and Okanvil.NotesPack[name]) ~= nil
end

-- ------------------------------------------------------------
-- Who may change a note.
--
-- Officers only. A raider reads the plan and receives it from the leader; the
-- page's Edit, Clear, New and Delete are switched off for them, because a note
-- they type is one only they can see and it will be overwritten by the next
-- Send anyway -- an edit that looks like it worked and then silently does not.
--
-- The guild roster is EMPTY for a second or two after a /reload, and
-- U.isOfficer reads that roster -- so asking it at the wrong moment tells an
-- officer they are not one. The answer is remembered the first time it comes
-- back true and the roster is asked to refresh when it comes back false, so a
-- cold roster delays the buttons rather than locking them.
-- ------------------------------------------------------------
local wasOfficer = false

function N.CanEdit()
	-- Unlocked by hand, per character: "/oknotes unlock".
	--
	-- The rank checks below cover the normal cases, but they depend on the
	-- guild roster saying who you are, and a character the roster has not
	-- caught up with -- a fresh alt, a note not written yet -- is locked out
	-- of notes nobody else is going to send it. This is the way back in.
	if Okanvil.cdb and Okanvil.cdb.notesUnlocked then return true end
	if not (Okanvil.U and Okanvil.U.isOfficer) then return true end   -- no roster API: do not lock anyone out
	-- NO GUILD, NO GATE. The lock exists because an officer's Send overwrites
	-- what a raider typed -- an edit that looks like it worked and then quietly
	-- does not. Outside a guild nobody can Send to you, so the notes are yours
	-- alone and locking them only stopped you using the module at all.
	if IsInGuild and not IsInGuild() then return true end
	local me = UnitName("player") or ""
	if Okanvil.U.isOfficer(me) then
		wasOfficer = true
		return true
	end
	if wasOfficer then return true end      -- known officer, roster just went cold

	-- An officer's own alt edits too. The lock is there so an officer's Send
	-- cannot quietly overwrite what a raider typed -- but an officer taking a
	-- second character into the raid is the same person, and locking them out
	-- of their own notes helps nobody. The roster already knows: the guild
	-- note says "<Main> alt", which is how the Home page counts people.
	local main = Okanvil.U.mainOf and Okanvil.U.mainOf(me)
	if main and Okanvil.U.isOfficer(main) then return true end

	if GuildRoster then GuildRoster() end   -- warm it for the next check
	return false
end

-- May this character SEND notes to other people?  Stricter than CanEdit: it
-- needs a guild (there is nobody to send to without one) and officer rank (the
-- receiving side refuses anyone else anyway, so the button would lie).
function N.CanShare()
	if not (IsInGuild and IsInGuild()) then return false end
	local U = Okanvil.U
	if not (U and U.isOfficer) then return false end
	return N.CanEdit()
end

function N.Set(name, text)
	if not name or name == "" then return end
	if not N.CanEdit() then return end
	local old = db.notes[name]
	db.notes[name] = text or ""
	-- Stamp only a real change: Commit runs on every focus loss, and re-stamping
	-- unchanged text would make this client look newer than everyone else.
	if old ~= db.notes[name] then
		-- Typed here, so this character owns it now -- even if the text that was
		-- sitting there arrived from somebody else.
		db.authors = db.authors or {}
		db.authors[name] = UnitName("player") or ""
		if N.Touch then N.Touch(name) end
	end
	if name == db.selected then N.Broadcast() end
end

-- ------------------------------------------------------------
-- What a WeakAura reads.
--
-- The aura asks for the note that is live right now, and is told when it
-- changes. Deliberately the whole public surface: an aura should not have to
-- know about OkanvilNotesDB, the shipped pack, or how zones pick a note.
-- ------------------------------------------------------------
function N.Current()
	local text = N.Get(db and db.selected) or ""

	-- Fill the role slots before handing the note over.
	--
	-- {Holy1} is a slot, not a name, and it stays literal in the stored text.
	-- Every other reader goes through NotesParse.Render, which fills the slots
	-- on the way to the screen -- so the note said "Okanor" everywhere a person
	-- could see it, and "{Holy1}" here. An aura then asked "is this line about
	-- me?", compared its owner's name against "{Holy1}", and quietly answered no
	-- for every line in the note.
	--
	-- FillSlots and not Render: Render also turns {spell:1234} into a texture
	-- for a FontString, and the aura needs that tag intact to pick its icon.
	--
	-- The colour codes come off because the aura matches a name against the raw
	-- line and colours it itself; leaving them in makes that match depend on
	-- where the codes happen to sit.
	local P = Okanvil.NotesParse
	if text ~= "" and P and P.FillSlots then
		-- Unescape FIRST. A note pasted out of MRT carries doubled pipes
		-- ("||cff..."), and stripping colour codes before collapsing them
		-- leaves a stray "|" in every coloured name -- so the aura matched
		-- its owner against "|Okanor|" and answered no to its own line.
		-- Render does this in the same order for the same reason.
		text = P.FillSlots(text:gsub("||", "|"))
			:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	end

	-- {room:} says where the note runs; the aura has no use for it. The line it
	-- sat on goes too, or the aura would count an empty first row.
	if text:find("{room:", 1, true) then
		text = ("\n" .. text):gsub("\n[ \t]*{room:[^}]*}[ \t]*\r?\n", "\n"):sub(2)
		text = text:gsub("{room:[^}]*}", "")
	end

	return text
end

function N.CurrentName()
	return db and db.selected or nil
end

-- Is the selected note the one for the room we are standing in?
--
-- 3.3.5a has no ENCOUNTER_START, so anything watching for a pull falls back to
-- "entered combat" -- which is also true for a dungeon trash pack, a duel, or a
-- mob on the way in. This is the question that separates those: the note only
-- belongs here if the room asked for it.
--
-- THE ROOM IS THE PROOF, not the instance type. A matched ZONE_NOTE entry says
-- this subzone is a place a note runs; nothing more is needed, and asking
-- IsInInstance() on top of it only adds a way to be wrong. It was wrong in the
-- worst direction: on this client the instance type reads "none" for a second
-- or two after zoning in, so standing in The Frost Queen's Lair with Sindragosa
-- selected was refused eleven times in one night -- the right note, the right
-- room, no timers.
--
-- The routes that do NOT name a room carry their own instance check instead
-- (see oneRoomRaid below), because there the choice of note is the only signal
-- and it needs the raid around it to mean anything.

function N.InNoteRoom()
	-- Off is off. The module table exists whether or not the module is enabled --
	-- the .toc always loads this file -- so an aura asking this question gets a
	-- real answer from a module the player has switched off unless we say no
	-- here. Without this, disabling Notes hid the tab and left the timers running.
	if Okanvil.ModuleActive and not Okanvil:ModuleActive(ADDON) then return false end

	-- The room names a note, and it is the one you have selected. This is the
	-- whole test, and it works the same in Icecrown and on a target dummy: add
	-- the subzone you practise in to ZONE_NOTE and a note written for it runs
	-- there by this very path. That is why there is no test mode -- a bypass
	-- that says yes everywhere is a bypass you forget to switch off, and then
	-- every trash pull runs a boss note.
	local here = N.NoteForHere()
	if here then
		return here == (db and db.selected)
	end

	-- A one-room raid has no subzone to ask. Trial of the Crusader is a single
	-- arena for five bosses, so the lookup above can never succeed there -- and
	-- returning false would mean the timers never start, however carefully the
	-- note was picked. Here the CHOICE is the signal: you selected it, you are
	-- standing in the raid it belongs to, that is as much as can be known.
	--
	-- Which is also why this one asks where it is and the zone route does not:
	-- with no room to vouch for it, the raid around it is the only thing left.
	-- ONE_ROOM_RAIDS is keyed by zone name, so being in that zone is already
	-- established by the time we get here.
	--
	-- The choice only counts in the raid it was written for. Vault of Archavon is
	-- one room too, and a ToC note still selected from last night is not a plan
	-- for Toravon: it has to belong to a raid whose zone this is.
	if N.IsOneRoomRaid and N.IsOneRoomRaid() then
		local raid = db and db.selected and N.RaidOfBoss(N.BossOf(db.selected))
		return raid ~= nil and N.InRaidZone(raid)
	end
	return false
end

-- The raid tab a boss is listed under, or nil for a note of your own.
function N.RaidOfBoss(boss)
	for _, raid in ipairs(RAIDS) do
		for _, b in ipairs(raid.bosses) do
			if b == boss then return raid end
		end
	end
	return nil
end

function N.InRaidZone(raid)
	local zone = GetZoneText()
	return zone ~= nil and (zone == raid.zone or zone == raid.altZone)
end

-- Fired when the live note changes -- a different boss, or an edit to the one
-- being shown. The name mirrors MRT's own event so an aura written against MRT
-- needs one word changed, not a rewrite.
function N.Broadcast()
	if WeakAuras and WeakAuras.ScanEvents then
		WeakAuras.ScanEvents("OKANVIL_NOTE_UPDATE")
	end
	-- Picking a different note changes whether the fight window belongs on
	-- screen, without any zone event firing.
	if Okanvil.NotesWindow and Okanvil.NotesWindow.ApplyVisibility then
		Okanvil.NotesWindow.ApplyVisibility()
	end
	-- Raiders running only the aura have no zone logic of their own: tell them
	-- which boss this is, or they read whichever note arrived last.
	if N.AnnounceSelected then N.AnnounceSelected() end
end

-- Every note we know about, for the size the page is showing: the twelve
-- encounters in pull order, then anything you added under a name of your own.
--
-- Returns KEYS -- "Sindragosa" on the 25 tab, "Sindragosa (10)" on the 10 --
-- while the list draws N.BossOf() of each, so both tabs read the same and the
-- size lives in the tab rather than in twelve note names.
-- Which raid tab the page is on. Follows the zone until you press a tab.
function N.ViewRaid()
	if db and db.viewRaid then return db.viewRaid end
	for _, raid in ipairs(RAIDS) do
		if N.InRaidZone(raid) then return raid.key end
	end
	return RAIDS[1].key
end

function N.SetViewRaid(key)
	if not db then return end
	db.viewRaid = key
	-- Land on something: the boss you were reading is in another raid now.
	local list = N.List()
	if list[1] then db.selected = list[1] end
	N.Broadcast()
	if N.Refresh then N.Refresh() end
end

function N.Raids() return RAIDS end

function N.List()
	local size = N.ViewSize()
	local heroic = N.ViewHeroic()
	local raidKey = N.ViewRaid()
	local bosses
	for _, raid in ipairs(RAIDS) do
		if raid.key == raidKey then bosses = raid.bosses break end
	end
	bosses = bosses or NOTE_ORDER

	local seen, out = {}, {}
	for _, n in ipairs(bosses) do
		local key = N.KeyFor(n, size, heroic)
		out[#out + 1] = key
		seen[key] = true
	end
	-- Notes of your own, under a name no raid lists. They belong to no tab, so
	-- they go on the LAST one -- dropping them entirely would make a note you
	-- wrote unreachable, which is worse than it sitting one tab further along.
	local isLastTab = (raidKey == RAIDS[#RAIDS].key)
	local known = {}
	for _, raid in ipairs(RAIDS) do
		for _, boss in ipairs(raid.bosses) do known[boss] = true end
	end

	local extra = {}
	for n in pairs((db and db.notes) or {}) do
		-- Matched on BOTH markers: a note written for the other difficulty is a
		-- different note, and listing it here would offer a plan whose anchors
		-- cannot fire at the difficulty this tab is showing.
		if not seen[n] and N.SizeOf(n) == size and N.IsHeroic(n) == heroic
			and isLastTab and not known[N.BossOf(n)] then
			extra[#extra + 1] = n
			seen[n] = true
		end
	end
	table.sort(extra)
	for _, n in ipairs(extra) do out[#out + 1] = n end
	return out
end

-- Raids that are ONE room for every boss in them. A subzone cannot tell those
-- encounters apart -- Trial of the Crusader is a single arena for all five --
-- so the zone maps to nothing and there is nothing to switch to.
--
-- Listing them matters: without this the zone lookup simply fails, the note
-- stays on whatever was last selected (an ICC one), and pulling Jaraxxus fires
-- Lord Marrowgar's timers.
local ONE_ROOM_RAIDS = {
	["Trial of the Crusader"] = true,
	["Trial of the Grand Crusader"] = true,
	["Onyxia's Lair"] = true,
	["Vault of Archavon"] = true,
	["The Obsidian Sanctum"] = true,
	["The Eye of Eternity"] = true,
}

-- ------------------------------------------------------------
-- Rooms named in the note itself: {room:The Spire}
--
-- ZONE_NOTE ships with the addon, so correcting it meant sending every raider a
-- new build. A room written into the note travels with the note, and notes
-- already reach the raid through Send.
--
-- A boss whose note names any room uses ONLY the rooms it names: the shipped
-- entries for that boss are dropped, which is how a room is taken away (the
-- whole lower spire reads "The Spire" on some cores, so Marrowgar's note fired
-- at the entrance). A room named by a note also outranks the shipped table's
-- claim on it for another boss.
--
-- Rebuilt at most once a second: the aura asks InNoteRoom constantly, and a note
-- edit a second late costs nothing.
-- ------------------------------------------------------------
local roomCache, roomCacheAt = nil, -1

local function customRooms()
	local now = GetTime()
	if roomCache and now - roomCacheAt < 1 then return roomCache end
	local rooms, owned = {}, {}
	for key, text in pairs((db and db.notes) or {}) do
		if type(text) == "string" and text:find("{room:", 1, true) then
			local boss = N.BossOf(key)
			for list in text:gmatch("{room:([^}]*)}") do
				for room in list:gmatch("[^,]+") do
					room = room:match("^%s*(.-)%s*$")
					if room ~= "" then
						rooms[room] = boss
						owned[boss] = true
					end
				end
			end
		end
	end
	roomCache = { rooms = rooms, owned = owned }
	roomCacheAt = now
	return roomCache
end

-- The note a room belongs to: the note's own {room:} first, then the shipped table.
local function noteForRoom(name)
	if not name or name == "" then return nil end
	local c = customRooms()
	if c.rooms[name] then return c.rooms[name] end
	local boss = ZONE_NOTE[name]
	if boss and not c.owned[boss] then return boss end
	return nil
end

-- The note for the room you are standing in, or nil outside a boss room.
function N.NoteForHere()
	-- Sized on the way out, so walking into a room on a 10 picks the 10-man note
	-- and the same step on a 25 picks the 25. One lookup, one place.
	local bySub = noteForRoom(GetSubZoneText())
	if bySub then return N.SizedName(bySub) end
	-- Halion's own zone reads through GetZoneText, not a subzone
	local byZone = noteForRoom(GetZoneText())
	if byZone then return N.SizedName(byZone) end
	-- No subzone to ask: let the target answer instead.
	local byTarget = N.NoteForTarget()
	if byTarget then return N.SizedName(byTarget) end
	return nil
end

-- Is this a raid where the subzone can never name the boss? Used to explain the
-- silence rather than leave the page looking broken.
function N.IsOneRoomRaid()
	local zone = GetZoneText()
	return (zone and ONE_ROOM_RAIDS[zone]) == true
end

-- ------------------------------------------------------------
-- One-room raids: the TARGET names the boss.
--
-- Trial of the Crusader is a single arena for five encounters, so walking in
-- cannot pick a note the way it does in Icecrown -- and picking by hand before
-- every pull is the thing nobody remembers to do at the moment it matters. What
-- IS unambiguous is what the raid is looking at: target Jaraxxus and there is
-- exactly one note that can mean.
--
-- OkanvilBossGroups already maps every NPC to its encounter for the loot module;
-- the names differ from the note names in two places, hence the aliases.
-- ------------------------------------------------------------
local BOSS_NOTE_ALIAS = {
	["Twin Val'kyr"] = "Val'kyr Twins",
	["Anub'Arak"]    = "Anub'arak",
}

function N.NoteForTarget()
	if not N.IsOneRoomRaid() then return nil end
	local groups = _G.OkanvilBossGroups
	if not groups then return nil end
	-- Your target first, then the target of whoever you are following: a healer
	-- watching the tank is looking at the boss just as surely as the tank is.
	for _, unit in ipairs({ "target", "targettarget", "focus" }) do
		if UnitExists(unit) and not UnitIsPlayer(unit) then
			local name = UnitName(unit)
			local enc = name and groups[name]
			if enc then return BOSS_NOTE_ALIAS[enc] or enc end
		end
	end
	return nil
end

-- ------------------------------------------------------------
-- Zone watching
--
-- Zone events arrive in bursts (and fire mid-pull), so this throttles and,
-- crucially, never switches the note while you are in combat -- changing what
-- someone is reading mid-fight is worse than being one room behind.
-- ------------------------------------------------------------
local watcher = CreateFrame("Frame")
local pendingZone = false

local function applyZone()
	if not (db and db.autoZone) then return end

	local want = N.NoteForHere()
	if not want or want == db.selected then return end

	-- Never swap the plan mid-pull -- EXCEPT when the note is wrong for the boss
	-- being fought.
	--
	-- In Icecrown a room change during combat is you running somewhere, and the
	-- note must hold. In a one-room raid the target is what names the boss, and
	-- you only ever target it once the pull is under way: holding off until
	-- combat drops would mean the note arrives after the fight it was for. So a
	-- target-driven answer is allowed to land in combat, and only that.
	if InCombatLockdown and InCombatLockdown() then
		if not N.NoteForTarget() then
			pendingZone = true
			return
		end
	end

	db.selected = want
	pendingZone = false
	N.Broadcast()
	if F and F.panel and F.panel:IsShown() then N.Refresh() end
end

watcher:RegisterEvent("ZONE_CHANGED")
watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
watcher:RegisterEvent("ZONE_CHANGED_INDOORS")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
-- In a one-room raid the target is the only thing that names the boss, and it
-- changes without any zone event firing.
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")

watcher:SetScript("OnEvent", function(_, event)
	if not db then return end
	-- Module off means no auto-switching: walking into a boss's room should not
	-- quietly change which note is live for a module you turned off.
	if Okanvil.ModuleActive and not Okanvil:ModuleActive(ADDON) then return end
	if event == "PLAYER_REGEN_ENABLED" then
		-- left combat: apply whatever room change we held back
		if pendingZone then applyZone() end
		return
	end
	if event == "PLAYER_TARGET_CHANGED" then
		-- This fires on every click of every mob. Only a one-room raid reads the
		-- target at all, so everywhere else it is answered and dropped here
		-- rather than walking the zone tables hundreds of times a fight.
		if not N.IsOneRoomRaid() then return end
	end
	applyZone()
end)

-- ------------------------------------------------------------
-- UI
-- ------------------------------------------------------------

-- The syntax crib. A reference this long does not belong in a tooltip -- it
-- grew past the top of the screen and covered the bar it was anchored to. It
-- gets its own panel, laid out as code on the left and what it means on the
-- right, which is how you actually read a format table.
--
--   { code, meaning }  or  a string = a section heading  or  false = a gap
local HELP_ROWS = {
	"WHEN -- what starts the countdown",
	{ "{time:0:52}",              "52s after the pull" },
	{ "{time:0:22,SAA:74792:1}",  "22s after that aura is first applied" },
	{ "{time:0:21,SCC:72905:3}",  "21s after the 3rd cast of that spell" },
	false,
	{ "SCS",  "cast start" },
	{ "SCC",  "cast done" },
	{ "SAA",  "aura on" },
	{ "SAR",  "aura off" },
	{ "",     "The last number is which occurrence -- 1 is the first." },
	false,
	"WHO -- who the line is for",
	{ "Okanor",  "Just the name. A line shows for whoever it names," },
	{ "",        "so spelling matters." },
	{ "",        "The aura colours names by class during a fight; the" },
	{ "",        "codes below are for colouring one HERE, in the note." },
	false,
	"CLASS COLOURS -- |cffRRGGBB name|r",
	{ "|cffc41f3b", "Death Knight" },
	{ "|cffff7d0a", "Druid" },
	{ "|cffabd473", "Hunter" },
	{ "|cff69ccf0", "Mage" },
	{ "|cfff58cba", "Paladin" },
	{ "|cffffffff", "Priest" },
	{ "|cfffff569", "Rogue" },
	{ "|cff0070de", "Shaman" },
	{ "|cff9482c9", "Warlock" },
	{ "|cffc79c6e", "Warrior" },
	{ "", "Always close with |r, or the colour bleeds into the" },
	{ "", "rest of the line." },
	false,
	"EXTRAS",
	{ "{spell:64205}",  "that spell's icon, inline" },
	{ "{skull}",        "raid marker -- also cross, square, moon," },
	{ "",               "star, circle, diamond, triangle" },
	{ "",               "A line with no {time:} is plain text: markers," },
	{ "",               "reminders, headers." },
	{ "{room:The Spire}", "the room this note runs in (never shown)." },
	{ "",               "Comma for several; replaces the built-in rooms" },
	{ "",               "for this boss. {room:none} = no room at all." },
	{ "",               "The room you stand in shows at the top." },
}

local HELP_EXAMPLE = "{time:0:58}Bone Storm 1 - Okanor {spell:64205}"

-- Built once, on first ask. Nobody opens this every session, so paying for the
-- frames up front would be frames nobody looks at.
local helpPanel
-- Park the help beside the addon window rather than over it.
--
-- It is a reference you read WHILE typing a line, so it has to sit where the
-- note still shows. Centred, it covered the thing it was explaining and had to
-- be dragged away before it was any use.
--
-- Anchored, not parented: the panel stays its own window (closable, draggable
-- if you want it somewhere else), it just starts in the useful place.
local function parkHelp(f)
	local shell = _G.Okanvil_Window
	f:ClearAllPoints()
	if shell and shell:IsShown() then
		f:SetPoint("TOPLEFT", shell, "TOPRIGHT", 8, 0)
	else
		f:SetPoint("CENTER")
	end
end

local function showHelp()
	if helpPanel then
		-- Kept, not rebuilt, so Popup() never runs again on this path: say
		-- so ourselves, or the panel this one replaces stays underneath it.
		if Okanvil.ClosePopup then Okanvil:ClosePopup(helpPanel) end
		if Okanvil.SetPopup then Okanvil:SetPopup(helpPanel) end
		parkHelp(helpPanel)
		helpPanel:Show()
		helpPanel:Raise()
		return
	end

	local f = Okanvil:Popup("Writing a note line")
	-- ESC closes it, like the main window.
	--
	-- UISpecialFrames is a list of GLOBAL NAMES, and Popup builds anonymous
	-- frames, so the panel has to be given one before Blizzard can find it. A
	-- help panel left open behind the addon window -- with no way to dismiss it
	-- except its own X -- is exactly what ESC is for.
	if not _G.Okanvil_NotesHelp then
		_G.Okanvil_NotesHelp = f
		tinsert(UISpecialFrames, "Okanvil_NotesHelp")

		-- Closing the addon closes this with it.
		--
		-- The panel is parented to UIParent, not to the window it explains --
		-- it has to be, to sit beside it rather than inside it -- so hiding the
		-- window leaves it floating over the game with nothing it belongs to.
		-- Hooking the window's own OnHide covers every way it closes: the X,
		-- the collapse to the puck, Escape, a DBM pull.
		local shell = _G.Okanvil_Window
		if shell and not shell._okNotesHelpHooked then
			shell._okNotesHelpHooked = true
			shell:HookScript("OnHide", function()
				if helpPanel then helpPanel:Hide() end
			end)
		end
	end
	-- Wider than it was: the rows are a size up now, and at 430 every second
	-- explanation wrapped onto a line of its own.
	local PANEL_W = 500
	f:SetWidth(PANEL_W)
	helpPanel = f
	parkHelp(f)

	-- The code column has to fit "{time:0:22,SAA:74792:1}" at 14px without
	-- running into the meaning beside it.
	local CODE_X, MEAN_X = 14, 210
	local y = -34

	for _, row in ipairs(HELP_ROWS) do
		if row == false then
			y = y - 10
		elseif type(row) == "string" then
			local h = W.Text(f, row, "head", "accent")
			h:SetPoint("TOPLEFT", CODE_X, y)
			y = y - 20
		else
			local code, meaning = row[1], row[2]
			-- A colour code cannot be PRINTED as itself: "|cfff58cba" is an
			-- instruction, so a FontString eats it and leaves the column blank --
			-- which is the one column you came here to copy. Doubling the pipe
			-- escapes it, and the swatch moves to the right-hand column so you
			-- get both: the letters to type, and the colour they produce.
			local hex = code:match("^|cff(%x%x%x%x%x%x)$")
			if code ~= "" then
				local c = W.Text(f, hex and ("|" .. code) or code, "note")
				c:SetPoint("TOPLEFT", CODE_X, y)
				-- Monospace so the braces line up down the column; this is the
				-- half you copy, and it should read as code.
				c:SetFont("Fonts\\ARIALN.TTF", 14)
			end
			local m = W.Text(f, hex and ("|cff" .. hex .. meaning .. "|r") or meaning,
				"note", hex and nil or "dim")
			m:SetPoint("TOPLEFT", MEAN_X, y)
			m:SetWidth(PANEL_W - MEAN_X - 14)
			m:SetJustifyH("LEFT")
			-- One size up from the page's note text. This panel is read at arm's
			-- length while typing into the box beside it, not skimmed in passing.
			m:SetFont(Okanvil:Font(), 14)
			-- Step by the height the text ACTUALLY took. A fixed 17 assumed one
			-- line, so every explanation that wrapped to two stole a row from
			-- whatever came after -- and the last example fell off the bottom of a
			-- panel whose height was hard-coded.
			y = y - math.max(17, (m:GetStringHeight() or 0) + 5)
		end
	end

	-- The example, rendered the way the note will actually look -- icon and all.
	-- Seeing it resolved is worth more than another line of prose about it.
	y = y - 12
	local exHead = W.Text(f, "LOOKS LIKE", "head", "accent")
	exHead:SetPoint("TOPLEFT", CODE_X, y)
	y = y - 20

	local raw = W.Text(f, HELP_EXAMPLE, "note", "dim")
	raw:SetPoint("TOPLEFT", CODE_X, y)
	raw:SetFont("Fonts\\ARIALN.TTF", 12)
	y = y - 20

	local P = Okanvil.NotesParse
	local shown = W.Text(f, P and P.Render(HELP_EXAMPLE) or HELP_EXAMPLE, "body")
	shown:SetPoint("TOPLEFT", CODE_X, y)

	-- Size to what was laid out, rather than to a number typed in once. The
	-- rendered example is the last thing on the panel and the first to be cut
	-- off, which is exactly the line the reader needs to see.
	f:SetHeight(math.abs(y) + (shown:GetStringHeight() or 14) + 18)
end

-- ------------------------------------------------------------
-- What the bosses were SEEN casting, one library per raid.
--
-- The ID Finder answers "does this spell exist", which is not the question a
-- note needs. Every difficulty's variant ships in the client's spell table, so
-- a lookup happily returns a name for an id this core's boss never casts --
-- and a line anchored to it waits for ever, looking exactly like a bug.
--
-- This panel answers the real question: what did we WATCH it cast, in the raid
-- whose tab is open. Filled in the background by NotesParse on every raid pull
-- -- a wipe at 30% still records everything up to 30%.
-- ------------------------------------------------------------
local seenPanel
local seenShows      -- "<raid key>|<boss>" the open panel was drawn for

local SEEN_W, SEEN_MAX_H = 460, 620

local function viewRaidEntry()
	local key = N.ViewRaid()
	for _, raid in ipairs(RAIDS) do
		if raid.key == key then return raid end
	end
	return RAIDS[1]
end

-- Does this caster belong to the selected note? Either name may hold the
-- other: "Rotface & Festergut" holds "Rotface", "Blood-Queen Lana'thel" holds
-- "Queen Lana'thel".
local function belongsTo(src, boss)
	if not (src and boss and boss ~= "") then return false end
	local s, b = src:lower(), boss:lower()
	return s:find(b, 1, true) ~= nil or b:find(s, 1, true) ~= nil
end

local function viewDiff()
	return N.ViewSize() .. (N.ViewHeroic() and "H" or "N")
end

local function diffLabel(diff)
	local size, hc = diff:match("^(%d+)([NH])$")
	if not size then return "difficulty unknown" end
	return size .. " " .. (hc == "H" and "Heroic" or "Normal")
end

local function showSeen()
	local P = Okanvil.NotesParse
	if not (P and P.SourcesSeen) then return end

	if seenPanel then
		seenPanel:Hide()
		seenPanel = nil
	end

	local raid = viewRaidEntry()
	local diff = viewDiff()
	local boss = N.BossOf(db and db.selected) or ""
	seenShows = raid.key .. "|" .. diff .. "|" .. boss

	local f = Okanvil:Popup(("Spells seen cast -- %s %s"):format(raid.label, diffLabel(diff)))
	if not _G.Okanvil_NotesSeen then
		_G.Okanvil_NotesSeen = f
		tinsert(UISpecialFrames, "Okanvil_NotesSeen")
		local shell = _G.Okanvil_Window
		if shell and not shell._okNotesSeenHooked then
			shell._okNotesSeenHooked = true
			shell:HookScript("OnHide", function()
				if seenPanel then seenPanel:Hide() end
			end)
		end
	end

	f:SetWidth(SEEN_W)
	seenPanel = f
	if parkHelp then parkHelp(f) end

	local X = 14

	-- The selected note's boss first, because that is the note being written;
	-- the rest of the raid follows busiest first, so the trash sinks.
	local function ordered(d)
		local first, rest = {}, {}
		for _, src in ipairs(P.SourcesSeen(raid.zone, d)) do
			if belongsTo(src, boss) then first[#first + 1] = src else rest[#rest + 1] = src end
		end
		for _, src in ipairs(rest) do first[#first + 1] = src end
		return first
	end
	local sources = ordered(diff)
	-- Records whose difficulty was never known go last, under their own label:
	-- they are real ids, just not proven to be THIS difficulty's.
	local unknown = ordered(P.UNKNOWN_DIFF or "?")

	if #sources == 0 and #unknown == 0 then
		local none = W.Text(f, ("Nothing recorded for %s %s yet. Pull a boss there"
			.. " -- it records by itself, once per boss and difficulty."):format(
				raid.zone, diffLabel(diff)),
			"note", "dim")
		none:SetPoint("TOPLEFT", X, -34)
		none:SetWidth(SEEN_W - X * 2)
		none:SetJustifyH("LEFT")
		f:SetHeight(110)
		return
	end

	local sf = CreateFrame("ScrollFrame", nil, f)
	sf:SetPoint("TOPLEFT", 0, -30)
	sf:SetPoint("BOTTOMRIGHT", -10, 8)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(SEEN_W - 10, 1)
	sf:SetScrollChild(child)

	local y = -4

	local function drawSource(d, src)
		local rows = P.SpellsSeen(raid.zone, d, src)
		if #rows == 0 then return end

		local h = W.Text(child, src:upper(), "head", "accent")
		h:SetPoint("TOPLEFT", X, y)

		-- Complete once it was seen dying: later kills leave it alone, and
		-- "redo" throws it away so the next pull records it again.
		local killed = P.KilledAt(raid.zone, d, src)
		local state = W.Text(child, killed
			and ("|cff7cfc8akilled|r |cff6f7176%s|r"):format(date("%d %b", killed))
			or "|cffe0b860recording|r", "note")
		state:SetPoint("LEFT", h, "RIGHT", 8, 0)

		local redo = W.Button(child, "redo")
		redo:SetSize(40, 16)
		redo:SetPoint("TOPRIGHT", child, "TOPRIGHT", -8, y + 1)
		redo:Tooltip("Forget these ids and record this boss again on the next pull.")
		redo:SetScript("OnClick", function()
			P.ResetSource(raid.zone, d, src)
			showSeen()
		end)
		y = y - 20

		for i = 1, #rows do
			local r = rows[i]
			-- Written the way it goes INTO a note, so it can be read straight
			-- across into the editor rather than reassembled by hand.
			local code = W.Text(child, ("%s:%d"):format(r.prefix or "?", r.id or 0), "note")
			code:SetPoint("TOPLEFT", X, y)
			code:SetFont("Fonts\\ARIALN.TTF", 13)

			local nm = W.Text(child, ("%s  |cff6f7176x%d|r"):format(r.name or "?", r.n or 0),
				"note", "dim")
			nm:SetPoint("TOPLEFT", X + 110, y)
			nm:SetWidth(SEEN_W - X - 134)
			nm:SetJustifyH("LEFT")
			y = y - 17
		end
		y = y - 10
	end

	for _, src in ipairs(sources) do drawSource(diff, src) end

	if #unknown > 0 then
		local sep = W.Text(child, "DIFFICULTY UNKNOWN", "note", "dim")
		sep:SetPoint("TOPLEFT", X, y)
		y = y - 20
		for _, src in ipairs(unknown) do drawSource(P.UNKNOWN_DIFF or "?", src) end
	end

	local contentH = math.abs(y)
	child:SetHeight(contentH)
	local viewH = math.min(contentH, SEEN_MAX_H - 38)
	f:SetHeight(viewH + 38)

	local overflow = contentH - viewH
	if overflow > 0 then
		local sb = CreateFrame("Slider", nil, f)
		sb:SetPoint("TOPRIGHT", -4, -30); sb:SetPoint("BOTTOMRIGHT", -4, 8); sb:SetWidth(4)
		sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
		local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetSize(4, 30)
		do local a = Okanvil.Colors.accent; th:SetVertexColor(a[1], a[2], a[3], 1) end
		sb:SetThumbTexture(th)
		sb:SetMinMaxValues(0, overflow)
		sb:SetValue(0)
		sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
		sf:EnableMouseWheel(true)
		sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 40) end)
	end
end

-- Follows the page: switching raid, size, difficulty or boss redraws an open
-- panel, so it never shows one raid's ids under another raid's note.
local function refreshSeen()
	if not (seenPanel and seenPanel:IsShown()) then return end
	local want = viewRaidEntry().key .. "|" .. viewDiff() .. "|"
		.. (N.BossOf(db and db.selected) or "")
	if want ~= seenShows then showSeen() end
end

-- Roughly 30/70 across the content panel.
--
-- The list holds names like "Deathbringer Saurfang (10) (HC)" and was
-- clipping them to "Deathbringer Sa..."; the note beside it is a column of
-- short timed lines that never needed the width it was given.
local LIST_W = 260
local ROW_H = 34

local function listRow(i)
	local r = F.rows[i]
	if r then return r end
	r = W.Frame(F.listChild, "bare")
	r:SetHeight(ROW_H)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 2))
	r:SetPoint("TOPRIGHT", 0, -(i - 1) * (ROW_H + 2))

	r.sel = r:CreateTexture(nil, "BACKGROUND")
	r.sel:SetAllPoints(); r.sel:SetTexture(FLAT)
	local a = Okanvil.Colors.accent
	r.sel:SetVertexColor(a[1], a[2], a[3], 0.16)
	r.sel:Hide()

	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(); hl:SetTexture(FLAT)
	hl:SetVertexColor(1, 1, 1, 0.05)

	-- Two lines: the boss, then who last wrote the note.
	--
	-- The credit used to be a word squeezed against the right edge, which cost
	-- the name the room it needed -- "Deathbringer Sa..." -- and said "edited"
	-- without saying by whom. Underneath it fits, and it can say the name.
	-- The forge look's row: the boss, the note's first line under it, and a
	-- status chip on the right (LIVE / READY / EMPTY). Who last edited it is in
	-- the row's tooltip.
	r.chip = CreateFrame("Frame", nil, r)
	r.chip:SetHeight(16); r.chip:SetPoint("RIGHT", -6, 0)
	r.chip:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
	r.chip.text = W.Text(r.chip, "", "note")
	r.chip.text:SetPoint("CENTER", 0, 0)

	r.name = W.Text(r, "", "body")
	r.name:SetPoint("TOPLEFT", 7, -4)
	r.name:SetPoint("RIGHT", r.chip, "LEFT", -6, 0)
	r.name:SetJustifyH("LEFT")
	if r.name.SetWordWrap then r.name:SetWordWrap(false) end

	r.dot = W.Text(r, "", "note", "dim")
	r.dot:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
	r.dot:SetPoint("RIGHT", r.chip, "LEFT", -6, 0)
	r.dot:SetJustifyH("LEFT")
	if r.dot.SetWordWrap then r.dot:SetWordWrap(false) end

	local rule = r:CreateTexture(nil, "BORDER")
	rule:SetTexture(FLAT); rule:SetVertexColor(1, 1, 1, 0.06)
	rule:SetHeight(1); rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
	r:SetScript("OnEnter", function(self)
		if not self._tipText then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self._tipText, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)

	r:EnableMouse(true)
	r:SetScript("OnMouseUp", function(self)
		if not self._name then return end
		N.Select(self._name)
		N.Refresh()
	end)
	F.rows[i] = r
	return r
end

-- Make a note the live one. Commits whatever is half-typed first, so switching
-- notes never saves your text into the one you just left.
function N.Select(name)
	if not name or name == db.selected then return end
	N.Commit()
	db.selected = name
	N.Broadcast()
end

-- ------------------------------------------------------------
-- Adding and removing notes
--
-- The list is the twelve shipped encounters plus whatever you add. Both halves
-- were read-only from the UI: a note under a name of your own could be created
-- by hand in Notes-Data.lua and never removed from the game.
-- ------------------------------------------------------------

-- Ask for a name and select the new note. A name that already exists just
-- selects it rather than quietly wiping what is there.
function N.PromptNew()
	Okanvil:Prompt("New note", "Boss or fight name", "", function(name)
		name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" then return end
		-- Keyed for the TAB YOU ARE ON, not the bare name.
		--
		-- The typed name was stored as-is, which is the 25-normal key -- so a note
		-- created while looking at 10 heroic was written to 25 normal and vanished
		-- from the list the moment it was made.
		local key = N.KeyFor(name, N.ViewSize(), N.ViewHeroic())
		local existing = db and db.notes and db.notes[key]
		if existing ~= nil or N.HasPacked(key) then
			Okanvil:Print(("|cff8a8d93A note for|r %s |cff8a8d93already exists -- opening it.|r"):format(key))
		else
			db.notes = db.notes or {}
			db.notes[key] = ""
			if N.Touch then N.Touch(key) end
		end
		N.Select(key)
		N.Refresh()
	end)
end

-- Remove the selected note. A note the pack ships is not deleted -- there is
-- nothing to delete, the shipped text is in the addon -- so clearing yours puts
-- the original back, and the wording says which of the two is happening.
function N.PromptDelete()
	local name = db and db.selected
	if not name then
		Okanvil:Print("|cff8a8d93Pick a note first.|r")
		return
	end
	local packed = N.HasPacked(name)
	-- Not N.IsOwn: that reads an empty note as "not yours", so a shipped note you
	-- had cleared could never be reset, and neither could an empty leftover.
	-- Holding a row in db.notes at all is what makes it yours to remove.
	local own = db.notes and db.notes[name] ~= nil
	if packed and not own then
		Okanvil:Print(("|cff8a8d93%s|r is a note that ships with the addon -- nothing of yours to remove."):format(name))
		return
	end
	local msg = packed
		and ("Reset |cffffd200%s|r to the note that ships with the addon?\n\nYour version is lost."):format(name)
		or ("Delete the |cffffd200%s|r note?\n\nThis cannot be undone."):format(name)
	Okanvil:Confirm(msg, packed and "Reset" or "Delete", function()
		-- Forget the editor's note FIRST. Moving the selection commits whatever is
		-- in the edit box back into the note it came from -- so deleting one, then
		-- selecting another, wrote the deleted note straight back as an empty
		-- entry: gone from the list, still selected, and refusing to be deleted
		-- again because an empty note does not count as one of yours.
		if F then F.editing = nil end
		db.notes[name] = nil
		if db.stamps then db.stamps[name] = nil end
		-- The text is gone, so the credit for it goes too. Left behind, it would
		-- put somebody's name against the shipped note that takes its place.
		if db.authors then db.authors[name] = nil end
		if not packed then
			-- The list no longer has it, so the selection has to move or the page
			-- sits on a note that is not there any more.
			local list = N.List()
			db.selected = list[1]
		end
		N.Refresh()
		N.Broadcast()
		Okanvil:Print(packed
			and ("Reset |cffffd200%s|r to the shipped note."):format(name)
			or ("Deleted the |cffffd200%s|r note."):format(name))
	end)
end

-- Push the edit box back into the note it belongs to. Called before the
-- selection changes and when the box loses focus, so nothing is typed into
-- one note and saved into another.
function N.Commit()
	if not (F and F.edit and F.editing) then return end
	N.Set(F.editing, F.edit.edit:GetText() or "")
end

local function build(panel)
	if F then return end
	F = { rows = {} }
	F.panel = panel

	local dash = W.Dashboard(panel, {
		title = "Notes",
		subtitle = "Switch on as you walk into each room",
		icon = (Okanvil.ICONS and Okanvil.ICONS.notes) or "Interface\\Icons\\INV_Scroll_03",
		pills = true,
		drawerWidth = 0,
		footerHeight = 0,
		-- No button for the fight window. It follows the room: walk into one a
		-- note is mapped to and it appears, walk out and it goes. A button meant
		-- the window could also be switched on by hand, and a hand-opened window
		-- was exempt from the room check -- so it sat on screen through cities
		-- and dungeons, looking like the note had triggered there.
		--
		-- Send and the audit are officer work: a raider cannot send (the sync
		-- refuses them) and has nobody to audit, so showing the buttons would
		-- only promise something that never happens.
		secondaryText = function() return "Send to raid" end,
		secondaryWidth = 100,
		-- CanEdit is now true outside a guild (your notes are yours alone there),
		-- but sending needs an officer AND a guild to send to -- so these two ask
		-- the stricter question rather than riding on the edit gate.
		secondaryShown = function() return N.CanShare and N.CanShare() end,
		onSecondary = function()
			if N.SendNow then N.SendNow() end
			-- Repaint immediately: the header shows the send tally, and without
			-- this it only updated when the first confirmation happened to
			-- arrive -- so a send nobody answered looked like nothing happened.
			if F and F.dash then F.dash:Refresh() end
		end,

		tertiaryText = function() return "Who has them?" end,
		tertiaryWidth = 110,
		tertiaryTip = "Ask the group to report back. Anyone who does not answer\nis not running Okanvil -- which is what you want to know\nbefore a pull, not after one.",
		tertiaryShown = function() return N.CanShare and N.CanShare() end,
		onTertiary = function() N.RunAudit() end,

		-- After a Send, the header carries the tally: how many notes went and
		-- how many people confirmed. Pressing the button only proves the
		-- messages left this client; the second number is the one that matters.
		statusText = function()
			if N.LastSend then
				local sent, got, ago = N.LastSend()
				if sent and ago and ago < 120 then
					local c = (got > 0) and "|cff7cfc8a" or "|cffff5555"
					return ("|cff6f7176Sent %d -- |r%s%d confirmed|r"):format(sent, c, got)
				end
			end
			return N.auditLine or ""
		end,
		-- Before the first pill is built, not after: BuildPage puts the Follow
		-- the room switch on the toolbar, and the toolbar is only reachable
		-- through the dashboard this hands over.
		onReady = function(d) F.dash = d end,

		tabs = {
			{ key = "notes", label = "Notes", height = 420, fill = true,
			  build = function(p) N.BuildPage(p) end },
			-- The fight window's settings live beside the notes they display,
			-- not in the addon's global Settings page.
			{ key = "window", label = "Fight window", height = 300,
			  build = function(p) N.BuildWindowPage(p) end },
		},
	})
	F.dash = dash
end

function N.BuildPage(p)
	-- ---- top strip: where you are, and the auto-switch toggle ----
	-- Where you are, at the FOOT. It is status, not a control: reading it is how
	-- you check the page followed you into the room, which is a glance after the
	-- fact rather than something you act on -- and at the top it cost the list a
	-- row it needed more.
	F.here = W.Text(p, "", "note", "dim")
	-- Anchored to the count rather than to the panel: the two are one status
	-- line, and pinning both to the same left edge stacked them on each other.
	-- Placed after F.count is built, at the end of BuildPage.

	-- On the TAB ROW, at the right end, not down in the page foot.
	--
	-- It is a page-wide switch -- it decides what the whole page shows, the same
	-- way the Notes/Fight window pills do -- so it belongs on the row those pills
	-- sit on, opposite them. In the foot it was a fourth thing competing for a
	-- strip that already held the count, the room and the syntax hint, and it
	-- cost the note card a row it wanted more.
	--
	-- Parented to the dashboard's toolbar, which is free at its right end: this
	-- page has no drawer, so nothing else claims that corner.
	local toolbar = (F.dash and F.dash.toolbar) or p
	F.auto = W.Check(toolbar, "Follow the room",
		function() return db.autoZone end,
		function(v)
			db.autoZone = v and true or false
			if v then applyZone() end
			N.Refresh()
		end)
	-- The checkbox label sits to the RIGHT of the 18px box, so the whole widget
	-- is anchored by its box and the words run on past it -- anchoring the box
	-- itself to the right edge would push the text off the panel. Measured and
	-- offset instead, so the LABEL ends at the edge.
	if toolbar == p then
		F.auto:SetPoint("TOPRIGHT", -10, -6)
	else
		-- +6 is the gap W.Check leaves between the box and its label.
		local lw = (F.auto.text and F.auto.text:GetStringWidth()) or 92
		F.auto:SetPoint("RIGHT", toolbar, "RIGHT", -(lw + 6), 0)
	end
	F.auto:Tooltip("Switch to the boss's note when you walk into their room.\nNever switches while you are in combat.")

	-- ---- left: the note list ----
	-- The card stops short of the bottom to leave room for the two buttons under
	-- it. Adding and deleting a note was only possible by editing Notes-Data.lua,
	-- so a note you made for a test -- or for a boss the pack does not ship --
	-- could be created but never removed.
	-- 10 / 25 above the list.
	--
	-- The size lives HERE and not in the note names: both tabs list the same
	-- twelve bosses, so "Sindragosa" reads the same on either, and picking a tab
	-- is picking which plan those names point at. Naming the notes instead --
	-- "Sindragosa 10", "Sindragosa 25" -- doubles a list you have to read under
	-- time pressure and puts the two plans for one boss in different places.
	local TAB_H = 22

	-- Raid and size sit over the LIST they filter, not in the page header.
	-- They choose which notes the column below shows, so they belong to that
	-- column -- in the header they were a long way from what they changed, and
	-- the header has its own job (the note being sent, the send tally).
	--
	-- One row, because they fit: the raid pills are the wide ones and the two
	-- sizes are narrow, so the whole filter is one band over the list rather
	-- than two bands eating the page.
	-- TWO rows, size over raid, each spanning the full width of the list they
	-- filter. One cramped row of 40px pills left two thirds of the band empty
	-- while the pills themselves were too small to hit comfortably -- so both
	-- rows now divide LIST_W between their buttons and grow to fill it.
	--
	-- Size on TOP because it is the coarser question: which raid you are
	-- reading for is asked once a night, which boss changes constantly.
	--
	-- The band starts at the top of the page. The note's own buttons share the
	-- boss name's row on the right, so nothing sits above this -- a strip left
	-- clear for them cost both columns a row and showed nothing.
	local TAB_Y = -8
	-- ONE tab row, raid and size together (ICC 10, ICC 25, ToC 10 ...), across the
	-- top of the page -- the forge look's tabs. Two stacked rows of big buttons
	-- asked the same question twice; one tab names the exact plan list you get.
	-- The note's own buttons (ids, ?, Edit, Clear) share this row on the right.
	local TABROW_H = 24
	-- Where both cards start: under the tab row. One number, so the list and the
	-- note cannot drift apart.
	local CARD_Y = TAB_Y - TABROW_H - 12
	F.comboTabs = {}
	do
		local x = 6
		for _, raid in ipairs(N.Raids()) do
			for _, size in ipairs({ 10, 25 }) do
				local b = W.Button(p, raid.label .. " " .. size, "tab")
				local tw = (b.text and b.text:GetStringWidth() or 50) + 18
				b:SetSize(math.max(54, tw), TABROW_H)
				b:SetPoint("TOPLEFT", x, TAB_Y)
				b._raid, b._size = raid.key, size
				b:Tooltip(raid.zone .. " -- " .. size .. " man")
				b:SetScript("OnClick", function()
					N.SetViewRaid(raid.key)
					N.SetViewSize(size)
				end)
				F.comboTabs[#F.comboTabs + 1] = b
				x = x + b:GetWidth() + 6
			end
		end
	end
	local tabRule = p:CreateTexture(nil, "ARTWORK")
	tabRule:SetTexture(FLAT)
	do local bc = Okanvil.Colors.border; tabRule:SetVertexColor(bc[1], bc[2], bc[3], 1) end
	tabRule:SetHeight(1)
	tabRule:SetPoint("TOPLEFT", 6, TAB_Y - TABROW_H - 1)
	tabRule:SetPoint("TOPRIGHT", -6, TAB_Y - TABROW_H - 1)

	local lcard = W.Frame(p, "soft")
	-- Below BOTH filter rows now, measured from them rather than by a constant:
	-- the band is two rows of ROW_H plus the gap between them.
	-- The buttons hang BELOW the card, so the card has to stop high enough to
	-- leave room for them: their 22px plus the 6px gap, over the same 30px foot
	-- the note card on the right uses. A flat 40 here was two things at once --
	-- too high to reach the foot, too low to clear the buttons -- so the list
	-- was clipped mid-row and a band of empty panel sat underneath it.
	local BTN_H, BTN_GAP, FOOT = 22, 6, 30
	lcard:SetPoint("TOPLEFT", 6, CARD_Y)
	lcard:SetPoint("BOTTOMLEFT", 6, FOOT + BTN_H + BTN_GAP)
	lcard:SetWidth(LIST_W)

	F.addBtn = W.Button(p, "+ New", "primary")
	F.addBtn:SetSize(LIST_W / 2 - 3, BTN_H)
	F.addBtn:SetPoint("TOPLEFT", lcard, "BOTTOMLEFT", 0, -BTN_GAP)
	F.addBtn:SetScript("OnClick", function() N.PromptNew() end)

	F.delBtn = W.Button(p, "Delete", "danger")
	F.delBtn:SetSize(LIST_W / 2 - 3, BTN_H)
	F.delBtn:SetPoint("TOPRIGHT", lcard, "BOTTOMRIGHT", 0, -BTN_GAP)
	F.delBtn:SetScript("OnClick", function() N.PromptDelete() end)

	local lsf = CreateFrame("ScrollFrame", nil, lcard)
	lsf:SetPoint("TOPLEFT", 3, -3); lsf:SetPoint("BOTTOMRIGHT", -9, 3)
	local lchild = CreateFrame("Frame", nil, lsf); lchild:SetSize(10, 1)
	lsf:SetScrollChild(lchild)
	local lsb = CreateFrame("Slider", nil, lcard)
	lsb:SetPoint("TOPRIGHT", -3, -3); lsb:SetPoint("BOTTOMRIGHT", -3, 3); lsb:SetWidth(4)
	lsb:SetOrientation("VERTICAL"); lsb:SetValueStep(1)
	local lth = lsb:CreateTexture(nil, "OVERLAY"); lth:SetTexture(FLAT); lth:SetSize(4, 30)
	do local a = Okanvil.Colors.accent; lth:SetVertexColor(a[1], a[2], a[3], 1) end
	lsb:SetThumbTexture(lth)
	lsb:SetScript("OnValueChanged", function(_, v) lsf:SetVerticalScroll(v) end)
	lsf:EnableMouseWheel(true)
	lsf:SetScript("OnMouseWheel", function(_, d) lsb:SetValue(lsb:GetValue() - d * 30) end)
	lsf:SetScript("OnSizeChanged", function() lchild:SetWidth(lsf:GetWidth()) end)
	F.listChild, F.listSF, F.listSB = lchild, lsf, lsb

	-- ---- right: the note itself ----
	local RX = 6 + LIST_W + 10
	F.title = W.Text(p, "", "head", "accent")
	-- On the SIZE row's line, not centred in the band: the boss name and the
	-- note's own buttons make one header row across the top of the right
	-- column, level with the first row of filters on the left. Centred, it sat
	-- between the two filter rows and read as a caption for neither.
	F.title:SetPoint("TOPLEFT", RX, CARD_Y - 2)

	-- Normal / Heroic, on the NOTE rather than on the page.
	--
	-- Here and not up with the size pills because it belongs to the plan, not to
	-- the browsing: the boss stays selected and its place in the list does not
	-- move, only which of its two versions you are reading. Sat directly over the
	-- note it switches, so there is no doubt about what it applies to.
	F.diffTabs = {}
	for i, hc in ipairs({ false, true }) do
		local b = W.Button(p, hc and "Heroic" or "Normal", "secondary")
		b:SetSize(62, TAB_H)
		-- Beside the boss name, because it changes which version of THAT
		-- plan you are reading -- not which page you are on.
		b:SetPoint("LEFT", F.title, "RIGHT", 12 + (i - 1) * 60, 1)
		b._hc = hc
		b:Tooltip(hc
			and "The heroic plan."
				.. "\nHeroic abilities carry DIFFERENT spell ids, so a normal"
				.. "\nnote's timers never fire here -- this is its own note."
			or "The normal plan.")
		b:SetScript("OnClick", function() N.SetViewHeroic(hc) end)
		F.diffTabs[#F.diffTabs + 1] = b
	end

	-- No "Fill names" button. The slots resolve as you type now, so writing the
	-- names into the text bought nothing and cost the note its link to the slot
	-- table -- change a paladin and that one note would have been left behind.
	F.clear = W.Button(p, "Clear")
	-- On the boss name's line: these act on the note under them, so they
	-- share its row rather than sitting in a band of their own. Level with
	-- TAB_Y, so the header reads as one row across both columns.
	F.clear:SetSize(54, 20); F.clear:SetPoint("TOPRIGHT", -10, TAB_Y)
	F.clear:Tooltip("Undo your edits to this note.\nIt goes back to the one Okanvil ships with.")
	F.clear:SetScript("OnClick", function()
		local sel = db.selected
		if not sel then return end
		-- Clearing your edit falls back to the shipped note rather than leaving
		-- nothing, so "Clear" is undo, not delete.
		-- With a shipped note behind it, Clear is an undo; without one it deletes.
		local packed = N.HasPacked(sel)
		Okanvil:Confirm(
			packed and ("Throw away your edits to " .. sel .. "?\n\nIt goes back to the note Okanvil ships with.")
			        or ("Clear the note for " .. sel .. "?"),
			packed and "Reset" or "Clear",
			function()
				db.notes[sel] = nil
				F.editing = nil
				N.Broadcast()
				N.Refresh()
			end)
	end)

	-- Read is what you watch in the fight; Edit is where you paste. One note,
	-- two views -- a note being read must not be a text box you can nudge.
	F.mode = W.Button(p, "Edit")
	F.mode:SetSize(54, 20); F.mode:SetPoint("RIGHT", F.clear, "LEFT", -5, 0)

	-- Syntax crib. A click, not a hover: it is a reference you read while typing,
	-- and a hover tip vanishes the moment you reach for the keyboard.
	F.help = W.Button(p, "?")
	F.help:SetSize(22, 20)
	F.help:SetPoint("RIGHT", F.mode, "LEFT", -5, 0)
	F.help:Tooltip("How to write a note line, and the class colours.\nOpens beside this window.")
	F.help:SetScript("OnClick", showHelp)

	-- The ids this core's bosses actually cast, beside the syntax that uses
	-- them. Here rather than in Settings because it is read WHILE writing a
	-- line, in the half-second between wondering which id and typing one.
	F.seen = W.Button(p, "ids")
	F.seen:SetSize(34, 20)
	F.seen:SetPoint("RIGHT", F.help, "LEFT", -5, 0)
	F.seen:Tooltip("What the bosses were seen casting, and how often."
		.. "\nRecorded once per boss and difficulty, from the first kill -- nothing to switch on."
		.. "\nUse it when a timer never starts: the id may not exist here.")
	F.seen:SetScript("OnClick", showSeen)
	F.mode:SetScript("OnClick", function()
		N.Commit()
		F.editMode = not F.editMode
		N.Refresh()
	end)

	-- ---- read view: the note as timed lines ----
	F.readCard = W.Frame(p, "soft")
	-- CARD_Y, not -40: the note card and the list card are two halves of one
	-- view and have to start on the same line. The filter band grew to two rows
	-- and the left card moved down with it, leaving the right one floating a
	-- row and a half higher with a strip of bare panel beside its heading.
	F.readCard:SetPoint("TOPLEFT", RX, CARD_Y - 28)
	-- 30: the foot is ONE row again. Follow the room moved up to the toolbar,
	-- so the card takes back the 22px its second row was holding.
	-- -6: the same margin the list card keeps on the left, so the two halves
	-- sit symmetrically in the page instead of the note stopping short of the edge.
	F.readCard:SetPoint("BOTTOMRIGHT", -6, 30)

	local rbar = F.readCard:CreateTexture(nil, "ARTWORK")
	rbar:SetTexture(FLAT)
	do local a = Okanvil.Colors.accent; rbar:SetVertexColor(a[1], a[2], a[3], 1) end
	rbar:SetWidth(2); rbar:SetPoint("TOPLEFT"); rbar:SetPoint("BOTTOMLEFT")

	local rsf = CreateFrame("ScrollFrame", nil, F.readCard)
	-- -8 at the top: a line starting 4px under the border touched it.
	rsf:SetPoint("TOPLEFT", 4, -8); rsf:SetPoint("BOTTOMRIGHT", -10, 4)
	local rchild = CreateFrame("Frame", nil, rsf); rchild:SetSize(10, 1)
	rsf:SetScrollChild(rchild)
	local rsb = CreateFrame("Slider", nil, F.readCard)
	rsb:SetPoint("TOPRIGHT", -3, -4); rsb:SetPoint("BOTTOMRIGHT", -3, 4); rsb:SetWidth(4)
	rsb:SetOrientation("VERTICAL"); rsb:SetValueStep(1)
	local rth = rsb:CreateTexture(nil, "OVERLAY"); rth:SetTexture(FLAT); rth:SetSize(4, 30)
	do local a = Okanvil.Colors.accent; rth:SetVertexColor(a[1], a[2], a[3], 1) end
	rsb:SetThumbTexture(rth)
	rsb:SetScript("OnValueChanged", function(_, v) rsf:SetVerticalScroll(v) end)
	rsf:EnableMouseWheel(true)
	rsf:SetScript("OnMouseWheel", function(_, d) rsb:SetValue(rsb:GetValue() - d * 30) end)
	rsf:SetScript("OnSizeChanged", function() rchild:SetWidth(rsf:GetWidth()) end)
	F.readChild, F.readSF, F.readSB = rchild, rsf, rsb
	F.lineRows = {}

	-- Countdowns only move while something is running, so the ticker sleeps
	-- otherwise rather than repainting a static list forever.
	F.readCard:SetScript("OnUpdate", function(self, el)
		self._t = (self._t or 0) + el
		if self._t < 0.2 then return end
		self._t = 0
		if Okanvil.NotesParse and Okanvil.NotesParse.InCombat() then N.PaintLines() end
	end)

	F.edit = W.MultiEdit(p)
	F.edit:SetTextSize(14)      -- a note is read as much as typed in
	F.edit:SetPoint("TOPLEFT", RX, CARD_Y - 28)
	-- Same foot as the read card: the two are one card in two modes, and a
	-- different bottom made the note jump as you switched between them.
	F.edit:SetPoint("BOTTOMRIGHT", -6, 30)
	F.edit.edit:SetScript("OnEditFocusLost", function() N.Commit(); N.Refresh() end)

	-- One status line, left to right: what the note holds, where you are, and
	-- the switch that decides whether the page follows you.
	--
	-- Each takes a WIDTH. Without one a FontString grows to whatever it holds,
	-- and three of them on one row simply drew over each other -- the note count,
	-- the room and the syntax hint all in the same 40 pixels, unreadable.
	F.count = W.Text(p, "", "note", "dim")
	F.count:SetPoint("BOTTOMLEFT", RX, 12)
	F.count:SetWidth(120)
	F.count:SetJustifyH("LEFT")

	F.here:ClearAllPoints()
	F.here:SetPoint("LEFT", F.count, "RIGHT", 8, 0)
	F.here:SetWidth(150)
	F.here:SetJustifyH("LEFT")


	-- Short, because it shares the row. The long version is one click away
	-- behind the ? and does not need repeating along the bottom of the window.
	F.hint = W.Text(p, "MRT format -- press ? for the syntax", "note", "dim")
	F.hint:SetPoint("BOTTOMRIGHT", -10, 12)
	F.hint:SetJustifyH("RIGHT")

	-- No anchor for F.auto here: it lives on the toolbar now, beside the pills.
	-- The foot is one row again -- the count, the room and the syntax hint --
	-- which is what let the note card drop from 52 to 30.

	N.Refresh()
end

-- ------------------------------------------------------------
-- Fight window settings, as a pill beside the notes.
--
-- A right-click menu on the window itself was the first try, and it closed the
-- moment you clicked anything in it. Settings belong on a page.
-- ------------------------------------------------------------
function N.BuildWindowPage(p)
	local WIN = Okanvil.NotesWindow
	local X = 6
	local y = -14

	local head = W.Text(p, "FIGHT WINDOW", "head", "accent")
	head:SetPoint("TOPLEFT", X, y)
	y = y - 28

	local hint = W.Text(p,
		"A small window with the current note's timers, so you can read it with Okanvil closed. Hover it and click the padlock to unlock; unlocked, drag it anywhere or pull the bottom-right corner to set its width.",
		"note", "dim")
	hint:SetPoint("TOPLEFT", X, y)
	hint:SetPoint("RIGHT", p, "RIGHT", -16, 0)
	hint:SetJustifyH("LEFT")
	hint:SetHeight(34)
	y = y - 52

	-- W.Slider draws its label ABOVE the bar, so each one needs clearance on top
	-- as well as below -- 46px of pitch put the next label on the last bar.
	F.wAlpha = W.Slider(p, "Background opacity", 0, 100, 5,
		function() return WIN and WIN.GetAlpha() or 85 end,
		function(v) if WIN then WIN.SetAlpha(v) end end)
	F.wAlpha:SetPoint("TOPLEFT", X, y)
	F.wAlpha:SetWidth(240)
	y = y - 30

	local aHint = W.Text(p, "At 0 the panel disappears and the text takes an outline.", "note", "dim")
	aHint:SetPoint("TOPLEFT", X, y)
	y = y - 40

	F.wRoom = W.Check(p, "Only show in the boss's room",
		function() return WIN and WIN.OnlyInRoom() end,
		function(v) if WIN then WIN.SetOnlyInRoom(v) end end)
	F.wRoom:SetPoint("TOPLEFT", X, y)
	F.wRoom:Tooltip("Off, the window stays up everywhere -- useful while writing\nnotes, noisy while playing.")
	y = y - 40

	F.wSize = W.Slider(p, "Text size", 10, 20, 1,
		function() return WIN and WIN.GetSize() or 13 end,
		function(v) if WIN then WIN.SetSize(v) end end)
	F.wSize:SetPoint("TOPLEFT", X, y)
	F.wSize:SetWidth(240)
	y = y - 30

	local sHint = W.Text(p, "The window grows to fit the note at whatever size you pick.", "note", "dim")
	sHint:SetPoint("TOPLEFT", X, y)
	y = y - 40

	-- Icons separately from the text. They carry the part you read fastest --
	-- which cooldown -- so they are worth making bigger than the words beside
	-- them, and tying the two together would stop you doing that.
	F.wIcon = W.Slider(p, "Icon size", 12, 32, 2,
		function() return WIN and WIN.GetIconSize() or 18 end,
		function(v) if WIN then WIN.SetIconSize(v) end end)
	F.wIcon:SetPoint("TOPLEFT", X, y)
	F.wIcon:SetWidth(240)
	y = y - 30

	local iHint = W.Text(p, "The spell and marker icons inside a note.", "note", "dim")
	iHint:SetPoint("TOPLEFT", X, y)
	y = y - 42

	-- No role slots.
	--
	-- There was a page of boxes here -- Holy1, Prot, Ret -- that filled {Holy1}
	-- style tags in the notes. It worked for paladin cooldowns and nothing else:
	-- the list of roles lived in this file, so wanting a Lust, a PI or a tank
	-- cooldown meant editing the addon and shipping a release. Mid-raid, that is
	-- not a thing anybody can do.
	--
	-- A note is text. Write the player's name in it, like MRT, and any cooldown
	-- works the moment you type it -- no list to extend, nothing to keep in step.

	-- ---- sharing ----
	local shHead = W.Text(p, "SHARING", "head", "accent")
	shHead:SetPoint("TOPLEFT", X, y)
	y = y - 28

	F.wShare = W.Check(p, "Keep notes in step with other officers",
		function() return db.share ~= false end,
		function(v) db.share = v and true or false end)
	F.wShare:SetPoint("TOPLEFT", X, y)
	F.wShare:Tooltip("Officers running Okanvil swap notes automatically, newest wins.\nPer note, so two officers can edit different bosses and both survive.")
	y = y - 32

	-- Send and "Who has them?" live in the page header, beside Fight window:
	-- they act on the raid, and burying them on a config tab meant the answer to
	-- "did they get it?" was two clicks away from the note you just changed.
	local shHint = W.Text(p,
		"Send to raid and Who has them? are in the header, beside Fight window.",
		"note", "dim")
	shHint:SetPoint("TOPLEFT", X, y)
end

-- ------------------------------------------------------------
-- "Who has them?" -- the answer to the only question that matters before a
-- pull. The count goes in the header; the names go in a panel, because a raid
-- of 25 does not fit on a status line.
-- ------------------------------------------------------------
local auditPanel

local function showAudit(ok, stale, missing, noWA)
	local f = auditPanel
	if not f then
		f = Okanvil:Popup("Who has the notes")
		f:SetSize(360, 380)
		f.body = W.Text(f, "", "note")
		f.body:SetPoint("TOPLEFT", 14, -34)
		f.body:SetPoint("BOTTOMRIGHT", -14, 14)
		f.body:SetJustifyH("LEFT")
		f.body:SetJustifyV("TOP")
		if f.body.SetWordWrap then f.body:SetWordWrap(true) end
		auditPanel = f
	end

	local out = {}
	local function section(colour, head, list)
		if #list == 0 then return end
		out[#out + 1] = ("|c%s%s (%d)|r"):format(colour, head, #list)
		out[#out + 1] = table.concat(list, ", ")
		out[#out + 1] = ""
	end
	section("ff7cfc8a", "Up to date", ok)
	section("ffe0b860", "On an older copy -- press Send to raid", stale)
	section("ffff5555", "Not answering -- no Okanvil", missing)
	section("ffff8c42", "Without the Okanvil Timers WA -- the note stays hidden for them", noWA or {})
	f.body:SetText(table.concat(out, "\n"))
	f:Show()
	f:Raise()
end

function N.RunAudit()
	if not N.AuditRaid then return end
	N.auditLine = "|cff8a8d93Asking the raid...|r"
	if F and F.dash then F.dash:Refresh() end

	local started = N.AuditRaid(function()
		local ok, stale, missing, noWA = N.AuditResult()
		-- The header carries the verdict at a glance; anything wrong is worth a
		-- colour, and all-clear is worth saying plainly.
		if #missing > 0 then
			N.auditLine = ("|cffff5555%d without Okanvil|r"):format(#missing)
		elseif #noWA > 0 then
			N.auditLine = ("|cffff8c42%d without the Timers WA|r"):format(#noWA)
		elseif #stale > 0 then
			N.auditLine = ("|cffe0b860%d on an older copy|r"):format(#stale)
		else
			N.auditLine = ("|cff7cfc8aAll %d up to date|r"):format(#ok)
		end
		if F and F.dash then F.dash:Refresh() end
		showAudit(ok, stale, missing, noWA)
	end)

	if not started then
		N.auditLine = "|cff8a8d93Not in a group -- nobody to ask|r"
		if F and F.dash then F.dash:Refresh() end
	end
end

function N.Refresh()
	if not (F and F.listChild) then return end
	refreshSeen()

	-- where you are
	local here = N.NoteForHere()
	if here then
		-- The ROOM, then the note it picked. NoteForHere returns the note's name
		-- -- which is the boss -- so printing "In <that>" read as if the subzone
		-- were called "Deathbringer Saurfang", and looked like a bad match when
		-- the match was right.
		local room = GetSubZoneText()
		if not room or room == "" then room = GetZoneText() or "" end
		if room ~= "" and room ~= here then
			F.here:SetText(("|cff6f7176%s|r  |cff8a8d93->|r |cffe0b860%s|r"):format(room, here))
		else
			F.here:SetText("|cffe0b860" .. here .. "|r")
		end
	elseif N.IsOneRoomRaid() then
		-- One arena for every boss: nothing to switch on. Say so, or the page
		-- looks like it failed to notice where you are.
		F.here:SetText("|cffe0b860" .. (GetZoneText() or "")
			.. "|r |cff6f7176-- pick the note yourself, one room for every boss|r")
	else
		local z = GetSubZoneText()
		if not z or z == "" then z = GetZoneText() or "" end
		F.here:SetText(z ~= "" and ("|cff6f7176" .. z .. "|r") or "")
	end

	-- which raid + size tab is live
	if F.comboTabs then
		local vr, vs = N.ViewRaid(), N.ViewSize()
		for _, b in ipairs(F.comboTabs) do
			b:SetKind((b._raid == vr and b._size == vs) and "tabOn" or "tab")
		end
	end
	if F.diffTabs then
		local vh = N.ViewHeroic()
		for _, b in ipairs(F.diffTabs) do
			b:SetKind(b._hc == vh and "tabOn" or "tab")
		end
	end

	-- the list
	for _, r in ipairs(F.rows) do r:Hide() end
	local list = N.List()
	for i, name in ipairs(list) do
		local r = listRow(i)
		r._name = name
		local text = N.Get(name)
		local has = text and text ~= ""
		local own = N.IsOwn(name)
		-- The boss, never the key: the size is the tab you are on, and repeating
		-- it on every row is noise you have to read past twelve times.
		r.name:SetText((has and "|cffdcddde" or "|cff6f7176") .. N.BossOf(name) .. "|r")
		-- WHO and WHEN, not "edited".
		--
		-- The old badge said a note had been changed without saying by whom, which
		-- is the half worth knowing: a plan somebody else rewrote this morning is a
		-- different thing from one you typed last week. The shipped notes say
		-- nothing at all -- a badge on every row is a badge nobody reads.
		local by = N.AuthorOf(name)
		if by then
			local stamp = db.stamps and db.stamps[name]
			local when = stamp and date("%d %b", stamp) or nil
			local col = own and "|cff7cfc8a" or "|cff8a8d93"
			r._tipText = when
				and ("|cff8a8d93last edit|r %s%s|r |cff8a8d93%s|r"):format(col, by, when)
				or ("|cff8a8d93last edit|r %s%s|r"):format(col, by)
		else
			r._tipText = nil
		end
		-- Preview: the note's first real line, markup stripped (timers, spell
		-- tags, colour codes), so the row says what the plan is at a glance.
		local first = ""
		if has then
			for line in (text .. "\n"):gmatch("(.-)\n") do
				local t = line:gsub("%b{}", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
				t = t:gsub("^%s+", ""):gsub("%s+$", "")
				if t ~= "" then first = t; break end
			end
		end
		r.dot:SetText(first)
		-- LIVE = the note the raid is on (sent to their WeakAuras); READY = has a
		-- plan; EMPTY = nothing written yet.
		local cc, label
		if name == db.selected and has then
			cc, label = Okanvil.Colors.ok, "LIVE"
		elseif has then
			cc, label = Okanvil.Colors.textDim, "READY"
		else
			cc, label = { 0.37, 0.38, 0.40 }, "EMPTY"
		end
		r.chip.text:SetText(label)
		r.chip.text:SetTextColor(cc[1], cc[2], cc[3])
		r.chip:SetBackdropBorderColor(cc[1], cc[2], cc[3], 0.6)
		r.chip:SetWidth((r.chip.text:GetStringWidth() or 30) + 12)
		r.sel:SetShown(name == db.selected)
		r:Show()
	end
	local h = math.max(1, #list * (ROW_H + 2))
	F.listChild:SetHeight(h)
	local maxs = math.max(0, h - F.listSF:GetHeight())
	F.listSB:SetMinMaxValues(0, maxs); F.listSB:SetShown(maxs > 4)

	-- the note
	local sel = db.selected
	local canEdit = N.CanEdit()
	-- Boss on the left, size dim on the right: the title is the one place worth
	-- saying which plan this is, because the editor below it changes with it.
	-- Boss and size only. The difficulty is the lit tab right beside this, so
	-- naming it again in the title said the same thing twice in two colours.
	F.title:SetText(sel
		and (N.BossOf(sel) .. ("  |cff6f7176%d man|r"):format(N.SizeOf(sel)))
		or "|cff6f7176Pick a note|r")

	-- Every control that CHANGES a note is hidden for a raider, rather than shown
	-- and refused on click. They read the plan and get it from the leader; an Edit
	-- button that appears to work, then loses what was typed to the next Send, is
	-- worse than no button.
	F.clear:SetShown(sel ~= nil and canEdit)
	-- HasStored, not IsOwn: the word turns on whether there is stored text to
	-- put back, which is true of a note an officer sent you just as much as one
	-- you typed. Asking who wrote it would label a received note "Clear" and
	-- then reset it anyway.
	F.clear.text:SetText(N.HasStored(sel) and "Reset" or "Clear")
	F.mode:SetShown(sel ~= nil and canEdit)
	if F.addBtn then F.addBtn:SetShown(canEdit) end
	if F.delBtn then F.delBtn:SetShown(canEdit) end

	F.mode.text:SetText(F.editMode and "Read" or "Edit")

	local editing = sel ~= nil and F.editMode and canEdit
	F.edit:SetShown(editing)
	F.readCard:SetShown(sel ~= nil and not editing)

	if sel then
		local text = N.Get(sel) or ""
		-- Only push text in when the box is not being typed in, or the cursor
		-- jumps to the end on every refresh.
		if editing and (F.editing ~= sel or not F.edit.edit:HasFocus()) then
			F.edit.edit:SetText(text)
			F.editing = sel
		end
		F.entries = Okanvil.NotesParse and Okanvil.NotesParse.Parse(text) or {}
		local timed = 0
		for _, e in ipairs(F.entries) do if e.time then timed = timed + 1 end end
		-- An empty heroic note is the expected state, not a fault -- the plan
		-- simply has not been written yet -- but it has to SAY so, because the
		-- normal version sitting one tab away looks like it should have appeared.
		if #F.entries == 0 and N.IsHeroic(sel) then
			-- Short: it shares the footer row. The why is in the Heroic tab's
			-- own tooltip, where there is room for it.
			F.count:SetText("|cffe8734aNo heroic note yet|r")
		else
			F.count:SetText(("|cff6f7176%d lines, %d timed|r"):format(#F.entries, timed))
		end
		if not editing then N.PaintLines() end
	else
		F.editing = nil
		F.entries = nil
		F.count:SetText("")
	end
end

-- ------------------------------------------------------------
-- The read view: one row per note line, with a live countdown.
-- ------------------------------------------------------------
-- Taller than the list rows: this is the half you read at a glance mid-pull,
-- and the page has the vertical room now that the filters moved to the header.
local LROW_H = 32

local function lineRow(i)
	local r = F.lineRows[i]
	if r then return r end
	r = W.Frame(F.readChild, "bare")
	r:SetHeight(LROW_H)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * LROW_H)
	r:SetPoint("TOPRIGHT", 0, -(i - 1) * LROW_H)

	-- Time on the RIGHT, matching MRT's reminder bars and the fight window.
	-- A left column reserves its width even on a line that has no clock.
	r.t = W.Text(r, "", "head", "accent")
	r.t:SetPoint("RIGHT", -6, 0)
	r.t:SetJustifyH("RIGHT")

	r.mark = r:CreateTexture(nil, "BACKGROUND")
	r.mark:SetTexture(FLAT)
	r.mark:SetPoint("TOPLEFT", 0, 0)
	r.mark:SetPoint("BOTTOMLEFT", 0, 0)
	r.mark:SetWidth(2)
	do local a = Okanvil.Colors.accentHi; r.mark:SetVertexColor(a[1], a[2], a[3], 1) end
	r.mark:Hide()

	r.txt = W.Text(r, "", "head")
	r.txt:SetPoint("LEFT", 6, 0)
	r.txt:SetPoint("RIGHT", r.t, "LEFT", -10, 0)
	r.txt:SetJustifyH("LEFT")
	if r.txt.SetWordWrap then r.txt:SetWordWrap(false) end

	F.lineRows[i] = r
	return r
end

-- mm:ss for anything a minute out, bare seconds when it is close -- the last
-- ten seconds are the ones you read under pressure.
local function fmt(s)
	if s >= 60 then return ("%d:%02d"):format(math.floor(s / 60), math.floor(s % 60)) end
	if s >= 10 then return ("%d"):format(math.floor(s)) end
	return ("%.1f"):format(s)
end

function N.PaintLines()
	if not (F and F.readChild and F.entries) then return end
	local P = Okanvil.NotesParse
	local now = GetTime()

	for _, r in ipairs(F.lineRows) do r:Hide() end

	for i, e in ipairs(F.entries) do
		local r = lineRow(i)
		r:Show()
		r.txt:SetText(P and P.Render(e.text) or (e.text or ""))
		-- Your own line, marked: four names read the same at a glance.
		if r.mark then r.mark:SetShown(e.mine and true or false) end

		if e.plain then
			-- A line with no {time:} keeps no clock column.
			--
			-- The width was reserved either way, so a plain reminder started 52px in
			-- with nothing to its left -- a gap that read as a missing timer rather
			-- than as a line that never had one.
			r.t:SetText("")
			r:SetAlpha(1)
		else
			local left = P and P.Remaining(e, now)
			if not left then
				-- Out of combat, or waiting on an occurrence: show what is
				-- written rather than a blank, so the note still reads as a plan.
				r.t:SetText(("|cff6f7176%d:%02d|r"):format(math.floor(e.time / 60), e.time % 60))
				r:SetAlpha(1)
			elseif left <= 0 then
				r.t:SetText("")          -- passed: the line stays, the clock goes
				r:SetAlpha(0.45)
			else
				local col = left <= 5 and "|cffff5555" or (left <= 10 and "|cffe0b860" or "|cff7cfc8a")
				r.t:SetText(col .. fmt(left) .. "|r")
				r:SetAlpha(1)
			end
		end
	end

	local h = math.max(1, #F.entries * LROW_H)
	F.readChild:SetHeight(h)
	local maxs = math.max(0, h - F.readSF:GetHeight())
	F.readSB:SetMinMaxValues(0, maxs); F.readSB:SetShown(maxs > 4)
end

-- ------------------------------------------------------------
-- Boot
-- ------------------------------------------------------------
local core = CreateFrame("Frame")
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
core:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == "Okanvil" then
		OkanvilNotesDB = OkanvilNotesDB or {}
		for k, v in pairs(defaults) do
			if OkanvilNotesDB[k] == nil then
				OkanvilNotesDB[k] = (type(v) == "table") and {} or v
			end
		end
		db = OkanvilNotesDB
		N.db = db

		-- Sweep out empty notes that nobody created on purpose.
		--
		-- These are leftovers: a note the addon used to ship and no longer does,
		-- or one deleted while its text was still in the editor and written back
		-- empty. They hold nothing and leaving one selected showed "No note for X"
		-- with nothing in the list to explain it.
		--
		-- A note made with + New is also empty until it is typed into, so the
		-- STAMP is what separates them: New stamps the note, the write-back does
		-- not. Without that test a note created just before a /reload was swept
		-- away by this.
		for name, text in pairs(db.notes or {}) do
			local stamped = db.stamps and db.stamps[name]
			if (text == nil or text == "") and not stamped
				and not (Okanvil.NotesPack and Okanvil.NotesPack[name]) then
				db.notes[name] = nil
			end
		end

		-- Whatever was selected may have just gone with them.
		if db.selected and not (db.notes[db.selected]
			or (Okanvil.NotesPack and Okanvil.NotesPack[db.selected])) then
			db.selected = N.List()[1]
		end

		Okanvil_Plugins = Okanvil_Plugins or {}
		Okanvil_Plugins[ADDON] = {
			title = "Notes",
			desc = "Raid notes per boss, switching on their own as you walk into each room.",
			icon = (Okanvil.ICONS and Okanvil.ICONS.notes) or "Interface\\Icons\\INV_Scroll_03",
			build = function(panel) build(panel) end,
			refresh = function() N.Refresh() end,
		}
		return
	end

	if event == "PLAYER_LOGIN" then
		if not db then return end
		if Okanvil and Okanvil.Register then Okanvil:Register(ADDON) end
		applyZone()
	end
end)

-- ------------------------------------------------------------
-- /oknotes -- where this room stands, and a manual Send.
--
-- To practise a note on a target dummy, map the subzone you stand in: add it to
-- ZONE_NOTE, write a note under that name, and it runs there through the same
-- path Icecrown uses. That replaced a test mode that answered yes everywhere,
-- which drifted in both directions -- it ran boss notes on dungeon trash when
-- left on, and a raider running only the aura was never gated by it anyway.
-- ------------------------------------------------------------
SLASH_OKNOTES1 = "/oknotes"
SlashCmdList["OKNOTES"] = function(msg)
	local arg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

	if arg == "send" then
		if N.SendNow then N.SendNow() end
		return
	end

	if arg == "unlock" then
		if not Okanvil.cdb then
			Okanvil:Print("Not ready yet -- try again once you are logged in.")
			return
		end
		Okanvil.cdb.notesUnlocked = not Okanvil.cdb.notesUnlocked
		if Okanvil.cdb.notesUnlocked then
			Okanvil:Print("Notes |cff00ff00unlocked|r on this character -- you can edit them.")
		else
			Okanvil:Print("Notes |cffff5555locked|r again on this character.")
		end
		if N.Refresh then N.Refresh() end
		return
	end

	local P = Okanvil.NotesParse

	-- Why a line never counted down. An anchored line waits for a combat-log
	-- event, and when that event never arrives the line just sits there -- the
	-- same thing you see when the spell id is wrong for this core, so the log
	-- has to be watched rather than guessed at.
	if arg == "watch" then
		if not (P and P.SetDebug) then return end
		P.SetDebug(not P.Debug())
		if P.Debug() then
			Okanvil:Print("Notes log recording |cff7cfc8aON|r -- pull the boss, then |cffe0b860/reload|r.")
			Okanvil:Print("|cff8a8d93The pull is written to SavedVariables\\Okanvil.lua"
				.. " (OkanvilNotesDB.log), so nothing scrolls away.|r")
			-- Prove the switch reached the SAVED table, not just the copy in
			-- memory. Code synced while the client is running does not take
			-- effect until it reloads the Lua, and until then a watch that looks
			-- fine writes nothing -- which is indistinguishable from a bug.
			local stored = OkanvilNotesDB and OkanvilNotesDB.log
			if stored and stored.watching then
				Okanvil:Print("|cff7cfc8aSaved.|r The flag is in the file -- /reload will write the pull.")
			else
				Okanvil:Print("|cffff5555Not saved|r -- this client is running older code. Restart WoW.")
			end
		else
			Okanvil:Print("Notes log recording |cffff5555OFF|r.")
		end
		return
	end

	-- What the LAST pull actually produced. Survives the wipe that produced it,
	-- which is the point: nobody reads chat mid-fight.
	if arg == "anchors" then
		if not (P and P.SeenAnchors) then return end
		local seen = P.SeenAnchors()
		local keys = {}
		for k in pairs(seen) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b) return (seen[a] or 0) < (seen[b] or 0) end)
		if #keys == 0 then
			Okanvil:Print("|cff8a8d93No anchor events seen since the last pull.|r"
				.. " Either nothing was cast, or the ids are not arriving.")
			return
		end
		Okanvil:Print(("|cffe0b860%d|r anchor events since the last pull:"):format(#keys))
		for i = 1, math.min(#keys, 40) do
			Okanvil:Print(("  |cff8a8d93+%5.1fs|r  %s"):format(seen[keys[i]] or 0, keys[i]))
		end
		return
	end

	Okanvil:Print("|cffe0b860/oknotes send|r -- push your notes to the group now")
	Okanvil:Print("|cffe0b860/oknotes watch|r -- print combat-log ids as they arrive")
	Okanvil:Print("|cffe0b860/oknotes anchors|r -- what the last pull produced")
	-- Where the note you have selected would run, and whether that is here. The
	-- question "why are my timers not starting" used to be answered by a test
	-- mode that made them start everywhere; this answers it instead.
	local here = N.NoteForHere and N.NoteForHere()
	local sel = db and db.selected
	if here then
		Okanvil:Print(("This room wants |cffe0b860%s|r -- you have |cffe0b860%s|r selected.")
			:format(here, tostring(sel or "nothing")))
	else
		Okanvil:Print(("|cff8a8d93No note is mapped to this room, so nothing runs here.|r"
			.. " Selected: |cffe0b860%s|r"):format(tostring(sel or "nothing")))
	end
end
