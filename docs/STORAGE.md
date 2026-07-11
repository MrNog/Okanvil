# 💾 Okanvil — storage model

Where every piece of Okanvil data lives. Read this **before** editing, wiping, or
debugging saved data — otherwise you hunt in the wrong file.

> **The one gotcha:** loot history is **per-character**. Wiping the account file does
> **not** clear a toon's drops.

Declared in `Okanvil.toc`:

```
## SavedVariables:             Okanvil_DB, RecruitDB, OkanvilIDsDB
## SavedVariablesPerCharacter: OkanvilLogsDB, Okanvil_CharDB
```

<br>

---

## 🌐 Account-wide — one copy for the whole account

📁 `WTF\Account\<ACCOUNT>\SavedVariables\Okanvil.lua`

| Global | Code alias | Holds |
|:--|:--|:--|
| `Okanvil_DB` | `Okanvil.db` | brand/skin, loot **config** (collectors, roll messages, thresholds), invite settings, roll window position |
| `RecruitDB` | Recruit module | recruit keyword / config |
| `OkanvilIDsDB` | IDs module | ID Finder data |

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
