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
	local gb = self.db.brand
	local guildFS
	if gb and gb ~= "" and gb ~= "Okanvil" then
		guildFS = W.Text(p, gb, "head", "accent"); guildFS:Color(0.88, 0.72, 0.38)
		guildFS:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
		anchor = guildFS
	end
	local sub = W.Text(p, "v" .. (self.version or "1.0") .. "  --  raid & guild toolkit by Okanor", "label", "dim")
	sub:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)

	-- stat tiles: online / raiders / sewers / your rank. Anchored to the header's
	-- (the `sub` line) so a 2- or 3-line header never overlaps them.
	-- Three identical tiles in one row. All values share the SAME font size and
	-- baseline so numbers and the rank name read as one aligned row (a big "20pt
	-- number" next to a "Warchief Rat" name looked like uneven steps before).
	local TILE_W, TILE_H, VAL_SZ = 132, 48, 17
	-- the rank tile holds a NAME, not a number, so it gets the room a name needs
	local RANK_W = 190
	local tiles = {}
	local function tile(i, label)
		local t = W.Frame(p, "input")
		-- the rank tile holds a NAME, not a number, so it gets the width one needs
		t:SetSize((label == "YOUR RANK") and RANK_W or TILE_W, TILE_H)
		if i == 1 then
			t:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
		else
			t:SetPoint("TOPLEFT", tiles["_t" .. (i - 1)], "TOPRIGHT", 8, 0)
		end
		-- label pinned near the bottom; the value sits just above it, so all three
		-- values line up on the same baseline regardless of number vs name.
		t.lbl = W.Text(t, label, "note", "dim"); t.lbl:SetPoint("BOTTOMLEFT", 12, 8)
		t.num = W.Text(t, "--", VAL_SZ, "accent")
		t.num:SetPoint("BOTTOMLEFT", t.lbl, "TOPLEFT", 0, 5); t.num:SetPoint("RIGHT", t, "RIGHT", -10, 0); t.num:SetJustifyH("LEFT")
		if t.num.SetWordWrap then t.num:SetWordWrap(false) end
		tiles["_t" .. i] = t
		return t
	end
	tiles.online = tile(1, "ONLINE")
	-- Raider and Sewer counts instead of a MAINS total: "how many raiders do we
	-- have" is the question actually asked, and a combined total answered none of
	-- it. Alts are excluded from both, the way MAINS excluded them.
	tiles.raiders = tile(2, "RAIDERS")
	tiles.sewers = tile(3, "SEWERS")
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
	local tabOnline = W.Button(p, "Online", "primary")
	tabOnline:SetSize(88, 22)
	tabOnline:SetPoint("TOPLEFT", tiles._t1, "BOTTOMLEFT", 0, -10)
	local tabSnaps = W.Button(p, "Snapshots")
	tabSnaps:SetSize(96, 22)
	tabSnaps:SetPoint("LEFT", tabOnline, "RIGHT", 6, 0)
	local exportBtn = W.Button(p, "Export roster")
	exportBtn:SetSize(110, 22)
	exportBtn:SetPoint("RIGHT", p, "RIGHT", -X, 0)
	exportBtn:SetPoint("TOP", tabOnline, "TOP", 0, 0)
	exportBtn:Tooltip("Build the roster JSON the web hub imports.")
	exportBtn:SetScript("OnClick", function()
		local G = Okanvil.Guild
		if not (G and G.ExportRoster) then Okanvil:Print("Guild module not loaded."); return end
		-- async: the offline members have to finish loading or the export is only
		-- whoever happened to be online
		G.ExportRoster(function(json) Okanvil:ShowExport(json, "Guild roster") end)
	end)

	local gcard = W.Frame(p, "input")
	gcard:SetPoint("TOPLEFT", tabOnline, "BOTTOMLEFT", 0, -10)
	gcard:SetPoint("RIGHT", p, "RIGHT", -X, 0)
	gcard:SetPoint("BOTTOM", p, "BOTTOM", 0, 12)
	gcard:SetHeight(180)   -- fallback min; the BOTTOM anchor stretches it taller
	local gh = W.Text(gcard, "GUILD ONLINE", "note", "dim"); gh:SetPoint("TOPLEFT", 10, -8)
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
	-- Ported from the old Guild page rather than rewritten: this row layout and its
	-- inline expansion already work, and attendance is data you cannot re-capture
	-- if a rewrite gets it wrong.
	local scard = W.Frame(p, "input")
	scard:SetAllPoints(gcard)
	local sh = W.Text(scard, "SAVED SNAPSHOTS", "note", "dim"); sh:SetPoint("TOPLEFT", 10, -8)
	local snapNow = W.Button(scard, "Snapshot group now")
	snapNow:SetSize(150, 22); snapNow:SetPoint("TOPRIGHT", -10, -4)
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
	-- three columns of names when a snapshot is expanded: a 25-man is five
	-- groups of five, which fits three-across without scrolling
	local SNAP_COLS = 3
	wrap.snapRows, wrap.snapDetail, wrap.snapOpen = {}, {}, nil

	local function rebuildSnaps()
		local G = Okanvil.Guild
		for _, r in ipairs(wrap.snapRows) do r:Hide() end
		for _, set in ipairs(wrap.snapDetail) do
			for _, t in ipairs(set) do t:Hide() end
		end
		local snaps = (Okanvil.db.guild and Okanvil.db.guild.snapshots) or {}
		schild:SetWidth(math.max(40, ssf:GetWidth()))
		if #snaps == 0 or not G then
			wrap.snapEmpty = wrap.snapEmpty or W.Text(schild, "", "body", "dim")
			wrap.snapEmpty:ClearAllPoints(); wrap.snapEmpty:SetPoint("TOPLEFT", 4, -6)
			wrap.snapEmpty:SetText(G and "|cff888888No snapshots yet. They save at the first pull, or use the button above.|r"
				or "|cff888888Guild module not loaded.|r")
			wrap.snapEmpty:Show(); schild:SetHeight(40); ssb:SetShown(false); return
		end
		if wrap.snapEmpty then wrap.snapEmpty:Hide() end

		local di, y = 0, 0
		for i, snap in ipairs(snaps) do
			local r = wrap.snapRows[i]
			if not r then
				r = W.Frame(schild, "dark")
				r.title = W.Text(r, "", "body"); r.title:SetPoint("TOPLEFT", 10, -6)
				r.sub = W.Text(r, "", "note", "dim"); r.sub:SetPoint("BOTTOMLEFT", 10, 6)
				r.del = W.Button(r, "X", "danger"); r.del:SetSize(24, 22); r.del:SetPoint("RIGHT", -8, 0)
				r.export = W.Button(r, "Export"); r.export:SetSize(72, 22); r.export:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
				r.view = W.Button(r, "View"); r.view:SetSize(60, 22); r.view:SetPoint("RIGHT", r.export, "LEFT", -6, 0)
				r.inv = W.Button(r, "Invite", "primary"); r.inv:SetSize(60, 22)
				r.inv:SetPoint("RIGHT", r.view, "LEFT", -6, 0)
				r:EnableMouse(true)
				wrap.snapRows[i] = r
			end
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", schild, "RIGHT", 0, 0)
			r:SetHeight(40)
			local dateStr = date("%b %d  %H:%M", snap.t)
			local where = (snap.zone ~= "" and snap.zone) or "Unknown"
			local isOpen = (wrap.snapOpen == snap)
			r.title:SetText((isOpen and "|cffffd200v|r  " or "|cff8a8d93>|r  ")
				.. where .. ((snap.boss or "") ~= "" and ("  |cff8a8d93-- " .. snap.boss .. "|r") or ""))
			r.sub:SetText(dateStr .. "  |cff8a8d93|  " .. (snap.count or 0) .. " players  |  " .. (snap.trigger or "") .. "|r")
			r.view.text:SetText(isOpen and "Close" or "View")
			r.view:SetScript("OnClick", function()
				-- if/else, NOT "cond and nil or snap": that idiom cannot yield nil,
				-- because `and nil` is falsy so the `or` branch always wins. Written
				-- as a ternary this row could open but never close.
				if wrap.snapOpen == snap then
					wrap.snapOpen = nil
				else
					wrap.snapOpen = snap
				end
				rebuildSnaps()
			end)
			r.export:SetScript("OnClick", function()
				Okanvil:ShowExport(G.SnapshotJSON(snap), "Attendance -- " .. dateStr)
			end)
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
			y = y + 46
			if isOpen then
				-- Three columns, bigger text. One column ran the groups straight down
				-- and left two thirds of a 900px card empty, so a 25-man snapshot
				-- scrolled for no reason.
				di = di + 1
				local set = wrap.snapDetail[di]
				if not set then
					set = {}
					for c = 1, SNAP_COLS do
						local t = W.Text(schild, "", "body")
						t:SetJustifyH("LEFT")
						t:SetJustifyV("TOP")
						-- NO SetWordWrap(false) here. It is right for the one-line row
						-- labels this was copied from, but each column is a MULTI-LINE
						-- block ("Group 1\n  Name\n  Name"): wrapping off collapses the
						-- whole thing to one truncated line -- "Group 1...".
						set[c] = t
					end
					wrap.snapDetail[di] = set
				end
				local cols = G.SnapshotColumns and G.SnapshotColumns(snap, SNAP_COLS)
					or { G.SnapshotBodyText(snap) }
				local colW = math.max(80, (schild:GetWidth() - 28) / SNAP_COLS)
				-- Height from the LINE COUNT, not GetStringHeight(): a font string
				-- measures 0 until WoW has laid it out, which is the same frame we
				-- are positioning in. Measuring there left `tallest` at 0, so the
				-- next row drew straight on top of this expansion -- covering its
				-- own Close button, which is why Close appeared dead.
				local LINE_H = 15
				local mostLines = 0
				for c = 1, SNAP_COLS do
					local t = set[c]
					local txt = cols[c] or ""
					t:ClearAllPoints()
					t:SetPoint("TOPLEFT", 14 + (c - 1) * colW, -y)
					t:SetWidth(colW - 8)
					t:SetText(txt)
					t:Show()
					local n = 0
					if txt ~= "" then
						n = 1
						for _ in txt:gmatch("\n") do n = n + 1 end
					end
					if n > mostLines then mostLines = n end
				end
				y = y + mostLines * LINE_H + 12
			end
		end
		schild:SetHeight(math.max(1, y))
		local maxs = math.max(0, y - ssf:GetHeight())
		ssb:SetMinMaxValues(0, maxs); ssb:SetShown(maxs > 4)
	end
	wrap.rebuildSnaps = rebuildSnaps

	snapNow:SetScript("OnClick", function()
		local G = Okanvil.Guild
		if not (G and G.SaveSnapshot) then return end
		local snap, err = G.SaveSnapshot("manual")
		if not snap then Okanvil:Print("Snapshot failed: " .. (err or "?"))
		else wrap.snapOpen = snap; rebuildSnaps() end
	end)
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
		if snaps then tabOnline:SetKind(nil) else tabOnline:SetKind("primary") end
		tabSnaps:SetKind(snaps and "primary" or nil)
		if snaps then rebuildSnaps() end
	end
	tabOnline:SetScript("OnClick", function() showTab("online") end)
	tabSnaps:SetScript("OnClick", function() showTab("snaps") end)

	-- (The web-hub link now lives in the window FOOTER, WeakAuras-style -- always
	-- visible, click to copy the URL. No card here anymore.)

	-- (rat art is one shared overlay on Okanvil.content -- nothing to build here.)

	local function refreshGuild()
		if not (IsInGuild and IsInGuild()) then
			tiles.online.num:SetText("--"); tiles.rank.num:SetText("--")
			tiles.raiders.num:SetText("--"); tiles.sewers.num:SetText("--")
			for _, r in ipairs(wrap.gRows) do r:Hide() end
			if wrap.gsb then wrap.gsb:Hide() end
			wrap.gempty:SetText("|cff888888You are not in a guild.|r")
			return
		end
		local online, mine, mineIdx = 0, "--", nil
		local raiders, sewers = 0, 0
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
		local function rankColor(rankName, rankIndex, alt)
			if alt then return "ff8fb4d9" end            -- alt: muted blue-grey
			local rn = (rankName or ""):lower()
			-- Guild Master / Rat King ("King Rat" / "Rat King") -> purple
			if rankIndex == 0 or rn:find("king", 1, true) then return "ffc659ff" end
			if rn:find("warchief rat", 1, true) then return "ffff4d4d" end   -- Warchief Rat: officer red
			if rn:find("raider", 1, true) then return "ffffa030" end          -- Raider Rat: orange
			if rn:find("sewer", 1, true) then return "ffffe049" end           -- Sewer Rat: yellow
			return "ff9aa0a6"                                                  -- Pug / unranked: grey
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
						-- matched on the rank NAME, like rankColor above, so renaming a
						-- rank in game does not silently zero the count
						local rn = (rank or ""):lower()
						if rn:find("raider", 1, true) then raiders = raiders + 1
						elseif rn:find("sewer", 1, true) then sewers = sewers + 1 end
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
		-- your rank, coloured with the SAME rank colour used in the online list. Keep
		-- the shared value size so it lines up with the two numbers; only step down a
		-- point if a very long rank name would clip the tile.
		local myCol = rankColor(mine, mineIdx, false)
		tiles.rank.num._okSize = nil
		tiles.rank.num:SetFont(Okanvil:Font(), (#mine > 16) and (VAL_SZ - 3) or VAL_SZ)
		tiles.rank.num:SetText("|c" .. myCol .. mine .. "|r")

		-- render the online list as scrollable rows, each with a quick [inv] button.
		-- Order: Rat King > Warchief > Raider > Sewer > ... , alts ALWAYS last
		-- (regardless of their own rankIndex), then alphabetical within a tier.
		table.sort(onlineList, function(a, b)
			if a.alt ~= b.alt then return not a.alt end          -- alts sink to the bottom
			if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
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
				row.sep:SetVertexColor(1, 1, 1, 0.13)
				row.sep:SetHeight(1)
				row.sep:SetPoint("BOTTOMLEFT", 6, 0)
				row.sep:SetPoint("BOTTOMRIGHT", -6, 0)
				-- Alternating shade, the same trick the hub's lists use
				-- (.row:nth-child(odd)): the eye tracks a row across to the zone
				-- column without drifting onto the next one.
				row.zebra = row:CreateTexture(nil, "BACKGROUND")
				row.zebra:SetTexture("Interface\\Buttons\\WHITE8x8")
				row.zebra:SetVertexColor(1, 1, 1, 0.022)
				row.zebra:SetPoint("TOPLEFT", 2, 0)
				row.zebra:SetPoint("BOTTOMRIGHT", -2, 1)
				-- ...and the rank's own colour down the left edge, like the hub's
				-- tier border, so a rank is recognisable before it is read.
				row.edge = row:CreateTexture(nil, "ARTWORK")
				row.edge:SetTexture("Interface\\Buttons\\WHITE8x8")
				row.edge:SetWidth(2)
				row.edge:SetPoint("TOPLEFT", 2, -2)
				row.edge:SetPoint("BOTTOMLEFT", 2, 3)

				row.hl = row:CreateTexture(nil, "BACKGROUND")
				row.hl:SetTexture("Interface\\Buttons\\WHITE8x8")
				row.hl:SetVertexColor(1, 1, 1, 0.10)
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

				row.btn = W.Button(row, "inv", "secondary")
				row.btn:SetSize(38, math.max(15, gfs + 5)); row.btn:SetPoint("RIGHT", -10, 0)
				row.btn:Tooltip("Invite to your group/raid")
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
			-- name column has a fixed right bound so it never runs into the rank column
			row.name:SetPoint("RIGHT", row, "LEFT", RANK_X - 6, 0)
			-- Just the name, class-coloured. No bullet, no icon: the rank is carried by
			-- its own colour in the rank column, so the name column stays clean.
			-- crop the shared class sheet to this class; unknown class -> hide rather
			-- than show the whole sheet squashed into one square
			-- shade every other row, and carry the rank colour down the left edge
			row.zebra:SetShown(k % 2 == 1)
			-- m.col is the same "aarrggbb" rankColor() feeds to |c, so the edge and
			-- the rank text can never disagree about what colour a rank is
			local er, eg, eb = 1, 1, 1
			if m.col and #m.col == 8 then
				er = (tonumber(m.col:sub(3, 4), 16) or 255) / 255
				eg = (tonumber(m.col:sub(5, 6), 16) or 255) / 255
				eb = (tonumber(m.col:sub(7, 8), 16) or 255) / 255
			end
			row.edge:SetVertexColor(er, eg, eb, 0.85)

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
			row.btn:SetShown(who ~= myName)
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
			p:SetHeight(math.max(wrap.scroll:GetHeight(), 640))
			refreshGuild()
		end
	end)

	wrap:SetScript("OnShow", function()
		if GuildRoster then GuildRoster() end   -- async; GUILD_ROSTER_UPDATE fires when ready
		-- Height FIRST, rows second. The guild card's BOTTOM is anchored to `p`, so
		-- until p has its final height the card is the wrong size -- and refreshGuild
		-- measures gsf:GetHeight() to decide whether the list needs a scrollbar. Doing
		-- it the other way round measured a stale height, so with a full guild online
		-- the rows ran off the bottom of the card with no scrollbar to reach them.
		p:SetHeight(math.max(wrap.scroll:GetHeight(), 640))
		refreshGuild()
		-- Prime the FULL roster: GetGuildRosterInfo only returns offline members
		-- once the client has fetched them, and an export taken before that is
		-- only whoever was online -- the "238 left the guild" bug.
		if IsInGuild and IsInGuild() and SetGuildRosterShowOffline then
			SetGuildRosterShowOffline(true)
		end
		if wrap.rebuildSnaps and scard:IsShown() then wrap.rebuildSnaps() end
		wrap.relayout()
	end)
	return wrap
end

-- ------------------------------------------------------------
-- Guild (native) -- roster export + raid attendance snapshots
-- ------------------------------------------------------------
