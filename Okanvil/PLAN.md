# Okanvil — plan / roadmap

**Okanvil** (say it: _"OK Anvil"_ — also **Okan**or+an**vil**) is an ElvUI/MRT-style **host addon**
for WoW **3.3.5a / Warmane**. A single gold-themed window with a left nav; each tool is a **module
you toggle on/off** (like DBM/BigWigs). The host has a **native core** (guild dashboard Home +
Modules manager) so it's useful with zero plugins, and every plugin _also_ runs standalone.

Forged by **Okanor** (main paladin; old rats knew him as Okanata). The product name **"Okanvil"**
and the author credit are **fixed**; only the _guild skin_ (`db.brand`) is configurable — see
**Branding** below.

Monorepo: `Projects\OkanvilSuite\` — host `Okanvil\` + plugins `Okanvil-IDs / -Logs / -Recruit / -Guild`.
Edit source here; the live `…\AddOns\` copies are synced separately (Fork GUI / manual copy).
**New addon folder → full game RESTART; code-only change → `/reload`.**

---

## ✅ Host — Okanvil core (shipped)

- `Okanvil.toc` → embedded libs → `Core.lua` → `Widgets.lua` → `UI.lua`. SavedVar: `Okanvil_DB`.
- `Libs\` — embedded **LibStub**, **CallbackHandler-1.0**, **LibSharedMedia-3.0** (standalone-safe).
- `Core.lua` — engine: DB+defaults, media API (`Font/Texture/NewText/ApplyFonts/Backdrop`),
  plugin registry (`Register/ProcessPlugins/CountPlugins`), **module enable state**
  (`IsModuleEnabled/SetModuleEnabled`, `db.modules[name].enabled`), `ShouldRecord()` (dungeon/raid
  toggles), boot + `/okanvil`.
- `Widgets.lua` — the **`Okanvil.W`** widget layer (mini-ELib, MRT-modelled): `Frame/Text/Button/
Check/Slider/EditBox/MultiEdit/DropDown`, `Okanvil:Skin`, one global clamped **DropDown**,
  `Okanvil:Popup` + `Okanvil:ShowExport` (shared multi-line copy dialog). Gold RATS-hub palette in
  `Okanvil.Colors`.
- `UI.lua` — shell: resizable+movable window; scroll-vs-fill panels (anti-spill); **Home** guild
  dashboard (online roster w/ rank colors + per-row invite, tiles, web-hub card); **Settings**
  (appearance / media / branding / loot & recording / background art / **About**); **Modules**
  manager; minimap button.

**Wordmark:** `⚒ Okanvil` (anvil icon as logo on the left, name as one clean word). Guild skin
shows as a dim suffix after the version. Author credit in the footer + About card.

---

## ✅ Modules (shipped, toggleable)

Each fills `Okanvil_Plugins[name] = { title, desc, icon, build(panel), refresh }`, registers via
`Okanvil:Register`, and falls back to its own window if the host is absent. `## Dependencies: Okanvil`
(or OptionalDeps) in each `.toc`.

- **ID Finder** (`Okanvil-IDs`) — find a spell/item **ID by name** for WeakAuras. Refactored into a
  **library + thin UI**: `Okanvil.IDs.*` public API (`EnsureSpells / SpellID / FindSpell / FindItem /
ItemSpell / RecordItem / SweepLoaded / FullScan / MergeSeed / ExportItems` + item↔spell link store)
  that other addons can call. Spells = offline client scan (`GetSpellInfo 1..80000`). Items =
  harvested (tooltip-hover, bags/bank/merchant, chat links) + Sweep; **Full scan** brute-force is
  risky and tucked behind an "advanced" footer. **Seed/Export:** scan once → _Export DB_ → paste into
  `Okanvil-IDs-Data.lua` (`OkanvilIDs_Seed`, loaded before the main file) so the shared addon ships
  pre-filled; `MergeSeed` folds it in at boot (new ids only). 2 columns (**Spells/Auras · Items** —
  auras ARE spells, no separate column), id read off the row, no copy bar. Slash `/okid`.
  _(Removed: the live aura-catcher, the copy/pick/related/link UI — dead weight.)_
