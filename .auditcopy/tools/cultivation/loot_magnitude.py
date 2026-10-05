"""Which rung of the magnitude ladder a drop's PLACEMENT pays, and whether it is owed.

**This module measures PLACEMENT, not the runtime.** `payments()` derives a paid rung
by walking authored placement down the nesting chain from the band (`_walk`: `realm =
table_realm(...) or realm`) and never reads `loot_rewards.gd`. Every number it
prints is a statement about where entries SIT, and none is a statement about what a
player receives.

**ADR 0166's decision 1 has landed, so the runtime already pays the item's own rung.**
`LootRewards.contextualize` overrides rarity only and keeps `def.realm`, and
`ItemGenerator` hands `def.realm` to `OptionCatalog`, so a band no longer caps
magnitude at all. Every entry counted below is therefore a **placement census entry,
not a mis-paid drop**, and `--scope all` is permanently red on a number this module
cannot move. It is a census, not a work queue — and the count is not stable either,
because a content wave rewrites the tables it walks, so read `report` for the live
figure rather than any number written here. BL-0704 (the "unbuilt programme") and
BL-0765 (the "red gate, three findings") both rested on this number and are now
closed as superseded by ADR 0166.

What guards the landed decision is SOURCE, not a corpus scan, because once the change
is in, a corpus scan is trivially satisfied and before it, the same scan is red for
reasons that say nothing about the decision:

- `game/tests/modules/loot/test_loot_band_magnitude_ruling.gd` reads the source and
  pins the one-seam claim, `def.realm` as the magnitude, the resolver still reporting
  the band, and a CEILING on shipped pool tables so the rejected migration fails the
  build instead of quietly truncating 279 of 333 tables.
- `game/tests/modules/loot/test_loot_drop_pays_own_rung.gd` asserts the VALUE: a
  foreign band context leaves the item at its own rung, on the realized drop.

Both run in `tools test`, and `tools/check.py:113` runs `tools test`, so the mechanism
is already guarded inside the gate this module is one step of. ADR 0166's "Tool change
to build (**not built here**)" — `check --scope magnitude` — is therefore redundant
with a guard that runs, and is deliberately not built here; see [method check].

`item_magnitude_scale.json` is ONE per-realm table shared by every ladder (ADR 0050:
item magnitudes are not actor stats and deliberately differ), so the rung a reagent
owes is the `realm` on its own `ItemDef` and nothing else. That is still what
[method mispaid] compares placement against, and it is why a direct entry on a
foreign band is the shape to look for: a direct entry has no table of its own to
override the band, which is BL-0645.

A second finding is measured here and kept deliberately separate, because the two
were reported as one and are not: an item whose `realm` names a rung the scale table
has no row for is BL-0437's `qi_condensation` failure — a **missing key**, the
opposite failure from a wrong-rung payment, and one `options.load_scale` aborts on
before any of this runs. It is [method off_ladder], not [method mispaid].

## Actions

- `report` - every direct entry, what its placement pays, what its item owes, and
  which domain binds it.
- `check`  - non-zero when any exists inside `--scope` (`gate` by default, `all` for
  the whole corpus, which is red today and cannot be greened from this file).
- `fix`    - **REFUSED, unconditionally.** The placement migration it implemented is
  the alternative ADR 0166 rejected. See [method fix] for the four measured blockers
  and for why the refusal is a hard stop rather than a flag.
- `repair` - bring an `entries` array back to a loadable shape. `check` also asserts
  that shape ([method structural]), because `fix` used to splice refs and a defect it
  could introduce has to be one it could also see.
"""

from __future__ import annotations

import re
import time
from dataclasses import dataclass

from ..acquisition.chain import Graph, resource_scalar, scalar
from ..acquisition.loot import MAX_NESTING_DEPTH
from ..common import REPO_ROOT, ToolError, fail, info, ok
from ..options import load_scale

TABLE_DIR = REPO_ROOT / "game" / "data" / "loot" / "tables"
# `[sub_resource ...]` headers, as `chain.sub_resources` finds them but with the
# offsets a removal needs. `sub_resources` returns bodies only, and a fix has to
# excise exactly one of them from a file it must otherwise leave alone.
_BLOCK_HEAD = re.compile(r"(?m)^\[sub_resource[^\n]*\]\n?")
_MAIN_HEAD = re.compile(r"(?m)^\[resource\]")


