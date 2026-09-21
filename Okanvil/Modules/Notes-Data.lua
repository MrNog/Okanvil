-- ============================================================
-- Okanvil -- Notes: no notes ship with the addon.
--
-- This table is deliberately empty, and adding notes here would be a mistake.
--
-- A note is a raid's plan: who presses which cooldown, on which pull, with the
-- names of real people in it. That belongs to whoever installs the addon, not
-- to the addon. Shipping one guild's plan meant every other guild opened the
-- Notes tab to a roster of strangers, and meant a plan could change under them
-- on an addon update they did not ask for.
--
-- So: you write your notes in the Notes tab, they live in OkanvilNotesDB, and
-- an officer shares them with the raid over the wire. Nothing here.
--
-- The table itself stays because the module reads it as a fallback -- an empty
-- fallback is a note you have not written yet, which is the truth.
-- ============================================================

Okanvil.NotesPack = {}
