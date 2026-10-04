"""Character context resolution: walk the graph and emit what a character inherits.

This is the deliverable the whole bible exists to serve. Every other command
describes the world; this one answers the question a character generator actually
asks: *given this race, this homeland, this era, what does someone born here
already have, and what are they already up against?*

The output is deliberately PROSE, not numbers. ADR 0138 made `reference_stats`
prose by decision and `unique_characters check` refuses a number there, because a
number in a reference document is a balance surface no gate can see. A resolver
that emitted stat numbers would push authors straight through that guard, so it
emits the pressures and constraints a writer turns into numbers deliberately.

The other half is `gaps`. A context is only as good as its weakest link, and a
resolver that silently omits a missing domain is worse than one that refuses: the
character gets written anyway, with invented background, and the invention is
invisible. So every hop that finds nothing is named as a gap, which is what makes
this a measurement of the bible's maturity rather than a pretty-printer.
"""

from __future__ import annotations

from collections import defaultdict

from ..common import ToolError
from .analysis import resolve
from .model import Bible

# Which relation pulls a domain into a character context, and what the hop is for.
# Ordered by how directly the domain shapes a life. `CONTEXT_HOPS` is the whole
# definition of "background a character inherits": if a relation is not here, the
# domain it crosses is not part of the answer.
CONTEXT_HOPS: tuple[tuple[str, tuple[str, ...], str], ...] = (
    ("races", ("native_to", "descended_from", "hybrid_of", "requires"), "body and origin"),
    ("cultures", ("part_of", "member_of", "influenced_by", "requires"), "what is expected of you"),
    ("civilizations", ("member_of", "located_in", "part_of"), "who you answer to"),
    (
        "geography",
        ("located_in", "native_to", "part_of", "controls"),
        "where you are and what is scarce",
    ),
    ("worlds", ("located_in", "part_of", "native_to"), "what the world permits"),
    ("cosmology", ("depends_on", "requires", "part_of", "applies_in"), "what laws bind you"),
    ("ecology", ("native_to", "located_in", "depends_on", "requires"), "what lives here"),
    ("families", ("member_of", "part_of", "descended_from"), "who you owe"),
    ("organizations", ("member_of", "founded_by", "part_of"), "what you have sworn to"),
    ("economy", ("depends_on", "trades_with", "located_in", "controls"), "what you can afford"),
    ("conflicts", ("participated_in", "caused", "conflicts_with"), "what is being fought over"),
    ("religion", ("believes", "member_of", "influenced_by"), "what is held sacred"),
    ("politics", ("controls", "member_of", "part_of"), "who holds office"),
    ("knowledge", ("requires", "depends_on", "hidden_from"), "what you are allowed to know"),
    ("history", ("caused", "preceded_by", "participated_in"), "what already happened"),
    ("people", ("descended_from", "member_of", "participated_in"), "who came before you"),
    ("mysteries", ("knows_about", "hidden_from", "depends_on"), "what nobody will explain"),
)

# Domains whose absence is a hole in a character's context rather than merely an
# empty index. `history` and `cultures` are here because a character with no
# recorded past and no recorded expectations is a character invented from nothing -
# which is the exact failure this program exists to prevent.
LOAD_BEARING = ("cultures", "history", "geography", "worlds", "cosmology")

MAX_CONTEXT_ENTITIES = 120


def _incident(bible: Bible, entity_id: str, rels: tuple[str, ...]) -> list[tuple[str, str, str]]:
    """(rel, other_id, other_domain) for matching incident edges, both directions.

    The inbound branch is the subtle half, and it is a trap worth stating plainly
    because it has cost several agent waves: `CONTEXT_HOPS` names 20 relations and
    18 of their registry inverses are NOT among them. Only `conflicts_with` and
    `trades_with` are symmetric, so only those two work inbound by name.

    So `people.d2_iron_monarch member_of organizations.saltledger` is invisible
    from `organizations.saltledger`: the edge exists, the endpoint resolves, and
    `validate` is green - but the walk needs `inverse(member_of)` == `has_member`
    to be in the hop list, and it is not. Measured over the registry: 18 of 20
    accepted relations have an unnamed inverse.

    The consequence for authoring: to be reachable FROM a domain, an edge must
    point OUT of that domain using a relation the hop list names. Pointing into it
    is not enough. `_hop_reachable_relations` reports which relations that is.
    """
    found: list[tuple[str, str, str]] = []
    for rel, other, _edge in bible.out_edges.get(entity_id, ()):
        if rel in rels:
            domain = bible.entities.get(other, {}).get("domain", "?")
            found.append((rel, other, domain))
    for rel, other, _edge in bible.in_edges.get(entity_id, ()):
        inverse = bible.registry.inverse(rel)
        if inverse in rels:
            domain = bible.entities.get(other, {}).get("domain", "?")
            found.append((inverse, other, domain))
    return sorted(set(found))


