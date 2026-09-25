-- ============================================================
-- Okanvil -- Widgets: a small chained-API widget layer (mini-ELib),
-- modelled on Method Raid Tools' ExLib. Provides :Point/:Size/:Color
-- chaining, consistent flat templates, and -- crucially -- a single
-- screen-clamped global dropdown so lists never spill out of the window.
--
-- Public surface used by UI.lua / plugins:
--   Okanvil.W.Frame/Text/Button/Check/Slider/EditBox/ScrollList/DropDown
--   Okanvil:Skin(frame[, kind])       flat panel backdrop (kinds below)
--   Okanvil:Popup(title)              draggable, clamped dialog
-- The chained widgets all understand :Point :Size :Shown :OnClick :OnEnter
-- :OnLeave :Color, and hand back `self` so calls compose.
-- ============================================================

local Okanvil = Okanvil
local W = {}
Okanvil.W = W

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

-- ------------------------------------------------------------
-- Type scale -- ONE place that decides how big anything is.
--
-- Sizes used to be written at each call site, which grew to ten different
-- values across 175 calls: section labels at 10 on one page and 11 on the next,
-- list rows at 12 here and 13 there. Nothing was wrong on its own, and together
-- the pages read as untidy because the same KIND of text was a different size
-- depending on who wrote that page.
--
-- Now a call site names the ROLE and the scale decides the number. Change one
-- line here and every page moves together.
--
-- The window's Scale slider does the zooming (it scales text, icons, spacing and
-- padding alike, which is what "make it bigger" actually means), so these are
-- fixed pixel sizes and there is no separate font slider fighting them.
W.F = {
	title   = 16,   -- the window wordmark, a page's own name
	head    = 13,   -- section headers inside a page ("APPEARANCE", "TRINKETS")
	body    = 12,   -- the default: list rows, values, anything you read
	label   = 11,   -- field labels, button text, tab text
	note    = 10,   -- hints, footnotes, the dim line under a control
	huge    = 24,   -- standalone overlay readouts (timers, gold counters)
}

-- ------------------------------------------------------------
-- Design tokens (one place -- keeps every panel consistent)
-- ------------------------------------------------------------
-- Palette mirrors the RATS Hub website (gold accent on neutral dark), so the
-- addon and the hub read as one brand. Values are the hub's CSS vars in 0-1.
local C = {
	accent   = { 0.75, 0.58, 0.23 },       -- #c0943a  gold -- fills (buttons/bars/active)
	accentHi = { 0.88, 0.72, 0.38 },       -- #e0b860  gold, bright (hover fills)
	accentText = { 1.0, 0.82, 0.0 },       -- #ffd200  bright WoW gold -- TEXT/titles (readable on dark)
	accentD  = { 0.32, 0.25, 0.11 },       -- gold, dimmed fill
	panel    = { 0.150, 0.157, 0.176 },    -- #26282d  default panel
	panelD   = { 0.078, 0.082, 0.090 },    -- #141517  recessed well (nav/content)
	panelHi  = { 0.180, 0.188, 0.212 },    -- header / hover raise
	surface  = { 0.125, 0.133, 0.145 },    -- #202225  buttons (secondary)
	border   = { 0.184, 0.192, 0.216 },    -- #2f3137  1px hairline
	borderHi = { 0.34, 0.30, 0.18 },       -- gold-tinted hover/focus border
	text     = { 0.863, 0.867, 0.871 },    -- #dcddde
	textDim  = { 0.541, 0.553, 0.576 },    -- #8a8d93
	ok       = { 0.486, 0.988, 0.541 },    -- #7cfc8a
	danger   = { 0.85, 0.30, 0.32 },
	dark     = { 0.078, 0.082, 0.090 },    -- text on gold buttons
}
Okanvil.Colors = C

local function unpack3(t, a) return t[1], t[2], t[3], a or 1 end

-- Clip a ScrollFrame's overflow if the client supports it. SetClipsChildren
-- was added in WoW 5.x; on 3.3.5 it's absent, so we no-op there (the
-- ScrollFrame's child sizing still keeps content in place). Never call the
-- method blindly -- that errors on 3.3.5.
local function Clip(frame)
	if frame.SetClipsChildren then frame:SetClipsChildren(true) end
	return frame
end
Okanvil.Clip = Clip

-- ------------------------------------------------------------
-- Skin: the single source of the flat 1px look. `kind`:
--   nil/"panel"  standard fill
--   "dark"       recessed well (nav / content)
--   "raise"      header / hovered raise
--   "input"      edit boxes / dropdowns (slightly darker, focusable)
--   "page"       page panel: BORDER only, transparent fill -- so the ONE content
--                well (with the rat watermark) shows through uniformly behind
--                every page. Its alpha is fixed 0 (ignores the opacity slider).
-- Registers the frame so the Settings alpha slider can re-tint it.
-- ------------------------------------------------------------
function Okanvil:Skin(frame, kind)
	kind = kind or "panel"
	frame:SetBackdrop({
		bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	local fill = C.panel
	if kind == "dark" or kind == "input" then fill = C.panelD
	elseif kind == "raise" then fill = C.panelHi end
	if kind == "page" or kind == "well" then
		-- Fully invisible container: transparent body AND transparent border. The
		-- outer `content` well already frames the page; drawing this panel's own
		-- 1px border created a seam line that cut across the art where main/drawer
		-- meet. No fill, no edge => the window's wallpaper reads as one clean
		-- background behind the page. NOT registered for the opacity slider.
		frame:SetBackdrop(nil)
		return frame
	end
	-- The forge look inside pages (see the first-run setup):
	--   "row"   a list row on the art -- no fill, a hairline under it
	--   "soft"  a group that still needs grouping (a reading card, a column) --
	--           a faint dark wash, no border
	if kind == "row" then
		frame:SetBackdrop(nil)
		if not frame._okRule then
			local rule = frame:CreateTexture(nil, "BORDER")
			rule:SetTexture(FLAT); rule:SetVertexColor(1, 1, 1, 0.06)
			rule:SetHeight(1); rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
			frame._okRule = rule
		end
		return frame
	end
	if kind == "soft" then
		-- A faint hairline edge too: on the wallpaper the wash alone was too weak
		-- to separate side-by-side groups (the PuG columns vanished into the art).
		frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
			insets = { left = 1, right = 1, top = 1, bottom = 1 } })
		frame:SetBackdropColor(C.panelD[1], C.panelD[2], C.panelD[3], 0.55)
		frame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 0.9)
		return frame
	end
	local a = self.db and self.db.bgAlpha or 0.95
	frame:SetBackdropColor(fill[1], fill[2], fill[3], a)
	frame:SetBackdropBorderColor(unpack3(C.border))
	self._skinned = self._skinned or {}
	self._skinned[frame] = { fill = fill }
	return frame
end

-- re-apply fills at a new alpha (Settings slider)
function Okanvil:ReskinAll(alpha)
	if not self._skinned then return end
	for f, info in pairs(self._skinned) do
		if f.SetBackdropColor then
			f:SetBackdropColor(info.fill[1], info.fill[2], info.fill[3], alpha)
		end
	end
end

-- ------------------------------------------------------------
-- Chained-API mixin (the ELib `Mod` idea, trimmed)
-- ------------------------------------------------------------
local function Mod(self)
	function self:Point(...) self:SetPoint(...); return self end
	function self:NewPoint(...) self:ClearAllPoints(); self:SetPoint(...); return self end
	function self:Size(...) self:SetSize(...); return self end
	function self:Shown(b) if b then self:Show() else self:Hide() end; return self end
	function self:OnClick(fn) self:SetScript("OnClick", fn); return self end
	function self:OnEnter(fn) self:SetScript("OnEnter", fn); return self end
	function self:OnLeave(fn) self:SetScript("OnLeave", fn); return self end
	function self:Tooltip(text) self._tip = text; return self end
	return self
end
Okanvil.Mod = Mod

-- shared tooltip wiring (used by anything with a ._tip).
-- A "\n" in the text starts a NEW LINE: AddLine does not honour newlines itself, so a
-- multi-line tip rendered as one run-on line. Each line wraps (the `true` arg), which
-- is what lets a tip carry a short explanation and not just a label.
local function tipEnter(self)
	if not self._tip then return end
	-- Anchor by where there is room, not by a fixed side. A tall tip on a button
	-- near the top of the screen grows past the edge with ANCHOR_RIGHT, because
	-- the tooltip hangs DOWN from the anchor and the client then shoves the whole
	-- thing up and off-screen. Picking the corner nearest the middle keeps it in.
	local cx, cy = self:GetCenter()
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local anchor = "ANCHOR_RIGHT"
	if cx and cy then
		local right = cx < sw / 2
		local down  = cy > sh / 2
		anchor = right and (down and "ANCHOR_BOTTOMRIGHT" or "ANCHOR_RIGHT")
			or (down and "ANCHOR_LEFT" or "ANCHOR_LEFT")
	end
	GameTooltip:SetOwner(self, anchor)
	if GameTooltip.SetClampedToScreen then GameTooltip:SetClampedToScreen(true) end
	for line in (tostring(self._tip) .. "\n"):gmatch("(.-)\n") do
		if line == "" then
			GameTooltip:AddLine(" ")            -- blank spacer line
		else
			GameTooltip:AddLine(line, C.text[1], C.text[2], C.text[3], true)
		end
	end
	GameTooltip:Show()
