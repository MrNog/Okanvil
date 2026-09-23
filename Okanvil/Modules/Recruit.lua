-- ============================================================
-- Recruit  (WotLK 3.3.5a)
-- Generic guild-recruitment advertiser: auto-advertise, keyword auto-invite and
-- a list of keyword auto-replies ("?discord" -> the link) that fire independently
-- of the invite, each with its own on/off.
-- Guild name is configurable (default "Guild"); use {guild} in any
-- message and it is replaced with the guild name at send time.
-- Three pills: Message (what you post and what gets answered), Inbox (who
-- whispered, what they were sent, and a way back to each of them) and Setup (who
-- gets invited, filters, toast).
-- A native Okanvil module (no standalone window / minimap).
-- ============================================================

-- Native Okanvil module (lives in the host folder). ADDON is only the module
-- key registered in Okanvil_Plugins / IsModuleEnabled -- NOT a separate addon.
local ADDON = "Okanvil-Recruit"
local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

-- ------------------------------------------------------------
-- Saved-variable defaults -- NO pre-filled text (the user inserts it all).
-- ------------------------------------------------------------
local defaults = {
	guildName = "Guild", -- used by the {guild} token and the join toast
	message = "",
	-- The ADVERTISE text is empty (it is the guild's own words), but these two
	-- lists are not guild-specific at all -- every recruiter wants the same
	-- trigger words and the same scam filter, and leaving them blank meant
	-- auto-invite silently did nothing until you guessed what to type.
	keywords = "inv, invite, join, guild, raid, recruit, lf guild",
	-- Whispers that must NEVER trigger an invite or a reply: gold sellers,
	-- boosting services and anything carrying a link.
	blacklist = "gold, sell, selling, buy, boost, carry, gdkp, swipe, powerlevel, http, www, .com",
	-- Auto-replies: a list of { keywords, text, enabled }. Independent of the
	-- invite -- answering "what's the discord?" must not also invite the asker.
	replies = {},
	-- What an invited player hears. This is the ONE line that goes out with an
	-- invite, in place of any auto-reply: someone who asked to join and was
	-- invited does not also want to be told you are away.
	welcome = "Invite sent, welcome! Raids, signups & info are on our Discord -- an officer will get to you there.",
	-- Only answer while advertising is ON. Off a recruiting session (running a
	-- pug, raiding) the module stays quiet.
	repliesNeedActive = true,
	-- Never answer someone already in your party/raid: the pug next to you asking
	-- for Discord gets a human answer, not a canned one.
	repliesSkipGroup = true,
	-- Per-name whisper conversations, read by the Inbox tab.
	contacts = {},
	replyCooldown = 600,
	inviteCooldown = 300,
	active = false,
	autoInvite = true,
	toastOnJoin = true, -- pop a toast when someone joins the guild
	toastOnlyActive = false, -- ...only while advertising is ON (false = always)
	filterGuild = true,
	filterGroup = true,
	filterFriends = true,
	-- per-channel spam interval in seconds (0 = off). All off by default.
	channelIntervals = { Global = 0, LookingForGroup = 0, General = 0 },
	customChannel = "",
	customInterval = 0,
	log = {},
	session = {}, -- per-name recruiting tally (uncapped); cleared from the Summary tab
}

local db
local chElapsed = {} -- per-channel advertise timer accumulators
local recentInvites = {}
local repliedTo = {}

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------
local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffF1C40F[Recruit]|r " .. tostring(msg))
end

-- guild name with a safe fallback (never empty)
local function gname()
	return (db and db.guildName and db.guildName ~= "" and db.guildName) or "Guild"
end

-- replace the {guild} token with the configured guild name
local function brand(s)
	if not s or s == "" then
		return s
	end
	return (s:gsub("{guild}", gname()))
end

local function stripRealm(name)
	if not name then
		return name
	end
	local n = strsplit("-", name)
	return n
end

-- best-effort real class lookup (self / group / guild roster); nil if unknown
local function resolveClass(name)
	if not name or name == "" then
		return nil
	end
	if name == UnitName("player") then
		return select(2, UnitClass("player"))
	end
	local raidN = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	if raidN > 0 then
		for i = 1, raidN do
			if UnitName("raid" .. i) == name then
				return select(2, UnitClass("raid" .. i))
			end
		end
	else
		local partyN = (GetNumPartyMembers and GetNumPartyMembers()) or 0
		for i = 1, partyN do
			if UnitName("party" .. i) == name then
				return select(2, UnitClass("party" .. i))
			end
		end
	end
	if IsInGuild and IsInGuild() then
		local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
		for i = 1, total do
			local gn = GetGuildRosterInfo(i)
			if gn then
				gn = strsplit("-", gn)
				if gn == name then
					return select(11, GetGuildRosterInfo(i))
				end
			end
		end
	end
	return nil
end

-- Is this whisper one of OUR auto-replies coming back to us? Every rule's text is
-- checked, not just the one that would fire now -- a rule turned off a second ago
-- can still have its answer in flight.
local function isOwnReply(msg)
	if not msg or msg == "" then return false end
	for _, r in ipairs(db.replies or {}) do
		if r.text and r.text ~= "" and brand(r.text) == msg then return true end
	end
	return false
end

-- In my party or raid right now. Separate from the filterGroup setting: that one
-- silences the module entirely for group members, this one only gates the canned
-- replies, and both can be on.
local function isInMyGroup(name)
	if not name then return false end
	local raidN = (GetNumRaidMembers and GetNumRaidMembers()) or 0
	if raidN > 0 then
		for i = 1, raidN do
			if UnitName("raid" .. i) == name then return true end
		end
		return false
	end
	local partyN = (GetNumPartyMembers and GetNumPartyMembers()) or 0
	for i = 1, partyN do
		if UnitName("party" .. i) == name then return true end
	end
	return false
end

-- ------------------------------------------------------------
-- Conversations -- what the Inbox tab reads.
-- One entry per person, holding their lines and ours interleaved, so the window
-- shows a conversation rather than a list of their whispers with our answers
-- missing. Capped per person: a recruiting session runs for hours.
-- ------------------------------------------------------------
local MAX_LOG_LINES = 30

local function contactOf(name, classFile)
	db.contacts = db.contacts or {}
	local c = db.contacts[name]
	if not c then
		c = { name = name, log = {}, unread = 0 }
		db.contacts[name] = c
	end
	if classFile then c.class = classFile end
	return c
end

function Rec_LogIncoming(name, msg, classFile)
	if not (name and msg and msg ~= "") then return end
	local c = contactOf(name, classFile)
	c.log[#c.log + 1] = { them = true, msg = msg, t = time() }
	while #c.log > MAX_LOG_LINES do table.remove(c.log, 1) end
	c.unread = (c.unread or 0) + 1
	c.t = time()
end

function Rec_LogOutgoing(name, msg)
	if not (name and msg and msg ~= "") then return end
	local c = db.contacts and db.contacts[name]
	if not c then return end
	c.log[#c.log + 1] = { them = false, msg = msg, t = time() }
	while #c.log > MAX_LOG_LINES do table.remove(c.log, 1) end
	c.t = time()
end

-- Send a whisper AND record it, so a reply typed in the window can never land in
-- chat without showing up in the conversation that sent it.
function Rec_Whisper(name, msg)
	if not (name and msg and msg ~= "") then return end
	SendChatMessage(msg, "WHISPER", nil, name)
	Rec_LogOutgoing(name, msg)
end

-- Conversations, newest first -- the window orders by who spoke last.
function Rec_ContactList()
	local out = {}
	for _, c in pairs((db and db.contacts) or {}) do out[#out + 1] = c end
	table.sort(out, function(x, y) return (x.t or 0) > (y.t or 0) end)
	return out
end

function Rec_UnreadCount()
	local n = 0
	for _, c in pairs((db and db.contacts) or {}) do
		if (c.unread or 0) > 0 then n = n + 1 end
	end
	return n
end

-- skip people we already know / are playing with (toggle each in Filters tab)
local function isKnownContact(name)
	if not name then
		return false
	end
	if db.filterGroup then
		local raidN = (GetNumRaidMembers and GetNumRaidMembers()) or 0
		if raidN > 0 then
			for i = 1, raidN do
				if UnitName("raid" .. i) == name then
					return true
				end
			end
		else
			local partyN = (GetNumPartyMembers and GetNumPartyMembers()) or 0
			for i = 1, partyN do
				if UnitName("party" .. i) == name then
					return true
				end
			end
		end
	end
	if db.filterFriends then
		local nf = (GetNumFriends and GetNumFriends()) or 0
		for i = 1, nf do
			local fname = GetFriendInfo(i)
			if fname then
				fname = strsplit("-", fname)
				if fname == name then
					return true
				end
			end
		end
	end
	if db.filterGuild and IsInGuild and IsInGuild() then
		local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
		for i = 1, total do
			local gn = GetGuildRosterInfo(i)
			if gn then
				gn = strsplit("-", gn)
				if gn == name then
					return true
				end
			end
		end
	end
	return false
end

-- is this name currently in MY guild? (used to hide the re-invite button)
local function isInMyGuild(name)
	if not (IsInGuild and IsInGuild()) then
		return false
	end
	local total = (GetNumGuildMembers and GetNumGuildMembers()) or 0
	for i = 1, total do
		local gn = GetGuildRosterInfo(i)
		if gn then
			gn = strsplit("-", gn)
			if gn == name then
				return true
			end
		end
	end
	return false
end

-- parse guild join/decline system messages to track an invite's outcome
local function makePattern(fmt)
	local p = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
	return (p:gsub("%%s", "(.+)"))
end
local PAT_JOIN = ERR_GUILD_JOIN_S and makePattern(ERR_GUILD_JOIN_S)
local PAT_DECLINE = ERR_GUILD_DECLINE_S and makePattern(ERR_GUILD_DECLINE_S)
local PAT_FAILS = {}
do
	local function addFail(g)
		if g and g:find("%%s") then
			PAT_FAILS[#PAT_FAILS + 1] = makePattern(g)
		end
	end
	addFail(ERR_ALREADY_IN_GUILD_S)
	addFail(ERR_ALREADY_INVITED_TO_GUILD_S)
end
local PAT_OFFLINE = ERR_GUILD_PLAYER_NOT_FOUND_S
	and ERR_GUILD_PLAYER_NOT_FOUND_S:find("%%s")
	and makePattern(ERR_GUILD_PLAYER_NOT_FOUND_S)
local PAT_FRIEND_ONLINE = ERR_FRIEND_ONLINE_SS and makePattern(ERR_FRIEND_ONLINE_SS)

local function setInviteState(name, state)
	db.session[name] = db.session[name] or {}
	db.session[name].state = state
	for i = 1, #db.log do
		local e = db.log[i]
		if e.who == name then
			e.state = state
			break
		end
	end
	if Rec_RefreshWhispers then Rec_RefreshWhispers() end
end

-- resolve a configured channel name to the numeric id THIS player has for it.
local function resolveChannelId(name)
	if not name or name == "" then
		return nil
	end
	local asNum = tonumber(name)
	if asNum then
		return asNum
	end
	local id = GetChannelName(name)
	if id and id > 0 then
		return id
	end
	local list = { GetChannelList() } -- id1, name1, id2, name2, ...
	local target = name:lower()
	for i = 1, #list - 1, 2 do -- exact match first
		if type(list[i + 1]) == "string" and list[i + 1]:lower() == target then
			return list[i]
		end
	end
	for i = 1, #list - 1, 2 do -- then prefix ("General" -> "General - Dalaran")
		if type(list[i + 1]) == "string" and list[i + 1]:lower():find(target, 1, true) == 1 then
			return list[i]
		end
	end
	return nil
end

local function SendToChannel(name, msg)
	if not name or not msg or msg == "" then
		return
	end
	if name == "GUILD" then
		SendChatMessage(msg, "GUILD")
		return
	end
	local id = resolveChannelId(name)
	if id and id > 0 then
		SendChatMessage(msg, "CHANNEL", nil, id)
	end
end

-- ------------------------------------------------------------
-- Core engine
-- ------------------------------------------------------------
local core = CreateFrame("Frame")

core:SetScript("OnUpdate", function(self, e)
	if not db or not db.active then
		return
	end
	-- The OnEvent handler on this same frame gates; this one did not, so a
	-- disabled Recruit kept advertising to every channel it was set up for.
	-- Same omission as PuG's spam loop: a module with two script handlers gets
	-- the gate on one of them.
	if Okanvil.ModuleActive and not Okanvil:ModuleActive(ADDON) then
		return
	end
	if not db.message or db.message == "" then
		return -- nothing to advertise until the user writes a message
	end
	-- each channel advertises on its own interval (staggered)
	for name, iv in pairs(db.channelIntervals) do
		if iv and iv > 0 then
			chElapsed[name] = (chElapsed[name] or 0) + e
			if chElapsed[name] >= iv then
				chElapsed[name] = 0
				SendToChannel(name, brand(db.message))
			end
		end
	end
	if db.customChannel ~= "" and (db.customInterval or 0) > 0 then
		chElapsed.__custom = (chElapsed.__custom or 0) + e
		if chElapsed.__custom >= db.customInterval then
			chElapsed.__custom = 0
			SendToChannel(db.customChannel, brand(db.message))
		end
	end
end)

core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
core:RegisterEvent("CHAT_MSG_WHISPER")
core:RegisterEvent("CHAT_MSG_SYSTEM")

core:SetScript("OnEvent", function(self, event, arg1, arg2)
	-- Recruit is now a NATIVE module of Okanvil (it lives in the host folder and is
	-- loaded by Okanvil.toc, so Okanvil.W is always present). It initialises on the
	-- HOST's ADDON_LOADED -- there's no separate "Okanvil-Recruit" addon anymore.
	if event == "ADDON_LOADED" and arg1 == "Okanvil" then
		RecruitDB = RecruitDB or {}
		for k, v in pairs(defaults) do
			if RecruitDB[k] == nil then
				if type(v) == "table" then
					RecruitDB[k] = {}
					for kk, vv in pairs(v) do
						RecruitDB[k][kk] = vv
					end
				else
					RecruitDB[k] = v
				end
			end
		end
		db = RecruitDB
		-- Kept across a reload, like the PuG advert: the whisper catcher is
		-- switched on for a recruiting night, not for a session, and a reload
		-- in the middle of one should not quietly stop answering applicants.
		-- The single auto-reply (and the AFK one) became the first entries in the
		-- rules list. Carry whatever text was configured across rather than
		-- silently dropping it, then clear the old keys so this runs once.
		db.replies = db.replies or {}
		db.contacts = db.contacts or {}
		if db.reply and db.reply ~= "" then
			table.insert(db.replies, { text = db.reply, enabled = true })
		end
		if db.afkReply and db.afkReply ~= "" then
			table.insert(db.replies, { text = db.afkReply, enabled = false })
		end
		db.reply, db.afkReply, db.afkMode = nil, nil, nil

		-- Drop a rule's own keyword list when it is just a copy of the invite
		-- keywords, which is what this migration used to put there. Leaving it
		-- would freeze that rule on the old words: editing the list on Setup
		-- would move the invites and leave the reply behind.
		for _, r in ipairs(db.replies) do
			if r.keywords and (r.keywords == "" or r.keywords == db.keywords) then
				r.keywords = nil
			end
		end
		if GuildRoster then
			GuildRoster()
		end
		-- register as a Okanvil plugin (Okanvil builds it lazily into its panel)
		Okanvil_Plugins = Okanvil_Plugins or {}
		Okanvil_Plugins[ADDON] = {
			title = "Recruit",
			desc = "Recruitment/pug advertiser with auto-reply and auto-invite. For officers & pug leaders.",
			icon = (Okanvil.ICONS and Okanvil.ICONS.recruit) or "Interface\\Icons\\Ability_Warrior_BattleShout",
			build = function(panel)
				Rec_BuildUI(panel)
			end,
			refresh = function()
				Rec_RefreshUI()
			end,
		}
		return
	end

	if event == "PLAYER_LOGIN" then
		if not db then
			return
		end
		-- native module: always hosted. Okanvil builds the UI lazily when you open
		-- the Recruit tab (and Modules lets you toggle it off).
		if Okanvil and Okanvil.Register then
			Okanvil:Register(ADDON)   -- silent; /recruit still opens it
		end

		-- Say it is still catching. The switch now survives a reload, and a
		-- catcher answering applicants you have forgotten about is worse than
		-- one line in chat.
		if db.active then
			Okanvil:Print("|cffe0b860Recruit is still catching whispers.|r")
		end
		return
	end

	-- Modulo Recruit DESLIGADO = nao responde a whispers nem reage a chat.
	if Okanvil.ModuleActive and not Okanvil:ModuleActive(ADDON) then return end

	if event == "CHAT_MSG_WHISPER" then
		-- ONLY while advertising.
		--
		-- This used to log every whisper whatever the switch said, on the grounds
		-- that turning the spam off should not stop the replies. What it actually
		-- did was fill the Whispers list with people answering a PUG advert --
		-- "rsham 5k1", "mm hunter? 5.3 gs" -- who never wanted a guild and were
		-- never going to be invited to one.
		--
		-- The reply rules keep their own "only while advertising" guard, so this
		-- takes nothing away from them that they were not already refusing.
		local msg, sender = arg1, arg2
		if not sender then
			return
		end
		if not db.active then
			return
		end
		local clean = stripRealm(sender)
		if isOwnReply(msg) then
			return -- ignore our own auto-reply echoing back
		end
		if isKnownContact(clean) then
			return -- guildies / party / friends: ignore entirely
		end

		local ctx = {
			known = false,
			now = GetTime(),
			lastInvite = recentInvites[clean],
			lastReply = repliedTo[clean],
			isEcho = false,
			active = db.active,
			inGroup = isInMyGroup(clean),
		}
		local decision = RecruitLogic.decide(db, msg, ctx)
		local sentReply, didInvite = nil, false
		if decision.invite then
			recentInvites[clean] = ctx.now
			GuildInvite(clean)
			didInvite = true
			Print("Guild-invited |cff00ff00" .. clean .. "|r.")
		end
		if decision.reply then
			repliedTo[clean] = ctx.now
			sentReply = brand(decision.reply)
			SendChatMessage(sentReply, "WHISPER", nil, sender)
		end

		-- Feed the Inbox: their line, then ours if we answered.
		local classFile = resolveClass(clean)
		Rec_LogIncoming(clean, msg, classFile)
		if sentReply then Rec_LogOutgoing(clean, sentReply) end

		db.session[clean] = db.session[clean] or {}
		if didInvite then
			db.session[clean].invited = true
		end
		if sentReply then
			db.session[clean].replied = true
		end

		local wasBlocked = db.blacklist and db.blacklist ~= ""
			and RecruitLogic.matchList(msg, db.blacklist) or nil
		table.insert(db.log, 1, { who = clean, msg = msg or "", inv = didInvite, state = (didInvite and "sent" or nil), reply = sentReply, blocked = wasBlocked, class = classFile, t = date("%H:%M"), ts = time() })
		while #db.log > 50 do
			table.remove(db.log)
		end
		if Rec_RefreshWhispers then Rec_RefreshWhispers() end
	end

	if event == "CHAT_MSG_SYSTEM" and db then
		local m = arg1 or ""
		if PAT_JOIN then
			local who = m:match(PAT_JOIN)
			if who then
				who = stripRealm(who)
				setInviteState(who, "joined")
				if db.toastOnJoin and (not db.toastOnlyActive or db.active) then
					Rec_ShowToast(who, resolveClass(who))
				end
				return
			end
		end
		if PAT_DECLINE then
			local who = m:match(PAT_DECLINE)
			if who then
				setInviteState(stripRealm(who), "declined")
				return
			end
		end
		if PAT_OFFLINE then
			local who = m:match(PAT_OFFLINE)
			if who then
				setInviteState(stripRealm(who), "offline")
				return
			end
		end
		if PAT_FRIEND_ONLINE then
			local who = m:match(PAT_FRIEND_ONLINE)
			if who then
				who = stripRealm(who)
				local s = db.session[who]
				if s and s.watch then
					s.watch = nil
					Rec_ShowToast(who, resolveClass(who), "|cff66ddffOnline now -- re-invite!|r")
				end
				return
			end
		end
		for _, p in ipairs(PAT_FAILS) do
			local who = m:match(p)
			if who then
				setInviteState(stripRealm(who), "failed")
				return
			end
		end
	end
end)

-- ------------------------------------------------------------
-- SHARE THE ADVERTISE LINE with the other officers.
--
-- Four officers recruiting with four slightly different messages is how a guild
-- ends up advertising two different raid nights. Same shape as the notes sync:
-- officer-gated on BOTH ends, because it overwrites what the receiver has.
--
--   RECMSG | <text>     guild channel, officers only
--
-- Trust is by ROLE, checked on receipt -- the prefix proves nothing, so the
-- receiver re-asks "is this sender actually an officer?" before taking it.
-- ------------------------------------------------------------
local function recruitSyncAllowed(who)
	if Okanvil.ModuleActive and not Okanvil:ModuleActive(ADDON) then return false end
	local U = Okanvil.U
	return U and U.isOfficer and U.isOfficer(who or UnitName("player"))
end

function Rec_ShareMessage()
	local C = Okanvil.Comms
	if not C then return end
	if not recruitSyncAllowed() then
		Okanvil:Print("|cffff5555Recruit:|r officers only.")
		return
	end
	local msg = db.message or ""
	if msg == "" then
		Okanvil:Print("|cffff5555Recruit:|r nothing to share -- write the advertise line first.")
		return
	end
	if not (IsInGuild and IsInGuild()) then
		Okanvil:Print("|cffff5555Recruit:|r you are not in a guild.")
		return
	end
	-- One message: an advertise line is ~200 bytes and C.Send caps at 240. A
	-- longer one is refused rather than arriving truncated, which would leave
	-- every other officer spamming half a sentence.
	local ok = C.SendGuild and C.SendGuild("RECMSG", msg)
	if ok then
		Okanvil:Print("|cff7cfc8aRecruit:|r message sent to the other officers.")
	else
		Okanvil:Print("|cffff5555Recruit:|r could not send -- the message may be too long.")
	end
end

if Okanvil.Comms then
	Okanvil.Comms.On("RECMSG", function(sender, text)
		if not text or text == "" then return end
		if sender == (UnitName and UnitName("player")) then return end   -- our own echo
		-- The SENDER must be an officer, checked here rather than trusted from the
		-- wire: anyone can put a prefix on an addon message.
		if not recruitSyncAllowed(sender) then return end
		if not recruitSyncAllowed() then return end        -- and so must we
		if db.message == text then return end
		db.message = text
		Okanvil:Print(("|cffe0b860Recruit:|r advertise message updated by |cffffd200%s|r."):format(
			tostring(sender)))
		-- Repaint the box if the page is open, so the new text is visible rather
		-- than only taking effect on the next spam.
		local rf = RecruitFrame
		if rf and rf.msg and rf.msg.SetText then pcall(rf.msg.SetText, rf.msg, text) end
	end)
end

function Rec_ToggleActive(state)
	if state == nil then
		state = not db.active
	end
	db.active = state
	chElapsed = {}
	if db.active then
		-- MUTUAL EXCLUSION with the Invite module's keyword-invite: both grab the
		-- same "inv" whisper, so only one runs. Turning Recruit ON stands it down.
		if Okanvil and Okanvil.Invite and Okanvil.Invite.KeywordEnabled
			and Okanvil.Invite.KeywordEnabled() then
			Okanvil.Invite.SetKeywordEnabled(false)
			Print("Invite keyword-invite turned OFF (can't share the invite keyword).")
		end
		-- Post ONCE right away, then start the interval. Waiting a full cycle before
		-- the first line makes the button look dead -- 60s of silence after pressing
		-- START reads as "it did nothing" -- and the leader who just turned it on
		-- wants the message out now.
		local msg = brand(db.message)
		if msg and msg ~= "" then
			for name, iv in pairs(db.channelIntervals) do
				if iv and iv > 0 then SendToChannel(name, msg) end
			end
			if db.customChannel ~= "" and (db.customInterval or 0) > 0 then
				SendToChannel(db.customChannel, msg)
			end
		end
		-- then stagger the repeats so the channels never fire on the same tick
		local i = 0
		for name, iv in pairs(db.channelIntervals) do
			if iv and iv > 0 then
				i = i + 1
				chElapsed[name] = -(i - 1) * 5
			end
		end
	end
	if RecruitFrame then
		Rec_RefreshUI()
	end
	if db.active then
		Print("advertising |cff00ff00ON|r.")
	else
		Print("advertising |cffff5555OFF|r.")
	end
end

-- ============================================================
-- UI
-- ============================================================
local CH_LIST = { "Global", "LookingForGroup", "General" }

local CLASS_COLORS = {
	DEATHKNIGHT = "C41F3B",
	DRUID = "FF7D0A",
	HUNTER = "ABD473",
	MAGE = "69CCF0",
	PALADIN = "F58CBA",
	PRIEST = "FFFFFF",
	ROGUE = "FFF569",
	SHAMAN = "0070DE",
	WARLOCK = "9482C9",
	WARRIOR = "C79C6E",
}
local function nameColor(name, classFile)
	return "|cff" .. ((classFile and CLASS_COLORS[classFile]) or "F1C40F")
end

-- ---- UI helpers: prefer the shared Okanvil.W widgets (gold design system);
-- UI helpers: thin wrappers over the shared Okanvil.W widget layer (the host is
-- always present -- this is a native module, no standalone).
local W = Okanvil.W

-- flat panel backdrop for the few floating frames (toast) that live on UIParent,
-- not inside a W.Dashboard. Extra args are ignored -- Okanvil:Skin owns the look.
local function flatBackdrop(frame) Okanvil:Skin(frame, "input") end

-- single-line edit box; returns the EditBox (with .bd = the bordered frame) so
-- existing call-sites (SetText/GetText/hooks) keep working.
local function makeBox(parent, name, x, y, w, h)
	local box = W.EditBox(parent)
	box:SetSize(w, h); box:SetPoint("TOPLEFT", x, y)
	local e = box.edit
	e.bd = box
	return e
end

-- responsive multi-line box: stretches to the parent's right edge (minus rightMargin)
local function makeScrollBox(parent, name, x, y, rightMargin, h)
	local box = W.MultiEdit(parent)
	box:SetPoint("TOPLEFT", x, y)
	box:SetPoint("RIGHT", parent, "RIGHT", -(rightMargin or 12), 0)
	box:SetHeight(h)
	local e = box.edit
	e.bd = box
	return e
end

-- checkbox bound to a db key; W.Check reads/writes via getFn/setFn. onChange(v)
-- runs after a toggle. Returns a frame with SetChecked/GetChecked shims so the
-- existing Rec_RefreshUI (which calls :SetChecked) keeps working.
local function makeCheck(parent, key, label, x, y, onChange)
	local c = W.Check(parent, label,
		function() return db[key] end,
		function(v) db[key] = v and true or false; if onChange then onChange(v) end end)
	c:SetPoint("TOPLEFT", x, y)
	c.SetChecked = function(_, v) db[key] = v and true or false; c.refresh() end
	c.GetChecked = function() return db[key] end
	return c
end

local function numHook(box, key, lo, hi)
	box:SetScript("OnEditFocusLost", function(s)
		local v = tonumber(s:GetText())
		if v then
			db[key] = math.max(lo, math.min(hi, math.floor(v)))
		end
		s:SetText(db[key])
		if s.bd then
			s.bd:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
		end
	end)
end

local function strHook(box, key)
	box:SetScript("OnEditFocusLost", function(s)
		db[key] = (s:GetText() or ""):gsub("\n", " ")
		if s.bd then
			s.bd:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
		end
		-- The Message tab prints the invite keywords, because the replies answer
		-- them. Edit them here and that line has to follow, or the two tabs
		-- disagree until the window is reopened.
		if key == "keywords" and Rec_ApplyMessage then Rec_ApplyMessage() end
	end)
end

-- ============================================================
-- "New member!" toast -- pops when someone joins the guild
-- ============================================================
local toast
local function Rec_ApplyToastPoint()
	if not toast then
		return
	end
	toast:ClearAllPoints()
	local p = db.toastPoint
	if p and p.point then
		toast:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
	else
		toast:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -180)
	end
end

local function Rec_BuildToast()
	if toast then
		return
	end
	local t = CreateFrame("Frame", "Recruit_Toast", UIParent)
	t:SetSize(236, 56)
	t:SetFrameStrata("FULLSCREEN_DIALOG")
	flatBackdrop(t, 0.09, 0.09, 0.11, 0.96, 0.85, 0.66, 0.2)
	t:EnableMouse(true)
	t:SetMovable(true)
	t:RegisterForDrag("LeftButton")
	t:SetScript("OnMouseDown", function(self)
		if not self.unlocked then
			self:Hide()
		end
	end)
	t:SetScript("OnDragStart", function(self)
		if self.unlocked then
			self:StartMoving()
		end
	end)
	t:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint(1)
		db.toastPoint = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	t:Hide()

	local icon = t:CreateTexture(nil, "ARTWORK")
	icon:SetSize(38, 38)
	icon:SetPoint("LEFT", 9, 0)
	icon:SetTexture((Okanvil.ICONS and Okanvil.ICONS.recruit) or "Interface\\Icons\\Ability_Warrior_BattleShout")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- Kept, so the texture can be set again when the toast is shown. Built
	-- once and never touched, it held whatever ICONS.recruit was at build
	-- time -- change the icon and the toast kept the old one until a reload.
	t.icon = icon

	local top = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	top:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -4)
	t.top = top

	local bottom = t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	bottom:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -4)
	t.bottom = bottom

	t:SetScript("OnUpdate", function(self, e)
		if self.unlocked then
			return
		end
		self.life = (self.life or 0) - e
		if self.life <= 0 then
			self:Hide()
		elseif self.life < 1 then
			self:SetAlpha(self.life)
		end
	end)
	toast = t
	Rec_ApplyToastPoint()
end

function Rec_ShowToast(name, classFile, title)
	if not name then
		return
	end
	Rec_BuildToast()
	if toast.unlocked then
		return
	end
	if toast.icon and Okanvil.ICONS and Okanvil.ICONS.recruit then
		toast.icon:SetTexture(Okanvil.ICONS.recruit)
	end
	toast.top:SetText(title or ("|cffF1C40FNew member joined " .. gname() .. "!|r"))
	toast.bottom:SetText(nameColor(name, classFile) .. name .. "|r")
	toast:SetAlpha(1)
	toast.life = 5
	toast:Show()
	PlaySound("UI_BnetToast")
end

function Rec_SetToastMove(on)
	Rec_BuildToast()
	toast.unlocked = on
	if on then
		toast.top:SetText("|cffF1C40FToast preview|r")
		toast.bottom:SetText("|cff00ff00drag me, untick to lock|r")
		toast:SetAlpha(1)
		toast:Show()
		Print("Toast |cff00ff00unlocked|r -- drag it where you want, then untick to lock.")
	else
		toast:Hide()
		Print("Toast position |cffffcc00locked|r.")
	end
end

function Rec_BuildUI(parent)
	if RecruitFrame then
		return
	end

	-- Okanvil always gives us a content panel (it owns the window chrome).
	local f = parent
	RecruitFrame = f

	-- content region: everything below draws through a shared Dashboard shell
	-- (header + toggleable contacts drawer + config overlays). The X offset just
	-- pads inside each fill frame.
	local X = 4

	local dash = W.Dashboard(f, {
		title = "Recruit",
		icon = (Okanvil.ICONS and Okanvil.ICONS.recruit) or "Interface\\Icons\\Ability_Warrior_BattleShout",
		pills = true,
		drawerWidth = 0,
		footerHeight = 0,
		primaryText = function() return db.active and "STOP advertising" or "START advertising" end,
		onPrimary = function() Rec_ToggleActive() end,
		-- Share the advertise line with the other officers, so the guild spams ONE
		-- message instead of four slightly different ones -- the same reason notes
		-- and the priority ladder sync. Officer-gated both ways: it overwrites what
		-- the receiver has.
		secondaryText = function() return "Share message" end,
		secondaryWidth = 120,
		secondaryShown = function()
			return Okanvil.U and Okanvil.U.isOfficer and Okanvil.U.isOfficer(UnitName("player"))
		end,
		onSecondary = function() Rec_ShareMessage() end,
		-- State, then the night's tally, on one line in the header. The counts used
		-- to sit at the bottom of Setup, which is the one place you are not looking
		-- while a campaign runs -- and they are the whole answer to "is this
		-- working?", so they belong where the ON/OFF is.
		statusText = function()
			local invited, replied, blocked = 0, 0, 0
			for _, v in pairs(db.session or {}) do
				if v.invited or v.state == "sent" or v.state == "joined" then invited = invited + 1 end
				if v.replied then replied = replied + 1 end
			end
			for _, e in ipairs(db.log or {}) do
				if e.blocked then blocked = blocked + 1 end
			end
			local state = db.active and "|cff7cfc8aAdvertising ON|r" or "|cffff5555Advertising OFF|r"
			-- Unread whispers lead: they are the one number here that asks you to
			-- do something, and missing them is how a recruit goes unanswered.
			local unread = Rec_UnreadCount()
			if unread > 0 then
				state = state .. ("   |cffe0b860%d new|r|cff8a8d93 in Inbox|r"):format(unread)
			end
			-- Nothing happened yet: the row of zeroes says less than no row at all.
			if invited + replied + blocked == 0 then return state end
			return ("%s   |cff8a8d93|r |cff7cfc8a%d|r|cff8a8d93 inv|r  |cffe0b860%d|r|cff8a8d93 rep|r  |cffff5555%d|r|cff8a8d93 blk|r")
				:format(state, invited, replied, blocked)
		end,
		tabs = {
			{ key = "message",  label = "Message",  height = 340, build = function(p) Rec_BuildMessage(p) end },
			{ key = "inbox",    label = "Inbox",    height = 200, build = function(p) Rec_BuildInbox(p) end },
			{ key = "setup",    label = "Setup",    height = 640, build = function(p) Rec_BuildSetup(p) end },
		},
	})
	f.dash = dash
	f.toggleBtn = dash.cta

	Rec_RefreshUI()
	return
end

-- ------------------------------------------------------------
-- Layout helpers -- a running y cursor instead of the absolute coordinates the
-- old three tabs used, so inserting a control doesn't mean re-typing every
-- offset below it.
-- ------------------------------------------------------------
local X = 4

local function secHead(p, text, y)
	local fs = W.Text(p, text, "head", "accent")
	fs:SetPoint("TOPLEFT", X, y)
	local line = p:CreateTexture(nil, "ARTWORK")
	line:SetTexture(FLAT)
	line:SetHeight(1)
	line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
	line:SetPoint("RIGHT", p, "RIGHT", -12, 0)
	local c = Okanvil.Colors.border
	line:SetVertexColor(c[1], c[2], c[3], 1)
	return y - 24
end

local function fieldLabel(p, text, y)
	local fs = W.Text(p, text, "label", "dim")
	fs:SetPoint("TOPLEFT", X, y)
	return y - 18
end

-- ---------- PILL 1: Message ----------
-- ONLY what you touch while recruiting: the ad, and the answers. Everything you
-- set once and forget lives on Setup -- a page you have to scroll past is a page
-- you stop reading.
function Rec_BuildMessage(p)
	local f = RecruitFrame
	local y = -8

	-- ---- what you post ----
	y = secHead(p, "ADVERTISE", y)
	f.msg = makeScrollBox(p, "msg", X, y, 12, 52)
	strHook(f.msg, "message")
	y = y - 62

	-- ---- auto-replies ----
	y = secHead(p, "AUTO-REPLIES", y)
	-- Which words these answer is set once, on Setup. Saying so here is what
	-- replaced the per-rule keyword box: the rule editor no longer shows a list,
	-- so without this line there is nothing to tell you where it went.
	f.replyKw = W.Text(p, "", "note", "dim")
	f.replyKw:SetPoint("TOPLEFT", X, y)
	f.replyKw:SetPoint("RIGHT", p, "RIGHT", -12, 0)
	f.replyKw:SetJustifyH("LEFT")
	y = y - 20

	f.cNeedActive = makeCheck(p, "repliesNeedActive", "Only reply while Advertising is ON", X, y)
	y = y - 26
	f.cSkipGroup = makeCheck(p, "repliesSkipGroup", "Never reply to someone in my group or raid", X, y)
	y = y - 28

	f.ruleHost = CreateFrame("Frame", nil, p)
	f.ruleHost:SetPoint("TOPLEFT", X, y)
	f.ruleHost:SetPoint("RIGHT", p, "RIGHT", -12, 0)
	f.ruleHost:SetHeight(1)
	f.ruleRows = {}
	f.ruleAddY = y

	f.addRule = W.Button(p, "+ Add reply", "primary")
	f.addRule:SetSize(96, 22)
	f.addRule:SetScript("OnClick", function()
		db.replies = db.replies or {}
		table.insert(db.replies, { text = "", enabled = true })
		f.editing = #db.replies
		Rec_RenderRules()
	end)

	-- A standing warning, not a one-off print: both modules watch the same
	-- whispers, and the person reading this page is the one who can fix it.
	-- Positioned by Rec_RenderRules, below the rules.
	f.clash = W.Text(p, "", "note")
	f.clash:SetJustifyH("LEFT")

	f.msgPage = p
	Rec_RenderRules()
	Rec_ApplyMessage()
end

-- ---------- PILL 2: Setup ----------
-- Set once, then forgotten: the guild name, where and how often the ad goes out,
-- what counts as an invite keyword, who to skip, and the toast.
function Rec_BuildSetup(p)
	local f = RecruitFrame
	local COL2 = X + 224
	local y = -8

	-- ---- guild ----
	y = secHead(p, "GUILD", y)
	y = fieldLabel(p, "Guild name -- fills {guild} in any message", y)
	f.guildName = makeBox(p, "guildName", X, y, 260, 22)
	strHook(f.guildName, "guildName")
	y = y - 34

	-- ---- channels ----
	y = secHead(p, "WHERE AND HOW OFTEN", y)
	f.chInputs = {}
	local function chHook(box, name)
		box:SetScript("OnEditFocusLost", function(s)
			local v = math.max(0, math.min(3600, math.floor(tonumber(s:GetText()) or 0)))
			db.channelIntervals[name] = v
			s:SetText(v)
			if s.bd then s.bd:SetBackdropBorderColor(0.4, 0.4, 0.45, 1) end
		end)
	end
	local CH_LABELS = { Global = "Global", LookingForGroup = "LFG", General = "General" }
	local cols = { { lx = X, bx = X + 76 }, { lx = COL2, bx = COL2 + 76 } }
	local rowY = y
	for i, name in ipairs(CH_LIST) do
		local col = cols[((i - 1) % 2) + 1]
		local lb = W.Text(p, CH_LABELS[name], "label", "dim")
		lb:SetPoint("TOPLEFT", col.lx, rowY - 4)
		local box = makeBox(p, "iv_" .. name, col.bx, rowY, 52, 22)
		chHook(box, name)
		f.chInputs[name] = box
		if i % 2 == 0 then rowY = rowY - 28 end
	end
	y = rowY - 32

	-- The custom row lines up with the three above it: name where a channel
	-- label sits, interval in the same column as theirs. It used to put its
	-- seconds box at COL2+76 while its name box ran to X+286, so the two sat
	-- nowhere near each other and the number read as unlabelled.
	local cl = W.Text(p, "Custom", "label", "dim")
	cl:SetPoint("TOPLEFT", X, y - 4)
	f.custom = makeBox(p, "custom", X + 76, y, 150, 22)
	strHook(f.custom, "customChannel")
	-- The tooltip goes on the WRAPPER (box.bd), not on the EditBox makeBox hands
	-- back: Tooltip is a W widget method, and calling it on the raw EditBox threw
	-- mid-build. Everything below this line -- keywords, blacklist, cooldowns,
	-- filters, the toast options -- was never created, so the page looked like it
	-- had lost its settings when they were sitting safe in the saved variables.
	if f.custom.bd and f.custom.bd.Tooltip then
		f.custom.bd:Tooltip("A channel you joined yourself -- type its NAME, not its number.")
	end

	local ivl = W.Text(p, "every", "label", "dim")
	ivl:SetPoint("TOPLEFT", X + 234, y - 4)
	f.customIv = makeBox(p, "iv_custom", X + 272, y, 52, 22)
	numHook(f.customIv, "customInterval", 0, 3600)
	y = y - 26

	local ivNote = W.Text(p, "Seconds between posts in each channel. 0 = never post there.",
		"note", "dim")
	ivNote:SetPoint("TOPLEFT", X, y)
	y = y - 30

	-- ---- invite ----
	y = secHead(p, "WHO GETS AN INVITE", y)
	f.cInvite = makeCheck(p, "autoInvite", "Auto-invite people who whisper a keyword", X, y)
	y = y - 30
	y = fieldLabel(p, "Whispers that trigger a guild invite", y)
	f.keywords = makeScrollBox(p, "keywords", X, y, 12, 44)
	strHook(f.keywords, "keywords")
	y = y - 54

	y = fieldLabel(p, "Never invite or reply if the whisper contains", y)
	f.blacklist = makeScrollBox(p, "blacklist", X, y, 12, 44)
	strHook(f.blacklist, "blacklist")
	y = y - 54

	local cdl = W.Text(p, "Invite cooldown (s)", "label", "dim"); cdl:SetPoint("TOPLEFT", X, y - 4)
	f.inviteCd = makeBox(p, "inviteCd", X + 130, y, 52, 22)
	numHook(f.inviteCd, "inviteCooldown", 0, 3600)
	local rcl = W.Text(p, "Reply cooldown (s)", "label", "dim"); rcl:SetPoint("TOPLEFT", COL2, y - 4)
	f.replyCd = makeBox(p, "replyCd", COL2 + 130, y, 52, 22)
	numHook(f.replyCd, "replyCooldown", 0, 3600)
	y = y - 40

	-- ---- who to skip ----
	y = secHead(p, "DON'T BOTHER", y)
	f.fGuild = makeCheck(p, "filterGuild", "Skip guild members", X, y); y = y - 26
	f.fGroup = makeCheck(p, "filterGroup", "Skip people in my party or raid", X, y); y = y - 26
	f.fFriends = makeCheck(p, "filterFriends", "Skip my friends list", X, y); y = y - 34

	-- ---- toast ----
	y = secHead(p, "TOAST", y)
	f.cToast = makeCheck(p, "toastOnJoin", "Pop a toast when someone joins the guild", X, y); y = y - 26
	f.cToastActive = makeCheck(p, "toastOnlyActive", "...only while advertising is ON", X + 18, y); y = y - 26
	f.cToastMove = makeCheck(p, "toastMove", "Move it (drag it, untick to lock)", X, y,
		function(v) Rec_SetToastMove(v) end)
	y = y - 40

	-- ---- history ----
	-- The counts live in the header now, beside the ON/OFF. What is left here is
	-- the button that empties them, which is a thing you do rarely and on purpose.
	y = secHead(p, "HISTORY", y)
	local clr = W.Button(p, "Clear")
	clr:SetSize(60, 22); clr:SetPoint("TOPLEFT", X, y - 4)
	clr:SetScript("OnClick", function() Rec_ClearWhispers() end)
	clr:Tooltip("Forget today's whispers, invite counts and the contact list.")
	y = y - 38

	p:SetHeight(math.abs(y) + 20)
	f.setupPage = p
	Rec_ApplySetup()
end

-- The reply rules, and the tail of the page that has to sit below them. Rules
-- are added and removed at runtime, so everything after them is repositioned
-- here rather than at build time.
function Rec_RenderRules()
	local f = RecruitFrame
	if not (f and f.ruleHost) then return end
	local p = f.msgPage
	local ROW_H, GAP = 40, 4
	-- The open editor's height, used both to size it and to push the rows under
	-- it down -- two numbers for one height is how the editor ended up drawn over
	-- the next reply and the Add button.
	local EDITOR_H = 104

	for _, r in ipairs(f.ruleRows) do r:Hide() end

	local list = db.replies or {}
	local y = 0
	for i, rule in ipairs(list) do
		local row = f.ruleRows[i]
		if not row then
			row = W.Frame(f.ruleHost, "input")

			-- No "edit" button: clicking the row opens it. One less control per row,
			-- and the whole row is a bigger target than a 38px button.
			row.tog = W.Button(row, "ON")
			row.tog:SetSize(36, 18); row.tog:SetPoint("TOPRIGHT", -5, -5)

			-- The ANSWER reads first, on its own line with the full width. What tells
			-- two rules apart is what they say, not the keyword list -- which is often
			-- the same on several rules and truncates to an identical stub.
			row.txt = W.Text(row, "", "body")
			row.txt:SetPoint("TOPLEFT", 8, -6)
			row.txt:SetPoint("RIGHT", row.tog, "LEFT", -8, 0)
			row.txt:SetJustifyH("LEFT")
			if row.txt.SetWordWrap then row.txt:SetWordWrap(false) end

			row.kw = W.Text(row, "", "note", "accent")
			row.kw:SetPoint("TOPLEFT", 8, -23)
			row.kw:SetPoint("RIGHT", row.tog, "LEFT", -8, 0)
			row.kw:SetJustifyH("LEFT")
			if row.kw.SetWordWrap then row.kw:SetWordWrap(false) end

			local hl = row:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints(); hl:SetTexture(FLAT)
			hl:SetVertexColor(1, 1, 1, 0.05)
			row:EnableMouse(true)
			f.ruleRows[i] = row
		end
		row:SetHeight(ROW_H)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f.ruleHost, "TOPLEFT", 0, y)
		row:SetPoint("RIGHT", f.ruleHost, "RIGHT", 0, 0)
		row:Show()

		local on = rule.enabled ~= false
		-- The open row reads as the head of the editor below it, not as another
		-- list item that happens to sit above one.
		local bc = (f.editing == i) and Okanvil.Colors.accent or Okanvil.Colors.border
		row:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)
		-- While this rule is open its full text sits in the editor right below, so
		-- the row drops the truncated copy and just labels what is open.
		if f.editing == i then
			row.txt:SetText("|cffe0b860Editing this reply|r")
		else
			row.txt:SetText(rule.text ~= "" and rule.text or "|cff6f7176(nothing to send yet)|r")
		end

		-- Every rule answers the same words, so only the FIRST enabled one can ever
		-- fire -- first match wins. That is worth saying on the row: without it,
		-- a second reply you switched on simply never goes out and nothing
		-- explains why.
		local shadowed = false
		if on then
			for j = 1, i - 1 do
				-- An "any whisper" rule above this one answers first, every time.
				if list[j].enabled ~= false and (list[j].text or "") ~= "" then
					shadowed = true
					break
				end
			end
		end
		local kwText = ""
		if f.editing == i then
			kwText = ""
		elseif rule.anyMsg then
			-- Said on the row, because it changes who gets this: a rule that answers
			-- everything shadows every rule under it, whatever their keywords.
			kwText = "|cffe0b860answers any whisper|r"
		elseif (rule.text or "") == "" then
			kwText = "|cff6f7176nothing to send -- never fires|r"
		elseif shadowed then
			kwText = "|cffff5555never fires|r |cff8a8d93-- the reply above it answers first|r"
		end
		row.kw:SetText(kwText)
		row.tog.text:SetText(on and "|cff7cfc8aON|r" or "|cff8a8d93OFF|r")
		row:SetAlpha(on and 1 or 0.55)
		row.tog:SetScript("OnClick", function()
			rule.enabled = not on
			Rec_RenderRules()
		end)
		row:SetScript("OnMouseUp", function()
			f.editing = (f.editing == i) and nil or i
			Rec_RenderRules()
		end)

		-- The open editor is flush against its own row (no gap) and indented, so the
		-- two read as one object instead of two stacked boxes.
		y = y - ROW_H - ((f.editing == i) and 0 or GAP)

		-- The open editor pushes the rows below it down rather than floating over
		-- them: an inline editor, the same as the Loot and Logs detail views.
		if f.editing == i then
			local ed = f.ruleEditor
			if not ed then
				ed = W.Frame(f.ruleHost, "dark")
				-- One field: the text. There used to be a keyword box here as well,
				-- holding a copy of the invite keywords from Setup -- the same list
				-- in two editable places, which is a promise to keep them in step by
				-- hand. Every reply now answers the words on the Setup page.
				ed.txLbl = W.Text(ed, "reply", "label", "dim")
				ed.txLbl:SetPoint("TOPLEFT", 8, -13)
				ed.txBox = W.MultiEdit(ed)
				ed.txBox:SetHeight(40)
				ed.txBox:SetPoint("TOPLEFT", 60, -9)
				ed.txBox:SetPoint("RIGHT", ed, "RIGHT", -8, 0)

				-- "Answer anything" -- for the AFK reply.
				--
				-- Every other rule answers the invite keywords from Setup, which is
				-- right for a recruitment line: it goes to someone who asked about the
				-- guild. An AFK notice is the opposite -- if you are away you are away
				-- for whoever whispers, and "do yall need a disc priest?" matched none
				-- of those words and went unanswered.
				-- getFn/setFn read ed._rule, not a captured upvalue: the editor frame
				-- is built once and reused for every rule, so a closure over the rule
				-- open at build time would keep writing to that one for ever.
				ed.any = W.Check(ed, "Answer any whisper",
					function() return ed._rule and ed._rule.anyMsg and true or false end,
					function(v)
						if ed._rule then ed._rule.anyMsg = v and true or nil end
						Rec_RenderRules()
					end)
				ed.any:SetPoint("TOPLEFT", 60, -52)
				ed.any:Tooltip("Send this reply to EVERY whisper, not only the ones"
					.. "\nthat contain a keyword. For an AFK notice.")

				ed.done = W.Button(ed, "Done", "primary")
				ed.done:SetSize(58, 20)
				ed.done:SetPoint("TOPLEFT", 60, -76)

				ed.del = W.Button(ed, "Delete", "danger")
				ed.del:SetSize(58, 20)
				ed.del:SetPoint("LEFT", ed.done, "RIGHT", 5, 0)
				f.ruleEditor = ed
			end
			ed:ClearAllPoints()
			ed:SetPoint("TOPLEFT", f.ruleHost, "TOPLEFT", 14, y)
			ed:SetPoint("RIGHT", f.ruleHost, "RIGHT", 0, 0)
			ed:SetHeight(EDITOR_H)
			ed:Show()

			ed.txBox.edit:SetText(rule.text or "")
			ed._rule = rule
			if ed.any.refresh then ed.any.refresh() end
			-- Commit on focus loss, not on every keystroke: OnTextChanged would
			-- re-render the list under the cursor while it is being typed in.
			ed.txBox.edit:SetScript("OnEditFocusLost", function(s)
				rule.text = (s:GetText() or ""):gsub("\n", " ")
				Rec_RenderRules()
			end)
			ed.done:SetScript("OnClick", function()
				rule.text = (ed.txBox.edit:GetText() or ""):gsub("\n", " ")
				f.editing = nil
				Rec_RenderRules()
			end)
			ed.del:SetScript("OnClick", function()
				table.remove(db.replies, i)
				f.editing = nil
				Rec_RenderRules()
			end)
			y = y - (EDITOR_H + GAP)
		end
	end
	if f.ruleEditor and not f.editing then f.ruleEditor:Hide() end

	local used = math.abs(y)
	f.ruleHost:SetHeight(math.max(1, used))

	-- everything below the rules, pushed down by however tall they came out
	local ry = f.ruleAddY - used - 4
	f.addRule:ClearAllPoints(); f.addRule:SetPoint("TOPLEFT", X, ry)
	ry = ry - 34

	f.clash:ClearAllPoints()
	f.clash:SetPoint("TOPLEFT", X, ry)
	f.clash:SetPoint("RIGHT", p, "RIGHT", -12, 0)

	-- The page grew or shrank by however tall the rules came out, so it has to be
	-- resized and the Dashboard's scrollbar range recomputed -- its own relayout
	-- only fires on a size change it can see, and adding a rule is not one.
	p:SetHeight(math.abs(ry) + 44)
	local sf = p:GetParent()
	if sf and sf._relayout then sf._relayout() end
