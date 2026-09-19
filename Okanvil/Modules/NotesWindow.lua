-- ============================================================
-- Okanvil -- Notes: the floating fight window.
--
-- What you actually watch during a pull: the current boss's note as timed
-- lines, on its own frame, so the main window can stay closed.
--
-- Skada-style handling: unlock to drag, grab the corner to resize, and it
-- remembers where you put it. Its settings live on the Fight window pill in the
-- Notes page rather than a right-click menu -- the menu closed the moment you
-- clicked anything in it.
-- ============================================================

local ADDON = "Okanvil-Notes"
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

local N = Okanvil.Notes
local W = Okanvil.W
local C = Okanvil.Colors

local win
local ROW_H = 22        -- recomputed from cfg().size when it changes

local function db() return (N and N.db) or nil end

local function cfg()
	local d = db()
	if not d then return {} end
	d.window = d.window or {
		shown = false, locked = true, alpha = 0.6, size = 13,
		onlyInRoom = true,   -- hide unless standing in the selected boss's room
		w = 260, h = 190, point = nil,
	}
	return d.window
end

-- ------------------------------------------------------------
-- Build
-- ------------------------------------------------------------
local function applyLook()
	if not win then return end
	local c = cfg()
	win:SetBackdropColor(C.panelD[1], C.panelD[2], C.panelD[3], c.alpha or 0.85)
	win:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], (c.alpha or 0.85) + 0.1)
	-- Locked: click-through everywhere but the rows, so it never eats a click
	-- meant for the game. Unlocked: grabbable, with the grip showing.
	win.grip:SetShown(not c.locked)
	win.title:SetShown(not c.locked)

	-- Gold shut, green open: the padlock says which state you are in without a
	-- tooltip, and the open one is the one you want to notice.
	if win.lock and win.lock.tint then
		win.lock.shackleL:SetPoint("BOTTOMLEFT", win.lock.body, "TOPLEFT", c.locked and 2 or 5, 0)
		win.lock.tint(0.6)
	end

	-- Text size is per-window, not the global scale: this is the one thing you
	-- read mid-pull, and it wants to be bigger than the rest of the addon.
	--
	-- At low opacity there is no panel behind the text any more, so it gets an
	-- outline to stay readable against whatever the fight is drawing.
	local size = c.size or 13
	ROW_H = size + 9
	local font = Okanvil:Font()
	local flag = ((c.alpha or 0.6) < 0.35) and "OUTLINE" or nil
	for i, r in ipairs(win.rows or {}) do
		r:SetHeight(ROW_H)
		r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
		r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
		r.t:SetFont(font, size, flag)
		r.txt:SetFont(font, size, flag)
		r.t:SetWidth(size * 3.2)
	end
	if win._entries then
		win:SetHeight(18 + (#win._entries * ROW_H) + 6)
	end
end

local function savePoint()
	if not win then return end
	local point, _, relPoint, x, y = win:GetPoint(1)
	local c = cfg()
	c.point = { point = point, relPoint = relPoint, x = x, y = y }
end

local function applyPoint()
	if not win then return end
	win:ClearAllPoints()
	local p = cfg().point
	if p and p.point then
		win:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
	else
		win:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
	end
end

local function row(i)
	local r = win.rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, win.child)
	r:SetHeight(ROW_H)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)

	r.t = W.Text(r, "", "head", "accent")
	r.t:SetPoint("LEFT", 4, 0)
	r.t:SetWidth(38); r.t:SetJustifyH("RIGHT")

	r.mark = r:CreateTexture(nil, "BACKGROUND")
	r.mark:SetTexture(FLAT)
	r.mark:SetPoint("TOPLEFT", 0, 0)
	r.mark:SetPoint("BOTTOMLEFT", 0, 0)
	r.mark:SetWidth(2)
	do local a = C.accentHi; r.mark:SetVertexColor(a[1], a[2], a[3], 1) end
	r.mark:Hide()

	r.txt = W.Text(r, "", "head")
	r.txt:SetPoint("LEFT", r.t, "RIGHT", 6, 0)
	r.txt:SetPoint("RIGHT", -4, 0)
	r.txt:SetJustifyH("LEFT")
	if r.txt.SetWordWrap then r.txt:SetWordWrap(false) end

	win.rows[i] = r
	return r
end

