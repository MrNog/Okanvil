# Okanvil — UI kit makeover plan

Branch `feature/ui-kit-makeover`. Goal: Okanvil looks like Ratree and RatStash, following
`wow-addons/UI-KIT.md`. Nothing is coded until the mock gets a "sim".

Status: **round 1 built (2026-10-20), waiting for the in-game look.** Button style B.

Round 1 (done, uncommitted on the branch):
- Media/UI: kit sheets + `medallion.blp` (Forge site anvil).
- Widgets.lua: red plate = `primary`, quiet edged button = the rest, red X for any "X" button,
  kit checkbox (`W.Check`, `W.ToggleRow` = settings row), stepper (`W.Slider`), kit dropdown +
  list, kit field / holder edges, popup title bar + X, page title in Morpheus + framed icon,
  gold sections, `C.ok` and every green colour code → gold (guild-chat and item greens kept).
- Shell: kit title bar, medallion, status on the right as icon + name, collapse = minus button,
  framed nav icons, kit window colours, puck = medallion.
- Settings rebuilt in the kit layout; moved in: Fight notes, Raid Finder, Council auto-ask,
  Farm price, tooltip switches. "Invite" pill renamed Groups.
- Modules page: On / On bar checkbox columns, framed icons grey when off.
- Marks bar: X removed (right-click a mark clears), bronze edge.
- Mini roll: fixed size, 4 drops then it scrolls.

Next round (after the in-game look):
- Recruit Setup → Settings › Recruit (its widgets are refreshed from all over Recruit.lua).
- Segmented buttons → dropdowns per page (SR per player, sizes, difficulties, RF filters, …).
- Hint lines still on some pages; Setup's StaticPopup; ID Finder's FauxScrollFrame.
- The "found on the way" fixes in section 4, if wanted.

---

## 1. What changes, in one line each

