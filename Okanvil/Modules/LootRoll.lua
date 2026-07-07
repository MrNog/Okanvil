-- ============================================================
-- Okanvil -- Mini Roll Manager (native module).
-- A small floating loot-master window (RaidRoll-style): pops when eligible loot
-- drops, lists the items, lets you START a roll (MS / OS / Free -> announced in
-- raid/RW), shows the live rolls (main-spec beats off-spec, highest wins), and
-- AWARDS the winner (marks the drop owner + whispers them). Also shows the
-- fragment/BoE collector counters. Uses the Loot module's data + API; adds NO
-- new capture -- purely a control surface, so you don't open the big window.
-- ============================================================

local Okanvil = Okanvil
local W = Okanvil.W
local L = Okanvil.Loot
local RM = {}
Okanvil.RollMgr = RM

-- roomier than before: bigger rows, bigger text (user asked for more spacing).
local ROW_H = 26
local FONT_SZ = 13
local ITEM_ROWS, ROLL_ROWS = 5, 6
local WIN_W = 340   -- wider: long item names + player names fit

local function db()
	Okanvil.db.rollmgr = Okanvil.db.rollmgr or { point = "RIGHT", x = -30, y = 60, autoShow = true }
	return Okanvil.db.rollmgr
end

-- Icon resolver: delegates to the shared Core warmer (Okanvil:ItemIcon), which
-- returns the icon now or nil + auto-queues a server query so a later tick fills
-- it in. Fixes the "?" icons on a fresh client without any manual hovering.
local function itemIcon(itemLink)
	return itemLink and Okanvil:ItemIcon(itemLink) or nil
end

-- are we the loot master right now? (drives ML-vs-raider layout)
local function amML()
	return (GetLootMethod and GetLootMethod()) == "master"
end

-- class-ish color for an item by rarity (falls back to white)
local function rarityColor(r)
	local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r or 1]
	if q then return q.r, q.g, q.b end
	return 0.9, 0.9, 0.9
end

