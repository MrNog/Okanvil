-- ============================================================
-- Okanvil -- PuG whispers.
-- Everyone who whispers while the LFM line is running, with where they stand:
--   new       whispered, not invited yet
--   invited   an invite went out (from the panel, /inv, or any other addon)
--   joined    they are in the group
--   declined  they turned the invite down
--   busy      already in another group
--   offline   the invite could not find them
-- The status follows the game's own system messages and the roster, so it is
-- right however the invite was sent. PuG-UI.lua draws the panel.
-- ============================================================

local Okanvil = Okanvil
local M = Okanvil.PuG
local U = Okanvil.U

-- Display order: who still needs an answer first, the settled ones last.
local STATUS_ORDER = { new = 1, invited = 2, joined = 3, declined = 4, busy = 5, offline = 6 }
M.WHISPER_STATUS_ORDER = STATUS_ORDER

local function applicants()
	return M.db and M.db.applicants or {}
end

local function changed()
	if M.RefreshWhispers then M.RefreshWhispers() end
end
M.WhispersChanged = changed

local function setStatus(name, status)
	local a = name and M.Applicant(name)
	if not a or a.status == status then return end
	-- A player in the raid stays "joined" until they leave it; a late
	-- "declines" from an old invite does not undo that.
	if a.status == "joined" and status ~= "new" then return end
	a.status = status
	a.st = time()
	changed()
end

-- Words that only turn up in a whisper asking to join. The spec and gearscore
-- the parser reads count too, so "rsham 5.4" gets in on those alone.
local APPLY_WORDS = {
	"inv", "spot", "room", "join", "need", "space", "achi", "%f[%a]lf%f[%A]",
	"%f[%a]gs%f[%A]", "%f[%a]dps%f[%A]", "tank", "heal", "%f[%a]ms%f[%A]", "%f[%a]os%f[%A]",
	"^%s*[%+x1]%s*$",                      -- the bare "+" / "x" / "1" people send
}

-- Does this whisper ask to join? An addon's auto-reply ("<DBM> ...", "<AFK>")
-- never does, whatever words it contains.
function M.LooksLikeApplication(msg, spec, gs)
	local low = (msg or ""):lower()
	if low:find("^%s*<") then return false end
	if spec or gs then return true end
	for _, p in ipairs(APPLY_WORDS) do
		if low:find(p) then return true end
	end
	return false
end

