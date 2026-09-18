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
Okanvil._navHeaders = {}   -- section labels, pooled separately from the clickable rows
local HOME, LOOT, SETTINGS = "__home", "__loot", "__settings"

-- FIXED window size (MRT-style): the window is NOT resizable -- a hand-tuned size
-- that always looks right. Users make it bigger/smaller with the Scale slider in
-- Settings (proportional, never breaks the layout). Resizing from offsets was
-- fragile and could break the UI, so we dropped it entirely.
-- 1100 wide, not 940: the pages outgrew the old width. The PuG spec row alone
-- needs ~790px of buttons and was clipping "bdk" off the right edge, and the
-- comp columns, the loot rows and the raid-finder table were all fighting for
-- the same ~730px of content well (940 minus the 190 nav and the padding).
--
-- Still safe on a 1280x720 laptop: the window is centred, so this leaves ~90px
-- either side, and anyone tighter than that has the Scale slider in Settings.
local WIN_W, WIN_H = 1100, 660
local MIN_W, MIN_H = WIN_W, WIN_H   -- kept for any legacy references
local NAV_W = 190
local HEADER_H = 30
local FOOTER_H = 22

-- ------------------------------------------------------------
-- Nav entry (icon + label + active bar)
-- ------------------------------------------------------------
-- Row metrics, derived from the user's font size so the Scale and Font sliders in
-- Settings move the nav along with everything else. The old fixed 15px icon and
-- default text made this the smallest thing on screen, next to a Home page whose
-- rows are 38px tall.
local function navFont()
	local _, base = Okanvil:Font()
	return math.max(8, (base or 12) + 2)
end
local function navRowH() return navFont() + 16 end
local function navIcon() return math.min(navRowH() - 8, 24) end
-- Section labels get extra room ABOVE them, which is what actually separates the
-- groups -- the label text itself sits at the bottom of that space.
local function navHeaderH() return navFont() + 14 end

local function makeNavEntry(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(navRowH())
	local hl = b:CreateTexture(nil, "BACKGROUND")
	hl:SetAllPoints(); hl:SetTexture(FLAT); hl:SetVertexColor(0, 0, 0, 0)
	b.hl = hl
	local bar = b:CreateTexture(nil, "ARTWORK")   -- left accent bar when active
	bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT"); bar:SetWidth(3)
	bar:SetTexture(FLAT); bar:SetVertexColor(u3(C.accent)); bar:Hide()
	b.bar = bar
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(navIcon(), navIcon()); b.icon:SetPoint("LEFT", 10, 0)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.text = W.Text(b, nil, navFont()); b.text:SetPoint("LEFT", b.icon, "RIGHT", 9, 0); b.text:SetJustifyH("LEFT")
	b:SetScript("OnEnter", function(s) if not s._active then s.hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.08) end end)
	b:SetScript("OnLeave", function(s) if not s._active then s.hl:SetVertexColor(0, 0, 0, 0) end end)
	return b
end

-- Section label ("RAID", "GUILD"...). A plain frame, not a Button, so it can never
-- take a click or steal the active highlight -- it only says what the rows under it
-- are for. Smaller and dimmer than a row: a signpost, not an entry.
local function makeNavHeader(parent)
	local h = CreateFrame("Frame", nil, parent)
	h:SetHeight(navHeaderH())
	local rule = h:CreateTexture(nil, "ARTWORK")
	rule:SetPoint("BOTTOMLEFT", 10, 3); rule:SetPoint("BOTTOMRIGHT", -10, 3); rule:SetHeight(1)
	rule:SetTexture(FLAT); rule:SetVertexColor(1, 1, 1, 0.07)
	h.text = W.Text(h, nil, math.max(8, navFont() - 3), "dim")
	h.text:SetPoint("BOTTOMLEFT", 10, 6); h.text:SetJustifyH("LEFT")
	return h
end

