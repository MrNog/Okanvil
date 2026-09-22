# WeakAura cast bars -- every id per ability

An Icecrown ability is numbered per difficulty, so a bar watching one id shows
at one raid size and nowhere else. Put ALL of them in the trigger's `or` boxes:
the ids that do not exist at the difficulty you are in simply never fire, so one
bar covers everything.

Read from three real logs (10N, 10HC, 25N) -- ids that were OBSERVED being cast,
not ids that merely exist in the client.

| bar | ids for the `or` boxes | caster |
|---|---|---|
| Marrowgar: Bone Storm | `69076` | Lord Marrowgar |
| Deathwhisper: Frostbolt Volley | `72905`, `72906`, `72907` | Lady Deathwhisper |
| Saurfang: Blood Nova | `72378`, `73058` | Deathbringer Saurfang |
| Rotface: Slime Spray | `69508` | Rotface |
| Rotface: Unstable Ooze Explosion | `69839` | Big Ooze |
| Festergut: Pungent Blight | `69195`, `71219`, `73031`, `73032` | Festergut |
| Putricide: Unstable Experiment | `70351`, `71966`, `71967` | Professor Putricide |
| Putricide: Volatile Experiment | `72842` | Professor Putricide |
| Putricide: Tear Gas | `71617` | Professor Putricide |
| Putricide: Volatile Ooze Adhesive | `70447`, `72836`, `72837` | Volatile Ooze |
| Putricide: Gaseous Bloat | `70672`, `72455`, `72832` | Gas Cloud |
| Lana'thel: Bloodbolt Whirl | `71772` | Blood-Queen Lana'thel |
| Sindragosa: Blistering Cold | `70123`, `71047`, `71048` | Sindragosa |
| Lich King: Infest | `70541`, `73779`, `73780` | The Lich King |
| Lich King: Remorseless Winter | `68981`, `72259`, `74270`, `74271`, `74273`, `74274` | The Lich King |
| Lich King: Defile | `72762` | The Lich King |
| Lich King: Quake | `72262` | The Lich King |
| Lich King: Fury of Frostmourne | `72350` | The Lich King |
| Lich King: Harvest Soul | `68980`, `74325` | The Lich King |

## Which id is which

| id | difficulty |
|---|---|
| `72905` | 10N |
| `72906` | 25N |
| `72907` | 10HC |
| `72378` | 10N/10HC |
| `73058` | 25N |
| `69195` | 10N |
| `71219` | 25N |
| `73031` | 10HC |
| `73032` | 25N |
| `70351` | 10N |
| `71966` | 25N |
| `71967` | 10HC |
| `72842` | 10HC only |
| `71617` | normal only |
| `70447` | 10N |
| `72836` | 25N |
| `72837` | 10HC |
| `70672` | 10N |
| `72455` | 25N |
| `72832` | 10HC |
| `70123` | 10N |
| `71047` | 25N |
| `71048` | 10HC |
| `70541` | 10N |
| `73779` | 25N |
| `73780` | 10HC |
| `68981` | 10N |
| `72259` | 10N |
| `74270` | 25N |
| `74271` | 10HC |
| `74273` | 25N |
| `74274` | 10HC |
| `68980` | 10N |
| `74325` | 25N |

## Two fixes beyond the ids

**The npc filter.** `Source NPC Id` is worth turning OFF on these. On 3.3.5a a
boss can report a VEHICLE guid rather than a creature one -- Putricide does --
and a bar filtering on npc id then only shows while you have the boss targeted.
Every spell id above is cast by that boss alone, so the filter buys nothing.

**One wrong npc id.** Valithria Dreamwalker is **36789** in the log, not 36791.
That bar could never have fired.

## Putricide on normal

Volatile Experiment (`72842`) is HEROIC only -- it never fires on normal, so that
bar staying dark there is correct, not broken. The normal phase change is Tear
Gas (`71617`); the oozes come from Unstable Experiment, which is `70351` on 10N
and `71966` on 25N.
