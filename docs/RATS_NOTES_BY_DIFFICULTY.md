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

# 10 normal

Note keys carry `(10)`.

### Lord Marrowgar (10)

```
|cfff58cbaOkanor|r FFA {spell:64205} DSAC
```

### Lady Deathwhisper (10)

```
Frostbolt Volley 1
Frostbolt Volley 2
{time:00:11,SCC:72905:2}Frostbolt Volley 3 - |cfff58cbaRellik|r {spell:31821} AM {spell:48945}
{time:00:21,SCC:72905:3}Frostbolt Volley 4 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48945}
|cfff58cbaOkanor|r FFA {spell:64205} DSAC
```

### Gunship Battle (10)

```
|cfff58cbaOkanor|r FFA {spell:64205} DSAC
```

### Deathbringer Saurfang (10)

```
Stun - Hammer of Justice
{skull}|cfff58cbaRellik|r {spell:10308} - {cross}|cfff58cbaOkanor|r {spell:10308}
{time:00:50}High Energy 1 - |cfff58cbaRellik|r {spell:31821} AM {spell:48942}
{time:01:35}High Energy 2 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:02:55}High Energy 3
{time:03:35}High Energy 4 - |cfff58cbaOkanor|r {spell:64205} DSAC
Low energy Boiling Blood:
1 - |cfff58cbaOkanor|r {spell:64205} DSAC
FFA.
{skull}Stun1 - {cross}Rellik - {moon}Okanor
```

### Rotface & Festergut (10)

```
Rotface - Right
|cfff58cbaOkanor|r FFA {spell:64205} DSAC

Festergut - Left
{time:00:05,SAA:72219:1}Pull - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:07,SAA:72219:1}Gastric Bloat - |cfff58cbaOkanor|r {spell:31821} AM {spell:48943}
{time:02:13,SAA:72219:1}Pungent Blight 1 - |cfff58cbaOkanor|r {spell:64205} DSAC
```

### Professor Putricide (10)

```
|cfff58cbaOkanor|r FFA {spell:64205} DSAC
```

### Blood Council (10)

```
|cfff58cbaOkanor|r FFA {spell:64205} DSAC
```

### Queen Lana'thel (10)

```
Pull - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:01:33}Bloodbolt 1 - |cfff58cbaOkanor|r {spell:64205} DSAC
Air Phase
|cfff58cbaRellik|r BOP {spell:10278} <bite 1>
|cfff58cbaOkanor|r BOP {spell:10278} <bite 2>
```

### Valithria Dreamwalker (10)

```
{time:00:55}Portal 1 - |cfff58cbaOkanor|r {spell:31821} AM {spell:32223}
{time:01:41}Portal 2 - |cfff58cbaOkanor|r {spell:31821} AM {spell:32223}
```

### Sindragosa (10)

```
{time:00:03}Pull - |cfff58cbaOkanor|r {spell:31821} AM {spell:48945}
{time:00:05}Pull - |cfff58cbaRellik|r {spell:31821} AM {spell:48945}
{time:00:05,SCS:70123:1}Unchained Magic - |cfff58cbaOkanor|r {spell:64205} DSAC
P3
{time:00:05,SAA:70126:2}Frost Beacon 2 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:05,SAA:70126:2}Frost Beacon 2 - |cfff58cbaRellik|r {spell:31821} AM {spell:48945}
{time:00:05,SAA:70126:3}Frost Beacon 3 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48945}
```

### The Lich King (10)

```
Infest 1
{time:00:04,SCS:70541:1}Infest 2 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48943}
{time:00:23,SCS:70541:2}Infest 3 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:23,SCS:70541:3}Infest 4 - |cfff58cbaRellik|r {spell:31821} AM {spell:48943}
{time:00:13,SCS:70541:4}Infest 5 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:23,SCS:70541:5}Infest 6 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48943}
{time:00:23,SCS:70541:6}Infest 7 - |cfff58cbaRellik|r {spell:31821} AM {spell:48943}
{time:00:23,SCS:70541:7}Infest 8 - Global Healthstone {spell:6262}
{time:00:23,SCS:70541:8}Infest 9 - Global Healthstone {spell:6262}
BOP targets
{star}|cfff58cbaRellik|r - {circle}|cfff58cbaOkanor|r
P3
{time:00:13,SCC:68980:1}Harvest Soul 1 - |cfff58cbaOkanor|r {spell:64205} DSAC
```

