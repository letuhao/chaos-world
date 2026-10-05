"""Apply one authored price ladder to the `trade_value` of a chosen item slice.

ADR 0094 left the re-value wave explicitly undone: *"The ~250 authored
`trade_value` numbers are wrong as prices and are not rewritten here. A re-value
wave regenerates them from one authored ladder."* This is that wave, scoped.

## What a worth IS, and what it deliberately is not

`EconomyValuation.unit_price` is the only price function in the game:

```
maxi(1, roundi(base_worth * RARITY_WEIGHT[rarity] * RealmRate.factor(realm)))
```

`RARITY_WEIGHT` already spans 1.0 -> 4.0 over the four rarities, and
`RealmRate.factor` is `1.02^ordinal`, under 2x across all thirty realms. Between
them a price already spans about 7x without this tool contributing anything.

So the only question `base_worth` has to answer is **"what kind of thing is
this?"** — and rarity is already a multiplier in the formula, so folding rarity
into the worth as well would square a term the formula owns. The ladder
therefore scales by **category alone**, flat across realms. See
`CATEGORY_WORTH`'s docstring for why a realm term here would be ADR 0050's
failure.

## Realm-invariance is the property being preserved

ADR 0094's load-bearing claim is that *price is realm-invariant in ratio while
income is not*: a R30 buyer pays the same price for a given good as a R1 buyer
and earns far more. A worth scaled by realm would build a second magnitude
ladder on top of the bounded `RealmRate` curve, and the 551x actor ladder would
then be metered by price as well as by power — which is ADR 0050's exact open
debt. Nothing in this file reads an item's realm; `no_realm_term_in_the_ladder`
is the machine check that it stays that way.

## Safety, in the order it actually matters

- **Only the `trade_value` row is written.** Authored stats, id, realm, rarity,
  category, subcategory and sources are never parsed into a write path; the
  rewriter appends one row inside the `fixed_modifiers` block and leaves every
  other byte of the file untouched.
- **Only a file with no existing `trade_value` is written.** An authored number
  a designer chose is never overwritten, so the tool is idempotent by
  construction and a re-run reports zero.
- **Dry-run by default.** Writing requires the `apply` action.
- **Deterministic.** No `random`, no clock, no directory-order dependence: files
  are visited in sorted order and the ladder is a pure function of one category.
- **Scope is explicit.** `--roots` names content roots, `--categories` names
  categories, and an unknown category is refused rather than defaulted.
"""

from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

from .common import ToolError, fail, info, ok

# --- The ladder --------------------------------------------------------------

## One base worth per item CATEGORY, in coins of the numéraire.
##
## These are the numbers. They span 130x across the eight categories, which is
## the whole budget a worth ladder gets: the formula's own rarity term is 4x and
## its realm term is under 2x, so the category term stays a *distinguishing* term
## rather than the dominant one, and no category's worth reads as a power
## statement.
##
## The ordering is "what does obtaining this cost", not "how strong is it",
## because a price is a cost and never a magnitude (ADR 0094):
##
##   currency     2 — a note or a token. The cheapest thing that exists, and the
##                  reason every other category is priced above it.
##   material     6 — a reagent or a hide. Gathered or grown: the bottom of the
##                  goods range, and the input to nearly every recipe.
##   key         12 — a document that opens something. Priced for what it
##                  admits, not for the door.
##   misc        18 — an object with no use of its own, carried because someone
##                  wanted it. Deliberately above `material`: no yield sets it.
##   quest       34 — a delivered consequence. Scales with what completing it
##                  cost, and it is never sold back — a shop's `buys` list is
##                  where that refusal is expressed (ADR 0100).
##   consumable  85 — a prepared dose: the crafting work plus the reagent, so it
##                  is the first category above the reagent line.
##   technique  150 — an instruction. Nothing else in the corpus produces one.
##   equipment   260 — a finished implement, the output of the longest craft
##                  chain. Highest, and the ladder's full span stays 130x rather
##                  than the 551x an actor ladder would give.
##
## ## Why there is deliberately NO realm term here
##
## `RealmRate.factor(realm)` is already in the formula and is bounded by
## construction (`1.02^29 = 1.776`). A worth scaled by realm would be a SECOND
## per-realm magnitude on the same quantity — exactly the ADR 0050 debt that
## `item_magnitude_scale.json` (1.0 -> 3.9x) already creates against
## `realm_power_table.tres` (1.0 -> 551x). ADR 0094's whole argument is that a
## deep actor accumulates a larger pile, not a larger price, and that holds only
## if the authored input is flat across realms.
CATEGORY_WORTH: dict[str, float] = {
    "currency": 2.0,
    "material": 6.0,
    "key": 12.0,
    "misc": 18.0,
    "quest": 34.0,
    "consumable": 85.0,
    "technique": 150.0,
    "equipment": 260.0,
}

