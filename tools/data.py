"""Content data tooling for game/data (ADR 0008/0009).

`audit`/`report` parse Godot `.tres` content and check the acquisition dependency
layers. `new` scaffolds a valid `.tres` so generators do not hand-write the format.
No Godot runtime required.
"""

from __future__ import annotations

import re
from pathlib import Path

from .common import REPO_ROOT, ToolError, fail, info, ok

DATA_ROOT = REPO_ROOT / "game" / "data"
STAT_DEFS = REPO_ROOT / "game" / "src" / "contracts" / "stat.gd"
ACTOR_STATS = REPO_ROOT / "game" / "src" / "core" / "actor_stats.gd"

CATEGORIES = {
    "material",
    "consumable",
    "equipment",
    "technique",
    "quest",
    "key",
    "currency",
    "misc",
}
GRADES = {"mortal", "spirit", "earth", "heaven", "immortal", "divine"}
GRADE_ORDER = ("mortal", "spirit", "earth", "heaven", "immortal", "divine")

# Categories whose items are expected to carry gameplay modifiers.
MODIFIER_CATEGORIES = {"equipment", "technique", "consumable"}

# Categories where a subcategory is meaningful for grouping.
SUBCATEGORY_CATEGORIES = {"material", "consumable", "equipment", "technique"}

# folder -> {id, arrays, scalars}
SCHEMA = {
    "items": {
        "id": "id",
        "arrays": ["sources"],
        "dicts": ["flat_modifiers", "percent_modifiers"],
        "scalars": ["category", "subcategory", "grade"],
    },
    "recipes": {"id": "id", "arrays": ["inputs", "outputs"], "scalars": ["station"]},
    "bosses": {"id": "id", "arrays": ["loot"], "scalars": ["domain_id"]},
    "domains": {"id": "id", "arrays": ["boss_ids"], "scalars": []},
}
TYPE_BY_FOLDER = {"items": "item", "recipes": "recipe", "bosses": "boss", "domains": "domain"}
BASE_SOURCES = {"gather", "starter"}
REF_SOURCES = {"craft": "recipe", "boss": "boss", "domain": "domain"}
# `quest` is accepted but not reference-checked: there is no QuestDef resource yet.
UNCHECKED_SOURCES = {"quest"}
KNOWN_SOURCE_TYPES = BASE_SOURCES | set(REF_SOURCES) | UNCHECKED_SOURCES

SCRIPTS = {
    "item": "res://src/modules/items/item_def.gd",
    "recipe": "res://src/modules/items/recipe_def.gd",
    "boss": "res://src/modules/world/boss_def.gd",
    "domain": "res://src/modules/world/domain_def.gd",
}
SCRIPT_CLASS = {"item": "ItemDef", "recipe": "RecipeDef", "boss": "BossDef", "domain": "DomainDef"}


def register(subparsers) -> None:
    parser = subparsers.add_parser("data", help="scaffold and audit content under game/data")
    actions = parser.add_subparsers(dest="data_action", required=True)

    for name in ("audit", "report"):
        action = actions.add_parser(name)
        action.add_argument("--root", default=None, help="data root (default game/data)")

    dist = actions.add_parser(
        "distribution",
        help="audit item characteristic distribution and diversity (read-only, non-gating)",
    )
    dist.add_argument("--root", default=None, help="data root (default game/data)")
    dist.add_argument(
        "--fail-on",
        choices=["none", "warn", "error"],
        default="none",
        help="exit non-zero above this finding level (default none)",
    )

    edit = actions.add_parser("edit", help="update fields on an existing item or boss .tres")
    edit.add_argument("--root", default=None)
    edit.add_argument("--kind", default="item", choices=["item", "boss"])
    edit.add_argument("--id", required=True)
    edit.add_argument("--name", default=None)
    edit.add_argument("--subtype", default=None)
    edit.add_argument("--grade", default=None)
    edit.add_argument("--flat", default="", help="replace flat_modifiers (stat=value,...)")
    edit.add_argument("--percent", default="", help="replace percent_modifiers (stat=value,...)")
    edit.add_argument("--add-sources", default="", help="append sources")
    edit.add_argument("--add-flat", default="", help="merge into flat_modifiers")
    edit.add_argument("--add-percent", default="", help="merge into percent_modifiers")
    edit.add_argument("--clear-flat", action="store_true", help="remove the flat_modifiers block")
    edit.add_argument(
        "--clear-percent", action="store_true", help="remove the percent_modifiers block"
    )
    edit.add_argument("--add-loot", default="", help="append item ids to a boss's loot array")

    new = actions.add_parser("new", help="scaffold a content .tres")
    new.add_argument("--root", default=None)
    new.add_argument("--kind", required=True, choices=["item", "recipe", "boss", "domain"])
    new.add_argument("--id", required=True)
    new.add_argument("--name", default=None)
    new.add_argument("--category", default="misc")
    new.add_argument("--subtype", default="")
    new.add_argument("--grade", default="mortal")
    new.add_argument("--sources", default="")
    new.add_argument("--flat", default="")
    new.add_argument("--percent", default="")
    new.add_argument("--station", default="")
    new.add_argument("--inputs", default="")
    new.add_argument("--outputs", default="")
    new.add_argument("--domain", default="")
    new.add_argument("--loot", default="")
    new.add_argument("--bosses", default="")


