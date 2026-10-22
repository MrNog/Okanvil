-- ============================================================
--  Okanvil -- Wishlist: what each raider is after this raid ID.
--
--  Optional, 25-man only. The master looter switches it on for one raid ID and
--  presses Ask; raiders with Okanvil then get the soft-reserve pick window as a
--  wish window: one
--  item per raid ID, normal or heroic, changeable until the master looter
--  locks the list. It is NOT a reserve -- it only tells the council, on the
--  board, that this item is what that raider is hunting. The council decides.
--
--  Open belongs to the raid ID, not to a switch: the next raid ID starts closed.
--  Before the first kill the raid ID is not known yet and the key is the date
--  ("icc25:20261021"); the first kill moves everything to the ID key.
--
--  Every wish goes to the whole group, so every council member holds the list,
--  not only the master looter. Opening it again asks raiders who already sent
--  to send their wish once more, for anyone who missed it.
--
--  Wire:
--    WISHON    raid, size, lockKey, locked   ML     -> group (switched on, no window)
--    WISHPOST  raid, size, lockKey, gen, locked  ML -> group (Ask: opens the window)
--    WISHOFF   lockKey                       ML     -> group
--    WISHPICK  lockKey, itemId               raider -> group
--    WISHPASS  lockKey                       raider -> group (no wish this ID)
--    WISHLOCKED lockKey, itemId | "pass"     ML     -> raider (change refused)
--
--  /okwish test   your own wish window, solo
-- ============================================================

local Okanvil = Okanvil
local SR = Okanvil.SoftRes
if not SR then return end

local Wi = {}
Okanvil.Wish = Wi

-- A wish arriving (or the switch flipping) repaints the council board and the
-- Loot page's council panel, when they are up.
function Wi.onChange()
	local CC = Okanvil.Council
	if CC and CC.RepaintBoard then pcall(CC.RepaintBoard) end
	if CC and CC._paintState then pcall(CC._paintState) end
	-- the Loot page re-measures the council panel, which grows with the list
	if SR.onChange then pcall(SR.onChange) end
	-- the "Your wish" line under the mode cards
	if Okanvil.Loot_PaintMine then pcall(Okanvil.Loot_PaintMine) end
	-- the mini roll's WH button and the wish panel beside it
	local RM = Okanvil.RollMgr
	if RM and RM.SyncSRButton then pcall(RM.SyncSRButton) end
	if Wi.Panel then pcall(Wi.Panel.Sync); pcall(Wi.Panel.Paint) end
	-- the Loot page's Lock button
	if Wi._paintLock then pcall(Wi._paintLock) end
	-- the Loot page's Wishlist row: its buttons follow on / off
	if Wi._paintRow then pcall(Wi._paintRow) end
end

local KEEP_DAYS = 8

local function db()
	Okanvil.db.wish = Okanvil.db.wish or {}
	local d = Okanvil.db.wish
	d.list = d.list or {}
	d.open = d.open or {}      -- lockKey -> { at, locked }: the raid IDs it is open on
	-- the old saved switch: it kept the wishlist on into every raid after
	d.on, d.locked, d.gen = nil, nil, nil
	return d
end
local function stripRealm(n) return n and (n:gsub("%-.*$", "")) or n end
local function me() return UnitName("player") end

-- The master looter. Solo (no group) you are your own master looter, so the
-- commands can be tried out.
local function isML(who)
	who = stripRealm(who)
	if not who then return false end
	local inGroup = (GetNumRaidMembers() or 0) > 0 or (GetNumPartyMembers() or 0) > 0
	if not inGroup then return who == me() end
	local L = Okanvil.Loot
	local ml = L and L.MasterLooterName and L.MasterLooterName()
	return ml ~= nil and stripRealm(ml):lower() == who:lower()
end

-- The raid leader or an assist (rank 1 or 2 in the raid roster); in a party, its leader.
local function isAssist(who)
	who = stripRealm(who)
	if not who then return false end
	for i = 1, GetNumRaidMembers() or 0 do
		local n, rank = GetRaidRosterInfo(i)
		if n and stripRealm(n):lower() == who:lower() then return (rank or 0) >= 1 end
	end
	if (GetNumRaidMembers() or 0) == 0 and (GetNumPartyMembers() or 0) > 0 then
		if who == me() then return IsPartyLeader() and true or false end
		for i = 1, GetNumPartyMembers() do
			if (UnitName("party" .. i) or ""):lower() == who:lower() then
				return UnitIsPartyLeader("party" .. i) and true or false
			end
		end
	end
	return false
end

-- Whispered wishes go to the master looter, whoever opened the list.
local function mlName()
	local L = Okanvil.Loot
	local ml = L and L.MasterLooterName and L.MasterLooterName()
	return ml and stripRealm(ml) or me() or "me"
end

-- Who may open, ask, lock and clear it: the master looter and the assists.
local function canTrigger(who) return isML(who) or isAssist(who) end
Wi.CanTrigger = function() return canTrigger(me()) end

-- Who sees the list: the master looter and the officers (the council).
function Wi.CanSee()
	if canTrigger(me()) then return true end
	local U, who = Okanvil.U, me()
	return U and U.isOfficer and (U.isOfficer(who) or (U.isOfficerAlt and U.isOfficerAlt(who))) and true or false
end

-- ---- Raid ID keys -----------------------------------------------------------------
-- "icc25:20261021" before the first kill, "icc25:48213" after. A date key of the
-- same raid and size from the last few hours is this run: its wishes, its open
-- state and your own sent wish move to the ID key as soon as the ID is known.
local ADOPT_SECS = 12 * 3600
local function split(k) return k:match("^(.*):([^:]*)$") end
local function isDateKey(k) local _, t = split(k); return t ~= nil and t:match("^%d%d%d%d%d%d%d%d$") ~= nil end

