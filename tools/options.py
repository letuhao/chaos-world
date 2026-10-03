"""Master option catalog tooling (ADR 0025).

Registration, audit, derivation, and reporting for the authoritative item-option
JSONL catalog under game/data/item_options/. Strict validation, atomic writes,
deterministic derivation. No Godot runtime required.
"""

from __future__ import annotations

import hashlib
import json
import os
import random
import re
import tempfile
from pathlib import Path

from .common import REPO_ROOT, ToolError, fail, info, ok

CATALOG_DIR = REPO_ROOT / "game" / "data" / "item_options"
DEFAULT_CATALOG = CATALOG_DIR / "master_option_pool.jsonl"
DERIVED_DIR = CATALOG_DIR / "derived"
PROJECTION_VERSION = 2
# Golden fixture pinning the Python mirror of the option magnitude window to the
# Godot runtime. Bump when the *shape* changes, not when a number moves (a moved
# number is a balance change and must be regenerated on purpose). v2 replaced the
# ladder column with the per-realm magnitude scale.
PARITY_VERSION = 2
PARITY_PATH = REPO_ROOT / "game" / "tests" / "fixtures" / "option_magnitude_windows.json"
SCALE_VERSION = 1
SCALE_PATH = CATALOG_DIR / "item_magnitude_scale.json"
# The realm axis of a MAGNITUDE is data, not a curve: one authored multiplier per
# realm, read by both the runtime and this tooling from `item_magnitude_scale.json`.
# There is no dial left in `src/` and no formula to restate the ramp, so a designer
# retunes a single realm by editing one number in that file.
#
# SEED_REALM_SCALE is used ONCE, to seed a table that does not exist yet: the
# per-realm weight this module shipped before any shared ladder existed, which is
# why `scale --write` refuses to overwrite. It is deliberately not a regeneration
# rule — re-running the seed would restate the balance behind the designer's back.
SEED_REALM_SCALE = 0.10
# Magnitude window per unit: [base_min, base_max, realm_scale, rarity_scale].
# min/max = base * realm_factor * (1 + rarity_index * rarity_scale), where a
# magnitude's realm_factor is the authored per-realm scale and a rate's is the
# linear `1 + realm_index * realm_scale` read (slot 2, unused by `magnitude`).
# The runtime mirrors this table in OptionCatalog.MAGNITUDE_POLICY; keep them equal.
MAGNITUDE_POLICY = {
    "magnitude": [1.0, 10.0, 0.10, 0.25],
    "rate": [0.01, 0.05, 0.005, 0.01],
    "fraction": [0.01, 0.06, 0.01, 0.02],
}

SCHEMA_VERSION = 1
VALID_OPS = {"FLAT", "PERCENT", "MULT"}
VALID_UNITS = {"magnitude", "rate", "fraction"}
VALID_STATUSES = {"active", "deprecated"}
VALID_CONTEXTS = {
    "base",
    "prefix",
    "postfix",
    "socket_item",
    "socket_slot",
    "enchantment",
    "set_bonus",
    "unique",
}
VALID_TARGET_TYPES = {"stat", "resource", "property"}
# Activation channels (ADR 0028). An option may only be authored on an item whose
# category activates through a channel listed here, so every registered option
# has a real consumer instead of being decorative.
VALID_ACTIVATIONS = {"equipped", "consumed", "learned", "crafted", "property"}
# `property` targets name a numeric item property owned by the items module.
# craft_potency/craft_yield are read by Crafting; key_reach/quest_potency/
# trade_value are read through ItemsApi by the encounter, reward and loot
# surfaces that consume them (ADR 0028). No property is registered without a
# named consumer.
VALID_PROPERTIES = {
    "craft_potency",
    "craft_yield",
    "key_reach",
    "quest_potency",
    "trade_value",
}
# Resource targets are either one-shot restoration of the current value or a
# persistent capacity/regeneration change (ADR 0025).
VALID_RESOURCE_SCOPES = {"current", "maximum", "regen"}
# Category -> activation channel. Every in-game category must resolve.
CATEGORY_ACTIVATION = {
    "equipment": "equipped",
    "consumable": "consumed",
    "technique": "learned",
    "material": "crafted",
    "key": "property",
    "currency": "property",
    "quest": "property",
    "misc": "property",
}
ID_PATTERN = r"^[a-z][a-z0-9_]*$"


def activations_for(record: dict) -> set[str]:
    """Activation channels an option may be authored on.

    Derived from the record's categories so category -> activation stays the
    single source of truth; an explicit `activations` list may only narrow it.
    """
    declared = set(record.get("activations", []))
    derived = {CATEGORY_ACTIVATION[c] for c in record.get("categories", [])}
    if not derived:
        raise ToolError(f"{record['id']}: no categories, so no activation channel")
    if declared and not declared <= derived:
        raise ToolError(
            f"{record['id']}: activations {sorted(declared)} are not all "
            f"reachable from categories {record.get('categories')}"
        )
    return declared or derived