def run(args) -> int:
    root = Path(args.root) if args.root else DATA_ROOT
    if args.data_action == "audit":
        return _audit_command(root)
    if args.data_action == "report":
        return _report_command(root)
    if args.data_action == "distribution":
        return _distribution_command(root, getattr(args, "fail_on", "none"))
    if args.data_action == "edit":
        return _edit_command(root, args)
    if args.data_action == "new":
        return _new_command(root, args)
    raise ToolError(f"unknown data action: {args.data_action}")


def _extract_scalar(text: str, field: str) -> str | None:
    match = re.search(rf'(?m)^\s*{field}\s*=\s*&"([^"]*)"', text)
    return match.group(1) if match else None


def _extract_array(text: str, field: str) -> list[str]:
    match = re.search(rf"(?ms)^\s*{field}\s*=\s*Array\[StringName\]\(\[(.*?)\]\)", text)
    if not match:
        return []
    return re.findall(r'&"([^"]*)"', match.group(1))


def _extract_dict(text: str, field: str) -> dict[str, float]:
    match = re.search(rf"(?ms)^\s*{field}\s*=\s*\{{(.*?)\}}", text)
    if not match:
        return {}
    pairs = re.findall(r'"([^"]+)"\s*:\s*(-?[\d.]+)', match.group(1))
    return {key: float(value) for key, value in pairs}


def _load(root: Path) -> tuple[dict, list[str]]:
    records: dict = {name: {} for name in TYPE_BY_FOLDER.values()}
    malformed: list[str] = []
    if not root.is_dir():
        return records, malformed
    for path in sorted(root.rglob("*.tres")):
        rel = path.relative_to(root)
        folder = rel.parts[0] if rel.parts else ""
        type_name = TYPE_BY_FOLDER.get(folder)
        if type_name is None:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        schema = SCHEMA[folder]
        record_id = _extract_scalar(text, schema["id"])
        if not record_id:
            malformed.append(rel.as_posix())
            continue
        record = {
            "path": rel.as_posix(),
            "id": record_id,
            "arrays": {},
            "dicts": {},
            "scalars": {},
        }
        for field in schema["arrays"]:
            record["arrays"][field] = _extract_array(text, field)
        for field in schema.get("dicts", []):
            record["dicts"][field] = _extract_dict(text, field)
        for field in schema["scalars"]:
            record["scalars"][field] = _extract_scalar(text, field) or ""
        # Records are keyed by id, so a duplicate id would silently overwrite
        # rather than collide. Track the losers so the audit can report them.
        previous = records[type_name].get(record_id)
        if previous is not None:
            record["duplicate_of"] = previous["path"]
        records[type_name][record_id] = record
    return records, malformed


def _find_recipe_cycle(recipes: dict) -> list[str] | None:
    graph: dict[str, set[str]] = {}
    for recipe in recipes.values():
        inputs = recipe["arrays"].get("inputs", [])
        for output in recipe["arrays"].get("outputs", []):
            graph.setdefault(output, set()).update(inputs)
    color: dict[str, int] = {}
    stack: list[str] = []

    def visit(node: str) -> list[str] | None:
        color[node] = 1
        stack.append(node)
        for dep in graph.get(node, ()):
            state = color.get(dep, 0)
            if state == 1:
                return stack[stack.index(dep) :] + [dep]
            if state == 0:
                found = visit(dep)
                if found:
                    return found
        stack.pop()
        color[node] = 2
        return None

    for node in graph:
        if color.get(node, 0) == 0:
            found = visit(node)
            if found:
                return found
    return None


