-- ============================================================
--  Okanvil -- SoftRes-Live: soft reserves taken in game, for a PuG.
--
--  In a PuG only the master looter runs Okanvil, so raiders reserve by
--  whispering the master looter:
--      sr [item link]     reserve it (or replace the oldest when at the limit)
--      sr Item Name       the same, by name, for whoever has no link handy
--      sr                 "what did I reserve?"
--      sr remove          drop my reserves
--  Every whisper is answered, so nobody has to ask whether it worked. The
--  reserves land in the same list a softres.it import fills (SoftRes.lua), so
--  tags, tooltips and the roll filter treat them the same.
--
--  Only in SR mode, only while intake is open, and only on the master
--  looter's (or raid leader's) client. Intake closes at the first pull in a
--  raid instance, or by hand.
--
--  /okres test        solo test: a mock softres.it list, three test drops
--  /okres test w <Name> <text>   pretend <Name> whispered <text>
--  /okres test off    undo all of it
-- ============================================================

local Okanvil = Okanvil
local SR = Okanvil.SoftRes
if not SR then return end

local function db()
	Okanvil.db.softres = Okanvil.db.softres or {}
	local d = Okanvil.db.softres
	d.intake = d.intake or { open = false, limit = 1 }
	return d.intake
end

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function stripRealm(n) return n and (n:gsub("%-.*$", "")) or n end

local function linkOf(id)
	local _, link = GetItemInfo(id)
	if link then return link end
	local n = (Okanvil.db.softres.names or {})[id]
	return "[" .. (n or ("item " .. id)) .. "]"
end

-- ---- Intake state ----------------------------------------------------------
function SR.IntakeOpen() return db().open and true or false end
function SR.Limit() return db().limit or 1 end

function SR.SetLimit(n)
	n = math.max(1, math.min(3, tonumber(n) or 1))
	db().limit = n
	if SR.onPanel then SR.onPanel() end
	if SR.onChange then SR.onChange() end
end

function SR.SetIntake(open)
	db().open = open and true or false
	db().lockedAt = (not open) and time() or nil
	Okanvil:Print(open and "|cff7cfc8aSR open|r -- whispers \"sr [item]\" are recorded."
		or "|cffff5555SR locked|r -- whispers are answered with \"SR is locked\".")
	if SR.onPanel then SR.onPanel() end
	if SR.onChange then SR.onChange() end
end

-- Reserve whispers are answered by the master looter, or the leader before one
-- is set; anyone else in the raid with Okanvil stays quiet.
local function isLead()
	-- solo: nobody else could answer, and it is how the whisper flow is tested
	if (GetNumRaidMembers() or 0) == 0 and (GetNumPartyMembers() or 0) == 0 then return true end
	local RM = Okanvil.RollMgr
	if RM and RM.IsML and RM.IsML() then return true end
	return (IsRaidLeader and IsRaidLeader()) or (UnitIsPartyLeader and UnitIsPartyLeader("player")) or false
end

-- ---- Finding the item ------------------------------------------------------
-- The difficulty we are in, as RaidLoot-Data writes it ("25h"), or nil outside.
local function difficultyTag()
	return Okanvil.U and Okanvil.U.raidMode and Okanvil.U.raidMode() or nil
end

-- An item by name: the client cache first, then every raid's loot table. One
-- name drops in several difficulties as different items, so a table hit is
-- taken only when it is the one for the difficulty we are in, or the only one.
local function findByName(text)
	local low = trim(text):lower()
	if low == "" then return nil end
	local _, link = GetItemInfo(text)
	if link then return tonumber(link:match("item:(%d+)")) end
	local hits, tag = {}, difficultyTag()
	for _, raid in pairs(OkanvilRaidLoot or {}) do
		for _, b in ipairs(raid) do
			for _, it in ipairs(b.items or {}) do
				if it.name and it.name:lower() == low then
					if tag and it.m and it.m:find(tag, 1, true) then return it.id end
					hits[it.id] = true
				end
			end
		end
	end
	local only, n = nil, 0
	for id in pairs(hits) do only = id; n = n + 1 end
	return n == 1 and only or nil
end
SR.FindItemByName = findByName

