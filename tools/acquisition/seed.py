"""Write the loot content that makes the body path's authored sources reachable.

An `ItemDef` source of `boss:<id>` is only delivered once `LootApi.enter_domain`
can spawn that boss, and `LootApi` resolves a domain through one authored
`LootEncounterDef` under `res://data/loot/encounters/`. So the fix is content:
one encounter per body trial, one loot table per boss, and the boss's own legacy
`loot` array retired so the table is the single authority.

Idempotent by construction. A file that already exists is left alone and reported
as authored, because a generated id colliding with a hand-written one means
somebody decided that content, and overwriting it would delete the decision.
`--force` overwrites only a file whose declared id is the one this run was about
to write, so it can refresh a generator's own output and still never touches
somebody else's file.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from ..common import ToolError, info
from ..data import DATA_ROOT, _merge_array_block
from . import design, emit
from .chain import (
    Encounter,
    Graph,
    Trial,
    resource_scalar,
    scalar,
    string_array,
    sub_resources,
    unquote,
)
from .chain import (
    bindings as read_bindings,
)
from .loot import reachable_items

TABLE_DIR = DATA_ROOT / "loot" / "tables"
ENCOUNTER_DIR = DATA_ROOT / "loot" / "encounters"


@dataclass
class Written:
    """What a seed run did, so the caller reports content it refused to touch."""

    tables: list[str] = field(default_factory=list)
    encounters: list[str] = field(default_factory=list)
    kept: list[str] = field(default_factory=list)
    retired: list[str] = field(default_factory=list)
    contested: list[str] = field(default_factory=list)
    folded: list[str] = field(default_factory=list)
    deleted: list[str] = field(default_factory=list)
    adopted: list[str] = field(default_factory=list)
    completed: list[str] = field(default_factory=list)
    completed_ids: list[str] = field(default_factory=list)

    @property
    def created(self) -> int:
        return len(self.tables) + len(self.encounters)


def seed(graph: Graph, force: bool = False) -> Written:
    """Seed every trial's loot content. Returns what it wrote.

    All three cultivation ladders plus every non-ladder world domain, because a
    boss in no authored encounter is a boss `LootApi.enter_domain` cannot spawn
    whatever ladder it came from. The body ladder was seeded first and in
    isolation, which is why the qi and mind ladders and the 58 world domains
    carried drops nothing could deliver.
    """
    written = Written()
    gaps: list[str] = []
    for trial in sorted(graph.all_trials, key=lambda entry: (not entry.ladder, entry.path, entry.index)):
        gaps.extend(_seed_trial(graph, trial, written, force))
    if gaps:
        # Loud, not silent: a boss with nothing to drop would produce a table the
        # loot validator rejects, and a run that reported "ok" over content it
        # could not author is exactly the failure this command exists to remove.
        raise ToolError(
            f"{len(gaps)} boss(es) have no authored drop to migrate: "
            + "; ".join(sorted(gaps)[:10])
        )
    info(
        f"seeded {written.created} file(s): {len(written.tables)} table(s), "
        f"{len(written.encounters)} encounter(s); kept {len(written.kept)} authored "
        f"file(s); retired {len(written.retired)} legacy boss loot array(s)"
    )
    if written.adopted:
        info(
            f"carried {len(written.adopted)} authored table(s) over from a folded "
            "encounter, so their non-catalyst drops stay reachable:"
        )
        for line in written.adopted:
            info(f"  - {line}")
    if written.completed:
        info(
            f"completed {len(written.completed_ids)} authored encounter(s) that never "
            "spawned a boss their own domain declares. Their bands, rarity and "
            "vitality are untouched; only the missing bosses and bindings were added:"
        )
        for line in written.completed:
            info(f"  - {line}")
    if written.folded:
        info(
            f"folded {len(written.folded)} contested domain(s) into the body trial's "
            "own encounter, which guarantees the catalysts the folded one rolled:"
        )
        for line in written.folded:
            info(f"  - {line}")
    if written.deleted:
        info(
            f"deleted {len(written.deleted)} superseded encounter file(s); one domain "
            "may carry at most one encounter:"
        )
        for line in written.deleted:
            info(f"  - {line}")
    if written.contested:
        info(
            f"SKIPPED {len(written.contested)} domain(s): an encounter already claims "
            "them. A second encounter for one domain is a content error, so the "
            "existing file stands; `acquisition validate` names whatever it leaves out."
        )
        for line in written.contested:
            info(f"  - {line}")
    return written


def _adopted_tables(graph: Graph, encounter: Encounter) -> dict[str, str]:
    """boss id -> the table a folded encounter already bound it to.

    Read from every band rather than the first, because the binding is the thing
    being preserved: an E-tier boss that only the deeper band listed would lose its
    table if only one band were consulted.
    """
    out: dict[str, str] = {}
    for tier in encounter.tiers:
        for binding in tier["bindings"]:
            boss_id = unquote(str(binding.get("boss_id", "")))
            table_id = unquote(str(binding.get("table_id", "")))
            if boss_id and table_id and table_id in graph.loot_tables:
                out[boss_id] = table_id
    return out


def _seed_trial(graph: Graph, trial: Trial, written: Written, force: bool) -> list[str]:
    # One domain may have at most one encounter. A file that already claims this
    # domain stands, whether it was authored by hand or by another agent's run:
    # writing a second one would be a content error. The exception is a `loot_route_*`
    # encounter, which loses the domain on the soft-lock above, and `--force` against
    # the file this generator itself wrote, which is the only way to re-apply a
    # generator change without deleting somebody's decision first.
    existing = graph.encounter_for_domain(trial.domain_id)
    mine = design.encounter_id(trial.domain_id)
    adopted: dict[str, str] = {}
    completing = False
    if existing is not None and existing.encounter_id != mine:
        unspawned = [b for b in trial.boss_ids if b not in existing.boss_ids]
        # An encounter that omits a boss its own domain declares is **completed**,
        # never folded, whatever its id looks like. Folding deletes the authored
        # file and replaces its bands with the generated two, and a band declares a
        # rarity that `_promote` takes the maximum of against each entry's own
        # floor — so a `legendary` one-band encounter whose entries only floor at
        # `rare` hands out `legendary` drops, and folding silently downgrades all
        # of them. Completion keeps the author's bands and adds the missing boss.
        if unspawned:
            completing = True
            adopted = _adopted_tables(graph, existing)
            written.completed.append(
                f"{trial.domain_id}: {existing.path.name} never spawned "
                f"{', '.join(unspawned)}"
            )
        elif not design.supersedes(existing.encounter_id):
            written.contested.append(
                f"{trial.domain_id}: {existing.path.name} already hosts "
                f"{', '.join(existing.boss_ids) or 'nothing'}"
            )
            return []
        else:
            adopted = _adopted_tables(graph, existing)
            written.folded.append(
                f"{trial.domain_id}: {existing.path.name} -> {mine} "
                f"(carrying {len(adopted)} authored table binding(s))"
            )
    elif existing is not None:
        # This generator's own encounter for the domain, from a previous run. Its
        # bindings are adopted for the same reason a folded one is: some of them
        # name a table this generator did not write, and regenerating a binding
        # for a file that already exists without `--force` would write a *second*
        # table and leave the first one bound by nothing — an unreachable drop
        # table that no check would name.
        adopted = _adopted_tables(graph, existing)
    gaps: list[str] = []
    bindings = []
    for boss_id in trial.boss_ids:
        # A boss whose drops already live in an authored table keeps that table.
        # Regenerating it would drop everything the folded encounter held — the
        # unique artifacts are guaranteed entries there and weighted rolls here.
        #
        # `--force` overrides an adopted binding only when the table is one this
        # generator wrote. A `loot_route_*` table is somebody else's decision and
        # is never regenerated; a `loot_<boss>` or `loot_<boss>_pool_<realm>` table
        # *is* this generator's own output, and adopting it forever would make a
        # generator change impossible to re-apply — which is exactly what `--force`
        # exists for.
        keep = adopted.get(boss_id, "")
        if keep and (not force or not _owns_table(keep, boss_id)):
            bindings.append({"boss_id": boss_id, "table_id": keep})
            written.adopted.append(f"{boss_id} keeps {keep}")
            continue
        table = design.table_id(boss_id)
        if not _boss_items(graph, boss_id) and not graph.catalysts_for(boss_id):
            gaps.append(f"{boss_id} (domain {trial.domain_id})")
            continue
        path = TABLE_DIR / f"{table}.tres"
        if _write(
            path,
            emit.table(
                table,
                graph.boss_display_name(boss_id) or f"{boss_id} ({trial.realm_id})",
                _boss_entries(graph, trial, boss_id, written, force),
            ),
            written,
            "table",
            force,
        ):
            _check_table(path, table)
        bindings.append({"boss_id": boss_id, "table_id": table})
        _retire_legacy_loot(graph, boss_id, written)
    if completing and existing is not None:
        added = [
            binding
            for binding in bindings
            if binding["boss_id"] not in existing.boss_ids
        ]
        unspawned = [boss for boss in trial.boss_ids if boss not in existing.boss_ids]
        if added and _complete_encounter(existing.path, unspawned, added):
            written.completed_ids.append(existing.path.name)
        else:
            gaps.append(
                f"{trial.domain_id}: {existing.encounter_id} never spawned "
                f"{', '.join(unspawned)} and could not be completed additively"
            )
        return gaps
    encounter = design.encounter_id(trial.domain_id)
    path = ENCOUNTER_DIR / f"{encounter}.tres"
    if _write(
        path,
        emit.encounter(
            encounter,
            trial.display_name or trial.domain_id,
            trial.domain_id,
            tuple(binding["boss_id"] for binding in bindings),
            trial.realm_id,
            trial.index,
            bindings,
        ),
        written,
        "encounter",
        force,
    ):
        _check_encounter(path, trial.boss_ids, bindings)
    # The folded file goes only once the replacement is complete. A gap leaves the
    # winner holding fewer bosses than the domain declares, and deleting the loser
    # then would turn a loud `validate` failure into a silent content hole.
    if gaps:
        return gaps
    _retire_folded(graph, existing, written)
    return gaps


def _complete_encounter(path: Path, missing: list[str], bindings: list[dict]) -> bool:
    """Add `missing` bosses and their bindings to an authored encounter in place.

    The alternative is folding the encounter into a generated one, and folding is
    the wrong answer for a world domain: the fold replaces the author's bands with
    the two generated ones, and a band declares a rarity that `_promote` takes the
    **maximum** of against each entry's own floor. A `legendary` band whose table
    entries only floor at `rare` therefore hands out `legendary` drops, and folding
    it into a `common`/`rare` pair silently downgrades every one of them.

    So the author's bands, their rarity, their vitality and their existing bindings
    are all preserved verbatim and the missing bosses are appended. The edit is
    purely additive and is verified by reading the file back, so a shape this does
    not understand is reported rather than rewritten.
    """
    text = path.read_text(encoding="utf-8")
    entries = "".join(
        "\t"
        + "{"
        + ", ".join(
            f'"{key}": {emit.name(value) if isinstance(value, str) else value}'
            for key, value in binding.items()
        )
        + "},\n"
        for binding in bindings
    )
    boss_line = ", ".join(emit.name(boss_id) for boss_id in missing)
    blocks = 0
    out_lines: list[str] = []
    inside = False
    for line in text.splitlines(keepends=True):
        if line.startswith("boss_ids = Array[StringName](["):
            out_lines.append(line.rstrip("\n").replace("])", f", {boss_line}])") + "\n")
            continue
        if line.startswith("boss_tables = Array[Dictionary](["):
            inside = True
            out_lines.append(line)
            continue
        if inside:
            if line.startswith("])"):
                inside = False
                blocks += 1
                out_lines.append(line)
                continue
            if line.strip() == "":
                out_lines.append(line)
                continue
            out_lines.append(line)
            if line.rstrip().endswith("}),"):
                out_lines.append(entries)
            continue
        out_lines.append(line)
    if blocks == 0:
        return False
    path.write_text("".join(out_lines), encoding="utf-8")
    reread = path.read_text(encoding="utf-8")
    return all(
        boss_id in string_array(reread, "boss_ids")
        and any(
            unquote(str(binding.get("boss_id", ""))) == boss_id
            for chunk in sub_resources(reread)
            if "boss_tables" in chunk
            for binding in read_bindings(chunk, "boss_tables")
        )
        for boss_id in missing
    )


def _owns_table(table_id: str, boss_id: str) -> bool:
    """Whether `table_id` is this generator's own output for `boss_id`.

    Naming, not authorship: a table following the design's id scheme for this boss
    was produced by [method _boss_entries] or [method _pool_entries], so
    regenerating it re-applies a decision rather than overwriting somebody's. A
    `loot_route_*` id follows a different scheme and is a hand decision.
    """
    return table_id == design.table_id(boss_id) or table_id.startswith(
        f"{design.TABLE_PREFIX}{boss_id}{design.POOL_SUFFIX}"
    )


def _retire_folded(graph: Graph, existing: Encounter | None, written: Written) -> None:
    """Delete a folded encounter's file, once its replacement reads back.

    Deletion is last because it is the one irreversible step: while both files
    exist the domain carries two encounters, which `acquisition validate` names
    loudly, whereas a deleted table that nothing replaced is a silent hole. The
    replacement is written and verified by the caller before this runs, so the
    loser's bindings are already carried over.
    """
    if existing is None or not design.supersedes(existing.encounter_id):
        return
    if not existing.path.is_file():
        return
    existing.path.unlink()
    written.deleted.append(existing.path.name)


def _boss_items(graph: Graph, boss_id: str) -> list[str]:
    """Every item `boss_id` drops: its legacy list, plus what its tables hold.

    Every table the boss is *bound* to, not only the one named after it. Migrating
    a boss empties its legacy `loot` array, so a re-run sees an empty list and
    would regenerate a table with nothing but its catalysts — quietly dropping the
    migrated loot on the floor. Reading the bound tables back makes a re-run
    reproduce the same content instead of a smaller one, and covers the bosses
    whose table carries a `loot_route_*` id carried over from a folded encounter.
    """
    items = set(graph.boss_loot(boss_id))
    for table_id in (design.table_id(boss_id), *graph.bound_table_ids(boss_id)):
        if table_id in graph.loot_tables:
            items |= reachable_items(graph, table_id)
    return sorted(items)


def _boss_entries(
    graph: Graph, trial: Trial, boss_id: str, written: Written, force: bool
) -> list[emit.Entry]:
    """A boss's table: its catalysts guaranteed, its migrated loot as pools.

    The catalysts are guaranteed because a cleared band grants no second run
    (loot rule E2), so a catalyst left to a roll can leave a player permanently
    unable to reach the next realm. They are read through
    [method Graph.catalysts_for] rather than off `trial`, because a guardian that
    gates a realm's breakthrough lives in a grouped domain the realm seed never
    names — asking the hosting trial would answer nothing and leave the reagent
    that gates the whole ladder to a roll. Everything else migrates as a weighted
    draw into a realm pool, which keeps each item rolling at its own authored realm
    instead of inheriting the trial's.

    A catalyst whose own realm is the trial's stays a **direct** guaranteed
    entry, because a direct entry rolls at the band's realm and the band is this
    realm — the shape every body trial already ships, unchanged. A catalyst
    belonging to *another* realm cannot: a `LootTier` declares one realm and the
    qi ladder groups three realms' guardians into one domain, so a direct entry
    would hand out two thirds of that domain's breakthrough reagents scaled at the
    wrong rung. Those go into their own realm's pool, where `LootResolver` takes
    the innermost table's realm over the band's.
    """
    catalysts = graph.catalysts_for(boss_id)
    entries: list[emit.Entry] = []
    pooled: list[str] = []
    for index, item_id in enumerate(catalysts):
        if _catalyst_realm(graph, item_id, trial.realm_id) == trial.realm_id:
            entries.append(
                emit.Entry(
                    f"{boss_id}_core_{index}",
                    item_id=item_id,
                    guaranteed=True,
                    quantity=design.CATALYST_QUANTITY,
                    rarity_floor=graph.item_field(item_id, "rarity"),
                )
            )
        else:
            pooled.append(item_id)
    legacy = [item for item in _boss_items(graph, boss_id) if item not in catalysts]
    buckets: dict[str, list[str]] = {}
    for item_id in legacy:
        buckets.setdefault(graph.item_field(item_id, "realm") or "", []).append(item_id)
    for item_id in pooled:
        buckets.setdefault(_catalyst_realm(graph, item_id, trial.realm_id), []).append(item_id)
    for realm_id in sorted(buckets):
        pool = _pool_entries(graph, boss_id, realm_id, buckets[realm_id], set(catalysts))
        if not pool:
            # Every item in this realm is route-limited to a different boss, so a
            # pool here could only resolve to refused drops. No file, no entry.
            continue
        pool_id = design.pool_id(boss_id, realm_id or design.UNREALMED)
        pool_path = TABLE_DIR / f"{pool_id}.tres"
        if _write(
            pool_path,
            emit.table(
                pool_id,
                f"{graph.boss_display_name(boss_id) or boss_id} salvage ({realm_id})",
                pool,
                realm=realm_id,
            ),
            written,
            "table",
            force,
        ):
            _check_table(pool_path, pool_id)
        entries.append(
            emit.Entry(f"{boss_id}_pool_{realm_id or design.UNREALMED}", table_id=pool_id)
        )
    return entries


def _catalyst_realm(graph: Graph, item_id: str, band: str) -> str:
    """The realm a catalyst should realize at, falling back to the band.

    A catalyst with no authored realm inherits the band, which is correct only
    because a band belongs to exactly one realm — so the fallback is the band's
    own id, never an empty string that a `LootTier` would reject.
    """
    return graph.item_field(item_id, "realm") or band


def _pool_entries(
    graph: Graph, boss_id: str, realm_id: str, items: list[str], catalysts: set[str]
) -> list[emit.Entry]:
    """One realm's worth of a boss's table, minus another boss's route.

    A catalyst in the bucket stays a guaranteed entry inside the pool: the pool
    resolves it whenever it is reached, which is as unconditional as a direct one,
    and it is the only place a foreign-realm catalyst can carry its own realm.
    """
    entries = []
    for index, item_id in enumerate(items):
        # A route-limited item may only drop from the boss it names. Listing it
        # under a different boss resolves to a refused drop with a warning, so it
        # is left out and the real owner keeps the claim.
        routes = [tag.split(design.ROUTE_TAG, 1)[1] for tag in graph.item_tags(item_id)]
        if routes and boss_id not in routes:
            continue
        entries.append(
            emit.Entry(
                f"{boss_id}_{realm_id}_{index}",
                item_id=item_id,
                guaranteed=item_id in catalysts,
                quantity=design.CATALYST_QUANTITY if item_id in catalysts else 1,
                rarity_floor=graph.item_field(item_id, "rarity"),
            )
        )
    return entries


def _retire_legacy_loot(graph: Graph, boss_id: str, written: Written) -> None:
    """Empty a boss's `loot` array: the table is now its single authority.

    The loot validator rejects a boss carrying both an authored binding and a
    populated legacy list, because those are two independent answers to "what
    does this boss drop". Nothing is lost: every item of the list is now an entry
    of the table this command just wrote.
    """
    record = graph.bosses.get(boss_id)
    if not record or not graph.boss_loot(boss_id):
        return
    path = graph.root / record["path"]
    if not path.is_file():
        return
    path.write_text(
        _merge_array_block(path.read_text(encoding="utf-8"), "loot", []), encoding="utf-8"
    )
    written.retired.append(boss_id)


def _write(path: Path, content: str, written: Written, bucket: str, force: bool) -> bool:
    """Write a generated file, or leave an existing one and report it as authored.

    A collision means a hand-written file already claims this id, which is a
    decision somebody made; overwriting it would delete the decision silently.
    `force` overwrites only when the existing file declares the same id, so a
    refresh can never reach content this generator did not write. Returns whether
    the file on disk is now the content this run produced.
    """
    if path.exists():
        if not force or resource_scalar(path.read_text(encoding="utf-8"), "id") != resource_scalar(
            content, "id"
        ):
            written.kept.append(path.stem)
            return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    list_ = written.encounters if bucket == "encounter" else written.tables
    list_.append(path.stem)
    return True


def _check_table(path: Path, table_id: str) -> None:
    """Read a written table back and prove it names the ids it was built from.

    A `.tres` that does not round-trip fails at run time, not at authoring time,
    and the failure names a parser error rather than the generator that produced
    it. Reading the file back with the same parser the validator uses is the only
    cheap moment where that is still catchable.
    """
    reread = path.read_text(encoding="utf-8")
    if resource_scalar(reread, "id") != table_id:
        raise ToolError(f"wrote {path.name} but it does not declare id '{table_id}'")
    entries = sub_resources(reread)
    if not entries:
        raise ToolError(f"wrote {path.name} with no readable entry")
    for chunk in entries:
        if not scalar(chunk, "item_id") and not scalar(chunk, "table_id"):
            raise ToolError(f"wrote {path.name} with an entry naming neither item nor table")


def _check_encounter(path: Path, boss_ids: tuple[str, ...], bindings: list[dict]) -> None:
    """Read a written encounter back and prove it says what it was asked to.

    Same reason as `_check_table`: a malformed `boss_tables` array parses at
    authoring time and fails to load at run time.
    """
    reread = path.read_text(encoding="utf-8")
    if string_array(reread, "boss_ids") != boss_ids:
        raise ToolError(f"wrote {path.name} but it does not list its bosses back")
    bands = [chunk for chunk in sub_resources(reread) if "boss_tables" in chunk]
    if len(bands) != len(design.TIERS):
        raise ToolError(f"wrote {path.name} with {len(bands)} band(s), expected {design.TIERS}")
    wanted = [str(binding["boss_id"]) for binding in bindings]
    for chunk in bands:
        found = [
            unquote(str(entry.get("boss_id", ""))) for entry in read_bindings(chunk, "boss_tables")
        ]
        if found != wanted:
            raise ToolError(f"wrote {path.name} but its band bindings do not read back")
