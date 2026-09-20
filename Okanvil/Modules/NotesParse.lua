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
			return {
				kind = "event",
				key  = prefix .. ":" .. spellID .. ":" .. ((count ~= "" and count) or "1"),
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

function P.Render(text)
	if not text or text == "" then return "" end
	-- Notes copied out of MRT carry escaped pipes (||cff...), which a FontString
	-- prints literally instead of colouring. Unescape first.
	text = text:gsub("||", "|")
	text = P.FillSlots(text)
	text = text:gsub("{spell:(%d+):?%d*}", function(id)
		return "|T" .. P.SpellIcon(id) .. ":18|t"
	end)
	text = text:gsub("{(%a+%d?)}", function(tag)
		local n = ICONS[tag:lower()]
		if not n then return "{" .. tag .. "}" end
		return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. n .. ":18|t"
	end)
	return text
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
	local _, sub, _, _, _, _, _, _, spellID = ...
	local prefix = CLEU_PREFIX[sub]
	if not (prefix and type(spellID) == "number") then return end

	local base = prefix .. ":" .. spellID
	local n = (counters[base] or 0) + 1
	counters[base] = n
	reached[base .. ":" .. n] = GetTime()
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
boot:SetScript("OnEvent", function() P.HookDBM() end)
