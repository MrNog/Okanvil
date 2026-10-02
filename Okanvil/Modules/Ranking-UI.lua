-- ============================================================
-- Okanvil -- Ranking page (GUILD > Ranking).
-- Your portrait and numbers on the left; the board on the right: the top
-- three as art banners, everyone else in a list under them. One board at a
-- time -- DPS, Healing or Tanking, 25 or 10 -- Normal and Heroic already
-- merged by the site.
-- ============================================================

local Okanvil = Okanvil
local W = Okanvil.W
local C = Okanvil.Colors
local R = Okanvil.Ranking
local ADDON = "Okanvil-Ranking"

local FLAT = "Interface\\Buttons\\WHITE8x8"
local CLASS_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
-- Media/Ranking/<name>.blp: the raider's art from the RATS site, a 2:1 crop of
-- the whole picture (the rat stands on the right). _<class>.blp for the rest.
local ART = "Interface\\AddOns\\Okanvil\\Media\\Ranking\\"
local LEFT_W, GAP, PAD = 230, 14, 12
local CARD_H, CARD_GAP, ROW_H = 170, 8, 30
local PORTRAIT_H = 250
-- The name, numbers and boss list start this far up INTO the portrait, over its
-- darkened foot, so the whole list fits under it without scrolling.
local LIFT = 40
local INK = { 0.035, 0.037, 0.043 }   -- the near-black the cards sit on
local BEST_MAX = 12
local NAME_W, VAL_W = 84, 26
-- one boss row in the list: spread up to BAR_STEP_MAX when there is room,
-- never tighter than BAR_STEP (then the list scrolls)
local BAR_STEP, BAR_STEP_MAX = 18, 26
-- a boss row: the card's inner width less a gutter for the scrollbar
local BAR_W = LEFT_W - 12 - 26
-- a row stops short of the list's edge: the list clips there, and a right-aligned
-- number draws a pixel or two past its own box
local ROW_W = BAR_W - 6
local TRACK_W = ROW_W - NAME_W - 4 - VAL_W - 6
-- the rank numeral on each top-three card
local MEDAL = {
	{ 0.90, 0.75, 0.40 },   -- gold
	{ 0.80, 0.82, 0.86 },   -- silver
	{ 0.80, 0.55, 0.36 },   -- bronze
}
local DOT = "  |cff4a4d55·|r  "

local function classIcon(tex, token)
	local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token or ""]
	if c then
		tex:SetTexture(CLASS_TEX)
		tex:SetTexCoord(c[1], c[2], c[3], c[4])
	else
		tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end

-- The raider's art, else their class's; then cut to the frame's shape. The
-- texture is 2:1, so a frame of aspect `a` (width / height) shows the whole
-- height and the right a/2 of the width when a < 2 (the portrait), or the full
-- width and a band 2/a tall around the head when a > 2 (a banner).
local function setArt(tex, name, token, aspect)
	if not (name and tex:SetTexture(ART .. R.Norm(name))) then
		if not tex:SetTexture(ART .. "_" .. (token or ""):lower()) then tex:SetTexture(nil); return end
	end
	if aspect < 2 then
		tex:SetTexCoord(1 - aspect / 2, 1, 0, 1)
	else
		local h = 2 / aspect
		local top = math.max(0, 0.36 - h / 2)
		tex:SetTexCoord(0, 1, top, math.min(1, top + h))
	end
end

local function classRGB(token)
	local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token or ""]
	if cc then return cc.r, cc.g, cc.b end
	return C.text[1], C.text[2], C.text[3]
end

