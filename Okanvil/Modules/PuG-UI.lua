-- ============================================================
-- Okanvil -- PuG UI.
-- One page: the raid picker and role needs across the top, the assignment board
-- (Unassigned / Tank / Healer / Melee / Ranged) taking the middle, and the
-- outgoing line plus the channel / reserve / class strips along the bottom.
-- Every strip is a solid panel -- the shared rat art is drawn above the content
-- well's own fill, so a transparent strip puts text on top of a picture.
-- Draws into the panel the host hands us (never its own window).
-- ============================================================

local Okanvil = Okanvil
local M = Okanvil.PuG
local W = Okanvil.W
local C = Okanvil.Colors

-- The flat 1px texture every panel and slider in the addon is drawn with. It was
-- used three times in this file without being declared here -- it is a LOCAL in
-- Shell.lua, so those calls were passing nil and the scrollbar thumbs and row
-- highlights had no texture at all.
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

local ROLES = { "tank", "healer", "melee", "ranged" }

-- The page's controls (raid picker, sizes, Send once, reserves, header buttons)
-- read one size up from the shared button label, and stand taller. The board in
-- the middle keeps the standard sizes.
local MENU_FONT, MENU_H = 13, 26
local function menu(b)
	local t = b and (b.text or b.textFS)
	if t then t._okSize = MENU_FONT; t:SetFont(Okanvil:Font(), MENU_FONT) end
	return b
end
local ROLE_COLOR = {
	tank   = "|cff4a90d9",
	healer = "|cff7cfc8a",
	melee  = "|cffe05555",
	ranged = "|cffc77dd6",
}
-- plain {r,g,b} of the same four, for column headers and borders
local ROLE_RGB = {
	tank   = { 0.29, 0.56, 0.85 },
	healer = { 0.49, 0.99, 0.54 },
	melee  = { 0.88, 0.33, 0.33 },
	ranged = { 0.78, 0.49, 0.84 },
}
local ROLE_LABEL = { tank = "Tank", healer = "Healer", melee = "Melee", ranged = "Ranged" }

local F                      -- built frame set (nil until BuildUI runs)
-- Two lines per person: the name, then the spec and gearscore under it.
--
-- This is the POOL size, not how many are visible -- the columns scroll, so it
-- only has to cover the biggest list a pug produces. Twenty-one applicants in one
-- ToGC was real, and a 25-man raid is twenty-five names.
local BOARD_ROWS = 30
local BOARD_ROW_H = 34

local function db() return M.DB() end

local function class_color(token)
	if not token then return "|cffffffff" end
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	if c then return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
	return "|cffffffff"
end

local function label(parent, text, x, y, role, size)
	local fs = W.Text(parent, text, size, role or "dim")
	fs:SetPoint("TOPLEFT", x, y)
	return fs
end

-- ------------------------------------------------------------
-- Touching a PICK hands control back to the generator.
--
-- Hand-editing the line switches the builder off, which is right -- your typing
-- must not be overwritten. But then the raid / size / difficulty / Reserve
-- controls would silently do nothing, so clicking one of those IS the statement
-- "build it from my picks" and takes control back.
--
-- The need counts and the Ask-for chips do NOT call this. They only change the
-- "need ..." clause, and a hand-typed line already gets that clause spliced in
-- live (PuG.lua outgoing), so they work on your text without discarding it.
-- Leaders tap +/- all night as people join; if that threw the text away, the
-- spam went out as the default line and nobody noticed until pugs said so.
--
-- When it does take over it says so in chat: the text is kept in d.custom but
-- no longer sent, and the box is below the fold of attention mid-pug. `gs` /
-- `note`, which are typed rather than picked, never call this.
--
-- Declared up here, above the first builder that uses it: a `local` is only in
-- scope AFTER its declaration, so defining it further down would leave the top
-- strip calling a nil global.
-- ------------------------------------------------------------
local function pickTakesOver()
	local d = db()
	if not d.useCustom then return end
	d.useCustom = false
	Okanvil:Print("|cffF1C40F[PuG]|r Your own text was replaced by the built line (you changed the raid, size or reserves). Type it again to send your wording.")
end

-- ------------------------------------------------------------
-- Top strip: raid, size, difficulty, gearscore
-- ------------------------------------------------------------
local function buildTopStrip(p)
	local d = db()

	F.raidDD = W.DropDown(p,
		function()
			local out = {}
			for _, r in ipairs(OkanvilRaids or {}) do
				out[#out + 1] = { text = r.name, value = r.key }
			end
			return out
		end,
		function()
			for _, r in ipairs(OkanvilRaids or {}) do
				if r.key == d.raid then return r.name end
			end
			return ""
		end,
		function(v)
			pickTakesOver()
			d.raid = v
			if v ~= "voa" then d.classRun = false end
			-- the new instance may not offer the picked size/difficulty
			local info
			for _, r in ipairs(OkanvilRaids or {}) do if r.key == v then info = r end end
			if info then
				local ok = false
				for _, s in ipairs(info.sizes) do if s == d.size then ok = true end end
				if not ok then
					d.size = info.sizes[1]
					M.ApplySizeComp()   -- a forced size change gets that size's comp
				end
				if not info.hc then d.hc = false end
			end
			M.FitNeedsToSize()
			M.RefreshUI()
		end)
	F.raidDD:SetSize(220, MENU_H)
	F.raidDD:SetPoint("TOPLEFT", 4, -5)
	menu(F.raidDD)
	-- the raid name is what the whole page is about: one size up again
	F.raidDD.textFS._okSize = 14; F.raidDD.textFS:SetFont(Okanvil:Font(), 14)

	F.size10 = menu(W.Button(p, "10", nil):Size(44, MENU_H))
	F.size25 = menu(W.Button(p, "25", nil):Size(44, MENU_H))
	F.size10:OnClick(function() pickTakesOver(); d.classRun = false; d.size = 10; M.ApplySizeComp(); M.RefreshUI() end)
	F.size25:OnClick(function() pickTakesOver(); d.classRun = false; d.size = 25; M.ApplySizeComp(); M.RefreshUI() end)
	-- VoA only: the "18" class run, one raider per PvP set (see M.VoABoard). The
	-- instance is still the 25-man vault; 18 is how many places the run has.
	F.size18 = menu(W.Button(p, "18", nil):Size(44, MENU_H))
	F.size18:OnClick(function() pickTakesOver(); d.classRun = true; d.size = 25; M.RefreshUI() end)
	F.size18:Tooltip("VoA 18: one raider per PvP set, plus two tanks.\n"
		.. "Nobody shares a set, so nobody rolls against anyone.")

	-- Normal | Heroic as a pair, the picked one lit. Hidden for a raid with no
	-- heroic mode, rather than a grey "Normal" that cannot be changed.
	F.diffBtn = menu(W.Button(p, "Normal", nil):Size(70, MENU_H))
	F.diffBtn:OnClick(function() pickTakesOver(); d.hc = false; M.RefreshUI() end)
	F.diffHC = menu(W.Button(p, "Heroic", nil):Size(70, MENU_H))
	F.diffHC:OnClick(function() pickTakesOver(); d.hc = true; M.RefreshUI() end)

	-- The label is anchored to the box, so the two always line up.
	F.gsBox = W.EditBox(p):Size(60, MENU_H)
	F.gsLabel = W.Text(p, "min gs", "body", "dim")
	F.gsLabel:SetPoint("RIGHT", F.gsBox, "LEFT", -6, 0)
	F.gsBox.edit:SetScript("OnTextChanged", function(s) d.gs = s:GetText() or ""; M.RefreshPreview() end)

	-- No free-text box here: extra words go straight into the line at the bottom,
	-- which is editable.

	-- No "Read specs" button: specs are read by themselves. When spamming starts
	-- and as each player joins, anyone without a fresh spec is put on the inspect
	-- watch (PuG-Whispers.lua), which reads them one at a time as they come in range.
end
-- ------------------------------------------------------------
-- The board: Unassigned + one column per role.
--
-- DRAG a name onto any column to place it there -- one motion, any target.
-- Clicking still cycles it to the next column (kept for one-step nudges) and
-- right-click drops it back to Unassigned.
-- Assignments live in db.assign, so a /reload mid-forming keeps the comp.
-- ------------------------------------------------------------
-- Four columns, one per role. There used to be a fifth -- "Applicants" -- for
-- people who whispered but had not been invited yet. It went with the whisper
-- catching: the board is about the raid you HAVE, and who wants in is a
-- conversation that belongs in the chat frame.
local COLS = { "tank", "healer", "melee", "ranged" }

-- What each role column offers under "Ask for": only what can fill that role,
-- and the SPEC where the class alone would say too little (a holy paladin, not
-- any paladin, for a heal spot). Tokens are OkanvilClassSpecs / OkanvilClasses
-- tokens, so the picks feed the "(bdk/prot warr)" part of the line unchanged.
local ASKS = M.ASKS

-- token -> { short, name, class } from the shipped class and spec tables
local function askInfo(token)
	for _, sp in ipairs(OkanvilClassSpecs or {}) do
		if sp.token == token then return sp.short, sp.name, sp.class end
	end
	for _, c in ipairs(OkanvilClasses or {}) do
		if c.token == token then return c.short, c.name, c.token end
	end
end
local COL_TITLE = {
	tank = "Tank", healer = "Healer", melee = "Melee", ranged = "Ranged",
}

-- Where to PARK a hybrid whose spec nobody has read. Not a claim about what they
-- play -- the board marks these rows with a "?" -- just somewhere to show them
-- while you press Read specs.
--
-- Shared from PuG.lua: the roster COUNT has to park them the same way the board
-- does, or the column reads 9/9 while the LFM line still asks for two more.
local HYBRID_PARK = M.HYBRID_PARK

-- ------------------------------------------------------------
-- Drag & drop
--
-- 3.3.5a has no drag-and-drop framework for custom frames: OnReceiveDrag only
-- fires for real cursor payloads (items/spells), never for a frame you moved.
-- So we do it by hand -- a small label that follows the mouse while the button is
-- held, and on release we ask which column the cursor is over. GetCursorPosition
-- returns UI coordinates scaled by UIParent, hence the division by the frame's
-- effective scale.
-- ------------------------------------------------------------
local drag = { name = nil, ghost = nil }

local function ensureGhost()
	if drag.ghost then return drag.ghost end
	local g = CreateFrame("Frame", nil, UIParent)
	g:SetFrameStrata("TOOLTIP")
	g:SetSize(120, 20)
	Okanvil:Skin(g, "raise")
	g.text = W.Text(g, "", "body")
	g.text:SetPoint("CENTER")
	g:Hide()
	g:SetScript("OnUpdate", function(self)
		local x, y = GetCursorPosition()
		local sc = self:GetEffectiveScale()
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc + 60, y / sc - 12)
	end)
	drag.ghost = g
	return g