def _hop_reachable_relations(bible: Bible, domain: str) -> tuple[tuple[str, ...], tuple[str, ...]]:
    """(relations that work outbound from `domain`, ones that work inbound).

    Outbound is simply the hop list. Inbound is the subset of it whose REGISTRY
    INVERSE is also in the hop list, which is what `_incident` will follow when it
    arrives at `domain` from the other side.

    Exposed so a briefing can state the reachable relations instead of leaving an
    agent to discover the asymmetry by writing edges that silently do nothing.
    """
    entry = next((rels for name, rels, _p in CONTEXT_HOPS if name == domain), ())
    inbound = tuple(rel for rel in entry if (bible.registry.inverse(rel) or rel) in entry)
    return entry, inbound


def resolve_context(bible: Bible, start_id: str, *, depth: int = 2) -> dict:
    """Everything a character anchored at `start_id` inherits, and every gap in it.

    Bounded twice over: `depth` hops of breadth, and a hard entity ceiling. Both
    matter. A lore bible is a graph with no natural smallness - a well-connected
    cosmology node reaches most of the book - so an unbounded walk here would hang
    on the healthiest bible rather than the broken one, which is backwards.
    """
    if not 1 <= depth <= 4:
        raise ToolError("--depth must be between 1 and 4")
    anchor = resolve(bible, start_id)

    seen: set[str] = {start_id}
    frontier = [(start_id, 0)]
    per_domain: dict[str, list[dict]] = defaultdict(list)

    while frontier and len(seen) < MAX_CONTEXT_ENTITIES:
        node_id, level = frontier.pop(0)
        if level >= depth:
            continue
        for _domain, rels, _purpose in CONTEXT_HOPS:
            for rel, other, domain in _incident(bible, node_id, rels):
                entity = bible.entities.get(other)
                if entity is None:
                    continue
                record = {
                    "id": other,
                    "name": entity.get("name"),
                    "type": entity.get("type"),
                    "via": rel,
                    "from": node_id,
                    "status": entity.get("status"),
                    "lore_depth": (entity.get("attributes") or {}).get("lore_depth"),
                    "summary": entity.get("summary"),
                }
                if not any(existing["id"] == other for existing in per_domain[domain]):
                    per_domain[domain].append(record)
                if other not in seen:
                    seen.add(other)
                    if level + 1 < depth:
                        frontier.append((other, level + 1))

    context_domains = {domain for domain, _, _ in CONTEXT_HOPS}
    missing = [
        {
            "domain": domain,
            "why": _purpose_of(domain),
            "severity": "load-bearing" if domain in LOAD_BEARING else "supporting",
        }
        for domain in sorted(context_domains)
        if not per_domain.get(domain)
    ]

    thin = [
        domain
        for domain in sorted(per_domain)
        if all(item.get("lore_depth") in {"stub", None} for item in per_domain[domain])
    ]

    return {
        "anchor": {
            "id": anchor.get("id"),
            "name": anchor.get("name"),
            "domain": anchor.get("domain"),
            "type": anchor.get("type"),
            "summary": anchor.get("summary"),
            "status": anchor.get("status"),
        },
        "depth": depth,
        "inherited": {
            domain: per_domain[domain][:12] for domain in sorted(per_domain) if per_domain[domain]
        },
        "counts": {domain: len(items) for domain, items in sorted(per_domain.items())},
        "thin_domains": thin,
        "gaps": missing,
        "ready": not missing,
        "entities_examined": len(seen),
        "truncated": len(seen) >= MAX_CONTEXT_ENTITIES,
    }


def _purpose_of(domain: str) -> str:
    for name, _rels, purpose in CONTEXT_HOPS:
        if name == domain:
            return purpose
    return ""