-- ------------------------------------------------------------
-- Shell (window)
-- ------------------------------------------------------------
function Okanvil:BuildShell()
	if self.win then return end
	local db = self.db

	local f = CreateFrame("Frame", "Okanvil_Window", UIParent)
	f:SetSize(WIN_W, WIN_H)          -- FIXED size (not resizable) -- use Scale to grow
	f:SetPoint(db.window.point, UIParent, db.window.point, db.window.x, db.window.y)
	f:SetScale(db.scale or 1)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetResizable(false)            -- no drag-resize: it broke layouts. Scale instead.
	self:Skin(f)
	self.win = f
	-- ESC closes the window: register it as a special frame (WoW hides frames in
	-- UISpecialFrames when Escape is pressed). Uses the frame's global name.
	tinsert(UISpecialFrames, "Okanvil_Window")
	-- SAFETY: closing the window must release any keyboard focus, so a text box can
	-- never keep eating W/A/S/D after you close the addon.
	f:HookScript("OnHide", function() Okanvil:ClearAllFocus() end)
	-- Clicking a bare area of the window drops focus where it can (a focused 3.3.5a
	-- EditBox captures input, so this won't fire in every case -- ESC and closing
	-- the window are the reliable releases).
	f:SetScript("OnMouseDown", function() Okanvil:ClearAllFocus() end)

	-- header (drag)
	local hdr = W.Frame(f, "raise")
	hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1); hdr:SetHeight(HEADER_H)
	hdr:EnableMouse(true); hdr:RegisterForDrag("LeftButton")
	hdr:SetScript("OnMouseDown", function() Okanvil:ClearAllFocus() end)  -- click header = stop typing
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
	local title = W.Text(hdr, "Okanvil", "title", "accent")
	title:SetPoint("LEFT", logo, "RIGHT", 7, 0); title:Color(1, 0.82, 0)
	local ver = W.Text(hdr, "v" .. (self.version or "1.0"), "note", "dim")
	ver:SetPoint("LEFT", title, "RIGHT", 6, -1)
	-- guild skin (editable) sits after the version as a dimmer suffix
	local brandFS = W.Text(hdr, "", "body", "dim")
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
	-- collapse to a small anvil icon (WeakAuras-style): hides the big window and
	-- shows a draggable puck so you can watch your game; click the puck to restore.
	local collapse = W.Button(hdr, "_"); collapse:SetSize(24, 20); collapse:SetPoint("RIGHT", close, "LEFT", -3, 0)
	collapse:SetScript("OnClick", function() Okanvil:Collapse(true) end)

	-- left nav
	local nav = W.Frame(f, "dark")
	nav:SetPoint("TOPLEFT", 6, -(HEADER_H + 6))
	nav:SetPoint("BOTTOMLEFT", 6, FOOTER_H + 4)
	nav:SetWidth(NAV_W)
	local navHdr = W.Text(nav, "NAVIGATION", "note", "dim"); navHdr:SetPoint("TOPLEFT", 10, -8)
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
	-- ONE shared rat behind every page (single mount; see MountPageRat).
	self:MountPageRat()

	-- footer: fixed author credit (Okanvil is by Okanor) + a flavor line
	local footer = W.Text(f, "|cffe0b860Okanvil by Okanor|r  |cff55575b--  the void in your stack trace|r", "note", "dim")
	footer:SetPoint("BOTTOMLEFT", 10, 6)
	-- web-hub link in the footer (WeakAuras-style): click -> copyable URL popup.
	local hubBtn = CreateFrame("Button", nil, f)
	hubBtn:SetHeight(14); hubBtn:SetPoint("BOTTOM", 0, 6)
	local hubTxt = W.Text(hubBtn, "", "note", "accent"); hubTxt:SetAllPoints(); hubTxt:SetJustifyH("CENTER")
	hubBtn.text = hubTxt
	self.footerHub = hubBtn
	local function paintHub()
		hubTxt:SetText("|cffe0b860Web Hub:|r |cff8a8d93" .. (self.db.hubURL or "") .. "|r")
		hubBtn:SetWidth(hubTxt:GetStringWidth() + 8)
	end
	paintHub(); self.footerPaintHub = paintHub
	hubBtn:SetScript("OnEnter", function() hubTxt:SetText("|cffffd200Web Hub:|r |cffffffff" .. (self.db.hubURL or "") .. "|r") end)
	hubBtn:SetScript("OnLeave", paintHub)
	hubBtn:SetScript("OnClick", function()
		if Okanvil.ShowExport then Okanvil:ShowExport(self.db.hubURL or "", "Web Hub -- Ctrl+C to copy") end
	end)
	self.footerCount = W.Text(f, "", "note", "dim")
	self.footerCount:SetPoint("BOTTOMRIGHT", -20, 6)

	-- (No resize grip: the window is fixed-size. Grow it with the Scale slider in
	-- Settings -- proportional and layout-safe.)

	-- The quick-access menu is parented to UIParent (so it can sit above the shell),
	-- which means hiding the window does NOT hide it. Hook the window's own OnHide
	-- and every close path is covered at once -- the X, the collapse, a DBM pull.
	f:SetScript("OnHide", function()
	end)

	self:RefreshNav()
	self:ShowPanel(HOME)
	f:Hide()
end

-- ------------------------------------------------------------
-- Collapse to a small draggable anvil puck (WeakAuras-style). Lets you watch the
-- game without the big window; click the puck to restore. The puck position is
-- saved so it stays where you left it.
-- ------------------------------------------------------------
function Okanvil:BuildPuck()
	if self.puck then return self.puck end
	local db = self.db
	db.puck = db.puck or { point = "CENTER", x = 0, y = 0 }
	local p = CreateFrame("Button", "Okanvil_Puck", UIParent)
	p:SetSize(48, 48)
	p:SetPoint(db.puck.point, UIParent, db.puck.point, db.puck.x, db.puck.y)
	p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetFrameLevel(200); p:SetToplevel(true)
	-- skin via SetBackdrop directly (safer on a Button than :Skin)
	p:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 } })
	p:SetBackdropColor(u3(C.panelHi)); p:SetBackdropBorderColor(u3(C.accent))
	local ic = p:CreateTexture(nil, "ARTWORK")
	ic:SetPoint("TOPLEFT", 4, -4); ic:SetPoint("BOTTOMRIGHT", -4, 4)
	ic:SetTexture("Interface\\Icons\\Trade_BlackSmithing"); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
	p:SetScript("OnDragStart", p.StartMoving)
	p:SetScript("OnDragStop", function(s)
		s:StopMovingOrSizing()
		local pt, _, _, x, y = s:GetPoint(1)
		db.puck.point, db.puck.x, db.puck.y = pt, x, y
	end)
	p:SetScript("OnClick", function() Okanvil:Collapse(false) end)
	p:SetScript("OnEnter", function(s)
		GameTooltip:SetOwner(s, "ANCHOR_LEFT")
		GameTooltip:AddLine("|cffffd200Okanvil|r")
		GameTooltip:AddLine("Click: open   ·   Drag: move", 1, 1, 1)
		GameTooltip:Show()
	end)
	p:SetScript("OnLeave", function() GameTooltip:Hide() end)
	p:Hide()
	self.puck = p
	return p
