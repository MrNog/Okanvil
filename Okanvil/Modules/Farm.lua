-- ============================================================
-- Okanvil -- Farm (native core module).
-- A small floating window that answers one question while you farm: how much
-- gold an hour is this actually making?
--
-- Counts three things and divides by the time the session has been RUNNING:
--   * cash picked up off corpses
--   * what the items you looted are worth
--   * quest rewards
--
-- Paused time does not count, so stepping away to eat does not wreck the rate.
-- ============================================================

local Okanvil = Okanvil
local M = {}
Okanvil.Farm = M

local ADDON = "Okanvil-Farm"

-- ------------------------------------------------------------
-- Saved variables -- per character.
--
-- A farm run belongs to the toon that ran it: your miner's gold/hr says nothing
-- about your herbalist, and averaging the two would make the number meaningless.
-- ------------------------------------------------------------
local function db()
	Okanvil_CharDB = Okanvil_CharDB or {}
	Okanvil_CharDB.farm = Okanvil_CharDB.farm or {}
	local d = Okanvil_CharDB.farm
	if d.price == nil then d.price = "auto" end   -- "auto" = AH price, else vendor
	if d.scale == nil then d.scale = 100 end
	if type(d.history) ~= "table" then d.history = {} end
	return d
end
M.DB = db

-- ------------------------------------------------------------
-- The live session. Deliberately NOT saved: a farm run is a thing you start and
-- stop in one sitting, and a half-finished session restored after a /reload would
-- quietly keep counting time you were not farming.
-- ------------------------------------------------------------
local S = {
	running = false,
	startedAt = nil,      -- when the current RUNNING stretch began
	elapsed = 0,          -- seconds banked from previous stretches
	cash = 0, items = 0, quests = 0,
	kills = 0, drops = 0,
	zone = "",
	loot = {},            -- [itemLink] = { value, count }
}
M.S = S

local function now() return (GetTime and GetTime()) or 0 end

-- Seconds this session has actually been running.
function M.Duration()
	if not S.running or not S.startedAt then return S.elapsed end
	return S.elapsed + (now() - S.startedAt)
end

function M.Total() return (S.cash or 0) + (S.items or 0) + (S.quests or 0) end
-- Same run, priced two ways. Cash and quest gold are real money either way, so
-- only the item half differs.
function M.TotalVendor() return (S.cash or 0) + (S.itemsVendor or 0) + (S.quests or 0) end
function M.TotalAH()     return (S.cash or 0) + (S.itemsAH or 0) + (S.quests or 0) end

-- The whole point of the module: copper per hour.
function M.GoldPerHour()
	local dur = M.Duration()
	if dur < 5 then return 0 end     -- under 5s the rate is noise, not information
	-- Rated at AH value, matching the highlighted figure in the window: the
	-- headline and the breakdown must be the same number or one of them is a lie.
	return math.floor(M.TotalAH() / dur * 3600)
end

function M.IsRunning() return S.running end

-- ------------------------------------------------------------
-- Money formatting -- "1,234g 56s" style, short enough for a narrow window.
-- ------------------------------------------------------------
function M.Money(copper, short)
	copper = math.floor(tonumber(copper) or 0)
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	if short and g > 0 then
		if g >= 10000 then return string.format("|cffffd700%.1fk|rg", g / 1000) end
		return "|cffffd700" .. g .. "|rg " .. string.format("%02d", s) .. "s"
	end
	if g > 0 then
		return "|cffffd700" .. g .. "|rg |cffc7c7cf" .. s .. "|rs"
	elseif s > 0 then
		return "|cffc7c7cf" .. s .. "|rs |cffeda55f" .. c .. "|rc"
	end
	return "|cffeda55f" .. c .. "|rc"
end

function M.Clock(secs)
	secs = math.floor(tonumber(secs) or 0)
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
	return string.format("%d:%02d", m, s)
end

-- ------------------------------------------------------------
-- What is an item worth?
--
-- An auction addon's price is the honest answer for anything you would sell --
-- vendor price on a stack of Saronite is off by an order of magnitude. Auctionator
-- is checked first (it is what the guild runs), then TSM, then the vendor price
-- the game itself reports. `price = "vendor"` forces the last one, for someone who
-- vendors everything and wants the number to match what they actually get.
-- ------------------------------------------------------------
local function auctionPrice(link)
	if _G.Atr_GetAuctionBuyout then
		local p = _G.Atr_GetAuctionBuyout(link)
		if p and p > 0 then return p end
	end
	if _G.Atr_GetAuctionPrice then
		local p = _G.Atr_GetAuctionPrice(link)
		if p and p > 0 then return p end
	end
	if _G.TSMAPI and _G.TSMAPI.GetItemValue then
		local ok, p = pcall(_G.TSMAPI.GetItemValue, link, "DBMarket")
		if ok and p and p > 0 then return p end
	end
	return nil
end

function M.ItemValue(link)
	if not link then return 0 end
	local _, _, _, _, _, _, _, _, _, _, vendor = GetItemInfo(link)
	if db().price ~= "vendor" then
		local p = auctionPrice(link)
		if p then return p end
	end
	return vendor or 0