### Halion (10)

> `SAA:74792` (unverified) -- not cast at this difficulty; that line will not fire.

```
Freedoms
{time:00:03,SAA:74792:1}Shadow Debuff 1 - |cfff58cbaOkanor|r {spell:1044}
{time:00:22,SAA:74792:1}Shadow Debuff 2 - |cfff58cbaRellik|r {spell:1044}
{time:00:22,SAA:74792:2}Shadow Debuff 3 - |cfff58cbaOkanor|r {spell:1044}
{time:00:22,SAA:74792:3}Shadow Debuff 4 - |cfff58cbaRellik|r {spell:1044}
```

---

# 10 heroic

Note keys carry `(10) (HC)`.

### Lord Marrowgar (10) (HC)

```
|cfff58cbaOkanor|r FFA {spell:64205} DSAC
```

### Lady Deathwhisper (10) (HC)

```
Frostbolt Volley 1
Frostbolt Volley 2
{time:00:11,SCC:72907:2}Frostbolt Volley 3 - |cfff58cbaRellik|r {spell:31821} AM {spell:48945}
{time:00:21,SCC:72907:3}Frostbolt Volley 4 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48945}
|cfff58cbaOkanor|r FFA {spell:64205} DSAC
```

### Gunship Battle (10) (HC)

```
|cfff58cbaOkanor|r FFA {spell:64205} DSAC
```

### Deathbringer Saurfang (10) (HC)

```
Stun - Hammer of Justice
{skull}|cfff58cbaRellik|r {spell:10308} - {cross}|cfff58cbaOkanor|r {spell:10308}
{time:00:50}High Energy 1 - |cfff58cbaRellik|r {spell:31821} AM {spell:48942}
{time:01:35}High Energy 2 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:02:55}High Energy 3
{time:03:35}High Energy 4 - |cfff58cbaOkanor|r {spell:64205} DSAC
Low energy Boiling Blood:
1 - |cfff58cbaOkanor|r {spell:64205} DSAC
FFA.
{skull}Stun1 - {cross}Rellik - {moon}Okanor
```

### Rotface & Festergut (10) (HC)

```
Rotface - Right
|cfff58cbaOkanor|r FFA {spell:64205} DSAC

Festergut - Left
{time:00:05,SAA:72552:1}Pull - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:07,SAA:72552:1}Gastric Bloat - |cfff58cbaOkanor|r {spell:31821} AM {spell:48943}
{time:02:13,SAA:72552:1}Pungent Blight 1 - |cfff58cbaOkanor|r {spell:64205} DSAC
```

### Professor Putricide (10) (HC)

```
|cfff58cbaOkanor|r FFA {spell:64205} DSAC
```

### Blood Council (10) (HC)

```
|cfff58cbaOkanor|r FFA {spell:64205} DSAC
```

### Queen Lana'thel (10) (HC)

```
Pull - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:01:33}Bloodbolt 1 - |cfff58cbaOkanor|r {spell:64205} DSAC
Air Phase
|cfff58cbaRellik|r BOP {spell:10278} <bite 1>
|cfff58cbaOkanor|r BOP {spell:10278} <bite 2>
```

### Valithria Dreamwalker (10) (HC)

```
{time:00:55}Portal 1 - |cfff58cbaOkanor|r {spell:31821} AM {spell:32223}
{time:01:41}Portal 2 - |cfff58cbaRellik|r {spell:31821} AM {spell:32223}
```

### Sindragosa (10) (HC)

