# Loot council in Okanvil — plan

Written 2026-09-20, after surveying what the addon already has.

RATS runs a loot council through RCLootCouncil, but **does not use its voting**.
Decisions are made on voice or in officer chat. What the addon is actually used
for is narrower than RCLoot's feature list: ask each raider what an item is worth
to them, show the answers in one list, hand the item over.

That is the part worth building, and most of the pieces already exist.

---

## What exists today

| Piece | Where | Good enough as-is? |
|---|---|---|
| Addon comms, chunked transfers | `Core/Comms.lua` | yes, with caveats below |
| Loot capture, drop records, rolls | `Modules/Loot.lua` | yes |
| Master-loot give + award confirmation | `Loot.lua:2454-2548` | yes |
| Priority ladder from the website | `Modules/LootPrio.lua` | yes |
| `P.Names(prio, limit)` → ordered array | `LootPrio.lua:228` | this seeds the council order |
| Spec / role / gearscore of a raider | `Modules/Inspect.lua` | partly — see gaps |
| Officer identity | `Core/Util.lua:170` | partly — see gaps |
| Loot history per run | `Loot.lua`, sessions | yes |

### The one missing piece

**There is no way to ask a raider anything.** No popup on their client, no
request/response pair on the wire. Everything the addon knows about what a
raider wants comes from parsing `/roll` out of chat — a number, with no note and
no reason.

This is the centre of the feature and it is not large. `VERQ`/`VERR`
(`Comms.lua:288-326`) is already exactly this shape — broadcast a question, each
client whispers back, collect with a timeout — it is just hardcoded to version
strings.

---

## Two limits that will bite

**`C.Send` silently rejects payloads over 240 bytes.** `Comms.lua:91` returns
`false` and nothing else happens. A council roster of 25 responses is far past
that, so anything carrying a list must go through `C.SendBig` (chunks at 180
bytes, 0.35s apart — `Comms.lua:187-188`).

**`C.On` allows one handler per message type**, last registration wins
(`Comms.lua:81`). A council type must not collide with the existing ones:
`BIG`, `VERQ`, `VERR`, `LOOT`, `PRIOV`, `PRIOQ`, `NOTEV`, `NOTESEL`, `NOTEWHO`,
`NOTEACK`, `NOTEREQ`, `NOTEQ`.

**The mini roll window is 270px wide** (`LootRoll.lua:34`). A council board with
five columns does not fit in it. This needs its own frame.

---

## What to build, in order

### Stage 1 — a generic ask/collect helper

Not council-specific. Generalise the `VERQ`/`VERR` shape into something any
module can use:

```lua
Comms.Ask(type, payload, opts)  -- broadcast a question, collect replies
  -- opts: { timeout = 20, onReply = fn(sender, ...), onDone = fn(replies) }
Comms.Answer(type, fn)          -- register what this client replies with
```

Every reply needs a **round id**. Nothing on the wire carries session identity
today, so two bosses in a row — or one re-broadcast — would mix answers
together. The round id is what keeps them apart.

**Test it alone**, with two clients, before anything is built on top. The wire
is where this addon has failed silently before, and a round of council that
half-arrives is worse than none.

Ship this stage on its own. It also replaces the hand-rolled
`NOTEWHO`/`NOTEACK` in `NotesSync.lua` eventually.

### Stage 1b — who gets asked

The council opens on an item and only the people who **can use it** are asked.
A rogue is not offered a plate helm; a hunter is not asked about a spellpower
staff they cannot weigh up.

This is decided on the **raider's own client**, not the leader's. The popup
arrives for everyone in the raid and each client decides whether to show it.
Two reasons: the leader would otherwise need everyone's class and spec before
asking (and `Inspect` cannot deliver 25 scans mid-boss —
`Inspect.lua:213-230`), and the raider's client knows its own class for free.

Three filters, cheapest first:

**1. Armour type.** One armour class per class, in WotLK — a rogue only ever
wants leather. The table exists on the RATS website already and needs porting
into the addon as data.