local adopted        -- the ID key already adopted into: nothing new lands under a date key after
local function adopt(k)
	local base = split(k)
	if not base or isDateKey(k) or k == adopted then return end
	adopted = k
	local d, now = db(), time()
	-- the date keys of this raid and size from the last few hours (collected
	-- first: a table must not gain keys while pairs walks it)
	local function dateKeys(t, at, keyOf)
		local out = {}
		for tk, v in pairs(t) do
			local lk = keyOf(tk)
			if lk and split(lk) == base and isDateKey(lk) and now - (at(v) or 0) <= ADOPT_SECS then
				out[#out + 1] = tk
			end
		end
		return out
	end
	local function same(tk) return tk end

	for _, dk in ipairs(dateKeys(d.list, function(l) return l._at end, same)) do
		local l = d.list[dk]
		d.list[k] = d.list[k] or {}
		-- a wish already under the ID is newer: it stays
		for who, w in pairs(l) do
			if who ~= "_at" and not d.list[k][who] then d.list[k][who] = w end
		end
		d.list[k]._at = math.max(d.list[k]._at or 0, l._at or 0)
		d.list[dk] = nil
	end
	for _, dk in ipairs(dateKeys(d.open, function(o) return o.at end, same)) do
		if not d.open[k] then d.open[k] = d.open[dk] end
		d.open[dk] = nil
	end
	local mine = Okanvil.db.softres and Okanvil.db.softres.myPicks
	if mine then
		local tail = (":" .. (me() or "")):gsub("%p", "%%%0")
		local function lockOf(pk) return pk:match("^wish:(.*)" .. tail .. "$") end
		local nk = SR.PickKey("wish", k)
		for _, pk in ipairs(dateKeys(mine, function(p) return p.at end, lockOf)) do
			if not mine[nk] then mine[nk] = mine[pk] end
			mine[pk] = nil
		end
	end
end

-- The key of the raid ID being run, after moving a date key over to it.
local function curKey()
	local k = SR.LockKey()
	adopt(k)
	return k
end
Wi.Key = curKey

-- A key from the wire, as this client files it: the same raid and size is this
-- run, whichever of the date or the ID the sender knew at the time.
local function norm(lockKey)
	if not lockKey then return curKey() end
	local cur = curKey()
	return (split(lockKey) == split(cur)) and cur or lockKey
end

-- Open on this raid ID, or for this session by /okwish test (not saved, so a
-- test never leaves it open after a reload).
-- An entry with `off` is switched off but keeps its lock for when it is back on.
local function openState()
	local o = db().open[curKey()]
	return (o and not o.off) and o or nil
end
function Wi.IsOn() return (Wi._test or openState() ~= nil) and true or false end
-- Wishes are for the guild's 25-man raids only, normal or heroic.
local function is25() return (SR.Raid().size or 25) == 25 end
-- Wishes count only on a council night in a 25: open, and the loot mode is Council.
function Wi.Live() return Wi.IsOn() and (Wi._test or (SR.Mode() == "council" and is25())) and true or false end

-- "ICC 25 · Normal & Heroic": what a wish on this raid counts for.
function Wi.Label()
	local r = SR.Raid()
	return SR.RaidLabel({ key = r.key, size = 25 }) .. "  ·  Normal & Heroic"
end

local function prune()
	local d, cutoff = db(), time() - KEEP_DAYS * 86400
	for k, l in pairs(d.list) do
		if (l._at or 0) < cutoff then d.list[k] = nil end
	end
	for k, o in pairs(d.open) do
		if (o.at or 0) < cutoff then d.open[k] = nil end
	end
end

-- A change refused by the lock: the master looter tells that raider what stands,
-- so a client that missed the lock (offline when it came) shows the right wish.
local function refused(lockKey, who, w)
	if who == me() or not isML(me()) then return end
	local C = Okanvil.Comms
	if C and C.Whisper then C.Whisper("WISHLOCKED", who, lockKey, w.pass and "pass" or tostring(w.id)) end
end

-- One wish per raider per raid ID; a new one replaces it until the list is locked.
-- Locked, a raider who has a wish or a pass keeps it; one with neither (a late
-- joiner on the second night) can still send theirs.
local function store(lockKey, who, id)
	id = tonumber(id)
	if not (who and id) then return end
	lockKey = norm(lockKey)
	local d = db()
	if not Wi.IsOn() then return end
	d.list[lockKey] = d.list[lockKey] or {}
	local l = d.list[lockKey]
	local old = l[who]
	if old and old.id == id then return end
	if old and Wi.IsLocked() then refused(lockKey, who, old); return end
	l._at = time()
	l[who] = { id = id, name = GetItemInfo(id) }
	Okanvil:Trace("WISH", who .. (old and " changes wish to " or " wishes ") .. tostring(l[who].name or id))
	if Wi.onChange then Wi.onChange() end
end

-- A raider who wants nothing this raid ID: kept as a pass, so Ask missing
-- leaves them alone. A wish sent later replaces it.
local function storePass(lockKey, who)
	if not who then return end
	lockKey = norm(lockKey)
	local d = db()
	if not Wi.IsOn() then return end
	d.list[lockKey] = d.list[lockKey] or {}
	local l = d.list[lockKey]
	if l[who] and l[who].pass then return end
	if l[who] and Wi.IsLocked() then refused(lockKey, who, l[who]); return end
	l._at = time()
	l[who] = { pass = true }
	Okanvil:Trace("WISH", who .. " passes")
	if Wi.onChange then Wi.onChange() end
end

-- The item this raider wished for on this raid's lockout, or nil.
function Wi.Of(who)
	if not Wi.Live() then return nil end
	local l = db().list[curKey()]
	local w = l and l[stripRealm(who)]
	if w and w.pass then return nil end
	return w and w.id or nil, w and w.name
end

-- Every wish on this raid's lockout, sorted by player: { { who, id, name }, ... }.
-- A pass is { who, pass = true }.
function Wi.All()
	local out = {}
	local l = db().list[curKey()]
	for who, w in pairs(l or {}) do
		if who ~= "_at" and type(w) == "table" then
			if w.pass then
				out[#out + 1] = { who = who, pass = true }
			else
				out[#out + 1] = { who = who, id = w.id, name = w.name or GetItemInfo(w.id) }
			end
		end
	end
	table.sort(out, function(a, b) return a.who < b.who end)
	return out
end

-- Did this raider wish for this item? Matched by name too: the normal and the
-- heroic copy are different ids for the same wish.
function Wi.Wants(who, link)
	local id, wname = Wi.Of(who)
	if not id then return false end
	local want = Okanvil.U.itemIDFromLink(link)
	if want == id then return true end
	local name = GetItemInfo(link or want)
	wname = wname or GetItemInfo(id)
	return name ~= nil and name == wname
end

local mySent, openWhenCalm      -- defined below, used by SetOn

-- A line for the whole group, Okanvil or not: a raid warning when we may send one.
local function announce(msg)
	local inRaid = (GetNumRaidMembers() or 0) > 0
	local chan = inRaid and ((IsRaidLeader() or IsRaidOfficer()) and "RAID_WARNING" or "RAID")
		or ((GetNumPartyMembers() or 0) > 0 and "PARTY") or nil
	if chan then SendChatMessage(msg, chan) end
end

-- ---- Master looter: open / close -------------------------------------------------
function Wi.SetOn(on)
	if on and not is25() then
		Okanvil:Print("|cffff5555Wishlist not opened:|r wishes are for 25-man raids only, and this raid is "
			.. SR.RaidLabel() .. ". Set the raid difficulty to 25.")
		return
	end
	local d = db()
	local lockKey = curKey()
	if not on then Wi._test = nil end
	local C = Okanvil.Comms
	if on then
		local r = SR.Raid()
		prune()
		-- back on keeps a lock: only Unlock or Clear lifts it
		d.open[lockKey] = d.open[lockKey] or { at = time() }
		d.open[lockKey].off = nil
		d.open[lockKey].asked = nil
		-- on, quietly: nobody's window opens until Ask
		if C and C.Send then C.Send("WISHON", r.key, r.size, lockKey, Wi.IsLocked() and "1" or "0") end
		Okanvil:Print("Wishlist on for this raid ID. Press Ask to send the wish window.")
	else
		-- off, not forgotten: the lock stays for when it is switched on again
		if d.open[lockKey] then d.open[lockKey].off = true end
		if C and C.Send then C.Send("WISHOFF", lockKey) end
		if SR.PickWindow and SR.PickWindow.HideKind then SR.PickWindow.HideKind("wish") end
		Okanvil:Print("Wishlist off.")
	end
	if Wi.onChange then Wi.onChange() end
end

-- Ask is the only thing that sends the wish window: it opens for raiders who
-- have neither sent a wish nor passed; everyone else just sends theirs again.
-- The first Ask of a round (after switching it on, or after a Clear) also puts a
-- raid warning up, for raiders without Okanvil; a later one (a late joiner) is
-- quiet. Works while locked: the lock holds the wishes already in.
function Wi.AskMissing()
	if not Wi.Live() then Okanvil:Print("The wishlist is not on."); return end
	local r, lockKey = SR.Raid(), curKey()
	local C = Okanvil.Comms
	if C and C.Send then C.Send("WISHPOST", r.key, r.size, lockKey, 0, Wi.IsLocked() and "1" or "0") end
	local o = openState()
	if o and not o.asked then
		o.asked = true
		announce(Wi.IsLocked()
			and ("WISHLIST: no wish yet for this raid ID? Pick 1 item in Okanvil, or whisper %s: wh [item]."):format(mlName())
			or ("WISHLIST open: pick 1 item for this raid ID in Okanvil, or whisper %s: wh [item]. "
				.. "You can change it until the list is locked. It is not a reserve."):format(mlName()))
	end
	-- the master looter raids too: they get the window like everyone else
	if not mySent(lockKey) then
		openWhenCalm({ r.key, r.size, false, 1, lockKey, me(), "0", "wish" })
	end
	Okanvil:Print("Wish window sent to everyone without a wish.")
end

-- Clear every wish on this raid ID, everywhere: the officers' lists and each
-- raider's own sent wish, so Ask reaches everyone again.
-- With no lockKey every raid ID goes: a wish saved under another raid, size or
-- day would otherwise still show as "Your wish" after a Clear.
local function wipeLocal(lockKey)
	local s = Okanvil.db.softres and Okanvil.db.softres.myPicks
	if lockKey then
		db().list[lockKey] = nil
		if s then s[SR.PickKey("wish", lockKey)] = nil end
	else
		db().list = {}
		for k in pairs(s or {}) do
			if k:find("^wish:") then s[k] = nil end
		end
	end
	if Okanvil.Loot_PaintMine then pcall(Okanvil.Loot_PaintMine) end
	if Wi.onChange then Wi.onChange() end
end

function Wi.Clear()
	local lockKey = curKey()
	wipeLocal()
	local C = Okanvil.Comms
	if C and C.Send then C.Send("WISHCLEAR", lockKey) end
	-- a clear also lifts the lock; nobody's window opens until Ask, whose next
	-- press is a new round with its raid warning
	if Wi.IsLocked() then Wi.SetLocked(false, true) end
	local o = db().open[lockKey]
	if o then o.asked = nil end
	Okanvil:Print("Wishes cleared for this raid ID. Press Ask to send the wish window.")
end

-- Lock: the wishes and passes already sent are final for this raid ID. A raider
-- with neither can still send one (Ask). It lasts across nights and an off / on
-- of the wishlist; only Unlock or Clear lifts it.
function Wi.IsLocked()
	local o = db().open[curKey()]
	return (o and o.locked) and true or false
end
-- Locked and this character already has a wish or a pass: nothing to change.
function Wi.Frozen() return Wi.IsLocked() and mySent(curKey()) ~= nil end
-- Can this character send (or change) a wish right now?
function Wi.Accepting() return Wi.Live() and not Wi.Frozen() end
local function applyLock(locked)
	local d, k = db(), curKey()
	if locked and not d.open[k] then d.open[k] = { at = time(), off = true } end
	if d.open[k] then d.open[k].locked = locked or nil end
	if Wi.Frozen() and SR.PickWindow and SR.PickWindow.HideKind then SR.PickWindow.HideKind("wish") end
	if Wi.onChange then Wi.onChange() end
end
function Wi.SetLocked(locked, quiet)
	applyLock(locked)
	local C = Okanvil.Comms
	if C and C.Send then C.Send("WISHLOCK", locked and "1" or "0") end
	if quiet then return end
	announce(locked and "WISHLIST LOCKED: wishes are final for this raid ID. If you have none yet, you can still pick one."
		or "WISHLIST open again: pick or change 1 item in Okanvil, or whisper " .. mlName() .. ": wh [item].")
	Okanvil:Print(locked and "Wishlist locked: wishes are final, raiders without one can still pick."
		or "Wishlist unlocked.")
end

-- ---- Raider: send -------------------------------------------------------------
function Wi.SendPick(lockKey, id)
	if not id then return end
	if not Wi.Live() then      -- the window checked the lock before saving the pick
		Okanvil:Print("The wishlist is closed: wish not sent.")
		return
	end
	lockKey = norm(lockKey)
	store(lockKey, me(), id)
	local C = Okanvil.Comms
	if C and C.Send and C.Send("WISHPICK", lockKey, id) then
		Okanvil:Print("Wish sent to the council.")
	else
		Okanvil:Print("Wish saved.")
	end
end

-- No wish this raid ID: the window never opens for you again on it.
function Wi.SendPass(lockKey)
	if not Wi.Live() then      -- the window checked the lock before saving the pass
		Okanvil:Print("The wishlist is closed.")
		return
	end
	lockKey = norm(lockKey)
	storePass(lockKey, me())
	local C = Okanvil.Comms
	if C and C.Send then C.Send("WISHPASS", lockKey) end
	Okanvil:Print("Pass sent: no wish this raid ID.")
end

-- The wish this character already sent on a lockout (the pick window keeps it),
-- or "pass".
mySent = function(lockKey)
	local s = Okanvil.db.softres and Okanvil.db.softres.myPicks
	local p = s and s[SR.PickKey("wish", lockKey)]
	if not (p and p.sentGen ~= nil) then return nil end
	if p.pass then return "pass" end
	return p.list and p.list[1] or nil
end

-- ---- Wire -----------------------------------------------------------------------
local pending
openWhenCalm = function(args)
	if not Wi.Live() then return end
	if UnitAffectingCombat and UnitAffectingCombat("player") then pending = args; return end
	SR.PickWindow.Open(unpack(args))
end
local calm = CreateFrame("Frame")
calm:RegisterEvent("PLAYER_REGEN_ENABLED")
calm:SetScript("OnEvent", function()
	if pending then local a = pending; pending = nil; SR.PickWindow.Open(unpack(a)) end
end)

do
	local C = Okanvil.Comms
	if C and C.On then
		C.On("WISHPOST", function(sender, raid, size, lockKey, g, locked)
			sender = stripRealm(sender)
			if sender == me() then return end
			if not canTrigger(sender) then return end
			if tonumber(size) ~= 25 then return end
			lockKey = norm(lockKey)
			local d = db()
			d.open[lockKey] = d.open[lockKey] or { at = time() }
			d.open[lockKey].off = nil
			-- the sender says whether it is locked (an older build sends nothing: open)
			d.open[lockKey].locked = (locked == "1") or nil
			if Wi.onChange then Wi.onChange() end
			-- already sent this ID: send it again for whoever missed it, no window
			local sent = mySent(lockKey)
			if sent == "pass" then
				C.Send("WISHPASS", lockKey)
				return
			elseif sent then
				C.Send("WISHPICK", lockKey, sent)
				return
			end
			openWhenCalm({ raid, size, false, 1, lockKey, sender, g or "0", "wish" })
		end)
		-- switched on: the list is open on this raid ID, no window until Ask
		C.On("WISHON", function(sender, raid, size, lockKey, locked)
			sender = stripRealm(sender)
			if sender == me() or not canTrigger(sender) or tonumber(size) ~= 25 then return end
			lockKey = norm(lockKey)
			local d = db()
			d.open[lockKey] = d.open[lockKey] or { at = time() }
			d.open[lockKey].off = nil
			d.open[lockKey].locked = (locked == "1") or nil
			if Wi.onChange then Wi.onChange() end
		end)
		C.On("WISHOFF", function(sender, lockKey)
			if not canTrigger(sender) then return end
			local o = db().open[norm(lockKey)]
			if o then o.off = true end
			pending = nil
			if SR.PickWindow and SR.PickWindow.HideKind then SR.PickWindow.HideKind("wish") end
			if Wi.onChange then Wi.onChange() end
		end)
		C.On("WISHLOCK", function(sender, v)
			if not canTrigger(sender) or stripRealm(sender) == me() then return end
			applyLock(v == "1")
		end)
		C.On("WISHCLEAR", function(sender, lockKey)
			if not canTrigger(sender) or stripRealm(sender) == me() then return end
			wipeLocal(norm(lockKey))
			local o = db().open[norm(lockKey)]
			if o then o.locked = nil end
		end)
		C.On("WISHPICK", function(sender, lockKey, id)
			store(lockKey, stripRealm(sender), id)
		end)
		C.On("WISHPASS", function(sender, lockKey)
			storePass(lockKey, stripRealm(sender))
		end)
		-- our change was refused, the list is locked: this is the wish that stands
		C.On("WISHLOCKED", function(sender, lockKey, v)
			if not canTrigger(sender) or not v then return end
			lockKey = norm(lockKey)
			local d = db()
			d.open[lockKey] = d.open[lockKey] or { at = time() }
			d.open[lockKey].locked = true
			d.list[lockKey] = d.list[lockKey] or {}
			local s = Okanvil.db.softres
			if v == "pass" then
				d.list[lockKey][me()] = { pass = true }
				if s then
					s.myPicks = s.myPicks or {}
					s.myPicks[SR.PickKey("wish", lockKey)] = { at = time(), list = {}, sentGen = 0, pass = true }
				end
				Okanvil:Print("The wishlist is locked: you passed on this raid ID.")
			elseif tonumber(v) then
				local id = tonumber(v)
				d.list[lockKey][me()] = { id = id, name = GetItemInfo(id) }
				if SR.PickWindow and SR.PickWindow.MarkSent then SR.PickWindow.MarkSent("wish", lockKey, id) end
				local _, link = GetItemInfo(id)
				Okanvil:Print("The wishlist is locked: your wish stays " .. (link or ("item " .. id)) .. ".")
			end
			if SR.PickWindow and SR.PickWindow.HideKind then SR.PickWindow.HideKind("wish") end
			if Okanvil.Loot_PaintMine then pcall(Okanvil.Loot_PaintMine) end
			if Wi.onChange then Wi.onChange() end
		end)
		-- a wish someone whispered to the master looter, passed on for them
		C.On("WISHFOR", function(sender, lockKey, id, who)
			if not canTrigger(sender) or not who or who == "" then return end
			who = stripRealm(who)
			lockKey = norm(lockKey)
			store(lockKey, who, id)
			-- our own whisper: it is our wish too, not only a line on the officers' list
			if who == me() and tonumber(id) and SR.PickWindow and SR.PickWindow.MarkSent then
				SR.PickWindow.MarkSent("wish", lockKey, tonumber(id))
			end
		end)
	end
end

-- ---- Whispers: "wh [item]" for raiders without Okanvil ----------------------------
-- The master looter answers "wh [item]" / "wish [item]": the wish is saved,
-- passed to the council, and confirmed by whisper. One per raid ID, like the
-- window; a second whisper changes it until the list is locked.
local function reply(to, text) SendChatMessage(text, "WHISPER", nil, to) end

local function onWhisper(text, sender)
	-- the master looter alone answers, so a whisper gets one reply
	if not (Wi.Live() and isML(me())) then return end
	local rest = text:match("^%s*[Ww][Hh]%s+(.+)$") or text:match("^%s*[Ww][Ii][Ss][Hh]%s+(.+)$")
	if not rest then return end
	local who = stripRealm(sender)
	local id = tonumber(rest:match("item:(%d+)"))
	if not id and SR.FindItemByName then id = SR.FindItemByName((rest:gsub("[%[%]]", ""))) end
	if not id then
		reply(sender, "Wish: item not found. Whisper me: wh [item link]")
		return
	end
	if SR.DropsHere and not SR.DropsHere(id) then
		reply(sender, "Wish: that item does not drop in this raid.")
		return
	end
	local lockKey = curKey()
	local l = db().list[lockKey]
	local had = l and l[who]
	if had and had.id == id then
		reply(sender, "Wish: that is already your wish for this raid ID.")
		return
	end
	-- locked: a wish or pass already in stays; a first wish is still taken
	if had and Wi.IsLocked() then
		reply(sender, "Wish: the wishlist is locked, your wish for this raid ID stays.")
		return
	end
	store(lockKey, who, id)
	local C = Okanvil.Comms
	if C and C.Send then C.Send("WISHFOR", lockKey, id, who) end
	local _, link = GetItemInfo(id)
	if had then
		local _, hl = GetItemInfo(had.id)
		reply(sender, "Wish changed: " .. (hl or had.name or "?") .. " -> " .. (link or ("item " .. id))
			.. " -- you can change it until the list is locked.")
	else
		reply(sender, "Wish saved: " .. (link or ("item " .. id))
			.. " -- you can change it until the list is locked. It is not a reserve.")
	end
end

local wev = CreateFrame("Frame")
wev:RegisterEvent("CHAT_MSG_WHISPER")
wev:SetScript("OnEvent", function(_, _, text, sender)
	if text and sender then
		local ok, err = pcall(onWhisper, text, sender)
		if not ok and Okanvil.Err then Okanvil:Err("Wishlist whisper", err) end
	end
end)

-- ---- WH panel: every wish, docked beside the mini roll ---------------------------
-- The council-night twin of the SR panel, opened from the mini roll's WH button.
-- Officers only, and only while the wishlist is on.
local WP = {}
Wi.Panel = WP
local wpanel
-- Same look as the SR panel: items under their boss, icon and name, who wished
-- for it underneath, and what became of it tonight.
local WP_W, WP_PAD, WP_ICON, WP_GAP, WP_HDR = 290, 14, 28, 6, 26
local WP_MIN, WP_MAX = 110, 560
-- where the list starts: the title bar sits 6px inside the window's edge
local WP_TOP = WP_HDR + 6

local function rollWin() return _G.Okanvil_RollMgr end

local function wbuild()
	if wpanel then return wpanel end
	local W = Okanvil.W
	local f = CreateFrame("Frame", "Okanvil_WishPanel", UIParent)
	f:SetWidth(WP_W); f:SetHeight(WP_MIN)
	f:SetFrameStrata("DIALOG"); f:SetFrameLevel(10)
	Okanvil:Skin(f, "panel")
	local br, bg, bb = f:GetBackdropColor()
	if br then f:SetBackdropColor(br, bg, bb, 0.97) end
	f:EnableMouse(true); f:SetClampedToScreen(true)
	if W.ForgeArt then W.ForgeArt(f, 0.22) end

	-- the mini roll's title bar: its top corners follow the window's cut
	local hdr = W.TitleBar(f, WP_HDR)
	local title = hdr.title
	title:ClearAllPoints(); title:SetPoint("LEFT", 4, 0); title:SetJustifyH("LEFT")
	title:SetText("Wishes")
	local close = W.CloseButton(hdr); close:SetSize(18, 18); close:SetPoint("RIGHT", -2, 0)
	close:SetScript("OnClick", function() WP.Hide(true) end)
	local clr = W.Button(hdr, "Clear"); clr:SetSize(44, 18); clr:SetPoint("RIGHT", close, "LEFT", -4, 0)
	clr:Tooltip("Clear every wish on this raid ID and unlock it.\nThe window opens again only when you press Ask.")
	clr:SetScript("OnClick", function()
		Okanvil:Confirm("Clear every wish on this raid ID?\n|cff8a8d93Press Ask after to send the wish window.|r", "Clear", Wi.Clear)
	end)
	f.clr = clr
	local ask = W.Button(hdr, "Ask"); ask:SetSize(36, 18); ask:SetPoint("RIGHT", clr, "LEFT", -4, 0)
	ask:Tooltip("Open the wish window for everyone without a wish (late joiners).\n"
		.. "Not for those who already picked or passed. No raid warning.")
	ask:SetScript("OnClick", function() Wi.AskMissing() end)
	f.ask = ask
	-- after the title, cut short before the buttons: never on top of the title
	f.count = W.Text(hdr, "", "note", "dim")
	f.count:SetPoint("LEFT", title, "RIGHT", 8, 0)
	f.count:SetPoint("RIGHT", ask, "LEFT", -6, 0)
	f.count:SetJustifyH("LEFT")
	if f.count.SetWordWrap then f.count:SetWordWrap(false) end

	-- flat scroll, like the SR panel
	local sf = CreateFrame("ScrollFrame", nil, f)
	sf:SetPoint("TOPLEFT", WP_PAD, -(WP_TOP + 6)); sf:SetPoint("BOTTOMRIGHT", -WP_PAD - 6, WP_PAD)
	local child = CreateFrame("Frame", nil, sf)
	child:SetWidth(WP_W - WP_PAD * 2 - 6); child:SetHeight(1)
	sf:SetScrollChild(child)
	if Okanvil.Clip then Okanvil.Clip(sf) end
	local sb = CreateFrame("Slider", nil, f)
	sb:SetPoint("TOPRIGHT", -9, -(WP_TOP + 6)); sb:SetPoint("BOTTOMRIGHT", -9, WP_PAD); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1); sb:SetMinMaxValues(0, 0); sb:SetValue(0)
	local th = sb:CreateTexture(nil, "OVERLAY")
	th:SetTexture("Interface\\Buttons\\WHITE8x8")
	local ac = Okanvil.Colors and Okanvil.Colors.accent or { 0.75, 0.58, 0.23 }
	th:SetVertexColor(ac[1], ac[2], ac[3]); th:SetSize(4, 30)
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, dz) sb:SetValue(sb:GetValue() - dz * 60) end)
	f.sf, f.child, f.sb = sf, child, sb
	f.heads, f.rows = {}, {}

	-- items this client has not seen yet arrive over a second or two
	f:SetScript("OnUpdate", function(s, e)
		if not s._cold then return end
		s._acc = (s._acc or 0) + e
		if s._acc >= 1 then s._acc = 0; WP.Paint() end
	end)
	wpanel = f
	f:Hide()
	return f
