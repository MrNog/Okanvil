# Okanvil — plan / roadmap

**Okanvil** (say it: _"OK Anvil"_ — also **Okan**or+an**vil**) is an MRT-style **single addon** for
WoW **3.3.5a / Warmane**. One gold-themed window with a left nav; each tool is a **module you toggle
on/off per character** (like DBM/BigWigs). A **native core** (guild dashboard Home + Modules manager)
makes it useful with zero modules on. **It's all one addon — there are no standalone plugins.**

Forged by **Okanor** (main paladin; old rats knew him as Okanata — two separate toons). The product
name **"Okanvil"** and the author credit are **fixed**; only the _guild skin_ (`db.brand`) is
configurable — see **Branding** below.

**Addon lives in a nested `Okanvil\` folder.** The repo root holds dev files (README, `.github`,
`.claude`); the addon itself is `Projects\Okanvil\Okanvil\` (`Okanvil.toc` + `Core\ Modules\ Libs\
Media\ PLAN.md`). The build zips that subfolder as-is. Edit source here; the live `…\AddOns\Okanvil\`
copy is synced separately (Fork GUI / manual copy). **New addon folder → full game RESTART; code-only
→ `/reload`.**

---

## ✅ Core (shipped)

- `Okanvil.toc` → embedded libs → `Core\Core.lua` → `Core\Widgets.lua` → `Core\UI.lua`.
  SavedVariables: `Okanvil_DB`, `RecruitDB`, `OkanvilIDsDB`. **PerCharacter:** `OkanvilLogsDB`,
  `Okanvil_CharDB` (module enable state + the per-char loot session log).
- `Libs\` — embedded **LibStub**, **CallbackHandler-1.0**, **LibSharedMedia-3.0**.
- `Core.lua` — engine: DB+defaults, media API (`Font/Texture/NewText/ApplyFonts/Backdrop`),
  module registry (`Register/ProcessPlugins/CountPlugins`), **per-character module enable state**
  (`IsModuleEnabled/SetModuleEnabled`, `Okanvil_CharDB.modules[name].enabled`), `ShouldRecord()`
  (dungeon/raid capture toggles), boot + `/okanvil`.
- `Widgets.lua` — the **`Okanvil.W`** widget layer (mini-ELib, MRT-modelled): `Frame/Text/Button/
  Check/Slider/EditBox/MultiEdit/DropDown` + **`W.Dashboard`** (the shared header/tabs/drawer shell
  every module uses), `Okanvil:Skin`, one global clamped **DropDown**, `Okanvil:Popup` +
  `Okanvil:ShowExport` (shared copy dialog). Gold RATS-hub palette in `Okanvil.Colors`.
- `UI.lua` — shell: **fixed-size** movable window (non-resizable; a Scale slider replaces the resize
  grip) with a collapse-to-puck; scroll-vs-fill panels (anti-spill); the **nav order** is one editable
  list (`Okanvil.NAV_ORDER`); the shared **icon set** is `Okanvil.ICONS`. Pages: **Home** (guild
  dashboard — online roster with rank colors + per-row invite, 3 stat tiles, big online list),
  **Settings** (one page: appearance + media + branding, author badge bottom-right), **Modules**
  manager, minimap button. Every module page is a `W.Dashboard`.

**Wordmark:** `⚒ Okanvil` (anvil icon left, name as one clean word). Guild skin shows after it.
Author credit in the footer (`Okanvil by Okanor`, gold) + the Settings page badge.

---

## ✅ Modules (shipped, toggleable, ALL native)

Each fills `Okanvil_Plugins[name] = { title, desc, icon, build(panel), refresh }` and registers via
`Okanvil:Register`. **No standalone fallback** — the host is always present (it's one addon). Every
page draws into a `W.Dashboard` (gold header + optional tabs + optional drawer).

- **Guild** (`Modules\Guild.lua`) — guild dashboard + JSON roster export for the web hub; inline
  snapshot viewer. Dashboard header + single scroll.
- **Invite** (`Modules\Invite.lua`) — two ways to invite, never "everyone": **by rank** (tick ranks →
  button) or **this list** (roster picker → button). Roster picker is grouped by rank, class-colored,
  with a **live search filter**. Saved lists persist account-wide and have a **My Lists tab** (see
  members, Load / Auto / Delete). Auto-invite on login is guarded (`canAutoInvite`): only when solo or
  lead/assist of a **pure-guild** group — never in someone else's group or a pug raid. Keyword-invite
  has a **master enable** and is **mutually exclusive with Recruit** (both grab the "inv" whisper).
- **Recruit** (`Modules\Recruit.lua` + `RecruitLogic.lua`) — recruitment advertiser (auto-reply +
  auto-invite) for officers/pug leaders. Dashboard with Text/Settings/Filters tabs + a contacts
  drawer. Advertise channels: **Global · LFG · General** (+ one Custom). Turning it ON stands the
  Invite keyword-invite down (mutual exclusion).
- **Loot** (`Modules\Loot.lua`) — per-boss loot capture. **Sessions are PER CHARACTER** (you only see
  your own runs; stored in `Okanvil_CharDB`), keyed by a **run token** that bumps on each fresh
  dungeon entry (two runs of the same dungeon in a day = two sessions) and by lockout for raids.
  itemID de-dupe (double-opened corpses) + emblem/gem/mat filtering. Tabs: History (landing) ·
  Collectors · Messages · Settings (rarity threshold + dungeon/raid capture). **Collectors** auto
  master-loot Main/Frag/BoE — but an **empty field means DO NOTHING** (loot stays on the corpse to
  roll); nothing is ever swept to the ML by default, and only the real ML auto-gives.
- **Mini Roll Manager** (`Modules\LootRoll.lua`, `/okroll`, `Okanvil.RollMgr`) — RaidRoll-style
  floating window. Pops **the moment the need/greed prompt appears** (hooks Blizzard `GroupLootFrame`
  + `START_LOOT_ROLL`), auto-jumps the pager to the **newest boss**, animated "Rolling…" status with
  a countdown. ML gets Start Roll (MS/OS/Free/Stop) + Award/Clear + **Clear session loot**; a raider
  just watches and rolls (Roll MS 100 / Roll OS 99). ML-only controls are gated on the real loot
  method (no test toggles).
- **ID Finder** (`Modules\IDs.lua` + `IDs-Data.lua` seed) — find a spell/item **ID by name** for
  WeakAuras. Library + thin UI: `Okanvil.IDs.*` public API (`EnsureSpells / SpellID / FindSpell /
  FindItem / SearchItems / ItemName / RecordItem / SweepLoaded / FullScan / MergeSeed / ExportItems`
  + item↔spell link store). Spells = offline client scan; items = harvested (tooltip-hover,
  bags/bank/merchant, chat links) + Sweep. **Full scan** is risky and tucked behind an "advanced"
  footer. **Seed/Export:** scan once → _Export DB_ → paste into `Modules\IDs-Data.lua`
  (`OkanvilIDs_Seed`) so the shipped addon opens pre-filled. 2 columns (Spells/Auras · Items). `/okid`.
- **Combat Logs** (`Modules\Logs.lua`, `/oklog`) — one-click `/combatlog` with a movable/lockable
  **REC timer**, a **"log this raid?" prompt shown only on RAID entry** (never dungeons), a
  combat-drop watchdog that re-arms logging, and a **session history** naming the bosses you killed
  (raid list by NPC id/name + loot-confirmed for dungeon bosses via the Loot module). Dashboard page.

---

## ▶️ NEXT / open

- **Addon-comms layer (`SendAddonMessage`) — FUTURE, shared infra.** A general cross-client channel
  many features reuse (attendance, version-check, roster, loot-collector sync). Native
  `SendAddonMessage("OKANVIL", msg, "RAID")` + `CHAT_MSG_ADDON`, **versioned** payloads (`OKV1|…`),
  **~255 bytes/msg** so chunk + don't spam, fire-and-forget → pair PUSH with FETCH. **Trust by ROLE**
  (real ML / raid lead/assist) and **confirm before applying** (popup) — never silently overwrite.
  First consumers: share loot collectors (a new ML inherits Main/Frag/BoE) and fragment/BoE counters.
  Mirrors RCLootCouncil's `SendCommand`.
- **Master-loot give bug (from RCLootCouncil `ml_core.lua`).** `GiveMasterLoot` fails when
  `GetMasterLootCandidate(i)` is nil/stale for the winner. Root cause on 3.3.5a: the candidate list is
  **server-populated only when the loot window opens under master loot**; after an ML change / relog /
  desync the client loses it. The manual fix (swap ML and back) forces a resend — there is **no client
  API to re-request candidates**, so a "Fix master loot" button can't truly help. Best mitigation:
  docs (winner in range, loot window open) + the collectors-sync above for ML handoffs.
- **Event-gating for disabled modules:** a toggled-off module still registers events; make deeper
  gating opt-in per module (don't hook combat log / roster when off).
- **PNG art alpha:** okanor.png / anvil.png have black backgrounds (fine on dark GitHub). rat1.png is
  keyed transparent. rat1.blp is the in-game watermark.
- **Remember last open panel** across sessions (save `_current` to DB).
- Version-check / module-list niceties.

---

## 🎨 Branding rules (don't break these)

- **Product name "Okanvil" is FIXED** — a wordmark, not editable. It's the "Method Raid Tools" of this
  app; the pun ("OK Anvil") is deliberate.
- **Guild skin = `db.brand`** — the ONLY editable branding, shown after the wordmark and as a Home
  subtitle. `""` or `"Okanvil"` = no suffix. Repaint via `Okanvil.headerPaintBrand()`, never SetText
  the wordmark. Default `"RATS Guild Hub"`.
- **Author = Okanor** — fixed credit (footer + Settings badge). Never editable.
- `db.hubURL` (web hub) is editable next to the guild skin.

## 🔖 Versioning / releases

The **git tag is the single source of truth** — you never edit `## Version:` in the .toc by hand.

