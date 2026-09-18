-- ============================================================
--  Okanvil -- LootPrio: the officer page's ladder, pasted in and kept.
--
--  The site works the ladder out live from the guild roster, our logs and the
--  loot history. A 3.3.5a client cannot reach the site, so the page's export is
--  pasted here once and stored account-wide; it stays until the next paste.
--
--  The export is Lua SOURCE, but it is never run: a pasted chunk is untrusted
--  and loadstring would execute whatever it contains. The lines are read with a
--  pattern instead, so the worst a bad paste can do is match nothing.
-- ============================================================

local W = Okanvil.W
local P = {}
Okanvil.LootPrio = P

-- Account-wide: the ladder is guild data, the same on every toon. (Loot HISTORY
-- is per-character, which is a different thing and lives elsewhere.)
local migrated = false
local function db()
	Okanvil.db.lootPrio = Okanvil.db.lootPrio or {}
	local d = Okanvil.db.lootPrio
	-- Repair an older stored paste the first time anything asks for it. Done here
	-- rather than at file scope: Okanvil.db does not exist until ADDON_LOADED.
	if not migrated then
		migrated = true
		if P.Migrate then P.Migrate(d) end
	end
	return d
end

-- ------------------------------------------------------------
-- Parse
-- ------------------------------------------------------------
-- Reads the rows the page emits:
--     ["deathbringer's will"] = { n = "Deathbringer's Will", p = "Kobee > ..." },
-- Anything else in the paste (the header comment, the table wrapper) is ignored,
-- so pasting the whole file is fine.
function P.Parse(text)
	if type(text) ~= "string" or text == "" then return nil, 0 end
	-- An EditBox hands back "||" for every "|" the user pasted: the pipe is WoW's
	-- own escape character, so the control doubles it on the way in. Our class
	-- separator IS a pipe, so undo that before anything is matched or every name
	-- would keep a stray "|" and lose its colour.
	text = text:gsub("||", "|")
	local items, n = {}, 0
	-- the tail after p is matched loosely: rows carry optional boss/icon/reserved
	-- fields, and the pattern must take a row whichever of them are present.
	for key, name, prio, tail in
		text:gmatch('%[%s*"(.-)"%s*%]%s*=%s*{%s*n%s*=%s*"(.-)"%s*,%s*p%s*=%s*"(.-)"%s*(.-)}') do
		-- the page escapes " and \ for Lua; undo that, longest escape first
		local function unesc(s) return (s:gsub('\\\\', '\\'):gsub('\\"', '"')) end
		key = unesc(key)
		if key ~= "" then
			items[key] = {
				n = unesc(name), p = unesc(prio),
				bo = tail:match('bo%s*=%s*"(.-)"'),
				ic = tail:match('ic%s*=%s*"(.-)"'),
				g = tail:match('g%s*=%s*"(.-)"'),
				go = tonumber(tail:match("go%s*=%s*(%d+)")) or 99,
				id = tonumber(tail:match("[,{]%s*id%s*=%s*(%d+)")),
				r = tail:find("r%s*=%s*1") and true or nil,
			}
			n = n + 1
		end
	end
	if n == 0 then return nil, 0 end
	-- the page stamps the raid it was built from; keep it so the UI can say how old
	local stamp = text:match('generated%s*=%s*"(.-)"')
	return { items = items, generated = stamp or "", count = n }, n
end

-- Store a pasted export. Returns count, or nil + why.
function P.Import(text)
	local parsed, n = P.Parse(text)
	if not parsed then return nil, "nothing that looks like a prio list" end
	local d = db()
	d.items = parsed.items
	d.generated = parsed.generated
	d.count = n
	d.imported = date("%d %b %Y")
	d.stale = nil
	P.Unprime()      -- new items: let the client be asked about them again
	return n
end

function P.Clear()
	local d = db()
	d.items, d.count, d.generated, d.imported = nil, nil, nil, nil
end