end

-- which board column is the cursor inside right now? nil = none.
local function columnUnderCursor()
	if not F or not F.cols then return nil end
	local x, y = GetCursorPosition()
	for _, key in ipairs(COLS) do
		local col = F.cols[key] and F.cols[key].frame
		if col and col:IsVisible() then
			local sc = col:GetEffectiveScale()
			local cx, cy = x / sc, y / sc
			if cx >= col:GetLeft() and cx <= col:GetRight()
			   and cy >= col:GetBottom() and cy <= col:GetTop() then
				return key
			end
		end
	end
	return nil
end

local function startDrag(name, class)
	if not name then return end
	drag.name = name
	local g = ensureGhost()
	g.text:SetText(class_color(class) .. name .. "|r")
	g:Show()
end

local function endDrag()
	local name = drag.name
	drag.name = nil
	if drag.ghost then drag.ghost:Hide() end
	if not name then return end
	-- OnDragStop fires before this row's OnMouseUp, which would otherwise read the
	-- release as a plain click and cycle the player one extra column. The stamp is
	-- cleared by the next click that is NOT part of a drag.
	drag.justDropped = GetTime and GetTime() or 0
	local key = columnUnderCursor()
	if not key then return end                      -- dropped outside: no change
	M.Assign(name, key ~= "unassigned" and key or nil)
	M.RefreshUI()
end