def register(subparsers) -> None:
    parser = subparsers.add_parser("options", help="master option catalog tooling")
    actions = parser.add_subparsers(dest="options_action", required=True)

    report = actions.add_parser("report", help="summarize the catalog")
    report.add_argument("--catalog", default=None)

    audit = actions.add_parser("audit", help="structurally audit the catalog")
    audit.add_argument("--catalog", default=None)

    reg = actions.add_parser("register", help="register options from a JSONL file")
    reg.add_argument("--input", required=True, help="validated JSONL candidate catalog")
    reg.add_argument("--catalog", default=None)
    reg.add_argument("--update", action="store_true", help="allow changing existing ids")

    derive = actions.add_parser("derive", help="derive pools into a projection")
    derive.add_argument("--catalog", default=None)
    derive.add_argument("--check", action="store_true", help="verify projection is current")

    dist = actions.add_parser(
        "option_distribution", help="audit option distribution and balance (read-only)"
    )
    dist.add_argument("--catalog", default=None)
    dist.add_argument("--seed", type=int, default=104729, help="simulation seed")
    dist.add_argument("--samples", type=int, default=1000, help="rolls per realm/rarity")
    dist.add_argument(
        "--fail-on",
        choices=["none", "warn", "error"],
        default="none",
        help="exit non-zero above this finding level (default none)",
    )
    dist.add_argument(
        "--json", action="store_true", help="also write build/option_distribution.json"
    )

    cover = actions.add_parser(
        "coverage",
        help="report the target -> option -> consumer coverage matrix (read-only)",
    )
    cover.add_argument("--catalog", default=None)
    cover.add_argument(
        "--fail-on",
        choices=["none", "error"],
        default="none",
        help="exit non-zero when a registered option has no implemented consumer",
    )

    parity = actions.add_parser(
        "parity",
        help=(
            "pin the Python and Godot magnitude windows to one golden fixture "
            "so the gate cannot validate content against a curve the game "
            "does not apply"
        ),
    )
    parity.add_argument("--catalog", default=None)
    parity.add_argument("--write", action="store_true", help="rewrite the fixture")
    parity.add_argument("--check", action="store_true", help="fail when the fixture is stale")

    scale = actions.add_parser(
        "scale",
        help=(
            "the per-realm item magnitude scale: seed it once, then it is authored "
            "data the runtime reads"
        ),
    )
    scale.add_argument(
        "--write",
        action="store_true",
        help="seed the table when it is missing (never overwrites an existing one)",
    )
    scale.add_argument(
        "--check", action="store_true", help="fail when a realm is missing or malformed"
    )


def run(args) -> int:
    action = args.options_action
    # `scale` operates on the magnitude table, not on a catalog.
    catalog = Path(getattr(args, "catalog", None) or DEFAULT_CATALOG)
    if action == "report":
        return _report(catalog)
    if action == "audit":
        return _audit(catalog)
    if action == "register":
        return _register(catalog, Path(args.input), args.update)
    if action == "derive":
        return _derive(catalog, args.check)
    if action == "option_distribution":
        return _distribution(
            catalog, args.seed, args.samples, args.fail_on, getattr(args, "json", False)
        )
    if action == "coverage":
        return _coverage(catalog, args.fail_on)
    if action == "parity":
        return _parity(args.write, args.check)
    if action == "scale":
        return _scale(args.write, args.check)
    raise ToolError(f"unknown options action: {action}")


def _parity_fixture() -> dict:
    """Golden windows for every (unit, realm, rarity) the generator can produce.

    The Python mirror and `OptionCatalog.magnitude_bounds` must agree, or the
    gate would validate authored item values against numbers the game never rolls.

    The windows are NOT the only thing pinned here. `scales` carries the authored
    per-realm multipliers keyed by realm ID, and the GDScript suite re-derives a
    window from that map by a second route (id -> ladder index, rather than the
    index -> window composition the runtime performs). A fixture generated only
    from windows can never disagree with its own generator; an id-keyed column
    can, which is the whole point of it.
    """
    windows = {}
    for unit in sorted(MAGNITUDE_POLICY):
        for realm_id in _scale_ladder():
            for rarity_index in range(len(RARITIES)):
                window = _magnitude_bounds(unit, realm_id, rarity_index)
                windows[f"{unit}:{realm_id}:{rarity_index}"] = [
                    round(window["min"], 6),
                    round(window["max"], 6),
                ]
    return {
        "version": PARITY_VERSION,
        # The whole realm axis, not one pin: a shape change must be regenerated on
        # purpose, and the runtime is asserted against these exact values. Keyed by
        # realm id so the assertion goes through the ladder, not through a position
        # both sides could get wrong the same way.
        "scales": {realm_id: round(scale, 6) for realm_id, scale in load_scale().items()},
        "windows": windows,
    }


