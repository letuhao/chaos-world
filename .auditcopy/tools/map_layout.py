"""Grid-anchored map composition with alpha-mask overlap checks."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

from .common import GAME_DIR, REPO_ROOT, ToolError, ok

ALPHA_OCCUPANCY_THRESHOLD = 128
GRID_UNIT_PX = 128


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
    blocked: dict[tuple[int, int], str] = {}
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
        footprint_cells = asset.get("footprint_cells")
        if (
            not isinstance(footprint_cells, list)
            or len(footprint_cells) != 2
            or any(type(value) is not int or value < 1 for value in footprint_cells)
        ):
            raise ToolError(f"{asset_id} must define footprint_cells as two positive integers")
        footprint_width, footprint_height = footprint_cells
        if column + footprint_width > columns or row + footprint_height > rows:
            raise ToolError(
                f"{label}.cell plus {footprint_width}x{footprint_height} footprint must fit "
                f"inside the {columns}x{rows} grid"
            )
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
        footprint_left = origin_x + column * cell_px
        footprint_top = origin_y + row * cell_px
        footprint_pixel_width = footprint_width * cell_px
        footprint_pixel_height = footprint_height * cell_px
        pixel_scale = (
            min(
                footprint_pixel_width / sprite.width,
                footprint_pixel_height / sprite.height,
            )
            * scale
        )
        if pixel_scale != 1:
            sprite = sprite.resize(
                (
                    max(1, round(sprite.width * pixel_scale)),
                    max(1, round(sprite.height * pixel_scale)),
                ),
                Image.Resampling.LANCZOS,
            )

        left = round(footprint_left + (footprint_pixel_width - sprite.width) / 2)
        top = round(
            footprint_top + footprint_pixel_height - sprite.height
            if asset["pivot"] == "bottom_center"
            else footprint_top + (footprint_pixel_height - sprite.height) / 2
        )
        visible_footprint = _footprint(sprite, left, top)
        if visible_footprint is None:
            raise ToolError(f"{label} has no visible pixels at alpha {ALPHA_OCCUPANCY_THRESHOLD}+")
        mask, mask_left, mask_top = visible_footprint
        if (
            mask_left < 0
            or mask_top < 0
            or mask_left + mask.width > width
            or mask_top + mask.height > height
        ):
            raise ToolError(f"{label} extends outside the terrain canvas")
        if (
            mask_left < origin_x
            or mask_top < origin_y
            or mask_left + mask.width > origin_x + columns * cell_px
            or mask_top + mask.height > origin_y + rows * cell_px
        ):
            raise ToolError(f"{label} visible pixels extend outside the declared grid")
        if overlap == "forbid":
            occupied_cells = _occupied_cells(mask, mask_left, mask_top, origin_x, origin_y, cell_px)
            for cell_x, cell_y in occupied_cells:
                previous_id = blocked.get((cell_x, cell_y))
                if previous_id is not None:
                    raise ToolError(
                        f"{label} ({asset_id}) alpha mask overlaps non-overlap asset "
                        f"'{previous_id}' at cell [{cell_x}, {cell_y}]"
                    )
            for cell in occupied_cells:
                blocked[cell] = asset_id
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


def _occupied_cells(
    mask: Image.Image, left: int, top: int, origin_x: int, origin_y: int, cell_px: int
) -> set[tuple[int, int]]:
    first_column = max(0, (left - origin_x) // cell_px)
    first_row = max(0, (top - origin_y) // cell_px)
    last_column = (left + mask.width - 1 - origin_x) // cell_px
    last_row = (top + mask.height - 1 - origin_y) // cell_px
    occupied: set[tuple[int, int]] = set()
    for row in range(first_row, last_row + 1):
        for column in range(first_column, last_column + 1):
            cell_left = origin_x + column * cell_px
            cell_top = origin_y + row * cell_px
            crop = mask.crop(
                (
                    max(0, cell_left - left),
                    max(0, cell_top - top),
                    min(mask.width, cell_left + cell_px - left),
                    min(mask.height, cell_top + cell_px - top),
                )
            )
            if crop.getbbox() is not None:
                occupied.add((column, row))
    return occupied


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
