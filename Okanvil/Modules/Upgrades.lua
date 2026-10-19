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
U.CLASS_BIS = CLASS_BIS
-- each BiS list's own colour, by its school or role (the class keeps its class colour)
local SPEC_COLOR = {
	["Death knight"] = { ["Blood dps"] = "E0303A", ["Blood tank"] = "B01E28", Frost = "5CB8FF", Unholy = "5FD35F" },
	Druid = { Balance = "7A8CFF", ["Feral dps"] = "FF9A2E", ["Feral tank"] = "E0303A", Restoration = "5FD35F" },
	Hunter = { ["Beast mastery"] = "5FD35F", Marksmanship = "E8665A", Survival = "FF7EB6" },
	Mage = { Arcane = "B36BFF", Fire = "FF7A1F", ["Fire FFB"] = "FFA54A", Frost = "5CB8FF" },
	Paladin = { Holy = "FFD966", Protection = "C9CED6", Retribution = "F58CBA" },
	Priest = { Discipline = "F2F2F2", Holy = "FFD966", Shadow = "8A55D6" },
	Rogue = { Assassination = "7CCB3A", Combat = "FFF569" },
	Shaman = { Elemental = "4A9BFF", Enhancement = "FFB347", Restoration = "3FD0B0" },
	Warlock = { Affliction = "5FD35F", Demonology = "9482C9", Destruction = "FF6A1F" },
	Warrior = { Arms = "C79C6E", Fury = "E0303A", Protection = "C9CED6" },
}
-- "Rogue", "Combat" -> "|cffFFF569Combat|r" (uncoloured if unknown)
function U.SpecText(cls, list, text)
	local hex = SPEC_COLOR[cls] and SPEC_COLOR[cls][list]
	text = text or list
	return hex and ("|cff" .. hex .. text .. "|r") or text
end
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
local specCache, offCache
local function readSpec(group)
	local _, class = UnitClass("player")
	if not (class and TREES[class] and GetTalentTabInfo) then return nil end
	local active = GetActiveTalentGroup and GetActiveTalentGroup(false) or 1
	group = group or active
	local best, bestPts = nil, 0
	for i = 1, (GetNumTalentTabs and GetNumTalentTabs()) or 3 do
		local _, _, pts = GetTalentTabInfo(i, false, false, group)
		if (pts or 0) > bestPts then best, bestPts = i, pts end
	end
	if not best then return nil end
	local t = TREES[class][best]
	local label, list = t[1], t[2]
	-- a Blood DK by its talents; a feral druid by its bear talents, or bear form
	-- in the spec you are in
	if class == "DEATHKNIGHT" and best == 1 then
		local role = Okanvil.RaidFinder_BloodRole and Okanvil.RaidFinder_BloodRole(group)
		if role == "Tank" then label, list = "Blood Tank", "Blood tank" end
	elseif class == "DRUID" and best == 2
		and ((Okanvil.Prof and Okanvil.Prof.Tanking and Okanvil.Prof.Tanking(group))
			or (group == active and inBear())) then
		label, list = "Feral Tank", "Feral tank"
	end
	return { class = class, label = label, list = list }
end

function U.Spec()
	if specCache == nil then specCache = readSpec() or false end
	return specCache or nil
end

-- Your other talent spec (dual spec), or nil: no second spec, or the same list.
function U.OffSpec()
	if offCache == nil then
		offCache = false
		if (GetNumTalentGroups and GetNumTalentGroups(false) or 1) >= 2 then
			local active = GetActiveTalentGroup and GetActiveTalentGroup(false) or 1
			local off, main = readSpec(active == 1 and 2 or 1), U.Spec()
			if off and not (main and main.list == off.list) then offCache = off end
		end
	end
	return offCache or nil
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

-- Upgrades reads LFM chat itself: Raid Finder only scans while its page is
-- open. Parsing every line lags a busy raid, so a line is parsed only when it
-- names a raid newer than the phase already known, and not at all inside a raid.
local LFM_WORDS = {
	T8  = { "uld" },
	T9  = { "toc", "togc", "trial", "ony" },
	T10 = { "icc", "icecrown" },
	RS  = { "%f[%a]rs%f[%A]", "ruby", "halion" },
}
local function namesNewerRaid(msg)
	local now = PHASE_ORDER[U.Phase()]
	msg = msg:lower()
	for p, words in pairs(LFM_WORDS) do
		if PHASE_ORDER[p] > now then
			for _, w in ipairs(words) do
				if msg:find(w) then return true end
			end
		end
	end
end
local lfmEv = CreateFrame("Frame")
lfmEv:RegisterEvent("CHAT_MSG_CHANNEL")
lfmEv:RegisterEvent("CHAT_MSG_YELL")
lfmEv:SetScript("OnEvent", function(self, _, msg, sender)
	if PHASE_ORDER[U.Phase()] >= PHASE_ORDER.RS then self:UnregisterAllEvents(); return end
	if not (msg and sender and Okanvil.RF and Okanvil.RF.parse) then return end
	local _, itype = IsInInstance()
	if itype == "raid" or not namesNewerRaid(msg) then return end
	local ok, info = pcall(Okanvil.RF.parse, msg)
	if ok and info and info.instance then U.SeenLFM(sender, info.instance) end
end)

