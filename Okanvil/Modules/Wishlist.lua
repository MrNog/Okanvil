-- ============================================================
--  Okanvil -- Wishlist: what each raider is after this raid ID.
--
--  Optional, off by default. Any officer (or the raid leader / master looter)
--  turns it on; raiders with Okanvil then get the soft-reserve pick window as
--  a wish window: one item per raid ID, sent once. It is NOT a reserve -- it
--  only tells the council, on the board, that this item is what that raider is
--  hunting. The council still decides.
--
--  Every wish goes to the whole group, so every council member holds the list,
--  not only whoever turned it on. Turning it on again asks raiders who already
--  sent to send their wish once more, for anyone who missed it.
--
--  Wire:
--    WISHPOST  raid, size, lockKey, gen      officer -> group (opens the window)
--    WISHOFF                                 officer -> group
--    WISHPICK  lockKey, itemId               raider  -> group
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
end

local KEEP_DAYS = 8

local function db()
	Okanvil.db.wish = Okanvil.db.wish or {}
	local d = Okanvil.db.wish
	d.list = d.list or {}
	return d
end
local function stripRealm(n) return n and (n:gsub("%-.*$", "")) or n end
local function me() return UnitName("player") end

-- Who may switch it on: an officer (or an officer's alt), the raid leader, or
-- the master looter.
local function canTrigger(who)
	who = stripRealm(who)
	local U = Okanvil.U
	if U and U.isOfficer and (U.isOfficer(who) or (U.isOfficerAlt and U.isOfficerAlt(who))) then return true end
	return SR.IsLeadOrML and SR.IsLeadOrML(who) or false
end
Wi.CanTrigger = function() return canTrigger(me()) end

function Wi.IsOn() return db().on and true or false end

local function prune()
	local d, cutoff = db(), time() - KEEP_DAYS * 86400
	for k, l in pairs(d.list) do
		if (l._at or 0) < cutoff then d.list[k] = nil end
	end
end

local function store(lockKey, who, id)
	id = tonumber(id)
	if not (lockKey and who and id) then return end
	local d = db()
	d.list[lockKey] = d.list[lockKey] or {}
	local l = d.list[lockKey]
	l._at = time()
	-- one wish per raid ID: the first one sent stands
	if l[who] then return end
	l[who] = { id = id, name = GetItemInfo(id) }
	Okanvil:Trace("WISH", who .. " wishes " .. tostring(l[who].name or id))
	if Wi.onChange then Wi.onChange() end
end

-- The item this raider wished for on this raid's lockout, or nil.
function Wi.Of(who)
	if not Wi.IsOn() then return nil end
	local l = db().list[SR.LockKey()]
	local w = l and l[stripRealm(who)]
	return w and w.id or nil, w and w.name
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

-- ---- Officer: on / off --------------------------------------------------------
function Wi.SetOn(on)
	local d = db()
	d.on = on and true or false
	local C = Okanvil.Comms
	if d.on then
		local r = SR.Raid()
		local lockKey = SR.LockKey(r)
		d.gen = d.gen or {}
		d.gen[lockKey] = d.gen[lockKey] or 0
		prune()
		if C and C.Send then C.Send("WISHPOST", r.key, r.size, lockKey, d.gen[lockKey]) end
		Okanvil:Print("Wishlist on: raiders with Okanvil get the wish window.")
	else
		if C and C.Send then C.Send("WISHOFF") end
		Okanvil:Print("Wishlist off.")
	end
	if Wi.onChange then Wi.onChange() end
end

-- ---- Raider: send -------------------------------------------------------------
function Wi.SendPick(lockKey, id)
	if not id then return end
	store(lockKey, me(), id)
	local C = Okanvil.Comms
	if C and C.Send and C.Send("WISHPICK", lockKey, id) then
		Okanvil:Print("Wish sent to the council.")
	else
		Okanvil:Print("Wish saved.")
	end
end

-- The wish this character already sent on a lockout (the pick window keeps it).
local function mySent(lockKey)
	local s = Okanvil.db.softres and Okanvil.db.softres.myPicks
	local p = s and s["wish:" .. lockKey .. ":" .. (me() or "")]
	return p and p.sentGen ~= nil and p.list and p.list[1] or nil
end

-- ---- Wire -----------------------------------------------------------------------
local pending
local function openWhenCalm(args)
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
		C.On("WISHPOST", function(sender, raid, size, lockKey, g)
			sender = stripRealm(sender)
			if sender == me() then return end
			if not canTrigger(sender) then return end
			db().on = true
			if Wi.onChange then Wi.onChange() end
			-- already sent this ID: send it again for whoever missed it, no window
			local sent = mySent(lockKey)
			if sent then
				C.Send("WISHPICK", lockKey, sent)
				return
			end
			openWhenCalm({ raid, size, false, 1, lockKey, sender, g or "0", "wish" })
		end)
		C.On("WISHOFF", function(sender)
			if not canTrigger(sender) then return end
			db().on = false
			if Wi.onChange then Wi.onChange() end
		end)
		C.On("WISHPICK", function(sender, lockKey, id)
			store(lockKey, stripRealm(sender), id)
		end)
	end
end

-- ---- Test ----------------------------------------------------------------------
-- The window as a raider sees it, sending to yourself. Your earlier wish on
-- this ID is dropped first so it can be run again.
function Wi.Test()
	local d = db()
	d.on = true
	local r = SR.Raid()
	local lockKey = SR.LockKey(r)
	if d.list[lockKey] then d.list[lockKey][me()] = nil end
	local s = Okanvil.db.softres and Okanvil.db.softres.myPicks
	if s then s["wish:" .. lockKey .. ":" .. (me() or "")] = nil end
	SR.PickWindow.Open(r.key, r.size, false, 1, lockKey, me(), "0", "wish")
	if Wi.onChange then Wi.onChange() end
end

SLASH_OKWISH1 = "/okwish"
SlashCmdList.OKWISH = function(arg)
	arg = (arg or ""):lower()
	if arg == "test" then Wi.Test()
	elseif arg == "on" or arg == "off" then
		if not canTrigger(me()) then Okanvil:Print("Only an officer, the raid leader or the master looter can do that."); return end
		Wi.SetOn(arg == "on")
	else
		Okanvil:Print("/okwish on | off | test")
	end
end
