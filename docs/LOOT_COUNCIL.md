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
| **Announce → collect rolls → award**, whole loop | `Loot.lua:1874`, `2454` | **done; do not disturb** |
| Attributing a voice-called roll from chat | `Loot.lua:2285` | done |
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

| | | Ships alone? |
|---|---|---|
| **1** | A generic ask/collect helper on comms | yes |
| **1b** | Who gets asked — the eligibility filter | with 2 |
| **2** | The raider's frame | with 1b |
| **2b** | Surviving a reload | **before any raid sees it** |
| **2c** | Test mode | **before stage 3** |
| **3** | The council board | yes |
| **3b** | Council from the bags, with auto loot on | second phase |
| **4** | Recording the decision | yes |

2b and 2c are not polish at the end. A council that loses a raider to a reload
is the failure RATS already lives with in RCLootCouncil, and a feature that can
only be tested during ICC is one whose bugs are found by twenty-four other
people.

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

A token like Vanquisher's Mark names its three classes in the tooltip, so
filter 2 handles it.

**An escape hatch is required.** Any raider can open the round manually —
`/okcouncil` — and answer for an item their client filtered out. The first
time the filter is wrong about a legendary fragment or a server-custom item,
the person it excluded must still be able to put their hand up.

**A filtered client still replies.** It answers "not eligible" instead of
showing a popup, and that reply is what lets the board count `4 of 5` rather
than `4 of the whole raid`. Without it, silence would mean both "cannot use
this" and "has not answered yet", and the count that tells the council whether
it can decide would be worthless.

It also makes a filter mistake visible: the board can say who was skipped and
why, instead of the person simply not being there.

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

#### Asking the master looter first

When the raid forms — or when the loot method becomes master loot, or when the
ML changes — the new master looter is asked once:

```
┌──────────────────────────────────────────────────┐
│  You are the master looter.                      │
│  Use loot council tonight?                       │
│                                                  │
│          [ Yes ]              [ No ]             │
└──────────────────────────────────────────────────┘
```

This turns the council **buttons** on, not the council itself. Nothing is asked
of the raid until the ML presses Ask on an actual item — saying yes here just
means the tools are on the table.

That matters because rolls do not go away: a council night still has pieces the
ML calls as a plain roll, so both rows sit in the mini roll and each item goes
one way or the other. `No` hides the council row entirely and the mini roll is
exactly what it is today.

It is a question rather than a setting because whether tonight is a council
night is a decision about tonight. A stored setting is the one that silently
does the wrong thing three weeks later.

#### The popup

Everything the boss dropped that this character can use, in one frame, one row
per item. A raider choosing between two trinkets has to see both — asked one at
a time they answer differently than asked together.

```
┌────────────────────────────────────────────────────────────────┐
│  Loot council · Deathbringer Saurfang                    0:42  │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ⬛ [Deathbringer's Will]          Trinket                     │
│      ┌─────┐ ┌────────┐ ┌───────┐ ┌─────┐ ┌──────┐             │
│      │ BIS │ │ Upgrade│ │ Minor │ │ OS  │ │ Pass │             │
│      └─────┘ └────────┘ └───────┘ └─────┘ └──────┘             │
│                                                                │
│  ⬛ [Bryntroll, the Bone Arbiter]  2H Axe                      │
│      ┌─────┐ ┌────────┐ ┌───────┐ ┌─────┐ ┌──────┐             │
│      │ BIS │ │ Upgrade│ │ Minor │ │ OS  │ │ Pass │             │
│      └─────┘ └────────┘ └───────┘ └─────┘ └──────┘             │
│                                                                │
│  ⬛ [Vanquisher's Mark]            Token · Gloves      ✓ BIS   │
│                                                                │
├────────────────────────────────────────────────────────────────┤
│  Unanswered items pass when the timer runs out.     [Pass all] │
└────────────────────────────────────────────────────────────────┘
```

- The **timer** is the only pressure. It runs for the whole frame, not per
  item, and anything still unanswered passes when it hits zero — a raider who
  is dead, afk or loading does not stall the council.
- An **answered row collapses** to its answer (`✓ BIS`), so what is left to do
  is what is still showing buttons. Clicking the answer re-opens the row to
  change it, while the round is open.
