"""Assert the shape of the generated acquisition content.

Every check is content-shaped: it answers "could a player walk the authored sources
to a terminal", never "is this fun". The shape is asserted, not the recipe that
filled it, so a hand-written encounter satisfying every rule is as acceptable as a
generated one.

The rules restate, in one place, what the runtime already enforces:

  - a boss named by a `boss:` source must appear in an authored encounter, or the
    source is a claim nothing can deliver;
  - every band of that encounter must bind the boss to a table that resolves;
  - the boss's own `loot` array must be empty, or it is a second authority for a
    question its table already answers;
  - a catalyst must be reachable as a `guaranteed` entry, because a cleared band
    grants no second run and a rolled catalyst can soft-lock the path. That holds
    for every table the encounter binds, not only the catalyst's own;
  - a band must guarantee enough of each catalyst to craft the realm's three
    recipes, because a guaranteed entry is paid once at its exact quantity;
  - one domain carries at most one encounter, and every `loot_route_*` table is
    bound by a band. Both are invisible to a walk that reads the first match: the
    loser looks fine while its content is unreachable.
"""

from __future__ import annotations

from typing import NamedTuple

from .chain import Encounter, Graph, Trial, unquote
from .design import ROUTE_PREFIX
from .loot import guaranteed_items, guaranteed_quantities, reachable_items

# A realm's three recipes (breakthrough, strengthening, recovery) each consume one
# of each of their two reagents, so a band has to yield three of every catalyst
# before the next realm is craftable at all.
MIN_CRAFTS_PER_REALM = 3


def validate(graph: Graph) -> list[str]:
    """Every problem found, named by trial and boss. Empty means clean."""
    problems: list[str] = []
    hosted = graph.hosted_bosses()
    for trial in sorted(graph.all_trials, key=lambda entry: (entry.path, entry.index)):
        problems.extend(_trial_problems(graph, trial, hosted))
    problems.extend(_content_problems(graph))
    problems.extend(_loader_problems(graph))
    return problems


def _content_problems(graph: Graph) -> list[str]:
    """The facts a per-realm walk cannot see, because it only ever reads one.

    `encounter_for_domain` answers with the first match, so a second encounter for a
    domain is invisible to every other check: the winner looks perfect while the
    loser sits on disk holding a boss nothing can spawn. And a table nothing binds is
    a silent hole — its drops are unreachable, but nothing reports an absence.

    The loot validator rejects both at run time. This names them at authoring time,
    which is the only moment the file that caused them can still be found.
    """
    problems: list[str] = []
    claims: dict[str, list[str]] = {}
    bound: set[str] = set()
    for encounter in graph.encounters.values():
        claims.setdefault(encounter.domain_id, []).append(encounter.encounter_id)
        for tier in encounter.tiers:
            problems.extend(_band_agreement_problems(encounter, tier))
            for boss_id in encounter.boss_ids:
                table_id = graph.table_for(encounter, tier, boss_id)
                if table_id:
                    bound.add(table_id)
    for domain_id, ids in sorted(claims.items()):
        if len(ids) > 1:
            problems.append(
                f"domain {domain_id}: {len(ids)} encounters "
                f"({', '.join(sorted(ids))}); one domain carries at most one"
            )
    # The other direction, and the one that actually strands drops: an encounter
    # checks that every boss it lists appears on the domain, but nothing checks
    # that the domain's other bosses are listed at all. A domain can therefore
    # declare two bosses, have an authored encounter for one of them, and leave the
    # other's drops behind nothing — which is the shape the last unhosted boss in
    # the corpus has, and it is invisible to every check that reads one encounter.
    for encounter in graph.encounters.values():
        spawned = set(encounter.boss_ids)
        for boss_id in graph.domain_bosses(encounter.domain_id):
            if boss_id not in spawned:
                problems.append(
                    f"domain {encounter.domain_id}: declares boss '{boss_id}', which "
                    f"{encounter.encounter_id} never spawns, so its "
                    f"{len(graph.boss_drops(boss_id))} drop(s) are unreachable"
                )
    for table_id in sorted(t for t in graph.loot_tables if t.startswith(ROUTE_PREFIX)):
        if table_id not in bound:
            problems.append(
                f"table {table_id}: no band binds it, so the drops it holds are unreachable"
            )
    problems.extend(_domain_route_problems(graph))
    return problems