end

-- Forget the night's whispers, the invite counts and the contact list.
--
-- Lives here rather than on a page of its own: the Whispers tab that used to
-- hold it was a second inbox for messages the chat frame already had, which is
-- the same reason the PuG message window went.
function Rec_ClearWhispers()
	local n = 0
	for _ in pairs(db.log or {}) do n = n + 1 end
	if n == 0 then
		Print("Nothing to clear.")
		return
	end
	-- Not undoable, so it asks.
	Okanvil:Confirm(
		("Clear %d whisper%s?\n\nThe list and today's counts go with it."):format(
			n, n == 1 and "" or "s"),
		"Clear",
		function()
			db.contacts = db.contacts or {}
			wipe(db.log); wipe(db.session); wipe(db.contacts)
			if Rec_RefreshUI then Rec_RefreshUI() end
			Print("Whispers cleared.")
		end)
end

-- The whisper handler and the invite paths call this every time something lands.
-- There is no whisper LIST any more, but the header carries the running tally,
-- so this repaints that -- otherwise the counts only moved when you reopened the
-- page, and a campaign looked dead while it was working.
function Rec_RefreshWhispers()
	local f = RecruitFrame
	if f and f.dash then f.dash:Refresh() end
	if Rec_RenderInbox then Rec_RenderInbox() end
	if Rec_PaintInboxPill then Rec_PaintInboxPill() end
