# Testing the loot council with two clients

Written for: you and whoever is testing with you. Everything here is done in
game; nothing needs a raid.

The council has been built and tested **solo**, where `Comms.Ask` falls back to a
loopback path — the question never crosses the wire. That proves the round
bookkeeping, the frame and the board, and proves **nothing at all** about the one
thing this addon has failed at before: whether a message actually arrives.

That is what a second client tests.

---

## Before you start

**Send the whole addon, not just the council files.** `Council.lua` needs
`Comms.lua`, `Loot.lua`, `Widgets.lua` and the updated `Okanvil.toc` — a partial
copy will error on load or silently do nothing.

Both clients must be on the **same build**. A version mismatch is the most likely
cause of "he never got the popup", and it looks exactly like a bug in the code.
Check with `/okrc` (version check) once you are grouped — both names should come
back with the same number.

**Your friend does not need to be an officer.** Answering a round is open to
everyone; only asking and seeing the board are gated. If he is not in the guild
at all, he still answers normally.

He does need **Loot Council enabled** in the Modules list (it is on by default).

---

## The test, in order

Run these in a **party of two**. Nothing here gives away real loot.

### 1. Does the wire work at all?

    /okcomms          (both of you — prints every addon message as it arrives)
    /okask            (you)

He should print a reply line. If nothing arrives, stop here: nothing below can
work, and the problem is the wire, not the council.

`/okcomms` again to switch the firehose off.

### 2. Does the eligibility filter run on HIS client?

    /okprof all [shift-click a plate chest]

Should list WARRIOR, PALADIN, DEATHKNIGHT and nobody else. Run it on both
clients — it is pure local logic, so a disagreement means a load problem.

### 3. A real round

    /okcouncil test 3        (you)

Items land in your mini roll. Pick one, press **Ask this one**.

What should happen:

| | |
|---|---|
| his client | popup opens, but **only** with items his class can equip |
| your board | his name appears as he clicks, with his equipped item and the ilvl gap |
| the count | `1 answered`, plus `n can't use` if the filter dropped items for him |

**If he can use none of the items**, no popup opens for him at all and the board
says so. That is correct, not a failure — try again with gear his class wears.

### 4. The things that only break with two people

Worth doing deliberately, because these are the real failure modes:

- **He answers, then `/reload`s.** Does his answer stay on your board? (It
  should — the reply was already sent.)
- **He `/reload`s BEFORE answering.** His popup is gone and it does not come
  back. **This is the known gap** — reload recovery is not built yet. Expect it
  to fail; the point is to see what it looks like.
- **You `/reload` mid-round.** Your board empties. Same known gap.
- **He is dead / afk.** The timer runs out and his items auto-pass.
- **Two items at once**, one he can use and one he cannot. The board should show
  a different candidate count per item.

### 5. Award

Still in test mode, press **Give to `<him>`**. It prints what it *would* have
done and gives nothing away. Confirm the chat line names him.

Then `/okcouncil test off` — his popup closes, your test drops are hidden, and
world recording goes back to what it was.

---

## What is expected to fail

Say this to him up front, so he does not report it as a bug:

- **A `/reload` before answering loses the round on that client.** No
  persistence is built yet.
- **A dropped addon message is lost.** There is no retry, so if his popup never
  appears once in twenty rounds, that is why.

Both are the next thing being built. Everything else should work.

---

## If something goes wrong

- `/okcouncil status` — what this client thinks is open
- `/okcomms` — watch the raw messages
- `/okerr` — Okanvil's error log, on both clients

The useful report is: **what each client saw**, not just yours. "He got no
popup" and "he got a popup with the wrong items" are completely different bugs.