end

-- collapse(true) -> hide window, show puck. collapse(false) -> restore window.
function Okanvil:Collapse(on)
	local ok, err = pcall(function() self:BuildPuck() end)
	if not ok or not self.puck then
		-- puck failed to build -> DON'T hide the window (that would look like "close")
		self:Print("|cffff5555Collapse error:|r " .. tostring(err))
		return
	end
	if on then
		if self.win then self.win:Hide() end
		self.puck:Show()
		self.puck:Raise()
		self:Print("collapsed -- click the anvil puck (screen center) to reopen, or /okanvil")
	else
		self.puck:Hide()
		if self.win then self.win:Show() end
	end
end

-- ------------------------------------------------------------
-- Nav list
-- ------------------------------------------------------------
-- Built-in modules (rendered by the shell's own BuildLoot, not a
-- plugin build()). Listed here so they ALSO appear in the Modules manager and can
-- be toggled on/off exactly like the plugin modules. Home/Modules/Settings are the
-- fixed "core" and are never toggleable.
-- One coherent icon set (all verified 3.3.5a paths). Keep the nav icon and the
-- module's Dashboard header icon the SAME so the two never look mismatched.
Okanvil.ICONS = {
	home    = "Interface\\Icons\\INV_Misc_Rune_01",
	invite  = "Interface\\Icons\\Spell_ChargePositive",
	guild   = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
	loot    = "Interface\\Icons\\INV_Misc_Coin_02",
	logs    = "Interface\\Icons\\INV_Scroll_03",
	ids     = "Interface\\Icons\\INV_Misc_Spyglass_02",
	recruit = "Interface\\Icons\\Achievement_General_StayClassy",
	modules = "Interface\\Icons\\INV_Misc_Gear_01",
	settings= "Interface\\Icons\\Trade_Engineering",
	raidcheck = "Interface\\Icons\\INV_Misc_Food_15",   -- food buff (Raid Check)
}

Okanvil.NATIVE = {
	{ key = "__invite", title = "Invite", icon = Okanvil.ICONS.invite, noNav = true,
	  desc = "Auto-invite on a keyword. Set it up in Settings > Invite; invite people from Home." },
	{ key = "__guild",  title = "Guild",  icon = Okanvil.ICONS.guild, noNav = true,
	  desc = "Attendance snapshots + roster export. Both live on Home." },
	{ key = "__loot",   title = "Loot",   icon = Okanvil.ICONS.loot,
	  desc = "Per-boss loot tracking + Mini Roll Manager (MS/OS roll-offs, award, speed-run sweep)." },
}