- **Items are links** — hover for the tooltip, shift-click to put one in chat,
  the same as anywhere else in the game.
- The **slot** is next to the name, because "Trinket" or "2H Axe" answers half
  the question before the tooltip is even read.
- **Rows are tinted from the raider's own gear**, the way RCLootCouncil does
  it (`lootFrame.lua:117-151`). Nothing here comes from the guild's priority
  list — this is the raider's information about themselves:

```
│  ⬛ [Deathbringer's Will]   Trinket                              │  green
│  ⬛ [Bryntroll, the Bone Arbiter]  2H Axe   You already have this│  red
```

  **Red** when they are already wearing it — the one case where answering at
  all is a mistake, and the tint stops it before the click.

  **Green** for a BiS item, if a BiS list exists to check against. RCLoot reads
  one from the `RaidAssistBisList` addon; Okanvil would need its own, which is
  a feature of its own and not part of this plan.

  Red first: it needs no list, it works for everyone tonight, and it prevents
  a real mistake rather than flagging a nice-to-have.
- **`Pass all`** for the raider who wants nothing off this boss: one click
  instead of five.

Rules:
- **Never steals keyboard focus.** A captured EditBox eats WASD; this has
  killed someone before.
- Only items this character can equip appear (stage 1b), so the frame is
  usually two or three rows, not the whole kill.
- If every item was filtered out, no frame opens at all.

##### The priority list never reaches a raider

`syncAllowed()` (`LootPrio.lua:916`) sends the ladder to officers only, and
`canSeePrio` (`Util.lua:240`) gates reading it the same way. The council changes
nothing about that: no position, no flag, not even *that* they are on it.

Knowing you are queued for an item changes how you answer, and the order is the
council's to weigh. Everything the raider's frame shows comes from their own
gear.

#### What a raider sees the rest of the time

Nothing. No nav row, no window, no board. The frame is the whole feature on
their client — it appears, they answer, it is gone.

### Stage 2b — surviving a reload

This is where RCLootCouncil visibly fails in RATS raids, in two ways that have
both been seen more than once:

- the council breaks and the loot method has to be flipped off master loot and
  back on to get it working again;
- a raider never gets the prompt at all, and nobody notices until the item is
  being handed out.

Both are the same root cause: **round state lives in memory on several clients
at once, and a reload wipes one of them.** A raider who `/reload`s between the
broadcast and their answer is simply gone; the leader's board waits forever on
someone whose client has forgotten the round exists.

Four rules, and none of them is optional.

**1. The leader's rounds are saved to disk, not held in memory.**
An open round survives `/reload`, a disconnect, and a crash. On load, any round
that is still open is restored and the board reopens on it. Everything in the
addon that has ever been lost — the note being typed, the farm run that was
never banked — was lost because it only existed in a Lua table.

**2. A raider who reloads asks for what they missed.**
On `PLAYER_ENTERING_WORLD`, if there is a group and a known master looter, the
client asks *"is a round open?"* and is sent whatever it needs. This is the
same shape as the notes module's zone-in request (`NotesSync.lua`), and it is
what fixes "the prompt never appeared" without anyone having to notice.

**3. The leader re-broadcasts, rather than waiting.**
An open round is re-sent every ~15 seconds to clients that have not answered.
An addon message can be dropped with no error and no retry (`C.Send` is
fire-and-forget, `Comms.lua:88`), so one lost packet must not cost the round.
Answers carry the round id, so a re-broadcast to someone who already answered
changes nothing.

**4. The master looter can change mid-raid.**
The ML flipping is normal — it is also RATS's current workaround when RCLoot
breaks. An open round belongs to the round id, not to whoever happens to be ML
at that second. When the ML changes, the new one is offered the open rounds;
declining closes them cleanly rather than leaving twenty-five clients waiting
on someone who is no longer looting.

**The escape hatch.** `/okcouncil status` prints what this client thinks is
open, and `/okcouncil resend` re-broadcasts from the leader. When something
does go wrong at 22:30 on a Tuesday, the answer has to be one command, not
"everyone reload".

### Stage 2c — test mode

`/okcouncil test 3` opens a real round on three items without a boss, without
master loot, and without a raid.

