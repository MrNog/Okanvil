-- ============================================================
--   ██████╗ ██╗  ██╗ █████╗ ███╗   ██╗██╗   ██╗██╗██╗
--  ██╔═══██╗██║ ██╔╝██╔══██╗████╗  ██║██║   ██║██║██║
--  ██║   ██║█████╔╝ ███████║██╔██╗ ██║██║   ██║██║██║
--  ██║   ██║██╔═██╗ ██╔══██║██║╚██╗██║╚██╗ ██╔╝██║██║
--  ╚██████╔╝██║  ██╗██║  ██║██║ ╚████║ ╚████╔╝ ██║███████╗
--   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚══════╝
--  Okanvil -- a single raid & guild toolkit (MRT-style), by Okanor. One addon
--  with a native core (guild dashboard + module manager) and a set of built-in
--  modules (Guild / Invite / Recruit / Loot / ID Finder / Combat Logs) you toggle
--  on/off per character. Modules register into Okanvil_Plugins and share one media
--  layer. No standalone plugins -- it's all one addon.
-- ============================================================

Okanvil = Okanvil or {}
local Okanvil = Okanvil

-- ------------------------------------------------------------
-- 3.3.5a API compat shim: SetShown was added in WoW 4.x (Cataclysm). On a stock
-- 3.3.5a client the widget methods don't exist, so every `frame:SetShown(cond)`
-- throws "attempt to call method 'SetShown' (a nil value)". Some custom/patched
-- 3.3.5a cores backport it, which is why it works for some players and not
-- others. Polyfill it onto the shared widget metatables here, BEFORE any UI is
-- built (Core loads first in the .toc), so all 25+ call sites just work. Guarded
-- so a client that already has SetShown (patched core) is left untouched.
-- ------------------------------------------------------------
do
	local function polyfill(obj)
		if not obj then return end
		local mt = getmetatable(obj)
		local idx = mt and mt.__index
		if type(idx) ~= "table" then return end
		if not idx.SetShown then
			idx.SetShown = function(self, shown)
				if shown then self:Show() else self:Hide() end
			end
		end
	end
	-- Each widget TYPE has its own method table on 3.3.5a -- a Frame, a Slider and a
	-- Button do not share one. Every type we actually use must be patched, or
	-- `slider:SetShown(...)` still dies with "attempt to call method 'SetShown'".
	--
	-- CRITICAL: do NOT create an EditBox here to "also patch it". A fresh EditBox
	-- defaults to autoFocus=true and GRABS the keyboard on creation -- an orphan box
	-- left focused eats W/A/S/D for the whole session and makes the game unplayable.
	local f = CreateFrame("Frame")
	polyfill(f)
	polyfill(f:CreateTexture())
	polyfill(f:CreateFontString())
	polyfill(CreateFrame("Button"))
	polyfill(CreateFrame("Slider"))
	polyfill(CreateFrame("StatusBar"))
	polyfill(CreateFrame("ScrollFrame"))
	polyfill(CreateFrame("CheckButton"))
	polyfill(CreateFrame("Cooldown"))
end

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
Okanvil.LSM = LSM

Okanvil.version = GetAddOnMetadata and GetAddOnMetadata("Okanvil", "Version") or "1.0"
Okanvil.entries = {}          -- name -> plugin table (registered)
Okanvil._fontStrings = {}     -- font strings to restyle when the font changes

-- ------------------------------------------------------------
-- KEYBOARD-FOCUS SAFETY
-- An EditBox with keyboard focus swallows ALL keys -- including W/A/S/D -- so a
-- focus we forget to release makes the game unplayable (the user lost all keybinds
-- and had to delete the addon). Rules, per the user:
--   * NEVER auto-SetFocus (opening the addon must not steal the keyboard -- you
--     could be mid-fight and unable to move).
--   * Clicking ANYWHERE outside a text box drops focus.
--   * Entering combat / closing the window / switching page releases focus.
-- We track every EditBox we make and clear them all on those events.
-- ------------------------------------------------------------
Okanvil._editBoxes = Okanvil._editBoxes or {}
function Okanvil:TrackEditBox(e)
	if not e then return end
	self._editBoxes[e] = true
end
function Okanvil:ClearAllFocus()
	for e in pairs(self._editBoxes) do
		if e.HasFocus and e:HasFocus() then e:ClearFocus() end
	end
end

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

