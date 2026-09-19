# Notes module

A Notes tab in Okanvil that holds raid notes, resolves their role slots to real
names, counts their timers live, and drives a WeakAura — without MRT.

Status: **not built**. Design only.

## Why not just use MRT

MRT does all of this today and is installed on this machine. Two reasons not to
lean on it:

- The raid does not run MRT. A note that only renders inside MRT reaches nobody.
- Okanvil already knows the roster and everyone's spec. The manual Ctrl+H step
  the community notes tell you to do is work it can do correctly every raid.

MRT stays the reference implementation. `MRT/Note.lua` is 4707 lines, but the
part that matters here is small and is documented in `MRT_NOTE_FORMAT.md`.

## Copy the format, not the feature set

The goal is the smallest thing that renders these notes correctly — not a second
MRT. Deliberately out of scope:

- note editing history, drafts, profiles, rosters
- the `{p}...{/p}` phase blocks, `{self}`, `{h}...{/h}` role filters
- glow, `all`, per-source and per-phase counter filters
- sending notes to people who then edit them

What is in scope is exactly what the ICC pack uses: `{time:}` with the four
trigger prefixes, `{spell:}`, raid target icons, and colour codes. Anything the
notes do not use, Okanvil does not parse — an unknown tag is left as text rather
than erroring.

## What a note is

Plain text in the community ICC format. Lines look like:

```
{time:00:52}Bone Storm 1 - |cfff58cbaProt|r {spell:64205}
{time:00:22,SAA:74792:3}Shadow Debuff 4 - |cfff58cbaRet|r {spell:1044}
```

A bare `{time:}` counts from the pull. With a trigger it counts from the Nth
occurrence of a combat-log event. Full syntax in `MRT_NOTE_FORMAT.md`.

## The three jobs

### 1. Hold notes, one per boss

A list of named notes with a text body. `OkanvilNotesDB`, account-wide — a note
is guild knowledge, not per-character.

Backed by the boss catalogue already in `Modules/Bosses-Data.lua`, so a note can
be tied to an encounter.

**Auto-switch on subzone.** ICC gives each boss its own subzone, so walking into
the room is enough to pick the note — no clicking, no thinking about it mid-raid.
The map is the one the Lyri WA shipped, which is worth reusing verbatim:

| Subzone | Note |
|---|---|
| The Spire | Lord Marrowgar |
| Oratory of the Damned | Lady Deathwhisper |
| The Colossal Forge / Rampart of Skulls | Gunship Battle |
| Deathbringer's Rise | Deathbringer Saurfang |
| The Plagueworks | Rotface & Festergut |
| Putricide's Laboratory… | Professor Putricide |
| The Crimson Hall | Blood Council |
| The Sanctum of Blood | Queen Lana'thel |
| The Frostwing Halls | Valithria Dreamwalker |
| The Frost Queen's Lair | Sindragosa |
| The Frozen Throne | The Lich King |
| The Ruby Sanctum | Halion |

Two things the map does not solve:

- **The Plagueworks holds two bosses.** Rotface and Festergut share a subzone, so
  the note has to cover both — which is why the community pack ships them
  combined. Keep that.
- **Never switch in combat.** Zone events fire mid-pull; changing the note under
  someone who is reading it is worse than being one room behind. Defer to
  `PLAYER_REGEN_ENABLED`, the way the Lyri WA does.

Fires on `ZONE_CHANGED`, `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED_INDOORS` and
`PLAYER_ENTERING_WORLD`, throttled — `GetSubZoneText` is cheap but these events
arrive in bursts. `Modules/Logs.lua` already reads `GetZoneText` for session
tracking, so the pattern exists in the addon.

### 2. Fill the slots

Community notes ship with role slots, never names:

```
Holy1  Holy2  Holy3  Prot  Ret  RetAM
```

Okanvil resolves them from the live raid:

| Slot | Resolved by |
|---|---|
| `Holy1..3` | paladins specced Holy, in roster order |
| `Prot` | paladin specced Protection |
| `Ret` / `RetAM` | ret paladin — which one depends on whether they took Aura Mastery |
| unassigned | the line is dropped |

Spec comes from `Modules/Inspect.lua`, which already caches every group member's
spec through `NotifyInspect` (the PuG board reads it for spec and gearscore).

### Spec does not imply the cooldown

The two spells sit in different trees — MRT's own talent map (`ExCD2.lua:13266`):

```lua
_tm[31821] = {1, 6}   -- Aura Mastery      -> Holy tree, tier 6
_tm[64205] = {2, 6}   -- Divine Sacrifice  -> Protection tree, tier 6
```

A Holy paladin reaches Aura Mastery in their own tree *and* has points to spare
for Divine Sacrifice, so **holy paladins have both**. A prot paladin has Divine
Sacrifice but cannot reach Aura Mastery. A ret has whichever one they spent
points on — which is exactly why the community pack ships `Ret` and `RetAM` as
separate slots, and two complete note sets.

A real roster:

| Player | Spec | AM | DSac |
|---|---|---|---|
| Okanor | holy | yes | yes |
| Sola | holy | yes | yes |
| Mongo | prot | no | yes |
| Rellik | ret | yes | no |

So slot filling must check the **talent**, not the spec. A note line carries the
spell it wants (`{spell:64205}`), and a name only goes in if that player actually
has it. Putting Mongo on an Aura Mastery line is a silent failure in the fight —
the addon should flag it rather than write the name.

This is also why note lines exist like:

```
{time:00:05}Pull - Holy2 {spell:64205} + {spell:31821}
```

One person giving both at once, which only a holy paladin can do.

Dropping unfilled lines replaces another manual instruction the note carries:
*"Remove Holy3 lines if you only bring 2 holy paladins."*

### This matters most with pugs

With a guild run you roughly know who took what. With pugs you know nothing —
and asking six strangers which tier-6 talent they picked, before every pull, is
exactly the kind of call a raid leader should not have to make.

The talent scan answers it without asking anyone. The leader reads the filled
note, sees the gaps, and only has to make the calls that are genuinely theirs:
who covers a slot nobody can fill.

Ties into the PuG module, which already inspects applicants for spec and
gearscore through the same `Modules/Inspect.lua` cache.

### 3. Run the timers

This is the part MRT does that nothing else will.

**Count occurrences.** Watch `COMBAT_LOG_EVENT_UNFILTERED` and keep a counter per
`(event, spellID)`, resetting on pull. MRT stores the *time* each counter was
reached, keyed as `SCC:72905:3`, which is exactly what a line needs:

```lua
-- MRT/Note.lua:4471
local key = tableName .. ":" .. spellID .. ":" .. table[spellID]
ECT[key] = GetTime()
```

Four events map to four prefixes: `SCS` cast start, `SCC` cast success,
`SAA` aura applied, `SAR` aura removed.

**Resolve each line to a countdown.** Two cases, and MRT's whole timing model is
these two lines (`Note.lua:377` and `:389`):

```lua
time = eventStart     + time - now   -- anchored to an occurrence
time = encounter_time + time - now   -- anchored to the pull
```

A line anchored to an event slides when the event slides. That is why the numbers
moved in the screenshots when the raid pushed harder — it comes free, no
prediction needed.

**Repaint.** An OnUpdate ticking a few times a second is enough; MRT throttles
the same way rather than rebuilding text every frame.

## What the Kaze aura's source settles

The 3.3.5a port of the Kaze MRT Timers aura (custom init + trigger, read in full)
answers three things the plan had open.

**It reads MRT's saved variables directly, not an event:**

```lua
KT.notes = { _G.VMRT.Note.Text1, _G.VMRT.Note.SelfText }
```

So firing `EXRT_NOTE_TIME_EVENT` would *not* make this aura work against Okanvil.
Driving it means giving it somewhere else to read from — see below.

**Who sees a line is decided by keyword matching, not by slot.** The aura builds
a keyword set per player and shows a line if the text contains any of them:

