-- ============================================================
-- Okanvil -- Notes: the ICC pack that ships with the addon.
--
-- The community paladin-cooldown notes, in MRT syntax, as published. Data, not
-- behaviour: the next revision of the pack is a paste over this file.
--
-- ONE NOTE PER BOSS. The pack ships several plans for Sindragosa and the Lich
-- King, named by the cooldowns the raid brings ("2 air phases 3dsac 3am"); the
-- one taken here is 3 Divine Sacrifice + 3 Aura Mastery, which is what this
-- guild fields. Bring a different set of paladins and you edit the note, which
-- is what the pack's own instructions tell you to do anyway.
--
-- The role slots the pack ships with (Holy1, Holy2, Prot, Ret, RetAM) have been
-- replaced with this guild's paladins, because a slot name matches nobody and
-- the aura shows a line only when it contains YOUR name:
--
--   Holy1 -> Okanor        main hpala, the busier slot: 35 lines against 28,
--                          and the only one Halion uses at all
--   Holy2 -> Solanarrage
--   Prot  -> Mongoloide    tank, Divine Sacrifice
--   Ret   -> Rellik        ret with Aura Mastery; his plain "Ret" lines are
--     RetAM                Halion Hand of Freedom, which any paladin has
--
-- Change a paladin and you edit the note, which is what the pack's own
-- instructions tell you to do. Editing one in the Notes tab makes it yours;
-- this table is only read for a boss you have never written a note for.
--
-- Long-bracket strings, because a note is multi-line and Lua strings cannot
-- span lines.
--
-- Source: the "ret with Aura Mastery" half of the pack.
-- ============================================================