| Today | After |
|---|---|
| Flat gold "primary" and grey "secondary" buttons | Every button is the red plate (`redplate.blp`), same height as the X |
| Text "X" close buttons (main window, popups, floating windows) | Retail red X (`redbutton2x.blp`), 24×24 |
| 30px header: icon + "Okanvil" + version + brand + green chips | 26px kit title bar, centred title, **medallion** top-left (Okanvil's own anvil icon, cut round) |
| ON/OFF buttons on settings rows (`W.ToggleRow`) | Kit checkbox at the row's right edge; the whole row toggles |
| `W.Check` flat square | Kit checkbox (`controls.blp`) |
| Sliders (`W.Slider`) | Kit stepper: **−  value  +** |
| Flat dropdown + ChatFrame arrow | Kit dropdown (`dropdown.blp`), solid list, tick on the current choice |
| Plain edit boxes, raw search boxes | Kit field (`controls.blp`); searches get the glass and the clear button |
| Segmented buttons that pick a value (1/2/3, 10/25, Normal/Heroic, filters) | Dropdowns |
| Green states (status chips, "Master Looter", Council "awarded", Attendance "extra", whisper "ok", countdown) | Gold; nothing green (item rarity and class colours stay as they are) |
| Hint lines and tooltips under settings | Removed; unclear labels renamed so they read alone |
| Page titles in Friz | **Morpheus** for page titles and the headers over art (the Ratree spec-header look) |
| Nav icons plain, gold edge stripe when active | Icons in the kit's octagon frame: gold frame = current page, grey = the rest |

Kept as they are: the left nav layout, the forge wallpaper and its fade, hairline rows (no
boxes), class-coloured names, item-quality colours, HUD overlays (marks bar, Raid Check toast,
fight notes, REC timer) stay plain dark, but their buttons and X switch to the kit.

---

## 2. How it is built (engineering)

Most of the addon draws through `Core/Widgets.lua`, so the swap is done **once there**, keeping
every constructor's signature. Pages restyle themselves without being touched; the per-page
work is only what the kit forbids (segmented buttons, green, hints) and the settings moves.

1. **Media** — copy from RatStash to `Okanvil/Media/UI/`: `redbutton2x`, `redplate`, `controls`,
   `dropdown`, `iconframes`, `ring`. Make `medallion.blp` from the Forge site's
   `okanvil.webp` (anvil) with `make_medallion.py`. Add `THIRD_PARTY_NOTICES.md` (Blizzard art
   line; DragonUI MIT text for any code ported from it).
2. **Widgets.lua** (same API, new look):
   - `W.Button` — every kind draws the red plate; `tab`/`tabOn` stay text tabs with a gold underline.
   - `W.Check` → kit checkbox 20×20. `W.ToggleRow` → kit settings row (30 tall, checkbox right,
     `desc` ignored). `W.Slider` → stepper with the same arguments.
   - `W.DropDown` + the shared menu → kit dropdown and kit list.
   - `W.EditBox` / `W.MultiEdit` → kit field edge.
   - New: `W.CloseButton`, `W.TitleBar`, `W.Medallion`, `W.FramedIcon`, `W.Search`,
     `W.SettingsSection`, `W.SettingsRow` (copied from `RatStash/Style.lua` + `Options.lua`).
   - `Okanvil:Popup/Confirm/Prompt/ShowExport/ShowImport` → title bar + red X + art.
   - Colours: window body `0.043,0.043,0.047`, border `0.235,0.204,0.157`; `C.ok` becomes gold.
3. **Shell** — title bar, medallion, red X, collapse as a red plate with a minus bar, status
   chips in gold, nav framed icons, "NAVIGATION" label removed (the medallion sits there).
4. **Settings page** rebuilt on the kit's two-column layout (section 4 below).
5. **Pages**, one commit each: Home → Loot (+ Council, SR, Wishlist, Priority) → Upgrades →
   Notes → Raid Finder → PuG → Ranking → Attendance → Recruit → ID Finder → Farm → Modules.
6. **Floating windows**: mini roll, SR / Wish panels, pick window, council raider frame + board +
   picker, Loot priority, Notes help / spells seen, Farm, Mini Raid Browser, Reserves, Snapshot,
   Whispers panel, Setup, Tour.
7. **Stock Blizzard pieces left**: ID Finder's `FauxScrollFrameTemplate` → Okanvil scroll; its raw
   search box → `W.Search`; Setup's `StaticPopup` (rival addons) → `Okanvil:Confirm`.
8. **Docs**: `DEFAULTS.md`, `SLASH_COMMANDS.md`, `Media/README.md` brought up to date.

Every step: `luac` check → sync to the HD client (stamp the latest tag in the `.toc`) →
**full WoW restart** for new textures → you test → next step. Push only on "push"; merge ships
as `[minor]`.

Risks: layouts with fixed heights (rows go from 44 to 30 tall), Loot.lua is at the 200-locals
limit (not touched beyond strings), textures stay ≤ 1024 per side.

---

## 3. Every page: what changes

| Page / window | Changes |
|---|---|
| **Shell** | Title bar + medallion + red X; nav framed icons; chips gold; footer unchanged |
| **Home** | "Okanvil" title in Morpheus; tiles unchanged; Online / Snapshots / Saved raids stay tabs; row buttons (inv, w, Recheck, Invite, Export, X) → red plates; saved-raid chips: heroic orange stays (difficulty, not state) |
| **Loot · Loot** | Header buttons red; **Loot mode** tiles → dropdown (see Q2); SR "Per player 1/2/3" → dropdown; raid picker → dropdown; Lock/Open → checkbox row "Whispers open"; collectors rows: field + Self/Target/Clear red plates |
| **Loot · History** | Row buttons red; drop outcome colours: green "given" → gold |
| **Loot · Priority** | Search → kit search; All/Reserved/Prio roll and Boss/Type → dropdowns |
| **Upgrades** | "BiS lists / For me" stay tabs (views); 10/10 HC/25/25 HC → dropdown; class/spec/raid → kit dropdowns; search → kit search |
| **Notes** | Raid+size tabs stay (they pick the note you are reading); Normal/Heroic → dropdown; Clear/Edit/?/ids → red plates; **Fight window pill moves to Settings › Raid** (Q3) |
| **Raid Finder** | SIZE/ROLE/TYPE segmented → three dropdowns; /w + Join → red plates; **Settings tab moves to Settings › Raid Finder** |
| **PuG** | 10/25/18 and Normal/Heroic → dropdowns; role − / + → kit sign buttons; reserve category toggles → checkboxes in the Reserves window; Whispers panel kit look |
| **Ranking** | Period and size → dropdowns; DPS / Healing / Tanking stay tabs (views) |
| **Attendance** | Tabs stay; green "extra" chip → grey frame (gold = our ID); rule buttons → dropdowns per raid size |
| **Recruit** | Rule ON/OFF → checkbox; **Setup pill moves to Settings › Recruit** (Q3) |
| **ID Finder** | Kit search; own scroll instead of Blizzard's |
| **Farm** | Start/Pause/Finish red; "Value loot at vendor price" → Settings › Tools |
| **Modules** | ON/OFF → checkbox; Shortcut/Hidden → second checkbox column "On bar" |
| **Settings** | Rebuilt, section 4 |
| **Mini roll / Council / SR / Pick / Farm / Popups** | Kit title bar + X + art; every button red; council response buttons BIS/Upgrade/Small/OS/Pass red plates |
| **HUDs** | Plain dark kept; marks-bar clear and REC Stop → red plates |

---

## 4. Settings review — where each one lives

Rule proposed: **Settings holds options** (things set once); **pages hold work** (things you do
during a raid). Today the options are spread over Settings, Raid Finder's own tab, Recruit's Setup
pill, Notes' Fight window pill, the Loot page and the Farm page; two PuG options sit under
"Invite" and Combat Log under "Raid".

New Settings pills (each one two kit columns):

| Pill | Sections → rows |
|---|---|
| **General** | WINDOW: Scale · Opacity · Text size · Font — BACKGROUND: Background art · Art strength — BEHAVIOUR: Close windows on a DBM pull — ABOUT: Version check · Run setup again |
| **Loot** | RECORD LOOT: Dungeons · Dungeon quality · Keep dungeon runs · Raids · Raid quality · Keep raid runs — ROLLS: Main spec message · Off spec message · Reserve message · Roll timer — COUNCIL: Ask when a corpse opens *(from Loot page)* — AWARD: Whisper the winner · Winner message — PRIORITY *(officers)*: One name per line |
| **Raid** | READY CHECK: Show on a ready check · Close when everyone is ready · Minutes on icons · Show missing buffs · Sort by · Size · Preview — MARKS BAR: Show the marks bar · Size · Pull timer — FIGHT NOTES *(from Notes)*: Only in the boss room · Only my lines · Background · Text size · Icon size · Sync with officers — COMBAT LOG: Ask when entering a raid · Start at the first pull · Lock the REC timer |
| **Groups** *(was Invite)* | INVITE: Invite on a keyword · From whispers · From guild chat · Keywords — PUG *(from Invite)*: Sort joiners by role · Also /yell the LFM |
| **Raid Finder** *(from its tab)* | GEAR: Gear score override · Short spec names — SCANNING: Chat channels · Yell · Keep scanning in the background — LIST: Show raids I'm saved to · Hide listings after · Minimum gear score — TOOLS: Verify achievement IDs |
| **Recruit** *(from its Setup pill)* | GUILD: Guild name — CHANNELS: Global · LFG · General · Custom channel · Custom every — INVITES: Auto-invite on a keyword · Keywords · Blacklist · Invite cooldown · Reply cooldown — SKIP: Guild members · My group · Friends — TOAST: Toast on join · Only while advertising · Move the toast |
| **Tools** | FARM: Value loot at vendor price *(from Farm page)* — TOOLTIPS *(new rows for switches that are slash-only today)*: Upgrade sound · BiS rank · Fits your spec · Drops from · Spell and item IDs |

Stays on its page (it is work, not a setting): Loot mode, SR intake/limit/raid/post/import,
council night start/end, Wishlist on / lock / clear, speed-run collectors, Notes "Follow the room",
Attendance rules (officer data that syncs), Recruit ad text + auto-replies.

Label renames (hint text goes, so labels must stand alone):

| Today | New |
|---|---|
| Dungeons / Raids (capture checks) | Record dungeon loot / Record raid loot |
| Log items of quality (column head) | Dungeon quality / Raid quality |
| Keep in history ×2 | Keep dungeon runs / Keep raid runs |
| Timer + "s (0 = off)" | Roll timer (stepper, 0 shows "Off") |
| Minutes left on each icon (inverted key) | Minutes on icons |
| Grey out missing buffs (inverted key) | Show missing buffs |
| Size ×2 | Size (under its own section header) |
| Forge wallpaper / Wallpaper strength | Background art / Art strength (same as RatStash) |
| Lock the REC timer | Lock the recording timer |
| Override GS | Gear score override |
| Keep notes in step with other officers | Sync notes with officers |
| Value loot at vendor price (off = use an auction addon) | Value loot at vendor price |
| Shortcut / Hidden (Modules) | On bar (checkbox) |
| Send each name on its own line | One name per line |

Found on the way (fix only if you say yes):
- Home's header hairline never draws: `"Interface\Buttons\WHITE8x8"` has single backslashes
  (`Page_Home.lua:60`).
- Modules hint says "Off = hidden from the menu"; Off really switches the module off.
- Invite module text still mentions the login toast and mass invite (both removed).
- `DEFAULTS.md` is out of date (art 30% vs 0.45, Combat Log autostart, snapshots 20 vs 10).
- Undocumented slash commands: `/okcouncil night|force|purge`, `/okwish lock|unlock`,
  `/oknotes anchors`, `/pug enchscan`, `/okanvil tour`.
- Keys with no UI (left alone, listed for later): `rollmgr.autoShow` (mini roll opens on loot),
  Recruit `welcome` reply text, `farm.scale`, `inspect.staleDays`, old PuG/Invite keys.

---

## 5. Decisions for you (the mock shows the recommended choice)

Feedback 2026-10-20 (on the first mock):
- Red plates everywhere: **not liked**. Mock now has A / B / C to compare (B = red only for each
  window's main action, the rest a quiet edged button; C = B + icon buttons on list rows).
- Title-bar status ("Council night", "Logging"): the underlined chips were **not liked**. Now on
  the right, before − and X: a small gold-framed icon + its name in gold; click opens it.
- Marks bar: the marks are the game's own raid-target icons; **no X** (right-click a mark clears
  it); Ready check and Pull are icons like the other shortcuts, not buttons.
- Mini roll: **fixed size**. Drop list is 4 rows tall and scrolls; the roll box is fixed too; the
  window never grows or shrinks with the item count.

1. **Button style** A / B / C (see above). Waiting for the pick.
2. **Loot mode tiles** (Council / SR / Roll). The kit says choices are dropdowns. Recommended:
   a dropdown "Loot mode" in the Loot header.
3. **Settings moves** in section 4 (Fight window, Raid Finder tab, Recruit Setup, Farm price,
   Council auto-ask). Recommended: all of them.
4. **Tools pill tooltips** (exposing slash-only switches as rows). Recommended: yes, they already
   exist; this only gives them a checkbox.
5. **Morpheus** for page titles and section headers over art. Recommended: page titles + the big
   card headers (like Ratree's HOLY 54).
6. **Modules descriptions**: keep the one-line description under each module (it is a list of
   features, not a setting), or drop it for the kit's calm rows. Recommended: keep.
