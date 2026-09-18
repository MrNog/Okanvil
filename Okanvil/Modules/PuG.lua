-- ============================================================
-- Okanvil -- PuG (native core module).
-- Builds a raid: pick instance/size/difficulty, set how many tanks, healers
-- and DPS you need (plus specific classes), and spam the LFM line on staggered
-- channel timers. Counts what you still need from the LIVE roster, so the
-- message shrinks by itself as people join. Whispers land in an applicant list
-- you can invite from with one click.
-- ============================================================

local Okanvil = Okanvil
local M = {}
Okanvil.PuG = M

local ADDON = "Okanvil-PuG"

-- ------------------------------------------------------------
-- Saved variables
-- ------------------------------------------------------------
local defaults = {
	raid = "icc",
	size = 25,
	hc = false,
	need = { tank = 2, healer = 5, melee = 8, ranged = 10 },  -- targets for the WHOLE raid
	-- Class picks, kept PER ROLE: { tank = { DRUID = true }, ranged = { MAGE = true } }.
	-- One flat set meant picking Tank+Druid and then switching to Ranged threw the
	-- Druid away, so the line could only ever name classes for one role.
	wantClasses = {},
	gs = "",                 -- gearscore requirement, free text ("5.8k"); "" = don't mention
	note = "",               -- tail note appended to the line ("SR>MS>OS", "wsp me")
	reserve = {},            -- { boe = true, orb = true, ... } reserved CATEGORIES
	reserveItems = {},       -- array of item names/links hard-reserved by the leader
	reserveNone = false,     -- advertise "no res" explicitly (louder than saying nothing)
	custom = "",             -- hand-edited message; "" = use the generated one
	useCustom = false,       -- true once the user edits the preview
	-- Extra channel beyond the two built-in ones (name or number). "" = none.
	customChannel = "",
	toGuild = false,
	active = false,
	autoReply = false,       -- whisper back automatically when someone applies
	replyText = "",
	-- Applicants are always collected while spamming -- the Messages window is
	-- where they land. (Kept as a field: older profiles have it.)
	catchWhispers = true,
	-- [name] = { class=, role=, gs=, spec=, msg=, t=, invited=, unread=,
	--            log = { { them=, msg=, t= }, ... } }
	applicants = {},
	assign = {},             -- [name] = "tank"/"healer"/"melee"/"ranged"; the leader's
	                         -- board. Persisted so a /reload mid-forming keeps the comp.
	autoGroup = true,        -- move people into their role's raid group as they accept
	wantRole = "tank",       -- which role's classes the Want row is showing right now
	classRun = false,        -- VoA-style "one of each class" instead of role targets
	classPer = 1,            -- how many of each class a class run wants
	presets = {},            -- [name] = a saved setup (raid, size, needs, note...)
}

local db
local chElapsed = {}        -- per-channel advertise timer accumulators
local replied = {}          -- name -> time we last auto-replied

-- Four buckets, not three: a 25-man comp is built as tank/heal/melee/ranged, and
-- that is how applicants whisper ("melee dk?"). The order here is the order the
-- board columns and the LFM line use.
local ROLES = { "tank", "healer", "melee", "ranged" }
-- how a role is spelled IN THE LFM LINE (short, the way pug spam reads)
local ROLE_SHORT = { tank = "Tank", healer = "Heal", melee = "Melee", ranged = "Ranged" }
M.ROLES = ROLES

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffF1C40F[PuG]|r " .. tostring(msg))
end

-- Cross-realm senders arrive as "Name-Realm"; the invite/whisper APIs and the
-- roster all speak the bare name, so normalise once at the door.
local function stripRealm(name)
	if not name then return name end
	local n = strsplit("-", name)
	return n
end

-- catalogue lookups -------------------------------------------------------
local function raidInfo(key)
	for _, r in ipairs(OkanvilRaids or {}) do
		if r.key == (key or db.raid) then return r end
	end
	return (OkanvilRaids or {})[1]
end

-- "ICC 25 HC" / "ToGC 25" -- the raid token as it goes into the LFM line.
local function raidLabel()
	local r = raidInfo()
	if not r then return "" end
	if db.hc and r.hc then
		local alt = OkanvilRaidHCName and OkanvilRaidHCName[r.key]
		if alt then return alt .. db.size end
		return r.short .. db.size .. " HC"
	end
	return r.short .. db.size
end

-- ------------------------------------------------------------
-- Roster: who is already in the group, by role.
--
-- 3.3.5a has NO GetNumGroupMembers / UnitGroupRolesAssigned (those are Cata+/MoP).
-- The WotLK truth is GetNumRaidMembers() / GetNumPartyMembers(), and the role a
-- raid member is flagged with is the 10th return of GetRaidRosterInfo -- but only
-- in a raid, and only if the leader set it. In a party there is no role data at
-- all, so we fall back to the class-only guess below.
-- ------------------------------------------------------------

-- Classes that CANNOT fill a role, used to keep the guess honest. A rogue is never
-- a healer; a mage is never a tank. Where a class could go either way (paladin,
-- druid, priest...) we cannot tell from class alone and count them as dps, because
-- over-counting tanks/healers would silently stop advertising for them.
local CAN_TANK = { WARRIOR = true, DRUID = true, PALADIN = true, DEATHKNIGHT = true }
local CAN_HEAL = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true }

-- Where a class lands with NO other information. Only the unambiguous ones are
-- listed: a rogue is always melee, a mage always ranged. Hybrids are deliberately
-- absent -- the leader clicks those into place, which is the whole point of the board.
local CLASS_DEFAULT = {
	ROGUE   = "melee",  WARRIOR = "melee",  DEATHKNIGHT = "melee",
	MAGE    = "ranged", WARLOCK = "ranged", HUNTER      = "ranged",
	PRIEST  = "ranged", SHAMAN  = "ranged", DRUID       = "ranged",
	PALADIN = "melee",
}

-- Melee or ranged for a DPS spec. The board splits dps two ways, but a talent
-- tree only says "dps" -- so the spec name decides which side of the board it is.
local MELEE_SPECS = {
	["Retribution"] = true, ["Feral (Cat)"] = true, ["Enhancement"] = true,
	["Arms"] = true, ["Fury"] = true, ["Combat"] = true,
	["Assassination"] = true, ["Subtlety"] = true,
	["Frost"] = true, ["Unholy"] = true,      -- DK trees; the mage Frost is caught
	                                          -- by the class check in specRole()
}

