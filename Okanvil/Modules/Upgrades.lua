-- ============================================================
-- Okanvil -- Upgrades (native core module).
-- Which raid drops are an upgrade for the spec you are in right now: on your
-- BiS list above what you wear, or a higher item level your class and spec can
-- use. Feeds the Upgrades page and a few lines on a raid boss's tooltip.
-- ============================================================

local Okanvil = Okanvil
local U = {}
Okanvil.Upgrades = U

U.ADDON = "Okanvil-Upgrades"

local function active() return Okanvil:ModuleActive(U.ADDON) end

-- GetInstanceDifficulty() inside a raid: 1 = 10, 2 = 25, 3 = 10 heroic, 4 = 25 heroic
U.MODES = { "10n", "25n", "10h", "25h" }
-- the order they are shown in: each size with its heroic beside it
U.MODE_ORDER = { "10n", "10h", "25n", "25h" }
U.MODE_LABEL = { ["10n"] = "10", ["25n"] = "25", ["10h"] = "10 HC", ["25h"] = "25 HC" }

local function Loot() return OkanvilRaidLoot end

-- ------------------------------------------------------------
-- Spec: the talent tree with the most points, per class by tree index (the
-- tree names are localized, the index is not). A Blood DK tanks in Frost
-- Presence, a Feral druid in Bear Form.
-- ------------------------------------------------------------
local CLASS_BIS = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	DEATHKNIGHT = "Death knight", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
-- tree index -> { label, BiS list name } (nil list = no BiS list, item level only)
local TREES = {
	WARRIOR     = { { "Arms", "Arms" }, { "Fury", "Fury" }, { "Protection", "Protection" } },
	PALADIN     = { { "Holy", "Holy" }, { "Protection", "Protection" }, { "Retribution", "Retribution" } },
	HUNTER      = { { "Beast Mastery", "Beast mastery" }, { "Marksmanship", "Marksmanship" }, { "Survival", "Survival" } },
	ROGUE       = { { "Assassination", "Assassination" }, { "Combat", "Combat" }, { "Subtlety" } },
	PRIEST      = { { "Discipline", "Discipline" }, { "Holy", "Holy" }, { "Shadow", "Shadow" } },
	DEATHKNIGHT = { { "Blood DPS", "Blood dps" }, { "Frost", "Frost" }, { "Unholy", "Unholy" } },
	SHAMAN      = { { "Elemental", "Elemental" }, { "Enhancement", "Enhancement" }, { "Restoration", "Restoration" } },
	MAGE        = { { "Arcane", "Arcane" }, { "Fire", "Fire" }, { "Frost", "Frost" } },
	WARLOCK     = { { "Affliction", "Affliction" }, { "Demonology", "Demonology" }, { "Destruction", "Destruction" } },
	DRUID       = { { "Balance", "Balance" }, { "Feral DPS", "Feral dps" }, { "Restoration", "Restoration" } },
}

local function inBear()
	local bear, dire = GetSpellInfo(5487), GetSpellInfo(9634)
	local form = GetShapeshiftForm and GetShapeshiftForm() or 0
	if form > 0 and GetShapeshiftFormInfo then
		local _, name = GetShapeshiftFormInfo(form)
		return name ~= nil and (name == bear or name == dire)
	end
	return false
end

-- { class = "PALADIN", label = "Retribution", list = "Retribution" } or nil
-- while talents are not loaded. Kept until a talent, form or presence change
-- (the events below): the page asks for it once per item.
local specCache
local function readSpec()
	local _, class = UnitClass("player")
	if not (class and TREES[class] and GetTalentTabInfo) then return nil end
	local group = GetActiveTalentGroup and GetActiveTalentGroup(false) or 1
	local best, bestPts = nil, 0
	for i = 1, (GetNumTalentTabs and GetNumTalentTabs()) or 3 do
		local _, _, pts = GetTalentTabInfo(i, false, false, group)
		if (pts or 0) > bestPts then best, bestPts = i, pts end
	end
	if not best then return nil end
	local t = TREES[class][best]
	local label, list = t[1], t[2]
	if class == "DEATHKNIGHT" and best == 1 then
		local role = Okanvil.RaidFinder_BloodRole and Okanvil.RaidFinder_BloodRole()
		if role == "Tank" then label, list = "Blood Tank", "Blood tank" end
	elseif class == "DRUID" and best == 2 and ((Okanvil.Prof and Okanvil.Prof.Tanking and Okanvil.Prof.Tanking()) or inBear()) then
		label, list = "Feral Tank", "Feral tank"
	end
	return { class = class, label = label, list = list }
end

function U.Spec()
	if specCache == nil then specCache = readSpec() or false end
	return specCache or nil
end

-- ------------------------------------------------------------
-- Repaint, at most once a second: item answers arrive in bursts, and each
-- repaint judges a whole raid.
-- ------------------------------------------------------------
local verdicts = {}   -- link .. raid -> verdict (false = no upgrade), until gear/spec change
local debounce = CreateFrame("Frame")
debounce:Hide()
local wait = 0
debounce:SetScript("OnUpdate", function(self, elapsed)
	wait = wait - elapsed
	if wait > 0 then return end
	self:Hide()
	if U.onChange then U.onChange() end
end)
local function Changed(delay)
	delay = delay or 1
	if debounce:IsShown() and wait <= delay then return end
	wait = delay
	debounce:Show()
end

-- Judging is spread over frames: a page refresh judges at most U.budget new
-- items, shows the rest as loading, and comes back the next frame. Opening the
-- page used to judge a whole raid in one frame and froze the game.
U.budget = nil      -- nil = no limit (the boss tooltip)
U.more = false

