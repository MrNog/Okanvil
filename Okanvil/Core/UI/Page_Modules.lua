-- ============================================================
-- Okanvil -- UI: Modules page
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

-- Modules is its own nav entry under TOOLS. It was a Settings pill, which read
-- as configuration -- but this is not a setting, it is what the addon HAS, and
-- somebody looking for a feature they remember will not think to open Settings.
function Okanvil:BuildModules()
	local fill = newFillPanel()
	local host = fill.child

	local dash = W.Dashboard(host, {
		title = "Modules",
		subtitle = "What this character uses",
		icon = Okanvil.ICONS.modules or "Interface\\Icons\\INV_Misc_Gear_01",
		drawerWidth = 0,
		footerHeight = 0,
	})
	self:Settings_Modules(dash.main)
	return fill
end

-- The list itself. Still callable on any panel, so the page above and anything
-- else that wants it draw the same thing.
function Okanvil:Settings_Modules(panel)
	local X = 4

	local hint = W.FixedText(panel, "For this character. Off = hidden from the menu; each module's settings stay shared across your toons.", 13, "dim")
	hint:SetPoint("TOPLEFT", X, -6); hint:SetPoint("RIGHT", panel, "RIGHT", -X, 0); hint:SetJustifyH("LEFT")

	-- SCROLLED. Twelve modules is taller than the page, so the last few were cut
	-- off with nothing to say they existed -- the list grows every time a module
	-- is added, and the window does not.
	local sf = CreateFrame("ScrollFrame", nil, panel)
	sf:SetPoint("TOPLEFT", 0, -38)
	sf:SetPoint("BOTTOMRIGHT", 0, 0)
	Okanvil.Clip(sf)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(1, 1)
	sf:SetScrollChild(child)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(self, delta)
		local cur = self:GetVerticalScroll()
		local max = math.max(0, child:GetHeight() - self:GetHeight())
		local nxt = cur - delta * 60
		if nxt < 0 then nxt = 0 elseif nxt > max then nxt = max end
		self:SetVerticalScroll(nxt)
	end)
	-- The child must track the scrollframe's width or the rows anchor to nothing.
	sf:SetScript("OnSizeChanged", function(self, w) child:SetWidth(w or 1) end)

	local p = child
	local wrap = { relayout = function() end }

	wrap.rows = {}
	-- Two groups, as in the first-run setup: what every raider keeps on, then the
	-- optional rest. Section labels are built once and placed on every rebuild.
	local ESSENTIAL = { ["__council"] = true, ["Okanvil-Notes"] = true }
	local secEss = W.FixedText(p, "ESSENTIALS", 13); secEss:SetTextColor(u3(C.accentText))
	local secExt = W.FixedText(p, "EXTRAS", 13); secExt:SetTextColor(u3(C.accentText))
	-- the two checkbox columns: is the module on, and is its page on the marks bar
	local COL_ON, COL_BAR = -20, -100
	local hOn = W.FixedText(panel, "On", 13); hOn:SetTextColor(u3(C.accentText))
	hOn:SetPoint("BOTTOM", panel, "TOPRIGHT", COL_ON - 12 + 4, -30)
	local hBar = W.FixedText(panel, "On bar", 13); hBar:SetTextColor(u3(C.accentText))
	hBar:SetPoint("BOTTOM", panel, "TOPRIGHT", COL_BAR - 12 + 4, -30)
	-- a checkbox button: 24x24, tick shown while on
	local function checkButton(parent)
		local b = CreateFrame("Button", nil, parent)
		b:SetSize(24, 24)
		local box, tick = W.CheckTextures(b, 24)
		box:SetPoint("CENTER")
		function b:SetChecked(on) if on then tick:Show() else tick:Hide() end end
		return b
	end
	local function rebuild()
		for _, r in ipairs(wrap.rows) do r:Hide() end
		local all = Okanvil:ModuleItems(true)
		local items = {}
		for _, it in ipairs(all) do if ESSENTIAL[it.key] then items[#items + 1] = it end end
		local nEss = #items
		for _, it in ipairs(all) do if not ESSENTIAL[it.key] then items[#items + 1] = it end end
		if wrap.empty then wrap.empty:SetText("") end

		-- Starts at 0: the hint is outside the scroll frame now, so the rows no
		-- longer need to leave room for it.
		local y = 0
		for i, it in ipairs(items) do
			if i == 1 and nEss > 0 then
				secEss:ClearAllPoints(); secEss:SetPoint("TOPLEFT", X, -y - 4)
				y = y + 26
			end
			if i == nEss + 1 then
				secExt:ClearAllPoints(); secExt:SetPoint("TOPLEFT", X, -y - 10)
				y = y + 32
			end
			local name = it.key
			local r = wrap.rows[i]
			if not r then
				r = W.Frame(p, "row")
				-- the module's icon in the kit frame: gold while on, grey while off
				r.slot = W.FramedIcon(r, nil, 34, true)
				r.slot:SetPoint("LEFT", 6, 0)
				r.icon = r.slot.icon
				r.title = W.FixedText(r, "", 16); r.title:SetPoint("TOPLEFT", r.slot, "TOPRIGHT", 12, 0)
				r.desc = W.FixedText(r, "", 13, "dim")
				r.desc:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
				r.desc:SetPoint("RIGHT", r, "RIGHT", -140, 0); r.desc:SetJustifyH("LEFT")
				-- On: is the module on at all
				r.toggle = checkButton(r)
				r.toggle:SetPoint("RIGHT", COL_ON + X + 4, 0)

				-- On bar: is this page on the marks bar's shortcut strip. A different
				-- question from whether the module is on; which pages earn the space
				-- is one guild's answer, not the addon's.
				r.sc = checkButton(r)
				r.sc:SetPoint("RIGHT", COL_BAR + X + 4, 0)
				wrap.rows[i] = r
			end
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", X, -y); r:SetPoint("RIGHT", p, "RIGHT", -X, 0)
			r:SetHeight(52)
			r.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			r.title:SetText(it.title or name)
			r.desc:SetText(it.desc or "")

			local function paintToggle()
				local on = Okanvil:IsModuleEnabled(name) or it.shortcutOnly
				r.toggle:SetChecked(on)
				W.SetFramedIconUsable(r.slot, on and true or false)
			end
			paintToggle()
			-- A module with no on/off (Invite) shows the Shortcut switch alone.
			-- Rows are reused, so the button is re-anchored either way.
			if it.shortcutOnly then r.toggle:Hide() else r.toggle:Show() end

			-- Only for a module that HAS a page on the strip. Guild draws no nav row
			-- at all and Combat Logs lives inside Settings, so a Shortcut switch on
			-- those rows was a button with nothing to show or hide.
			local hasPanel = it.shortcutOnly
				or (Okanvil.PANEL_TITLE and Okanvil.PANEL_TITLE[name]) ~= nil
			r.sc:SetShown(hasPanel)

			local function paintSc()
				if not hasPanel then return end
				local on = not Okanvil.IsShortcutEnabled
					or Okanvil:IsShortcutEnabled(name)
				r.sc:SetChecked(on)
			end
			paintSc()
			r.sc:SetScript("OnClick", function()
				if not Okanvil.SetShortcutEnabled then return end
				Okanvil:SetShortcutEnabled(name, not Okanvil:IsShortcutEnabled(name))
				paintSc()
			end)

			r.toggle:SetScript("OnClick", function()
				Okanvil:SetModuleEnabled(name, not Okanvil:IsModuleEnabled(name))
				paintToggle()
				-- What actually has to change is the NAV: a module switched off loses
				-- its row, one switched on gains it back. This called `dash:Refresh()`
				-- on a global that was never defined here, so every toggle threw
				-- "attempt to index global 'dash'".
				Okanvil:RefreshNav()
				-- Pages built before the toggle are stale: Home hides the snapshot
				-- tab and the roster export when Guild is off, and it is cached, so
				-- without this the switch appeared to do nothing at all.
				if Okanvil.InvalidatePanel then Okanvil:InvalidatePanel("__home") end
			end)
			r:Show()
			y = y + 54
		end
		p:SetHeight(math.max(y + 10, 200))
	end

	wrap._rebuild = rebuild
	panel:SetScript("OnShow", rebuild)
	rebuild()
end

-- ------------------------------------------------------------
-- Toggle
-- ------------------------------------------------------------
