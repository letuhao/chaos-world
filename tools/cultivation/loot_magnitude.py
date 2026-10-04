"""Which rung of the magnitude ladder a drop actually pays, and whether it is owed.

A `LootEntry` realizes at a realm the RESOLVER computes, never at the realm its
item is authored for. `LootResolver._plan` takes `context.realm` whenever it is set
and only falls back to `LootTableDef.realm`; the context is the band
(`LootRewards.make_context(tier.realm, ...)`), and `LootResolver._child_context`
lets a nested table override the band only where that table declares a `realm` of
its own. So the rung a drop pays is

    the band realm, overridden by each table's own `realm` from the outside in.

`item_magnitude_scale.json` is ONE per-realm table shared by every ladder
(ADR 0050: item magnitudes are not actor stats and deliberately differ), so the rung
a reagent owes is the `realm` on its own `ItemDef` and nothing else. Three places in
the repo already say so in prose, and this module is the executable form of all
three:

- `tools/acquisition/design.py`: "the band is a statement about difficulty, not
  about which realm a drop belongs to, so moving the realm between bands would
  mis-scale the loot", and a boss's loot is "grouped by the realm its items roll
  at, so one iron relic in a primordial trial still rolls at an iron magnitude".
- `tools/acquisition/chain.py:band_realm`: "a wrong-high fallback hands out loot
  scaled above its authored magnitude".
- `game/src/modules/loot/loot_rewards.gd`: "the drop rolls for the realm and rarity
  it fell from, not the ones its definition was authored at".

That last line is why this is a PLACEMENT defect and not a scale defect. The
resolver's rule is right and `item_magnitude_scale.json` is right; what is wrong is
a **direct** entry sitting on a band whose realm is not its item's own. A direct
entry has no table of its own to override the band, so it pays the band's rung: that
is BL-0645, whose named instance `mind_core_formation_mind_herb` paid `dao_ancestor`
(3.8x) where it owes `core_formation` (1.2x). A foreign-realm reagent is supposed to
sit in a nested pool that declares its own realm — the shape
`tools/acquisition/seed.py` `_boss_entries` already emits for every foreign-realm
catalyst, and the shape 30 shipped `_pool_*` tables already carry.

A second finding is measured here and kept deliberately separate, because the two
were reported as one and are not: an item whose `realm` names a rung the scale table
has no row for is BL-0437's `qi_condensation` failure — a **missing key**, the
opposite failure from a wrong-rung payment, and one `options.load_scale` aborts on
before any of this runs. It is [method off_ladder], not [method mispaid].

## What was measured, not assumed

The gate ([method gated]) found **53** mis-paying guaranteed reagents where BL-0645
named 13: its 13 Mind herbs plus **40 qi-ladder herbs and cores** in the identical
shape, which its own audit never reached because it walked the Mind ladder only. Both
halves are fixed here, because a gate that reports 13 of 53 is not a gate.

The class itself is far larger than either ladder's reagents: `report` measures 6,310
of 8,083 reachable direct entries paying a rung that is not their item's own, of which
6,245 are domain relics. That residual is BL-0704, is *measured and printed* by
`report`, and is deliberately not in the gate — see [method gated] for why it cannot
be fixed the same way.

## Actions

- `report` - every direct entry, what it pays, what it owes, and which domain pays.
- `check`  - non-zero when any exists inside `--scope` (`gate` by default, `all` for
  the whole corpus, which is red today on BL-0704's residual). The class guard.
- `fix`    - move the foreign-realm direct entries into the pool that declares their
  realm, as text surgery on the two files. Never a full re-emit: `emit.Entry` writes
  no `chance` and no `quantity_max`, so regenerating a 24-entry boss table to move
  one entry would silently normalize the other twenty-three.
- `repair` - bring an `entries` array back to a loadable shape. `check` also asserts
  that shape ([method structural]), because `fix` splices refs and a defect the fixer
  can introduce has to be one the fixer can also see.
"""

from __future__ import annotations

import re
import time
from dataclasses import dataclass

from ..acquisition import design, emit
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


# --- the fix ------------------------------------------------------------------


def pool_id_for(table_id: str, realm_id: str) -> str:
    """The pool a foreign-realm entry moves into, on the generator's own id scheme.

    `design.pool_id` is keyed on a BOSS id, and the table being fixed is usually
    `loot_<boss_id>` but is not always: a folded encounter's `loot_route_*` table
    survives as a boss's bound table. Deriving from the table id keeps both on the
    scheme `tools/acquisition/seed.py` recognises, so a re-seed reproduces the fix
    instead of treating the pool as a hand decision.
    """
    prefix = design.TABLE_PREFIX
    stem = table_id[len(prefix) :] if table_id.startswith(prefix) else table_id
    return f"{prefix}{stem}{design.POOL_SUFFIX}{realm_id}"


