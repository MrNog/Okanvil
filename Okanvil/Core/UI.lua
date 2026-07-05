-- ============================================================
-- Okanvil -- UI shell: resizable window with a left nav, a clipped
-- scrolling content well, a Home page and a built-in Settings tab.
-- Built on Okanvil.W (Widgets.lua). Every panel lives inside a scrolling
-- child frame, so plugin widgets stay bounded by the content well and
-- never spill past the window edge -- the MRT structure the guild liked.
-- ============================================================

local Okanvil = Okanvil
local W = Okanvil.W
local C = Okanvil.Colors
local LSM = Okanvil.LSM
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local function u3(t, a) return t[1], t[2], t[3], a or 1 end

Okanvil.panels = {}       -- key -> { panel, scroll, child }
Okanvil._navButtons = {}
local HOME, GUILD, LOOT, INVITE, MODULES, SETTINGS = "__home", "__guild", "__loot", "__invite", "__modules", "__settings"

local MIN_W, MIN_H = 560, 400
local NAV_W = 190
local HEADER_H = 30
local FOOTER_H = 22

-- ------------------------------------------------------------
-- Nav entry (icon + label + active bar)
-- ------------------------------------------------------------
local function makeNavEntry(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(24)
	local hl = b:CreateTexture(nil, "BACKGROUND")
	hl:SetAllPoints(); hl:SetTexture(FLAT); hl:SetVertexColor(0, 0, 0, 0)
	b.hl = hl
	local bar = b:CreateTexture(nil, "ARTWORK")   -- left accent bar when active
	bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT"); bar:SetWidth(2)
	bar:SetTexture(FLAT); bar:SetVertexColor(u3(C.accent)); bar:Hide()
	b.bar = bar
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(15, 15); b.icon:SetPoint("LEFT", 8, 0)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.text = W.Text(b); b.text:SetPoint("LEFT", b.icon, "RIGHT", 7, 0); b.text:SetJustifyH("LEFT")
	b:SetScript("OnEnter", function(s) if not s._active then s.hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.08) end end)
	b:SetScript("OnLeave", function(s) if not s._active then s.hl:SetVertexColor(0, 0, 0, 0) end end)
	return b
end

-- ------------------------------------------------------------
-- Shell (window)
-- ------------------------------------------------------------
function Okanvil:BuildShell()
	if self.win then return end
	local db = self.db

	local f = CreateFrame("Frame", "Okanvil_Window", UIParent)
	f:SetSize(db.window.width, db.window.height)
	f:SetPoint(db.window.point, UIParent, db.window.point, db.window.x, db.window.y)
	f:SetScale(db.scale or 1)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetResizable(true)
	-- robust min-size: SetResizeBounds (modern) / SetMinResize (3.3.5) / manual clamp
	if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H)
	elseif f.SetMinResize then f:SetMinResize(MIN_W, MIN_H) end
	self:Skin(f)
	self.win = f

	-- header (drag)
	local hdr = W.Frame(f, "raise")
	hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1); hdr:SetHeight(HEADER_H)
	hdr:EnableMouse(true); hdr:RegisterForDrag("LeftButton")
	hdr:SetScript("OnDragStart", function() f:StartMoving() end)
	hdr:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local p, _, _, x, y = f:GetPoint(1)
		db.window.point, db.window.x, db.window.y = p, x, y
	end)

	-- ---- product wordmark: [anvil] Okanvil ("OK Anvil" pun lives in the word) ----
	-- The product name is FIXED (Okanvil, by Okanor); only the guild skin (db.brand)
	-- is editable -- shown as a separate suffix, MRT-style. Title/version must be
	-- children of the HEADER (not the window) so they draw ABOVE its raised backdrop.
	local logo = hdr:CreateTexture(nil, "OVERLAY")
	logo:SetSize(18, 18); logo:SetPoint("LEFT", 9, 0)
	logo:SetTexture("Interface\\Icons\\Trade_BlackSmithing")   -- the anvil
	logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local title = W.Text(hdr, "Okanvil", 16, "accent")
	title:SetPoint("LEFT", logo, "RIGHT", 7, 0); title:Color(1, 0.82, 0)
	local ver = W.Text(hdr, "v" .. (self.version or "1.0"), 10, "dim")
	ver:SetPoint("LEFT", title, "RIGHT", 6, -1)
	-- guild skin (editable) sits after the version as a dimmer suffix
	local brandFS = W.Text(hdr, "", 13, "dim")
	brandFS:SetPoint("LEFT", ver, "RIGHT", 8, 1)
	local function paintBrand()
		local b = db.brand or ""
		if b == "" or b == "Okanvil" then brandFS:SetText("") -- no guild skin set
		else brandFS:SetText("|cff8a8d93\194\183  " .. b .. "|r") end -- "· <guild>"
	end
	paintBrand()
	self.headerTitle = brandFS   -- so Settings can rebrand live
	self.headerPaintBrand = paintBrand

	local close = W.Button(hdr, "X"); close:SetSize(24, 20); close:SetPoint("RIGHT", -3, 0)
	close:SetScript("OnClick", function() f:Hide() end)

	-- left nav
	local nav = W.Frame(f, "dark")
	nav:SetPoint("TOPLEFT", 6, -(HEADER_H + 6))
	nav:SetPoint("BOTTOMLEFT", 6, FOOTER_H + 4)
	nav:SetWidth(NAV_W)
	local navHdr = W.Text(nav, "NAVIGATION", 10, "dim"); navHdr:SetPoint("TOPLEFT", 10, -8)
	local navSF = CreateFrame("ScrollFrame", "Okanvil_NavSF", nav)
	navSF:SetPoint("TOPLEFT", 4, -24); navSF:SetPoint("BOTTOMRIGHT", -6, 4)
	Okanvil.Clip(navSF)
	local navChild = CreateFrame("Frame", nil, navSF)
	navChild:SetSize(NAV_W - 12, 1); navSF:SetScrollChild(navChild)
	navSF:EnableMouseWheel(true)
	navSF:SetScript("OnMouseWheel", function(s, d)
		local cur = s:GetVerticalScroll()
		local maxS = math.max(0, navChild:GetHeight() - s:GetHeight())
		s:SetVerticalScroll(math.min(maxS, math.max(0, cur - d * 24)))
	end)
	self.navChild = navChild

	-- content well
	local content = W.Frame(f, "dark")
	content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 6, 0)
	content:SetPoint("BOTTOMRIGHT", -6, FOOTER_H + 4)
	self.content = content

	-- footer: fixed author credit (Okanvil is by Okanor) + a flavor line
	local footer = W.Text(f, "|cff8a8d93Okanvil |cff6f7176by|r Okanor|r  |cff55575b--  the void in your stack trace|r", 10, "dim")
	footer:SetPoint("BOTTOMLEFT", 10, 6)
	self.footerCount = W.Text(f, "", 10, "dim")
	self.footerCount:SetPoint("BOTTOMRIGHT", -20, 6)

	-- resize grip. It MUST stay clickable above the content well / plugin panels
	-- (which are created later and would otherwise cover the corner and swallow the
	-- mouse -> "resize doesn't work"). Give it its own top-level strata + high level.
	local grip = CreateFrame("Button", nil, f)
	grip:SetFrameStrata("HIGH"); grip:SetFrameLevel(f:GetFrameLevel() + 20)
	grip:SetToplevel(true)
	grip:SetPoint("BOTTOMRIGHT", -2, 2); grip:SetSize(18, 18)
	grip:EnableMouse(true)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetScript("OnMouseDown", function()
		f:SetResizable(true)
		f:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		db.window.width, db.window.height = f:GetWidth(), f:GetHeight()
		if Okanvil.RelayoutActivePanel then Okanvil:RelayoutActivePanel() end
	end)
	-- manual min-size clamp fallback, only when the client lacks a native
	-- min-size API. Guarded against re-entrancy (SetWidth/SetHeight re-fire
	-- OnSizeChanged) so it can't loop.
	if not f.SetResizeBounds and not f.SetMinResize then
		f:SetScript("OnSizeChanged", function(s)
			if s._clamping then return end
			s._clamping = true
			if s:GetWidth() < MIN_W then s:SetWidth(MIN_W) end
			if s:GetHeight() < MIN_H then s:SetHeight(MIN_H) end
			s._clamping = nil
		end)
	end

	self:RefreshNav()
	self:ShowPanel(HOME)
	f:Hide()
