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
-- VERSION CHECK (RCLootCouncil-style). Ask the group OR the guild which Okanvil
-- everyone runs, so a stale client can be spotted before it causes "phantom"
-- bugs (e.g. an old build that showed the ML layout to plain raiders).
--
--   VERQ            -> broadcast "who's out there?" (RAID/PARTY or GUILD)
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

-- someone asked -> whisper our version straight back
C.On("VERQ", function(sender)
	if not sender or sender == "" then return end
	C.Whisper("VERR", sender, tostring(Okanvil.version or "?"))
end)

-- a reply came in -> record it and let the UI repaint
C.On("VERR", function(sender, ver)
	if not sender or sender == "" then return end
	verReplies[sender] = (ver ~= nil and ver ~= "") and tostring(ver) or "?"
	if C.onVersionReply then C.onVersionReply() end
end)

-- Kick off a check. `scope` is "group" (default) or "guild"; `onDone(replies)`
-- fires after `timeout` seconds (default 5). Returns false when there is nobody
-- to ask (solo for "group", unguilded for "guild").
function C.RequestVersions(scope, onDone, timeout)
	-- old call shape was (onDone, timeout) -- keep it working
	if type(scope) == "function" then scope, onDone, timeout = "group", scope, onDone end
	if verRunning then return false end
	local chan
	if scope == "guild" then
		chan = (IsInGuild and IsInGuild()) and "GUILD" or nil
	else
		chan = groupChannel()
	end
	if not chan then return false end        -- nobody to ask
	wipe(verReplies)
	-- count ourselves immediately; we never whisper ourselves
	local me = UnitName and UnitName("player")
	if me then verReplies[me] = tostring(Okanvil.version or "?") end
	verRunning = true
	SendAddonMessage(PREFIX, pack("VERQ"), chan)
	C.After(timeout or 5, function()
		verRunning = false
		if C.onVersionReply then C.onVersionReply() end
		if type(onDone) == "function" then onDone(verReplies) end
	end)
	return true
end

-- Everyone we asked, for "who didn't reply". scope mirrors RequestVersions:
-- "group" = current raid/party, "guild" = ONLINE guild members (offline ones
-- can't answer, so listing them as "no reply" would just be noise).
function C.GroupRoster(scope)
	local out = {}
	if scope == "guild" then
		if not (IsInGuild and IsInGuild()) then return out end
		if GuildRoster then GuildRoster() end     -- ask for a refresh; list may be a few seconds stale
		local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
		for i = 1, n do
			local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
			if name and online then out[#out + 1] = (name:gsub("%-.*$", "")) end
		end
		return out
	end
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