RCLootCouncil does this and the trick is worth copying exactly
(`core.lua:804-834`): it **uses the gear you are wearing** as the test items.
No fixture list to maintain, no item that turns out not to be cached, and the
armour type is right for your class — which is what stage 1b's filter is being
tested against. A hardcoded fallback list covers a naked character.

What test mode must do:

- Run the **real path**: the same broadcast, the same round ids, the same
  raider frame, the same board. A test that takes a shortcut past the wire
  tests the half that was never broken.
- Work **solo**, so the whole thing can be exercised before asking anyone else
  to log in. The leader sees the board; their own client answers as the one
  raider.
- Work **in a party of two**, which is the real test — that is where the wire,
  the reload recovery and the per-item count are actually proven.
- **Never touch real loot.** No master-loot give, no history entry, no export.
  A test award prints what it would have done.
- Say so, loudly and constantly. The board header reads `TEST` in the accent
  colour, and every chat line it prints is prefixed. The worst outcome here is
  a real raid running in test mode and the loot never being given out.
- End on `/okcouncil test off`, and on its own at the next real boss.

This is stage 2c because it has to exist **before** stage 3, not after. Every
bug found today was found by you, in a screenshot, after a raid — the wire is
where this addon fails silently, and a council round that half-arrives during
ICC is worse than no council at all.

---

### Stage 3 — the council board

A new window, officer-only. Wider than the mini roll (which is 270px and cannot
grow), because this is a table.

**The items are icons down the outside edge**, not rows inside the window —
the trick RCLootCouncil uses (`votingFrame.lua:671-710`). The whole window is
then one item's candidates, and the table gets the full width instead of
sharing it with a list of items that is mostly not being looked at.

```
                                                                      ┌────┐
┌────────────────────────────────────────────────────────────────┐    │ ▣  │ ← yellow: open
│ ⚖ [Bryntroll, the Bone Arbiter]   2H Axe           4/5   0:12  │    ├────┤
│    prio  Kobee > Grokara >> Yahmom > Setanegra >> Foug ...      │    │ ▣  │ ← green: awarded
├────────────────────────────────────────────────────────────────┤    ├────┤
│  PLAYER         WANTS          PRIO   SPEC / GEAR    RECENT     │    │ ▣  │ ← white: waiting
│ ───────────────────────────────────────────────────────────────│    ├────┤
│  Kobee          BIS            #1     Combat  5.8k   —          │    │ ▣  │
│  Grokara        Big upgrade    #2     Combat  5.6k   —          │    └────┘
│  Foug           Off-spec       #5     Unholy  5.9k   Vanq (1d)  │
│  Tchilly        Pass           —      Fire    5.7k   —          │
│  Yahmom         —              #3     Frost   5.5k   —          │
│ ───────────────────────────────────────────────────────────────│
│  [Give to Kobee]                        [Disenchant]    [Skip]  │
└────────────────────────────────────────────────────────────────┘
```

Each icon is the item's own texture, 40px, with a coloured border saying where
it stands:

| Border | Meaning |
|---|---|
| Yellow | the item on screen right now |
| Green | already awarded |
| White | still waiting on a decision |

Hovering an icon shows its tooltip; clicking switches the whole board to it.
They stack downward and start a second column after ten, so a full ICC kill
does not run off the bottom of the screen.

This is worth copying wholesale. It also gives the officer the one thing a list
of items inside the window could not: **a glance tells you how much is left**,
without reading anything.

**The count is per item, not per raid.** `4/5` means four of the five people
whose clients were asked about *this* item have answered — one is still out. A
raid-wide `8/25` would be meaningless: most of those 25 were never asked,
because a 2H axe never reached the healers.

This is the number that says whether the council can decide yet. With `4/5` on
screen, waiting for the fifth is a choice; with `8/25` nobody can tell whether
anyone is still thinking.

The denominator comes from the eligibility filter (stage 1b): the leader knows
how many clients were asked because each one answers — including the ones that
filtered the item out, which reply "not eligible" rather than staying silent.
Silence has to mean *not answered yet*, or the count cannot be trusted.

**Someone without the addon never replies at all**, so they would sit in the
denominator forever and the count would never complete. The board has to know
who is running Okanvil before it can count — the `Who has them?` audit in the
notes module already does exactly this (`NotesSync.lua`), and the council needs
the same roster. Anyone without the addon is listed separately: *"3 raiders
have no addon"*, decided the old way.