def _domain_route_problems(graph: Graph) -> list[str]:
    """A `domain:` route must name a domain an encounter can actually deliver from.

    The mirror of the `boss:` rule the module docstring states. `ItemSources` calls
    `domain` a **shipped** kind — the reader resolves it — so a `domain:` ref is a
    delivery claim, and 6540 of them across 160 domains were being read by nothing
    here. That is not a small omission: it is the half of the drop graph that made
    DEF-0188 call 41 items unobtainable when a domain was handing out every one of
    them, because the analysis that produced it walked `boss:` refs only.

    It stays a *reachability* rule and is deliberately not a guarantee rule. A
    domain that pays an item by a roll is reachable, and the guarantee question is
    already asked where it belongs — [method Trial.catalysts] over `boss:` routes,
    and [method _band_problems] over every table a band binds. Demanding
    unconditional delivery here instead would not describe the content, it would
    demand 41 new guaranteed entries across a corpus that authors `domain:` drops as
    ordinary rolls.
    """
    return [
        f"item {item_id}: declares route 'domain:{domain_id}', which no authored "
        f"encounter can deliver from ({_why_unpayable(graph, domain_id)}), so the "
        f"source is a claim nothing pays"
        for item_id, domain_id in graph.unpayable_domain_routes()
    ]


def _why_unpayable(graph: Graph, domain_id: str) -> str:
    """Which of the three failures made a `domain:` route unpayable.

    Reported rather than counted, because "your route points nowhere" and "your
    route points at a boss one band forgot to bind" are different authoring mistakes
    and a validator that merges them names only the first.
    """
    if domain_id not in graph.domains:
        return f"no domain '{domain_id}' exists"
    if graph.encounter_for_domain(domain_id) is None:
        return f"domain '{domain_id}' has no authored encounter"
    unbound = graph.unbound_delivery_bosses(domain_id)
    if unbound:
        return (
            f"domain '{domain_id}' spawns boss '{unbound[0]}' with no table bound on "
            f"every band, and a cleared band is never re-run"
        )
    return f"domain '{domain_id}' binds no boss that can deliver"


def _band_agreement_problems(encounter: Encounter, tier: dict) -> list[str]:
    """A band and its encounter must name the same bosses, in both directions.

    `LootValidator` rejects either half ("does not bind boss '<id>'", "binds boss
    '<id>' which the encounter does not list"), but only when the engine loads the
    content. Nothing in the Python gates could see it, because the walk that judges
    bindings is the *catalyst* walk: it reads `trial.catalysts`, and a world trial
    has none, so all 68 world encounters' bands were unchecked on both sides.

    Both directions matter and they fail differently. A boss listed but unbound is
    a boss `enter_domain` spawns with no table, so its declared drops are
    undeliverable. A boss bound but unlisted is worse for the acquisition graph: the
    binding still credits the boss with every item its table holds, so an item
    declaring `boss:<id>` passes `data audit` on the strength of a boss the
    encounter never spawns. Both were verified as mutations that leave the gate
    green, and both are now named here.
    """
    listed = set(encounter.boss_ids)
    bound = {unquote(str(binding.get("boss_id", ""))) for binding in tier["bindings"]}
    problems: list[str] = []
    for boss_id in sorted(listed - bound):
        problems.append(
            f"{encounter.encounter_id} band {tier['tier']}: lists boss '{boss_id}' but "
            f"binds no table for it, so its drops are undeliverable"
        )
    for boss_id in sorted(bound - listed):
        problems.append(
            f"{encounter.encounter_id} band {tier['tier']}: binds boss '{boss_id}' which "
            f"the encounter does not list, so enter_domain never spawns it"
        )
    return problems


class _Boss(NamedTuple):
    boss_id: str
    catalysts: tuple[str, ...]


