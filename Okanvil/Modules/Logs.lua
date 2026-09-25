-- ============================================================
--   ██████╗ ██╗  ██╗ █████╗ ███╗   ██╗██╗   ██╗██╗██╗
--  ██╔═══██╗██║ ██╔╝██╔══██╗████╗  ██║██║   ██║██║██║
--  ██║   ██║█████╔╝ ███████║██╔██╗ ██║██║   ██║██║██║
--  ██║   ██║██╔═██╗ ██╔══██║██║╚██╗██║╚██╗ ██╔╝██║██║
--  ╚██████╔╝██║  ██╗██║  ██║██║ ╚████║ ╚████╔╝ ██║███████╗
--   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚══════╝
--  Okanvil-Logs -- combat-log control + a movable/lockable REC timer
--  + session tracker. A native Okanvil module (no standalone).
--  (Addons can't read/write files, so SLICING + EXPORT live in the
--   desktop tool; this records start/stop/zone as a reference.)
-- ============================================================

local ADDON = "Okanvil-Logs"
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

local defaults = {
	-- Never prompt on entering a raid. Logging starts by itself at the first pull
	-- and the REC timer says when it is running, so the question only ever had one
	-- answer. (Kept as a field, not deleted: old saved variables still carry it.)
	askOnEnter = false,
	autoLog = false, -- legacy: silently auto-log on raid entry (used only if askOnEnter is off)
	autoOnPull = true, -- start logging at the first raid pull (Settings > Raid)
	recLocked = false, -- lock the REC timer (click-through, no drag)
	rec = { point = "TOP", x = 0, y = -140 },
	sessions = {}, -- persisted history of logging sessions (zone, start, stop, bosses)
}
local db
local rec, toastF, askLogF -- floating frames (live on UIParent, not in the host window)
local askedZone -- last instance we already prompted for (avoid re-asking on repeat PLAYER_ENTERING_WORLD)
OkanvilLogs = OkanvilLogs or {} -- tiny namespace for slash / boot

-- ------------------------------------------------------------
-- helpers -- thin wrappers over the shared Okanvil widget layer. The host is
-- always loaded (this is a native module), so no local fallbacks. These are only
-- used for the floating frames (REC timer, toast, ask-prompt); the in-window UI
-- uses Okanvil.W.* directly.
-- ------------------------------------------------------------
local function flat(f, a, dark) Okanvil:Backdrop(f, a, dark) end

local function newText(parent, layer, size)
	local fs = Okanvil:NewText(parent, layer)
	if size then fs._okSize = size; fs:SetFont(Okanvil:Font(), size) end
	return fs
end

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffe0b860[Okanvil-Logs]|r " .. tostring(msg))
end

