"""Batch generator for Yin-Jian (Netherworld) asset pack.

Iterates over ungenerated assets in game/assets/packs/yin-jian/yin_jian_pack.json,
submits requests to local ComfyUI (Krea2 default with RMBG-2.0),
validates candidate quality (up to 3 candidates per asset),
normalizes runtime PNGs with padding and pivots,
and updates yin_jian_pack.json incrementally.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import sys
import time
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_PATH = REPO_ROOT / "game" / "assets" / "packs" / "yin-jian" / "yin_jian_pack.json"
GAME_ROOT = REPO_ROOT / "game"

sys.path.insert(0, str(REPO_ROOT))
from tools.map_generate import generate, load_index_record, DEFAULT_CHECKPOINT, DEFAULT_REMBG_MODEL


def evaluate_candidate(image_path: Path, alpha_mode: str) -> tuple[bool, str]:
    """Inspect candidate image pixels to ensure quality and absence of noise/ground."""
    if not image_path.is_file():
        return False, "File does not exist"

    try:
        with Image.open(image_path) as opened:
            img = opened.convert("RGBA" if alpha_mode == "transparent" else "RGB")
    except Exception as exc:
        return False, f"Corrupted image: {exc}"

    if alpha_mode == "transparent":
        alpha = img.split()[-1]
        w, h = img.size
        his = alpha.histogram()
        trans_ratio = sum(his[:10]) / (w * h)
        if trans_ratio < 0.20:
            return False, f"Insufficient transparency ({trans_ratio:.1%}): possible background cutout failure"
        if trans_ratio > 0.98:
            return False, f"Excessive transparency ({trans_ratio:.1%}): object eroded away"
        bbox = alpha.getbbox()
        if not bbox:
            return False, "Empty transparent canvas"
        return True, f"Clean alpha cutout ({trans_ratio:.1%} transparent)"
    else:
        w, h = img.size
        if w < 128 or h < 128:
            return False, f"Image too small ({w}x{h})"
        return True, "Valid opaque surface"


def normalize_and_save(source_path: Path, dest_path: Path, target_size: tuple[int, int], alpha_mode: str, pivot: str = "bottom_center") -> None:
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    target_w, target_h = target_size
    margin = 16

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


def run_batch(max_assets: int = 50, start_offset: int = 0) -> None:
    if not PACK_PATH.is_file():
        print(f"Error: pack index not found at {PACK_PATH}", file=sys.stderr)
        sys.exit(1)

    with open(PACK_PATH, "r", encoding="utf-8") as f:
        pack = json.load(f)

    assets = pack.get("assets", [])
    ungenerated = [a for a in assets if a.get("status") != "generated"]
    print(f"Total assets: {len(assets)} | Ungenerated: {len(ungenerated)}")

    target_slice = ungenerated[start_offset:start_offset + max_assets]
    print(f"Processing slice: {len(target_slice)} assets")

    success_count = 0

    for idx, asset in enumerate(target_slice, 1):
        asset_id = asset["id"]
        record = load_index_record(PACK_PATH, asset_id)
        cat = asset.get("category", "props")
        item_slug = asset_id.split(".")[-1]
        alpha_mode = record.get("alpha", "transparent")
        canvas_px = record.get("canvas_px", [128, 128])
        pivot = record.get("pivot", "bottom_center")
        rel_runtime_path = f"res://assets/world_map/yin_jian/{cat}/{item_slug}.png"
        runtime_file = GAME_ROOT / rel_runtime_path.replace("res://", "")

        print(f"\n[{idx}/{len(target_slice)}] Generating {asset_id} (mode={alpha_mode}, size={canvas_px})...")

        best_candidate = None
        best_seed = None
        best_prompt = None

        # 3 candidate rule
        for candidate_idx in range(3):
            seed = int(time.time() * 1000) % 1000000000 + candidate_idx * 1337
            prompt_brief = asset.get("prompt_summary") or asset.get("name") or asset_id

            gen_args = argparse.Namespace(
                asset_id=asset_id,
                index=str(PACK_PATH),
                prompt=prompt_brief,
                negative=(
                    "ground plane, floor, tiles, terrain texture, shadows on ground, environment, scenery, landscape, room, walls, text, letters, watermark, border, UI, extra objects, duplicate subject, isometric view, 3D render, photorealism, noisy texture"
                    if alpha_mode == "transparent"
                    else "border, frame, perspective, horizon, sky, object, building, tree, prop, lantern, shadow, tilt, isometric"
                ),
                seed=seed,
                size=1024,
                preview_only=True,
                steps=8,
                cfg=1.0,
                guidance=None,
                sampler="euler_ancestral",
                scheduler="beta",
                profile="krea2",
                checkpoint=DEFAULT_CHECKPOINT,
                lora="",
                lora_strength=0.0,
                rembg_model=DEFAULT_REMBG_MODEL if alpha_mode == "transparent" else "none",
                rembg_post_processing=False,
                alpha_matting=False,
                alpha_foreground_threshold=240,
                alpha_background_threshold=10,
                alpha_erode_size=0,
                comfy_url="http://127.0.0.1:8188",
                timeout=600,
                compare_rembg=False,
                output_dir="map-generated",
            )

            try:
                record = load_index_record(PACK_PATH, asset_id)
                output_path, used_prompt, used_seed = generate(record, gen_args)
                is_valid, reason = evaluate_candidate(output_path, alpha_mode)
                print(f"  Candidate {candidate_idx + 1} (seed {used_seed}): {reason}")

                if is_valid:
                    best_candidate = output_path
                    best_seed = used_seed
                    best_prompt = used_prompt
                    break
                else:
                    best_candidate = output_path
                    best_seed = used_seed
                    best_prompt = used_prompt
            except Exception as exc:
                print(f"  Candidate {candidate_idx + 1} failed: {exc}", file=sys.stderr)
                time.sleep(2)

        if best_candidate and best_candidate.is_file():
            print(f"  Installing best candidate: {best_candidate.name}")
            normalize_and_save(best_candidate, runtime_file, (canvas_px[0], canvas_px[1]), alpha_mode, pivot)

            # Update asset record in memory and persist
            asset.update({
                "status": "generated",
                "path": rel_runtime_path,
                "source": f"ComfyUI local checkpoint: {DEFAULT_CHECKPOINT}",
                "license": "Generated locally; source checkpoint license terms apply",
                "generated_on": time.strftime("%Y-%m-%d"),
                "prompt_ref": f"comfyui-map-v1:{asset_id}:{best_seed}",
                "reference_ids": ["docs/art-direction.md#top-down-world-map"],
            })

            for retry in range(5):
                try:
                    temp_pack = PACK_PATH.with_suffix(".tmp")
                    with open(temp_pack, "w", encoding="utf-8") as f:
                        json.dump(pack, f, indent=2, ensure_ascii=False)
                    temp_pack.replace(PACK_PATH)
                    break
                except OSError as exc:
                    if retry == 4:
                        print(f"  [WARN] Failed to write pack JSON after 5 retries: {exc}", file=sys.stderr)
                    time.sleep(0.5)

            success_count += 1
            print(f"  [OK] Successfully registered {asset_id} -> {rel_runtime_path}")
        else:
            print(f"  [FAIL] Could not produce acceptable candidate for {asset_id}")

    print(f"\nBatch completed: {success_count}/{len(target_slice)} assets successfully generated and registered.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=20, help="Number of assets to generate in this run")
    parser.add_argument("--offset", type=int, default=0, help="Offset into ungenerated list")
    args = parser.parse_args()
    run_batch(max_assets=args.count, start_offset=args.offset)