-- Which classes can actually fill a role, in WotLK. Showing all nine classes for
-- every role asked the leader to remember that a mage cannot tank -- so the Want
-- row now offers only the classes that can do the job being asked for.
--
-- Mirrors MELEE_SPECS above: ret, feral, enh, arms/fury, combat/assa/sub,
-- frost/unholy DK. A druid appears in all four because it genuinely has a spec
-- for each.
local ROLE_CLASSES = {
	tank   = { "DEATHKNIGHT", "WARRIOR", "DRUID", "PALADIN" },
	healer = { "PALADIN", "DRUID", "SHAMAN", "PRIEST" },
	melee  = { "DEATHKNIGHT", "WARRIOR", "DRUID", "PALADIN", "SHAMAN", "ROGUE" },
	ranged = { "HUNTER", "MAGE", "WARLOCK", "PRIEST", "SHAMAN", "DRUID" },
}
M.ROLE_CLASSES = ROLE_CLASSES

-- The classes to OFFER for a role. nil/unknown role = all of them, which is what
-- "Any" means on the picker.
function M.ClassesForRole(role)
	local want = ROLE_CLASSES[role or ""]
	local out = {}
	for _, c in ipairs(OkanvilClasses or {}) do
		if not want then
			out[#out + 1] = c
		else
			for _, tok in ipairs(want) do
				if tok == c.token then out[#out + 1] = c; break end
			end
		end
	end
	return out
end

-- What the INSPECTED spec says this player does. nil = we have not inspected them
-- (or the answer is stale), so the caller falls through to its other guesses.
local function specRole(name, class)
	local I = Okanvil.Inspect
	if not (I and I.Get) then return nil end
	local spec, cls, role = I.Get(name)
	if not (spec and role) then return nil end

	if role == "tank" or role == "healer" then return role end

	-- role == "dps": which half of the board?
	if class == "MAGE" or cls == "MAGE" then return "ranged" end   -- Frost mage, not Frost DK
	return MELEE_SPECS[spec] and "melee" or "ranged"
end

-- Best guess for a player we have just seen, most trusted first:
--   1. the leader put them somewhere by hand -- never override that
--   2. their INSPECTED spec -- the only source that is actually about this
--      character rather than a guess about their class
--   3. what they said in their own whisper ("bdk 5.8k")
--   4. the class default, which cannot tell a holy paladin from a ret
function M.GuessRole(name, class)
	if name and db.assign[name] then return db.assign[name] end

	local bySpec = name and specRole(name, class)
	if bySpec then return bySpec end

	local a = name and db.applicants[name]
	if a and a.role then return a.role end

	return (class and CLASS_DEFAULT[class]) or "ranged"
end

-- Put a player in a bucket (nil = back to Unassigned).
function M.Assign(name, role)
	if not name then return end
	db.assign[name] = role
end

function M.AssignedRole(name)
	return name and db.assign[name] or nil
end

-- Click cycles: Unassigned -> tank -> healer -> melee -> ranged -> Unassigned.
function M.CycleRole(name)
	if not name then return end
	local cur = db.assign[name]
	if not cur then db.assign[name] = ROLES[1]; return end
	for i, r in ipairs(ROLES) do
		if r == cur then
			db.assign[name] = ROLES[i + 1]   -- nil past the end = Unassigned
			return
		end
	end
	db.assign[name] = nil
end

-- Everyone in the group right now: { name=, class=, role=, online= }, in raid order.
-- This is the board's data source, so it must be cheap enough to call on every
-- refresh -- it is, GetRaidRosterInfo is a local lookup.
local function rosterList()
	local out = {}
	local n = GetNumRaidMembers and GetNumRaidMembers() or 0
	if n > 0 then
		for i = 1, n do
			local name, _, _, _, _, class, _, online, _, flag = GetRaidRosterInfo(i)
			if name then
				-- The raid's own MAINTANK flag is a real signal, so seed the board with
				-- it the first time we see that player. After that the leader's click wins.
				if flag == "MAINTANK" and db.assign[name] == nil then db.assign[name] = "tank" end
				out[#out + 1] = {
					name = name, class = class, online = online,
					role = M.GuessRole(name, class),
				}
			end
		end
		return out
	end
	-- party (or solo): yourself first, then party1..N
	local _, myClass = UnitClass("player")
	local me = UnitName("player")
	out[1] = { name = me, class = myClass, online = true, role = M.GuessRole(me, myClass) }
	local pn = GetNumPartyMembers and GetNumPartyMembers() or 0
	for i = 1, pn do
		local unit = "party" .. i
		local nm = UnitName(unit)
		if nm then
			local _, cl = UnitClass(unit)
			out[#out + 1] = { name = nm, class = cl, online = UnitIsConnected(unit),
			                  role = M.GuessRole(nm, cl) }
		end
	end
	return out
end
M.RosterList = rosterList

-- ------------------------------------------------------------
-- Role targets can never sum past the raid size: 2 tank + 2 heal + 4 melee in a
-- 10-man leaves exactly 2 ranged, and advertising for more is asking for people
-- you have no room for.
--
-- The role being EDITED always wins -- the leader just said what they want. The
-- surplus comes off the other DPS bucket first (ranged, then melee), because a
-- comp flexes on dps long before it gives up a tank or a healer. Those two are
-- touched only when dps is already at zero and the numbers still do not fit.
-- ------------------------------------------------------------
local function donorOrder(edited)
	-- who gives up slots, in order, when `edited` grows
	local order = { "ranged", "melee", "healer", "tank" }
	local out = {}
	for _, r in ipairs(order) do
		if r ~= edited then out[#out + 1] = r end
	end
	return out
end

-- How many people are already standing in each column. A target can never be
-- pushed BELOW this: "Tank 2/0" -- two tanks in the raid, asking for zero -- is
-- not a state the leader can mean, and it makes the needs strip read "full" while
-- the column plainly has people in it.
local function assignedCounts()
	local have = {}
	for _, r in ipairs(ROLES) do have[r] = 0 end
	for _, p in ipairs(M.RosterList()) do
		local a = db.assign[p.name]
		if a and have[a] then have[a] = have[a] + 1 end
	end
	return have
end
M.AssignedCounts = assignedCounts

-- Trim `over` slots from the donor roles, never below what is already assigned.
-- Returns whatever could not be freed.
local function drain(over, donors, floor)
	for _, donor in ipairs(donors) do
		if over <= 0 then break end
		local cur = tonumber(db.need[donor]) or 0
		local take = math.min(cur - (floor[donor] or 0), over)
		if take > 0 then
			db.need[donor] = cur - take
			over = over - take
		end
	end
	return over
end

-- Set one role's target and rebalance the rest to fit db.size.
function M.SetNeed(role, value)
	if not role or not db.need[role] then return end
	local size = tonumber(db.size) or 25
	local floor = assignedCounts()

	-- The edited role is bounded by what the raid can still hold: the other roles
	-- cannot give up people who are already in them.
	local reserved = 0
	for _, r in ipairs(ROLES) do
		if r ~= role then reserved = reserved + (floor[r] or 0) end
	end
	local ceiling = math.max(floor[role] or 0, size - reserved)
	value = math.max(floor[role] or 0, math.min(tonumber(value) or 0, ceiling))
	db.need[role] = value

	local total = 0
	for _, r in ipairs(ROLES) do total = total + (tonumber(db.need[r]) or 0) end
	drain(total - size, donorOrder(role), floor)
end

-- Switching 25 -> 10 leaves targets that no longer fit (a 25-man comp is 22 too
-- many for a 10-man). Trim from the dps end until it does, same donor order.
function M.FitNeedsToSize()
	local size = tonumber(db.size) or 25
	local floor = assignedCounts()

	-- A target below the number already in that column is meaningless, so raise
	-- any that slipped under before trimming the excess.
	for _, r in ipairs(ROLES) do
		local f = floor[r] or 0
		if (tonumber(db.need[r]) or 0) < f then db.need[r] = f end
	end

	local total = 0
	for _, r in ipairs(ROLES) do total = total + (tonumber(db.need[r]) or 0) end
	drain(total - size, { "ranged", "melee", "healer", "tank" }, floor)
end

-- Counts of who is IN the group right now, per role.
local function rosterCounts()
	local have = {}
	for _, r in ipairs(ROLES) do have[r] = 0 end
	local list = rosterList()
	for _, p in ipairs(list) do
		if p.role then have[p.role] = (have[p.role] or 0) + 1 end
	end
	return have, #list
end
M.RosterCounts = rosterCounts

-- What is STILL missing, per role, clamped at zero.
local function stillNeeded()
	local have = rosterCounts()
	local out = {}
	for _, r in ipairs(ROLES) do
		local want = tonumber(db.need[r]) or 0
		local left = want - (have[r] or 0)
		out[r] = left > 0 and left or 0
	end
	return out
end
M.StillNeeded = stillNeeded

-- ------------------------------------------------------------
-- Presets -- a named setup you can come back to.
--
-- The same handful of runs come round every week (rep farm, weekly, alt run, a
-- VoA class run) and each needs the same instance, size, targets and wording
-- retyped. A preset stores the shape of the run, not the applicants or the board.
-- ------------------------------------------------------------
local PRESET_KEYS = {
	"raid", "size", "hc", "gs", "note", "custom", "useCustom",
	"reserveNone", "classRun", "classPer",
}

function M.SavePreset(name)
	if not name or name == "" then return nil, "no name" end
	db.presets = db.presets or {}
	local p = {}
	for _, k in ipairs(PRESET_KEYS) do p[k] = db[k] end
	-- tables are copied, never referenced: sharing them would make editing the
	-- live setup silently rewrite the preset too
	p.need = {}
	for k, v in pairs(db.need or {}) do p.need[k] = v end
	p.wantClasses = {}
	for k, v in pairs(db.wantClasses or {}) do p.wantClasses[k] = v end
	p.reserve = {}
	for k, v in pairs(db.reserve or {}) do p.reserve[k] = v end
	p.reserveItems = {}
	for i, v in ipairs(db.reserveItems or {}) do p.reserveItems[i] = v end
	db.presets[name] = p
	return p
end

function M.LoadPreset(name)
	local p = db.presets and db.presets[name]
	if not p then return false end
	for _, k in ipairs(PRESET_KEYS) do
		if p[k] ~= nil then db[k] = p[k] end
	end
	db.need = {}
	for k, v in pairs(p.need or {}) do db.need[k] = v end
	db.wantClasses = {}
	for k, v in pairs(p.wantClasses or {}) do db.wantClasses[k] = v end
	db.reserve = {}
	for k, v in pairs(p.reserve or {}) do db.reserve[k] = v end
	db.reserveItems = {}
	for i, v in ipairs(p.reserveItems or {}) do db.reserveItems[i] = v end
	-- A preset saved before the two became mutually exclusive can carry both, and
	-- restoring it verbatim would put the contradiction back. The item wins: it is
	-- the specific claim, and "no res" is the blanket one.
	if #db.reserveItems > 0 then db.reserveNone = false end
	return true
end

function M.DeletePreset(name)
	if db.presets then db.presets[name] = nil end
end

-- names, sorted, for a dropdown
function M.PresetNames()
	local out = {}
	for k in pairs(db.presets or {}) do out[#out + 1] = k end
	table.sort(out)
	return out
end

-- ------------------------------------------------------------
-- Class run (VoA 18 and friends)
--
-- Some runs are not built from roles at all: a VoA "class run" wants one of each
-- class, so it fills at ~18 rather than needing a full 25. Counting tank/heal/
-- melee/ranged answers nothing there -- the question is "which class is still
-- missing?" -- so this is a second way of reading the same roster.
-- ------------------------------------------------------------

-- How many of each class we already have. Keyed by the TOKEN ("PALADIN"), which
-- is what GetRaidRosterInfo and OkanvilClasses both use.
function M.ClassCounts()
	local have = {}
	for _, c in ipairs(OkanvilClasses or {}) do have[c.token] = 0 end
	local list = rosterList()
	for _, p in ipairs(list) do
		local tok = p.class and p.class:upper()
		if tok and have[tok] ~= nil then have[tok] = have[tok] + 1 end
	end
	return have, #list
end

-- Which classes we are still missing, in the picker's own order so the LFM line
-- and the board list them the same way.
function M.ClassesMissing()
	local have = M.ClassCounts()
	local want = tonumber(db.classPer) or 1
	local out = {}
	for _, c in ipairs(OkanvilClasses or {}) do
		if (have[c.token] or 0) < want then
			out[#out + 1] = { token = c.token, short = c.short, name = c.name,
				missing = want - (have[c.token] or 0) }
		end
	end
	return out
end

function M.IsClassRun() return db and db.classRun and true or false end

-- ------------------------------------------------------------
-- Reserved loot
--
-- The categories, letters and wrapper below are NOT invented: they are exactly
-- what RaidFinder-Parser reads out of other people's spam (its letter_cats and
-- word_cats). Emitting the same shape means anyone running Okanvil parses our
-- line correctly -- and so do the humans, since this is the server's idiom.
--   letter form:  "(B+O+P res)"        categories, compact -- what leaders type
--   word form:    "Frags res"          for categories with no conventional letter
--   items:        "HR: [Shadowmourne]" hard-reserved specific drops
-- ------------------------------------------------------------

-- key -> { short letter (nil = spell the word), label for the UI }
-- Order is the order they appear in the line.
local RESERVE_CATS = {
	{ key = "boe",       letter = "B", label = "BoE",       word = "BoE"       },
	{ key = "orb",       letter = "O", label = "Orbs",      word = "Orbs"      },
	{ key = "pattern",   letter = "P", label = "Patterns",  word = "Patterns"  },
	{ key = "frag",      letter = "F", label = "Fragments", word = "Frags"     },
	{ key = "shard",     letter = nil, label = "Shards",    word = "Shards"    },
	{ key = "mount",     letter = nil, label = "Mount",     word = "Mount"     },
	{ key = "quest",     letter = nil, label = "Quest",     word = "Quest"     },
	{ key = "key",       letter = nil, label = "Key",       word = "Key"       },
}
M.ReserveCats = RESERVE_CATS

-- "(B+O+P res)" / "(B+O res + Frags)" / "HR: [Shadowmourne]" / "no res"
local function reserveText()
	-- "no res" and a reserved item are mutually exclusive: setting either one
	-- clears the other, so this says one thing plainly instead of explaining a
	-- contradiction the UI should never have allowed in the first place.
	if db.reserveNone then return "no res" end

	local letters, words = {}, {}
	for _, c in ipairs(RESERVE_CATS) do
		if db.reserve[c.key] then
			if c.letter then letters[#letters + 1] = c.letter
			else words[#words + 1] = c.word end
		end
	end

	local out = {}
	-- ONE "( ... res)" group, letters first then any spelled-out categories:
	-- "(B+O+Mount res)". Two adjacent groups ("(B res) (Mount res)") is not how
	-- anyone writes it, and the parser reads letters and words from the same group
	-- anyway.
	local all = {}
	for _, v in ipairs(letters) do all[#all + 1] = v end
	for _, v in ipairs(words) do all[#all + 1] = v end
	if #all > 0 then
		out[#out + 1] = "(" .. table.concat(all, "+") .. " res)"
	end

	-- Specific hard-reserved drops. "HR" is the server idiom for a named item the
	-- leader keeps, as opposed to a whole category.
	--
	-- Stored entries may be full item LINKS (the reserve picker keeps those so the
	-- UI can colour them and show a tooltip). Chat caps a line at 255 bytes and one
	-- link costs ~65 of them in escape codes against ~18 for the name, so:
	--   ONE item  -> send the LINK. There is room, and a link people can click and
	--               hover is worth far more than the bytes.
	--   TWO+      -> send NAMES. Two links is ~130 bytes of escapes and a third
	--               would push the line past the cap and get it truncated.
	local items = db.reserveItems or {}
	if #items == 1 then
		out[#out + 1] = "HR: " .. items[1]
	elseif #items > 1 then
		local names = {}
		for _, v in ipairs(items) do
			names[#names + 1] = v:match("|h%[(.-)%]|h") or v
		end
		out[#out + 1] = "HR: " .. table.concat(names, " ")
	end

	return table.concat(out, " ")
end
M.ReserveText = reserveText

-- Add / remove a hard-reserved item. Accepts a raw [item link] or a typed name;
-- duplicates are ignored so dragging the same item twice is harmless.
function M.AddReserveItem(text)
	if not text or text == "" then return end
	-- Reserving something contradicts "no res", so claiming an item drops that
	-- claim rather than letting both be true at once.
	db.reserveNone = false
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	for _, v in ipairs(db.reserveItems) do
		if v == text then return end
	end
	table.insert(db.reserveItems, text)
end

function M.RemoveReserveItem(i)
	table.remove(db.reserveItems, i)
end

-- ------------------------------------------------------------
-- Message builder
-- ------------------------------------------------------------
-- The picks for ONE role, as a set. Created on demand so an untouched role costs
-- nothing in the saved file.
--
-- Migration: wantClasses used to be one flat set shared by every role. An old
-- profile is recognised by having class tokens at the top level, and is moved
-- under whichever role was selected at the time.
local function rolePicks(role)
	role = (role and role ~= "" and role) or "tank"
	db.wantClasses = db.wantClasses or {}
	local w = db.wantClasses
	if w[role] == nil or type(w[role]) ~= "table" then
		local flat = nil
		for k, v in pairs(w) do
			if type(v) ~= "table" then flat = flat or {}; flat[k] = v end
		end
		if flat then
			for k in pairs(flat) do w[k] = nil end
			w[db.wantRole or "tank"] = flat
		end
		w[role] = w[role] or {}
	end
	return w[role]
end
M.RolePicks = rolePicks

-- The classes asked for under one role, as "DK/Rogue".
-- Specs first, then plain classes. A leader who ticked both "hpala" and "Pala"
-- means "a holy one especially, but any paladin", and reading the specific ask
-- first is how it gets said out loud.
local function wantText(role)
	local picks = rolePicks(role)
	local want = {}
	for _, s in ipairs(OkanvilClassSpecs or {}) do
		if picks[s.token] then want[#want + 1] = s.short end
	end
	for _, c in ipairs(OkanvilClasses or {}) do
		if picks[c.token] then want[#want + 1] = c.short end
	end
	return table.concat(want, "/")
end

-- "LFM ICC25 HC need 1 Tank (DK/Pala) 2 Heal 5 DPS 5.8k+ gs wsp me"
local function buildMessage()
	local need = stillNeeded()
	local parts = { "LFM", raidLabel() }

	local bits = {}
	if db.classRun then
		-- A class run asks by CLASS, not by role: "need Rogue, Mage" is the whole
		-- point of the run, and role counts say nothing about it.
		for _, c in ipairs(M.ClassesMissing()) do
			bits[#bits + 1] = (c.missing > 1 and (c.missing .. " ") or "") .. c.short
		end
	else
		-- Every role carries its own picks, so one line can say "2 Tank (Druid)
		-- 1 Ranged (Hunter/Mage)". The Want row only shows one role at a time, but
		-- what it shows is a VIEW of the picks -- switching roles no longer throws
		-- the previous role's classes away.
		for _, r in ipairs(ROLES) do
			if need[r] > 0 then
				local bit = need[r] .. " " .. ROLE_SHORT[r]
				local ask = wantText(r)
				if ask ~= "" then bit = bit .. " (" .. ask .. ")" end
				bits[#bits + 1] = bit
			end
		end
	end
	if #bits > 0 then
		parts[#parts + 1] = "need " .. table.concat(bits, " ")
	else
		-- Everything is filled. Saying "need" with nothing after it reads as a typo,
		-- so the line becomes a last-call instead.
		parts[#parts + 1] = "almost full"
	end

	-- A class run asks by class, not by role, so its picks go at the end rather
	-- than beside a role count that does not apply.
	if db.classRun then
		local w = wantText(db.wantRole)
		if w ~= "" then parts[#parts + 1] = "(" .. w .. ")" end
	end

	if db.gs ~= "" then parts[#parts + 1] = db.gs .. "+ gs" end

	local res = reserveText()
	if res ~= "" then parts[#parts + 1] = res end

	if db.note ~= "" then parts[#parts + 1] = db.note end

	return table.concat(parts, " ")
end
M.BuildMessage = buildMessage

-- The line that actually gets sent: the hand-edited one if the user took control.
local function outgoing()
	if db.useCustom and db.custom ~= "" then return db.custom end
	return buildMessage()
end
M.Outgoing = outgoing

-- ------------------------------------------------------------
-- Channels (same resolution Recruit uses: a name may be a number, a live
-- channel, or a prefix like "General" -> "General - Dalaran")
-- ------------------------------------------------------------
local function resolveChannelId(name)
	if not name or name == "" then return nil end
	local asNum = tonumber(name)
	if asNum then return asNum end
	local id = GetChannelName(name)
	if id and id > 0 then return id end
	local list = { GetChannelList() }          -- id1, name1, id2, name2, ...
	local target = name:lower()
	for i = 1, #list - 1, 2 do                  -- exact match first
		if type(list[i + 1]) == "string" and list[i + 1]:lower() == target then
			return list[i]
		end
	end
	for i = 1, #list - 1, 2 do                  -- then prefix
		if type(list[i + 1]) == "string" and list[i + 1]:lower():find(target, 1, true) == 1 then
			return list[i]
		end
	end
	return nil
end

-- Returns true if the line actually went out. A channel the player has not
-- joined has no id, and posting to it is a silent no-op -- the caller needs to
-- know so it can say so rather than pretending it worked.
local function sendTo(name, msg)
	if not name or not msg or msg == "" then return false end
	if name == "GUILD" then
		if IsInGuild and not IsInGuild() then return false end
		SendChatMessage(msg, "GUILD")
		return true
	end
	local id = resolveChannelId(name)
	if id and id > 0 then
		SendChatMessage(msg, "CHANNEL", nil, id)
		return true
	end
	return false
end
M.SendTo = sendTo

-- ------------------------------------------------------------
-- Whisper catcher
--
-- Turns "hi BDK 5.9k" into { class=DEATHKNIGHT, role=tank, spec="Blood", gs=5900 }.
-- The class comes from the whisper's GUID (exact, no inspect); the ROLE is read
-- from what they typed, because only the applicant knows which spec they are
-- bringing. Nothing here is destructive -- a bad guess just mislabels a row the
-- leader can re-click.
-- ------------------------------------------------------------

-- Spec words -> role. Longest/most specific first: "resto" must win before a bare
-- "rs", and "prot" before "pro". Each entry is { pattern, role, label }.
local SPEC_WORDS = {
	-- tanks
	{ "blood%s*dk",   "tank",   "Blood DK"  }, { "bdk",        "tank",   "Blood DK"  },
	{ "prot%s*pal",   "tank",   "Prot Pala" }, { "ppal",       "tank",   "Prot Pala" },
	{ "prot%s*warr",  "tank",   "Prot Warr" }, { "pwar",       "tank",   "Prot Warr" },
	{ "prot",         "tank",   "Prot"      }, { "bear",       "tank",   "Bear"      },
	{ "feral%s*tank", "tank",   "Bear"      }, { "tank",       "tank",   nil         },
	-- healers
	{ "resto%s*sham", "healer", "Resto Sham"}, { "rsham",      "healer", "Resto Sham"},
	{ "resto%s*dru",  "healer", "Resto Dru" }, { "rdru%a*",    "healer", "Resto Dru" },
	{ "rdudu",        "healer", "Resto Dru" },
	{ "holy%s*pal",   "healer", "Holy Pala" }, { "hpal",       "healer", "Holy Pala" },
	{ "holy%s*pri",   "healer", "Holy Pri"  }, { "hpri",       "healer", "Holy Pri"  },
	{ "disc",         "healer", "Disc"      }, { "resto",      "healer", "Resto"     },
	-- "holy" MUST be frontier-anchored: unanchored it matches inside "unholy", and
	-- every Unholy DK who spelled out their spec was classified as a healer.
	{ "%f[%w]holy%f[%W]", "healer", "Holy"  }, { "heal",       "healer", nil         },
	-- dps: each spec already tells us melee or ranged, so classify straight into
	-- the bucket the board uses. A bare "dps" cannot -- that one stays ambiguous
	-- and falls through to the class default.
	-- Unholy sits ABOVE the healer words as well, so "unholy" can never fall
	-- through to a holy match however the table is reordered later.
	{ "unholy",       "melee",  "Unholy"    }, { "%f[%w]uh%f[%W]", "melee", "Unholy" },
	{ "retri%a*",     "melee",  "Ret"       }, { "ret",        "melee",  "Ret"       },
	{ "shadow",       "ranged", "Shadow"    },
	{ "spri",         "ranged", "Shadow"    }, { "boomkin",    "ranged", "Boomkin"   },
	{ "balance",      "ranged", "Boomkin"   }, { "moonkin",    "ranged", "Boomkin"   },
	{ "boomie",       "ranged", "Boomkin"   }, { "boomy",      "ranged", "Boomkin"   },
	{ "enh",          "melee",  "Enh"       }, { "ele",        "ranged", "Ele"       },
	{ "feral",        "melee",  "Cat"       }, { "cat",        "melee",  "Cat"       },
	{ "fury",         "melee",  "Fury"      }, { "arms",       "melee",  "Arms"      },
	{ "udk",          "melee",  "Unholy DK" },
	{ "frost%s*dk",   "melee",  "Frost DK"  },
	{ "%f[%w]mm%f[%W]",     "ranged", "MM"     },
	{ "survival",           "melee",  "Survival" },
	{ "%f[%w]sv%f[%W]",     "melee",  "Survival" },
	{ "%f[%w]bm%f[%W]",     "ranged", "BM"     },
	{ "%f[%w]aff%a*",       "ranged", "Affli"  },
	{ "destro%a*",          "ranged", "Destro" },
	{ "destruct%a*",        "ranged", "Destro" },
	{ "demo",               "ranged", "Demo"   },
	{ "%f[%w]fire%f[%W]",   "ranged", "Fire"   },
	{ "%f[%w]arcane%f[%W]", "ranged", "Arcane" },
	{ "%f[%w]combat%f[%W]", "melee",  "Combat" },
	{ "crogue",             "melee",  "Combat" },
	{ "sub%a*",             "melee",  "Sub"    },
	{ "%f[%w]melee%f[%W]",  "melee",  nil      },
	{ "%f[%w]ranged?%f[%W]","ranged", nil      },
	{ "%f[%w]range%f[%W]",  "ranged", nil      },
	{ "dps",          nil,      nil         },   -- says nothing about melee vs ranged
}

-- Classes that can only ever dps: if no spec word matched, their class alone
-- already decides the bucket (a rogue is melee, a mage is ranged).
local PURE_DPS = { MAGE = true, WARLOCK = true, HUNTER = true, ROGUE = true }

-- "5.8k" / "5800" / "5,8k" -> 5800. Returns nil when the text has no gearscore.
local function parseGS(msg)
	local n, k = msg:match("(%d[%d%.,]*)%s*(k?)")
	if not n then return nil end
	n = n:gsub(",", ".")
	local v = tonumber(n)
	if not v then return nil end
	if k == "k" or v < 100 then v = v * 1000 end
	-- A raid size ("25") or a year is not a gearscore. WotLK GS tops out near 6.5k.
	if v < 1000 or v > 9000 then return nil end
	return math.floor(v)
end
M.ParseGS = parseGS

-- Read an applicant's whisper. class may be nil (GUID missing) -- then the spec
-- word is all we have.
local function classify(msg, class)
	local low = (msg or ""):lower()
	local role, spec
	for _, e in ipairs(SPEC_WORDS) do
		if low:find(e[1]) then
			role, spec = e[2], e[3]
			break
		end
	end
	-- No usable spec word (or a bare "dps"): the class decides the bucket, but only
	-- when it is unambiguous. A rogue whispering "dps" is melee; a paladin doing the
	-- same could be ret or holy, so it stays nil and the leader places them.
	if not role and class then
		if PURE_DPS[class] or (not CAN_TANK[class] and not CAN_HEAL[class]) then
			role = CLASS_DEFAULT[class]
		end
	end
	return role, spec, parseGS(low)
end
M.Classify = classify

-- Record (or update) an applicant. Returns the row.
-- Lines kept per conversation. Enough to see how an exchange went; not so many
-- that a night of pugging bloats the saved file.
local MAX_LOG_LINES = 30

local function addApplicant(name, msg, guid)
	local class
	if guid and GetPlayerInfoByGUID then
		local _, token = GetPlayerInfoByGUID(guid)
		class = token
	end
	local a = db.applicants[name]
	if not a then
		a = { name = name, t = time(), invited = false }
		db.applicants[name] = a
	end
	local role, spec, gs = classify(msg, class or a.class)
	a.class = class or a.class
	a.role  = role or a.role
	a.spec  = spec or a.spec
	a.gs    = gs or a.gs
	a.msg   = msg
	a.t     = time()
	-- Keep the CONVERSATION, not just the last line: the messages window shows
	-- what was said on both sides, and "5.2" three messages later only means
	-- anything next to the "whats your gs?" it answers.
	a.log = a.log or {}
	a.log[#a.log + 1] = { them = true, msg = msg, t = a.t }
	while #a.log > MAX_LOG_LINES do table.remove(a.log, 1) end
	a.unread = (a.unread or 0) + 1
	return a
end

-- Record something WE sent, so the window reads as a conversation rather than a
-- list of their lines with our replies missing.
function M.LogOutgoing(name, msg)
	if not (name and msg and msg ~= "") then return end
	local a = db.applicants[name]
	if not a then return end
	a.log = a.log or {}
	a.log[#a.log + 1] = { them = false, msg = msg, t = time() }
	while #a.log > MAX_LOG_LINES do table.remove(a.log, 1) end
end

-- Send a whisper AND log it. One call so a reply can never land in the chat
-- without showing up in the window that sent it.
function M.Whisper(name, msg)
	if not (name and msg and msg ~= "") then return false end
	SendChatMessage(msg, "WHISPER", nil, name)
	M.LogOutgoing(name, msg)
	return true
end

function M.MarkRead(name)
	local a = db.applicants[name]
	if a then a.unread = 0 end
end

-- Applicants, newest conversation first -- the list in the window is ordered by
-- who spoke last, the way any messages app is.
function M.ApplicantList()
	local out = {}
	for _, a in pairs(db.applicants or {}) do out[#out + 1] = a end
	table.sort(out, function(x, y) return (x.t or 0) > (y.t or 0) end)
	return out
end
M.AddApplicant = addApplicant

function M.RemoveApplicant(name)
	db.applicants[name] = nil
end

function M.ClearApplicants()
	db.applicants = {}
end

-- Applicants as a sorted array (newest first) for the UI to walk.
function M.ApplicantList()
	local out = {}
	for _, a in pairs(db.applicants) do out[#out + 1] = a end
	table.sort(out, function(x, y) return (x.t or 0) > (y.t or 0) end)
	return out
end

function M.InviteApplicant(name)
	if InviteUnit then InviteUnit(name) end
	local a = db.applicants[name]
	if a then a.invited = true end
end

-- ------------------------------------------------------------
-- Engine: staggered per-channel advertising
-- ------------------------------------------------------------
local core = CreateFrame("Frame")

-- Where the line goes. Pug spam lives in General and Global -- that is not a
-- preference worth a row of toggles, so it is fixed. SPAM_EVERY is the interval
-- for both; Global is offset half a cycle in Start() so the two never fire on
-- the same tick (that is what gets a leader muted).
local SPAM_CHANNELS = { "General", "Global" }
local SPAM_EVERY = 60

core:SetScript("OnUpdate", function(self, e)
	if not db or not db.active then return end
	local msg = outgoing()
	if msg == "" then return end

	for _, name in ipairs(SPAM_CHANNELS) do
		chElapsed[name] = (chElapsed[name] or 0) + e
		if chElapsed[name] >= SPAM_EVERY then
			chElapsed[name] = 0
			sendTo(name, msg)
		end
	end
	-- optional extras, set in the More tab
	if db.customChannel ~= "" then
		chElapsed.__custom = (chElapsed.__custom or 0) + e
		if chElapsed.__custom >= SPAM_EVERY then
			chElapsed.__custom = 0
			sendTo(db.customChannel, msg)
		end
	end
	if db.toGuild then
		chElapsed.__guild = (chElapsed.__guild or 0) + e
		if chElapsed.__guild >= SPAM_EVERY then
			chElapsed.__guild = 0
			sendTo("GUILD", msg)
		end
	end
end)

function M.Start()
	if not db then return end
	local msg = outgoing()
	if msg == "" then
		Print("|cffff5555Nothing to advertise|r -- the message is empty.")
		return
	end
	db.active = true
	chElapsed = {}

	-- Post ONCE right now. Waiting a full interval before the first line makes the
	-- button look dead (60s of silence reads as "it did nothing"), and a leader who
	-- just hit START wants the line out now.
	local sent, missing = 0, {}
	for _, name in ipairs(SPAM_CHANNELS) do
		if sendTo(name, msg) then sent = sent + 1 else missing[#missing + 1] = name end
	end
	if db.customChannel ~= "" then
		if sendTo(db.customChannel, msg) then sent = sent + 1 else missing[#missing + 1] = db.customChannel end
	end
	if db.toGuild then sendTo("GUILD", msg) end

	-- then space the repeats out: General on the minute, Global half a cycle later
	for i, name in ipairs(SPAM_CHANNELS) do
		chElapsed[name] = -((i - 1) * (SPAM_EVERY / #SPAM_CHANNELS))
	end

	if sent > 0 then
		Print("Advertising every " .. SPAM_EVERY .. "s: |cffffd200" .. msg .. "|r")
	end
	-- A channel you have not joined cannot be posted to, and silently doing nothing
	-- is the worst outcome -- say which one and how to fix it.
	if #missing > 0 then
		Print("|cffff5555Not in|r " .. table.concat(missing, ", ") ..
			" |cff8a8d93-- join the channel (/join " .. missing[1] .. ") or it will be skipped.|r")
	end
end

function M.Stop()
	if db then db.active = false end
	Print("Advertising stopped.")
end

function M.Toggle()
	if db and db.active then M.Stop() else M.Start() end
end

function M.IsActive() return db and db.active end
function M.DB() return db end

-- Send the line once, right now, everywhere it would normally go.
function M.SendNow()
	local msg = outgoing()
	if msg == "" then
		Print("|cffff5555Nothing to send|r -- the message is empty.")
		return
	end
	local sent, missing = 0, {}
	for _, name in ipairs(SPAM_CHANNELS) do
		if sendTo(name, msg) then sent = sent + 1 else missing[#missing + 1] = name end
	end
	if db.customChannel ~= "" then
		if sendTo(db.customChannel, msg) then sent = sent + 1 else missing[#missing + 1] = db.customChannel end
	end
	if db.toGuild then sendTo("GUILD", msg) end
	if sent == 0 then
		Print("|cffff5555Sent nowhere|r -- not in " .. table.concat(missing, " or ") ..
			". |cff8a8d93Try /join " .. (missing[1] or "General") .. "|r")
	end
end

-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
core:RegisterEvent("CHAT_MSG_WHISPER")

core:SetScript("OnEvent", function(self, event, arg1, arg2, ...)
	if event == "ADDON_LOADED" and arg1 == "Okanvil" then
		OkanvilPuGDB = OkanvilPuGDB or {}
		for k, v in pairs(defaults) do
			if OkanvilPuGDB[k] == nil then
				if type(v) == "table" then
					OkanvilPuGDB[k] = {}
					for kk, vv in pairs(v) do OkanvilPuGDB[k][kk] = vv end
				else
					OkanvilPuGDB[k] = v
				end
			end
		end
		-- Channels are fixed (General + Global) and no longer a saved setting; drop
		-- the old per-channel tables so they cannot linger in the saved file.
		OkanvilPuGDB.channelIntervals = nil
		OkanvilPuGDB.guildInterval = nil

		db = OkanvilPuGDB
		db.active = false          -- never resume spamming across a reload
		-- A profile saved before "no res" and reserved items became mutually
		-- exclusive can hold both. Settle it once, the same way the controls do
		-- now: the named item is the specific claim, so it wins.
		if db.reserveNone and #(db.reserveItems or {}) > 0 then db.reserveNone = false end
		-- Targets saved before the clamp existed can exceed the raid size (a 10-man
		-- sitting at 11). Trim once on load so the very first line is honest.
		M.FitNeedsToSize()
		M.db = db

		Okanvil_Plugins = Okanvil_Plugins or {}
		Okanvil_Plugins[ADDON] = {
			title = "PuG",
			desc = "Build a raid: pick the instance, the roles you need, and spam the LFM line. Whispers become an invite list.",
			icon = "Interface\\Icons\\INV_Misc_GroupLooking",
			build = function(panel) M.BuildUI(panel) end,
			refresh = function() if M.RefreshUI then M.RefreshUI() end end,
		}
		return
	end

	if event == "PLAYER_LOGIN" then
		if not db then return end
		if Okanvil and Okanvil.Register then Okanvil:Register(ADDON) end
		return
	end

	if event == "CHAT_MSG_WHISPER" then
		if not db then return end
		-- module switched off in Modules = stay silent
		if Okanvil.ModuleActive and not Okanvil:ModuleActive(ADDON) then return end
		-- Only act while forming. Off-hours whispers are just chat.
		if not db.active then return end
		-- Applicants are always collected while forming: there IS a window to show
		-- them in now, and a whisper you did not catch is a raider you did not see.
		local msg, sender = arg1, stripRealm(arg2)
		if not sender then return end
		-- CHAT_MSG_* args: 1 msg, 2 sender, ... 11 guid. We already consumed the
		-- first two, so the GUID is the 9th of the rest.
		local guid = select(9, ...)
		addApplicant(sender, msg, guid)
		if M.onApplicant then M.onApplicant(sender) end
		if db.autoReply and db.replyText ~= "" then
			local last = replied[sender]
			if not last or (time() - last) > 60 then
				replied[sender] = time()
				SendChatMessage(db.replyText, "WHISPER", nil, sender)
			end
		end
	end
end)

-- ------------------------------------------------------------
-- Auto-assign: role -> raid group, applied as people accept.
--
-- Inviting a pug meant reading each whisper, inviting, then dragging the name
-- into the right group in the raid frame. The role is already known (the board
-- and the whisper parser agree on tank/healer/melee/ranged), so the drag is
-- work the addon can do.
--
-- SetRaidSubgroup only works on someone already IN the raid, so the move waits
-- for RAID_ROSTER_UPDATE rather than happening at invite time.
-- ------------------------------------------------------------

-- Which groups each role owns. The WotLK standard: a group each for tanks and
-- healers, two each for melee and ranged -- that holds 2-3 tanks, 5-6 healers,
-- and up to 10 of each dps flavour in a 25.
local ROLE_GROUPS = {
	tank   = { 1 },
	healer = { 2 },
	melee  = { 3, 4 },
	ranged = { 5, 6 },
}
M.ROLE_GROUPS = ROLE_GROUPS

-- Only ever move people when it is OUR raid to arrange. Never reshuffle someone
-- else's group.
local function canArrange()
	if (GetNumRaidMembers and GetNumRaidMembers() or 0) == 0 then return false end
	if IsRaidLeader and IsRaidLeader() then return true end
	if IsRaidOfficer and IsRaidOfficer() then return true end
	return false
end

-- name -> raid index, current subgroup
local function raidIndexOf(name)
	local n = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	local want = (name or ""):lower()
	for i = 1, n do
		local rn, _, sub = GetRaidRosterInfo(i)
		if rn and rn:lower() == want then return i, sub end
	end
	return nil
end

-- How many raiders are already sitting in this subgroup.
local function groupCount(g)
	local n = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	local c = 0
	for i = 1, n do
		local _, _, sub = GetRaidRosterInfo(i)
		if sub == g then c = c + 1 end
	end
	return c
end

-- The group this role wants: the first of its groups with room. Returns nil when
-- the role's groups are all full, so we leave the player alone rather than
-- pushing them somewhere arbitrary.
local function groupForRole(role)
	local list = ROLE_GROUPS[role]
	if not list then return nil end
	for _, g in ipairs(list) do
		if groupCount(g) < 5 then return g end
	end
	return nil
end
M.GroupForRole = groupForRole

-- Move ONE raider into their role's group. Returns true when it actually moved.
local function placeOne(name, role)
	if not canArrange() then return false end
	role = role or M.GuessRole(name)
	local want = groupForRole(role)
	if not want then return false end
	local idx, cur = raidIndexOf(name)
	if not idx then return false end          -- not in the raid (yet)
	if cur == want then return false end      -- already where they belong
	if not SetRaidSubgroup then return false end
	SetRaidSubgroup(idx, want)
	return true
end
M.PlaceOne = placeOne

-- Everyone we have a role for, in one pass. Safe to run repeatedly: anyone
-- already in the right group is skipped.
function M.ArrangeRaid()
	if not canArrange() then
		Print("Not in a raid you lead -- nothing to arrange.")
		return 0
	end
	local n = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	local moved = 0
	for i = 1, n do
		local rn, _, _, _, _, class = GetRaidRosterInfo(i)
		if rn then
			-- GuessRole honours a manual board placement first, so arranging can
			-- never undo a decision the leader made by hand.
			if placeOne(rn, M.GuessRole(rn, class and class:upper())) then
				moved = moved + 1
			end
		end
	end
	Print("Arranged " .. moved .. " raider(s) into their role groups.")
	return moved
end

-- As people accept, place them. Only newly-seen names are touched, so someone
-- the leader moved by hand is not dragged back on the next roster event.
local seenInRaid = {}
local aev = CreateFrame("Frame")
aev:RegisterEvent("RAID_ROSTER_UPDATE")
aev:SetScript("OnEvent", function()
	if not db or not db.autoGroup then return end
	if Okanvil.ModuleActive and not Okanvil:ModuleActive(ADDON) then return end
	if not canArrange() then return end
	local n = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	local present = {}
	for i = 1, n do
		local rn, _, _, _, _, class = GetRaidRosterInfo(i)
		if rn then
			present[rn] = true
			if not seenInRaid[rn] then
				seenInRaid[rn] = true
				placeOne(rn, M.GuessRole(rn, class and class:upper()))
			end
		end
	end
	-- forget anyone who left, so a re-invite is placed again
	for rn in pairs(seenInRaid) do
		if not present[rn] then seenInRaid[rn] = nil end
	end
end)

-- ------------------------------------------------------------
-- Slash
-- ------------------------------------------------------------
SLASH_OKPUG1 = "/pug"
SlashCmdList["OKPUG"] = function(arg)
	arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if arg == "start" then M.Start()
	elseif arg == "stop" then M.Stop()
	elseif arg == "send" then M.SendNow()
	elseif arg == "msg" then Print(outgoing())
	else
		-- open the window on our own page (the plugin name IS the panel key)
		if not (Okanvil.win and Okanvil.win:IsShown()) then Okanvil:Toggle() end
		if Okanvil.ShowPanel then Okanvil:ShowPanel(ADDON) end
	end
end
