"""`uv run python -m tools element_coverage` — every element's coverage, or a non-zero exit.

## The gap this exists to close

`ElementStats` declares ten elements (`modules/elements/stats.gd:20-21`), and `StatusDef`
restates them (`modules/status/status_def.gd:62-79`). Each element ships two authored
statuses and they are all reachable — but "the element has authored counterplay GEAR"
was true of only SEVEN of the ten. `wind`, `light` and `dark` had statuses a player
could suffer and no authored `element_defense_<e>` item to answer with, and nothing
in the tree failed: `data audit` checks that an item's fixed option exists and is
in-window, never that every element HAS such an item. A gap that no gate names is a gap
that ships.

## What is asserted, for every element, and why each one is a separate claim

1. **Declared** — the element is in `ElementStats.BASE_ELEMENTS` +
   `ADVANCED_ELEMENTS` + `TIER_THREE_ELEMENTS`, and in `StatusDef.AUTHORED_ELEMENTS`.
2. **SSOT row** — exactly one `game/data/elements/element-coverage.jsonl` record, and
   that record names no element the element table does not have.
3. **Two authored statuses** — exactly two `.tres` under `game/data/statuses/` declare
   `element = <e>`, and the SSOT names the same two ids. A third is a gap the claim does
   not cover; a different pair is a drift between the record and the content. A TIER-3
   element (ADR 0925) ships its SINGLE combat expression instead: the triad's pair rule
   is the ADR's, and the blessing package it does not yet ship is tracked rather than
   silently absent.
4. **Status files exist and parse** — each id resolves to a real file whose declared
   `id` and `element` match, so a rename cannot leave the record naming a ghost.
5. **Statuses are reachable through a shipped producer** — a COMBAT-scope status needs
   `on_landed_blow = true` (`StatusApi.status_for_element` only ever answers one of
   those), and a CULTIVATION-scope status needs a `TribulationBlessing.REWARD_TABLE` row
   naming its element (`TribulationBlessing.award` is its only production payer). Both
   are read out of `game/src`, not out of the SSOT, so a producer deleted in code fails
   here even with a perfectly consistent record.
6. **An authored, obtainable ward** (tiers 1-2) — an item carries
   `element_defense_<e>` in `fixed_modifiers`, its declared realm/rarity are on the
   realm ladder with a rarity the audit knows, and its magnitude is inside the option's
   own realm/rarity window (`data._magnitude_bounds`, the same numbers `tools data
   audit` gates on). Obtainability is measured through `tools acquisition`'s graph: the
   item must resolve through a declared source whose whole craft chain terminates at a
   `gather`/`boss`/`domain` route. An authored-but-unreachable ward is exactly the
   "obtainable" claim failing.
7. **A craftable recipe** (tiers 1-2) — the SSOT's `ward_recipe` exists, and it names
   the element's ward in `outputs` and a `station`, with inputs that are themselves
   resolvable.

## Why the expected set is derived, never pinned

A pinned literal list is the ADR 0066 failure mode: a new element added to
`ElementStats` would fail a guard that enumerates the old ten (now thirteen), and the
natural response would be to edit the literal — which is precisely how a coverage claim
stops covering. Every element under test comes from the ELEMENT TABLE, so joining is
automatic and the only way to make this go red is to genuinely drop coverage.

## Where the numbers live

Nothing a balance pass tunes is a literal here. The ward magnitudes are in the
`.tres`; the realm/rarity magnitude curve is `game/data/item_options/
item_magnitude_scale.json` through `options.MAGNITUDE_POLICY`; the divisor a
resistance is read against is `combat_damage.tres`. This module reads all three.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from .common import GAME_DIR, REPO_ROOT, ToolError, fail, info, ok

SSOT_RELATIVE = Path("data") / "elements" / "element-coverage.jsonl"
STATUSES_RELATIVE = Path("data") / "statuses"
ITEMS_RELATIVE = Path("data") / "items"
RECIPES_RELATIVE = Path("data") / "recipes"
ELEMENT_STATS_RELATIVE = Path("src") / "modules" / "elements" / "stats.gd"
STATUS_DEF_RELATIVE = Path("src") / "modules" / "status" / "status_def.gd"
BLESSING_RELATIVE = Path("src") / "modules" / "status" / "tribulation_blessing.gd"
BOSSES_RELATIVE = Path("data") / "bosses"

# Every `.tres` field this reads is a plain `key = &"value"` or `key = value` scalar,
# so one parser serves all of them. `newline=""` because the corpus is not uniformly
# CRLF and a value rewrite must not restate a file's line endings.
SCALAR = re.compile(r"^(?P<key>[a-z_0-9]+) = (?P<value>.*)$", re.M)
STRINGNAME_ARRAY = re.compile(r"Array\[StringName\]\(\[(?P<body>.*?)\]\)", re.S)
DEFENSE_ENTRY = re.compile(
    r'\{"option_id": &"(?P<option>element_defense_[a-z_0-9]+)", "value": (?P<value>-?[\d.]+)'
)

# A production route that terminates a craft chain: the three `ItemSources` kinds a
# player reaches without another recipe. Anything else is a link, not an end.
TERMINAL_ROUTE_KINDS = ("gather", "boss", "domain")


class CoverageError(Exception):
    """One unmet assertion, carried with the element it is about."""


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "element_coverage",
        help="assert every element ships its statuses, producers and an obtainable ward",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print the per-element verdict as JSON instead of a table",
    )


# --- reading the tree ----------------------------------------------------------


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _scalars(text: str) -> dict[str, str]:
    """Every top-level `key = value` in a `.tres`, unquoted."""
    out: dict[str, str] = {}
    for match in SCALAR.finditer(text):
        value = match.group("value").strip()
        if value.startswith('&"') and value.endswith('"'):
            value = value[2:-1]
        out[match.group("key")] = value
    return out


def _stringnames(text: str, key: str) -> tuple[str, ...]:
    """The `&"..."` entries of `Array[StringName]` under `key`."""
    match = re.search(r"^" + key + r" = Array\[StringName\]\(\[(.*?)\]\)", text, re.M | re.S)
    return tuple(re.findall(r'&"([^"]+)"', match.group(1))) if match else ()


def _gd_literal_consts(text: str, const_name: str) -> tuple[str, ...]:
    """The `&"..."` values of a GDScript constant that composes literal arrays.

    `status_def.gd` declares `AUTHORED_ELEMENTS = TIER_ONE_ELEMENTS + TIER_TWO_ELEMENTS
    + TIER_THREE_ELEMENTS` (the third added by ADR 0925), so the name itself holds no
    literals. Reading only its own bracket would yield zero and call every element
    un-authored; the set is the union of the arrays it adds.

    The right-hand side is read to the END OF ITS STATEMENT, not to the first newline
    or the first blank line: a formatter may wrap a long sum inside parentheses, and
    the next `const` may follow without a blank line between them (so a blank-line
    terminator over-reads and resolves consts that are not part of this one).
    """
    head = re.search(r"const " + const_name + r"\s*:?[^=\n]*=\s*", text)
    if not head:
        return ()
    rest = text[head.end() :]
    if rest.startswith("("):
        depth = 0
        end = 0
        for index, char in enumerate(rest):
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        rhs = rest[:end]
    else:
        rhs = rest.split("\n", 1)[0]
    parts = re.findall(r"[A-Z_][A-Z0-9_]*", rhs)
    out: list[str] = []
    for part in parts:
        body = re.search(r"const " + part + r"\s*:?[^=\n]*=\s*\[(.*?)\]", text, re.S)
        if body:
            out.extend(re.findall(r'&"([^"]+)"', body.group(1)))
    return tuple(out)


def _gd_bare_consts(text: str, const_name: str) -> tuple[str, ...]:
    """The `&"..."` values of a GDScript `const NAME: Array[StringName] = [A, B, C]`.

    `elements/stats.gd` names each element as its own `const METAL := &"metal"` and then
    lists them by CONSTANT REFERENCE (`BASE_ELEMENTS = [METAL, WOOD, ...]`), so a regex
    over `&"..."` inside the bracket finds nothing and the tool would read ZERO elements
    and then call all ten authored rows orphans. Resolving the references through their
    own single-line declarations is the reading that matches the shipped shape.
    """
    match = re.search(r"const " + const_name + r"\s*:?[^=\n]*=\s*\[([^\]]*)\]", text)
    if not match:
        return ()
    out: list[str] = []
    for name in (token.strip() for token in match.group(1).split(",")):
        if not name:
            continue
        # `\\b` is load-bearing: without it `LIGHT` resolves inside `LIGHTNING`, because
        # `[^=\n]*` happily swallows "NING " and the guard then reads ten elements as nine
        # with a duplicate, silently dropping `light` from the table it claims to enforce.
        literal = re.search(
            r"^const\s+" + re.escape(name) + r"\b\s*:?[^=\n]*:=\s*&\"([^\"]+)\"",
            text,
            re.M,
        )
        if literal is None:
            raise ToolError(f'{const_name} lists {name}, which is not a declared &"..." constant')
        out.append(literal.group(1))
    return tuple(out)


def authored_elements() -> tuple[
    tuple[str, ...], tuple[str, ...], tuple[str, ...], tuple[str, ...]
]:
    """`(base, advanced, tier_three, status_def)` element lists, read from GDScript.

    The element table is the ONE place the expected set comes from. It is read rather
    than imported because `tools/` is outside `res://` and GDScript must never import
    from it (AGENTS.md:130); a regex over the declared constants is the reading that
    cannot silently return an empty set, because an empty read fails the "elements
    are declared" assertion below rather than making every later loop vacuous.
    """
    stats = _read(GAME_DIR / ELEMENT_STATS_RELATIVE)
    base = _gd_bare_consts(stats, "BASE_ELEMENTS")
    advanced = _gd_bare_consts(stats, "ADVANCED_ELEMENTS")
    tier_three = _gd_bare_consts(stats, "TIER_THREE_ELEMENTS")
    declared = _gd_literal_consts(_read(GAME_DIR / STATUS_DEF_RELATIVE), "AUTHORED_ELEMENTS")
    return base, advanced, tier_three, declared


def blessing_elements() -> tuple[str, ...]:
    """Every element a producer row can pay.

    TWO tables since ADR 0920: `TribulationBlessing.REWARD_TABLE` (a survived trial)
    and `DOMAIN_TABLE` (a cleared elemental domain). Both are read from source, so a
    table that stops naming an element fails this check rather than reading as a
    prose claim nothing verifies.
    """
    text = _read(GAME_DIR / BLESSING_RELATIVE)
    out: list[str] = []
    for name in ("REWARD_TABLE", "DOMAIN_TABLE"):
        match = re.search(rf"const {name}: Dictionary = \{{(.*?)\n\}}", text, re.S)
        if match:
            out.extend(re.findall(r'&"([^"]+)"', match.group(1)))
    return tuple(out)


def boss_afflictions() -> tuple[str, ...]:
    """Every status id a shipped `BossDef.affliction` can pay.

    The THIRD producer. `combat/exchange.gd:_boss_affliction_numbers` reads this field
    and `loot/loot_affliction.gd` gates it on a real roll, so a status named here is
    reachable in production exactly as a landed-blow status is. Without this reader a
    status reachable ONLY as an affliction looks unreachable, and the guard would demand
    a second landed-blow claimer — which ADR 0105 forbids.
    """
    out: list[str] = []
    for path in sorted((GAME_DIR / BOSSES_RELATIVE).rglob("*.tres")):
        match = re.search(r"^affliction = &\"([^\"]+)\"", _read(path), re.M)
        if match:
            out.append(match.group(1))
    return tuple(out)


def load_ssot(path: Path) -> list[dict]:
    if not path.is_file():
        raise ToolError(f"{path.relative_to(REPO_ROOT).as_posix()} is missing")
    rows: list[dict] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError as exc:
            raise ToolError(f"{path.name}:{number}: malformed JSON ({exc})") from None
    return rows


def status_defs() -> dict[str, dict]:
    """Every `.tres` under `game/data/statuses/`, keyed by its declared `id`."""
    root = GAME_DIR / STATUSES_RELATIVE
    out: dict[str, dict] = {}
    for path in sorted(root.glob("*.tres")):
        text = _read(path)
        scalars = _scalars(text)
        status_id = scalars.get("id") or path.stem
        out[status_id] = {
            "id": status_id,
            "element": scalars.get("element", ""),
            "scope": scalars.get("scope", ""),
            "landed": scalars.get("on_landed_blow", "false") == "true",
            "mitigation_tags": _stringnames(text, "mitigation_tags"),
            "path": path,
        }
    return out


def _is_ward(record: dict) -> bool:
    """Whether this record is a purpose-built ward item rather than an incidental grant."""
    return str(record.get("item", "")).startswith("ward_")


def defense_items() -> dict[str, dict]:
    """Every item carrying an `element_defense_<e>` fixed modifier, keyed by element.

    SEVERAL items may grant the same element's defense: `tide_vault_hoard_of_shells`
    grants ice alongside `ward_ice_ward`, and that is legitimate — an element with exactly
    one counterplay source is under-served content, not a correct one. The guard is that at
    least one EXISTS and is obtainable, so this returns the first in sorted order and records
    every other carrier in `also`, which the report prints so a reader can see the whole set.
    """
    root = GAME_DIR / ITEMS_RELATIVE
    out: dict[str, dict] = {}
    for path in sorted(root.rglob("*.tres")):
        text = _read(path)
        for match in DEFENSE_ENTRY.finditer(text):
            option = match.group("option")
            element = option[len("element_defense_") :]
            scalars = _scalars(text)
            record = {
                "element": element,
                "option": option,
                "value": float(match.group("value")),
                "item": scalars.get("id", path.stem),
                "realm": scalars.get("realm", ""),
                "rarity": scalars.get("rarity", ""),
                "sources": _stringnames(text, "sources"),
                "path": path,
            }
            if element in out:
                # Keep the item the SSOT row names as THE ward. A boss incidental that
                # also grants this element must not displace the purpose-built ward, which
                # is the one carrying the recipe and the magnitude window — so a `ward_`
                # item always outranks a non-ward, and among wards the name decides.
                primary = out[element]
                if _is_ward(record) and not _is_ward(primary):
                    primary["also"].append(record)
                    out[element] = record
                elif _is_ward(record) == _is_ward(primary) and record["item"] < primary["item"]:
                    primary["also"].append(record)
                    out[element] = record
                else:
                    primary["also"].append(record)
                continue
            record["also"] = []
            out[element] = record
    return out


def recipe_defs() -> dict[str, dict]:
    """Every recipe under `game/data/recipes/`, keyed by its declared `id`."""
    root = GAME_DIR / RECIPES_RELATIVE
    out: dict[str, dict] = {}
    for path in sorted(root.glob("*.tres")):
        text = _read(path)
        scalars = _scalars(text)
        recipe_id = scalars.get("id") or path.stem
        out[recipe_id] = {
            "id": recipe_id,
            "station": scalars.get("station", ""),
            "inputs": _stringnames(text, "inputs"),
            "outputs": _stringnames(text, "outputs"),
            "path": path,
        }
    return out


# --- obtainability --------------------------------------------------------------


def _acquisition_graph():
    """The acquisition graph, loaded lazily so `--help` and a parse error stay cheap."""
    from .acquisition.chain import Graph  # noqa: PLC0415

    return Graph()


def _resolves_to_a_terminal_route(graph, item_id: str, _depth: int = 0) -> bool:
    """Whether `item_id` is obtainable in the shipped content graph.

    Walks the authored `sources` of an item: a `gather`/`boss`/`domain` route ENDS the
    walk because a player reaches it without another recipe, and a `craft:` route
    continues into its recipe's inputs. `DEPTH_CAP` bounds the walk — the `craft:`
    graph is asserted acyclic by `tools acquisition validate`, but a graph that grew a
    cycle must FAIL rather than spin, so the cap is a real termination guard and the
    cap being hit is reported as unresolved rather than swallowed.
    """
    if _depth > 24:
        return False
    for source in graph.item_sources(item_id):
        kind, _, ref = source.partition(":")
        if kind in TERMINAL_ROUTE_KINDS and ref:
            return True
        if kind == "craft" and ref:
            for reagent in graph._reagents(ref):  # noqa: SLF001 - the graph's own walk
                if _resolves_to_a_terminal_route(graph, reagent, _depth + 1):
                    return True
    return False


# --- the assertions -------------------------------------------------------------


def check_element(element: str, row: dict | None, tree: dict) -> dict:
    """Every assertion for one element, as data. Raises `CoverageError` on the first."""
    findings: list[str] = []
    verdict = {
        "element": element,
        "statuses": [],
        "reachable": [],
        "ward": None,
        "obtainable": False,
    }

    def require(condition: bool, message: str) -> None:
        if not condition:
            raise CoverageError(f"{element}: {message}")

    # 1. declared
    require(element in tree["status_def_elements"], "not in StatusDef.AUTHORED_ELEMENTS")
    triad = element in tree["tier_three"]
    verdict["tier"] = 3 if triad else (1 if element in tree["base"] else 2)

    # 2. SSOT row
    require(row is not None, "has no row in element-coverage.jsonl")
    require(row.get("id") == element, f"row declares id {row.get('id')!r}")
    if triad:
        # ADR 0925: the triad's package is its single combat status. The ward, its
        # recipe and the blessing are tiers-1-2 claims; extending them to tier 3 is
        # tracked rather than silently demanded or silently skipped.
        for field in ("statuses", "combat_status"):
            require(field in row, f"row has no {field!r} field")
    else:
        expected_option = f"element_defense_{element}"
        require(
            row.get("defense_option") == expected_option,
            f"row names defense option {row.get('defense_option')!r}, expected {expected_option!r}",
        )
        for field in (
            "statuses",
            "combat_status",
            "cultivation_status",
            "ward_item",
            "ward_recipe",
        ):
            require(field in row, f"row has no {field!r} field")

    # 3. the element's pair plus at most one blessing, and the row names them all
    authored = sorted(
        status_id for status_id, def_ in tree["statuses"].items() if def_["element"] == element
    )
    verdict["statuses"] = authored
    if triad:
        require(
            len(authored) == 1,
            f"has {len(authored)} authored status(es) {authored}; the triad ships one "
            f"combat expression (ADR 0925)",
        )
    else:
        require(
            2 <= len(authored) <= 3,
            f"has {len(authored)} authored status(es) {authored}, expected its pair plus at most "
            f"one blessing (ADR 0920)",
        )
    declared = sorted(str(status_id) for status_id in row["statuses"])
    require(
        declared == authored,
        f"row names statuses {declared} but the content ships {authored}",
    )

    # 4. the status files exist and say what the row says
    for status_id in authored:
        def_ = tree["statuses"][status_id]
        require(
            def_["path"].is_file(),
            f"status {status_id} resolves to a file that is not there",
        )
        require(
            def_["scope"] in {"combat", "cultivation"},
            f"status {status_id} declares scope {def_['scope']!r}",
        )

    # 5. reachable through a SHIPPED producer
    combat = [s for s in authored if tree["statuses"][s]["scope"] == "combat"]
    cultivation = [s for s in authored if tree["statuses"][s]["scope"] == "cultivation"]
    require(bool(combat), "ships no COMBAT-scope status, so no landed blow can inflict one")
    if triad:
        # ADR 0925: the triad ships no blessing yet; the package is tracked.
        require(
            not cultivation,
            f"ships {sorted(cultivation)}; the triad ships no blessing in ADR 0925",
        )
    else:
        # ADR 0920: every element ships exactly ONE blessing, and the row must name it.
        require(cultivation, "ships no CULTIVATION-scope blessing (ADR 0920)")
        require(
            len(cultivation) == 1,
            f"ships {len(cultivation)} cultivation defs {cultivation}; exactly one blessing",
        )
        row_cultivation_named = str(row["cultivation_status"] or "")
        require(
            bool(row_cultivation_named),
            "leaves cultivation_status empty; every element ships one (ADR 0920)",
        )
    # ADR 0105: a blow carries ONE element and every element ships TWO combat defs, so
    # EXACTLY ONE of the pair may claim `on_landed_blow`. StatusCatalog refuses a second
    # claimer at load rather than tie-breaking on catalogue order, so demanding that
    # every combat status claim the blow would assert the opposite of the design.
    landed = [s for s in combat if tree["statuses"][s]["landed"]]
    require(
        len(landed) == 1,
        f"has {len(landed)} statuses claiming the landed blow ({', '.join(landed) or 'none'}); "
        f"ADR 0105 requires exactly one, since a blow carries one element",
    )
    if cultivation:
        require(
            element in tree["blessing_elements"],
            f"ships a cultivation status but no producer row (TribulationBlessing."
            f"REWARD_TABLE or DOMAIN_TABLE) names {element}, so nothing ever pays it",
        )
    afflictions = tree["boss_afflictions"]
    verdict["reachable"] = sorted(
        s for s in combat if tree["statuses"][s]["landed"] or s in afflictions
    ) + sorted(cultivation)
    require(
        len(verdict["reachable"]) >= (1 if triad else 2),
        f"only {len(verdict['reachable'])} of its {len(authored)} statuses have a "
        f"shipped producer: {authored}",
    )
    row_combat = str(row["combat_status"])
    require(
        row_combat in authored,
        f"row names combat_status {row_combat!r}, which the content does not ship",
    )
    require(
        tree["statuses"][row_combat]["landed"],
        f"row names combat_status {row_combat!r}, which does not claim the landed blow",
    )
    row_cultivation = str(row.get("cultivation_status") or "")
    if row_cultivation:
        require(
            row_cultivation in cultivation,
            f"row names cultivation_status {row_cultivation!r}, which is not a "
            f"cultivation-scope status on {element}",
        )
    else:
        require(
            not cultivation,
            f"row leaves cultivation_status empty but {sorted(cultivation)} ship(s) one",
        )

    # 6. an authored ward, in-window
    if triad:
        # The triad's package ends at its combat status (ADR 0925): no ward, no recipe,
        # no obtainability claim to make yet.
        if findings:
            raise CoverageError("; ".join(findings))
        return verdict
    ward = tree["defense_items"].get(element)
    require(
        ward is not None,
        f"has no authored item carrying {expected_option} in fixed_modifiers",
    )
    assert ward is not None
    verdict["ward"] = ward["item"]
    verdict["ward_value"] = ward["value"]
    require(
        ward["item"] == row["ward_item"],
        f"row names ward_item {row['ward_item']!r} but the authored ward is {ward['item']!r}",
    )
    require(
        ward["option"] in tree["catalog"],
        f"the option catalog has no record for {ward['option']}",
    )
    record = tree["catalog"][ward["option"]]
    require(
        record.get("status") == "active",
        f"option {ward['option']} is {record.get('status')!r}, not active",
    )
    require(ward["value"] > 0.0, f"ward {ward['item']} authors a non-positive value")
    window = tree["magnitude_window"](record["unit"], ward["realm"], ward["rarity"])
    if window is None:
        require(False, f"ward {ward['item']} declares realm/rarity the window cannot grade")
    low, high = window
    require(
        low <= ward["value"] <= high,
        f"ward {ward['item']} authors {ward['value']:g}, outside its own "
        f"{record['unit']} window [{low:g}, {high:g}] at {ward['realm']}/{ward['rarity']}",
    )

    # 7. a craftable recipe whose whole chain terminates
    recipe_id = str(row["ward_recipe"])
    recipe = tree["recipes"].get(recipe_id)
    require(recipe is not None, f"row names recipe {recipe_id!r}, which does not exist")
    assert recipe is not None
    require(bool(recipe["station"]), f"recipe {recipe_id} declares no station")
    require(
        ward["item"] in recipe["outputs"],
        f"recipe {recipe_id} outputs {list(recipe['outputs'])}, not {ward['item']!r}",
    )
    require(
        f"craft:{recipe_id}" in ward["sources"],
        f"ward {ward['item']} sources are {list(ward['sources'])}, missing craft:{recipe_id}",
    )
    for reagent in recipe["inputs"]:
        require(reagent in tree["items_by_id"], f"recipe {recipe_id} inputs unknown {reagent!r}")
        require(
            _resolves_to_a_terminal_route(tree["graph"], reagent),
            f"recipe {recipe_id} input {reagent!r} resolves to no {TERMINAL_ROUTE_KINDS} route",
        )
    verdict["obtainable"] = _resolves_to_a_terminal_route(tree["graph"], ward["item"])
    require(
        verdict["obtainable"],
        f"ward {ward['item']} resolves to no {TERMINAL_ROUTE_KINDS} route in the "
        f"acquisition graph, so no player can hold it",
    )
    if findings:
        raise CoverageError("; ".join(findings))
    return verdict


def _magnitude_window(unit: str, realm: str, rarity: str) -> tuple[float, float] | None:
    """The option's realm/rarity magnitude window, or None when the tier is unknown."""
    from . import data  # noqa: PLC0415

    rarity_index = data.RARITY_INDEX.get(rarity)
    if rarity_index is None:
        return None
    data._load_realms()  # noqa: SLF001 - the ladder the audit itself loads
    if realm not in data.REALM_ORDER:
        return None
    return data._magnitude_bounds(unit, realm, rarity_index)


