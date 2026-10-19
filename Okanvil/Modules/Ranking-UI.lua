-- ============================================================
-- Okanvil -- Ranking page (GUILD > Ranking).
-- One toon at a time: your rank on its main board, its numbers, its server %
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
local PAD, GAP = 12, 8
local CHIP_H, HERO_H, STAT_H = 24, 170, 44
local ART_FADE = 90              -- the art's left edge melting into the card
local ROW_H, AROUND_H, BOSS_STEP = 26, 24, 20
local AROUND = 2                 -- players shown above and below you
local INK = { 0.035, 0.037, 0.043 }   -- the near-black the cards sit on
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
-- height and the right a/2 of the width when a < 2, or the full width and a
-- band 2/a tall around the head when a > 2 (a banner).
local function setArt(tex, name, token, aspect)
	if not (name and tex:SetTexture(ART_RAIDER .. R.Norm(name))) then
		if not tex:SetTexture(ART_CLASS .. (token or ""):lower()) then tex:SetTexture(nil); return end
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

-- a hairline inside a card, between two of its cells
local function vline(parent, x)
	local t = fill(parent, "BORDER", C.border[1], C.border[2], C.border[3], 1)
	t:SetWidth(1)
	t:SetPoint("TOP", parent, "TOPLEFT", x, -1)
	t:SetPoint("BOTTOM", parent, "BOTTOMLEFT", x, 1)
	return t
end