**2. Class restriction on the item.** `"Classes: Rogue"` and similar appear in
the tooltip, which the drop record already captures as `dp.tip`
(`Loot.lua:224-250`). If the line is there, it is the whole answer.

**3. Weapon proficiency.** From `GetItemInfo`'s type/subtype — a priest cannot
use an axe whatever its stats say.

What is explicitly **not** filtered:

- **Stats.** A spellpower plate item is for a holy paladin and a ret paladin
  will still ask; that is a conversation, not a rule. Filtering on stats is
  where this stops being helpful and starts being wrong.
- **Off-spec.** A resto shaman may want a dps weapon for their elemental set.
  The response list already has an Off-spec answer for exactly this.
- **Tokens and fragments.** A Vanquisher's Mark is for three classes; the
  tooltip says so and filter 2 handles it.

**An escape hatch is required.** Any raider can open the round manually —
a `/okcouncil` or a button on the minimap toast — and answer for an item their
client filtered out. The filter is a convenience, never a lock: the first time
it is wrong about a legendary fragment or a server-custom item, the person it
excluded must still be able to put their hand up.

The leader's board shows who was **asked** as well as who answered, so a
raider missing because of a filter is visible rather than silently absent.

### Stage 2 — the raider side

#### What opens a round

The master looter opens the corpse and the council starts — that is the moment
everything is on screen and nobody has walked off yet.

```
loot window opens (master loot)
        │
        ├─ every epic / configured-threshold item in it
        │
        └─ one round per item, broadcast at once
                 │
                 └─ each raider's client decides whether to show it  (1b)
```

Three ways a round begins, in the order they matter:

1. **Automatic**, on the loot window. `Loot.lua` already fires `onLootWindow`
   the instant a corpse opens with items (`LootRoll.lua` hangs the mini roll off
   it), so the hook exists. Opt-in per guild, and gated on the quality threshold
   the Loot module already has — nobody wants a council round on a green.
2. **From the mini roll**, one item at a time: a `Council` button beside the
   existing `Start roll` buttons. For the item that needs it when the rest do
   not.
3. **Manually**, `/okcouncil [item link]`, for an item already in the bags —
   the BoE someone is holding, or a round re-opened because half the raid was
   dead when it first went out.

**Automatic is the default but must be switchable off.** A guild that wants to
call each item by hand should not have five popups fire on every kill.

#### The popup

Small, and gone in one click — a raider is mid-fight or looting, not filling in
a form.

```
┌──────────────────────────────────────────────────┐
│  Loot council                              0:18  │
│                                                  │
│  ⬛ [Deathbringer's Will]                        │
│     Deathbringer Saurfang · Trinket              │
│                                                  │
│  ┌──────┐ ┌────────────┐ ┌───────┐ ┌─────┐ ┌────┐│
│  │ BIS  │ │ Big upgrade│ │ Minor │ │ OS  │ │Pass││
│  └──────┘ └────────────┘ └───────┘ └─────┘ └────┘│
└──────────────────────────────────────────────────┘
```

- The **timer** counts down to the auto-pass. It is the only pressure: a raider
  who is dead, afk or loading does not stall the council.
- The **item** is a real link — hovering shows the tooltip, shift-click links it
  to chat, like anywhere else in the game.
- Under the name: the boss it came from and the slot, because "Trinket" answers
  half the question on its own.

After answering, the popup collapses to a line that stays a few seconds:

```
┌──────────────────────────────────────────────────┐
│  Sent: Big upgrade  ·  [Deathbringer's Will]     │
└──────────────────────────────────────────────────┘
```

That line exists because a popup that just vanishes leaves the raider unsure
whether the answer went. It also carries an **undo** while the round is still
open — misclicking Pass on your BIS is the one mistake worth being able to take
back.

Rules:
- **Never steals keyboard focus.** A captured EditBox eats WASD; this has
  killed someone before.
- Auto-passes on timeout rather than waiting forever.
- One popup at a time; several items open together queue up, and the header
  says `2 of 3` so the raider knows more is coming.
- A raider who wants nothing all night can mute the round from the popup
  (`Pass everything this boss`), rather than clicking Pass five times.

