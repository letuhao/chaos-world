"""Content data tooling for game/data (ADR 0008/0009).

`audit`/`report` parse Godot `.tres` content and check the acquisition dependency
layers. `new` scaffolds a valid `.tres` so generators do not hand-write the format.
No Godot runtime required.
"""

from __future__ import annotations

import re
from pathlib import Path

from . import item_migrate, options
from .common import REPO_ROOT, ToolError, fail, info, ok, warn
from .options import (
    CATEGORY_ACTIVATION,
    DEFAULT_CATALOG,
    _load_jsonl,
    activations_for,
)
from .options import (
    _magnitude_bounds as option_magnitude_bounds,
)

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
RARITIES = ("common", "magic", "rare", "legendary")
RARITY_COUNT = {"common": 1, "magic": 2, "rare": 3, "legendary": 4}
RARITY_INDEX = {name: index for index, name in enumerate(RARITIES)}
GRADE_TIER = {"mortal": 1, "spirit": 2, "earth": 2, "heaven": 3, "immortal": 3, "divine": 4}

# Canonical 30-realm ladder: index, tier, and the display band each realm sits in.
REALM_ORDER: tuple[str, ...] = ()
REALM_INDEX: dict[str, int] = {}
REALM_TIER: dict[str, int] = {}


def _load_realms() -> None:
    global REALM_ORDER, REALM_INDEX, REALM_TIER
    if REALM_ORDER:
        return
    from .item_migrate import realm_ladder  # noqa: PLC0415

    ladder = realm_ladder()
    REALM_ORDER = tuple(ladder)
    REALM_INDEX = {realm_id: index for index, realm_id in enumerate(ladder)}
    REALM_TIER = {
        realm_id: (1 if index < 9 else 2 if index < 18 else 3 if index < 27 else 4)
        for index, realm_id in enumerate(ladder)
    }


def _magnitude_bounds(unit: str, realm_index: int, rarity_index: int) -> tuple[float, float]:
    """Option value window, read from the same source the runtime uses.

    Delegates to the option module so the gate can never validate authored content
    against numbers the game does not roll.
    """
    window = option_magnitude_bounds(unit, realm_index, rarity_index)
    return float(window["min"]), float(window["max"])


# Categories whose items are expected to carry gameplay modifiers.
MODIFIER_CATEGORIES = {"equipment", "technique", "consumable"}

# Categories where a subcategory is meaningful for grouping.
SUBCATEGORY_CATEGORIES = {"material", "consumable", "equipment", "technique"}

# folder -> {id, arrays, scalars}
SCHEMA = {
    "items": {
        "id": "id",
        "arrays": ["sources"],
        "dicts": [],
        "scalars": ["category", "subcategory", "grade", "rarity", "realm"],
        "fixed": True,
    },
    # A loot table can produce an item directly or through a nested table. Both
    # are extracted so the audit can prove every drop is actually obtainable
    # and that no table can reach itself (ADR 0043).
    "loot_table": {
        "id": "id",
        "arrays": [],
        "scalars": ["realm", "rarity"],
        "entries": "item_id",
        "nested": "table_id",
    },
    "loot_tier": {"id": "id", "arrays": ["boss_tables"], "scalars": ["realm", "rarity"]},
    "recipes": {"id": "id", "arrays": ["inputs", "outputs"], "scalars": ["station"]},
    "bosses": {"id": "id", "arrays": ["loot"], "scalars": ["domain_id"]},
    "domains": {"id": "id", "arrays": ["boss_ids"], "scalars": []},
}
TYPE_BY_FOLDER = {
    "items": "item",
    "recipes": "recipe",
    "bosses": "boss",
    "domains": "domain",
    # A feature module owns its own item namespace, so the audit gates it with
    # exactly the same rules as `data/items` rather than exempting it (ADR 0008).
    "socket": "item",
    "sets/items": "item",
    "loot/tables": "loot_table",
    "loot": "loot_tier",
}
# Folder prefix -> the schema that parses it. Several prefixes share one schema:
# a feature module's item namespace is gated by exactly the `items` rules.
SCHEMA_FOR_PREFIX = {
    "items": "items",
    "socket": "items",
    "sets/items": "items",
    "loot/tables": "loot_table",
    "loot": "loot_tier",
    "recipes": "recipes",
    "bosses": "bosses",
    "domains": "domains",
}
BASE_SOURCES = {"gather", "starter"}
# Stats whose flat modifier is a fraction rather than a magnitude (ADR 0022).
FRACTION_FLAT_STATS = {"damage_reduction"}
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
    edit.add_argument("--kind", default="item", choices=["item", "boss", "domain"])
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
    edit.add_argument(
        "--add-bosses", default="", help="append boss ids to a domain's boss_ids array"
    )

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

    # Master option catalog tooling (ADR 0025).
    options.register(actions)
    # Item definition migration from the legacy modifier stub (ADR 0025).
    item_migrate.register(actions)