-- class color of a player by NAME -> "|cffRRGGBB". Finds their class from the
-- party/raid, else the guild roster, else a learned cache. Falls back to gold if
-- unknown -- but once we EVER see the player grouped, we remember their class, so
-- the color shows up even later (like RaidRoll knowing you're a mage).
local classCache = {}   -- [lowername] = "MAGE" etc.
local function classColorCode(name)
	if not name or name == "" then return "|cffffd200" end
	local short = name:gsub("%-.*$", "")
	local low = short:lower()
	local class
	-- party/raid units
	local function scan(prefix, n)
		for i = 1, n do
			local u = prefix .. i
			if UnitExists(u) and UnitName(u) == short then class = select(2, UnitClass(u)); return true end
		end
	end
	if UnitName("player") == short then class = select(2, UnitClass("player"))
	elseif GetNumRaidMembers and GetNumRaidMembers() > 0 then scan("raid", GetNumRaidMembers())
	elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then scan("party", GetNumPartyMembers()) end
	-- guild roster fallback
	if not class and IsInGuild and IsInGuild() and GetNumGuildMembers then
		for i = 1, GetNumGuildMembers() do
			local gn, _, _, _, _, _, _, _, _, _, gc = GetGuildRosterInfo(i)
			if gn and gn:gsub("%-.*$", "") == short then class = gc; break end
		end
	end
	if class then classCache[low] = class          -- learn it for next time
	else class = classCache[low] end               -- ... or reuse what we learned
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
	return "|cffffd200"   -- unknown class -> gold (shows up once they're grouped/guilded)
end

-- ------------------------------------------------------------
-- window
-- ------------------------------------------------------------
local win
local selected            -- the drop table currently picked for a roll
local function isML() return amML() end

local function buildWindow()
	if win then return win end
	local f = CreateFrame("Frame", "Okanvil_RollMgr", UIParent)
	f:SetSize(WIN_W, 200)   -- height set dynamically in Refresh
	local d = db()
	f:SetPoint(d.point or "RIGHT", UIParent, d.point or "RIGHT", d.x or -30, d.y or 60)
	f:SetFrameStrata("HIGH"); f:SetToplevel(true)
	Okanvil:Skin(f, "panel")
	local br, bg, bb = f:GetBackdropColor()
	if br then f:SetBackdropColor(br, bg, bb, 0.97) end
	f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(s)
		s:StopMovingOrSizing()
		local p, _, _, x, y = s:GetPoint(1)
		d.point, d.x, d.y = p, x, y
	end)
	f:SetClampedToScreen(true)

	-- header
	local hdr = W.Frame(f, "raise")
	hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1); hdr:SetHeight(26)
	local ico = hdr:CreateTexture(nil, "OVERLAY")
	ico:SetSize(16, 16); ico:SetPoint("LEFT", 8, 0)
	ico:SetTexture("Interface\\Icons\\Trade_BlackSmithing")   -- anvil, like the shell
	ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local title = W.Text(hdr, "Okanvil - Mini Roll Manager", 13, "accent"); title:SetPoint("LEFT", ico, "RIGHT", 6, 0); title:Color(1, 0.82, 0)
	local close = W.Button(hdr, "X"); close:SetSize(22, 20); close:SetPoint("RIGHT", -3, 0)
	close:SetScript("OnClick", function() f:Hide() end)

	-- status line (ML / Raider, from the real loot method)
	local status = W.Text(f, "", 12, "dim"); status:SetPoint("TOPLEFT", 12, -34)
	f.status = status

	-- everything below the status is rebuilt when the ML state changes, so pack the
	-- mode-specific widgets into a container we can wipe. Give it a FULL size
	-- (TOPLEFT + BOTTOMRIGHT) -- a frame with height 0 doesn't render its children
	-- reliably on 3.3.5a, which is why the body looked empty.
	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", 0, -52); body:SetPoint("BOTTOMRIGHT", 0, 0)
	f.body = body

	-- "Roll open" animation: while a roll-off is open, cycle dots + a pulsing gold
	-- so the window feels alive. NO countdown: a roll never auto-closes here (the
	-- item is often handed out by master loot outside the addon), so a shrinking
	-- "110s" timer just got stuck at "Rolling.." forever after the item was given.
	-- We show which item is up for roll, no timer.
	f._anim = 0
	f:SetScript("OnUpdate", function(self, e)
		if not self:IsShown() then return end
		-- Fill in any "?" icons once the client has cached the item (fresh client:
		-- GetItemInfo is nil at first). Throttled to ~2x/sec so it's cheap.
		self._iconAcc = (self._iconAcc or 0) + e
		if self._iconAcc >= 0.5 and self.itemRows then
			self._iconAcc = 0
			for _, r in ipairs(self.itemRows) do
				if r:IsShown() and r._d and r._d.item then
					local tex = itemIcon(r._d.item)
					if tex then r.icon:SetTexture(tex) end
				end
			end
		end
		-- Shrinking roll-timer bars on the item rows (ElvUI M:statusbarOnUpdate style):
		-- read GetLootRollTimeLeft(rollID) each frame and scale the row-width bar.
		if self.itemRows then
			self._dots = (self._dots or 0) + e
			local dots = ("."):rep(1 + (math.floor(self._dots * 2) % 3))   -- . / .. / ...
			for _, r in ipairs(self.itemRows) do
				local d = r._d
				if r:IsShown() and r._rolling and d then
					-- shrinking bar
					local frac
					if d.rollID then
						local left = GetLootRollTimeLeft and GetLootRollTimeLeft(d.rollID) or 0
						local dur = (d.rollDur and d.rollDur > 0) and (d.rollDur * 1000) or 60000
						frac = left / dur
					elseif d.rollStart and d.rollDur then
						frac = 1 - ((GetTime() - d.rollStart) / d.rollDur)
					end
					if frac then
						if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
						if frac <= 0 then r.bar:Hide()
						else r.bar:SetWidth(math.max(1, r:GetWidth() * frac)) end
					end
					-- animated "- rolling ..." suffix on the row text
					if r._baseTxt then
						r.txt:SetText(r._baseTxt .. "  |cffffd200- rolling " .. dots .. "|r")
					end
				end
			end
		end
		-- "Roll open" pulsing label (only when a managed roll-off is active)
		local ar = L and L.ActiveRoll and L.ActiveRoll()
		if not (ar and self.rollState) then return end
		self._anim = self._anim + e
		local dots = ("."):rep(1 + (math.floor(self._anim * 2) % 3))   -- . / .. / ...
		local pulse = 0.7 + 0.3 * math.abs(math.sin(self._anim * 3))
		local g = string.format("|cff%02xd200", math.floor(0xff * pulse))
		local m = (ar.mode == "ms" and "MS") or (ar.mode == "os" and "OS") or "FREE"
		local nm = (ar.name ~= "" and ar.name) or "item"
		self.rollState:SetText(g .. "Roll open" .. dots .. "|r " .. nm .. "  |cff8a8d93[" .. m .. "]|r")
	end)

	win = f
	f:Hide()
	return f
