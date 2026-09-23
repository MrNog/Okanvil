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
-- must not be overwritten. But then every raid / size / need / Reserve / Want /
-- Spec control silently stopped doing anything, and the only way back was a
-- Rebuild button you had to know existed. Clicking a pick IS the statement
-- "build it from my picks", so it takes control back by itself and the
-- dead-button state cannot happen.
--
-- The hand-typed text is kept in d.custom (just no longer used), so nothing the
-- user wrote is destroyed by a stray click -- and `gs` / `note`, which are typed
-- rather than picked, deliberately do NOT call this.
--
-- Declared up here, above the first builder that uses it: a `local` is only in
-- scope AFTER its declaration, so defining it further down would leave the top
-- strip calling a nil global.
-- ------------------------------------------------------------
local function pickTakesOver()
	local d = db()
	if d.useCustom then d.useCustom = false end
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
	F.raidDD:SetSize(186, 22)
	F.raidDD:SetPoint("TOPLEFT", 4, -4)

	F.size10 = W.Button(p, "10", nil):Size(34, 22):Point("TOPLEFT", 196, -4)
	F.size25 = W.Button(p, "25", nil):Size(34, 22):Point("TOPLEFT", 232, -4)
	F.size10:OnClick(function() pickTakesOver(); d.size = 10; M.ApplySizeComp(); M.RefreshUI() end)
	F.size25:OnClick(function() pickTakesOver(); d.size = 25; M.ApplySizeComp(); M.RefreshUI() end)

	F.diffBtn = W.Button(p, "Normal", nil):Size(70, 22):Point("TOPLEFT", 270, -4)
	F.diffBtn:OnClick(function() pickTakesOver(); d.hc = not d.hc; M.RefreshUI() end)
	F.diffBtn:Tooltip("Normal / Heroic.\nStays on Normal for raids with no heroic mode.")

	-- "min gs" is ~38px at font 12, so the box has to start past 350+38 or the
	-- label runs into it.
	label(p, "min gs", 352, -9)
	F.gsBox = W.EditBox(p):Size(56, 22):Point("TOPLEFT", 398, -4)
	F.gsBox.edit:SetScript("OnTextChanged", function(s) d.gs = s:GetText() or ""; M.RefreshPreview() end)

	-- A free-text tail, back on the strip.
	--
	-- It was taken off on the grounds that every ask has its own control. That
	-- was wrong for the things no control covers -- "Gbid DC", "link achieve",
	-- "no dc" -- and the only way left to say them was hand-editing the line,
	-- which Rebuild then threw away along with the edit.
	--
	-- Living in db.note means the builder appends it to every generated line, so
	-- Rebuild keeps it and Send carries it.
	local noteLbl = W.Text(p, "say", "label", "dim")
	noteLbl:SetPoint("TOPLEFT", 462, -9)
	F.noteBox = W.EditBox(p):Size(120, 22):Point("TOPLEFT", 486, -4)
	F.noteBox.edit:SetScript("OnTextChanged", function(s)
		d.note = s:GetText() or ""
		M.RefreshPreview()
	end)
	F.noteBox:Tooltip("Tacked onto the end of every line -- \"Gbid DC\", \"link achieve\".\nSurvives Rebuild, unlike editing the line by hand.")

	-- Read everyone's actual spec instead of guessing from class. Without this the
	-- board files every paladin the same way and the leader sorts 25 people by hand,
	-- remembering who heals. Explicit button, not automatic: inspecting the whole
	-- raid is a burst of server traffic and should happen when asked for.
	F.scanBtn = W.Button(p, "Read specs", nil):Size(96, 22):Point("TOPLEFT", 616, -4)
	F.scanBtn:OnClick(function()
		local I = Okanvil.Inspect
		if not (I and I.ScanGroup) then
			Okanvil:Print("|cffff5555Inspect module not loaded.|r")
			return
		end
		if I.IsScanning and I.IsScanning() then
			Okanvil:Print("Already scanning...")
			return
		end
		I.onProgress = function(done, total)
			if F and F.scanBtn and F.scanBtn.text then
				F.scanBtn.text:SetText(done .. "/" .. total)
			end
		end
		-- force = true. Pressing a button called "Read specs" means read them NOW:
		-- the cached answer is days fresh by IsFresh's reckoning, but someone who
		-- respecced and regeared five minutes ago is exactly who you are pressing it
		-- for -- and it kept showing their old spec and old gearscore.
		local ok, total = I.ScanGroup(true, function(done)
			I.onProgress = nil
			if F and F.scanBtn and F.scanBtn.text then F.scanBtn.text:SetText("Read specs") end
			Okanvil:Print("Specs read for " .. tostring(done) .. " player(s).")
			M.RefreshUI()
		end)
		if not ok then
			Okanvil:Print("|cffff5555Could not start the scan.|r")
		elseif total == 0 then
			-- With force on, an empty queue means there was nobody to read -- not
			-- that they were all cached.
			Okanvil:Print("Nobody in range to inspect.")
		end
	end)
	F.scanBtn:Tooltip("Inspect the group and read each player's real spec,\n"
		.. "then sort the board by it -- healers to Healer, tanks to Tank.\n\n"
		.. "Only works on people in range. Cached, so a second scan only\n"
		.. "checks who is new.")
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
		local col = W.Frame(p, "dark")
		col:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
		col:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
		col._idx = i

		-- The header carries EVERYTHING about this role: its name, how many you have
		-- against how many you want, and the two buttons that change the target.
		-- There used to be a second strip above the board saying "Melee 1/8 need 7"
		-- while the column below it said "Melee 1" -- the same fact twice, costing
		-- 50px of the board it was describing.
		local head = W.Frame(col, "raise")
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
			-- other dps bucket first (see PuG.lua)
			local role = key
			minus:OnClick(function()
				pickTakesOver()
				M.SetNeed(role, (tonumber(db().need[role]) or 0) - 1)
				M.RefreshUI()
			end)
			plus:OnClick(function()
				pickTakesOver()
				M.SetNeed(role, (tonumber(db().need[role]) or 0) + 1)
				M.RefreshUI()
			end)
		end

		-- Each column scrolls. A pug fills the Applicants column with everyone who
		-- answered -- twenty-one of them in one ToGC -- and a fixed ten slots either
		-- hid the rest behind "+11 more" or drew them past the bottom edge.
		local csf = CreateFrame("ScrollFrame", nil, col)
		csf:SetPoint("TOPLEFT", 1, -26)
		csf:SetPoint("BOTTOMRIGHT", -5, 3)
		local cchild = CreateFrame("Frame", nil, csf)
		cchild:SetSize(10, 1); csf:SetScrollChild(cchild)
		Okanvil.Clip(csf)

		local csb = CreateFrame("Slider", nil, col)
		csb:SetPoint("TOPRIGHT", -2, -26); csb:SetPoint("BOTTOMRIGHT", -2, 3); csb:SetWidth(3)
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
		                sf = csf, child = cchild, sb = csb }
	end

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
	end
	p:SetScript("OnSizeChanged", function() if F.layoutBoard then F.layoutBoard() end end)
	F.layoutBoard()
