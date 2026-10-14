-- ============================================================
-- Okanvil -- Audit (native core module, no page).
-- What an inspect says about a player's preparation: unenchanted slots, empty
-- sockets, a missing belt buckle, cheap gems on raid gear, an inactive meta gem,
-- and which raid achievements they have.
--
-- Gear is read inside the Inspect module's own inspect window (Inspect calls
-- M.Gear), so it costs no extra request. Achievements need a second, separate
-- request (SetAchievementComparisonUnit), which this module queues itself: one
-- player at a time, only in range, never in combat. Both results land in the
-- Inspect cache next to the spec and gearscore.
-- ============================================================

local Okanvil = Okanvil
local M = {}
Okanvil.Audit = M

local function stripRealm(name)
	return name and (name:gsub("%-.*$", "")) or name
end

-- ------------------------------------------------------------
-- GEAR
-- ------------------------------------------------------------

-- Slots that take an enchant from anyone. Rings only take one from the wearer's
-- own Enchanting, which an inspect cannot see, so they are left out. Off hand and
-- ranged are decided by what is in them (see enchantable).
local ENCHANT_SLOTS = {
	{  1, "Head"      }, {  3, "Shoulders" }, { 15, "Cloak"  }, {  5, "Chest"    },
	{  9, "Bracers"   }, { 10, "Gloves"    }, {  7, "Legs"   }, {  8, "Boots"    },
	{ 16, "Weapon"    }, { 17, "Off hand"  }, { 18, "Ranged" },
}

-- Every slot that can hold a gem.
local GEM_SLOTS = {
	{  1, "Head"     }, {  2, "Neck"     }, {  3, "Shoulders" }, { 15, "Cloak"   },
	{  5, "Chest"    }, {  9, "Bracers"  }, { 10, "Gloves"    }, {  6, "Belt"    },
	{  7, "Legs"     }, {  8, "Boots"    }, { 11, "Ring"      }, { 12, "Ring"    },
	{ 13, "Trinket"  }, { 14, "Trinket"  }, { 16, "Weapon"    }, { 17, "Off hand" },
	{ 18, "Ranged"   },
}

local OFFHAND_ENCHANTABLE = {
	INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true,
	INVTYPE_2HWEAPON = true,                -- Titan's Grip
}
-- Only a hunter's bow, gun or crossbow takes a scope; a wand, relic or thrown
-- weapon takes nothing.
local RANGED_ENCHANTABLE = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true }

-- Rare gems are what a fresh 80 uses; on ICC-level gear they cost real stats.
local EPIC_GEMS_FROM_ILVL = 245

-- Gem colours by item sub-type. The sub-type is the client's localized word, so
-- this reads an enUS client only; elsewhere colours stay unknown and the meta
-- check reports "unknown" rather than guessing.
local GEM_COLOURS = {
	Red = { r = 1 }, Yellow = { y = 1 }, Blue = { b = 1 },
	Orange = { r = 1, y = 1 }, Green = { y = 1, b = 1 }, Purple = { r = 1, b = 1 },
	Prismatic = { r = 1, y = 1, b = 1 },
}
local META_SUBTYPE = "Meta"

local function enchantable(slot, equipLoc, class)
	if slot == 17 then return OFFHAND_ENCHANTABLE[equipLoc or ""] == true end
	if slot == 18 then return class == "HUNTER" and RANGED_ENCHANTABLE[equipLoc or ""] == true end
	return true
end

-- How many sockets the item was MADE with. Read from the bare item, not the
-- equipped link: the equipped one carries the gems, and a filled socket is not
-- reported as a socket any more.
local function baseSockets(itemId)
	local _, baseLink = GetItemInfo(itemId)
	local stats = baseLink and GetItemStats and GetItemStats(baseLink)
	if not stats then return nil end
	local n, meta = 0, false
	for k, v in pairs(stats) do
		if type(k) == "string" and k:find("^EMPTY_SOCKET_") then
			n = n + (tonumber(v) or 1)
			if k == "EMPTY_SOCKET_META" then meta = true end
		end
	end
	return n, meta
end

