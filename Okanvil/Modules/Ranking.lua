-- ============================================================
-- Okanvil -- Ranking (GUILD > Ranking).
-- The guild's DPS / Healing / Tanking boards from the RATS site, in game: an
-- officer pastes the site's "Export to Okanvil" text once, and every guild
-- member online gets it over the guild addon channel. Whoever logs in later
-- asks the guild and gets it from anyone who already has it. Read by the
-- Ranking page (Ranking-UI.lua) and by the player tooltip.
--
-- The text is the site's export as-is (see buildOkanvilExport in the site's
-- rankings.js): one record per line, fields separated by commas.
--   OKR1
--   H,<unix time>,<raid key>,<raid label>,<periods, "+" between>
--   K,<boss 1>,<boss 2>,...
--   B,<size>,<d|h|t>,<period: week|month|all>
--   P,<name>,<CLASS>,<spec>,<rate>,<pts>,<srv %>,<fights>,<total>,<hc 0|1>
--   S,<size>,<toon>,<boss idx>:<pct>[h] ...
-- On the wire it gains a first line "BY,<officer>" -- who imported it.
--
-- Sync (all tiny messages, then ONE whispered transfer):
--   RKQ <t>  guild, at login: "my ranking is from time t"
--   RKH <t>  whisper back from anyone holding a newer one
--   RKG      whisper to the newest holder: "send it"
--   BIG RANK the payload; on import it goes to the whole guild at once
-- A payload is kept only when it is newer than ours and was imported by an
-- officer. That is the roster's word for it, not proof -- the data is a
-- leaderboard, so a spoofed one costs nothing but a re-import.
-- ============================================================

local Okanvil = Okanvil
local R = {}
Okanvil.Ranking = R

local MODULE = "Okanvil-Ranking"
local OFFER_WAIT = 4          -- seconds to collect RKH offers before asking one
local SEND_GAP = 60           -- seconds before the same player is sent the payload again

R.BOARDS = { "d", "h", "t" }
R.BOARD_LABEL = { d = "DPS", h = "Healing", t = "Tanking" }
R.BOARD_UNIT = { d = "DPS", h = "HPS", t = "TAKEN / FIGHT" }
R.SIZES = { "25", "10" }
R.PERIODS = { "week", "month", "all" }
R.PERIOD_LABEL = { week = "This week", month = "This month", all = "All time" }

-- boards are keyed "<period>|<size>|<kind>"
local function boardKey(period, size, kind) return period .. "|" .. size .. "|" .. kind end

-- The site's name key: lower case, letters and digits only. Same rule on both
-- sides so a toon's S record is found by the name on its tooltip.
function R.Norm(name)
	return (tostring(name or ""):gsub("%-.*$", ""):lower():gsub("[^%w]", ""))
end

local function db()
	local d = Okanvil.db
	if not d then return nil end
	d.ranking = d.ranking or {}
	return d.ranking
end

local function split(s, sep)
	local out = {}
	for f in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = f end
	return out
end