end

-- ------------------------------------------------------------
-- Class row (main page): "specifically looking for"
-- ------------------------------------------------------------
-- Want row: pick a ROLE first, then only the classes that can fill it.
--
-- All nine classes were offered for everything, which made the leader do the
-- filtering -- "which of these can even tank?" -- every time. Picking Tank now
-- leaves DK / Warr / Druid / Pala on screen and nothing else.
local function buildClassRow(p)
	local d = db()
	F.classBtns = {}
	F.roleBtns = {}

	local lbl = W.Text(p, "|cff8a8d93Want|r", "label", "dim")
	lbl:SetPoint("LEFT", 4, 0)

	-- role filter
	local x = 40
	-- No "Any": a class pick is always FOR a role ("a druid... to do what?"), and
	-- with picks stored per role there is nothing for an "any" bucket to hold.
	local ROLE_PICKS = {
		{ key = "tank",   label = "Tank" },
		{ key = "healer", label = "Heal" },
		{ key = "melee",  label = "Melee" },
		{ key = "ranged", label = "Range" },
	}
	for _, r in ipairs(ROLE_PICKS) do
		local b = W.Button(p, r.label, nil):Size(48, 20)
		b:SetPoint("LEFT", x, 0)
		b:OnClick(function()
			-- Same as the class and spec buttons: touching a pick means the line is
			-- being built from the picks again. Without this the role button was the
			-- one control that left a hand-edited line frozen, so switching from
			-- Range to Tank changed the buttons and nothing else.
			pickTakesOver()
			-- Only changes WHICH role's picks the row is showing. Each role keeps
			-- its own, so switching from Tank to Ranged no longer throws the tank
			-- classes away -- the line can name both.
			d.wantRole = r.key
			M.RefreshUI()
		end)
		b:Tooltip(r.key == "" and "Show every class."
			or ("Only classes that can " .. r.label:lower() .. "."))
		F.roleBtns[r.key] = b
		x = x + 50
	end

	-- separator, then the class buttons themselves
	local sep = p:CreateTexture(nil, "ARTWORK")
	sep:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	sep:SetSize(1, 16); sep:SetPoint("LEFT", x + 2, 0)
	sep:SetVertexColor(1, 1, 1, 0.12)
	x = x + 10

	-- Every class button is built once and simply hidden when the picked role
	-- cannot use it: rebuilding the row on each click would drop the buttons'
	-- handlers and leak frames, which WoW never reclaims.
	F.classX0 = x
	for _, c in ipairs(OkanvilClasses or {}) do
		local b = W.Button(p, c.short, nil):Size(50, 20)
		b:SetPoint("LEFT", x, 0)
		local tw = (b.text and b.text:GetStringWidth()) or 0
		b:SetWidth(math.max(50, tw + 16))
		b:OnClick(function()
			pickTakesOver()
			local picks = M.RolePicks(d.wantRole)
			picks[c.token] = (not picks[c.token]) or nil
			M.RefreshUI()
		end)
		b:Tooltip(c.name .. "\nAdds it to the \"(DK/Rogue)\" part of the line.")
		F.classBtns[c.token] = b
	end
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
	F.preview:SetPoint("RIGHT", p, "RIGHT", -180, 0)
	F.preview:SetHeight(40)

	-- Losing focus is what saves an edit (see the handler above), so a send the user
	-- clicks releases the box first.
	M.CommitPreview = function()
		if F.preview and F.preview.edit and F.preview.edit:HasFocus() then
			F.preview.edit:ClearFocus()
		end
	end

	F.autoTag = W.Text(p, "", "label", "dim")
	F.autoTag:SetPoint("TOPLEFT", 8, -50)

	F.sendBtn = W.Button(p, "Send once", "primary"):Size(82, 22)
	F.sendBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -92, -6)
	F.sendBtn:OnClick(function() M.SendNow() end)
	F.sendBtn:Tooltip("Post the line once, right now, in General and Global.\nSTART spamming (top right) repeats it every 60s.")

	F.resetBtn = W.Button(p, "Rebuild", nil):Size(82, 22)
	F.resetBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -6, -6)
	F.resetBtn:OnClick(function()
		local d = db()
		d.useCustom = false
		d.custom = ""
		M.RefreshUI()
	end)
	F.resetBtn:Tooltip("Throw away your hand-edits and rebuild the line\nfrom the raid, roles and reserves you picked.\nThis does NOT send anything.")

	F.charCount = W.Text(p, "", "label", "dim")
	F.charCount:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -34)
