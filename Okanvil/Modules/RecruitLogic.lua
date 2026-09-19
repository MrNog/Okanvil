-- ============================================================
-- Recruit -- PURE logic (NO WoW API). Unit-testable.
-- Loaded before Recruit.lua.
-- ============================================================

RecruitLogic = RecruitLogic or {}

-- Damerau-Levenshtein distance (counts an adjacent transposition as 1, so it
-- catches common typos like "guidl" -> "guild" and "jpin" -> "join").
local function editDistance(a, b)
	local la, lb = #a, #b
	if math.abs(la - lb) > 1 then
		return 2
	end
	local d = {}
	for i = 0, la do
		d[i] = {}
		d[i][0] = i
	end
	for j = 0, lb do
		d[0][j] = j
	end
	for i = 1, la do
		for j = 1, lb do
			local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
			d[i][j] = math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
			if i > 1 and j > 1 and a:sub(i, i) == b:sub(j - 1, j - 1) and a:sub(i - 1, i - 1) == b:sub(j, j) then
				d[i][j] = math.min(d[i][j], d[i - 2][j - 2] + 1)
			end
		end
	end
	return d[la][lb]
end

-- does `msg` contain ANY of the comma-separated keywords in `list`?
-- Exact substring match, PLUS a 1-char fuzzy match per word for keywords of
-- length >= 4 (so "jpin" still matches "join", "guidl" matches "guild", ...).
function RecruitLogic.matchList(msg, list)
	if not msg or msg == "" or not list or list == "" then
		return false
	end
	local lower = string.lower(msg)
	for raw in string.gmatch(list, "[^,]+") do
		local kw = raw:gsub("^%s+", ""):gsub("%s+$", ""):lower()
		if kw ~= "" then
			if string.find(lower, kw, 1, true) then
				return true
			end
			if #kw >= 4 then
				for word in string.gmatch(lower, "%a+") do
					if math.abs(#word - #kw) <= 1 and editDistance(word, kw) <= 1 then
						return true
					end
				end
			end
		end
	end
	return false
end

-- Which auto-reply rule answers this whisper? Rules are tried in order and the
-- FIRST match wins -- two rules matching one whisper send one reply, not two, and
-- the order in the list is the tie-break you control.
--
-- A rule with no keywords of its own answers the SAME words that trigger an
-- invite (db.keywords). There used to be a second keyword box per rule, seeded
-- from db.keywords, so the identical list sat in two places that had to be kept
-- in step by hand -- and when they drifted, the reply stopped going to people
-- who were still being invited.
-- Returns the rule and its index, or nil.
function RecruitLogic.matchReply(db, msg)
	for i, r in ipairs(db.replies or {}) do
		local kw = (r.keywords and r.keywords ~= "") and r.keywords or db.keywords
		if r.enabled ~= false and r.text and r.text ~= ""
			and RecruitLogic.matchList(msg, kw) then
			return r, i
		end
	end
	return nil
end

-- Pure decision: what should happen for one whisper?
--   db  = config (keywords, replies, autoInvite, repliesNeedActive,
--                 repliesSkipGroup, replyCooldown, inviteCooldown, blacklist)
--   ctx = { known=bool, now=number, lastInvite=num|nil, lastReply=num|nil,
--           isEcho=bool, active=bool, inGroup=bool }
-- returns { invite=bool, reply=string|nil, ruleIndex=number|nil }
--
-- Invite and reply are decided INDEPENDENTLY: answering "what's the discord?"
-- must not drag a guild invite along with it, and inviting someone who only said
-- "inv" must not require a reply rule to exist.
function RecruitLogic.decide(db, msg, ctx)
	local out = { invite = false, reply = nil }
	if ctx.isEcho or ctx.known then
		return out
	end
	-- block words win over everything: gold sellers / beggars / ads are ignored
	-- even when they include an invite keyword ("inv pls i pay 10 gold").
	if db.blacklist and db.blacklist ~= "" and RecruitLogic.matchList(msg, db.blacklist) then
		return out
	end

	-- ---- invite ----
	if db.autoInvite and RecruitLogic.matchList(msg, db.keywords) then
		if not (ctx.lastInvite and (ctx.now - ctx.lastInvite) <= (db.inviteCooldown or 300)) then
			out.invite = true
		end
	end

	-- ---- reply ----
	-- Two guards, both independent of the invite. The group one is what keeps the
	-- Discord link from going out to a pug who asks for it mid-raid.
	local repliesOk = true
	if db.repliesNeedActive ~= false and not ctx.active then
		repliesOk = false
	end
	if db.repliesSkipGroup ~= false and ctx.inGroup then
		repliesOk = false
	end
	if repliesOk and not (ctx.lastReply and (ctx.now - ctx.lastReply) <= (db.replyCooldown or 600)) then
		local rule, idx = RecruitLogic.matchReply(db, msg)
		if rule then
			out.reply = rule.text
			out.ruleIndex = idx
		end
	end
	return out
end