#### What a raider sees the rest of the time

Nothing. No nav row, no window, no board. The popup is the whole feature on
their client — it appears, they answer, it is gone.

The one exception is the **fight window analogue**: if RATS wants raiders to see
where they sit, the popup can carry their own prio line:

```
│     Deathbringer Saurfang · Trinket               │
│     You are 3rd on the list for this              │
```

That is open question 4. It explains the decision before an argument starts, or
it starts one earlier — RATS decides which.

### Stage 3 — the council board

A new window, officer-only. Wider than the mini roll (which is 270px and cannot
grow), because this is a table.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ⚖ Loot council                     8 answered / 25      0:12    [Close all] │
├─────────────────────────────────────────────────────────────────────────────┤
│  ▸ [Deathbringer's Will]   Saurfang · Trinket              3 want it        │
│  ▸ [Shadowfrost Shard]     Saurfang · Fragment             reserved         │
│  ▾ [Bryntroll, the Bone Arbiter]  Saurfang · 2H Axe        2 want it        │
├─────────────────────────────────────────────────────────────────────────────┤
│  PLAYER         WANTS          PRIO      SPEC / GEAR      RECENT            │
│ ───────────────────────────────────────────────────────────────────────────│
│  Kobee          BIS            #1        Combat  5.8k     —                 │
│  Grokara        Big upgrade    #2        Combat  5.6k     —                 │
│  Foug           Off-spec       #5        Unholy  5.9k     Vanquisher (1d)   │
│  Tchilly        Pass           —         Fire    5.7k     —                 │
│  Yahmom         —              #3        Frost   5.5k     —                 │
│ ───────────────────────────────────────────────────────────────────────────│
│  [Give to Kobee]          [Announce list]        [Disenchant]   [Skip]      │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Reading the board.** One row per raider who could answer, sorted by the prio
ladder — the order the website already decided — not by who clicked first.

- `Yahmom` has a dash under WANTS: has not answered yet. Still listed, because
  "who has not answered" is as useful as who has.
- `Tchilly` answered Pass and stays visible, greyed. Removing him would make the
  council wonder whether he was asked.
- `Foug` is the row this whole feature exists for: he wants it off-spec, he is
  fifth on the list, and he took the Vanquisher token yesterday. Nobody had to
  remember that.

**Columns, and where each comes from:**

| Column | Source | Notes |
|---|---|---|
| Player | the response, class-coloured | `L.ClassColorName` |
| Wants | stage 2 | `—` = no answer yet |
| Prio | `P.Names(rec.p)` — index of this name | `—` = not on the list |
| Spec / gear | `Inspect.M.Info(name)` | stale is marked, not hidden |
| Recent | loot history, this run + this lockout | the age is what matters |

**Actions.** The primary button names the person the board thinks is next —
top of the prio among those who want it — but it is a suggestion in a button,
not a decision. Clicking any row changes who the button names.

- `Give to <name>` → the existing `L.AwardWinner` path, master-loot give and
  all its confirmation handling (`Loot.lua:2454-2548`).
- `Announce list` → posts the candidates to officer chat, for the voice call.
- `Disenchant`, `Skip` → the two endings that are not an award.

**No votes, no quorum, no tally.** RATS decides by talking. The board's job is
to have the facts on screen while they do.

#### Officer vs raider, side by side

| | Raider / Sewer | Officer |
|---|---|---|
| Council opens | popup with the item and the buttons | board opens with every item of the kill |
| During | nothing after answering | live count, rows filling in |
| Sees others' answers | no | yes, all of them |
| Sees the prio | own position only, if enabled | full ladder |
| Sees loot history | no | recent wins per candidate |
| Can award | no | yes |
| Nav entry | none | `Loot > Council`, or the marks bar |

The asymmetry is the point. A raider answers one question about one item. An
officer needs every fact about every candidate at once.

### Stage 4 — record the decision

`L.AwardWinner(id, winner, topRoll, spec)` has no notion of a council award
(`Loot.lua:2533`). Add the response and the reason to the drop record, so the
history and the website export can tell "won a roll" from "council gave it to
them, they answered BIS".

---

## Deliberately not doing

**Talking to RCLootCouncil.** It would mean speaking its internal protocol,
which is undocumented and changes between versions. It would be the most fragile
part of the whole feature and it would break on someone else's release.

**Voting, quorum, blind votes.** RATS decides by voice. Building a voting system
nobody uses is how RCLoot ended up bigger than what it is used for.

**Filtering on stats, spec or item level.**

Stage 1b filters hard: plate never reaches a cloth wearer, an axe never reaches
a priest. That is the same line RCLootCouncil draws, and for the same reason —
a popup for an item you cannot equip is screen clutter during a fight.

It stops at *cannot equip*. Spellpower plate still reaches every paladin,
because the ret may want it for their holy set; a dps weapon still reaches the
resto shaman building an elemental offspec. The response list already has an
Off-spec answer for exactly that, and a filter that guesses at intent removes
the person who had a reason nobody asked about.

The rule: **the client hides what the character could never wear. Everything
softer than that is the council's call.**

---

## Design choices worth arguing about

Three places where the mock above picked one option and the other is defensible.

### A. Where the officer board lives

**As drawn: its own window.** Opens on the kill, closes when the last item is
decided. Sits next to the mini roll rather than replacing it.

*The alternative:* a tab inside the Loot page. Fewer windows, but it means
opening the hub mid-raid and the board competing with the rest of that page for
width. The mini roll exists as a floating window for exactly this reason.

### B. What the raider popup costs them

**As drawn: five buttons, one click, auto-pass on a timer.**

*The alternative:* no popup at all — the raider types `/roll` as they do now,
and the board reads the rolls. Zero disruption, nothing new to learn, works for
people without the addon. But it loses the whole point: a roll is a number, not
"this is my BIS and I have never had one".

A middle option: popup for people with the addon, `/roll` still parsed for
everyone else, both feeding the same board. More code, but nobody is locked out
on the night someone forgot to install it.

### C. How much the raider is told

**As drawn: their own prio position, and nothing else.**

*The alternative A:* tell them nothing. The council decides, the result is
announced. Least friction on the night.

*The alternative B:* show them the full board, read-only, after the decision.
Most transparent, and the loudest — everyone can now see they were second.

RATS already publishes the ladder on the website, so hiding it in the addon
buys nothing; that argues for at least the "you are 3rd" line.

---

## Open questions

1. **Response set** — is `BIS / Big upgrade / Minor / Off-spec / Pass` right, or
   does RATS use different words?
2. **Who sees the board** — `U.isOfficer` is guild-rank only
   (`Util.lua:170`), so a pug or a trusted non-officer cannot be on the council.
   Is that acceptable, or is a council roster needed?
3. **Timeout** — how long does a raider get to answer before it auto-passes?
4. **Does the raider see the prio?** Showing it explains the decision. Hiding it
   avoids an argument before one is needed. `canSeePrio` (`Util.lua:240`)
   currently blocks non-officers entirely.

---

## Gaps found in the survey, for reference

Things a fuller council would need that do not exist. None blocks the plan
above; they are listed so the next session does not rediscover them.

- **No class proficiency table in the addon.** Stage 1b needs it: which armour
  type each class wears, which weapons it can hold. The data exists on the RATS
  website (the fair-loot metric uses it) and has to be ported in as a data file
  — `Modules/Proficiency-Data.lua` alongside the other `*-Data.lua`.
- No per-slot gear retained — `Inspect` stores aggregate ilvl/GearScore only
  (`Inspect.lua:250`), so "what are they wearing in that slot right now" is not
  available.
- `Inspect`'s queue is strictly serial, one in flight (`Inspect.lua:213-230`),
  and out-of-range raiders are silently skipped. Scanning 25 people mid-boss is
  not feasible through it — a raider pushing their own gear over comms would be.
- No council-member roster; only guild rank.
- No multi-copy council flow. `dp.winners` exists for roll-offs
  (`Loot.lua:1855`) but there is no "three of these, three decisions".
- No council history — nothing records who asked for what, after the raid.
