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

-- ONE layout, deliberately small. There used to be a second, wider one a chevron
-- away in the title bar -- but this window's job is to sit beside the loot frame
-- without covering what you are rolling on, which is the small one, every time.
--
-- An item row is TWO lines: the item name on top, the winner and trade timer below.
-- One line meant the name, the winner and the timer all fought for the same width, so
-- everything was truncated and the rows were unreadable. Two lines give each
-- its own space and let the icon grow.
--
-- The rolls are NOT a separate panel: expanding an item inserts its rolls as extra rows
-- in this same list (an accordion). One list means one scroll, no repeated item caption,
-- and the rolls sit directly under the item they belong to.
--   LIST_ROWS -- visible rows of the mixed list (items + any expanded rolls).
--   MAX_ROLLS -- rolls shown inline before the roll block itself starts scrolling.
-- One size. There used to be a "full" layout twice this wide, switched by a
-- chevron in the title bar -- but the compact one is what the window is FOR: a
-- small thing beside the loot frame that never covers what you are looting.
local SIZE = { ROW_H = 26, FONT_SZ = 11, SUB_SZ = 9, ROLL_H = 15, LIST_ROWS = 10, WIN_W = 270 }
local MAX_ROLLS = 5   -- inline rolls visible at once; the rest scroll within the block

-- Live geometry, unpacked from SIZE. These are locals rather than SIZE lookups
-- because the layout code reads them on every row of every rebuild.
local ROW_H, FONT_SZ, SUB_SZ, ROLL_H, LIST_ROWS, WIN_W =
	SIZE.ROW_H, SIZE.FONT_SZ, SIZE.SUB_SZ, SIZE.ROLL_H, SIZE.LIST_ROWS, SIZE.WIN_W

-- HORIZONTAL GEOMETRY -- one source of truth, so the item name, the roll name and the
-- tree glyph cannot drift apart (they are three different frames that must line up).
--   PAD      inset of a row's content from the row edge -- the SAME on the left and
--            right, which is what makes the highlight look centred.
--   ICO_GAP  gap between the icon and the item name.
-- textX() is where an item's NAME starts; the rolls indent to exactly that column, so
-- a roll reads as hanging off the item above it.
--
-- These MUST be declared after ROW_H: a Lua function closes over the locals visible
-- where it is WRITTEN, so declaring them above would have captured a global (nil) ROW_H
-- and thrown on the first row it drew.
local PAD, ICO_GAP = 4, 7
local function iconSize() return ROW_H - 4 end
local function textX() return PAD + iconSize() + ICO_GAP end

local function db()
	local d = Okanvil.db.rollmgr
	if not d then
		d = { point = "RIGHT", x = -30, y = 60, autoShow = true }
		Okanvil.db.rollmgr = d
	end
	-- `compact` and `compactDefaulted` may still be sitting in an older saved
	-- profile. Nothing reads them any more -- there is one layout now -- and they
	-- are left alone rather than deleted, so downgrading keeps its setting.
	return d
end

-- pull the geometry for the currently-selected mode into the locals above
-- Pixels from the window top to the body frame: the 26px header + the status line.
-- ONE source of truth -- the body anchor and the final SetHeight both use it, so a
-- mode switch can never leave them disagreeing (which clipped the bottom buttons).
-- no status line (ML / Raider): the tabs already say which mode you're in, so the
-- body starts straight under the title bar.
local function BODY_TOP() return 28 end

-- Icon resolver: delegates to the shared Core warmer (Okanvil:ItemIcon), which
-- returns the icon now or nil + auto-queues a server query so a later tick fills
-- it in. Fixes the "?" icons on a fresh client without any manual hovering.
local function itemIcon(itemLink)
	return itemLink and Okanvil:ItemIcon(itemLink) or nil
end

-- Should the body carry the "Roll MS / Roll OS" buttons? They /roll into chat, which is
-- the RATS roll-off convention -- and that convention only runs under MASTER LOOT. Under
-- group loot / need-before-greed you roll in Blizzard's own need/greed frame, so a manual
-- chat /roll there is noise; a stray /roll under a Blizzard roll-off just confuses the ML.
--
-- So the buttons show only when the group is actually on master loot (which already
-- implies party/raid -- there is no master loot solo). It stays a named function because
-- Rebuild decides the layout from it and OnRollOpen decides whether the layout needs
-- rebuilding from it, and those two must never disagree.
local function wantsChatRollButtons()
	return L and L.IsMasterLootMethod and L.IsMasterLootMethod() or false
end

-- are we the loot master right now? (drives ML-vs-raider layout)
-- MUST match the Loot module's real check: master-loot method AND *we* are the ML.
-- The old test only checked the method was "master" (true for EVERYONE in the raid,
-- not just the ML), so it showed the "Loot Master" layout + Award button to plain
-- raiders who can't actually give loot -- and disagreed with the Loot page's
-- "not the Master Looter" banner. Delegate to L.IsMasterLooter so they always agree.
local function amML()
	-- COUNCIL TEST MODE counts as being the master looter, but ONLY SOLO. Solo
	-- there is no raid and no master loot, so isML() is false and every ML
	-- control is hidden -- including the Council row, which is the whole point of
	-- the test.
	--
	-- In a real group the real answer is the only safe one: a test left switched
	-- on handed ML controls to someone who was not the master looter, in the
	-- middle of an actual raid.
	local CC = Okanvil.Council
	if CC and CC.testMode then
		local inGroup = (GetNumRaidMembers and GetNumRaidMembers() > 0)
			or (GetNumPartyMembers and GetNumPartyMembers() > 0)
		if not inGroup then return true end
	end
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
-- Pending "jump to the newest boss" request from a loot event. Declared HERE, beside
-- the other pending-page state, because SelectItemById must be able to CANCEL it: a
-- roll names an exact page and always outranks "go to the newest boss".
local pendingJumpNewest = false
local function isML() return amML() end