-- a row of equal cells across a card, each a dim label over a value
local function cellRow(parent, n)
	local cells, lines = {}, {}
	for i = 1, n do
		local c = CreateFrame("Frame", nil, parent)
		c.k = W.Text(c, "", "note", "dim"); c.k:SetPoint("TOPLEFT", 10, -7)
		c.v = W.Text(c, "", "head"); c.v:SetPoint("TOPLEFT", c.k, "BOTTOMLEFT", 0, -3)
		cells[i] = c
		if i > 1 then lines[i] = vline(parent, 0) end
	end
	local function layout()
		local w = (parent:GetWidth() or 0) - 2
		if w < 40 then return end
		local x = 1
		for i, c in ipairs(cells) do
			local cw = math.floor(w / n)
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -1)
			c:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 1)
			c:SetWidth(cw)
			if lines[i] then
				lines[i]:ClearAllPoints()
				lines[i]:SetPoint("TOP", parent, "TOPLEFT", x, -1)
				lines[i]:SetPoint("BOTTOM", parent, "BOTTOMLEFT", x, 1)
			end
			x = x + cw
		end
	end
	parent:HookScript("OnSizeChanged", layout)
	return cells, layout
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
	if name == UnitName("player") then return (select(2, UnitClass("player"))) end
	for _, s in ipairs(R.SIZES) do
		for _, pd in ipairs(R.PERIODS) do
			for _, k in ipairs(R.BOARDS) do
				local p = R.Find(s, k, name, pd, true)
				if p then return p.class, p.spec end
			end
		end
	end
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
		subtitle = "Your toons on the guild's boards from the RATS site",
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

	-- ---- top line: your toons (or "< My toon" on the board), then size and period ----
	local top = CreateFrame("Frame", nil, page)
	top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(CHIP_H)
	local chips = {}
	local function chipAt(i)
		local c = chips[i]
		if c then return c end
		c = W.Button(top, "", "tab")
		c:SetHeight(CHIP_H)
		c.dot = fill(c, "OVERLAY", 1, 1, 1, 1); c.dot:SetSize(7, 7); c.dot:SetPoint("LEFT", 8, 0)
		c:SetScript("OnClick", function() state.toon = c._name; refresh() end)
		chips[i] = c
		return c
	end
	local back = W.Button(top, "< My toon", "tab")
	back:SetSize(84, CHIP_H); back:SetPoint("LEFT", 0, 0)
	back:SetScript("OnClick", function() state.view = "toon"; refresh() end)

	local prevTab
	for i = #R.SIZES, 1, -1 do
		local sz = R.SIZES[i]
		local b = tab(top, sz .. "-man", 58, function() state.size = sz end)
		if prevTab then b:SetPoint("RIGHT", prevTab, "LEFT", -4, 0)
		else b:SetPoint("RIGHT", top, "RIGHT", 0, 0) end
		sizeTabs[sz] = b
		prevTab = b
	end
	for i = #R.PERIODS, 1, -1 do
		local pd = R.PERIODS[i]
		periodTabs[pd] = tab(top, R.PERIOD_LABEL[pd], pd == "all" and 62 or 74, function() state.period = pd end)
	end

	-- ==== TOON VIEW ====
	local toon = CreateFrame("Frame", nil, page)
	toon:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -GAP)
	toon:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")

	-- the hero: the whole picture on the right at its own 2:1 shape, in full
	-- colour; the rank and the name on the dark to its left
	local hero = darkCard(toon)
	hero:SetPoint("TOPLEFT"); hero:SetPoint("TOPRIGHT"); hero:SetHeight(HERO_H)
	local hArt = hero:CreateTexture(nil, "BORDER")
	hArt:SetPoint("TOPRIGHT", -1, -1); hArt:SetPoint("BOTTOMRIGHT", -1, 1)
	local hFade = inkFade(hero, "HORIZONTAL", 1, 0)
	hFade:SetPoint("TOPLEFT", hArt, "TOPLEFT"); hFade:SetPoint("BOTTOMLEFT", hArt, "BOTTOMLEFT")
	hFade:SetWidth(ART_FADE)
	local hBar = fill(hero, "ARTWORK", 1, 1, 1, 1)
	hBar:SetHeight(2); hBar:SetPoint("TOPLEFT", 1, -1); hBar:SetPoint("TOPRIGHT", -1, -1)
	local hBoard = W.Text(hero, "", "note", "dim"); hBoard:SetPoint("TOPLEFT", 18, -18)
	local hRank = W.Text(hero, "", "huge", "accent"); hRank:SetPoint("TOPLEFT", hBoard, "BOTTOMLEFT", 0, -8)
	local hOf = W.Text(hero, "", "label", "dim"); hOf:SetPoint("BOTTOMLEFT", hRank, "BOTTOMRIGHT", 8, 3)
	local hMove = W.Text(hero, "", "label"); hMove:SetPoint("LEFT", hOf, "RIGHT", 22, 0)
	hMove:SetJustifyH("LEFT")
	local hIcon = hero:CreateTexture(nil, "OVERLAY"); hIcon:SetSize(22, 22)
	hIcon:SetPoint("BOTTOMLEFT", 18, 40)
	local hName = W.Text(hero, "", "huge"); hName:SetPoint("LEFT", hIcon, "RIGHT", 8, 0)
	local hSpec = W.Text(hero, "", "label", "dim"); hSpec:SetPoint("TOPLEFT", hIcon, "BOTTOMLEFT", 0, -6)
	local hNone = W.Text(hero, "", "label", "dim"); hNone:SetPoint("TOPLEFT", 18, -18)
	-- the art keeps its 2:1 shape; a card narrower than that cuts its left side
	local function artWidth()
		return math.min((hero:GetWidth() or 0) - 2, (HERO_H - 2) * 2)
	end
	hero:HookScript("OnSizeChanged", function()
		local w = artWidth()
		if w < 10 then return end
		hArt:SetWidth(w)
		if hero._name then setArt(hArt, hero._name, hero._class, w / (HERO_H - 2)) end
	end)

	-- your four numbers on the main board
	local stats = darkCard(toon)
	stats:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -GAP); stats:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, -GAP)
	stats:SetHeight(STAT_H)
	local statCells, statLayout = cellRow(stats, 4)

	-- left: server % per boss, in the raid's order
	local bossCard = darkCard(toon)
	bossCard:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -GAP)
	bossCard:SetPoint("BOTTOM", toon, "BOTTOM", 0, 0)
	local bossHead = W.Text(bossCard, "PER BOSS  |cff6f7176SERVER %|r", "note", "dim")
	bossHead:SetPoint("TOPLEFT", 10, -8)
	local bsf, bchild, bsb, brange = scrollList(bossCard, nil, BOSS_STEP)
	bsf:SetPoint("TOPLEFT", 10, -26); bsf:SetPoint("BOTTOMRIGHT", -14, 8)
	bsb:SetPoint("TOPLEFT", bsf, "TOPRIGHT", 5, 0); bsb:SetPoint("BOTTOMLEFT", bsf, "BOTTOMRIGHT", 5, 0)
	local bossRows = {}
	local function bossAt(i)
		local b = bossRows[i]
		if b then return b end
		b = CreateFrame("Frame", nil, bchild)
		b:SetHeight(16)
		b:SetPoint("TOPLEFT", 0, -(i - 1) * BOSS_STEP); b:SetPoint("RIGHT", bchild, "RIGHT", -2, 0)
		b.name = W.Text(b, "", "note"); b.name:SetPoint("LEFT", 0, 0); b.name:SetWidth(96)
		b.name:SetJustifyH("LEFT")
		if b.name.SetWordWrap then b.name:SetWordWrap(false) end
		b.val = W.Text(b, "", "note"); b.val:SetPoint("RIGHT", 0, 0); b.val:SetWidth(44); b.val:SetJustifyH("RIGHT")
		b.track = fill(b, "BACKGROUND", 0, 0, 0, 0.45); b.track:SetHeight(5)
		b.track:SetPoint("LEFT", b.name, "RIGHT", 6, 0); b.track:SetPoint("RIGHT", b.val, "LEFT", -6, 0)
		b.bar = fill(b, "ARTWORK", 1, 1, 1, 1); b.bar:SetHeight(5)
		b.bar:SetPoint("LEFT", b.track, "LEFT", 0, 0)
		bossRows[i] = b
		return b
	end

	-- right: the players around you, your rank on each board, the whole board
	local nearCard = darkCard(toon)
	nearCard:SetPoint("TOPLEFT", bossCard, "TOPRIGHT", GAP, 0)
	nearCard:SetPoint("BOTTOMRIGHT", toon, "BOTTOMRIGHT", 0, 0)
	local function splitCols()
		local w = toon:GetWidth() or 0
		if w > 40 then bossCard:SetWidth(math.floor((w - GAP) * 0.55)) end
	end
	toon:HookScript("OnSizeChanged", splitCols)
	local nearHead = W.Text(nearCard, "AROUND YOU", "note", "dim"); nearHead:SetPoint("TOPLEFT", 10, -8)
	local full = W.Button(nearCard, "Full board >", "tab")
	full:SetSize(92, 20); full:SetPoint("TOPRIGHT", -6, -4)
	full:SetScript("OnClick", function() state.view = "board"; refresh() end)
	local near = {}
	for i = 1, AROUND * 2 + 1 do
		local r = CreateFrame("Frame", nil, nearCard)
		r:SetHeight(AROUND_H)
		r:SetPoint("TOPLEFT", 1, -26 - (i - 1) * AROUND_H); r:SetPoint("RIGHT", nearCard, "RIGHT", -1, 0)
		r.me = fill(r, "BACKGROUND", C.accent[1], C.accent[2], C.accent[3], 0.14); r.me:SetAllPoints()
		r.mark = fill(r, "BORDER", C.accent[1], C.accent[2], C.accent[3], 1); r.mark:SetWidth(2)
		r.mark:SetPoint("TOPLEFT"); r.mark:SetPoint("BOTTOMLEFT")
		r.n = W.Text(r, "", "label", "dim"); r.n:SetPoint("LEFT", 10, 0); r.n:SetWidth(30); r.n:SetJustifyH("LEFT")
		r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 42, 0)
		r.v = W.Text(r, "", "label", "dim"); r.v:SetPoint("RIGHT", -10, 0); r.v:SetJustifyH("RIGHT")
		r.name = W.Text(r, "", "label"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r.name:SetPoint("RIGHT", r.v, "LEFT", -6, 0); r.name:SetJustifyH("LEFT")
		if r.name.SetWordWrap then r.name:SetWordWrap(false) end
		near[i] = r
	end
	local boards = CreateFrame("Frame", nil, nearCard)
	boards:SetPoint("BOTTOMLEFT", 0, 0); boards:SetPoint("BOTTOMRIGHT", 0, 0); boards:SetHeight(44)
	local bRule = fill(boards, "BORDER", C.border[1], C.border[2], C.border[3], 1)
	bRule:SetHeight(1); bRule:SetPoint("TOPLEFT", 1, 0); bRule:SetPoint("TOPRIGHT", -1, 0)
	local boardCells, boardLayout = cellRow(boards, 3)
	local nearNone = W.Text(nearCard, "", "label", "dim"); nearNone:SetPoint("TOPLEFT", 10, -32)

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

	-- ---- paint: the toon chips ----
	local function paintChips()
		local mine = Okanvil.U and Okanvil.U.toonsOf and Okanvil.U.toonsOf(UnitName("player")) or { UnitName("player") }
		local list = {}
		for _, n in ipairs(mine) do
			if n == UnitName("player") or R.Has(n) then list[#list + 1] = n end
		end
		local ok = false
		for _, n in ipairs(list) do if n == state.toon then ok = true end end
		if not ok then state.toon = UnitName("player") end
		local xx = 0
		for i, n in ipairs(list) do
			local c = chipAt(i)
			c._name = n
			local cls, spec = classOf(n)
			local r, g, b = classRGB(cls)
			c.dot:SetVertexColor(r, g, b, cls and 1 or 0.3)
			c.text:SetText("   " .. n .. (spec and spec ~= "" and ("  |cff8a8d93" .. spec .. "|r") or ""))
			local w = (c.text and c.text:GetStringWidth() or 60) + 18
			c:SetWidth(math.max(70, w))
			c:SetKind(n == state.toon and "tabOn" or "tab")
			c:ClearAllPoints(); c:SetPoint("LEFT", top, "LEFT", xx, 0)
			xx = xx + c:GetWidth() + 6
			c:Show()
		end
		for i = #list + 1, #chips do chips[i]:Hide() end
		-- one toon alone needs no picker
		if #list < 2 then for _, c in ipairs(chips) do c:Hide() end end
	end

	-- ---- paint: the toon view ----
	local function paintToon()
		local name = state.toon or UnitName("player")
		local p, rank, of, kind, size = mainBoard(name, state.size, state.period)
		size = size or state.size
		local cls, spec = classOf(name)
		local cr, cg, cb = classRGB(cls)
		hero._name, hero._class = name, cls
		local aw = artWidth()
		if aw < 10 then aw = (HERO_H - 2) * 2 end
		hArt:SetWidth(aw)
		setArt(hArt, name, cls, aw / (HERO_H - 2))
		classIcon(hIcon, cls)
		hBar:SetVertexColor(cr, cg, cb, 0.9)
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
				{ "PTS", ("|cffe0b860%.1f|r"):format(p.pts) },
				{ "SERVER", pctText(p.srv) },
				{ "FIGHTS", tostring(p.fights) .. (p.hc and "  |cffff8000H|r" or "") },
			}
			for i, v in ipairs(vals) do statCells[i].k:SetText(v[1]); statCells[i].v:SetText(v[2]) end
		else
			hBoard:Hide(); hRank:Hide(); hOf:Hide(); paintMove(hMove, nil); hMove:Hide()
			hNone:Show(); hNone:SetText("Not on a board " .. (state.period == "week" and "this week" or "yet"))
			for i = 1, 4 do statCells[i].k:SetText(""); statCells[i].v:SetText("") end
			statCells[1].k:SetText("NO BOARD"); statCells[1].v:SetText("|cff6f7176--|r")
		end
		statLayout()

		-- every boss of the raid, in order; the ones with no parse dimmed
		local d = R.Data()
		local byIdx = {}
		for _, c in ipairs(R.Parses(size, name) or {}) do if c.i then byIdx[c.i] = c end end
		local n = 0
		for i, boss in ipairs(d and d.bosses or {}) do
			n = n + 1
			local b, c = bossAt(n), byIdx[i - 1]
			b.name:SetText(R.ShortBoss(boss) .. (c and c.hc and " |cffff8000H|r" or ""))
			if c then
				local r, g, bl = R.PctColor(c.pct)
				b.name:SetTextColor(0.80, 0.81, 0.83)
				b.val:SetText(("%d"):format(math.floor(c.pct))); b.val:SetTextColor(r, g, bl)
				b.bar:SetVertexColor(r, g, bl, 1)
				local tw = math.max(10, (bsf:GetWidth() or 200) - 96 - 6 - 44 - 8)
				b.bar:SetWidth(math.max(2, tw * math.min(c.pct, 100) / 100)); b.bar:Show()
			else
				b.name:SetTextColor(0.37, 0.38, 0.41)
				b.val:SetText("no kill"); b.val:SetTextColor(0.37, 0.38, 0.41)
				b.bar:Hide()
			end
			b:Show()
		end
		for i = n + 1, #bossRows do bossRows[i]:Hide() end
		bchild:SetHeight(math.max(1, n * BOSS_STEP))
		brange()

		-- the players around you on your main board
		local list = p and R.Board(size, kind, state.period) or {}
		local from = rank and math.max(1, math.min(rank - AROUND, #list - AROUND * 2)) or 1
		for i, r in ipairs(near) do
			local q = p and list[from + i - 1]
			if q then
				local qr, qg, qb = classRGB(q.class)
				local isMe = (from + i - 1) == rank
				r.n:SetText("#" .. (from + i - 1))
				classIcon(r.icon, q.class)
				r.name:SetText(q.name); r.name:SetTextColor(qr, qg, qb)
				r.v:SetText(fmtRate(q.rate, kind))
				if isMe then r.me:Show(); r.mark:Show(); r.n:SetTextColor(C.accentHi[1], C.accentHi[2], C.accentHi[3])
				else r.me:Hide(); r.mark:Hide(); r.n:SetTextColor(0.54, 0.55, 0.58) end
				r:Show()
			else
				r:Hide()
			end
		end
		if p then nearNone:Hide() else nearNone:Show(); nearNone:SetText("Not on a board.") end

		for i, k in ipairs(R.BOARDS) do
			local c = boardCells[i]
			local q, qr, qo = R.Find(size, k, name, state.period, true)
			c.k:SetText(R.BOARD_LABEL[k]:upper())
			c.v:SetText(q and ("#" .. qr .. " |cff8a8d93/ " .. qo .. "|r") or "|cff6f7176not ranked|r")
		end
		boardLayout()
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
		splitCols()
		if state.view == "board" then
			for _, c in ipairs(chips) do c:Hide() end
			back:Show(); toon:Hide(); boardView:Show()
			paintBoard()
		else
			back:Hide(); boardView:Hide(); toon:Show()
			paintChips()
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
	desc  = "Your toons on the guild's DPS / Healing / Tanking boards from the RATS site, plus each "
		.. "raider's best bosses on their tooltip. An officer imports it; everyone online gets it.",
	icon  = Okanvil.ICONS and Okanvil.ICONS.ranking,
	build = function(panel) Okanvil:BuildRanking(panel) end,
}
if Okanvil and Okanvil.Register then
	Okanvil:Register(ADDON)
end
