"""Diagnostic cell matrices. Fixture gate: tools selftest run --suite map-geometry.

Every loop is bounded by an image dimension or a snapshot of input records.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

if __package__:
    from .geometry import ALPHA_THRESHOLD, CELL_PX, art_bbox, find_repo_root, read_alpha
    from .semantics import CORE_RING, FOOTPRINT, FULL_BODY, GROUND_CONTACT, SEMANTICS
else:
    from geometry import ALPHA_THRESHOLD, CELL_PX, art_bbox, find_repo_root, read_alpha
    from semantics import CORE_RING, FOOTPRINT, FULL_BODY, GROUND_CONTACT, SEMANTICS

ROOT = find_repo_root(__file__)
GAME = ROOT / "game"
INDEX = GAME / "assets/map-asset-index.jsonl"
OUT = ROOT / "build/mapdata/cells.json"
ALPHA_T = ALPHA_THRESHOLD


def coverage_grid(
    path: Path, fp_cols: int | None = None, fp_rows: int | None = None
) -> tuple[list[list[float]], int, int, float]:
    """Per-cell fraction of pixels with alpha >= ALPHA_T. Row 0 is the TOP row.

    Authored dimensions partition the thresholded art bbox independently along
    each axis. This is a density diagnostic, not the compositor's uniform fit.
    Without authored dimensions, partition the entire canvas in reference cells.
    Also returns frac_zero, the fraction of the whole canvas with alpha == 0.
    """
    alpha = read_alpha(path)
    w, h = alpha.size
    frac_zero = alpha.histogram()[0] / (w * h)
    authored = fp_cols is not None
    if (fp_cols is None) != (fp_rows is None):
        raise ValueError("both footprint dimensions are required")
    if fp_cols is None:
        cols, rows = (w + CELL_PX - 1) // CELL_PX, (h + CELL_PX - 1) // CELL_PX
        ox = oy = 0
        span_w, span_h = w, h
    else:
        cols, rows = fp_cols, fp_rows
        if any(type(value) is not int or value < 1 for value in (fp_cols, fp_rows)):
            raise ValueError("footprint dimensions must be positive integers")
        bbox = art_bbox(alpha)
        if bbox is None:
            return [[0.0] * cols for _ in range(rows)], cols, rows, round(frac_zero, 4)
        # Apply the bbox origin before partitioning; padding cannot shift the measured art.
        ox, oy, bx1, by1 = bbox
        span_w, span_h = bx1 - ox, by1 - oy

    grid: list[list[float]] = []
    for cy in range(rows):
        line: list[float] = []
        y0 = oy + (cy * span_h) // rows if authored else cy * CELL_PX
        y1 = oy + ((cy + 1) * span_h) // rows if authored else min(h, (cy + 1) * CELL_PX)
        for cx in range(cols):
            x0 = ox + (cx * span_w) // cols if authored else cx * CELL_PX
            x1 = ox + ((cx + 1) * span_w) // cols if authored else min(w, (cx + 1) * CELL_PX)
            # A footprint finer than the source samples its nearest source pixel.
            cell = alpha.crop((x0, y0, max(x0 + 1, x1), max(y0 + 1, y1)))
            hit = sum(cell.histogram()[ALPHA_T:])
            line.append(round(hit / (cell.width * cell.height), 3))
        grid.append(line)
    return grid, cols, rows, round(frac_zero, 4)


def occluder_mask(rule: str, cov: list[list[float]], gate: float) -> list[list[bool]]:
    """Turn a coverage grid into a blocking mask under the archetype's rule.

    `gate` is chosen by the caller from the footprint size, not fixed here: a
    1-cell prop lands far denser in its cell than a 4-cell one does.
    """
    rows = len(cov)
    cols = len(cov[0]) if rows else 0
    mask = [[False] * cols for _ in range(rows)]

    if rule == GROUND_CONTACT:
        # Only the bottom row of cells touches the ground plane. Everything
        # above it is canopy/overhang a unit walks under -- this is the rule
        # that stops a 2x2 tree from blocking 4 cells when its trunk is 1.
        bottom = rows - 1
        for cx in range(cols):
            mask[bottom][cx] = cov[bottom][cx] >= gate
        return mask

    for cy in range(rows):
        for cx in range(cols):
            value = cov[cy][cx]
            if rule == FULL_BODY:
                mask[cy][cx] = value >= gate
            elif rule == CORE_RING:
                mask[cy][cx] = value >= gate
            # NONE leaves everything False
    return mask


def walk_surface_mask(cov: list[list[float]], rule: str, enabled: bool) -> list[list[bool]]:
    """Cells a unit may STAND ON (bridge decks, log tops)."""
    mask = [[False] * len(line) for line in cov]
    if not enabled or not cov:
        return mask
    if rule == GROUND_CONTACT:
        bottom = len(cov) - 1
        mask[bottom] = [value >= 0.10 for value in cov[bottom]]
        return mask
    return [[v >= 0.10 for v in line] for line in cov]


def apply_authored_open(mask: list[list[bool]], spec: str) -> list[list[bool]]:
    """Force an authored opening. Returns a NEW mask; the input is untouched.

    `bottom_centre` opens the bottom row's central cells, which is the doorway
    of a gate, an arch or a cave mouth. Applied AFTER coverage so a dense gate
    whose art fills every cell still leaves the player a way through.
    """
    if not spec or not mask:
        return mask
    out = [row[:] for row in mask]
    rows = len(out)
    cols = len(out[0])
    bottom = rows - 1
    if spec == "bottom_centre":
        if cols == 1:
            span = [0]
        elif cols == 2:
            span = [0, 1]
        else:
            mid = cols // 2
            span = sorted({mid - 1, mid} & set(range(cols)))
        for cx in span:
            out[bottom][cx] = False
    return out


def build(env_filter: str | None) -> dict:
    rows = [json.loads(ln) for ln in INDEX.read_text(encoding="utf-8").splitlines() if ln.strip()]
    live = [r for r in rows if r["status"] != "planned"]
    if env_filter:
        live = [r for r in live if r["environment"] == env_filter]
    live.sort(key=lambda r: r["id"])

    assets: list[dict] = []
    failed: list[str] = []
    issues: list[str] = []

    for row in live:  # bounded by the snapshot above
        arch = row["archetype"]
        sem = SEMANTICS.get(arch)
        if sem is None:
            issues.append(f"{row['id']}: no semantics for archetype {arch}")
            continue
        rel = row["path"].replace("res://", "")
        path = GAME / rel
        if not path.exists():
            failed.append(f"{row['id']}: file missing {rel}")
            continue

        # Size comes from the AUTHORED footprint on the archetype, never from the
        # PNG. An archetype missing an entry falls back to the index's value and
        # is reported, so the table cannot silently under-cover.
        fp = FOOTPRINT.get(arch)
        if fp is None:
            fp = tuple(row["footprint_cells"])
            issues.append(
                f"{row['id']}: no authored footprint for {arch}, "
                f"fell back to the index's {list(fp)}"
            )
        cov, cols, rows_n, frac_zero = coverage_grid(path, fp[0], fp[1])
        if row["alpha"] == "transparent":
            alpha = read_alpha(path)
            if alpha.getextrema()[0] != 0 or art_bbox(alpha) is None:
                failed.append(f"{row['id']}: cutout needs transparent background and visible art")
                continue
        # A 1-cell footprint concentrates its art; a 4-cell one spreads it. Use
        # the low gate for the former so a solid small_rock actually blocks.
        gate = sem["cov_gate"] if cols * rows_n > 1 else sem["small_cov_gate"]
        mask = occluder_mask(sem["occluder_rule"], cov, gate)
        if sem.get("authored_open"):
            mask = apply_authored_open(mask, sem["authored_open"])
        deck = walk_surface_mask(cov, sem["occluder_rule"], sem["walk_surface"])

        occ_cells = sum(1 for line in mask for v in line if v)
        # A failed background-removal pass is detected by how much of the FILE is
        # opaque, not by per-cell coverage. Both earlier tests were wrong for
        # different reasons:
        #
        #  * `frac_zero` alone: a signpost is genuinely ~87% empty (it is a
        #    pole), so a whole-frame emptiness test deletes real art.
        #  * max cell coverage: once the art is FIT to its authored footprint,
        #    coverage is measured against the alpha bounding box, and a sparse
        #    prop -- a pole in a wide bbox, a distant tree -- legitimately covers
        #    only a few percent of its own box. That test flagged 38 healthy
        #    assets as empty.
        #
        # What actually distinguishes a failed cutout is that there is
        # essentially nothing to measure: the opaque pixels are a negligible
        # fraction of the file AND no single cell has any of them.
        max_cov = max((v for line in cov for v in line), default=0.0)
        if row["alpha"] == "transparent" and frac_zero > 0.995 and max_cov < 0.02:
            failed.append(
                f"{row['id']}: cutout has no art "
                f"({(1 - frac_zero) * 100:.2f}% opaque, max cell coverage {max_cov:.3f})"
            )
            continue

        anchor_row = rows_n - 1
        assets.append(
            {
                "id": row["id"],
                "archetype": arch,
                "environment": row["environment"],
                "world_tier": row["world_tier"],
                "type": row["type"],
                "category": row["category"],
                "name": row["name"],
                "path": row["path"],
                "canvas_px": list(read_alpha(path).size),
                "cell_px": CELL_PX,
                "grid": [cols, rows_n],
                "pivot": row["pivot"],
                "coverage": cov,
                "frac_zero": frac_zero,
                "blocks": mask,
                "walk_surface": deck,
                "block_cell_count": occ_cells,
                "anchor_cell": [cols // 2, anchor_row]
                if row["pivot"] == "bottom_center"
                else [cols // 2, rows_n // 2],
                "sem": {
                    "occluder_rule": sem["occluder_rule"],
                    "cov_gate": gate,
                    "authored_open": sem.get("authored_open", ""),
                    "passable_under": sem["passable_under"],
                    "walk_surface": sem["walk_surface"],
                    "blocks_sight": sem["blocks_sight"],
                    "blocks_projectile": sem.get("blocks_projectile", False),
                    "vision_mode": sem.get("vision_mode", "transparent"),
                    "acoustic_profile": sem.get("acoustic_profile", sem["material"]),
                    "material": sem["material"],
                    "elevation": sem["elevation"],
                    "destructible": sem["destructible"],
                    "interact": sem["interact"],
                    "cultivation": sem.get("cultivation", {}),
                    "resource": sem.get("resource"),
                    "scale_profile": sem.get("scale_profile", {}),
                },
            }
        )

    return {
        "schema": "mapdata/cells@1",
        "cell_px": CELL_PX,
        "alpha_threshold": ALPHA_T,
        "generated_for": env_filter or "all-environments",
        "asset_count": len(assets),
        "failed": failed,
        "issues": issues,
        "assets": assets,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env")
    args = parser.parse_args(argv)
    data = build(args.env)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, indent=1), encoding="utf-8")

    print(f"cell_px={data['cell_px']} alpha_threshold={data['alpha_threshold']}")
    print(f"assets derived: {data['asset_count']}  ({data['generated_for']})")
    if data["issues"]:
        print(f"\nISSUES ({len(data['issues'])}):")
        for line in data["issues"][:20]:
            print("  ", line)
    if data["failed"]:
        print(f"\nFAILED CUTOUTS / MISSING ({len(data['failed'])}):")
        for line in data["failed"][:20]:
            print("  ", line)

    blocking = [a for a in data["assets"] if a["block_cell_count"] > 0]
    under = [a for a in data["assets"] if a["sem"]["passable_under"]]
    print(f"\nassets that block at least one cell: {len(blocking)}")
    print(f"assets passable beneath: {len(under)}")
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 1 if data["issues"] or data["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