```
{time:00:03}Pull - |cfff58cbaOkanor|r {spell:31821} AM {spell:48945}
{time:00:05}Pull - |cfff58cbaRellik|r {spell:31821} AM {spell:48945}
{time:00:05,SCS:71048:1}Unchained Magic - |cfff58cbaOkanor|r {spell:64205} DSAC
P3
{time:00:05,SAA:70126:2}Frost Beacon 2 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:05,SAA:70126:2}Frost Beacon 2 - |cfff58cbaRellik|r {spell:31821} AM {spell:48945}
{time:00:05,SAA:70126:3}Frost Beacon 3 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48945}
```

### The Lich King (10) (HC)

```
Infest 1
{time:00:04,SCS:70541:1}Infest 2 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48943}
{time:00:23,SCS:70541:2}Infest 3 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:23,SCS:70541:3}Infest 4 - |cfff58cbaRellik|r {spell:31821} AM {spell:48943}
{time:00:13,SCS:70541:4}Infest 5 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:23,SCS:70541:5}Infest 6 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48943}
{time:00:23,SCS:70541:6}Infest 7 - |cfff58cbaRellik|r {spell:31821} AM {spell:48943}
{time:00:23,SCS:70541:7}Infest 8 - Global Healthstone {spell:6262}
{time:00:23,SCS:70541:8}Infest 9 - Global Healthstone {spell:6262}
BOP targets
{star}|cfff58cbaRellik|r - {circle}|cfff58cbaOkanor|r
P3
{time:00:13,SCC:68980:1}Harvest Soul 1 - |cfff58cbaOkanor|r {spell:64205} DSAC
```

### Halion (10) (HC)

> `SAA:74792` (unverified) -- not cast at this difficulty; that line will not fire.

```
Freedoms
{time:00:03,SAA:74792:1}Shadow Debuff 1 - |cfff58cbaOkanor|r {spell:1044}
{time:00:22,SAA:74792:1}Shadow Debuff 2 - |cfff58cbaRellik|r {spell:1044}
{time:00:22,SAA:74792:2}Shadow Debuff 3 - |cfff58cbaOkanor|r {spell:1044}
{time:00:22,SAA:74792:3}Shadow Debuff 4 - |cfff58cbaRellik|r {spell:1044}
```

---

# 25 normal

Note keys carry `no suffix -- this is the bare name`.

### Lord Marrowgar

```
Marrowgar Trash - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:05}Pull - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:52}Bone Storm 1 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:01:04}Bone Storm 1 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
{time:02:20}Bone Storm 2 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:02:32}Bone Storm 2 - |cfff58cbaRellik|r {spell:31821} AM
AM FFA on Coldflame DMG
```

### Lady Deathwhisper

```
{time:00:11,SAR:70842:1}Frostbolt Volley 1 - |cfff58cbaSolanarrage|r {spell:31821} AM {spell:48945}
{time:00:21,SCC:72906:1}Frostbolt Volley 2 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
{time:00:21,SCC:72906:2}Frostbolt Volley 3 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:21,SCC:72906:3}Frostbolt Volley 4 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:00:21,SCC:72906:4}Frostbolt Volley 5 - |cfff58cbaRellik|r {spell:31821} AM {spell:48945}
{time:00:21,SCC:72906:5}Frostbolt Volley 6 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48945}
{time:00:21,SCC:72906:6}Frostbolt Volley 7 - |cfff58cbaSolanarrage|r {spell:31821} AM {spell:48945}
```

### Deathbringer Saurfang

```
{time:00:50}High Energy 1 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:01:35}High Energy 2 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:02:55}High Energy 3 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:03:35}High Energy 4 - |cfff58cbaOkanor|r {spell:64205} DSAC
Low energy Boiling Blood:
1 - |cfff58cbaOkanor|r {spell:64205} DSAC
2 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
FFA.
{skull}Stun1 - {cross}Rellik - {square}Solanarrage - {moon}Okanor - {triangle}Mongoloide
```

### Rotface & Festergut