def _catalog() -> dict[str, dict]:
    from .options import DEFAULT_CATALOG, _load_jsonl  # noqa: PLC0415

    return {record["id"]: record for record in _load_jsonl(DEFAULT_CATALOG)}


def _items_by_id() -> dict[str, str]:
    root = GAME_DIR / ITEMS_RELATIVE
    out: dict[str, str] = {}
    for path in sorted(root.rglob("*.tres")):
        out.setdefault(_scalars(_read(path)).get("id", path.stem), path.as_posix())
    return out


def build_tree() -> dict:
    base, advanced, tier_three, status_def = authored_elements()
    return {
        "base": base,
        "advanced": advanced,
        "tier_three": tier_three,
        "status_def_elements": status_def,
        "blessing_elements": blessing_elements(),
        "boss_afflictions": boss_afflictions(),
        "statuses": status_defs(),
        "defense_items": defense_items(),
        "recipes": recipe_defs(),
        "catalog": _catalog(),
        "items_by_id": _items_by_id(),
        "graph": _acquisition_graph(),
        "magnitude_window": _magnitude_window,
    }


def audit(tree: dict | None = None) -> tuple[list[dict], list[str]]:
    """`(verdicts, problems)`. Never raises for an unmet assertion — collects them."""
    tree = tree if tree is not None else build_tree()
    problems: list[str] = []

    base, advanced, tier_three = tree["base"], tree["advanced"], tree["tier_three"]
    elements = list(base) + list(advanced) + list(tier_three)
    if not elements:
        problems.append("the element table declares no elements at all")
    if len(set(elements)) != len(elements):
        problems.append(f"the element table names a duplicate: {sorted(elements)}")
    for missing in sorted(set(tree["status_def_elements"]) - set(elements)):
        problems.append(
            f"{missing}: StatusDef.AUTHORED_ELEMENTS names it but the element table does not"
        )

    ssot = load_ssot(GAME_DIR / SSOT_RELATIVE)
    by_id: dict[str, dict] = {}
    for row in ssot:
        element = str(row.get("id", ""))
        if element in by_id:
            problems.append(f"{element}: element-coverage.jsonl has two rows for one element")
        by_id[element] = row
    for orphan in sorted(set(by_id) - set(elements)):
        problems.append(
            f"{orphan}: element-coverage.jsonl has a row for an element the table does not declare"
        )

    verdicts: list[dict] = []
    for element in elements:
        try:
            verdicts.append(check_element(element, by_id.get(element), tree))
        except CoverageError as exc:
            problems.append(str(exc))
    return verdicts, problems


