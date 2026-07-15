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
	local title = W.Text(p, "Okanvil", 26, "accent"); title:SetPoint("TOPLEFT", X, -20)
	local anchor = title
	-- guild skin (editable) as a subtitle under the product name
	local gb = self.db.brand
	local guildFS
	if gb and gb ~= "" and gb ~= "Okanvil" then
		guildFS = W.Text(p, gb, 14, "accent"); guildFS:Color(0.88, 0.72, 0.38)
		guildFS:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
		anchor = guildFS
	end
	local sub = W.Text(p, "v" .. (self.version or "1.0") .. "  --  raid & guild toolkit by Okanor", 11, "dim")
	sub:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)

	-- stat tiles: online / members / your rank. Anchored to the header's bottom
	-- (the `sub` line) so a 2- or 3-line header never overlaps them.
	-- Three identical tiles in one row. All values share the SAME font size and
	-- baseline so numbers and the rank name read as one aligned row (a big "20pt
	-- number" next to a "Warchief Rat" name looked like uneven steps before).
	local TILE_W, TILE_H, VAL_SZ = 150, 48, 17
	local tiles = {}
	local function tile(i, label)
		local t = W.Frame(p, "input")
		t:SetSize(TILE_W, TILE_H)
		if i == 1 then
			t:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
		else
			t:SetPoint("TOPLEFT", tiles["_t" .. (i - 1)], "TOPRIGHT", 8, 0)
		end
		-- label pinned near the bottom; the value sits just above it, so all three
		-- values line up on the same baseline regardless of number vs name.
		t.lbl = W.Text(t, label, 10, "dim"); t.lbl:SetPoint("BOTTOMLEFT", 12, 8)
		t.num = W.Text(t, "--", VAL_SZ, "accent")
		t.num:SetPoint("BOTTOMLEFT", t.lbl, "TOPLEFT", 0, 5); t.num:SetPoint("RIGHT", t, "RIGHT", -10, 0); t.num:SetJustifyH("LEFT")
		if t.num.SetWordWrap then t.num:SetWordWrap(false) end
		tiles["_t" .. i] = t
		return t
	end
	tiles.online = tile(1, "ONLINE")
	tiles.members = tile(2, "MAINS")
	tiles.rank = tile(3, "YOUR RANK")

	-- guild online card -- a SCROLLABLE row list (shows everyone, not a capped
	-- text blob) with a per-row [inv] button for quick invites from Home.
	-- The online card fills the rest of the page height (Home is a fixed-size
	-- window, so anchoring its bottom to the content area gives many more visible
	-- rows -> far less scrolling). BOTTOMRIGHT is the scroll area's real bottom.
	local gcard = W.Frame(p, "input")
	gcard:SetPoint("TOPLEFT", tiles._t1, "BOTTOMLEFT", 0, -12)
	gcard:SetPoint("RIGHT", p, "RIGHT", -X, 0)
	gcard:SetPoint("BOTTOM", p, "BOTTOM", 0, 12)
	gcard:SetHeight(180)   -- fallback min; the BOTTOM anchor stretches it taller
	local gh = W.Text(gcard, "GUILD ONLINE", 10, "dim"); gh:SetPoint("TOPLEFT", 10, -8)
	-- flat scroll (no Blizzard template): plain ScrollFrame + our own slider
	local gsf = CreateFrame("ScrollFrame", nil, gcard)
	gsf:SetPoint("TOPLEFT", 8, -24); gsf:SetPoint("BOTTOMRIGHT", -12, 6)
	local gchild = CreateFrame("Frame", nil, gsf); gchild:SetSize(10, 1)
	gsf:SetScrollChild(gchild)
	local gsb = CreateFrame("Slider", nil, gcard)
	gsb:SetPoint("TOPRIGHT", -3, -24); gsb:SetPoint("BOTTOMRIGHT", -3, 6); gsb:SetWidth(4)
	gsb:SetOrientation("VERTICAL"); gsb:SetValueStep(1)
	local gth = gsb:CreateTexture(nil, "OVERLAY"); gth:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	gth:SetSize(4, 30); local ga = Okanvil.Colors.accent; gth:SetVertexColor(ga[1], ga[2], ga[3], 1)
	gsb:SetThumbTexture(gth)
	gsb:SetScript("OnValueChanged", function(_, v) gsf:SetVerticalScroll(v) end)
	gsf:EnableMouseWheel(true)
	gsf:SetScript("OnMouseWheel", function(_, d) gsb:SetValue(gsb:GetValue() - d * 24) end)
	wrap.gsf, wrap.gchild, wrap.gsb, wrap.gRows = gsf, gchild, gsb, {}
	local gempty = W.Text(gcard, "", 12, "dim"); gempty:SetPoint("TOPLEFT", 10, -26)
	wrap.gempty = gempty

	-- (The web-hub link now lives in the window FOOTER, WeakAuras-style -- always
	-- visible, click to copy the URL. No card here anymore.)

	-- (rat art is one shared overlay on Okanvil.content -- nothing to build here.)

	local function refreshGuild()
		if not (IsInGuild and IsInGuild()) then
			tiles.online.num:SetText("--"); tiles.members.num:SetText("--"); tiles.rank.num:SetText("--")
			for _, r in ipairs(wrap.gRows) do r:Hide() end
			if wrap.gsb then wrap.gsb:Hide() end
			wrap.gempty:SetText("|cff888888You are not in a guild.|r")
			return
		end
		local online, mains, mine, mineIdx = 0, 0, "--", nil
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
			if publicnote and publicnote ~= "" then
				local first = publicnote:match("^%s*([A-Za-z\192-\255]+)")
				if first and #first >= 2 then return first end
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
			if rn:find("fang", 1, true) then return "ffff8c42" end            -- Warchief's Fangs: orange-red
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
					if not alt then mains = mains + 1 end
					if isOnline then
						online = online + 1
						onlineList[#onlineList + 1] = {
							name = name, rank = rank or "", rankIndex = rankIndex or 99, class = class,
							col = rankColor(rank, rankIndex, alt), alt = alt,
							nameCol = classHex(class),   -- NAME is class-coloured
							zone = zone or "",
							main = alt and mainOf(publicnote, officernote) or nil,
						}
					end
					if name == myName then mine = rank or "--"; mineIdx = rankIndex end
				end
			end
		end)
		tiles.online.num:SetText(tostring(online))
		tiles.members.num:SetText(tostring(mains))   -- MAINS only (real people, alts excluded)
		-- your rank, coloured with the SAME rank colour used in the online list. Keep
		-- the shared value size so it lines up with the two numbers; only step down a
		-- point if a very long rank name would clip the tile.
		local myCol = rankColor(mine, mineIdx, false)
		tiles.rank.num._okSize = nil
		tiles.rank.num:SetFont(Okanvil:Font(), (#mine > 12) and (VAL_SZ - 3) or VAL_SZ)
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
		local rows, ROWH = wrap.gRows, 20
		local RANK_X = 130   -- fixed left edge of the rank column
		local ZONE_W = 150   -- width of the right-aligned zone column
		for _, r in ipairs(rows) do r:Hide() end
		for k, m in ipairs(onlineList) do
			local row = rows[k]
			if not row then
				row = CreateFrame("Frame", nil, wrap.gchild)
				row:SetHeight(ROWH)
				row.name = row:CreateFontString(nil, "OVERLAY")
				row.name:SetFont(Okanvil:Font(), 12)
				-- 10px in: the bullet that used to hold this gutter is gone, so the name
				-- would otherwise sit flush against the card edge.
				row.name:SetPoint("LEFT", 10, 0); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
				row.rank = row:CreateFontString(nil, "OVERLAY")
				row.rank:SetFont(Okanvil:Font(), 12)
				row.rank:SetPoint("LEFT", RANK_X, 0); row.rank:SetJustifyH("LEFT"); row.rank:SetWordWrap(false)
				-- main column sits right AFTER the rank text (close to the name), not
				-- pushed to the far right edge.
				row.main = row:CreateFontString(nil, "OVERLAY")
				row.main:SetFont(Okanvil:Font(), 11)
				row.main:SetPoint("LEFT", RANK_X + 84, 0); row.main:SetJustifyH("LEFT"); row.main:SetWordWrap(false)
				row.btn = W.Button(row, "inv", "secondary")
				row.btn:SetSize(34, 15); row.btn:SetPoint("RIGHT", -4, 0)
				row.btn:Tooltip("Invite to your group/raid")
				-- zone column: current location, right-aligned just left of the inv
				-- button (like the default Blizzard guild list's location column).
				row.zone = row:CreateFontString(nil, "OVERLAY")
				row.zone:SetFont(Okanvil:Font(), 11)
				row.zone:SetPoint("RIGHT", row.btn, "LEFT", -8, 0)
				row.zone:SetJustifyH("RIGHT"); row.zone:SetWordWrap(false)
				row.zone:SetWidth(ZONE_W)
				-- main column ends where the zone begins (avoids overlap on alts).
				-- Set once here; the LEFT point is already fixed above.
				row.main:SetPoint("RIGHT", row.zone, "LEFT", -8, 0)
				rows[k] = row
			end
			row:SetWidth(wrap.gsf:GetWidth()); row:SetHeight(ROWH)
			row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(k - 1) * ROWH); row:Show()
			-- name column has a fixed right bound so it never runs into the rank column
			row.name:SetPoint("RIGHT", row, "LEFT", RANK_X - 6, 0)
			-- Just the name, class-coloured. No bullet, no icon: the rank is carried by
			-- its own colour in the rank column, so the name column stays clean.
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

	-- live-update on roster changes (login/logoff), not just when the panel opens.
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("GUILD_ROSTER_UPDATE")
	ev:SetScript("OnEvent", function()
		-- Ignore roster events WE caused: WithFullRoster toggles Show-Offline, which
		-- fires GUILD_ROSTER_UPDATE, which would call refreshGuild -> WithFullRoster
		-- again -> a C stack overflow. rosterBusy stays set across that async event.
		if Okanvil.rosterBusy then return end
		if wrap:IsShown() then refreshGuild() end
	end)

	wrap:SetScript("OnShow", function()
		if GuildRoster then GuildRoster() end   -- async; GUILD_ROSTER_UPDATE fires when ready
		refreshGuild()
		p:SetHeight(math.max(wrap.scroll:GetHeight(), 640))
		wrap.relayout()
	end)
	return wrap
end

-- ------------------------------------------------------------
-- Guild (native) -- roster export + raid attendance snapshots
-- ------------------------------------------------------------