end
local function tipLeave() GameTooltip:Hide() end

-- ------------------------------------------------------------
-- Frame
-- ------------------------------------------------------------
function W.Frame(parent, kind)
	local f = CreateFrame("Frame", nil, parent)
	if kind ~= "bare" then Okanvil:Skin(f, kind) end
	return Mod(f)
end

-- ------------------------------------------------------------
-- Text (registers with Okanvil:ApplyFonts via Okanvil:NewText)
-- ------------------------------------------------------------
-- size may be a number or a scale role name ("body", "head", "note"...). The
-- names are what new code should use; the numbers stay accepted so a page that
-- genuinely needs an odd size can still ask for one.
function W.Size(size)
	if type(size) == "string" then return W.F[size] or W.F.body end
	return size
end

function W.Text(parent, text, size, role)
	local fs = Okanvil:NewText(parent, "OVERLAY")
	size = W.Size(size)
	if size then fs._okSize = size; local f = Okanvil:Font(); fs:SetFont(f, size) end
	if role == "dim" then fs:SetTextColor(unpack3(C.textDim))
	elseif role == "accent" then fs:SetTextColor(unpack3(C.accentText))  -- bright gold, readable
	else fs:SetTextColor(unpack3(C.text)) end
	if text then fs:SetText(text) end
	function fs:Point(...) fs:SetPoint(...); return fs end
	function fs:Color(r, g, b, a) fs:SetTextColor(r, g, b, a or 1); return fs end
	function fs:Justify(h) fs:SetJustifyH(h); return fs end
	return fs
end

-- ------------------------------------------------------------
-- Hint: the dim explanatory line under a control.
--
--   local y = W.Hint(parent, "what this does", x, y, width)
--
-- Returns the NEXT y, stepped by the height the text actually took. That return
-- is the whole point of the widget: every page that laid a hint out by hand
-- stepped a flat 18 or 20px, so a hint that wrapped to two lines ran into the
-- control below it -- the same bug, written three separate times.
--
-- Give it a real width. Without one a FontString does not wrap at all, it just
-- runs off the panel.
-- ------------------------------------------------------------
function W.Hint(parent, text, x, y, width, gap)
	local t = W.Text(parent, "|cff6f7176" .. (text or "") .. "|r", "note", "dim")
	t:SetPoint("TOPLEFT", x, y)
	if width then t:SetWidth(width) end
	t:SetJustifyH("LEFT")
	if t.SetWordWrap then t:SetWordWrap(true) end
	local h = (t:GetStringHeight() or 0)
	return y - math.max(18, h + (gap or 6)), t
end

-- ------------------------------------------------------------
-- Section heading: dim all-caps label with a hairline to the right edge.
--
--   local y = W.Section(parent, "APPEARANCE", x, y)          -- to the parent's right
--   local y = W.Section(parent, "READY CHECK", x, y, 360)    -- fixed reach
--
-- One definition of what a section looks like, so a page cannot end up with
-- half its headings in all-caps notes and the other half in normal-case labels
-- -- which is exactly what Settings and the Loot page had drifted into.
-- ------------------------------------------------------------
function W.Section(parent, text, x, y, reach)
	local t = W.Text(parent, text, "note", "dim")
	t:SetPoint("TOPLEFT", x, y)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetTexture("Interface\\Buttons\\WHITE8x8")
	rule:SetVertexColor(C.border[1], C.border[2], C.border[3], 1)
	rule:SetHeight(1)
	rule:SetPoint("LEFT", t, "RIGHT", 8, 0)
	if reach then
		rule:SetWidth(reach)
	else
		rule:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
	end
	return y - 26, t
end

-- ------------------------------------------------------------
-- How much clear space a slider needs ABOVE its anchor point.
--
-- W.Slider anchors at its BAR and paints its label above that, so anchoring one
-- directly under a heading prints the label over the heading. Pages used to
-- carry their own magic number for this, or forget it.
-- ------------------------------------------------------------
W.SLIDER_TOP = 20

-- ------------------------------------------------------------
-- Button. kind:
--   "primary"   solid gold fill, dark bold label (calls to action)
--   nil/"secondary"  surface fill, hairline border, dim label -> gold on hover
--   "danger"    like secondary but red label/hover
-- Matches the RATS Hub button hierarchy.
-- ------------------------------------------------------------
function W.Button(parent, text, kind)
	local b = CreateFrame("Button", nil, parent)
	b:SetBackdrop({
		bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	local primary = (kind == "primary")
	-- Button labels get a FIXED size (12) so the global "Font size" slider can't
	-- grow them past the button box. The slider is for body text, not chrome.
	local t = W.Text(b, text, "body")
	t:SetPoint("CENTER")
	b.text = t
	b._kind = kind

	-- "tab" / "tabOn": the forge look's tabs -- no box, dim label, and the picked
	-- one in gold with a gold underline (see the first-run setup / the mock).
	local under
	local function paint(hover)
		local isTab = (kind == "tab" or kind == "tabOn")
		if under then under:SetShown(kind == "tabOn") end
		if isTab then
			if not under then
				under = b:CreateTexture(nil, "ARTWORK")
				under:SetTexture(FLAT); under:SetVertexColor(unpack3(C.accent))
				under:SetHeight(2); under:SetPoint("BOTTOMLEFT", 2, 0); under:SetPoint("BOTTOMRIGHT", -2, 0)
				under:SetShown(kind == "tabOn")
			end
			b:SetBackdropColor(0, 0, 0, 0)
			b:SetBackdropBorderColor(0, 0, 0, 0)
			if kind == "tabOn" then t:SetTextColor(unpack3(C.accentText))
			elseif hover then t:SetTextColor(unpack3(C.accentHi))
			else t:SetTextColor(0.74, 0.75, 0.77) end
		elseif primary then
			local f = hover and C.accentHi or C.accent
			b:SetBackdropColor(f[1], f[2], f[3], 1)
			b:SetBackdropBorderColor(unpack3(C.accentHi))
			t:SetTextColor(unpack3(C.dark))
		else
			b:SetBackdropColor(unpack3(hover and C.panelHi or C.surface))
			b:SetBackdropBorderColor(unpack3(hover and C.borderHi or C.border))
			local lbl = (kind == "danger") and C.danger or (hover and C.accentHi or C.textDim)
			t:SetTextColor(unpack3(b._active and C.accentHi or lbl))
		end
	end
	b._paint = paint
	paint(false)
	b:SetScript("OnEnter", function(s) paint(true); tipEnter(s) end)
	b:SetScript("OnLeave", function(s) paint(false); tipLeave() end)

	-- Re-style in place. For an ON/OFF toggle the STATE is the fill, not a colour
	-- code in the label: a "primary" button is a solid gold box whose label is
	-- painted dark, so an embedded |cff8a8d93 (dim grey) override lands grey-on-gold
	-- and is unreadable. Flip the kind instead -> ON = gold primary, OFF = surface.
	function b:SetKind(k)
		self._kind = k
		primary = (k == "primary")
		kind = k
		paint(self._hover)
	end
	b:HookScript("OnEnter", function(s) s._hover = true end)
	b:HookScript("OnLeave", function(s) s._hover = false end)
	return Mod(b)
end

-- ------------------------------------------------------------
-- Check (flat checkbox)
-- ------------------------------------------------------------
function W.Check(parent, label, getFn, setFn)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(18, 18)
	local box = W.Frame(b, "input")
	box:SetAllPoints()
	-- Our own palette, not Blizzard's UI-CheckBox-Check -- that texture carries its
	-- own yellow and bevel and clashes with the flat gold-on-dark used everywhere
	-- else. A filled gold square inset in the box: unambiguous at 18px, and it needs
	-- no SetRotation, which stock 3.3.5a textures do not have.
	local tick = box:CreateTexture(nil, "OVERLAY")
	tick:SetTexture(FLAT)
	tick:SetVertexColor(unpack3(C.accent))
	tick:SetPoint("TOPLEFT", 4, -4)
	tick:SetPoint("BOTTOMRIGHT", -4, 4)
	local t = W.Text(b, label)
	t:SetPoint("LEFT", b, "RIGHT", 6, 0)
	b.text = t
	local function refresh() tick:SetShown(getFn and getFn() or false) end
	refresh()
	b:SetScript("OnClick", function()
		if setFn then setFn(not (getFn and getFn())) end
		refresh()
	end)
	-- honour :Tooltip() like W.Button does -- without tipEnter here, calling
	-- :Tooltip() on a checkbox silently did nothing (this OnEnter overwrote it).
	b:SetScript("OnEnter", function(s) box:SetBackdropBorderColor(unpack3(C.borderHi)); tipEnter(s) end)
	b:SetScript("OnLeave", function() box:SetBackdropBorderColor(unpack3(C.border)); tipLeave() end)
	b.refresh = refresh
	return Mod(b)
end

-- ------------------------------------------------------------
-- ToggleRow -- the forge look's setting: a title, a dim line under it saying
-- what it does, an ON / OFF button on the right, a hairline below. Replaces a
-- checkbox wherever a setting deserves its one-line reason.
--   local r = W.ToggleRow(parent, "Title", "what it does", getFn, setFn)
--   r:SetPoint("TOPLEFT", x, y); r:SetPoint("RIGHT", parent, "RIGHT", -x, 0)
--   y = y - r:GetHeight()
-- r.refresh() repaints from getFn; r:Tooltip(text) works like on a button.
-- ------------------------------------------------------------
function W.ToggleRow(parent, title, desc, getFn, setFn)
	local r = CreateFrame("Frame", nil, parent)
	r:SetHeight((desc and desc ~= "") and 44 or 32)
	r:EnableMouse(true)
	local rule = r:CreateTexture(nil, "BORDER")
	rule:SetTexture(FLAT); rule:SetVertexColor(1, 1, 1, 0.06)
	rule:SetHeight(1); rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")

	local btn = W.Button(r, "")
	btn:SetSize(52, 22); btn:SetPoint("RIGHT", 0, 0)
	r.btn = btn

	local t = W.Text(r, title, "body")
	t:SetJustifyH("LEFT")
	r.text = t
	if desc and desc ~= "" then
		t:SetPoint("TOPLEFT", 0, -6)
		local d = W.Text(r, desc, "note", "dim")
		d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
		d:SetPoint("RIGHT", btn, "LEFT", -12, 0); d:SetJustifyH("LEFT")
		if d.SetWordWrap then d:SetWordWrap(false) end
		r.desc = d
	else
		t:SetPoint("LEFT", 0, 0)
	end
	t:SetPoint("RIGHT", btn, "LEFT", -12, 0)

	local function refresh()
		local on = getFn and getFn() or false
		btn:SetKind(on and "primary" or nil)
		btn.text:SetText(on and "ON" or "OFF")
	end
	btn:SetScript("OnClick", function()
		if setFn then setFn(not (getFn and getFn())) end
		refresh()
	end)
	r.refresh = refresh
	refresh()
	Mod(r)
	-- the tooltip hangs off the whole row, the button included
	r:SetScript("OnEnter", tipEnter); r:SetScript("OnLeave", tipLeave)
	btn:HookScript("OnEnter", function() if r._tip then tipEnter(r) end end)
	btn:HookScript("OnLeave", tipLeave)
	return r
end

-- ------------------------------------------------------------
-- Slider (thin flat track + thumb + label above)
-- ------------------------------------------------------------
function W.Slider(parent, label, lo, hi, step, getFn, setFn, onRelease)
	local s = CreateFrame("Slider", nil, parent)
	s:SetSize(200, 14)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	Okanvil:Skin(s, "input")
	s:EnableMouse(true)

	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(FLAT)
	thumb:SetVertexColor(unpack3(C.accent))
	thumb:SetSize(8, 18)
	s:SetThumbTexture(thumb)

	local title = W.Text(s, nil, nil, "dim")
	title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 5)
	local function paint(v) title:SetText(label .. ": |cffffd200" .. v .. "|r") end
	paint(getFn()); s:SetValue(getFn())

	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v / step + 0.5) * step
		paint(v); s._pending = v
		if not onRelease then setFn(v) end
	end)
	if onRelease then
		s:SetScript("OnMouseUp", function() if s._pending then setFn(s._pending) end end)
	end
	s:SetScript("OnEnter", function() thumb:SetVertexColor(1, 1, 1, 1) end)
	s:SetScript("OnLeave", function() thumb:SetVertexColor(unpack3(C.accent)) end)
	return Mod(s)
