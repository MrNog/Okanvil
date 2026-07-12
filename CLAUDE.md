# Okanvil — working rules

WoW 3.3.5a (Interface 30300) addon. Repo root **is** the addon: `Okanvil/Core/` is the
shell, `Okanvil/Modules/` are the tools. UI work is governed by the `okanvil-ui` skill —
load it before touching any frame code.

## Commit messages control the release — read this before committing

**Every push to `main` cuts a release**: the GitHub Action bumps the version, creates the
tag, builds the zip, publishes, and announces to Discord. There is no separate "release"
step and **no tag is ever made by hand**.

The bump level comes from a keyword in the commit message (any case, anywhere in the
subject or body):

| keyword    | `1.2.1` becomes | when to use it |
|:-----------|:----------------|:---------------|
| *(none)*   | `1.2.2`         | bug fix, refactor, tweak — **the default** |
| `[minor]`  | `1.3.0`         | new module, new feature, new user-visible capability |
| `[major]`  | `2.0.0`         | breaking change (e.g. wipes SavedVariables, changes the comms protocol) |
| `[skip]`   | *no release*    | docs, README, CI, comments — anything with no shipped code change |

### What this means for Claude

When the user asks to **commit** or **push**, you must choose the keyword yourself and say
which you chose and why. Do not ask unless it is genuinely ambiguous.

- Judge by what the *diff* does, not by how the user phrased the request.
- Touching only `README.md`, `docs/**`, `.github/**`, or comments → `[skip]`.
- Fixing a bug in `Okanvil/**` → no keyword (patch).
- Adding a module, a window, a command, or a new module capability → `[minor]`.
- Anything that invalidates existing saved data or the addon-comms wire format → `[major]`.
- A mixed diff takes the **highest** level it contains — a feature plus a docs tweak is
  `[minor]`, never `[skip]`.

### The commit body becomes the Discord post — write it for officers

The release embed in `#okanor-logs` is built from the commit **bodies** since the last
tag, not from the diff. Officers read it; they do not read code. So the body must say
what changed *for a user*, in plain words.

Sort each user-visible change onto its own line, prefixed with a keyword:

```
[minor] loot: raid ID tracking

new: Loot now tracks the raid ID, so two raids on the same night no longer merge.
fix: Master-loot window no longer shows for every raider, only the actual ML.
- Internal: renamed exportRunId. (no keyword -> not announced)
```

- `new:` / `feature:` / `add:` → the **✨ New** list.
- `fix:` / `fixed:` / `bug:` → the **🔧 Fixed** list.
- Any other line (internals, refactors, co-author trailers) is **left out of the post**.
- A commit with no keyword line at all falls back to its subject, so nothing ever
  vanishes — but that subject is usually developer shorthand, which is exactly the
  problem. **Write the keyword lines.**

One line = one thing the officer would notice in-game. Name the module, say the effect,
skip the mechanism ("no longer merges two raids", not "keys off s.key not s.day").

**Never hand-edit `## Version:` in `Okanvil/Okanvil.toc`.** The tag is the single source of
truth and the Action stamps the `.toc` at build time. Editing it by hand does nothing except
make local builds lie about their version.

## Editing vs. the live addon

Edit the source in **this repo**, never the installed copy under
`<WoW>\Interface\AddOns\Okanvil\` (a separate copy). After editing, copy the changed
files into each WoW client's AddOns folder or the fix "won't take" after `/reload`.

This machine runs **two** clients, so a fix must be synced to **both** — the exact
install paths are machine-specific, so keep them in a local (git-ignored) note or your
shell history, not here.

## Validating Lua

There is no Lua interpreter available. Validate structurally: a stripping block-balancer
(strip comments/strings/long-brackets first — words like "the void" or "host for" contain
`for`/`if`/`end` and produce false positives), then check `then`/`do`/`function`/`repeat`
against `end`/`until`/`elseif` nets to zero, plus paren and brace balance. Sanity-check the
balancer against the pristine `git show HEAD:<file>` before trusting a zero. Then the user
loads in-game and reports the error line.

3.3.5a traps: no `SetShown`/`SetEnabled`, no `C_Timer` (use `Okanvil.Comms.After`), no
`SetClipsChildren` (use `Okanvil.Clip`), no `RegisterAddonMessagePrefix`, no HTTP.
