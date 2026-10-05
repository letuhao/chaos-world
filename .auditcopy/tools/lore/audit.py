"""Contradiction, duplication, isolation and gap detection.

These are the checks that make "a lot of lore" mean something. Volume is not the
goal; the goal is that a new character can be traced backwards through causes. A
bible with four hundred disconnected entries fails the real test while passing
every schema check, so the checks here are about *structure*: does this thing
hang together, is it doing a job nothing else does, and is anything missing that
the next wave should write.

The near-duplicate check is deliberately structural rather than lexical. Five
hundred differently named sword sects is the exact monoculture this program is
supposed to avoid, and a name-similarity test rates it as perfect diversity
because every name is distinct. So similarity is measured over type, tags and
attribute shape instead.
"""

from __future__ import annotations

import re
from collections import Counter, defaultdict
from itertools import combinations

from ..common import ToolError
from .model import (
    Bible,
    Edge,
    normalised_entropy,
    validate_edges,
    validate_entities,
    validate_external_refs,
)

# Above this Jaccard score two same-domain entities of the same type are treated
# as doing the same job under different names.
STRUCTURAL_DUP_THRESHOLD = 0.8
# Above this, two names are close enough to be worth a human look.
NAME_DUP_THRESHOLD = 0.7
# A domain with more than this many entities and a scaled entropy below
# MONOCULTURE_ENTROPY is reported as monocultural.
MONOCULTURE_MIN_ENTITIES = 8
MONOCULTURE_ENTROPY = 0.45
# A tag held by more than this share of a domain's entities is overused.
OVERUSED_TAG_SHARE = 0.35

_WORD_RE = re.compile(r"[a-z0-9]+")


def _tokens(text: str) -> set[str]:
    stop = {"the", "of", "and", "a", "an", "in", "at", "for", "to"}
    return {word for word in _WORD_RE.findall(text.lower()) if word not in stop}


def _jaccard(left: set[str], right: set[str]) -> float:
    if not left or not right:
        return 0.0
    return len(left & right) / len(left | right)


# --- contradictions ---------------------------------------------------------


def contradictions(bible: Bible) -> list[str]:
    issues: list[str] = []
    issues += _exclusive_relations(bible)
    issues += _exclusive_statuses(bible)
    issues += _containment_cycles(bible)
    issues += _ancestry_cycles(bible)
    issues += _timeline_disagreements(bible)
    return issues


def _exclusive_relations(bible: Bible) -> list[str]:
    """Two parties cannot be allied and at war, and cannot belong and wage war.

    Declared in the registry rather than hardcoded so a new relation states its own
    exclusions instead of needing this function edited.
    """
    issues: list[str] = []
    pairs: dict[frozenset[str], set[str]] = defaultdict(set)
    witnesses: dict[tuple[frozenset[str], str], Edge] = {}
    for edge in bible.edges:
        if edge.source == edge.target:
            continue
        key = frozenset({edge.source, edge.target})
        pairs[key].add(edge.rel)
        witnesses[(key, edge.rel)] = edge
    for key, rels in sorted(pairs.items(), key=lambda item: sorted(item[0])):
        for rel_a, rel_b in combinations(sorted(rels), 2):
            relation = bible.registry.relations.get(rel_a)
            if not relation:
                continue
            if (
                rel_b in relation.exclusive_with
                or rel_a in bible.registry.relations.get(rel_b, relation).exclusive_with
            ):
                issues.append(
                    f"{sorted(key)[0]} and {sorted(key)[1]} are both {rel_a} and {rel_b}, "
                    f"which the registry declares exclusive "
                    f"({witnesses[(key, rel_a)].origin} vs {witnesses[(key, rel_b)].origin})"
                )
    return issues


def _exclusive_statuses(bible: Bible) -> list[str]:
    issues: list[str] = []
    for first, second in bible.registry.exclusive_status_pairs():
        actives = {e["id"] for e in bible.entities.values() if e.get("status") == first}
        others = {e["id"] for e in bible.entities.values() if e.get("status") == second}
        for entity_id in sorted(actives & others):
            issues.append(f"{entity_id}: reported as both {first} and {second}")
    return issues