end

-- ------------------------------------------------------------
-- EditBox (single line, focus-highlighted)
-- ------------------------------------------------------------
function W.EditBox(parent, onEnter)
	local box = W.Frame(parent, "input")
	local e = CreateFrame("EditBox", nil, box)
	e:SetPoint("TOPLEFT", 6, -1)
	e:SetPoint("BOTTOMRIGHT", -6, 1)
	e:SetAutoFocus(false)
	e:SetFontObject(GameFontHighlightSmall)
	-- A caller that needs bigger text sets box:SetTextSize(n) after building --
	-- the note editor is read as much as it is typed in.
	local fp = Okanvil:Font()
	e:SetFont(fp, 12)                 -- fixed size: the box height is fixed, so the
	e:SetTextColor(unpack3(C.text))   -- global font slider must not overflow it
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEditFocusGained", function() box:SetBackdropBorderColor(unpack3(C.borderHi)) end)
	-- COMMIT ON FOCUS LOSS as well as on Enter. Only firing on Enter meant typing
	-- a value and then clicking away silently threw it out -- the field still
	-- showed the text, so it looked saved, and the setting only "worked" after a
	-- /reload repainted the box from the unchanged db.
	e:SetScript("OnEditFocusLost", function(s)
		box:SetBackdropBorderColor(unpack3(C.border))
		if onEnter and s._committed ~= s:GetText() then
			s._committed = s:GetText()
			onEnter(s:GetText())
		end
	end)
	if onEnter then
		e:SetScript("OnEnterPressed", function(s)
			s._committed = s:GetText()
			onEnter(s:GetText()); s:ClearFocus()
		end)
	end
	-- The whole box is clickable, not just the glyphs. An EditBox only takes
	-- focus where it has text to hit, so clicking an empty field anywhere but
	-- the top-left -- where the cursor sits -- did nothing at all, and a short
	-- value left most of the field dead. The frame behind it catches the click
	-- and hands over focus, putting the cursor nearest to where you clicked.
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		e:SetFocus()
		-- Clicking past the end of the text puts the cursor at the end, which is
		-- what the empty space to the right of a value means.
		local x = GetCursorPosition() / (e:GetEffectiveScale() or 1)
		if x > (e:GetLeft() or 0) + (e:GetStringWidth() or 0) then
			e:SetCursorPosition(e:GetText() and #e:GetText() or 0)
		end
	end)

	Okanvil:TrackEditBox(e)   -- so the window can release keyboard focus on hide
	box.edit = e
	function box:Size(w, h) box:SetSize(w, h); return box end
	function box:Point(...) box:SetPoint(...); return box end
	-- Per-box override of the fixed 12: a box you READ as much as you type in
	-- wants bigger text than a one-line field.
	function box:SetTextSize(px)
		e:SetFont(Okanvil:Font(), px or 12)
		return box
	end
	return box
end

-- ------------------------------------------------------------
-- MultiEdit -- multiline edit box with our own flat scrollbar (no Blizzard
-- template). For longer text (advertise/reply messages). onDone(text) fires
-- on focus-lost so callers can persist. Exposes .edit and :SetText/:GetText.
-- ------------------------------------------------------------
function W.MultiEdit(parent, onDone)
	local box = W.Frame(parent, "input")
	local sf = CreateFrame("ScrollFrame", nil, box)
	sf:SetPoint("TOPLEFT", 5, -5); sf:SetPoint("BOTTOMRIGHT", -10, 5)
	local e = CreateFrame("EditBox", nil, sf)
	e:SetMultiLine(true)
	e:SetAutoFocus(false)
	e:SetFontObject(GameFontHighlightSmall)
	-- A caller that needs bigger text sets box:SetTextSize(n) after building --
	-- the note editor is read as much as it is typed in.
	local fp = Okanvil:Font()
	e:SetFont(fp, 12)                 -- fixed size: the box height is fixed, so the
	e:SetTextColor(unpack3(C.text))   -- global font slider must not overflow it
	e:SetScript("OnEscapePressed", e.ClearFocus)
	Okanvil:TrackEditBox(e)   -- so the window can release keyboard focus on hide
	sf:SetScrollChild(e)

	local sb = CreateFrame("Slider", nil, box)
	sb:SetPoint("TOPRIGHT", -3, -5); sb:SetPoint("BOTTOMRIGHT", -3, 5); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
	local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetVertexColor(unpack3(C.accent)); th:SetSize(4, 30)
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	local function range()
		local max = math.max(0, e:GetHeight() - sf:GetHeight())
		sb:SetMinMaxValues(0, max); sb:SetShown(max > 4)
	end
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 20) end)
	sf:SetScript("OnSizeChanged", function() e:SetWidth(math.max(40, sf:GetWidth())); range() end)

	-- keep the caret visible as you type/scroll
	e:SetScript("OnCursorChanged", function(self, _, ypos, _, height)
		range()
		local off, viewH = sf:GetVerticalScroll(), sf:GetHeight()
		ypos = -ypos
		if ypos < off then sf:SetVerticalScroll(ypos)
		elseif (ypos + height) > (off + viewH) then sf:SetVerticalScroll(math.max(0, ypos + height - viewH)) end
	end)
	e:SetScript("OnEditFocusGained", function() box:SetBackdropBorderColor(unpack3(C.borderHi)) end)
	e:SetScript("OnEditFocusLost", function()
		box:SetBackdropBorderColor(unpack3(C.border))
		if onDone then onDone(e:GetText()) end
	end)

	-- The empty space below the last line is clickable too. A multiline
	-- EditBox is only as tall as the text it holds, so in a box with two lines
	-- of text everything under them belonged to the scroll frame and clicking
	-- there did nothing -- you had to hit the text itself to start typing.
	-- Clicking the empty part means "carry on at the end", so that is where
	-- the cursor goes.
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		e:SetFocus()
		e:SetCursorPosition(e:GetText() and #e:GetText() or 0)
	end)

	box.edit = e
	function box:SetText(t) e:SetText(t or "") end
	function box:GetText() return e:GetText() end
	function box:Size(w, h) box:SetSize(w, h); return box end
	function box:Point(...) box:SetPoint(...); return box end
	-- Per-box override of the fixed 12: a box you READ as much as you type in
	-- wants bigger text than a one-line field.
	function box:SetTextSize(px)
		e:SetFont(Okanvil:Font(), px or 12)
		return box
	end
	return box