```
{name}, {nickname}, class:{class}, group:{mygroup},
spec:{spec}, role:{role}, everyone, type:{type}
```

That is why replacing `Holy1` with a real name is enough to make that line show
for that player — their own name is a keyword. It also means Okanvil does not
have to teach the aura anything about slots.

**DBM callbacks do fire.** An earlier read of `DBM-Core.lua` looked for
`FireEvent(` and found only the definition, which suggested the callback system
was dead. Wrong: the call sites use a local lowercase `fireEvent`, and
`DBM_SetStage` is fired at `DBM-Core.lua:6926`. The Kaze aura subscribes to it
for phase changes and that works. Phase tracking can lean on DBM rather than
being inferred.

**Its 3.3.5a port has a live bug.** `KT.readNote` and the `ENCOUNTER_START`
handler both call `C_AddOns.IsAddOnLoaded("MRT")`. `C_AddOns` does not exist on
3.3.5a — WeakAuras polyfills `C_Timer` but not this — so the init errors. The
fix is the global `IsAddOnLoaded`.

## Talking to the aura

MRT fires a WeakAuras event when a line is close:

```lua
-- MRT/Note.lua:~400
WeakAuras.ScanEvents("EXRT_NOTE_TIME_EVENT", waEventID, timeleft, msg)
```

Only for lines carrying a `wa:name` tag, only under 20s, and only at 5s steps or
the last 5 seconds.

Okanvil should fire the **same event name**. Any aura written against MRT then
works against Okanvil unchanged — including the Kaze timer aura, if it turns out
to key off this event rather than reading `VMRT.Note` directly. Worth testing
before writing an aura from scratch.

## Sending to the raid

`Core/Comms.lua` already chunks large payloads (`SendBig`/`OnBig`, 180 bytes per
chunk, `OKANVIL` prefix) — the path that syncs loot priority between officers.
A note is a few KB, so this is wiring, not new machinery.

Receivers need Okanvil to *store* a sent note. That is the open question below.

## Open questions

**Who renders the list?** The scrolling list of lines with live countdowns is
useful to everyone, but drawing it requires Okanvil. Either:

- the raid installs Okanvil (contradicts the premise), or
- only the player's own next line is shown, by an aura, and the full list is a
  leader-side view.

The second matches what was actually asked for: each person sees their own turn,
nothing else.

**Does the Kaze aura read the event or the DB?** Answered: it reads
`_G.VMRT.Note` directly, so MRT's event would not reach it.

**Decided: Okanvil owns this end to end, no MRT compatibility layer.** Shimming a
`VMRT.Note`-shaped table was considered and dropped — this raid does not run MRT,
so the fallback would never be exercised, and pretending to be another addon's
saved variables breaks silently whenever that addon changes shape.

**That is about storage, not syntax.** The note *text* stays byte-for-byte MRT
format — `{time:00:22,SAA:74792:3}`, `{spell:64205}`, role slots, colour codes,
raid icons. Every ICC note on the internet is written that way and none are
written for Okanvil, so a note pasted from Discord or wago must just work.
Inventing a syntax would mean hand-converting a twelve-boss pack with a dozen
variants, forever, for no gain.

What is Okanvil's own is only where the text lives (`OkanvilNotesDB`) and what
reads it.

The Kaze aura stays a reference for *how*, not a dependency. Its keyword model
(a line shows if it contains your name, class, spec, role or group) is worth
copying exactly, because it means the aura never needs to know about role slots —
Okanvil resolves those before the note is sent, and the aura only matches text.

## Order

1. Notes tab: create, edit, store, pick by boss
2. Slot resolution against the live raid — visible as a preview, sending nothing
3. Combat-log counters + timer resolution, rendered in the tab
4. Fire `EXRT_NOTE_TIME_EVENT`, test against the Kaze aura
5. Send to raid, only once the local half is proven

Steps 1–3 are useful alone: a leader-side note window with live timers, with no
aura and no comms involved.
