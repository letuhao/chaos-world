"""Content data tooling for game/data (ADR 0008/0009).

`audit`/`report` parse Godot `.tres` content and check the acquisition dependency
layers. `new` scaffolds a valid `.tres` so generators do not hand-write the format.
No Godot runtime required.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import NamedTuple

from . import item_migrate, options
from .common import REPO_ROOT, SRC_DIR, ToolError, fail, info, ok, warn
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


def _magnitude_bounds(unit: str, realm_id: str, rarity_index: int) -> tuple[float, float]:
    """Option value window, read from the same source the runtime uses.

    Keyed by realm ID, never by ladder position (ADR 0050). Delegates to the option
    module so the gate can never validate authored content against numbers the game
    does not roll.
    """
    window = option_magnitude_bounds(unit, realm_id, rarity_index)
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
    "loot_tier": {
        "id": "id",
        "arrays": [],
        "scalars": ["realm", "rarity"],
        "bindings": "boss_tables",
    },
    "recipes": {"id": "id", "arrays": ["inputs", "outputs"], "scalars": ["station"]},
    "bosses": {"id": "id", "arrays": ["loot"], "scalars": ["domain_id"]},
    "domains": {"id": "id", "arrays": ["boss_ids"], "scalars": []},
    # Fate and destiny content is stat-bearing like items but has no acquisition
    # graph, so it gets its own schema rather than borrowing the items rules: the
    # gates that matter here are a real stat id and a FLAT/PERCENT split that
    # respects `Stat.RATE_STATS`. A bad stat id in a `.tres` is otherwise silent,
    # because nothing re-reads the field after load.
    "fate": {
        "id": "id",
        "arrays": ["counters", "tags"],
        "dicts": ["flat_modifiers", "percent_modifiers"],
        "scalars": ["category", "visibility"],
        "rate_stats": True,
    },
    "destiny": {
        "id": "id",
        "arrays": ["grants_fates", "requires_fates", "requires_destinies", "gate_aliases"],
        "dicts": [],
        "scalars": ["group", "visibility"],
    },
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
    "destiny/fates": "fate",
    "destiny/destinies": "destiny",
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
    "destiny/fates": "fate",
    "destiny/destinies": "destiny",
}
BASE_SOURCES = {"gather", "starter"}
# `subcategory = "numeraire"` marks the economy's unit of account. It is still an ordinary
# held ItemDef: `economy`, `market` and `custody` read it with `inventory.count`/`has` and
# pass coin rows into `EconomyExchange.exchange`, which physically moves the stack. ADR 0099
# once exempted it from the acquisition requirement on the premise that it was an integer
# balance; that premise was false against the tree it shipped into, the exemption hid an
# unreachable item, and `data audit` reported the coin as unroutable. ADR 0099 named its own
# escape hatch for exactly this case and it has now fired, so the exemption is gone: the coin
# declares a real `starter` route like every other item. The marker itself stays, because it
# is what tells a designer which currency item is the unit of account rather than a good.
NUMERAIRE_SUBCATEGORY = "numeraire"
# Stats whose flat modifier is a fraction rather than a magnitude (ADR 0022).
FRACTION_FLAT_STATS = {"damage_reduction"}
REF_SOURCES = {"craft": "recipe", "boss": "boss", "domain": "domain"}
# `quest` takes an OPTIONAL reference, which is the runtime's own policy
# (`ItemSources.KINDS`, `KIND_QUEST: {"ref": REF_OPTIONAL, ...}`): a bare `quest`
# claims the kind and no quest in particular, while `quest:<id>` claims a specific
# quest and is resolved against the authored `QuestDef` set below. This used to be a
# flat "unchecked, there is no QuestDef resource yet", which stopped being true the
# moment `game/src/modules/quest/quest_def.gd` and `game/data/quest/quests/` landed —
# and the stale comment is why 1697 items went on naming a `quest:<id>` that resolves
# to nothing without one run ever saying so.
OPTIONAL_REF_SOURCES = {"quest"}
KNOWN_SOURCE_TYPES = BASE_SOURCES | set(REF_SOURCES) | OPTIONAL_REF_SOURCES
# Authored quest definitions. A `quest:<id>` source is resolved against exactly this
# set, read the way the runtime reads it: `QuestCatalog` loads
# `res://data/quest/quests/*.tres` and keys them by the main resource's `id`.
QUEST_DIR = DATA_ROOT / "quest" / "quests"
# The runtime's own table of which source kinds shipping code delivers.
# `ItemSources` is the ONLY reader of `ItemDef.sources` in `game/src`, so its
# `KINDS[*]["shipped"]` flag is the engine's own answer to "does a route exist" —
# and `RUNTIME_ROUTES` above is the gate's answer. Two declarations of one fact with
# nothing between them is precisely how a route gets declared for a kind the game
# cannot deliver and `data audit` goes green while the item stays unobtainable.
ITEM_SOURCES_SCRIPT = SRC_DIR / "modules" / "items" / "item_sources.gd"


# --- Runtime availability ----------------------------------------------------
# "Obtainable in the content graph" and "obtainable by code that ships" are two
# different questions, and only the first one is a statement about content.
# `ItemDef.sources` (`src/modules/items/item_def.gd:18`) is authoring metadata:
# nothing in `game/src` reads it, so naming a source proves nothing about whether
# a player can ever hold the item. Every source type below declares the shipping
# code that would deliver it plus the membership an item must satisfy to be
# delivered through that code. A source type with no entry has no route at all,
# so items resting on it are graph-obtainable and runtime-unreachable, and the
# audit says so instead of counting them as roots.
class Route(NamedTuple):
    """One acquisition source type and the code that can actually deliver it."""

    script: str
    """Path under `game/src` that implements the route."""

    symbols: tuple[str, ...]
    """Every marker that must be present for the route to count as shipping."""

    membership: str
    """Rule id the item must satisfy, named in the finding message."""

    detail: str
    """What that rule requires, in one clause."""

    call_sites: tuple[tuple[str, ...], ...]
    """One group per verb the route needs CALLED, each group listing the spellings
    that count as that call.

    Existence is not delivery. A route whose code is present but which nothing in
    `game/src` ever invokes delivers nothing, and the quest module is exactly that
    shape: `QuestApi.advance` and `QuestApi.complete` both exist, their ledger,
    gates and once-guard all work, a dozen tests drive them — and no file outside
    `game/tests` calls either one, so no quest completes in the game. Declaring a
    route on that evidence would raise this count while the item stayed
    unobtainable, which is the one outcome a gate exists to prevent.

    So a route counts as shipping only when every group below is found in a `.gd`
    file under `game/src`. `game/tests` is out of scope by construction, which is
    the point: a call site only a test makes is not delivery. The declaring script
    is NOT excluded — a use inside the file that declares the verb is still a use
    that runs — but no marker here collides with a route's own `symbols`, which is
    what keeps a definition from counting as its own caller.

    Spellings are the qualified call (`ItemsApi.craft(`) or the injected-`Callable`
    binding (`Callable(LootApi, "enter_domain")`), never a bare verb name. The
    trailing `(` is load-bearing: prose in a docstring names `ItemsApi.craft`
    without it, and a marker that matches a comment is a marker that lies.
    """

    by_example: str = ""
    """One production file, `path:line`-free, that demonstrates the call. Reported
    in the finding so a reader can check the claim instead of trusting it."""


RUNTIME_ROUTES: dict[str, Route] = {
    "craft": Route(
        "modules/items/api.gd",
        ("static func craft(",),
        "recipe_output",
        "a recipe whose inputs are all reachable produces it",
        (("ItemsApi.craft(",),),
        "ui/screens/crafting_screen.gd",
    ),
    # `LootApi.enter_domain` spawns a boss and `LootApi.strike` defeats it, and
    # `LootContent.table_for_boss` answers from the boss's own `loot` list, so a
    # `boss:` source is delivered once an authored encounter hosts that boss.
    #
    # `enter_domain` has NO direct call site in `game/src`: `ui/` may not name a
    # module the arch rules do not declare, so the composition root injects it as a
    # `Callable` on `LootBridge` and the screen invokes it through `call_action`.
    # Both halves are required, because either alone is a lie — a binding nothing
    # reads is a dead end, and `call_action(&"enter"` is meaningless unbound. The
    # bare spelling `LootApi.enter_domain(` is deliberately NOT a marker: the only
    # occurrence of it under `game/src` is the signature inside a docstring in
    # `ui/screens/loot_bridge.gd`, which is exactly the prose false positive the
    # requirement is meant to exclude.
    "boss": Route(
        "modules/loot/api.gd",
        ("static func enter_domain(", "static func strike("),
        "hosted_boss",
        "an authored LootEncounterDef lists it in boss_ids, so enter_domain spawns it",
        (
            ('Callable(LootApi, "enter_domain")', 'call_action(&"enter"'),
            ("LootApi.strike(",),
        ),
        "app/item_workbench_app.gd binds it; ui/screens/loot_encounter.gd calls it",
    ),
    "domain": Route(
        "modules/loot/api.gd",
        ("static func enter_domain(",),
        "entered_domain",
        "an authored LootEncounterDef references it and one of its bosses drops the item",
        (('Callable(LootApi, "enter_domain")', 'call_action(&"enter"'),),
        "app/item_workbench_app.gd binds it; ui/screens/loot_encounter.gd calls it",
    ),
    # The only grant of a starter item is the composition root's own list.
    "starter": Route(
        "app/item_workbench_app.gd",
        ("STARTER_ITEMS",),
        "granted_id",
        "the composition root lists its id in STARTER_ITEMS",
        (("for item_id in STARTER_ITEMS:",),),
        "app/item_workbench_app.gd",
    ),
    # `gather` was the LAST kind with no route, and it was missing a SUBSYSTEM rather
    # than a wire. `ForageApi.harvest` works a held node through `HoldingsApi.accrue`
    # and settles the units into a real item through the granter `app/` installs, so the
    # verb is real and the `shipped` flag in `ItemSources.KINDS` followed it.
    #
    # BOTH call-site groups are required and neither is satisfied by the declaring file:
    # the harvest verb and the grant half are two different concerns in two different
    # layers, and a route that only had one of them would deliver accruals nobody could
    # spend. `game/tests` cannot satisfy either group by construction.
    "gather": Route(
        "modules/forage/api.gd",
        ("static func harvest(", "static func set_granter("),
        "gatherable_item",
        "an item named in ForageApi.NODE_YIELDS, produced by a node the actor holds",
        (
            ("ForageApi.harvest(",),
            ("ForageApi.set_granter(", "ForageGranary.deliver"),
        ),
        "app/economy_boot.gd calls ForageApi.harvest through a screen's action; "
        "app/economy_boot.gd binds ForageGranary.deliver",
    ),
}
# Authored encounter content is what makes a boss reachable: `LootApi.enter_domain`
# resolves an encounter by domain id and spawns `encounter.boss_ids`.
ENCOUNTER_DIR = DATA_ROOT / "loot" / "encounters"

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
        if name == "audit":
            action.add_argument(
                "--fail-on-unreachable",
                action="store_true",
                help="also fail when content is graph-obtainable but no shipping route "
                "delivers it (default: report only)",
            )

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
        return _audit_command(root, getattr(args, "fail_on_unreachable", False))
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


def _extract_bindings(text: str) -> list[tuple[str, str]]:
    """`{boss_id, table_id}` pairs from a tier's `boss_tables` array.

    Read as ordered token runs rather than per-line fields, because each binding
    is authored as one inline dictionary.
    """
    boss_ids = re.findall(r'"boss_id":\s*&"([^"]+)"', text)
    table_ids = re.findall(r'"table_id":\s*&"([^"]+)"', text)
    return list(zip(boss_ids, table_ids, strict=False))


def _authored_boss_drops(records: dict) -> dict[str, set[str]]:
    """boss id -> every item an authored loot table bound to it can produce.

    A boss's drops are declared in exactly one place. Normally that is its
    `BossDef.loot` array; when the boss is bound in an authored loot tier the
    table is the authority instead (`LootValidator` rejects a boss carrying
    both). The gate has to accept either, or it would demand a second
    declaration the runtime deliberately ignores.
    """
    drops: dict[str, set[str]] = {}
    tables = records.get("loot_table", {})

    def collect(table_id: str, seen: set[str]) -> set[str]:
        if table_id in seen:
            return set()
        seen.add(table_id)
        table = tables.get(table_id, {})
        found = set(table.get("entries", []))
        for nested in table.get("nested", []):
            found |= collect(nested, seen)
        return found

    for tier in records.get("loot_tier", {}).values():
        for boss_id, table_id in tier.get("bindings", []):
            drops.setdefault(boss_id, set()).update(collect(table_id, set()))
    return drops


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
            "bindings": [],
            "legacy": bool(re.search(r"(?m)^\s*(flat_modifiers|percent_modifiers)\s*=", text)),
        }
        for field in schema["arrays"]:
            record["arrays"][field] = _extract_array(text, field)
        for field in schema.get("dicts", []):
            record["dicts"][field] = _extract_dict(text, field)
        for field in schema["scalars"]:
            record["scalars"][field] = _extract_scalar(text, field) or ""
        if schema.get("bindings"):
            record["bindings"] = _extract_bindings(text)
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
    # A boss's drops are declared in exactly one place, and there are two
    # authoring eras for it: a `BossDef.loot` array, or an authored loot table
    # bound to the boss in an encounter tier (`LootValidator` rejects a boss
    # carrying both). The gate has to read whichever one is populated, or every
    # table-hosted boss would report each of its drops as a false gap.
    authored_drops = _authored_boss_drops(records)
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
    #
    # Read from `BossDef.loot` alone, deliberately. A loot table may list an item
    # the definition does not name as a drop — the shipped ember and storm
    # tables both do — and that is a statement about the table, not about the
    # item's own acquisition claim. Enforcing it here would gate content the
    # loot module already accepts, so the check stays where the claim is authored.
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
        # A numeraire is an ordinary held item here, not an integer balance.
        #
        # ADR 0099 originally exempted it from the acquisition requirement on the premise
        # that "nothing ever puts a coin `ItemDef` in an inventory". That premise was false
        # against the tree it shipped into: `economy`, `market` and `custody` all read the
        # coin with `inventory.count`/`inventory.has` and pass coin ROWS into
        # `EconomyExchange.exchange`, which physically moves the stack. So the exemption
        # was not describing a unit of account, it was hiding an unreachable item — and
        # `data audit` duly reported `curr_spirit_coin` as "obtainable in the content graph
        # but not through any shipping route". ADR 0099 named its own escape hatch:
        # "If the economy later grows held currency — coins as inventory rather than a
        # balance — this decision is wrong and must be superseded." It has, so the
        # exemption goes and the coin acquires a real route like everything else.
        #
        # Note the coin must NOT simply declare `gather`: `item_sources.KINDS[gather]` is
        # `shipped: false`, so a gather source is graph-rooted but still runtime-unreachable.
        # `starter` is the one route that both roots the graph and is actually granted
        # (`app/item_workbench_app.gd` STARTER_ITEMS loop), which is why that is the source.
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
                elif item_id not in bosses[ref]["arrays"].get("loot", []) and (
                    item_id not in authored_drops.get(ref, set())
                ):
                    gaps.append(f"item {item_id}: boss '{ref}' does not drop it")
            elif target_type == "domain" and ref not in domains:
                gaps.append(f"item {item_id}: domain '{ref}' is not defined")

    cycle = _find_recipe_cycle(recipes)
    if cycle:
        gaps.append("recipe cycle: " + " -> ".join(cycle))
    gaps.extend(_unobtainable(items, recipes))
    return gaps


def _close_recipes(roots: set[str], recipes: dict, allow_craft: bool = True) -> set[str]:
    """Roots plus every recipe output whose whole input set is already reachable.

    Iterated to a fixed point, so a chain of any depth resolves regardless of
    the order the records are visited in.

    `allow_craft` is what makes the `craft` ROUTE load-bearing. Closing over
    recipes is the one thing this gate does that no declared route describes, so
    without this flag the `craft` entry in `RUNTIME_ROUTES` is decoration:
    deleting it outright still reported 1553 deliverable, because the closure
    below ran anyway. `_obtainable` passes the default because the GRAPH question
    is "can the corpus reach it", which is a statement about content and must not
    consult a runtime route; `_runtime_reachable` passes the live-ness of the
    `craft` route, so breaking that route really does reduce the count.
    """
    obtainable = set(roots)
    if not allow_craft:
        return obtainable
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


def _obtainable(items: dict, recipes: dict) -> set[str]:
    """Items the content graph can acquire, by closing over craftable recipes.

    Roots are items with a non-craft source. This is a statement about the
    content graph only: it says nothing about whether shipping code can deliver
    those sources. `_runtime_reachable` is the other measurement.
    """
    root_types = KNOWN_SOURCE_TYPES - {"craft"}
    roots = {
        item_id
        for item_id, item in items.items()
        if any(
            source.partition(":")[0] in root_types for source in item["arrays"].get("sources", [])
        )
    }
    return _close_recipes(roots, recipes)


def _unobtainable(items: dict, recipes: dict) -> list[str]:
    """Items nothing in the corpus can ever produce or drop (DEF-0036)."""
    obtainable = _obtainable(items, recipes)
    orphans = sorted(set(items) - obtainable)
    if not orphans:
        return []
    listed = ", ".join(orphans[:10])
    more = f" (+{len(orphans) - 10} more)" if len(orphans) > 10 else ""
    return [f"{len(orphans)} item(s) cannot be acquired from any source: {listed}{more}"]


# --- Runtime reachability ----------------------------------------------------


def _route_present(route: Route) -> bool:
    """Whether the production code backing a route is actually in the tree."""
    path = SRC_DIR / route.script
    if not path.is_file():
        return False
    text = path.read_text(encoding="utf-8", errors="replace")
    return all(symbol in text for symbol in route.symbols)


# Every `.gd` file under `game/src`, read once per run. `game/tests` is deliberately
# outside this set: a call site only a test makes is not a delivery path, and that
# is the whole distinction `call_sites` exists to draw.
_GDSCRIPT_FILES: list[Path] | None = None
_GDSCRIPT_TEXT: dict[Path, str] = {}
# Liveness per `Route`, and the text cache above, exist because `_runtime_roots`
# asks the question once per ITEM PER SOURCE — about 16_000 times over this corpus.
# Uncached that is 16_000 sweeps of every shipped script, which measured 168
# seconds; memoized it is four. Both caches are per-process and this is a batch
# tool that reads the tree once, so nothing observes a stale answer. A long-lived
# host that edited `game/src` between two audits would need `clear` called.
_ROUTE_LIVE: dict[Route, bool] = {}


def _gdscript_files() -> list[Path]:
    global _GDSCRIPT_FILES
    if _GDSCRIPT_FILES is None:
        _GDSCRIPT_FILES = (
            sorted(path for path in SRC_DIR.rglob("*.gd") if path.is_file())
            if SRC_DIR.is_dir()
            else []
        )
    return _GDSCRIPT_FILES


# GDScript's triple-quote delimiter, built rather than written: this file's own
# docstrings use the same delimiter, so a literal would terminate them.
_TRIPLE = '"' * 3


def _code_only(text: str) -> str:
    """`text` with every `#` comment removed, string literals respected.

    A marker that matches a comment is a marker that lies, and this corpus is full
    of prose that names a call: `ui/screens/crafting_screen.gd` says
    "`ItemsApi.craft`" in its own class docstring, and `ui/screens/loot_bridge.gd`
    prints the full `LootApi.enter_domain(actor, domain_id, ...)` signature inside a
    comment. Matching raw text therefore counts documentation as a call site, which
    is the same class of bug as counting a definition as its own caller.

    `#` inside a string is deliberately left alone, because a marker can legitimately
    BE a string — the loot route's call site is `Callable(LootApi, "enter_domain")`.
    Triple-quoted blocks are skipped whole for the same reason.
    """
    out: list[str] = []
    for line in text.splitlines():
        quote = ""
        cut = len(line)
        index = 0
        while index < len(line):
            if line.startswith(_TRIPLE, index):
                closing = line.find(_TRIPLE, index + 3)
                index = len(line) if closing < 0 else closing + 3
                continue
            char = line[index]
            if quote:
                if char == "\\":
                    index += 2
                    continue
                if char == quote:
                    quote = ""
            elif char in ('"', "'"):
                quote = char
            elif char == "#":
                cut = index
                break
            index += 1
        out.append(line[:cut])
    return "\n".join(out)


def _gdscript_code(path: Path) -> str:
    if path not in _GDSCRIPT_TEXT:
        _GDSCRIPT_TEXT[path] = _code_only(path.read_text(encoding="utf-8", errors="replace"))
    return _GDSCRIPT_TEXT[path]


def _production_callers(marker: str, exclude_dir: Path | None = None) -> list[str]:
    """`src/`-relative paths of every shipped file whose CODE contains `marker`.

    `exclude_dir` is the declaring MODULE's own directory, and it is excluded on
    purpose: `QuestBeatHandler` calls `QuestApi.advance`, so a `quest` route whose
    call site is `QuestApi.advance(` would be satisfied by a file inside the very
    module that declares the route. A module talking to itself is not an external
    entry point, and accepting one would make the check pass for precisely the
    module it exists to disqualify. Composition-root routes (`app/`) are not
    modules and are not excluded: `STARTER_ITEMS` is a list the composition root
    reads in its own file, and that read IS the delivery.
    """
    out: list[str] = []
    for path in _gdscript_files():
        if exclude_dir is not None and exclude_dir in path.parents:
            continue
        if marker in _gdscript_code(path):
            out.append(path.relative_to(SRC_DIR).as_posix())
    return out


def _called_from_production(spellings: tuple[str, ...], exclude_dir: Path | None) -> bool:
    """Whether ANY of the caller's spellings appears in shipped code."""
    return any(_production_callers(marker, exclude_dir) for marker in spellings)


