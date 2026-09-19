# MRT note timers

The syntax the Kaze-style cooldown notes use, verified against MRT's own parser
(`MRT/Note.lua`) rather than inferred from screenshots.

## The tag

```
{time:TIME,TRIGGER:SPELL_ID:COUNT:SOURCE_NAME:PHASE}
```

Everything after `TIME` is optional. MRT's in-game help (`Note.lua:3200`) spells
out the full form; the ICC notes use the first three fields.

### TIME

Seconds, `M:SS` or `MM:SS`. What it counts from depends on whether a trigger
follows:

| Form | Means |
|---|---|
| `{time:00:52}` | 52s after the pull |
| `{time:00:22,SAA:74792:1}` | 22s after the **1st application** of spell 74792 |

So a bare `{time:}` is pull-relative and anything with a trigger is
event-relative. This is what makes the displayed countdown slide when the raid
does more damage: the event lands earlier, and every line hanging off it moves
with it.

### TRIGGER

Four combat-log events, parsed at `Note.lua:375`:

| Code | Combat log event |
|---|---|
| `SCS` | SPELL_CAST_START |
| `SCC` | SPELL_CAST_SUCCESS |
| `SAA` | SPELL_AURA_APPLIED |
| `SAR` | SPELL_AURA_REMOVED |

### COUNT

Which occurrence, 1-based. `SCC:72905:3` is the third cast-success of 72905 this
encounter. MRT keeps per-encounter counters (`encounter_counters`) and bumps them
in `AddCounter`; they reset on pull.

Counters also exist per source name and per phase, which is what the two optional
trailing fields filter on:

```
{time:65,SCC:17:2:Okanor}     only count Okanor's casts
{time:1:05,SCC:17:2::p3}      only count during phase 3
```

## Other tags in these notes

| Tag | Effect |
|---|---|
| `{spell:64205}` | inline spell icon |
| `\|cfff58cba...\|r` | colour; the ICC notes use paladin pink for role slots |
| `{skull}` `{cross}` `{square}` `{moon}` `{triangle}` `{star}` `{circle}` `{diamond}` | raid target icons |
| `{self}` | replaced with the viewer's own `SelfText` |
| `{h}...{/h}` | healers only — stripped for everyone else |
| `{p,SCC:17:2}...{/p}` | show only while a phase condition holds |
| `wa:eventName` | fires a named event WeakAuras can trigger on |

That last one matters: MRT can drive a WeakAura directly from a note line, which
is how the Kaze timer aura gets its cues.

## Role slots, not names

The ICC notes never name a player. They use slots:

```
Holy1  Holy2  Holy3  Prot  Ret  RetAM
```

The note's own instructions say to open Notepad and Ctrl+H each slot into a real
name. That is the manual step worth replacing: the slot list is stable, the names
change every raid.

`RetAM` vs `Ret` encodes a talent choice — whether the ret paladin took Aura
Mastery or Divine Sacrifice — which is why the pack ships two full sets of notes.

## Spell IDs used

| ID | Spell |
|---|---|
| 64205 | Divine Sacrifice |
| 31821 | Aura Mastery |
| 1044 | Hand of Freedom |
| 47875 | Healthstone (global call) |

## Why this matters for the Okanvil module

The notes are the hard part and they already exist, tuned by people who raid
this content. Nothing here needs inventing — the module's job is:

1. Hold the note per boss
2. Replace the role slots with the names of whoever is actually in the raid,
   using the spec detection Okanvil already has in `Modules/Inspect.lua`
3. Send the result to everyone's aura

Steps 1 and 3 are plumbing. Step 2 is the Ctrl+H the note's author tells you to
do by hand, done automatically and correctly every raid.
