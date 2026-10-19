-- ============================================================
-- Okanvil -- Ranking page (GUILD > Ranking).
-- Your main only: your rank on its main board, its numbers, its server %
-- per boss, and the players just above and below it. The whole board is one click away.
-- Normal and Heroic already merged by the site.
-- ============================================================

local Okanvil = Okanvil
local W = Okanvil.W
local C = Okanvil.Colors
local R = Okanvil.Ranking
local ADDON = "Okanvil-Ranking"

local FLAT = "Interface\\Buttons\\WHITE8x8"
local CLASS_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
-- The raider's art (a 2:1 crop of the RATS site's picture, the rat on the
-- right) ships in the optional Okanvil-Art addon, so new art never needs an
-- Okanvil update. Without it, or for a raider with no art, the class's own.
local ART_RAIDER = "Interface\\AddOns\\Okanvil-Art\\Ranking\\"
local ART_CLASS = "Interface\\AddOns\\Okanvil\\Media\\Ranking\\_"
local ART_FOCUS = 0.62           -- where the raider stands across the 2:1 art
local PAD, GAP = 12, 8
local CHIP_H, ROW_H, BOSS_STEP, BOSS_STEP_MAX = 24, 26, 19, 28
local AROUND = 4                 -- the one above you, you, and two below
local RANK_SIZE, NAME_SIZE, NUM_SIZE = 44, 30, 18
local BOSS_NAME_W, VAL_W = 110, 64
local CARD_SHARE, INFO_GAP = 0.50, 14   -- the portrait card's share of the width; the gap after it
local FOOT_H, FOOT_FADE = 118, 40  -- the card's solid foot under the rank and name; its melt into the art
local TILE_H, TILE_GAP, NEAR_H = 44, 6, 22
local INK = { 0.035, 0.037, 0.043 }   -- the near-black the card sits on
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
-- height and a/2 of the width when a < 2, centred on the raider (ART_FOCUS),
-- or the full width and a band 2/a tall around the head when a > 2 (a banner).
local function setArt(tex, name, token, aspect)
	if not (name and tex:SetTexture(ART_RAIDER .. R.Norm(name))) then
		if not tex:SetTexture(ART_CLASS .. (token or ""):lower()) then tex:SetTexture(nil); return end
	end
	if aspect < 2 then
		local span = aspect / 2
		local left = math.min(math.max(ART_FOCUS - span / 2, 0), 1 - span)
		tex:SetTexCoord(left, left + span, 0, 1)
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

local function moveText(mv)
	if mv == nil or mv == 0 then return "" end
	if mv == "new" then return "|cffe0b860NEW|r" end
	-- places climbed or lost since the previous ranking; paintMove adds the arrow
	if mv > 0 then return "|cff4fd16a" .. mv .. "|r" end
	return "|cffe0564f" .. -mv .. "|r"
end

-- The movement number with an arrow beside it: green pointing up for places
-- climbed, red pointing down for places lost. The client has no plain solid
-- triangle, so it is drawn from 1px strips of flat colour, 13 wide down to 1.
local ARROW_H = 7
local function paintMove(fs, mv)
	fs:SetText(moveText(mv))
	local a = fs._arrow
	if not a then
		a = CreateFrame("Frame", nil, fs:GetParent())
		a:SetSize(ARROW_H * 2 - 1, ARROW_H)
		a.strips = {}
		for i = 1, ARROW_H do
			local t = a:CreateTexture(nil, "OVERLAY")
			t:SetTexture(FLAT)
			t:SetSize(i * 2 - 1, 1)
			a.strips[i] = t
		end
		fs._arrow = a
	end
	if type(mv) ~= "number" or mv == 0 then a:Hide(); return end
	local up = mv > 0
	local r, g, b = 0.31, 0.82, 0.42
	if not up then r, g, b = 0.88, 0.34, 0.31 end
	for i, t in ipairs(a.strips) do
		t:ClearAllPoints()
		-- the 1px tip sits at the top for up, at the bottom for down
		if up then t:SetPoint("TOP", a, "TOP", 0, -(i - 1))
		else t:SetPoint("BOTTOM", a, "BOTTOM", 0, i - 1) end
		t:SetVertexColor(r, g, b, 1)
	end
	a:ClearAllPoints()
	if fs:GetJustifyH() == "LEFT" then
		a:SetPoint("RIGHT", fs, "LEFT", -3, 0)
	else
		a:SetPoint("RIGHT", fs, "RIGHT", -(fs:GetStringWidth() + 4), 0)
	end
	a:Show()
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
local function scrollList(parent, onResize, step)
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
	sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * (step or ROW_H) * 2) end)
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
	f:SetBackdropBorderColor(C.borderHi[1], C.borderHi[2], C.borderHi[3], 1)
	return f