end

-- ============================================================
-- Global dropdown -- the anti-spill piece.
-- ONE list frame, parented to UIParent, strata TOOLTIP, clamped to
-- screen, that flips up when there's no room below. Every dropdown
-- button borrows it (like ELib.ScrollDropDown). Lists therefore never
-- get trapped inside -- or clipped by -- the main window.
-- ============================================================
local MENU  -- lazily created shared menu
local MENU_MAX_H = 260

local function ensureMenu()
	if MENU then return MENU end
	local m = CreateFrame("Frame", "Okanvil_DropdownMenu", UIParent)
	m:SetFrameStrata("TOOLTIP")
	m:SetClampedToScreen(true)
	m:SetToplevel(true)
	Okanvil:Skin(m, "input")
	-- Opaque whatever the window opacity is (a list over the game must be read),
	-- with a gold-tinted edge so it reads as "open" against the page.
	m:SetBackdropColor(C.panelD[1], C.panelD[2], C.panelD[3], 0.98)
	m:SetBackdropBorderColor(unpack3(C.borderHi))
	m:Hide()

	local sf = CreateFrame("ScrollFrame", nil, m)
	sf:SetPoint("TOPLEFT", 3, -3)
	sf:SetPoint("BOTTOMRIGHT", -8, 3)
	Clip(sf)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(10, 1)
	sf:SetScrollChild(child)
	m.sf, m.child = sf, child

	local sb = CreateFrame("Slider", nil, m)
	sb:SetPoint("TOPRIGHT", -3, -3)
	sb:SetPoint("BOTTOMRIGHT", -3, 3)
	sb:SetWidth(4)
	sb:SetOrientation("VERTICAL")
	sb:SetValueStep(1)
	local th = sb:CreateTexture(nil, "OVERLAY")
	th:SetTexture(FLAT); th:SetVertexColor(unpack3(C.accent)); th:SetSize(4, 40)
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 20) end)
	m.sb = sb

	m.rows = {}
	-- close when clicking elsewhere
	m:SetScript("OnHide", function() m.owner = nil end)
	MENU = m
	return m
end

-- close helper (UI.lua calls this on panel switch)
function Okanvil:CloseDropdown()
	if MENU and MENU:IsShown() then MENU:Hide() end
end

-- position the menu under (or above) the owning button, clamped
local function placeMenu(m, owner, height)
	m:ClearAllPoints()
	local ownerBottom = owner:GetBottom() or 0
	local room = ownerBottom - height - 4
	if room < 0 then
		-- not enough room below -> flip up
		m:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
	else
		m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	end
end

-- open the shared menu for `owner`, listing items {text=, value=} (or plain strings)
local function openMenu(owner)
	local m = ensureMenu()
	if m.owner == owner and m:IsShown() then m:Hide(); return end
	m.owner = owner
	m:SetWidth(owner:GetWidth())

	local items = owner.listFn()
	local cur = owner.getFn and owner.getFn()
	local font = Okanvil:Font()
	local rowH = 22
	local y = 0
	for _, r in ipairs(m.rows) do r:Hide() end
	for i, it in ipairs(items) do
		-- An explicit if, not `and/or`: a label row's value is false, and
		-- `t and t.value or t` would turn that false back into the table.
		local val, label
		if type(it) == "table" then val, label = it.value, it.text else val, label = it, it end
		local r = m.rows[i]
		if not r then
			r = CreateFrame("Button", nil, m.child)
			r.tex = r:CreateTexture(nil, "ARTWORK")
			r.tex:SetPoint("TOPLEFT", 1, -1); r.tex:SetPoint("BOTTOMRIGHT", -1, 1); r.tex:Hide()
			r.t = r:CreateFontString(nil, "OVERLAY")
			r.t:SetPoint("LEFT", 10, 0); r.t:SetJustifyH("LEFT")
			r.t:SetShadowColor(0, 0, 0, 1); r.t:SetShadowOffset(1, -1)
			-- the current choice: a faint gold wash and a gold bar on its left
			r.sel = r:CreateTexture(nil, "BACKGROUND")
			r.sel:SetAllPoints(); r.sel:SetTexture(FLAT)
			r.sel:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.10)
			r.bar = r:CreateTexture(nil, "ARTWORK")
			r.bar:SetTexture(FLAT); r.bar:SetVertexColor(unpack3(C.accent))
			r.bar:SetWidth(2); r.bar:SetPoint("TOPLEFT", 0, -3); r.bar:SetPoint("BOTTOMLEFT", 0, 3)
			local hl = r:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints(); hl:SetTexture(FLAT); hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.14)
			m.rows[i] = r
		end
		r:SetHeight(rowH); r:SetWidth(m:GetWidth() - 12)
		r:SetPoint("TOPLEFT", 0, -y)
		if owner.preview == "font" then
			local fp = Okanvil.LSM and Okanvil.LSM:Fetch("font", val, true)
			r.t:SetFont(fp or font, 13)
		else
			r.t:SetFont(font, 12)
		end
		if owner.preview == "statusbar" then
			local tp = Okanvil.LSM and Okanvil.LSM:Fetch("statusbar", val, true)
			r.tex:SetTexture(tp or FLAT); r.tex:SetVertexColor(1, 1, 1, 1); r.tex:Show()
		elseif r.tex then r.tex:Hide() end
		r.t:SetText(label)
		local isCur = (val ~= false and val == cur)
		r.sel:SetShown(isCur); r.bar:SetShown(isCur)
		if val == false then r.t:SetTextColor(unpack3(C.textDim))   -- a label, not a choice
		elseif isCur then r.t:SetTextColor(unpack3(C.accentText))
		elseif owner.preview == "statusbar" then r.t:SetTextColor(1, 1, 1)
		else r.t:SetTextColor(unpack3(C.text)) end
		r:SetScript("OnClick", function()
			if val == false then return end     -- label rows do nothing when clicked
			owner.setFn(val)
			if owner.refreshText then owner:refreshText() end
			m:Hide()
		end)
		r:Show()
		y = y + rowH
	end
	m.child:SetHeight(math.max(1, y))
	local h = math.min(y + 6, MENU_MAX_H)
	m:SetHeight(h)
	local maxScroll = math.max(0, y - (h - 6))
	m.sb:SetMinMaxValues(0, maxScroll); m.sb:SetValue(0)
	m.sb:SetShown(maxScroll > 0)
	placeMenu(m, owner, h)
	m:Show()
end