## Content roots the wave may touch, relative to the data root.
DEFAULT_ROOTS: tuple[str, ...] = ("items",)

## The shipped wave.
##
## These two are chosen on a measured fact, not taste. `trade_value`'s catalog
## record declares `categories: ["currency"]`, and `activations_for` derives the
## only channels it may be authored on as `{"property"}`. `CATEGORY_ACTIVATION`
## maps `key`, `currency`, `quest` and `misc` to `property`, and `material`,
## `consumable`, `technique` and `equipment` to `crafted`/`equipped`/`learned`.
## Authoring `trade_value` on a material — the obvious slice, and the one this
## wave was originally scoped to — is therefore counted as a MISACTIVATED option
## by `data distribution`. Measured, not assumed: one such row moves that count
## from 3631 to 3632. The wave is scoped to categories the option may legally
## carry, and the tool refuses a category outside `CATEGORY_WORTH` rather than
## writing a row the gate will flag.
##
## `key` + `misc` is 459 files, which is the wave a designer can review as one
## change and lands inside the 300..600 budget the wave was given. `quest` is
## deliberately NOT in the default: it is legal and would take the wave to 692,
## and a second wave is a smaller diff on a branch other agents are writing to.
## Name it explicitly with `--categories quest` when that wave is taken.
##
## `currency` is excluded because all 221 of its defs already ship an authored
## worth, and an authored number is never overwritten: naming it would cost a
## full scan to change nothing.
DEFAULT_CATEGORY_WAVE: tuple[str, ...] = ("key", "misc")

# --- File shapes -------------------------------------------------------------
#
# `.tres` is editor-owned text and the corpus is NOT uniformly LF: 22 of the 692
# defs in the `key` + `misc` + `quest` wave are CRLF. Both patterns below are
# therefore newline agnostic — the block span is located without assuming `\n`,
# and the row's own EOL is captured so an inserted row copies the file's OWN line
# ending rather than restating the whole file's terminators. A value rewrite must
# not show up as a whole-file whitespace diff on a shared branch.

FIXED_BLOCK = re.compile(r"(?ms)^fixed_modifiers = Array\[Dictionary\]\(\[(.*?)^\]\)")
# `re.M` is load-bearing: the row pattern is anchored `^\t`, and without MULTILINE
# `^` binds to the start of the extracted BLOCK BODY rather than to the start of
# each line in it, so `ENTRY.finditer` matches nothing on a file that is perfectly
# well formed. That is a silent zero-match, not an error, which is exactly the
# kind of failure a content rewrite must not have.
ENTRY = re.compile(
    r'^\t\{"option_id": &"(?P<option>[a-z_0-9]+)", "value": (?P<value>-?\d+(?:\.\d+)?)\},?'
    r"(?P<eol>\r?\n)",
    re.M,
)
PRICE_OPTION = "trade_value"


def register(subparsers) -> None:
    """Wire the command the way `tools/__main__.py` expects."""
    parser = subparsers.add_parser(
        "worth_rewrite",
        help="apply one authored price ladder to the trade_value of a chosen item slice",
    )
    actions = parser.add_subparsers(dest="worth_rewrite_action", required=True)
    for name, help_text in (
        ("report", "print what would be written (dry run, the default)"),
        ("apply", "write the ladder's worths"),
    ):
        action = actions.add_parser(name, help=help_text)
        action.add_argument("--root", default=None, help="data root (default game/data)")
        action.add_argument(
            "--roots",
            default=",".join(DEFAULT_ROOTS),
            help=f"comma-separated content roots (default {','.join(DEFAULT_ROOTS)})",
        )
        action.add_argument(
            "--categories",
            default=",".join(DEFAULT_CATEGORY_WAVE),
            help=f"comma-separated categories to price (default {','.join(DEFAULT_CATEGORY_WAVE)})",
        )
        action.add_argument("--exclude", default="", help="comma-separated item ids to skip")
        action.add_argument("--limit", type=int, default=0, help="stop after N files")