def _audit(root: Path) -> list[str]:
    records, malformed = _load(root)
    items = records.get("item", {})
    recipes = records.get("recipe", {})
    bosses = records.get("boss", {})
    domains = records.get("domain", {})
    gaps = [f"{path}: missing id" for path in malformed]

    for type_name in sorted(records):
        for record_id, record in sorted(records[type_name].items()):
            other = record.get("duplicate_of")
            if other:
                gaps.append(f"{type_name} {record_id}: duplicate id, also defined in {other}")

    for item_id, item in sorted(items.items()):
        if not item["scalars"].get("subcategory"):
            gaps.append(f"item {item_id}: has no subcategory")

    # A manufactured material (an ingot, a cut gem, a cordial) is not foraged.
    # If a recipe produces it and its only source is `gather`, the source
    # metadata claims a route the content does not support.
    produced_by: dict[str, str] = {}
    for recipe_id, recipe in recipes.items():
        for output_id in recipe["arrays"].get("outputs", []):
            produced_by.setdefault(output_id, recipe_id)
    for item_id, recipe_id in sorted(produced_by.items()):
        item = items.get(item_id)
        if not item or item["scalars"].get("category") != "material":
            continue
        if item["arrays"].get("sources") == ["gather"]:
            gaps.append(f"item {item_id}: produced by '{recipe_id}' but sourced only from 'gather'")

    for recipe_id, recipe in recipes.items():
        inputs = recipe["arrays"].get("inputs", [])
        for item_id in inputs:
            if item_id not in items:
                gaps.append(f"recipe {recipe_id}: input '{item_id}' is not a defined item")
        repeated = sorted({i for i in inputs if inputs.count(i) > 1})
        for item_id in repeated:
            gaps.append(f"recipe {recipe_id}: input '{item_id}' is listed more than once")
        outputs = recipe["arrays"].get("outputs", [])
        if not outputs:
            gaps.append(f"recipe {recipe_id}: has no outputs")
        for item_id in outputs:
            if item_id not in items:
                gaps.append(f"recipe {recipe_id}: output '{item_id}' is not a defined item")

    for boss_id, boss in bosses.items():
        domain_id = boss["scalars"].get("domain_id", "")
        if not domain_id:
            gaps.append(f"boss {boss_id}: has no domain")
        elif domain_id not in domains:
            gaps.append(f"boss {boss_id}: domain '{domain_id}' is not a defined domain")
        for item_id in boss["arrays"].get("loot", []):
            if item_id not in items:
                gaps.append(f"boss {boss_id}: loot '{item_id}' is not a defined item")

    for domain_id, domain in domains.items():
        boss_ids = domain["arrays"].get("boss_ids", [])
        if not boss_ids:
            gaps.append(f"domain {domain_id}: has no bosses")
        for boss_id in boss_ids:
            if boss_id not in bosses:
                gaps.append(f"domain {domain_id}: boss '{boss_id}' is not a defined boss")

    for item_id, item in items.items():
        sources = item["arrays"].get("sources", [])
        if not sources:
            gaps.append(f"item {item_id}: has no acquisition source")
            continue
        for source in sources:
            source_type, _, ref = source.partition(":")
            if source_type in BASE_SOURCES:
                continue
            if source_type not in KNOWN_SOURCE_TYPES:
                gaps.append(f"item {item_id}: unknown acquisition source type '{source_type}'")
                continue
            target_type = REF_SOURCES.get(source_type)
            if target_type is None:
                continue
            if not ref:
                gaps.append(f"item {item_id}: source '{source_type}' has no reference")
            elif target_type == "recipe":
                if ref not in recipes:
                    gaps.append(f"item {item_id}: recipe '{ref}' is not defined")
                elif item_id not in recipes[ref]["arrays"].get("outputs", []):
                    gaps.append(f"item {item_id}: recipe '{ref}' does not output it")
            elif target_type == "boss":
                if ref not in bosses:
                    gaps.append(f"item {item_id}: boss '{ref}' is not defined")
                elif item_id not in bosses[ref]["arrays"].get("loot", []):
                    gaps.append(f"item {item_id}: boss '{ref}' does not drop it")
            elif target_type == "domain" and ref not in domains:
                gaps.append(f"item {item_id}: domain '{ref}' is not defined")

    cycle = _find_recipe_cycle(recipes)
    if cycle:
        gaps.append("recipe cycle: " + " -> ".join(cycle))
    return gaps


