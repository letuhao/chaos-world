"""Audit and maintain the item-to-art links in the asset index."""

from __future__ import annotations

import colorsys
import json
import os
import re
import tempfile
from collections import Counter
from pathlib import Path

from PIL import Image

from . import item_asset_generate, map_assets
from .common import GAME_DIR, REPO_ROOT, ToolError, fail, ok

ITEM_ROOT = GAME_DIR / "data" / "items"
INDEX_PATH = GAME_DIR / "assets" / "asset-index.jsonl"
MATCH_FIELDS = {"category", "subcategory", "id_prefix", "id_regex"}
VISUAL_TRAIT_RE = re.compile(r"^[a-z][a-z0-9_-]*:[a-z][a-z0-9_-]*$")
SINGLE_VALUE_TRAIT_AXES = {"form", "palette", "presentation"}
MIN_UNIQUE_IMAGE_TARGET = 2000


def register(subparsers) -> None:
    parser = subparsers.add_parser("assets", help="audit and maintain item art links")
    actions = parser.add_subparsers(dest="assets_action", required=True)
    report = actions.add_parser("report", help="show item coverage and asset-family distribution")
    report.add_argument("--all", action="store_true", help="show every asset family")
    report.add_argument(
        "--diversity", action="store_true", help="show visual palette and item-form diversity"
    )
    actions.add_parser("audit", help="fail on missing, stale, or conflicting item art links")
    actions.add_parser("sync", help="refresh item_ids in asset-index.jsonl from item match rules")
    inspect = actions.add_parser("inspect", help="list item seeds assigned to one asset family")
    inspect.add_argument("asset_id")
    inspect.add_argument("--limit", type=int, default=30)
    normalize = actions.add_parser("normalize", help="crop and resize a transparent generated PNG")
    normalize.add_argument("--source", required=True, help="generated PNG source path")
    normalize.add_argument("--output", required=True, help="new filename in generated item assets")
    item_asset_generate.register(actions)
    map_assets.register(actions)


def run(args) -> int:
    if args.assets_action == "map":
        return map_assets.run(args)
    if args.assets_action == "generate":
        return item_asset_generate.run(args)
    items = _load_items()
    records = _load_index()
    if args.assets_action == "inspect":
        return _inspect(records, args.asset_id, args.limit)
    issues: list[str] = []
    winners = _resolve(items, records, issues)

    if args.assets_action == "sync":
        if issues:
            missing_ids = items.keys() - winners.keys()
            groups = Counter(
                (items[item_id]["category"], items[item_id]["subcategory"])
                for item_id in missing_ids
            )
            summary = ", ".join(
                f"{category}/{subcategory} ({count})"
                for (category, subcategory), count in groups.most_common()
            )
            samples = "\n".join(f"  - {issue}" for issue in issues[:20])
            more = f"\n  ... {len(issues) - 20} more" if len(issues) > 20 else ""
            raise ToolError(
                f"cannot sync asset links: {len(issues)} unresolved items; "
                f"groups: {summary}\n{samples}{more}"
            )
        _write_links(records, winners)
        ok(f"updated {INDEX_PATH.relative_to(REPO_ROOT).as_posix()} ({len(items)} item seeds)")
        return 0
    if args.assets_action == "normalize":
        _normalize_image(Path(args.source), args.output)
        return 0

    linked, link_issues = _read_links(items, records, winners)
    issues.extend(link_issues)
    _print_report(
        items,
        records,
        linked,
        issues,
        show_all=getattr(args, "all", False),
        show_diversity=getattr(args, "diversity", False),
    )
    if args.assets_action == "audit":
        if issues:
            fail(f"asset audit failed: {len(issues)} issue(s)")
            return 1
        ok("asset audit complete")
    return 0