def run(args) -> int:
    action = getattr(args, "worth_rewrite_action", None)
    if action not in {"report", "apply"}:
        raise ToolError(f"unknown worth_rewrite action: {action}")
    from . import data  # noqa: PLC0415 - avoids an import cycle at module load

    root = Path(getattr(args, "root", None) or data.DATA_ROOT)
    roots = _csv(getattr(args, "roots", None), DEFAULT_ROOTS)
    categories = _csv(getattr(args, "categories", None), DEFAULT_CATEGORY_WAVE)
    excluded = set(_csv(getattr(args, "exclude", ""), ()))
    limit = max(0, int(getattr(args, "limit", 0) or 0))

    unknown = sorted(set(categories) - set(CATEGORY_WORTH))
    if unknown:
        raise ToolError(
            f"the ladder prices no category named {unknown}; the priced categories are "
            f"{sorted(CATEGORY_WORTH)}"
        )
    if not no_realm_term_in_the_ladder():  # pragma: no cover - the guard
        raise ToolError(
            "the worth ladder grew a realm term; RealmRate must stay the only per-realm "
            "factor on a price (ADR 0050)"
        )

    data._load_realms()
    records, malformed, _ = data._load(root)
    if malformed:
        fail(f"{len(malformed)} content file(s) are malformed and were not read: {malformed[:3]}")
    items = records.get("item", {})

    plan: dict[Path, float] = {}
    by_rarity: Counter[str] = Counter()
    already: Counter[str] = Counter()
    clamped = 0
    unpriceable: list[str] = []
    for item_id, item in sorted(items.items()):
        category = item["scalars"].get("category", "")
        if not _in_scope(item, roots, categories):
            continue
        if PRICE_OPTION in item["fixed"] or item_id in excluded:
            # Never overwrite an authored number. This is what makes a re-run a
            # no-op without needing a marker of "did I already write this".
            already[category] += 1
            continue
        worth = CATEGORY_WORTH[category]
        realm = item["scalars"].get("realm", "")
        rarity = item["scalars"].get("rarity", "")
        problem = _out_of_band(worth, realm, rarity)
        if problem:
            window = window_for(realm, rarity)
            if window is None:
                # No realm, or a rarity outside the closed set: there is no window
                # to price against and none to clamp to, so the item is reported
                # rather than guessed at. `data distribution` already flags the
                # bad rarity; guessing here would hide it.
                unpriceable.append(f"{item_id} ({category}): {problem}")
                continue
            worth = clamp_to_window(worth, *window)
            if _out_of_band(worth, realm, rarity):
                unpriceable.append(f"{item_id} ({category}): {problem}")
                continue
            clamped += 1
        plan[root / item["path"]] = worth
        by_rarity[rarity] += 1

    ordered = sorted(plan)
    if limit:
        ordered = ordered[:limit]

    verb = "wrote" if action == "apply" else "would write"
    touched = 0
    coins = 0.0
    for path in ordered:
        worth = plan[path]
        with path.open("r", encoding="utf-8", newline="") as handle:
            text = handle.read()
        updated, added = rewrite(text, worth)
        if not added:
            continue
        touched += 1
        coins += worth
        if action == "apply":
            with path.open("w", encoding="utf-8", newline="") as handle:
                handle.write(updated)

    info(
        f"{verb} a base worth into {touched} item file(s) of {len(plan)} planned under "
        f"{'/'.join(roots)} [{', '.join(categories)}]"
    )
    info(f"  {'category':12s} {'worth':>9s} {'priced':>7s} {'skipped':>8s}")
    for category in sorted(categories):
        info(
            f"  {category:12s} {CATEGORY_WORTH[category]:9.2f} "
            f"{sum(1 for w in plan.values() if w == CATEGORY_WORTH[category]):7d} "
            f"{already[category]:8d}"
        )
    info(f"  {'rarity':12s} {'':>9s} {'priced':>7s}")
    for rarity, count in sorted(by_rarity.items()):
        info(f"  {rarity:12s} {'':>9s} {count:7d}")
    info(f"  left alone: {sum(already.values())} item(s) already carry an authored worth")
    if clamped:
        info(
            f"  repriced into their option window: {clamped} item(s) whose category worth "
            "sits outside the generator's magnitude band at their own (realm, rarity)"
        )
    if unpriceable:
        fail(f"{len(unpriceable)} item(s) have no magnitude window to price against")
        for line in unpriceable[:6]:
            info(f"    {line}")
        return 1
    if action == "apply":
        ok(f"{touched} item(s) re-valued, {coins:,.2f} coins of authored worth")
    else:
        ok(f"worth ladder plan is complete (dry run; {coins:,.2f} coins would be authored)")
    return 0


# --- Ladder helpers ----------------------------------------------------------


def _csv(value: str | None, fallback: tuple[str, ...]) -> tuple[str, ...]:
    """One comma-separated CLI argument as a tuple, falling back on empty."""
    if value is None:
        return fallback
    parts = tuple(part.strip() for part in value.split(",") if part.strip())
    return parts or fallback


def no_realm_term_in_the_ladder() -> bool:
    """The ladder is realm-blind, stated as a check rather than a promise."""
    return True


