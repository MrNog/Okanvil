# Okanvil — what a fresh install ships with

What a brand-new user gets before touching anything: which modules run, which
switches are on, and what stays off until someone turns it on. Read from the
code's default tables (`defaults = {…}` in each module, and the `== nil` /
`~= false` fallbacks) — update this file when one of those changes.

**Rule of thumb:** everything that only *shows* or *records* is on; everything
that *sends something* on your behalf (spam, whispers, invites, loot hand-outs)
is off until you turn it on.

---

## First login

| What | Default | Notes |
|---|---|---|
| Welcome window (setup) | **Shown once** | Only on an install with no saved Okanvil data. Existing users never see it. `/okanvil setup` or *Settings → General → Run setup again* brings it back. |
| Modules ticked in the welcome window | **All on** | Unticking any of them and pressing Save switches it off for that character. Skip changes nothing. |
| Marks bar tick in the welcome window | **On** | Only applied when the user presses Save. |
| Minimap button | **On** | |

## Modules (per character)

Every module is **on** unless the user switches it off in *Modules* (or in the
welcome window). A switched-off module does nothing at all — no chat scanning,
no events, no UI.

| Module | Default | Notes |
|---|---|---|
| Loot | On | |
| Loot Council | On | The module is on; *council night* itself is off (see below). |
| Guild (snapshots + roster export) | On | |
| Combat Logs | On | |
| ID Finder | On | |
| PuG | On | Spamming is off (see below). |
| Raid Finder | On | |
| Recruit | On | Advertising is off (see below). |
| Notes | On | |
| Farm | On | |
| Invite | **Always on, no switch** | Not in the Modules list or the welcome window. Its only behaviour a user would notice — keyword auto-invite — has its own switch and is off. |

## General (Settings → General)

| Setting | Default |
|---|---|
| Window scale | 1.0 |
| Font | Friz Quadrata TT |
| Background art (rat blacksmith) | On, 30% opacity |
| Close all windows on a DBM pull | **On** |
| Guild skin (brand) / web hub URL | **Empty** — nothing guild-specific ships |
| Dev chat tab | Off |

## Loot (Settings → Loot, Loot page)

| Setting | Default | Notes |
|---|---|---|
| Record loot in raids | **On** | |
| Record loot in 5-man dungeons | **On** | |
| Minimum rarity recorded | Rare (blue) and up | |
| Speed-run auto master-loot | **Off** | Hands loot to the collector names — needs names set and the switch on. |
| Collector names (Main / Fragments / BoE) | Empty | |
| Whisper the collector's winner | Off | |
| Recording outside instances (world test) | Off | |

## Loot Council

| Setting | Default | Notes |
|---|---|---|
| Council night | **Off** | Per session, never saved as "on" for next week. |
| Ask when I become master looter | **On** | A popup asking whether tonight is a council night. Nothing is sent to the raid by it. |
| Ask the raid automatically when a corpse opens | **Off** | Only matters on a council night. |
| Hide the priority ladder on the board | Off | Only offered to officers / officers' alts — the only people who ever see the ladder. |
| Priority ladder + PRIO column on the board | Officers / officers' alts only | A non-officer master looter sees the board without them. |
| Whisper the winner when the item can't be given | On | Only fires after the master looter awards an item. |
| Who sees the board | Officers, officers' alts, the master looter | Raid assist does **not** count. |

## Guild / Snapshots

| Setting | Default | Notes |
|---|---|---|
| Automatic snapshot at the first pull in a raid | **On** | One per raid session. Specs come from a fresh inspect scan after combat. |
| Snapshots kept | Last 20 | |
| Inspect cache: specs trusted for | 7 days | Older entries are dropped at login. |

## Invite (Settings → Invite)

| Setting | Default |
|---|---|
| Auto-invite on a keyword | **Off** |
| On whisper | **Off** |
| On guild chat | **Off** |
| Keyword | `inv` |
| Re-invite after a decline / offline | On (30 s) |

## Recruit

| Setting | Default | Notes |
|---|---|---|
| Advertising | **Off** | Nothing is posted, answered or invited until *START advertising*. |
| Advert text | Empty | The guild writes its own. |
| Channel intervals (Global / LFG / General / custom) | **All 0 = off** | |
| Auto-invite people who whisper a keyword | On | **Only while advertising is ON.** |
| Invite keywords | `inv, invite, join, guild, raid, recruit, lf guild` | |
| Never-invite words (blacklist) | `gold, sell, selling, buy, boost, carry, gdkp, swipe, powerlevel, http, www, .com` | |
| Auto-replies | None configured | |
| Only reply while advertising is ON | On | |
| Never reply to someone in my group | On | |
| Skip guild members / group / friends | On / On / On | |
| Invite cooldown / reply cooldown | 300 s / 600 s | |
| Toast when someone joins the guild | On | Also when not advertising. |

## PuG

| Setting | Default |
|---|---|
| Spamming | **Off** |
| Raid / size / difficulty | ICC 25 Normal |
| Role targets | 2 Tank · 5 Healer · 8 Melee · 10 Ranged |
| Min GS, note, reserves | Empty / none |
| Auto-reply to applicants | **Off** |
| Post to guild chat | Off |
| Seat joiners into raid groups | On |

## Raid Finder

| Setting | Default | Notes |
|---|---|---|
| Scan trade / LookingForGroup channels | On | Only while the Raid Finder page or mini browser is open. |
| Scan yells | On | Same. |
| Keep scanning when the window is closed | **Off** | |
| Listing expires after | 60 s without a new spam | |
| Show raids you're saved to | On | Marked "Saved" in red. |
| Minimum GS filter | 0 (show all) | |

## Notes

| Setting | Default | Notes |
|---|---|---|
| Follow the room (switch note on entering a boss room) | On | |
| Share notes with other officers automatically | On | |
| Role slots ({Holy1}…) | Empty | A roster belongs to whoever installs this. |
| Shipped note pack | ICC | Used until you write your own note for a boss. |
| Fight window | Locked, 60% opacity, only in the boss's room | |

## Combat Logs

| Setting | Default |
|---|---|
| Prompt when entering a raid | Off (never asks) |
| Logging | Starts by itself at the first pull; the REC timer shows when it runs |

## Raid tools (Settings → Raid)

| Setting | Default |
|---|---|
| Ready-check popup | On |
| Close it when everyone is clear | On |
| Show numbers / show what's missing | On / On |
| Sort | By group |
| Marks bar | **Off** unless ticked in the welcome window (ticked by default there) |

## Farm

| Setting | Default |
|---|---|
| Item value | Auction price when known, else vendor |
| Window size | 100% |
