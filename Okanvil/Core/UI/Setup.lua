-- ============================================================
-- Okanvil -- UI: first-run setup
--
-- Shown once, on the first login of an install that has never run Okanvil
-- (db.setupPending, set in Core.lua when Okanvil_DB is created). It asks the
-- two things a new user cannot guess: which modules this character wants, and
-- whether the marks bar shows. Every choice is also on the Modules and Settings
-- pages, so Skip loses nothing. /okanvil setup and the Settings button bring it
-- back.
--
-- Nothing applies until Save: the ticks are a draft, so closing the window half
-- way through leaves the install exactly as it was.
-- ============================================================

local Okanvil = Okanvil
local W = Okanvil.W

local WIN_W, COL_W, ROW_H = 560, 250, 28

local setupF

local function finish()
	Okanvil.db.setupPending = nil
	if setupF then setupF:Hide() end
end

function Okanvil:ShowSetup()
	if setupF then setupF:Hide() end

	local f = CreateFrame("Frame", "Okanvil_Setup", UIParent)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetPoint("CENTER")
	self:Skin(f)
	local C = self.Colors
	f:SetBackdropColor(C.panelD[1], C.panelD[2], C.panelD[3], 0.97)
	setupF = f

	local X = 20
	local title = W.Text(f, "Welcome to Okanvil", "huge", "accent")
	title:SetPoint("TOPLEFT", X, -18)
	local intro = W.Text(f, "Pick what you want to use. You can change all of this later"
		.. " on the Modules and Settings pages.", "body", "dim")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetWidth(WIN_W - X * 2)
	intro:SetJustifyH("LEFT")

	-- ---- modules: a draft of the enable flags, applied on Save ----
	local items = self:ModuleItems()
	local want = {}
	for _, it in ipairs(items) do want[it.key] = self:IsModuleEnabled(it.key) end

	local y = -84
	W.Section(f, "MODULES", X, y, WIN_W - X * 2)
	y = y - 26
	local note = W.Text(f, "For this character. Hover a module to see what it does.", "note", "dim")
	note:SetPoint("TOPLEFT", X, y)
	y = y - 22

	for i, it in ipairs(items) do
		local col = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		local cx, cy = X + col * COL_W, y - row * ROW_H

		local icon = f:CreateTexture(nil, "ARTWORK")
		icon:SetSize(20, 20)
		icon:SetPoint("TOPLEFT", cx, cy)
		if it.icon then
			icon:SetTexture(it.icon)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end

		local key = it.key
		local chk = W.Check(f, it.title or key,
			function() return want[key] end,
			function(v) want[key] = v and true or false end)
		chk:SetPoint("TOPLEFT", cx + 28, cy - 1)
		if it.desc then chk:Tooltip(it.desc) end
	end
	y = y - math.ceil(#items / 2) * ROW_H - 10

	-- ---- shortcuts: the marks bar is where the page shortcuts live ----
	local MB = self.MarksBar
	local wantBar = true
	if MB then
		W.Section(f, "SHORTCUTS", X, y, WIN_W - X * 2)
		y = y - 28
		local bar = W.Check(f, "Show the marks bar",
			function() return wantBar end,
			function(v) wantBar = v and true or false end)
		bar:SetPoint("TOPLEFT", X, y)
		bar:Tooltip("A small bar with raid marks, ready check, pull timer and"
			.. "\none-click shortcuts into the Okanvil pages you use most.")
		y = y - 22
		local barNote = W.Text(f, "Marks and pull only appear while you are leader or assist;"
			.. " the shortcuts are always yours.", "note", "dim")
		barNote:SetPoint("TOPLEFT", X + 24, y)
		barNote:SetWidth(WIN_W - X * 2 - 24)
		barNote:SetJustifyH("LEFT")
		y = y - 26
	end

	-- ---- footer ----
	local save = W.Button(f, "Save", "primary")
	save:SetSize(110, 26)
	save:SetPoint("BOTTOMRIGHT", -X, 16)
	save:SetScript("OnClick", function()
		for _, it in ipairs(items) do
			if want[it.key] ~= self:IsModuleEnabled(it.key) then
				self:SetModuleEnabled(it.key, want[it.key])
			end
		end
		if MB and MB.Toggle then MB:Toggle(wantBar) end
		finish()
		self:Print("setup saved. |cff8a8d93Run it again any time with|r |cff00ff00/okanvil setup|r.")
	end)

	local skip = W.Button(f, "Skip")
	skip:SetSize(90, 26)
	skip:SetPoint("RIGHT", save, "LEFT", -8, 0)
	skip:Tooltip("Keep everything as it is. /okanvil setup brings this back.")
	skip:SetScript("OnClick", finish)

	f:SetSize(WIN_W, math.abs(y) + 60)
	f:Show()
end