def _route_module_dir(route: Route) -> Path | None:
    """The declaring MODULE's directory (absolute), or None when not in a module.

    Absolute because it is compared against `Path.parents` of absolute
    `SRC_DIR.rglob` results; a relative `modules/quest` never matches either, which
    silently disables the exclusion and lets a module vouch for itself.
    """
    script = Path(route.script)
    if len(script.parts) < 2 or script.parts[0] != "modules":
        return None
    return SRC_DIR.joinpath(*script.parts[:2])


def _route_live(route: Route | None) -> bool:
    """Whether a route's code both EXISTS and is CALLED by shipped code.

    This is the claim the whole gate rests on, so it is the whole check: the
    definition is present, and every verb the route needs is invoked from
    somewhere under `game/src`. A route with no `call_sites` at all is NOT live —
    a route nobody declared a caller for has not been argued for, and defaulting
    it to shipping would make the check vacuous for exactly the routes added later.
    A `None` route is the "no route declared for this kind" case and is not live.
    """
    if route is None:
        return False
    if route not in _ROUTE_LIVE:
        own = _route_module_dir(route)
        _ROUTE_LIVE[route] = bool(
            route.call_sites
            and _route_present(route)
            and all(_called_from_production(group, own) for group in route.call_sites)
        )
    return _ROUTE_LIVE[route]


