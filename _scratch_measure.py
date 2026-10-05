"""Measure gather reachability honestly against the shipped runtime table."""

import sys
from pathlib import Path

ROOT = Path(r"D:\Works\source\chaos-world")
sys.path.insert(0, str(ROOT))

from tools.data import (  # noqa: E402
    DATA_ROOT, _gatherable_ids, _load, _authored_boss_drops, _runtime_reachable,
)

gatherable = _gatherable_ids()
print("gatherable item ids (ForageApi.NODE_YIELDS):", len(gatherable))

records, _mal, _und = _load(DATA_ROOT)
items = records["item"]
recipes = records["recipe"]
print("items:", len(items), " recipes:", len(recipes))

bosses = records["boss"]
authored = _authored_boss_drops(records)
reachable, blocked = _runtime_reachable(items, recipes, bosses, authored)
print("graph-reachable:", len(reachable), " blocked:", len(blocked))

gather_decl = [i for i, it in items.items()
               if any(s.partition(":")[0] == "gather"
                      for s in it["arrays"].get("sources", []))]
print("\nitems declaring a `gather` source:", len(gather_decl))

in_yields = [i for i in gather_decl if i in gatherable]
no_forager = [i for i in gather_decl if i not in gatherable]
print("  named in NODE_YIELDS (a forager EXISTS):", len(in_yields))
print("  NO node yields them (claim is fiction):", len(no_forager))

# Of the fiction ones, how many are reachable anyway via another kind / recipe closure?
fict_unreach = [i for i in no_forager if i not in reachable]
print("  of those, unreachable overall too:", len(fict_unreach))

cats = {}
for i in no_forager:
    c = items[i].get("category", "?")
    cats[c] = cats.get(c, 0) + 1
print("\ncategory census, gather-claiming items with no forager:")
for k, v in sorted(cats.items(), key=lambda kv: -kv[1]):
    print(f"  {k}: {v}")

# how many of the fiction ones are recipe inputs vs recipe outputs
inputs, outputs = set(), set()
for r in recipes.values():
    inputs.update(r["arrays"].get("inputs", []))
    outputs.update(r["arrays"].get("outputs", []))
nof = set(no_forager)
print("\nno-forager gather items that are recipe INPUTS:", len(nof & inputs))
print("no-forager gather items that are also recipe OUTPUTS:", len(nof & outputs))

nodes = sorted((DATA_ROOT / "holdings" / "nodes").rglob("*.tres"))
print("\nauthored ResourceNodeDef .tres files:", len(nodes))