-- Offline replay of raid loot chat against the real Loot.lua.
-- Run from the repo root:  lua5.1 scripts/loot_replay_test.lua
-- LOOT_FILE=<path> swaps in another Loot.lua (e.g. an older version) to compare.
-- Scenarios come from real raids where a master looter without Okanvil lost tokens.
local ROOT = "Okanvil/"

-- ---- clock ----
local NOW = 1792540000
function time() return NOW end
function GetTime() return NOW end
local function advance(s) NOW = NOW + s end

-- ---- frames: record OnEvent handlers so we can fire events ----
local frames = {}
local function newFrame()
	local f = { scripts = {} }
	local mt = { __index = function(t, k)
		return function(self, ...)
			if k == "SetScript" then local name, fn = ...; self.scripts[name] = fn end
			if k == "GetScript" then return self.scripts[(...)] end
			if k == "NumLines" then return 0 end
			return nil
		end
	end }
	setmetatable(f, mt)
	frames[#frames + 1] = f
	return f
end
function CreateFrame() return newFrame() end
local function fire(event, ...)
	for _, f in ipairs(frames) do
		local h = f.scripts.OnEvent
		if h then h(f, event, ...) end
	end
end

-- ---- WoW globals the loot path touches ----
function GetRealmName() return "Onyxia" end
SlashCmdList = {}
function UnitGUID() return nil end
function UnitExists() return false end
function UnitIsDead() return false end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strsplit = function(sep, s)
	local out = {}
	for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = p end
	return unpack(out)
end
date = os.date
LOOT_ITEM = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED = "%s receives item: %s."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ROLL_WON = "%s won: %s"
LOOT_ROLL_YOU_WON = "You won: %s"
LOOT_ROLL_ALL_PASSED = "Everyone passed on: %s"
LOOT_ROLL_NEED = "Need Roll - %d for %s by %s"
ITEM_BIND_ON_PICKUP = "Binds when picked up"
ITEM_BIND_ON_EQUIP = "Binds when equipped"
ITEM_BIND_QUEST = "Quest Item"

local ME, ML = "Okanath", "Gatlock"
function UnitName(u) if u == "player" then return ME end return nil end
function UnitClass() return "Death Knight", "DEATHKNIGHT" end
function GetLootMethod() return "master", nil, 2 end
function GetRaidRosterInfo(i) if i == 2 then return ML end return "Raider" .. i end
function GetNumRaidMembers() return 25 end
function GetNumPartyMembers() return 4 end
function IsInRaid() return true end
function IsInInstance() return true, "raid" end
function GetInstanceInfo() return "Icecrown Citadel", "raid", 2, "25 Player", 25, 0, false, 631 end
function GetRealZoneText() return "Icecrown Citadel" end
function GetNumSavedInstances() return 1 end
function GetSavedInstanceInfo() return "Icecrown Citadel", 8276882, 400000, 2, true, false, 0, true, 25 end

local ITEMS = {
	[52025] = "Vanquisher's Mark of Sanctification",
	[52026] = "Protector's Mark of Sanctification",
	[52027] = "Conqueror's Mark of Sanctification",
	[50423] = "Sundial of Eternal Dusk",
	[50333] = "Toskk's Maximized Wristguards",
}
local function link(id) return ("|cffa335ee|Hitem:%d:0:0:0:0:0:0:0:80|h[%s]|h|r"):format(id, ITEMS[id]) end
function GetItemInfo(x)
	local id = tonumber(tostring(x):match("item:(%d+)")) or tonumber(x)
	if not ITEMS[id] then return nil end
	return ITEMS[id], link(id), 4, 251, 80, "Miscellaneous", "Junk", 1, "", "Interface\\Icons\\x"
end
function GetItemIcon() return "Interface\\Icons\\x" end
function GetAuctionItemClasses() return "Weapon", "Armor", "Container", "Consumable", "Glyph", "Trade Goods", "Projectile", "Quiver", "Recipe", "Gem", "Miscellaneous", "Quest" end

-- ---- Okanvil host ----
Okanvil = { db = {}, cdb = {}, ICONS = {} }
function Okanvil:Trace(cat, msg) TRACE = TRACE or {}; TRACE[#TRACE + 1] = cat .. " " .. msg end
function Okanvil:Print() end
function Okanvil:Err(_, e) print("ERR", e) end
function Okanvil:WarmItem() end
function Okanvil:RegisterPlugin() end
function Okanvil:ModuleActive() return true end

local LOOT_FILE = os.getenv("LOOT_FILE")
for _, f in ipairs({ "Core/Util.lua", "Modules/Bosses-Data.lua", "Modules/ItemBoss-Data.lua",
	"Modules/RaidLoot-Data.lua", "Modules/Loot.lua" }) do
	local path = (f == "Modules/Loot.lua" and LOOT_FILE) or (ROOT .. f)
	local chunk = assert(loadfile(path))
	local ok, err = pcall(chunk)
	if not ok then print("LOAD", f, err) end
end
local L = Okanvil.Loot

-- ---- scenario helpers ----
local function session()
	local list = Okanvil.cdb.lootSessions or (Okanvil.cdb and Okanvil.cdb.loot and Okanvil.cdb.loot.sessions)
	return list and list[1]
end
local function killBoss(cid)
	-- 0xF13000xxxx...: cid in hex chars 6..10
	local guid = ("0xF1300%05X000001"):format(cid)
	fire("COMBAT_LOG_EVENT_UNFILTERED", NOW, "UNIT_DIED", nil, "", 0, guid, "boss", 0)
end
local function say(msg) fire("CHAT_MSG_LOOT", msg) end
local function rows(boss, id)
	local s, n = session(), 0
	for _, d in ipairs(s and s.drops or {}) do
		if (not boss or d.boss == boss) and (not id or d.id == id) then n = n + 1 end
	end
	return n
end
local fails = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then fails = fails + 1 end
	print(("%s  %-60s got %s want %s"):format(ok and "PASS" or "FAIL", label, tostring(got), tostring(want)))
end

-- 1) Putricide: a Protector Mark from a scanned corpse, still held by the ML
killBoss(36678)                    -- Professor Putricide
say(("%s receives loot: %s."):format(ML, link(52026)))
local s = session()
-- in-game this row came from our own corpse scan, not the ML's chat
for _, d in ipairs(s.drops) do if d.id == 52026 then d.fromML = nil; d.corpse = "0xF150008F4600040E"; d.heldBy = ML end end
print("session", s and s.key, "drops", s and #s.drops)
check("Putricide Protector recorded", rows("Professor Putricide", 52026), 1)

-- 2) an hour later, Sindragosa: ML (no Okanvil) loots 3 items
advance(3600)
killBoss(36853)                    -- Sindragosa
say(("%s receives loot: %s."):format(ML, link(50423)))
say(("%s receives loot: %s."):format(ML, link(52025)))
say(("%s receives loot: %s."):format(ML, link(52026)))
check("Sindragosa Sundial", rows("Sindragosa", 50423), 1)
check("Sindragosa Vanquisher", rows("Sindragosa", 52025), 1)
check("Sindragosa Protector (was swallowed)", rows("Sindragosa", 52026), 1)
check("Putricide Protector untouched", rows("Professor Putricide", 52026), 1)

-- 3) Saurfang-style: two of the SAME token off one boss
advance(3600)
killBoss(37813)                    -- Deathbringer Saurfang
say(("%s receives loot: %s."):format(ML, link(52026)))
say(("%s receives loot: %s."):format(ML, link(52026)))
say(("%s receives loot: %s."):format(ML, link(50333)))
check("Saurfang 2x Protector", rows("Deathbringer Saurfang", 52026), 2)
check("Saurfang Wristguards", rows("Deathbringer Saurfang", 50333), 1)