def run(args) -> int:
    if args.data_action == "options":
        return options.run(args)
    if args.data_action == "items":
        return item_migrate.run(args)
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


def _main_resource(text: str) -> str:
    """The file's own `[resource]` block, ignoring every `sub_resource` before it.

    A loot table authors each entry as a `sub_resource` that carries its own
    `id`, so a first-match scan over the whole file would read the first entry's
    id as the table's. Scalars always mean the main resource.
    """
    marker = "\n[resource]"
    index = text.rfind(marker)
    return text[index + 1 :] if index >= 0 else text


def _extract_scalar(text: str, field: str) -> str | None:
    match = re.search(rf'(?m)^\s*{field}\s*=\s*&"([^"]*)"', _main_resource(text))
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


def _extract_fixed(text: str) -> dict[str, float]:
    """`fixed_modifiers` option id -> authored value (ADR 0025)."""
    match = re.search(r"(?ms)^\s*fixed_modifiers\s*=\s*Array\[Dictionary\]\(\[(.*?)^\]\)", text)
    if not match:
        return {}
    return {
        option_id: float(value)
        for option_id, value in re.findall(
            r'"option_id": &"([a-z_]+)", "value": (-?[\d.]+)', match.group(1)
        )
    }


def _extract_tokens(text: str, field: str) -> list[str]:
    """Every `field = &"..."` value in the file.

    Loot entries are authored as `sub_resource` blocks, one field per line, so a
    whole-file scan is what actually reads them.
    """
    return re.findall(rf'(?m)^{field} = &"([^"]+)"', text)


def _extract_bool(text: str, field: str, default: str = "true") -> str:
    match = re.search(rf"(?m)^\s*{field}\s*=\s*(true|false)", text)
    return match.group(1) if match else default


def _extract_roll_spec(text: str) -> dict:
    match = re.search(r"(?m)^\s*roll_spec\s*=\s*\{(.*)\}\s*$", text)
    if not match:
        return {}
    body = match.group(1)
    spec: dict = {}
    count = re.search(r'"count":\s*(-?\d+)', body)
    if count:
        spec["count"] = int(count.group(1))
    contexts = re.search(r'"contexts":\s*\[(.*?)\]', body)
    if contexts:
        spec["contexts"] = re.findall(r'"([a-z_]+)"', contexts.group(1))
    return spec


def _folder_key(rel: Path) -> str | None:
    """Registered folder prefix for a content file, shallowest match first.

    A module may nest its items one level down (`sets/items/...`), so the whole
    prefix is tried before falling back to the top-level folder alone. Returns
    the key used by both `TYPE_BY_FOLDER` and `SCHEMA`.
    """
    for depth in range(len(rel.parts) - 1, 0, -1):
        key = "/".join(rel.parts[:depth])
        if key in TYPE_BY_FOLDER:
            return key
    return None