def _audit_command(root: Path) -> int:
    gaps = _audit(root)
    if gaps:
        for gap in gaps:
            fail(gap)
        fail(f"data audit failed: {len(gaps)} gap(s)")
        return 1
    ok("data audit clean")
    return 0


def _report_command(root: Path) -> int:
    records, _ = _load(root)
    for type_name in ("item", "recipe", "boss", "domain"):
        entries = records.get(type_name, {})
        info(f"{type_name}: {len(entries)}")
        for record_id in sorted(entries):
            info(f"    {record_id}")
    return 0


def _group_by(items: dict, field_set: str, field_name: str) -> dict[str, list[dict]]:
    groups: dict[str, list[dict]] = {}
    for item in items.values():
        key = item[field_set].get(field_name, "")
        groups.setdefault(key, []).append(item)
    return groups


def _bar(count: int, peak: int, width: int = 28) -> str:
    if peak <= 0:
        return ""
    filled = max(1, round(count * width / peak)) if count else 0
    return "#" * filled


def _pct(count: int, total: int) -> float:
    return count * 100.0 / total if total else 0.0


def _print_table(title: str, rows: list[tuple[str, int]], total: int) -> None:
    info("")
    info(f"=== {title} ===")
    if not rows:
        info("  (none)")
        return
    peak = max(count for _, count in rows)
    for label, count in rows:
        info(f"  {label:28s} {count:5d}  {_pct(count, total):5.1f}%  {_bar(count, peak)}")


def _modifier_keys(item: dict) -> set[str]:
    keys: set[str] = set()
    for values in item["dicts"].values():
        keys.update(values)
    return keys


def _valid_stats() -> set[str]:
    """Stat ids declared in contracts/stat.gd, so the audit follows the real schema."""
    if not STAT_DEFS.is_file():
        return set()
    text = STAT_DEFS.read_text(encoding="utf-8", errors="replace")
    return set(re.findall(r'&"([a-z_]+)"', text))


def _resolve_rate_stats() -> set[str]:
    """Map RATE_STATS const names through their &"id" values."""
    if not STAT_DEFS.is_file():
        return set()
    text = STAT_DEFS.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"(?ms)^const RATE_STATS\s*:=\s*\[(.*?)\]", text)
    if not match:
        return set()
    names = set(re.findall(r"^\s*([A-Z_]+),", match.group(1), re.M))
    ids: set[str] = set()
    for name in names:
        found = re.search(rf'const {name} := &"([a-z_]+)"', text)
        if found:
            ids.add(found.group(1))
    return ids


def _resolve_zero_baseline_stats() -> set[str]:
    """Stats whose baseline in actor_stats.gd is the literal 0.0.

    `_put` resolves `(base + flat) * (1 + percent)`, so a PERCENT modifier on a
    stat whose baseline is identically zero can never change the result. This is
    the shape that made `damage_reduction` a no-op for every item that used it
    (ADR 0022); deriving the set from the resolver keeps that from returning.
    """
    if not ACTOR_STATS.is_file():
        return set()
    text = ACTOR_STATS.read_text(encoding="utf-8", errors="replace")
    ids: set[str] = set()
    for stat_const, baseline in re.findall(
        r"(?ms)_put\(\s*Stat\.([A-Z_]+)\s*,\s*([0-9.]+)\s*,", text
    ):
        if float(baseline) != 0.0:
            continue
        found = re.search(
            rf'const {stat_const} := &"([a-z_]+)"',
            STAT_DEFS.read_text(encoding="utf-8", errors="replace"),
        )
        if found:
            ids.add(found.group(1))
    return ids


