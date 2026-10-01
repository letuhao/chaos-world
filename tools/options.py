"""Master option catalog tooling (ADR 0025).

Registration, audit, derivation, and reporting for the authoritative item-option
JSONL catalog under game/data/item_options/. Strict validation, atomic writes,
deterministic derivation. No Godot runtime required.
"""

from __future__ import annotations

import json
import os
import random
import tempfile
from pathlib import Path

from .common import REPO_ROOT, ToolError, fail, info, ok

CATALOG_DIR = REPO_ROOT / "game" / "data" / "item_options"
DEFAULT_CATALOG = CATALOG_DIR / "master_option_pool.jsonl"
DERIVED_DIR = CATALOG_DIR / "derived"

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
VALID_TARGET_TYPES = {"stat", "resource"}
ID_PATTERN = r"^[a-z][a-z0-9_]*$"


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


def run(args) -> int:
    action = args.options_action
    catalog = Path(args.catalog) if args.catalog else DEFAULT_CATALOG
    if action == "report":
        return _report(catalog)
    if action == "audit":
        return _audit(catalog)
    if action == "register":
        return _register(catalog, Path(args.input), args.update)
    if action == "derive":
        return _derive(catalog, args.check)
    if action == "option_distribution":
        return _distribution(catalog, args.seed, args.samples, args.fail_on)
    raise ToolError(f"unknown options action: {action}")


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
        err("target.type must be 'stat' or 'resource'")
    if not isinstance(target.get("id"), str) or not target["id"]:
        err("target.id must be a non-empty string")
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
    # FLAT on a rate/fraction stat is a content error (ADR 0011), except
    # damage_reduction which is deliberately FLAT (ADR 0022).
    rate_units = {"rate", "fraction"}
    for record in active:
        if record["op"] == "FLAT" and record["unit"] in rate_units:
            if record["target"]["id"] == "damage_reduction":
                continue
            errors.append(f"{record['id']}: FLAT on {record['unit']} stat must be PERCENT")
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


def _derive(catalog: Path, check_only: bool) -> int:
    records = _load_jsonl(catalog)
    active = [r for r in records if r["status"] == "active"]
    # Deterministic projection: group by (family, op, unit) with sorted ids.
    projection: dict[str, list[str]] = {}
    for record in active:
        key = f"{record['family']}:{record['op']}:{record['unit']}"
        projection.setdefault(key, []).append(record["id"])
    for key in projection:
        projection[key].sort()
    if check_only:
        projection_path = DERIVED_DIR / "option_pools.json"
        if not projection_path.is_file():
            raise ToolError("no derived projection found; run derive first")
        on_disk = json.loads(projection_path.read_text(encoding="utf-8"))
        if on_disk != projection:
            raise ToolError("derived projection is stale; run derive")
        ok("derived projection is current")
        return 0
    DERIVED_DIR.mkdir(parents=True, exist_ok=True)
    projection_path = DERIVED_DIR / "option_pools.json"
    projection_path.write_text(
        json.dumps(projection, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    ok(f"derived {len(active)} options into {len(projection)} pools")
    return 0


def _distribution(catalog: Path, seed: int, samples: int, fail_on: str) -> int:
    """Audit option distribution and balance via seeded simulation (read-only).

    Mirrors the runtime generator's weighted selection so Python and Godot agree
    on the algorithm. Reports availability, observed frequency, and magnitude
    range per family/element/realm/rarity.
    """
    records = _load_jsonl(catalog)
    active = [r for r in records if r["status"] == "active"]
    if not active:
        raise ToolError("catalog has no active options")
    rng = random.Random(seed)
    # Group active options by family for weighted selection.
    by_family: dict[str, list[dict]] = {}
    for record in active:
        by_family.setdefault(record["family"], []).append(record)
    # Simulate rolls across realm/rarity bands.
    bands = [(0, 0), (9, 1), (18, 2), (29, 3)]
    observations: dict[str, int] = {}
    magnitudes: dict[str, list[float]] = {}
    total_rolls = 0
    for realm_index, rarity_index in bands:
        for _ in range(samples):
            # Weighted selection of one affix per roll (mirrors runtime).
            family = _weighted_pick(
                rng, {f: sum(r["weight"] for r in opts) for f, opts in by_family.items()}
            )
            option_id = _weighted_pick(rng, {r["id"]: r["weight"] for r in by_family[family]})
            option = next(r for r in by_family[family] if r["id"] == option_id)
            stat = option["target"]["id"]
            observations[stat] = observations.get(stat, 0) + 1
            bounds = _magnitude_bounds(option["unit"], realm_index, rarity_index)
            value = (bounds["min"] + bounds["max"]) / 2.0
            magnitudes.setdefault(stat, []).append(value)
            total_rolls += 1
    info(f"seed: {seed}  samples/band: {samples}  total rolls: {total_rolls}")
    info("")
    info("=== Option Distribution ===")
    info(f"  {'option':32s} {'family':14s} {'obs':>6s} {'freq':>6s} {'min':>8s} {'max':>8s}")
    errors: list[str] = []
    warnings: list[str] = []
    for stat in sorted(observations):
        opts = next(r for r in active if r["target"]["id"] == stat)
        obs = observations[stat]
        freq = obs / total_rolls if total_rolls else 0.0
        vals = magnitudes[stat]
        row = "  {:32s} {:14s} {:6d} {:6.3f} {:8.2f} {:8.2f}".format(
            stat, opts["family"], obs, freq, min(vals), max(vals)
        )
        info(row)
        if obs == 0:
            errors.append(f"{stat}: never selected in {total_rolls} rolls")
    # Coverage: every active option should be selectable.
    selectable = set(observations.keys())
    for record in active:
        if record["target"]["id"] not in selectable:
            errors.append(f"{record['id']}: not selectable in simulation")
    if errors:
        for error in errors:
            fail(error)
        if fail_on == "error":
            fail(f"option distribution failed: {len(errors)} error(s)")
            return 1
    if warnings:
        for warning in warnings:
            info(f"  warn: {warning}")
    ok("option distribution audit complete")
    return 0


def _weighted_pick(rng: random.Random, weights: dict) -> str:
    total = sum(weights.values())
    if total <= 0:
        raise ToolError("no positive weights to select from")
    pick = rng.random() * total
    for key, weight in weights.items():
        pick -= weight
        if pick <= 0:
            return key
    return next(iter(weights))


def _magnitude_bounds(unit: str, realm_index: int, rarity_index: int) -> dict:
    policy = {
        "magnitude": [1.0, 10.0, 0.10, 0.25],
        "rate": [0.01, 0.05, 0.005, 0.01],
        "fraction": [0.01, 0.05, 0.005, 0.01],
    }.get(unit, [1.0, 10.0, 0.10, 0.25])
    realm_factor = 1.0 + realm_index * float(policy[2])
    rarity_factor = 1.0 + rarity_index * float(policy[3])
    return {
        "min": float(policy[0]) * realm_factor * rarity_factor,
        "max": float(policy[1]) * realm_factor * rarity_factor,
    }
