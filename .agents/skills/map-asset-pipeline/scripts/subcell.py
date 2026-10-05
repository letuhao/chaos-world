"""Diagnostic subcell fill and cell-granular contact bounds.

Native 32px fill and bottom-row trunk columns describe the cropped art.
The shared native contact run is uniformly projected into the authored reference
footprint. That projection owns every emitted contact rectangle; subcell columns
are a separate density diagnostic. Neither representation proves runtime collision.

Outputs per asset
-----------------
  sub_fill        fill ratio per 32px sub-cell, row 0 = TOP
  sub_grid        [sub_cols, sub_rows]
  trunk_columns   sub-cell columns on the bottom sub-row that are solid
  block_rect      inclusive cell bounds, equal to blocked_by_scale["1.0"]
  block_rect_px   half-open pixel bounds of those cells, not pixel-exact collision

Fixture gate: uv run python -m tools selftest run --suite map-geometry
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

if __package__:
    from .geometry import (
        ALPHA_THRESHOLD,
        CELL_PX,
        SUB_PX,
        art_bbox,
        contact_run,
        find_repo_root,
        read_alpha,
    )
    from .semantics import FOOTPRINT, GROUND_CONTACT, SEMANTICS
else:
    from geometry import (
        ALPHA_THRESHOLD,
        CELL_PX,
        SUB_PX,
        art_bbox,
        contact_run,
        find_repo_root,
        read_alpha,
    )
    from semantics import FOOTPRINT, GROUND_CONTACT, SEMANTICS

ROOT = find_repo_root(__file__)
GAME = ROOT / "game"
INDEX = GAME / "assets/map-asset-index.jsonl"
CELLS = ROOT / "build/mapdata/cells.json"
OUT = ROOT / "build/mapdata/subcell.json"

SUB_ALPHA = ALPHA_THRESHOLD
SOLID_FILL = 0.35  # a trunk is a solid column; canopy fringe is not
# Archetypes whose art is a thin pole. A 1-cell pole spread over a 32px sub-cell
# lands ~0.2-0.3 fill, so the mass threshold would erase them entirely -- which
# is what happened: 16/16 shrubs and 18/19 signposts came back with an empty
# rect, i.e. shrubs and signposts became walkable. These keep a lower gate; the
# bottom-row contiguous run is diagnostic; it does not prove vertical continuity.
POLE_FILL = 0.12
POLE_ARCHETYPES = frozenset(
    {
        "flora.shrub",
        "flora.root_cluster",
        "flora.fallen_log",
        "travel_and_wayfinding.signpost",
        "travel_and_wayfinding.trail_marker",
        "landmark_and_environment_detail.banner",
        "stone_and_ore.standing_stone",
        "travel_and_wayfinding.stone_waypoint",
    }
)


def subcell_fill(path: Path) -> tuple[list[list[float]], int, int, int, int, bool]:
    """Fill ratio per 32px sub-cell of the CROPPED art.

    Returns (grid, cols, rows, crop_x, crop_y, is_opaque).

    The crop is essential and is not cosmetic. `map_assets._install` thumbnails
    the cutout to (canvas-32) and re-pads it with 16px, bottom-aligned, so the
    bottom 16px of a 256px canvas is transparent margin. Measuring the raw
    canvas therefore diluted the bottom sub-row roughly twofold and made a real
    trunk read at 0.07-0.22 fill instead of the ~0.6 it actually occupies.
    Measuring the art rather than the frame is what makes SOLID_FILL meaningful.
    """
    alpha = read_alpha(path)
    is_opaque = alpha.getextrema()[0] == 255
    bbox = art_bbox(alpha)
    if bbox is None:
        return ([], 0, 0, 0, 0, False)
    crop_x, crop_y = bbox[:2]
    alpha = alpha.crop(bbox)
    cw, ch = alpha.size
    # Include partial edge cells: floor division discarded narrow poles and the ground band.
    cols, rows = (cw + SUB_PX - 1) // SUB_PX, (ch + SUB_PX - 1) // SUB_PX
    grid: list[list[float]] = []
    for ry in range(rows):
        line: list[float] = []
        for rx in range(cols):
            box = (rx * SUB_PX, ry * SUB_PX, min(cw, (rx + 1) * SUB_PX), min(ch, (ry + 1) * SUB_PX))
            sub = alpha.crop(box)
            hist = sub.histogram()
            px_total = sub.width * sub.height
            line.append(round(sum(hist[SUB_ALPHA:]) / px_total, 3))
        grid.append(line)
    return grid, cols, rows, crop_x, crop_y, is_opaque


def trunk_columns(fill: list[list[float]], solid: float = SOLID_FILL) -> list[int]:
    """Longest contiguous solid-fill run on the bottom row; no vertical-continuity claim."""
    if not fill:
        return []
    bottom = fill[-1]
    cols = [cx for cx, v in enumerate(bottom) if v >= solid]
    if not cols:
        return []
    # longest contiguous run, tie-broken to the widest then leftmost
    runs: list[list[int]] = []
    current = [cols[0]]
    for cx in cols[1:]:
        if cx == current[-1] + 1:
            current.append(cx)
        else:
            runs.append(current)
            current = [cx]
    runs.append(current)
    runs.sort(key=lambda r: (-(r[-1] - r[0] + 1), r[0]))
    return runs[0]


def measure(thresholds: list[float]) -> None:
    """Sweep the solid-fill threshold against ground_contact archetypes."""
    rows = [json.loads(ln) for ln in INDEX.read_text(encoding="utf-8").splitlines() if ln.strip()]
    live = sorted([r for r in rows if r["status"] != "planned"], key=lambda r: r["id"])
    ground_contact = {
        arch for arch, sem in SEMANTICS.items() if sem["occluder_rule"] == GROUND_CONTACT
    }

    cache: dict[str, tuple] = {}
    by_arch: dict[str, list[tuple]] = defaultdict(list)
    for row in live:
        if row["archetype"] not in ground_contact:
            continue
        path = GAME / row["path"].replace("res://", "")
        if not path.exists():
            continue
        key = row["id"]
        cache[key] = subcell_fill(path)
        by_arch[row["archetype"]].append((key, cache[key]))

    print(f"ground_contact assets measured: {sum(len(v) for v in by_arch.values())}")
    header = "".join(f"{'>=' + str(t):>9}" for t in thresholds)
    print(f"\n{'archetype':<30}{'n':>4}{'fp_cells':>9}{header}")
    for arch in sorted(by_arch):
        items = by_arch[arch]
        fp_cols, fp_rows = FOOTPRINT[arch]
        fp_cells = fp_cols * fp_rows
        counts = []
        for t in thresholds:
            hits = 0
            for _key, (fill, _c, _r, _ox, _oy, _o) in items:
                if trunk_columns(fill, t):
                    hits += 1
            counts.append(hits)
        print(f"{arch:<30}{len(items):>4}{fp_cells:>9}" + "".join(f"{c:>9}" for c in counts))

    print("\nexample bottom sub-row fill (canopy_tree), CROPPED to the art:")
    for key, (fill, _c, _r, ox, oy, _o) in by_arch["flora.canopy_tree"][:6]:
        print(f"  {key}  crop=({ox},{oy}) sub={len(fill[0])}x{len(fill)}")
        print(f"      bottom sub-row: {fill[-1]}")


SCALES = (0.85, 1.0, 1.15, 1.35, 1.6)
CONTACT_RULE = "constant_subcell"
# Above this scale the true contact patch counts; at or below it the trunk is
# clamped to one sub-cell so a slightly bigger sprite does not seal more ground.
CONTACT_STEP_SCALE = 1.35


def contact_px(path: Path, band: int = 16) -> int:
    """Widest opaque horizontal run over the lowest `band` rows of the art.

    This is an alpha-based estimate; baked shadows or stray solid art can widen it.
    """
    run = contact_run(path, band)
    return run[1] - run[0] if run else 0


def rect_at_scale(
    contact: float,
    scale: float,
    fp_cols: int,
    fp_rows: int,
    min_cells: int = 1,
    *,
    center_px: float | None = None,
) -> list[int] | None:
    """Cells blocked when the contact patch is drawn at `scale`.

    A cell seals once the projected patch covers at least half its width.
    `center_px` preserves the measured anchor; omitting it uses the box center.

    Existing diagnostic policy clamps contact to one reference subcell through
    CONTACT_STEP_SCALE and floors measurable ground contact to `min_cells`.
    Zero contact stays empty. The caller records thin-contact warnings separately.
    """
    if any(type(value) is not int or value < 1 for value in (fp_cols, fp_rows)):
        raise ValueError("footprint dimensions must be positive integers")
    if type(min_cells) is not int or not 0 <= min_cells <= fp_cols:
        raise ValueError("minimum contact cells must fit the footprint")
    if not math.isfinite(scale) or scale <= 0 or not math.isfinite(contact) or contact < 0:
        raise ValueError(
            "scale must be finite and positive; contact must be finite and nonnegative"
        )
    if contact <= 0:
        return None
    # Under `contact_rule: constant_subcell` the physical trunk stays clamped to
    # ONE sub-cell (32px) while the visual canopy grows, and only past the
    # 1.35x threshold does the true contact patch start counting. Without the
    # clamp a prop with a wide base would seal a second cell at 1.15x purely
    # because its sprite is 15% bigger -- which is the cosmetic scale the whole
    # feature exists to replace.
    effective = contact
    if scale <= CONTACT_STEP_SCALE:
        effective = min(contact, SUB_PX)
    width = effective * scale
    box = fp_cols * CELL_PX
    centre = box / 2.0 if center_px is None else center_px
    if not math.isfinite(centre):
        raise ValueError("contact center must be finite")
    lo = centre - width / 2.0
    hi = centre + width / 2.0
    if hi <= 0 or lo >= box:
        return None
    blocked = []
    for c in range(fp_cols):
        cell_lo, cell_hi = c * CELL_PX, (c + 1) * CELL_PX
        overlap = max(0.0, min(hi, cell_hi) - max(lo, cell_lo))
        if overlap * 2 >= CELL_PX:
            blocked.append(c)
    if not blocked:
        if min_cells <= 0:
            return None
        # An exact cell-boundary tie selects its right-hand cell; off-center art keeps its anchor.
        mid = max(0, min(fp_cols - 1, int(centre // CELL_PX)))
        start = max(0, min(fp_cols - min_cells, mid - min_cells // 2))
        blocked = list(range(start, start + min_cells))
    bottom = fp_rows - 1
    return [min(blocked), bottom, max(blocked), bottom]


def build() -> dict:
    data = json.loads(CELLS.read_text(encoding="utf-8"))
    out: list[dict] = []
    failed: list[str] = []
    stats = {"narrowed": 0, "unchanged": 0, "empty": 0, "scaled_up": 0}
    art_defects: list[str] = []

    for a in data["assets"]:  # bounded by the snapshot
        rel = a["path"].replace("res://", "")
        path = GAME / rel
        if not path.exists():
            failed.append(f"{a['id']}: missing {rel}")
            continue
        fill, sub_cols, sub_rows, crop_x, crop_y, _is_opaque = subcell_fill(path)
        rule = a["sem"]["occluder_rule"]

        run = contact_run(path) if rule == "ground_contact" else None
        if rule == "ground_contact":
            arch = a["archetype"]
            gate = POLE_FILL if arch in POLE_ARCHETYPES else SOLID_FILL
            cols = trunk_columns(fill, gate)
            rect = None  # The scale projection below owns the emitted contact rectangle.
        else:
            # full_body / core_ring already fill their declared footprint; the
            # sub-cell grid is recorded for the collision layer but does not
            # narrow the cell mask.
            cols = []
            rect = [0, 0, max(0, a["grid"][0] - 1), max(0, a["grid"][1] - 1)]
            if not any(any(row) for row in fill):
                rect = None
            # `none` means NEVER BLOCKS -- ground, decals, effects, flowers. It
            # must yield None unconditionally, because a 1x1 prop's full
            # footprint rect is [0,0,0,0], which is truthy: every flower_cluster
            # was sealing its cell and walling the forest into pockets. The
            # semantic rule outranks the geometry, always.
            if rule == "none":
                rect = None

        # Contact keeps its measured offset through uniform canvas fit and visual scale.
        # Full-body/ring rectangles retain the prototype's coarse footprint policy.
        fp_cols, fp_rows = a["grid"]
        contact = run[1] - run[0] if run else 0
        canvas_width, canvas_height = read_alpha(path).size
        reference_scale = min(fp_cols * CELL_PX / canvas_width, fp_rows * CELL_PX / canvas_height)
        contact_reference = contact * reference_scale
        box_center = fp_cols * CELL_PX / 2
        contact_center = (
            box_center + ((run[0] + run[1]) / 2 - canvas_width / 2) * reference_scale
            if run
            else box_center
        )
        if rule in ("full_body", "core_ring"):
            by_scale = {str(s): rect for s in SCALES}
        else:
            # min_cells is 1 ONLY for a prop that has ground contact. A prop with
            # `occluder_rule: none` is a flower, a decal, litter -- it must block
            # nothing at any scale, and applying the floor to it made every
            # flower_cluster seal its cell (props 90 -> 63, walkable 67% -> 61%).
            floor_cells = 1 if rule == "ground_contact" else 0
            by_scale = {}
            for s in SCALES:
                center = box_center + (contact_center - box_center) * s
                r = rect_at_scale(
                    contact_reference, s, fp_cols, fp_rows, min_cells=floor_cells, center_px=center
                )
                by_scale[str(s)] = r
                if floor_cells and r is not None and contact_reference * s < CELL_PX / 2:
                    art_defects.append(
                        f"{a['id']}: {a['archetype']} claims {a['grid']} cells but its "
                        f"contact patch is {contact_reference:.1f} reference px "
                        f"({contact_reference * s:.0f}px at {s}x); "
                        f"floored to one cell -- regenerate the art with a thicker trunk"
                    )
        # One projection owns both fields; measured art position must not be replaced by box center.
        rect = by_scale["1.0"]
        if rect is None:
            stats["empty"] += 1
        elif (rect[2] - rect[0] + 1) < fp_cols:
            stats["narrowed"] += 1
        else:
            stats["unchanged"] += 1
        widest = (
            max((r[2] - r[0] + 1) for r in by_scale.values() if r is not None)
            if any(r is not None for r in by_scale.values())
            else 0
        )
        narrowest = (
            min((r[2] - r[0] + 1) for r in by_scale.values() if r is not None)
            if any(r is not None for r in by_scale.values())
            else 0
        )
        if widest > narrowest:
            stats["scaled_up"] += 1

        out.append(
            {
                "id": a["id"],
                "archetype": a["archetype"],
                "sub_px": SUB_PX,
                "sub_grid": [sub_cols, sub_rows],
                "crop": [crop_x, crop_y],
                "sub_fill": fill,
                "trunk_columns": cols,
                "solid_fill_used": (POLE_FILL if a["archetype"] in POLE_ARCHETYPES else SOLID_FILL)
                if rule == "ground_contact"
                else None,
                "contact_px": contact,
                "contact_reference_px": contact_reference,
                "contact_center_reference_px": contact_center,
                "footprint": [fp_cols, fp_rows],
                "scales": list(SCALES),
                "blocked_by_scale": by_scale,
                "block_rect": rect,
                "block_rect_px": (
                    None
                    if rect is None
                    else [
                        rect[0] * CELL_PX,
                        rect[1] * CELL_PX,
                        (rect[2] + 1) * CELL_PX,
                        (rect[3] + 1) * CELL_PX,
                    ]
                ),
            }
        )

    return {
        "schema": "mapdata/subcell@2",
        "sub_px": SUB_PX,
        "scales": list(SCALES),
        "contact_rule": CONTACT_RULE,
        "contact_step_scale": CONTACT_STEP_SCALE,
        "cell_px": CELL_PX,
        "solid_fill": SOLID_FILL,
        "alpha_threshold": SUB_ALPHA,
        "asset_count": len(out),
        "stats": stats,
        "art_defects": sorted(set(art_defects)),
        "failed": failed,
        "assets": out,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--measure", action="store_true")
    args = parser.parse_args(argv)
    if args.measure:
        measure([0.20, 0.30, 0.35, 0.45, 0.55, 0.65])
        return 0

    data = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, indent=1), encoding="utf-8")
    s = data["stats"]
    print(f"sub_px={SUB_PX} solid_fill={SOLID_FILL}")
    print(f"assets with a sub-cell grid: {data['asset_count']}")
    print(f"  rect NARROWED below the declared footprint: {s['narrowed']}")
    print(f"  rect unchanged (already full width):        {s['unchanged']}")
    print(f"  rect empty (no solid ground contact):       {s['empty']}")
    print(f"  assets whose blocked cells GROW with scale: {s['scaled_up']}")
    if data.get("art_defects"):
        print(
            f"\nART DEFECTS ({len(data['art_defects'])}): contact patch too thin "
            f"for the authored footprint"
        )
        for line in data["art_defects"][:6]:
            print("    ", line)
        if len(data["art_defects"]) > 6:
            print(f"     ... and {len(data['art_defects']) - 6} more (see subcell.json)")
    if data["failed"]:
        print(f"  failed: {len(data['failed'])}")
        for line in data["failed"][:10]:
            print("    ", line)
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 1 if data["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