-- An older paste can be sitting in the saved variables already: it was stored
-- before the pipe-doubling was understood, and before the page sent the slot
-- group. Repair what can be repaired on load, and flag the rest as stale so the
-- tab can say so instead of just rendering wrong.
function P.Migrate(d)
	d = d or (Okanvil.db and Okanvil.db.lootPrio)
	if not (d and d.items) then return end
	local fixed, grouped = 0, 0
	for _, rec in pairs(d.items) do
		if rec.p and rec.p:find("||", 1, true) then
			rec.p = rec.p:gsub("||", "|")
			fixed = fixed + 1
		end
		if rec.g then grouped = grouped + 1 end
	end
	-- no row carries a slot group: the paste predates it and only a re-export
	-- can supply it, so mark the list rather than pretend it is complete.
	d.stale = (grouped == 0) and true or nil
	if fixed > 0 then
		Okanvil:Print("Loot priority: repaired |cffffd200" .. fixed .. "|r rows from an older paste.")
	end
end

function P.IsStale() return db().stale and true or false end

-- Ask the server for every item the list knows an id for. GetItemInfo returns
-- nothing the first time for an uncached item but queues the fetch, so doing this
-- once when the list is shown means a later Send already has a real link to post
-- instead of falling back to a bare name.
local primed = false   -- per session: the client's item cache does not persist
function P.Unprime() primed = false end
function P.PrimeCache()
	local d = db()
	if not d.items or primed then return end
	primed = true
	for _, rec in pairs(d.items) do
		if rec.id then GetItemInfo(rec.id) end
	end
end

function P.Count() return db().count or 0 end
function P.Generated() return db().generated end
function P.Imported() return db().imported end

-- ------------------------------------------------------------
-- Look up
-- ------------------------------------------------------------
-- Items are keyed by lowercased name because that is what both ends can agree
-- on: the client knows an item's name from its link, and the page has no item
-- ids for the drops nobody has ever looted.
function P.For(itemName)
	if not itemName or itemName == "" then return nil end
	local d = db()
	if not d.items then return nil end
	return d.items[itemName:lower()]
end

-- Accepts a link or a bare name.
function P.ForLink(link)
	if not link then return nil end
	local name = link:match("%[(.-)%]") or link
	return P.For(name)
end

-- ------------------------------------------------------------
-- Announce
-- ------------------------------------------------------------
-- Officer chat, one line: the LINK (so it is clickable and shows the tooltip)
-- followed by the ladder. Chat caps a message at 255 bytes and drops anything
-- over it silently, so a long ladder is trimmed rather than lost -- the names
-- that matter are at the front.
local CHAT_MAX = 255