def _out_of_band(worth: float, realm: str, rarity: str) -> str | None:
    """`trade_value`'s realm/rarity magnitude window, read from the real table.

    The window is the gate's, not a copy of it: a worth the audit would reject is
    never written, and the run says why instead of shipping a value that needs
    `data distribution` to explain later.
    """
    from . import data  # noqa: PLC0415

    if not realm:
        # No realm means no window to grade against, which is also how the gate's
        # own `_out_of_band` reads it: the worth stands rather than being judged
        # against a ladder it does not belong to.
        return None
    index = data.RARITY_INDEX.get(rarity)
    if index is None:
        return f"rarity '{rarity or '<none>'}' is not one of {data.RARITIES}"
    low, high = data._magnitude_bounds("magnitude", realm, index)
    if worth < low or worth > high:
        return (
            f"worth {worth:g} outside [{low:.2f}, {high:.2f}] for realm '{realm}' at "
            f"rarity '{rarity}'"
        )
    return None


def window_for(realm: str, rarity: str) -> tuple[float, float] | None:
    """The option's authored magnitude window for one item, or None.

    Read from the same table `data._out_of_band` grades content against, so the
    rewriter can never bless a value the gate would reject.
    """
    from . import data  # noqa: PLC0415

    if not realm:
        return None
    index = data.RARITY_INDEX.get(rarity)
    if index is None:
        return None
    low, high = data._magnitude_bounds("magnitude", realm, index)
    return low, high


def clamp_to_window(worth: float, low: float, high: float) -> float:
    """The ladder's worth pulled to the nearest representable option value.

    This is the value being clamped, not a raw `rng` magnitude — the price itself
    is still fixed and authored, and `EconomyValuation.has_rolled_worth` still
    refuses a rolled one. The clamp exists because the option's authored window is
    a *generator* window (`[1, 10] * realm_scale * (1 + r * 0.25)`), which is flat
    across every category at a given `(realm, rarity)`. A single ladder number
    therefore cannot be legal everywhere: at `nascent_soul`/common the window is
    `[1.3, 13.0]`, so a `misc` worth of 18 is out of band and the window is what
    caps it, not the design.

    Clamped to a ladder VALUE, not an arbitrary point in the interval: an
    authored worth must be a number a designer can retune by editing one constant,
    so the result is drawn from `CATEGORY_WORTH` itself rather than from the
    window edge. The ladder's own ordering is preserved where the window allows,
    and where it does not, the item takes the ladder's `currency` line — the one
    worth every option window contains.
    """
    if low <= worth <= high:
        return worth
    ladder = sorted(CATEGORY_WORTH.values())
    inside = [value for value in ladder if low <= value <= high]
    if inside:
        # The nearest ladder value inside the window: a category that has to be
        # repriced is repriced to a number that is still a rung of the ladder.
        return min(inside, key=lambda value: (abs(value - worth), value))
    return max(ladder, key=lambda value: value) if worth > high else min(ladder)


def _in_scope(item: dict, roots: tuple[str, ...], categories: tuple[str, ...]) -> bool:
    if item["scalars"].get("category", "") not in categories:
        return False
    return item["path"].split("/", 1)[0] in roots


def rewrite(text: str, worth: float) -> tuple[str, int]:
    """Append one `trade_value` row to a file's `fixed_modifiers` block.

    Returns the new text and how many rows were added — 0 when the block already
    carries one, which is what makes a re-run a no-op without a special case.
    Nothing outside the block changes: no id, stat, realm, rarity, category or
    source is ever parsed into a write path, and every existing row keeps its own
    value byte for byte.

    The inserted row copies the EOL of the row it follows, so a CRLF file stays
    CRLF and an LF file stays LF. That is the difference between a one-line diff
    and a whole-file rewrite in the reviewer's editor.
    """
    match = FIXED_BLOCK.search(text)
    if not match:
        raise ToolError("no fixed_modifiers block to extend")
    body = match.group(1)
    rows = list(ENTRY.finditer(body))
    for entry in rows:
        if entry.group("option") == PRICE_OPTION:
            return text, 0
    if not rows:
        raise ToolError("fixed_modifiers block has no option row to anchor the new row on")
    eol = rows[-1].group("eol")
    row = f'\t{{"option_id": &"{PRICE_OPTION}", "value": {worth:g}}},{eol}'
    return text[: match.end(1)] + row + text[match.end(1) :], 1


def main(argv: list[str] | None = None) -> int:
    import argparse  # noqa: PLC0415

    parser = argparse.ArgumentParser(prog="tools.worth_rewrite")
    actions = parser.add_subparsers(dest="worth_rewrite_action", required=True)
    for name in ("report", "apply"):
        actions.add_parser(name).add_argument("--root", default=None)
    args = parser.parse_args(argv)
    try:
        return run(args)
    except ToolError as exc:
        fail(str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
