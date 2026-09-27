# Attendance for fair loot: plan

Status: **designed, not built.** Written 2026-09-28 after the ToC 25 debrief.
Visual mock: https://claude.ai/artifact/WN9Aa2FP5SENE85vw2fV8i (private; ask Okanor for access).

## Goal

Loot priority should reward the mains who come to the guild's main run. The rule
the guild wants:

> A main who misses the 25-man main run of a lockout goes to the **bottom of every
> loot prio ladder**, whatever their spec, until they come to a main run again.

Today nothing enforces it, and attendance is counted in two places that disagree.

## What exists today (deep dive)

### Site: History page (`rats/officer/history/history.js`, `computeAttendance`)

- Counts per **lockout chain**: one obligation per lockout week + instance + size,
  however many nights it took. ToC Normal and ToC Heroic are separate obligations.
- 25-man is mandatory for everyone since their join date. 10-man counts only for
  whoever played it. A raid can be flagged **optional** (log-only).
- Came one night, missed a later one of the same run = partial credit. A latecomer
  who never missed a later night = full credit.
- Vacations (`vacations` node) and marked no-shows are **excused**.
- Data enters by hand: Raid-Helper JSON or the Okanvil attendance JSON pasted into
  `officer/comp/` (`addonAttendanceToComp`), then **Save to history** (encrypted
  `history` node).
- Two nights are treated as the same lockout by a guess: same Wed→Wed week, same
  instance and size, and at least 50% of the same toons (`isContinuation`).

### Site: loot prio (`rats/public/loot/prio/prio-engine.js`)

- Used by the Loot page's officer **Priority** tab and by the export that is pasted
  into the addon (`Okanvil/Modules/LootPrio.lua`).
- Has its **own** attendance, built from the wow-logs `rankings` snapshot:
  `att` = raid days in any log, `icc` = ICC 25 nights, `recent` = nights in the last
  8 raid days (0 = off the ladders).
- It counts **any** logged night: 10-man, alts and pugs the guild logged. It knows
  nothing about vacations, bench or no-shows.
- Weight: `score = merit*0.65 + attpct*0.35 + standing + activity`, where
  `activity` = 10% ICC share + 10% recent share. Attendance also breaks ties inside
  a 5% output band (`byOutputThenLoyalty`) and limits how far a "lucky" raider is
  lifted (`orderLadder`).

### Addon

- Guild module (`Modules/Guild.lua`) takes an attendance snapshot at the first pull
  of a 10/25 raid instance: roster, zone, difficulty, time, and the raid's
  `lockoutId` (filled after the first boss dies, `G.FillLockout`). One per night,
  guarded across `/reload`.
- `G.SnapshotJSON` exports one snapshot as `{"type":"attendance", ..., "lockoutId":N, "players":[...]}`.

## Why the prio stays on the site

The addon cannot compute the prio: 65% of the score is ICC output from wow-logs, and
WoW 3.3.5a has no HTTP. The site also holds everyone's loot history, the vacations,
join dates and the sheet's item bands. And a prio computed in-game would differ per
officer (each client only sees the nights it recorded).

**Addon = sensor, site = brain.** The addon records attendance exactly and
passively; the site decides the order; the order comes back to the game through the
existing pasted ladder.

## Design decisions (agreed)

- **Own module**, officer-only, in the **GUILD** nav group, next to Recruit.
- **Passive.** No popups, no questions, nothing typed by hand in-game. See the
  "passive" rule in the memory notes.
- **No per-boss presence.** A night is its first-pull snapshot. To see who was in a
  given night, open that snapshot.
- **Two raid nights per lockout.** Nights with the same lockout ID are one lockout.
  The ID replaces the 50% guess.
- **No bench in the addon.** Bench, vacations and excused absences are marked on the
  site, as today.
- **Zero addon comms.** Only one client records the night, so five officers online
  never compete to update anything.

## Pending decisions

1. Who records: only the **master looter** (or the raid leader when there is no
   ML)? Proposed: yes.
2. How long the penalty lasts: **until the next main run the player attends**?
   Proposed: yes.
3. Optional extras for v1 (proposed: none; add later):
   - streak in the prio tooltip ("4 of the last 4 main runs");
   - automatic main-run detection: reserved raid (ICC 25) + officer ML/RL + at least
     half the raid are guild mains;
   - weekly Discord post after reset listing who dropped to the bottom.

Also to decide on the site: whether coming to **one of the two nights** counts as
attending (proposed: yes; only missing **both** triggers the rule, the History
partial credit still lowers the %).

## Addon: the Attendance module

Page (officer-only, `canSeePrio` gate), built with `W.Dashboard`:

- **This lockout**: raid, size, lockout ID, and each night (date, players, who
  recorded it).
- **Mains, last 4 lockouts**: one row per guild main (alts folded into mains with the
  guild's rule: rank index 4 / "alt" in rank / "<Main> alt" note, see `U.mainOf`),
  one cell per lockout: both nights / one night / missed, plus a %.
- **Missed this lockout**: mains with no night in the current lockout ID. Info only.
- **Export for site** (header button): one line with every night not exported yet.

Recording:

- Reuse the existing snapshot (`G.SaveSnapshot`). Mark a snapshot as a **main run**
  when it is a reserved raid (configurable list, default ICC 25) and this client is
  the recorder (decision 1).
- Group snapshots by `lockoutId`. A night whose ID is still unknown joins by zone +
  size + lockout week until the ID arrives.
- Keep snapshots in the guild SavedVariables (already account-wide). The current cap
  of 10 snapshots is too small for 4+ weeks of two nights: raise it for main-run
  snapshots or keep main runs in their own list.

Export format (one line, prefix so the site recognises it):

```
OKV1:ATT:{"lockoutId":8841,"zone":"Icecrown Citadel","size":25,"difficulty":2,
 "nights":[{"date":"2026-09-23","recorder":"Kobee","players":[{"n":"Okanor","c":"PALADIN"}, ...]},
           {"date":"2026-09-27", ...}]}
```

Track which nights were exported (`exportedAt`) so the next export only carries new
ones, and let the site dedupe anyway.

## Site changes

1. **History → Import from Okanvil** (`officer/history/`): paste the line, preview
   (raid, ID, nights, players), **Save to history**. One history entry per night,
   each carrying `lockoutId`. Skip nights already imported (same `lockoutId` + date).
   Bench and vacations are still marked here.
2. **Continuation by ID**: in `isContinuation` / the lockout-chain grouping, when both
   runs have a `lockoutId`, group by it and skip the 50% heuristic. Keep the
   heuristic for old entries without an ID.
3. **Prio uses the History %** (`prio-engine.js`): replace the log-based `att`/
   `attpct` with the History attendance (lockout chains, excused vacations). The
   engine runs on officer pages, so it can read the decrypted `history` like the
   History page does. Logs keep feeding output and spec.
4. **The rule**: a main with no night in the latest ICC 25 main-run lockout, and no
   vacation/bench for it, goes to the bottom of every ladder until they attend a main
   run. Apply it as a pass after `orderLadder` (it is not a comparator term), and
   mark them "missed main run" in the ladder and in the export pasted into the addon.

## Out of scope

- Sharing lockouts between clients (who spent their lockout elsewhere) and any
  warning to a player entering a raid: dropped, too intrusive.
- Per-boss presence, late/left tracking.
- Bench typed in-game.