@dataclass(frozen=True)
class Payment:
    """One direct item entry, and the rung the resolver will realize it at."""

    item_id: str
    item_realm: str
    paid_realm: str
    table_id: str
    entry_id: str
    quantity: int
    guaranteed: bool
    rarity_floor: str
    depth: int
    domain_id: str

    @property
    def key(self) -> tuple[str, str, str]:
        """Identity for dedupe: one entry seen through several bands is one payment."""
        return (self.item_id, self.table_id, self.entry_id)


@dataclass(frozen=True)
class Entry:
    """One authored `LootEntry`, as the fix needs to read it."""

    entry_id: str
    item_id: str
    table_id: str
    quantity: int
    quantity_max: int
    guaranteed: bool
    rarity_floor: str
    resource_id: str


# --- reading ------------------------------------------------------------------


def table_realm(graph: Graph, table_id: str) -> str:
    """A `LootTableDef.realm`, read off the `[resource]` block.

    `resource_scalar` rather than `scalar`: a `.tres` repeats field names across
    `sub_resource` blocks, and only the main block carries the id a reader addresses
    the file by.
    """
    record = graph.loot_tables.get(table_id)
    return resource_scalar(graph.read(record), "realm") if record else ""


def _blocks(text: str) -> list[tuple[str, str]]:
    """`(resource_id, block_text)` per `sub_resource`, in authored order.

    Split on the header, like `chain.sub_resources`, and bounded above by the
    `[resource]` block as well as by the next header — otherwise the LAST entry's
    span would swallow the main block and removing it would delete the table's id.
    """
    main = _MAIN_HEAD.search(text)
    limit = main.start() if main else len(text)
    heads = [match for match in _BLOCK_HEAD.finditer(text) if match.start() < limit]
    out: list[tuple[str, str]] = []
    for index, head in enumerate(heads):
        end = heads[index + 1].start() if index + 1 < len(heads) else limit
        resource_id = head.group(0).strip().rsplit('id="', 1)[-1].rstrip('"]')
        out.append((resource_id, text[head.start() : end]))
    return out


def _int(chunk: str, name: str, default: int) -> int:
    """One integer entry field, defaulted the way the runtime defaults it."""
    raw = scalar(chunk, name)
    return int(float(raw)) if raw else default


def entries(graph: Graph, table_id: str) -> list[Entry]:
    """Every authored entry of one table, in order.

    Read from the `sub_resource` blocks because `data.py`'s loot-table schema records
    what a table can produce but not which entry is `guaranteed`, and the guarantee is
    exactly what a fix must preserve.
    """
    record = graph.loot_tables.get(table_id)
    if record is None:
        return []
    out: list[Entry] = []
    for resource_id, block in _blocks(graph.read(record)):
        out.append(
            Entry(
                entry_id=scalar(block, "id"),
                item_id=scalar(block, "item_id"),
                table_id=scalar(block, "table_id"),
                quantity=_int(block, "quantity", 1),
                quantity_max=_int(block, "quantity_max", 0),
                guaranteed="guaranteed = true" in block,
                rarity_floor=scalar(block, "rarity_floor"),
                resource_id=resource_id,
            )
        )
    return out


# --- measuring ----------------------------------------------------------------


def _walk(
    graph: Graph,
    table_id: str,
    realm: str,
    domain_id: str,
    depth: int,
    out: list[Payment],
) -> None:
    """Record every direct item entry `table_id` can pay, at the rung it pays.

    `depth` is capped at `MAX_NESTING_DEPTH`, the resolver's own ceiling, so a
    cyclic table terminates here instead of recursing until the guard gives up. The
    cap is a bound, not a budget: `data audit` fails a cycle outright, so nothing
    legitimate ever reaches it.
    """
    if depth > MAX_NESTING_DEPTH:
        return
    record = graph.loot_tables.get(table_id)
    if record is None:
        return
    realm = table_realm(graph, table_id) or realm
    for entry in entries(graph, table_id):
        if entry.table_id:
            _walk(graph, entry.table_id, realm, domain_id, depth + 1, out)
            continue
        if not entry.item_id:
            continue
        out.append(
            Payment(
                item_id=entry.item_id,
                item_realm=graph.item_field(entry.item_id, "realm"),
                paid_realm=realm,
                table_id=table_id,
                entry_id=entry.entry_id,
                quantity=entry.quantity,
                guaranteed=entry.guaranteed,
                rarity_floor=entry.rarity_floor,
                depth=depth,
                domain_id=domain_id,
            )
        )


