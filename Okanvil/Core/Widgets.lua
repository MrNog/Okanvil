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
-- :OnLeave :Color, and hand back `self` so calls compose like MRT's.
-- ============================================================

local Okanvil = Okanvil
local W = {}
Okanvil.W = W

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

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
	if kind == "page" then
		-- Fully invisible container: transparent body AND transparent border. The
		-- outer `content` well already frames the page; drawing this panel's own
		-- 1px border created a seam line that cut across the rat where main/drawer
		-- meet. No fill, no edge => the single content rat reads as one clean
		-- background behind the page. NOT registered for the opacity slider.
		frame:SetBackdrop(nil)
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

-- shared tooltip wiring (used by anything with a ._tip)
local function tipEnter(self)
	if not self._tip then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(self._tip, unpack3(C.text))
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
function W.Text(parent, text, size, role)
	local fs = Okanvil:NewText(parent, "OVERLAY")
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
	local t = W.Text(b, text, 12)
	t:SetPoint("CENTER")
	b.text = t
	b._kind = kind

	local function paint(hover)
		if primary then
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
	local tick = box:CreateTexture(nil, "OVERLAY")
	tick:SetTexture(FLAT)
	tick:SetPoint("TOPLEFT", 3, -3)
	tick:SetPoint("BOTTOMRIGHT", -3, 3)
	tick:SetVertexColor(unpack3(C.accent))
	local t = W.Text(b, label)
	t:SetPoint("LEFT", b, "RIGHT", 6, 0)
	b.text = t
	local function refresh() tick:SetShown(getFn and getFn() or false) end
	refresh()
	b:SetScript("OnClick", function()
		if setFn then setFn(not (getFn and getFn())) end
		refresh()
	end)
	b:SetScript("OnEnter", function() box:SetBackdropBorderColor(unpack3(C.borderHi)) end)
	b:SetScript("OnLeave", function() box:SetBackdropBorderColor(unpack3(C.border)) end)
	b.refresh = refresh
	return Mod(b)
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
	local fp = Okanvil:Font()
	e:SetFont(fp, 12)                 -- fixed size: the box height is fixed, so the
	e:SetTextColor(unpack3(C.text))   -- global font slider must not overflow it
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEditFocusGained", function() box:SetBackdropBorderColor(unpack3(C.borderHi)) end)
	e:SetScript("OnEditFocusLost", function() box:SetBackdropBorderColor(unpack3(C.border)) end)
	if onEnter then
		e:SetScript("OnEnterPressed", function(s) onEnter(s:GetText()); s:ClearFocus() end)
	end
	Okanvil:TrackEditBox(e)   -- so the window can release keyboard focus on hide
	box.edit = e
	function box:Size(w, h) box:SetSize(w, h); return box end
	function box:Point(...) box:SetPoint(...); return box end
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

	box.edit = e
	function box:SetText(t) e:SetText(t or "") end
	function box:GetText() return e:GetText() end
	function box:Size(w, h) box:SetSize(w, h); return box end
	function box:Point(...) box:SetPoint(...); return box end
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
	local rowH = owner.preview == "statusbar" and 20 or 18
	local y = 0
	for _, r in ipairs(m.rows) do r:Hide() end
	for i, it in ipairs(items) do
		local val = type(it) == "table" and it.value or it
		local label = type(it) == "table" and it.text or it
		local r = m.rows[i]
		if not r then
			r = CreateFrame("Button", nil, m.child)
			r.tex = r:CreateTexture(nil, "ARTWORK")
			r.tex:SetPoint("TOPLEFT", 1, -1); r.tex:SetPoint("BOTTOMRIGHT", -1, 1); r.tex:Hide()
			r.t = r:CreateFontString(nil, "OVERLAY")
			r.t:SetPoint("LEFT", 6, 0); r.t:SetJustifyH("LEFT")
			r.t:SetShadowColor(0, 0, 0, 1); r.t:SetShadowOffset(1, -1)
			local hl = r:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints(); hl:SetTexture(FLAT); hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.18)
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
		if val == cur then r.t:SetTextColor(unpack3(C.accent))
		elseif owner.preview == "statusbar" then r.t:SetTextColor(1, 1, 1)
		else r.t:SetTextColor(unpack3(C.text)) end
		r:SetScript("OnClick", function()
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
	local txt = W.Text(dd, nil, 12)
	txt:SetPoint("LEFT", 6, 0); txt:SetPoint("RIGHT", -16, 0); txt:SetJustifyH("LEFT")
	dd.textFS = txt
	local arrow = W.Text(dd, "v", 12, "dim")
	arrow:SetPoint("RIGHT", -6, 0)
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
	dd:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(unpack3(C.borderHi)) end)
	dd:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(unpack3(C.border)) end)
	dd:SetScript("OnClick", function(s) openMenu(s) end)
	return Mod(dd)
end

