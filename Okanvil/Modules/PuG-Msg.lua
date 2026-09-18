-- ============================================================
-- Okanvil -- PuG Messages.
-- A second window that docks to the RIGHT of the PuG page: the people who
-- whispered you down the left, the conversation with the selected one on the
-- right, and Invite / Read specs above it.
--
-- Why a separate window rather than another tab: while you are forming a raid
-- you are reading a whisper and looking at the board at the same time. A tab
-- would make those two things take turns.
-- ============================================================

local Okanvil = Okanvil
local M = Okanvil.PuG
local W = Okanvil.W
local C = Okanvil.Colors
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

local WIN_W, WIN_H = 440, 520
local LIST_W = 140          -- the conversation list down the left
local ROW_H = 38            -- two lines: name, then spec + gs

local win                   -- built lazily on first open
local selected              -- whose conversation is open

local function db() return M.DB() end

local function classColor(token)
	local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	if c then return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
	return "|cffdcddde"
end

-- "5m" / "2h" -- how long ago they last said something. A pug applicant goes
-- stale fast, so the age is the second thing you look at after the name.
local function ago(t)
	if not t then return "" end
	local s = time() - t
	if s < 60 then return "now" end
	if s < 3600 then return math.floor(s / 60) .. "m" end
	if s < 86400 then return math.floor(s / 3600) .. "h" end
	return math.floor(s / 86400) .. "d"
end

-- The one-line summary under a name: "combat rogue 5.2k", with whatever parts
-- the whisper actually gave us. An applicant who only said "inv" has neither,
-- and the line is left empty rather than padded with "unknown".
local function subLine(a)
	local bits = {}
	if a.spec then bits[#bits + 1] = a.spec end
	if a.gs then bits[#bits + 1] = a.gs end
	return table.concat(bits, "  ")
end

-- ------------------------------------------------------------
-- Conversation list (left)
-- ------------------------------------------------------------
local function listRow(i)
	local r = win.rows[i]
	if r then return r end
	r = W.Frame(win.listChild, "bare")
	r:SetHeight(ROW_H)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 2))
	r:SetPoint("TOPRIGHT", 0, -(i - 1) * (ROW_H + 2))

	r.sel = r:CreateTexture(nil, "BACKGROUND")
	r.sel:SetAllPoints(); r.sel:SetTexture(FLAT)
	r.sel:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.16)
	r.sel:Hide()

	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(); hl:SetTexture(FLAT)
	hl:SetVertexColor(1, 1, 1, 0.05)

	r.name = W.Text(r, "", "label"); r.name:SetPoint("TOPLEFT", 6, -5)
	r.age  = W.Text(r, "", "note", "dim"); r.age:SetPoint("TOPRIGHT", -6, -5)
	r.sub  = W.Text(r, "", "note", "dim")
	r.sub:SetPoint("TOPLEFT", 6, -20); r.sub:SetPoint("RIGHT", -6, 0)
	r.sub:SetJustifyH("LEFT")
	if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end

	r:EnableMouse(true)
	r:SetScript("OnMouseUp", function(self)
		if self._name then
			selected = self._name
			M.MarkRead(selected)
			M.Msg_Refresh()
		end
	end)
	win.rows[i] = r
	return r
end