-- ------------------------------------------------------------
-- Item cache: GetItemInfo is empty until the client has seen an item. A hidden
-- tooltip asks the server, a few per second so it does not throttle us.
-- ------------------------------------------------------------
local Ask
local askTip = CreateFrame("GameTooltip", "OkanvilUpgradesAskTip", nil, "GameTooltipTemplate")
local queue, queued = {}, {}
local asker = CreateFrame("Frame")
asker:Hide()
local since = 0
asker:SetScript("OnUpdate", function(self, elapsed)
	since = since + elapsed
	if since < 0.25 then return end
	since = 0
	local id = table.remove(queue, 1)
	if not id then
		self:Hide()
		Okanvil:Trace("UPGRADES", "asked " .. (U.asked or 0) .. " items, queue empty")
		wipe(verdicts)
		Changed()
		return
	end
	if not GetItemInfo(id) then
		askTip:SetOwner(UIParent, "ANCHOR_NONE")
		askTip:SetHyperlink("item:" .. id)
		askTip:Hide()
	end
	if #queue % 8 == 0 then Changed() end
end)

Ask = function(id)
	if queued[id] or GetItemInfo(id) then return end
	queued[id] = true
	U.asked = (U.asked or 0) + 1
	queue[#queue + 1] = id
	asker:Show()
end

-- ------------------------------------------------------------
-- BiS lists (Upgrades-Bis-Data.lua): the top 6 per slot for each spec and
-- phase. Lists hold one id per item (mostly the 25 heroic one), so items are
-- matched by name too: the 10, 25 and heroic copies share it.
-- ------------------------------------------------------------

-- the list a raid's loot is judged by; a missing phase falls through to the next one
local PHASE = {
	icc = { "T10", "RS", "T9" }, rs = { "RS", "T10" }, toc = { "T9", "T10" },
	ulduar = { "T8", "T9", "T10" }, naxx = { "T7", "PR", "T9" }, os = { "T7", "PR", "T9" },
	eoe = { "T7", "PR", "T9" }, voa = { "T10", "T9", "T8", "T7" }, ony = { "T9", "T10" },
}

-- The server's content phase: the list that names your BiS today. A phase not
-- out yet never counts, and an older raid's drop can be an upgrade but is never
-- called BiS. The game does not say which phase a server is in, so it is read
-- off what proves a raid is open, and the highest ever seen is kept (phases
-- only move forward):
--   your raid achievements; the raids you are saved to; the raid gear you wear;
--   the raid achievements of anyone Okanvil inspected; standing inside the raid;
--   three players advertising it in LFM chat (Raid Finder).
-- /okup phase T7 .. RS sets it by hand (and wins); /okup phase auto goes back.
local PHASE_ORDER = { PR = 0, T7 = 1, T8 = 2, T9 = 3, T10 = 4, RS = 5 }
local PHASE_NAMES = { [0] = "PR", "T7", "T8", "T9", "T10", "RS" }
-- the phase each raid came out in
local RAID_PHASE = { naxx = "T7", os = "T7", eoe = "T7", ulduar = "T8", toc = "T9", ony = "T9",
	icc = "T10", voa = "T7", rs = "RS" }
local INSTANCE_PHASE = { ["Naxxramas"] = "T7", ["Ulduar"] = "T8", ["Trial of the Crusader"] = "T9",
	["Icecrown Citadel"] = "T10", ["The Ruby Sanctum"] = "RS" }

local function udb()
	Okanvil.db.upgrades = Okanvil.db.upgrades or {}
	return Okanvil.db.upgrades
end

local function raidOfAch(id)
	for _, e in ipairs(Okanvil.RaidFinder_Achievements or {}) do
		if e.id == id then return e.raid:match("^(%a+)") end
	end
end

-- the highest phase anything in this session proves is open
local function proven()
	local best = 1
	local function see(p) if p and PHASE_ORDER[p] and PHASE_ORDER[p] > best then best = PHASE_ORDER[p] end end
	for _, e in ipairs(Okanvil.RaidFinder_Achievements or {}) do
		local ok, _, _, _, done = pcall(GetAchievementInfo, e.id)
		if ok and done then see(RAID_PHASE[e.raid:match("^(%a+)")]) end
	end
	for i = 1, (GetNumSavedInstances and GetNumSavedInstances() or 0) do
		see(INSTANCE_PHASE[(GetSavedInstanceInfo(i))])
	end
	-- standing inside a raid proves it is open, before anyone has killed a boss
	local zone, itype = GetInstanceInfo()
	if itype == "raid" then see(INSTANCE_PHASE[zone]) end
	local raidOf = {}
	for raid, bosses in pairs(OkanvilRaidLoot or {}) do
		for _, b in ipairs(bosses) do
			for _, it in ipairs(b.items or {}) do raidOf[it.id] = raid end
		end
	end
	for slot = 1, 18 do
		local l = GetInventoryItemLink("player", slot)
		local id = l and tonumber(l:match("item:(%d+)"))
		if id and raidOf[id] then see(RAID_PHASE[raidOf[id]]) end
	end
	local specs = Okanvil_DB and Okanvil_DB.inspect and Okanvil_DB.inspect.specs
	for _, e in pairs(specs or {}) do
		for id, has in pairs(type(e) == "table" and e.ach or {}) do
			if has then see(RAID_PHASE[raidOfAch(id) or ""]) end
		end
	end
	return PHASE_NAMES[best]
end

-- Re-read the evidence; the phase only ever moves forward.
function U.LearnPhase()
	local d = udb()
	local p = proven()
	if not d.phaseSeen or PHASE_ORDER[p] > (PHASE_ORDER[d.phaseSeen] or 0) then
		d.phaseSeen = p
		Okanvil:Trace("UPGRADES", "server phase " .. p)
	end
end

-- Three different players advertising a raid in LFM chat prove it is open,
-- before anyone in your guild has set foot in it.
local LFM_PROOF = 3
local lfmSeen = {}      -- [instance] = { [sender] = true }, this session
function U.SeenLFM(sender, instance)
	local p = INSTANCE_PHASE[instance]
	if not p or PHASE_ORDER[p] <= PHASE_ORDER[U.Phase()] then return end
	lfmSeen[instance] = lfmSeen[instance] or {}
	lfmSeen[instance][sender] = true
	local n = 0
	for _ in pairs(lfmSeen[instance]) do n = n + 1 end
	if n < LFM_PROOF then return end
	local d = udb()
	if not d.phaseSeen or PHASE_ORDER[p] > (PHASE_ORDER[d.phaseSeen] or 0) then
		d.phaseSeen = p
		Okanvil:Trace("UPGRADES", "server phase " .. p .. " (" .. n .. " players advertise " .. instance .. ")")
		wipe(verdicts)
		Changed()
	end
end

function U.Phase()
	local d = Okanvil.db and Okanvil.db.upgrades or {}
	if d.phase and PHASE_ORDER[d.phase] then return d.phase end
	return (d.phaseSeen and PHASE_ORDER[d.phaseSeen]) and d.phaseSeen or "T7"
end
local function out(p) return (PHASE_ORDER[p] or 0) > PHASE_ORDER[U.Phase()] end
-- Is this raid out yet on the server?
function U.RaidOut(raid) return not out(RAID_PHASE[raid] or "T7") end

-- inventory slots each list row stands for
local ROW_SLOTS = {
	Head = { 1 }, Neck = { 2 }, Shoulder = { 3 }, Back = { 15 }, Chest = { 5 }, Wrist = { 9 },
	Hands = { 10 }, Waist = { 6 }, Legs = { 7 }, Feet = { 8 }, Finger = { 11, 12 },
	Trinket = { 13, 14 }, Weapon = { 16 }, ["Off hand"] = { 17 }, Ranged = { 18 }, Relic = { 18 },
}

-- id -> name for every raid drop, so a list id names its 10/25/heroic copies
-- without a server query, and id -> how high its version is
local VERSION = { ["10n"] = 1, ["25n"] = 2, ["10h"] = 2, ["25h"] = 3 }
local lootName, lootVersion
local function NameOf(id)
	if not lootName then
		lootName, lootVersion = {}, {}
		for _, bosses in pairs(Loot() or {}) do
			for _, boss in ipairs(bosses) do
				for _, it in ipairs(boss.items) do
					lootName[it.id] = it.name
					lootVersion[it.id] = VERSION[(it.m or ""):match("^[^,]+")] or 0
				end
			end
		end
	end
	return lootName[id] or GetItemInfo(id)
end

-- A list sometimes orders two versions of one item backwards. A higher version
-- is never worse, so within a name the places go best place to highest version.
local function FixVersions(r)
	local groups = {}
	for id, n in pairs(r.rank) do
		local name = NameOf(id)
		if name then
			groups[name] = groups[name] or {}
			table.insert(groups[name], { id = id, n = n, v = lootVersion[id] or 0 })
		end
	end
	for _, g in pairs(groups) do
		if #g > 1 then
			local places = {}
			for i, e in ipairs(g) do places[i] = e.n end
			table.sort(places)
			table.sort(g, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.n < b.n end)
			for i, e in ipairs(g) do r.rank[e.id] = places[i] end
		end
	end
end

-- ToC drops differ by faction (a Horde Juggernaut's Vitality is the Alliance
-- Satrina's Impeding Scarab) and the lists name the Alliance id. The map's keys
-- are Alliance ids, its values Horde ones, so a Horde id is looked up in reverse.
local hordeToAli

-- The loot table names the Horde copy of each faction item of the Crusader's
-- coliseum. An Alliance character gets the Alliance copy instead (id and name),
-- once, at login: every page reading the table -- this one, soft reserves, the
-- wishlist, the loot recorder -- then sees the items that really drop for it.
function U.FactionLoot()
	if UnitFactionGroup("player") ~= "Alliance" then return end
	local toAli = {}
	for ali, horde in pairs(OkanvilBisHordeToAli or {}) do toAli[horde] = ali end
	for _, bosses in pairs(OkanvilRaidLoot or {}) do
		for _, b in ipairs(bosses) do
			for _, it in ipairs(b.items or {}) do
				local ali = toAli[it.id]
				if ali then
					it.id = ali
					it.name = (OkanvilIDs_Seed and OkanvilIDs_Seed[ali]) or it.name
				end
			end
		end
	end
end

local function AliId(id)
	if not hordeToAli then
		hordeToAli = {}
		for ali, horde in pairs(OkanvilBisHordeToAli or {}) do hordeToAli[horde] = ali end
	end
	return hordeToAli[id] or id
end

-- rows of the list for this spec + raid:
--   { { name = "Finger", top = id, rank = { [id] = n }, byName = { [name] = best n } }, ... }
local rowCache = {}
local RowsOf
local function Rows(spec, raid)
	local cls = OkanvilBis and OkanvilBis[CLASS_BIS[spec.class]]
	local bySpec = cls and spec.list and cls[spec.list]
	if not bySpec then return end
	local phase
	for _, p in ipairs(PHASE[raid] or { "T10" }) do
		if not out(p) and bySpec[p] and #bySpec[p] > 0 then phase = p; break end
	end
	if not phase then return end
	return RowsOf(spec, phase), phase
end

-- Is the piece you wear on this spec's list for a LATER phase (T10, RS)?
-- Then it is end-game gear the current list is too early to name, and it stays.
local LATER = { "RS", "T10", "T9", "T8" }
local function OnLaterList(spec, phase, rowName, wid, wname)
	for _, p in ipairs(LATER) do
		-- a list later than the raid's, but out already
		if p ~= phase and not out(p) and PHASE_ORDER[p] > (PHASE_ORDER[phase] or 0) then
			for _, r in ipairs(RowsOf(spec, p) or {}) do
				if r.name == rowName and (r.rank[wid] or (wname and r.byName[wname])) then return true end
			end
		end
	end
	return false
end

-- rows where item level says little: a trinket, ring or neck is worth its effect
local JEWEL_ROWS = { Trinket = true, Finger = true, Neck = true }

RowsOf = function(spec, phase)
	local cls = OkanvilBis and OkanvilBis[CLASS_BIS[spec.class]]
	local bySpec = cls and spec.list and cls[spec.list]
	if not (bySpec and bySpec[phase] and #bySpec[phase] > 0) then return nil end
	local key = spec.class .. spec.list .. phase
	if rowCache[key] then return rowCache[key] end
	local rows = {}
	for _, row in ipairs(bySpec[phase]) do
		local r = { name = row.slot, rank = {}, byName = {}, top = row[1] }
		for n = 1, 6 do
			local id = row[n]
			if id and id > 0 then
				r.rank[id] = r.rank[id] or n
				local name = NameOf(id)
				if name and not r.byName[name] then r.byName[name] = n end
			end
		end
		FixVersions(r)
		rows[#rows + 1] = r
	end
	rowCache[key] = rows
	return rows
end

-- exact = this version's place on the list; byName = the best place of any version
local function RankIn(row, id, name)
	local ali = AliId(id)
	local aliName = ali ~= id and NameOf(ali)
	local exact = row.rank[ali] or row.rank[id]
	local byName = (name and row.byName[name]) or (aliName and row.byName[aliName]) or exact
	return exact or byName, exact, byName
end

local function Ilvl(link) return select(4, GetItemInfo(link)) or 0 end

-- Does the drop beat the piece you wear, both on this list row? At the same
-- item level the list's order decides; across item levels the exact version's
-- place does, a version the list doesn't name sitting half a place under it.
local function Beats(row, link, id, wornLink, wid)
	local _, dExact, dName = RankIn(row, id, GetItemInfo(link))
	local _, wExact, wName = RankIn(row, wid, GetItemInfo(wornLink))
	local dl, wl = Ilvl(link), Ilvl(wornLink)
	if dl == wl then return dName < wName end
	local d, w = dExact or (dName + 0.5), wExact or (wName + 0.5)
	if d ~= w then return d < w end
	return dl > wl
end

-- Set pieces: the tooltip's "Sanctified Lightsworn Battlegear (4/5)" line names
-- the set and how many you wear. Cached until your gear changes.
local scan = CreateFrame("GameTooltip", "OkanvilUpgradesSetScan", nil, "GameTooltipTemplate")
local wornSet, itemSet = {}, {}

local function ReadSet()
	for i = 2, scan:NumLines() do
		local fs = _G["OkanvilUpgradesSetScanTextLeft" .. i]
		if fs then
			local name, n = (fs:GetText() or ""):match("^(.-) %((%d+)/%d+%)$")
			if name then return name, tonumber(n) end
		end
	end
	return false
end

local function WornSet(slot)
	if wornSet[slot] == nil then
		scan:SetOwner(UIParent, "ANCHOR_NONE")
		scan:SetInventoryItem("player", slot)
		local name, n = ReadSet()
		wornSet[slot] = name and { name = name, n = n } or false
		scan:Hide()
	end
	return wornSet[slot]
end

-- the set an item belongs to, false for none, nil while it isn't cached.
-- An uncached item is asked for once (Ask) and never scanned until it is.
local function SetOf(id)
	if not id then return nil end
	if itemSet[id] == nil then
		if not GetItemInfo(id) then Ask(id); return nil end
		scan:SetOwner(UIParent, "ANCHOR_NONE")
		scan:SetHyperlink("item:" .. id)
		itemSet[id] = ReadSet() or false
		scan:Hide()
	end
	return itemSet[id]
end

local TIER_ROWS = { Head = true, Shoulder = true, Chest = true, Hands = true, Legs = true }

-- Would this item, in place of the set piece you wear in `slot`, cost a set
-- bonus your spec plays with? The list says how many set pieces the spec
-- wants. Without the answer (items not cached): dropping out of exactly 2 or 4
-- loses a bonus.
local function BreaksSet(id, slot, row, rows)
	local worn = WornSet(slot)
	if not worn or SetOf(id) == worn.name then return false end
	local here = SetOf(row.top)
	if here == worn.name then return true end
	local wanted, unknown = 0, here == nil
	for _, r in ipairs(rows) do
		if TIER_ROWS[r.name] then
			local s = SetOf(r.top)
			if s == nil then unknown = true elseif s == worn.name then wanted = wanted + 1 end
		end
	end
	if unknown then return worn.n == 2 or worn.n == 4 end
	return worn.n - 1 < wanted
end

-- equip slot -> inventory slots, for the item level check
local INV_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- Not on your list: an upgrade when your class can use it, its stats suit your
-- spec, and it beats the item level of what you wear there (rings and
-- trinkets: the weaker one). Returns the item level gained, or nil.
local function IlvlGain(link)
	local P = Okanvil.Prof
	if P and P.CanIUse and not P.CanIUse(link) then return nil end
	if P and P.StatsFitMe and not P.StatsFitMe(link) then return nil end
	local equip = select(9, GetItemInfo(link)) or ""
	local slots = INV_SLOTS[equip]
	if not slots then return nil end
	-- holding a two-hander: a one-hander replaces it, an off hand item has no slot
	local mh = GetInventoryItemLink("player", 16)
	if mh and select(9, GetItemInfo(mh)) == "INVTYPE_2HWEAPON" then
		if equip == "INVTYPE_WEAPON" then slots = { 16 }
		elseif slots[1] == 17 then return nil end
	end
	local ilvl, weakest = Ilvl(link), nil
	for _, s in ipairs(slots) do
		local worn = GetInventoryItemLink("player", s)
		local lvl = worn and Ilvl(worn) or 0
		if not weakest or lvl < weakest then weakest = lvl end
	end
	if weakest and ilvl > weakest then return ilvl - weakest, weakest == 0 end
	return nil
end

-- How a drop ranks for you, as { rank = n } (on your list, above your piece),
-- { ilvl = n } (item levels gained), { empty = true } (nothing in that slot),
-- or nil when it is no upgrade. Owned items are no upgrade.
-- v.ilvl, and v.worn: the piece it replaces (the lower item level of two
-- rings or trinkets, the one you would swap out). No stat %: weights go wrong
-- past a hit or haste cap.
local function measure(link, v)
	v.ilvl = Ilvl(link)
	local equip = select(9, GetItemInfo(link)) or ""
	local slots = INV_SLOTS[equip]
	if not slots then return v end
	-- holding a two-hander: a one-hander replaces it, not the empty off hand
	local mh = GetInventoryItemLink("player", 16)
	if mh and select(9, GetItemInfo(mh)) == "INVTYPE_2HWEAPON" and equip ~= "INVTYPE_2HWEAPON" and slots[1] == 16 then
		slots = { 16 }
	end
	local low
	for _, s in ipairs(slots) do
		local l = GetInventoryItemLink("player", s)
		local lvl = l and Ilvl(l) or 0
		if not low or lvl < low then low, v.worn = lvl, l end
	end
	return v
end

-- Rank a drop against one list (one phase). Returns best place, whether it
-- beats what you wear, whether it is that list's very BiS version.
local function against(rows, phase, spec, link, id, current)
	local name = GetItemInfo(link)
	local best, show, bis
	for _, row in ipairs(rows) do
		local r, exact = RankIn(row, id, name)
		if r then
			best = (best and math.min(best, r)) or r
			-- BiS is the very version the list names (the heroic one, mostly);
			-- the normal copy of a BiS item is an upgrade, not the BiS
			if exact == 1 then bis = true end
			-- an upgrade if it beats the piece in ANY of the row's slots
			for _, s in ipairs(ROW_SLOTS[row.name] or {}) do
				local l = GetInventoryItemLink("player", s)
				if not l then
					show = true
				elseif not BreaksSet(id, s, row, rows) then
					local wid = tonumber(l:match("item:(%d+)"))
					local wname = GetItemInfo(l)
					local wr = wid and RankIn(row, wid, wname)
					if not current then
						-- an older phase's list: only a higher item level is an upgrade
						if Ilvl(link) > Ilvl(l) and (not wr or Beats(row, link, id, l, wid)) then show = true end
					elseif wr then
						if Beats(row, link, id, l, wid) then show = true end
					elseif not OnLaterList(spec, phase, row.name, wid, wname) then
						-- off every list: a trinket, ring or neck on TODAY's list beats it
						-- (its effect, not its item level, is what it is worth); an older
						-- phase's drop, and every other slot, needs the higher item level
						if (current and JEWEL_ROWS[row.name]) or Ilvl(link) > Ilvl(l) then show = true end
					end
				end
			end
		end
	end
	return best, show, bis
end

local function judge(link, raid, spec)
	local id = tonumber(link:match("item:(%d+)"))
	if not id or GetItemCount(id, true) > 0 then return nil end
	-- your class's own armour and weapons only: the BiS lists name leather on a death knight
	local P = Okanvil.Prof
	if P and P.CanIUse and not P.CanIUse(link) then return nil end
	-- the spec's own weapon hands and stats: the lists name a one-hander for a Blood DK.
	-- With a list only listed items show, so only the hard rules apply to them.
	local rows, phase = Rows(spec, raid)
	if P and P.StatsFitMe and not P.StatsFitMe(link, rows ~= nil) then return nil end
	if rows then
		-- The current list first (T10, else RS): a ToC trinket or Anub'arak's
		-- cloak that is still BiS in ICC counts while you raid ICC. Then the
		-- raid's own phase list, for gear that only that phase names.
		local now = U.Phase()
		local tries = {}
		local cur = RowsOf(spec, now)
		if cur then tries[#tries + 1] = { cur, now, true } end
		if phase ~= now then tries[#tries + 1] = { rows, phase, false } end
		for _, t in ipairs(tries) do
			local best, show, bis = against(t[1], t[2], spec, link, id, t[3])
			-- BiS only off today's list; an older phase's #1 is an upgrade at most
			if best and show then return { rank = best, bis = t[3] and bis or nil, list = t[2] } end
		end
		-- with a list for your spec, only the lists count: a higher item level
		-- off them is how a tank mace and a healer trinket turned up for a Blood DPS
		return nil
	end
	-- no list for this spec: item level is all there is
	local gain, empty = IlvlGain(link)
	if gain then return empty and { empty = true } or { ilvl = gain } end
	return nil
end

-- nil when the budget for this pass is spent (the caller shows it as loading)
function U.Judge(link, raid)
	local spec = U.Spec()
	if not (spec and link) then return nil end
	local key = link .. raid .. spec.label
	local v = verdicts[key]
	if v == nil then
		if U.budget then
			if U.budget <= 0 then U.more = true; return nil, true end
			U.budget = U.budget - 1
		end
		local t0 = debugprofilestop and debugprofilestop()
		v = judge(link, raid, spec) or false
		if v then measure(link, v) end
		verdicts[key] = v
		if t0 then
			local ms = debugprofilestop() - t0
			U.judged, U.judgeMs = (U.judged or 0) + 1, (U.judgeMs or 0) + ms
			if ms > 10 then
				Okanvil:Trace("UPGRADES", ("slow judge %s %.1fms"):format(link:match("item:(%d+)") or "?", ms))
			end
		end
	end
	return v or nil
end

-- Start / end a page pass; a pass that ran out of budget comes back next frame.
function U.BeginPass(n) U.budget, U.more = n, false end
function U.EndPass()
	U.budget = nil
	if U.more then Changed(0.02) end
	return U.more
end

-- The short label of a verdict: "BiS", "Upgrade", "+13 ilvl", "empty slot".
function U.Label(v)
	if not v then return "" end
	-- only the list's first is BiS; anything else on it is an upgrade
	if v.rank then return v.bis and "BiS" or "Upgrade" end
	if v.empty then return "empty slot" end
	return "+" .. v.ilvl .. " ilvl"
end

local function DropsIn(item, mode) return (item.m or ""):find(mode, 1, true) ~= nil end

-- One boss's upgrades in this difficulty, best first; and how many items are
-- still loading.
function U.Of(boss, raid, mode)
	local out, pending = {}, 0
	for _, it in ipairs(boss.items) do
		if DropsIn(it, mode) then
			local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(it.id)
			if not name then
				Ask(it.id)
				pending = pending + 1
			else
				local v, later = U.Judge(link, raid)
				if later then
					pending = pending + 1
				elseif v then
					out[#out + 1] = { link = link, name = name, quality = quality, icon = icon,
						slot = it.slot, v = v }
				end
			end
		end
	end
	table.sort(out, function(a, b)
		local ra, rb = a.v.rank or 99, b.v.rank or 99
		if ra ~= rb then return ra < rb end
		return (a.v.ilvl or 999) > (b.v.ilvl or 999)
	end)
	return out, pending
end

-- ------------------------------------------------------------
-- Where you are: raid key + mode, or nil outside a raid.
-- ------------------------------------------------------------
local hereAt, hereKey, hereMode, hereR = -10
function U.Here()
	local now = GetTime()
	if now - hereAt < 2 then return hereKey, hereMode, hereR end
	hereAt = now
	hereKey, hereMode, hereR = nil, nil, nil
	local SR = Okanvil.SoftRes
	local r = SR and SR.RaidHere and SR.RaidHere()
	if not r then return nil end
	hereKey, hereMode, hereR = r.key, U.MODES[GetInstanceDifficulty and GetInstanceDifficulty() or 1] or "10n", r
	return hereKey, hereMode, hereR
end

-- The difficulties a raid's loot table has, in MODES order.
local modesCache = {}
function U.ModesOf(raid)
	if modesCache[raid] then return modesCache[raid] end
	local has = {}
	for _, boss in ipairs((Loot() or {})[raid] or {}) do
		for _, it in ipairs(boss.items) do
			for m in (it.m or ""):gmatch("[^,]+") do has[m] = true end
		end
	end
	local out = {}
	for _, m in ipairs(U.MODE_ORDER) do if has[m] then out[#out + 1] = m end end
	if #out == 0 then out = { "10n", "25n" } end
	modesCache[raid] = out
	return out
end

-- ------------------------------------------------------------
-- Bosses by NPC name. The loot table's names are short ("Lanathel",
-- "Putricide"); a unit's name contains them once squashed to letters.
-- Encounters fought as several NPCs, or whose NPC carries another boss's
-- name (the gunship's High Overlord Saurfang), are named here.
-- ------------------------------------------------------------
local ALIAS = {
	["High Overlord Saurfang"] = "Gunship Battle", ["Muradin Bronzebeard"] = "Gunship Battle",
	["Prince Valanar"] = "Council", ["Prince Keleseth"] = "Council", ["Prince Taldaram"] = "Council",
	["Fjola Lightbane"] = "Twin Valkyrs", ["Eydis Darkbane"] = "Twin Valkyrs",
	["Gormok the Impaler"] = "Northrend Beasts", ["Acidmaw"] = "Northrend Beasts",
	["Dreadscale"] = "Northrend Beasts", ["Icehowl"] = "Northrend Beasts",
	["Steelbreaker"] = "Iron Council", ["Runemaster Molgeim"] = "Iron Council",
	["Stormcaller Brundir"] = "Iron Council",
	["Thane Korth'azz"] = "Four Horsemen", ["Lady Blaumeux"] = "Four Horsemen",
	["Sir Zeliek"] = "Four Horsemen", ["Baron Rivendare"] = "Four Horsemen",
	["Onyxia"] = "xia_", ["Flame Leviathan"] = "Leviathan",
	-- Mimiron's machines die between phases: hovering them shows his loot, but
	-- only his own death marks the kill (see KILL_SKIP)
	["Leviathan Mk II"] = "Mimiron", ["VX-001"] = "Mimiron", ["Aerial Command Unit"] = "Mimiron",
}
-- NPCs that die before their encounter is over
local KILL_SKIP = {
	["Leviathan Mk II"] = true, ["VX-001"] = true, ["Aerial Command Unit"] = true,
	["Gormok the Impaler"] = true, ["Acidmaw"] = true, ["Dreadscale"] = true,
}
-- loot-table boss names that read badly on a page
local SHOWN = { xia_ = "Onyxia", Council = "Blood Prince Council", Lanathel = "Blood-Queen Lana'thel" }
function U.BossLabel(name) return SHOWN[name] or name end
local function Squash(s) return (s or ""):lower():gsub("[^%a]", "") end

function U.BossFor(raid, npc)
	local bosses = raid and (Loot() or {})[raid]
	if not (bosses and npc) then return nil end
	local want = ALIAS[npc]
	local sq = Squash(npc)
	for _, b in ipairs(bosses) do
		if want then
			if b.boss == want then return b end
		else
			local bs = Squash(b.boss)
			if #bs >= 4 and sq:find(bs, 1, true) then return b end
		end
	end
	return nil
end

-- ------------------------------------------------------------
-- Kills this lockout. 3.3.5a has no per-boss lockout call, so a boss is
-- marked when one of its NPCs dies in front of you. Per character, per raid ID.
-- ------------------------------------------------------------
local KEEP_DAYS = 8
local function killDB()
	local c = Okanvil.cdb
	if not c then return {} end
	c.upgradesKilled = c.upgradesKilled or {}
	return c.upgradesKilled
end

local function lockKey(r)
	local SR = Okanvil.SoftRes
	return SR and SR.LockKey and r and SR.LockKey(r) or nil
end

function U.Killed(raid, bossName)
	local key, _, r = U.Here()
	if key ~= raid then return false end
	local l = killDB()[lockKey(r) or ""]
	return l and l[bossName] and true or false
end

local function markKill(npc)
	if KILL_SKIP[npc] then return end
	local raid, _, r = U.Here()
	local b = raid and U.BossFor(raid, npc)
	local k = b and lockKey(r)
	if not k then return end
	local d = killDB()
	d[k] = d[k] or {}
	if d[k][b.boss] then return end
	d[k][b.boss] = true
	d[k]._at = time()
	Okanvil:Trace("UPGRADES", "killed " .. b.boss)
	Changed()
end

local function pruneKills()
	local d, cutoff = killDB(), time() - KEEP_DAYS * 86400
	for k, l in pairs(d) do
		if type(l) ~= "table" or (l._at or 0) < cutoff then d[k] = nil end
	end
end

-- ------------------------------------------------------------
-- Boss tooltip: up to 3 upgrades for your spec, in a raid, while the boss is
-- still alive on your lockout.
-- ------------------------------------------------------------
local TIP_MAX = 3

local function onUnitTip(tip)
	if not active() then return end
	local raid, mode = U.Here()
	if not raid then return end
	local _, unit = tip:GetUnit()
	if not unit or UnitIsPlayer(unit) then return end
	local b = U.BossFor(raid, UnitName(unit))
	if not b or U.Killed(raid, b.boss) then return end
	local ups = U.Of(b, raid, mode)
	if #ups == 0 then return end
	local spec = U.Spec()
	tip:AddLine(" ")
	tip:AddLine("Upgrades · " .. (spec and spec.label or "?"), 0.88, 0.72, 0.38)
	for i = 1, math.min(TIP_MAX, #ups) do
		local u = ups[i]
		local r, g, bl = GetItemQualityColor(u.quality or 4)
		tip:AddDoubleLine(u.name, U.Label(u.v), r, g, bl, 0.49, 0.99, 0.54)
	end
	if #ups > TIP_MAX then
		tip:AddLine("+" .. (#ups - TIP_MAX) .. " more · /okup", 0.54, 0.55, 0.58)
	end
	tip:Show()
end

-- ------------------------------------------------------------
-- Events
-- ------------------------------------------------------------
local lastLabel
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
ev:RegisterEvent("PLAYER_TALENT_UPDATE")
ev:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
ev:RegisterEvent("UNIT_AURA")                    -- a DK presence, on cores that send no form event
ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
ev:RegisterEvent("UPDATE_INSTANCE_INFO")         -- raid lockouts: one more proof of the phase
ev:RegisterEvent("PLAYER_ENTERING_WORLD")        -- zoning into a raid: another
ev:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		U.FactionLoot()
		pruneKills()
		-- the evidence for the phase: once cached a few seconds in, then on new lockouts
		if Okanvil.Comms and Okanvil.Comms.After then
			Okanvil.Comms.After(10, function()
				local was = U.Phase()
				U.LearnPhase()
				if U.Phase() ~= was then wipe(verdicts); Changed() end
			end)
		end
		if RequestRaidInfo then RequestRaidInfo() end
		GameTooltip:HookScript("OnTooltipSetUnit", function(tip)
			local ok, err = pcall(onUnitTip, tip)
			if not ok and Okanvil.Err then Okanvil:Err("Upgrades tooltip", err) end
		end)
		return
	end
	if event == "UPDATE_INSTANCE_INFO" or event == "PLAYER_ENTERING_WORLD" then
		local was = U.Phase()
		U.LearnPhase()
		if U.Phase() ~= was then wipe(verdicts); Changed() end
		return
	end
	if not active() then return end
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		local _, sub, _, _, _, _, destName = ...
		if sub == "UNIT_DIED" and destName then markKill(destName) end
		return
	end
	if event == "UNIT_AURA" and (...) ~= "player" then return end
	if event ~= "PLAYER_EQUIPMENT_CHANGED" then
		-- talent events also fire for every inspect, and a druid shifts all fight
		-- long: only a change of spec (tree, bear, presence) is worth a re-judge
		specCache = nil
		local spec = U.Spec()
		local label = spec and spec.label
		if label == lastLabel then return end
		lastLabel = label
	else
		wipe(wornSet)
	end
	wipe(verdicts)
	Changed()
end)

-- /okup            open the page
-- /okup <itemlink> what the judge says about one item
SLASH_OKUPGRADES1 = "/okup"
-- /okup audit: every drop of every raid that is out, for the spec you are in,
-- with the verdict and why, saved for review (Okanvil.db.upgrades.audit) --
-- one pass over everything instead of spotting wrong rows one by one.
function U.Audit()
	local spec = U.Spec()
	if not spec then Okanvil:Print("Upgrades audit: talents not loaded yet."); return end
	wipe(verdicts)
	local lines, shown, total, pending = {}, 0, 0, 0
	for raid, bosses in pairs(Loot() or {}) do
		if U.RaidOut(raid) then
			for _, b in ipairs(bosses) do
				for _, it in ipairs(b.items or {}) do
					total = total + 1
					local name, link = GetItemInfo(it.id)
					if not name then
						Ask(it.id); pending = pending + 1
					else
						local v = judge(link, raid, spec)
						if v then measure(link, v) end
						local worn = v and v.worn and Ilvl(v.worn) or 0
						local wname = v and v.worn and GetItemInfo(v.worn) or ""
						lines[#lines + 1] = table.concat({ raid, it.m or "", b.boss, tostring(it.id), name, it.slot or "",
							tostring(Ilvl(link)), v and U.Label(v) or "-", v and tostring(v.rank or "") or "",
							v and (v.list or "") or "", wname, tostring(worn) }, " | ")
						if v then shown = shown + 1 end
					end
				end
			end
		end
	end
	table.sort(lines)

	-- Every spec of every class, not just yours: is each drop meant for it?
	--   fit:  the stat rules (ClassLoot left out) against ClassLoot's own lists
	--   list: drops on a spec's BiS list for this phase that the filter refuses
	local P = Okanvil.Prof
	local fitLines, listLines = {}, {}
	local KEY_LIST = {
		WarriorArms = "Arms", WarriorFury = "Fury", WarriorTank = "Protection",
		PaladinHoly = "Holy", PaladinTank = "Protection", PaladinRetribution = "Retribution",
		HunterBeastMastery = "Beast mastery", HunterMarksman = "Marksmanship", HunterSurvival = "Survival",
		RogueAssassination = "Assassination", RogueCombat = "Combat",
		PriestDiscipline = "Discipline", PriestHoly = "Holy", PriestShadow = "Shadow",
		DeathKnightBloodDps = "Blood dps", DeathKnightBloodTank = "Blood tank", DeathKnightFrostDps = "Frost",
		DeathKnightUnholyDps = "Unholy",
		ShamanElemental = "Elemental", ShamanEnhancement = "Enhancement", ShamanRestoration = "Restoration",
		MageArcane = "Arcane", MageFire = "Fire", MageFrost = "Frost",
		WarlockAffliction = "Affliction", WarlockDemonology = "Demonology", WarlockDestruction = "Destruction",
		DruidBalance = "Balance", DruidFeralDps = "Feral dps", DruidFeralTank = "Feral tank",
		DruidRestoration = "Restoration",
	}
	if P and P.FitsSpec and P.SpecKeys then
		for raid, bosses in pairs(Loot() or {}) do
			if U.RaidOut(raid) then
				for _, b in ipairs(bosses) do
					for _, it in ipairs(b.items or {}) do
						local name, link = GetItemInfo(it.id)
						if name then
							for _, sk in ipairs(P.SpecKeys()) do
								if not P.CanUse or P.CanUse(link, sk.class) then
									-- ClassLoot's 5 stars = meant for the spec, none = not; 4 is "can wear"
									local ours = P.FitsSpec(link, sk.key, true)
									local stars = P.ClassLootStars and P.ClassLootStars(it.id, sk.key)
									if stars and ((ours and stars == 0) or (not ours and stars == 5)) then
										local keys = {}
										for k in pairs(GetItemStats(link) or {}) do
											keys[#keys + 1] = (k:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""))
										end
										table.sort(keys)
										fitLines[#fitLines + 1] = table.concat({ sk.key, raid, tostring(it.id), name,
											it.slot or "", ours and "ours=yes" or "ours=no", "stars=" .. stars,
											table.concat(keys, ",") }, " | ")
									end
								end
							end
						end
					end
				end
			end
		end
		-- each spec's list for this phase: anything the filter would refuse
		local now = U.Phase()
		for _, sk in ipairs(P.SpecKeys()) do
			local cls = OkanvilBis and OkanvilBis[CLASS_BIS[sk.class]]
			local rowsOf = cls and KEY_LIST[sk.key] and cls[KEY_LIST[sk.key]] and cls[KEY_LIST[sk.key]][now]
			for _, row in ipairs(rowsOf or {}) do
				for n = 1, 6 do
					local id = row[n]
					local name, link = id and GetItemInfo(id)
					if name and not P.FitsSpec(link, sk.key) then
						listLines[#listLines + 1] = table.concat({ sk.key, row.slot, "#" .. n, tostring(id), name }, " | ")
					elseif id and id > 0 and not name then
						Ask(id)
					end
				end
			end
		end
		table.sort(fitLines); table.sort(listLines)
	end

	udb().audit = { spec = spec.label, class = spec.class, phase = U.Phase(), at = time(), lines = lines,
		fit = fitLines, list = listLines }
	Okanvil:Print(("Upgrades audit: %d items, %d upgrades for you; all specs: %d stat-rule vs ClassLoot differences, %d BiS-list items refused%s. /reload to save it.")
		:format(total, shown, #fitLines, #listLines,
			pending > 0 and (", " .. pending .. " not cached -- run it again in a minute") or ""))
end

SlashCmdList.OKUPGRADES = function(arg)
	if arg and arg:lower():match("^%s*audit") then U.Audit(); return end
	local ph = arg and arg:match("^%s*[Pp]hase%s*(%S*)")
	if ph then
		ph = ph:upper()
		if PHASE_ORDER[ph] or ph == "AUTO" then
			udb().phase = PHASE_ORDER[ph] and ph or nil
			if ph == "AUTO" then U.LearnPhase() end
			wipe(verdicts)
			Okanvil:Print("Upgrades: server phase " .. U.Phase() .. (ph == "AUTO" and " (read from the game)." or " (set by hand)."))
			if U.onChange then U.onChange() end
		else
			Okanvil:Print("Upgrades phase: " .. U.Phase() .. (udb().phase and " (set by hand)" or " (read from the game)")
				.. "  -- /okup phase T7 | T8 | T9 | T10 | RS | auto")
		end
		return
	end
	local link = arg and arg:match("|Hitem:[^|]+|h%[[^%]]+%]|h") and arg
	if link then
		local raid = U.Here() or "icc"
		local spec = U.Spec()
		local v = U.Judge(link, raid)
		Okanvil:Print(link .. " for " .. (spec and spec.label or "?") .. ": "
			.. (v and ("|cff7cfc8a" .. U.Label(v) .. "|r") or "|cff8a8d93no upgrade|r"))
		return
	end
	if not active() then Okanvil:Print("Upgrades is off (Modules).") return end
	if not Okanvil.win or not Okanvil.win:IsShown() then Okanvil:Toggle() end
	Okanvil:ShowPanel(U.ADDON)
end