local function buildBoard(p)
	F.cols = {}
	local n = #COLS
	local gap = 6
	-- columns are laid out proportionally so the board fills whatever width the
	-- host panel has, rather than assuming a fixed window size
	for i, key in ipairs(COLS) do
		local col = W.Frame(p, "soft")
		col:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
		col:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
		col._idx = i

		-- The header carries EVERYTHING about this role: its name, how many you have
		-- against how many you want, and the two buttons that change the target.
		-- There used to be a second strip above the board saying "Melee 1/8 need 7"
		-- while the column below it said "Melee 1" -- the same fact twice, costing
		-- 50px of the board it was describing.
		local head = W.Frame(col, "row")
		head:SetPoint("TOPLEFT", 1, -1)
		head:SetPoint("TOPRIGHT", -1, -1)
		head:SetHeight(24)

		local rgb = ROLE_RGB[key]
		local title = W.Text(head, COL_TITLE[key], "body")
		title:SetPoint("LEFT", 6, 0)
		if rgb then title:SetTextColor(rgb[1], rgb[2], rgb[3]) end

		local cnt, minus, plus
		do
			plus = W.Button(head, "+", nil):Size(18, 16)
			plus:SetPoint("RIGHT", -4, 0)
			minus = W.Button(head, "-", nil):Size(18, 16)
			minus:SetPoint("RIGHT", plus, "LEFT", -2, 0)
			cnt = W.Text(head, "", "label", "accent")
			cnt:SetPoint("RIGHT", minus, "LEFT", -6, 0)

			-- SetNeed clamps the total to the raid size, taking any surplus off the
			-- other dps bucket first (see PuG.lua). They only change the need clause,
			-- which a hand-typed line gets spliced in, so they never take over.
			local role = key
			minus:OnClick(function()
				M.SetNeed(role, (tonumber(db().need[role]) or 0) - 1)
				M.RefreshUI()
			end)
			plus:OnClick(function()
				M.SetNeed(role, (tonumber(db().need[role]) or 0) + 1)
				M.RefreshUI()
			end)
		end

		-- "Ask for": the classes this role wants, right under its count. Picks are
		-- kept per role, so each column says its own "(bdk/prot warr)" in the line.
		local ask = CreateFrame("Frame", nil, col)
		ask:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
		ask:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, 0)
		ask:SetHeight(44)
		local albl = W.Text(ask, "ASK FOR", "note", "dim"); albl:SetPoint("TOPLEFT", 6, -5)
		local arule = ask:CreateTexture(nil, "BORDER")
		arule:SetTexture(FLAT); arule:SetVertexColor(1, 1, 1, 0.06); arule:SetHeight(1)
		arule:SetPoint("BOTTOMLEFT"); arule:SetPoint("BOTTOMRIGHT")
		local chips = {}
		for _, token in ipairs(ASKS[key] or {}) do
			local short, name, class = askInfo(token)
			if short then
				local b = CreateFrame("Button", nil, ask)
				b:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
					insets = { left = 1, right = 1, top = 1, bottom = 1 } })
				b.text = W.Text(b, short, "note"); b.text:SetPoint("CENTER", 0, 0)
				b:SetSize((b.text:GetStringWidth() or 30) + 12, 18)
				local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
				b._rgb = cc and { cc.r, cc.g, cc.b } or { 1, 1, 1 }
				b._token = token
				local role = key
				b:SetScript("OnClick", function()
					if db().classRun then pickTakesOver() end   -- a class run lists these outside the need clause
					local picks = M.RolePicks(role)
					picks[token] = (not picks[token]) or nil
					M.RefreshUI()
				end)
				b:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_TOP")
					GameTooltip:AddLine(name, 1, 1, 1)
					GameTooltip:AddLine('Adds "' .. short .. '" to this role in the line.', 0.6, 0.6, 0.6)
					GameTooltip:Show()
				end)
				b:SetScript("OnLeave", function() GameTooltip:Hide() end)
				chips[#chips + 1] = b
			end
		end
		-- Picked = the class colour, filled; not picked = a faint outline.
		local function paintChip(b, on)
			local r, g, bl = b._rgb[1], b._rgb[2], b._rgb[3]
			if on then
				b:SetBackdropColor(r, g, bl, 0.18); b:SetBackdropBorderColor(r, g, bl, 1)
				b.text:SetTextColor(r, g, bl)
			else
				b:SetBackdropColor(0, 0, 0, 0); b:SetBackdropBorderColor(r, g, bl, 0.25)
				b.text:SetTextColor(r * 0.55 + 0.1, g * 0.55 + 0.1, bl * 0.55 + 0.1)
			end
		end
		-- Chips wrap to the column's width; the list below starts under them.
		local function reflow()
			local w = ask:GetWidth() or 0
			if w < 20 then return end
			local x, y = 6, -20
			for _, b in ipairs(chips) do
				local bw = b:GetWidth()
				if x + bw > w - 6 and x > 6 then x = 6; y = y - 22 end
				b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, y)
				x = x + bw + 4
			end
			ask:SetHeight(-y + 24)
		end
		ask:SetScript("OnSizeChanged", reflow)

		-- Each column scrolls. A pug fills the Applicants column with everyone who
		-- answered -- twenty-one of them in one ToGC -- and a fixed ten slots either
		-- hid the rest behind "+11 more" or drew them past the bottom edge.
		local csf = CreateFrame("ScrollFrame", nil, col)
		csf:SetPoint("TOPLEFT", ask, "BOTTOMLEFT", 1, -3)
		csf:SetPoint("BOTTOMRIGHT", -5, 3)
		local cchild = CreateFrame("Frame", nil, csf)
		cchild:SetSize(10, 1); csf:SetScrollChild(cchild)
		Okanvil.Clip(csf)

		local csb = CreateFrame("Slider", nil, col)
		csb:SetPoint("TOPRIGHT", ask, "BOTTOMRIGHT", -2, -3); csb:SetPoint("BOTTOMRIGHT", -2, 3); csb:SetWidth(3)
		csb:SetOrientation("VERTICAL"); csb:SetValueStep(1); csb:SetMinMaxValues(0, 0)
		local cth = csb:CreateTexture(nil, "OVERLAY"); cth:SetTexture(FLAT); cth:SetSize(3, 26)
		do local a = C.accent; cth:SetVertexColor(a[1], a[2], a[3], 1) end
		csb:SetThumbTexture(cth)
		csb:SetScript("OnValueChanged", function(_, v) csf:SetVerticalScroll(v) end)
		csf:EnableMouseWheel(true)
		csf:SetScript("OnMouseWheel", function(_, dz) csb:SetValue(csb:GetValue() - dz * 40) end)
		csf:SetScript("OnSizeChanged", function() cchild:SetWidth(csf:GetWidth()) end)

		local rows = {}
		local y = 0
		for r = 1, BOARD_ROWS do
			local row = W.Frame(cchild, "input")
			row:SetPoint("TOPLEFT", 3, y)
			row:SetPoint("TOPRIGHT", -3, y)
			row:SetHeight(BOARD_ROW_H)
			row:Hide()

			-- Two lines. The parser already reads the spec and the gearscore out of
			-- every whisper; one 18px line could only hold the name, so all of it was
			-- thrown away at the point where it would have been useful.
			row.text = W.Text(row, "", "label")
			row.text:SetPoint("TOPLEFT", 5, -4)
			row.text:SetPoint("RIGHT", -4, 0)
			row.text:SetJustifyH("LEFT")
			if row.text.SetWordWrap then row.text:SetWordWrap(false) end

			row.sub = W.Text(row, "", "note", "dim")
			row.sub:SetPoint("TOPLEFT", 5, -19)
			row.sub:SetPoint("RIGHT", -4, 0)
			row.sub:SetJustifyH("LEFT")
			if row.sub.SetWordWrap then row.sub:SetWordWrap(false) end

			row:EnableMouse(true)
			row:SetMovable(true)
			row:RegisterForDrag("LeftButton")
			-- Drag is the primary gesture (one motion to any column); the click-cycle
			-- stays as a fallback for people who prefer it, and right-click is the
			-- one-step "off the board" that dragging to Unassigned also does.
			row:SetScript("OnDragStart", function(self)
				if self._name then startDrag(self._name, self._class) end
			end)
			row:SetScript("OnDragStop", endDrag)
			row:SetScript("OnMouseUp", function(self, button)
				if not self._name then return end
				-- swallow the click that ends a drag (see endDrag)
				if drag.justDropped and GetTime() - drag.justDropped < 0.2 then
					drag.justDropped = nil
					return
				end
				if button == "RightButton" then
					M.Assign(self._name, nil)
				else
					M.CycleRole(self._name)
				end
				M.RefreshUI()
			end)
			row:SetScript("OnEnter", function(self)
				if not self._name then return end
				-- Brighten the row's OWN colour rather than replacing it: the border is
				-- the player's class, and swapping it for a generic highlight threw
				-- that away for as long as the mouse was over it.
				local e = self._edge
				if e then self:SetBackdropBorderColor(e[1], e[2], e[3], 1)
				else self:SetBackdropBorderColor(C.borderHi[1], C.borderHi[2], C.borderHi[3], 1) end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(self._name, 1, 1, 1)
				if self._sub then GameTooltip:AddLine(self._sub, 0.6, 0.6, 0.6) end
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("Drag to any column", 0.5, 0.9, 0.5)
				GameTooltip:AddLine("Click: next column", 0.6, 0.6, 0.6)
				GameTooltip:AddLine("Right-click: unassign", 0.9, 0.5, 0.5)
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", function(self)
				local e = self._edge
				if e then self:SetBackdropBorderColor(e[1], e[2], e[3], e[4] or 1)
				else self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end
				GameTooltip:Hide()
			end)

			rows[r] = row
			y = y - (BOARD_ROW_H + 3)
		end

		-- "+3 more" when a column overflows the drawn rows
		local more = W.Text(col, "", "label", "dim")
		more:SetPoint("BOTTOMLEFT", 6, 5)

		F.cols[key] = { frame = col, rows = rows, count = cnt, more = more,
		                sf = csf, child = cchild, sb = csb,
		                chips = chips, paintChip = paintChip, reflow = reflow }
	end

	-- ---- VoA 18: one card per place, drawn over the role columns ----------
	-- Six across, three down: the places are grouped by class in M.VoASlots, so
	-- the three druids and the three shamans read as runs of one colour.
	local grid = W.Frame(p, "bare")
	grid:SetAllPoints(p)
	grid:Hide()
	F.voaGrid = grid
	F.voaCards = {}
	local VOA_COLS, VOA_ROWS, UNPLACED_H = 6, 3, 22
	for i = 1, #(M.VoASlots or {}) do
		local card = W.Frame(grid, "input")
		card.title = W.Text(card, "", "note")
		card.title:SetPoint("TOPLEFT", 7, -6)
		card.title:SetPoint("RIGHT", -6, 0)
		card.title:SetJustifyH("LEFT")
		card.name = W.Text(card, "", "body")
		card.name:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
		card.name:SetPoint("RIGHT", -6, 0)
		card.name:SetJustifyH("LEFT")
		card.sub = W.Text(card, "", "note", "dim")
		card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
		card.sub:SetPoint("RIGHT", -6, 0)
		card.sub:SetJustifyH("LEFT")
		-- a second raider on the same set, named on the card itself: "+1" alone
		-- made you hover every card to find out who
		card.dup = W.Text(card, "", "note")
		card.dup:SetPoint("TOPLEFT", card.sub, "BOTTOMLEFT", 0, -4)
		card.dup:SetPoint("RIGHT", -6, 0)
		card.dup:SetJustifyH("LEFT")
		for _, fs in ipairs({ card.title, card.name, card.sub, card.dup }) do
			if fs.SetWordWrap then fs:SetWordWrap(false) end
		end
		-- hover lists everyone on the place, so a duplicate can be found by name
		card:EnableMouse(true)
		card:SetScript("OnEnter", function(self)
			if self._empty then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(self._tipTitle or "", 1, 0.82, 0)
				local cand = self._key and M.VoACandidates(self._key) or {}
				if #cand > 0 then
					GameTooltip:AddLine("Click: put " .. cand[1].name .. " here", 0.5, 0.9, 0.5)
					GameTooltip:AddLine("(spec not read yet)", 0.6, 0.6, 0.6)
				else
					GameTooltip:AddLine("Click to name this place in the line.", 0.6, 0.6, 0.6)
				end
				GameTooltip:Show()
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self._tipTitle or "", 1, 0.82, 0)
			for _, line in ipairs(self._tip or {}) do GameTooltip:AddLine(line, 1, 1, 1) end
			if self._hand then GameTooltip:AddLine("Right-click: take " .. self._hand .. " off this place", 0.9, 0.5, 0.5) end
			GameTooltip:Show()
		end)
		card:SetScript("OnLeave", function() GameTooltip:Hide() end)
		-- An empty place takes the first raider of its class the board could not
		-- place (spec not read); with nobody to place, it toggles whether the line
		-- asks for it, like the role columns' Ask for chips. Right-click undoes a
		-- hand placement.
		card:SetScript("OnMouseUp", function(self, button)
			if not self._key then return end
			if button == "RightButton" then
				if self._hand then M.VoAPlace(self._hand, nil); M.RefreshUI() end
				return
			end
			if button ~= "LeftButton" or not self._empty then return end
			local cand = M.VoACandidates(self._key)
			if #cand > 0 then
				M.VoAPlace(cand[1].name, self._key)
			else
				pickTakesOver()   -- a class run's own text has no need clause to update
				M.ToggleVoAAsk(self._key)
			end
			M.RefreshUI()
		end)
		F.voaCards[i] = card
	end
	F.voaUnplaced = W.Text(grid, "", "note", "dim")
	F.voaUnplaced:SetPoint("BOTTOMLEFT", 4, 4)
	F.voaUnplaced:SetPoint("RIGHT", -4, 0)
	F.voaUnplaced:SetJustifyH("LEFT")

	-- width them once the panel has a real size
	F.layoutBoard = function()
		local total = p:GetWidth()
		if not total or total < 50 then return end
		local w = (total - gap * (n - 1)) / n
		for i, key in ipairs(COLS) do
			local col = F.cols[key].frame
			col:ClearAllPoints()
			col:SetPoint("TOPLEFT", p, "TOPLEFT", (i - 1) * (w + gap), 0)
			col:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", (i - 1) * (w + gap), 0)
			col:SetWidth(w)
		end
		local th = p:GetHeight() or 0
		if th > 50 then
			local cw = (total - gap * (VOA_COLS - 1)) / VOA_COLS
			local ch = math.min(78, (th - UNPLACED_H - gap * (VOA_ROWS - 1)) / VOA_ROWS)
			for i, card in ipairs(F.voaCards) do
				local c, r = (i - 1) % VOA_COLS, math.floor((i - 1) / VOA_COLS)
				card:ClearAllPoints()
				card:SetPoint("TOPLEFT", grid, "TOPLEFT", c * (cw + gap), -r * (ch + gap))
				card:SetSize(cw, ch)
			end
		end
	end
	p:SetScript("OnSizeChanged", function() if F.layoutBoard then F.layoutBoard() end end)
	F.layoutBoard()
