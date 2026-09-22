# The Kaze timer WeakAura

The aura that turns a note into on-screen reminders. It reads the note, finds
the lines that are about you, and shows an icon and a countdown for each.

This is the aura's own documentation, kept here because the aura itself lives
in a WeakAuras string that nobody can search. Where the Okanvil build differs
from the original, it says so.

> **Okanvil:** the original reads its note from MRT. This build reads
> `Okanvil.Notes.Current()` instead, so the note is whichever one the addon has
> selected. Everything below still applies -- the note FORMAT is unchanged.

## Requirements

| | Addon | For |
|---|---|---|
| Required | Okanvil (was: MRT) | the note itself |
| Recommended | DBM **or** BigWigs | phase detection, for `p2` triggers |
| Optional | SharedMedia_Causese | the 3-2-1 countdown sound |

## How a line is built

Two parts: a **timer** that says WHEN, and an **input** that says WHAT and FOR
WHOM.

### The timer

| Written | Means |
|---|---|
| `{time:75}` | 75 seconds |
| `{time:1:10}` | 1 minute 10 |
| `{time:01:15}` | 1 minute 15 |
| `{time:02:30,p2}` | 2:30 into phase 2 (needs DBM/BigWigs) |
| `{time:00:30,SCC:347704:2}` | 30s after the **2nd** cast of spell 347704 |

Forms: `{time:ss}`, `{time:mm:ss}`, `{time:mm.ss}`, `{time:mm:ss,condition}`.

### Conditions

```
event:spellid:counter
```

| Part | Values |
|---|---|
| `event` | `SCC` `SCS` `SAA` `SAR` |
| `spellid` | the numeric id |
| `counter` | which occurrence; **0 means every one** |

`p2` triggers at the start of phase 2 instead, and needs DBM or BigWigs.

| Code | Combat-log event |
|---|---|
| `SCC` | SPELL_CAST_SUCCESS |
| `SCS` | SPELL_CAST_START |
| `SAA` | SPELL_AURA_APPLIED |
| `SAR` | SPELL_AURA_REMOVED |

`SCS` fires when the cast STARTS, so it buys you the cast time. `SAA` fires
once the aura has already landed.

### The input

The text after the tag. The aura matches it against your keywords to decide
whether the line is yours.

Rules worth knowing:

- **Double space** separates several inputs on one timer. Each gets its own icon.
- **Single space** keeps it as one input, and only the LAST `{spell:}` becomes
  the icon; the rest render inline as images.
- **Text before a hyphen (` - `) is ignored.** So never write your realm name
  (`Kazeshinu-Ravencrest`), and a label like `Use roar - Name` shows only `Name`.

### Put together

| Line | Result |
|---|---|
| `{time:20}Kazeshinu` | the text "Kazeshinu" |
| `{time:20}Kazeshinu {spell:77764}` | Roar's icon, text "Kazeshinu" |
| `{time:20,p2}Kazeshinu {spell:33891}  Kazeshinu {spell:740}` | two icons (double space), 20s into phase 2 |
| `{time:20}Kazeshinu {spell:33891} Kazeshinu {spell:740}` | ONE icon (single space) -- Tranq, with all the text run together |
| `{time:20,SAR:348805:1}\|cfffe7b09Kazeshinu\|r {spell:77764}` | Roar, 20s after aura 348805 first falls off |
| `{time:20}Use roar - \|cfffe7b09Kazeshinu\|r {spell:77761}` | "Use roar" is dropped -- it sits before the hyphen |
| `{time:20}\|cff3fc7ebSadmage\|r {spell:68252}` | shows for Sadmage, NOT for you |

> **Okanvil gotcha:** colour codes take SINGLE pipes -- `|cff...|r`. A note
> pasted out of MRT can carry doubled pipes (`||cff...||r`), and the aura then
> matches your name against `|Okanor|` instead of `Okanor`. The addon now
> unescapes them on the way out, but a stored note is cleaner fixed at source.

