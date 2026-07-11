# ⌨️ Okanvil — slash commands

Okanvil has **four** slash commands. Everything else opens from the **minimap button** —
every tool is a module inside the one window, so there's no command to memorise per module.

Type **`/okanvil help`** in game to print this list.

<br>

---

## ⚒️ `/okanvil` — the window

| arg | does |
|:--|:--|
| *(none)* | open / close the main window |
| `tab` | create the dedicated `Okanvil` chat tab; all output moves there |
| `help` · `?` | print this list in chat |

## 🎲 `/okroll` — mini roll manager

Toggles the small roll window. No arguments.

## 🆘 `/okfocus` — panic button

Frees a stuck keyboard focus. If an edit box ever traps your keys mid-fight and
`W`/`A`/`S`/`D` stop working, **this is the escape hatch.**

## 🛠️ `/okerr` — error log

| arg | does |
|:--|:--|
| *(none)* | show the persisted error log (copyable, survives logout) |
| `clear` | wipe it |

<br>

---

## 💬 Where messages go

Output prints to a dedicated **`Okanvil` chat tab** when it exists, otherwise your default
chat frame. Create the tab once with **`/okanvil tab`** (it survives `/reload`).

**Dev mode** is a toggle in **Settings** (default off) — it sends debug lines to that same
tab. There's no command for it.

<br>

## 🧑‍🔧 For maintainers

The four commands live in:

| file | command |
|:--|:--|
| `Core/Core.lua` | `/okanvil` · `/okfocus` · `/okerr` |
| `Modules/LootRoll.lua` | `/okroll` |

Module actions that used to be slash args — ID sweep, log on/off, recruit on/off/afk,
the one-off tooltip backfill (`/okdebug`) — are now buttons/toggles inside each module's
panel, or one-time jobs that are done. Their `L.*` functions stay in the code.

`Okanvil:Print(msg)` is the single output funnel; it resolves the chat tab via
`Okanvil:DevFrame(false)`, so changing where messages land is a one-function edit.

> ⚠️ **A bare `|` starts a colour escape in chat** (`|cAARRGGBB … |r`). Writing
> `(on | off)` in a `Print` truncates the line — use `/` as a separator, or `||`.
