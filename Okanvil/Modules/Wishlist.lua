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

-- On by the switch (saved), or for this session by /okwish test (not saved, so
-- a test never leaves the switch on after a reload).
function Wi.IsOn() return (db().on or Wi._test) and true or false end
-- Wishes are for the guild's 25-man raids only.
local function is25() return (SR.Raid().size or 25) == 25 end
-- Wishes count only on a council night in a 25: on, and the loot mode is Council.
function Wi.Live() return Wi.IsOn() and (Wi._test or (SR.Mode() == "council" and is25())) and true or false end

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
	-- off or locked: the wishes already in stay, no new ones
	if d.locked or not Wi.IsOn() then return end
	l[who] = { id = id, name = GetItemInfo(id) }
	Okanvil:Trace("WISH", who .. " wishes " .. tostring(l[who].name or id))
	if Wi.onChange then Wi.onChange() end
end

-- The item this raider wished for on this raid's lockout, or nil.
function Wi.Of(who)
	if not Wi.Live() then return nil end
	local l = db().list[SR.LockKey()]
	local w = l and l[stripRealm(who)]
	return w and w.id or nil, w and w.name
end

-- Every wish on this raid's lockout, sorted by player: { { who, id, name }, ... }.
function Wi.All()
	local out = {}
	local l = db().list[SR.LockKey()]
	for who, w in pairs(l or {}) do
		if who ~= "_at" and type(w) == "table" then
			out[#out + 1] = { who = who, id = w.id, name = w.name or GetItemInfo(w.id) }
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

-- ---- Officer: on / off --------------------------------------------------------
function Wi.SetOn(on)
	if on and not is25() then
		Okanvil:Print("|cffff5555Wishlist not turned on:|r wishes are for 25-man raids only, and this raid is "
			.. SR.RaidLabel() .. ". Set the raid difficulty to 25.")
		return
	end
	local d = db()
	d.on = on and true or false
	d.locked = nil
	if not on then Wi._test = nil end
	local C = Okanvil.Comms
	if d.on then
		local r = SR.Raid()
		local lockKey = SR.LockKey(r)
		d.gen = d.gen or {}
		d.gen[lockKey] = d.gen[lockKey] or 0
		prune()
		if C and C.Send then C.Send("WISHPOST", r.key, r.size, lockKey, d.gen[lockKey]) end
		Okanvil:Print("Wishlist on: everyone in the group with Okanvil gets the wish window.")
		announce(("WISHLIST open: pick 1 item for this raid ID in Okanvil, or whisper %s: wh [item]. "
			.. "It tells the council what you want, it is not a reserve."):format(me() or "me"))
		-- whoever turned it on raids too: they get the window like everyone else
		if not mySent(lockKey) then
			openWhenCalm({ r.key, r.size, false, 1, lockKey, me(), tostring(d.gen[lockKey]), "wish" })
		end
	else
		if C and C.Send then C.Send("WISHOFF") end
		if SR.PickWindow and SR.PickWindow.HideKind then SR.PickWindow.HideKind("wish") end
		Okanvil:Print("Wishlist off.")
	end
	if Wi.onChange then Wi.onChange() end
end

-- Clear every wish on this raid ID, everywhere: the officers' lists and each
-- raider's own sent wish, so the window opens again and everyone picks anew.
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
	local lockKey = SR.LockKey()
	wipeLocal()
	local C = Okanvil.Comms
	if C and C.Send then C.Send("WISHCLEAR", lockKey) end
	Okanvil:Print("Wishes cleared for this raid ID.")
	-- still on: everyone gets the window again
	if Wi.Live() then Wi.SetOn(true) end
end

-- Lock: the wishes already sent stay on the board, nobody can add one. Every
-- raider's window closes; turning it on again, or Clear, opens it up again.
-- A lock only means something while the wishlist is on.
function Wi.IsLocked() return (Wi.IsOn() and db().locked) and true or false end
function Wi.Accepting() return Wi.Live() and not db().locked end
local function applyLock(locked)
	db().locked = locked or nil
	if locked and SR.PickWindow and SR.PickWindow.HideKind then SR.PickWindow.HideKind("wish") end
	if Wi.onChange then Wi.onChange() end
end
function Wi.SetLocked(locked)
	applyLock(locked)
	local C = Okanvil.Comms
	if C and C.Send then C.Send("WISHLOCK", locked and "1" or "0") end
	announce(locked and "WISHLIST LOCKED: your wishes are saved, no new wishes for this raid ID."
		or "WISHLIST open again: pick 1 item in Okanvil, or whisper " .. (me() or "me") .. ": wh [item].")
	Okanvil:Print(locked and "Wishlist locked: no new wishes." or "Wishlist unlocked.")
end

-- ---- Raider: send -------------------------------------------------------------
function Wi.SendPick(lockKey, id)
	if not id then return end
	if not Wi.Accepting() then
		Okanvil:Print("The wishlist is closed: wish not sent.")
		return
	end
	store(lockKey, me(), id)
	local C = Okanvil.Comms
	if C and C.Send and C.Send("WISHPICK", lockKey, id) then
		Okanvil:Print("Wish sent to the council.")
	else
		Okanvil:Print("Wish saved.")
	end
end

-- The wish this character already sent on a lockout (the pick window keeps it).
mySent = function(lockKey)
	local s = Okanvil.db.softres and Okanvil.db.softres.myPicks
	local p = s and s[SR.PickKey("wish", lockKey)]
	return p and p.sentGen ~= nil and p.list and p.list[1] or nil
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
		C.On("WISHPOST", function(sender, raid, size, lockKey, g)
			sender = stripRealm(sender)
			if sender == me() then return end
			if not canTrigger(sender) then return end
			if tonumber(size) ~= 25 then return end
			db().on = true
			db().locked = nil
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
			db().locked = nil
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
			wipeLocal(lockKey)
		end)
		C.On("WISHPICK", function(sender, lockKey, id)
			store(lockKey, stripRealm(sender), id)
		end)
		-- a wish someone whispered to an officer, passed on for them
		C.On("WISHFOR", function(sender, lockKey, id, who)
			if not canTrigger(sender) or not who or who == "" then return end
			who = stripRealm(who)
			store(lockKey, who, id)
			-- our own whisper: it is our wish too, not only a line on the officers' list
			if who == me() and tonumber(id) and SR.PickWindow and SR.PickWindow.MarkSent then
				SR.PickWindow.MarkSent("wish", lockKey, tonumber(id))
			end
		end)
	end
end

-- ---- Whispers: "wh [item]" for raiders without Okanvil ----------------------------
-- Whoever turned the wishlist on (any officer, the raid leader, the master
-- looter) answers "wh [item]" / "wish [item]": the wish is saved, passed to the
-- other officers, and confirmed by whisper. One per raid ID, like the window.
local function reply(to, text) SendChatMessage(text, "WHISPER", nil, to) end

local function onWhisper(text, sender)
	if not (Wi.Live() and canTrigger(me())) then return end
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
	local lockKey = SR.LockKey()
	local l = db().list[lockKey]
	local had = l and l[who]
	if had then
		local _, hl = GetItemInfo(had.id)
		reply(sender, "Wish: you already have one for this raid ID: " .. (hl or had.name or "?"))
		return
	end
	if db().locked then
		reply(sender, "Wish: the wishlist is closed for this raid ID.")
		return
	end
	store(lockKey, who, id)
	local C = Okanvil.Comms
	if C and C.Send then C.Send("WISHFOR", lockKey, id, who) end
	local _, link = GetItemInfo(id)
	reply(sender, "Wish saved: " .. (link or ("item " .. id)) .. " -- the council sees it, it is not a reserve.")
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
local WP_W, WP_PAD, WP_ICON, WP_GAP, WP_HDR = 290, 8, 20, 6, 26
local WP_MIN, WP_MAX = 110, 560

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

	local hdr = W.Frame(f, "bare")
	hdr._okTitleBar = true   -- its buttons are drawn like the X: the red plate
	hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1); hdr:SetHeight(WP_HDR)
	W.Hairline(hdr, "BOTTOM", 8)
	local title = W.Text(hdr, "Wishes", "body", "accent")
	title:SetPoint("LEFT", WP_PAD, 0); title:Color(1, 0.82, 0)
	local close = W.Button(hdr, "X"); close:SetSize(22, 20); close:SetPoint("RIGHT", -3, 0)
	close:SetScript("OnClick", function() WP.Hide(true) end)
	local clr = W.Button(hdr, "Clear"); clr:SetSize(44, 20); clr:SetPoint("RIGHT", close, "LEFT", -4, 0)
	clr:Tooltip("Clear every wish on this raid ID.\nEveryone gets the window again.")
	clr:SetScript("OnClick", function()
		Okanvil:Confirm("Clear every wish on this raid ID?\n|cff8a8d93Everyone picks again.|r", "Clear", Wi.Clear)
	end)
	f.count = W.Text(hdr, "", "note", "dim")
	f.count:SetPoint("RIGHT", clr, "LEFT", -8, 0)

	-- flat scroll, like the SR panel
	local sf = CreateFrame("ScrollFrame", nil, f)
	sf:SetPoint("TOPLEFT", WP_PAD, -(WP_HDR + 6)); sf:SetPoint("BOTTOMRIGHT", -WP_PAD - 6, WP_PAD)
	local child = CreateFrame("Frame", nil, sf)
	child:SetWidth(WP_W - WP_PAD * 2 - 6); child:SetHeight(1)
	sf:SetScrollChild(child)
	if Okanvil.Clip then Okanvil.Clip(sf) end
	local sb = CreateFrame("Slider", nil, f)
	sb:SetPoint("TOPRIGHT", -4, -(WP_HDR + 6)); sb:SetPoint("BOTTOMRIGHT", -4, WP_PAD); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1); sb:SetMinMaxValues(0, 0); sb:SetValue(0)
	local th = sb:CreateTexture(nil, "OVERLAY")
	th:SetTexture("Interface\\Buttons\\WHITE8x8")
	local ac = Okanvil.Colors and Okanvil.Colors.accent or { 0.75, 0.58, 0.23 }
	th:SetVertexColor(ac[1], ac[2], ac[3]); th:SetSize(4, 30)
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, dz) sb:SetValue(sb:GetValue() - dz * 30) end)
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
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(WP_ICON, WP_ICON); r.icon:SetPoint("TOPLEFT", 0, -3)
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	r.status = W.Text(r, "", "note")
	r.status:SetPoint("TOPRIGHT", -4, -3); r.status:SetJustifyH("RIGHT")
	r.name = W.Text(r, "", 11)
	r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", WP_GAP, 0)
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
	local byItem, items = {}, {}
	for _, w in ipairs(Wi.All()) do
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
	y = y + 8

	if #items == 0 then
		f.empty = f.empty or W.Text(f.child, "Nobody has sent a wish yet.", "note", "dim")
		f.empty:SetPoint("TOPLEFT", 0, -4); f.empty:SetWidth(width); f.empty:SetJustifyH("LEFT")
		f.empty:Show()
		y = 40
	elseif f.empty then
		f.empty:Hide()
	end

	local ni = #items
	f.count:SetText(("%d item%s, %d raider%s"):format(ni, ni == 1 and "" or "s", people, people == 1 and "" or "s"))

	f.child:SetHeight(math.max(1, y))
	local h = math.min(WP_MAX, math.max(WP_MIN, WP_HDR + 6 + y + WP_PAD))
	f:SetHeight(h)
	local view = h - (WP_HDR + 6) - WP_PAD
	local maxScroll = math.max(0, y - view)
	f.sb:SetMinMaxValues(0, maxScroll)
	if f.sb:GetValue() > maxScroll then f.sb:SetValue(maxScroll) end
	if maxScroll > 0 then f.sb:Show() else f.sb:Hide(); f.sf:SetVerticalScroll(0) end