Okanvil.NotesPack = {
	["Lord Marrowgar"] = [==[
{time:00:52}Bone Storm 1 - |cfff58cbaMongoloide|r {spell:64205}
{time:00:58}Bone Storm 1 - |cfff58cbaOkanor|r {spell:64205}
{time:01:00}Bone Storm 1 - |cfff58cbaRellik|r {spell:31821}
{time:01:04}Bone Storm 1 - |cfff58cbaSolanarrage|r {spell:64205}]==],
	["Lady Deathwhisper"] = [==[
{time:00:11,SAR:70842:1}Frostbolt Volley 1 - |cfff58cbaSolanarrage|r {spell:31821}
{time:00:21,SCC:72905:1}Frostbolt Volley 2 - |cfff58cbaSolanarrage|r {spell:64205}
{time:00:21,SCC:72905:2}Frostbolt Volley 3 - |cfff58cbaOkanor|r {spell:64205}
{time:00:21,SCC:72905:3}Frostbolt Volley 4 - |cfff58cbaMongoloide|r {spell:64205}
{time:00:21,SCC:72905:4}Frostbolt Volley 5 - |cfff58cbaRellik|r {spell:31821}
{time:00:21,SCC:72905:5}Frostbolt Volley 6 - |cfff58cbaOkanor|r {spell:31821}
{time:00:21,SCC:72905:6}Frostbolt Volley 7 - |cfff58cbaSolanarrage|r {spell:31821}]==],
	-- Gunship Battle: not in this pack
	["Deathbringer Saurfang"] = [==[
{time:01:10}High Energy 1 - |cfff58cbaMongoloide|r {spell:64205}
{time:03:10}High Energy 3 - |cfff58cbaMongoloide|r {spell:64205}
Low energy Boiling Blood:
1 - |cfff58cbaOkanor|r {spell:64205}
2 - |cfff58cbaSolanarrage|r {spell:64205}
{skull}Stun1 - {cross}RetAM - {square}Holy2 - {moon}Holy1 - {triangle}Prot]==],
	["Rotface & Festergut"] = [==[
{time:00:05,SAA:69674:1}Slime Spray 1 - |cfff58cbaMongoloide|r {spell:64205}
{time:00:25,SCC:69508:1}Slime Spray 2 - |cfff58cbaOkanor|r {spell:64205}
{time:00:25,SCC:69508:2}Slime Spray 3 - |cfff58cbaSolanarrage|r {spell:64205}
{time:00:25,SCC:69508:3}Slime Spray 4
{time:00:25,SCC:69508:4}Slime Spray 5
{time:00:25,SCC:69508:5}Slime Spray 6 - |cfff58cbaMongoloide|r {spell:64205}
{time:00:05,SAA:72219:1}Pull - |cfff58cbaOkanor|r {spell:64205}
{time:00:07,SAA:72219:1}Gastric Bloat - |cfff58cbaOkanor|r {spell:31821}
{time:00:13,SAA:72219:1}Gastric Bloat - |cfff58cbaSolanarrage|r {spell:31821}
{time:00:19,SAA:72219:1}Gastric Bloat - |cfff58cbaRellik|r {spell:31821}
{time:00:25,SAA:72219:1}Gastric Bloat - |cfff58cbaMongoloide|r {spell:64205}
{time:00:30,SAA:72219:1}Gas Spore 1 - |cfff58cbaSolanarrage|r {spell:64205}
{time:02:13,SAA:72219:1}Pungent Blight 1 - |cfff58cbaOkanor|r {spell:64205}
{time:02:19,SAA:72219:1}Gastric Bloat - |cfff58cbaOkanor|r {spell:31821}
{time:02:25,SAA:72219:1}Gastric Bloat - |cfff58cbaSolanarrage|r {spell:31821}
{time:02:31,SAA:72219:1}Gastric Bloat - |cfff58cbaRellik|r {spell:31821}
{time:02:37,SAA:72219:1}Gastric Bloat - |cfff58cbaMongoloide|r {spell:64205}
{time:02:42,SAA:72219:1}Gas Spore 1 - |cfff58cbaSolanarrage|r {spell:64205}]==],
	["Professor Putricide"] = [==[
Intermission 1
{time:00:15,SCS:72840:1}Green Explosion - |cfff58cbaOkanor|r {spell:64205}
{time:00:25,SCS:72840:1}Green Explosion - |cfff58cbaSolanarrage|r {spell:64205}
Intermission 2
{time:00:15,SCS:72840:2}Green Explosion - |cfff58cbaOkanor|r {spell:64205}
{time:00:25,SCS:72840:2}Green Explosion - |cfff58cbaSolanarrage|r {spell:64205}
P3
{time:00:26,SAA:72451:1}Raid DMG - |cfff58cbaMongoloide|r {spell:64205}
|cfff58cbaSolanarrage|r BOP Taunt1]==],
	["Blood Council"] = [==[
{time:00:05,SCS:72039:1}Shock 1 - |cfff58cbaMongoloide|r {spell:64205}
{time:00:05,SCS:72039:1}Shock 1 - |cfff58cbaRellik|r {spell:31821}
{time:00:05,SCS:72039:2}Shock 2 - |cfff58cbaSolanarrage|r {spell:64205}
{time:00:05,SCS:72040:1}Flame 1 - |cfff58cbaOkanor|r {spell:64205}
{time:00:05,SCS:72039:3}Shock 3 - |cfff58cbaMongoloide|r {spell:64205}
{time:00:05,SCS:72039:3}Shock 3 - |cfff58cbaRellik|r {spell:31821}]==],
	["Queen Lana'thel"] = [==[
{time:00:05}Pull - |cfff58cbaOkanor|r {spell:64205}
{time:00:12}Pull - |cfff58cbaSolanarrage|r {spell:64205}
{time:02:16}Bloodbolt 1 - |cfff58cbaRellik|r {spell:31821}
{time:02:16}Bloodbolt 1 - |cfff58cbaSolanarrage|r {spell:64205} & {spell:31821}
{time:02:16}Bloodbolt 1 - |cfff58cbaOkanor|r {spell:64205}
{time:02:16}Bloodbolt 1 - |cfff58cbaMongoloide|r {spell:64205}
Air Phase
|cfff58cbaSolanarrage|r BOP Bite3
|cfff58cbaSolanarrage|r SAC Bite1
|cfff58cbaOkanor|r BOP Bite4
|cfff58cbaOkanor|r SAC Bite2]==],
	["Valithria Dreamwalker"] = [==[
{time:01:08}Portal 1 - |cfff58cbaOkanor|r {spell:31821}
{time:01:14}Portal 1 - |cfff58cbaSolanarrage|r {spell:31821}
{time:01:58}Portal 2 - |cfff58cbaRellik|r {spell:31821}]==],
	["Sindragosa"] = [==[
{time:00:05}Pull - |cfff58cbaSolanarrage|r {spell:64205} + {spell:31821}
{time:00:10}Pull - |cfff58cbaOkanor|r {spell:31821}
{time:00:18}Pull - |cfff58cbaRellik|r {spell:31821}
{time:00:05,SCS:70123:1}Blistering Cold 1 - |cfff58cbaMongoloide|r {spell:64205}
{time:00:05,SCS:69712:1}Frost Beacon 1 - |cfff58cbaOkanor|r {spell:64205}
{time:00:05,SCS:70123:2}Blistering Cold 2 - |cfff58cbaSolanarrage|r {spell:64205}
{time:00:05,SCS:69712:2}Frost Beacon 2 - |cfff58cbaRellik|r {spell:31821}
{time:00:05,SCS:70123:3}Blistering Cold 3 - |cfff58cbaMongoloide|r {spell:64205}
P3
{time:00:05,SCS:69712:3}Frost Beacon 3 - |cfff58cbaOkanor|r {spell:64205}
{time:00:05,SCS:69712:4}Frost Beacon 4 - |cfff58cbaSolanarrage|r {spell:31821}
{time:00:05,SCS:69712:5}Frost Beacon 5 - |cfff58cba-|r {spell:64205}
{time:00:05,SCS:70123:4}Blistering Cold 4 - |cfff58cbaSolanarrage|r {spell:64205}
{time:00:05,SCS:69712:6}Frost Beacon 6 - |cfff58cbaOkanor|r {spell:31821}
{time:00:05,SCS:69712:7}Frost Beacon 7 - |cfff58cbaRellik|r {spell:31821}
{time:00:05,SCS:69712:8}Frost Beacon 8 - |cfff58cba-|r {spell:31821}
{time:00:05,SCS:69712:9}Frost Beacon 9
{time:00:05,SCS:70123:5}Blistering Cold 5 - |cfff58cbaMongoloide|r {spell:64205}
{time:00:05,SCS:69712:10}Frost Beacon 10 - |cfff58cbaOkanor|r {spell:64205}]==],
	["The Lich King"] = [==[
{time:00:08}Infest 1 - |cfff58cbaOkanor|r {spell:64205}
{time:00:23,SCS:70541:1}Infest 2 - |cfff58cbaSolanarrage|r {spell:64205}
{time:00:23,SCS:70541:2}Infest 3 - |cfff58cbaRellik|r {spell:31821}
{time:00:23,SCS:70541:3}Infest 4 - |cfff58cbaMongoloide|r {spell:64205}
{time:00:23,SCS:70541:4}Infest 5 - |cfff58cbaOkanor|r {spell:31821}
{time:02:10,SCS:70541:1}Intermission - |cfff58cbaSolanarrage|r {spell:31821}
{time:00:13,SCS:72262:1}Infest 6 - |cfff58cbaOkanor|r {spell:64205}
{time:00:23,SCS:70541:6}Infest 7 - |cfff58cbaSolanarrage|r {spell:64205}
{time:00:23,SCS:70541:7}Infest 8 - |cfff58cbaRellik|r {spell:31821}
{time:00:23,SCS:70541:8}Infest 9 - |cfff58cbaMongoloide|r {spell:64205}
{time:00:23,SCS:70541:9}Infest 10 - |cfff58cbaOkanor|r {spell:31821}
{time:00:23,SCS:70541:10}Infest 11 - |cfff58cbaSolanarrage|r {spell:31821}
{time:00:23,SCS:70541:11}Infest 12 - |cfff58cbaOkanor|r {spell:64205}
{star}Prot - {circle}Holy2 - {diamond}Holy1
P3
{time:00:13,SCS:72262:2}Harvest Soul 1 - |cfff58cbaSolanarrage|r {spell:64205}
{time:01:45,SCC:73654:1}Harvest Soul 2 - |cfff58cbaOkanor|r {spell:64205}]==],
	["Halion"] = [==[
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
{time:00:22,SAA:74792:13}Shadow Debuff 14 - |cfff58cbaRellik|r {spell:1044}]==],
}