local function hexOf(r, g, b)
	return ("ff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- 8380 -> "8,380"; tank soak runs to the hundreds of thousands -> "586K", "1.24M"
local function fmtRate(n, kind)
	n = math.floor((n or 0) + 0.5)
	if kind == "t" then
		if n >= 1e6 then return ("%.2fM"):format(n / 1e6) end
		if n >= 1e4 then return ("%.0fK"):format(n / 1e3) end
	end
	local s = tostring(n)
	while true do
		local k
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then break end
	end
	return s
end

local function fmtTotal(n)
	n = n or 0
	if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
	if n >= 1e3 then return ("%.0fK"):format(n / 1e3) end
	return tostring(math.floor(n))
end

local function moveText(mv)
	if mv == nil or mv == 0 then return "" end
	if mv == "new" then return "|cffe0b860NEW|r" end
	if mv > 0 then return "|cff4fd16a+" .. mv .. "|r" end
	return "|cffe0564f" .. mv .. "|r"
end

local function pctText(p, suffix)
	if not p then return "|cff6f7176no parse|r" end
	local r, g, b = R.PctColor(p)
	return ("|c%s%.0f%%%s|r"):format(hexOf(r, g, b), p, suffix or "")
end

local function fill(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer)
	t:SetTexture(FLAT)
	t:SetVertexColor(r, g, b, a)
	return t
end

-- a vertical scroll list: plain ScrollFrame + our own slider, like Home's cards
local function scrollList(parent, onResize)
	local sf = CreateFrame("ScrollFrame", nil, parent)
	local child = CreateFrame("Frame", nil, sf); child:SetSize(10, 1)
	sf:SetScrollChild(child)
	local sb = CreateFrame("Slider", nil, parent)
	sb:SetWidth(4); sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
	local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT)
	th:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1); th:SetSize(4, 30)
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * ROW_H * 2) end)
	local function range()
		child:SetWidth(math.max(40, sf:GetWidth()))
		local max = math.max(0, child:GetHeight() - sf:GetHeight())
		sb:SetMinMaxValues(0, max)
		if max > 4 then sb:Show() else sb:Hide() end
		if sb:GetValue() > max then sb:SetValue(max) end
		if onResize then onResize(child:GetWidth()) end
	end
	sf:SetScript("OnSizeChanged", range)
	return sf, child, sb, range
end

-- ------------------------------------------------------------
-- Import popup (officers): paste the site's export.
-- ------------------------------------------------------------
local importDlg
local function showImport()
	local f = importDlg
	if not f then
		f = Okanvil:Popup("Import ranking")
		f:SetSize(460, 300)
		local hint = W.Text(f, "On the RATS site: Rankings > Export to Okanvil. Paste here (Ctrl+V), then Save.", "note", "dim")
		hint:SetPoint("TOPLEFT", 10, -30)
		local box = W.MultiEdit(f)
		box:SetPoint("TOPLEFT", 8, -46)
		box:SetPoint("BOTTOMRIGHT", -8, 38)
		local save = W.Button(f, "Save", "primary")
		save:SetSize(100, 22); save:SetPoint("BOTTOMLEFT", 8, 8)
		local cancel = W.Button(f, "Cancel")
		cancel:SetSize(80, 22); cancel:SetPoint("LEFT", save, "RIGHT", 6, 0)
		local msg = W.Text(f, "", "label", "dim")
		msg:SetPoint("LEFT", cancel, "RIGHT", 10, 0)
		cancel:SetScript("OnClick", function() f:Hide() end)
		save:SetScript("OnClick", function()
			local n, err = R.Import(box:GetText())
			if n then
				box:SetText("")
				f:Hide()
				Okanvil:Print("Ranking saved -- |cffffd200" .. n .. "|r entries, shared with the guild online.")
			else
				msg:SetText("|cffff5555" .. (err or "could not read that") .. "|r")
			end
		end)
		f:HookScript("OnShow", function() msg:SetText("") end)
		f.box = box
		importDlg = f
	end
	f.box:SetText("")
	f:Show()
end