def _hosted_bosses() -> set[str]:
    """Boss ids an authored encounter can spawn through `LootApi.enter_domain`."""
    if not ENCOUNTER_DIR.is_dir():
        return set()
    hosted: set[str] = set()
    for path in sorted(ENCOUNTER_DIR.glob("*.tres")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for block in re.findall(r"(?ms)^boss_ids\s*=\s*Array\[StringName\]\(\[(.*?)\]\)", text):
            hosted |= set(re.findall(r'&"([^"]*)"', block))
    return hosted


def _entered_domains() -> dict[str, set[str]]:
    """domain id -> the boss ids an authored encounter spawns inside it."""
    domains: dict[str, set[str]] = {}
    if not ENCOUNTER_DIR.is_dir():
        return domains
    for path in sorted(ENCOUNTER_DIR.glob("*.tres")):
        text = path.read_text(encoding="utf-8", errors="replace")
        domain = re.search(r'(?m)^domain_id\s*=\s*&"([^"]*)"', text)
        if not domain:
            continue
        bosses = domains.setdefault(domain.group(1), set())
        for block in re.findall(r"(?ms)^boss_ids\s*=\s*Array\[StringName\]\(\[(.*?)\]\)", text):
            bosses |= set(re.findall(r'&"([^"]*)"', block))
    return domains


def _gatherable_ids() -> set[str]:
    """Item ids a `gather` source can actually produce, read out of the runtime table.

    `ForageApi.NODE_YIELDS` is the ONLY place in `game/src` that knows what a resource
    node yields, and it had to be: `ResourceNodeDef` carries no item id and
    `test_a_node_definition_names_no_item` pins that field list, so there is nowhere else
    the answer could live. This function reads that one table rather than keeping a second
    copy here, so a yield authored in the game and a yield counted by this gate cannot
    drift apart without one of the two reading a different file than it thinks.

    Empty is an honest answer rather than an error: a build with no `forage` module has no
    gather route at all, and reporting every `gather`-sourced item as undeliverable is
    exactly what should happen then.
    """
    route = RUNTIME_ROUTES.get("gather")
    if route is None:
        return set()
    path = SRC_DIR / route.script
    if not path.is_file():
        return set()
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"(?ms)^const NODE_YIELDS[^\n=]*=\s*\{(.*?)^\}", text)
    if not match:
        return set()
    return set(re.findall(r'&"([^"]+)"', match.group(1)))