def _load(root: Path) -> tuple[dict, list[str]]:
    records: dict = {name: {} for name in {*TYPE_BY_FOLDER.values(), *SCHEMA_FOR_PREFIX.values()}}
    malformed: list[str] = []
    if not root.is_dir():
        return records, malformed
    for path in sorted(root.rglob("*.tres")):
        rel = path.relative_to(root)
        folder = _folder_key(rel)
        if folder is None:
            continue
        type_name = TYPE_BY_FOLDER[folder]
        text = path.read_text(encoding="utf-8", errors="replace")
        schema = SCHEMA[SCHEMA_FOR_PREFIX[folder]]
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
            "fixed": {},
            "roll_spec": {},
            "entries": [],
            "nested": [],
            "legacy": bool(re.search(r"(?m)^\s*(flat_modifiers|percent_modifiers)\s*=", text)),
        }
        for field in schema["arrays"]:
            record["arrays"][field] = _extract_array(text, field)
        for field in schema.get("dicts", []):
            record["dicts"][field] = _extract_dict(text, field)
        for field in schema["scalars"]:
            record["scalars"][field] = _extract_scalar(text, field) or ""
        if schema.get("entries"):
            record["entries"] = _extract_tokens(text, schema["entries"])
        if schema.get("nested"):
            record["nested"] = _extract_tokens(text, schema["nested"])
        if schema.get("fixed"):
            record["fixed"] = _extract_fixed(text)
            record["roll_spec"] = _extract_roll_spec(text)
            record["scalars"]["stackable"] = _extract_bool(text, "stackable")
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
            elif bosses[boss_id]["scalars"].get("domain_id") != domain_id:
                # Both directions are checked separately above, so without this a
                # boss and a domain can each be internally valid and disagree.
                gaps.append(
                    f"domain {domain_id}: lists boss '{boss_id}' whose domain_id is "
                    f"'{bosses[boss_id]['scalars'].get('domain_id')}'"
                )

    for boss_id, boss in bosses.items():
        domain_id = boss["scalars"].get("domain_id", "")
        if domain_id in domains and boss_id not in domains[domain_id]["arrays"].get("boss_ids", []):
            gaps.append(f"boss {boss_id}: domain '{domain_id}' does not list it in boss_ids")

    # The reverse of the source check below: an item a boss drops is obtainable
    # from that boss, so it must declare it. Without this, a second boss sharing
    # an item's loot is invisible as an acquisition route.
    drops: dict[str, set[str]] = {}
    for boss_id, boss in bosses.items():
        for item_id in boss["arrays"].get("loot", []):
            drops.setdefault(item_id, set()).add(boss_id)
    for item_id, droppers in sorted(drops.items()):
        item = items.get(item_id)
        if not item:
            continue
        declared = {
            source.split(":", 1)[1]
            for source in item["arrays"].get("sources", [])
            if source.startswith("boss:")
        }
        for boss_id in sorted(droppers - declared):
            gaps.append(f"item {item_id}: dropped by boss '{boss_id}' but declares no such source")

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
    gaps.extend(_unobtainable(items, recipes))
    return gaps


def _obtainable(items: dict, recipes: dict) -> set[str]:
    """Items a player can actually acquire, by closing over craftable recipes.

    Roots are items with a non-craft source. A recipe becomes craftable once
    every one of its inputs is obtainable, and then its outputs are too.
    Iterated to a fixed point, so a chain of any depth resolves regardless of
    the order the records are visited in.
    """
    root_types = KNOWN_SOURCE_TYPES - {"craft"}
    roots = {
        item_id
        for item_id, item in items.items()
        if any(
            source.partition(":")[0] in root_types for source in item["arrays"].get("sources", [])
        )
    }
    obtainable = set(roots)
    pending = list(recipes.values())
    progressed = True
    while progressed:
        progressed = False
        still_pending = []
        for recipe in pending:
            outputs = recipe["arrays"].get("outputs", [])
            if not outputs:
                continue
            if all(i in obtainable for i in recipe["arrays"].get("inputs", [])):
                obtainable.update(outputs)
                progressed = True
            else:
                still_pending.append(recipe)
        pending = still_pending
    return obtainable


