"""The authored technique magnitude ladder: emit it, check it, print it.

ADR 0055 sized a third per-realm table. `core/realm_power_table.tres` is an
actor's strength (1.0 → 551x) and `data/item_options/item_magnitude_scale.json`
is a relative item upgrade (1.0 → 3.9x); a technique's magnitude measures neither,
it is a bonus riding on top of both, so it gets its own table at
`game/data/techniques/technique_magnitude_table.tres`, keyed by realm id, 1.0 →
~2.77x.

This module exists for two jobs and no more, exactly like `realm_power.py`:

- **`emit`** writes the file from the one authored step below, so the 30 numbers
  are produced by arithmetic rather than by a language model guessing them. It
  never overwrites an existing file without `--force`, because the table is
  authored content the moment it lands on disk.
- **`check`** asserts the *properties* the runtime depends on: one entry per realm
  and no others, R1 at exactly 1.0, strictly rising, every consecutive ratio at or
  below `TECHNIQUE_STEP`, all finite, and the top inside a readable range.

`check` deliberately does **not** assert that the file still equals the recipe, for
the reason `realm_power check` does not either: if it did, the recipe would be the
real source of truth and the file a cache, which is the private-curve failure ADR
0050 removed wearing a data file as a disguise. A designer retunes a realm by
editing one line of the `.tres`.

The per-pair ratio assertion is the load-bearing one. ADR 0055 rejects a linear
ladder precisely because a linear step shrinks as a percentage of a rising base,
so the linear shape fails at the DEEP end - and a check that only compared the
first pair, or only the total span, would pass a ladder that is exactly wrong
where the work-budget floor binds. Measured: the authored item table breaks the
ceiling on 19 of its 29 pairs. This guard walks every pair.

`LEARN_STEP` is asserted here too, and it is the more important of the two
numbers for a player's progress: the learning-cost ladder is what spends it. The
constant itself is owned by the techniques module (`src/modules/techniques/`, one
`LEARN_STEP` per path like the triplicated `RATE_STEP`); it is restated here
rather than imported because a GDScript constant cannot be read from Python, and
restating it in the guard is the point - a copy that disagrees with the module is
the drift this catches.
"""

from __future__ import annotations

import math
import re
from pathlib import Path

from .common import GAME_DIR, ToolError, info, ok, warn
from .realm_power import load_realms

TABLE_REL = Path("data/techniques/technique_magnitude_table.tres")
TABLE_SCRIPT = "res://src/core/technique_magnitude_table.gd"

# The `.tres` body is a plain Dictionary literal. Godot's text resource parser
# accepts no comment lines inside `[resource]` - one silently swallows the
# property after it - so every note about this file lives in
# `src/core/technique_magnitude_table.gd` instead.
TABLE_BLOCK = re.compile(r"^values = \{\n(.*?)^\}\s*$", re.MULTILINE | re.DOTALL)
TABLE_ENTRY = re.compile(r'^\s*&"([a-z0-9_]+)":\s*(-?[\d.]+),?\s*$')

# The recipe. One authored number, from ADR 0055: the per-realm step of a
# technique's magnitude, sized at the measured binding floor of the per-realm work
# budget - qi's own deep step, `progress_required` at R29 to R30, which is
# `2900/2800 = 29/28`. Body and mind are looser at 1.047619 and 1.052225, so qi
# sets the floor a shared ladder has to clear. A magnitude that outran the budget
# would make the deep realms cheap.
#
# This is a comment, not a dependency: `check` never asks whether the file still
# equals it.
TECHNIQUE_STEP = 1.035714

# The learning-cost step, per ADR 0055, owned by the techniques module (one copy
# per cultivation path, like `RATE_STEP`). It is the ladder that actually spends
# player progress, so it carries two separate obligations:
#
#   1. it stays at or below the work-budget floor, with ~0.55% of headroom; and
#   2. it clears the authored `29/28`, so DEF-0084's generator drift (the authored
#      seeds drifting from the generator that produced them) cannot push it above
#      the floor it is measured against.
#
# If the module retunes `LEARN_STEP`, retune the constant below with it. The
# 0.55% margin is deliberately thin: that is what makes the two assertions below
# worth running.
LEARN_STEP = 1.03