end

-- ------------------------------------------------------------
-- Bottom: the outgoing line + applicants
-- ------------------------------------------------------------
local function buildBottom(p)
	-- Only a REAL edit flips the line to hand-edited.
	--
	-- This fires on focus-LOST, which also happens when you merely click into the box
	-- to read it and then click away. Comparing against BuildMessage() at that moment
	-- was wrong twice over: the built line may have changed since the box was filled
	-- (a class toggled, someone joined), so an untouched box looked edited and got
	-- locked -- with "Hand-edited, your picks no longer change this line" and no
	-- obvious way back. It also could not tell an empty box from a deliberate one.
	--
	-- So we compare against the text this box was last GIVEN (F.previewShown), which
	-- is what the user actually saw. Same text = they changed nothing.
	F.preview = W.MultiEdit(p, function(txt)
		local d = db()
		txt = txt or ""
		local shown = F.previewShown or ""
		if txt == shown then return end          -- untouched: not an edit

		if txt:gsub("%s+", "") == "" then
			-- Cleared the box: they want the generated line back, not an empty spam.
			d.useCustom = false
			d.custom = ""
		else
			d.custom = txt
			d.useCustom = true
		end
		M.RefreshUI()
	end)
	F.preview:SetPoint("TOPLEFT", 6, -6)
	F.preview:SetPoint("RIGHT", p, "RIGHT", -148, 0)
	F.preview:SetHeight(44)
	F.preview:SetTextSize(14)      -- the line you are about to send: easy to read

	-- Losing focus is what saves an edit (see the handler above), so a send the user
	-- clicks releases the box first.
	M.CommitPreview = function()
		if F.preview and F.preview.edit and F.preview.edit:HasFocus() then
			F.preview.edit:ClearFocus()
		end
	end


	F.sendBtn = menu(W.Button(p, "Send once", "primary"):Size(102, 28))
	F.sendBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -40, -6)
	F.sendBtn:OnClick(function() M.SendNow() end)
	F.sendBtn:Tooltip("Post the line once, right now, in General and Global.\nSTART spamming (top right) repeats it: General, then Global 30s later, each every 45s.")

	-- Rebuild: a square button with a circular arrow, beside Send once. Used now
	-- and then, so it gets an icon rather than a second full-width button.
	F.resetBtn = W.Button(p, "", nil):Size(30, 28)
	F.resetBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -6, -6)
	local rIcon = F.resetBtn:CreateTexture(nil, "OVERLAY")
	rIcon:SetSize(20, 20); rIcon:SetPoint("CENTER")
	rIcon:SetTexture("Interface\\AddOns\\Okanvil\\Media\\icon-refresh")   -- our own gold arrow
	F.resetBtn:OnClick(function()
		local d = db()
		-- Release the box FIRST. With the cursor still in it the refresh below
		-- would not redraw it, and the next focus-lost saved the old text as a
		-- hand-edit again -- Rebuild looked like it did nothing.
		if F.preview and F.preview.edit and F.preview.edit:HasFocus() then
			F.preview.edit:ClearFocus()
		end
		d.useCustom = false
		d.custom = ""
		M.RefreshUI()
	end)
	F.resetBtn:Tooltip("Rebuild\nThrow away your hand-edits and rebuild the line\nfrom the raid, roles and reserves you picked.\nThis does NOT send anything.")

	F.charCount = W.Text(p, "", "label", "dim")
	F.charCount:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -38)
end

-- ------------------------------------------------------------
-- Reserve strip (main page): the loot categories, as toggles.
-- Specific hard-reserved ITEMS still live in the Reserves tab -- they need a
-- text box and a list, which does not fit a one-line strip.
-- ------------------------------------------------------------
local function buildReserveStrip(p)
	local d = db()
	F.resBtns = {}

	local lbl = W.Text(p, "|cff8a8d93Reserve|r", "body", "dim")
	lbl:SetPoint("LEFT", 6, 0)

	-- Width per label, not one fixed size: "Fragments" needs ~72px while "Key"
	-- needs 46, and a single width either clipped the long ones or wasted the row.
	-- The chips start after the MEASURED label: Text size grows it past any fixed x.
	local x0 = math.max(56, 6 + math.ceil(lbl:GetStringWidth() or 0) + 10)
	for _, c in ipairs(M.ReserveCats) do
		local b = menu(W.Button(p, c.label, nil):Size(46, 24))
		-- MEASURE the rendered label instead of guessing from the character count:
		-- the font is proportional, so "Fragments" and "Shards" are nowhere near
		-- len*N apart. F.layoutRes advances by the width we actually set, or a wide
		-- button is overlapped by the next one.
		local tw = (b.text and b.text:GetStringWidth()) or 0
		b:SetWidth(math.max(46, tw + 16))
		b:OnClick(function()
			pickTakesOver()
			d.reserve[c.key] = (not d.reserve[c.key]) or nil
			if d.reserve[c.key] then d.reserveNone = false end
			M.RefreshUI()
		end)
		if c.letter then
			b:Tooltip(c.label .. "\nGoes in the line as |cffffd200" .. c.letter .. "|r (the usual letter).")
		else
			b:Tooltip(c.label .. "\nSpelled out -- this one has no conventional letter.")
		end
		F.resBtns[c.key] = b
	end

	-- The rest of the categories, the HR/GBid word and specific items live in
	-- the "more" window; this strip only carries what is in use.
	F.resMoreBtn = menu(W.Button(p, "+ more", nil):Size(66, 24))
	F.resMoreBtn:OnClick(function() M.OpenReserves() end)
	F.resMoreBtn:Tooltip("Other loot to reserve, and specific items.")

	F.resNoneBtn = menu(W.Button(p, "no res", nil):Size(66, 24))
	F.resNoneBtn:OnClick(function()
		pickTakesOver()
		d.reserveNone = not d.reserveNone
		-- "no res" means NOTHING is reserved, so it drops the reserved categories
		-- AND any reserved item. Clearing only the categories left the strip showing
		-- "no res" beside "+1 item" -- two claims that cannot both be true.
		if d.reserveNone then
			d.reserve = {}
			d.reserveItems = {}
		end
		M.RefreshUI()
	end)
	F.resNoneBtn:Tooltip("Advertise that nothing is reserved.\nFills pugs faster than leaving people to ask.\n\nTurning this on drops any reserved item.")

	-- HR or GBid: the word the reserved ITEMS go out under. Two different
	-- promises -- HR keeps the drop, GBid puts it to a gold bid among the raid --
	-- so the leader picks which one the spam claims.
	F.resTagBtn = menu(W.Button(p, "HR", nil):Size(56, 24))
	F.resTagBtn:OnClick(function()
		d.reserveTag = (d.reserveTag == "gbid") and "hr" or "gbid"
		M.RefreshUI()
	end)
	F.resTagBtn:Tooltip("How reserved items are announced.\n\n"
		.. "|cffe0b860HR|r -- the leader keeps the drop.\n"
		.. "|cffe0b860GBid|r -- it goes to a gold bid among the raid.")

	-- how many specific items are hard-reserved (they are set in the "more" window)
	F.resItemTag = W.Text(p, "", "label", "dim")

	-- Lay the strip out left to right: the three everyday categories always, any
	-- other one only while it is on, then "+ more", "no res", the HR/GBid word
	-- (only with reserved items) and the item count.
	local COMMON = { boe = true, orb = true, pattern = true }
	function F.layoutRes()
		local d2 = db()
		local x = x0
		for _, c in ipairs(M.ReserveCats) do
			local b = F.resBtns[c.key]
			b:ClearAllPoints()
			if COMMON[c.key] or d2.reserve[c.key] then
				b:SetPoint("LEFT", x, 0); b:Show()
				x = x + b:GetWidth() + 4
			else
				b:Hide()
			end
		end
		F.resMoreBtn:ClearAllPoints(); F.resMoreBtn:SetPoint("LEFT", x + 2, 0)
		x = x + 2 + F.resMoreBtn:GetWidth() + 10
		F.resNoneBtn:ClearAllPoints(); F.resNoneBtn:SetPoint("LEFT", x, 0)
		x = x + F.resNoneBtn:GetWidth() + 6
		F.resTagBtn:ClearAllPoints(); F.resTagBtn:SetPoint("LEFT", x, 0)
		if F.resTagBtn:IsShown() then x = x + F.resTagBtn:GetWidth() + 6 end
		F.resItemTag:ClearAllPoints(); F.resItemTag:SetPoint("LEFT", x, 0)
	end
