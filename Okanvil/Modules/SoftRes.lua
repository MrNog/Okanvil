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
				players[k] = true
			end
		end
	end
	if rows == 0 then return nil, "No reserves found. Paste the CSV from softres.it (Export > CSV)." end
	local d = db()
	d.items, d.names, d.at = items, names, time()
	local ni, np = 0, 0
	for _ in pairs(items) do ni = ni + 1 end
	for _ in pairs(players) do np = np + 1 end
	d.nItems, d.nPlayers = ni, np
	if SR.onChange then SR.onChange() end
	return ni, np
end

function SR.Clear()
	local d = db()
	d.items, d.names, d.at, d.nItems, d.nPlayers = nil, nil, nil, nil, nil
	if SR.onChange then SR.onChange() end
end

-- items, raiders, import time -- or nil when nothing is loaded
function SR.Summary()
	local d = db()
	if not d.items then return nil end
	return d.nItems or 0, d.nPlayers or 0, d.at
end

local function idOf(item)
	if type(item) == "number" then return item end
	if type(item) == "string" then return tonumber(item:match("item:(%d+)")) end
	return nil
end

-- The raiders who reserved this item (id or link), in import order. Empty when
-- the item is not reserved or no list is loaded.
function SR.For(item)
	local id = idOf(item)
	local d = db()
	return (id and d.items and d.items[id]) or {}
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
function SR.Names(item, plain)
	local out = {}
	for _, e in ipairs(SR.For(item)) do
		local n = e.name .. (e.count > 1 and (" x" .. e.count) or "")
		out[#out + 1] = plain and n or (classColor(e.class) .. n .. "|r")
	end
	return table.concat(out, plain and ", " or "|cff6f7176, |r")
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
