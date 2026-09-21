# Plan — what to take from RNTools, and what to fix in Okanvil

Written after reading the whole **RealNibba pack** (`Projects/Nibba/`) against Okanvil,
2026-09-15.

---

## The headline

RNTools is **one person**, not a dev team. In the places that matter Okanvil is already
ahead. The pack is worth mining for **four specific ideas**, not for a rewrite.

Evidence it is not more tested than ours — their master looter has the exact bug we
already fixed:

```lua
-- Nibba/RNTools/Master_Looter.lua:280
return masterLooterPartyID == 0 or masterLooterRaidID == 0
```

In a raid `partyML` is 0 for *everyone*, so **every raider sees the ML UI**. Ours checks
`raidML` first and lowercases + strips the realm before comparing.

### Where each addon wins

| Area | Winner | Why |
|:--|:--|:--|
| Boss attribution | **Okanvil** | They have no `COMBAT_LOG_EVENT_UNFILTERED` at all — flat `[15:23] item -> player` log, no idea which boss dropped what |
| Loot sessions / raid ID | **Okanvil** | They store `date("%H:%M")` and a 1000-entry rolling list |
| Lockouts | **Okanvil** | Ours caches every alt account-wide; theirs reads the current character only |
| Collector storage | **Okanvil** | Ours is account-wide config; theirs is `SavedVariablesPerCharacter`, so every officer alt re-types the names |
| Shell / navigation | **Okanvil** | Left nav scales to 11 modules; their 8 top tabs would wrap |
| Spec inspection | **RNTools** | We have none at all |
| Keyword auto-reply | **RNTools** | Ours is a single canned reply; theirs is a command table |
| Buff assignment | **RNTools** | We have nothing |
| Page density | **RNTools** | Roughly 2x the rows per pixel, and real sortable column headers |

---

## DONE this session

- [x] **`Modules/Inspect.lua`** — ported their spec scanner, fixed three bugs in the process
  (see below). Registered in the `.toc`. **Not yet wired to anything.**
- [x] **Inspect also reads GEAR** — gearscore, average item level, and PvP-piece count, read
  in the *same* inspect window as the spec so it costs no extra request. Cached per player
  name. `M.GearOf()`, `M.GearLabel()`, `M.Info()`, `M.ScanOne(name)`.
  - GearScore addon first (so our number matches what the raid sees), average item level as
    fallback — returned as a **separate field**, never labelled "GS".
  - PvP detection by **resilience** on the item tooltip: no PvE item in 3.3.5a carries it.
    String comes from `ITEM_MOD_RESILIENCE_RATING`, so it survives a non-enUS client.
  - `store()` **merges** rather than replaces: a scan that reads the spec but whose inventory
    is not cached yet must not wipe a good gearscore from an earlier scan.
- [x] **DBM pull hook actually attaches** — `Okanvil:HookDBMPull()` now retries (DBM builds
  its callback API across its own load steps, so the one-shot check at `PLAYER_LOGIN` found
  `DBM.RegisterCallback` nil and silently never tried again). This is why the raid-check
  toast had to be closed by hand every pull.
- [x] **`PLAYER_REGEN_DISABLED` backstop** in RaidCheck — closes the toast on a pull even
  with no DBM, or when someone pulls with no countdown. Honours the same `closeOnPull`.
- [x] **Guild roster warmed at login** — nothing ever called `GuildRoster()`, and
  `GetNumGuildMembers()` answers 0 until the client fetches. That was the "takes a while to
  show up" on first open.
- [x] **Layout tokens** (`Okanvil.UI.PAD_X / PAD_TOP / ROW_H / SECTION / FIELD_H`) and
  `Okanvil.UI.DashScroll()` — a byte-identical 14-line scroll block was copy-pasted into
  four pages. Net **-110 lines**.

### What Inspect fixed vs their original

