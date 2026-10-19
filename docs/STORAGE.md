# 💾 Okanvil — storage model

Where every piece of Okanvil data lives. Read this **before** editing, wiping, or
debugging saved data — otherwise you hunt in the wrong file.

> **The one gotcha:** loot history is **per-character**. Wiping the account file does
> **not** clear a toon's drops.

Declared in `Okanvil.toc`:

```
## SavedVariables:             Okanvil_DB, RecruitDB, OkanvilIDsDB, OkanvilRaidFinderDB,
                               OkanvilBugDB, OkanvilPuGDB, OkanvilNotesDB
## SavedVariablesPerCharacter: OkanvilLogsDB, Okanvil_CharDB
```

<br>

---

## 🌐 Account-wide — one copy for the whole account

📁 `WTF\Account\<ACCOUNT>\SavedVariables\Okanvil.lua`

| Global | Code alias | Holds |
|:--|:--|:--|
| `Okanvil_DB` | `Okanvil.db` | brand/skin, loot **config** (collectors, roll messages, thresholds), invite settings, window positions; one sub-table per module: `council`, `lootPrio`, `softres`, `wish`, `upgrades`, `marksbar`, `ranking`, `attendance` |
| `RecruitDB` | Recruit module | recruit keyword / config |
| `OkanvilIDsDB` | IDs module | ID Finder data |
| `OkanvilRaidFinderDB` | Raid Finder | scanner settings and filters |
| `OkanvilPuGDB` | PuG module | the LFM builder, spam state, applicants, the enchant scan |
| `OkanvilNotesDB` | Notes module | your own notes and role slots (the shipped pack is in `Notes-Data.lua`) |
| `OkanvilBugDB` | Core | the always-on trace and error log, per session: what to ask a raider for when they hit a bug |

> Loot **config** is account-wide on purpose — an officer sets collectors once for all
> their toons.

<br>

## 👤 Per-character — a separate copy for each toon

📁 `WTF\Account\<ACCOUNT>\<REALM>\<CHARACTER>\SavedVariables\Okanvil.lua`
*(one each for Okanor, Okanata, Okanthys…)*

| Global | Code alias | Holds |
|:--|:--|:--|
| `Okanvil_CharDB` | `Okanvil.cdb` | **loot sessions / drop history** (`cdb.lootSessions`), enabled-modules state |
| `OkanvilLogsDB` | Logs module | boss-kill / session logs |

> The loot **session log** (every drop, receiver, boss) is per-character. The code
> aliases `db().sessions` onto `Okanvil.cdb.lootSessions`.

<br>

---

## 🧹 Common tasks

**Wipe a character's loot history**
→ edit `lootSessions` in that **character's** per-char file. The account file has no
sessions (config only). Or use the in-game "Clear session" button — it clears the
**current** character only.

**Edit any SavedVariables file by hand**
→ **close WoW first.** It rewrites SV from memory on `/reload` and logout, clobbering
any edit you made on disk.
