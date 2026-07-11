# Okanvil — working notes

The conventions and hard-won lessons that aren't obvious from the code.
Read this and [`../CLAUDE.md`](../CLAUDE.md) before making changes.

**What Okanvil is:** one addon for WoW 3.3.5a. A native core (guild dashboard +
Modules manager) plus built-in modules — Guild, Invite, Recruit, Loot, LootRoll,
IDs, Logs — that toggle on/off like DBM/BigWigs.

> There are **no standalone plugins**. That was an old design. It's all one addon.

---

## 🔑 Golden rules

**Edit the repo, not the live copy.**
The installed addon under `<WoW>\Interface\AddOns\Okanvil\` is a separate copy.
After editing, copy the changed files in, or the fix "won't take" after `/reload`.

**This machine runs two clients — sync both.**
The exact paths are machine-specific, so keep them in a local note, not in git.

**The commit message cuts the release.**
Every push to `main` auto-builds and releases. A keyword steers the version bump:

| keyword | bump |
|---|---|
| *(none)* | patch — bug fix, tweak |
| `[minor]` | feature |
| `[major]` | breaking change |
| `[skip]` | no release (docs only) |

> Never hand-edit `## Version:` in the `.toc` — CI stamps it from the git tag.

**Push via the Fork GUI**, no `gh` CLI. Leave the repo commit-ready.

**No Lua interpreter here.** Validate with a char-by-char block balancer, then load
in-game and read the error line. (A naive keyword grep false-positives on `--`
inside strings.)

---

## ⚠️ 3.3.5a API traps

The client is old. These retail APIs are missing or behave differently:

| Don't use | Use instead / why |
|---|---|
| `SetShown` / `SetEnabled` | 4.x only — they **crash**. Core polyfills `SetShown`; else `Show`/`Hide`. |
| `C_Timer` | `Okanvil.Comms.After(delay, fn)` |
| `SetClipsChildren` | `Okanvil.Clip(frame)` |
| `RegisterAddonMessagePrefix`, HTTP, `OpenURL` | none exist (sandboxed Lua) |

**`GetLootMethod` field order** — check `raidML` *before* `partyML == 0`.
In a raid `partyML` is 0 for everyone; reading it first showed the ML UI to all raiders.

**`GetNumGuildMembers` counts online only** unless "Show Offline" is on.
To walk the whole roster use `Okanvil:WithFullRoster(fn)` — it forces offline in and
restores the flag. Toggling it directly leaks into Blizzard's Guild panel and the
`GUILD_ROSTER_UPDATE` storm can stack-overflow.

**Never guess an item ID.** Grep `Modules/IDs-Data.lua` by name; the in-game ID
Finder module is the source of truth.

---

## 🎨 UI conventions

Full spec is in the `okanvil-ui` skill. The essentials:

- **Use the shared widgets** `Okanvil.W` (Core/Widgets.lua) + `W.Dashboard`.
  Don't hand-roll `CreateFrame`+`SetBackdrop` buttons.
- **Palette = gold on neutral dark** (`accent #c0943a`), mirroring the RATS web hub.
  Never add a new accent colour. Toggle ON = green, OFF = dim.
- **Never auto-`SetFocus` an edit box.** A captured box eats W/A/S/D — a player once
  *died mid-fight* because of this. Click-outside, combat, and hide all clear focus.
- **Anti-spill windows** (MRT/ExLib style): module pages get a full-size fill panel;
  dropdowns use the one global menu parented to UIParent.
- **Branding is configurable** (`db.brand`) so any guild can reskin. Only the *skin*
  is editable — "Okanvil" itself is a fixed name.

---

## 📦 Loot & rolls (the biggest, trickiest module)

Storage layout → [`STORAGE.md`](STORAGE.md).
Export contract → the web hub's `docs/LOOT_EXPORT.md`.

- **No `ENCOUNTER_*` events on 3.3.5a** — boss detection is an MRT-style chat scanner.
- **A session = one instance run.** Bosses are *pages within it* (the `<>` pager),
  not separate sessions.
- **Loot is per-character**, config is account-wide. Wiping the account file does
  **not** clear a toon's drops. Edit SavedVariables only with WoW **closed**.
- **Every capture path must be gated by `shouldRecordHere()`** — including the
  addon-comms `LOOT` handler. An ungated path mints ghost `day|<zone>` sessions
  ("Kalimdor / 0 drops") when a teammate's broadcast reaches you in the open world.
- **Master-loot give can silently fail** (WotLK: the candidate list is server-only,
  no re-request API). Confirm before awarding; only real hand-overs count.
- **Tooltips travel in the export** (`dp.tip`, scanned off the client's GameTooltip),
  so the hub draws in-game-looking tooltips with no Wowhead. (`L.BackfillTips` /
  `L.ScanIDs` can re-scan old drops if ever needed — the one-off command is gone.)
- **Textures must be BLP2 DXT5, 256×256, with mips.** PNG/TGA fail silently, and a
  full WoW restart (not `/reload`) is needed to refresh the texture cache.

---

## ⌨️ Commands

Full list → [`SLASH_COMMANDS.md`](SLASH_COMMANDS.md), or type `/okanvil help` in game.

Output goes to a dedicated **`Okanvil` chat tab** when it exists (`/okanvil tab`),
otherwise the default chat frame.