**Reading the board.** One row per raider who could answer, sorted by the prio
ladder — the order the website already decided — not by who clicked first.

- `Yahmom` has a dash under WANTS: has not answered yet. Still listed, because
  "who has not answered" is as useful as who has.
- `Tchilly` answered Pass and stays visible, greyed. Removing him would make the
  council wonder whether he was asked.
- `Foug` is the row this whole feature exists for: he wants it off-spec, he is
  fifth on the list, and he took the Vanquisher token yesterday. Nobody had to
  remember that.

**The full ladder sits in the header**, under the item's name — the same string
the website produced, class-coloured through `P.Line` (`LootPrio.lua:370`). The PRIO column gives each
candidate's position; the ladder gives the shape of the whole decision — who is
in the same band as whom (`>`), and where it steps down (`>>`). A council
weighing a #2 against a #3 needs to know whether those two are level or a tier
apart, and a number on its own does not say.

It also shows the people who have **not** answered and are not in the raid at
all, which is the difference between "nobody ahead of Kobee wants it" and
"nobody ahead of Kobee is here tonight".

A real ladder runs to a dozen names and will not fit on one line. It truncates
at the window's width with a `...`, and the full string is in the tooltip —
truncation is right here because the names that matter are at the front.

**Columns, and where each comes from:**

| Column | Source | Notes |
|---|---|---|
| Player | the response, class-coloured | `L.ClassColorName` |
| Wants | stage 2, **coloured by response** | `—` = no answer yet |
| Prio | `P.Names(rec.p)` — index of this name | `—` = not on the list |
| Spec / gear | `Inspect.M.Info(name)` | stale is marked, not hidden |
| Recent | loot history, this run + this lockout | the age is what matters |

**Actions.** The primary button names the person the board thinks is next —
top of the prio among those who want it — but it is a suggestion in a button,
not a decision. Clicking any row changes who the button names.

- `Give to <name>` → the existing `L.AwardWinner` path, master-loot give and
  all its confirmation handling (`Loot.lua:2454-2548`).
- `Disenchant` → see below.
- `Skip` → decided outside the addon, or not decided tonight. The round closes
  and the item stays undecided, so the picker can offer it again later.

#### Disenchant

Nobody wanted it, so it becomes a shard. Two things have to happen, and only
one of them is a give.

**The record.** The drop is marked `de = true` rather than given an owner. The
history and the website export already understand this — the export sends the
sentinel `"Disenchant"` in the player field so the hub excludes it from win
counts (`Loot.lua:2877-2879`), and the history row prints
`-> Disenchant` in purple (`Loot.lua:2930`).

**There is a bug waiting here.** `d.de` is read in four places and **written in
none**. The reader was built for Blizzard's native Disenchant roll, which never
arrives under master loot — so today every disenchanted item is recorded as
belonging to whoever shattered it, and the hub counts it as a win. The council's
Disenchant button is the first thing that would ever set the flag.

**The give.** The item still has to reach an enchanter. Under master loot with
the window open, that is a normal `GiveMasterLoot` to whoever is disenchanting
— so the button needs to know who that is:

- A **disenchanter is named** for the raid, once, the way the master looter is.
  The button then reads `Disenchant → Tchilly` and gives it to them.
- With nobody named, it asks the first time and remembers for the night.
- With auto loot on and the corpse gone, there is no give — the item is already
  in someone's bags. The button only writes the record, and says so.

`de = true` and a `receivedBy` are not exclusive: the shard went *to* someone,
and knowing who held it matters for the same reason `heldBy` does. What the flag
changes is that it does not count as loot they won.

**No votes, no quorum, no tally.** RATS decides by talking. The board's job is
to have the facts on screen while they do.

#### Officer vs raider, side by side

| | Raider / Sewer | Officer |
|---|---|---|
| Council opens | popup with the item and the buttons | board opens with every item of the kill |
| During | nothing after answering | live count, rows filling in |
| Sees others' answers | no | yes, all of them |
| Sees the prio | nothing at all | full ladder |
| Sees loot history | no | recent wins per candidate |
| Can award | no | yes |
| Nav entry | none | `Loot > Council`, or the marks bar |

