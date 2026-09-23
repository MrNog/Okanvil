# RATS notes, per difficulty

Built from the Kaze pack's **Aura Mastery** half (lines 1-230) -- the bottom
half assumes a ret with Divine Sacrifice, and Rellik has Aura Mastery only.

Every spell id was re-looked-up **by name** against a real log of that
difficulty, because an id is numbered per difficulty while the name is not.
Infest is `70541` on 10N, `73780` on 10HC and `73779` on 25N; a note copied
between them without this step waits for a cast that never comes.

Slots: Holy1 = **Okanor**, Holy2 = **Solanarrage**, Prot = **Mongoloide**,
RetAM = **Rellik** (Aura Mastery only, so every line of his is `{spell:31821}`).

---

## Reading the second column

The left column is what you type into the note. The right is what the fight
window draws: names in their class colour (shown here in **bold**), the clock
in its own column on the left, and each `{spell:}` as its icon. Markdown
cannot draw a WoW icon, so a stand-in emoji is used per spell -- enough to
check at a glance that a line names the right person and the right cooldown.

| icon | spell | id |
|---|---|---|
| 🟡 | Divine Sacrifice | `64205` |
| 🔵 | Aura Mastery | `31821` |
| 🟢 | Devotion Aura | `48942` |
| 🟣 | Shadow Resistance Aura | `48943` |
| ⚪ | Frost Resistance Aura | `48945` |
| 🔴 | Fire Resistance Aura | `48947` |
| 🟠 | Crusader Aura | `32223` |
| 💚 | Hand of Freedom | `1044` |
| 🛡️ | Hand of Protection | `10278` |
| 🔨 | Hammer of Justice | `10308` |
| ❤️ | Healthstone | `6262` |

Raid markers render as themselves: 💀 skull, ❌ cross, 🟦 square,
🌙 moon, 🔺 triangle, 🔷 diamond, 🟠 circle, ⭐ star.

> **`6262` is unverified.** Every other id here was looked up in the client's
> own harvested database; that one is not in it. If the Healthstone lines on
> the Lich King show a question mark in game, search "Healthstone" in the ID
> Finder and use what it gives.

# 10 normal

Note keys carry `(10)`.

### Lord Marrowgar (10)

| what you type | how it reads in game |
|---|---|
| `\|cfff58cbaOkanor\|r FFA {spell:64205} DSAC` | **Okanor** FFA 🟡 DSAC |


### Lady Deathwhisper (10)

| what you type | how it reads in game |
|---|---|
| `Frostbolt Volley 1` | Frostbolt Volley 1 |
| `Frostbolt Volley 2` | Frostbolt Volley 2 |
| `{time:00:11,SCC:72905:2}Frostbolt Volley 3 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48945}` | 00:11  Frostbolt Volley 3 - **Rellik** 🔵 AM ⚪ |
| `{time:00:21,SCC:72905:3}Frostbolt Volley 4 - \|cfff58cbaOkanath\|r {spell:31821} AM {spell:48945}` | 00:21  Frostbolt Volley 4 - **Okanath** 🔵 AM ⚪ |
| `\|cfff58cbaOkanor\|r FFA {spell:64205} DSAC` | **Okanor** FFA 🟡 DSAC |


### Gunship Battle (10)

| what you type | how it reads in game |
|---|---|
| `\|cfff58cbaOkanor\|r FFA {spell:64205} DSAC` | **Okanor** FFA 🟡 DSAC |


### Deathbringer Saurfang (10)