local function fmtTime(s)
	s = math.floor(s or 0)
	if s >= 3600 then
		return string.format("%d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
	end
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- shared gold RATS-Hub button (host always present)
local function flatButton(parent, text, w, h, kind)
	local b = Okanvil.W.Button(parent, text, kind)
	b:SetSize(w, h)
	return b
end

-- A full-width settings card: title (+ optional sub) on the left, an ON/OFF pill
-- right-aligned INSIDE the card. Nothing can overlap regardless of label width.
local function cardToggle(parent, title, sub, getFn, setFn)
	local card = Okanvil.W.Frame(parent, "soft")
	card:SetHeight(sub and 42 or 30)

	local t = newText(card, "OVERLAY")
	t:SetPoint("LEFT", 12, sub and 8 or 0)
	t:SetText(title)

	if sub then
		local s = newText(card, "OVERLAY", 10)
		s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
		s:SetText("|cff8a8d93" .. sub .. "|r")
	end

	local b = flatButton(card, "", 48, 20)
	b:SetPoint("RIGHT", -10, 0)
	local function paint()
		b.text:SetText(getFn() and "|cff7cfc8aON|r" or "|cff8a8d93OFF|r")
	end
	paint()
	b:SetScript("OnClick", function() setFn(not getFn()); paint() end)
	card.pill, card._paint = b, paint
	return card
end

-- ------------------------------------------------------------
-- logging state + sessions
-- ------------------------------------------------------------
local function isLogging()
	return LoggingCombat()
end

-- We keep a small history of logging sessions (zone, times, bosses killed) so the
-- Combat Logs page is a real log, not just a live toggle. The desktop tool still
-- does the actual WoWCombatLog.txt slicing; this is the in-game reference index.
local MAX_LOG_SESSIONS = 30
-- How long a session may sit untouched and still be treated as the same raid on
-- the next login. Long enough to cover a reload, a zone-in or a disconnect and
-- reconnect; short enough that logging off for the night never resumes.
local STALE_AFTER = 30 * 60
-- A session closed on login that reopens this soon after, in the same zone, is the
-- same raid coming back from a /reload -- not a new one. Comfortably over the
-- worst reload (the client reloads the whole UI and reconnects), well under the
-- break where a raid really does end.
local REOPEN_WITHIN = 10 * 60
-- Standing back inside the same raid keeps a session alive past STALE_AFTER, but
-- only this far: a long break is still one raid night, sleeping in the instance is
-- not. Covers the worst DBM break plus wipes; well short of logging back in the
-- next day.
local SAME_RAID_GRACE = 90 * 60
local function beginSession()
	local zone = GetRealZoneText()
	if not zone or zone == "" then zone = GetZoneText() end
	zone = zone or ""

	-- Same raid, coming back? A reload mid-raid can still close the session (the
	-- watchdog fires before we ever get to say the raid is alive), and starting a
	-- fresh one there splits one night into two -- two entries in the history, and
	-- two separate uploads at the log site. Reopening keeps the night whole.
	local last = db.sessions and db.sessions[1]
	if last and last.stop and last.zone == zone and zone ~= ""
		and (time() - last.stop) <= REOPEN_WITHIN then
		local gap = time() - last.stop
		table.remove(db.sessions, 1)
		last.stop = nil
		last.seen = time()
		-- the gap belongs to the raid now: the client log missed it, but the session
		-- did not end there, and `note` is what says so when reading the history back
		last.note = ("reopened after a %d min break (client log has a gap here)"):format(math.floor(gap / 60))
		last.bosses = last.bosses or {}
		db._cur = last
		db._lastBosses = nil   -- those kills are the LIVE session's again, not a finished one's
		return
	end

	db._cur = { start = time(), zone = zone, bosses = {} }
end

-- Heartbeat: the last moment we KNOW the session was live. Logout fires no event
-- we can rely on (a crash fires none at all), so the next login reads this to tell
-- a quick /reload from an overnight gap.
--
-- This used to live in the REC frame's OnUpdate, which meant it only ticked while
-- REC was SHOWN -- hide the timer and the session's clock froze, so the next
-- reload read a stale `seen`, called a live raid an overnight absence and split it
-- in two. It ticks on its own frame now, tied to the session and nothing else.
local beat = CreateFrame("Frame")
beat:SetScript("OnUpdate", function(s, e)
	s._t = (s._t or 0) + e
	if s._t < 1 then return end
	s._t = 0
	if db and db._cur then db._cur.seen = time() end
end)

-- stopAt: when the session actually ended. Normally now, but a session closed on
-- login ended whenever we last saw it -- stamping it "now" would write the hours
-- spent logged off into the history as raid time.
local function endSession(stopAt)
	if db._cur then
		db._cur.stop = stopAt or time()
		db._cur.recentDeaths = nil          -- transient, don't persist
		db._lastBosses = db._cur.bosses     -- keep last session's kills visible after Stop
		-- persist into the history list (newest first)
		db.sessions = db.sessions or {}
		table.insert(db.sessions, 1, db._cur)
		while #db.sessions > MAX_LOG_SESSIONS do table.remove(db.sessions) end
	end
	db._cur = nil
	if OkanvilLogs.Refresh then OkanvilLogs.Refresh() end
end

function OkanvilLogs.DeleteSession(sess)
	if not db or not db.sessions then return end
	for i = #db.sessions, 1, -1 do
		if db.sessions[i] == sess then table.remove(db.sessions, i); break end
	end
	if OkanvilLogs.Refresh then OkanvilLogs.Refresh() end
end

-- ------------------------------------------------------------
-- transient toast (start/stop)
-- ------------------------------------------------------------
local function toast(msg, color)
	PlaySound("UI_BnetToast")
	if not toastF then
		toastF = CreateFrame("Frame", nil, UIParent)
		toastF:SetSize(230, 30)
		toastF:SetPoint("TOP", 0, -100)
		toastF:SetFrameStrata("FULLSCREEN_DIALOG")
		flat(toastF, 0.96, true)
		toastF.txt = newText(toastF, "OVERLAY")
		toastF.txt:SetPoint("CENTER")
		toastF:SetScript("OnUpdate", function(s, e)
			s._life = (s._life or 0) - e
			if s._life <= 0 then
				s:Hide()
			elseif s._life < 1 then
				s:SetAlpha(s._life)
			end
		end)
	end
	toastF.txt:SetText("|cff" .. (color or "ffffff") .. msg .. "|r")
	toastF:SetAlpha(1)
	toastF._life = 3
	toastF:Show()
end

-- ------------------------------------------------------------
-- boss recognition -- record which bosses died during a session
-- (no encounter API in 3.3.5a: we match UNIT_DIED by creatureID, name as fallback)
-- ------------------------------------------------------------
-- Both tables are DERIVED from the shared list in
-- Modules/Bosses-Data.lua (loaded first via the .toc), so Logs and Loot agree on what
-- a boss is and there is one place to add one.
--
local BOSS_IDS = {}   -- [creatureID] = true
local BOSSES   = {}   -- [name]       = true  (fallback when the GUID gives no id)
do
	local src = OkanvilBosses or {}
	for cid, name in pairs(src) do
		BOSS_IDS[cid] = true
		if name and name ~= "" then BOSSES[name] = true end
	end
end

-- 3.3.5a: pull the creature entry id out of a unit GUID ("0x" + 4 type nibbles + 4 id nibbles)
local function npcID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local id = guid:match("^0x%x%x%x%x(%x%x%x%x)")
	return id and tonumber(id, 16) or nil
end

-- Multi-NPC encounters: collapse their members into one line (by id or name).
-- Shared with Loot.lua via Modules/Bosses-Data.lua.
local GROUP = OkanvilBossGroups or {}

-- add a boss to the current session (deduped). Shared by the combat-log death
-- path and the loot-confirmation path.
local function addBoss(label, id)
	local cur = db and db._cur
	if not cur or not label or label == "" then return end
	cur.bosses = cur.bosses or {}
	for i = 1, #cur.bosses do
		if cur.bosses[i].name == label then return end -- already logged this session
	end
	cur.bosses[#cur.bosses + 1] = { name = label, id = id, at = time() - cur.start }
	toast("Boss logged: " .. label, "00ddff")
	if OkanvilLogs.Refresh then OkanvilLogs.Refresh() end
end

local function recordBoss(guid, name)
	local id = npcID(guid)
	local known = (id and BOSS_IDS[id]) or (name and BOSSES[name])
	-- Dungeon bosses aren't in the raid list -- but if the Loot module already
	-- recorded a drop from this name, it's a real boss (loot-confirmed). Also
	-- remember recent NPC deaths so a kill can be promoted when its loot arrives.
	if not known then
		if Okanvil.Loot and Okanvil.Loot.SessionHasBoss and Okanvil.Loot.SessionHasBoss(name) then
			known = true
		else
			-- stash as a candidate; loot arriving later promotes it (NoteBossFromLoot)
			if name and name ~= "" and db and db._cur then
				db._cur.recentDeaths = db._cur.recentDeaths or {}
				db._cur.recentDeaths[name] = time() - db._cur.start
			end
			return
		end
	end
	-- The id is authoritative; only match by NAME when there is no id. Names repeat
	-- across instances (Utgarde Keep's Prince Keleseth, Ahn'kahet's Prince Taldaram),
	-- so a name lookup would file those dungeon kills as "Blood Prince Council".
	local label
	if id then label = GROUP[id] or ((name and name ~= "") and name)
	else label = (name and GROUP[name]) or ((name and name ~= "") and name) end
	label = label or ("NPC " .. tostring(id))
	addBoss(label, id)
end

-- Called by the Loot module when it records a drop from `bossName`. If we saw
-- that NPC die this session (recentDeaths), promote it to a logged boss -- this
-- is how dungeon bosses get named without a hardcoded 5-man list.
function OkanvilLogs.NoteBossFromLoot(bossName)
	if not bossName or bossName == "" then return end
	local cur = db and db._cur
	if not cur then return end
	if cur.recentDeaths and cur.recentDeaths[bossName] then
		addBoss(bossName)
	end
end

-- ------------------------------------------------------------
-- "Log this instance?" prompt (shown once on entering an instance)
-- ------------------------------------------------------------
local function askToLog(zone)
	if not askLogF then
		askLogF = CreateFrame("Frame", nil, UIParent)
		askLogF:SetSize(280, 76)
		askLogF:SetPoint("TOP", 0, -120)
		askLogF:SetFrameStrata("FULLSCREEN_DIALOG")
		flat(askLogF, 0.97, true)
		askLogF.txt = newText(askLogF, "OVERLAY")
		askLogF.txt:SetPoint("TOP", 0, -12)
		local yes = flatButton(askLogF, "Start log", 116, 24, "primary")
		yes:SetPoint("BOTTOMLEFT", 12, 12)
		yes:SetScript("OnClick", function()
			askLogF:Hide()
			OkanvilLogs.SetLogging(true)
		end)
		local no = flatButton(askLogF, "|cffff5555No|r", 116, 24)
		no:SetPoint("BOTTOMRIGHT", -12, 12)
		no:SetScript("OnClick", function()
			askLogF:Hide()
			-- No means this raid, pulls included: without this the first pull's
			-- safety net started the log you had just declined.
			OkanvilLogs._suppressAuto = true
		end)
	end
	askLogF.txt:SetText("Log this instance?\n|cffaaaaaa" .. (zone or "") .. "|r")
	PlaySound("UI_BnetToast")
	askLogF:Show()
end

-- ------------------------------------------------------------
-- REC timer (persistent while logging; movable + lockable)
-- ------------------------------------------------------------
local function applyRecLock()
	if not rec then
		return
	end
	rec:EnableMouse(not db.recLocked) -- locked = click-through (no accidental drags mid-fight)
end

local function buildRec()
	if rec then
		return
	end
	local r = CreateFrame("Frame", "OkanvilLogs_Rec", UIParent)
	r:SetSize(160, 26)
	r:SetPoint(db.rec.point, UIParent, db.rec.point, db.rec.x, db.rec.y)
	r:SetFrameStrata("HIGH")
	flat(r, 0.9, true)
	r:SetMovable(true)
	r:RegisterForDrag("LeftButton")
	r:SetScript("OnDragStart", function(s)
		if not db.recLocked then
			s:StartMoving()
		end
	end)
	r:SetScript("OnDragStop", function(s)
		s:StopMovingOrSizing()
		local p, _, _, x, y = s:GetPoint(1)
		db.rec.point, db.rec.x, db.rec.y = p, x, y
	end)
	local dot = newText(r, "OVERLAY")
	dot:SetPoint("LEFT", 9, 0)
	dot:SetText("|cffff3333REC|r")
	r.label = newText(r, "OVERLAY")
	r.label:SetPoint("LEFT", dot, "RIGHT", 6, 0)
	r.label:SetText("0:00")
	-- Stop button: always clickable (even when locked/click-through) to end the session
	local stop = flatButton(r, "|cffff5555Stop|r", 42, 18)
	stop:SetPoint("RIGHT", -4, 0)
	stop:SetScript("OnClick", function()
		OkanvilLogs.SetLogging(false)
	end)
	r:SetScript("OnUpdate", function(s, e)
		s._t = (s._t or 0) + e
		if s._t < 0.5 then
			return
		end
		s._t = 0
		if db._cur then
			-- (the session heartbeat runs on its own frame -- see `beat` above, so it
			-- keeps ticking even while this REC timer is hidden)
			s.label:SetText(fmtTime(time() - db._cur.start))
			-- live-tick the panel's status sub-line if the page is open
			local pn = OkanvilLogs.panel
			if pn and pn._stSub and pn:IsVisible() then
				local nb = db._cur.bosses and #db._cur.bosses or 0
				pn._stSub:SetText("|cff8a8d93" .. fmtTime(time() - db._cur.start) .. "  |  " .. nb .. " boss" .. (nb == 1 and "" or "es") .. " logged|r")
			end
			-- WATCHDOG: a session is open, but is the client log ACTUALLY on? A zone change,
			-- death or ghost re-enter can silently switch LoggingCombat off while the timer
			-- keeps ticking. Detect that, self-heal, and make it visible.
			if not LoggingCombat() then
				LoggingCombat(true)
				dot:SetText("|cffffaa00REC!|r") -- amber = it had dropped and was re-armed
				if not s._dropped then
					s._dropped = true
					toast("Logging had DROPPED -- re-armed!", "ffaa00")
				end
			else
				dot:SetText("|cffff3333REC|r")
				s._dropped = false
			end
		end
		dot:SetAlpha((math.floor(GetTime() * 1.5) % 2 == 0) and 1 or 0.35) -- blink
	end)
	r:Hide()
	rec = r
	applyRecLock()
end

-- ------------------------------------------------------------
-- start / stop
-- ------------------------------------------------------------
-- Public reader: the marks bar needs to know whether we are recording so its
-- REC button can show the state, and isLogging() is a local.
function OkanvilLogs.IsLogging() return isLogging() end

-- Settings owns the two toggles now, and the lock one has to re-apply itself.
function OkanvilLogs.ApplyRecLock() applyRecLock() end
function OkanvilLogs.DB() return db end

function OkanvilLogs.SetLogging(on)
	buildRec()
	if on then
		if not LoggingCombat() then
			LoggingCombat(true)
		end
		if not db._cur then
			beginSession()
		end
		OkanvilLogs._suppressAuto = nil -- explicit start -> auto-log allowed
		rec:Show()
		toast("REC -- combat log STARTED", "00ff00")
	else
		if LoggingCombat() then
			LoggingCombat(false)
		end
		endSession()
		OkanvilLogs._suppressAuto = true -- explicit stop -> don't auto-restart until you leave the raid
		rec:Hide()
		toast("STOP -- combat log saved", "ff5555")
	end
	if OkanvilLogs.Refresh then
		OkanvilLogs.Refresh()
	end
end

-- ------------------------------------------------------------
-- UI panel -- a native Okanvil module page (Dashboard shell)
-- ------------------------------------------------------------
function OkanvilLogs.BuildUI(host)
	local X = 16
	local W = Okanvil.W

	-- Dashboard shell (MRT/Recruit-style gold header). The logger's own layout
	-- (big Start/Stop, status card, settings, history) draws into dash.main; the
	-- header carries the title + a REC status readout.
	local dash = W.Dashboard(host, {
		title = "Combat Logs",
		subtitle = "Logs every raid from the first pull",
		icon = Okanvil.ICONS and Okanvil.ICONS.logs or "Interface\\Icons\\INV_Scroll_03",
		drawerWidth = 0,
		footerHeight = 0,
		statusText = function()
			if isLogging() then return "|cffff5555REC|r |cff8a8d93logging|r" end
			return "|cff8a8d93idle|r"
		end,
	})
	local parent = dash.main
	OkanvilLogs._dash = dash
	OkanvilLogs.panel = parent   -- RebuildHistory/Refresh read _hist* off this frame

	-- ---- Row 1: big Start/Stop CTA (left) + live status card (right) ----
	local toggle = flatButton(parent, "", 190, 46, "primary")
	toggle:SetPoint("TOPLEFT", X, -16)
	toggle:SetScript("OnClick", function()
		OkanvilLogs.SetLogging(not isLogging())
	end)
	parent._toggle = toggle

	-- status card: shows REC state + elapsed while a session is open
	local status = W.Frame(parent, "soft")
	status:SetPoint("TOPLEFT", toggle, "TOPRIGHT", 10, 0)
	status:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
	status:SetHeight(46)
	local stTop = newText(status, "OVERLAY")
	stTop:SetPoint("TOPLEFT", 12, -8)
	local stSub = newText(status, "OVERLAY", 10)
	stSub:SetPoint("BOTTOMLEFT", 12, 8)
	parent._stTop, parent._stSub = stTop, stSub

	-- ---- Row 2/3: settings cards (label left, pill right -- no clipping) ----
	local c1 = cardToggle(parent, "Ask to log when entering a raid",
		"Pops a Start log / No prompt on the first raid zone-in. Dungeons never prompt.",
		function() return db.askOnEnter end,
		function(v) db.askOnEnter = v end)
	c1:SetPoint("TOPLEFT", X, -74)
	c1:SetPoint("RIGHT", parent, "RIGHT", -14, 0)

	local c2 = cardToggle(parent, "Lock REC timer (click-through)",
		"Stops accidental drags mid-fight. Stop still works.",
		function() return db.recLocked end,
		function(v) db.recLocked = v; applyRecLock() end)
	c2:SetPoint("TOPLEFT", X, -122)
	c2:SetPoint("RIGHT", parent, "RIGHT", -14, 0)

	local hint = newText(parent, "OVERLAY", 11)
	hint:SetPoint("TOPLEFT", X, -172)
	hint:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText(
		"|cff6f7176Logging writes to WoWCombatLog.txt -- slice/export it with the desktop tool. Bosses that drop loot are named automatically.|r"
	)

	-- ---- live "this session" boss list (only while a session is open) ----
	-- Its header+list live in a container we can hide/collapse; PAST SESSIONS
	-- and the scroll re-anchor under it so there is no dead space when idle.
	local live = CreateFrame("Frame", nil, parent)
	live:SetPoint("TOPLEFT", X, -200)
	live:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
	live:SetHeight(20)
	local blbl = newText(live, "OVERLAY")
	blbl:SetPoint("TOPLEFT", 0, 0)
	blbl:SetText("|cffffd200THIS SESSION|r")
	parent._blbl = blbl
	local blist = newText(live, "OVERLAY")
	blist:SetPoint("TOPLEFT", 0, -18)
	blist:SetWidth(420); blist:SetJustifyH("LEFT"); blist:SetJustifyV("TOP")
	parent._blist = blist
	parent._live = live

	-- ---- session history: a scrollable, inline-expandable list ----
	-- Anchored just below the live block (which collapses to 0 height when idle).
	local hh = newText(parent, "OVERLAY")
	hh:SetPoint("TOPLEFT", live, "BOTTOMLEFT", 0, -14)
	hh:SetText("|cff8a8d93PAST SESSIONS|r")
	parent._histHdr = hh

	-- flat scroll (no Blizzard template): plain ScrollFrame + our own slider
	local sf = CreateFrame("ScrollFrame", nil, parent)
	sf:SetPoint("TOPLEFT", hh, "BOTTOMLEFT", 0, -8); sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -14, 8)
	local child = CreateFrame("Frame", nil, sf); child:SetSize(10, 1); sf:SetScrollChild(child)
	local sb = CreateFrame("Slider", nil, parent)
	sb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 8, 0); sb:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 8, 0); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
	local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetSize(4, 40)
	do local a = Okanvil.Colors.accent; th:SetVertexColor(a[1], a[2], a[3], 1) end
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 30) end)
	sf:SetScript("OnSizeChanged", function() child:SetWidth(sf:GetWidth()) end)
	parent._histSF, parent._histChild, parent._histSB = sf, child, sb
	parent._histRows, parent._histDetail = {}, {}
	parent._expanded = nil

	OkanvilLogs.Refresh()
	OkanvilLogs.RebuildHistory()
