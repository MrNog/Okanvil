-- ============================================================
-- Okanvil -- Give loot (master loot picker).
-- Stands in for the Blizzard "Give loot to" dropdown (GroupLootDropDown, which the
-- stock loot frame and ElvUI open on OPEN_MASTER_LOOT_LIST): a small window at the
-- mouse with the raid in three columns, sorted by class, names in class colour.
-- Whoever the server will not let receive the item is grey. A click picks a name;
-- Give hands it over, so a slip of the mouse never gives an item away.
--
-- /okgive          open it on a fake raid (solo test, nothing is given)
-- /okgive on|off   use it instead of the dropdown, or go back to the dropdown
-- ============================================================

local Okanvil = Okanvil
local W = Okanvil.W
local G = {}
Okanvil.LootGive = G

local FLAT = "Interface\\Buttons\\WHITE8x8"
local COLS, CELL_W, CELL_H, GAP, PAD, ICON = 3, 104, 20, 2, 8, 30
local TOP = PAD + ICON + 8      -- where the names start, under the item
local BTN_H = 22
local CLASS_ORDER = { DEATHKNIGHT = 1, DRUID = 2, HUNTER = 3, MAGE = 4, PALADIN = 5,
	PRIEST = 6, ROGUE = 7, SHAMAN = 8, WARLOCK = 9, WARRIOR = 10 }

local function db()
	local d = Okanvil.db.lootgive
	if not d then
		d = { on = true }
		Okanvil.db.lootgive = d
	end
	return d
end

local function short(name) return (tostring(name or ""):gsub("%-.*$", "")) end

-- The fake raid for /okgive: 25 names, two of them out of reach.
local MOCK = {
	{ "Okanor", "PALADIN" }, { "Gatlock", "WARLOCK" }, { "Mijinho", "DEATHKNIGHT" },
	{ "Yahmom", "WARRIOR" }, { "Radnah", "ROGUE" }, { "Onetreeheals", "DRUID" },
	{ "Lecoque", "PRIEST" }, { "Shayla", "SHAMAN" }, { "Faerin", "MAGE" },
	{ "Kobee", "HUNTER" }, { "Tchilly", "DEATHKNIGHT" }, { "Zhong", "PALADIN" },
	{ "Brutarr", "WARRIOR" }, { "Velith", "MAGE" }, { "Moonsong", "DRUID", true },
	{ "Ravok", "HUNTER" }, { "Sylvae", "PRIEST" }, { "Grimtusk", "SHAMAN" },
	{ "Nyxie", "ROGUE" }, { "Dreadmor", "WARLOCK" }, { "Holyrat", "PALADIN" },
	{ "Cheddar", "MAGE" }, { "Gorrak", "WARRIOR", true }, { "Lunari", "DRUID" },
	{ "Skarn", "DEATHKNIGHT" },
}
local MOCK_ITEM = 50421   -- Sindragosa's Cruel Claw (25N), from RaidLoot-Data

local function sortList(list)
	table.sort(list, function(a, b)
		local oa, ob = CLASS_ORDER[a.class or ""] or 99, CLASS_ORDER[b.class or ""] or 99
		if oa ~= ob then return oa < ob end
		return a.name < b.name
	end)
	return list
end

-- The candidate index the server gave this name, or nil: it is what GiveMasterLoot
-- takes, and it is read again at the click, since the list can change while open.
local function candidateIndex(name)
	local key = short(name):lower()
	for i = 1, 40 do
		local n = GetMasterLootCandidate(i)
		if n and short(n):lower() == key then return i end
	end
	return nil
end

