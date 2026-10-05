"""Re-derive stale authored item magnitudes against the current realm scale.

`item_magnitude_scale.json` is authored balance: one multiplier per realm, and a
designer retunes a realm by editing that file. Every magnitude an item carries
was once read off a shared ladder reaching ~1e46 by realm 30; when the ladder was
replaced, the authored values that were *derived from it* stopped meaning
anything, and `data audit` reports them as out of band.

This tool re-derives those values. It never widens the scale, never clamps a
value to a window edge, and never divides the corpus by a constant: each stale
value is replaced by the value its own item tier implies under the option's own
authored magnitude range.

The derivation, per fixed entry:

1. **Cohort** - the item's design peers: `(category, subcategory, option, realm,
   rarity)`. Peers share one window, so the cohort is the population whose
   relative standing is meaningful.
2. **Window** - the option's realm/rarity magnitude range at the item's authored
   realm and rarity, intersected with the option's declared final `bounds` (the
   runtime clamps fixed values into them, so an authored value above one is a
   lie the game would silently correct).
3. **Position** - the item's authored value is replaced by the cohort's *distinct
   authored values* mapped in ascending order onto the window's representable
   grid, evenly spread and strictly increasing. The magnitude of the authored
   number is discarded; only its ordinal standing among the cohort's peers
   survives, re-expressed in the current scale.

Equal authored values stay equal (peers that were identical remain identical)
and the ordering is preserved exactly, which is what a magnitude change is
supposed to do: move the corpus onto new numbers, not reshape it. The invariant
holds among the values this tool moves; a value that was already legal is left
exactly as authored, so a derived peer can end up adjacent to one.

Why this is a derivation and not a clamp: a clamp is a function of the stale
number alone - it keeps the number and pins it to an edge. This is a function of
the cohort the item belongs to, so two peers that used to differ still differ,
in the ratio the current window allows, and a number nobody designed never
survives as itself.

Idempotent: a value already inside its window is never touched, so a second run
finds nothing to do. Deterministic: no RNG, ties resolved by value equality, and
all arithmetic done in integer grid ticks. `--limit` is a debugging aid that
deliberately breaks that guarantee - a cohort's positions come from the values
currently in it, so a partially applied cohort converges on the next full run
rather than in the run that stops early.
"""

from __future__ import annotations

import re
from collections import Counter
from decimal import ROUND_CEILING, ROUND_FLOOR, Decimal
from pathlib import Path

from .common import REPO_ROOT, ToolError, fail, info, ok
from .options import _scale_ladder  # noqa: PLC0415

# Content roots the derivation owns. `items` is the main item tree; `socket` is a
# module's own item namespace, which `data audit` gates with exactly the same
# rules (ADR 0008), so leaving it stale would keep the gate red.
DEFAULT_ROOTS = ("items", "socket")
FIXED_BLOCK = re.compile(r"(?ms)^fixed_modifiers = Array\[Dictionary\]\(\[(.*?)^\]\)")
ENTRY = re.compile(
    r'(?P<head>\{"option_id": &"(?P<option>[a-z_0-9]+)", "value": )'
    r"(?P<value>-?\d+(?:\.\d+)?)(?P<tail>\},?)"
)


def register(subparsers) -> None:
    """Wire the command the way `tools/__main__.py` expects."""
    parser = subparsers.add_parser(
        "item_derive",
        help="re-derive stale authored item magnitudes against the current scale",
    )
    _add_actions(parser.add_subparsers(dest="item_derive_action", required=True))


def _add_actions(actions) -> None:
    for name, help_text in (
        ("report", "report the stale values and the value each would be given"),
        ("apply", "write the re-derived values"),
    ):
        action = actions.add_parser(name, help=help_text)
        action.add_argument("--root", default=None, help="data root (default game/data)")
        action.add_argument(
            "--roots",
            default=",".join(DEFAULT_ROOTS),
            help="comma-separated content roots to re-derive (default items,socket)",
        )
        action.add_argument("--limit", type=int, default=0, help="stop after N changed files")