local function build()
	if win then return win end
	local f = CreateFrame("Frame", "Okanvil_NotesWindow", UIParent)
	local c = cfg()
	f:SetSize(c.w or 260, c.h or 190)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetResizable(true)
	if f.SetMinResize then f:SetMinResize(160, 80) end
	f:SetBackdrop({
		bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	f.rows = {}

	-- The title only shows while unlocked: in a fight it is one more thing to
	-- read past, and once placed you know what the window is.
	f.title = W.Text(f, "Notes", "note", "dim")
	f.title:SetPoint("TOPLEFT", 6, -4)

	-- Lock toggle, Skada-style: invisible until the mouse is over the window,
	-- so locking lives on the thing being locked instead of a settings page.
	local lock = CreateFrame("Button", nil, f)
	lock:SetSize(16, 16)
	lock:SetPoint("TOPRIGHT", -3, -3)
	lock:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
	-- Drawn, not a Blizzard texture: LockButton-* is not present on 3.3.5a, so
	-- an icon referencing it renders as nothing at all. A shackle over a body,
	-- from the same flat texture as the rest of the addon.
	lock.body = lock:CreateTexture(nil, "OVERLAY")
	lock.body:SetTexture(FLAT)
	lock.body:SetPoint("BOTTOMLEFT", 3, 2)
	lock.body:SetPoint("BOTTOMRIGHT", -3, 2)
	lock.body:SetHeight(7)

	lock.shackleL = lock:CreateTexture(nil, "OVERLAY")
	lock.shackleL:SetTexture(FLAT)
	lock.shackleL:SetSize(2, 5)
	lock.shackleL:SetPoint("BOTTOMLEFT", lock.body, "TOPLEFT", 2, 0)

	lock.shackleR = lock:CreateTexture(nil, "OVERLAY")
	lock.shackleR:SetTexture(FLAT)
	lock.shackleR:SetSize(2, 5)
	lock.shackleR:SetPoint("BOTTOMRIGHT", lock.body, "TOPRIGHT", -2, 0)

	lock.shackleT = lock:CreateTexture(nil, "OVERLAY")
	lock.shackleT:SetTexture(FLAT)
	lock.shackleT:SetHeight(2)
	lock.shackleT:SetPoint("BOTTOMLEFT", lock.shackleL, "TOPLEFT", 0, 0)
	lock.shackleT:SetPoint("BOTTOMRIGHT", lock.shackleR, "TOPRIGHT", 0, 0)

	lock.tint = function(a)
		local col = cfg().locked and C.accentHi or C.ok
		for _, t in ipairs({ lock.body, lock.shackleL, lock.shackleR, lock.shackleT }) do
			t:SetVertexColor(col[1], col[2], col[3], a)
		end
	end
	lock:Hide()
	lock:SetScript("OnClick", function()
		Okanvil.NotesWindow.SetLocked(not Okanvil.NotesWindow.IsLocked())
	end)
	lock:SetScript("OnEnter", function(s)
		s.tint(1)
		GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
		GameTooltip:SetText(cfg().locked and "Unlock: drag and resize" or "Lock in place")
		GameTooltip:Show()
	end)
	lock:SetScript("OnLeave", function(s)
		s.tint(0.6)
		GameTooltip:Hide()
	end)
	f.lock = lock

	-- The padlock appears on hover, polled in OnUpdate rather than driven by
	-- OnEnter/OnLeave: children (the grip, the rows) take the mouse first and
	-- the window's own enter/leave fire at the wrong moments. IsMouseOver is
	-- true for the window and anything inside it, which is exactly the question.
	f._hover = false

	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(s)
		if cfg().locked then return end
		s:StartMoving()
	end)
	f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); savePoint() end)

	-- Resize grip, the way MRT does it: a Frame (not a Button) raised above
	-- everything else in the window, or the scroll frame swallows the drag.
	local grip = CreateFrame("Frame", nil, f)
	grip:SetSize(15, 15)
	grip:SetPoint("BOTTOMRIGHT", 0, 0)
	grip:EnableMouse(true)
	grip:SetFrameStrata("DIALOG")
	grip:SetFrameLevel((f:GetFrameLevel() or 1) + 50)
	local gt = grip:CreateTexture(nil, "OVERLAY")
	gt:SetPoint("BOTTOMRIGHT", -2, 2)
	gt:SetSize(10, 10)
	gt:SetTexture(FLAT)
	gt:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
	grip:SetScript("OnMouseDown", function()
		if f.SetResizable then f:SetResizable(true) end
		if f.StartSizing then f:StartSizing("BOTTOMRIGHT") end
	end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		-- Only the width is remembered: the height is whatever the note needs.
		cfg().w = f:GetWidth()
		savePoint()
		Okanvil.NotesWindow.Refresh()
	end)
	f.grip = grip

	-- The lines, in a plain frame -- no scroll. A note is short and the window
	-- grows to fit it, and the scroll frame this replaced covered the whole
	-- window and swallowed every mouse event meant for it.
	local child = CreateFrame("Frame", nil, f)
	child:SetPoint("TOPLEFT", 4, -18)
	child:SetPoint("BOTTOMRIGHT", -4, 4)
	f.child = child

	f.empty = W.Text(f, "", "note", "dim")
	f.empty:SetPoint("TOPLEFT", 8, -22)
	f.empty:SetPoint("RIGHT", -8, 0)
	f.empty:SetJustifyH("LEFT")

	-- Repaint while a fight is running; idle otherwise. The same tick shows and
	-- hides the padlock, at 10/s so it feels immediate.
	f:SetScript("OnUpdate", function(s, el)
		s._h = (s._h or 0) + el
		if s._h >= 0.1 then
			s._h = 0
			local over = s:IsMouseOver()
			if over ~= s._hover then
				s._hover = over
				if over then s.lock:Show() else s.lock:Hide() end
			end
		end
		s._t = (s._t or 0) + el
		if s._t < 0.2 then return end
		s._t = 0
		Okanvil.NotesWindow.Refresh()
	end)

	win = f
	applyPoint()
	applyLook()
	return f
