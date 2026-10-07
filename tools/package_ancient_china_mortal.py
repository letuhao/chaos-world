"""Packaging and normalization pipeline for Ancient China Mortal World asset pack.

Normalizes raw generation images, archives originals, generates individual asset JSON data,
computes diagnostic geometry matrix_data, updates pack manifest, and imports assets into Godot.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import shutil
import sys
import time
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_DIR = REPO_ROOT / "game" / "assets" / "packs" / "ancient_china_mortal"
PACK_PATH = PACK_DIR / "ancient_china_mortal_pack.json"
ORIGINAL_DIR = PACK_DIR / "original"
RUNTIME_DIR = PACK_DIR / "runtime"
DATA_DIR = PACK_DIR / "data"
GAME_DIR = REPO_ROOT / "game"

sys.path.insert(0, str(REPO_ROOT / ".agents" / "skills" / "map-asset-pipeline" / "scripts"))
import geometry
import derive
import subcell

from tools.godot import run_godot


def normalize_image(
    source_path: Path,
    dest_path: Path,
    target_size: tuple[int, int],
    alpha_mode: str,
    pivot: str = "bottom_center",
    margin: int = 16,
) -> None:
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    target_w, target_h = target_size

    with Image.open(source_path) as opened:
        img = opened.copy()

    if alpha_mode == "transparent":
        rgba = img.convert("RGBA")
        alpha = rgba.split()[-1]
        bbox = alpha.getbbox()
        cropped = rgba.crop(bbox) if bbox else rgba

        cw, ch = cropped.size
        max_w = max(1, target_w - margin * 2)
        max_h = max(1, target_h - margin * 2)
        scale = min(max_w / cw, max_h / ch)
        new_w = max(1, int(cw * scale))
        new_h = max(1, int(ch * scale))
        resized = cropped.resize((new_w, new_h), Image.Resampling.LANCZOS)

        canvas = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
        pos_x = (target_w - new_w) // 2
        pos_y = target_h - new_h - margin if pivot == "bottom_center" else (target_h - new_h) // 2
        canvas.paste(resized, (pos_x, pos_y), resized)
        canvas.save(dest_path, format="PNG", optimize=True)
    else:
        resized = img.convert("RGB").resize((target_w, target_h), Image.Resampling.LANCZOS)
        resized.save(dest_path, format="PNG", optimize=True)


def compute_matrix_data(
    runtime_path: Path,
    footprint_cells: list[int],
    alpha_mode: str,
    collision_type: str,
    pivot: str,
    interactive_verb: str | None = None,
) -> dict:
    fp_cols, fp_rows = footprint_cells
    cell_px = geometry.CELL_PX

    if alpha_mode == "opaque":
        cov = [[1.0] * fp_cols for _ in range(fp_rows)]
        frac_zero = 0.0
        is_walk_surface = collision_type == "walk_surface"
        blocks = [[False] * fp_cols for _ in range(fp_rows)]
        walk_surface = [[is_walk_surface] * fp_cols for _ in range(fp_rows)]
        block_cell_count = 0
        anchor_cell = [fp_cols // 2, fp_rows // 2]
        sub_grid = [fp_cols * 4, fp_rows * 4]
        sub_fill = [[1.0] * (fp_cols * 4) for _ in range(fp_rows * 4)]
        return {
            "coverage": cov,
            "frac_zero": frac_zero,
            "blocks": blocks,
            "walk_surface": walk_surface,
            "block_cell_count": block_cell_count,
            "anchor_cell": anchor_cell,
            "sub_grid": sub_grid,
            "sub_fill": sub_fill,
            "crop_offset": [0, 0],
            "trunk_columns": list(range(fp_cols * 4)),
            "contact_px": fp_cols * cell_px,
            "contact_reference_px": float(fp_cols * cell_px),
            "blocked_by_scale": {str(s): None for s in [0.85, 1.0, 1.15, 1.35, 1.6]},
            "block_rect": None,
            "block_rect_px": None,
        }

    # Transparent image
    cov, cols, rows, frac_zero = derive.coverage_grid(runtime_path, fp_cols, fp_rows)

    # Occluder mask
    gate = 0.20 if (fp_cols * fp_rows) > 1 else 0.35
    rule = "ground_contact" if collision_type == "ground_contact" else (
        "core_ring" if collision_type == "core_ring" else (
            "full_body" if collision_type in ("solid", "full_body") else "none"
        )
    )
    blocks = derive.occluder_mask(rule, cov, gate)
    if interactive_verb in ("doorway", "portal", "pass_under", "gate"):
        blocks = derive.apply_authored_open(blocks, "bottom_centre")

    walk_surface = derive.walk_surface_mask(cov, rule, collision_type == "walk_surface")
    block_cell_count = sum(sum(1 for cell in line if cell) for line in blocks)
    anchor_cell = (
        [cols // 2, rows - 1]
        if pivot == "bottom_center"
        else [cols // 2, rows // 2]
    )

    # Subcell details
    fill, sub_cols, sub_rows, crop_x, crop_y, _ = subcell.subcell_fill(runtime_path)
    cols_solid = subcell.trunk_columns(fill, solid=subcell.SOLID_FILL)
    alpha = geometry.read_alpha(runtime_path)
    run = geometry.contact_run(runtime_path)
    contact = run[1] - run[0] if run else 0
    canvas_w, canvas_h = alpha.size
    ref_scale = min(fp_cols * cell_px / canvas_w, fp_rows * cell_px / canvas_h)
    contact_ref = contact * ref_scale
    box_center = fp_cols * cell_px / 2
    contact_center = (
        box_center + ((run[0] + run[1]) / 2 - canvas_w / 2) * ref_scale
        if run
        else box_center
    )

    by_scale = {}
    floor_cells = 1 if rule == "ground_contact" else 0
    for s in [0.85, 1.0, 1.15, 1.35, 1.6]:
        if rule in ("full_body", "core_ring"):
            by_scale[str(s)] = [0, 0, fp_cols - 1, fp_rows - 1] if block_cell_count > 0 else None
        else:
            center = box_center + (contact_center - box_center) * s
            r = subcell.rect_at_scale(contact_ref, s, fp_cols, fp_rows, min_cells=floor_cells, center_px=center)
            by_scale[str(s)] = r

    rect = by_scale.get("1.0")
    rect_px = (
        None
        if rect is None
        else [rect[0] * cell_px, rect[1] * cell_px, (rect[2] + 1) * cell_px, (rect[3] + 1) * cell_px]
    )

    return {
        "coverage": cov,
        "frac_zero": frac_zero,
        "blocks": blocks,
        "walk_surface": walk_surface,
        "block_cell_count": block_cell_count,
        "anchor_cell": anchor_cell,
        "sub_grid": [sub_cols, sub_rows],
        "sub_fill": fill,
        "crop_offset": [crop_x, crop_y],
        "trunk_columns": cols_solid,
        "contact_px": contact,
        "contact_reference_px": contact_ref,
        "blocked_by_scale": by_scale,
        "block_rect": rect,
        "block_rect_px": rect_px,
    }


def package_batch(source_dir: Path, batch_name: str = "Batch 1") -> int:
    if not PACK_PATH.is_file():
        print(f"Error: pack manifest not found at {PACK_PATH}", file=sys.stderr)
        return 1

    with open(PACK_PATH, "r", encoding="utf-8") as f:
        pack = json.load(f)

    assets = pack.get("assets", [])
    files = list(source_dir.glob("*.png"))
    print(f"Loaded {len(assets)} assets from manifest, {len(files)} source files from {source_dir}")

    installed_count = 0

    for idx, asset in enumerate(assets, 1):
        asset_id = asset["id"]
        category = asset.get("category", "misc")
        slug = asset_id.split(".")[-1]
        file_prefix = asset_id.replace(".", "_")

        # Find matching generated image
        matched_files = [f for f in files if f.name.startswith(file_prefix)]
        if not matched_files:
            continue

        raw_source = matched_files[0]
        alpha_mode = asset.get("alpha", "transparent")
        pivot = asset.get("pivot", "bottom_center")
        canvas_px = asset.get("canvas_px", [128, 128])
        footprint = asset.get("footprint_cells", [1, 1])
        collision_type = asset.get("collision_type", "none")
        interactive_verb = asset.get("interactive_verb")

        # 1. Archive original image
        orig_category_dir = ORIGINAL_DIR / category
        orig_category_dir.mkdir(parents=True, exist_ok=True)
        dest_orig = orig_category_dir / raw_source.name
        if not dest_orig.is_file():
            shutil.copy2(raw_source, dest_orig)

        # 2. Normalize and save runtime PNG
        runtime_category_dir = RUNTIME_DIR / category
        runtime_category_dir.mkdir(parents=True, exist_ok=True)
        runtime_png = runtime_category_dir / f"{slug}.png"
        normalize_image(
            raw_source,
            runtime_png,
            (canvas_px[0], canvas_px[1]),
            alpha_mode,
            pivot=pivot,
            margin=16,
        )

        # 3. Compute diagnostic matrix data
        matrix_data = compute_matrix_data(
            runtime_png,
            footprint,
            alpha_mode,
            collision_type,
            pivot=pivot,
            interactive_verb=interactive_verb,
        )

        # 4. Update asset metadata
        rel_runtime_path = f"res://assets/packs/ancient_china_mortal/runtime/{category}/{slug}.png"
        asset.update({
            "status": "generated",
            "path": rel_runtime_path,
            "source": "ComfyUI local unet: krea2/raySemiReal_krea2TurboV1Nsfw.safetensors, lora: krea2/Scottie__Krea2.safetensors (1.0)",
            "license": "Generated locally; source checkpoint license terms apply",
            "generated_on": time.strftime("%Y-%m-%d"),
            "prompt_ref": f"comfyui-map-v1:{asset_id}:auto",
            "matrix_data": matrix_data,
        })

        # 5. Emit individual asset data JSON file
        data_category_dir = DATA_DIR / category
        data_category_dir.mkdir(parents=True, exist_ok=True)
        data_json_path = data_category_dir / f"{slug}.json"
        data_json_path.write_text(json.dumps(asset, indent=2, ensure_ascii=False), encoding="utf-8")

        installed_count += 1
        if idx % 20 == 0 or idx == len(assets):
            print(f"[{installed_count}/{len(assets)}] Installed {asset_id} -> {rel_runtime_path}")

    # Write updated pack manifest
    pack_manifest_path = PACK_PATH
    temp_pack = PACK_PATH.with_suffix(".tmp")
    with open(temp_pack, "w", encoding="utf-8") as f:
        json.dump(pack, f, indent=2, ensure_ascii=False)
    temp_pack.replace(pack_manifest_path)
    print(f"\nSaved updated pack manifest to {PACK_PATH}")
    print(f"Successfully packaged and installed {installed_count} assets.")

    # 6. Run Godot headless import to generate .import files
    print("\nInvoking Godot headless editor to import new textures and generate .import files...")
    res = run_godot(["--headless", "--editor", "--path", str(GAME_DIR), "--import", "--quit"], capture=True, tag="mortal-pack-import")
    print(f"Godot import process finished with returncode {res.returncode}")

    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, default=REPO_ROOT / "build" / "ancient_china_mortal_batch1")
    parser.add_argument("--batch", type=str, default="Batch 1")
    args = parser.parse_args()
    sys.exit(package_batch(args.source_dir, batch_name=args.batch))