| what you type | how it reads in game |
|---|---|
| `Stun - Hammer of Justice` | Stun - Hammer of Justice |
| `{skull}\|cfff58cbaRellik\|r {spell:10308} - {cross}\|cfff58cbaOkanor\|r {spell:10308}` | 💀**Rellik** 🔨 - ❌**Okanor** 🔨 |
| `{time:00:50}High Energy 1 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48942}` | 00:50  High Energy 1 - **Rellik** 🔵 AM 🟢 |
| `{time:01:35}High Energy 2 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 01:35  High Energy 2 - **Okanor** 🟡 DSAC |
| `{time:02:55}High Energy 3 -\|cfff58cbaRellik\|r {spell:31821} AM {spell:48942}` | 02:55  High Energy 3 -**Rellik** 🔵 AM 🟢 |
| `{time:03:35}High Energy 4 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 03:35  High Energy 4 - **Okanor** 🟡 DSAC |
| `Low energy Boiling Blood:` | Low energy Boiling Blood: |
| `1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 1 - **Okanor** 🟡 DSAC |


### Rotface & Festergut (10)

| what you type | how it reads in game |
|---|---|
| `Rotface - Right` | Rotface - Right |
| `\|cfff58cbaOkanor\|r FFA {spell:64205} DSAC` | **Okanor** FFA 🟡 DSAC |
| | |
| `Festergut - Left` | Festergut - Left |
| `{time:00:05,SAA:72219:1}Pull - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:05  Pull - **Okanor** 🟡 DSAC |
| `{time:00:07,SAA:72219:1}Gastric Bloat - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48943}` | 00:07  Gastric Bloat - **Okanor** 🔵 AM 🟣 |
| `{time:02:13,SAA:72219:1}Pungent Blight 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 02:13  Pungent Blight 1 - **Okanor** 🟡 DSAC |


### Professor Putricide (10)

| what you type | how it reads in game |
|---|---|
| `\|cfff58cbaOkanor\|r FFA {spell:64205} DSAC` | **Okanor** FFA 🟡 DSAC |


### Blood Council (10)

| what you type | how it reads in game |
|---|---|
| `\|cfff58cbaOkanor\|r FFA {spell:64205} DSAC` | **Okanor** FFA 🟡 DSAC |


### Queen Lana'thel (10)

| what you type | how it reads in game |
|---|---|
| `Pull - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | Pull - **Okanor** 🟡 DSAC |
| `{time:01:33}Bloodbolt 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 01:33  Bloodbolt 1 - **Okanor** 🟡 DSAC |
| `Air Phase` | Air Phase |
| `\|cfff58cbaRellik\|r BOP {spell:10278} <bite 1>` | **Rellik** BOP 🛡️ <bite 1> |
| `\|cfff58cbaOkanor\|r BOP {spell:10278} <bite 2>` | **Okanor** BOP 🛡️ <bite 2> |


### Valithria Dreamwalker (10)

| what you type | how it reads in game |
|---|---|
| `{time:02:16}Portal 1 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:32223}` | 02:16  Portal 1 - **Okanor** 🔵 AM 🟠 |
| `{time:00:47}Portal 2 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:32223}` | 00:47  Portal 2 - **Rellik** 🔵 AM 🟠 |
| `{time:00:46}Portal 3` | 00:46  Portal 3 |
| `{time:00:46}Portal 4 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:32223}` | 00:46  Portal 4 - **Okanor** 🔵 AM 🟠 |


### Sindragosa (10)

| what you type | how it reads in game |
|---|---|
| `{time:00:05}Pull - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48945}` | 00:05  Pull - **Okanor** 🔵 AM ⚪ |
| `{time:00:10}Pull - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48945}` | 00:10  Pull - **Rellik** 🔵 AM ⚪ |
| `{time:00:05,SCS:70123:1}Unchained Magic - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:05  Unchained Magic - **Okanor** 🟡 DSAC |
| `P3` | P3 |
| `{time:00:05,SAA:70126:2}Frost Beacon 2 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:05  Frost Beacon 2 - **Okanor** 🟡 DSAC |
| `{time:00:05,SAA:70126:2}Frost Beacon 2 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48945}` | 00:05  Frost Beacon 2 - **Rellik** 🔵 AM ⚪ |
| `{time:00:05,SAA:70126:3}Frost Beacon 3 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48945}` | 00:05  Frost Beacon 3 - **Okanor** 🔵 AM ⚪ |


### The Lich King (10)

| what you type | how it reads in game |
|---|---|
| `Infest 1` | Infest 1 |
| `{time:00:04,SCS:70541:1}Infest 2 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48943}` | 00:04  Infest 2 - **Okanor** 🔵 AM 🟣 |
| `{time:00:23,SCS:70541:2}Infest 3 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:23  Infest 3 - **Okanor** 🟡 DSAC |
| `{time:00:23,SCS:70541:3}Infest 4 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48943}` | 00:23  Infest 4 - **Rellik** 🔵 AM 🟣 |
| `{time:00:13,SCS:70541:4}Infest 5 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:13  Infest 5 - **Okanor** 🟡 DSAC |
| `{time:00:23,SCS:70541:5}Infest 6 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48943}` | 00:23  Infest 6 - **Okanor** 🔵 AM 🟣 |
| `{time:00:23,SCS:70541:6}Infest 7 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48943}` | 00:23  Infest 7 - **Rellik** 🔵 AM 🟣 |
| `{time:00:23,SCS:70541:7}Infest 8 - Global Healthstone {spell:6262}` | 00:23  Infest 8 - Global Healthstone ❤️ |
| `{time:00:23,SCS:70541:8}Infest 9 - Global Healthstone {spell:6262}` | 00:23  Infest 9 - Global Healthstone ❤️ |
| `BOP targets` | BOP targets |
| `{star}\|cfff58cbaRellik\|r - {circle}\|cfff58cbaOkanor\|r` | ⭐**Rellik** - 🟠**Okanor** |
| `P3` | P3 |
| `{time:00:13,SCC:68980:1}Harvest Soul 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:13  Harvest Soul 1 - **Okanor** 🟡 DSAC |


### Halion (10)

> `SAA:74792` (unverified) -- not cast at this difficulty; that line will not fire.

| what you type | how it reads in game |
|---|---|
| `Freedoms` | Freedoms |
| `{time:00:03,SAA:74792:1}Shadow Debuff 1 - \|cfff58cbaOkanor\|r {spell:1044}` | 00:03  Shadow Debuff 1 - **Okanor** 💚 |
| `{time:00:22,SAA:74792:1}Shadow Debuff 2 - \|cfff58cbaRellik\|r {spell:1044}` | 00:22  Shadow Debuff 2 - **Rellik** 💚 |
| `{time:00:22,SAA:74792:2}Shadow Debuff 3 - \|cfff58cbaOkanor\|r {spell:1044}` | 00:22  Shadow Debuff 3 - **Okanor** 💚 |
| `{time:00:22,SAA:74792:3}Shadow Debuff 4 - \|cfff58cbaRellik\|r {spell:1044}` | 00:22  Shadow Debuff 4 - **Rellik** 💚 |


---

# 10 heroic

Note keys carry `(10) (HC)`.

### Lord Marrowgar (10) (HC)

| what you type | how it reads in game |
|---|---|
| `\|cfff58cbaOkanor\|r FFA {spell:64205} DSAC` | **Okanor** FFA 🟡 DSAC |


### Lady Deathwhisper (10) (HC)