def _parity(write: bool, check: bool) -> int:
    expected = _parity_fixture()
    path = PARITY_PATH
    if write:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(expected, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        tmp.replace(path)
        ok(f"wrote {len(expected['windows'])} option windows to {path.name}")
        return 0
    if not path.is_file():
        raise ToolError(f"no parity fixture at {path}; run `data options parity --write`")
    on_disk = json.loads(path.read_text(encoding="utf-8"))
    if on_disk != expected:
        stale = sorted(
            key
            for key in set(on_disk.get("windows", {})) | set(expected["windows"])
            if on_disk.get("windows", {}).get(key) != expected["windows"].get(key)
        )
        raise ToolError(
            f"option magnitude parity fixture is stale ({len(stale)} window(s) differ); "
            f"run `data options parity --write`. First: {', '.join(stale[:5])}"
        )
    if check:
        ok(f"option magnitude parity fixture is current ({len(expected['windows'])} windows)")
        return 0
    ok(f"option magnitude parity fixture is current ({len(expected['windows'])} windows)")
    return 0


def _coverage(catalog: Path, fail_on: str) -> int:
    """Report which implemented consumer can express each registered target.

    A target is only covered when the game actually computes it: core owns the
    base attributes and everything `ActorStats._put` derives, a module provider
    owns what its provider contributes, resource pools are the ids an Actor
    really carries, and item properties are the ones the items module reads.
    Anything else is reported rather than assumed.
    """
    records = _load_jsonl(catalog)
    active = [r for r in records if r["status"] == "active"]
    consumers = _implemented_targets()
    by_target: dict[str, list[str]] = {}
    for record in active:
        by_target.setdefault(record["target"]["id"], []).append(record["id"])

    info("=== Option Target Coverage ===")
    info(f"  {'target':38s} {'kind':10s} {'options':>7s}  activations")
    errors: list[str] = []
    for target in sorted(by_target):
        kind = _consumer_kind(target, consumers)
        options = by_target[target]
        if kind is None:
            errors.append(f"{target}: no implemented consumer ({', '.join(options)})")
            info(f"  {target:38s} {'NONE':10s} {len(options):>7d}  -")
            continue
        pool_options = [r for r in active if r["target"]["id"] == target]
        activations = sorted({a for r in pool_options for a in activations_for(r)})
        info(f"  {target:38s} {kind:10s} {len(options):>7d}  {', '.join(activations)}")
    info("")
    for kind in sorted(consumers):
        count = len(consumers[kind])
        info(f"  {kind:10s} implements {count:4d} target(s)")
    info("")
    for error in errors:
        fail(error)
    covered = len(by_target) - len(errors)
    if errors:
        if fail_on == "error":
            fail(f"option coverage failed: {len(errors)} target(s) without a consumer")
            return 1
    ok(f"option coverage: {covered}/{len(by_target)} targets have an implemented consumer")
    return 0


CONSUMER_SOURCE = "src"


def _implemented_targets() -> dict[str, set[str]]:
    """Target ids the game actually implements, grouped by consumer kind."""
    from .common import REPO_ROOT  # noqa: PLC0415

    game = REPO_ROOT / "game"
    stat_src = (game / "src" / "contracts" / "stat.gd").read_text(encoding="utf-8")
    stats_src = (game / "src" / "core" / "actor_stats.gd").read_text(encoding="utf-8")
    core: set[str] = set()
    for const in re.findall(r"_put\(Stat\.([A-Z_0-9]+)", stats_src):
        found = re.search(rf'const {const} := &"([a-z_0-9]+)"', stat_src)
        if found:
            core.add(found.group(1))
    for const, value in re.findall(r'^const ([A-Z_0-9]+) := &"([a-z_0-9]+)"', stat_src, re.M):
        if const.startswith("BASE_") or const in {
            "PHYSIQUE",
            "SPIRIT",
            "APTITUDE",
            "COMPREHENSION",
            "AGILITY",
            "WILL",
            "FORTUNE",
        }:
            core.add(value)

    provider: set[str] = set()
    element_prefixes: list[str] = []
    for stats_file in sorted((game / "src" / "modules").rglob("stats.gd")):
        for const in re.findall(
            r'^const ([A-Z_0-9]+) := &"([a-z_0-9]+)"', stats_file.read_text(encoding="utf-8"), re.M
        ):
            provider.add(const[1])
        for prefix in re.findall(
            r'const [A-Z_0-9]+_PREFIX := "([a-z_]+_)"', stats_file.read_text(encoding="utf-8")
        ):
            element_prefixes.append(prefix)
    elements_src = (game / "src" / "modules" / "elements" / "stats.gd").read_text(encoding="utf-8")
    for const in re.findall(r"const ([A-Z_0-9]+) := &\"([a-z_0-9]+)\"", elements_src):
        provider.add(const[1])
    for prefix in ("element_mastery_", "element_power_", "element_resistance_"):
        element_prefixes.append(prefix)
    elements: set[str] = set()
    for prefix in element_prefixes:
        for match in re.findall(
            rf"{re.escape(prefix)}([a-z_]+)",
            "\n".join(r["id"] for r in active_catalog(catalog_cache())),
        ):
            elements.add(f"{prefix}{match}")

    resources: set[str] = set()
    for stats_file in sorted((game / "src" / "modules").rglob("stats.gd")):
        block = re.search(
            r"# Resources\s*\n((?:\s*const [A-Z_0-9]+ := &\"[a-z_0-9]+\"\s*\n)+)",
            stats_file.read_text(encoding="utf-8"),
        )
        if not block:
            continue
        for line in block.group(1).splitlines():
            found = re.search(r'&"([a-z_0-9]+)"', line)
            if found:
                resources.add(found.group(1))
    for pool in re.findall(
        r'ResourcePool\.new\(\s*&?"([a-z_0-9]+)"',
        "\n".join(p.read_text(encoding="utf-8") for p in (game / "src").rglob("*.gd")),
    ):
        resources.add(pool)
    # Pools core declares as canonical for every actor.
    core_block = (game / "src" / "core" / "actor.gd").read_text(encoding="utf-8")
    for block in re.findall(r"^const \w+ := \{$\n(.*?)^\}$", core_block, re.M | re.S):
        for pool_id in re.findall(r'&"([a-z_0-9]+)"', block):
            resources.add(pool_id)

    return {
        "core": core,
        "provider": provider,
        "element": elements,
        "resource": resources,
        "property": set(VALID_PROPERTIES),
    }


_CATALOG_CACHE: dict[Path, list[dict]] = {}


def catalog_cache() -> Path:
    return DEFAULT_CATALOG


def active_catalog(path: Path) -> list[dict]:
    if path not in _CATALOG_CACHE:
        _CATALOG_CACHE[path] = _load_jsonl(path)
    return [r for r in _CATALOG_CACHE[path] if r["status"] == "active"]


def _consumer_kind(target: str, consumers: dict[str, set[str]]) -> str | None:
    for kind in ("core", "element", "provider", "resource", "property"):
        if target in consumers[kind]:
            return kind
    return None


# --- Loading & validation ---------------------------------------------------


def _load_jsonl(path: Path) -> list[dict]:
    if not path.is_file():
        raise ToolError(f"catalog not found: {path}")
    records: list[dict] = []
    seen_ids: set[str] = set()
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ToolError(f"{path.name}:{lineno}: invalid JSON: {exc}") from exc
        if not isinstance(record, dict):
            raise ToolError(f"{path.name}:{lineno}: record is not an object")
        _validate_record(record, path, lineno)
        rid = record["id"]
        if rid in seen_ids:
            raise ToolError(f"{path.name}:{lineno}: duplicate id '{rid}'")
        seen_ids.add(rid)
        records.append(record)
    return records


def _validate_record(record: dict, path: Path, lineno: int) -> None:
    def err(msg: str) -> None:
        raise ToolError(f"{path.name}:{lineno}: {msg}")

    for field in (
        "id",
        "schema_version",
        "status",
        "label",
        "family",
        "target",
        "op",
        "unit",
        "contexts",
        "weight",
    ):
        if field not in record:
            err(f"missing field '{field}'")
    rid = record["id"]
    if not isinstance(rid, str) or not rid:
        err("id must be a non-empty string")
    import re

    if not re.match(ID_PATTERN, rid):
        err(f"id '{rid}' does not match {ID_PATTERN}")
    if record["schema_version"] != SCHEMA_VERSION:
        err(f"unsupported schema_version {record['schema_version']}")
    if record["status"] not in VALID_STATUSES:
        err(f"invalid status '{record['status']}'")
    if record["op"] not in VALID_OPS:
        err(f"invalid op '{record['op']}'")
    if record["unit"] not in VALID_UNITS:
        err(f"invalid unit '{record['unit']}'")
    target = record["target"]
    if not isinstance(target, dict) or target.get("type") not in VALID_TARGET_TYPES:
        err(f"target.type must be one of {sorted(VALID_TARGET_TYPES)}")
    if not isinstance(target.get("id"), str) or not target["id"]:
        err("target.id must be a non-empty string")
    if target.get("type") == "resource":
        scope = target.get("scope")
        if scope not in VALID_RESOURCE_SCOPES:
            err(f"resource target.scope must be one of {sorted(VALID_RESOURCE_SCOPES)}")
    if target.get("type") == "property" and target.get("id") not in VALID_PROPERTIES:
        err(f"property target.id must be one of {sorted(VALID_PROPERTIES)}")
    categories = record.get("categories")
    if not isinstance(categories, list) or not categories:
        err("categories must be a non-empty list")
    else:
        for category in categories:
            if category not in CATEGORY_ACTIVATION:
                err(f"unknown category '{category}'")
    # `activations` is optional: when absent it is derived from the record's
    # categories, so an option can never claim a consumer its categories do not
    # have. This keeps category -> activation the single source of truth.
    activations = record.get("activations")
    if activations is not None:
        if not isinstance(activations, list) or not activations:
            err("activations must be a non-empty list when present")
        else:
            for act in activations:
                if act not in VALID_ACTIVATIONS:
                    err(f"invalid activation '{act}'")
    for key in ("slots", "tags"):
        listed = record.get(key, [])
        if not isinstance(listed, list):
            err(f"{key} must be a list")
        for entry in listed:
            if not isinstance(entry, str):
                err(f"{key} entries must be strings")
    contexts = record["contexts"]
    if not isinstance(contexts, list) or not contexts:
        err("contexts must be a non-empty list")
    for ctx in contexts:
        if ctx not in VALID_CONTEXTS:
            err(f"invalid context '{ctx}'")
    weight = record["weight"]
    if not isinstance(weight, (int, float)) or weight <= 0:
        err("weight must be a positive number")
    bounds = record.get("bounds", {})
    if not isinstance(bounds, dict):
        err("bounds must be an object")
    else:
        for key in ("min", "max"):
            if key in bounds and (
                not isinstance(bounds[key], (int, float)) or not _is_finite(bounds[key])
            ):
                err(f"bounds.{key} must be a finite number")
        if "min" in bounds and "max" in bounds and bounds["min"] > bounds["max"]:
            err("bounds.min exceeds bounds.max")
    # Reject NaN/Infinity anywhere in the record.
    _reject_nonfinite(record, path, lineno)


def _is_finite(value: float) -> bool:
    return value == value and value not in (float("inf"), float("-inf"))


def _reject_nonfinite(value, path: Path, lineno: int) -> None:
    if isinstance(value, float) and not _is_finite(value):
        raise ToolError(f"{path.name}:{lineno}: non-finite number")
    if isinstance(value, dict):
        for v in value.values():
            _reject_nonfinite(v, path, lineno)
    if isinstance(value, list):
        for v in value:
            _reject_nonfinite(v, path, lineno)


# --- Commands ---------------------------------------------------------------


def _report(catalog: Path) -> int:
    records = _load_jsonl(catalog)
    info(f"catalog: {catalog.relative_to(REPO_ROOT).as_posix()}")
    info(f"  options: {len(records)}")
    by_family: dict[str, int] = {}
    for record in records:
        by_family[record["family"]] = by_family.get(record["family"], 0) + 1
    for family, count in sorted(by_family.items()):
        info(f"    {family:16s} {count}")
    return 0


def _audit(catalog: Path) -> int:
    records = _load_jsonl(catalog)
    errors: list[str] = []
    active = [r for r in records if r["status"] == "active"]
    if not active:
        errors.append("catalog has no active options")
    # Every active option must have at least one context and a positive weight.
    for record in active:
        if not record["contexts"]:
            errors.append(f"{record['id']}: no contexts")
        if record["weight"] <= 0:
            errors.append(f"{record['id']}: non-positive weight")
    # FLAT on a rate/fraction *actor stat* is a content error (ADR 0011), except
    # damage_reduction which is deliberately FLAT (ADR 0022). Item properties are
    # not actor stats: `craft_yield` is a plain fractional chance read by
    # Crafting, not a multiplier on a rate baseline.
    rate_units = {"rate", "fraction"}
    for record in active:
        if record["op"] != "FLAT" or record["unit"] not in rate_units:
            continue
        if record["target"]["type"] != "stat":
            continue
        if record["target"]["id"] == "damage_reduction":
            continue
        errors.append(f"{record['id']}: FLAT on {record['unit']} stat must be PERCENT")
    # Every option must declare categories so it resolves to a real consumer.
    for record in active:
        if not record.get("categories"):
            errors.append(f"{record['id']}: no categories, so no consumer")
    # Resource options must distinguish one-shot restoration from persistent
    # capacity/regeneration so a consumable cannot become a permanent buff.
    for record in active:
        if record["target"]["type"] != "resource":
            continue
        scope = record["target"].get("scope")
        if scope == "current" and record["op"] != "FLAT":
            errors.append(f"{record['id']}: current-resource restore must be FLAT")
        if scope in {"maximum", "regen"} and record["op"] != "FLAT":
            errors.append(f"{record['id']}: persistent resource option must be FLAT")
    if errors:
        for error in errors:
            fail(error)
        fail(f"option audit failed: {len(errors)} error(s)")
        return 1
    ok(f"option audit clean ({len(records)} options)")
    return 0


def _register(catalog: Path, source: Path, allow_update: bool) -> int:
    if not source.is_file():
        raise ToolError(f"input not found: {source}")
    candidates = _load_jsonl(source)
    if not candidates:
        raise ToolError("input catalog is empty")
    existing = _load_jsonl(catalog) if catalog.is_file() else []
    existing_by_id = {r["id"]: r for r in existing}
    added = 0
    changed = 0
    for record in candidates:
        rid = record["id"]
        if rid in existing_by_id:
            if existing_by_id[rid] == record:
                continue  # idempotent
            if not allow_update:
                raise ToolError(
                    f"id '{rid}' already exists and differs; pass --update to change it"
                )
            changed += 1
        else:
            added += 1
        existing_by_id[rid] = record
    # Atomic write: temp file + rename, stable sort by id.
    merged = sorted(existing_by_id.values(), key=lambda r: r["id"])
    catalog.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(catalog.parent), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            for record in merged:
                handle.write(json.dumps(record, ensure_ascii=False) + "\n")
        os.replace(tmp_name, catalog)
    except BaseException:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)
        raise
    ok(f"registered {added} new, updated {changed} ({len(merged)} total)")
    return 0