def payments(graph: Graph) -> list[Payment]:
    """Every direct item entry reachable from an authored band, deduplicated.

    Bounded on both axes: bands are finite, and each band's walk is capped at
    `MAX_NESTING_DEPTH` (see [_walk]). The dedupe dict is keyed on a snapshot of the
    payment's own identity, never on a size the walk itself grows.
    """
    out: list[Payment] = []
    for encounter in graph.encounters.values():
        for tier in encounter.tiers:
            for binding in tier["bindings"]:
                table_id = str(binding.get("table_id", ""))
                if table_id:
                    _walk(graph, table_id, str(tier["realm"]), encounter.domain_id, 0, out)
    seen: dict[tuple[str, str, str], Payment] = {}
    for payment in out:
        # A table bound on bands of two realms is a content error `acquisition
        # validate` already reports; the shorter (shallower) label is kept so one
        # entry is one row rather than two.
        previous = seen.get(payment.key)
        if previous is None or len(payment.paid_realm) < len(previous.paid_realm):
            seen[payment.key] = payment
    return sorted(seen.values(), key=lambda payment: (payment.item_id, payment.table_id))


def mispaid(graph: Graph, scale: dict[str, float]) -> list[Payment]:
    """Payments whose rung is not the item's authored rung.

    Both rungs must be on the scale: an item with no authored `realm` legitimately
    inherits the band's, and an item whose realm the table has no row for is the
    missing-key finding ([method off_ladder]), not a wrong-rung payment.
    """
    return [
        payment
        for payment in payments(graph)
        if payment.item_realm in scale
        and payment.paid_realm in scale
        and payment.item_realm != payment.paid_realm
    ]


def mispaid_scoped(graph: Graph, scale: dict[str, float]) -> list[Payment]:
    """Every mis-payment on an item the cultivation seeds declare, guaranteed or rolled.

    Both halves of the ladder's declared content — [method reagents] and
    [method seeded_consumables] — because both are balance numbers a player is
    priced against. Measured, not gated: the gate ([method gated]) takes only the part
    it can move, and this exists so [method report] can name what the gate leaves
    behind instead of only what it catches.
    """
    wanted = reagents(graph) | seeded_consumables(graph)
    return [payment for payment in mispaid(graph, scale) if payment.item_id in wanted]


def off_ladder(graph: Graph, scale: dict[str, float]) -> list[tuple[str, str]]:
    """`(item_id, realm)` for every item whose authored realm has no scale row.

    BL-0437's `qi_condensation` shape: the item names a rung the table does not
    carry, so its payout has no authored number. Distinct from a wrong-rung payment
    and reported on its own so the two are never mistaken for one fix.
    """
    out: set[tuple[str, str]] = set()
    for payment in payments(graph):
        if payment.item_realm and payment.item_realm not in scale:
            out.add((payment.item_id, payment.item_realm))
    return sorted(out)


def unbound(graph: Graph) -> list[str]:
    """Tables no band binds, sorted. Counted, not judged: they pay nothing."""
    bound: set[str] = set()
    for encounter in graph.encounters.values():
        for tier in encounter.tiers:
            for binding in tier["bindings"]:
                bound.add(str(binding.get("table_id", "")))
    return sorted(table_id for table_id in graph.loot_tables if table_id not in bound)


def reagents(graph: Graph) -> frozenset[str]:
    """Every item a realm seed's own recipe demands: the herbs and the warden cores.

    Read off `Trial.consumables`, so it is derived and never a regex or a hand-list.
    **`Consumable.reagents`, not `Trial.catalysts`**: the latter is keyed on the BOSS
    that carries a catalyst, so a reagent delivered through a `domain:` route is not
    in it — and that is exactly how all 13 Mind herbs escaped BL-0645's own audit,
    since `mind_<realm>_mind_herb` declares `domain:` and no `boss:`. A reagent is a
    recipe input whichever route delivers it.
    """
    return frozenset(
        reagent.item_id
        for trial in graph.all_trials
        if trial.ladder
        for consumable in trial.consumables
        for reagent in consumable.reagents
    )