| what you type | how it reads in game |
|---|---|
| `Frostbolt Volley 1` | Frostbolt Volley 1 |
| `Frostbolt Volley 2` | Frostbolt Volley 2 |
| `{time:00:11,SCC:72907:2}Frostbolt Volley 3 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48945}` | 00:11  Frostbolt Volley 3 - **Rellik** 🔵 AM ⚪ |
| `{time:00:21,SCC:72907:3}Frostbolt Volley 4 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48945}` | 00:21  Frostbolt Volley 4 - **Okanor** 🔵 AM ⚪ |
| `\|cfff58cbaOkanor\|r FFA {spell:64205} DSAC` | **Okanor** FFA 🟡 DSAC |


### Gunship Battle (10) (HC)

| what you type | how it reads in game |
|---|---|
| `\|cfff58cbaOkanor\|r FFA {spell:64205} DSAC` | **Okanor** FFA 🟡 DSAC |


### Deathbringer Saurfang (10) (HC)

| what you type | how it reads in game |
|---|---|
| `Stun - Hammer of Justice` | Stun - Hammer of Justice |
| `{skull}\|cfff58cbaRellik\|r {spell:10308} - {cross}\|cfff58cbaOkanor\|r {spell:10308}` | 💀**Rellik** 🔨 - ❌**Okanor** 🔨 |
| `{time:00:50}High Energy 1 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48942}` | 00:50  High Energy 1 - **Rellik** 🔵 AM 🟢 |
| `{time:01:35}High Energy 2 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 01:35  High Energy 2 - **Okanor** 🟡 DSAC |
| `{time:02:55}High Energy 3` | 02:55  High Energy 3 |
| `{time:03:35}High Energy 4 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 03:35  High Energy 4 - **Okanor** 🟡 DSAC |
| `Low energy Boiling Blood:` | Low energy Boiling Blood: |
| `1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 1 - **Okanor** 🟡 DSAC |
| `FFA.` | FFA. |
| `{skull}Stun1 - {cross}Rellik - {moon}Okanor` | 💀Stun1 - ❌Rellik - 🌙Okanor |


### Rotface & Festergut (10) (HC)

| what you type | how it reads in game |
|---|---|
| `Rotface - Right` | Rotface - Right |
| `\|cfff58cbaOkanor\|r FFA {spell:64205} DSAC` | **Okanor** FFA 🟡 DSAC |
| | |
| `Festergut - Left` | Festergut - Left |
| `{time:00:05,SAA:72552:1}Pull - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:05  Pull - **Okanor** 🟡 DSAC |
| `{time:00:07,SAA:72552:1}Gastric Bloat - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48943}` | 00:07  Gastric Bloat - **Okanor** 🔵 AM 🟣 |
| `{time:02:13,SAA:72552:1}Pungent Blight 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 02:13  Pungent Blight 1 - **Okanor** 🟡 DSAC |


### Professor Putricide (10) (HC)

| what you type | how it reads in game |
|---|---|
| `\|cfff58cbaOkanor\|r FFA {spell:64205} DSAC` | **Okanor** FFA 🟡 DSAC |


### Blood Council (10) (HC)

| what you type | how it reads in game |
|---|---|
| `\|cfff58cbaOkanor\|r FFA {spell:64205} DSAC` | **Okanor** FFA 🟡 DSAC |


### Queen Lana'thel (10) (HC)

| what you type | how it reads in game |
|---|---|
| `Pull - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | Pull - **Okanor** 🟡 DSAC |
| `{time:01:33}Bloodbolt 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 01:33  Bloodbolt 1 - **Okanor** 🟡 DSAC |
| `Air Phase` | Air Phase |
| `\|cfff58cbaRellik\|r BOP {spell:10278} <bite 1>` | **Rellik** BOP 🛡️ <bite 1> |
| `\|cfff58cbaOkanor\|r BOP {spell:10278} <bite 2>` | **Okanor** BOP 🛡️ <bite 2> |


### Valithria Dreamwalker (10) (HC)

| what you type | how it reads in game |
|---|---|
| `{time:02:16}Portal 1 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:32223}` | 02:16  Portal 1 - **Okanor** 🔵 AM 🟠 |
| `{time:00:47}Portal 2 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:32223}` | 00:47  Portal 2 - **Rellik** 🔵 AM 🟠 |
| `{time:00:46}Portal 3` | 00:46  Portal 3 |
| `{time:00:46}Portal 4 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:32223}` | 00:46  Portal 4 - **Okanor** 🔵 AM 🟠 |


### Sindragosa (10) (HC)

| what you type | how it reads in game |
|---|---|
| `{time:00:05}Pull - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48945}` | 00:05  Pull - **Okanor** 🔵 AM ⚪ |
| `{time:00:10}Pull - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48945}` | 00:10  Pull - **Rellik** 🔵 AM ⚪ |
| `{time:00:05,SCS:71048:1}Unchained Magic - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:05  Unchained Magic - **Okanor** 🟡 DSAC |
| `P3` | P3 |
| `{time:00:05,SAA:70126:2}Frost Beacon 2 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:05  Frost Beacon 2 - **Okanor** 🟡 DSAC |
| `{time:00:05,SAA:70126:2}Frost Beacon 2 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48945}` | 00:05  Frost Beacon 2 - **Rellik** 🔵 AM ⚪ |
| `{time:00:05,SAA:70126:3}Frost Beacon 3 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48945}` | 00:05  Frost Beacon 3 - **Okanor** 🔵 AM ⚪ |


### The Lich King (10) (HC)

| what you type | how it reads in game |
|---|---|
| `Infest 1` | Infest 1 |
| `{time:00:04,SCS:70541:1}Infest 2 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48943}` | 00:04  Infest 2 - **Okanor** 🔵 AM 🟣 |
| `{time:00:23,SCS:70541:2}Infest 3 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:23  Infest 3 - **Okanor** 🟡 DSAC |
| `{time:00:23,SCS:70541:3}Infest 4 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48943}` | 00:23  Infest 4 - **Rellik** 🔵 AM 🟣 |
| `{time:00:13,SCS:70541:4}Infest 5 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:13  Infest 5 - **Okanor** 🟡 DSAC |
| `{time:00:23,SCS:70541:5}Infest 6 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48943}` | 00:23  Infest 6 - **Okanor** 🔵 AM 🟣 |
| `{time:00:23,SCS:70541:6}Infest 7 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48943}` | 00:23  Infest 7 - **Rellik** 🔵 AM 🟣 |
| `{time:00:23,SCS:70541:7}Infest 8 - Global Healthstone {spell:6262}` | 00:23  Infest 8 - Global Healthstone ❤️ |
| `{time:00:23,SCS:70541:8}Infest 9 - Global Healthstone {spell:6262}` | 00:23  Infest 9 - Global Healthstone ❤️ |
| `BOP targets` | BOP targets |
| `{star}\|cfff58cbaRellik\|r - {circle}\|cfff58cbaOkanor\|r` | ⭐**Rellik** - 🟠**Okanor** |
| `P3` | P3 |
| `{time:00:13,SCC:68980:1}Harvest Soul 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:13  Harvest Soul 1 - **Okanor** 🟡 DSAC |


