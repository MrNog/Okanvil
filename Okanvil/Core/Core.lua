-- ============================================================
--   ██████╗ ██╗  ██╗ █████╗ ███╗   ██╗██╗   ██╗██╗██╗
--  ██╔═══██╗██║ ██╔╝██╔══██╗████╗  ██║██║   ██║██║██║
--  ██║   ██║█████╔╝ ███████║██╔██╗ ██║██║   ██║██║██║
--  ██║   ██║██╔═██╗ ██╔══██║██║╚██╗██║╚██╗ ██╔╝██║██║
--  ╚██████╔╝██║  ██╗██║  ██║██║ ╚████║ ╚████╔╝ ██║███████╗
--   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚══════╝
--  Okanvil -- a host shell for standalone addons (ElvUI-style plugins).
--  Plugins register into Okanvil_Plugins; Okanvil gives them a home + shared media.
-- ============================================================

Okanvil = Okanvil or {}
local Okanvil = Okanvil

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
Okanvil.LSM = LSM

Okanvil.version = GetAddOnMetadata and GetAddOnMetadata("Okanvil", "Version") or "1.0"
Okanvil.entries = {}          -- name -> plugin table (registered)
Okanvil._fontStrings = {}     -- font strings to restyle when the font changes

local FLAT = "Interface\\ChatFrame\\ChatFrameBackground"

-- ------------------------------------------------------------
-- Saved-variable defaults
-- ------------------------------------------------------------
local defaults = {
	window = { width = 660, height = 480, point = "CENTER", x = 0, y = 0 },
	scale = 1.0,
	font = "Friz Quadrata TT", -- LSM font name
	fontSize = 12,
	fontFlag = "", -- "", "OUTLINE", "THICKOUTLINE"
	statusbar = "Blizzard", -- LSM statusbar (for plugins that draw bars)
	bgAlpha = 0.95,
	minimapAngle = 200,
	modules = {},      -- name -> { enabled = bool }. Absent = enabled by default.
	brand = "RATS Guild Hub", -- GUILD SKIN shown after the fixed "Okanvil" wordmark (editable per guild; "" = none)
	hubURL = "https://mrnog.github.io/RATS/", -- the guild's web hub
	lootThreshold = 3, -- min item rarity to log: 0 poor,1 common,2 uncommon,3 rare,4 epic
	recordDungeon = true, -- capture attendance/loot in 5-man dungeons (party instances)
	recordRaid = true,    -- capture attendance/loot in raids
	ratArt = "on",         -- faded rat blacksmith art in the page corner: "on" | "off"
}