def _containment_cycles(bible: Bible) -> list[str]:
    """`located_in` must be a forest.

    A cycle here is not a stylistic choice, it is a place that is inside itself,
    and every traversal, containment query and region lookup downstream inherits
    the loop.
    """
    return _cycles(bible, {"located_in"})


def _ancestry_cycles(bible: Bible) -> list[str]:
    """Descent must be acyclic: nobody is their own grandparent."""
    return _cycles(bible, {"descended_from", "hybrid_of", "founded_by"})


def _cycles(bible: Bible, rels: set[str]) -> list[str]:
    issues: list[str] = []
    graph: dict[str, list[str]] = defaultdict(list)
    for edge in bible.edges:
        if edge.rel in rels:
            graph[edge.source].append(edge.target)
    state: dict[str, int] = {}

    def walk(node: str, trail: list[str]) -> None:
        if state.get(node) == 2:
            return
        if state.get(node) == 1:
            cycle = trail[trail.index(node) :] if node in trail else trail
            issues.append(" -> ".join([*cycle, node]))
            return
        state[node] = 1
        for neighbour in sorted(graph.get(node, ())):
            walk(neighbour, [*trail, node])
        state[node] = 2

    for node in sorted(graph):
        walk(node, [])
    return [f"cycle in {sorted(rels)}: {cycle}" for cycle in sorted(set(issues))]


def _timeline_disagreements(bible: Bible) -> list[str]:
    """`preceded_by` must agree with the numeric order the records carry.

    Prose chronology drifts; a number does not. When the two disagree the bible
    has two answers to "what happened when", and anything generated from it
    inherits a coin flip.
    """
    issues: list[str] = []
    orders: dict[str, float] = {}
    for entity_id, entity in bible.entities.items():
        attributes = entity.get("attributes")
        if not isinstance(attributes, dict):
            continue
        order = attributes.get("order")
        if isinstance(order, (int, float)) and not isinstance(order, bool):
            orders[entity_id] = float(order)
    for edge in bible.edges:
        if edge.rel != "preceded_by":
            continue
        before, after = orders.get(edge.source), orders.get(edge.target)
        if before is None or after is None:
            continue
        if before >= after:
            issues.append(
                f"{edge.source} (order {before:g}) precedes {edge.target} "
                f"(order {after:g}), which the numbers contradict"
            )
    return issues


# --- duplication ------------------------------------------------------------


def duplicate_names(bible: Bible) -> list[str]:
    """Two hand-authored entities in one domain sharing a name are the same thing twice.

    Entities that arrived by import carry an `external_ref` and are EXEMPT. The
    authored tree really does contain six distinct "Ascension Warden" bosses and
    four distinct "Storm Phoenix Domain" trials, differing by cultivation path and
    by which realm gate they sit behind; failing those would mean deleting or
    renaming real content, and neither is this program's business. Shared labels on
    imported content are still worth seeing, so `shared_labels` reports them as a
    signal for the next wave rather than a build failure.
    """
    issues: list[str] = []
    by_domain: dict[str, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))
    for entity_id, entity in bible.entities.items():
        name = entity.get("name")
        if isinstance(name, str) and name.strip() and not entity.get("external_ref"):
            by_domain[entity.get("domain", "?")][name.strip().lower()].append(entity_id)
    for domain, names in sorted(by_domain.items()):
        for name, ids in sorted(names.items()):
            if len(ids) > 1:
                issues.append(
                    f"{domain}: {len(ids)} entities named {name!r}: {', '.join(sorted(ids))}"
                )
    return issues


def shared_labels(bible: Bible) -> list[str]:
    """Report-only: imported entities that share a display name.

    Not a defect, because the authored tree intends them. But a domain where four
    entities are all called "Storm Phoenix Domain" is a domain whose authors will
    confuse each other, so the next wave needs to know before it writes prose that
    refers to them by name.
    """
    by_domain: dict[str, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))
    for entity_id, entity in bible.entities.items():
        name = entity.get("name")
        if isinstance(name, str) and name.strip() and entity.get("external_ref"):
            by_domain[entity.get("domain", "?")][name.strip().lower()].append(entity_id)
    findings: list[str] = []
    for domain, names in sorted(by_domain.items()):
        for name, ids in sorted(names.items()):
            if len(ids) > 1:
                findings.append(
                    f"{domain}: {len(ids)} imported entities share the label {name!r}: "
                    + ", ".join(sorted(ids))
                )
    return findings


