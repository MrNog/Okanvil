-- ============================================================
--  Okanvil-IDs-Data -- OPTIONAL pre-built item-name database.
--
--  The whole point of the ID Finder's item DB is: scan ONCE, then ship the
--  data so everyone who installs the addon opens it already full -- no scan,
--  no server-hammering brute force.
--
--  HOW TO REGENERATE (do this on YOUR client, then paste the result here):
--    1. Open the ID Finder -> "advanced +" -> "Full scan" (let it finish).
--    2. Click "Export DB" -> the dialog holds a `OkanvilIDs_Seed = {...}` chunk.
--    3. Ctrl+C it, and REPLACE everything below this comment with it.
--    4. Ship the addon. On load, new ids are folded into each player's DB
--       (their own harvested names are never overwritten).
--
--  Leaving the table empty is fine -- the finder just starts empty and fills
--  as people hover/sweep items.
-- ============================================================

OkanvilIDs_Seed = OkanvilIDs_Seed or {
	-- [44731] = "Bracers of the Hunt",
	-- ... paste your exported ids here ...
}