def run(args) -> int:
    action = getattr(args, "item_derive_action", None)
    if action not in {"report", "apply"}:
        raise ToolError(f"unknown item_derive action: {action}")
    from . import data  # noqa: PLC0415 - avoids an import cycle at module load

    root = Path(getattr(args, "root", None) or data.DATA_ROOT)
    roots = (
        tuple(
            part.strip() for part in (getattr(args, "roots", None) or "").split(",") if part.strip()
        )
        or DEFAULT_ROOTS
    )
    plan, notes = plan_derivation(root, roots)
    verb = "re-derived" if action == "apply" else "would re-derive"
    changed, moved, limit = 0, 0, int(getattr(args, "limit", 0) or 0)
    for path, updates in plan.items():
        if limit and changed >= limit:
            break
        # `newline=""` on both sides: a .tres is editor-owned text and the corpus
        # is not uniformly CRLF, so a value rewrite must not restate the whole
        # file's line endings.
        with path.open("r", encoding="utf-8", newline="") as handle:
            text = handle.read()
        updated, moved_here = rewrite(text, updates)
        if not moved_here:
            continue
        changed += 1
        moved += moved_here
        if action == "apply":
            with path.open("w", encoding="utf-8", newline="") as handle:
                handle.write(updated)
    scope = ", ".join(roots)
    info(f"{verb} {moved} value(s) across {changed} of {len(plan)} file(s) under {scope}")
    for key, count in sorted(notes["by_root"].items()):
        info(f"  {key:12s} {count:6d} value(s)")
    for key, count in sorted(notes["by_side"].items()):
        info(f"  {key:12s} {count:6d} value(s)")
    if action == "report" and notes["sample"]:
        info("")
        info("=== Sample ===")
        info(f"  {'item':44s} {'option':22s} {'authored':>9s} {'window':>20s} {'derived':>9s}")
        for row in notes["sample"][:12]:
            window = f"[{row['low']:.4g}, {row['high']:.4g}]"
            info(
                f"  {row['item']:44s} {row['option']:22s} {row['before']:>9g} "
                f"{window:>20s} {row['after']:>9s}"
            )
    for key, count in sorted(notes["reasons"].items()):
        info(f"  left alone: {count:5d}  {key}")
    for detail in notes["details"][:10]:
        info(f"    {detail}")
    for line in notes["skipped"][:10]:
        info(f"    skipped: {line}")
    if notes["details"]:
        fail(
            f"{len(notes['details'])} value(s) cannot be represented inside their window at "
            f"the option's declared precision; the option's bounds, not the item, are wrong"
        )
        return 1
    if action == "apply":
        ok("authored item magnitudes re-derived")
    else:
        ok("derivation plan is complete (dry run)")
    return 0


# --- Planning ---------------------------------------------------------------


def _edge(value: float, precision: int, rounding: str) -> int:
    """A window edge as an integer grid tick.

    `Decimal(repr(x))` keeps the authored decimal free of binary dust, so an edge
    never lands a whole tick away from where it reads (`ceil(1.0 / 0.01)` is 101
    in binary floating point, not 100).
    """
    step = Decimal(1).scaleb(-precision)
    scaled = Decimal(repr(value)) / step
    return int(scaled.to_integral_value(rounding=rounding))


def _window(record: dict, realm_id: str, rarity_index: int) -> tuple[float, float]:
    """The option's realm/rarity magnitude range, intersected with its final bounds.

    The intersection is what the game will actually apply to a fixed value
    (`OptionCatalog.clamp_to_bounds`), so it is the range a derived value has to
    be inside for the authored number to mean what it says.
    """
    from .data import _magnitude_bounds  # noqa: PLC0415

    low, high = _magnitude_bounds(record["unit"], realm_id, rarity_index)
    limits = record.get("bounds") or {}
    if "min" in limits:
        low = max(low, float(limits["min"]))
    if "max" in limits:
        high = min(high, float(limits["max"]))
    return low, high


# One extra decimal place, and no more: a narrow rate window can hold fewer ticks
# than a cohort has distinct authored values, and a refinement ladder is worth one
# place of precision. Past that the window is the thing that is wrong, and the
# value gets reported instead of moved.
MAX_EXTRA_PLACES = 1


def window_ticks(
    record: dict, realm_id: str, rarity_index: int, places: int | None = None
) -> tuple[int, int, int]:
    """`(first, last, places)` grid ticks of an option's representable window."""
    low, high = _window(record, realm_id, rarity_index)
    places = int(record.get("precision", 2)) if places is None else places
    return _edge(low, places, ROUND_CEILING), _edge(high, places, ROUND_FLOOR), places