end

-- ------------------------------------------------------------
-- Nav list
-- ------------------------------------------------------------
-- Built-in modules (rendered by the shell's own BuildInvite/Guild/Loot, not a
-- plugin build()). Listed here so they ALSO appear in the Modules manager and can
-- be toggled on/off exactly like the plugin modules. Home/Modules/Settings are the
-- fixed "core" and are never toggleable.
Okanvil.NATIVE = {
	{ key = "__invite", title = "Invite", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
	  desc = "Mass-invite the guild, by rank, or from saved lists." },
	{ key = "__guild",  title = "Guild",  icon = "Interface\\Icons\\INV_Misc_GroupLooking",
	  desc = "Guild dashboard + JSON roster export for the web hub." },
	{ key = "__loot",   title = "Loot",   icon = "Interface\\Icons\\INV_Misc_Coin_01",
	  desc = "Per-boss loot tracking with a fair-loot priority tab." },
}

function Okanvil:RefreshNav()
	if not self.navChild then return end
	for _, b in ipairs(self._navButtons) do b:Hide() end

	local list = {
		{ key = HOME, title = "Home", icon = "Interface\\Icons\\INV_Misc_Rune_01" },
	}
	-- built-in modules (respect their enable state, keyed by __key)
	for _, m in ipairs(self.NATIVE) do
		if self:IsModuleEnabled(m.key) then
			list[#list + 1] = { key = m.key, title = m.title, icon = m.icon }
		end
	end
	-- plugin modules (registered via Okanvil_Plugins)
	local names = {}
	for name in pairs(self.entries) do names[#names + 1] = name end
	table.sort(names, function(a, b) return (self.entries[a].title or a) < (self.entries[b].title or b) end)
	for _, name in ipairs(names) do
		if self:IsModuleEnabled(name) then      -- disabled modules drop out of the nav
			list[#list + 1] = { key = name, title = self.entries[name].title or name, icon = self.entries[name].icon }
		end
	end
	list[#list + 1] = { key = MODULES, title = "Modules", icon = "Interface\\Icons\\INV_Misc_Gear_01" }
	list[#list + 1] = { key = SETTINGS, title = "Settings", icon = "Interface\\Icons\\Trade_Engineering" }

	local y = 0
	for i, item in ipairs(list) do
		local b = self._navButtons[i] or makeNavEntry(self.navChild)
		self._navButtons[i] = b
		b:ClearAllPoints(); b:SetPoint("TOPLEFT", 0, -y); b:SetPoint("TOPRIGHT", 0, -y)
		b.text:SetText(item.title)
		if item.icon then b.icon:SetTexture(item.icon); b.icon:Show() else b.icon:Hide() end
		b._key = item.key
		b:SetScript("OnClick", function() Okanvil:ShowPanel(item.key) end)
		b:Show()
		y = y + 26
	end
	self.navChild:SetHeight(math.max(1, y))
	if self.footerCount then
		-- count = built-in natives + registered plugins
		local total, on = 0, 0
		for _, m in ipairs(self.NATIVE) do
			total = total + 1
			if self:IsModuleEnabled(m.key) then on = on + 1 end
		end
		for name in pairs(self.entries) do
			total = total + 1
			if self:IsModuleEnabled(name) then on = on + 1 end
		end
		self.footerCount:SetText(on .. "/" .. total .. " modules on")
	end
end

-- ------------------------------------------------------------
-- Panels. Two shapes:
--   newFillPanel()   -> a frame that FILLS the content well (real
--                       BOTTOMRIGHT). Plugins draw into `.child` here;
--                       they anchor their own widgets/scrollframes to it,
--                       exactly as they were written. This is what stops
--                       Recruit/IDs/etc collapsing.
--   newScrollPanel() -> internal scrolling area for the shell's own long
--                       pages (Home, Settings).
-- Both expose `.child` (draw target) and `.relayout()`.
-- ------------------------------------------------------------
-- ------------------------------------------------------------
-- Shared "rat art" background -- a faded image pinned bottom-right of a panel,
-- behind the content, on EVERY page. WoW 3.3.5a draws only BLP (DXT5) shipped in
-- the addon -> Media\rat<N>.blp. db.ratArtPick (1..) chooses it; db.ratArt "off"
-- hides. One texture per host frame, tracked in Okanvil._bgArts so Settings can
-- refresh them all live.
-- single art file: Media\rat1.blp (the Okanor blacksmith). No picker.
local RAT_TEX = "Interface\\AddOns\\Okanvil\\Media\\rat1"
local function applyRatTex(tex)
	tex:SetTexture(RAT_TEX); tex:SetTexCoord(0, 1, 0, 1)
end

-- attach the faded bg art to `host` (a visible panel frame). Returns the texture.
function Okanvil:MountBgArt(host)
	local art = host:CreateTexture(nil, "BACKGROUND")
	art:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, 8)
	art:SetAlpha(0.55)
	local function refresh()
		if (Okanvil.db.ratArt or "on") == "off" then art:Hide(); return end
		applyRatTex(art)
		local vw, vh = host:GetWidth() or 700, host:GetHeight() or 500
		local s = math.max(200, math.min(vh * 0.55, vw * 0.4))
		art:SetSize(s, s); art:Show()
	end
	art.refresh = refresh
	host:HookScript("OnSizeChanged", refresh)
	host:HookScript("OnShow", refresh)
	refresh()
	self._bgArts = self._bgArts or {}
	self._bgArts[#self._bgArts + 1] = art
	return art
end

-- refresh every mounted bg art (called from Settings when style/pick changes).
function Okanvil:RefreshRatArt()
	if not self._bgArts then return end
	for _, a in ipairs(self._bgArts) do if a.refresh then a:refresh() end end
end

local function newFillPanel()
	local wrap = CreateFrame("Frame", nil, Okanvil.content)
	wrap:SetPoint("TOPLEFT", 2, -2); wrap:SetPoint("BOTTOMRIGHT", -2, 2)
	wrap:Hide()
	wrap.child = wrap                 -- plugins anchor straight to the panel
	wrap.relayout = function() end
	Okanvil:MountBgArt(wrap)          -- bg art on plugin pages too
	return wrap
end

local function newScrollPanel()
	local wrap = CreateFrame("Frame", nil, Okanvil.content)
	wrap:SetPoint("TOPLEFT", 2, -2); wrap:SetPoint("BOTTOMRIGHT", -2, 2)
	wrap:Hide()

	local sf = CreateFrame("ScrollFrame", nil, wrap)
	sf:SetPoint("TOPLEFT", 4, -4); sf:SetPoint("BOTTOMRIGHT", -8, 4)
	Okanvil.Clip(sf)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(10, 10); sf:SetScrollChild(child)

	local sb = CreateFrame("Slider", nil, wrap)
	sb:SetPoint("TOPRIGHT", -3, -4); sb:SetPoint("BOTTOMRIGHT", -3, 4); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
	local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetVertexColor(u3(C.accent)); th:SetSize(4, 40)
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 24) end)

	local function relayout()
		child:SetWidth(sf:GetWidth())
		local maxS = math.max(0, child:GetHeight() - sf:GetHeight())
		sb:SetMinMaxValues(0, maxS)
		sb:SetShown(maxS > 0)
	end
	sf:SetScript("OnSizeChanged", relayout)
	wrap.scroll, wrap.child, wrap.relayout = sf, child, relayout
	Okanvil:MountBgArt(wrap)          -- faded rat art bottom-right, behind content
	return wrap
end

function Okanvil:ShowPanel(key)
	self:CloseDropdown()
	for _, b in ipairs(self._navButtons) do
		b._active = (b._key == key)
		if b._active then b.hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.10); b.bar:Show()
		else b.hl:SetVertexColor(0, 0, 0, 0); b.bar:Hide() end
	end

	local entry = self.panels[key]
	if not entry then
		if key == HOME then entry = self:BuildHome()
		elseif key == GUILD then entry = self:BuildGuild()
		elseif key == LOOT then entry = self:BuildLoot()
		elseif key == INVITE then entry = self:BuildInvite()
		elseif key == MODULES then entry = self:BuildModules()
		elseif key == SETTINGS then entry = self:BuildSettings()
		else
			local plug = self.entries[key]
			if plug and plug.build then
				entry = newFillPanel()
				plug.build(entry.child)   -- plugin draws into a full-size panel
			end
		end
		self.panels[key] = entry
	end

	for _, e in pairs(self.panels) do if e.Hide then e:Hide() end end
	if entry then
		entry:Show()
		if entry.relayout then entry.relayout() end
		local plug = self.entries[key]
		if plug and plug.refresh then plug.refresh() end
	end
	self._current = key
end

-- ------------------------------------------------------------
-- Home
-- ------------------------------------------------------------
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
	local tiles = {}
	local function tile(i, label)
		local t = W.Frame(p, "input")
		t:SetSize(120, 48)
		if i == 1 then
			t:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
		else
			t:SetPoint("TOPLEFT", tiles["_t" .. (i - 1)], "TOPRIGHT", 8, 0)
		end
		t.num = W.Text(t, "--", 20, "accent"); t.num:SetPoint("TOPLEFT", 10, -6)
		t.lbl = W.Text(t, label, 10, "dim"); t.lbl:SetPoint("BOTTOMLEFT", 10, 6)
		tiles["_t" .. i] = t
		return t
	end
	tiles.online = tile(1, "ONLINE")
	tiles.members = tile(2, "MAINS")
	tiles.rank = tile(3, "YOUR RANK")

	-- guild online card -- a SCROLLABLE row list (shows everyone, not a capped
	-- text blob) with a per-row [inv] button for quick invites from Home.
	local gcard = W.Frame(p, "input")
	gcard:SetPoint("TOPLEFT", tiles._t1, "BOTTOMLEFT", 0, -12); gcard:SetPoint("RIGHT", p, "RIGHT", -X, 0); gcard:SetHeight(180)
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

	-- hub card. WoW 3.3.5a can't launch a browser, so we just SHOW the URL
	-- (no fake "open" button). Copy it from Settings > Branding if needed.
	local rcard = W.Frame(p, "input")
	rcard:SetPoint("TOPLEFT", gcard, "BOTTOMLEFT", 0, -12); rcard:SetPoint("RIGHT", p, "RIGHT", -X, 0); rcard:SetHeight(58)
	local rh = W.Text(rcard, "WEB HUB", 10, "dim"); rh:SetPoint("TOPLEFT", 10, -8)
	local rdesc = W.Text(rcard, "Rankings, profiles and roster live on the hub:", 11)
	rdesc:SetPoint("TOPLEFT", 10, -24)
	local rurl = W.Text(rcard, "", 11, "accent"); rurl:SetPoint("TOPLEFT", 10, -40)
	rurl:SetText(Okanvil.db.hubURL or "")

	-- (rat art background is mounted by newScrollPanel -> Okanvil:MountBgArt, on
	-- every page; nothing to build here.)

	local function refreshGuild()
		if not (IsInGuild and IsInGuild()) then
			tiles.online.num:SetText("--"); tiles.members.num:SetText("--"); tiles.rank.num:SetText("--")
			for _, r in ipairs(wrap.gRows) do r:Hide() end
			if wrap.gsb then wrap.gsb:Hide() end
			wrap.gempty:SetText("|cff888888You are not in a guild.|r")
			return
		end
		-- 3.3.5a: GetNumGuildMembers only counts ONLINE unless offline are shown.
		-- Force offline in so we walk the whole roster, not just online.
		if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
		local total = GetNumGuildMembers and GetNumGuildMembers() or 0
		local online, mains, mine = 0, 0, "--"
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
		-- rank colour so the online list is scannable at a glance. RATS ladder
		-- (rankIndex 0 = top): Warchief Rat / Warchief's Fangs = officers (red-gold),
		-- Raider Rat = orange, Sewer Rat = yellow, Alt = grey-blue, Pug/other = grey.
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
		for i = 1, total do
			-- 3.3.5: name, rank, rankIndex, level, class, zone, publicnote, officernote, online
			local name, rank, rankIndex, _, class, _, publicnote, officernote, isOnline = GetGuildRosterInfo(i)
			if name then
				local alt = isAlt(rank, rankIndex, officernote)
				if not alt then mains = mains + 1 end
				if isOnline then
					online = online + 1
					onlineList[#onlineList + 1] = {
						name = name, rank = rank or "", rankIndex = rankIndex or 99, class = class,
						col = rankColor(rank, rankIndex, alt), alt = alt,
						main = alt and mainOf(publicnote, officernote) or nil,
					}
				end
				if name == myName then mine = rank or "--" end
			end
		end
		tiles.online.num:SetText(tostring(online))
		tiles.members.num:SetText(tostring(mains))   -- MAINS only (real people, alts excluded)
		tiles.rank.num:SetText(mine)
		tiles.rank.num._okSize = nil; tiles.rank.num:SetFont(Okanvil:Font(), (#mine > 6) and 12 or 20)

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
		for _, r in ipairs(rows) do r:Hide() end
		for k, m in ipairs(onlineList) do
			local row = rows[k]
			if not row then
				row = CreateFrame("Frame", nil, wrap.gchild)
				row:SetHeight(ROWH)
				row.name = row:CreateFontString(nil, "OVERLAY")
				row.name:SetFont(Okanvil:Font(), 12)
				row.name:SetPoint("LEFT", 4, 0); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
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
				rows[k] = row
			end
			row:SetWidth(wrap.gsf:GetWidth()); row:SetHeight(ROWH)
			row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(k - 1) * ROWH); row:Show()
			-- name column has a fixed right bound so it never runs into the rank column
			row.name:SetPoint("RIGHT", row, "LEFT", RANK_X - 6, 0)
			row.name:SetText("|cff5a5d63* |r|c" .. m.col .. m.name .. "|r")
			row.rank:SetText("|cff8a8d93" .. m.rank .. "|r")
			-- alt -> show the main it belongs to, aligned in its own right column
			if m.alt and m.main then
				row.main:SetText("|cff6a6d73of |r|cffbfc4cc" .. m.main .. "|r")
			else
				row.main:SetText("")
			end
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
function Okanvil:BuildGuild()
	local wrap = newScrollPanel()
	local p = wrap.child
	local G = Okanvil.Guild
	local X = 18

	local h = W.Text(p, "Guild", 18, "accent"); h:SetPoint("TOPLEFT", X, -16)
	local hint = W.Text(p, "Export data for the web hub. Attendance is captured automatically at the first pull.", 11, "dim")
	hint:SetPoint("TOPLEFT", X, -40); hint:SetPoint("RIGHT", p, "RIGHT", -X, 0); hint:SetJustifyH("LEFT")

	-- action buttons
	local exportRoster = W.Button(p, "Export roster", "primary")
	exportRoster:SetSize(150, 26); exportRoster:SetPoint("TOPLEFT", X, -70)
	exportRoster:SetScript("OnClick", function()
		local json = G.BuildRosterJSON()
		Okanvil:ShowExport(json, "Guild roster")
	end)

	local snapNow = W.Button(p, "Snapshot group now")
	snapNow:SetSize(150, 26); snapNow:SetPoint("LEFT", exportRoster, "RIGHT", 10, 0)
	snapNow:SetScript("OnClick", function()
		local snap, err = G.SaveSnapshot("manual")
		if not snap then
			Okanvil:Print("Snapshot failed: " .. (err or "?"))
		else
			wrap.expanded = snap        -- expand the new snapshot inline (no popup)
			if wrap._rebuild then wrap._rebuild() end
		end
	end)

	-- snapshots list header
	local sh = W.Text(p, "SAVED SNAPSHOTS", 10, "dim"); sh:SetPoint("TOPLEFT", X, -110)

	wrap.rows = {}
	wrap.detailFS = {}       -- pooled expansion text blocks (one per row when open)
	wrap.expanded = nil
	local function rebuild()
		for _, r in ipairs(wrap.rows) do r:Hide() end
		for _, t in ipairs(wrap.detailFS) do t:Hide() end
		local snaps = (Okanvil.db.guild and Okanvil.db.guild.snapshots) or {}
		if #snaps == 0 then
			wrap.empty = wrap.empty or W.Text(p, "", 12, "dim")
			wrap.empty:SetPoint("TOPLEFT", X, -132)
			wrap.empty:SetText("|cff888888No snapshots yet. They save at the first pull, or use the button above.|r")
			p:SetHeight(180); wrap.relayout(); return
		end
		if wrap.empty then wrap.empty:SetText("") end

		local di = 0
		local y = 130
		for i, snap in ipairs(snaps) do
			local r = wrap.rows[i]
			if not r then
				r = W.Frame(p, "input")
				r.title = W.Text(r, "", 13); r.title:SetPoint("TOPLEFT", 10, -6)
				r.sub = W.Text(r, "", 10, "dim"); r.sub:SetPoint("BOTTOMLEFT", 10, 6)
				r.del = W.Button(r, "X", "danger"); r.del:SetSize(24, 22); r.del:SetPoint("RIGHT", -8, 0)
				r.export = W.Button(r, "Export"); r.export:SetSize(72, 22); r.export:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
				r.view = W.Button(r, "View"); r.view:SetSize(60, 22); r.view:SetPoint("RIGHT", r.export, "LEFT", -6, 0)
				r:EnableMouse(true)
				wrap.rows[i] = r
			end
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", X, -y); r:SetPoint("RIGHT", p, "RIGHT", -X, 0); r:SetHeight(40)
			local dateStr = date("%b %d  %H:%M", snap.t)
			local where = (snap.zone ~= "" and snap.zone) or "Unknown"
			local isOpen = (wrap.expanded == snap)
			r.title:SetText((isOpen and "|cffffd200v|r  " or "|cff8a8d93>|r  ")
				.. where .. (snap.boss ~= "" and ("  |cff8a8d93-- " .. snap.boss .. "|r") or ""))
			r.sub:SetText(dateStr .. "  |cff8a8d93|  " .. (snap.count or 0) .. " players  |  " .. (snap.trigger or "") .. "|r")
			r.view.text:SetText(isOpen and "Close" or "View")
			local function toggle()
				if wrap.expanded == snap then wrap.expanded = nil else wrap.expanded = snap end
				rebuild()
			end
			r.view:SetScript("OnClick", toggle)   -- View/Close button owns the toggle
			r.export:SetScript("OnClick", function()
				Okanvil:ShowExport(G.SnapshotJSON(snap), "Attendance -- " .. dateStr)
			end)
			r.del:SetScript("OnClick", function()
				if wrap.expanded == snap then wrap.expanded = nil end
				G.DeleteSnapshot(snap)
			end)
			r:Show()
			y = y + 46

			if isOpen then
				di = di + 1
				local t = wrap.detailFS[di]
				if not t then t = W.Text(p, "", 12); t:SetJustifyH("LEFT"); wrap.detailFS[di] = t end
				t:ClearAllPoints()
				t:SetPoint("TOPLEFT", X + 14, -y); t:SetPoint("RIGHT", p, "RIGHT", -X, 0)
				t:SetText(G.SnapshotBodyText(snap))
				t:Show()
				y = y + t:GetStringHeight() + 10
			end
		end
		p:SetHeight(math.max(y + 10, wrap.scroll:GetHeight()))
		wrap.relayout()
	end
	wrap._rebuild = rebuild
	G.onSnapshot = function() if wrap:IsShown() then rebuild() end end
	wrap:SetScript("OnShow", rebuild)
	return wrap
end

-- ------------------------------------------------------------
-- Loot (native) -- what dropped, per boss. Data only; winners on the hub.
-- ------------------------------------------------------------
function Okanvil:BuildLoot()
	local wrap = newScrollPanel()
	local p = wrap.child
	local L = Okanvil.Loot
	local X = 18

	local h = W.Text(p, "Loot", 18, "accent"); h:SetPoint("TOPLEFT", X, -16)
	local hint = W.Text(p, "Items that dropped, per boss. Open a corpse to log it. Winners are decided on the hub.", 11, "dim")
	hint:SetPoint("TOPLEFT", X, -40); hint:SetPoint("RIGHT", p, "RIGHT", -X, 0); hint:SetJustifyH("LEFT")

	local sh = W.Text(p, "SESSIONS", 10, "dim"); sh:SetPoint("TOPLEFT", X, -74)

	wrap.rows = {}
	wrap.detailRows = {}     -- pooled item/boss rows for the inline expansion
	wrap.expanded = nil      -- the session table currently expanded (accordion)

	-- The expanded drops live in ONE reusable box with its OWN internal scroll
	-- (fixed height) -- so opening a session doesn't grow/scroll the whole page.
	local DETAIL_H = 280
	local dbox = W.Frame(p, "dark")
	local dsf = CreateFrame("ScrollFrame", nil, dbox)
	dsf:SetPoint("TOPLEFT", 4, -4); dsf:SetPoint("BOTTOMRIGHT", -10, 4)
	local dchild = CreateFrame("Frame", nil, dsf); dchild:SetSize(10, 1); dsf:SetScrollChild(dchild)
	local dsb = CreateFrame("Slider", nil, dbox)
	dsb:SetPoint("TOPRIGHT", -3, -4); dsb:SetPoint("BOTTOMRIGHT", -3, 4); dsb:SetWidth(4)
	dsb:SetOrientation("VERTICAL"); dsb:SetValueStep(1)
	local dth = dsb:CreateTexture(nil, "OVERLAY"); dth:SetTexture(FLAT); dth:SetVertexColor(u3(C.accent)); dth:SetSize(4, 40)
	dsb:SetThumbTexture(dth)
	dsb:SetScript("OnValueChanged", function(_, v) dsf:SetVerticalScroll(v) end)
	dsf:EnableMouseWheel(true)
	dsf:SetScript("OnMouseWheel", function(_, d) dsb:SetValue(dsb:GetValue() - d * 28) end)
	dsf:SetScript("OnSizeChanged", function() dchild:SetWidth(dsf:GetWidth()) end)
	dbox:Hide()
	wrap.dbox, wrap.dchild, wrap.dsb, wrap.dsf = dbox, dchild, dsb, dsf

	-- pull one pooled detail row (child of the SCROLL BOX, not the page)
	local function detailRow(idx, yTop)
		local r = wrap.detailRows[idx]
		if not r then
			r = CreateFrame("Button", nil, dchild)
			r:SetHeight(18)
			r.icon = r:CreateTexture(nil, "ARTWORK")
			r.icon:SetSize(16, 16); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); r.icon:Hide()
			r.txt = r:CreateFontString(nil, "OVERLAY"); r.txt:SetFont(Okanvil:Font()); r.txt:SetJustifyH("LEFT")
			local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
			hl:SetTexture(FLAT); hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.10)
			wrap.detailRows[idx] = r
		end
		-- yTop here is relative to the scroll child's top (starts at ~4)
		r:ClearAllPoints(); r:SetPoint("TOPLEFT", 8, -yTop); r:SetPoint("RIGHT", dchild, "RIGHT", -6, 0)
		r:SetScript("OnEnter", nil); r:SetScript("OnLeave", nil); r:SetScript("OnClick", nil)
		r.icon:Hide(); r:Show()
		return r
	end

	local function rebuild()
		for _, r in ipairs(wrap.rows) do r:Hide() end
		for _, r in ipairs(wrap.detailRows) do r:Hide() end
		wrap.dbox:Hide()
		local sessions = (Okanvil.db.loot and Okanvil.db.loot.sessions) or {}
		if #sessions == 0 then
			wrap.empty = wrap.empty or W.Text(p, "", 12, "dim")
			wrap.empty:SetPoint("TOPLEFT", X, -96)
			wrap.empty:SetText("|cff888888No loot logged yet. Kill a boss and open the corpse.|r")
			p:SetHeight(150); wrap.relayout(); return
		end
		if wrap.empty then wrap.empty:SetText("") end

		local y = 94
		for i, s in ipairs(sessions) do
			local r = wrap.rows[i]
			if not r then
				r = W.Frame(p, "input")
				r.title = W.Text(r, "", 13); r.title:SetPoint("TOPLEFT", 10, -6)
				r.sub = W.Text(r, "", 10, "dim"); r.sub:SetPoint("BOTTOMLEFT", 10, 6)
				r.del = W.Button(r, "X", "danger"); r.del:SetSize(24, 22); r.del:SetPoint("RIGHT", -8, 0)
				r.export = W.Button(r, "Export"); r.export:SetSize(72, 22); r.export:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
				r.view = W.Button(r, "View"); r.view:SetSize(60, 22); r.view:SetPoint("RIGHT", r.export, "LEFT", -6, 0)
				r:EnableMouse(true)
				wrap.rows[i] = r
			end
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", X, -y); r:SetPoint("RIGHT", p, "RIGHT", -X, 0); r:SetHeight(40)
			local where = (s.zone ~= "" and s.zone) or "World"
			local isOpen = (wrap.expanded == s)
			r.title:SetText((isOpen and "|cffffd200v|r  " or "|cff8a8d93>|r  ") .. where .. "  |cff8a8d93" .. (s.day or "") .. "|r")
			r.sub:SetText("|cff8a8d93" .. #s.drops .. " drops  |  " .. #s.rolls .. " rolls|r")
			r.view.text:SetText(isOpen and "Close" or "View")
			r.view:SetScript("OnClick", function()   -- View/Close button owns the toggle
				-- NOTE: `(cond) and nil or s` ALWAYS returns s in Lua (nil is falsy),
				-- so it never closed. Use an explicit if.
				if wrap.expanded == s then wrap.expanded = nil else wrap.expanded = s end
				rebuild()
			end)
			r.export:SetScript("OnClick", function()
				Okanvil:ShowExport(L.SessionJSON(s), "Loot -- " .. (s.day or where))
			end)
			r.del:SetScript("OnClick", function()
				if wrap.expanded == s then wrap.expanded = nil end
				L.DeleteSession(s)
			end)
			r:Show()
			y = y + 46

			-- expansion: render this session's drops INSIDE the fixed-height scroll box
			-- anchored right under the row. The page only grows by the box height, and
			-- the drops scroll internally instead of stretching the whole page.
			if isOpen then
				wrap.dbox:ClearAllPoints()
				wrap.dbox:SetPoint("TOPLEFT", X, -y); wrap.dbox:SetPoint("RIGHT", p, "RIGHT", -X, 0)
				wrap.dbox:SetHeight(DETAIL_H); wrap.dbox:Show()
				wrap.dchild:SetWidth(wrap.dsf:GetWidth())   -- ensure child width before layout
				local dy = select(2, L.RenderInline(s, detailRow, 0, 4))
				wrap.dchild:SetHeight(math.max(1, dy))
				local maxs = math.max(0, dy - (DETAIL_H - 8))
				wrap.dsb:SetMinMaxValues(0, maxs); wrap.dsb:SetValue(0); wrap.dsb:SetShown(maxs > 4)
				y = y + DETAIL_H + 6
			end
		end
		p:SetHeight(math.max(y + 10, wrap.scroll:GetHeight()))
		wrap.relayout()
	end
	wrap._rebuild = rebuild
	L.onLoot = function() if wrap:IsShown() then rebuild() end end
	wrap:SetScript("OnShow", rebuild)
	return wrap
end

-- ------------------------------------------------------------
-- Invite (native) -- form a raid/party fast: mass-invite, by rank, saved lists
-- with comp-group import + auto-assign, keyword whisper invite, on-login invite.
-- ------------------------------------------------------------
function Okanvil:BuildInvite()
	local wrap = newScrollPanel()
	local p = wrap.child
	local I = Okanvil.Invite
	local X = 18

	local h = W.Text(p, "Invite", 18, "accent"); h:SetPoint("TOPLEFT", X, -16)

	-- Invite.lua provides the engine (Okanvil.Invite). If it isn't loaded, show a
	-- note instead of erroring (nil-index) so the tab never crashes the UI.
	if not I then
		local warn = W.Text(p, "", 12, "dim"); warn:SetPoint("TOPLEFT", X, -44)
		warn:SetPoint("RIGHT", p, "RIGHT", -X, 0); warn:SetJustifyH("LEFT")
		warn:SetText("|cffff8888The Invite engine (Invite.lua) isn't loaded.|r\n\n"
			.. "|cff888888Make sure Invite.lua is in the Okanvil folder and listed in Okanvil.toc, then /reload.|r")
		p:SetHeight(160); wrap.relayout()
		return wrap
	end

	local hint = W.Text(p, "Form a group fast. Build a raid list by picking raiders from the roster, then invite it. Parties auto-convert to raid past 5.", 11, "dim")
	hint:SetPoint("TOPLEFT", X, -40); hint:SetPoint("RIGHT", p, "RIGHT", -X, 0); hint:SetJustifyH("LEFT")

	-- The current working list name (all list actions use this).
	local curList = "Raid"

	-- ============================================================
	-- LEFT COLUMN = controls (fixed width). RIGHT COLUMN = list manager.
	-- ============================================================
	local LEFT_W = 340
	local left = W.Frame(p, "bare"); left:SetPoint("TOPLEFT", X, -64); left:SetWidth(LEFT_W); left:SetHeight(560)

	-- ---- quick invite ----
	local qh = W.Text(left, "QUICK INVITE", 10, "dim"); qh:SetPoint("TOPLEFT", 0, 0)
	local bAll = W.Button(left, "Invite guild online", "primary")
	bAll:SetSize(160, 26); bAll:SetPoint("TOPLEFT", 0, -16)
	bAll:SetScript("OnClick", function() I.InviteGuildOnline() end)
	local bRank = W.Button(left, "Invite by rank")
	bRank:SetSize(130, 26); bRank:SetPoint("LEFT", bAll, "RIGHT", 8, 0)
	bRank:SetScript("OnClick", function() I.InviteByRank() end)

	-- rank checkboxes bound to iv.ranks[rankIndex], built once from the roster.
	local rankChecks = {}
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
		local cx, cy = 0, -48
		for i, r in ipairs(ranks) do
			local idx = r.idx
			local c = W.Check(left, r.name, function() return iv.ranks[idx] end,
				function(v) iv.ranks[idx] = v and true or false end)
			c:SetPoint("TOPLEFT", cx, cy)
			rankChecks[#rankChecks + 1] = c
			cx = cx + 165
			if i % 2 == 0 then cx = 0; cy = cy - 24 end
		end
		rankBuilt = true
	end

	-- ---- keyword invite (whisper + guild chat) ----
	local whlbl = W.Text(left, "KEYWORD INVITE", 10, "dim"); whlbl:SetPoint("TOPLEFT", 0, -110)
	local wChk = W.Check(left, "On whisper", function() return I.db().whisperInvite end,
		function(v) I.db().whisperInvite = v end)
	wChk:SetPoint("TOPLEFT", 0, -126)
	local gChk = W.Check(left, "On guild chat", function() return I.db().guildInvite end,
		function(v) I.db().guildInvite = v end)
	gChk:SetPoint("TOPLEFT", 150, -126)
	local kwlbl = W.Text(left, "Keyword:", 11, "dim"); kwlbl:SetPoint("TOPLEFT", 0, -152)
	local kwBox = W.EditBox(left, function(t) I.db().keyword = (t or ""):gsub("%s", "") end)
	kwBox:Size(120, 22); kwBox:SetPoint("LEFT", kwlbl, "RIGHT", 8, 0)
	kwBox.edit:SetText(I.db().keyword or "inv")

	-- ---- saved list (built by picking raiders on the right) ----
	local llbl = W.Text(left, "RAID LIST", 10, "dim"); llbl:SetPoint("TOPLEFT", 0, -186)
	local nmLbl = W.Text(left, "List:", 11, "dim"); nmLbl:SetPoint("TOPLEFT", 0, -204)
	local nmBox = W.EditBox(left); nmBox:Size(140, 22); nmBox:SetPoint("LEFT", nmLbl, "RIGHT", 8, 0)
	nmBox.edit:SetText(curList)
	nmBox.edit:SetScript("OnEditFocusLost", function(s)
		local v = (s:GetText() or ""):gsub("%s+", ""); if v == "" then v = "Raid" end
		curList = v; if wrap._rebuild then wrap._rebuild() end
	end)

	local cntLbl = W.Text(left, "", 11, "dim"); cntLbl:SetPoint("TOPLEFT", 0, -230)

	local bInviteList = W.Button(left, "Invite this list", "primary")
	bInviteList:SetSize(130, 24); bInviteList:SetPoint("TOPLEFT", 0, -252)
	bInviteList:SetScript("OnClick", function() I.InviteList(curList) end)
	local bClear = W.Button(left, "Clear list")
	bClear:SetSize(90, 24); bClear:SetPoint("LEFT", bInviteList, "RIGHT", 6, 0)
	bClear:SetScript("OnClick", function() I.SaveList(curList, {}); if wrap._rebuild then wrap._rebuild() end end)

	local alChk = W.Check(left, "Auto-invite this list when they log in",
		function() local iv = I.db(); return iv.autoLoginList == curList and curList ~= "" end,
		function(v)
			local iv = I.db()
			iv.autoLoginList = (v and curList ~= "") and curList or ""
			if v and curList ~= "" then Okanvil:Print("Armed auto-invite for '" .. curList .. "' on login.") end
		end)
	alChk:SetPoint("TOPLEFT", 0, -286)

	local pinfo = W.Text(left, "Pick raiders on the right (real roster names). Click a name to add/remove it from the list.", 10, "dim")
	pinfo:SetPoint("TOPLEFT", 0, -314); pinfo:SetWidth(LEFT_W); pinfo:SetJustifyH("LEFT")

	-- ============================================================
	-- RIGHT COLUMN = ROSTER PICKER: real guildies grouped by rank, class-coloured,
	-- click to toggle into the current list. Names are the true in-game names, so
	-- invites always match (no fuzzy sign-up name problems).
	-- ============================================================
	local rcard = W.Frame(p, "input")
	rcard:SetPoint("TOPLEFT", X + LEFT_W + 16, -64)
	rcard:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -X, 8)
	rcard:SetHeight(560)
	local rhdr = W.Text(rcard, "GUILD ROSTER  --  click to add/remove", 11, "dim"); rhdr:SetPoint("TOPLEFT", 10, -8)

	local rsf = CreateFrame("ScrollFrame", nil, rcard)
	rsf:SetPoint("TOPLEFT", 8, -28); rsf:SetPoint("BOTTOMRIGHT", -12, 8)
	local rchild = CreateFrame("Frame", nil, rsf); rchild:SetSize(10, 1); rsf:SetScrollChild(rchild)
	local rsb = CreateFrame("Slider", nil, rcard)
	rsb:SetPoint("TOPRIGHT", -3, -28); rsb:SetPoint("BOTTOMRIGHT", -3, 8); rsb:SetWidth(4)
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
		if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
		local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
		-- collect members, split alts out (same alt rule as Home), group by rank
		local buckets, order = {}, {}
		for i = 1, total do
			local name, rank, rankIndex, _, class, _, publicnote, officernote, online = GetGuildRosterInfo(i)
			if name then
				name = (name:gsub("%-.*$", ""))
				local isAlt = (rankIndex == 4)
					or (rank and rank:lower():find("alt", 1, true))
					or (officernote and officernote:lower():match("^.-%s+alt%f[%A]"))
				if not isAlt then
					local key = rankIndex or 99
					if not buckets[key] then buckets[key] = { name = rank or ("Rank " .. key), idx = key, list = {} }; order[#order + 1] = key end
					table.insert(buckets[key].list, { name = name, class = class, online = online })
				end
			end
		end
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
			r.mark:Hide(); r:SetScript("OnClick", nil); r:Show()
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

	local function rebuild()
		buildRankChecks()
		rebuildPicker()
		local n = 0
		local mem = I.ListMembers(curList)
		if mem then n = #mem end
		cntLbl:SetText("|cff7cfc8a" .. n .. "|r |cff8a8d93in list|r")
		p:SetHeight(640); wrap.relayout()
	end
	wrap._rebuild = rebuild
	I.onChange = function() if wrap:IsShown() then rebuild() end end
	wrap:SetScript("OnShow", function() if GuildRoster then GuildRoster() end; rebuild() end)
	return wrap
end

-- ------------------------------------------------------------
-- Settings
-- ------------------------------------------------------------
function Okanvil:BuildSettings()
	local wrap = newScrollPanel()
	local p = wrap.child
	local db = self.db
	local X = 16

	local h = W.Text(p, "Settings", 18, "accent"); h:SetPoint("TOPLEFT", X, -14)

	-- card helper: titled panel in a 2-column grid. Returns the card frame;
	-- anchor children relative to it (its inner top-left is ~10,-28).
	local COLW = 300         -- card width
	local function card(title, col, y, hgt)
		local c = W.Frame(p, "input")
		local cx = X + (col == 2 and (COLW + 14) or 0)
		c:SetPoint("TOPLEFT", cx, -y); c:SetSize(COLW, hgt)
		local t = W.Text(c, title, 12, "accent"); t:SetPoint("TOPLEFT", 12, -10)
		return c
	end
	-- column cursors (track the next y for each column so cards stack)
	local colY = { 44, 44 }
	local function place(title, col, hgt)
		local c = card(title, col, colY[col], hgt)
		colY[col] = colY[col] + hgt + 12
		return c
	end

	-- ---- Appearance (left) ----
	local ap = place("Appearance", 1, 176)
	W.Slider(ap, "Window scale", 0.6, 1.4, 0.05, function() return db.scale end,
		function(v) db.scale = v; Okanvil.win:SetScale(v) end, true):SetPoint("TOPLEFT", 14, -44)
	W.Slider(ap, "Background opacity", 0.3, 1.0, 0.05, function() return db.bgAlpha end,
		function(v) db.bgAlpha = v; Okanvil:ReskinAll(v) end):SetPoint("TOPLEFT", 14, -92)
	W.Slider(ap, "Font size", 8, 20, 1, function() return db.fontSize end,
		function(v) db.fontSize = v; Okanvil:ApplyFonts() end):SetPoint("TOPLEFT", 14, -140)

	-- ---- Media (right) ----
	local md = place("Media", 2, 176)
	local fl = W.Text(md, "Font", 11, "dim"); fl:SetPoint("TOPLEFT", 12, -34)
	W.DropDown(md, function() return (LSM and LSM:List("font")) or { db.font } end,
		function() return db.font end, function(v) db.font = v; Okanvil:ApplyFonts() end, "font")
		:Size(160, 22):Point("TOPLEFT", 12, -52)
	local tl = W.Text(md, "Bar texture", 11, "dim"); tl:SetPoint("TOPLEFT", 12, -86)
	W.DropDown(md, function() return (LSM and LSM:List("statusbar")) or { db.statusbar } end,
		function() return db.statusbar end, function(v) db.statusbar = v end, "statusbar")
		:Size(160, 22):Point("TOPLEFT", 12, -104)
	if not LSM then
		local warn = W.Text(md, "LibSharedMedia not found -- using defaults.", 10, "dim")
		warn:SetPoint("TOPLEFT", 12, -140)
	end

	-- ---- Branding (left) ----
	-- The product name (Okanvil, by Okanor) is FIXED. Guilds only set their own
	-- skin, shown after "Okanvil" in the header and as a Home subtitle.
	local br = place("Branding", 1, 176)
	local nl = W.Text(br, "Guild skin (shown after Okanvil)", 11, "dim"); nl:SetPoint("TOPLEFT", 12, -34)
	local nameBox = W.EditBox(br, function(txt)
		db.brand = txt or ""
		if Okanvil.headerPaintBrand then Okanvil.headerPaintBrand() end
		Okanvil.panels["__home"] = nil
	end)
	nameBox:SetSize(COLW - 24, 22); nameBox:SetPoint("TOPLEFT", 12, -52)
	nameBox.edit:SetText((db.brand ~= "Okanvil" and db.brand) or "")
	local nh = W.Text(br, "e.g. RATS Guild Hub -- leave empty for just \"Okanvil\".", 10, "dim")
	nh:SetPoint("TOPLEFT", 12, -76)
	local ul = W.Text(br, "Web hub URL", 11, "dim"); ul:SetPoint("TOPLEFT", 12, -100)
	local urlBox = W.EditBox(br, function(txt) db.hubURL = txt end)
	urlBox:SetSize(COLW - 24, 22); urlBox:SetPoint("TOPLEFT", 12, -118)
	urlBox.edit:SetText(db.hubURL or "")

	-- ---- Loot + Recording (right) ----
	local lo = place("Loot & Recording", 2, 160)
	local ll = W.Text(lo, "Log items of quality", 11, "dim"); ll:SetPoint("TOPLEFT", 12, -34)
	local RARITY = {
		{ text = "|cff9d9d9dPoor+|r", value = 0 }, { text = "|cffffffffCommon+|r", value = 1 },
		{ text = "|cff1eff00Uncommon+|r", value = 2 }, { text = "|cff0070ddRare+|r", value = 3 },
		{ text = "|cffa335eeEpic|r", value = 4 },
	}
	local lootDD = W.DropDown(lo, function() return RARITY end,
		function() return db.lootThreshold or 3 end, function(v) db.lootThreshold = v end)
	lootDD:Size(140, 22):Point("TOPLEFT", 12, -52)
	lootDD.refreshText = function(self)
		local cur = db.lootThreshold or 3
		for _, o in ipairs(RARITY) do
			if o.value == cur then self.textFS:SetText(o.text); return end
		end
	end
	lootDD:refreshText()
	local rhint = W.Text(lo, "Auto-capture in:", 11, "dim"); rhint:SetPoint("TOPLEFT", 12, -92)
	local cDun = W.Check(lo, "Dungeons",
		function() return db.recordDungeon ~= false end, function(v) db.recordDungeon = v end)
	cDun:SetPoint("TOPLEFT", 12, -112)
	local cRaid = W.Check(lo, "Raids",
		function() return db.recordRaid ~= false end, function(v) db.recordRaid = v end)
	cRaid:SetPoint("TOPLEFT", 150, -112)

	-- ---- Background art (left) ----
	local ha = place("Background art", 1, 84)
	local showChk = W.Check(ha, "Show rat art on pages",
		function() return (db.ratArt or "on") ~= "off" end,
		function(v) db.ratArt = v and "on" or "off"; Okanvil:RefreshRatArt() end)
	showChk:SetPoint("TOPLEFT", 12, -36)
	local ahint = W.Text(ha, "A faded blacksmith in the corner. Turn off for a cleaner look.", 10, "dim")
	ahint:SetPoint("TOPLEFT", 12, -58); ahint:SetPoint("RIGHT", ha, "RIGHT", -12, 0); ahint:SetJustifyH("LEFT")

	-- ---- About (right) ----
	local ab = place("About", 2, 132)
	local an = W.Text(ab, "Okanvil", 15, "accent"); an:SetPoint("TOPLEFT", 12, -32); an:Color(1, 0.82, 0)
	local av = W.Text(ab, "v" .. (self.version or "1.0"), 10, "dim"); av:SetPoint("LEFT", an, "RIGHT", 6, -1)
	local aby = W.Text(ab, "Raid & guild toolkit -- by |cffe0b860Okanor|r.", 11, "dim")
	aby:SetPoint("TOPLEFT", 12, -54); aby:SetPoint("RIGHT", ab, "RIGHT", -12, 0); aby:SetJustifyH("LEFT")
	local acr = W.Text(ab, "ID Finder / Combat Logs / Loot / Recruit as toggleable modules.", 10, "dim")
	acr:SetPoint("TOPLEFT", 12, -84); acr:SetPoint("RIGHT", ab, "RIGHT", -12, 0); acr:SetJustifyH("LEFT")
	acr:SetTextColor(0.42, 0.43, 0.46)

	p:SetHeight(math.max(colY[1], colY[2]) + 16)
	return wrap
end

-- ------------------------------------------------------------
-- Modules -- enable/disable each registered plugin (no /reload for
-- show/hide in the nav; deeper event-gating is opt-in per plugin later)
-- ------------------------------------------------------------
function Okanvil:BuildModules()
	local wrap = newScrollPanel()
	local p = wrap.child
	local X = 18

	local h = W.Text(p, "Modules", 18, "accent"); h:SetPoint("TOPLEFT", X, -16)
	local hint = W.Text(p, "Turn modules on/off for THIS character (off = hidden from the menu). Each module's settings stay shared across your toons.", 11, "dim")
	hint:SetWidth(560); hint:SetJustifyH("LEFT")
	hint:SetPoint("TOPLEFT", X, -40)

	wrap.rows = {}
	local function rebuild()
		for _, r in ipairs(wrap.rows) do r:Hide() end
		-- one unified list: built-in modules first (in NATIVE order), then plugins.
		-- Each item = { key, title, icon, desc } -- the key is what IsModuleEnabled
		-- and the nav use.
		local items = {}
		for _, m in ipairs(Okanvil.NATIVE) do
			items[#items + 1] = { key = m.key, title = m.title, icon = m.icon, desc = m.desc }
		end
		local names = {}
		for name in pairs(Okanvil.entries) do names[#names + 1] = name end
		table.sort(names, function(a, b)
			return (Okanvil.entries[a].title or a) < (Okanvil.entries[b].title or b)
		end)
		for _, name in ipairs(names) do
			local e = Okanvil.entries[name]
			items[#items + 1] = { key = name, title = e.title or name, icon = e.icon, desc = e.desc }
		end
		if wrap.empty then wrap.empty:SetText("") end

		local y = 68
		for i, it in ipairs(items) do
			local name = it.key
			local r = wrap.rows[i]
			if not r then
				r = W.Frame(p, "input")
				r.icon = r:CreateTexture(nil, "ARTWORK")
				r.icon:SetSize(24, 24); r.icon:SetPoint("LEFT", 8, 0)
				r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				r.title = W.Text(r, "", 13); r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -1)
				r.desc = W.Text(r, "", 10, "dim")
				r.desc:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -15)
				r.desc:SetPoint("RIGHT", r, "RIGHT", -110, 0); r.desc:SetJustifyH("LEFT")
				r.toggle = W.Button(r, "")
				r.toggle:SetSize(88, 24)
				r.toggle:SetPoint("RIGHT", -8, 0)
				wrap.rows[i] = r
			end
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", X, -y); r:SetPoint("RIGHT", p, "RIGHT", -X, 0)
			r:SetHeight(44)
			r.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			r.title:SetText(it.title or name)
			r.desc:SetText(it.desc or "")

			local function paintToggle()
				local on = Okanvil:IsModuleEnabled(name)
				r.toggle.text:SetText(on and "|cff7cfc8aEnabled|r" or "|cff8a8d93Disabled|r")
				r.toggle._active = on
				if r.toggle._paint then r.toggle._paint(false) end
			end
			paintToggle()
			r.toggle:SetScript("OnClick", function()
				Okanvil:SetModuleEnabled(name, not Okanvil:IsModuleEnabled(name))
				paintToggle()
			end)
			r:Show()
			y = y + 50
		end
		p:SetHeight(math.max(y + 10, wrap.scroll:GetHeight()))
		wrap.relayout()
	end

	wrap._rebuild = rebuild
	wrap:SetScript("OnShow", rebuild)
	return wrap
end

-- ------------------------------------------------------------
-- Toggle
-- ------------------------------------------------------------
function Okanvil:Toggle()
	if not self.win then self:BuildShell() end
	if self.win:IsShown() then
		self:CloseDropdown()
		self.win:Hide()
	else
		self:RefreshNav()
		self.win:Show()
		self:ShowPanel(self._current or HOME)
	end
end

-- ------------------------------------------------------------
-- Minimap button
-- ------------------------------------------------------------
function Okanvil:BuildMinimap()
	if self.minimap then return end
	local b = CreateFrame("Button", "Okanvil_MinimapButton", Minimap)
	b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp"); b:RegisterForDrag("LeftButton")

	local overlay = b:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53); overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); overlay:SetPoint("TOPLEFT")
	local icon = b:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20); icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")   -- anvil
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); icon:SetPoint("CENTER", 1, 1)

	local function pos()
		local a = math.rad(Okanvil.db.minimapAngle or 200)
		b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a))
	end
	pos()
	b:SetScript("OnDragStart", function(s)
		s:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local sc = Minimap:GetEffectiveScale()
			Okanvil.db.minimapAngle = math.deg(math.atan2(py / sc - my, px / sc - mx))
			pos()
		end)
	end)
	b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
	b:SetScript("OnClick", function() Okanvil:Toggle() end)
	b:SetScript("OnEnter", function(s)
		GameTooltip:SetOwner(s, "ANCHOR_LEFT")
		GameTooltip:AddLine("|cffffd200Okanvil|r")
		local gb = Okanvil.db.brand
		if gb and gb ~= "" and gb ~= "Okanvil" then GameTooltip:AddLine(gb, 0.88, 0.72, 0.38) end
		GameTooltip:AddLine("Click: open", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.minimap = b
end