# The authored qi budget ratio behind the floor: `progress_required` R30 / R29 =
# 2900 / 2800. The floor is the *measured* ratio, so the authored one is the
# value generator drift would move.
AUTHORED_QI_STEP = 29.0 / 28.0

# Emitted to 7dp and TRUNCATED, not rounded. This is a measured choice, not a
# display one: the ratio ceiling is a hard inequality on the parsed file, and
# nearest rounding pushes a pair as much as one unit in the last place ABOVE the
# step (6dp: 1.0357145, 5e-7 over). Truncation is monotone - every entry is at or
# below the exact `step^i` - so every consecutive ratio of the emitted file is at
# or below the step, by construction, with no epsilon fudge in the assertion. The
# cost is 2e-6 on the top of the ladder (2.766656 against an exact 2.7666585),
# which is a rounding artefact and not a balance number.
DECIMALS = 7

# A technique's magnitude is a bonus on top of the actor table. It must stay two
# orders of magnitude below `realm_power_table.tres`'s 551.46x, so a table that
# climbs into the hundreds is the category error ADR 0055 exists to prevent, not
# a retune. The ceiling is the ADR's own 2.7667 span plus generous headroom.
MAX_TOP = 10.0

# The floor: a technique must never be a penalty, and R1 is the neutral baseline.
MIN_VALUE = 1.0


def recipe(realms: list[tuple[str, str, int]]) -> list[float]:
    """Expand the single step into one magnitude per realm.

    Each realm is the one below it times `TECHNIQUE_STEP`, truncated as it goes,
    so the emitted table is auditable by hand: divide any entry by the one above
    it and the ratio is the step you can read off the ADR.
    """
    scale = 10**DECIMALS
    magnitudes = [1.0]
    for _realm_id, _display_name, _tier in realms[1:]:
        magnitudes.append(int(magnitudes[-1] * TECHNIQUE_STEP * scale) / scale)
    return magnitudes


def read_table() -> dict[str, float]:
    """The magnitudes as they are on disk, which is what the runtime will read."""
    path = GAME_DIR / TABLE_REL
    if not path.is_file():
        raise ToolError(f"{path} not found - run `uv run python -m tools technique_power emit`")
    block = TABLE_BLOCK.search(path.read_text(encoding="utf-8"))
    if block is None:
        raise ToolError(f"{path}: no `values = {{ ... }}` block")
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
            raise ToolError(f"{path}: unparseable magnitude {exc}") from exc
    if not table:
        raise ToolError(f"{path}: the magnitude table is empty")
    return table


def _render(realms: list[tuple[str, str, int]], magnitudes: list[float]) -> str:
    rows = ",\n".join(
        f'&"{realm_id}": {magnitude:.{DECIMALS}f}'
        for (realm_id, _name, _tier), magnitude in zip(realms, magnitudes, strict=True)
    )
    return (
        '[gd_resource type="Resource" script_class="TechniqueMagnitudeTable" '
        "load_steps=2 format=3]\n"
        "\n"
        f'[ext_resource type="Script" path="{TABLE_SCRIPT}" id="1"]\n'
        "\n"
        "[resource]\n"
        'script = ExtResource("1")\n'
        f"values = {{\n{rows}\n}}\n"
    )