def _normalize_image(source: Path, output_name: str, *, replace: bool = False) -> None:
    source = source.resolve()
    output_dir = GAME_DIR / "assets" / "items" / "generated"
    output_path = (output_dir / output_name).resolve()
    if source.suffix.lower() != ".png" or not source.is_file():
        raise ToolError(f"source must be an existing PNG: {source}")
    if Path(output_name).name != output_name or not output_name.lower().endswith(".png"):
        raise ToolError("output must be a PNG filename without directory components")
    if not output_path.is_relative_to(output_dir.resolve()):
        raise ToolError("output must stay under game/assets/items/generated")
    if output_path.exists() and not replace:
        raise ToolError(f"refusing to overwrite existing asset: {output_path}")

    with Image.open(source) as opened:
        image = opened.convert("RGBA")
    alpha = image.getchannel("A")
    if alpha.getextrema()[0] != 0:
        raise ToolError(f"source has no transparent pixels: {source}")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ToolError(f"source is fully transparent: {source}")
    image = image.crop(bounds)
    image.thumbnail((232, 232), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    canvas.alpha_composite(image, ((256 - image.width) // 2, (256 - image.height) // 2))
    if replace:
        temporary_path: Path | None = None
        try:
            with tempfile.NamedTemporaryFile(
                suffix=".png", dir=output_dir, delete=False
            ) as temporary:
                temporary_path = Path(temporary.name)
                canvas.save(temporary, format="PNG", optimize=True)
            os.replace(temporary_path, output_path)
        finally:
            if temporary_path and temporary_path.exists():
                temporary_path.unlink()
    else:
        descriptor = None
        try:
            descriptor = os.open(output_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(descriptor, "wb") as output:
                descriptor = None
                canvas.save(output, format="PNG", optimize=True)
        except FileExistsError as exc:
            raise ToolError(f"refusing to overwrite existing asset: {output_path}") from exc
        except OSError as exc:
            output_path.unlink(missing_ok=True)
            raise ToolError(f"could not save normalized asset: {output_path}: {exc}") from exc
        finally:
            if descriptor is not None:
                os.close(descriptor)
    ok(f"normalized {output_path.relative_to(REPO_ROOT).as_posix()} (256x256, transparent)")


def _load_items() -> dict[str, dict[str, str]]:
    items: dict[str, dict[str, str]] = {}
    if not ITEM_ROOT.is_dir():
        raise ToolError(f"item directory not found: {ITEM_ROOT}")
    for path in sorted(ITEM_ROOT.rglob("*.tres")):
        text = path.read_text(encoding="utf-8")
        item_id = _scalar(text, "id")
        category = _scalar(text, "category")
        subcategory = _scalar(text, "subcategory")
        if not item_id or not category or not subcategory:
            raise ToolError(
                f"{path.relative_to(REPO_ROOT)}: item needs id, category, and subcategory"
            )
        if item_id in items:
            raise ToolError(f"duplicate item id '{item_id}'")
        items[item_id] = {"category": category, "subcategory": subcategory}
    return items


def _scalar(text: str, field: str) -> str:
    match = re.search(rf'(?m)^\s*{field}\s*=\s*&"([^"]*)"', text)
    return match.group(1) if match else ""


def _load_index() -> list[dict]:
    if not INDEX_PATH.is_file():
        raise ToolError(f"asset index not found: {INDEX_PATH}")
    records: list[dict] = []
    ids: set[str] = set()
    for line_number, line in enumerate(INDEX_PATH.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ToolError(f"{INDEX_PATH.name}:{line_number}: invalid JSON ({exc.msg})") from exc
        if not isinstance(record, dict):
            raise ToolError(f"{INDEX_PATH.name}:{line_number}: each line must be a JSON object")
        asset_id = record.get("id")
        match = record.get("match")
        if not isinstance(asset_id, str) or not asset_id:
            raise ToolError(f"{INDEX_PATH.name}:{line_number}: missing asset id")
        if asset_id in ids:
            raise ToolError(f"{INDEX_PATH.name}:{line_number}: duplicate asset id '{asset_id}'")
        ids.add(asset_id)
        if record.get("type") != "item_icon" or not isinstance(record.get("path"), str):
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' needs item_icon type and path"
            )
        if not isinstance(match, dict) or not match or set(match) - MATCH_FIELDS:
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' has an invalid match rule"
            )
        if any(not isinstance(value, str) or not value for value in match.values()):
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' has an empty match value"
            )
        if "id_regex" in match:
            try:
                re.compile(match["id_regex"])
            except re.error as exc:
                raise ToolError(
                    f"{INDEX_PATH.name}:{line_number}: '{asset_id}' has invalid id_regex"
                ) from exc
        asset_path = record["path"]
        if not asset_path.startswith("res://assets/"):
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' path must be under res://assets/"
            )
        local_path = GAME_DIR / asset_path.removeprefix("res://")
        if not local_path.is_file():
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' file is missing: {asset_path}"
            )
        item_ids = record.get("item_ids", [])
        if not isinstance(item_ids, list) or any(not isinstance(value, str) for value in item_ids):
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' item_ids must be strings"
            )
        visual_traits = record.get("visual_traits", [])
        if not isinstance(visual_traits, list) or any(
            not isinstance(value, str) or not VISUAL_TRAIT_RE.fullmatch(value)
            for value in visual_traits
        ):
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' visual_traits "
                "must be namespaced strings such as 'form:robe'"
            )
        single_axes = [
            value.split(":", 1)[0]
            for value in visual_traits
            if value.split(":", 1)[0] in SINGLE_VALUE_TRAIT_AXES
        ]
        if len(single_axes) != len(set(single_axes)):
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' has conflicting "
                "form, palette, or presentation tags"
            )
        records.append(record)
    return records


