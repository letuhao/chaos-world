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
import json
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

import derive
import geometry
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
    "2D orthographic top-down (~45 degrees), gouache hand-painted, pine-soot ink contour lines (#1C1C1E), "
    "balanced East Asian Xianxia mineral palette (loess ochre #B88648, vermilion cinnabar #A8382B, "
    "weathered pine #5A4838, celadon jade #7A9A8B, spirit spring azure #4A7A8C, incense ash #4A4A52). "
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


def convert_black_bg_to_alpha(img: Image.Image, noise_floor: int = 8) -> Image.Image:
    """Convert a luminous VFX sprite generated on pure black (#000000)
    into a clean transparent RGBA sprite with unmultiplied color to avoid dark fringes.
    """
    rgb = img.convert("RGB")
    w, h = rgb.size
    raw_bytes = bytearray(rgb.tobytes())
    out_bytes = bytearray(w * h * 4)

    scale_table = [0.0] * 256
    for i in range(1, 256):
        scale_table[i] = 255.0 / i

    floor_range = 255 - noise_floor
    in_idx = 0
    out_idx = 0
    total_pixels = w * h

    for _ in range(total_pixels):
        r = raw_bytes[in_idx]
        g = raw_bytes[in_idx + 1]
        b = raw_bytes[in_idx + 2]
        in_idx += 3

        max_c = r if r > g else g
        if b > max_c:
            max_c = b

        if max_c <= noise_floor:
            pass
        else:
            pa = int((max_c - noise_floor) * 255 / floor_range)
            if pa > 255:
                pa = 255
            scale = scale_table[max_c]
            nr = int(r * scale)
            ng = int(g * scale)
            nb = int(b * scale)
            out_bytes[out_idx] = 255 if nr > 255 else nr
            out_bytes[out_idx + 1] = 255 if ng > 255 else ng
            out_bytes[out_idx + 2] = 255 if nb > 255 else nb
            out_bytes[out_idx + 3] = pa
        out_idx += 4

    return Image.frombytes("RGBA", (w, h), bytes(out_bytes))


def normalize_image(
    source_path: Path,
    dest_path: Path,
    target_size: tuple[int, int],
    alpha_mode: str,
    pivot: str = "bottom_center",
    margin: int = 16,
    is_vfx: bool = False,
) -> None:
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    target_w, target_h = target_size

    with Image.open(source_path) as opened:
        img = opened.copy()

    if alpha_mode in ("transparent", "cutout"):
        if is_vfx:
            rgba = convert_black_bg_to_alpha(img)
        else:
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
    rule = (
        "ground_contact"
        if collision_type == "ground_contact"
        else (
            "core_ring"
            if collision_type == "core_ring"
            else ("full_body" if collision_type in ("solid", "full_body") else "none")
        )
    )
    blocks = derive.occluder_mask(rule, cov, gate)
    if interactive_verb in ("doorway", "portal", "pass_under", "gate"):
        blocks = derive.apply_authored_open(blocks, "bottom_centre")

    walk_surface = derive.walk_surface_mask(cov, rule, collision_type == "walk_surface")
    block_cell_count = sum(sum(1 for cell in line if cell) for line in blocks)
    anchor_cell = [cols // 2, rows - 1] if pivot == "bottom_center" else [cols // 2, rows // 2]

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
        box_center + ((run[0] + run[1]) / 2 - canvas_w / 2) * ref_scale if run else box_center
    )

    by_scale = {}
    floor_cells = 1 if rule == "ground_contact" else 0
    for s in [0.85, 1.0, 1.15, 1.35, 1.6]:
        if rule in ("full_body", "core_ring"):
            by_scale[str(s)] = [0, 0, fp_cols - 1, fp_rows - 1] if block_cell_count > 0 else None
        else:
            center = box_center + (contact_center - box_center) * s
            r = subcell.rect_at_scale(
                contact_ref, s, fp_cols, fp_rows, min_cells=floor_cells, center_px=center
            )
            by_scale[str(s)] = r

    rect = by_scale.get("1.0")
    rect_px = (
        None
        if rect is None
        else [
            rect[0] * cell_px,
            rect[1] * cell_px,
            (rect[2] + 1) * cell_px,
            (rect[3] + 1) * cell_px,
        ]
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


def get_asset_paths(
    domain: str, sub_domain: str, asset_slug: str, variant_slug: str
) -> dict[str, Path]:
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
    "laboratory glassware, modern objects, anime mech, sci-fi wires, "
    "monochrome cyan wash, heavy cyan tint, dull teal filter, blue-green cast, unnatural cyan glow"
)