-- The guild shares the phase: a new player with no raid history of their own
-- learns it from anyone who has. Announced at login; a lower announce gets one
-- answer from the guild, from whoever's random delay runs out first.
local function seenOrder() return PHASE_ORDER[udb().phaseSeen or ""] or 0 end
local function announcePhase()
	if Okanvil.Comms and udb().phaseSeen then Okanvil.Comms.SendGuild("UPPH", udb().phaseSeen) end
end
local answerDue
if Okanvil.Comms and Okanvil.Comms.On then
	Okanvil.Comms.On("UPPH", function(sender, p)
		if not (p and PHASE_ORDER[p]) or sender == UnitName("player") then return end
		if PHASE_ORDER[p] > seenOrder() then
			local was = U.Phase()
			udb().phaseSeen = p
			Okanvil:Trace("UPGRADES", "server phase " .. p .. " (from " .. tostring(sender) .. ")")
			if U.Phase() ~= was then wipe(verdicts); Changed() end
		elseif PHASE_ORDER[p] < seenOrder() and not answerDue then
			answerDue = true
			Okanvil.Comms.After(2 + math.random() * 6, function()
				if answerDue then announcePhase() end
				answerDue = nil
			end)
		else
			answerDue = nil   -- someone already answered
		end
	end)
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
local lootName, lootVersion, lootMode
local function NameOf(id)
	if not lootName then
		lootName, lootVersion, lootMode = {}, {}, {}
		for _, bosses in pairs(Loot() or {}) do
			for _, boss in ipairs(bosses) do
				for _, it in ipairs(boss.items) do
					lootName[it.id] = it.name
					lootVersion[it.id] = VERSION[(it.m or ""):match("^[^,]+")] or 0
					lootMode[it.id] = (it.m or ""):match("^[^,]+")
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
local function HordeToAli()
	if not hordeToAli then
		hordeToAli = {}
		for ali, horde in pairs(OkanvilBisHordeToAli or {}) do hordeToAli[horde] = ali end
	end
	return hordeToAli
end

-- The loot table names the Horde copy of each faction item of the Crusader's
-- coliseum. An Alliance character gets the Alliance copy instead (id and name),
-- once, at login: every page reading the table -- this one, soft reserves, the
-- wishlist, the loot recorder -- then sees the items that really drop for it.
function U.FactionLoot()
	if UnitFactionGroup("player") ~= "Alliance" then return end
	local toAli = HordeToAli()
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