-- ============================================================
-- Dashboard -- a reusable plugin shell (header strip + live main area +
-- toggleable right stats drawer + config tabs that open as a FULL overlay
-- with a Back button + footer strip). Plugins fill the zones via callbacks
-- and never worry about the layout again. Modelled on how MRT lays a module
-- into the host panel. Returns a table of the zone frames + a few methods.
--
--   local dash = W.Dashboard(panel, {
--     title = "Recruit", icon = "Interface\\Icons\\...",
--     primaryText = fn() -> "START advertising",  -- header CTA label
--     onPrimary   = fn(),                          -- header CTA click
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
	local header = W.Frame(parent, "raise")
	header:SetPoint("TOPLEFT", 0, 0); header:SetPoint("TOPRIGHT", 0, 0); header:SetHeight(30)
	D.header = header

	local ix = 10
	if cfg.icon then
		local ic = header:CreateTexture(nil, "OVERLAY")
		ic:SetSize(18, 18); ic:SetPoint("LEFT", 10, 0)
		ic:SetTexture(cfg.icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		ix = 32
	end
	local htitle = W.Text(header, cfg.title, nil, "accent")
	htitle:SetPoint("LEFT", ix, 0)

	-- header CTA (primary button, right)
	local cta
	if cfg.onPrimary then
		cta = W.Button(header, cfg.primaryText and cfg.primaryText() or "", "primary")
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
	-- header status text (between title and CTA)
	local status = W.Text(header, "", nil, "dim")
	status:SetJustifyH("RIGHT")
	if cta2 then status:SetPoint("RIGHT", cta2, "LEFT", -10, 0)
	elseif cta then status:SetPoint("RIGHT", cta, "LEFT", -10, 0)
	else status:SetPoint("RIGHT", -8, 0) end
	status:SetPoint("LEFT", htitle, "RIGHT", 10, 0)
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
		footer = W.Frame(parent, "dark")
		footer:SetPoint("BOTTOMLEFT", 0, 0); footer:SetPoint("BOTTOMRIGHT", 0, 0)
		footer:SetHeight(footerH)
	end
	D.footer = footer

	-- ---- config overlay (full-cover page host, hidden until a tab is clicked) ----
	local overlay = W.Frame(parent, "dark")
	overlay:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	overlay:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	overlay:Hide()
	D.overlay = overlay

	local back = W.Button(overlay, "< Back", "secondary")
	back:SetSize(64, 20); back:SetPoint("TOPLEFT", PAD, -8)
	local otitle = W.Text(overlay, "", nil, "accent")
	otitle:SetPoint("LEFT", back, "RIGHT", 12, 0)

	local function closeOverlay()
		overlay:Hide(); toolbar:Show(); body:Show(); if footer then footer:Show() end
		for _, b in pairs(D.tabBtns) do b._active = false; b._paint(false) end
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
			local sf = CreateFrame("ScrollFrame", nil, overlay)
			sf:SetPoint("TOPLEFT", PAD, -34); sf:SetPoint("BOTTOMRIGHT", -(PAD + 6), 8)
			local page = W.Frame(sf, "bare")
			page:SetSize(10, tab.height or 400)
			sf:SetScrollChild(page)

			local sb = CreateFrame("Slider", nil, overlay)
			sb:SetPoint("TOPRIGHT", -PAD, -34); sb:SetPoint("BOTTOMRIGHT", -PAD, 8); sb:SetWidth(4)
			sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
			local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetSize(4, 40)
			th:SetVertexColor(unpack3(C.accent)); sb:SetThumbTexture(th)
			sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
			sf:EnableMouseWheel(true)
			sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 30) end)
			local function relayout()
				page:SetWidth(sf:GetWidth() or 400)
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
		toolbar:Hide(); body:Hide(); if footer then footer:Hide() end; overlay:Show()
		for _, b in pairs(D.tabBtns) do b._active = (b._key == key); b._paint(false) end
	end
	D.OpenPage = openPage

	-- lay the tab buttons + drawer toggle onto the toolbar. Width auto-fits the
	-- label (min 60) so longer labels like "Appearance"/"Collectors" never clip.
	local prev
	for _, t in ipairs(cfg.tabs or {}) do
		local b = W.Button(toolbar, t.label, "secondary")
		local tw = (b.text and b.text:GetStringWidth() or 60) + 22
		b:SetSize(math.max(60, tw), 20); b._key = t.key
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
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
		if cta2 then
			if cfg.secondaryText then cta2.text:SetText(cfg.secondaryText()) end
			if cfg.secondaryShown then
				if cfg.secondaryShown() then cta2:Show() else cta2:Hide() end
			end
		end
		if cfg.statusText then status:SetText(cfg.statusText() or "") end
	end
	D:Refresh()
	return D
end

-- ------------------------------------------------------------
-- Popup -- draggable, screen-clamped dialog (for plugin sub-windows)
-- ------------------------------------------------------------
function Okanvil:Popup(title)
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetPoint("CENTER")
	self:Skin(f)
	local hdr = W.Frame(f, "raise")
	hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1); hdr:SetHeight(24)
	hdr:EnableMouse(true); hdr:RegisterForDrag("LeftButton")
	hdr:SetScript("OnDragStart", function() f:StartMoving() end)
	hdr:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
	-- title must be a child of the HEADER bar (not the window) or the bar's
	-- raised backdrop draws over it -> dark/invisible title (same fix as the shell).
	local t = W.Text(hdr, title, nil, "accent"); t:SetPoint("LEFT", 8, 0)
	local close = W.Button(hdr, "X"); close:SetSize(20, 18); close:SetPoint("RIGHT", -2, 0)
	close:SetScript("OnClick", function() f:Hide() end)
	f.header, f.title = hdr, t
	return Mod(f)
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
		local hint = W.Text(f, "Ctrl+C to copy, then paste into the hub importer.", 10, "dim")
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
