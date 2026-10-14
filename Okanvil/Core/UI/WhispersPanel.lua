-- ============================================================
-- Okanvil -- Whispers panel (shared by PuG and Recruit).
-- Its own window docked to the right of the main one: a header, a row of status
-- filters, the people who whispered (name, status, how long ago, one sub line,
-- Inv / /w / x), and a footer with Clear and an optional bulk action. A click on
-- a row opens what they said. The module supplies the list and the actions, so
-- PuG's Inv is a raid invite and Recruit's is a guild invite.
--
--   local wp = W.WhispersPanel(parent, cfg)
--   wp:Refresh()   wp:Toggle()   wp.side (the window)
--
-- cfg:
--   title, subtitle, icon
--   items()          -> { { name, class, status, t, sub, said, canInvite,
--                          badge, detail }, ... }
--     badge  = short coloured text next to the name (optional)
--     detail = { text = "...", actions = { { label, kind, width, tip, onClick }, ... } }
--              shown under what they said when the row is opened (optional)
--   status          = { [status] = { label, colour }, ... }
--   filters         = { { key, label, match = { [status] = true } | nil }, ... }
--   onInvite(name), onDismiss(name), onOpen(name) (optional), onClear()
--   inviteTip, bulk = { label, tip, onClick } (optional)
--   hidden() / setHidden(bool)   -- remembered open/closed state
--   emptyHint                    -- the line under "No whispers yet"
-- ============================================================

local Okanvil = Okanvil
local W = Okanvil.W
local C = Okanvil.Colors

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local PANEL_W = 360
local ROW_H = 42
local CTRL_FONT, CTRL_H = 13, 26

local function big(b)
	local t = b and (b.text or b.textFS)
	if t then t._okSize = CTRL_FONT; t:SetFont(Okanvil:Font(), CTRL_FONT) end
	return b
end

local function classHex(token)
	local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	if c then return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
	return "|cffffffff"
end

local function ago(t)
	local s = math.max(0, time() - (t or time()))
	if s < 60 then return s .. "s" end
	if s < 3600 then return math.floor(s / 60) .. "m" end
	if s < 86400 then return math.floor(s / 3600) .. "h" end
	return math.floor(s / 86400) .. "d"
end

-- ------------------------------------------------------------
-- A scrolling list in a soft card: returns card, child, relayout(h), scrollframe.
-- ------------------------------------------------------------
function W.ScrollList(parent, x, w, top, bottom)
	local card = W.Frame(parent, "soft")
	card:SetPoint("TOPLEFT", x, top)
	card:SetWidth(w)
	card:SetPoint("BOTTOM", parent, "BOTTOM", 0, bottom)

	local sf = CreateFrame("ScrollFrame", nil, card)
	sf:SetPoint("TOPLEFT", 4, -4); sf:SetPoint("BOTTOMRIGHT", -10, 4)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(10, 1); sf:SetScrollChild(child)

	-- 3.3.5a hides rows scrolled out of view but still hit-tests them, so a row
	-- scrolled off the top sits invisibly over the search box and takes its
	-- clicks. Only rows whose middle is inside the viewport keep the mouse.
	local function syncMouse()
		local top, bottom = sf:GetTop(), sf:GetBottom()
		if not (top and bottom) then return end
		for _, row in ipairs({ child:GetChildren() }) do
			local rt, rb = row:GetTop(), row:GetBottom()
			local mid = rt and rb and (rt + rb) / 2
			row:EnableMouse(mid ~= nil and mid <= top and mid >= bottom)
		end
	end

	local sb = CreateFrame("Slider", nil, card)
	sb:SetPoint("TOPRIGHT", -3, -4); sb:SetPoint("BOTTOMRIGHT", -3, 4); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
	local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetSize(4, 30)
	do local a = C.accent; th:SetVertexColor(a[1], a[2], a[3], 1) end
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v); syncMouse() end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, dz) sb:SetValue(sb:GetValue() - dz * 30) end)
	sf:SetScript("OnSizeChanged", function() child:SetWidth(sf:GetWidth()) end)

	local function relayout(h)
		child:SetWidth(sf:GetWidth() or w)
		child:SetHeight(math.max(1, h or 1))
		local maxs = math.max(0, (h or 1) - sf:GetHeight())
		sb:SetMinMaxValues(0, maxs); sb:SetShown(maxs > 4)
		syncMouse()
	end
	return card, child, relayout, sf
