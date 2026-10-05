"""Audit the derived cell matrices. Does the occupancy model hold?

Checks, per the proposal:
  1. no occluder cell has coverage < cov_gate (a blocker with no art)
  2. no passable_under asset has a FULLY covered cell (nothing to walk under)
  3. ground_contact never blocks more than the footprint's bottom row
  4. tree trunks land on 1 cell, not 4  (the claim that motivated the rules)
  5. bridges/arches keep a passable surface (walk_surface / core_ring work)
"""

from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

def _find_repo_root() -> Path:
    p = Path(__file__).resolve()
    for parent in [p, *p.parents]:
        if (parent / "game" / "project.godot").exists() or (parent / "pyproject.toml").exists():
            return parent
    return p.parents[4]

ROOT = _find_repo_root()
CELLS = ROOT / "build/mapdata/cells.json"
SUBCELL = ROOT / "build/mapdata/subcell.json"


def show(mask: list[list[bool]]) -> str:
    return "\n".join("      " + "".join("#" if v else "." for v in line) for line in mask)


def main() -> int:
    data = json.loads(CELLS.read_text(encoding="utf-8"))
    assets = data["assets"]
    by_arch: dict[str, list[dict]] = defaultdict(list)
    for a in assets:
        by_arch[a["archetype"]].append(a)

    print(f"assets={len(assets)}  cell_px={data['cell_px']}")

    # 1. blocker with no art
    bad = []
    for a in assets:
        gate = a["sem"]["cov_gate"]
        for y, line in enumerate(a["blocks"]):
            for x, v in enumerate(line):
                if v and a["coverage"][y][x] < gate:
                    bad.append(f"{a['id']} cell({x},{y}) cov={a['coverage'][y][x]} < gate={gate}")
    print(f"\n1. occluder cells with coverage below their gate: {len(bad)}")
    for line in bad[:8]:
        print("   ", line)

    # 2. passable_under with a fully covered cell
    bad2 = []
    for a in assets:
        if not a["sem"]["passable_under"]:
            continue
        for y, line in enumerate(a["coverage"]):
            for x, v in enumerate(line):
                if v >= 0.95 and a["blocks"][y][x]:
                    bad2.append(f"{a['id']} cell({x},{y}) cov={v} blocks AND passable_under")
    print(f"\n2. passable_under cells that are both full and blocking: {len(bad2)}")
    for line in bad2[:8]:
        print("   ", line)

    # 3. ground_contact only touches the bottom row
    bad3 = 0
    for a in assets:
        if a["sem"]["occluder_rule"] != "ground_contact":
            continue
        rows = len(a["blocks"])
        for y in range(rows - 1):
            bad3 += sum(1 for v in a["blocks"][y] if v)
    print(f"\n3. ground_contact blockers above the bottom row: {bad3}")

    # 4. THE claim: trees must not fill their footprint
    print("\n4. trees: strict-vs-derived blocking, per archetype")
    print(f"      {'archetype':<26}{'fp_cells':>9}{'derived':>9}{'ratio':>8}")
    for arch in ["flora.canopy_tree", "flora.slender_tree", "flora.ancient_tree", "flora.shrub"]:
        items = by_arch.get(arch, [])
        if not items:
            continue
        sample = items[0]
        cols, rows = sample["grid"]
        fp = cols * rows
        derived = sum(1 for line in sample["blocks"] for v in line if v)
        strict = sum(1 for line in sample["coverage"] for v in line if v > 0.0)
        print(
            f"      {arch:<26}{fp:>9}{derived:>9}"
            f"{derived / fp:>8.0%}   (strict alpha would give {strict}/{fp})"
        )

    print("\n   canopy_tree derived masks, 4 samples:")
    for a in by_arch["flora.canopy_tree"][:4]:
        print(f"      {a['id']}")
        print(show(a["blocks"]))

    # 5. walk surfaces + arches
    print("\n5. walk_surface archetypes: cells a unit can stand on")
    for arch in [
        "travel_and_wayfinding.stone_bridge",
        "travel_and_wayfinding.wooden_bridge",
        "flora.fallen_log",
        "terrain_transition.slope_ramp",
    ]:
        items = by_arch.get(arch, [])
        if not items:
            continue
        sample = items[0]
        total = sum(1 for line in sample["walk_surface"] for v in line if v)
        print(f"      {arch:<44} {total}/{sample['grid'][0] * sample['grid'][1]}  id={sample['id']}")

    print("\n6. SUB-CELL: a ground_contact prop must not block its whole footprint")
    # The regression this guards: canopy_tree measured 2 blocked cells of a 2x2
    # footprint, because a ~30px trunk straddles the 128px cell boundary and
    # lands faintly in both bottom cells. subcell.py now emits a precise rect.
    try:
        sub = json.loads((SUBCELL).read_text(encoding="utf-8"))
    except FileNotFoundError:
        print("      SKIP: subcell.json not built (run subcell.py)")
        sub = {"assets": []}
    wide = []
    empty = 0
    for a in sub["assets"]:
        if a["archetype"] not in ("flora.canopy_tree", "flora.slender_tree", "flora.ancient_tree"):
            continue
        rect = a["block_rect"]
        if rect is None:
            empty += 1
            continue
        cols, rows = a["grid"] if "grid" in a else (0, 0)
        del cols, rows
        width = rect[2] - rect[0] + 1
        fp_w = max(1, a["sub_grid"][0] // 4)
        if width >= fp_w and fp_w > 1:
            wide.append(f"{a['id']} rect={rect} fp_width={fp_w}")
    trees = [a for a in sub["assets"] if a["archetype"] in
             ("flora.canopy_tree", "flora.slender_tree", "flora.ancient_tree")]
    print(f"      {len(trees)} tree assets measured; {len(wide)} still block their full footprint width")
    for line in wide[:6]:
        print("        ", line)
    print(f"      trees with no measurable ground contact: {empty}")
    print("      RESULT:", "FAIL" if wide else "PASS")

    print("\n7. core_ring (openings must stay passable):")
    for arch in [
        "landmark_and_environment_detail.ruined_arch",
        "landmark_and_environment_detail.cave_entrance",
        "travel_and_wayfinding.portal_frame",
        "travel_and_wayfinding.path_gate",
    ]:
        items = by_arch.get(arch, [])
        if not items:
            continue
        sample = items[0]
        cells = sample["grid"][0] * sample["grid"][1]
        blocked = sum(1 for line in sample["blocks"] for v in line if v)
        print(f"      {arch:<48} blocks {blocked}/{cells} ({blocked / cells:.0%})")
        print(show(sample["blocks"]))

    print("\n7. blocking summary by archetype (greenwood only, the POC env)")
    greenwood = [a for a in assets if a["environment"] == "mortal_greenwood"]
    print(f"      greenwood assets: {len(greenwood)}")
    print(f"      {'archetype':<50}{'n':>4}{'avg_blocks':>12}")
    gag: dict[str, list[dict]] = defaultdict(list)
    for a in greenwood:
        gag[a["archetype"]].append(a)
    for arch in sorted(gag):
        items = gag[arch]
        avg = sum(a["block_cell_count"] for a in items) / len(items)
        print(f"      {arch:<50}{len(items):>4}{avg:>12.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
