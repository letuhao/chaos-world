"""The authored difficulty preset table: check it, print it (ADR 0129).

Difficulty has one reason to change — what a difficulty id means — and a retune must not be a
code edit. So the presets live in one data file, `game/data/difficulty/difficulty_table.tres`,
keyed by a stable preset id, and the runtime reads it verbatim. This is the same shape and the
same reasoning as the realm power table (`tools/realm_power.py`), and for the same reason: a
number keyed by position shifts everything below it when something is inserted.

What difficulty is allowed to move is the whole of ADR 0129: **a fraction of what the player
already holds, never a magnitude the game computes.** That is why the scalar set is CLOSED.
This repo has three power-shaped tables already and a written rule that a fourth needs an ADR,
because reading one number as two is what produced the realm power ladder in the first place.
A fifth column here would be a fourth table wearing a difficulty label, so `check` fails on
it rather than trusting a future author to remember.

The set SHRANK from five to four (BL-0779). `loot_ceiling` was authored in every preset and
read by nothing, and a `LootTier` is ORDINAL — selected by an authored index, paying a per-band
reward and an authored vitality — so scaling one by a difficulty is ADR 0050's category error
one layer down. A column with no honest consumer is removed, not left authored.

`check` asserts **shape**, never a recipe, for the reason `realm_power.check` does: a guard
that re-derived the numbers would make the recipe the source of truth and the file a cache.
The file is authored content from the moment it lands; a designer retunes a preset by editing
one line.
"""

from __future__ import annotations

import math
import re

from .common import GAME_DIR, ToolError, info, ok, warn

TABLE_REL = "data/difficulty/difficulty_table.tres"
TABLE_SCRIPT = "res://src/modules/difficulty/difficulty_table.gd"

# The closed scalar vocabulary, mirrored from `DifficultyTable.SCALARS`. This tool asserts the
# set rather than restating the numbers: a scalar it does not know about is a failure, not a
# scalar it quietly ignores.
SCALARS = (
    "soul_damage_share",
    "guardian_effectiveness",
    "tribulation_preparation_credit",
)

# The preset that must be inert, so selecting the shipped default is a no-op. This is the
# "R1 at exactly 1.0" rule of the realm power table applied to a preset axis.
NEUTRAL = "standard"

# The preset that must be the hard end, so the ladder is a difficulty setting and not a menu.
HARDEST = "hard"

MIN_SCALAR = 0.0
MAX_SCALAR = 10.0

# Godot's text resource parser accepts no comment line inside `[resource]` — one silently
# swallows the property after it — so the file carries none and this module carries the notes.
PRESET_LINE = re.compile(r'^\s*&"([a-z0-9_]+)":\s*\{\s*$')
SCALAR_LINE = re.compile(r'^\s*"([a-z0-9_]+)":\s*(-?[\d.]+),?\s*$')
CLOSING_LINE = re.compile(r"^\s*\},\s*$")

# A column named after a realm, a tier or a position is ADR 0050's category error one layer
# down: a difficulty that scales by how deep the player is has become a second power curve.
FORBIDDEN_KEY_SHAPE = re.compile(r"realm|tier|ordinal|index|ladder|position", re.IGNORECASE)


def read_table() -> dict[str, dict[str, float]]:
    """The presets as they are on disk, which is what the runtime will read.

    Parsed rather than imported: the file is Godot content, and the tool must validate exactly
    what ships rather than what a Python-side model of it would produce.
    """
    path = GAME_DIR / TABLE_REL
    if not path.is_file():
        raise ToolError(f"{path} not found")
    lines = path.read_text(encoding="utf-8").splitlines()
    presets: dict[str, dict[str, float]] = {}
    current: str | None = None
    for line in lines:
        if line.startswith("presets") or line.strip() in {"", "[resource]"} or line.startswith("["):
            continue
        preset_match = PRESET_LINE.match(line)
        if preset_match is not None:
            current = preset_match.group(1)
            presets[current] = {}
            continue
        scalar_match = SCALAR_LINE.match(line)
        if scalar_match is not None and current is not None:
            try:
                presets[current][scalar_match.group(1)] = float(scalar_match.group(2))
            except ValueError as exc:
                raise ToolError(f"{path}: unparseable scalar {scalar_match.group(2)!r}") from exc
            continue
        if CLOSING_LINE.match(line):
            current = None
            continue
    if not presets:
        raise ToolError(f"{path}: no presets parsed - the table format changed")
    return presets