-- 4) ML wins two native rolls on two copies: each win takes its own copy
local sc = session()
local copies = {}
for _, d in ipairs(sc.drops) do if d.boss == "Deathbringer Saurfang" and d.id == 52026 then copies[#copies + 1] = d end end
say(("%s won: %s"):format(ML, link(52026)))
say(("%s won: %s"):format(ML, link(52026)))
check("copy 1 won by ML", copies[1] and copies[1].receivedBy, ML)
check("copy 2 won by ML", copies[2] and copies[2].receivedBy, ML)

-- 5) the ML hands a copy to a raider: it lands on a free copy of the newest boss, not Putricide
advance(10)
killBoss(36853)
advance(5)
say(("%s receives loot: %s."):format("Mijinho", link(52026)))
local putri
for _, d in ipairs(sc.drops) do if d.boss == "Professor Putricide" and d.id == 52026 then putri = d end end
print("putricide row: received", putri and putri.receivedBy, "held", putri and putri.heldBy)

-- 6) an auction-worded call on two identical Marks: "Bidding for [item] started.
-- Please place your bets." Each bid's rolls belong to its own copy.
advance(600)
killBoss(36853)
say(("%s receives loot: %s."):format(ML, link(52027)))
say(("%s receives loot: %s."):format(ML, link(52027)))
local conq = {}
for _, d in ipairs(sc.drops) do if d.boss == "Sindragosa" and d.id == 52027 then conq[#conq + 1] = d end end
local function rollsOf(d)
	local got = {}
	for _, e in ipairs(d and d.rolls or {}) do got[#got + 1] = e.player .. " " .. e.roll end
	return table.concat(got, ", ")
end
local bid = ("Bidding for %s started. Please place your bets."):format(link(52027))
fire("CHAT_MSG_RAID_WARNING", bid, ML)
fire("CHAT_MSG_SYSTEM", "Mijinho rolls 57 (1-100)")
fire("CHAT_MSG_SYSTEM", "Yahmom rolls 83 (1-100)")
fire("CHAT_MSG_RAID_WARNING", ("Bidding for %s ended."):format(link(52027)), ML)
fire("CHAT_MSG_RAID_WARNING", bid, ML)
fire("CHAT_MSG_SYSTEM", "Radnah rolls 12 (1-100)")
check("bidding: rolls of the 1st bid on copy 1", rollsOf(conq[1]), "Mijinho 57, Yahmom 83")
check("bidding: rolls of the 2nd bid on copy 2", rollsOf(conq[2]), "Radnah 12")
check("bidding: no extra copy", rows("Sindragosa", 52027), 2)

-- 7) any wording from the ML over raid warning is a call, once the raid rolls on it;
-- a result line, an item that is not this raid's loot, or a link nobody rolls on is not
local function allRolls(id)
	local out = {}
	for _, d in ipairs(sc.drops) do
		if d.id == id and d.rolls and #d.rolls > 0 then out[#out + 1] = rollsOf(d) end
	end
	return table.concat(out, " | ")
end
advance(600)
killBoss(36853)
say(("%s receives loot: %s."):format(ML, link(50423)))
fire("CHAT_MSG_RAID_WARNING", ("%s goes to Mijinho"):format(link(50423)), ML)
fire("CHAT_MSG_SYSTEM", "Lecoque rolls 40 (1-100)")
check("'goes to' line opens no roll", allRolls(50423), "")
advance(120)
ITEMS[12345] = "Someone's Old Sword"
fire("CHAT_MSG_RAID_WARNING", ("look at my %s lol"):format(link(12345)), ML)
fire("CHAT_MSG_SYSTEM", "Lecoque rolls 40 (1-100)")
check("item not from this raid opens no roll", rows(nil, 12345), 0)
advance(120)
fire("CHAT_MSG_RAID_WARNING", ("Next up %s, go go"):format(link(50423)), ML)
advance(90)
fire("CHAT_MSG_SYSTEM", "Lecoque rolls 40 (1-100)")
check("nobody rolled within a minute: no roll", allRolls(50423), "")
fire("CHAT_MSG_RAID_WARNING", ("Next up %s, go go"):format(link(50423)), ML)
advance(5)
fire("CHAT_MSG_SYSTEM", "Onetreeheals rolls 91 (1-100)")
fire("CHAT_MSG_SYSTEM", "Lecoque rolls 22 (1-100)")
check("free-worded call + rolls: tracked", allRolls(50423), "Onetreeheals 91, Lecoque 22")

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
if os.getenv("TRACE") then for _, l in ipairs(TRACE or {}) do print(l) end end
