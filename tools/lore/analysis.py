"""Query, traversal, causal-chain and character-readiness analysis.

Traversal is breadth-first with an explicit visited set and a depth ceiling. A
knowledge graph built by many agents in parallel will eventually contain a cycle
somebody thinks is meaningful - a guild that descends from a house that
descends from the guild - and an unbounded walk over one is a hang, not a
feature. The ceiling is what makes "how did this character come to exist"
answerable in bounded time.
"""

from __future__ import annotations

from collections import Counter, defaultdict, deque

from ..common import ToolError
from .model import Bible, normalised_entropy

MAX_DEPTH = 6
# A walk that visits more of the graph than this is a bug in the query, not an
# answer. The bible is meant to be navigable, not to be a single component.
MAX_VISITED = 4000

# The relation types that express causation, weakest cause first. `chain` follows
# these upward from an entity to answer "why does this exist".
CAUSAL_RELS = (
    "requires",
    "depends_on",
    "influenced_by",
    "caused_by",
    "originated_from",
    "descended_from",
)

# Domain pairs that a character's context should be able to cross, and the
# relations that can carry each hop. Used by `readiness` to name the exact missing
# link rather than reporting that a chain "failed".
READINESS_CHAINS = {
    "character": [
        ("races", "cultures", {"part_of", "member_of", "native_to", "requires", "influenced_by"}),
        ("cultures", "civilizations", {"part_of", "member_of", "located_in", "participated_in"}),
        ("families", "civilizations", {"member_of", "located_in", "part_of"}),
        ("civilizations", "geography", {"located_in", "controls", "part_of"}),
        ("geography", "worlds", {"located_in", "part_of"}),
        ("worlds", "cosmology", {"part_of", "depends_on", "requires"}),
    ],
    "conflict": [
        ("people", "organizations", {"member_of", "participated_in"}),
        ("organizations", "conflicts", {"participated_in", "enemy_of"}),
        ("conflicts", "economy", {"caused", "depends_on", "conflicts_with"}),
        ("economy", "geography", {"depends_on", "located_in", "requires"}),
    ],
    "lineage": [
        ("races", "races", {"descended_from", "hybrid_of"}),
        ("races", "worlds", {"native_to", "migrated_from", "originated_from"}),
        ("worlds", "history", {"caused", "participated_in"}),
        ("history", "history", {"caused", "preceded_by"}),
    ],
}


def search(
    bible: Bible, query: str, *, limit: int = 25, domain: str | None = None
) -> list[tuple[int, dict, str]]:
    """Ranked search over id, name, tags and summary.

    Scores whole-token id and name matches highest, then prefix matches, then tag
    and summary hits. An agent searching before creating needs the obvious answer
    first; a bag-of-characters score buries it.
    """
    needle = query.strip().lower()
    if not needle:
        raise ToolError("search needs a query")
    hits: list[tuple[int, dict, str]] = []
    for entity in bible.entities.values():
        if domain and entity.get("domain") != domain:
            continue
        entity_id = entity.get("id", "")
        name = entity.get("name", "")
        score = 0
        why = ""
        id_lower, name_lower = entity_id.lower(), name.lower()
        if id_lower == needle or name_lower == needle:
            score, why = 100, "exact"
        elif id_lower.startswith(needle) or name_lower.startswith(needle):
            score, why = 80, "prefix"
        elif needle in id_lower or needle in name_lower:
            score, why = 60, "substring"
        else:
            tags = [str(tag).lower() for tag in entity.get("tags", []) or []]
            if needle in tags:
                score, why = 50, "tag"
            elif needle in str(entity.get("type", "")).lower():
                score, why = 40, "type"
            elif needle in str(entity.get("summary", "")).lower():
                score, why = 20, "summary"
        if score:
            hits.append((score, entity, why))
    hits.sort(key=lambda item: (-item[0], item[1]["id"]))
    return hits[:limit]


def resolve(bible: Bible, entity_id: str) -> dict:
    entity = bible.entities.get(entity_id)
    if entity is None:
        matches = [candidate for candidate in bible.entities if entity_id in candidate]
        hint = f"; did you mean: {', '.join(sorted(matches)[:5])}" if matches else ""
        raise ToolError(f"unknown lore id {entity_id!r}{hint}")
    return entity