end

-- ------------------------------------------------------------
-- Loot tab: what the raid reserves
-- ------------------------------------------------------------

-- The difficulty token the loot table uses for what is picked on the main page:
-- "10n" / "25n" / "10h" / "25h".
local function currentMode()
	local d = db()
	return tostring(d.size or 25) .. (d.hc and "h" or "n")
end

-- Every item that drops in the SELECTED raid at the SELECTED difficulty, flattened
-- to a list of rows: a boss header, then its items. `filter` narrows by name.
--
-- Rebuilt on each refresh rather than cached: it is a walk over one raid's table
-- (a few hundred entries, already in memory) and caching it would need
-- invalidating on every raid/size/difficulty change, which is most of the page.
local function lootRows(filter)
	local d = db()
	local raid = OkanvilRaidLoot and OkanvilRaidLoot[d.raid]
	if not raid then return nil end

	local mode = currentMode()
	filter = (filter or ""):lower()

	local rows = {}
	for _, b in ipairs(raid) do
		local hits = {}
		for _, it in ipairs(b.items or {}) do
			-- `m` is a comma list ("10n,25h"); plain find is enough because the
			-- tokens are fixed-width and cannot be a prefix of one another.
			if it.m and it.m:find(mode, 1, true) then
				if filter == "" or it.name:lower():find(filter, 1, true) then
					hits[#hits + 1] = it
				end
			end
		end
		if #hits > 0 then
			rows[#rows + 1] = { boss = b.boss }
			for _, it in ipairs(hits) do rows[#rows + 1] = { item = it } end
		end
	end
	return rows
end


-- ------------------------------------------------------------
-- Reserves tab -- TWO COLUMNS: what the raid drops on the left, what you are
-- reserving on the right. Click an item to send it across.
--
-- The old version was one paged table (14 rows, "page 1/9"): browsing a raid
-- meant clicking through nine pages, and what you had already reserved was
-- somewhere further down the tab, out of sight while you picked. Two scrolling
-- lists side by side show both halves of the job at once.
-- ------------------------------------------------------------
-- Readable first: the list scrolls, so cramming more rows in is not worth
-- squinting at a wall of purple item names to find the one you want.
--
-- HEIGHT and STEP are separate. The row frame is the icon's height; the step is
-- that plus a gap, so consecutive icons do not touch. Advancing by the height
-- alone stacked them edge to edge and the list read as one solid block.
local LOOT_ROW_H = 24
local LOOT_ROW_STEP = LOOT_ROW_H + 5
-- Where the item name starts. ONE constant because two places set it -- the row
-- builder and the refresh that re-anchors it for boss headers -- and they drifted:
-- the refresh still used the offset from when the icon was 14px, so the name sat
-- on top of an 18px icon.
local LOOT_ICON = 18
local LOOT_TEXT_X = 5 + LOOT_ICON + 8

-- One scrolling list: returns the scroll child to draw rows into, plus a
-- relayout() to call once the content height is known.
local makeList = W.ScrollList

-- A pooled row. `side` decides which way the arrow points.
local function lootRow(pool, i, parent, side)
	local row = pool[i]
	if row then return row end

	row = W.Frame(parent, "bare")
	row:SetHeight(LOOT_ROW_H)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(LOOT_ICON, LOOT_ICON)
	row.icon:SetPoint("LEFT", 5, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.text = W.Text(row, "", "head")
	row.text:SetPoint("LEFT", LOOT_TEXT_X, 0)
	row.text:SetPoint("RIGHT", -6, 0)
	row.text:SetJustifyH("LEFT")
	if row.text.SetWordWrap then row.text:SetWordWrap(false) end

	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(); hl:SetTexture(FLAT)
	hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.15)

	-- The whole row is the button: clicking anywhere moves the item to the other
	-- column. A 20px [+] to aim at was the fiddliest part of the old list.
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		if not self._link then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self._link)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self)
		if self._link and IsShiftKeyDown() and ChatEdit_InsertLink then
			ChatEdit_InsertLink(self._link)     -- shift-click still links to chat
			return
		end
		if self._go then self._go() end
	end)

	pool[i] = row
	return row
end

local function buildLoot(p)
	local d = db()
	local X = 4

	label(p, "Click an item to reserve it. Click it again on the right to drop it.", X, -6)

	F.lootFilter = ""
	F.lootSearch = W.EditBox(p)
	F.lootSearch:SetSize(300, 22)
	F.lootSearch:SetPoint("TOPLEFT", X, -28)
	local ghost = W.Text(F.lootSearch, "|cff777777search the raid's loot...|r", "label", "dim")
	ghost:SetPoint("LEFT", 6, 0)
	F.lootSearch.edit:SetScript("OnTextChanged", function(s)
		local t = s:GetText() or ""
		ghost:SetShown(t == "")
		F.lootFilter = t
		if M.RefreshLootList then M.RefreshLootList() end
	end)

	F.lootScope = W.Text(p, "", "label", "dim")
	F.lootScope:SetPoint("LEFT", F.lootSearch, "RIGHT", 10, 0)

	-- Column headers, then the two lists under them. Widths are proportional so the
	-- pair fills whatever the tab page is given.
	F.lootHdrL = W.Text(p, "|cff8a8d93DROPS IN THIS RAID|r", "label", "dim")
	F.lootHdrL:SetPoint("TOPLEFT", X + 4, -58)
	F.lootHdrR = W.Text(p, "|cffe0b860RESERVED|r", "label", "dim")

	local card, child, relayout = makeList(p, X, 300, -74, 6)
	F.lootCard, F.lootChild, F.lootRelayout = card, child, relayout
	F.lootPool = {}

	local rcard, rchild, rrelayout = makeList(p, X + 310, 240, -74, 6)
	F.resCard, F.resChild, F.resRelayout = rcard, rchild, rrelayout
	F.resPool = {}

	-- Both cards are anchored by a fixed x/width, but the page width is only known
	-- once the tab is shown -- so re-spread them whenever it changes.
	p:SetScript("OnSizeChanged", function(self)
		local w = self:GetWidth() or 560
		local gap, pad = 10, X
		local lw = math.floor((w - gap - pad * 2) * 0.60)
		local rw = w - gap - pad * 2 - lw
		F.lootCard:SetWidth(lw)
		F.resCard:ClearAllPoints()
		F.resCard:SetPoint("TOPLEFT", pad + lw + gap, -74)
		F.resCard:SetPoint("BOTTOM", self, "BOTTOM", 0, 6)
		F.resCard:SetWidth(rw)
		F.lootHdrR:ClearAllPoints()
		F.lootHdrR:SetPoint("TOPLEFT", pad + lw + gap + 4, -58)
		if M.RefreshLootList then M.RefreshLootList() end
	end)

	-- No manual "Add" box: the list covers every raid AtlasLoot knows, and clicking
	-- a row is the whole interaction. A second input next to the search only raised
	-- the question of which one to type in.
	--
	-- Shift-clicking an item link straight into the SEARCH box still works, so an
	-- item you are holding is one shift-click and one row-click away.
	if not F._linkHooked and hooksecurefunc then
		F._linkHooked = true
		hooksecurefunc("ChatEdit_InsertLink", function(link)
			local box = F.lootSearch and F.lootSearch.edit
			if not (box and box:HasFocus() and link) then return end
			box:SetText(link:match("|h%[(.-)%]|h") or link)
		end)
	end

	if M.RefreshLootList then M.RefreshLootList() end
end