def _granted_ids() -> set[str]:
    """Item ids the composition root hands a fresh actor.

    Reads the path off the `starter` route but tolerates its absence: this is
    membership evidence, not a reason to crash, and a gate that raises when a
    route is removed cannot measure the removal. With no route there is no path
    to read and the honest answer is "nothing is granted".
    """
    route = RUNTIME_ROUTES.get("starter")
    if route is None:
        return set()
    path = SRC_DIR / route.script
    if not path.is_file():
        return set()
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"(?ms)^const STARTER_ITEMS[^=]*=\s*\[(.*?)\]", text)
    return set(re.findall(r'&"([^"]*)"', match.group(1))) if match else set()


def _authored_quest_ids() -> set[str]:
    """Quest ids the authored `QuestDef` tree defines, read as the runtime reads them.

    `QuestCatalog` loads every `.tres` in this folder and keys it by the main
    resource's `id`, so this is the set a `quest:<id>` source can possibly resolve to.
    """
    if not QUEST_DIR.is_dir():
        return set()
    known: set[str] = set()
    for path in sorted(QUEST_DIR.glob("*.tres")):
        record_id = _extract_scalar(path.read_text(encoding="utf-8", errors="replace"), "id")
        if record_id:
            known.add(record_id)
    return known


def _runtime_shipped_kinds() -> dict[str, bool] | None:
    """kind -> `ItemSources.is_shipped(kind)`, read out of the runtime's own table.

    `ItemSources.KINDS` is a GDScript `const` dictionary keyed by the `KIND_*`
    constants, so this resolves those constants the way the engine does and reads the
    `shipped` flag off each row. `None` means the table could not be read at all, which
    is reported rather than treated as "nothing ships" — a parser that silently returned
    an empty table would make every route look unshipped and turn a file the game ships
    into a green audit.
    """
    if not ITEM_SOURCES_SCRIPT.is_file():
        return None
    text = ITEM_SOURCES_SCRIPT.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"(?ms)^\s*const KINDS[^\n=]*=\s*\{(.*?)^\}", text)
    if not match:
        return None
    aliases = {
        name: value
        for name, value in re.findall(r'(?m)^\s*const\s+(KIND_[A-Z_]+)\s*:?=\s*&"([a-z_]+)"', text)
    }
    shipped: dict[str, bool] = {}
    for key, flags in re.findall(r"(?m)^\s*([A-Za-z_&][\w]*)\s*:\s*\{([^}]*)\}", match.group(1)):
        flag = re.search(r'"shipped"\s*:\s*(true|false)', flags)
        if flag is None:
            continue
        kind = aliases.get(key, key.strip('"'))
        shipped[kind] = flag.group(1) == "true"
    return shipped or None