| Their bug | Ours |
|:--|:--|
| Stores whatever `INSPECT_TALENT_READY` returns | Re-checks `UnitName(curUnit) == curName` first — a mid-scan roster shuffle otherwise files one player's spec under another's name |
| Queues yourself | You cannot inspect yourself (the inspect cache is never populated for your own unit) — burns a full 3s timeout every scan. Ours reads live talents directly |
| Talentless alt filed as "Blood" | `bestPts <= 0` returns nil, so a fresh alt never poisons the cache |
| Reads the talent tab **name** | We index by **position** — locale-proof |

Also solves the `feral` bear-vs-cat ambiguity that
`Modules/RaidFinder.lua` explicitly gives up on.

---

## TODO — in order

### 1. Auto Reply module (keyword table)
**New:** `Modules/AutoReply.lua`

Today we have one canned reply, in two places (`PuG.lua` `autoReply`/`replyText`,
`Recruit.lua` `CHAT_MSG_WHISPER`). Theirs is a **command → response table** with presets.

- `?discord` / `?apply` / `?raid` → per-command response
- Exact vs Contains matching
- Per-sender cooldown (theirs: 7 min) so a spammer can't flood you
- Shared service; PuG and Recruit both consume it

Best first job: no dependency on anything untested.

### 2. Buff assignment (Greater Blessings)
Depends on **Inspect** working in a live raid.

Their auto-assign is genuinely smart:
Ret → Might (preferring the one with **Improved Blessing of Might**), Holy → Wisdom,
Prot → Sanctuary, Kings → whoever is left. Special case: with **≤3 paladins**, a Prot
paladin takes **Kings** instead and Sanctuary is left unassigned.

Paladin detection comes from the raid roster; specs come from `Okanvil.Inspect`.

### 3. Loot page: 3 config tabs → 1
The three tabs hold **11 controls total**:

| Tab | Content | Height |
|:--|:--|:--|
| Collectors | 1 checkbox, 3 name rows, 1 checkbox | 330 |
| Messages | 4 edit boxes | 260 |
| Settings | 1 dropdown, 2 checkboxes | 160 |

And the split is arbitrary — *"Whisper winner on Award"* is a checkbox in **Collectors**
while the whisper **text** is an edit box in **Messages**. Two clicks apart, one feature.

Merge `Loot_BuildCollectors` + `Loot_BuildMessages` + `Loot_BuildSettings` into one
`Loot_BuildConfig` with **section headers** instead of tabs:

```
CAPTURE          quality dropdown, dungeons/raids
ANNOUNCE         MS / OS / Free templates
SPEED-RUN LOOT   enable, 3 collector rows, whisper check + its text
```

**The rule this establishes:** a tab is for a different **task**, not a different **group
of settings**. History vs Config = tabs. Collectors/Messages/Settings = one page.

### 4. Density + column headers
From the screenshots, theirs fits ~2x the rows per pixel and every list has a **clickable
sort header** (`Type ↑`). Our guild list has no header at all, so column 3 being a zone is
guesswork.

- `ROW_H` 20 → 16-18 on list pages
- Sortable column headers on the Home guild list — **reuse**, we already have them in
  `RaidFinder-Mini.lua`

### 5. Recruit: same tab merge as Loot
Text / Settings / Filters → one config page, once the Loot pattern is proven.

### 6. Invite: surface rank buttons
`I.InviteByRank()` already exists and is buried. UI problem, not a missing feature.

### 7. Raid-warning spectator parse
The one genuinely missing **capability**. They listen to `CHAT_MSG_RAID_WARNING` for
another addon's roll announcements, so their window follows along when the officer is
running RCLootCouncil or RaidRoll.

We already register that event for external rollers — check whether it covers their
`"rolls closed"` and `"no winner for"` states.

### 8. PuG: show inspected gear on applicants
The cheap half of the "comp builder" idea. `Inspect.lua` already reads gear; this just
surfaces it.