end

-- ------------------------------------------------------------
-- Paint
-- ------------------------------------------------------------
local WIN = {}
Okanvil.NotesWindow = WIN

local function fmt(s)
	if s >= 60 then return ("%d:%02d"):format(math.floor(s / 60), math.floor(s % 60)) end
	if s >= 10 then return ("%d"):format(math.floor(s)) end
	return ("%.1f"):format(s)
end

function WIN.Refresh()
	if not win then return end

	if not win:IsShown() then return end
	local P = Okanvil.NotesParse
	local d = db()
	-- N.Get, not d.notes: a note you have not edited lives in the shipped pack,
	-- and reading the table directly showed nothing for eleven of twelve bosses.
	local note = d and d.selected and N.Get(d.selected)

	if not note or note == "" then
		for _, r in ipairs(win.rows) do r:Hide() end
		win.empty:SetText(d and d.selected
			and ("|cff6f7176No note for " .. d.selected .. ".|r")
			or "|cff6f7176No note picked.|r")
		-- Shrink to the message: without this the window keeps the height of
		-- whatever note was last shown, as a big empty box.
		win._entries = nil
		win:SetHeight(46)
		return
	end
	win.empty:SetText("")

	-- Standing somewhere else, this is a note you are READING, not a fight in
	-- progress. Say so, rather than showing timers that will never start.

	-- Reparse only when the text changed: this runs five times a second.
	if win._src ~= note then
		win._src = note
		win._entries = P and P.Parse(note) or {}
	end
	local entries = win._entries or {}
	local now = GetTime()

	for _, r in ipairs(win.rows) do r:Hide() end
	for i, e in ipairs(entries) do
		local r = row(i)
		r:Show()
		r.txt:SetText(P and P.Render(e.text) or (e.text or ""))
		-- Your own line, marked: four names read the same at a glance, and the
		-- one that matters is the one with your name in it.
		if r.mark then r.mark:SetShown(e.mine and true or false) end
		r.txt:SetAlpha(e.mine and 1 or 0.72)
		if e.plain then
			r.t:SetText("")
			r:SetAlpha(1)
		else
			local left = P and P.Remaining(e, now)
			if not left then
				r.t:SetText(("|cff6f7176%d:%02d|r"):format(math.floor(e.time / 60), e.time % 60))
				r:SetAlpha(1)
			elseif left <= 0 then
				r.t:SetText("")
				r:SetAlpha(0.4)
			else
				local col = left <= 5 and "|cffff5555" or (left <= 10 and "|cffe0b860" or "|cff7cfc8a")
				r.t:SetText(col .. fmt(left) .. "|r")
				r:SetAlpha(1)
			end
		end
	end

	-- Grow to the note: 18px header strip + the lines + a little bottom padding.
	local want = 18 + (#entries * ROW_H) + 6
	if math.abs((win:GetHeight() or 0) - want) > 1 then
		win:SetHeight(want)
		cfg().h = want
	end
end

function WIN.Toggle(state)
	if not db() then
		Okanvil:Print("|cffff5555Notes not loaded yet.|r")
		return
	end
	local ok, err = pcall(build)
	if not ok then
		Okanvil:Print("|cffff5555Fight window failed to build:|r " .. tostring(err))
		return
	end
	if not win then
		Okanvil:Print("|cffff5555Fight window did not build.|r")
		return
	end
	local c = cfg()
	-- Toggle the SETTING, not the frame. Out of the boss's room the frame is
	-- hidden while the window is on, so reading the frame meant every press out
	-- there turned it "on" again -- and it could never be switched off, or on.
	if state == nil then state = not c.shown end
	c.shown = state and true or false
	if state then
		applyPoint(); applyLook()
		win:Show()
		WIN.Refresh()
	else
		win:Hide()
	end
end

-- Is the window turned ON -- not "is the frame currently painted". The header
-- button's label asks this question, and out of the boss's room the two answers
-- differ.
function WIN.IsShown() return cfg().shown and true or false end

-- Is the frame actually on screen right now?
function WIN.IsVisible() return win and win:IsShown() or false end

-- ------------------------------------------------------------
-- Visibility follows the room -- on zone changes only.
--
-- Walking into a boss's room brings the note up by itself, and walking out
-- puts it away. What it must never do is undo the button: you open the window
-- in Dalaran to read a note, and the next zone event would have closed it with
-- no explanation. The button owns `shown`; this only reacts to moving.
-- ------------------------------------------------------------
function WIN.ApplyVisibility()
	if not win then return end
	-- Module off: the fight window is part of Notes, so it goes away with it.
	if Okanvil.ModuleActive and not Okanvil:ModuleActive("Okanvil-Notes") then
		if win:IsShown() then win:Hide() end
		return
	end
	local c = cfg()
	if not c.shown then
		if win:IsShown() then win:Hide() end
		return
	end
	if c.onlyInRoom == false or not N.InNoteRoom then
		if not win:IsShown() then win:Show(); WIN.Refresh() end
		return
	end
	if N.InNoteRoom() and not win:IsShown() then
		win:Show()
		WIN.Refresh()
	end
end

-- Leaving a boss's room puts the window away again -- but only on an actual
-- move. Hiding lives here rather than in ApplyVisibility so that opening the
-- window by hand, anywhere, stays open until you close it.
local lastRoom
local function onZone()
	local room = N.InNoteRoom and N.InNoteRoom() or false
	local left = (lastRoom == true and room == false)
	lastRoom = room
	if left and win and win:IsShown() and cfg().onlyInRoom ~= false then
		win:Hide()
		return
	end
	WIN.ApplyVisibility()
end

local zone = CreateFrame("Frame")
zone:RegisterEvent("ZONE_CHANGED")
zone:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zone:RegisterEvent("ZONE_CHANGED_INDOORS")
zone:RegisterEvent("PLAYER_ENTERING_WORLD")
zone:SetScript("OnEvent", onZone)

-- ------------------------------------------------------------
-- What the Fight window settings pill drives.
-- ------------------------------------------------------------
function WIN.IsLocked() return cfg().locked ~= false end

function WIN.SetLocked(state)
	cfg().locked = state and true or false
	applyLook()
end

function WIN.GetAlpha() return math.floor((cfg().alpha or 0.85) * 100) end
function WIN.SetAlpha(pct)
	cfg().alpha = (pct or 85) / 100
	applyLook()
end

function WIN.OnlyInRoom() return cfg().onlyInRoom ~= false end
function WIN.SetOnlyInRoom(state)
	cfg().onlyInRoom = state and true or false
	WIN.ApplyVisibility()
end

function WIN.GetSize() return cfg().size or 13 end
function WIN.SetSize(px)
	cfg().size = px or 13
	applyLook()
end

-- Dragged off-screen, or onto a monitor you no longer have: put it back in the
-- middle. No button calls this -- SetClampedToScreen already stops the window
-- leaving the screen -- but it is the recovery if that ever fails.
function WIN.ResetPosition()
	cfg().point = nil
	applyPoint()
	savePoint()
end

-- Restore on login if it was open when you logged out.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
	if db() and cfg().shown then WIN.Toggle(true) end
end)
