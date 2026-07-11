# 🎁 Loot capture — how the two systems work

Written to stop the whack-a-mole: a fix for one path kept breaking the other. This maps
**every** way a drop gets recorded, so we can decide changes with the whole picture in view.

There are **three capture paths** and they can all fire for the same physical item. That
overlap is the root of every duplication bug — and the third path (comms) means a
**second raider running Okanvil can add a fourth reason** the same item shows up.

---

## The two paths

### 1. `captureCorpse()` — the corpse scanner
- **Fires on:** `LOOT_OPENED` — i.e. **when YOU open a corpse.**
- Walks every loot slot (`GetNumLootItems` / `GetLootSlotInfo`) and records each one.
- Knows the corpse **GUID** (`UnitGUID("target")`) and guards against re-scanning the same
  corpse (`scannedCorpses[guid]`), so re-opening doesn't double the loot.
- Uses **`allowDup=true`**: each slot is its own line, so two identical rings on one corpse
  become two rows. This is the path that **skips** the id+boss de-dup.

### 2. `captureRollStart(rollID)` — the need/greed scanner
- **Fires on:** `START_LOOT_ROLL` — the WoW client's **need/greed/DE prompt.**
- Fires **once per item, on EVERY player in the party** — even if you never open the corpse.
- Records the item with a **`rollID`**. Has **no corpse GUID** (the API gives item + rarity
  + timer, nothing about which body it came from).
- Uses `storeDrop` **without** `allowDup`, so it de-dups by id+boss.

### 3. `Comms.On("LOOT")` — a teammate's broadcast
- **Fires when:** another player **running Okanvil** opens a corpse. Their `captureCorpse`
  calls `broadcastDrop`, which sends the item list over addon comms to everyone else with
  the addon (the idea: everyone sees what dropped before it's handed out).
- Records the item via `storeDrop` **without** `allowDup` → de-dups by id+boss.
- **Protected:** you never receive your OWN broadcast (`Comms` drops `sender == me`), and
  it's gated by `shouldRecordHere()`.
- **The catch:** this only exists if a SECOND person runs the addon. Solo-addon raids never
  hit it. It's a real fourth way the same item reaches your session.

---

## Does a second Okanvil user interfere?

**Yes — partly protected, one real hole.**

- You don't get your own broadcast back, and a received broadcast de-dups by id+boss, so a
  normal single drop that you already recorded (via your roll) just **collapses** — no dup.
- **The hole:** the broadcast de-dups by **id+boss**, but your local corpse scan uses
  `allowDup`. With **two identical items**, your scan makes two lines, but the teammate's
  two broadcasts both match id+boss and collapse onto the SAME one line — so the count can
  end up wrong, or `receivedBy` can attach to the wrong copy.
- Net: two Okanvil users won't usually double a single drop, but **duplicate items + comms**
  is unreliable, for the same root reason as everything else here.

---

## Who fires when

| Situation | `captureCorpse` (you open) | `captureRollStart` (need/greed) |
|:--|:--:|:--:|
| **You** open a boss, need/greed loot | ✅ yes | ✅ yes (both fire → **overlap**) |
| **Someone else** opens, need/greed loot | ❌ no (no target/GUID) | ✅ yes |
| Master loot (no need/greed) | ✅ yes | ❌ no |
| Two identical items, need/greed | ✅ yes | ✅ **twice** (one roll per item) |
| Trash mobs dropping the same item | ✅ per mob you open | ✅ once per mob |

**The client guarantees:** loot drops **once** per corpse (re-opening doesn't re-add), and
the need/greed prompt fires **once per physical item**. So the roll count already equals the
real item count — the server never duplicates. Any duplication is the addon's two paths
both recording the same item.

---

## Why the GUID can't be the key

Tempting idea: tag each drop with the corpse GUID, so "same item, same corpse" collapses
and "same item, two mobs" stays split. **It doesn't work** — because when *someone else*
opens the corpse, you only get `START_LOOT_ROLL`, which carries **no GUID**. You literally
don't know which body the item came from. The GUID is only available on the path (corpse
scan) that doesn't even run in that case.

---

## Current de-dup logic (what's in the code now)

**Roll fires, then you open the corpse** *(the common dungeon case)*
→ roll creates the drop (with `rollID`); the corpse scan calls `claimRollDrop`, finds that
roll-drop, and **claims** it instead of adding a line. **1 line.** ✓

**Corpse opens, then the roll fires** *(the race the user described)*
→ scan creates the drop (allowDup, no rollID); the roll then calls `storeDrop` without
allowDup → `dropExists` finds the corpse drop and **attaches** the rollID to it. **1 line.** ✓

**Two identical items**
→ two `START_LOOT_ROLL`s = two roll-drops; the scan claims one per slot (`_slotSeen` marks a
claimed one so the second slot claims the second). **2 lines.** ✓

**Master loot (no need/greed)**
→ no roll ever fires; the scan is the only source, with `allowDup`. **1 line per slot.** ✓

### The one fragile spot
`dropExists` returns the *most recent* drop matching id+boss. With **two identical items +
corpse-opens-first**, the two roll events could both attach to the same corpse drop, or
attach ambiguously — the line count stays right (2), but which line owns which `rollID`
(and thus shows "rolling") can get crossed. Rare, cosmetic, not a duplication.

---

## The open design question

Two ways to make this bulletproof, each with a catch:

**A. Keep "count the rolls"** (current). The corpse scan claims roll-drops. Works for all
five cases above. Risk: the fragile spot, and it leans on event ordering.

**B. "Roll is the sole authority"** — if an item goes to need/greed, the corpse scan
ignores it entirely; the scan only records master-loot. Cleaner in theory, BUT: the scan
often runs *before* the roll prompt arrives, so at scan time we can't yet know "does this
item go to need/greed?" We'd have to defer, or reconcile after a short delay — which
reintroduces timing. And master-loot detection has to be exactly right, or ML drops vanish.

The decision hinges on: **can we know, at the moment we scan a corpse slot, whether that
item will go to need/greed?** If not, option B needs a deferral and isn't obviously simpler
than A.

### And the comms path complicates both

Whatever we pick, the teammate broadcast (path 3) records with plain id+boss de-dup, which
can't tell a duplicate item apart from the same item seen twice. Options worth weighing:

- **Stamp each drop with a source id.** The corpse scan already has the corpse GUID + slot
  index — a real "this physical item" key. The roll path has the `rollID` — also unique per
  item. If every drop carried a stable per-item key, all three paths (scan, roll, comms)
  could de-dup on THAT instead of id+boss, and duplicates-vs-same-item stops being
  guesswork. The broadcast would need to carry the key too. *This is the proper fix, and it
  retires the whack-a-mole.*
- **Or: make the broadcast advisory only** — a teammate's broadcast shows the item in the
  roll window but doesn't get written to history unless it's your own capture. Simpler, but
  you lose loot other people opened when you didn't.

The real question to answer before any more fixes: **do we want one canonical per-item key
(rollID where present, else corpse-GUID+slot) threaded through all three paths?** That's the
change that makes duplicates and comms both correct, instead of patching each case.
