-- ============================================================
-- Okanvil -- Notes: sharing between officers.
--
-- Same shape as the loot-priority sync in LootPrio.lua, for the same reason:
-- two officers each editing their own copy is how a raid ends up running off
-- yesterday's plan.
--
--   NOTEV  "I hold notes stamped <t>"      broadcast, cheap
--   NOTEQ  "send me yours"                 whisper
--   NOTES  the notes themselves            whisper, chunked
--
-- Newest wins, by an edit stamp per note. Officer-gated in both directions:
-- the sender is checked against the live guild roster, not taken on faith from
-- a name off the wire.
-- ============================================================

local N = Okanvil.Notes
local Comms = Okanvil.Comms

local function db() return N and N.db or nil end

-- ------------------------------------------------------------
-- The last Send, so the page can show how it went.
--
-- Pressing Send only proves the messages left this client. What it does NOT
-- prove is that anybody got them -- so the confirmations are counted as they
-- come back, and the header shows both numbers.
--
-- Declared up here because SendNow writes it and the NOTEACK handler reads it,
-- and those sit on opposite sides of the file.
-- ------------------------------------------------------------
local lastSend = nil     -- { at =, notes =, chunks =, chan =, got = {} }

-- How the last send went: sentNotes, confirmedPeople, secondsAgo -- or nil.
function N.LastSend()
	if not lastSend then return nil end
	local got = 0
	for _ in pairs(lastSend.got) do got = got + 1 end
	return lastSend.notes, got, math.floor((GetTime() or 0) - lastSend.at)
end

-- ------------------------------------------------------------
-- Who may share
-- ------------------------------------------------------------
-- Returns false plus a reason, so a failed send can say WHY instead of doing
-- nothing. Every send and every accept runs through here, so one check covers
-- the lot -- and one explanation covers them too.
local function syncAllowed()
	if Okanvil.ModuleActive and not Okanvil:ModuleActive("Okanvil-Notes") then
		return false, "the Notes module is off"
	end
	local d = db()
	if not d then return false, "no saved settings yet" end
	if d.share == false then return false, "sharing is switched off in Notes settings" end

	local me = UnitName("player") or ""
	if Okanvil.U and Okanvil.U.isOfficer and Okanvil.U.isOfficer(me) then return true end

	-- Leading the group is authority enough.
	--
	-- The officer check reads the guild roster, which is empty for a few seconds
	-- after a /reload and stays empty in a group of non-guildies -- so the person
	-- who called the raid could press Send and have nothing happen, with no way
	-- to tell that from the sync being broken.
	if IsPartyLeader and IsPartyLeader() then return true end
	if IsRaidLeader and IsRaidLeader() then return true end

	if GuildRoster then GuildRoster() end     -- warm it for the next attempt
	return false, "you are not an officer and not leading the group"
end