### Halion (10) (HC)

> `SAA:74792` (unverified) -- not cast at this difficulty; that line will not fire.

| what you type | how it reads in game |
|---|---|
| `Freedoms` | Freedoms |
| `{time:00:03,SAA:74792:1}Shadow Debuff 1 - \|cfff58cbaOkanor\|r {spell:1044}` | 00:03  Shadow Debuff 1 - **Okanor** 💚 |
| `{time:00:22,SAA:74792:1}Shadow Debuff 2 - \|cfff58cbaRellik\|r {spell:1044}` | 00:22  Shadow Debuff 2 - **Rellik** 💚 |
| `{time:00:22,SAA:74792:2}Shadow Debuff 3 - \|cfff58cbaOkanor\|r {spell:1044}` | 00:22  Shadow Debuff 3 - **Okanor** 💚 |
| `{time:00:22,SAA:74792:3}Shadow Debuff 4 - \|cfff58cbaRellik\|r {spell:1044}` | 00:22  Shadow Debuff 4 - **Rellik** 💚 |


---

# 25 normal

Note keys carry `no suffix -- this is the bare name`.

### Lord Marrowgar

| what you type | how it reads in game |
|---|---|
| `Marrowgar Trash - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | Marrowgar Trash - **Okanor** 🟡 DSAC |
| `{time:00:05}Pull - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:05  Pull - **Okanor** 🟡 DSAC |
| `{time:00:52}Bone Storm 1 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:52  Bone Storm 1 - **Mongoloide** 🟡 DSAC |
| `{time:01:04}Bone Storm 1 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 01:04  Bone Storm 1 - **Solanarrage** 🟡 DSAC |
| `{time:02:20}Bone Storm 2 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 02:20  Bone Storm 2 - **Okanor** 🟡 DSAC |
| `{time:02:32}Bone Storm 2 - \|cfff58cbaRellik\|r {spell:31821} AM` | 02:32  Bone Storm 2 - **Rellik** 🔵 AM |
| `AM FFA on Coldflame DMG` | AM FFA on Coldflame DMG |


### Lady Deathwhisper

| what you type | how it reads in game |
|---|---|
| `{time:00:11,SAR:70842:1}Frostbolt Volley 1 - \|cfff58cbaSolanarrage\|r {spell:31821} AM {spell:48945}` | 00:11  Frostbolt Volley 1 - **Solanarrage** 🔵 AM ⚪ |
| `{time:00:21,SCC:72906:1}Frostbolt Volley 2 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:21  Frostbolt Volley 2 - **Solanarrage** 🟡 DSAC |
| `{time:00:21,SCC:72906:2}Frostbolt Volley 3 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:21  Frostbolt Volley 3 - **Okanor** 🟡 DSAC |
| `{time:00:21,SCC:72906:3}Frostbolt Volley 4 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:21  Frostbolt Volley 4 - **Mongoloide** 🟡 DSAC |
| `{time:00:21,SCC:72906:4}Frostbolt Volley 5 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48945}` | 00:21  Frostbolt Volley 5 - **Rellik** 🔵 AM ⚪ |
| `{time:00:21,SCC:72906:5}Frostbolt Volley 6 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48945}` | 00:21  Frostbolt Volley 6 - **Okanor** 🔵 AM ⚪ |
| `{time:00:21,SCC:72906:6}Frostbolt Volley 7 - \|cfff58cbaSolanarrage\|r {spell:31821} AM {spell:48945}` | 00:21  Frostbolt Volley 7 - **Solanarrage** 🔵 AM ⚪ |


### Deathbringer Saurfang

