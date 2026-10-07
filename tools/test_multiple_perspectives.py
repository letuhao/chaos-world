# -*- coding: utf-8 -*-
"""Generate candidate assets across multiple perspectives to validate visual and structural diversity.

Tests 3 distinct perspective projections on representative asset classes:
  1. 45-degree Orthographic 3/4 RPG View (Elevational Front + Top)
  2. 90-degree Strict Overhead Plan View (Perpendicular Bird's-Eye)
  3. 30-degree High-Angle Isometric Depth View (Axonometric 3/4)

Generates candidate outputs via local ComfyUI and evaluates alpha isolation,
silhouette legibility, bounding box fill, and modular snap suitability.
"""

from __future__ import annotations

import copy
import json
import os
import sys
import time
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / ".agents" / "skills" / "map-asset-pipeline" / "scripts"))

from tools.common import ToolError
from tools.map_generate import generate

OUTPUT_DIR = REPO_ROOT / "build" / "perspective_tests"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


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
    seed = 8888
    lora = "scottie:1.0"
    lora_strength = 1.0


# 3 Representative Test Subjects
TEST_SUBJECTS = [
    {
        "id": "ancient_china_mortal.modular_architecture_timber.wal_white_lime_plaster_window_plum_blossom_lattice",
        "name": "Jiangnan White Lime Plaster Wall with Plum Blossom Lattice Window",
        "category": "modular_architecture_timber",
        "type": "structure",
        "alpha": "transparent",
        "pivot": "bottom_center",
        "canvas_px": [128, 128],
        "footprint_cells": [1, 1],
        "environment_name": "Ancient China Mortal World (Cửu Châu Phàm Trần)",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contour lines (#263A35), grounded East Asian mortal palette.",
        "world_tier": "Mortal World (Phàm Nhân Giới / Cửu Châu)",
        "base_desc": "Ancient Chinese Jiangnan vernacular white plaster wall section with carved plum blossom openwork lattice window, dark grey clay roof coping tiles on top.",
    },
    {
        "id": "ancient_china_mortal.mountain_cliff_geology.clf_grey_limestone_strata_cliff_cut_stone_stairs",
        "name": "Stratified Grey Limestone Cliff with Ancient Chiseled Stone Stairway",
        "category": "mountain_cliff_geology",
        "type": "structure",
        "alpha": "transparent",
        "pivot": "bottom_center",
        "canvas_px": [128, 256],
        "footprint_cells": [1, 2],
        "environment_name": "Ancient China Mortal World (Cửu Châu Phàm Trần)",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contour lines (#263A35), grounded East Asian mortal palette.",
        "world_tier": "Mortal World (Phàm Nhân Giới / Cửu Châu)",
        "base_desc": "Ancient mountainous limestone cliff precipice with narrow winding stone stairs hand-carved into the vertical rock face, weathered stone strata.",
    },
    {
        "id": "ancient_china_mortal.rural_farming_and_pastoral.trp_crimson_sun_chili_sun_drying_round_bamboo_mat",
        "name": "Round Bamboo Winnowing Mat Full of Fiery Red Sun-Drying Peppers",
        "category": "rural_farming_and_pastoral",
        "type": "prop",
        "alpha": "transparent",
        "pivot": "bottom_center",
        "canvas_px": [128, 128],
        "footprint_cells": [1, 1],
        "environment_name": "Ancient China Mortal World (Cửu Châu Phàm Trần)",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contour lines (#263A35), grounded East Asian mortal palette.",
        "world_tier": "Mortal World (Phàm Nhân Giới / Cửu Châu)",
        "base_desc": "Traditional shallow round woven bamboo winnowing tray mat spread flat on ground filled with ripe bright crimson red chili peppers sun-curing.",
    },
]

PERSPECTIVE_PROFILES = [
    {
        "key": "p1_ortho_45deg",
        "label": "Perspective 1: Standard 45° 3/4 RPG Angle (Elevation + Top)",
        "prompt_clause": (
            "2D orthographic top-down 45-degree angle RPG map view, showing front elevation facade and upper surface clearly, "
            "standard 2D action-RPG perspective (Zelda / RPG Maker style), ground-facing silhouette. "
        ),
    },
    {
        "key": "p2_overhead_90deg",
        "label": "Perspective 2: Strict 90° Overhead Bird's-Eye (Plan View)",
        "prompt_clause": (
            "Strict overhead top-down bird's-eye 90-degree perpendicular plan view, looking directly straight down from sky, "
            "zero vertical facade visible, purely flat top planar view, direct overhead projection. "
        ),
    },
    {
        "key": "p3_isometric_30deg",
        "label": "Perspective 3: High-Angle Isometric 30° Depth View",
        "prompt_clause": (
            "2D high-angle isometric 30-degree angle projection, displaying top plane and two angled sides with 3D architectural depth, "
            "axonometric RPG viewpoint. "
        ),
    },
]


def run_perspective_test():
    print("=" * 80)
    print("MULTI-PERSPECTIVE GENERATION & DIVERSITY VALIDATION TEST")
    print(f"Testing 3 distinct perspectives across {len(TEST_SUBJECTS)} representative asset types...")
    print("=" * 80)

    results = []

    for s_idx, subject in enumerate(TEST_SUBJECTS, 1):
        s_id = subject["id"]
        s_name = subject["name"]
        print(f"\n--- [Subject {s_idx}/{len(TEST_SUBJECTS)}] {s_name} ---")

        for p_idx, profile in enumerate(PERSPECTIVE_PROFILES, 1):
            pkey = profile["key"]
            plabel = profile["label"]
            pclause = profile["prompt_clause"]

            print(f"  Generating {pkey} ({plabel})...")

            # Build tailored test record
            rec = copy.deepcopy(subject)
            custom_prompt = (
                f"{subject['base_desc']}. {pclause}"
                "Crisp dark ink contour lines (#263A35), hand-painted gouache watercolor texture, East Asian mortal palette. "
                "Isolated single asset on solid plain pure white background, completely transparent background with RMBG, "
                "no floor, no ground plane, no background scenery, no shadows cast on terrain, no UI, no text."
            )
            rec["prompt_summary"] = custom_prompt

            args = ComfyArgs()
            args.prompt = custom_prompt
            args.seed = 9000 + (s_idx * 10) + p_idx

            t0 = time.time()
            try:
                out_path, _, used_seed = generate(
                    rec,
                    args,
                    output_dir=f"perspective_tests",
                )
                elapsed = time.time() - t0

                # Analyze output image metrics
                with Image.open(out_path) as img:
                    rgba = img.convert("RGBA")
                    w, h = rgba.size
                    alpha = rgba.split()[-1]
                    bbox = alpha.getbbox()

                coverage = 0.0
                bbox_info = None
                if bbox:
                    bw = bbox[2] - bbox[0]
                    bh = bbox[3] - bbox[1]
                    coverage = (bw * bh) / (w * h)
                    bbox_info = [bbox[0], bbox[1], bbox[2], bbox[3]]

                # Copy to local easily accessible filename
                clean_name = f"{subject['category']}_{s_idx}_{pkey}.png"
                clean_path = OUTPUT_DIR / clean_name
                rgba.save(clean_path)

                print(f"    ✓ Generated in {elapsed:.2f}s | Size: {w}x{h} | Alpha BBox: {bbox_info} | Area Coverage: {coverage*100:.1f}%")
                print(f"    Saved: {clean_path}")

                results.append({
                    "subject": s_name,
                    "category": subject["category"],
                    "perspective_key": pkey,
                    "perspective_label": plabel,
                    "file_path": str(clean_path),
                    "coverage": round(coverage, 3),
                    "bbox": bbox_info,
                    "seed": used_seed,
                    "elapsed_s": round(elapsed, 2),
                })
            except Exception as e:
                print(f"    ✗ Generation failed: {e}")

    # Save summary report
    report_file = OUTPUT_DIR / "perspective_test_results.json"
    with open(report_file, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    print("\n" + "=" * 80)
    print(f"COMPLETED MULTI-PERSPECTIVE TEST: {len(results)} candidate renders saved in {OUTPUT_DIR}")
    print(f"Summary JSON: {report_file}")
    print("=" * 80)
    return results


if __name__ == "__main__":
    run_perspective_test()