def resolve_shot(bible: Bible, *candidates: str) -> dict:
    """Accept a bare slug as well as a namespaced id.

    Agents are given ids in briefs and will retype them; making them fail on a
    missing namespace prefix trains them to stop reading the ids they were given.
    """
    for candidate in candidates:
        if candidate in bible.entities:
            return bible.entities[candidate]
    for entity_id in sorted(bible.entities):
        if entity_id.rpartition(".")[2] == candidates[-1]:
            return bible.entities[entity_id]
    raise ToolError(f"unknown lore id {candidates[-1]!r}")


def show(bible: Bible, entity_id: str) -> dict:
    """The resolved view: the entity plus its incident edges with both endpoints named."""
    entity = resolve(bible, entity_id)
    out_edges = [
        {
            "rel": edge.rel,
            "to": edge.target,
            "to_name": bible.entities.get(edge.target, {}).get("name", edge.target),
            "status": edge.status,
            "since": edge.since,
            "note": edge.note,
        }
        for _rel, _target, edge in sorted(
            bible.out_edges.get(entity_id, ()), key=lambda item: (item[0], item[1])
        )
    ]
    in_edges = [
        {
            "rel": bible.registry.inverse(edge.rel),
            "from": edge.source,
            "from_name": bible.entities.get(edge.source, {}).get("name", edge.source),
            "status": edge.status,
            "since": edge.since,
            "note": edge.note,
        }
        for _rel, _source, edge in sorted(
            bible.in_edges.get(entity_id, ()), key=lambda item: (item[0], item[1])
        )
    ]
    return {
        "id": entity_id,
        "domain": entity.get("domain"),
        "type": entity.get("type"),
        "name": entity.get("name"),
        "summary": entity.get("summary"),
        "tags": entity.get("tags", []),
        "status": entity.get("status"),
        "attributes": entity.get("attributes", {}),
        "provenance": entity.get("provenance", {}),
        "external_ref": entity.get("external_ref"),
        "out": out_edges,
        "in": in_edges,
        "degree": len(out_edges) + len(in_edges),
    }


def traverse(
    bible: Bible,
    entity_id: str,
    *,
    rels: set[str] | None = None,
    depth: int = 2,
    direction: str = "both",
) -> dict:
    """Bounded BFS. `rels` filters relation types; `direction` is out, in or both."""
    if not 1 <= depth <= MAX_DEPTH:
        raise ToolError(f"--depth must be between 1 and {MAX_DEPTH}")
    resolve(bible, entity_id)
    start = bible.entities[entity_id]
    seen: set[str] = {entity_id}
    layers: list[dict] = [{"depth": 0, "id": entity_id, "name": start.get("name")}]
    frontier: deque[tuple[str, int]] = deque([(entity_id, 0)])
    while frontier and len(seen) < MAX_VISITED:
        node, level = frontier.popleft()
        if level >= depth:
            continue
        neighbours = bible.neighbours(node)
        for rel, other, way in sorted(neighbours, key=lambda item: (item[0], item[1])):
            if rels and rel not in rels:
                continue
            if direction != "both" and way != direction:
                continue
            if other in seen:
                continue
            seen.add(other)
            layers.append(
                {
                    "depth": level + 1,
                    "id": other,
                    "name": bible.entities.get(other, {}).get("name", other),
                    "via": rel,
                    "from": node,
                }
            )
            frontier.append((other, level + 1))
            if len(seen) >= MAX_VISITED:
                break
    return {
        "root": entity_id,
        "depth": depth,
        "visited": len(seen),
        "truncated": len(seen) >= MAX_VISITED,
        "layers": layers,
    }


def causal_chain(bible: Bible, entity_id: str, *, depth: int = 4) -> dict:
    """Walk backwards along causation to answer "why does this exist?".

    Only the CAUSAL_RELS are followed, and only backwards, because a forward walk
    from a cause enumerates everything the cause touches - which is most of the
    bible - while a backward walk from a specific thing terminates in the handful
    of conditions that actually produced it.
    """
    resolve(bible, entity_id)
    chains: list[list[dict]] = []
    stack: list[tuple[str, int, list[dict]]] = [(entity_id, 0, [])]
    visited: set[tuple[str, ...]] = set()
    while stack:
        node, level, trail = stack.pop()
        signature = tuple(step["id"] for step in trail)
        if signature in visited:
            continue
        visited.add(signature)
        if level >= depth:
            if trail:
                chains.append(trail)
            continue
        parents: list[tuple[str, str]] = []
        for rel in CAUSAL_RELS:
            for source, _target, _edge in bible.in_edges.get(node, ()):
                if bible.registry.inverse(rel) == source:
                    continue
            for _rel, source, _edge in bible.in_edges.get(node, ()):
                if bible.registry.inverse(_rel) == rel:
                    parents.append((rel, source))
        if not parents:
            chains.append(trail)
            continue
        for rel, source in sorted(set(parents)):
            entity = bible.entities.get(source)
            if entity is None:
                continue
            step = {
                "id": source,
                "name": entity.get("name"),
                "rel": rel,
                "domain": entity.get("domain"),
                "summary": entity.get("summary"),
            }
            stack.append((source, level + 1, [*trail, step]))
            if len(visited) >= MAX_VISITED:
                break
    return {"root": entity_id, "roots": chains[:40], "truncated": len(visited) >= MAX_VISITED}