The asymmetry is the point. A raider answers one question about one item. An
officer needs every fact about every candidate at once.

### Stage 3b — choosing what goes to council (second phase)

Everything above assumes the loot window is open and the leader is deciding
item by item. Real RATS raids do not always work that way — with **auto loot**
on, the corpse empties itself by rule: BoP to the master looter, BoE to
whoever is collecting them, fragments and shards to someone else again.

The items are then in bags, the loot window is shut, and the council still has
to happen.

#### Council and rolls live side by side

The two are **not** modes of the night. A master looter running council will
still say *"this one just roll"* for a piece nobody is arguing about, and both
have to be one click away on the same item.

So with council on, the ML row becomes:

```
  ┌──────────────┐ ┌────────┐ ┌──────┐ ┌──────┐
  │ Ask this one │ │  Pick  │ │ Roll │ │ Stop │
  └──────────────┘ └────────┘ └──────┘ └──────┘
```

- **Ask this one** — opens a council round on the selected item.
- **Pick** — ticks several and asks about them in one round.
- **Roll** — announces a plain roll on this item, no spec split.
- **Stop** — closes whatever is open on it.

`Ask` rather than `Send`, because it is the same verb as `Comms.Ask` and it
says what happens next: the raid is asked, and answers come back.

**One Roll button, not MS / OS / Free.** Under council the split means nothing
— the council decides who gets it, and someone rolling "off-spec" is a line in
the response list, not a separate roll.

The announce is just the item:

```
Roll [Deathbringer's Will]
```

No `FREE`, no `/roll (1-100)`. The existing `free` message spells the range out
(`Loot.lua:1711`) because a guild rolling MS against OS needs to say which is
which; under council there is only one kind of roll and everyone knows how to
type it.

It reuses `L.StartRoll(link, "free")` unchanged and collects the same way.

The message needs its **own template**, not the `free` one — a guild using both
would otherwise have the council's Roll and the plain Free roll share a line,
and editing one would change the other. `L.RollMsg`/`SetRollMsg` are keyed by
mode (`Loot.lua:1714-1721`), so a `council` key alongside `ms`/`os`/`free` is
the whole change, plus a fourth box on the Loot settings page.

The four-button row (`LootRoll.lua:654-657`) is what a guild without council
uses, and that guild sees the mini roll exactly as it is today.

**There is a third way, and it must keep working.** The master looter often
decides an item entirely on voice — *"Kobee and Grokara, roll for it"* — and
hands it over from the loot window. No round, no managed roll, nothing pressed
in the addon at all.

Okanvil already handles this: `/roll` lines are read from chat and
`L.AttributeByRoll` (`Loot.lua:2285`) records the winner on its own. The
council must not get in the way of it — an item with no open round and no
managed roll behaves exactly as it does today, and the two rolls that went past
in chat still land on the right drop.

So the three paths are:

| How the item is decided | What the addon does |
|---|---|
| Council round | asks the raid, board, award |
| Managed roll (one button under council) | announces, collects, award |
| **Called on voice** | watches chat, attributes the winner |

**The managed roll already works end to end** and the council changes none of
it. `L.StartRoll` posts the item link to the announce channel
(`Loot.lua:1886-1887`), the `/roll` lines land on that drop and show as roll
rows under it, and clicking the winning row calls `L.AwardWinner` — which does
the master-loot give from the corpse and watches it land
(`Loot.lua:2454-2548`).

That loop is the thing the council is being built alongside, not on top of.
Nothing in stages 1-4 may change how it behaves.

**An item takes one path at a time.** Starting a roll on something with an open
council round closes the round first and says so; asking the council about
something being rolled on does the same in reverse. Two ways of deciding one
item at once is how a raid ends up with two winners.

The voice path needs no such guard — it is passive, and it is the fallback
whenever the other two are not used.

#### Picking happens in the mini roll

Because rolls and council share the same item, they have to share the same
list. A separate picker window — the way RCLootCouncil does it
(`sessionFrame.lua:114-143`) — would mean the ML deciding *"roll this, council
that"* while looking at two copies of the same loot in two windows, and having
to keep track of which is which.