local function buildWindow()
	if win then return win end
	local f = CreateFrame("Frame", "Okanvil_RollMgr", UIParent)
	f:SetSize(WIN_W, 200)   -- height set dynamically in Refresh
	local d = db()
	f:SetPoint(d.point or "RIGHT", UIParent, d.point or "RIGHT", d.x or -30, d.y or 60)
	-- DIALOG, not HIGH. The main hub window is HIGH too, and two frames sharing a
	-- strata have no defined order between them -- so the mini roll and the hub
	-- interleaved, drawing the hub's rows through the roll list. This window
	-- floats OVER the hub by design, so it belongs one strata up.
	f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
	-- Level, not just strata: the council's frames share DIALOG, and two frames
	-- on the same level have no defined order either. Lowest of the three -- the
	-- council windows are opened ON TOP of this one and must stay readable.
	f:SetFrameLevel(10)
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
	local title = W.Text(hdr, "", "body", "accent"); title:SetPoint("LEFT", ico, "RIGHT", 6, 0); title:Color(1, 0.82, 0)
	f.title = title
	local close = W.Button(hdr, "X"); close:SetSize(22, 20); close:SetPoint("RIGHT", -3, 0)
	close:SetScript("OnClick", function() f:Hide() end)

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
		-- (a live roll announces itself ON the item row -- the shrinking bar and the
		--  "- rolling ..." suffix above -- so there is no separate status line.)
	end)

	win = f
	f:Hide()
	return f
end

