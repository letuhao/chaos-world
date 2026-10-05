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
this, and at what tier"** — and rarity is already a multiplier in the formula, so
folding rarity into the worth as well would square a term the formula owns. The
ladder therefore scales by **category and grade**, flat across rarity and realm.
See `CATEGORY_FLOOR`'s docstring for why a realm term here would be ADR 0050's
failure.

## What a worth may be READ from: fixed only, never rolled

`trade_value` is ROLLABLE. The catalog registers it with `"contexts":
["base", "prefix", "postfix"]` and it is a live member of every `property:*` roll
pool, so on a def whose own `roll_spec` names a context the rarity policy actually
chooses, the generator can realize a ROLLED worth. A rolled worth is an `rng`
draw: `EconomyValuation.base_worth_of` refuses it, and `has_rolled_worth` makes
`EconomyExchange` and `MarketApi` refuse to SETTLE the item at all. Authoring a
price onto such a def would turn a priced item into an unsellable one.

So this tool writes a worth **only onto a def that cannot roll one** — see
`ROLLABLE_CONTEXTS` for the exact, measured test — and reports every def it
refused rather than quietly skipping it.

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
- **Only a def that cannot roll a worth is written.** A `prefix`/`postfix` in its
  `roll_spec` is a refusal, counted and named, because a rolled worth makes the
  item unsettleable and a price nobody can pay is not a price.
- **Dry-run by default.** Writing requires the `apply` action.
- **Deterministic.** No `random`, no clock, no directory-order dependence: files
  are visited in sorted order and the ladder is a pure function of one item's
  `(category, grade)`.
- **Scope is explicit.** `--roots` names content roots, `--categories` names
  categories, and an unknown category is refused rather than defaulted.