def _trial_problems(graph: Graph, trial: Trial, hosted: set[str]) -> list[str]:
    label = f"{trial.trial_id} ({trial.domain_id})"
    encounter = graph.encounter_for_domain(trial.domain_id)
    if encounter is None:
        return [f"{label}: no authored encounter, so LootApi.enter_domain refuses it"]
    problems: list[str] = []
    if trial.ladder and not trial.consumables:
        return [f"{label}: no consumable resolves from its seed"]
    missing = [boss for boss in trial.boss_ids if boss not in encounter.boss_ids]
    if missing:
        problems.append(f"{label}: the encounter omits authored boss(es) {', '.join(missing)}")
    if len(encounter.tiers) < 2:
        problems.append(
            f"{label}: {len(encounter.tiers)} band(s); a cleared band grants no second "
            "run, so a catalyst has to be reachable more than once"
        )
    problems.extend(_band_realm_problems(graph, trial, encounter))
    if not trial.ladder:
        return problems
    for boss_id, catalysts in trial.catalysts.items():
        host = graph.encounter_hosting(boss_id)
        if host is None:
            problems.append(
                f"{label}: catalyst boss '{boss_id}' is in no encounter, so "
                "LootApi.enter_domain cannot spawn it"
            )
            continue
        # Judged against the encounter that actually hosts the boss. A reagent
        # shared across two ladders drops from the other ladder's trial, and a
        # check against this trial's bands would demand a binding nothing reads.
        problems.extend(_boss_problems(graph, trial.trial_id, host, _Boss(boss_id, catalysts)))
        problems.extend(_supply_problems(label, host, set(catalysts), graph))
    problems.extend(_band_problems(label, encounter, trial, graph))
    return problems


def _band_realm_problems(graph: Graph, trial: Trial, encounter: Encounter) -> list[str]:
    """A band must be labelled with the realm the trial walks, or the lowest one.

    A ladder trial has exactly one realm, so its bands must carry it: a band that
    rolls at another realm hands out loot scaled above its authored magnitude. A
    world trial owns no realm, so its label is the derived conservative default
    and the rule is that the file still reads back as what the generator decided —
    a band carrying an unrelated realm is a hand edit that would mis-scale every
    direct entry on the domain's tables.
    """
    problems: list[str] = []
    for tier in encounter.tiers:
        if tier["realm"] == trial.realm_id:
            continue
        problems.append(
            f"{trial.trial_id}: band {tier['tier']} is labelled realm "
            f"'{tier['realm']}' where the trial walks '{trial.realm_id}'"
        )
    return problems


def _band_problems(label: str, encounter: Encounter, trial: Trial, graph: Graph) -> list[str]:
    """No table bound on any band may leave one of the trial's catalysts to a roll.

    The per-catalyst-boss rule above only judges the catalyst's OWN table, which
    is not the whole exposure: an encounter also binds sibling bosses, and a
    sibling's table can list a reagent of the same recipe. A band that yields a
    catalyst by roll is a second way to miss it, and a cleared band grants no
    second run (rule E2), so the miss is permanent.

    Only the catalysts hosted *here* count, and only where their own boss is bound
    on this encounter's bands: a catalyst whose boss lives in another domain is
    another encounter's business and is judged there.

    A table that cannot yield the catalyst at all is another boss's business and is
    left alone: not every boss in a trial has to carry every reagent.
    """
    here = {boss_id for boss_id in trial.catalysts if graph.encounter_hosting(boss_id) is encounter}
    wanted = {item for boss_id in here for item in trial.catalysts[boss_id]}
    if not wanted:
        return []
    # Tables already judged by `_boss_problems`, which names the boss as well and so
    # reports the same fact more precisely. Checked once: a table bound on both
    # bands is one table, not two.
    judged = {
        graph.table_for(encounter, tier, boss_id)
        for boss_id in here
        for tier in encounter.tiers
        if graph.table_for(encounter, tier, boss_id)
    }
    problems: list[str] = []
    seen: set[str] = set()
    for tier in encounter.tiers:
        for boss_id in encounter.boss_ids:
            table_id = graph.table_for(encounter, tier, boss_id)
            if not table_id or table_id in seen or table_id in judged:
                continue
            seen.add(table_id)
            reachable = reachable_items(graph, table_id)
            if not reachable & wanted:
                continue
            rolled = sorted(item for item in wanted & reachable - guaranteed_items(graph, table_id))
            if rolled:
                problems.append(
                    f"{label}: {table_id} (band {tier['tier']}, {boss_id}) only rolls "
                    f"catalyst {', '.join(rolled)}; a cleared band grants no second "
                    "run, so a roll can soft-lock the path"
                )
    problems.extend(_supply_problems(label, encounter, wanted, graph))
    return problems


