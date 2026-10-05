"""Sub-cell occupancy: the precise footprint of a prop, at 32px.

Gap this closes
---------------
A 128px cell cannot express a tree trunk. `_install` centres the art in its
canvas, so a ~30px trunk straddles the cell boundary and lands faintly in BOTH
bottom cells -- which is why `canopy_tree` measured 2 blocked cells out of a 4
cell footprint. Widening the cell does not fix it either: the trunk's width is a
property of the art, not of the grid.

Method
------
Cell-level coverage is the wrong measurement for a thin vertical object. What
distinguishes a trunk from the canopy edge is FILL, not presence: a trunk
sub-cell is a solid column (mostly opaque), while a canopy sub-cell at its
lower corner is sparse foliage that happens to touch the cell. So this module
computes per-SUBCELL fill ratio at 32px -- which is also the size of the
existing Godot TileSet region (`texture_region_size = Vector2i(32, 32)`), so
one grid serves both -- and reads the ground-contact column run off it.

A sub-cell is opaque at >= SUB_ALPHA (the same 128 threshold the rest of the
pipeline uses), and a sub-cell is SOLID at >= SOLID_FILL of that.

Outputs per asset
-----------------
  sub_fill        fill ratio per 32px sub-cell, row 0 = TOP
  sub_grid        [sub_cols, sub_rows]
  trunk_columns   sub-cell columns on the bottom sub-row that are solid
  block_rect      [x0, y0, x1, y1] in CELL units: the precise blocked rect
                  the chunk grid uses, which is narrower than footprint_cells
                  whenever the art is narrower than its declared footprint
  block_rect_px   the same rect in pixels, for a sub-cell collision layer

Run: uv run python build/mapdata/subcell.py            # summary + measure
     uv run python build/mapdata/subcell.py --measure  # threshold sweep
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image

def _find_repo_root() -> Path:
    p = Path(__file__).resolve()
    for parent in [p, *p.parents]:
        if (parent / "game" / "project.godot").exists() or (parent / "pyproject.toml").exists():
            return parent
    return p.parents[4]

ROOT = _find_repo_root()
GAME = ROOT / "game"
INDEX = GAME / "assets/map-asset-index.jsonl"
CELLS = ROOT / "build/mapdata/cells.json"
OUT = ROOT / "build/mapdata/subcell.json"

SUB_PX = 32          # matches the Godot TileSet texture_region_size
CELL_PX = 128
SUB_ALPHA = 128
SOLID_FILL = 0.35   # a trunk is a solid column; canopy fringe is not
# Archetypes whose art is a thin pole. A 1-cell pole spread over a 32px sub-cell
# lands ~0.2-0.3 fill, so the mass threshold would erase them entirely -- which
# is what happened: 16/16 shrubs and 18/19 signposts came back with an empty
# rect, i.e. shrubs and signposts became walkable. These keep a lower gate; the
# distinction from canopy fringe is the SHAPE of the run (a narrow continuous
# column reaching the frame's bottom), which trunk_columns already requires.
POLE_FILL = 0.12
POLE_ARCHETYPES = frozenset({
    "flora.shrub",
    "flora.root_cluster",
    "flora.fallen_log",
    "travel_and_wayfinding.signpost",
    "travel_and_wayfinding.trail_marker",
    "landmark_and_environment_detail.banner",
    "stone_and_ore.standing_stone",
    "travel_and_wayfinding.stone_waypoint",
})


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
    with Image.open(path) as img:
        img = img.convert("RGBA")
        w, h = img.size
        alpha = img.getchannel("A")
        ext = alpha.getextrema()
        is_opaque = ext[0] == 255
        if is_opaque:
            cols, rows = w // SUB_PX, h // SUB_PX
            return ([[1.0] * cols for _ in range(rows)], cols, rows, 0, 0, True)

        bbox = alpha.getbbox()
        if bbox is None:
            return ([], 0, 0, 0, 0, False)
        crop_x, crop_y = bbox[0], bbox[1]
        alpha = alpha.crop(bbox)
        cw, ch = alpha.size
        cols, rows = cw // SUB_PX, ch // SUB_PX
        grid: list[list[float]] = []
        for ry in range(rows):
            line: list[float] = []
            for rx in range(cols):
                box = (rx * SUB_PX, ry * SUB_PX, (rx + 1) * SUB_PX, (ry + 1) * SUB_PX)
                sub = alpha.crop(box)
                hist = sub.histogram()
                px_total = sub.width * sub.height
                solid = px_total - hist[0] - sum(hist[1:SUB_ALPHA])
                line.append(round(solid / px_total, 3))
            grid.append(line)
        return grid, cols, rows, crop_x, crop_y, False


def trunk_columns(fill: list[list[float]], solid: float = SOLID_FILL) -> list[int]:
    """Sub-cell columns on the bottom row that carry a solid vertical body.

    The bottom sub-row is the one touching the ground plane. Only its SOLID
    sub-cells count: a signpost's pole is solid, its crossbar's tips are not.

    The run is then CLIPPED to the columns that form the contiguous body, so a
    detached speck of foliage on the same row cannot drag the rect wider than
    the trunk it belongs to.
    """
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


def block_rect_from_columns(
    cols: list[int],
    sub_cols: int,
    sub_rows: int,
    crop_x: int,
    crop_y: int,
    canvas_cells: list[int],
) -> list[int]:
    """Map solid bottom-row sub-columns to a precise rect in CELL units.

    A cell counts as blocked when the solid run covers at least half of its
    width: a trunk clipping a cell by 20% should not seal a walkable cell, and
    one filling 60% of it should. `crop_x/crop_y` put the cropped sub-cell
    indices back into canvas space before dividing down to cells.
    """
    if not cols:
        # None, not [0,0,0,0]. A 1x1 prop's real rect IS [0,0,0,0] (it blocks
        # its only cell), so the zero rect was indistinguishable from "no ground
        # contact" -- which silently reported every shrub and signpost as having
        # no blocker and made them walkable.
        return None
    per_cell = CELL_PX // SUB_PX
    cell_cols = max(1, canvas_cells[0])
    solid_px = [(crop_x + cx * SUB_PX, crop_x + (cx + 1) * SUB_PX) for cx in cols]

    blocked: list[int] = []
    for c in range(cell_cols):
        lo, hi = c * CELL_PX, (c + 1) * CELL_PX
        # overlap of the solid run with this cell, in PIXELS
        covered = sum(max(0, min(hi, b) - max(lo, a)) for a, b in solid_px)
        if covered * 2 >= CELL_PX:
            blocked.append(c)
    if not blocked:
        # The solid run is narrower than half a cell -- a pole, or a prop whose
        # art is genuinely small inside its canvas. Anchor to the cell holding
        # the run's centre instead of giving up. An earlier version had no
        # fallback and every shrub and signpost came back EMPTY, i.e. silently
        # walkable, while its bottom sub-row measured 0.55-1.0 fill: the run
        # simply never reached half a cell's width, which is the normal case
        # for a single 32px sub-cell inside a 128px cell.
        mid = (solid_px[len(solid_px) // 2][0] + solid_px[len(solid_px) // 2][1]) // 2
        blocked = [min(cell_cols - 1, mid // CELL_PX)]

    # The rect's vertical extent is the BOTTOM CELL ROW of the declared
    # footprint. A ground_contact prop is bottom-anchored, so its trunk is
    # always in the last row -- deriving the row from the crop arithmetic gave
    # row 0 for a 2-row tree, which is the canopy.
    bottom_row = max(0, canvas_cells[1] - 1)
    return [min(blocked), bottom_row, max(blocked), bottom_row]


def measure(thresholds: list[float]) -> None:
    """Sweep the solid-fill threshold against ground_contact archetypes."""
    rows = [json.loads(ln) for ln in INDEX.read_text(encoding="utf-8").splitlines() if ln.strip()]
    live = sorted([r for r in rows if r["status"] != "planned"], key=lambda r: r["id"])
    ground_contact = {
        "flora.canopy_tree",
        "flora.slender_tree",
        "flora.ancient_tree",
        "flora.shrub",
        "flora.root_cluster",
        "flora.fallen_log",
        "stone_and_ore.standing_stone",
        "travel_and_wayfinding.signpost",
        "travel_and_wayfinding.trail_marker",
        "travel_and_wayfinding.stone_waypoint",
        "landmark_and_environment_detail.banner",
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
        grid_cols = items[0][1][1]
        grid_rows = items[0][1][2]
        fp_cells = (grid_cols // 4) * (grid_rows // 4)
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

    This is the prop's contact patch -- the part of it that touches the ground --
    and it is the only honest basis for how much ground a scaled prop blocks.
    """
    with Image.open(path) as img:
        a = img.convert("RGBA").getchannel("A")
    bbox = a.getbbox()
    if bbox is None:
        return 0
    a = a.crop(bbox)
    w, h = a.size
    px = a.load()
    best = 0
    for y in range(max(0, h - band), h):
        run = 0
        for x in range(w):
            if px[x, y] >= SUB_ALPHA:
                run += 1
                if run > best:
                    best = run
            else:
                run = 0
    return best