def near_duplicate_names(bible: Bible) -> list[str]:
    issues: list[str] = []
    by_domain: dict[str, list[dict]] = defaultdict(list)
    for entity in bible.entities.values():
        by_domain[entity.get("domain", "?")].append(entity)
    for domain, entities in sorted(by_domain.items()):
        if len(entities) > 60:
            continue
        for left, right in combinations(sorted(entities, key=lambda e: e["id"]), 2):
            score = _jaccard(_tokens(left.get("name", "")), _tokens(right.get("name", "")))
            if score >= NAME_DUP_THRESHOLD:
                issues.append(
                    f"{domain}: {left['id']} and {right['id']} have near-identical names "
                    f"(score {score:.2f}): {left.get('name')!r} / {right.get('name')!r}"
                )
    return issues


def structural_duplicates(bible: Bible) -> list[str]:
    """Same domain, same type, same shape: the monoculture this program must avoid.

    Measured over `type`, tags and attribute keys, so five hundred sects that all
    answer to `type: martial-sect` with a `leader` and a `doctrine` attribute score
    as one idea wearing five hundred names - which a name-similarity test would
    score as perfect diversity.

    Imported entities are exempt, for the same reason `duplicate_names` exempts
    them. Uniformity is the POINT of a closed categorical set: all six world laws
    carry `group`, `value_min`, `value_max` because that is what a world law IS,
    and all three Daos carry `dao_alignment` and `home_tier` for the same reason.
    Flagging those would mean every future wave's cosmology work starts by ignoring
    the guard. The check targets what agents author, where variety is the
    requirement.
    """
    issues: list[str] = []
    by_bucket: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for entity in bible.entities.values():
        if entity.get("external_ref"):
            continue
        attributes = entity.get("attributes") if isinstance(entity.get("attributes"), dict) else {}
        shape = (
            _tokens(str(entity.get("type", "")))
            | {str(key) for key in attributes}
            | _tokens(" ".join(str(t) for t in entity.get("tags", []) or []))
        )
        by_bucket[(entity.get("domain", "?"), str(entity.get("type", "?")))].append(
            {**entity, "_shape": shape}
        )
    for (domain, kind), bucket in sorted(by_bucket.items()):
        if len(bucket) < 3:
            continue
        for left, right in combinations(sorted(bucket, key=lambda e: e["id"]), 2):
            score = _jaccard(left["_shape"], right["_shape"])
            if score >= STRUCTURAL_DUP_THRESHOLD:
                issues.append(
                    f"{domain}/{kind}: {left['id']} and {right['id']} have the same shape "
                    f"(score {score:.2f}); one of them is probably a renamed duplicate"
                )
    return issues


# --- isolation --------------------------------------------------------------


def isolated_entities(bible: Bible, *, limit: int = 40) -> list[str]:
    """Entities with no relationships at all.

    A dangling entry cannot be reached from a character walk, so it cannot inform
    one, and it will never appear in a traversal - which is how a lore bible grows
    a private wing nothing can reach.

    A whole collection of one type is reported once rather than listed entity by
    entity. The four imported races are each islands because the authored `.tres`
    files record no relationship between them; that is a real gap, but it is one
    the next wave closes by linking them, and naming it four times tells the reader
    nothing they cannot get from the count.

    Never fatal. `validate` reserves failure for what a writer must fix in the line
    they wrote - a dangling id, a bad slug, an exclusive-relation clash. Isolation
    is a measure of progress, not a defect, and a guard that fires on the starting
    state is a guard people learn to ignore.
    """
    orphans = sorted(entity_id for entity_id in bible.entities if bible.degree(entity_id) == 0)
    if not orphans:
        return []
    kinds = Counter(
        (bible.entities[entity_id].get("domain"), bible.entities[entity_id].get("type"))
        for entity_id in orphans
    )
    findings: list[str] = []
    singletons: list[str] = []
    for (domain, kind), count in sorted(kinds.items(), key=lambda item: str(item[0])):
        if count >= 3:
            findings.append(
                f"{count} {domain}/{kind} entities are unconnected to each other (authored data "
                "records no relationship between them; the next wave should link them)"
            )
        else:
            singletons.extend(
                entity_id
                for entity_id in orphans
                if (bible.entities[entity_id].get("domain"), bible.entities[entity_id].get("type"))
                == (domain, kind)
            )
    if singletons:
        shown = singletons[:limit]
        suffix = "" if len(singletons) <= limit else f" (+{len(singletons) - limit} more)"
        findings.append(f"{len(singletons)} unconnected entities{suffix}: " + ", ".join(shown))
    return findings