def _collect_findings(items: dict) -> list[tuple[str, str]]:
    """Return (level, message) findings. level is 'error' or 'warn'."""
    findings: list[tuple[str, str]] = []
    total = len(items)
    if not total:
        return findings

    for item in items.values():
        path = item["path"]
        cat = item["scalars"].get("category", "")
        grade = item["scalars"].get("grade", "")
        if not cat:
            findings.append(("error", f"{path}: has no category"))
        elif cat not in CATEGORIES:
            findings.append(("error", f"{path}: unknown category '{cat}'"))
        if not grade:
            findings.append(("error", f"{path}: has no grade"))
        elif grade not in GRADES:
            findings.append(("error", f"{path}: unknown grade '{grade}'"))

    by_cat = _group_by(items, "scalars", "category")

    # Missing categories and empty categories.
    for cat in sorted(CATEGORIES):
        if cat not in by_cat:
            findings.append(("warn", f"category '{cat}' has no items"))

    # Dominant category concentration.
    if by_cat:
        top_cat, top_items = max(by_cat.items(), key=lambda kv: len(kv[1]))
        share = _pct(len(top_items), total)
        if share > 60.0:
            findings.append(
                ("warn", f"category '{top_cat}' holds {share:.1f}% of all items; pool is narrow")
            )

    # Subtype diversity: a category with only one subtype has no variety.
    for cat, cat_items in sorted(by_cat.items()):
        subs = {item["scalars"].get("subcategory", "") for item in cat_items}
        real = {s for s in subs if s}
        if len(real) == 1 and len(cat_items) >= 8:
            only = next(iter(real))
            findings.append(
                ("warn", f"category '{cat}' has one subtype '{only}' across {len(cat_items)} items")
            )
        if not real and cat in SUBCATEGORY_CATEGORIES:
            findings.append(("warn", f"category '{cat}' items have no subcategory set"))
        # Over-fragmentation: many singleton subtypes carry no grouping value.
        if len(real) > 4:
            per_subtype = len(cat_items) / len(real)
            if per_subtype < 3.0:
                findings.append(
                    (
                        "warn",
                        f"category '{cat}' is fragmented: {len(real)} subtypes for "
                        f"{len(cat_items)} items ({per_subtype:.1f} each)",
                    )
                )

    # Grade coverage: every category should span the ladder.
    for cat, cat_items in sorted(by_cat.items()):
        grades = {item["scalars"].get("grade", "") for item in cat_items}
        missing = [g for g in GRADE_ORDER if g not in grades]
        if len(missing) >= 3:
            findings.append(("warn", f"category '{cat}' is missing grades: {', '.join(missing)}"))

    # Modifier coverage for stat-bearing categories.
    for cat in sorted(MODIFIER_CATEGORIES):
        cat_items = by_cat.get(cat, [])
        if not cat_items:
            continue
        bare = [item["path"] for item in cat_items if not _modifier_keys(item)]
        if bare:
            share = _pct(len(bare), len(cat_items))
            level = "error" if share > 25.0 else "warn"
            findings.append(
                (level, f"category '{cat}' has {len(bare)} items with no modifiers ({share:.1f}%)")
            )

    # Modifier stat diversity overall.
    all_keys: dict[str, int] = {}
    for item in items.values():
        for key in _modifier_keys(item):
            all_keys[key] = all_keys.get(key, 0) + 1
    if all_keys and len(all_keys) <= 4:
        used = ", ".join(sorted(all_keys))
        findings.append(("warn", f"only {len(all_keys)} distinct modifier stats in use: {used}"))

    # Declared stats that no item modifies leave part of the stat surface unreachable.
    valid = _valid_stats()
    if valid:
        unused = sorted(valid - set(all_keys))
        if unused:
            findings.append(
                (
                    "warn",
                    f"{len(unused)} declared stat(s) never used by any item: {', '.join(unused)}",
                )
            )

    # FLAT on a fractional/multiplier stat means e.g. +1000% instead of +10%.
    rate = _resolve_rate_stats()
    if rate:
        offenders: dict[str, list[str]] = {}
        for item_id, item in sorted(items.items()):
            for key in item["dicts"].get("flat_modifiers", {}):
                if key in rate:
                    offenders.setdefault(key, []).append(item_id)
        if offenders:
            detail = "; ".join(f"{k} x{len(v)}" for k, v in sorted(offenders.items()))
            findings.append(("error", f"FLAT modifier on rate stat(s), must be PERCENT: {detail}"))

    # A zero-valued modifier grants nothing.
    noop = [
        item_id
        for item_id, item in sorted(items.items())
        for field in ("flat_modifiers", "percent_modifiers")
        for value in item["dicts"].get(field, {}).values()
        if value == 0
    ]
    if noop:
        findings.append(("warn", f"{len(noop)} zero-valued modifier(s) grant nothing"))

    # PERCENT cannot change a stat whose baseline is identically zero.
    zero_base = _resolve_zero_baseline_stats()
    if zero_base:
        dead_percent: dict[str, list[str]] = {}
        for item_id, item in sorted(items.items()):
            for key in item["dicts"].get("percent_modifiers", {}):
                if key in zero_base:
                    dead_percent.setdefault(key, []).append(item_id)
        if dead_percent:
            detail = "; ".join(f"{k} x{len(v)}" for k, v in sorted(dead_percent.items()))
            findings.append(
                (
                    "error",
                    "PERCENT modifier on zero-baseline stat(s), can never apply "
                    f"(use FLAT): {detail}",
                )
            )

    # Power curve: within a category+subtype, a tier must not be weaker than the one below.
    buckets: dict[tuple[str, str, str, str], list[float]] = {}
    for item in items.values():
        grade = item["scalars"].get("grade", "")
        cat = item["scalars"].get("category", "")
        sub = item["scalars"].get("subcategory", "")
        for key, value in item["dicts"].get("flat_modifiers", {}).items():
            buckets.setdefault((cat, sub, key, grade), []).append(value)
    for cat, sub, key in sorted({(c, s, k) for c, s, k, _ in buckets}):
        series = []
        for grade in GRADE_ORDER:
            values = buckets.get((cat, sub, key, grade))
            if values and len(values) >= 3:
                series.append((grade, sum(values) / len(values)))
        for (low, low_mean), (high, high_mean) in zip(series, series[1:], strict=False):
            # A relative drop is only meaningful on a magnitude-scale stat. On a
            # fraction-scale stat (0.05 -> 0.04) a 10% move is noise, so require
            # an absolute gap as well.
            if high_mean < low_mean * 0.9 and low_mean - high_mean > 1.0:
                findings.append(
                    (
                        "warn",
                        f"power curve inverted on '{key}' in {cat}/{sub}: {high} mean "
                        f"{high_mean:.0f} is below {low} mean {low_mean:.0f}",
                    )
                )
                break

    # Modifier stats that the game does not define are silently ignored at runtime.
    valid = _valid_stats()
    if valid:
        unknown: dict[str, list[str]] = {}
        for item_id, item in sorted(items.items()):
            for key in sorted(_modifier_keys(item)):
                if key not in valid:
                    unknown.setdefault(key, []).append(item_id)
        for key, ids in sorted(unknown.items()):
            findings.append(
                (
                    "error",
                    f"unknown modifier stat '{key}' on {len(ids)} item(s) "
                    f"(not declared in contracts/stat.gd): {', '.join(ids[:6])}"
                    + ("..." if len(ids) > 6 else ""),
                )
            )

    return findings


