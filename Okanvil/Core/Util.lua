-- ============================================================
-- Okanvil -- shared utilities (Okanvil.U).
--
-- A home for the small string/link helpers that several modules need, so the
-- same code stops living copied in two places. Loads right after Core.lua and
-- before any module, so `Okanvil.U.*` is ready by the time modules run.
--
--   Okanvil.U.esc(s)            -> JSON string escape (WoW strings are UTF-8)
--   Okanvil.U.escPattern(s)     -> escape Lua-pattern magic chars, for building
--                                  runtime patterns from chat-message templates
--   Okanvil.U.itemIDFromLink(l) -> numeric item id from a link (0 if none)
--   Okanvil.U.shortLink(l)      -> the "item:1234:..." span of a link (nil if none)
-- ============================================================

local Okanvil = Okanvil
local U = {}
Okanvil.U = U

-- JSON string escape. WoW strings are already UTF-8, so raw bytes are valid
-- JSON; we only need to escape the structural characters.
function U.esc(s)
	s = tostring(s or "")
	return (s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t"))
end

-- Escape the magic characters so an arbitrary literal string can be dropped into
-- a Lua pattern. Used when a chat-message template ("%s rolled Need") is turned
-- into a matcher at runtime.
function U.escPattern(t)
	return (tostring(t or ""):gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"))
end

function U.itemIDFromLink(link)
	return link and tonumber(link:match("item:(%d+)")) or 0
end

function U.shortLink(link)
	return link and link:match("(item:[%-%d:]+)") or nil
end