-- ------------------------------------------------------------
-- Parse the export text into boards. Returns the data table, or nil + reason.
-- ------------------------------------------------------------
function R.Parse(text)
	text = tostring(text or "")
	local d = { boards = {}, parses = {}, bosses = {}, periods = {}, count = 0 }
	local seenPeriod = {}
	local board
	local seenHead = false
	for line in text:gmatch("[^\r\n]+") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		local f = split(line, ",")
		local kind = f[1]
		if kind == "OKR1" then
			seenHead = true
		elseif kind == "BY" then
			d.by = f[2]
		elseif kind == "H" then
			d.t = tonumber(f[2])
			d.raid, d.label = f[3], f[4]
			-- an export from before the period toggle has ONE period here, and boards without one
			d.period = (f[5] or ""):match("^[^+]+") or "week"
		elseif kind == "K" then
			for i = 2, #f do d.bosses[i - 1] = f[i] end
		elseif kind == "B" and f[2] and R.BOARD_LABEL[f[3] or ""] then
			local period = (f[4] and f[4] ~= "") and f[4] or d.period or "week"
			if not seenPeriod[period] then seenPeriod[period] = true; d.periods[#d.periods + 1] = period end
			board = {}
			d.boards[boardKey(period, f[2], f[3])] = board
		elseif kind == "P" and board and f[2] and f[2] ~= "" then
			board[#board + 1] = {
				name = f[2], key = R.Norm(f[2]), class = f[3], spec = f[4],
				rate = tonumber(f[5]) or 0, pts = tonumber(f[6]) or 0, srv = tonumber(f[7]),
				fights = tonumber(f[8]) or 0, total = tonumber(f[9]) or 0, hc = f[10] == "1",
			}
			d.count = d.count + 1
		elseif kind == "S" and f[2] and f[3] then
			local bySize = d.parses[f[2]] or {}
			d.parses[f[2]] = bySize
			local cells = {}
			for idx, pct, h in (f[4] or ""):gmatch("(%d+):([%d%.]+)(h?)") do
				local boss = d.bosses[(tonumber(idx) or -1) + 1]
				if boss then cells[#cells + 1] = { boss = boss, i = tonumber(idx), pct = tonumber(pct) or 0, hc = h == "h" } end
			end
			table.sort(cells, function(a, b) return a.pct > b.pct end)
			bySize[f[3]] = cells
		end
	end
	if not seenHead or not d.t then return nil, "That is not an Okanvil ranking export." end
	if d.count == 0 then return nil, "The export has no players in it." end
	return d
end

-- ------------------------------------------------------------
-- The stored ranking, parsed once per change.
-- ------------------------------------------------------------
local cache, cacheText

function R.Data()
	local s = db()
	if not (s and s.text) then return nil end
	if cacheText ~= s.text then
		cache = R.Parse(s.text)
		cacheText = s.text
	end
	return cache
end

function R.Stamp()
	local s = db()
	return s and s.t or 0
end

-- The period shown when none is picked: all time if the export has it.
function R.DefaultPeriod()
	local d = R.Data()
	if not d then return "all" end
	for _, p in ipairs(d.periods) do if p == "all" then return p end end
	return d.periods[1] or "all"
end

function R.HasPeriod(period)
	local d = R.Data()
	if not d then return false end
	for _, p in ipairs(d.periods) do if p == period then return true end end
	return false
end

-- The board, a player's place on it, and how far they moved since the ranking
-- before this one (nil = no earlier ranking to compare, "new" = not on it then).
function R.Board(size, kind, period)
	local d = R.Data()
	return d and d.boards[boardKey(period or R.DefaultPeriod(), size, kind)] or nil
end

function R.Move(size, kind, key, rank, period)
	local s = db()
	local prev = s and s.prev and s.prev[boardKey(period or R.DefaultPeriod(), size, kind)]
	if not prev then return nil end
	local was = prev[key]
	if not was then return "new" end
	return was - rank
end

-- Find a player on a board by toon name, then by their main (an alt's own name
-- is not on the board: the site files a person under their main). exact = the
-- toon's own name only, for a card that shows that character's numbers.
function R.Find(size, kind, name, period, exact)
	local list = R.Board(size, kind, period)
	if not list then return nil end
	local keys = { R.Norm(name) }
	local main = not exact and Okanvil.U and Okanvil.U.mainOf and Okanvil.U.mainOf(name)
	if main then keys[2] = R.Norm(main) end
	for _, k in ipairs(keys) do
		for i, p in ipairs(list) do
			if p.key == k then return p, i, #list end
		end
	end
	return nil
end

function R.Parses(size, name)
	local d = R.Data()
	return d and d.parses[size] and d.parses[size][R.Norm(name)] or nil
end

-- ------------------------------------------------------------
-- Store a ranking. The ranks of the one it replaces are kept for the arrows.
-- ------------------------------------------------------------
local function store(text, by, t)
	local s = db()
	local old = R.Data()
	if old then
		local prev = {}
		for key, list in pairs(old.boards) do
			local m = {}
			for i, p in ipairs(list) do m[p.key] = i end
			prev[key] = m
		end
		s.prev = prev
	end
	s.text, s.by, s.t, s.at = text, by, t, time()
	cache, cacheText = nil, nil
	if R.onChange then R.onChange() end
end

local function payload()
	local s = db()
	if not (s and s.text) then return nil end
	return "BY," .. (s.by or "") .. "\n" .. s.text
end

-- Officer import from the site. Returns the player count, or nil + reason.
function R.Import(text)
	if not (Okanvil.U and Okanvil.U.canSeePrio and Okanvil.U.canSeePrio()) then
		return nil, "Only officers can import the ranking."
	end
	text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local d, err = R.Parse(text)
	if not d then return nil, err end
	if d.t < R.Stamp() then return nil, "That export is older than the ranking you have." end
	store(text, UnitName("player"), d.t)
	Okanvil:Trace("RANK", ("import t=%d players=%d"):format(d.t, d.count))
	local p = payload()
	if p and Okanvil.Comms.SendBig then Okanvil.Comms.SendBig("RANK", p, "GUILD") end
	return d.count
end

-- ------------------------------------------------------------
-- Guild sync
-- ------------------------------------------------------------
local Comms = Okanvil.Comms
local asked = false
local offer, offerT = nil, 0
local lastSent = {}

local function active()
	return IsInGuild and IsInGuild() and Okanvil:ModuleActive(MODULE)
end

function R.AskGuild()
	if asked or not active() then return end
	if InCombatLockdown and InCombatLockdown() then return end
	asked = true
	Comms.SendGuild("RKQ", R.Stamp())
	Okanvil:Trace("RANK", "asked the guild, have t=" .. R.Stamp())
end

Comms.On("RKQ", function(sender, t)
	if sender == UnitName("player") or not active() then return end
	local mine = R.Stamp()
	if mine <= (tonumber(t) or 0) then return end
	-- spread the answers so everyone holding it doesn't whisper in the same second
	Comms.After(0.5 + math.random() * 2.5, function()
		Comms.Whisper("RKH", sender, mine)
	end)
end)

Comms.On("RKH", function(sender, t)
	t = tonumber(t) or 0
	if t <= R.Stamp() or t <= offerT then return end
	local first = (offer == nil)
	offer, offerT = sender, t
	if not first then return end
	Comms.After(OFFER_WAIT, function()
		local who = offer
		offer, offerT = nil, 0
		if who then Comms.Whisper("RKG", who) end
	end)
end)

Comms.On("RKG", function(sender)
	if not active() then return end
	if InCombatLockdown and InCombatLockdown() then return end
	local now = time()
	if lastSent[sender] and now - lastSent[sender] < SEND_GAP then return end
	local p = payload()
	if not p then return end
	lastSent[sender] = now
	Comms.SendBig("RANK", p, "WHISPER", sender)
	Okanvil:Trace("RANK", "sent the ranking to " .. sender)
end)

Comms.OnBig("RANK", function(sender, text)
	if sender == UnitName("player") or not active() then return end
	local d = R.Parse(text)
	if not d then return end
	local by = d.by or ""
	if by == "" or not Okanvil.U.canSeePrio(by) then
		Okanvil:Trace("RANK", ("dropped from %s: imported by %s, not an officer"):format(sender, by))
		return
	end
	if d.t <= R.Stamp() then return end
	-- keep the site text alone; the BY line is put back when we pass it on
	store((text:gsub("^BY,[^\n]*\n", "")), by, d.t)
	Okanvil:Trace("RANK", ("got t=%d from %s (by %s)"):format(d.t, sender, by))
end)

do
	-- Ask once per session, after the roster is in (canSeePrio reads it) and
	-- out of combat.
	local f = CreateFrame("Frame")
	f:RegisterEvent("GUILD_ROSTER_UPDATE")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function()
		if asked then f:UnregisterAllEvents(); return end
		local ok, err = pcall(R.AskGuild)
		if not ok then Okanvil:Err("Ranking sync", err) end
	end)
end

-- ------------------------------------------------------------
-- Player tooltip: the boards they are on, then their best bosses.
-- ------------------------------------------------------------
local TIP_BOSSES = 5

-- wow-logs' percentile colours
function R.PctColor(p)
	p = p or 0
	if p >= 100 then return 0.898, 0.800, 0.502 end
	if p >= 99 then return 0.886, 0.408, 0.659 end
	if p >= 95 then return 1.000, 0.502, 0.000 end
	if p >= 75 then return 0.639, 0.208, 0.933 end
	if p >= 50 then return 0.000, 0.439, 1.000 end
	if p >= 25 then return 0.118, 1.000, 0.000 end
	return 0.502, 0.502, 0.502
end

-- "Lord Marrowgar" -> "Marrowgar", "Ignis the Furnace Master" -> "Ignis"
-- Names too long for a narrow column, by the name raiders use.
local SHORT = {
	["Blood Prince Council"] = "Princes",
	["Blood-Queen Lana'thel"] = "Blood Queen",
	["Valithria Dreamwalker"] = "Dreamwalker",
	["Icecrown Gunship Battle"] = "Gunship",
	["Gunship Battle"] = "Gunship",
	["Northrend Beasts"] = "Beasts",
	["Faction Champions"] = "Champions",
	["Twin Val'kyr"] = "Twins",
	["Assembly of Iron"] = "Iron Council",
	["Flame Leviathan"] = "Leviathan",
}

function R.ShortBoss(name)
	if SHORT[name] then return SHORT[name] end
	return (name:gsub("^Lord ", ""):gsub("^Lady ", ""):gsub("^Professor ", "")
		:gsub("^Deathbringer ", ""):gsub("^The ", ""):gsub(" the .*$", ""))
end
local shortBoss = R.ShortBoss

-- The hovered toon's own numbers only: an alt never shows its main's ranks.
local function addTooltip(tip, name)
	local d = R.Data()
	if not d then return end
	-- the size they rank in; 25 first
	local size, roles
	for _, sz in ipairs(R.SIZES) do
		local found = {}
		for _, k in ipairs(R.BOARDS) do
			local p, rank, of = R.Find(sz, k, name, nil, true)
			if p then found[#found + 1] = { kind = k, p = p, rank = rank, of = of } end
		end
		if #found > 0 then size, roles = sz, found; break end
	end
	if not size then
		for _, sz in ipairs(R.SIZES) do
			local p = R.Parses(sz, name)
			if p and #p > 0 then size = sz; break end
		end
	end
	if not size then return end
	local parses = R.Parses(size, name)

	tip:AddLine(" ")
	if roles then
		table.sort(roles, function(a, b) return a.p.pts > b.p.pts end)
		for i = 1, math.min(2, #roles) do
			local r = roles[i]
			local left = ("%s #%d |cff8a8d93/ %d  %sm|r"):format(R.BOARD_LABEL[r.kind], r.rank, r.of, size)
			if i == 1 then
				tip:AddDoubleLine(left, ("%.1f"):format(r.p.pts), 1, 0.82, 0, 1, 0.82, 0)
			else
				tip:AddDoubleLine(left, ("%.1f"):format(r.p.pts), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
			end
		end
	else
		tip:AddLine(("Ranking  |cff8a8d93%sm|r"):format(size), 1, 0.82, 0)
	end
	if parses then
		for i = 1, math.min(TIP_BOSSES, #parses) do
			local c = parses[i]
			local rr, gg, bb = R.PctColor(c.pct)
			tip:AddDoubleLine(shortBoss(c.boss) .. (c.hc and " |cffff8000H|r" or ""),
				("%d"):format(math.floor(c.pct)), 0.9, 0.9, 0.9, rr, gg, bb)
		end
	end
	tip:Show()
end

GameTooltip:HookScript("OnTooltipSetUnit", function(tip)
	if not (Okanvil.db and active()) then return end
	local _, unit = tip:GetUnit()
	if not (unit and UnitIsPlayer(unit)) then return end
	local name = UnitName(unit)
	if not name then return end
	local ok, err = pcall(addTooltip, tip, name)
	if not ok then Okanvil:Err("Ranking tooltip", err) end
end)