def _distribution_command(root: Path, fail_on: str) -> int:
    records, malformed = _load(root)
    items = records.get("item", {})
    total = len(items)

    info("=== Inventory ===")
    info(f"  total items:   {total}")
    info(f"  malformed:     {len(malformed)}")
    for type_name in ("recipe", "boss", "domain"):
        label = "bosses" if type_name == "boss" else f"{type_name}s"
        info(f"  {label:14s} {len(records.get(type_name, {}))}")

    if not total:
        info("")
        info("no items to analyse")
        return 0

    by_cat = _group_by(items, "scalars", "category")
    cat_rows = [(cat or "<none>", len(group)) for cat, group in sorted(by_cat.items())]
    _print_table("Category Distribution", cat_rows, total)

    sub_rows: list[tuple[str, int]] = []
    for cat, group in sorted(by_cat.items()):
        for sub, count in sorted(
            _group_by({item["id"]: item for item in group}, "scalars", "subcategory").items(),
            key=lambda kv: (-len(kv[1]), kv[0]),
        ):
            sub_rows.append((f"{cat or '<none>'}/{sub or '<none>'}", len(count)))
    _print_table("Category/Subtype Distribution", sub_rows, total)

    by_grade = _group_by(items, "scalars", "grade")
    grade_rows = [(grade, len(by_grade.get(grade, []))) for grade in GRADE_ORDER]
    _print_table("Grade Distribution", grade_rows, total)

    src_counts: dict[str, int] = {}
    for item in items.values():
        for source in item["arrays"].get("sources", []):
            key = source.partition(":")[0]
            src_counts[key] = src_counts.get(key, 0) + 1
    _print_table("Acquisition Source Distribution", sorted(src_counts.items()), total)

    flat = {item["id"]: item for item in items.values() if item["dicts"].get("flat_modifiers")}
    pct = {item["id"]: item for item in items.values() if item["dicts"].get("percent_modifiers")}
    info("")
    info("=== Modifier Coverage ===")
    info(f"  items with flat modifiers:    {len(flat):5d}  ({_pct(len(flat), total):5.1f}%)")
    info(f"  items with percent modifiers: {len(pct):5d}  ({_pct(len(pct), total):5.1f}%)")
    info(f"  items with no modifiers:      {total - len({*flat, *pct}):5d}")

    stat_counts: dict[str, int] = {}
    for item in items.values():
        for key in _modifier_keys(item):
            stat_counts[key] = stat_counts.get(key, 0) + 1
    _print_table("Modifier Stat Distribution", sorted(stat_counts.items()), total)

    findings = _collect_findings(items)
    errors = [msg for level, msg in findings if level == "error"]
    warnings = [msg for level, msg in findings if level == "warn"]

    info("")
    info("=== Findings ===")
    if not findings:
        info("  none - distribution is healthy")
    else:
        for msg in errors:
            fail(msg)
        for msg in warnings:
            info(f"  warn: {msg}")
        info(f"  {len(errors)} error(s), {len(warnings)} warning(s)")

    if malformed:
        for path in malformed:
            fail(f"malformed: {path}")

    if fail_on != "none" and errors:
        fail(f"distribution audit failed: {len(errors)} error(s)")
        return 1
    if fail_on == "warn" and warnings:
        fail(f"distribution audit failed: {len(warnings)} warning(s)")
        return 1
    ok("distribution audit complete")
    return 0


