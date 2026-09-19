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
local ZONE_NOTE = {
	["The Spire"]                    = "Lord Marrowgar",
	["Oratory of the Damned"]        = "Lady Deathwhisper",
	["The Colossal Forge"]           = "Gunship Battle",
	["Rampart of Skulls"]            = "Gunship Battle",
	["Deathbringer's Rise"]          = "Deathbringer Saurfang",
	["The Plagueworks"]              = "Rotface & Festergut",
	["Putricide's Laboratory of Alchemical Horrors and Fun"] = "Professor Putricide",
	["The Crimson Hall"]             = "Blood Council",
	["The Sanctum of Blood"]         = "Queen Lana'thel",
	["The Frostwing Halls"]          = "Valithria Dreamwalker",
	["The Frost Queen's Lair"]       = "Sindragosa",
	["The Frozen Throne"]            = "The Lich King",
	["The Ruby Sanctum"]             = "Halion",
}

-- The order the list shows them in: the order you meet them, not alphabetical.
local NOTE_ORDER = {
	"Lord Marrowgar", "Lady Deathwhisper", "Gunship Battle",
	"Deathbringer Saurfang", "Rotface & Festergut", "Professor Putricide",
	"Blood Council", "Queen Lana'thel", "Valithria Dreamwalker",
	"Sindragosa", "The Lich King", "Halion",
}

local defaults = {
	notes = {},        -- [name] = text
	autoZone = true,   -- switch note on entering a boss room
	selected = nil,    -- which note the page is showing
	share = true,      -- swap notes with other officers automatically
	stamps = {},       -- [name] = time() of the last edit, for the sync
}

-- ------------------------------------------------------------
-- Data
-- ------------------------------------------------------------
-- A note you have never written falls back to the shipped ICC pack, so the tab
-- is useful before you have typed anything. Writing one makes it yours and the
-- pack is never consulted for it again.
function N.Get(name)
	if not name then return nil end
	-- db is nil until ADDON_LOADED. A WeakAura's init runs on its own schedule
	-- and can reach this first -- `db.notes` then errors inside the aura, which
	-- takes the rest of ITS init down with it.
	local own = db and db.notes and db.notes[name]
	if own and own ~= "" then return own end
	return Okanvil.NotesPack and Okanvil.NotesPack[name] or nil
end

-- Has the user written their own, as opposed to reading the shipped one?
function N.IsOwn(name)
	local t = name and db and db.notes and db.notes[name]
	return t ~= nil and t ~= ""
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
	if not (Okanvil.U and Okanvil.U.isOfficer) then return true end   -- no roster API: do not lock anyone out
	local me = UnitName("player") or ""
	if Okanvil.U.isOfficer(me) then
		wasOfficer = true
		return true
	end
	if wasOfficer then return true end      -- known officer, roster just went cold
	if GuildRoster then GuildRoster() end   -- warm it for the next check
	return false
end

function N.Set(name, text)
	if not name or name == "" then return end
	if not N.CanEdit() then return end
	local old = db.notes[name]
	db.notes[name] = text or ""
	-- Stamp only a real change: Commit runs on every focus loss, and re-stamping
	-- unchanged text would make this client look newer than everyone else.
	if old ~= db.notes[name] and N.Touch then N.Touch(name) end
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
	return N.Get(db and db.selected) or ""
end

function N.CurrentName()
	return db and db.selected or nil
end

-- Is the selected note the one for the room we are standing in?
--
-- 3.3.5a has no ENCOUNTER_START, so anything watching for a pull falls back to
-- "entered combat" -- which is also true for a dungeon trash pack, a duel, or a
-- mob on the way in. This is the question that separates those: the note only
-- belongs here if the subzone asked for it.
function N.InNoteRoom()
	-- Test mode: pretend we are standing in the selected note's room, wherever
	-- we actually are. For trying the timers on a target dummy -- the raider
	-- running only the aura has no Okanvil and is never gated, so without this
	-- the two sides of a test behave differently and only theirs works.
	--
	-- Deliberately not persisted: it turns itself off at logout, because a
	-- forgotten bypass means every trash pull runs a boss note.
	if N.testMode then return (db and db.selected) ~= nil end

	-- No special case for the test note: Valley of Honor is in ZONE_NOTE, so the
	-- ordinary zone lookup below answers for it exactly as it does for a boss
	-- room. That is the point -- the test exercises the real path.
	local here = N.NoteForHere()
	if here then return here == (db and db.selected) end

	-- A one-room raid has no subzone to ask. Trial of the Crusader is a single
	-- arena for five bosses, so the lookup above can never succeed there -- and
	-- returning false would mean the timers never start, however carefully the
	-- note was picked. Here the CHOICE is the signal: you selected it, you are
	-- standing in the raid it belongs to, that is as much as can be known.
	if N.IsOneRoomRaid and N.IsOneRoomRaid() then
		return (db and db.selected) ~= nil
	end
	return false
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