```
Rotface - Right
{time:00:05,SAA:71224:1}Slime Spray 1 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:00:25,SCC:69508:1}Slime Spray 2 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:25,SCC:69508:2}Slime Spray 3 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
{time:00:25,SCC:69508:3}Slime Spray 4
{time:00:25,SCC:69508:4}Slime Spray 5
{time:00:25,SCC:69508:5}Slime Spray 6 - |cfff58cbaMongoloide|r {spell:64205} DSAC

Festergut - Left
{time:00:05,SAA:72551:1}Pull - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:07,SAA:72551:1}Gastric Bloat - |cfff58cbaOkanor|r {spell:31821} AM {spell:48943}
{time:00:13,SAA:72551:1}Gastric Bloat - |cfff58cbaSolanarrage|r {spell:31821} AM {spell:48943}
{time:00:19,SAA:72551:1}Gastric Bloat - |cfff58cbaRellik|r {spell:31821} AM {spell:48943}
{time:00:25,SAA:72551:1}Gastric Bloat - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:00:30,SAA:72551:1}Gas Spore 1 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
{time:02:13,SAA:72551:1}Pungent Blight 1 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:02:19,SAA:72551:1}Gastric Bloat - |cfff58cbaOkanor|r {spell:31821} AM {spell:48943}
{time:02:25,SAA:72551:1}Gastric Bloat - |cfff58cbaSolanarrage|r {spell:31821} AM {spell:48943}
{time:02:31,SAA:72551:1}Gastric Bloat - |cfff58cbaRellik|r {spell:31821} AM {spell:48943}
{time:02:37,SAA:72551:1}Gastric Bloat - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:02:42,SAA:72551:1}Gas Spore 1 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
```

### Professor Putricide

```
Intermission 1
{time:00:15,SCS:71966:1}Green Explosion - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:25,SCS:71966:1}Green Explosion - |cfff58cbaSolanarrage|r {spell:64205} DSAC
Intermission 2
{time:00:15,SCS:71966:2}Green Explosion - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:25,SCS:71966:2}Green Explosion - |cfff58cbaSolanarrage|r {spell:64205} DSAC
P3
{time:00:26,SAA:72463:1}Raid DMG - |cfff58cbaMongoloide|r {spell:64205} DSAC
|cfff58cbaSolanarrage|r BOP {spell:10278} Taunt1
```

### Blood Council

```
{time:00:05,SCS:73037:1}Shock 1 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:00:05,SCS:73037:1}Shock 1 - |cfff58cbaRellik|r {spell:31821} AM{spell:48947}
{time:00:05,SCS:73037:2}Shock 2 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
{time:00:05,SCS:72040:1}Flame 1 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:05,SCS:73037:3}Shock 3 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:00:05,SCS:73037:3}Shock 3 - |cfff58cbaRellik|r {spell:31821} AM
```

### Queen Lana'thel

```
{time:00:05}Pull - |cfff58cbaOkanor|r {spell:64205} DSAC + {spell:31821} AM{spell:48943}
{time:00:50}Pact - |cfff58cbaSolanarrage|r {spell:64205} DSAC
{time:01:20}Pact - |cfff58cbaRellik|r {spell:31821} AM{spell:48943}
{time:02:15}Bloodbolt 1 - |cfff58cbaOkanor|r {spell:64205} DSAC + {spell:31821} AM{spell:48943}
{time:02:15}Bloodbolt 1 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:04:00}Bloodbolt 2 - |cfff58cbaSolanarrage|r {spell:64205} DSAC + {spell:31821} AM{spell:48943}
{time:04:00}Bloodbolt 2 - |cfff58cbaRellik|r {spell:31821} AM{spell:48943}
{time:04:14}Pact - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:04:28}Bites - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:04:45}Pact - |cfff58cbaOkanor|r {spell:31821} AM{spell:48943}
Bite targets BOPs
|cfff58cbaOkanor|r BOP {spell:10278} Bite3
|cfff58cbaSolanarrage|r BOP {spell:10278} Bite4
```

### Valithria Dreamwalker

```
{time:01:08}Portal 1 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48943}
{time:01:58}Portal 2 - |cfff58cbaSolanarrage|r {spell:31821} AM {spell:48943}
```

### Sindragosa