def _matches(match: dict, item_id: str, item: dict[str, str]) -> bool:
    return all(
        item_id.startswith(value)
        if key == "id_prefix"
        else re.fullmatch(value, item_id) is not None
        if key == "id_regex"
        else item.get(key) == value
        for key, value in match.items()
    )


def _specificity(match: dict) -> tuple[int, int, int, int, int]:
    # Exact-pattern rules, then prefixes, override category/subcategory rules.
    regex = match.get("id_regex", "")
    prefix = match.get("id_prefix", "")
    return (bool(regex), len(regex), bool(prefix), len(prefix), len(match))


def _resolve(
    items: dict[str, dict[str, str]], records: list[dict], issues: list[str]
) -> dict[str, str]:
    winners: dict[str, str] = {}
    for item_id, item in items.items():
        matches = [record for record in records if _matches(record["match"], item_id, item)]
        if not matches:
            issues.append(f"item {item_id}: no matching asset family")
            continue
        best_score = max(_specificity(record["match"]) for record in matches)
        best = [record for record in matches if _specificity(record["match"]) == best_score]
        if len(best) != 1:
            issues.append(
                f"item {item_id}: ambiguous asset families {', '.join(r['id'] for r in best)}"
            )
            continue
        winners[item_id] = best[0]["id"]
    return winners


def _read_links(
    items: dict[str, dict[str, str]], records: list[dict], winners: dict[str, str]
) -> tuple[dict[str, str], list[str]]:
    linked: dict[str, str] = {}
    issues: list[str] = []
    for record in records:
        asset_id = record["id"]
        for item_id in record.get("item_ids", []):
            if item_id not in items:
                issues.append(f"asset {asset_id}: stale item link '{item_id}'")
                continue
            previous = linked.get(item_id)
            if previous:
                issues.append(f"item {item_id}: linked to both {previous} and {asset_id}")
            else:
                linked[item_id] = asset_id
            expected = winners.get(item_id)
            if expected and expected != asset_id:
                issues.append(f"item {item_id}: links to {asset_id}, rule resolves to {expected}")
    for item_id in sorted(items.keys() - linked.keys()):
        issues.append(f"item {item_id}: missing asset link")
    for item_id in sorted(linked.keys() - winners.keys()):
        issues.append(f"item {item_id}: linked without a unique matching rule")
    return linked, issues


