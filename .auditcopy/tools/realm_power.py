"""The authored per-realm power table: emit it, check it, print it.

ADR 0042 built one shared power ladder - `P(Θ) = C · exp(a·r + b·r² + c·s)` - and then
removed it (ADR 0050). What survives is the part that was never a curve: *which realm
is how strong*. That is content, so it lives in one data file,
`game/src/core/realm_power_table.tres`, keyed by realm id, and the runtime reads it
verbatim.

This module exists for two jobs and no more:

- **`emit`** writes the file from the recipe below, so the 30 numbers are produced by
  arithmetic rather than by a language model guessing them. It never overwrites an
  existing file without `--force`, because the table is authored content the moment it
  lands on disk.
- **`check`** asserts the *properties* the runtime depends on: one entry per realm and
  no others, R1 at exactly 1.0, every realm strictly above the one below it, all
  finite, and the top of the ladder inside a readable range.

`check` deliberately does **not** assert that the file still equals the recipe. If it
did, the recipe would be the real source of truth and the file would be a cache - which
is the private-curve failure ADR 0050 removed, wearing a data file as a disguise. The
recipe is how the first draft was written; the file is the truth from then on, and a
designer retunes a realm by editing one line of it.
"""

from __future__ import annotations

import math
import re
from pathlib import Path

from .common import GAME_DIR, ToolError, info, ok, warn

LADDER_REL = Path("src/core/realm_defaults.gd")
TABLE_REL = Path("src/core/realm_power_table.tres")
TABLE_SCRIPT = "res://src/core/realm_power_table.gd"

# The ladder is a fixed list in core/realm_defaults.gd. Tools parse it rather than
# restate it, so adding a realm is a one-place change.
REALM_LINE = re.compile(r'_make\(\s*&"([a-z0-9_]+)"\s*,\s*"([^"]*)"\s*,\s*([A-Z]+)\s*\)')
TIER_CONST = re.compile(r"^const\s+([A-Z_]+)\s*:?=\s*(-?\d+)", re.MULTILINE)

# The `.tres` body is a plain Dictionary literal. Godot's text resource parser accepts
# no comment lines inside `[resource]` - one silently swallows the property after it -
# so every note about this file lives in realm_power_table.gd instead.
TABLE_BLOCK = re.compile(r"^multipliers = \{\n(.*?)^\}\s*$", re.MULTILINE | re.DOTALL)
TABLE_ENTRY = re.compile(r'^\s*&"([a-z0-9_]+)":\s*(-?[\d.]+),?\s*$')

# The recipe. One step per realm tier: how much stronger the NEXT realm is than this
# one. Four authored numbers, no formula, no exponent - a designer reads this table and
# knows exactly what it says: a Mortal step is small, an Immortal step is a wall.
#
# The steps escalate with depth, which is the property ADR 0042 bought with its curve
# and this table keeps without one. The endpoint lands near 550x, the order of magnitude
# the authored per-tier ladders used before ADR 0042 (ADR 0016 measured P(R30) =
# 601.43), so the seed work requirements and capacities already on disk are not re-based
# by orders of magnitude. The old ladder's endpoint was 1.13e46.
TIER_STEP = {1: 1.12, 2: 1.22, 3: 1.32, 4: 1.45}

# Emitted to 2dp so a human can read the table and edit it without a spreadsheet.
DECIMALS = 2

# The top of the ladder must stay a number a player can be shown and a stat can carry.
# ADR 0042's ladder reached 1.13e46 at R30, which is why `check` bounds it here rather
# than trusting it.
MAX_TOP = 1.0e6


