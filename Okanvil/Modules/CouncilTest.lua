-- ============================================================
-- Okanvil -- Council foundation test harness.  TEMPORARY.
--
-- This file exists to prove the two pieces the loot council is built on, in
-- game, BEFORE any council UI exists:
--
--   /okask          -- the Comms.Ask/Answer round trip (Core/Comms.lua)
--   /okprof         -- the proficiency filter (Modules/Proficiency-Data.lua)
--
-- Both are pure checks: nothing here touches loot, sessions, master loot or
-- SavedVariables. Delete this file (and its .toc line) once the council module
-- ships -- it is scaffolding, not a feature.
--
-- WHY IT EXISTS AT ALL: the wire is where this addon has failed silently in the
-- past, and a half-arriving council round during ICC is worse than none. Ten
-- minutes with these two commands is the cheap version of that lesson.
-- ============================================================

local Okanvil = Okanvil
local C = Okanvil.Comms

local function say(msg) Okanvil:Print("|cffe0b860[test]|r " .. msg) end

-- The council is a switchable module (Settings > Modules). Off means OFF: no
-- comms answers, no popups, and the proficiency tables released. Everything
-- below returns early when it is disabled rather than half-working.
local function councilOn()
	if Okanvil.Prof and Okanvil.Prof.SyncEnabled then return Okanvil.Prof.SyncEnabled() end
	return not Okanvil.ModuleActive or Okanvil:ModuleActive("__council")
end

-- Keep the tables in step with the switch: on login, and again whenever the
-- Modules page flips it. SetModuleEnabled has no callback, so we re-check on the
-- events that follow a flip AND lazily in each command below.
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function()
		if Okanvil.Prof and Okanvil.Prof.SyncEnabled then Okanvil.Prof.SyncEnabled() end
	end)
end

-- ------------------------------------------------------------
-- /okask -- ask the group a question and print who answered.
--
-- Every client running this build replies with its class and whether it could
-- use the item you asked about, which is exactly the shape stage 1b needs.
-- Solo, Comms.Ask falls back to its loopback path so this still runs.
-- ------------------------------------------------------------
if C and C.Answer then
	C.Answer("TESTASK", function(sender, payload)
		-- A disabled council answers nothing at all -- not even "not eligible".
		-- Silence here is correct: the asker's roster check reports us the same way
		-- it reports someone with no Okanvil, which is exactly what we are.
		if not councilOn() then return nil end
		-- payload is an item link (or ""), the question being "can you use this?"
		local class = select(2, UnitClass("player")) or "?"
		if payload and payload ~= "" and Okanvil.Prof then
			local ok, why = Okanvil.Prof.CanIUse(payload)
			return class .. ":" .. (ok and "yes" or ("no/" .. tostring(why or "?")))
		end
		return class .. ":here"
	end)
end

_G.SLASH_OKASK1 = "/okask"
_G.SlashCmdList["OKASK"] = function(msg)
	if not (C and C.Ask) then say("|cffff5555Comms.Ask missing|r"); return end
	if not councilOn() then
		say("Loot Council is |cffff5555OFF|r for this character (Modules list). Nothing was sent.")
		return
	end
	msg = (msg or ""):match("^%s*(.-)%s*$")

	-- An item link pasted after the command turns this into a real eligibility
	-- round; with no argument it is just a "who is out there" ping.
	local link = msg ~= "" and msg or ""
	local inGroup = (GetNumRaidMembers and GetNumRaidMembers() > 0)
		or (GetNumPartyMembers and GetNumPartyMembers() > 0)

	say(("asking%s (%s)..."):format(
		link ~= "" and (" about " .. link) or "",
		inGroup and "group" or "|cffe0b860solo loopback|r"))

	local round = C.Ask("TESTASK", link, {
		timeout = 6,
		onReply = function(sender, payload)
			say(("  <- %s = %s"):format(tostring(sender), tostring(payload)))
		end,
		onDone = function(replies)
			local n = 0
			for _ in pairs(replies) do n = n + 1 end
			say(("done: |cff7cfc8a%d|r repl%s"):format(n, n == 1 and "y" or "ies"))
			-- Name anyone in the group who never answered: that is the gap the
			-- council board has to show as "no addon", not as "still thinking".
			if inGroup and C.GroupRoster then
				local missing = {}
				for _, name in ipairs(C.GroupRoster("group")) do
					if replies[name] == nil then missing[#missing + 1] = name end
				end
				if #missing > 0 then
					say("no reply: |cffff5555" .. table.concat(missing, ", ") .. "|r")
				end
			end
		end,
	})
	if not round then say("|cffff5555Ask returned false|r") end
end

-- ------------------------------------------------------------
-- /okprof -- run the proficiency filter against an item, for THIS character or
-- for every class at once. This is the one that catches a bad table entry.
--
--   /okprof [item link]        -- can I use it?
--   /okprof all [item link]    -- which of the ten classes can?
-- ------------------------------------------------------------
local ALL_CLASSES = {
	"WARRIOR", "PALADIN", "DEATHKNIGHT", "HUNTER", "SHAMAN",
	"ROGUE", "DRUID", "PRIEST", "MAGE", "WARLOCK",
}

_G.SLASH_OKPROF1 = "/okprof"
_G.SlashCmdList["OKPROF"] = function(msg)
	local P = Okanvil.Prof
	if not P then say("|cffff5555Proficiency-Data not loaded|r"); return end
	if not councilOn() then
		say("Loot Council is |cffff5555OFF|r -- the proficiency tables are released, "
			.. "so every item would answer \"can use\". Switch it on in Modules to test.")
		return
	end
	msg = (msg or ""):match("^%s*(.-)%s*$")

	local all = false
	if msg:lower():sub(1, 3) == "all" then all = true; msg = msg:sub(4):match("^%s*(.-)%s*$") end
	if msg == "" then
		say("usage: /okprof [item link]   or   /okprof all [item link]")
		return
	end

	-- Report what the client actually knows about the item: an uncached item is
	-- the single most likely reason for a surprising answer, and the filter is
	-- deliberately permissive there.
	local name, _, _, _, _, iType, iSub, _, equip = GetItemInfo(msg)
	if not name then
		say("|cffe0b860not cached|r -- the filter will allow it (open the tooltip once, then retry)")
	else
		say(("%s |cff8a8d93%s / %s / %s|r"):format(msg, tostring(iType), tostring(iSub), tostring(equip)))
		local eng = P.Subtype(iSub)
		say(("subtype resolves to: %s"):format(eng and ("|cff7cfc8a" .. eng .. "|r") or "|cffff5555(unknown)|r"))
	end

	if not all then
		local ok, why = P.CanIUse(msg)
		say(("you (%s): %s"):format(
			select(2, UnitClass("player")) or "?",
			ok and "|cff7cfc8aCAN USE|r" or ("|cffff5555no|r (" .. tostring(why or "?") .. ")")))
		return
	end

	local yes, no = {}, {}
	for _, cls in ipairs(ALL_CLASSES) do
		local ok = P.CanUse(msg, cls)
		if ok then yes[#yes + 1] = cls else no[#no + 1] = cls end
	end
	say("can use: |cff7cfc8a" .. (#yes > 0 and table.concat(yes, ", ") or "(none)") .. "|r")
	say("cannot:  |cffff5555" .. (#no > 0 and table.concat(no, ", ") or "(none)") .. "|r")
end