-- Nav display order (top to bottom), by module TITLE. This is the ONE place to
-- set where a module sits in the menu -- add a new feature's title here at the
-- index you want. Home is always first; Modules + Settings are always last.
-- Anything enabled but NOT listed here falls to the end (alphabetical).
-- Raid Check and the Marks Bar are deliberately NOT here: neither has a page.
-- Both ARE their on-screen overlay, and their switches live in Settings > RAID TOOLS.
-- Nav sections. Same idea as the old flat NAV_ORDER -- one table you edit to
-- place a feature -- but grouped, so the shape of the list says what each entry
-- is FOR. A section with nothing enabled in it prints no header.
Okanvil.NAV_GROUPS = {
	{ section = nil,      items = { "Home" } },
	{ section = "RAID",   items = { "Loot", "Raid Finder", "PuG" } },
	{ section = "GUILD",  items = { "Recruit" } },
	{ section = "TOOLS",  items = { "ID Finder", "Settings" } },
}
-- flat order, derived: anything not named above still falls through alphabetically
Okanvil.NAV_ORDER = {}
for _, g in ipairs(Okanvil.NAV_GROUPS) do
	for _, t in ipairs(g.items) do Okanvil.NAV_ORDER[#Okanvil.NAV_ORDER + 1] = t end
end

function Okanvil:RefreshNav()
	if not self.navChild then return end
	for _, b in ipairs(self._navButtons) do b:Hide() end

	local list = {}

	-- Gather every enabled module (native + plugins) into one pool keyed by title,
	-- then emit them grouped, in the fixed order NAV_GROUPS gives. Anything not
	-- named there falls to the end (alphabetical) so a new plugin still shows up.
	local pool = {}
	for _, m in ipairs(self.NATIVE) do
		-- `noNav` = the module runs, and can still be switched off in Modules, but
		-- owns no page. Its settings live elsewhere (Settings, Home, the marks bar).
		-- Without this the only way to hide a page was to DISABLE the module, which
		-- also stops its engine -- auto-invite would quietly stop working.
		if self:IsModuleEnabled(m.key) and not m.noNav then
			pool[m.title] = { key = m.key, title = m.title, icon = m.icon }
		end
	end
	for name in pairs(self.entries) do
		-- plugins honour `noNav` too: a module whose UI is a floating window or a
		-- marks-bar button should not also claim a nav row
		if self:IsModuleEnabled(name) and not self.entries[name].noNav then
			local t = self.entries[name].title or name
			pool[t] = { key = name, title = t, icon = self.entries[name].icon }
		end
	end

	-- Home and Settings are the shell's own, not modules, so they are not in the
	-- pool -- put them there so the group table can place them like anything else.
	pool["Home"] = { key = HOME, title = "Home", icon = self.ICONS.home }
	pool["Settings"] = { key = SETTINGS, title = "Settings", icon = self.ICONS.settings }

	-- emit group by group. A header is only printed once we know the section has
	-- at least one enabled entry, so switching a module off never leaves a lone
	-- heading behind.
	local emitted = {}
	for _, g in ipairs(self.NAV_GROUPS) do
		local rows = {}
		for _, title in ipairs(g.items) do
			if pool[title] then rows[#rows + 1] = pool[title]; emitted[title] = true end
		end
		if #rows > 0 then
			if g.section then list[#list + 1] = { header = g.section } end
			for _, r in ipairs(rows) do list[#list + 1] = r end
		end
	end
	-- any enabled module not named above (future plugins), alphabetical, under TOOLS
	local leftover = {}
	for title in pairs(pool) do if not emitted[title] then leftover[#leftover + 1] = title end end
	table.sort(leftover)
	for _, title in ipairs(leftover) do list[#list + 1] = pool[title] end

	-- Headers and rows come from two separate pools: reusing a Button as a label
	-- would leave it clickable, so a section title would open whatever page that
	-- button last pointed at.
	local y, nb, nh = 0, 0, 0
	for _, item in ipairs(list) do
		if item.header then
			nh = nh + 1
			local h = self._navHeaders[nh] or makeNavHeader(self.navChild)
			self._navHeaders[nh] = h
			h:SetHeight(navHeaderH())
			h.text:SetFont(Okanvil:Font(), math.max(8, navFont() - 3))
			h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y); h:SetPoint("TOPRIGHT", 0, -y)
			h.text:SetText(item.header)
			h:Show()
			y = y + navHeaderH()
		else
			nb = nb + 1
			local b = self._navButtons[nb] or makeNavEntry(self.navChild)
			self._navButtons[nb] = b
			-- re-apply the metrics: the font slider can move since this row was built
			b:SetHeight(navRowH())
			b.icon:SetSize(navIcon(), navIcon())
			b.text:SetFont(Okanvil:Font(), navFont())
			b:ClearAllPoints(); b:SetPoint("TOPLEFT", 0, -y); b:SetPoint("TOPRIGHT", 0, -y)
			b.text:SetText(item.title)
			if item.icon then b.icon:SetTexture(item.icon); b.icon:Show() else b.icon:Hide() end
			b._key = item.key
			-- A module whose real UI is a floating window can claim its own nav click
			-- (navAction) rather than open a page that only says "open the window".
			local reg = Okanvil_Plugins and Okanvil_Plugins[item.key]
			local act = reg and reg.navAction
			if act then
				b:SetScript("OnClick", function() act() end)
			else
				b:SetScript("OnClick", function() Okanvil:ShowPanel(item.key) end)
			end
			b:Show()
			y = y + navRowH()
		end
	end
	for i = nh + 1, #self._navHeaders do self._navHeaders[i]:Hide() end
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
-- Shared "rat art" watermark -- ONE faded image in the content's bottom-right
-- corner, shown on every page. WoW 3.3.5a draws only BLP (DXT5) shipped in the
-- addon -> Media\rat1.blp (the Okanor blacksmith). db.ratArt "off" hides it.
-- Mounted once on Okanvil.content's ARTWORK layer (see MountPageRat), behind the
-- transparent "page" panels, so it is ALWAYS visible -- independent of panel
-- opacity, via its own db.ratAlpha slider -- and never duplicated.
-- ------------------------------------------------------------
local RAT_TEX = "Interface\\AddOns\\Okanvil\\Media\\rat1"
local function applyRatTex(tex)
	tex:SetTexture(RAT_TEX); tex:SetTexCoord(0, 1, 0, 1)
end

-- ONE rat, once, on the shared content well -- NOT per panel.
--
-- Old design mounted a rat on every panel (main + drawer + each scroll/fill
-- wrap), so a page with a drawer + inner scrolls showed 2-3 rats, each pinned to
-- its OWN corner => duplicated + misaligned art, plus a stray small one in list
-- columns. We now mount a SINGLE texture on `Okanvil.content` (the frame that
-- hosts every page), on its ARTWORK layer -- above content's own dark fill but
-- below the page panels, which are the transparent "page" skin -- so this one
-- rat reads as a true, uniform background behind every page and NEVER moves.
-- Its intensity is db.ratAlpha (its own Settings slider), so it stays visible
-- even at full panel opacity.
function Okanvil:MountPageRat()
	if self._pageRat then return self._pageRat end
	local host = self.content
	if not host then return end
	-- Single texture on the content well's ARTWORK layer -- ABOVE content's own
	-- dark BACKGROUND fill, but BELOW the page panels (which are now transparent,
	-- see the "page" skin) so it reads as a true background behind the content.
	-- One draw, fixed corner, never duplicated. Intensity = db.ratAlpha (its own
	-- Settings slider, independent of the panel opacity slider).
	local art = host:CreateTexture(nil, "ARTWORK")
	art:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -10, 10)
	local function refresh()
		if (Okanvil.db.ratArt or "on") == "off" then art:Hide(); return end
		applyRatTex(art)
		art:SetAlpha(Okanvil.db.ratAlpha or 0.30)
		local vw, vh = host:GetWidth() or 700, host:GetHeight() or 500
		local s = math.max(220, math.min(vh * 0.62, vw * 0.46))
		art:SetSize(s, s); art:Show()
	end
	art.refresh = refresh
	host:HookScript("OnSizeChanged", refresh)
	host:HookScript("OnShow", refresh)
	refresh()
	self._pageRat = art
	return art
end

-- Back-compat no-op: panels used to call this to get their own rat. Now the
-- single content rat covers every page, so per-panel mounts do nothing. Kept so
-- existing call sites don't error while we remove them.
function Okanvil:MountBgArt() end

-- refresh the single page rat (called from Settings when opacity/toggle changes).
function Okanvil:RefreshRatArt()
	if self._pageRat and self._pageRat.refresh then self._pageRat.refresh() end
end

local function newFillPanel()
	local wrap = CreateFrame("Frame", nil, Okanvil.content)
	wrap:SetPoint("TOPLEFT", 2, -2); wrap:SetPoint("BOTTOMRIGHT", -2, 2)
	wrap:Hide()
	wrap.child = wrap                 -- plugins anchor straight to the panel
	wrap.relayout = function() end
	-- (rat art is a single shared overlay on content -- no per-panel mount)
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
	-- (rat art is a single shared overlay on content -- no per-panel mount)
	return wrap
end

function Okanvil:ShowPanel(key)
	self:CloseDropdown()
	self:ClearAllFocus()          -- switching pages releases any text-box focus
	for _, b in ipairs(self._navButtons) do
		b._active = (b._key == key)
		if b._active then b.hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.10); b.bar:Show()
		else b.hl:SetVertexColor(0, 0, 0, 0); b.bar:Hide() end
	end

	local entry = self.panels[key]
	if not entry then
		if key == HOME then entry = self:BuildHome()
		elseif key == LOOT then entry = self:BuildLoot()
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

-- Drop a built page so the next ShowPanel rebuilds it. Pages are built once and
-- cached, which is right for a layout but wrong when what the page may SHOW has
-- changed underneath it.
function Okanvil:InvalidatePanel(key)
	local e = self.panels[key]
	if not e then return end
	if e.Hide then e:Hide() end
	if e.SetParent then e:SetParent(nil) end
	self.panels[key] = nil
	if self._current == key then self:ShowPanel(key) end
end

-- The guild roster arrives asynchronously, and the first GuildRoster() after
-- login can come back empty -- so an officer opening Loot early would be told
-- they are not one and lose the Prio tab until a /reload. Watch the roster and
-- rebuild the page the moment the answer actually changes.
do
	local was = nil
	local gr = CreateFrame("Frame")
	gr:RegisterEvent("GUILD_ROSTER_UPDATE")
	gr:RegisterEvent("PLAYER_GUILD_UPDATE")
	gr:SetScript("OnEvent", function()
		if not Okanvil.U or not Okanvil.U.canSeePrio then return end
		local now = Okanvil.U.canSeePrio() and true or false
		if was == nil then was = now; return end     -- first answer: nothing built yet
		if now ~= was then
			was = now
			Okanvil:InvalidatePanel(LOOT)
		end
	end)
end

-- ------------------------------------------------------------
-- Home
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- Shared UI kit. The page files (UI/Page_*.lua) load AFTER this one and pull the
-- few shell helpers they need off Okanvil.UI, so those helpers live in exactly
-- one place. `local newFillPanel = Okanvil.UI.newFillPanel` at the top of each
-- page keeps the call sites unchanged.
-- ------------------------------------------------------------
Okanvil.UI = Okanvil.UI or {}
Okanvil.UI.FLAT           = FLAT
Okanvil.UI.u3             = u3
Okanvil.UI.newFillPanel   = newFillPanel
Okanvil.UI.newScrollPanel = newScrollPanel

-- ------------------------------------------------------------
-- LAYOUT TOKENS
--
-- The numbers every page uses for the same job, in one place. They exist because
-- the pages drifted: the first element sat at y=-8 on Guild, -20 on Home, -14 on
-- Invite and -6 on Loot, and the left margin was 12 / 16 / 14 / 8. Nothing was
-- wrong on its own, but switching pages in the nav made the content JUMP, which
-- reads as sloppy even when each page looks fine alone.
--
-- A token is for a shared JOB, not for every number. A page with a genuine reason
-- to differ (a tight grid, a fixed column) still hardcodes its own value -- these
-- are the defaults, not a straitjacket.
-- ------------------------------------------------------------
Okanvil.UI.PAD_X    = 12   -- left margin of page content
Okanvil.UI.PAD_TOP  = 10   -- y of the first element on a page (use as -PAD_TOP)
Okanvil.UI.ROW_H    = 20   -- one row in a list
Okanvil.UI.SECTION  = 12   -- vertical gap between two blocks
Okanvil.UI.FIELD_H  = 46   -- vertical stride of one labelled control

-- ------------------------------------------------------------
-- The scroll area inside a W.Dashboard's main pane.
--
-- This exact block (scroll frame + thin accent slider + wheel + relayout) was
-- copy-pasted BYTE-IDENTICAL into Guild, Modules, Loot and Invite -- the only
-- difference was the left margin, which is now a token. Four copies meant a
-- scrolling fix had to be made four times, so it lives here once.
--
-- Returns the scroll child to draw into, plus `relayout()` to call after the
-- content height changes.
-- ------------------------------------------------------------
function Okanvil.UI.DashScroll(main, padX)
	local X = padX or Okanvil.UI.PAD_X
	local sf = CreateFrame("ScrollFrame", nil, main)
	sf:SetPoint("TOPLEFT", X, -8); sf:SetPoint("BOTTOMRIGHT", -14, 8)
	local p = CreateFrame("Frame", nil, sf); p:SetSize(10, 1); sf:SetScrollChild(p)
	local sb = CreateFrame("Slider", nil, main)
	sb:SetPoint("TOPRIGHT", -4, -8); sb:SetPoint("BOTTOMRIGHT", -4, 8); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
	local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetVertexColor(u3(C.accent)); th:SetSize(4, 40)
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 30) end)
	sf:SetScript("OnSizeChanged", function() p:SetWidth(sf:GetWidth()) end)
	return p, function()
		p:SetWidth(sf:GetWidth())
		local maxs = math.max(0, p:GetHeight() - sf:GetHeight())
		sb:SetMinMaxValues(0, maxs); sb:SetShown(maxs > 4)
	end, sf, sb
end
function Okanvil:Toggle()
	if not self.win then self:BuildShell() end
	if self.puck then self.puck:Hide() end   -- opening always leaves the collapsed puck
	if self.win:IsShown() then
		self:CloseDropdown()
		self.win:Hide()
	else
		self:RefreshNav()
		self.win:Show()
		self:ShowPanel(self._current or HOME)
	end
end
-- Hide EVERY Okanvil frame: the shell, the collapsed puck, the global dropdown, and
-- the mini roll manager. Wired to DBM's pull (see the DBM_Pull hook at PLAYER_LOGIN)
-- so the whole UI gets out of the way the instant the raid engages a boss. pcall'd
-- per frame so one missing piece can't stop the rest from closing.
function Okanvil:CloseAll()
	local function try(fn) local ok, err = pcall(fn); if not ok and self.Err then self:Err("CloseAll", err) end end
	if self.CloseDropdown then try(function() self:CloseDropdown() end) end
	if self.win     then try(function() self.win:Hide() end) end
	if self.puck    then try(function() self.puck:Hide() end) end
	if self.RollMgr and self.RollMgr.Hide then try(function() self.RollMgr.Hide() end) end
	-- The Raid Check toast goes too: once the boss is pulled, who was missing a
	-- flask is no longer actionable -- it is just something in front of the fight.
	if self.RaidCheck and self.RaidCheck.HideToast then
		try(function() self.RaidCheck:HideToast() end)
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
	b:SetScript("OnEnter", function(s) Okanvil:ShowMinimapTip(s) end)
	b:SetScript("OnLeave", function() Okanvil:HideMinimapTip() end)
	self.minimap = b
end

-- ------------------------------------------------------------
-- MINIMAP TOOLTIP  --  lockout grid (raid rows x toon columns)
--
-- Built as our OWN frame, not GameTooltip: the stock 3.3.5a tooltip only offers
-- AddLine / AddDoubleLine (two columns), and a grid of N toons needs N columns.
-- SavedInstances solves this with LibQTip; we do it with Okanvil.W instead, so no
-- new library enters the addon.
--
-- Columns are laid out by MEASURING text (fs:GetStringWidth()) rather than padding
-- with spaces -- the WoW font is proportional, so space-padding never lines up.
-- ------------------------------------------------------------
-- Tooltip scale. Row height tracks the font size, or lines overlap when it grows.
local TIP_FONT     = 15   -- body / grid cells
local TIP_TITLE    = 17   -- "Okanvil" wordmark
local TIP_SMALL    = 13   -- brand line, reset footer, click hint
local TIP_ROW_H    = TIP_FONT + 6
local TIP_PAD      = 14
local TIP_COL_GAP  = 16

function Okanvil:ShowMinimapTip(owner)
	local tip = self.minimapTip
	if not tip then
		tip = W.Frame(UIParent, "dark")       -- deepest panel: reads as a tooltip, not a window
		-- Opt OUT of the opacity slider: ReskinAll() would repaint this back to the
		-- stock panelD fill and undo the darker tooltip look below.
		if self._skinned then self._skinned[tip] = nil end
		tip:SetBackdropColor(0.04, 0.04, 0.05, 0.96)
		tip:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)  -- gold hairline
		tip:SetFrameStrata("TOOLTIP")
		tip:EnableMouse(false)          -- never eat clicks meant for the minimap
		tip:SetClampedToScreen(true)
		tip.rows = {}                   -- pooled FontStrings, reused between hovers
		-- A dedicated off-pool string used only to MEASURE text (GetStringWidth).
		-- It must not come from the pool, or the next line() would overwrite the
		-- very string we are still measuring with.
		tip.probe = W.Text(tip, nil, TIP_FONT)
		tip.probe:Hide()
		self.minimapTip = tip
	end

	-- release every pooled string from the last hover
	for _, fs in ipairs(tip.rows) do fs:Hide() end
	local used = 0
	local function line(text, size, role)
		used = used + 1
		local fs = tip.rows[used]
		if not fs then
			fs = W.Text(tip, nil, size or TIP_FONT, role)
			tip.rows[used] = fs
		end
		fs:SetFont(Okanvil:Font(), size or TIP_FONT)
		fs:SetText(text or "")
		fs:Show()
		return fs
	end

	local y = -TIP_PAD
	local maxW = 0

	-- header: fixed wordmark + optional guild skin
	local title = line("|cffffd200Okanvil|r", TIP_TITLE)
	title:ClearAllPoints(); title:SetPoint("TOPLEFT", TIP_PAD, y)
	maxW = math.max(maxW, title:GetStringWidth())
	y = y - (TIP_TITLE + 6)          -- the wordmark is taller than a body row

	local gb = self.db.brand
	if gb and gb ~= "" and gb ~= "Okanvil" then
		local sub = line(gb, TIP_SMALL); sub:Color(0.88, 0.72, 0.38)
		sub:ClearAllPoints(); sub:SetPoint("TOPLEFT", TIP_PAD, y)
		maxW = math.max(maxW, sub:GetStringWidth())
		y = y - (TIP_SMALL + 6)
	end

	-- ---------- the grid ----------
	local LO = self.Lockouts
	local toons = LO and LO:Get() or {}
	if #toons > 0 then
		y = y - 8
		local hdr = line("|cffc0943aSaved raids|r", TIP_FONT)
		hdr:ClearAllPoints(); hdr:SetPoint("TOPLEFT", TIP_PAD, y)
		y = y - TIP_ROW_H - 2

		-- Collect the distinct raids (rows) and the raid SIZES actually in use.
		-- cell[raid][toon][size] = true  -- a toon can be saved to the same raid at
		-- two sizes (10 AND 25), which is why size is a dimension and not a string.
		local raidOrder, cell, sizeSeen = {}, {}, {}
		local soonest
		for _, toon in ipairs(toons) do
			for _, inst in ipairs(toon.instances) do
				if not cell[inst.name] then
					cell[inst.name] = {}
					raidOrder[#raidOrder + 1] = inst.name
				end
				-- The label carries the difficulty, not just the size: a 25 normal and a
				-- 25 heroic are different lockouts and must not share a cell. "25H" /
				-- "10H" sorts after the plain size, which is the order we want.
				local n = (inst.players and inst.players > 0) and inst.players or 0
				local size = inst.heroic and (n .. "H") or tostring(n)
				cell[inst.name][toon.name] = cell[inst.name][toon.name] or {}
				cell[inst.name][toon.name][size] = true
				sizeSeen[size] = true
				if not soonest or inst.resets < soonest then soonest = inst.resets end
			end
		end
		table.sort(raidOrder)

		-- Sizes become FIXED sub-columns, ascending: 10H | 25 | 25H. This is what makes
		-- the grid line up -- a lone "25" lands in the 25-column, directly under every
		-- other 25, instead of drifting into a merged cell.
		--
		-- Sorted by the NUMBER first, then normal before heroic. A plain table.sort on
		-- the strings would order them lexically, which puts "10H" before "10" and
		-- breaks as soon as a label reaches two digits.
		local sizes = {}
		for s in pairs(sizeSeen) do sizes[#sizes + 1] = s end
		table.sort(sizes, function(a, b)
			local na = tonumber(a:match("%d+")) or 0
			local nb = tonumber(b:match("%d+")) or 0
			if na ~= nb then return na < nb end
			return (a:find("H") == nil) and (b:find("H") ~= nil)
		end)

		local probe = tip.probe
		probe:SetFont(Okanvil:Font(), TIP_FONT)

		-- column 1: raid name, as wide as the longest raid.
		--
		-- SHORT names ("ToGC", not "Trial of the Grand Crusader"): the full name is
		-- wider than the column, and with no SetWidth the FontString wrapped onto a
		-- second line and drew straight over the "resets in ..." footer beneath it.
		-- Abbreviating is also just how the raid talks about them.
		local shortOf = {}
		local nameW = 0
		for _, raid in ipairs(raidOrder) do
			local s = (Okanvil.U and Okanvil.U.raidShort) and Okanvil.U.raidShort(raid) or raid
			shortOf[raid] = s
			probe:SetText(s)
			nameW = math.max(nameW, probe:GetStringWidth())
		end

		-- Sub-column width: the widest size label, same for all -- uniform cells are
		-- what let the eye scan a column straight down.
		local cellW = 0
		for _, s in ipairs(sizes) do
			probe:SetText(tostring(s))
			cellW = math.max(cellW, probe:GetStringWidth())
		end
		cellW = cellW + 6

		-- Each toon gets only the sub-columns it ACTUALLY uses. A toon with nothing but
		-- 25s does not need a 10H column standing empty next to it, and reserving one
		-- for every difficulty any toon anywhere is saved to made the tooltip much wider
		-- than the data in it. Work out each toon's own set of labels.
		local toonSizes = {}
		for _, toon in ipairs(toons) do
			local seen, list = {}, {}
			for _, raid in ipairs(raidOrder) do
				local saved = cell[raid][toon.name]
				if saved then
					for s in pairs(saved) do
						if not seen[s] then seen[s] = true; list[#list + 1] = s end
					end
				end
			end
			-- keep the global column order, so the same label sits at the same depth
			local ordered = {}
			for _, s in ipairs(sizes) do
				if seen[s] then ordered[#ordered + 1] = s end
			end
			toonSizes[toon.name] = ordered
		end

		-- The block must also be wide enough for the toon's NAME, or the header
		-- FontString truncates it to "Oka...". Widen to whichever is bigger; the cells
		-- centre inside it.
		local colX, blockW, cellOff = {}, {}, {}
		local x = TIP_PAD + nameW + TIP_COL_GAP
		for _, toon in ipairs(toons) do
			local n = #toonSizes[toon.name]
			local cellsW = math.max(1, n) * cellW + math.max(0, n - 1) * 4
			probe:SetText(toon.name)
			local w = math.max(cellsW, probe:GetStringWidth())
			colX[toon.name]   = x
			blockW[toon.name] = w
			cellOff[toon.name] = (w - cellsW) / 2
			x = x + w + TIP_COL_GAP
		end
		maxW = math.max(maxW, x - TIP_COL_GAP - TIP_PAD)

		-- header row: toon names, class-coloured, centred over their block
		for _, toon in ipairs(toons) do
			local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[toon.class]
			local fs = line(toon.name, TIP_FONT)
			if c then fs:Color(c.r, c.g, c.b) end
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", colX[toon.name], y)
			fs:SetWidth(blockW[toon.name]); fs:Justify("CENTER")
		end
		y = y - TIP_ROW_H

		-- one row per raid; a cell per sub-column THIS toon uses
		for _, raid in ipairs(raidOrder) do
			local nm = line(shortOf[raid] or raid, TIP_FONT)
			nm:ClearAllPoints(); nm:SetPoint("TOPLEFT", TIP_PAD, y)
			-- pin the width: without it a long name wraps onto the next row
			nm:SetWidth(nameW); nm:Justify("LEFT")
			if nm.SetWordWrap then nm:SetWordWrap(false) end
			for _, toon in ipairs(toons) do
				local saved = cell[raid][toon.name]
				for i, s in ipairs(toonSizes[toon.name]) do
					local fs = line(saved and saved[s] and tostring(s) or "", TIP_FONT)
					fs:ClearAllPoints()
					fs:SetPoint("TOPLEFT",
						colX[toon.name] + cellOff[toon.name] + (i - 1) * (cellW + 4), y)
					fs:SetWidth(cellW); fs:Justify("CENTER")
				end
			end
			y = y - TIP_ROW_H
		end

		-- Every WotLK raid lockout resets on the same weekly server tick, so a
		-- per-row countdown would repeat the same value N times. One footer instead.
		if soonest then
			y = y - 4
			local rst = line("resets in " .. LO:FormatTime(soonest - time()), TIP_SMALL, "dim")
			rst:ClearAllPoints(); rst:SetPoint("TOPLEFT", TIP_PAD, y)
			y = y - TIP_ROW_H
		end
	end

	y = y - 6
	local hint = line("Click: open", TIP_SMALL, "dim")
	hint:ClearAllPoints(); hint:SetPoint("TOPLEFT", TIP_PAD, y)
	maxW = math.max(maxW, hint:GetStringWidth())
	y = y - TIP_ROW_H

	tip:SetSize(maxW + TIP_PAD * 2, -y + TIP_PAD - TIP_ROW_H + 6)
	-- Anchor BELOW the button (the minimap button lives near the top of the screen,
	-- so anchoring above would run it off the top edge).
	tip:ClearAllPoints()
	tip:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", 0, -4)
	tip:Show()
end

function Okanvil:HideMinimapTip()
	if self.minimapTip then self.minimapTip:Hide() end
end
