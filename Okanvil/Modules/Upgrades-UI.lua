-- ============================================================
-- Okanvil -- Upgrades page (RAID > Upgrades).
-- Pick a raid and difficulty; every boss lists the drops that are an upgrade
-- for the spec you are in. Bosses killed on your lockout stay in place, greyed.
-- ============================================================

local Okanvil = Okanvil
local W = Okanvil.W
local C = Okanvil.Colors
local U = Okanvil.Upgrades
local ADDON = U.ADDON

local FLAT = "Interface\\Buttons\\WHITE8x8"
local BOSS_H, ITEM_H, ICON, SMALL = 36, 42, 30, 20
-- the page's controls read one size up and stand taller (as on PuG)
local CTRL_FONT, CTRL_H, BAR_H = 13, 24, 44
local function big(b)
	local t = b and (b.text or b.textFS)
	if t then t._okSize = CTRL_FONT; t:SetFont(Okanvil:Font(), CTRL_FONT) end
	return b
end
local RAID_ORDER = { "icc", "rs", "toc", "ulduar", "naxx", "voa", "os", "eoe", "ony" }

local function u3(c) return c[1], c[2], c[3] end

local function raidName(key)
	for _, r in ipairs(OkanvilRaids or {}) do
		if r.key == key then return r.name end
	end
	return key
end

local function db()
	Okanvil.db.upgrades = Okanvil.db.upgrades or {}
	return Okanvil.db.upgrades
end

