"""Scratch: which meridians does the body ladder actually require, by realm?

Used to place the authored injury catalog where a gate can be proven without
disturbing the R1-R9 play the existing suites walk.
"""
import re
import glob
import os

rows = []
for path in sorted(glob.glob("game/data/body_cultivation/realms/*.tres")):
    text = open(path, encoding="utf-8").read()
    m = re.search(r"^required_meridians = Array\[StringName\]\(\[([^\]]*)\]\)", text, re.M)
    ids = re.findall(r'&"([^"]+)"', m.group(1)) if m else []
    rows.append((os.path.basename(path)[:-5], ids))

for name, ids in rows:
    print("%-24s %s" % (name, ",".join(ids)))

seen = {}
for name, ids in rows:
    for i in ids:
        seen.setdefault(i, []).append(name)
print()
print("meridian -> realms requiring it")
for k in sorted(seen):
    print("%-24s %d  first=%s" % (k, len(seen[k]), seen[k][0]))