def _route_agreement_problems(records: dict) -> list[str]:
    """The gate's routes and the runtime's own routes must agree, in both directions.

    `RUNTIME_ROUTES` is what `data audit` trusts; `ItemSources.KINDS` is what the game
    asks. An item resting on a kind only one of them calls shipped is unobtainable, and
    the failure is silent in the worst direction: declare a route in `tools/data.py` and
    the count goes up while `ItemSources.resolve` still answers the player
    `no_shipped_route`. That is a gate that lies, so it is named here.

    The other direction matters for the same reason. A kind the runtime ships but the
    gate has no route for reports every item that rests on it as unreachable, which
    under-reports — the audit would blame content for a gap that is one dict entry away.
    """
    shipped = _runtime_shipped_kinds()
    if shipped is None:
        return [
            f"{ITEM_SOURCES_SCRIPT.relative_to(REPO_ROOT).as_posix()}: cannot read the "
            "runtime's `KINDS` table, so no route declaration can be cross-checked against "
            "the engine's own answer; fix the file or this audit is trusting one side of a "
            "two-sided claim"
        ]
    problems: list[str] = []
    items = records.get("item", {})
    declared: dict[str, int] = {}
    for item in items.values():
        for source in item["arrays"].get("sources", []):
            kind = source.partition(":")[0]
            declared[kind] = declared.get(kind, 0) + 1
    for kind in sorted(set(RUNTIME_ROUTES) | set(declared)):
        in_gate = kind in RUNTIME_ROUTES
        in_game = shipped.get(kind)
        if in_gate and in_game is False:
            problems.append(
                f"acquisition source '{kind}': tools/data.py declares a shipping route "
                f"({RUNTIME_ROUTES[kind].script}) but "
                f"{ITEM_SOURCES_SCRIPT.relative_to(REPO_ROOT).as_posix()} marks it "
                f"shipped=false, so {declared.get(kind, 0)} item(s) would be counted as "
                "deliverable while the game still refuses to deliver them. Fix the route or "
                "the runtime table — never both"
            )
        if kind in declared and in_game is None:
            problems.append(
                f"acquisition source '{kind}': {declared[kind]} item(s) declare it and "
                f"{ITEM_SOURCES_SCRIPT.relative_to(REPO_ROOT).as_posix()} KINDS does not "
                "carry it, so the corpus and the only reader of `ItemDef.sources` disagree "
                "about the vocabulary"
            )
        if in_game and not in_gate and kind in declared:
            problems.append(
                f"acquisition source '{kind}': the runtime marks it shipped but "
                f"tools/data.py declares no route, so {declared[kind]} item(s) are reported "
                "unreachable when the game may well deliver them"
            )
    return problems


def _quest_ref_findings(records: dict) -> list[tuple[str, str]]:
    """Every `quest:<id>` an item names, resolved against the authored quest set.

    A bare `quest` is a claim about the kind and is legal. `quest:<id>` is a claim about
    a specific quest, and it reads exactly like a working reference — so when it names a
    quest no authored `QuestDef` defines, nothing reports the absence and the item looks
    routed. Measured today: 442 distinct ids across 3076 items, none of them an authored
    quest.
    """
    items = records.get("item", {})
    if not items:
        return []
    known = _authored_quest_ids()
    dangling: dict[str, list[str]] = {}
    resolved = 0
    for item_id, item in sorted(items.items()):
        for source in item["arrays"].get("sources", []):
            kind, _, ref = source.partition(":")
            if kind != "quest" or not ref:
                continue
            if ref in known:
                resolved += 1
                continue
            dangling.setdefault(ref, []).append(item_id)
    if not dangling:
        return []
    total = sum(len(ids) for ids in dangling.values())
    listed = ", ".join(sorted(dangling)[:6])
    more = f" (+{len(dangling) - 6} more)" if len(dangling) > 6 else ""
    return [
        (
            "warn",
            f"{total} item(s) declare a `quest:<id>` naming one of {len(dangling)} quest "
            f"ids no authored QuestDef defines ({listed}{more}); {resolved} resolve, so a "
            "quest source is a claim about a quest that does not exist",
        )
    ]


def _boss_drops(bosses: dict, authored: dict | None = None) -> dict[str, set[str]]:
    """boss id -> the item ids it can hand out.

    Both authoring eras feed one answer: the legacy `BossDef.loot` list, and the
    authored loot table bound to the boss in an encounter tier. `LootValidator`
    rejects a boss carrying both, so this never has to choose.
    """
    drops: dict[str, set[str]] = {boss_id: set() for boss_id in bosses}
    for boss_id, boss in bosses.items():
        drops[boss_id] = set(boss["arrays"].get("loot", []))
    for boss_id, ids in (authored or {}).items():
        drops.setdefault(boss_id, set()).update(ids)
    return drops


def _runtime_roots(
    items: dict, bosses: dict, authored: dict | None = None
) -> tuple[set[str], dict[str, tuple[str, ...]]]:
    """Items a present route can deliver outright, and why the rest cannot.

    The second return value maps every rejected item to EVERY source type that rejected
    it, not the first. It used to keep one kind per item, which made the printed
    breakdown read as a partition when it is not: an item declaring both `gather` and
    `quest` rests on two kinds no route delivers, and reporting it under whichever came
    first in its own `sources` array understates both classes by exactly the overlap.
    The total is unchanged; the attribution is what the corpus actually says.

    ## A route alone cannot inflate this number

    Delivery is decided by the per-kind membership branches below, not by the mere
    presence of a `RUNTIME_ROUTES` entry: `boss`, `starter` and `domain` each have a
    branch, and any other kind falls through to `unshipped.append(kind)`. So adding a
    `Route` for a kind with no branch leaves the count exactly where it was — measured,
    declaring `quest` with a call site that satisfies `_route_live` still reports 1553.
    That is deliberate and is the second of two independent guards: `_route_live` asks
    whether the code runs, and this function asks whether the rule can be satisfied,
    and a kind has to pass both.
    """
    hosted = _hosted_bosses()
    domains = _entered_domains()
    drops = _boss_drops(bosses, authored)
    granted = _granted_ids()
    roots: set[str] = set()
    blocked: dict[str, tuple[str, ...]] = {}
    for item_id, item in items.items():
        unshipped: list[str] = []
        delivered = False
        for source in item["arrays"].get("sources", []):
            kind = source.partition(":")[0]
            if kind == "craft":
                # A recipe output is never a root; it is reachable when its inputs are.
                continue
            route = RUNTIME_ROUTES.get(kind)
            if not _route_live(route):
                unshipped.append(kind)
                continue
            _, _, ref = source.partition(":")
            if kind == "boss" and ref in hosted:
                delivered = True
                break
            if kind == "starter" and item_id in granted:
                delivered = True
                break
            if kind == "domain" and any(
                item_id in drops.get(boss_id, set()) for boss_id in domains.get(ref, set())
            ):
                delivered = True
                break
            if kind == "gather" and item_id in _gatherable_ids():
                delivered = True
                break
            unshipped.append(kind)
        if delivered:
            roots.add(item_id)
        else:
            blocked[item_id] = tuple(sorted(set(unshipped)))
    return roots, blocked