local function AliId(id) return HordeToAli()[id] or id end

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
		-- place -> the id the list names there, to say which version a place is
		r.idAt = {}
		for id, n in pairs(r.rank) do r.idAt[n] = r.idAt[n] or id end
		rows[#rows + 1] = r
	end
	rowCache[key] = rows
	return rows
end

-- Which raid size / difficulty an item id drops in ("25 HC"), or "another version".
function U.ModeLabel(id)
	NameOf(id)
	local m = lootMode[id] or lootMode[(OkanvilBisHordeToAli or {})[id] or id]
	return U.MODE_LABEL[m] or "another version"
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
	-- two copies of the same item (normal and heroic, 10 and 25): the higher
	-- item level is the better one, whichever copy the list happens to name
	local dn, wn = GetItemInfo(link), GetItemInfo(wornLink)
	if dn and dn == wn then return dl > wl end
	if dl == wl then return dName < wName end
	-- the list's place is another (higher) copy's: this lower copy does not
	-- beat a piece of higher item level, whatever that copy's place
	if not dExact and dl < wl then return false end
	-- and the same for what you wear: a lower copy of a listed piece does not
	-- keep that copy's place against a drop of higher item level
	if not wExact and wl < dl then return true end
	local d, w = dExact or (dName + 0.5), wExact or (wName + 0.5)
	if d ~= w then return d < w end
	return dl > wl
end

-- Set pieces: the tooltip's "Sanctified Lightsworn Battlegear (4/5)" line names
-- the set. How many you wear is counted here, from the item ids in your slots:
-- on a transmog server the client counts the looks and says 3/5 for a real 4.
-- Cached until your gear changes.
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

local function wornId(slot)
	local l = GetInventoryItemLink("player", slot)
	return l and tonumber(l:match("item:(%d+)"))
end
-- how many pieces of this set you wear, by item id
local function setCount(name)
	local n = 0
	for slot = 1, 19 do
		local id = wornId(slot)
		if id and SetOf(id) == name then n = n + 1 end
	end
	return n
end
U.SetCount = setCount

local function WornSet(slot)
	if wornSet[slot] == nil then
		local id = wornId(slot)
		local name = id and SetOf(id)
		if name == nil and id then return false end      -- not cached yet: ask again later
		wornSet[slot] = name and { name = name, n = setCount(name) } or false
	end
	return wornSet[slot]
end

-- The item tooltip's set block, told the truth: "(4/5)", the pieces you wear
-- lit, and the bonuses you have green -- counted from the item ids you wear.
local SET_ON, SET_OFF = { 1, 1, 0.6 }, { 0.5, 0.5, 0.5 }
local function fixSetTip(tip)
	local name = tip:GetName()
	if not name then return end
	local setName, setLine, total
	for i = 2, tip:NumLines() do
		local fs = _G[name .. "TextLeft" .. i]
		local t = fs and fs:GetText()
		local sn, _, tot = (t or ""):match("^(.-) %((%d+)/(%d+)%)$")
		if sn then setName, setLine, total = sn, i, tot; break end
	end
	if not setName then return end
	local have = setCount(setName)
	if have == 0 then return end                      -- not yours: the client's count stands
	local wornNames = {}
	for slot = 1, 19 do
		local l = GetInventoryItemLink("player", slot)
		local n = l and GetItemInfo(l)
		if n then wornNames[n] = true end
	end
	_G[name .. "TextLeft" .. setLine]:SetText(setName .. " (" .. have .. "/" .. total .. ")")
	-- the piece names, an empty line, then the bonuses: the block ends at the
	-- first line after the gap that is not a bonus
	local pieces = true
	for i = setLine + 1, tip:NumLines() do
		local fs = _G[name .. "TextLeft" .. i]
		local t = fs and fs:GetText()
		if not t or t == "" or t == " " then
			if not pieces then break end
			pieces = false
		else
			local need, bonus = t:match("^%((%d+)%) Set: (.*)$")
			if need then
				pieces = false
				if tonumber(need) <= have then fs:SetText("Set: " .. bonus); fs:SetTextColor(0.1, 1, 0.1) end
			elseif t:match("^Set: ") then
				pieces = false                        -- already green
			elseif pieces then
				local piece = t:gsub("^%s+", "")
				local c = wornNames[piece] and SET_ON or SET_OFF
				fs:SetTextColor(c[1], c[2], c[3])
			else
				break                                 -- past the bonuses
			end
		end
	end
end
for _, t in ipairs({ GameTooltip, ItemRefTooltip }) do
	t:HookScript("OnTooltipSetItem", function(tip)
		local ok, err = pcall(fixSetTip, tip)
		if not ok and Okanvil.Err then Okanvil:Err("Set tooltip", err) end
	end)
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
	local best, show, bis, as
	for _, row in ipairs(rows) do
		local r, exact = RankIn(row, id, name)
		if r then
			-- a place the list gives another version of this item (the heroic one,
			-- mostly) is that version's: remember which, for the label
			if not best or r < best then
				as = not exact and row.idAt and row.idAt[r] or nil
			end
			best = (best and math.min(best, r)) or r
			-- BiS is the very version the list names (the heroic one, mostly);
			-- the normal copy of a BiS item is an upgrade, not the BiS
			-- (two rings and two trinkets are worn: the list's top two are both BiS)
			local bisPlaces = #(ROW_SLOTS[row.name] or {}) > 1 and 2 or 1
			if exact and exact <= bisPlaces then bis = true end
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
	return best, show, bis, as
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
			local best, show, bis, as = against(t[1], t[2], spec, link, id, t[3])
			-- BiS only off today's list; an older phase's #1 is an upgrade at most
			if best and show then
				return { rank = best, bis = t[3] and bis or nil, list = t[2], as = as and U.ModeLabel(as) or nil }
			end
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
function U.Judge(link, raid, spec)
	spec = spec or U.Spec()
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
function U.Of(boss, raid, mode, spec)
	local out, pending = {}, 0
	for _, it in ipairs(boss.items) do
		if DropsIn(it, mode) then
			local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(it.id)
			if not name then
				Ask(it.id)
				pending = pending + 1
			else
				local v, later = U.Judge(link, raid, spec)
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
	-- your spec, then your other spec (OS); always a line under each: an empty
	-- tooltip reads as the feature missing
	local function section(spec, tag, max)
		local ups, pending = U.Of(b, raid, mode, spec)
		tip:AddLine(" ")
		tip:AddLine(tag .. " · " .. (spec and spec.label or "?"), 0.88, 0.72, 0.38)
		if #ups == 0 then
			tip:AddLine(pending > 0 and "loading items, hover again" or "none from this boss", 0.54, 0.55, 0.58)
			return
		end
		for i = 1, math.min(max, #ups) do
			local u = ups[i]
			local r, g, bl = GetItemQualityColor(u.quality or 4)
			tip:AddDoubleLine(u.name, U.Label(u.v), r, g, bl, 0.49, 0.99, 0.54)
		end
		if #ups > max then
			tip:AddLine("+" .. (#ups - max) .. " more · /okup", 0.54, 0.55, 0.58)
		end
	end
	section(U.Spec(), "Upgrades", TIP_MAX)
	local off = U.OffSpec()
	if off then section(off, "Off-spec", 4) end
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
				announcePhase()
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
		specCache, offCache = nil, nil
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

-- ------------------------------------------------------------
-- Drop alert: an upgrade for you drops (a corpse you loot, a roll, the master
-- looter linking it in raid warning) -> a toast, the rat sound and one line in
-- your own chat. Nothing anyone else sees. /okup sound turns it off.
-- ------------------------------------------------------------
local RAT_SOUND = [[Interface\AddOns\Okanvil\Media\rat.wav]]
local alerted, lastSound = {}, 0

-- The toast: icon, name, verdict, boss. Ten seconds, held while hovered; drag
-- to move, right click to close.
local toast
local function makeToast()
	local W = Okanvil.W
	local t = CreateFrame("Button", "Okanvil_UpgradeToast", UIParent)
	t:SetSize(320, 52)
	local pos = udb().toastPos or { "CENTER", "CENTER", 0, 120 }
	t:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	t:SetMovable(true); t:SetClampedToScreen(true)
	t:RegisterForDrag("LeftButton"); t:RegisterForClicks("RightButtonUp")
	t:SetScript("OnDragStart", function(self) self:StartMoving() end)
	t:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		udb().toastPos = { p, rp, x, y }
	end)
	t:SetFrameStrata("HIGH")
	Okanvil:Skin(t, "panel")
	local ac = Okanvil.Colors and Okanvil.Colors.accent or { 0.75, 0.58, 0.23 }
	t:SetBackdropBorderColor(ac[1], ac[2], ac[3])
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetSize(40, 40); t.icon:SetPoint("LEFT", 6, 0)
	t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	t.top = W.Text(t, "UPGRADE DROPPED", "note", "accent")
	t.top:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 8, -1)
	t.name = W.Text(t, "", 13)
	t.name:SetPoint("LEFT", t.icon, "RIGHT", 8, -2); t.name:SetPoint("RIGHT", -8, -2)
	t.name:SetJustifyH("LEFT")
	t.meta = W.Text(t, "", "note", "dim")
	t.meta:SetPoint("BOTTOMLEFT", t.icon, "BOTTOMRIGHT", 8, 1)
	t:SetScript("OnEnter", function(self)
		self.hold = true
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetHyperlink(self.link)
		GameTooltip:AddLine("Drag to move, right click to close.", 0.54, 0.55, 0.58)
		GameTooltip:Show()
	end)
	t:SetScript("OnLeave", function(self) self.hold = nil; GameTooltip:Hide() end)
	t:SetScript("OnClick", function(self) self:Hide() end)
	t:SetScript("OnUpdate", function(self, elapsed)
		if self.hold then return end
		self.left = self.left - elapsed
		if self.left <= 0 then self:Hide()
		elseif self.left < 1 then self:SetAlpha(self.left) end
	end)
	t:Hide()
	return t
end

local function bossOf(raid, id)
	for _, b in ipairs((Loot() or {})[raid] or {}) do
		for _, it in ipairs(b.items or {}) do if it.id == id then return b.boss end end
	end
end

local function showToast(link, v, os, raid, id)
	local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(link)
	toast = toast or makeToast()
	toast.link = link
	toast.icon:SetTexture(icon)
	local r, g, b = GetItemQualityColor(quality or 4)
	toast.name:SetText(name); toast.name:SetTextColor(r, g, b)
	local bits = { "|cff7dfc8a" .. U.Label(v) .. "|r" }
	if os then bits[#bits + 1] = "OS " .. os.label end
	local boss = bossOf(raid, id)
	if boss then bits[#bits + 1] = boss end
	toast.meta:SetText(table.concat(bits, "  "))
	toast.left = 10
	toast:SetAlpha(1)
	toast:Show()
end

local function alertDrop(link, retry)
	if not link or udb().sound == false or not active() then return end
	local raid = U.Here()
	if not raid then return end
	local id = tonumber(link:match("item:(%d+)"))
	if not id or (alerted[id] and GetTime() - alerted[id] < 600) then return end
	if not GetItemInfo(link) then
		-- not cached yet: ask, and look once more
		if retry then return end
		Ask(id)
		if Okanvil.Comms and Okanvil.Comms.After then Okanvil.Comms.After(1.5, function() alertDrop(link, true) end) end
		return
	end
	local v, os = U.Judge(link, raid), nil
	if not v then
		local off = U.OffSpec()
		v = off and U.Judge(link, raid, off)
		os = v and off
	end
	if not v then return end
	alerted[id] = GetTime()
	Okanvil:Print("|cff7dfc8aUpgrade|r " .. link .. " -- " .. U.Label(v) .. (os and (" |cff8a8d93(OS " .. os.label .. ")|r") or ""))
	showToast(link, v, os, raid, id)
	if GetTime() - lastSound > 2 then
		lastSound = GetTime()
		PlaySoundFile(RAT_SOUND)
	end
end

local function alertText(msg)
	for link in (msg or ""):gmatch("|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r") do alertDrop(link) end
end

local aev = CreateFrame("Frame")
aev:RegisterEvent("START_LOOT_ROLL")
aev:RegisterEvent("LOOT_OPENED")
aev:RegisterEvent("CHAT_MSG_RAID_WARNING")
aev:RegisterEvent("CHAT_MSG_RAID_LEADER")
aev:SetScript("OnEvent", function(_, event, a1)
	local ok, err = pcall(function()
		if event == "START_LOOT_ROLL" then alertDrop(GetLootRollItemLink(a1))
		elseif event == "LOOT_OPENED" then
			for i = 1, GetNumLootItems() do alertDrop(GetLootSlotLink(i)) end
		else alertText(a1) end
	end)
	if not ok and Okanvil.Err then Okanvil:Err("Upgrades drop alert", err) end
end)

-- ------------------------------------------------------------
-- BiS lines on every item tooltip: each spec whose list names this item, with
-- its icon, and every phase that names it ("T9 BIS / T10 alt 2"). Phases not
-- out on the server are left out; sorted by place, yours first among equals.
-- /okup bis turns it off.
-- ------------------------------------------------------------
local BIS_CLASS_TOKEN = {}
for token, name in pairs(CLASS_BIS) do BIS_CLASS_TOKEN[name] = token end
local bisIndex      -- [id] = { ["Rogue|Combat"] = { class, list, places = { [phase] = rank } } }

local function buildBisIndex()
	bisIndex = {}
	for clsName, specs in pairs(OkanvilBis or {}) do
		for list, phases in pairs(specs) do
			for phase, rows in pairs(phases) do
				for _, row in ipairs(rows) do
					-- two rings and two trinkets are worn: the list's top two are both BIS
					local pair = row.slot == "Finger" or row.slot == "Trinket"
					for n, id in ipairs(row) do
						local rank = (pair and n == 2) and 1 or n
						local byItem = bisIndex[id] or {}
						bisIndex[id] = byItem
						local k = clsName .. "|" .. list
						local e = byItem[k] or { class = clsName, list = list, places = {} }
						byItem[k] = e
						if not e.places[phase] or rank < e.places[phase] then e.places[phase] = rank end
					end
				end
			end
		end
	end
end

local function onItemTip(tip)
	if udb().bisTip == false or not active() then return end
	local _, link = tip:GetItem()
	local id = link and tonumber(link:match("item:(%d+)"))
	if not id then return end
	if not bisIndex then buildBisIndex() end
	local byItem = bisIndex[AliId(id)]
	if not byItem then return end
	local now = PHASE_ORDER[U.Phase()] or 4
	local mine = U.Spec()
	local rows = {}
	for _, e in pairs(byItem) do
		local parts, latest = {}, nil
		for _, phase in ipairs(OkanvilBisPhases or {}) do
			local rank = e.places[phase]
			if rank and (PHASE_ORDER[phase] or 0) <= now then
				parts[#parts + 1] = phase .. (rank == 1 and " BIS" or (" alt " .. rank))
				latest = rank
			end
		end
		if #parts > 0 then
			local own = mine and CLASS_BIS[mine.class] == e.class and mine.list == e.list
			-- sorted by its place on the newest list that names it: BIS, alt 2, alt 3...
			rows[#rows + 1] = { e = e, text = table.concat(parts, " / "), own = own, rank = latest }
		end
	end
	if #rows == 0 then return end
	table.sort(rows, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.own ~= b.own then return a.own end
		if a.e.class ~= b.e.class then return a.e.class < b.e.class end
		return a.e.list < b.e.list
	end)
	tip:AddLine(" ")
	for _, r in ipairs(rows) do
		local icons = OkanvilBisIcons and OkanvilBisIcons[r.e.class]
		local icon = icons and (icons[r.e.list] or icons.classIcon)
		local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[BIS_CLASS_TOKEN[r.e.class] or ""] or { r = 1, g = 1, b = 0 }
		-- the whole line in the class colour: with the rank colours on the right,
		-- a second colour per spec is one too many
		local left = (icon and ("|T" .. icon .. ":18|t ") or "")
			.. ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) .. r.e.class .. " - " .. r.e.list .. "|r"
		-- the places in one quiet grey; only a BIS stands out, in gold
		if r.rank == 1 then
			tip:AddDoubleLine(left, r.text, 1, 1, 1, 1, 0.82, 0.25)
		else
			tip:AddDoubleLine(left, r.text, 1, 1, 1, 0.72, 0.73, 0.75)
		end
	end
	tip:Show()
end

-- ------------------------------------------------------------
-- "Fits": who the item is for, in stars, on every raid item. 5 stars: on that
-- spec's BiS list (either copy, normal or heroic). 4 stars: the class wears it
-- and its stats and weapon suit the spec (the same rules the Upgrades page uses).
-- ------------------------------------------------------------
local FIT_TO_BIS = {
	WarriorArms = { "Warrior", "Arms" }, WarriorFury = { "Warrior", "Fury" }, WarriorTank = { "Warrior", "Protection" },
	PaladinHoly = { "Paladin", "Holy" }, PaladinTank = { "Paladin", "Protection" },
	PaladinRetribution = { "Paladin", "Retribution" },
	HunterBeastMastery = { "Hunter", "Beast mastery" }, HunterMarksman = { "Hunter", "Marksmanship" },
	HunterSurvival = { "Hunter", "Survival" },
	RogueAssassination = { "Rogue", "Assassination" }, RogueCombat = { "Rogue", "Combat" },
	PriestDiscipline = { "Priest", "Discipline" }, PriestHoly = { "Priest", "Holy" }, PriestShadow = { "Priest", "Shadow" },
	DeathKnightBloodDps = { "Death knight", "Blood dps" }, DeathKnightBloodTank = { "Death knight", "Blood tank" },
	DeathKnightFrostDps = { "Death knight", "Frost" }, DeathKnightUnholyDps = { "Death knight", "Unholy" },
	ShamanElemental = { "Shaman", "Elemental" }, ShamanEnhancement = { "Shaman", "Enhancement" },
	ShamanRestoration = { "Shaman", "Restoration" },
	MageArcane = { "Mage", "Arcane" }, MageFire = { "Mage", "Fire" }, MageFrost = { "Mage", "Frost" },
	WarlockAffliction = { "Warlock", "Affliction" }, WarlockDemonology = { "Warlock", "Demonology" },
	WarlockDestruction = { "Warlock", "Destruction" },
	DruidBalance = { "Druid", "Balance" }, DruidFeralDps = { "Druid", "Feral dps" },
	DruidFeralTank = { "Druid", "Feral tank" }, DruidRestoration = { "Druid", "Restoration" },
}
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12|t"
local BLANK = "|T:12:12|t"       -- an empty spacer one star wide
local bisByName     -- [item name] = { ["Rogue|Combat"] = true }

local function onList(id, name, cls, list)
	if not bisIndex then buildBisIndex() end
	local k = cls .. "|" .. list
	local byItem = bisIndex[AliId(id)]
	if byItem and byItem[k] then return true end
	if not bisByName then
		bisByName = {}
		local seed = OkanvilIDs_Seed or {}
		for lid, specs in pairs(bisIndex) do
			local n = seed[lid] or GetItemInfo(lid)
			if n then
				bisByName[n] = bisByName[n] or {}
				for sk in pairs(specs) do bisByName[n][sk] = true end
			end
		end
	end
	return name and bisByName[name] and bisByName[name][k] or false
end

local FIT_WRAP = 34       -- characters per class line before it wraps
-- right-hand lines this tooltip moved left; put back when it is cleared, or the
-- next tooltip's right column (sell price, "Bank 0") would sit in the middle
local movedRight = {}
local function restoreRight(tip)
	local moved = movedRight[tip]
	if not moved then return end
	local name = tip:GetName()
	for i in pairs(moved) do
		local l, r = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
		if l and r then
			r:ClearAllPoints()
			r:SetPoint("RIGHT", l, "LEFT", 40, 0)
			r:SetWidth(0)            -- back to sizing to its text
		end
		moved[i] = nil
	end
end
for _, t in ipairs({ GameTooltip, ItemRefTooltip }) do t:HookScript("OnTooltipCleared", restoreRight) end

-- Where an item drops, from the loot table: [id] = { { raid, boss, m }, ... }
local dropIndex
local function dropsOf(id)
	if not dropIndex then
		dropIndex = {}
		for raid, bosses in pairs(Loot() or {}) do
			for _, bo in ipairs(bosses) do
				for _, it in ipairs(bo.items or {}) do
					dropIndex[it.id] = dropIndex[it.id] or {}
					table.insert(dropIndex[it.id], { raid = raid, boss = bo.boss, m = it.m or "" })
				end
			end
		end
	end
	return dropIndex[id]
end
local RAID_TITLE = {}
for _, r in ipairs(OkanvilRaids or {}) do RAID_TITLE[r.key] = r.name end
-- "25h" -> "25 Player (Heroic)", as the game's own instance names read
local function modeText(m)
	local size, hc = m:match("^(%d+)(%a)$")
	if not size then return m end
	return size .. " Player" .. (hc == "h" and " (Heroic)" or "")
end

-- "Classes: Rogue" on the tooltip (tier pieces, class-only items): only those
-- classes, as tokens; nil when the item has no such line. Cached per item.
local classOnly = {}
local CLASSES_PREFIX = (ITEM_CLASSES_ALLOWED or "Classes: %s"):gsub("%%s", "")
local function allowedClasses(link, id)
	if classOnly[id] ~= nil then return classOnly[id] or nil end
	local byName = {}
	for _, list in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
		for token, nm in pairs(list) do byName[nm] = token end
	end
	scan:SetOwner(UIParent, "ANCHOR_NONE")
	scan:SetHyperlink(link)
	local found = false
	for i = 2, scan:NumLines() do
		local fs = _G["OkanvilUpgradesSetScanTextLeft" .. i]
		local t = fs and fs:GetText()
		if t and t:sub(1, #CLASSES_PREFIX) == CLASSES_PREFIX then
			found = {}
			for nm in t:sub(#CLASSES_PREFIX + 1):gmatch("[^,]+") do
				local token = byName[(nm:gsub("^%s+", ""):gsub("%s+$", ""))]
				if token then found[token] = true end
			end
			break
		end
	end
	scan:Hide()
	classOnly[id] = found
	return found or nil
end

-- Does the item suit ANY spec of this class -- on its BiS list, or its stats and
-- weapon fit (the tooltip's stars)? Talents change between raids, so the
-- council asks a raider about what their class could play, not only today's
-- two specs.
function U.FitsAnySpec(link, class)
	local P = Okanvil.Prof
	if not (P and P.FitsSpec and OkanvilFitSpecs and link) then return true end
	local id = tonumber(link:match("item:(%d+)"))
	local name = GetItemInfo(link)
	for _, sp in ipairs(OkanvilFitSpecs) do
		if sp.class == class then
			local b = FIT_TO_BIS[sp.key]
			if (b and id and onList(id, name, b[1], b[2])) or P.FitsSpec(link, sp.key, true) then
				return true
			end
		end
	end
	return false
end

local function starRows(link, name, id, rows)
	local P = Okanvil.Prof
	if not (P and P.FitsSpec and P.CanUse and OkanvilFitSpecs) then return end
	local only = id and allowedClasses(link, id)
	local tiers = { [5] = {}, [4] = {} }
	local order = { [5] = {}, [4] = {} }
	local perClass = {}
	for _, sp in ipairs(OkanvilFitSpecs) do
		perClass[sp.class] = (perClass[sp.class] or 0) + 1
		if P.CanUse(link, sp.class) then
			local b = FIT_TO_BIS[sp.key]
			local stars
			if b and onList(id, name, b[1], b[2]) then stars = 5
			elseif P.FitsSpec(link, sp.key, true) then stars = 4 end
			if stars then
				local t = tiers[stars]
				if not t[sp.class] then t[sp.class] = {}; table.insert(order[stars], sp.class) end
				table.insert(t[sp.class], sp.label)
			end
		end
	end
	for _, stars in ipairs({ 5, 4 }) do
		local line, len, first = "", 0, true
		-- a wrapped line keeps the stars' width on the left, as empty spacers,
		-- so the tooltip measures it at its real width
		local function flush()
			if line ~= "" then rows[#rows + 1] = { first and STAR:rep(stars) or BLANK:rep(stars), line } end
			line, len, first = "", 0, false
		end
		local list = order[stars]
		for i, class in ipairs(list) do
			local specs = tiers[stars][class]
			local cls = CLASS_BIS[class] or class
			local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] or { r = 1, g = 1, b = 1 }
			local hex = ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
			-- every spec of the class: the class alone
			local txt = #specs >= perClass[class] and cls or (cls .. " (" .. table.concat(specs, ", ") .. ")")
			-- wrapped at every comma, the ones inside the brackets too: one long
			-- class cannot run off the edge
			local pieces = {}
			for part in (txt .. ","):gmatch("([^,]*),") do pieces[#pieces + 1] = (part:gsub("^%s+", "")) end
			for k, part in ipairs(pieces) do
				-- a comma after every piece but the very last one
				local bit = part .. ((k < #pieces or i < #list) and "," or "")
				if len > 0 and len + #bit + 1 > FIT_WRAP then flush() end
				line = line .. (len > 0 and " " or "") .. hex .. bit .. "|r"
				len = len + #bit + 1
			end
		end
		flush()
	end
end

-- "Boss" and "Instance" rows: every boss that drops it, and the raid with the
-- difficulties this copy drops in
local LABEL = "|cfff2e68c"
local function dropRows(id, rows)
	local drops = dropsOf(id)
	if not drops then return end
	local bosses, places, seenB, seenP = {}, {}, {}, {}
	for _, d in ipairs(drops) do
		local bn = U.BossLabel(d.boss)
		if not seenB[bn] then seenB[bn] = true; bosses[#bosses + 1] = bn end
		for m in d.m:gmatch("[^,]+") do
			local place = (RAID_TITLE[d.raid] or d.raid) .. ": " .. modeText(m)
			if not seenP[place] then seenP[place] = true; places[#places + 1] = place end
		end
	end
	-- a token drops from half the raid: the first few, then how many more
	if #bosses > 4 then
		local more = #bosses - 3
		for i = #bosses, 4, -1 do bosses[i] = nil end
		bosses[4] = "and " .. more .. " more"
	end
	for i, bn in ipairs(bosses) do rows[#rows + 1] = { i == 1 and (LABEL .. "Boss|r") or " ", LABEL .. bn .. "|r" } end
	for i, pl in ipairs(places) do rows[#rows + 1] = { i == 1 and (LABEL .. "Instance|r") or " ", LABEL .. pl .. "|r" } end
end

local function onFitTip(tip)
	if not active() then return end
	local _, link = tip:GetItem()
	if not link then return end
	local name, _, quality, _, _, _, _, _, equip = GetItemInfo(link)
	if not name then return end
	local id = tonumber(link:match("item:(%d+)"))
	local rows = {}
	-- stars: gear only (tokens, patterns and quest items have no slot)
	local gear = equip and equip ~= "" and (quality or 0) >= 3
		and equip ~= "INVTYPE_BAG" and equip ~= "INVTYPE_TABARD" and equip ~= "INVTYPE_BODY"
	-- an item on a BiS list already says whose it is, line by line: the stars
	-- are for the rest
	local listed = false
	if udb().bisTip ~= false and id then
		if not bisIndex then buildBisIndex() end
		local now = PHASE_ORDER[U.Phase()] or 4
		for _, e in pairs(bisIndex[AliId(id)] or {}) do
			for phase in pairs(e.places) do
				if (PHASE_ORDER[phase] or 0) <= now then listed = true end
			end
		end
	end
	if gear and not listed and udb().fitTip ~= false then starRows(link, name, id, rows) end
	-- where it drops: any raid item, tokens too
	if udb().dropTip ~= false and id then dropRows(id, rows) end
	if #rows == 0 then return end
	tip:AddLine(" ")
	local tname = tip:GetName()
	local firstLine = tip:NumLines() + 1
	for _, r in ipairs(rows) do tip:AddDoubleLine(r[1], r[2]) end
	-- the right text moved from the right edge to just after the widest left
	-- label (stars, Boss, Instance)
	local maxLeft = 0
	for i = firstLine, tip:NumLines() do
		local l = _G[tname .. "TextLeft" .. i]
		if l then maxLeft = math.max(maxLeft, l:GetWidth()) end
	end
	-- Every left label padded to the same width with an empty spacer (|T:h:w|t
	-- draws nothing): the tooltip then measures each line with room for the
	-- moved text, so nothing is cut to "He..." -- on every redraw, not just once
	movedRight[tip] = movedRight[tip] or {}
	for i = firstLine, tip:NumLines() do
		local l, r = _G[tname .. "TextLeft" .. i], _G[tname .. "TextRight" .. i]
		if l and r then
			local pad = math.floor(maxLeft - l:GetWidth() + 16)
			if pad > 0 then l:SetText((l:GetText() or "") .. "|T:1:" .. pad .. "|t") end
			r:ClearAllPoints()
			r:SetPoint("LEFT", l, "LEFT", maxLeft + 10, 0)
			movedRight[tip][i] = true
		end
	end
	tip:Show()
end

for _, t in ipairs({ GameTooltip, ItemRefTooltip }) do
	t:HookScript("OnTooltipSetItem", function(tip)
		local ok, err = pcall(onFitTip, tip)
		if not ok and Okanvil.Err then Okanvil:Err("Fits tooltip", err) end
		ok, err = pcall(onItemTip, tip)
		if not ok and Okanvil.Err then Okanvil:Err("BiS tooltip", err) end
	end)
end

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
			local b = FIT_TO_BIS[sk.key]
			local lists = b and OkanvilBis and OkanvilBis[b[1]]
			local rowsOf = lists and lists[b[2]] and lists[b[2]][now]
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

-- /okup                open the page
-- /okup <item link>    what the judge says about one item
-- /okup drops|fits|bis|sound  switch one tooltip part (or the drop alert) on / off
-- /okup toast | audit | phase [..]
local SWITCHES = {
	drops = { "dropTip", "Boss and instance lines on item tooltips" },
	fits  = { "fitTip", "Fits stars on item tooltips" },
	bis   = { "bisTip", "BiS lines on item tooltips" },
	sound = { "sound", "Upgrades drop sound" },
}
SLASH_OKUPGRADES1 = "/okup"
SlashCmdList.OKUPGRADES = function(arg)
	local word = arg and arg:lower():match("^%s*(%a+)")
	if word == "audit" then U.Audit(); return end
	local sw = SWITCHES[word]
	if sw then
		local key = sw[1]
		udb()[key] = (udb()[key] == false) and true or false
		Okanvil:Print(sw[2] .. " " .. (udb()[key] and "on" or "off") .. ".")
		if key == "sound" and udb().sound then PlaySoundFile(RAT_SOUND) end
		return
	end
	if word == "toast" then
		-- your best upgrade in this raid (or ICC), to see the toast and drag it into place
		local raid, mode = U.Here()
		raid, mode = raid or "icc", mode or "25n"
		for _, b in ipairs((Loot() or {})[raid] or {}) do
			local u = U.Of(b, raid, mode)[1]
			if u then
				showToast(u.link, u.v, nil, raid, tonumber(u.link:match("item:(%d+)")))
				PlaySoundFile(RAT_SOUND)
				return
			end
		end
		Okanvil:Print("Upgrades: no upgrade found yet (items still loading?), try again in a moment.")
		return
	end
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
	if not active() then Okanvil:Print("Upgrades is off (Modules)."); return end
	if not Okanvil.win or not Okanvil.win:IsShown() then Okanvil:Toggle() end
	Okanvil:ShowPanel(U.ADDON)
end