"""

from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

from .common import ToolError, fail, info, ok

# --- The ladder --------------------------------------------------------------

## One base worth per item CATEGORY **and grade tier**.
##
## These are the numbers. They span 21x across the four categories, which is the
## whole budget a worth ladder gets: the formula's own rarity term is 4x and its
## realm term is under 2x, so the category term stays a *distinguishing* term
## rather than the dominant one, and no category's worth reads as a power
## statement.
##
## ## Why the ladder has a GRADE axis and not a rarity or realm axis
##
## `grade` is the item's authored tier placement (`mortal` -> `divine`), and it is
## the one tier field every def in the corpus carries. It is a ladder ON THE ITEM,
## not a lookup into another table, so authoring from it does not become the
## forbidden "derive a worth from rarity, realm, or another table".
##
## The two axes that are NOT folded in are exactly the two ADR 0094's formula
## already owns as multipliers:
##
##   rarity -> `RARITY_WEIGHT` 1.0 / 1.6 / 2.6 / 4.0
##   realm  -> `RealmRate.factor` `1.02^ordinal`, under 2x over thirty realms
##
## Squaring either into the authored term would mean a legendary item's price is
## decided by rarity twice. So within a grade the worth is FLAT, and grade only
## says *what tier of thing this is*.
##
## ## The ordering is "what does obtaining this cost", not "how strong is it",
## ## because a price is a cost and never a magnitude (ADR 0094):
##
##   currency     2 — a note or a token. The cheapest thing that exists, and the
##                  reason every other category is priced above it.
##   key          5 — a document that opens something. Priced for what it admits,
##                  not for the door.
##   misc         8 — an object with no use of its own, carried because someone
##                  wanted it. Deliberately above `currency`: no yield sets it.
##   quest       10 — a delivered consequence. Scales with what completing it
##                  cost, and it is never sold back — a shop's `buys` list is
##                  where that refusal is expressed (ADR 0100).
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
GRADE_ORDER: tuple[str, ...] = ("mortal", "spirit", "earth", "heaven", "immortal", "divine")

#: How each rung moves along its category's own rung. Every category uses the same
#: SHAPE, so an editor retunes a category by moving one number rather than
#: re-deriving six: the rungs are 1x, 1.6x, 2.1x, 2.7x, 3.4x, 4.2x of the
#: category's own floor. Those multipliers are deliberately close to (and under)
#: the formula's own 4x rarity span, so the grade axis never out-shouts it.
GRADE_MULTIPLIER: dict[str, float] = {
    "mortal": 1.0,
    "spirit": 1.6,
    "earth": 2.1,
    "heaven": 2.7,
    "immortal": 3.4,
    "divine": 4.2,
}

## Each category's FLOOR rung, i.e. what its `mortal` item is worth. The other
## five grades follow from `GRADE_MULTIPLIER`.
CATEGORY_FLOOR: dict[str, float] = {
    "currency": 2.0,
    "key": 5.0,
    "misc": 8.0,
    "quest": 10.0,
}

CATEGORY_WORTH: dict[str, float] = {
    category: {grade: floor * GRADE_MULTIPLIER[grade] for grade in GRADE_ORDER}
    for category, floor in CATEGORY_FLOOR.items()
}

## ## `base` is the context that makes a rolled worth POSSIBLE, and nothing else
##
## `ItemGenerator.roll` intersects the rarity policy's contexts with the def's own
## `roll_spec.contexts`:
##
##     chosen = ItemRarity.contexts(def.rarity) & def.roll_spec.contexts
##
## and `ItemRarity.POLICY` names only `prefix` and `postfix` for all four rarities
## (common -> [prefix]; magic/rare/legendary -> [prefix, postfix]). **`base` is
## never a chosen context.** So a def whose `roll_spec` names only `base` chooses
## nothing at all, `roll()` returns early, and `trade_value` cannot reach its
## `rolled` channel no matter the seed.
##
## That is the whole rule, and it is the same distinction `economy_valuation.gd`
## draws: `base_worth_of` reads `fixed_modifiers` and `has_rolled_worth` refuses
## anything in `rolled`. A def that names `prefix` or `postfix` has `trade_value`
## live in its `property:<context>` pool, so it CAN realize a rolled worth — and
## `EconomyExchange._plan` then refuses to settle the item by name
## (`no_settlement`), which would make an authored price into an unsellable one.
##
## Measured, not assumed: over all 680 already-priced defs, exactly the 231 `misc`
## defs (whose `roll_spec` is `{base, prefix}`) realize a rolled worth within 40
## seeds, and no `currency`/`key` def (`roll_spec` `{base}`) ever does.
ROLLABLE_CONTEXTS: frozenset[str] = frozenset({"prefix", "postfix"})

## `ItemRarity.POLICY`'s contexts, mirrored from `item_rarity.gd`. `base` is
## absent because the runtime never chooses it — that absence IS the rule.
RARITY_CONTEXTS: dict[str, frozenset[str]] = {
    "common": frozenset({"prefix"}),
    "magic": frozenset({"prefix", "postfix"}),
    "rare": frozenset({"prefix", "postfix"}),
    "legendary": frozenset({"prefix", "postfix"}),
}

## Content roots the wave may touch, relative to the data root.
DEFAULT_ROOTS: tuple[str, ...] = ("items",)

## ## The shipped wave, and what the census left
##
## The measured census (not the DEF-0128 title, which says 221/7945 and was stale
## by three waves) is **680 of 8060** defs carrying a fixed `trade_value`:
## `currency` 221, `key` 228, `misc` 231, and **`quest` 0 of 233**. `quest` is
## therefore the whole remaining honest slice, and it is legal on both counts:
##
##   - `trade_value`'s catalog record declares `categories: ["currency"]` and
##     `activations_for` derives the only channel it may be authored on as
##     `{"property"}`. `CATEGORY_ACTIVATION` maps `key`, `currency`, `quest` and
##     `misc` to `property`, and `material`, `consumable`, `technique` and
##     `equipment` to `crafted`/`consumed`/`equipped`/`learned`. Authoring
##     `trade_value` on a material — the obvious slice — is a MISACTIVATED row by
##     `data distribution`. So the ~7000 `material`/`consumable`/`equipment`/
##     `technique` defs are NOT authorable, and saying otherwise would be fiction.
##   - every `quest` def declares `roll_spec.contexts == ["base"]`, and `base` is
##     never a context `ItemRarity.POLICY` chooses, so a `quest` item can never
##     realize a ROLLED worth (see `ROLLABLE_CONTEXTS`).
##
## `key` stays in the default because 2 of its 230 defs are still unpriced (they
## are the only stragglers), and `currency`/`misc` are excluded because an
## authored number is never overwritten: naming them costs a full scan to change
## nothing. `misc` would in any case be refused outright — all 231 of its defs
## name `prefix`, so every one of them can roll a worth.
DEFAULT_CATEGORY_WAVE: tuple[str, ...] = ("key", "quest")

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
    by_grade: Counter[tuple[str, str]] = Counter()
    already: Counter[str] = Counter()
    clamped = 0
    unpriceable: list[str] = []
    rollable: list[str] = []
    for item_id, item in sorted(items.items()):
        category = item["scalars"].get("category", "")
        if not _in_scope(item, roots, categories):
            continue
        if PRICE_OPTION in item["fixed"] or item_id in excluded:
            # Never overwrite an authored number. This is what makes a re-run a
            # no-op without needing a marker of "did I already write this".
            already[category] += 1
            continue
        if can_roll_a_worth(item):
            # A def that can realize a ROLLED trade_value: writing a fixed worth
            # onto it does not make it priced, it makes it UNSETTLEABLE, because
            # `EconomyExchange._plan` and `MarketApi.list_lot` both refuse an
            # instance whose `has_rolled_worth` is true. Reported, never written.
            rollable.append(f"{item_id} ({category}): {item.get('roll_spec', {})}")
            continue
        worth = _worth_for(item)
        if worth is None:
            unpriceable.append(
                f"{item_id} ({category}): grade "
                f"'{item['scalars'].get('grade', '')}' is not on the ladder"
            )
            continue
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
        by_grade[(category, item["scalars"].get("grade", ""))] += 1

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
    info(f"  {'category':12s} {'floor':>9s} " + " ".join(f"{g[:4]:>6s}" for g in GRADE_ORDER))
    for category in sorted(categories):
        cells = " ".join(f"{CATEGORY_WORTH[category][grade]:6.1f}" for grade in GRADE_ORDER)
        info(f"  {category:12s} {CATEGORY_FLOOR[category]:9.2f} {cells}")
    info(f"  {'category/grade':20s} {'worth':>9s} {'priced':>7s}")
    for category, grade in sorted(by_grade):
        info(
            f"  {category + '/' + grade:20s} {CATEGORY_WORTH[category][grade]:9.2f} "
            f"{by_grade[(category, grade)]:7d}"
        )
    info(f"  left alone: {sum(already.values())} item(s) already carry an authored worth")
    if clamped:
        info(
            f"  repriced into their option window: {clamped} item(s) whose rung "
            "sits outside the generator's magnitude band at their own (realm, rarity)"
        )
    if rollable:
        info(
            f"  refused: {len(rollable)} item(s) name a rollable context, so a ROLLED "
            "worth is reachable on them and a fixed worth would make them unsettleable"
        )
        for line in rollable[:6]:
            info(f"    {line}")
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


def can_roll_a_worth(item: dict) -> bool:
    """True when `ItemGenerator.roll` can realize a ROLLED `trade_value` on `item`.

    The one place in this file that reads an item's `roll_spec`, and it reads it
    for the refusal rather than for the write. `ItemGenerator.roll` intersects the
    rarity policy's contexts with the def's own:

        chosen = ItemRarity.contexts(def.rarity) & def.roll_spec.contexts

    `ItemRarity.POLICY` names only `prefix` (common) and `prefix`/`postfix`
    (magic, rare, legendary) — **`base` is never chosen** — so a def whose
    `roll_spec` names only `base` chooses nothing, `roll()` returns early, and no
    seed can put a `trade_value` in `rolled`.

    A `prefix` or `postfix` in the spec means the option is live in that def's
    `property:<context>` pool. `trade_value`'s record lists all three contexts, so
    it is live there too, and it carries weight 3.0 out of a 15.0 family — it is
    a real candidate, not a formality. Measured: all 231 already-priced `misc`
    defs realize one within 40 seeds and no `currency`/`key` def does.
    """
    spec = item.get("roll_spec") or {}
    if not spec:
        # No roll channel at all: `ItemGenerator.roll` returns [] before it reads
        # a context, so nothing can roll.
        return False
    chosen = RARITY_CONTEXTS.get(item["scalars"].get("rarity", ""), {"prefix"}) & set(
        spec.get("contexts") or []
    )
    return bool(chosen & ROLLABLE_CONTEXTS)


def _worth_for(item: dict) -> float | None:
    """The ladder rung for one item: its category's worth at its own grade.

    Two inputs, both read off the item itself — never off a lookup into another
    table, and never off its rarity or realm, which ADR 0094's formula already
    owns as multipliers.
    """
    rungs = CATEGORY_WORTH.get(item["scalars"].get("category", ""))
    if rungs is None:
        return None
    return rungs.get(item["scalars"].get("grade", ""))


# --- Ladder helpers ----------------------------------------------------------


def _csv(value: str | None, fallback: tuple[str, ...]) -> tuple[str, ...]:
    """One comma-separated CLI argument as a tuple, falling back on empty."""
    if value is None:
        return fallback
    parts = tuple(part.strip() for part in value.split(",") if part.strip())
    return parts or fallback


def no_realm_term_in_the_ladder() -> bool:
    """The ladder is realm-blind AND rarity-blind, stated as a check.

    Not a promise: the rung table is built from two constants that have no realm
    and no rarity in them, and a rung can only exist for a grade in `GRADE_ORDER`.
    A realm term added later — a `realm_scale` multiplier, a per-realm dict — would
    have to name a realm somewhere in this module, so the assertion below is the
    cheap machine check that the table did not grow one.
    """
    rungs = [rung for rungs in CATEGORY_WORTH.values() for rung in rungs.values()]
    if not rungs:
        return False
    # Every rung must be a constant multiple of its category floor, and no rung may
    # depend on anything but the grade: the table has exactly len(GRADE_ORDER)
    # entries per category and the same six for each.
    for category, rungs_for_category in CATEGORY_WORTH.items():
        if set(rungs_for_category) != set(GRADE_ORDER):
            return False
        floor = CATEGORY_FLOOR[category]
        for grade, rung in rungs_for_category.items():
            if rung != floor * GRADE_MULTIPLIER[grade]:
                return False
    return all(rung > 0.0 for rung in rungs)


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
    across every category at a given `(realm, rarity)`. No ladder number can be
    legal everywhere: at `qi_refining`/common the window is `[1.00, 10.00]`, so a
    `quest` `divine` rung of 42 is out of band, and the window is what caps it, not
    the design.

    Clamped to a ladder VALUE, not an arbitrary point in the interval: an authored
    worth must be a number a designer can retune by editing one constant, so the
    result is drawn from `CATEGORY_WORTH` itself rather than from the window edge.
    The candidate pool is EVERY rung of EVERY category, so a clamp can step down
    the grade axis or across the category axis and still land on a number some
    designer's hand wrote.
    """
    if low <= worth <= high:
        return worth
    ladder = sorted({rung for rungs in CATEGORY_WORTH.values() for rung in rungs.values()})
    inside = [value for value in ladder if low <= value <= high]
    if inside:
        # The nearest ladder value inside the window: a rung that has to be
        # repriced is repriced to a number that is still a rung of the ladder.
        return min(inside, key=lambda value: (abs(value - worth), value))
    # No rung fits at all — the window is narrower than the ladder's whole span.
    # Take the nearest EDGE rather than inventing a value: an authored number that
    # no rung of the ladder contains is a number nobody chose.
    return high if worth > high else low


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
