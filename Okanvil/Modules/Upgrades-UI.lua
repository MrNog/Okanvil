-- ============================================================
-- Okanvil -- Upgrades page (RAID > Upgrades).
-- Pick a raid and difficulty; every boss lists the drops that are an upgrade
-- for the spec you are in. Bosses killed on your lockout fold into one line.
-- ============================================================

local Okanvil = Okanvil
local W = Okanvil.W
local C = Okanvil.Colors
local U = Okanvil.Upgrades
local ADDON = U.ADDON

local FLAT = "Interface\\Buttons\\WHITE8x8"
local BOSS_H, ITEM_H, ICON, SMALL = 36, 42, 30, 20
-- the page's controls read one size up and stand taller (as on PuG)
local CTRL_FONT, CTRL_H, BAR_H = 15, 30, 48
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
	local state = { open = {} }
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
		subtitle = "Raid drops that beat your gear, for the spec you are in",
		icon = Okanvil.ICONS.upgrades,
		drawerWidth = 0,
		footerHeight = 0,
		-- the spec in your class colour
		statusText = function()
			local spec = U.Spec()
			local c = spec and RAID_CLASS_COLORS and RAID_CLASS_COLORS[spec.class]
			local hex = c and ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) or "|cffe0b860"
			return "|cff8a8d93Spec|r " .. (spec and (hex .. spec.label .. "|r") or "|cff8a8d93?|r")
		end,
	})

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
		-- search: matching bosses open, the rest fold away
		local openAll = big(W.Button(header, "Open all"))
		openAll:SetSize(96, CTRL_H); openAll:SetPoint("RIGHT", header, "RIGHT", -Okanvil.UI.PAD_X, 0)
		openAll:SetScript("OnClick", function()
			state.allOpen = not state.allOpen
			state.open = {}
			openAll.text:SetText(state.allOpen and "Close all" or "Open all")
			refresh()
		end)
		local search = W.EditBox(header, function(text)
			state.query = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
			refresh()
		end)
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
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(ICON, ICON); r.icon:SetPoint("LEFT", 22, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.val = W.Text(r, "", "head"); r.val:SetPoint("RIGHT", -6, 0); r.val:SetWidth(78)
		r.val:SetJustifyH("RIGHT")
		-- left half: the drop; right half: what it replaces
		r.name = W.Text(r, "", "head"); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
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

	refresh = function()
		if not host:IsVisible() then return end
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
		dash:Refresh()
		for _, r in ipairs(bossRows) do r:Hide() end
		for _, r in ipairs(itemRows) do r:Hide() end

		local bosses = OkanvilRaidLoot and OkanvilRaidLoot[state.raid] or {}
		local hereRaid = U.Here()
		local y, nb, ni, waiting, killed, total = 6, 0, 0, 0, 0, 0
		local W_ = p:GetWidth()

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

		-- killed bosses first, as one line you can open
		local dead, live = {}, {}
		for _, b in ipairs(bosses) do
			if hereRaid == state.raid and U.Killed(state.raid, b.boss) then dead[#dead + 1] = b
			else live[#live + 1] = b end
		end
		killed = #dead

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
			r.name:SetText((isNext and "|cffe0b860> |r" or "") .. U.BossLabel(b.boss) .. (isDead and "  |cff7cfc8akilled|r" or ""))
			r.name:SetTextColor(u3(isDead and C.textDim or (isNext and C.accentText or C.text)))
			r.tag:SetText(#ups .. " for you")
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
				local place = u.v.rank and (u.v.bis and "BiS" or ("#" .. u.v.rank .. " on your list")) or nil
				it.sub:SetText((u.slot or "") .. (u.v.ilvl and ("  ·  " .. u.v.ilvl) or "")
					.. (place and ("  ·  " .. place) or ""))
				-- what it replaces, from the middle of the row
				local half = math.floor((p:GetWidth() or 600) * 0.48)
				it.name:SetWidth(half - ICON - 30); it.sub:SetWidth(half - ICON - 30)
				it.vsK:ClearAllPoints(); it.vsK:SetPoint("LEFT", it, "LEFT", half, 0)
				if u.v.worn then
					local wn, _, wq, wl, _, _, _, _, _, wt = GetItemInfo(u.v.worn)
					it.vsIcon:SetTexture(wt); it.vsIcon:Show()
					local wr, wg, wb = GetItemQualityColor(wq or 4)
					it.vs:SetText(("|cff%02x%02x%02x%s|r  |cff8a8d93%s|r"):format(wr * 255, wg * 255, wb * 255,
						wn or "?", wl or ""))
					it.vsK:SetText("replaces")
				else
					it.vsIcon:Hide()
					it.vsK:SetText("")
					it.vs:SetText("|cff8a8d93empty slot|r")
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

		-- killed bosses first, greyed and folded like the rest
		for _, b in ipairs(dead) do drawBoss(b, false, true) end
		local nextDone = hereRaid ~= state.raid
		for _, b in ipairs(live) do
			local before = nb
			drawBoss(b, not nextDone, false)
			if nb > before then nextDone = true end
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