def _display_name(record_id: str) -> str:
    return " ".join(word.capitalize() for word in record_id.split("_"))


def _array_literal(values: list[str]) -> str:
    return "Array[StringName]([" + ", ".join(f'&"{value}"' for value in values) + "])"


def _split_list(raw: str) -> list[str]:
    return [part.strip() for part in raw.split(",") if part.strip()]


def _split_pairs(raw: str) -> list[tuple[str, float]]:
    pairs: list[tuple[str, float]] = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        key, _, value = part.partition("=")
        key = key.strip()
        if not key:
            continue
        try:
            pairs.append((key, float(value)))
        except ValueError as exc:
            raise ToolError(f"bad modifier '{part}' (expected stat=value)") from exc
    return pairs


def _dict_literal(pairs: list[tuple[str, float]]) -> str:
    body = ",\n".join(f'"{key}": {value}' for key, value in pairs)
    return "{\n" + body + "\n}"


def _tres(kind: str, lines: list[str]) -> str:
    header = (
        f'[gd_resource type="Resource" script_class="{SCRIPT_CLASS[kind]}" '
        "load_steps=2 format=3]\n\n"
        f'[ext_resource type="Script" path="{SCRIPTS[kind]}" id="1_{kind}"]\n\n'
        "[resource]\n"
        f'script = ExtResource("1_{kind}")\n'
    )
    return header + "\n".join(lines) + "\n"


def _merge_dict_block(text: str, field: str, pairs: list[tuple[str, float]]) -> str:
    """Replace a ``field = { ... }`` block, or append one if absent.

    Uses the same formatting as `_dict_literal` so output stays stable.
    """
    pattern = re.compile(rf"(?m)^\s*{field}\s*=\s*\{{.*?\n\}}", re.S)
    if not pairs:
        new_text = pattern.sub("", text)
        return new_text.rstrip() + "\n"
    block = f"{field} = {_dict_literal(pairs)}"
    if pattern.search(text):
        return pattern.sub(lambda _m: block, text)
    return text.rstrip() + "\n" + block + "\n"


def _merge_array_block(text: str, field: str, values: list[str]) -> str:
    pattern = re.compile(rf"(?m)^\s*{field}\s*=\s*Array\[StringName\]\(\[.*?\]\)", re.S)
    return pattern.sub(lambda _m: f"{field} = {_array_literal(values)}", text)