def _runtime_reachable(
    items: dict, recipes: dict, bosses: dict, authored: dict | None = None
) -> tuple[set[str], dict[str, tuple[str, ...]]]:
    """What shipping code can deliver: route-satisfying roots, closed over recipes."""
    roots, blocked = _runtime_roots(items, bosses, authored)
    reachable = _close_recipes(roots, recipes, _route_live(RUNTIME_ROUTES.get("craft")))
    # Anything the closure reached is not blocked, whatever its own sources say.
    for item_id in reachable - set(roots):
        blocked.pop(item_id, None)
    # What is left is attributed to the union of its recipe inputs' blocking kinds. An
    # item declaring only `craft:` names no kind of its own — it is unobtainable because
    # something it is made from is — so the union is the only honest label, and an output
    # fed entirely by craft-only chains reads as `an unreachable input`. Run AFTER the
    # pop above, or the closure would erase the attribution it just computed.
    inputs: dict[str, set[str]] = {}
    for recipe in recipes.values():
        for output in recipe["arrays"].get("outputs", []):
            kinds: set[str] = set()
            for item_id in recipe["arrays"].get("inputs", []):
                kinds.update(blocked.get(item_id, ()))
            if kinds:
                inputs.setdefault(output, set()).update(kinds)
    for item_id, kinds in inputs.items():
        if item_id not in reachable:
            blocked[item_id] = tuple(sorted(kinds))
    return reachable, blocked


def _route_roots_by_kind(
    items: dict, bosses: dict, authored: dict | None = None
) -> tuple[dict[str, set[str]], set[str]]:
    """Which items each LIVE route delivers, keyed by kind, and the outright total.

    Separate from `_runtime_roots` because that function answers "is this item
    reachable at all" and throws away which kind did it. This one keeps the
    attribution, and it exists to make a route that delivers NOTHING visible: a
    `Route` entry whose corpus membership is empty is indistinguishable from a
    working one in every other number this file prints, and an undelivered route
    is exactly the thing a mutation cannot break — measured today, `domain` and
    `starter` are live routes that 0 of 7982 items claim, so breaking either one
    moves the count by zero and proves nothing about the gate.

    `craft` is deliberately NOT counted here. A recipe output is never a root by
    construction (`_runtime_roots` skips `craft` explicitly), so counting roots
    would report `craft 0` on a corpus where crafting delivers hundreds of items —
    precisely the under-reporting a validator must never do. The caller folds the
    recipe closure in, which makes the per-kind numbers a partition of the total.
    """
    hosted = _hosted_bosses()
    domains = _entered_domains()
    drops = _boss_drops(bosses, authored)
    granted = _granted_ids()
    out: dict[str, set[str]] = {}
    outright: set[str] = set()
    for kind in RUNTIME_ROUTES:
        if kind == "craft" or not _route_live(RUNTIME_ROUTES[kind]):
            continue
        delivered: set[str] = set()
        for item_id, item in items.items():
            for source in item["arrays"].get("sources", []):
                if source.partition(":")[0] != kind:
                    continue
                _, _, ref = source.partition(":")
                if kind == "boss" and ref in hosted:
                    delivered.add(item_id)
                    break
                if kind == "starter" and item_id in granted:
                    delivered.add(item_id)
                    break
                if kind == "domain" and any(
                    item_id in drops.get(boss_id, set()) for boss_id in domains.get(ref, set())
                ):
                    delivered.add(item_id)
                    break
                if kind == "gather" and item_id in _gatherable_ids():
                    delivered.add(item_id)
                    break
        out[kind] = delivered
        outright |= delivered
    return out, outright


def _route_delivery_findings(records: dict) -> list[tuple[str, str]]:
    """Every live route, and how many items it actually delivers.

    Reported for ALL live routes, not only the empty ones. A route's reach is the
    only evidence that its `membership` rule is doing any work, and a rule that
    matches nothing is indistinguishable from a rule that was never checked.
    """
    items = records.get("item", {})
    recipes = records.get("recipe", {})
    if not items:
        return []
    by_kind, outright = _route_roots_by_kind(
        items, records.get("boss", {}), _authored_boss_drops(records)
    )
    if _route_live(RUNTIME_ROUTES.get("craft")):
        by_kind["craft"] = _close_recipes(outright, recipes, True) - outright
    live = sorted(kind for kind in by_kind if _route_live(RUNTIME_ROUTES[kind]))
    if not live:
        return []
    parts = ", ".join(f"{kind} {len(by_kind[kind])}" for kind in live)
    findings: list[tuple[str, str]] = [
        (
            "info",
            "delivered per live route, a partition of the deliverable total "
            f"(sums to {sum(len(by_kind[k]) for k in live)}): {parts}",
        )
    ]
    idle = [kind for kind in live if not by_kind[kind]]
    if idle:
        findings.append(
            (
                "warn",
                f"{len(idle)} declared route(s) deliver nothing because no item in the "
                f"corpus declares them ({', '.join(idle)}); the route is real and called, so "
                "this is a content gap — add a `sources` entry that names it — and not a "
                "wiring fault. Breaking such a route cannot move the deliverable count, "
                "which is why the count alone is not evidence a route works",
            )
        )
    return findings


