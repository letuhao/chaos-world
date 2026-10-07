"""Automated generation, packaging, and data derivation pipeline for Medieval Western asset pack.

Iterates through planned assets across target spheres/batches, calls ComfyUI local API,
archives raw images, normalizes runtime PNGs, calculates diagnostic matrix data,
emits individual asset data JSONs, updates the pack manifest, and invokes Godot
headless editor to generate engine .import files.
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
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / ".agents" / "skills" / "map-asset-pipeline" / "scripts"))

sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

LOG_PATH = REPO_ROOT / "build" / "package_medieval_western.log"
LOG_PATH.parent.mkdir(parents=True, exist_ok=True)


class TeeWriter:
    def __init__(self, stream, log_file_path):
        self.stream = stream
        self.log_file = open(log_file_path, "a", encoding="utf-8", buffering=1)

    def write(self, data):
        self.stream.write(data)
        try:
            self.log_file.write(data)
        except Exception:
            pass

    def flush(self):
        self.stream.flush()
        try:
            self.log_file.flush()
        except Exception:
            pass


sys.stdout = TeeWriter(sys.stdout, LOG_PATH)
sys.stderr = TeeWriter(sys.stderr, LOG_PATH)

import geometry
import derive
import subcell
from tools.common import ToolError
from tools.godot import run_godot
from tools.map_generate import generate

PACK_DIR = REPO_ROOT / "game" / "assets" / "packs" / "medieval_western"
PACK_PATH = PACK_DIR / "medieval_western_pack.json"
CATEGORIES_PATH = PACK_DIR / "categories.json"
ORIGINAL_DIR = PACK_DIR / "original"
RUNTIME_DIR = PACK_DIR / "runtime"
DATA_DIR = PACK_DIR / "data"
GAME_DIR = REPO_ROOT / "game"

# 7 Life Spheres
SPHERES = {
    "sphere1": "Cultural Crossroads",
    "sphere2": "Built Architecture",
    "sphere3": "Faith & Mortality",
    "sphere4": "Manorial Supply Chains",
    "sphere5": "Commerce & Urban Life",
    "sphere6": "War & Underworld",
    "sphere7": "Ecology & Living Traces",
}


def load_sphere_categories() -> dict[str, list[str]]:
    """Build mapping of sphere identifier -> list of category IDs."""
    if not CATEGORIES_PATH.is_file():
        raise FileNotFoundError(f"Missing categories.json at {CATEGORIES_PATH}")
    categories_data = json.loads(CATEGORIES_PATH.read_text(encoding="utf-8"))

    # Map sphere name to category IDs
    sphere_name_to_ids: dict[str, list[str]] = {}
    for cat in categories_data:
        s_name = cat.get("sphere", "Other")
        sphere_name_to_ids.setdefault(s_name, []).append(cat["id"])

    res: dict[str, list[str]] = {}
    for s_key, s_name in SPHERES.items():
        res[s_key] = sphere_name_to_ids.get(s_name, [])
        # Also alias batch1 -> sphere1
        b_key = s_key.replace("sphere", "batch")
        res[b_key] = res[s_key]

    return res


class ComfyArgs:
    profile = "krea2"
    checkpoint = "krea2/raySemiReal_krea2TurboV1Nsfw.safetensors"
    steps = 8
    cfg = 1.0
    guidance = None
    sampler = "euler_ancestral"
    scheduler = "beta"
    size = 1024
    width = None
    height = None
    rembg_model = "RMBG-2.0"
    rembg_post_processing = False
    alpha_matting = False
    alpha_foreground_threshold = 240
    alpha_background_threshold = 10
    alpha_erode_size = 0
    comfy_url = "http://127.0.0.1:8188"
    timeout = 600
    compare_rembg = False
    prompt = ""
    seed = -1
    lora = "scottie:1.0"
    lora_strength = 1.0


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

    if alpha_mode in ("transparent", "cutout"):
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

    cov, cols, rows, frac_zero = derive.coverage_grid(runtime_path, fp_cols, fp_rows)

    gate = 0.20 if (fp_cols * fp_rows) > 1 else 0.35
    rule = "ground_contact" if collision_type == "ground_contact" else (
        "core_ring" if collision_type == "core_ring" else (
            "full_body" if collision_type in ("solid", "full_body") else "none"
        )
    )
    blocks = derive.occluder_mask(rule, cov, gate)
    if interactive_verb in ("doorway", "portal", "pass_under", "gate", "open"):
        blocks = derive.apply_authored_open(blocks, "bottom_centre")

    walk_surface = derive.walk_surface_mask(cov, rule, collision_type == "walk_surface")
    block_cell_count = sum(sum(1 for cell in line if cell) for line in blocks)
    anchor_cell = (
        [cols // 2, rows - 1]
        if pivot == "bottom_center"
        else [cols // 2, rows // 2]
    )

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


def save_manifest(pack: dict) -> None:
    temp_pack = PACK_PATH.with_suffix(".tmp")
    with open(temp_pack, "w", encoding="utf-8") as f:
        json.dump(pack, f, indent=2, ensure_ascii=False)
    for _ in range(10):
        try:
            temp_pack.replace(PACK_PATH)
            return
        except PermissionError:
            time.sleep(0.5)
    # Direct fallback if replace is locked
    try:
        with open(PACK_PATH, "w", encoding="utf-8") as f:
            json.dump(pack, f, indent=2, ensure_ascii=False)
        if temp_pack.exists():
            temp_pack.unlink()
    except Exception as e:
        print(f"Warning: could not save manifest: {e}", file=sys.stderr)


def determine_perspective_clause(asset: dict) -> str:
    """Return perspective guidance clause based on asset role and geometry."""
    role = asset.get("gameplay_role", "").lower()
    col = asset.get("collision_type", "").lower()
    subcat = asset.get("sub_category", "").lower()
    name = asset.get("name", "").lower()
    alpha = asset.get("alpha", "").lower()
    asset_type = asset.get("type", "").lower()

    is_ground_plane = (
        asset_type in ("terrain_texture", "tile")
        or col in ("none", "walk_surface") and (
            alpha == "opaque"
            or any(kw in role for kw in ("decal", "mat", "rug", "carpet", "tray", "puddle", "rut", "litter", "threshing", "shallow", "pool", "shingle", "patch", "mud", "footprint", "ground", "paving", "cobble", "furrow"))
            or any(kw in subcat for kw in ("puddle", "litter", "rut", "wetland", "mud", "footprint", "furrow", "paving", "cobble"))
            or any(kw in name for kw in ("paving", "rut", "puddle", "mat", "carpet", "rug", "mud", "furrow", "patch", "moss", "decal"))
        )
    )

    if is_ground_plane:
        return "Strict overhead top-down bird's-eye 90-degree perpendicular plan view, looking directly straight down from sky, flat planar projection. "
    else:
        return "2D orthographic top-down 45-degree angle RPG map view, showing front elevation facade and upper surface clearly, ground-facing silhouette. "


def run_pipeline(
    batch_name: str = "sphere1",
    category_filter: str | None = None,
    limit: int | None = None,
    skip_godot_import: bool = False,
) -> int:
    sphere_cats = load_sphere_categories()

    if batch_name in ("all", "all_spheres") and not category_filter:
        print("=== Full Run: Processing All 7 Spheres sequentially ===")
        total_ret = 0
        for s in ["sphere1", "sphere2", "sphere3", "sphere4", "sphere5", "sphere6", "sphere7"]:
            print(f"\n==========================================")
            print(f"       STARTING {s.upper()} ({SPHERES.get(s)})")
            print(f"==========================================")
            ret = run_single_batch(
                batch_name=s,
                category_filter=None,
                limit=limit,
                skip_godot_import=skip_godot_import,
                sphere_cats=sphere_cats,
            )
            if ret != 0:
                print(f"Warning: {s} finished with errors.")
                total_ret = ret
        return total_ret

    return run_single_batch(
        batch_name=batch_name,
        category_filter=category_filter,
        limit=limit,
        skip_godot_import=skip_godot_import,
        sphere_cats=sphere_cats,
    )


def run_single_batch(
    batch_name: str,
    category_filter: str | None,
    limit: int | None,
    skip_godot_import: bool,
    sphere_cats: dict[str, list[str]],
) -> int:
    with open(PACK_PATH, "r", encoding="utf-8") as f:
        pack = json.load(f)

    assets = pack.get("assets", [])
    print(f"Loaded {len(assets)} total assets from medieval western pack manifest.")

    # Determine target categories
    norm_batch = batch_name.lower().strip()
    if norm_batch.startswith("batch"):
        norm_batch = norm_batch.replace("batch", "sphere")

    if category_filter:
        target_cats = [category_filter]
    elif norm_batch in sphere_cats:
        target_cats = sphere_cats[norm_batch]
    else:
        # Check if sphere name directly matched
        matched = [k for k, name in SPHERES.items() if name.lower() == norm_batch]
        if matched:
            target_cats = sphere_cats[matched[0]]
        else:
            raise ValueError(f"Unknown batch or sphere: {batch_name}. Available: {list(SPHERES.keys())}")

    target_assets = [
        a for a in assets
        if a.get("category") in target_cats and a.get("status") == "planned"
    ]
    if limit:
        target_assets = target_assets[:limit]

    sphere_title = SPHERES.get(norm_batch, norm_batch)
    print(f"Target scope: sphere '{norm_batch}' ({sphere_title}), categories: {len(target_cats)} {target_cats}")
    print(f"Found {len(target_assets)} planned assets to generate and package.")

    if not target_assets:
        print("No planned assets to process in this scope.")
        return 0

    success_count = 0
    skipped_count = 0
    failed_count = 0
    t0_all = time.time()

    temp_gen_dir = REPO_ROOT / "build" / f"medieval_western_gen_{norm_batch}"
    temp_gen_dir.mkdir(parents=True, exist_ok=True)

    for idx, asset in enumerate(target_assets, 1):
        asset_id = asset["id"]
        category = asset.get("category", "misc")
        slug = asset_id.split(".")[-1]
        canvas_px = asset.get("canvas_px", [128, 128])
        footprint = asset.get("footprint_cells", [1, 1])
        alpha_mode = asset.get("alpha", "cutout")
        pivot = asset.get("pivot", "bottom_center")
        collision_type = asset.get("collision_type", "none")
        interactive_verb = asset.get("interactive_verb")

        runtime_cat_dir = RUNTIME_DIR / category
        runtime_cat_dir.mkdir(parents=True, exist_ok=True)
        runtime_png = runtime_cat_dir / f"{slug}.png"

        orig_cat_dir = ORIGINAL_DIR / category
        orig_cat_dir.mkdir(parents=True, exist_ok=True)

        data_cat_dir = DATA_DIR / category
        data_cat_dir.mkdir(parents=True, exist_ok=True)
        data_json = data_cat_dir / f"{slug}.json"

        # Check if already generated and runtime png exists
        if runtime_png.is_file() and data_json.is_file():
            print(f"[{idx}/{len(target_assets)}] SKIPPED (already installed): {asset_id}")
            rel_runtime_path = f"res://assets/packs/medieval_western/runtime/{category}/{slug}.png"
            try:
                dj = json.loads(data_json.read_text(encoding="utf-8"))
                asset.update({
                    "status": "generated",
                    "path": rel_runtime_path,
                    "matrix_data": dj.get("matrix_data"),
                })
            except Exception:
                asset["status"] = "generated"
                asset["path"] = rel_runtime_path
            skipped_count += 1
            continue

        print(f"\n[{idx}/{len(target_assets)}] GENERATING: {asset_id} ({asset.get('name')})")
        t_asset_start = time.time()

        args = ComfyArgs()
        base_prompt = asset.get("prompt_summary") or asset.get("name") or asset_id
        perspective_clause = determine_perspective_clause(asset)

        args.prompt = f"{base_prompt}. {perspective_clause}"
        args.seed = 6000 + idx

        # Generate via ComfyUI
        generated_source: Path | None = None
        for attempt in range(3):
            try:
                out_path, _, used_seed = generate(
                    asset,
                    args,
                    output_dir=f"medieval_western_gen_{norm_batch}",
                )
                generated_source = out_path
                break
            except ToolError as te:
                if "refusing to overwrite" in str(te):
                    matches = list(temp_gen_dir.glob(f"{asset_id.replace('.', '_')}*"))
                    if matches:
                        generated_source = matches[0]
                        break
                print(f"  [Attempt {attempt+1}] ToolError: {te}")
                time.sleep(2)
            except Exception as e:
                print(f"  [Attempt {attempt+1}] Error generating {asset_id}: {e}")
                time.sleep(3)

        if not generated_source or not generated_source.is_file():
            print(f"  FAILED to generate asset {asset_id}")
            failed_count += 1
            continue

        # 1. Archive original raw image
        orig_dest = orig_cat_dir / generated_source.name
        if not orig_dest.is_file():
            shutil.copy2(generated_source, orig_dest)

        # 2. Normalize runtime PNG
        normalize_image(
            generated_source,
            runtime_png,
            (canvas_px[0], canvas_px[1]),
            alpha_mode,
            pivot=pivot,
            margin=16,
        )

        # 3. Compute diagnostic geometry matrix_data
        matrix_data = compute_matrix_data(
            runtime_png,
            footprint,
            alpha_mode,
            collision_type,
            pivot=pivot,
            interactive_verb=interactive_verb,
        )

        # 4. Update asset metadata
        rel_runtime_path = f"res://assets/packs/medieval_western/runtime/{category}/{slug}.png"
        asset.update({
            "status": "generated",
            "path": rel_runtime_path,
            "source": "ComfyUI local unet: krea2/raySemiReal_krea2TurboV1Nsfw.safetensors, lora: krea2/Scottie__Krea2.safetensors (1.0)",
            "license": "Generated locally; source checkpoint license terms apply",
            "generated_on": time.strftime("%Y-%m-%d"),
            "prompt_ref": f"comfyui-map-v1:{asset_id}:auto",
            "matrix_data": matrix_data,
        })

        # 5. Emit individual asset data JSON
        data_json.write_text(json.dumps(asset, indent=2, ensure_ascii=False), encoding="utf-8")

        elapsed_asset = time.time() - t_asset_start
        print(f"  -> SUCCESS ({elapsed_asset:.1f}s): {rel_runtime_path}")
        success_count += 1

        # Periodic manifest checkpoint every 5 items
        if success_count % 5 == 0:
            save_manifest(pack)
            print(f"  [Checkpoint] Saved manifest ({success_count} assets processed).")

    # Final manifest save
    save_manifest(pack)
    print(f"\nManifest saved to {PACK_PATH}")
    print(f"Finished sphere {norm_batch}: {success_count} succeeded, {skipped_count} skipped, {failed_count} failed in {time.time()-t0_all:.1f}s")

    # Godot headless import
    if not skip_godot_import and success_count > 0:
        print("\nInvoking Godot headless editor to import new textures and generate .import files...")
        res = run_godot(["--headless", "--editor", "--path", str(GAME_DIR), "--import", "--quit"], capture=True, tag="medieval-pack-import")
        print(f"Godot import process finished with returncode {res.returncode}")

    return 0 if failed_count == 0 else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Package Medieval Western Asset Pack")
    parser.add_argument(
        "--sphere",
        "--batch",
        dest="batch",
        type=str,
        default="sphere1",
        help="Target sphere or batch (sphere1..sphere7, batch1..batch7, all)",
    )
    parser.add_argument("--category", type=str, default=None, help="Filter to single category")
    parser.add_argument("--limit", type=int, default=None, help="Limit number of assets to process")
    parser.add_argument("--skip-import", action="store_true", default=False, help="Skip Godot headless import")
    args = parser.parse_args()

    sys.exit(run_pipeline(
        batch_name=args.batch,
        category_filter=args.category,
        limit=args.limit,
        skip_godot_import=args.skip_import,
    ))