def _unobtainable(items: dict, recipes: dict) -> list[str]:
    """Items nothing in the corpus can ever produce or drop (DEF-0036)."""
    obtainable = _obtainable(items, recipes)
    orphans = sorted(set(items) - obtainable)
    if not orphans:
        return []
    listed = ", ".join(orphans[:10])
    more = f" (+{len(orphans) - 10} more)" if len(orphans) > 10 else ""
    return [f"{len(orphans)} item(s) cannot be acquired from any source: {listed}{more}"]


def _audit_command(root: Path) -> int:
    gaps = _audit(root)
    records, _ = _load(root)
    gaps.extend(msg for level, msg in _loot_findings(records) if level == "error")
    # Report out-of-window fixed values here too. `data distribution` computes
    # them, but a green audit that silently omits thousands of illegal authored
    # values is worse than a red one: the count has to be impossible to miss.
    catalog = {
        record["id"]: record
        for record in _load_jsonl(DEFAULT_CATALOG)
        if record["status"] == "active"
    }
    out_of_band = _out_of_band(records.get("item", {}), catalog)
    if out_of_band:
        warn(
            f"{len(out_of_band)} authored fixed value(s) sit outside the option's "
            f"realm/rarity magnitude window, e.g. "
            f"{', '.join(out_of_band[:4])}. A scale change retires them; see "
            f"`data distribution` and re-derive the content against the current "
            f"scale."
        )
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
    """Target stat ids of the option references an item author, via the catalog."""
    catalog = _catalog()
    keys: set[str] = set()
    for option_id in item.get("fixed", {}):
        record = catalog.get(option_id)
        if not record:
            continue
        target = record["target"]
        if target["type"] == "stat":
            keys.add(target["id"])
    return keys


def _catalog() -> dict[str, dict]:
    """Master option catalog keyed by id, read once per audit (ADR 0025)."""
    cached = getattr(_catalog, "_cache", None)
    if cached is None:
        cached = {r["id"]: r for r in _load_jsonl(DEFAULT_CATALOG)}
        _catalog._cache = cached  # type: ignore[attr-defined]
    return cached  # type: ignore[return-value]


def _progression_items() -> set[str]:
    """Item ids consumed as progression payloads rather than for their stats.

    A breakthrough bundle is a consumable that unlocks a realm; its effect is
    the unlock, so carrying no modifier is correct (ADR 0009). The realm seeds
    name these in `breakthrough_item` / `training_item` / `sea_catalyst`, and the
    cultivation modules consume them. Keyed on a field suffix so a future seed
    field naming a consumed item is exempt without a code change.
    """
    ids: set[str] = set()
    # `breakthrough_item`, `training_item`, `strengthening_item`, `sea_catalyst`.
    # Keyed on a field SUFFIX rather than an exact name so a future seed field
    # naming a consumed item is exempt without a code change. `id` is excluded:
    # realm ids are not item ids.
    pattern = re.compile(r'^\w+_(?:item|catalyst)\s*=\s*&"([^"]+)"', re.MULTILINE)
    # One realms directory per cultivation path (body, mind, qi); glob so a new
    # path is covered without touching this function.
    for realms in sorted(DATA_ROOT.glob("*/realms")):
        for seed in sorted(realms.glob("*.tres")):
            text = seed.read_text(encoding="utf-8", errors="replace")
            ids.update(pattern.findall(text))
    return ids


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


