---
name: okanvil-ui
description: Build and restyle the Okanvil addon UI (WoW 3.3.5a Lua). Use when adding/editing frames, buttons, dropdowns, sliders, panels, or any in-game UI in Okanvil's Core or Modules (Guild / Invite / Recruit / Loot / LootRoll / IDs / Logs). Enforces the shared widget layer (Okanvil.W) and W.Dashboard shell, the gold RATS-Hub palette, 3.3.5a API safety, and the anti-spill window structure modelled on Method Raid Tools (MRT/ExLib).
metadata:
  author: Okanor
  version: "1.1"
---

# Okanvil UI

Okanvil is an MRT-style **single addon** for WoW 3.3.5a: one window with a left
nav. It's **all one addon** — a native core (Home + Modules) plus built-in
modules (Guild/Invite/Recruit/Loot/LootRoll/IDs/Logs) that register and draw into
a content panel. **There are no standalone plugins.** Every module page is built
on **`W.Dashboard`** (gold header + optional tabs + optional drawer). The
structure is modelled on **Method Raid Tools' ExLib** so components never spill
out of the main window.

## Non-negotiables

1. **Target is WoW 3.3.5a (Interface 30300).** No retail-only APIs unless guarded
   with `if frame.Method then`. Known traps:
   - `SetClipsChildren` — absent on 3.3.5. Always via `Okanvil.Clip(frame)`.
   - `SetResizeBounds` — retail. Fall back to `SetMinResize`, then a re-entrancy-guarded `OnSizeChanged`.
   - `SetObeyStepOnDrag` — guard it.
   - `BackdropTemplate`/`Mixin` — NOT needed on 3.3.5 (all frames have `SetBackdrop` natively). Don't add them.
2. **Use the shared widget layer `Okanvil.W`** (Widgets.lua). Do NOT hand-roll
   `CreateFrame`+`SetBackdrop` buttons — that's the "old button style".
   Available: `W.Frame/Text/Button/Check/Slider/EditBox/DropDown/MultiEdit` +
   **`W.Dashboard`**, plus `Okanvil:Skin(frame, kind)`, `Okanvil:Popup(title)`,
   `Okanvil:ReskinAll(alpha)`.
3. **Edit source in `Projects\Okanvil` (repo root = the addon), never the live WoW
   AddOns copy.** They are separate copies; the user syncs via the Fork GUI.
4. **Preserve the module-facing API:** `Okanvil:NewText/Backdrop/Font/Texture/Register/Toggle`.

## Palette (mirror the RATS Hub — gold on neutral dark)

`Okanvil.Colors` holds these (0-1 floats). Match the hub so addon + website read as one brand:

| token   | hex       | use                         |
|---------|-----------|-----------------------------|
| accent  | `#c0943a` | gold: primary btn, active   |
| accentHi| `#e0b860` | bright gold: hover, links   |
| panelD  | `#141517` | recessed wells (nav/content)|
| surface | `#202225` | secondary buttons           |
| panel   | `#26282d` | default panels              |
| border  | `#2f3137` | 1px hairline                |
| text    | `#dcddde` | body                        |
| textDim | `#8a8d93` | labels, hints               |
| ok      | `#7cfc8a` | success/on                  |

Never introduce a new accent colour (the old cyan is gone). Toggle "ON" = `ok`, "OFF" = `textDim`.

## Button hierarchy (the fix for "cute text but old button")

- `W.Button(parent, "Do it", "primary")` — solid gold fill, dark bold label. One per view, the main action.
- `W.Button(parent, "Cancel")` — surface fill, hairline border, dim label → gold on hover. Everything else.
- `W.Button(parent, "Delete", "danger")` — red label.

Plugins that still use a local `makeFlatButton`/`makeButton` should be migrated to
`Okanvil.W.Button`. Same for ON/OFF pills → use a two-colour `W.Button` toggle.

## Product model (core is NOT empty)

Okanvil has a **native core** (a guild dashboard Home + a Modules manager) so it's
useful with zero modules on. The tools (Guild/Invite/Recruit/Loot/LootRoll/IDs/Logs)
are **optional modules you toggle on/off** — like DBM/BigWigs. It's all one addon;
there are no standalone plugins.

