"""Generate indexed item-family icons through the local ComfyUI workflow."""

from __future__ import annotations

import json
import os
import re
import tempfile
from datetime import date
from pathlib import Path

from . import assets, map_generate
from .common import GAME_DIR, REPO_ROOT, ToolError, ok

OUTPUT_DIR = GAME_DIR / "assets" / "items" / "generated"
ASSET_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")


def register(actions) -> None:
    generate = actions.add_parser(
        "generate", help="generate and index one item-family icon through local ComfyUI"
    )
    generate.add_argument("--asset-id", required=True, help="family id from asset-index.jsonl")
    generate.add_argument("--prompt", required=True, help="item appearance and material details")
    generate.add_argument("--negative", default=map_generate.DEFAULT_NEGATIVE)
    generate.add_argument("--seed", type=int, default=-1, help="-1 chooses a random seed")
    generate.add_argument("--size", type=int, default=1024, help="square generation resolution")
    generate.add_argument("--target-size", type=int, default=256, help="installed square canvas")
    generate.add_argument("--preview-only", action="store_true", help="do not install or index")
    generate.add_argument(
        "--replace-generated", action="store_true", help="replace this family's generated icon"
    )
    generate.add_argument("--steps", type=int, default=32)
    generate.add_argument("--cfg", type=float, default=1.0)
    generate.add_argument("--guidance", type=float, default=3.5)
    generate.add_argument("--sampler", default="euler")
    generate.add_argument("--scheduler", default="normal")
    generate.add_argument("--checkpoint", default=map_generate.DEFAULT_CHECKPOINT)
    generate.add_argument("--lora", default=map_generate.DEFAULT_LORA)
    generate.add_argument("--lora-strength", type=float, default=0.8)
    generate.add_argument("--rembg-model", default=map_generate.DEFAULT_REMBG_MODEL)
    generate.add_argument("--rembg-post-processing", action="store_true")
    generate.add_argument("--alpha-matting", action="store_true")
    generate.add_argument("--alpha-foreground-threshold", type=int, default=240)
    generate.add_argument("--alpha-background-threshold", type=int, default=10)
    generate.add_argument("--alpha-erode-size", type=int, default=0)
    generate.add_argument("--comfy-url", default="http://127.0.0.1:8188")
    generate.add_argument("--timeout", type=int, default=600)
    generate.add_argument(
        "--license",
        default="Generated locally; source checkpoint license terms apply",
        help="terms recorded with the generated asset",
    )
    generate.add_argument("--reference-id", action="append", default=[])


def run(args) -> int:
    records = assets._load_index()
    record = next((item for item in records if item["id"] == args.asset_id), None)
    if record is None:
        raise ToolError(f"unknown item asset family '{args.asset_id}'")
    if not ASSET_ID_RE.fullmatch(record["id"]):
        raise ToolError(f"item asset id '{record['id']}' cannot form a safe filename")
    if args.target_size < 64 or args.target_size > 2048 or args.target_size % 16:
        raise ToolError("--target-size must be a multiple of 16 between 64 and 2048")

    filename = f"{record['id']}.png"
    asset_path = f"res://assets/items/generated/{filename}"
    output_path = OUTPUT_DIR / filename
    _check_install_target(records, record, asset_path, output_path, args.replace_generated)

    generation_record = {
        "id": record["id"],
        "type": "item_icon",
        "alpha": "transparent",
        "name": (
            f"{record['match'].get('category', 'item')} "
            f"{record['match'].get('subcategory', 'icon')}"
        ),
        "match": record["match"],
        "family_examples": record.get("item_ids", [])[:5],
    }
    image_path, prompt, seed = map_generate.generate(
        generation_record,
        args,
        output_dir="item-generated",
        client_id="chaos-world-item-assets",
    )
    if args.preview_only:
        preview = image_path.relative_to(REPO_ROOT).as_posix()
        ok(f"generated item preview only; asset index unchanged ({preview})")
        return 0

    # Rendering may take minutes. Reload so the final write preserves concurrent index edits.
    current_records = assets._load_index()
    current = next((item for item in current_records if item["id"] == args.asset_id), None)
    if current is None:
        raise ToolError(f"item asset family '{args.asset_id}' was removed while generating")
    if current.get("match") != record.get("match"):
        raise ToolError(f"item asset family '{args.asset_id}' changed while generating")
    _check_install_target(current_records, current, asset_path, output_path, args.replace_generated)
    assets._normalize_image(image_path, filename, replace=args.replace_generated)

    current["path"] = asset_path
    current["source"] = f"ComfyUI local checkpoint: {args.checkpoint}"
    current["prompt_ref"] = f"comfyui-item-v1:{record['id']}:{seed}"
    current["prompt"] = prompt
    current["generated_on"] = date.today().isoformat()
    current["license"] = args.license
    current["generation_settings"] = {
        "checkpoint": args.checkpoint,
        "lora": args.lora,
        "lora_strength": args.lora_strength,
        "seed": seed,
        "steps": args.steps,
        "size": args.size,
        "target_size": args.target_size,
        "cfg": args.cfg,
        "guidance": args.guidance,
        "sampler": args.sampler,
        "scheduler": args.scheduler,
        "rembg_model": args.rembg_model,
        "rembg_post_processing": args.rembg_post_processing,
        "alpha_matting": args.alpha_matting,
        "alpha_foreground_threshold": args.alpha_foreground_threshold,
        "alpha_background_threshold": args.alpha_background_threshold,
        "alpha_erode_size": args.alpha_erode_size,
    }
    current["reference_id"] = args.reference_id or ["docs/art-direction.md#item-icons"]
    _write_index(current_records)
    ok(f"installed {asset_path}; retained {len(current.get('item_ids', []))} item-seed links")
    return 0


def _check_install_target(
    records: list[dict], record: dict, asset_path: str, output_path: Path, replace: bool
) -> None:
    if not asset_path.startswith("res://assets/items/generated/"):
        raise ToolError("generated item icons must be stored under res://assets/items/generated/")
    shared = [
        other["id"]
        for other in records
        if other is not record and other["path"] == asset_path
    ]
    if shared:
        raise ToolError(f"generated path is also assigned to another family: {', '.join(shared)}")
    if output_path.exists() and replace and record.get("path") != asset_path:
        raise ToolError(
            f"refusing to replace an unindexed file for '{record['id']}': "
            f"{output_path.relative_to(REPO_ROOT).as_posix()}"
        )
    if output_path.exists() and not replace:
        raise ToolError(
            f"refusing to overwrite {output_path.relative_to(REPO_ROOT).as_posix()}; "
            "use --replace-generated after reviewing the preview"
        )


def _write_index(records: list[dict]) -> None:
    index_path = assets.INDEX_PATH
    content = "".join(
        json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n"
        for record in records
    )
    index_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", newline="\n", dir=index_path.parent, delete=False
        ) as temporary:
            temporary.write(content)
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, index_path)
    finally:
        if temporary_path and temporary_path.exists():
            temporary_path.unlink()
