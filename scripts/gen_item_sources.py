"""Build Okanvil's Modules/ItemSource-Data.lua: where each item on the BiS lists comes from
when it is not a raid drop (a dungeon boss, an emblem vendor, a reputation, PvP, crafting).
Raid drops already have their Boss / Instance rows (RaidLoot-Data, ItemBoss-Data).
Read from AtlasLoot's WotLK, Crafting and World Events tables.
usage: python -I scripts/gen_item_sources.py <AddOns dir> <Okanvil Modules dir>"""
import os, re, sys

addons, okv_dir = sys.argv[1:3]

# the BiS ids that still need a source: no raid drop knows them
bis = open(os.path.join(okv_dir, "Upgrades-Bis-Data.lua"), encoding="utf-8").read()
wanted = set()
for m in re.finditer(r'e = \{[^}]*\},?([^}]*)\}', bis):
    wanted |= {int(x) for x in re.findall(r'\d+', m.group(1))}
h2a = {int(h): int(a) for h, a in re.findall(r'\[(\d+)\] = (\d+),', bis.split("BIS_HORDE_TO_ALI")[1])}
wanted |= set(h2a)          # the Horde copies of faction items too
raid = {int(x) for x in re.findall(r'id = (\d+)', open(os.path.join(okv_dir, "RaidLoot-Data.lua"), encoding="utf-8").read())}
raid |= {int(x) for x in re.findall(r'\[(\d+)\]=', open(os.path.join(okv_dir, "ItemBoss-Data.lua"), encoding="utf-8").read())}
wanted -= raid

# table key -> its name (AtlasLoot_TableNames, English)
names_src = open(os.path.join(addons, "AtlasLoot", "TableRegister", "loottables.en.lua"), encoding="utf-8-sig").read()
table_name = {}
for key, expr in re.findall(r'AtlasLoot_TableNames\["([^"]+)"\] = \{ (.*?), "[^"]*" \};', names_src):
    parts = re.findall(r'"([^"]*)"', expr)
    table_name[key] = " ".join(p for p in parts if p.strip())

CURRENCY = {
    "eofheroism": "Emblem of Heroism", "eofvalor": "Emblem of Valor", "eofconquest": "Emblem of Conquest",
    "eoftriumph": "Emblem of Triumph", "eoffrost": "Emblem of Frost", "arena": "Arena Points",
    "wintergraspmark": "Wintergrasp Mark of Honor", "wintergrasp": "Stone Keeper's Shard", "honor": "Honor",
}
HEADER = {"#j1#": "Normal", "#j3#": "Heroic", "#r1#": "Neutral", "#r2#": "Friendly",
          "#r3#": "Honored", "#r4#": "Revered", "#r5#": "Exalted"}
# lists that never say where an item comes from
SKIP_SECTIONS = {"Heirloom Items", "Tabards", "Mounts", "Vanity Pets", "Upper Deck Card Game Items",
                 "Sets & Collections", "Keys"}
# collections that only list an item again: used only when nothing else knows it
FALLBACK_SECTIONS = {"Armor Sets", "Wrath Of The Lich King Sets", "Naxx Sets (T7)/Ulduar Sets (T8)",
                     "Tier 9 Sets (T9)", "Tier 10 Sets (T10)", "Level 80 Epic Non-Sets", "Legendaries"}
TIER_SET = {"Naxx Sets (T7)/Ulduar Sets (T8)": "Tier 7 / Tier 8 set", "Tier 9 Sets (T9)": "Tier 9 set",
            "Tier 10 Sets (T10)": "Tier 10 set"}

def cost_text(raw):
    """'25 #eofheroism#' -> '25 Emblem of Heroism'; anything unknown is left out."""
    out = []
    for n, tok in re.findall(r'(\d+)\s*#([a-z]+)#', raw or ""):
        if tok in CURRENCY:
            out.append(f"{n} {CURRENCY[tok]}")
    return ", ".join(out)

def header_text(text):
    for tok, word in HEADER.items():
        if tok in text:
            return word
    return ""

entry_re = re.compile(r'\{\s*\d+\s*,\s*("?s?\d+"?)\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*([^}]*)\}')

sources = {}
fallback = {}
def read(path, crafted=False):
    section, key, header = "", None, ""
    for line in open(path, encoding="utf-8-sig"):
        m = re.match(r'^\s*-{3}\s+(.+?)\s+-{3}\s*$', line)
        if m:
            section = m.group(1).strip()
            continue
        m = re.match(r'^\s*AtlasLoot_Data\["([^"]+)"\]', line)
        if m:
            key, header = m.group(1), ""
            continue
        if not key:
            continue
        m = entry_re.search(line)
        if not m:
            continue
        first, second, third, rest = m.groups()
        first = first.strip('"')
        if crafted:
            # { slot, "s<spell>", "<item>", "=qN=Name", desc }
            if not first.startswith("s") or not second.isdigit():
                continue
            item = int(second)
        else:
            item = int(first)
            if item == 0:
                header = header_text(third)
                continue
        if item not in wanted or item in sources or section in SKIP_SECTIONS:
            continue
        quoted = re.findall(r'"([^"]*)"', rest)
        cost = cost_text(quoted[1] if len(quoted) > 1 else "")
        tname = table_name.get(key, "")
        emblem = re.match(r'^(Emblem of \w+) Items$', section)
        if crafted:
            where = "Crafted: " + (section or tname)
        elif emblem:
            where = emblem.group(1) + " vendor"
        elif section in TIER_SET:
            where = TIER_SET[section]
        elif section in FALLBACK_SECTIONS:
            where = section + (" - " + tname if tname else "")
        else:
            where = section or tname
            if header in ("Normal", "Heroic"):
                where += " (" + header + ")"
            if tname and tname != section:
                where += " - " + tname
            if header and header not in ("Normal", "Heroic"):
                where += " - " + header
        if section in FALLBACK_SECTIONS:
            fallback.setdefault(item, (where, cost))
        else:
            sources[item] = (where, cost)

read(os.path.join(addons, "AtlasLoot_WrathoftheLichKing", "wrathofthelichking.lua"))
# pre-raid lists still name Burning Crusade gear
bc = os.path.join(addons, "AtlasLoot_BurningCrusade")
for f in sorted(os.listdir(bc)) if os.path.isdir(bc) else []:
    if f.endswith(".lua") and f != "localization.lua":
        read(os.path.join(bc, f))
events = os.path.join(addons, "AtlasLoot_WorldEvents")
for f in sorted(os.listdir(events)) if os.path.isdir(events) else []:
    if f.endswith(".lua") and f != "localization.lua":
        read(os.path.join(events, f))
read(os.path.join(addons, "AtlasLoot_Crafting", "crafting.lua"), crafted=True)
for item, v in fallback.items():
    sources.setdefault(item, v)

def lua(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

out = ["-- Okanvil -- where a non-raid item on the BiS lists comes from, generated by",
       "-- scripts/gen_item_sources.py; regenerate it, do not edit by hand.",
       "-- OkanvilItemSource[itemId] = { where, cost } (cost may be empty)",
       "OkanvilItemSource = {"]
for item in sorted(sources):
    where, cost = sources[item]
    out.append(f"\t[{item}] = {{ {lua(where)}, {lua(cost)} }},")
out.append("}")
open(os.path.join(okv_dir, "ItemSource-Data.lua"), "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
print(len(wanted), "BiS items without a raid source,", len(sources), "found a source,",
      len(wanted - set(sources)), "still unknown")