end

-- build the past-sessions list (rows + inline expansion), like the Loot tab.
function OkanvilLogs.RebuildHistory()
	local p = OkanvilLogs.panel
	if not p or not p._histChild then return end
	local W = Okanvil.W
	local child = p._histChild
	for _, r in ipairs(p._histRows) do r:Hide() end
	for _, t in ipairs(p._histDetail) do t:Hide() end
	local sessions = (db and db.sessions) or {}

	if #sessions == 0 then
		p._histEmpty = p._histEmpty or newText(child, "OVERLAY")
		p._histEmpty:SetPoint("TOPLEFT", 2, -4)
		p._histEmpty:SetText("|cff888888No past sessions yet. Start a log and kill a boss.|r")
		p._histEmpty:Show()
		child:SetHeight(30)
		return
	end
	if p._histEmpty then p._histEmpty:Hide() end

	local di, y = 0, 0
	for i, s in ipairs(sessions) do
		local r = p._histRows[i]
		if not r then
			r = W.Frame(child, "row")
			r.title = newText(r, "OVERLAY"); r.title:SetPoint("TOPLEFT", 8, -5)
			r.sub = newText(r, "OVERLAY", 10); r.sub:SetPoint("BOTTOMLEFT", 8, 5)
			r.del = W.Button(r, "X", "danger")
			r.del:SetSize(22, 20); r.del:SetPoint("RIGHT", -6, 0)
			r:EnableMouse(true)
			p._histRows[i] = r
		end
		r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetPoint("RIGHT", child, "RIGHT", 0, 0); r:SetHeight(38)
		local where = (s.zone ~= "" and s.zone) or "World"
		local dateStr = date("%b %d  %H:%M", s.start)
		local dur = (s.stop and s.stop > s.start) and fmtTime(s.stop - s.start) or "?"
		local nb = s.bosses and #s.bosses or 0
		local isOpen = (p._expanded == s)
		r.title:SetText((isOpen and "|cffffd200v|r  " or "|cff8a8d93>|r  ") .. where)
		r.sub:SetText("|cff8a8d93" .. dateStr .. "  |  " .. dur .. "  |  " .. nb .. " boss" .. (nb == 1 and "" or "es") .. "|r")
		local function toggle()
			if p._expanded == s then p._expanded = nil else p._expanded = s end
			OkanvilLogs.RebuildHistory()
		end
		r:SetScript("OnMouseUp", toggle)
		r.del:SetScript("OnClick", function()
			if p._expanded == s then p._expanded = nil end
			OkanvilLogs.DeleteSession(s)
		end)
		r:Show()
		y = y + 44

		if isOpen then
			di = di + 1
			local t = p._histDetail[di]
			if not t then t = newText(child, "OVERLAY"); t:SetJustifyH("LEFT"); t:SetJustifyV("TOP"); p._histDetail[di] = t end
			t:ClearAllPoints(); t:SetPoint("TOPLEFT", 14, -y); t:SetPoint("RIGHT", child, "RIGHT", -8, 0)
			if s.bosses and #s.bosses > 0 then
				local lines = {}
				for k = 1, #s.bosses do
					lines[k] = string.format("|cff66dd66+|r %s  |cff888888%s|r", s.bosses[k].name, fmtTime(s.bosses[k].at or 0))
				end
				t:SetText(table.concat(lines, "\n"))
			else
				t:SetText("|cff888888No bosses recorded this session.|r")
			end
			t:Show()
			y = y + (t:GetStringHeight() or 12) + 10
		end
	end
	child:SetHeight(math.max(1, y))
	local maxs = math.max(0, y - p._histSF:GetHeight())
	p._histSB:SetMinMaxValues(0, maxs); p._histSB:SetShown(maxs > 4)