def build_game_ready_prompt(asset: dict, var: dict) -> tuple[str, str]:
    """
    Construct game-ready positive prompt and negative prompt based on the 7 Archetypes
    defined in Section 8 of README.md, strictly preventing diorama, chimera, and cultural drift.
    """
    asset_class = (asset.get("asset_class") or asset.get("type") or "prop_workstation").lower()

    raw_asset_name = asset.get("name") or asset.get("id", "cultivation_asset")
    # Retain full subject identity for multi-part titles (e.g. "Crimson Flame Lingzhi - Mature Flourishing Specimen")
    if " - " in raw_asset_name:
        parts = raw_asset_name.split(" - ")
        asset_name = f"{parts[0].strip()} ({parts[1].strip()})" if len(parts) >= 2 else raw_asset_name.strip()
    else:
        asset_name = raw_asset_name

    material = asset.get("material", "carved wood and polished bronze")
    var_mod = var.get("prompt_modifier") or var.get("prompt") or ""
    # Strip any negation words in var_mod to prevent FLUX T5 positive-trigger inversion
    var_mod = (
        var_mod.replace("zero front entrance steps", "solid continuous rear wall")
        .replace("zero entrance steps", "solid continuous rear wall")
        .replace("zero ground shadow", "")
        .replace("zero pedestal", "")
        .strip(" ,")
    )
    var_slug = var.get("variant_slug", "")

    # Adaptive background contrast keying: prevent white/snow assets from being clipped by RMBG-2.0
    is_pale = (
        "winter" in var_slug
        or "snow" in var_slug
        or any(
            w in asset_name.lower()
            for w in ("white", "crane", "snow", "jade", "frost", "silver", "pale")
        )
    )
    adaptive_bg = (
        "solid neutral contrast grey background (#D0D0D0)"
        if is_pale
        else "solid pure white background (#FFFFFF)"
    )

    # Archetype 1: Items, Handheld Tools, Weapons & Pickups
    if any(k in asset_class for k in ("item", "tool", "weapon", "talisman", "consumable", "icon")):
        # Sanitize tool materials if mismatched by heuristic
        low_name = asset_name.lower()
        if any(w in low_name for w in ("shovel", "spade", "trowel")):
            if any(b in material.lower() for b in ("herb", "stalk", "leaf", "dew", "soil", "dirt")):
                material = "carved translucent mutton-fat nephrite jade blade, polished brass ferrule socket, dark rosewood handle"
        elif any(w in low_name for w in ("pick", "pickaxe", "mining")):
            if any(b in material.lower() for b in ("herb", "stalk", "leaf", "dew", "soil", "dirt")):
                material = "forged heavy cold iron pick head with chisel point, reinforced bronze bands, aged hardwood shaft"
        elif any(w in low_name for w in ("sickle", "scythe", "harvester")):
            if any(b in material.lower() for b in ("herb", "stalk", "leaf", "dew", "soil", "dirt")):
                material = "forged cold iron crescent blade with sharp curved edge, polished dark rosewood handle wrapped in cord"

        is_ground_drop = "ground" in var_slug or "drop" in var_slug or "flat" in var_slug
        shadow_clause = (
            "subtle micro contact shadow directly underneath only, resting flat,"
            if is_ground_drop
            else "zero ground shadow, zero pedestal,"
        )
        item_neg = (
            "diorama, miniature scene, floating island, dirt slab, grass pedestal, room, building, landscape, "
            f"trees, field, human hands, fingers, holding, multiple items, collection, frame, UI, watermark, {ANTI_DRIFT_CLAUSE}"
            if is_ground_drop
            else (
                "diorama, miniature scene, floating island, dirt slab, grass pedestal, ground plane, "
                "floor, surface, shadow on ground, building, house, cottage, farm, fence, landscape, "
                "trees, field, human hands, fingers, holding, multiple items, collection, collage, border, "
                f"frame, UI, watermark, blurry edges, microscopic high-frequency noise, decorative clouds, cloud swirls, vapor wisps, {ANTI_DRIFT_CLAUSE}"
            )
        )
        pos = (
            f"Single isolated 2D game asset of {asset_name.lower()}, {material}, {var_mod}, "
            "Ancient Chinese Xianxia cultivation mortal realm aesthetic, double-edged Chinese straight sword or authentic Daoist implement, "
            "bold readable silhouette, clean grouped value planes, chunky stylized proportions for 2D icon clarity, "
            f"fine dark #1C1C1E ink contours, gouache hand-painted, {shadow_clause} centered on {adaptive_bg}."
        )
        return pos, item_neg

    # Archetype 3b: Natural Geological Landmarks & Mountain Spires
    if any(
        k in asset_class for k in ("landmark", "mountain", "peak", "cliff", "spire", "crag_pillar")
    ):
        is_rear = any(k in var_slug for k in ("rear", "back", "north"))
        is_west = any(k in var_slug for k in ("west", "left"))
        is_east = any(k in var_slug for k in ("east", "right"))

        if is_rear:
            landmark_pos = (
                "steep high-angle top-down RPG map perspective looking down from above, "
                "sheer northern crag face and upper summit plateau surface fully visible from above, "
                "weathered northern rock terraces descending away from summit,"
            )
        elif is_west:
            landmark_pos = (
                "steep high-angle top-down RPG map perspective looking down from above, "
                "landmark rotated 90 degrees with elongated rock spine running North-South, "
                "western stepped cliff strata and summit crest visible from overhead,"
            )
        elif is_east:
            landmark_pos = (
                "steep high-angle top-down RPG map perspective looking down from above, "
                "landmark rotated 90 degrees with elongated rock spine running North-South, "
                "eastern stepped cliff strata and summit crest visible from overhead,"
            )
        else:
            landmark_pos = (
                "steep high-angle top-down RPG map perspective looking down from above, "
                "summit crest and upper rock terraces fully visible from above, "
                "stepped crag shelves and gnarled cliff pine seen from overhead,"
            )

        pos = (
            f"Single isolated 2D top-down world-map natural landmark sprite of {asset_name.lower()}, {material}, {var_mod}, "
            f"Ancient Chinese Xianxia landscape style, {landmark_pos} "
            "sheer vertical natural rock base ending abruptly in clean rock perimeter resting directly on ground, "
            "crisp isolated rock contour base without turf or soil skirts, micro contact shadow directly under stone base only, "
            "gouache hand-painted with dark #1C1C1E ink contours, isolated on solid plain white background."
        )
        neg = (
            "diorama, miniature base, floating rock island, sky, clouds, horizon, distant mountains, landscape vista, "
            "eye-level view, side-view portrait, flat elevation, landscape painting, "
            "grass patch, turf, lawn, meadow, green ground plane, soil patch, path, cobblestone, road, "
            "grass rim, turf skirt, dirt mound base, green turf, moss ring around base, diorama base plate, dirt path in front, "
            f"frame, border, UI, watermark, human figures, birds in sky, {ANTI_DRIFT_CLAUSE}"
        )
        return pos, neg

    # Archetype 6: Ground Terrains, Walk Surfaces & Path Decals
    dom = asset.get("domain", "")
    is_ground = any(
        k in asset_class for k in ("terrain_tile", "ground_tile", "walk_surface", "surface_decal")
    ) or (
        "terrain" in dom
        and not any(
            k in asset_class
            for k in (
                "landmark",
                "mountain",
                "peak",
                "cliff",
                "spire",
                "crag_pillar",
                "boulder",
                "prop",
            )
        )
    )
    if is_ground:
        # Determine actual ground soil/rock material from category or raw_name
        cat_id = asset.get("category_id") or asset.get("sub_domain") or ""
        # Strip triggering tokens like 'tile' and 'flat surface tile' that cause paver/grid hallucinations
        clean_name = (
            raw_asset_name.lower()
            .replace("pristine flat surface tile", "")
            .replace("flat surface tile", "")
            .replace("surface tile", "")
            .replace("tile", "")
            .replace("crags", "soil")
            .replace("peaks", "limestone floor")
            .strip(" -_")
        )
        if not clean_name or len(clean_name) < 3:
            clean_name = cat_id.replace("_", " ").strip()
            for pfx in ("ter 01 ", "ter 02 ", "ter 03 ", "ter 04 ", "ter 05 ", "ter 06 ", "ter 07 ", "ter 08 "):
                clean_name = clean_name.replace(pfx, "")

        pos = (
            f"Seamless 2D ground texture map of {clean_name}, {material}, {var_mod}, "
            "painterly anime gouache, continuous uniform natural earth texture, monolithic unbroken flat ground plane, "
            "macro top-down perpendicular 90-degree satellite overhead view looking straight down at soil surface, "
            "edge-to-edge seamless soil texture filling 100% of canvas."
        )
        neg = (
            "tiles, pavers, flagstones, stone slabs, paving, grid lines, tile seams, grout, cracks between tiles, subdivided stones, "
            "stepping stones, stone blocks, rock slabs, river stones, pebbles in a line, furrows, trenches, channels, walking path, stepping path, "
            "crater, arena, depression, circular hollow, ring of cliffs, surrounding rocks, border cliffs, perimeter rocks, "
            "border, frame, circular frame, ring of rocks, corner bushes, perimeter foliage, vignette, diorama, "
            "cliffs, canyon, pillars, columns, rock towers, elevation, horizon, sky, clouds, landscape, "
            "vista, distant view, perspective, 3D scene, chasm, ravine, valley, walls, UI, watermark, props, objects, buildings, trees"
        )
        return pos, neg

    # Archetype 7: Atmospheric VFX & Overlay Particle Sheets (Bypasses RemBG in post-process)
    if any(k in asset_class for k in ("vfx", "particle", "overlay", "phenomena")):
        pos = (
            f"2D game particle VFX sprite of {asset_name.lower()}, {var_mod}, "
            "luminous spiritual motes, soft radiant glow edges, glowing magical energy, "
            "isolated on solid pure black background (#000000) for additive alpha blending."
        )
        neg = (
            "white background, light background, grey background, opaque solid shapes, opaque borders, "
            "ground, floor, landscape, characters, buildings, terrain, solid geometry, ui frames, decorative frames"
        )
        return pos, neg

    # Archetype 4: Flora, Spirit Herbs & Sacred Trees
    if any(k in asset_class for k in ("flora", "herb", "tree", "plant")):
        name_lower = asset_name.lower()
        mat_lower = material.lower()
        combined_text = f"{name_lower} {mat_lower}"

        # Dynamic morphology and color cues tailored to plant family
        if any(w in combined_text for w in ("lingzhi", "mushroom", "fungus", "fungi", "spore", "toadstool")):
            foliage_spec = (
                "woody bracket fungus, broad lacquered mushroom cap, spore gills and fungal stalk viewed foreshortened from overhead, "
                "vermilion cinnabar lacquer cap or earthy spore ochre tones,"
            )
        elif any(w in combined_text for w in ("lotus", "lily", "water_plant", "pond")):
            foliage_spec = (
                "broad rounded floating lotus leaf pads, delicate lotus blossom petals, fragrant aquatic floral crown viewed from overhead,"
            )
        elif any(w in combined_text for w in ("ginseng", "root", "tuber", "rhizome")):
            foliage_spec = (
                "tuberous spiritual root rhizome, medicinal root crown, branching fibrous rootlets and small herbal sprig viewed from overhead,"
            )
        elif any(w in combined_text for w in ("osmanthus", "peach", "blossom", "orchid", "wisteria", "flower")):
            foliage_spec = (
                "flowering canopy, fragrant blossom clusters, delicate floral petals and leafy twig sprigs viewed foreshortened from overhead,"
            )
        elif any(w in combined_text for w in ("vine", "creeper", "bramble", "briar", "thorn")):
            foliage_spec = (
                "twisting woody creeper vines, prickly thorny brambles, clinging tangled stems and curled tendrils viewed from overhead,"
            )
        elif any(w in combined_text for w in ("bamboo", "culm", "cane")):
            foliage_spec = (
                "segmented bamboo culms, slender bamboo foliage and nodes viewed foreshortened from overhead,"
            )
        elif any(w in combined_text for w in ("rice", "grain", "crop", "grass", "reed", "fern", "moss")):
            foliage_spec = (
                "slender vegetative stems, feathery foliage fronds and textured ground vegetation viewed foreshortened from overhead,"
            )
        elif any(w in combined_text for w in ("pine", "cypress", "conifer")):
            foliage_spec = (
                "gnarled evergreen needle canopy, weathered resinous bark branches, spreading evergreen crown viewed foreshortened from overhead,"
            )
        elif any(w in combined_text for w in ("willow", "poplar", "tree", "wood", "grove", "bush")):
            foliage_spec = (
                "branching hardwood canopy, weeping leafy boughs and textured tree crown viewed foreshortened from overhead,"
            )
        else:
            foliage_spec = (
                "botanical canopy, branching herbal crown and leafy foliage viewed foreshortened from overhead, spread outward on ground plane,"
            )

        pos = (
            f"Single isolated 2D top-down RPG map sprite of {asset_name.lower()}, {material}, {var_mod}, "
            "Ancient Chinese Xianxia herbal aesthetic, steep high-angle 3/4 top-down perspective looking down from above (65-75 degree angle), "
            f"{foliage_spec} "
            "gouache hand-painted with dark #1C1C1E pine-soot ink contours, flat grounded root base, short attached micro contact shadow only, "
            "isolated on solid plain white background."
        )
        neg = (
            "eye-level view, flat front elevation, horizontal side profile, botanical plate, specimen drawing, side-scroller view, straight-on view, "
            "diorama, plant pot, planter, flowerbed border, dirt mound base, turf chunk, forest background, "
            "surrounding grass, garden scene, landscape, mountains, sky, multiple clumps, human hands, shears, "
            f"tall upright crystals, decorative swirls, floating cloud swirls, {ANTI_DRIFT_CLAUSE}"
        )
        return pos, neg

    # Archetype 5: Fauna, Spirit Beasts, Demons & Denizens
    if any(k in asset_class for k in ("fauna", "beast", "creature", "monster", "npc")):
        is_carcass = "dead" in var_slug or "carcass" in var_slug
        contact_spec = (
            "contact shadow directly under body only"
            if is_carcass
            else "ground foot contact shadow only"
        )
        carcass_neg = ", standing upright, flying, walking" if is_carcass else ""
        pos = (
            f"Single isolated 2D top-down RPG game creature sprite of {asset_name.lower()}, {material}, {var_mod}, "
            "Shan Hai Jing ancient Chinese mythological aesthetic, steep high-angle 3/4 top-down perspective looking down from above (65-75 degree angle), "
            f"back, wings, shoulders and creature body viewed foreshortened from overhead, gouache painted with dark ink contours, "
            f"{contact_spec}, zero directional drop shadow, isolated on {adaptive_bg}."
        )
        neg = (
            "flat side view, horizontal profile, eye-level portrait, side-scroller view, straight-on view, "
            "diorama, cage, stable, pen, pasture, fence, saddle, reins, rider, trainer, human hands, "
            "background scenery, landscape, grass chunk, multiple animals, herd, UI healthbar, floating icons, "
            f"perch, tree branch, rock pedestal, stone platform, diorama base, four legs on bird, quadruped bird{carcass_neg}, {ANTI_DRIFT_CLAUSE}"
        )
        return pos, neg

    # Archetype 3a: Architecture, Sect Facilities, Temples & Dwellings
    if any(
        k in asset_class
        for k in (
            "structure",
            "building",
            "architecture",
            "gateway",
            "gate",
            "pagoda",
            "pavilion",
            "tower",
            "hall",
            "shrine",
            "temple",
            "cottage",
            "house",
            "dongfu",
            "dwelling",
        )
    ):
        is_rear = any(k in var_slug for k in ("rear", "back", "north"))
        is_west = any(k in var_slug for k in ("west", "left"))
        is_east = any(k in var_slug for k in ("east", "right"))

        # Architectural style discrimination: Monumental/Formal vs Vernacular/Rustic
        is_rustic = any(
            k in asset_class or k in asset_name.lower() or k in material.lower()
            for k in ("cottage", "hut", "dwelling", "shack", "thatch", "straw", "bamboo", "rustic")
        )

        if is_rustic:
            roof_spec = (
                "authentic uniform golden thatched straw roof surface dominant and fully visible overhead (70%-80% of height), "
                "split bamboo ridge rafters and thick straw eaves seen from above,"
            )
            gable_spec = "high-angle triangular thatched timber gable end"
            material_neg = "ceramic tiles, glazed tiles, blue roof tiles, dark roof tiles, terracotta tiles, dougong brackets, imperial palace, temple hall, "
        else:
            roof_spec = "broad glazed ceramic roof tiles and curved dougong eaves dominant and fully visible overhead (70%-80% of height), "
            gable_spec = "high-angle triangular dougong timber gable end"
            material_neg = "thatched straw roof, straw hut, hay, rustic shack, "

        if is_rear:
            persp_pos = (
                "steep high-angle top-down RPG map perspective looking down from above, "
                f"roof ridge running East-West with broad northern rear roof surface {roof_spec} "
                "solid unbroken timber lattice back wall and stone foundation foreshortened beneath eaves at bottom, "
                "completely windowless and doorless flat rear wall flush on level ground, clean horizontal baseline, back exterior view,"
            )
            dir_neg = (
                "front entrance door, open doorway, entrance steps, stairs, portal, door plaque, "
                "front veranda, open portal, descending stairs, central doorway, porch, arched entryway, "
            )
        elif is_west:
            persp_pos = (
                "steep high-angle top-down RPG map perspective looking down from above, "
                f"building rotated 90 degrees with roof ridge running North-South, "
                f"western roof slope and {gable_spec} dominant and fully visible overhead, "
                "western side wall foreshortened beneath eaves at bottom, side window or railing,"
            )
            dir_neg = (
                "symmetrical front entrance facade, central double doors at bottom, front steps at bottom-center, "
                "annexed side structure, attached side pavilion, extra side gate, secondary structure, side tower, courtyard wing, "
            )
        elif is_east:
            persp_pos = (
                "steep high-angle top-down RPG map perspective looking down from above, "
                f"building rotated 90 degrees with roof ridge running North-South, "
                f"eastern roof slope and {gable_spec} dominant and fully visible overhead, "
                "eastern side wall foreshortened beneath eaves at bottom, side window or railing,"
            )
            dir_neg = (
                "symmetrical front entrance facade, central double doors at bottom, front steps at bottom-center, "
                "annexed side structure, attached side pavilion, extra side gate, secondary structure, side tower, courtyard wing, "
            )
        else:
            # Default / front South facade
            persp_pos = (
                "steep high-angle top-down RPG map perspective looking down from above, "
                f"roof ridge running East-West with broad southern roof surface {roof_spec} "
                "foreshortened front walls and entrance visible beneath eaves at bottom-center, stone courtyard steps descending at bottom,"
            )
            dir_neg = ""

        pos = (
            f"Single isolated 2D top-down world-map building sprite of {asset_name.lower()}, {material}, {var_mod}, "
            f"Ancient Chinese Tang-Song Xianxia architectural style, {persp_pos} "
            "gouache hand-painted with dark #1C1C1E ink contours, flat grounded baseline, short attached micro contact shadow only, "
            "isolated on solid plain white background."
        )
        neg = (
            f"{material_neg}{dir_neg}clouds on roof, miniature mountain on roof, mountain peak on roof, puff of cloud, smoke on roof, cropped at top edge, canvas boundary cut, "
            "diorama, miniature landscape, floating rock island, cutaway foundation, courtyard boundary walls, "
            "garden lawn, surrounding trees, forest, mountains, sky, clouds, horizon, roads, cobblestone path, "
            "eye-level view, flat front elevation drawing, flat side view profile, side-scroller, "
            f"human figures, isometric box frame, cutout diorama base, directional drop shadow, {ANTI_DRIFT_CLAUSE}"
        )
        return pos, neg

    # Archetype 2b: Containers, Chests & Storage Furnishings
    is_container_or_furnishing = any(
        k in asset_class or k in asset_name.lower()
        for k in (
            "container",
            "chest",
            "casket",
            "box",
            "cabinet",
            "shelf",
            "wardrobe",
            "table",
            "chair",
            "desk",
            "seat",
        )
    )
    if is_container_or_furnishing:
        pos = (
            f"Single isolated 2D RPG game prop of {asset_name.lower()}, {material}, {var_mod}, "
            "Ancient Chinese Xianxia cultivation aesthetic, authentic Chinese traditional carved rosewood joinery or Daoist storage implement, "
            "gouache hand-painted with crisp dark #1C1C1E ink contours, flat zero-cast-shadow baseline, "
            "micro ambient contact occlusion directly under base only, isolated on solid plain white background."
        )
        neg = (
            "diorama, miniature base, floating island, dirt chunk, grass slab, square tile pedestal, floor plane, "
            "room interior, walls, ceiling, surrounding furniture, background building, trees, outdoor scenery, "
            f"multiple objects, human operator, worker, cauldron, furnace, ding, collage, frame, directional cast shadow, {ANTI_DRIFT_CLAUSE}"
        )
        return pos, neg

    # Default / Archetype 2a: Workstations, Heavy Apparatus & Functional Props
    pos = (
        f"Single isolated 2D RPG game prop of {asset_name.lower()}, {material}, {var_mod}, "
        "Ancient Chinese Xianxia cultivation aesthetic, authentic Chinese tripod ding cauldron or traditional workshop implement, "
        "gouache hand-painted with crisp dark #1C1C1E ink contours, flat zero-cast-shadow baseline, "
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
    force: bool = False,
) -> int:
    if not PACK_PATH.is_file():
        print(f"Error: manifest not found at {PACK_PATH}", file=sys.stderr)
        return 1

    with open(PACK_PATH, encoding="utf-8") as f:
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
        if (
            asset_filter
            and asset_slug != asset_filter
            and asset.get("id") != asset_filter
            and asset_filter not in asset_slug
        ):
            continue

        variants = asset.get("variants", [])
        if not variants:
            # Single default variant if not explicitly decomposed
            variants = [
                {
                    "variant_slug": "default",
                    "name": asset.get("name", asset_slug),
                    "prompt_modifier": "",
                    "status": asset.get("status", "planned"),
                }
            ]

        for var in variants:
            var_slug = var.get("variant_slug", "default")
            if variant_filter and var_slug != variant_filter:
                continue

            var_status = var.get("status") or asset.get("status", "planned")
            if var_status == "planned" or force:
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
        if not force and paths["runtime_png"].is_file() and paths["variant_json"].is_file():
            print(
                f"[{idx}/{len(work_items)}] SKIPPED (already installed): {asset_slug} -> {var_slug}"
            )
            skipped_count += 1
            var["status"] = "generated"
            var["path"] = (
                f"res://assets/packs/{PACK_ID}/runtime/{dom}/{sub_dom}/{asset_slug}/{var_slug}.png"
            )
            continue

        print(f"\n[{idx}/{len(work_items)}] GENERATING: {dom}/{sub_dom}/{asset_slug} [{var_slug}]")
        t_start = time.time()

        args = ComfyArgs()
        pos_prompt, neg_prompt = build_game_ready_prompt(asset, var)
        args.prompt = pos_prompt
        args.negative = neg_prompt
        if var.get("seed"):
            args.seed = int(var["seed"])
        else:
            import hashlib
            seed_hash = int(hashlib.md5(f"{asset_slug}_{var_slug}".encode("utf-8")).hexdigest()[:6], 16)
            args.seed = 10000 + (seed_hash % 20000)

        if force:
            for old_tmp in temp_gen_dir.glob(f"*{asset_slug}*{var_slug}*"):
                old_tmp.unlink(missing_ok=True)

        generated_source: Path | None = None
        for attempt in range(3):
            try:
                gen_dict = {
                    "id": f"{asset_id}.{var_slug}",
                    "name": f"{asset.get('name')} ({var_slug})",
                    "category": sub_dom,
                    "prompt": args.prompt,
                    "type": asset.get("type", "prop"),
                    "alpha": asset.get("alpha", "transparent"),
                    "pivot": asset.get("pivot", "bottom_center"),
                    "environment_name": asset.get("environment_name", "Mortal World"),
                    "world_tier": asset.get("world_tier", "Low Cultivation"),
                    "environment_theme": asset.get(
                        "environment_theme",
                        "2D Orthographic top-down, gouache hand-painted, ink contours",
                    ),
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
                print(f"  [Attempt {attempt + 1}] ToolError: {te}")
                time.sleep(2)
            except Exception as e:
                print(f"  [Attempt {attempt + 1}] Error: {e}")
                time.sleep(3)

        if not generated_source or not generated_source.is_file():
            print(f"  FAILED to generate variant {asset_slug} -> {var_slug}")
            failed_count += 1
            continue

        # 1. Archive raw original
        if not paths["orig_raw"].is_file():
            shutil.copy2(generated_source, paths["orig_raw"])

        # 2. Normalize runtime PNG
        asset_class = (asset.get("asset_class") or asset.get("type") or "").lower()
        is_vfx = any(k in asset_class for k in ("vfx", "particle", "overlay")) or "vfx" in dom
        normalize_image(
            generated_source,
            paths["runtime_png"],
            (canvas_px[0], canvas_px[1]),
            alpha_mode,
            pivot=pivot,
            margin=16,
            is_vfx=is_vfx,
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
        rel_runtime_path = (
            f"res://assets/packs/{PACK_ID}/runtime/{dom}/{sub_dom}/{asset_slug}/{var_slug}.png"
        )
        var.update(
            {
                "status": "generated",
                "path": rel_runtime_path,
                "generated_on": time.strftime("%Y-%m-%d"),
                "matrix_data": matrix_data,
            }
        )

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
        paths["variant_json"].write_text(
            json.dumps(var_payload, indent=2, ensure_ascii=False), encoding="utf-8"
        )

        # 6. Update master asset.json
        paths["asset_json"].write_text(
            json.dumps(asset, indent=2, ensure_ascii=False), encoding="utf-8"
        )

        elapsed = time.time() - t_start
        print(f"  -> SUCCESS ({elapsed:.1f}s): {rel_runtime_path}")
        success_count += 1

        if success_count % 5 == 0:
            save_manifest(pack)
            print(f"  [Checkpoint] Saved manifest ({success_count} variants processed).")

    save_manifest(pack)
    print(f"\nManifest saved to {PACK_PATH}")
    print(
        f"Finished pipeline: {success_count} succeeded, {skipped_count} skipped, {failed_count} failed in {time.time() - t0_all:.1f}s"
    )

    # Godot headless editor import
    if not skip_godot_import and success_count > 0:
        print("\nInvoking Godot headless editor to import new textures...")
        res = run_godot(
            ["--headless", "--editor", "--path", str(GAME_DIR), "--import", "--quit"],
            capture=True,
            tag="low-cultivation-import",
        )
        print(f"Godot import process finished with returncode {res.returncode}")

    return 0 if failed_count == 0 else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Living Map Generation Pipeline for Ancient China Low Cultivation Pack"
    )
    parser.add_argument("--domain", type=str, default=None, help="Filter by domain ID")
    parser.add_argument("--sub-domain", type=str, default=None, help="Filter by sub-domain ID")
    parser.add_argument("--asset", type=str, default=None, help="Filter by asset slug or ID")
    parser.add_argument("--variant", type=str, default=None, help="Filter by variant slug")
    parser.add_argument(
        "--limit", type=int, default=None, help="Limit number of variants to process"
    )
    parser.add_argument(
        "--skip-import", action="store_true", default=False, help="Skip Godot headless import"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        default=False,
        help="Show planned file paths without generating",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        default=False,
        help="Force regenerate targets even if already generated",
    )
    args = parser.parse_args()

    sys.exit(
        run_pipeline(
            domain_filter=args.domain,
            sub_domain_filter=args.sub_domain,
            asset_filter=args.asset,
            variant_filter=args.variant,
            limit=args.limit,
            skip_godot_import=args.skip_import,
            dry_run=args.dry_run,
            force=args.force,
        )
    )