def _runtime_findings(records: dict) -> list[tuple[str, str]]:
    """Graph-obtainable content that no shipping code can deliver.

    Level is always `warn`. The shortfall is not one kind of gap, and the old wording
    ("no forager, no quest system") was wrong about half of it, so the two are now named
    for what they are:

      - `gather` WAS a MISSING subsystem and no longer is. It is recorded here because
        the shape of the gap is the interesting part and it is the reason the fix had to
        be shaped the way it was: `holdings` is custody, not gathering. `ResourceNodeDef`
        carries no item id at all, `accrue` credits `yield_per_period * periods` abstract
        units into an obligation line, `settle` hands those units back to "the caller's own
        accounting", and `holdings` declares no `items` edge. So the conversion could not be
        bolted onto the module that owns nodes. It ships as the `forage` module, which owns
        the harvest RULE and takes the item half as an injected `Callable` that `app/`
        binds — because `ItemsApi` is at its twelve-method cap and `Crafting.resolve` is
        `items` internals only `app/` may name. The route went live only after an item
        demonstrably arrives.
      - `quest` is an UNWIRED one, and unwired is now MEASURED rather than inferred.
        The module ships and its ledger, gates and once-guard all work, but four
        separate things each block delivery on their own:
          1. `QuestGrants.pay` records an item grant as unspent with
             `no_inventory_dependency`, and `quest` declares no `items` edge;
          2. nothing under `game/src` calls `QuestApi.accept`, `.advance` or
             `.complete` — every caller is a test, so `QuestGrants.pay` is
             unreachable from the game and no quest can complete at all. The
             `BeatDirector` that would call it is constructed only by tests;
          3. 442 distinct authored `quest:<id>` refs name 0 quests that exist;
          4. the single authored quest that does grant an item is one item.
        Item (2) is the one a `call_sites` check exists to catch: it is a module
        whose verbs exist, whose tests pass, and whose call graph reaches nothing.
      - Missing authored content, as before: no encounter hosting the bosses that carry
        their drops.

    `quest` therefore still carries NO `Route`, and that is the finding rather than an
    omission. A `Route` is a claim that shipped code delivers the item, and
    `call_sites` is what makes the claim checkable: the declaring verb must be
    invoked from `game/src`, not only from `game/tests`. Declaring `quest` on the
    evidence that "the module exists and its tests pass" is the exact failure this
    gate exists to prevent, and it is the one that raises the count while the item
    stays unobtainable. `gather` is declared, and its `call_sites` are the two groups
    a delivery actually needs — someone must CALL `ForageApi.harvest` and someone must
    BIND the granter — so declaring it is a checkable claim rather than a flag flip.

    None of that is a data defect inside a subsystem that already ships, so none belongs
    in the gating set; what belongs there is reported, loudly, every run. `data audit
    --fail-on-unreachable` promotes these to failures for a caller that wants the gate.
    """
    items = records.get("item", {})
    recipes = records.get("recipe", {})
    bosses = records.get("boss", {})
    if not items:
        return []
    findings: list[tuple[str, str]] = []

    declared: dict[str, int] = {}
    for item in items.values():
        for source in item["arrays"].get("sources", []):
            kind = source.partition(":")[0]
            declared[kind] = declared.get(kind, 0) + 1

    for kind in sorted(declared):
        route = RUNTIME_ROUTES.get(kind)
        if _route_live(route):
            continue
        # Three refusals, three different repairs, so they are named rather than
        # collapsed. "no route declared" and "the route's code is never called"
        # read the same to anyone skimming, and only the second one is a wiring
        # bug: the module is already there and the game simply never asks it.
        if route is None:
            expected = (
                "no acquisition route is declared for it in tools/data.py, so no shipping "
                "code claims to deliver it"
            )
        elif not route.call_sites:
            expected = (
                f"{route.script} defines {' / '.join(route.symbols)} but the route "
                "declares no production call site, so nothing in game/src is proven to "
                "invoke it; add the caller's spelling to `call_sites` or drop the route"
            )
        elif not _route_present(route):
            expected = f"{route.script} must still define {' / '.join(route.symbols)}"
        else:
            missing = [
                " or ".join(group)
                for group in route.call_sites
                if not _called_from_production(group, _route_module_dir(route))
            ]
            expected = (
                f"{route.script} defines {' / '.join(route.symbols)}, but no file under "
                f"game/src calls {'; '.join(missing)} — the code ships and the game never "
                "runs it, so a call site only game/tests makes is not a delivery path"
            )
        findings.append(
            (
                "warn",
                f"acquisition source '{kind}' has no shipping route ({expected}); "
                f"{declared[kind]} item(s) declare it",
            )
        )

    # The gate's routes against the runtime's own. Checked before anything is counted as
    # deliverable, because a route the game refuses to honour makes every number below
    # an overstatement rather than a shortfall.
    for problem in _route_agreement_problems(records):
        findings.append(("warn", problem))
    findings.extend(_quest_ref_findings(records))
    for message in _route_delivery_findings(records):
        findings.append(message)

    reachable, blocked = _runtime_reachable(items, recipes, bosses, _authored_boss_drops(records))
    orphans = sorted(set(items) - reachable)
    if orphans:
        # Every kind each orphan rests on, so the breakdown is a cover rather than a
        # partition. `gather 2145, quest 3025` on a 3850 shortfall is only honest if the
        # reader knows 1349 items are in both columns, which a per-item single kind could
        # never say.
        per_kind: dict[str, int] = {}
        signatures: dict[tuple[str, ...], int] = {}
        for item_id in orphans:
            kinds = blocked.get(item_id, ())
            if not kinds:
                # A recipe output whose inputs are unreachable: no kind of its own.
                signatures[("an unreachable input",)] = (
                    signatures.get(("an unreachable input",), 0) + 1
                )
                continue
            signatures[kinds] = signatures.get(kinds, 0) + 1
            for kind in kinds:
                per_kind[kind] = per_kind.get(kind, 0) + 1
        columns = ", ".join(f"{kind} {count}" for kind, count in sorted(per_kind.items()))
        breakdown = "; ".join(
            f"{'+'.join(kinds)} {count}" for kinds, count in sorted(signatures.items())
        )
        listed = ", ".join(orphans[:6])
        more = f" (+{len(orphans) - 6} more)" if len(orphans) > 6 else ""
        findings.append(
            (
                "warn",
                f"{len(orphans)} item(s) are obtainable in the content graph but not "
                f"through any shipping route. Resting on no shipped route, counting every "
                f"kind they declare: {columns}. Overlapping, not additive: {breakdown}. "
                f"e.g. {listed}{more}",
            )
        )

    hosted = _hosted_bosses()
    drops = _boss_drops(bosses, _authored_boss_drops(records))
    unhosted = sorted({boss_id for boss_id, ids in drops.items() if ids} - hosted)
    if unhosted:
        stranded = sum(len(drops[boss_id]) for boss_id in unhosted)
        listed = ", ".join(unhosted[:6])
        more = f" (+{len(unhosted) - 6} more)" if len(unhosted) > 6 else ""
        findings.append(
            (
                "warn",
                f"{len(unhosted)} boss record(s) carrying {stranded} drop(s) appear in no "
                f"authored loot encounter, so LootApi.enter_domain cannot spawn them: "
                f"{listed}{more}",
            )
        )
    return findings


def _runtime_summary(records: dict) -> tuple[int, int, int]:
    """(total items, graph reachable, runtime reachable) for the printed report."""
    items = records.get("item", {})
    graph = len(_obtainable(items, records.get("recipe", {})))
    runtime = len(
        _runtime_reachable(
            items,
            records.get("recipe", {}),
            records.get("boss", {}),
            _authored_boss_drops(records),
        )[0]
    )
    return len(items), graph, runtime