-- Everyone in the group, with whether the server lets them receive this item.
local function realList()
	local list, seen = {}, {}
	local function add(name)
		if not name or name == "" then return end
		local key = short(name):lower()
		if seen[key] then return end
		seen[key] = true
		local _, class = UnitClass(name)
		list[#list + 1] = { name = short(name), class = class, cand = candidateIndex(name) ~= nil }
	end
	if GetNumRaidMembers() > 0 then
		for i = 1, GetNumRaidMembers() do add((GetRaidRosterInfo(i))) end
	else
		add(UnitName("player"))
		for i = 1, GetNumPartyMembers() do add(UnitName("party" .. i)) end
	end
	-- a candidate the roster did not list still gets a cell
	for i = 1, 40 do add(GetMasterLootCandidate(i)) end
	return sortList(list)
end

local win

local function cell(i)
	local c = win.cells[i]
	if c then return c end
	c = CreateFrame("Button", nil, win)
	c:SetSize(CELL_W, CELL_H)
	c.bg = c:CreateTexture(nil, "BACKGROUND")
	c.bg:SetAllPoints(); c.bg:SetTexture(FLAT)
	local hl = c:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(); hl:SetTexture(FLAT); hl:SetVertexColor(1, 1, 1, 0.07)
	c.txt = W.Text(c, "", 11)
	c.txt:SetPoint("LEFT", 6, 0); c.txt:SetPoint("RIGHT", -4, 0)
	c.txt:SetJustifyH("LEFT")
	if c.txt.SetWordWrap then c.txt:SetWordWrap(false) end
	c:SetScript("OnClick", function(self)
		if not (self.p and self.p.cand) then return end
		G.pick = (G.pick ~= self.p) and self.p or nil
		G.Paint()
	end)
	win.cells[i] = c
	return c
end

local function giveNow()
	local p = G.pick
	if not p then return end
	if G.test then
		Okanvil:Print(("|cffe0b860[TEST]|r would give %s to |cffffd200%s|r -- |cff8a8d93nothing was given.|r")
			:format(G.itemText or "the item", p.name))
		win:Hide()
		return
	end
	local idx = candidateIndex(p.name)
	if not (idx and G.slot) then
		Okanvil:Print("|cffff5555Not given:|r " .. p.name
			.. " cannot receive it right now (out of range, offline or not eligible).")
		G.Refresh()
		return
	end
	GiveMasterLoot(G.slot, idx)
	win:Hide()
end

local function build()
	if win then return win end
	local f = CreateFrame("Frame", "Okanvil_LootGive", UIParent)
	-- over the loot frame and the mini roll, like the dropdown it stands in for
	f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
	f:SetClampedToScreen(true); f:EnableMouse(true)
	f:SetWidth(PAD * 2 + COLS * CELL_W + (COLS - 1) * GAP)
	f:SetHeight(120)
	Okanvil:Skin(f, "panel")
	local br, bg, bb = f:GetBackdropColor()
	if br then f:SetBackdropColor(br, bg, bb, 0.97) end
	tinsert(UISpecialFrames, "Okanvil_LootGive")   -- Esc closes it
	-- the forge art of the mini roll, as faint: the names sit on solid cells
	W.ForgeArt(f, 0.22, W.LOOT_ART)

	f.slot = W.FramedIcon(f, nil, ICON, true)
	f.slot:SetPoint("TOPLEFT", PAD, -PAD)
	f.slot:EnableMouse(true)
	f.slot:SetScript("OnEnter", function(self)
		if not G.link then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(G.link)
		GameTooltip:Show()
	end)
	f.slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

	f.close = W.CloseButton(f)
	f.close:SetPoint("TOPRIGHT", -PAD + 2, -PAD + 1)
	f.close:SetScript("OnClick", function() f:Hide() end)

	f.item = W.Text(f, "", 12)
	f.item:SetPoint("LEFT", f.slot, "RIGHT", 8, 0)
	f.item:SetPoint("RIGHT", f.close, "LEFT", -6, 0)
	f.item:SetJustifyH("LEFT")
	if f.item.SetWordWrap then f.item:SetWordWrap(false) end

	f.cells = {}

	f.cancel = W.Button(f, "Cancel")
	f.cancel:SetSize(64, BTN_H)
	f.cancel:SetScript("OnClick", function() G.pick = nil; G.Paint() end)
	f.give = W.Button(f, "Give", "primary"):SetMain(true)
	f.give:SetHeight(BTN_H)
	f.give:SetScript("OnClick", giveNow)

	f:SetScript("OnHide", function() G.pick = nil; G.test = nil end)
	f:Hide()
	win = f
	return f
end

function G.Paint()
	if not win then return end
	local list = G.list or {}
	-- the picked name may have left the list (UPDATE_MASTER_LOOT_LIST)
	local still = false
	for _, p in ipairs(list) do if p == G.pick and p.cand then still = true end end
	if not still then G.pick = nil end

	-- each column is as wide as its longest name, so no name is ever cut
	local colW = {}
	for col = 0, COLS - 1 do colW[col] = CELL_W end
	for i, p in ipairs(list) do
		local c = cell(i)
		c.txt:SetText(p.name)
		local col = (i - 1) % COLS
		colW[col] = math.max(colW[col], math.ceil(c.txt:GetStringWidth()) + 10)
	end
	local colX, width = {}, PAD
	for col = 0, COLS - 1 do
		colX[col] = width
		width = width + colW[col] + GAP
	end
	win:SetWidth(width - GAP + PAD)

	for i, p in ipairs(list) do
		local c = cell(i)
		local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", colX[col], -(TOP + row * (CELL_H + GAP)))
		c:SetWidth(colW[col])
		c.p = p
		if p.cand then
			local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class or ""]
			if cc then c.txt:SetTextColor(cc.r, cc.g, cc.b) else c.txt:SetTextColor(1, 0.82, 0) end
			c:Enable()
		else
			c.txt:SetTextColor(0.29, 0.30, 0.32)
			c:Disable()
		end
		if G.pick == p then c.bg:SetVertexColor(0.75, 0.58, 0.23, 0.45)
		else c.bg:SetVertexColor(0.106, 0.11, 0.125, 1) end
		c:Show()
	end
	for i = #list + 1, #win.cells do win.cells[i]:Hide() end

	local rows = math.max(1, math.ceil(#list / COLS))
	local y = TOP + rows * (CELL_H + GAP) - GAP + PAD
	if G.pick then
		local inner = win:GetWidth() - PAD * 2
		win.give:ClearAllPoints(); win.give:SetPoint("TOPLEFT", PAD, -y)
		win.give:SetWidth(inner - 64 - 4)
		win.give.text:SetText("Give to " .. G.pick.name)
		win.cancel:ClearAllPoints(); win.cancel:SetPoint("LEFT", win.give, "RIGHT", 4, 0)
		win.give:Show(); win.cancel:Show()
		y = y + BTN_H + PAD
	else
		win.give:Hide(); win.cancel:Hide()
	end
	win:SetHeight(y)
end

local function showItem(tex, text, link)
	G.link, G.itemText = link, text
	win.slot.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
	win.item:SetText(text or "")
end

local function openAtCursor()
	local x, y = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	win:ClearAllPoints()
	win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 12, y / s + 12)
	win:Show()
end

-- Re-read the loot slot and the candidates (a name in range a moment ago may not be).
function G.Refresh()
	if not (win and win:IsShown()) or G.test then return end
	G.list = realList()
	G.Paint()
end

function G.OpenReal()
	build()
	local slot = LootFrame and LootFrame.selectedSlot
	if not slot then return end
	local tex, name, _, quality = GetLootSlotInfo(slot)
	if not name then return end
	G.test, G.slot, G.pick = nil, slot, nil
	local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 4]
	showItem(tex, (q and q.hex or "|cffa335ee") .. name .. "|r", GetLootSlotLink(slot))
	G.list = realList()
	G.Paint()
	openAtCursor()