def load_realms() -> list[tuple[str, str, int]]:
    """`(realm_id, display_name, tier)` per ladder position, parsed from core source."""
    path = GAME_DIR / LADDER_REL
    if not path.is_file():
        raise ToolError(f"{path} not found")
    text = path.read_text(encoding="utf-8")
    tiers = {name: int(number) for name, number in TIER_CONST.findall(text)}
    realms: list[tuple[str, str, int]] = []
    for realm_id, display_name, tier_name in REALM_LINE.findall(text):
        if tier_name not in tiers:
            raise ToolError(f"{path}: realm {realm_id!r} names unknown tier {tier_name!r}")
        realms.append((realm_id, display_name, tiers[tier_name]))
    if not realms:
        raise ToolError(f"{path}: no realms parsed - the ladder format changed")
    return realms


def recipe(realms: list[tuple[str, str, int]]) -> list[float]:
    """Expand the per-tier steps into one multiplier per realm.

    Each realm is the one below it times its tier's step, rounded as it goes, so the
    emitted table is auditable by hand: divide any entry by the one above it and the
    ratio is a step you can read off the `TIER_STEP` table.
    """
    if not realms:
        return []
    multipliers = [1.0]
    for _realm_id, _display_name, tier in realms[1:]:
        step = TIER_STEP.get(tier)
        if step is None:
            raise ToolError(f"no authored step for tier {tier}; add one to TIER_STEP")
        multipliers.append(round(multipliers[-1] * step, DECIMALS))
    return multipliers


def read_table() -> dict[str, float]:
    """The multipliers as they are on disk, which is what the runtime will read."""
    path = GAME_DIR / TABLE_REL
    if not path.is_file():
        raise ToolError(f"{path} not found - run `uv run python -m tools realm_power emit`")
    block = TABLE_BLOCK.search(path.read_text(encoding="utf-8"))
    if block is None:
        raise ToolError(f"{path}: no `multipliers = {{ ... }}` block")
    table: dict[str, float] = {}
    for line in block.group(1).splitlines():
        if not line.strip():
            continue
        entry = TABLE_ENTRY.match(line)
        if entry is None:
            raise ToolError(f"{path}: unparseable entry {line.strip()!r}")
        try:
            table[entry.group(1)] = float(entry.group(2))
        except ValueError as exc:
            raise ToolError(f"{path}: unparseable multiplier {exc}") from exc
    if not table:
        raise ToolError(f"{path}: the multiplier table is empty")
    return table


def read_multipliers() -> list[float]:
    """The table as a ladder-ordered list, for a caller already walking realms in order.

    A projection of `read_table`, not a second source: it still resolves every value
    through the table, it just discards the ids. Raises if the table and the ladder
    disagree, because a positional read of a mismatched table is the silent shift this
    keying scheme exists to prevent.
    """
    realms = load_realms()
    table = read_table()
    multipliers: list[float] = []
    for realm_id, _display_name, _tier in realms:
        if realm_id not in table:
            raise ToolError(f"{TABLE_REL.as_posix()}: no multiplier for realm {realm_id!r}")
        multipliers.append(table[realm_id])
    return multipliers


def _render(realms: list[tuple[str, str, int]], multipliers: list[float]) -> str:
    rows = ",\n".join(
        f'&"{realm_id}": {multiplier:.{DECIMALS}f}'
        for (realm_id, _name, _tier), multiplier in zip(realms, multipliers, strict=True)
    )
    return (
        '[gd_resource type="Resource" script_class="RealmPowerTable" load_steps=2 format=3]\n'
        "\n"
        f'[ext_resource type="Script" path="{TABLE_SCRIPT}" id="1"]\n'
        "\n"
        "[resource]\n"
        'script = ExtResource("1")\n'
        f"multipliers = {{\n{rows}\n}}\n"
    )


