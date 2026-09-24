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
--   * prefix + text must stay under ~255 bytes and shares the chat throttle.
--
-- TRANSPORT: AceComm-3.0 over ChatThrottleLib, the same pair RCLootCouncil uses.
-- ChatThrottleLib queues every message under the server's rate limit instead of
-- letting a burst (a council question, its answers and a priority list, all in
-- the same second) be dropped with no error; AceComm splits anything longer
-- than one message and rebuilds it on the far side. Messages are still
-- fire-and-forget: pair a PUSH with a FETCH/ACK.
--
-- ENCODING, also RCLootCouncil's: every message is compressed with LibDeflate
-- and sent through EncodeForPrint. Compression is what makes a raid note or the
-- priority list a handful of messages instead of dozens; EncodeForPrint is
-- needed because deflate output is binary, and an addon message cannot carry
-- every byte (a \0 ends it).
--
-- WIRE FORMAT (versioned so mismatched clients ignore what they don't know):
--     OKV2|<TYPE>|<arg1>|<arg2>|...
--   Fields are '|'-separated; a leading "OKV2" gates the protocol version.
--   OKV1 was the same format sent uncompressed: the two cannot read each other,
--   so an OKV1 client shows up as "no reply" in the version check.
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
local VERSION = "OKV2"      -- payload version tag; bump only on a breaking change
local SEP     = "|"

-- registered message handlers: TYPE -> fn(sender, ...args). Modules add theirs
-- with C.On("MLFIX", handler). Kept load-order safe: a module can register
-- before or after Comms loads, as long as Comms loads first in the .toc (it does).
local handlers = {}

-- The AceComm endpoint. A private table rather than embedding into C, so its
-- mixin names (SendCommMessage, RegisterComm...) never collide with ours.
local AceComm = LibStub and LibStub("AceComm-3.0", true)
local endpoint = AceComm and AceComm:Embed({}) or nil
local Deflate = LibStub and LibStub("LibDeflate", true)

local function encode(text)
	if not Deflate then return text end
	local packed = Deflate:CompressDeflate(text)
	return packed and Deflate:EncodeForPrint(packed) or text
end

-- Anything that does not decode is handed back unchanged: the raw pings, and an
-- OKV1 client's uncompressed text (which then simply fails the version gate).
local function decode(msg)
	if not Deflate then return msg end
	local packed = Deflate:DecodeForPrint(msg)
	local text = packed and Deflate:DecompressDeflate(packed)
	return text or msg
end

-- Every message in and out goes into the always-on trace (Okanvil:Trace). The
-- preview is the plain text before compression, cut short, with control bytes
-- (the field escape, the notes' record marks) shown as '~' so a line stays one
-- readable line in the saved file.
local TRACE_PREVIEW = 120
local function preview(text)
	return (tostring(text or ""):sub(1, TRACE_PREVIEW):gsub("%c", "~"))
end

local function msgTypeOf(text)
	return tostring(text or ""):match("^[^|]*|([^|]*)") or "?"
end

local function trace(line)
	if Okanvil.Trace then Okanvil:Trace("COMMS", line) end
end

-- Put one Okanvil string on the wire. prio is ChatThrottleLib's: "ALERT",
-- "NORMAL" (default) or "BULK" -- bulk transfers use BULK so a question or an
-- answer is never stuck in the queue behind the parts of a list.
-- Returns the encoded length, which is what the wire actually carries.
local function wire(text, chan, target, prio)
	local plain = text
	text = encode(text)
	trace(("-> %s%s %s %db/%db %s"):format(chan, target and (" " .. target) or "",
		msgTypeOf(plain), #plain, #text, preview(plain)))
	if endpoint then
		endpoint:SendCommMessage(PREFIX, text, chan, target, prio or "NORMAL")
	elseif target then
		SendAddonMessage(PREFIX, text, chan, target)
	else
		SendAddonMessage(PREFIX, text, chan)
	end
	return #text
end

-- ------------------------------------------------------------
-- Field escaping. '|' is our separator, and raid notes and item links are full
-- of it, so inside a field it travels as \031 and is put back on arrival. A
-- control character rather than a printable one: the old '/' stand-in turned
-- every real '/' in a note ("Okanor/Zhong") into '|' on the far side. The
-- whole message is encoded before it reaches the wire, so \031 never does.
-- ------------------------------------------------------------
local FIELD_ESC = "\031"

local function encField(s)
	return (tostring(s == nil and "" or s):gsub("|", FIELD_ESC))
end

local function decField(s)
	return (tostring(s or ""):gsub(FIELD_ESC, "|"))
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
	wire(pack(msgType, ...), chan)
	return true
end

-- Send to the GUILD channel rather than the current group. Most Okanvil traffic
-- is about the group you are in, but some of it is about the guild and has to
-- reach officers who are not standing next to you -- the recruit message is the
-- first. Returns false when you are not in a guild.
function C.SendGuild(msgType, ...)
	if not (IsInGuild and IsInGuild()) then return false end
	wire(pack(msgType, ...), "GUILD")
	return true
end

-- Whisper a typed message straight to one player (for targeted ACKs). target is
-- a unit name. Works even when the recipient isn't in your subgroup channel.
function C.Whisper(msgType, target, ...)
	if not target or target == "" then return false end
	-- NEVER whisper ourselves. The client refuses it and the SERVER answers with a
	-- visible "Player not found." in chat -- an addon message the player was never
	-- meant to see, printed once per reply. Callers that need to answer themselves
	-- go through C.Reply, which delivers locally instead.
	local me = UnitName and UnitName("player")
	if me and target == me then return false end
	wire(pack(msgType, ...), "WHISPER", target)
	return true
end

-- ------------------------------------------------------------
-- Receive: split the payload, gate on version, dispatch to the type handler.
-- The sender name is passed through un-trusted -- handlers validate by role.
-- ------------------------------------------------------------
-- Debug: /okcomms shows every Okanvil addon message as it arrives. Off by
-- default; it is a firehose in a raid.
C.debug = false
_G.SLASH_OKCOMMS1 = "/okcomms"
-- Chat treats '|' as the start of a colour or link code, so a raw payload
-- printed as-is can come out garbled or not at all. "||" prints one '|'.
local function shown(s)
	return (tostring(s or ""):gsub("|", "||"))
end

-- /okcomms ping -- the wire itself, with nothing of ours in between. Sends two
-- raw messages straight to SendAddonMessage, one with a '|' in it and one
-- without, and a raw listener below reports every one that comes back. Your own
-- group messages echo back to you, so this works with one person: whichever
-- form does not come back is the one the server drops.
local pingSeq = 0
local function ping()
	local chan = groupChannel()
	if not chan then Okanvil:Print("Ping: you're not in a party or raid."); return end
	pingSeq = pingSeq + 1
	SendAddonMessage(PREFIX, "PING:plain:" .. pingSeq, chan)
	SendAddonMessage(PREFIX, "PING|pipe|" .. pingSeq, chan)
	Okanvil:Print(("Ping %d sent on %s -- expect two lines back: |cff7cfc8aplain|r and |cff7cfc8apipe|r."):format(pingSeq, chan))
end

do
	local raw = CreateFrame("Frame")
	raw:RegisterEvent("CHAT_MSG_ADDON")
	raw:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
		if prefix ~= PREFIX or type(message) ~= "string" or message:sub(1, 4) ~= "PING" then return end
		local kind = message:sub(5, 5) == "|" and "pipe" or "plain"
		Okanvil:Print(("|cff7cfc8aPing back:|r %s from %s [%s] %s"):format(
			kind, tostring(sender), tostring(channel), shown(message)))
	end)
end

_G.SlashCmdList["OKCOMMS"] = function(msg)
	if (msg or ""):lower():match("^%s*ping") then ping(); return end
	C.debug = not C.debug
	Okanvil:Print("Comms debug " .. (C.debug and "|cff7cfc8aON|r" or "|cffff5555OFF|r"))
end

local function onMessage(prefix, message, channel, sender)
	if prefix ~= PREFIX or not message then return end
	local wireLen = #message
	message = decode(message)
	trace(("<- %s %s %s %db/%db %s"):format(tostring(sender), tostring(channel),
		msgTypeOf(message), #message, wireLen, preview(message)))
	if C.debug then
		Okanvil:Print(("|cff6f7176<- %s [%s] %s|r"):format(
			tostring(sender), tostring(channel), shown(tostring(message):sub(1, 60))))
	end
	-- split on SEP
	local fields = {}
	for f in (message .. SEP):gmatch("(.-)" .. "%" .. SEP) do fields[#fields + 1] = f end
	if fields[1] ~= VERSION then                     -- other/older protocol -> ignore
		trace(("-- dropped: %s speaks %s, we speak %s"):format(tostring(sender),
			tostring(fields[1]):sub(1, 8), VERSION))
		return
	end
	local msgType = fields[2]
	local fn = msgType and handlers[msgType]
	if not fn then                                    -- unknown type -> forward-compatible drop
		trace("-- dropped: no handler for " .. tostring(msgType))
		return
	end
	-- normalise the sender ("Name-Realm" -> "Name" for same-realm compares)
	local who = sender and sender:gsub("%-.*$", "") or ""
	-- hand the remaining fields (3..n) to the handler as varargs
	for i = 3, #fields do fields[i] = decField(fields[i]) end
	fn(who, unpack(fields, 3))
end

local ev = CreateFrame("Frame")
if endpoint then
	-- AceComm hands over whole messages, multipart ones already reassembled.
	endpoint:RegisterComm(PREFIX, function(prefix, message, channel, sender)
		onMessage(prefix, message, channel, sender)
	end)
else
	ev:RegisterEvent("CHAT_MSG_ADDON")
	ev:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
		onMessage(prefix, message, channel, sender)
	end)
end

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
-- BIG PAYLOADS
--
-- A payload of any size goes out as ONE Okanvil message:
--
--   BIG|<tag>|<text>
--
-- The text is compressed whole, then AceComm splits the result into as many
-- addon messages as it needs and rebuilds it on the far side, in order. A raid
-- note or the ~4KB priority list compresses to a fraction of its size, so it
-- costs a handful of messages. BULK priority keeps it behind any council
-- question or answer sent at the same time.
-- Whatever arrives is still only DATA -- the receiving handler decides whether
-- the sender was allowed to send it.
-- ------------------------------------------------------------
local bigHandlers = {}         -- tag -> fn(sender, text)

-- Register the handler for a big payload. fn(sender, wholeText).
function C.OnBig(tag, fn) bigHandlers[tag] = fn end

-- Send a large string. Returns how many addon messages it took, or false when
-- there is nobody to send to. Needs AceComm: without it only one addon message
-- of ~250 bytes could go out, and a cut-off note is worse than none.
function C.SendBig(tag, text, chan, target)
	text = tostring(text or "")
	if text == "" or not endpoint then return false end
	if not chan then
		chan = groupChannel()
		if not chan then return false end
	end
	local len = wire(pack("BIG", tag, text), chan, target, "BULK")
	return math.max(1, math.ceil(len / 250))
end

C.On("BIG", function(sender, tag, text)
	local fn = tag and bigHandlers[tag]
	if not fn then return end
	local ok, err = pcall(fn, sender, text or "")
	if not ok and Okanvil.Err then Okanvil:Err("Comms.OnBig " .. tostring(tag), err) end
end)

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
	wire(pack("VERQ"), chan)
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

-- ============================================================
-- ASK / ANSWER -- broadcast a question, collect one reply per client.
--
-- This is VERQ/VERR (above) with the version string taken out: ask the group
-- something, every client answers, the caller gets the replies together after a
-- timeout. The loot council is the first user; the notes module's hand-rolled
-- NOTEWHO/NOTEACK pair is the same shape and can move onto this later.
--
-- WIRE:
--   ASK | <topic> | <round> | <payload>        broadcast to the group
--   ANS | <topic> | <round> | <payload>        whispered back to the asker
--
-- THE ROUND ID is the point of this layer. Nothing else on the Okanvil wire
-- carries session identity, so two questions on the same topic -- two bosses in
-- a row, or one re-broadcast after a dropped packet -- would pool their answers
-- into one list and the caller could not tell them apart. Every reply carries
-- the round it belongs to and anything from a round we are not running is
-- dropped. That is also what makes a RE-BROADCAST free: a client that already
-- answered answers again, and the second reply lands on the same slot.
--
-- TRUST: unchanged from the rest of this file. An answer is DATA. Ask() records
-- who said what; deciding whether that person was entitled to say it is the
-- caller's job, and the caller re-checks live game state before acting.
-- ============================================================

local askRounds   = {}   -- round id -> { topic, replies, roster, onReply, onDone, done }
local answerFns   = {}   -- topic -> fn(sender, payload) -> reply payload
local askSeq      = 0

-- Mint a round id that cannot collide with another player's. The name matters:
-- two clients both asking about the same boss within the same second would
-- otherwise generate the same id, and their answers would cross.
local function newRound()
	askSeq = askSeq + 1
	local me = (UnitName and UnitName("player")) or "?"
	return ("%s-%d-%d"):format(me, (time and time() or 0) % 100000, askSeq)
end

-- Register what THIS client replies with when someone asks about `topic`.
-- fn(sender, payload) returns the reply string (or nil to stay silent -- but
-- see the note in the council plan: silence is ambiguous, so prefer an explicit
-- "not applicable" reply over nil wherever a count depends on it).
function C.Answer(topic, fn)
	answerFns[topic] = fn
end

-- Ask the group a question.
--   topic    -- string, namespaces the question (e.g. "COUNCIL")
--   payload  -- string carried to every client (keep it SHORT; see the cap below)
--   opts     -- { timeout = 20, onReply = fn(sender, payload, replies),
--                 onDone = fn(replies, round) }
-- Returns the round id, or false when there is nobody to ask.
--
-- SIZE: keep a question small (an item link and a flag). AceComm would split a
-- long one, but every chunk then has to arrive before anyone can answer. Anything
-- carrying a LIST goes out with C.SendBig under its own tag and uses Ask only to
-- announce it.
function C.Ask(topic, payload, opts)
	opts = opts or {}
	local round = newRound()
	local rec = {
		topic   = topic,
		replies = {},                 -- sender -> payload
		count   = 0,
		onReply = opts.onReply,
		onDone  = opts.onDone,
		roster  = C.GroupRoster("group"),
	}
	askRounds[round] = rec

	local sent = C.Send("ASK", topic, round, payload or "")

	-- SOLO LOOPBACK. C.Send no-ops when we are not in a group, which would make
	-- the whole feature untestable without a second person online -- and this
	-- addon's wire bugs are exactly the ones that only show up at raid time.
	-- So when there is no channel we hand the question to our OWN answer handler
	-- on the next frame.
	--
	-- Only the SEND is skipped; the answer handler, the round bookkeeping and the
	-- timeout are the same code the group path runs. Nothing downstream of the
	-- send can tell the difference, which is what makes the test worth anything.
	if not sent then
		local me = (UnitName and UnitName("player")) or "?"
		C.After(0, function()
			local fn = answerFns[topic]
			if not fn then return end
			-- Same signature as the wire path, round included: a handler that
			-- answers late must behave identically solo, or the test proves nothing.
			local ok, reply = pcall(fn, me, payload or "", round)
			if ok and reply ~= nil then C.DeliverAnswer(me, topic, round, tostring(reply)) end
		end)
	end

	C.After(opts.timeout or 20, function()
		local r = askRounds[round]
		if not r or r.done then return end
		r.done = true
		askRounds[round] = nil
		if type(r.onDone) == "function" then
			local ok, err = pcall(r.onDone, r.replies, round)
			if not ok and Okanvil.Err then Okanvil:Err("Comms.Ask onDone " .. tostring(topic), err) end
		end
	end)

	return round
end

-- Record one answer against an open round. Exposed (rather than local) so the
-- loopback path above and the wire handler below share ONE code path -- if this
-- ever diverges, solo testing stops proving anything about a real raid.
function C.DeliverAnswer(sender, topic, round, payload)
	local rec = askRounds[round]
	if not rec or rec.topic ~= topic then return end   -- stale/unknown round -> drop
	if rec.replies[sender] == nil then rec.count = rec.count + 1 end
	rec.replies[sender] = payload or ""
	if type(rec.onReply) == "function" then
		local ok, err = pcall(rec.onReply, sender, payload, rec.replies)
		if not ok and Okanvil.Err then Okanvil:Err("Comms.Ask onReply " .. tostring(topic), err) end
	end
end

-- Someone asked us something -> run our handler and whisper the reply back.
--
-- The handler is called as fn(sender, payload, round). Most answers are a pure
-- function of the question and ignore `round`, but a handler that answers OVER
-- TIME -- the loot council frame, which replies as the raider clicks -- needs it
-- to whisper back later. Returning nil means "not yet, I will send my own"; the
-- round is the only way to address that reply to the right question.
C.On("ASK", function(sender, topic, round, payload)
	if not sender or sender == "" or not topic or not round then return end
	local fn = answerFns[topic]
	if not fn then return end                       -- we have nothing to say on this topic
	local ok, reply = pcall(fn, sender, payload or "", round)
	if not ok then
		if Okanvil.Err then Okanvil:Err("Comms.Answer " .. tostring(topic), reply) end
		return
	end
	if reply == nil then return end                 -- handler will answer later, or chose silence
	-- C.Reply, not C.Whisper: the asker hears their own broadcast too, and a
	-- whisper to yourself is dropped -- their own "can't use it" never landed.
	C.Reply(sender, topic, round, reply)
end)

-- Send a late answer to a question asked earlier. The counterpart to a handler
-- that returned nil: the round id is what pairs it with the right question, so a
-- reply arriving after the next boss cannot land on that boss's round.
--
-- ANSWERING YOURSELF. The client does NOT deliver an addon whisper addressed to
-- the sender -- it is dropped with no error. That matters well beyond testing:
-- the master looter is usually IN the raid and eligible for the item, so their
-- own answer would silently never reach their own board. Short-circuit straight
-- into the round instead of going near the wire.
function C.Reply(asker, topic, round, payload)
	if not (asker and topic and round) then return false end
	local me = UnitName and UnitName("player")
	if me and asker == me then
		C.DeliverAnswer(me, topic, round, tostring(payload or ""))
		return true
	end
	return C.Whisper("ANS", asker, topic, round, tostring(payload or ""))
end

-- A reply came back.
C.On("ANS", function(sender, topic, round, payload)
	if not sender or sender == "" or not round then return end
	C.DeliverAnswer(sender, topic, round, payload)
end)

-- Close a round early -- every expected answer is in, or the caller gave up.
-- Fires onDone exactly once (the timeout then finds it gone and does nothing).
function C.CloseAsk(round)
	local rec = askRounds[round]
	if not rec or rec.done then return false end
	rec.done = true
	askRounds[round] = nil
	if type(rec.onDone) == "function" then
		local ok, err = pcall(rec.onDone, rec.replies, round)
		if not ok and Okanvil.Err then Okanvil:Err("Comms.Ask onDone " .. tostring(rec.topic), err) end
	end
	return true
end

-- Re-send an open question to the group. The plan's stage 2b calls for this on a
-- timer: an addon message can be dropped with no error and no retry, so one lost
-- packet must not cost the round. Clients that already answered land on the same
-- reply slot, so this is safe to call repeatedly.
function C.ReAsk(round, payload)
	local rec = askRounds[round]
	if not rec or rec.done then return false end
	return C.Send("ASK", rec.topic, round, payload or "")
end

-- Re-open collection on a round that was started BEFORE a reload. The round id
-- already exists on every other client and answers are still coming back, but
-- this client has forgotten it -- without adopting it those replies are dropped
-- as an unknown round and the leader's board stays empty for ever.
--
-- Same shape as C.Ask minus the broadcast: the question is already out there.
function C.Adopt(topic, round, opts)
	if not (topic and round) then return false end
	if askRounds[round] then return true end       -- already collecting
	opts = opts or {}
	askRounds[round] = {
		topic   = topic,
		replies = {},
		count   = 0,
		onReply = opts.onReply,
		onDone  = opts.onDone,
		roster  = C.GroupRoster("group"),
	}
	C.After(opts.timeout or 20, function()
		local r = askRounds[round]
		if not r or r.done then return end
		r.done = true
		askRounds[round] = nil
		if type(r.onDone) == "function" then
			local ok, err = pcall(r.onDone, r.replies, round)
			if not ok and Okanvil.Err then Okanvil:Err("Comms.Adopt onDone " .. tostring(topic), err) end
		end
	end)
	return true
end

-- Is this round still collecting?  (for a UI that draws "4 of 5")
function C.AskStatus(round)
	local rec = askRounds[round]
	if not rec then return nil end
	return rec.count, rec.replies, rec.roster
end