def _print(realms: list[tuple[str, str, int]], table: dict[str, float]) -> None:
    width = max(len(realm_id) for realm_id, _name, _tier in realms)
    header = f"{'#':>3}  {'realm':<{width}}  {'tier':>4} {'magnitude':>12} {'step':>12}"
    print(header)
    print("-" * len(header))
    previous = 1.0
    for index, (realm_id, _name, tier) in enumerate(realms):
        current = table[realm_id]
        ratio = current / previous
        flag = "" if ratio <= TECHNIQUE_STEP else "  <- over the ceiling"
        print(
            f"{index + 1:>3}  {realm_id:<{width}}  {tier:>4} {current:>12.7f} {ratio:>11.7f}x{flag}"
        )
        previous = current
    top = table[realms[-1][0]]
    print(f"total R{len(realms)}/R1 = {top / table[realms[0][0]]:.4f}x")
    print(f"step {TECHNIQUE_STEP} x{len(realms) - 1} = {TECHNIQUE_STEP ** (len(realms) - 1):.4f}x")


def _emit(args) -> int:
    realms = load_realms()
    magnitudes = recipe(realms)
    path = GAME_DIR / TABLE_REL
    if path.exists() and not getattr(args, "force", False):
        warn(
            f"{TABLE_REL.as_posix()} already exists and is authored content; "
            "pass --force to overwrite it"
        )
        return 1
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_render(realms, magnitudes), encoding="utf-8")
    ok(f"wrote {len(magnitudes)} technique magnitudes to {TABLE_REL.as_posix()}")
    _print(realms, dict(zip([realm[0] for realm in realms], magnitudes, strict=True)))
    return 0


def _report(args) -> int:
    realms = load_realms()
    table = read_table()
    info(f"recipe: one step, TECHNIQUE_STEP = {TECHNIQUE_STEP} (ADR 0055, qi's work budget)")
    _print(realms, table)
    return 0


def _check_ladder(realms: list[tuple[str, str, int]]) -> int:
    """The guard for the magnitude table. Asserts its shape, not the recipe."""
    ladder_ids = [realm_id for realm_id, _name, _tier in realms]
    problems = 0
    try:
        table = read_table()
    except ToolError as exc:
        warn(str(exc))
        return 1

    missing = [realm_id for realm_id in ladder_ids if realm_id not in table]
    if missing:
        warn(
            f"no magnitude for: {', '.join(missing)} - add the entry or the technique "
            "stays at 1.0 for that realm"
        )
        problems += 1
    stale = sorted(set(table) - set(ladder_ids))
    if stale:
        warn(f"magnitude for realms no longer on the ladder: {', '.join(stale)} - drop them")
        problems += 1
    if not missing and not stale:
        ok(f"one magnitude per realm ({len(realms)}), no stale entries")

    if math.isclose(table.get(ladder_ids[0], 0.0), 1.0):
        ok("the first realm is the unscaled baseline")
    else:
        warn(
            f"the first realm is {table.get(ladder_ids[0])}, not 1.0 - a mortal technique "
            "must not be scaled"
        )
        problems += 1

    # The load-bearing loop. Every consecutive ratio, not the first one and not the
    # span: a linear ladder is under the ceiling at R1 and over it at R29 → R30,
    # which is exactly the shape this table must not have.
    previous_id = ladder_ids[0]
    previous = table.get(previous_id, 0.0)
    over: list[str] = []
    for realm_id in ladder_ids[1:]:
        current = table.get(realm_id)
        if current is None:
            previous, previous_id = current, realm_id
            continue
        if not math.isfinite(current):
            warn(f"{realm_id} is not finite ({current})")
        elif current <= previous:
            warn(
                f"{realm_id} ({current}) is not above {previous_id} ({previous}); "
                "a deeper realm must never be a smaller technique"
            )
            problems += 1
        else:
            ratio = current / previous
            if ratio > TECHNIQUE_STEP:
                over.append(f"{previous_id}->{realm_id} {ratio:.7f}x")
        previous, previous_id = current, realm_id

    if over:
        warn(
            f"{len(over)} of {len(realms) - 1} consecutive ratios exceed the ceiling "
            f"{TECHNIQUE_STEP}: {', '.join(over[:5])}"
            + (", ..." if len(over) > 5 else "")
            + " - a technique's magnitude must never outrun the per-realm work budget, "
            "or the deep realms get cheap; a geometric ladder satisfies the floor "
            "everywhere once it satisfies it at the deep end"
        )
        problems += 1
    elif len(realms) > 1:
        ratios = [
            table[ladder_ids[i + 1]] / table[ladder_ids[i]]
            for i in range(len(realms) - 1)
            if ladder_ids[i] in table and ladder_ids[i + 1] in table
        ]
        if len(ratios) == len(realms) - 1:
            ok(
                f"every one of the {len(ratios)} consecutive ratios is at or below the "
                f"ceiling {TECHNIQUE_STEP} (largest {max(ratios):.7f}x)"
            )

    top = table.get(ladder_ids[-1], 0.0)
    if math.isfinite(top) and MIN_VALUE < top <= MAX_TOP:
        ok(
            f"the ladder tops out at {top:.4f}x, inside the readable range and an order "
            "of magnitude below the 551x actor table"
        )
    else:
        warn(
            f"top of the ladder is {top}; keep it finite, above {MIN_VALUE} and at or below "
            f"{MAX_TOP:g} - a technique rides on top of the actor table, never on it"
        )
        problems += 1

    return problems