end

function G.OpenTest()
	build()
	G.test, G.slot, G.pick = true, nil, nil
	Okanvil:WarmItem(MOCK_ITEM)
	local name, link, quality, _, _, _, _, _, _, tex = GetItemInfo(MOCK_ITEM)
	local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 4]
	showItem(tex or (GetItemIcon and GetItemIcon(MOCK_ITEM)),
		(q and q.hex or "|cffa335ee") .. (name or "Sindragosa's Cruel Claw") .. "|r", link)
	local list = {}
	for _, m in ipairs(MOCK) do list[#list + 1] = { name = m[1], class = m[2], cand = not m[3] } end
	G.list = sortList(list)
	G.Paint()
	openAtCursor()
end

-- The stock loot frame and ElvUI both open GroupLootDropDown as the first
-- dropdown level. ElvUI calls its own local copy of ToggleDropDownMenu, so a
-- hook on the global never sees it; the list frame showing is what both share.
-- Close it as it opens and show this window in its place.
DropDownList1:HookScript("OnShow", function()
	local menu = UIDROPDOWNMENU_OPEN_MENU
	if not (GroupLootDropDown and (menu == GroupLootDropDown or menu == "GroupLootDropDown")) then return end
	if not db().on then return end
	CloseDropDownMenus()
	local ok, err = pcall(G.OpenReal)
	if not ok and Okanvil.Err then Okanvil:Err("LootGive.OpenReal", err) end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("LOOT_CLOSED")
ev:RegisterEvent("LOOT_SLOT_CLEARED")
ev:RegisterEvent("UPDATE_MASTER_LOOT_LIST")
ev:SetScript("OnEvent", function(_, event, slot)
	if not (win and win:IsShown()) or G.test then return end
	if event == "LOOT_CLOSED" or (event == "LOOT_SLOT_CLEARED" and slot == G.slot) then
		win:Hide()
	elseif event == "UPDATE_MASTER_LOOT_LIST" then
		G.Refresh()
	end
end)

SLASH_OKGIVE1 = "/okgive"
SlashCmdList["OKGIVE"] = function(msg)
	local arg = (msg or ""):lower():match("^%s*(%S*)")
	if arg == "on" or arg == "off" then
		db().on = (arg == "on")
		Okanvil:Print("Give loot window is " .. (db().on and "|cffffd200ON|r" or "|cffff5555OFF|r -- the dropdown is back") .. ".")
		return
	end
	G.OpenTest()
end