def seeded_consumables(graph: Graph) -> frozenset[str]:
    """The realm seeds' own consumables: recipe OUTPUTS that also appear as drops.

    A separate set because it is a different question. A reagent is a recipe input, so
    every ladder declares three per realm and they all must be craftable. A
    consumable is an output, so finding one on a boss table is a DEF-0188 route
    decision, not a mis-scoped reagent — the whole 62-row residual of it is tracked
    where it belongs rather than folded into this gate.
    """
    return frozenset(
        consumable.item_id
        for trial in graph.all_trials
        if trial.ladder
        for consumable in trial.consumables
        if consumable.item_id
    )


def gated(graph: Graph, scale: dict[str, float]) -> list[Payment]:
    """The payments this module's gate owns.

    A **reagent a band guarantees**. Three conditions, each for a reason:

    - *reagent*, because it is a recipe input a ladder cannot advance without, and the
      game guarantees it by contract. [method seeded_consumables] is the neighbouring
      class and is deliberately excluded.
    - *guaranteed*, because that is the only class that can be moved without changing
      acquisition. A guaranteed entry inside a realm-correct pool yields exactly the
      same units as the direct entry did; a rolled one would become one candidate
      among many on its parent, which is DEF-0187's permanent-miss class all over
      again. Rolled reagents are measured and reported, never moved.
    - *mis-paying*, from [method mispaid].
    """
    wanted = reagents(graph)
    return [
        payment
        for payment in mispaid(graph, scale)
        if payment.item_id in wanted and payment.guaranteed
    ]


# --- the refused fix ----------------------------------------------------------


_ENTRIES_ARRAY = re.compile(r"(?s)entries = Array\[LootEntry\]\(\[\r?\n(?P<body>.*?)\r?\n\]\)")


def _read(path) -> str:
    """A table's authored text, with its line endings preserved verbatim.

    `Path.read_text` translates CRLF to LF on the way in and `Path.write_text`
    translates LF back to `os.linesep` on the way out, so a read/write round trip
    through them **flips a file's line endings even when the content is untouched**.
    That is how the first `repair` pass rewrote nine shipped pools it had no business
    touching, and git's autocrlf hides the damage in `git diff` while `git status`
    still reports every one of them. Read and write bytes; nothing else in this module
    touches a `.tres` on disk.
    """
    return path.read_bytes().decode("utf-8")


def _write(path, text: str) -> None:
    """Write a table's text with no newline translation in either direction.

    **Bounded retry** (3 attempts, no unbounded spin): ~20 agents share this working
    tree and a Windows `open` can lose a race with a handle another one holds, which
    surfaces as OSError rather than as a half-written file. Three is enough to ride out
    a moment; anything longer is a lock somebody else owns, and this must fail rather
    than wait.
    """
    for attempt in range(3):
        try:
            path.write_bytes(text.encode("utf-8"))
            return
        except OSError:
            if attempt == 2:
                raise
            time.sleep(0.2 * (attempt + 1))


def _eol(text: str) -> str:
    """The line ending this file already uses, so a rebuild does not switch it."""
    return "\r\n" if "\r\n" in text else "\n"


def _normalise_entries_array(text: str) -> str:
    """One `\tSubResource("id")` per line, comma-separated, no blank lines.

    Godot's variant parser needs the comma BETWEEN elements and accepts its absence
    after the last, which is why the shipped tables write it that way. Splicing a ref
    in without restoring that comma produced a table that would not load, so the array
    is re-derived from the ref ids it actually holds rather than patched in place.

    **A trailing comma on the last element is preserved as authored** — the presence of
    one is read off the array, not inferred — so the output is byte-identical to the
    input on an already well formed array. Half the shipped pools write one and half do
    not; normalising that away would rewrite files this change has no business
    touching, and a fixer that restyles the corpus is a fixer whose diff nobody can
    read. An earlier version inferred the comma instead of reading it and added one to
    1,300 tables in a single pass, which is the cost of getting this line wrong. For
    the same reason the rebuild joins with the file's own line ending (see [_eol]).
    """
    found = _ENTRIES_ARRAY.search(text)
    if found is None:
        raise ToolError("no entries array to normalise")
    refs = re.findall(r'SubResource\("([^"]+)"\)', found.group("body"))
    if not refs:
        raise ToolError("the entries array holds no SubResource ref")
    lines = [f'\tSubResource("{resource_id}")' for resource_id in refs]
    if found.group("body").rstrip().endswith(","):
        lines[-1] += ","
    body = ("," + _eol(text)).join(lines)
    return text[: found.start("body")] + body + text[found.end("body") :]