| what you type | how it reads in game |
|---|---|
| `{time:00:50}High Energy 1 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:50  High Energy 1 - **Mongoloide** 🟡 DSAC |
| `{time:01:35}High Energy 2 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 01:35  High Energy 2 - **Okanor** 🟡 DSAC |
| `{time:02:55}High Energy 3 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 02:55  High Energy 3 - **Mongoloide** 🟡 DSAC |
| `{time:03:35}High Energy 4 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 03:35  High Energy 4 - **Okanor** 🟡 DSAC |
| `Low energy Boiling Blood:` | Low energy Boiling Blood: |
| `1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 1 - **Okanor** 🟡 DSAC |
| `2 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 2 - **Solanarrage** 🟡 DSAC |
| `FFA.` | FFA. |
| `{skull}Stun1 - {cross}Rellik - {square}Solanarrage - {moon}Okanor - {triangle}Mongoloide` | 💀Stun1 - ❌Rellik - 🟦Solanarrage - 🌙Okanor - 🔺Mongoloide |


### Rotface & Festergut

| what you type | how it reads in game |
|---|---|
| `Rotface - Right` | Rotface - Right |
| `{time:00:05,SAA:71224:1}Slime Spray 1 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:05  Slime Spray 1 - **Mongoloide** 🟡 DSAC |
| `{time:00:25,SCC:69508:1}Slime Spray 2 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:25  Slime Spray 2 - **Okanor** 🟡 DSAC |
| `{time:00:25,SCC:69508:2}Slime Spray 3 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:25  Slime Spray 3 - **Solanarrage** 🟡 DSAC |
| `{time:00:25,SCC:69508:3}Slime Spray 4` | 00:25  Slime Spray 4 |
| `{time:00:25,SCC:69508:4}Slime Spray 5` | 00:25  Slime Spray 5 |
| `{time:00:25,SCC:69508:5}Slime Spray 6 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:25  Slime Spray 6 - **Mongoloide** 🟡 DSAC |
| | |
| `Festergut - Left` | Festergut - Left |
| `{time:00:05,SAA:72551:1}Pull - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:05  Pull - **Okanor** 🟡 DSAC |
| `{time:00:07,SAA:72551:1}Gastric Bloat - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48943}` | 00:07  Gastric Bloat - **Okanor** 🔵 AM 🟣 |
| `{time:00:13,SAA:72551:1}Gastric Bloat - \|cfff58cbaSolanarrage\|r {spell:31821} AM {spell:48943}` | 00:13  Gastric Bloat - **Solanarrage** 🔵 AM 🟣 |
| `{time:00:19,SAA:72551:1}Gastric Bloat - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48943}` | 00:19  Gastric Bloat - **Rellik** 🔵 AM 🟣 |
| `{time:00:25,SAA:72551:1}Gastric Bloat - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:25  Gastric Bloat - **Mongoloide** 🟡 DSAC |
| `{time:00:30,SAA:72551:1}Gas Spore 1 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:30  Gas Spore 1 - **Solanarrage** 🟡 DSAC |
| `{time:02:13,SAA:72551:1}Pungent Blight 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 02:13  Pungent Blight 1 - **Okanor** 🟡 DSAC |
| `{time:02:19,SAA:72551:1}Gastric Bloat - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48943}` | 02:19  Gastric Bloat - **Okanor** 🔵 AM 🟣 |
| `{time:02:25,SAA:72551:1}Gastric Bloat - \|cfff58cbaSolanarrage\|r {spell:31821} AM {spell:48943}` | 02:25  Gastric Bloat - **Solanarrage** 🔵 AM 🟣 |
| `{time:02:31,SAA:72551:1}Gastric Bloat - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48943}` | 02:31  Gastric Bloat - **Rellik** 🔵 AM 🟣 |
| `{time:02:37,SAA:72551:1}Gastric Bloat - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 02:37  Gastric Bloat - **Mongoloide** 🟡 DSAC |
| `{time:02:42,SAA:72551:1}Gas Spore 1 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 02:42  Gas Spore 1 - **Solanarrage** 🟡 DSAC |


### Professor Putricide

