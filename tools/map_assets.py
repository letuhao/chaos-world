"""Plan and validate the top-down world-map asset catalog."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from collections import Counter
from datetime import date
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from . import map_generate
from .common import GAME_DIR, REPO_ROOT, ToolError, fail, ok

INDEX_PATH = GAME_DIR / "assets" / "map-asset-index.jsonl"
ASSET_ROOT = GAME_DIR / "assets" / "world_map"
MIN_ASSETS = 1000

# Each environment gets one large terrain surface and a coherent 64-asset kit.
# Region-specific art changes materials and silhouettes, not just hue.
ENVIRONMENTS = (
    (
        "mortal_plains",
        "Mortal World",
        "Mortal Plains",
        "Sun-warmed ochre loam, low golden grasses, rounded hills, and worn farm tracks.",
    ),
    (
        "mortal_greenwood",
        "Mortal World",
        "Mortal Greenwood",
        "Dense broadleaf canopy, tangled roots, emerald moss, and dappled forest clearings.",
    ),
    (
        "mortal_riverlands",
        "Mortal World",
        "Mortal Riverlands",
        "Silt banks, winding slate-blue channels, smooth river stones, and reed beds.",
    ),
    (
        "mortal_highlands",
        "Mortal World",
        "Mortal Highlands",
        "Exposed grey granite, steep broken ledges, wind-shaped pines, and pale lichen.",
    ),
    (
        "spirit_peaks",
        "Spirit World",
        "Spirit Peaks",
        "Cold blue stone, sparse snow, crystalline mist, and hardy dark mountain pines.",
    ),
    (
        "spirit_bamboo_sea",
        "Spirit World",
        "Spirit Bamboo Sea",
        "Interlocking jade bamboo crowns, pale leaf litter, green shoots, and winding footpaths.",
    ),
    (
        "spirit_moonfen",
        "Spirit World",
        "Spirit Moonfen",
        "Blue-black fen pools, silver reeds, peat islands, and restrained moonlit reflections.",
    ),
    (
        "spirit_ghostwood",
        "Spirit World",
        "Spirit Ghostwood",
        "Charcoal soil, bone-pale roots, sparse ghost grass, and small cold cyan spirit lights.",
    ),
    (
        "immortal_court",
        "Immortal World",
        "Immortal Court",
        "Ivory stone terraces, balanced formal layouts, fine antique-gold seams, and cloud carving.",
    ),
    (
        "immortal_cloud_isles",
        "Immortal World",
        "Immortal Cloud Isles",
        "Floating pale rock shelves, soft cloud banks, cool blue-grey shade, and airy silhouettes.",
    ),
    (
        "immortal_jade_orchard",
        "Immortal World",
        "Immortal Jade Orchard",
        "Ancient ordered fruit trees, pale blossoms, jade moss, and clear mineral pools.",
    ),
    (
        "immortal_star_lake",
        "Immortal World",
        "Immortal Star Lake",
        "Deep teal lake stone, star-like reflections, quiet silver highlights, and celestial markings.",
    ),
    (
        "transcendent_realm",
        "Transcendent World",
        "Transcendent Realm",
        "Calm ivory and platinum forms, sparse gold accents, and impossibly clean sacred stone.",
    ),
    (
        "primordial_wilds",
        "Transcendent World",
        "Primordial Wilds",
        "Colossal exposed roots, ancient moss-dark basalt, amber minerals, and untamed growth.",
    ),
    (
        "void_shoal",
        "Transcendent World",
        "Void Shoal",
        "Black glass shoals, deep violet water, scattered stone fragments, and sparse cyan glimmers.",
    ),
    (
        "dao_fracture",
        "Transcendent World",
        "Dao Fracture",
        "Misaligned stone planes, impossible cracks, suspended shards, and narrow luminous seams.",
    ),
    (
        "ember_grotto",
        "Mortal World",
        "Ember Grotto",
        "Soot-dark basalt, warm umber stone, ember fissures, and compact volcanic formations.",
    ),
    (
        "flame_valley_depths",
        "Spirit World",
        "Flame Valley Depths",
        "Layered cinder slopes, copper-red stone, scorched earth, and controlled internal firelight.",
    ),
    (
        "stormwrack_reach",
        "Immortal World",
        "Stormwrack Reach",
        "Wet dark coastal rock, broken seafoam, wind-bent coastal flora, and weathered driftwood.",
    ),
)
ENVIRONMENT_IDS = {entry[0] for entry in ENVIRONMENTS}
WORLD_TIERS = {entry[1] for entry in ENVIRONMENTS}
ENVIRONMENT_THEMES = {entry[0]: entry[3] for entry in ENVIRONMENTS}

# id suffix, display name, asset kind, canvas size, pivot, collision role
ASSET_ROLES = {
    "ground_tile": (
        ("base_ground", "Base ground", "tile", 128, "center", "none"),
        ("soft_ground", "Soft ground", "tile", 128, "center", "none"),
        ("packed_trail", "Packed trail", "tile", 128, "center", "none"),
        ("stone_paving", "Stone paving", "tile", 128, "center", "none"),
        ("leaf_or_silt_litter", "Leaf or silt litter", "tile", 128, "center", "none"),
        ("cracked_ground", "Cracked ground", "tile", 128, "center", "none"),
        ("sacred_ground", "Sacred ground", "tile", 128, "center", "none"),
        ("resource_bare_ground", "Resource bare ground", "tile", 128, "center", "none"),
    ),
    "terrain_texture": (
        ("base_surface", "Base terrain surface", "terrain_texture", 1024, "center", "none"),
    ),
    "terrain_transition": (
        ("ground_edge", "Ground edge", "tile", 128, "center", "none"),
        ("trail_edge", "Trail edge", "tile", 128, "center", "none"),
        ("shore_edge", "Shore edge", "tile", 128, "center", "none"),
        ("cliff_edge", "Cliff edge", "tile", 128, "center", "solid"),
        ("slope_ramp", "Slope ramp", "tile", 128, "center", "none"),
        ("terrain_corner", "Terrain corner", "tile", 128, "center", "none"),
        ("terrain_inner_corner", "Terrain inner corner", "tile", 128, "center", "none"),
        ("terrain_island", "Terrain island", "tile", 128, "center", "none"),
    ),
    "water_feature": (
        ("shallow_water", "Shallow water", "tile", 128, "center", "none"),
        ("deep_water", "Deep water", "tile", 128, "center", "solid"),
        ("pool", "Natural pool", "prop", 256, "center", "solid"),
        ("stream", "Stream segment", "tile", 128, "center", "none"),
        ("waterfall", "Waterfall", "prop", 256, "bottom_center", "none"),
        ("spring", "Spring", "prop", 256, "bottom_center", "none"),
        ("water_foam", "Water foam", "decal", 128, "center", "none"),
        ("water_plant", "Water plant", "prop", 128, "bottom_center", "none"),
    ),
    "flora": (
        ("canopy_tree", "Canopy tree", "prop", 256, "bottom_center", "solid"),
        ("slender_tree", "Slender tree", "prop", 256, "bottom_center", "solid"),
        ("ancient_tree", "Ancient tree", "landmark", 512, "bottom_center", "solid"),
        ("shrub", "Shrub", "prop", 128, "bottom_center", "solid"),
        ("flower_cluster", "Flower cluster", "prop", 128, "bottom_center", "none"),
        ("cultivation_herb", "Cultivation herb", "resource_node", 128, "bottom_center", "none"),
        ("fallen_log", "Fallen log", "prop", 256, "bottom_center", "solid"),
        ("root_cluster", "Exposed root cluster", "prop", 128, "bottom_center", "solid"),
    ),
    "stone_and_ore": (
        ("small_rock", "Small rock", "prop", 128, "bottom_center", "solid"),
        ("boulder", "Boulder", "prop", 256, "bottom_center", "solid"),
        ("stone_cluster", "Stone cluster", "prop", 256, "bottom_center", "solid"),
        ("ore_vein", "Ore vein", "resource_node", 256, "bottom_center", "solid"),
        ("crystal_growth", "Crystal growth", "resource_node", 256, "bottom_center", "solid"),
        ("standing_stone", "Standing stone", "prop", 256, "bottom_center", "solid"),
        ("rubble", "Rubble scatter", "decal", 128, "center", "none"),
        ("mineral_spring", "Mineral spring", "resource_node", 256, "bottom_center", "none"),
    ),
    "travel_and_wayfinding": (
        ("trail_marker", "Trail marker", "prop", 128, "bottom_center", "none"),
        ("signpost", "Signpost", "prop", 128, "bottom_center", "solid"),
        ("stone_waypoint", "Stone waypoint", "prop", 256, "bottom_center", "solid"),
        ("wooden_bridge", "Wooden bridge", "prop", 256, "bottom_center", "none"),
        ("stone_bridge", "Stone bridge", "prop", 256, "bottom_center", "none"),
        ("path_gate", "Path gate", "prop", 256, "bottom_center", "solid"),
        ("portal_frame", "Portal frame", "landmark", 512, "bottom_center", "solid"),
        ("travel_shrine", "Travel shrine", "interactable", 256, "bottom_center", "solid"),
    ),
    "settlement_and_domain_prop": (
        ("shelter", "Field shelter", "prop", 256, "bottom_center", "solid"),
        ("storehouse", "Storehouse", "building", 512, "bottom_center", "solid"),
        ("workbench", "Outdoor workbench", "interactable", 256, "bottom_center", "solid"),
        ("supply_crate", "Supply crate", "prop", 128, "bottom_center", "solid"),
        ("sealed_cache", "Sealed cache", "interactable", 128, "bottom_center", "solid"),
        ("cultivation_altar", "Cultivation altar", "interactable", 256, "bottom_center", "solid"),
        ("domain_seal", "Domain seal", "interactable", 256, "bottom_center", "solid"),
        ("resting_stone", "Resting stone", "interactable", 128, "bottom_center", "solid"),
    ),
    "landmark_and_environment_detail": (
        ("cliff_formation", "Cliff formation", "landmark", 512, "bottom_center", "solid"),
        ("cave_entrance", "Cave entrance", "landmark", 512, "bottom_center", "solid"),
        ("domain_entrance", "Domain entrance", "landmark", 512, "bottom_center", "solid"),
        ("ruined_arch", "Ruined arch", "landmark", 512, "bottom_center", "solid"),
        ("statue", "Guardian statue", "landmark", 256, "bottom_center", "solid"),
        ("banner", "Faction banner", "prop", 256, "bottom_center", "solid"),
        ("ground_decal", "Ground detail decal", "decal", 128, "center", "none"),
        ("ambient_effect", "Ambient spirit effect", "effect", 256, "center", "none"),
    ),
}


def register(parent_parser) -> None:
    parser = parent_parser.add_parser("map", help="plan, generate, and compose top-down map art")
    actions = parser.add_subparsers(dest="map_assets_action", required=True)
    actions.add_parser("scaffold", help="write the initial map asset plan")
    actions.add_parser("report", help="summarize map assets by environment and category")
    next_assets = actions.add_parser("next", help="prioritize undercovered map assets")
    next_assets.add_argument("--count", type=int, default=12)
    actions.add_parser("audit", help="validate the map asset index")
    actions.add_parser("preview", help="build a contact sheet of produced map assets")
    actions.add_parser("migrate", help="add explicit alpha mode to older index entries")
    compose = actions.add_parser(
        "compose", help="place indexed sprites over a terrain texture using a JSON layout"
    )
    compose.add_argument("--layout", required=True, help="JSON terrain and sprite placements")
    install = actions.add_parser("install", help="normalize and register one generated sprite")
    install.add_argument("--asset-id", required=True)
    install.add_argument("--source", required=True, help="generated transparent PNG")
    install.add_argument("--source-name", required=True, help="generation tool/model and date")
    install.add_argument("--license", required=True, help="license or generation terms")
    install.add_argument("--generated-on", required=True, help="generation date (YYYY-MM-DD)")
    install.add_argument("--prompt-ref", required=True, help="stable prompt identifier")
    install.add_argument("--prompt", required=True, help="exact generation prompt")
    install.add_argument("--reference-id", action="append", default=[])
    generate = actions.add_parser(
        "generate", help="generate and index one map asset through local ComfyUI"
    )
    generate.add_argument("--asset-id", required=True)
    generate.add_argument("--prompt", required=True, help="subject and asset-specific details")
    generate.add_argument("--negative", default=map_generate.DEFAULT_NEGATIVE)
    generate.add_argument("--seed", type=int, default=-1, help="-1 chooses a random seed")
    generate.add_argument("--size", type=int, default=1024, help="square generation resolution")
    generate.add_argument(
        "--preview-only",
        action="store_true",
        help="save a generated preview without installing it in the map index",
    )
    generate.add_argument(
        "--replace-generated",
        action="store_true",
        help="replace an existing generated asset after reviewing its preview",
    )
    generate.add_argument(
        "--compare-rembg",
        action="store_true",
        help="also save cutouts from each installed background-removal model",
    )
    generate.add_argument(
        "--target-size",
        type=int,
        help="installed square canvas; defaults to --size to keep the high-resolution result",
    )
    generate.add_argument("--steps", type=int, default=32)
    generate.add_argument("--cfg", type=float, default=1.0)
    generate.add_argument("--guidance", type=float, default=3.5)
    generate.add_argument("--sampler", default="euler")
    generate.add_argument("--scheduler", default="normal")
    generate.add_argument(
        "--checkpoint",
        default=map_generate.DEFAULT_CHECKPOINT,
        help="ComfyUI checkpoint name; must match the loaded CLIP/VAE workflow",
    )
    generate.add_argument(
        "--lora",
        default=map_generate.DEFAULT_LORA,
        help="ComfyUI LoRA name for model and CLIP (default: selected 2D game-asset LoRA)",
    )
    generate.add_argument("--lora-strength", type=float, default=0.8)
    generate.add_argument(
        "--rembg-model",
        default=map_generate.DEFAULT_REMBG_MODEL,
        help="cutout model (default: isnet-anime; use --compare-rembg to compare installed choices)",
    )
    generate.add_argument(
        "--rembg-post-processing", action=argparse.BooleanOptionalAction, default=False
    )
    generate.add_argument("--alpha-matting", action=argparse.BooleanOptionalAction, default=False)
    generate.add_argument(
        "--alpha-foreground-threshold",
        type=int,
        default=240,
        help="alpha matting foreground cutoff",
    )
    generate.add_argument(
        "--alpha-background-threshold", type=int, default=10, help="alpha matting background cutoff"
    )
    generate.add_argument(
        "--alpha-erode-size",
        type=int,
        default=0,
        help="alpha matting edge erosion; 0 preserves fine painted edges",
    )
    generate.add_argument("--comfy-url", default="http://127.0.0.1:8188")
    generate.add_argument("--timeout", type=int, default=600, help="generation timeout in seconds")
    generate.add_argument(
        "--license",
        default="Generated locally; source checkpoint license terms apply",
        help="terms recorded with the generated asset",
    )
    generate.add_argument("--reference-id", action="append", default=[])


def run(args) -> int:
    action = args.map_assets_action
    if action == "scaffold":
        _scaffold()
        return 0

    records = _load_index()
    if action == "migrate":
        changed = 0
        for record in records:
            if "environment_theme" not in record:
                record["environment_theme"] = ENVIRONMENT_THEMES.get(record.get("environment"), "")
                changed += 1
            if "alpha" not in record:
                category = record.get("category", "")
                suffix = record.get("id", "").rsplit(".", 1)[-1]
                record["alpha"] = _alpha_mode(category, suffix, record.get("type", ""))
                changed += 1
        existing_ids = {record.get("id") for record in records}
        for environment in ENVIRONMENTS:
            for role in ASSET_ROLES["terrain_texture"]:
                terrain_record = _record_for_role(environment, "terrain_texture", role)
                if terrain_record["id"] not in existing_ids:
                    records.append(terrain_record)
                    existing_ids.add(terrain_record["id"])
                    changed += 1
        if changed:
            _atomic_write(
                "".join(
                    json.dumps(item, ensure_ascii=False, separators=(",", ":")) + "\n"
                    for item in records
                )
            )
        ok(f"added missing map metadata to {changed} asset records")
        return 0
    if action == "install":
        _install(records, args)
        return 0
    if action == "generate":
        _generate(records, args)
        return 0
    if action == "preview":
        _preview(records)
        return 0
    if action == "compose":
        _compose(records, args)
        return 0
    if action == "next":
        if args.count < 1:
            raise ToolError("--count must be at least 1")
        issues = _validate(records)
        if issues:
            raise ToolError(f"cannot prioritize an invalid map index ({len(issues)} issue(s))")
        _next_assets(records, args.count)
        return 0
    issues = _validate(records)
    if action == "report":
        _report(records, issues)
        return 1 if issues else 0
    if issues:
        for issue in issues:
            fail(issue)
        fail(f"map asset audit failed: {len(issues)} issue(s)")
        return 1
    ok(f"map asset audit complete ({len(records)} planned/generated assets)")
    return 0


def _scaffold() -> None:
    if INDEX_PATH.exists():
        raise ToolError(f"refusing to overwrite existing index: {INDEX_PATH}")
    records: list[dict] = []
    for environment in ENVIRONMENTS:
        for category, roles in ASSET_ROLES.items():
            records.extend(_record_for_role(environment, category, role) for role in roles)
    if len(records) < MIN_ASSETS:
        raise ToolError(f"scaffold contains only {len(records)} assets; minimum is {MIN_ASSETS}")
    content = "".join(
        json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n" for record in records
    )
    _atomic_write(content)
    ok(f"wrote {INDEX_PATH.relative_to(REPO_ROOT).as_posix()} ({len(records)} planned assets)")


def _record_for_role(environment: tuple, category: str, role: tuple) -> dict:
    environment_id, world_tier, environment_name, environment_theme = environment
    suffix, display_name, kind, size, pivot, collision = role
    return {
        "id": f"{environment_id}.{category}.{suffix}",
        "path": f"res://assets/world_map/{environment_id}/{category}/{suffix}.png",
        "type": kind,
        "category": category,
        "environment": environment_id,
        "environment_name": environment_name,
        "environment_theme": environment_theme,
        "world_tier": world_tier,
        "archetype": f"{category}.{suffix}",
        "name": display_name,
        "canvas_px": [size, size],
        "alpha": _alpha_mode(category, suffix, kind),
        "pivot": pivot,
        "collision": collision,
        "status": "planned",
        "source": "planned; not generated",
        "license": "not applicable until generated",
    }


def _load_index() -> list[dict]:
    if not INDEX_PATH.is_file():
        raise ToolError(f"map asset index not found; run 'assets map scaffold': {INDEX_PATH}")
    records: list[dict] = []
    for line_number, line in enumerate(INDEX_PATH.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ToolError(f"{INDEX_PATH.name}:{line_number}: invalid JSON ({exc.msg})") from exc
        if not isinstance(record, dict):
            raise ToolError(f"{INDEX_PATH.name}:{line_number}: each line must be an object")
        records.append(record)
    return records


def _alpha_mode(category: str, suffix: str, kind: str) -> str:
    if category in {"ground_tile", "terrain_texture"} or (
        category == "water_feature" and kind == "tile"
    ):
        return "opaque"
    return "transparent"


def _generate(records: list[dict], args) -> None:
    if args.target_size is not None and (
        not 64 <= args.target_size <= 2048 or args.target_size % 16
    ):
        raise ToolError("--target-size must be a multiple of 16 between 64 and 2048")
    issues = _validate(records)
    if issues:
        raise ToolError(f"cannot generate from an invalid map index ({len(issues)} issue(s))")
    record = next((item for item in records if item["id"] == args.asset_id), None)
    if record is None:
        raise ToolError(f"unknown map asset id '{args.asset_id}'")
    if args.preview_only:
        image_path, _, _ = map_generate.generate(record, args)
        ok(
            f"generated preview only; map index unchanged ({image_path.relative_to(REPO_ROOT).as_posix()})"
        )
        return
    replace_generated = args.replace_generated and record["status"] == "generated"
    if record["status"] != "planned" and not replace_generated:
        raise ToolError(f"refusing to replace '{args.asset_id}' with status '{record['status']}'")

    image_path, prompt, seed = map_generate.generate(record, args)
    install_args = argparse.Namespace(
        asset_id=args.asset_id,
        source=str(image_path),
        source_name=f"ComfyUI local checkpoint: {args.checkpoint}",
        license=args.license,
        generated_on=date.today().isoformat(),
        prompt_ref=f"comfyui-map-v1:{args.asset_id}:{seed}",
        prompt=prompt,
        replace_generated=replace_generated,
        canvas_px=[args.target_size or args.size, args.target_size or args.size],
        negative_prompt=args.negative,
        generation_settings={
            "checkpoint": args.checkpoint,
            "lora": args.lora,
            "lora_strength": args.lora_strength,
            "seed": seed,
            "steps": args.steps,
            "size": args.size,
            "target_size": args.target_size or args.size,
            "cfg": args.cfg,
            "guidance": args.guidance,
            "sampler": args.sampler,
            "scheduler": args.scheduler,
            "rembg_model": args.rembg_model if record["alpha"] == "transparent" else "none",
            "rembg_post_processing": args.rembg_post_processing,
            "alpha_matting": args.alpha_matting,
            "alpha_foreground_threshold": args.alpha_foreground_threshold,
            "alpha_background_threshold": args.alpha_background_threshold,
            "alpha_erode_size": args.alpha_erode_size,
        },
        reference_id=args.reference_id or ["docs/art-direction.md#top-down-world-map"],
    )
    # Generation can take minutes. Reload after it completes so this install
    # cannot overwrite index edits made while ComfyUI was rendering.
    _install(_load_index(), install_args)


def _install(records: list[dict], args) -> None:
    issues = _validate(records)
    if issues:
        raise ToolError(f"cannot install into an invalid map index ({len(issues)} issue(s))")
    record = next((item for item in records if item["id"] == args.asset_id), None)
    if record is None:
        raise ToolError(f"unknown map asset id '{args.asset_id}'")
    replace_generated = (
        getattr(args, "replace_generated", False) and record["status"] == "generated"
    )
    if record["status"] != "planned" and not replace_generated:
        raise ToolError(f"refusing to replace '{args.asset_id}' with status '{record['status']}'")
    if not args.reference_id or any(not value.strip() for value in args.reference_id):
        raise ToolError("at least one non-empty --reference-id is required")
    try:
        generated_date = date.fromisoformat(args.generated_on)
    except ValueError as exc:
        raise ToolError("--generated-on must be a valid YYYY-MM-DD date") from exc
    if generated_date.isoformat() != args.generated_on:
        raise ToolError("--generated-on must use YYYY-MM-DD format")
    if not args.source_name.strip() or not args.license.strip() or not args.prompt.strip():
        raise ToolError("source name, license terms, and prompt must be non-empty")

    source_path = Path(args.source).resolve()
    if source_path.suffix.lower() != ".png" or not source_path.is_file():
        raise ToolError(f"source must be an existing PNG: {source_path}")
    output_path = (GAME_DIR / record["path"].removeprefix("res://")).resolve()
    if not output_path.is_relative_to(ASSET_ROOT.resolve()):
        raise ToolError("asset output must stay under game/assets/world_map")
    if output_path.exists() and not replace_generated:
        raise ToolError(f"refusing to overwrite existing asset: {output_path}")
    previous_image = output_path.read_bytes() if replace_generated else None

    try:
        with Image.open(source_path) as opened:
            source_image = opened.convert("RGBA")
    except OSError as exc:
        raise ToolError(f"could not read source PNG: {source_path}") from exc
    alpha = source_image.getchannel("A")
    canvas_px = getattr(args, "canvas_px", None)
    if canvas_px is not None:
        record["canvas_px"] = canvas_px
    width, height = record["canvas_px"]
    if record["alpha"] == "transparent":
        if alpha.getextrema()[0] != 0:
            raise ToolError("source PNG has no fully transparent pixels")
        bounds = alpha.getbbox()
        if bounds is None:
            raise ToolError("source PNG is fully transparent")
        source_image = source_image.crop(bounds)
        padding = 16
        source_image.thumbnail(
            (width - padding * 2, height - padding * 2), Image.Resampling.LANCZOS
        )
        canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        if record["pivot"] == "bottom_center":
            position = ((width - source_image.width) // 2, height - padding - source_image.height)
        else:
            position = ((width - source_image.width) // 2, (height - source_image.height) // 2)
        canvas.alpha_composite(source_image, position)
    else:
        if "A" in source_image.getbands() and alpha.getextrema()[0] != 255:
            raise ToolError("opaque tile source contains transparent pixels")
        canvas = source_image.resize((width, height), Image.Resampling.LANCZOS)

    record.update(
        {
            "status": "generated",
            "source": args.source_name.strip(),
            "license": args.license.strip(),
            "generated_on": args.generated_on,
            "prompt_ref": args.prompt_ref.strip(),
            "prompt": args.prompt.strip(),
            "reference_ids": sorted(set(args.reference_id)),
        }
    )
    negative_prompt = getattr(args, "negative_prompt", None)
    if negative_prompt:
        record["negative_prompt"] = negative_prompt
    generation_settings = getattr(args, "generation_settings", None)
    if generation_settings:
        record["generation_settings"] = generation_settings
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            suffix=".png", dir=output_path.parent, delete=False
        ) as temporary:
            temporary_path = Path(temporary.name)
        canvas.save(temporary_path, format="PNG", optimize=True)
        os.replace(temporary_path, output_path)
        temporary_path = None
        try:
            _atomic_write(
                "".join(
                    json.dumps(item, ensure_ascii=False, separators=(",", ":")) + "\n"
                    for item in records
                )
            )
        except OSError:
            if previous_image is None:
                output_path.unlink(missing_ok=True)
            else:
                restore_path: Path | None = None
                try:
                    with tempfile.NamedTemporaryFile(
                        suffix=".png", dir=output_path.parent, delete=False
                    ) as restore:
                        restore.write(previous_image)
                        restore_path = Path(restore.name)
                    os.replace(restore_path, output_path)
                    restore_path = None
                finally:
                    if restore_path and restore_path.exists():
                        restore_path.unlink()
            raise
    finally:
        if temporary_path and temporary_path.exists():
            temporary_path.unlink()
    ok(
        f"installed {output_path.relative_to(REPO_ROOT).as_posix()} "
        f"({width}x{height}, {record['alpha']} pixels)"
    )


def _validate(records: list[dict]) -> list[str]:
    issues: list[str] = []
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    for index, record in enumerate(records, 1):
        label = f"{INDEX_PATH.name}:{index}"
        asset_id = record.get("id")
        if not isinstance(asset_id, str) or not asset_id.strip():
            issues.append(f"{label}: missing asset id")
        elif asset_id in seen_ids:
            issues.append(f"{label}: duplicate asset id '{asset_id}'")
        else:
            seen_ids.add(asset_id)
        path = record.get("path")
        if not isinstance(path, str) or not path.startswith("res://assets/world_map/"):
            issues.append(f"{label}: path must be under res://assets/world_map/")
        elif path in seen_paths:
            issues.append(f"{label}: duplicate asset path '{path}'")
        else:
            seen_paths.add(path)
        if isinstance(path, str) and path.startswith("res://"):
            local_path = (GAME_DIR / path.removeprefix("res://")).resolve()
            if not local_path.is_relative_to(ASSET_ROOT.resolve()):
                issues.append(f"{label}: resolved path escapes game/assets/world_map")
            if local_path.suffix.lower() != ".png":
                issues.append(f"{label}: map art path must end in .png")
        required_strings = (
            "type",
            "category",
            "environment",
            "environment_name",
            "environment_theme",
            "world_tier",
            "archetype",
            "name",
            "alpha",
            "pivot",
            "collision",
            "status",
            "source",
            "license",
        )
        for key in required_strings:
            if not isinstance(record.get(key), str) or not record[key].strip():
                issues.append(f"{label}: '{key}' must be a non-empty string")
        category = record.get("category")
        environment = record.get("environment")
        world_tier = record.get("world_tier")
        asset_type = record.get("type")
        status = record.get("status")
        pivot = record.get("pivot")
        collision = record.get("collision")
        alpha_mode = record.get("alpha")
        if not isinstance(category, str) or category not in ASSET_ROLES:
            issues.append(f"{label}: unknown category '{record.get('category')}'")
        if not isinstance(environment, str) or environment not in ENVIRONMENT_IDS:
            issues.append(f"{label}: unknown environment '{record.get('environment')}'")
        if not isinstance(world_tier, str) or world_tier not in WORLD_TIERS:
            issues.append(f"{label}: unknown world tier '{record.get('world_tier')}'")
        if not isinstance(asset_type, str) or asset_type not in {
            "tile",
            "terrain_texture",
            "prop",
            "landmark",
            "resource_node",
            "building",
            "interactable",
            "decal",
            "effect",
        }:
            issues.append(f"{label}: unknown asset type '{record.get('type')}'")
        canvas = record.get("canvas_px")
        if (
            not isinstance(canvas, list)
            or len(canvas) != 2
            or any(type(value) is not int or value < 1 for value in canvas)
        ):
            issues.append(f"{label}: canvas_px must contain two positive integers")
        if not isinstance(status, str) or status not in {"planned", "generated", "approved"}:
            issues.append(f"{label}: status must be planned, generated, or approved")
        if not isinstance(pivot, str) or pivot not in {"center", "bottom_center"}:
            issues.append(f"{label}: pivot must be center or bottom_center")
        if not isinstance(collision, str) or collision not in {"none", "solid"}:
            issues.append(f"{label}: collision must be none or solid")
        if not isinstance(alpha_mode, str) or alpha_mode not in {"opaque", "transparent"}:
            issues.append(f"{label}: alpha must be opaque or transparent")
        if status in {"generated", "approved"}:
            _validate_existing_file(record, label, issues)
            source = record.get("source")
            license_terms = record.get("license")
            if not isinstance(source, str) or source.startswith("planned"):
                issues.append(f"{label}: generated asset needs source provenance")
            if not isinstance(license_terms, str) or license_terms.startswith("not applicable"):
                issues.append(f"{label}: generated asset needs license or generation terms")
            for key in ("generated_on", "prompt_ref", "prompt"):
                if not isinstance(record.get(key), str) or not record[key].strip():
                    issues.append(f"{label}: generated asset needs '{key}' provenance")
            generated_on = record.get("generated_on")
            if isinstance(generated_on, str):
                try:
                    if date.fromisoformat(generated_on).isoformat() != generated_on:
                        issues.append(f"{label}: generated_on must use YYYY-MM-DD format")
                except ValueError:
                    issues.append(f"{label}: generated_on must be a valid YYYY-MM-DD date")
            reference_ids = record.get("reference_ids")
            if (
                not isinstance(reference_ids, list)
                or not reference_ids
                or any(not isinstance(value, str) or not value.strip() for value in reference_ids)
            ):
                issues.append(f"{label}: generated asset needs non-empty reference_ids")
            approved_by = record.get("approved_by")
            if status == "approved" and (
                not isinstance(approved_by, str) or not approved_by.strip()
            ):
                issues.append(f"{label}: approved asset needs 'approved_by'")

    category_counts = Counter(
        record.get("category") for record in records if isinstance(record.get("category"), str)
    )
    environment_counts = Counter(
        record.get("environment")
        for record in records
        if isinstance(record.get("environment"), str)
    )
    if len(records) < MIN_ASSETS:
        issues.append(f"index has {len(records)} assets; minimum is {MIN_ASSETS}")
    if len(category_counts) < 8:
        issues.append(
            f"index has only {len(category_counts)} asset categories; expected at least 8"
        )
    if len(environment_counts) < 4:
        issues.append(f"index has only {len(environment_counts)} environments; expected at least 4")
    return issues


def _validate_existing_file(record: dict, label: str, issues: list[str]) -> None:
    path = record.get("path")
    if not isinstance(path, str) or not path.startswith("res://"):
        return
    local_path = (GAME_DIR / path.removeprefix("res://")).resolve()
    if not local_path.is_relative_to(ASSET_ROOT.resolve()):
        issues.append(f"{label}: resolved file escapes game/assets/world_map")
    elif not local_path.is_file():
        issues.append(f"{label}: {path} is missing for status '{record.get('status')}'")
    else:
        try:
            with Image.open(local_path) as image:
                if list(image.size) != record.get("canvas_px"):
                    issues.append(
                        f"{label}: image is {image.width}x{image.height}; "
                        f"index expects {record.get('canvas_px')}"
                    )
                if record.get("alpha") == "transparent":
                    if "A" not in image.getbands() or image.getchannel("A").getextrema()[0] != 0:
                        issues.append(f"{label}: transparent asset needs zero-alpha pixels")
                elif "A" in image.getbands() and image.getchannel("A").getextrema()[0] != 255:
                    issues.append(f"{label}: opaque asset contains transparent pixels")
        except OSError:
            issues.append(f"{label}: generated PNG cannot be opened")


def _report(records: list[dict], issues: list[str]) -> None:
    statuses = Counter(
        value if isinstance(value := record.get("status"), str) else "invalid" for record in records
    )
    categories = {
        record.get("category") for record in records if isinstance(record.get("category"), str)
    }
    environments = {
        record.get("environment")
        for record in records
        if isinstance(record.get("environment"), str)
    }
    print(
        f"map assets: {len(records)} | categories: "
        f"{len(categories)} | environments: {len(environments)} | "
        f"status: {dict(sorted(statuses.items()))}"
    )
    for label, key in (("category", "category"), ("environment", "environment")):
        grouped: dict[str, Counter[str]] = {}
        for record in records:
            value = record.get(key)
            name = value if isinstance(value, str) else "invalid"
            grouped.setdefault(name, Counter())[record.get("status", "invalid")] += 1
        print(f"{label} coverage (produced/total):")
        for name, counts in sorted(grouped.items()):
            total = sum(counts.values())
            produced = counts["generated"] + counts["approved"]
            print(f"  {name}: {produced}/{total} ({counts['planned']} planned)")
    if issues:
        print(f"issues: {len(issues)}")
        for issue in issues[:30]:
            print(f"  - {issue}")
        if len(issues) > 30:
            print(f"  ... {len(issues) - 30} more")


def _preview(records: list[dict]) -> None:
    issues = _validate(records)
    if issues:
        raise ToolError(f"cannot preview an invalid map index ({len(issues)} issue(s))")
    produced = sorted(
        (record for record in records if record.get("status") in {"generated", "approved"}),
        key=lambda record: (record["environment"], record["category"], record["id"]),
    )
    if not produced:
        raise ToolError("no generated map assets are available to preview")

    columns = 4
    cell_width = 320
    cell_height = 360
    image_size = 288
    rows = (len(produced) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell_width, rows * cell_height), (36, 39, 43))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    checker = Image.new("RGBA", (image_size, image_size), (225, 225, 225, 255))
    checker_draw = ImageDraw.Draw(checker)
    checker_size = 16
    for y in range(0, image_size, checker_size):
        for x in range(0, image_size, checker_size):
            if (x // checker_size + y // checker_size) % 2:
                checker_draw.rectangle(
                    (x, y, x + checker_size - 1, y + checker_size - 1),
                    fill=(190, 190, 190, 255),
                )

    for index, record in enumerate(produced):
        column = index % columns
        row = index // columns
        left = column * cell_width + (cell_width - image_size) // 2
        top = row * cell_height + 8
        with Image.open(GAME_DIR / record["path"].removeprefix("res://")) as opened:
            asset = opened.convert("RGBA")
        asset.thumbnail((image_size, image_size), Image.Resampling.LANCZOS)
        if record["alpha"] == "transparent":
            preview = checker.copy()
            preview.alpha_composite(
                asset,
                ((image_size - asset.width) // 2, (image_size - asset.height) // 2),
            )
        else:
            preview = Image.new("RGBA", (image_size, image_size), (54, 58, 62, 255))
            preview.alpha_composite(
                asset,
                ((image_size - asset.width) // 2, (image_size - asset.height) // 2),
            )
        sheet.paste(preview.convert("RGB"), (left, top))
        label_y = top + image_size + 6
        draw.text(
            (column * cell_width + 16, label_y),
            record["environment"],
            fill="white",
            font=font,
        )
        draw.text(
            (column * cell_width + 16, label_y + 16),
            f"{record['category']} / {record['id'].rsplit('.', 1)[-1]}",
            fill=(205, 210, 215),
            font=font,
        )

    output_path = REPO_ROOT / "build" / "map-assets-preview.png"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path, format="PNG", optimize=True)
    ok(f"wrote {output_path.relative_to(REPO_ROOT).as_posix()} ({len(produced)} assets)")
    _preview_repeated_tiles(produced)


def _compose(records: list[dict], args) -> None:
    issues = _validate(records)
    if issues:
        raise ToolError(f"cannot compose from an invalid map index ({len(issues)} issue(s))")
    layout_path = Path(args.layout)
    try:
        layout = json.loads(layout_path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ToolError(f"cannot read composition layout: {layout_path}") from exc
    except json.JSONDecodeError as exc:
        raise ToolError(f"composition layout is invalid JSON: {layout_path}") from exc
    if not isinstance(layout, dict):
        raise ToolError("composition layout must be a JSON object")
    layout_id = layout.get("id")
    if (
        not isinstance(layout_id, str)
        or not layout_id
        or not all(character.isalnum() or character in "_-" for character in layout_id)
    ):
        raise ToolError("composition layout id may contain only letters, numbers, '_' and '-'")

    by_id = {record["id"]: record for record in records}
    terrain_id = layout.get("terrain_id")
    terrain = by_id.get(terrain_id) if isinstance(terrain_id, str) else None
    if (
        terrain is None
        or terrain["type"] != "terrain_texture"
        or terrain["status"] not in {"generated", "approved"}
        or terrain["alpha"] != "opaque"
    ):
        raise ToolError("terrain_id must name an opaque generated terrain_texture asset")
    placements = layout.get("placements")
    if not isinstance(placements, list):
        raise ToolError("composition placements must be a JSON array")

    terrain_path = GAME_DIR / terrain["path"].removeprefix("res://")
    try:
        with Image.open(terrain_path) as opened:
            composite = opened.convert("RGBA")
    except OSError as exc:
        raise ToolError(f"cannot read terrain texture: {terrain_path}") from exc
    width, height = composite.size
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
        x, y, scale = placement.get("x"), placement.get("y"), placement.get("scale", 0.25)
        if (
            isinstance(x, bool)
            or not isinstance(x, (int, float))
            or not 0 <= x <= width
            or isinstance(y, bool)
            or not isinstance(y, (int, float))
            or not 0 <= y <= height
            or isinstance(scale, bool)
            or not isinstance(scale, (int, float))
            or not 0 < scale <= 4
        ):
            raise ToolError(f"{label} needs in-canvas x/y coordinates and scale in (0, 4]")
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
        left = round(x - sprite.width / 2)
        top = round(
            y - sprite.height if asset["pivot"] == "bottom_center" else y - sprite.height / 2
        )
        crop_left, crop_top = max(0, left), max(0, top)
        crop_right, crop_bottom = min(width, left + sprite.width), min(height, top + sprite.height)
        if crop_left >= crop_right or crop_top >= crop_bottom:
            raise ToolError(f"{label} falls completely outside the terrain texture")
        visible = sprite.crop(
            (crop_left - left, crop_top - top, crop_right - left, crop_bottom - top)
        )
        composite.alpha_composite(visible, (crop_left, crop_top))

    output_path = REPO_ROOT / "build" / "map-compositions" / f"{layout_id}.png"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            suffix=".png", dir=output_path.parent, delete=False
        ) as temporary:
            temporary_path = Path(temporary.name)
        composite.save(temporary_path, format="PNG", optimize=True)
        os.replace(temporary_path, output_path)
        temporary_path = None
    finally:
        if temporary_path and temporary_path.exists():
            temporary_path.unlink()
    ok(f"wrote {output_path.relative_to(REPO_ROOT).as_posix()} with {len(placements)} sprites")


def _preview_repeated_tiles(produced: list[dict]) -> None:
    tiles = [record for record in produced if record.get("type") == "tile"]
    if not tiles:
        return

    columns = 3
    cell_width = 416
    cell_height = 430
    image_size = 384
    rows = (len(tiles) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell_width, rows * cell_height), (36, 39, 43))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    checker = Image.new("RGBA", (image_size, image_size), (225, 225, 225, 255))
    checker_draw = ImageDraw.Draw(checker)
    checker_size = 24
    for y in range(0, image_size, checker_size):
        for x in range(0, image_size, checker_size):
            if (x // checker_size + y // checker_size) % 2:
                checker_draw.rectangle(
                    (x, y, x + checker_size - 1, y + checker_size - 1),
                    fill=(190, 190, 190, 255),
                )

    for index, record in enumerate(tiles):
        column = index % columns
        row = index // columns
        left = column * cell_width + (cell_width - image_size) // 2
        top = row * cell_height + 8
        with Image.open(GAME_DIR / record["path"].removeprefix("res://")) as opened:
            tile = opened.convert("RGBA")
        repeated = Image.new("RGBA", (image_size, image_size), (0, 0, 0, 0))
        for y in range(3):
            for x in range(3):
                repeated.alpha_composite(tile, (x * tile.width, y * tile.height))
        if record["alpha"] == "transparent":
            preview = checker.copy()
            preview.alpha_composite(repeated)
        else:
            preview = Image.new("RGBA", (image_size, image_size), (54, 58, 62, 255))
            preview.alpha_composite(repeated)
        sheet.paste(preview.convert("RGB"), (left, top))
        label_y = top + image_size + 6
        label = (
            f"{record['environment']} / {record['category']} / {record['id'].rsplit('.', 1)[-1]}"
        )
        draw.text((column * cell_width + 16, label_y), label, fill="white", font=font)

    output_path = REPO_ROOT / "build" / "map-tiles-repeat-preview.png"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path, format="PNG", optimize=True)
    ok(f"wrote {output_path.relative_to(REPO_ROOT).as_posix()} ({len(tiles)} repeated tiles)")


def _next_assets(records: list[dict], count: int) -> None:
    environment_totals = Counter(record["environment"] for record in records)
    category_totals = Counter(record["category"] for record in records)
    environment_produced: Counter[str] = Counter()
    category_produced: Counter[str] = Counter()
    planned: list[tuple[int, dict]] = []
    for index, record in enumerate(records):
        if record["status"] == "planned":
            planned.append((index, record))
        elif record["status"] in {"generated", "approved"}:
            environment_produced[record["environment"]] += 1
            category_produced[record["category"]] += 1

    selected: list[dict] = []
    for _ in range(min(count, len(planned))):

        def priority(item: tuple[int, dict]) -> tuple[int, float, float, float, int, int, int]:
            index, record = item
            environment = record["environment"]
            category = record["category"]
            environment_ratio = environment_produced[environment] / environment_totals[environment]
            category_ratio = category_produced[category] / category_totals[category]
            return (
                0 if category == "terrain_texture" else 1,
                environment_ratio + category_ratio,
                environment_ratio,
                category_ratio,
                environment_produced[environment],
                category_produced[category],
                index,
            )

        selected_index = min(
            range(len(planned)), key=lambda candidate: priority(planned[candidate])
        )
        _, record = planned.pop(selected_index)
        selected.append(record)
        environment_produced[record["environment"]] += 1
        category_produced[record["category"]] += 1

    print(f"next {len(selected)} planned assets (lowest combined environment/category coverage):")
    for record in selected:
        width, height = record["canvas_px"]
        print(
            f"  {record['id']} | {record['type']} {width}x{height} | "
            f"{record['pivot']} pivot | {record['collision']} collision"
        )


def _atomic_write(content: str) -> None:
    INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", newline="\n", dir=INDEX_PATH.parent, delete=False
        ) as temporary:
            temporary.write(content)
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, INDEX_PATH)
    finally:
        if temporary_path and temporary_path.exists():
            temporary_path.unlink()