end

function OkanvilLogs.Refresh()
	if OkanvilLogs._dash then OkanvilLogs._dash:Refresh() end   -- header REC status
	local p = OkanvilLogs.panel
	if not p or not p._toggle then
		return
	end
	if isLogging() then
		p._toggle.text:SetText("STOP logging")
	else
		p._toggle.text:SetText("START logging")
	end
	-- status card (right of the CTA)
	if p._stTop then
		local cur = db and db._cur
		if cur then
			p._stTop:SetText("|cffff3333REC|r  |cffdcddde" .. ((cur.zone ~= "" and cur.zone) or "World") .. "|r")
			local nb = cur.bosses and #cur.bosses or 0
			p._stSub:SetText("|cff8a8d93" .. fmtTime(time() - cur.start) .. "  |  " .. nb .. " boss" .. (nb == 1 and "" or "es") .. " logged|r")
		else
			p._stTop:SetText("|cff8a8d93Not logging|r")
			p._stSub:SetText("|cff6f7176Press START to begin a session.|r")
		end
	end
	if p._blist then
		local cur = db and db._cur
		if cur then
			if p._blbl then p._blbl:Show() end
			if p._live then p._live:Show() end
			local list = cur.bosses
			local n = list and #list or 0
			if n > 0 then
				local lines = {}
				for i = 1, n do
					lines[i] = string.format("|cff66dd66+|r %s  |cff888888%s|r", list[i].name, fmtTime(list[i].at or 0))
				end
				p._blist:SetText(table.concat(lines, "\n"))
			else
				p._blist:SetText("|cff888888Recording... boss kills appear here as they happen.|r")
			end
			-- grow the live block so PAST SESSIONS sits below it
			if p._live then
				local h = 18 + (p._blist:GetStringHeight() or 12) + 6
				p._live:SetHeight(math.max(20, h))
			end
		else
			-- no open session: COLLAPSE the live block so the history list pulls
			-- right up under the hint (no dead space).
			if p._blbl then p._blbl:Hide() end
			p._blist:SetText("")
			if p._live then p._live:SetHeight(1); p._live:Hide() end
		end
	end
	if OkanvilLogs.RebuildHistory then OkanvilLogs.RebuildHistory() end