-- Every note we know about: the twelve encounters in pull order, then anything
-- you added under a name of your own.
function N.List()
	local seen, out = {}, {}
	for _, n in ipairs(NOTE_ORDER) do
		out[#out + 1] = n
		seen[n] = true
	end
	-- Anything else we hold: notes you added yourself, AND notes the pack ships
	-- that are not in the pull order above. The pack was skipped here, so a note
	-- added to Notes-Data.lua under a new name existed but could never be picked.
	local extra = {}
	for n in pairs((db and db.notes) or {}) do
		if not seen[n] then extra[#extra + 1] = n; seen[n] = true end
	end
	for n in pairs(Okanvil.NotesPack or {}) do
		if not seen[n] then extra[#extra + 1] = n; seen[n] = true end
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

-- The note for the room you are standing in, or nil outside a boss room.
function N.NoteForHere()
	local sub = GetSubZoneText()
	if sub and sub ~= "" and ZONE_NOTE[sub] then return ZONE_NOTE[sub] end
	-- Halion's own zone reads through GetZoneText, not a subzone
	local zone = GetZoneText()
	if zone and ZONE_NOTE[zone] then return ZONE_NOTE[zone] end
	return nil
end

-- Is this a raid where the subzone can never name the boss? Used to explain the
-- silence rather than leave the page looking broken.
function N.IsOneRoomRaid()
	local zone = GetZoneText()
	return (zone and ONE_ROOM_RAIDS[zone]) == true
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
	if InCombatLockdown and InCombatLockdown() then pendingZone = true; return end
	local want = N.NoteForHere()
	if not want or want == db.selected then return end
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
	{ "Okanor",  "Just the name. The aura colours raid members by class," },
	{ "",        "so you never write colour codes yourself." },
	{ "",        "A line shows for whoever it names: spelling matters." },
	false,
	"EXTRAS",
	{ "{spell:64205}",  "that spell's icon, inline" },
	{ "{skull}",        "raid marker -- also cross, square, moon," },
	{ "",               "star, circle, diamond, triangle" },
	{ "",               "A line with no {time:} is plain text: markers," },
	{ "",               "reminders, headers." },
}

local HELP_EXAMPLE = "{time:0:58}Bone Storm 1 - Okanor {spell:64205}"

-- Built once, on first ask. Nobody opens this every session, so paying for the
-- frames up front would be frames nobody looks at.
local helpPanel
local function showHelp()
	if helpPanel then
		helpPanel:Show()
		helpPanel:Raise()
		return
	end

	local f = Okanvil:Popup("Writing a note line")
	f:SetWidth(430)
	helpPanel = f

	local CODE_X, MEAN_X = 14, 176
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
			if code ~= "" then
				local c = W.Text(f, code, "note")
				c:SetPoint("TOPLEFT", CODE_X, y)
				-- Monospace so the braces line up down the column; this is the
				-- half you copy, and it should read as code.
				c:SetFont("Fonts\\ARIALN.TTF", 12)
			end
			local m = W.Text(f, meaning, "note", "dim")
			m:SetPoint("TOPLEFT", MEAN_X, y)
			m:SetWidth(430 - MEAN_X - 14)
			m:SetJustifyH("LEFT")
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

local LIST_W = 180
local ROW_H = 24

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

	r.dot = W.Text(r, "", "note", "dim")
	r.dot:SetPoint("RIGHT", -7, 0)

	r.name = W.Text(r, "", "body")
	r.name:SetPoint("LEFT", 7, 0)
	r.name:SetPoint("RIGHT", r.dot, "LEFT", -5, 0)
	r.name:SetJustifyH("LEFT")
	if r.name.SetWordWrap then r.name:SetWordWrap(false) end

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
		local existing = db and db.notes and db.notes[name]
		if existing ~= nil or N.HasPacked(name) then
			Okanvil:Print(("|cff8a8d93A note for|r %s |cff8a8d93already exists -- opening it.|r"):format(name))
		else
			db.notes = db.notes or {}
			db.notes[name] = ""
			if N.Touch then N.Touch(name) end
		end
		N.Select(name)
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
		icon = "Interface\\Icons\\INV_Scroll_03",
		pills = true,
		drawerWidth = 0,
		footerHeight = 0,
		-- In the header, not on the page: these act on the raid or on a separate
		-- window, rather than on the note you are looking at.
		primaryText = function()
			return (Okanvil.NotesWindow and Okanvil.NotesWindow.IsShown())
				and "Hide fight window" or "Fight window"
		end,
		onPrimary = function()
			if Okanvil.NotesWindow then Okanvil.NotesWindow.Toggle() end
			if F and F.dash then F.dash:Refresh() end
		end,

		-- Send and the audit are officer work: a raider cannot send (the sync
		-- refuses them) and has nobody to audit, so showing the buttons would
		-- only promise something that never happens. The fight window stays --
		-- that is what a raider opens.
		secondaryText = function() return "Send to raid" end,
		secondaryWidth = 100,
		secondaryShown = function() return N.CanEdit() end,
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
		tertiaryShown = function() return N.CanEdit() end,
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
	F.here = W.Text(p, "", "body", "dim")
	F.here:SetPoint("TOPLEFT", 6, -10)

	F.auto = W.Check(p, "Follow the room",
		function() return db.autoZone end,
		function(v)
			db.autoZone = v and true or false
			if v then applyZone() end
			N.Refresh()
		end)
	-- The checkbox label sits to the RIGHT of the 18px box, so anchoring the box
	-- to the edge would push the words off the panel. Leave room for both.
	F.auto:SetPoint("TOPRIGHT", p, "TOPRIGHT", -124, -8)
	F.auto:Tooltip("Switch to the boss's note when you walk into their room.\nNever switches while you are in combat.")

	-- ---- left: the note list ----
	-- The card stops short of the bottom to leave room for the two buttons under
	-- it. Adding and deleting a note was only possible by editing Notes-Data.lua,
	-- so a note you made for a test -- or for a boss the pack does not ship --
	-- could be created but never removed.
	local lcard = W.Frame(p, "dark")
	lcard:SetPoint("TOPLEFT", 6, -40)
	lcard:SetPoint("BOTTOMLEFT", 6, 40)
	lcard:SetWidth(LIST_W)

	F.addBtn = W.Button(p, "+ New", "primary")
	F.addBtn:SetSize(LIST_W / 2 - 3, 22)
	F.addBtn:SetPoint("TOPLEFT", lcard, "BOTTOMLEFT", 0, -6)
	F.addBtn:SetScript("OnClick", function() N.PromptNew() end)

	F.delBtn = W.Button(p, "Delete", "danger")
	F.delBtn:SetSize(LIST_W / 2 - 3, 22)
	F.delBtn:SetPoint("TOPRIGHT", lcard, "BOTTOMRIGHT", 0, -6)
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
	F.title:SetPoint("TOPLEFT", RX, -42)

	F.clear = W.Button(p, "Clear")
	F.clear:SetSize(54, 20); F.clear:SetPoint("TOPRIGHT", -10, -38)
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
	F.help:Tooltip("How to write a note line.")
	F.help:SetScript("OnClick", showHelp)
	F.mode:SetScript("OnClick", function()
		N.Commit()
		F.editMode = not F.editMode
		N.Refresh()
	end)

	-- ---- read view: the note as timed lines ----
	F.readCard = W.Frame(p, "dark")
	F.readCard:SetPoint("TOPLEFT", RX, -66)
	F.readCard:SetPoint("BOTTOMRIGHT", -10, 34)

	local rsf = CreateFrame("ScrollFrame", nil, F.readCard)
	rsf:SetPoint("TOPLEFT", 4, -4); rsf:SetPoint("BOTTOMRIGHT", -10, 4)
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
	F.edit:SetPoint("TOPLEFT", RX, -66)
	F.edit:SetPoint("BOTTOMRIGHT", -10, 34)
	F.edit.edit:SetScript("OnEditFocusLost", function() N.Commit(); N.Refresh() end)

	F.count = W.Text(p, "", "note", "dim")
	F.count:SetPoint("BOTTOMLEFT", RX, 12)

	F.hint = W.Text(p, "MRT note format. Role slots are filled in a later version.", "note", "dim")
	F.hint:SetPoint("BOTTOMRIGHT", -10, 12)

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
	y = y - 42

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

local function showAudit(ok, stale, missing)
	local f = auditPanel
	if not f then
		f = Okanvil:Popup("Who has the notes")
		f:SetSize(360, 300)
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
	section("ffff5555", "Not answering -- no aura installed", missing)
	f.body:SetText(table.concat(out, "\n"))
	f:Show()
	f:Raise()
end

function N.RunAudit()
	if not N.AuditRaid then return end
	N.auditLine = "|cff8a8d93Asking the raid...|r"
	if F and F.dash then F.dash:Refresh() end

	local started = N.AuditRaid(function()
		local ok, stale, missing = N.AuditResult()
		-- The header carries the verdict at a glance; anything wrong is worth a
		-- colour, and all-clear is worth saying plainly.
		if #missing > 0 then
			N.auditLine = ("|cffff5555%d without the aura|r"):format(#missing)
		elseif #stale > 0 then
			N.auditLine = ("|cffe0b860%d on an older copy|r"):format(#stale)
		else
			N.auditLine = ("|cff7cfc8aAll %d up to date|r"):format(#ok)
		end
		if F and F.dash then F.dash:Refresh() end
		showAudit(ok, stale, missing)
	end)

	if not started then
		N.auditLine = "|cff8a8d93Not in a group -- nobody to ask|r"
		if F and F.dash then F.dash:Refresh() end
	end
end

function N.Refresh()
	if not (F and F.listChild) then return end

	-- where you are
	local here = N.NoteForHere()
	if here then
		F.here:SetText("|cff8a8d93In|r |cffe0b860" .. here .. "|r")
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

	-- the list
	for _, r in ipairs(F.rows) do r:Hide() end
	local list = N.List()
	for i, name in ipairs(list) do
		local r = listRow(i)
		r._name = name
		local text = N.Get(name)
		local has = text and text ~= ""
		local own = N.IsOwn(name)
		r.name:SetText((has and "|cffdcddde" or "|cff6f7176") .. name .. "|r")
		-- A mark only where there is something to say: you edited this one. The
		-- shipped notes are the normal case and need no badge -- a dot on almost
		-- every row says nothing.
		r.dot:SetText(own and "|cff7cfc8aedited|r" or "")
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
	F.title:SetText(sel or "|cff6f7176Pick a note|r")

	-- Every control that CHANGES a note is hidden for a raider, rather than shown
	-- and refused on click. They read the plan and get it from the leader; an Edit
	-- button that appears to work, then loses what was typed to the next Send, is
	-- worse than no button.
	F.clear:SetShown(sel ~= nil and canEdit)
	F.clear.text:SetText(N.IsOwn(sel) and "Reset" or "Clear")
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
		F.count:SetText(("|cff6f7176%d lines, %d timed|r"):format(#F.entries, timed))
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
local LROW_H = 26

local function lineRow(i)
	local r = F.lineRows[i]
	if r then return r end
	r = W.Frame(F.readChild, "bare")
	r:SetHeight(LROW_H)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * LROW_H)
	r:SetPoint("TOPRIGHT", 0, -(i - 1) * LROW_H)

	r.t = W.Text(r, "", "head", "accent")
	r.t:SetPoint("LEFT", 6, 0)
	r.t:SetWidth(52); r.t:SetJustifyH("RIGHT")

	r.mark = r:CreateTexture(nil, "BACKGROUND")
	r.mark:SetTexture(FLAT)
	r.mark:SetPoint("TOPLEFT", 0, 0)
	r.mark:SetPoint("BOTTOMLEFT", 0, 0)
	r.mark:SetWidth(2)
	do local a = Okanvil.Colors.accentHi; r.mark:SetVertexColor(a[1], a[2], a[3], 1) end
	r.mark:Hide()

	r.txt = W.Text(r, "", "head")
	r.txt:SetPoint("LEFT", r.t, "RIGHT", 10, 0)
	r.txt:SetPoint("RIGHT", -6, 0)
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
			icon = "Interface\\Icons\\INV_Scroll_03",
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
-- /oknotes test -- run the timers outside a boss room.
--
-- A raider running only the aura has no Okanvil, so nothing gates their pull:
-- any combat starts the note. The leader DOES have Okanvil and is gated by the
-- room check, so without a bypass a two-person test on a target dummy works for
-- one of you and not the other.
--
-- Not saved: it is off again next login.
-- ------------------------------------------------------------
SLASH_OKNOTES1 = "/oknotes"
SlashCmdList["OKNOTES"] = function(msg)
	local arg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

	if arg == "test" then
		N.testMode = not N.testMode
		if N.testMode then
			Okanvil:Print("Notes test mode |cff7cfc8aON|r -- any fight runs |cffe0b860"
				.. (db and db.selected or "?") .. "|r. /oknotes test to stop.")
		else
			Okanvil:Print("Notes test mode |cffff5555OFF|r.")
		end
		return
	end

	if arg == "send" then
		if N.SendNow then N.SendNow() end
		return
	end

	Okanvil:Print("|cffe0b860/oknotes test|r -- run the selected note anywhere (target dummy)")
	Okanvil:Print("|cffe0b860/oknotes send|r -- push your notes to the group now")
	if N.testMode then
		Okanvil:Print("Test mode is |cff7cfc8aON|r.")
	end
end
