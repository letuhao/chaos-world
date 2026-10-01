"""Content data audit for game/data (ADR 0008).

Parses Godot `.tres` content under the data root and checks the acquisition
dependency layers: item sources -> recipes/bosses/domains, recipe materials,
boss domains, and domain bosses. No Godot runtime required.
"""

from __future__ import annotations

import re
from pathlib import Path

from .common import REPO_ROOT, ToolError, fail, info, ok

DATA_ROOT = REPO_ROOT / "game" / "data"

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


def register(subparsers) -> None:
    parser = subparsers.add_parser("data", help="audit content data under game/data")
    actions = parser.add_subparsers(dest="data_action", required=True)
    for name in ("audit", "report"):
        action = actions.add_parser(name)
        action.add_argument("--root", default=None, help="data root (default game/data)")


def run(args) -> int:
    root = Path(args.root) if args.root else DATA_ROOT
    if args.data_action == "audit":
        return _audit_command(root)
    if args.data_action == "report":
        return _report_command(root)
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