-- ------------------------------------------------------------
-- ITEM CACHE WARMER  (shared by Mini Roll / Loot / Raid Finder)
-- On a fresh client, GetItemInfo returns nil for an item it has never seen, so
-- icons show "?" and AtlasLoot draws a red border. The fix is exactly what
-- AtlasLoot's "Query" button does: a hidden GameTooltip:SetHyperlink forces the
-- client to request the item from the server; a moment later GetItemInfo works.
--   * Okanvil:WarmItem(link|id)  -> queue a server request (deduped, throttled)
--   * Okanvil:ItemIcon(link|id)  -> icon texture now, or nil + auto-warm for later
-- Warming is throttled to a few items/sec on a ticker so it can't lag/disconnect
-- you (AtlasLoot's busy-loop can; ours is async).
-- ------------------------------------------------------------
do
	local tip                       -- hidden scanning tooltip (created on demand)
	local queue, queued = {}, {}    -- pending item keys + dedupe set
	local ticker                    -- OnUpdate driver (runs only while queue nonempty)
	local acc = 0

	local function keyOf(itemLinkOrId)
		if type(itemLinkOrId) == "number" then return "item:" .. itemLinkOrId end
		if type(itemLinkOrId) ~= "string" then return nil end
		if itemLinkOrId:find("item:") then
			-- extract the numeric id so links/ids dedupe to the same key
			local id = itemLinkOrId:match("item:(%d+)")
			return id and ("item:" .. id) or itemLinkOrId
		end
		local id = tonumber(itemLinkOrId)
		return id and ("item:" .. id) or nil
	end

	local function pump()
		if #queue == 0 then
			if ticker then ticker:SetScript("OnUpdate", nil); ticker:Hide() end
			return
		end
		if not tip then
			tip = CreateFrame("GameTooltip", "OkanvilWarmTip", nil, "GameTooltipTemplate")
			tip:SetOwner(WorldFrame, "ANCHOR_NONE")
		end
		-- process a few per tick (throttle -- server query is the risky part)
		for _ = 1, 3 do
			local key = table.remove(queue, 1)
			if not key then break end
			queued[key] = nil
			GetItemInfo(key)                       -- triggers cache request
			pcall(function() tip:SetHyperlink(key) end)
		end
	end

	function Okanvil:WarmItem(itemLinkOrId)
		local key = keyOf(itemLinkOrId)
		if not key or queued[key] then return end
		-- already cached? nothing to do.
		if GetItemInfo(key) then return end
		queued[key] = true
		queue[#queue + 1] = key
		if not ticker then
			ticker = CreateFrame("Frame")
		end
		-- (re)arm the driver: it clears its own OnUpdate when the queue empties.
		ticker:SetScript("OnUpdate", function(_, e)
			acc = acc + e
			if acc >= 0.1 then acc = 0; pump() end
		end)
		ticker:Show()
	end

	-- Return the icon texture NOW, or nil (and queue a warm so a later paint fills
	-- it in). Order: (1) the ID Finder's FILE-persisted icon (survives a client
	-- change -> no "?" after switching clients, IF you ran a Full scan), then
	-- (2) the live client cache (select(10, GetItemInfo) = icon path in 3.3.5a).
	function Okanvil:ItemIcon(itemLinkOrId)
		if not itemLinkOrId then return nil end
		-- try the saved DB first (needs a numeric id)
		if Okanvil.IDs and Okanvil.IDs.ItemIcon then
			local id = (type(itemLinkOrId) == "number") and itemLinkOrId
				or tonumber(tostring(itemLinkOrId):match("item:(%d+)"))
				or tonumber(itemLinkOrId)
			if id then
				local saved = Okanvil.IDs.ItemIcon(id)
				if saved then return saved end
			end
		end
		local tex = select(10, GetItemInfo(itemLinkOrId))
		if not tex then self:WarmItem(itemLinkOrId) end
		return tex
	end
end

-- ------------------------------------------------------------
-- Saved-variable defaults
-- ------------------------------------------------------------
local defaults = {
	window = { width = 660, height = 480, point = "CENTER", x = 0, y = 0 },
	scale = 1.0,
	font = "Friz Quadrata TT", -- LSM font name
	fontSize = 12,
	fontFlag = "", -- "", "OUTLINE", "THICKOUTLINE"
	statusbar = "Blizzard", -- LSM statusbar (for plugins that draw bars)
	bgAlpha = 0.95,
	minimapAngle = 200,
	modules = {},      -- name -> { enabled = bool }. Absent = enabled by default.
	brand = "RATS Guild Hub", -- GUILD SKIN shown after the fixed "Okanvil" wordmark (editable per guild; "" = none)
	hubURL = "https://mrnog.github.io/RATS/", -- the guild's web hub
	lootThreshold = 3, -- min item rarity to log: 0 poor,1 common,2 uncommon,3 rare,4 epic
	recordDungeon = true, -- capture attendance/loot in 5-man dungeons (party instances)
	recordRaid = true,    -- capture attendance/loot in raids
	closeOnPull = true,    -- DBM pull -> close all Okanvil windows (get out of the way on engage)
	ratArt = "on",         -- faded rat blacksmith art in the page corner: "on" | "off"
	ratAlpha = 0.30,       -- rat watermark intensity (own slider; independent of bgAlpha)
	devMode = false,       -- dev output -> dedicated "Okanvil" chat tab (off for raiders)
}

local function applyDefaults(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then
				dst[k] = {}
				applyDefaults(dst[k], v)
			else
				dst[k] = v
			end
		elseif type(v) == "table" then
			applyDefaults(dst[k], v)
		end
	end
end

-- ------------------------------------------------------------
-- Media (shared look -- plugins use these so everything matches)
-- ------------------------------------------------------------
function Okanvil:Font()
	local db = self.db
	local path = LSM and LSM:Fetch("font", db.font, true)
	return path or STANDARD_TEXT_FONT, db.fontSize, db.fontFlag
end

function Okanvil:Texture()
	return (LSM and LSM:Fetch("statusbar", self.db.statusbar, true)) or FLAT
end

-- create a font string that auto-restyles when the user changes the font
function Okanvil:NewText(parent, layer, template)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY", template)
	fs:SetFont(self:Font())
	self._fontStrings[fs] = true
	return fs
end

function Okanvil:ApplyFonts()
	local font, size, flag = self:Font()
	for fs in pairs(self._fontStrings) do
		if fs.SetFont then
			-- keep per-string size if it was bumped (store a .sizeMul); default to global size
			fs:SetFont(font, fs._okSize or size, flag)
		end
	end
end

-- flat 1px-bordered panel (the Okanvil/ElvUI look). Plugins: use Okanvil:Backdrop(frame).
-- Kept for back-compat; delegates to the shared Okanvil:Skin (Widgets.lua) so
-- legacy plugins pick up the same palette and alpha re-tinting as the shell.
function Okanvil:Backdrop(frame, alpha, dark)
	if self.Skin then
		self:Skin(frame, dark and "dark" or "panel")
		if alpha then
			local r, g, b = frame:GetBackdropColor()
			frame:SetBackdropColor(r, g, b, alpha)
		end
		return
	end
	-- fallback if Widgets.lua somehow didn't load
	frame:SetBackdrop({
		bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	local a = alpha or self.db.bgAlpha
	if dark then frame:SetBackdropColor(0.06, 0.06, 0.08, a)
	else frame:SetBackdropColor(0.10, 0.10, 0.12, a) end
	frame:SetBackdropBorderColor(0.32, 0.32, 0.38, 1)
end

-- Every addon message goes to the "Okanvil" chat tab when that tab EXISTS, else to
-- the default frame. We never create it here (DevFrame(false)): a raider who has
-- never opened the tab keeps seeing messages in General instead of having a window
-- appear unasked. Create it with /okanvil tab.
--
-- self:DevFrame is resolved at call time, so it being defined further down is fine.
function Okanvil:Print(msg)
	local f = (self.DevFrame and self:DevFrame(false)) or DEFAULT_CHAT_FRAME
	f:AddMessage("|cffffd200[Okanvil]|r " .. tostring(msg))
end

-- ------------------------------------------------------------
-- Walk the FULL guild roster without leaving the Blizzard guild UI changed.
--
-- 3.3.5a trap: GetNumGuildMembers() only counts ONLINE members unless "Show Offline"
-- is on, so to iterate everyone you must SetGuildRosterShowOffline(true). But that
-- flag is GLOBAL and STICKY -- it flips the checkbox in Blizzard's own Guild panel and
-- stays on after we're done, which is why the guild tab was suddenly always showing
-- offline members.
--
-- 3.3.5a has no reliable getter for the flag, and inferring "did we turn it on?" from
-- the member count is unsound: forcing offline in does NOT change the count when the
-- whole guild is already online, so we could never tell we'd enabled it and would leak
-- it on. So we don't guess -- we ALWAYS restore the WoW default (offline hidden) after
-- walking. Cost: a user who manually ticked "Show Offline" gets it unticked after we
-- run. That is rare and far less bad than the addon silently forcing it on for everyone;
-- if it ever matters, add an explicit opt-out setting.
--
--   Okanvil:WithFullRoster(function(total) ... GetGuildRosterInfo(i) ... end)
--
-- LOOP GUARD: toggling SetGuildRosterShowOffline fires GUILD_ROSTER_UPDATE. Our guild
-- panel refreshes on that event, and the refresh calls WithFullRoster, which toggles
-- again -> event -> refresh -> ... an endless storm that ends in a C stack overflow.
-- The event is async (fires AFTER we return), so a simple in-function reentrancy flag
-- is not enough. Instead we publish Okanvil.rosterBusy while we hold the flag; the
-- GUILD_ROSTER_UPDATE handler skips its refresh when it sees a roster event we caused
-- ourselves. Reads only ever set the flag briefly, so a real login/logoff that lands
-- outside our window still refreshes normally.
function Okanvil:WithFullRoster(fn)
	if not (IsInGuild and IsInGuild()) then return end
	if self.rosterBusy then
		-- nested call (offline already forced in): run against the roster as-is
		local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
		local ok, err = pcall(fn, total)
		if not ok and Okanvil.Err then Okanvil:Err("WithFullRoster(nested)", err) end
		return
	end
	self.rosterBusy = true
	if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
	local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
	local ok, err = pcall(fn, total)
	if SetGuildRosterShowOffline then SetGuildRosterShowOffline(false) end
	-- Keep the guard up briefly: GUILD_ROSTER_UPDATE from our two toggles arrives
	-- AFTER we return here (it's async), so clearing rosterBusy now would let that
	-- late event trigger a refresh -> another WithFullRoster -> the loop. Drop it a
	-- moment later; a genuine login/logoff event after that still refreshes.
	if Okanvil.Comms and Okanvil.Comms.After then
		Okanvil.Comms.After(0.3, function() Okanvil.rosterBusy = false end)
	else
		self.rosterBusy = false
	end
	if not ok and Okanvil.Err then Okanvil:Err("WithFullRoster", err) end
end

-- ------------------------------------------------------------
-- DEV CHAT TAB -- a dedicated "Okanvil" chat window (like DBM's debug tab),
-- sitting next to General / Combat Log. Debug output goes there instead of
-- spamming the general chat. Created ON DEMAND (only when dev mode is turned
-- on), so raiders never see it.
--
-- 3.3.5a API: FCF_OpenNewWindow(name) opens a new chat window and returns it in
-- the global ChatFrameN; GetChatWindowInfo(i) gives each window's name. There is
-- no C_ChatInfo here -- windows are plain frames we can AddMessage() to.
-- ------------------------------------------------------------
local DEV_TAB_NAME = "Okanvil"
local devFrame                       -- cached ChatFrame we write into

-- find an existing chat window called "Okanvil" (survives /reload -- the client
-- persists chat windows, so we must re-find it rather than open a duplicate).
local function findDevFrame()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local name = GetChatWindowInfo and GetChatWindowInfo(i)
		if name == DEV_TAB_NAME then return _G["ChatFrame" .. i] end
	end
	return nil
end

-- Get the dev chat frame, creating the tab if asked to (and if we can).
function Okanvil:DevFrame(createIfMissing)
	if devFrame and devFrame.AddMessage then return devFrame end
	devFrame = findDevFrame()
	if devFrame or not createIfMissing then return devFrame end
	if not FCF_OpenNewWindow then return nil end
	-- opening a window can fail when all 10 slots are used
	local ok = pcall(FCF_OpenNewWindow, DEV_TAB_NAME)
	if ok then devFrame = findDevFrame() end
	return devFrame
end

-- Write one line to the dev tab. Falls back to the default chat frame only when
-- the tab could not be created, so a message is never silently lost.
function Okanvil:Dev(msg)
	if not self.db or not self.db.devMode then return end
	local f = self:DevFrame(true) or DEFAULT_CHAT_FRAME
	f:AddMessage("|cff8a8d93[dbg]|r " .. tostring(msg))
end

-- ------------------------------------------------------------
-- SILENT-ERROR REPORTER. Wrap a pcall's failure with this instead of dropping
-- it: `if not ok then Okanvil:Err("Comms.After", err) end`.
--
-- Rules that keep it from ever becoming spam:
--   * dev mode OFF -> PRINTS nothing anywhere (raiders never see it),
--   * ...but it is still RECORDED, so a bug that happened mid-raid is waiting
--     for you afterwards even though you never had dev mode on,
--   * the same error at the same site prints ONCE per session; repeats only
--     bump a counter (an error inside OnUpdate would otherwise print 60x/sec).
--
-- The record lives in the per-character DB, which WoW flushes to
-- SavedVariables\Okanvil.lua on logout/reload -- so nothing is lost if you
-- forget to check it before quitting. Read it back with
-- `/okerr`, or straight out of the .lua file.
-- ------------------------------------------------------------
-- A WoW addon cannot write files (no `io` in the sandbox). The ONLY file we get
-- is a SavedVariable, which the client flushes on logout/reload. `OkanvilBugDB`
-- is declared in the .toc purely for this, so the crash history sits in its own
-- top-level table inside:
--     WTF\Account\<ACCOUNT>\SavedVariables\Okanvil.lua
-- A raider who hit a bug sends that file; you read the OkanvilBugDB block and
-- ignore the rest. (BugSack persists its errors the same way.)
--
-- Layout: OkanvilBugDB.sessions = { {start=<unix>, ver=<addon ver>, errors={...}}, ... }
-- newest session LAST. Each error: { context, msg, count, first, last }.
local ERR_SESSIONS = 5    -- keep the last N play sessions
local ERR_PER_SESS  = 40  -- distinct errors per session (bounds the SV file)

local errSession          -- the session table for THIS login (created lazily)

function Okanvil:ErrorLog()
	-- The SV table only exists after ADDON_LOADED; an error can fire earlier, so
	-- create it on demand rather than erroring inside the error reporter itself.
	OkanvilBugDB = OkanvilBugDB or {}
	OkanvilBugDB.sessions = OkanvilBugDB.sessions or {}
	return OkanvilBugDB.sessions
end

-- The session record for this login, trimming old sessions on first use.
local function currentErrSession(self)
	if errSession then return errSession end
	local log = self:ErrorLog()
	errSession = {
		start = time(), ver = self.version or "?",
		char = (UnitName and UnitName("player")) or "?",
		errors = {},
	}
	log[#log + 1] = errSession
	while #log > ERR_SESSIONS do table.remove(log, 1) end
	return errSession
end

-- Record a silent error. ALWAYS persisted (so you can ask a raider for their
-- Okanvil.lua after a bug), but only PRINTED when dev mode is on -- and then
-- only once per distinct error, so a failure inside OnUpdate can't spam.
function Okanvil:Err(context, err)
	local ctx, msg = tostring(context or "?"), tostring(err or "?")
	local s = currentErrSession(self)
	for _, e in ipairs(s.errors) do
		if e.context == ctx and e.msg == msg then
			e.count = (e.count or 1) + 1
			e.last = time()
			return                                -- already reported this session
		end
	end
	if #s.errors >= ERR_PER_SESS then return end  -- full: drop rather than grow the SV
	s.errors[#s.errors + 1] = { context = ctx, msg = msg, count = 1, first = time(), last = time() }
	self:Dev("|cffff5555ERROR|r " .. ctx .. ": " .. msg)
end

-- This session's distinct errors, most frequent first.
function Okanvil:ErrorSummary()
	local out = {}
	for _, e in ipairs(currentErrSession(self).errors) do out[#out + 1] = e end
	table.sort(out, function(a, b) return (a.count or 0) > (b.count or 0) end)
	return out
end

-- Whole history, formatted for the copy box (/okerr). This is also what
-- you read straight out of Okanvil.lua when a raider sends you their file.
function Okanvil:ErrorReport()
	local log = self:ErrorLog()
	local total = 0
	for _, s in ipairs(log) do total = total + #s.errors end
	if total == 0 then return nil end
	local out = { "Okanvil error log -- " .. #log .. " session" .. (#log ~= 1 and "s" or "")
		.. ", " .. total .. " error" .. (total ~= 1 and "s" or "") }
	for i = #log, 1, -1 do                        -- newest session first
		local s = log[i]
		out[#out + 1] = ""
		out[#out + 1] = "=== " .. date("%Y-%m-%d %H:%M", s.start or 0)
			.. "   " .. (s.char or "?") .. "   Okanvil v" .. (s.ver or "?")
			.. "   (" .. #s.errors .. " error" .. (#s.errors ~= 1 and "s" or "") .. ")"
		if #s.errors == 0 then out[#out + 1] = "    (none)" end
		for _, e in ipairs(s.errors) do
			out[#out + 1] = "  [x" .. (e.count or 1) .. "] " .. date("%H:%M", e.first or 0)
				.. "  " .. (e.context or "?") .. ": " .. (e.msg or "?")
		end
	end
	return table.concat(out, "\n")
end

function Okanvil:ClearErrors()
	OkanvilBugDB = { sessions = {} }
	errSession = nil
end

-- Turn dev mode on/off. Opening the tab is deferred to the first Dev() call, but
-- we create it here too so the user immediately SEES where output will land.
function Okanvil:SetDevMode(on)
	self.db.devMode = on and true or false
	if self.db.devMode then
		local f = self:DevFrame(true)
		self:Print("Dev mode |cff7cfc8aON|r"
			.. (f and (" -- output goes to the |cffe0b860" .. DEV_TAB_NAME .. "|r chat tab.")
			or " -- |cffff5555could not open a chat tab (all 10 in use); using default chat.|r"))
	else
		self:Print("Dev mode |cff8a8d93OFF|r")
	end
end

-- Should we record attendance/loot right now? Respects the dungeon/raid toggles.
-- Outside instances (e.g. world) we still allow it (manual snapshots, etc.).
function Okanvil:ShouldRecord()
	if not GetInstanceInfo then return true end
	local _, instanceType = GetInstanceInfo()
	if instanceType == "party" then return self.db.recordDungeon ~= false end
	if instanceType == "raid" then return self.db.recordRaid ~= false end
	return true
end

-- ------------------------------------------------------------
-- Plugin registry (load-order safe: plugins fill Okanvil_Plugins)
-- ------------------------------------------------------------
function Okanvil:Register(name)
	local p = Okanvil_Plugins and Okanvil_Plugins[name]
	if not p or self.entries[name] then
		return
	end
	self.entries[name] = p
	if self.RefreshNav then
		self:RefreshNav() -- live update if the window is already built
	end
end

function Okanvil:ProcessPlugins()
	if not Okanvil_Plugins then
		return
	end
	for name in pairs(Okanvil_Plugins) do
		self:Register(name)
	end
end

function Okanvil:CountPlugins()
	local n = 0
	for _ in pairs(self.entries) do
		n = n + 1
	end
	return n
end

-- ------------------------------------------------------------
-- Module enable state -- PER CHARACTER (Okanvil_CharDB). Default: enabled. Each
-- toon decides which tools show; content settings stay account-wide. A disabled
-- module is still registered but hidden from the nav; deeper event-gating is
-- opt-in inside each module later.
-- ------------------------------------------------------------
function Okanvil:IsModuleEnabled(name)
	local m = self.cdb and self.cdb.modules and self.cdb.modules[name]
	if m and m.enabled == false then
		return false
	end
	return true
end

-- Should this module's PASSIVE behaviour run right now? A DISABLED module must be
-- as if it didn't exist -- it must NOT scan chat, log combat, capture loot, or
-- auto-invite. Every module gates its event handlers / OnUpdate ticks with this
-- (return early when false). Safe before login (cdb nil -> treated as enabled, so
-- boot events still register). This is the ONE rule for "off = off, not just hidden".
function Okanvil:ModuleActive(name)
	if not self.cdb then return true end   -- pre-login: let boot run
	return self:IsModuleEnabled(name)
end

function Okanvil:SetModuleEnabled(name, enabled)
	local cdb = self.cdb
	cdb.modules = cdb.modules or {}
	cdb.modules[name] = cdb.modules[name] or {}
	cdb.modules[name].enabled = enabled and true or false
	if self.RefreshNav then self:RefreshNav() end
	-- if the active panel was just disabled, fall back to Home
	if not enabled and self._current == name and self.ShowPanel then
		self:ShowPanel("__home")
	end
end

-- ------------------------------------------------------------
-- Events / boot
-- ------------------------------------------------------------
local core = CreateFrame("Frame")
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
core:RegisterEvent("PLAYER_REGEN_DISABLED")   -- entered combat -> release keyboard
core:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_REGEN_DISABLED" then
		-- combat started: never keep the keyboard captured (movement must work)
		Okanvil:ClearAllFocus()
		return
	end
	if event == "ADDON_LOADED" and arg1 == "Okanvil" then
		Okanvil_DB = Okanvil_DB or {}
		applyDefaults(Okanvil_DB, defaults)
		Okanvil.db = Okanvil_DB
		-- PER-CHARACTER state (which modules THIS toon shows). Content settings
		-- (brand, fonts, recruit messages, item DB...) stay account-wide in db;
		-- only enable/disable is per-char, so each toon can turn tools on/off.
		Okanvil_CharDB = Okanvil_CharDB or {}
		Okanvil.cdb = Okanvil_CharDB
		-- one-time migration: move any account-wide module toggles to this char
		if Okanvil_DB.modules and not Okanvil_CharDB.modules then
			Okanvil_CharDB.modules = Okanvil_DB.modules
			Okanvil_DB.modules = nil
		end
		Okanvil_CharDB.modules = Okanvil_CharDB.modules or {}
		-- migrate old saved brands: the product name is now a FIXED wordmark, so
		-- db.brand is only the guild skin. Strip a leading "Okanvil" (+ separator)
		-- left over from when it held the whole "Okanvil - <guild>" string.
		local b = Okanvil_DB.brand
		if type(b) == "string" then
			local skin = b:gsub("^%s*[Oo]kanvil%s*[%-%:%|\194\183]*%s*", "")
			if skin == "Okanvil" then skin = "" end
			Okanvil_DB.brand = skin
		end
	elseif event == "PLAYER_LOGIN" then
		Okanvil:ProcessPlugins()
		if Okanvil.BuildMinimap then
			Okanvil:BuildMinimap()
		end
		-- DBM pull -> close every Okanvil window (get the UI out of the way on engage).
		-- DBM fires "DBM_Pull" the moment a boss is pulled. Guarded: only if DBM is
		-- present with its callback API, and toggleable via db.closeOnPull (default on).
		if DBM and DBM.RegisterCallback and not Okanvil._dbmPullHooked then
			local ok = pcall(function()
				DBM:RegisterCallback("DBM_Pull", function()
					if Okanvil.db and Okanvil.db.closeOnPull == false then return end
					if Okanvil.CloseAll then Okanvil:CloseAll() end
				end)
			end)
			if ok then Okanvil._dbmPullHooked = true end
		end
		Okanvil:Print("loaded -- |cff00ff00/okanvil|r. " .. Okanvil:CountPlugins() .. " plugin(s).")
	end
end)

-- ------------------------------------------------------------
-- Slash
-- ------------------------------------------------------------
SLASH_Okanvil1 = "/okanvil"
SlashCmdList["Okanvil"] = function(arg)
	arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if arg == "tab" then
		-- opt in to the dedicated chat tab: from now on Print() lands there
		local f = Okanvil:DevFrame(true)
		if f then
			Okanvil:Print("Okanvil messages now go to the |cffe0b860Okanvil|r chat tab.")
		else
			Okanvil:Print("|cffff5555Could not open a chat tab (all 10 slots in use).|r")
		end
		return
	end
	if arg == "help" or arg == "?" then
		Okanvil:Print("commands:")
		Okanvil:Print("  |cffffd200/okanvil|r        open/close the window   |cff8a8d93(/okanvil tab = own chat tab)|r")
		Okanvil:Print("  |cffffd200/okroll|r         mini roll manager")
		Okanvil:Print("  |cffffd200/okerr|r          error log  |cff8a8d93(clear)|r")
		Okanvil:Print("  |cffffd200/okfocus|r    release a stuck keyboard focus")
			Okanvil:Print("  |cff8a8d93every module opens from the minimap button.|r")
		return
	end
	Okanvil:Toggle()
end

-- Emergency keyboard release: if anything ever traps the keyboard again, this
-- clears our tracked boxes AND force-releases any lingering focus. Type /okfocus.
SLASH_OKFOCUS1 = "/okfocus"
SlashCmdList["OKFOCUS"] = function()
	Okanvil:ClearAllFocus()
	Okanvil:Print("released keyboard focus.")
end

-- Dev mode has no slash command -- it's a toggle in Settings (Okanvil:SetDevMode,
-- default OFF). Debug output goes to the "Okanvil" chat tab when it's on.

-- /okerr        -- show the persisted error log (copyable; survives logout)
-- /okerr clear  -- wipe it
SLASH_OKERR1 = "/okerr"
SlashCmdList["OKERR"] = function(arg)
	arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if arg == "clear" then
		Okanvil:ClearErrors()
		Okanvil:Print("Error log cleared.")
		return
	end
	local report = Okanvil:ErrorReport()
	if not report then
		Okanvil:Print("No errors recorded. |cff7cfc8aNice.|r")
		return
	end
	if Okanvil.ShowExport then
		Okanvil:ShowExport(report, "Okanvil errors -- Ctrl+C to copy")
	else
		Okanvil:Print(report)
	end
end

-- ------------------------------------------------------------
-- UPDATE TOAST -- "a newer Okanvil exists". Peer-to-peer: a 3.3.5a addon can't
-- reach the internet, so Comms learns the version from raiders who already
-- updated (see Comms' nag logic). Modelled on Recruit's join toast: a small
-- draggable card on UIParent. Unlike that one it does NOT fade -- it stays put
-- until dismissed, because an update notice you miss is a notice wasted.
-- ------------------------------------------------------------
local updToast
local function buildUpdateToast()
	if updToast then return updToast end
	local t = CreateFrame("Frame", "Okanvil_UpdateToast", UIParent)
	t:SetSize(288, 74)
	t:SetFrameStrata("FULLSCREEN_DIALOG")
	t:SetPoint("TOP", UIParent, "TOP", 0, -140)
	Okanvil:Backdrop(t, 0.96)
	t:EnableMouse(true)
	t:SetMovable(true)
	t:RegisterForDrag("LeftButton")
	t:SetScript("OnDragStart", function(self) self:StartMoving() end)
	t:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	t:Hide()

	local icon = t:CreateTexture(nil, "ARTWORK")
	icon:SetSize(38, 38); icon:SetPoint("TOPLEFT", 10, -9)
	icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local title = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
	title:SetText("|cffe0b860Okanvil update available|r")
	t.title = title

	local sub = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	sub:SetJustifyH("LEFT")
	t.sub = sub

	-- close (X): the toast is persistent, this is the only way out
	local x = CreateFrame("Button", nil, t)
	x:SetSize(18, 18); x:SetPoint("TOPRIGHT", -5, -5)
	local xt = x:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	xt:SetAllPoints(); xt:SetText("|cff8a8d93X|r")
	x:SetScript("OnEnter", function() xt:SetText("|cffff5555X|r") end)
	x:SetScript("OnLeave", function() xt:SetText("|cff8a8d93X|r") end)
	x:SetScript("OnClick", function() t:Hide() end)

	-- copy the download link (no OpenURL on 3.3.5a -> a selectable text box)
	local link = CreateFrame("Button", nil, t)
	link:SetSize(120, 18); link:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, -18)
	local lt = link:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	lt:SetAllPoints(); lt:SetJustifyH("LEFT"); lt:SetText("|cff7cfc8aGet the link|r")
	link:SetScript("OnClick", function()
		local url = (Okanvil.db and Okanvil.db.hubURL) or "https://mrnog.github.io/RATS/"
		if Okanvil.ShowExport then Okanvil:ShowExport(url, "Okanvil -- download (Ctrl+C)") end
	end)
	updToast = t
	return t
end

-- Show the toast for `ver`. Safe to call more than once (Comms nags only once).
function Okanvil:ShowUpdateToast(ver)
	local t = buildUpdateToast()
	t.sub:SetText("|cff8a8d93You run|r " .. (self.version or "?")
		.. "  |cff8a8d93-- newest seen|r |cff7cfc8a" .. tostring(ver) .. "|r")
	t:Show()
	self:Print("A newer Okanvil (|cff7cfc8a" .. tostring(ver) .. "|r) is out -- you run "
		.. (self.version or "?") .. ".")
end

-- wire Comms' nag to the toast once both exist
local bootUpd = CreateFrame("Frame")
bootUpd:RegisterEvent("PLAYER_LOGIN")
bootUpd:SetScript("OnEvent", function()
	if Okanvil.Comms then
		Okanvil.Comms.onNewerVersion = function(ver) Okanvil:ShowUpdateToast(ver) end
	end
end)
