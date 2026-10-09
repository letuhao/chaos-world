"""Prepare, install, and audit Celadon Faultlands map assets."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import tempfile
from collections import Counter
from datetime import date
from pathlib import Path

from PIL import Image

from .common import REPO_ROOT, ToolError, ok

GAME_DIR = REPO_ROOT / "game"
PACK_ID = "spirit_world_celadon_faultlands"
PACK_DIR = GAME_DIR / "assets" / "packs" / PACK_ID
PACK_PATH = PACK_DIR / f"{PACK_ID}_pack.json"
DATA_DIR = PACK_DIR / "data"
ORIGINAL_DIR = PACK_DIR / "original"
RUNTIME_DIR = PACK_DIR / "runtime"
LOCK_PATH = REPO_ROOT / "build" / f"{PACK_ID}.lock"
ASSET_ID_RE = re.compile(r"^[a-z0-9_]+(?:\.[a-z0-9_]+)+$")
CATEGORY_ID_RE = re.compile(r"^[a-z0-9_]+$")
ALPHA_CROP_THRESHOLD = 16
SOURCE_MARGIN_PX = 16
SCALES = (0.85, 1.0, 1.15, 1.35, 1.6)


def register(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser(
        "faultlands", help="install and audit Celadon Faultlands map assets"
    )
    actions = parser.add_subparsers(dest="faultlands_action", required=True)
    actions.add_parser("init-data", help="create per-asset JSON records from the pack manifest")
    actions.add_parser("audit", help="check asset, original, runtime, variant, and data mappings")
    install = actions.add_parser(
        "install", help="preserve a source PNG and normalize its runtime copy"
    )
    install.add_argument("--asset-id", required=True)
    install.add_argument("--source", required=True)
    install.add_argument("--source-name", default="OpenAI image_gen")
    install.add_argument(
        "--license", default="Generated for Chaos World under OpenAI service terms"
    )
    install.add_argument("--generated-on", default=date.today().isoformat())
    install.add_argument("--prompt-ref", required=True)
    install.add_argument("--prompt", required=True)
    install.add_argument("--replace-generated", action="store_true")
    prompt = actions.add_parser("prompt", help="print the production prompt for one planned asset")
    prompt.add_argument("--asset-id", required=True)


def run(args: argparse.Namespace) -> int:
    if args.faultlands_action == "init-data":
        _init_data(PACK_DIR)
        return 0
    if args.faultlands_action == "audit":
        findings = _audit(PACK_DIR)
        if findings:
            raise ToolError("Faultlands pack audit failed:\n- " + "\n- ".join(findings))
        ok(f"audited {PACK_ID}: 45 base assets and 4 variant plans")
        return 0
    if args.faultlands_action == "prompt":
        pack = _load_pack(PACK_DIR)
        record = next((item for item in _records(pack) if item.get("id") == args.asset_id), None)
        if record is None:
            raise ToolError(f"unknown Faultlands asset id {args.asset_id!r}")
        if record.get("variant_of"):
            base = next(item for item in pack["assets"] if item["id"] == record["variant_of"])
            if base.get("status") != "generated":
                raise ToolError(f"generate and install base asset {base['id']} before its variant")
            reference_path = _safe_pack_path(PACK_DIR, base["path"], base["id"])
            if not reference_path.is_file():
                raise ToolError(f"base reference image is missing: {reference_path}")
            print(f"Reference image to attach: {reference_path}")
        print(_production_prompt(pack, record))
        return 0
    if args.faultlands_action == "install":
        _install(args, PACK_DIR)
        return 0
    raise ToolError(f"unknown Faultlands action {args.faultlands_action!r}")


def _load_pack(pack_dir: Path) -> dict:
    path = pack_dir / f"{PACK_ID}_pack.json"
    try:
        pack = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ToolError(f"cannot read pack manifest {path}: {exc}") from exc
    if not isinstance(pack, dict) or pack.get("id") != PACK_ID:
        raise ToolError(f"manifest must declare pack id {PACK_ID!r}")
    return pack


def _slug(record: dict) -> str:
    return Path(record["path"].removeprefix("res://")).stem


def _variant_record(pack: dict, plan: dict) -> dict:
    base = next((item for item in pack["assets"] if item["id"] == plan["base_asset_id"]), None)
    if base is None:
        raise ToolError(f"variant {plan.get('id')}: unknown base asset")
    variant = copy.deepcopy(base)
    variant.update(plan)
    if plan.get("status") == "planned":
        for field in (
            "source_path",
            "source_images",
            "generated_on",
            "source",
            "license",
            "prompt_ref",
            "matrix_data",
            "matrix_review",
        ):
            variant.pop(field, None)
    variant.update(
        {
            "name": f"{base['name']} ({plan['state']})",
            "variant_of": base["id"],
            "variant": {"axis": plan["state_axis"], "value": plan["state"]},
            "brief": plan.get(
                "brief", plan.get("variant_brief", plan.get("prompt", base["brief"]))
            ),
        }
    )
    return variant


def _records(pack: dict) -> list[dict]:
    result = list(pack.get("assets", []))
    result.extend(_variant_record(pack, plan) for plan in pack.get("variant_plans", []))
    return result


def _production_prompt(pack: dict, record: dict) -> str:
    transparent = record["alpha"] == "transparent"
    output_alpha = (
        "real transparent PNG alpha outside the complete sprite; no checkerboard or matte"
        if transparent
        else "fully opaque PNG; fill the entire square with the ground surface"
    )
    composition = (
        "one isolated complete map object, readable silhouette, clear ground contact, "
        "transparent padding, honor the indexed pivot"
        if transparent
        else "edge-to-edge ground texture, quiet under gameplay objects, no isolated props"
    )
    tile_rule = (
        "Connect all four edges cleanly for seamless grid repetition. "
        if record.get("type") == "tile"
        else ""
    )
    reference_rule = (
        "Use the attached base-asset image as the reference. Preserve its subject identity, "
        "silhouette, footprint, scale, camera, palette, lighting, and anchor; change only the "
        "state described here. "
        if record.get("variant_of")
        else ""
    )
    brief = record.get("brief", "").strip()
    return "\n".join(
        (
            "Use case: stylized-concept",
            "Asset type: production 2D top-down game-map asset for Chaos World",
            f"Primary request: {reference_rule}{brief}",
            f"Environment: {pack['environment_theme']}",
            "View: strict straight-down orthographic camera; no horizon, isometric angle, or perspective",
            f"Art direction: {pack['art_style']}",
            f"Composition: {composition}. {tile_rule}No frame, text, UI, watermark, or unrelated subject.",
            f"Output: 1024x1024 high-quality PNG source. Runtime target is {record['canvas_px'][0]}x{record['canvas_px'][1]} px.",
            f"Alpha: {output_alpha}.",
            "Use readable material shapes and restrained surface detail that remain clear after downsampling.",
        )
    )


def _data_path(pack_dir: Path, record: dict) -> Path:
    category = record["category"]
    if not isinstance(category, str) or not CATEGORY_ID_RE.fullmatch(category):
        raise ToolError(f"{record.get('id', 'asset')}: invalid category path")
    path = (pack_dir / "data" / category / f"{_slug(record)}.json").resolve()
    if not path.is_relative_to(pack_dir.resolve()):
        raise ToolError(f"{record.get('id', 'asset')}: data path escapes pack directory")
    return path


def _safe_pack_path(pack_dir: Path, path_value: str, label: str) -> Path:
    if not isinstance(path_value, str) or not path_value.strip():
        raise ToolError(f"{label} must be a non-empty path")
    if path_value.startswith("res://"):
        relative = path_value.removeprefix("res://")
        prefix = f"assets/packs/{PACK_ID}/"
        if not relative.startswith(prefix):
            raise ToolError(f"{label} is outside the Faultlands runtime directory")
        target = (pack_dir / relative.removeprefix(prefix)).resolve()
    else:
        target = (pack_dir / path_value).resolve()
    if not target.is_relative_to(pack_dir.resolve()):
        raise ToolError(f"{label} escapes the Faultlands pack directory")
    return target


def _findings(pack: dict, pack_dir: Path, *, verify_data: bool = True) -> list[str]:
    findings: list[str] = []
    bases = pack.get("assets")
    variants = pack.get("variant_plans")
    if not isinstance(bases, list) or len(bases) != 45:
        findings.append("manifest must contain exactly 45 base asset records")
        bases = bases if isinstance(bases, list) else []
    if not isinstance(variants, list) or len(variants) != 4:
        findings.append("manifest must contain exactly 4 selective variant plans")
        variants = variants if isinstance(variants, list) else []
    if pack.get("asset_count") != len(bases):
        findings.append("asset_count does not match base asset records")
    if pack.get("variant_count") != len(variants):
        findings.append("variant_count does not match variant plans")
    source_policy = pack.get("source_policy")
    if (
        not isinstance(source_policy, dict)
        or source_policy.get("keep_original_unchanged") is not True
    ):
        findings.append("source_policy must preserve originals unchanged")
    elif source_policy.get("source_render_minimum_px") != [1024, 1024]:
        findings.append("source_policy must require at least 1024x1024 source renders")
    if (
        not isinstance(source_policy, dict)
        or source_policy.get("exclude_original_from_engine_import") is not True
    ):
        findings.append("source_policy must keep original renders out of Godot imports")
    if not (pack_dir / "original" / ".gdignore").is_file():
        findings.append(
            "original/.gdignore is required to exclude source renders from Godot imports"
        )
    category_ids = pack.get("categories")
    if not isinstance(category_ids, list) or not all(
        isinstance(item, str) and CATEGORY_ID_RE.fullmatch(item) for item in category_ids
    ):
        findings.append("categories must be a list of category ids")
        category_ids = []
    expected_categories = set(category_ids)
    category_file = pack_dir / "categories.json"
    try:
        category_data = json.loads(category_file.read_text(encoding="utf-8"))
        category_counts = {item["id"]: item["planned_count"] for item in category_data}
        if set(category_counts) != expected_categories:
            findings.append("categories.json ids do not match manifest categories")
        actual_counts = Counter(item.get("category") for item in bases if isinstance(item, dict))
        for category in expected_categories:
            if category_counts.get(category) != actual_counts.get(category, 0):
                findings.append(
                    f"{category}: categories.json planned_count disagrees with manifest"
                )
    except (OSError, json.JSONDecodeError, KeyError, TypeError):
        findings.append("categories.json is missing or invalid")
    ids: set[str] = set()
    for record in _records(pack):
        asset_id = record.get("id")
        if not isinstance(asset_id, str) or not ASSET_ID_RE.fullmatch(asset_id):
            findings.append(f"invalid asset id {asset_id!r}")
            continue
        if asset_id in ids:
            findings.append(f"duplicate asset id {asset_id}")
        ids.add(asset_id)
        category = record.get("category")
        if category not in expected_categories:
            findings.append(f"{asset_id}: category is not declared by the pack")
            continue
        if record.get("status") not in ("planned", "generated"):
            findings.append(f"{asset_id}: unsupported status {record.get('status')!r}")
        canvas = record.get("canvas_px")
        footprint = record.get("footprint_cells")
        if not _positive_pair(canvas) or not _positive_pair(footprint):
            findings.append(f"{asset_id}: canvas_px and footprint_cells must be positive pairs")
            continue
        if record.get("alpha") not in ("opaque", "transparent"):
            findings.append(f"{asset_id}: alpha must be opaque or transparent")
        try:
            runtime_path = _safe_pack_path(pack_dir, record.get("path"), f"{asset_id}.path")
        except ToolError as exc:
            findings.append(str(exc))
            continue
        data_path = _data_path(pack_dir, record)
        if record.get("status") == "planned":
            if runtime_path.exists():
                findings.append(f"{asset_id}: planned asset already has a runtime PNG")
        else:
            if not runtime_path.is_file():
                findings.append(f"{asset_id}: generated runtime PNG is missing")
            else:
                findings.extend(_image_findings(record, runtime_path, asset_id))
            try:
                source_images = record.get("source_images")
                if not isinstance(source_images, list) or not source_images:
                    findings.append(f"{asset_id}: generated asset has no source_images mapping")
                else:
                    for source in source_images:
                        findings.extend(_source_findings(source, asset_id))
                    latest_path = source_images[-1].get("path")
                    pack_prefix = f"game/assets/packs/{PACK_ID}/"
                    expected_source_path = (
                        latest_path.removeprefix(pack_prefix)
                        if isinstance(latest_path, str)
                        else None
                    )
                    if record.get("source_path") != expected_source_path:
                        findings.append(
                            f"{asset_id}: source_path does not map to latest source image"
                        )
                    latest = source_images[-1]
                    expected_name = f"{_slug(record)}--{latest.get('sha256', '')[:12]}.png"
                    expected_repo_path = (
                        f"{pack_prefix}original/{record['category']}/{expected_name}"
                    )
                    if latest_path != expected_repo_path:
                        findings.append(
                            f"{asset_id}: original path does not map to category and hash"
                        )
            except OSError as exc:
                findings.append(f"{asset_id}: cannot verify source archive ({exc})")
        if verify_data:
            if not data_path.is_file():
                findings.append(f"{asset_id}: per-asset data file is missing")
            else:
                try:
                    data_record = json.loads(data_path.read_text(encoding="utf-8"))
                    if data_record != record:
                        findings.append(f"{asset_id}: per-asset data differs from pack manifest")
                except (OSError, json.JSONDecodeError):
                    findings.append(f"{asset_id}: per-asset data is not valid JSON")
    base_ids = {item.get("id") for item in bases if isinstance(item, dict)}
    for plan in variants:
        if not isinstance(plan, dict):
            findings.append("variant plan must be an object")
        elif plan.get("base_asset_id") not in base_ids:
            findings.append(f"{plan.get('id')}: variant references an unknown base asset")
        elif (
            plan.get("state_axis") == plan.get("state")
            or not plan.get("state_axis")
            or not plan.get("state")
        ):
            findings.append(f"{plan.get('id')}: variant needs a distinct state_axis and state")
    matrix_complete = all(record.get("status") == "generated" for record in _records(pack))
    if pack.get("has_matrix_data") is not matrix_complete:
        findings.append(
            "has_matrix_data must match the generation state of every asset and variant"
        )
    return findings


def _positive_pair(value: object) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 2
        and all(type(item) is int and item > 0 for item in value)
    )


def _image_findings(record: dict, path: Path, label: str) -> list[str]:
    findings: list[str] = []
    try:
        with Image.open(path) as image:
            if image.format != "PNG":
                return [f"{label}: runtime image is not PNG"]
            if list(image.size) != record.get("canvas_px"):
                findings.append(f"{label}: runtime dimensions do not match canvas_px")
            alpha = image.convert("RGBA").getchannel("A")
            extrema = alpha.getextrema()
            if record.get("alpha") == "opaque" and extrema != (255, 255):
                findings.append(f"{label}: opaque runtime image contains transparent pixels")
            if record.get("alpha") == "transparent" and (extrema[0] != 0 or extrema[1] == 0):
                findings.append(f"{label}: transparent runtime image has invalid alpha bounds")
    except OSError:
        findings.append(f"{label}: runtime file is not a readable PNG")
    matrix = record.get("matrix_data")
    if not isinstance(matrix, dict):
        findings.append(f"{label}: matrix_data is missing")
    else:
        coverage = matrix.get("coverage")
        cols, rows = record["footprint_cells"]
        if (
            not isinstance(coverage, list)
            or len(coverage) != rows
            or any(not isinstance(line, list) or len(line) != cols for line in coverage)
        ):
            findings.append(f"{label}: matrix coverage dimensions do not match footprint")
        elif any(
            not isinstance(value, (int, float)) or not 0.0 <= value <= 1.0
            for line in coverage
            for value in line
        ):
            findings.append(f"{label}: matrix coverage must contain ratios from 0 to 1")
    return findings


def _source_findings(source: object, label: str) -> list[str]:
    if not isinstance(source, dict):
        return [f"{label}: source image mapping must be an object"]
    path_value = source.get("path")
    if not isinstance(path_value, str) or not path_value.startswith("game/assets/packs/"):
        return [f"{label}: source path must be repository-relative inside game/assets/packs"]
    path = (REPO_ROOT / path_value).resolve()
    if not path.is_relative_to(ORIGINAL_DIR.resolve()):
        return [f"{label}: source path escapes this pack's original directory"]
    if path.suffix.lower() != ".png":
        return [f"{label}: original source path must end in .png"]
    if not path.is_file():
        return [f"{label}: original PNG is missing: {path_value}"]
    expected_hash = source.get("sha256")
    if (
        not isinstance(expected_hash, str)
        or len(expected_hash) != 64
        or any(character not in "0123456789abcdef" for character in expected_hash)
    ):
        return [f"{label}: source sha256 must be a lowercase 64-character digest"]
    actual_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    if expected_hash != actual_hash:
        return [f"{label}: original SHA-256 does not match"]
    try:
        with Image.open(path) as image:
            if list(image.size) != source.get("size_px"):
                return [f"{label}: original dimensions do not match source_images metadata"]
            if image.format != "PNG":
                return [f"{label}: original archive is not PNG"]
            if image.width < 1024 or image.height < 1024:
                return [f"{label}: original source is below the 1024px production minimum"]
    except OSError:
        return [f"{label}: original archive is not a readable PNG"]
    for field in ("source", "license", "generated_on", "prompt_ref", "prompt"):
        if not isinstance(source.get(field), str) or not source[field].strip():
            return [f"{label}: source image mapping is missing {field}"]
    try:
        generated_on = date.fromisoformat(source["generated_on"]).isoformat()
        if generated_on != source["generated_on"]:
            return [f"{label}: generated_on must use YYYY-MM-DD"]
    except ValueError:
        return [f"{label}: generated_on must use YYYY-MM-DD"]
    return []


def _audit(pack_dir: Path) -> list[str]:
    try:
        pack = _load_pack(pack_dir)
    except ToolError as exc:
        return [str(exc)]
    try:
        return _findings(pack, pack_dir)
    except (ToolError, AttributeError, KeyError, TypeError, ValueError) as exc:
        return [f"manifest could not be audited: {exc}"]


def _init_data(pack_dir: Path) -> None:
    pack = _load_pack(pack_dir)
    findings = _manifest_findings(pack, pack_dir)
    if findings:
        raise ToolError("cannot initialize invalid pack data:\n- " + "\n- ".join(findings))
    writes = []
    for record in _records(pack):
        data_path = _data_path(pack_dir, record)
        content = _json_text(record)
        if data_path.exists():
            if data_path.read_text(encoding="utf-8") != content:
                raise ToolError(f"refusing to replace existing per-asset data: {data_path}")
        else:
            writes.append((data_path, content.encode("utf-8")))
    _commit_files(writes)
    count = len(_records(pack))
    data_label = DATA_DIR.relative_to(REPO_ROOT)
    ok(f"initialized {count} per-asset records under {data_label}")


def _manifest_findings(pack: dict, pack_dir: Path) -> list[str]:
    try:
        return _findings(pack, pack_dir, verify_data=False)
    except (ToolError, AttributeError, KeyError, TypeError, ValueError) as exc:
        return [f"manifest could not be validated: {exc}"]


def _install(args: argparse.Namespace, pack_dir: Path) -> None:
    source_path = Path(args.source).expanduser().resolve()
    if source_path.suffix.lower() != ".png" or not source_path.is_file():
        raise ToolError(f"source must be an existing PNG: {source_path}")
    try:
        generated_on = date.fromisoformat(args.generated_on).isoformat()
        if generated_on != args.generated_on:
            raise ValueError("date must use YYYY-MM-DD")
    except ValueError as exc:
        raise ToolError("--generated-on must use YYYY-MM-DD") from exc
    for label, value in (
        ("source-name", args.source_name),
        ("license", args.license),
        ("prompt-ref", args.prompt_ref),
        ("prompt", args.prompt),
    ):
        if not value.strip():
            raise ToolError(f"--{label} must be non-empty")
    LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(LOCK_PATH, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError as exc:
        raise ToolError(f"another Faultlands install is active ({LOCK_PATH})") from exc
    try:
        with os.fdopen(descriptor, "w", encoding="ascii") as lock:
            lock.write(f"pid={os.getpid()} asset={args.asset_id}\n")
        _install_locked(args, pack_dir, source_path, generated_on)
    finally:
        LOCK_PATH.unlink(missing_ok=True)


def _install_locked(
    args: argparse.Namespace, pack_dir: Path, source_path: Path, generated_on: str
) -> None:
    pack = _load_pack(pack_dir)
    target = next((item for item in _records(pack) if item.get("id") == args.asset_id), None)
    if target is None:
        raise ToolError(f"unknown Faultlands asset id {args.asset_id!r}")
    plan = next((item for item in pack["variant_plans"] if item.get("id") == args.asset_id), None)
    if plan is not None:
        base = next(item for item in pack["assets"] if item["id"] == plan["base_asset_id"])
        if base.get("status") != "generated":
            raise ToolError(f"generate the base asset {base['id']} before its variant")
    replacing = target.get("status") == "generated" and args.replace_generated
    if target.get("status") != "planned" and not replacing:
        raise ToolError(f"refusing to replace {args.asset_id} without --replace-generated")
    runtime_path = _safe_pack_path(pack_dir, target.get("path"), f"{args.asset_id}.path")
    data_path = _data_path(pack_dir, target)
    if runtime_path.exists() and not replacing:
        raise ToolError(f"refusing to overwrite runtime image: {runtime_path}")
    try:
        with Image.open(source_path) as opened:
            if opened.format != "PNG":
                raise ToolError("source file must contain PNG data")
            source_image = opened.convert("RGBA")
    except OSError as exc:
        raise ToolError(f"could not decode source PNG: {source_path}") from exc
    canvas = _normalize(source_image, target)
    matrix_data = _matrix_data(canvas, target)
    image_bytes = _png_bytes(canvas)
    source_bytes = source_path.read_bytes()
    digest = hashlib.sha256(source_bytes).hexdigest()
    relative_source = (
        Path("game/assets/packs")
        / PACK_ID
        / "original"
        / target["category"]
        / f"{_slug(target)}--{digest[:12]}.png"
    )
    archive_path = (REPO_ROOT / relative_source).resolve()
    if not archive_path.is_relative_to(ORIGINAL_DIR.resolve()):
        raise ToolError("computed source archive path escapes original directory")
    if archive_path.exists() and hashlib.sha256(archive_path.read_bytes()).hexdigest() != digest:
        raise ToolError(f"source archive hash collision at {archive_path}")
    if not archive_path.exists():
        _exclusive_write(archive_path, source_bytes)
    source_record = {
        "path": relative_source.as_posix(),
        "sha256": digest,
        "size_px": list(source_image.size),
        "source": args.source_name.strip(),
        "license": args.license.strip(),
        "generated_on": generated_on,
        "prompt_ref": args.prompt_ref.strip(),
        "prompt": args.prompt.strip(),
    }
    target.setdefault("source_images", [])
    target["source_images"] = [
        item for item in target["source_images"] if item.get("sha256") != digest
    ]
    target["source_images"].append(source_record)
    target.update(
        {
            "status": "generated",
            "source_path": f"original/{target['category']}/{_slug(target)}--{digest[:12]}.png",
            "source": args.source_name.strip(),
            "license": args.license.strip(),
            "generated_on": generated_on,
            "prompt_ref": args.prompt_ref.strip(),
            "prompt": args.prompt.strip(),
            "matrix_data": matrix_data,
            "matrix_review": "alpha-derived; visual review pending",
        }
    )
    if plan is not None:
        plan.update(
            {key: value for key, value in target.items() if key not in ("path", "name", "brief")}
        )
        plan["brief"] = target["brief"]
        plan["path"] = target["path"]
    pack["has_matrix_data"] = all(item.get("status") == "generated" for item in _records(pack))
    pack["matrix_data_status"] = (
        "complete"
        if pack["has_matrix_data"]
        else "partial; generated records have alpha-derived mapping"
    )
    manifest_path = pack_dir / f"{PACK_ID}_pack.json"
    writes = [
        (runtime_path, image_bytes),
        (manifest_path, _json_text(pack).encode("utf-8")),
        (data_path, _json_text(target).encode("utf-8")),
    ]
    _commit_files(writes, replace=True)
    source_size = f"{source_image.width}x{source_image.height}"
    runtime_size = f"{canvas.width}x{canvas.height}"
    ok(f"installed {args.asset_id}: preserved {source_size}; runtime {runtime_size}")


def _normalize(source: Image.Image, record: dict) -> Image.Image:
    width, height = record["canvas_px"]
    if record["alpha"] == "opaque":
        if source.getchannel("A").getextrema() != (255, 255):
            raise ToolError("opaque asset source contains transparent pixels")
        return (
            source.convert("RGB").resize((width, height), Image.Resampling.LANCZOS).convert("RGBA")
        )
    alpha = source.getchannel("A")
    if alpha.getextrema()[0] != 0 or alpha.getextrema()[1] == 0:
        raise ToolError(
            "transparent asset source must include visible and fully transparent pixels"
        )
    bounds = alpha.point(lambda value: 255 if value >= ALPHA_CROP_THRESHOLD else 0).getbbox()
    if bounds is None:
        raise ToolError("transparent asset source has no visible pixels")
    cropped = source.crop(bounds)
    max_width = max(1, width - SOURCE_MARGIN_PX * 2)
    max_height = max(1, height - SOURCE_MARGIN_PX * 2)
    scale = min(max_width / cropped.width, max_height / cropped.height)
    resized = cropped.resize(
        (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    x = (width - resized.width) // 2
    y = (
        height - resized.height - SOURCE_MARGIN_PX
        if record["pivot"] == "bottom_center"
        else (height - resized.height) // 2
    )
    canvas.alpha_composite(resized, (x, y))
    return canvas


def _matrix_data(image: Image.Image, record: dict) -> dict:
    repo_root = Path(__file__).resolve().parents[1]
    scripts = repo_root / ".agents" / "skills" / "map-asset-pipeline" / "scripts"
    import sys

    if str(scripts) not in sys.path:
        sys.path.insert(0, str(scripts))
    import derive
    import geometry
    import subcell

    (REPO_ROOT / "build").mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".png", dir=REPO_ROOT / "build", delete=False) as tmp:
        temporary_path = Path(tmp.name)
    try:
        image.save(temporary_path, format="PNG")
        cols, rows = record["footprint_cells"]
        if record["alpha"] == "opaque":
            coverage = [[1.0] * cols for _ in range(rows)]
            frac_zero = 0.0
        else:
            coverage, _cols, _rows, frac_zero = derive.coverage_grid(temporary_path, cols, rows)
        collision = record["collision"]
        rule = "full_body" if collision == "solid" else "none"
        gate = 0.20 if cols * rows > 1 else 0.35
        blocks = derive.occluder_mask(rule, coverage, gate)
        walk_surface = derive.walk_surface_mask(coverage, rule, False)
        fill, sub_cols, sub_rows, crop_x, crop_y, _ = subcell.subcell_fill(temporary_path)
        contact = geometry.contact_run(temporary_path)
        contact_px = contact[1] - contact[0] if contact else 0
        canvas_width, canvas_height = image.size
        reference_scale = min(
            cols * geometry.CELL_PX / canvas_width,
            rows * geometry.CELL_PX / canvas_height,
        )
        contact_reference_px = contact_px * reference_scale
        blocked = {
            str(scale): ([0, 0, cols - 1, rows - 1] if any(map(any, blocks)) else None)
            for scale in SCALES
        }
        block_rect = blocked["1.0"]
        cell_px = geometry.CELL_PX
        return {
            "coverage": coverage,
            "frac_zero": frac_zero,
            "blocks": blocks,
            "walk_surface": walk_surface,
            "block_cell_count": sum(sum(row) for row in blocks),
            "anchor_cell": [cols // 2, rows - 1]
            if record["pivot"] == "bottom_center"
            else [cols // 2, rows // 2],
            "sub_grid": [sub_cols, sub_rows],
            "sub_fill": fill,
            "crop_offset": [crop_x, crop_y],
            "trunk_columns": subcell.trunk_columns(fill),
            "contact_px": contact_px,
            "contact_reference_px": float(contact_reference_px),
            "blocked_by_scale": blocked,
            "block_rect": block_rect,
            "block_rect_px": (
                None
                if block_rect is None
                else [
                    block_rect[0] * cell_px,
                    block_rect[1] * cell_px,
                    (block_rect[2] + 1) * cell_px,
                    (block_rect[3] + 1) * cell_px,
                ]
            ),
        }
    finally:
        temporary_path.unlink(missing_ok=True)


def _png_bytes(image: Image.Image) -> bytes:
    with tempfile.SpooledTemporaryFile() as buffer:
        image.save(buffer, format="PNG", optimize=True)
        buffer.seek(0)
        return buffer.read()


def _json_text(value: dict) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def _exclusive_write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        if path.read_bytes() == content:
            return
        raise ToolError(f"refusing to overwrite existing source archive: {path}") from None
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(content)
    except OSError:
        path.unlink(missing_ok=True)
        raise


def _commit_files(writes: list[tuple[Path, bytes]], *, replace: bool = False) -> None:
    staged: list[tuple[Path, Path, bytes | None]] = []
    installed: list[tuple[Path, bytes | None]] = []
    try:
        for target, content in writes:
            target.parent.mkdir(parents=True, exist_ok=True)
            previous = target.read_bytes() if target.exists() else None
            if previous is not None and not replace and previous != content:
                raise ToolError(f"refusing to overwrite existing file: {target}")
            with tempfile.NamedTemporaryFile(dir=target.parent, suffix=".tmp", delete=False) as tmp:
                tmp.write(content)
                staged.append((target, Path(tmp.name), previous))
        for target, temporary, previous in staged:
            os.replace(temporary, target)
            installed.append((target, previous))
    except (OSError, ToolError) as exc:
        for target, previous in reversed(installed):
            if previous is None:
                target.unlink(missing_ok=True)
            else:
                _write_atomic(target, previous)
        if isinstance(exc, ToolError):
            raise
        raise ToolError(f"could not write Faultlands pack files: {exc}") from exc
    finally:
        for _target, temporary, _previous in staged:
            temporary.unlink(missing_ok=True)


def _write_atomic(target: Path, content: bytes) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=target.parent, suffix=".tmp", delete=False) as tmp:
        tmp.write(content)
        temporary = Path(tmp.name)
    os.replace(temporary, target)