-- A card on near-black, not the grey raised panel: the art carries the colour.
local function darkCard(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
	f:SetBackdropColor(INK[1], INK[2], INK[3], 0.94)
	f:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
	return f
end

-- ink fading over a picture, so text beside it sits on dark and the picture keeps its colours
local function inkFade(parent, dir, a1, a2)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetTexture(FLAT)
	t:SetGradientAlpha(dir, INK[1], INK[2], INK[3], a1, INK[1], INK[2], INK[3], a2)
	return t
end

local function isOfficer()
	return Okanvil.U and Okanvil.U.canSeePrio and Okanvil.U.canSeePrio() and true or false
end

-- ------------------------------------------------------------
-- The page
-- ------------------------------------------------------------
function Okanvil:BuildRanking(host)
	local state = { size = "25", kind = "d" }
	local kindTabs, sizeTabs, periodTabs = {}, {}, {}
	local refresh

	local function tab(parent, label, w, onClick)
		local b = W.Button(parent, label, "tab")
		b:SetSize(w, 22)
		b:SetScript("OnClick", function() onClick(); refresh() end)
		return b
	end

	local dash = W.Dashboard(host, {
		title = "Ranking",
		subtitle = "The guild's boards from the RATS site -- Normal and Heroic together",
		icon = Okanvil.ICONS.ranking,
		drawerWidth = 0,
		footerHeight = 0,
		onSecondary = showImport,
		secondaryText = function() return "Import" end,
		secondaryWidth = 90,
		secondaryShown = isOfficer,
		statusText = function()
			local d, s = R.Data(), Okanvil.db and Okanvil.db.ranking
			if not d then return "" end
			return ("|cff8a8d93%s%s%s|r"):format(d.label or d.raid or "?", DOT,
				(s and s.t and date("%d %b", s.t) or "?") .. ((s and s.by) and (" by " .. s.by) or ""))
		end,
	})
	if dash.cta2 then dash.cta2:Tooltip("Paste the RATS site's \"Export to Okanvil\". It goes to everyone in the guild online.") end

	local page = CreateFrame("Frame", nil, dash.main)
	page:SetPoint("TOPLEFT", PAD, -PAD)
	page:SetPoint("BOTTOMRIGHT", -PAD, PAD)

	-- ---- left: your portrait, your numbers on it ----
	local you = darkCard(page)
	you:SetPoint("TOPLEFT", 0, 0)
	you:SetPoint("BOTTOMLEFT", 0, 0)
	you:SetWidth(LEFT_W)
	local yArt = you:CreateTexture(nil, "BORDER")
	yArt:SetPoint("TOPLEFT", 1, -1); yArt:SetPoint("TOPRIGHT", -1, -1)
	yArt:SetHeight(PORTRAIT_H)
	-- full colour; only its lower part darkens under your name and rank
	local yFade = inkFade(you, "VERTICAL", 1, 0)
	yFade:SetPoint("BOTTOMLEFT", yArt, "BOTTOMLEFT"); yFade:SetPoint("BOTTOMRIGHT", yArt, "BOTTOMRIGHT")
	yFade:SetHeight(110 + LIFT)
	-- where the text below the picture begins: LIFT up from its bottom edge
	local yBase = CreateFrame("Frame", nil, you)
	yBase:SetSize(1, 1)
	yBase:SetPoint("BOTTOMLEFT", yArt, "BOTTOMLEFT", 0, LIFT)
	local yBar = fill(you, "ARTWORK", 1, 1, 1, 1)
	yBar:SetHeight(2); yBar:SetPoint("TOPLEFT", 1, -1); yBar:SetPoint("TOPRIGHT", -1, -1)
	local yRank = W.Text(you, "", "huge", "accent")
	yRank:SetPoint("BOTTOMLEFT", yBase, "BOTTOMLEFT", 12, 6)
	local yOf = W.Text(you, "", "label", "dim"); yOf:SetPoint("BOTTOMLEFT", yRank, "BOTTOMRIGHT", 6, 3)
	local yIcon = you:CreateTexture(nil, "ARTWORK"); yIcon:SetSize(18, 18)
	yIcon:SetPoint("BOTTOMLEFT", yRank, "TOPLEFT", 0, 6)
	local yName = W.Text(you, "", "head"); yName:SetPoint("LEFT", yIcon, "RIGHT", 6, 0)
	local yMove = W.Text(you, "", "label"); yMove:SetPoint("LEFT", yName, "RIGHT", 6, 0)
	local yNone = W.Text(you, "", "label", "dim")
	yNone:SetPoint("BOTTOMLEFT", yBase, "BOTTOMLEFT", 12, 10)
	yNone:SetPoint("RIGHT", you, "RIGHT", -12, 0)
	yNone:SetJustifyH("LEFT")

	-- four numbers in two rows of tiles
	local tiles = {}
	local TILE_W = (LEFT_W - 24 - 6) / 2
	for i = 1, 4 do
		local t = CreateFrame("Frame", nil, you)
		t:SetSize(TILE_W, 36)
		local col, rowi = (i - 1) % 2, math.floor((i - 1) / 2)
		t:SetPoint("TOPLEFT", yBase, "BOTTOMLEFT", 11 + col * (TILE_W + 6), -8 - rowi * 42)
		local bg = fill(t, "BACKGROUND", 1, 1, 1, 0.04); bg:SetAllPoints()
		t.l = W.Text(t, "", "note", "dim"); t.l:SetPoint("TOPLEFT", 7, -5)
		t.v = W.Text(t, "", "head"); t.v:SetPoint("BOTTOMLEFT", 7, 4)
		tiles[i] = t
	end
	local bestLbl = W.Text(you, "BEST BOSSES", "note", "dim")
	bestLbl:SetPoint("TOPLEFT", tiles[3], "BOTTOMLEFT", 1, -14)
	-- the boss rows scroll inside the card, so a long raid never runs past it
	local bsf, bchild, bsb, brange = scrollList(you)
	-- a fixed width, set outright: a width derived from anchors read too wide
	-- here and the values on the right were cut off
	bsf:SetPoint("TOPLEFT", bestLbl, "BOTTOMLEFT", 0, -6)
	bsf:SetPoint("BOTTOM", you, "BOTTOM", 0, 10)
	bsf:SetWidth(BAR_W)
	-- its height is only known once laid out (and changes with the window): re-spread the rows
	bsf:HookScript("OnSizeChanged", function() if refresh then refresh() end end)
	bsb:SetPoint("TOPLEFT", bsf, "TOPRIGHT", 6, 0); bsb:SetPoint("BOTTOMLEFT", bsf, "BOTTOMRIGHT", 6, 0)
	local bars = {}
	for i = 1, BEST_MAX do
		local b = CreateFrame("Frame", nil, bchild)
		b:SetHeight(16)
		b:SetPoint("TOPLEFT", 0, -(i - 1) * BAR_STEP)
		b:SetWidth(ROW_W)
		b.name = W.Text(b, "", "note"); b.name:SetPoint("LEFT", 0, 0); b.name:SetWidth(NAME_W)
		b.name:SetJustifyH("LEFT"); b.name:SetTextColor(0.80, 0.81, 0.83)
		if b.name.SetWordWrap then b.name:SetWordWrap(false) end
		b.val = W.Text(b, "", "note"); b.val:SetPoint("RIGHT", 0, 0); b.val:SetWidth(VAL_W); b.val:SetJustifyH("RIGHT")
		b.track = fill(b, "BACKGROUND", 0, 0, 0, 0.45); b.track:SetHeight(4)
		b.track:SetPoint("LEFT", b.name, "RIGHT", 4, 0); b.track:SetPoint("RIGHT", b.val, "LEFT", -6, 0)
		b.bar = fill(b, "ARTWORK", 1, 1, 1, 1); b.bar:SetHeight(4)
		b.bar:SetPoint("LEFT", b.track, "LEFT", 0, 0)
		bars[i] = b
	end

	-- ---- right: switches, top three, then the rest ----
	local right = CreateFrame("Frame", nil, page)
	right:SetPoint("TOPLEFT", you, "TOPRIGHT", GAP, 0)
	right:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

	local x = 0
	for _, k in ipairs(R.BOARDS) do
		local b = tab(right, R.BOARD_LABEL[k], k == "d" and 46 or 68, function() state.kind = k end)
		b:SetPoint("TOPLEFT", right, "TOPLEFT", x, 0)
		x = x + b:GetWidth() + 8
		kindTabs[k] = b
	end
	local prevTab
	for i = #R.SIZES, 1, -1 do
		local sz = R.SIZES[i]
		local b = tab(right, sz .. "-man", 58, function() state.size = sz end)
		if prevTab then b:SetPoint("RIGHT", prevTab, "LEFT", -4, 0)
		else b:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, 0) end
		sizeTabs[sz] = b
		prevTab = b
	end
	-- week / all time, left of the sizes (only the periods the export carries)
	for i = #R.PERIODS, 1, -1 do
		local pd = R.PERIODS[i]
		local b = tab(right, R.PERIOD_LABEL[pd], pd == "all" and 62 or 74, function() state.period = pd end)
		periodTabs[pd] = b
	end

	-- the top three side by side, each the whole picture with the rank, name and
	-- numbers over its darkened foot
	local cards = {}
	for i = 1, 3 do
		local c = darkCard(right)
		c:SetHeight(CARD_H)
		c.art = c:CreateTexture(nil, "BORDER")
		c.art:SetPoint("TOPLEFT", 1, -1); c.art:SetPoint("BOTTOMRIGHT", -1, 1)
		c.fade = inkFade(c, "VERTICAL", 1, 0)
		c.fade:SetPoint("BOTTOMLEFT", 1, 1); c.fade:SetPoint("BOTTOMRIGHT", -1, 1); c.fade:SetHeight(96)
		c.top = c:CreateTexture(nil, "ARTWORK"); c.top:SetTexture(FLAT); c.top:SetHeight(2)
		c.top:SetPoint("TOPLEFT", 1, -1); c.top:SetPoint("TOPRIGHT", -1, -1)
		local m = MEDAL[i]
		c.num = W.Text(c, tostring(i), "huge"); c.num:SetPoint("TOPLEFT", 10, -8)
		c.num:SetTextColor(m[1], m[2], m[3])
		c.move = W.Text(c, "", "label"); c.move:SetPoint("TOPRIGHT", -10, -10)
		c.sub = W.Text(c, "", "note", "dim"); c.sub:SetPoint("BOTTOMLEFT", 10, 8)
		c.sub:SetPoint("RIGHT", c, "RIGHT", -8, 0); c.sub:SetJustifyH("LEFT")
		if c.sub.SetWordWrap then c.sub:SetWordWrap(false) end
		c.rate = W.Text(c, "", "title", "accent"); c.rate:SetPoint("BOTTOMLEFT", c.sub, "TOPLEFT", 0, 4)
		c.unit = W.Text(c, "", "note", "dim"); c.unit:SetPoint("BOTTOMLEFT", c.rate, "BOTTOMRIGHT", 5, 1)
		c.icon = c:CreateTexture(nil, "ARTWORK"); c.icon:SetSize(18, 18)
		c.icon:SetPoint("BOTTOMLEFT", c.rate, "TOPLEFT", 0, 5)
		c.name = W.Text(c, "", "head"); c.name:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
		if i == 1 then c:SetBackdropBorderColor(C.borderHi[1], C.borderHi[2], C.borderHi[3], 1) end
		cards[i] = c
	end
	cards[1]:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -30)
	cards[3]:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, -30)
	cards[2]:SetPoint("TOPLEFT", cards[1], "TOPRIGHT", CARD_GAP, 0)
	cards[2]:SetPoint("TOPRIGHT", cards[3], "TOPLEFT", -CARD_GAP, 0)
	-- three equal cards across whatever width the window gives; the art is cut to
	-- each card's shape, so it is cut again when that changes
	local function sizeCards()
		local w = math.floor(((right:GetWidth() or 0) - 2 * CARD_GAP) / 3)
		if w < 60 then return end
		cards[1]:SetWidth(w); cards[3]:SetWidth(w)
		for _, c in ipairs(cards) do
			if c._p then setArt(c.art, c._p.name, c._p.class, (w - 2) / (CARD_H - 2)) end
		end
	end
	right:SetScript("OnSizeChanged", sizeCards)

	local listBox = CreateFrame("Frame", nil, right)
	listBox:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -12)
	listBox:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
	local function col(parent, w, justify, size, role)
		local t = W.Text(parent, "", size or "label", role)
		t:SetWidth(w); t:SetJustifyH(justify)
		if t.SetWordWrap then t:SetWordWrap(false) end
		return t
	end
	-- right-hand columns, from the edge in
	local COLS = { { "srv", 46 }, { "pts", 48 }, { "rate", 66 }, { "move", 40 } }
	local function layoutCols(parent, row)
		local anchor
		for _, cdef in ipairs(COLS) do
			local t = row[cdef[1]]
			if anchor then t:SetPoint("RIGHT", anchor, "LEFT", -8, 0) else t:SetPoint("RIGHT", parent, "RIGHT", -8, 0) end
			anchor = t
		end
		return anchor
	end
	local head = CreateFrame("Frame", nil, listBox)
	head:SetHeight(18); head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT", -8, 0)
	local hr = fill(head, "BORDER", C.border[1], C.border[2], C.border[3], 1)
	hr:SetHeight(1); hr:SetPoint("BOTTOMLEFT"); hr:SetPoint("BOTTOMRIGHT")
	head.srv = col(head, 46, "CENTER", "note", "dim"); head.srv:SetText("SERVER")
	head.pts = col(head, 48, "RIGHT", "note", "dim"); head.pts:SetText("PTS")
	head.rate = col(head, 66, "RIGHT", "note", "dim")
	head.move = col(head, 40, "RIGHT", "note", "dim")
	layoutCols(head, head)
	local hN = W.Text(head, "#", "note", "dim"); hN:SetPoint("LEFT", 0, 0); hN:SetWidth(22); hN:SetJustifyH("RIGHT")
	local hP = W.Text(head, "PLAYER", "note", "dim"); hP:SetPoint("LEFT", 62, 0)

	local rows = {}
	-- the pts bar under each row is a share of the row's width, known only once laid out
	local function sizeBars(w)
		for _, r in ipairs(rows) do
			if r:IsShown() and r._pts then r.ptsBar:SetWidth(math.max(2, (w or 300) * math.min(r._pts, 100) / 100)) end
		end
	end
	local sf, child, sb, range = scrollList(listBox, sizeBars)
	sf:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2); sf:SetPoint("BOTTOMRIGHT", -8, 0)
	sb:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -1, -20); sb:SetPoint("BOTTOMRIGHT", -1, 0)
	local function rowAt(i)
		local r = rows[i]
		if r then return r end
		r = CreateFrame("Frame", nil, child)
		r:SetHeight(ROW_H)
		r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H); r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
		-- the player's class colour from the left, and their pts as a thin bar underneath
		r.tint = r:CreateTexture(nil, "BACKGROUND"); r.tint:SetTexture(FLAT)
		r.tint:SetPoint("TOPLEFT"); r.tint:SetPoint("BOTTOMLEFT"); r.tint:SetWidth(280)
		r.ptsBar = r:CreateTexture(nil, "BORDER"); r.ptsBar:SetTexture(FLAT); r.ptsBar:SetHeight(2)
		r.ptsBar:SetPoint("BOTTOMLEFT", 0, 0)
		r.me = fill(r, "BORDER", C.accent[1], C.accent[2], C.accent[3], 0.14); r.me:SetAllPoints()
		r.n = col(r, 22, "RIGHT", "body", "dim"); r.n:SetPoint("LEFT", 0, 0)
		r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", 32, 0)
		r.srv = col(r, 46, "CENTER", "label"); r.pts = col(r, 48, "RIGHT", "body"); r.rate = col(r, 66, "RIGHT", "body")
		r.move = col(r, 40, "RIGHT", "body")
		r.pts:SetTextColor(C.accentHi[1], C.accentHi[2], C.accentHi[3])
		local last = layoutCols(r, r)
		-- the server % as a coloured chip
		r.chip = r:CreateTexture(nil, "ARTWORK"); r.chip:SetTexture(FLAT)
		r.chip:SetPoint("LEFT", r.srv, "LEFT", 3, 0); r.chip:SetPoint("RIGHT", r.srv, "RIGHT", -3, 0); r.chip:SetHeight(18)
		r.name = W.Text(r, "", "body"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
		r.name:SetPoint("RIGHT", last, "LEFT", -6, 0); r.name:SetJustifyH("LEFT")
		if r.name.SetWordWrap then r.name:SetWordWrap(false) end
		rows[i] = r
		return r
	end

	local empty = W.Text(page, "", "body", "dim")
	empty:SetPoint("TOPLEFT", 4, -4)
	empty:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	empty:SetJustifyH("LEFT")

	-- ---- paint ----
	local function paintYou()
		local myName = UnitName("player")
		local myClass = select(2, UnitClass("player"))
		local cr, cg, cb = classRGB(myClass)
		setArt(yArt, myName, myClass, (LEFT_W - 2) / PORTRAIT_H)
		classIcon(yIcon, myClass)
		yBar:SetVertexColor(cr, cg, cb, 0.9)
		yName:SetText(myName or ""); yName:SetTextColor(cr, cg, cb)
		-- your MAIN spec, not the tab you are looking at: the board you have the most
		-- fights on, in the size picked (or the other size if you are on none there)
		local p, rank, of, kind, size
		local sizes = { state.size }
		for _, sz in ipairs(R.SIZES) do if sz ~= state.size then sizes[#sizes + 1] = sz end end
		for _, sz in ipairs(sizes) do
			for _, k in ipairs(R.BOARDS) do
				local q, qr, qo = R.Find(sz, k, myName, state.period, true)
				if q and (not p or q.fights > p.fights) then p, rank, of, kind, size = q, qr, qo, k, sz end
			end
			if p then break end
		end
		if p then
			yNone:Hide(); yRank:Show(); yOf:Show()
			yRank:SetText("#" .. rank)
			yOf:SetText(("of %d  %s%s"):format(of, R.BOARD_LABEL[kind], size ~= state.size and ("  " .. size .. "-man") or ""))
			yMove:SetText(moveText(R.Move(size, kind, p.key, rank, state.period)))
			local vals = {
				{ R.BOARD_UNIT[kind], fmtRate(p.rate, kind) },
				{ "PTS", ("|cffe0b860%.1f|r"):format(p.pts) },
				{ "SERVER", pctText(p.srv) },
				{ "FIGHTS", tostring(p.fights) },
			}
			for i, v in ipairs(vals) do tiles[i].l:SetText(v[1]); tiles[i].v:SetText(v[2]); tiles[i]:Show() end
			yIcon:ClearAllPoints(); yIcon:SetPoint("BOTTOMLEFT", yRank, "TOPLEFT", 0, 6)
			bestLbl:ClearAllPoints(); bestLbl:SetPoint("TOPLEFT", tiles[3], "BOTTOMLEFT", 1, -14)
		else
			yRank:Hide(); yOf:Hide(); yMove:SetText("")
			for i = 1, 4 do tiles[i]:Hide() end
			yNone:Show()
			yNone:SetText("Not on the ranking yet.")
			yIcon:ClearAllPoints(); yIcon:SetPoint("BOTTOMLEFT", yNone, "TOPLEFT", 0, 6)
			bestLbl:ClearAllPoints(); bestLbl:SetPoint("TOPLEFT", yBase, "BOTTOMLEFT", 12, -12)
		end
		local parses = R.Parses(size or state.size, myName)
		if parses and #parses > 0 then bestLbl:Show(); bsf:Show() else bestLbl:Hide(); bsf:Hide() end
		-- in the raid's boss order, not best first: easier to find a boss
		local ordered = {}
		for i, c in ipairs(parses or {}) do ordered[i] = c end
		table.sort(ordered, function(a, b) return (a.i or 99) < (b.i or 99) end)
		local shown = 0
		for i = 1, BEST_MAX do
			local b, c = bars[i], ordered[i]
			if c then shown = i end
			if c then
				local r, g, bl = R.PctColor(c.pct)
				b.name:SetText(R.ShortBoss(c.boss))
				b.val:SetText(("%d"):format(math.floor(c.pct))); b.val:SetTextColor(r, g, bl)
				b.bar:SetVertexColor(r, g, bl, 1)
				-- a fixed width: the track has none yet the first time the page paints
				b.bar:SetWidth(math.max(2, TRACK_W * math.min(c.pct, 100) / 100))
				b:Show()
			else
				b:Hide()
			end
		end
		-- spread the rows over the height the card has, so a short raid does not
		-- leave the bottom of the card empty
		local room = bsf:GetHeight() or 0
		local step = BAR_STEP
		if shown > 0 and room > 0 then
			step = math.max(BAR_STEP, math.min(BAR_STEP_MAX, math.floor(room / shown)))
		end
		for i = 1, BEST_MAX do
			bars[i]:ClearAllPoints()
			bars[i]:SetPoint("TOPLEFT", 0, -(i - 1) * step)
		end
		bchild:SetHeight(math.max(1, shown * step))
		bsb:SetValue(0)
		brange()
	end

	refresh = function()
		for k, b in pairs(kindTabs) do b:SetKind(k == state.kind and "tabOn" or "tab") end
		for sz, b in pairs(sizeTabs) do b:SetKind(sz == state.size and "tabOn" or "tab") end
		dash:Refresh()
		if not R.Data() then
			you:Hide(); right:Hide()
			empty:SetText(isOfficer()
				and "No ranking yet. On the RATS site open Rankings, press Export to Okanvil, then Import it here. Everyone in the guild online gets it."
				or "No ranking yet. It arrives by itself once an officer imports it, or from any guild member who has it.")
			empty:Show()
			return
		end
		empty:Hide(); you:Show(); right:Show()
		if not (state.period and R.HasPeriod(state.period)) then state.period = R.DefaultPeriod() end
		local anchor = sizeTabs[R.SIZES[1]]
		for i = #R.PERIODS, 1, -1 do
			local pd = R.PERIODS[i]
			local b = periodTabs[pd]
			b:ClearAllPoints()
			if R.HasPeriod(pd) then
				b:SetPoint("RIGHT", anchor, "LEFT", anchor == sizeTabs[R.SIZES[1]] and -18 or -4, 0)
				b:SetKind(pd == state.period and "tabOn" or "tab")
				b:Show()
				anchor = b
			else
				b:Hide()
			end
		end

		local list = R.Board(state.size, state.kind, state.period) or {}
		local unit = R.BOARD_UNIT[state.kind]
		head.rate:SetText(unit)
		paintYou()

		local me = R.Norm(UnitName("player"))
		local main = Okanvil.U and Okanvil.U.mainOf and Okanvil.U.mainOf(UnitName("player"))
		local mainKey = main and R.Norm(main)
		for i = 1, 3 do
			local c, p = cards[i], list[i]
			c._p = p
			if p then
				local r, g, bl = classRGB(p.class)
				c.top:SetVertexColor(r, g, bl, 0.9)
				classIcon(c.icon, p.class)
				c.name:SetText(p.name); c.name:SetTextColor(r, g, bl)
				c.move:SetText(moveText(R.Move(state.size, state.kind, p.key, i, state.period)))
				c.sub:SetText(("|cffe0b860%.1f pts|r%s%d fight%s%s%s"):format(
					p.pts, DOT, p.fights, p.fights == 1 and "" or "s", DOT, pctText(p.srv, " srv"))
					.. (p.hc and (DOT .. "|cffff8000H|r") or ""))
				c.rate:SetText(fmtRate(p.rate, state.kind))
				c.unit:SetText(unit)
				c:Show()
			else
				c:Hide()
			end
		end
		sizeCards()

		local n = 0
		for i = 4, #list do
			local p = list[i]
			n = n + 1
			local r = rowAt(n)
			local cr, cg, cb = classRGB(p.class)
			r.tint:SetGradientAlpha("HORIZONTAL", cr, cg, cb, 0.16, cr, cg, cb, 0)
			r.ptsBar:SetVertexColor(cr, cg, cb, 0.35)
			r._pts = p.pts
			r.n:SetText(i)
			classIcon(r.icon, p.class)
			-- H = their best came from Heroic
			r.name:SetText(p.name .. (p.hc and "  |cffff8000H|r" or "")); r.name:SetTextColor(cr, cg, cb)
			r.move:SetText(moveText(R.Move(state.size, state.kind, p.key, i, state.period)))
			r.rate:SetText(fmtRate(p.rate, state.kind))
			r.pts:SetText(("%.1f"):format(p.pts))
			if p.srv then
				local sr, sg, sbb = R.PctColor(p.srv)
				r.chip:SetVertexColor(sr, sg, sbb, 1); r.chip:Show()
				r.srv:SetText(("%.0f%%"):format(p.srv)); r.srv:SetTextColor(0.06, 0.06, 0.07)
			else
				r.chip:Hide()
				r.srv:SetText("--"); r.srv:SetTextColor(0.37, 0.38, 0.41)
			end
			if p.key == me or p.key == mainKey then r.me:Show() else r.me:Hide() end
			r:Show()
		end
		for i = n + 1, #rows do rows[i]:Hide() end
		if n == 0 then head:Hide() else head:Show() end
		child:SetHeight(math.max(1, n * ROW_H))
		range()
	end

	R.onChange = function() if host:IsVisible() then refresh() end end
	host:HookScript("OnShow", refresh)
	refresh()
end

-- ------------------------------------------------------------
-- Register
-- ------------------------------------------------------------
Okanvil_Plugins = Okanvil_Plugins or {}
Okanvil_Plugins[ADDON] = {
	title = "Ranking",
	desc  = "The guild's DPS / Healing / Tanking boards from the RATS site, plus each raider's "
		.. "best bosses on their tooltip. An officer imports it; everyone online gets it.",
	icon  = Okanvil.ICONS and Okanvil.ICONS.ranking,
	build = function(panel) Okanvil:BuildRanking(panel) end,
}
if Okanvil and Okanvil.Register then
	Okanvil:Register(ADDON)
end