-- ------------------------------------------------------------
-- DropDown button (borrows the global menu)
-- ------------------------------------------------------------
function W.DropDown(parent, listFn, getFn, setFn, preview)
	local dd = CreateFrame("Button", nil, parent)
	dd:SetSize(160, 22)
	Okanvil:Skin(dd, "input")
	-- fixed size (12): the dropdown box is a fixed height, so its text must not
	-- scale with the global body-font slider (it would clip / overflow).
	local txt = W.Text(dd, nil, "body")
	txt:SetPoint("LEFT", 6, 0); txt:SetPoint("RIGHT", -16, 0); txt:SetJustifyH("LEFT")
	dd.textFS = txt
	-- WoW's small menu arrow turned to point down (8-point SetTexCoord -- 3.3.5a
	-- textures cannot rotate), desaturated so it takes the palette's colours.
	local arrow = dd:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetSize(12, 12); arrow:SetPoint("RIGHT", -5, 0)
	arrow:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
	if arrow.SetDesaturated then arrow:SetDesaturated(true) end
	local function tint(c) arrow:SetVertexColor(unpack3(c)) end
	tint(C.textDim)
	dd.listFn, dd.getFn, dd.setFn, dd.preview = listFn, getFn, setFn, preview
	function dd:refreshText()
		local v = getFn() or ""
		txt:SetText(v)
		if preview == "font" then
			local fp = Okanvil.LSM and Okanvil.LSM:Fetch("font", v, true)
			txt:SetFont(fp or Okanvil:Font(), 13)
		end
	end
	dd:refreshText()
	dd:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(unpack3(C.borderHi)); tint(C.accentHi) end)
	dd:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(unpack3(C.border)); tint(C.textDim) end)
	dd:SetScript("OnClick", function(s) openMenu(s) end)
	return Mod(dd)
end

-- The same menu from any button, for a list that is an action rather than a
-- setting. Give the button listFn() -> { {text=, value=}, ... } and setFn(value);
-- a row whose value is false is a label and does nothing when clicked.
W.OpenMenu = openMenu