```
{time:00:05}Pull - |cfff58cbaSolanarrage|r {spell:64205} DSAC + {spell:31821} AM {spell:48945}
{time:00:10}Pull - |cfff58cbaOkanor|r {spell:31821} AM {spell:48945}
{time:00:18}Pull - |cfff58cbaRellik|r {spell:31821} AM {spell:48945}
{time:00:05,SCS:71047:1}Blistering Cold 1 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:00:05,SCS:69712:1}Frost Beacon 1 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:05,SCS:71047:2}Blistering Cold 2 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
{time:00:05,SCS:69712:2}Frost Beacon 2 - |cfff58cbaRellik|r {spell:31821} AM {spell:48945}
{time:00:05,SCS:71047:3}Blistering Cold 3 - |cfff58cbaMongoloide|r {spell:64205} DSAC
P3
{time:00:05,SCS:69712:3}Frost Beacon 3 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:05,SCS:69712:4}Frost Beacon 4 - |cfff58cbaSolanarrage|r {spell:31821} AM {spell:48945}
{time:00:05,SCS:69712:5}Frost Beacon 5 - |cfff58cba-|r {spell:64205} DSAC
{time:00:05,SCS:71047:4}Blistering Cold 4 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
{time:00:05,SCS:69712:6}Frost Beacon 6 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48945}
{time:00:05,SCS:69712:7}Frost Beacon 7 - |cfff58cbaRellik|r {spell:31821} AM {spell:48945}
{time:00:05,SCS:69712:8}Frost Beacon 8 - |cfff58cba-|r {spell:31821} AM {spell:48945}
{time:00:05,SCS:69712:9}Frost Beacon 9
{time:00:05,SCS:71047:5}Blistering Cold 5 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:00:05,SCS:69712:10}Frost Beacon 10 - |cfff58cbaOkanor|r {spell:64205} DSAC
```

### The Lich King

```
{time:00:08}Infest 1 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:23,SCS:73779:1}Infest 2 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
{time:00:23,SCS:73779:2}Infest 3 - |cfff58cbaRellik|r {spell:31821} AM {spell:48943}
{time:00:23,SCS:73779:3}Infest 4 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:00:23,SCS:73779:4}Infest 5 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48943}
{time:02:10,SCS:73779:1}Intermission - |cfff58cbaSolanarrage|r {spell:31821} AM {spell:48943}
{time:00:13,SCS:72262:1}Infest 6 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:23,SCS:73779:6}Infest 7 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
{time:00:23,SCS:73779:7}Infest 8 - |cfff58cbaRellik|r {spell:31821} AM {spell:48943}
{time:00:23,SCS:73779:8}Infest 9 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:00:23,SCS:73779:9}Infest 10 - |cfff58cbaOkanor|r {spell:31821} AM {spell:48943}
{time:00:23,SCS:73779:10}Infest 11 - |cfff58cbaSolanarrage|r {spell:31821} AM {spell:48943}
{time:00:23,SCS:73779:11}Infest 12 - |cfff58cbaOkanor|r {spell:64205} DSAC
{star}Mongoloide - {circle}Solanarrage - {diamond}Okanor
P3
{time:00:13,SCS:72262:2}Harvest Soul 1 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
{time:01:45,SCC:74325:1}Harvest Soul 2 - |cfff58cbaOkanor|r {spell:64205} DSAC
```

### Halion

> `SAA:74792` (unverified) -- not cast at this difficulty; that line will not fire.