end

local function wHead(i)
	local W = Okanvil.W
	local h = wpanel.heads[i]
	if h then return h end
	h = CreateFrame("Frame", nil, wpanel.child)
	h:SetHeight(18)
	h.txt = W.Text(h, "", "note", "accent")
	h.txt:SetPoint("BOTTOMLEFT", 0, 3)
	W.Hairline(h, "BOTTOM", 0)
	wpanel.heads[i] = h
	return h
end

local function wRow(i)
	local W = Okanvil.W
	local r = wpanel.rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, wpanel.child)
	r:EnableMouse(true)
	-- the kit's grey octagon around the icon
	r.ic = W.FramedIcon(r, nil, WP_ICON, false)
	r.ic:SetPoint("TOPLEFT", 0, -2)
	r.icon = r.ic.icon
	r.status = W.Text(r, "", "note")
	r.status:SetPoint("TOPRIGHT", -4, -3); r.status:SetJustifyH("RIGHT")
	r.name = W.Text(r, "", 11)
	r.name:SetPoint("TOPLEFT", r.ic, "TOPRIGHT", WP_GAP, -3)
	r.name:SetPoint("RIGHT", r.status, "LEFT", -6, 0)
	r.name:SetJustifyH("LEFT")
	if r.name.SetWordWrap then r.name:SetWordWrap(false) end
	r.who = W.Text(r, "", "note")
	r.who:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
	r.who:SetWidth(WP_W - WP_PAD * 2 - WP_ICON - WP_GAP - 10)
	r.who:SetJustifyH("LEFT")
	r:SetScript("OnEnter", function(s)
		if not s._id then return end
		GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. s._id); GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	wpanel.rows[i] = r
	return r