# --- coverage, diversity and gaps -------------------------------------------


def ungrounded(bible: Bible) -> list[str]:
    """Entities whose subject matter requires a place, with no place recorded.

    A race with no `native_to` geography, or a culture with no `located_in`, is a
    fact with no setting. It cannot ground a character - `lore context` walks
    outward from a species to find a homeland, and finds nothing - and it is
    invisible to every other check, because a species record with a superb summary
    and eight edges to other species validates perfectly while answering none of
    the questions a writer asks about it.

    Reported, never fatal: this is a hole to close, not a malformed line. The
    distinction that matters is that it is CHECKABLE, so a batch that fixes it can
    be shown to have fixed it.
    """
    requirements = {
        "races": ("native_to", "originated_from", "located_in"),
        "cultures": ("located_in", "native_to", "part_of"),
        "ecology": ("located_in", "native_to"),
        "organizations": ("located_in", "headquartered_in"),
    }
    findings: list[str] = []
    for domain, (place_rel, *alternatives) in sorted(requirements.items()):
        acceptable = {place_rel, *alternatives}
        for entity in sorted(bible.by_domain().get(domain, []), key=lambda item: item["id"]):
            if entity.get("external_ref"):
                continue
            entity_id = entity["id"]
            places = set()
            for rel, other, _edge in bible.out_edges.get(entity_id, ()):
                if rel in acceptable:
                    places.add(bible.entities.get(other, {}).get("domain"))
            # An incoming edge from a place counts: a settlement that houses a
            # culture has grounded it just as concretely as the reverse edge.
            for rel, other, _edge in bible.in_edges.get(entity_id, ()):
                if bible.registry.inverse(rel) in acceptable:
                    places.add(bible.entities.get(other, {}).get("domain"))
            if "geography" not in places and "cosmology" not in places:
                noun = {
                    "races": "race",
                    "cultures": "culture",
                    "ecology": "habitat",
                    "organizations": "seat",
                }[domain]
                findings.append(
                    f"{entity_id}: no {noun} is recorded anywhere - it exists "
                    "in the bible but not in the world"
                )
    return findings


def domain_coverage(bible: Bible) -> dict[str, dict]:
    coverage: dict[str, dict] = {}
    grouped = bible.by_domain()
    for domain, entities in sorted(grouped.items()):
        depths = Counter(
            (entity.get("attributes") or {}).get("lore_depth", "unknown") for entity in entities
        )
        coverage[domain] = {
            "entities": len(entities),
            "types": len({entity.get("type") for entity in entities}),
            "authored": depths.get("authored", 0),
            "sketched": depths.get("sketched", 0),
            "stub": depths.get("stub", 0),
            "edges": sum(bible.degree(entity["id"]) for entity in entities) // 2,
        }
    return coverage


def diversity(bible: Bible) -> dict[str, dict]:
    """Structural diversity per domain, plus the monoculture verdict.

    Three numbers, because each catches a different monoculture:
    - type entropy: are there genuinely different kinds of thing here?
    - tag entropy: do they differ in substance and not only in type?
    - edge density: does anything participate in the graph, or is it a list?
    """
    report: dict[str, dict] = {}
    grouped = bible.by_domain()
    tags_by_domain: dict[str, Counter] = defaultdict(Counter)
    for entity in bible.entities.values():
        for tag in entity.get("tags", []) or []:
            if isinstance(tag, str):
                tags_by_domain[entity.get("domain", "?")][tag] += 1
    for domain, entities in sorted(grouped.items()):
        total = len(entities)
        type_counts = Counter(entity.get("type", "?") for entity in entities)
        type_entropy = normalised_entropy(type_counts)
        tag_entropy = normalised_entropy(tags_by_domain[domain])
        degrees = [bible.degree(entity["id"]) for entity in entities]
        density = sum(degrees) / total if total else 0.0
        monocultural = total >= MONOCULTURE_MIN_ENTITIES and (
            type_entropy < MONOCULTURE_ENTROPY or tag_entropy < MONOCULTURE_ENTROPY
        )
        overused = [
            (tag, count)
            for tag, count in sorted(tags_by_domain[domain].items(), key=lambda kv: -kv[1])
            if total and count / total > OVERUSED_TAG_SHARE and count > 1
        ]
        report[domain] = {
            "entities": total,
            "type_entropy": type_entropy,
            "tag_entropy": tag_entropy,
            "edge_density": density,
            "monocultural": monocultural,
            "overused_tags": overused[:8],
        }
    return report


