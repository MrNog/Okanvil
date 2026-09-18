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

-- Modules is a list of on/off switches -- configuration, which is what Settings
-- is for. It had its own nav row purely because it predated the Settings tabs.
function Okanvil:Settings_Modules(panel)
	local X = 4
	local p = panel
	local wrap = { relayout = function() end }
	local sf = panel

	local hint = W.Text(p, "Turn modules on/off for THIS character (off = hidden from the menu). Each module's settings stay shared across your toons.", 11, "dim")
	hint:SetPoint("TOPLEFT", X, -6); hint:SetPoint("RIGHT", p, "RIGHT", -X, 0); hint:SetJustifyH("LEFT")

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

		local y = 44
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
				dash:Refresh()
			end)
			r:Show()
			y = y + 50
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