end

-- ------------------------------------------------------------
-- Reserve strip (main page): the loot categories, as toggles.
-- Specific hard-reserved ITEMS still live in the Reserves tab -- they need a
-- text box and a list, which does not fit a one-line strip.
-- ------------------------------------------------------------
local function buildReserveStrip(p)
	local d = db()
	F.resBtns = {}

	local lbl = W.Text(p, "|cff8a8d93Reserve|r", "label", "dim")
	lbl:SetPoint("LEFT", 6, 0)

	-- Width per label, not one fixed size: "Fragments" needs ~72px while "Key"
	-- needs 46, and a single width either clipped the long ones or wasted the row.
	local x = 56
	for _, c in ipairs(M.ReserveCats) do
		local b = W.Button(p, c.label, nil):Size(46, 20)
		b:SetPoint("LEFT", x, 0)
		-- MEASURE the rendered label instead of guessing from the character count:
		-- the font is proportional, so "Fragments" and "Shards" are nowhere near
		-- len*N apart. Advance x by the width we actually set, or a wide button is
		-- overlapped by the next one.
		local tw = (b.text and b.text:GetStringWidth()) or 0
		local bw = math.max(46, tw + 16)
		b:SetWidth(bw)
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
		x = x + bw + 4
	end

	F.resNoneBtn = W.Button(p, "no res", nil):Size(56, 20)
	F.resNoneBtn:SetPoint("LEFT", x + 6, 0)
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
	F.resTagBtn = W.Button(p, "HR", nil):Size(52, 20)
	F.resTagBtn:SetPoint("LEFT", x + 68, 0)
	F.resTagBtn:OnClick(function()
		d.reserveTag = (d.reserveTag == "gbid") and "hr" or "gbid"
		M.RefreshUI()
	end)
	F.resTagBtn:Tooltip("How reserved items are announced.\n\n"
		.. "|cffe0b860HR|r -- the leader keeps the drop.\n"
		.. "|cffe0b860GBid|r -- it goes to a gold bid among the raid.")

	-- how many specific items are hard-reserved (they are set in the Reserves tab)
	F.resItemTag = W.Text(p, "", "label", "dim")
	F.resItemTag:SetPoint("LEFT", x + 126, 0)
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
local function makeList(parent, x, w, top, bottom)
	local card = W.Frame(parent, "input")
	card:SetPoint("TOPLEFT", x, top)
	card:SetWidth(w)
	card:SetPoint("BOTTOM", parent, "BOTTOM", 0, bottom)

	local sf = CreateFrame("ScrollFrame", nil, card)
	sf:SetPoint("TOPLEFT", 4, -4); sf:SetPoint("BOTTOMRIGHT", -10, 4)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(10, 1); sf:SetScrollChild(child)

	local sb = CreateFrame("Slider", nil, card)
	sb:SetPoint("TOPRIGHT", -3, -4); sb:SetPoint("BOTTOMRIGHT", -3, 4); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
	local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetSize(4, 30)
	do local a = C.accent; th:SetVertexColor(a[1], a[2], a[3], 1) end
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, dz) sb:SetValue(sb:GetValue() - dz * 30) end)
	sf:SetScript("OnSizeChanged", function() child:SetWidth(sf:GetWidth()) end)

	local function relayout(h)
		child:SetWidth(sf:GetWidth() or w)
		child:SetHeight(math.max(1, h or 1))
		local maxs = math.max(0, (h or 1) - sf:GetHeight())
		sb:SetMinMaxValues(0, maxs); sb:SetShown(maxs > 4)
	end
	return card, child, relayout, sf