## Extras

| Written | Does |
|---|---|
| `%target` | replaced by the target of the triggering spell |
| `%caster` | replaced by its caster |
| `@PLAYERNAME` | that player's raid frame glows while the reminder is up |
| `{text}...{/text}` | the text inside is what gets displayed |
| `{ABCDEFG}` | anything in braces is not displayed |

## Keywords

Comma-separated, case-insensitive. A line shows only if it contains one of
them. The defaults:

```
{name},class:{class},group:{mygroup},spec:{spec},role:{role},everyone,type:{type}
```

| Keyword | Replaced by |
|---|---|
| `{name}` | your character name |
| `class:{class}` | your class, NO SPACES (`DeathKnight`) |
| `group:{mygroup}` | your raid group number |
| `spec:{spec}` | your spec (`Restoration`, `Frost`, ...) |
| `role:{role}` | `DAMAGER` / `TANK` / `HEALER` |
| `everyone` | the literal word |
| `type:{type}` | `Melee` / `Ranged` |

**Ignore keywords** work the other way: a line containing one is dropped even
if it would otherwise show.

## Options

| Option | Type | Does |
|---|---|---|
| Display Icon Spell Name | toggle | spell name under the icon |
| Display Icon Text | toggle | text beside the icon |
| Warn Duration | number | how far out the countdown starts |
| Delay Duration | number | how long it lingers after 0 |
| Disable WA When | selection | ties the aura to note-window settings |
| Enable Countdown 3,2,1 | toggle | sound countdown (needs SharedMedia_Causese) |
| TTS When < Time Left | number | speak when less than this remains |
| Enable TTS | toggle | text-to-speech on/off |
| TTS Message | text | the spoken format, see below |
| Matching Keywords | text | comma-separated, decides what shows |
| Ignore Keywords | text | comma-separated, decides what never shows |
| Disable Shared Note | toggle | ignore the shared note |
| Show ALL Shared Timers | toggle | ignore keyword filtering on it |
| Disable Personal Note | toggle | ignore the personal note |
| Show All Private Timers | toggle | ignore keyword filtering on it |

Options can also be set per spell id of the icon. Plain text counts as spell id 0.

### TTS message

Any value in the aura's state can be spoken by wrapping its name in braces, and
several can be listed in priority order. The default is:

```
{spellName:name} in {progress}
```

-- if `spellName` is empty it falls back to `name`.

| Variable | Is |
|---|---|
| `{name}` | the input text |
| `{spellName}` | the icon's spell name |
| `{spellId}` | the icon's spell id |
| `{unit}` | the player named by `@PLAYERNAME` |
| `{target}` | the target, when `%target` was used |
| `{caster}` | the caster, when `%caster` was used |
| `{progress}` | the time at which it spoke |

## Advanced settings in the note

A block inside the note itself, for swapping a name without rewriting the plan
-- a healer drops out and you replace them in one line rather than twelve.

```
kazestart
command1 arg1,arg2
command2 arg1,arg2,arg3
kazeend
```

Every line between `kazestart` and `kazeend` is a command.

| Command | Arguments | Does |
|---|---|---|
| `namereplace` | name1, name2 | name1 becomes name2 |
| `#nr` | name1, name2 | short for `namereplace` |

## Where this bites in practice

Two failures look identical from outside -- the line just sits there and never
counts down:

1. **The spell never fires at that difficulty.** Putricide's Volatile
   Experiment (72840/72842/72843) is the HEROIC intermission; on normal the
   transition is Tear Gas (71617). A note anchored to a heroic-only id waits
   forever on normal.
2. **The aura is holding an older copy of the note.** It re-reads on entering
   combat, so an edit made mid-fight is not seen until the next pull.

`/oknotes watch` records a pull's combat-log events into
`OkanvilNotesDB.log`, which survives the wipe and can be read out of
`SavedVariables\Okanvil.lua` afterwards. That says which of the two it was.