end

-- (re)build the mode-specific body: full manager for ML, just roll buttons for a
-- raider. Called on show and whenever the ML mode changes.
function RM.Rebuild()
	if not win then return end
	local f = win
	-- clear old body widgets. NOTE: fontstrings/textures CANNOT take a nil parent
	-- on 3.3.5a (that's the LootRoll.lua:112 error) -- only real Frames can be
	-- reparented to the hidden trash. FontStrings just get hidden + cleared.
	f.trash = f.trash or CreateFrame("Frame"); f.trash:Hide()
	if f.bodyKids then
		for _, w in ipairs(f.bodyKids) do
			w:Hide()
			if w.GetObjectType and w:GetObjectType() == "FontString" then
				if w.SetText then w:SetText("") end
			elseif w.SetParent then
				w:SetParent(f.trash)
			end
		end
	end
	f.bodyKids = {}
	f.itemRows, f.rollRows = {}, {}
	local body = f.body
	local function keep(w) f.bodyKids[#f.bodyKids + 1] = w; return w end

	local ml = isML()
	local ac = Okanvil.Colors and Okanvil.Colors.accent or { 0.75, 0.58, 0.23 }

	-- UNIFIED layout: raider and ML share the same look (boss pager, item box,
	-- rolls box, "Your roll"). The ML additionally gets the management controls
	-- (Start roll MS/OS/Free/Stop + Award/Clear). Raider just watches + rolls.
	local M = 12
	local INNER = WIN_W - M * 2
	local y = -6

	-- boss pager header:  <  Boss Name (1/3)  >
	local prev = keep(W.Button(body, "<")); prev:SetSize(24, 22); prev:SetPoint("TOPLEFT", M, y)
	prev:SetScript("OnClick", function()
		f.bossIdx = math.max(1, (f.bossIdx or 1) - 1); selected = nil; RM.Refresh()
	end)
	local bossHd = keep(W.Text(body, "", 13, "accent")); bossHd:Color(1, 0.82, 0)
	bossHd:SetPoint("LEFT", prev, "RIGHT", 6, 0); bossHd:SetPoint("RIGHT", -M - 28, 0); bossHd:SetJustifyH("CENTER")
	if bossHd.SetWordWrap then bossHd:SetWordWrap(false) end
	f.bossHd = bossHd
	local nxt = keep(W.Button(body, ">")); nxt:SetSize(24, 22); nxt:SetPoint("TOPRIGHT", -M, y)
	nxt:SetScript("OnClick", function()
		f.bossIdx = math.min(f.bossCount or 1, (f.bossIdx or 1) + 1); selected = nil; RM.Refresh()
	end)
	y = y - 28

	-- item box (this boss's items) -------------------------------------------
	local LIST_H = ITEM_ROWS * ROW_H
	local ibox = keep(W.Frame(body, "dark")); ibox:SetPoint("TOPLEFT", M, y); ibox:SetSize(INNER, LIST_H + 6)
	f.ibox = ibox
	-- mouse wheel pages the item list (raids drop more than ITEM_ROWS items)
	ibox:EnableMouseWheel(true)
	ibox:SetScript("OnMouseWheel", function(_, delta)
		f.itemScroll = (f.itemScroll or 0) - delta   -- wheel up = earlier items
		RM.Refresh()
	end)
	f.makeItemRow = function(i)
		local r = f.itemRows[i]
		if r then return r end
		r = CreateFrame("Button", nil, ibox)
		-- roll timer bar: the WHOLE ROW is the bar. It fills the row from the left and
		-- shrinks as the Blizzard need/greed timer runs down (a reversed cast bar), so
		-- you can watch the time left to choose. Sits at BACKGROUND, behind text/icon.
		r.bar = r:CreateTexture(nil, "BACKGROUND")
		r.bar:SetPoint("TOPLEFT", 0, 0); r.bar:SetPoint("BOTTOMLEFT", 0, 0)
		r.bar:SetTexture(0.75, 0.58, 0.23, 0.30)   -- gold, translucent
		r.bar:Hide()
		r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", 5, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.txt = W.Text(r, "", FONT_SZ); r.txt:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.txt:SetPoint("RIGHT", -6, 0); r.txt:SetJustifyH("LEFT")
		if r.txt.SetWordWrap then r.txt:SetWordWrap(false) end
		r.hl = r:CreateTexture(nil, "BORDER"); r.hl:SetAllPoints(); r.hl:SetTexture(0.75, 0.58, 0.23, 0.22); r.hl:Hide()
		r:SetScript("OnEnter", function(s)
			if s._d and s._d.item then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(s._d.item); GameTooltip:Show() end
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		-- only the ML picks an item to run a roll on; raiders can hover but not select
		r:SetScript("OnClick", function(s) if ml and s._d then selected = s._d; RM.Refresh() end end)
		f.itemRows[i] = r
		return r
	end
	y = y - (LIST_H + 6) - 10

	-- ML-only: Start Roll row (4 equal buttons) ------------------------------
	if ml then
		local sr = keep(W.Text(body, "Start roll (announces)", 11, "dim")); sr:SetPoint("TOPLEFT", M, y); y = y - 16
		local gap, bw = 6, (INNER - 3 * 6) / 4
		local function srBtn(label, kind, idx, fn)
			local b = keep(W.Button(body, label, kind)); b:SetSize(bw, 26)
			b:SetPoint("TOPLEFT", M + (idx - 1) * (bw + gap), y)
			b:SetScript("OnClick", fn); return b
		end
		local function startSel(mode)
			if not (selected and selected.item) then Okanvil:Print("Pick an item first."); return end
			L.StartRoll(selected.item, mode)
		end
		srBtn("MS", "primary", 1, function() startSel("ms") end)
		srBtn("OS", nil, 2, function() startSel("os") end)
		srBtn("Free", nil, 3, function() startSel("free") end)
		srBtn("Stop", "danger", 4, function() L.StopRoll() end)
		y = y - 32
	end

	-- rolls: state line + list (both modes see the rolls) --------------------
	local rs = keep(W.Text(body, "", 11, "dim")); rs:SetPoint("TOPLEFT", M, y); f.rollState = rs; y = y - 16
	local rl = keep(W.Text(body, ml and "Rolls -- click to pick winner" or "Rolls", 10, "dim")); rl:SetPoint("TOPLEFT", M, y); y = y - 16
	local rbox = keep(W.Frame(body, "dark")); rbox:SetPoint("TOPLEFT", M, y); rbox:SetSize(INNER, ROLL_ROWS * ROW_H + 4)
	for i = 1, ROLL_ROWS do
		local r = CreateFrame("Button", nil, rbox)
		r:SetSize(INNER - 8, ROW_H); r:SetPoint("TOPLEFT", 4, -2 - (i - 1) * ROW_H)
		r.txt = W.Text(r, "", FONT_SZ); r.txt:SetPoint("LEFT", 4, 0); r.txt:SetPoint("RIGHT", -4, 0); r.txt:SetJustifyH("LEFT")
		r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(); r.hl:SetTexture(0.49, 0.99, 0.54, 0.16); r.hl:Hide()
		-- only ML can award by clicking a roll
		r:SetScript("OnClick", function(s)
			if ml and s._roll and selected then L.AwardWinner(selected.id, s._roll.player, s._roll.roll, s._roll.spec) end
		end)
		f.rollRows[i] = r
	end
	y = y - (ROLL_ROWS * ROW_H + 4) - 10

	-- ML-only: award / clear -------------------------------------------------
	if ml then
		local award = keep(W.Button(body, "Award top roll", "primary")); award:SetSize(INNER - 90, 26); award:SetPoint("TOPLEFT", M, y)
		award:SetScript("OnClick", function()
			local ar = L.ActiveRoll()
			if ar and ar.best and selected then L.AwardWinner(selected.id, ar.best.player, ar.best.roll, ar.best.spec)
			else Okanvil:Print("No rolls yet.") end
		end)
		local clear = keep(W.Button(body, "Clear")); clear:SetSize(82, 26); clear:SetPoint("LEFT", award, "RIGHT", 8, 0)
		clear:SetScript("OnClick", function() selected = nil; L.StopRoll(); RM.Refresh() end)
		y = y - 36

		-- Clear the whole session's loot list (fresh run). Confirms first.
		local wipeBtn = keep(W.Button(body, "Clear session loot", "danger")); wipeBtn:SetSize(INNER, 22); wipeBtn:SetPoint("TOPLEFT", M, y)
		wipeBtn:SetScript("OnClick", function()
			if not StaticPopupDialogs["OKANVIL_ROLL_CLEAR"] then
				StaticPopupDialogs["OKANVIL_ROLL_CLEAR"] = {
					text = "Clear ALL loot from this session's list?\n(Any roll in progress is cancelled.)",
					button1 = YES, button2 = NO,
					OnAccept = function()
						if L.ClearActiveDrops and L.ClearActiveDrops() then
							selected = nil
							Okanvil:Print("Cleared this session's loot.")
						end
						RM.Refresh()
					end,
					timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
				}
			end
			StaticPopup_Show("OKANVIL_ROLL_CLEAR")
		end)
		y = y - 28
	end

	-- Your roll (both modes) -------------------------------------------------
	local yrl = keep(W.Text(body, "Your roll", 11, "dim")); yrl:SetPoint("TOPLEFT", M, y); y = y - 18
	local hw = (INNER - 8) / 2
	local myms = keep(W.Button(body, "Roll MS (100)", "primary")); myms:SetSize(hw, 28); myms:SetPoint("TOPLEFT", M, y)
	myms:SetScript("OnClick", function() L.SelfRoll("ms") end)
	local myos = keep(W.Button(body, "Roll OS (99)")); myos:SetSize(hw, 28); myos:SetPoint("LEFT", myms, "RIGHT", 8, 0)
	myos:SetScript("OnClick", function() L.SelfRoll("os") end)
	y = y - 32
	-- (fragment/BoE collector tally is NOT shown here -- it lives on the Loot page's
	--  COLLECTED panel. The mini manager stays focused on rolling.)
	f.colInfo = nil

	f:SetHeight(52 + (-y) + 8)

	RM.Refresh()
end

-- ------------------------------------------------------------
-- refresh -- paint items, rolls, status from the Loot module's live data
-- ------------------------------------------------------------
function RM.Refresh()
	if not win or not win:IsShown() then return end
	local f = win
	local ml = isML()
	f.status:SetText(ml and "|cff7cfc8aLoot Master|r" or "|cff8a8d93Raider|r")

	local ar = L.ActiveRoll()

	-- per-boss pager: pick the current boss group and list its items (both modes)
	local groups = L.DropsByBoss and L.DropsByBoss() or {}
	f.bossCount = #groups
	if f.bossCount == 0 then
		if f.bossHd then f.bossHd:SetText("|cff8a8d93No loot yet|r") end
		for _, r in ipairs(f.itemRows) do r:Hide() end
	else
		-- auto-jump to the newest boss when fresh loot just arrived (a new kill).
		-- DropsByBoss() lists bosses in arrival order, so newest = last.
		if f._jumpNewest then f.bossIdx = f.bossCount; f._jumpNewest = nil end
		f.bossIdx = math.max(1, math.min(f.bossIdx or 1, f.bossCount))
		local g = groups[f.bossIdx]
		if f.bossHd then f.bossHd:SetText(g.boss .. "  |cff8a8d93(" .. f.bossIdx .. "/" .. f.bossCount .. ")|r") end
		-- SCROLL: a raid boss drops more than ITEM_ROWS items, so page the list with
		-- the mouse wheel instead of the old "...and N more" dead-end. Clamp the
		-- offset so we never scroll past the last full page.
		local nItems = #g.items
		local maxOff = math.max(0, nItems - ITEM_ROWS)
		f.itemScroll = math.max(0, math.min(f.itemScroll or 0, maxOff))
		local off = f.itemScroll
		for _, r in ipairs(f.itemRows) do r._d = nil; r:Hide() end
		for i = 1, ITEM_ROWS do
			local d = g.items[i + off]
			local r = f.makeItemRow(i)
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -2 - (i - 1) * ROW_H); r:SetPoint("RIGHT", f.ibox, "RIGHT", -4, 0); r:SetHeight(ROW_H)
			if d then
				r._d = d
				r.icon:Show(); r.icon:SetTexture(itemIcon(d.item) or "Interface\\Icons\\INV_Misc_QuestionMark")
				-- item name in RARITY color; receiver in CLASS color; both inline so
				-- one string can carry two colors. Long names get truncated with ...
				r.txt:SetTextColor(1, 1, 1)   -- base; inline codes do the coloring
				local cr, cg, cb = rarityColor(d.rarity)
				local rcode = string.format("|cff%02x%02x%02x", cr * 255, cg * 255, cb * 255)
				local nm = d.name ~= "" and d.name or "?"
				if #nm > 24 then nm = nm:sub(1, 23) .. "..." end
				local who = ""
				if d.receivedBy and d.receivedBy ~= "" then
					who = "  |cff8a8d93->|r " .. classColorCode(d.receivedBy) .. d.receivedBy .. "|r"
				end
				-- little up/down hint on the edge rows when there's more above/below
				local more = ""
				if i == 1 and off > 0 then more = "  |cff5e6166[+]|r"
				elseif i == ITEM_ROWS and (off + ITEM_ROWS) < nItems then more = "  |cff5e6166[v]|r" end
				local baseTxt = rcode .. nm .. "|r" .. who .. more
				r.hl:SetShown(selected == d)
				-- roll timer bar (ElvUI-style): show while a roll is live for this item
				-- and not yet won. Live = a native need/greed roll (d.rollID) OR the
				-- time-based fallback (d.rollStart). Master loot has neither, so no bar.
				-- The row's OnUpdate shrinks it each frame + animates "rolling".
				if (d.rollID or d.rollStart) and not d.receivedBy then
					r.bar:Show()
					r.bar:SetWidth(r:GetWidth())   -- start full; OnUpdate shrinks it
					r.bar:SetTexture(cr * 0.6, cg * 0.6, cb * 0.6, 0.30)  -- tinted by rarity
					r._rolling = true
					r._baseTxt = baseTxt           -- OnUpdate appends " - rolling ..."
				else
					r.bar:Hide()
					r._rolling = false
				end
				r.txt:SetText(baseTxt)
				r:Show()
			else
				r._d = nil; r:Hide()
			end
		end
	end

	-- roll state line
	if f.rollState then
		if ar then
			-- animated "Rolling..." is painted by the window's OnUpdate; just seed it
			f.rollState:SetText("|cffffd200Rolling...|r")
		elseif selected then
			f.rollState:SetText("|cff8a8d93Selected: " .. (selected.name ~= "" and selected.name or "item") .. "|r")
		else
			f.rollState:SetText("|cff5e6166Pick an item, then MS/OS/Free.|r")
		end
	end

	-- rolls (main first, then roll desc)
	local list = (ar and ar.list) or {}
	local sorted = {}
	for _, e in ipairs(list) do sorted[#sorted + 1] = e end
	table.sort(sorted, function(a, b)
		if a.spec ~= b.spec then return a.spec == "main" end
		return a.roll > b.roll
	end)
	local best = ar and ar.best
	for i = 1, ROLL_ROWS do
		local r, e = f.rollRows[i], sorted[i]
		if e then
			r._roll = e
			local tag = e.spec == "off" and " |cff8a5ad9(off)|r" or ""
			local isBest = best and best.player == e.player and best.roll == e.roll
			local mark = isBest and "|cff7cfc8a> |r" or "  "
			-- player name in CLASS color, roll value in gold
			r.txt:SetText(mark .. classColorCode(e.player) .. e.player .. "|r  |cffffd200" .. e.roll .. "|r" .. tag)
			r.hl:SetShown(isBest)
			r:Show()
		else
			r._roll = nil; r:Hide()
		end
	end

	-- (collector tally intentionally not shown here -- it's on the Loot page)
end

-- show the window (building + rebuilding the mode-specific body)
local function showWin()
	buildWindow()
	win:Show()                       -- always show (idempotent)
	win:Raise()                      -- bring to front in case something covers it
	local ok, err = pcall(RM.Rebuild)  -- never let a rebuild error leave it half-open
	if not ok then Okanvil:Print("|cffff5555Roll rebuild error:|r " .. tostring(err)) end
end

-- Only auto-pop when boss loot drops in the CURRENT run while we're inside the
-- instance. The old code popped on any loot/chat event, which resurrected a stale
-- session (a dungeon left hours ago) the moment you joined a new raid. Now: if
-- we're not in a live run, never show it on our own -- just refresh if it's
-- already open. New loot may mean a newer boss -> jump the pager to it.
local function canAutoShow()
	return db().autoShow and Okanvil.Loot and Okanvil.Loot.InLiveRun and Okanvil.Loot.InLiveRun()
end
local function onLoot()
	if win then win._jumpNewest = true end
	if win and win:IsShown() then RM.Refresh()
	elseif canAutoShow() then showWin()
	else RM.Refresh() end
end

-- also pop for a raider when a roll opens (so they see the Roll MS/OS buttons) --
-- but only for a roll that's genuinely live now, and only inside a live run.
function RM.OnRollOpen()
	if win then win._jumpNewest = true end
	if win and win:IsShown() then RM.Refresh()
	elseif canAutoShow() then showWin()
	else RM.Refresh() end
end

function RM.Toggle()
	local ok, err = pcall(function()
		if win and win:IsShown() then
			win:Hide()
		else
			showWin()
		end
	end)
	if not ok then
		Okanvil:Print("|cffff5555Roll manager error:|r " .. tostring(err))
		-- recover: force a clean show so a transient error can't wedge it closed
		if win then pcall(function() win:Show(); RM.Rebuild() end) end
	end
end

-- ------------------------------------------------------------
-- boot: hook the Loot module's callbacks + register a slash
-- ------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
	if not Okanvil.Loot then return end
	L = Okanvil.Loot
	-- chain onto Loot's callbacks without clobbering them
	local prevLoot = L.onLoot
	L.onLoot = function() if prevLoot then prevLoot() end; onLoot() end
	L.onRoll = function() RM.OnRollOpen() end
end)

SLASH_OKROLL1 = "/okroll"
SlashCmdList["OKROLL"] = function() RM.Toggle() end