def places_for(record: dict, realm_id: str, rarity_index: int, needed: int) -> tuple[int, int, int]:
    """The finest grid that can tell a cohort's authored values apart.

    The option's declared precision answers for every cohort whose distinct values
    fit it; the grid is only refined when the window would otherwise force distinct
    authored values onto one another.
    """
    declared = int(record.get("precision", 2))
    fallback = window_ticks(record, realm_id, rarity_index, declared)
    for places in range(declared, declared + MAX_EXTRA_PLACES + 1):
        first, last, _ = window_ticks(record, realm_id, rarity_index, places)
        if last - first + 1 >= needed:
            return first, last, places
    return fallback


def derived_values(values: list[float], first: int, last: int) -> dict[float, int]:
    """Map a cohort's distinct authored values onto the window's grid.

    Ascending in, ascending out: the cohort's ordering and its equality classes
    are preserved, and the spread is even. The window's ticks are split into one
    disjoint slot per distinct authored value, so no two values can ever collide
    - the property that makes a second run find nothing to change. Integers all
    the way down, so no value can drift out of the window through float rounding.
    """
    groups = sorted(set(values))
    span = last - first + 1
    if span <= 0:
        return {}
    if len(groups) > span:
        # The window cannot host one distinct value per authored value at the
        # option's declared precision. One value for the whole cohort is the only
        # honest answer, and it is a fixed point: a re-run sees a single group.
        center = first + (span - 1) // 2
        return {value: center for value in groups}
    out: dict[float, int] = {}
    count = len(groups)
    for index, value in enumerate(groups):
        # Every slot is non-empty when span >= count, and they tile [first, last].
        slot_low = first + (span * index) // count
        slot_high = first + (span * (index + 1)) // count - 1
        tick = round((slot_low + slot_high) / 2)
        out[value] = max(slot_low, min(slot_high, tick))
    return out


def _render(tick: int, precision: int) -> str:
    """One authored number, in the corpus's own plain-decimal style."""
    text = f"{tick * Decimal(1).scaleb(-precision):f}"
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    if "e" in text or "E" in text:  # pragma: no cover - defensive, never authored
        raise ToolError(f"derived value {text} is not a plain decimal")
    return text


