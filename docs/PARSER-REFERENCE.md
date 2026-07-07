# RaidFinder Parser — Reference (how RaidBrowser does it)

This is a **study document**, not code to copy. It explains the technique from
RaidBrowser's `core.lua` (Act/Horsebreed@Warmane) so we can reimplement the same
idea as our own understood code in `Okanvil.RF`. It also flags which parts are
solid and which are fragile, so we know what to trust vs rewrite.

The whole point of the parser: turn a noisy chat line like

    "LFM ICC 10 hc 2 heal 1 tank 5.8k+ gs whisper me [The Light of Dawn]"

into a clean listing `{ raid=icc25hc, size, roles={tank,heal}, gs="5.8", ... }`
— **and reject** guild-recruit / WTS / LFG spam so they never appear as raids.

---

## 1. The core trick: meta-token reduction

Naive parsing ("does the message contain a raid name?") gives tons of false
positives — recruit ads, WTS, people looking FOR a group all mention raids.

RaidBrowser's insight: **don't just detect keywords — consume them and check
what's left forms a valid LFM sentence.**

It works like a tiny lexer. As each meaningful token is recognized, it's
replaced in the string with a **meta-marker**:

| Recognized thing        | Replaced with |
|-------------------------|---------------|
| a raid name (icc, naxx) | `¿raid¿`      |
| a role (tank/heal/dps)  | `¿role¿`      |
| a gearscore (5.8k)      | `¿gs¿`        |
| a guild name            | `¿guild¿`     |

(The marker char is a rare byte — `\194\191`, the inverted `¿` — so it can't
collide with real text.)

After reduction, `"LFM icc 10 hc 2 heal 1 tank 5.8k gs wsp me"` becomes roughly
`"lfm ¿raid¿ 10 hc 2 ¿role¿ 1 ¿role¿ ¿gs¿ wsp me"`. Now you can ask a much
sharper question: **does this skeleton match a known LFM shape?** e.g.
`lfm ... ¿role¿ ... ¿raid¿` or `¿raid¿ ... ¿gs¿ ... whisper me`. That's what
`lfm_patterns` checks. A recruit ad won't reduce to an LFM skeleton, so it's
dropped.

**This is the part worth keeping.** It's why the list stays clean.

---

## 2. The pipeline (stage by stage)

`lex_and_extract(message)`:

1. **lowercase** the message.
2. **strip http links** (streaming URLs etc.) — else they inject junk tokens.
3. **early reject**: if it matches `guild_recruitment_patterns` (`recruiting`,
   `we raid`, `<Guild> is a ... guild`, raid times) or `trade_message_patterns`
   (`wts`, `wtb`, `selling`, `buying`) → bail, not a raid listing.
4. **remove any stray meta chars** from the raw text (safety).
5. **lex guild names** → `¿guild¿` (so "Guild Foo Bar recruiting" is catchable).
6. **lex the raid** → `¿raid¿`, remembering which raid + how many DISTINCT raids
   appeared. (See §3.)
7. if a guild-recruit skeleton (`¿guild¿ ... ¿raid¿`) shows up → bail.
8. if **more than one distinct raid** was mentioned → bail (recruit ads list
   many raids; a real LFM lists one).
9. **lex achievement links** down to just their `[Name]` text.
10. **lex roles** → `¿role¿` (dps, then tank, then healer). If none found, assume
    all three are wanted. If the message says "lfm all" / "need all", skip role
    parsing and mark all roles.
11. **lex gearscore** → `¿gs¿` and extract the number.
12. **reduce role-lists**: collapse `¿role¿ and ¿role¿` → single `¿role¿`
    repeatedly, so multi-role requests match the skeleton patterns.

Then `raid_info(message)` does the final gate:
13. if the skeleton matches `lfg_patterns` (someone LOOKING for a group, not
    forming one) → bail.
14. if it does **not** match `lfm_patterns` → bail.
15. otherwise return `raid, roles, gs`.

Our `RF.parse` will follow this same 15-step spine.

---

## 3. Raid lexing details (the genuinely useful data)

`raid_list` is an ordered array. Each entry:

```lua
{ name = 'icc10hc', instance_name = 'Icecrown Citadel', size = 10,
  patterns = { ...lua patterns that mean "this raid"... } }
```

