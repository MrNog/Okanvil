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

### The commit body becomes the Discord post — write it for EVERY raider

The release embed is built from the commit **bodies** since the last tag, not from the
diff. It goes to **all raiders** through one webhook, so it must be short and must
never reveal officer tooling — the user tells officers about their features in person.

Sort each change onto its own line, prefixed with a keyword:

```
[minor] loot: mini roll buttons, lockout ID

new: Mini roll: each item has a Roll button that asks Main or Off spec.
fix: Shortcut tooltips no longer cover the other icons.
officer: Attendance snapshots record the raid's lockout ID. (never posted)
- Internal: renamed exportRunId. (no keyword -> not posted)
```

- `new:` / `feature:` / `add:` → **✨ New**. `fix:` / `fixed:` / `bug:` → **🔧 Fixed**.
  Only things **a raider sees** (mini roll, tooltips, menus, their own view).
- `officer:` → **never posted**. Everything only officers see or that tracks raiders:
  Council/Priority tabs, attendance, lockout IDs, prio, blacklist, website export,
  ML/officer-only buttons. When in doubt, it is `officer:`.
- Any other line, and a commit with no keyword line, is **left out** (no subject
  fallback). If nothing is left, the post just says "Small fixes and improvements."
- The post shows at most **3 New + 3 Fixed**, each cut at ~90 chars; extras collapse
  into "+ other small fixes". So put the most important line first and keep each
  line under ~80 chars.

One line = one thing a raider notices in-game. Name the module, say the effect,
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

Lua 5.1.5 (the version 3.3.5a embeds) is installed on PATH as `lua5.1` / `luac5.1`, and a
user-level PostToolUse hook runs `luac5.1 -p` on every `.lua` Claude edits — a syntax error
comes back immediately with file:line. To check the whole addon:
`find Okanvil -name '*.lua' -exec luac5.1 -p {} \;` (silent = all parse).

`luac -p` only proves the file parses; runtime errors (nil index, 4.x-only API) still need
the user to load in-game and report the error line.

3.3.5a traps: no `SetShown`/`SetEnabled`, no `C_Timer` (use `Okanvil.Comms.After`), no
`SetClipsChildren` (use `Okanvil.Clip`), no `RegisterAddonMessagePrefix`, no HTTP.