def _edit_command(root: Path, args) -> int:
    folder = "bosses" if args.kind == "boss" else "items"
    candidates = sorted((root / folder).rglob(f"{args.id}.tres"))
    if not candidates:
        raise ToolError(f"no {args.kind} found with id '{args.id}'")
    if len(candidates) > 1:
        paths = ", ".join(p.relative_to(root).as_posix() for p in candidates)
        raise ToolError(f"id '{args.id}' is ambiguous ({len(candidates)} files): {paths}")
    path = candidates[0]
    text = path.read_text(encoding="utf-8")

    if args.kind == "boss":
        if not args.add_loot:
            raise ToolError("boss edits require --add-loot")
        existing = _extract_array(text, "loot")
        added = []
        for value in _split_list(args.add_loot):
            if value not in existing:
                existing.append(value)
                added.append(value)
        if not added:
            fail(f"{path}: all requested loot already present")
            return 1
        text = _merge_array_block(text, "loot", existing)
        path.write_text(text, encoding="utf-8")
        shown = path.relative_to(REPO_ROOT).as_posix()
        ok(f"updated {shown} (+{len(added)} loot: {', '.join(added)})")
        return 0

    if args.name is not None:
        if not re.search(r'(?m)^\s*display_name\s*=\s*"', text):
            raise ToolError(f"{path}: no display_name field to replace")
        text = re.sub(r'(?m)^(\s*display_name\s*=\s*)"[^"]*"', rf'\1"{args.name}"', text)
    if args.subtype is not None:
        text = re.sub(r'(?m)^(\s*subcategory\s*=\s*)&"[^"]*"', rf'\1&"{args.subtype}"', text)
    if args.grade is not None:
        if args.grade not in GRADES:
            raise ToolError(f"unknown grade '{args.grade}' (allowed: {sorted(GRADES)})")
        text = re.sub(r'(?m)^(\s*grade\s*=\s*)&"[^"]*"', rf'\1&"{args.grade}"', text)

    flat = _split_pairs(args.flat)
    add_flat = _split_pairs(args.add_flat)
    if args.clear_flat:
        text = _merge_dict_block(text, "flat_modifiers", [])
    elif flat or args.flat:
        text = _merge_dict_block(text, "flat_modifiers", flat)
    elif add_flat:
        existing = _extract_dict(text, "flat_modifiers")
        for key, value in add_flat:
            existing[key] = value
        text = _merge_dict_block(text, "flat_modifiers", sorted(existing.items()))

    percent = _split_pairs(args.percent)
    add_percent = _split_pairs(args.add_percent)
    if args.clear_percent:
        text = _merge_dict_block(text, "percent_modifiers", [])
    elif percent or args.percent:
        text = _merge_dict_block(text, "percent_modifiers", percent)
    elif add_percent:
        existing = _extract_dict(text, "percent_modifiers")
        for key, value in add_percent:
            existing[key] = value
        text = _merge_dict_block(text, "percent_modifiers", sorted(existing.items()))

    if args.add_sources:
        existing = _extract_array(text, "sources")
        for value in _split_list(args.add_sources):
            if value not in existing:
                existing.append(value)
        text = _merge_array_block(text, "sources", existing)

    path.write_text(text, encoding="utf-8")
    ok(f"updated {path.relative_to(REPO_ROOT).as_posix()}")
    return 0


def _new_command(root: Path, args) -> int:
    record_id = args.id
    kind = args.kind
    name = args.name or _display_name(record_id)

    if kind == "item":
        category = args.category
        if category not in CATEGORIES:
            raise ToolError(f"unknown category '{category}' (allowed: {sorted(CATEGORIES)})")
        if args.grade not in GRADES:
            raise ToolError(f"unknown grade '{args.grade}' (allowed: {sorted(GRADES)})")
        path = root / "items" / category / f"{record_id}.tres"
        lines = [
            f'id = &"{record_id}"',
            f'display_name = "{name}"',
            f'category = &"{category}"',
            f'subcategory = &"{args.subtype}"',
            f'grade = &"{args.grade}"',
            f"sources = {_array_literal(_split_list(args.sources))}",
        ]
        flat = _split_pairs(args.flat)
        if flat:
            lines.append(f"flat_modifiers = {_dict_literal(flat)}")
        percent = _split_pairs(args.percent)
        if percent:
            lines.append(f"percent_modifiers = {_dict_literal(percent)}")
    elif kind == "recipe":
        path = root / "recipes" / f"{record_id}.tres"
        lines = [
            f'id = &"{record_id}"',
            f'display_name = "{name}"',
            f'station = &"{args.station}"',
            f"inputs = {_array_literal(_split_list(args.inputs))}",
            f"outputs = {_array_literal(_split_list(args.outputs))}",
        ]
    elif kind == "boss":
        path = root / "bosses" / f"{record_id}.tres"
        lines = [
            f'id = &"{record_id}"',
            f'display_name = "{name}"',
            f'domain_id = &"{args.domain}"',
            f"loot = {_array_literal(_split_list(args.loot))}",
        ]
    else:  # domain
        path = root / "domains" / f"{record_id}.tres"
        lines = [
            f'id = &"{record_id}"',
            f'display_name = "{name}"',
            f"boss_ids = {_array_literal(_split_list(args.bosses))}",
        ]

    if path.exists():
        raise ToolError(f"already exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_tres(kind, lines), encoding="utf-8")
    shown = path.relative_to(REPO_ROOT).as_posix() if path.is_relative_to(REPO_ROOT) else str(path)
    ok(f"created {shown}")
    return 0