def _destiny_findings(records: dict) -> tuple[list[str], list[str]]:
    """Defects in fate/destiny content, and authoring notes worth surfacing.

    A `.tres` stat id is never re-read after load: an unknown key produces a
    modifier nobody can attribute, and a FLAT on a rate stat multiplies a 0..1
    baseline into something enormous. Neither raises, so this gate is the only
    place they can be caught. Cross-references are checked here too, because a
    `grants_fates` entry naming a deleted fate silently grants nothing.
    """
    fates = records.get("fate", {})
    destinies = records.get("destiny", {})
    if not fates and not destinies:
        return [], []
    gaps: list[str] = []
    valid = _valid_stats()
    rate_stats = _resolve_rate_stats()
    fraction_flat = FRACTION_FLAT_STATS | rate_stats
    visibility = {"revealed", "hidden", "teaser"}
    narrative: list[str] = []
    notes: list[str] = []

    for fate_id, fate in sorted(fates.items()):
        where = fate["path"]
        if fate.get("duplicate_of"):
            gaps.append(f"{where}: duplicate fate id '{fate_id}' also in {fate['duplicate_of']}")
        vis = fate["scalars"].get("visibility", "")
        if vis and vis not in visibility:
            gaps.append(f"{where}: fate '{fate_id}' declares unknown visibility '{vis}'")
        for field in ("flat_modifiers", "percent_modifiers"):
            for stat_id in fate["dicts"].get(field, {}):
                if stat_id not in valid:
                    gaps.append(
                        f"{where}: fate '{fate_id}' {field} names unknown stat "
                        f"'{stat_id}'; it would contribute nothing"
                    )
                elif field == "flat_modifiers" and stat_id in fraction_flat:
                    gaps.append(
                        f"{where}: fate '{fate_id}' applies FLAT to rate stat "
                        f"'{stat_id}'; use percent_modifiers or the value multiplies "
                        f"the baseline"
                    )
        if not fate["dicts"].get("flat_modifiers") and not fate["dicts"].get("percent_modifiers"):
            # Not a gap: a pure-narrative fate is a legitimate authoring choice,
            # and gating story is the module's whole reason for existing.
            narrative.append(fate_id)

    for destiny_id, destiny in sorted(destinies.items()):
        where = destiny["path"]
        if destiny.get("duplicate_of"):
            gaps.append(
                f"{where}: duplicate destiny id '{destiny_id}' also in {destiny['duplicate_of']}"
            )
        vis = destiny["scalars"].get("visibility", "")
        if vis and vis not in visibility:
            gaps.append(f"{where}: destiny '{destiny_id}' declares unknown visibility '{vis}'")
        for field, known in (
            ("grants_fates", set(fates)),
            ("requires_fates", set(fates)),
            ("requires_destinies", set(destinies)),
        ):
            for ref in destiny["arrays"].get(field, []):
                if ref not in known:
                    gaps.append(
                        f"{where}: destiny '{destiny_id}' {field} names '{ref}', "
                        f"which no authored record defines"
                    )
        for ref in destiny["arrays"].get("requires_destinies", []):
            if ref == destiny_id:
                gaps.append(f"{where}: destiny '{destiny_id}' requires itself")

    groups: dict[str, list[str]] = {}
    for destiny_id, destiny in sorted(destinies.items()):
        group = destiny["scalars"].get("group", "")
        if group:
            groups.setdefault(group, []).append(destiny_id)
    # Exclusivity and pure-narrative fates are authoring choices, not defects, so
    # they are surfaced rather than gated: a group closes its members for good,
    # which is worth seeing once, and a fate may legitimately carry no numbers.
    for group, members in sorted(groups.items()):
        if len(members) > 1:
            notes.append(
                f"destiny group '{group}' closes {', '.join(members)} against each other "
                f"permanently — earning one forfeits the rest"
            )
    if narrative:
        notes.append(
            f"{len(narrative)} fate(s) carry no stat and exist only to gate story: "
            f"{', '.join(narrative)}"
        )
    return gaps, notes


def _audit_command(root: Path, fail_on_unreachable: bool = False) -> int:
    gaps = _audit(root)
    records, _ = _load(root)
    gaps.extend(msg for level, msg in _loot_findings(records) if level == "error")
    # Fate/destiny content is gated rather than warned: these defects are inside
    # a subsystem that already ships, so a typo would silently ship a fate that
    # grants nothing (bad stat id) or one that multiplies instead of adding
    # (FLAT on a rate stat). Nothing re-reads the field after load, so the audit
    # is the only place the mistake can still be caught.
    gaps.extend(_destiny_findings(records)[0])
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
    runtime = _runtime_findings(records)
    for note in _destiny_findings(records)[1]:
        warn(note)
    # The measurement prints BEFORE the verdict and nothing returns early above
    # it. A content gap used to `return 1` before this readout, so one bad
    # `sources` entry silently erased the deliverable count -- the single number
    # the acquisition work is graded on. A gate that hides its own measurement
    # when it fails is how a regression hides behind an unrelated red.
    total, graph, runtime_count = _runtime_summary(records)
    info("")
    info(
        f"acquisition: {graph}/{total} item(s) obtainable in the content graph, "
        f"{runtime_count}/{total} deliverable by shipping code"
    )
    # Per-route delivery is a MEASUREMENT, so it prints before any early return
    # too. It is the only thing that distinguishes "the domain route works" from
    # "the total went up", and a gate that withholds it while a content gap is
    # open forces the next reader to re-derive the picture from a count alone.
    for level, message in runtime:
        if level == "info":
            info(message)
    if gaps:
        for gap in gaps:
            fail(gap)
        fail(f"data audit failed: {len(gaps)} gap(s)")
        return 1
    for level, message in runtime:
        if level == "info":
            # A measurement, not a gap: the per-route delivery breakdown states a
            # fact about the corpus and raises nothing. Only `warn` is promoted by
            # `--fail-on-unreachable` and only `warn` counts toward the summary
            # line, so an informational readout can never fail a build.
            info(message)
        elif fail_on_unreachable:
            fail(message)
        else:
            warn(message)
    gaps_left = [message for level, message in runtime if level != "info"]
    if fail_on_unreachable and gaps_left:
        fail(f"data audit failed: {len(gaps_left)} runtime-availability gap(s)")
        return 1
    if gaps_left:
        ok(
            f"data audit clean (graph reachable only: {len(gaps_left)} runtime-availability "
            "gap(s) reported above, not gated)"
        )
        return 0
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
    # The realm ladder MUST be loaded here, not by a caller: `REALM_INDEX` and
    # `REALM_TIER` are module globals populated only by `_load_realms()`, and the
    # caller `_collect_findings` reads them. The window itself is keyed by realm ID
    # (ADR 0050), so the item's own `realm` field is passed straight through — a
    # ladder position would grade every row against a neighbour's window.
    _load_realms()
    offenders: list[str] = []
    for item_id, item in sorted(items.items()):
        rarity_index = RARITY_INDEX.get(item["scalars"].get("rarity", ""), 0)
        realm_id = item["scalars"].get("realm", "")
        # A numeraire declares no realm on purpose: its trade value is the unit the
        # other values are measured in, so there is no per-realm window to grade it
        # against and `magnitude_scale("")` would abort the entire audit on it.
        if not realm_id:
            continue
        for option_id, value in item["fixed"].items():
            record = catalog.get(option_id)
            if not record:
                continue
            low, high = _magnitude_bounds(record["unit"], realm_id, rarity_index)
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

    # Reachability is printed before the findings pass so an unrelated hard
    # failure downstream (a magnitude window that cannot resolve) cannot swallow
    # these numbers the way it swallowed every section after it.
    total_items, graph_items, runtime_items = _runtime_summary(records)
    runtime = _runtime_findings(records)
    info("")
    info("=== Runtime Reachability ===")
    info(f"  total items:                {total_items:5d}")
    info(
        f"  content-graph reachable:    {graph_items:5d}  ({_pct(graph_items, total_items):5.1f}%)"
    )
    info(
        f"  shipping-code reachable:    {runtime_items:5d}  "
        f"({_pct(runtime_items, total_items):5.1f}%)"
    )
    for message in (msg for _level, msg in runtime):
        info(f"  warn: {message}")

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