local function applyDefaults(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then
				dst[k] = {}
				applyDefaults(dst[k], v)
			else
				dst[k] = v
			end
		elseif type(v) == "table" then
			applyDefaults(dst[k], v)
		end
	end
end

-- ------------------------------------------------------------
-- Media (shared look -- plugins use these so everything matches)
-- ------------------------------------------------------------
function Okanvil:Font()
	local db = self.db
	local path = LSM and LSM:Fetch("font", db.font, true)
	return path or STANDARD_TEXT_FONT, db.fontSize, db.fontFlag
end

function Okanvil:Texture()
	return (LSM and LSM:Fetch("statusbar", self.db.statusbar, true)) or FLAT
end

-- create a font string that auto-restyles when the user changes the font
function Okanvil:NewText(parent, layer, template)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY", template)
	fs:SetFont(self:Font())
	self._fontStrings[fs] = true
	return fs
end

function Okanvil:ApplyFonts()
	local font, size, flag = self:Font()
	for fs in pairs(self._fontStrings) do
		if fs.SetFont then
			-- keep per-string size if it was bumped (store a .sizeMul); default to global size
			fs:SetFont(font, fs._okSize or size, flag)
		end
	end
end

-- flat 1px-bordered panel (the Okanvil/ElvUI look). Plugins: use Okanvil:Backdrop(frame).
-- Kept for back-compat; delegates to the shared Okanvil:Skin (Widgets.lua) so
-- legacy plugins pick up the same palette and alpha re-tinting as the shell.
function Okanvil:Backdrop(frame, alpha, dark)
	if self.Skin then
		self:Skin(frame, dark and "dark" or "panel")
		if alpha then
			local r, g, b = frame:GetBackdropColor()
			frame:SetBackdropColor(r, g, b, alpha)
		end
		return
	end
	-- fallback if Widgets.lua somehow didn't load
	frame:SetBackdrop({
		bgFile = FLAT, edgeFile = FLAT, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	local a = alpha or self.db.bgAlpha
	if dark then frame:SetBackdropColor(0.06, 0.06, 0.08, a)
	else frame:SetBackdropColor(0.10, 0.10, 0.12, a) end
	frame:SetBackdropBorderColor(0.32, 0.32, 0.38, 1)
end

function Okanvil:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd200[Okanvil]|r " .. tostring(msg))
end

-- Should we record attendance/loot right now? Respects the dungeon/raid toggles.
-- Outside instances (e.g. world) we still allow it (manual snapshots, etc.).
function Okanvil:ShouldRecord()
	if not GetInstanceInfo then return true end
	local _, instanceType = GetInstanceInfo()
	if instanceType == "party" then return self.db.recordDungeon ~= false end
	if instanceType == "raid" then return self.db.recordRaid ~= false end
	return true
end

-- ------------------------------------------------------------
-- Plugin registry (load-order safe: plugins fill Okanvil_Plugins)
-- ------------------------------------------------------------
function Okanvil:Register(name)
	local p = Okanvil_Plugins and Okanvil_Plugins[name]
	if not p or self.entries[name] then
		return
	end
	self.entries[name] = p
	if self.RefreshNav then
		self:RefreshNav() -- live update if the window is already built
	end
end

function Okanvil:ProcessPlugins()
	if not Okanvil_Plugins then
		return
	end
	for name in pairs(Okanvil_Plugins) do
		self:Register(name)
	end
end

function Okanvil:CountPlugins()
	local n = 0
	for _ in pairs(self.entries) do
		n = n + 1
	end
	return n
end

-- ------------------------------------------------------------
-- Module enable state -- PER CHARACTER (Okanvil_CharDB). Default: enabled. Each
-- toon decides which tools show; content settings stay account-wide. A disabled
-- module is still registered but hidden from the nav; deeper event-gating is
-- opt-in inside each module later.
-- ------------------------------------------------------------
function Okanvil:IsModuleEnabled(name)
	local m = self.cdb and self.cdb.modules and self.cdb.modules[name]
	if m and m.enabled == false then
		return false
	end
	return true
end

function Okanvil:SetModuleEnabled(name, enabled)
	local cdb = self.cdb
	cdb.modules = cdb.modules or {}
	cdb.modules[name] = cdb.modules[name] or {}
	cdb.modules[name].enabled = enabled and true or false
	if self.RefreshNav then self:RefreshNav() end
	-- if the active panel was just disabled, fall back to Home
	if not enabled and self._current == name and self.ShowPanel then
		self:ShowPanel("__home")
	end
end

-- ------------------------------------------------------------
-- Events / boot
-- ------------------------------------------------------------
local core = CreateFrame("Frame")
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
core:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == "Okanvil" then
		Okanvil_DB = Okanvil_DB or {}
		applyDefaults(Okanvil_DB, defaults)
		Okanvil.db = Okanvil_DB
		-- PER-CHARACTER state (which modules THIS toon shows). Content settings
		-- (brand, fonts, recruit messages, item DB...) stay account-wide in db;
		-- only enable/disable is per-char, so each toon can turn tools on/off.
		Okanvil_CharDB = Okanvil_CharDB or {}
		Okanvil.cdb = Okanvil_CharDB
		-- one-time migration: move any account-wide module toggles to this char
		if Okanvil_DB.modules and not Okanvil_CharDB.modules then
			Okanvil_CharDB.modules = Okanvil_DB.modules
			Okanvil_DB.modules = nil
		end
		Okanvil_CharDB.modules = Okanvil_CharDB.modules or {}
		-- migrate old saved brands: the product name is now a FIXED wordmark, so
		-- db.brand is only the guild skin. Strip a leading "Okanvil" (+ separator)
		-- left over from when it held the whole "Okanvil - <guild>" string.
		local b = Okanvil_DB.brand
		if type(b) == "string" then
			local skin = b:gsub("^%s*[Oo]kanvil%s*[%-%:%|\194\183]*%s*", "")
			if skin == "Okanvil" then skin = "" end
			Okanvil_DB.brand = skin
		end
	elseif event == "PLAYER_LOGIN" then
		Okanvil:ProcessPlugins()
		if Okanvil.BuildMinimap then
			Okanvil:BuildMinimap()
		end
		Okanvil:Print("loaded -- |cff00ff00/okanvil|r. " .. Okanvil:CountPlugins() .. " plugin(s).")
	end
end)

-- ------------------------------------------------------------
-- Slash
-- ------------------------------------------------------------
SLASH_Okanvil1 = "/okanvil"
SlashCmdList["Okanvil"] = function()
	Okanvil:Toggle()
end
