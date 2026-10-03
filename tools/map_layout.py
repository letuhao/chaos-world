"""Grid-anchored map composition with alpha-mask overlap checks."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

from .common import GAME_DIR, REPO_ROOT, ToolError, ok

ALPHA_OCCUPANCY_THRESHOLD = 128


def compose(records: list[dict], layout: dict, terrain: dict) -> None:
    grid = layout.get("grid")
    if not isinstance(grid, dict):
        raise ToolError("grid must be a JSON object")
    placements = layout.get("placements")
    if not isinstance(placements, list):
        raise ToolError("composition placements must be a JSON array")
    show_grid = layout.get("show_grid", False)
    if not isinstance(show_grid, bool):
        raise ToolError("show_grid must be true or false")

    terrain_path = GAME_DIR / terrain["path"].removeprefix("res://")
    try:
        with Image.open(terrain_path) as opened:
            composite = opened.convert("RGBA")
    except OSError as exc:
        raise ToolError(f"cannot read terrain texture: {terrain_path}") from exc

    cell_px = _positive_int(grid.get("cell_px"), "grid.cell_px")
    columns = _positive_int(grid.get("columns"), "grid.columns")
    rows = _positive_int(grid.get("rows"), "grid.rows")
    origin = _pair(grid.get("origin_px", [0, 0]), "grid.origin_px")
    origin_x, origin_y = origin
    width, height = composite.size
    if origin_x + columns * cell_px > width or origin_y + rows * cell_px > height:
        raise ToolError("grid extent must fit inside the terrain canvas")

    if show_grid:
        _draw_grid(composite, origin_x, origin_y, cell_px, columns, rows)

    by_id = {record["id"]: record for record in records}
    blocked: list[tuple[str, Image.Image, int, int]] = []
    for index, placement in enumerate(placements, 1):
        label = f"placement {index}"
        if not isinstance(placement, dict):
            raise ToolError(f"{label} must be a JSON object")
        asset_id = placement.get("asset_id")
        asset = by_id.get(asset_id) if isinstance(asset_id, str) else None
        if (
            asset is None
            or asset["environment"] != terrain["environment"]
            or asset["type"] == "terrain_texture"
            or asset["alpha"] != "transparent"
            or asset["status"] not in {"generated", "approved"}
        ):
            raise ToolError(
                f"{label} must name a transparent generated asset in the terrain's environment"
            )

        column, row = _pair(placement.get("cell"), f"{label}.cell")
        if column >= columns or row >= rows:
            raise ToolError(f"{label}.cell must be inside the {columns}x{rows} grid")
        scale = placement.get("scale", 1.0)
        if isinstance(scale, bool) or not isinstance(scale, (int, float)) or not 0 < scale <= 4:
            raise ToolError(f"{label}.scale must be in (0, 4]")
        overlap = placement.get("overlap", "forbid" if asset["collision"] == "solid" else "allow")
        if overlap not in ("allow", "forbid"):
            raise ToolError(f"{label}.overlap must be 'allow' or 'forbid'")

        asset_path = GAME_DIR / asset["path"].removeprefix("res://")
        try:
            with Image.open(asset_path) as opened:
                sprite = opened.convert("RGBA")
        except OSError as exc:
            raise ToolError(f"cannot read composition sprite: {asset_path}") from exc
        if scale != 1:
            sprite = sprite.resize(
                (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale))),
                Image.Resampling.LANCZOS,
            )

        anchor_x = origin_x + column * cell_px + cell_px / 2
        anchor_y = origin_y + row * cell_px + cell_px / 2
        left = round(anchor_x - sprite.width / 2)
        top = round(
            anchor_y - sprite.height
            if asset["pivot"] == "bottom_center"
            else anchor_y - sprite.height / 2
        )
        footprint = _footprint(sprite, left, top)
        if footprint is None:
            raise ToolError(f"{label} has no visible pixels at alpha {ALPHA_OCCUPANCY_THRESHOLD}+")
        mask, mask_left, mask_top = footprint
        if (
            mask_left < 0
            or mask_top < 0
            or mask_left + mask.width > width
            or mask_top + mask.height > height
        ):
            raise ToolError(f"{label} extends outside the terrain canvas")
        if overlap == "forbid":
            for previous_id, previous_mask, previous_left, previous_top in blocked:
                if _masks_intersect(
                    mask, mask_left, mask_top, previous_mask, previous_left, previous_top
                ):
                    raise ToolError(
                        f"{label} ({asset_id}) overlaps non-overlap asset '{previous_id}'"
                    )
            blocked.append((asset_id, mask, mask_left, mask_top))
        composite.alpha_composite(sprite, (left, top))

    _save(composite, layout["id"], len(placements), cell_px, columns, rows)


def _positive_int(value, name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise ToolError(f"{name} must be a positive integer")
    return value


def _pair(value, name: str) -> tuple[int, int]:
    if (
        not isinstance(value, list)
        or len(value) != 2
        or any(isinstance(item, bool) or not isinstance(item, int) or item < 0 for item in value)
    ):
        raise ToolError(f"{name} must be a pair of non-negative integers")
    return value[0], value[1]


def _footprint(sprite: Image.Image, left: int, top: int) -> tuple[Image.Image, int, int] | None:
    mask = sprite.getchannel("A").point(
        lambda alpha: 255 if alpha >= ALPHA_OCCUPANCY_THRESHOLD else 0
    )
    bounds = mask.getbbox()
    if bounds is None:
        return None
    return mask.crop(bounds), left + bounds[0], top + bounds[1]


def _masks_intersect(
    first: Image.Image,
    first_x: int,
    first_y: int,
    second: Image.Image,
    second_x: int,
    second_y: int,
) -> bool:
    left, top = max(first_x, second_x), max(first_y, second_y)
    right = min(first_x + first.width, second_x + second.width)
    bottom = min(first_y + first.height, second_y + second.height)
    if left >= right or top >= bottom:
        return False
    first_crop = first.crop((left - first_x, top - first_y, right - first_x, bottom - first_y))
    second_crop = second.crop(
        (left - second_x, top - second_y, right - second_x, bottom - second_y)
    )
    return ImageChops.multiply(first_crop, second_crop).getbbox() is not None


def _draw_grid(
    image: Image.Image, origin_x: int, origin_y: int, cell_px: int, columns: int, rows: int
) -> None:
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    right, bottom = origin_x + columns * cell_px, origin_y + rows * cell_px
    for column in range(columns + 1):
        x = origin_x + column * cell_px
        draw.line((x, origin_y, x, bottom), fill=(125, 205, 218, 105), width=1)
    for row in range(rows + 1):
        y = origin_y + row * cell_px
        draw.line((origin_x, y, right, y), fill=(125, 205, 218, 105), width=1)
    image.alpha_composite(overlay)


def _save(
    image: Image.Image, layout_id: str, count: int, cell_px: int, columns: int, rows: int
) -> None:
    output_path = REPO_ROOT / "build" / "map-compositions" / f"{layout_id}.png"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            suffix=".png", dir=output_path.parent, delete=False
        ) as temporary:
            temporary_path = Path(temporary.name)
        image.save(temporary_path, format="PNG", optimize=True)
        os.replace(temporary_path, output_path)
        temporary_path = None
    finally:
        if temporary_path and temporary_path.exists():
            temporary_path.unlink()
    ok(
        f"wrote {output_path.relative_to(REPO_ROOT).as_posix()} with {count} sprites "
        f"on a {columns}x{rows} grid ({cell_px}px cells)"
    )
