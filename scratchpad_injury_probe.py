"""Scratch: does the ladder leave room for a recreation step past refinement_cap?"""
import re
import glob
import os

rows = []
for path in sorted(glob.glob("game/data/body_cultivation/realms/*.tres")):
    text = open(path, encoding="utf-8").read()

    def get(key):
        m = re.search(r"^%s = ([-\d.]+)" % key, text, re.M)
        return float(m.group(1)) if m else None

    rows.append((os.path.basename(path)[:-5], get("required_refinement"), get("refinement_cap")))

print("realm                     req   cap  tight?")
tight = 0
for name, req, cap in rows:
    if req is None or cap is None:
        continue
    eq = req >= cap
    if eq:
        tight += 1
    print("%-24s %4.0f %5.0f  %s" % (name, req, cap, "TIGHT" if eq else ""))
print("tight count =", tight)