def _check_learn_step() -> int:
    """The learning-cost step, against the floor it is measured against.

    Owned by the techniques module; asserted here because the relationship is the
    invariant and the module cannot be imported from a Python guard. The ladder
    that spends a player's progress is worth one more line of gate.
    """
    problems = 0
    if LEARN_STEP <= TECHNIQUE_STEP:
        headroom = (TECHNIQUE_STEP / LEARN_STEP - 1) * 100
        ok(
            f"LEARN_STEP {LEARN_STEP} stays under the work-budget floor {TECHNIQUE_STEP} "
            f"with {headroom:.2f}% of headroom"
        )
    else:
        warn(
            f"LEARN_STEP {LEARN_STEP} is above the work-budget floor {TECHNIQUE_STEP}; "
            "study would cost more than a breakthrough and technique mastery would become "
            "the cheapest path to power"
        )
        problems += 1

    if LEARN_STEP <= AUTHORED_QI_STEP:
        ok(
            f"LEARN_STEP {LEARN_STEP} also clears the authored {AUTHORED_QI_STEP:.6f}, so "
            "generator drift in the qi seeds cannot push it above the floor"
        )
    else:
        warn(
            f"LEARN_STEP {LEARN_STEP} is above the authored {AUTHORED_QI_STEP:.6f}; DEF-0084's "
            "seed drift could push it over the floor without anything else changing"
        )
        problems += 1

    if TECHNIQUE_STEP <= AUTHORED_QI_STEP:
        ok(
            f"TECHNIQUE_STEP {TECHNIQUE_STEP} is at or below the authored "
            f"{AUTHORED_QI_STEP:.6f} it was measured from"
        )
    else:
        warn(
            f"TECHNIQUE_STEP {TECHNIQUE_STEP} is above the authored {AUTHORED_QI_STEP:.6f} "
            "qi budget step it was sized against"
        )
        problems += 1

    return problems


def _check(args) -> int:
    realms = load_realms()
    problems = _check_ladder(realms) + _check_learn_step()
    return 1 if problems else 0


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "technique_power", help="the authored per-realm technique magnitude ladder"
    )
    actions = parser.add_subparsers(dest="action", required=True)
    emit = actions.add_parser("emit", help="write the table from the authored step")
    emit.add_argument("--force", action="store_true", help="overwrite the authored table")
    emit.set_defaults(func=_emit)
    actions.add_parser("report", help="print the ladder with every consecutive ratio").set_defaults(
        func=_report
    )
    actions.add_parser(
        "check",
        help="guard: one entry per realm, strictly rising, every ratio under the ceiling",
    ).set_defaults(func=_check)


def run(args) -> int:
    return args.func(args)