def _build_projection(records: list[dict]) -> dict:
    """Deterministic runtime projection of the master catalog.

    Pool membership is keyed by activation and affix context so the runtime never
    rescans the catalog, and every pool is sorted by id so registration order
    cannot change a roll. A content hash fails a stale projection.
    """
    pools: dict[str, list[str]] = {}
    families: dict[str, list[str]] = {}
    for record in records:
        rid = record["id"]
        families.setdefault(record["family"], []).append(rid)
        for activation in sorted(activations_for(record)):
            for context in record["contexts"]:
                pools.setdefault(f"{activation}:{context}", []).append(rid)
    for key in pools:
        pools[key] = sorted(set(pools[key]))
    for key in families:
        families[key] = sorted(set(families[key]))
    digest = hashlib.sha256(
        json.dumps([r["id"] for r in records], sort_keys=True).encode("utf-8")
    ).hexdigest()[:16]
    return {
        "version": PROJECTION_VERSION,
        "source_sha256": digest,
        "pools": pools,
        "families": families,
    }


def _derive(catalog: Path, check_only: bool) -> int:
    records = _load_jsonl(catalog)
    active = sorted((r for r in records if r["status"] == "active"), key=lambda r: r["id"])
    projection = _build_projection(active)
    projection_path = DERIVED_DIR / "option_pools.json"
    if check_only:
        if not projection_path.is_file():
            raise ToolError("no derived projection found; run derive first")
        on_disk = json.loads(projection_path.read_text(encoding="utf-8"))
        if on_disk != projection:
            raise ToolError("derived projection is stale; run derive")
        ok("derived projection is current")
        return 0
    DERIVED_DIR.mkdir(parents=True, exist_ok=True)
    projection_path.write_text(
        json.dumps(projection, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    ok(f"derived {len(active)} options into {len(projection['pools'])} pools")
    return 0


RARITIES = ("common", "magic", "rare", "legendary")
RARITY_AFFIX_COUNT = {"common": 1, "magic": 2, "rare": 3, "legendary": 4}
# Options may sit in a pool but never be reachable in practice; a share of the
# pool's total weight above this is a monopoly worth reporting.
MONOPOLY_SHARE = 0.20
# An option whose exact selection probability is this small is likely starved.
STARVATION_SHARE = 0.0015


def _distribution(catalog: Path, seed: int, samples: int, fail_on: str, as_json: bool) -> int:
    """Audit option distribution and balance via seeded simulation (read-only).

    Mirrors the runtime generator: pools come from the derived projection,
    selection is weighted without replacement by option id and exclusive family,
    and values are drawn uniformly inside the realm/rarity magnitude window.
    Reports eligibility, effective selection probability, observed frequency and
    magnitude range per option, plus concentration and starvation findings.
    """
    records = _load_jsonl(catalog)
    by_id = {r["id"]: r for r in records if r["status"] == "active"}
    if not by_id:
        raise ToolError("catalog has no active options")
    projection = _build_projection(sorted(by_id.values(), key=lambda r: r["id"]))
    pools: dict[str, list[str]] = projection["pools"]
    rng = random.Random(seed)

    observed: dict[str, int] = {rid: 0 for rid in by_id}
    values: dict[str, list[float]] = {rid: [] for rid in by_id}
    eligible: dict[str, int] = {rid: 0 for rid in by_id}
    pool_ids: dict[str, set[str]] = {}
    for key, ids in pools.items():
        pool_ids.setdefault(key, set()).update(ids)
    for ids in pool_ids.values():
        for rid in ids:
            if rid in eligible:
                eligible[rid] += 1

    ladder = _scale_ladder()
    bands = [(ladder[i], r) for i, r in ((0, 0), (8, 1), (17, 2), (26, 3), (29, 3))]
    total_rolls = 0
    for realm_id, rarity_index in bands:
        for rarity in RARITIES:
            count = RARITY_AFFIX_COUNT[rarity]
            for _ in range(samples):
                for context in _roll_contexts(count):
                    picked = _roll_one(rng, pools, by_id, context, realm_id, rarity_index)
                    if picked is None:
                        continue
                    option_id, value = picked
                    observed[option_id] += 1
                    values[option_id].append(value)
                    total_rolls += 1

    errors: list[str] = []
    warnings: list[str] = []
    rows: list[dict] = []
    for rid in sorted(by_id):
        record = by_id[rid]
        pool = _roll_pool(pools, record)
        weight_total = sum(by_id[o]["weight"] for o in pool if o in by_id)
        exact = 0.0
        if weight_total > 0:
            exact = by_id[rid]["weight"] / weight_total
        share = observed[rid] / total_rolls if total_rolls else 0.0
        values_list = sorted(values[rid])
        rows.append(
            {
                "option_id": rid,
                "family": record["family"],
                "target": record["target"]["id"],
                "target_type": record["target"]["type"],
                "op": record["op"],
                "unit": record["unit"],
                "eligible_pools": eligible[rid],
                "pool_size": len(pool),
                "weight_share": round(exact, 6),
                "observed": observed[rid],
                "observed_share": round(share, 6),
                "value_min": round(values_list[0], 4) if values_list else None,
                "value_max": round(values_list[-1], 4) if values_list else None,
                "value_median": (
                    round(values_list[len(values_list) // 2], 4) if values_list else None
                ),
            }
        )
        if not pool:
            errors.append(f"{rid}: registered but in no rollable pool")
        elif observed[rid] == 0:
            warnings.append(f"{rid}: eligible but never selected in {total_rolls} rolls")
        elif share < STARVATION_SHARE:
            warnings.append(f"{rid}: starved at {share:.4%} of observed rolls")
        if weight_total > 0 and exact > MONOPOLY_SHARE and len(pool) > 1:
            warnings.append(
                f"{rid}: holds {exact:.1%} of its pool's weight across {len(pool)} options"
            )

    report = {
        "seed": seed,
        "samples_per_band": samples,
        "total_rolls": total_rolls,
        "catalog_sha256": projection["source_sha256"],
        "options": rows,
        "errors": errors,
        "warnings": warnings,
    }
    if as_json:
        out = REPO_ROOT / "build" / "option_distribution.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        info(f"wrote {out.relative_to(REPO_ROOT).as_posix()}")
    else:
        info(f"seed: {seed}  samples/band: {samples}  total rolls: {total_rolls}")
        info("")
        info("=== Option Distribution ===")
        info(
            f"  {'option':32s} {'family':12s} {'pools':>5s} {'w.share':>8s} "
            f"{'obs':>7s} {'share':>8s} {'min':>8s} {'max':>8s}"
        )
        for row in rows:
            info(
                "  {:32s} {:12s} {:5d} {:8.4f} {:7d} {:8.4f} {:>8s} {:>8s}".format(
                    row["option_id"],
                    row["family"],
                    row["eligible_pools"],
                    row["weight_share"],
                    row["observed"],
                    row["observed_share"],
                    "-" if row["value_min"] is None else f"{row['value_min']:g}",
                    "-" if row["value_max"] is None else f"{row['value_max']:g}",
                )
            )
    for error in errors:
        fail(error)
    for warning in warnings:
        info(f"  warn: {warning}")
    if errors and fail_on == "error":
        fail(f"option distribution failed: {len(errors)} error(s)")
        return 1
    if warnings and fail_on == "warn":
        fail(f"option distribution warnings: {len(warnings)}")
        return 1
    ok(f"option distribution audit complete ({total_rolls} rolls, {len(rows)} options)")
    return 0


def _roll_contexts(count: int) -> list[str]:
    """Affix positions an item of `count` options rolls, mirroring the runtime."""
    if count <= 1:
        return ["prefix"]
    return ["prefix", "postfix"]


def _roll_pool(pools: dict[str, list[str]], record: dict) -> list[str]:
    out: set[str] = set()
    for activation in activations_for(record):
        for context in record["contexts"]:
            out.update(pools.get(f"{activation}:{context}", []))
    return sorted(out)


def _roll_one(
    rng: random.Random,
    pools: dict[str, list[str]],
    by_id: dict[str, dict],
    context: str,
    realm_id: str,
    rarity_index: int,
) -> tuple[str, float] | None:
    """One weighted selection from a context pool, with exclusivity honored."""
    taken: set[str] = set()
    families: set[str] = set()
    candidates: list[tuple[str, float]] = []
    total = 0.0
    for key, ids in sorted(pools.items()):
        activation, pool_context = key.split(":", 1)
        if pool_context != context:
            continue
        for rid in ids:
            record = by_id.get(rid)
            if record is None or rid in taken:
                continue
            if activation not in activations_for(record):
                continue
            family = record.get("exclusive_family")
            if family and family in families:
                continue
            weight = float(record["weight"])
            if weight <= 0:
                continue
            candidates.append((rid, weight))
            total += weight
    if not candidates or total <= 0:
        return None
    pick = rng.random() * total
    chosen = candidates[-1][0]
    for rid, weight in candidates:
        pick -= weight
        if pick <= 0:
            chosen = rid
            break
    record = by_id[chosen]
    family = record.get("exclusive_family")
    return chosen, _roll_value(record, realm_id, rarity_index, rng)


def _roll_value(record: dict, realm_id: str, rarity_index: int, rng: random.Random) -> float:
    bounds = _magnitude_bounds(record["unit"], realm_id, rarity_index)
    value = bounds["min"] + (bounds["max"] - bounds["min"]) * rng.random()
    precision = int(record.get("precision", 2))
    return round(value, precision)


def _scale_ladder() -> list[str]:
    """Canonical realm ids in ladder order, read from the Godot source of truth."""
    from .item_migrate import realm_ladder  # noqa: PLC0415

    return realm_ladder()


def _seed_scale() -> dict[str, float]:
    """The scale a fresh table is seeded with: this module's pre-ladder realm ramp.

    Used only to bootstrap `item_magnitude_scale.json` when it does not exist, so
    the numbers in it were computed by the tool rather than typed by hand. Once the
    file exists it is authored data: `--write` refuses to overwrite it, because a
    regeneration rule for a balance table is a curve wearing a data file's clothes.
    """
    return {
        realm_id: round(1.0 + SEED_REALM_SCALE * index, 6)
        for index, realm_id in enumerate(_scale_ladder())
    }


def load_scale() -> dict[str, float]:
    """The authored per-realm magnitude multipliers, keyed by realm id."""
    if not SCALE_PATH.is_file():
        raise ToolError(
            f"no item magnitude scale at {SCALE_PATH}; run `data options scale --write`"
        )
    try:
        payload = json.loads(SCALE_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ToolError(f"{SCALE_PATH.name}: invalid JSON: {exc}") from exc
    version = int(payload.get("version", 0))
    if version != SCALE_VERSION:
        raise ToolError(
            f"{SCALE_PATH.name}: scale version {version} is not {SCALE_VERSION}; "
            "the runtime only reads a table it understands"
        )
    realms = payload.get("realms")
    if not isinstance(realms, dict) or not realms:
        raise ToolError(f"{SCALE_PATH.name}: 'realms' must be a non-empty object")
    out: dict[str, float] = {}
    for realm_id, value in realms.items():
        if not isinstance(value, (int, float)) or not _is_finite(float(value)):
            raise ToolError(f"{SCALE_PATH.name}: realm '{realm_id}' has a non-finite scale")
        if float(value) <= 0.0:
            raise ToolError(f"{SCALE_PATH.name}: realm '{realm_id}' has a non-positive scale")
        out[str(realm_id)] = float(value)
    missing = [realm_id for realm_id in _scale_ladder() if realm_id not in out]
    if missing:
        raise ToolError(
            f"{SCALE_PATH.name}: no scale for {len(missing)} realm(s), "
            f"e.g. {', '.join(missing[:3])}; every realm on the ladder rolls items"
        )
    return out


def magnitude_scale(realm_id: str) -> float:
    """The authored magnitude multiplier for one realm, looked up by realm id.

    Keyed by id and never by position: an inserted realm must not silently hand
    every realm below it a neighbour's number (ADR 0050). Mirrors
    `OptionCatalog.realm_magnitude_scale`, so the gate cannot validate content
    against numbers the runtime would not roll.
    """
    scale = load_scale()
    if realm_id not in scale:
        raise ToolError(
            f"{SCALE_PATH.name}: no magnitude scale for realm '{realm_id}'; "
            "every realm on the ladder rolls items"
        )
    return scale[realm_id]


def realm_ordinal(realm_id: str) -> int:
    """A realm's position on the canonical ladder, or 0 when it is not on it.

    This is an ordinal, not a scale: only a rate reads it.
    """
    ladder = _scale_ladder()
    return ladder.index(realm_id) if realm_id in ladder else 0


def _scale(write: bool, check: bool) -> int:
    ladder = _scale_ladder()
    if write:
        if SCALE_PATH.is_file():
            # Never overwrite: the table is authored balance once it exists.
            info(f"item magnitude scale already exists at {SCALE_PATH.name}; not overwritten")
            return _scale_report()
        table = _seed_scale()
        SCALE_PATH.parent.mkdir(parents=True, exist_ok=True)
        payload = {"version": SCALE_VERSION, "realms": table}
        tmp = SCALE_PATH.with_suffix(".tmp")
        tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        tmp.replace(SCALE_PATH)
        ok(f"seeded {len(table)} realm scales into {SCALE_PATH.name}")
        return 0
    # Either way the table is read and validated, so `--check` fails loudly on a
    # missing realm instead of letting the gate bless content against a partial one.
    table = load_scale()
    report = _scale_report()
    if check:
        if len(table) != len(ladder):
            raise ToolError(
                f"item magnitude scale covers {len(table)} realms, the ladder has {len(ladder)}"
            )
        ok(f"item magnitude scale is complete ({len(table)} realms)")
    return report


def _scale_report() -> int:
    table = load_scale()
    ladder = _scale_ladder()
    info(f"item magnitude scale: {SCALE_PATH.relative_to(REPO_ROOT).as_posix()}")
    info(f"  {'realm':24s} {'index':>5s} {'scale':>8s}  window min..max (common)")
    for index, realm_id in enumerate(ladder):
        scale = table[realm_id]
        low = float(MAGNITUDE_POLICY["magnitude"][0]) * scale
        high = float(MAGNITUDE_POLICY["magnitude"][1]) * scale
        info(f"  {realm_id:24s} {index:5d} {scale:8.3f}  {low:.3f}..{high:.3f}")
    ok(f"item magnitude scale spans {table[ladder[0]]:.3f}x..{table[ladder[-1]]:.3f}x")
    return 0


def realm_factor(unit: str, realm_id: str, slope: float) -> float:
    """Realm factor for one option unit, keyed by realm id.

    A magnitude is DATA: the authored per-realm scale table. A rate or fraction is
    not a magnitude and stays a contest read: linear in the realm ordinal with the
    unit's authored weight, so a one-realm gap is worth the same at R30 as at R5.

    Mirrors `OptionCatalog._realm_factor`, so tooling and the game cannot disagree
    about what a rolled item is worth.
    """
    if unit == "magnitude":
        return magnitude_scale(realm_id)
    # power: rate-read - a rate is linear in the realm ordinal by design.
    return 1.0 + realm_ordinal(realm_id) * slope


def _magnitude_bounds(unit: str, realm_id: str, rarity_index: int) -> dict:
    policy = MAGNITUDE_POLICY.get(unit, MAGNITUDE_POLICY["magnitude"])
    realm = realm_factor(unit, realm_id, float(policy[2]))
    rarity = 1.0 + rarity_index * float(policy[3])
    return {
        "min": float(policy[0]) * realm * rarity,
        "max": float(policy[1]) * realm * rarity,
    }