-- Re-apply the window chrome, then rebuild the body. Called on every show.
function RM.ApplyMode()
	if not win then return end
	win:SetWidth(WIN_W)
	if win.title then
		win.title:SetText("Okanvil - Roll")
	end
	-- body is built once, so re-anchor it
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
	-- One row pool. A row renders EITHER as an item (icon + name + winner + timer) or as
	-- a roll of the expanded item -- the list is a single mixed sequence of the two.
	f.itemRows = {}
	local body = f.body
	-- Once the list is placed, `trackTail` turns on and every widget kept after it is
	-- recorded with its layout y. fitList() then slides that whole tail up when the list
	-- turns out shorter than the cap it was laid out against.
	local trackTail = false
	local function keep(w)
		f.bodyKids[#f.bodyKids + 1] = w
		if trackTail then
			w._pts = nil          -- freshly laid out: fitList must re-capture its anchors
			f.tail[#f.tail + 1] = w
		end
		return w
	end

	local ml = isML()
		local ac = Okanvil.Colors and Okanvil.Colors.accent or { 0.75, 0.58, 0.23 }

	-- UNIFIED layout: raider and ML share the same look (boss pager, the list, "Your
	-- roll"). The ML additionally gets the management controls (Start roll MS/OS/Free/
	-- Stop + Award/Clear). The raider just watches and rolls.
	--
	-- M is the margin on ALL FOUR sides of the body, so the gap left of the "<" equals
	-- the gap right of the ">" and the list is inset the same amount on both edges.
	-- The body already starts BODY_TOP() below the window top (clear of the title bar),
	-- so the first row starts at -M, not at some extra hand-tuned offset on top of it.
	local M = 8
	local INNER = WIN_W - M * 2
	local y = -M

	-- boss pager header:  <  Boss Name (1/3)  >
	-- The label is anchored BETWEEN the two buttons (not to the body with a hardcoded
	-- -28 inset, which assumed the full-size 24px button and overflowed the name in
	-- compact). Create `nxt` first so the label can anchor to it.
	local pgH = 18
	local pgW = 20
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

	-- THE LIST -- items, plus the rolls of whichever item is expanded ---------
	-- LIST_ROWS is the CAP, not the size: the box is resized to what is actually in it
	-- (fitList below), so three drops give a three-row window instead of a tall empty
	-- panel. LIST_H here is only the starting height; Refresh has the real content.
	local LIST_H = LIST_ROWS * ROW_H
	local ibox = keep(W.Frame(body, "dark")); ibox:SetPoint("TOPLEFT", M, y); ibox:SetSize(INNER, LIST_H + 6)
	f.ibox = ibox
	f.listH = LIST_H
	-- Everything below the list is anchored under it, so shrinking the box has to move
	-- it all. From here on, every widget `keep()` places gets its y remembered, and
	-- fitList() slides that whole tail up by however much the list shrank.
	f.listAssumedH = LIST_H + 6
	f.tail = {}
	f.tailBaseH = nil        -- window height as laid out (before any shrink)
	trackTail = true
	-- mouse wheel scrolls the list. Over an expanded item's ROLLS the wheel scrolls
	-- the rolls instead, so a long roll-off doesn't drag the whole list around --
	-- the row under the cursor decides, which is set in the row's own OnMouseWheel.
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
	-- One row object serves BOTH jobs. It carries an item face (icon + name + winner +
	-- trade timer) and a roll face (indented name + number); render time shows one and
	-- hides the other. A single pool means the mixed list needs no second row type and
	-- no second scroll.
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
		local icoSz = ROW_H - 4
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(icoSz, icoSz)
		r.icon:SetPoint("LEFT", PAD, 0)
		r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		-- line 1: item name, rarity-coloured
		r.txt = W.Text(r, "", FONT_SZ)
		r.txt:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", ICO_GAP, 1)
		r.txt:SetPoint("RIGHT", -PAD, 0)
		r.txt:SetJustifyH("LEFT")
		if r.txt.SetWordWrap then r.txt:SetWordWrap(false) end

		-- line 2: who won it (left) and how long it can still be traded (right)
		r.sub = W.Text(r, "", SUB_SZ)
		r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", ICO_GAP, 0)
		r.sub:SetJustifyH("LEFT")
		if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end

		r.timer = W.Text(r, "", SUB_SZ)
		r.timer:SetPoint("BOTTOMRIGHT", -PAD, 2)
		r.timer:SetJustifyH("RIGHT")
		r.sub:SetPoint("RIGHT", r.timer, "LEFT", -4, 0)
		r.hl = r:CreateTexture(nil, "BORDER"); r.hl:SetAllPoints(); r.hl:SetTexture(0.75, 0.58, 0.23, 0.22); r.hl:Hide()

		-- ROLL FACE: shown instead of the item face when this row renders a roll of the
		-- expanded item.
		--
		-- TREE GUIDE: two 1px LINES (textures), drawn -- not text glyphs. "|-" and "`-"
		-- render in a proportional font, so they never line up down the column nor sit at
		-- the right height, which is what made the branch look broken.
		--
		-- `stem` is the vertical run down the row, `elbow` the tick across to the name.
		-- Every roll gets the same pair, full height: stopping the stem half-way on the
		-- last roll left a stub dangling mid-row instead of reading as a corner.
		local TREE_X = PAD + 6            -- the column the branch runs down
		r.stem = r:CreateTexture(nil, "ARTWORK")
		r.stem:SetWidth(1)
		r.stem:SetTexture(0.45, 0.45, 0.48, 0.9)
		r.stem:Hide()
		r.elbow = r:CreateTexture(nil, "ARTWORK")
		r.elbow:SetHeight(1)
		r.elbow:SetTexture(0.45, 0.45, 0.48, 0.9)
		r.elbow:Hide()
		r._treeX = TREE_X

		r.rollTxt = W.Text(r, "", FONT_SZ)
		r.rollTxt:SetPoint("LEFT", textX(), 0)
		r.rollTxt:SetPoint("RIGHT", -PAD, 0)
		r.rollTxt:SetJustifyH("LEFT")
		if r.rollTxt.SetWordWrap then r.rollTxt:SetWordWrap(false) end
		r.rollTxt:Hide()

		r:SetScript("OnEnter", function(s)
			if s._roll then return end   -- a roll row has no item to preview
			if s._d and s._d.item then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(s._d.item); GameTooltip:Show() end
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)

		-- Wheel over an EXPANDED item's rolls scrolls the rolls; anywhere else it
		-- scrolls the list. Without this a long roll-off could only be reached by
		-- dragging the whole list, which pushed the item itself off screen.
		r:EnableMouseWheel(true)
		r:SetScript("OnMouseWheel", function(s, delta)
			if s._roll then
				f.rollScroll = (f.rollScroll or 0) - delta
			else
				f.itemScroll = (f.itemScroll or 0) - delta
			end
			RM.Refresh()
		end)

		-- CLICK.
		--   shift-click -> link the item into the open chat edit box (the game-wide
		--                  convention). Works on the item row and on its roll rows, since
		--                  both belong to the same item.
		--   item row    -> EXPAND it (anyone). Its rolls appear inline, right below.
		--                  Clicking the open item again collapses it. One at a time.
		--   roll row    -> AWARD that player (master looter only).
		r:SetScript("OnClick", function(s)
			if IsShiftKeyDown() then
				-- the item is on the row itself (item face) or on the selected drop the
				-- roll belongs to (roll face)
				local link = (s._d and s._d.item) or (s._roll and selected and selected.item)
				if link then
					-- ChatEdit_InsertLink only works when an edit box is already open;
					-- if none is, open one first, exactly like a shift-click in the bags.
					if not (ChatEdit_InsertLink and ChatEdit_InsertLink(link)) then
						local eb = ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend()
						if eb then
							ChatEdit_ActivateChat(eb)
							ChatEdit_InsertLink(link)
						end
					end
				end
				return
			end
			if s._roll then
				if not isML() then return end
				if not selected then return end
				L.AwardWinner(selected.id, s._roll.player, s._roll.roll, s._roll.spec)
				return
			end
			if not s._d then return end
			-- toggle: clicking the already-expanded item collapses it. (Don't use the
			-- "a and nil or b" idiom -- nil is falsy in Lua, so "true and nil or s._d"
			-- returns s._d and never collapsed.)
			if selected == s._d then
				selected = nil
				f.userCleared = true    -- deliberate collapse: don't auto-expand again
			else
				selected = s._d
				f.userCleared = false
				f.scrollToSelected = true   -- opened by hand: make sure it is in view
			end
			f.rollScroll = 0            -- new item -> start its rolls at the top
			RM.Refresh()
		end)
		f.itemRows[i] = r
		return r
	end
	y = y - (LIST_H + 6) - 6

	-- ML-only: COUNCIL row, above the rolls ----------------------------------
	--
	-- Only when the council is switched on for this session (Loot Council page ->
	-- "Council night"). The two are NOT modes of the night: a master looter
	-- running a council still says "this one just roll" for a piece nobody is
	-- arguing about, so both rows act on the SAME selected item and each item goes
	-- one way or the other. With the council off, this row does not exist and the
	-- mini roll is exactly what it has always been.
	local CC = Okanvil.Council
	if ml and CC and CC.active and CC.Enabled and CC.Enabled() then
		local ccH = 22
		local cc = keep(W.Text(body, "Loot council", 10, "dim")); cc:SetPoint("TOPLEFT", M, y); y = y - 13
		local gap2, bw2 = 6, (INNER - 6) / 2
		local askB = keep(W.Button(body, "Ask this one", "primary"))
		askB:SetSize(bw2, ccH); askB:SetPoint("TOPLEFT", M, y)
		askB:SetScript("OnClick", function()
			if not (selected and selected.item) then Okanvil:Print("Pick an item first."); return end
			-- Starting a council round on something being rolled on closes the roll
			-- first: two ways of deciding one item at once is how a raid ends up
			-- with two winners.
			if L.StopRoll then L.StopRoll() end
			CC.Ask({ selected.item }, selected.boss or "")
		end)
		local pickB = keep(W.Button(body, "Pick several"))
		pickB:SetSize(bw2, ccH); pickB:SetPoint("TOPLEFT", M + bw2 + gap2, y)
		pickB:SetScript("OnClick", function()
			if CC.OpenPicker then CC.OpenPicker() end
		end)
		y = y - (ccH + 8)
	end

	-- ML-only: Start Roll row (4 equal buttons) ------------------------------
	if ml then
		local srH = 22
		local sr = keep(W.Text(body, "Start roll (announces)", 10, "dim")); sr:SetPoint("TOPLEFT", M, y); y = y - 13
		-- TWO buttons, not four. Free was a third kind of roll nobody called, and
		-- Stop is still on /okroll stop -- four buttons at 62px each was a row you
		-- had to read rather than aim at.
		local gap, bw = 6, (INNER - 6) / 2
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
		y = y - (srH + 6)
	end

	-- NO "Send prio" button. The ladder is on the Loot Council page and under the
	-- item on the council board -- the two places an officer is already looking
	-- when they need it. Posting it to officer chat from here was a third copy,
	-- and the button spent most of its life reading "(not on the list)".

	-- (No separate rolls panel: the rolls render inside the list above, under whichever
	--  item is expanded.)

	-- ML-only: award ---------------------------------------------------------
	-- "Stop" above already cancels a roll, and clicking the winning roll in the list
	-- awards the item -- so this is only the shortcut for "give it to the top roll"
	-- without aiming at the name. Hiding the run's loot lives on the Loot page: it is
	-- end-of-raid tidying, not something you reach for mid-boss.
	if ml then
		local awH = 22
		local award = keep(W.Button(body, "Award top roll", "primary")); award:SetSize(INNER, awH); award:SetPoint("TOPLEFT", M, y)

		-- Say WHICH award this will be before it is clicked. GiveMasterLoot only works
		-- from an OPEN loot window; once the corpse is closed the item is in the ML's
		-- bags and the award can only be recorded, with the hand-over done by trade.
		-- Both are fine -- but finding out afterwards is what made this feel broken.
		award.SyncLabel = function()
			local open = (GetNumLootItems and (GetNumLootItems() or 0) > 0)
			if award.text then
				-- No embedded colour: a "primary" button paints its label DARK on
				-- gold, so a |cff8a8d93 grey landed grey-on-gold and could not be
				-- read. The distinction is carried by the word itself, and the
				-- tooltip explains it -- the same rule as the council's Give button.
				award.text:SetText(open and "Award top roll" or "Award top roll (record)")
			end
			award:Tooltip(open
				and "Hands the item straight to the winner through master loot."
				or  "The loot window is closed, so the item is already in your bags.\n"
				 .. "This records the winner and tells the raid -- you trade it over.\n\n"
				 .. "Keep the corpse's loot window OPEN during the roll to hand it\n"
				 .. "over automatically instead.")
		end
		award.SyncLabel()
		RM._awardBtn = award

		award:SetScript("OnClick", function()
			if not selected then Okanvil:Print("|cffff5555Open an item in the list first.|r"); return end
			-- Award the top roll of the OPEN item, from the rolls actually captured on
			-- it, falling back to a managed roll's own winner.
			local top = L.RollWinner and L.RollWinner(selected)
			if not top then
				local ar = L.ActiveRoll()
				if ar and ar.best and ((not ar.id) or (not selected.id) or ar.id == selected.id) then top = ar.best end
			end
			if not top then Okanvil:Print("|cffff5555No rolls captured for this item yet.|r"); return end
			L.AwardWinner(selected.id, top.player, top.roll, top.spec)
		end)
		y = y - (awH + 6)

		-- START FRESH. The list keeps the whole run, which is right during a raid
		-- and wrong the moment the next one starts -- last week's boss pages were
		-- still sitting there. This HIDES the drops (they stay in the history and
		-- the export); it does not delete the session.
		local clr = keep(W.Button(body, "Clear list (new raid)"))
		clr:SetSize(INNER, awH); clr:SetPoint("TOPLEFT", M, y)
		clr:Tooltip("Hides every item currently listed, so the window is empty for a\n"
			.. "new raid. The loot history and the export keep them.")
		clr:SetScript("OnClick", function()
			Okanvil:Confirm("Clear the mini roll list?\n"
				.. "|cff8a8d93The loot history keeps everything -- this only empties the window.|r",
				"Clear list",
				function()
					if L.ClearActiveDrops and L.ClearActiveDrops() then
						Okanvil:Print("Mini roll: list cleared.")
					else
						Okanvil:Print("Mini roll: nothing to clear.")
					end
					local ok, err = pcall(RM.Rebuild)
					if not ok and Okanvil.Err then Okanvil:Err("RollMgr clear", err) end
				end)
		end)
		y = y - (awH + 10)
	end

	-- Your roll ---------------------------------------------------------------
	if wantsChatRollButtons() then
		local yrl = keep(W.Text(body, "Your roll", 10, "dim")); yrl:SetPoint("TOPLEFT", M, y); y = y - 15
		local hw = (INNER - 8) / 2
		local bh = 22
		local myms = keep(W.Button(body, "Roll MS (100)", "primary")); myms:SetSize(hw, bh); myms:SetPoint("TOPLEFT", M, y)
		myms:SetScript("OnClick", function() L.SelfRoll("ms") end)
		local myos = keep(W.Button(body, "Roll OS (99)")); myos:SetSize(hw, bh); myos:SetPoint("LEFT", myms, "RIGHT", 8, 0)
		myos:SetScript("OnClick", function() L.SelfRoll("os") end)
		y = y - (bh + 4)
	end
	-- (fragment/BoE collector tally is NOT shown here -- it lives on the Loot page's
	--  COLLECTED panel. The mini manager stays focused on rolling.)
	f.colInfo = nil

	-- Bottom margin = M, the same inset used on the other three sides. This is the
	-- height with the list at its FULL cap; fitList() trims it to the real content.
	f.tailBaseH = BODY_TOP() + (-y) + M
	f.tailMargin = M
	f:SetHeight(f.tailBaseH)

	RM.Refresh()
end

-- Shrink the list (and the window) to what is actually in it. The list is laid out
-- against LIST_ROWS -- the CAP -- so three drops would otherwise leave a tall empty
-- panel and a window mostly full of nothing.
--
-- `usedH` is the real height of the rendered rows. Everything below the list slides up
-- by the difference, and the window loses the same amount.
--
-- Widgets are moved by re-applying ALL of their points, not just the first. A widget
-- gets its WIDTH from a second anchor (a TOPLEFT plus a RIGHT); clearing the lot and
-- restoring only point 1 drops that second anchor, and the widget collapses to the
-- width of its own text -- which squeezed the whole window into a sliver.
local function fitList(f, usedH)
	if not (f.ibox and f.tail and f.tailBaseH) then return end
	local full = f.listAssumedH or (LIST_ROWS * ROW_H + 6)
	local want = math.min(full, math.max(ROW_H, usedH + 6))
	local shrink = full - want
	f.ibox:SetHeight(want)
	f.listH = want - 6

	for _, w in ipairs(f.tail) do
		if w.GetNumPoints and w:GetNumPoints() > 0 then
			-- capture every point ONCE, before anything has been moved
			if not w._pts then
				local pts = {}
				for i = 1, w:GetNumPoints() do
					local p, rel, rp, x, wy = w:GetPoint(i)
					pts[i] = { p = p, rel = rel, rp = rp, x = x, y = wy }
				end
				w._pts = pts
			end
			w:ClearAllPoints()
			for _, pt in ipairs(w._pts) do
				-- Only points anchored to the BODY shift: one anchored to a sibling
				-- follows that sibling on its own and must keep its original offset.
				local dy = (pt.rel == f.body) and shrink or 0
				w:SetPoint(pt.p, pt.rel, pt.rp, pt.x, (pt.y or 0) + dy)
			end
		end
	end
	f:SetHeight(f.tailBaseH - shrink)
end

-- ------------------------------------------------------------
-- refresh -- paint items, rolls from the Loot module's live data
-- ------------------------------------------------------------
-- Page to the item with this id, OPEN it, and scroll it into view. Fired when a roll
-- starts (L.onRollStart), ours or an external roller's raid-warning, so the manager
-- always shows the item the raid is actually rolling on -- you never hunt the boss
-- tabs for it, and everyone watches the rolls land under it.
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

					-- Scroll so the rolled item sits at the TOP of the view: its rolls
					-- expand BELOW it, so centring the item would push them off the
					-- bottom. Clamp to the last full page.
					local maxOff = math.max(0, #g.items - LIST_ROWS)
					pendingItemScroll = math.max(0, math.min(ii - 1, maxOff))

					if win then
						win.bossIdx = gi
						win.userCleared = false
						win.rollScroll = 0
						win.itemScroll = pendingItemScroll
						-- A loot event may have queued a jump to the newest boss. The
						-- roll is the newer intent and names an exact page, so drop it --
						-- otherwise the next Refresh pages away from the rolled item.
						win._jumpNewest = nil
					end
					pendingJumpNewest = false
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

-- The rolls of one item, ranked. ONE roll per player (the Loot module already keeps
-- only the first, this guards the manual-roll list too, which has no such rule).
--
-- Rank: need beats all; ms (a /roll 1-100) beats os (a /roll 1-99); greed and
-- disenchant tie at the base level (the game awards the higher number between them,
-- so a greed 14 does NOT beat a DE 35). Equal ranks go to the higher number, and
-- equal numbers break on name -- table.sort is not stable, so without that tiebreak
-- two people on the same roll would swap places on every repaint.
local RANK = { need = 3, ms = 2, greed = 1, de = 1, os = 0 }

local function rankedRolls(dp, ar)
	local out, seen = {}, {}
	local src
	if dp and dp.rolls and #dp.rolls > 0 then
		src = dp.rolls
	elseif dp and ar and ((not ar.id) or (not dp.id) or (ar.id == dp.id)) then
		src = ar.list          -- a managed /roll running on this item
	end
	for _, e in ipairs(src or {}) do
		local key = (e.player or ""):lower()
		if key ~= "" and not seen[key] then
			seen[key] = true
			out[#out + 1] = e
		end
	end
	table.sort(out, function(a, b)
		-- the manual roll list tags off-spec as `spec`, the captured one as `kind`
		local ka = a.kind or ((a.spec == "off") and "os" or "ms")
		local kb = b.kind or ((b.spec == "off") and "os" or "ms")
		local ra, rb = RANK[ka] or 0, RANK[kb] or 0
		if ra ~= rb then return ra > rb end
		local va, vb = a.roll or 0, b.roll or 0
		if va ~= vb then return va > vb end
		return (a.player or "") < (b.player or "")
	end)

	-- The winner is whoever ACTUALLY received the item, not the top roll -- the two
	-- disagree whenever the game awards on a rule we don't model, or when the receiver
	-- never appears in the captured rolls.
	local best = out[1]
	if dp and dp.receivedBy and dp.receivedBy ~= "" then
		local low = dp.receivedBy:lower()
		best = nil
		for _, e in ipairs(out) do
			if e.player and e.player:lower() == low then best = e; break end
		end
	end
	return out, best
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
		fitList(f, ROW_H)   -- nothing to show -> collapse to a single empty row
	else
		-- Fresh loot just arrived: jump to the page holding the NEWEST drop. Not simply
		-- the last page -- Trash always sits last, so a boss kill after some trash
		-- would have opened on Trash instead of the boss that just died.
		if f._jumpNewest then
			local best, bestT = f.bossCount, -1
			for gi, grp in ipairs(groups) do
				for _, d in ipairs(grp.items) do
					if (d.t or 0) > bestT then best, bestT = gi, (d.t or 0) end
				end
			end
			f.bossIdx = best
			f._jumpNewest = nil
		end
		f.bossIdx = math.max(1, math.min(f.bossIdx or 1, f.bossCount))
		local g = groups[f.bossIdx]
		if f.bossHd then
			-- Truncate the BOSS NAME, never the counter. SetWordWrap(false) clips the
			-- tail, so "Argent Confessor Paletress (2/3)" lost the "/3)" -- you could no
			-- longer see how many bosses there were. Cut the name, keep "(2/3)" whole.
			local bn = g.boss or "?"
			local maxB = 20
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
			f.scrollToSelected = true   -- auto-opened: bring it into view once
		end
		-- BUILD THE MIXED LIST: every item, and -- directly under the OPEN one -- its
		-- rolls. One list, one scroll, and the rolls sit against the item they belong
		-- to instead of in a panel that had to repeat the item's name to say so.
		--
		-- Only the open item's rolls are inserted, and at most MAX_ROLLS of them: a
		-- 25-man roll-off would otherwise push every other item off the screen. The
		-- rest scroll within the block (wheel over a roll row).
		local entries = {}          -- { d = drop } | { roll = e, best = bool }
		local rolls, best
		for _, d in ipairs(g.items) do
			entries[#entries + 1] = { d = d }
			if selected == d then
				rolls, best = rankedRolls(d, ar)
				local nR = #rolls
				if nR == 0 then
					entries[#entries + 1] = { empty = true }
				else
					local maxR = math.max(0, nR - MAX_ROLLS)
					f.rollScroll = math.max(0, math.min(f.rollScroll or 0, maxR))
					local shown = math.min(MAX_ROLLS, nR)
					for i = 1, shown do
						local e = rolls[i + f.rollScroll]
						if e then
							entries[#entries + 1] = {
								roll = e,
								best = (best == e),
								more = (nR > MAX_ROLLS) and nR or nil,
							}
						end
					end
				end
			end
		end

		-- SCROLL the list. Clamp so we never scroll past the last full page.
		local nEnt = #entries
		local maxOff = math.max(0, nEnt - LIST_ROWS)
		f.itemScroll = math.max(0, math.min(f.itemScroll or 0, maxOff))
		local off = f.itemScroll

		-- BRING A NEWLY-OPENED ITEM INTO VIEW -- once, when it is opened, not on every
		-- repaint. Pinning the view to the open item every frame made `off` snap back to
		-- the item's own index on each rebuild, so the wheel could never move the list:
		-- with the open item at the top (index 1) the floor was 0 and the list was
		-- frozen outright. Scrolling away from an open item is legitimate -- you scroll
		-- to reach the items below it -- so only the moment of opening moves the view.
		if selected and f.scrollToSelected then
			for i, en in ipairs(entries) do
				if en.d == selected then
					-- only if it is actually off screen; an item already visible stays put
					if i - 1 < off or i - 1 >= off + LIST_ROWS then
						off = math.max(0, math.min(i - 1, maxOff))
						f.itemScroll = off
					end
					break
				end
			end
		end
		f.scrollToSelected = nil

		for _, r in ipairs(f.itemRows) do r._d = nil; r._roll = nil; r:Hide() end

		-- Rows pack from the top: an item row is ROW_H tall, a roll row only ROLL_H, so
		-- the y cursor advances by whatever the row actually is rather than by a fixed
		-- stride (which would leave a gap under every roll).
		local yRow = -2

		-- Reserve room for the scrollbar ONLY when there is one. Always reserving it
		-- left every row 12px clear of the right edge against 4px on the left, so the
		-- highlight sat visibly off-centre even on a list short enough to need no bar.
		local needBar = nEnt > LIST_ROWS
		local RIGHT_PAD = needBar and (PAD + (f.sbW or 5) + 3) or PAD

		for i = 1, LIST_ROWS do
			local en = entries[i + off]
			if not en then break end
			local r = f.makeItemRow(i)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", PAD, yRow)
			r:SetPoint("RIGHT", f.ibox, "RIGHT", -RIGHT_PAD, 0)

			if en.d then
				-- ---- ITEM FACE ----
				local d = en.d
				r:SetHeight(ROW_H); yRow = yRow - ROW_H
				r._d = d; r._roll = nil
				r.rollTxt:Hide(); r.stem:Hide(); r.elbow:Hide()
				r.icon:Show(); r.icon:SetTexture(itemIcon(d.item) or "Interface\\Icons\\INV_Misc_QuestionMark")
				r.txt:Show(); r.sub:Show(); r.timer:Show()
				r.txt:SetTextColor(1, 1, 1)   -- base; inline codes do the coloring
				local cr, cg, cb = rarityColor(d.rarity)
				local rcode = string.format("|cff%02x%02x%02x", cr * 255, cg * 255, cb * 255)

				-- LINE 1: the item name gets the row to itself, so it no longer has to be
				-- cut short to leave room for a winner and a timer.
				local baseTxt = rcode .. (d.name ~= "" and d.name or "?") .. "|r"

				-- LINE 2, left: who owns it. Under master loot every item passes through
				-- the ML first, so `receivedBy` alone means "the ML is holding it" and
				-- says nothing about who it is for -- the roll winner is the real answer.
				-- NOT `local a, b = f and f()`: `and` truncates its right side to ONE
				-- value, so the second return was always nil and the "(giving...)" line
				-- concatenated a nil. Call it on its own to keep both returns.
				local pendId, pendWho
				if L.PendingAward then pendId, pendWho = L.PendingAward() end
				local wn = L.RollWinner and L.RollWinner(d)
				local mlName = L.MasterLooterName and L.MasterLooterName()
				-- heldBy is set when the ML picks an item up to hand out later; the
				-- receivedBy test stays for rows captured before that field existed.
				local heldByML = (d.heldBy ~= nil and d.heldBy ~= "")
					or (mlName ~= nil and d.receivedBy == mlName)

				-- "passed" only ever means NOBODY has it, so a known owner outranks it:
				-- an item everyone passed on can still be handed out by the master
				-- looter afterwards, and that hand-over is the newer truth.
				local owned = d.receivedBy and d.receivedBy ~= "" and not heldByML

				local sub
				if pendId and pendId == d.id and pendWho and not d.receivedBy then
					sub = "|cff5e6166" .. pendWho .. " (giving...)|r"
				elseif wn then
					sub = classColorCode(wn.player) .. wn.player .. "|r"
						.. " |cff8a8d93" .. (wn.roll or 0) .. (wn.kind == "os" and " os" or "") .. "|r"
				elseif owned then
					sub = classColorCode(d.receivedBy) .. d.receivedBy .. "|r"
				elseif d.passed then
					sub = "|cff8a8d93passed|r"
				else
					sub = ""          -- unrolled, or simply sitting with the ML
				end
				r.sub:SetText(sub)

				-- LINE 2, right: how long the item can still be traded. tradeTimeLeft only
				-- finds items sitting in OUR bags, which is exactly the master looter's
				-- case -- an item won on a roll is still ours to hand over, and that is
				-- precisely when the deadline matters.
				local left = (not d.passed) and tradeTimeLeft(d.item) or nil
				r.timer:SetText(left and ("|cffc0943a" .. left .. "|r") or "")

				r.hl:SetShown(selected == d)
				-- roll timer bar: show while a roll is live for this item and not yet won.
				-- Live = a native need/greed roll (d.rollID) OR the time-based fallback
				-- (d.rollStart). Master loot has neither, so no bar. The window's OnUpdate
				-- shrinks it each frame and animates "rolling".
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

			elseif en.roll then
				-- ---- ROLL FACE (inline, under the open item) ----
				local e = en.roll
				r:SetHeight(ROLL_H); yRow = yRow - ROLL_H
				r._d = nil; r._roll = e; r._rolling = false
				r.icon:Hide(); r.txt:Hide(); r.sub:Hide(); r.timer:Hide(); r.bar:Hide()

				-- TREE. The stem runs the full height of every roll row and the elbow ticks
				-- across to where the name starts, so the branch reads as one continuous
				-- line down the column with a rung at each roll.
				local tx = r._treeX
				-- mid FLOORED + stem 1px TALLER than the row: with an odd ROLL_H (compact = 15)
				-- the fractional half (7.5) rounded inconsistently, so adjacent stems landed a
				-- hair apart -- some pixel-columns carried two overlapping 1px stems (a THICK/
				-- double line), others a gap. Snapping mid to an int + overlapping each stem 1px
				-- into the next row makes one clean continuous line (the artefact was compact-only).
				local mid = math.floor(ROLL_H / 2)
				r.stem:ClearAllPoints()
				r.stem:SetPoint("TOPLEFT", tx, 0)
				r.stem:SetHeight(ROLL_H + 1)
				r.stem:Show()

				-- Elbow starts 1px RIGHT of the stem so the horizontal rung ABUTS the vertical
				-- line instead of stacking a second texture in the stem's own pixel column --
				-- the overlapped corner was the darker/"doubled" rung. `mid` is already floored
				-- (integer), so the rung sits on a whole pixel row and stays a crisp 1px.
				r.elbow:ClearAllPoints()
				r.elbow:SetPoint("TOPLEFT", tx + 1, -mid)
				r.elbow:SetWidth(math.max(1, textX() - tx - 5))
				r.elbow:Show()

				-- tag: the roll TYPE. `kind` is the captured roll (need/greed/de, or ms/os
				-- from the 1-100 vs 1-99 range); `spec` is the managed roll's own field.
				local kind = e.kind or ((e.spec == "off") and "os" or "ms")
				local tag = ""
				if kind == "greed" then tag = " |cff8a8d93(greed)|r"
				elseif kind == "de" then tag = " |cff8a5ad9(DE)|r"
				elseif kind == "need" then tag = " |cff7cfc8a(need)|r"
				elseif kind == "os" then tag = " |cff8a5ad9(OS)|r" end

				local mark = en.best and "|cff7cfc8a> |r" or ""
				local more = ""
				if en.more then more = "  |cff5e6166(" .. en.more .. ")|r" end
				r.rollTxt:SetText(mark .. classColorCode(e.player) .. e.player .. "|r  |cffffd200"
					.. (e.roll or 0) .. "|r" .. tag .. more)
				r.rollTxt:Show()
				r.hl:SetShown(en.best and true or false)
				if en.best then r.hl:SetTexture(0.49, 0.99, 0.54, 0.16)
				else r.hl:SetTexture(0.75, 0.58, 0.23, 0.22) end
				r:Show()

			else
				-- ---- open item, but nobody has rolled yet ----
				r:SetHeight(ROLL_H); yRow = yRow - ROLL_H
				r._d = nil; r._roll = nil; r._rolling = false
				r.icon:Hide(); r.txt:Hide(); r.sub:Hide(); r.timer:Hide(); r.bar:Hide(); r.hl:Hide()
				-- same branch as a real roll, just with nothing hanging off it
				local tx, mid = r._treeX, math.floor(ROLL_H / 2)   -- floor + 1px overlap: see roll face above
				r.stem:ClearAllPoints(); r.stem:SetPoint("TOPLEFT", tx, 0)
				r.stem:SetHeight(ROLL_H + 1); r.stem:Show()
				r.elbow:ClearAllPoints(); r.elbow:SetPoint("TOPLEFT", tx + 1, -mid)   -- +1: abut, don't stack on the stem
				r.elbow:SetWidth(math.max(1, textX() - tx - 5)); r.elbow:Show()
				r.rollTxt:SetText("|cff5e6166no rolls yet|r")
				r.rollTxt:Show()
				r:Show()
			end
		end

		-- Shrink the list to the rows actually drawn (yRow is now the bottom of the last
		-- one), so a 3-drop boss gives a small window instead of a tall empty panel.
		fitList(f, -yRow)

		-- size + place the side scrollbar thumb from the scroll position. Thumb
		-- height = (visible / total) of the track; thumb top slides with `off`.
		if f.sbThumb and f.sbTrack then
			if not needBar then
				f.sbThumb:Hide(); f.sbTrack:Hide()   -- everything fits -> no bar
			else
				f.sbTrack:Show(); f.sbThumb:Show()
				local trackH = f.listH or (LIST_ROWS * ROW_H)
				local thumbH = math.max(16, trackH * (LIST_ROWS / nEnt))
				local frac = (maxOff > 0) and (off / maxOff) or 0
				local yOff = -3 - frac * (trackH - thumbH)
				f.sbThumb:SetHeight(thumbH)
				f.sbThumb:ClearAllPoints()
				f.sbThumb:SetPoint("TOPRIGHT", f.ibox, "TOPRIGHT", -2, yOff)
				f.sbThumb:SetWidth(f.sbW or 5)
			end
		end
	end

	-- WATCH the open item for manual /rolls (the ML rolling bag items by hand). Done
	-- here so EVERY path that changes `selected` (click, boss page, clear, award,
	-- auto-open) updates the watch: opening an item is enough to capture what people
	-- roll on it, no managed roll needed.
	if L and L.WatchItem then L.WatchItem(selected) end

	-- (collector tally intentionally not shown here -- it's on the Loot page)
end

-- (pendingJumpNewest is declared with the other pending-page state near the top: it
--  lives at MODULE scope, not on the maybe-nil `win` frame, so a loot event arriving
--  BEFORE the window is ever built is not lost -- showWin() applies it once the frame
--  exists. That is what makes the pager auto-advance to boss 2's loot.)

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
		-- A roll that just picked an item owns the page. L.NoteExternalRoll fires
		-- onRollStart (which pages to the item) and then onLootWindow (force=true)
		-- back to back, so jumping to the newest boss here threw away the page the
		-- roll had just selected -- the announced item "wasn't in the list" because
		-- the window had been dragged to another boss tab.
		if force and not pendingBossIdx then
			win._jumpNewest = true; pendingJumpNewest = false
			win.userCleared = false   -- new loot -> auto-select it even if you'd cleared
		end
		pendingBossIdx = nil; pendingItemScroll = nil
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

-- A roll just opened. Pop the window, and rebuild it ONLY if the buttons it should
-- carry have changed: the "Your roll" pair only exists while a chat roll-off is
-- plausible, and a plain Refresh repaints the list without re-deciding the body -- so
-- a raider would watch rolls come in with no way to roll himself.
--
-- Gated on the FLAG, not on the event: onRoll fires for every captured roll, and a full
-- Rebuild per roll is 25 rebuilds in a 25-man roll-off (the shape of the raid lag).
local lastChatRoll = nil
function RM.OnRollOpen()
	popOrRefresh(false)
	if not (win and win:IsShown()) then return end
	local now = wantsChatRollButtons()
	if now == lastChatRoll then return end
	lastChatRoll = now
	local ok, err = pcall(RM.Rebuild)
	if not ok and Okanvil.Err then Okanvil:Err("RollMgr OnRollOpen", err) end
end

-- a loot window just opened with items in front of us -> always pop (forced).
function RM.OnLootWindow() popOrRefresh(true) end

-- The loot window opened or closed, so "Award top roll" may have just changed
-- between handing the item over and only recording it. Cheap: relabels one button.
function RM.SyncAward()
	if RM._awardBtn and RM._awardBtn.SyncLabel then
		local ok, err = pcall(RM._awardBtn.SyncLabel)
		if not ok and Okanvil.Err then Okanvil:Err("RollMgr SyncAward", err) end
	end
end

-- Is the mini roll on screen?  The council's test mode watches this: a test
-- lasts as long as its windows, and this is one of the three.
function RM.IsOpen()
	return (win and win:IsShown()) and true or false
end

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

-- This file has no plugin key of its own: the roll manager is part of the Loot
-- module, so it answers to the same switch. Without this it announced master
-- looter changes in chat and kept its callbacks live with Loot switched off --
-- a module that has no nav row is easy to forget when the gate goes in.
local function lootOn()
	return not (Okanvil.ModuleActive and not Okanvil:ModuleActive("__loot"))
end

ev:SetScript("OnEvent", function(_, event)
	-- PLAYER_LOGIN still runs with the module off: it only WIRES the callbacks,
	-- and each of them checks the gate when it fires. Skipping it would leave
	-- the roll manager permanently dead for anyone who enabled Loot later in
	-- the session.
	if event ~= "PLAYER_LOGIN" then
		if lootOn() then mlChanged() end
		return
	end
	if not Okanvil.Loot then return end
	L = Okanvil.Loot
	lastML = isML()
	lastMethod = isMLMethod()
	-- chain onto Loot's callbacks without clobbering them. Each checks the gate
	-- as it fires, so the chain can be wired once at login and still stay quiet
	-- while the module is off.
	local prevLoot = L.onLoot
	L.onLoot = function() if prevLoot then prevLoot() end; if lootOn() then onLoot() end end
	L.onRoll = function() if lootOn() then RM.OnRollOpen() end end
	-- a roll just STARTED on an item id -> page to it and select it (no tab hunting)
	L.onRollStart = function(id)
		if not lootOn() then return end
		local ok, err = pcall(RM.SelectItemById, id)
		if not ok and Okanvil.Err then Okanvil:Err("RollMgr SelectItemById", err) end
	end
	-- fired the instant a loot window opens with items (RaidRoll / RCLootCouncil
	-- model) -- pop the mini roll even if the item is filtered from recording, and
	-- regardless of the InLiveRun timing race (we KNOW a corpse is open).
	local prevWin = L.onLootWindow
	L.onLootWindow = function()
		if prevWin then prevWin() end
		if lootOn() then RM.OnLootWindow() end
	end
end)

SLASH_OKROLL1 = "/okroll"
SlashCmdList["OKROLL"] = function(msg)
	if not lootOn() then
		Okanvil:Print("|cff8a8d93The Loot module is switched off.|r")
		return
	end
	-- /okroll stop -- ends the open roll. The Stop button is gone from the window
	-- (four buttons in a 270px row were unreadable), so this is how a roll called
	-- by mistake is closed.
	if (msg or ""):match("^%s*(%a*)"):lower() == "stop" then
		if L and L.StopRoll then L.StopRoll() end
		return
	end
	RM.Toggle()
end