local tip
local function tipLines(link)
	if not tip then
		tip = CreateFrame("GameTooltip", "OkanvilAuditTip", nil, "GameTooltipTemplate")
	end
	tip:ClearLines()
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	local out = {}
	if pcall(tip.SetHyperlink, tip, link) then
		for i = 2, tip:NumLines() do
			local fs = _G["OkanvilAuditTipTextLeft" .. i]
			local t = fs and fs:GetText()
			if t then out[#out + 1] = t end
		end
	end
	tip:Hide()
	return out
end

-- The meta gem's own condition, as written on its tooltip:
--   "Requires at least 1 Red Gem, at least 1 Yellow Gem, and at least 1 Blue Gem."
--   "Requires more Blue gems than Red gems."
-- Returns { min = { r=, y=, b= }, more = { {a, b}, ... } } or nil when unreadable.
local COLOUR_KEY = { red = "r", yellow = "y", blue = "b" }
local function metaRule(gemLink)
	for _, line in ipairs(tipLines(gemLink)) do
		local low = line:lower()
		if low:find("requires") and low:find("gem") then
			local rule = { min = {}, more = {} }
			for a, b in low:gmatch("more (%a+) gems? than (%a+) gems?") do
				if COLOUR_KEY[a] and COLOUR_KEY[b] then rule.more[#rule.more + 1] = { COLOUR_KEY[a], COLOUR_KEY[b] } end
			end
			for n, c in low:gmatch("(%d+) (%a+) gems?") do
				if COLOUR_KEY[c] then rule.min[COLOUR_KEY[c]] = tonumber(n) end
			end
			if next(rule.min) or #rule.more > 0 then return rule end
		end
	end
	return nil
end

local function metaActive(rule, have)
	for c, n in pairs(rule.min) do
		if (have[c] or 0) < n then return false end
	end
	for _, p in ipairs(rule.more) do
		if (have[p[1]] or 0) <= (have[p[2]] or 0) then return false end
	end
	return true
end

-- The audit of one inspected unit. Called by Inspect while the inspect cache
-- holds this unit's gear.
--   noEnchant   = { "Cloak", "Boots" }
--   empty       = sockets with no gem;  emptySlots = { "Belt" }
--   noBuckle    = the belt has no extra socket in use
--   lowGems     = rare-or-worse gems on EPIC_GEMS_FROM_ILVL+ items
--   meta        = true active / false inactive / nil no meta or unreadable
--   partial     = some item was not in the client's cache, so a check was skipped
function M.Gear(unit)
	local _, class = UnitClass(unit)
	local a = { noEnchant = {}, empty = 0, emptySlots = {}, noBuckle = false,
		lowGems = 0, partial = false }
	local colours = { r = 0, y = 0, b = 0 }
	local coloursKnown = true
	local metaLink

	for _, e in ipairs(ENCHANT_SLOTS) do
		local link = GetInventoryItemLink(unit, e[1])
		if link then
			local ench = link:match("item:%d+:(%-?%d+)")
			local equipLoc = select(9, GetItemInfo(link))
			if (e[1] == 17 or e[1] == 18) and not equipLoc then
				a.partial = true
			elseif ench == "0" and enchantable(e[1], equipLoc, class) then
				a.noEnchant[#a.noEnchant + 1] = e[2]
			end
		end
	end

	for _, e in ipairs(GEM_SLOTS) do
		local slot, slotName = e[1], e[2]
		local link = GetInventoryItemLink(unit, slot)
		local id = link and tonumber(link:match("item:(%d+)"))
		if id then
			local sockets = baseSockets(id)
			if not sockets then
				a.partial = true
			else
				local filled = 0
				for i = 1, 4 do
					local gemName, gemLink = nil, nil
					if GetItemGem then gemName, gemLink = GetItemGem(link, i) end
					if gemLink then
						filled = filled + 1
						local _, _, q, _, _, _, subType = GetItemInfo(gemLink)
						if subType == META_SUBTYPE then
							metaLink = gemLink
						elseif not q then
							a.partial = true
							coloursKnown = false
						else
							local ilvl = select(4, GetItemInfo(link)) or 0
							if q < 4 and ilvl >= EPIC_GEMS_FROM_ILVL then a.lowGems = a.lowGems + 1 end
							local c = GEM_COLOURS[subType or ""]
							if c then
								for k in pairs(c) do colours[k] = colours[k] + 1 end
							else
								coloursKnown = false
							end
						end
					end
				end
				-- A belt buckle adds one socket that the bare item does not have.
				local want = (slot == 6) and sockets + 1 or sockets
				if filled < want then
					if slot == 6 and filled == sockets then
						a.noBuckle = true
					else
						a.empty = a.empty + (want - filled)
						a.emptySlots[#a.emptySlots + 1] = slotName
					end
				end
			end
		end
	end

	if metaLink then
		local rule = coloursKnown and metaRule(metaLink)
		if rule then a.meta = metaActive(rule, colours) end
	end
	return a
end

-- Problems that cost the raid something, and the softer ones.
function M.Counts(a)
	if not a then return nil end
	local hard = #(a.noEnchant or {}) + (a.empty or 0) + (a.noBuckle and 1 or 0) + (a.meta == false and 1 or 0)
	return hard, (a.lowGems or 0)
end

-- One friendly whisper listing what to fix, or nil when there is nothing.
function M.WhisperText(a)
	if not a then return nil end
	local bits = {}
	local ne = a.noEnchant or {}
	if #ne > 0 then bits[#bits + 1] = table.concat(ne, " + ") .. " unenchanted" end
	if (a.empty or 0) > 0 then
		bits[#bits + 1] = a.empty .. " empty socket" .. (a.empty > 1 and "s" or "")
			.. " (" .. table.concat(a.emptySlots, ", ") .. ")"
	end
	if a.noBuckle then bits[#bits + 1] = "belt missing buckle" end
	if a.meta == false then bits[#bits + 1] = "meta gem not active" end
	if #bits == 0 then return nil end
	local msg = "Hi! Quick gear check: " .. table.concat(bits, ", ") .. ". Can you fix before pull? :)"
	if #msg > 250 then msg = msg:sub(1, 247) .. "..." end
	return msg
end

-- ------------------------------------------------------------
-- ACHIEVEMENTS
--
-- The ids are RaidFinder's table (Okanvil.RaidFinder_Achievements), which has a
-- "Verify Achievement IDs" button for this server; an id the server does not
-- know is skipped, never shown as "missing".
-- ------------------------------------------------------------

-- The chips for one raid key from the PuG catalogue ("icc", "toc", ...), in
-- table order: { { id, label }, ... }. Empty when the raid has none.
function M.RaidChips(raidKey)
	local out = {}
	for _, e in ipairs(Okanvil.RaidFinder_Achievements or {}) do
		local size = raidKey and e.raid:match("^" .. raidKey .. "(%d+)")
		if size and GetAchievementInfo(e.id) then
			out[#out + 1] = { id = e.id, label = size .. (e.raid:find("hc$") and " HC" or "") }
		end
	end
	return out
end

local ACH_TTL = 3 * 3600        -- one night: earned achievements do not go away
local ACH_EVERY, ACH_TIMEOUT, ACH_TRIES = 2, 4, 3

local want = {}                 -- [name] = tries
local curName, curUnit, waited
local acc = 0

local function unitFor(name)
	local raidN = GetNumRaidMembers() or 0
	if raidN > 0 then
		for i = 1, raidN do
			if stripRealm(UnitName("raid" .. i)) == name then return "raid" .. i end
		end
		return nil
	end
	for i = 1, GetNumPartyMembers() or 0 do
		if stripRealm(UnitName("party" .. i)) == name then return "party" .. i end
	end
	return nil
end

local function hasFreshAch(name)
	local I = Okanvil.Inspect
	local info = I and I.Info and I.Info(name)
	return info and info.achAt and (time() - info.achAt) < ACH_TTL
end

local runner = CreateFrame("Frame")
runner:Hide()

-- Queue a player's achievements to be read once they are in range.
function M.WantAchievements(name)
	name = stripRealm(name)
	if not name or name == "" or name == stripRealm(UnitName("player")) then return end
	if want[name] or hasFreshAch(name) then return end
	if not SetAchievementComparisonUnit then return end
	want[name] = 0
	runner:Show()
end

local function release()
	if ClearAchievementComparisonUnit then ClearAchievementComparisonUnit() end
	curName, curUnit, waited = nil, nil, 0
end

local function notify(name)
	if M.onRead then
		local ok, err = pcall(M.onRead, name)
		if not ok and Okanvil.Err then Okanvil:Err("Audit.onRead", err) end
	end
end

runner:RegisterEvent("INSPECT_ACHIEVEMENT_READY")
runner:SetScript("OnEvent", function(_, _, guid)
	-- It is ours only while we are waiting on one player. Some 3.3.5a cores send
	-- the GUID, others nothing; when it is there, it must be our player's.
	if not curName then return end
	local same = stripRealm(UnitName(curUnit) or "") == curName
	if same and guid and UnitGUID(curUnit) and guid ~= UnitGUID(curUnit) then same = false end
	if same then
		local got = {}
		for _, e in ipairs(Okanvil.RaidFinder_Achievements or {}) do
			if GetAchievementInfo(e.id) then
				got[e.id] = GetAchievementComparisonInfo(e.id) and true or false
			end
		end
		local I = Okanvil.Inspect
		if I and I.Put then I.Put(curName, { ach = got, achAt = time() }) end
		Okanvil:Trace("AUDIT", "achievements read for " .. curName)
		want[curName] = nil
		local name = curName
		release()
		notify(name)
	else
		release()
	end
end)

runner:SetScript("OnUpdate", function(self, elapsed)
	if curName then
		waited = waited + elapsed
		if waited >= ACH_TIMEOUT then release() end
		return
	end
	acc = acc + elapsed
	if acc < ACH_EVERY then return end
	acc = 0
	if not next(want) then self:Hide(); return end
	-- Passive work: wait out combat, a running talent scan, and an open
	-- Achievements window (its own comparison would be switched to someone else).
	if InCombatLockdown and InCombatLockdown() then return end
	local I = Okanvil.Inspect
	if I and I.IsScanning and I.IsScanning() then return end
	if AchievementFrame and AchievementFrame:IsShown() then return end

	for name, tries in pairs(want) do
		local unit = unitFor(name)
		if not unit or tries >= ACH_TRIES or hasFreshAch(name) then
			want[name] = nil
		elseif UnitIsConnected(unit) and CheckInteractDistance(unit, 1) then
			want[name] = tries + 1
			curName, curUnit, waited = name, unit, 0
			SetAchievementComparisonUnit(unit)
			return
		end
	end
end)
