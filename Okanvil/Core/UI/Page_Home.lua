-- ============================================================
-- Okanvil -- UI: Home page
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

function Okanvil:BuildHome()
	local wrap = newScrollPanel()
	local p = wrap.child
	local X = 16

	-- header: product wordmark (fixed) + guild skin subtitle + version
	-- product wordmark (there's no logo.blp; the text wordmark IS the logo)
	local title = W.Text(p, "Okanvil", "huge", "accent"); title:SetPoint("TOPLEFT", X, -20)
	local anchor = title
	-- guild skin (editable) as a subtitle under the product name
	-- Same rule as the title bar: no guild, no guild skin. The brand is stored
	-- account-wide, so without this an alt in no guild wore the main's guild name.
	local gb = self.db.brand
	if IsInGuild and not IsInGuild() then gb = "" end
	local guildFS
	if gb and gb ~= "" and gb ~= "Okanvil" then
		guildFS = W.Text(p, gb, "head", "accent"); guildFS:Color(0.88, 0.72, 0.38)
		guildFS:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
		anchor = guildFS
	end
	local sub = W.Text(p, "v" .. (self.version or "1.0") .. "  --  raid & guild toolkit by Okanor", "label", "dim")
	sub:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
	local hrule = p:CreateTexture(nil, "ARTWORK")
	hrule:SetTexture("Interface\Buttons\WHITE8x8")
	local bc = Okanvil.Colors.border
	hrule:SetVertexColor(bc[1], bc[2], bc[3], 1)
	hrule:SetHeight(1)
	hrule:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -10)
	hrule:SetPoint("RIGHT", p, "RIGHT", -X, 0)

	-- stat tiles: online / raiders / sewers / your rank. Anchored to the header's
	-- (the `sub` line) so a 2- or 3-line header never overlaps them.
	-- Three identical tiles in one row. All values share the SAME font size and
	-- baseline so numbers and the rank name read as one aligned row (a big "20pt
	-- number" next to a "Warchief Rat" name looked like uneven steps before).
	local TILE_W, TILE_H, VAL_SZ = 120, 48, 22
	-- the rank tile holds a NAME, not a number, so it gets the room a name needs
	local RANK_W = 190
	local tiles = {}
	local function tile(i, label)
		-- No box: a big gold value over a small label, straight on the page art.
		local t = W.Frame(p, "bare")
		-- the rank tile holds a NAME, not a number, so it gets the width one needs
		t:SetSize((label == "YOUR RANK") and RANK_W or TILE_W, TILE_H)
		if i == 1 then
			t:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -18)
		else
			t:SetPoint("TOPLEFT", tiles["_t" .. (i - 1)], "TOPRIGHT", 8, 0)
		end
		-- label pinned near the bottom; the value sits just above it, so all three
		-- values line up on the same baseline regardless of number vs name.
		t.lbl = W.Text(t, label, "note", "dim"); t.lbl:SetPoint("BOTTOMLEFT", 0, 6)
		t.num = W.Text(t, "--", VAL_SZ, "accent")
		t.num:SetPoint("BOTTOMLEFT", t.lbl, "TOPLEFT", 0, 5); t.num:SetPoint("RIGHT", t, "RIGHT", -10, 0); t.num:SetJustifyH("LEFT")
		if t.num.SetWordWrap then t.num:SetWordWrap(false) end
		tiles["_t" .. i] = t
		return t
	end
	tiles.online = tile(1, "ONLINE")
	-- Two rank counts instead of a MAINS total: "how many raiders do we have" is
	-- the question actually asked, and a combined total answered none of it. Alts
	-- are excluded from both, the way MAINS excluded them.
	--
	-- The labels are the guild's OWN rank names, filled in once the roster is
	-- known -- they used to read RAIDERS and SEWERS, which are this guild's words
	-- and meant nothing in any other guild that installed Okanvil.
	tiles.raiders = tile(2, "RAIDERS")
	tiles.sewers = tile(3, "MEMBERS")
	tiles.rank = tile(4, "YOUR RANK")

	-- guild online card -- a SCROLLABLE row list (shows everyone, not a capped
	-- text blob) with a per-row [inv] button for quick invites from Home.
	-- The online card fills the rest of the page height (Home is a fixed-size
	-- window, so anchoring its bottom to the content area gives many more visible
	-- rows -> far less scrolling). BOTTOMRIGHT is the scroll area's real bottom.
	-- Online / Snapshots switch + the roster export. The Guild page was one export
	-- button and this snapshot list; both are guild data, and this is where you
	-- already come to look at guild data, so they live here instead of behind
	-- their own nav row.
	local tabOnline = W.Button(p, "Online", "tabOn")
	tabOnline:SetSize(72, 22)
	tabOnline:SetPoint("TOPLEFT", tiles._t1, "BOTTOMLEFT", 0, -10)
	local tabSnaps = W.Button(p, "Snapshots", "tab")
	tabSnaps:SetSize(92, 22)
	tabSnaps:SetPoint("LEFT", tabOnline, "RIGHT", 10, 0)
	-- Snapshots and the roster export ARE the Guild module -- switching it off in
	-- Modules should take them with it. It did not: the module had a switch that
	-- changed nothing on the one page its features live on.
	local guildOn = Okanvil:IsModuleEnabled("__guild")
	tabSnaps:SetShown(guildOn)
	local exportBtn = W.Button(p, "Export roster")
	exportBtn:SetSize(110, 22)
	exportBtn:SetPoint("RIGHT", p, "RIGHT", -X, 0)
	exportBtn:SetPoint("TOP", tabOnline, "TOP", 0, 0)
	-- Exports feed the website, which is officer work: no button for anyone else.
	exportBtn:SetShown(guildOn and Okanvil.U and Okanvil.U.canSeePrio and Okanvil.U.canSeePrio() and true or false)
	exportBtn:Tooltip("Build the roster JSON the web hub imports.")
	exportBtn:SetScript("OnClick", function()
		local G = Okanvil.Guild
		if not (G and G.ExportRoster) then Okanvil:Print("Guild module not loaded."); return end
		-- async: the offline members have to finish loading or the export is only
		-- whoever happened to be online
		G.ExportRoster(function(json) Okanvil:ShowExport(json, "Guild roster") end)
	end)

	local gcard = W.Frame(p, "bare")
	gcard:SetPoint("TOPLEFT", tabOnline, "BOTTOMLEFT", 0, -10)
	gcard:SetPoint("RIGHT", p, "RIGHT", -X, 0)
	gcard:SetPoint("BOTTOM", p, "BOTTOM", 0, 12)
	gcard:SetHeight(180)   -- fallback min; the BOTTOM anchor stretches it taller
	local gh = W.Text(gcard, "GUILD ONLINE", "note", "dim"); gh:SetPoint("TOPLEFT", 0, -8)
	-- flat scroll (no Blizzard template): plain ScrollFrame + our own slider
	local gsf = CreateFrame("ScrollFrame", nil, gcard)
	gsf:SetPoint("TOPLEFT", 8, -24); gsf:SetPoint("BOTTOMRIGHT", -12, 6)
	local gchild = CreateFrame("Frame", nil, gsf); gchild:SetSize(10, 1)
	gsf:SetScrollChild(gchild)
	local gsb = CreateFrame("Slider", nil, gcard)
	gsb:SetPoint("TOPRIGHT", -3, -24); gsb:SetPoint("BOTTOMRIGHT", -3, 6); gsb:SetWidth(6)
	gsb:SetOrientation("VERTICAL"); gsb:SetValueStep(1)
	-- a faint track behind the thumb: a lone 4px bar on a dark card was easy to
	-- miss, so there was no sign the list scrolled at all
	local gtrack = gsb:CreateTexture(nil, "BACKGROUND")
	gtrack:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	gtrack:SetAllPoints(gsb)
	gtrack:SetVertexColor(1, 1, 1, 0.06)
	local gth = gsb:CreateTexture(nil, "OVERLAY"); gth:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	gth:SetSize(6, 36); local ga = Okanvil.Colors.accent; gth:SetVertexColor(ga[1], ga[2], ga[3], 1)
	gsb:SetThumbTexture(gth)
	gsb:SetScript("OnValueChanged", function(_, v) gsf:SetVerticalScroll(v) end)
	gsf:EnableMouseWheel(true)
	gsf:SetScript("OnMouseWheel", function(_, d) gsb:SetValue(gsb:GetValue() - d * 24) end)
	wrap.gsf, wrap.gchild, wrap.gsb, wrap.gRows = gsf, gchild, gsb, {}
	local gempty = W.Text(gcard, "", "body", "dim"); gempty:SetPoint("TOPLEFT", 10, -26)
	wrap.gempty = gempty

	-- ---- SNAPSHOTS card: same space as the online list, shown by the tab ----
	-- One row per snapshot; View expands it in place into group cards below.
	local scard = W.Frame(p, "bare")
	scard:SetAllPoints(gcard)
	local sh = W.Text(scard, "SAVED SNAPSHOTS", "note", "dim"); sh:SetPoint("TOPLEFT", 0, -8)
	local ssf = CreateFrame("ScrollFrame", nil, scard)
	ssf:SetPoint("TOPLEFT", 8, -28); ssf:SetPoint("BOTTOMRIGHT", -12, 6)
	local schild = CreateFrame("Frame", nil, ssf); schild:SetSize(10, 1)
	ssf:SetScrollChild(schild)
	local ssb = CreateFrame("Slider", nil, scard)
	ssb:SetPoint("TOPRIGHT", -3, -28); ssb:SetPoint("BOTTOMRIGHT", -3, 6); ssb:SetWidth(6)
	ssb:SetOrientation("VERTICAL"); ssb:SetValueStep(1)
	local strack = ssb:CreateTexture(nil, "BACKGROUND")
	strack:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	strack:SetAllPoints(ssb); strack:SetVertexColor(1, 1, 1, 0.06)
	local sth = ssb:CreateTexture(nil, "OVERLAY")
	sth:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	sth:SetSize(6, 36); sth:SetVertexColor(ga[1], ga[2], ga[3], 1)
	ssb:SetThumbTexture(sth)
	ssb:SetScript("OnValueChanged", function(_, v) ssf:SetVerticalScroll(v) end)
	ssf:EnableMouseWheel(true)
	ssf:SetScript("OnMouseWheel", function(_, d) ssb:SetValue(ssb:GetValue() - d * 46) end)
	scard:Hide()
	wrap.snapRows, wrap.snapCards, wrap.snapOpen = {}, {}, nil

	-- ---- expanded snapshot: one card per raid group, one tile per player ----
	-- Cards sit side by side as far as the width allows, so a 25-man's five
	-- groups read as five columns on a full-width window and wrap on a narrow one.
	local CARD_MIN_W, CARD_GAP, CARD_HEAD_H, PROW_H = 190, 8, 26, 38
	local ROLE_BADGE = { MAINTANK = "MT", MAINASSIST = "MA" }

	-- The class crest when the spec was never inspected: still says what the
	-- player is, just not which tree.
	local function classIcon(tex, token)
		local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token or ""]
		if c then
			tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
			tex:SetTexCoord(c[1], c[2], c[3], c[4])
		else
			tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
	end

	local function playerTile(card, i)
		card.tiles = card.tiles or {}
		local r = card.tiles[i]
		if r then return r end
		r = CreateFrame("Frame", nil, card)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(28, 28); r.icon:SetPoint("LEFT", 8, 0)
		r.name = W.Text(r, "", "body")
		r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
		r.name:SetJustifyH("LEFT")
		r.spec = W.Text(r, "", "note", "dim")
		r.spec:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 0)
		r.spec:SetJustifyH("LEFT")
		r.badge = W.Text(r, "", "note", "accent")
		r.badge:SetPoint("RIGHT", -8, 0)
		card.tiles[i] = r
		return r
	end

	local function fillTile(r, p, width)
		-- The spec saved with the snapshot is what they played that night. The
		-- live inspect cache only stands in for a snapshot saved without one, and
		-- only when it is recent -- an old reading is shown as unknown rather than
		-- passed off as current.
		local spec, icon = p.spec, p.specIcon
		if not spec then
			local I = Okanvil.Inspect
			local info = I and I.Info and I.Info(p.name)
			if info and I.IsFresh and I.IsFresh(p.name) then spec, icon = info.spec, info.icon end
		end
		if icon then
			r.icon:SetTexture(icon)
			r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		else
			classIcon(r.icon, p.class)
		end

		local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class or ""]
		if c then r.name:SetTextColor(c.r, c.g, c.b) end
		r.name:SetText(p.name or "?")
		r.name:SetWidth(width - 84)

		local sub = spec or "spec unknown"
		if (p.level or 0) > 0 and p.level < 80 then sub = sub .. "  |cff5e6166lvl " .. p.level .. "|r" end
		if p.online == false then sub = sub .. "  |cff5e6166offline|r" end
		r.spec:SetText(sub)
		r.spec:SetWidth(width - 84)

		r.badge:SetText(ROLE_BADGE[p.role or ""] or "")
		r:SetAlpha(p.online == false and 0.5 or 1)
	end

	-- Lays the cards out under the snapshot row at offset y; returns the y below them.
	local function drawSnapCards(snap, y)
		local groups, order = {}, {}
		for _, p in ipairs(snap.players or {}) do
			local g = p.group or 0
			if not groups[g] then groups[g] = {}; order[#order + 1] = g end
			local list = groups[g]
			list[#list + 1] = p
		end
		if #order == 0 then return y end

		local width = math.max(CARD_MIN_W, schild:GetWidth() - 8)
		local cols = math.max(1, math.min(#order,
			math.floor((width + CARD_GAP) / (CARD_MIN_W + CARD_GAP))))
		local cardW = (width - (cols - 1) * CARD_GAP) / cols

		local top, lineH = y, 0
		for idx, g in ipairs(order) do
			local col = (idx - 1) % cols
			if col == 0 and idx > 1 then
				top = top + lineH + CARD_GAP
				lineH = 0
			end
			local card = wrap.snapCards[idx]
			if not card then
				card = W.Frame(schild, "soft")
				card.head = W.Text(card, "", "note", "dim")
				card.head:SetPoint("TOPLEFT", 10, -8)
				wrap.snapCards[idx] = card
			end
			local list = groups[g]
			local h = CARD_HEAD_H + #list * PROW_H + 6
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", 4 + col * (cardW + CARD_GAP), -top)
			card:SetSize(cardW, h)
			card.head:SetText(g > 0 and ("GROUP " .. g) or "PARTY")
			for _, t in ipairs(card.tiles or {}) do t:Hide() end
			for i, p in ipairs(list) do
				local r = playerTile(card, i)
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", 0, -(CARD_HEAD_H + (i - 1) * PROW_H))
				r:SetSize(cardW, PROW_H)
				fillTile(r, p, cardW)
				r:Show()
			end
			card:Show()
			if h > lineH then lineH = h end
		end
		return top + lineH + 12
	end

	local function rebuildSnaps()
		local G = Okanvil.Guild
		for _, r in ipairs(wrap.snapRows) do r:Hide() end
		for _, c in ipairs(wrap.snapCards) do c:Hide() end
		local snaps = (Okanvil.db.guild and Okanvil.db.guild.snapshots) or {}
		schild:SetWidth(math.max(40, ssf:GetWidth()))
		if #snaps == 0 or not G then
			wrap.snapEmpty = wrap.snapEmpty or W.Text(schild, "", "body", "dim")
			wrap.snapEmpty:ClearAllPoints(); wrap.snapEmpty:SetPoint("TOPLEFT", 4, -6)
			wrap.snapEmpty:SetText(G and "|cff888888No snapshots yet. One is saved automatically at the first pull of a raid.|r"
				or "|cff888888Guild module not loaded.|r")
			wrap.snapEmpty:Show(); schild:SetHeight(40); ssb:SetShown(false); return
		end
		if wrap.snapEmpty then wrap.snapEmpty:Hide() end

		local di, y = 0, 0
		for i, snap in ipairs(snaps) do
			local r = wrap.snapRows[i]
			if not r then
				r = Okanvil.UI.RecordRow(schild, function(row)
					local sn = row._snap
					if not sn then return end
					if wrap.snapOpen == sn then wrap.snapOpen = nil else wrap.snapOpen = sn end
					rebuildSnaps()
				end)
				r.del = W.Button(r, "X", "danger"); r.del:SetSize(24, 22); r.del:SetPoint("RIGHT", -8, 0)
				r.export = W.Button(r, "Export"); r.export:SetSize(72, 22); r.export:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
				r.inv = W.Button(r, "Invite", "primary"); r.inv:SetSize(60, 22)
				r.inv:SetPoint("RIGHT", r.export, "LEFT", -6, 0)
				Okanvil.UI.HoverReveal(r, { r.inv, r.export, r.del })
				wrap.snapRows[i] = r
			end
			r._snap = snap
			local RH = Okanvil.UI.RECORD_ROW_H
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", schild, "RIGHT", 0, 0)
			r:SetHeight(RH)
			local dateStr = date("%b %d  %H:%M", snap.t)
			local where = (snap.zone ~= "" and snap.zone) or "Unknown"
			local isOpen = (wrap.snapOpen == snap)
			local size, heroic = Okanvil.UI.RaidDifficulty(snap.difficulty)
			Okanvil.UI.PaintRecordRow(r, {
				size = size or ((snap.groupSize or 0) > 0 and snap.groupSize or nil),
				heroic = heroic,
				title = where .. ((snap.boss or "") ~= "" and ("  |cff8a8d93--|r  " .. snap.boss) or ""),
				sub = Okanvil.UI.NightStamp(snap.t) .. "   |cff5e6166·|r   " .. (snap.count or 0)
					.. " players   |cff5e6166·|r   " .. (snap.trigger or ""),
				open = isOpen,
			})

			r.export:SetScript("OnClick", function()
				Okanvil:ShowExport(G.SnapshotJSON(snap), "Attendance -- " .. dateStr)
			end)
			-- Exports feed the website, which is officer work: no button for anyone else.
			local canExport = Okanvil.U and Okanvil.U.canSeePrio and Okanvil.U.canSeePrio()
			r.export._allowed = canExport and true or false
			r._revealUpdate()
			r.inv:ClearAllPoints()
			r.inv:SetPoint("RIGHT", canExport and r.export or r.del, "LEFT", -6, 0)
			r.inv:Tooltip("Invite everyone from this snapshot (" .. (snap.count or 0) .. " players).\nAlready in the group, or offline, are skipped.")
			r.inv:SetScript("OnClick", function()
				local sent, total = G.InviteSnapshot(snap)
				local skipped = (total or 0) - (sent or 0)
				if skipped > 0 then
					Okanvil:Print("|cff8a8d93" .. skipped .. " skipped (already in your group, or offline).|r")
				end
			end)
			r.del:SetScript("OnClick", function()
				if wrap.snapOpen == snap then wrap.snapOpen = nil end
				G.DeleteSnapshot(snap)
				rebuildSnaps()
			end)
			r:Show()
			y = y + RH + 6
			if isOpen then y = drawSnapCards(snap, y) end
		end
		schild:SetHeight(math.max(1, y))
		local maxs = math.max(0, y - ssf:GetHeight())
		ssb:SetMinMaxValues(0, maxs); ssb:SetShown(maxs > 4)
	end
	wrap.rebuildSnaps = rebuildSnaps

	-- Re-measure only, like the online card: rebuildSnaps() re-renders every row
	-- and rebuilds the body text of any expanded one, which is far too much to run
	-- on each frame of a resize.
	ssf:SetScript("OnSizeChanged", function(self)
		schild:SetWidth(math.max(40, self:GetWidth()))
		local maxs = math.max(0, schild:GetHeight() - self:GetHeight())
		ssb:SetMinMaxValues(0, maxs)
		ssb:SetShown(maxs > 4)
	end)

	-- tab switching: one card visible at a time, both filling the same space
	local function showTab(which)
		local snaps = (which == "snaps")
		gcard:SetShown(not snaps)
		scard:SetShown(snaps)
		-- not "snaps and nil or primary": that can never be nil, so the Online tab
		-- stayed gold while Snapshots was showing
		tabOnline:SetKind(snaps and "tab" or "tabOn")
		tabSnaps:SetKind(snaps and "tabOn" or "tab")
		if snaps then rebuildSnaps() end
	end
	tabOnline:SetScript("OnClick", function() showTab("online") end)
	tabSnaps:SetScript("OnClick", function() showTab("snaps") end)

	-- (The web-hub link now lives in the window FOOTER, WeakAuras-style -- always
	-- visible, click to copy the URL. No card here anymore.)

	-- (rat art is one shared overlay on Okanvil.content -- nothing to build here.)

	-- ---- no guild: pug mode ----
	-- Guild counts and a guild roster mean nothing without a guild, so instead of
	-- four "--" tiles the page says what Okanvil is for right now and offers the
	-- two pug tools.
	local pug = CreateFrame("Frame", nil, p)
	pug:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -26)
	pug:SetPoint("RIGHT", p, "RIGHT", -X, 0)
	pug:SetHeight(160)
	pug:Hide()
	local pugHead = W.Text(pug, "No guild -- pug mode", "head", "accent")
	pugHead:SetPoint("TOPLEFT", 0, 0)
	local pugText = W.Text(pug, "Find a raid in chat, or build your own and spam the LFM line. "
		.. "Joined a guild? Run |cff00ff00/okanvil setup|r again to turn on the guild tools.", "body", "dim")
	pugText:SetPoint("TOPLEFT", pugHead, "BOTTOMLEFT", 0, -8)
	pugText:SetPoint("RIGHT", pug, "RIGHT", 0, 0)
	pugText:SetJustifyH("LEFT")
	local bRF = W.Button(pug, "Raid Finder", "primary"); bRF:SetSize(130, 26)
	bRF:SetPoint("TOPLEFT", pugText, "BOTTOMLEFT", 0, -14)
	bRF:SetScript("OnClick", function() Okanvil:ShowPanel("Okanvil-RaidFinder") end)
	local bPug = W.Button(pug, "PuG"); bPug:SetSize(110, 26)
	bPug:SetPoint("LEFT", bRF, "RIGHT", 8, 0)
	bPug:SetScript("OnClick", function() Okanvil:ShowPanel("Okanvil-PuG") end)

	-- Two columns under the buttons: raids asking for people right now (what Raid
	-- Finder has read in chat), and what this character is saved to -- the two
	-- things a pugger checks before whispering anyone.
	pug:SetHeight(470)
	local function colHead(text, anchorX)
		local t = W.Text(pug, text, "note", "dim")
		t:SetPoint("TOPLEFT", bRF, "BOTTOMLEFT", anchorX, -26)
		return t
	end
	local lfHead = colHead("LOOKING FOR PEOPLE", 0)
	local lkHead = W.Text(pug, "YOUR LOCKOUTS", "note", "dim")

	local function makeRows(parent, head, n, rightEdge)
		local rows = {}
		for i = 1, n do
			local r = CreateFrame("Button", nil, parent)
			r:SetHeight(24)
			r:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6 - (i - 1) * 26)
			r:SetPoint("RIGHT", rightEdge, "RIGHT", 0, 0)
			local rule = r:CreateTexture(nil, "BORDER")
			rule:SetTexture("Interface\\Buttons\\WHITE8x8"); rule:SetVertexColor(1, 1, 1, 0.06)
			rule:SetHeight(1); rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT")
			local hl = r:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints(); hl:SetTexture("Interface\\Buttons\\WHITE8x8"); hl:SetVertexColor(1, 1, 1, 0.04)
			r.l = W.Text(r, "", "body"); r.l:SetPoint("LEFT", 2, 0); r.l:SetJustifyH("LEFT")
			r.r = W.Text(r, "", "note", "dim"); r.r:SetPoint("RIGHT", -2, 0); r.r:SetJustifyH("RIGHT")
			r.l:SetPoint("RIGHT", r.r, "LEFT", -8, 0)
			if r.l.SetWordWrap then r.l:SetWordWrap(false) end
			r:Hide()
			rows[i] = r
		end
		return rows
	end
	-- the left column stops at the page's middle, the right one runs to its edge
	local mid = CreateFrame("Frame", nil, pug)
	mid:SetPoint("TOP", pug, "TOP"); mid:SetPoint("BOTTOM", pug, "BOTTOM")
	mid:SetPoint("RIGHT", pug, "CENTER", -12, 0); mid:SetWidth(1)
	-- the right column's heading: level with the left one, just past the middle
	lkHead:SetPoint("TOP", lfHead, "TOP", 0, 0)
	lkHead:SetPoint("LEFT", mid, "RIGHT", 24, 0)
	local lfRows = makeRows(pug, lfHead, 5, mid)
	local lkRows = makeRows(pug, lkHead, 5, pug)
	local lfEmpty = W.Text(pug, "", "note", "dim")
	lfEmpty:SetPoint("TOPLEFT", lfHead, "BOTTOMLEFT", 0, -8)
	lfEmpty:SetPoint("RIGHT", mid, "RIGHT", 0, 0); lfEmpty:SetJustifyH("LEFT")
	local lkEmpty = W.Text(pug, "", "note", "dim")
	lkEmpty:SetPoint("TOPLEFT", lkHead, "BOTTOMLEFT", 0, -8)
	lkEmpty:SetPoint("RIGHT", pug, "RIGHT", 0, 0); lkEmpty:SetJustifyH("LEFT")

	-- ---- GUILDS RECRUITING: recruitment spam caught from chat ----
	-- Only while you have no guild (it is the one time the spam is useful), never
	-- in combat. Newest line per sender, kept 20 minutes, at most 20 senders.
	local grHead = W.Text(pug, "GUILDS RECRUITING", "note", "dim")
	grHead:SetPoint("TOPLEFT", lfHead, "BOTTOMLEFT", 0, -6 - 5 * 26 - 16)
	local grRows = makeRows(pug, grHead, 5, pug)
	for _, r in ipairs(grRows) do
		r.w = W.Button(r, "Whisper"); r.w:SetSize(70, 20)
		r.w:SetPoint("RIGHT", -2, 0)
		r.r:ClearAllPoints(); r.r:SetPoint("RIGHT", r.w, "LEFT", -8, 0)
	end
	local grEmpty = W.Text(pug, "", "note", "dim")
	grEmpty:SetPoint("TOPLEFT", grHead, "BOTTOMLEFT", 0, -8)
	grEmpty:SetPoint("RIGHT", pug, "RIGHT", 0, 0); grEmpty:SetJustifyH("LEFT")

	Okanvil._recruitSeen = Okanvil._recruitSeen or {}
	local seen = Okanvil._recruitSeen
	local function isRecruitSpam(low)
		-- a player asking for a guild is not a guild recruiting
		if low:find("lf guild", 1, true) or low:find("looking for guild", 1, true)
			or low:find("looking for a guild", 1, true) or low:find("lf a guild", 1, true) then
			return false
		end
		if low:find("recruit", 1, true) then return true end
		if low:find("guild", 1, true) and (low:find("looking for", 1, true)
			or low:find("lf ", 1, true) or low:find("join", 1, true) or low:find("members", 1, true)) then
			return true
		end
		return false
	end
	local function cleanLine(msg)
		msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		msg = msg:gsub("|H.-|h(.-)|h", "%1")
		return msg
	end
	if not Okanvil._recruitWatch then
		local ev = CreateFrame("Frame")
		ev:RegisterEvent("CHAT_MSG_CHANNEL")
		ev:SetScript("OnEvent", function(_, _, msg, sender)
			if IsInGuild and IsInGuild() then return end
			if InCombatLockdown() then return end
			if not msg or not sender or sender == "" then return end
			local low = msg:lower()
			if not isRecruitSpam(low) then return end
			local name = sender:gsub("%-.*$", "")
			if name == UnitName("player") then return end
			seen[name] = { sender = name, guild = msg:match("<([^>]+)>"), text = cleanLine(msg), t = time() }
		end)
		Okanvil._recruitWatch = ev
	end
	local function whisperTo(who)
		if ChatFrame_SendTell then ChatFrame_SendTell(who)
		elseif ChatEdit_ActivateChat and ChatFrame1EditBox then
			ChatFrame1EditBox:SetAttribute("chatType", "WHISPER")
			ChatFrame1EditBox:SetAttribute("tellTarget", who)
			ChatEdit_ActivateChat(ChatFrame1EditBox)
		end
	end
	local function paintRecruit()
		local now, list = time(), {}
		for name, e in pairs(seen) do
			if now - e.t > 1200 then seen[name] = nil else list[#list + 1] = e end
		end
		table.sort(list, function(a, b) return a.t > b.t end)
		while #list > 20 do seen[list[#list].sender] = nil; table.remove(list) end
		for i, r in ipairs(grRows) do
			local e = list[i]
			if e then
				local head = e.guild and ("|cffe0b860<" .. e.guild .. ">|r ") or ""
				r.l:SetText(head .. "|cff8a8d93" .. e.text .. "|r")
				local mins = math.floor((now - e.t) / 60)
				r.r:SetText(e.sender .. "  " .. (mins < 1 and "now" or (mins .. "m")))
				local who = e.sender
				r.w:SetScript("OnClick", function() whisperTo(who) end)
				r:SetScript("OnClick", function() whisperTo(who) end)
				r:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_TOP")
					GameTooltip:AddLine(e.text, 1, 1, 1, true)
					GameTooltip:Show()
				end)
				r:SetScript("OnLeave", function() GameTooltip:Hide() end)
				r:Show()
			else
				r:Hide()
			end
		end
		if #list == 0 then
			grEmpty:SetText("No recruitment seen yet. Guild ads posted in General, Trade or "
				.. "Global show up here, newest first, with a button to whisper the recruiter.")
			grEmpty:Show()
		else
			grEmpty:Hide()
		end
	end

	local function resetText(secs)
		if secs <= 0 then return "resetting" end
		local d = math.floor(secs / 86400); local h = math.floor((secs % 86400) / 3600)
		if d > 0 then return ("resets in %dd %dh"):format(d, h) end
		return ("resets in %dh %dm"):format(h, math.floor((secs % 3600) / 60))
	end

	local function paintPug()
		-- raids asking for people
		local RS = Okanvil.RaidFinder_Shared
		local list = (RS and RS.module_on and RS.module_on() and RS.get_view and RS.get_view()) or {}
		for i, r in ipairs(lfRows) do
			local info = list[i]
			if info then
				r.l:SetText((RS.raid_label and RS.raid_label(info) or (info.instance or "?")) .. "  "
					.. (RS.roles_text and RS.roles_text(info.roles) or ""))
				r.r:SetText((info.sender or "") .. "  " .. (RS.age_text and RS.age_text(info) or ""))
				r:SetScript("OnClick", function() Okanvil:ShowPanel("Okanvil-RaidFinder") end)
				r:Show()
			else
				r:Hide()
			end
		end
		if #list == 0 then
			lfEmpty:SetText(Okanvil:IsModuleEnabled("Okanvil-RaidFinder")
				and "Nothing seen yet. Raid Finder reads LFM lines in chat while its page is open, "
					.. "or all the time with background scanning on (Raid Finder > Settings)."
				or "Raid Finder is off -- turn it on in Modules to see raids here.")
			lfEmpty:Show()
		else
			lfEmpty:Hide()
		end

		-- this character's lockouts
		local me = UnitName("player")
		local mine = {}
		local LK = Okanvil.Lockouts
		for _, row in ipairs((LK and LK.Get and LK:Get()) or {}) do
			if row.name == me then mine = row.instances or {} end
		end
		local now = time()
		for i, r in ipairs(lkRows) do
			local inst = mine[i]
			if inst then
				local size = (inst.diff == 2 or inst.diff == 4) and "25" or "10"
				r.l:SetText(inst.name .. "  |cff8a8d93" .. size .. (inst.heroic and " HC" or "") .. "|r")
				r.r:SetText(resetText((inst.resets or now) - now))
				r:SetScript("OnClick", nil)
				r:Show()
			else
				r:Hide()
			end
		end
		if #mine == 0 then
			lkEmpty:SetText("Not saved to any raid -- free to join anything.")
			lkEmpty:Show()
		else
			lkEmpty:Hide()
		end

		paintRecruit()
	end
	pug:SetScript("OnShow", paintPug)
	pug:SetScript("OnUpdate", function(self, el)
		self._t = (self._t or 0) + el
		if self._t < 5 then return end
		self._t = 0
		paintPug()
	end)

	local guildParts = { tiles._t1, tiles._t2, tiles._t3, tiles._t4, tabOnline, tabSnaps, gcard, scard }
	local function setPugMode(on)
		if on then
			for _, f in ipairs(guildParts) do f:Hide() end
			exportBtn:Hide()
			bRF:SetShown(Okanvil:IsModuleEnabled("Okanvil-RaidFinder"))
			bPug:SetShown(Okanvil:IsModuleEnabled("Okanvil-PuG"))
			pug:Show()
		elseif pug:IsShown() then
			pug:Hide()
			for i = 1, 4 do tiles["_t" .. i]:Show() end
			tabOnline:Show()
			tabSnaps:SetShown(Okanvil:IsModuleEnabled("__guild"))
			showTab("online")
		end
	end

	local function refreshGuild()
		if not (IsInGuild and IsInGuild()) then
			setPugMode(true)
			return
		end
		setPugMode(false)
		local online, mine, mineIdx = 0, "--", nil
		local raiders, sewers = 0, 0
		-- "Raiders" = officers and the rank just below them; everyone deeper is the
		-- rest of the roster. Derived from how many ranks the guild actually has,
		-- so a four-rank guild and a ten-rank guild both split sensibly.
		local RAIDER_RANK = 2
		if Okanvil.U and Okanvil.U.guildRanks then
			local _, maxIdx = Okanvil.U.guildRanks()
			if maxIdx and maxIdx >= 2 then RAIDER_RANK = math.min(2, maxIdx - 1) end
		end
		local myName = UnitName and UnitName("player")
		local onlineList = {}
		-- Alt rule -- MUST match the RATS website (loot/history tools): an entry is an
		-- ALT if rankIndex == 4, OR its rank name contains "alt", OR its officer note
		-- starts with "<Main> alt". MEMBERS counts MAINS only (real people), not toons.
		local function isAlt(rankName, rankIndex, officernote)
			if rankIndex == 4 then return true end
			if rankName and rankName:lower():find("alt", 1, true) then return true end
			-- officer note like "Mainname alt" (site rule: /^(.+?)\s+alt\b/i)
			if officernote and officernote:lower():match("^.-%s+alt%f[%A]") then return true end
			return false
		end
		-- Which MAIN does this alt belong to? Mirrors the RATS site mainOfG/altMainNote:
		--   1) officer note "Mainname alt ..." -> the word before "alt"
		--   2) else the first word of the public note if it looks like a name
		-- Returns nil if we can't tell.
		local function mainOf(publicnote, officernote)
			if officernote and officernote ~= "" then
				local m = officernote:match("^(.-)%s+[Aa][Ll][Tt]%f[%A]")
				if m and m ~= "" then return (m:gsub("^%s+", ""):gsub("%s+$", "")) end
			end
			-- The public note is mostly spec and PROFESSION text ("Master of
			-- Engineering", "Tank, 5.8k gs"), so only the explicit "<Main> alt" form
			-- names a main. Taking the first word of any note instead read a
			-- profession as a person -- "alt of Engineering".
			if publicnote and publicnote ~= "" then
				local m = publicnote:match("^(.-)%s+[Aa][Ll][Tt]%f[%A]")
				if m and m ~= "" then return (m:gsub("^%s+", ""):gsub("%s+$", "")) end
			end
			return nil
		end
		-- Rank ICON, mirroring the web hub's hierarchy (rats CLAUDE.md):
		--   "One hierarchy icon per member, highest wins: GM > Officer > Fang."
		-- On the site those are the emoji crown/star/skull; here we use the game's
		-- own textures so it reads native. Everyone below Fang gets no icon --
		-- the rank column already spells it out, and a row of dots is just noise.
		-- Class colour for the NAME. GetGuildRosterInfo hands back the LOCALIZED
		-- class name ("Paladin"), but RAID_CLASS_COLORS is keyed by TOKEN
		-- ("PALADIN") -- look the token up instead of colouring everyone gold.
		local classToken = {}
		for token, localized in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classToken[localized] = token end
		for token, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classToken[localized] = token end
		local function classHex(localizedClass)
			local tok = classToken[localizedClass or ""] or (localizedClass or ""):upper()
			local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[tok]
			if not c then return "ffdcddde" end       -- unknown class: plain text colour
			return string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
		end

		-- rank colour, still used for the RANK column + the "your rank" tile. The
		-- NAME is class-coloured instead (far easier to read at a glance), and the
		-- rank is conveyed by the icon in front of it.
		-- Colour by rank POSITION, never by rank NAME. This used to match on one
		-- guild's words ("warchief rat", "sewer"), so every other guild that
		-- installed Okanvil got a roster of identical grey rows.
		local function rankColor(rankName, rankIndex, alt)
			if alt then return "ff8fb4d9" end            -- alt: muted blue-grey
			if Okanvil.U and Okanvil.U.rankColor then return Okanvil.U.rankColor(rankIndex) end
			return "ff9aa0a6"
		end
		-- Walk the FULL roster (offline included) without leaving Blizzard's "Show
		-- Offline" checkbox stuck on -- see Okanvil:WithFullRoster.
		Okanvil:WithFullRoster(function(total)
			for i = 1, total do
				-- 3.3.5: name, rank, rankIndex, level, class, zone, publicnote, officernote, online
				local name, rank, rankIndex, _, class, zone, publicnote, officernote, isOnline = GetGuildRosterInfo(i)
				if name then
					local alt = isAlt(rank, rankIndex, officernote)
					if not alt then
						-- By POSITION, not by rank name: the first rank below the
						-- officers is "the raiders", and everything under it is the
						-- rest of the roster. Matching names counted nothing at all in
						-- a guild that had not picked this guild's words.
						if rankIndex and rankIndex <= RAIDER_RANK then raiders = raiders + 1
						elseif rankIndex then sewers = sewers + 1 end
					end
					if isOnline then
						online = online + 1
						onlineList[#onlineList + 1] = {
							name = name, rank = rank or "", rankIndex = rankIndex or 99, class = class,
							col = rankColor(rank, rankIndex, alt), alt = alt,
							nameCol = classHex(class),   -- NAME is class-coloured
							classTok = classToken[class or ""] or (class or ""):upper(),
							zone = zone or "",
							main = alt and mainOf(publicnote, officernote) or nil,
						}
					end
					if name == myName then mine = rank or "--"; mineIdx = rankIndex end
				end
			end
		end)
		tiles.online.num:SetText(tostring(online))
		tiles.raiders.num:SetText(tostring(raiders))
		tiles.sewers.num:SetText(tostring(sewers))
		-- Label the two rank tiles with the guild's OWN words, now that the roster
		-- has told us what they are. "RAIDERS/SEWERS" were this guild's names and
		-- read as nonsense anywhere else.
		if Okanvil.U and Okanvil.U.rankName then
			if tiles.raiders.lbl then
				tiles.raiders.lbl:SetText((Okanvil.U.rankName(RAIDER_RANK) or "RAIDERS"):upper())
			end
			if tiles.sewers.lbl then
				local low = Okanvil.U.lowestRankIndex and Okanvil.U.lowestRankIndex()
				tiles.sewers.lbl:SetText(low and (Okanvil.U.rankName(low) or "MEMBERS"):upper() or "MEMBERS")
			end
		end
		-- your rank, coloured with the SAME rank colour used in the online list. Keep
		-- the shared value size so it lines up with the two numbers; only step down a
		-- point if a very long rank name would clip the tile.
		local myCol = rankColor(mine, mineIdx, false)
		tiles.rank.num._okSize = nil
		tiles.rank.num:SetFont(Okanvil:Font(), (#mine > 16) and (VAL_SZ - 3) or VAL_SZ)
		tiles.rank.num:SetText("|c" .. myCol .. mine .. "|r")

		-- render the online list as scrollable rows, each with a quick [inv] button.
		-- Order: Rat King > Warchief > Raider > Sewer > ... , alts ALWAYS last
		-- (regardless of their own rankIndex), then by CLASS within a tier, then
		-- alphabetical. Grouping by class puts the row colours in blocks, so you
		-- can see at a glance which classes are on without reading every name --
		-- the question you are actually asking when you open this list.
		table.sort(onlineList, function(a, b)
			if a.alt ~= b.alt then return not a.alt end          -- alts sink to the bottom
			if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
			local ca, cb = a.classTok or "", b.classTok or ""
			if ca ~= cb then return ca < cb end
			return a.name:lower() < b.name:lower()
		end)
		-- three ALIGNED columns per row so it reads like a clean table:
		--   [name]        [rank]              [-> main]   [inv]
		-- name left, rank at a fixed x, main right-aligned before the inv button.
		-- Row height and text follow the user's font size: at 20px with fixed 12pt
		-- text the list was a dense block, and picking the right person to invite
		-- meant reading carefully. A separator and a hover highlight make each row
		-- a distinct thing you are clicking.
		local _, gfs = Okanvil:Font()
		gfs = gfs or 12
		local rows, ROWH = wrap.gRows, gfs + 26
		local ICON_SZ = math.min(ROWH - 12, 26)
		-- 190, not 130: at 130 the name column was ~82px and truncated anything
		-- longer than "Padrebocado". Rank text is short, so it can start later.
		local RANK_X = 190   -- fixed left edge of the rank column
		local ZONE_W = 150   -- width of the right-aligned zone column
		for _, r in ipairs(rows) do r:Hide() end
		for k, m in ipairs(onlineList) do
			local row = rows[k]
			if not row then
				row = CreateFrame("Frame", nil, wrap.gchild)
				row:SetHeight(ROWH)
				-- Class icon, the way the Loot priority list leads each row with the
				-- item icon: something to aim at before reading anything. Uses the
				-- client's own class sheet, cropped per class by CLASS_ICON_TCOORDS.
				row.cls = row:CreateTexture(nil, "ARTWORK")
				row.cls:SetTexture("Interface\\WorldStateFrame\\ICONS-CLASSES")
				row.cls:SetPoint("LEFT", 8, 0)
				row.name = row:CreateFontString(nil, "OVERLAY")
				row.name:SetFont(Okanvil:Font(), gfs + 1)
				-- 10px in: the bullet that used to hold this gutter is gone, so the name
				-- would otherwise sit flush against the card edge.
				row.name:SetPoint("LEFT", 10 + ICON_SZ + 6, 0); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
				row.rank = row:CreateFontString(nil, "OVERLAY")
				row.rank:SetFont(Okanvil:Font(), gfs)
				row.rank:SetPoint("LEFT", RANK_X, 0); row.rank:SetJustifyH("LEFT"); row.rank:SetWordWrap(false)
				-- main column sits right AFTER the rank text (close to the name), not
				-- pushed to the far right edge.
				row.main = row:CreateFontString(nil, "OVERLAY")
				row.main:SetFont(Okanvil:Font(), gfs - 1)
				row.main:SetPoint("LEFT", RANK_X + 84, 0); row.main:SetJustifyH("LEFT"); row.main:SetWordWrap(false)
				-- hairline under each row, and a highlight under the cursor: this list
				-- is clicked, so the row you are about to invite must be obvious.
				row.sep = row:CreateTexture(nil, "BACKGROUND")
				row.sep:SetTexture("Interface\\Buttons\\WHITE8x8")
				row.sep:SetVertexColor(1, 1, 1, 0.06)
				row.sep:SetHeight(1)
				row.sep:SetPoint("BOTTOMLEFT", 6, 0)
				row.sep:SetPoint("BOTTOMRIGHT", -6, 0)
				row.hl = row:CreateTexture(nil, "BACKGROUND")
				row.hl:SetTexture("Interface\\Buttons\\WHITE8x8")
				row.hl:SetVertexColor(1, 1, 1, 0.05)
				row.hl:SetPoint("TOPLEFT", 2, 0)
				row.hl:SetPoint("BOTTOMRIGHT", -2, 1)
				row.hl:Hide()
				row:EnableMouse(true)
				row:SetScript("OnEnter", function(self) self.hl:Show() end)
				row:SetScript("OnLeave", function(self) self.hl:Hide() end)
				-- A mouse-enabled child EATS the wheel, so with rows on screen the
				-- list stopped scrolling everywhere except the empty space below it.
				-- Hand the wheel back to the scrollframe that owns the list.
				row:EnableMouseWheel(true)
				row:SetScript("OnMouseWheel", function(self, d)
					local sb = wrap.gsb
					-- step by the row's CURRENT height: the closure is created once, so
					-- capturing ROWH would keep scrolling by the old size after a font change
					if sb then sb:SetValue(sb:GetValue() - d * (self:GetHeight() or 24)) end
				end)

				-- Whisper sits on the OUTSIDE, inv keeps its place.
				--
				-- Anchoring the new button to the row's right edge and hanging inv off
				-- it leaves inv where the eye already expects it, and the zone column
				-- reflows on its own because it is anchored to inv rather than to a
				-- measured width.
				row.wbtn = W.Button(row, "w", "secondary")
				row.wbtn:SetSize(22, math.max(15, gfs + 5)); row.wbtn:SetPoint("RIGHT", -10, 0)
				row.wbtn:Tooltip("Whisper")

				row.btn = W.Button(row, "inv", "secondary")
				row.btn:SetSize(38, math.max(15, gfs + 5))
				row.btn:SetPoint("RIGHT", row.wbtn, "LEFT", -4, 0)
				row.btn:Tooltip("Invite to your group/raid")
				Okanvil.UI.HoverReveal(row, { row.btn, row.wbtn })
				-- zone column: current location, right-aligned just left of the inv
				-- button (like the default Blizzard guild list's location column).
				row.zone = row:CreateFontString(nil, "OVERLAY")
				row.zone:SetFont(Okanvil:Font(), gfs - 1)
				row.zone:SetPoint("RIGHT", row.btn, "LEFT", -8, 0)
				row.zone:SetJustifyH("RIGHT"); row.zone:SetWordWrap(false)
				row.zone:SetWidth(ZONE_W)
				-- main column ends where the zone begins (avoids overlap on alts).
				-- Set once here; the LEFT point is already fixed above.
				row.main:SetPoint("RIGHT", row.zone, "LEFT", -8, 0)
				rows[k] = row
			end
			-- Anchored, not SetWidth: a measured width freezes at whatever the card
			-- was when the row was built, so a window-scale change left the rows
			-- narrower than the card. The snapshot rows already anchor this way.
			row:SetHeight(ROWH)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -(k - 1) * ROWH)
			row:SetPoint("RIGHT", wrap.gchild, "RIGHT", 0, 0)
			row:Show()
			-- Rows are built once and reused, so re-apply the sizes every refresh:
			-- otherwise moving the font slider leaves the existing rows at the size
			-- they were created with and only new ones pick the change up.
			row.name:SetFont(Okanvil:Font(), gfs + 1)
			row.rank:SetFont(Okanvil:Font(), gfs)
			row.main:SetFont(Okanvil:Font(), gfs - 1)
			row.zone:SetFont(Okanvil:Font(), gfs - 1)
			if row.btn then row.btn:SetSize(38, math.max(15, gfs + 5)) end
			if row.wbtn then row.wbtn:SetSize(22, math.max(15, gfs + 5)) end
			-- name column has a fixed right bound so it never runs into the rank column
			row.name:SetPoint("RIGHT", row, "LEFT", RANK_X - 6, 0)
			-- Just the name, class-coloured. No bullet, no icon: the rank is carried by
			-- its own colour in the rank column, so the name column stays clean.
			-- crop the shared class sheet to this class; unknown class -> hide rather
			-- than show the whole sheet squashed into one square

			row.cls:SetSize(ICON_SZ, ICON_SZ)
			local tok = m.classTok
			local tc = tok and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[tok]
			if tc then
				row.cls:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
				row.cls:Show()
			else
				row.cls:Hide()
			end
			row.name:SetText("|c" .. m.nameCol .. m.name .. "|r")
			row.rank:SetText("|c" .. m.col .. m.rank .. "|r")
			-- alt -> show the main it belongs to, aligned in its own right column
			if m.alt and m.main then
				row.main:SetText("|cff6a6d73of |r|cffbfc4cc" .. m.main .. "|r")
			else
				row.main:SetText("")
			end
			-- zone (current location), dim so the name/rank stay dominant
			row.zone:SetText(m.zone ~= "" and ("|cff8a8d93" .. m.zone .. "|r") or "")
			local who = m.name
			row.btn.text:SetText("inv")
			row.btn:SetScript("OnClick", function()
				if InviteUnit then InviteUnit(who) else GuildInvite(who) end
			end)
			row.btn._allowed = (who ~= myName)

			-- Open the chat box addressed to them rather than sending anything: a
			-- button that fired a message off on one click would be a button you
			-- could not take back.
			--
			-- ChatFrame_SendTell is a Blizzard UI helper, so a UI replacement can
			-- have removed it -- same guard and fallback RaidFinder's whisper uses.
			row.wbtn:SetScript("OnClick", function()
				if ChatFrame_SendTell then
					ChatFrame_SendTell(who)
				elseif ChatEdit_ActivateChat and ChatFrame1EditBox then
					ChatFrame1EditBox:SetAttribute("chatType", "WHISPER")
					ChatFrame1EditBox:SetAttribute("tellTarget", who)
					ChatEdit_ActivateChat(ChatFrame1EditBox)
				else
					Okanvil:Print("|cffff5555Could not open a whisper window.|r")
				end
			end)
			row.wbtn._allowed = (who ~= myName)
			row._revealUpdate()
		end
		local h = math.max(1, #onlineList * ROWH)
		wrap.gchild:SetHeight(h); wrap.gchild:SetWidth(wrap.gsf:GetWidth())
		local maxs = math.max(0, h - wrap.gsf:GetHeight())
		wrap.gsb:SetMinMaxValues(0, maxs); wrap.gsb:SetShown(maxs > 4)
		wrap.gempty:SetText(#onlineList == 0 and "|cff888888Nobody online.|r" or "")
	end

	-- Re-measure when the card resizes. The snapshots card already did this; the
	-- online one did not, so after a window-scale change its scrollbar range was
	-- computed against the old height -- a bar that stopped short of the last rows.
	-- Only the RANGE is recomputed: refreshGuild() walks the whole guild roster,
	-- which is far too much work to run on every frame of a resize.
	gsf:SetScript("OnSizeChanged", function(self)
		local child = wrap.gchild
		if not (child and wrap.gsb) then return end
		child:SetWidth(math.max(40, self:GetWidth()))
		local maxs = math.max(0, child:GetHeight() - self:GetHeight())
		wrap.gsb:SetMinMaxValues(0, maxs)
		wrap.gsb:SetShown(maxs > 4)
	end)

	-- live-update on roster changes (login/logoff), not just when the panel opens.
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("GUILD_ROSTER_UPDATE")
	ev:SetScript("OnEvent", function()
		-- Ignore roster events WE caused: WithFullRoster toggles Show-Offline, which
		-- fires GUILD_ROSTER_UPDATE, which would call refreshGuild -> WithFullRoster
		-- again -> a C stack overflow. rosterBusy stays set across that async event.
		if Okanvil.rosterBusy then return end
		if wrap:IsShown() then
			-- Same ordering as OnShow: the card must be sized before the row list
			-- measures it, or someone logging in while you watch re-renders the list
			-- against a stale height.
			p:SetHeight(math.max(wrap.scroll:GetHeight(), 1))
			refreshGuild()
		end
	end)

	local onShow
	wrap:SetScript("OnShow", function()
		local ok, err = pcall(onShow)
		if not ok then Okanvil:Err("Home OnShow", err); Okanvil:Trace("UI", "Home OnShow failed: " .. tostring(err)) end
	end)
	onShow = function()
		if GuildRoster then GuildRoster() end   -- async; GUILD_ROSTER_UPDATE fires when ready
		-- Width before anything is laid out: the page starts 10px wide, and building
		-- the rows against that gave them negative widths.
		wrap.relayout()
		-- The page takes the VIEW's height, never a fixed minimum. It used to floor
		-- at 640, which is taller than the window: the guild card is anchored to this
		-- frame's BOTTOM, so it stretched past the view and its own scrollbar range
		-- came out as zero -- a full guild ran off the bottom with no way to scroll
		-- to it, because the outer scroll and the card's scroll were fighting.
		-- Height FIRST, rows second. The guild card's BOTTOM is anchored to `p`, so
		-- until p has its final height the card is the wrong size -- and refreshGuild
		-- measures gsf:GetHeight() to decide whether the list needs a scrollbar. Doing
		-- it the other way round measured a stale height, so with a full guild online
		-- the rows ran off the bottom of the card with no scrollbar to reach them.
		p:SetHeight(math.max(wrap.scroll:GetHeight(), 1))
		refreshGuild()
		-- Prime the FULL roster: GetGuildRosterInfo only returns offline members
		-- once the client has fetched them, and an export taken before that is
		-- only whoever was online -- the "238 left the guild" bug.
		if IsInGuild and IsInGuild() and SetGuildRosterShowOffline then
			SetGuildRosterShowOffline(true)
		end
		if wrap.rebuildSnaps and scard:IsShown() then wrap.rebuildSnaps() end
		wrap.relayout()
	end
	return wrap
end

-- ------------------------------------------------------------
-- Guild (native) -- roster export + raid attendance snapshots
-- ------------------------------------------------------------