-- A stored ladder for chat: drop the class after each name and turn the marks
-- into words, since "*" and "~" mean nothing to someone reading officer chat.
-- numbered: "1. Tchilly, 2. Franzherman » 3. Onetreeheals" for chat, where the
-- order matters more than the band and a bare ">" is lost among the names.
function P.Plain(prio, numbered)
	if not prio or prio == "" then return "" end
	local out, rank = {}, 0
	for word in prio:gmatch("%S+") do
		if word == ">" or word == ">>" then
			-- a same-band step needs no mark once the names are numbered; only the
			-- drop to a lower group still earns one
			-- ">>" stays ASCII: chat is a byte stream and a multi-byte glyph is one
			-- more thing that can arrive mangled on someone else's client.
			out[#out + 1] = numbered and (word == ">>" and ">>" or ",") or word
		else
			local body = word:match("^%((.*)%)$") or word
			local suffix = ""
			local b, m = body:match("^(.-)([%*~%?])$")
			if b then
				body = b
				-- only off-spec is worth a word in chat; the older ~ and ? marks
				-- can still arrive from a stale paste, and are simply dropped.
				suffix = (m == "*" and " (OS)") or ""
			end
			local name = body:match("^(.-)|") or body
			if numbered then
				rank = rank + 1
				name = rank .. ". " .. name
			end
			out[#out + 1] = name .. suffix
		end
	end
	-- the separators attach to the name before them, so "A , B" reads "A, B"
	return (table.concat(out, " "):gsub(" ,", ","))
end

-- The ladder as a plain list, top-first: { "Grokara", "Kobee (OS)", ... }.
-- Same reading as P.Plain, but kept as entries so the caller can put one per
-- chat line instead of joining them.
function P.Names(prio, limit)
	local out = {}
	if not prio or prio == "" then return out end
	for word in prio:gmatch("%S+") do
		if word ~= ">" and word ~= ">>" then
			local body = word:match("^%((.*)%)$") or word
			local suffix = ""
			local b, m = body:match("^(.-)([%*~%?])$")
			if b then
				body = b
				suffix = (m == "*" and " (OS)") or ""
			end
			out[#out + 1] = (body:match("^(.-)|") or body) .. suffix
			if limit and #out >= limit then break end
		end
	end
	return out
end

-- How many names a multi-line post sends. Past about five the list stops being
-- something anyone reads mid-pull and becomes a wall of officer chat.
local TOP_N = 5

function P.MultiLine() return db().multiLine and true or false end

function P.ToggleMultiLine()
	local d = db()
	d.multiLine = (not d.multiLine) or nil
	Okanvil:Print("Loot priority: Send now posts |cffffd200"
		.. (d.multiLine and ("one name per line (top " .. TOP_N .. ")") or "a single line") .. "|r.")
	return d.multiLine and true or false
end

function P.Announce(link, itemName)
	local rec = P.ForLink(link) or P.For(itemName)
	local shown = link or itemName
	-- No link to hand on (sent from the list rather than from a drop). Ask by ITEM
	-- ID, not by name: GetItemInfo only answers for items already in the client's
	-- cache, and a token nobody in the raid has ever looted never is -- which is
	-- why a plain name went out. An id makes the client fetch it. The name stays
	-- as the fallback for the first call, before the server has answered.
	if not link and rec then
		local byId = rec.id and select(2, GetItemInfo(rec.id))
		local byName = (not byId) and itemName and select(2, GetItemInfo(itemName)) or nil
		shown = byId or byName or shown
	end
	if not shown then return false, "no item" end
	if not rec then return false, "no prio for " .. (itemName or shown) end

	if not (IsInGuild and IsInGuild()) then return false, "not in a guild" end

	local chan = P.Channel()

	-- One name per line: the item on its own line, then the top few numbered. Costs
	-- several messages, so it is opt-in -- worth it when the call is being read out,
	-- too noisy to be the only way to post.
	if P.MultiLine() then
		SendChatMessage(shown, chan)
		local names = P.Names(rec.p, TOP_N)
		for i, name in ipairs(names) do
			SendChatMessage(" " .. i .. ". " .. name, chan)
		end
		if #names == 0 then SendChatMessage(" (nobody eligible)", chan) end
		return true
	end

	-- Single line. The item ran straight into the first name and the ">" between
	-- names vanished once the line wrapped, so a dash sets the item apart and the
	-- order is numbered.
	local head = shown .. " -- "
	local prio = P.Plain(rec.p, true)
	if #head + #prio > CHAT_MAX then
		-- cut at a separator so the line never ends mid-name
		local room = CHAT_MAX - #head - 4
		local cut = prio:sub(1, math.max(0, room))
		cut = cut:match("^(.*)%s*[,>]+%s*%S*$") or cut
		prio = cut .. " ..."
	end
	SendChatMessage(head .. prio, chan)
	return true
end

-- Where Send posts. OFFICER in normal use; SAY while testing, so the format can be
-- checked without putting a dozen test lines in front of the other officers.
function P.Channel()
	return db().testChannel and "SAY" or "OFFICER"
end

function P.ToggleTest()
	local d = db()
	d.testChannel = (not d.testChannel) or nil
	Okanvil:Print("Loot priority: Send now posts to |cffffd200"
		.. (d.testChannel and "SAY (testing)" or "OFFICER") .. "|r.")
	return d.testChannel and true or false
end

-- ------------------------------------------------------------
-- Colouring
-- ------------------------------------------------------------
-- The page hands each name its class, so the addon can paint the ladder the same
-- way instead of one flat grey line. RAID_CLASS_COLORS is keyed by the token
-- ("DEATHKNIGHT"), the export carries the display name ("Death Knight").
local CLASS_HEX = {
	["death knight"] = "c41f3b", ["deathknight"] = "c41f3b",
	druid = "ff7d0a", hunter = "abd473", mage = "69ccf0",
	paladin = "f58cba", priest = "ffffff", rogue = "fff569",
	shaman = "0070de", warlock = "9482c9", warrior = "c79c6e",
}

-- One entry of a ladder: "Name|Class", optionally wrapped/suffixed with a mark.
-- Returns the coloured name plus the tag to draw after it.
function P.Paint(token)
	local mark, body = nil, token
	local inner = token:match("^%((.*)%)$")
	if inner then mark, body = "has", inner end
	if not mark then
		local b, m = body:match("^(.-)([%*~%?])$")
		if b then
			body = b
			mark = (m == "*" and "off") or (m == "~" and "low") or "new"
		end
	end
	local name, cls = body:match("^(.-)|(.*)$")
	name = name or body
	local hex = cls and CLASS_HEX[cls:lower()] or nil
	local painted = hex and ("|cff" .. hex .. name .. "|r") or name
	if mark == "has" then
		-- already holds it: greyed, so the eye skips straight to who is next
		painted = "|cff6a6d73" .. name .. "|r"
	end
	return painted, mark
end

-- No tags on the names. "new" and "low" landed on most of the list at once, so
-- they added length without narrowing a decision; the ORDER already says who is
-- ahead. Off-spec is the one distinction that changes what an officer does, so
-- it is the only mark left.
local MARK_TEXT = {
	off = "|cff6a6d73(OS)|r",
}

-- A whole ladder string -> one coloured line.
function P.Line(prio)
	if not prio or prio == "" then return "" end
	local out = {}
	for word in prio:gmatch("%S+") do
		if word == ">" then
			out[#out + 1] = "|cff4a4d53>|r"
		elseif word == ">>" then
			out[#out + 1] = "|cffc0943a>>|r"
		else
			local painted, mark = P.Paint(word)
			out[#out + 1] = painted .. (mark and MARK_TEXT[mark] or "")
		end
	end
	return table.concat(out, " ")
end

-- Sorted copy for display: the store is keyed by name for lookup, which has no
-- order of its own. Reserved items first -- those are the council's calls, the
-- ones worth finding fastest -- then alphabetical inside each group.
-- What a search term can mean besides "these letters appear in the name".
--
-- Typing "mace" should find every mace, not only items with "mace" in their title.
-- The icon slug already carries the weapon type the client itself assigned
-- (inv_mace_116, inv_sword_153, inv_weapon_shortblade_94), and the group carries
-- the slot, so a term is matched against those too.
local KIND_WORDS = {
	mace = "mace", maces = "mace",
	sword = "sword", swords = "sword", blade = "sword", blades = "sword",
	axe = "axe", axes = "axe",
	staff = "staff", staves = "staff", stave = "staff",
	dagger = "shortblade", daggers = "shortblade", dagger1h = "shortblade",
	wand = "wand", wands = "wand",
	bow = "bow", bows = "bow",
	crossbow = "crossbow", xbow = "crossbow",
	gun = "gun", guns = "gun",
	shield = "shield", shields = "shield",
	polearm = "polearm", polearms = "polearm",
}

-- Words that mean a SLOT rather than a weapon type. Matched against the group
-- name the page already sends, so these stay in step with the page's own headings.
local SLOT_WORDS = {
	["1h"] = "one%-hand", ["one hand"] = "one%-hand", onehand = "one%-hand",
	["2h"] = "two%-hand", ["two hand"] = "two%-hand", twohand = "two%-hand",
	trinket = "trinket", trinkets = "trinket",
	ring = "neck", rings = "neck", neck = "neck", necklace = "neck",
	cloak = "back", cloaks = "back", back = "back", cape = "back",
	boot = "boot", boots = "boot", feet = "boot",
	belt = "belt", belts = "belt", waist = "belt",
	glove = "glove", gloves = "glove", hands = "glove",
	bracer = "bracer", bracers = "bracer", wrist = "bracer",
	leg = "leg", legs = "leg", pants = "leg",
	chest = "chest", robe = "chest",
	head = "head", helm = "head", helmet = "head",
	shoulder = "shoulder", shoulders = "shoulder",
	token = "token", tokens = "token", tier = "token", t10 = "token",
	offhand = "off%-hand", ["off hand"] = "off%-hand",
	ranged = "ranged",
}

-- Does one search term match this item by any route?
local function termMatches(rec, key, term)
	if key:find(term, 1, true) then return true end                 -- item name
	if (rec.p or ""):lower():find(term, 1, true) then return true end -- a player
	if (rec.bo or ""):lower():find(term, 1, true) then return true end -- the boss

	-- Weapon type, read from the slug's TYPE position only. A loose search of the
	-- whole slug is wrong: the tier tokens use "ability_paladin_shieldofthetemplar",
	-- which would answer to "shield" without being one.
	local kind = KIND_WORDS[term]
	if kind then
		local ic = (rec.ic or ""):lower()
		local base = ic:match("^inv_weapon_([a-z]+)") or ic:match("^inv_([a-z]+)")
		if base == kind then return true end
	end

	local slot = SLOT_WORDS[term]
	if slot and (rec.g or ""):lower():find(slot) then return true end

	-- also let a bare word match the group heading, so "weapon" or "trinkets"
	-- works without needing an entry in the table above
	if (rec.g or ""):lower():find(term, 1, true) then return true end
	return false
end

-- tier: "all" | "R" (reserved, the council's calls) | "P" (prio roll)
function P.Sorted(filter, tier)
	local d = db()
	local out = {}
	if not d.items then return out end
	filter = filter and filter:lower() or ""

	-- Several words narrow, they do not widen: "mace ret" is the maces a ret
	-- wants, not every mace plus everything Rellik is on.
	local terms = {}
	for w in filter:gmatch("%S+") do terms[#terms + 1] = w end

	for key, rec in pairs(d.items) do
		local okTier = (tier == nil or tier == "all")
			or (tier == "R" and rec.r)
			or (tier == "P" and not rec.r)
		local okFilter = true
		for _, term in ipairs(terms) do
			if not termMatches(rec, key, term) then okFilter = false; break end
		end
		if okTier and okFilter then
			out[#out + 1] = rec
		end
	end
	-- Grouped by slot, in the website's own order (trinkets, rings, weapons...),
	-- so an item is found where you would look for it rather than somewhere in
	-- one long alphabetical run.
	table.sort(out, function(a, b)
		local ga, gb = a.go or 99, b.go or 99
		if ga ~= gb then return ga < gb end
		return (a.n or "") < (b.n or "")
	end)
	return out
end

-- ------------------------------------------------------------
-- Import popup -- opened from the tab, closes itself on success
-- ------------------------------------------------------------
local importDlg

function P.ShowImport(onDone)
	local f = importDlg
	if not f then
		f = Okanvil:Popup("Import loot priority")
		f:SetSize(460, 300)

		local hint = W.Text(f, "Copy the site's \"Export reserved\", paste here (Ctrl+V), then Save.", 10, "dim")
		hint:SetPoint("TOPLEFT", 10, -30)

		local box = W.MultiEdit(f)
		box:SetPoint("TOPLEFT", 8, -46)
		box:SetPoint("BOTTOMRIGHT", -8, 38)

		local save = W.Button(f, "Save", "primary")
		save:SetSize(100, 22); save:SetPoint("BOTTOMLEFT", 8, 8)
		local cancel = W.Button(f, "Cancel")
		cancel:SetSize(80, 22); cancel:SetPoint("LEFT", save, "RIGHT", 6, 0)
		local msg = W.Text(f, "", 11, "dim")
		msg:SetPoint("LEFT", cancel, "RIGHT", 10, 0)

		cancel:SetScript("OnClick", function() f:Hide() end)
		save:SetScript("OnClick", function()
			local n, err = P.Import(box:GetText())
			if n then
				box:SetText("")
				f:Hide()
				Okanvil:Print("Loot priority saved -- |cffffd200" .. n .. "|r items.")
				if f._onDone then f._onDone() end
			else
				msg:SetText("|cffff5555" .. (err or "could not read that") .. "|r")
			end
		end)
		f:HookScript("OnShow", function() msg:SetText("") end)
		f.box = box
		importDlg = f
	end
	f._onDone = onDone
	f.box:SetText("")
	f:Show()
end

-- ------------------------------------------------------------
-- Prio tab -- the stored list, grouped by slot
-- ------------------------------------------------------------
-- Text sizes are derived from the user's global font size rather than fixed, so
-- the Settings > Font size slider scales this list along with the rest of the UI.
-- The offsets keep the hierarchy: group heading largest, then item, then ladder.
local function fsz(delta)
	local _, base = Okanvil:Font()
	return math.max(8, (base or 12) + (delta or 0))
end

-- Row geometry follows the font: two stacked lines of text plus padding. Fixed
-- heights clipped the ladder as soon as the font slider went up.
local GROUP_GAP = 14
local function rowH()  return fsz(3) + fsz(2) + 16 end
local function iconSz() return math.min(rowH() - 12, 40) end
local function headH() return fsz(4) + 10 end

function P.BuildTab(p)
	local status = W.Text(p, "", fsz(0), "dim")
	status:SetPoint("TOPLEFT", 8, -8)

	-- controls -----------------------------------------------------------
	-- The paste box was a permanently open well for something done once a week,
	-- so it is a popup now: the list gets that whole strip of screen instead.
	-- Import and Clear sit on the status line, hard right: they are used once a
	-- week, so they get the corner and the list keeps the full width below.
	local imp = W.Button(p, "Import list", "primary")
	imp:SetSize(100, 22); imp:SetPoint("TOPRIGHT", -8, -4)

	local clear = W.Button(p, "Clear")
	-- anchored LEFT of Import, so the offset must be negative or it overlaps it
	clear:SetSize(70, 22); clear:SetPoint("RIGHT", imp, "LEFT", -6, 0)

	local search = W.EditBox(p)
	search:SetSize(200, 22); search:SetPoint("TOPLEFT", 8, -28)

	-- Reserved / prio-roll toggle, same three states as the website's tabs.
	local tier = "all"
	local tierBtns = {}
	local function setTier(t)
		tier = t
		for k, b in pairs(tierBtns) do b:SetKind(k == t and "primary" or nil) end
		if p._rebuild then p._rebuild() end
	end
	local function tierBtn(label, key, w, anchor, gap)
		local b = W.Button(p, label, key == "all" and "primary" or nil)
		b:SetSize(w, 22)
		b:SetPoint("LEFT", anchor, "RIGHT", gap or 6, 0)
		b:SetScript("OnClick", function() setTier(key) end)
		tierBtns[key] = b
		return b
	end
	local bAll = tierBtn("All", "all", 44, search, 10)
	local bRes = tierBtn("Reserved", "R", 74, bAll)
	local bRoll = tierBtn("Prio roll", "P", 70, bRes)

	-- Send goes to officer chat; flipping this to SAY lets the format be checked
	-- without putting test lines in front of the other officers.
	local chan = W.Button(p, "")
	chan:SetSize(74, 22); chan:SetPoint("RIGHT", clear, "LEFT", -6, 0)
	local function syncChan()
		local testing = P.Channel() == "SAY"
		if chan.text then
			chan.text:SetText(testing and "|cffff5555SAY|r" or "Officer")
		end
		chan:Tooltip(testing
			and "Testing: Send posts to SAY. Click to post to officer chat."
			or "Send posts to officer chat. Click to test in SAY instead.")
	end
	chan:SetScript("OnClick", function() P.ToggleTest(); syncChan() end)
	syncChan()

	-- One line, or the item plus its top names one per line.
	local fmt = W.Button(p, "")
	fmt:SetSize(74, 22); fmt:SetPoint("RIGHT", chan, "LEFT", -6, 0)
	local function syncFmt()
		local multi = P.MultiLine()
		if fmt.text then fmt.text:SetText(multi and "Lines" or "1 line") end
		fmt:Tooltip(multi
			and "Send posts the item, then its top names one per line.\nClick for a single line."
			or "Send posts one line.\nClick to put each name on its own line.")
	end
	fmt:SetScript("OnClick", function() P.ToggleMultiLine(); syncFmt() end)
	syncFmt()

	local collapseAll = W.Button(p, "Collapse all")
	collapseAll:SetSize(88, 22); collapseAll:SetPoint("LEFT", bRoll, "RIGHT", 10, 0)

	-- list ---------------------------------------------------------------
	local listTop = 28 + 22 + 8
	local well = W.Frame(p, "dark")
	well:SetPoint("TOPLEFT", 8, -listTop)
	well:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -8, 8)

	local sf = CreateFrame("ScrollFrame", nil, well)
	sf:SetPoint("TOPLEFT", 4, -4); sf:SetPoint("BOTTOMRIGHT", -10, 4)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(1, 1); sf:SetScrollChild(child)
	Okanvil.Clip(well)

	local sb = CreateFrame("Slider", nil, well)
	sb:SetPoint("TOPRIGHT", -3, -4); sb:SetPoint("BOTTOMRIGHT", -3, 4); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
	local th = sb:CreateTexture(nil, "OVERLAY")
	th:SetTexture("Interface\\Buttons\\WHITE8x8")
	local ac = Okanvil.Colors and Okanvil.Colors.accent or { 0.75, 0.58, 0.23 }
	th:SetVertexColor(ac[1], ac[2], ac[3]); th:SetSize(4, 30)
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, dz) sb:SetValue(sb:GetValue() - dz * rowH()) end)

	local rows = {}
	local function rowAt(i)
		local r = rows[i]
		if r then return r end
		r = CreateFrame("Frame", nil, child)
		r:SetHeight(rowH())

		-- item icon, same art the website shows
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(iconSz(), iconSz())
		r.icon:SetPoint("TOPLEFT", 4, -4)
		r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- trim the stock border
		r.ibg = r:CreateTexture(nil, "BACKGROUND")
		r.ibg:SetTexture("Interface\\Buttons\\WHITE8x8")
		r.ibg:SetVertexColor(0, 0, 0, 0.5)
		r.ibg:SetPoint("TOPLEFT", r.icon, -1, 1)
		r.ibg:SetPoint("BOTTOMRIGHT", r.icon, 1, -1)

		-- Reserved gets a gold bar down the left edge: the council's calls are
		-- findable at a glance without reading a star into every row.
		r.bar = r:CreateTexture(nil, "ARTWORK")
		r.bar:SetTexture("Interface\\Buttons\\WHITE8x8")
		r.bar:SetWidth(2)
		r.bar:SetPoint("TOPLEFT", 0, -2)
		r.bar:SetPoint("BOTTOMLEFT", 0, 2)

		r.name = W.Text(r, "", fsz(3))
		r.name:SetPoint("TOPLEFT", iconSz() + 14, -5)
		r.boss = W.Text(r, "", fsz(-1), "dim")
		r.boss:SetPoint("LEFT", r.name, "RIGHT", 6, 0)

		-- Send this one item's prio to officer chat, without going through the
		-- roll manager: the drop is often called out before anyone opens it.
		r.send = W.Button(r, "Send")
		r.send:SetSize(52, 20)
		r.send:SetPoint("RIGHT", -6, 0)
		r.send:SetScript("OnClick", function(self)
			local rec = self:GetParent()._rec
			if not rec then return end
			local ok, why = P.Announce(nil, rec.n)
			if not ok then Okanvil:Print("|cff8a8d93No prio sent|r -- " .. (why or "?") .. ".") end
		end)
		r.send:Tooltip("Post this item and its priority order to officer chat.")

		r.prio = W.Text(r, "", fsz(2))
		r.prio:SetPoint("TOPLEFT", iconSz() + 14, -(fsz(3) + 8))
		r.prio:SetPoint("RIGHT", r.send, "LEFT", -8, 0)
		r.prio:SetJustifyH("LEFT")
		r.prio:SetWordWrap(false)

		r.sep = r:CreateTexture(nil, "BACKGROUND")
		r.sep:SetTexture("Interface\\Buttons\\WHITE8x8")
		r.sep:SetVertexColor(1, 1, 1, 0.04)
		r.sep:SetHeight(1)
		r.sep:SetPoint("BOTTOMLEFT", 4, 0)
		r.sep:SetPoint("BOTTOMRIGHT", -4, 0)

		rows[i] = r
		return r
	end

	-- Which groups are folded away. Collapsing is the point of the grouping on a
	-- 72-item list: fold the slots you are not looting for and the ones you are
	-- fit on one screen.
	local folded = {}

	local heads = {}
	local function headAt(i)
		local h = heads[i]
		if h then return h end
		h = CreateFrame("Button", nil, child)
		h:SetHeight(headH())
		h.text = W.Text(h, "", fsz(4), "accent")
		h.text:SetPoint("LEFT", 2, 0)
		h.count = W.Text(h, "", fsz(0), "dim")
		h.count:SetPoint("LEFT", h.text, "RIGHT", 6, 0)
		h:SetScript("OnClick", function(self)
			if self._g then
				folded[self._g] = not folded[self._g] or nil
				if p._rebuild then p._rebuild() end
			end
		end)
		heads[i] = h
		return h
	end

	local function rebuild()
		local n = P.Count()
		if n > 0 and P.IsStale() then
			-- The stored paste predates the slot groups, so it cannot be grouped
			-- however well the code handles it. Say so rather than look broken.
			status:SetText("|cffffd200" .. n .. " items|r |cffff5555-- old format, "
				.. "re-export from the site for groups and colours|r")
		elseif n > 0 then
			local when = P.Generated()
			status:SetText("|cff7cfc8a" .. n .. " items|r"
				.. ((when and when ~= "") and (" |cff8a8d93from " .. when .. "|r") or ""))
		else
			status:SetText("|cff8a8d93No list yet -- Import list, and paste the site's export.|r")
		end

		P.PrimeCache()
		local list = P.Sorted(search.edit:GetText(), tier)
		child:SetWidth(math.max(40, sf:GetWidth()))

		-- how many items each group holds, so a folded header can still say so
		local nIn = {}
		for _, rec in ipairs(list) do
			local g = rec.g or "Other"
			nIn[g] = (nIn[g] or 0) + 1
		end

		local y, lastG, nHead, nRow = 0, nil, 0, 0
		for _, rec in ipairs(list) do
			-- slot header whenever the group changes, like the page's sections
			local g = rec.g or "Other"
			if g ~= lastG then
				lastG = g
				nHead = nHead + 1
				local h = headAt(nHead)
				h._g = g
				h:ClearAllPoints()
				h:SetPoint("TOPLEFT", 2, -(y + GROUP_GAP))
				h:SetPoint("RIGHT", child, "RIGHT", -2, 0)
				local arrow = folded[g] and "|cff8a8d93>|r " or "|cffc0943av|r "
				h.text:SetText(arrow .. "|cffc0943a" .. g:upper() .. "|r")
				h.count:SetText(nIn[g] .. (nIn[g] == 1 and " item" or " items"))
				h:Show()
				y = y + headH() + GROUP_GAP
			end
			if folded[g] then
				-- header only: the rows stay built, they just take no space
			else
			nRow = nRow + 1
			local r = rowAt(nRow)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 0, -y)
			r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
			-- Epic purple for the item, as in game and on the page. Reserved keeps
			-- the gold star: the council's call rather than a roll with an order.
			r.name:SetText("|cffa335ee" .. (rec.n or "?") .. "|r")
			if rec.r then r.bar:SetVertexColor(0.75, 0.58, 0.23, 1); r.bar:Show()
			else r.bar:Hide() end
			r.boss:SetText(rec.bo or "")
			r.prio:SetText(P.Line(rec.p))
			if rec.ic and rec.ic ~= "" then
				r.icon:SetTexture("Interface\\Icons\\" .. rec.ic)
			else
				r.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			end
			r._rec = rec
			r:Show()
			y = y + rowH()
			end
		end
		for i = nRow + 1, #rows do rows[i]:Hide() end
		for i = nHead + 1, #heads do heads[i]:Hide() end

		child:SetHeight(math.max(1, y))
		local maxs = math.max(0, y - sf:GetHeight())
		sb:SetMinMaxValues(0, maxs)
		if sb:GetValue() > maxs then sb:SetValue(maxs) end
		sb:SetShown(maxs > 4)
	end

	-- the tier buttons and the group headers both repaint through this
	p._rebuild = rebuild
	sf:SetScript("OnSizeChanged", rebuild)
	search.edit:SetScript("OnTextChanged", rebuild)

	collapseAll:SetScript("OnClick", function(self)
		-- Fold everything; if anything is already folded, unfold instead, so one
		-- button covers both directions without a second control.
		local any = false
		for _ in pairs(folded) do any = true break end
		if any then
			for k in pairs(folded) do folded[k] = nil end
		else
			for _, rec in ipairs(P.Sorted(nil, nil)) do folded[rec.g or "Other"] = true end
		end
		if self.text then self.text:SetText(any and "Collapse all" or "Expand all") end
		rebuild()
	end)

	imp:SetScript("OnClick", function() P.ShowImport(rebuild) end)

	clear:SetScript("OnClick", function()
		Okanvil:Confirm("Clear the stored loot priority list?", "Clear", function()
			P.Clear(); rebuild(); Okanvil:Print("Loot priority list cleared.")
		end)
	end)

	p:SetScript("OnShow", rebuild)
	rebuild()
end

-- ------------------------------------------------------------
-- Standalone window -- the same list, without opening the hub
-- ------------------------------------------------------------
-- Mid-raid the list is wanted in two clicks from the marks bar, not four through
-- Loot > Prio. The tab builder fills whatever frame it is handed, so the window
-- is just a popup with a body for it to draw into.
local prioWin

function P.Toggle()
	if prioWin and prioWin:IsShown() then prioWin:Hide(); return end
	if not prioWin then
		local f = Okanvil:Popup("Loot priority")
		f:SetSize(760, 520)
		local body = W.Frame(f, "bare")
		body:SetPoint("TOPLEFT", 4, -26)
		body:SetPoint("BOTTOMRIGHT", -4, 4)
		P.BuildTab(body)
		f._body = body
		prioWin = f
	end
	prioWin:Show()
	if prioWin._body and prioWin._body._rebuild then prioWin._body._rebuild() end
end
