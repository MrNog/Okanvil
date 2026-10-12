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
		return (x.t or 0) > (y.t or 0)            -- newest whisper first
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

function M.DismissApplicant(name)
	local a = M.Applicant(name)
	if a then a.hidden = true; changed() end
end

function M.ClearWhispers()
	for name in pairs(applicants()) do
		local a = M.Applicant(name)
		if a then a.hidden = true end
	end
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
		syncRoster()
	end
end)