def _write_links(records: list[dict], winners: dict[str, str]) -> None:
    assignments: dict[str, list[str]] = {record["id"]: [] for record in records}
    for item_id, asset_id in winners.items():
        assignments[asset_id].append(item_id)
    for record in records:
        record["item_ids"] = sorted(assignments[record["id"]])
    content = "".join(
        json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n" for record in records
    )
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


def _print_report(
    items: dict[str, dict[str, str]],
    records: list[dict],
    linked: dict[str, str],
    issues: list[str],
    *,
    show_all: bool,
    show_diversity: bool = False,
) -> None:
    counts = Counter(linked.values())
    used = sum(counts.get(record["id"], 0) > 0 for record in records)
    unique_paths = len({record["path"] for record in records})
    print(
        f"item seeds: {len(items)} | linked: {len(linked)} | gaps: {len(items) - len(linked)} "
        f"| asset families: {len(records)} | unique files: {unique_paths} "
        f"| used: {used} | unused: {len(records) - used}"
    )
    gap_groups = Counter(
        (item["category"], item["subcategory"])
        for item_id, item in items.items()
        if item_id not in linked
    )
    if gap_groups:
        print("unlinked item groups:")
        groups = sorted(gap_groups.items(), key=lambda entry: (-entry[1], entry[0]))
        shown_groups = groups if show_all else groups[:20]
        for (category, subcategory), count in shown_groups:
            print(f"  {category}/{subcategory}: {count}")
        if len(shown_groups) < len(groups):
            print(f"  ... {len(groups) - 20} more groups")
    distribution = [record for record in records if show_all or counts.get(record["id"], 0) > 0]
    distribution.sort(key=lambda value: (-counts.get(value["id"], 0), value["id"]))
    shown = distribution if show_all else distribution[:20]
    print(f"items per asset family (showing {len(shown)} of {len(distribution)} used):")
    for record in shown:
        print(f"  {record['id']}: {counts.get(record['id'], 0)}")
    if len(shown) < len(distribution):
        print(f"  ... {len(distribution) - len(shown)} more (pass --all)")
    if issues:
        print(f"issues: {len(issues)}")
        for issue in issues[:30]:
            print(f"  - {issue}")
        if len(issues) > 30:
            print(f"  ... {len(issues) - 30} more")
    if show_diversity:
        _print_diversity(items, records, linked)


def _print_diversity(
    items: dict[str, dict[str, str]], records: list[dict], linked: dict[str, str]
) -> None:
    unique_images = len({record["path"] for record in records})
    print(
        f"  unique image target: at least {MIN_UNIQUE_IMAGE_TARGET} | "
        f"current {unique_images} | remaining {max(0, MIN_UNIQUE_IMAGE_TARGET - unique_images)}"
    )
    grouped_items: Counter[tuple[str, str]] = Counter(
        (item["category"], item["subcategory"]) for item in items.values()
    )
    grouped_families: dict[tuple[str, str], set[str]] = {}
    grouped_paths: dict[tuple[str, str], set[str]] = {}
    for record in records:
        groups = {
            (items[item_id]["category"], items[item_id]["subcategory"])
            for item_id in record.get("item_ids", [])
            if item_id in items
        }
        for group in groups:
            grouped_families.setdefault(group, set()).add(record["id"])
            grouped_paths.setdefault(group, set()).add(record["path"])

    print("\nitem visual diversity:")
    print("  seed category/subcategory | seeds | families | unique images")
    for category, subcategory in sorted(grouped_items):
        group = (category, subcategory)
        print(
            f"  {category}/{subcategory} | {grouped_items[group]} | "
            f"{len(grouped_families.get(group, set()))} | "
            f"{len(grouped_paths.get(group, set()))}"
        )

    _print_equipment_forms(items, records)
    _print_equipment_presentations(items, records)
    _print_palette_distribution(items, records, linked)
    _print_visual_trait_distribution(items, records)