-- ============================================================
-- Dashboard -- a reusable plugin shell (header strip + live main area +
-- toggleable right stats drawer + config tabs that open as a FULL overlay
-- with a Back button + footer strip). Plugins fill the zones via callbacks
-- and never worry about the layout again. Lays a module
-- into the host panel. Returns a table of the zone frames + a few methods.
--
--   local dash = W.Dashboard(panel, {
--     title = "Recruit", icon = "Interface\\Icons\\...",
--     primaryText = fn() -> "START advertising",  -- header CTA label
--     onPrimary   = fn(),                          -- header CTA click
--     onSecondary / onTertiary = fn(),             -- extra header buttons, right to left
--     secondaryText / tertiaryText = fn() -> "",   -- their labels (live)
--     statusText  = fn() -> "|cff..Advertising OFF|r",
--     tabs = { {key=, label=, build=fn(page)}, ... },  -- config overlays
--     drawerWidth = 168, footerHeight = 26,
--   })
--   dash.main            -- fill Frame for the live content
--   dash.drawer          -- fill Frame for the stat column (right)
--   dash.footer          -- fill Frame for the bottom strip
--   dash:Refresh()       -- repaint header label/status
--   dash:ToggleDrawer()  -- show/hide the stat column
-- ============================================================
function W.Dashboard(parent, cfg)
	cfg = cfg or {}
	local D = { pages = {}, tabBtns = {} }
	local drawerW = cfg.drawerWidth or 168
	local footerH = cfg.footerHeight or 26

	-- ---- header strip (fixed, top) ----
	-- `pills` mode: the tabs are a segmented switch over ONE shared body, the way
	-- the Home page swaps Online for Snapshots -- the landing is just the first
	-- pill, so there is nothing to go "< Back" to. The overlay mode stays for
	-- pages whose tabs really are separate screens on top of a landing page.
	local pillMode = cfg.pills and true or false

	-- The setup's header: icon, gold title, a hairline under it. No filled strip:
	-- the page sits on the window's art like every other part of the shell.
	local header = W.Frame(parent, "bare")
	header:SetPoint("TOPLEFT", 0, 0); header:SetPoint("TOPRIGHT", 0, 0)
	header:SetHeight(cfg.subtitle and 48 or 40)
	D.header = header
	local hrule = header:CreateTexture(nil, "ARTWORK")
	hrule:SetTexture(FLAT); hrule:SetVertexColor(unpack3(C.border))
	hrule:SetHeight(1)
	hrule:SetPoint("BOTTOMLEFT", 10, 0); hrule:SetPoint("BOTTOMRIGHT", -10, 0)

	local ix = 10
	if cfg.icon then
		local ic = header:CreateTexture(nil, "OVERLAY")
		ic:SetSize(26, 26); ic:SetPoint("LEFT", 10, 0)
		ic:SetTexture(cfg.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		ix = 46
	end
	local htitle = W.Text(header, cfg.title, "title", "accent")
	-- subtitle = one short grey line under the title saying what the page is for
	local tdy = cfg.subtitle and 7 or 0
	htitle:SetPoint("LEFT", ix, tdy)
	D.htitle = htitle
	if cfg.subtitle then
		local hsub = W.Text(header, cfg.subtitle, "note", "dim")
		hsub:SetPoint("TOPLEFT", htitle, "BOTTOMLEFT", 0, -3)
		D.hsub = hsub
	end

	-- Filters beside the title, for a page whose controls choose WHAT the page
	-- is showing rather than acting on it.
	--
	-- The strip between the title and the buttons is dead space on every page,
	-- and a page that puts raid/size pills in its body spends a whole band on
	-- them -- which on Notes pushed the note itself halfway down the window.
	-- The page builds its own controls here; the shell only says where.
	if cfg.headerBuild then
		local anchor = W.Frame(header, "bare")
		anchor:SetPoint("LEFT", htitle, "RIGHT", 10, 0)
		anchor:SetPoint("TOP", 0, 0); anchor:SetPoint("BOTTOM", 0, 0)
		anchor:SetWidth(1)
		D.headerSlot = anchor
		cfg.headerBuild(header, anchor)
	end

	-- header CTA (primary button, right)
	local cta
	if cfg.onPrimary then
		-- primaryKind (optional) -> fn() returning "primary"/"secondary", so a CTA that
		-- is really an ON/OFF switch can show its state as the button fill.
		cta = W.Button(header, cfg.primaryText and cfg.primaryText() or "",
			cfg.primaryKind and cfg.primaryKind() or "primary")
		cta:SetSize(150, 22); cta:SetPoint("RIGHT", -10, 0)
		cta:SetScript("OnClick", function() cfg.onPrimary() end)
		D.cta = cta
	end
	-- optional secondary header button (left of the primary CTA). Its label may be
	-- dynamic (secondaryText fn) and Refresh() can hide it (secondaryShown fn).
	local cta2
	if cfg.onSecondary then
		cta2 = W.Button(header, cfg.secondaryText and cfg.secondaryText() or "", "secondary")
		cta2:SetSize(cfg.secondaryWidth or 130, 22)
		if cta then cta2:SetPoint("RIGHT", cta, "LEFT", -6, 0)
		else cta2:SetPoint("RIGHT", -10, 0) end
		cta2:SetScript("OnClick", function() cfg.onSecondary() end)
		D.cta2 = cta2
	end
	-- optional third header button, left of the secondary. Same contract as
	-- cta2: a module with three header actions (do it / share it / check it)
	-- should not have to hide the third one on a config tab nobody opens.
	local cta3
	if cfg.onTertiary then
		cta3 = W.Button(header, cfg.tertiaryText and cfg.tertiaryText() or "", "secondary")
		cta3:SetSize(cfg.tertiaryWidth or 120, 22)
		if cta2 then cta3:SetPoint("RIGHT", cta2, "LEFT", -6, 0)
		elseif cta then cta3:SetPoint("RIGHT", cta, "LEFT", -6, 0)
		else cta3:SetPoint("RIGHT", -10, 0) end
		cta3:SetScript("OnClick", function() cfg.onTertiary() end)
		if cfg.tertiaryTip then cta3:Tooltip(cfg.tertiaryTip) end
		D.cta3 = cta3
	end

	-- header status text (between title and CTA)
	local status = W.Text(header, "", nil, "dim")
	status:SetJustifyH("RIGHT")
	if cta3 then status:SetPoint("RIGHT", cta3, "LEFT", -10, 0)
	elseif cta2 then status:SetPoint("RIGHT", cta2, "LEFT", -10, 0)
	elseif cta then status:SetPoint("RIGHT", cta, "LEFT", -10, 0)
	else status:SetPoint("RIGHT", -8, 0) end
	status:SetPoint("LEFT", htitle, "RIGHT", 10, -tdy)
	D.statusFS = status

	-- horizontal breathing room so tab buttons / Back aren't glued to the edges
	local PAD = 10

	-- ---- toolbar row (config tabs + drawer toggle) ----
	local toolbar = W.Frame(parent, "bare")
	toolbar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", PAD, -4)
	toolbar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -PAD, -4)
	toolbar:SetHeight(22)
	D.toolbar = toolbar

	-- ---- content region (main + drawer), below toolbar, above footer ----
	local body = W.Frame(parent, "bare")
	body:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -4)
	body:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, footerH + 4)

	-- drawerWidth = 0 -> single-panel page: no side drawer, no toggle button.
	-- main fills the whole content region. (Guild/Modules/Settings use this.)
	local hasDrawer = drawerW > 0

	local drawer
	if hasDrawer then
		drawer = W.Frame(body, "page")
		drawer:SetPoint("TOPRIGHT", 0, 0); drawer:SetPoint("BOTTOMRIGHT", 0, 0)
		drawer:SetWidth(drawerW)
	end
	D.drawer = drawer

	local main = W.Frame(body, "page")
	main:SetPoint("TOPLEFT", 0, 0); main:SetPoint("BOTTOMLEFT", 0, 0)
	if hasDrawer then
		main:SetPoint("TOPRIGHT", drawer, "TOPLEFT", -6, 0)
		main:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMLEFT", -6, 0)
	else
		main:SetPoint("TOPRIGHT", 0, 0); main:SetPoint("BOTTOMRIGHT", 0, 0)
	end
	D.main = main
	-- (rat art is a single shared overlay mounted once on Okanvil.content --
	-- Dashboard pages no longer mount their own, which caused duplicate/misaligned
	-- rats when main + drawer + inner scrolls each drew one.)

	local drawerShown = hasDrawer
	local function layoutMain()
		main:ClearAllPoints()
		main:SetPoint("TOPLEFT", 0, 0); main:SetPoint("BOTTOMLEFT", 0, 0)
		if hasDrawer and drawerShown then
			main:SetPoint("TOPRIGHT", drawer, "TOPLEFT", -6, 0)
			main:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMLEFT", -6, 0)
		else
			main:SetPoint("TOPRIGHT", 0, 0); main:SetPoint("BOTTOMRIGHT", 0, 0)
		end
	end
	local drawerLabel = cfg.drawerLabel or "panel"
	function D:ToggleDrawer()
		if not hasDrawer then return end
		drawerShown = not drawerShown
		drawer:SetShown(drawerShown)
		layoutMain()
		if D.drawerBtn then D.drawerBtn.text:SetText(drawerShown and ("Hide " .. drawerLabel) or ("Show " .. drawerLabel)) end
	end

	-- ---- footer strip (optional; footerHeight = 0 removes it) ----
	local footer
	if footerH > 0 then
		footer = W.Frame(parent, "bare")
		footer:SetPoint("BOTTOMLEFT", 0, 0); footer:SetPoint("BOTTOMRIGHT", 0, 0)
		footer:SetHeight(footerH)
		local frule = footer:CreateTexture(nil, "ARTWORK")
		frule:SetTexture(FLAT); frule:SetVertexColor(unpack3(C.border))
		frule:SetHeight(1)
		frule:SetPoint("TOPLEFT", 10, 0); frule:SetPoint("TOPRIGHT", -10, 0)
	end
	D.footer = footer

	-- ---- page host. In overlay mode it covers everything below the header and the
	-- toolbar goes with it; in pill mode it starts BELOW the toolbar, because the
	-- pills stay on screen as the switch between pages.
	-- Transparent: the body it replaces is hidden while it shows, so the page art
	-- carries through instead of a dark slab.
	local overlay = W.Frame(parent, "bare")
	if pillMode then
		overlay:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", -PAD, -4)
		overlay:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", PAD, -4)
	else
		overlay:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	end
	overlay:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	overlay:Hide()
	D.overlay = overlay

	local back = W.Button(overlay, "< Back", "secondary")
	back:SetSize(64, 20); back:SetPoint("TOPLEFT", PAD, -8)
	local otitle = W.Text(overlay, "", nil, "accent")
	otitle:SetPoint("LEFT", back, "RIGHT", 12, 0)

	local function closeOverlay()
		-- In pill mode there is nothing to close BACK to -- a pill is always the
		-- current page -- so this is a no-op rather than a way to end up staring at
		-- an empty body with every pill unlit.
		if pillMode then return end
		overlay:Hide(); toolbar:Show(); body:Show(); if footer then footer:Show() end
		for _, b in pairs(D.tabBtns) do b._active = false; b:SetKind("tab") end
	end
	back:SetScript("OnClick", closeOverlay)
	D.CloseOverlay = closeOverlay

	local function openPage(key)
		local tab
		for _, t in ipairs(cfg.tabs or {}) do if t.key == key then tab = t break end end
		if not tab then return end
		otitle:SetText(tab.label)
		-- Build the page lazily the first time, INSIDE a flat scroll container (no
		-- Blizzard template) so a tall config page never spills off the window.
		-- tab.height gives the content height; the child scrolls if it exceeds the view.
		if not D.pages[key] then
			-- in pill mode there is no "< Back" row to clear, so the page starts at
			-- the top of the overlay instead of 34px down
			local topPad = pillMode and 6 or 34
			local sf = CreateFrame("ScrollFrame", nil, overlay)
			sf:SetPoint("TOPLEFT", PAD, -topPad); sf:SetPoint("BOTTOMRIGHT", -(PAD + 6), 8)
			local page = W.Frame(sf, "bare")
			page:SetSize(10, tab.height or 400)
			sf:SetScrollChild(page)

			local sb = CreateFrame("Slider", nil, overlay)
			sb:SetPoint("TOPRIGHT", -PAD, -topPad); sb:SetPoint("BOTTOMRIGHT", -PAD, 8); sb:SetWidth(4)
			sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
			local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetSize(4, 40)
			th:SetVertexColor(unpack3(C.accent)); sb:SetThumbTexture(th)
			sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
			sf:EnableMouseWheel(true)
			sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 30) end)
			local function relayout()
				page:SetWidth(sf:GetWidth() or 400)
				-- A `fill` page is not a tall form that scrolls: it owns its own
				-- scrolling list, so it takes the view's height and the outer
				-- scrollbar stays out of the way.
				if tab.fill then
					local h = sf:GetHeight()
					if h and h > 1 then page:SetHeight(h) end
				end
				local maxs = math.max(0, page:GetHeight() - sf:GetHeight())
				sb:SetMinMaxValues(0, maxs); sb:SetShown(maxs > 4)
			end
			sf:SetScript("OnSizeChanged", relayout)
			sf._relayout, sf.child, sf.sb = relayout, page, sb
			D.pages[key] = sf
			if tab.build then tab.build(page) end
			relayout()
		end
		for k, p in pairs(D.pages) do p:SetShown(k == key); if p.sb then p.sb:SetShown(k == key and (select(2, p.sb:GetMinMaxValues()) > 4)) end end
		if D.pages[key]._relayout then D.pages[key]._relayout() end
		if pillMode then
			-- the pills stay on screen and stay clickable: this is a switch, not a
			-- drill-down, so the toolbar is part of the page rather than something
			-- the page covers up
			body:Hide(); overlay:Show()
			back:Hide(); otitle:Hide()
			if footer then footer:Show() end
		else
			toolbar:Hide(); body:Hide(); if footer then footer:Hide() end; overlay:Show()
		end
		for _, b in pairs(D.tabBtns) do
			b._active = (b._key == key)
			-- Pills read as a segmented switch, so the picked one takes the solid
			-- gold fill the Home page uses for Online/Snapshots. Gold TEXT alone was
			-- too quiet to say "you are here" when the pills never go away.
			if b.SetKind then b:SetKind(b._active and "tabOn" or "tab") end
			b._paint(false)
		end
	end
	D.OpenPage = openPage

	-- lay the tab buttons + drawer toggle onto the toolbar. Width auto-fits the
	-- label (min 60) so longer labels like "Appearance"/"Collectors" never clip.
	local prev
	for _, t in ipairs(cfg.tabs or {}) do
		local b = W.Button(toolbar, t.label, "tab")
		local tw = (b.text and b.text:GetStringWidth() or 60) + 22
		b:SetSize(math.max(60, tw), 20); b._key = t.key
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 10, 0)
		else b:SetPoint("LEFT", 0, 0) end
		b:SetScript("OnClick", function() openPage(t.key) end)
		D.tabBtns[t.key] = b
		prev = b
	end
	-- drawer toggle (right end of toolbar) -- only when the page has a drawer.
	-- Width follows the LABEL, never a magic number: "Show collected" is wider
	-- than "Hide collected", and a fixed 96px glued the text to the border.
	if hasDrawer then
		local dbtn = W.Button(toolbar, "Hide " .. drawerLabel, "secondary")
		dbtn:SetHeight(20); dbtn:SetPoint("RIGHT", 0, 0)
		-- size to the WIDER of the two states so the button never resizes on click
		D.fitDrawerBtn = function()
			local t = dbtn.text
			local shown = t:GetText()
			local w = 0
			for _, s in ipairs({ "Hide " .. drawerLabel, "Show " .. drawerLabel }) do
				t:SetText(s)
				w = math.max(w, t:GetStringWidth() or 0)
			end
			t:SetText(shown)                       -- restore the live label
			dbtn:SetWidth(math.max(96, w + 20))    -- 10px padding each side
		end
		D.fitDrawerBtn()
		dbtn:SetScript("OnClick", function() D:ToggleDrawer() end)
		D.drawerBtn = dbtn
	end

	-- No tabs and no drawer -> nothing lives on the toolbar. Collapse it and pull
	-- the content region up under the header so the page starts flush.
	if (not cfg.tabs or #cfg.tabs == 0) and not hasDrawer then
		toolbar:Hide()
		body:ClearAllPoints()
		body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
		body:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, footerH + 4)
	end

	function D:Refresh()
		if cta and cfg.primaryText then cta.text:SetText(cfg.primaryText()) end
		if cta and cfg.primaryKind then cta:SetKind(cfg.primaryKind()) end
		if cta2 then
			if cfg.secondaryText then cta2.text:SetText(cfg.secondaryText()) end
			if cfg.secondaryShown then
				if cfg.secondaryShown() then cta2:Show() else cta2:Hide() end
			end
		end
		if cta3 then
			if cfg.tertiaryText then cta3.text:SetText(cfg.tertiaryText()) end
			if cfg.tertiaryShown then
				if cfg.tertiaryShown() then cta3:Show() else cta3:Hide() end
			end
		end
		if cfg.statusText then status:SetText(cfg.statusText() or "") end
	end
	D:Refresh()

	-- Hand the dashboard back BEFORE the first page is built. A pill page is
	-- built inside this function, so a module that stores the return value only
	-- sees it afterwards -- and any build() wanting the header or the toolbar
	-- (to put a page-wide control at its free end) found nil and fell back.
	if cfg.onReady then cfg.onReady(D) end

	-- In pill mode the first pill IS the landing -- there is no separate page
	-- underneath for it to sit on top of, so open it now rather than showing an
	-- empty body until something is clicked.
	if pillMode and cfg.tabs and cfg.tabs[1] then
		openPage(cfg.tabs[1].key)
	end
	return D
