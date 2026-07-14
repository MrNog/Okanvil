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

-- Two layouts, toggled by the [-]/[+] button in the header and remembered in the DB.
--   full    -- roomy rows/text, the default.
--   compact -- RaidRoll-density (its roll frame is 185x180): tighter rows, smaller
--              font, fewer visible rows, narrower window. Same sections, no features
--              removed -- it just takes about a quarter of the screen area.
-- An item row is TWO lines: the item name on top, the winner and trade timer below.
-- One line meant the name, the winner and the timer all fought for the same width, so
-- everything was truncated to "Hauberk of the Towering Mon.. -> Ud..." and the compact
-- layout was unreadable. Two lines give each its own space and let the icon grow.
local SIZES = {
	full    = { ROW_H = 32, FONT_SZ = 12, SUB_SZ = 10, ROLL_H = 18, ITEM_ROWS = 5, ROLL_ROWS = 7, WIN_W = 330 },
	compact = { ROW_H = 26, FONT_SZ = 11, SUB_SZ =  9, ROLL_H = 15, ITEM_ROWS = 4, ROLL_ROWS = 5, WIN_W = 270 },
}
-- Live geometry, re-pointed at one of the SIZES tables by applySize(). Seeded from
-- `full` at LOAD time: Okanvil.db does not exist yet here (Core.lua only assigns it
-- on VARIABLES_LOADED, after every file has run), so calling db() at this scope
-- would index a nil table. applySize() is called from showWin()/the toggle instead,
-- both of which run long after the DB is up.
local ROW_H, FONT_SZ, SUB_SZ, ROLL_H, ITEM_ROWS, ROLL_ROWS, WIN_W do
	local s = SIZES.full
	ROW_H, FONT_SZ, SUB_SZ, ROLL_H, ITEM_ROWS, ROLL_ROWS, WIN_W =
		s.ROW_H, s.FONT_SZ, s.SUB_SZ, s.ROLL_H, s.ITEM_ROWS, s.ROLL_ROWS, s.WIN_W
end

local function db()
	Okanvil.db.rollmgr = Okanvil.db.rollmgr
		or { point = "RIGHT", x = -30, y = 60, autoShow = true, compact = true }
	return Okanvil.db.rollmgr
end

-- pull the geometry for the currently-selected mode into the locals above
local function applySize()
	local s = SIZES[db().compact and "compact" or "full"]
	ROW_H, FONT_SZ, SUB_SZ, ROLL_H, ITEM_ROWS, ROLL_ROWS, WIN_W =
		s.ROW_H, s.FONT_SZ, s.SUB_SZ, s.ROLL_H, s.ITEM_ROWS, s.ROLL_ROWS, s.WIN_W
end

-- Pixels from the window top to the body frame: the 26px header + the status line.
-- ONE source of truth -- the body anchor and the final SetHeight both use it, so a
-- mode switch can never leave them disagreeing (which clipped the bottom buttons).
-- no status line (ML / Raider): the tabs already say which mode you're in, so the
-- body starts straight under the title bar.
local function BODY_TOP() return db().compact and 28 or 34 end

-- Icon resolver: delegates to the shared Core warmer (Okanvil:ItemIcon), which
-- returns the icon now or nil + auto-queues a server query so a later tick fills
-- it in. Fixes the "?" icons on a fresh client without any manual hovering.
local function itemIcon(itemLink)
	return itemLink and Okanvil:ItemIcon(itemLink) or nil
end

-- are we the loot master right now? (drives ML-vs-raider layout)
-- MUST match the Loot module's real check: master-loot method AND *we* are the ML.
-- The old test only checked the method was "master" (true for EVERYONE in the raid,
-- not just the ML), so it showed the "Loot Master" layout + Award button to plain
-- raiders who can't actually give loot -- and disagreed with the Loot page's
-- "not the Master Looter" banner. Delegate to L.IsMasterLooter so they always agree.
local function amML()
	if L and L.IsMasterLooter then return L.IsMasterLooter() end
	return false
end

-- class-ish color for an item by rarity (falls back to white)
local function rarityColor(r)
	local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r or 1]
	if q then return q.r, q.g, q.b end
	return 0.9, 0.9, 0.9
end

-- ------------------------------------------------------------
-- TRADE TIMER
-- A BoP item looted in a group can be traded to another eligible player for a
-- limited window. The SERVER owns that countdown -- it stops while you are logged
-- out, so it cannot be derived from "when did this drop". The only honest source is
-- the item's own tooltip, where the server writes the remaining time.
--
-- That means the timer can only be read for items sitting in YOUR OWN bags, which
-- is exactly the master looter's case: the drops still waiting to be handed out.
-- ------------------------------------------------------------
local tradeTip
local BIND_PAT   -- "You may trade this item ... for %s" -> a Lua pattern

local function tradePattern()
	if BIND_PAT then return BIND_PAT end
	local s = BIND_TRADE_TIME_REMAINING
	if not s or s == "" then return nil end
	-- escape magic chars, then turn the %s placeholder into a capture
	BIND_PAT = "^" .. s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", "(.+)")
	return BIND_PAT
end

-- CACHE. Reading this means walking every bag slot and scanning a tooltip, and the
-- roll manager redraws on EVERY roll -- 25 people rolling on one item redrew 25
-- times, each walk costing ~100 GetContainerItemLink calls per visible row. That is
-- thousands of scans in a second, and it is felt as a periodic stutter mid-raid.
--
-- The value only changes on the minute, so it is cached per item link and only
-- recomputed when the cache is stale or the bags actually changed.
local tradeCache = {}       -- [link] = { text = "1h 43m" | false, at = GetTime() }
local TRADE_TTL = 20        -- seconds a cached answer stays good

local function tradeTimeUncached(link)
	local pat = tradePattern()
	if not pat then return nil end

	if not tradeTip then
		tradeTip = CreateFrame("GameTooltip", "OkanvilTradeTip", nil, "GameTooltipTemplate")
		tradeTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	end

	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			if GetContainerItemLink(bag, slot) == link then
				tradeTip:ClearLines()
				tradeTip:SetBagItem(bag, slot)
				for i = 2, tradeTip:NumLines() do
					local fs = _G["OkanvilTradeTipTextLeft" .. i]
					local txt = fs and fs:GetText()
					if txt then
						local left = txt:match(pat)
						if left then return left end
					end
				end
				return nil          -- found the item, but no trade line: not tradeable
			end
		end
	end
	return nil                      -- not in our bags