-- ------------------------------------------------------------
-- Build
-- ------------------------------------------------------------
local function build()
	if win then return win end
	local f = Okanvil:Popup("Messages")
	f:SetSize(WIN_W, WIN_H)
	f.rows = {}

	-- ---- left: the conversation list ----
	local lcard = W.Frame(f, "dark")
	lcard:SetPoint("TOPLEFT", 6, -30)
	lcard:SetPoint("BOTTOMLEFT", 6, 6)
	lcard:SetWidth(LIST_W)

	local lsf = CreateFrame("ScrollFrame", nil, lcard)
	lsf:SetPoint("TOPLEFT", 3, -3); lsf:SetPoint("BOTTOMRIGHT", -9, 3)
	local lchild = CreateFrame("Frame", nil, lsf); lchild:SetSize(10, 1)
	lsf:SetScrollChild(lchild)
	local lsb = CreateFrame("Slider", nil, lcard)
	lsb:SetPoint("TOPRIGHT", -3, -3); lsb:SetPoint("BOTTOMRIGHT", -3, 3); lsb:SetWidth(4)
	lsb:SetOrientation("VERTICAL"); lsb:SetValueStep(1)
	local lth = lsb:CreateTexture(nil, "OVERLAY"); lth:SetTexture(FLAT)
	lth:SetSize(4, 30); lth:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
	lsb:SetThumbTexture(lth)
	lsb:SetScript("OnValueChanged", function(_, v) lsf:SetVerticalScroll(v) end)
	lsf:EnableMouseWheel(true)
	lsf:SetScript("OnMouseWheel", function(_, d) lsb:SetValue(lsb:GetValue() - d * 30) end)
	lsf:SetScript("OnSizeChanged", function() lchild:SetWidth(lsf:GetWidth()) end)
	f.listChild, f.listSB, f.listSF = lchild, lsb, lsf

	f.listEmpty = W.Text(lcard, "", "note", "dim")
	f.listEmpty:SetPoint("TOPLEFT", 8, -8); f.listEmpty:SetPoint("RIGHT", -8, 0)
	f.listEmpty:SetJustifyH("LEFT")

	-- ---- right: who, the actions, the conversation, the reply box ----
	local RX = 6 + LIST_W + 6
	f.who = W.Text(f, "", "head", "accent")
	f.who:SetPoint("TOPLEFT", RX, -34)

	f.invBtn = W.Button(f, "Invite", "primary")
	f.invBtn:SetSize(66, 22); f.invBtn:SetPoint("TOPRIGHT", -8, -30)
	f.invBtn:SetScript("OnClick", function()
		if not selected then return end
		M.InviteApplicant(selected)
		M.Msg_Refresh()
	end)

	f.scanBtn = W.Button(f, "Read spec")
	f.scanBtn:SetSize(74, 22); f.scanBtn:SetPoint("RIGHT", f.invBtn, "LEFT", -5, 0)
	f.scanBtn:SetScript("OnClick", function()
		if not selected then return end
		local I = Okanvil.Inspect
		if not (I and I.ScanOne) then
			Okanvil:Print("|cffff5555Inspect module not loaded.|r")
			return
		end
		I.ScanOne(selected, function() M.Msg_Refresh() end)
	end)
	f.scanBtn:Tooltip("Read this player's real spec and gear.\nOnly works while they are in range.")

	-- the conversation itself
	local ccard = W.Frame(f, "dark")
	ccard:SetPoint("TOPLEFT", RX, -58)
	ccard:SetPoint("BOTTOMRIGHT", -6, 36)

	local csf = CreateFrame("ScrollFrame", nil, ccard)
	csf:SetPoint("TOPLEFT", 4, -4); csf:SetPoint("BOTTOMRIGHT", -10, 4)
	local cchild = CreateFrame("Frame", nil, csf); cchild:SetSize(10, 1)
	csf:SetScrollChild(cchild)
	local csb = CreateFrame("Slider", nil, ccard)
	csb:SetPoint("TOPRIGHT", -3, -4); csb:SetPoint("BOTTOMRIGHT", -3, 4); csb:SetWidth(4)
	csb:SetOrientation("VERTICAL"); csb:SetValueStep(1)
	local cth = csb:CreateTexture(nil, "OVERLAY"); cth:SetTexture(FLAT)
	cth:SetSize(4, 30); cth:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
	csb:SetThumbTexture(cth)
	csb:SetScript("OnValueChanged", function(_, v) csf:SetVerticalScroll(v) end)
	csf:EnableMouseWheel(true)
	csf:SetScript("OnMouseWheel", function(_, d) csb:SetValue(csb:GetValue() - d * 30) end)
	csf:SetScript("OnSizeChanged", function() cchild:SetWidth(csf:GetWidth()) end)

	-- ONE font string, not a row per line: a conversation is a block of text, and
	-- 30 pooled frames to draw it would be 30 frames to keep in step.
	f.convo = W.Text(cchild, "", "label")
	f.convo:SetPoint("TOPLEFT", 6, -4)
	f.convo:SetPoint("TOPRIGHT", -6, -4)
	f.convo:SetJustifyH("LEFT")
	f.convoSF, f.convoSB, f.convoChild = csf, csb, cchild

	-- With nobody to show, every control on the right is hidden -- so without this
	-- the window is two empty rectangles that explain nothing. Say what has to
	-- happen for anything to appear here.
	f.empty = W.Text(ccard, "", "label", "dim")
	f.empty:SetPoint("TOPLEFT", 14, -14)
	f.empty:SetPoint("RIGHT", -14, 0)
	f.empty:SetJustifyH("LEFT")

	-- reply box
	f.reply = W.EditBox(f, function(txt)
		if not (selected and txt and txt ~= "") then return end
		M.Whisper(selected, txt)
		f.reply.edit:SetText("")
		M.Msg_Refresh()
	end)
	f.reply:SetHeight(24)
	f.reply:SetPoint("BOTTOMLEFT", RX, 6)
	f.reply:SetPoint("BOTTOMRIGHT", -66, 6)

	f.sendBtn = W.Button(f, "Send")
	f.sendBtn:SetSize(54, 24); f.sendBtn:SetPoint("BOTTOMRIGHT", -6, 6)
	f.sendBtn:SetScript("OnClick", function()
		local txt = f.reply.edit:GetText() or ""
		if selected and txt ~= "" then
			M.Whisper(selected, txt)
			f.reply.edit:SetText("")
			M.Msg_Refresh()
		end
	end)

	win = f
	return f
end

