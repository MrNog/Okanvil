-- ============================================================
-- Okanvil -- Comms (central addon-message bus).
-- ONE place for ALL cross-client talk. Every feature that needs to reach other
-- players' Okanvil (loot re-sync now; collectors / counters / whatever later)
-- goes through here instead of each module opening its own SendAddonMessage.
--
-- 3.3.5a notes (verified against RCLootCouncil's AceComm on the live client):
--   * SendAddonMessage(prefix, text, chattype, target) exists; NO
--     RegisterAddonMessagePrefix on this patch -- CHAT_MSG_ADDON just arrives,
--     we filter by prefix in the handler.
--   * CHAT_MSG_ADDON fires as (prefix, message, channel, sender).
--   * prefix + text must stay under ~255 bytes and shares the chat throttle, so
--     payloads are short and fire-and-forget (pair a PUSH with a FETCH/ACK).
--
-- WIRE FORMAT (versioned so mismatched clients ignore what they don't know):
--     OKV1|<TYPE>|<arg1>|<arg2>|...
--   Fields are '|'-separated; a leading "OKV1" gates the protocol version.
--   Unknown TYPEs are dropped silently (forward-compatible).
--
-- TRUST MODEL (the user's hard rule -- anti-ninja): messages are trusted by the
-- sender's ROLE, never by the prefix (anyone can spoof "OKANVIL"). A handler
-- that ACTS on a message (e.g. changes loot method) must re-check the live
-- game state -- "is this sender really the current ML / raid leader?" -- before
-- doing anything. Comms only delivers; it never assumes the sender is honest.
-- ============================================================

local Okanvil = Okanvil
local C = {}
Okanvil.Comms = C

local PREFIX  = "OKANVIL"   -- addon-message prefix (shared by every feature)
local VERSION = "OKV1"      -- payload version tag; bump only on a breaking change
local SEP     = "|"

-- registered message handlers: TYPE -> fn(sender, ...args). Modules add theirs
-- with C.On("MLFIX", handler). Kept load-order safe: a module can register
-- before or after Comms loads, as long as Comms loads first in the .toc (it does).
local handlers = {}

-- ------------------------------------------------------------
-- Encode / decode. We escape the separator inside args so a name or payload that
-- happens to contain '|' can't split a field (belt-and-suspenders: player names
-- can't contain '|', but future payloads might).
-- ------------------------------------------------------------
local function encField(s)
	return (tostring(s == nil and "" or s):gsub("|", "/"))   -- '|' -> '/' (names never contain either meaningfully)
end

local function pack(msgType, ...)
	local parts = { VERSION, msgType }
	local n = select("#", ...)
	for i = 1, n do parts[#parts + 1] = encField(select(i, ...)) end
	return table.concat(parts, SEP)
end

-- ------------------------------------------------------------
-- Channel pick: whatever group we're in. RAID if raiding, else PARTY; nil solo
-- (nothing to send to -- callers should no-op). We never send to GUILD here:
-- these messages are about the CURRENT group's state, not the whole guild.
-- ------------------------------------------------------------
local function groupChannel()
	if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
	if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
	return nil
end

-- ------------------------------------------------------------
-- PUBLIC API
-- ------------------------------------------------------------

-- Register a handler for a message TYPE. fn is called as fn(sender, arg1, arg2, ...)
-- where sender is the raw unit name from CHAT_MSG_ADDON. Only ONE handler per
-- type (last registration wins) -- keeps the bus simple; a type maps to a feature.
function C.On(msgType, fn)
	handlers[msgType] = fn
end

-- Send a typed message to the current group. Returns true if it went out.
-- Fire-and-forget: no delivery guarantee (that's why acts are PUSH + ACK).
function C.Send(msgType, ...)
	local chan = groupChannel()
	if not chan then return false end
	local text = pack(msgType, ...)
	if #text > 240 then return false end   -- stay well under the ~255B cap; long payloads must chunk (none yet)
	SendAddonMessage(PREFIX, text, chan)
	return true
end

-- Whisper a typed message straight to one player (for targeted ACKs). target is
-- a unit name. Works even when the recipient isn't in your subgroup channel.
function C.Whisper(msgType, target, ...)
	if not target or target == "" then return false end
	local text = pack(msgType, ...)
	if #text > 240 then return false end
	SendAddonMessage(PREFIX, text, "WHISPER", target)
	return true
end

-- ------------------------------------------------------------
-- Receive: split the payload, gate on version, dispatch to the type handler.
-- The sender name is passed through un-trusted -- handlers validate by role.
-- ------------------------------------------------------------
local function onMessage(prefix, message, channel, sender)
	if prefix ~= PREFIX or not message then return end
	-- split on SEP
	local fields = {}
	for f in (message .. SEP):gmatch("(.-)" .. "%" .. SEP) do fields[#fields + 1] = f end
	if fields[1] ~= VERSION then return end          -- other/older protocol -> ignore
	local msgType = fields[2]
	local fn = msgType and handlers[msgType]
	if not fn then return end                         -- unknown type -> forward-compatible drop
	-- normalise the sender ("Name-Realm" -> "Name" for same-realm compares)
	local who = sender and sender:gsub("%-.*$", "") or ""
	-- hand the remaining fields (3..n) to the handler as varargs
	fn(who, unpack(fields, 3))
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
	onMessage(prefix, message, channel, sender)
end)

-- ------------------------------------------------------------
-- Small shared helper other modules reuse: run fn() ONCE after `delay` seconds.
-- 3.3.5a has no C_Timer, and the ML flip needs two SetLootMethod calls on
-- SEPARATE frames -- so we expose a tiny one-shot timer on the Comms frame.
-- ------------------------------------------------------------
local pending = {}   -- { {at=GetTime()+delay, fn=fn}, ... }
function C.After(delay, fn)
	if type(fn) ~= "function" then return end
	pending[#pending + 1] = { at = (GetTime() or 0) + (delay or 0), fn = fn }
	ev:Show()
end
ev:SetScript("OnUpdate", function(self)
	if #pending == 0 then self:Hide(); return end
	local now = GetTime() or 0
	for i = #pending, 1, -1 do
		if now >= pending[i].at then
			local fn = pending[i].fn
			table.remove(pending, i)
			-- pcall so one bad callback can't wedge the timer loop. Report the
			-- failure to the dev tab instead of dropping it -- a timer that dies
			-- silently is exactly the kind of bug that takes a raid to find.
			local ok, err = pcall(fn)
			if not ok and Okanvil.Err then Okanvil:Err("Comms.After callback", err) end
		end
	end
end)
ev:Hide()   -- OnUpdate only runs while timers are pending

-- ------------------------------------------------------------
-- VERSION CHECK (RCLootCouncil-style). Ask everyone in the group which Okanvil
-- they run, so a stale client can be spotted before it causes "phantom" bugs
-- (e.g. an old build that showed the ML layout to plain raiders).
--
--   VERQ            -> broadcast "who's out there?"
--   VERR|<version>  -> whispered straight back to whoever asked
--
-- Anyone who does NOT reply within the timeout either has no Okanvil or a build
-- too old to answer -- both are reported as "no reply".
-- Note: replies only arrive from clients on the SAME protocol tag (OKV1); a
-- client on a future/breaking protocol is invisible here by design.
-- ------------------------------------------------------------
local verReplies = {}      -- name -> version string
local verRunning = false
C.VersionReplies = function() return verReplies end
C.VersionCheckRunning = function() return verRunning end

-- ------------------------------------------------------------
-- Semantic version compare. "1.10.0" > "1.9.0" -- a plain string compare gets
-- that backwards, which is why we split on dots and compare numerically.
-- Anything non-numeric (a "-dev+sha" suffix from a main build) is ignored, so a
-- dev build of 1.2.0 never claims to be newer than the 1.2.0 release.
-- Returns 1 (a>b), -1 (a<b) or 0.
-- ------------------------------------------------------------
local function verParts(v)
	-- take only the leading X.Y.Z; a package.yml dev build is "1.2.0-dev+ab12cd"
	-- and those trailing digits must NOT make it look newer than the 1.2.0 release.
	local core = tostring(v or ""):match("^%s*([%d%.]+)") or ""
	local out = {}
	for n in core:gmatch("(%d+)") do out[#out + 1] = tonumber(n) end
	return out
end
local function verCmp(a, b)
	local pa, pb = verParts(a), verParts(b)
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x > y and 1 or -1 end
	end
	return 0
end
C.CompareVersions = verCmp

-- ------------------------------------------------------------
-- UPDATE NAG. Peer-to-peer, because a 3.3.5a addon cannot make HTTP requests:
-- clients announce their version on joining a group, and a client running an
-- OLDER build learns a new one exists from whoever already updated.
--
-- Anti-abuse (straight from DBM's HandleVersion): one player can lie about
-- their version, so we only nag once TWO DIFFERENT people report the same
-- higher version. A single troll can't make the raid see "update me".
-- We also cap how far ahead a claimed version may be, so "999.0.0" is ignored.
-- ------------------------------------------------------------
local newerSeen = {}         -- version string -> { [name]=true }
local nagged = false         -- only nag once per session/group
local MAX_MAJOR_JUMP = 5     -- a claim more than this many majors ahead is a lie

local function plausible(ver)
	local mineMaj = (verParts(Okanvil.version)[1]) or 0
	local theirMaj = (verParts(ver)[1]) or 0
	return theirMaj <= mineMaj + MAX_MAJOR_JUMP
end

-- called for every version we learn about (from VERR or the join broadcast)
local function noteVersion(sender, ver)
	if not (sender and ver and ver ~= "" and ver ~= "?") then return end
	if nagged then return end
	if verCmp(ver, Okanvil.version or "0") <= 0 then return end   -- not newer
	if not plausible(ver) then return end                          -- anti-abuse
	local me = UnitName and UnitName("player")
	if sender == me then return end

	newerSeen[ver] = newerSeen[ver] or {}
	newerSeen[ver][sender] = true
	local n = 0
	for _ in pairs(newerSeen[ver]) do n = n + 1 end
	-- DBM waits for 2 independent reports before believing the claim
	if n >= 2 then
		nagged = true
		if C.onNewerVersion then C.onNewerVersion(ver) end
	end
end

-- someone asked -> whisper our version straight back
C.On("VERQ", function(sender)
	if not sender or sender == "" then return end
	C.Whisper("VERR", sender, tostring(Okanvil.version or "?"))
end)

-- a reply came in -> record it and let the UI repaint
C.On("VERR", function(sender, ver)
	if not sender or sender == "" then return end
	verReplies[sender] = (ver ~= nil and ver ~= "") and tostring(ver) or "?"
	noteVersion(sender, ver)
	if C.onVersionReply then C.onVersionReply() end
end)

-- unsolicited "here I am" broadcast, sent on joining a group. Feeds the same
-- nag logic, so you learn about a new build without pressing any button.
C.On("VERB", function(sender, ver)
	if not sender or sender == "" then return end
	verReplies[sender] = (ver ~= nil and ver ~= "") and tostring(ver) or "?"
	noteVersion(sender, ver)
end)

-- Announce our version to the group (throttled: joining a raid fires several
-- roster events in a row, and we must not spam the addon channel).
local lastAnnounce = 0
function C.AnnounceVersion()
	local now = GetTime and GetTime() or 0
	if now - lastAnnounce < 20 then return end
	lastAnnounce = now
	C.Send("VERB", tostring(Okanvil.version or "?"))
end

-- Announce on joining a group, and re-arm the nag when the group changes so a
-- fresh raid can still tell you you're behind (DBM wipes its list the same way).
local vev = CreateFrame("Frame")
vev:RegisterEvent("PLAYER_ENTERING_WORLD")
vev:RegisterEvent("RAID_ROSTER_UPDATE")
vev:RegisterEvent("PARTY_MEMBERS_CHANGED")
local wasGrouped = false
vev:SetScript("OnEvent", function()
	local grouped = groupChannel() ~= nil
	if grouped and not wasGrouped then
		wipe(newerSeen); nagged = false        -- new group -> allow one nag again
	end
	wasGrouped = grouped
	if grouped then C.AnnounceVersion() end
end)

-- Kick off a check. `onDone(replies)` fires after `timeout` seconds (default 5).
-- Returns false when solo (nothing to ask).
function C.RequestVersions(onDone, timeout)
	if verRunning then return false end
	local chan = groupChannel()
	if not chan then return false end        -- solo: nobody to ask
	wipe(verReplies)
	-- count ourselves immediately; we never whisper ourselves
	local me = UnitName and UnitName("player")
	if me then verReplies[me] = tostring(Okanvil.version or "?") end
	verRunning = true
	C.Send("VERQ")
	C.After(timeout or 5, function()
		verRunning = false
		if C.onVersionReply then C.onVersionReply() end
		if type(onDone) == "function" then onDone(verReplies) end
	end)
	return true
end

-- Everyone in the current group (raid or party), for "who didn't reply".
function C.GroupRoster()
	local out = {}
	local nRaid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	if nRaid > 0 then
		for i = 1, nRaid do
			local n = GetRaidRosterInfo and GetRaidRosterInfo(i)
			if n then out[#out + 1] = (n:gsub("%-.*$", "")) end
		end
		return out
	end
	local nParty = (GetNumPartyMembers and GetNumPartyMembers()) or 0
	local me = UnitName and UnitName("player")
	if me then out[#out + 1] = me end
	for i = 1, nParty do
		local n = UnitName and UnitName("party" .. i)
		if n then out[#out + 1] = (n:gsub("%-.*$", "")) end
	end
	return out
end