The cost is real and worth naming: `LootRoll.lua` is 1400 lines already
juggling an accordion, roll rows, a trade timer and the ML button row, and it
works every raid night. Adding a checkbox column and a council row is another
state threaded through all of it.

It is still the right trade. Two windows showing the same boss's loot, each
able to act on it differently, is worse than one window with one more column.

```
┌──────────────────────────────────┐
│  Saurfang            ◂ 2 of 4 ▸  │
├──────────────────────────────────┤
│ ☑ ⬛ [Deathbringer's Will]       │
│      Trinket                     │
│ ☑ ⬛ [Bryntroll, the Bone Arb…]  │
│      2H Axe                      │
│ ☐ ⬛ [Shadowfrost Shard]         │
│      asked                       │
│ ☐ ⬛ [Cryptmaker]                │
│      Kobee                       │
├──────────────────────────────────┤
│  Council                         │
│  [Ask this one] [Pick] [Stop]    │
└──────────────────────────────────┘
```

Everything undecided ticks itself. Untick what should not go, press **Pick**,
and one round carries all of them — which is the single frame stage 2 asks for.

- An item already **awarded** shows who has it, unticked — including one the
  addon attributed from chat rolls after a voice call, which is the common
  case and needs no council round at all.
- One already **asked about** is marked `asked`, unticked — re-asking is a
  deliberate tick. See problem 1.
- The boss tabs the mini roll already has are the scope control: a tab is one
  boss, and an `All` tab is the whole run. No extra dropdown.
- **My bags** is the one thing the mini roll cannot show, because those items
  never came off a corpse it watched. It is a tab, next to the bosses.
- Dropping an item link on the window adds it, for anything never captured.

Either way the **board is its own window** — one item's candidates, with the
item icons hanging off its edge. The 270px mini roll could never hold a
candidate table, whatever happens to the picking.

#### Two problems this creates

**1. An item that went to council and was not awarded.**
It is still undecided, so a sweep picks it up again and the raid answers a
second time on something they already answered.

The picker handles the common case: a drop remembers the round it was in, and
anything carrying one is listed `asked` and **unticked**. Re-asking is then a
deliberate tick, not a side effect.

What is still open is what the *raider* sees on a re-ask. Their previous answer
is known — does the frame come back pre-filled with it, or blank? Pre-filled is
kinder and risks them not noticing they were asked again; blank is honest and
costs the answer of anyone who has walked away.

**2. With auto loot, the give has to be recorded by hand.**
Under master loot with the window open, `L.AwardWinner` does the give and the
addon watches it land (`Loot.lua:2454-2548`). With auto loot the item is
already in someone's bags, so there is nothing to give — the leader trades it
later, and the addon cannot see a trade.

So the council decision has to *be* the record: choosing a winner writes
`receivedBy` directly, rather than waiting for a hand-over it will never
observe. That is a change to what an award means, and it is the same gap that
made the loot history read "Jiskob" against every item of a night.

*Also not designed yet.* The pieces exist — `heldBy` already distinguishes
carrying from owning — but the flow from "council picked Kobee" to "the history
says Kobee has it, and Jiskob still physically holds it" needs writing down.

---

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

**Guessing at intent.** The filter hides what a character cannot equip and
stops there — a paladin still gets asked about spellpower plate, because the
ret may want it for their holy set, and the response list has an Off-spec
answer for exactly that.

---

## Design choices worth arguing about

Three places where the mock above picked one option and the other is defensible.

### A. Where the officer board lives

**As drawn: its own window.** Opens on the kill, closes when the last item is
decided. Sits next to the mini roll rather than replacing it.

*The alternative:* a tab inside the Loot page. Fewer windows, but it means
opening the hub mid-raid and the board competing with the rest of that page for
width. The mini roll exists as a floating window for exactly this reason.

### A2. Where the ML picks items — settled

**The mini roll**, with a checkbox column and a council button row beside the
existing roll buttons.

Settled by a fact about how RATS actually raids: a master looter running
council still calls *"this one just roll"* on individual pieces. The two are
per-item, not per-night, so both have to act on the same list — and a separate
picker window would mean two copies of one boss's loot, each able to do
something different to it.

The cost is a checkbox column and one more mode in a 1400-line file that works
today. Accepted; see stage 3b.

