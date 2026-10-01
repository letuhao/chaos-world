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

# folder -> {id, arrays, scalars}
SCHEMA = {
    "items": {"id": "id", "arrays": ["sources"], "scalars": []},
    "recipes": {"id": "id", "arrays": ["inputs", "outputs"], "scalars": ["station"]},
    "bosses": {"id": "id", "arrays": ["loot"], "scalars": ["domain_id"]},
    "domains": {"id": "id", "arrays": ["boss_ids"], "scalars": []},
}
TYPE_BY_FOLDER = {"items": "item", "recipes": "recipe", "bosses": "boss", "domains": "domain"}
BASE_SOURCES = {"gather", "starter"}
REF_SOURCES = {"craft": "recipe", "boss": "boss", "domain": "domain"}

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
        record = {"path": rel.as_posix(), "id": record_id, "arrays": {}, "scalars": {}}
        for field in schema["arrays"]:
            record["arrays"][field] = _extract_array(text, field)
        for field in schema["scalars"]:
            record["scalars"][field] = _extract_scalar(text, field) or ""
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

    for recipe_id, recipe in recipes.items():
        for item_id in recipe["arrays"].get("inputs", []):
            if item_id not in items:
                gaps.append(f"recipe {recipe_id}: input '{item_id}' is not a defined item")
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