end

-- ------------------------------------------------------------
-- The panel
-- ------------------------------------------------------------
function W.WhispersPanel(parent, cfg)
	local P = { cfg = cfg, rows = {}, filter = (cfg.filters[1] or {}).key, open = nil }

	local function rowOf(i, list)
		local row = P.rows[i]
		if row then return row end
		row = CreateFrame("Button", nil, list)
		row:SetHeight(ROW_H)
		local hl = row:CreateTexture(nil, "BACKGROUND")
		hl:SetAllPoints(); hl:SetTexture(FLAT); hl:SetVertexColor(1, 1, 1, 0)
		row.hl = hl
		local rule = row:CreateTexture(nil, "BORDER")
		rule:SetTexture(FLAT); rule:SetHeight(1)
		do local b = C.border; rule:SetVertexColor(b[1], b[2], b[3], 1) end
		rule:SetPoint("BOTTOMLEFT", 0, 0); rule:SetPoint("BOTTOMRIGHT", 0, 0)

		row.x = W.Button(row, "x", nil):Size(22, 22)
		row.x:SetPoint("TOPRIGHT", -2, -4)
		row.x:Tooltip("Remove from the list.\nThey come back if they whisper again.")
		row.w = W.Button(row, "/w", nil):Size(30, 22)
		row.w:SetPoint("RIGHT", row.x, "LEFT", -3, 0)
		row.w:Tooltip("Whisper them.")
		row.inv = W.Button(row, "Inv", "primary"):Size(38, 22)
		row.inv:SetPoint("RIGHT", row.w, "LEFT", -3, 0)
		if cfg.inviteTip then row.inv:Tooltip(cfg.inviteTip) end

		row.badge = W.Text(row, "", "label")
		row.badge:SetJustifyH("RIGHT")

		row.top = W.Text(row, "", "body")
		row.top:SetPoint("TOPLEFT", 6, -5)
		row.top:SetPoint("RIGHT", row.badge, "LEFT", -4, 0)
		row.top:SetJustifyH("LEFT")
		if row.top.SetWordWrap then row.top:SetWordWrap(false) end

		row.sub = W.Text(row, "", "label", "dim")
		row.sub:SetPoint("TOPLEFT", 6, -23)
		row.sub:SetPoint("RIGHT", -4, 0)
		row.sub:SetJustifyH("LEFT")
		if row.sub.SetWordWrap then row.sub:SetWordWrap(false) end

		-- what they said, shown when the row is opened
		row.said = W.Text(row, "", "label")
		row.said:SetPoint("TOPLEFT", 6, -40)
		row.said:SetPoint("RIGHT", -4, 0)
		row.said:SetJustifyH("LEFT")
		row.said:SetJustifyV("TOP")

		row.detail = W.Text(row, "", "label")
		row.detail:SetJustifyH("LEFT")
		row.detail:SetJustifyV("TOP")
		row.acts = {}

		row:SetScript("OnEnter", function(s) s.hl:SetVertexColor(1, 1, 1, 0.05) end)
		row:SetScript("OnLeave", function(s) s.hl:SetVertexColor(1, 1, 1, s._open and 0.03 or 0) end)
		row:SetScript("OnClick", function(s)
			P.open = (P.open ~= s._name) and s._name or nil
			if P.open and cfg.onOpen then cfg.onOpen(P.open) end
			P:Refresh()
		end)
		row.inv:OnClick(function() if row._name then cfg.onInvite(row._name) end end)
		row.w:OnClick(function() if row._name and ChatFrame_SendTell then ChatFrame_SendTell(row._name) end end)
		row.x:OnClick(function()
			if not row._name then return end
			if P.open == row._name then P.open = nil end
			cfg.onDismiss(row._name)
		end)

		P.rows[i] = row
		return row
	end

	local function matches(f, item)
		return not f.match or f.match[item.status]
	end

	function P:Refresh()
		if not self.child then return end
		local items = cfg.items()
		self.count:SetText(#items > 0 and tostring(#items) or "")

		local cur
		for _, f in ipairs(cfg.filters) do
			local n = 0
			for _, it in ipairs(items) do if matches(f, it) then n = n + 1 end end
			local b = self.filterBtns[f.key]
			b.text:SetText((f.match and n > 0) and (f.label .. " " .. n) or f.label)
			b:SetKind(self.filter == f.key and "primary" or nil)
			if self.filter == f.key then cur = f end
		end
		cur = cur or cfg.filters[1]

		local list = {}
		for _, it in ipairs(items) do if matches(cur, it) then list[#list + 1] = it end end

		local y = 0
		for i, it in ipairs(list) do
			local row = rowOf(i, self.child)
			local open = self.open == it.name
			row._name, row._open = it.name, open
			local look = cfg.status[it.status] or { it.status or "", "|cff8a8d93" }
			-- the tab already says it ("joined" under Joined): leave the room to the name
			local word = (it.status == cur.key) and "" or (look[2] .. look[1] .. "|r  ")
			row.top:SetText(classHex(it.class) .. it.name .. "|r  " .. word .. "|cff6f7176"
				.. ago(it.t) .. "|r")
			row.sub:SetText(it.sub or "")
			if it.canInvite then row.inv:Show() else row.inv:Hide() end
			row.badge:ClearAllPoints()
			row.badge:SetPoint("TOPRIGHT", it.canInvite and row.inv or row.w, "TOPLEFT", -4, -5)
			row.badge:SetText(it.badge or "")
			local h = ROW_H
			if open then
				row.said:SetText(it.said or "")
				row.said:Show()
				h = ROW_H + (row.said:GetStringHeight() or 0) + 6
			else
				row.said:SetText(""); row.said:Hide()
			end
			local d = open and it.detail
			if d and d.text and d.text ~= "" then
				row.detail:ClearAllPoints()
				row.detail:SetPoint("TOPLEFT", 6, -h)
				row.detail:SetPoint("TOPRIGHT", -4, -h)
				row.detail:SetText(d.text)
				row.detail:Show()
				h = h + (row.detail:GetStringHeight() or 0) + 8
			else
				row.detail:SetText(""); row.detail:Hide()
			end
			local acts = d and d.actions or {}
			local right = -4
			for ai = #acts, 1, -1 do
				local a = acts[ai]
				local b = row.acts[ai]
				if not b then
					b = W.Button(row, "", a.kind)
					row.acts[ai] = b
				end
				if b.SetKind then b:SetKind(a.kind) end
				b.text:SetText(a.label)
				b:Size(a.width or 70, 22)
				b:Tooltip(a.tip)
				b:OnClick(a.onClick)
				b:ClearAllPoints()
				b:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, -h)
				b:Show()
				right = right - (a.width or 70) - 3
			end
			for ai = #acts + 1, #row.acts do row.acts[ai]:Hide() end
			if #acts > 0 then h = h + 22 + 8 end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -y); row:SetPoint("TOPRIGHT", 0, -y)
			row:SetHeight(h)
			row.hl:SetVertexColor(1, 1, 1, open and 0.03 or 0)
			row:Show()
			y = y + h
		end
		for i = #list + 1, #self.rows do self.rows[i]:Hide() end

		local empty = #list == 0
		if empty then self.emptyIcon:Show() else self.emptyIcon:Hide() end
		if #items == 0 then
			self.empty:SetText(empty and "No whispers yet" or "")
			self.emptyHint:SetText(empty and (cfg.emptyHint or "") or "")
		else
			self.empty:SetText(empty and "Nobody here" or "")
			self.emptyHint:SetText(empty and "Try another filter." or "")
		end
		self.relayout(y)
	end

	-- the window, docked outside the main one so the page keeps its full width
	local side = CreateFrame("Frame", nil, parent)
	Okanvil:Skin(side)
	W.ForgeArt(side, 0.22)
	side:SetWidth(PANEL_W + 24)
	side:EnableMouse(true)
	local p = W.Frame(side, "bare")
	p:SetPoint("TOPLEFT", 12, -12); p:SetPoint("BOTTOMRIGHT", -12, 10)
	P.side = side

	-- Dock on the right; flip to the left when the window sits against the
	-- screen's right edge and the panel would hang off it.
	local function dock()
		local win = Okanvil.win
		if not win then return end
		side:ClearAllPoints()
		local right = (win:GetRight() or 0) * win:GetEffectiveScale()
		local room = UIParent:GetRight() * UIParent:GetEffectiveScale() - right
		if room >= side:GetWidth() * win:GetEffectiveScale() then
			side:SetPoint("TOPLEFT", win, "TOPRIGHT", 2, 0)
			side:SetPoint("BOTTOMLEFT", win, "BOTTOMRIGHT", 2, 0)
		else
			side:SetPoint("TOPRIGHT", win, "TOPLEFT", -2, 0)
			side:SetPoint("BOTTOMRIGHT", win, "BOTTOMLEFT", -2, 0)
		end
	end
	side:SetScript("OnShow", function() dock(); P:Refresh() end)
	dock()

	-- header in the page style: icon, gold title, one grey line, a hairline
	local head = W.Frame(p, "bare")
	head:SetPoint("TOPLEFT", 0, 0); head:SetPoint("TOPRIGHT", 0, 0)
	head:SetHeight(50)
	W.Hairline(head, "BOTTOM", 0)
	local icon = head:CreateTexture(nil, "OVERLAY")
	icon:SetSize(28, 28); icon:SetPoint("LEFT", 0, 2)
	icon:SetTexture(cfg.icon or "Interface\\Icons\\INV_Letter_15"); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local title = W.Text(head, cfg.title or "Whispers", "title", "accent")
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 1)
	local sub = W.Text(head, cfg.subtitle or "", "note", "dim")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
	P.count = W.Text(head, "", "title", "accent")
	P.count:SetPoint("RIGHT", -2, 2)

	-- filters: one segmented row across the full width
	P.filterBtns = {}
	local n = #cfg.filters
	local seg = (PANEL_W - (n - 1) * 3) / n
	for i, f in ipairs(cfg.filters) do
		local b = big(W.Button(p, f.label, nil):Size(seg, 24))
		b:SetPoint("TOPLEFT", (i - 1) * (seg + 3), -60)
		b:OnClick(function() P.filter = f.key; P:Refresh() end)
		P.filterBtns[f.key] = b
	end

	-- footer: Clear on the left, the bulk action on the right
	local foot = W.Frame(p, "bare")
	foot:SetPoint("BOTTOMLEFT", 0, 0); foot:SetPoint("BOTTOMRIGHT", 0, 0)
	foot:SetHeight(34)
	W.Hairline(foot, "TOP", 0)
	if cfg.bulk then
		local bulk = big(W.Button(foot, cfg.bulk.label, "primary"):Size(120, CTRL_H))
		bulk:SetPoint("RIGHT", 0, -2)
		bulk:OnClick(cfg.bulk.onClick)
		if cfg.bulk.tip then bulk:Tooltip(cfg.bulk.tip) end
	end
	local clear = big(W.Button(foot, "Clear", nil):Size(64, CTRL_H))
	clear:SetPoint("LEFT", 0, -2)
	clear:OnClick(function() P.open = nil; cfg.onClear() end)
	clear:Tooltip("Empty the list.\nAnyone who whispers again comes back.")

	local card, child, relayout = W.ScrollList(p, 0, PANEL_W, -88, 42)
	P.child, P.relayout = child, relayout
	-- a light wash, not a slab: the forge art should read through the list
	do local d = C.panelD; card:SetBackdropColor(d[1], d[2], d[3], 0.35) end

	-- empty state, centred in the list
	P.emptyIcon = card:CreateTexture(nil, "ARTWORK")
	P.emptyIcon:SetSize(36, 36); P.emptyIcon:SetPoint("CENTER", 0, 30)
	P.emptyIcon:SetTexture("Interface\\Icons\\INV_Letter_15"); P.emptyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	P.emptyIcon:SetDesaturated(true); P.emptyIcon:SetAlpha(0.35)
	P.empty = W.Text(card, "", "label", "dim")
	P.empty:SetPoint("TOP", P.emptyIcon, "BOTTOM", 0, -10)
	P.emptyHint = W.Text(card, "", "note", "dim")
	P.emptyHint:SetPoint("TOP", P.empty, "BOTTOM", 0, -4)
	P.emptyHint:SetJustifyH("CENTER")

	-- keep the "12s ago" honest while the panel is open
	local tick = 0
	p:SetScript("OnUpdate", function(_, e)
		tick = tick + e
		if tick < 5 then return end
		tick = 0
		P:Refresh()
	end)

	function P:Toggle()
		local hide = side:IsShown()
		if cfg.setHidden then cfg.setHidden(hide) end
		if hide then side:Hide() else side:Show() end
	end

	if cfg.hidden and cfg.hidden() then side:Hide() end
	P:Refresh()
	return P
end