### B. What the raider popup costs them

**As drawn: five buttons, one click, auto-pass on a timer.**

*The alternative:* no popup at all — the raider types `/roll` as they do now,
and the board reads the rolls. Zero disruption, nothing new to learn, works for
people without the addon. But it loses the whole point: a roll is a number, not
"this is my BIS and I have never had one".

A middle option: popup for people with the addon, `/roll` still parsed for
everyone else, both feeding the same board. More code, but nobody is locked out
on the night someone forgot to install it.

### C. How much the raider is told — settled

**Nothing about the priority list.** Not their position, not that they are on
it at all. The ladder stays with the officers, where it already lives.

What their frame highlights comes from their own gear instead: red for an item
they are already wearing, green for a BiS item if a BiS list exists. That is
information about them, not about the guild's decision.

Rejected: their position (a raider who knows they are fourth argues from it),
a flag saying they are on the list (same problem, one bit at a time), and
showing the board read-only afterwards (everyone then sees who beat them).

---

## What RCLootCouncil does, for reference

Read out of the installed copy, since RATS already uses it and the raiders'
muscle memory is worth matching where it costs nothing.

**Five buttons by default**: BiS, Big Upgrade, Small Upgrade, Off Spec, Pass
(`core.lua:176-181`). BiS ships with it — guilds do not add it. Up to ten
buttons, set by the master looter.

**Each response has a colour** (`core.lua:85-88`): BiS red, Big Upgrade orange,
Small Upgrade yellow, Off Spec blue, Pass grey. The colour is **not** on the
raider's buttons — those are plain — it is the text colour on the council's
board (`votingFrame.lua:751-755`) and in the loot history.

Worth copying: a BiS row in red against a Pass in grey is read at a glance in a
list of ten candidates, which is exactly what the board is for.

**The master looter's settings win.** Every client reads the ML's broadcast
config rather than its own (`core.lua:1611-1627`), so a raider who renamed their
buttons cannot answer something the officer sees differently.

**Filtering is done on the raider's client**, not by the ML — the whole loot
table goes to everyone and each client autopasses what it cannot use
(`core.lua:1050-1060`). It checks armour/weapon subtype against class, and token
class restrictions. No ilvl, no stats, no spec. Two details worth taking:

- **Cloaks are never filtered** (`autopassOverride`, `core.lua:1046`) — every
  class wears one.
- A filtered item is dropped from the **list**, not the window
  (`lootFrame.lua:22-24`); the frame still opens for whatever survived.

---

## Open questions

1. **Response set** — is `BIS / Big upgrade / Minor / Off-spec / Pass` right, or
   does RATS use different words?
2. **Who sees the board** — `U.isOfficer` is guild-rank only
   (`Util.lua:170`), so a pug or a trusted non-officer cannot be on the council.
   Is that acceptable, or is a council roster needed?
3. **Timeout** — how long does a raider get to answer before it auto-passes?
4. ~~**Does the raider see the prio?**~~ **Answered: no, nothing.** Not the
   position, not even that they are on the list. Their frame highlights from
   their own gear instead — red for already wearing it. See stage 2.
5. **Re-asking about an item.** The picker marks it `asked` and unticks it, so
   sending twice is deliberate — but what does the raider see the second time?
   Pre-filled with their last answer (kinder, easy to miss) or blank (honest,
   loses anyone who walked away)?
6. **Recording a winner when the item is already in someone's bags.** With auto
   loot there is no give to watch, so the council's choice has to write
   `receivedBy` itself. What does the history show while Jiskob still physically
   holds Kobee's trinket? Blocks stage 3b.

---

## A bug found while planning this

**`dp.de` is never set.** It is read in four places — the export's player
sentinel and class field (`Loot.lua:2877-2879`), the export's own `de` column
(`:2886`) and the history row (`:2930`) — and no code anywhere writes it.

The reader was written for Blizzard's native Disenchant roll, which does not
happen under master loot: the master looter takes the item and hands it to an
enchanter like any other give. So today a disenchanted item is recorded as
belonging to whoever shattered it, the loot history shows it as theirs, and the
website counts it against them in the fair-loot metric.

This is worth fixing whether or not the council is built. The council's
`Disenchant` button would be the first thing to ever set the flag.

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
