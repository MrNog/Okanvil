"""Repair boss labels in already-recorded Okanvil loot.

The scanner could mislabel a drop when it couldn't vet an encounter (see the header
of Modules/ItemBoss-Data.lua for the why). The item knows better: raid gear drops
from exactly one boss. This rewrites stored drops to the item's true boss.

  python fix_loot_bosses.py <path to Okanvil.lua> [--write]

Without --write it only reports what it would change. ALWAYS CLOSE WOW BEFORE
WRITING: the client rewrites SavedVariables on logout and would clobber the edit.
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, '..', 'Okanvil', 'Modules', 'ItemBoss-Data.lua')


def load_map(path=DATA):
    """Parse [id]="Boss" pairs straight out of the Lua data file."""
    txt = open(path, encoding='utf-8').read()
    return {int(i): b for i, b in re.findall(r'\[(\d+)\]="([^"]+)"', txt)}


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    sv = sys.argv[1]
    write = '--write' in sys.argv
    if not os.path.exists(sv):
        print('not found: %s' % sv)
        return 1

    m = load_map()
    txt = open(sv, encoding='utf-8', errors='replace').read()
    fixed, seen = [], [0]

    def repl(mo):
        """Rewrite only the boss field, leaving every other field and the formatting."""
        seen[0] += 1
        body = mo.group(0)
        real = m.get(int(mo.group('id')))
        if not real:
            return body
        bm = re.search(r'\["boss"\]\s*=\s*"([^"]*)"', body)
        if not bm or bm.group(1) == real:
            return body
        fixed.append((int(mo.group('id')), bm.group(1), real))
        return body[:bm.start(1)] + real + body[bm.end(1):]

    # One stored drop = a brace group carrying both ["id"] and ["boss"].
    pat = re.compile(r'\{[^{}]*?\["id"\]\s*=\s*(?P<id>\d+)[^{}]*?\}', re.S)
    out = pat.sub(repl, txt)

    print('drops scanned: %d | relabelled: %d' % (seen[0], len(fixed)))
    for iid, old, new in fixed:
        print('  %-8d %-28s -> %s' % (iid, old, new))
    if not fixed:
        return 0
    if not write:
        print('\ndry run - pass --write to apply (CLOSE WOW FIRST)')
        return 0

    bak = sv + '.bak'
    shutil.copy2(sv, bak)
    open(sv, 'w', encoding='utf-8').write(out)
    print('\nwritten. backup: %s' % bak)
    return 0


if __name__ == '__main__':
    sys.exit(main())