def structural(graph: Graph) -> list[str]:
    """Loot tables whose `entries` array cannot load, or refs a block that is gone.

    A ref with no matching `[sub_resource ... id=...]` is a dangling reference, and a
    neighbouring pair with no comma between them is an unparseable array. Both are
    load-time failures, not balance findings, and neither is visible to a reader
    comparing magnitudes — which is exactly how this module's own `fix` shipped 53
    unloadable tables before [method _normalise_entries_array] existed. Checked
    because a defect the fixer can introduce has to be one the fixer can also see.
    """
    problems: list[str] = []
    for table_id in sorted(graph.loot_tables):
        text = graph.read(graph.loot_tables[table_id])
        found = _ENTRIES_ARRAY.search(text)
        if found is None:
            problems.append(f"{table_id}: has no entries array")
            continue
        declared = {resource_id for resource_id, _block in _blocks(text)}
        for reference in re.findall(r'SubResource\("([^"]+)"\)', found.group("body")):
            if reference not in declared:
                problems.append(
                    f"{table_id}: refs SubResource('{reference}'), which no sub_resource "
                    "block declares"
                )
        elements = [line for line in found.group("body").splitlines() if line.strip()]
        for index, line in enumerate(elements[:-1]):
            if not line.rstrip().endswith(","):
                problems.append(
                    f"{table_id}: the entries array has no comma between elements "
                    f"{index + 1} and {index + 2}"
                )
    return problems


def repair() -> int:
    """Normalise every table's `entries` array, and drop a ref with no block.

    Idempotent, and a no-op when the array is already well formed. The repair
    [method fix] needed on the tables it wrote, exposed as an action so the shape can be
    brought back without re-deriving anything: it reads only the ref ids already in the
    array, so it cannot invent an entry.

    **A ref with no `[sub_resource ... id=...]` block is dropped, and named.** It is
    the only possible repair — the block it names is not in the file, so there is
    nothing to restore it from — but it is also a load-time failure, so every drop is
    printed rather than made quietly.
    """
    graph = Graph()
    repaired = 0
    dropped = 0
    for table_id in sorted(graph.loot_tables):
        path = TABLE_DIR / f"{table_id}.tres"
        if not path.is_file():
            continue
        text = _read(path)
        original = text
        declared = {resource_id for resource_id, _block in _blocks(text)}
        found = _ENTRIES_ARRAY.search(text)
        if found is None:
            raise ToolError(f"{table_id}: has no entries array")
        for reference in re.findall(r'SubResource\("([^"]+)"\)', found.group("body")):
            if reference not in declared:
                info(f"{table_id}: dropping dangling SubResource('{reference}')")
                text = re.sub(
                    rf'^\tSubResource\("{re.escape(reference)}"\),?\r?\n',
                    "",
                    text,
                    count=1,
                    flags=re.M,
                )
                dropped += 1
        fixed = _normalise_entries_array(text)
        # Compared against `original`, not against the dropped text: a drop that
        # already leaves a well formed array produces no further normalisation, and
        # testing the wrong pair of strings silently threw the drop away — which is
        # what left the first pass reporting the same dangling ref it had just fixed.
        if fixed != original:
            _write(path, fixed)
            repaired += 1
    ok(f"normalised {repaired} table(s); dropped {dropped} dangling ref(s)")
    return check()


