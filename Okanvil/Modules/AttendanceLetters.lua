-- ============================================================
-- Okanvil -- Attendance letters.
-- Every Okanvil tells the officers, ONCE per lockout, which raid ID its character
-- got saved to -- every raid of the catalogue, not only the ones the guild counts
-- today: which raids are mandatory is the officers' Rules, so a raider's client
-- never has to know it. That is how the officers tell "absent" (no raid that week)
-- from "saved to another ID" (the guild rule broken), and who puts in extra effort
-- -- things no client can read about another player.
--
-- Store and forward: the letter is kept on the raider's disk until an officer is
-- online, goes out as one message on the guild addon channel, and is marked
-- delivered when an officer answers. No popup, nothing shown to anyone; a
-- letter that finds nobody waits for the next officer.
--
-- Officers then sync their inboxes with each other (one officer uploads to the
-- site, so that one needs every letter): an officer who logs in sends theirs to
-- the officers online, and each of them answers with their own.
-- ============================================================

local Okanvil = Okanvil
local A = Okanvil.Attendance
local L = {}
A.Letters = L

local RETRY_GAP = 600      -- seconds between tries while no officer answers
local MAX_TRIES = 6        -- per login; the next login starts over
local KEEP_WEEKS = 5       -- officers keep letters this long: the 4-week grid + this week; the site keeps the rest

local function stripRealm(n) return (n or ""):gsub("%-.*$", "") end

-- ------------------------------------------------------------
-- Raider side: this character's letters (per character, like its lockouts)
-- ------------------------------------------------------------
local function outbox()
	local c = Okanvil.cdb
	if not c then return {} end
	c.attLetters = c.attLetters or {}
	return c.attLetters
end

-- Write a letter for every raid lockout this character holds that has none yet.
-- The raid goes by its rule short name ("ICC", "Naxx", "ToGC").
function L.Scan()
	if not (IsInGuild and IsInGuild()) or not GetNumSavedInstances then return end
	local box, now = outbox(), time()
	for i = 1, (GetNumSavedInstances() or 0) do
		-- 3.3.5a: name, id, expires (seconds left), diff, locked, extended, mostsig, raid, players
		local iname, id, expires, diff, locked, _, _, raid, players = GetSavedInstanceInfo(i)
		-- ToGC is its own raid here: another lockout ID than ToC
		local cat = A.RuleRaidOf(iname or "", diff)
		local z = cat and cat.short
		if z and raid and locked and id and (expires or 0) > 0 then
			local size = (players == 10 or players == 25) and players or ((diff == 1 or diff == 3) and 10 or 25)
			local resets = now + expires
			local week = A.WeekOf(resets - 7 * 86400 + 3600)   -- the week this lockout belongs to
			local key = z .. size .. "|" .. week
			local cur = box[key]
			if not cur or cur.id ~= id then
				box[key] = { z = z, size = size, id = id, week = week, resets = resets }
				Okanvil:Trace("ATT", ("letter %s %d id %s week %s"):format(z, size, tostring(id), week))
			end
		end
	end
	-- delivered and expired letters have done their job
	for key, l in pairs(box) do
		if (l.resets or 0) < now and (l.acked or (l.resets or 0) < now - KEEP_WEEKS * 7 * 86400) then box[key] = nil end
	end
	L.TrySend()
end

local function officerOnline()
	local me = UnitName("player")
	for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
		local n, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
		if n and online then
			n = stripRealm(n)
			if n ~= me and Okanvil.U.canSeePrio(n) then return n end
		end
	end
end

