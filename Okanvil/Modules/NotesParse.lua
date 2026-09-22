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
-- The saved record. Declared in the .toc beside OkanvilBugDB, and kept to a few
-- pulls: a raid night of every cast would be a file nobody can open.
local LOG_PULLS = 4

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
-- ONE ROW PER SPELL, not per occurrence: { id, name, prefix, n }. A boss fight
-- is thousands of events and a handful of distinct spells, so counting is what
-- makes this small enough to keep for every boss in the game.
--
-- Silent by design. Nothing prints, nothing warns, nothing asks -- you read it
-- when you sit down to write a note, not while you are tanking.
-- ------------------------------------------------------------
local function catalogue()
	local d = logDB()
	d.seen = d.seen or {}
	return d.seen
end

-- The boss this cast belongs to. The source NAME, not the note or the room: a
-- room can hold two bosses (the Plagueworks) and the note is whatever happens
-- to be selected, which may be the wrong one or none at all.
local function noteSpell(srcName, prefix, spellID, spellName)
	if not srcName or srcName == "" then return end
	local seen = catalogue()
	local boss = seen[srcName]
	if not boss then
		boss = {}
		seen[srcName] = boss
	end
	local key = prefix .. ":" .. spellID
	local row = boss[key]
	if row then
		row.n = row.n + 1
		return
	end
	-- Bounded per source, so a boss with a long tail of trash abilities cannot
	-- grow the file without limit.
	local count = 0
	for _ in pairs(boss) do count = count + 1 end
	if count >= 60 then return end
	boss[key] = {
		id = spellID,
		name = (type(spellName) == "string" and spellName) or "?",
		prefix = prefix,
		n = 1,
	}
end

-- Every spell recorded against one source, most cast first.
function P.SpellsSeen(srcName)
	local seen = (OkanvilNotesDB and OkanvilNotesDB.log and OkanvilNotesDB.log.seen) or {}
	local boss = seen[srcName]
	if not boss then return {} end
	local out = {}
	for _, row in pairs(boss) do out[#out + 1] = row end
	table.sort(out, function(a, b) return (a.n or 0) > (b.n or 0) end)
	return out
end

-- Who we have seen cast anything, so the UI can offer a list.
function P.SourcesSeen()
	local seen = (OkanvilNotesDB and OkanvilNotesDB.log and OkanvilNotesDB.log.seen) or {}
	local out = {}
	for name in pairs(seen) do out[#out + 1] = name end
	table.sort(out)
	return out
end

function P.ClearCatalogue()
	local d = logDB()
	d.seen = {}
end

local function logPull()
	local pulls = logDB().pulls
	local rec = {
		start = time(),
		zone = (GetZoneText and GetZoneText()) or "?",
		room = (GetSubZoneText and GetSubZoneText()) or "?",
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
			-- The parts are kept beside the key because the key is not final: most
			-- Icecrown abilities carry a different id per difficulty, so the number
			-- written in the note is translated at match time (see Remaining). The
			-- key stays as typed, for anything that wants to show it back.
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
	for line in note:gmatch("[^\r\n]+") do
		local secs, opts, rest = parseTime(line)
		if secs then
			out[#out + 1] = {
				time    = secs,
				anchor  = parseAnchor(opts),
				text    = rest,
				raw     = line,
				spellID = tonumber(line:match("{spell:(%d+)")),
				mine    = P.IsMine(rest),
			}
		elseif line:match("%S") then
			out[#out + 1] = { text = line, raw = line, plain = true }
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

watch:SetScript("OnEvent", function(_, event, ...)
	if not moduleOn() then return end

	if event == "PLAYER_REGEN_DISABLED" then
		-- No ENCOUNTER_START on 3.3.5a, so entering combat is the pull.
		resetEncounter()
		pullAt = GetTime()
		phaseAt = pullAt
		-- A fresh pull starts a fresh record. Kept past PLAYER_REGEN_ENABLED,
		-- unlike the counters, so a wipe can still be read back afterwards.
		seenKeys = {}
		pullRec = P.Debug() and logPull() or nil
		if pullRec then
			Okanvil:Print("|cff7cfc8a[notes]|r recording this pull -- /reload when done.")
		end
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		resetEncounter()
		return
	end

	if not pullAt then return end

	-- 3.3.5a's combat log has no raid-flag fields, so spellID sits two slots
	-- earlier than on retail. Signature, per DBM-Core.lua:1166:
	--   timestamp, event, sourceGUID, sourceName, sourceFlags,
	--   destGUID, destName, destFlags, spellID, spellName, spellSchool
	-- Reading the retail position silently counted spellName as the id, so
	-- every {time:...,SCC:nnn:k} anchor waited for an occurrence that never came.
	local _, sub, srcGUID, srcName, _, _, dstName, _, spellID = ...
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

	-- The catalogue runs ALWAYS, with nothing switched on. One row per spell
	-- per boss, so it costs a counter bump for everything after the first
	-- sighting -- cheap enough to leave on for every pull of every night, which
	-- is the point: the answer is already there when you sit down to write.
	noteSpell(srcName, prefix, spellID, spellName)

	-- The full ordered trace is the opt-in half (/oknotes watch), because that
	-- one IS per occurrence and would grow without bound.
	if pullRec and #pullRec.events < 400 then
		pullRec.events[#pullRec.events + 1] = {
			key = key, at = at, name = tostring(spellName or "?"),
		}
	end
end)

-- DBM already tracks phases and fires a callback for them (DBM-Core.lua:6926),
-- so there is nothing to infer here. Registered once, lazily -- DBM loads after
-- this file.
local hooked = false
function P.HookDBM()
	if hooked or not (DBM and DBM.RegisterCallback) then return end
	hooked = true
	-- The gate goes INSIDE the callback, not around the registration: DBM offers
	-- no way to unregister, so a hook installed at login is permanent. Checking
	-- here means a disabled Notes module stops tracking phases without leaving a
	-- dead hook that can never be removed.
	DBM:RegisterCallback("DBM_SetStage", function(_, _, _, stage)
		if not stage then return end
		if Okanvil.ModuleActive and not Okanvil:ModuleActive("Okanvil-Notes") then return end
		phase = stage
		phaseAt = GetTime()
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
