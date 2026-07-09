# How the **RaidRoll** addon works (3.3.5a)

*A plain explanation of Musou's "Raid Roll" and its two plugins. Line numbers
point at the real source under `Interface/AddOns/RaidRoll*`.*

---

## 1. The three addons

RaidRoll ships as one core addon + two optional plugins:

| Addon | File(s) | Job |
|---|---|---|
| **RaidRoll** (core) | `RaidRoll_OnLoad.lua`, `RaidRoll_ExtraRollFrames.lua`, `RaidRoll_OptionsMenu.lua` | The roll window. Detects loot on a corpse, tracks `/roll` results, picks a winner, hands the item over with master loot. |
| **RaidRoll_LootTracker** | `RaidRoll_LootTracker.lua` | The loot **history** window ("Musou's Loot Tracker"). Stores what dropped, grouped into "windows", so you can Raid-Roll each item later. |
| **RaidRoll_EPGP** | `RaidRoll_EPGP.lua` | Optional EPGP priority layer on top of the roll winner logic. |

The core works alone (rolls). The LootTracker is what makes it *record* loot.
They talk to each other through **addon messages** (§3).

---

## 2. Capture: scan the corpse the moment it opens

RaidRoll captures loot when a **corpse opens**, by reading the full loot table
off the body.

### The trigger

```
RR_LootEventHook:RegisterEvent("LOOT_OPENED")      -- OnLoad.lua:487
...
if event == "LOOT_OPENED" then
    RR_SendItemInfo()                              -- OnLoad.lua:74-82
end
```

Every time a loot window opens, `RR_SendItemInfo()` runs.

### What RR_SendItemInfo does (OnLoad.lua:87–343)

1. **Identify the corpse.** Reads `UnitName("target")` / `UnitGUID("target")`,
   then checks the GUID's type nibble to confirm it's an NPC:

   ```lua
   local B = tonumber(mob_guid:sub(5,5), 16)
   local maskedB = B % 8                 -- same as & 0x7
   local knownTypes = {[0]="player",[3]="NPC",[4]="pet",[5]="vehicle"}
   if Type ~= "NPC" then mob_name = "Unknown" end   -- OnLoad.lua:104-114
   ```

   The boss name comes from the looted **target**; if the target isn't an NPC
   the mob is labelled `"Unknown"` instead of being mislabelled as a player.

2. **Walk every loot slot** with the standard 3.3.5a API:

   ```lua
   numLootItems = GetNumLootItems()
   for i=1,numLootItems do
       if LootSlotIsItem(i) then
           local lootIcon, lootName, lootQuantity, rarity = GetLootSlotInfo(i)
           local ItemLink = GetLootSlotLink(i)
           ...
       end
   end                                    -- OnLoad.lua:129-170
   ```

3. **Filter** each item (§5).

4. **Broadcast** each surviving item as an addon message (§3). Note it does *not*
   write to its own DB here — storage happens on receipt:

   ```lua
   String = Version .. "\a" .. player_name .. "\a" .. mob_name .. "\a"
          .. ItemId  .. "\a" .. lootName   .. "\a" .. ItemLvl
   if UnitInRaid("player") then SendAddonMessage("RRL", String, "RAID") end
   if IsInGuild()          then SendAddonMessage("RRL", String, "GUILD") end
   -- OnLoad.lua:290-340
   ```

   Fields are joined with `\a` (the BEL char, `\007`) — an invisible delimiter
   that won't appear in item names.

---

## 3. The broadcast: everyone shares one loot list

When you loot a boss, **only you** see that corpse's items — no other raider's
client knows what dropped. RaidRoll fixes this by having the looter **announce**
each drop to the raid over a hidden addon channel (`"RRL"`).

Every RaidRoll user's client **receives** that message and records it into their
own copy of the loot history. Result: the whole raid ends up with the same list,
no matter who physically opened the body.