end

-- ------------------------------------------------------------
-- Popup -- draggable, screen-clamped dialog (for plugin sub-windows)
-- ------------------------------------------------------------
-- The one popup that is open.
--
-- Two of these on screen at once is unreadable: they are the same size, the
-- same colour, and they stack -- so the help panel under the id list looked
-- like one torn window. Opening a second closes the first, which also means
-- a stray one can never be left behind something.
local openPopup

-- Close whatever popup is up. Public because a panel that is kept and
-- re-Shown never goes through Popup() again, so it has to say so itself.
function Okanvil:ClosePopup(except)
	if openPopup and openPopup ~= except and openPopup:IsShown() then
		openPopup:Hide()
	end
end

function Okanvil:SetPopup(f) openPopup = f end

-- ------------------------------------------------------------
-- Forge look helpers for floating windows (the first-run setup's chrome).
--   W.Hairline(frame, "BOTTOM"|"TOP", inset)  a 1px border-coloured rule
--   W.ForgeArt(frame, alpha)  the smith at the anvil behind the window, cropped
--     to the frame's shape (keeping the right side, where he stands), with a
--     dark fade from the left so text stays readable. Follows db.ratArt.
-- ------------------------------------------------------------
function W.Hairline(frame, side, inset)
	inset = inset or 0
	local r = frame:CreateTexture(nil, "ARTWORK")
	r:SetTexture(FLAT); r:SetVertexColor(unpack3(C.border)); r:SetHeight(1)
	local s = side or "BOTTOM"
	r:SetPoint(s .. "LEFT", inset, 0); r:SetPoint(s .. "RIGHT", -inset, 0)
	return r
end

local FORGE_ART = "Interface\\AddOns\\Okanvil\\Media\\setup-bg"
function W.ForgeArt(f, alpha)
	-- BACKGROUND for the art, BORDER for the fade: separate layers, so the fade
	-- is always on top (one layer = undefined order). The backdrop sits below both.
	local art = f:CreateTexture(nil, "BACKGROUND")
	art:SetPoint("TOPLEFT", 1, -1); art:SetPoint("BOTTOMRIGHT", -1, 1)
	art:SetTexture(FORGE_ART)
	local fade = f:CreateTexture(nil, "BORDER")
	fade:SetPoint("TOPLEFT", 1, -1); fade:SetPoint("BOTTOMRIGHT", -1, 1)
	fade:SetTexture(FLAT)
	local d = C.panelD
	fade:SetGradientAlpha("HORIZONTAL", d[1], d[2], d[3], 0.92, d[1], d[2], d[3], 0.40)
	local function crop()
		local w, h = f:GetWidth() or 0, f:GetHeight() or 0
		if w <= 0 or h <= 0 then return end
		if w >= h then
			local span = h / w
			local top = math.max(0, math.min(1 - span, 0.55 - span / 2))
			art:SetTexCoord(0, 1, top, top + span)
		else
			local span = w / h
			art:SetTexCoord(1 - span, 1, 0, 1)
		end
	end
	local function refresh()
		local off = Okanvil.db and (Okanvil.db.ratArt or "on") == "off"
		if off then art:Hide(); fade:Hide(); return end
		art:SetAlpha(alpha or 0.22); art:Show(); fade:Show(); crop()
	end
	f:HookScript("OnSizeChanged", crop)
	f:HookScript("OnShow", refresh)
	refresh()
	return art, fade
end

function Okanvil:Popup(title)
	self:ClosePopup()
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetPoint("CENTER")
	self:Skin(f)
	-- Opaque, whatever the window alpha is set to. The shell can be made
	-- see-through so the fight shows behind it; a popup is the opposite --
	-- it exists to be READ, and at 60% the raid frames behind it turned a
	-- table of spell ids into noise.
	local C = Okanvil.Colors
	f:SetBackdropColor(C.panelD[1], C.panelD[2], C.panelD[3], 0.97)
	f:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
	W.ForgeArt(f, 0.22)
	-- The setup's header: no raised strip, a gold title, a hairline under it.
	local hdr = W.Frame(f, "bare")
	hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1); hdr:SetHeight(26)
	hdr:EnableMouse(true); hdr:RegisterForDrag("LeftButton")
	hdr:SetScript("OnDragStart", function() f:StartMoving() end)
	hdr:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
	W.Hairline(hdr, "BOTTOM", 8)
	local t = W.Text(hdr, title, "head", "accent"); t:SetPoint("LEFT", 10, 0)
	local close = W.Button(hdr, "X"); close:SetSize(20, 18); close:SetPoint("RIGHT", -2, 0)
	close:SetScript("OnClick", function() f:Hide() end)
	f.header, f.title = hdr, t

	openPopup = f
	f:HookScript("OnHide", function(sf)
		if openPopup == sf then openPopup = nil end
	end)
	return Mod(f)
end

