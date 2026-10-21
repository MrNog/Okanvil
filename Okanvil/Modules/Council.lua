-- ============================================================
-- Okanvil -- Loot Council (stage 2: the raider side).
--
-- WHAT THIS IS. The master looter puts one or more items to the raid and asks
-- "what is this worth to you?". Each raider gets ONE frame listing every item of
-- that round their character can actually equip, answers each with a single
-- click, and the frame goes away. That is the whole feature on a raider's
-- client: no nav row, no window, nothing the rest of the time.
--
-- WHAT IT IS NOT. There is no voting, no quorum and no tally -- RATS decides on
-- voice. The officer board (stage 3) exists to put the facts on screen while
-- they talk, not to compute a winner.
--
-- THE PRIORITY LADDER NEVER REACHES A RAIDER. Not their position, not even that
-- they are on it. Knowing you are queued for an item changes how you answer, and
-- the order is the council's to weigh. Everything this frame shows about an item
-- comes from the raider's OWN character.
--
-- WIRE (over Comms.Ask, so every reply carries a round id):
--   ask payload   ->  <boss> ^ <link> ^ <link> ^ ...
--   reply payload ->  <index>=<response> , <index>=<response> , ...
--                     response is one of the KEYS below, or "na" (not eligible).
--
-- "na" IS SENT, NOT WITHHELD. A client that filtered every item still answers.
-- Without that, silence would mean both "cannot use this" and "has not answered
-- yet", and the count that tells the council whether it can decide would be
-- worthless. It also makes a filter mistake visible instead of a person simply
-- not being there.
-- ============================================================

local Okanvil = Okanvil
local W = Okanvil.W
local C = Okanvil.Comms
local C_ = {}
Okanvil.Council = C_

local TOPIC = "COUNCIL"
local SEP_ITEM = "^"      -- between items in the question
local SEP_ANS  = ","      -- between answers in the reply

-- ------------------------------------------------------------
-- RESPONSES. Mirrors RCLootCouncil's default set (BiS / Big Upgrade / Small
-- Upgrade / Off Spec / Pass) because the raiders' muscle memory is worth
-- matching where it costs nothing.
--
-- The COLOUR is not used on the raider's buttons -- those stay plain, exactly as
-- RCLoot has them. It is the text colour on the officer board, where a BiS row
-- in red against a Pass in grey is read at a glance in a list of ten candidates.
-- ------------------------------------------------------------
-- Order matters and is the order they are read in: strongest claim first, Pass
-- last. Same sequence RCLoot ships, so a raider clicking by muscle memory lands
-- on the same answer they meant.
C_.RESPONSES = {
	{ key = "bis",   label = "BIS",     color = { 0.90, 0.25, 0.25 } },
	{ key = "up",    label = "Upgrade", color = { 0.95, 0.60, 0.20 } },
	{ key = "minor", label = "Small",   color = { 0.90, 0.85, 0.30 } },
	{ key = "os",    label = "OS",      color = { 0.40, 0.65, 0.95 } },
	{ key = "pass",  label = "Pass",    color = { 0.55, 0.57, 0.60 } },
}

-- Rank of each response, for sorting the board. Lower = stronger claim.
local RESP_RANK = {}
for i, r in ipairs(C_.RESPONSES) do RESP_RANK[r.key] = i end

local RESP_BY_KEY = {}
for _, r in ipairs(C_.RESPONSES) do RESP_BY_KEY[r.key] = r end

-- "wait" is not a button: it is the state a candidate is in between being asked
-- and clicking. It IS a real answer on the wire, so the board can show who is
-- still deciding instead of leaving them off the list entirely. Added after both
-- tables exist -- writing it above them indexed a nil global.
RESP_BY_KEY["wait"] = { key = "wait", label = "deciding...", color = { 0.95, 0.85, 0.25 } }
RESP_RANK["wait"]   = 90     -- below every real answer, above "na"

C_.ResponseInfo = function(key) return RESP_BY_KEY[key] end

-- Okanvil.db only exists from ADDON_LOADED onward, and this file is parsed
-- before that. Returning an empty table pre-login keeps the defaults rather than
-- erroring on a nil index -- nothing here is worth a Lua error in someone's raid.
local function db()
	if not Okanvil.db then return {} end
	Okanvil.db.council = Okanvil.db.council or {}
	return Okanvil.db.council
end

-- IS TONIGHT A COUNCIL NIGHT?  Per session, not a stored setting: whether the
-- raid is running a council is a decision about tonight, and a setting is the
-- thing that silently does the wrong thing three weeks later.
--
-- This turns the council BUTTONS on, not the council itself. Nothing is asked of
-- the raid until an item is actually put to it -- a council night still has
-- pieces the ML calls as a plain roll, so both rows sit in the mini roll and each
-- item goes one way or the other.
C_.active = false

-- How long council night, and the answer to "council tonight?", outlive a reload.
-- One raid night at most, never the next one.
local NIGHT_TTL = 3 * 3600

function C_.SetActive(on)
	if on and not C_.MayRun() then
		Okanvil:Print("|cffff5555Loot council:|r only the master looter can start council night.")
		return
	end
	C_.active = on and true or false
	-- Persisted: a /reload in the middle of a raid used to silently end the
	-- council night -- the mini roll came back with no Council row and nothing
	-- said why. Stored with a timestamp so it expires rather than following you
	-- into next week (see the restore on login).
	local d = db()
	d.activeAt = C_.active and time() or nil
	-- Tell the other officers (their header shows it read-only).
	if C and C.Send and C_.MayRun() then
		C.Send("CNIGHT", C_.active and "1" or "0")
		if C_.active and C_.AskEnchanters then C_.AskEnchanters() end
	end
	-- The mini roll draws a different button row depending on this, so it has to
	-- be rebuilt rather than waiting for the next natural refresh.
	if Okanvil.RollMgr and Okanvil.RollMgr.Rebuild then Okanvil.RollMgr.Rebuild() end
	if C_._repaintHeader then pcall(C_._repaintHeader) end
	Okanvil:Print(C_.active
		and "|cffe0b860Loot council:|r ON for this session -- the mini roll now has a Council row."
		or  "|cffe0b860Loot council:|r off -- the mini roll is back to plain rolls.")
end

-- No C_.Timeout any more: nothing counts down. A round ends when the officer
-- ends it, and the board shows who has not answered instead of guessing for
-- them. RCLootCouncil's loot frame has no timer either.

local function enabled()
	if Okanvil.Prof and Okanvil.Prof.SyncEnabled then Okanvil.Prof.SyncEnabled() end
	return not Okanvil.ModuleActive or Okanvil:ModuleActive("__council")
end
C_.Enabled = enabled