-- ---- The whisper ----------------------------------------------------------
-- Answer a reserve whisper. `reply(text)` sends the answer; the test passes a
-- printer instead. Returns true when the line was a reserve command at all.
function SR.HandleWhisper(sender, msg, class, reply)
	local text = trim(msg or "")
	local after = text:match("^[Ss][Rr]%f[%A](.*)$")
	if not after and text:lower() ~= "sr" then return false end
	local rest = trim(after)
	sender = stripRealm(sender)

	local function mine()
		local ids = SR.ReservesOf(sender)
		local out = {}
		for i, id in ipairs(ids) do out[i] = linkOf(id) end
		return ids, table.concat(out, ", ")
	end

	if rest == "" then
		local ids, list = mine()
		reply(#ids > 0 and ("Your SR: " .. list .. ".")
			or "No SR yet. Whisper me: sr [item link]")
		return true
	end

	-- Our own answers start with "SR": one that comes back (a whisper to
	-- yourself, another master looter's Okanvil) must not be read as a request,
	-- or the two answer each other for ever.
	local low = rest:lower()
	if low:match("^saved") or low:match("^changed") or low:match("^is locked") or low:match("^not saved")
		or low:match("^removed") then
		return true
	end

	if not SR.IntakeOpen() then
		local _, list = mine()
		reply("SR is locked, nothing changed." .. (list ~= "" and (" Yours: " .. list .. ".") or ""))
		return true
	end

	if low == "remove" or low == "clear" or low == "del" or low == "delete" then
		local gone = SR.RemoveReserve(sender)
		reply(#gone > 0 and "SR removed." or "You had no SR.")
		return true
	end

	-- Every linked item, up to the limit; or one item by name.
	local ids = {}
	for lid in rest:gmatch("|Hitem:(%d+)") do
		if #ids < SR.Limit() then ids[#ids + 1] = tonumber(lid) end
	end
	if #ids == 0 then ids[1] = findByName((rest:gsub("^%[", ""):gsub("%]$", ""))) end
	if not ids[1] then
		reply("Item not found. Whisper me: sr [item link] (shift-click the item).")
		return true
	end
	for _, id in ipairs(ids) do SR.ReserveOne(sender, class, id, reply) end
	return true
end

-- One item for one raider, with its answer: refused, already there, replacing
-- the oldest at the limit, or saved.
function SR.ReserveOne(sender, class, id, reply)
	local d = Okanvil.db.softres
	local link = linkOf(id)

	-- Only loot of the raid being run: a vendor item or another raid's drop
	-- can never be rolled on tonight.
	if SR.DropsHere and not SR.DropsHere(id) then
		reply("SR not saved: " .. link .. " does not drop in " .. SR.RaidLabel() .. ".")
		return true
	end

	-- An item the raider's class cannot use is refused: it would only ever be
	-- won to be vendored. Unknown class (not in the group yet) is let through.
	local P = Okanvil.Prof
	local _, real = GetItemInfo(id)
	if class and P and P.CanEquip and real and not P.CanEquip(real, class) then
		reply("SR not saved: " .. link .. " is not for your class.")
		return true
	end

	-- the same item, either difficulty's copy
	local myName = GetItemInfo(id) or (d.names or {})[id]
	for _, have in ipairs(SR.ReservesOf(sender)) do
		if have == id or (myName and (GetItemInfo(have) or (d.names or {})[have]) == myName) then
			reply("You already reserved " .. link .. ".")
			return true
		end
	end

	local swapped
	local ids = SR.ReservesOf(sender)
	if #ids >= SR.Limit() then
		swapped = ids[1]
		SR.RemoveReserve(sender, swapped)
	end
	local itemName = GetItemInfo(id) or ((d.names or {})[id])
	SR.AddReserve(sender, class, id, itemName)
	local now = SR.ReservesOf(sender)
	if swapped then
		reply("SR changed: " .. linkOf(swapped) .. " -> " .. link .. ".")
	else
		reply("SR saved: " .. link .. " (" .. #now .. "/" .. SR.Limit() .. ").")
	end
	Okanvil:Print(("|cffe0b860SR|r %s -> %s"):format(sender, link))
	return true
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_WHISPER")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function(_, event, msg, sender, ...)
	if event == "PLAYER_REGEN_DISABLED" then
		-- The first pull closes intake: reserves are made before the loot is seen.
		if SR.WhisperMode() and SR.IntakeOpen() then
			local _, itype = IsInInstance()
			if itype == "raid" then SR.SetIntake(false) end
		end
		return
	end
	-- A locked list still answers ("SR is locked"), so this is not gated on intake.
	if not SR.WhisperMode() or not isLead() then return end
	if not (msg or ""):lower():match("^%s*sr") then return end
	local class
	local guid = select(10, ...)
	if guid and GetPlayerInfoByGUID then class = select(2, GetPlayerInfoByGUID(guid)) end
	local ok, err = pcall(SR.HandleWhisper, sender, msg, class, function(text)
		SendChatMessage(text, "WHISPER", nil, sender)
	end)
	if not ok and Okanvil.Err then Okanvil:Err("SR whisper", err) end
end)

-- ---- Telling the raid ------------------------------------------------------
local function channel()
	local L = Okanvil.Loot
	if L and L.SoloTestML and L.SoloTestML() then return nil end
	if (GetNumRaidMembers() or 0) > 0 then
		return ((IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer())) and "RAID_WARNING" or "RAID"
	end
	if (GetNumPartyMembers() or 0) > 0 then return "PARTY" end
	return nil
end

local function say(lines)
	local ch = channel()
	for i, line in ipairs(lines) do
		if ch then
			-- a raid warning per item would bury the screen; the list goes to raid chat
			local c = (i > 1 and ch == "RAID_WARNING") and "RAID" or ch
			Okanvil.Comms.After((i - 1) * 0.4, function() SendChatMessage(line, c) end)
		else
			Okanvil:Print("|cff8a8d93[test chat]|r " .. line)
		end
	end
end

-- Telling the raid "SR open" while whispers are locked would answer every one
-- of them with "SR is locked", so posting the rules opens intake too.
function SR.PostOpen()
	if not SR.IntakeOpen() then SR.SetIntake(true) end
	local n = SR.Limit()
	say({ ("SR open: whisper me  sr [item]  -- %d per player. Locks at the first pull."):format(n) })
end

function SR.PostList()
	if not SR.Active() then Okanvil:Print("Soft reserves are off in " .. SR.ModeLabel() .. " mode."); return end
	local lines = { "Soft reserves:" }
	for _, it in ipairs(SR.All()) do
		local line = "SR " .. linkOf(it.id) .. ": " .. SR.Names(it.id, true)
		if #line > 250 then line = line:sub(1, 247) .. "..." end
		lines[#lines + 1] = line
	end
	if #lines == 1 then Okanvil:Print("No reserves to post."); return end
	say(lines)
end

-- ---- Solo test -------------------------------------------------------------
-- Three ICC 25 drops: one reserved by you alone (Give), one contested by you
-- and two others (Roll SR), one nobody reserved (plain roll).
local TEST = {
	{ id = 50361, name = "Sindragosa's Flawless Fang", boss = "Sindragosa" },
	{ id = 50362, name = "Deathbringer's Will", boss = "Deathbringer Saurfang" },
	{ id = 50333, name = "Toskk's Maximized Wristguards", boss = "Deathbringer Saurfang" },
}

local function testCSV()
	local me = UnitName("player")
	local _, myClass = UnitClass("player")
	local cls = (myClass or "WARRIOR"):sub(1, 1) .. (myClass or "WARRIOR"):sub(2):lower()
	local rows = {
		"Item Name,Item ID,From,Raider Name,Discord ID,Discord Name,Raider Class,Raider Spec,Raider Note,Extra Reserves,Date",
		('"%s",%d,%s,%s,,,%s,,,0,2026-10-15'):format(TEST[1].name, TEST[1].id, TEST[1].boss, me, cls),
		('"%s",%d,%s,%s,,,%s,,,0,2026-10-15'):format(TEST[2].name, TEST[2].id, TEST[2].boss, me, cls),
		('"%s",%d,%s,Frostgrip,,,Death Knight,Frost,,0,2026-10-15'):format(TEST[2].name, TEST[2].id, TEST[2].boss),
		('"%s",%d,%s,Stabbington,,,Rogue,Combat,"needs it, BiS",0,2026-10-15'):format(TEST[2].name, TEST[2].id, TEST[2].boss),
	}
	return table.concat(rows, "\n")
end

local function whenCached(ids, fn, tries)
	tries = tries or 0
	local missing = false
	for _, id in ipairs(ids) do
		if not GetItemInfo(id) then
			missing = true
			GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
			pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. id)
			GameTooltip:Hide()
		end
	end
	if not missing or tries >= 6 then return fn(not missing) end
	Okanvil.Comms.After(1, function() whenCached(ids, fn, tries + 1) end)
end

local function testOn()
	local L, RM = Okanvil.Loot, Okanvil.RollMgr
	if (GetNumRaidMembers() or 0) > 0 or (GetNumPartyMembers() or 0) > 0 then
		Okanvil:Print("SR test: leave your group first (the test is solo only).")
		return
	end
	if L.WorldTest then L.WorldTest(true) end
	L._testML = true
	if RM and RM.ApplyMode then pcall(RM.ApplyMode) end
	SR.SetMode("sr")
	local ni, np = SR.Import(testCSV())
	SR.SetLimit(1)
	db().open = true
	Okanvil:Print(("SR test: mock softres.it list loaded (%s items, %s raiders), mode SR, intake open.")
		:format(tostring(ni), tostring(np)))
	local ids = {}
	for i, t in ipairs(TEST) do ids[i] = t.id end
	whenCached(ids, function(all)
		if not all then Okanvil:Print("|cffff5555SR test:|r some test items are not cached yet -- run /okres test again.") end
		for _, t in ipairs(TEST) do
			local dp, why = L.InjectTestDrop(t.id, "SR test")
			if not dp and why then Okanvil:Print("SR test: " .. t.name .. " not dropped (" .. why .. ").") end
		end
		if RM and RM.OnLootWindow then RM.OnLootWindow() end
		Okanvil:Print("SR test: Fang = Give (only you), Deathbringer's Will = Roll SR (3), Toskk's = no SR.")
		Okanvil:Print("SR test: /okres test w Frostgrip sr Sindragosa's Flawless Fang -- fake a whisper.")
	end)
end

local function testOff()
	local L, RM = Okanvil.Loot, Okanvil.RollMgr
	local n = L.PurgeTestDrops and L.PurgeTestDrops() or 0
	SR.Clear()
	db().open = false
	SR.SetMode(nil)
	if L.WorldTest then L.WorldTest(false) end
	L._testML = nil
	if RM and RM.ApplyMode then pcall(RM.ApplyMode) end
	Okanvil:Print(("SR test off: %d test drops removed, list cleared, mode back to Roll."):format(n))
end

-- /okres <cmd>; returns true when it handled the command.
function SR.Slash(arg)
	local cmd, rest = trim(arg or ""):match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()
	if cmd == "test" then
		local sub, more = rest:match("^(%S*)%s*(.*)$")
		sub = (sub or ""):lower()
		if sub == "off" then testOff()
		elseif sub == "raider" then
			if SR.TestRaider then SR.TestRaider((more or ""):lower()) end
		elseif sub == "w" then
			local who, text = more:match("^(%S+)%s+(.+)$")
			if not who then Okanvil:Print("Usage: /okres test w <Name> sr [item]"); return true end
			local cls = ({ frostgrip = "DEATHKNIGHT", stabbington = "ROGUE", lightwardh = "PALADIN",
				blinkzor = "MAGE" })[who:lower()]
			if not SR.HandleWhisper(who, text, cls, function(t)
				Okanvil:Print("|cffff80ff[W] To " .. who .. ": " .. t .. "|r")
			end) then
				Okanvil:Print("Not a reserve whisper (starts with \"sr\").")
			end
		else testOn() end
		return true
	elseif cmd == "mode" then
		local m = rest:lower()
		local map = { council = "council", sr = "sr", roll = "roll", off = false }
		if map[m] == nil then Okanvil:Print("Usage: /okres mode council | sr | roll"); return true end
		SR.SetMode(map[m] or nil)
		Okanvil:Print("Loot mode: " .. (SR.ModeLabel and SR.ModeLabel() or tostring(SR.Mode())))
		return true
	elseif cmd == "open" then SR.SetIntake(true); return true
	elseif cmd == "lock" then SR.SetIntake(false); return true
	elseif cmd == "post" then SR.PostOpen(); return true
	elseif cmd == "list" then SR.PostList(); return true
	end
	return false
end

function SR.ModeLabel(m)
	m = m or SR.Mode()
	return ({ council = "Council", sr = "SR", roll = "Roll" })[m] or "Roll"
end