def run(args) -> int:
    verdicts, problems = audit()
    elements = build_elements()

    if args.json:
        info(json.dumps({"verdicts": verdicts, "problems": problems}, indent=1))
    else:
        info(
            f"{'element':10s} {'tier':>4s} {'statuses':30s} {'reachable':30s} "
            f"{'ward':22s} {'defense':>7s} obtainable"
        )
        for verdict in verdicts:
            value = verdict.get("ward_value", "")
            info(
                "{:<10s} {:>4} {:<30s} {:<30s} {:<22s} {:>7s} {}".format(
                    verdict["element"],
                    verdict.get("tier", "?"),
                    ",".join(verdict["statuses"]),
                    ",".join(verdict["reachable"]),
                    verdict["ward"] or "-",
                    f"{value:g}" if isinstance(value, float) else "",
                    "yes" if verdict["obtainable"] else "no",
                )
            )
        info("")
        info(
            f"{len(verdicts)}/{len(elements)} element(s) fully covered: "
            f"{', '.join(sorted(v['element'] for v in verdicts))}"
        )

    for problem in problems:
        fail(f"element coverage: {problem}")
    if problems:
        fail(f"element coverage failed: {len(problems)} gap(s)")
        return 1
    ok("every element ships its statuses, producers, and a ward where the package owes one")
    return 0


def build_elements() -> tuple[str, ...]:
    """The expected element set, derived from the element table rather than pinned."""
    base, advanced, tier_three, _ = authored_elements()
    return tuple(base) + tuple(advanced) + tuple(tier_three)
