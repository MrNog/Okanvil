# Using Okanvil in another guild — imports, exports and art

Okanvil was built for RATS, and a few officer tools talk to the **RATS web hub**: they read a text the hub
exports, or write one the hub reads. A 3.3.5a client can't make HTTP requests, so all of this is
copy and paste. Another guild has three options:

- **Skip it.** Each of these tools is optional. Without its paste, the page says it has no data and
  everything else keeps working.
- **Produce the same text from your own site or sheet.** The formats are below. They're plain text, and
  the addon only checks what's listed here.
- **Use the parts that need no site at all.** These are listed under *Works with any guild*.

## Works with any guild (no site needed)

| Tool | Reads | Notes |
|:--|:--|:--|
| Loot Council, Notes, Loot history, Raid snapshots, Raid Finder, PuG, Recruit, Combat Logs, ID Finder, Farm | the game | No outside data. |
| **Invite** (lists, Raid-Helper comp import) | Raid-Helper | Any Raid-Helper composition export (JSON with `slots[].name` + `groupNumber`), any JSON with a `name`/`character`/`player` field, or a plain list of names separated by spaces, commas or `;`. Only the comp JSON carries raid groups. |
| **Soft reserves** (Loot page) | softres.it | softres.it → *Export → CSV*, pasted as-is. |

## Imports — text the addon reads from a site

### Ranking (GUILD → Ranking) · officers

Pasted once, then shared to the whole guild over the addon channel. One record per line, fields
separated by commas. No field may contain a comma.

```
OKR1
H,<unix time>,<raid key>,<raid label>,<period>[+<period>...]
K,<boss 1>,<boss 2>,...
B,<size 25|10>,<board d|h|t>,<period week|month|all>
P,<name>,<CLASS>,<spec>,<rate>,<pts>,<server %>,<fights>,<total>,<heroic 0|1>
S,<size>,<toon>,<boss idx>:<pct>[h] <boss idx>:<pct>[h] ...
```

- `OKR1` must be the first record, and `H` must have a time, or the paste is refused.
- `B` opens a board (`d` = DPS, `h` = Healing, `t` = Tanking). The `P` lines after it are that board's
  players, in rank order.
- `CLASS` is the WoW class token (`WARRIOR`, `DEATHKNIGHT`, …). `rate` is the board's number (DPS, HPS or
  damage taken per fight), and `pts` is your own score.
- `S` lists one toon's best parse per boss. `boss idx` counts from 0 in the `K` line, and a trailing `h`
  marks heroic.
- Names are matched in lower case with letters and digits only, so `Kobée` and `kobee` are the same toon.

On RATS this comes from *Rankings → Export to Okanvil*. The full reference is the header of
`Okanvil/Modules/Ranking.lua`.

### Loot priority (Loot Council → Priority) · officers

A Lua-looking table that the addon **reads with a pattern and never runs**. Each item is one row:

```lua
["deathbringer's will"] = { n = "Deathbringer's Will", p = "Kobee|ROGUE > Grunho|WARRIOR >> Rellik|WARRIOR*", id = 50363, bo = "Deathbringer Saurfang", g = "Trinkets", go = 3, ic = "inv_misc_..." , r = 1 },
```

- **Required:** the key (item name in lower case), `n` (display name) and `p` (the ladder).
- `p` is a list of words separated by spaces. Each name is written `Name|CLASS`, where the class
  colours the name. A trailing `*` marks off-spec. Between names, `>` is the next place in the same
  group and `>>` drops to a lower group.
- **Optional:** `id` (item id), `bo` (boss), `ic` (icon name), `g` (group label) and `go` (group order),
  plus `r = 1` for a reserved item.
- Escape `"` and `\` the Lua way. Anything outside the rows (comments, the table wrapper) is ignored.
- Two optional lines say how old the list is: `generated = "<raid>"` and `exported = "<time>"`. When two
  officers' copies meet, the newer `exported` wins.

On RATS this comes from the officer Loot page's *Export reserved*.

## Exports — text the addon writes for a site

These are what a guild site would import. The addon doesn't care whether anything reads them.

| Export | Where | Shape |
|:--|:--|:--|
| **Roster** | GUILD → Export roster | `{ guildName, realm, exportedAt, ranks:[{name, rankIndex}], roster:[{name, class, level, rankName, rankIndex, publicNote, officerNote}] }`. Includes offline members. |
| **Loot run** | Loot history → export | `{ type:"loot", guildName, realm, capturedAt, day, zone, runId, size, loot:[{ts, player, class, itemId, name, icon, quality, boss, raid, size, runId, de, boe, tip}] }`. A disenchanted item has `player:"Disenchant"`. |
| **Attendance** | Attendance → Export for site | one line: runs `{lockoutId, zone, size, difficulty, week, nights:[{date, t, recorder, players:[{n, c, g, s}]}]}`, plus excuse letters and clears. |

## Ranking art

The Ranking card shows a portrait for each raider:

1. `Okanvil/Media/Ranking/<name>.blp` when there is one. `<name>` is the toon name in lower case, with
   letters and digits only.
2. Otherwise the class art, `Okanvil/Media/Ranking/_<class>.blp` (`_druid.blp`, …).

**The personal portraits are RATS raiders.** They ship in the addon, so in another guild a raider who
happens to share a RATS name would show a RATS rat. Every other raider shows the class art, which works
for any guild.

To add your own portraits:

- Use a 2:1 crop, saved as **BLP2 DXT5 at 512×256**, with `scripts/png2blp_dxt5.py`. It needs
  Pillow 11.2 or newer, because older Pillow writes uncompressed data the client can't load.
- Drop the file into `Media/Ranking/` and fully restart the game.

> **Planned:** a generic build that keeps only the class art, with guild portraits moved to an optional
> art pack. Until then, delete the non-`_` files in `Media/Ranking/` if you want class art only.
