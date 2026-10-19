# Upgrades — plano

The RatStash loot radar (the Spyglass on the bags) moves into Okanvil as a page in **RAID, under Loot**.
Mock: https://claude.ai/artifact/X6mAgvvrW8gbStY7eVAqh6

- **Name:** Upgrades
- **Icon:** `Interface\Icons\Spell_Fire_Incinerate`
- **Branch:** `feature/soft-reserve`. Keep it separate until it has been tested in a real raid.

## What it does

1. **Page:** pick the raid and the difficulty (10 / 25 / 10 HC / 25 HC). Each boss lists the drops that are upgrades for your **current** spec. Bosses killed this lockout are folded away, and the next boss is marked.
2. **Boss tooltip:** on mouseover or target, a boss in a raid gets a section "Upgrades · <spec>" with up to 3 lines and "+N more".
3. **Toggle:** an on/off switch in **Modules** and a **Shortcut** switch for the Raid Check bar. Both come for free from registering the plugin and adding it to `PANEL_KEY`. When the module is off, the tooltip hook does nothing and the page leaves the nav.

## When an item counts as an upgrade (no %)

In order:
1. It is **on your spec's BiS list** for the raid's phase and ranks above what you wear in that slot. Shown as **BiS #N**. This is the ranking logic from RatStash `Bis.lua`, including the tier-set rule.
2. Otherwise, it has a **higher ilvl** than what you wear in that slot (for rings and trinkets, the weaker of the two). Shown as **+N ilvl**.

The item must also pass two existing checks:
- `Okanvil.Prof.CanIUse`, for the class's armor and weapons.
- `Okanvil.Prof.StatsFitMe`, for the spec's stats. A DK never sees a spell-power neck.

## Spec

The talent tree with the most points.
- **Blood DK:** Tank in Frost Presence, DPS otherwise. Reuses `RaidFinder_BloodRole`.
- **Feral:** Tank in Bear Form, DPS otherwise.
- **Warrior/Paladin Protection:** Tank.

It refreshes on a talent swap, a presence or form change, and an equipment change.

## Files

| File | What |
|---|---|
| `Modules/Upgrades-Bis-Data.lua` | Copy of RatStash `BisData.lua` (Bistooltip's MIT notice kept) → `OkanvilBis` |
| `Modules/Upgrades.lua` | Spec, judge, kill tracking, tooltip hook |
| `Modules/Upgrades-UI.lua` | Page + plugin registration |
| `Core/UI/Shell.lua` | `NAV_GROUPS` (after Loot), `PANEL_KEY`, `ICONS.upgrades` |
| `Okanvil.toc` | 3 new files, after `RaidLoot-Data.lua` (a new file needs a full WoW restart) |

Reused, nothing new: `OkanvilRaidLoot` (bosses and drops), `SR.LockKey` (raid ID), `Okanvil.Prof`, `W.*`.

## Killed bosses

3.3.5a has no per-boss lockout API. The module stores the bosses this character killed, per `SR.LockKey`, from `UNIT_DIED` in the combat log. Encounters without a single death need aliases: Gunship, Valithria, Faction Champions, Council, Twins, Four Horsemen, Iron Council. Anything unmatched just stays unfolded.

## Steps

1. BiS data + judge + spec (no UI). Test with `/okup test <itemlink>`.
2. Page (mock layout).
3. Boss tooltip.
4. Modules/Shortcut toggle + nav.
5. Kill tracking.
6. In-game test → then decide what happens to the RatStash radar (remove the Spyglass or leave it).

## Not in it

- No upgrade %.
- No drop toast or sound for now. RatStash already has them.
- No sync with the raid. Each player sees only their own data.