- **Enable state is PER CHARACTER** — `Okanvil_CharDB.modules[name].enabled`
  (absent = enabled). API: `Okanvil:IsModuleEnabled(name)`,
  `Okanvil:SetModuleEnabled(name, bool)`. Content settings stay account-wide.
- Disabled = **hidden from the nav** (instant, no /reload). Deeper event-gating
  (a module not registering its events when off) is opt-in inside each module, TODO.
- Modules add `desc = "..."` to their `Okanvil_Plugins[name]` table for the Modules list.
- **Nav order** is one editable list (`Okanvil.NAV_ORDER`, by title); the shared
  **icon set** is `Okanvil.ICONS` (keep a module's nav icon == its Dashboard header icon).
- Home is a **guild dashboard** (online count/members/rank tiles, online list, web-hub
  card). Uses 3.3.5a guild API: `IsInGuild`, `GuildRoster`, `GetNumGuildMembers`,
  `GetGuildRosterInfo`.
- **Branding is configurable** so any guild can rebrand: `db.brand` (default
  "RATS Guild Hub") drives the header title, Home title, minimap tooltip; `db.hubURL`
  (default https://mrnog.github.io/RATS/) is the web hub. Both editable in Settings > Branding.
- **No browser open on 3.3.5** (no OpenURL/LaunchURL, Lua is sandboxed without os/io).
  The "Open Web Hub" button calls `Okanvil:ShowURL(url, label)` -> a StaticPopup with the
  URL pre-selected (Ctrl+C -> paste). Never claim a button opens the browser directly.
- **Header/minimap icon** is the anvil `Interface\Icons\Trade_BlackSmithing`; brand text
  is gold `|cffe0b860...|r` (the old cyan `66ddff` is fully removed).

## Validation (no Lua interpreter locally)

Use the proper block-balancer, not a naive grep count (strings like "the void" or
"host for" contain the words for/if/end and give false positives). A stripping
balancer (comments + strings + long-brackets removed, then `then/do/function/repeat`
vs `end/until/elseif`) must report depth 0. Then the user loads in-game.

## Window / panel structure (anti-spill, from MRT)

- **Module pages receive a full-size fill panel** (real BOTTOMRIGHT) via
  `newFillPanel()`, then build a `W.Dashboard` into it. Do NOT hand a module a tiny
  scroll-child — that collapses its `BOTTOMRIGHT` anchors (this broke Recruit once).
- **Shell-owned long pages** (Home) use `newScrollPanel()` (internal clipped scroll).
- **Dropdowns use the ONE global menu** (`W.DropDown`): parented to UIParent, strata
  `TOOLTIP`, `SetClampedToScreen`, flips up when no room below. Never build a
  dropdown list as a child of the button (it gets trapped/clipped by the window).
- Every panel/dropdown that scrolls: match child width to the scrollframe and
  recompute the slider range in a `relayout()` on `OnSizeChanged`.

## Workflow

1. Read the relevant file(s) under `Projects\Okanvil` (repo root = the addon). Match surrounding style.
2. Prefer `Okanvil.W.*` and `W.Dashboard`; extend Widgets.lua if a needed widget is missing (keep the chained `:Point/:Size` API and register skins for alpha re-tint).
3. There is **no local Lua interpreter** — validate structurally: block balance
   (`function/if/for/do` vs `end`), paren balance, and cross-file symbols. Then the
   user loads in-game and reports any Lua error line.
4. Keep changes small and incremental; one module at a time when migrating buttons.

## Files

- `Core/Core.lua` — boot, DB, media, module registry, legacy `:Backdrop`.
- `Core/Widgets.lua` — the `Okanvil.W` widget layer + `W.Dashboard` + palette + global dropdown + Popup.
- `Core/UI.lua` — shell: window, nav (`NAV_ORDER`/`ICONS`), panels (fill vs scroll), Home, Settings, Modules, minimap.
- `Modules/*.lua` — each fills `Okanvil_Plugins[name] = { title, icon, desc, build(panel), refresh }` and draws a `W.Dashboard`.
