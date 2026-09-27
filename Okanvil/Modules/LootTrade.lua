-- ============================================================
-- Okanvil -- Loot owed by trade.
--
-- An award that master loot could not hand over (the corpse was closed, the
-- winner out of range) leaves the item in the master looter's bags, owed to
-- someone. This module remembers those items and gets them to their owner:
--
--   * a gold square on the item in your bags, and "Okanvil: trade to X" on
--     its tooltip, so it is found at a glance among forty other purples;
--   * opening a trade with the winner puts the item in the window by itself,
--     so the hand-over is one click on Trade.
--
-- The list is per character (it is about THIS toon's bags) and forgets an
-- item once it has left the bags in a completed trade, or after the two
-- hours a looted item can be traded for at all.
-- ============================================================

local Okanvil = Okanvil
local T = {}
Okanvil.Trade = T

local TRADE_WINDOW = 2 * 3600

local function short(n) return n and (n:gsub("%-.*$", "")) or n end

local function owed()
	local cdb = Okanvil.cdb
	if not cdb then return {} end
	cdb.lootOwed = cdb.lootOwed or {}
	local now = time()
	for i = #cdb.lootOwed, 1, -1 do
		if (now - (cdb.lootOwed[i].at or 0)) > TRADE_WINDOW then table.remove(cdb.lootOwed, i) end
	end
	return cdb.lootOwed
end

local function idOfLink(link)
	return link and tonumber(link:match("item:(%d+)")) or nil
end

-- Every bag slot holding this item id: { {bag, slot}, ... }
local function slotsOf(id)
	local out = {}
	for bag = 0, 4 do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			if idOfLink(GetContainerItemLink(bag, slot)) == id then out[#out + 1] = { bag, slot } end
		end
	end
	return out
end

local function countOf(id) return #slotsOf(id) end

-- ---- Remember / forget --------------------------------------------------

-- An award that has to go by trade. `test` marks the council test's, so ending
-- the test takes them away again.
function T.Add(id, winner, link, test)
	id = tonumber(id)
	if not (id and winner and winner ~= "") then return end
	local me = UnitName("player")
	-- Awarded to yourself it is already yours: nothing to trade. The council
	-- test is the exception -- solo, you are the only possible winner.
	if short(winner) == me and not test then return end
	local list = owed()
	list[#list + 1] = { id = id, winner = short(winner), link = link, at = time(), test = test or nil }
	T.Refresh()
end

function T.ClearTest()
	local list = owed()
	for i = #list, 1, -1 do
		if list[i].test then table.remove(list, i) end
	end
	T.Refresh()
end

function T.Owed() return owed() end

-- Who this item in your bags is owed to, or nil.
local function winnerOf(id)
	for _, e in ipairs(owed()) do
		if e.id == id then return e.winner end
	end
	return nil
end

-- ---- The square in the bags ---------------------------------------------
-- Bag addons each draw their own buttons, so the button for (bag, slot) is
-- found per addon: ElvUI names them, AdiBags keeps .bag/.slot on a pooled
-- button. Blizzard's bags and Bagnon follow the item-button rule that the
-- button's ID is the slot and its parent's ID the bag (Bagnon also borrows
-- Blizzard's buttons, which is why both are checked the same way).
local function templated(b, bag, slot)
	if not (b and b:IsVisible() and b:GetID() == slot) then return false end
	local p = b:GetParent()
	if not (p and p:GetID() == bag) then return false end
	-- Bagnon can show another character's bags from its cache
	if b.IsCached and b:IsCached() then return false end
	return true
end

local function buttonsFor(bag, slot)
	local out = {}
	local elv = _G["ElvUI_ContainerFrameBag" .. bag .. "Slot" .. slot]
	if elv and elv:IsVisible() then out[#out + 1] = elv end

	local n = 1
	while true do
		local b = _G["AdiBagsItemButton" .. n]
		if not b then break end
		if b.bag == bag and b.slot == slot and b:IsVisible() then out[#out + 1] = b end
		n = n + 1
	end

	n = 1
	while true do
		local b = _G["BagnonItemSlot" .. n]
		if not b then break end
		if templated(b, bag, slot) then out[#out + 1] = b end
		n = n + 1
	end

	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		for j = 1, MAX_CONTAINER_ITEMS or 36 do
			local b = _G["ContainerFrame" .. i .. "Item" .. j]
			if not b then break end
			if templated(b, bag, slot) then out[#out + 1] = b end
		end
	end
	return out
end

local marks = {}

local function markAt(i)
	local m = marks[i]
	if m then return m end
	m = CreateFrame("Frame", nil, UIParent)
	m:SetFrameStrata("TOOLTIP")
	local ac = Okanvil.Colors and Okanvil.Colors.accent or { 0.75, 0.58, 0.23 }
	local function edge(p1, p2, w, h)
		local t = m:CreateTexture(nil, "OVERLAY")
		t:SetTexture("Interface\\Buttons\\WHITE8x8")
		t:SetVertexColor(1, 0.82, 0, 1)
		t:SetPoint(p1); t:SetPoint(p2)
		if w then t:SetWidth(w) else t:SetHeight(h) end
	end
	edge("TOPLEFT", "TOPRIGHT", nil, 2)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
	edge("TOPLEFT", "BOTTOMLEFT", 2, nil)
	edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
	m.glow = m:CreateTexture(nil, "ARTWORK")
	m.glow:SetTexture("Interface\\Buttons\\WHITE8x8")
	m.glow:SetVertexColor(ac[1], ac[2], ac[3], 0.18)
	m.glow:SetAllPoints()
	marks[i] = m
	return m
end

function T.Refresh()
	local used = 0
	local list = owed()
	if #list > 0 then
		local seen = {}
		for _, e in ipairs(list) do
			if not seen[e.id] then
				seen[e.id] = true
				for _, bs in ipairs(slotsOf(e.id)) do
					for _, b in ipairs(buttonsFor(bs[1], bs[2])) do
						used = used + 1
						local m = markAt(used)
						m:ClearAllPoints()
						m:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
						m:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
						m:Show()
					end
				end
			end
		end
	end
	for i = used + 1, #marks do marks[i]:Hide() end
end

-- Bags open, close, re-sort and scroll without telling anyone, so the squares
-- follow them on a short ticker -- only while something is owed.
do
	local tick = CreateFrame("Frame")
	local acc = 0
	tick:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.3 then return end
		acc = 0
		local cdb = Okanvil.cdb
		if cdb and cdb.lootOwed and #cdb.lootOwed > 0 then
			T.Refresh()
		elseif marks[1] and marks[1]:IsShown() then
			T.Refresh()
		end
	end)
end

-- "Okanvil: trade to X" on the item's tooltip.
hooksecurefunc(GameTooltip, "SetBagItem", function(tip, bag, slot)
	local id = idOfLink(GetContainerItemLink(bag, slot))
	local who = id and winnerOf(id)
	if not who then return end
	-- the winner in their class colour, like everywhere else in the addon
	local L = Okanvil.Loot
	local class = L and L.ClassOf and L.ClassOf(who)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	local name = c and ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, who) or who
	tip:AddLine("|cffe0b860Okanvil:|r |cffdcdddetrade to|r " .. name)
	tip:Show()
end)

-- ---- The trade window ---------------------------------------------------
-- The trade partner is unit "NPC" while the trade window is open.
local partner, before = nil, {}

local function freeTradeSlot()
	for i = 1, 6 do
		if not GetTradePlayerItemLink(i) then return i end
	end
	return nil
end

local function fillTrade()
	if not partner then return end
	local placed = {}
	for _, e in ipairs(owed()) do
		if e.winner:lower() == partner:lower() then
			local slots = slotsOf(e.id)
			local k = (placed[e.id] or 0) + 1
			local bs = slots[k]
			local ts = freeTradeSlot()
			if bs and ts then
				placed[e.id] = k
				ClearCursor()
				PickupContainerItem(bs[1], bs[2])
				ClickTradeButton(ts)
				Okanvil:Print("|cffe0b860Trade:|r put " .. (e.link or ("item " .. e.id))
					.. " in for " .. e.winner .. " -- press Trade.")
			end
		end
	end
end

-- Equipping an owed item is keeping it: it comes off the list for good, so
-- taking it off again later does not bring the square back.
local function forgetEquipped()
	local list = owed()
	if #list == 0 then return end
	local worn = {}
	for slot = 1, 19 do
		local id = GetInventoryItemID("player", slot)
		if id then worn[id] = true end
	end
	local changed = false
	for i = #list, 1, -1 do
		if worn[list[i].id] then table.remove(list, i); changed = true end
	end
	if changed then T.Refresh() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("TRADE_SHOW")
ev:RegisterEvent("TRADE_CLOSED")
ev:RegisterEvent("UI_INFO_MESSAGE")
ev:SetScript("OnEvent", function(_, event, msg)
	if event == "PLAYER_EQUIPMENT_CHANGED" then
		forgetEquipped()
	elseif event == "TRADE_SHOW" then
		partner = short(UnitName("NPC"))
		before = {}
		for _, e in ipairs(owed()) do before[e.id] = countOf(e.id) end
		-- A beat later: the window's slots are not ready on the event itself.
		local C = Okanvil.Comms
		if C and C.After then C.After(0.3, fillTrade) else fillTrade() end
	elseif event == "TRADE_CLOSED" then
		partner = nil
	elseif event == "UI_INFO_MESSAGE" and msg == ERR_TRADE_COMPLETE then
		-- Whatever left the bags in this trade has been delivered: one entry off
		-- the list per copy that went.
		local list = owed()
		local who = partner
		local C = Okanvil.Comms
		local function settle()
			for id, n in pairs(before) do
				local gone = n - countOf(id)
				for i = #list, 1, -1 do
					if gone <= 0 then break end
					local e = list[i]
					if e.id == id and (not who or e.winner:lower() == who:lower()) then
						table.remove(list, i)
						gone = gone - 1
					end
				end
			end
			before = {}
			T.Refresh()
		end
		-- the bags update just after the message
		if C and C.After then C.After(0.5, settle) else settle() end
	end
end)