def _out_of_band(items: dict, catalog: dict) -> list[str]:
    """`item:option=value` for every authored fixed value outside its window.

    Authored content is derived against whichever magnitude scale was current when
    it was written. When the scale is retuned these go stale wholesale, so this is
    reported by both `data audit` and `data distribution`.
    """
    # The realm ladder MUST be loaded here, not by a caller. `REALM_INDEX` is a module
    # global populated only by `_load_realms()`, and `_out_of_band` reads it with a
    # `.get(realm, 0)` fallback. If it is empty, EVERY item silently resolves to
    # ordinal 0 and gets graded against the Qi Refining window — which made `data
    # audit` report thousands of false positives on content that was in band at its
    # own realm, and made it under-report the genuine ones. A green audit that
    # mis-grades every row is worse than a red one, because it is trusted.
    _load_realms()
    offenders: list[str] = []
    for item_id, item in sorted(items.items()):
        rarity_index = RARITY_INDEX.get(item["scalars"].get("rarity", ""), 0)
        realm_index = REALM_INDEX.get(item["scalars"].get("realm", ""), 0)
        for option_id, value in item["fixed"].items():
            record = catalog.get(option_id)
            if not record:
                continue
            low, high = _magnitude_bounds(record["unit"], realm_index, rarity_index)
            if value < low or value > high:
                offenders.append(f"{item_id}:{option_id}={value:g}")
    return offenders


def _loot_findings(records: dict) -> list[tuple[str, str]]:
    """Loot tables can only produce obtainable items, and cannot reach themselves.

    A table naming an undefined item is an unobtainable drop; a table reaching
    itself through nesting is an infinite resolution. Both are structural, so
    the gate fails on them (ADR 0043).
    """
    findings: list[tuple[str, str]] = []
    tables = records.get("loot_table", {})
    defined_items = set(records.get("item", {}))
    if not tables:
        return findings
    for table_id, table in sorted(tables.items()):
        for item_id in table["entries"]:
            if item_id not in defined_items:
                findings.append(
                    ("error", f"loot table {table_id}: drops undefined item '{item_id}'")
                )
        for nested in table["nested"]:
            if nested == table_id:
                findings.append(("error", f"loot table {table_id}: references itself"))
            elif nested not in tables:
                findings.append(
                    ("error", f"loot table {table_id}: references unknown table '{nested}'")
                )

    # A cycle across two or more tables is as fatal as a self-reference.
    def reaches_self(start: str) -> bool:
        seen: set[str] = set()
        pending = [start]
        while pending:
            current = pending.pop()
            if current in seen:
                continue
            seen.add(current)
            if current == start and len(seen) > 1:
                return True
            pending.extend(tables.get(current, {}).get("nested", []))
        return False

    for table_id in sorted(tables):
        if reaches_self(table_id):
            findings.append(("error", f"loot table {table_id}: participates in a cycle"))
    return findings