-- Who we accept notes FROM.
--
-- Wider than who may send: an officer, or whoever is leading this group. The
-- raid leader is who calls the pull, so their plan is the one that matters, and
-- gating on the guild roster alone locked out a leader who was not an officer
-- -- or one whose roster had not loaded yet.
--
-- Being trusted only earns a sender the right to be CONSIDERED. Nothing of
-- yours is replaced without you saying so; see merge.
local function senderTrusted(who)
	if not (who and who ~= "") then return false end
	if Okanvil.U and Okanvil.U.isOfficer and Okanvil.U.isOfficer(who) then return true end

	local n = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	if n > 0 then
		for i = 1, n do
			local name, rank = GetRaidRosterInfo(i)
			if name and name:gsub("%-.*$", "") == who then return (rank or 0) >= 1 end
		end
		return false
	end
	if (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0 then
		local leader = nil
		for i = 1, GetNumPartyMembers() do
			if UnitIsPartyLeader and UnitIsPartyLeader("party" .. i) then
				leader = UnitName("party" .. i)
				break
			end
		end
		return leader ~= nil and leader == who
	end
	return false
end

-- ------------------------------------------------------------
-- Stamps
--
-- One timestamp per note, set when you edit it. The highest of them is what
-- gets announced, so "who is newer" is a single number comparison and a raid
-- that has not changed anything sends nothing.
-- ------------------------------------------------------------
function N.Touch(name)
	local d = db()
	if not (d and name) then return end
	d.stamps = d.stamps or {}
	d.stamps[name] = time()
end

function N.Stamp()
	local d = db()
	if not d or not d.stamps then return 0 end
	local hi = 0
	for _, t in pairs(d.stamps) do if t > hi then hi = t end end
	return hi
end

-- ------------------------------------------------------------
-- Wire format
--
-- Deliberately not a serialiser: a note is already text, and the only thing
-- that cannot appear inside one is a line we choose. Records are
--   \1 name \1 stamp \1 text
-- which survives the chunking in Comms and is trivially readable in a log.
-- ------------------------------------------------------------
local SEP = "\1"

-- What goes on the wire: your edited notes, each with its stamp.
--
-- The shipped notes are NOT sent. Both ends run Okanvil, so both already have
-- the same pack, and putting it on the wire only makes every send longer for a
-- result that was already there.
--
-- `withPack` survives for the one case that still needs it: a receiver whose
-- pack is older than yours, where a shipped note you never touched would
-- otherwise read as missing on their side.
-- The role slots travel WITH the notes, as one more record.
--
-- Without them a raider received "{Holy1}" where a name belongs and had to type
-- the roster in by hand, spelled exactly as the officer spelled it -- so one
-- "Solanarage" for "Solanarrage" left that person's lines naming nobody, which
-- looks identical to a note that failed to load.
--
-- The name is a slot the note format cannot produce: it starts with a character
-- no boss name contains, so an older client's decode skips the record instead of
-- storing a note called "slots".
local SLOTREC = "\2slots"

local function encodeSlots(d)
	local parts = {}
	for slot, who in pairs(d.slots or {}) do
		if type(slot) == "string" and type(who) == "string" and who ~= "" then
			parts[#parts + 1] = slot .. "=" .. who
		end
	end
	if #parts == 0 then return nil end
	table.sort(parts)      -- stable payload: same roster encodes the same way
	return table.concat(parts, ",")
end

local function encode(withPack)
	local d = db()
	if not d then return "" end

	local seen, out = {}, {}
	for name, text in pairs(d.notes or {}) do
		if text and text ~= "" then
			local stamp = (d.stamps and d.stamps[name]) or 0
			out[#out + 1] = SEP .. name .. SEP .. stamp .. SEP .. text
			seen[name] = true
		end
	end

	-- Stamped like a note so the same "newer wins" rule covers the roster, and a
	-- resend of an unchanged roster changes nothing on the far side.
	local slots = encodeSlots(d)
	if slots then
		out[#out + 1] = SEP .. SLOTREC .. SEP .. (d.slotStamp or 0) .. SEP .. slots
	end

	if withPack and Okanvil.NotesPack then
		for name, text in pairs(Okanvil.NotesPack) do
			if not seen[name] and text and text ~= "" then
				-- Stamp 1, not 0: the receiver only accepts a stamp HIGHER than
				-- what it holds, and an unseen note is held at 0.
				out[#out + 1] = SEP .. name .. SEP .. 1 .. SEP .. text
			end
		end
	end

	return table.concat(out, "\n")
end

-- Returns a list of { name, stamp, text }, or nil when the payload is not ours.
local function decode(raw)
	if not raw or raw == "" then return nil end
	local out = {}
	-- Split on the record marker rather than newlines: a note is multi-line, so
	-- line-splitting would cut one note into several.
	for name, stamp, text in raw:gmatch(SEP .. "([^" .. SEP .. "]+)" .. SEP .. "(%d+)" .. SEP .. "([^" .. SEP .. "]*)") do
		out[#out + 1] = { name = name, stamp = tonumber(stamp) or 0, text = text }
	end
	return (#out > 0) and out or nil
end

-- ------------------------------------------------------------
-- Merge
--
-- Per note, not wholesale: two officers can each have edited a different boss
-- and both edits should survive. Only a strictly newer stamp wins, so a repeat
-- of the same payload changes nothing.
-- ------------------------------------------------------------
-- Take what is safe to take, and ASK about the rest.
--
-- A note you wrote is work. The old merge replaced it the moment a higher stamp
-- arrived, so a raider who opened someone else's pack could wipe a boss plan
-- typed minutes before a pull, silently, with no way back. "Newest wins" is
-- fine between two people editing the same plan; it is not fine when the thing
-- being overwritten is something only you have.
--
-- So: a note you do not have yet is simply taken -- there is nothing to lose.
-- A note you DO have, with your own text in it, is queued and confirmed one by
-- one. Answering No keeps yours and leaves your stamp alone, so the same pack
-- arriving again asks again rather than sneaking past.
local pendingAsk = nil      -- queue of { name =, text =, stamp =, who = }

local function askNext()
	local q = pendingAsk
	if not q or #q == 0 then pendingAsk = nil return end
	local rec = table.remove(q, 1)

	local d = db()
	if not d then pendingAsk = nil return end
	-- It may have been settled while this one waited in line.
	if (d.stamps[rec.name] or 0) >= rec.stamp then return askNext() end

	Okanvil:Confirm(
		("|cffe0b860%s|r sent a note for |cffffd200%s|r.\n\nYou already have one. Replace yours?")
			:format(rec.who, rec.name),
		"Replace",
		function()
			d.notes[rec.name] = rec.text
			d.stamps[rec.name] = rec.stamp
			Okanvil:Print(("Replaced your |cffffd200%s|r note with %s's."):format(rec.name, rec.who))
			if N.Broadcast then N.Broadcast() end
			if N.Refresh then N.Refresh() end
			askNext()
		end,
		function()
			Okanvil:Print(("Kept your |cffffd200%s|r note."):format(rec.name))
			askNext()
		end)
end

local function merge(list, who)
	local d = db()
	if not (d and list) then return 0 end
	d.stamps = d.stamps or {}
	d.notes = d.notes or {}
	local n, ask = 0, {}
	for _, rec in ipairs(list) do
		if rec.name == SLOTREC then
			-- The roster, not a note. Wholesale, not per slot: it describes one
			-- raid, and merging half of somebody's roster into half of yours
			-- names people who are not standing here.
			--
			-- Never asked about, unlike a note: a slot holds a name somebody
			-- typed once, not work, and the officer sending it is the one who
			-- decides who is on cooldowns tonight.
			if rec.stamp >= (d.slotStamp or 0) then
				local got = {}
				for slot, whoName in rec.text:gmatch("([^,=]+)=([^,]+)") do
					got[slot] = whoName
				end
				if next(got) then
					d.slots = got
					d.slotStamp = rec.stamp
					if N.PaintLines then pcall(N.PaintLines) end
					if Okanvil.NotesWindow and Okanvil.NotesWindow.Refresh then
						pcall(Okanvil.NotesWindow.Refresh)
					end
				end
			end
		elseif rec.text ~= "" then
			local mine = d.stamps[rec.name] or 0
			local haveText = (d.notes[rec.name] or "") ~= ""
			if not haveText then
				-- Nothing of yours here: take it.
				d.notes[rec.name] = rec.text
				d.stamps[rec.name] = rec.stamp
				n = n + 1
			elseif d.notes[rec.name] == rec.text then
				-- Same text, newer stamp. Nothing to decide.
				if rec.stamp > mine then d.stamps[rec.name] = rec.stamp end
			elseif rec.stamp > mine then
				ask[#ask + 1] = { name = rec.name, text = rec.text, stamp = rec.stamp, who = who }
			end
		end
	end
	if n > 0 then
		if N.Broadcast then N.Broadcast() end
		if N.Refresh then N.Refresh() end
	end
	if #ask > 0 then
		pendingAsk = ask
		askNext()
	end
	return n
end

-- ------------------------------------------------------------
-- Talking
-- ------------------------------------------------------------
local lastAnnounce = 0

function N.AnnounceSync()
	if not (Comms and syncAllowed()) then return end
	local stamp = N.Stamp()
	if stamp == 0 then return end
	local now = GetTime() or 0
	if now - lastAnnounce < 5 then return end    -- roster events arrive in bursts
	lastAnnounce = now
	Comms.Send("NOTEV", tostring(stamp))
end

-- ------------------------------------------------------------
-- Telling the raid which note is live.
--
-- A raider running only the WeakAura has the notes but no zone logic -- the
-- aura has no idea which boss you are about to pull. This is the leader saying
-- so, and it is why walking into a room is enough for everyone.
--
-- Not officer-gated on the receiving side: it names a note, it does not change
-- one, and a raider ignoring it would just read the wrong plan.
-- ------------------------------------------------------------
local lastSel
function N.AnnounceSelected(force)
	if not Comms then return end
	local d = db()
	local sel = d and d.selected
	if not sel or sel == "" then return end
	if not force and sel == lastSel then return end
	-- Only the person driving the raid should be steering everyone's note.
	if not (IsRaidLeader and IsRaidLeader()) and not (IsRaidOfficer and IsRaidOfficer()) then
		if (GetNumRaidMembers() or 0) > 0 then return end
	end
	lastSel = sel
	Comms.Send("NOTESEL", sel)
end

-- Push everything to the group, on demand. The button; the rest is automatic.
function N.SendNow()
	-- EVERY path says something. A button that sometimes does its job silently
	-- and sometimes fails silently is one you cannot trust before a pull: you
	-- press it, nothing happens, and there is no way to tell which it was.
	if not Comms then
		Okanvil:Print("|cffff5555Cannot send -- the comms layer is not loaded.|r")
		return
	end
	local ok, why = syncAllowed()
	if not ok then
		Okanvil:Print("|cffff5555Cannot send|r -- " .. (why or "sharing is not allowed"))
		return
	end
	-- withPack: a Send to the group is aimed at raiders running only the aura,
	-- and they hold nothing until we give it to them.
	local raw = encode(true)
	if raw == "" then
		Okanvil:Print("|cff8a8d93Nothing to share -- no notes at all.|r")
		return
	end
	local chan = (GetNumRaidMembers() or 0) > 0 and "RAID"
		or ((GetNumPartyMembers() or 0) > 0 and "PARTY" or nil)
	if not chan then
		Okanvil:Print("|cff8a8d93Nobody to share with -- not in a group.|r")
		return
	end

	-- Name the slots whose player is not in this group, before the roster goes
	-- out to everyone.
	--
	-- A slot is matched by NAME, so one wrong letter -- "Solanarage" for
	-- "Solanarrage" -- assigns the line to nobody, and it reads on screen exactly
	-- like a line correctly assigned to someone else. Sending it copies that
	-- mistake to the whole raid.
	--
	-- Said, not enforced: an alt logging in late, or a name typed ahead of the
	-- invite, are both ordinary, and a Send that refuses before a pull is worse
	-- than a Send that warns.
	local d = db()
	if d and d.slots and next(d.slots) then
		local inGroup = {}
		local nRaid = GetNumRaidMembers() or 0
		if nRaid > 0 then
			for i = 1, nRaid do
				local rn = GetRaidRosterInfo(i)
				if rn then inGroup[rn:lower()] = true end
			end
		else
			inGroup[(UnitName("player") or ""):lower()] = true
			for i = 1, (GetNumPartyMembers() or 0) do
				local pn = UnitName("party" .. i)
				if pn then inGroup[pn:lower()] = true end
			end
		end
		local strays = {}
		for slot, whoName in pairs(d.slots) do
			if type(whoName) == "string" and whoName ~= ""
				and not inGroup[whoName:lower()] then
				strays[#strays + 1] = slot .. "=" .. whoName
			end
		end
		if #strays > 0 then
			table.sort(strays)
			Okanvil:Print(("|cffe0b860Heads up:|r %s not in the group -- check the spelling.")
				:format(table.concat(strays, ", ")))
		end
	end

	-- Count what is going out, so the confirmation is a fact rather than a
	-- reassurance: "12 notes" tells you the pack went; "1 note" tells you
	-- something is wrong before the raid finds out.
	-- The roster rides along as a record but is not a note, so it must not be
	-- counted as one: "13 notes" for a pack of 12 is the kind of small lie that
	-- makes the number useless for spotting a real short send.
	local n = 0
	for recName in raw:gmatch("\1([^\1]+)\1%d+\1") do
		if recName ~= SLOTREC then n = n + 1 end
	end

	local chunks = Comms.SendBig("NOTES", raw, chan)
	if not chunks then
		Okanvil:Print("|cffff5555Send failed.|r Nothing went out.")
		return
	end

	lastSend = { at = GetTime(), notes = n, chunks = chunks, chan = chan, got = {} }
	N.AnnounceSelected(true)

	local sel = (db() and db().selected)
	Okanvil:Print(("Sent |cffffd200%d|r %s to the %s%s"):format(
		n, n == 1 and "note" or "notes", chan:lower(),
		sel and (" -- live: |cffe0b860" .. sel .. "|r") or "."))

	-- The replies land over the next second or two. Report the tally once
	-- rather than a line per person, and name whoever stayed silent -- that is
	-- the half worth knowing.
	Comms.After(4, function()
		if not lastSend then return end
		local got = 0
		for _ in pairs(lastSend.got) do got = got + 1 end

		local missing = {}
		local me = UnitName("player") or ""
		local nRaid = (GetNumRaidMembers() or 0)
		if nRaid > 0 then
			for i = 1, nRaid do
				local who = GetRaidRosterInfo(i)
				who = who and (who:gsub("%-.*$", ""))
				if who and who ~= me and not lastSend.got[who] then
					missing[#missing + 1] = who
				end
			end
		else
			for i = 1, (GetNumPartyMembers() or 0) do
				local who = UnitName("party" .. i)
				if who and not lastSend.got[who] then missing[#missing + 1] = who end
			end
		end

		-- You never confirm to yourself: with Okanvil installed the aura reads
		-- the note straight out of it and never touches the receiver that sends
		-- the ACK. So "nobody confirmed" in a group of one means nothing was
		-- asked, not that anything failed.
		if got == 0 and #missing == 0 then
			Okanvil:Print("|cff8a8d93Sent -- nobody else in the group to confirm.|r")
		elseif got == 0 then
			-- Silence is not a diagnosis. It means one of: no aura, an aura that
			-- never received, or a reply that did not come back -- and naming the
			-- first as fact sent us hunting someone's install for an evening
			-- while the message itself was the problem. Say what is known.
			table.sort(missing)
			Okanvil:Print(("|cffff5555No reply from|r %s -- no aura, or it did not receive."):format(
				table.concat(missing, ", ")))
		elseif #missing == 0 then
			Okanvil:Print(("|cff7cfc8aAll %d confirmed.|r"):format(got))
		else
			table.sort(missing)
			Okanvil:Print(("|cff7cfc8a%d confirmed|r, |cffff5555%d did not:|r %s"):format(
				got, #missing, table.concat(missing, ", ")))
		end
		if N.Refresh then N.Refresh() end
	end)
end

-- ------------------------------------------------------------
-- Who actually has the notes.
--
-- The whole point of sending is that a raider casts on the right second, so the
-- leader needs to know who is holding what before the pull.
--
--   NOTEREQ  raider -> group    "I hold <stamp>, is that current?"   (on joining)
--   NOTEWHO  leader -> group    "everyone report"                    (the button)
--   NOTEACK  raider -> leader   "I hold <stamp>"
--
-- Between Okanvil clients only. Answering requires the addon, which is the
-- point: a stamp equal to ours means they are current, lower means stale, and
-- no reply means no addon -- the case you most need to catch before a pull.
-- ------------------------------------------------------------
local acks = {}          -- name -> { stamp = n, at = GetTime() }

function N.Acks() return acks end

-- Ask the raid to report. The replies arrive over the next second or two, so
-- the caller gets a callback rather than a return value.
function N.AuditRaid(onDone, timeout)
	if not Comms then return false end
	local chan = (GetNumRaidMembers() or 0) > 0 and "RAID"
		or ((GetNumPartyMembers() or 0) > 0 and "PARTY" or nil)
	if not chan then return false end
	wipe(acks)
	Comms.Send("NOTEWHO")
	Comms.After(timeout or 4, function()
		if type(onDone) == "function" then onDone(acks) end
	end)
	return true
end

-- The raid, split three ways against our own stamp. Anyone in the roster who
-- never answered is listed as missing -- that is the real finding.
function N.AuditResult()
	local mine = N.Stamp()
	local ok, stale, missing = {}, {}, {}
	local me = UnitName("player") or ""
	local n = (GetNumRaidMembers() or 0)
	local roster = {}
	if n > 0 then
		for i = 1, n do
			local who = GetRaidRosterInfo(i)
			if who then roster[#roster + 1] = (who:gsub("%-.*$", "")) end
		end
	else
		roster[#roster + 1] = me
		for i = 1, (GetNumPartyMembers() or 0) do
			local who = UnitName("party" .. i)
			if who then roster[#roster + 1] = who end
		end
	end
	for _, who in ipairs(roster) do
		if who == me then
			ok[#ok + 1] = who                          -- we are the source
		else
			local a = acks[who]
			if not a then missing[#missing + 1] = who
			elseif a.stamp >= mine then ok[#ok + 1] = who
			else stale[#stale + 1] = who end
		end
	end
	table.sort(ok); table.sort(stale); table.sort(missing)
	return ok, stale, missing
end

if Comms then
	-- A raider's aura reports what it holds. Recorded whoever they are: this is
	-- information about them, it changes nothing here.
	Comms.On("NOTEACK", function(who, stamp, applied)
		if not who or who == "" then return end
		-- The aura replies on the group channel now, which means our own client
		-- hears it too. We are the source; confirming to ourselves would make
		-- an empty raid read as "1 confirmed".
		if who == (UnitName("player") or "") then return end
		acks[who] = { stamp = tonumber(stamp) or 0, at = GetTime() or 0 }

		-- Tally against the last Send rather than printing a line each: in a
		-- 25-man that would be 24 lines of chat for one button press. The
		-- summary goes out once, a few seconds later.
		if lastSend and (GetTime() - lastSend.at) < 20 then
			lastSend.got[who] = tonumber(applied) or 0
			if N.Refresh then N.Refresh() end
		end

		if N.OnAck then N.OnAck(who) end
	end)

	-- A raider joined and is asking whether they are current. Answer by sending,
	-- but only if we actually have something newer -- otherwise every zone-in
	-- would re-send the whole pack to the whole raid.
	Comms.On("NOTEREQ", function(who, stamp)
		if not syncAllowed() then return end
		if who == (UnitName("player") or "") then return end
		-- This asker is an aura with no pack of its own (see encode).
		local raw = encode(true)
		if raw == "" then return end
		if (tonumber(stamp) or 0) >= N.Stamp() then
			-- They are current; they just do not know which boss is live.
			N.AnnounceSelected(true)
			return
		end
		Comms.SendBig("NOTES", raw, "WHISPER", who)
		Comms.After(2, function() N.AnnounceSelected(true) end)
	end)

	-- Someone says what they hold. Ask only when theirs is newer than ours.
	Comms.On("NOTEV", function(who, stamp)
		if not (syncAllowed() and senderTrusted(who)) then return end
		if who == (UnitName("player") or "") then return end
		stamp = tonumber(stamp) or 0
		if stamp <= N.Stamp() then return end
		Comms.Whisper("NOTEQ", who)
	end)

	-- Someone asked. Send ours, to them alone.
	Comms.On("NOTEQ", function(who)
		if not (syncAllowed() and senderTrusted(who)) then return end
		local raw = encode()
		if raw == "" then return end
		Comms.SendBig("NOTES", raw, "WHISPER", who)
	end)

	-- Notes arrived. Re-check trust: the chunks took time, and `who` is still
	-- only a name off the wire.
	Comms.OnBig("NOTES", function(who, text)
		if Okanvil.ModuleActive and not Okanvil:ModuleActive("Okanvil-Notes") then return end
		local d = db()
		if not d or d.share == false then return end
		if not senderTrusted(who) then return end
		local list = decode(text)
		if not list then return end
		local n = merge(list, who)
		if n > 0 then
			Okanvil:Print(("Notes updated from |cffffd200%s|r (%d %s)."):format(
				who, n, n == 1 and "note" or "notes"))
		end
	end)

	-- Announce when the group changes: an officer joining is exactly when the
	-- two copies should meet. Settle first -- a raid forming fires these in a
	-- burst and the guild roster may not have caught up.
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("RAID_ROSTER_UPDATE")
	ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
	ev:SetScript("OnEvent", function()
		if not syncAllowed() then return end
		Comms.After(3, function() N.AnnounceSync() end)
	end)
end