function Okanvil:BuildUpgrades(host)
	local state = { open = {}, allOpen = true, view = db().view == "bis" and "bis" or "me" }
	local viewTabs, specFS = {}
	-- the spec in your class colour
	local function specText()
		local spec = U.Spec()
		local c = spec and RAID_CLASS_COLORS and RAID_CLASS_COLORS[spec.class]
		local hex = c and ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) or "|cffe0b860"
		return "|cff8a8d93Spec|r " .. (spec and (hex .. spec.label .. "|r") or "|cff8a8d93?|r")
	end
	local modeTabs = {}
	local refresh

	-- what the page shows: the raid you are in, else the last one picked
	local function pickDefault()
		local raid, mode = U.Here()
		if raid then state.raid, state.mode = raid, mode; return end
		state.raid = db().raid or "icc"
		if U.RaidOut and not U.RaidOut(state.raid) then state.raid = "icc" end
		state.mode = db().mode or "25n"
	end
	pickDefault()

	local dash = W.Dashboard(host, {
		title = "Upgrades",
		settingsTab = "general",
		subtitle = "Raid drops that beat your gear, for the spec you are in",
		icon = Okanvil.ICONS.upgrades,
		drawerWidth = 0,
		footerHeight = 0,
		-- the spec you are in, at the right of the header; the two views (the
		-- drops for you, any spec's BiS list) are side tabs on the window's edge
		headerBuild = function(header)
			specFS = W.Text(header, "", nil, "dim")
			specFS:SetPoint("RIGHT", header, "RIGHT", -10, 0)
		end,
	})

	for i, v in ipairs({ { "me", "For me", "Interface\\Icons\\Spell_Holy_HolyBolt" },
			{ "bis", "BiS lists", "Interface\\Icons\\INV_Misc_Note_02" } }) do
		local b = W.SideTab(host, v[2], v[3], function()
			state.view = v[1]; db().view = v[1]; refresh()
		end)
		b:Place(i - 1)
		viewTabs[v[1]] = b
	end
	if dash.settingsTab then dash.settingsTab:Place(2, 12) end

	-- raid and difficulty in a bar of their own at the top of the page: beside
	-- the title they were small and crowded the subtitle
	local bar = CreateFrame("Frame", nil, dash.main)
	bar:SetPoint("TOPLEFT", 0, 0); bar:SetPoint("TOPRIGHT", 0, 0); bar:SetHeight(BAR_H)
	W.Hairline(bar, "BOTTOM", 0)
	do
		local header, anchor = bar, bar
		local dd = W.DropDown(header,
			function()
				local out = {}
				for _, k in ipairs(RAID_ORDER) do
					if OkanvilRaidLoot and OkanvilRaidLoot[k] and (not U.RaidOut or U.RaidOut(k)) then  -- not out yet: hidden
						out[#out + 1] = { text = raidName(k), value = k }
					end
				end
				return out
			end,
			function() return raidName(state.raid) end,
			function(v)
				state.raid = v
				local modes, keep = U.ModesOf(v), nil
				for _, m in ipairs(modes) do if m == state.mode then keep = m end end
				-- a raid without your difficulty opens on 25, else its first
				local has25
				for _, m in ipairs(modes) do if m == "25n" then has25 = m end end
				state.mode = keep or has25 or modes[1]
				db().raid, db().mode = state.raid, state.mode
				state.open = {}
				refresh()
			end)
		dd:SetSize(250, CTRL_H); dd:SetPoint("LEFT", anchor, "LEFT", Okanvil.UI.PAD_X, 0)
		big(dd)
		state.dd = dd
		local prev = dd
		for _, m in ipairs(U.MODE_ORDER) do
			local b = big(W.Button(header, U.MODE_LABEL[m], "tab"))
			b:SetSize(m:find("h") and 84 or 58, CTRL_H)
			b:SetPoint("LEFT", prev, "RIGHT", prev == dd and 14 or 4, 0)
			b:SetScript("OnClick", function()
				state.mode = m; db().mode = m; refresh()
			end)
			modeTabs[m] = b
			prev = b
		end
		local openAll = big(W.Button(header, "Close all"))
		openAll:SetSize(96, CTRL_H); openAll:SetPoint("RIGHT", header, "RIGHT", -Okanvil.UI.PAD_X, 0)
		openAll:SetScript("OnClick", function()
			state.allOpen = not state.allOpen
			state.open = {}
			openAll.text:SetText(state.allOpen and "Close all" or "Open all")
			refresh()
		end)
		-- search: matching bosses open, the rest fold away. Read as it is typed;
		-- Enter only lets go of the keyboard.
		local search = W.EditBox(header, function() end)
		search:SetHeight(CTRL_H); search:SetWidth(200)
		search:SetPoint("RIGHT", openAll, "LEFT", -8, 0)
		search.edit:SetFont(Okanvil:Font(), 13)
		local ph = W.Text(search, "Search item or slot", "label", "dim"); ph:SetPoint("LEFT", 8, 0)
		search.edit:HookScript("OnTextChanged", function(e)
			local t = e:GetText() or ""
			if t == "" then ph:Show() else ph:Hide() end
			state.query = t:lower():gsub("^%s+", ""):gsub("%s+$", "")
			refresh()
		end)
		search.edit:HookScript("OnEditFocusGained", function() ph:Hide() end)
	end

	local body = CreateFrame("Frame", nil, dash.main)
	body:SetPoint("TOPLEFT", 0, -BAR_H); body:SetPoint("BOTTOMRIGHT", 0, 0)
	local X = Okanvil.UI.PAD_X
	local p, relayout, sf = Okanvil.UI.DashScroll(body, X)

	local status = W.Text(p, "", "note", "dim")
	status:SetJustifyH("LEFT")

	-- ---- row pools ----
	local bossRows, itemRows = {}, {}

	local function newBossRow()
		local r = CreateFrame("Button", nil, p)
		r:SetHeight(BOSS_H)
		local line = r:CreateTexture(nil, "ARTWORK")
		line:SetTexture(FLAT); line:SetVertexColor(u3(C.border)); line:SetHeight(1)
		line:SetPoint("TOPLEFT", 0, 0); line:SetPoint("TOPRIGHT", 0, 0)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetTexture(FLAT); hl:SetAllPoints(); hl:SetVertexColor(1, 1, 1, 0.03)
		r.caret = W.Text(r, "", "label", "dim"); r.caret:SetPoint("LEFT", 4, -1)
		r.tag = W.Text(r, "", "note", "dim"); r.tag:SetPoint("RIGHT", -4, -1); r.tag:SetWidth(78)
		r.tag:SetJustifyH("RIGHT")
		r.name = W.Text(r, "", "head"); r.name:SetPoint("LEFT", 20, -1)
		r.name:SetPoint("RIGHT", r.tag, "LEFT", -8, 0); r.name:SetJustifyH("LEFT")
		r:SetScript("OnClick", function(self)
			if self.onClick then self.onClick() end
		end)
		return r
	end

	local function newItemRow()
		local r = CreateFrame("Button", nil, p)
		r:SetHeight(ITEM_H)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetTexture(FLAT); hl:SetAllPoints(); hl:SetVertexColor(1, 1, 1, 0.05)
		r.slot = W.FramedIcon(r, nil, ICON + 6, true)
		r.slot:SetPoint("LEFT", 19, 0)
		r.icon = r.slot.icon
		-- a stripe in the verdict's colour
		r.bar = r:CreateTexture(nil, "ARTWORK")
		r.bar:SetTexture(FLAT); r.bar:SetWidth(3)
		r.bar:SetPoint("TOPLEFT", 10, -4); r.bar:SetPoint("BOTTOMLEFT", 10, 4)
		r.val = W.Text(r, "", "head"); r.val:SetPoint("RIGHT", -6, 0); r.val:SetWidth(78)
		r.val:SetJustifyH("RIGHT")
		-- left half: the drop; right half: what it replaces
		r.name = W.Text(r, "", "head"); r.name:SetPoint("TOPLEFT", r.slot, "TOPRIGHT", 8, -2)
		r.name:SetJustifyH("LEFT")
		r.sub = W.Text(r, "", "note", "dim"); r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
		r.sub:SetJustifyH("LEFT")
		r.vsK = W.Text(r, "replaces", "note", "dim")
		r.vsIcon = r:CreateTexture(nil, "ARTWORK"); r.vsIcon:SetSize(SMALL, SMALL)
		r.vsIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.vsIcon:SetPoint("LEFT", r.vsK, "RIGHT", 6, 0)
		r.vs = W.Text(r, "", "label"); r.vs:SetPoint("LEFT", r.vsIcon, "RIGHT", 6, 0)
		r.vs:SetPoint("RIGHT", r.val, "LEFT", -10, 0); r.vs:SetJustifyH("LEFT")
		for _, fs in ipairs({ r.name, r.sub, r.vs }) do
			if fs.SetWordWrap then fs:SetWordWrap(false) end
		end
		r:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self.link)
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		r:SetScript("OnClick", function(self)
			if IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link)
			elseif IsModifiedClick("DRESSUP") then DressUpItemLink(self.link) end
		end)
		return r
	end

	local slowStop = false
	local function timedRefresh()
		if not host:IsVisible() or slowStop then return end
		local t0 = debugprofilestop and debugprofilestop()
		U.judged, U.judgeMs = 0, 0
		refresh()
		if not t0 then return end
		local ms = debugprofilestop() - t0
		Okanvil:Trace("UPGRADES", ("refresh %.0fms, judged %d in %.0fms, more %s")
			:format(ms, U.judged or 0, U.judgeMs or 0, tostring(U.more)))
		if ms > 250 then
			slowStop = true
			Okanvil:Trace("UPGRADES", "refresh too slow: automatic repaints stopped")
			status:SetText("|cffff6060Paused: this page was too slow. Reopen Okanvil to try again.|r")
		end
	end

	-- ---- BiS lists view: any class, spec and phase; each slot's top 6 as icons,
	-- two columns of slots so the whole list fits without a scroll ----
	local bis = CreateFrame("Frame", nil, dash.main)
	bis:SetAllPoints(dash.main)
	bis:Hide()
	local BIS_ICON, BIS_GAP, BIS_ROW, SLOT_W, ENH_W, ENH = 42, 6, 58, 70, 50, 16
	local RANK_HEX = { "ff4040", "bf66ff", "ff9926", "4d99ff", "59e659", "b3b3b3" }
	local mySpec = U.Spec()
	state.bClass = db().bisClass or (mySpec and U.CLASS_BIS[mySpec.class]) or "Warrior"
	state.bList = db().bisList or (mySpec and mySpec.list)
	state.bPhase = db().bisPhase or U.Phase()

	-- "Death knight" -> its class colour, for the dropdowns
	local TOKEN = {}
	for token, name in pairs(U.CLASS_BIS) do TOKEN[name] = token end
	local function tint(cls, text)
		local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[TOKEN[cls] or ""]
		if not c then return text end
		return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) .. text .. "|r"
	end
	local function specIcon(cls, list)
		local icons = OkanvilBisIcons and OkanvilBisIcons[cls]
		local tex = icons and (icons[list] or icons.classIcon)
		return tex and ("|T" .. tex .. ":16|t ") or ""
	end

	local function listsOf(cls)
		local out = {}
		for list in pairs((OkanvilBis or {})[cls] or {}) do out[#out + 1] = list end
		table.sort(out)
		return out
	end
	local function fixList()
		local lists = listsOf(state.bClass)
		for _, l in ipairs(lists) do if l == state.bList then return end end
		state.bList = lists[1]
	end
	fixList()

	local bbar = CreateFrame("Frame", nil, bis)
	bbar:SetPoint("TOPLEFT", 0, 0); bbar:SetPoint("TOPRIGHT", 0, 0); bbar:SetHeight(BAR_H)
	W.Hairline(bbar, "BOTTOM", 0)
	local cdd = W.DropDown(bbar,
		function()
			local out = {}
			for cls in pairs(OkanvilBis or {}) do out[#out + 1] = { text = tint(cls, cls), value = cls, key = cls } end
			table.sort(out, function(a, b) return a.key < b.key end)
			return out
		end,
		function() return tint(state.bClass, state.bClass) end,
		function(v) state.bClass = v; fixList(); db().bisClass, db().bisList = v, state.bList; refresh() end)
	cdd:SetSize(170, CTRL_H); cdd:SetPoint("LEFT", bbar, "LEFT", Okanvil.UI.PAD_X, 0); big(cdd)
	local sdd = W.DropDown(bbar,
		function()
			local out = {}
			for _, l in ipairs(listsOf(state.bClass)) do
				out[#out + 1] = { text = specIcon(state.bClass, l) .. U.SpecText(state.bClass, l), value = l }
			end
			return out
		end,
		function() return state.bList and (specIcon(state.bClass, state.bList) .. U.SpecText(state.bClass, state.bList)) or "" end,
		function(v) state.bList = v; db().bisList = v; refresh() end)
	sdd:SetSize(190, CTRL_H); sdd:SetPoint("LEFT", cdd, "RIGHT", 8, 0); big(sdd)
	local phaseTabs, prevP = {}, sdd
	for _, ph in ipairs(OkanvilBisPhases or {}) do
		local b = big(W.Button(bbar, ph, "tab"))
		b:SetSize(52, CTRL_H)
		b:SetPoint("LEFT", prevP, "RIGHT", prevP == sdd and 14 or 2, 0)
		b:SetScript("OnClick", function() state.bPhase = ph; db().bisPhase = ph; refresh() end)
		phaseTabs[ph] = b
		prevP = b
	end
	-- back to the spec you are in, today's phase
	local mine = W.Button(bbar, "My spec"):SetMain(true)
	mine:SetSize(96, 24); mine:SetPoint("RIGHT", bbar, "RIGHT", -Okanvil.UI.PAD_X, 0)
	mine:SetScript("OnClick", function()
		local sp = U.Spec()
		if sp then state.bClass, state.bList = U.CLASS_BIS[sp.class] or state.bClass, sp.list end
		state.bPhase = U.Phase()
		fixList()
		db().bisClass, db().bisList, db().bisPhase = state.bClass, state.bList, state.bPhase
		refresh()
	end)

	local grid = CreateFrame("Frame", nil, bis)
	grid:SetPoint("TOPLEFT", 0, -BAR_H - 10); grid:SetPoint("BOTTOMRIGHT", 0, 0)
	local slotTexts, cells, heads = {}, {}, {}
	local horde = UnitFactionGroup("player") == "Horde"

	local function cell(i)
		if cells[i] then return cells[i] end
		local b = CreateFrame("Button", nil, grid)
		b:SetSize(BIS_ICON, BIS_ICON)
		-- the kit's octagon frame (grey; gold when you have the item)
		W.DressFramedIcon(b, nil, b:GetWidth())
		W.SetFramedIconGold(b, false)
		-- you have it: a check mark in the corner
		-- on its own frame, so it draws above the octagon frame
		local top = CreateFrame("Frame", nil, b)
		top:SetAllPoints(b); top:SetFrameLevel(b:GetFrameLevel() + 2)
		b.own = top:CreateTexture(nil, "OVERLAY")
		b.own:SetSize(22, 22); b.own:SetPoint("BOTTOMRIGHT", 3, -3)
		b.own:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
		local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
		hl:SetTexture(FLAT); hl:SetVertexColor(1, 1, 1, 0.15)
		b:SetScript("OnEnter", function(s)
			if not s.id then return end
			GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink("item:" .. s.id)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("OnClick", function(s)
			local _, link = GetItemInfo(s.id or 0)
			if not link then return end
			if IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(link)
			elseif IsModifiedClick("DRESSUP") then DressUpItemLink(link) end
		end)
		cells[i] = b
		return b
	end
	-- the BiS piece's enchant and gems, small, two by two in the list's order
	local enhs = {}
	local function enhIcon(i)
		if enhs[i] then return enhs[i] end
		local b = CreateFrame("Button", nil, grid)
		b:SetSize(ENH, ENH)
		-- the kit's octagon frame (grey; gold when you have the item)
		W.DressFramedIcon(b, nil, b:GetWidth())
		W.SetFramedIconGold(b, false)
		local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
		hl:SetTexture(FLAT); hl:SetVertexColor(1, 1, 1, 0.15)
		b:SetScript("OnEnter", function(s)
			GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(s.link)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("OnClick", function(s)
			if not IsModifiedClick("CHATLINK") then return end
			local link = s.spell and GetSpellLink(s.spell) or select(2, GetItemInfo(s.item or 0))
			if link then ChatEdit_InsertLink(link) end
		end)
		enhs[i] = b
		return b
	end

	local function label(pool, i, size, role)
		if not pool[i] then pool[i] = W.Text(grid, "", size, role) end
		pool[i]:ClearAllPoints()
		pool[i]:Show()
		return pool[i]
	end

	local function paintBis()
		cdd:refreshText(); sdd:refreshText()
		for ph, b in pairs(phaseTabs) do b:SetKind(ph == state.bPhase and "tabOn" or "tab") end
		for _, c in ipairs(cells) do c:Hide() end
		for _, t in ipairs(slotTexts) do t:Hide() end
		for _, t in ipairs(heads) do t:Hide() end
		for _, e in ipairs(enhs) do e:Hide() end
		local rows = (((OkanvilBis or {})[state.bClass] or {})[state.bList] or {})[state.bPhase] or {}
		-- slots with no items on this phase's list are left out
		local filled = {}
		for _, row in ipairs(rows) do if row[1] then filled[#filled + 1] = row end end
		local half = math.ceil(#filled / 2)
		local ICONS_X = SLOT_W + ENH_W
		local colW = ICONS_X + 6 * (BIS_ICON + BIS_GAP)
		local nT, nC, nH, nE = 0, 0, 0, 0
		if #filled == 0 then
			nH = nH + 1
			label(heads, nH, "body", "dim"):SetPoint("TOPLEFT", Okanvil.UI.PAD_X, 0)
			heads[nH]:SetText("No list for " .. (state.bList or "?") .. " in " .. state.bPhase .. ".")
			return
		end
		for col = 0, (#filled > half) and 1 or 0 do
			local x = Okanvil.UI.PAD_X + col * (colW + 28)
			nH = nH + 1
			label(heads, nH, "note", "dim"):SetPoint("TOPLEFT", grid, "TOPLEFT", x, 0)
			heads[nH]:SetText("SLOT")
			for r = 1, 6 do
				nH = nH + 1
				label(heads, nH, "note"):SetPoint("TOP", grid, "TOPLEFT",
					x + ICONS_X + (r - 1) * (BIS_ICON + BIS_GAP) + BIS_ICON / 2, 0)
				heads[nH]:SetText("|cff" .. RANK_HEX[r] .. (r == 1 and "BIS" or tostring(r)) .. "|r")
			end
			for i = col * half + 1, math.min(#filled, (col + 1) * half) do
				local row = filled[i]
				local y = -18 - (i - col * half - 1) * BIS_ROW
				nT = nT + 1
				label(slotTexts, nT, "body"):SetPoint("LEFT", grid, "TOPLEFT", x, y - BIS_ICON / 2)
				slotTexts[nT]:SetText(row.slot or "")
				for k, eid in ipairs(row.e or {}) do
					if k > 6 then break end
					if eid ~= 0 then
						nE = nE + 1
						local e = enhIcon(nE)
						e:ClearAllPoints()
						-- the block centred on the item icons, 3px between gems
						local lines = math.ceil(math.min(#row.e, 6) / 2)
						local top = y - math.floor((BIS_ICON - (lines * (ENH + 3) - 3)) / 2)
						e:SetPoint("TOPLEFT", grid, "TOPLEFT", x + SLOT_W + ((k - 1) % 2) * (ENH + 3),
							top - math.floor((k - 1) / 2) * (ENH + 3))
						if eid < 0 then
							e.spell, e.item, e.link = -eid, nil, "spell:" .. (-eid)
							e.icon:SetTexture((select(3, GetSpellInfo(-eid))) or "Interface\\Icons\\INV_Misc_QuestionMark")
						else
							e.spell, e.item, e.link = nil, eid, "item:" .. eid
							e.icon:SetTexture((GetItemIcon and GetItemIcon(eid)) or "Interface\\Icons\\INV_Misc_QuestionMark")
						end
						e:Show()
					end
				end
				for r = 1, 6 do
					local id = row[r]
					if id then
						-- the lists name the Alliance copy of faction items
						if horde then id = (OkanvilBisHordeToAli or {})[id] or id end
						nC = nC + 1
						local c = cell(nC)
						c:ClearAllPoints()
						c:SetPoint("TOPLEFT", grid, "TOPLEFT", x + ICONS_X + (r - 1) * (BIS_ICON + BIS_GAP), y)
						c.id = id
						c.icon:SetTexture((GetItemIcon and GetItemIcon(id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
						local have = (GetItemCount(id, true) or 0) > 0
						if have then c.own:Show() else c.own:Hide() end
						W.SetFramedIconGold(c, have)
						c:Show()
					end
				end
			end
		end
	end

	refresh = function()
		if not host:IsVisible() then return end
		dash:Refresh()
		for v, b in pairs(viewTabs) do b:SetKind(v == state.view and "tabOn" or "tab") end
		if specFS then specFS:SetText(specText()) end
		if state.view == "bis" then
			bar:Hide(); body:Hide(); bis:Show()
			paintBis()
			return
		end
		bis:Hide(); bar:Show(); body:Show()
		U.BeginPass(20)
		-- only the raid's own difficulties, side by side: a hidden tab keeps no gap
		local prevTab = state.dd
		for _, m in ipairs(U.MODE_ORDER) do
			local b = modeTabs[m]
			local has = false
			for _, x in ipairs(U.ModesOf(state.raid)) do if x == m then has = true end end
			if b and has then
				b:ClearAllPoints()
				b:SetPoint("LEFT", prevTab, "RIGHT", prevTab == state.dd and 14 or 4, 0)
				b:Show()
				prevTab = b
			elseif b then
				b:Hide()
			end
			if b then b:SetKind(m == state.mode and "tabOn" or "tab") end
		end
		if state.dd then state.dd:refreshText() end
		for _, r in ipairs(bossRows) do r:Hide() end
		for _, r in ipairs(itemRows) do r:Hide() end

		local bosses = OkanvilRaidLoot and OkanvilRaidLoot[state.raid] or {}
		local hereRaid = U.Here()
		local y, nb, ni, waiting, total = 6, 0, 0, 0, 0

		local function bossRow()
			nb = nb + 1
			local r = bossRows[nb] or newBossRow()
			bossRows[nb] = r
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", p, "RIGHT", 0, 0)
			r.onClick = nil
			r:Show()
			y = y + BOSS_H
			return r
		end

		local q = state.query or ""

		-- One line per boss, folded; the next boss (and anything the search
		-- matches) open. Click a boss to open or close it.
		local function drawBoss(b, isNext, isDead)
			local all, pending = U.Of(b, state.raid, state.mode)
			waiting = waiting + pending
			local ups = {}
			for _, u in ipairs(all) do
				if q == "" or (u.name or ""):lower():find(q, 1, true) or (u.slot or ""):lower():find(q, 1, true) then
					ups[#ups + 1] = u
				end
			end
			if #ups == 0 then return end
			total = total + #ups
			local open = state.open[b.boss]
			if q ~= "" then open = true
			elseif open == nil then open = state.allOpen or isNext end
			local r = bossRow()
			r.caret:SetText(open and "v" or ">")
			r.caret:SetTextColor(u3(open and C.accentText or C.textDim))
			r.name:SetText((isNext and "|cffe0b860> |r" or "") .. U.BossLabel(b.boss) .. (isDead and "  |cffffd200killed|r" or ""))
			r.name:SetTextColor(u3(isDead and C.textDim or (isNext and C.accentText or C.text)))
			local nBis = 0
			for _, u in ipairs(ups) do if u.v.bis then nBis = nBis + 1 end end
			r.tag:SetText((nBis > 0 and ("|cffff8000" .. nBis .. " BiS|r  ") or "")
				.. "|cffe0b860" .. #ups .. "|r for you")
			r.onClick = function() state.open[b.boss] = not open; refresh() end
			if not open then return end
			for _, u in ipairs(ups) do
				ni = ni + 1
				local it = itemRows[ni] or newItemRow()
				itemRows[ni] = it
				it.link = u.link
				it:ClearAllPoints()
				it:SetPoint("TOPLEFT", 0, -y); it:SetPoint("RIGHT", p, "RIGHT", 0, 0)
				it.icon:SetTexture(u.icon)
				local qr, qg, qb = GetItemQualityColor(u.quality or 4)
				it.name:SetText(u.name); it.name:SetTextColor(qr, qg, qb)
				local place = u.v.rank and (u.v.bis and "|cffff8000BiS|r"
					or ("|cffe0b860#" .. u.v.rank .. "|r on your list"
						.. (u.v.as and (" |cff8a8d93(the|r |cffe0b860" .. u.v.as .. "|r |cff8a8d93copy)|r") or ""))) or nil
				it.sub:SetText((u.slot or "") .. (u.v.ilvl and ("  ·  |cffffd200" .. u.v.ilvl .. "|r") or "")
					.. (place and ("  ·  " .. place) or ""))
				local cr, cg, cb = 0.49, 0.99, 0.54
				if u.v.bis then cr, cg, cb = 1, 0.5, 0
				elseif u.v.rank then cr, cg, cb = u3(C.accentText) end
				it.bar:SetVertexColor(cr, cg, cb, 0.9)
				-- what it replaces, from the middle of the row
				local half = math.floor((p:GetWidth() or 600) * 0.48)
				it.name:SetWidth(half - ICON - 30); it.sub:SetWidth(half - ICON - 30)
				it.vsK:ClearAllPoints(); it.vsK:SetPoint("LEFT", it, "LEFT", half, 0)
				if u.v.worn then
					local wn, _, wq, wl, _, _, _, _, _, wt = GetItemInfo(u.v.worn)
					it.vsIcon:SetTexture(wt); it.vsIcon:Show()
					local wr, wg, wb = GetItemQualityColor(wq or 4)
					local gain = (u.v.ilvl and wl) and (u.v.ilvl - wl) or 0
					it.vs:SetText(("|cff%02x%02x%02x%s|r  |cffd06a6a%s|r%s"):format(wr * 255, wg * 255, wb * 255,
						wn or "?", wl or "", gain > 0 and ("  |cffffd200+" .. gain .. "|r") or ""))
					it.vsK:SetText("replaces")
				else
					it.vsIcon:Hide()
					it.vsK:SetText("")
					it.vs:SetText("|cffffd200empty slot|r")
				end
				it.val:SetText(U.Label(u.v))
				if u.v.bis then it.val:SetTextColor(1, 0.5, 0)
				elseif u.v.rank then it.val:SetTextColor(u3(C.accentText))
				else it.val:SetTextColor(0.49, 0.99, 0.54) end
				it:SetAlpha(isDead and 0.5 or 1)
				it:Show()
				y = y + ITEM_H
			end
			y = y + 4
		end

		-- the raid's own boss order; killed ones greyed in place
		local nextDone = hereRaid ~= state.raid
		for _, b in ipairs(bosses) do
			local isDead = hereRaid == state.raid and U.Killed(state.raid, b.boss)
			if isDead then
				drawBoss(b, false, true)
			else
				local before = nb
				drawBoss(b, not nextDone, false)
				if nb > before then nextDone = true end
			end
		end

		status:ClearAllPoints()
		status:SetPoint("TOPLEFT", 2, -(y + 6)); status:SetPoint("RIGHT", p, "RIGHT", 0, 0)
		if waiting > 0 then
			status:SetText("Loading " .. waiting .. " items...")
		elseif total == 0 then
			local spec = U.Spec()
			status:SetText("Nothing here beats your gear" .. (spec and (" for " .. spec.label) or "") .. ".")
		else
			status:SetText("Shift-click an item to link it, ctrl-click to try it on.")
		end
		p:SetHeight(math.max(y + 30, sf:GetHeight()))
		relayout()
		U.EndPass()
	end

	U.onChange = function() if host:IsVisible() then timedRefresh() end end
	host:HookScript("OnShow", function()
		slowStop = false
		-- walking into a raid moves the page there
		local raid, mode = U.Here()
		if raid and raid ~= state.raid then state.raid, state.mode = raid, mode end
		timedRefresh()
	end)
	if host:IsVisible() then timedRefresh() end
end

-- ------------------------------------------------------------
-- Register
-- ------------------------------------------------------------
Okanvil_Plugins = Okanvil_Plugins or {}
Okanvil_Plugins[ADDON] = {
	title = "Upgrades",
	desc  = "Raid drops that are an upgrade for your current spec, on a page and on boss tooltips.",
	icon  = (Okanvil.ICONS and Okanvil.ICONS.upgrades) or "Interface\\Icons\\INV_Sword_39",
	build = function(panel) Okanvil:BuildUpgrades(panel) end,
}
if Okanvil and Okanvil.Register then
	Okanvil:Register(ADDON)
end