def _print_equipment_forms(items: dict[str, dict[str, str]], records: list[dict]) -> None:
    equipment_ids = {item_id for item_id, item in items.items() if item["category"] == "equipment"}
    forms: dict[str, dict[str, set[str]]] = {}
    for record in records:
        match = record["match"]
        if match.get("category") != "equipment" or "id_prefix" not in match:
            continue
        prefix = match["id_prefix"].removesuffix("_")
        form = forms.setdefault(prefix, {"items": set(), "families": set(), "paths": set()})
        form["items"].update(set(record.get("item_ids", [])) & equipment_ids)
        form["families"].add(record["id"])
        form["paths"].add(record["path"])

    print("  equipment id-prefix forms:")
    if not forms:
        print("    none indexed")
    ordered_forms = sorted(forms.items(), key=lambda entry: (-len(entry[1]["items"]), entry[0]))
    for name, values in ordered_forms:
        print(
            f"    {name}: {len(values['items'])} seeds | "
            f"{len(values['families'])} families | {len(values['paths'])} images"
        )

    gender_words = {"male", "female", "masculine", "feminine"}
    explicit_ids = {
        item_id
        for item_id in equipment_ids
        if gender_words & set(re.findall(r"[a-z]+", item_id.lower()))
    }
    print(
        "  equipment seed IDs with explicit gender words: "
        f"{len(explicit_ids)} of {len(equipment_ids)}"
    )


def _print_equipment_presentations(items: dict[str, dict[str, str]], records: list[dict]) -> None:
    equipment_families: list[tuple[dict, set[str]]] = []
    for record in records:
        ids = {
            item_id
            for item_id in record.get("item_ids", [])
            if items.get(item_id, {}).get("category") == "equipment"
        }
        if ids:
            equipment_families.append((record, ids))
    tagged: Counter[str] = Counter()
    tagged_items: Counter[str] = Counter()
    untagged_families = 0
    untagged_items = 0
    for record, item_ids in equipment_families:
        presentation = next(
            (
                value.removeprefix("presentation:")
                for value in record.get("visual_traits", [])
                if value.startswith("presentation:")
            ),
            None,
        )
        if presentation is None:
            untagged_families += 1
            untagged_items += len(item_ids)
        else:
            tagged[presentation] += 1
            tagged_items[presentation] += len(item_ids)
    labels = ("male", "female", "unisex")
    counts = ", ".join(f"{label} {tagged[label]}" for label in labels)
    seed_counts = ", ".join(f"{label} {tagged_items[label]}" for label in labels)
    print(f"  equipment presentation tags (families): {counts}, untagged {untagged_families}")
    print(f"  equipment presentation tags (seeds): {seed_counts}, untagged {untagged_items}")


def _print_palette_distribution(
    items: dict[str, dict[str, str]], records: list[dict], linked: dict[str, str]
) -> None:
    path_palette = {
        path: _dominant_palette(GAME_DIR / path.removeprefix("res://"))
        for path in sorted({record["path"] for record in records})
    }
    palette_files: Counter[str] = Counter()
    palette_families: Counter[str] = Counter()
    palette_items: Counter[str] = Counter()
    for record in records:
        palette = path_palette[record["path"]]
        palette_families[palette] += 1
        palette_items[palette] += sum(
            linked.get(item_id) == record["id"] for item_id in record.get("item_ids", [])
        )
    for palette in path_palette.values():
        palette_files[palette] += 1

    print("  dominant raster hue by unique image (SVGs are marked unmeasured):")
    for palette, _count in palette_files.most_common():
        print(
            f"    {palette}: {palette_files[palette]} files | "
            f"{palette_families[palette]} families | {palette_items[palette]} seeds"
        )


def _dominant_palette(path: Path) -> str:
    if path.suffix.lower() != ".png":
        suffix = path.suffix.lower().lstrip(".") or "unknown"
        return f"{suffix}-unmeasured"
    with Image.open(path) as opened:
        image = opened.convert("RGBA")
    image.thumbnail((64, 64), Image.Resampling.BOX)
    colors: Counter[str] = Counter()
    for red, green, blue, alpha in image.getdata():
        if alpha < 128:
            continue
        hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        if saturation < 0.2 or value < 0.12:
            continue
        colors[_hue_family(hue)] += 1
    return colors.most_common(1)[0][0] if colors else "neutral"