def plan_derivation(root: Path, roots: tuple[str, ...]) -> tuple[dict[Path, dict], dict]:
    """Every stale value mapped to its re-derived number, keyed by file."""
    from . import data  # noqa: PLC0415
    from .options import DEFAULT_CATALOG, _load_jsonl  # noqa: PLC0415

    data._load_realms()
    records, _, _ = data._load(root)
    catalog = {r["id"]: r for r in _load_jsonl(DEFAULT_CATALOG)}
    cohorts: dict[tuple, list[tuple[str, float]]] = {}
    item_by_id = {record["id"]: record for record in records.get("item", {}).values()}
    for record in records.get("item", {}).values():
        scalars = record["scalars"]
        if not any(record["path"].startswith(f"{name}/") for name in roots):
            continue
        for option_id, value in record["fixed"].items():
            if option_id not in catalog:
                continue
            cohorts.setdefault(
                (
                    scalars.get("category", ""),
                    scalars.get("subcategory", ""),
                    option_id,
                    scalars.get("realm", ""),
                    scalars.get("rarity", ""),
                ),
                [],
            ).append((record["id"], value))

    plan: dict[Path, dict] = {}
    reasons: Counter[str] = Counter()
    details: list[str] = []
    by_root: Counter[str] = Counter()
    by_side: Counter[str] = Counter()
    sample: list[dict] = []
    skipped: list[str] = []
    scale_ladder = set(_scale_ladder())
    for key in sorted(cohorts):
        category, _sub, option_id, realm, rarity = key
        members = cohorts[key]
        record = catalog[option_id]
        rarity_index = data.RARITY_INDEX.get(rarity, 0)
        # A cohort whose items declare no realm is not realm-scaled, so there is no
        # authored per-realm factor to check it against. Falling back to a ladder
        # position would judge it against a realm it does not belong to, which is
        # the index-keyed mistake ADR 0050 exists to prevent. Report and skip.
        if realm not in scale_ladder:
            reasons["item declares no realm, so it has no authored realm window"] += len(members)
            skipped.append(
                f"{category}/{option_id}@{realm or '<no realm>'}/{rarity}: "
                f"{len(members)} authored value(s) left alone, the item declares no realm"
            )
            continue
        low, high = _window(record, realm, rarity_index)
        # Staleness is judged against the window the gate judges against, not
        # against a grid: an authored value carrying more decimals than the
        # option's declared precision is still a legal authored value, and the
        # runtime does not re-round fixed effects.
        stale = [(item_id, value) for item_id, value in members if not low <= value <= high]
        if not stale:
            continue
        first, last, places = places_for(
            record, realm, rarity_index, len(set(value for _, value in members))
        )
        table = derived_values([value for _, value in members], first, last)
        if not table:
            reasons["option window is narrower than one declared-precision step"] += len(stale)
            details.append(
                f"{category}/{option_id}@{realm}/{rarity}: window "
                f"[{low:g}, {high:g}] cannot hold a value at precision {places}"
            )
            continue
        if places > int(record.get("precision", 2)):
            reasons["cohort needed one decimal past the option's precision to stay distinct"] += (
                len(stale)
            )
        if len(set(table.values())) == 1 and len({value for _, value in members}) > 1:
            reasons["cohort collapsed: window cannot host one value per authored value"] += len(
                stale
            )
        scale = 10.0**-places
        for item_id, value in stale:
            tick = table[value]
            rendered = tick * scale
            if not low <= rendered <= high:  # pragma: no cover - the slots guarantee this
                reasons["derived value fell outside the window"] += 1
                details.append(f"{item_id}:{option_id}={value:g} has no in-window value")
                continue
            item = item_by_id[item_id]
            text = _render(tick, places)
            plan.setdefault(REPO_ROOT / "game" / "data" / item["path"], {})[option_id] = text
            by_root[item["path"].split("/")[0]] += 1
            side = "below" if value < low else "above"
            by_side[side] += 1
            sample.append(
                {
                    "item": item_id,
                    "option": option_id,
                    "before": value,
                    "after": text,
                    "low": low,
                    "high": high,
                }
            )
    # One row per option - the option that moved furthest, not the option that
    # happens to sort first - so the sample spans the catalog instead of one
    # repeated option.
    extremes: dict[str, dict] = {}
    for row in sample:
        current = extremes.get(row["option"])
        if current is None or abs(_ratio(row)) > abs(_ratio(current)):
            extremes[row["option"]] = row
    ordered = sorted(extremes.values(), key=lambda row: -abs(_ratio(row)))
    return plan, {
        "reasons": reasons,
        "details": details,
        "skipped": skipped,
        "by_root": by_root,
        "by_side": by_side,
        "sample": ordered,
    }


def _ratio(row: dict) -> float:
    """How far a value had to move, in log ticks of the window it now sits in."""
    span = row["high"] - row["low"]
    if span <= 0 or row["before"] <= 0:
        return 0.0
    inside = (row["low"] + row["high"]) / 2.0
    return (inside / row["before"]) - 1.0


# --- Writing ----------------------------------------------------------------


def rewrite(text: str, updates: dict[str, str]) -> tuple[str, int]:
    """Replace only the numbers of the named options, leaving the file untouched elsewhere.

    The whole block is matched first so an update can never land on a value
    belonging to a different option, and the entry regex anchors on the option id
    so field order, indentation and the trailing comma survive untouched. Returns
    the new text and how many numbers actually changed.
    """
    match = FIXED_BLOCK.search(text)
    if not match:
        raise ToolError("no fixed_modifiers block to rewrite")
    body = match.group(1)
    pending = dict(updates)
    moved = 0

    def replace(entry: re.Match[str]) -> str:
        nonlocal moved
        option = entry.group("option")
        if option not in pending:
            return entry.group(0)
        rendered = pending.pop(option)
        if entry.group("value") == rendered:
            return entry.group(0)
        moved += 1
        return f"{entry.group('head')}{rendered}{entry.group('tail')}"

    rewritten = ENTRY.sub(replace, body)
    if pending:
        raise ToolError(f"fixed_modifiers block has no entry for {sorted(pending)}")
    return text[: match.start(1)] + rewritten + text[match.end(1) :], moved


def main(argv: list[str] | None = None) -> int:
    import argparse  # noqa: PLC0415

    parser = argparse.ArgumentParser(prog="tools.item_derive")
    _add_actions(parser.add_subparsers(dest="item_derive_action", required=True))
    args = parser.parse_args(argv)
    try:
        return run(args)
    except ToolError as exc:
        fail(str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
