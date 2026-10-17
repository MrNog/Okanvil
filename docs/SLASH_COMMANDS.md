# ⌨️ Okanvil — slash commands

Type **`/okanvil help`** in game for this list, or **`/okanvil help <word>`** for only the
lines with that word (`/okanvil help wish`, `/okanvil help test`). The list lives in
`Okanvil.HELP` in `Core/Core.lua`; keep this page and that table together.

Every tool also opens from the **minimap button** and the window's nav.

<br>

## 👥 Everyone

| command | what it does |
|:--|:--|
| `/okanvil` | open or close the window |
| `/okanvil help [word]` | the command list in chat (only lines with that word) |
| `/okanvil tab` | send Okanvil's messages to their own `Okanvil` chat tab |
| `/okanvil setup` | the first-run setup again |
| `/okroll [stop]` | the mini roll window; `stop` ends the open roll |
| `/oktrade [clear]` | loot you still owe by trade, and to whom; `clear` forgets it |
| `/okrc [list \| say \| aura]` | raid check: the popup, a list in your chat, announce missing buffs, your own buffs |
| `/oknotes [send \| unlock \| watch]` | boss notes: status, send now, unlock editing on this character, watch the timers |
| `/okfarm start \| stop \| reset` | farm session: gold and items per hour |
| `/okver` | who in the group or guild runs Okanvil, and which version |
| `/okerr [clear]` | the error log (copyable, survives logout); `clear` empties it |
| `/okfocus` | free the keyboard if a text box is stuck on it — the panic button when W/A/S/D stop working |

## 📣 PuG leader

| command | what it does |
|:--|:--|
| `/pug start \| stop` | start or stop spamming the LFM line |
| `/pug send` | send the LFM line once |
| `/pug msg` | print the line that would be sent |

## 💰 Master looter / officer

| command | what it does |
|:--|:--|
| `/okres mode council \| sr \| roll` | tonight's loot mode |
| `/okres open \| lock` | take, or stop taking, `sr [item]` whispers (locks itself at the first pull) |
| `/okres post \| list` | raid chat: the SR rules, or every reserve and who made it |
| `/okres` | the soft-reserve list beside the mini roll |
| `/okwish on \| off` | wishlist for the council: raiders pick one item per raid ID in the window, or whisper you `wh [item]` |
| `/okwish clear` | clear every wish on this raid ID; everyone picks again |
| `/okcouncil board \| close` | reopen the council board, or end the round |
| `/okcouncil auto on \| off` | ask the council about every epic when a corpse opens |
| `/okcouncil ask [item links]` | a council round on items already in someone's bags |

Raiders **without Okanvil** use whispers: `sr [item]` to the master looter for a soft reserve,
`wh [item]` to whoever turned the wishlist on for a wish.

## 🏷️ Guild skin

| command | what it does |
|:--|:--|
| `/okanvil brand <name>` | your guild's name on the window (empty: clear) |
| `/okanvil hub <url>` | your guild's web hub link (empty: clear) |
| `/okanvil generic` | clear the guild skin and the web hub |

## 🧪 Testing, solo

| command | what it does |
|:--|:--|
| `/okcouncil test [n] \| test off` | a council round on gear you wear (3 items by default); nothing is given away |
| `/okres test \| test raider \| test off` | a soft-reserve night with test drops, or its pick window as a raider sees it |
| `/okres test w <name> sr [item]` | fake a reserve whisper from someone |
| `/okwish test` | your wish window |
| `/pug mock` | five fake players in the group, for the board and the audit |
| `/okloottest [id \| name \| world \| ml \| roll \| clear]` | fake drops in the loot list; `world` records outside instances |
| `/okanvil dev` | debug output to the Okanvil chat tab |
| `/okcomms` | every Okanvil addon message as it arrives (a firehose) |