def _supply_problems(label: str, encounter: Encounter, wanted: set[str], graph: Graph) -> list[str]:
    """One band must yield enough of each catalyst to craft a realm's whole recipes.

    Guaranteed is not sufficient on its own: a resolve pays a guaranteed entry once
    at its exact quantity, the draw count does not multiply it, and the acquisition
    walk clears only the lowest band. A catalyst guaranteed at one unit a band is
    therefore craftable once and never again — the same permanent stall as a rolled
    one, one step later. A realm's three recipes each consume one of each reagent,
    so three is the floor.
    """
    problems: list[str] = []
    for tier in encounter.tiers:
        supply: dict[str, int] = {}
        for boss_id in encounter.boss_ids:
            table_id = graph.table_for(encounter, tier, boss_id)
            if not table_id:
                continue
            for item_id, count in guaranteed_quantities(graph, table_id).items():
                if item_id in wanted:
                    supply[item_id] = supply.get(item_id, 0) + count
        short = sorted(
            f"{item} ({supply.get(item, 0)}/{MIN_CRAFTS_PER_REALM})"
            for item in wanted
            if supply.get(item, 0) < MIN_CRAFTS_PER_REALM
        )
        if short:
            problems.append(
                f"{label}: band {tier['tier']} guarantees too little of "
                f"{', '.join(short)}; a realm's {MIN_CRAFTS_PER_REALM} recipes consume "
                "one each and a cleared band is never re-run"
            )
    return problems


def _boss_problems(graph: Graph, trial_id: str, encounter: Encounter, boss: _Boss) -> list[str]:
    label = f"{trial_id}: boss {boss.boss_id}"
    problems: list[str] = []
    if graph.boss_loot(boss.boss_id):
        problems.append(
            f"{label}: carries a legacy loot array and an authored table, so two "
            "authorities answer what it drops"
        )
    for tier in encounter.tiers:
        table_id = graph.table_for(encounter, tier, boss.boss_id)
        if not table_id:
            problems.append(f"{label}: band {tier['tier']} binds no table for it")
            continue
        if table_id not in graph.loot_tables:
            problems.append(f"{label}: band {tier['tier']} names '{table_id}', unresolved")
            continue
        problems.extend(_catalyst_problems(label, tier, table_id, boss.catalysts, graph))
    return problems


def _catalyst_problems(
    label: str, tier: dict, table_id: str, catalysts: tuple[str, ...], graph: Graph
) -> list[str]:
    band = f"band {tier['tier']}"
    reachable = reachable_items(graph, table_id)
    absent = [item for item in catalysts if item not in reachable]
    if absent:
        return [
            f"{label}: {band} never drops catalyst {', '.join(absent)}, which the realm's "
            "recipe needs"
        ]
    guaranteed = guaranteed_items(graph, table_id)
    rolled = [item for item in catalysts if item not in guaranteed]
    if rolled:
        return [
            f"{label}: {band} only rolls catalyst {', '.join(rolled)}; a cleared band grants "
            "no second run, so a roll can soft-lock the path"
        ]
    return []


def _loader_problems(graph: Graph) -> list[str]:
    """A `.tres` the corpus loader could not name is a silent hole in the answer.

    Every downstream answer would be quietly smaller without it, so it is named
    rather than counted away.
    """
    relevant = sorted(
        name
        for name in graph.malformed
        if name.startswith(("items", "recipes", "bosses", "domains", "loot"))
    )
    if not relevant:
        return []
    listed = ", ".join(relevant[:5])
    more = f" (+{len(relevant) - 5} more)" if len(relevant) > 5 else ""
    return [f"malformed acquisition content: {listed}{more}"]