end

-- The boss an item drops from in the raid being run, by id or by name (the
-- heroic copy is another id). "Other" when the loot table does not know it.
local function bossOf(id, name)
	local r = SR.Raid()
	for _, b in ipairs(OkanvilRaidLoot and OkanvilRaidLoot[r.key] or {}) do
		for _, it in ipairs(b.items or {}) do
			if it.id == id or (name and it.name == name) then return b.boss end
		end
	end
	return "Other"
end

-- What happened to each item tonight: how many dropped, who won them.
local function dropStatus()
	local L = Okanvil.Loot
	local st = {}
	for _, g in ipairs(L and L.DropsByBoss and L.DropsByBoss() or {}) do
		for _, dp in ipairs(g.items or {}) do
			local id = tonumber(dp.id)
			if id then
				local s = st[id] or { n = 0, won = {} }
				st[id] = s
				s.n = s.n + 1
				local wn = L.RollWinner and L.RollWinner(dp)
				local who = (wn and wn.player) or (dp.awarded and dp.receivedBy) or nil
				if who and who ~= "" then s.won[#s.won + 1] = who end
			end
		end
	end
	return st
end

local function wdock()
	local rm = rollWin()
	if not (wpanel and rm) then return end
	wpanel:ClearAllPoints()
	local cx = rm:GetCenter()
	if cx and cx > (UIParent:GetWidth() / 2) then
		wpanel:SetPoint("TOPRIGHT", rm, "TOPLEFT", -4, 0)
	else
		wpanel:SetPoint("TOPLEFT", rm, "TOPRIGHT", 4, 0)
	end
end

function WP.Paint()
	if not (wpanel and wpanel:IsShown()) then return end
	local W, L, f = Okanvil.W, Okanvil.Loot, wpanel

	-- one entry per item, with everyone who wished for it, ordered by boss
	local byItem, items, passes = {}, {}, {}
	for _, w in ipairs(Wi.All()) do
		if w.pass then
			passes[#passes + 1] = w.who
		else
			local name = w.name or GetItemInfo(w.id)
			local key = name or w.id
			local e = byItem[key]
			if not e then
				e = { id = w.id, name = name, who = {}, boss = bossOf(w.id, name) }
				byItem[key] = e
				items[#items + 1] = e
			end
			e.who[#e.who + 1] = w.who
		end
	end
	local order = {}
	for i, b in ipairs(OkanvilRaidLoot and OkanvilRaidLoot[SR.Raid().key] or {}) do order[b.boss] = i end
	table.sort(items, function(a, b)
		local oa, ob = order[a.boss] or 99, order[b.boss] or 99
		if oa ~= ob then return oa < ob end
		return (a.name or "") < (b.name or "")
	end)

	local st = dropStatus()
	-- who is in the group now; a wisher who left is greyed out
	local here, grouped = { [(me() or ""):lower()] = true }, false
	local n, unit = GetNumRaidMembers() or 0, "raid"
	if n == 0 then n, unit = GetNumPartyMembers() or 0, "party" end
	for i = 1, n do local nm = UnitName(unit .. i); if nm then here[nm:lower()] = true end end
	grouped = n > 0

	for _, h in ipairs(f.heads) do h:Hide() end
	for _, r in ipairs(f.rows) do r:Hide() end
	local y, hi, ri, cold, people, lastBoss = 0, 0, 0, false, 0, nil
	local width = f.child:GetWidth()
	for _, it in ipairs(items) do
		if it.boss ~= lastBoss then
			lastBoss = it.boss
			hi = hi + 1
			local h = wHead(hi)
			h:SetPoint("TOPLEFT", 0, -y); h:SetWidth(width)
			h.txt:SetText(it.boss)
			h:Show()
			y = y + 18 + 4
		end
		ri = ri + 1
		local r = wRow(ri)
		r._id = it.id
		local iname, _, rarity, _, _, _, _, _, _, tex = GetItemInfo(it.id)
		if not iname then cold = true end
		r.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
		local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[rarity or 4]
		r.name:SetText((qc and qc.hex or "|cffa335ee") .. (iname or it.name or ("item " .. it.id)) .. "|r")

		local s = st[it.id]
		if s and #s.won > 0 then
			local w = {}
			for _, who in ipairs(s.won) do w[#w + 1] = (L and L.ClassColorName and L.ClassColorName(who)) or who end
			r.status:SetText("|cffffd200won|r " .. table.concat(w, ", "))
		elseif s then
			r.status:SetText("|cffffd200dropped" .. (s.n > 1 and (" x" .. s.n) or "") .. "|r")
		else
			r.status:SetText("")
		end

		local names = {}
		for _, who in ipairs(it.who) do
			people = people + 1
			if grouped and not here[who:lower()] then
				names[#names + 1] = "|cff5e6166" .. who .. "|r"
			else
				names[#names + 1] = (L and L.ClassColorName and L.ClassColorName(who)) or who
			end
		end
		r.who:SetText(table.concat(names, "|cff6f7176, |r"))

		local rh = math.max(WP_ICON + 6, 3 + (r.name:GetStringHeight() or 12) + 3 + (r.who:GetStringHeight() or 10) + 6)
		r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(width); r:SetHeight(rh)
		r:Show()
		y = y + rh + 2
	end
	f._cold = cold

	-- who passed: no wish this raid ID, and Ask missing leaves them alone
	if #passes > 0 then
		table.sort(passes)
		hi = hi + 1
		local h = wHead(hi)
		h:SetPoint("TOPLEFT", 0, -y); h:SetWidth(width)
		h.txt:SetText("Pass")
		h:Show()
		y = y + 18 + 4
		f.passTxt = f.passTxt or W.Text(f.child, "", "note")
		f.passTxt:ClearAllPoints(); f.passTxt:SetPoint("TOPLEFT", 0, -y)
		f.passTxt:SetWidth(width); f.passTxt:SetJustifyH("LEFT")
		local names = {}
		for _, who in ipairs(passes) do
			people = people + 1
			names[#names + 1] = (L and L.ClassColorName and L.ClassColorName(who)) or who
		end
		f.passTxt:SetText(table.concat(names, "|cff6f7176, |r"))
		f.passTxt:Show()
		y = y + (f.passTxt:GetStringHeight() or 12) + 4
	elseif f.passTxt then
		f.passTxt:Hide()
	end
	y = y + 8

	if #items == 0 and #passes == 0 then
		f.empty = f.empty or W.Text(f.child, "Nobody has sent a wish yet.", "note", "dim")
		f.empty:SetPoint("TOPLEFT", 0, -4); f.empty:SetWidth(width); f.empty:SetJustifyH("LEFT")
		f.empty:Show()
		y = 40
	elseif f.empty then
		f.empty:Hide()
	end

	local ni = #items
	f.count:SetText(("%s  ·  %d item%s, %d raider%s"):format(SR.RaidLabel({ key = SR.Raid().key, size = 25 }),
		ni, ni == 1 and "" or "s", people, people == 1 and "" or "s"))
	-- the council reads the list; only the master looter asks and clears it
	if canTrigger(me()) then f.clr:Show(); f.ask:Show() else f.clr:Hide(); f.ask:Hide() end

	f.child:SetHeight(math.max(1, y))
	local h = math.min(WP_MAX, math.max(WP_MIN, WP_TOP + 6 + y + WP_PAD))
	f:SetHeight(h)
	local view = h - (WP_TOP + 6) - WP_PAD
	local maxScroll = math.max(0, y - view)
	f.sb:SetMinMaxValues(0, maxScroll)
	if f.sb:GetValue() > maxScroll then f.sb:SetValue(maxScroll) end
	if maxScroll > 0 then f.sb:Show() else f.sb:Hide(); f.sf:SetVerticalScroll(0) end
end

-- Whether the WH button and panel belong on screen: council night, wishlist
-- open, and you are the master looter or an officer.
function WP.Allowed()
	local rm = rollWin()
	return SR.Mode() == "council" and Wi.IsOn() and Wi.CanSee() and rm and rm:IsShown() and true or false
end

-- Closed by default: WH opens it, and it closes again with the mini roll.
local wpOpen

function WP.Show()
	wpOpen = true
	local rm = rollWin()
	-- closes with the mini roll; opening it again is WH
	if rm and not rm._wishHooked then
		rm._wishHooked = true
		rm:HookScript("OnHide", function() WP.Hide(true) end)
		rm:HookScript("OnShow", function() WP.Sync() end)
	end
	if not WP.Allowed() then return end
	wbuild(); wdock(); wpanel:Show(); WP.Paint()
end

function WP.Hide(forget)
	if forget then wpOpen = nil end
	if wpanel then wpanel:Hide() end
end

function WP.Toggle()
	if wpanel and wpanel:IsShown() then WP.Hide(true) else WP.Show() end
end

function WP.Sync()
	if wpOpen and WP.Allowed() then WP.Show() else WP.Hide(false) end
end

-- ---- Test ----------------------------------------------------------------------
-- The window as a raider sees it, sending to yourself. Your earlier wish on
-- this ID is dropped first so it can be run again.
function Wi.Test()
	local d = db()
	if Wi.IsLocked() then Okanvil:Print("The wishlist is locked: no new wishes."); return end
	Wi._test = true
	-- wishes are for 25s: the test is the 25 of the raid picked
	local r = SR.Raid()
	r = { key = r.key, size = 25, hc = r.hc }
	local lockKey = SR.LockKey(r)
	if d.list[lockKey] then d.list[lockKey][me()] = nil end
	local s = Okanvil.db.softres and Okanvil.db.softres.myPicks
	if s then s[SR.PickKey("wish", lockKey)] = nil end
	SR.PickWindow.Open(r.key, r.size, false, 1, lockKey, me(), "0", "wish")
	if Wi.onChange then Wi.onChange() end
end

-- Your own wish window again, to change the wish before the list is locked.
function Wi.OpenMine()
	if not Wi.Live() then Okanvil:Print("The wishlist is not open on this raid."); return end
	if Wi.Frozen() then Okanvil:Print("The wishlist is locked: your wish can no longer change."); return end
	local r = SR.Raid()
	local L = Okanvil.Loot
	local ml = L and L.MasterLooterName and L.MasterLooterName()
	SR.PickWindow.Open(r.key, 25, false, 1, curKey(), ml and stripRealm(ml) or me(), "0", "wish")
end

SLASH_OKWISH1 = "/okwish"
-- master looter and assist commands: arg -> what it does
local ML_CMD = {
	clear = Wi.Clear, reset = Wi.Clear,
	on = function() Wi.SetOn(true) end, off = function() Wi.SetOn(false) end,
	lock = function() Wi.SetLocked(true) end, unlock = function() Wi.SetLocked(false) end,
}
SlashCmdList.OKWISH = function(arg)
	arg = (arg or ""):lower()
	if arg == "test" then Wi.Test(); return end
	if arg == "" then Wi.OpenMine(); return end
	local fn = ML_CMD[arg]
	if not fn then Okanvil:Print("/okwish (your wish) | on | off | lock | unlock | clear | test"); return end
	if not canTrigger(me()) then Okanvil:Print("Only the master looter or an assist can do that."); return end
	fn()
end
