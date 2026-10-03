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
    family = generate.add_mutually_exclusive_group(required=True)
    family.add_argument("--asset-id", help="existing family id from asset-index.jsonl")
    family.add_argument("--family-id", help="new family id to add to asset-index.jsonl")
    generate.add_argument(
        "--match-item",
        action="append",
        default=[],
        help="item seed to assign to a new family; repeat to group matching seeds",
    )
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
    generate.add_argument(
        "--visual-trait",
        action="append",
        default=[],
        help="record a tag such as form:robe, presentation:female, or palette:cinnabar",
    )


def run(args) -> int:
    records = assets._load_index()
    new_family = args.family_id is not None
    if new_family:
        if not args.match_item:
            raise ToolError("--family-id requires at least one --match-item")
        if len(args.match_item) != len(set(args.match_item)):
            raise ToolError("--match-item values must be unique")
        items = assets._load_items()
        record = _new_family_record(args.family_id, args.match_item, items)
        if any(item["id"] == record["id"] for item in records):
            raise ToolError(f"item asset family '{record['id']}' already exists")
        _validate_new_family(records, record, items)
    else:
        if args.match_item:
            raise ToolError("--match-item can only be used with --family-id")
        record = next((item for item in records if item["id"] == args.asset_id), None)
        if record is None:
            raise ToolError(f"unknown item asset family '{args.asset_id}'")
    if not ASSET_ID_RE.fullmatch(record["id"]):
        raise ToolError(f"item asset id '{record['id']}' cannot form a safe filename")
    if args.target_size < 64 or args.target_size > 2048 or args.target_size % 16:
        raise ToolError("--target-size must be a multiple of 16 between 64 and 2048")
    if any(not assets.VISUAL_TRAIT_RE.fullmatch(value) for value in args.visual_trait):
        raise ToolError("--visual-trait must use lowercase namespace:value form")
    selected_axes = [
        value.split(":", 1)[0]
        for value in args.visual_trait
        if value.split(":", 1)[0] in assets.SINGLE_VALUE_TRAIT_AXES
    ]
    if len(selected_axes) != len(set(selected_axes)):
        raise ToolError("only one form, palette, and presentation tag may be supplied per family")

    filename = f"{record['id']}.png"
    asset_path = f"res://assets/items/generated/{filename}"
    output_path = OUTPUT_DIR / filename
    if new_family and args.replace_generated:
        raise ToolError("--replace-generated only applies to an existing family")
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
        "visual_traits": args.visual_trait,
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
    if new_family:
        current_items = assets._load_items()
        current = _new_family_record(args.family_id, args.match_item, current_items)
        if any(item["id"] == current["id"] for item in current_records):
            raise ToolError(f"item asset family '{args.family_id}' was added while generating")
        _validate_new_family(current_records, current, current_items)
    else:
        current = next((item for item in current_records if item["id"] == args.asset_id), None)
        if current is None:
            raise ToolError(f"item asset family '{args.asset_id}' was removed while generating")
        if current.get("match") != record.get("match"):
            raise ToolError(f"item asset family '{args.asset_id}' changed while generating")
    _check_install_target(current_records, current, asset_path, output_path, args.replace_generated)
    assets._normalize_image(image_path, filename, replace=args.replace_generated)

    if new_family:
        current_records.append(current)
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
    traits = set(current.get("visual_traits", []))
    for value in args.visual_trait:
        axis = value.split(":", 1)[0]
        if axis in assets.SINGLE_VALUE_TRAIT_AXES:
            traits = {existing for existing in traits if not existing.startswith(f"{axis}:")}
        traits.add(value)
    if traits:
        current["visual_traits"] = sorted(traits)
    else:
        current.pop("visual_traits", None)
    if new_family:
        issues: list[str] = []
        winners = assets._resolve(current_items, current_records, issues)
        if issues:
            raise ToolError(f"cannot add item family: item match has {len(issues)} issue(s)")
        if any(winners.get(item_id) != current["id"] for item_id in args.match_item):
            raise ToolError("new item family does not win its selected seed matches")
        assets._write_links(current_records, winners)
        linked_count = len(args.match_item)
    else:
        _write_index(current_records)
        linked_count = len(current.get("item_ids", []))
    ok(f"installed {asset_path}; linked {linked_count} item seeds")
    return 0


def _new_family_record(family_id: str, item_ids: list[str], items: dict[str, dict]) -> dict:
    if not ASSET_ID_RE.fullmatch(family_id):
        raise ToolError(f"item asset id '{family_id}' cannot form a safe filename")
    missing = sorted(set(item_ids) - items.keys())
    if missing:
        raise ToolError(f"unknown item seed(s): {', '.join(missing[:10])}")
    categories = {
        (items[item_id]["category"], items[item_id]["subcategory"]) for item_id in item_ids
    }
    if len(categories) != 1:
        raise ToolError("all --match-item seeds must share one category and subcategory")
    category, subcategory = next(iter(categories))
    expression = "^(?:" + "|".join(re.escape(item_id) for item_id in sorted(item_ids)) + ")$"
    return {
        "id": family_id,
        "path": f"res://assets/items/generated/{family_id}.png",
        "type": "item_icon",
        "match": {"category": category, "subcategory": subcategory, "id_regex": expression},
        "item_ids": sorted(item_ids),
    }


def _validate_new_family(records: list[dict], record: dict, items: dict[str, dict]) -> None:
    selected = set(record["item_ids"])
    matched = {
        item_id
        for item_id, item in items.items()
        if assets._matches(record["match"], item_id, item)
    }
    if matched != selected:
        raise ToolError(f"family '{record['id']}' match rule includes unselected item seeds")
    issues: list[str] = []
    winners = assets._resolve(items, [*records, record], issues)
    if issues:
        raise ToolError(
            f"cannot create item family: existing asset matches have {len(issues)} issue(s)"
        )
    not_won = sorted(item_id for item_id in selected if winners.get(item_id) != record["id"])
    if not_won:
        raise ToolError(
            f"family '{record['id']}' does not win its selected seed matches: "
            + ", ".join(not_won[:10])
        )


def _check_install_target(
    records: list[dict], record: dict, asset_path: str, output_path: Path, replace: bool
) -> None:
    if not asset_path.startswith("res://assets/items/generated/"):
        raise ToolError("generated item icons must be stored under res://assets/items/generated/")
    shared = [
        other["id"] for other in records if other is not record and other["path"] == asset_path
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
        json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n" for record in records
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
