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
local PAD, GAP = 12, 8
local CHIP_H, ROW_H, AROUND_H, BOSS_STEP = 24, 26, 28, 19
local AROUND = 4                 -- the one above you, you, and two below
local RANK_SIZE, NAME_SIZE, NUM_SIZE = 46, 32, 18
local NUM_W, BOSS_NAME_W, VAL_W = 96, 110, 64
local INK = { 0.035, 0.037, 0.043 }   -- the panel's near-black
local SPLIT, MELT_W = 0.44, 110    -- the panel's share of the page; where panel melts into art
local BAND_H = PAD + AROUND_H + 8  -- the solid band at the foot, under the art
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

	-- A poster: a solid panel on the left holds everything you read; the
	-- raider's art fills the right above the foot band, nothing on top of it,
	-- with a short melt where the two meet.
	local ground = fill(host, "BACKGROUND", INK[1], INK[2], INK[3], 1)
	ground:SetAllPoints(host)
	local art = host:CreateTexture(nil, "BORDER")
	art:SetPoint("TOPRIGHT"); art:SetPoint("BOTTOMRIGHT", 0, BAND_H)
	local melt = host:CreateTexture(nil, "ARTWORK"); melt:SetTexture(FLAT)
	melt:SetGradientAlpha("HORIZONTAL", INK[1], INK[2], INK[3], 1, INK[1], INK[2], INK[3], 0)
	melt:SetPoint("TOPLEFT", art, "TOPLEFT"); melt:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT")
	melt:SetWidth(MELT_W)
	local function split() return math.floor((host:GetWidth() or 0) * SPLIT) end
	local artFor = {}
	local function paintArt(name, cls)
		artFor.name, artFor.cls = name, cls
		local w, h = host:GetWidth() or 0, host:GetHeight() or 0
		if w < 10 or h < BAND_H + 10 then return end
		local aw = w - split()
		art:SetWidth(aw)
		setArt(art, name, cls, aw / (h - BAND_H))
	end
	host:HookScript("OnSizeChanged", function()
		if artFor.name then paintArt(artFor.name, artFor.cls) end
	end)

	local page = CreateFrame("Frame", nil, dash.main)
	page:SetPoint("TOPLEFT", PAD, -PAD)
	page:SetPoint("BOTTOMRIGHT", -PAD, PAD)

	-- ---- top line: "< My toon" on the board, then size and period ----
	local top = CreateFrame("Frame", nil, page)
	top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(CHIP_H)
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

	-- ==== TOON VIEW: the panel on the left ====
	local toon = CreateFrame("Frame", nil, page)
	toon:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -GAP)
	toon:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")

	local hBoard = W.Text(toon, "", "note", "dim"); hBoard:SetPoint("TOPLEFT", 0, -6)
	local hRank = W.Text(toon, "", RANK_SIZE, "accent"); hRank:SetPoint("TOPLEFT", hBoard, "BOTTOMLEFT", 0, -4)
	local hOf = W.Text(toon, "", "head", "dim"); hOf:SetPoint("BOTTOMLEFT", hRank, "BOTTOMRIGHT", 8, 6)
	local hMove = W.Text(toon, "", "label"); hMove:SetPoint("LEFT", hOf, "RIGHT", 22, 0)
	hMove:SetJustifyH("LEFT")
	local hName = W.Text(toon, "", NAME_SIZE); hName:SetPoint("TOPLEFT", hRank, "BOTTOMLEFT", 0, -10)
	local hSpec = W.Text(toon, "", "body", "dim"); hSpec:SetPoint("TOPLEFT", hName, "BOTTOMLEFT", 0, -4)
	local hNone = W.Text(toon, "", "label", "dim"); hNone:SetPoint("TOPLEFT", 0, -6)

	-- your four numbers on the main board, under a hairline
	local nums = CreateFrame("Frame", nil, toon)
	nums:SetPoint("TOPLEFT", hSpec, "BOTTOMLEFT", 0, -12); nums:SetHeight(40)
	local nRule = fill(nums, "ARTWORK", 1, 1, 1, 0.16)
	nRule:SetHeight(1); nRule:SetPoint("TOPLEFT"); nRule:SetPoint("TOPRIGHT")
	local stat = {}
	for i = 1, 4 do
		local k = W.Text(nums, "", "note", "dim")
		k:SetPoint("TOPLEFT", (i - 1) * NUM_W, -7)
		local v = W.Text(nums, "", NUM_SIZE)
		v:SetPoint("TOPLEFT", k, "BOTTOMLEFT", 0, -2)
		stat[i] = { k = k, v = v }
	end

	-- who is around you, one line across the foot of the page
	local around = CreateFrame("Frame", nil, toon)
	around:SetPoint("BOTTOMLEFT"); around:SetPoint("BOTTOMRIGHT"); around:SetHeight(AROUND_H)
	local aRule = fill(around, "ARTWORK", 1, 1, 1, 0.16)
	aRule:SetHeight(1); aRule:SetPoint("TOPLEFT"); aRule:SetPoint("TOPRIGHT")
	local aLbl = W.Text(around, "", "note", "dim"); aLbl:SetText("AROUND YOU"); aLbl:SetPoint("LEFT", 0, -2)
	local full = W.Button(around, "Full board >", "tab")
	full:SetSize(92, 20); full:SetPoint("RIGHT", 0, -2)
	full:SetScript("OnClick", function() state.view = "board"; refresh() end)
	local near = {}
	for i = 1, AROUND do
		local t = W.Text(around, "", "label")
		if i == 1 then t:SetPoint("LEFT", aLbl, "RIGHT", 16, 0) else t:SetPoint("LEFT", near[i - 1], "RIGHT", 18, 0) end
		near[i] = t
	end

	-- server % per boss
	local bossBox = CreateFrame("Frame", nil, toon)
	bossBox:SetPoint("TOPLEFT", nums, "BOTTOMLEFT", -14, -10)
	bossBox:SetPoint("BOTTOM", around, "TOP", 0, 10)
	local bsf, bchild, bsb, brange = scrollList(bossBox, nil, BOSS_STEP)
	bsf:SetPoint("TOPLEFT", 14, -10); bsf:SetPoint("BOTTOMRIGHT", -24, 10)
	bsb:SetPoint("TOPLEFT", bsf, "TOPRIGHT", 6, 0); bsb:SetPoint("BOTTOMLEFT", bsf, "BOTTOMRIGHT", 6, 0)
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
		b.track = fill(b, "BORDER", 0, 0, 0, 0.5); b.track:SetHeight(4)
		b.track:SetPoint("LEFT", b.name, "RIGHT", 6, 0); b.track:SetPoint("RIGHT", b.val, "LEFT", -8, 0)
		b.bar = fill(b, "ARTWORK", 1, 1, 1, 1); b.bar:SetHeight(4)
		b.bar:SetPoint("LEFT", b.track, "LEFT", 0, 0)
		bossRows[i] = b
		return b
	end

	-- the left column fills the panel; the filters above it share its width
	local function sizeLeft()
		local lw = split() - PAD - 24
		if lw < 40 then return end
		nums:SetWidth(lw)
		bossBox:SetWidth(lw + 14 + 10)
		if state.view ~= "board" then
			top:ClearAllPoints(); top:SetPoint("TOPLEFT"); top:SetWidth(lw)
		end
	end
	toon:HookScript("OnSizeChanged", sizeLeft)

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
		paintArt(name, cls)
		hName:SetText(name); hName:SetTextColor(cr, cg, cb)
		hSpec:SetText(spec and spec ~= "" and spec or "")
		sizeLeft()

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
			nums:Show()
		else
			hBoard:Hide(); hRank:Hide(); hOf:Hide(); paintMove(hMove, nil); hMove:Hide()
			hNone:Show(); hNone:SetText("Not on a board " .. (state.period == "week" and "this week" or "yet"))
			nums:Hide()
		end
		-- with no rank line, the name moves up to where it was
		hName:ClearAllPoints()
		if p then hName:SetPoint("TOPLEFT", hRank, "BOTTOMLEFT", 0, -10)
		else hName:SetPoint("TOPLEFT", hNone, "BOTTOMLEFT", 0, -10) end
		bossBox:ClearAllPoints()
		bossBox:SetPoint("TOPLEFT", p and nums or hSpec, "BOTTOMLEFT", -14, -10)
		bossBox:SetPoint("BOTTOM", around, "TOP", 0, 10)
		sizeLeft()

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
				.. (c and c.guild and " |cffb4b6bbG|r" or ""))
			if c then
				local r, g, bl = R.PctColor(c.pct)
				b.name:SetTextColor(0.95, 0.95, 0.96)
				b.val:SetText(("%d"):format(math.floor(c.pct))); b.val:SetTextColor(r, g, bl)
				b.bar:SetVertexColor(r, g, bl, 1)
				local tw = math.max(10, (bsf:GetWidth() or 200) - BOSS_NAME_W - 6 - VAL_W - 8)
				b.bar:SetWidth(math.max(2, tw * math.min(c.pct, 100) / 100)); b.bar:Show()
			else
				b.name:SetTextColor(0.55, 0.56, 0.60)
				b.val:SetText("no parse"); b.val:SetTextColor(0.55, 0.56, 0.60)
				b.bar:Hide()
			end
			b:Show()
		end
		for i = n + 1, #bossRows do bossRows[i]:Hide() end
		bchild:SetHeight(math.max(1, n * BOSS_STEP))
		brange()

		-- the one above you, you, and the two below, on your main board
		local list = p and R.Board(size, kind, state.period) or {}
		local from = rank and math.max(1, math.min(rank - 1, #list - AROUND + 1)) or 1
		for i, t in ipairs(near) do
			local at = from + i - 1
			local q = p and list[at]
			if q then
				local hex = at == rank and "ffffd25a" or hexOf(classRGB(q.class))
				t:SetText(("|cffb4b6bb#%d|r  |c%s%s|r  %s"):format(at, hex, q.name, fmtRate(q.rate, kind)))
				t:Show()
			else
				t:Hide()
			end
		end
		if p then around:Show() else around:Hide() end
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
		if state.view == "board" then
			back:Show(); toon:Hide(); boardView:Show(); art:Hide(); melt:Hide()
			top:ClearAllPoints(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
			paintBoard()
		else
			back:Hide(); boardView:Hide(); toon:Show(); art:Show(); melt:Show()
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