def _remove_entry(text: str, wanted_id: str) -> str:
    """Excise one entry's block and its `SubResource` ref, and nothing else.

    The ref's comma is OPTIONAL, because the last element of the array carries none and
    a removal that missed that case left a dangling ref the [method structural] guard
    caught on 1 of the 53 tables this fix wrote.

    The remaining blocks keep their authored `entry_N` numbers, so a gap is left where
    the removed one was. Godot keys a `SubResource` ref by that string, so a gap is
    load-bearing-free: renumbering would rewrite every later ref and turn a one-entry
    fix into a whole-file diff.
    """
    target = next((block for resource_id, block in _blocks(text) if resource_id == wanted_id), "")
    if not target:
        raise ToolError(f"no entry block {wanted_id} to remove")
    out = text.replace(target, "", 1)
    return re.sub(
        rf'^\tSubResource\("{re.escape(wanted_id)}"\),?\r?\n',
        "",
        out,
        count=1,
        flags=re.M,
    )


def _add_entry(text: str, entry: emit.Entry, resource_id: str) -> str:
    """Append one entry's block before `[resource]` and its ref at the array's end.

    Appended rather than inserted: `LootResolver` pays guaranteed entries before the
    weighted draw, so an appended guaranteed entry cannot reorder a single draw, and
    the diff stays one added block plus one added line.
    """
    main = _MAIN_HEAD.search(text)
    if main is None:
        raise ToolError("no [resource] block to insert an entry before")
    at = main.start()
    return _normalise_entries_array(text[:at] + entry.body(resource_id) + text[at:])


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


def _bump_load_steps(text: str, removed: int, added: int) -> str:
    """Keep `load_steps` equal to 3 + the entry count, as the shipped tables write it.

    `emit.table` writes `3 + len(entries)` for two `ext_resource` lines and one per
    entry, so a removal plus an addition is a wash. Kept honest rather than assumed:
    Godot reads the header as a progress hint, and a stale one is a lie in the file a
    reviewer reads.
    """
    head = re.search(r"load_steps=(\d+)", text)
    if head is None:
        return text
    total = max(1, int(head.group(1)) + added - removed)
    return text[: head.start(1)] + str(total) + text[head.end(1) :]


def fix(*, scope: str = "gate") -> int:
    """Move every foreign-realm direct entry into a pool that declares its realm.

    The guarantee moves with it, which is the whole reason the entry may move: a
    guaranteed entry inside a pool is unconditional only when the nesting entry above
    it is guaranteed too, so the parent entry is written with exactly the flag the
    moved entries carried. A realm whose moved entries disagree about that flag is
    **refused**, because no single pool can preserve both — a rolled parent would
    demote a guaranteed reagent (BL-0645's original DEF-0187 class) and a guaranteed
    parent would promote a rolled one, and either would change acquisition silently.
    """
    graph = Graph()
    scale = load_scale()
    found = mispaid(graph, scale) if scope == "all" else gated(graph, scale)
    if not found:
        ok("no foreign-realm direct entry to move")
        return 0
    by_table: dict[str, list[Payment]] = {}
    for payment in found:
        by_table.setdefault(payment.table_id, []).append(payment)
    # Group by (realm, guarantee) BEFORE touching a file, so an unfixable grouping
    # fails with the tree untouched rather than half-rewritten.
    for table_id, group in sorted(by_table.items()):
        pools: dict[str, set[bool]] = {}
        for payment in group:
            pools.setdefault(payment.item_realm, set()).add(payment.guaranteed)
        for realm_id, flags in sorted(pools.items()):
            if len(flags) > 1:
                raise ToolError(
                    f"{table_id}: {realm_id} entries disagree about `guaranteed` "
                    f"({sorted(flags)}); one pool cannot preserve both, so nothing was "
                    "written"
                )
            if table_id.endswith(f"{design.POOL_SUFFIX}{realm_id}"):
                raise ToolError(f"{table_id} is already the {realm_id} pool; nothing to move")
    written = 0
    moved_entries = 0
    for table_id in sorted(by_table):
        group = by_table[table_id]
        wanted: dict[str, list[Payment]] = {}
        for payment in group:
            wanted.setdefault(payment.item_realm, []).append(payment)
        path = TABLE_DIR / f"{table_id}.tres"
        text = _read(path)
        removed = 0
        added = 0
        for realm_id in sorted(wanted):
            pool_id = pool_id_for(table_id, realm_id)
            _refuse_unreproducible(graph, pool_id)
            existing = entries(graph, pool_id)
            kept = [
                entry
                for entry in existing
                if entry.item_id not in {payment.item_id for payment in wanted[realm_id]}
            ]
            pool_entries = [emit.Entry(entry.entry_id, **emit_fields(entry)) for entry in kept]
            for payment in sorted(wanted[realm_id], key=lambda item: item.entry_id):
                pool_entries.append(
                    emit.Entry(
                        payment.entry_id,
                        item_id=payment.item_id,
                        guaranteed=payment.guaranteed,
                        quantity=payment.quantity,
                        rarity_floor=payment.rarity_floor,
                    )
                )
                record = next(
                    entry
                    for entry in entries(graph, table_id)
                    if entry.entry_id == payment.entry_id
                )
                text = _remove_entry(text, record.resource_id)
                removed += 1
                moved_entries += 1
            pool_path = TABLE_DIR / f"{pool_id}.tres"
            _write(
                pool_path,
                emit.table(
                    pool_id,
                    f"{_display(graph, table_id)} ({realm_id})",
                    pool_entries,
                    realm=realm_id,
                ),
            )
            # The nesting entry carries the moved entries' own guarantee, because a
            # guaranteed entry inside a pool is unconditional only if the step above
            # it is too (`tools/acquisition/loot.py`).
            nesting_id = f"pool_{realm_id}"
            text = _add_entry(
                text,
                emit.Entry(nesting_id, table_id=pool_id, guaranteed=wanted[realm_id][0].guaranteed),
                f"entry_{nesting_id}",
            )
            added += 1
            written += 1
        text = _bump_load_steps(text, removed, added)
        _write(path, text)
        written += 1
    ok(
        f"moved {moved_entries} foreign-realm direct entries across "
        f"{len(by_table)} table(s) and wrote {written} file(s)"
    )
    return check(scope=scope)