def rect_at_scale(
    contact: int, scale: float, fp_cols: int, fp_rows: int, min_cells: int = 1
) -> list[int] | None:
    """Cells blocked when the contact patch is drawn at `scale`.

    The patch is centred on the prop's box, and a cell seals once the patch
    covers at least half its width -- so scale is DYNAMIC, not cosmetic: a
    canopy tree can hold one cell at 1.0 and two at 1.6, and a forest gets a
    specimen that genuinely occupies more ground than its neighbours.

    `min_cells` is the floor, and it is the important part. The generated art
    has inverted contact widths -- the landmark ancient tree's trunk is 11px
    while a shrub's is 64px -- so a purely pixel-derived rect makes a tree
    WALKABLE THROUGH at 1.0 and lets a shrub block more ground than a landmark.
    That is not a measurement, it is a broken tree.

    So the authored footprint is the floor for a prop that has ground contact:
    it blocks at least one cell, and scale raises it from there. A prop with
    `occluder_rule: none` passes min_cells=0 and stays walkable, because a
    flower you can walk through is correct and a tree you can walk through is
    not. When the pixels cannot justify the authored size, that is recorded as
    an ART DEFECT for the generator to fix, not silently honoured.
    """
    if min_cells <= 0 and contact <= 0:
        return None
    # VISUAL SCALE vs CONTACT SCALE (map-asset-pipeline skill, section E).
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
    centre = box / 2.0
    lo = centre - width / 2.0
    hi = centre + width / 2.0
    blocked = []
    for c in range(fp_cols):
        cell_lo, cell_hi = c * CELL_PX, (c + 1) * CELL_PX
        overlap = max(0.0, min(hi, cell_hi) - max(lo, cell_lo))
        if overlap * 2 >= CELL_PX:
            blocked.append(c)
    if not blocked:
        if min_cells <= 0:
            return None
        # Anchor the floor at the centre of the footprint: the trunk is there.
        mid = fp_cols // 2
        blocked = [mid] if fp_cols == 1 else [mid - (min_cells // 2), mid + (min_cells // 2)]
        blocked = [c for c in blocked if 0 <= c < fp_cols]
        if not blocked:
            blocked = [fp_cols // 2]
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
        fill, sub_cols, sub_rows, crop_x, crop_y, is_opaque = subcell_fill(path)
        rule = a["sem"]["occluder_rule"]

        if rule == "ground_contact":
            arch = a["archetype"]
            gate = POLE_FILL if arch in POLE_ARCHETYPES else SOLID_FILL
            cols = trunk_columns(fill, gate)
            rect = block_rect_from_columns(cols, sub_cols, sub_rows, crop_x, crop_y, a["grid"])
        else:
            # full_body / core_ring already fill their declared footprint; the
            # sub-cell grid is recorded for the collision layer but does not
            # narrow the cell mask.
            cols = []
            rect = [0, 0, max(0, a["grid"][0] - 1), max(0, a["grid"][1] - 1)]
            if is_opaque or not any(any(row) for row in fill):
                rect = None
            # `none` means NEVER BLOCKS -- ground, decals, effects, flowers. It
            # must yield None unconditionally, because a 1x1 prop's full
            # footprint rect is [0,0,0,0], which is truthy: every flower_cluster
            # was sealing its cell and walling the forest into pockets. The
            # semantic rule outranks the geometry, always.
            if rule == "none":
                rect = None

        if rect is None:
            stats["empty"] += 1
        elif (rect[2] - rect[0] + 1) < a["grid"][0]:
            stats["narrowed"] += 1
        else:
            stats["unchanged"] += 1

        # Dynamic scale. For a contact-measured prop the blocked rect at each
        # scale tier is precomputed, because the patch is centred and a wider
        # patch simply seals more cells -- the generator then picks a tier and
        # the walkable grid follows the sprite it actually drew. full_body and
        # core_ring props block their whole declared footprint at every scale,
        # since scaling them does not change what part of them is solid.
        fp_cols, fp_rows = a["grid"]
        contact = contact_px(path) if rule == "ground_contact" else 0
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
                r = rect_at_scale(contact, s, fp_cols, fp_rows, min_cells=floor_cells)
                by_scale[str(s)] = r
                if floor_cells and r is not None and contact * s < CELL_PX / 2:
                    art_defects.append(
                        f"{a['id']}: {a['archetype']} claims {a['grid']} cells but its "
                        f"contact patch is only {contact}px ({contact * s:.0f}px at {s}x); "
                        f"floored to one cell -- regenerate the art with a thicker trunk"
                    )
        widest = max(
            (r[2] - r[0] + 1) for r in by_scale.values() if r is not None
        ) if any(r is not None for r in by_scale.values()) else 0
        narrowest = min(
            (r[2] - r[0] + 1) for r in by_scale.values() if r is not None
        ) if any(r is not None for r in by_scale.values()) else 0
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
                "footprint": [fp_cols, fp_rows],
                "scales": list(SCALES),
                "blocked_by_scale": by_scale,
                "block_rect": rect,
                "block_rect_px": (
                    None
                    if rect is None
                    else [rect[0] * CELL_PX, rect[1] * CELL_PX,
                          (rect[2] + 1) * CELL_PX, (rect[3] + 1) * CELL_PX]
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
    if "--measure" in argv:
        measure([0.20, 0.30, 0.35, 0.45, 0.55, 0.65])
        return 0

    data = build()
    OUT.write_text(json.dumps(data, indent=1), encoding="utf-8")
    s = data["stats"]
    print(f"sub_px={SUB_PX} solid_fill={SOLID_FILL}")
    print(f"assets with a sub-cell grid: {data['asset_count']}")
    print(f"  rect NARROWED below the declared footprint: {s['narrowed']}")
    print(f"  rect unchanged (already full width):        {s['unchanged']}")
    print(f"  rect empty (no solid ground contact):       {s['empty']}")
    print(f"  assets whose blocked cells GROW with scale: {s['scaled_up']}")
    if data.get("art_defects"):
        print(f"\nART DEFECTS ({len(data['art_defects'])}): contact patch too thin "
              f"for the authored footprint")
        for line in data["art_defects"][:6]:
            print("    ", line)
        if len(data["art_defects"]) > 6:
            print(f"     ... and {len(data['art_defects']) - 6} more (see subcell.json)")
    if data["failed"]:
        print(f"  failed: {len(data['failed'])}")
        for line in data["failed"][:10]:
            print("    ", line)
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
