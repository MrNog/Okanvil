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
	-- "on / done / good" is gold like every other state: the UI kit has no green
	ok       = { 1.0, 0.82, 0.0 },
	danger   = { 0.85, 0.30, 0.32 },
	dark     = { 0.078, 0.082, 0.090 },    -- text on gold buttons
	-- the UI kit's window: near-black body, bronze edge
	body     = { 0.043, 0.043, 0.047 },
	edge     = { 0.235, 0.204, 0.157 },
	titleText = { 0.878, 0.761, 0.478 },   -- a window's title in its title bar
	cream    = { 0.953, 0.918, 0.839 },    -- Morpheus headers over the art
}
Okanvil.Colors = C

local function unpack3(t, a) return t[1], t[2], t[3], a or 1 end

-- ------------------------------------------------------------
-- UI kit pieces (wow-addons/UI-KIT.md): the red X, the red plate button that
-- matches it, framed icons, the medallion, the checkbox, the stepper and the
-- title bar. The art lives in Media\UI.
-- ------------------------------------------------------------
local UI = "Interface\\AddOns\\Okanvil\\Media\\UI\\"
W.UI = UI
-- the header face of the newer game's talent screen: outlined, with a hard shadow
W.TITLE_FONT = "Fonts\\MORPHEUS.TTF"

-- 3.3.5a's IsEnabled returns 1 or 0, and 0 is truthy in Lua.
local function isDisabled(b)
	local enabled = b:IsEnabled()
	return not enabled or enabled == 0
end

-- the red X, all four states from one sheet
function W.CloseButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(24, 24)
	-- a plain Button has no state textures yet, so each one is set before it is cut
	local function dress(state, l, r, t, bottom, blend)
		b["Set" .. state .. "Texture"](b, UI .. "redbutton2x")
		local tex = b["Get" .. state .. "Texture"](b)
		tex:SetTexCoord(l, r, t, bottom)
		if blend then tex:SetBlendMode(blend) end
	end
	dress("Normal", 39 / 256, 75 / 256, 1 / 128, 39 / 128)
	dress("Pushed", 39 / 256, 75 / 256, 81 / 128, 119 / 128)
	dress("Disabled", 39 / 256, 75 / 256, 41 / 128, 79 / 128)
	dress("Highlight", 115 / 256, 151 / 256, 1 / 128, 39 / 128, "ADD")
	-- always square: callers written for the old text X asked for 22x20 and the art stretched
	local setSize = b.SetSize
	function b:SetSize(w, h)
		local sz = math.max(w or 24, h or 24)
		setSize(self, sz, sz)
	end
	-- the same fields a W.Button has, so code written for an "X" W.Button still runs
	b.text = b:CreateFontString(nil, "OVERLAY")
	b.text:Hide()
	b._paint = function() end
	function b:SetKind() end
	return b
end