def _print(realms: list[tuple[str, str, int]], table: dict[str, float]) -> None:
    width = max(len(realm_id) for realm_id, _name, _tier in realms)
    header = f"{'#':>3}  {'realm':<{width}}  {'tier':>4} {'power':>10} {'step':>8}"
    print(header)
    print("-" * len(header))
    previous = 1.0
    for index, (realm_id, _name, tier) in enumerate(realms):
        current = table[realm_id]
        print(
            f"{index + 1:>3}  {realm_id:<{width}}  {tier:>4} {current:>10.2f}"
            f" {current / previous:>7.2f}x"
        )
        previous = current
    top = table[realms[-1][0]]
    print(f"total R{len(realms)}/R1 = {top / table[realms[0][0]]:.2f}x")


def _emit(args) -> int:
    realms = load_realms()
    multipliers = recipe(realms)
    path = GAME_DIR / TABLE_REL
    if path.exists() and not getattr(args, "force", False):
        warn(
            f"{TABLE_REL.as_posix()} already exists and is authored content; "
            "pass --force to overwrite it"
        )
        return 1
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_render(realms, multipliers), encoding="utf-8")
    ok(f"wrote {len(multipliers)} realm multipliers to {TABLE_REL.as_posix()}")
    _print(realms, dict(zip([realm[0] for realm in realms], multipliers, strict=True)))
    return 0


def _report(args) -> int:
    realms = load_realms()
    table = read_table()
    info(
        "recipe: per-tier step " + "  ".join(f"t{tier}={step}" for tier, step in TIER_STEP.items())
    )
    _print(realms, table)
    return 0


def _check(args) -> int:
    """The guard. Asserts the properties the runtime relies on, not the recipe."""
    realms = load_realms()
    ladder_ids = [realm_id for realm_id, _name, _tier in realms]
    problems = 0
    try:
        table = read_table()
    except ToolError as exc:
        warn(str(exc))
        return 1

    missing = [realm_id for realm_id in ladder_ids if realm_id not in table]
    if missing:
        warn(f"no multiplier for: {', '.join(missing)} - add the entry or the realm stays unscaled")
        problems += 1
    stale = sorted(set(table) - set(ladder_ids))
    if stale:
        warn(f"multiplier for realms no longer on the ladder: {', '.join(stale)} - drop them")
        problems += 1
    if not missing and not stale:
        ok(f"one multiplier per realm ({len(realms)}), no stale entries")

    if math.isclose(table.get(ladder_ids[0], 0.0), 1.0):
        ok("the first realm is the unscaled baseline")
    else:
        warn(
            f"the first realm is {table.get(ladder_ids[0])}, not 1.0 - a mortal must not be scaled"
        )
        problems += 1

    previous_id = ladder_ids[0]
    previous = table.get(previous_id, 0.0)
    for realm_id in ladder_ids[1:]:
        current = table.get(realm_id)
        if current is None:
            previous, previous_id = previous, realm_id
            continue
        if not math.isfinite(current):
            warn(f"{realm_id} is not finite ({current})")
        elif current <= previous:
            warn(
                f"{realm_id} ({current}) is not above {previous_id} ({previous}); "
                "a breakthrough must never be a power loss"
            )
            problems += 1
        previous, previous_id = current, realm_id

    top = table.get(ladder_ids[-1], 0.0)
    if math.isfinite(top) and 0.0 < top <= MAX_TOP:
        ok(f"the ladder tops out at {top:.2f}x, inside the readable range")
    else:
        warn(f"top of the ladder is {top}; keep it finite and at or below {MAX_TOP:g}")
        problems += 1

    return 1 if problems else 0


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "realm_power", help="the authored per-realm power table: emit, report, check"
    )
    actions = parser.add_subparsers(dest="action", required=True)
    emit = actions.add_parser("emit", help="write the table from the per-tier recipe")
    emit.add_argument("--force", action="store_true", help="overwrite the authored table")
    emit.set_defaults(func=_emit)
    actions.add_parser("report", help="print the table with its per-realm step").set_defaults(
        func=_report
    )
    actions.add_parser(
        "check", help="guard: one entry per realm, strictly rising, finite, bounded"
    ).set_defaults(func=_check)


def run(args) -> int:
    return args.func(args)
