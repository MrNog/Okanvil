-- ============================================================
-- Okanvil -- UI: Guild page
-- Split out of the old monolithic Core/UI.lua. Loads after Core/UI/Shell.lua,
-- which publishes the shared helpers on Okanvil.UI (see that file).
-- ============================================================

local Okanvil = Okanvil
local W   = Okanvil.W
local C   = Okanvil.Colors
local LSM = Okanvil.LSM
local FLAT           = Okanvil.UI.FLAT
local u3             = Okanvil.UI.u3
local newFillPanel   = Okanvil.UI.newFillPanel
local newScrollPanel = Okanvil.UI.newScrollPanel

function Okanvil:BuildGuild()
	local fill = newFillPanel()
	local host = fill.child
	local G = Okanvil.Guild

	-- Prime the FULL roster now so an export moments later has the offline members
	-- loaded. GetGuildRosterInfo only returns offline members after the client has
	-- fetched them (GUILD_ROSTER_UPDATE), which needs SetGuildRosterShowOffline(true)
	-- + a GuildRoster() request. Without this, opening the panel and hitting Export
	-- immediately exported only the online members (the "238 left the guild" bug).
	if IsInGuild and IsInGuild() then
		if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
		if GuildRoster then GuildRoster() end
	end

	-- Dashboard shell (MRT/Recruit-style): header (icon + title + status + CTA),
	-- no tabs, no drawer -> the snapshots list gets the whole content area and
	-- scrolls internally. CTA = Export roster.
	local dash = W.Dashboard(host, {
		title = "Guild",
		icon = Okanvil.ICONS.guild,
		drawerWidth = 0,
		footerHeight = 0,
		primaryText = function() return "Export roster" end,
		onPrimary = function()
			-- Async: force "Show Offline Members" on, refresh, wait for the roster to
			-- actually load the offline members (GUILD_ROSTER_UPDATE), THEN build + show
			-- the full list. A synchronous build here caught only the online members.
			G.ExportRoster(function(json)
				Okanvil:ShowExport(json, "Guild roster")
			end)
		end,
		statusText = function()
			local snaps = (Okanvil.db.guild and Okanvil.db.guild.snapshots) or {}
			return "|cff8a8d93" .. #snaps .. " snapshot" .. (#snaps == 1 and "" or "s") .. "|r"
		end,
	})
	fill.dash = dash

	-- a scroll panel INSIDE main so the snapshots list scrolls without resizing
	local main = dash.main
	local X = 12
	local sf = CreateFrame("ScrollFrame", nil, main)
	sf:SetPoint("TOPLEFT", X, -8); sf:SetPoint("BOTTOMRIGHT", -14, 8)
	local p = CreateFrame("Frame", nil, sf); p:SetSize(10, 1); sf:SetScrollChild(p)
	local sb = CreateFrame("Slider", nil, main)
	sb:SetPoint("TOPRIGHT", -4, -8); sb:SetPoint("BOTTOMRIGHT", -4, 8); sb:SetWidth(4)
	sb:SetOrientation("VERTICAL"); sb:SetValueStep(1)
	local th = sb:CreateTexture(nil, "OVERLAY"); th:SetTexture(FLAT); th:SetVertexColor(u3(C.accent)); th:SetSize(4, 40)
	sb:SetThumbTexture(th)
	sb:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, d) sb:SetValue(sb:GetValue() - d * 30) end)
	sf:SetScript("OnSizeChanged", function() p:SetWidth(sf:GetWidth()) end)
	local wrap = { relayout = function()
		p:SetWidth(sf:GetWidth())
		local maxs = math.max(0, p:GetHeight() - sf:GetHeight())
		sb:SetMinMaxValues(0, maxs); sb:SetShown(maxs > 4)
	end }

	-- row 0: intro hint + "Snapshot now" secondary action, then the list below it
	local hint = W.Text(p, "Attendance is captured automatically at the first pull. Export roster feeds the web hub.", 10, "dim")
	local snapNow = W.Button(p, "Snapshot group now")
	snapNow:SetSize(150, 24)
	snapNow:SetScript("OnClick", function()
		local snap, err = G.SaveSnapshot("manual")
		if not snap then
			Okanvil:Print("Snapshot failed: " .. (err or "?"))
		else
			wrap.expanded = snap        -- expand the new snapshot inline (no popup)
			if wrap._rebuild then wrap._rebuild() end
		end
	end)
	local sh = W.Text(p, "SAVED SNAPSHOTS", 10, "dim")

	wrap.rows = {}
	wrap.detailFS = {}       -- pooled expansion text blocks (one per row when open)
	wrap.expanded = nil
	local function rebuild()
		for _, r in ipairs(wrap.rows) do r:Hide() end
		for _, t in ipairs(wrap.detailFS) do t:Hide() end
		-- top block (hint + snapshot-now + list header) lives inside the scroll child
		hint:ClearAllPoints(); hint:SetPoint("TOPLEFT", X, -4); hint:SetPoint("RIGHT", p, "RIGHT", -X, 0); hint:SetJustifyH("LEFT")
		snapNow:ClearAllPoints(); snapNow:SetPoint("TOPLEFT", X, -34)
		sh:ClearAllPoints(); sh:SetPoint("TOPLEFT", X, -70)
		local snaps = (Okanvil.db.guild and Okanvil.db.guild.snapshots) or {}
		if #snaps == 0 then
			wrap.empty = wrap.empty or W.Text(p, "", 12, "dim")
			wrap.empty:ClearAllPoints(); wrap.empty:SetPoint("TOPLEFT", X, -90)
			wrap.empty:SetText("|cff888888No snapshots yet. They save at the first pull, or use the button above.|r")
			wrap.empty:Show(); p:SetHeight(140); wrap.relayout(); return
		end
		if wrap.empty then wrap.empty:Hide() end

		local di = 0
		local y = 90
		for i, snap in ipairs(snaps) do
			local r = wrap.rows[i]
			if not r then
				r = W.Frame(p, "input")
				r.title = W.Text(r, "", 13); r.title:SetPoint("TOPLEFT", 10, -6)
				r.sub = W.Text(r, "", 10, "dim"); r.sub:SetPoint("BOTTOMLEFT", 10, 6)
				r.del = W.Button(r, "X", "danger"); r.del:SetSize(24, 22); r.del:SetPoint("RIGHT", -8, 0)
				r.export = W.Button(r, "Export"); r.export:SetSize(72, 22); r.export:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
				r.view = W.Button(r, "View"); r.view:SetSize(60, 22); r.view:SetPoint("RIGHT", r.export, "LEFT", -6, 0)
				r:EnableMouse(true)
				wrap.rows[i] = r
			end
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", X, -y); r:SetPoint("RIGHT", p, "RIGHT", -X, 0); r:SetHeight(40)
			local dateStr = date("%b %d  %H:%M", snap.t)
			local where = (snap.zone ~= "" and snap.zone) or "Unknown"
			local isOpen = (wrap.expanded == snap)
			r.title:SetText((isOpen and "|cffffd200v|r  " or "|cff8a8d93>|r  ")
				.. where .. (snap.boss ~= "" and ("  |cff8a8d93-- " .. snap.boss .. "|r") or ""))
			r.sub:SetText(dateStr .. "  |cff8a8d93|  " .. (snap.count or 0) .. " players  |  " .. (snap.trigger or "") .. "|r")
			r.view.text:SetText(isOpen and "Close" or "View")
			local function toggle()
				if wrap.expanded == snap then wrap.expanded = nil else wrap.expanded = snap end
				rebuild()
			end
			r.view:SetScript("OnClick", toggle)   -- View/Close button owns the toggle
			r.export:SetScript("OnClick", function()
				Okanvil:ShowExport(G.SnapshotJSON(snap), "Attendance -- " .. dateStr)
			end)
			r.del:SetScript("OnClick", function()
				if wrap.expanded == snap then wrap.expanded = nil end
				G.DeleteSnapshot(snap)
			end)
			r:Show()
			y = y + 46

			if isOpen then
				di = di + 1
				local t = wrap.detailFS[di]
				if not t then t = W.Text(p, "", 12); t:SetJustifyH("LEFT"); wrap.detailFS[di] = t end
				t:ClearAllPoints()
				t:SetPoint("TOPLEFT", X + 14, -y); t:SetPoint("RIGHT", p, "RIGHT", -X, 0)
				t:SetText(G.SnapshotBodyText(snap))
				t:Show()
				y = y + t:GetStringHeight() + 10
			end
		end
		p:SetHeight(math.max(y + 10, sf:GetHeight()))
		wrap.relayout()
	end
	wrap._rebuild = rebuild
	local function refreshAll() dash:Refresh(); rebuild() end
	G.onSnapshot = function() if fill:IsShown() then refreshAll() end end
	fill:SetScript("OnShow", refreshAll)
	return fill
end

-- ------------------------------------------------------------
-- Loot (native) -- what dropped, per boss. Data only; winners on the hub.
-- ------------------------------------------------------------