-- The X's twin with a centred minus (Media\UI\minus, cut from the X's sheet):
-- normal, pushed and disabled side by side; the highlight is the X's own.
function W.MinusButton(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(24, 24)
	local function dress(state, l, r, t, bottom, tex, blend)
		b["Set" .. state .. "Texture"](b, tex)
		local x = b["Get" .. state .. "Texture"](b)
		x:SetTexCoord(l, r, t, bottom)
		if blend then x:SetBlendMode(blend) end
	end
	dress("Normal", 0, 36 / 128, 0, 38 / 64, UI .. "minus")
	dress("Pushed", 40 / 128, 76 / 128, 0, 38 / 64, UI .. "minus")
	dress("Disabled", 80 / 128, 116 / 128, 0, 38 / 64, UI .. "minus")
	dress("Highlight", 115 / 256, 151 / 256, 1 / 128, 39 / 128, UI .. "redbutton2x", "ADD")
	return b
end

-- the red plate: a three-slice whose caps keep the frame's corners at any width
local PLATE_W, PLATE_H, CAP_W = 128, 64, 32
local PLATE_U = {
	left = { 0, CAP_W / PLATE_W },
	middle = { CAP_W / PLATE_W, (PLATE_W - CAP_W) / PLATE_W },
	right = { (PLATE_W - CAP_W) / PLATE_W, 1 },
}

local function threeSlice(b, layer, tex, u, v)
	local pieces = {}
	for _, part in ipairs({ "left", "middle", "right" }) do
		local t = b:CreateTexture(nil, layer)
		t:SetTexture(tex)
		t:SetTexCoord(u[part][1], u[part][2], v[1], v[2])
		pieces[part] = t
	end
	pieces.left:SetPoint("TOPLEFT"); pieces.left:SetPoint("BOTTOMLEFT")
	pieces.right:SetPoint("TOPRIGHT"); pieces.right:SetPoint("BOTTOMRIGHT")
	pieces.middle:SetPoint("TOPLEFT", pieces.left, "TOPRIGHT")
	pieces.middle:SetPoint("BOTTOMRIGHT", pieces.right, "BOTTOMLEFT")
	return pieces
end

local function capWidth(pieces, w)
	pieces.left:SetWidth(w); pieces.right:SetWidth(w)
end

local function eachPiece(pieces, fn) for _, t in pairs(pieces) do fn(t) end end

-- the bronze plate (retail's dropdown and button). Media/UI/plate, 128x512: one
-- state a row, 80 apart (78 tall); caps 24 wide on either side of a 16px middle
-- (one column repeated, sampled away from the joins).
-- The art carries its shadow, so it is drawn past the frame: drawn for a 25 tall
-- box it is 39 tall and reaches 7 out on every side, the caps 12 wide.
local BRONZE = UI .. "plate"
local BRONZE_ROW = { normal = 0, hover = 1, open = 2, disabled = 3 }
local BRONZE_U = { left = { 0, 24 / 128 }, middle = { 28 / 128, 36 / 128 }, right = { 40 / 128, 64 / 128 } }

local function bronzePlate(b)
	local pieces = {}
	for _, part in ipairs({ "left", "middle", "right" }) do
		local t = b:CreateTexture(nil, "BACKGROUND")
		t:SetTexture(BRONZE)
		pieces[part] = t
	end
	local function size()
		local h = b:GetHeight() or 25
		if h <= 0 then h = 25 end
		local out, cap = 7 * h / 25, 12 * h / 25
		pieces.left:ClearAllPoints()
		pieces.left:SetPoint("TOPLEFT", -out, out); pieces.left:SetPoint("BOTTOMLEFT", -out, -out)
		pieces.right:ClearAllPoints()
		pieces.right:SetPoint("TOPRIGHT", out, out); pieces.right:SetPoint("BOTTOMRIGHT", out, -out)
		capWidth(pieces, cap)
		pieces.middle:ClearAllPoints()
		pieces.middle:SetPoint("TOPLEFT", pieces.left, "TOPRIGHT")
		pieces.middle:SetPoint("BOTTOMRIGHT", pieces.right, "BOTTOMLEFT")
	end
	b:HookScript("OnSizeChanged", size)
	size()
	function pieces:State(state)
		local i = BRONZE_ROW[state] or 0
		local v0, v1 = i * 80 / 512, (i * 80 + 78) / 512
		for part, u in pairs(BRONZE_U) do self[part]:SetTexCoord(u[1], u[2], v0, v1) end
	end
	function pieces:SetShown(on)
		for _, part in ipairs({ "left", "middle", "right" }) do
			if on then self[part]:Show() else self[part]:Hide() end
		end
	end
	pieces:State("normal")
	return pieces
end

-- an icon in the gold (or grey) octagon frame. The frame's opening is 75% of it,
-- so the icon is drawn at 80%: its edge tucks under the metal.
local FRAME_GOLD = { 0, 80 / 256, 0, 80 / 128 }
local FRAME_GREY = { 128 / 256, 208 / 256, 0, 80 / 128 }

-- dresses an existing frame: f.icon + f.frame. Returns f.
function W.DressFramedIcon(f, texture, size)
	local icon = f.icon or f:CreateTexture(nil, "ARTWORK")
	icon:ClearAllPoints()
	icon:SetSize(size * 0.8, size * 0.8)
	icon:SetPoint("CENTER")
	if texture then icon:SetTexture(texture) end
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- a re-dress (new size) keeps the frame's gold / grey state
	local fresh = not f.frame
	local frame = f.frame or f:CreateTexture(nil, "OVERLAY")
	frame:ClearAllPoints()
	frame:SetSize(size, size)
	frame:SetPoint("CENTER", icon, "CENTER")
	if fresh then
		frame:SetTexture(UI .. "iconframes")
		frame:SetTexCoord(unpack(FRAME_GOLD))
	end
	f.icon, f.frame = icon, frame
	return f
end

-- gold frame = current / on; grey frame = the rest
function W.SetFramedIconGold(f, gold)
	if f.frame then f.frame:SetTexCoord(unpack(gold and FRAME_GOLD or FRAME_GREY)) end
end

-- grey frame + grey icon: cannot act right now
function W.SetFramedIconUsable(f, usable)
	W.SetFramedIconGold(f, usable)
	if f.icon then
		f.icon:SetDesaturated(not usable)
		local s = usable and 1 or 0.6
		f.icon:SetVertexColor(s, s, s)
	end
end

function W.FramedIcon(parent, texture, size, gold)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	W.DressFramedIcon(f, texture, size)
	W.SetFramedIconGold(f, gold ~= false)
	return f
end

function W.FramedIconButton(parent, texture, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	W.DressFramedIcon(b, texture, size)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")
	hl:SetAllPoints(b.icon)
	return b
end

-- Okanvil's app icon (the anvil) cut round inside a gold ring, over a window's
-- top-left corner. The picture is 92% of the ring so no sliver shows past it.
function W.Medallion(parent, size)
	size = size or 60
	local m = CreateFrame("Frame", nil, parent)
	m:SetSize(size, size)
	m:SetPoint("CENTER", parent, "TOPLEFT", 10, -8)
	m:SetFrameLevel(parent:GetFrameLevel() + 10)
	local icon = m:CreateTexture(nil, "ARTWORK")
	icon:SetSize(size * 0.92, size * 0.92)
	icon:SetPoint("CENTER")
	icon:SetTexture(UI .. "medallion")
	local ring = m:CreateTexture(nil, "OVERLAY")
	ring:SetAllPoints(m)
	ring:SetTexture(UI .. "ring")
	ring:SetVertexColor(0.886, 0.722, 0.263)
	m.icon, m.ring = icon, ring
	return m
end

-- A window's title bar: no strip of its own (the title sits on the window's art),
-- a hairline under it, the title centred in gold. The caller adds the X
-- (W.CloseButton) at its right end.
function W.TitleBar(parent, height)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(height or 26)
	bar._okChrome = true
	-- every button on a title bar is drawn like the X beside it: the red plate
	bar._okTitleBar = true
	-- 6px in, like the art; its top corners are cut by covers (below)
	bar:SetPoint("TOPLEFT", 6, -6)
	bar:SetPoint("TOPRIGHT", -6, -6)
	local rule = bar:CreateTexture(nil, "BORDER")
	rule:SetTexture(FLAT); rule:SetVertexColor(unpack3(C.edge)); rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
	-- the bar's top corners follow the window's cut
	bar.covers = W.CoverCorners(bar, bar, W.COVER, C.body[1], C.body[2], C.body[3], 1, { "TOPLEFT", "TOPRIGHT" })
	-- they wear the window's fill colour, like the art's covers
	local pch = parent._okChamfer
	if pch then
		pch.covers = pch.covers or {}
		pch.covers[#pch.covers + 1] = bar.covers
		local c = pch.color
		if c and (c[4] or 0) > 0 then bar.covers:Tint(c[1], c[2], c[3], c[4]) end
	end
	local title = bar:CreateFontString(nil, "OVERLAY")
	title:SetFont(STANDARD_TEXT_FONT, 15)
	title:SetShadowColor(0, 0, 0, 1); title:SetShadowOffset(1, -1)
	title:SetTextColor(unpack3(C.accentText))
	title:SetPoint("CENTER")
	bar.title = title
	return bar, title
end

-- a header in the talent screen's face: Morpheus, outlined, hard shadow, cream
function W.TitleText(parent, text, size)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(W.TITLE_FONT, size or 20, "OUTLINE")
	fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(2, -2)
	fs:SetTextColor(unpack3(C.cream))
	if text then fs:SetText(text) end
	return fs
end

-- the kit's checkbox: box + tick textures on `parent`, size x size, tick hidden
local CHECK_BOX = { 0.5, 0.734375, 0.015625, 0.12890625 }
local CHECK_MARK = { 0.03125, 0.265625, 0.203125, 0.31640625 }
function W.CheckTextures(parent, size)
	local box = parent:CreateTexture(nil, "ARTWORK")
	box:SetSize(size, size)
	box:SetTexture(UI .. "controls")
	box:SetTexCoord(unpack(CHECK_BOX))
	local tick = parent:CreateTexture(nil, "OVERLAY")
	tick:SetAllPoints(box)
	tick:SetTexture(UI .. "controls")
	tick:SetTexCoord(unpack(CHECK_MARK))
	tick:Hide()
	return box, tick
end

-- the kit's field edge (the search field's three-slice) behind any one-line box
local FIELD_TEX = UI .. "controls"
local FIELD_U = { left = { 0.03125, 0.15625 }, middle = { 0.40625, 0.4375 }, right = { 0.21875, 0.34375 } }
local FIELD_V = { 0.015625, 0.171875 }
local function dressField(f)
	local pieces = threeSlice(f, "BACKGROUND", FIELD_TEX, FIELD_U, FIELD_V)
	local function size() capWidth(pieces, math.max(4, (f:GetHeight() or 22) * 0.4)) end
	f:HookScript("OnSizeChanged", size)
	size()
	f._field = pieces
	return pieces
end
local function litField(f, on)
	if not f._field then return end
	local s = on and 1.25 or 1
	eachPiece(f._field, function(t) t:SetVertexColor(s, s, s) end)
end

-- W.DressSearch(editBox): the kit's search field on an EditBox that already
-- has its scripts -- the field edge, the glass on the left, a clear button on
-- the right while there is text. Call it after the box's own SetScripts.
function W.DressSearch(e)
	dressField(e)
	e:SetTextInsets(22, 22, 0, 0)
	local glass = e:CreateTexture(nil, "ARTWORK")
	glass:SetSize(12, 12); glass:SetPoint("LEFT", 6, 0)
	glass:SetTexture(UI .. "controls")
	glass:SetTexCoord(0.625, 0.8125, 0.203125, 0.296875)
	glass:SetVertexColor(0.6, 0.6, 0.6)
	local clr = CreateFrame("Button", nil, e)
	clr:SetSize(14, 14); clr:SetPoint("RIGHT", -5, 0)
	clr:SetNormalTexture(UI .. "controls")
	clr:GetNormalTexture():SetTexCoord(0.03125, 0.1875, 0.3515625, 0.4296875)
	clr:GetNormalTexture():SetVertexColor(0.7, 0.7, 0.7)
	clr:SetScript("OnEnter", function(s) s:GetNormalTexture():SetVertexColor(1, 1, 1) end)
	clr:SetScript("OnLeave", function(s) s:GetNormalTexture():SetVertexColor(0.7, 0.7, 0.7) end)
	clr:SetScript("OnClick", function() e:SetText(""); e:ClearFocus() end)
	clr:Hide()
	local function paint()
		if (e:GetText() or "") ~= "" then clr:Show() else clr:Hide() end
	end
	e:HookScript("OnTextChanged", paint)
	e:HookScript("OnEditFocusGained", function() litField(e, true); glass:SetVertexColor(1, 1, 1) end)
	e:HookScript("OnEditFocusLost", function() litField(e, false); glass:SetVertexColor(0.6, 0.6, 0.6) end)
	paint()
	return e
end

-- the dropdown's dark text holder, a nine-slice drawn at 0.8; also the edge of
-- a multi-line box
local DROP = UI .. "dropdown"
local HOLDER_U = { 0, 0.125, 0.296875, 0.421875 }
local HOLDER_V = { 0.625, 0.6796875, 0.71484375, 0.78515625 }
local EDGE_X = { { "LEFT", -6.4 }, { "LEFT", 6.4 }, { "RIGHT", -6.4 }, { "RIGHT", 6.4 } }
local EDGE_Y = { { "TOP", 5.6 }, { "TOP", -5.6 }, { "BOTTOM", 7.2 }, { "BOTTOM", -7.2 } }
local function dressHolder(b)
	for row = 1, 3 do
		for col = 1, 3 do
			local piece = b:CreateTexture(nil, "BACKGROUND")
			piece:SetTexture(DROP)
			piece:SetTexCoord(HOLDER_U[col], HOLDER_U[col + 1], HOLDER_V[row], HOLDER_V[row + 1])
			local x1, y1, x2, y2 = EDGE_X[col], EDGE_Y[row], EDGE_X[col + 1], EDGE_Y[row + 1]
			piece:SetPoint("TOPLEFT", b, y1[1] .. x1[1], x1[2], y1[2])
			piece:SetPoint("BOTTOMRIGHT", b, y2[1] .. x2[1], x2[2], y2[2])
		end
	end
end
W.DressHolder = dressHolder

-- ------------------------------------------------------------
-- Cut corners. No frame in Okanvil is a plain rectangle: the corners are cut
-- like the icon frames'. 3.3.5a cannot mask a frame, so Media\UI\chamfer (a
-- white cut-corner fill and a 1px cut-corner line, in a large and a small
-- size) is sliced nine ways behind the frame and tinted.
--
-- W.Chamfer(frame, big) takes over the frame's backdrop: SetBackdropColor /
-- SetBackdropBorderColor / GetBackdropColor tint the pieces instead, so every
-- caller written for a flat backdrop keeps working. The fill sits on the
-- BACKGROUND layer (below art on BORDER), the line on OVERLAY.
-- ------------------------------------------------------------
local CHAMF = UI .. "chamfer"
-- corner slices: the large set's are 24px on the sheet (cut 20), the small set's 16 (cut 12)
local CH_U_BIG = { 0, 24 / 128, 40 / 128, 64 / 128 }
local CH_U_SMALL = { 0, 16 / 128, 48 / 128, 64 / 128 }
local function ninePieces(f, layer, ox, oy, corner, CH_U)
	local pieces = {}
	local xs = { { "LEFT", 0 }, { "LEFT", corner }, { "RIGHT", -corner }, { "RIGHT", 0 } }
	local ys = { { "TOP", 0 }, { "TOP", -corner }, { "BOTTOM", corner }, { "BOTTOM", 0 } }
	for row = 1, 3 do
		for col = 1, 3 do
			local t = f:CreateTexture(nil, layer)
			t:SetTexture(CHAMF)
			t:SetTexCoord(ox + CH_U[col], ox + CH_U[col + 1], oy + CH_U[row], oy + CH_U[row + 1])
			local x1, y1, x2, y2 = xs[col], ys[row], xs[col + 1], ys[row + 1]
			t:SetPoint("TOPLEFT", f, y1[1] .. x1[1], x1[2], y1[2])
			t:SetPoint("BOTTOMRIGHT", f, y2[1] .. x2[1], x2[2], y2[2])
			pieces[#pieces + 1] = t
		end
	end
	return pieces
end

-- The size of one screen pixel in this frame's units, never under 1. In a
-- scaled-down window a 1-unit border is thinner than a pixel and, depending on
-- where it lands, the game rounds it away (the last of a row of buttons lost
-- its right edge).
local screenH
function W.Pixel(f)
	if not screenH then
		local res = GetCVar and GetCVar("gxResolution") or ""
		screenH = tonumber(res:match("%d+x(%d+)")) or 768
	end
	local e = (f and f:GetEffectiveScale()) or 1
	return math.max(1, 768 / (screenH * e))
end

function W.Chamfer(f, big)
	if f._okChamfer then return f._okChamfer end
	f:SetBackdrop(nil)
	-- windows: a 10px cut; boxes, fields and buttons: 6px
	local oy = big and 0 or 0.5
	local corner = big and 12 or 8
	local u = big and CH_U_BIG or CH_U_SMALL
	local ch = { fill = ninePieces(f, "BACKGROUND", 0, oy, corner, u),
		edge = ninePieces(f, "OVERLAY", 0.5, oy, corner, u), color = { 0, 0, 0, 0 } }
	local function tint(list, r, g, b, a)
		for _, t in ipairs(list) do t:SetVertexColor(r or 0, g or 0, b or 0, a or 1) end
	end
	-- The cut is the OUTSIDE of a window only: a frame placed straight on the
	-- screen (its parent is UIParent) and 30 tall or more. Everything inside a
	-- window -- boxes, lists, buttons, fields -- keeps a plain square box, drawn
	-- by the frame's own backdrop, so a square selection never sits in a cut box.
	-- _okKeepCut opts a frame in anyway (side tabs, the stepper's - / +, the
	-- Ranking art card).
	local mt = getmetatable(f).__index
	local rawSB, rawSBC, rawSBBC = mt.SetBackdrop, mt.SetBackdropColor, mt.SetBackdropBorderColor
	ch.border = { 0, 0, 0, 0 }
	ch.show = true
	local function paint()
		local c, e = ch.color, ch.border
		for _, cv in ipairs(ch.covers or {}) do cv:Tint(c[1], c[2], c[3], c[4]) end
		if ch.flat then
			rawSBC(f, c[1], c[2], c[3], c[4]); rawSBBC(f, e[1], e[2], e[3], e[4])
		else
			tint(ch.fill, c[1], c[2], c[3], c[4]); tint(ch.edge, e[1], e[2], e[3], e[4])
		end
	end
	local function mode()
		local h = f:GetHeight() or 0
		local outside = f:GetParent() == UIParent and h >= 30
		local flat = not (f._okKeepCut or outside)
		ch.flat = flat
		local cut = ch.show and not flat
		for _, t in ipairs(ch.fill) do if cut then t:Show() else t:Hide() end end
		for _, t in ipairs(ch.edge) do if cut then t:Show() else t:Hide() end end
		if flat and ch.show then
			local px = W.Pixel(f)
			rawSB(f, { bgFile = FLAT, edgeFile = FLAT, edgeSize = px,
				insets = { left = px, right = px, top = px, bottom = px } })
		else
			rawSB(f, nil)
		end
		paint()
	end
	function f:SetBackdropColor(r, g, b, a)
		ch.color = { r or 0, g or 0, b or 0, a or 1 }
		paint()
	end
	function f:SetBackdropBorderColor(r, g, b, a)
		ch.border = { r or 0, g or 0, b or 0, a or 1 }
		paint()
	end
	function f:GetBackdropColor() return unpack(ch.color) end
	-- a later SetBackdrop(nil) means "no box": hide everything; any other call
	-- keeps the frame's look
	function f:SetBackdrop(bd)
		ch.show = bd ~= nil
		mode()
	end
	f:HookScript("OnSizeChanged", mode)
	f._okChamfer = ch
	mode()
	return ch
end

-- Corner covers. Art is square and 3.3.5a cannot mask it, so inside a cut window
-- its corners would leave a wide gap at each cut while the sides keep a slim one.
-- A small triangle (Media\UI\cutcover) in the window's own background colour laid
-- over each corner of the art cuts it parallel to the window's edge.
--   W.CoverCorners(host, region, size, r, g, b, a[, corners])
local COVER = UI .. "cutcover"
local COVER_TC = { TOPLEFT = { 0, 1, 0, 1 }, TOPRIGHT = { 1, 0, 0, 1 },
	BOTTOMLEFT = { 0, 1, 1, 0 }, BOTTOMRIGHT = { 1, 0, 1, 0 } }
-- For art 6px inside a window's 10px cut. The art's own corner must sit INSIDE
-- the cut (6 + 6 > 10), or the cover would paint a black square corner outside
-- the window; the cover then cuts it parallel to the edge, the same 5px gap as
-- the sides. Size = 10 - 0.586 x the inset.
W.COVER = 6.5
function W.CoverCorners(host, region, size, r, g, b, a, corners)
	local list = {}
	for _, c in ipairs(corners or { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
		local t = host:CreateTexture(nil, "OVERLAY")
		t:SetTexture(COVER)
		t:SetTexCoord(unpack(COVER_TC[c]))
		t:SetSize(size, size)
		t:SetPoint(c, region, c, 0, 0)
		t:SetVertexColor(r, g, b, a or 1)
		list[#list + 1] = t
	end
	function list:SetAlpha(alpha) for _, t in ipairs(self) do t:SetAlpha(alpha) end end
	function list:SetShown(on) for _, t in ipairs(self) do if on then t:Show() else t:Hide() end end end
	function list:Tint(cr, cg, cb, ca) for _, t in ipairs(self) do t:SetVertexColor(cr, cg, cb, ca or 1) end end
	-- On a window with the cut-corner backdrop the covers wear ITS fill colour
	-- (a grey panel, the near-black main window...) and follow every change of it:
	-- a cover in any other colour shows as a dark corner inside the window.
	local ch = host._okChamfer
	if ch then
		ch.covers = ch.covers or {}
		ch.covers[#ch.covers + 1] = list
		local c = ch.color
		if c and (c[4] or 0) > 0 then list:Tint(c[1], c[2], c[3], c[4]) end
	end
	return list
end

-- a frame with no fill and no edge, but a backdrop all the same, so code that
-- recolours a box's edge (focus, a warning) still runs on it
local function clearBackdrop(f)
	W.Chamfer(f, false)
end

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
	if kind == "page" or kind == "well" or kind == "row" then
		frame:SetBackdrop(nil)
	else
		-- cut corners: large for windows and panels, small for boxes and fields
		W.Chamfer(frame, kind == "panel" or kind == "dark")
	end
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

-- Text that sits in a fixed-size box (a chip, a badge, a dropdown): it keeps
-- its size when Settings > Text size grows the page text, like button labels.
function W.FixedText(parent, text, size, role)
	local fs = W.Text(parent, text, size, role)
	fs._okFixed = true
	if fs._okSize then fs:SetFont(Okanvil:Font(), fs._okSize) end
	return fs
end

function W.Text(parent, text, size, role)
	local fs = Okanvil:NewText(parent, "OVERLAY")
	size = W.Size(size)
	if size then
		fs._okSize = size
		local f = Okanvil:Font()
		fs:SetFont(f, math.floor(size * Okanvil:TextScale() + 0.5))
	end
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
-- The kit's section: 11px uppercase gold, hairline to the column's end.
function W.Section(parent, text, x, y, reach)
	text = text or ""
	-- upper-case plain labels; one carrying a colour code is left as written
	if not text:find("|c", 1, true) then text = text:upper() end
	local t = W.FixedText(parent, text, 12)
	t:SetTextColor(unpack3(C.accentText))
	t:SetPoint("TOPLEFT", x, y)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetTexture("Interface\\Buttons\\WHITE8x8")
	rule:SetVertexColor(C.edge[1], C.edge[2], C.edge[3], 1)
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
-- Button: every one is the red plate, the X's family. kind:
--   "primary"          the main action (or a picked choice): full red, gold label
--   nil / "secondary"  the rest: the same plate a touch darker, cream label
--   "danger"           a light red label
--   "tab" / "tabOn"    a text tab; the picked one gold with a gold underline
--   "glyph"            a bare gold glyph (pager arrows), no plate
-- A button labelled "X" is the red close X.
-- ------------------------------------------------------------
-- Where a button sits decides how it is drawn. In chrome -- a page header, a
-- title bar, a floating window's own controls -- the main action is the red
-- plate. Inside content -- list rows, a page's body, a settings row -- every
-- button is the quiet box: red plates in the middle of a list read as clutter.
local function isChrome(parent)
	local depth, f = 0, parent
	while f and f ~= UIParent do
		if f._okChrome then return true end
		-- a popup's own list of toggles is content, however shallow it sits
		if f._okContent then return false end
		if f == Okanvil.win then return false end
		depth = depth + 1
		f = f:GetParent()
	end
	return depth <= 3
end
W.IsChrome = isChrome

function W.Button(parent, text, kind)
	if text == "X" or text == "x" then return Mod(W.CloseButton(parent)) end
	local chrome = isChrome(parent)
	local onBar = parent and parent._okTitleBar
	local b = CreateFrame("Button", nil, parent)
	clearBackdrop(b)
	-- Button labels get a FIXED size so Settings > Text size can't grow them past
	-- the box. The slider is for body text, not chrome.
	local t = W.Text(b, text, "body")
	t._okFixed = true
	-- Tabs read one size up: they name the page you are on, not an action.
	t._okSize = (kind == "tab" or kind == "tabOn") and 14 or 13
	t:SetFont(Okanvil:Font(), t._okSize)
	t:SetPoint("CENTER")
	b.text = t
	b._kind = kind

	local plate, glow, under, uline, bronze
	local function ensurePlate()
		if plate then return end
		local v = { 0, 1 }
		plate = threeSlice(b, "BACKGROUND", UI .. "redplate", PLATE_U, v)
		glow = threeSlice(b, "HIGHLIGHT", UI .. "redplate", PLATE_U, v)
		eachPiece(glow, function(g) g:SetBlendMode("ADD"); g:SetAlpha(0.25) end)
		local function size()
			local cap = CAP_W * (b:GetHeight() or PLATE_H) / PLATE_H
			capWidth(plate, cap); capWidth(glow, cap)
		end
		b:HookScript("OnSizeChanged", size)
		size()
	end

	local function paint(hover)
		local off = isDisabled(b)
		local isTab = (kind == "tab" or kind == "tabOn")
		-- content: the quiet box, never the red plate (plates in a list read as clutter)
		local link = false
		local plated = not isTab and kind ~= "glyph"
		-- red is for a window's one main action; everything else, and a row of
		-- choices (buttons switched with SetKind), is on the bronze plate: the
		-- picked choice lit, the others dark
		local picked = b._toggle and ((kind == "primary") or b._active)
		local unpicked = plated and b._toggle and not picked
		local red = plated and (b._main or (kind == "primary" and not b._toggle))
		-- a main action switched off by its owner (nothing to give yet): the grey plate
		local idle = red and b._main ~= "always" and b._toggle and kind ~= "primary"
		local metal = plated and not red
		if red then ensurePlate() end
		if metal and not bronze then bronze = bronzePlate(b) end
		if plate then
			local shade = off and 0.6 or (b._down and 0.75 or (idle and 0.85 or 1))
			eachPiece(plate, function(p)
				if red then p:Show() else p:Hide() end
				p:SetDesaturated(off or idle)
				p:SetVertexColor(shade, shade, shade)
			end)
			eachPiece(glow, function(g) if red then g:Show() else g:Hide() end end)
		end
		if bronze then
			bronze:SetShown(metal)
			if metal then
				bronze:State((off or unpicked) and "disabled"
					or ((picked or b._down) and "open")
					or (hover and "hover") or "normal")
			end
		end
		if under then if kind == "tabOn" then under:Show() else under:Hide() end end
		if link then
			-- gold text, no box; the main action / the picked one is underlined
			if not uline then
				uline = b:CreateTexture(nil, "ARTWORK")
				uline:SetTexture(FLAT); uline:SetHeight(1)
				uline:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
				uline:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, -2)
			end
			b:SetBackdropColor(0, 0, 0, 0)
			b:SetBackdropBorderColor(0, 0, 0, 0)
			local picked = (kind == "primary") or b._active
			if picked or hover then uline:Show() else uline:Hide() end
			uline:SetVertexColor(1, 0.82, 0, picked and 0.9 or 0.45)
			if off then t:SetTextColor(0.5, 0.5, 0.5)
			elseif kind == "danger" then t:SetTextColor(unpack3(C.danger))
			elseif hover then t:SetTextColor(1, 1, 1)
			else t:SetTextColor(unpack3(C.accentText)) end
			return
		end
		if uline then uline:Hide() end
		if kind == "glyph" then
			b:SetBackdropColor(0, 0, 0, 0)
			b:SetBackdropBorderColor(0, 0, 0, 0)
			if off then t:SetTextColor(0.4, 0.4, 0.4)
			elseif hover then t:SetTextColor(1, 1, 1)
			else t:SetTextColor(unpack3(C.accentText)) end
			return
		end
		if isTab then
			if not under then
				under = b:CreateTexture(nil, "ARTWORK")
				under:SetTexture(FLAT); under:SetVertexColor(unpack3(C.accentText))
				under:SetHeight(2); under:SetPoint("BOTTOMLEFT", 2, 0); under:SetPoint("BOTTOMRIGHT", -2, 0)
				if kind == "tabOn" then under:Show() else under:Hide() end
			end
			b:SetBackdropColor(0, 0, 0, 0)
			b:SetBackdropBorderColor(0, 0, 0, 0)
			if kind == "tabOn" then t:SetTextColor(unpack3(C.accentText))
			elseif hover then t:SetTextColor(unpack3(C.accentHi))
			else t:SetTextColor(0.74, 0.75, 0.77) end
		elseif red then
			b:SetBackdropColor(0, 0, 0, 0)
			b:SetBackdropBorderColor(0, 0, 0, 0)
			-- white on the red plate, gold under the cursor; grey on the grey plate
			if off then t:SetTextColor(0.5, 0.5, 0.5)
			elseif hover then t:SetTextColor(unpack3(C.accentText))
			elseif idle then t:SetTextColor(0.75, 0.75, 0.75)
			else t:SetTextColor(1, 1, 1) end
		elseif metal then
			b:SetBackdropColor(0, 0, 0, 0)
			b:SetBackdropBorderColor(0, 0, 0, 0)
			-- gold on the bronze plate, white under the cursor or when picked;
			-- an unpicked choice grey
			if off then t:SetTextColor(0.5, 0.5, 0.5)
			elseif unpicked and not hover then t:SetTextColor(0.6, 0.6, 0.6)
			elseif kind == "danger" then t:SetTextColor(1, 0.55, 0.5)
			elseif hover or picked then t:SetTextColor(1, 1, 1)
			else t:SetTextColor(unpack3(C.accentText)) end
		else
			-- the quiet button: solid dark fill, light bronze edge, cream label;
			-- gold edge while hovered or picked (a segment that is on, the main action)
			local lit = (hover or b._active or (kind == "primary")) and not off
			b:SetBackdropColor(0.094, 0.086, 0.075, 1)
			if lit then b:SetBackdropBorderColor(1, 0.82, 0, 0.6)
			else b:SetBackdropBorderColor(0.463, 0.384, 0.267, 1) end
			if off then t:SetTextColor(0.5, 0.5, 0.5)
			elseif kind == "danger" then t:SetTextColor(unpack3(C.danger))
			elseif hover then t:SetTextColor(1, 1, 1)
			else t:SetTextColor(unpack3(C.cream)) end
		end
	end
	b._paint = paint
	paint(false)
	b:SetScript("OnEnter", function(s) paint(true); tipEnter(s) end)
	b:SetScript("OnLeave", function(s) s._down = nil; paint(false); tipLeave() end)
	b:HookScript("OnMouseDown", function(s) s._down = true; paint(s._hover) end)
	b:HookScript("OnMouseUp", function(s) s._down = nil; paint(s._hover) end)
	b:HookScript("OnEnable", function(s) paint(s._hover) end)
	b:HookScript("OnDisable", function(s) paint(false) end)

	-- Re-style in place: a toggle shows its state by switching kind.
	function b:SetKind(k)
		self._kind = k
		kind = k
		-- switched by its owner: one of a row of choices (see `unpicked` above)
		if k ~= "tab" and k ~= "tabOn" then self._toggle = true end
		paint(self._hover)
	end
	-- A window's main action: the red plate whatever its kind. "always" keeps it
	-- red when its owner switches it to secondary (an ON/OFF call to action);
	-- otherwise secondary shows the grey plate.
	function b:SetMain(on)
		self._main = on
		paint(self._hover)
		return self
	end
	b:HookScript("OnEnter", function(s) s._hover = true end)
	b:HookScript("OnLeave", function(s) s._hover = false end)
	return Mod(b)
end

-- the sign buttons of a stepper: gold bars drawn centred (the font's "-" sits low)
function W.SignButton(parent, plus)
	local b = W.Button(parent, "")
	b._okKeepCut = true
	b:SetSize(24, 22)
	local bars = { { 8, 2 } }
	if plus then bars[2] = { 2, 8 } end
	for _, sz in ipairs(bars) do
		local bar = b:CreateTexture(nil, "OVERLAY")
		bar:SetTexture(FLAT)
		bar:SetVertexColor(unpack3(C.accentText))
		bar:SetSize(sz[1], sz[2])
		bar:SetPoint("CENTER", 0, 0)
	end
	return b
end

-- ------------------------------------------------------------
-- Check -- the kit's checkbox (20x20), label to its right
-- ------------------------------------------------------------
function W.Check(parent, label, getFn, setFn)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(20, 20)
	local box, tick = W.CheckTextures(b, 20)
	box:SetPoint("CENTER")
	local t = W.Text(b, label)
	t:SetPoint("LEFT", b, "RIGHT", 6, 0)
	b.text = t
	local function refresh()
		if getFn and getFn() then tick:Show() else tick:Hide() end
	end
	refresh()
	b:SetScript("OnClick", function()
		if setFn then setFn(not (getFn and getFn())) end
		refresh()
	end)
	b:SetScript("OnEnter", function(s) box:SetVertexColor(1.25, 1.25, 1.25); tipEnter(s) end)
	b:SetScript("OnLeave", function() box:SetVertexColor(1, 1, 1); tipLeave() end)
	b.refresh = refresh
	return Mod(b)
end

-- ------------------------------------------------------------
-- Settings rows (the kit): 30 tall, the name on the left, the control on the
-- right edge, every other row a faint band, hover lightens. No hint line, no
-- tooltip. Rows count their own stripes per parent; W.ResetStripes(parent)
-- starts a new section.
-- ------------------------------------------------------------
W.ROW_H = 34
function W.ResetStripes(parent) parent._okStripe = false end

function W.SettingsRow(parent, label)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(W.ROW_H)
	W.ROW_FONT = W.ROW_FONT or 16
	if parent._okStripe then
		local band = row:CreateTexture(nil, "BACKGROUND")
		band:SetTexture(FLAT); band:SetVertexColor(1, 1, 1, 0.03); band:SetAllPoints(row)
	end
	parent._okStripe = not parent._okStripe
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetTexture(FLAT); hover:SetVertexColor(1, 1, 1, 0.05); hover:SetAllPoints(row)
	local fs = W.FixedText(row, label, W.ROW_FONT)
	fs:SetPoint("LEFT", 6, 0)
	-- a hard shadow keeps the label readable over bright art, with no box behind it
	fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1.5, -1.5)
	fs:SetJustifyH("LEFT")
	row.text = fs
	return Mod(row)
end

-- ------------------------------------------------------------
-- ToggleRow -- a settings row with a checkbox on its right; the whole row
-- toggles it. `desc` is accepted and ignored (the kit has no hint lines).
--   local r = W.ToggleRow(parent, "Title", nil, getFn, setFn)
--   r:SetPoint("TOPLEFT", x, y); r:SetPoint("RIGHT", parent, "RIGHT", -x, 0)
--   y = y - r:GetHeight()
-- r.refresh() repaints from getFn.
-- ------------------------------------------------------------
function W.ToggleRow(parent, title, desc, getFn, setFn)
	local r = W.SettingsRow(parent, title)
	local box = CreateFrame("Frame", nil, r)
	box:SetSize(20, 20); box:SetPoint("RIGHT", -4, 0)
	local tex, tick = W.CheckTextures(box, 20)
	tex:SetPoint("CENTER")
	r.btn = box
	r.text:SetPoint("RIGHT", box, "LEFT", -8, 0)
	local function refresh()
		if getFn and getFn() then tick:Show() else tick:Hide() end
	end
	r:SetScript("OnClick", function()
		if setFn then setFn(not (getFn and getFn())) end
		refresh()
	end)
	r.refresh = refresh
	refresh()
	return r
end

-- ------------------------------------------------------------
-- Slider -- drawn as the kit's stepper: the label on the left, then
-- [-] value [+] at the right end. Same arguments as the old slider.
--   r:SetValue(v) repaints, r:GetValue() reads.
-- ------------------------------------------------------------
local function stepFormat(step)
	if step >= 1 then return "%d" end
	if step >= 0.1 then return "%.1f" end
	return "%.2f"
end

function W.Slider(parent, label, lo, hi, step, getFn, setFn, onRelease)
	local r = CreateFrame("Frame", nil, parent)
	r:SetSize(300, 24)
	local plus = W.SignButton(r, true)
	plus:SetPoint("RIGHT", 0, 0)
	local value = W.FixedText(r, "", 15)
	value:SetTextColor(unpack3(C.accentText))
	value:SetShadowColor(0, 0, 0, 1); value:SetShadowOffset(1.5, -1.5)
	value:SetWidth(48); value:SetJustifyH("CENTER")
	value:SetPoint("RIGHT", plus, "LEFT", -2, 0)
	local minus = W.SignButton(r, false)
	minus:SetPoint("RIGHT", value, "LEFT", -2, 0)
	local title = W.FixedText(r, label, 13)
	title:SetPoint("LEFT", 0, 0)
	title:SetPoint("RIGHT", minus, "LEFT", -8, 0)
	title:SetJustifyH("LEFT")
	r.text = title
	local fmt = stepFormat(step)
	local cur
	local function paint(v)
		if v == 0 then v = 0 end   -- -0 prints as "-0"
		cur = v
		value:SetText(fmt:format(v))
	end
	local function bump(d)
		local v = math.floor(((cur or getFn() or lo) + d) / step + 0.5) * step
		if v < lo - step / 2 or v > hi + step / 2 then return end
		v = math.max(lo, math.min(hi, v))
		paint(v)
		setFn(v)
	end
	minus:SetScript("OnClick", function() bump(-step) end)
	plus:SetScript("OnClick", function() bump(step) end)
	paint(getFn() or lo)
	function r:SetValue(v) paint(v) end
	function r:GetValue() return cur end
	function r:SetMinMaxValues(a, b) lo, hi = a, b end
	r.minus, r.plus = minus, plus
	return Mod(r)
end

-- ------------------------------------------------------------
-- EditBox (single line, focus-highlighted)
-- ------------------------------------------------------------
function W.EditBox(parent, onEnter)
	-- the kit's field edge; the backdrop stays (clear) so callers can still tint it
	local box = W.Frame(parent, "bare")
	clearBackdrop(box)
	dressField(box)
	local e = CreateFrame("EditBox", nil, box)
	e:SetPoint("TOPLEFT", 8, -1)
	e:SetPoint("BOTTOMRIGHT", -8, 1)
	e:SetAutoFocus(false)
	e:SetFontObject(GameFontHighlightSmall)
	-- A caller that needs bigger text sets box:SetTextSize(n) after building --
	-- the note editor is read as much as it is typed in.
	local fp = Okanvil:Font()
	e:SetFont(fp, 12)                 -- fixed size: the box height is fixed, so the
	e:SetTextColor(unpack3(C.text))   -- global font slider must not overflow it
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEditFocusGained", function() litField(box, true) end)
	-- COMMIT ON FOCUS LOSS as well as on Enter. Only firing on Enter meant typing
	-- a value and then clicking away silently threw it out -- the field still
	-- showed the text, so it looked saved, and the setting only "worked" after a
	-- /reload repainted the box from the unchanged db.
	e:SetScript("OnEditFocusLost", function(s)
		litField(box, false)
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
	-- 3.3.5a EditBoxes have no GetStringWidth, so the text is measured on a
	-- hidden FontString set to the same font.
	local measure = box:CreateFontString(nil, "OVERLAY")
	measure:Hide()
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		e:SetFocus()
		-- Clicking past the end of the text puts the cursor at the end, which is
		-- what the empty space to the right of a value means.
		local font, size, flags = e:GetFont()
		if font then measure:SetFont(font, size, flags) end
		measure:SetText(e:GetText() or "")
		local x = GetCursorPosition() / (e:GetEffectiveScale() or 1)
		if x > (e:GetLeft() or 0) + (measure:GetStringWidth() or 0) then
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
	-- the dropdown's dark holder as the edge of a multi-line box
	local box = W.Frame(parent, "bare")
	clearBackdrop(box)
	dressHolder(box)
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
	e:SetScript("OnEditFocusGained", function() box:SetBackdropBorderColor(1, 0.82, 0, 0.35) end)
	e:SetScript("OnEditFocusLost", function()
		box:SetBackdropBorderColor(0, 0, 0, 0)
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
local MENU_MAX_H = 280
local MENU_INSET_X, MENU_INSET_Y, MENU_ROW_H, MENU_CHECK_W = 12, 10, 21, 16

local function ensureMenu()
	if MENU then return MENU end
	local m = CreateFrame("Frame", "Okanvil_DropdownMenu", UIParent)
	m:SetFrameStrata("TOOLTIP")
	m:SetClampedToScreen(true)
	m:SetToplevel(true)
	-- the kit's list: the tooltip box, plus a solid fill (the tooltip background
	-- alone is see-through)
	m:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 },
	})
	m:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
	m:SetBackdropBorderColor(0.5, 0.5, 0.5)
	local fill = m:CreateTexture(nil, "BACKGROUND")
	fill:SetTexture(FLAT)
	fill:SetVertexColor(0.04, 0.04, 0.045, 1)
	fill:SetPoint("TOPLEFT", 4, -4)
	fill:SetPoint("BOTTOMRIGHT", -4, 4)
	m:Hide()

	local sf = CreateFrame("ScrollFrame", nil, m)
	sf:SetPoint("TOPLEFT", MENU_INSET_X, -MENU_INSET_Y)
	sf:SetPoint("BOTTOMRIGHT", -MENU_INSET_X, MENU_INSET_Y)
	Clip(sf)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(10, 1)
	sf:SetScrollChild(child)
	m.sf, m.child = sf, child

	local sb = CreateFrame("Slider", nil, m)
	sb:SetPoint("TOPRIGHT", -6, -MENU_INSET_Y)
	sb:SetPoint("BOTTOMRIGHT", -6, MENU_INSET_Y)
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
	m:SetScript("OnHide", function()
		local o = m.owner
		m.owner = nil
		if o and o.syncArrow then o.syncArrow() end
	end)
	-- The menu lives on UIParent, so nothing hides it with its button: close it
	-- when the button goes away (window closed, page rebuilt) or on a click
	-- anywhere outside the menu and its button.
	m:SetScript("OnUpdate", function(s)
		local o = s.owner
		if not (o and o:IsVisible()) then s:Hide(); return end
		if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
			and not MouseIsOver(s) and not MouseIsOver(o) then
			s:Hide()
		end
	end)
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
	local rowH = MENU_ROW_H
	local inner = m:GetWidth() - MENU_INSET_X * 2
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
			r.t:SetPoint("LEFT", MENU_CHECK_W + 2, 0); r.t:SetJustifyH("LEFT")
			r.t:SetShadowColor(0, 0, 0, 1); r.t:SetShadowOffset(1, -1)
			-- the current choice carries Blizzard's tick on its left
			r.check = r:CreateTexture(nil, "ARTWORK")
			r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			r.check:SetSize(MENU_CHECK_W, MENU_CHECK_W); r.check:SetPoint("LEFT", 0, 0)
			local hl = r:CreateTexture(nil, "HIGHLIGHT")
			hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
			hl:SetBlendMode("ADD"); hl:SetAllPoints()
			m.rows[i] = r
		end
		r:SetHeight(rowH); r:SetWidth(inner)
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
		if isCur then r.check:Show() else r.check:Hide() end
		if val == false then r.t:SetTextColor(unpack3(C.textDim))   -- a label, not a choice
		else r.t:SetTextColor(1, 1, 1) end
		r:SetScript("OnClick", function()
			if val == false then return end     -- label rows do nothing when clicked
			owner.setFn(val)
			if owner.refreshText then owner:refreshText() end
			m:Hide()
		end)
		r:Show()
		y = y + rowH
	end
	-- At least as wide as the button, and wider when a label needs it: a menu
	-- opened from a small button cut its own text off at the button's width.
	local widest = 0
	for i = 1, #items do
		local w = m.rows[i].t:GetStringWidth() or 0
		if w > widest then widest = w end
	end
	local mw = math.max(owner:GetWidth() + 4, widest + MENU_CHECK_W + 2 + MENU_INSET_X * 2 + 12)
	if mw ~= m:GetWidth() then
		m:SetWidth(mw)
		for i = 1, #items do m.rows[i]:SetWidth(mw - MENU_INSET_X * 2) end
	end
	m.child:SetWidth(mw - MENU_INSET_X * 2)
	m.child:SetHeight(math.max(1, y))
	local h = math.min(y + MENU_INSET_Y * 2, MENU_MAX_H)
	m:SetHeight(h)
	local maxScroll = math.max(0, y - (h - MENU_INSET_Y * 2))
	m.sb:SetMinMaxValues(0, maxScroll); m.sb:SetValue(0)
	m.sb:SetShown(maxScroll > 0)
	placeMenu(m, owner, h)
	m:Show()
end

-- ------------------------------------------------------------
-- DropDown button (borrows the global menu)
-- ------------------------------------------------------------
-- the bronze plate's arrow button (Media/UI/plate), at rest and lit
local ARROW = {
	normal = { 70 / 128, 124 / 128, 0, 54 / 512 },
	hover = { 70 / 128, 124 / 128, 60 / 512, 114 / 512 },
}

function W.DropDown(parent, listFn, getFn, setFn, preview)
	local dd = CreateFrame("Button", nil, parent)
	dd:SetSize(160, 26)
	clearBackdrop(dd)
	-- the bronze plate: lit under the cursor and while its list is open
	local plate = bronzePlate(dd)
	local txt
	local function edge(lit)
		local open = MENU and MENU:IsShown() and MENU.owner == dd
		plate:State((open and "open") or (lit and "hover") or "normal")
		if txt then
			if lit or open then txt:SetTextColor(1, 1, 1)
			else txt:SetTextColor(unpack3(C.accentText)) end
		end
	end
	dd._edge = edge
	edge(false)
	-- fixed size (12): the dropdown box is a fixed height, so its text must not
	-- scale with the global body-font slider (it would clip / overflow).
	txt = W.FixedText(dd, nil, 15)
	txt:SetTextColor(unpack3(C.accentText))
	txt:SetPoint("LEFT", 8, 0); txt:SetPoint("RIGHT", -26, 0); txt:SetJustifyH("LEFT")
	dd.textFS = txt
	local arrow = dd:CreateTexture(nil, "ARTWORK")
	arrow:SetTexture(BRONZE)
	-- the plate's face sits lower in its art than its shadow, so the arrow
	-- button drops to the face's centre
	arrow:SetSize(22, 22); arrow:SetPoint("RIGHT", -2, -2)
	local function syncArrow()
		local open = MENU and MENU:IsShown() and MENU.owner == dd
		arrow:SetTexCoord(unpack(ARROW[(open or dd._hover) and "hover" or "normal"]))
		if dd._edge then dd._edge(dd._hover) end
	end
	dd.syncArrow = syncArrow
	syncArrow()
	-- one height everywhere: the holder art is drawn for 24 (callers asked 22-26)
	local setSize, setHeight = dd.SetSize, dd.SetHeight
	function dd:SetSize(w, h) setSize(self, w, 26) end
	function dd:SetHeight() setHeight(self, 26) end
	local function tint() syncArrow() end
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
	dd:SetScript("OnEnter", function(s) s._hover = true; tint(); edge(true); tipEnter(s) end)
	dd:SetScript("OnLeave", function(s) s._hover = false; s._down = nil; tint(); edge(false); tipLeave() end)
	dd:SetScript("OnMouseDown", function(s) s._down = true; tint() end)
	dd:SetScript("OnMouseUp", function(s) s._down = nil; tint() end)
	dd:SetScript("OnClick", function(s) openMenu(s); tint() end)
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
--     landingLabel = "Listings",                   -- the main view's own tab (non-pill pages)
--     drawerWidth = 168, footerHeight = 26,
--   })
--   dash.main            -- fill Frame for the live content
--   dash.drawer          -- fill Frame for the stat column (right)
--   dash.footer          -- fill Frame for the bottom strip
--   dash:Refresh()       -- repaint header label/status
--   dash:ToggleDrawer()  -- show/hide the stat column
-- ============================================================
-- every page's header buttons are one size, so pages match side by side
local BTN_W, BTN_H, BTN_FONT = 130, 24, 13
W.HEADER_BTN_W, W.HEADER_BTN_H, W.HEADER_BTN_FONT = BTN_W, BTN_H, BTN_FONT
-- the label one size up, to match the taller button; fixed like every button
-- label, so Settings > Text size does not grow it past the box
local function headerFont(b)
	local t = b and b.text
	if not t then return b end
	t._okSize, t._okFixed = BTN_FONT, true
	t:SetFont(Okanvil:Font(), BTN_FONT)
	return b
end
W.HeaderFont = headerFont
-- ------------------------------------------------------------
-- Side tab: a page's tab on the main window's right edge -- the tab's icon in
-- the kit frame, the open one wider and gold, its name on hover.
--   local t = W.SideTab(page, "History", icon, onClick)
--   t:Place(i)             -- i-th tab from the top, 0-based
--   t:SetKind("tabOn")     -- open; "tab" = closed
-- Parented to the page so it shows and hides with it; never inside a scroll
-- frame (it would be clipped).
-- ------------------------------------------------------------
local SIDE_W, SIDE_ON_W, SIDE_H, SIDE_GAP, SIDE_TOP = 54, 60, 46, 6, -70
function W.SideTab(parent, label, icon, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(SIDE_W, SIDE_H)
	-- below the window: its left 8px (with the left cut corners) tuck under the
	-- window's edge, so only the right side shows, joined to the window
	b:SetFrameLevel(math.max(0, (Okanvil.win:GetFrameLevel() or 1) - 1))
	b._okKeepCut = true
	W.Chamfer(b, false)
	local slot = W.FramedIcon(b, icon, 34, false)
	slot:SetPoint("CENTER", 4, 0)
	b.slot = slot
	-- one pixel over the window's edge, so the tab and the window read as one
	-- `extra` pushes it further down (the Settings shortcut sits apart from the page's tabs)
	function b:Place(i, extra)
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", Okanvil.win, "TOPRIGHT", -8, SIDE_TOP - i * (SIDE_H + SIDE_GAP) - (extra or 0))
	end
	function b:SetKind(k)
		local on = (k == "tabOn")
		self:SetWidth(on and SIDE_ON_W or SIDE_W)
		W.SetFramedIconGold(self.slot, on)
		if on then self:SetBackdropColor(0.102, 0.090, 0.075, 1)
		else self:SetBackdropColor(C.body[1], C.body[2], C.body[3], 1) end
		self:SetBackdropBorderColor(unpack3(C.edge))
	end
	b:SetKind("tab")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(s)
		GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
		GameTooltip:AddLine(label, 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

-- The gear at the bottom of a page's side tabs: opens Settings on the tab that
-- holds this page's options. `after` = how many side tabs sit above it.
function W.SettingsSideTab(parent, settingsKey, after)
	local b = W.SideTab(parent, "Settings", Okanvil.ICONS and Okanvil.ICONS.settings,
		function() Okanvil:OpenSettingsTab(settingsKey) end)
	b:Place(after or 0, (after or 0) > 0 and 12 or 0)
	-- a panel docked to the window's right (Whispers) moves out past it
	parent._okSideTabs = true
	return b
end

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
	-- Two or more pills go onto the main window's right edge as side tabs (an
	-- icon in the kit frame, the open one wider and gold); the tab row in the
	-- page goes away. A lone pill keeps the old row, since a page may put its
	-- own controls there (Notes does).
	local sideMode = pillMode and cfg.tabs and #cfg.tabs >= 2 and Okanvil.win and true or false
	-- An overlay page gets its landing view as the FIRST tab (cfg.landingLabel).
	-- A lone "Settings" tab reads as a selected item, not as a tab: with the
	-- landing beside it there are always two, and the lit one is where you are.
	-- The tabs then stay on screen like pills, so there is no "< Back" either.
	local LANDING = "__landing"
	local landing = (not pillMode) and cfg.tabs and #cfg.tabs > 0 and (cfg.landingLabel or "Overview")
	local switchMode = pillMode or (landing and true or false)

	-- The setup's header: icon, gold title, a hairline under it. No filled strip:
	-- the page sits on the window's art like every other part of the shell.
	local header = W.Frame(parent, "bare")
	header:SetPoint("TOPLEFT", 0, 0); header:SetPoint("TOPRIGHT", 0, 0)
	header._okChrome = true
	header:SetHeight(cfg.subtitle and 48 or 40)
	D.header = header
	local hrule = header:CreateTexture(nil, "ARTWORK")
	hrule:SetTexture(FLAT); hrule:SetVertexColor(unpack3(C.border))
	hrule:SetHeight(1)
	hrule:SetPoint("BOTTOMLEFT", 10, 0); hrule:SetPoint("BOTTOMRIGHT", -10, 0)

	local ix = 10
	if cfg.icon then
		-- the page's icon in the gold frame, like its row in the nav
		local ic = W.FramedIcon(header, cfg.icon, 30, true)
		ic:SetPoint("LEFT", 8, 0)
		D.hicon = ic
		ix = 48
	end
	-- the page's name in the talent screen's face (Morpheus, outlined, cream)
	local htitle = W.TitleText(header, cfg.title, 20)
	function htitle:Point(...) self:SetPoint(...); return self end
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
		cta:SetMain("always")
		headerFont(cta):SetSize(BTN_W, BTN_H); cta:SetPoint("RIGHT", -10, 0)
		cta:SetScript("OnClick", function() cfg.onPrimary() end)
		D.cta = cta
	end
	-- optional secondary header button (left of the primary CTA). Its label may be
	-- dynamic (secondaryText fn) and Refresh() can hide it (secondaryShown fn).
	local cta2
	if cfg.onSecondary then
		cta2 = W.Button(header, cfg.secondaryText and cfg.secondaryText() or "", "secondary")
		headerFont(cta2):SetSize(BTN_W, BTN_H)
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
		headerFont(cta3):SetSize(BTN_W, BTN_H)
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
	toolbar:SetHeight(28)
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
	if sideMode then
		overlay:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
		overlay:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
	elseif switchMode then
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

	local function paintTabs(key)
		for _, b in pairs(D.tabBtns) do
			b._active = (b._key == key)
			-- Pills read as a segmented switch, so the picked one takes the solid
			-- gold fill the Home page uses for Online/Snapshots. Gold TEXT alone was
			-- too quiet to say "you are here" when the pills never go away.
			if b.SetKind then b:SetKind(b._active and "tabOn" or "tab") end
			if b._paint then b._paint(false) end
		end
	end

	local function closeOverlay()
		-- In pill mode there is nothing to close BACK to -- a pill is always the
		-- current page -- so this is a no-op rather than a way to end up staring at
		-- an empty body with every pill unlit.
		if pillMode then return end
		overlay:Hide(); toolbar:Show(); body:Show(); if footer then footer:Show() end
		paintTabs(LANDING)
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
		-- the header names the open side tab, in gold beside the page's name
		if sideMode then htitle:SetText((cfg.title or "") .. "  |cffffd100" .. (tab.label or "") .. "|r") end
		if not D.pages[key] then
			-- in pill mode there is no "< Back" row to clear, so the page starts at
			-- the top of the overlay instead of 34px down
			local topPad = switchMode and 6 or 34
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
		if switchMode then
			-- the pills stay on screen and stay clickable: this is a switch, not a
			-- drill-down, so the toolbar is part of the page rather than something
			-- the page covers up
			body:Hide(); overlay:Show()
			back:Hide(); otitle:Hide()
			if footer then footer:Show() end
		else
			toolbar:Hide(); body:Hide(); if footer then footer:Hide() end; overlay:Show()
		end
		paintTabs(key)
	end
	D.OpenPage = openPage

	-- lay the tab buttons + drawer toggle onto the toolbar. Width auto-fits the
	-- label (min 60) so longer labels like "Appearance"/"Collectors" never clip.
	local prev
	local function addSideTab(key, label, icon, onClick)
		local n = 0
		for _ in pairs(D.tabBtns) do n = n + 1 end
		local b = W.SideTab(parent, label, icon or cfg.icon, onClick)
		b:Place(n)
		b._key = key
		D.tabBtns[key] = b
	end
	local function addTabBtn(key, label, onClick, icon)
		if sideMode then return addSideTab(key, label, icon, onClick) end
		local b = W.Button(toolbar, label, "tab")
		local tw = (b.text and b.text:GetStringWidth() or 60) + 22
		b:SetSize(math.max(64, tw), 26); b._key = key
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 10, 0)
		else b:SetPoint("LEFT", 0, 0) end
		b:SetScript("OnClick", onClick)
		D.tabBtns[key] = b
		prev = b
	end
	if landing then addTabBtn(LANDING, landing, closeOverlay) end
	for _, t in ipairs(cfg.tabs or {}) do
		addTabBtn(t.key, t.label, function() openPage(t.key) end, t.icon)
	end
	if sideMode and not hasDrawer then toolbar:Hide() end
	-- cfg.settingsTab = a Settings tab key: a gear under the side tabs opens it
	if cfg.settingsTab and Okanvil.win then
		D.settingsTab = W.SettingsSideTab(parent, cfg.settingsTab, sideMode and #cfg.tabs or 0)
	end
	-- a panel docked to the window's right (Whispers) moves out past the tabs
	if sideMode then parent._okSideTabs = true end
	if landing then paintTabs(LANDING) end
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
		-- Close up behind hidden buttons: each button and the status text sit left
		-- of the nearest button still SHOWN. Anchored to a hidden one, they kept its
		-- empty slot, and the status text floated in the middle of the header.
		local left = cta
		if cta2 and cta2:IsShown() then
			cta2:ClearAllPoints()
			if left then cta2:SetPoint("RIGHT", left, "LEFT", -6, 0) else cta2:SetPoint("RIGHT", -10, 0) end
			left = cta2
		end
		if cta3 and cta3:IsShown() then
			cta3:ClearAllPoints()
			if left then cta3:SetPoint("RIGHT", left, "LEFT", -6, 0) else cta3:SetPoint("RIGHT", -10, 0) end
			left = cta3
		end
		status:ClearAllPoints()
		if left then status:SetPoint("RIGHT", left, "LEFT", -10, 0) else status:SetPoint("RIGHT", -8, 0) end
		status:SetPoint("LEFT", htitle, "RIGHT", 10, -tdy)
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
-- Okanvil.ForgeArtStyle, when set, swaps the picture for another one:
--   { tex = path, aspect = width / height of the picture as painted,
--     washL = fade on the left, washR = fade on the right }
-- The art is then drawn at full strength under that wash, and cropped to the
-- window's shape from the picture's real aspect. The lite build sets it.
function W.ForgeArt(f, alpha)
	local st = Okanvil.ForgeArtStyle
	-- BACKGROUND for the art, BORDER for the fade: separate layers, so the fade
	-- is always on top (one layer = undefined order). The backdrop sits below both.
	-- 6px inside the edge (the same gap all round); covers cut its corners like the window's
	local art = f:CreateTexture(nil, "BORDER")
	art:SetPoint("TOPLEFT", 6, -6); art:SetPoint("BOTTOMRIGHT", -6, 6)
	art:SetTexture(st and st.tex or FORGE_ART)
	local fade = f:CreateTexture(nil, "ARTWORK")
	fade:SetPoint("TOPLEFT", 6, -6); fade:SetPoint("BOTTOMRIGHT", -6, 6)
	local covers = W.CoverCorners(f, art, W.COVER, C.body[1], C.body[2], C.body[3], 0.97)
	fade:SetTexture(FLAT)
	local d = C.panelD
	fade:SetGradientAlpha("HORIZONTAL", d[1], d[2], d[3], st and st.washL or 0.92,
		d[1], d[2], d[3], st and st.washR or 0.40)
	local function crop()
		local w, h = f:GetWidth() or 0, f:GetHeight() or 0
		if w <= 0 or h <= 0 then return end
		if st then
			-- narrower than the picture: keep its right edge; wider: its middle band
			local A, want = st.aspect or 1, w / h
			if want < A then
				art:SetTexCoord(1 - want / A, 1, 0, 1)
			else
				local span = A / want
				art:SetTexCoord(0, 1, 0.5 - span / 2, 0.5 + span / 2)
			end
		elseif w >= h then
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
		if off then art:Hide(); fade:Hide(); covers:SetShown(false); return end
		art:SetAlpha(st and 1 or alpha or 0.22); art:Show(); fade:Show(); covers:SetShown(true); crop()
	end
	f:HookScript("OnSizeChanged", crop)
	f:HookScript("OnShow", refresh)
	refresh()
	return art, fade
end

-- A window never bigger than the screen. Sizes are fixed in UI units (the council
-- board is 980 wide), and the screen in UI units shrinks with a small resolution or
-- a big UI scale -- so when the window does not fit, it scales down until it does.
-- Re-fitted whenever it is shown or resized, and when the resolution or UI scale changes.
--
-- With a key and a grip (the window's title bar), Ctrl + mouse wheel on the grip
-- sets the window's own size, remembered per key in db.winScale. Scale, not a drag
-- corner: the layouts are fixed sizes and a drag-resize broke them. The screen
-- still wins -- the size you pick is used as far as it fits.
local FIT_MARGIN, FIT_MIN = 40, 0.5
local USER_MIN, USER_MAX, USER_STEP = 0.6, 1.4, 0.05
-- Until you pick a size, a window takes the screen's: 1.0 on a screen 1600 UI units
-- wide -- where the council board (980), the raider's window (540) and the gaps sit
-- side by side -- and proportionally smaller on a narrower one.
local FIT_REF_W = 1600
local fitted = {}
local function defaultScale()
	local sw = UIParent:GetWidth() or FIT_REF_W
	return math.max(USER_MIN, math.min(1, math.floor(sw / FIT_REF_W * 20) / 20))
end
local function userScale(key)
	local t = key and Okanvil.db and Okanvil.db.winScale
	return (t and t[key]) or defaultScale()
end
function W.FitToScreen(f, key, grip)
	local function fit()
		local w, h = f:GetWidth(), f:GetHeight()
		local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
		if not (w and h and w > 1 and h > 1 and sw and sh) then return end
		local s = math.max(FIT_MIN, math.min(userScale(key), (sw - FIT_MARGIN) / w, (sh - FIT_MARGIN) / h))
		if math.abs((f:GetScale() or 1) - s) > 0.01 then f:SetScale(s) end
	end
	f:HookScript("OnShow", fit)
	f:HookScript("OnSizeChanged", fit)
	if key and grip then
		grip:EnableMouseWheel(true)
		grip:SetScript("OnMouseWheel", function(_, delta)
			if not IsControlKeyDown() then return end
			local db = Okanvil.db
			if not db then return end
			db.winScale = db.winScale or {}
			local s = math.floor((userScale(key) + delta * USER_STEP) * 20 + 0.5) / 20
			db.winScale[key] = math.max(USER_MIN, math.min(USER_MAX, s))
			fit()
		end)
	end
	fitted[#fitted + 1] = fit
	fit()
	return fit
end
do
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("UI_SCALE_CHANGED")
	ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
	ev:SetScript("OnEvent", function() for _, fit in ipairs(fitted) do fit() end end)
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
	f:SetBackdropColor(C.body[1], C.body[2], C.body[3], 0.97)
	f:SetBackdropBorderColor(unpack3(C.edge))
	W.ForgeArt(f, 0.22)
	-- the kit's title bar: gradient, centred gold title, the red X
	local hdr = W.TitleBar(f, 26)
	hdr:EnableMouse(true); hdr:RegisterForDrag("LeftButton")
	hdr:SetScript("OnDragStart", function() f:StartMoving() end)
	hdr:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
	local t = hdr.title
	t:ClearAllPoints()
	t:SetPoint("LEFT", 30, 0); t:SetPoint("RIGHT", -30, 0)
	t:SetJustifyH("CENTER")
	t:SetText(title or "")
	if t.SetWordWrap then t:SetWordWrap(false) end
	local close = W.CloseButton(hdr); close:SetPoint("RIGHT", -4, 0)
	close:SetScript("OnClick", function() f:Hide() end)
	f.header, f.title, f.closeBtn = hdr, t, close

	openPopup = f
	f:HookScript("OnHide", function(sf)
		if openPopup == sf then openPopup = nil end
	end)
	W.FitToScreen(f, "popup:" .. tostring(title), hdr)
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
-- label = a short title (cut with "..." rather than run past the window);
-- hint (optional) = the grey line under it, for the details and where to paste.
local EXPORT_HINT = "Ctrl+C to copy, then paste into the hub importer."
function Okanvil:ShowExport(text, label, hint)
	local f = exportDlg
	if not f then
		f = self:Popup("Export")
		f:SetSize(440, 320)
		local hint = W.Text(f, EXPORT_HINT, "note", "dim")
		hint:SetPoint("TOPLEFT", 10, -30); hint:SetPoint("RIGHT", f, "RIGHT", -10, 0)
		hint:SetJustifyH("LEFT")
		if hint.SetWordWrap then hint:SetWordWrap(false) end
		f.hint = hint

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
	f.hint:SetText(hint or EXPORT_HINT)
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
-- Copy line -- ShowExport without the wall of text: a small window with ONE line
-- of the text showing, already selected. Ctrl+C still copies all of it (the
-- EditBox holds everything; the view just clips to a line). For exports that are
-- pasted somewhere else and never read here.
--   Okanvil:ShowCopyLine(text, "Attendance export", "Ctrl+C, then ... on the site")
-- ------------------------------------------------------------
local copyDlg
function Okanvil:ShowCopyLine(text, label, hint)
	local f = copyDlg
	if not f then
		f = self:Popup("Copy")
		f:SetSize(420, 96)
		local h = W.Text(f, "", "note", "dim")
		h:SetPoint("TOPLEFT", 10, -32); h:SetPoint("RIGHT", f, "RIGHT", -10, 0)
		h:SetJustifyH("LEFT")
		if h.SetWordWrap then h:SetWordWrap(false) end
		f.hint = h
		local box = W.Frame(f, "input")
		box:SetPoint("BOTTOMLEFT", 8, 10); box:SetPoint("BOTTOMRIGHT", -8, 10); box:SetHeight(24)
		-- a scroll frame one line tall: it clips the multi-line box to its first line
		local sf = CreateFrame("ScrollFrame", nil, box)
		sf:SetPoint("TOPLEFT", 6, -5); sf:SetPoint("BOTTOMRIGHT", -6, 3)
		local eb = CreateFrame("EditBox", nil, sf)
		eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetWidth(390)
		eb:SetFontObject(GameFontHighlightSmall)
		eb:SetTextColor(unpack3(C.textDim))
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		-- nothing to type here: any key but Ctrl+C / Ctrl+A puts the text back
		eb:SetScript("OnTextChanged", function(s, user) if user and f._text then s:SetText(f._text); s:HighlightText() end end)
		Okanvil:TrackEditBox(eb)
		f:HookScript("OnHide", function() eb:ClearFocus() end)
		sf:SetScrollChild(eb)
		f.eb = eb
		copyDlg = f
	end
	f._text = text or ""
	f.title:SetText("|cffffd200" .. (label or "Copy") .. "|r")
	f.hint:SetText(hint or "Ctrl+C to copy.")
	f.eb:SetText(f._text)
	f:Show()
	-- Focus so Ctrl+C works -- never in combat (it would eat the movement keys).
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