end

-- The two prices split out. Vendor is what the game itself pays and is always
-- known; AH needs an auction addon and falls back to vendor when there is no
-- price for the item, so the two totals stay comparable instead of the AH one
-- silently dropping whatever Auctionator has never seen.
function M.VendorValue(link)
	if not link then return 0 end
	local vendor = select(11, GetItemInfo(link))
	return vendor or 0
end

function M.AHValue(link)
	if not link then return 0 end
	return auctionPrice(link) or M.VendorValue(link)
end

-- ------------------------------------------------------------
-- Session control
-- ------------------------------------------------------------
function M.Start()
	if S.running then return end
	if not S.startedAt and S.elapsed == 0 then
		S.zone = (GetRealZoneText and GetRealZoneText()) or ""
	end
	S.running = true
	S.startedAt = now()
	if M.onChange then M.onChange() end
end

function M.Pause()
	if not S.running then return end
	S.elapsed = M.Duration()
	S.running = false
	S.startedAt = nil
	if M.onChange then M.onChange() end
end

function M.Toggle()
	if S.running then M.Pause() else M.Start() end
end

-- Bank the run into history, then clear.
--
-- A run that is too short or made nothing is not banked -- a mis-click that
-- started and stopped the timer is not a farm session. But it SAYS so: this used
-- to drop the run without a word, so pressing Finish after a real session that
-- happened to miss a threshold looked exactly like the history being broken.
local MIN_RUN = 30       -- seconds

function M.Stop()
	-- `total` stays the AH figure so the history row matches the rate the window
	-- showed while the run was going; the vendor figure rides along beside it.
	local dur, total = M.Duration(), M.TotalAH()
	if dur < MIN_RUN then
		Okanvil:Print(("|cff8a8d93Run not saved -- only %s. A session has to last %ds.|r")
			:format(M.Clock(dur), MIN_RUN))
	elseif total <= 0 then
		Okanvil:Print("|cff8a8d93Run not saved -- nothing was looted or earned.|r")
	else
		local h = db().history
		table.insert(h, 1, {
			at = time(), zone = S.zone, dur = dur, total = total,
			totalVendor = M.TotalVendor(),
			cash = S.cash, items = S.items, quests = S.quests,
			itemsVendor = S.itemsVendor, itemsAH = S.itemsAH,
			kills = S.kills, drops = S.drops,
		})
		-- keep the last 20; the window shows a handful and the file stays small
		while #h > 20 do table.remove(h) end
		local gph = (dur > 0) and math.floor(total / dur * 3600) or 0
		Okanvil:Print(("Run saved -- |cffffd200%s|r in %s (|cffe0b860%s/h|r)."):format(
			M.Money(total, true), M.Clock(dur), M.Money(gph, true)))
	end
	M.Reset()
end

function M.Reset()
	S.running, S.startedAt, S.elapsed = false, nil, 0
	S.cash, S.items, S.quests = 0, 0, 0
	S.itemsVendor, S.itemsAH = 0, 0
	S.kills, S.drops = 0, 0
	S.zone = (GetRealZoneText and GetRealZoneText()) or ""
	S.loot = {}
	if M.onChange then M.onChange() end
end

function M.History() return db().history end
function M.ClearHistory() db().history = {} end