Show `Inspect.GearLabel(name)` next to each applicant, so **"he said 5.8k"** becomes
**"5875, 3 PvP"**. Kills the self-reported-gearscore problem, which is the single most
useful thing in that whole screenshot.

**Limit to be honest about:** inspect only works **in range and in your group**. You cannot
inspect an applicant before inviting them — so the flow is invite → inspect → see the truth,
not vet-before-invite.

### 9. Player blacklist
A name list with a reason, checked when an applicant whispers and when the roster renders.

Local first. A guild-wide sync over addon-comms is possible later and fits the planned
comms layer — but **it can never be a server-wide ninja list**: no HTTP on 3.3.5a, so it is
only ever as wide as the people running Okanvil.

*(Recruit's existing `blacklist` is a **word filter** for gold-seller spam — a different
thing that happens to share the name.)*

### 10. PuG comp grid (BIG — do last of the features)
The expensive half: slot boxes for tanks/healers/DPS, click-to-swap, red for blacklisted,
GS + PvP on each tile.

Wait until **after** the Loot/Recruit tab merges — building a grid into a page layout that
is about to change means building it twice.

### 11. In-game help (LAST)
Theirs is a flat data table + a ~35-line renderer, ~200 content rows:

```lua
{ h=true, t="ROLL MANAGER" }   -- header
{ q=true, t="How does a roll work?" }
{ a=true, t="1. Add an item to the list" }
{ s=true }                     -- spacer
```

The valuable part is that it answers **"why did this happen to me?"** — *"Why is Warmane
muting me?"*, *"What does [Timeout] mean?"* — not just "what button does this".

**But not as one monolithic tab.** With 11 modules that is worse than theirs. Per-module
help behind a `?` in the `W.Dashboard` header, fed by `Okanvil.Help[<module>]`.

Do it **after** the UI settles, or it gets rewritten. Write each module's entries as that
module is touched.

---

## Explicitly NOT doing

| Thing | Why |
|:--|:--|
| Port to Ace3 | ~40 lib files for widgets `Okanvil.W` already provides; we would lose the left-nav shell |
| Their master looter | Has the `partyML == 0` bug we fixed |
| Splash screen | 6-second animated logo on every login |
| Setup wizard (8 pages) | Their settings are scattered so they need one; ours are not |
| Their BiS database | Hardcoded ICC/RS; our `IDs-Data.lua` is real |
| MS-change whisper tracking | Inspect reads live specs — a manual whisper override is a worse version of what we now get automatically |
| Moving nav to the top | Left nav scales to 11 modules; the real complaint is *inside* the pages |

---

## Deferred / watch

- **`IDs-Data.lua` is 368KB** — ~60% of non-lib code, loaded at login for everyone. Lazy-load
  the ID Finder data if login ever feels slow. Perf, not a bug.
- **`Loot.lua` is 154KB** — deliberately left coupled. Still right. If it ever gets painful,
  the **capture** half (corpse scan, chat patterns, boss resolve) separates from the
  **storage/export** half.
- **Weekly-quest aliases** — their `RaidBrowser.lua` has ~60 (`"weekly patch"`, `"fl must
  die"`) with a smart rule: ambiguous shorthands (`fl`, `raz`, `xt`) only count when
  "weekly" also appears. Pure data; fold into `RaidFinder-Parser.lua` next time it's open.
- **MarketWatch as a module** — their trade-chat scanner (WTB/WTS/WTT) is the best fit in
  the pack. We already own every piece: parser, expiry, sortable list, quality colours. The
  new part is `Dictionaries.lua`, categorised keyword lists with an ordered first-match-wins.
  Keep their ordering (SFS before MiningBS — raid-loot posts mention both).
- **Collector comms sync** — already planned: share Main/Frag/BoE so a **new** ML inherits
  them when the game's ML changes. RNTools cannot do this at all.

---

## Needs testing in a real raid (not a code gap)

- **Inspect** — `M.ScanGroup()` against a live 25-man
- **Loot collectors** — the speed-run sweep path has never been properly exercised
