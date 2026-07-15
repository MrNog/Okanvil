-- ============================================================
-- Okanvil -- UI: Invite page
-- Split out of the old monolithic Core/UI.lua. Loads after Core/UI/Shell.lua,
-- which publishes the shared helpers on Okanvil.UI (see that file).
-- ============================================================

local Okanvil = Okanvil
local W   = Okanvil.W
local C   = Okanvil.Colors
local LSM = Okanvil.LSM
local FLAT           = Okanvil.UI.FLAT
local u3             = Okanvil.UI.u3
local newFillPanel   = Okanvil.UI.newFillPanel
local newScrollPanel = Okanvil.UI.newScrollPanel

function Okanvil:BuildInvite()
	local fill = newFillPanel()
	local host = fill.child
	local I = Okanvil.Invite

	-- Dashboard shell (MRT/Recruit-style): header (icon + title + CTA), no tabs,
	-- no drawer -> the two-column control/roster layout scrolls in one panel.
	local dash = W.Dashboard(host, {
		title = "Invite",
		icon = Okanvil.ICONS.invite,
		drawerWidth = 0,
		footerHeight = 0,
		-- Header ON/OFF for AUTO-INVITE (like the Logs REC button) -- mais visivel
		-- que a checkbox. Este e o master switch do keyword/on-login auto-invite:
		-- OFF = nenhum auto-invite mesmo com listas armadas (nao deixa guildies cair
		-- na tua party numa dungeon). A checkbox de baixo foi removida (era duplicada).
		-- O estado vive no FILL do botao (gold = ON, surface = OFF). Nao meter |cff...
		-- no label: o kind "primary" ja pinta o texto escuro sobre o dourado, e um
		-- cinzento embutido ficava cinzento-sobre-dourado (ilegivel).
		primaryText = function()
			if not I then return "" end
			return I.KeywordEnabled() and "Auto-Invite: ON" or "Auto-Invite: OFF"
		end,
		primaryKind = function()
			return (I and I.KeywordEnabled()) and "primary" or "secondary"
		end,
		onPrimary = function()
			if not I then return end
			I.SetKeywordEnabled(not I.KeywordEnabled())
			if Okanvil.RefreshPanel then Okanvil:RefreshPanel() end
		end,
		statusText = function()
			if not I then return "|cffff5555engine not loaded|r" end
			return ""
		end,
		tabs = {
			{ key = "lists", label = "My Lists", height = 460, build = function(pg) Okanvil:Invite_BuildLists(pg) end },
		},
	})
	fill.dash = dash

	-- The page fills dash.main DIRECTLY -- no page-level scroll (the whole Invite
	-- page must never scroll). Only the roster on the right scrolls internally.
	-- The left column is short enough to always fit.
	local main = dash.main
	local X = 14
	local p = main
	local wrap = { relayout = function() end }   -- no page scroll to relayout

	-- Invite.lua provides the engine (Okanvil.Invite). If it isn't loaded, show a
	-- note instead of erroring (nil-index) so the tab never crashes the UI.
	if not I then
		local warn = W.Text(p, "", 12, "dim"); warn:SetPoint("TOPLEFT", X, -14)
		warn:SetPoint("RIGHT", p, "RIGHT", -X, 0); warn:SetJustifyH("LEFT")
		warn:SetText("|cffff8888The Invite engine (Invite.lua) isn't loaded.|r\n\n"
			.. "|cff888888Make sure Invite.lua is in the Okanvil folder and listed in Okanvil.toc, then /reload.|r")
		p:SetHeight(160); wrap.relayout()
		return fill
	end

	-- The current working list name (all list actions use this).
	local curList = "Raid"

	-- ============================================================
	-- LEFT COLUMN = controls (fixed width). RIGHT COLUMN = list manager.
	-- Both start flush at the top -- no full-width intro banner (it pushed
	-- everything down and forced the page to scroll).
	-- ============================================================
	local LEFT_W = 340
	-- The controls column can be TALLER than the window (many guild ranks + all the
	-- keyword/list sections). Put it in its own ScrollFrame that stretches to the
	-- page bottom, so the footer ("Pick raiders...") is reachable by scrolling
	-- instead of being clipped. Mirrors the roster card on the right.
	local lsf = CreateFrame("ScrollFrame", nil, p)
	lsf:SetPoint("TOPLEFT", X, -10); lsf:SetWidth(LEFT_W + 8)
	lsf:SetPoint("BOTTOM", p, "BOTTOM", 0, 10)
	local left = W.Frame(lsf, "bare"); left:SetWidth(LEFT_W); left:SetHeight(560)
	lsf:SetScrollChild(left)
	local lsb = CreateFrame("Slider", nil, p)
	lsb:SetPoint("TOPLEFT", lsf, "TOPRIGHT", -4, 0); lsb:SetPoint("BOTTOMLEFT", lsf, "BOTTOMRIGHT", -4, 0); lsb:SetWidth(4)
	lsb:SetOrientation("VERTICAL"); lsb:SetValueStep(1)
	local lth = lsb:CreateTexture(nil, "OVERLAY"); lth:SetTexture(FLAT); lth:SetSize(4, 30)
	do local a = Okanvil.Colors.accent; lth:SetVertexColor(a[1], a[2], a[3], 1) end
	lsb:SetThumbTexture(lth)
	lsb:SetScript("OnValueChanged", function(_, v) lsf:SetVerticalScroll(v) end)
	lsf:EnableMouseWheel(true)
	lsf:SetScript("OnMouseWheel", function(_, d) lsb:SetValue(lsb:GetValue() - d * 28) end)
	-- keep the scrollbar range in sync with the column's real content height
	local function leftRelayout()
		local maxS = math.max(0, left:GetHeight() - lsf:GetHeight())
		lsb:SetMinMaxValues(0, maxS)
		lsb:SetShown(maxS > 0)
	end
	lsf:SetScript("OnSizeChanged", leftRelayout)
	wrap._leftRelayout = leftRelayout

	-- ---- invite BY RANK ----
	-- Two ways to invite: (1) BY RANK -- tick ranks, hit the button; (2) THIS LIST --
	-- pick names on the right, hit the list button. We never blanket-invite everyone.
	local qh = W.Text(left, "INVITE BY RANK", 11, "accent"); qh:SetPoint("TOPLEFT", 0, 0)
	local qsub = W.Text(left, "Tick the ranks to invite, then click.", 10, "dim"); qsub:SetPoint("TOPLEFT", 0, -18)

	-- rank checkboxes bound to iv.ranks[rankIndex], built once from the roster. The
	-- sections below anchor to `rankAnchor`, which grows with the number of ranks so
	-- nothing ever overlaps the next section.
	local rankChecks = {}
	local rankAnchor = W.Frame(left, "bare"); rankAnchor:SetPoint("TOPLEFT", 0, -40); rankAnchor:SetSize(1, 1)
	local rankBuilt = false
	local function buildRankChecks()
		if rankBuilt then for _, c in ipairs(rankChecks) do c.refresh() end; return end
		local iv = I.db()
		local seen, ranks = {}, {}
		local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
		for i = 1, total do
			local _, rname, ridx = GetGuildRosterInfo(i)
			if ridx and not seen[ridx] then
				seen[ridx] = true
				ranks[#ranks + 1] = { idx = ridx, name = (rname and rname ~= "" and rname) or ("Rank " .. ridx) }
			end
		end
		if #ranks == 0 then return end
		table.sort(ranks, function(a, b) return a.idx < b.idx end)
		local cx, cy = 0, 0
		for i, r in ipairs(ranks) do
			local idx = r.idx
			local c = W.Check(rankAnchor, r.name, function() return iv.ranks[idx] end,
				function(v) iv.ranks[idx] = v and true or false end)
			c:SetPoint("TOPLEFT", cx, cy)
			rankChecks[#rankChecks + 1] = c
			cx = cx + 165
			if i % 2 == 0 then cx = 0; cy = cy - 28 end       -- roomier rows
		end
		-- final height of the rank block so the button + sections sit below it
		rankAnchor:SetHeight(math.max(28, math.ceil(#ranks / 2) * 28))
		rankBuilt = true
	end

	local bRank = W.Button(left, "Invite by rank", "primary")
	bRank:SetSize(150, 26); bRank:SetPoint("TOPLEFT", rankAnchor, "BOTTOMLEFT", 0, -10)
	bRank:SetScript("OnClick", function() I.InviteByRank() end)

	-- ---- keyword invite (whisper/guild sub-toggles) ----
	-- O MASTER enable ("Auto-Invite: ON/OFF") vive no header do Dashboard, nao aqui
	-- (era duplicado). Mantemos so o aviso de exclusao com o Recruit + os sub-toggles.
	local whlbl = W.Text(left, "KEYWORD INVITE", 11, "accent"); whlbl:SetPoint("TOPLEFT", bRank, "BOTTOMLEFT", 0, -18)
	local kwWarn = W.Text(left, "|cff8a8d93Can't run with Recruit (shared keyword) -- enabling one disables the other.|r", 10, "dim")
	kwWarn:SetPoint("TOPLEFT", whlbl, "BOTTOMLEFT", 0, -8); kwWarn:SetWidth(LEFT_W); kwWarn:SetJustifyH("LEFT")

	local wChk = W.Check(left, "On whisper", function() return I.db().whisperInvite end,
		function(v) I.db().whisperInvite = v end)
	wChk:SetPoint("TOPLEFT", kwWarn, "BOTTOMLEFT", 0, -10)
	local gChk = W.Check(left, "On guild chat", function() return I.db().guildInvite end,
		function(v) I.db().guildInvite = v end)
	gChk:SetPoint("LEFT", wChk, "LEFT", 165, 0)
	local kwlbl = W.Text(left, "Keywords", 10, "dim"); kwlbl:SetPoint("TOPLEFT", wChk, "BOTTOMLEFT", 0, -14)
	-- multiple keywords allowed, comma/space separated (e.g. "inv, invite, ginv").
	-- Keep the raw text; matching splits it and checks each as a whole word.
	local kwBox = W.EditBox(left, function(t) I.db().keyword = t or "" end)
	kwBox:Size(300, 22); kwBox:SetPoint("TOPLEFT", kwlbl, "BOTTOMLEFT", 0, -4)
	kwBox.edit:SetText(I.db().keyword or "inv")
	local kwhint = W.Text(left, "comma-separated -- any of them triggers an invite", 10, "dim")
	kwhint:SetPoint("TOPLEFT", kwBox, "BOTTOMLEFT", 0, -6)

	-- ---- saved list (built by picking raiders on the right) ----
	local llbl = W.Text(left, "RAID LIST", 11, "accent"); llbl:SetPoint("TOPLEFT", kwhint, "BOTTOMLEFT", 0, -18)
	local nmLbl = W.Text(left, "List name", 10, "dim"); nmLbl:SetPoint("TOPLEFT", llbl, "BOTTOMLEFT", 0, -12)
	local nmBox = W.EditBox(left); nmBox:Size(160, 22); nmBox:SetPoint("TOPLEFT", nmLbl, "BOTTOMLEFT", 0, -4)
	nmBox.edit:SetText(curList)
	nmBox.edit:SetScript("OnEditFocusLost", function(s)
		local v = (s:GetText() or ""):gsub("%s+", ""); if v == "" then v = "Raid" end
		curList = v; if wrap._rebuild then wrap._rebuild() end
	end)

	local cntLbl = W.Text(left, "", 12, "dim"); cntLbl:SetPoint("LEFT", nmBox, "RIGHT", 12, 0)

	-- action row 1: invite + clear
	local bInviteList = W.Button(left, "Invite this list", "primary")
	bInviteList:SetSize(150, 26); bInviteList:SetPoint("TOPLEFT", nmBox, "BOTTOMLEFT", 0, -12)
	bInviteList:SetScript("OnClick", function() I.InviteList(curList) end)
	local bClear = W.Button(left, "Clear")
	bClear:SetSize(70, 26); bClear:SetPoint("LEFT", bInviteList, "RIGHT", 8, 0)
	bClear:SetScript("OnClick", function() I.SaveList(curList, {}); if wrap._rebuild then wrap._rebuild() end end)

	-- action row 2: save (lists persist; this just confirms + refreshes My Lists)
	local bSave = W.Button(left, "Save list")
	bSave:SetSize(100, 24); bSave:SetPoint("TOPLEFT", bInviteList, "BOTTOMLEFT", 0, -8)
	bSave:SetScript("OnClick", function()
		if I.PersistList then I.PersistList(curList) end
		Okanvil:Print("Saved list '" .. curList .. "'.")
		if wrap._rebuildSaved then wrap._rebuildSaved() end
	end)

	local alChk = W.Check(left, "Auto-invite this list when they log in",
		function() local iv = I.db(); return iv.autoLoginList == curList and curList ~= "" end,
		function(v)
			local iv = I.db()
			iv.autoLoginList = (v and curList ~= "") and curList or ""
			if v and curList ~= "" then Okanvil:Print("Armed auto-invite for '" .. curList .. "' on login.") end
		end)
	alChk:SetPoint("TOPLEFT", bSave, "BOTTOMLEFT", 0, -12)

	local pinfo = W.Text(left, "Pick raiders on the right -- click a name to add/remove it. Saved lists live in the My Lists tab above.", 10, "dim")
	pinfo:SetPoint("TOPLEFT", alChk, "BOTTOMLEFT", 0, -8); pinfo:SetWidth(LEFT_W); pinfo:SetJustifyH("LEFT")

	-- ============================================================
	-- RIGHT COLUMN = ROSTER PICKER: real guildies grouped by rank, class-coloured,
	-- click to toggle into the current list. Names are the true in-game names, so
	-- invites always match (no fuzzy sign-up name problems).
	-- ============================================================
	local rcard = W.Frame(p, "input")
	rcard:SetPoint("TOPLEFT", X + LEFT_W + 16, -10)
	rcard:SetPoint("RIGHT", p, "RIGHT", -X, 0)
	rcard:SetPoint("BOTTOM", p, "BOTTOM", 0, 10)   -- fill down to the page bottom; only THIS scrolls
	local rhdr = W.Text(rcard, "GUILD ROSTER", 11, "dim"); rhdr:SetPoint("TOPLEFT", 10, -8)

	-- search filter: narrows the roster AS YOU TYPE (empty box = show everyone).
	-- Sits on its own row under the header so it never overlaps the label.
	local rfilter = ""
	local fBox = W.EditBox(rcard)
	fBox:Size(200, 20); fBox:SetPoint("TOPLEFT", 10, -26); fBox:SetPoint("RIGHT", rcard, "RIGHT", -12, 0)
	local fGhost = W.Text(fBox, "|cff777777type a name to filter...|r", 10, "dim"); fGhost:SetPoint("LEFT", 6, 0)
	fBox.edit:SetScript("OnTextChanged", function(s)
		local t = s:GetText() or ""
		fGhost:SetShown(t == "")
		rfilter = string.lower(t:gsub("^%s*(.-)%s*$", "%1"))
		if wrap._rebuildPicker then wrap._rebuildPicker() end
	end)

	local rsf = CreateFrame("ScrollFrame", nil, rcard)
	rsf:SetPoint("TOPLEFT", 8, -52); rsf:SetPoint("BOTTOMRIGHT", -12, 8)
	local rchild = CreateFrame("Frame", nil, rsf); rchild:SetSize(10, 1); rsf:SetScrollChild(rchild)
	local rsb = CreateFrame("Slider", nil, rcard)
	rsb:SetPoint("TOPRIGHT", -3, -52); rsb:SetPoint("BOTTOMRIGHT", -3, 8); rsb:SetWidth(4)
	rsb:SetOrientation("VERTICAL"); rsb:SetValueStep(1)
	local rth = rsb:CreateTexture(nil, "OVERLAY"); rth:SetTexture(FLAT); rth:SetSize(4, 30)
	do local a = Okanvil.Colors.accent; rth:SetVertexColor(a[1], a[2], a[3], 1) end
	rsb:SetThumbTexture(rth)
	rsb:SetScript("OnValueChanged", function(_, v) rsf:SetVerticalScroll(v) end)
	rsf:EnableMouseWheel(true)
	rsf:SetScript("OnMouseWheel", function(_, d) rsb:SetValue(rsb:GetValue() - d * 28) end)
	rsf:SetScript("OnSizeChanged", function() rchild:SetWidth(rsf:GetWidth()) end)
	wrap.pickRows = {}

	local CLASS_HEX = {
		DEATHKNIGHT="C41F3B", DRUID="FF7D0A", HUNTER="ABD473", MAGE="69CCF0", PALADIN="F58CBA",
		PRIEST="FFFFFF", ROGUE="FFF569", SHAMAN="0070DE", WARLOCK="9482C9", WARRIOR="C79C6E",
	}

	local function rebuildPicker()
		for _, r in ipairs(wrap.pickRows) do r:Hide() end
		if not (IsInGuild and IsInGuild()) then
			local r = wrap.pickRows[1]
			if not r then r = CreateFrame("Button", nil, rchild); r.txt = W.Text(r, ""); r.txt:SetPoint("LEFT", 6, 0); wrap.pickRows[1] = r end
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -4); r:SetSize(200, 18)
			r.txt:SetText("|cff888888Not in a guild.|r"); r:Show(); rchild:SetHeight(30); return
		end
		-- collect members, split alts out (same alt rule as Home), group by rank
		local buckets, order = {}, {}
		Okanvil:WithFullRoster(function(total)
			for i = 1, total do
				local name, rank, rankIndex, _, class, _, publicnote, officernote, online = GetGuildRosterInfo(i)
				if name then
					name = (name:gsub("%-.*$", ""))
					local isAlt = (rankIndex == 4)
						or (rank and rank:lower():find("alt", 1, true))
						or (officernote and officernote:lower():match("^.-%s+alt%f[%A]"))
					-- search filter: if a query is typed, keep only matching names
					local pass = (rfilter == "") or name:lower():find(rfilter, 1, true)
					if not isAlt and pass then
						local key = rankIndex or 99
						if not buckets[key] then buckets[key] = { name = rank or ("Rank " .. key), idx = key, list = {} }; order[#order + 1] = key end
						table.insert(buckets[key].list, { name = name, class = class, online = online })
					end
				end
			end
		end)
		table.sort(order)
		local ri, y = 0, 4
		-- get a pooled row; the CALLER positions it (we manage x/y manually for columns)
		local function pickRow()
			ri = ri + 1
			local r = wrap.pickRows[ri]
			if not r then
				r = CreateFrame("Button", nil, rchild)
				r.mark = r:CreateTexture(nil, "ARTWORK"); r.mark:SetTexture(FLAT); r.mark:SetSize(10, 10); r.mark:SetPoint("LEFT", 6, 0)
				r.txt = W.Text(r, ""); r.txt:SetPoint("LEFT", 22, 0); r.txt:SetPoint("RIGHT", -4, 0); r.txt:SetJustifyH("LEFT"); r.txt:SetWordWrap(false)
				local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(FLAT)
				hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.12)
				wrap.pickRows[ri] = r
			end
			-- reset to the NAME-row layout every time. Rows are pooled and a row that
			-- was last used as a rank HEADER left r.txt anchored at LEFT,6 -- if not
			-- reset, the reused name would render on top of the checkbox mark.
			r.mark:Hide(); r:SetScript("OnClick", nil)
			r.txt:ClearAllPoints(); r.txt:SetPoint("LEFT", 22, 0); r.txt:SetPoint("RIGHT", -4, 0)
			r:Show()
			return r
		end

		local COLW = 175
		local cols = math.max(1, math.floor((rsf:GetWidth() or 520) / COLW))
		for _, key in ipairs(order) do
			local b = buckets[key]
			table.sort(b.list, function(a, c) return a.name:lower() < c.name:lower() end)
			-- rank header row (full width)
			local hr = pickRow()
			hr:ClearAllPoints(); hr:SetPoint("TOPLEFT", 0, -y); hr:SetPoint("RIGHT", rchild, "RIGHT", 0, 0); hr:SetHeight(18)
			hr.txt:ClearAllPoints(); hr.txt:SetPoint("LEFT", 6, 0); hr.txt:SetPoint("RIGHT", -4, 0)
			hr.txt:SetText("|cffc0943a" .. (b.name or "") .. "|r  |cff8a8d93(" .. #b.list .. ")|r")
			y = y + 20
			-- names laid across `cols` columns
			local col = 0
			for _, m in ipairs(b.list) do
				local r = pickRow()
				r:ClearAllPoints(); r:SetPoint("TOPLEFT", col * COLW, -y); r:SetWidth(COLW - 4); r:SetHeight(18)
				local inList = I.IsInList(curList, m.name)
				r.mark:Show(); r.mark:SetVertexColor(inList and C.ok[1] or 0.3, inList and C.ok[2] or 0.3, inList and C.ok[3] or 0.34, 1)
				local hex = (m.class and CLASS_HEX[m.class]) or "dcddde"
				local off = m.online and "" or "  |cff5e6166o|r"
				r.txt:SetText("|c" .. (inList and "ff" or "aa") .. hex .. m.name .. "|r" .. off)
				local who = m.name
				r:SetScript("OnClick", function() I.ToggleInList(curList, who) end)
				col = col + 1
				if col >= cols then col = 0; y = y + 18 end
			end
			if col > 0 then y = y + 18 end
			y = y + 8
		end
		rchild:SetHeight(math.max(1, y))
		local maxs = math.max(0, y - rsf:GetHeight())
		rsb:SetMinMaxValues(0, maxs); rsb:SetShown(maxs > 4)
	end
	wrap._rebuildPicker = rebuildPicker   -- the search filter re-runs just this

	local function rebuild()
		buildRankChecks()
		rebuildPicker()
		nmBox.edit:SetText(curList)                    -- reflect the active list name
		local n = 0
		local mem = I.ListMembers(curList)
		if mem then n = #mem end
		cntLbl:SetText("|cff7cfc8a" .. n .. "|r |cff8a8d93in list|r")
		if alChk.refresh then alChk.refresh() end        -- re-read the auto-invite toggle
		-- Fit the left column to its ACTUAL content (the rank block grows with the
		-- number of guild ranks). Measuring the last element and sizing the frame
		-- from it stops the footer ("Pick raiders...") being clipped off the bottom
		-- when there are many ranks. A fixed height cannot know how many there are.
		local top = left:GetTop()
		local bot = pinfo:GetBottom()
		if top and bot then left:SetHeight(math.max(1, top - bot + 6)) end
		if wrap._leftRelayout then wrap._leftRelayout() end   -- refresh the scrollbar range
	end
	wrap._rebuild = rebuild

	-- Public setter so the My Lists tab can switch the active list and have the
	-- whole page update (name box, count, auto toggle, roster ticks).
	function fill:SetActiveList(name)
		if not name or name == "" then return end
		curList = name
		rebuild()
	end

	Okanvil._inviteFill = fill                 -- the My Lists tab reads engine off this
	local function refreshAll()
		dash:Refresh(); rebuild()
		if fill._rebuildLists then fill._rebuildLists() end   -- keep the My Lists tab fresh
	end
	I.onChange = function() if fill:IsShown() then refreshAll() end end
	fill:SetScript("OnShow", function() if GuildRoster then GuildRoster() end; refreshAll() end)
	return fill
end

-- ---- Invite: My Lists tab -- see each saved list's members, load / arm / delete ----
function Okanvil:Invite_BuildLists(p)
	local I = Okanvil.Invite
	local fill = Okanvil._inviteFill
	if not I then
		local w = W.Text(p, "|cffff8888Invite engine not loaded.|r", 12, "dim"); w:SetPoint("TOPLEFT", 8, -8)
		return
	end
	local X = 8
	local hint = W.Text(p, "Your saved raid lists. Load one to edit/invite it, arm Auto to invite it when its members log in, or delete it.", 10, "dim")
	hint:SetPoint("TOPLEFT", X, -6); hint:SetPoint("RIGHT", p, "RIGHT", -X, 0); hint:SetJustifyH("LEFT")
	local safe = W.Text(p, "|cff7cfc8aSafe:|r |cff8a8d93Auto-invite only fires when you're solo, or the leader/assistant of a pure-guild group -- never in someone else's group or a pug raid.|r", 10, "dim")
	safe:SetPoint("TOPLEFT", X, -22); safe:SetPoint("RIGHT", p, "RIGHT", -X, 0); safe:SetJustifyH("LEFT")

	local rows, detail = {}, {}
	local expanded = nil
	local function rebuild()
		for _, r in ipairs(rows) do r:Hide() end
		for _, t in ipairs(detail) do t:Hide() end
		local lists = I.SavedLists()
		local names = {}
		for name in pairs(lists) do names[#names + 1] = name end
		table.sort(names)
		if #names == 0 then
			p._empty = p._empty or W.Text(p, "", 11, "dim")
			p._empty:ClearAllPoints(); p._empty:SetPoint("TOPLEFT", X, -60)
			p._empty:SetText("|cff6f7176No saved lists yet. Build one in the Invite page (pick raiders, name it, Save list).|r")
			p._empty:Show(); p:SetHeight(120); return
		end
		if p._empty then p._empty:Hide() end
		local di, y = 0, 60
		for i, name in ipairs(names) do
			local members = lists[name] or {}
			local r = rows[i]
			if not r then
				r = W.Frame(p, "input")
				r.name = W.Text(r, "", 13); r.name:SetPoint("LEFT", 10, 0)
				r.del  = W.Button(r, "Delete", "danger"); r.del:SetSize(60, 22); r.del:SetPoint("RIGHT", -8, 0)
				r.auto = W.Button(r, "Auto"); r.auto:SetSize(54, 22); r.auto:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
				r.load = W.Button(r, "Load"); r.load:SetSize(54, 22); r.load:SetPoint("RIGHT", r.auto, "LEFT", -6, 0)
				r:EnableMouse(true)
				rows[i] = r
			end
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", X, -y); r:SetPoint("RIGHT", p, "RIGHT", -X, 0); r:SetHeight(30)
			local armed = (I.db().autoLoginList == name)
			local isOpen = (expanded == name)
			r.name:SetText((isOpen and "|cffffd200v|r  " or "|cff8a8d93>|r  ") .. name
				.. "  |cff8a8d93(" .. #members .. ")|r" .. (armed and "  |cff7cfc8a[auto]|r" or ""))
			r.load:SetScript("OnClick", function()
				if fill and fill.SetActiveList then fill:SetActiveList(name) end  -- switch active list + refresh page
				if fill and fill.dash then fill.dash:CloseOverlay() end          -- back to the picker
				Okanvil:Print("Loaded list '" .. name .. "' (" .. #members .. ") -- now editing it.")
			end)
			r.auto:SetScript("OnClick", function()
				local iv = I.db(); iv.autoLoginList = (iv.autoLoginList == name) and "" or name
				Okanvil:Print(iv.autoLoginList == name and ("Auto-invite armed for '" .. name .. "'.") or "Auto-invite disarmed.")
				rebuild()
			end)
			r.del:SetScript("OnClick", function()
				if expanded == name then expanded = nil end
				if I.DeleteSavedList then I.DeleteSavedList(name) end
				rebuild()
			end)
			-- expand/collapse the member list on click of the row (not the buttons)
			r:SetScript("OnMouseUp", function()
				expanded = (expanded == name) and nil or name; rebuild()
			end)
			r:Show()
			y = y + 34
			if isOpen then
				di = di + 1
				local t = detail[di]
				if not t then
					t = W.Text(p, "", 11); t:SetJustifyH("LEFT"); t:SetJustifyV("TOP")
					if t.SetWordWrap then t:SetWordWrap(true) end
					detail[di] = t
				end
				-- give the fontstring an EXPLICIT width (the scroll child's real width
				-- minus our left indent + right pad) so the names actually wrap to
				-- multiple lines instead of overflowing off the right edge.
				local wpx = math.max(100, (p:GetWidth() or 400) - (X + 16) - X)
				t:ClearAllPoints(); t:SetPoint("TOPLEFT", X + 16, -y); t:SetWidth(wpx)
				if #members > 0 then
					local nm = {}
					for k = 1, #members do nm[k] = members[k].name end
					table.sort(nm)
					t:SetText("|cffdcddde" .. table.concat(nm, "  |cff5e6166\194\183|r  ") .. "|r")
				else
					t:SetText("|cff888888(empty list)|r")
				end
				t:Show()
				y = y + (t:GetStringHeight() or 12) + 12
			end
		end
		p:SetHeight(math.max(y + 10, 200))
		local sf = p:GetParent()          -- the overlay scrollframe owns _relayout
		if sf and sf._relayout then sf._relayout() end
	end
	fill._rebuildLists = rebuild
	rebuild()
end

-- ------------------------------------------------------------
-- Settings
-- ------------------------------------------------------------
