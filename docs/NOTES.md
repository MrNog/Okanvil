# Okanvil — working notes

The conventions and hard-won lessons that aren't obvious from the code.
Read this and [`../CLAUDE.md`](../CLAUDE.md) before making changes.

**What Okanvil is:** one addon for WoW 3.3.5a. A native core (Home dashboard,
Settings, Modules manager) plus built-in modules that switch on or off per
character, like DBM/BigWigs. There are **no standalone plugins**; that was an old
design.

---

## 🗺️ Where things are

```
Okanvil\                      repo root (dev files)
  README.md  CLAUDE.md        player-facing readme / rules for working here
  docs\                       these notes; docs\archive\ = finished plans
  scripts\                    png2blp_dxt5.py (art), gen_bis_data.py, fix_loot_bosses.py
  .github\workflows\          package.yml: push to main = release (zips Okanvil\ only)
  Okanvil\                    THE ADDON (what ships)
    Core\                     Core.lua (DB, media, module registry, HELP), Util.lua (Okanvil.U),
                              Comms.lua (addon bus), Lockouts.lua, Widgets.lua (Okanvil.W)
    Core\UI\                  Shell + Page_Home / Page_Loot / Page_Settings / Page_Modules,
                              Setup (first run), WhispersPanel
    Modules\                  one file (or a few) per tool, *-Data.lua = static tables
    Libs\  Media\
  Okanvil-Art\                optional second addon: RATS raider portraits for Ranking.
                              NOT in Okanvil.zip; art.yml publishes it to the `art` release.
```

The nav (`Okanvil.NAV_GROUPS` in `Core/UI/Shell.lua`):

| group | pages | behind them |
|:--|:--|:--|
| | Home | guild online list, rank counts, last raids, lockouts |
| RAID | Loot · Upgrades · Notes · Raid Finder · PuG | Loot holds the history, the loot mode (Council / SR / Roll) and the officers' Council and Priority tabs (Loot, LootRoll, LootSync, LootTrade, SoftRes*, Council, LootPrio, Wishlist). PuG holds the Whispers panel and the gear audit (PuG*, Audit, Inspect). |
| GUILD | Ranking · Attendance · Recruit | Attendance is officer-only |
| TOOLS | ID Finder · Farm · Modules · Settings | |

No page of their own: Guild snapshots (Home + Settings), Invite (Settings), Combat
Logs (REC timer), Raid Check and the Marks bar (floating windows).

Module enable state is **per character**; each module's settings are
**account-wide**. Storage details → [`STORAGE.md`](STORAGE.md). How to write a new
module → [`MODULE_CONVENTIONS.md`](MODULE_CONVENTIONS.md). Out-of-the-box values →
[`DEFAULTS.md`](DEFAULTS.md).

---

## 🔑 Golden rules

**Edit the repo, not the live copy.**
The installed addon under `<WoW>\Interface\AddOns\Okanvil\` is a separate copy.
After editing, copy the changed files in, or the fix "won't take" after `/reload`.
A new file in the `.toc` needs a full game restart.

**The commit message cuts the release.**
Every push to `main` auto-builds and releases. A keyword steers the version bump;
the full rules (and how to write the Discord post) are in [`../CLAUDE.md`](../CLAUDE.md).

| keyword | bump |
|---|---|
| *(none)* | patch: bug fix, tweak |
| `[minor]` | feature |
| `[major]` | breaking change |
| `[skip]` | no release (docs only) |

> Never hand-edit `## Version:` in the `.toc`; CI stamps it from the git tag.

**Push via the Fork GUI**, no `gh` CLI. Leave the repo commit-ready.

**Validate Lua with `luac5.1 -p`** (Lua 5.1.5 is on PATH, and a hook checks every
edited file). It proves the file parses; runtime errors still need a load in game.

**New features go on their own `feature/<name>` branch** and reach `main` only after
a real in-game test: every release makes the whole raid update.

---

## 🎨 Branding (don't break these)

- **"Okanvil" is a fixed product name**, a wordmark, not editable. The pun
  ("OK Anvil") is deliberate.
- **Guild skin = `db.brand`**, the ONLY editable branding, shown after the wordmark
  and as a Home subtitle. Repaint via `Okanvil.headerPaintBrand()`, never `SetText`
  the wordmark. `db.hubURL` (web hub) sits next to it. Nothing guild-specific ships.
- **Author = Okanor**: fixed credit in the footer and the Settings badge.
- RATS-only data (raider portraits) lives in **Okanvil-Art**, so the core works for
  any guild. Import/export formats for other guilds → [`GUILD_DATA.md`](GUILD_DATA.md).

---

## ⚠️ 3.3.5a API traps

The client is old. These retail APIs are missing or behave differently:

| Don't use | Use instead / why |
|---|---|
| `SetShown` / `SetEnabled` | 4.x only; they **crash**. Core polyfills `SetShown`; else `Show`/`Hide`. |
| `C_Timer` | `Okanvil.Comms.After(delay, fn)` |
| `SetClipsChildren` | `Okanvil.Clip(frame)` |
| `RegisterAddonMessagePrefix`, HTTP, `OpenURL` | none exist (sandboxed Lua) |
| `ENCOUNTER_START` / `ENCOUNTER_END` | don't exist: bosses come from a chat/NPC scanner, pulls from `PLAYER_REGEN_DISABLED` or DBM |