local tries, lastTry = 0, 0
function L.TrySend()
	if InCombatLockdown and InCombatLockdown() then return end
	local pending = {}
	for _, l in pairs(outbox()) do if not l.acked then pending[#pending + 1] = l end end
	if #pending == 0 then return end
	-- an officer files their own letters straight into their inbox
	if Okanvil.U.canSeePrio() then
		local me = UnitName("player") or ""
		for _, l in ipairs(pending) do
			L.Store(me, l.z, l.size, l.id, l.week)
			l.acked = time()
		end
		return
	end
	if tries >= MAX_TRIES or time() - lastTry < RETRY_GAP then return end
	local officer = officerOnline()
	if not officer then return end
	lastTry, tries = time(), tries + 1
	for _, l in ipairs(pending) do
		Okanvil.Comms.SendGuild("ATTL", l.z, l.size, l.id, l.week)
	end
	Okanvil:Trace("ATT", ("sent %d letter(s), try %d, officer online: %s"):format(#pending, tries, officer))
end

-- ------------------------------------------------------------
-- Officer side: the inbox (account-wide, it is guild data)
-- ------------------------------------------------------------
function L.Inbox()
	local a = A.DB()
	a.letters = a.letters or {}
	return a.letters
end

function L.Store(n, z, size, id, week)
	local box = L.Inbox()
	box[n .. "|" .. z .. size .. "|" .. week] = { n = n, z = z, size = size, id = id, week = week, t = time() }
	local cut = A.WeekOf(time() - KEEP_WEEKS * 7 * 86400)
	for k, l in pairs(box) do if (l.week or "") < cut then box[k] = nil end end
	if A.onChange then A.onChange() end
end

local function valid(z, size, id, week)
	return z and A.RaidByShort(z) and (size == 10 or size == 25) and id
		and type(week) == "string" and week:match("^%d%d%d%d%-%d%d%-%d%d$")
end

Okanvil.Comms.On("ATTL", function(sender, z, size, id, week)
	if not Okanvil.U.canSeePrio() then return end
	size, id = tonumber(size), tonumber(id)
	if not valid(z, size, id, week) then return end
	L.Store(sender, z, size, id, week)
	Okanvil.Comms.Whisper("ATTA", sender, z, size, id)
end)

-- An answer only counts from an officer: anyone else could claim the letter arrived.
Okanvil.Comms.On("ATTA", function(sender, z, size, id)
	if not Okanvil.U.canSeePrio(sender) then return end
	size, id = tonumber(size), tonumber(id)
	for _, l in pairs(outbox()) do
		if l.z == z and l.size == size and l.id == id and not l.acked then
			l.acked = time()
			Okanvil:Trace("ATT", ("letter %s %d delivered to %s"):format(z, size, sender))
		end
	end
end)

-- ------------------------------------------------------------
-- Officer sync. Both sides merge, so a letter any officer holds reaches every
-- officer the next time two of them are online together. Only the recent weeks
-- travel: that is all the site's list and 10-man report look at.
-- ------------------------------------------------------------
local SYNC_WEEKS = 5

local function bundle()
	local cut = A.WeekOf(time() - SYNC_WEEKS * 7 * 86400)
	local out = {}
	for _, l in pairs(L.Inbox()) do
		if (l.week or "") >= cut then
			out[#out + 1] = table.concat({ l.n, l.z, l.size, tostring(l.id), l.week, l.t or 0 }, ",")
		end
	end
	-- officers' clearances ride along ("C" records): the uploader needs those too
	for _, c in pairs(A.DB().cleared or {}) do
		if (c.week or "") >= cut then
			out[#out + 1] = table.concat({ "C", c.week, c.n, (c.reason or ""):gsub("[,;]", " "), c.by or "",
				c.t or 0, c.on and 1 or 0 }, ",")
		end
	end
	-- and the Rules ("R" record), once an officer has set them
	if (A.Rules().t or 0) > 0 then out[#out + 1] = L.RulesRecord() end
	-- never empty: an officer with no letters still has to ask for the others'
	return #out > 0 and table.concat(out, ";") or "-", #out
end

-- Add what we lack. The same toon with a different ID for the same week keeps the
-- newer letter (a reset re-entry, or an old letter from before a mistake).
function L.Merge(text)
	local box, added = L.Inbox(), 0
	local a = A.DB()
	a.cleared = a.cleared or {}
	for rec in (text or ""):gmatch("[^;]+") do
		local rt, rb, rall, rmust, rextra = rec:match("^R,(%d+),([^,]*),([01]),([^,]+),([^,]+)$")
		if rt then
			local function split(s)
				local out = {}
				if s ~= "-" then for ref in s:gmatch("[^+]+") do out[#out + 1] = ref end end
				return out
			end
			if A.ApplyRules(tonumber(rt), rb, rall == "1", split(rmust), split(rextra)) then added = added + 1 end
		end
		local cw, cn, cr, cb, ct, con = rec:match("^C,([^,]+),([^,]+),([^,]*),([^,]*),([^,]*),([01])$")
		if cw then
			ct = tonumber(ct) or 0
			local key = cw .. "|" .. cn:lower()
			local cur = a.cleared[key]
			if not cur or ct > (cur.t or 0) then
				a.cleared[key] = { week = cw, n = cn, reason = cr, by = cb, t = ct, on = con == "1" }
				added = added + 1
			end
		end
		local n, z, size, id, week, t = rec:match("^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]*)$")
		size, id, t = tonumber(size), tonumber(id), tonumber(t) or 0
		if n and valid(z, size, id, week) then
			local key = n .. "|" .. z .. size .. "|" .. week
			local cur = box[key]
			if not cur or (cur.id ~= id and t > (cur.t or 0)) then
				box[key] = { n = n, z = z, size = size, id = id, week = week, t = t }
				added = added + 1
			end
		end
	end
	if added > 0 and A.onChange then A.onChange() end
	return added
end

-- A clearance goes to the officers online right away (the same record format as the
-- sync), so whoever uploads has it without waiting for the next login.
function L.ShareClear(c)
	if not c then return end
	local rec = table.concat({ "C", c.week, c.n, (c.reason or ""):gsub("[,;]", " "), c.by or "", c.t or 0, c.on and 1 or 0 }, ",")
	Okanvil.Comms.SendBig("ATTR", rec, "GUILD")
end

-- The Rules as one sync record: "R,<t>,<by>,<all 0/1>,<must a+b>,<extra a+b>", "-" for none.
function L.RulesRecord()
	local r = A.Rules()
	return table.concat({ "R", r.t or 0, (r.by or ""):gsub("[,;]", ""), r.all and 1 or 0,
		#r.must > 0 and table.concat(r.must, "+") or "-", #r.extra > 0 and table.concat(r.extra, "+") or "-" }, ",")
end

-- A change of the Rules goes to the officers online right away, like a clearance.
function L.ShareRules()
	Okanvil.Comms.SendBig("ATTR", L.RulesRecord(), "GUILD")
end

local synced = false
function L.SyncOnLogin()
	if synced or not Okanvil.U.canSeePrio() then return end
	if InCombatLockdown and InCombatLockdown() then return end
	if not officerOnline() then return end
	synced = true
	local text, n = bundle()
	Okanvil.Comms.SendBig("ATTS", text, "GUILD")
	Okanvil:Trace("ATT", "sync: sent " .. n .. " letter(s) to the officers online")
end

Okanvil.Comms.OnBig("ATTS", function(sender, text)
	if sender == UnitName("player") then return end
	if not (Okanvil.U.canSeePrio() and Okanvil.U.canSeePrio(sender)) then return end
	local added = L.Merge(text)
	-- spread the answers so the officers online don't all whisper in the same second
	Okanvil.Comms.After(1 + math.random() * 4, function()
		local out, n = bundle()
		Okanvil.Comms.SendBig("ATTR", out, "WHISPER", sender)
		Okanvil:Trace("ATT", ("sync: %s sent theirs (+%d new), answered with %d"):format(sender, added, n))
	end)
	synced = true   -- they reached us, so our login sync would only repeat this
end)

Okanvil.Comms.OnBig("ATTR", function(sender, text)
	if not (Okanvil.U.canSeePrio() and Okanvil.U.canSeePrio(sender)) then return end
	local added = L.Merge(text)
	Okanvil:Trace("ATT", ("sync: %s answered, +%d new letter(s)"):format(sender, added))
end)

do
	local f = CreateFrame("Frame")
	f:RegisterEvent("UPDATE_INSTANCE_INFO")    -- lockouts read (login, and after every raid fight)
	f:RegisterEvent("GUILD_ROSTER_UPDATE")     -- an officer may have come online
	f:RegisterEvent("PLAYER_REGEN_ENABLED")    -- out of combat: send what waited
	f:SetScript("OnEvent", function(_, event)
		local ok, err = pcall(event == "UPDATE_INSTANCE_INFO" and L.Scan or L.TrySend)
		if not ok then Okanvil:Err("Attendance letters", err) end
		if event ~= "UPDATE_INSTANCE_INFO" then
			ok, err = pcall(L.SyncOnLogin)
			if not ok then Okanvil:Err("Attendance sync", err) end
		end
	end)
end