def _print(presets: dict[str, dict[str, float]]) -> None:
    width = max(len(name) for name in presets)
    header = f"{'preset':<{width}}  " + "  ".join(f"{scalar[:14]:>14}" for scalar in SCALARS)
    print(header)
    print("-" * len(header))
    for name in sorted(presets):
        row = presets[name]
        cells = "  ".join(f"{row.get(scalar, float('nan')):>14.2f}" for scalar in SCALARS)
        print(f"{name:<{width}}  {cells}")


def _report(args) -> int:
    presets = read_table()
    info(f"{len(presets)} presets, {len(SCALARS)} closed scalars")
    _print(presets)
    return 0


def _check(args) -> int:
    """The guard. Asserts the shape the runtime relies on, never the recipe."""
    try:
        presets = read_table()
    except ToolError as exc:
        warn(str(exc))
        return 1
    problems = 0

    for name, row in sorted(presets.items()):
        missing = [scalar for scalar in SCALARS if scalar not in row]
        if missing:
            warn(
                f"{name} is missing {', '.join(missing)} - a missing scalar reads as absent, "
                "and a consumer would read that as a zero"
            )
            problems += 1
        for scalar in sorted(set(row) - set(SCALARS)):
            warn(f"{name} carries an unknown column {scalar!r} - the scalar set is closed")
            problems += 1
        for scalar, value in sorted(row.items()):
            if not math.isfinite(value):
                warn(f"{name}.{scalar} is not finite ({value})")
                problems += 1
            elif not MIN_SCALAR <= value <= MAX_SCALAR:
                warn(
                    f"{name}.{scalar} is {value}, outside [{MIN_SCALAR:g}, {MAX_SCALAR:g}] - "
                    "a scalar out there is either decorative or a magnitude the game owns"
                )
                problems += 1
        for scalar in sorted(row):
            if FORBIDDEN_KEY_SHAPE.search(scalar):
                warn(
                    f"{name} carries a column named {scalar!r} - a difficulty that scales by how "
                    "deep the player is is a second power curve (ADR 0050)"
                )
                problems += 1

    if problems:
        return 1

    neutral = presets.get(NEUTRAL)
    if neutral is None:
        warn(f"the neutral preset {NEUTRAL!r} is missing, so an unset difficulty has no row")
        return 1
    drifted = [scalar for scalar, value in neutral.items() if not math.isclose(value, 1.0)]
    if drifted:
        warn(
            f"{NEUTRAL} is not inert on {', '.join(drifted)} - the shipped default must be "
            "exactly 1.0, or choosing the middle option silently retunes the game"
        )
        problems += 1
    else:
        ok(f"{NEUTRAL} is the neutral baseline on every scalar")

    hardest = presets.get(HARDEST)
    if hardest is None:
        warn(f"the hardest preset {HARDEST!r} is missing, so the ladder has no upper end")
        problems += 1
    elif hardest.get("soul_damage_share") is not None and neutral.get("soul_damage_share"):
        if hardest["soul_damage_share"] <= neutral["soul_damage_share"]:
            warn(
                f"{HARDEST}.soul_damage_share ({hardest['soul_damage_share']}) is not above "
                f"{NEUTRAL} ({neutral['soul_damage_share']}) - an unordered ladder is a menu"
            )
            problems += 1
        else:
            ok(
                f"{HARDEST} costs more than {NEUTRAL} "
                f"({hardest['soul_damage_share']}x vs {neutral['soul_damage_share']}x)"
            )

    return 1 if problems else 0


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "difficulty", help="the authored difficulty preset table: report, check"
    )
    actions = parser.add_subparsers(dest="difficulty_action", required=True)
    actions.add_parser("report", help="print every preset row").set_defaults(func=_report)
    actions.add_parser(
        "check",
        help="guard: the closed scalar set, bounded, with an inert neutral row",
    ).set_defaults(func=_check)


def run(args) -> int:
    return args.func(args)