def _collect_findings(items: dict) -> list[tuple[str, str]]:
    """Return (level, message) findings. level is 'error' or 'warn'."""
    _load_realms()
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

    # Fixed/rolled coverage for every category: an item must carry at least one
    # fixed option with a real consumer and a usable roll spec (ADR 0025/0028).
    progression = _progression_items()
    catalog = _catalog()
    bare: list[str] = []
    unregistered: list[str] = []
    misactivated: list[str] = []
    zero_value: list[str] = []
    missing_roll: list[str] = []
    bad_rarity: list[str] = []
    bad_realm: list[str] = []
    bad_count: list[str] = []
    stackable_equipment: list[str] = []
    for item_id, item in sorted(items.items()):
        if item["legacy"]:
            findings.append(
                (
                    "error",
                    f"{item['path']}: legacy flat/percent modifier blocks remain; "
                    "run `tools data items migrate`",
                )
            )
        category = item["scalars"].get("category", "")
        activation = CATEGORY_ACTIVATION.get(category)
        if not item["fixed"] and item_id not in progression:
            bare.append(item_id)
        for option_id in item["fixed"]:
            record = catalog.get(option_id)
            if not record:
                unregistered.append(f"{item_id}:{option_id}")
                continue
            if activation and activation not in activations_for(record):
                misactivated.append(f"{item_id}:{option_id}")
            if item["fixed"][option_id] == 0:
                zero_value.append(item_id)
        spec = item["roll_spec"]
        if not spec:
            missing_roll.append(item_id)
            continue
        if int(spec.get("count", 0)) <= 0:
            bad_count.append(item_id)
        rarity = item["scalars"].get("rarity", "")
        if rarity not in RARITIES:
            bad_rarity.append(f"{item_id}:{rarity or '<none>'}")
        elif int(spec.get("count", 0)) != RARITY_COUNT[rarity]:
            bad_count.append(f"{item_id}:count {spec.get('count')} for {rarity}")
        # Equipment must remain a distinct instance: a stackable item merges and
        # loses its realized rolls, so it can never be equipped (ADR 0025).
        if category == "equipment" and item["scalars"].get("stackable", "true") != "false":
            stackable_equipment.append(item_id)
        realm = item["scalars"].get("realm", "")
        if realm not in REALM_INDEX:
            bad_realm.append(f"{item_id}:{realm or '<none>'}")
        elif REALM_TIER[realm] < GRADE_TIER.get(item["scalars"].get("grade", ""), 1):
            bad_realm.append(f"{item_id}:{realm} below grade tier")
    for label, offenders in (("fixed", bare), ("roll", missing_roll)):
        if offenders:
            findings.append(
                (
                    "error",
                    f"{len(offenders)} items carry no {label} channel: "
                    f"{', '.join(offenders[:6])}" + ("..." if len(offenders) > 6 else ""),
                )
            )
    for offenders, message in (
        (unregistered, "items reference options that are not in the master catalog"),
        (misactivated, "items reference options with no consumer for their category"),
        (zero_value, "items have a zero-valued fixed option that grants nothing"),
        (bad_rarity, "items have an unknown rarity"),
        (bad_realm, "items have an invalid realm for their grade"),
        (bad_count, "items have a roll count that disagrees with their rarity"),
        (
            stackable_equipment,
            "equipment is stackable, so it merges and cannot be equipped; "
            "run `tools data items migrate`",
        ),
    ):
        if offenders:
            detail = ", ".join(offenders[:6]) + ("..." if len(offenders) > 6 else "")
            findings.append(("error", f"{len(offenders)} {message}: {detail}"))

    # Modifier target diversity overall.
    all_keys: dict[str, int] = {}
    for item in items.values():
        for key in _modifier_keys(item):
            all_keys[key] = all_keys.get(key, 0) + 1
    if all_keys and len(all_keys) <= 4:
        used = ", ".join(sorted(all_keys))
        findings.append(("warn", f"only {len(all_keys)} distinct modifier targets in use: {used}"))

    # Declared stats that no item targets leave part of the stat surface unreachable.
    valid = _valid_stats()
    if valid:
        unused = sorted(valid - set(all_keys))
        if unused:
            findings.append(
                (
                    "warn",
                    f"{len(unused)} declared stat(s) never targeted by any item: "
                    f"{', '.join(unused)}",
                )
            )

    # Authored fixed values must sit inside the option's realm/rarity magnitude
    # window. The unit/op policy itself (FLAT on a rate, PERCENT above 1.0, a
    # PERCENT on a zero baseline) is now a property of the master catalog and is
    # enforced by `tools data options audit`, so it is checked once there instead
    # of per item.
    out_of_band = _out_of_band(items, catalog)
    if out_of_band:
        detail = ", ".join(out_of_band[:6]) + ("..." if len(out_of_band) > 6 else "")
        findings.append(
            (
                "error",
                f"{len(out_of_band)} fixed value(s) outside the option's realm/rarity "
                f"magnitude window: {detail}",
            )
        )

    # Power curve: within a category+subtype, a tier must not be weaker than the
    # one below, per resolved target stat.
    buckets: dict[tuple[str, str, str, str], list[float]] = {}
    for item in items.values():
        grade = item["scalars"].get("grade", "")
        cat = item["scalars"].get("category", "")
        sub = item["scalars"].get("subcategory", "")
        for option_id, value in item["fixed"].items():
            record = catalog.get(option_id)
            if not record or record["target"]["type"] != "stat":
                continue
            if record["unit"] != "magnitude":
                continue
            buckets.setdefault((cat, sub, record["target"]["id"], grade), []).append(value)
    for cat, sub, key in sorted({(c, s, k) for c, s, k, _ in buckets}):
        series = []
        for grade in GRADE_ORDER:
            values = buckets.get((cat, sub, key, grade))
            if values and len(values) >= 3:
                series.append((grade, sum(values) / len(values)))
        for (low, low_mean), (high, high_mean) in zip(series, series[1:], strict=False):
            if high_mean < low_mean * 0.9 and low_mean - high_mean > 1.0:
                findings.append(
                    (
                        "warn",
                        f"power curve inverted on '{key}' in {cat}/{sub}: {high} mean "
                        f"{high_mean:.0f} is below {low} mean {low_mean:.0f}",
                    )
                )
                break

    return findings