def _hue_family(hue: float) -> str:
    if hue < 0.035 or hue >= 0.965:
        return "red"
    if hue < 0.10:
        return "orange"
    if hue < 0.17:
        return "yellow"
    if hue < 0.42:
        return "green"
    if hue < 0.53:
        return "cyan"
    if hue < 0.69:
        return "blue"
    if hue < 0.80:
        return "violet"
    return "magenta"


def _print_visual_trait_distribution(items: dict[str, dict[str, str]], records: list[dict]) -> None:
    traits: dict[str, dict[str, set[str]]] = {}
    tagged_families: set[str] = set()
    tagged_items: set[str] = set()
    category_families: dict[str, set[str]] = {}
    category_items: dict[str, set[str]] = {}
    category_axis_families: dict[tuple[str, str], set[str]] = {}
    category_axis_items: dict[tuple[str, str], set[str]] = {}
    for record in records:
        values = record.get("visual_traits", [])
        axes = {trait.split(":", 1)[0] for trait in values}
        item_ids = {item_id for item_id in record.get("item_ids", []) if item_id in items}
        categories = {items[item_id]["category"] for item_id in item_ids}
        for category in categories:
            category_families.setdefault(category, set()).add(record["id"])
            category_items.setdefault(category, set()).update(
                item_id for item_id in item_ids if items[item_id]["category"] == category
            )
            for axis in axes:
                key = (category, axis)
                category_axis_families.setdefault(key, set()).add(record["id"])
                category_axis_items.setdefault(key, set()).update(
                    item_id for item_id in item_ids if items[item_id]["category"] == category
                )
        if values:
            tagged_families.add(record["id"])
            tagged_items.update(item_ids)
        for trait in values:
            axis, value = trait.split(":", 1)
            entry = traits.setdefault(axis, {}).setdefault(value, set())
            entry.add(record["id"])
    print(
        "  explicit visual traits: "
        f"{len(tagged_families)} of {len(records)} families tagged; "
        f"{len(tagged_items)} of {len(items)} seeds covered"
    )
    axes = sorted(set(traits) | SINGLE_VALUE_TRAIT_AXES | {"motif"})
    print("    trait-tag coverage by item category (families; seeds):")
    for category in sorted(category_families):
        total_families = len(category_families[category])
        total_items = len(category_items[category])
        coverage = ", ".join(
            f"{axis} {len(category_axis_families.get((category, axis), set()))}/{total_families}"
            f" families,"
            f" {len(category_axis_items.get((category, axis), set()))}/{total_items} seeds"
            for axis in axes
        )
        print(f"      {category}: {coverage}")
    if not traits:
        print("    no visual_traits recorded yet")
        return
    for axis, values in sorted(traits.items()):
        axis_total = sum(len(families) for families in values.values())
        print(f"    {axis} ({axis_total} family tags):")
        for value, families in sorted(values.items(), key=lambda entry: (-len(entry[1]), entry[0])):
            seed_count = sum(
                len(record.get("item_ids", [])) for record in records if record["id"] in families
            )
            print(f"      {value}: {len(families)} families | {seed_count} seeds")


def _inspect(records: list[dict], asset_id: str, limit: int) -> int:
    if limit < 1:
        raise ToolError("--limit must be positive")
    record = next((value for value in records if value["id"] == asset_id), None)
    if record is None:
        raise ToolError(f"unknown asset family '{asset_id}'")
    item_ids = record.get("item_ids", [])
    print(f"{asset_id}: {record['path']} | {len(item_ids)} linked item seeds")
    print(f"match: {json.dumps(record['match'], separators=(',', ':'))}")
    for item_id in item_ids[:limit]:
        print(f"  {item_id}")
    if len(item_ids) > limit:
        print(f"  ... {len(item_ids) - limit} more (increase --limit)")
    return 0