| what you type | how it reads in game |
|---|---|
| `Intermission 1` | Intermission 1 |
| `{time:00:15,SCS:71966:1}Green Explosion - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:15  Green Explosion - **Okanor** 🟡 DSAC |
| `{time:00:25,SCS:71966:1}Green Explosion - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:25  Green Explosion - **Solanarrage** 🟡 DSAC |
| `Intermission 2` | Intermission 2 |
| `{time:00:15,SCS:71966:2}Green Explosion - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:15  Green Explosion - **Okanor** 🟡 DSAC |
| `{time:00:25,SCS:71966:2}Green Explosion - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:25  Green Explosion - **Solanarrage** 🟡 DSAC |
| `P3` | P3 |
| `{time:00:26,SAA:72463:1}Raid DMG - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:26  Raid DMG - **Mongoloide** 🟡 DSAC |
| `\|cfff58cbaSolanarrage\|r BOP {spell:10278} Taunt1` | **Solanarrage** BOP 🛡️ Taunt1 |


### Blood Council

| what you type | how it reads in game |
|---|---|
| `{time:00:05,SCS:73037:1}Shock 1 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:05  Shock 1 - **Mongoloide** 🟡 DSAC |
| `{time:00:05,SCS:73037:1}Shock 1 - \|cfff58cbaRellik\|r {spell:31821} AM{spell:48947}` | 00:05  Shock 1 - **Rellik** 🔵 AM🔴 |
| `{time:00:05,SCS:73037:2}Shock 2 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:05  Shock 2 - **Solanarrage** 🟡 DSAC |
| `{time:00:05,SCS:72040:1}Flame 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:05  Flame 1 - **Okanor** 🟡 DSAC |
| `{time:00:05,SCS:73037:3}Shock 3 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:05  Shock 3 - **Mongoloide** 🟡 DSAC |
| `{time:00:05,SCS:73037:3}Shock 3 - \|cfff58cbaRellik\|r {spell:31821} AM` | 00:05  Shock 3 - **Rellik** 🔵 AM |


### Queen Lana'thel

| what you type | how it reads in game |
|---|---|
| `{time:00:05}Pull - \|cfff58cbaOkanor\|r {spell:64205} DSAC + {spell:31821} AM{spell:48943}` | 00:05  Pull - **Okanor** 🟡 DSAC + 🔵 AM🟣 |
| `{time:00:50}Pact - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:50  Pact - **Solanarrage** 🟡 DSAC |
| `{time:01:20}Pact - \|cfff58cbaRellik\|r {spell:31821} AM{spell:48943}` | 01:20  Pact - **Rellik** 🔵 AM🟣 |
| `{time:02:15}Bloodbolt 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC + {spell:31821} AM{spell:48943}` | 02:15  Bloodbolt 1 - **Okanor** 🟡 DSAC + 🔵 AM🟣 |
| `{time:02:15}Bloodbolt 1 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 02:15  Bloodbolt 1 - **Mongoloide** 🟡 DSAC |
| `{time:04:00}Bloodbolt 2 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC + {spell:31821} AM{spell:48943}` | 04:00  Bloodbolt 2 - **Solanarrage** 🟡 DSAC + 🔵 AM🟣 |
| `{time:04:00}Bloodbolt 2 - \|cfff58cbaRellik\|r {spell:31821} AM{spell:48943}` | 04:00  Bloodbolt 2 - **Rellik** 🔵 AM🟣 |
| `{time:04:14}Pact - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 04:14  Pact - **Mongoloide** 🟡 DSAC |
| `{time:04:28}Bites - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 04:28  Bites - **Okanor** 🟡 DSAC |
| `{time:04:45}Pact - \|cfff58cbaOkanor\|r {spell:31821} AM{spell:48943}` | 04:45  Pact - **Okanor** 🔵 AM🟣 |
| `Bite targets BOPs` | Bite targets BOPs |
| `\|cfff58cbaOkanor\|r BOP {spell:10278} Bite3` | **Okanor** BOP 🛡️ Bite3 |
| `\|cfff58cbaSolanarrage\|r BOP {spell:10278} Bite4` | **Solanarrage** BOP 🛡️ Bite4 |


### Valithria Dreamwalker

| what you type | how it reads in game |
|---|---|
| `{time:01:08}Portal 1 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48943}` | 01:08  Portal 1 - **Okanor** 🔵 AM 🟣 |
| `{time:01:58}Portal 2 - \|cfff58cbaSolanarrage\|r {spell:31821} AM {spell:48943}` | 01:58  Portal 2 - **Solanarrage** 🔵 AM 🟣 |


### Sindragosa

| what you type | how it reads in game |
|---|---|
| `{time:00:05}Pull - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC + {spell:31821} AM {spell:48945}` | 00:05  Pull - **Solanarrage** 🟡 DSAC + 🔵 AM ⚪ |
| `{time:00:10}Pull - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48945}` | 00:10  Pull - **Okanor** 🔵 AM ⚪ |
| `{time:00:18}Pull - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48945}` | 00:18  Pull - **Rellik** 🔵 AM ⚪ |
| `{time:00:05,SCS:71047:1}Blistering Cold 1 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:05  Blistering Cold 1 - **Mongoloide** 🟡 DSAC |
| `{time:00:05,SAA:70126:1}Frost Beacon 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:05  Frost Beacon 1 - **Okanor** 🟡 DSAC |
| `{time:00:05,SCS:71047:2}Blistering Cold 2 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:05  Blistering Cold 2 - **Solanarrage** 🟡 DSAC |
| `{time:00:05,SAA:70126:2}Frost Beacon 2 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48945}` | 00:05  Frost Beacon 2 - **Rellik** 🔵 AM ⚪ |
| `{time:00:05,SCS:71047:3}Blistering Cold 3 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:05  Blistering Cold 3 - **Mongoloide** 🟡 DSAC |
| `P3` | P3 |
| `{time:00:05,SAA:70126:3}Frost Beacon 3 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:05  Frost Beacon 3 - **Okanor** 🟡 DSAC |
| `{time:00:05,SAA:70126:4}Frost Beacon 4 - \|cfff58cbaSolanarrage\|r {spell:31821} AM {spell:48945}` | 00:05  Frost Beacon 4 - **Solanarrage** 🔵 AM ⚪ |
| `{time:00:05,SAA:70126:5}Frost Beacon 5 - Global Healthstone {item:36892}` | 00:05  Frost Beacon 5 - Global Healthstone 🧪 |
| `{time:00:05,SCS:71047:4}Blistering Cold 4 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:05  Blistering Cold 4 - **Solanarrage** 🟡 DSAC |
| `{time:00:05,SAA:70126:6}Frost Beacon 6 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48945}` | 00:05  Frost Beacon 6 - **Okanor** 🔵 AM ⚪ |
| `{time:00:05,SAA:70126:7}Frost Beacon 7 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48945}` | 00:05  Frost Beacon 7 - **Rellik** 🔵 AM ⚪ |
| `{time:00:05,SAA:70126:8}Frost Beacon 8 - Global Healthstone {item:36892}` | 00:05  Frost Beacon 8 - Global Healthstone 🧪 |
| `{time:00:05,SAA:70126:9}Frost Beacon 9` | 00:05  Frost Beacon 9 |
| `{time:00:05,SCS:71047:5}Blistering Cold 5 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:05  Blistering Cold 5 - **Mongoloide** 🟡 DSAC |
| `{time:00:05,SAA:70126:10}Frost Beacon 10 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:05  Frost Beacon 10 - **Okanor** 🟡 DSAC |


### The Lich King

| what you type | how it reads in game |
|---|---|
| `{time:00:08}Infest 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:08  Infest 1 - **Okanor** 🟡 DSAC |
| `{time:00:23,SCS:73779:1}Infest 2 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:23  Infest 2 - **Solanarrage** 🟡 DSAC |
| `{time:00:23,SCS:73779:2}Infest 3 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48943}` | 00:23  Infest 3 - **Rellik** 🔵 AM 🟣 |
| `{time:00:23,SCS:73779:3}Infest 4 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:23  Infest 4 - **Mongoloide** 🟡 DSAC |
| `{time:00:23,SCS:73779:4}Infest 5 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48943}` | 00:23  Infest 5 - **Okanor** 🔵 AM 🟣 |
| `{time:02:10,SCS:73779:1}Intermission - \|cfff58cbaSolanarrage\|r {spell:31821} AM {spell:48943}` | 02:10  Intermission - **Solanarrage** 🔵 AM 🟣 |
| `{time:00:13,SCS:72262:1}Infest 6 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:13  Infest 6 - **Okanor** 🟡 DSAC |
| `{time:00:23,SCS:73779:6}Infest 7 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:23  Infest 7 - **Solanarrage** 🟡 DSAC |
| `{time:00:23,SCS:73779:7}Infest 8 - \|cfff58cbaRellik\|r {spell:31821} AM {spell:48943}` | 00:23  Infest 8 - **Rellik** 🔵 AM 🟣 |
| `{time:00:23,SCS:73779:8}Infest 9 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:23  Infest 9 - **Mongoloide** 🟡 DSAC |
| `{time:00:23,SCS:73779:9}Infest 10 - \|cfff58cbaOkanor\|r {spell:31821} AM {spell:48943}` | 00:23  Infest 10 - **Okanor** 🔵 AM 🟣 |
| `{time:00:23,SCS:73779:10}Infest 11 - \|cfff58cbaSolanarrage\|r {spell:31821} AM {spell:48943}` | 00:23  Infest 11 - **Solanarrage** 🔵 AM 🟣 |
| `{time:00:23,SCS:73779:11}Infest 12 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:23  Infest 12 - **Okanor** 🟡 DSAC |
| `{star}Mongoloide - {circle}Solanarrage - {diamond}Okanor` | ⭐Mongoloide - 🟠Solanarrage - 🔷Okanor |
| `P3` | P3 |
| `{time:00:13,SCS:72262:2}Harvest Soul 1 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:13  Harvest Soul 1 - **Solanarrage** 🟡 DSAC |
| `{time:01:45,SCC:74325:1}Harvest Soul 2 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 01:45  Harvest Soul 2 - **Okanor** 🟡 DSAC |


