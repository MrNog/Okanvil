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

-- The other half. Needed since big payloads carry raid notes, which are full of
-- '|' in their colour codes -- without putting them back the text arrives
-- mangled, or split across fields that were never meant to be separate.
local function decField(s)
	return (tostring(s or ""):gsub("/", "|"))
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

-- Send to the GUILD channel rather than the current group. Most Okanvil traffic
-- is about the group you are in, but some of it is about the guild and has to
-- reach officers who are not standing next to you -- the recruit message is the
-- first. Returns false when you are not in a guild.
function C.SendGuild(msgType, ...)
	if not (IsInGuild and IsInGuild()) then return false end
	local text = pack(msgType, ...)
	if #text > 240 then return false end
	SendAddonMessage(PREFIX, text, "GUILD")
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
	local text = pack(msgType, ...)
	if #text > 240 then return false end
	SendAddonMessage(PREFIX, text, "WHISPER", target)
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
_G.SlashCmdList["OKCOMMS"] = function()
	C.debug = not C.debug
	Okanvil:Print("Comms debug " .. (C.debug and "|cff7cfc8aON|r" or "|cffff5555OFF|r"))
end

local function onMessage(prefix, message, channel, sender)
	if prefix ~= PREFIX or not message then return end
	if C.debug then
		Okanvil:Print(("|cff6f7176<- %s [%s] %s|r"):format(
			tostring(sender), tostring(channel), tostring(message):sub(1, 60)))
	end
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
-- BIG PAYLOADS (chunked send/receive)
--
-- One addon message caps out around 255 bytes and shares the player's chat
-- throttle, so anything larger goes out as a numbered series and is rebuilt on
-- the far side. The loot priority list is ~4KB, about 20 messages.
--
--   BIG|<tag>|<id>|<seq>|<total>|<chunk>
--
-- `id` distinguishes two transfers of the same tag crossing over. A partial
-- transfer is dropped after BIG_TIMEOUT rather than kept forever: the sender may
-- have logged out mid-send, and half a priority list is worse than none.
-- Whatever arrives is still only DATA -- the receiving handler decides whether
-- the sender was allowed to send it.
-- ------------------------------------------------------------
local BIG_CHUNK   = 180        -- payload bytes per message, well under the cap
local BIG_GAP     = 0.35       -- seconds between sends: stay under the chat throttle
local BIG_TIMEOUT = 60         -- give up on a half-finished transfer after this
local bigIn  = {}              -- sender.."\0"..tag -> { id, total, parts, at }
local bigHandlers = {}         -- tag -> fn(sender, text)
local bigSeq = 0

-- Register the handler for a chunked payload. fn(sender, wholeText) runs once the
-- series is complete.
function C.OnBig(tag, fn) bigHandlers[tag] = fn end

-- Send a large string as a numbered series. Returns the number of chunks, or
-- false when there is nobody to send to.
function C.SendBig(tag, text, chan, target)
	text = tostring(text or "")
	if text == "" then return false end
	if not chan then
		if GetNumRaidMembers and GetNumRaidMembers() > 0 then chan = "RAID"
		elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then chan = "PARTY"
		else return false end
	end
	bigSeq = bigSeq + 1
	local id = tostring((time and time() or 0) % 100000) .. "-" .. bigSeq
	local total = math.ceil(#text / BIG_CHUNK)
	for i = 1, total do
		local part = text:sub((i - 1) * BIG_CHUNK + 1, i * BIG_CHUNK)
		-- spread the series over time: firing 20 messages in one frame trips the
		-- client's own throttle and the tail is silently dropped.
		C.After(BIG_GAP * (i - 1), function()
			-- The PART is escaped too, not just the tag and id.
			--
			-- It used to go on the wire raw, which worked for as long as the only
			-- payload was the loot list. A raid note is full of '|' -- every
			-- colour code is |cff......|r -- and the receiver splits on exactly
			-- that character, so the note shattered into fragments and only the
			-- piece before the first colour survived.
			local body = table.concat({ VERSION, "BIG", encField(tag), encField(id), i, total, encField(part) }, SEP)
			if target then SendAddonMessage(PREFIX, body, chan, target)
			else SendAddonMessage(PREFIX, body, chan) end
		end)
	end
	return total
end

C.On("BIG", function(sender, tag, id, seq, total, part)
	if not tag or not id then return end
	seq, total = tonumber(seq), tonumber(total)
	if not seq or not total or seq < 1 or total < 1 then return end
	local key = (sender or "") .. "\0" .. tag
	local slot = bigIn[key]
	-- a different id for the same tag means a newer transfer: start over rather
	-- than interleaving two lists into one corrupt blob
	if not slot or slot.id ~= id then
		slot = { id = id, total = total, parts = {}, at = GetTime() or 0 }
		bigIn[key] = slot
	end
	slot.parts[seq] = decField(part or "")
	slot.at = GetTime() or 0
	for i = 1, total do if slot.parts[i] == nil then return end end   -- still incomplete
	bigIn[key] = nil
	local fn = bigHandlers[tag]
	if not fn then return end
	local ok, err = pcall(fn, sender, table.concat(slot.parts))
	if not ok and Okanvil.Err then Okanvil:Err("Comms.OnBig " .. tostring(tag), err) end
end)

-- Sweep abandoned transfers so a sender who logged out mid-series cannot pin
-- their partial payload in memory for the rest of the session.
do
	local sweep = CreateFrame("Frame")
	local acc = 0
	sweep:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 10 then return end
		acc = 0
		local now = GetTime() or 0
		for k, v in pairs(bigIn) do
			if now - (v.at or 0) > BIG_TIMEOUT then bigIn[k] = nil end
		end
	end)
end

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
-- SIZE: this goes through C.Send, which silently refuses anything over 240
-- bytes. A question is expected to be small (an item link and a flag). Anything
-- carrying a LIST must go out with C.SendBig under its own tag and use Ask only
-- to announce it.
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
	C.Whisper("ANS", sender, topic, round, tostring(reply))
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