-- ------------------------------------------------------------
-- Paint
-- ------------------------------------------------------------
function M.Msg_Refresh()
	if not (win and win:IsShown()) then return end
	local list = M.ApplicantList()

	-- Nobody selected yet (or the selected one was invited away): open the newest,
	-- so the window is never showing an empty right half while names sit on the left.
	if selected then
		local still = false
		for _, a in ipairs(list) do if a.name == selected then still = true; break end end
		if not still then selected = nil end
	end
	if not selected and list[1] then selected = list[1].name; M.MarkRead(selected) end

	for _, r in ipairs(win.rows) do r:Hide() end
	for i, a in ipairs(list) do
		local r = listRow(i)
		r._name = a.name
		r.name:SetText(classColor(a.class) .. a.name .. "|r"
			.. ((a.unread or 0) > 0 and " |cffe0b860*|r" or ""))
		r.age:SetText(ago(a.t))
		r.sub:SetText("|cff8a8d93" .. subLine(a) .. "|r")
		r.sel:SetShown(a.name == selected)
		r:Show()
	end
	local h = math.max(1, #list * (ROW_H + 2))
	win.listChild:SetHeight(h)
	local maxs = math.max(0, h - win.listSF:GetHeight())
	win.listSB:SetMinMaxValues(0, maxs); win.listSB:SetShown(maxs > 4)
	win.listEmpty:SetText(#list == 0
		and "|cff6f7176Nobody has whispered yet.|r" or "")

	-- right half
	local a
	for _, x in ipairs(list) do if x.name == selected then a = x; break end end
	win.who:SetText(a and (classColor(a.class) .. a.name .. "|r"
		.. (subLine(a) ~= "" and ("  |cff8a8d93" .. subLine(a) .. "|r") or "")) or "")
	win.invBtn:SetShown(a ~= nil)
	win.scanBtn:SetShown(a ~= nil)
	win.reply:SetShown(a ~= nil)
	win.sendBtn:SetShown(a ~= nil)
	if a then
		win.empty:SetText("")
	elseif not M.IsActive() then
		win.empty:SetText("|cff8a8d93Whispers land here while you are spamming.|r\n\n"
			.. "|cff6f7176Press |r|cffe0b860START spamming|r|cff6f7176 and anyone who "
			.. "whispers you appears in this list, with the spec and gearscore read "
			.. "out of what they wrote.|r")
	else
		win.empty:SetText("|cff8a8d93Spamming -- waiting for whispers.|r\n\n"
			.. "|cff6f7176Whoever answers the LFM shows up here. Click a name to read "
			.. "the conversation, reply, and invite them.|r")
	end

	local lines = {}
	for _, e in ipairs((a and a.log) or {}) do
		local who = e.them and (classColor(a.class) .. a.name .. "|r") or "|cffe0b860you|r"
		lines[#lines + 1] = who .. ": |cffdcddde" .. e.msg .. "|r"
	end
	win.convo:SetText(table.concat(lines, "\n"))
	-- GetStringHeight is only valid once laid out, so the child is sized on the
	-- next frame rather than from a value that is still 0 here.
	local ch = win.convoChild
	ch:SetHeight(math.max(1, (win.convo:GetStringHeight() or 0) + 10))
	local cmax = math.max(0, ch:GetHeight() - win.convoSF:GetHeight())
	win.convoSB:SetMinMaxValues(0, cmax); win.convoSB:SetShown(cmax > 4)
	win.convoSB:SetValue(cmax)        -- newest message in view
end

-- ------------------------------------------------------------
-- Open / close. The window docks to the RIGHT of the main Okanvil window, so
-- the board and the whisper are readable at the same time -- which is the whole
-- reason this is not a tab.
-- ------------------------------------------------------------
function M.Msg_Toggle()
	build()
	if win:IsShown() then win:Hide(); return end
	win:ClearAllPoints()
	if Okanvil.win and Okanvil.win:IsShown() then
		win:SetPoint("TOPLEFT", Okanvil.win, "TOPRIGHT", 6, 0)
	else
		win:SetPoint("CENTER", UIParent, "CENTER", 220, 0)
	end
	win:Show()
	-- It is an extension of the main window, not a window of its own: closing
	-- Okanvil (X, ESC, the DBM-pull hide) has to take this with it, or a panel is
	-- left floating over the game with nothing to close it from.
	if Okanvil.win and not win._hookedHost then
		win._hookedHost = true
		Okanvil.win:HookScript("OnHide", function() if win then win:Hide() end end)
	end
	M.Msg_Refresh()
end

function M.Msg_IsShown() return win and win:IsShown() end

-- Open the window ON a given person -- what clicking an applicant on the board
-- does. Opening it on whoever happened to be newest would make the click feel
-- like it went to the wrong row.
function M.Msg_Open(name)
	if not name then return end
	if not (win and win:IsShown()) then M.Msg_Toggle() end
	selected = name
	M.MarkRead(name)
	M.Msg_Refresh()
end

-- How many people are waiting on a reply -- the number on the button that opens
-- this window.
function M.UnreadCount()
	local n = 0
	for _, a in pairs((db() or {}).applicants or {}) do
		if (a.unread or 0) > 0 then n = n + 1 end
	end
	return n
end

-- A whisper landing while the window is open should appear in it, and the button
-- that opens it has to recount either way.
M.onApplicant = function()
	if M.Msg_Refresh then M.Msg_Refresh() end
	if M.RefreshMsgBtn then M.RefreshMsgBtn() end
end