### Halion

> `SAA:74792` (unverified) -- not cast at this difficulty; that line will not fire.

| what you type | how it reads in game |
|---|---|
| `Freedoms` | Freedoms |
| `{time:00:03,SAA:74792:1}Shadow Debuff 1 - \|cfff58cbaOkanor\|r {spell:1044}` | 00:03  Shadow Debuff 1 - **Okanor** 💚 |
| `{time:00:22,SAA:74792:1}Shadow Debuff 2 - \|cfff58cbaRellik\|r {spell:1044}` | 00:22  Shadow Debuff 2 - **Rellik** 💚 |
| `{time:00:22,SAA:74792:2}Shadow Debuff 3 - \|cfff58cbaOkanor\|r {spell:1044}` | 00:22  Shadow Debuff 3 - **Okanor** 💚 |
| `{time:00:22,SAA:74792:3}Shadow Debuff 4 - \|cfff58cbaRellik\|r {spell:1044}` | 00:22  Shadow Debuff 4 - **Rellik** 💚 |
| `{time:00:22,SAA:74792:4}Shadow Debuff 5 - \|cfff58cbaOkanor\|r {spell:1044}` | 00:22  Shadow Debuff 5 - **Okanor** 💚 |
| `{time:00:22,SAA:74792:5}Shadow Debuff 6 - \|cfff58cbaRellik\|r {spell:1044}` | 00:22  Shadow Debuff 6 - **Rellik** 💚 |
| `{time:00:22,SAA:74792:6}Shadow Debuff 7 - \|cfff58cbaOkanor\|r {spell:1044}` | 00:22  Shadow Debuff 7 - **Okanor** 💚 |
| `{time:00:22,SAA:74792:7}Shadow Debuff 8 - \|cfff58cbaRellik\|r {spell:1044}` | 00:22  Shadow Debuff 8 - **Rellik** 💚 |
| `{time:00:22,SAA:74792:8}Shadow Debuff 9 - \|cfff58cbaOkanor\|r {spell:1044}` | 00:22  Shadow Debuff 9 - **Okanor** 💚 |
| `{time:00:22,SAA:74792:9}Shadow Debuff 10 - \|cfff58cbaRellik\|r {spell:1044}` | 00:22  Shadow Debuff 10 - **Rellik** 💚 |
| `{time:00:22,SAA:74792:10}Shadow Debuff 11 - \|cfff58cbaOkanor\|r {spell:1044}` | 00:22  Shadow Debuff 11 - **Okanor** 💚 |
| `{time:00:22,SAA:74792:11}Shadow Debuff 12 - \|cfff58cbaRellik\|r {spell:1044}` | 00:22  Shadow Debuff 12 - **Rellik** 💚 |
| `{time:00:22,SAA:74792:12}Shadow Debuff 13 - \|cfff58cbaOkanor\|r {spell:1044}` | 00:22  Shadow Debuff 13 - **Okanor** 💚 |
| `{time:00:22,SAA:74792:13}Shadow Debuff 14 - \|cfff58cbaRellik\|r {spell:1044}` | 00:22  Shadow Debuff 14 - **Rellik** 💚 |



