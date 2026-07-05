-- ============================================================
-- Okanvil -- Invite (native core module).
-- Tools to form a raid/party fast: mass-invite online guildies (all, by rank,
-- or from a saved list), a keyword whisper-invite (whisper "inv" -> pulled into
-- YOUR group), and an opt-in "auto-invite these people when they log in".
-- Parties auto-convert to raid past 5; declined/offline are retried on a cooldown.
--
-- 3.3.5a API: InviteUnit, GetNumRaidMembers/GetNumPartyMembers, ConvertToRaid,
-- GetGuildRosterInfo, GuildRoster. No retail C_PartyInfo.
-- ============================================================

local Okanvil = Okanvil
local I = {}
Okanvil.Invite = I

-- ------------------------------------------------------------
-- DB
-- ------------------------------------------------------------
local function db()
	local d = Okanvil.db
	d.invite = d.invite or {}
	local iv = d.invite
	if iv.keyword == nil then iv.keyword = "inv" end
	if iv.whisperInvite == nil then iv.whisperInvite = false end
	if iv.guildInvite == nil then iv.guildInvite = false end   -- keyword in /guild chat
	if iv.retry == nil then iv.retry = true end
	if iv.retryCooldown == nil then iv.retryCooldown = 30 end
	if iv.autoAssign == nil then iv.autoAssign = true end  -- move to comp group as they join
	iv.ranks = iv.ranks or {}          -- rankIndex(number) -> true = include when "invite by rank"
	-- iv.lists: name -> { members = { {name=, group=}, ... } }. Legacy plain-array
	-- lists ({ "A", "B" }) are auto-migrated to this shape on first read.
	iv.lists = iv.lists or {}
	for k, v in pairs(iv.lists) do
		if v[1] ~= nil and v.members == nil then          -- old plain-array list
			local members = {}
			for _, n in ipairs(v) do members[#members + 1] = { name = n } end
			iv.lists[k] = { members = members }
		end
	end
	iv.autoLoginList = iv.autoLoginList or ""  -- which saved list is armed for on-login invite ("" = off)
	return iv
end

-- members of a saved list (always the {name=,group=} shape)
local function listMembers(iv, listName)
	local l = iv.lists[listName]
	return l and l.members or nil
end
I.ListMembers = function(listName) return listMembers(db(), listName) end

-- list names (sorted) for a picker/dropdown
function I.ListNames()
	local out = {}
	for k in pairs(db().lists) do out[#out + 1] = k end
	table.sort(out)
	return out
end

-- is `name` a member of this list?
function I.IsInList(listName, name)
	local members = listMembers(db(), listName)
	if not members then return false end
	for _, m in ipairs(members) do if m.name == name then return true end end
	return false
end

-- toggle a roster name in/out of the list (used by the roster picker checkboxes)
function I.ToggleInList(listName, name)
	if I.IsInList(listName, name) then I.RemoveFromList(listName, name)
	else I.AddToList(listName, name) end
end

-- comp grouped for display: returns an ordered array of
--   { group = <n or nil>, names = { "A", "B", ... } }
-- groups first (1..8, in order), then an "ungrouped" bucket last.
function I.ListGrouped(listName)
	local members = listMembers(db(), listName)
	if not members then return {} end
	local byGroup, ungrouped = {}, {}
	for _, m in ipairs(members) do
		if m.group then
			byGroup[m.group] = byGroup[m.group] or {}
			table.insert(byGroup[m.group], m.name)
		else
			ungrouped[#ungrouped + 1] = m.name
		end
	end
	local out = {}
	for g = 1, 8 do
		if byGroup[g] then out[#out + 1] = { group = g, names = byGroup[g] } end
	end
	if #ungrouped > 0 then out[#out + 1] = { group = nil, names = ungrouped } end
	return out
end
I.db = db

local function Print(msg) Okanvil:Print(msg) end

-- ------------------------------------------------------------
-- group helpers
-- ------------------------------------------------------------
local function groupSize()
	local r = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	if r > 0 then return r, true end
	local p = (GetNumPartyMembers and GetNumPartyMembers()) or 0
	return p + (p > 0 and 1 or 0), false   -- party count includes you when non-empty
end

-- is `name` already in my group (party or raid)?
local function inMyGroup(name)
	local r = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	if r > 0 then
		for i = 1, r do if UnitName("raid" .. i) == name then return true end end
		return false
	end
	local p = (GetNumPartyMembers and GetNumPartyMembers()) or 0
	for i = 1, p do if UnitName("party" .. i) == name then return true end end
	return name == UnitName("player")
end

-- Send one invite (guarded). Tracks pending invites for retry. Auto-converts to
-- raid when the group would exceed 5.
local pending = {}   -- name -> GetTime() when we last invited (retry cooldown)
local function inviteOne(name)
	if not name or name == "" then return false end
	name = (name:gsub("%-.*$", ""))     -- strip realm
	if name == UnitName("player") then return false end
	if inMyGroup(name) then return false end
	-- convert to raid BEFORE we overflow a full party
	local size = groupSize()
	if size >= 5 and (GetNumRaidMembers and GetNumRaidMembers() == 0) and ConvertToRaid then
		ConvertToRaid()
	end
	if InviteUnit then InviteUnit(name) else return false end
	pending[name] = GetTime and GetTime() or 0
	return true
end
I.InviteOne = inviteOne

-- Invite a plain list of names. Returns how many invites were sent.
function I.InviteNames(names)
	if not names then return 0 end
	local sent = 0
	for _, n in ipairs(names) do
		if inviteOne(n) then sent = sent + 1 end
	end
	if sent > 0 then Print("Invited " .. sent .. " player(s).") end
	if I.onChange then I.onChange() end
	return sent
end

-- ------------------------------------------------------------
-- roster scan: walk online guildies, optionally filtered by included ranks.
-- rankFilter=nil -> everyone online. Returns a list of {name, rankIndex, rank}.
-- ------------------------------------------------------------
local function onlineGuildies(rankFilter)
	local out = {}
	if not (IsInGuild and IsInGuild()) then return out end
	if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
	local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
	local me = UnitName and UnitName("player")
	for i = 1, total do
		local name, rank, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
		if name and online and name ~= me then
			name = (name:gsub("%-.*$", ""))
			if (not rankFilter) or rankFilter[rankIndex] then
				out[#out + 1] = { name = name, rankIndex = rankIndex or 99, rank = rank or "" }
			end
		end
	end
	return out
end
I.OnlineGuildies = onlineGuildies

-- Invite every online guildie (skips grouped). One button.
function I.InviteGuildOnline()
	if GuildRoster then GuildRoster() end
	local list = onlineGuildies(nil)
	local names = {}
	for _, m in ipairs(list) do names[#names + 1] = m.name end
	return I.InviteNames(names)
end

-- Invite online guildies whose rankIndex is in the ticked set (iv.ranks).
function I.InviteByRank()
	local iv = db()
	local any = false
	for _, v in pairs(iv.ranks) do if v then any = true break end end
	if not any then Print("Pick at least one rank first."); return 0 end
	if GuildRoster then GuildRoster() end
	local list = onlineGuildies(iv.ranks)
	local names = {}
	for _, m in ipairs(list) do names[#names + 1] = m.name end
	return I.InviteNames(names)
end

-- The list currently "loaded" for group auto-assignment: name -> desired group.
-- Set when you invite a list; used as members accept (RAID_ROSTER_UPDATE).
local activeComp = nil    -- { [nameLower] = group, listName = ..., raw = members }

-- Invite everyone on a saved list. Also arms group auto-assignment from that
-- list's comp, so people are moved to their group as they accept.
function I.InviteList(listName)
	local iv = db()
	local members = listMembers(iv, listName)
	if not members or #members == 0 then Print("List '" .. tostring(listName) .. "' is empty."); return 0 end
	I.LoadComp(listName)         -- arm auto-assign for this comp
	local names = {}
	for _, m in ipairs(members) do names[#names + 1] = m.name end
	return I.InviteNames(names)
end

-- Arm the group map from a saved list (so auto-assign + Arrange use it).
function I.LoadComp(listName)
	local iv = db()
	local members = listMembers(iv, listName)
	if not members then activeComp = nil; return end
	local map = { listName = listName, raw = members }
	for _, m in ipairs(members) do if m.group then map[m.name:lower()] = m.group end end
	activeComp = map
end

-- ------------------------------------------------------------
-- Group assignment (SetRaidSubgroup) -- put raiders into their comp group.
-- Only works in a raid; needs group lead/assist. Arrange() does a full pass over
-- everyone currently in the raid; assignOne() handles a single joiner.
-- ------------------------------------------------------------
local function raidIndexOf(name)
	local n = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	for i = 1, n do
		local rn, _, subgroup = GetRaidRosterInfo(i)
		if rn == name then return i, subgroup end
	end
	return nil
end

local function assignOne(name)
	if not activeComp then return end
	local want = activeComp[name:lower()]
	if not want or want < 1 or want > 8 then return end
	local idx, cur = raidIndexOf(name)
	if not idx or cur == want then return end
	if SetRaidSubgroup then SetRaidSubgroup(idx, want) end
end

-- full pass: move every raider we have a comp group for. Safe to click repeatedly.
function I.Arrange()
	if not activeComp then Print("No comp loaded -- invite a saved list first."); return end
	if (GetNumRaidMembers and GetNumRaidMembers() or 0) == 0 then Print("Not in a raid yet."); return end
	local n = GetNumRaidMembers()
	local moved = 0
	for i = 1, n do
		local rn = GetRaidRosterInfo(i)
		if rn then
			local want = activeComp[rn:lower()]
			if want then
				local _, cur = raidIndexOf(rn)
				if cur ~= want and SetRaidSubgroup then SetRaidSubgroup(i, want); moved = moved + 1 end
			end
		end
	end
	Print("Arranged " .. moved .. " raider(s) into comp groups.")
end

-- ------------------------------------------------------------
-- saved lists (members = { {name=, group=}, ... })
-- ------------------------------------------------------------
function I.SaveList(listName, members)
	if not listName or listName == "" then return end
	local iv = db()
	iv.lists[listName] = { members = members or {} }
	if I.onChange then I.onChange() end
end

function I.AddToList(listName, name, group)
	if not listName or not name or name == "" then return end
	local iv = db()
	local l = iv.lists[listName]; if not l then l = { members = {} }; iv.lists[listName] = l end
	name = (name:gsub("%-.*$", ""))
	for _, m in ipairs(l.members) do if m.name == name then if group then m.group = group end return end end
	l.members[#l.members + 1] = { name = name, group = group }
	if I.onChange then I.onChange() end
end

function I.RemoveFromList(listName, name)
	local iv = db()
	local l = iv.lists[listName]; if not l then return end
	for i = #l.members, 1, -1 do if l.members[i].name == name then table.remove(l.members, i) end end
	if I.onChange then I.onChange() end
end

function I.DeleteList(listName)
	local iv = db()
	iv.lists[listName] = nil
	if iv.autoLoginList == listName then iv.autoLoginList = "" end
	if activeComp and activeComp.listName == listName then activeComp = nil end
	if I.onChange then I.onChange() end
end

-- ------------------------------------------------------------
-- JSON / paste import -- lenient. Handles:
--   * Composition/Raid-Helper exports: a "slots":[ {..,"name":"X",..}, .. ] array
--     (we take ONLY slot names, never the classes[]/groups[] name fields).
--   * a plain comma / newline / space separated list of names.
-- Names are cleaned like the RATS website normName: strip [..] and (..) tags,
-- take the first of "A/B" or "A|B" or "A,B", drop trailing emoji/flags, keep the
-- leading letter run. e.g. "Shockaa[SHAKA]" -> Shockaa, "Lecoque/Chims" -> Lecoque,
-- "Franzherman<flag>" -> Franzherman. De-dupes, WoW-capitalizes.
-- ------------------------------------------------------------
local function cleanName(raw)
	if not raw or raw == "" then return nil end
	local n = raw
	n = n:gsub("%[.-%]", ""):gsub("%(.-%)", "")   -- drop [tags] and (notes)
	n = n:gsub("%-.*$", "")                          -- drop realm
	n = n:match("^%s*([^/|,]+)") or n                -- first of A/B, A|B, A,B
	-- keep only the leading run of letters (ASCII + Latin-1 accented bytes),
	-- which strips trailing emoji/flag codepoints and spaces
	n = n:match("([A-Za-z\192-\255]+)") or ""
	if #n < 2 then return nil end
	return n:sub(1, 1):upper() .. n:sub(2):lower()
end

-- Parse into MEMBERS: { {name=, group=}, ... }. `group` is the raid subgroup 1-5
-- (nil if unknown). De-dupes by name. Handles the composition export's groupNumber
-- and slotNumber, a generic names JSON, OR a pasted grid where each LINE is a group
-- (line 1 = group 1, etc.) with names separated by commas; "-" = empty slot.
function I.ParseMembers(text)
	if not text or text == "" then return {} end
	local seen, out = {}, {}
	local function add(raw, group)
		local n = cleanName(raw)
		if not n then return end
		local key = n:lower()
		if seen[key] then
			if group and not seen[key].group then seen[key].group = group end
			return
		end
		local m = { name = n, group = group }
		seen[key] = m; out[#out + 1] = m
	end

	-- 1) Composition/Raid-Helper: pull name + groupNumber from each slot object ONLY.
	local slotsBlock = text:match('"slots"%s*:%s*(%b[])')
	if slotsBlock then
		for obj in slotsBlock:gmatch("%b{}") do
			local nm = obj:match('"name"%s*:%s*"([^"]+)"')
			local grp = tonumber(obj:match('"groupNumber"%s*:%s*(%d+)'))
			if nm then add(nm, grp) end
		end
		if #out > 0 then return out end
	end

	-- 2) generic JSON name-ish keys (no group info)
	local hadField = false
	for _, field in ipairs({ "name", "character", "char", "player", "user", "nickname" }) do
		for v in text:gmatch('"' .. field .. '"%s*:%s*"([^"]+)"') do
			hadField = true; add(v, nil)
		end
	end
	if hadField and #out > 0 then return out end

	-- 3) plain TEXT list -- any Raid-Helper "Players" export (space / , / ; delimited,
	-- horizontal or vertical). We do NOT infer groups from text layout: horizontal vs
	-- vertical grids are indistinguishable from raw text, so a wrong guess would put
	-- people in the wrong raid group. Use the JSON export when you want group assignment.
	-- "-" = empty slot (skipped).
	for tok in text:gmatch("[^%s,;]+") do
		if tok ~= "-" then add(tok, nil) end
	end
	return out
end

-- back-compat: names-only view of ParseMembers
function I.ParseNames(text)
	local out = {}
	for _, m in ipairs(I.ParseMembers(text)) do out[#out + 1] = m.name end
	return out
end

-- import `text` into a named list (merges, de-dupes, keeps group numbers).
-- If `replace` is true the list is overwritten with exactly the imported comp.
function I.ImportToList(listName, text, replace)
	local members = I.ParseMembers(text)
	if #members == 0 then Print("No names found in that text."); return 0 end
	if replace then I.SaveList(listName, {}) end
	for _, m in ipairs(members) do I.AddToList(listName, m.name, m.group) end
	local withGroups = 0
	for _, m in ipairs(members) do if m.group then withGroups = withGroups + 1 end end
	Print("Imported " .. #members .. " name(s) into '" .. listName .. "'"
		.. (withGroups > 0 and (" (" .. withGroups .. " with groups).") or "."))
	return #members
end

-- ------------------------------------------------------------
-- events: keyword whisper-invite, decline/offline retry, on-login auto-invite
-- ------------------------------------------------------------
-- build patterns from WoW globals so join/decline detection is locale-safe
local function mkPat(fmt) local p = (fmt or ""):gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"); return (p:gsub("%%s", "(.+)")) end
local PAT_DECLINE = ERR_INVITE_PLAYER_S and mkPat(ERR_DECLINE_GROUP_S or "%s declines your group invitation.")
local PAT_GUILD_ONLINE = ERR_FRIEND_ONLINE_SS and mkPat(ERR_FRIEND_ONLINE_SS)

-- shared keyword-invite: if `sender` said the keyword, pull them into the group.
local function keywordInvite(msg, sender, where)
	local iv = db()
	if not sender or not msg then return end
	local kw = (iv.keyword or "inv"):lower()
	if kw == "" then return end
	if not msg:lower():find(kw, 1, true) then return end
	local clean = (sender:gsub("%-.*$", ""))
	if inviteOne(clean) then
		Print("Invited " .. clean .. " (" .. (where or "chat") .. " keyword).")
		if I.onChange then I.onChange() end
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_WHISPER")
ev:RegisterEvent("CHAT_MSG_GUILD")     -- keyword in guild chat
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:SetScript("OnEvent", function(_, event, arg1, arg2)
	local iv = db()
	if event == "CHAT_MSG_WHISPER" then
		if iv.whisperInvite then keywordInvite(arg1, arg2, "whisper") end
		return
	end
	if event == "CHAT_MSG_GUILD" then
		if iv.guildInvite then keywordInvite(arg1, arg2, "guild") end
		return
	end
	if event == "CHAT_MSG_SYSTEM" then
		local m = arg1 or ""
		-- retry on decline
		if iv.retry and PAT_DECLINE then
			local who = m:match(PAT_DECLINE)
			if who then
				who = (who:gsub("%-.*$", ""))
				-- re-arm: clear cooldown so the OnUpdate retry can re-invite
				pending[who] = (GetTime and GetTime() or 0) - (iv.retryCooldown or 30) + 5
				return
			end
		end
		-- auto-invite armed list members when they come online (friend-online line)
		if iv.autoLoginList ~= "" and PAT_GUILD_ONLINE then
			local who = m:match(PAT_GUILD_ONLINE)
			if who then
				who = (who:gsub("%-.*$", ""))
				local l = iv.lists[iv.autoLoginList]
				if l then
					for _, n in ipairs(l) do
						if n == who then
							if inviteOne(who) then Print("Auto-invited " .. who .. " (just logged in).") end
							break
						end
					end
				end
			end
		end
	end
end)

-- retry loop: re-invite pending names whose cooldown elapsed and who still aren't
-- grouped (covers declines + offline-then-online). Cheap 1s tick, only while we
-- actually have pending invites.
ev:SetScript("OnUpdate", function(self, e)
	self._t = (self._t or 0) + e
	if self._t < 1 then return end
	self._t = 0
	local iv = Okanvil.db and Okanvil.db.invite
	if not iv or not iv.retry then return end
	local now = GetTime and GetTime() or 0
	local cd = iv.retryCooldown or 30
	for name, t in pairs(pending) do
		if inMyGroup(name) then
			pending[name] = nil
		elseif (now - t) >= cd then
			if InviteUnit then InviteUnit(name) end
			pending[name] = now
		end
	end
end)

-- On-login auto-invite: watch GUILD roster online flips (more reliable than the
-- friend line for guildies). Poll the roster diff on GUILD_ROSTER_UPDATE.
local wasOnline = {}
local gev = CreateFrame("Frame")
gev:RegisterEvent("GUILD_ROSTER_UPDATE")
gev:SetScript("OnEvent", function()
	local iv = Okanvil.db and Okanvil.db.invite
	if not iv or iv.autoLoginList == "" then return end
	local l = iv.lists[iv.autoLoginList]
	local members = l and l.members
	if not members or #members == 0 then return end
	-- build a quick name->online map
	local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
	local online = {}
	for i = 1, total do
		local name, _, _, _, _, _, _, _, isOn = GetGuildRosterInfo(i)
		if name then online[(name:gsub("%-.*$", ""))] = isOn and true or false end
	end
	for _, m in ipairs(members) do
		local n = m.name
		local now = online[n]
		if now and wasOnline[n] == false then   -- just flipped offline->online
			if inviteOne(n) then Print("Auto-invited " .. n .. " (came online).") end
		end
		if now ~= nil then wasOnline[n] = now end
	end
end)

-- Auto-assign to comp group as people accept: when the raid roster changes and a
-- comp is loaded (via InviteList/LoadComp), move any raider we have a group for.
local rev = CreateFrame("Frame")
rev:RegisterEvent("RAID_ROSTER_UPDATE")
rev:SetScript("OnEvent", function()
	local iv = Okanvil.db and Okanvil.db.invite
	if not iv or not iv.autoAssign or not activeComp then return end
	if (GetNumRaidMembers and GetNumRaidMembers() or 0) == 0 then return end
	-- one pass: cheap, idempotent (assignOne skips anyone already in the right group)
	local n = GetNumRaidMembers()
	for i = 1, n do
		local rn = GetRaidRosterInfo(i)
		if rn then assignOne(rn) end
	end
end)