def _refuse_unreproducible(graph: Graph, pool_id: str) -> None:
    """Refuse to re-emit a pool whose entries `emit.table` cannot reproduce.

    `emit.Entry` writes `weight = 1.0` and the `NO_CHANCE` sentinel and nothing else,
    so merging into a pool that carries a real `weight` or a real `chance` would
    silently normalize it. That pool is a different design than the one this fix
    writes, and rewriting it is its owner's decision, not this fix's.
    """
    record = graph.loot_tables.get(pool_id)
    if record is None:
        return
    text = graph.read(record)
    if "chance = -1.0" not in text:
        raise ToolError(f"{pool_id} declares a real `chance`; refusing to re-emit it")
    for line in text.splitlines():
        weight = line.split("=", 1)[1].strip() if line.startswith("weight = ") else ""
        if weight and weight != "1.0":
            raise ToolError(f"{pool_id} declares weight {weight}; refusing to re-emit it")


def emit_fields(entry: Entry) -> dict:
    """`emit.Entry` keywords for an entry read back off disk.

    `weight` and `chance` are absent from `emit.Entry` because every entry
    `emit.table` writes is weight 1.0 with the `NO_CHANCE` sentinel; an entry that
    says otherwise is not reproduced by re-emission and must not be.
    """
    if entry.table_id:
        return {"table_id": entry.table_id, "guaranteed": entry.guaranteed}
    return {
        "item_id": entry.item_id,
        "guaranteed": entry.guaranteed,
        "quantity": entry.quantity,
        "quantity_max": entry.quantity_max,
        "rarity_floor": entry.rarity_floor,
    }


def _display(graph: Graph, table_id: str) -> str:
    """`LootTableDef.display_name`, or the id when the file omits it."""
    record = graph.loot_tables.get(table_id)
    return resource_scalar(graph.read(record), "display_name") or table_id


# --- commands -----------------------------------------------------------------


def report() -> int:
    """Print what every direct entry pays against what it owes, and what the gate owns."""
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
        f"paying a rung other than their own: {len(found)}\n"
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
    """Fail on any payment at a rung other than the item's own, inside `scope`.

    `scope="gate"` covers the guaranteed reagents ([method gated]) — the class
    BL-0645 is an instance of, and the only one that can move without changing
    acquisition. `scope="all"` covers every direct entry and is red today on the
    residual [method report] names; it exists so the next agent measures that residual
    against a command rather than against this docstring.
    """
    graph = Graph()
    scale = load_scale()
    gate = mispaid(graph, scale) if scope == "all" else gated(graph, scale)
    problems: list[str] = []
    for payment in gate:
        paid = scale[payment.paid_realm]
        owed = scale[payment.item_realm]
        problems.append(
            f"{payment.table_id}.{payment.entry_id} pays {payment.item_id} at "
            f"{payment.paid_realm} ({paid:.2f}x) where the item is authored "
            f"{payment.item_realm} ({owed:.2f}x): {payment.domain_id} binds it on a "
            "band it does not own, and a direct entry has no realm of its own to "
            "override the band"
        )
    for item_id, realm_id in off_ladder(graph, scale):
        problems.append(f"{item_id}: authored realm '{realm_id}' has no magnitude scale row")
    problems.extend(structural(graph))
    for problem in problems:
        fail(problem)
    if problems:
        return 1
    ok(
        f"every direct loot entry in scope '{scope}' pays its item's own rung "
        f"({len(payments(graph))} entries measured, {len(scale)} scale rows)"
    )
    return 0


def run(action: str, scope: str = "gate") -> int:
    """Dispatch one action. `action` is constrained by the parser, not here."""
    if action == "report":
        return report()
    if action == "fix":
        return fix(scope=scope)
    if action == "repair":
        return repair()
    return check(scope=scope)