def readiness(bible: Bible, chain_name: str) -> dict:
    """Can a character's context actually be walked through the world?

    Reports every hop of a chain template with the number of edges that actually
    cross it. A hop with zero edges is the exact missing link, named by the two
    domains it should join - which is the difference between "the bible feels thin
    somewhere" and "races and cultures are not connected to anything".
    """
    template = READINESS_CHAINS.get(chain_name)
    if template is None:
        raise ToolError(f"unknown chain {chain_name!r}; try: {', '.join(sorted(READINESS_CHAINS))}")
    hops: list[dict] = []
    for left, right, rels in template:
        matched = 0
        for edge in bible.edges:
            if edge.rel not in rels:
                continue
            source_domain = bible.entities.get(edge.source, {}).get("domain")
            target_domain = bible.entities.get(edge.target, {}).get("domain")
            if {source_domain, target_domain} == {left, right}:
                matched += 1
        hops.append(
            {
                "from": left,
                "to": right,
                "relations": sorted(rels),
                "edges": matched,
                "ok": matched > 0,
            }
        )
    return {"chain": chain_name, "hops": hops, "complete": all(hop["ok"] for hop in hops)}


def summarise(bible: Bible) -> dict:
    grouped = bible.by_domain()
    return {
        "entities": len(bible.entities),
        "edges": len(bible.edges),
        "domains": {
            domain: {
                "entities": len(entities),
                "types": len({entity.get("type") for entity in entities}),
                "tag_entropy": normalised_entropy(
                    Counter(
                        tag
                        for entity in entities
                        for tag in entity.get("tags", []) or []
                        if isinstance(tag, str)
                    )
                ),
                "avg_degree": (
                    sum(bible.degree(entity["id"]) for entity in entities) / len(entities)
                    if entities
                    else 0.0
                ),
            }
            for domain, entities in sorted(grouped.items())
        },
        "relations": dict(sorted(Counter(edge.rel for edge in bible.edges).items())),
        "statuses": dict(
            sorted(Counter(str(e.get("status")) for e in bible.entities.values()).items())
        ),
    }


def hubs_and_leaves(bible: Bible, *, limit: int = 10) -> dict:
    """What everything points at, and what points at nothing.

    Both matter. A hub with fifty incoming edges and no outgoing ones is usually a
    root the author never finished; a leaf with one edge is usually a name waiting
    for the history that gives it a reason.
    """
    degrees = {entity_id: bible.degree(entity_id) for entity_id in bible.entities}
    ordered = sorted(degrees.items(), key=lambda item: (-item[1], item[0]))
    return {
        "hubs": [{"id": key, "degree": value} for key, value in ordered[:limit] if value],
        "leaves": [{"id": key, "degree": value} for key, value in ordered[::-1][:limit]],
        "components": _component_count(bible),
    }


def _component_count(bible: Bible) -> int:
    """How many disconnected islands the graph has.

    One component means a character walk can reach everything. Several means the
    bible is a set of private wings, and the count is the single most useful
    structural number for deciding what the next wave should link.
    """
    parent: dict[str, str] = {}

    def find(node: str) -> str:
        parent.setdefault(node, node)
        while parent[node] != node:
            parent[node] = parent[parent[node]]
            node = parent[node]
        return node

    def union(a: str, b: str) -> None:
        root_a, root_b = find(a), find(b)
        if root_a != root_b:
            parent[root_a] = root_b

    for entity_id in bible.entities:
        find(entity_id)
    for edge in bible.edges:
        if edge.source in parent and edge.target in parent:
            union(edge.source, edge.target)
    roots = {find(entity_id) for entity_id in bible.entities}
    sizes: dict[str, int] = defaultdict(int)
    for entity_id in bible.entities:
        sizes[find(entity_id)] += 1
    return len(roots) if bible.entities else 0