end

-- Whether the WH button and panel belong on screen: council night, wishlist on,
-- and you are one who may run it.
function WP.Allowed()
	local rm = rollWin()
	return SR.Mode() == "council" and Wi.IsOn() and canTrigger(me()) and rm and rm:IsShown() and true or false
end

function WP.Show()
	db().panel = true
	local rm = rollWin()
	-- follows the mini roll: hidden with it, back with it
	if rm and not rm._wishHooked then
		rm._wishHooked = true
		rm:HookScript("OnHide", function() WP.Hide(false) end)
		rm:HookScript("OnShow", function() WP.Sync() end)
	end
	if not WP.Allowed() then return end
	wbuild(); wdock(); wpanel:Show(); WP.Paint()
end

function WP.Hide(forget)
	if forget then db().panel = nil end
	if wpanel then wpanel:Hide() end
end

function WP.Toggle()
	if wpanel and wpanel:IsShown() then WP.Hide(true) else WP.Show() end
end

function WP.Sync()
	if db().panel and WP.Allowed() then WP.Show() else WP.Hide(false) end
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

SLASH_OKWISH1 = "/okwish"
-- officer commands: arg -> what it does
local OFFICER_CMD = {
	clear = Wi.Clear, reset = Wi.Clear,
	on = function() Wi.SetOn(true) end, off = function() Wi.SetOn(false) end,
	lock = function() Wi.SetLocked(true) end, unlock = function() Wi.SetLocked(false) end,
}
SlashCmdList.OKWISH = function(arg)
	arg = (arg or ""):lower()
	if arg == "test" then Wi.Test(); return end
	local fn = OFFICER_CMD[arg]
	if not fn then Okanvil:Print("/okwish on | off | lock | unlock | clear | test"); return end
	if not canTrigger(me()) then Okanvil:Print("Only an officer, the raid leader or the master looter can do that."); return end
	fn()
end
