-- ============================================================
--  Okanvil -- SoftRes-Pick: raiders choose their soft reserves in a window.
--
--  In SR mode a raider without Okanvil reserves by whisper (SoftRes-Live.lua).
--  A raider WITH Okanvil gets a window instead: when the master looter presses
--  Post rules, it opens on their screen (after combat, never during it). They
--  pick, press Send, confirm, and the picks reach the master looter over addon
--  messages, into the same list a whisper or a softres.it import fills.
--
--  A raider sends once per raid ID; clearing the list lets everyone send again.
--  Everything is kept per raid lockout (SR.LockKey): the next night on the same
--  ID still has the picks, a new ID starts empty.
--
--  Wire:
--    SRPOST  raid, size, hc, limit, lockKey, gen       ML -> group
--    SRPICK  lockKey, "id;id"                          raider -> ML
--    SRACK   lockKey, count or "x:why"                 ML -> raider
--
--  /okres test raider   open the window as a raider would, solo
-- ============================================================

local Okanvil = Okanvil
local SR = Okanvil.SoftRes
local W = Okanvil.W
if not SR then return end

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"
local KEEP_DAYS = 8

local function db()
	Okanvil.db.softres = Okanvil.db.softres or {}
	return Okanvil.db.softres
end
local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function stripRealm(n) return n and (n:gsub("%-.*$", "")) or n end
local function me() return UnitName("player") end
local function solo() return (GetNumRaidMembers() or 0) == 0 and (GetNumPartyMembers() or 0) == 0 end

-- ---- Which raid, which lockout --------------------------------------------
local function raidDef(key)
	for _, r in ipairs(OkanvilRaids or {}) do if r.key == key then return r end end
end

-- The raid we are in, as { key, size, hc }, or nil outside a raid instance.
function SR.RaidHere()
	local name, itype, diff, _, maxPlayers = GetInstanceInfo()
	if itype ~= "raid" then return nil end
	for _, r in ipairs(OkanvilRaids or {}) do
		if r.name == name then
			local size = maxPlayers or ((diff == 2 or diff == 4) and 25 or 10)
			-- normal and heroic are one soft-reserve raid (see SR.InRun)
			return { key = r.key, size = size, hc = false }
		end
	end
end

-- The raid the master looter is setting up: the one we are in, else the one
-- picked on the Loot page, else ICC. The size is your raid difficulty (10 or
-- 25, right-click your portrait), what the raid will really be.
local function groupSize()
	if not GetRaidDifficulty then return nil end
	local d = GetRaidDifficulty()
	if d == 1 or d == 3 then return 10 elseif d == 2 or d == 4 then return 25 end
end
function SR.Raid()
	local here = SR.RaidHere()
	if here then return here end
	local p = db().raidPick
	local size = groupSize()
	if p and raidDef(p.key) then return { key = p.key, size = size or p.size, hc = false } end
	return { key = "icc", size = size or 25, hc = false }
end

function SR.SetRaid(key, size, hc)
	db().raidPick = { key = key, size = size, hc = hc and true or false }
	-- the size IS the raid difficulty: picking ICC 10 sets 10 player (leader or solo)
	if SetRaidDifficulty and GetRaidDifficulty and (size == 10 or size == 25) then
		local want = (size == 10) and 1 or 2
		local cur = GetRaidDifficulty()
		local heroic = (cur == 3 or cur == 4)
		if heroic then want = want + 2 end
		local lead = ((GetNumRaidMembers() or 0) == 0 and (GetNumPartyMembers() or 0) == 0)
			or IsRaidLeader() or IsPartyLeader()
		if cur ~= want and lead then SetRaidDifficulty(want) end
	end
	if SR.onChange then SR.onChange() end
end

function SR.RaidLabel(r)
	r = r or SR.Raid()
	local def = raidDef(r.key)
	local hcName = OkanvilRaidHCName and OkanvilRaidHCName[r.key]
	if r.hc and hcName then return hcName .. " " .. r.size end
	return ((def and def.short) or r.key) .. " " .. r.size .. (r.hc and " HC" or "")
end

-- Whether this item drops in the raid (and size/difficulty) being run. A raid
-- with no loot table here lets everything through.
function SR.DropsHere(id)
	local r = SR.Raid()
	local bosses = OkanvilRaidLoot and OkanvilRaidLoot[r.key]
	if not bosses then return true end
	for _, b in ipairs(bosses) do
		for _, it in ipairs(b.items or {}) do
			if it.id == id and SR.InRun(it.m, r) then return true end
		end
	end
	return false
end

-- Whether a loot-table entry (its `m`, "25n,25h") drops in this run. Normal
-- and heroic both count: the heroic copy is the same item with better stats,
-- so a reserve is for the item whichever version drops (SR.For matches by
-- name). Only the raid size has to match.
function SR.InRun(m, r)
	if not m then return false end
	r = r or SR.Raid()
	return m:find(r.size .. "n", 1, true) ~= nil or m:find(r.size .. "h", 1, true) ~= nil