end

-- ------------------------------------------------------------
-- events / boot
-- ------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_DISABLED") -- entered combat -> guarantee the raid is being logged
ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") -- watch for boss deaths to list them per session
ev:SetScript("OnEvent", function(_, event, arg1, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		-- Modulo Combat Logs DESLIGADO = nao regista nada (como se nao existisse).
		if Okanvil.ModuleActive and not Okanvil:ModuleActive(ADDON) then return end
		-- cheap early-out unless a session is active; arg1 = timestamp, ... = subevent, src*, dest*
		if not db or not db._cur then
			return
		end
		if ... == "UNIT_DIED" then
			recordBoss(select(5, ...), select(6, ...)) -- destGUID, destName
		end
		return
	end
	if event == "ADDON_LOADED" and arg1 == "Okanvil" then -- native module: host's load
		OkanvilLogsDB = OkanvilLogsDB or {}
		for k, v in pairs(defaults) do
			if OkanvilLogsDB[k] == nil then
				OkanvilLogsDB[k] = (type(v) == "table") and {} or v
				if type(v) == "table" then
					for kk, vv in pairs(v) do
						OkanvilLogsDB[k][kk] = vv
					end
				end
			end
		end
		db = OkanvilLogsDB
		-- NOTE: we intentionally KEEP db._cur across reload/relog. A session stays
		-- open until the user hits Stop, so PLAYER_ENTERING_WORLD can resume the
		-- client log (reload/teleport turn it off) without losing or splitting it.
	elseif event == "PLAYER_LOGIN" then
		buildRec()
		-- native module: register into the host (toggle in Modules to hide it)
		Okanvil_Plugins = Okanvil_Plugins or {}
		Okanvil_Plugins[ADDON] = {
			title = "Combat Logs",
			-- No nav row: logging starts itself at the first pull, the REC timer on
			-- screen says when it is running, and its two settings live in
			-- Settings > Raid Tools. A page for a switch you never press.
			noNav = true,
			desc = "Combat-log control + REC timer. Starts at the first pull; settings in Settings > Raid Tools.",
			icon = (Okanvil and Okanvil.ICONS and Okanvil.ICONS.logs) or "Interface\\Icons\\INV_Scroll_03",
			build = function(panel)
				OkanvilLogs.panel = panel
				OkanvilLogs.BuildUI(panel)
			end,
			refresh = function()
				OkanvilLogs.Refresh()
			end,
		}
		if Okanvil and Okanvil.Register then
			Okanvil:Register(ADDON)   -- silent; /oklog still toggles logging
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if not db then
			return
		end
		-- Modulo desligado = nao faz auto-resume nem pergunta para gravar.
		if Okanvil.ModuleActive and not Okanvil:ModuleActive(ADDON) then return end
		local inInstance, itype = IsInInstance()
		-- A session left open across a long absence is not the same raid. The timer
		-- counts wall clock, so resuming one after a night offline showed hours of
		-- "recording" that never happened. Anything under the gap is a reload, a
		-- teleport or a short disconnect and still resumes silently.
		if db._cur then
			local idle = time() - (db._cur.seen or db._cur.start or time())
			-- ...unless we land back INSIDE the same raid the session belongs to, and
			-- not too long after. Then the raid is plainly still going and the idle
			-- time is a break, not the end of the night -- closing here splits one
			-- raid into two logs, which is what a long DBM break plus a /reload used
			-- to do. The ceiling still matters: log out inside the instance and come
			-- back tomorrow and that IS a new raid, however unchanged the zone looks.
			local sameRaid = inInstance and itype == "raid"
				and db._cur.zone == (GetRealZoneText() or GetZoneText() or "")
				and idle <= SAME_RAID_GRACE
			if idle > STALE_AFTER and not sameRaid then
				local mins = math.floor(idle / 60)
				endSession(db._cur.seen or db._cur.start)
				if LoggingCombat() then LoggingCombat(false) end
				if rec then rec:Hide() end
				Okanvil:Print(("|cffc0943aLogs|r closed a session left open for %s -- starting fresh.")
					:format(mins >= 120 and (math.floor(mins / 60) .. "h") or (mins .. " min")))
			end
		end

		if db._cur then
			-- Session still open: a /reload, relog or in-instance teleport turns the
			-- client log back OFF. Silently RESUME -- never reset, never split, never re-ask.
			-- Stamp `seen` first: it may be minutes old (that is how we just got here),
			-- and leaving it stale would make the very next check call this idle again.
			db._cur.seen = time()
			if not LoggingCombat() then
				buildRec()
				LoggingCombat(true)
				rec:Show()
				toast("REC -- resumed (still logging)", "00ff00")
			end
		elseif inInstance and itype == "raid" and not LoggingCombat() then
			-- No active session and we just entered a RAID: ask once per zone. We only
			-- prompt for raids -- 5-man dungeon combat logs are rarely wanted, so they
			-- never nag (start those by hand with the Combat Logs page if needed).
			local zone = GetRealZoneText()
			if not zone or zone == "" then
				zone = GetZoneText()
			end
			if db.askOnEnter and zone ~= askedZone then
				askedZone = zone
				askToLog(zone)
			elseif db.autoLog then
				OkanvilLogs.SetLogging(true) -- legacy silent auto-log (askOnEnter off)
			end
		elseif not inInstance then
			askedZone = nil -- left the instance -> allow asking again on next entry
			OkanvilLogs._suppressAuto = nil -- left the raid -> auto-log may kick in again next time
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Modulo desligado = nao inicia logging automatico ao entrar em combate.
		if Okanvil.ModuleActive and not Okanvil:ModuleActive(ADDON) then return end
		-- Entered combat: guarantee a raid pull is always being logged.
		if db then
			if db._cur then
				if not LoggingCombat() then LoggingCombat(true) end -- keep an open session truly ON
			else
				local inInstance, itype = IsInInstance()
				if inInstance and itype == "raid" and not OkanvilLogs._suppressAuto
					and db.autoOnPull ~= false then
					OkanvilLogs.SetLogging(true) -- safety net: never miss a raid boss again
				end
			end
		end
	end
end)

-- ------------------------------------------------------------
-- slash
-- ------------------------------------------------------------
-- No slash command: open Okanvil from the minimap button and pick Combat Logs.
-- Start/stop logging is a toggle inside the module UI.