```
Freedoms
{time:00:03,SAA:74792:1}Shadow Debuff 1 - |cfff58cbaOkanor|r {spell:1044}
{time:00:22,SAA:74792:1}Shadow Debuff 2 - |cfff58cbaRellik|r {spell:1044}
{time:00:22,SAA:74792:2}Shadow Debuff 3 - |cfff58cbaOkanor|r {spell:1044}
{time:00:22,SAA:74792:3}Shadow Debuff 4 - |cfff58cbaRellik|r {spell:1044}
{time:00:22,SAA:74792:4}Shadow Debuff 5 - |cfff58cbaOkanor|r {spell:1044}
{time:00:22,SAA:74792:5}Shadow Debuff 6 - |cfff58cbaRellik|r {spell:1044}
{time:00:22,SAA:74792:6}Shadow Debuff 7 - |cfff58cbaOkanor|r {spell:1044}
{time:00:22,SAA:74792:7}Shadow Debuff 8 - |cfff58cbaRellik|r {spell:1044}
{time:00:22,SAA:74792:8}Shadow Debuff 9 - |cfff58cbaOkanor|r {spell:1044}
{time:00:22,SAA:74792:9}Shadow Debuff 10 - |cfff58cbaRellik|r {spell:1044}
{time:00:22,SAA:74792:10}Shadow Debuff 11 - |cfff58cbaOkanor|r {spell:1044}
{time:00:22,SAA:74792:11}Shadow Debuff 12 - |cfff58cbaRellik|r {spell:1044}
{time:00:22,SAA:74792:12}Shadow Debuff 13 - |cfff58cbaOkanor|r {spell:1044}
{time:00:22,SAA:74792:13}Shadow Debuff 14 - |cfff58cbaRellik|r {spell:1044}
```


---

# Trial of the Crusader


One note per boss, no size or difficulty suffix: the same plan is run at
every size, so these keys carry no `(10)` and no `(HC)`.


### Northrend Beasts

```
{time:00:00,SCC:66330:1}Staggering Stomp 1 - |cfff58cbaOkanor|r {spell:31821} AM
{time:00:00,SCC:66330:2}Staggering Stomp 2 - |cfff58cbaSolanarrage|r {spell:31821} AM
{time:00:00,SCC:66330:3}Staggering Stomp 3 - |cfff58cbaRellik|r {spell:31821} AM
{time:00:00,SCC:66901:1}Paralytic Spray 1 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:00:00,SCC:66902:1}Burning Spray 1 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:00,SCC:66901:2}Paralytic Spray 2 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
```

### Lord Jaraxxus

```
{time:00:00,SAA:66237:1}Incinerate Flesh 1 - |cfff58cbaOkanor|r {spell:48947} {spell:31821} AM
{time:00:00,SAA:66237:2}Incinerate Flesh 2 - |cfff58cbaSolanarrage|r {spell:48947} {spell:31821} AM
{time:00:00,SAA:66237:3}Incinerate Flesh 3 - |cfff58cbaRellik|r {spell:48947} {spell:31821} AM
{time:00:00,SCC:66258:1}Infernal Volcano - |cfff58cbaMongoloide|r {spell:64205} DSAC
```

### Faction Champions

```
{time:00:30}Burst inimigo - |cfff58cbaOkanor|r {spell:31821} AM
{time:01:00}Segundo burst - |cfff58cbaSolanarrage|r {spell:31821} AM
{time:01:30}Foco em grupo - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:02:00}Freedom nos healers - |cfff58cbaRellik|r {spell:1044}
```

### Val'kyr Twins

```
{time:00:00,SCS:65875:1}Twin's Pact 1 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:00:00,SCS:66046:1}Vortex 1 - |cfff58cbaOkanor|r {spell:48943} {spell:31821} AM
{time:00:00,SCS:65875:2}Twin's Pact 2 - |cfff58cbaSolanarrage|r {spell:64205} DSAC
{time:00:00,SCS:66058:1}Vortex 2 - |cfff58cbaRellik|r {spell:48943} {spell:31821} AM
```

### Anub'arak

```
{time:00:00,SAA:66013:1}Penetrating Cold 1 - |cfff58cbaOkanor|r {spell:64205} DSAC
{time:00:00,SAA:66013:2}Penetrating Cold 2 - |cfff58cbaSolanarrage|r {spell:48945} {spell:31821} AM
{time:00:00,SAA:66013:3}Penetrating Cold 3 - |cfff58cbaMongoloide|r {spell:64205} DSAC
{time:00:00,SAA:66013:4}Penetrating Cold 4 - |cfff58cbaRellik|r {spell:48945} {spell:31821} AM
{time:00:05,p3}Fase 3 - Leeching Swarm
```