end

-- "icc25:48213" -- the lockout this raid is saved to, or the date before the
-- first kill (no ID exists yet).
function SR.LockKey(r)
	r = r or SR.Raid()
	local def = raidDef(r.key)
	local base = r.key .. r.size
	if def and GetNumSavedInstances then
		for i = 1, GetNumSavedInstances() do
			local name, id, _, _, locked, _, _, isRaid, maxPlayers = GetSavedInstanceInfo(i)
			if name == def.name and locked and isRaid ~= false and (maxPlayers == nil or maxPlayers == r.size) then
				return base .. ":" .. tostring(id)
			end
		end
	end
	return base .. ":" .. date("%Y%m%d")
end

-- Each clear of the list starts a new round for that lockout: a raider who
-- already sent may send again (the window's lock compares this number).
local function gen(lockKey)
	return (db().gen or {})[lockKey] or 0
end
local function bumpGen(lockKey)
	local d = db()
	d.gen = d.gen or {}
	d.gen[lockKey] = (d.gen[lockKey] or 0) + 1
end

local function prune()
	local d, cutoff = db(), time() - KEEP_DAYS * 86400
	for k, p in pairs(d.myPicks or {}) do if (p.at or 0) < cutoff then d.myPicks[k] = nil end end
end

-- ---- Posting (master looter) -----------------------------------------------
-- Opens the pick window on every raider with Okanvil. Post rules calls it next
-- to the raid-chat rules, which are for everyone else.
function SR.PostPick()
	local r = SR.Raid()
	local lockKey = SR.LockKey(r)
	local d = db()
	-- a reserve list from another lockout is last week's
	if d.lockKey and d.lockKey ~= lockKey and SR.Summary() then
		SR.Clear()
		Okanvil:Print("New raid ID: the old reserve list was cleared.")
	end
	d.lockKey = lockKey
	if SR.SetIntake and not SR.IntakeOpen() then SR.SetIntake(true) end
	d.post = { raid = r.key, size = r.size, hc = r.hc, limit = SR.Limit(), lockKey = lockKey, gen = gen(lockKey) }
	prune()
	local C = Okanvil.Comms
	if C and C.Send then
		C.Send("SRPOST", r.key, r.size, r.hc and "1" or "0", SR.Limit(), lockKey, d.post.gen)
	end
end

-- ---- Receiving picks (master looter) ---------------------------------------
local function classOf(name)
	for i = 1, GetNumRaidMembers() or 0 do
		local n, _, _, _, _, cls = GetRaidRosterInfo(i)
		if n and stripRealm(n):lower() == name:lower() then return cls end
	end
	for i = 1, GetNumPartyMembers() or 0 do
		local u = "party" .. i
		if (UnitName(u) or ""):lower() == name:lower() then return select(2, UnitClass(u)) end
	end
	if name:lower() == (me() or ""):lower() then return select(2, UnitClass("player")) end
end

-- Returns the number of reserves kept, or nil + why they were refused.
function SR.ReceivePicks(sender, lockKey, payload)
	sender = stripRealm(sender)
	local post = db().post
	if not post or post.lockKey ~= lockKey then return nil, "no open soft reserve" end
	if not SR.IntakeOpen() then return nil, "soft reserves are locked" end
	if not solo() and not (UnitInRaid(sender) or UnitInParty(sender) or sender == me()) then
		return nil, "not in the group"
	end
	-- One send per raider: final until the master looter clears the list.
	if #SR.ReservesOf(sender) > 0 then return nil, "already sent -- ask the master looter" end
	local class = classOf(sender)
	local P = Okanvil.Prof
	local kept = 0
	for id in (payload or ""):gmatch("(%d+)") do
		if kept >= post.limit then break end
		id = tonumber(id)
		local name, link = GetItemInfo(id)
		if SR.DropsHere(id) and (not (class and P and P.CanEquip and link) or P.CanEquip(link, class)) then
			SR.AddReserve(sender, class, id, name)
			kept = kept + 1
		end
	end
	Okanvil:Print(("|cffe0b860SR|r %s: %d item%s."):format(sender, kept, kept == 1 and "" or "s"))
	return kept
end

-- Clearing the list is a reset: raiders may send again.
do
	local baseClear = SR.Clear
	SR.Clear = function(...)
		baseClear(...)
		bumpGen(SR.LockKey())
	end
end

-- ---- The raider's window ----------------------------------------------------
local P = {}
SR.PickWindow = P
local win
local state = { raid = "icc", size = 25, hc = false, limit = 1, lockKey = "", from = nil, gen = 0, kind = "sr" }
local picks = {}      -- item ids
local filter = ""
local scroll = 0
local flipped = {}    -- boss -> true: clicked away from its default (a wish starts folded, a reserve open)
local ROWS, ROW_H, WIN_W, SLOT_H = 12, 22, 380, 28

-- Where this character's picks are saved (db.myPicks): one key per kind and
-- lockout, so a wish is kept apart from a soft reserve on the same raid ID.
function SR.PickKey(kind, lockKey)
	return (kind == "wish" and "wish:" or "") .. lockKey .. ":" .. (me() or "")
end
local function picksKey() return SR.PickKey(state.kind, state.lockKey) end

-- Before the first kill a lock key ends in the date ("icc25:20261018"), not an ID.
local function idOfLockKey(lockKey)
	local id = lockKey:match(":(%d+)$")
	return (id and not id:match("^20%d%d%d%d%d%d$")) and id or nil
end

-- `sentGen` is the round these picks were sent in: once sent, the window is
-- read-only until the master looter clears the list.
local function savePicks(sentGen)
	local d = db()
	d.myPicks = d.myPicks or {}
	local old = d.myPicks[picksKey()]
	-- a pass stands until a wish is actually sent
	d.myPicks[picksKey()] = { at = time(), list = picks, sentGen = sentGen or (old and old.sentGen),
		pass = (not sentGen and old and old.pass) or nil }
	if sentGen and Okanvil.Loot_PaintMine then pcall(Okanvil.Loot_PaintMine) end   -- "Your SR / wish" line
end

local function loadPicks()
	local saved = (db().myPicks or {})[picksKey()]
	picks = {}
	for _, id in ipairs(saved and saved.list or {}) do picks[#picks + 1] = id end
	state.sent = saved ~= nil and saved.sentGen ~= nil
	state.passed = state.sent and saved.pass or nil
	-- a wish can change until the master looter locks the list; a soft reserve is final
	if state.kind == "wish" then
		-- locked holds a wish or pass already sent; a late joiner can still pick
		state.locked = Okanvil.Wish and Okanvil.Wish.Frozen() or false
	else
		state.locked = state.sent and saved.sentGen == state.gen
	end
end

local canUse          -- below

-- Bosses and their items for this raid and difficulty, filtered by the search
-- and, with "Usable" on, by what you can use.
local function entries()
	local out, want, seen = {}, filter:lower(), {}
	local onlyUsable = db().onlyUsable
	local run = { key = state.raid, size = state.size, hc = state.hc }
	-- which copy a row shows follows the raid difficulty: heroic set, the heroic
	-- copy (its icon, ilvl and tooltip). The pick still counts for both copies.
	local d = GetRaidDifficulty and GetRaidDifficulty()
	local hcTag = state.size .. ((d == 3 or d == 4) and "h" or "n")
	local rowOf = {}      -- name -> its index in this boss's items
	for _, b in ipairs(OkanvilRaidLoot and OkanvilRaidLoot[state.raid] or {}) do
		local items = {}
		wipe(rowOf)
		for _, it in ipairs(b.items or {}) do
			-- this boss already has the item's other copy: swap in this one if it
			-- is the difficulty being raided
			local at = it.name and rowOf[it.name]
			if at and (it.m or ""):find(hcTag, 1, true) then items[at] = it end
			-- one row per item: its normal and heroic copies are the same reserve
			-- epics only: white quest items (Crystalline Essence) are not loot to pick
			local _, _, q, _, _, itype = GetItemInfo(it.id)
			-- a wish is never a quest item (Festergut's Acidic Blood), even before the
			-- client has cached it: the loot table's slot says so
			local plain = (q and q < 4) or itype == "Quest" or (state.kind == "wish" and it.slot == "Quest")
			if SR.InRun(it.m, run) and not seen[it.name or it.id] and not SR.IsMaterial(it.id, it.name) and not plain
				and (want == "" or (it.name or ""):lower():find(want, 1, true))
				and not (onlyUsable and not canUse(it.id)) then
				seen[it.name or it.id] = true
				items[#items + 1] = it
				if it.name then rowOf[it.name] = #items end
			end
		end
		if #items > 0 then
			-- a search shows every match, folded bosses too
			local shut = ((state.kind == "wish") ~= (flipped[b.boss] == true)) and want == ""
			out[#out + 1] = { boss = b.boss, shut = shut, n = #items }
			if not shut then
				for _, it in ipairs(items) do out[#out + 1] = { item = it } end
			end
		end
	end
	return out
end

-- ok, and "Cloth"/"Leather"/"Mail" when it is lighter than your own armour.
-- The council's rule: your own armour, or lighter armour that suits your spec
-- and beats what you wear (Prof.LighterWorthAsking).
canUse = function(id)
	local Pf = Okanvil.Prof
	local _, link = GetItemInfo(id)
	if not (Pf and Pf.CanIUse and link) then return true end
	-- the right armour or weapon, but stats for another spec (spell power on a DK);
	-- a wish counts your off spec too, as the council does
	local fits = (state.kind == "wish" and Pf.FitsEitherSpec) or Pf.StatsFitMe
	if fits and not fits(link) then return false end
	if Pf.CanIUse(link) then return true end
	if Pf.LighterWorthAsking and Pf.LighterWorthAsking(link) then
		return true, Pf.LighterArmor(link, (select(2, UnitClass("player"))))
	end
	return false
end

-- by id, or by name: a pick of the normal copy is the heroic copy's row too
local function picked(id)
	local name = GetItemInfo(id)
	for i, p in ipairs(picks) do
		if p == id or (name and GetItemInfo(p) == name) then return i end
	end
end

local function itemName(id, fallback)
	local n, _, q = GetItemInfo(id)
	local r, g, b
	if GetItemQualityColor then r, g, b = GetItemQualityColor(q or 4) end
	if not (r and g and b) then r, g, b = 0.64, 0.21, 0.93 end
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, n or fallback or ("item " .. id))
end

local paint

local function build()
	local C = Okanvil.Colors
	local f = CreateFrame("Frame", "Okanvil_PickWindow", UIParent)
	f:SetSize(WIN_W, 150 + ROWS * ROW_H)
	f:SetPoint("CENTER", 220, 40)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true); f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	Okanvil:Skin(f, "panel")
	tinsert(UISpecialFrames, "Okanvil_PickWindow")
	-- the mini roll's art and title bar: both cut at the window's corners
	W.ForgeArt(f, 0.22)
	local hdr = W.TitleBar(f, 26)
	f.title = hdr.title
	f.title:ClearAllPoints(); f.title:SetPoint("LEFT", 4, 0); f.title:SetJustifyH("LEFT")
	f.title:SetText("Soft reserve")
	local close = W.CloseButton(hdr); close:SetSize(18, 18); close:SetPoint("RIGHT", -2, 0)
	close:SetScript("OnClick", function() f:Hide() end)
	-- Usable: hide what you can't use; gold while on, remembered
	local usable = W.Button(hdr, "Usable"); usable:SetSize(54, 18); usable:SetPoint("RIGHT", close, "LEFT", -4, 0)
	usable:Tooltip("Show only items you can use (either spec).")
	local function paintUsable() usable:SetKind(db().onlyUsable and "primary" or nil) end
	usable:SetScript("OnClick", function()
		db().onlyUsable = not db().onlyUsable or nil
		scroll = 0
		paintUsable(); paint()
	end)
	paintUsable()
	f.sub = W.Text(hdr, "", "label", "dim"); f.sub:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
	f.sub:SetPoint("RIGHT", usable, "LEFT", -6, 0); f.sub:SetJustifyH("LEFT")
	if f.sub.SetWordWrap then f.sub:SetWordWrap(false) end

	-- the picks, one line each: item, then a remove cross
	f.slots = {}
	for i = 1, 3 do
		local s = CreateFrame("Button", nil, f)
		s:SetHeight(SLOT_H)
		Okanvil:Skin(s, "dark")
		s.icon = s:CreateTexture(nil, "ARTWORK"); s.icon:SetSize(20, 20); s.icon:SetPoint("LEFT", 5, 0)
		s.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		s.del = W.Button(s, "X"); s.del:SetSize(20, 18); s.del:SetPoint("RIGHT", -4, 0)
		s.del:SetScript("OnClick", function()
			if picks[i] then table.remove(picks, i); savePicks(); paint() end
		end)
		s.txt = W.Text(s, "", "label"); s.txt:SetPoint("LEFT", s.icon, "RIGHT", 6, 0)
		s.txt:SetJustifyH("LEFT")
		if s.txt.SetWordWrap then s.txt:SetWordWrap(false) end
		s:SetScript("OnEnter", function(self)
			if not picks[i] then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. picks[i]); GameTooltip:Show()
		end)
		s:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.slots[i] = s
	end

	local search = W.EditBox(f)
	search:SetHeight(22)
	-- "Search..." in the empty box, gone while you type in it
	local hint = W.Text(search, "Search...", "label", "dim"); hint:SetPoint("LEFT", 8, 0)
	-- an X at the end of the box clears it
	local clear = W.Button(search, "X"); clear:SetSize(18, 16); clear:SetPoint("RIGHT", -3, 0)
	clear:SetScript("OnClick", function() search.edit:SetText(""); search.edit:ClearFocus() end)
	search.edit:SetPoint("BOTTOMRIGHT", -24, 1)
	local function syncHint()
		local empty = trim(search.edit:GetText()) == ""
		if empty and not search.edit:HasFocus() then hint:Show() else hint:Hide() end
		if empty then clear:Hide() else clear:Show() end
	end
	search.edit:HookScript("OnEditFocusGained", syncHint)
	search.edit:HookScript("OnEditFocusLost", syncHint)
	search.edit:SetScript("OnTextChanged", function(e) filter = trim(e:GetText()); scroll = 0; syncHint(); paint() end)
	f.search = search
	syncHint()

	f.rows = {}
	for i = 1, ROWS do
		local r = CreateFrame("Button", nil, f)
		r:SetHeight(ROW_H)
		r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetTexture(FLAT); r.bg:SetAllPoints()
		r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetTexture(FLAT); r.hl:SetVertexColor(1, 1, 1, 0.05); r.hl:SetAllPoints()
		r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 10, 0)
		r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		r.tag = W.Text(r, "", "note"); r.tag:SetPoint("RIGHT", -10, 0)
		r.txt = W.Text(r, "", "label"); r.txt:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r.txt:SetPoint("RIGHT", r.tag, "LEFT", -6, 0); r.txt:SetJustifyH("LEFT")
		if r.txt.SetWordWrap then r.txt:SetWordWrap(false) end
		r:SetScript("OnClick", function(self)
			-- a boss header folds or unfolds its items
			if self._boss then
				flipped[self._boss] = not flipped[self._boss] or nil
				paint()
				return
			end
			local it = self._item
			if not it then return end
			if IsShiftKeyDown() then
				local _, link = GetItemInfo(it.id)
				if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
				return
			end
			if state.locked then return end
			local at = picked(it.id)
			if at then table.remove(picks, at)
			elseif not canUse(it.id) then return
			elseif #picks < state.limit then picks[#picks + 1] = it.id
			else
				-- full: the newest pick is replaced, so a change of mind is one click
				picks[#picks] = it.id
			end
			savePicks(); paint()
		end)
		r:SetScript("OnEnter", function(self)
			if not self._item then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self._item.id); GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		r:EnableMouseWheel(true)
		r:SetScript("OnMouseWheel", function(_, delta) scroll = scroll - delta * 5; paint() end)
		f.rows[i] = r
	end
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta) scroll = scroll - delta * 5; paint() end)

	f.status = W.Text(f, "", "label", "dim"); f.status:SetPoint("BOTTOMLEFT", 12, 14)
	f.send = W.Button(f, "Send", "primary"); f.send:SetSize(80, 22); f.send:SetPoint("BOTTOMRIGHT", -10, 10)
	f.send:SetScript("OnClick", function() P.Send() end)
	-- a wish only: "I want nothing this raid ID", and the window stops asking
	f.pass = W.Button(f, "Pass"); f.pass:SetSize(60, 22); f.pass:SetPoint("RIGHT", f.send, "LEFT", -6, 0)
	f.pass:Tooltip("No wish this raid ID.\nThe window won't open for you again on it.")
	f.pass:SetScript("OnClick", function() P.Pass() end)

	-- Never keep the keyboard: a focused search box eats movement keys.
	f:SetScript("OnHide", function() search.edit:ClearFocus() end)
	return f
end

paint = function()
	if not (win and win:IsShown()) then return end
	local C = Okanvil.Colors
	win.title:SetText(state.kind == "wish" and "Wishlist" or "Soft reserve")
	if state.kind == "wish" and Okanvil.Wish then
		win.sub:SetText(SR.RaidLabel({ key = state.raid, size = 25 }))
	else
		win.sub:SetText(SR.RaidLabel({ key = state.raid, size = state.size, hc = state.hc }) .. "  ·  " .. state.limit)
	end

	-- the picks, stacked; everything below moves down to fit them
	local y = -40
	for i, s in ipairs(win.slots) do
		if i > state.limit then s:Hide() else
			s:ClearAllPoints(); s:SetPoint("TOPLEFT", 10, y); s:SetPoint("TOPRIGHT", -10, y)
			y = y - SLOT_H - 4
			local id = picks[i]
			if id then
				s.icon:SetTexture(GetItemIcon(id)); s.icon:Show()
				if state.locked then s.del:Hide() else s.del:Show() end
				s.txt:SetText(itemName(id)); s.txt:SetPoint("LEFT", s.icon, "RIGHT", 6, 0)
				s.txt:SetPoint("RIGHT", s.del, "LEFT", -6, 0)
			else
				s.icon:Hide(); s.del:Hide()
				s.txt:SetText("|cff6f7176Click an item below|r"); s.txt:SetPoint("LEFT", 8, 0)
				s.txt:SetPoint("RIGHT", -6, 0)
			end
			s:Show()
		end
	end
	y = y - 4
	win.search:ClearAllPoints()
	win.search:SetPoint("TOPLEFT", 10, y); win.search:SetPoint("TOPRIGHT", -10, y)
	y = y - 28
	for i, r in ipairs(win.rows) do
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 6, y - (i - 1) * ROW_H); r:SetPoint("TOPRIGHT", -6, y - (i - 1) * ROW_H)
	end
	win:SetHeight(-y + ROWS * ROW_H + 44)

	local list = entries()
	scroll = math.max(0, math.min(scroll, math.max(0, #list - ROWS)))
	for i, r in ipairs(win.rows) do
		local e = list[i + scroll]
		r._item = e and e.item or nil
		r._boss = e and e.boss or nil
		if not e then r:Hide()
		elseif e.boss then
			r.icon:Hide()
			r.tag:SetText(e.shut and ("|cff8a8d93" .. e.n .. "  +|r") or "|cff8a8d93-|r")
			r.txt:SetPoint("LEFT", 10, 0)
			r.txt:SetText(e.boss:upper()); r.txt:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
			r.txt:SetAlpha(1)
			r.bg:SetVertexColor(0, 0, 0, 0)
			r:Show()
		else
			local id = e.item.id
			r.icon:SetTexture(GetItemIcon(id)); r.icon:Show()
			r.txt:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
			r.txt:SetTextColor(1, 1, 1)
			local usable, lighter = canUse(id)
			r.txt:SetText(itemName(id, e.item.name))
			r.txt:SetAlpha(usable and 1 or 0.45); r.icon:SetAlpha(usable and 1 or 0.45)
			r.tag:SetText(not usable and "|cffd94d52can't use|r" or (lighter and ("|cff8a8d93" .. lighter .. "|r")) or "")
			if picked(id) then r.bg:SetVertexColor(C.accentD[1], C.accentD[2], C.accentD[3], 0.6)
			else r.bg:SetVertexColor(C.panelD[1], C.panelD[2], C.panelD[3], 0.7) end
			r:Show()
		end
	end

	if state.locked then
		win.status:SetText(state.kind == "wish" and "|cffffd200Locked|r"
			or "|cffffd200Sent|r")
		win.send:Disable(); win.send:SetAlpha(0.4)
	elseif state.kind == "wish" and state.passed then
		win.status:SetText("|cffffd200Passed|r")
		win.send:Enable(); win.send:SetAlpha(1)
	elseif state.kind == "wish" and state.sent then
		win.status:SetText("|cffffd200Sent|r")
		win.send:Enable(); win.send:SetAlpha(1)
	else
		win.status:SetText(#picks .. " / " .. state.limit)
		win.send:Enable(); win.send:SetAlpha(1)
	end
	if state.kind == "wish" and not state.locked and not state.passed then win.pass:Show() else win.pass:Hide() end
end

function P.Open(raid, size, hc, limit, lockKey, from, g, kind)
	state.kind = kind == "wish" and "wish" or "sr"
	state.raid, state.size, state.hc = raid, tonumber(size) or 25, hc and true or false
	state.limit = math.max(1, math.min(3, tonumber(limit) or 1))
	state.lockKey, state.from, state.gen = lockKey, from, tonumber(g) or 0
	filter, scroll, flipped = "", 0, {}
	loadPicks()
	while #picks > state.limit do table.remove(picks) end
	if not win then win = build() end
	win.search.edit:SetText("")
	win.search.edit:ClearFocus()
	win:Show()
	paint()
end

-- "can't use" follows the spec you are in: a dual-spec swap with the window up
-- repaints it, the same as closing and opening it again would.
do
	local specWatch = CreateFrame("Frame")
	specWatch:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
	specWatch:RegisterEvent("PLAYER_TALENT_UPDATE")
	specWatch:SetScript("OnEvent", function() if win and win:IsShown() then paint() end end)
end

-- Send asks first: once sent, the picks are final.
function P.Send()
	if state.locked then return end
	if #picks == 0 then Okanvil:Print("Pick an item first."); return end
	if state.kind == "wish" then
		Okanvil:Confirm("Send your wish? The council sees it when the item drops.\n"
			.. "|cff8a8d93It is not a reserve. You can change it until the master looter locks the list.|r",
			"Send", P.DoSend)
		return
	end
	Okanvil:Confirm("Send your soft reserve? You cannot change it after.", "Send", P.DoSend)
end

function P.DoSend()
	-- switched off or locked while the window was open: nothing goes out
	if state.kind == "wish" and Okanvil.Wish and not Okanvil.Wish.Accepting() then
		Okanvil:Print("The wishlist is closed: wish not sent.")
		win:Hide()
		return
	end
	local payload = table.concat(picks, ";")
	savePicks(state.gen)
	state.sent = true
	if state.kind ~= "wish" then state.locked = true end
	if state.kind == "wish" then
		if Okanvil.Wish then Okanvil.Wish.SendPick(state.lockKey, picks[1]) end
		win:Hide()
		return
	end
	local from = state.from
	if not from or from == me() then
		-- solo test, or you are the master looter yourself
		local n, why = SR.ReceivePicks(me(), state.lockKey, payload)
		if n then Okanvil:Print("Soft reserve saved.") else Okanvil:Print("|cffff5555Not saved:|r " .. tostring(why)) end
	else
		Okanvil.Comms.Whisper("SRPICK", from, state.lockKey, payload)
		Okanvil:Print("Soft reserve sent to " .. from .. ".")
	end
	-- done: the window gets out of the way; the answer arrives in chat
	win:Hide()
end

-- No wish this raid ID. Saved as sent, so the window does not open again on it;
-- picking an item and sending later still works.
function P.Pass()
	if state.kind ~= "wish" or state.locked then return end
	Okanvil:Confirm("Pass: no wish this raid ID?\n|cff8a8d93The window won't open for you again on it.|r", "Pass", function()
		local Wi = Okanvil.Wish
		if not (Wi and Wi.Accepting()) then
			Okanvil:Print("The wishlist is closed.")
			win:Hide()
			return
		end
		local d = db()
		d.myPicks = d.myPicks or {}
		picks = {}
		d.myPicks[picksKey()] = { at = time(), list = {}, sentGen = state.gen, pass = true }
		Wi.SendPass(state.lockKey)
		win:Hide()
	end)
end

-- Close the window if it is open on this kind of pick ("wish" / "sr").
function P.HideKind(kind)
	if win and win:IsShown() and state.kind == kind then win:Hide() end
end

-- A pick sent some other way (a "wh [item]" whisper an officer saved) counts as
-- sent from this window: the Loot page shows it and the window stops asking.
function P.MarkSent(kind, lockKey, id)
	local d = db()
	d.myPicks = d.myPicks or {}
	local key = SR.PickKey(kind, lockKey)
	local old = d.myPicks[key]
	local gen = (win and win:IsShown() and state.lockKey == lockKey and state.kind == kind) and state.gen
	d.myPicks[key] = { at = time(), list = { id }, sentGen = gen or (old and old.sentGen) or 0 }
	if gen then win:Hide() end
	if Okanvil.Loot_PaintMine then pcall(Okanvil.Loot_PaintMine) end
end

-- Every pick set this character sent and still holds: one per raid ID and kind,
-- wishes first, newest first. A raid ID that is no longer in your saved list has
-- reset, and its picks with it. Each: { kind = "wish"|"sr", lockKey, list, at, pass }.
function SR.MyPickSets()
	local mine, out = ":" .. (me() or ""), {}
	local cutoff = time() - KEEP_DAYS * 86400
	local saved, any = {}, false
	for i = 1, (GetNumSavedInstances and GetNumSavedInstances() or 0) do
		local _, id = GetSavedInstanceInfo(i)
		if id then saved[tostring(id)] = true; any = true end
	end
	for k, p in pairs(db().myPicks or {}) do
		if k:sub(-#mine) == mine and p.sentGen ~= nil and (p.at or 0) >= cutoff and (p.pass or (p.list and #p.list > 0)) then
			local isWish = k:find("^wish:") ~= nil
			local lockKey = k:sub(isWish and 6 or 1, -#mine - 1)
			local id = idOfLockKey(lockKey)
			-- wishes are for 25s only: a wish saved on a 10 is not shown
			local size = tonumber(lockKey:match("^%a+(%d+):"))
			-- an ID that left the saved list has reset, and its picks with it
			if not (id and any and not saved[id]) and not (isWish and size ~= 25) then
				-- a pass is one card that says so, item id 0
				out[#out + 1] = { kind = isWish and "wish" or "sr", lockKey = lockKey, list = p.pass and { 0 } or p.list,
					pass = p.pass, at = p.at or 0, id = id }
			end
		end
	end
	-- the list you hold (as master looter, or shared to the raid) is the truth
	-- for this raid's soft reserves, however they were made: it replaces your
	-- own records of that raid, whatever size or ID they were saved under
	local held = SR.ReservesOf and SR.ReservesOf(me()) or {}
	if #held > 0 then
		local lk = SR.LockKey()
		local raidKey = lk:match("^(%a+)")
		for i = #out, 1, -1 do
			if out[i].kind == "sr" and out[i].lockKey:match("^(%a+)") == raidKey then table.remove(out, i) end
		end
		out[#out + 1] = { kind = "sr", lockKey = lk, list = held, at = time(), id = idOfLockKey(lk) }
	end
	table.sort(out, function(a, b)
		if a.kind ~= b.kind then return a.kind == "wish" end
		return a.at > b.at
	end)
	return out
end

-- A soft reserve made by whisper: the master looter's Okanvil answers "SR saved:
-- [item]", "SR changed: [old] -> [new]" or "SR removed." -- kept as yours, so
-- YOUR PICKS shows it like one sent from the window.
local function linkIds(text)
	local ids = {}
	for id in text:gmatch("|Hitem:(%d+)") do ids[#ids + 1] = tonumber(id) end
	return ids
end
local function onReply(text)
	local saved, changed, removed = text:match("^SR saved: "), text:match("^SR changed: "), text:match("^SR removed")
	if not (saved or changed or removed) then return end
	local d = db()
	d.myPicks = d.myPicks or {}
	local key = SR.PickKey("sr", SR.LockKey())
	local old = d.myPicks[key]
	local list = {}
	for _, id in ipairs(old and old.list or {}) do list[#list + 1] = id end
	local ids = linkIds(text)
	if removed then
		list = {}
	elseif changed and ids[2] then
		for i, id in ipairs(list) do if id == ids[1] then table.remove(list, i); break end end
		list[#list + 1] = ids[2]
	elseif saved and ids[1] then
		local have
		for _, id in ipairs(list) do if id == ids[1] then have = true end end
		if not have then list[#list + 1] = ids[1] end
	end
	d.myPicks[key] = { at = time(), list = list, sentGen = (old and old.sentGen) or 0 }
	if Okanvil.Loot_PaintMine then pcall(Okanvil.Loot_PaintMine) end
end
local rev = CreateFrame("Frame")
rev:RegisterEvent("CHAT_MSG_WHISPER")
rev:SetScript("OnEvent", function(_, _, text)
	if text then pcall(onReply, text) end
end)

-- Drop this character's own record of its soft reserves (not its wishes): the
-- list they were on was cleared.
function SR.ForgetMyReserves()
	local mine = ":" .. (me() or "")
	for k in pairs(db().myPicks or {}) do
		if not k:find("^wish:") and k:sub(-#mine) == mine then db().myPicks[k] = nil end
	end
	if Okanvil.Loot_PaintMine then pcall(Okanvil.Loot_PaintMine) end
end

-- ---- Wire handlers -----------------------------------------------------------
local pendingOpen
local function openWhenCalm(args)
	if UnitAffectingCombat and UnitAffectingCombat("player") then pendingOpen = args; return end
	P.Open(unpack(args))
end

local calm = CreateFrame("Frame")
calm:RegisterEvent("PLAYER_REGEN_ENABLED")
calm:SetScript("OnEvent", function()
	if pendingOpen then local a = pendingOpen; pendingOpen = nil; P.Open(unpack(a)) end
end)

do
	local C = Okanvil.Comms
	if C and C.On then
		C.On("SRPOST", function(sender, raid, size, hc, limit, lockKey, g)
			sender = stripRealm(sender)
			if sender == me() then return end
			if SR.IsLeadOrML and not SR.IsLeadOrML(sender) then return end
			openWhenCalm({ raid, size, hc == "1", limit, lockKey, sender, g or "0" })
		end)
		C.On("SRCLEAR", function(sender)
			sender = stripRealm(sender)
			if sender == me() then return end
			if SR.IsLeadOrML and not SR.IsLeadOrML(sender) then return end
			SR.ForgetMyReserves()
		end)
		C.On("SRPICK", function(sender, lockKey, payload)
			local n, why = SR.ReceivePicks(sender, lockKey, payload)
			C.Whisper("SRACK", stripRealm(sender), lockKey, n and tostring(n) or ("x:" .. tostring(why)))
		end)
		C.On("SRACK", function(sender, lockKey, n)
			if state.lockKey ~= lockKey then return end
			if tostring(n):match("^x:") then
				Okanvil:Print("|cffff5555Soft reserve not saved:|r " .. tostring(n):sub(3))
			else
				Okanvil:Print("|cffffd200Soft reserve received by " .. stripRealm(sender) .. ".|r")
			end
		end)
	end
end

-- Test: the window as a raider sees it, sending to yourself. Your own earlier
-- reserve is dropped first, so the test can be run again and again.
function SR.TestRaider()
	SR.SetMode("sr")
	local lockKey = SR.LockKey()
	SR.RemoveReserve(me())
	if db().myPicks then db().myPicks[SR.PickKey("sr", lockKey)] = nil end
	SR.PostPick()
	local post = db().post
	P.Open(post.raid, post.size, post.hc, post.limit, post.lockKey, me(), post.gen)
end

-- ---- Picks live as long as the group ----------------------------------------
-- A soft reserve belongs to the group it was made in: out of a group for GRACE
-- seconds (left, disbanded, or logged in alone) and this character's reserves
-- are gone, so the next PuG starts clean. Wishes stay: they are per raid ID for
-- the guild's own nights. The grace keeps them through a roster blink while
-- zoning or a relog mid-raid.
do
	local GRACE = 120
	local function inGroup()
		return (GetNumRaidMembers() or 0) > 0 or (GetNumPartyMembers() or 0) > 0
	end
	local pending = false
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("PARTY_MEMBERS_CHANGED")
	f:RegisterEvent("RAID_ROSTER_UPDATE")
	f:SetScript("OnEvent", function()
		if inGroup() or pending or not (Okanvil.Comms and Okanvil.Comms.After) then return end
		pending = true
		Okanvil.Comms.After(GRACE, function()
			pending = false
			if inGroup() then return end
			local d, mine = db(), ":" .. (me() or "")
			local any = false
			for k in pairs(d.myPicks or {}) do
				if k:sub(-#mine) == mine and not k:find("^wish:") then d.myPicks[k] = nil; any = true end
			end
			if not any then return end
			wipe(picks)
			if Okanvil.Loot_PaintMine then pcall(Okanvil.Loot_PaintMine) end
		end)
	end)
end