end

local function tradeTimeLeft(link)
	if not link then return nil end
	local now = GetTime()
	local c = tradeCache[link]
	if c and (now - c.at) < TRADE_TTL then
		return c.text or nil        -- `false` caches a known negative
	end
	local t = tradeTimeUncached(link)
	tradeCache[link] = { text = t or false, at = now }
	return t
end

-- Bags changed -> the cached answers may be wrong (an item was given away, or a new
-- one arrived). Cheaper to drop the whole cache than to work out which entry moved.
local bagEv = CreateFrame("Frame")
bagEv:RegisterEvent("BAG_UPDATE")
bagEv:SetScript("OnEvent", function() tradeCache = {} end)

-- class color of a player by NAME -> "|cffRRGGBB". Finds their class from the
-- party/raid, else the guild roster, else a learned cache. Falls back to gold if
-- unknown -- but once we EVER see the player grouped, we remember their class, so
-- the color shows up even later (like RaidRoll knowing you're a mage).
local classCache = {}   -- [lowername] = "MAGE" etc.  (fallback local)
local function classColorCode(name)
	if not name or name == "" then return "|cffffd200" end
	local short = name:gsub("%-.*$", "")
	local low = short:lower()
	local class
	-- Primary source: the PERSISTENT cache from the Loot module (L.ClassOf), shared
	-- with the history -- so rolls and history use the SAME class color,
	-- and it persists across sessions (remembered once seen grouped/in the guild).
	if Okanvil.Loot and Okanvil.Loot.ClassOf then
		local c0 = Okanvil.Loot.ClassOf(short)
		if c0 and c0 ~= "" then class = c0 end
	end
	-- fallback: resolve here (party/raid/guild) if the cache doesn't know yet
	if not class then
		local function scan(prefix, n)
			for i = 1, n do
				local u = prefix .. i
				if UnitExists(u) and UnitName(u) == short then class = select(2, UnitClass(u)); return true end
			end
		end
		if UnitName("player") == short then class = select(2, UnitClass("player"))
		elseif GetNumRaidMembers and GetNumRaidMembers() > 0 then scan("raid", GetNumRaidMembers())
		elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then scan("party", GetNumPartyMembers()) end
		if not class and IsInGuild and IsInGuild() and GetNumGuildMembers then
			for i = 1, GetNumGuildMembers() do
				local gn, _, _, _, _, _, _, _, _, _, gc = GetGuildRosterInfo(i)
				if gn and gn:gsub("%-.*$", "") == short then class = gc; break end
			end
		end
		if class then classCache[low] = class else class = classCache[low] end
	end
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
	return "|cffffd200"   -- unknown class -> gold (shows up once they're grouped/guilded)
end

-- ------------------------------------------------------------
-- window
-- ------------------------------------------------------------
local win
local selected            -- the drop table currently picked for a roll
-- Boss page a roll asked us to jump to while the window did not exist yet. Applied
-- when it is next shown, so a roll announced before you ever opened the manager still
-- lands on the right page.
local pendingBossIdx
local pendingItemScroll   -- scroll offset that puts the selected item on screen
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
	local title = W.Text(hdr, "", 13, "accent"); title:SetPoint("LEFT", ico, "RIGHT", 6, 0); title:Color(1, 0.82, 0)
	f.title = title
	local close = W.Button(hdr, "X"); close:SetSize(22, 20); close:SetPoint("RIGHT", -3, 0)
	close:SetScript("OnClick", function() f:Hide() end)

	-- compact toggle: [-] shrinks to the tight layout, [+] restores the roomy one.
	local size = W.Button(hdr, ""); size:SetSize(22, 20); size:SetPoint("RIGHT", close, "LEFT", -2, 0)
	f.sizeBtn = size
	size:SetScript("OnClick", function()
		local d = db()
		d.compact = not d.compact
		applySize()
		RM.ApplyMode()
	end)

	-- everything below the title is rebuilt when the ML state changes, so pack the
	-- mode-specific widgets into a container we can wipe. Give it a FULL size
	-- (TOPLEFT + BOTTOMRIGHT) -- a frame with height 0 doesn't render its children
	-- reliably on 3.3.5a, which is why the body looked empty.
	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", 0, -BODY_TOP()); body:SetPoint("BOTTOMRIGHT", 0, 0)
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
		-- Trade timers tick down in whole minutes, so a redraw every 20s is plenty and
		-- keeps the bag scan off the per-frame path.
		self._tradeAcc = (self._tradeAcc or 0) + e
		if self._tradeAcc >= 20 then
			self._tradeAcc = 0
			RM.Refresh()
		end
		-- Shrinking roll-timer bars on the item rows (ElvUI M:statusbarOnUpdate style):
		-- read GetLootRollTimeLeft(rollID) each frame and scale the row-width bar.
		if self.itemRows then
			self._dots = (self._dots or 0) + e
			local dots = ("."):rep(1 + (math.floor(self._dots * 2) % 3))   -- . / .. / ...
			local needRefresh = false
			for _, r in ipairs(self.itemRows) do
				local d = r._d
				if r:IsShown() and r._rolling and d then
					-- SETTLED: the roll is over the moment the item has an owner (or
					-- everyone passed). recordRollWon() clears rollID *and* rollStart, which
					-- left `frac` nil below -- so the "timer ended" branch never fired and
					-- this loop kept re-appending "- rolling" from a STALE _baseTxt (captured
					-- before the winner was known). That is why an awarded item stayed
					-- "rolling ..." until you clicked it and forced a Refresh.
					if d.receivedBy or d.passed or not (d.rollID or d.rollStart) then
						r._rolling = false
						r.bar:Hide()
						needRefresh = true    -- repaint once after the loop, not per row
					else
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
						-- TIMER EXPIRED with no winner event: stop showing "rolling" so the
						-- bar doesn't stay stuck forever.
						if frac and frac <= 0 then
							r._rolling = false
							d.rollID = nil; d.rollStart = nil
							if r._baseTxt then r.txt:SetText(r._baseTxt) end
						elseif r._baseTxt then
							r.txt:SetText(r._baseTxt .. "  |cffffd200- rolling " .. dots .. "|r")
						end
					end
				end
			end
			-- one repaint per frame, after the loop (not once per settled row)
			if needRefresh then RM.Refresh() end
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

-- Re-apply the current size mode to the frame chrome, then rebuild the body.
-- Called by the [-]/[+] toggle and on every show (the DB may have changed).
function RM.ApplyMode()
	if not win then return end
	local compact = db().compact
	win:SetWidth(WIN_W)
	if win.title then
		win.title:SetText(compact and "Okanvil - Roll" or "Okanvil - Mini Roll Manager")
	end
	if win.sizeBtn then
		win.sizeBtn.text:SetText(compact and "+" or "-")
	end
	-- body is built once, so re-anchor it for the new mode
	if win.body then
		win.body:ClearAllPoints()
		win.body:SetPoint("TOPLEFT", 0, -BODY_TOP()); win.body:SetPoint("BOTTOMRIGHT", 0, 0)
	end
	local ok, err = pcall(RM.Rebuild)
	if not ok then Okanvil:Print("|cffff5555Roll rebuild error:|r " .. tostring(err)) end
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
	local compact = db().compact and true or false
	local ac = Okanvil.Colors and Okanvil.Colors.accent or { 0.75, 0.58, 0.23 }

	-- UNIFIED layout: raider and ML share the same look (boss pager, item box,
	-- rolls box, "Your roll"). The ML additionally gets the management controls
	-- (Start roll MS/OS/Free/Stop + Award/Clear). Raider just watches + rolls.
	local M = compact and 8 or 12
	local INNER = WIN_W - M * 2
	local y = compact and -4 or -6

	-- boss pager header:  <  Boss Name (1/3)  >
	-- The label is anchored BETWEEN the two buttons (not to the body with a hardcoded
	-- -28 inset, which assumed the full-size 24px button and overflowed the name in
	-- compact). Create `nxt` first so the label can anchor to it.
	local pgH = compact and 18 or 22
	local pgW = compact and 20 or 24
	local prev = keep(W.Button(body, "<")); prev:SetSize(pgW, pgH); prev:SetPoint("TOPLEFT", M, y)
	prev:SetScript("OnClick", function()
		f.bossIdx = math.max(1, (f.bossIdx or 1) - 1); selected = nil; f.userCleared = false; f.itemScroll = 0; f.rollScroll = 0; RM.Refresh()
	end)
	local nxt = keep(W.Button(body, ">")); nxt:SetSize(pgW, pgH); nxt:SetPoint("TOPRIGHT", -M, y)
	nxt:SetScript("OnClick", function()
		f.bossIdx = math.min(f.bossCount or 1, (f.bossIdx or 1) + 1); selected = nil; f.userCleared = false; f.itemScroll = 0; f.rollScroll = 0; RM.Refresh()
	end)
	local bossHd = keep(W.Text(body, "", FONT_SZ, "accent")); bossHd:Color(1, 0.82, 0)
	bossHd:SetPoint("LEFT", prev, "RIGHT", 4, 0); bossHd:SetPoint("RIGHT", nxt, "LEFT", -4, 0); bossHd:SetJustifyH("CENTER")
	if bossHd.SetWordWrap then bossHd:SetWordWrap(false) end
	f.bossHd = bossHd
	y = y - (pgH + 6)

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
	-- side scrollbar: a thin track on the right edge with a gold thumb whose size +
	-- position reflect how much of the list is shown / where we are. Replaces the
	-- old [+]/[v] end-row hints with a proper scroll indicator. Purely visual here
	-- (the wheel still does the scrolling); RM.Refresh sizes it each rebuild.
	local SB_W = 5
	local track = ibox:CreateTexture(nil, "ARTWORK")
	track:SetPoint("TOPRIGHT", -2, -3); track:SetPoint("BOTTOMRIGHT", -2, 3); track:SetWidth(SB_W)
	track:SetTexture(1, 1, 1, 0.06)   -- faint track
	local thumb = ibox:CreateTexture(nil, "OVERLAY")
	thumb:SetPoint("TOPRIGHT", -2, -3); thumb:SetWidth(SB_W)
	thumb:SetTexture(0.75, 0.58, 0.23, 0.9)   -- gold thumb
	f.sbTrack, f.sbThumb, f.sbW = track, thumb, SB_W
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
		-- TWO-LINE ROW. The icon takes the full height (so it is big enough to read at
		-- a glance), the item NAME sits on the top line with the whole width to itself,
		-- and the winner + trade timer share the line beneath it. Nothing has to be
		-- truncated to make room for anything else.
		local icoSz = ROW_H - 8
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(icoSz, icoSz)
		r.icon:SetPoint("LEFT", 5, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		-- line 1: item name, rarity-coloured
		r.txt = W.Text(r, "", FONT_SZ)
		r.txt:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 7, 1)
		r.txt:SetPoint("RIGHT", -6, 0)
		r.txt:SetJustifyH("LEFT")
		if r.txt.SetWordWrap then r.txt:SetWordWrap(false) end

		-- line 2: who won it (left) and how long it can still be traded (right)
		r.sub = W.Text(r, "", SUB_SZ)
		r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 7, 0)
		r.sub:SetJustifyH("LEFT")
		if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end

		r.timer = W.Text(r, "", SUB_SZ)
		r.timer:SetPoint("BOTTOMRIGHT", -6, 2)
		r.timer:SetJustifyH("RIGHT")
		r.sub:SetPoint("RIGHT", r.timer, "LEFT", -4, 0)
		r.hl = r:CreateTexture(nil, "BORDER"); r.hl:SetAllPoints(); r.hl:SetTexture(0.75, 0.58, 0.23, 0.22); r.hl:Hide()
		r:SetScript("OnEnter", function(s)
			if s._d and s._d.item then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(s._d.item); GameTooltip:Show() end
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		-- clicking an item SELECTS it -> the Rolls panel below shows that item's
		-- rolls (each person's need/greed). ANYONE can select (the
		-- raider just watches; the ML can also start a roll on the selected item).
		-- Clicking the same item again de-selects.
		r:SetScript("OnClick", function(s)
			if not s._d then return end
			-- toggle: clicking the already-selected item DE-selects. (Don't use the
			-- "a and nil or b" idiom -- nil is falsy in Lua, so "true and nil or s._d"
			-- returns s._d and never de-selected.)
			if selected == s._d then
				selected = nil
				f.userCleared = true    -- deliberate de-select: don't auto-pick again
			else
				selected = s._d
				f.userCleared = false
			end
			f.rollScroll = 0            -- new item -> start its roll list at the top
			RM.Refresh()
		end)
		f.itemRows[i] = r
		return r
	end
	y = y - (LIST_H + 6) - (compact and 6 or 10)

	-- ML-only: Start Roll row (4 equal buttons) ------------------------------
	if ml then
		local srH = compact and 22 or 26
		local sr = keep(W.Text(body, "Start roll (announces)", compact and 10 or 11, "dim")); sr:SetPoint("TOPLEFT", M, y); y = y - (compact and 13 or 16)
		local gap, bw = 6, (INNER - 3 * 6) / 4
		local function srBtn(label, kind, idx, fn)
			local b = keep(W.Button(body, label, kind)); b:SetSize(bw, srH)
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
		y = y - (srH + 6)
	end

	-- rolls: state line + list (both modes see the rolls) --------------------
	-- No caption above the list at all -- the rows speak for themselves, and the ML
	-- clicks a row to award without needing a label to say so.
	local lnH = compact and 13 or 16
	local rs = keep(W.Text(body, "", compact and 10 or 11, "dim")); rs:SetPoint("TOPLEFT", M, y); f.rollState = rs; y = y - lnH
	local rbox = keep(W.Frame(body, "dark")); rbox:SetPoint("TOPLEFT", M, y); rbox:SetSize(INNER, ROLL_ROWS * ROLL_H + 4)
	f.rbox = rbox
	-- mouse wheel pages the roll list (a big roll-off has more than ROLL_ROWS entries)
	rbox:EnableMouseWheel(true)
	rbox:SetScript("OnMouseWheel", function(_, delta)
		f.rollScroll = (f.rollScroll or 0) - delta   -- wheel up = higher rolls
		RM.Refresh()
	end)
	for i = 1, ROLL_ROWS do
		local r = CreateFrame("Button", nil, rbox)
		r:SetSize(INNER - 8, ROLL_H); r:SetPoint("TOPLEFT", 4, -2 - (i - 1) * ROLL_H)
		r.txt = W.Text(r, "", FONT_SZ); r.txt:SetPoint("LEFT", 4, 0); r.txt:SetPoint("RIGHT", -4, 0); r.txt:SetJustifyH("LEFT")
		r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(); r.hl:SetTexture(0.49, 0.99, 0.54, 0.16); r.hl:Hide()
		-- only ML can award by clicking a roll. Be LOUD about why a click no-ops
		-- (RaidRoll-style: always say why loot couldn't be awarded) instead of
		-- silently doing nothing -- that reads as "the button is broken".
		r:SetScript("OnClick", function(s)
			if not ml then return end
			if not s._roll then return end   -- empty roll row, ignore
			if not selected then Okanvil:Print("|cffff5555Pick an item in the list first, then click a roll to award.|r"); return end
			L.AwardWinner(selected.id, s._roll.player, s._roll.roll, s._roll.spec)
		end)
		f.rollRows[i] = r
	end
	y = y - (ROLL_ROWS * ROLL_H + 4) - (compact and 6 or 10)

	-- ML-only: award / clear -------------------------------------------------
	if ml then
		local awH = compact and 22 or 26
		local award = keep(W.Button(body, "Award top roll", "primary")); award:SetSize(INNER - 90, awH); award:SetPoint("TOPLEFT", M, y)
		award:SetScript("OnClick", function()
			local ar = L.ActiveRoll()
			if not selected then Okanvil:Print("|cffff5555Pick an item in the list first.|r"); return end
			if not ar then Okanvil:Print("|cffff5555No roll in progress -- press MS/OS/Free to start one.|r"); return end
			if not ar.best then Okanvil:Print("|cffff5555No rolls captured yet for this item.|r"); return end
			-- award the top roll for the item you actually started the roll on. If
			-- the selected list item drifted off the rolled item, warn instead of
			-- awarding the wrong drop.
			if ar.id and selected.id and ar.id ~= selected.id then
				Okanvil:Print("|cffff5555The active roll is for a different item than the one selected. Re-select the rolled item.|r"); return
			end
			L.AwardWinner(selected.id, ar.best.player, ar.best.roll, ar.best.spec)
		end)
		local clear = keep(W.Button(body, "Clear")); clear:SetSize(82, awH); clear:SetPoint("LEFT", award, "RIGHT", 8, 0)
		clear:SetScript("OnClick", function() selected = nil; L.StopRoll(); RM.Refresh() end)
		y = y - (awH + 10)

		-- Hide this run's items from THIS list. Does not delete: the history and the
		-- export keep everything (use the Loot page to actually delete a session).
		-- The list also clears itself when you zone into a new run, so this is only
		-- for tidying up mid-run.
		local wipeBtn = keep(W.Button(body, "Hide from this list")); wipeBtn:SetSize(INNER, 22); wipeBtn:SetPoint("TOPLEFT", M, y)
		wipeBtn:SetScript("OnClick", function()
			if not StaticPopupDialogs["OKANVIL_ROLL_CLEAR"] then
				StaticPopupDialogs["OKANVIL_ROLL_CLEAR"] = {
					text = "Hide this run's loot from the mini roll list?\n\n"
						.. "|cff7cfc8aNothing is deleted|r -- the history and the export keep it.\n"
						.. "(Any roll in progress is cancelled.)",
					button1 = YES, button2 = NO,
					OnAccept = function()
						if L.ClearActiveDrops and L.ClearActiveDrops() then
							selected = nil
							Okanvil:Print("Hidden from the list (history kept).")
						end
						RM.Refresh()
					end,
					timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
				}
			end
			StaticPopup_Show("OKANVIL_ROLL_CLEAR")
		end)
		y = y - (compact and 24 or 28)
	end

	-- Your roll -- MASTER LOOT ONLY ------------------------------------------
	-- Under group loot / need-before-greed the game shows its own roll frame and
	-- these buttons would just spam a /roll nobody reads. Only a master-loot run
	-- decides by a chat roll-off, so that's the only place they belong.
	if L.IsMasterLootMethod and L.IsMasterLootMethod() then
		local yrl = keep(W.Text(body, "Your roll", compact and 10 or 11, "dim")); yrl:SetPoint("TOPLEFT", M, y); y = y - (compact and 15 or 18)
		local hw = (INNER - 8) / 2
		local bh = compact and 22 or 28
		local myms = keep(W.Button(body, "Roll MS (100)", "primary")); myms:SetSize(hw, bh); myms:SetPoint("TOPLEFT", M, y)
		myms:SetScript("OnClick", function() L.SelfRoll("ms") end)
		local myos = keep(W.Button(body, "Roll OS (99)")); myos:SetSize(hw, bh); myos:SetPoint("LEFT", myms, "RIGHT", 8, 0)
		myos:SetScript("OnClick", function() L.SelfRoll("os") end)
		y = y - (bh + 4)
	end
	-- (fragment/BoE collector tally is NOT shown here -- it lives on the Loot page's
	--  COLLECTED panel. The mini manager stays focused on rolling.)
	f.colInfo = nil

	f:SetHeight(BODY_TOP() + (-y) + 8)

	RM.Refresh()
end

-- ------------------------------------------------------------
-- refresh -- paint items, rolls from the Loot module's live data
-- ------------------------------------------------------------
-- Jump to and SELECT the item with this id, across ALL boss tabs. Fired when a roll
-- starts (L.onRollStart) so you don't have to search the tabs for the item being
-- rolled -- Okanvil pages to it and selects it, and its live rolls show immediately.
-- Jump to the item being rolled: find it among the drops, switch to ITS boss page,
-- and select it. Called whenever a roll starts (ours or an external roller's), so the
-- manager always shows the item the raid is actually rolling on -- you never have to
-- hunt for it, and the rolls have somewhere to land.
--
-- This must work with the window CLOSED: the manager is built lazily, and it is the
-- roll starting that opens it. Bailing out on `not win` meant a roll announced before
-- you ever opened the manager selected nothing at all, so every roll was discarded.
function RM.SelectItemById(id)
	if not id then return end

	-- Two passes: first an item still OPEN for rolls (not awarded), so re-rolling a
	-- fresh drop of an id doesn't land on an old awarded copy; then any copy of the id.
	local groups = L.DropsByBoss and L.DropsByBoss() or {}
	local function pick(openOnly)
		for gi, g in ipairs(groups) do
			for ii, d in ipairs(g.items) do
				if d.id == id and (not openOnly or not d.receivedBy) then
					selected = d                    -- module-scope: survives the window not existing
					pendingBossIdx = gi             -- applied when the window is (re)built

					-- Scroll the item INTO VIEW. Selecting row 9 of a 5-row list would
					-- otherwise highlight something you cannot see -- the item being
					-- rolled has to be on screen, not just selected. Centre it in the
					-- page, clamped to the ends of the list.
					local maxOff = math.max(0, #g.items - ITEM_ROWS)
					local off = math.floor(ii - 1 - (ITEM_ROWS - 1) / 2)
					pendingItemScroll = math.max(0, math.min(off, maxOff))

					if win then
						win.bossIdx = gi
						win.userCleared = false
						win.rollScroll = 0
						win.itemScroll = pendingItemScroll
					end
					RM.Refresh()                    -- no-op while hidden; the selection still stands
					return true
				end
			end
		end
		return false
	end
	if pick(true) then return end
	pick(false)
end

function RM.Refresh()
	if not win or not win:IsShown() then return end
	local f = win

	local ar = L.ActiveRoll()

	-- per-boss pager: pick the current boss group and list its items (both modes)
	local groups = L.DropsByBoss and L.DropsByBoss() or {}
	f.bossCount = #groups
	if f.bossCount == 0 then
		if f.bossHd then f.bossHd:SetText("|cff8a8d93No loot yet|r") end
		for _, r in ipairs(f.itemRows) do r:Hide() end
		if f.sbThumb then f.sbThumb:Hide(); if f.sbTrack then f.sbTrack:Hide() end end
	else
		-- auto-jump to the newest boss when fresh loot just arrived (a new kill).
		-- DropsByBoss() lists bosses in arrival order, so newest = last.
		if f._jumpNewest then f.bossIdx = f.bossCount; f._jumpNewest = nil end
		f.bossIdx = math.max(1, math.min(f.bossIdx or 1, f.bossCount))
		local g = groups[f.bossIdx]
		if f.bossHd then
			-- Truncate the BOSS NAME, never the counter. SetWordWrap(false) clips the
			-- tail, so "Argent Confessor Paletress (2/3)" lost the "/3)" -- you could no
			-- longer see how many bosses there were. Cut the name, keep "(2/3)" whole.
			local bn = g.boss or "?"
			local maxB = db().compact and 20 or 28
			if #bn > maxB then bn = bn:sub(1, maxB - 1) .. ".." end
			f.bossHd:SetText(bn .. "  |cff8a8d93(" .. f.bossIdx .. "/" .. f.bossCount .. ")|r")
		end
		-- VALIDAR a seleccao AQUI (antes de desenhar os itens/highlight): o `selected`
		-- so vale se pertence ao boss ATUAL mostrado. Mudar de boss com <> limpa uma
		-- seleccao de outro boss, e o highlight fica sincronizado.
		if selected then
			local inThisBoss = false
			for _, d in ipairs(g.items) do if d == selected then inThisBoss = true; break end end
			if not inThisBoss then selected = nil end
		end
		-- AUTO-SELECT: with nothing picked, show the first item's rolls straight away
		-- instead of an empty "Click an item" panel. Prefer an item still being rolled
		-- (that's the actionable one); otherwise fall back to the first drop. Clicking
		-- an item still toggles it off -- `userCleared` remembers that so we don't
		-- immediately re-select it on the next repaint.
		if not selected and not f.userCleared and #g.items > 0 then
			local pick
			for _, d in ipairs(g.items) do
				if (d.rollID or d.rollStart) and not d.receivedBy and not d.passed then pick = d; break end
			end
			selected = pick or g.items[1]
		end
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
			-- leave room on the right for the scrollbar (track width + gaps)
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", 4, -2 - (i - 1) * ROW_H); r:SetPoint("RIGHT", f.ibox, "RIGHT", -4 - (f.sbW or 5) - 3, 0); r:SetHeight(ROW_H)
			if d then
				r._d = d
				r.icon:Show(); r.icon:SetTexture(itemIcon(d.item) or "Interface\\Icons\\INV_Misc_QuestionMark")
				r.txt:SetTextColor(1, 1, 1)   -- base; inline codes do the coloring
				local cr, cg, cb = rarityColor(d.rarity)
				local rcode = string.format("|cff%02x%02x%02x", cr * 255, cg * 255, cb * 255)

				-- LINE 1: the item name gets the row to itself, so it no longer has to be
				-- cut short to leave room for a winner and a timer.
				local baseTxt = rcode .. (d.name ~= "" and d.name or "?") .. "|r"

				-- LINE 2, left: who owns it. Under master loot every item passes through
				-- the ML first, so `receivedBy` alone means "the ML is holding it" and
				-- says nothing about who it is for -- the roll winner is the real answer.
				local pendId, pendWho = L.PendingAward and L.PendingAward()
				local win = L.RollWinner and L.RollWinner(d)
				local mlName = L.MasterLooterName and L.MasterLooterName()
				-- Under master loot every item is handed to the ML first, so a receivedBy
				-- that is just the ML's own name means "still in his bags, nobody has won
				-- it yet" -- printing him as the owner is noise. Say nothing instead.
				local heldByML = mlName and d.receivedBy == mlName

				local sub
				if pendId and pendId == d.id and not d.receivedBy then
					sub = "|cff5e6166" .. pendWho .. " (giving...)|r"
				elseif win then
					sub = classColorCode(win.player) .. win.player .. "|r"
						.. " |cff8a8d93" .. (win.roll or 0) .. (win.kind == "os" and " os" or "") .. "|r"
				elseif d.passed then
					sub = "|cff8a8d93passed|r"
				elseif d.receivedBy and d.receivedBy ~= "" and not heldByML then
					sub = classColorCode(d.receivedBy) .. d.receivedBy .. "|r"
				else
					sub = ""          -- unrolled, or simply sitting with the ML
				end
				r.sub:SetText(sub)

				-- LINE 2, right: how long the item can still be traded. tradeTimeLeft only
				-- finds items sitting in OUR bags, which is exactly the master looter's
				-- case -- an item won on a roll is still ours to hand over, and that is
				-- precisely when the deadline matters. So ask regardless of receivedBy;
				-- an item that is not ours simply returns nil.
				local left = (not d.passed) and tradeTimeLeft(d.item) or nil
				r.timer:SetText(left and ("|cffc0943a" .. left .. "|r") or "")

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

		-- size + place the side scrollbar thumb from the scroll position. Thumb
		-- height = (visible / total) of the track; thumb top slides with `off`.
		if f.sbThumb and f.sbTrack then
			if nItems <= ITEM_ROWS then
				f.sbThumb:Hide(); f.sbTrack:Hide()   -- everything fits -> no bar
			else
				f.sbTrack:Show(); f.sbThumb:Show()
				local trackH = ITEM_ROWS * ROW_H       -- usable track height (approx)
				local thumbH = math.max(16, trackH * (ITEM_ROWS / nItems))
				local frac = (maxOff > 0) and (off / maxOff) or 0
				local yOff = -3 - frac * (trackH - thumbH)
				f.sbThumb:SetHeight(thumbH)
				f.sbThumb:ClearAllPoints()
				f.sbThumb:SetPoint("TOPRIGHT", f.ibox, "TOPRIGHT", -2, yOff)
				f.sbThumb:SetWidth(f.sbW or 5)
			end
		end
	end

	-- (the selection was already validated against the current boss above, before drawing
	-- the items -- so here `selected` is already valid or nil.)

	-- The bottom panel (state + rolls) only shows something when an item is SELECTED.
	-- No selection = empty (we don't auto-pick any item). "only when I select".
	local rollItem = selected

	-- WATCH the selected item for manual /rolls (ML rolling bag items by hand). Done
	-- here in Refresh so EVERY path that changes `selected` (click, boss page change,
	-- clear, award, auto-pick) updates the watch. No managed roll needed -- selecting
	-- the item is enough to see people's rolls live. (Refresh runs on select.)
	if L and L.WatchItem then L.WatchItem(selected) end

	-- roll state line
	if f.rollState then
		if rollItem then
			local nm = (rollItem.name ~= "" and rollItem.name) or "item"
			-- The winner already shows on the item row above (the "-> name") and the
			-- green ">" marks the winning roll below, so DON'T repeat the name here --
			-- just the item, plus "(all passed)" which isn't shown anywhere else.
			local note = (rollItem.passed and not rollItem.receivedBy) and "  |cff8a8d93(all passed)|r" or ""
			f.rollState:SetText("|cffffd200" .. nm .. "|r" .. note)
		elseif ar then
			f.rollState:SetText("|cffffd200Rolling...|r")
		else
			f.rollState:SetText("|cff5e6166Click an item to see its rolls.|r")
		end
	end

	-- ROLLS of the selected item (native need/greed in dp.rolls), OR the MANUAL roll
	-- (activeRoll) if no item is selected but a /roll is in progress.
	local sorted, best = {}, nil
	local selRolls = rollItem and rollItem.rolls
	local showingItemRolls = false
	if selRolls and #selRolls > 0 then
		-- item need/greed: Need beats everything; Greed and Disenchant compete at the
		-- SAME level (the game awards the highest roll between them -- a greed 14 does
		-- NOT beat a DE 35), so they share a rank and the number decides. Ties break on
		-- name: table.sort is not stable, so equal rolls would otherwise swap places
		-- between refreshes.
		-- need beats all; ms (main-spec manual) beats os (off-spec manual); greed/de
		-- tie at the base level (the game awards the higher number between them).
		local rank = { need = 3, ms = 2, greed = 1, de = 1, os = 0 }
		for _, e in ipairs(selRolls) do sorted[#sorted + 1] = e end
		table.sort(sorted, function(a, b)
			local ra, rb = rank[a.kind] or 0, rank[b.kind] or 0
			if ra ~= rb then return ra > rb end
			local va, vb = a.roll or 0, b.roll or 0
			if va ~= vb then return va > vb end
			return (a.player or "") < (b.player or "")
		end)
		-- Once the item HAS an owner, the winner is whoever actually received it --
		-- not the top roll. The two disagree whenever the game awards on a rule we
		-- don't model, or when the winner never appears in the captured rolls (you
		-- won an item and the green marker sat on the top greed roll instead).
		best = sorted[1]
		if rollItem.receivedBy and rollItem.receivedBy ~= "" then
			local low = rollItem.receivedBy:lower()
			local owner
			for _, e in ipairs(sorted) do
				if e.player and e.player:lower() == low then owner = e; break end
			end
			best = owner        -- nil when the receiver never rolled -> nothing highlighted
		end
		showingItemRolls = true
	elseif rollItem and ar then
		-- item selected AND a manual /roll (activeRoll) is running: show the manual
		-- roll results so the ML can click a name to award. Without this, selecting
		-- an item hid the /roll list and award silently no-oped ("no rolls captured"
		-- even though people rolled). Match by id when we can, else show them anyway.
		if (not ar.id) or (not rollItem.id) or (ar.id == rollItem.id) then
			local list = (ar and ar.list) or {}
			for _, e in ipairs(list) do sorted[#sorted + 1] = e end
			table.sort(sorted, function(a, b)
				if a.spec ~= b.spec then return a.spec == "main" end
				return a.roll > b.roll
			end)
			best = ar and ar.best
		end
		showingItemRolls = true
	elseif rollItem then
		-- item selected but NO rolls yet -> empty list (don't fall to the manual
		-- roll). showingItemRolls stays true so we show the right header.
		showingItemRolls = true
	else
		-- nothing selected and nothing rolling -> MANUAL roll (activeRoll).
		local list = (ar and ar.list) or {}
		for _, e in ipairs(list) do sorted[#sorted + 1] = e end
		table.sort(sorted, function(a, b)
			if a.spec ~= b.spec then return a.spec == "main" end
			return a.roll > b.roll
		end)
		best = ar and ar.best
	end
	-- SCROLL the roll list the same way the item list scrolls: more rolls than
	-- ROLL_ROWS used to just vanish off the bottom (you could only see ~4). Page with
	-- the wheel; clamp so we never scroll past the last full page.
	local nRolls = #sorted
	local maxRollOff = math.max(0, nRolls - ROLL_ROWS)
	f.rollScroll = math.max(0, math.min(f.rollScroll or 0, maxRollOff))
	local roff = f.rollScroll
	for i = 1, ROLL_ROWS do
		local r, e = f.rollRows[i], sorted[i + roff]
		if e then
			r._roll = e
			-- tag: spec (manual) OR need/greed/de type (native)
			local tag = ""
			if e.kind == "greed" then tag = " |cff8a8d93(greed)|r"
			elseif e.kind == "de" then tag = " |cff8a5ad9(DE)|r"
			elseif e.kind == "need" then tag = " |cff7cfc8a(need)|r"
			elseif e.spec == "off" then tag = " |cff8a5ad9(off)|r" end
			-- match on the ENTRY, not on player+roll: two people rolling the same number
			-- both matched, so the winner marker lit up on two rows at once. The manual
			-- roll's `best` is a separate table, so fall back to comparing the player.
			local isBest = best and (best == e or best.player == e.player)
			local mark = isBest and "|cff7cfc8a> |r" or "  "
			r.txt:SetText(mark .. classColorCode(e.player) .. e.player .. "|r  |cffffd200" .. (e.roll or 0) .. "|r" .. tag)
			r.hl:SetShown(isBest)
			r:Show()
		elseif i == 1 and showingItemRolls then
			-- selected item with no captured rolls (e.g. master loot, or still
			-- ongoing with nobody having rolled) -> a note instead of an empty panel.
			r._roll = nil
			r.txt:SetText("|cff5e6166   (no rolls captured for this item)|r")
			r.hl:Hide(); r:Show()
		else
			r._roll = nil; r:Hide()
		end
	end

	-- (collector tally intentionally not shown here -- it's on the Loot page)
end

-- pending "jump to the newest boss" request. Kept at MODULE scope (not on the
-- maybe-nil `win` frame) so a loot event that arrives BEFORE the window is ever
-- built is not lost -- showWin() applies it once the frame exists. This is what
-- makes the pager auto-advance to boss 2's loot instead of staying on boss 1.
local pendingJumpNewest = false

-- show the window (building + rebuilding the mode-specific body)
local function showWin()
	buildWindow()
	-- A roll that started while the window was closed already picked the item and the
	-- page it lives on. Honour that over "jump to newest", or opening the manager
	-- would land on the last boss instead of the item actually being rolled.
	if pendingBossIdx then
		win.bossIdx = pendingBossIdx
		win.userCleared = false
		win.rollScroll = 0
		win.itemScroll = pendingItemScroll or 0
		pendingBossIdx = nil
		pendingItemScroll = nil
		pendingJumpNewest = false
	elseif pendingJumpNewest then
		win._jumpNewest = true; pendingJumpNewest = false
	end
	win:Show()                       -- always show (idempotent)
	win:Raise()                      -- bring to front in case something covers it
	applySize()                      -- DB may have changed since the last show
	local ok, err = pcall(RM.ApplyMode)  -- never let a rebuild error leave it half-open
	if not ok then Okanvil:Print("|cffff5555Roll rebuild error:|r " .. tostring(err)) end
	if OkanvilLootDebug and L and L.Dbg then
		local p, _, _, x, y = win:GetPoint(1)
		L.Dbg("  showWin: visible=" .. tostring(win:IsVisible())
			.. " shown=" .. tostring(win:IsShown())
			.. " strata=" .. tostring(win:GetFrameStrata())
			.. " alpha=" .. string.format("%.2f", win:GetAlpha())
			.. " @ " .. tostring(p) .. " " .. tostring(math.floor(x or 0)) .. "," .. tostring(math.floor(y or 0)))
	end
end

-- We auto-pop when boss loot drops in the CURRENT run (we never resurrect a stale
-- session from a dungeon left hours ago -- that's the InLiveRun / current-drops gate).
-- We auto-pop when either we're inside a live run OR the Loot module actually has
-- drops for the current session right now. The InLiveRun() check alone raced with
-- zoning (loot could fire a hair before IsInInstance/ShouldRecord settled), which
-- swallowed the very first boss's auto-show. If real loot just landed, show it.
local function haveCurrentDrops()
	local g = Okanvil.Loot and Okanvil.Loot.DropsByBoss and Okanvil.Loot.DropsByBoss()
	return g and #g > 0
end
local function canAutoShow()
	if not db().autoShow then return false end
	if Okanvil.Loot and Okanvil.Loot.InLiveRun and Okanvil.Loot.InLiveRun() then return true end
	return haveCurrentDrops()
end

-- shared handler: request a jump to the newest boss, then show/refresh. The jump
-- flag lives at module scope so it survives even if `win` isn't built yet.
-- `force` = we KNOW a loot window is open in front of us (the LOOT_OPENED trigger,
-- RaidRoll/RCLootCouncil style) so show regardless of the InLiveRun timing race.
local function popOrRefresh(force)
	local dbg = OkanvilLootDebug and L and L.Dbg
	if dbg then
		L.Dbg("  |cffccccffpopOrRefresh|r force=" .. tostring(force)
			.. " shown=" .. tostring(win and win:IsShown())
			.. " autoShow=" .. tostring(db().autoShow)
			.. " canAuto=" .. tostring(canAutoShow()))
	end
	if win and win:IsShown() then
		-- only jump to the newest boss when this is a FORCED pop (NEW loot
		-- coming in, force=true). A normal refresh (e.g. winner filled, roll
		-- captured) must NOT change the page you're viewing -- just redraws.
		if force then
			win._jumpNewest = true; pendingJumpNewest = false
			win.userCleared = false   -- new loot -> auto-select it even if you'd cleared
		end
		RM.Refresh()
		if dbg then L.Dbg("  => refresh (already shown)") end
	elseif (force and db().autoShow) or canAutoShow() then
		pendingJumpNewest = true; showWin()        -- eligible (or forced) -> build, show, then jump
		if dbg then L.Dbg("  => |cff7cfc8aSHOW|r") end
	else
		pendingJumpNewest = true                    -- hidden + not eligible -> remember for next open
		if dbg then L.Dbg("  => |cffff5555NOT shown|r (not eligible)") end
	end
end
local function onLoot() popOrRefresh(false) end

-- also pop for a raider when a roll opens (so they see the Roll MS/OS buttons).
function RM.OnRollOpen() popOrRefresh(false) end

-- a loot window just opened with items in front of us -> always pop (forced).
function RM.OnLootWindow() popOrRefresh(true) end

-- Just hide (never toggle open). Used by Okanvil:CloseAll() on a DBM pull.
function RM.Hide()
	if win and win:IsShown() then win:Hide() end
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
		-- recover: force a clean show so a transient error can't wedge it closed.
		-- If even the recovery fails the window really is broken -- say so in the
		-- dev tab rather than leaving a dead frame behind with no trace.
		if win then
			local ok2, err2 = pcall(function() win:Show(); RM.Rebuild() end)
			if not ok2 and Okanvil.Err then Okanvil:Err("RollMgr recover", err2) end
		end
	end
end

-- ------------------------------------------------------------
-- boot: hook the Loot module's callbacks + register a slash
-- ------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
-- The ML can change mid-raid (leader reassigns it, or loot method flips). The
-- window bakes the ML-vs-raider layout at Rebuild() time, so without these it
-- stayed on whatever it was built with -- an ex-ML kept the Award/Start-roll
-- controls, and a new ML never got them. Rebuild only when the flag ACTUALLY
-- flips, so we don't thrash the frame on every roster tick.
ev:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
ev:RegisterEvent("PARTY_LEADER_CHANGED")

local lastML = nil
local lastMethod = nil
local function isMLMethod() return L and L.IsMasterLootMethod and L.IsMasterLootMethod() or false end
local function mlChanged()
	if not L then return end
	local now = isML()
	local method = isMLMethod()
	-- Rebuild on EITHER flip. Tracking only `isML` was not enough: switching the raid
	-- from group loot to master loot with SOMEONE ELSE as the ML leaves isML() false
	-- both sides, yet the "Your roll" buttons must appear (they are master-loot only).
	if now == lastML and method == lastMethod then return end
	local mlFlipped = (now ~= lastML)
	lastML, lastMethod = now, method
	if win and win:IsShown() then
		local ok, err = pcall(RM.Rebuild)
		if not ok then Okanvil:Print("|cffff5555Roll rebuild error:|r " .. tostring(err)) end
	end
	if not mlFlipped then return end     -- method-only change: no need to announce
	local who = L.MasterLooterName and L.MasterLooterName()
	if now then
		Okanvil:Print("You are now the |cff7cfc8aMaster Looter|r.")
	elseif who then
		Okanvil:Print("Master Looter is now |cffffd200" .. who .. "|r.")
	end
end

ev:SetScript("OnEvent", function(_, event)
	if event ~= "PLAYER_LOGIN" then mlChanged(); return end
	if not Okanvil.Loot then return end
	L = Okanvil.Loot
	lastML = isML()
	lastMethod = isMLMethod()
	-- chain onto Loot's callbacks without clobbering them
	local prevLoot = L.onLoot
	L.onLoot = function() if prevLoot then prevLoot() end; onLoot() end
	L.onRoll = function() RM.OnRollOpen() end
	-- a roll just STARTED on an item id -> page to it and select it (no tab hunting)
	L.onRollStart = function(id) local ok, err = pcall(RM.SelectItemById, id)
		if not ok and Okanvil.Err then Okanvil:Err("RollMgr SelectItemById", err) end end
	-- fired the instant a loot window opens with items (RaidRoll / RCLootCouncil
	-- model) -- pop the mini roll even if the item is filtered from recording, and
	-- regardless of the InLiveRun timing race (we KNOW a corpse is open).
	local prevWin = L.onLootWindow
	L.onLootWindow = function() if prevWin then prevWin() end; RM.OnLootWindow() end
end)

SLASH_OKROLL1 = "/okroll"
SlashCmdList["OKROLL"] = function() RM.Toggle() end