end

-- ------------------------------------------------------------
-- Inbox -- everyone who whispered while advertising, newest first, with a way
-- back to each of them. The header tally says HOW MANY answered; this says WHO,
-- what they wrote, what we sent back, and where their invite stands -- so a
-- whisper that scrolled past in chat is still here to answer after the pull.
-- ------------------------------------------------------------
local INBOX_ROW_H, INBOX_LINE_H, INBOX_MAX = 46, 15, 100

local STATE_LABEL = {
	joined   = "|cff7cfc8ajoined|r",
	sent     = "|cffe0b860invite sent|r",
	declined = "|cffff5555declined|r",
	offline  = "|cff8a8d93was offline|r",
}

local function classHexOf(classFile)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if not c then return "ffdcddde" end
	return ("ff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

local function whenText(t)
	if not t then return "" end
	if date("%Y%m%d", t) == date("%Y%m%d") then return date("%H:%M", t) end
	return date("%d %b %H:%M", t)
end

-- Where this person stands, in one word: the invite outcome if there was one,
-- else whether they were blocked or only answered.
local function statusOf(name)
	local s = db.session and db.session[name]
	if s and s.state and STATE_LABEL[s.state] then return STATE_LABEL[s.state] end
	for _, e in ipairs(db.log or {}) do
		if e.who == name and e.blocked then return "|cffff5555blocked|r" end
	end
	if s and s.replied then return "|cff8a8d93auto-replied|r" end
	return "|cff8a8d93no reply sent|r"
end

local function lastFromThem(c)
	for i = #(c.log or {}), 1, -1 do
		local l = c.log[i]
		if l.them then return l.msg or "" end
	end
	return ""
end

function Rec_BuildInbox(p)
	local f = RecruitFrame
	f.inboxPage = p
	f.inboxRows = {}
	f.inboxOpen = {}

	local markAll = W.Button(p, "Mark all read")
	markAll:SetSize(110, 22)
	markAll:SetPoint("TOPRIGHT", -8, -2)
	markAll:SetScript("OnClick", function()
		for _, c in pairs(db.contacts or {}) do c.unread = 0 end
		Rec_RefreshWhispers()
	end)
	f.inboxMarkAll = markAll

	-- The conversations only: the inv / rep / blk counts in the header are the
	-- night's result and keep their own Clear on Setup.
	local clear = W.Button(p, "Clear inbox", "danger")
	clear:SetSize(96, 22)
	clear:SetPoint("RIGHT", markAll, "LEFT", -6, 0)
	clear:Tooltip("Delete every conversation in the Inbox.\nThe inv / rep / blk counts stay.")
	clear:SetScript("OnClick", function() Rec_ClearInbox() end)

	local hint = W.Text(p, "Everyone who whispered while advertising. Click a row for the"
		.. " whole conversation.", "note", "dim")
	hint:SetPoint("TOPLEFT", X, -6)
	hint:SetPoint("RIGHT", clear, "LEFT", -10, 0)
	hint:SetJustifyH("LEFT")

	f.inboxEmpty = W.Text(p, "No whispers yet. Anyone who answers your advert while it is ON"
		.. " lands here, with the auto-reply they got.", "body", "dim")
	f.inboxEmpty:SetPoint("TOPLEFT", X, -40)
	f.inboxEmpty:SetPoint("RIGHT", p, "RIGHT", -12, 0)
	f.inboxEmpty:SetJustifyH("LEFT")

	Rec_RenderInbox()
end

local function inboxRow(p, i)
	local f = RecruitFrame
	local r = f.inboxRows[i]
	if r then return r end
	r = W.Frame(p, "input")
	r:EnableMouse(true)

	r.dot = r:CreateTexture(nil, "OVERLAY")
	r.dot:SetTexture(FLAT)
	r.dot:SetSize(6, 6)
	r.dot:SetPoint("TOPLEFT", 8, -12)
	local a = Okanvil.Colors.accent
	r.dot:SetVertexColor(a[1], a[2], a[3], 1)

	r.name = W.Text(r, "", "body")
	r.name:SetPoint("TOPLEFT", 20, -6)
	r.status = W.Text(r, "", "note")
	r.status:SetPoint("LEFT", r.name, "RIGHT", 10, 0)
	r.when = W.Text(r, "", "note", "dim")
	r.when:SetPoint("LEFT", r.status, "RIGHT", 10, 0)

	r.friend = W.Button(r, "Friend")
	r.friend:SetSize(58, 22); r.friend:SetPoint("TOPRIGHT", -8, -11)
	r.friend:Tooltip("Add to your friends list -- you get a toast when they come online.")
	r.invite = W.Button(r, "Invite")
	r.invite:SetSize(58, 22); r.invite:SetPoint("RIGHT", r.friend, "LEFT", -6, 0)
	r.invite:Tooltip("Send a guild invite.")
	r.whisper = W.Button(r, "Whisper", "primary")
	r.whisper:SetSize(70, 22); r.whisper:SetPoint("RIGHT", r.invite, "LEFT", -6, 0)
	r.whisper:Tooltip("Open the chat box addressed to them.")

	r.last = W.Text(r, "", "note", "dim")
	r.last:SetPoint("TOPLEFT", 20, -26)
	r.last:SetPoint("RIGHT", r.whisper, "LEFT", -10, 0)
	r.last:SetJustifyH("LEFT")
	if r.last.SetWordWrap then r.last:SetWordWrap(false) end

	-- The whole conversation, shown under the row when it is opened.
	r.convo = W.Text(r, "", "note")
	r.convo:SetPoint("TOPLEFT", 20, -(INBOX_ROW_H - 2))
	r.convo:SetPoint("RIGHT", r, "RIGHT", -12, 0)
	r.convo:SetJustifyH("LEFT")
	r.convo:SetJustifyV("TOP")

	f.inboxRows[i] = r
	return r
end

function Rec_RenderInbox()
	local f = RecruitFrame
	if not (f and f.inboxPage) then return end
	local p = f.inboxPage

	for _, r in ipairs(f.inboxRows) do r:Hide() end
	local list = Rec_ContactList()
	if #list == 0 then f.inboxEmpty:Show() else f.inboxEmpty:Hide() end

	local canInvite = CanGuildInvite and CanGuildInvite()
	local y = -32
	for i = 1, math.min(#list, INBOX_MAX) do
		local c = list[i]
		local name = c.name
		local r = inboxRow(p, i)
		local open = f.inboxOpen[name]

		r.name:SetText(("|c%s%s|r"):format(classHexOf(c.class), name))
		r.status:SetText(statusOf(name))
		r.when:SetText(whenText(c.t))
		r.last:SetText(lastFromThem(c))
		if (c.unread or 0) > 0 then r.dot:Show() else r.dot:Hide() end

		local s = db.session and db.session[name]
		if canInvite and not isInMyGuild(name) and not (s and s.state == "joined") then
			r.invite:Show()
		else
			r.invite:Hide()
		end
		if s and s.watch then r.friend:Hide() else r.friend:Show() end

		r.whisper:SetScript("OnClick", function()
			-- Opened on the click, so the keyboard goes to the chat box because
			-- you asked for it; ESC or sending hands it straight back.
			if ChatFrame_SendTell then ChatFrame_SendTell(name) end
		end)
		r.invite:SetScript("OnClick", function()
			GuildInvite(name)
			db.session[name] = db.session[name] or {}
			db.session[name].invited = true
			db.session[name].state = "sent"
			Print("Guild-invited |cff00ff00" .. name .. "|r.")
			Rec_RefreshWhispers()
		end)
		r.friend:SetScript("OnClick", function() Rec_AddWatchFriend(name) end)

		-- Opening a conversation is reading it.
		r:SetScript("OnMouseUp", function()
			f.inboxOpen[name] = not f.inboxOpen[name] or nil
			c.unread = 0
			Rec_RefreshWhispers()
		end)

		local h = INBOX_ROW_H
		if open then
			local lines = {}
			for _, l in ipairs(c.log or {}) do
				local who = l.them
					and ("|c%s%s|r"):format(classHexOf(c.class), name)
					or "|cffe0b860You|r"
				lines[#lines + 1] = ("|cff6f7176%s|r  %s: |cffdcddde%s|r"):format(
					date("%H:%M", l.t or 0), who, l.msg or "")
			end
			r.convo:SetText(table.concat(lines, "\n"))
			r.convo:Show()
			h = h + #lines * INBOX_LINE_H + 8
		else
			r.convo:Hide()
		end

		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", X, y)
		r:SetPoint("RIGHT", p, "RIGHT", -8, 0)
		r:SetHeight(h)
		r:Show()
		y = y - h - 4
	end

	p:SetHeight(math.max(200, math.abs(y) + 10))
	local sf = f.dash and f.dash.pages and f.dash.pages.inbox
	if sf and sf._relayout then sf._relayout() end
end

function Rec_ClearInbox()
	local n = 0
	for _ in pairs(db.contacts or {}) do n = n + 1 end
	if n == 0 then
		Print("The Inbox is already empty.")
		return
	end
	-- Not undoable, so it asks.
	Okanvil:Confirm(
		("Delete %d conversation%s?\n\nThe inv / rep / blk counts stay."):format(
			n, n == 1 and "" or "s"),
		"Delete",
		function()
			db.contacts = db.contacts or {}
			wipe(db.contacts)
			local f = RecruitFrame
			if f and f.inboxOpen then wipe(f.inboxOpen) end
			Rec_RefreshWhispers()
			Print("Inbox cleared.")
		end)
end

-- The pill carries the unread count, so it is seen from the other two tabs --
-- before the Inbox has ever been opened, which is exactly when it matters.
function Rec_PaintInboxPill()
	local f = RecruitFrame
	local btn = f and f.dash and f.dash.tabBtns and f.dash.tabBtns.inbox
	if not (btn and btn.text) then return end
	local unread = Rec_UnreadCount()
	btn.text:SetText(unread > 0 and ("Inbox (" .. unread .. ")") or "Inbox")
	btn:SetWidth(math.max(60, (btn.text:GetStringWidth() or 40) + 22))
end


-- Pills are built LAZILY (only when the user opens one), so the apply-fn pushes
-- db values into widgets that may not exist yet -- hence the guard.
function Rec_ApplyMessage()
	local f = RecruitFrame
	if not (f and f.msg) then return end
	f.msg:SetText(db.message or "")
	f.cNeedActive:SetChecked(db.repliesNeedActive)
	f.cSkipGroup:SetChecked(db.repliesSkipGroup)

	if f.replyKw then
		local kw = db.keywords or ""
		f.replyKw:SetText(kw ~= ""
			and ("|cff8a8d93Sent to whoever whispers|r |cffdcddde" .. kw
				.. "|cff8a8d93 -- edit that list on Setup.|r")
			or "|cffff5555No keywords set|r |cff8a8d93-- nobody is answered. Set them on Setup.|r")
	end

	-- Both modules watch the same whispers and Recruit stands Invite down when it
	-- starts. Say so here rather than only in a chat line the user has scrolled past.
	local clash = Okanvil.Invite and Okanvil.Invite.KeywordEnabled
		and Okanvil.Invite.KeywordEnabled()
	f.clash:SetText(clash
		and "|cffe0c383The Invite module's keyword-invite is also on. Both watch the same whispers -- starting Recruit turns it off.|r"
		or "")
	f.clash:SetHeight(clash and 26 or 0)
end

function Rec_ApplySetup()
	local f = RecruitFrame
	if not (f and f.guildName) then return end
	f.guildName:SetText(db.guildName or "")
	f.keywords:SetText(db.keywords or "")
	f.blacklist:SetText(db.blacklist or "")
	f.custom:SetText(db.customChannel or "")
	f.customIv:SetText(db.customInterval or 0)
	f.replyCd:SetText(db.replyCooldown or 600)
	f.inviteCd:SetText(db.inviteCooldown or 300)
	f.cInvite:SetChecked(db.autoInvite)
	f.cToast:SetChecked(db.toastOnJoin)
	f.cToastActive:SetChecked(db.toastOnlyActive)
	f.fGuild:SetChecked(db.filterGuild)
	f.fGroup:SetChecked(db.filterGroup)
	f.fFriends:SetChecked(db.filterFriends)
	if f.chInputs then
		for name, box in pairs(f.chInputs) do
			box:SetText(db.channelIntervals[name] or 0)
		end
	end
end

function Rec_RefreshUI()
	local f = RecruitFrame
	if not f then return end
	if f.dash then f.dash:Refresh() end     -- also repaints the header tally
	Rec_ApplyMessage()
	Rec_ApplySetup()
	Rec_RenderInbox()
	Rec_PaintInboxPill()
end

function Rec_AddWatchFriend(name)
	if not name or name == "" then
		return
	end
	if AddFriend then
		AddFriend(name)
	end
	db.session[name] = db.session[name] or {}
	db.session[name].watch = true
	Print("Added |cff00ff00" .. name .. "|r to friends -- you'll get a toast when they come online.")
	Rec_RefreshWhispers()
end



-- ============================================================
-- Slash
-- ============================================================
-- No slash command: open Okanvil from the minimap button and pick Recruit.
-- On/off, clear-log and the toast preview are all controls inside the module UI.