```
Looter's client:  LOOT_OPENED → scan → SendAddonMessage("RRL", item, "RAID")
                                              │
                   ┌──────────────────────────┼───────────────────────────┐
                   ▼                          ▼                            ▼
   Raider A: RR_AddonMessageReceived   Raider B: ...receives...   Master Looter: ...receives...
   → store into RaidRoll_DB["Loot"]    → store                    → store + can Raid Roll it
```

### Receiving side (LootTracker.lua:321–651)

`RR_AddonMessageReceived(String, Channel)`:

- Splits the `\a`-separated string back into fields
  (`Version, player_name, mob_name, ItemId, lootName, ItemLvl` — LootTracker.lua:495).
- Honours a **channel gate**: GUILD messages are only accepted if you ticked
  *"Receive loot messages from guild"* (LootTracker.lua:328) — so you don't log
  loot from a guildie in a different raid.
- Re-runs the accept/reject filters (§5) on its side (it doesn't trust the sender
  blindly).
- Files the item into the current **window** (§4).

There's a small sync handshake too: if a client hears an `"RRL"` message it can't
parse (wrong/newer version), it replies `SendAddonMessage("RRL","Request",...)`
and looters re-broadcast their item info (OnLoad.lua:299-302, LootTracker.lua:53-64).

---

## 4. "Windows": grouping drops into loot events

The LootTracker doesn't store a flat list. It groups items into **windows**,
where one window ≈ "one boss's worth of loot".

```
RaidRoll_DB["Loot"] = {
    ["TOTAL WINDOWS"]  = 7,
    ["CURRENT WINDOW"] = 7,
    [1] = { ["MOB NAME"]="Gormok", ["LOOTER NAME"]="Okanor", ["TOTAL ITEMS"]=2,
            ["ITEM_1"] = { LOOTNAME=, ITEMLINK=, ICON=, WINNER="-", RECEIVED="-", ITEMLEVEL= },
            ["ITEM_2"] = { ... } },
    [2] = { ... },
    ...
}
```

### When a new window starts

Two rules decide whether an incoming item joins the current window or opens a new
one (LootTracker.lua:365-399):

1. **Duplicate-name guard** — if an item with the *same `lootName`* is already in
   the current window, it's treated as a re-scan and skipped:

   ```lua
   RR_DuplicateItemFound = false
   for i=1,TOTAL ITEMS do
       if ITEM_i.LOOTNAME == lootName then RR_DuplicateItemFound = true end
   end                                    -- LootTracker.lua:370-376
   ```

2. **30-second time gap** — a new window opens only when it's been >30 s since
   the last loot message:

   ```lua
   if RR_DuplicateItemFound == false then
       if GetTime() > (RR_LastLootMessageTime + 30) then
           ... TOTAL WINDOWS = TOTAL WINDOWS + 1 ...   -- new window
           RR_LastLootMessageTime = GetTime()
       end
   end                                    -- LootTracker.lua:388-399
   ```

Items arriving within 30 s of each other pile into **one window** (one boss); a
quiet gap of >30 s starts the next window (next boss). Because the dedup key is
*item name within the current window*, the same item name arriving twice in one
window is merged into a single row — which is how RaidRoll collapses the same
drop reported by several raiders into one entry.

---

## 5. The item filter (what's worth recording)

Applied on **both** send and receive. Three gates, all must pass
(OnLoad.lua:183-343, mirrored in LootTracker.lua:429-489):

**a) Quality gate** — `rarity > 3` (epic+) by default.

**b) Allow-list (force-include even if not epic)** — rare mats that ARE loot:

```lua
ItemId == 46110   -- Alchemist's Cache
ItemId == 47556   -- Crusader Orb
ItemId == 45087   -- Runed Orb
ItemId == 49908   -- Primordial Saronite     (OnLoad.lua:184-188)
```

**c) Deny-list (force-exclude even if epic)** — currency / gems / DE mats:

```lua
34057 Abyss Crystal;  36919/36922/36925/36928/36931/36934 epic gems;
47241 Emblem of Triumph;  49426 Emblem of Frost            (OnLoad.lua:197-207)
```

**d) Zone gate** — only records inside real raids:

```lua
ZoneName == "Trial of the Crusader" / "Icecrown Citadel" / "Naxxramas" /
            "Onyxia's Lair" / "The Eye of Eternity" / "The Obsidian Sanctum" /
            "Ulduar" / "Vault of Archavon"
-- OR: GetInstanceInfo() ins_type == "raid"   (OnLoad.lua:219-240)
```

---

## 6. Rolling and awarding (the core, not the tracker)

Once loot is in a window, the officer clicks **Raid Roll** on a row
(LootTracker.lua:918 `RR_Loot_RaidRollButton`). That drives the roll window:

1. **Announce** the item in RAID/PARTY/SAY with a `/roll` instruction.
2. **Collect `/roll` results** from `CHAT_MSG_SYSTEM` (parsed against the
   `RANDOM_ROLL_RESULT` pattern) and match them to the open roll ID.
3. **Countdown** (60 s window; can finish early — ExtraRollFrames.lua:308-351).
4. **Pick the winner** via `RR_FindWinner(rollID)` → highest eligible roll
   (EPGP-adjusted if the plugin is on).
5. **Give the loot** (ExtraRollFrames.lua:666-835):

```lua
function RR_FinishRolling()
    ...
    numLootItems = GetNumLootItems()
    for i=1,numLootItems do
        if LootSlotIsItem(i) then
            local id1 = itemId(GetLootSlotLink(i))
            local id2 = itemId(rr_Item[rr_CurrentRollID])
            if id1 == id2 then RR_GiveLoot(Winner, i) end   -- match by itemID
        end
    end
end
```

`RR_GiveLoot` pops a **confirm dialog** ("Give [item] to X?"), then
`RR_ReallyGiveLoot` resolves the winner's name to a master-loot candidate index
and hands it over:

```lua
function RR_ReallyGiveLoot(player, slot)          -- ExtraRollFrames.lua:790-835
    for i = 1, 40 do
        if GetMasterLootCandidate(i)
           and string.lower(GetMasterLootCandidate(i)) == string.lower(player) then
            GiveMasterLoot(slot, i)               -- one-arg GetMasterLootCandidate
        end
    end
    if GetNumRaidMembers() == 0 then              -- 5-man party: scan party indices
        for i = 1, GetNumPartyMembers()+1 do ... end
    end
end
```

Note the 3.3.5a specifics: `GetMasterLootCandidate(i)` takes **one** argument, the
name compare is **case-insensitive**, and the candidate index range differs
between a raid (1–40) and a 5-man party (`1..GetNumPartyMembers()+1`).

---

## 7. Whole flow, end to end

```
                         ┌─────────────── LOOTER'S CLIENT ───────────────┐
  Boss dies, corpse   →  │ LOOT_OPENED                                    │
  opened               │ └→ RR_SendItemInfo()                            │
                         │    • identify NPC (GUID nibble == 3)           │
                         │    • GetNumLootItems / walk slots              │
                         │    • filter (quality / allow / deny / zone)    │
                         │    • SendAddonMessage("RRL", item, RAID+GUILD) │
                         └───────────────────────┬───────────────────────┘
                                                 │  (addon channel)
                         ┌───────────────── EVERY CLIENT ────────────────┐
                         │ CHAT_MSG_ADDON "RRL"                           │
                         │ └→ RR_AddonMessageReceived()                   │
                         │    • channel gate (guild opt-in)               │
                         │    • re-filter                                 │
                         │    • dedup: same NAME in window? / >30s gap?   │
                         │    • store into RaidRoll_DB["Loot"][window]    │
                         └───────────────────────┬───────────────────────┘
                                                 │
                   Officer opens Loot Tracker, clicks "Raid Roll" on a row
                                                 │
                         ┌────────────── ROLL + AWARD ───────────────────┐
                         │ announce → collect /roll → countdown →         │
                         │ RR_FindWinner → confirm → RR_ReallyGiveLoot    │
                         │ (match itemID in loot window, GiveMasterLoot)  │
                         └────────────────────────────────────────────────┘
```
