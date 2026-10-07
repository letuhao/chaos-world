"""Automated generation and packaging pipeline for Ancient China Low Cultivation asset pack.

Migrated 4-tier hierarchy:
Pack (`ancient_china_low_cultivation`)
  └── Domain (`domain_id`)
        └── Sub-Domain (`sub_domain_id`)
              └── Individual Asset Folder (`asset_slug`)
                    └── Variant Files (`<variant_slug>.png`, `<variant_slug>.json`, `<variant_slug>_raw.png`)

Iterates through planned assets and their variants, calls ComfyUI local API,
archives raw images, normalizes runtime PNGs, calculates diagnostic matrix data,
emits individual variant and aggregated asset data JSONs, updates the pack manifest,
and invokes Godot headless editor to generate engine .import files.
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

LOG_PATH = REPO_ROOT / "build" / "package_low_cultivation.log"
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

PACK_ID = "ancient_china_low_cultivation"
PACK_DIR = REPO_ROOT / "game" / "assets" / "packs" / PACK_ID
PACK_PATH = PACK_DIR / f"{PACK_ID}_pack.json"
ORIGINAL_DIR = PACK_DIR / "original"
RUNTIME_DIR = PACK_DIR / "runtime"
DATA_DIR = PACK_DIR / "data"
GAME_DIR = REPO_ROOT / "game"

STYLE_PROMPT_CLAUSE = (
    "2D orthographic top-down (~45 degrees), gouache hand-painted, ink contour lines (#263A35), "
    "spiritual misty palette (celadon jade #7A9A8B, spirit spring azure #4A7A8C, "
    "vermilion cinnabar #A8382B, weathered pine #5A4838, loess ochre #B88648, incense ash #4A4A52). "
    "Isolated on solid pure white background, crisp silhouette."
)


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

    cov, cols, rows, frac_zero = derive.coverage_grid(runtime_path, fp_cols, fp_rows)

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
    try:
        with open(PACK_PATH, "w", encoding="utf-8") as f:
            json.dump(pack, f, indent=2, ensure_ascii=False)
        if temp_pack.exists():
            temp_pack.unlink()
    except Exception as e:
        print(f"Warning: could not save manifest: {e}", file=sys.stderr)


def get_asset_paths(domain: str, sub_domain: str, asset_slug: str, variant_slug: str) -> dict[str, Path]:
    """Resolves hierarchical paths:
    pack -> domain -> sub_domain -> asset_slug -> variant files
    """
    runtime_asset_dir = RUNTIME_DIR / domain / sub_domain / asset_slug
    orig_asset_dir = ORIGINAL_DIR / domain / sub_domain / asset_slug
    data_asset_dir = DATA_DIR / domain / sub_domain / asset_slug

    return {
        "runtime_dir": runtime_asset_dir,
        "runtime_png": runtime_asset_dir / f"{variant_slug}.png",
        "orig_dir": orig_asset_dir,
        "orig_raw": orig_asset_dir / f"{variant_slug}_raw.png",
        "data_dir": data_asset_dir,
        "variant_json": data_asset_dir / f"{variant_slug}.json",
        "asset_json": data_asset_dir / "asset.json",
    }


ANTI_DRIFT_CLAUSE = (
    "Japanese style, torii gate, shinto shrine, katana, samurai armor, tatami, ninja, "
    "western gothic castle, medieval stone fortress, European church, witch cauldron, "
    "laboratory glassware, modern objects, anime mech, sci-fi wires"
)


def build_game_ready_prompt(asset: dict, var: dict) -> tuple[str, str]:
    """
    Construct game-ready positive prompt and negative prompt based on the 7 Archetypes
    defined in Section 8 of README.md, strictly preventing diorama, chimera, and cultural drift.
    """
    asset_class = (
        asset.get("asset_class")
        or asset.get("type")
        or "prop_workstation"
    ).lower()

    asset_name = asset.get("name") or asset.get("id", "cultivation_asset")
    material = asset.get("material", "carved wood and polished bronze")
    var_mod = var.get("prompt_modifier") or var.get("prompt") or ""
    var_slug = var.get("variant_slug", "")

    # Adaptive background contrast keying: prevent white/snow assets from being clipped by RMBG-2.0
    is_pale = (
        "winter" in var_slug
        or "snow" in var_slug
        or any(w in asset_name.lower() for w in ("white", "crane", "snow", "jade", "frost", "silver", "pale"))
    )
    adaptive_bg = "solid neutral contrast grey background (#D0D0D0)" if is_pale else "solid pure white background (#FFFFFF)"

    # Archetype 1: Items, Handheld Tools, Weapons & Pickups
    if any(k in asset_class for k in ("item", "tool", "weapon", "talisman", "consumable", "icon")):
        pos = (
            f"Single isolated 2D game asset of {asset_name.lower()}, {material}, {var_mod}, "
            "Ancient Chinese Xianxia cultivation mortal realm aesthetic, double-edged Chinese straight sword or authentic Daoist implement, "
            "bold readable silhouette, clean grouped value planes, chunky stylized proportions for 2D icon clarity, "
            f"fine dark #263A35 ink contours, gouache hand-painted, centered on {adaptive_bg}."
        )
        neg = (
            "diorama, miniature scene, floating island, dirt slab, grass pedestal, ground plane, "
            "floor, surface, shadow on ground, building, house, cottage, farm, fence, landscape, "
            "trees, field, human hands, fingers, holding, multiple items, collection, collage, border, "
            f"frame, UI, watermark, blurry edges, microscopic high-frequency noise, {ANTI_DRIFT_CLAUSE}"
        )
        return pos, neg

    # Archetype 6: Ground Terrains, Walk Surfaces & Path Decals
    dom = asset.get("domain", "")
    if any(k in asset_class for k in ("terrain", "tile", "surface_decal", "ground")) or "terrain" in dom:
        pos = (
            f"Seamless flat 2D top-down ground terrain texture of {asset_name.lower()}, {material}, {var_mod}, "
            "90-degree perpendicular overhead camera angle, completely flat planar surface filling 100% of canvas corner-to-corner, "
            "gouache painted, dark ink linework, zero perspective, zero horizon, no focal prop."
        )
        neg = (
            "perspective, 45-degree angle, isometric, horizon, 3D elevation, relief shading, trees, "
            f"plants, buildings, houses, fences, focal object, standalone prop, pedestal, frame, borders, {ANTI_DRIFT_CLAUSE}"
        )
        return pos, neg

    # Archetype 7: Atmospheric VFX & Overlay Particle Sheets (Bypasses RemBG in post-process)
    if any(k in asset_class for k in ("vfx", "particle", "overlay", "phenomena")):
        pos = (
            f"2D game particle VFX sprite of {asset_name.lower()}, {var_mod}, "
            "luminous spiritual motes, soft radiant glow edges, glowing magical energy, "
            "isolated on solid pure black background (#000000) for additive alpha blending."
        )
        neg = "white background, opaque solid shapes, opaque borders, ground, floor, landscape, characters, buildings, terrain, solid geometry, ui frames"
        return pos, neg

    # Archetype 4: Flora, Spirit Herbs & Sacred Trees
    if any(k in asset_class for k in ("flora", "herb", "tree", "plant")):
        pos = (
            f"Single isolated 2D RPG plant sprite of {asset_name.lower()}, {material}, {var_mod}, "
            "Ancient Chinese herbal lore aesthetic, traditional Bencao Gangmu medicinal plant style, "
            "gouache hand-painted with dark ink contours, ground root base contact only, zero terrain mound, "
            "isolated on solid plain white background."
        )
        neg = (
            "diorama, plant pot, planter, flowerbed border, dirt mound base, turf chunk, forest background, "
            f"surrounding grass, garden scene, landscape, mountains, sky, multiple clumps, human hands, shears, {ANTI_DRIFT_CLAUSE}"
        )
        return pos, neg

    # Archetype 5: Fauna, Spirit Beasts, Demons & Denizens
    if any(k in asset_class for k in ("fauna", "beast", "creature", "monster", "npc")):
        pos = (
            f"Single isolated 2D game creature sprite of {asset_name.lower()}, {material}, {var_mod}, "
            "Shan Hai Jing ancient Chinese mythological bestiary style, gouache painted with dark ink contours, "
            f"ground foot contact shadow only, zero directional drop shadow, isolated on {adaptive_bg}."
        )
        neg = (
            "diorama, cage, stable, pen, pasture, fence, saddle, reins, rider, trainer, human hands, "
            f"background scenery, landscape, grass chunk, multiple animals, herd, UI healthbar, floating icons, {ANTI_DRIFT_CLAUSE}"
        )
        return pos, neg

    # Archetype 3: Architecture, Sect Facilities & Gateways
    if any(k in asset_class for k in ("structure", "building", "architecture", "gateway", "gate", "pagoda", "pavilion", "tower", "hall")):
        pos = (
            f"Single isolated 2D RPG architectural building sprite of {asset_name.lower()}, {material}, {var_mod}, "
            "Ancient Chinese Tang-Song Xianxia architectural style, upturned dougong bracket eaves, glazed ceramic roof tiles, "
            "carved timber joinery, vermilion columns, gouache hand-painted with dark #263A35 ink contours, "
            "clean horizontal ground contact baseline, micro contact shadow only, isolated on solid plain white background."
        )
        neg = (
            "diorama, miniature landscape, floating rock island, cutaway foundation, courtyard boundary walls, "
            "garden lawn, surrounding trees, forest, mountains, sky, clouds, horizon, roads, cobblestone path, "
            f"human figures, isometric box frame, cutout diorama base, directional drop shadow, {ANTI_DRIFT_CLAUSE}"
        )
        return pos, neg

    # Default / Archetype 2: Workstations, Heavy Apparatus & Functional Props
    pos = (
        f"Single isolated 2D RPG game prop of {asset_name.lower()}, {material}, {var_mod}, "
        "Ancient Chinese Xianxia cultivation aesthetic, authentic Chinese tripod ding cauldron or traditional workshop implement, "
        "gouache hand-painted with crisp dark #263A35 ink contours, flat zero-cast-shadow baseline, "
        "micro ambient contact occlusion directly under feet only, isolated on solid plain white background."
    )
    neg = (
        "diorama, miniature base, floating island, dirt chunk, grass slab, square tile pedestal, floor plane, "
        "room interior, walls, ceiling, surrounding furniture, background building, trees, outdoor scenery, "
        f"multiple objects, human operator, worker, collage, frame, directional cast shadow, {ANTI_DRIFT_CLAUSE}"
    )
    return pos, neg


def run_pipeline(
    domain_filter: str | None = None,
    sub_domain_filter: str | None = None,
    asset_filter: str | None = None,
    variant_filter: str | None = None,
    limit: int | None = None,
    skip_godot_import: bool = False,
    dry_run: bool = False,
) -> int:
    if not PACK_PATH.is_file():
        print(f"Error: manifest not found at {PACK_PATH}", file=sys.stderr)
        return 1

    with open(PACK_PATH, "r", encoding="utf-8") as f:
        pack = json.load(f)

    assets = pack.get("assets", [])
    print(f"Loaded pack '{PACK_ID}' with {len(assets)} registered assets.")

    # Flatten planned items: each item is an (asset_entry, variant_entry) pair
    work_items = []
    for asset in assets:
        dom = asset.get("domain", "misc")
        sub_dom = asset.get("sub_domain", "general")
        asset_slug = asset.get("asset_slug") or asset.get("id", "").split(".")[-1]

        if domain_filter and dom != domain_filter:
            continue
        if sub_domain_filter and sub_dom != sub_domain_filter:
            continue
        if asset_filter and asset_slug != asset_filter and asset.get("id") != asset_filter:
            continue

        variants = asset.get("variants", [])
        if not variants:
            # Single default variant if not explicitly decomposed
            variants = [{
                "variant_slug": "default",
                "name": asset.get("name", asset_slug),
                "prompt_modifier": "",
                "status": asset.get("status", "planned"),
            }]

        for var in variants:
            var_slug = var.get("variant_slug", "default")
            if variant_filter and var_slug != variant_filter:
                continue

            var_status = var.get("status") or asset.get("status", "planned")
            if var_status == "planned":
                work_items.append((asset, var))

    if limit:
        work_items = work_items[:limit]

    print(f"Discovered {len(work_items)} planned variant targets to process.")

    if not work_items:
        print("No planned variants to generate in this scope.")
        return 0

    if dry_run:
        print("\n--- DRY RUN: Planned Variant Hierarchy Targets ---")
        for idx, (asset, var) in enumerate(work_items, 1):
            dom = asset.get("domain", "misc")
            sub_dom = asset.get("sub_domain", "general")
            asset_slug = asset.get("asset_slug") or asset.get("id", "").split(".")[-1]
            var_slug = var.get("variant_slug", "default")
            paths = get_asset_paths(dom, sub_dom, asset_slug, var_slug)
            print(f"[{idx}] {dom} / {sub_dom} / {asset_slug} / {var_slug}.png")
            print(f"     Runtime Target: {paths['runtime_png']}")
            print(f"     Data Target:    {paths['variant_json']}")
        return 0

    success_count = 0
    skipped_count = 0
    failed_count = 0
    t0_all = time.time()

    temp_gen_dir = REPO_ROOT / "build" / f"{PACK_ID}_gen_temp"
    temp_gen_dir.mkdir(parents=True, exist_ok=True)

    for idx, (asset, var) in enumerate(work_items, 1):
        asset_id = asset["id"]
        dom = asset.get("domain", "misc")
        sub_dom = asset.get("sub_domain", "general")
        asset_slug = asset.get("asset_slug") or asset_id.split(".")[-1]
        var_slug = var.get("variant_slug", "default")

        paths = get_asset_paths(dom, sub_dom, asset_slug, var_slug)
        paths["runtime_dir"].mkdir(parents=True, exist_ok=True)
        paths["orig_dir"].mkdir(parents=True, exist_ok=True)
        paths["data_dir"].mkdir(parents=True, exist_ok=True)

        canvas_px = var.get("canvas_px") or asset.get("canvas_px", [128, 128])
        footprint = var.get("footprint_cells") or asset.get("footprint_cells", [1, 1])
        alpha_mode = var.get("alpha") or asset.get("alpha", "transparent")
        pivot = var.get("pivot") or asset.get("pivot", "bottom_center")
        collision_type = var.get("collision_type") or asset.get("collision_type", "none")
        interactive_verb = var.get("interactive_verb") or asset.get("interactive_verb")

        # Skip if already generated
        if paths["runtime_png"].is_file() and paths["variant_json"].is_file():
            print(f"[{idx}/{len(work_items)}] SKIPPED (already installed): {asset_slug} -> {var_slug}")
            skipped_count += 1
            var["status"] = "generated"
            var["path"] = f"res://assets/packs/{PACK_ID}/runtime/{dom}/{sub_dom}/{asset_slug}/{var_slug}.png"
            continue

        print(f"\n[{idx}/{len(work_items)}] GENERATING: {dom}/{sub_dom}/{asset_slug} [{var_slug}]")
        t_start = time.time()

        args = ComfyArgs()
        pos_prompt, neg_prompt = build_game_ready_prompt(asset, var)
        args.prompt = pos_prompt
        args.negative = neg_prompt
        args.seed = 7000 + idx

        generated_source: Path | None = None
        for attempt in range(3):
            try:
                gen_dict = {
                    "id": f"{asset_id}.{var_slug}",
                    "name": f"{asset.get('name')} ({var_slug})",
                    "category": sub_dom,
                    "prompt": args.prompt,
                }
                out_path, _, _ = generate(
                    gen_dict,
                    args,
                    output_dir=f"{PACK_ID}_gen_temp",
                )
                generated_source = out_path
                break
            except ToolError as te:
                if "refusing to overwrite" in str(te):
                    matches = list(temp_gen_dir.glob(f"*{asset_slug}*{var_slug}*"))
                    if matches:
                        generated_source = matches[0]
                        break
                print(f"  [Attempt {attempt+1}] ToolError: {te}")
                time.sleep(2)
            except Exception as e:
                print(f"  [Attempt {attempt+1}] Error: {e}")
                time.sleep(3)

        if not generated_source or not generated_source.is_file():
            print(f"  FAILED to generate variant {asset_slug} -> {var_slug}")
            failed_count += 1
            continue

        # 1. Archive raw original
        if not paths["orig_raw"].is_file():
            shutil.copy2(generated_source, paths["orig_raw"])

        # 2. Normalize runtime PNG
        normalize_image(
            generated_source,
            paths["runtime_png"],
            (canvas_px[0], canvas_px[1]),
            alpha_mode,
            pivot=pivot,
            margin=16,
        )

        # 3. Compute matrix_data
        matrix_data = compute_matrix_data(
            paths["runtime_png"],
            footprint,
            alpha_mode,
            collision_type,
            pivot=pivot,
            interactive_verb=interactive_verb,
        )

        # 4. Update variant metadata
        rel_runtime_path = f"res://assets/packs/{PACK_ID}/runtime/{dom}/{sub_dom}/{asset_slug}/{var_slug}.png"
        var.update({
            "status": "generated",
            "path": rel_runtime_path,
            "generated_on": time.strftime("%Y-%m-%d"),
            "matrix_data": matrix_data,
        })

        # 5. Emit variant JSON
        var_payload = {
            "asset_id": asset_id,
            "domain": dom,
            "sub_domain": sub_dom,
            "asset_slug": asset_slug,
            "variant_slug": var_slug,
            "name": var.get("name", f"{asset.get('name')} ({var_slug})"),
            "path": rel_runtime_path,
            "footprint_cells": footprint,
            "canvas_px": canvas_px,
            "alpha": alpha_mode,
            "pivot": pivot,
            "collision_type": collision_type,
            "interactive_verb": interactive_verb,
            "matrix_data": matrix_data,
        }
        paths["variant_json"].write_text(json.dumps(var_payload, indent=2, ensure_ascii=False), encoding="utf-8")

        # 6. Update master asset.json
        paths["asset_json"].write_text(json.dumps(asset, indent=2, ensure_ascii=False), encoding="utf-8")

        elapsed = time.time() - t_start
        print(f"  -> SUCCESS ({elapsed:.1f}s): {rel_runtime_path}")
        success_count += 1

        if success_count % 5 == 0:
            save_manifest(pack)
            print(f"  [Checkpoint] Saved manifest ({success_count} variants processed).")

    save_manifest(pack)
    print(f"\nManifest saved to {PACK_PATH}")
    print(f"Finished pipeline: {success_count} succeeded, {skipped_count} skipped, {failed_count} failed in {time.time()-t0_all:.1f}s")

    # Godot headless editor import
    if not skip_godot_import and success_count > 0:
        print("\nInvoking Godot headless editor to import new textures...")
        res = run_godot(["--headless", "--editor", "--path", str(GAME_DIR), "--import", "--quit"], capture=True, tag="low-cultivation-import")
        print(f"Godot import process finished with returncode {res.returncode}")

    return 0 if failed_count == 0 else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Living Map Generation Pipeline for Ancient China Low Cultivation Pack")
    parser.add_argument("--domain", type=str, default=None, help="Filter by domain ID")
    parser.add_argument("--sub-domain", type=str, default=None, help="Filter by sub-domain ID")
    parser.add_argument("--asset", type=str, default=None, help="Filter by asset slug or ID")
    parser.add_argument("--variant", type=str, default=None, help="Filter by variant slug")
    parser.add_argument("--limit", type=int, default=None, help="Limit number of variants to process")
    parser.add_argument("--skip-import", action="store_true", default=False, help="Skip Godot headless import")
    parser.add_argument("--dry-run", action="store_true", default=False, help="Show planned file paths without generating")
    args = parser.parse_args()

    sys.exit(run_pipeline(
        domain_filter=args.domain,
        sub_domain_filter=args.sub_domain,
        asset_filter=args.asset,
        variant_filter=args.variant,
        limit=args.limit,
        skip_godot_import=args.skip_import,
        dry_run=args.dry_run,
    ))
