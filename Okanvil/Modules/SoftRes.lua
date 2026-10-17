-- ============================================================
--  Okanvil -- SoftRes: the raid's soft reserves, and the hard-reserve lock.
--
--  Soft reserves come from softres.it: Export CSV, paste it on the Loot page.
--  With a list loaded, the roll manager shows who reserved each item, the MS
--  button calls a roll naming only those raiders, and a roll from anyone else
--  on that item is not recorded -- so "Award top roll" cannot hand a reserved
--  item to someone who never reserved it.
--
--  Hard reserves are the items on the PuG page's Reserves tab. Those are not
--  rolled at all: starting an MS/OS roll on one is refused, so a hard-reserved
--  item is never put up by a misclick.
--
--  Account-wide: the list belongs to the raid being run, not to a character,
--  and the master looter may swap toons between import and loot.
-- ============================================================

local SR = {}
Okanvil.SoftRes = SR

local function db()
	Okanvil.db.softres = Okanvil.db.softres or {}
	return Okanvil.db.softres
end

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function key(name) return (trim(name):gsub("%-.*$", "")):lower() end

-- One CSV line into fields. softres.it quotes a field that holds a comma (a
-- raider's note, usually) and doubles a quote inside one, so splitting on
-- commas alone would break those rows.
local function csvFields(line)
	local out, i, n = {}, 1, #line
	while i <= n + 1 do
		if line:sub(i, i) == '"' then
			local buf, j = {}, i + 1
			while j <= n do
				local c = line:sub(j, j)
				if c == '"' then
					if line:sub(j + 1, j + 1) == '"' then buf[#buf + 1] = '"'; j = j + 2
					else j = j + 1; break end
				else buf[#buf + 1] = c; j = j + 1 end
			end
			out[#out + 1] = table.concat(buf)
			-- skip to just past the next comma
			local comma = line:find(",", j, true)
			i = comma and comma + 1 or n + 2
		else
			local comma = line:find(",", i, true)
			if comma then
				out[#out + 1] = line:sub(i, comma - 1); i = comma + 1
			else
				out[#out + 1] = line:sub(i); i = n + 2
			end
		end
	end
	return out
end

-- The export's own column order, used when the header line was not pasted.
local DEFAULT_COLS = { "item name", "item id", "from", "raider name", "discord id",
	"discord name", "raider class", "raider spec", "raider note", "extra reserves", "date" }

-- "Death Knight" -> "DEATHKNIGHT", the token RAID_CLASS_COLORS is keyed by.
local function classToken(c)
	c = trim(c):upper():gsub("%s+", "")
	return c ~= "" and c or nil
end

-- Replace the loaded list with a softres.it CSV. Returns the number of items
-- and raiders read, or nil and the reason nothing was loaded.
function SR.Import(text)
	text = (text or ""):gsub("\r\n?", "\n")
	local col, items, names, players, rows = nil, {}, {}, {}, 0
	local bosses, order = {}, {}
	for line in text:gmatch("[^\n]+") do
		line = trim(line)
		if line ~= "" then
			local f = csvFields(line)
			if not col then
				local low = {}
				for i, v in ipairs(f) do low[trim(v):lower()] = i end
				if low["item id"] and low["raider name"] then
					col = low
				else
					col = {}
					for i, v in ipairs(DEFAULT_COLS) do col[v] = i end
				end
			end
			local id = tonumber(trim(f[col["item id"]] or ""))
			local who = trim(f[col["raider name"]] or "")
			if id and id > 0 and who ~= "" then
				rows = rows + 1
				if not items[id] then order[#order + 1] = id end
				local list = items[id] or {}
				items[id] = list
				local k = key(who)
				local found
				for _, e in ipairs(list) do if e.key == k then found = e; break end end
				if found then
					-- the same raider reserving the same item twice: one entry, counted
					found.count = found.count + 1
				else
					list[#list + 1] = {
						name = (who:gsub("%-.*$", "")), key = k,
						class = classToken(f[col["raider class"]] or ""),
						spec = trim(f[col["raider spec"]] or ""),
						note = trim(f[col["raider note"]] or ""),
						count = 1,
					}
				end
				names[id] = names[id] or trim(f[col["item name"]] or "")
				local from = trim(f[col["from"]] or "")
				if from ~= "" then bosses[id] = bosses[id] or from end
				players[k] = true
			end
		end
	end
	if rows == 0 then return nil, "No reserves found. Paste the CSV from softres.it (Export > CSV)." end
	local ni, np = SR._Store(items, names, time(), nil, bosses, order)
	-- The master looter or raid leader hands the list to the raid straight
	-- away, so nobody else has to paste it.
	if SR.CanShare() then SR.Share() end
	return ni, np
end

-- Keep a list, however it arrived. `from` is who sent it, nil for your own paste.
-- `bosses` (id -> the boss it drops from) and `order` (ids as the CSV listed
-- them) only come with a paste; a list received over comms has neither.
function SR._Store(items, names, at, from, bosses, order)
	local d = db()
	d.items, d.names, d.at, d.from = items, names, at, from
	d.bosses, d.order = bosses, order
	local ni, players = 0, {}
	for _, list in pairs(items) do
		ni = ni + 1
		for _, e in ipairs(list) do players[e.key] = true end
	end
	local np = 0
	for _ in pairs(players) do np = np + 1 end
	d.nItems, d.nPlayers = ni, np
	if SR.onChange then SR.onChange() end
	if SR.onPanel then SR.onPanel() end
	return ni, np
end

function SR.Clear()
	local d = db()
	d.items, d.names, d.at, d.from, d.nItems, d.nPlayers = nil, nil, nil, nil, nil, nil
	d.bosses, d.order = nil, nil
	if SR.onChange then SR.onChange() end
	if SR.onPanel then SR.onPanel() end
end

-- items, raiders, import time, who sent it -- or nil when nothing is loaded
function SR.Summary()
	local d = db()
	if not d.items then return nil end
	return d.nItems or 0, d.nPlayers or 0, d.at, d.from
end

-- ---- Sharing with the raid ----------------------------------------------
-- The master looter (or the raid leader) sends the list over addon messages,
-- and every raider with Okanvil gets the same [SR] tags without pasting.
-- Trust is by role, checked live on the receiving side: a list is taken only
-- from whoever is master looter or raid leader right now.
local function shortName(n) return n and (n:gsub("%-.*$", "")) or n end

local function isLeadOrML(who)
	who = shortName(who)
	if not who or who == "" then return false end
	local L = Okanvil.Loot
	local ml = L and L.MasterLooterName and L.MasterLooterName()
	if ml and shortName(ml):lower() == who:lower() then return true end
	for i = 1, (GetNumRaidMembers and GetNumRaidMembers() or 0) do
		local name, rank = GetRaidRosterInfo(i)
		if name and shortName(name):lower() == who:lower() then return rank == 2 end
	end
	if (GetNumRaidMembers() or 0) == 0 and (GetNumPartyMembers() or 0) > 0 then
		-- a party has no roster ranks; its leader is the one who can hand out loot
		if UnitIsPartyLeader and who:lower() == (UnitName("player") or ""):lower() then
			return UnitIsPartyLeader("player") and true or false
		end
		for i = 1, GetNumPartyMembers() do
			local u = "party" .. i
			if (UnitName(u) or ""):lower() == who:lower() then
				return UnitIsPartyLeader and UnitIsPartyLeader(u) and true or false
			end
		end
	end
	return false
end

SR.IsLeadOrML = isLeadOrML

function SR.CanShare()
	if not SR.Summary() then return false end
	local inGroup = (GetNumRaidMembers() or 0) > 0 or (GetNumPartyMembers() or 0) > 0
	return inGroup and isLeadOrML(UnitName("player"))
end

-- One line per reserver: id, count, name, class, spec, then the item name.
-- Tabs, not commas or pipes: an item name has commas, and Comms uses pipes.
local function serialize()
	local d = db()
	local out = { "SR1", tostring(d.at or time()) }
	for id, list in pairs(d.items or {}) do
		for _, e in ipairs(list) do
			out[#out + 1] = table.concat({ id, e.count or 1, e.name or "", e.class or "",
				e.spec or "", (d.names and d.names[id]) or "" }, "\t")
		end
	end
	return table.concat(out, "\n")
end

local function deserialize(text)
	local lines = {}
	for line in (text or ""):gmatch("[^\n]+") do lines[#lines + 1] = line end
	if lines[1] ~= "SR1" then return nil end
	local at = tonumber(lines[2]) or time()
	local items, names = {}, {}
	for i = 3, #lines do
		local id, count, name, class, spec, iname = lines[i]:match("^(%d+)\t(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
		id = tonumber(id)
		if id and name ~= "" then
			local list = items[id] or {}
			items[id] = list
			list[#list + 1] = { name = name, key = name:lower(), class = class ~= "" and class or nil,
				spec = spec, note = "", count = tonumber(count) or 1 }
			if iname ~= "" then names[id] = iname end
		end
	end
	return items, names, at
end

function SR.Share()
	local C = Okanvil.Comms
	if not (C and C.SendBig) then return false end
	return C.SendBig("SOFTRES", serialize())
end

local function sameList(items)
	local d = db()
	if not d.items then return false end
	local function flat(t)
		local out = {}
		for id, list in pairs(t) do
			for _, e in ipairs(list) do out[#out + 1] = id .. ":" .. e.key .. ":" .. (e.count or 1) end
		end
		table.sort(out)
		return table.concat(out, ",")
	end
	return flat(d.items) == flat(items)
end

local function onReceive(sender, text)
	sender = shortName(sender)
	if not sender or sender:lower() == (UnitName("player") or ""):lower() then return end
	if not isLeadOrML(sender) then return end
	local items, names, at = deserialize(text)
	if not items or not next(items) then return end
	if sameList(items) then return end
	local function take()
		local ni, np = SR._Store(items, names, at, sender)
		Okanvil:Print(("Soft reserves from %s: %d items, %d raiders."):format(sender, ni, np))
	end
	-- A list you already hold is replaced only if you say so; with none loaded
	-- there is nothing to lose.
	if SR.Summary() then
		Okanvil:Confirm(sender .. " sent the raid's soft reserves.\n|cff8a8d93Replace the list you have loaded?|r",
			"Replace", take)
	else
		take()
	end
end

do
	local C = Okanvil.Comms
	if C and C.OnBig then C.OnBig("SOFTRES", onReceive) end
end

local function idOf(item)
	if type(item) == "number" then return item end
	if type(item) == "string" then return tonumber(item:match("item:(%d+)")) end
	return nil
end

-- ---- Loot mode ------------------------------------------------------------
-- How tonight's loot is shared out, picked by the master looter:
--   "council"  loot council (and its priority list); soft reserves are ignored
--   "sr"       soft reserves: a softres.it CSV, "sr [item]" whispers, or the
--              pick window for raiders who run Okanvil; no council
--   "roll"     plain MS / OS rolls; no soft reserves, no council -- the default
-- A pick lasts one raid night (MODE_TTL); after that it is Roll again, so last
-- week's council night never comes back on its own. RatRoll (LITE) has no tiles
-- and is all about soft reserves, so its default is SR.
-- Hard reserves and reserved loot kinds (PuG page) apply in every mode.
local MODES = { council = true, sr = true, roll = true }
local MODE_TTL = 3 * 3600

-- Who sets the mode for the group: the master looter, or with no master loot
-- the group leader. Solo, you. Everyone else sees theirs, read-only.
local function shortName(n) return n and (n:gsub("%-.*$", "")) or n end
local function inGroup() return (GetNumRaidMembers() or 0) > 0 or (GetNumPartyMembers() or 0) > 0 end
local function setterName()
	local L = Okanvil.Loot
	local ml = L and L.MasterLooterName and L.MasterLooterName()
	if ml and ml ~= "" then return shortName(ml) end
	if (GetNumRaidMembers() or 0) > 0 then
		for i = 1, GetNumRaidMembers() do
			local name, rank = GetRaidRosterInfo(i)
			if rank == 2 then return shortName(name) end
		end
	elseif (GetNumPartyMembers() or 0) > 0 then
		if UnitIsPartyLeader("player") then return UnitName("player") end
		for i = 1, GetNumPartyMembers() do
			if UnitIsPartyLeader("party" .. i) then return shortName(UnitName("party" .. i)) end
		end
	end
	return nil
end
function SR.ModeSetter() return setterName() end
function SR.CanSetMode()
	if not inGroup() then return true end
	local who = setterName()
	return who == nil or who:lower() == (UnitName("player") or ""):lower()
end

local remote            -- { mode, from } as the setter sent it
local function ownMode()
	local d = db()
	if d.mode and d.modeAt and time() - d.modeAt < MODE_TTL then return d.mode end
	return Okanvil.LITE and "sr" or "roll"
end

function SR.Mode()
	-- in a group you follow the setter's mode, once it has told us
	if inGroup() and not SR.CanSetMode() and remote and remote.from == setterName() then
		return remote.mode
	end
	return ownMode()
end

local function sendMode()
	local C = Okanvil.Comms
	if C and C.Send and inGroup() and SR.CanSetMode() then C.Send("LOOTMODE", ownMode()) end
end

function SR.SetMode(m)
	if m ~= nil and not MODES[m] then return false end
	if not SR.CanSetMode() then
		Okanvil:Print("The loot mode is set by " .. (setterName() or "the master looter") .. ".")
		return false
	end
	m = m or "roll"
	local was = SR.Mode()
	db().mode, db().modeAt = m, time()
	-- Picking a reserve mode opens whispers; the first pull locks them again.
	if m == "sr" and was ~= m and SR.SetIntake and not SR.IntakeOpen() then SR.SetIntake(true) end
	-- Council IS council night, and every other mode ends it. Only the one who
	-- may run the council switches it; anyone else just changes their own view.
	local CC = Okanvil.Council
	if CC and CC.SetActive and CC.Enabled and CC.Enabled() and CC.MayRun and CC.MayRun() then
		local want = (m == "council")
		if (CC.active and true or false) ~= want then CC.SetActive(want) end
	end
	sendMode()
	if SR.onChange then SR.onChange() end
	if SR.onPanel then SR.onPanel() end
	local RM = Okanvil.RollMgr
	if RM and RM.Rebuild then
		local ok, err = pcall(RM.Rebuild)
		if not ok and Okanvil.Err then Okanvil:Err("SoftRes SetMode", err) end
	end
	return true
end

-- The setter's mode reaches everyone: LOOTMODE when it changes or when asked
-- (LOOTMODEQ, sent on joining a group and when the master looter changes).
local function repaint()
	if SR.onChange then pcall(SR.onChange) end
	if SR.onPanel then pcall(SR.onPanel) end
	local RM = Okanvil.RollMgr
	if RM and RM.Rebuild then pcall(RM.Rebuild) end
end
do
	local C = Okanvil.Comms
	if C and C.On then
		C.On("LOOTMODE", function(sender, mode)
			sender = shortName(sender)
			if not MODES[mode] or sender ~= setterName() then return end
			if remote and remote.mode == mode and remote.from == sender then return end
			remote = { mode = mode, from = sender }
			repaint()
		end)
		C.On("LOOTMODEQ", function() sendMode() end)
	end
	local f = CreateFrame("Frame")
	f:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
	f:RegisterEvent("PARTY_MEMBERS_CHANGED")
	f:RegisterEvent("RAID_ROSTER_UPDATE")
	local lastSetter, wasIn
	f:SetScript("OnEvent", function()
		local who, now = setterName(), inGroup()
		if who == lastSetter and now == wasIn then return end
		lastSetter, wasIn = who, now
		if not now then remote = nil; repaint(); return end
		if SR.CanSetMode() then sendMode()
		elseif C and C.Send then C.Send("LOOTMODEQ") end
		repaint()
	end)
end

-- Whether soft reserves count right now.
function SR.Active()
	return SR.Mode() == "sr"
end

-- Whether reserves are taken by whisper ("sr [item]") in this mode.
function SR.WhisperMode()
	return SR.Mode() == "sr"
end

-- Whether the loot council may be asked right now.
function SR.CouncilAllowed()
	return SR.Mode() == "council"
end

-- The raiders who reserved this item (id or link), in import order. Empty when
-- the item is not reserved, no list is loaded, or the mode ignores reserves.
function SR.For(item)
	if not SR.Active() then return {} end
	local id = idOf(item)
	local d = db()
	if not (id and d.items) then return {} end
	if d.items[id] then return d.items[id] end
	-- The heroic and normal copy of an item are two ids with one name, and in
	-- ICC or RS a raid kills bosses on either: a reserve is for the item, so it
	-- is matched by name too.
	local name = GetItemInfo(id) or (d.names or {})[id]
	if not name then return {} end
	for iid, list in pairs(d.items) do
		if ((d.names or {})[iid] or GetItemInfo(iid)) == name then return list end
	end
	return {}
end

-- ---- Reserves added one at a time (whispers, officer edits) ---------------
-- Same table an import fills, so tags, tooltips and the roll filter treat a
-- whispered reserve exactly like an imported one.

-- The item ids this raider has reserved, oldest first.
function SR.ReservesOf(name)
	local d, k, out = db(), key(name or ""), {}
	for _, id in ipairs(d.order or {}) do
		for _, e in ipairs((d.items or {})[id] or {}) do
			if e.key == k then out[#out + 1] = { id = id, at = e.at or 0 } end
		end
	end
	table.sort(out, function(a, b) return a.at < b.at end)
	local ids = {}
	for i, r in ipairs(out) do ids[i] = r.id end
	return ids
end

local function recount(d)
	local ni, players = 0, {}
	for _, list in pairs(d.items or {}) do
		ni = ni + 1
		for _, e in ipairs(list) do players[e.key] = true end
	end
	local np = 0
	for _ in pairs(players) do np = np + 1 end
	d.nItems, d.nPlayers = ni, np
	if SR.onChange then SR.onChange() end
	if SR.onPanel then SR.onPanel() end
end

function SR.AddReserve(name, class, id, itemName, boss)
	id = tonumber(id)
	if not (id and name and name ~= "") then return false end
	local d = db()
	d.items, d.names, d.order, d.bosses = d.items or {}, d.names or {}, d.order or {}, d.bosses or {}
	d.at = d.at or time()
	-- the other difficulty's copy already reserved: join that entry, one list per item
	if not d.items[id] then
		local nm = itemName or GetItemInfo(id)
		for iid in pairs(d.items) do
			if nm and (d.names[iid] or GetItemInfo(iid)) == nm then id = iid; break end
		end
	end
	local list = d.items[id]
	if not list then
		list = {}
		d.items[id] = list
		local listed = false
		for _, o in ipairs(d.order) do if o == id then listed = true; break end end
		if not listed then d.order[#d.order + 1] = id end
	end
	local k = key(name)
	for _, e in ipairs(list) do if e.key == k then return false end end
	list[#list + 1] = { name = (name:gsub("%-.*$", "")), key = k, class = class, spec = "", note = "",
		count = 1, at = time() }
	if itemName and itemName ~= "" then d.names[id] = d.names[id] or itemName end
	if boss and boss ~= "" then d.bosses[id] = d.bosses[id] or boss end
	recount(d)
	return true
end

-- Drop one reserve (id given) or all of this raider's. Returns the ids removed.
function SR.RemoveReserve(name, id)
	local d, k, gone = db(), key(name or ""), {}
	for iid, list in pairs(d.items or {}) do
		if not id or iid == tonumber(id) then
			for i = #list, 1, -1 do
				if list[i].key == k then table.remove(list, i); gone[#gone + 1] = iid end
			end
			if #list == 0 then d.items[iid] = nil end
		end
	end
	if #gone > 0 then recount(d) end
	return gone
end

-- Every reserved item id, in the CSV's order when there is one (a received
-- list has none, so it falls back to item name), with its boss and name.
function SR.All()
	local d = db()
	if not d.items then return {} end
	local out, seen = {}, {}
	for _, id in ipairs(d.order or {}) do
		if d.items[id] and not seen[id] then seen[id] = true; out[#out + 1] = id end
	end
	local rest = {}
	for id in pairs(d.items) do if not seen[id] then rest[#rest + 1] = id end end
	table.sort(rest, function(a, b) return ((d.names or {})[a] or "") < ((d.names or {})[b] or "") end)
	for _, id in ipairs(rest) do out[#out + 1] = id end
	local list = {}
	for _, id in ipairs(out) do
		list[#list + 1] = { id = id, boss = (d.bosses or {})[id], name = (d.names or {})[id] }
	end
	return list
end

function SR.IsReserved(item) return #SR.For(item) > 0 end

function SR.IsReserver(item, player)
	if not player then return false end
	local k = key(player)
	for _, e in ipairs(SR.For(item)) do if e.key == k then return true end end
	return false
end

local function classColor(token)
	local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
	if not c then return "|cffdcddde" end
	return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

-- "Mongoloide, Rellik x2" -- class-coloured for the screen, or plain for chat.
-- `max` caps how many are named; the rest become "+N", for a one-line row where
-- a long list would otherwise be cut off mid-name.
function SR.Names(item, plain, max)
	local out, list = {}, SR.For(item)
	for i, e in ipairs(list) do
		if max and i > max then break end
		local n = e.name .. (e.count > 1 and (" x" .. e.count) or "")
		out[#out + 1] = plain and n or (classColor(e.class) .. n .. "|r")
	end
	local s = table.concat(out, plain and ", " or "|cff6f7176, |r")
	local left = #list - #out
	if left > 0 then s = s .. (plain and (" +" .. left) or ("|cff8a8d93 +" .. left .. "|r")) end
	return s
end

-- Every reserver, one per line, for the item tooltip: class-coloured name, spec
-- and the raider's note from softres.it.
function SR.AddTooltip(tip, item)
	local list = SR.For(item)
	if #list == 0 then return end
	tip:AddLine(" ")
	tip:AddLine("Soft reserved (" .. #list .. ")", 0.88, 0.72, 0.38)
	for _, e in ipairs(list) do
		local n = classColor(e.class) .. e.name .. "|r" .. (e.count > 1 and (" x" .. e.count) or "")
		local extra = e.spec ~= "" and e.spec or ""
		if e.note ~= "" then extra = extra .. (extra ~= "" and " - " or "") .. e.note end
		tip:AddDoubleLine(n, extra, 1, 1, 1, 0.55, 0.55, 0.58)
	end
end

-- ---- Hard reserves ------------------------------------------------------
-- The PuG page's Reserves tab stores each item as the link it was clicked
-- from, or its bare name when the link was not cached. Match either.
function SR.IsHard(item)
	local P = Okanvil.PuG
	local pdb = P and P.DB and P.DB()
	local list = pdb and pdb.reserveItems
	if type(list) ~= "table" or #list == 0 or pdb.reserveNone then return false end
	local id = idOf(item)
	local name = type(item) == "string" and (item:match("%[(.-)%]") or GetItemInfo(item)) or nil
	if not name and id then name = GetItemInfo(id) end
	for _, v in ipairs(list) do
		local vid = idOf(v)
		if vid and id and vid == id then return true end
		local vname = v:match("%[(.-)%]") or v
		if name and trim(vname):lower() == name:lower() then return true end
	end
	return false
end

-- ---- Reserved loot categories --------------------------------------------
-- The PuG page's Reserve strip keeps whole kinds of loot for the leader:
-- "(B+O+P res)". A drop of a reserved kind is treated like a hard reserve --
-- tagged, and never rolled. The ids and names are the ones Loot's collectors
-- sort by; Primordial Saronite is ICC's "O".
local ORB_IDS  = { [45087] = true, [47556] = true, [49908] = true }
local FRAG_IDS = { [45038] = true, [45039] = true, [45896] = true, [50274] = true }
local ORB_NAMES  = { "runed orb", "crusader orb", "primordial saronite" }
local FRAG_NAMES = { "fragment of val'anyr", "fragments of val'anyr", "shadowfrost shard" }
local PATTERN_PREFIX = { "pattern:", "plans:", "recipe:", "schematic:", "formula:", "design:" }

-- Fragments (Val'anyr, Shadowfrost Shard) and orbs (Runed / Crusader orbs,
-- Primordial Saronite): raid materials, never something a raider reserves.
function SR.IsMaterial(id, name)
	if id and (FRAG_IDS[id] or ORB_IDS[id]) then return true end
	local n = (name or ""):lower()
	if n == "" then return false end
	for _, w in ipairs(FRAG_NAMES) do if n:find(w, 1, true) then return true end end
	for _, w in ipairs(ORB_NAMES) do if n:find(w, 1, true) then return true end end
	return false
end

local function hasAny(name, list, prefix)
	for _, w in ipairs(list) do
		if prefix then
			if name:sub(1, #w) == w then return true end
		elseif name:find(w, 1, true) then return true end
	end
	return false
end

local function nameOf(item)
	if type(item) == "string" then
		local n = item:match("%[(.-)%]") or (not item:find("|H", 1, true) and item) or GetItemInfo(item)
		if n then return n:lower() end
	elseif type(item) == "number" then
		local n = GetItemInfo(item)
		if n then return n:lower() end
	end
	return ""
end

-- "BoE" / "Orb" / "Pattern" / "Frag" when this drop is of a kind the leader
-- reserved, else nil. `boe` says whether the item binds on equip; the caller
-- knows (a captured drop carries it), an item link alone does not.
function SR.ReservedCat(item, boe)
	local P = Okanvil.PuG
	local pdb = P and P.DB and P.DB()
	local r = pdb and pdb.reserve
	if type(r) ~= "table" or pdb.reserveNone then return nil end
	-- A reserve is the master looter keeping loot back. Under group or need-before-
	-- greed loot (a random dungeon, a pug with no ML) nobody holds anything, and a
	-- BoE from trash is open to the whole group. The solo council test counts as ML.
	local RM = Okanvil.RollMgr
	if (GetLootMethod and GetLootMethod()) ~= "master" and not (RM and RM.IsML and RM.IsML()) then
		return nil
	end
	local id, name = idOf(item), nameOf(item)
	if (r.frag or r.shard) and ((id and FRAG_IDS[id]) or hasAny(name, FRAG_NAMES)) then return "Frag" end
	if r.orb and ((id and ORB_IDS[id]) or hasAny(name, ORB_NAMES)) then return "Orb" end
	if r.pattern and hasAny(name, PATTERN_PREFIX, true) then return "Pattern" end
	if r.boe and boe then return "BoE" end
	return nil
end

-- Why this item must not be rolled, or nil when it may be.
function SR.Blocked(item, boe)
	if SR.IsHard(item) then return "hard-reserved" end
	local cat = SR.ReservedCat(item, boe)
	if cat then return "reserved (" .. cat .. ")" end
	return nil
end

-- ---- The tag in front of an item name ------------------------------------
-- What a raider needs from a glance at the list is "may I roll on this?":
--   [HR] red   -- hard-reserved, nobody rolls
--   [BoE] [Orb] [Pattern] [Frag] red -- a kind of loot the leader reserved
--   [SR] gold  -- soft-reserved and you are one of the reservers
--   [SR] grey  -- soft-reserved by others, an MS roll from you will not count
-- The master looter is not rolling, so for them any reserved item is gold.
-- Returns "" for an item that is open to everyone.
function SR.Tag(item, id, boe)
	if SR.IsHard(item) then return "|cffff5555[HR]|r " end
	local cat = SR.ReservedCat(item, boe)
	if cat then return "|cffff5555[" .. cat .. "]|r " end
	id = id or idOf(item)
	if not SR.IsReserved(id) then return "" end
	-- The mini roll's own answer, so the tag and the window agree (it counts a
	-- solo council test as master looter; the Loot module's does not).
	local RM, L = Okanvil.RollMgr, Okanvil.Loot
	local ml
	if RM and RM.IsML then ml = RM.IsML()
	else ml = L and L.IsMasterLooter and L.IsMasterLooter() end
	if ml or SR.IsReserver(id, UnitName("player")) then return "|cffe0b860[SR]|r " end
	return "|cff6f7176[SR]|r "
end

-- ---- The MS call --------------------------------------------------------
local SR_MSG = "SR [item]  --  only [names]  /roll (1-100)"
function SR.Msg()
	return db().msg or SR_MSG
end
function SR.SetMsg(text)
	text = trim(text)
	db().msg = (text ~= "" and text) or nil
end

-- The roll call for a reserved item. Chat drops a line over 255 bytes without
-- a word, so when the names do not fit the tail becomes "+N" instead of the
-- whole call vanishing.
function SR.RollCall(link)
	local tmpl = SR.Msg():gsub("%[item%]", function() return link end)
	local list = SR.For(link)
	local shown = {}
	for i, e in ipairs(list) do
		local try = table.concat(shown, ", ") .. (#shown > 0 and ", " or "") .. e.name
		local rest = #list - i
		local tail = rest > 0 and (" +" .. rest) or ""
		local line = tmpl:gsub("%[names%]", function() return try .. tail end)
		if #line > 250 and #shown > 0 then break end
		shown[#shown + 1] = e.name
	end
	local left = #list - #shown
	local names = table.concat(shown, ", ") .. (left > 0 and (" +" .. left) or "")
	return (tmpl:gsub("%[names%]", function() return names end))
end