def gaps(bible: Bible) -> list[str]:
    """Deterministic work queue. The tool decides whether a gap exists.

    An agent that thinks something is missing should be able to check, and the
    answer has to be the same every time or two agents will both build the same
    filler.
    """
    issues: list[str] = []
    coverage = domain_coverage(bible)
    for domain, stats in sorted(coverage.items()):
        if stats["entities"] == 0:
            issues.append(f"EMPTY domain {domain}: nothing authored at all")
        elif stats["authored"] == 0 and stats["sketched"] == 0:
            issues.append(f"STUB domain {domain}: {stats['entities']} entities, none beyond a stub")
    stubs = sorted(
        entity_id
        for entity_id, entity in bible.entities.items()
        if (entity.get("attributes") or {}).get("lore_depth") == "stub"
    )
    for entity_id in stubs[:60]:
        issues.append(f"STUB entity {entity_id}: exists, carries no lore of its own")
    if len(stubs) > 60:
        issues.append(f"... and {len(stubs) - 60} further stub entities")
    for domain, stats in sorted(diversity(bible).items()):
        # `lore-gap` is on every stub by construction. Counting it as an overused
        # tag tells each brief to avoid the marker that means "write this", which
        # is the precise opposite of the intent - the agents most needed are the
        # ones filling gaps, and they are the ones carrying the tag.
        stats["overused_tags"] = [
            (tag, count) for tag, count in stats["overused_tags"] if tag != "lore-gap"
        ]
        if stats["monocultural"]:
            issues.append(
                f"MONOCULTURE {domain}: {stats['entities']} entities with type entropy "
                f"{stats['type_entropy']:.2f} and tag entropy {stats['tag_entropy']:.2f}"
            )
        for tag, count in stats["overused_tags"]:
            issues.append(f"OVERUSED {domain}: tag {tag!r} on {count}/{stats['entities']} entities")
    return issues


def edge_type_distribution(bible: Bible) -> Counter:
    return Counter(edge.rel for edge in bible.edges)


def audit(bible: Bible) -> list[str]:
    """Everything that must be fixed, in the order a reader should act on it.

    `shared_labels` is deliberately absent: it is information for the next wave,
    not a defect. Including it would make `validate` fail on content the game
    itself authored, which trains people to ignore `validate`.
    """
    findings: list[str] = []
    findings += [f"schema: {issue}" for issue in validate_entities(bible)]
    findings += [f"edge: {issue}" for issue in validate_edges(bible)]
    findings += [f"external: {issue}" for issue in validate_external_refs(bible)]
    findings += [f"contradiction: {issue}" for issue in contradictions(bible)]
    findings += [f"duplicate: {issue}" for issue in duplicate_names(bible)]
    findings += [f"near-duplicate: {issue}" for issue in near_duplicate_names(bible)]
    findings += [f"structural: {issue}" for issue in structural_duplicates(bible)]
    return findings


def audit_notes(bible: Bible) -> list[str]:
    """Reported by `validate` but never fatal.

    Isolation, shared labels and ungrounded records are all true statements about the
    bible's current state rather than faults in a line somebody wrote: an island is
    something the next wave connects, two imported entities sharing a label is
    authored content the game itself ships, and a species with no homeland is a
    hole rather than an error. Failing on them would make `validate` red from the
    first commit and teach everyone to route around it, which is how the guards in
    this repo stopped being read.
    """
    return (
        [f"isolation: {issue}" for issue in isolated_entities(bible)]
        + [f"shared-label: {issue}" for issue in shared_labels(bible)]
        + [f"ungrounded: {issue}" for issue in ungrounded(bible)]
    )


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ToolError(message)