-- Who may ASK, and who may look at the board. Same gate the loot-priority UI
-- uses (officers and officers' alts), for the same reason: the board carries the
-- prio ladder and everyone else's answers, and the raider side of this feature
-- is deliberately told neither.
--
-- Declared up here with the other gates: it is used by C_.Ask and the picker,
-- both of which are written well above the board.
local function canSeeBoard()
	-- The MASTER LOOTER always qualifies, guild rank or not. canSeePrio reads the
	-- GUILD roster, so an officer in a pug -- or anyone not in a guild at all --
	-- would be locked out of the tool they are running the raid with. Whoever is
	-- holding the loot is by definition the person deciding it.
	local L = Okanvil.Loot
	if L and L.MasterLooterName then
		local me = UnitName and UnitName("player")
		if me and L.MasterLooterName() == me then return true end
	end
	if not (IsInGuild and IsInGuild()) then return true end   -- no guild = no rank to check
	return not Okanvil.U or not Okanvil.U.canSeePrio or Okanvil.U.canSeePrio()
end
C_.CanSeeBoard = canSeeBoard

-- Who may RUN the council: switch council night on and put items to the raid.
-- In a group, only the master looter -- other officers see the board and vote.
-- Two people asking at once replace each other's popup on every raider.
-- Solo there is nobody to disturb, so solo is always allowed. /okcouncil force
-- lets an officer run it for this session when the master looter cannot.
local function mayRunCouncil()
	local inGroup = (GetNumRaidMembers and GetNumRaidMembers() > 0)
		or (GetNumPartyMembers and GetNumPartyMembers() > 0)
	if not inGroup then return true end
	if C_.forceRun and canSeeBoard() then return true end
	local L = Okanvil.Loot
	local me = UnitName and UnitName("player")
	return (L and L.MasterLooterName and me and L.MasterLooterName() == me) and true or false
end
C_.MayRun = mayRunCouncil

-- ============================================================
-- RAIDER SIDE -- the frame
-- ============================================================

local frame            -- the one reused popup
local current = nil    -- { round, asker, boss, items = { {link, idx, answer} } }

-- Answers are keyed by the item's index IN THE QUESTION, not by link: two copies
-- of the same item are two separate decisions and must not collapse into one.
-- Each answer carries what this character is WEARING in that item's slot, and
-- the ilvl gap between the two:
--
--     <idx>=<response>/<equippedID>/<diff>
--
-- The gear comes from the RAIDER's client because only that client knows it.
-- Inspect stores an aggregate gearscore, not per-slot gear (Inspect.lua), and it
-- cannot scan 25 people mid-boss anyway -- but every client knows its own kit for
-- free. The leader could not compute this column; the raider hands it over.
--
-- The DIFF is the number the council actually argues about: "+39" is a real
-- upgrade, "-6" is someone fishing for an offset piece. RCLoot puts the same
-- figure on its voting frame.
-- Equip location -> inventory slot NAMES, copied from RCLootCouncil
-- (core.lua INVTYPE_Slots). Named slots resolved through GetInventorySlotInfo,
-- not hardcoded numbers: the numbers are the thing that silently returns the
-- wrong slot when one is off by one, and this table has been right on this
-- client for years.
local INVTYPE_SLOTS = {
	INVTYPE_HEAD           = "HeadSlot",
	INVTYPE_NECK           = "NeckSlot",
	INVTYPE_SHOULDER       = "ShoulderSlot",
	INVTYPE_CLOAK          = "BackSlot",
	INVTYPE_CHEST          = "ChestSlot",
	INVTYPE_ROBE           = "ChestSlot",
	INVTYPE_WRIST          = "WristSlot",
	INVTYPE_HAND           = "HandsSlot",
	INVTYPE_WAIST          = "WaistSlot",
	INVTYPE_LEGS           = "LegsSlot",
	INVTYPE_FEET           = "FeetSlot",
	INVTYPE_SHIELD         = "SecondaryHandSlot",
	INVTYPE_2HWEAPON       = { "MainHandSlot", "SecondaryHandSlot" },
	INVTYPE_WEAPONMAINHAND = "MainHandSlot",
	INVTYPE_WEAPONOFFHAND  = { "SecondaryHandSlot", ["or"] = "MainHandSlot" },
	INVTYPE_WEAPON         = { "MainHandSlot", "SecondaryHandSlot" },
	INVTYPE_THROWN         = { "RangedSlot" },
	INVTYPE_RANGED         = { "RangedSlot" },
	INVTYPE_RANGEDRIGHT    = { "RangedSlot" },
	INVTYPE_FINGER         = { "Finger0Slot", "Finger1Slot" },
	INVTYPE_HOLDABLE       = { "SecondaryHandSlot", ["or"] = "MainHandSlot" },
	INVTYPE_TRINKET        = { "TRINKET0SLOT", "TRINKET1SLOT" },
	INVTYPE_RELIC          = { "RangedSlot" },
}

-- The link equipped in `slotName`, or nil.
local function linkInSlot(slotName)
	if not slotName or not GetInventorySlotInfo then return nil end
	local ok, id = pcall(GetInventorySlotInfo, slotName)
	if not ok or not id then return nil end
	return GetInventoryItemLink and GetInventoryItemLink("player", id)
end

-- Both items this one would replace (two for rings/trinkets/weapons), following
-- RCLoot's GetPlayersGear: the `or` fallback covers an off-hand compared against
-- the main hand when nothing is in the off-hand.
local function gearFor(link)
	local equip = select(9, GetItemInfo(link))
	local slot = equip and INVTYPE_SLOTS[equip]
	if not slot then return nil, nil end
	if type(slot) == "string" then return linkInSlot(slot), nil end
	local i1 = linkInSlot(slot[1])
	if not i1 and slot["or"] then i1 = linkInSlot(slot["or"]) end
	local i2 = slot[2] and linkInSlot(slot[2]) or nil
	return i1, i2
end

-- The one this item would actually replace: the WEAKER of the two, since that is
-- the one a raider swaps out. Returns id + ilvl for the wire, plus the id of
-- the OTHER item in a two-slot pair (rings, trinkets, weapons).
local function equippedFor(link)
	local a, b = gearFor(link)
	local bestID, bestIlvl, otherID
	-- Checked one at a time, not through ipairs{a, b}: ipairs stops at the first
	-- nil, so an empty main hand would have hidden a real off-hand.
	for _, have in pairs({ a or false, b or false }) do
		if have then
			local hl = select(4, GetItemInfo(have))
			local id = Okanvil.U.itemIDFromLink(have)
			if hl and (not bestIlvl or hl < bestIlvl) then
				otherID = bestID
				bestIlvl = hl
				bestID = id
			else
				otherID = id
			end
		end
	end
	return bestID, bestIlvl, otherID
end

-- A Mark of Sanctification has no slot to compare: it upgrades a T10 piece, the
-- normal mark 251 -> 264 and the heroic one 264 -> 277. What the council wants is
-- which pieces it would upgrade, so the value is the item level the piece has now.
local MARK_FROM = {
	[52025] = 251, [52026] = 251, [52027] = 251,   -- Vanquisher's / Protector's / Conqueror's
	[52028] = 264, [52029] = 264, [52030] = 264,   -- the same three, heroic
}
local TIER_SLOTS = { "HeadSlot", "ShoulderSlot", "ChestSlot", "HandsSlot", "LegsSlot" }

-- A set piece shows its set as "Name (2/5)"; Wrathful PvP sets carry resilience
-- and share the 264 item level, so those are left out.
local setPattern, resilPattern
local tierTip
local function isTierPiece(link)
	if not setPattern then
		setPattern = "^" .. Okanvil.U.escPattern(ITEM_SET_NAME or "%s (%d/%d)")
			:gsub("%%%%s", ".+"):gsub("%%%%d", "%%d+") .. "$"
		local r = (ITEM_MOD_RESILIENCE_RATING or "Resilience Rating")
			:gsub("%%[sd]", ""):gsub("^%+%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
		resilPattern = Okanvil.U.escPattern(r ~= "" and r or "Resilience")
	end
	if not tierTip then
		tierTip = CreateFrame("GameTooltip", "OkanvilCouncilTierTip", nil, "GameTooltipTemplate")
	end
	tierTip:SetOwner(UIParent, "ANCHOR_NONE")
	tierTip:ClearLines()
	if not pcall(tierTip.SetHyperlink, tierTip, link) then return false end
	local inSet = false
	for i = 2, tierTip:NumLines() do
		local fs = _G["OkanvilCouncilTierTipTextLeft" .. i]
		local t = fs and fs:GetText()
		if t then
			if t:find(resilPattern) then return false end
			if t:find(setPattern) then inSet = true end
		end
	end
	return inSet
end

-- The equipped T10 pieces this mark would upgrade, as item ids, and the ones it
-- already did (a tier piece above the mark's starting item level), so the council
-- sees "3 done, 1 to go" rather than only the one left.
local function tierToUpgrade(link)
	local from = MARK_FROM[Okanvil.U.itemIDFromLink(link)]
	if not from then return nil end
	local out, done = {}, {}
	for _, slot in ipairs(TIER_SLOTS) do
		local have = linkInSlot(slot)
		local ilvl = have and select(4, GetItemInfo(have))
		if ilvl and ilvl >= from and isTierPiece(have) then
			local list = (ilvl == from) and out or done
			list[#list + 1] = Okanvil.U.itemIDFromLink(have)
		end
	end
	return out, done
end

-- Our Enchanting skill, or nil. Asked ONCE, when the master looter starts council
-- night (ENCQ below), so their Disenchant list shows the raid's enchanters,
-- highest skill first, the way RCLootCouncil's does. The skill line is matched by
-- the localised name of the Enchanting spell, so it works on any client language.
local ENCHANTING = GetSpellInfo and GetSpellInfo(7411)
local function enchantSkill()
	if not (ENCHANTING and GetNumSkillLines and GetSkillLineInfo) then return nil end
	for i = 1, GetNumSkillLines() do
		local name, header, _, rank = GetSkillLineInfo(i)
		if not header and name == ENCHANTING then return rank end
	end
	return nil
end

local function buildReply()
	if not current then return "" end
	local parts, second = {}, {}
	for _, it in ipairs(current.items) do
		local eqID, eqIlvl, otherID = equippedFor(it.link)
		local newIlvl = select(4, GetItemInfo(it.link))
		local diff = (eqIlvl and newIlvl) and (newIlvl - eqIlvl) or ""
		-- a mark sends the pieces it would upgrade as "T<id>+<id>" in the gear
		-- field; an older board reads that as no item, which is what it showed anyway
		local tier, done = tierToUpgrade(it.link)
		if tier then
			-- a bare "T" = checked, no tier; the board tells that apart from an
			-- older client that sent nothing
			eqID = "T" .. table.concat(tier, "+")
			diff = ""
			otherID = nil
			-- pieces already sanctified ride in their own "D<idx>=<id>+<id>" part,
			-- which an older board's parser skips
			if #done > 0 then second[#second + 1] = ("D%d=%s"):format(it.idx, table.concat(done, "+")) end
		end
		-- The other ring/trinket rides in its own "S<idx>=<id>" part, which an
		-- older board's parser skips, so the main field keeps its old meaning.
		if otherID then second[#second + 1] = ("S%d=%s"):format(it.idx, otherID) end
		parts[#parts + 1] = ("%d=%s/%s/%s"):format(
			-- "wait", NOT "pass", for an item this raider has not answered yet.
			-- Defaulting to pass told the board they had declined every item the
			-- moment they answered ONE of them -- the council saw Pass against a
			-- name that had not decided anything. RCLootCouncil sends the same
			-- distinction (its WAIT response, "candidate is selecting").
			it.idx, it.answer or "wait", eqID or "", tostring(diff))
	end
	for _, p in ipairs(second) do parts[#parts + 1] = p end
	return table.concat(parts, SEP_ANS)
end

-- Forward-declared: sendReply below persists the round after every click, but
-- saveRound needs the round's shape and is written further down with the rest of
-- the reload handling. `function saveRound()` there assigns into THIS local.
local saveRound

-- Send what we have so far. Called on every click rather than only at the end:
-- a raider who answers two items then disconnects has still told the council
-- about those two, and the re-broadcast (stage 2b) would otherwise be the only
-- thing that ever carried them.
local function sendReply()
	if not current or not current.asker or not current.round then return end
	-- Carries the "na" items too: the council's count is only trustworthy if a
	-- filtered item is reported, not merely absent.
	local body = buildReply()
	if current.na and #current.na > 0 then
		body = body .. (body ~= "" and SEP_ANS or "") .. table.concat(current.na, SEP_ANS)
	end
	-- BROADCAST, not a whisper to the asker. A council is more than one person:
	-- every officer in the raid needs the answers to argue about them, and
	-- whispering only the master looter meant the board existed on exactly one
	-- client.
	--
	-- Sent to the group, where every Okanvil sees it; the ones that are not
	-- running a round simply have no such round and drop it. Solo (no group) the
	-- send no-ops, so the local delivery below is the only path -- which is what
	-- makes test mode work.
	if not C.Send("ANS", TOPIC, current.round, body) then
		C.Reply(current.asker, TOPIC, current.round, body)
	end
	-- Persist after every click, not just at the end: a raider who answers two
	-- items and then disconnects has still told the council about those two.
	saveRound()
	C_.RememberRound(current.round, current.asker, body)
end

-- ------------------------------------------------------------
-- SURVIVING A RELOAD.
--
-- Round state used to live only in memory, on several clients at once -- so a
-- /reload between the broadcast and the answer simply lost it: the raider's
-- popup never came back and the leader's board waited for ever on someone whose
-- client had forgotten the round existed. That is the failure RATS already lives
-- with in RCLootCouncil, and it is not acceptable to ship it again.
--
-- The open round is written to SavedVariables on every change and restored on
-- login. It is deliberately stored in the ACCOUNT db (Okanvil_DB) rather than a
-- new file: no .toc change, nothing to migrate.
--
-- A stale round is dropped on load. An hour-old question is not a live council,
-- and restoring one would put a popup on screen for an item handed out long ago.
-- Fifteen minutes. A council round is decided in minutes; an hour-long window
-- meant a reload well after the raid restored a question about an item that had
-- long since been handed out.
local ROUND_TTL = 900

-- ROUNDS THIS CLIENT HAS ALREADY ANSWERED, with the last reply sent for each.
-- The asker re-broadcasts a round several times in case a packet was dropped.
-- Once the frame has closed (everything answered) or a newer question replaced
-- it, `current` no longer names that round -- so without this list the repeat
-- looked like a brand-new question: the frame popped back open and "deciding..."
-- went out for every item, wiping the answers off every board.
--
-- Stored in the account db so a /reload between the answer and the repeat
-- does not forget it either.
function C_.RememberRound(round, asker, body)
	if not round then return end
	local d = db()
	d.pastRounds = d.pastRounds or {}
	local now = time()
	for r, p in pairs(d.pastRounds) do
		if (now - (p.at or 0)) > ROUND_TTL then d.pastRounds[r] = nil end
	end
	d.pastRounds[round] = { asker = asker, body = body, at = now }
end

local function pastRound(round)
	local p = round and db().pastRounds and db().pastRounds[round]
	if p and (time() - (p.at or 0)) <= ROUND_TTL then return p end
	return nil
end

-- Defined here but forward-declared above, so sendReply (which runs on every
-- click, further up the file) calls THIS function and not a nil global. The same
-- shape Loot.lua uses for runKey.
function saveRound()
	local d = db()
	if not current then d.openRound = nil; return end
	local items = {}
	for i, it in ipairs(current.items) do
		items[i] = { idx = it.idx, link = it.link, answer = it.answer,
			slotText = it.slotText, owned = it.owned }
	end
	d.openRound = {
		round = current.round, asker = current.asker, boss = current.boss,
		items = items, na = current.na, savedAt = time(),
		-- Whose round this is, and where. The db is account-wide, so without the
		-- name an alt logging in would be shown a popup for a question asked of
		-- another character; without the zone, a round opened in ICC came back in
		-- the next 5-man.
		who  = UnitName and UnitName("player") or "?",
		zone = (GetRealZoneText and GetRealZoneText()) or "",
	}
end

local function closeFrame()
	current = nil
	if frame then frame:Hide() end
	local d = db()
	d.openRound = nil
end

-- NO TIMER. The frame used to auto-pass everything when a clock ran out, which
-- RCLootCouncil does not do and which was the wrong pressure: a council decides
-- when it has heard enough, and a raider reading two tooltips should not lose
-- their say to a countdown. The round ends when the officer ends it.

-- Row geometry. Sized from RCLootCouncil's loot frame, which RATS raiders have
-- been clicking for years: a 36px icon, the name and ilvl stacked beside it, and
-- the five responses on their own line underneath. The point is that the item is
-- readable at a glance -- the name, what slot it is, and how big an upgrade --
-- before anyone reaches for a button.
-- Sized to read at a glance from across the room mid-raid, the way RCLoot's loot
-- frame and Okanvil's own Loot Prio page do. A council frame that has to be
-- squinted at during a pull is one people click through without reading.
local ICON_S  = 44
local BTN_W   = 96
local BTN_H   = 26
local BTN_GAP = 6
local ROW_PAD = 12
local ROW_H   = ICON_S + BTN_H + ROW_PAD * 2 + 14
local FRAME_W = ROW_PAD * 4 + (BTN_W * 5) + (BTN_GAP * 4)
local HEAD_H  = 60      -- header bar + the boss line
local FOOT_H  = 46

local function ensureFrame()
	if frame then return frame end

	local f = Okanvil:Popup("Loot council")
	-- Out of the one-popup slot: this frame and the board are on screen together,
	-- and creating one must not close the other.
	Okanvil:SetPopup(nil)
	f:SetWidth(FRAME_W)
	f:SetHeight(200)
	-- Above the loot window and the mini roll, below Confirm (which is
	-- FULLSCREEN_DIALOG) so an award confirmation is never buried.
	--
	-- Levels within DIALOG, because the mini roll is there too and same-level
	-- frames have no defined order -- that is what made windows draw through
	-- each other. mini roll 10 < board 20 < raider frame 30.
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(30)
	-- Right of centre, high on the screen: clear of the board on the far left,
	-- but not jammed against the screen edge. Both windows move by their title
	-- bar, so this is only where they start.
	f:SetPoint("CENTER", UIParent, "CENTER", 260, 220)

	-- NEVER take keyboard focus. A captured EditBox eats WASD and someone has
	-- died to that before; this frame has no edit box at all and must not start
	-- grabbing keys if one is ever added.
	f:EnableKeyboard(false)

	-- Mouse wheel scrolls the item list when it does not all fit.
	f._scrollTop = 1
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(self, delta)
		if not (self._total and self._maxRows) then return end
		if self._total <= self._maxRows then return end
		local top = (self._scrollTop or 1) - delta      -- wheel up = earlier items
		local maxTop = self._total - self._maxRows + 1
		if top < 1 then top = 1 elseif top > maxTop then top = maxTop end
		if top == self._scrollTop then return end
		self._scrollTop = top
		C_.Repaint()
	end)

	-- The header used to carry a countdown; there is no clock any more.

	-- The boss line. The window title already says "Loot council", so this says
	-- WHICH kill -- printing the same words twice told the raider nothing.
	local sub = W.Text(f, "", nil, "dim")
	sub:SetPoint("TOPLEFT", ROW_PAD + 2, -38)
	f.sub = sub

	f.rows = {}

	-- Footer. The hint is anchored to the LEFT of the button rather than to the
	-- frame edge, so a long sentence is clipped by its own anchor instead of
	-- running underneath "Pass all" (which is what it did).
	-- No "Change answer" button. An answered item leaves the frame and answering
	-- the last one closes it, so the button was only ever live in the gap between
	-- two answers of a multi-item round -- a control that is usually dead is worse
	-- than no control. A mis-click is corrected by the council, on voice.
	local passAll = W.Button(f, "Pass all")
	passAll:SetSize(84, 22)
	passAll:SetPoint("BOTTOMRIGHT", -ROW_PAD, 14)

	local foot = W.Text(f, "Answer what you want; the council decides when it has heard enough.", "note", "dim")
	foot:SetPoint("BOTTOMLEFT", ROW_PAD + 2, 19)
	foot:SetPoint("RIGHT", passAll, "LEFT", -8, 0)
	foot:SetJustifyH("LEFT")
	if foot.SetWordWrap then foot:SetWordWrap(false) end
	f.foot = foot
	passAll:SetScript("OnClick", function()
		if not current then return end
		for _, it in ipairs(current.items) do it.answer = "pass" end
		sendReply()
		C_.Repaint()
		closeFrame()
	end)

	-- No OnUpdate: nothing counts down any more.

	frame = f
	return f
end

-- One row per item: icon, link, slot, and the five response buttons. An answered
-- row collapses to its answer so what is left to do is what still shows buttons;
-- clicking the answer re-opens the row while the round is open.
local function ensureRow(i)
	local f = ensureFrame()
	if f.rows[i] then return f.rows[i] end

	local row = CreateFrame("Frame", nil, f)
	row:SetPoint("TOPLEFT", ROW_PAD, -(HEAD_H + (i - 1) * ROW_H))
	row:SetPoint("TOPRIGHT", -ROW_PAD, -(HEAD_H + (i - 1) * ROW_H))
	row:SetHeight(ROW_H - 4)

	-- A recessed well behind each row, so two items read as two blocks rather
	-- than one wall of text. "dark" is the palette's recessed fill (panelD).
	Okanvil:Skin(row, "soft")

	-- the item in the gold octagon frame (the UI kit's framed icon)
	local slot = W.FramedIcon(row, nil, ICON_S, true)
	slot:SetPoint("TOPLEFT", ROW_PAD, -ROW_PAD)
	local icon = slot.icon
	row.icon = icon

	-- The item name is a real link: hover for the tooltip, shift-click to put it
	-- in chat, exactly as anywhere else in the game.
	local name = CreateFrame("Button", nil, row)
	name:SetPoint("TOPLEFT", ROW_PAD + ICON_S + 10, -ROW_PAD)
	name:SetPoint("TOPRIGHT", -ROW_PAD, -ROW_PAD)
	name:SetHeight(20)
	-- The item name is the thing being decided, so it gets the largest text in
	-- the row -- one size up from body.
	local nameText = W.Text(name, "", "head")
	nameText:SetPoint("LEFT", 0, 0)
	nameText:SetJustifyH("LEFT")
	row.nameText = nameText

	-- Second line: ilvl, slot and armour type -- the facts RCLoot puts under the
	-- name, and the ones a raider actually weighs before answering.
	local meta = W.Text(row, "", "body", "dim")
	meta:SetPoint("TOPLEFT", ROW_PAD + ICON_S + 10, -ROW_PAD - 22)
	meta:SetJustifyH("LEFT")
	row.meta = meta

	-- The "you are already wearing this" warning, on its own so it can be shown
	-- and hidden without rebuilding the name string.
	local warn = W.Text(row, "", "body")
	warn:SetPoint("TOPRIGHT", -ROW_PAD, -ROW_PAD)
	warn:SetJustifyH("RIGHT")
	warn:SetTextColor(0.45, 0.85, 0.5)
	row.warn = warn
	-- Opens to the RIGHT of the whole frame, clear of the response buttons. An
	-- ANCHOR_RIGHT on the name itself covered the row below it -- including the
	-- buttons the raider was reaching for.
	name:SetScript("OnEnter", function(self)
		if not row._link then return end
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint("TOPLEFT", f, "TOPRIGHT", 8, 0)
		GameTooltip:SetHyperlink(row._link)
		GameTooltip:Show()
	end)
	name:SetScript("OnLeave", function() GameTooltip:Hide() end)
	name:SetScript("OnClick", function()
		if row._link and IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(row._link) end
	end)
	row.nameBtn = name

	-- The five response buttons, on their own line under the icon so they get the
	-- full row width instead of being squeezed beside the name.
	row.btns = {}
	local x = ROW_PAD
	for _, r in ipairs(C_.RESPONSES) do
		local b = W.Button(row, r.label)
		if r.key == "bis" then b:SetMain(true) end
		b:SetSize(BTN_W, BTN_H)
		b:SetPoint("TOPLEFT", x, -(ROW_PAD + ICON_S + 10))
		b:SetScript("OnClick", function()
			-- The row's CURRENT item, not items[i]: rows are reused and re-filled
			-- as answered items drop out, so a fixed index would answer the wrong
			-- item as soon as the list shifted up.
			local it = row._item
			if not it then return end
			it.answer = r.key
			sendReply()
			C_.Repaint()
			-- Every item answered -> nothing left to ask. Close rather than making
			-- them find the X; the answers are already on the wire.
			local done = true
			for _, o in ipairs(current.items) do
				if not o.answer then
					done = false
					break
				end
			end
			if done then
				Okanvil:Print("|cffe0b860Loot council:|r answers sent.")
				closeFrame()
			end
		end)
		row.btns[#row.btns + 1] = b
		x = x + BTN_W + BTN_GAP
	end

	f.rows[i] = row
	return row
end

-- Redraw from `current`. Kept separate from the click handlers so the same code
-- paints a fresh round, a re-opened row and a restored round after a reload.
function C_.Repaint()
	if not current then return end
	local f = ensureFrame()

	-- The title bar already says "Loot council". This line says WHICH kill, or --
	-- with no boss, how many items are being asked about. Repeating the title here
	-- (which it used to) told the raider nothing.
	local n = #current.items
	f.sub:SetText(current.boss ~= "" and current.boss
		or (("%d item%s"):format(n, n == 1 and "" or "s")))

	-- ONLY THE UNANSWERED ITEMS, the way RCLoot's loot frame works: answering a
	-- row removes it and the window shrinks to what is left. Collapsing the row
	-- in place instead kept a dead row on screen for the rest of the round, and
	-- the frame never got smaller however much you answered.
	local pending = {}
	for _, it in ipairs(current.items) do
		if not it.answer then pending[#pending + 1] = it end
	end
	-- SCROLLED, not capped. Twelve items is 12 x 92px of rows, taller than the
	-- screen, and a frame that grows past the bottom takes Pass all with it.
	--
	-- `scrollTop` is the index of the first row drawn; the mouse wheel moves it.
	-- Only the visible slice is painted, so the frame height is fixed by what
	-- fits rather than by how much was asked about.
	local total = #pending
	local avail = ((UIParent:GetHeight() or 768) * 0.70) - HEAD_H - FOOT_H
	local maxRows = math.max(2, math.floor(avail / ROW_H))
	if maxRows > total then maxRows = total end

	-- Clamp: answering items shrinks the list under the window, so a stale
	-- scrollTop would leave the frame showing nothing.
	local maxTop = math.max(1, total - maxRows + 1)
	if (f._scrollTop or 1) > maxTop then f._scrollTop = maxTop end
	if (f._scrollTop or 1) < 1 then f._scrollTop = 1 end
	local top = f._scrollTop or 1

	local slice = {}
	for i = 1, maxRows do slice[i] = pending[top + i - 1] end
	pending = slice
	n = #pending

	f._total, f._maxRows = total, maxRows

	f.sub:SetText(current.boss ~= "" and current.boss
		or (("%d item%s left"):format(total, total == 1 and "" or "s")))
	if total > maxRows then
		f.foot:SetText(("%d-%d of %d  |cff6f7176scroll|r"):format(
			top, top + n - 1, total))
	else
		f.foot:SetText("Answer what you want; the council decides when it has heard enough.")
	end

	-- Bound taken BEFORE the loop: ensureRow appends to f.rows as it builds, so
	-- reading #f.rows inside the loop grows the range while iterating it. Rows
	-- left over from a previous paint must still be hidden, which is the max.
	local built = #f.rows
	for i = 1, math.max(n, built) do
		local row = f.rows[i]
		if i > n then
			if row then row:Hide() end
		else
			row = ensureRow(i)
			local it = pending[i]
			row._item = it
			row._link = it.link
			row:Show()

			local iname, _, quality, ilvl, _, _, itemSub = GetItemInfo(it.link)
			local icon = select(10, GetItemInfo(it.link)) or (GetItemIcon and GetItemIcon(it.link))
			if icon then row.icon:SetTexture(icon) end

			-- Colour the name by rarity, the way the rest of Okanvil does.
			local hex = "|cffffffff"
			if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
				hex = "|c" .. ITEM_QUALITY_COLORS[quality].hex:gsub("^|c", "")
			end
			row.nameText:SetText(hex .. (iname or it.link) .. "|r")

			-- ilvl first: it is the number that decides most of these answers, and
			-- RCLoot puts it in the same place, so the habit carries over.
			local bits = {}
			if ilvl and ilvl > 0 then bits[#bits + 1] = "ilvl " .. ilvl end
			if (it.slotText or "") ~= "" then bits[#bits + 1] = it.slotText end
			if itemSub and itemSub ~= "" and itemSub ~= it.slotText then bits[#bits + 1] = itemSub end
			row.meta:SetText(table.concat(bits, "  |cff4a4d52|||r  "))

			-- ALREADY WEARING IT. Green, matching RCLoot -- it is information about
			-- the raider's own gear, not a warning that they did something wrong.
			-- Nothing here comes from the prio list.
			row.warn:SetText(it.owned and "you already have this" or "")

			-- Collapsed vs open is decided fresh every paint. Rows are REUSED between
			-- rounds, so a row still showing last round's answer button would sit
			-- there as an empty box over this round's five responses.
			-- Every row on screen is unanswered by definition now, so the buttons are
			-- always the five responses. The collapsed "your answer" state is gone
			-- with the row itself.
			for _, b in ipairs(row.btns) do b:Show() end
		end
	end

	f:SetWidth(FRAME_W)
	f:SetHeight(HEAD_H + n * ROW_H + FOOT_H)
end

-- ------------------------------------------------------------
-- "Do I already have one of these equipped?"  Compares by item id across the
-- slot the item goes in. Deliberately cheap: this is a hint, not a rule.
-- ------------------------------------------------------------
local function alreadyOwned(link)
	local id = Okanvil.U.itemIDFromLink(link)
	if not id or id == 0 then return false end
	-- Reuses gearFor, so "what am I wearing here" is answered by ONE table. The
	-- old numeric SLOT_IDS copy is gone.
	local a, b = gearFor(link)
	if a and Okanvil.U.itemIDFromLink(a) == id then return true end
	if b and Okanvil.U.itemIDFromLink(b) == id then return true end
	return false
end

-- Is this item one to ask me about? Anything my class can put on -- its own
-- armour or lighter (plate > mail > leather > cloth), weapons it holds, its tier
-- tokens -- whose stats suit a spec of my class: no Intellect plate for a
-- warrior, no caster cloth for a death knight, no spell-power neck for a rogue.
-- Any spec of the class, not just my two: talents change between raids. The
-- same BiS lists and stat rules as the item tooltip's stars.
local function fitsClass(link, cls)
	local P = Okanvil.Prof
	if not P then return true end
	local can = true
	if P.CanEquip then can = P.CanEquip(link, cls) elseif P.CanIUse then can = P.CanIUse(link) end
	if can then
		local U = Okanvil.Upgrades
		if U and U.FitsAnySpec then
			can = U.FitsAnySpec(link, cls)
		elseif P.FitsEitherSpec then
			can = P.FitsEitherSpec(link)
		end
	end
	return can and true or false
end

-- The classes each asked item suits, worked out on the master looter's client:
-- the item is on the corpse there, so its stats are known. A raider's client
-- often has not cached a fresh drop when the question lands, and an uncached
-- item used to reach every class. One character per class on the wire.
local CLASS_CH = { DEATHKNIGHT = "1", DRUID = "2", HUNTER = "3", MAGE = "4", PALADIN = "5",
	PRIEST = "6", ROGUE = "7", SHAMAN = "8", WARLOCK = "9", WARRIOR = "0" }
local fitFromML = {}     -- item id -> the class characters it suits

-- "50682=1250;50633=4689": only items cached here; the rest a raider judges itself.
local function classFitPayload(ids)
	local parts = {}
	for _, id in ipairs(ids) do
		local link = select(2, GetItemInfo(id))
		if link then
			local chars = {}
			for cls, ch in pairs(CLASS_CH) do
				if fitsClass(link, cls) then chars[#chars + 1] = ch end
			end
			table.sort(chars)
			parts[#parts + 1] = id .. "=" .. table.concat(chars)
		end
	end
	return table.concat(parts, ";")
end

local function readClassFit(body)
	fitFromML = {}
	for id, chars in (body or ""):gmatch("(%d+)=(%d*)") do fitFromML[tonumber(id)] = chars end
end

-- Is this item one to ask me about? The master looter's answer when it sent one;
-- otherwise my own client judges it. An item not cached yet passes then: its
-- stats are unknown, so recheckUncached judges it again once they arrive.
local function fitsMe(link)
	local cls = select(2, UnitClass("player"))
	local id = tonumber(tostring(link):match("item:(%d+)"))
	local chars = id and fitFromML[id]
	if chars then return chars:find(CLASS_CH[cls] or "-", 1, true) ~= nil end
	return fitsClass(link, cls)
end

-- The round's uncached items, once the server has sent them: the ones that do
-- not suit me leave the frame and go to the council as "na". Tries a few times
-- while an item is still not cached.
local function recheckUncached(round, try)
	if not (round and current == round) then return end
	local waiting, dropped = false, false
	for k = #round.items, 1, -1 do
		local it = round.items[k]
		if it.uncached then
			local full = it.id and (select(2, GetItemInfo(it.id))) or nil
			if full then
				it.uncached, it.link = nil, full
				if not fitsMe(full) then
					table.remove(round.items, k)
					round.na[#round.na + 1] = it.idx .. "=na"
					dropped = true
				end
			else
				waiting = true
			end
		end
	end
	if dropped then
		if #round.items == 0 then ensureFrame():Hide() else C_.Repaint() end
		sendReply()
	end
	if waiting and try < 4 then
		C.After(1.5, function() recheckUncached(round, try + 1) end)
	end
end

-- ------------------------------------------------------------
-- A question arrived -> decide, per item, whether to show it, and reply.
-- The filter runs HERE, on the raider's own client: the leader would otherwise
-- need everyone's class before asking, and this client knows its own for free.
-- ------------------------------------------------------------
local function onAsked(sender, payload)
	if not enabled() then return nil end          -- module off: silent, like no addon
	if not payload or payload == "" then return nil end

	-- A NEW question replaces whatever was open. Without this a round restored
	-- after a reload stayed in `current` and the next question piled its items on
	-- top -- three test items turned into twelve, and the frame grew off screen.
	-- The old round is gone the moment a new one is asked: that is what "one
	-- round at a time" means on the raider's side.
	current = nil

	-- boss ^ link ^ link ...
	local parts = {}
	for p in (payload .. SEP_ITEM):gmatch("(.-)%" .. SEP_ITEM) do parts[#parts + 1] = p end
	local boss = table.remove(parts, 1) or ""

	local items, naParts = {}, {}
	local P = Okanvil.Prof
	for i, raw in ipairs(parts) do
		if raw ~= "" then
			-- The wire carries item IDS (see C_.Ask). Rebuild the link locally --
			-- "item:<id>" is a valid hyperlink for GetItemInfo and the tooltip, and
			-- WarmItem pulls the real name/quality into the cache for the repaint.
			local id = tonumber(raw)
			local link = id and ("item:" .. id) or raw
			Okanvil:WarmItem(id or link)
			local full = id and (select(2, GetItemInfo(id))) or nil
			link = full or link
			if fitsMe(link) then
				local equip = select(9, GetItemInfo(link))
				items[#items + 1] = {
					idx = i, link = link, id = id,
					slotText = equip and _G[equip] or "",
					owned = alreadyOwned(link),
					-- not cached: the filter let it through unread; judged again below
					uncached = not full or nil,
				}
			else
				naParts[#naParts + 1] = i .. "=na"
			end
		end
	end

	-- Nothing survived the filter: answer "na" for everything and never open a
	-- frame. The council still gets a reply, which is what keeps its count honest.
	if #items == 0 then
		return table.concat(naParts, SEP_ANS)
	end

	current = {
		round = nil,                  -- filled by the ASK handler below
		asker = sender,
		boss  = boss,
		items = items,
		na    = naParts,
	}

	local f = ensureFrame()
	f._scrollTop = 1        -- a new question always starts at the first item
	C_.Repaint()
	f:Show()
	saveRound()

	-- ANSWER "deciding..." STRAIGHT AWAY. The board has to show everyone who was
	-- asked from the moment they are asked -- otherwise a name only appears once
	-- it has clicked, and the council cannot tell "still reading the tooltip"
	-- apart from "has no addon". RCLootCouncil does the same with its WAIT.
	--
	-- Deferred a frame: current.round is set by the caller right after this
	-- returns, and sendReply needs it.
	C.After(0, function() sendReply() end)
	if PlaySound then PlaySound("igMainMenuOpen") end
	for _, it in ipairs(items) do
		if it.uncached then local r = current; C.After(1.5, function() recheckUncached(r, 1) end); break end
	end

	-- Nothing is returned here: the frame answers as the raider clicks. Returning
	-- a reply now would tell the council "passed on everything" the instant the
	-- question arrived.
	return nil
end

-- Comms hands the handler (sender, payload, round). This frame is the case that
-- needs the round: it answers over TIME -- as the raider clicks -- rather than
-- returning one value now. Returning nil tells Comms "I will send my own", and
-- the round is what pairs those later replies with the right question.
if C then
	C.Answer(TOPIC, function(sender, payload, round)
		-- A RE-BROADCAST of the round we are already on is not a new question.
		-- Rebuilding would throw away answers already clicked and restart the
		-- timer, so the repeat is answered from what we have and ignored.
		if current and current.round == round then
			-- A repeat of a round restored after a login is proof it is still open.
			if current.restored then C_.ShowRestored(round) end
			sendReply()
			if C_.ResendVotes then C_.ResendVotes(round) end
			return nil
		end
		-- A repeat of a round this client already answered and closed, or one a
		-- newer question has replaced: send the same answers again and stay shut.
		-- Treating it as new is what re-opened the frame and put "deciding..."
		-- back over answers the council already had.
		local past = pastRound(round)
		if past then
			if not C.Send("ANS", TOPIC, round, past.body) then
				C.Reply(past.asker or sender, TOPIC, round, past.body)
			end
			if C_.ResendVotes then C_.ResendVotes(round) end
			return nil
		end
		-- A council member opens the board for this round too, before answering
		-- it as a raider: the question is the only thing that carries the items.
		if canSeeBoard() and C_.MirrorRound then C_.MirrorRound(sender, payload, round) end
		local reply = onAsked(sender, payload)
		if current then
			current.round = round
			-- Re-saved now that the round id is known: onAsked saved before it was
			-- set, so without this a restored round could not answer anybody.
			saveRound()
		end
		return reply           -- non-nil only when every item was filtered out
	end)
end

-- ============================================================
-- ASKER SIDE -- open a round on one or more items, and watch the answers.
-- ============================================================

C_.rounds = {}      -- round id -> { items = {link,...}, replies = {name -> {idx -> key}}, boss }

-- Board state lives HERE, above every function that touches it. Declared after
-- C_.Ask (which opens the board) these would have been separate globals, and the
-- board would have been rebuilt on every repaint instead of reused.
local board            -- the reused board frame
local boardItem = 1    -- which item of the round is on screen
local tabFirst  = 1    -- leftmost tab shown in the strip (paging window)
local BR_H   = 42      -- board row height; a full raid still fits on screen
local BOARD_MAX_ROWS = 12   -- rows drawn at once; the rest scroll
local TAB_S  = 44      -- item tab icon size
local TAB_TOP = 38     -- where the tab strip starts, under the title bar
-- Board columns, as x offsets. One place to shift the table rather than four.
-- Widened so the EQUIPPED column can show a full item name -- "Ramaladni's
-- Blade..." truncated at 18 characters was the column being too narrow, not the
-- name being too long.
local COL_NAME = 6       -- a little in from the row's edge
local COL_WANT = 240     -- room after the name for the "won tonight" icons
local COL_PRIO = 320
local COL_GEAR = 370     -- equipped icon
local COL_SPEC = 414     -- equipped item name, just right of its icon
local COL_DIFF = 640     -- the ilvl gap
local COL_VOTE = 700     -- council votes: count, two names, the Vote button
local BOARD_W  = 980

-- Sets "<colour><text>|r", cutting the text with "..." until it fits maxW pixels.
local function fitText(fs, hex, text, maxW)
	fs:SetText(hex .. text .. "|r")
	if fs:GetStringWidth() <= maxW then return end
	for n = #text - 1, 1, -1 do
		fs:SetText(hex .. text:sub(1, n):gsub("[%s,]+$", "") .. "...|r")
		if fs:GetStringWidth() <= maxW then return end
	end
end

-- "<idx>=<response>/<equippedID>/<diff>", with the two gear fields optional so an
-- older client (or one that could not read its own slot) still parses. An
-- "E=<skill>" part is the raider's Enchanting skill, kept as out.ench.
local function parseReply(payload)
	local out, second, done = {}, {}, {}
	for pair in tostring(payload or ""):gmatch("[^" .. SEP_ANS .. "]+") do
		local ench = pair:match("^E=(%d+)$")
		if ench then out.ench = tonumber(ench) end
		local sIdx, sID = pair:match("^S(%d+)=(%d+)$")
		if sIdx then second[tonumber(sIdx)] = tonumber(sID) end
		local dIdx, dIDs = pair:match("^D(%d+)=([%d+]+)$")
		if dIdx then
			local list = {}
			for id in dIDs:gmatch("%d+") do list[#list + 1] = { id = tonumber(id), done = true } end
			done[tonumber(dIdx)] = list
		end
		local idx, body = pair:match("^(%d+)=(.+)$")
		if idx then
			local key, eq, diff = body:match("^([^/]+)/([^/]*)/([^/]*)$")
			if not key then key = body end      -- bare "<idx>=<response>"
			local tier
			if eq and eq:sub(1, 1) == "T" then
				tier = {}
				for id in eq:gmatch("%d+") do tier[#tier + 1] = { id = tonumber(id) } end
			end
			out[tonumber(idx)] = {
				key  = key,
				eq   = tonumber(eq),
				diff = tonumber(diff),
				tier = tier,
			}
		end
	end
	for idx, id in pairs(second) do
		if out[idx] then out[idx].eq2 = id end
	end
	-- the done pieces go after the ones still to upgrade, on the same tier list
	for idx, list in pairs(done) do
		local t = out[idx] and out[idx].tier
		if t then for _, p in ipairs(list) do t[#t + 1] = p end end
	end
	return out
end

-- A "wait" never overwrites a real answer already on the board. Raiders cannot
-- take an answer back (there is no button for it), so a later "deciding..." for
-- an item they already answered is a stale or restarted client, not news.
local function mergeReply(old, new)
	if old then
		for idx, a in pairs(new) do
			local o = type(idx) == "number" and old[idx]
			if o and a.key == "wait" and o.key ~= "wait" then new[idx] = o end
		end
	end
	return new
end

-- ------------------------------------------------------------
-- COUNCIL VOTES.
--
-- Each council member may put ONE vote per item on a candidate, and move it or
-- take it back until the item is given. A vote is a suggestion shown on the
-- board, never a decision: the Give button still gives to whoever is selected.
--
-- The council is the officers (and officers' alts) who are IN the raid right
-- now, plus the master looter -- someone who is not here is not on the council
-- for this item, so the strip and the "n/m voted" count shrink with them.
--
--   rec.votes[itemIdx][voter] = candidateName
--
-- Wire: CVOTE <round> <itemIdx> <candidate>  ("" candidate = vote withdrawn).
-- Sent to the group like the answers, so every board sees every vote.
-- ------------------------------------------------------------
local function bareName(n) return n and (n:gsub("%-.*$", "")) or n end

-- May this name vote? Checked on every vote that arrives, not only on the one
-- we send: the wire says who sent it, not whether they were entitled to.
local function isCouncilName(name)
	if not name or name == "" then return false end
	local L = Okanvil.Loot
	local ml = L and L.MasterLooterName and L.MasterLooterName()
	if ml and bareName(ml) == name then return true end
	-- No guild, no ranks: the same rule canSeeBoard applies.
	if not (IsInGuild and IsInGuild()) then return true end
	local U = Okanvil.U
	return (U and U.canSeePrio and U.canSeePrio(name)) and true or false
end

-- The council present for this round, in raid order. Cached for 30 seconds on
-- the round: the rank check walks the guild roster once per name, and a board
-- repaints on every reply that lands.
local function councilOf(rec)
	local now = GetTime()
	if rec._council and (now - (rec._councilAt or 0)) < 30 then return rec._council end
	local out, seen = {}, {}
	local function add(n)
		n = bareName(n)
		if n and n ~= "" and not seen[n] then
			seen[n] = true
			out[#out + 1] = n
		end
	end
	local inGuild = IsInGuild and IsInGuild()
	local L = Okanvil.Loot
	local ml = L and L.MasterLooterName and L.MasterLooterName()
	local function consider(n)
		n = bareName(n)
		if not n then return end
		-- Outside a guild everyone in the raid would qualify, so only the people
		-- actually running the loot are listed there.
		if inGuild then
			if isCouncilName(n) then add(n) end
		elseif (ml and bareName(ml) == n) or n == rec.asker then
			add(n)
		end
	end
	local nRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	if nRaid > 0 then
		for i = 1, nRaid do consider((GetRaidRosterInfo(i))) end
	else
		consider(UnitName("player"))
		for i = 1, ((GetNumPartyMembers and GetNumPartyMembers()) or 0) do
			consider(UnitName("party" .. i))
		end
	end
	if #out == 0 then add(UnitName("player")) end
	rec._council, rec._councilAt = out, now
	return out
end

local function applyVote(rec, idx, voter, cand)
	rec.votes = rec.votes or {}
	rec.votes[idx] = rec.votes[idx] or {}
	rec.votes[idx][voter] = (cand and cand ~= "") and cand or nil
end

-- Vote for `cand` on item `idx` of the open round; the same candidate again
-- takes the vote back.
function C_.Vote(idx, cand)
	local rec = C_.current
	if not (rec and rec.round and idx and cand) then return end
	local me = UnitName("player")
	local cur = rec.votes and rec.votes[idx] and rec.votes[idx][me]
	if cur == cand then cand = "" end
	applyVote(rec, idx, me, cand)
	C.Send("CVOTE", rec.round, idx, cand)
	C_.SaveAsk()
	C_.RepaintBoard()
end

-- Our own votes on a round, sent again. Called whenever the question is
-- re-broadcast, so a council member who reloaded gets everyone's votes back
-- within one re-send.
function C_.ResendVotes(round)
	local rec = C_.rounds[round]
	if not (rec and rec.votes) then return end
	local me = UnitName("player")
	for idx, byVoter in pairs(rec.votes) do
		if byVoter[me] then C.Send("CVOTE", round, idx, byVoter[me]) end
	end
end

if C then
	C.On("CVOTE", function(sender, round, idx, cand)
		local rec = round and C_.rounds[round]
		idx = tonumber(idx)
		if not (rec and idx) then return end
		-- Ours was applied when we cast it; the echo off the raid channel is not
		-- news, and applying it twice would undo a quick change of mind.
		if sender == UnitName("player") then return end
		if not isCouncilName(sender) then return end
		applyVote(rec, idx, sender, cand)
		if rec == C_.current then
			C_.SaveAsk()
			C_.RepaintBoard()
		end
	end)
end

-- ------------------------------------------------------------
-- IS THIS ROUND STILL OPEN?  Asked by a raider who logged back in with a saved
-- round, before it puts the frame back on screen.
--
-- Wire: CQ <round> (raider -> asker, whisper), CQA <round> (asker -> raider).
-- Only a live answer opens the frame; silence drops the saved round.
-- ------------------------------------------------------------
function C_.RoundIsLive(round)
	local rec = round and C_.rounds[round]
	return (rec and not rec.closed and rec == C_.current) and true or false
end

-- A question you have not answered survives a reload or a relog, but its window
-- never opens by itself (a pop-up after a login, in the middle of whatever you
-- are doing, is the one thing the council must not do). One line in your own
-- chat says it is waiting; /okcouncil answer opens it.
local restoreWait
function C_.ShowRestored(round)
	if not (current and current.round == round) then return end
	if InCombatLockdown and InCombatLockdown() then
		restoreWait = restoreWait or CreateFrame("Frame")
		restoreWait:RegisterEvent("PLAYER_REGEN_ENABLED")
		restoreWait:SetScript("OnEvent", function(self)
			self:UnregisterEvent("PLAYER_REGEN_ENABLED")
			C_.ShowRestored(round)
		end)
		return
	end
	current.restored = nil
	Okanvil:Print("|cffe0b860Loot council:|r an item from before the reload still needs your answer -- "
		.. "|cffffd200/okcouncil answer|r")
end

-- /okcouncil answer: open the question waiting for your answer
function C_.OpenAnswer()
	if not current or current.restored then
		Okanvil:Print("Loot council: nothing is waiting for your answer.")
		return
	end
	local fr = ensureFrame()
	fr._scrollTop = 1
	C_.Repaint()
	fr:Show()
end

-- The saved round was not confirmed in time: forget it without a word.
function C_.DropRestored(round)
	if not (current and current.round == round and current.restored) then return end
	current = nil
	db().openRound = nil
end

if C then
	C.On("CQ", function(sender, round)
		if sender and C_.RoundIsLive(round) then C.Whisper("CQA", sender, round) end
	end)
	C.On("CQA", function(sender, round)
		if current and current.round == round and sender == current.asker then
			C_.ShowRestored(round)
		end
	end)
	-- the asker's class fit for the question right behind it (C_.Ask)
	C.On("CFIT", function(sender, body)
		if sender and sender:gsub("%-.*", "") ~= UnitName("player") then readClassFit(body) end
	end)

	-- COUNCIL NIGHT, as the master looter has it. Only the ML can switch it, so
	-- every other officer shows the ML's state in their header, read-only --
	-- they need to know whether the night is a council night without being able
	-- to change it. The ML announces each change; anyone opening the page or
	-- joining asks (CNQ) and the ML answers.
	local function isML(name)
		local L = Okanvil.Loot
		local ml = L and L.MasterLooterName and L.MasterLooterName()
		return ml and name and ml:gsub("%-.*", ""):lower() == name:gsub("%-.*", ""):lower()
	end
	C.On("CNIGHT", function(sender, v)
		if not isML(sender) or isML(UnitName("player")) then return end
		C_.remoteNight = (v == "1") and sender:gsub("%-.*", "") or nil
		if C_._repaintHeader then pcall(C_._repaintHeader) end
		if C_._paintRun then pcall(C_._paintRun) end
	end)
	C.On("CNQ", function()
		if isML(UnitName("player")) then C.Send("CNIGHT", C_.active and "1" or "0") end
	end)

	-- ENCHANTERS, asked once. The master looter asks when council night starts;
	-- every Okanvil with Enchanting whispers its skill back, and nobody else says
	-- anything. The Disenchant list reads this for the rest of the night.
	C.On("ENCQ", function(sender)
		local e = enchantSkill()
		if e and sender then C.Whisper("ENC", sender, tostring(e)) end
	end)
	C.On("ENC", function(sender, v)
		local n = tonumber(v)
		if sender and n then C_.enchanters[(sender:gsub("%-.*", ""))] = n end
	end)
end

-- name -> Enchanting skill, for the Disenchant list. Filled by one ENCQ round.
C_.enchanters = {}

-- Ask the group once per session. Asking again only happens after a reload,
-- when the list above starts empty.
function C_.AskEnchanters()
	if C_.enchAsked or not (C and C.Send) then return end
	C_.enchAsked = C.Send("ENCQ") or nil
	local mine = enchantSkill()
	if mine then C_.enchanters[UnitName("player")] = mine end
end

-- Is this item in a council round that is still open and not yet given? The
-- mini roll marks such an item "asked".
function C_.IsAsked(id)
	if not id then return false end
	for _, rec in pairs(C_.rounds or {}) do
		if not rec.closed then
			for i, link in ipairs(rec.items or {}) do
				if Okanvil.U.itemIDFromLink(link) == id and not (rec.awarded and rec.awarded[i]) then
					return true
				end
			end
		end
	end
	return false
end

-- Ask the master looter for the council-night state (their answer is CNIGHT).
function C_.QueryNight()
	if C and C.Send then C.Send("CNQ") end
end

-- ------------------------------------------------------------
-- THE BOARD ON EVERY COUNCIL MEMBER.
--
-- The answers already go to the whole group, but only the client that asked had
-- a round to file them under -- everyone else dropped them, so the board existed
-- on one screen. A council member who receives the question now opens the same
-- round on their own client and collects the same answers: that is what lets
-- them vote. The Give button stays with whoever can hand the item out.
-- ------------------------------------------------------------
function C_.MirrorRound(asker, payload, round)
	if not (round and payload and payload ~= "") then return end
	if C_.rounds[round] then return end
	local parts = {}
	for part in (payload .. SEP_ITEM):gmatch("(.-)%" .. SEP_ITEM) do parts[#parts + 1] = part end
	local boss = table.remove(parts, 1) or ""
	local items = {}
	for _, raw in ipairs(parts) do
		local id = tonumber(raw)
		if id then
			Okanvil:WarmItem(id)
			items[#items + 1] = select(2, GetItemInfo(id)) or ("item:" .. id)
		end
	end
	if #items == 0 then return end

	local rec = {
		items = items, boss = boss, replies = {}, at = GetTime(),
		round = round, payload = payload, asker = asker, mirror = true,
	}
	C_.rounds[round] = rec
	C_.current = rec
	C.Adopt(TOPIC, round, {
		timeout = 1800,
		onReply = function(sender, body)
			rec.replies[sender] = mergeReply(rec.replies[sender], parseReply(body))
			if rec == C_.current then C_.RepaintBoard() end
			C_.SaveAsk()
		end,
		onDone = function()
			rec.closed = true
			C_.SaveAsk()
			if rec == C_.current then C_.RepaintBoard() end
		end,
	})
	boardItem = 1
	tabFirst = 1
	C_.SaveAsk()
	C_.RepaintBoard()
end

-- Ask the group about a list of item links.
function C_.Ask(links, boss)
	if not enabled() then
		Okanvil:Print("Loot Council is |cffff5555off|r for this character (Modules list).")
		return false
	end
	if type(links) ~= "table" or #links == 0 then return false end
	-- shards, saronite, orbs and patterns are never a council question
	do
		local keep = {}
		for _, l in ipairs(links) do
			if C_.IsCouncilItem(l) then keep[#keep + 1] = l
			else Okanvil:Print("|cffe0b860Loot council:|r " .. tostring(l) .. " is not gear -- roll it or give it to its collector.") end
		end
		links = keep
		if #links == 0 then return false end
	end
	-- Only an officer may put an item to the raid. Without this any raider could
	-- open a round and pop a frame on twenty-five clients -- and a raider who
	-- could ask would then be shown the board, which is where the prio lives.
	if not canSeeBoard() then
		Okanvil:Print("|cffff5555Loot council:|r only officers can put an item to the council.")
		return false
	end
	if not mayRunCouncil() then
		Okanvil:Print("|cffff5555Loot council:|r only the master looter puts items to the raid "
			.. "-- you see the board and vote when they do.")
		return false
	end

	-- ITEM IDS, NOT LINKS. A full link is ~70 bytes and the id is all the receiver
	-- needs: it rebuilds the link locally with WarmItem + GetItemInfo, exactly as the
	-- loot module already does for its own drops. The round stays one short message.
	local ids = {}
	for _, l in ipairs(links) do
		local id = Okanvil.U.itemIDFromLink(l) or tonumber(l)
		if id and id ~= 0 then ids[#ids + 1] = id end
	end
	if #ids == 0 then
		Okanvil:Print("|cffff5555Loot council:|r no valid items.")
		return false
	end

	local payload = (boss or "") .. SEP_ITEM .. table.concat(ids, SEP_ITEM)
	if #payload > 200 then
		Okanvil:Print(("|cffff5555Loot council:|r too many items for one round (%d)."):format(#ids))
		return false
	end

	-- Resolve every entry to a real LINK for display. Callers legitimately pass
	-- bare ids (test mode uses GetInventoryItemID; the picker falls back to the
	-- drop's id when it has no stored link), and the board would otherwise print
	-- "50735" where the item name belongs.
	local shown = {}
	for i, l in ipairs(links) do
		if type(l) == "number" or tostring(l):match("^%d+$") then
			Okanvil:WarmItem(tonumber(l))
			shown[i] = select(2, GetItemInfo(tonumber(l))) or ("item:" .. tostring(l))
		else
			shown[i] = l
		end
	end

	-- `test` marks a round asked from test mode, so ending the test closes that
	-- round and never a real one.
	local rec = { items = shown, boss = boss or "", replies = {}, at = GetTime(),
		test = C_.testMode or nil }

	-- which classes each item suits, just ahead of the question on the same channel
	local fit = classFitPayload(ids)
	readClassFit(fit)
	if fit ~= "" then C.Send("CFIT", fit) end

	local round = C.Ask(TOPIC, payload, {
		-- The wire round stays open for 30 minutes. Nothing auto-passes any
		-- more, so this is only a backstop against a round nobody ever closes.
		timeout = 1800,
		onReply = function(sender, body)
			rec.replies[sender] = mergeReply(rec.replies[sender], parseReply(body))
			if C_.onReply then C_.onReply(rec) end
			-- Repaint rather than print: the board IS the status, and a chat line
			-- per click is unreadable once a real raid is answering.
			C_.RepaintBoard()
			C_.SaveAsk()        -- a crash now loses at most this one reply
		end,
		onDone = function()
			rec.closed = true
			C_.SaveAsk()             -- clears the saved round: it is over
			Okanvil:Print("|cffe0b860Loot council:|r round closed.")
			C_.RepaintBoard()
			C_.PrintStatus(rec, true)
		end,
	})
	if not round then
		Okanvil:Print("|cffff5555Loot council:|r nobody to ask.")
		return false
	end
	rec.round = round
	rec.payload = payload
	C_.rounds[round] = rec
	C_.current = rec
	-- The ASKER's round is persisted too. Only the raider's side was, so a leader
	-- who reloaded mid-council came back to an empty board and no way to award --
	-- the round was still live on every other client, answering into nothing.
	C_.SaveAsk()

	-- The question goes out ONCE. It used to be re-broadcast four times, 15s
	-- apart, in case a packet was dropped -- and every repeat made each client
	-- answer and re-send its votes again, a burst of traffic per round that kept
	-- the raid's windows busy long after the item was given. A raider whose
	-- question never arrived shows as "not answered" on the board.
	-- Open the board straight away, empty. Whoever asked has to be able to see
	-- that the question went out and watch answers arrive -- without it there is
	-- no way to tell a silent raid from a broken round.
	boardItem = 1
	tabFirst  = 1        -- a new round starts at the first page of tabs
	C_.RepaintBoard(true)

	Okanvil:Print(("|cffe0b860Loot council:|r asked about %d item(s)%s."):format(
		#links, (boss and boss ~= "") and (" from " .. boss) or ""))
	return round
end

-- ============================================================
-- THE BOARD (first cut).
--
-- RCLootCouncil shows the asker TWO frames: the one they answer in, and a voting
-- frame with everyone's responses. Without the second, whoever opened the round
-- cannot tell whether replies are arriving at all -- which is exactly the state
-- this module was in.
--
-- This is the honest minimum: one item at a time, one row per raider who could
-- answer, and the per-item count. The full board of the plan -- item icons down
-- the edge, the prio ladder in the header, spec/gear/recent columns, the award
-- button -- is stage 3 and is NOT here. Council votes are shown (see COUNCIL
-- VOTES above) but decide nothing: no quorum, no auto-award. The master looter
-- gives to whoever is selected, and the board's job is to have the facts on screen.
-- ============================================================

local function ensureBoard()
	if board then return board end
	local f = Okanvil:Popup("Loot council -- responses")
	Okanvil:SetPopup(nil)      -- shares the screen with the raider frame (see ensureFrame)
	-- Closed by hand = this officer is done with the round (voted, or has no
	-- opinion). Answers still arrive, a reload still restores the round, but
	-- neither puts the board back; /okcouncil board does.
	if f.closeBtn then
		f.closeBtn:HookScript("OnClick", function()
			local rec = C_.current
			if rec then rec.dismissed = true; C_.SaveAsk() end
		end)
	end
	f:SetWidth(BOARD_W)
	f:SetHeight(240)
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(20)      -- above the mini roll, below the raider frame
	-- FAR LEFT, anchored to the screen edge rather than offset from centre: the
	-- board is the wide one, and centring both meant they overlapped whenever the
	-- raider frame grew a row. The raider frame takes the right side.
	f:SetPoint("LEFT", UIParent, "LEFT", 24, 220)
	f:EnableKeyboard(false)

	-- The item name sits UNDER the tab strip: the tabs say which items exist, this
	-- says which one you are looking at.
	local title = W.Text(f, "", "head")
	title:SetPoint("TOPLEFT", 12, -(TAB_TOP + TAB_S + 8))
	title:SetJustifyH("LEFT")
	f.itemText = title

	local count = W.Text(f, "", nil, "accent")
	count:SetPoint("TOPRIGHT", -12, -(TAB_TOP + TAB_S + 8))
	f.count = count

	-- Hover the count for the names behind it: who is deciding, who passed, who
	-- cannot use the item (no popup), and who never answered at all.
	local countHit = CreateFrame("Frame", nil, f)
	countHit:SetAllPoints(count)
	countHit:EnableMouse(true)
	countHit:SetScript("OnEnter", function(self)
		local L = f._names
		if not L then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine("Who answered what", 0.88, 0.72, 0.38)
		-- class-coloured, one class together (all paladins, then all priests...), A-Z inside
		local LT = Okanvil.Loot
		local function block(label, list, r, g, b)
			if #list == 0 then return end
			local rows = {}
			for i, nm in ipairs(list) do
				rows[i] = { nm = nm, cls = (LT and LT.ClassOf and LT.ClassOf(nm)) or "~" }
			end
			table.sort(rows, function(x, y)
				if x.cls ~= y.cls then return x.cls < y.cls end
				return x.nm < y.nm
			end)
			local names = {}
			for i, e in ipairs(rows) do
				names[i] = (LT and LT.ClassColorName and LT.ClassColorName(e.nm)) or e.nm
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(label .. " (" .. #list .. ")", r, g, b)
			GameTooltip:AddLine(table.concat(names, ", "), 1, 1, 1, true)
		end
		block("Deciding", L.wait, 0.95, 0.85, 0.25)
		block("Passed", L.pass, 0.55, 0.57, 0.60)
		block("Can't use it (no popup)", L.na, 0.54, 0.55, 0.58)
		block("No answer (no Okanvil, or not reached)", L.silent, 1, 0.33, 0.33)
		GameTooltip:Show()
	end)
	countHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- ITEM TABS. One icon per item of the round, along the top: the whole window
	-- is then ONE item's responses and the table gets the full width, instead of
	-- sharing it with a list that is mostly not being looked at.
	--
	-- A coloured border says where each item stands, so a glance tells you how
	-- much is left without reading anything:
	--     gold  = the item on screen        white = still waiting
	-- (green = awarded arrives with the award button, in stage 3.)
	--
	-- The strip PAGES rather than growing: a ten-item boss would be ~500px of
	-- icons and would run off the window. Arrows appear only when there is more
	-- than fits.
	f.tabs = {}

	local left = W.Button(f, "<")
	left:SetSize(20, TAB_S)
	left:SetPoint("TOPLEFT", 12, -TAB_TOP)
	left:SetScript("OnClick", function()
		tabFirst = math.max(1, tabFirst - 1)
		f._tabManual = true          -- paged by hand: stop following the selection
		C_.RepaintBoard()
	end)
	left:Hide()
	f.tabLeft = left

	local right = W.Button(f, ">")
	right:SetSize(20, TAB_S)
	right:SetScript("OnClick", function()
		-- RepaintBoard clamps tabFirst against the item count, so a click at the
		-- end of the strip is a no-op rather than scrolling into empty space.
		tabFirst = tabFirst + 1
		f._tabManual = true
		C_.RepaintBoard()
	end)
	right:Hide()
	f.tabRight = right

	-- The prio ladder, under the item name. Body size and gold, not a dim note:
	-- it is the guild's own decision about this item and the council reads it on
	-- every round -- at "note" size in grey it could not be read at all.
	local prio = W.Text(f, "", "body", "accent")
	prio:SetPoint("TOPLEFT", 12, -(TAB_TOP + TAB_S + 28))
	prio:SetPoint("RIGHT", f, "RIGHT", -12, 0)
	prio:SetJustifyH("LEFT")
	if prio.SetWordWrap then prio:SetWordWrap(false) end
	f.prio = prio

	-- No line naming the council: the count says how many have voted, and the
	-- VOTES column already names who voted for whom.

	-- Who passed, in one dim line at the bottom right. Passes get no row: the
	-- council only needs to know they are out, not read them.
	local passLine = W.Text(f, "", "note", "dim")
	passLine:SetPoint("BOTTOMRIGHT", -12, 22)
	passLine:SetJustifyH("RIGHT")
	if passLine.SetWordWrap then passLine:SetWordWrap(false) end
	f.passLine = passLine

	-- More candidates than BOARD_MAX_ROWS: the wheel scrolls the table.
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		f._top = math.max(1, (f._top or 1) - delta)
		C_.RepaintBoard()
	end)

	-- ---- award row (bottom) -------------------------------------------
	-- The primary button NAMES the person it would give to. It is a suggestion in
	-- a button, not a decision: clicking any row changes who it names, and the
	-- council is still deciding on voice.
	local give = W.Button(f, "Give", "primary"):SetMain(true)
	give:SetSize(260, 26)
	give:SetPoint("BOTTOMLEFT", 12, 16)
	give:SetScript("OnClick", function()
		local rec = C_.current
		if not rec or not f._pick then return end
		-- Not armed because someone is still deciding -> the first click OVERRIDES
		-- the wait rather than doing nothing, so a dead or disconnected raider
		-- cannot hold the council hostage. The second click gives the item.
		if not f._armed then
			if f._waiting and f._waiting > 0 and not f._forceArm then
				f._forceArm = true
				Okanvil:Print(("|cffe0b860Council:|r %d raider(s) have not answered. "
					.. "Click again to give it anyway."):format(f._waiting))
				C_.RepaintBoard()
			end
			return
		end
		local link = rec.items[boardItem]
		local id = Okanvil.U.itemIDFromLink(link)
		if not id or id == 0 then
			Okanvil:Print("|cffff5555Council:|r cannot resolve that item.")
			return
		end
		-- Reuses the loot module's award path wholesale: it confirms first, does
		-- the master-loot give when the corpse is still open, and when it is NOT
		-- (auto loot, item already in bags) it records the winner anyway and tells
		-- the raid to trade you. That fallback is exactly the auto-loot case, and
		-- it is already written and already tested -- writing a second one here is
		-- how the two would drift apart.
		local L = Okanvil.Loot
		if not (L and L.AwardWinner) then
			Okanvil:Print("|cffff5555Council:|r the Loot module is not loaded.")
			return
		end
		local ansRec = rec.replies[f._pick]
		local ans = ansRec and ansRec[boardItem] and ansRec[boardItem].key

		local pick, item = f._pick, boardItem
		-- Remember it locally so the tab turns green and the board stops offering
		-- the same item again.
		local function given()
			rec.awarded = rec.awarded or {}
			rec.awarded[item] = pick
			C_.SaveAsk()
			C_.RepaintBoard()
		end

		-- TEST MODE NEVER GIVES REAL LOOT. No master-loot give and nothing said in
		-- chat -- a real raid left in test mode must not silently fail to hand
		-- loot out, and a test must not give an item away. The test DROP is marked
		-- as received, so the mini roll shows the result exactly as a real award
		-- would; test drops are deleted when the test ends.
		if C_.testMode then
			Okanvil:Print(("|cffe0b860[TEST]|r would give %s to |cffffd200%s|r%s "
				.. "-- |cff8a8d93nothing was given.|r"):format(
				tostring(link), tostring(pick),
				ans and (" (" .. ans .. ")") or ""))
			if L.NoteCouncilAward then L.NoteCouncilAward(id, pick, ans) end
			if L.MarkWinner then L.MarkWinner(id, pick) end
			if L.onLoot then L.onLoot() end
			given()
			return
		end

		-- Record HOW it was decided before the give, so the history and the site
		-- export can tell "won a roll" from "the council gave it to them, and they
		-- had answered BIS". AwardWinner writes receivedBy; this writes the reason.
		if L.NoteCouncilAward then L.NoteCouncilAward(id, pick, ans) end

		-- Marked only once the officer confirms: a Cancel on the confirm left the
		-- board saying "given to" for an item nobody got.
		L.AwardWinner(id, pick, nil, nil, nil, given)
	end)
	f.give = give

	-- ---- Disenchant ------------------------------------------------------
	-- Gives the item on screen to someone to disenchant: the history records it
	-- as DE, not as a win, so it never counts against anyone's loot priority.
	-- The list is the raid's ENCHANTERS by skill, asked once when council night
	-- started (C_.AskEnchanters). The whole raid is listed only when nobody has
	-- reported Enchanting (the enchanter may be running no Okanvil): shown every
	-- time, ten names read as "anyone can DE".
	local function inGroup()
		local out = {}
		if GetNumRaidMembers and GetNumRaidMembers() > 0 then
			for i = 1, GetNumRaidMembers() do
				local n = GetRaidRosterInfo(i)
				if n then out[#out + 1] = n end
			end
		else
			out[1] = UnitName("player")
			for i = 1, (GetNumPartyMembers and GetNumPartyMembers() or 0) do
				local n = UnitName("party" .. i)
				if n then out[#out + 1] = n end
			end
		end
		return out
	end

	local de = W.Button(f, "Disenchant")
	de:SetSize(120, 26)
	de:SetPoint("LEFT", give, "RIGHT", 8, 0)
	de.listFn = function()
		local L = Okanvil.Loot
		local function shown(n) return L and L.ClassColorName and L.ClassColorName(n) or n end
		local here = {}
		for _, n in ipairs(inGroup()) do here[n] = true end
		-- Nothing known yet (council night restored by a reload): ask now, and
		-- the next time the list opens it is filled.
		if not next(C_.enchanters) then C_.AskEnchanters() end
		local skill = {}
		for name, s in pairs(C_.enchanters) do
			if here[name] then skill[name] = s end
		end
		-- Older Okanvil builds still send their skill with each answer.
		for _, r in pairs(C_.rounds) do
			for name, answers in pairs(r.replies or {}) do
				if answers.ench and here[name] and answers.ench > (skill[name] or 0) then
					skill[name] = answers.ench
				end
			end
		end
		local ench = {}
		for name, s in pairs(skill) do ench[#ench + 1] = { name = name, skill = s } end
		table.sort(ench, function(a, b) return a.skill > b.skill end)
		local items = {}
		for _, e in ipairs(ench) do
			items[#items + 1] = { text = shown(e.name) .. " |cff8a8d93" .. e.skill .. "|r", value = e.name }
		end
		if #ench > 0 then return items end
		items[#items + 1] = { text = "|cff8a8d93No enchanters found. Pick anyone:|r", value = false }
		local rest = inGroup()
		table.sort(rest)
		for _, n in ipairs(rest) do items[#items + 1] = { text = shown(n), value = n } end
		return items
	end
	de.setFn = function(name)
		if not name then return end
		local rec = C_.current
		if not rec then return end
		local link = rec.items[boardItem]
		local id = Okanvil.U.itemIDFromLink(link)
		if not id or id == 0 then
			Okanvil:Print("|cffff5555Council:|r cannot resolve that item.")
			return
		end
		local item = boardItem
		local function given()
			rec.awarded = rec.awarded or {}
			rec.awarded[item] = name .. " (DE)"
			C_.SaveAsk()
			C_.RepaintBoard()
		end
		local L = Okanvil.Loot
		if C_.testMode then
			Okanvil:Print(("|cffe0b860[TEST]|r would give %s to |cffffd200%s|r to disenchant "
				.. "-- |cff8a8d93nothing was given.|r"):format(tostring(link), name))
			if L and L.MarkWinner then L.MarkWinner(id, name, true) end
			if L and L.onLoot then L.onLoot() end
			given()
			return
		end
		if not (L and L.AwardWinner) then
			Okanvil:Print("|cffff5555Council:|r the Loot module is not loaded.")
			return
		end
		if L.NoteCouncilAward then L.NoteCouncilAward(id, name, nil) end
		Okanvil:Trace("COUNCIL", ("disenchant %d -> %s (round %s)"):format(id, name, tostring(rec.round)))
		L.AwardWinner(id, name, nil, nil, true, given)
	end
	de:SetScript("OnClick", function(s) if W.OpenMenu then W.OpenMenu(s) end end)
	f.de = de

	-- In place of Give on a board that cannot hand the item out.
	local giveNote = W.Text(f, "Only the master looter gives the item. Your vote is a suggestion.",
		"body", "dim")
	giveNote:SetPoint("BOTTOMLEFT", 12, 22)
	giveNote:Hide()
	f.giveNote = giveNote

	-- NO "Skip" button. An item is undecided until Give is pressed, so skipping it
	-- is simply not pressing anything -- a button that only restated the default
	-- state was one more thing on screen that did nothing.

	-- Column headers.
	local hy = -(TAB_TOP + TAB_S + 50)
	local function col(text, x)
		local t = W.Text(f, text, "note", "dim")
		t:SetPoint("TOPLEFT", 12 + x, hy)
		return t
	end
	f.hdrs = {
		col("PLAYER", COL_NAME), col("WANTS", COL_WANT), col("PRIO", COL_PRIO),
		col("EQUIPPED", COL_GEAR), col("ILVL", COL_DIFF), col("COUNCIL VOTES", COL_VOTE),
	}

	f.rows = {}
	board = f
	return f
end

-- One row per responder. Sorted so the people who answered come first -- a
-- council reading the board wants the answers, not the gaps, at the top.
-- open = the player asked for the board (their own Ask, /okcouncil board, the
-- mini roll's Council button). Every other call -- an answer arriving, a vote, a
-- mirrored or restored round -- never puts back a board that was closed by hand.
function C_.RepaintBoard(open)
	local rec = C_.current
	if not rec then return end
	if not canSeeBoard() then return end
	local f = ensureBoard()
	if open then
		rec.dismissed = nil
	elseif rec.dismissed and not f:IsShown() then
		return
	end
	if boardItem > #rec.items then boardItem = 1 end

	-- ---- item tabs -------------------------------------------------------
	-- How many fit between the two arrows, given the window's width.
	local nItems  = #rec.items
	-- Room between the two arrows: 12px margins, a 20px arrow and an 8px gap at
	-- each end. Getting this wrong is what left a hole beside the right arrow.
	local stripW  = BOARD_W - (12 + 20 + 8) * 2
	local perPage = math.max(1, math.floor(stripW / (TAB_S + 6)))
	local paging  = nItems > perPage

	-- Follow the SELECTION only when it was just changed by something other than
	-- the arrows. Doing it unconditionally is what made the arrows dead: they
	-- moved tabFirst, then this snapped it straight back to wherever the selected
	-- item was, every single repaint.
	if not f._tabManual then
		if boardItem < tabFirst then tabFirst = boardItem end
		if boardItem > tabFirst + perPage - 1 then tabFirst = boardItem - perPage + 1 end
	end
	local maxFirst = math.max(1, nItems - perPage + 1)
	if tabFirst > maxFirst then tabFirst = maxFirst end
	if tabFirst < 1 then tabFirst = 1 end

	local xBase = paging and (12 + 20 + 8) or 12   -- clear of the left arrow
	if paging then
		f.tabLeft:Show()
		f.tabRight:Show()
		-- Anchored to the frame's RIGHT edge, not to where the last tab happens to
		-- land: the strip rarely fills the window exactly, so a left-anchored
		-- arrow floated in the middle with empty space beside it.
		f.tabRight:ClearAllPoints()
		f.tabRight:SetPoint("TOPRIGHT", -12, -TAB_TOP)
		-- An arrow at the end of its travel is dimmed rather than hidden: a
		-- control that vanishes moves everything beside it.
		f.tabLeft:SetAlpha(tabFirst > 1 and 1 or 0.35)
		f.tabRight:SetAlpha(tabFirst < maxFirst and 1 or 0.35)
	else
		f.tabLeft:Hide()
		f.tabRight:Hide()
	end

	for i = 1, math.max(nItems, #f.tabs) do
		local tab = f.tabs[i]
		-- Only the page's slice is drawn; the rest are hidden, not destroyed.
		local slot = i - tabFirst + 1
		if i > nItems or slot < 1 or slot > perPage then
			if tab then tab:Hide() end
		else
			if not tab then
				tab = CreateFrame("Button", nil, f)
				tab:SetSize(TAB_S, TAB_S)
				-- the item in the kit's octagon frame; the frame is the state
				W.DressFramedIcon(tab, nil, TAB_S)
				tab.tex = tab.icon
				tab:SetScript("OnClick", function()
					boardItem = i
					-- Picking an item by hand hands control back to the selection,
					-- so the strip follows it again from here.
					f._tabManual = nil
					-- The override is per item: switching items must not carry a
					-- "give it anyway" that was armed for a different decision.
					f._forceArm = nil
					f._top = 1
					C_.RepaintBoard()
				end)
				-- Tooltip off the board's RIGHT edge, into empty screen. It was
				-- dropped earlier because it covered the response table -- but that
				-- was while the board sat centred; anchored outside the window there
				-- is nothing for it to hide.
				tab:SetScript("OnEnter", function(self)
					if not self._link then return end
					-- The picker may hand over a bare item id when a drop has no
					-- stored link; "item:<id>" is a valid hyperlink either way.
					local lk = self._link
					if not tostring(lk):find("|H") then lk = "item:" .. tostring(lk) end
					GameTooltip:SetOwner(self, "ANCHOR_NONE")
					GameTooltip:ClearAllPoints()
					GameTooltip:SetPoint("TOPLEFT", f, "TOPRIGHT", 8, 0)
					local ok = pcall(function() GameTooltip:SetHyperlink(lk) end)
					if ok then GameTooltip:Show() else GameTooltip:Hide() end
				end)
				tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
				f.tabs[i] = tab
			end
			-- Re-anchored EVERY paint, not just at creation: an item's slot in the
			-- strip changes as the page moves, so a position set once would leave
			-- the icons where the first page put them.
			tab:ClearAllPoints()
			tab:SetPoint("TOPLEFT", xBase + (slot - 1) * (TAB_S + 6), -TAB_TOP)

			local lnk = rec.items[i]
			tab._link = lnk
			local tex = select(10, GetItemInfo(lnk)) or (GetItemIcon and GetItemIcon(lnk))
			if tex then tab.tex:SetTexture(tex) end
			-- The frame is the state, so a glance says how much is left:
			--   gold frame = on screen now   grey frame = the others
			--   a grey icon = already given
			local done = rec.awarded and rec.awarded[i]
			W.SetFramedIconGold(tab, i == boardItem)
			tab.tex:SetDesaturated(done and i ~= boardItem and true or false)
			tab.tex:SetAlpha((i == boardItem or not done) and 1 or 0.7)
			tab:Show()
		end
	end

	local link = rec.items[boardItem]
	-- TEST says so, loudly and constantly. The worst outcome of this feature is a
	-- real raid running in test mode and the loot never being handed out.
	f.itemText:SetText(("%s%s  |cff8a8d93(%d/%d)|r"):format(
		C_.testMode and "|cffe0b860[TEST]|r " or "",
		tostring(link), boardItem, #rec.items))

	-- The PRIO ladder for this item, from the website's list. The council's own
	-- order -- P.Names gives it top-first, so the index IS the position.
	local prioPos, prioLine = {}, nil
	-- Officers and officers' alts only -- the same rule as the Priority tab. The
	-- board itself also opens for a master looter outside that circle (and for
	-- anyone in no guild), and neither is meant to read the guild's order: no
	-- ladder, no PRIO column, and it does not sort their rows either.
	local U = Okanvil.U
	local canPrio = U and U.canSeePrio and U.canSeePrio() and true or false
	if f.hdrs and f.hdrs[3] then f.hdrs[3]:SetText(canPrio and "PRIO" or "") end
	do
		local P = Okanvil.LootPrio
		if canPrio and P and P.ForLink then
			-- P.ForLink returns the stored RECORD, not the ladder -- the ladder
			-- string is rec.p. Passing the record straight to P.Plain called
			-- gmatch on a table.
			local rec2 = P.ForLink(link)
			local prio = rec2 and rec2.p
			if prio and prio ~= "" then
				prioLine = (P.Line and P.Line(prio)) or (P.Plain and P.Plain(prio)) or prio
				for pos, nm in ipairs(P.Names(prio) or {}) do
					-- Names carries an " (OS)" suffix; the bare name is the key.
					local bare = nm:gsub("%s*%(OS%)$", "")
					if prioPos[bare] == nil then prioPos[bare] = pos end
				end
			end
		end
	end

	-- Collect answers for THIS item. "na" means the client filtered it out, which
	-- is a reply, not silence -- it is counted out of the denominator instead.
	-- "wait" is listed but NOT counted as answered: the council needs to see who
	-- is still deciding, and needs the count to say how many have actually made a
	-- decision. Conflating the two is what let a name show Pass before it had
	-- chosen anything.
	-- A Pass gets its row too, sorted after the real claims: the council has to
	-- see that the popup reached someone and they turned it down.
	local rows, answered, naCount, waiting, passed = {}, 0, 0, 0, {}
	local waitNames, naNames = {}, {}
	for name, answers in pairs(rec.replies) do
		local a = answers[boardItem]
		if a and a.key == "pass" then
			answered = answered + 1
			passed[#passed + 1] = name
			rows[#rows + 1] = {
				name = name, key = a.key, eq = a.eq, eq2 = a.eq2, diff = a.diff, tier = a.tier,
				prio = prioPos[name],
			}
		elseif a and a.key and a.key ~= "na" then
			if a.key == "wait" then
				waiting = waiting + 1
				waitNames[#waitNames + 1] = name
			else
				answered = answered + 1
			end
			rows[#rows + 1] = {
				name = name, key = a.key, eq = a.eq, eq2 = a.eq2, diff = a.diff, tier = a.tier,
				prio = prioPos[name],
			}
		elseif a and a.key == "na" then
			naCount = naCount + 1
			naNames[#naNames + 1] = name
		end
	end
	-- the names behind the count, for its tooltip
	do
		local replied, silent = {}, {}
		for name in pairs(rec.replies) do replied[name:gsub("%-.*", ""):lower()] = true end
		local me = (UnitName("player") or ""):lower()
		for _, nm in ipairs(C_.GroupNames()) do
			if not replied[nm:lower()] and nm:lower() ~= me then silent[#silent + 1] = nm end
		end
		for _, l in ipairs({ waitNames, naNames, silent }) do table.sort(l) end
		local pass = {}
		for i, nm in ipairs(passed) do pass[i] = nm end
		table.sort(pass)
		f._names = { wait = waitNames, pass = pass, na = naNames, silent = silent }
	end

	-- Sorted by WHAT THEY ANSWERED -- every BIS together, then Upgrade, down to
	-- Pass. The prio number is information in a column, not the order of the
	-- table: the council reads the claims first and weighs the ladder against
	-- them, so sorting by prio buried a BIS under two people who passed.
	--
	-- Prio breaks ties inside a response, which is where it actually decides
	-- something: two raiders both on BIS, and #1 is listed above #4.
	table.sort(rows, function(x, y)
		local rx = RESP_RANK[x.key] or 99
		local ry = RESP_RANK[y.key] or 99
		if rx ~= ry then return rx < ry end
		if x.prio and y.prio and x.prio ~= y.prio then return x.prio < y.prio end
		if x.prio and not y.prio then return true end
		if y.prio and not x.prio then return false end
		return x.name < y.name
	end)

	f._waiting = waiting
	-- Tick the board while anyone is still deciding, so the dots actually move.
	-- Nothing else repaints it between replies, and a frozen "deciding..." is the
	-- thing the animation exists to disprove.
	if not f._dotTick then
		f._dotTick = CreateFrame("Frame", nil, f)
		f._dotTick:SetScript("OnUpdate", function(self, e)
			self._acc = (self._acc or 0) + e
			if self._acc < 0.4 then return end
			self._acc = 0
			if (f._waiting or 0) == 0 or not f:IsShown() then return end
			-- Only the dots, not a full RepaintBoard: that rebuilds every row and
			-- re-reads the prio ladder, which is far too much work to do twice a
			-- second just to move three characters.
			local dots = ("."):rep(1 + (math.floor(GetTime() * 2) % 3))
			for _, r in ipairs(f.rows) do
				if r:IsShown() and r._wait then r.what:SetText("deciding" .. dots) end
			end
		end)
	end
	-- Who is on the council for this item, and who has voted on it.
	local members = councilOf(rec)
	local itemVotes = (rec.votes and rec.votes[boardItem]) or {}
	local votedN = 0
	for _, m in ipairs(members) do
		if itemVotes[m] ~= nil then votedN = votedN + 1 end
	end

	f.count:SetText(("%d answered%s|cff8a8d93%s%s|r   |cffe0b860%d/%d council voted|r"):format(
		answered,
		waiting > 0 and ("  |cffe0b860" .. waiting .. " deciding|r") or "",
		#passed > 0 and ("  ·  " .. #passed .. " passed") or "",
		naCount > 0 and ("  ·  " .. naCount .. " can't use") or "",
		votedN, #members))

	-- passes have their own rows now
	f.passLine:SetText("")

	-- Only BOARD_MAX_ROWS are drawn; the wheel moves the window. `rows` stays the
	-- full list so the default Give pick is still the top claim.
	local maxTop = math.max(1, #rows - BOARD_MAX_ROWS + 1)
	f._top = math.min(math.max(f._top or 1, 1), maxTop)
	local vis = {}
	for k = f._top, math.min(#rows, f._top + BOARD_MAX_ROWS - 1) do vis[#vis + 1] = rows[k] end

	-- The full ladder under the item name: the PRIO column gives each candidate's
	-- position, but the ladder shows the SHAPE of the decision -- who is level with
	-- whom (>) and where it steps down (>>). A number alone does not say that.
	f.prio:SetText(prioLine and ("|cff8a8d93prio|r  " .. prioLine) or "")

	local isMark = MARK_FROM[Okanvil.U.itemIDFromLink(link)] ~= nil
	for i = 1, math.max(#vis, #f.rows) do
		local r = f.rows[i]
		if i > #vis then
			if r then r:Hide() end
		else
			if not r then
				local top = TAB_TOP + TAB_S + 68
				r = CreateFrame("Frame", nil, f)
				r:SetPoint("TOPLEFT", 12, -(top + (i - 1) * BR_H))
				r:SetPoint("TOPRIGHT", -12, -(top + (i - 1) * BR_H))
				r:SetHeight(BR_H - 2)
				-- Alternating stripe, the same faint white the Home roster uses --
				-- enough to follow a row across five columns, not enough to read as
				-- a highlight. Show/Hide rather than SetShown: that is 4.x only.
				r.zebra = r:CreateTexture(nil, "BACKGROUND")
				r.zebra:SetTexture("Interface\\Buttons\\WHITE8x8")
				r.zebra:SetVertexColor(1, 1, 1, 0.022)
				r.zebra:SetPoint("TOPLEFT", 2, 0)
				r.zebra:SetPoint("BOTTOMRIGHT", -2, 1)
				-- Selection: a gold wash over the row the Give button names. Drawn
				-- above the zebra so the two do not cancel each other out.
				r.sel = r:CreateTexture(nil, "BORDER")
				r.sel:SetTexture("Interface\\Buttons\\WHITE8x8")
				r.sel:SetVertexColor(0.75, 0.58, 0.23, 0.18)
				r.sel:SetPoint("TOPLEFT", 2, 0)
				r.sel:SetPoint("BOTTOMRIGHT", -2, 1)
				r.sel:Hide()
				-- Class icon before the name, the way RCLoot's voting frame does it:
				-- a council scanning ten rows finds the healers by shape before it
				-- reads a single word.
				r.cls = r:CreateTexture(nil, "ARTWORK")
				r.cls:SetSize(30, 30)
				r.cls:SetPoint("LEFT", COL_NAME, 0)
				r.cls:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
				r.who  = W.Text(r, "", "head");      r.who:SetPoint("LEFT", COL_NAME + 38, 0)
				r.what = W.Text(r, "", "head");      r.what:SetPoint("LEFT", COL_WANT, 0)
				r.prio = W.Text(r, "", "head", "accent"); r.prio:SetPoint("LEFT", COL_PRIO, 0)
				-- What they have in that slot: icon, then the item's own name.
				r.eqIcon = r:CreateTexture(nil, "ARTWORK")
				r.eqIcon:SetSize(30, 30)
				r.eqIcon:SetPoint("LEFT", COL_GEAR + 4, 0)
				r.eqIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				-- the other ring/trinket, when the slot comes in a pair
				r.eqIcon2 = r:CreateTexture(nil, "ARTWORK")
				r.eqIcon2:SetSize(30, 30)
				r.eqIcon2:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				r.eqIcon2:Hide()
				-- the gold octagon round each equipped icon, shown and hidden with it
				for _, ic in ipairs({ r.eqIcon, r.eqIcon2 }) do
					local fr = r:CreateTexture(nil, "OVERLAY")
					fr:SetTexture("Interface\\AddOns\\Okanvil\\Media\\UI\\iconframes")
					fr:SetTexCoord(0, 80 / 256, 0, 80 / 128)
					fr:SetSize(38, 38); fr:SetPoint("CENTER", ic, "CENTER")
					fr:Hide()
					hooksecurefunc(ic, "Show", function() fr:Show() end)
					hooksecurefunc(ic, "Hide", function() fr:Hide() end)
				end
				r.spec = W.Text(r, "", "head");      r.spec:SetPoint("LEFT", COL_SPEC, 0)
				r.spec2 = W.Text(r, "", "head");     r.spec2:SetPoint("LEFT", r.eqIcon2, "RIGHT", 6, 0)
				r.diff = W.Text(r, "", "head");      r.diff:SetPoint("LEFT", COL_DIFF, 0)

				-- Hover the EQUIPPED area for that item's stats. Anchored off the
				-- board's RIGHT edge: the board sits far left, so the tooltip opens
				-- into empty screen instead of over the rows (which is why it was
				-- taken off the tabs).
				local eqHot = CreateFrame("Button", nil, r)
				eqHot:SetPoint("LEFT", COL_GEAR, 0)
				eqHot:SetPoint("RIGHT", r, "LEFT", COL_DIFF - 8, 0)
				eqHot:SetHeight(BR_H - 2)
				eqHot:SetScript("OnEnter", function(self)
					if not r._eqLink then return end
					GameTooltip:SetOwner(self, "ANCHOR_NONE")
					GameTooltip:ClearAllPoints()
					GameTooltip:SetPoint("TOPLEFT", f, "TOPRIGHT", 8, 0)
					GameTooltip:SetHyperlink(r._eqLink)
					GameTooltip:Show()
					-- the pair's other item beside it
					if r._eqLink2 and ShoppingTooltip1 then
						ShoppingTooltip1:SetOwner(GameTooltip, "ANCHOR_NONE")
						ShoppingTooltip1:ClearAllPoints()
						ShoppingTooltip1:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 4, 0)
						ShoppingTooltip1:SetHyperlink(r._eqLink2)
						ShoppingTooltip1:Show()
					end
				end)
				eqHot:SetScript("OnLeave", function()
					GameTooltip:Hide()
					if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
				end)
				-- Raised ABOVE the row-wide inspect button, which is created after
				-- this one and would otherwise sit on top and eat the hover.
				eqHot:SetFrameLevel(r:GetFrameLevel() + 5)
				r.eqHot = eqHot

				-- Click the row to INSPECT that raider -- the council's "what else is
				-- he wearing?" without alt-tabbing or asking. Only works in range and
				-- out of combat; that is the game's rule, not ours, so a failure says
				-- so rather than doing nothing.
				local hit = CreateFrame("Button", nil, r)
				hit:SetAllPoints(r)
				hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				hit:SetScript("OnClick", function(_, button)
					local who = r._who
					if not who then return end
					if button == "RightButton" then
						-- Right-click: whisper them, for "are you sure you want this?"
						if ChatFrame_SendTell then ChatFrame_SendTell(who) end
						return
					end
					-- PLAIN left-click SELECTS this candidate -- that is the common
					-- action, so it is the cheapest one. Inspect moved to shift-click.
					if not IsShiftKeyDown() then
						f._pick = who      -- `f` is this board frame; same object as `board`
						C_.RepaintBoard()
						return
					end
					-- A NAME is not a unit token, so find the raid/party unit first --
					-- InspectUnit("Okanor") silently does nothing.
					local unit
					local nRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
					if nRaid > 0 then
						for i = 1, nRaid do
							local n = UnitName("raid" .. i)
							if n == who then
								unit = "raid" .. i
								break
							end
						end
					else
						if UnitName("player") == who then unit = "player" end
						local nP = (GetNumPartyMembers and GetNumPartyMembers()) or 0
						for i = 1, nP do
							local n = UnitName("party" .. i)
							if n == who then
								unit = "party" .. i
								break
							end
						end
					end
					if not unit then
						Okanvil:Print(("Council: |cffff5555%s|r is not in the group."):format(who))
						return
					end
					if CheckInteractDistance and CheckInteractDistance(unit, 1) and InspectUnit then
						InspectUnit(unit)
					else
						Okanvil:Print(("Council: |cffff5555%s|r is too far away to inspect."):format(who))
					end
				end)
				r.hit = hit

				-- COUNCIL VOTES: a gold count, the first two voters, "+N" for the
				-- rest. Hover it for every name.
				r.vpill = CreateFrame("Frame", nil, r)
				r.vpill:SetSize(20, 18)
				r.vpill:SetPoint("LEFT", COL_VOTE, 0)
				local vbg = r.vpill:CreateTexture(nil, "ARTWORK")
				vbg:SetAllPoints()
				vbg:SetTexture("Interface\\Buttons\\WHITE8x8")
				vbg:SetVertexColor(0.88, 0.72, 0.38, 1)
				r.vcount = W.Text(r.vpill, "", "body")
				r.vcount:SetPoint("CENTER", 0, 0)
				r.vcount:SetTextColor(0.08, 0.08, 0.09)
				r.vnames = W.Text(r, "", "body")
				r.vnames:SetPoint("LEFT", COL_VOTE + 28, 0)
				r.vnames:SetJustifyH("LEFT")
				if r.vnames.SetWordWrap then r.vnames:SetWordWrap(false) end

				r.vbtn = W.Button(r, "Vote"):SetMain(true)
				r.vbtn:SetSize(52, 20)
				r.vbtn:SetPoint("RIGHT", -4, 0)
				r.vbtn:SetFrameLevel(r:GetFrameLevel() + 5)
				r.vbtn:SetScript("OnClick", function()
					if r._who then C_.Vote(boardItem, r._who) end
				end)
				r.vnames:SetPoint("RIGHT", r.vbtn, "LEFT", -8, 0)

				local vhot = CreateFrame("Button", nil, r)
				vhot:SetPoint("LEFT", COL_VOTE, 0)
				vhot:SetPoint("RIGHT", r.vbtn, "LEFT", -4, 0)
				vhot:SetHeight(BR_H - 2)
				vhot:SetFrameLevel(r:GetFrameLevel() + 5)
				vhot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
				-- The votes area is part of the row: a click there still selects.
				vhot:SetScript("OnClick", function(_, button)
					local fn = hit:GetScript("OnClick")
					if fn then fn(hit, button) end
				end)
				vhot:SetScript("OnEnter", function(self)
					local list = r._voters
					if not (list and #list > 0) then return end
					local L2 = Okanvil.Loot
					GameTooltip:SetOwner(self, "ANCHOR_NONE")
					GameTooltip:ClearAllPoints()
					GameTooltip:SetPoint("TOPLEFT", f, "TOPRIGHT", 8, 0)
					GameTooltip:AddLine(("%d vote%s for %s"):format(#list,
						#list == 1 and "" or "s", tostring(r._who)), 0.88, 0.72, 0.38)
					for _, v in ipairs(list) do
						GameTooltip:AddLine(L2 and L2.ClassColorName and L2.ClassColorName(v) or v)
					end
					GameTooltip:Show()
				end)
				vhot:SetScript("OnLeave", function() GameTooltip:Hide() end)
				r.vhot = vhot
				-- Hovering the equipped icon shows what it is. Anchored off the
				-- window so it never covers the table.
				-- The equipped item's NAME is in the column, so there is nothing a
				-- tooltip would add here that is worth covering the table for.
				f.rows[i] = r
			end
			local d = vis[i]
			if i % 2 == 1 then r.zebra:Show() else r.zebra:Hide() end

			-- Class-coloured name + the class icon, both from the same cached class
			-- token the loot history uses.
			local L = Okanvil.Loot
			r._who = d.name        -- for the inspect/whisper click
			local tok = L and L.ClassOf and L.ClassOf(d.name)
			-- an answer on lighter armour than they wear is an exception: say so
			local P = Okanvil.Prof
			local lighter = tok and P and P.LighterArmor and P.LighterArmor(link, tok)
			r.who:SetText((L and L.ClassColorName and L.ClassColorName(d.name) or d.name)
				.. (lighter and ("  |cff8a8d93" .. lighter .. "|r") or ""))
			local tc = tok and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[tok]
			if tc then
				r.cls:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
				r.cls:Show()
			else
				r.cls:Hide()
			end

			-- WISH: this is the item they said they are after this raid ID. A gold
			-- frame round the row and a pill after the name; it informs, it does
			-- not decide.
			local wished = Okanvil.Wish and Okanvil.Wish.Wants(d.name, link)
			if not r.wishEdge then
				r.wishEdge = CreateFrame("Frame", nil, r)
				r.wishEdge:SetPoint("TOPLEFT", 1, 1); r.wishEdge:SetPoint("BOTTOMRIGHT", -1, 0)
				r.wishEdge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
				r.wishEdge:SetBackdropBorderColor(0.88, 0.72, 0.38, 1)
				r.wishPill = CreateFrame("Frame", nil, r)
				r.wishPill:SetSize(34, 15)
				r.wishPill:SetPoint("LEFT", r.who, "RIGHT", 6, 0)
				local pbg = r.wishPill:CreateTexture(nil, "ARTWORK")
				pbg:SetAllPoints(); pbg:SetTexture("Interface\\Buttons\\WHITE8x8")
				pbg:SetVertexColor(0.88, 0.72, 0.38, 1)
				local pt = W.Text(r.wishPill, "WISH", "note")
				pt:SetPoint("CENTER", 0, 0); pt:SetTextColor(0.08, 0.08, 0.09)
			end
			if wished then r.wishEdge:Show(); r.wishPill:Show() else r.wishEdge:Hide(); r.wishPill:Hide() end

			-- ALREADY WON TONIGHT: a count (gold for one, red for two or more) and
			-- the items themselves after the name, so the council can spread the
			-- loot instead of stacking it on one raider. Hover an icon for the item.
			do
				local won = (L and L.WonTonight and L.WonTonight(d.name)) or {}
				r.wonIcons = r.wonIcons or {}
				if not r.wonN then r.wonN = W.Text(r, "", "body") end
				-- after the WISH pill when there is one
				r.wonN:ClearAllPoints()
				r.wonN:SetPoint("LEFT", wished and r.wishPill or r.who, "RIGHT", 6, 0)
				local nShow = math.min(3, #won)
				if #won > 0 then
					r.wonN:SetText(#won)
					if #won >= 2 then r.wonN:SetTextColor(1, 0.42, 0.37) else r.wonN:SetTextColor(0.88, 0.72, 0.38) end
				else
					r.wonN:SetText("")
				end
				for k = 1, math.max(nShow, #r.wonIcons) do
					local b = r.wonIcons[k]
					if k <= nShow and not b then
						b = CreateFrame("Button", nil, r)
						b:SetSize(22, 22)
						b:SetPoint("LEFT", k == 1 and r.wonN or r.wonIcons[k - 1], "RIGHT", k == 1 and 4 or 3, 0)
						b.tex = b:CreateTexture(nil, "ARTWORK")
						b.tex:SetAllPoints()
						b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
						b:SetScript("OnEnter", function(self)
							if not self.link then return end
							GameTooltip:SetOwner(self, "ANCHOR_NONE")
							GameTooltip:ClearAllPoints()
							GameTooltip:SetPoint("TOPLEFT", f, "TOPRIGHT", 8, 0)
							local ok = pcall(function() GameTooltip:SetHyperlink(self.link) end)
							if ok then GameTooltip:Show() else GameTooltip:Hide() end
						end)
						b:SetScript("OnLeave", function() GameTooltip:Hide() end)
						b:SetFrameLevel(r:GetFrameLevel() + 6)
						r.wonIcons[k] = b
					end
					if b then
						local dp = won[k]
						if k <= nShow and dp then
							local lk = (dp.item and dp.item ~= "") and dp.item or ("item:" .. tostring(dp.id))
							if not tostring(lk):find("|H") and not tostring(lk):find("^item:") then lk = "item:" .. tostring(dp.id) end
							b.link = lk
							b.tex:SetTexture((dp.icon and ("Interface\\Icons\\" .. dp.icon))
								or (GetItemIcon and dp.id and GetItemIcon(dp.id))
								or "Interface\\Icons\\INV_Misc_QuestionMark")
							b:Show()
						else
							b:Hide()
						end
					end
				end
			end

			local info = RESP_BY_KEY[d.key]
			-- "deciding" gets LIVE dots: . / .. / ... on a one-second cycle, so a
			-- board full of people who have not answered reads as waiting rather
			-- than as stuck. Everything else is a fixed label.
			r._wait = (d.key == "wait")
			if r._wait then
				local dots = ("."):rep(1 + (math.floor(GetTime() * 2) % 3))
				r.what:SetText("deciding" .. dots)
			else
				r.what:SetText((info and info.label) or d.key)
			end
			if info and info.color then
				r.what:SetTextColor(info.color[1], info.color[2], info.color[3])
			end

			r.prio:SetText(canPrio and (d.prio and ("#" .. d.prio) or "-") or "")

			-- WHAT THEY HAVE IN THAT SLOT -- the item itself, not a gearscore. A
			-- council arguing over a weapon wants to see the weapon being replaced;
			-- "Retribution 5016" says nothing about whether this axe is an upgrade.
			r._eqLink, r._eqLink2 = nil, nil
			r.eqIcon2:Hide(); r.spec2:SetText("")
			-- a mark shows the T10 pieces it would upgrade, one icon each, like the
			-- equipped item on any other row, then the ones already sanctified in a
			-- gold frame; no tier = nothing shown
			r.tierIcons = r.tierIcons or {}
			local tier = isMark and d.tier or {}
			for k = 1, math.max(#tier, #r.tierIcons) do
				local b = r.tierIcons[k]
				local t = tier[k]
				if t and not b then
					b = CreateFrame("Button", nil, r)
					b:SetSize(38, 38)
					b:SetPoint("LEFT", COL_GEAR + (k - 1) * 42, 0)
					-- the octagon: grey = the mark would upgrade it, gold = already
					-- sanctified, orange = already the heroic one
					W.DressFramedIcon(b, nil, 38)
					b.tex = b.icon
					b:SetScript("OnEnter", function(self)
						GameTooltip:SetOwner(self, "ANCHOR_NONE")
						GameTooltip:ClearAllPoints()
						GameTooltip:SetPoint("TOPLEFT", f, "TOPRIGHT", 8, 0)
						GameTooltip:SetHyperlink("item:" .. self.id)
						GameTooltip:Show()
					end)
					b:SetScript("OnLeave", function() GameTooltip:Hide() end)
					b:SetFrameLevel(r:GetFrameLevel() + 6)
					r.tierIcons[k] = b
				end
				if b then
					if t and t.id then
						b.id = t.id
						b.tex:SetTexture((GetItemIcon and GetItemIcon(t.id)) or select(10, GetItemInfo(t.id))
							or "Interface\\Icons\\INV_Misc_QuestionMark")
						-- gold = sanctified (264), orange = the heroic one too (277): nothing left to do
						W.SetFramedIconGold(b, t.done and true or false)
						local lvl = t.done and select(4, GetItemInfo(t.id))
						if lvl and lvl >= 277 then b.frame:SetVertexColor(1, 0.55, 0.15)
						else b.frame:SetVertexColor(1, 1, 1) end
						b:Show()
					else
						b:Hide()
					end
				end
			end
			if isMark then
				r.eqIcon:Hide()
				-- no tier list at all = an Okanvil too old to check its tier
				r.spec:SetText((d.tier == nil and d.key ~= "wait") and "|cff6f7176(old Okanvil)|r" or "")
			elseif d.eq then
				local eqName, eqLink, eqQ = GetItemInfo(d.eq)
				r._eqLink = eqLink
				local tex = select(10, GetItemInfo(d.eq)) or (GetItemIcon and GetItemIcon(d.eq))
				if tex then r.eqIcon:SetTexture(tex); r.eqIcon:Show() else r.eqIcon:Hide() end
				-- Name in its rarity colour, trimmed: the column is ~120px and the
				-- first words are what identifies an item.
				local hex = (eqQ and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[eqQ])
					and ("|c" .. ITEM_QUALITY_COLORS[eqQ].hex:gsub("^|c", "")) or "|cffffffff"
				-- Two items (rings, trinkets) share the column, so each gets half.
				-- Trimmed by drawn width, not characters: the font size varies with
				-- the UI scale, so a character count still ran into the next item.
				local colW = COL_DIFF - 8 - COL_GEAR
				local nameW = (d.eq2 and math.floor(colW / 2) or colW) - (COL_SPEC - COL_GEAR) - 6
				fitText(r.spec, hex, eqName or "?", nameW)
				if d.eq2 then
					local n2, l2, q2, _, _, _, _, _, _, tex2 = GetItemInfo(d.eq2)
					r._eqLink2 = l2
					tex2 = tex2 or (GetItemIcon and GetItemIcon(d.eq2))
					r.eqIcon2:ClearAllPoints()
					r.eqIcon2:SetPoint("LEFT", r, "LEFT", COL_GEAR + math.floor(colW / 2), 0)
					if tex2 then r.eqIcon2:SetTexture(tex2) else r.eqIcon2:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
					r.eqIcon2:Show()
					local hex2 = (q2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q2])
						and ("|c" .. ITEM_QUALITY_COLORS[q2].hex:gsub("^|c", "")) or "|cffffffff"
					fitText(r.spec2, hex2, n2 or "?", nameW)
				end
			else
				r.eqIcon:Hide()
				r.spec:SetText("|cff6f7176(nothing)|r")
			end
			if d.diff then
				-- Green for an upgrade, red for a downgrade: the sign is the point.
				local c = d.diff > 0 and "|cffffd200+" or (d.diff < 0 and "|cffff5555" or "|cff8a8d93")
				r.diff:SetText(("%s%d|r"):format(c, d.diff))
			else
				r.diff:SetText("")
			end

			-- Council votes on this candidate, for the item on screen.
			local me = UnitName("player")
			local itemVotes = (rec.votes and rec.votes[boardItem]) or {}
			local voters = {}
			for voter, cand in pairs(itemVotes) do
				if cand == d.name then voters[#voters + 1] = voter end
			end
			table.sort(voters)
			r._voters = voters
			if #voters > 0 then
				r.vcount:SetText(#voters)
				r.vpill:Show()
				local shown = {}
				for k = 1, math.min(2, #voters) do
					shown[k] = L and L.ClassColorName and L.ClassColorName(voters[k]) or voters[k]
				end
				local more = #voters > 2 and ("  |cff8a8d93+" .. (#voters - 2) .. "|r") or ""
				r.vnames:SetText(table.concat(shown, "  ") .. more)
			else
				r.vpill:Hide()
				r.vnames:SetText("")
			end
			if itemVotes[me] == d.name then
				r.vbtn:SetKind("primary")
				r.vbtn.text:SetText("Voted")
			else
				r.vbtn:SetKind("secondary")
				r.vbtn.text:SetText("Vote")
			end
			r:Show()
		end
	end

	-- ---- who the Give button names ------------------------------------
	-- Default: the top row, which after the sort is the strongest claim broken by
	-- prio. If the selected person is not a candidate for THIS item (the board was
	-- paged to another one), fall back to the top rather than naming someone who
	-- is not on screen.
	local valid = false
	for _, d in ipairs(rows) do
		if d.name == f._pick then
			valid = true
			break
		end
	end
	-- never defaults to someone who passed or is still deciding: those are picked by hand
	if not valid then
		local top = rows[1]
		f._pick = (top and top.key ~= "pass" and top.key ~= "wait") and top.name or nil
	end

	for i = 1, math.min(#vis, #f.rows) do
		local r = f.rows[i]
		if r and r.sel then
			if vis[i].name == f._pick then r.sel:Show() else r.sel:Hide() end
		end
	end

	-- The STATE is the button's fill, not a colour code in its label. A `primary`
	-- button is a solid gold box whose text is painted dark, so an embedded grey
	-- lands grey-on-gold and cannot be read (and a green would fare no better).
	-- Flip the kind instead: gold = an action to take, surface = nothing to do.
	-- SetKind repaints (which sets the label colour), so any override has to come
	-- AFTER it. Disable() is deliberately not used: it would fight the widget's own
	-- hover repaint: the click is guarded by f._armed instead.
	-- A mirrored board belongs to a council member who is not running the loot:
	-- no Give there unless they are the master looter.
	local canGive = not rec.mirror
	if rec.mirror then
		local L = Okanvil.Loot
		canGive = (L and L.IsMasterLooter and L.IsMasterLooter()) and true or false
	end
	if canGive then f.give:Show(); f.giveNote:Hide() else f.give:Hide(); f.giveNote:Show() end

	local awardedTo = rec.awarded and rec.awarded[boardItem]
	if canGive and not awardedTo then f.de:Show() else f.de:Hide() end
	if not canGive then
		f._armed = false
	elseif awardedTo then
		f.give:SetKind("secondary")
		f.give.text:SetText("given to " .. awardedTo)
		f.give.text:SetTextColor(0.45, 0.85, 0.5)          -- green: done
		f._armed = false
	elseif waiting > 0 and not f._forceArm then
		-- SOMEONE IS STILL DECIDING. Awarding now would hand the item over while a
		-- raider was mid-click, and their answer would land on a decision already
		-- made. The button says who it is waiting for rather than going dead.
		--
		-- NOT a hard lock: someone who dies, disconnects or walks away would
		-- otherwise hold the whole council hostage. Clicking it once more overrides
		-- the wait -- see the OnClick, which arms it and asks again.
		f.give:SetKind("secondary")
		f.give.text:SetText(("waiting for %d ... (click to override)"):format(waiting))
		f.give.text:SetTextColor(0.95, 0.85, 0.25)
		f._armed = false
	elseif f._pick then
		f.give:SetKind("primary")
		f.give.text:SetText("Give to " .. f._pick)
		f._armed = true
	else
		f.give:SetKind("secondary")
		f.give.text:SetText("nobody wants this")
		f.give.text:SetTextColor(0.54, 0.55, 0.58)         -- dim: nothing to do
		f._armed = false
	end

	-- Empty board still needs a body: "nobody has answered yet" is a real state and
	-- a window that collapses to nothing looks broken instead of waiting.
	if #rows == 0 and #passed == 0 then
		f.count:SetText("|cff8a8d93waiting...|r")
	end
	-- +46 at the bottom for the Give / Skip row.
	f:SetHeight(TAB_TOP + TAB_S + 68 + math.max(#vis, 1) * BR_H + 52)
	f:Show()
end

-- Print who answered what. This is the board's data in text form -- when stage 3
-- draws it, it reads exactly these records.
function C_.PrintStatus(rec, final)
	rec = rec or C_.current
	if not rec then Okanvil:Print("Loot council: no round."); return end
	for i, link in ipairs(rec.items) do
		local line, any = {}, false
		for name, answers in pairs(rec.replies) do
			local a = answers[i]
			if a and a.key and a.key ~= "na" then
				local info = RESP_BY_KEY[a.key]
				local col = info and info.color
				local hex = col and ("|cff%02x%02x%02x"):format(col[1] * 255, col[2] * 255, col[3] * 255) or "|cffffffff"
				local gap = a.diff and (" |cff8a8d93(%+d)|r"):format(a.diff) or ""
				line[#line + 1] = ("%s%s|r=%s%s|r%s"):format(
					"|cffffd200", name, hex, (info and info.label) or a.key, gap)
				any = true
			end
		end
		Okanvil:Print(("  %s  %s"):format(link,
			any and table.concat(line, "  ") or "|cff8a8d93(no answers)|r"))
	end
	if final then
		local n = 0
		for _ in pairs(rec.replies) do n = n + 1 end
		Okanvil:Print(("  |cff8a8d93%d client(s) replied.|r"):format(n))
	end
end

-- The group's names: the count's tooltip lists who never answered.
function C_.GroupNames()
	local out = {}
	local n = GetNumRaidMembers and GetNumRaidMembers() or 0
	if n > 0 then
		for i = 1, n do
			local nm = GetRaidRosterInfo(i)
			if nm then out[#out + 1] = (nm:gsub("%-.*", "")) end
		end
	else
		for i = 1, (GetNumPartyMembers and GetNumPartyMembers() or 0) do
			local nm = UnitName("party" .. i)
			if nm then out[#out + 1] = nm end
		end
		out[#out + 1] = UnitName("player")
	end
	return out
end

-- ============================================================
-- THE PICKER -- tick items from THIS RUN's loot and ask about them together.
--
-- This exists because of a hard limit, not a preference: WoW's chat edit box
-- stops at 255 characters and one item link is about 88, so "/okcouncil ask"
-- with four links is truncated by the client before the addon ever sees it --
-- it looked like the addon capped at three. The wire itself carries twenty
-- items in one message, because it sends item IDs rather than links.
--
-- So the ML ticks a list instead of typing. The list is the loot module's own
-- record of the run, which is already per-boss and already de-duplicated.
-- ============================================================
local picker

function C_.OpenPicker()
	if not enabled() then
		Okanvil:Print("Loot Council is |cffff5555off|r for this character (Modules list).")
		return
	end
	local L = Okanvil.Loot
	if not (L and L.DropsByBoss) then
		Okanvil:Print("|cffff5555Loot council:|r the Loot module is not loaded.")
		return
	end

	-- Flatten the run into one list, newest boss first. Anything already given
	-- out is skipped: a decided item is not a council question.
	local rows = {}
	-- Still up for grabs?  Mirrors the Loot module's own `unowned` check, which is
	-- file-local there. The subtlety it encodes: under MASTER LOOT every drop is
	-- stamped receivedBy = <the ML> the moment the boss dies, minutes before
	-- anything is decided. Holding is not owning, so a plain `receivedBy` test
	-- would have shown an empty picker on every master-loot kill -- exactly the
	-- night this feature is for.
	local ml = L.MasterLooterName and L.MasterLooterName()
	local function undecided(dp)
		-- Awarded or disenchanted is decided, whoever it went to -- the ML
		-- included, which the name test below cannot tell from "still holding".
		if dp.awarded or dp.de then return false end
		if dp.heldBy and dp.heldBy ~= "" and (not dp.receivedBy or dp.receivedBy == "") then
			return true
		end
		if not dp.receivedBy or dp.receivedBy == "" then return true end
		return ml ~= nil and dp.receivedBy == ml
	end

	-- DropsByBoss returns { {boss=, items={dp,...}}, ... } -- the per-boss field is
	-- `items`, not `drops`.
	for _, grp in ipairs(L.DropsByBoss() or {}) do
		for _, dp in ipairs(grp.items or {}) do
			if undecided(dp) and C_.IsCouncilItem(dp.item or dp.id) then
				local wn = L.RollWinner and L.RollWinner(dp)
				rows[#rows + 1] = { dp = dp, boss = grp.boss or dp.boss or "", rolled = wn and wn.player }
			end
		end
	end

	if #rows == 0 then
		Okanvil:Print("|cffe0b860Loot council:|r nothing undecided in this run to ask about.")
		return
	end

	if not picker then
		picker = Okanvil:Popup("Pick items for the council")
		picker:SetWidth(430)
		picker:SetFrameStrata("DIALOG")
		picker:SetFrameLevel(40)     -- opened on top of everything else here
		picker:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
		picker:EnableKeyboard(false)
		picker.rows = {}

		local ask = W.Button(picker, "Ask the raid", "primary")
		ask:SetSize(140, 24)
		ask:SetPoint("BOTTOMRIGHT", -12, 16)
		ask:SetScript("OnClick", function()
			local links, boss = {}, nil
			for _, r in ipairs(picker.rows) do
				if r:IsShown() and r._on and r._dp then
					links[#links + 1] = r._dp.item or tostring(r._dp.id)
					boss = boss or r._boss
				end
			end
			if #links == 0 then
				Okanvil:Print("|cffe0b860Loot council:|r tick at least one item.")
				return
			end
			picker:Hide()
			C_.Ask(links, boss or "")
		end)

		local none = W.Button(picker, "Clear")
		none:SetSize(80, 24)
		none:SetPoint("BOTTOMLEFT", 12, 16)
		none:SetScript("OnClick", function()
			for _, r in ipairs(picker.rows) do
				r.SetOn(false)
			end
		end)
	end

	local PR_H = 30
	for i = 1, math.max(#rows, #picker.rows) do
		local r = picker.rows[i]
		if i > #rows then
			if r then r:Hide() end
		else
			if not r then
				r = CreateFrame("Frame", nil, picker)
				r:SetPoint("TOPLEFT", 12, -(34 + (i - 1) * PR_H))
				r:SetPoint("TOPRIGHT", -12, -(34 + (i - 1) * PR_H))
				r:SetHeight(PR_H - 2)

				-- the settings' checkbox, without W.Check's label and get/set: here
				-- the row IS the label. Ticked = going to the council.
				local tick = CreateFrame("Button", nil, r)
				tick:SetSize(20, 20)
				tick:SetPoint("LEFT", 2, 0)
				local box, mark = W.CheckTextures(tick, 20)
				box:SetPoint("CENTER")
				function r.SetOn(v)
					r._on = v and true or false
					if r._on then mark:Show() else mark:Hide() end
				end
				tick:SetScript("OnClick", function() r.SetOn(not r._on) end)
				tick:SetScript("OnEnter", function() box:SetVertexColor(1.25, 1.25, 1.25) end)
				tick:SetScript("OnLeave", function() box:SetVertexColor(1, 1, 1) end)
				r.tick = tick

				r.icon = r:CreateTexture(nil, "ARTWORK")
				r.icon:SetSize(20, 20)
				r.icon:SetPoint("LEFT", 30, 0)
				r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

				r.label = W.Text(r, "", nil)
				r.label:SetPoint("LEFT", 56, 0)
				r.label:SetJustifyH("LEFT")
				picker.rows[i] = r
			end
			local row = rows[i]
			local dp = row.dp
			r._dp, r._boss = dp, row.boss
			-- Everything undecided starts ticked: the common case is "ask about
			-- what just dropped", and unticking two is less work than ticking six.
			-- An item already rolled on starts unticked: it has a winner waiting
			-- to be handed it, and asking again would be a second decision.
			r.SetOn(not row.rolled)

			local link = dp.item or ""
			local nm, _, q = GetItemInfo(link ~= "" and link or dp.id)
			local tex = (link ~= "" and select(10, GetItemInfo(link)))
				or (GetItemIcon and GetItemIcon(dp.id))
			if tex then r.icon:SetTexture(tex) end
			local hex = (q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q])
				and ("|c" .. ITEM_QUALITY_COLORS[q].hex:gsub("^|c", "")) or "|cffffffff"
			r.label:SetText(("%s%s|r  |cff8a8d93%s|r"):format(
				hex, nm or dp.name or ("item " .. tostring(dp.id)), row.boss)
				.. (row.rolled and ("  |cffffd200rolled: " .. row.rolled .. "|r") or ""))
			r:Show()
		end
	end

	picker:SetHeight(34 + #rows * PR_H + 50)
	picker:Show()
end

-- Repaint whatever header shows council night: the Loot page, when built.
C_._repaintHeader = function()
	local fill = Okanvil._lootFill
	if fill and fill.dash and fill.dash.Refresh then fill.dash:Refresh() end
end

-- The council's panel under the Council tile on the Loot page: the night's
-- state, its on / off switch, and the options. body.needH is the height it uses.
function C_.BuildRunTab(body)
	-- Two columns: what the council IS doing on the left, the buttons that act on
	-- it pinned right. Centred controls in a wide page leave the eye hunting;
	-- against an edge they are always in the same place.
	local BH, BW = 24, 160

	-- ---- left: state --------------------------------------------------
	local state = W.Text(body, "", "body")
	state:SetPoint("TOPLEFT", 14, -14)

	local hint = W.Text(body, "", "note", "dim")
	hint:SetPoint("TOPLEFT", 14, -36)
	hint:SetPoint("RIGHT", body, "RIGHT", -(BW + 28), 0)
	hint:SetJustifyH("LEFT")

	local function paintState()
		if not enabled() then
			state:SetText("|cffff5555Off|r for this character")
			hint:SetText("Switch it on in Modules.")
		elseif not canSeeBoard() then
			state:SetText("|cff8a8d93Officers run the council|r")
			hint:SetText("You will get a popup when an item is put to the raid.")
		elseif C_.current then
			local n = 0
			for _ in pairs(C_.current.replies) do n = n + 1 end
			state:SetText(("|cffffd200Round open|r -- %d item(s), %d repl%s")
				:format(#C_.current.items, n, n == 1 and "y" or "ies"))
			hint:SetText("|cff8a8d93/okcouncil board|r reopens the board, "
				.. "|cff8a8d93/okcouncil close|r ends the round.")
		elseif C_.active then
			state:SetText("|cffffd200Council night|r -- no round open")
			hint:SetText("Open the mini roll and press |cffe0b860Ask this one|r on an item.")
		elseif C_.remoteNight then
			state:SetText("|cffffd200Council night|r -- run by |cffe0b860" .. C_.remoteNight .. "|r")
			hint:SetText("The board opens on your screen when they put an item to the raid.")
		else
			state:SetText("|cff8a8d93Council night is off|r")
			hint:SetText("The master looter turns it on by picking Council.")
		end
	end
	paintState()

	-- ---- right: council night on / off -------------------------------
	-- Picking SR or Roll ends the night too; this is the switch while Council
	-- stays picked. The test round is /okcouncil test, not a button.
	local nightB = W.Button(body, "End council night")
	nightB:SetSize(BW, BH)
	nightB:SetPoint("TOPRIGHT", -14, -14)
	local function paintNight()
		if not (enabled() and C_.MayRun()) then nightB:Hide(); return end
		nightB:Show()
		nightB:SetKind(C_.active and "secondary" or "primary")
		nightB.text:SetText(C_.active and "End council night" or "Start council night")
	end
	nightB:SetScript("OnClick", function()
		C_.SetActive(not C_.active)
		paintNight(); paintState()
	end)
	nightB:Tooltip("Council night puts the Council row in the mini roll.\nOnly the master looter switches it.")
	paintNight()
	body:HookScript("OnShow", function() paintNight(); paintState() end)
	-- the master looter's CNIGHT answer lands after the page has drawn
	C_._paintRun = function() if body:IsVisible() then paintNight(); paintState() end end

	-- ---- options ------------------------------------------------------
	-- One button tall now, not two. The gap above the heading matches the one
	-- between its rule and the first row, so OPTIONS does not sit on the text.
	local y = -14 - (BH + 6) - 30
	y = W.Section(body, "OPTIONS", 14, y) - 8

	-- One setting per row: title, what it does, ON / OFF (see W.ToggleRow).
	local function opt(label, desc, tip, getFn, setFn)
		local c = W.ToggleRow(body, label, desc, getFn, setFn)
		c:SetPoint("TOPLEFT", 14, y)
		c:SetPoint("RIGHT", body, "RIGHT", -14, 0)
		c:Tooltip(tip)
		y = y - c:GetHeight()
		return c
	end

	-- Off by default: many master looters take the whole corpse and ask later.
	opt("Ask automatically when a corpse opens",
		"On a council night, every epic goes to the raid as one question",
		"Off by default. Only on a council night, and only for epics.\n"
			.. "Off = loot the corpse, then ask from the mini roll when you are ready.",
		function() return db().autoAsk end,
		function(v) db().autoAsk = v end)

	-- The master looter opens it, for this raid ID only (Wishlist.lua).
	local Wi = Okanvil.Wish
	if Wi and Wi.CanTrigger() then
		local wrow = opt("Wishlist",
			"25-man, normal & heroic: raiders pick one item for this raid ID; the board marks it WISH",
			"Closed on every new raid ID. Opening it opens the wish window for raiders with Okanvil.\n"
				.. "Raiders can change their wish until you lock it. It is not a reserve.",
			function() return Wi.IsOn() end,
			function(v) Wi.SetOn(v); if Wi._paintRow then Wi._paintRow() end end)
		-- Opening it warns the whole raid: only the checkbox switches it, a click
		-- elsewhere on the line does nothing.
		local toggle = wrow:GetScript("OnClick")
		wrow:SetScript("OnClick", nil)
		wrow.btn:EnableMouse(true)
		wrow.btn:SetScript("OnMouseUp", function(s, button)
			if button == "LeftButton" and s:IsMouseOver() and toggle then toggle(wrow) end
		end)
		-- Clear beside the switch, the same as the WH panel's
		local clr = W.Button(wrow, "Clear"); clr:SetSize(52, 22)
		clr:SetPoint("RIGHT", wrow.btn, "LEFT", -6, 0)
		clr:Tooltip("Clear every wish on this raid ID.\nEveryone gets the window again.")
		clr:SetScript("OnClick", function()
			Okanvil:Confirm("Clear every wish on this raid ID?\n|cff8a8d93Everyone picks again.|r", "Clear", Wi.Clear)
		end)
		-- Lock: keep the wishes in, take no new ones
		local lock = W.Button(wrow, "Lock"); lock:SetSize(62, 22)
		lock:SetPoint("RIGHT", clr, "LEFT", -6, 0)
		lock:Tooltip("Lock: the wishes already sent stay, nobody can add one.\nThe raiders' wish window closes.")
		-- locked: gold, like an ON switch
		local function paintLock()
			local on = Wi.IsLocked()
			lock:SetKind(on and "primary" or nil)
			lock.text:SetText(on and "Locked" or "Lock")
		end
		lock:SetScript("OnClick", function()
			if not Wi.IsOn() then Okanvil:Print("Turn the wishlist on first."); return end
			Wi.SetLocked(not Wi.IsLocked())
			paintLock()
		end)
		lock:SetScript("OnShow", paintLock)
		paintLock()
		Wi._paintLock = paintLock
		-- Lock and Clear only mean something while the wishlist is on
		local function paintRow()
			if Wi.IsOn() then lock:Show(); clr:Show() else lock:Hide(); clr:Hide() end
		end
		wrow:HookScript("OnShow", paintRow)
		paintRow()
		Wi._paintRow = paintRow
		if wrow.desc then wrow.desc:SetPoint("RIGHT", lock, "LEFT", -12, 0) end
		wrow.text:SetPoint("RIGHT", lock, "LEFT", -12, 0)
	end

	body.needH = -y + 8
	body.refresh = paintState
	C_._paintState = paintState
	return body
end

-- ============================================================
-- TEST MODE -- a real round on fake items, with no boss and no master loot.
--
-- The trick is RCLootCouncil's (core.lua Test): use THE GEAR YOU ARE WEARING as
-- the test items. No fixture list to maintain, nothing that turns out not to be
-- cached, and the armour type is right for your class -- which is exactly what
-- the eligibility filter is being tested against. A hardcoded list covers a
-- naked character.
--
-- It runs the REAL path: same broadcast, same round ids, same raider frame, same
-- board. A test that shortcuts past the wire tests the half that was never
-- broken.
--
-- It must NEVER touch real loot: no master-loot give, no history entry. A test
-- award prints what it would have done. The worst outcome here is a real raid
-- running in test mode and the loot never being handed out, so it says TEST
-- loudly and ends on its own.
-- ============================================================
C_.testMode = false

-- ICC-era epics, for a character wearing nothing.
local TEST_FALLBACK = { 50735, 50708, 50664, 50179, 50362, 50353, 50184, 50404 }

function C_.Test(num)
	if not enabled() then
		Okanvil:Print("Loot Council is |cffff5555off|r for this character (Modules list).")
		return
	end
	-- Solo only. In a group the roster watcher below ends a test the moment it
	-- starts, and a test in a real raid is exactly the state that gives no loot
	-- away -- in a group, run the council for real.
	if (GetNumRaidMembers and GetNumRaidMembers() > 0)
		or (GetNumPartyMembers and GetNumPartyMembers() > 0) then
		Okanvil:Print("|cffe0b860Loot council:|r the test only runs solo -- "
			.. "in a group the council runs for real.")
		return
	end
	num = tonumber(num) or 3
	if num < 1 then num = 1 elseif num > 8 then num = 8 end

	-- With a soft-reserve list loaded, test with the reserved items so the [SR]
	-- tags, the blocked MS rolls and the roll call all show up. Otherwise,
	-- everything currently equipped, slots 1-18.
	local pool = {}
	local srd = Okanvil.db.softres
	if srd and srd.items then
		local cold = 0
		for id in pairs(srd.items) do
			if GetItemInfo(id) then
				pool[#pool + 1] = id
			else
				-- never seen on this client: ask the server, it is ready next press
				cold = cold + 1
				if Okanvil.WarmItem then Okanvil:WarmItem(id) end
			end
		end
		if #pool == 0 and cold > 0 then
			Okanvil:Print("|cffe0b860[TEST]|r loading the " .. cold
				.. " soft-reserved item(s) -- press Test again in a second.")
			return
		end
	end
	if #pool == 0 then
		for slot = 1, 18 do
			local id = GetInventoryItemID and GetInventoryItemID("player", slot)
			if id then pool[#pool + 1] = id end
		end
	end
	if #pool == 0 then pool = TEST_FALLBACK end
	-- your own wish first, so the WISH row shows in the test (/okwish test)
	local myWish = Okanvil.Wish and Okanvil.Wish.Of(UnitName("player"))
	if myWish and not GetItemInfo(myWish) then myWish = nil end

	-- One piece of gear from the BAGS as well, first in the list. Equipped items
	-- are not in the bags, so awarding one could never show the "owed by trade"
	-- square; this one can.
	local bagItem
	for bag = 0, 4 do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local link = GetContainerItemLink(bag, slot)
			local q
			if link then q = select(3, GetItemInfo(link)) end
			if q and q >= 4 and IsEquippableItem(link) then
				bagItem = tonumber(link:match("item:(%d+)"))
				break
			end
		end
		if bagItem then break end
	end

	-- Distinct items where possible: asking about the same ring twice tests
	-- nothing the first one did not.
	local picked, seen = {}, {}
	if bagItem then picked[1] = bagItem; seen[bagItem] = true end
	if myWish and not seen[myWish] then picked[#picked + 1] = myWish; seen[myWish] = true end
	local guard = 0
	while #picked < num and guard < 200 do
		guard = guard + 1
		local id = pool[math.random(1, #pool)]
		if not seen[id] then
			seen[id] = true
			picked[#picked + 1] = id
		end
		if #seen >= #pool then break end
	end
	if #picked == 0 then
		Okanvil:Print("|cffff5555Council test:|r no items to test with.")
		return
	end

	C_.testMode = true
	C_.testStarted = GetTime()      -- the watcher's grace period runs from here
	-- A test is a council night by definition: without this the mini roll draws no
	-- Council row and the test would not reach the thing it is meant to exercise.
	-- The previous state is kept so ending the test puts it back, instead of
	-- switching off a council night that was already running.
	C_.testPrevActive = C_.active
	C_.SetActive(true)
	-- Remembered so a /reload mid-test can say what happened. testMode itself is
	-- deliberately NOT restored -- coming back from a reload silently still in a
	-- test is how a real raid ends up giving nothing away.
	-- Stamped with the CHARACTER. The council db is account-wide but the test's
	-- fake drops go into the loot module, which is per character -- so logging
	-- onto an alt used to restore "a test is running" for drops that toon has
	-- never seen, and its clean-up would have found nothing to clean.
	local d = db()
	d.testAt = time()
	d.testWho = UnitName and UnitName("player") or "?"

	-- Put the test items through the LOOT pipeline too, so the mini roll lists
	-- them and the Council row can actually be pressed. Without this the test
	-- exercised the popup and the board but never the mini roll integration --
	-- which is where the round is started on a real night.
	--
	-- Outside an instance nothing records, so world-test is switched on for the
	-- duration and remembered, to be put back exactly as it was on test off.
	local L = Okanvil.Loot
	if L and L.InjectTestDrop then
		-- Clear the PREVIOUS test's drops first. Without this every /okcouncil
		-- test piled three more items onto the list -- four runs and the mini roll
		-- was showing twenty items that never dropped.
		if L.PurgeTestDrops then L.PurgeTestDrops() end
		if L.WorldTest then
			C_.testPrevWorld = L.WorldTest()
			if not C_.testPrevWorld then L.WorldTest(true) end
		end
		local made = 0
		for _, id in ipairs(picked) do
			local dp, why = L.InjectTestDrop(id, "Council test")
			if dp then made = made + 1
			elseif why and made == 0 then
				Okanvil:Print("|cff8a8d93[TEST] mini roll: " .. why .. "|r")
			end
		end
		if made == 0 then
			-- The mini roll IS the test now, so failing to fill it is a failed test
			-- rather than a detail -- say so instead of leaving an empty window.
			Okanvil:Print("|cffff5555[TEST]|r nothing reached the mini roll. "
				.. "Check the Log threshold on the Loot page.")
			C_.testMode = false
			return
		end
		if made > 0 and Okanvil.RollMgr then
			-- OnLootWindow is the "there is loot, show yourself" entry point the
			-- real pipeline uses, so it opens the window if needed and refreshes it
			-- if it is already up. Toggle would CLOSE an open one, and there is no
			-- RM.IsShown to test against.
			local RMg = Okanvil.RollMgr
			pcall(RMg.OnLootWindow or RMg.Rebuild)
		end
	end

	-- The round is NOT started here. Test mode drops the items into the mini roll
	-- and stops -- you then pick one and press "Ask this one", which is the order
	-- a real night happens in: the loot appears, the ML chooses, THEN the raid is
	-- asked. Auto-asking here would have skipped the step the mini roll row exists
	-- for, and that row is the part that has never been exercised.
	Okanvil:Print(("|cffe0b860[TEST]|r Loot council: %d item(s) in the mini roll. "
		.. "Pick one and press |cffe0b860Ask this one|r."):format(#picked))
	Okanvil:Print("|cff8a8d93[TEST] Nothing will be given away. "
		.. "/okcouncil test off when done.|r")
	if C_._paintTest then pcall(C_._paintTest) end
end

function C_.TestOff()
	C_.testMode = false
	-- Only the TEST round's windows. A real round open on the board is left alone.
	local rec = C_.current
	if rec and rec.test then
		if rec.round and C.CloseAsk then C.CloseAsk(rec.round) end
		if current and current.round == rec.round then closeFrame() end
		if board then board:Hide() end
	end
	if C_.SyncRollButton then C_.SyncRollButton() end

	-- Put the loot module back exactly as it was. Leaving world-test on would
	-- silently record open-world drops for the rest of the session, and leaving
	-- the fake drops in the run would put them in the history and the export.
	local L = Okanvil.Loot
	if L then
		-- DELETE the fake drops by their mark, not "hide whatever is in the
		-- current session": the test injects with world recording on, so by now
		-- the active session can be a different one and the items came straight
		-- back the next time the mini roll opened.
		if L.PurgeTestDrops then L.PurgeTestDrops()
		elseif L.ClearActiveDrops then L.ClearActiveDrops() end
		-- After a reload testPrevWorld is gone, so "restore what it was" has
		-- nothing to restore and world recording would stay on for ever. With no
		-- record of the previous state, off is the safe answer: it is the default,
		-- and /okloottest world turns it back on in one command.
		if L.WorldTest then L.WorldTest(false) end
	end
	C_.testPrevWorld = nil
	if Okanvil.Trade then Okanvil.Trade.ClearTest() end
	local dOff = db()
	dOff.testAt, dOff.testWho = nil, nil
	-- A test switched council night ON to get the mini roll row. Ending the test
	-- puts it back as it was: left on, the flag sat there for its whole NIGHT_TTL
	-- life and a real raid hours later opened a corpse straight into an auto-ask;
	-- forced off, it killed a council night that was running before the test.
	C_.SetActive(C_.testPrevActive)
	C_.testPrevActive = nil
	if Okanvil.RollMgr and Okanvil.RollMgr.Rebuild then pcall(Okanvil.RollMgr.Rebuild) end

	if C_._paintTest then pcall(C_._paintTest) end
	Okanvil:Print("|cffe0b860Loot council:|r test mode off -- test drops hidden, "
		.. "world recording restored.")
end

-- ============================================================
-- WHO RUNS THE LOOT. On every loot-method / roster change, acts only when the
-- master looter moved: the old one's council-night state no longer applies,
-- and the new one is asked for theirs.
--
-- Nothing here ever SETS master loot: the Loot page's "Set me as ML" button is
-- the only way, and it asks first.
-- ============================================================
local lastML            -- ML name seen by the last check; "" = no master loot

local function mlCheck()
	local L = Okanvil.Loot
	if not (L and L.MasterLooterName) then return end
	local ml = L.MasterLooterName() or ""
	if ml == lastML then return end
	lastML = ml
	C_.remoteNight = nil
	if C_._repaintHeader then pcall(C_._repaintHeader) end
	if ml ~= "" then C_.QueryNight() end
end

do
	local mlQueued
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:RegisterEvent("RAID_ROSTER_UPDATE")
	ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
	ev:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
	ev:SetScript("OnEvent", function(_, event)
		-- Every loot-method change, whoever made it: another addon flipping the
		-- group to master loot otherwise looks exactly like Okanvil doing it.
		if event == "PARTY_LOOT_METHOD_CHANGED" and GetLootMethod then
			local method = GetLootMethod()
			local L = Okanvil.Loot
			local ml = L and L.MasterLooterName and L.MasterLooterName()
			Okanvil:Trace("LOOT", ("loot method now %s (ML %s)"):format(tostring(method), tostring(ml or "none")))
		end
		-- Coalesced: a roster update storm schedules one check, not fifty.
		if not mlQueued then
			mlQueued = true
			C.After(1, function() mlQueued = false; mlCheck() end)
		end
	end)
end

-- ============================================================
-- A TEST LASTS EXACTLY AS LONG AS ITS WINDOWS.
--
-- No timer, no half-hour grace: close the raider frame, the board and the mini
-- roll and the test is over. That is what "press it to test, press it again to
-- stop" should have meant -- anything that outlives what is on screen comes back
-- later as a test nobody remembers starting.
--
-- Checked on a slow tick rather than hooked onto each frame's OnHide: three
-- windows closing one after another would otherwise end the test on the first.
do
	local w = CreateFrame("Frame")
	local acc = 0
	w:SetScript("OnUpdate", function(_, e)
		if not C_.testMode then return end
		-- Grace at the start: the mini roll takes a moment to appear after the
		-- test injects its drops, and without this the watcher would find nothing
		-- open and end the test before it had begun.
		if (GetTime() - (C_.testStarted or 0)) < 3 then return end
		acc = acc + e
		if acc < 1 then return end
		acc = 0
		local anyOpen =
			(frame and frame:IsShown())
			or (board and board:IsShown())
			or (picker and picker:IsShown())
			or (Okanvil.RollMgr and Okanvil.RollMgr.IsOpen and Okanvil.RollMgr.IsOpen())
		if anyOpen then return end
		Okanvil:Print("|cffe0b860Loot council:|r test windows closed -- test mode ended.")
		C_.TestOff()
	end)
end

-- A test ends the moment a real group forms. Test mode is a solo scaffold: kept
-- across joining a raid it made the mini roll think you were the master looter,
-- and it survived closing every window because nothing was watching.
do
	local g = CreateFrame("Frame")
	g:RegisterEvent("RAID_ROSTER_UPDATE")
	g:RegisterEvent("PARTY_MEMBERS_CHANGED")
	g:SetScript("OnEvent", function()
		if not C_.testMode then return end
		local inGroup = (GetNumRaidMembers and GetNumRaidMembers() > 0)
			or (GetNumPartyMembers and GetNumPartyMembers() > 0)
		if not inGroup then return end
		Okanvil:Print("|cffe0b860Loot council:|r you joined a group -- test mode ended.")
		C_.TestOff()
	end)
end

-- RELOAD TEST (off). Lets a solo council test survive a quick /reload, to test
-- the reload path without a second player. Three blocks, all marked RELOAD TEST:
-- this one, the restore in the login block, and the save in C_.SaveAsk.
-- Uncomment all three together.
--
-- Stamps the moment a test leaves, so the login block can tell a /reload
-- (seconds) from anything else.
--[[
do
	local o = CreateFrame("Frame")
	o:RegisterEvent("PLAYER_LOGOUT")
	o:SetScript("OnEvent", function()
		if not C_.testMode then return end
		local d = db()
		d.testOutAt = time()
		d.testPrevActive = C_.testPrevActive
		d.testPrevWorld = C_.testPrevWorld
	end)
end
--]]

-- ============================================================
-- AUTO-OPEN on the loot window.
--
-- The master looter opens the corpse and the council starts -- that is the
-- moment everything is on screen and nobody has walked off yet.
--
-- Opt-in twice over: the council must be on for the session (Council night), and
-- auto-ask must be on in the settings. A guild that calls each item by hand
-- should not have a round fire on every kill.
-- ============================================================
-- Gear and tier tokens go to the council; a Shadowfrost Shard, Primordial
-- Saronite, an orb or a pattern does not -- those go to their collector or a
-- roll. Not equippable and not a token = not a council item. An item the client
-- has not cached yet counts as one, so nothing real is dropped by a cold cache.
function C_.IsCouncilItem(item)
	local id = tonumber(item) or tonumber(tostring(item or ""):match("item:(%d+)"))
	if not id then return false end
	local P = Okanvil.Prof
	if P and P.TokenUsable and P.TokenUsable(id, "WARRIOR") ~= nil then return true end
	local name, _, _, _, _, _, _, _, equip = GetItemInfo(id)
	if not name then return true end
	return equip ~= nil and equip ~= ""
end

function C_.AutoAsk()
	if not (enabled() and C_.active) then return end
	if not db().autoAsk then return end
	if not canSeeBoard() then return end
	-- Only the corpse the master looter opens: an assist who can run the council
	-- opening one too would put the same items to the raid twice.
	local inGroup = (GetNumRaidMembers and GetNumRaidMembers() > 0)
		or (GetNumPartyMembers and GetNumPartyMembers() > 0)
	local ML = Okanvil.Loot
	if inGroup and not (ML and ML.MasterLooterName and ML.MasterLooterName() == UnitName("player")) then return end
	-- Never on top of an open round: the raid is already answering something.
	if C_.current and not C_.current.closed then return end
	-- NEVER auto-ask from a test. A test round exists to exercise the UI, not to
	-- put a question to twenty-four other people the moment a corpse opens.
	if C_.testMode then return end

	local L = Okanvil.Loot
	if not (L and L.DropsByBoss) then return end

	-- Only what is in the corpse that just opened -- NOT the whole run. The
	-- picker is for sweeping a night; this is "the boss just died".
	local links = {}
	local n = (GetNumLootItems and GetNumLootItems()) or 0
	local thr = tonumber(db().autoRarity or 4) or 4
	for slot = 1, n do
		if LootSlotIsItem and LootSlotIsItem(slot) then
			local link = GetLootSlotLink and GetLootSlotLink(slot)
			if link then
				local rarity = select(3, GetItemInfo(link)) or 0
				if rarity >= thr and C_.IsCouncilItem(link) then links[#links + 1] = link end
			end
		end
	end
	if #links == 0 then return end
	-- No boss label: the Loot module's resolveBoss() is file-local, and the header
	-- falls back to "N items" without it. Not worth reaching into another module
	-- for a caption.
	C_.Ask(links, "")
	-- SAY WHY. A board appearing on its own reads as a bug, not a feature -- and
	-- if it was not wanted, the way to stop it has to be in the same line rather
	-- than three clicks into a settings page.
	Okanvil:Print("|cffe0b860Loot council:|r asked automatically on this corpse "
		.. "(|cffffd200/okcouncil auto off|r to stop).")
end

do
	-- Hooked at LOGIN, not at file load: this module loads BEFORE Loot.lua and
	-- LootRoll.lua in the .toc, so Okanvil.Loot does not exist yet here -- and
	-- LootRoll installs its own onLootWindow later, which would overwrite ours.
	-- Waiting until everything is loaded means we chain the mini roll's handler
	-- rather than replacing it (it allows ONE handler and owns it today).
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function()
		local L = Okanvil.Loot
		if L then
			local prev = L.onLootWindow
			L.onLootWindow = function()
				if prev then prev() end
				local ok, err = pcall(C_.AutoAsk)
				if not ok and Okanvil.Err then Okanvil:Err("Council.AutoAsk", err) end
			end
		end

		-- RESTORE an open round after a /reload or a disconnect. Deferred a few
		-- seconds: at PLAYER_LOGIN the item cache is cold and the frame would draw
		-- rows with no name or icon.
		-- Every automatic council option is opt-in. They used to default ON, so
		-- installs that already saved them are switched off once; anyone who
		-- wants one turns it back on under the Council tile of the Loot page.
		do
			local d = db()
			if not d._autoOffV1 then
				d.autoAsk = false
				d._autoOffV1 = true
			end
			-- settings of options that no longer exist (the Council tile is the choice now)
			d.askOnML, d.nightAnswer, d.whisperWinner, d.hidePrio = nil, nil, nil, nil
		end

		-- COUNCIL NIGHT survives a reload, for NIGHT_TTL, so it covers a raid night and
		-- expires before the next one -- "is tonight a council night" is a decision
		-- about tonight, and a flag that outlived the raid is the one that silently
		-- does the wrong thing three weeks later.
		do
			local d = db()
			local at = tonumber(d.activeAt or 0) or 0
			-- the loot mode decides: council night only comes back with Council picked.
			-- Someone else's mode has not arrived yet at login, so a helper in their
			-- group keeps the night they switched on.
			local SRM = Okanvil.SoftRes
			local councilMode = not (SRM and SRM.Mode) or SRM.Mode() == "council"
				or (SRM.CanSetMode and not SRM.CanSetMode())
			if at > 0 and (time() - at) < NIGHT_TTL and councilMode then
				C_.active = true
				Okanvil:Print("|cffe0b860Loot council:|r council night restored.")
			else
				d.activeAt = nil
			end
			-- A reload during a test leaves fake drops in the run and test mode off
			-- (it is never restored). Say so, with the one command that cleans up --
			-- otherwise the loot list quietly keeps items that never dropped.
			-- TEST MODE is restored too, for 30 minutes. Solo, test mode is what
			-- makes amML() true -- without it the mini roll loses every ML control
			-- and the test items sit there unusable, which is exactly what a reload
			-- looked like. The danger of coming back silently in a test is real, so
			-- it is bounded and loud instead of silent: half an hour, an on-screen
			-- [TEST] on the board, and a line in chat every login.
			-- TEST MODE IS NEVER RESTORED. It is a button you press and a button you
			-- press again -- carrying it across a login meant it came back on an
			-- alt, on the next session, and on a real raid night, which is exactly
			-- the state that makes loot silently never get handed out.
			--
			-- What IS carried is the mess it leaves: fake drops in that character's
			-- loot list. Say so once, name the command, and forget the flag.
			local tAt = tonumber(d.testAt or 0) or 0
			local me  = UnitName and UnitName("player")
			-- RELOAD TEST (off, see the PLAYER_LOGOUT block): a test left less than
			-- a minute ago, by this character, while solo, comes back -- that is a
			-- /reload, never a new session or a raid. To enable, uncomment and turn
			-- the `if` below into `elseif`.
			--[[
			local outAt = tonumber(d.testOutAt or 0) or 0
			local solo = not ((GetNumRaidMembers and GetNumRaidMembers() > 0)
				or (GetNumPartyMembers and GetNumPartyMembers() > 0))
			d.testOutAt = nil
			if tAt > 0 and d.testWho == me and solo and outAt > 0 and (time() - outAt) <= 60 then
				C_.testMode = true
				C_.testStarted = GetTime() + 5      -- windows reappear over the next seconds
				C_.testPrevActive = d.testPrevActive
				C_.testPrevWorld = d.testPrevWorld
				C_.active = true
				Okanvil:Print("|cffe0b860[TEST]|r test restored after the reload.")
			--]]
			if tAt > 0 and (d.testWho == nil or d.testWho == me) then
				d.testAt, d.testWho = nil, nil
				Okanvil:Print("|cffe0b860Loot council:|r a test was left open before. "
					.. "Run |cffffd200/okcouncil test off|r to clear its drops.")
			end

			-- ONE rebuild, after both flags are settled. The mini roll draws its
			-- Council row and its ML controls at BUILD time, so restoring the flags
			-- without this left the window exactly as it was: a plain loot list.
			-- OnLootWindow, not Rebuild: it OPENS the window as well as redrawing
			-- it. Rebuild alone repainted a window that was not on screen, so the
			-- Council row was correct but you had to go and find it by hand.
			-- Opened only inside a raid or with loot on the list: logging in to
			-- Dalaran with council night still on popped an empty "No loot yet".
			if C_.active or C_.testMode then
				local RMg = Okanvil.RollMgr
				local _, itype = IsInInstance()
				local L = Okanvil.Loot
				local drops = L and L.DropsByBoss and L.DropsByBoss() or {}
				if RMg then
					if itype == "raid" or #drops > 0 then pcall(RMg.OnLootWindow or RMg.Rebuild)
					elseif RMg.Rebuild then pcall(RMg.Rebuild) end
				end
			end

			-- And the board, for whoever was running the round.
			local okA, errA = pcall(C_.RestoreAsk)
			if not okA and Okanvil.Err then Okanvil:Err("Council.RestoreAsk", errA) end
		end

		C.After(4, function()
			if not enabled() then return end
			local d = db()
			local saved = d.openRound
			if not saved or not saved.round then return end

			-- Too old, a different character, or a different zone -- any of the
			-- three means the round is over. The db is account-wide and the round
			-- was not, and walking into a 5-man does not resume last raid's
			-- question.
			local age = (time() or 0) - (saved.savedAt or 0)
			local me   = UnitName and UnitName("player")
			local zone = (GetRealZoneText and GetRealZoneText()) or ""
			if age > ROUND_TTL
				or (saved.who and me and saved.who ~= me)
				or (saved.zone and saved.zone ~= "" and zone ~= "" and saved.zone ~= zone) then
				d.openRound = nil
				return
			end

			local items = {}
			for i, it in ipairs(saved.items or {}) do
				Okanvil:WarmItem(it.link)
				items[i] = { idx = it.idx, link = it.link, answer = it.answer,
					slotText = it.slotText, owned = it.owned }
			end
			if #items == 0 then d.openRound = nil; return end

			current = {
				round = saved.round, asker = saved.asker, boss = saved.boss,
				items = items, na = saved.na,
				restored = true,        -- hidden until the asker confirms (below)
			}

			-- Unanswered items still need an answer -> put the frame back. If the
			-- raider had already answered everything there is nothing to show, and
			-- the reply is already with the asker.
			local pending = false
			for _, it in ipairs(items) do
				if not it.answer then
					pending = true
					break
				end
			end
			if not pending then current = nil; d.openRound = nil; return end
			-- the loot mode moved off Council (Roll or SR): nothing to answer any more
			if not C_.CouncilMode() then current = nil; d.openRound = nil; return end

			-- ASK THE ASKER FIRST. While we were gone the officer may have awarded
			-- the item, moved on to another round or reloaded out of it; the saved
			-- round cannot tell. So the frame stays hidden until the asker confirms
			-- the round is still the one on their board, and a round nobody
			-- confirms is dropped instead of popping up on its own.
			local round = saved.round
			if saved.asker == me then
				if C_.RoundIsLive(round) then C_.ShowRestored(round) else C_.DropRestored(round) end
				return
			end
			C.Whisper("CQ", saved.asker, round)
			C.After(6, function() C_.DropRestored(round) end)
		end)
	end)
end

-- ------------------------------------------------------------
-- The ASKER's side of surviving a reload: the round being run, with whatever
-- answers have arrived. Saved on every reply so a crash loses at most the last
-- one; restored on login so the board comes back and the item can still be
-- awarded.
-- ------------------------------------------------------------
-- A round this officer can still act on: open, with an item not yet given.
function C_.HasOpenRound()
	local rec = C_.current
	if not rec or rec.closed or not canSeeBoard() then return false end
	for i in ipairs(rec.items or {}) do
		if not (rec.awarded and rec.awarded[i]) then return true end
	end
	return false
end

-- The mini roll's Council button: opens the board, or closes it when it is open.
function C_.OpenBoard()
	if board and board:IsShown() then
		-- closed by hand: the next answer must not pop it open again
		if C_.current then C_.current.dismissed = true; C_.SaveAsk() end
		board:Hide()
		return
	end
	if C_.current then C_.RepaintBoard(true) end
end

-- The mini roll shows its Council button only while there is a round to open.
local function syncRollButton()
	local RM = Okanvil.RollMgr
	if RM and RM.SyncCouncilButton then pcall(RM.SyncCouncilButton) end
end
C_.SyncRollButton = syncRollButton

function C_.SaveAsk()
	syncRollButton()
	local d = db()
	local rec = C_.current
	if not rec or rec.closed then d.askRound = nil; return end
	-- A TEST round is never saved. It exists to exercise the UI for a minute; a
	-- reload an hour later restoring one put an Ulduar item on the board in the
	-- middle of a 5-man.
	-- RELOAD TEST (off, see the PLAYER_LOGOUT block): delete this line to save
	-- the test round too; it is marked `test` and only restored with the test.
	if C_.testMode then d.askRound = nil; return end
	d.askRound = {
		test = rec.test,
		round = rec.round, boss = rec.boss, items = rec.items,
		replies = rec.replies, awarded = rec.awarded, votes = rec.votes,
		asker = rec.asker, mirror = rec.mirror, dismissed = rec.dismissed,
		payload = rec.payload, savedAt = time(),
		-- Where and with whom it was asked. A round belongs to the run it was
		-- opened in; coming back somewhere else means it is over.
		who  = UnitName and UnitName("player") or "?",
		zone = (GetRealZoneText and GetRealZoneText()) or "",
	}
end

-- Is the raid's loot mode Council? A saved round from before a /reload only
-- comes back while it is: after a switch to Roll or SR it would put a council
-- board (or question) on screen for loot the council no longer decides.
function C_.CouncilMode()
	local SR = Okanvil.SoftRes
	if not (SR and SR.Mode) then return true end
	-- Someone else's mode has not arrived yet right after a reload, so a raider
	-- keeps the round; only the one who sets the mode knows it for sure.
	return SR.Mode() == "council" or (SR.CanSetMode and not SR.CanSetMode()) or false
end

function C_.RestoreAsk()
	local d = db()
	local s = d.askRound
	if not (s and s.round and s.items and #s.items > 0) then return end

	-- A round belongs to the run it was opened in. Three ways it is over:
	--   * too old -- fifteen minutes, not an hour: a council is decided in
	--     minutes, and anything older is last night's window coming back;
	--   * a different CHARACTER -- the db is account-wide, the round was not;
	--   * a different ZONE -- walking into a 5-man does not resume an ICC round,
	--     which is exactly what put an Ulduar item on the board in Halls of
	--     Reflection.
	local me   = UnitName and UnitName("player")
	local zone = (GetRealZoneText and GetRealZoneText()) or ""
	if (time() - (s.savedAt or 0)) > 900
		or (s.who and me and s.who ~= me)
		or (s.zone and s.zone ~= "" and zone ~= "" and s.zone ~= zone) then
		d.askRound = nil
		return
	end

	-- Every item already handed out: the round is over, nothing to bring back.
	local open = false
	for i in ipairs(s.items) do
		if not (s.awarded and s.awarded[i]) then open = true; break end
	end
	if not open then d.askRound = nil; return end
	if s.test and not C_.testMode then d.askRound = nil; return end
	-- the loot mode moved off Council (Roll or SR): the round is over
	if not C_.CouncilMode() then d.askRound = nil; return end

	local rec = {
		test = s.test,
		round = s.round, boss = s.boss or "", items = s.items,
		replies = s.replies or {}, awarded = s.awarded, votes = s.votes,
		asker = s.asker, mirror = s.mirror, dismissed = s.dismissed,
		payload = s.payload, at = GetTime(),
	}
	C_.rounds[s.round] = rec
	C_.current = rec
	for _, l in ipairs(rec.items) do Okanvil:WarmItem(l) end

	-- Re-open the collection on the wire as well, so answers still arriving are
	-- recorded rather than dropped as an unknown round.
	--
	-- NO RE-ASK. The board comes back from what SaveAsk wrote after every reply;
	-- only answers sent during the loading screen itself are missing. Asking the
	-- raid again to fill that gap made every client answer again, and every
	-- answer put the board back on every officer's screen, mid-fight. A raider
	-- who clicks after the reload still arrives normally through Adopt.
	if C.Ask and rec.payload then
		C.Adopt(TOPIC, s.round, {
			timeout = 1800,
			onReply = function(sender, body)
				rec.replies[sender] = mergeReply(rec.replies[sender], parseReply(body))
				C_.RepaintBoard()
				C_.SaveAsk()
			end,
			onDone = function()
				rec.closed = true
				C_.SaveAsk()
				C_.RepaintBoard()
			end,
		})
	end

	-- Restored SILENTLY: a reload never puts the board back on screen by itself
	-- (one officer reloading mid-fight, or after everyone passed, must not pop a
	-- window). The round is kept; the mini roll's Council button or
	-- /okcouncil board opens it.
	rec.dismissed = true
	if canSeeBoard() then boardItem = 1 end
	syncRollButton()
end

-- ------------------------------------------------------------
-- Manual open: /okcouncil status | close
-- The escape hatch the plan asks for -- when something goes wrong at 22:30 the
-- answer has to be one command, not "everyone reload".
-- ------------------------------------------------------------
-- /okcouncil fitcheck: every raid drop against every class, the same test the
-- popup runs, saved to db.fitAudit for a reading outside the game. Items are
-- pulled into the cache first; one still missing after the wait is listed as such.
local AUDIT_CLASSES = { "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN",
	"PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
function C_.FitAudit()
	local ids, seen, from = {}, {}, {}
	for raid, bosses in pairs(OkanvilRaidLoot or {}) do
		for _, b in ipairs(bosses) do
			for _, it in ipairs(b.items or {}) do
				if it.id and not seen[it.id] then
					seen[it.id] = true
					ids[#ids + 1] = it.id
					from[it.id] = raid .. "/" .. (b.boss or "?") .. "/" .. (it.m or "")
					Okanvil:WarmItem(it.id)
				end
			end
		end
	end
	Okanvil:Print(("Fit check: loading %d items into the cache..."):format(#ids))
	local waited = 0
	local function finish()
		local out, missing, skipped = {}, 0, 0
		for _, id in ipairs(ids) do
			local name, link, _, _, _, _, _, _, equip = GetItemInfo(id)
			if not link then
				missing = missing + 1
				out[#out + 1] = id .. "|?|" .. from[id] .. "|uncached"
			elseif not C_.IsCouncilItem(id) then
				skipped = skipped + 1
			else
				local fits = {}
				for _, cls in ipairs(AUDIT_CLASSES) do
					if fitsClass(link, cls) then fits[#fits + 1] = cls end
				end
				-- the stats it was judged on: "STRENGTH=59,DODGE_RATING=40"
				local st = {}
				for k, v in pairs(GetItemStats(link) or {}) do
					st[#st + 1] = (k:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", "")) .. "=" .. tostring(v)
				end
				table.sort(st)
				out[#out + 1] = table.concat({ id, name, equip or "", from[id], table.concat(fits, ","),
					table.concat(st, ",") }, "|")
			end
		end
		Okanvil.db.fitAudit = { at = date("%Y-%m-%d %H:%M"), rows = out }
		Okanvil:Print(("Fit check done: %d items checked, %d not gear, %d never cached. /reload to save it.")
			:format(#out - missing, skipped, missing))
	end
	local function poll()
		local cold = 0
		for _, id in ipairs(ids) do if not GetItemInfo(id) then cold = cold + 1 end end
		waited = waited + 5
		if cold == 0 or waited >= 300 then finish(); return end
		if waited % 30 == 0 then Okanvil:Print(("Fit check: %d items still loading..."):format(cold)) end
		C.After(5, poll)
	end
	C.After(5, poll)
end

_G.SLASH_OKCOUNCIL1 = "/okcouncil"
_G.SlashCmdList["OKCOUNCIL"] = function(msg)
	-- Keep the RAW text: an item link is case-sensitive (|cff1eff00|Hitem:...),
	-- so lowercasing the whole message would break every link pasted after the
	-- verb. Only the verb itself is compared case-insensitively.
	local raw = (msg or ""):match("^%s*(.-)%s*$")
	local verb = raw:match("^(%a+)") or ""
	verb = verb:lower()
	msg = verb
	if not enabled() then
		Okanvil:Print("Loot Council is |cffff5555off|r for this character (Modules list).")
		return
	end
	-- Closes BOTH sides: the popup on this client, and -- if we are the one who
	-- asked -- the round itself. Only hiding the frame left the round collecting
	-- answers into a window nobody could see.
	if msg == "fitcheck" then C_.FitAudit(); return end
	if msg == "close" then
		closeFrame()
		if C_.current and C_.current.round and C.CloseAsk then
			C.CloseAsk(C_.current.round)
			if board then board:Hide() end
			Okanvil:Print("Loot council: round closed.")
		else
			Okanvil:Print("Loot council: closed.")
		end
		return
	end
	-- /okcouncil ask [link] [link]  -- open a round on whatever links follow.
	-- Stage 3b moves this onto buttons in the mini roll; the command stays as the
	-- escape hatch for an item already sitting in someone's bags.
	-- /okcouncil test [n]  |  /okcouncil test off
	if verb == "test" then
		local arg = raw:match("^%a+%s+(%S+)")
		if arg and arg:lower() == "off" then C_.TestOff() else C_.Test(arg) end
		return
	end
	-- /okcouncil auto [on|off] -- the switch the auto-ask line points at.
	-- /okcouncil board -- reopen the board on the open round (it closes by hand,
	-- and losing it used to mean there was no way back to the award button).
	-- /okcouncil answer -- open the question still waiting for your answer
	if verb == "answer" then
		C_.OpenAnswer()
		return
	end
	if verb == "board" then
		if not canSeeBoard() then
			Okanvil:Print("|cffff5555Loot council:|r the board is officers only.")
		elseif C_.current then
			C_.RepaintBoard(true)
		else
			Okanvil:Print("Loot council: no round open.")
		end
		return
	end
	-- /okcouncil purge -- delete leftover test drops without starting a test.
	-- Needed once for items created before they were marked; harmless after.
	if verb == "purge" then
		local L = Okanvil.Loot
		local n = (L and L.PurgeTestDrops and L.PurgeTestDrops()) or 0
		Okanvil:Print(("Loot council: removed |cffffd200%d|r test drop(s)."):format(n))
		if Okanvil.RollMgr and Okanvil.RollMgr.Rebuild then pcall(Okanvil.RollMgr.Rebuild) end
		return
	end
	if verb == "auto" then
		local arg = (raw:match("^%a+%s+(%S+)") or ""):lower()
		local d = db()
		if arg == "on" then d.autoAsk = true
		elseif arg == "off" then d.autoAsk = false
		else d.autoAsk = not d.autoAsk end
		Okanvil:Print("Loot council: auto-ask is "
			.. (d.autoAsk and "|cffffd200ON|r" or "|cffff5555OFF|r") .. ".")
		return
	end
	-- /okcouncil force -- an officer runs the council for this session when the
	-- master looter cannot (no Okanvil, wrong version). Not saved: a /reload ends it.
	if verb == "force" then
		if not canSeeBoard() then
			Okanvil:Print("|cffff5555Loot council:|r officers only.")
			return
		end
		C_.forceRun = not C_.forceRun or nil
		Okanvil:Print("Loot council: force is " .. (C_.forceRun and "|cffffd200ON|r -- you can start council night and ask."
			or "|cffff5555OFF|r -- the master looter runs it again."))
		if not C_.forceRun and C_.active and not C_.MayRun() then C_.SetActive(false) end
		if Okanvil.RollMgr and Okanvil.RollMgr.Rebuild then pcall(Okanvil.RollMgr.Rebuild) end
		if C_._paintRun then pcall(C_._paintRun) end
		return
	end
	-- /okcouncil night [on|off] -- council night, the switch that shows the mini
	-- roll's Council row and lets auto-ask run at all.
	if verb == "night" then
		local arg = (raw:match("^%a+%s+(%S+)") or ""):lower()
		if arg == "on" then C_.SetActive(true)
		elseif arg == "off" then C_.SetActive(false)
		else C_.SetActive(not C_.active) end
		if C_._paintTest then pcall(C_._paintTest) end
		return
	end
	if verb == "ask" then
		local links = {}
		-- Pull real item links out of the argument. Matching the hyperlink (not
		-- whitespace) is what lets an item name containing a space survive.
		for l in raw:gmatch("|c%x+|Hitem:.-|h.-|h|r") do links[#links + 1] = l end
		if #links == 0 then
			Okanvil:Print("Usage: /okcouncil ask [shift-click one or more items]")
			Okanvil:Print("  |cff8a8d93For more than ~3 items use Ask several items in the "
				.. "mini roll -- the chat box truncates longer lines.|r")
			return
		end
		C_.Ask(links, "")
		return
	end
	if msg == "replies" then
		-- Same gate as the board: this prints the same information in text form,
		-- so leaving it open would be a way around the window being closed.
		if not canSeeBoard() then
			Okanvil:Print("|cffff5555Loot council:|r officers only.")
			return
		end
		C_.PrintStatus(nil, true)
		return
	end
	-- status (default)
	if not current then
		Okanvil:Print("Loot council: |cff8a8d93no open round|r.")
		return
	end
	Okanvil:Print(("Loot council: round from |cffffd200%s|r, %d item(s)."):format(
		tostring(current.asker), #current.items))
	for _, it in ipairs(current.items) do
		Okanvil:Print(("   %s -> %s"):format(it.link, it.answer or "|cff8a8d93(no answer)|r"))
	end
end