def fix(*, scope: str = "gate") -> int:
    """REFUSED, unconditionally. The migration this action performed was rejected.

    ADR 0166 decided a drop realizes at its item's authored rung, and that ruling
    **landed**: `LootRewards.contextualize` overrides rarity only and keeps
    `def.realm`, and `ItemGenerator` hands `def.realm` to `OptionCatalog`. So the
    defect this function existed to correct no longer exists at runtime, and what
    it did instead was to PLACE the rolled residual into one realm pool per owed
    realm. ADR 0166 rejects that route on four measured blockers, any one
    disqualifying (`docs/adr/0166-*.md`, "Why placement was rejected"):

    - it truncates: median 13 pools per table, max 25, so **279 of 333** tables lose
      entries behind `MAX_PLANS_PER_RESOLVE = 12` and **318** exceed
      `MAX_DROPS_PER_RESOLVE = 8` — a silent drop, worse than a visible mis-payment;
    - it soft-locks: **2679** residual entries are inputs to shipped recipes and **13**
      are ruled `mind_sea_catalyst`, and loot rule E2 grants no second run, so any
      miss is the DEF-0187 / DEF-0199 permanent-miss class against a realm gate;
    - it is not acquisition-neutral: a rolled entry goes from 1 of `N` candidates to
      1 of `N` pools times 1 of `M`;
    - it needs ~4380 pools against the 1083 already shipped.

    **The refusal is unconditional on purpose — no flag, no scope, no confirmation.**
    A gate is one typo away from re-enabling a rejected migration, so there is no gate
    here. The migration body and its four helpers were **deleted** rather than left
    unreachable behind this raise, because dead code one edit away from the guard is
    the same hazard with extra steps. Nothing is lost: the generator owns
    realm-correct placement for its own output (`tools/acquisition/seed.py:412`
    `_boss_entries` buckets every item by its own realm and emits a realm pool per
    bucket), `repair` still owns the array shape, and git history holds the body if a
    future ADR reopens the question.

    `scope` is retained only so [method run]'s dispatch signature is unchanged. It
    selects nothing and reaches nothing.
    """
    raise ToolError(
        "loot-magnitude fix is REFUSED and always will be until an ADR reopens it. The "
        "placement migration it performed was rejected by ADR 0166, which instead ruled "
        "that a drop pays its item's own rung — and that ruling has landed in source "
        "(LootRewards.contextualize no longer overrides def.realm, and ItemGenerator "
        "reads def.realm as the magnitude), so there is nothing left to move. Running "
        "the migration would have truncated 279 of 333 tables behind "
        "MAX_PLANS_PER_RESOLVE = 12, soft-locked 2679 recipe inputs, changed a rolled "
        "entry from 1-of-N to 1-of-N-pools-times-1-of-M, and needed ~4380 pools against "
        "1083 shipped. See docs/adr/0166-a-drop-pays-its-item-s-own-rung-*.md. To measure "
        "instead, run: uv run python -m tools cultivation loot-magnitude report "
        "(placement census, NOT what a player receives — see this module's docstring)."
    )


# --- commands -----------------------------------------------------------------


def report() -> int:
    """Print what every direct entry's PLACEMENT pays against what its item owes.

    **This is a placement census, not a defect list.** Since ADR 0166 landed, a drop
    realizes at its item's own rung regardless of the band it sits on, so the
    mis-payment count below is a count of entries PLACED on a foreign band. Nothing
    here is a queue, and `fix` refuses to act on it. See this module's docstring.
    """
    graph = Graph()
    scale = load_scale()
    total = payments(graph)
    found = mispaid(graph, scale)
    scoped = mispaid_scoped(graph, scale)
    gate = gated(graph, scale)
    wanted = reagents(graph)
    rolled = [payment for payment in found if payment.item_id in wanted and not payment.guaranteed]
    consumables = len(scoped) - len(gate) - len(rolled)
    info(f"tables on disk: {len(graph.loot_tables)}, of which unbound: {len(unbound(graph))}")
    info(f"direct entries reachable from a band: {len(total)}")
    info(
        f"PLACED on a rung other than their own: {len(found)}  "
        "(a drop still realizes at its own rung since ADR 0166 — this is placement, "
        "not payment, and `fix` refuses to move any of it)\n"
        f"  gate: guaranteed reagent        {len(gate):>5}\n"
        f"  residual: rolled reagent        {len(rolled):>5}  "
        "(cannot move without changing acquisition)\n"
        f"  residual: seeded consumable     {consumables:>5}  "
        "(DEF-0188's route decision, not a mis-scoped reagent)\n"
        f"  residual: domain relic / other  {len(found) - len(scoped):>5}"
    )
    info(f"{'item':42s} {'owes':>20s} {'paid':>20s} {'x':>6s} {'gtd':>5s} {'table':46s} {'domain'}")
    for payment in gate:
        _row(payment, scale)
    loose = off_ladder(graph, scale)
    info(f"items whose authored realm has no scale row: {len(loose)}")
    for item_id, realm_id in loose:
        info(f"  {item_id} -> realm '{realm_id}'")
    return 0