def character_draft(context: dict, *, name: str, path: str) -> dict:
    """A `unique_characters` shaped draft, filled from the graph and nothing else.

    Prose only, deliberately. This function is the seam between two ADRs: the bible
    supplies the inherited context, the named-cast catalog records a person. It
    emits `draft` status even when the context is complete, because "the world's
    background exists" is not the same claim as "this person is written" - the
    promotion to `canon` is a human judgement about the lore, and a resolver that
    could set it would let a graph walk assert authorship.
    """
    inherited = context.get("inherited", {})
    anchor = context.get("anchor", {})

    def names(domain: str, limit: int = 4) -> list[str]:
        return [
            str(item.get("name")) for item in inherited.get(domain, [])[:limit] if item.get("name")
        ]

    world = names("worlds", 2) or names("cosmology", 2)
    culture = names("cultures", 3)
    ecology = names("ecology", 3)
    history = [
        str(item.get("name")) for item in inherited.get("history", [])[:4] if item.get("name")
    ]
    conflicts = [
        str(item.get("name")) for item in inherited.get("conflicts", [])[:3] if item.get("name")
    ]

    lines = [
        f"Produced from the Lore Bible by `lore context`, anchored on {anchor.get('id')}.",
        "Prose only: ADR 0138 keeps `reference_stats` number-free, so a resolver that",
        "emitted stat values would push an author straight through that guard.",
    ]
    if context.get("gaps"):
        lines.append(
            "INCOMPLETE CONTEXT - these domains contributed nothing, so the draft below "
            "has holes a writer must fill or the gaps must be closed first: "
            + ", ".join(gap["domain"] for gap in context["gaps"])
        )

    return {
        "id": "",
        "name": name,
        "aliases": [],
        "status": "draft",
        "identity": {
            "role": "npc",
            "path": path,
            "faction": ", ".join(names("organizations", 2) or names("politics", 2)),
            "home": ", ".join(world) or "UNRESOLVED - no world resolved from the bible",
            "realm": "",
        },
        "appearance": {
            "race": f"see lore anchor {anchor.get('id')} ({anchor.get('name')})",
            "presentation": "",
            "age": "",
            "build": "",
            "complexion": "",
            "hair": "",
            "eyes": "",
            "palette": "",
            "attire": "",
            "marks": "",
            "bearing": "",
        },
        "tags": [],
        "canon": {
            "role_in_story": "",
            "first_appearance": "",
            "lore": (
                f"{anchor.get('name')}: {anchor.get('summary')}" if anchor.get("summary") else ""
            ),
            "history": history,
            "personality": {
                "summary": "",
                "traits": [],
                "mannerisms": [],
                "motivations": [],
                "flaws": [],
                "voice": "",
                "taboos": [],
            },
            "relationships": [],
        },
        "reference_stats": {
            "summary": (
                "A person of "
                + (", ".join(culture) if culture else "an unrecorded culture")
                + (f" shaped by {', '.join(history)}" if history else "")
                + ". Fight them as a product of those conditions, not as a stat block."
            ),
            "strengths": ecology,
            "weaknesses": conflicts,
            "combat_read": "",
            "notes": " ".join(lines),
        },
        "art": {"style": "", "palette_notes": "", "shots": []},
        "published_as": {"portrait_id": "", "def_path": ""},
    }


def readiness_gaps(bible: Bible) -> dict:
    """How ready is the bible to describe a person at all?

    Sampled across the races that exist, because a single anchor can look complete
    while the race that matters is empty. The number that matters is how many
    sampled anchors come back `ready` - a bible where zero anchors resolve is a
    catalogue, not a world.
    """
    anchors = sorted(
        entity["id"]
        for entity in bible.entities.values()
        if entity.get("domain") == "races" and not entity.get("external_ref")
    )
    if not anchors:
        anchors = sorted(
            entity["id"] for entity in bible.entities.values() if entity.get("domain") == "races"
        )
    sample = anchors[:12]
    results = []
    for anchor in sample:
        try:
            context = resolve_context(bible, anchor, depth=2)
        except ToolError:
            continue
        results.append(
            {
                "anchor": anchor,
                "ready": context["ready"],
                "domains": len(context["inherited"]),
                "gaps": [gap["domain"] for gap in context["gaps"]],
            }
        )
    ready = sum(1 for row in results if row["ready"])
    return {
        "sampled": len(results),
        "ready": ready,
        "readiness_ratio": ready / len(results) if results else 0.0,
        "missing_domain_frequency": _gap_frequency(results),
        "results": results,
    }


def _gap_frequency(results: list[dict]) -> dict[str, int]:
    counts: dict[str, int] = defaultdict(int)
    for row in results:
        for domain in row["gaps"]:
            counts[domain] += 1
    return dict(sorted(counts.items(), key=lambda item: (-item[1], item[0])))