-- The items looted this session, best-value first -- so "what actually paid for
-- this run" is the top of the list, not a wall of grey trash.
function M.LootList()
	local out = {}
	for link, e in pairs(S.loot) do
		out[#out + 1] = { link = link, value = e[1], count = e[2] }
	end
	table.sort(out, function(a, b) return a.value > b.value end)
	return out
end

-- ------------------------------------------------------------
-- Capture
-- ------------------------------------------------------------
-- Things a farm run should not count as loot.
--
-- Emblems, marks and badges arrive through the same "You receive loot:" line as
-- a real drop, but they are currency: the vendor pays 0 for them, so they land
-- in the list worth nothing and push the actual drops down it. A dungeon run
-- ends up reading as twenty "drops" that earned no gold.
--
-- Matched on the item's own SELL PRICE and class, never on its name -- "Emblem"
-- is English and this has to hold on any client. Anything the vendor will not
-- pay for is not farm income.
local function isCurrency(link)
	if not link then return false end
	local _, _, _, _, _, class, _, _, _, _, vendor = GetItemInfo(link)
	-- NOT CACHED YET: keep it. A drop the client has never seen returns nils, and
	-- treating that as currency would silently bin a real item -- an orb the first
	-- time you ever loot one. Warm it so the next paint prices it properly.
	if class == nil then
		if Okanvil.WarmItem then Okanvil:WarmItem(link) end
		return false
	end
	-- Worth something to a vendor: real loot, whatever it is.
	if (vendor or 0) > 0 then return false end
	-- Worth nothing to a vendor, and the client knows what it is. Emblems, marks
	-- and badges land here; so do quest items and keys, which are equally not farm
	-- income. Anything actually valuable has a sell price, so this needs no list of
	-- item classes -- and no English name to match on.
	return true
end

local function addLoot(link, count)
	if not link then return end
	-- Not counted, not listed, not in the drop total: a run's drop count should
	-- mean "things that earned me money".
	if isCurrency(link) then return end
	count = count or 1
	local unit = M.ItemValue(link)
	local val = unit * count
	S.items = S.items + val
	S.itemsVendor = (S.itemsVendor or 0) + M.VendorValue(link) * count
	S.itemsAH = (S.itemsAH or 0) + M.AHValue(link) * count
	S.drops = S.drops + count
	local e = S.loot[link]
	if e then e[1] = e[1] + val; e[2] = e[2] + count
	else S.loot[link] = { val, count } end
end

-- "You loot 12 Gold, 34 Silver, 56 Copper" -- the money strings are localized, so
-- they are built from the game's own GOLD_AMOUNT/SILVER_AMOUNT globals rather than
-- hardcoding the English words.
local moneyPats
local function moneyPatterns()
	if moneyPats then return moneyPats end
	local function pat(fmt, mult)
		if not fmt then return nil end
		local p = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%d", "(%%d+)")
		return { p, mult }
	end
	moneyPats = {}
	local g = pat(GOLD_AMOUNT, 10000)
	local s = pat(SILVER_AMOUNT, 100)
	local c = pat(COPPER_AMOUNT, 1)
	if g then moneyPats[#moneyPats + 1] = g end
	if s then moneyPats[#moneyPats + 1] = s end
	if c then moneyPats[#moneyPats + 1] = c end
	return moneyPats
end

-- Only the loot that landed on YOU, built from the game's own message templates so
-- it works on a non-enUS client. A hardcoded "You receive loot:" also missed the
-- _MULTIPLE forms, which is every stack of more than one.
--   LOOT_ITEM_SELF          = "You receive loot: %s."
--   LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
--   (_PUSHED_ = crafted/quest items that go straight to the bags)
local selfLootPats
local function selfLootPatterns()
	if selfLootPats then return selfLootPats end
	selfLootPats = {}
	local function add(template, hasCount)
		if type(template) ~= "string" or template == "" then return end
		local p = template:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
		p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
		selfLootPats[#selfLootPats + 1] = { p, hasCount }
	end
	-- MULTIPLE first: its pattern is the plain one plus a count, so the plain form
	-- would happily match a stack line and swallow the "x3" into the link capture.
	add(LOOT_ITEM_SELF_MULTIPLE, true)
	add(LOOT_ITEM_PUSHED_SELF_MULTIPLE, true)
	add(LOOT_ITEM_SELF, false)
	add(LOOT_ITEM_PUSHED_SELF, false)
	return selfLootPats
end

-- link, count -- or nil when the line is somebody else's loot.
function M.ParseSelfLoot(msg)
	for _, e in ipairs(selfLootPatterns()) do
		if e[2] then
			local link, n = msg:match(e[1])
			if link then return link, tonumber(n) or 1 end
		else
			local link = msg:match(e[1])
			if link then return link, 1 end
		end
	end
	return nil
end

local function addCash(msg)
	if not msg then return end
	local total = 0
	for _, p in ipairs(moneyPatterns()) do
		local n = tonumber(msg:match(p[1]))
		if n then total = total + n * p[2] end
	end
	if total > 0 then S.cash = S.cash + total end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_LOOT")
ev:RegisterEvent("CHAT_MSG_MONEY")
ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:SetScript("OnEvent", function(_, event, ...)
	-- Nothing is counted while paused or stopped: a farm rate has to be about the
	-- time you were farming, or the number is a lie.
	if not S.running then
		if event == "ZONE_CHANGED_NEW_AREA" and S.elapsed == 0 then
			S.zone = (GetRealZoneText and GetRealZoneText()) or ""
		end
		return
	end
	if Okanvil.ModuleActive and not Okanvil:ModuleActive(ADDON) then return end

	if event == "CHAT_MSG_LOOT" then
		local msg = ...
		if not msg then return end
		local link, n = M.ParseSelfLoot(msg)
		if not link then return end
		addLoot(link, n)
		if M.onChange then M.onChange() end

	elseif event == "CHAT_MSG_MONEY" then
		addCash((...))
		if M.onChange then M.onChange() end

	elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
		-- 3.3.5a layout, which has no raid-flag fields:
		--   1 timestamp, 2 sub-event, 3 sourceGUID, 4 sourceName, 5 sourceFlags,
		--   6 destGUID, 7 destName, 8 destFlags
		-- This read destGUID from 5, which is sourceFlags -- a NUMBER. Every kill
		-- threw, and none was ever counted.
		if select(2, ...) == "UNIT_DIED" then
			if Okanvil.U.guidIsNPC(select(6, ...)) then S.kills = S.kills + 1 end
		end
	end
end)

-- ------------------------------------------------------------
-- Slash
-- ------------------------------------------------------------
SLASH_OKFARM1 = "/okfarm"
SlashCmdList["OKFARM"] = function(arg)
	arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if arg == "start" then M.Start()
	elseif arg == "stop" then M.Stop()
	elseif arg == "reset" then M.Reset()
	else
		if Okanvil.Farm_Toggle then Okanvil.Farm_Toggle() end
	end
end