-- Paint BOTH columns. Split out from RefreshUI because typing in the search box
-- must redraw only this -- a full refresh fights the edit box for focus on every
-- keystroke.
function M.RefreshLootList()
	if not (F and F.lootChild) then return end
	local d = db()

	-- ---- right column: what is reserved -------------------------------------
	local items = d.reserveItems or {}
	local reserved = {}
	for _, v in ipairs(items) do
		reserved[v] = true
		local nm = v:match("|h%[(.-)%]|h")
		if nm then reserved[nm] = true end        -- match a link against a stored name
	end

	for _, r in ipairs(F.resPool) do r:Hide() end
	local ry = 2
	for i, v in ipairs(items) do
		local row = lootRow(F.resPool, i, F.resChild, "right")
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -ry); row:SetPoint("RIGHT", F.resChild, "RIGHT", 0, 0)
		row:Show()

		local isLink = v:find("|Hitem:") ~= nil
		local nm = v:match("|h%[(.-)%]|h") or v
		local id = tonumber(v:match("item:(%d+)"))
		local icon = id and GetItemIcon and GetItemIcon(id)
		if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end
		row.text:SetText(isLink and v or ("|cffdcddde" .. nm .. "|r"))
		row._link = isLink and v or nil
		local idx = i
		row._go = function() M.RemoveReserveItem(idx); M.RefreshUI() end
		ry = ry + LOOT_ROW_STEP
	end
	F.resRelayout(ry)

	-- ---- left column: the raid's loot table ---------------------------------
	local rows = lootRows(F.lootFilter)

	local raidName = ""
	for _, r in ipairs(OkanvilRaids or {}) do
		if r.key == d.raid then raidName = r.short or r.name end
	end
	local modeLabel = tostring(d.size or 25) .. (d.hc and " HC" or " NM")

	for _, r in ipairs(F.lootPool) do r:Hide() end

	if not rows then
		local row = lootRow(F.lootPool, 1, F.lootChild, "left")
		row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -2)
		row:SetPoint("RIGHT", F.lootChild, "RIGHT", 0, 0); row:Show()
		row.icon:Hide(); row._link = nil; row._go = nil
		row.text:SetText("|cff8a8d93No loot table for " .. raidName .. " -- use the Add box.|r")
		F.lootScope:SetText("")
		F.lootRelayout(LOOT_ROW_STEP + 4)
		return
	end

	F.lootScope:SetText("|cffe0b860" .. raidName .. " " .. modeLabel .. "|r")

	local n, y = 0, 2
	for _, e in ipairs(rows) do
		n = n + 1
		local row = lootRow(F.lootPool, n, F.lootChild, "left")
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y); row:SetPoint("RIGHT", F.lootChild, "RIGHT", 0, 0)
		row:Show()

		if e.boss then
			row.icon:Hide()
			row.text:ClearAllPoints()
			row.text:SetPoint("LEFT", 4, 0); row.text:SetPoint("RIGHT", -6, 0)
			row.text:SetText("|cffc0943a" .. e.boss .. "|r")
			row._link, row._go = nil, nil
		else
			local it = e.item
			-- The REAL link when the client has the item cached: the row then carries
			-- the item's own rarity colour and its tooltip. GetItemInfo returns nil
			-- for an id this character has never seen -- fall back to the stored name.
			local inm, link, rarity = GetItemInfo(it.id)
			local already = reserved[it.name] or (link and reserved[link]) or false

			row.text:ClearAllPoints()
			row.text:SetPoint("LEFT", LOOT_TEXT_X, 0); row.text:SetPoint("RIGHT", -6, 0)

			local icon = GetItemIcon and GetItemIcon(it.id)
			if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end

			local q = rarity and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[rarity]
			local label = (q and q.hex or "|cffdcddde") .. (inm or it.name) .. "|r"
			if it.slot ~= "" then label = label .. " |cff6f7176" .. it.slot .. "|r" end
			if already then label = "|cff7cfc8a>|r " .. label end
			row.text:SetText(label)

			row._link = link
			row._go = function()
				-- Reserve the LINK when we have one, so the reserved column can colour
				-- it and show a tooltip. Already there -> clicking takes it back off.
				local want = link or it.name
				if already then
					for idx, v in ipairs(d.reserveItems or {}) do
						if v == want or v == it.name then M.RemoveReserveItem(idx); break end
					end
				else
					M.AddReserveItem(want)
				end
				M.RefreshUI()
			end
		end
		y = y + LOOT_ROW_STEP
	end

	if n == 0 then
		local row = lootRow(F.lootPool, 1, F.lootChild, "left")
		row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -2)
		row:SetPoint("RIGHT", F.lootChild, "RIGHT", 0, 0); row:Show()
		row.icon:Hide(); row._link, row._go = nil, nil
		row.text:SetText("|cff8a8d93No match.|r")
		y = y + LOOT_ROW_STEP
	end

	F.lootRelayout(y)
end

-- ------------------------------------------------------------
-- Refresh
-- ------------------------------------------------------------
function M.RefreshPreview()
	if not F or not F.preview then return end
	local d = db()
	local msg = M.Outgoing()
	-- Never overwrite what someone is actively typing. `previewShown` remembers the
	-- text we last PUT in the box, so the focus-lost handler can tell "they typed
	-- something" from "they just clicked in and out".
	if not F.preview.edit:HasFocus() then
		F.preview:SetText(msg)
		F.previewShown = msg
	end
	-- Hand-edited text: the rebuild button lights up gold and the count says so,
	-- instead of a whole line of explanation under the box.
	local edited = d.useCustom and d.custom ~= ""
	if F.resetBtn then F.resetBtn:SetKind(edited and "primary" or nil) end
	-- 255 is the chat hard limit; show it before the server truncates.
	local n = #msg
	local tag = edited and "|cffe0b860edited|r  " or ""
	if n > 255 then
		F.charCount:SetText(tag .. "|cffff5555" .. n .. "/255|r")
	else
		F.charCount:SetText(tag .. "|cff8a8d93" .. n .. "/255|r")
	end
end