def _row(payment: Payment, scale: dict[str, float]) -> None:
    """One payment, as the rung it pays against the rung it owes."""
    paid = scale[payment.paid_realm]
    owed = scale[payment.item_realm]
    info(
        f"{payment.item_id:42s} {payment.item_realm:>13s} {owed:>6.2f}x "
        f"{payment.paid_realm:>13s} {paid:>6.2f}x {paid / owed:>5.2f}x "
        f"{str(payment.guaranteed):>5s} {payment.table_id:46s} {payment.domain_id}"
    )


def check(*, scope: str = "gate") -> int:
    """Fail on any PLACEMENT at a rung other than the item's own, inside `scope`.

    `scope="gate"` covers the guaranteed reagents ([method gated]) — BL-0645's class.
    It is **empty and measured so** (0 of 8084 today), which is the point of measuring
    it: a gate that cannot report 13 of 53 is not a gate. `scope="all"` covers every
    direct entry.

    **`--scope all` is permanently red and this function cannot green it.** It measures
    placement, not the runtime, and ADR 0166's ruling — which HAS landed — is that the
    runtime ignores the band for magnitude. So its 6307 are entries that sit on a
    foreign band and receive their own rung, not 6307 mis-payments. Do not read this
    scope's output as a queue, and do not "fix" it by moving entries: [method fix]
    refuses precisely that migration, on four measured blockers.

    ADR 0166's unbuilt `check --scope magnitude` is **not** built here on purpose. Its
    three rules are all already implemented, in GDScript, by
    `game/tests/modules/loot/test_loot_band_magnitude_ruling.gd` (rules a/b/c, reading
    source) and `game/tests/modules/loot/test_loot_drop_pays_own_rung.gd` (the value,
    end to end). Both run in `tools test`, which `tools/check.py:113` runs, so the
    mechanism is already inside the gate. A second Python copy of one rule is a second
    thing to drift, and `--scope` here accepts only `{gate, all}`, so adding it would
    also mean editing `tools/cultivation/__init__.py`.

    Exit codes and findings are unchanged by any of the above. Nothing is suppressed.
    """
    graph = Graph()
    scale = load_scale()
    gate = mispaid(graph, scale) if scope == "all" else gated(graph, scale)
    problems: list[str] = []
    for payment in gate:
        paid = scale[payment.paid_realm]
        owed = scale[payment.item_realm]
        problems.append(
            f"{payment.table_id}.{payment.entry_id} PLACES {payment.item_id} at "
            f"{payment.paid_realm} ({paid:.2f}x) where the item is authored "
            f"{payment.item_realm} ({owed:.2f}x): {payment.domain_id} binds it on a "
            "band it does not own, and a direct entry has no realm of its own to "
            "override the band. Since ADR 0166 the drop realizes at the item's own "
            "rung anyway (this is a placement census, not a mis-payment)"
        )
    for item_id, realm_id in off_ladder(graph, scale):
        problems.append(f"{item_id}: authored realm '{realm_id}' has no magnitude scale row")
    problems.extend(structural(graph))
    for problem in problems:
        fail(problem)
    if problems:
        return 1
    ok(
        f"every direct loot entry in scope '{scope}' is placed on its item's own rung "
        f"({len(payments(graph))} entries measured, {len(scale)} scale rows)"
    )
    return 0


def run(action: str, scope: str = "gate") -> int:
    """Dispatch one action. `action` is constrained by the parser, not here.

    `fix` is dispatched rather than dropped from the parser choices on purpose: a
    refused action that explains WHY it was refused is worth more to the next agent
    than an argparse "invalid choice", and [method fix] raises before it reads a
    single file.
    """
    if action == "report":
        return report()
    if action == "fix":
        return fix(scope=scope)
    if action == "repair":
        return repair()
    return check(scope=scope)
