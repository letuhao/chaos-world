"""Plan, generate, validate, and report private character art assets."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import os
import random
import re
import secrets
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from . import map_generate
from .common import GAME_DIR, REPO_ROOT, ToolError, fail, ok

CHARACTER_ROOT = GAME_DIR / "assets" / "characters"
INDEX_PATH = CHARACTER_ROOT / "character-index.jsonl"
MIN_CHARACTERS = 2000
MAX_CHARACTERS = 10000
CHARACTER_ID_RE = re.compile(r"^character-[0-9]{4,}$")
CHARACTER_DEFAULT_PROFILE = "krea2"
CHARACTER_ASPECT_RATIOS = (
    "1:1 (Square)",
    "2:3 (Portrait Photo)",
    "3:2 (Photo)",
    "3:4 (Portrait Standard)",
    "4:3 (Standard)",
    "9:16 (Portrait Widescreen)",
    "16:9 (Widescreen)",
    "21:9 (Ultrawide)",
)
CHARACTER_PROFILES = {
    "krea2": {
        "checkpoint": map_generate.KREA2_MODEL,
        "rembg_model": "silueta",
        "steps": 8,
        "cfg": 1.0,
        "guidance": None,
        "sampler": "euler_ancestral",
        "scheduler": "beta",
    },
    "flux1s": {
        "checkpoint": "FLUX1984AnimeStyleFeat_v20Fp8Noclip.safetensors",
        "rembg_model": map_generate.DEFAULT_REMBG_MODEL,
        "lora": "",
        "lora_strength": 0.8,
        "steps": 32,
        "cfg": 1.0,
        "guidance": 3.5,
        "sampler": "euler",
        "scheduler": "normal",
    },
}

# These controlled vocabularies are balanced deterministically when the catalog is scaffolded.
TRAIT_AXES = {
    "race": (
        "human",
        "beastkin",
        "spiritkin",
        "dragonkin",
        "aquatic",
        "celestial",
        "revenant",
        "elemental",
        "plantkin",
        "stonekin",
    ),
    "presentation": ("masculine", "feminine", "androgynous"),
    "age": ("young-adult", "adult", "elder"),
    "build": ("slender", "wiry", "athletic", "sturdy", "broad", "tall"),
    "complexion": (
        "porcelain",
        "fair",
        "warm",
        "olive",
        "bronze",
        "umber",
        "deep-brown",
        "stone-grey",
    ),
    "hair_color": (
        "black",
        "brown",
        "auburn",
        "silver",
        "white",
        "blue-black",
        "copper",
        "violet",
        "teal",
        "golden",
    ),
    "hairstyle": (
        "long-braid",
        "high-knot",
        "short-cropped",
        "loose-shoulder-length",
        "twin-braids",
        "tied-back",
        "layered-bob",
        "waist-length",
        "coiled",
        "wind-swept",
    ),
    "eyes": ("dark-brown", "amber", "grey", "jade", "blue", "violet", "silver", "gold"),
    "palette": (
        "cinnabar",
        "amber",
        "mineral-blue",
        "violet",
        "ivory",
        "iron",
        "jade",
        "teal",
        "plum",
        "coral",
        "slate",
        "mixed-metals",
    ),
    "attire": (
        "traveling-robe",
        "layered-tunic",
        "light-armor",
        "formal-robes",
        "field-clothes",
        "scaled-coat",
        "woven-mantle",
        "ceremonial-vestment",
        "leather-armor",
        "scholar-robes",
    ),
    "motif": (
        "cloud-scroll",
        "constellation",
        "angular-seal",
        "scale-carving",
        "mineral-veining",
        "wave-lines",
        "leaf-embroidery",
        "sunburst",
        "rain-lines",
        "stepped-lines",
        "lacquer-bands",
        "wind-ribbons",
    ),
    "path": ("qi", "body", "mind", "unaffiliated"),
}

ASSET_SPECS = {
    "map_sprite": {
        "folder": "map_sprites",
        "canvas_px": [128, 192],
        "fit_px": [112, 176],
        "aspect_ratio": "2:3 (Portrait Photo)",
        "framing": (
            "one complete standing character viewed from a strict top-down three-quarter angle, "
            "facing north, feet visible, clear readable silhouette, centered with a bottom-center "
            "ground pivot"
        ),
    },
    "dialogue_portrait": {
        "folder": "dialogue_portraits",
        "canvas_px": [384, 512],
        "legacy_canvas_px": [[512, 512]],
        "fit_px": [352, 480],
        "aspect_ratio": "3:4 (Portrait Standard)",
        "framing": (
            "one head-and-shoulders dialogue portrait, front or gentle three-quarter view, "
            "face and expression clearly readable, shoulders included"
        ),
    },
}
VALID_ROLES = {"pc", "npc", "boss"}
CHARACTER_NEGATIVE = (
    "text, letters, watermark, border, UI, extra people, duplicate face, missing limbs, "
    "photorealism, 3D render, noisy texture, suggestive clothing, cleavage, large breasts, "
    "sexualized proportions, exposed chest, bare shoulders, strapless, low neckline, "
    "nudity, child, teen, childlike features"
)


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "character_assets", help="plan and generate private character art and diversity reports"
    )
    actions = parser.add_subparsers(dest="character_assets_action", required=True)
    scaffold = actions.add_parser("scaffold", help="create a balanced catalog of 2,000+ profiles")
    scaffold.add_argument("--count", type=int, default=MIN_CHARACTERS)
    actions.add_parser("report", help="report character, tag, and asset-slot coverage")
    actions.add_parser("audit", help="validate catalog tags and installed image files")
    next_assets = actions.add_parser("next", help="prioritize ungenerated character asset slots")
    next_assets.add_argument("--count", type=int, default=12)
    next_assets.add_argument("--slot", choices=tuple(ASSET_SPECS))
    preview = actions.add_parser("preview", help="build a contact sheet of installed character art")
    preview.add_argument("--slot", choices=tuple(ASSET_SPECS), default="dialogue_portrait")
    preview.add_argument("--limit", type=int, default=64)
    approve = actions.add_parser("approve", help="mark a generated image visually reviewed")
    approve.add_argument("--character-id", required=True)
    approve.add_argument("--slot", choices=tuple(ASSET_SPECS), required=True)
    generate = actions.add_parser("generate", help="generate and install one character asset")
    _add_generation_arguments(generate)
    install = actions.add_parser(
        "install", help="normalize and register an existing transparent PNG"
    )
    install.add_argument("--character-id", required=True)
    install.add_argument("--slot", choices=tuple(ASSET_SPECS), required=True)
    install.add_argument("--source", required=True, help="existing transparent PNG")
    install.add_argument("--prompt", required=True, help="exact prompt or source description")
    install.add_argument("--source-name", required=True, help="generation tool/model")
    install.add_argument(
        "--license", required=True, help="license or generated-media terms to record"
    )
    install.add_argument("--seed", type=int)
    install.add_argument("--replace-generated", action="store_true")


def _add_generation_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--character-id", required=True)
    parser.add_argument("--slot", choices=tuple(ASSET_SPECS), required=True)
    parser.add_argument("--detail", default="", help="optional character-specific prompt detail")
    parser.add_argument(
        "--profile",
        choices=tuple(CHARACTER_PROFILES),
        default=CHARACTER_DEFAULT_PROFILE,
        help="default Krea2; flux1s remains available for comparison",
    )
    parser.add_argument(
        "--seed",
        type=int,
        help="defaults to a stable character identity seed shared across its asset slots",
    )
    parser.add_argument(
        "--aspect-ratio",
        choices=CHARACTER_ASPECT_RATIOS,
        help="defaults to 2:3 for map sprites and 3:4 for dialogue portraits",
    )
    parser.add_argument(
        "--megapixels", type=float, default=2.0, help="target render size in megapixels"
    )
    parser.add_argument(
        "--multiple", type=int, default=32, help="round output dimensions to this multiple"
    )
    parser.add_argument("--steps", type=int)
    parser.add_argument("--cfg", type=float)
    parser.add_argument("--guidance", type=float)
    parser.add_argument("--checkpoint")
    parser.add_argument("--lora", help="Flux LoRA; Krea2 uses its three built-in LoRAs")
    parser.add_argument("--lora-strength", type=float, help="Flux LoRA strength")
    parser.add_argument("--lora-painterly-strength", type=float, default=0.0)
    parser.add_argument("--lora-dishwasher-strength", type=float, default=1.0)
    parser.add_argument("--lora-meion-strength", type=float, default=1.0)
    parser.add_argument("--negative", default=CHARACTER_NEGATIVE)
    parser.add_argument("--rembg-model", help="ComfyUI background-removal model")
    parser.add_argument("--comfy-url", default="http://127.0.0.1:8188")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--preview-only", action="store_true")
    parser.add_argument("--replace-generated", action="store_true")


def run(args) -> int:
    action = args.character_assets_action
    if action == "scaffold":
        _scaffold(args.count)
        return 0
    records = _load_index()
    if action == "report":
        _report(records)
        return 0
    if action == "audit":
        issues = _validate(records, check_files=True)
        if issues:
            for issue in issues:
                fail(issue)
            fail(f"character asset audit failed: {len(issues)} issue(s)")
            return 1
        ok(f"character asset audit complete ({len(records)} profiles)")
        return 0
    structure_issues = _validate(records, check_files=False)
    if structure_issues:
        raise ToolError(
            f"invalid character catalog ({len(structure_issues)} issue(s)); "
            "run character_assets audit for details"
        )
    if action == "next":
        _next(records, args.count, args.slot)
        return 0
    if action == "preview":
        _preview(records, args.slot, args.limit)
        return 0
    if action == "approve":
        _approve(records, args.character_id, args.slot)
        return 0
    if action == "install":
        _install(
            args.character_id,
            args.slot,
            Path(args.source),
            args.prompt,
            args.source_name,
            args.license,
            args.seed,
            args.replace_generated,
        )
        return 0
    if action == "generate":
        _generate(records, args)
        return 0
    raise ToolError(f"unknown character asset action: {action}")


def _scaffold(count: int) -> None:
    if count < MIN_CHARACTERS:
        raise ToolError(f"--count must be at least {MIN_CHARACTERS}")
    if count > MAX_CHARACTERS:
        raise ToolError(f"--count must be no more than {MAX_CHARACTERS}")
    if INDEX_PATH.exists():
        raise ToolError(f"refusing to overwrite private character catalog: {INDEX_PATH}")
    balanced_axes: dict[str, list[str]] = {}
    for axis, values in TRAIT_AXES.items():
        permutations = []
        cycles = (count + len(values) - 1) // len(values)
        for cycle in range(cycles):
            shuffled = list(values)
            random.Random(f"chaos-world:{axis}:{cycle}").shuffle(shuffled)
            permutations.extend(shuffled)
        balanced_axes[axis] = permutations[:count]
    records = []
    for number in range(1, count + 1):
        tags = [f"{axis}:{balanced_axes[axis][number - 1]}" for axis in TRAIT_AXES]
        character_id = f"character-{number:04d}"
        records.append(
            {
                "id": character_id,
                "roles": ["pc", "npc", "boss"],
                "tags": tags,
                "assets": {slot: {"status": "planned", "path": None} for slot in ASSET_SPECS},
            }
        )
    issues = _validate(records, check_files=False)
    if issues:
        raise ToolError("generated catalog failed validation: " + "; ".join(issues[:5]))
    _atomic_write(records)
    ok(
        f"created {INDEX_PATH.relative_to(REPO_ROOT).as_posix()} with {count} profiles, "
        f"{len(ASSET_SPECS)} private asset slots each"
    )


def _load_index() -> list[dict]:
    if not INDEX_PATH.is_file():
        raise ToolError(
            f"private character catalog not found; run character_assets scaffold: {INDEX_PATH}"
        )
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


def _validate(records: list[dict], *, check_files: bool) -> list[str]:
    issues: list[str] = []
    if len(records) < MIN_CHARACTERS:
        issues.append(f"{len(records)} character profiles; minimum is {MIN_CHARACTERS}")
    seen: set[str] = set()
    signatures: set[tuple[str, ...]] = set()
    for index, record in enumerate(records, 1):
        label = f"profile line {index}"
        character_id = record.get("id")
        if not isinstance(character_id, str) or not CHARACTER_ID_RE.fullmatch(character_id):
            issues.append(f"{label}: invalid character id {character_id!r}")
        elif character_id in seen:
            issues.append(f"{label}: duplicate id '{character_id}'")
        else:
            seen.add(character_id)
        roles = record.get("roles")
        if (
            not isinstance(roles, list)
            or not roles
            or any(not isinstance(role, str) for role in roles)
            or set(roles) - VALID_ROLES
        ):
            issues.append(f"{label}: roles must be a non-empty subset of {sorted(VALID_ROLES)}")
        tags = record.get("tags")
        values: dict[str, str] = {}
        if not isinstance(tags, list):
            issues.append(f"{label}: tags must be a list")
            tags = []
        for tag in tags:
            if not isinstance(tag, str) or ":" not in tag:
                issues.append(f"{label}: invalid tag {tag!r}")
                continue
            axis, value = tag.split(":", 1)
            if axis not in TRAIT_AXES or value not in TRAIT_AXES.get(axis, ()):
                issues.append(f"{label}: unknown tag '{tag}'")
            elif axis in values:
                issues.append(f"{label}: repeated tag axis '{axis}'")
            else:
                values[axis] = value
        missing_axes = set(TRAIT_AXES) - values.keys()
        if missing_axes:
            issues.append(f"{label}: missing tag axes {', '.join(sorted(missing_axes))}")
        signatures.add(tuple(f"{axis}:{values[axis]}" for axis in sorted(values)))
        assets = record.get("assets")
        if not isinstance(assets, dict) or set(assets) != set(ASSET_SPECS):
            issues.append(f"{label}: assets must include exactly {', '.join(ASSET_SPECS)}")
            continue
        for slot, spec in ASSET_SPECS.items():
            asset = assets[slot]
            status = asset.get("status") if isinstance(asset, dict) else None
            if not isinstance(status, str) or status not in {"planned", "generated", "approved"}:
                issues.append(f"{label}: {slot} has an invalid status")
                continue
            path = asset.get("path")
            if status == "planned" and path is not None:
                issues.append(f"{label}: planned {slot} must not name an installed path")
            if status != "planned":
                if not isinstance(path, str) or not path.startswith("res://assets/characters/"):
                    issues.append(f"{label}: installed {slot} needs a private res:// path")
                elif check_files:
                    issues.extend(_validate_image(path, spec, f"{character_id} {slot}"))
                for field in ("source", "prompt", "generated_on", "license"):
                    value = asset.get(field)
                    if not isinstance(value, str) or not value.strip():
                        issues.append(f"{label}: installed {slot} is missing {field} provenance")
    if len(signatures) != len(records):
        issues.append(f"{len(signatures)} unique visual profiles for {len(records)} characters")
    return issues


def _validate_image(path: str, spec: dict, label: str) -> list[str]:
    local_path = (GAME_DIR / path.removeprefix("res://")).resolve()
    if not local_path.is_relative_to(CHARACTER_ROOT.resolve()):
        return [f"{label}: asset path escapes the private character asset folder"]
    if not local_path.is_file():
        return [f"{label}: generated image is missing ({path})"]
    try:
        with Image.open(local_path) as opened:
            accepted_sizes = [spec["canvas_px"], *spec.get("legacy_canvas_px", [])]
            if list(opened.size) not in accepted_sizes:
                return [
                    f"{label}: expected one of {accepted_sizes}, found "
                    f"{[opened.width, opened.height]}"
                ]
            image = opened.convert("RGBA")
            if image.getchannel("A").getextrema()[0] != 0:
                return [f"{label}: image needs transparent pixels"]
    except OSError:
        return [f"{label}: generated PNG cannot be opened"]
    return []


def _report(records: list[dict]) -> None:
    issues = _validate(records, check_files=True)
    print(f"character profiles: {len(records)} | target: {MIN_CHARACTERS}+")
    signatures = {
        json.dumps(record.get("tags", []), ensure_ascii=False, sort_keys=True) for record in records
    }
    print(f"unique visual profiles: {len(signatures)}")
    role_counts = Counter(
        role
        for record in records
        for role in (record.get("roles", []) if isinstance(record.get("roles"), list) else [])
        if isinstance(role, str)
    )
    print(
        "role eligibility: "
        + ", ".join(f"{role}={role_counts[role]}" for role in sorted(VALID_ROLES))
    )
    print(f"private catalog: {INDEX_PATH.relative_to(REPO_ROOT).as_posix()}")
    for slot in ASSET_SPECS:
        counts = Counter()
        for record in records:
            assets = record.get("assets")
            asset = assets.get(slot) if isinstance(assets, dict) else None
            status = asset.get("status") if isinstance(asset, dict) else None
            counts[status if isinstance(status, str) else "invalid"] += 1
        print(
            f"{slot}: "
            + " | ".join(
                f"{status} {counts[status]}" for status in ("approved", "generated", "planned")
            )
        )
    print("tag distribution:")
    distributions: dict[str, Counter] = {axis: Counter() for axis in TRAIT_AXES}
    for record in records:
        tags = record.get("tags", [])
        for tag in tags if isinstance(tags, list) else []:
            if isinstance(tag, str) and ":" in tag:
                axis, value = tag.split(":", 1)
                if axis in distributions:
                    distributions[axis][value] += 1
    for axis, values in distributions.items():
        print(f"  {axis}: " + ", ".join(f"{value}={values[value]}" for value in TRAIT_AXES[axis]))
    if issues:
        print(f"audit findings: {len(issues)} (run character_assets audit for details)")
    else:
        ok("character asset catalog audit complete")


def _next(records: list[dict], count: int, slot_filter: str | None) -> None:
    if count < 1:
        raise ToolError("--count must be at least 1")
    done: dict[str, Counter] = {slot: Counter() for slot in ASSET_SPECS}
    for record in records:
        for slot, asset in record.get("assets", {}).items():
            if slot in done and asset.get("status") in {"generated", "approved"}:
                for tag in record.get("tags", []):
                    if isinstance(tag, str):
                        done[slot][tag] += 1
    slot_done = Counter()
    slot_totals = Counter()
    for record in records:
        for slot, asset in record.get("assets", {}).items():
            if slot in ASSET_SPECS:
                slot_totals[slot] += 1
                if asset.get("status") in {"generated", "approved"}:
                    slot_done[slot] += 1
    candidates = []
    for record in records:
        for slot in ASSET_SPECS:
            asset = record.get("assets", {}).get(slot, {})
            if (slot_filter is None or slot == slot_filter) and asset.get("status") == "planned":
                candidates.append((slot, record))
    if not candidates:
        raise ToolError("no planned character asset slots match the selected filter")
    selected = []
    for _ in range(min(count, len(candidates))):

        def priority(candidate: tuple[str, dict]) -> tuple[float, int, str, str]:
            slot, record = candidate
            slot_progress = slot_done[slot] / slot_totals[slot] if slot_totals[slot] else 0.0
            coverage = sum(done[slot][tag] for tag in record["tags"])
            return slot_progress, coverage, slot, record["id"]

        chosen = min(candidates, key=priority)
        candidates.remove(chosen)
        slot, record = chosen
        selected.append((slot, record))
        slot_done[slot] += 1
        for tag in record["tags"]:
            done[slot][tag] += 1
    print(f"next {len(selected)} planned character assets (balanced slot and tag coverage):")
    for slot, record in selected:
        print(f"  {record['id']} | {slot} | {', '.join(record['tags'])}")


def _generate(records: list[dict], args) -> None:
    profile_defaults = CHARACTER_PROFILES[args.profile]
    for name, value in profile_defaults.items():
        if getattr(args, name, None) is None:
            setattr(args, name, value)
    args.sampler = profile_defaults["sampler"]
    args.scheduler = profile_defaults["scheduler"]
    if args.profile == "krea2":
        args.lora = ""
        args.lora_strength = 0.0
    record = _character(records, args.character_id)
    slot_spec = ASSET_SPECS[args.slot]
    args.aspect_ratio = args.aspect_ratio or slot_spec["aspect_ratio"]
    if not math.isfinite(args.megapixels) or not 0.1 <= args.megapixels <= 16:
        raise ToolError("--megapixels must be between 0.1 and 16")
    if not 8 <= args.multiple <= 128 or args.multiple % 4:
        raise ToolError("--multiple must be a multiple of 4 between 8 and 128")
    args.render_width, args.render_height = _render_dimensions(
        args.aspect_ratio, args.megapixels, args.multiple
    )
    if (
        not 1 <= args.steps <= 64
        or args.cfg < 0
        or (args.guidance is not None and args.guidance < 0)
    ):
        raise ToolError("steps must be 1-64 and cfg/guidance must be non-negative")
    if not 1 <= args.timeout <= 900:
        raise ToolError("timeout must be 1-900 seconds")
    if args.profile == "flux1s" and (
        not math.isfinite(args.lora_strength) or not 0 <= args.lora_strength <= 2
    ):
        raise ToolError("Flux LoRA strength must be between 0 and 2")
    krea2_lora_strengths = (
        args.lora_painterly_strength,
        args.lora_dishwasher_strength,
        args.lora_meion_strength,
    )
    if args.profile == "krea2" and any(
        not math.isfinite(strength) or not 0 <= strength <= 2 for strength in krea2_lora_strengths
    ):
        raise ToolError("Krea2 LoRA strengths must be between 0 and 2")
    if not math.isfinite(args.cfg) or (
        args.guidance is not None and not math.isfinite(args.guidance)
    ):
        raise ToolError("cfg and guidance must be finite numbers")
    if args.seed is not None and not 0 <= args.seed < 2**31:
        raise ToolError("--seed must be between 0 and 2147483647")
    comfy = urllib.parse.urlparse(args.comfy_url)
    if (
        comfy.scheme not in {"http", "https"}
        or not comfy.netloc
        or comfy.username
        or comfy.password
    ):
        raise ToolError("--comfy-url must be an HTTP(S) URL without embedded credentials")
    if not args.checkpoint.strip() or (args.profile == "flux1s" and not args.rembg_model.strip()):
        raise ToolError("checkpoint and selected background-removal settings must be non-empty")
    asset = record["assets"][args.slot]
    replacing = args.replace_generated and asset["status"] == "generated"
    if asset["status"] != "planned" and not replacing:
        raise ToolError(f"refusing to replace {args.character_id}/{args.slot} ({asset['status']})")
    seed = args.seed if args.seed is not None else _stable_seed(args.character_id)
    prompt = _prompt(record, args.slot, args.detail)
    if args.profile == "krea2":
        prompt = prompt.replace(
            "Transparent background.",
            "A perfectly flat pure white background with no gradient, shadow, texture, "
            "or scenery. Keep a crisp clear edge around the figure.",
        )
    raw_path = _generate_comfy(record, args, prompt, seed)
    if args.preview_only:
        ok(f"generated private preview only; catalog unchanged ({raw_path.relative_to(REPO_ROOT)})")
        return
    _install(
        args.character_id,
        args.slot,
        raw_path,
        prompt,
        _generation_source(args),
        "Generated locally; source checkpoint and LoRA license terms apply",
        seed,
        replacing,
        generation_settings={
            "profile": args.profile,
            "checkpoint": args.checkpoint,
            "lora": args.lora,
            "lora_strength": args.lora_strength,
            "lora_names": (
                {
                    "painterly": map_generate.KREA2_LORAS[0],
                    "dishwasher": map_generate.KREA2_LORAS[1],
                    "meion": map_generate.KREA2_LORAS[2],
                }
                if args.profile == "krea2"
                else {}
            ),
            "lora_strengths": _profile_lora_strengths(args),
            "aspect_ratio": args.aspect_ratio,
            "megapixels": args.megapixels,
            "multiple": args.multiple,
            "render_width": args.render_width,
            "render_height": args.render_height,
            "steps": args.steps,
            "cfg": args.cfg,
            "guidance": args.guidance,
            "sampler": args.sampler,
            "scheduler": args.scheduler,
            "seed": seed,
            "background_removal": args.rembg_model,
        },
    )


def _profile_lora_strengths(args) -> dict[str, float]:
    if args.profile != "krea2":
        return {}
    return {
        "painterly": args.lora_painterly_strength,
        "dishwasher": args.lora_dishwasher_strength,
        "meion": args.lora_meion_strength,
    }


def _render_dimensions(aspect_ratio: str, megapixels: float, multiple: int) -> tuple[int, int]:
    ratio = aspect_ratio.split(" ", 1)[0]
    ratio_width, ratio_height = (float(part) for part in ratio.split(":"))
    ratio_value = ratio_width / ratio_height
    area = megapixels * 1_000_000
    width = math.sqrt(area * ratio_value)
    height = math.sqrt(area / ratio_value)
    return tuple(
        max(multiple, int(round(value / multiple) * multiple)) for value in (width, height)
    )


def _generation_source(args) -> str:
    if args.profile == "krea2":
        weights = _profile_lora_strengths(args)
        return (
            f"ComfyUI Krea2 checkpoint: {args.checkpoint}; LoRAs: "
            f"painterly={weights['painterly']}, dishwasher={weights['dishwasher']}, "
            f"meion={weights['meion']}"
        )
    return f"ComfyUI checkpoint: {args.checkpoint}; LoRA: {args.lora}"


def _generate_comfy(record: dict, args, prompt: str, seed: int) -> Path:
    output_node = "7"
    if args.profile == "krea2":
        graph = copy.deepcopy(map_generate.KREA2_ITEM_WORKFLOW)
        graph["761"]["inputs"]["unet_name"] = args.checkpoint
        graph["627"]["inputs"]["text"] = prompt
        graph["627"]["inputs"]["clip"] = ["755", 0]
        graph["763"] = {
            "inputs": {"text": args.negative, "clip": ["755", 0]},
            "class_type": "CLIPTextEncode",
        }
        graph["599"]["inputs"]["negative"] = ["763", 0]
        graph["857"] = {
            "inputs": {
                "aspect_ratio": args.aspect_ratio,
                "megapixels": args.megapixels,
                "multiple": args.multiple,
            },
            "class_type": "ResolutionSelector",
        }
        graph["698"]["inputs"].update(width=["857", 0], height=["857", 1])
        graph["851"]["inputs"]["seed"] = seed
        graph["599"]["inputs"].update(
            steps=args.steps,
            cfg=args.cfg,
            sampler_name=args.sampler,
            scheduler=args.scheduler,
            end_at_step=args.steps,
        )
        for node_id, strength in (
            ("868", args.lora_painterly_strength),
            ("867", args.lora_dishwasher_strength),
            ("854", args.lora_meion_strength),
        ):
            graph[node_id]["inputs"]["strength_model"] = strength
        graph["866"]["inputs"].update(
            model=args.rembg_model,
            transparency=True,
            post_processing=True,
            alpha_matting=True,
            alpha_matting_foreground_threshold=240,
            alpha_matting_background_threshold=10,
            alpha_matting_erode_size=4,
            background_color="none",
        )
        output_node = "732"
    else:
        graph = copy.deepcopy(map_generate.WORKFLOW)
        graph["1"]["inputs"]["ckpt_name"] = args.checkpoint
        if args.lora.strip():
            graph["10"] = {
                "inputs": {
                    "model": ["1", 0],
                    "clip": ["12", 0],
                    "lora_name": args.lora.strip(),
                    "strength_model": args.lora_strength,
                    "strength_clip": args.lora_strength,
                },
                "class_type": "LoraLoader",
            }
        graph["2"]["inputs"].update(t5xxl=prompt, guidance=args.guidance)
        graph["3"]["inputs"].update(clip_l=args.negative, guidance=args.guidance)
        graph["4"]["inputs"].update(width=args.render_width, height=args.render_height)
        graph["8"]["inputs"].update(
            noise_seed=seed,
            steps=args.steps,
            cfg=args.cfg,
            sampler_name=args.sampler,
            scheduler=args.scheduler,
        )
        graph["15"]["inputs"].update(model=args.rembg_model, transparency=True)
    source_path = (
        REPO_ROOT
        / "build"
        / "character-generated"
        / f"{record['id']}-{args.slot}-{args.profile}-{seed}.png"
    )
    source_path.parent.mkdir(parents=True, exist_ok=True)
    if source_path.exists():
        raise ToolError(f"refusing to overwrite generated source: {source_path}")
    base_url = args.comfy_url.rstrip("/")
    response = _http_json(
        f"{base_url}/prompt", {"prompt": graph, "client_id": "chaos-world-characters"}
    )
    prompt_id = response.get("prompt_id")
    if not prompt_id:
        raise ToolError(f"ComfyUI did not return a prompt_id: {response}")
    print(f"[character generate] submitted prompt_id={prompt_id}")
    deadline = time.monotonic() + args.timeout
    entry = None
    while time.monotonic() < deadline:
        history = _http_json(f"{base_url}/history/{urllib.parse.quote(prompt_id)}")
        entry = history.get(prompt_id)
        if entry:
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise ToolError(f"ComfyUI generation failed: {status.get('messages', status)}")
            if status.get("completed"):
                break
        time.sleep(min(2, max(0, deadline - time.monotonic())))
    else:
        raise ToolError(f"ComfyUI generation exceeded {args.timeout} seconds")
    image = _node_image(entry or {}, output_node)
    image_url = f"{base_url}/view?{urllib.parse.urlencode(image)}"
    _write_new_file(source_path, _http_bytes(image_url))
    return source_path


def _prompt(record: dict, slot: str, detail: str) -> str:
    traits = dict(tag.split(":", 1) for tag in record["tags"])
    presentation = {
        "masculine": "an adult man with unmistakably masculine facial features and grooming",
        "feminine": "an adult woman with clearly feminine facial features and grooming",
        "androgynous": "an adult with clearly gender-neutral facial features and grooming",
    }[traits["presentation"]]
    age = {
        "young-adult": "a young adult in their mid-20s with mature adult proportions",
        "adult": "an adult aged 35 to 50 with mature facial proportions",
        "elder": (
            "an elder aged 65 or older, with visible lines at the brow, eyes, and mouth "
            "and mature facial structure"
        ),
    }[traits["age"]]
    race = {
        "human": "human anatomy",
        "beastkin": "subtle animal ears and a short tail from one coherent animal type",
        "spiritkin": "humanlike anatomy with subtle luminous spirit marks at the temples",
        "dragonkin": "small swept horns, fine scales at the temples and forearms, and a slim tail",
        "aquatic": "subtle gill marks at the neck and slight webbing between the fingers",
        "celestial": "humanlike anatomy with faint star-flecked eyes and a restrained "
        "celestial mark",
        "revenant": "cool pallor and faint spectral edge-light, with no decay or skeletal features",
        "elemental": "a living elemental appearance with complexion-colored material "
        "accents and a few motes",
        "plantkin": "leaf-veined skin at the temples and hands, with no bulky plant growth",
        "stonekin": "stone-grain complexion and fine mineral veining, while retaining "
        "flexible humanlike features",
    }[traits["race"]]
    path = {
        "qi": "Qi Dao: creation through energy; show controlled motion and "
        "restrained flowing energy marks",
        "body": "Body Dao: preservation through form; use a grounded stance and "
        "practical, enduring construction",
        "mind": "Mind Dao: transcendence through spirit; use a focused gaze and "
        "subtle awareness motifs",
        "unaffiliated": "an independent Mortal Plains traveler, with practical travel "
        "wear and no sect insignia",
    }[traits["path"]]
    visual_traits = (
        f"{traits['build']} build, {traits['complexion']} complexion, {traits['hair_color']} hair "
        f"in a {traits['hairstyle']} style, {traits['eyes']} eyes, {traits['palette']} palette, "
        f"{traits['attire']} with a restrained {traits['motif']} motif"
    )
    framing = ASSET_SPECS[slot]["framing"]
    extra = f" Character-specific detail: {detail.strip()}." if detail.strip() else ""
    return (
        f"One adult character, identity {record['id']}: {age}; {presentation}; {race}. "
        f"Preserve exactly these visible traits: {visual_traits}. "
        f"Cultural and cultivation cue: {path}.{extra} {framing}. "
        "One subject only. Cultivation-fantasy production art for a 2D action RPG. "
        "Painterly anime illustration in matte gouache, fine dark ink contours, broad readable "
        "value planes, material-led color, restrained metallic accents, soft upper-left light. "
        "Use a loose-fitting, opaque, high-necked robe with a closed collar, long sleeves, and "
        "covered shoulders. Keep all torso skin covered. No garment cutouts, short hems, or "
        "transparent fabric. Use the same visual identity and costume across the character asset "
        "family. Keep the face, age, presentation, anatomy, palette, and costume faithful to the "
        "profile. Use a neutral upright pose with arms at the sides. Transparent "
        "background. All characters are adults, fully clothed, and nonsexual. No text, "
        "labels, UI, frame, watermark, extra figures, unrelated props, exaggerated "
        "body proportions, or childlike features."
    )


def _install(
    character_id: str,
    slot: str,
    source: Path,
    prompt: str,
    source_name: str,
    license_text: str,
    seed: int | None,
    replace_generated: bool,
    *,
    generation_settings: dict | None = None,
) -> None:
    original_records = _load_index()
    catalog_issues = _validate(original_records, check_files=False)
    if catalog_issues:
        raise ToolError(f"invalid character catalog ({len(catalog_issues)} issue(s))")
    original = _character(original_records, character_id)
    original_asset = original["assets"][slot]
    replacing = replace_generated and original_asset["status"] == "generated"
    if original_asset["status"] != "planned" and not replacing:
        raise ToolError(f"refusing to replace {character_id}/{slot} ({original_asset['status']})")
    if not source.is_file() or source.suffix.lower() != ".png":
        raise ToolError(f"source must be an existing PNG: {source}")
    if not prompt.strip() or not source_name.strip() or not license_text.strip():
        raise ToolError("prompt, source name, and license terms must be non-empty")
    if seed is not None and not 0 <= seed < 2**31:
        raise ToolError("seed must be between 0 and 2147483647")
    seed_part = f"-{seed}" if seed is not None else f"-{secrets.token_hex(4)}"
    spec = ASSET_SPECS[slot]
    filename = f"{character_id}{seed_part}.png"
    output_path = (CHARACTER_ROOT / spec["folder"] / filename).resolve()
    if not output_path.is_relative_to(CHARACTER_ROOT.resolve()):
        raise ToolError("asset output must stay under the private character asset folder")
    if output_path.exists():
        raise ToolError(f"refusing to overwrite existing character art: {output_path}")

    canvas = _normalize(source, spec)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = None
    created_output = False
    try:
        descriptor = os.open(output_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        created_output = True
        with os.fdopen(descriptor, "wb") as output:
            descriptor = None
            canvas.save(output, format="PNG", optimize=True)
        current_records = _load_index()
        current = _character(current_records, character_id)
        if current.get("tags") != original.get("tags"):
            raise ToolError(f"{character_id} visual profile changed while generating")
        current_asset = current["assets"][slot]
        if current_asset["status"] != "planned" and not (
            replacing and current_asset["status"] == "generated"
        ):
            raise ToolError(f"{character_id}/{slot} changed while generating")
        current_asset.update(
            status="generated",
            path=f"res://assets/characters/{spec['folder']}/{filename}",
            source=source_name,
            prompt=prompt,
            generated_on=datetime.now(UTC).date().isoformat(),
            license=license_text,
            seed=seed,
            generation_settings=generation_settings or {},
        )
        _atomic_write(current_records)
    except Exception:
        if created_output:
            output_path.unlink(missing_ok=True)
        raise
    finally:
        if descriptor is not None:
            os.close(descriptor)
    ok(
        f"installed private {character_id}/{slot} at "
        f"{output_path.relative_to(REPO_ROOT).as_posix()}"
    )


def _normalize(source: Path, spec: dict) -> Image.Image:
    try:
        with Image.open(source) as opened:
            if (
                opened.width > 8192
                or opened.height > 8192
                or opened.width * opened.height > 32_000_000
            ):
                raise ToolError(f"source image dimensions are too large: {opened.size}")
            image = opened.convert("RGBA")
    except OSError as exc:
        raise ToolError(f"source PNG cannot be opened: {source}") from exc
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ToolError(f"source image is fully transparent: {source}")
    if alpha.getextrema()[0] != 0:
        raise ToolError(f"source image has no transparent pixels: {source}")
    image = image.crop(bounds)
    image.thumbnail(tuple(spec["fit_px"]), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", tuple(spec["canvas_px"]), (0, 0, 0, 0))
    if spec["folder"] == "map_sprites":
        offset = ((canvas.width - image.width) // 2, canvas.height - image.height)
    else:
        offset = ((canvas.width - image.width) // 2, (canvas.height - image.height) // 2)
    canvas.alpha_composite(image, offset)
    return canvas


def _approve(records: list[dict], character_id: str, slot: str) -> None:
    record = _character(records, character_id)
    asset = record["assets"][slot]
    if asset["status"] != "generated":
        raise ToolError(f"only generated assets can be approved ({character_id}/{slot})")
    findings = _validate_image(asset["path"], ASSET_SPECS[slot], f"{character_id} {slot}")
    if findings:
        raise ToolError("cannot approve invalid image: " + "; ".join(findings))
    asset["status"] = "approved"
    asset["approved_on"] = datetime.now(UTC).date().isoformat()
    _atomic_write(records)
    ok(f"approved {character_id}/{slot} after image and dimension checks")


def _preview(records: list[dict], slot: str, limit: int) -> None:
    if not 1 <= limit <= 256:
        raise ToolError("--limit must be between 1 and 256")
    ready = [
        record
        for record in records
        if record.get("assets", {}).get(slot, {}).get("status") in {"generated", "approved"}
    ][:limit]
    if not ready:
        raise ToolError(f"no generated {slot} images to preview")
    columns, cell, image_size, label_height = 4, 192, 160, 32
    rows = (len(ready) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cell, rows * (image_size + label_height)), (38, 42, 48))
    font = ImageFont.load_default()
    for index, record in enumerate(ready):
        asset = record["assets"][slot]
        findings = _validate_image(asset["path"], ASSET_SPECS[slot], f"{record['id']} {slot}")
        if findings:
            raise ToolError("cannot preview invalid image: " + "; ".join(findings))
        path = GAME_DIR / asset["path"].removeprefix("res://")
        with Image.open(path) as opened:
            foreground = opened.convert("RGBA")
        foreground.thumbnail((image_size, image_size), Image.Resampling.LANCZOS)
        checker = Image.new("RGBA", (image_size, image_size), (230, 230, 230, 255))
        draw = ImageDraw.Draw(checker)
        size = 16
        for cy in range(0, image_size, size):
            for cx in range(0, image_size, size):
                if (cx // size + cy // size) % 2:
                    draw.rectangle(
                        (cx, cy, cx + size - 1, cy + size - 1), fill=(190, 190, 190, 255)
                    )
        checker.alpha_composite(
            foreground,
            ((image_size - foreground.width) // 2, (image_size - foreground.height) // 2),
        )
        sheet.paste(
            checker.convert("RGB"),
            (
                index % columns * cell + (cell - image_size) // 2,
                index // columns * (image_size + label_height),
            ),
        )
        ImageDraw.Draw(sheet).text(
            (
                index % columns * cell + 8,
                index // columns * (image_size + label_height) + image_size + 4,
            ),
            record["id"],
            fill="white",
            font=font,
        )
    output = REPO_ROOT / "build" / "character-preview" / f"{slot}.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, format="PNG", optimize=True)
    ok(
        f"wrote private preview sheet: {output.relative_to(REPO_ROOT).as_posix()} "
        f"({len(ready)} assets)"
    )


def _character(records: list[dict], character_id: str) -> dict:
    if not CHARACTER_ID_RE.fullmatch(character_id):
        raise ToolError(f"invalid character id '{character_id}'")
    record = next((item for item in records if item.get("id") == character_id), None)
    if record is None:
        raise ToolError(f"unknown character id '{character_id}'")
    return record


def _stable_seed(character_id: str) -> int:
    digest = hashlib.sha256(f"{character_id}:identity".encode()).digest()
    return int.from_bytes(digest[:4], "big") % (2**31)


def _atomic_write(records: list[dict]) -> None:
    INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
    content = "".join(
        json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n" for record in records
    )
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


def _http_json(url: str, payload: dict | None = None) -> dict:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"} if data else {}
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            result = json.load(response)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise ToolError(f"ComfyUI HTTP {exc.code}: {detail[:1000]}") from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise ToolError(f"could not reach ComfyUI at {url}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ToolError(f"ComfyUI returned invalid JSON from {url}") from exc
    return result


def _http_bytes(url: str) -> bytes:
    try:
        with urllib.request.urlopen(url, timeout=120) as response:
            return response.read()
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
        raise ToolError(f"could not fetch generated image from ComfyUI: {exc}") from exc


def _node_image(entry: dict, node_id: str) -> dict:
    node_output = (entry.get("outputs") or {}).get(node_id, {})
    for image in node_output.get("images") or []:
        if image.get("filename"):
            return {
                "filename": image["filename"],
                "subfolder": image.get("subfolder", ""),
                "type": image.get("type", "output"),
            }
    raise ToolError(f"ComfyUI completed without returning an image from node {node_id}")


def _write_new_file(path: Path, data: bytes) -> None:
    descriptor = None
    created = False
    try:
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        created = True
        with os.fdopen(descriptor, "wb") as output:
            descriptor = None
            output.write(data)
    except FileExistsError as exc:
        raise ToolError(f"refusing to overwrite generated source: {path}") from exc
    except OSError as exc:
        if created:
            path.unlink(missing_ok=True)
        raise ToolError(f"could not save generated source: {path}: {exc}") from exc
    finally:
        if descriptor is not None:
            os.close(descriptor)