function M.RefreshUI()
	if not F then return end
	local d = db()

	-- ---- top strip ----
	if F.raidDD then F.raidDD:refreshText() end
	local info
	for _, r in ipairs(OkanvilRaids or {}) do if r.key == d.raid then info = r end end
	if F.size10 then
		local voa = d.raid == "voa"
		if not voa and d.classRun then d.classRun = false end
		F.size10:SetKind((d.size == 10 and not d.classRun) and "primary" or nil)
		F.size25:SetKind((d.size == 25 and not d.classRun) and "primary" or nil)
		if F.size18 then
			if voa then F.size18:Show() else F.size18:Hide() end
			F.size18:SetKind(d.classRun and "primary" or nil)
		end
		-- Lay the strip out left to right in groups: sizes (18 only in VoA), then
		-- difficulty (only where there is a heroic), then the gearscore. Nothing
		-- leaves a gap when it is hidden.
		local canHC = info and info.hc
		local x = 4 + 220 + 12
		for _, b in ipairs({ F.size10, F.size25, voa and F.size18 or nil }) do
			b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, -5); x = x + 44 + 2
		end
		x = x + 10
		if canHC then
			F.diffBtn:ClearAllPoints(); F.diffBtn:SetPoint("TOPLEFT", x, -5); F.diffBtn:Show()
			F.diffHC:ClearAllPoints(); F.diffHC:SetPoint("TOPLEFT", x + 72, -5); F.diffHC:Show()
			F.diffBtn:SetKind((not d.hc) and "primary" or nil)
			F.diffHC:SetKind(d.hc and "primary" or nil)
			x = x + 72 + 70 + 12
		else
			F.diffBtn:Hide(); F.diffHC:Hide()
		end
		local lw = math.ceil(F.gsLabel:GetStringWidth() or 38)
		F.gsBox:ClearAllPoints(); F.gsBox:SetPoint("TOPLEFT", x + lw + 6, -5)
	end
	if F.gsBox and not F.gsBox.edit:HasFocus() then F.gsBox.edit:SetText(d.gs or "") end

	-- ---- roster + board ----
	local list = M.RosterList()
	local have = {}
	for _, r in ipairs(ROLES) do have[r] = 0 end
	local buckets = {}
	for _, r in ipairs(ROLES) do buckets[r] = {} end

	for _, pl in ipairs(list) do
		-- A HAND placement always wins -- that is the leader's decision and nothing
		-- may undo it. Failing that, use what the inspect read: reading specs and
		-- then leaving everyone where they were is the scan doing half its job.
		local assigned = M.AssignedRole(pl.name) or M.GuessRole(pl.name, pl.class)

		-- A hybrid nobody has inspected has no role at all now. Rather than drop
		-- them off the board, park them in the column their class most often
		-- plays and MARK it -- an uninspected resto shaman sitting silently in
		-- Ranged is how "4 Heal" went out while three healers were in the raid.
		local guessed = false
		if not assigned then
			assigned = HYBRID_PARK[pl.class or ""] or "ranged"
			guessed = true
		elseif not M.RoleIsKnown(pl.name, pl.class) then
			guessed = true
		end

		if buckets[assigned] then
			pl.guessed = guessed
			buckets[assigned][#buckets[assigned] + 1] = pl
			-- A GUESS COUNTS. It used to be left out, on the reasoning that
			-- advertising for healers you already have is worse than advertising
			-- for none -- but the column header counts every row it draws, so a
			-- full column read "9/9" while the LFM line still asked for two more.
			-- Asking for players you already have, in front of the whole server,
			-- is the worse of the two: a guessed ranged is still a body in the
			-- raid, and the leader can move them by hand if the guess is wrong.
			have[assigned] = (have[assigned] or 0) + 1
		end
	end

	if F.cols then
		for _, key in ipairs(COLS) do
			local col = F.cols[key]
			local members = buckets[key] or {}
			for i, row in ipairs(col.rows) do
				local pl = members[i]
				if pl then
					row._name = pl.name
					row._class = pl.class
					row._sub = pl.class or nil
					local txt = class_color(pl.class) .. pl.name .. "|r"
					if pl.online == false then txt = "|cff5a5a5a" .. pl.name .. "|r" end
					-- A guessed row is flagged in the name itself: this column is
					-- where the class usually plays, not where this player does.
					if pl.guessed then txt = txt .. " |cffe0b860?|r" end
					row.text:SetText(txt)
					-- Second line: what they are and how geared, from whichever source
					-- knows -- an inspect if we have one, otherwise whatever they said
					-- in their whisper. Blank when neither knows, rather than padded
					-- with "unknown".
					local sub = M.SubLabel and M.SubLabel(pl.name) or ""
					if pl.guessed and sub == "" then
						local I = Okanvil.Inspect
						sub = (I and I.Watching and I.Watching(pl.name))
							and "|cffe0b860spec not read -- reads when near|r"
							or "|cffe0b860spec not read|r"
					end
					row.sub:SetText("|cff8a8d93" .. sub .. "|r")
					-- A pending applicant gets a gold edge: it is the difference between
					-- someone you HAVE and someone you could invite, and the two sit in
					-- the same board.
					row._pending = pl.pending
					-- The card's edge is the player's CLASS -- a druid is orange, a
					-- rogue yellow -- so a column can be read as colour before it is
					-- read as text.
					--
					-- Pending is carried by ALPHA rather than a different colour: a gold
					-- border for applicants would have meant the edge said two unrelated
					-- things and neither reliably. Bright edge = still to invite, faint
					-- edge = already yours.
					local cc = RAID_CLASS_COLORS and pl.class and RAID_CLASS_COLORS[pl.class]
					-- Remembered on the row so hover can brighten it and OnLeave can put
					-- it back -- otherwise moving the mouse across the board repaints
					-- every card it touches grey.
					if cc then
						row._edge = { cc.r, cc.g, cc.b, pl.pending and 0.95 or 0.45 }
					else
						row._edge = { C.border[1], C.border[2], C.border[3], pl.pending and 0.95 or 1 }
					end
					row:SetBackdropBorderColor(row._edge[1], row._edge[2], row._edge[3], row._edge[4])
					row:Show()
				else
					row._name = nil
					row._class = nil
					-- clear the flag too: a pooled row reused for someone already in the
					-- group would otherwise still think it was an applicant, and a click
					-- would invite instead of opening the conversation
					row._pending = nil
					row._edge = nil
					row:Hide()
				end
			end
			local n = #members
			local want = tonumber(d.need[key]) or 0
			-- Count the rows we are ACTUALLY drawing, not a parallel tally. The
			-- header used to say "6/8" over five names, because `have` and the
			-- column were filled by different rules -- one counted the whole
			-- roster, the other only what fit in a column.
			col.count:SetText(n .. "|cff8a8d93/" .. want .. "|r")
			-- The column scrolls, so "+N more" is only for what BOARD_ROWS itself
			-- cannot hold -- the pooled rows are the hard limit, not the height.
			local overflow = n - BOARD_ROWS
			col.more:SetText(overflow > 0 and ("|cff8a8d93+" .. overflow .. " more|r") or "")
			if col.sf and col.sb and col.child then
				local drawn = math.min(n, BOARD_ROWS)
				local h = math.max(1, drawn * (BOARD_ROW_H + 3))
				col.child:SetHeight(h)
				local maxs = math.max(0, h - col.sf:GetHeight())
				col.sb:SetMinMaxValues(0, maxs)
				col.sb:SetShown(maxs > 4)
				if col.sb:GetValue() > maxs then col.sb:SetValue(maxs) end
			end
		end
	end

	-- ---- VoA 18 board: replaces the role columns while the run is on ----
	if F.voaGrid then
		for _, key in ipairs(COLS) do
			local fr = F.cols and F.cols[key] and F.cols[key].frame
			if fr then if d.classRun then fr:Hide() else fr:Show() end end
		end
		if d.classRun then
			F.voaGrid:Show()
			local places, unplaced = M.VoABoard()
			for i, card in ipairs(F.voaCards) do
				local pc = places[i]
				if pc then
					local def, who = pc.def, pc.who
					local cc = def.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[def.class]
					card.title:SetText(def.tank and "|cff5fa8ffTank|r"
						or (class_color(def.class) .. def.label .. "|r"))
					card._tipTitle = def.label
					card._tip = nil
					card._key = def.key
					card._empty = not who
					card._hand = who and M.VoAHandPlaced(who.name) == def.key and who.name or nil
					if who then
						card.name:SetText(class_color(who.class) .. who.name .. "|r")
						card.sub:SetText(M.SubLabel and M.SubLabel(who.name) or "")
						if #pc.dupes > 0 then
							-- a second raider on the same set rolls against the first:
							-- name them on the card, with spec and gear when there is
							-- room for one, names only when there are several
							local dup
							if #pc.dupes == 1 then
								local dp = pc.dupes[1]
								local ds = M.SubLabel and M.SubLabel(dp.name) or ""
								dup = class_color(dp.class) .. dp.name .. "|r"
									.. (ds ~= "" and ("  |cff8a8d93" .. ds .. "|r") or "")
							else
								local names = {}
								for _, dp in ipairs(pc.dupes) do names[#names + 1] = class_color(dp.class) .. dp.name .. "|r" end
								dup = table.concat(names, "|cff6f7176, |r")
							end
							card.dup:SetText("|cffff5555same set:|r " .. dup)
							card._tip = { who.name }
							for _, dp in ipairs(pc.dupes) do card._tip[#card._tip + 1] = dp.name end
						else
							card.dup:SetText("")
						end
						local e = cc or { r = 0.37, g = 0.66, b = 1 }
						card:SetBackdropBorderColor(e.r, e.g, e.b, #pc.dupes > 0 and 1 or 0.55)
					elseif d.voaAsk and d.voaAsk[def.key] then
						card.name:SetText("|cffe0b860asking|r")
						card.sub:SetText("|cff8a8d93in the line|r")
						card.dup:SetText("")
						card:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
					else
						card.name:SetText("|cff5e6166empty|r")
						card.sub:SetText("")
						card.dup:SetText("")
						card:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
					end
					card:Show()
				else
					card:Hide()
				end
			end
			-- hybrids with no spec read yet: a druid could be any of three places
			if #unplaced > 0 then
				local names = {}
				for _, pl in ipairs(unplaced) do names[#names + 1] = class_color(pl.class) .. pl.name .. "|r" end
				F.voaUnplaced:SetText("|cffe0b860Spec not read|r |cff8a8d93(reads when near, or click an empty place):|r "
					.. table.concat(names, "|cff6f7176, |r"))
			else
				F.voaUnplaced:SetText("")
			end
		else
			F.voaGrid:Hide()
		end
	end


	-- ---- reserves / classes / channels (tab pages, may not be built yet) ----
	if F.resBtns then
		for key, b in pairs(F.resBtns) do b:SetKind(d.reserve[key] and "primary" or nil) end
	end
	if F.moreResBtns then
		for key, b in pairs(F.moreResBtns) do b:SetKind(d.reserve[key] and "primary" or nil) end
	end
	if F.resNoneBtn then F.resNoneBtn:SetKind(d.reserveNone and "primary" or nil) end
	if F.resItemTag then
		local n = #(d.reserveItems or {})
		F.resItemTag:SetText(n > 0 and ("|cffe0b860+" .. n .. " item" .. (n > 1 and "s" or "") .. "|r") or "")
		-- The HR/GBid switch only means something when there ARE reserved items,
		-- so it is hidden rather than sitting there claiming something about
		-- nothing.
		if F.resTagBtn then
			if n > 0 then
				F.resTagBtn:Show()
				F.resTagBtn:SetKind(d.reserveTag == "gbid" and "primary" or nil)
				F.resTagBtn.text:SetText(d.reserveTag == "gbid" and "GBid" or "HR")
			else
				F.resTagBtn:Hide()
			end
		end
	end
	if F.layoutRes then F.layoutRes() end
	-- (the reserved list is the RIGHT column of the "more" window;
	--  M.RefreshLootList below paints both columns)
	if F.classRunTag then
		if d.classRun then
			local miss = M.ClassesMissing()
			local names = {}
			for _, c in ipairs(miss) do names[#names + 1] = c.short end
			F.classRunTag:SetText(#names > 0
				and ("|cffff5555still need|r " .. table.concat(names, ", "))
				or "|cff7cfc8aall nine classes covered|r")
		else
			F.classRunTag:SetText("")
		end
	end
	-- the Ask-for chips in each column
	for key, c in pairs(F.cols or {}) do
		if c.chips then
			local picks = M.RolePicks(key)
			for _, b in ipairs(c.chips) do c.paintChip(b, picks[b._token] and true or false) end
			if c.reflow then c.reflow() end
		end
	end
	-- (the spec row, the channel box, auto-reply and the presets lived on the
	-- "More" page, which is gone -- nothing builds those widgets any more)

	M.RefreshPreview()
	-- the browse list is scoped to the picked raid + difficulty, so it has to
	-- follow a change to either
	if M.RefreshLootList then M.RefreshLootList() end

	if F.dash then F.dash:Refresh() end
end

-- The "more" window: every reserve category, and the item browser that was the
-- Reserves tab. Built once on first open; opened from "+ more" on the strip.
function M.OpenReserves()
	if F.moreWin then
		if F.moreWin:IsShown() then F.moreWin:Hide() else F.moreWin:Show() end
		return
	end
	local w = Okanvil:Popup("Reserves")
	w:SetSize(600, 470)
	F.moreWin = w
	local d = db()

	local cats = W.Frame(w, "bare")
	cats:SetPoint("TOPLEFT", 10, -34); cats:SetPoint("TOPRIGHT", -10, -34); cats:SetHeight(22)
	F.moreResBtns = {}
	local x = 0
	for _, c in ipairs(M.ReserveCats) do
		local b = W.Button(cats, c.label, nil):Size(46, 20)
		local bw = math.max(46, ((b.text and b.text:GetStringWidth()) or 0) + 16)
		b:SetWidth(bw); b:SetPoint("LEFT", x, 0)
		b:OnClick(function()
			pickTakesOver()
			d.reserve[c.key] = (not d.reserve[c.key]) or nil
			if d.reserve[c.key] then d.reserveNone = false end
			M.RefreshUI()
		end)
		F.moreResBtns[c.key] = b
		x = x + bw + 4
	end

	local body = W.Frame(w, "bare")
	body:SetPoint("TOPLEFT", 6, -62); body:SetPoint("BOTTOMRIGHT", -6, 6)
	buildLoot(body)
	M.RefreshUI()
end

-- ------------------------------------------------------------
-- Whispers panel (W.WhispersPanel, docked to the right): everyone who whispered while
-- the line was running, and whether they were invited, joined or turned it down.
-- ------------------------------------------------------------
local WHISPERS = {
	title = "Whispers",
	subtitle = "Who asked to join",
	status = {
		new      = { "new",      "|cffe0b860" },
		invited  = { "invited",  "|cff4a90d9" },
		joined   = { "joined",   "|cff7cfc8a" },
		declined = { "declined", "|cffe05555" },
		busy     = { "in group", "|cffe05555" },
		offline  = { "offline",  "|cffe05555" },
	},
	-- Two tabs: who is still asking to join, and who is already in the group
	-- (with the gear audit). Mixed in one list they got lost under the spam.
	filters = {
		{ key = "asking", label = "Whispers",
			match = { new = true, invited = true, declined = true, busy = true, offline = true } },
		{ key = "joined", label = "Group", match = { joined = true } },
	},
	emptyHint = "Post your LFM line and everyone who\nasks to join shows up here.",
	items = function()
		local out = {}
		for _, a in ipairs(M.Whispers()) do
			local sub = M.SubLabel(a.name)
			-- a whisper carries no class: once they joined or were inspected, we know it
			local class = a.class
			if not class then
				local I = Okanvil.Inspect
				local _, c = I and I.Get and I.Get(a.name)
				class = c or select(2, UnitClass(a.name))
			end
			out[#out + 1] = { name = a.name, class = class, status = a.status, t = a.t,
				sub = sub ~= "" and sub or "|cff6f7176spec not read|r",
				said = "|cffff80ff" .. (a.said or "") .. "|r",
				-- a "declined" can be asked again
				canInvite = a.status ~= "invited" and a.status ~= "joined",
				badge = M.AuditBadge(a.name), detail = M.AuditDetail(a.name) }
		end
		for _, p in ipairs(M.GroupMembers()) do
			local sub = p.sub or M.SubLabel(p.name)
			out[#out + 1] = { name = p.name, class = p.class, status = "joined", t = p.t,
				sub = sub ~= "" and sub or "|cff6f7176spec not read|r",
				badge = M.AuditBadge(p.name), detail = M.AuditDetail(p.name) }
		end
		return out
	end,
	onInvite = function(name) M.InviteApplicant(name) end,
	onDismiss = function(name) M.DismissApplicant(name) end,
	onClear = function() M.ClearWhispers() end,
	bulk = {
		label = "Invite needed",
		tip = "Invite every new whisperer whose role you still need,\noldest whisper first. Invites already out count.\nPeople whose spec was not read are left to you.",
		onClick = function()
			if M.InviteNeeded() == 0 then
				DEFAULT_CHAT_FRAME:AddMessage("|cffF1C40F[PuG]|r Nobody new fits a role you still need.")
			end
		end,
	},
	hidden = function() return db().whispersHidden end,
	setHidden = function(v) db().whispersHidden = v end,
}

function M.RefreshWhispers()
	if F and F.whispers then F.whispers:Refresh() end
end

-- ------------------------------------------------------------
-- Build
-- ------------------------------------------------------------
function M.BuildUI(parent)
	if F then return end
	F = {}

	local dash = W.Dashboard(parent, {
		title = "PuG",
		icon = (Okanvil.ICONS and Okanvil.ICONS.pug) or "Interface\\Icons\\Ability_Warrior_RallyingCry",
		drawerWidth = 0,          -- one full-width page; the board needs the room
		footerHeight = 0,
		-- the Whispers panel is its own window docked to Okanvil's right edge
		onSecondary = function() M.ToggleWhispers() end,
		secondaryText = function() return "Whispers" end,
		primaryText = function() return M.IsActive() and "STOP spamming" or "START spamming" end,
		primaryKind = function() return M.IsActive() and "primary" or "secondary" end,
		onPrimary = function() M.Toggle(); M.RefreshUI() end,
		statusText = function()
			if M.IsActive() then return "|cff7cfc8aSpamming ON|r" end
			return "|cffff5555Spamming OFF|r"
		end,
		-- No tabs: the Reserves tab is the "+ more" window on the reserve strip.
	})
	F.dash = dash
	-- the header's two buttons, in the page's control size
	if dash.cta then menu(dash.cta):SetSize(160, 28) end
	if dash.cta2 then menu(dash.cta2):SetSize(104, 28) end

	-- A player read by the inspect watch repaints the board, so their row moves
	-- to the right column on its own.
	if Okanvil.Inspect then
		Okanvil.Inspect.onWatchRead = function() M.RefreshUI(); M.RefreshWhispers() end
	end
	if Okanvil.Audit then
		Okanvil.Audit.onRead = function() M.RefreshWhispers() end
	end

	-- The Whispers window. Parented to the PuG page so it shows and hides with
	-- it (and with Okanvil), docked outside the main window so the board keeps
	-- its full width.
	F.whispers = W.WhispersPanel(parent, WHISPERS)
	function M.ToggleWhispers()
		F.whispers:Toggle()
		dash:Refresh()
	end

	-- The single page is stacked inside dash.main: top strip, needs, board, bottom.
	local main = dash.main

	-- Every strip is a REAL panel ("dark"), not a transparent one. The shared rat
	-- art is drawn on the content well above its own fill, so anything transparent
	-- lets the art through and the text sits on top of a picture. Solid strips keep
	-- the rat where it belongs -- behind the page, visible only in empty space.
	local top = W.Frame(main, "well")
	top:SetPoint("TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", 0, 0)
	top:SetHeight(36)
	buildTopStrip(top)

	-- No needs strip. Each column header carries its own count, target and
	-- stepper now, so a 52px band repeating them above the board was the same
	-- facts twice -- and it was taking the space from the thing it described.

	-- Reserves and classes stay ON the page: picking "need a rogue" is the common
	-- ask and burying it behind a tab made it slower, not cleaner. The SPEC row is
	-- the one that goes -- asking for a HOLY paladin specifically is rare, and
	-- twelve more buttons was what made this strip unreadable.
	-- The class asks live in the columns now (see ASKS), so the reserves strip is
	-- the page's last row and the board gets the height the Want row took.
	local resStrip = W.Frame(main, "well")
	resStrip:SetPoint("BOTTOMLEFT", 0, 0)
	resStrip:SetPoint("BOTTOMRIGHT", 0, 0)
	resStrip:SetHeight(30)
	buildReserveStrip(resStrip)

	local bottom = W.Frame(main, "well")
	bottom:SetPoint("BOTTOMLEFT", resStrip, "TOPLEFT", 0, 3)
	bottom:SetPoint("BOTTOMRIGHT", resStrip, "TOPRIGHT", 0, 3)
	bottom:SetHeight(56)
	buildBottom(bottom)

	-- the board takes every pixel between the top strip and the message
	local board = W.Frame(main, "bare")
	board:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -4)
	board:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, -4)
	board:SetPoint("BOTTOM", bottom, "TOP", 0, 4)
	buildBoard(board)

	M.RefreshUI()
end

-- Keep the board honest: people joining/leaving changes the columns and therefore
-- the line being spammed.
local ev = CreateFrame("Frame")
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
ev:SetScript("OnEvent", Okanvil:CombatSafe("pug.board", function()
	if F then M.RefreshUI() end
end))
