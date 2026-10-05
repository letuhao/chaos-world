"""Validate serialized diagnostic matrices; loops visit finite input snapshots.

Fixture gate: uv run python -m tools selftest run --suite map-geometry.
This checks stored geometry consistency, not runtime integration or input freshness.
"""

from __future__ import annotations

import json

if __package__:
    from .geometry import CELL_PX, find_repo_root
else:
    from geometry import CELL_PX, find_repo_root

ROOT = find_repo_root(__file__)
CELLS = ROOT / "build/mapdata/cells.json"
SUBCELL = ROOT / "build/mapdata/subcell.json"
TREES = frozenset({"flora.canopy_tree", "flora.slender_tree", "flora.ancient_tree"})


def _pair(value: object) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 2
        and all(type(number) is int and number > 0 for number in value)
    )


def _matrix(value: object, grid: list[int], boolean: bool = True) -> bool:
    if not isinstance(value, list) or len(value) != grid[1]:
        return False
    for row in value:
        if not isinstance(row, list) or len(row) != grid[0]:
            return False
        for number in row:
            if boolean:
                if type(number) is not bool:
                    return False
            elif type(number) not in (int, float) or not 0 <= number <= 1:
                return False
    return True


def _rect(value: object, footprint: list[int]) -> bool:
    return value is None or (
        isinstance(value, list)
        and len(value) == 4
        and all(type(number) is int for number in value)
        and 0 <= value[0] <= value[2] < footprint[0]
        and 0 <= value[1] <= value[3] < footprint[1]
    )


def _records(data: object, label: str, findings: list[str]) -> list[dict]:
    if not isinstance(data, dict) or not isinstance(data.get("assets"), list):
        findings.append(f"{label}: expected an object with an assets array")
        return []
    for field in ("failed", "issues"):
        if data.get(field):
            findings.append(f"{label}: unresolved {field}")
    records = data["assets"]
    if not records:
        findings.append(f"{label}: no assets were measured")
    if "asset_count" in data and data["asset_count"] != len(records):
        findings.append(f"{label}: asset_count does not match records")
    return records