-- ------------------------------------------------------------
-- Confirm -- our OWN "are you sure?" dialog (NOT Blizzard's StaticPopup).
--
-- WoW reuses one shared pool of StaticPopup frames for every dialog, addon and
-- Blizzard alike (REPLACE_ENCHANT, trade, etc). Running a PROTECTED call (like
-- GiveMasterLoot) from a StaticPopup button taints that shared frame, and the next
-- protected action landing on it -- e.g. confirming a helm enchant -- gets blocked,
-- cancelling the player's cast. Owning our own frame side-steps the whole pool, so
-- our confirms can never taint Blizzard's dialogs.
--
--   Okanvil:Confirm(text, acceptLabel, onAccept[, onCancel])
--
-- One shared, reused frame. Calling it again just re-labels and re-shows.
-- ------------------------------------------------------------
local confirmDlg
-- Exposed so a caller can ask "is a question already on screen?" before adding
-- its own. There is ONE frame, so two modules asking at the same moment -- which
-- is exactly what a zone-in does -- means the second silently replaces the
-- first, and the player only ever sees one of them.
function Okanvil:ConfirmBusy()
	return confirmDlg and confirmDlg:IsShown() and true or false
end

function Okanvil:Confirm(text, acceptLabel, onAccept, onCancel)
	local f = confirmDlg
	if not f then
		f = self:Popup("Confirm")
		f:SetSize(340, 150)
		f:SetFrameStrata("FULLSCREEN_DIALOG")   -- above plugin popups + the loot window

		local msg = W.Text(f, "", nil)
		msg:SetPoint("TOPLEFT", 14, -34)
		msg:SetPoint("TOPRIGHT", -14, -34)
		msg:SetJustifyH("LEFT")
		msg:SetJustifyV("TOP")
		-- Anchoring both sides gives a width but NOT wrapping: without this a
		-- question longer than the dialog is silently cut off mid-word.
		if msg.SetWordWrap then msg:SetWordWrap(true) end
		msg:SetHeight(60)
		f.msg = msg

		local ok = W.Button(f, "", "primary")
		ok:SetSize(140, 24)
		ok:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 10)
		f.ok = ok

		local no = W.Button(f, CANCEL, "secondary")
		no:SetSize(140, 24)
		no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 10)
		f.no = no

		-- Handlers are re-bound per show (closures capture that show's callbacks).
		-- Both buttons hide first, THEN run the callback -- so the protected call in
		-- onAccept runs with the dialog already gone, never mid-click on the frame.
		ok:SetScript("OnClick", function()
			f:Hide()
			if f._accept then f._accept() end
		end)
		no:SetScript("OnClick", function()
			f:Hide()
			if f._cancel then f._cancel() end
		end)
		confirmDlg = f
	end

	f.msg:SetText(text or "")
	f.ok.text:SetText(acceptLabel or OKAY)
	-- Re-assert the label colour AFTER the text is set. The accept button is a solid
	-- gold fill, so its label must be the near-black `dark` -- anything lighter is
	-- gold-on-gold and unreadable, which is what the confirm button was showing.
	if f.ok._paint then f.ok._paint(f.ok._hover) end
	f._accept = onAccept
	f._cancel = onCancel
	f:Show()
	return f
end

-- ------------------------------------------------------------
-- Ask for one short string.
--
--   Okanvil:Prompt(title, label, initial, onAccept[, onCancel])
--
-- Confirm's shape with a single-line box in it. ShowImport was the only text
-- entry we had, and it is a 440x320 multiline panel built for pasting blocks of
-- JSON -- far too much furniture for "name this note".
--
-- The box does NOT take focus by itself. A captured EditBox eats W/A/S/D, and
-- an unexpected one is how you die in a fight; click it to type.
-- ------------------------------------------------------------
local promptDlg
function Okanvil:Prompt(title, label, initial, onAccept, onCancel)
	local f = promptDlg
	if not f then
		f = self:Popup("Prompt")
		f:SetSize(340, 150)
		f:SetFrameStrata("FULLSCREEN_DIALOG")

		local lbl = W.Text(f, "", "note", "dim")
		lbl:SetPoint("TOPLEFT", 14, -36)
		lbl:SetPoint("TOPRIGHT", -14, -36)
		lbl:SetJustifyH("LEFT")
		f.lbl = lbl

		local box = W.EditBox(f)
		box:SetHeight(24)
		box:SetPoint("TOPLEFT", 14, -56)
		box:SetPoint("TOPRIGHT", -14, -56)
		f.box = box

		local ok = W.Button(f, OKAY, "primary")
		ok:SetSize(140, 24)
		ok:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 10)
		f.ok = ok

		local no = W.Button(f, CANCEL, "secondary")
		no:SetSize(140, 24)
		no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 10)

		local function accept()
			local v = f.box.edit:GetText() or ""
			f.box.edit:ClearFocus()
			f:Hide()
			if f._accept then f._accept(v) end
		end
		ok:SetScript("OnClick", accept)
		box.edit:SetScript("OnEnterPressed", accept)
		box.edit:SetScript("OnEscapePressed", function() f:Hide() end)
		no:SetScript("OnClick", function()
			f.box.edit:ClearFocus()
			f:Hide()
			if f._cancel then f._cancel() end
		end)
		-- Whatever closed it, the keyboard goes back to the game.
		f:HookScript("OnHide", function() f.box.edit:ClearFocus() end)
		promptDlg = f
	end

	if f.title then f.title:SetText(title or "") end
	f.lbl:SetText(label or "")
	f.box.edit:SetText(initial or "")
	if f.ok._paint then f.ok._paint(f.ok._hover) end
	f._accept, f._cancel = onAccept, onCancel
	f:Show()
	return f
end

-- ------------------------------------------------------------
-- Export dialog -- a big multiline EditBox with the text pre-selected
-- (Ctrl+C to copy). One shared, reused dialog. For roster/attendance JSON.
-- ------------------------------------------------------------
local exportDlg
function Okanvil:ShowExport(text, label)
	local f = exportDlg
	if not f then
		f = self:Popup("Export")
		f:SetSize(440, 320)
		local hint = W.Text(f, "Ctrl+C to copy, then paste into the hub importer.", "note", "dim")
		hint:SetPoint("TOPLEFT", 10, -30)

		local box = W.Frame(f, "input")
		box:SetPoint("TOPLEFT", 8, -48); box:SetPoint("BOTTOMRIGHT", -8, 8)
		-- flat scroll (no Blizzard template): plain ScrollFrame + our own slider
		local sf = CreateFrame("ScrollFrame", nil, box)
		sf:SetPoint("TOPLEFT", 4, -4); sf:SetPoint("BOTTOMRIGHT", -10, 4)
		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetWidth(390)
		eb:SetFontObject(GameFontHighlightSmall)
		eb:SetTextColor(unpack3(C.text))
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		Okanvil:TrackEditBox(eb)
		-- SAFETY: always release the keyboard when the popup closes, so a lingering
		-- focus can never eat W/A/S/D in the game world.
		f:HookScript("OnHide", function() eb:ClearFocus() end)
		sf:SetScrollChild(eb)

		local sb = CreateFrame("Slider", nil, box)
		sb:SetPoint("TOPRIGHT", -3, -4); sb:SetPoint("BOTTOMRIGHT", -3, 4); sb:SetWidth(4)
		sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
		local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetVertexColor(unpack3(C.accent)); th:SetSize(4, 40)
		sb:SetThumbTexture(th)
		sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
		sf:EnableMouseWheel(true)
		sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 24) end)
		local function range()
			local max = math.max(0, eb:GetHeight() - sf:GetHeight())
			sb:SetMinMaxValues(0, max); sb:SetShown(max > 0)
		end
		eb:SetScript("OnTextChanged", range)
		f.eb, f._range = eb, range
		exportDlg = f
	end
	f.title:SetText("|cffffd200" .. (label or "Export") .. "|r")
	f.eb:SetText(text or "")
	f:Show()
	if f._range then f._range() end
	-- Focus the box so Ctrl+A/Ctrl+C works -- but NEVER while in combat (grabbing
	-- the keyboard mid-fight would eat your movement keys). Out of combat only.
	if not (InCombatLockdown and InCombatLockdown()) then
		f.eb:SetFocus()
		f.eb:HighlightText()
	end
	f.eb:SetCursorPosition(0)
end

-- ------------------------------------------------------------
-- Import dialog -- an empty multiline EditBox plus one action button. Same shape as
-- ShowExport, but the text flows the other way: you paste, we hand the string to
-- `onAccept`. Used to feed the addon a list of item ids from the website.
--   Okanvil:ShowImport("Paste ids", "Scan", function(text) ... end)
-- ------------------------------------------------------------
local importDlg
function Okanvil:ShowImport(label, actionText, onAccept, hintText)
	local f = importDlg
	if not f then
		f = self:Popup("Import")
		f:SetSize(440, 320)
		local hint = W.Text(f, "", "note", "dim")
		hint:SetPoint("TOPLEFT", 10, -30)

		local go = W.Button(f, "Go", "primary")
		go:SetSize(90, 22); go:SetPoint("BOTTOMRIGHT", -8, 8)

		local box = W.Frame(f, "input")
		box:SetPoint("TOPLEFT", 8, -48); box:SetPoint("BOTTOMRIGHT", -8, 38)
		local sf = CreateFrame("ScrollFrame", nil, box)
		sf:SetPoint("TOPLEFT", 4, -4); sf:SetPoint("BOTTOMRIGHT", -10, 4)
		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetWidth(390)
		eb:SetFontObject(GameFontHighlightSmall)
		eb:SetTextColor(unpack3(C.text))
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		Okanvil:TrackEditBox(eb)
		-- SAFETY: release the keyboard on close, so a lingering focus can never eat
		-- W/A/S/D out in the world.
		f:HookScript("OnHide", function() eb:ClearFocus() end)
		sf:SetScrollChild(eb)

		local sb = CreateFrame("Slider", nil, box)
		sb:SetPoint("TOPRIGHT", -3, -4); sb:SetPoint("BOTTOMRIGHT", -3, 4); sb:SetWidth(4)
		sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
		local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetVertexColor(unpack3(C.accent)); th:SetSize(4, 40)
		sb:SetThumbTexture(th)
		sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
		sf:EnableMouseWheel(true)
		sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 24) end)
		local function range()
			local max = math.max(0, eb:GetHeight() - sf:GetHeight())
			sb:SetMinMaxValues(0, max); sb:SetShown(max > 0)
		end
		eb:SetScript("OnTextChanged", range)
		f.eb, f._range, f.go, f.hint = eb, range, go, hint
		importDlg = f
	end
	f.title:SetText("|cffffd200" .. (label or "Import") .. "|r")
	f.hint:SetText(hintText or "Paste, then press the button.")
	f.go.text:SetText(actionText or "Go")
	f.go:SetScript("OnClick", function()
		local txt = f.eb:GetText() or ""
		f.eb:ClearFocus()
		f:Hide()
		if onAccept then onAccept(txt) end
	end)
	f.eb:SetText("")
	f:Show()
	if f._range then f._range() end
	if not (InCombatLockdown and InCombatLockdown()) then f.eb:SetFocus() end
end