- **Combat Logs** (`Okanvil-Logs`) — one-click `/combatlog` with a movable/lockable **REC timer**,
  "log this instance?" prompt, combat-drop watchdog, and a **session history** that names the bosses
  you killed (raid list by NPC id/name + loot-confirmed for dungeon bosses via the Loot module).
  Card-based page (Start CTA + live status card + settings cards + inline-expandable past sessions).
  Slash `/oklog`.
- **Loot** (`Okanvil-Loot`, in the host) — per-boss loot capture with itemID de-dupe (double-opened
  corpses) + emblem/gem/mat filtering; inline session viewer with internal scroll; fair-loot Priority
  tab (attendance × items won, officer-only).
- **Guild** (host `Guild.lua`) — guild dashboard + JSON roster export for the web hub; inline snapshot
  viewer.
- **Invite** — native mass-invite: whole guild online, by rank, saved lists; keyword whisper + guild-
  chat invites; auto-invite on login; roster picker (grouped by rank, class-colored toggles).
- **Recruit** (host `Recruit.lua` + `RecruitLogic.lua`) — recruitment advertiser (auto-reply +
  auto-invite), dashboard + drawer layout. **Native module** (uses `W.Dashboard` heavily, so it can't
  be standalone) — toggle it off in Modules like the others.

---

## ▶️ NEXT / open

- **Seed the shipped item DB:** run Full scan once on a live client → Export DB → commit the result
  into `Okanvil-IDs-Data.lua` so guildmates open the finder already full.
- **Event-gating for disabled modules:** a toggled-off module still registers events; make deeper
  gating opt-in per plugin (don't hook combat log / roster when off).
- **PNG art alpha:** okanor.png / anvil.png have black backgrounds (README ok on dark GitHub; edge-
  flood-fill if transparency wanted). rat1.png already keyed to transparent.
- **Remember last open panel** across sessions (save `_current` to DB).
- **`Okanvil:GetDB(pluginName)`** so embedded plugins can store settings in the host DB.
- Version-check / plugin-list niceties.

---

## 🎨 Branding rules (don't break these)

- **Product name "Okanvil" is FIXED** — a wordmark, not editable. It's the "Method Raid Tools" of
  this app; the pun ("OK Anvil") is deliberate.
- **Guild skin = `db.brand`** — the ONLY editable branding, shown as a suffix after the wordmark and
  as a Home subtitle. `""` or `"Okanvil"` = no suffix. Repaint via `Okanvil.headerPaintBrand()`,
  never SetText the wordmark. Default `"RATS Guild Hub"`.
- **Author = Okanor** — fixed credit in the footer + About card. Never editable.
- `db.hubURL` (web hub) is editable next to the guild skin.

## 🏗️ Architecture rules (don't break these)

- Host has a **native core** (Home + Modules) — it is NOT empty; the 4 tools are optional modules.
- Plugins **never hard-depend** on Okanvil; always keep a standalone fallback + own minimap button.
- One **shared media** source (`Okanvil.db` font/texture/alpha) themes the whole suite.
- Registration is **load-order safe** via the shared `Okanvil_Plugins` global.
- Use **`Okanvil.W.*`** — never hand-roll `CreateFrame`+`SetBackdrop` buttons in plugins.
- 3.3.5a target (Interface 30300): guard retail APIs (`SetClipsChildren`→`Okanvil.Clip`,
  `SetResizeBounds`, `SetObeyStepOnDrag`); no `BackdropTemplate`/`Mixin`.
- No local Lua interpreter → validate with the block-balancer (depth 0), then load in-game.

## File map

```
Projects\OkanvilSuite\
  README.md                     (forge-themed, RATS-hub style)
  Okanvil\                      host
    Okanvil.toc  Core.lua  Widgets.lua  UI.lua
    Guild.lua  Loot.lua  Invite.lua  RecruitLogic.lua  Recruit.lua   (native modules)
    Libs\        Media\ (anvil.png, okanor.png, rat1.png/.blp)  PLAN.md (this file)
  Okanvil-IDs\    Okanvil-IDs.lua  Okanvil-IDs-Data.lua (seed)  .toc   (standalone plugin)
  Okanvil-Logs\   Okanvil-Logs.lua  .toc                              (standalone plugin)
```