**`GetLootMethod` field order**: check `raidML` *before* `partyML == 0`.
In a raid `partyML` is 0 for everyone; reading it first showed the ML UI to all raiders.

**`GetNumGuildMembers` counts online only** unless "Show Offline" is on.
To walk the whole roster use `Okanvil:WithFullRoster(fn)`: it forces offline in and
restores the flag. Toggling it directly leaks into Blizzard's Guild panel and the
`GUILD_ROSTER_UPDATE` storm can stack-overflow.

**Inspect data arrives in pieces.** Items first, their gems a moment later, and only
while the inspect cache is held. A read with no gems or no enchants at all is
"not read", never "empty" (`Audit.Gear` sets `gemsUnread` / `enchUnread`), and a
partial read must never produce a whisper to the player.

**Never guess an item ID.** Grep `Modules/IDs-Data.lua` by name; the in-game ID
Finder module is the source of truth.

---

## 🎨 UI conventions

Full spec is in the `okanvil-ui` skill. The essentials:

- **Use the shared widgets** `Okanvil.W` (Core/Widgets.lua) + `W.Dashboard`.
  Don't hand-roll `CreateFrame`+`SetBackdrop` buttons.
- **Palette = gold on neutral dark** (`accent #c0943a`), mirroring the RATS web hub.
  Never add a new accent colour. Toggle ON = green, OFF = dim.
- **Never auto-`SetFocus` an edit box.** A captured box eats W/A/S/D; a player once
  *died mid-fight* because of this. Click-outside, combat, and hide all clear focus.
- **Passive, no popups.** Data flows silently; officers read a page. Nothing pops
  up on a raider unasked.
- **Quiet in combat.** Defer only *passive* work (roster sync, Raid Finder scan).
  Never block something the user started (PuG/Recruit spam, a council round).
- **Anti-spill windows** (MRT/ExLib style): module pages get a full-size fill panel;
  dropdowns use the one global menu parented to UIParent.
- **Textures must be BLP2 DXT5**, square power-of-two (up to 1024x512 for the art),
  with mips. PNG/TGA fail silently, and a full WoW restart (not `/reload`) is needed
  to refresh the texture cache. → `scripts/png2blp_dxt5.py`, `Okanvil/Media/README.md`.

---

## 📦 Loot & rolls (the biggest, trickiest module)

Storage layout → [`STORAGE.md`](STORAGE.md). Every capture path → [`LOOT_CAPTURE.md`](LOOT_CAPTURE.md).
Export contract → the web hub's `docs/LOOT_EXPORT.md`.

- **Three loot modes**, set by the master looter and synced to the group:
  **Council** (officers decide on the board; optional wishlist), **SR** (soft
  reserves: `sr [item]` whispers, or the pick window for raiders with Okanvil),
  **Roll** (plain MS/OS, the default). A pick lasts until the group disbands.
- **A session = one instance run.** Bosses are *pages within it* (the `<>` pager),
  not separate sessions.
- **Loot is per-character**, config is account-wide. Wiping the account file does
  **not** clear a toon's drops. Edit SavedVariables only with WoW **closed**.
- **Every capture path must be gated by `shouldRecordHere()`**, including the
  addon-comms `LOOT` handler. An ungated path mints ghost `day|<zone>` sessions
  ("Kalimdor / 0 drops") when a teammate's broadcast reaches you in the open world.
- **Any path that adds a drop validates it** against `RaidLoot-Data` (raid +
  difficulty) and `ItemBoss-Data` (which boss).
- **Master-loot give can silently fail** (WotLK: the candidate list is server-only,
  no re-request API). Confirm before awarding; only real hand-overs count.
- **Tooltips travel in the export** (`dp.tip`, scanned off the client's GameTooltip),
  so the hub draws in-game-looking tooltips with no Wowhead.

---

## 📝 Notes module

- The clock counts from **DBM's pull** (`DBM_Pull`). Anchor ids differ per
  difficulty; there is no translation, so the shipped pack is per difficulty →
  [`RATS_NOTES_BY_DIFFICULTY.md`](RATS_NOTES_BY_DIFFICULTY.md), [`ICC_SPELL_IDS.md`](ICC_SPELL_IDS.md).
- Note syntax → [`MRT_NOTE_FORMAT.md`](MRT_NOTE_FORMAT.md). The WeakAura that reads
  notes → [`KAZE_WEAKAURA.md`](KAZE_WEAKAURA.md), cast bars → [`WA_CAST_BAR_IDS.md`](WA_CAST_BAR_IDS.md).

---

## 🐞 Debugging

Okanvil always traces (no debug toggle): `OkanvilBugDB` in the account
SavedVariables holds each session's trace lines and errors, like a combat log.
`/okerr` shows the error log in game; `/okcomms` prints addon messages live.

---

## ⏭️ Open

- **Event gating for disabled modules:** a module switched off still registers some
  events; make deeper gating opt-in per module.
- **Remember the last open page** across sessions.

---

## ⌨️ Commands

Full list → [`SLASH_COMMANDS.md`](SLASH_COMMANDS.md), or type `/okanvil help` in game.

Output goes to a dedicated **`Okanvil` chat tab** when it exists (`/okanvil tab`),
otherwise the default chat frame.
