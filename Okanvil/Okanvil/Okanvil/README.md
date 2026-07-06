# Okanvil

MRT-style raid & guild toolkit for WoW **3.3.5a / Warmane**. One gold-themed
window, a left nav, each tool a per-character toggleable module. Forged by
**Okanor**. Product name is fixed; only the guild skin (`db.brand`) is editable.

> **Addon lives in the nested `Okanvil\` folder.** Edit source here; the live
> `…\AddOns\Okanvil\` copy is synced separately. New addon folder → full game
> RESTART; code-only change → `/reload`.

## Docs

| Doc | What |
|---|---|
| [PLAN.md](PLAN.md) | Roadmap, module list, branding model, build notes |
| [docs/STORAGE.md](docs/STORAGE.md) | **SavedVariables layout** — account-wide vs per-character (loot history is per-char!). Read before wiping/debugging saved data |
| [Media/README.md](Media/README.md) | Art / textures notes |

## Layout

- `Okanvil.toc` — load order + SavedVariables declaration
- `Core\` — Core, Comms, Widgets, UI (the shell + shared widget layer `Okanvil.W`)
- `Modules\` — Guild, Loot, LootRoll, Invite, Recruit, IDs, Logs
- `Libs\` — embedded LibStub, CallbackHandler-1.0, LibSharedMedia-3.0
- `Media\` — fonts, textures, icons