---

# Trial of the Crusader


One note per boss, no size or difficulty suffix: the same plan is run at
every size, so these keys carry no `(10)` and no `(HC)`.


### Northrend Beasts

| what you type | how it reads in game |
|---|---|
| `{time:00:00,SCS:67648:1}Staggering Stomp 1 - \|cfff58cbaOkanor\|r {spell:31821} AM` | 00:00  Staggering Stomp 1 - **Okanor** 🔵 AM |
| `{time:00:00,SCS:67648:2}Staggering Stomp 2 - \|cfff58cbaSolanarrage\|r {spell:31821} AM` | 00:00  Staggering Stomp 2 - **Solanarrage** 🔵 AM |
| `{time:00:00,SCS:67648:3}Staggering Stomp 3 - \|cfff58cbaRellik\|r {spell:31821} AM` | 00:00  Staggering Stomp 3 - **Rellik** 🔵 AM |
| `{time:00:00,SCS:67616:1}Paralytic Spray 1 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:00  Paralytic Spray 1 - **Mongoloide** 🟡 DSAC |
| `{time:00:00,SCS:66821:1}Molten Spew 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:00  Molten Spew 1 - **Okanor** 🟡 DSAC |
| `{time:00:00,SCS:67616:2}Paralytic Spray 2 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:00  Paralytic Spray 2 - **Solanarrage** 🟡 DSAC |


### Lord Jaraxxus

| what you type | how it reads in game |
|---|---|
| `{time:00:00,SAA:67050:1}Incinerate Flesh 1 - \|cfff58cbaOkanor\|r {spell:48947} {spell:31821} AM` | 00:00  Incinerate Flesh 1 - **Okanor** 🔴 🔵 AM |
| `{time:00:00,SAA:67050:2}Incinerate Flesh 2 - \|cfff58cbaSolanarrage\|r {spell:48947} {spell:31821} AM` | 00:00  Incinerate Flesh 2 - **Solanarrage** 🔴 🔵 AM |
| `{time:00:00,SAA:67050:3}Incinerate Flesh 3 - \|cfff58cbaRellik\|r {spell:48947} {spell:31821} AM` | 00:00  Incinerate Flesh 3 - **Rellik** 🔴 🔵 AM |
| `{time:00:00,SCC:67902:1}Infernal Eruption - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:00  Infernal Eruption - **Mongoloide** 🟡 DSAC |


### Faction Champions

| what you type | how it reads in game |
|---|---|
| `{time:00:30}Burst inimigo - \|cfff58cbaOkanor\|r {spell:31821} AM` | 00:30  Burst inimigo - **Okanor** 🔵 AM |
| `{time:01:00}Segundo burst - \|cfff58cbaSolanarrage\|r {spell:31821} AM` | 01:00  Segundo burst - **Solanarrage** 🔵 AM |
| `{time:01:30}Foco em grupo - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 01:30  Foco em grupo - **Mongoloide** 🟡 DSAC |
| `{time:02:00}Freedom nos healers - \|cfff58cbaRellik\|r {spell:1044}` | 02:00  Freedom nos healers - **Rellik** 💚 |


### Val'kyr Twins

| what you type | how it reads in game |
|---|---|
| `{time:00:00,SCS:67307:1}Twin's Pact 1 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:00  Twin's Pact 1 - **Mongoloide** 🟡 DSAC |
| `{time:00:00,SCS:67183:1}Dark Vortex 1 - \|cfff58cbaOkanor\|r {spell:48943} {spell:31821} AM` | 00:00  Dark Vortex 1 - **Okanor** 🟣 🔵 AM |
| `{time:00:00,SCS:67307:2}Twin's Pact 2 - \|cfff58cbaSolanarrage\|r {spell:64205} DSAC` | 00:00  Twin's Pact 2 - **Solanarrage** 🟡 DSAC |
| `{time:00:00,SCS:67183:2}Dark Vortex 2 - \|cfff58cbaRellik\|r {spell:48943} {spell:31821} AM` | 00:00  Dark Vortex 2 - **Rellik** 🟣 🔵 AM |


### Anub'arak

| what you type | how it reads in game |
|---|---|
| `{time:00:00,SAA:68509:1}Penetrating Cold 1 - \|cfff58cbaOkanor\|r {spell:64205} DSAC` | 00:00  Penetrating Cold 1 - **Okanor** 🟡 DSAC |
| `{time:00:00,SAA:68509:2}Penetrating Cold 2 - \|cfff58cbaSolanarrage\|r {spell:48945} {spell:31821} AM` | 00:00  Penetrating Cold 2 - **Solanarrage** ⚪ 🔵 AM |
| `{time:00:00,SAA:68509:3}Penetrating Cold 3 - \|cfff58cbaMongoloide\|r {spell:64205} DSAC` | 00:00  Penetrating Cold 3 - **Mongoloide** 🟡 DSAC |
| `{time:00:00,SAA:68509:4}Penetrating Cold 4 - \|cfff58cbaRellik\|r {spell:48945} {spell:31821} AM` | 00:00  Penetrating Cold 4 - **Rellik** ⚪ 🔵 AM |
| `{time:00:00,SCS:68646:1}Fase 3 - Leeching Swarm` | 00:00  Fase 3 - Leeching Swarm |

