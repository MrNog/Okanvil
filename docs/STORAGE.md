# Okanvil — SavedVariables / storage model

Where every piece of Okanvil data lives. Read this BEFORE editing, wiping, or
debugging saved data — otherwise you hunt for data in the wrong file.

Declared in `Okanvil.toc`:

```
## SavedVariables:            Okanvil_DB, RecruitDB, OkanvilIDsDB
## SavedVariablesPerCharacter: OkanvilLogsDB, Okanvil_CharDB
```

## ACCOUNT-WIDE (one copy for the whole account)

File on disk: `WTF\Account\<ACCOUNT>\SavedVariables\Okanvil.lua`
(plus `RecruitDB` and `OkanvilIDsDB` written to the same account SV folder).

| Global | Code alias | What |
|---|---|---|
| `Okanvil_DB` | `Okanvil.db` | brand/skin, loot **config** (collectors, roll messages, thresholds), invite settings, rollmgr window pos |
| `RecruitDB` | Recruit module | recruit keyword/config |
| `OkanvilIDsDB` | IDs module | ID Finder data |

> Loot **config** (collectors, `rollMsg`, thresholds) is account-wide on purpose —
> an officer sets collectors once for all their toons. See Loot.lua ~line 204.

## PER-CHARACTER (a separate copy for EACH character)

File on disk: `WTF\Account\<ACCOUNT>\<REALM>\<CHARACTER>\SavedVariables\Okanvil.lua`
— so e.g. the same account has one per Okanor, Okanath, Okanata, Okanthys…

| Global | Code alias | What |
|---|---|---|
| `Okanvil_CharDB` | `Okanvil.cdb` | **loot SESSIONS / drop history** (`cdb.lootSessions`, aliased to `db().sessions`), enabled-modules state |
| `OkanvilLogsDB` | Logs module | boss-kill / session logs |

> The loot SESSION LOG (every drop, receivedBy, boss) is **PER CHARACTER**. The
> code aliases `db().sessions` onto `Okanvil.cdb.lootSessions` (Loot.lua ~line 221).
> **This is the gotcha:** wiping the account file does NOT clear a character's loot
> history — you must clear that character's per-char `Okanvil.lua` (or the
> `lootSessions` table inside it).

## Practical rules

- **Wiping loot history** → edit `lootSessions` in the PER-CHARACTER file of the
  character(s) that recorded it. The account file has no sessions (only config).
- **Editing any SV file** → WoW must be fully CLOSED first; it rewrites SV from
  memory on `/reload` and logout, clobbering disk edits.
- The in-game "Clear session" button clears the CURRENT character's sessions only.