end

-- ink fading over a picture, so text on it sits on dark and the picture keeps its colours
local function inkFade(parent, dir, a1, a2)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetTexture(FLAT)
	t:SetGradientAlpha(dir, INK[1], INK[2], INK[3], a1, INK[1], INK[2], INK[3], a2)
	return t
end

local function isOfficer()
	return Okanvil.U and Okanvil.U.canSeePrio and Okanvil.U.canSeePrio() and true or false
end

-- The toon's main board: the one it has the most fights on, in the size picked
-- (or the other size if it is on none there).
local function mainBoard(name, size, period)
	local p, rank, of, kind, sz
	local sizes = { size }
	for _, s in ipairs(R.SIZES) do if s ~= size then sizes[#sizes + 1] = s end end
	for _, s in ipairs(sizes) do
		for _, k in ipairs(R.BOARDS) do
			local q, qr, qo = R.Find(s, k, name, period, true)
			if q and (not p or q.fights > p.fights) then p, rank, of, kind, sz = q, qr, qo, k, s end
		end
		if p then break end
	end
	return p, rank, of, kind, sz
end

-- A toon's class token: from any board it is on, else your own if it is you.
local function classOf(name)
	for _, s in ipairs(R.SIZES) do
		for _, pd in ipairs(R.PERIODS) do
			for _, k in ipairs(R.BOARDS) do
				local p = R.Find(s, k, name, pd, true)
				if p then return p.class, p.spec end
			end
		end
	end
	if name == UnitName("player") then return (select(2, UnitClass("player"))) end
	return nil
end

-- ------------------------------------------------------------
-- The page
-- ------------------------------------------------------------
function Okanvil:BuildRanking(host)
	local state = { size = "25", kind = "d", view = "toon" }
	local sizeTabs, periodTabs, kindTabs = {}, {}, {}
	local refresh

	local function tab(parent, label, w, onClick)
		local b = W.Button(parent, label, "tab")
		b:SetSize(w, 22)
		b:SetScript("OnClick", function() onClick(); refresh() end)
		return b
	end

	local dash = W.Dashboard(host, {
		title = "Ranking",
		subtitle = "Your main on the guild's boards from the RATS site",
		icon = Okanvil.ICONS.ranking,
		drawerWidth = 0,
		footerHeight = 0,
		onSecondary = showImport,
		secondaryText = function() return "Import" end,
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

	-- ---- top line: "< My toon" on the board, then size and period ----
	local top = CreateFrame("Frame", nil, page)
	top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(CHIP_H)
	local back = W.Button(top, "< My toon", "tab")
	back:SetSize(84, CHIP_H); back:SetPoint("LEFT", 0, 0)
	back:SetScript("OnClick", function() state.view = "toon"; refresh() end)

	for _, sz in ipairs(R.SIZES) do
		sizeTabs[sz] = tab(top, sz .. "-man", 58, function() state.size = sz end)
	end
	for _, pd in ipairs(R.PERIODS) do
		periodTabs[pd] = tab(top, R.PERIOD_LABEL[pd], pd == "all" and 62 or 74, function() state.period = pd end)
	end
	-- on the right of the line under the header: periods, then sizes, a wider
	-- gap between the two groups ("< My toon" on the left, on the board)
	local function layoutTabs()
		local row, firstSize = {}, 0
		for _, pd in ipairs(R.PERIODS) do
			local b = periodTabs[pd]
			b:ClearAllPoints()
			if R.HasPeriod(pd) then
				b:SetKind(pd == state.period and "tabOn" or "tab"); b:Show()
				row[#row + 1] = b
			else
				b:Hide()
			end
		end
		firstSize = #row + 1
		for _, sz in ipairs(R.SIZES) do
			sizeTabs[sz]:ClearAllPoints()
			row[#row + 1] = sizeTabs[sz]
		end
		local function gap(i) return i == firstSize and 18 or 4 end
		for i = #row, 1, -1 do
			local b = row[i]
			if i == #row then b:SetPoint("RIGHT", top, "RIGHT", 0, 0)
			else b:SetPoint("RIGHT", row[i + 1], "LEFT", -gap(i + 1), 0) end
		end
	end

	-- ==== TOON VIEW: a portrait card on the left, the numbers on the page ====
	local toon = CreateFrame("Frame", nil, page)
	toon:SetPoint("TOPLEFT", page, "TOPLEFT")
	toon:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")

	-- the card: the art whole, the class colour along its top, the rank and the
	-- name on its darkened foot
	local card = darkCard(toon)
	card:SetPoint("TOPLEFT"); card:SetPoint("BOTTOMLEFT")
	local cArt = card:CreateTexture(nil, "BORDER")
	cArt:SetPoint("TOPLEFT", 1, -1); cArt:SetPoint("BOTTOMRIGHT", -1, 1)
	-- the rank and name sit on a SOLID foot, never on the art (snow and light
	-- under them made them unreadable); only a short melt joins it to the picture
	local cFoot = fill(card, "ARTWORK", INK[1], INK[2], INK[3], 0.94)
	cFoot:SetPoint("BOTTOMLEFT", 1, 1); cFoot:SetPoint("BOTTOMRIGHT", -1, 1); cFoot:SetHeight(FOOT_H)
	local cMelt = inkFade(card, "VERTICAL", 0.94, 0)
	cMelt:SetPoint("BOTTOMLEFT", cFoot, "TOPLEFT"); cMelt:SetPoint("BOTTOMRIGHT", cFoot, "TOPRIGHT"); cMelt:SetHeight(FOOT_FADE)
	local cBar = fill(card, "ARTWORK", 1, 1, 1, 1)
	cBar:SetHeight(2); cBar:SetPoint("TOPLEFT", 1, -1); cBar:SetPoint("TOPRIGHT", -1, -1)
	local hSpec = W.Text(card, "", "body", "dim"); hSpec:SetPoint("BOTTOMLEFT", 16, 14)
	local hName = W.Text(card, "", NAME_SIZE); hName:SetPoint("BOTTOMLEFT", hSpec, "TOPLEFT", 0, 4)
	local hRank = W.Text(card, "", RANK_SIZE, "accent"); hRank:SetPoint("BOTTOMLEFT", hName, "TOPLEFT", 0, 6)
	local hOf = W.Text(card, "", "head", "dim"); hOf:SetPoint("BOTTOMLEFT", hRank, "BOTTOMRIGHT", 8, 6)
	local hMove = W.Text(card, "", "label"); hMove:SetPoint("LEFT", hOf, "RIGHT", 22, 0)
	hMove:SetJustifyH("LEFT")
	local hBoard = W.Text(card, "", "note", "dim"); hBoard:SetPoint("BOTTOMLEFT", hRank, "TOPLEFT", 0, 4)
	local hNone = W.Text(card, "", "label", "dim"); hNone:SetPoint("BOTTOMLEFT", hName, "TOPLEFT", 0, 8)
	local cardFor = {}
	local function paintCard(name, cls)
		cardFor.name, cardFor.cls = name, cls
		local w, h = card:GetWidth() or 0, card:GetHeight() or 0
		if w < 10 or h < 10 then return end
		setArt(cArt, name, cls, (w - 2) / (h - 2))
	end

	-- the page beside the card
	local info = CreateFrame("Frame", nil, toon)
	info:SetPoint("TOPLEFT", card, "TOPRIGHT", INFO_GAP, 0)
	info:SetPoint("BOTTOMRIGHT", toon, "BOTTOMRIGHT")

	-- your four numbers, one light tile each
	local stat = {}
	for i = 1, 4 do
		local t = CreateFrame("Frame", nil, info)
		t:SetHeight(TILE_H)
		local bg = fill(t, "BACKGROUND", 1, 1, 1, 0.04); bg:SetAllPoints()
		t.k = W.Text(t, "", "note", "dim"); t.k:SetPoint("TOPLEFT", 9, -6)
		t.v = W.Text(t, "", NUM_SIZE); t.v:SetPoint("BOTTOMLEFT", 9, 6)
		stat[i] = t
	end

	-- a section label over a hairline
	local function section(text)
		local f = CreateFrame("Frame", nil, info)
		f:SetHeight(18)
		local rule = fill(f, "BORDER", C.border[1], C.border[2], C.border[3], 1)
		rule:SetHeight(1); rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
		f.label = W.Text(f, text, "note", "dim"); f.label:SetPoint("BOTTOMLEFT", 0, 5)
		return f
	end

	-- who is around you, at the foot of the page: label and "Full board" on one line
	local nearHead = section("AROUND YOU")
	local full = W.Button(nearHead, "Full board >", "tab")
	full:SetSize(92, 18); full:SetPoint("BOTTOMRIGHT", 0, 2)
	full:SetScript("OnClick", function() state.view = "board"; refresh() end)
	local near = {}
	for i = 1, AROUND do
		local r = CreateFrame("Frame", nil, info)
		r:SetHeight(NEAR_H)
		r:SetPoint("BOTTOMLEFT", info, "BOTTOMLEFT", 0, (AROUND - i) * NEAR_H)
		r:SetPoint("RIGHT", info, "RIGHT", 0, 0)
		r.me = fill(r, "BACKGROUND", C.accent[1], C.accent[2], C.accent[3], 0.12); r.me:SetAllPoints()
		r.mark = fill(r, "BORDER", C.accent[1], C.accent[2], C.accent[3], 1); r.mark:SetWidth(2)
		r.mark:SetPoint("TOPLEFT"); r.mark:SetPoint("BOTTOMLEFT")
		r.n = W.Text(r, "", "label", "dim"); r.n:SetPoint("LEFT", 8, 0); r.n:SetWidth(30); r.n:SetJustifyH("LEFT")
		r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 40, 0)
		r.v = W.Text(r, "", "label", "dim"); r.v:SetPoint("RIGHT", -8, 0); r.v:SetJustifyH("RIGHT")
		r.name = W.Text(r, "", "body"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r.name:SetPoint("RIGHT", r.v, "LEFT", -6, 0); r.name:SetJustifyH("LEFT")
		if r.name.SetWordWrap then r.name:SetWordWrap(false) end
		near[i] = r
	end
	nearHead:SetPoint("BOTTOMLEFT", near[1], "TOPLEFT", 0, 4)
	nearHead:SetPoint("RIGHT", info, "RIGHT", 0, 0)

	-- server % per boss, filling the space between the numbers and "around you"
	local bossHead = section("PER BOSS  ·  SERVER %")
	bossHead:SetPoint("TOPLEFT", info, "TOPLEFT", 0, -(CHIP_H + GAP + TILE_H + 10))
	bossHead:SetPoint("RIGHT", info, "RIGHT", 0, 0)
	local bossBox = CreateFrame("Frame", nil, info)
	bossBox:SetPoint("TOPLEFT", bossHead, "BOTTOMLEFT", 0, -6)
	bossBox:SetPoint("BOTTOMRIGHT", nearHead, "TOPRIGHT", 0, 10)
	local bsf, bchild, bsb, brange = scrollList(bossBox, nil, BOSS_STEP)
	bsf:SetPoint("TOPLEFT"); bsf:SetPoint("BOTTOMRIGHT", -10, 0)
	bsb:SetPoint("TOPLEFT", bsf, "TOPRIGHT", 5, 0); bsb:SetPoint("BOTTOMLEFT", bsf, "BOTTOMRIGHT", 5, 0)
	local bossRows = {}
	local function bossAt(i)
		local b = bossRows[i]
		if b then return b end
		b = CreateFrame("Frame", nil, bchild)
		b:SetHeight(16)
		b:SetPoint("TOPLEFT", 0, -(i - 1) * BOSS_STEP); b:SetPoint("RIGHT", bchild, "RIGHT", -2, 0)
		b.name = W.Text(b, "", "body"); b.name:SetPoint("LEFT", 0, 0); b.name:SetWidth(BOSS_NAME_W)
		b.name:SetJustifyH("LEFT")
		if b.name.SetWordWrap then b.name:SetWordWrap(false) end
		b.val = W.Text(b, "", "body"); b.val:SetPoint("RIGHT", 0, 0); b.val:SetWidth(VAL_W); b.val:SetJustifyH("RIGHT")
		if b.val.SetWordWrap then b.val:SetWordWrap(false) end
		b.track = fill(b, "BORDER", 0, 0, 0, 0.45); b.track:SetHeight(4)
		b.track:SetPoint("LEFT", b.name, "RIGHT", 6, 0); b.track:SetPoint("RIGHT", b.val, "LEFT", -8, 0)
		b.bar = fill(b, "ARTWORK", 1, 1, 1, 1); b.bar:SetHeight(4)
		b.bar:SetPoint("LEFT", b.track, "LEFT", 0, 0)
		bossRows[i] = b
		return b
	end

	-- the card takes CARD_SHARE of the width; the tiles share what is left
	local function sizeCard()
		local w = toon:GetWidth() or 0
		if w < 40 then return end
		card:SetWidth(math.floor(w * CARD_SHARE))
		local iw = w - math.floor(w * CARD_SHARE) - INFO_GAP
		local tw = math.floor((iw - 3 * TILE_GAP) / 4)
		for i, t in ipairs(stat) do
			t:ClearAllPoints(); t:SetWidth(tw)
			t:SetPoint("TOPLEFT", info, "TOPLEFT", (i - 1) * (tw + TILE_GAP), -(CHIP_H + GAP))
		end
		if cardFor.name then paintCard(cardFor.name, cardFor.cls) end
	end
	toon:HookScript("OnSizeChanged", sizeCard)
	bsf:HookScript("OnSizeChanged", function() if state.view ~= "board" and refresh then refresh() end end)

	-- ==== BOARD VIEW: one whole board ====
	local boardView = CreateFrame("Frame", nil, page)
	boardView:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -GAP)
	boardView:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")
	local x = 0
	for _, k in ipairs(R.BOARDS) do
		local b = tab(boardView, R.BOARD_LABEL[k], k == "d" and 46 or 68, function() state.kind = k end)
		b:SetPoint("TOPLEFT", boardView, "TOPLEFT", x, 0)
		x = x + b:GetWidth() + 8
		kindTabs[k] = b
	end
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
	local head = CreateFrame("Frame", nil, boardView)
	head:SetHeight(18); head:SetPoint("TOPLEFT", 0, -30); head:SetPoint("TOPRIGHT", -8, -30)
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
	local sf, child, sb, range = scrollList(boardView, sizeBars)
	sf:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2); sf:SetPoint("BOTTOMRIGHT", -8, 0)
	sb:SetPoint("TOPRIGHT", boardView, "TOPRIGHT", -1, -50); sb:SetPoint("BOTTOMRIGHT", -1, 0)
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
		r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(20, 20); r.icon:SetPoint("LEFT", 32, 0)
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

	-- ---- the toon shown: your main (alts would crowd the page), else this toon ----
	local function pickToon()
		local me = UnitName("player")
		local main = Okanvil.U and Okanvil.U.mainOf and Okanvil.U.mainOf(me)
		state.toon = (main and R.Has(main)) and main or me
	end

	-- ---- paint: the toon view ----
	local function paintToon()
		local name = state.toon or UnitName("player")
		local p, rank, of, kind, size = mainBoard(name, state.size, state.period)
		size = size or state.size
		local cls, spec = classOf(name)
		local cr, cg, cb = classRGB(cls)
		sizeCard()
		paintCard(name, cls)
		cBar:SetVertexColor(cr, cg, cb, 0.9)
		hName:SetText(name); hName:SetTextColor(cr, cg, cb)
		hSpec:SetText(spec and spec ~= "" and spec or "")

		if p then
			hNone:Hide(); hBoard:Show(); hRank:Show(); hOf:Show(); hMove:Show()
			hBoard:SetText(("%s  ·  %s-MAN  ·  %s"):format(R.BOARD_LABEL[kind]:upper(), size,
				(R.PERIOD_LABEL[state.period] or ""):upper()))
			hRank:SetText("#" .. rank)
			hOf:SetText("of " .. of)
			paintMove(hMove, R.Move(size, kind, p.key, rank, state.period))
			local vals = {
				{ R.BOARD_UNIT[kind], fmtRate(p.rate, kind) },
				{ "PTS", ("|cffffd25a%.1f|r"):format(p.pts) },
				{ "SERVER", pctText(p.srv) },
				{ "FIGHTS", tostring(p.fights) .. (p.hc and "  |cffff8000H|r" or "") },
			}
			for i, v in ipairs(vals) do stat[i].k:SetText(v[1]); stat[i].v:SetText(v[2]) end
		else
			hBoard:Hide(); hRank:Hide(); hOf:Hide(); paintMove(hMove, nil); hMove:Hide()
			hNone:Show(); hNone:SetText("Not on a board " .. (state.period == "week" and "this week" or "yet"))
			for i = 1, 4 do stat[i].k:SetText(""); stat[i].v:SetText("") end
			stat[1].k:SetText("NO BOARD"); stat[1].v:SetText("|cff6f7176--|r")
		end

		-- every boss of the raid, in order; the ones this toon has no parse on
		-- dimmed. G = our own parse, for a boss the server does not rank.
		local d = R.Data()
		local byIdx = {}
		for _, c in ipairs(R.Parses(size, name) or {}) do if c.i then byIdx[c.i] = c end end
		local n = 0
		for i, boss in ipairs(d and d.bosses or {}) do
			n = n + 1
			local b, c = bossAt(n), byIdx[i - 1]
			b.name:SetText(R.ShortBoss(boss) .. (c and c.hc and " |cffff8000H|r" or "")
				.. (c and c.guild and " |cff8a8d93G|r" or ""))
			if c then
				local r, g, bl = R.PctColor(c.pct)
				b.name:SetTextColor(C.text[1], C.text[2], C.text[3])
				b.val:SetText(("%d"):format(math.floor(c.pct))); b.val:SetTextColor(r, g, bl)
				b.bar:SetVertexColor(r, g, bl, 1)
				local tw = math.max(10, (bsf:GetWidth() or 200) - BOSS_NAME_W - 6 - VAL_W - 8)
				b.bar:SetWidth(math.max(2, tw * math.min(c.pct, 100) / 100)); b.bar:Show()
			else
				b.name:SetTextColor(0.45, 0.46, 0.50)
				b.val:SetText("no parse"); b.val:SetTextColor(0.45, 0.46, 0.50)
				b.bar:Hide()
			end
			b:Show()
		end
		for i = n + 1, #bossRows do bossRows[i]:Hide() end
		-- spread the rows over the height there is, so no gap opens under the list
		local room = bsf:GetHeight() or 0
		local step = BOSS_STEP
		if n > 0 and room > 0 then step = math.max(BOSS_STEP, math.min(BOSS_STEP_MAX, math.floor(room / n))) end
		for i = 1, n do
			bossRows[i]:ClearAllPoints()
			bossRows[i]:SetPoint("TOPLEFT", 0, -(i - 1) * step); bossRows[i]:SetPoint("RIGHT", bchild, "RIGHT", -2, 0)
		end
		bchild:SetHeight(math.max(1, n * step))
		brange()

		-- the one above you, you, and the two below, on your main board
		local list = p and R.Board(size, kind, state.period) or {}
		local from = rank and math.max(1, math.min(rank - 1, #list - AROUND + 1)) or 1
		for i, r in ipairs(near) do
			local at = from + i - 1
			local q = p and list[at]
			if q then
				local qr, qg, qb = classRGB(q.class)
				r.n:SetText("#" .. at)
				classIcon(r.icon, q.class)
				r.name:SetText(q.name); r.name:SetTextColor(qr, qg, qb)
				r.v:SetText(fmtRate(q.rate, kind))
				if at == rank then
					r.me:Show(); r.mark:Show(); r.n:SetTextColor(C.accentHi[1], C.accentHi[2], C.accentHi[3])
				else
					r.me:Hide(); r.mark:Hide(); r.n:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
				end
				r:Show()
			else
				r:Hide()
			end
		end
		if p then nearHead:Show() else nearHead:Hide() end
	end

	-- ---- paint: the whole board ----
	local function paintBoard()
		for k, b in pairs(kindTabs) do b:SetKind(k == state.kind and "tabOn" or "tab") end
		local list = R.Board(state.size, state.kind, state.period) or {}
		head.rate:SetText(R.BOARD_UNIT[state.kind])
		local me = R.Norm(state.toon or UnitName("player"))
		for i, p in ipairs(list) do
			local r = rowAt(i)
			local cr, cg, cb = classRGB(p.class)
			r.tint:SetGradientAlpha("HORIZONTAL", cr, cg, cb, 0.16, cr, cg, cb, 0)
			r.ptsBar:SetVertexColor(cr, cg, cb, 0.35)
			r._pts = p.pts
			r.n:SetText(i)
			classIcon(r.icon, p.class)
			-- H = their best came from Heroic
			r.name:SetText(p.name .. (p.hc and "  |cffff8000H|r" or "")); r.name:SetTextColor(cr, cg, cb)
			paintMove(r.move, R.Move(state.size, state.kind, p.key, i, state.period))
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
			if p.key == me then r.me:Show() else r.me:Hide() end
			r:Show()
		end
		for i = #list + 1, #rows do rows[i]:Hide() end
		if #list == 0 then head:Hide() else head:Show() end
		child:SetHeight(math.max(1, #list * ROW_H))
		range()
	end

	refresh = function()
		for sz, b in pairs(sizeTabs) do b:SetKind(sz == state.size and "tabOn" or "tab") end
		dash:Refresh()
		if not R.Data() then
			top:Hide(); toon:Hide(); boardView:Hide()
			empty:SetText(isOfficer()
				and "No ranking yet. On the RATS site open Rankings, press Export to Okanvil, then Import it here. Everyone in the guild online gets it."
				or "No ranking yet. It arrives by itself once an officer imports it, or from any guild member who has it.")
			empty:Show()
			return
		end
		empty:Hide(); top:Show()
		if not (state.period and R.HasPeriod(state.period)) then state.period = R.DefaultPeriod() end
		layoutTabs()
		top:ClearAllPoints()
		if state.view == "board" then
			top:SetPoint("TOPLEFT", page, "TOPLEFT"); top:SetPoint("TOPRIGHT", page, "TOPRIGHT")
			back:Show(); toon:Hide(); boardView:Show()
			paintBoard()
		else
			top:SetPoint("TOPLEFT", info, "TOPLEFT"); top:SetPoint("TOPRIGHT", info, "TOPRIGHT")
			back:Hide(); boardView:Hide(); toon:Show()
			pickToon()
			paintToon()
		end
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
	desc  = "Your main on the guild's DPS / Healing / Tanking boards from the RATS site, plus each "
		.. "raider's best bosses on their tooltip. An officer imports it; everyone online gets it.",
	icon  = Okanvil.ICONS and Okanvil.ICONS.ranking,
	build = function(panel) Okanvil:BuildRanking(panel) end,
}
if Okanvil and Okanvil.Register then
	Okanvil:Register(ADDON)
end