Key points to reuse:

- **Order matters.** Heroic variants are listed BEFORE normal, because a normal
  pattern like `icc.10` would also match an "icc 10 hc" string. First match with
  the earliest position in the message wins, with a `prioritized` override for
  weekly-quest entries.
- Patterns include not just abbreviations (`icc 10`, `icc.25.hc`) but also
  **achievement/quest link ids** and **boss/achievement names** that imply the
  raid+difficulty (e.g. `Bane of the Fallen King` ⇒ icc10hc, `The Light of Dawn`
  ⇒ icc25hc). That's how it reads links people paste.
- `create_pattern_from_template(raid, size, diff)` generates the common
  abbreviation shapes so each raid doesn't hand-write them.
- `num_unique_raids` uses `get_short_raid_name` (strips the size/difficulty
  suffix) so `icc10` and `icc25` count as the SAME instance, but `icc` vs `naxx`
  count as two → recruit-ad rejection.

**For Okanvil we only need the raids we care about: Naxx, Ulduar, ToC, ICC (+RS
optional).** Skip the 20 legacy raids — less surface area, fewer surprises.

---

## 4. What's SOLID (reuse the logic confidently)

- **The meta-token pipeline + LFM/LFG skeleton validation** (§1, §2). This is the
  robust heart. Reimplement faithfully.
- **Raid name/size/difficulty patterns** for the raids we keep. Tedious but
  correct. Copy the pattern *shapes* for our raids, re-typed and understood.
- **Guild-recruit / WTS early rejection.** Cheap and effective.
- **"More than one distinct raid ⇒ reject"** heuristic. Simple, works.

## 5. What's FRAGILE / SUSPECT (rewrite, don't trust blindly)

- **`format_gs_string` GS normalization.** It guesses scale by magnitude
  (`>1000 → /1000`, `>100 → /100`, `>10 → /10`) to turn `5800`/`58`/`5.8` all
  into `"5.8"`. This is hacky and mis-fires on odd inputs (e.g. a bare `40` from
  "40 man"). We should write our own GS extractor with clearer rules and a sanity
  clamp (WotLK GS is ~2000–7000).
- **The role regex soup.** Huge list of spec nicknames (`boomy`, `tree`, `rdudu`,
  `disco`...). Mostly fine but some patterns are greedy and can match inside
  other words. Keep the *idea* (map nicknames→role) but build our table cleanly
  and test it.
- **Achievement id handling in `stats.lua` is BROKEN** (documented separately):
  it strips the raid id to `icc`/`toc`/`rs` and only has keys for those three, so
  links never fire for Naxx/Ulduar. Our achievement table is keyed by FULL raid
  id — see RAIDFINDER-PLAN.md §8. Do NOT reuse `find_best_achievement`.
- **`prioritized`/weekly overlap logic** is subtle; if we include weeklies, test
  that "icc 10 weekly" doesn't get mislabeled as a normal icc10 run.

## 6. What's NEW (not in RaidBrowser — we design)

- **Reserved-items extraction** (Ress column). RaidBrowser only has a throwaway
  `¿raid¿ reserved` pattern with no extraction. We detect `reserved / ress / sr /
  softres / EV / STS / ACHIEV / BoE` plus item/achievement links, and produce
  nil (unknown) / false (none) / string (snippet for the tooltip).
- **wantsAchiev flag** — did the leader's post itself contain an achievement
  link? Used to know they're gate-checking.
- **firstSeen / lastSeen split** — a MODULE concern, not the parser's, but noted
  here: the parser is pure (message → listing); the module owns timestamps so
  re-spam updates `lastSeen` without reordering.

---

## 7. Suggested implementation order (our code)

1. Raid lexer for our 4–5 raids + `num_unique_raids` rejection. Test with real
   spam strings.
2. Guild-recruit / WTS / LFG early rejection. Test recruit ads get dropped.
3. Role lexer (clean nickname table). Test.
4. GS extractor (our own, clamped). Test.
5. Reserved-items extractor. Test.
6. LFM-skeleton validation gate. Test the whole `RF.parse` end to end.

Each stage is small and independently testable via `/script`. Build one, prove
it, move on — so nothing is a black box.