def validate(cells: object, subcell: object) -> list[str]:
    """Return all structural and geometry findings; malformed input is never a clean audit."""
    findings: list[str] = []
    records = _records(cells, "cells", findings)
    by_id: dict[str, dict] = {}
    for asset in records:
        if not isinstance(asset, dict) or not isinstance(asset.get("id"), str):
            findings.append("cells: every asset needs a string id")
            continue
        label = asset["id"]
        if not label or label in by_id:
            findings.append(f"{label}: empty or duplicate cell asset id")
            continue
        by_id[label] = asset
        grid = asset.get("grid")
        if not _pair(grid):
            findings.append(f"{label}: grid must contain two positive integers")
            continue
        shape_ok = True
        for field in ("coverage", "blocks", "walk_surface"):
            if not _matrix(asset.get(field), grid, field != "coverage"):
                findings.append(f"{label}: invalid {field} matrix shape or values")
                shape_ok = False
        sem = asset.get("sem")
        if not isinstance(sem, dict):
            findings.append(f"{label}: missing semantics")
            continue
        gate = sem.get("cov_gate")
        if type(gate) not in (int, float) or not 0 <= gate <= 1:
            findings.append(f"{label}: invalid coverage gate")
            continue
        rule = sem.get("occluder_rule")
        if rule not in ("none", "ground_contact", "full_body", "core_ring"):
            findings.append(f"{label}: unknown occluder rule")
            continue
        if type(sem.get("walk_surface", False)) is not bool:
            findings.append(f"{label}: walk_surface declaration must be boolean")
        opening = sem.get("authored_open", "")
        if opening not in ("", "bottom_centre"):
            findings.append(f"{label}: unknown authored opening")
        if not shape_ok:
            continue
        blocks, coverage, walk = asset["blocks"], asset["coverage"], asset["walk_surface"]
        count = sum(sum(row) for row in blocks)
        if asset.get("block_cell_count") != count:
            findings.append(f"{label}: block_cell_count does not match mask")
        for y, row in enumerate(blocks):
            for x, blocked in enumerate(row):
                if blocked and coverage[y][x] < gate:
                    findings.append(f"{label}: phantom blocker at ({x},{y})")
                if blocked and rule == "none":
                    findings.append(f"{label}: nonblocking archetype has a blocker")
                if blocked and rule == "ground_contact" and y != grid[1] - 1:
                    findings.append(f"{label}: ground contact blocks above bottom row")
                if walk[y][x] and rule == "ground_contact" and y != grid[1] - 1:
                    findings.append(f"{label}: ground-contact walk surface above bottom row")
                if walk[y][x] and (not sem.get("walk_surface") or coverage[y][x] < 0.10):
                    findings.append(f"{label}: unsupported walk surface at ({x},{y})")
        if sem.get("walk_surface") and not any(any(row) for row in walk):
            findings.append(f"{label}: declared walk surface is empty")
        if opening == "bottom_centre":
            columns = [0] if grid[0] == 1 else [grid[0] // 2 - 1, grid[0] // 2]
            if any(blocks[-1][x] for x in columns):
                findings.append(f"{label}: authored bottom opening is blocked")

    seen: set[str] = set()
    for asset in _records(subcell, "subcell", findings):
        if not isinstance(asset, dict) or not isinstance(asset.get("id"), str):
            findings.append("subcell: every asset needs a string id")
            continue
        label = asset["id"]
        if not label or label in seen:
            findings.append(f"{label}: empty or duplicate subcell asset id")
            continue
        seen.add(label)
        footprint = asset.get("footprint")
        if not _pair(footprint):
            findings.append(f"{label}: invalid subcell footprint")
            continue
        original = by_id.get(label)
        if original is None:
            findings.append(f"{label}: subcell asset missing from cells")
        elif footprint != original.get("grid"):
            findings.append(f"{label}: cell and subcell footprints disagree")
        if original and asset.get("archetype") != original.get("archetype"):
            findings.append(f"{label}: cell and subcell archetypes disagree")
        sem = original.get("sem") if original else None
        rule = sem.get("occluder_rule") if isinstance(sem, dict) else None
        sub_grid = asset.get("sub_grid")
        if not _pair(sub_grid) or not _matrix(asset.get("sub_fill"), sub_grid, False):
            findings.append(f"{label}: invalid subcell fill matrix")
        rect = asset.get("block_rect")
        if not _rect(rect, footprint):
            findings.append(f"{label}: contact rectangle is outside its footprint")
            continue
        if rect is not None:
            # Authored footprint, not cropped sub-grid width, owns this check.
            archetype = original.get("archetype") if original else None
            if isinstance(archetype, str) and archetype in TREES and footprint[0] > 1:
                if rect[2] - rect[0] + 1 >= footprint[0]:
                    findings.append(f"{label}: tree contact spans the full footprint width")
            if rule == "none":
                findings.append(f"{label}: nonblocking archetype has contact")
            if rule == "ground_contact" and (
                rect[1] != footprint[1] - 1 or rect[3] != footprint[1] - 1
            ):
                findings.append(f"{label}: ground-contact rectangle is above bottom row")
        elif rule == "ground_contact":
            findings.append(f"{label}: ground-contact asset has no measurable contact")
        scales = asset.get("blocked_by_scale")
        if not isinstance(scales, dict) or "1.0" not in scales:
            findings.append(f"{label}: missing base-scale contact")
        elif scales["1.0"] != rect:
            findings.append(f"{label}: contact disagrees with base scale")
        if isinstance(scales, dict):
            for scale, scaled_rect in scales.items():
                if not _rect(scaled_rect, footprint):
                    findings.append(f"{label}: invalid rectangle at scale {scale}")
                if rule == "none" and scaled_rect is not None:
                    findings.append(f"{label}: nonblocking archetype has contact at scale {scale}")
        if "block_rect_px" in asset:
            expected = (
                None
                if rect is None
                else [
                    rect[0] * CELL_PX,
                    rect[1] * CELL_PX,
                    (rect[2] + 1) * CELL_PX,
                    (rect[3] + 1) * CELL_PX,
                ]
            )
            if asset["block_rect_px"] != expected:
                findings.append(f"{label}: pixel bounds disagree with cell rectangle")
    for label in sorted(set(by_id) - seen):
        findings.append(f"{label}: missing subcell asset")
    return findings


def main() -> int:
    try:
        cells = json.loads(CELLS.read_text(encoding="utf-8"))
        subcell = json.loads(SUBCELL.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"FAIL: missing or unreadable matrix input: {exc}")
        return 2
    findings = validate(cells, subcell)
    for finding in findings[:20]:
        print(f"FAIL: {finding}")
    print(f"RESULT: {'FAIL' if findings else 'PASS'} ({len(findings)} finding(s))")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