- Cut a release: `git tag v1.2.0 && git push --tags`. The Action stamps `1.2.0` into the staged
  `Okanvil.toc`, builds `Okanvil.zip`, publishes a **versioned release** (kept forever), and refreshes
  the rolling **Latest**.
- Just pushing to `main` (no tag) refreshes **only Latest** — a dev/bleeding-edge build, versioned
  `<lasttag>-dev+<sha>`.
- **Semver bump:** new module / feature = **MINOR** (1.1 → 1.2). Breaking change, e.g. wiping
  SavedVariables = **MAJOR** (1.x → 2.0). Bug-fix only = **PATCH** (1.2.0 → 1.2.1).

## 🏗️ Architecture rules (don't break these)

- It's **one addon**, no standalone plugins. The core is a native module host (Home + Modules); the
  tools are optional modules toggled **per character** (`Okanvil_CharDB.modules`).
- **Module enable = per character; content settings = account-wide.** (Disable Recruit on an alt but
  keep your recruit macros shared across toons.)
- Every module page uses **`W.Dashboard`** and **`Okanvil.W.*`** widgets — never hand-roll
  `CreateFrame`+`SetBackdrop` buttons.
- Registration is **load-order safe** via the shared `Okanvil_Plugins` global.
- 3.3.5a target (Interface 30300): guard retail APIs (`SetClipsChildren`→`Okanvil.Clip`,
  `SetResizeBounds`, `SetObeyStepOnDrag`); no `BackdropTemplate`/`Mixin`.
- Nav order lives in `Okanvil.NAV_ORDER`; the icon set in `Okanvil.ICONS` (nav icon == header icon).
- No local Lua interpreter → validate with the block-balancer (depth 0), then load in-game.

## File map

```
Projects\Okanvil\                 (repo root -- dev files only)
  README.md
  .github\workflows\package.yml    (zips Okanvil\ into Okanvil.zip on push to main)
  .claude\  .agents\  .gitignore
  Okanvil\                         (THE ADDON -- this folder is what ships)
    Okanvil.toc   PLAN.md  LICENSE  (PLAN/LICENSE dev-only, stripped from the zip)
    Core\      Core.lua  Widgets.lua  UI.lua
    Modules\   Guild.lua  Invite.lua  Recruit.lua  RecruitLogic.lua
               Loot.lua  LootRoll.lua  IDs.lua  IDs-Data.lua  Logs.lua
    Libs\      LibStub  CallbackHandler-1.0  LibSharedMedia-3.0
    Media\     anvil.png  okanor.png  rat1.png  rat1.blp
```