end

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
	if d.useCustom and d.custom ~= "" then
		F.autoTag:SetText("|cffe0b860Your text|r |cff8a8d93-- kept as you wrote it; the \"need ...\" counts still update. Rebuild to go back to auto.|r")
	else
		F.autoTag:SetText("|cff8a8d93Built from your picks -- updates as people join.|r")
	end
	-- 255 is the chat hard limit; show it before the server truncates.
	local n = #msg
	if n > 255 then
		F.charCount:SetText("|cffff5555" .. n .. "/255|r")
	else
		F.charCount:SetText("|cff8a8d93" .. n .. "/255|r")
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
		F.size10:SetKind(d.size == 10 and "primary" or nil)
		F.size25:SetKind(d.size == 25 and "primary" or nil)
	end
	if F.diffBtn then
		local canHC = info and info.hc
		F.diffBtn.text:SetText((canHC and d.hc) and "Heroic" or "Normal")
		F.diffBtn:SetKind((canHC and d.hc) and "primary" or nil)
	end
	if F.gsBox and not F.gsBox.edit:HasFocus() then F.gsBox.edit:SetText(d.gs or "") end
	if F.noteBox and not F.noteBox.edit:HasFocus() then F.noteBox.edit:SetText(d.note or "") end

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
						sub = "|cffe0b860spec not read|r"
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


	-- ---- reserves / classes / channels (tab pages, may not be built yet) ----
	if F.resBtns then
		for key, b in pairs(F.resBtns) do b:SetKind(d.reserve[key] and "primary" or nil) end
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
	-- (the reserved list is the RIGHT column of the Reserves tab now;
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
	if F.roleBtns then
		for key, b in pairs(F.roleBtns) do
			b:SetKind((d.wantRole or "") == key and "primary" or nil)
		end
	end
	if F.classBtns then
		-- Show only what the picked role can be, and re-flow so the visible
		-- buttons sit shoulder to shoulder instead of leaving gaps where the
		-- hidden ones used to be.
		local allowed = {}
		for _, c in ipairs(M.ClassesForRole(d.wantRole ~= "" and d.wantRole or "tank")) do
			allowed[c.token] = true
		end
		local x = F.classX0 or 54
		for _, c in ipairs(OkanvilClasses or {}) do
			local b = F.classBtns[c.token]
			if b then
				if allowed[c.token] then
					b:ClearAllPoints()
					b:SetPoint("LEFT", x, 0)
					b:SetKind(M.RolePicks(d.wantRole)[c.token] and "primary" or nil)
					b:Show()
					x = x + b:GetWidth() + 4
				else
					b:Hide()
				end
			end
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
		primaryText = function() return M.IsActive() and "STOP spamming" or "START spamming" end,
		primaryKind = function() return M.IsActive() and "primary" or "secondary" end,
		onPrimary = function() M.Toggle(); M.RefreshUI() end,
		-- No Messages button. Whispers from people wanting in are read in the chat
		-- frame, where every other whisper already is -- a second inbox for the
		-- same messages was one more place to look, not one fewer.
		statusText = function()
			if M.IsActive() then return "|cff7cfc8aSpamming ON|r" end
			return "|cffff5555Spamming OFF|r"
		end,
		tabs = {
			-- fill = take the VIEW's height. The two lists scroll internally and are
			-- anchored to the page's bottom, so they grow with it -- a fixed 420
			-- left a third of the window empty under a list you had to scroll.
			{ key = "loot",     label = "Reserves", height = 420, fill = true,
			  build = function(p) buildLoot(p) end },
			-- No "More" tab. It had grown to eight stacked sections -- channels,
			-- auto-reply, raid groups, spec picks, class run, presets -- none of
			-- which you touch while forming a raid.
		},
	})
	F.dash = dash

	-- The single page is stacked inside dash.main: top strip, needs, board, bottom.
	local main = dash.main

	-- Every strip is a REAL panel ("dark"), not a transparent one. The shared rat
	-- art is drawn on the content well above its own fill, so anything transparent
	-- lets the art through and the text sits on top of a picture. Solid strips keep
	-- the rat where it belongs -- behind the page, visible only in empty space.
	local top = W.Frame(main, "dark")
	top:SetPoint("TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", 0, 0)
	top:SetHeight(32)
	buildTopStrip(top)

	-- No needs strip. Each column header carries its own count, target and
	-- stepper now, so a 52px band repeating them above the board was the same
	-- facts twice -- and it was taking the space from the thing it described.

	-- Reserves and classes stay ON the page: picking "need a rogue" is the common
	-- ask and burying it behind a tab made it slower, not cleaner. The SPEC row is
	-- the one that goes -- asking for a HOLY paladin specifically is rare, and
	-- twelve more buttons was what made this strip unreadable.
	local classRow = W.Frame(main, "dark")
	classRow:SetPoint("BOTTOMLEFT", 0, 0); classRow:SetPoint("BOTTOMRIGHT", 0, 0)
	classRow:SetHeight(26)
	buildClassRow(classRow)

	local resStrip = W.Frame(main, "dark")
	resStrip:SetPoint("BOTTOMLEFT", classRow, "TOPLEFT", 0, 3)
	resStrip:SetPoint("BOTTOMRIGHT", classRow, "TOPRIGHT", 0, 3)
	resStrip:SetHeight(26)
	buildReserveStrip(resStrip)

	local bottom = W.Frame(main, "dark")
	bottom:SetPoint("BOTTOMLEFT", resStrip, "TOPLEFT", 0, 3)
	bottom:SetPoint("BOTTOMRIGHT", resStrip, "TOPRIGHT", 0, 3)
	bottom:SetHeight(74)
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
ev:SetScript("OnEvent", function()
	if F then M.RefreshUI() end
end)