-- Every live applicant, sorted for the panel. `filter` = a status, or nil for all.
function M.Whispers(filter)
	local out = {}
	for name in pairs(applicants()) do
		local a = M.Applicant(name)
		if a and not a.hidden and a.status and (not filter or a.status == filter) then
			out[#out + 1] = a
		end
	end
	table.sort(out, function(x, y)
		local ox, oy = STATUS_ORDER[x.status] or 9, STATUS_ORDER[y.status] or 9
		if ox ~= oy then return ox < oy end
		-- oldest first, by their FIRST whisper: a newcomer joins the bottom and a
		-- follow-up ("5.4k") does not move a row, so the Inv under the cursor stays put
		local fx, fy = x.first or x.t or 0, y.first or y.t or 0
		if fx ~= fy then return fx < fy end
		return x.name < y.name
	end)
	return out
end

-- How many sit in each status, for the filter buttons.
function M.WhisperCounts()
	local n = { all = 0 }
	for _, a in ipairs(M.Whispers()) do
		n[a.status] = (n[a.status] or 0) + 1
		n.all = n.all + 1
	end
	return n
end

function M.InviteApplicant(name)
	if not name then return end
	InviteUnit(name)
	-- Shown at once; the system message confirms it (or turns it into busy /
	-- offline) a moment later.
	setStatus(name, "invited")
end

-- Group members who never whispered: they get a Joined row too, so the gear
-- audit covers the whole group. [name] = { t, hidden, auditOk, kickAsk }
local members = {}

function M.GroupMembers()
	local out = {}
	local me = UnitName("player")
	for _, p in ipairs(M.RosterList and M.RosterList() or {}) do
		local a = p.name and M.Applicant(p.name)
		if p.name and p.name ~= me and not (a and a.status == "joined") then
			local m = members[p.name] or { t = time() }
			members[p.name] = m
			if not m.hidden then out[#out + 1] = { name = p.name, class = p.class, t = m.t } end
		end
	end
	return out
end

function M.DismissApplicant(name)
	local a = M.Applicant(name)
	if a then a.hidden = true end
	if members[name] then members[name].hidden = true end
	changed()
end

function M.ClearWhispers()
	for name in pairs(applicants()) do
		local a = M.Applicant(name)
		if a then a.hidden = true end
	end
	for _, m in pairs(members) do m.hidden = true end
	changed()
end

-- Invite every "new" whisperer whose role still has an open spot, oldest
-- whisper first. Invites already out count against the spots, so pressing it
-- twice does not over-invite. Whisperers whose role was not read are left for
-- the leader to judge.
function M.InviteNeeded()
	local open = M.StillNeeded()
	for _, a in ipairs(M.Whispers("invited")) do
		if a.role and open[a.role] then open[a.role] = open[a.role] - 1 end
	end
	local queue = M.Whispers("new")
	table.sort(queue, function(x, y) return (x.t or 0) < (y.t or 0) end)
	local sent = 0
	for _, a in ipairs(queue) do
		if a.role and (open[a.role] or 0) > 0 then
			open[a.role] = open[a.role] - 1
			M.InviteApplicant(a.name)
			sent = sent + 1
		end
	end
	return sent
end

-- ------------------------------------------------------------
-- Status from the game
-- ------------------------------------------------------------

-- "%s declines your group invitation." -> "^(.+) declines your group invitation%.$"
local function systemPattern(fmt)
	if not fmt then return nil end
	return "^" .. U.escPattern(fmt):gsub("%%%%s", "(.+)") .. "$"
end

local SYSTEM = {
	{ systemPattern(ERR_INVITE_PLAYER_S),     "invited" },
	{ systemPattern(ERR_DECLINE_GROUP_S),     "declined" },
	{ systemPattern(ERR_ALREADY_IN_GROUP_S),  "busy" },
	{ systemPattern(ERR_BAD_PLAYER_NAME_S),   "offline" },
	{ systemPattern(ERR_JOINED_GROUP_S),      "joined" },
	{ systemPattern(ERR_RAID_MEMBER_ADDED_S), "joined" },
}

-- Whisperers found in the group have joined, however they got the invite.
local function syncRoster()
	local inGroup = {}
	for _, p in ipairs(M.RosterList and M.RosterList() or {}) do
		if p.name then inGroup[p.name] = true end
	end
	for name in pairs(applicants()) do
		local a = M.Applicant(name)
		if a and a.status and a.status ~= "joined" and inGroup[name] then
			a.status, a.st = "joined", time()
		end
	end
	changed()
end

-- ------------------------------------------------------------
-- A joiner fills an ask
--
-- Asking for "bdk" in the Tank column and then getting one should take "bdk" out
-- of the LFM line by itself. When someone new joins while the line is running,
-- the first ask in their board column that matches their class (and, for the two
-- priest healers, their spec) is cleared. A joiner whose column is not known yet
-- (an uninspected hybrid who never whispered) is checked again until it is.
-- ------------------------------------------------------------
local SPEC_CLASS = {}
for _, s in ipairs(OkanvilClassSpecs or {}) do SPEC_CLASS[s.token] = s.class end
-- the only asks that share a class AND a column, told apart by the spec word
local SPEC_WORD = { PRIEST_DISC = "disc", PRIEST_HOLY = "holy" }

local settled            -- [name] = true once a joiner has been checked; nil = not spamming

local function specWordOf(name)
	local I = Okanvil.Inspect
	local spec = I and I.Get and I.Get(name)
	if not spec then
		local a = M.Applicant(name)
		spec = a and a.spec
	end
	return spec and spec:lower() or nil
end

local function fillAsk(p)
	local picks = M.RolePicks(p.role)
	for _, tok in ipairs(M.ASKS[p.role] or {}) do
		if picks[tok] and (SPEC_CLASS[tok] or tok) == p.class then
			local word = SPEC_WORD[tok]
			local spec = word and specWordOf(p.name)
			-- a priest of the OTHER healing spec does not fill this ask
			if not (word and spec and not spec:find(word, 1, true)) then
				picks[tok] = nil
				return true
			end
		end
	end
	return false
end

-- Put a player on the inspect watch unless their spec is already known and
-- fresh. The watch reads one player at a time as they come in range, so this
-- replaces the old "Read specs" button without a burst of inspects.
local watched = {}
local function readSpec(name)
	local I = Okanvil.Inspect
	if not (name and I and I.Watch) or watched[name] then return end
	watched[name] = true
	if Okanvil.Audit then Okanvil.Audit.WantAchievements(name) end
	-- a spec read before the audit existed has no gear check: read it again
	if I.IsFresh and I.IsFresh(name) and (not I.HasAudit or I.HasAudit(name)) then return end
	I.Watch({ name })
end

function M.CheckJoinersFillAsks()
	if not M.db then return end
	local list = M.RosterList()
	if not M.db.active then
		-- not hosting: still read each group member once, as they come in range,
		-- so the board shows spec and gear for a group someone else is leading
		settled = nil
		for _, p in ipairs(list) do readSpec(p.name) end
		return
	end
	if not settled then
		-- spamming just started: whoever is already here asked for nothing, but
		-- their specs are worth reading for the board
		settled = {}
		for _, p in ipairs(list) do settled[p.name] = true; readSpec(p.name) end
		return
	end
	local changed = false
	for _, p in ipairs(list) do
		if p.name and not settled[p.name] then
			readSpec(p.name)
			if p.class and p.role then
				settled[p.name] = true
				if fillAsk(p) then changed = true end
			end
		end
	end
	if changed and M.RefreshUI then M.RefreshUI() end
end

local wasInGroup          -- nil until the first roster event: a login solo is not a leave
local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
ev:SetScript("OnEvent", function(_, event, msg)
	if not M.db then return end
	if Okanvil.ModuleActive and not Okanvil:ModuleActive("Okanvil-PuG") then return end
	if event == "CHAT_MSG_SYSTEM" then
		if not msg then return end
		for _, s in ipairs(SYSTEM) do
			local who = s[1] and msg:match(s[1])
			if who then
				who = who:gsub("^'", ""):gsub("'$", "")
				setStatus(who:match("^[^%-]+") or who, s[2])
				return
			end
		end
	else
		-- leaving the group ends that pug: its whispers go, and the next group
		-- gets its specs read afresh
		local inGroup = (GetNumRaidMembers() or 0) > 0 or (GetNumPartyMembers() or 0) > 0
		if wasInGroup and not inGroup then
			M.ClearWhispers()
			settled, watched, members = nil, {}, {}
		end
		wasInGroup = inGroup
		syncRoster()
		M.CheckJoinersFillAsks()
	end
end)

-- Joiners whose column was not known at join time get another look every few
-- seconds while spamming (an inspect or a whisper may have placed them since).
local tick = 0
ev:SetScript("OnUpdate", function(_, e)
	tick = tick + e
	if tick < 3 then return end
	tick = 0
	if M.db then M.CheckJoinersFillAsks() end
end)

-- ------------------------------------------------------------
-- Gear audit
--
-- Joined players are inspected as they come near (see readSpec); the audit rides
-- on that inspect. The panel shows a badge per joined row and, opened, what is
-- missing plus Mark OK / Whisper / Kick. Nothing is sent or done unless clicked.
-- ------------------------------------------------------------
local RED, YELLOW, GREEN, DIM, GOLD = "|cffd94d52", "|cfff0c040", "|cff7cfc8a", "|cff8a8d93", "|cffffd200"
local KICK_CONFIRM = 4

-- The row state for a joined player: their applicant entry, or the members entry
-- for someone who joined without whispering.
local function joinedState(name)
	local a = M.Applicant(name)
	if a and a.status == "joined" then return a end
	return members[name]
end

local function auditOf(name)
	local I = Okanvil.Inspect
	local info = I and I.Info and I.Info(name)
	return info and info.audit, info
end

function M.AuditBadge(name)
	local a = joinedState(name)
	if not a then return nil end
	if a.auditOk then return GREEN .. "OK|r" end
	local audit = auditOf(name)
	if not audit then return DIM .. "...|r" end
	local hard, soft = Okanvil.Audit.Counts(audit)
	if hard > 0 then return RED .. "x" .. hard .. "|r" end
	if soft > 0 then return YELLOW .. "!" .. soft .. "|r" end
	return GREEN .. "OK|r"
end

local function progressLine(info)
	local raid = M.db and M.db.raid
	local chips = Okanvil.Audit.RaidChips(raid)
	if #chips == 0 then return nil end
	local short = raid
	for _, r in ipairs(OkanvilRaids or {}) do if r.key == raid then short = r.short end end
	if not (info and info.ach) then
		return DIM .. short .. "|r  " .. DIM .. "reads when near|r"
	end
	local bits = {}
	for _, c in ipairs(chips) do
		bits[#bits + 1] = (info.ach[c.id] and GOLD or "|cff5a5c60") .. c.label .. "|r"
	end
	return DIM .. short .. "|r  " .. table.concat(bits, "   ")
end

local function canKick()
	if (GetNumRaidMembers() or 0) > 0 then
		return (IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer())
	end
	return IsPartyLeader and IsPartyLeader()
end

function M.AuditDetail(name)
	local a = joinedState(name)
	if not a then return nil end
	local audit, info = auditOf(name)
	local lines = {}

	if not audit then
		lines[#lines + 1] = DIM .. "Gear not read yet -- reads when they come near.|r"
	else
		local hard = Okanvil.Audit.Counts(audit)
		local stat = {}
		if info.ilvl then stat[#stat + 1] = DIM .. "ilvl|r " .. info.ilvl end
		if (info.pvp or 0) > 0 then stat[#stat + 1] = DIM .. "PvP|r " .. RED .. info.pvp .. "|r" end
		if #stat > 0 then lines[#lines + 1] = table.concat(stat, "   ") end

		local ne = audit.noEnchant or {}
		lines[#lines + 1] = (#ne > 0 and RED or GREEN) .. "Enchants|r  "
			.. (#ne > 0 and (table.concat(ne, ", ") .. " missing") or "all done")

		local g = {}
		if (audit.empty or 0) > 0 then g[#g + 1] = audit.empty .. " empty (" .. table.concat(audit.emptySlots, ", ") .. ")" end
		if audit.noBuckle then g[#g + 1] = "no buckle" end
		if (audit.lowGems or 0) > 0 then g[#g + 1] = audit.lowGems .. " rare on raid gear" end
		local gc = ((audit.empty or 0) > 0 or audit.noBuckle) and RED or ((audit.lowGems or 0) > 0 and YELLOW or GREEN)
		lines[#lines + 1] = gc .. "Gems|r  " .. (#g > 0 and table.concat(g, ", ") or "all filled, epic")

		if audit.meta ~= nil then
			lines[#lines + 1] = (audit.meta and GREEN or RED) .. "Meta|r  " .. (audit.meta and "active" or "not active")
		end
		if audit.partial then lines[#lines + 1] = DIM .. "Some items were not cached; reopen later.|r" end
		if hard == 0 and a.auditOk then lines[#lines + 1] = DIM .. "Marked OK.|r" end
	end

	local prog = progressLine(info)
	if prog then lines[#lines + 1] = prog end

	local msg = audit and Okanvil.Audit.WhisperText(audit)
	if msg then lines[#lines + 1] = "|cffff80ff" .. msg .. "|r" end

	local actions = {}
	actions[#actions + 1] = { label = a.auditOk and "Unmark" or "Mark OK", width = 62,
		tip = "Mark them as fine (green badge), whatever the audit says.",
		onClick = function() a.auditOk = not a.auditOk or nil; changed() end }
	if msg then
		actions[#actions + 1] = { label = a.auditSent and "Again" or "Whisper", kind = "primary", width = 64,
			tip = "Whisper them the pink line above.",
			onClick = function()
				SendChatMessage(msg, "WHISPER", nil, name)
				a.auditSent = true
				changed()
			end }
	end
	if canKick() then
		local asking = a.kickAsk and (GetTime() - a.kickAsk) < KICK_CONFIRM
		actions[#actions + 1] = { label = asking and "Sure?" or "Kick", kind = "danger", width = 52,
			tip = "Remove them from the group. Click twice.",
			onClick = function()
				if a.kickAsk and (GetTime() - a.kickAsk) < KICK_CONFIRM then
					a.kickAsk = nil
					UninviteUnit(name)
					Okanvil:Trace("AUDIT", "kicked " .. name)
				else
					a.kickAsk = GetTime()
				end
				changed()
			end }
	end
	return { text = table.concat(lines, "\n"), actions = actions }
end