def _distribution_command(root: Path, fail_on: str) -> int:
    _load_realms()
    records, malformed = _load(root)
    items = records.get("item", {})
    total = len(items)

    info("=== Inventory ===")
    info(f"  total items:   {total}")
    info(f"  malformed:     {len(malformed)}")
    for type_name in ("recipe", "boss", "domain", "loot_table", "loot_tier"):
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

    by_rarity = _group_by(items, "scalars", "rarity")
    rarity_rows = [(rarity, len(by_rarity.get(rarity, []))) for rarity in RARITIES]
    _print_table("Rarity Distribution", rarity_rows, total)

    realm_rows = [
        (realm_id, sum(1 for item in items.values() if item["scalars"].get("realm") == realm_id))
        for realm_id in REALM_ORDER
    ]
    _print_table("Realm Distribution (all 30 canonical realms)", realm_rows, total)

    src_counts: dict[str, int] = {}
    for item in items.values():
        for source in item["arrays"].get("sources", []):
            key = source.partition(":")[0]
            src_counts[key] = src_counts.get(key, 0) + 1
    _print_table("Acquisition Source Distribution", sorted(src_counts.items()), total)

    catalog = _catalog()
    fixed_count = sum(1 for item in items.values() if item["fixed"])
    roll_count = sum(1 for item in items.values() if item["roll_spec"])
    option_counts: dict[str, int] = {}
    for item in items.values():
        for option_id in item["fixed"]:
            option_counts[option_id] = option_counts.get(option_id, 0) + 1
    info("")
    info("=== Option Coverage ===")
    info(f"  items with fixed options:  {fixed_count:5d}  ({_pct(fixed_count, total):5.1f}%)")
    info(f"  items with a roll_spec:    {roll_count:5d}  ({_pct(roll_count, total):5.1f}%)")
    info(f"  distinct options authored: {len(option_counts):5d} / {len(catalog)} registered")
    _print_table("Fixed Option Distribution", sorted(option_counts.items()), fixed_count or 1)

    findings = [*_collect_findings(items), *_loot_findings(records)]
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
    kind = getattr(args, "kind", "item")
    folder = {"boss": "bosses", "domain": "domains"}.get(kind, "items")
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

    if args.kind == "domain":
        if not args.add_bosses:
            raise ToolError("domain edits require --add-bosses")
        existing = _extract_array(text, "boss_ids")
        added = [v for v in _split_list(args.add_bosses) if v not in existing]
        if not added:
            fail(f"{path}: all requested bosses already present")
            return 1
        text = _merge_array_block(text, "boss_ids", existing + added)
        path.write_text(text, encoding="utf-8")
        ok(f"updated {path.relative_to(REPO_ROOT).as_posix()} (+{len(added)} bosses)")
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
