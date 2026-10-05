"""The work queue: which specific record should the next agent fix, and why.

`audit.gaps` answers "what is missing from this domain". That is the wrong
granularity to hand an agent. "geography has 164 stubs" is a number; "this one,
because it has no cause and no upstream edge" is a task. An agent given the number
will sample whatever it finds first, which is how 90% of a batch ends up
describing the same kind of thing.

So the queue ranks individual records by a fixability score, and every rank
carries the reason it ranked there. Three properties matter:

- **Deterministic.** Same bible, same order. Two agents must not pick the same
  record because of a hash seed, and a queue that reshuffles between runs cannot
  be used to track progress.
- **Spread across types.** A queue sorted purely by "most broken" hands an agent
  40 consecutive stub domains of identical shape, which produces the monoculture
  the diversity metrics exist to prevent. The rank therefore interleaves types.
- **Self-declaring.** Every entry says what would make it stop being a gap, so an
  agent can tell "finished" from "described".
"""

from __future__ import annotations

from collections import defaultdict

from .model import Bible

# What a record needs before it is not a stub. Ordered by how much work closing it
# is, so a queue can offer an agent something it can actually finish.
FIX_CRITERIA: tuple[tuple[str, str, int], ...] = (
    ("has_cause", "names what caused or required its existence", 3),
    ("has_upstream", "is reachable from a cosmology or history root", 2),
    ("has_type_variety", "differs structurally from its neighbours", 1),
    ("has_prose", "summary states a cause, not only a category", 2),
)

STUB = {"stub", None, "unknown"}


def _is_stub(entity: dict) -> bool:
    attributes = entity.get("attributes")
    depth = attributes.get("lore_depth") if isinstance(attributes, dict) else None
    return depth in STUB


def _has_cause(bible: Bible, entity_id: str) -> bool:
    """Does an upstream record explain why this one exists?

    Causal relations only. An entity with three `located_in` edges is well
    embedded but causally unexplained, which is a different and more serious gap:
    a character can be placed there but cannot be told why anything happens.
    """
    causal = {
        "caused",
        "required",
        "requires",
        "influenced_by",
        "caused_by",
        "depends_on",
        "originated_from",
        "founded_by",
        "descended_from",
    }
    for rel, _other, _edge in bible.out_edges.get(entity_id, ()):
        if rel in causal:
            return True
    for rel, _other, _edge in bible.in_edges.get(entity_id, ()):
        if bible.registry.inverse(rel) in causal:
            return True
    return False


def _has_upstream(bible: Bible, entity_id: str) -> bool:
    """Is it connected to a root domain at all?

    Cosmology and history are the roots everything descends from. A record with no
    path to either is an island, and an island cannot inform a character walk no
    matter how well written it is.
    """
    roots = {
        entity["id"]
        for entity in bible.entities.values()
        if entity.get("domain") in {"cosmology", "history"}
    }
    seen: set[str] = set()
    frontier = [entity_id]
    while frontier and len(seen) < 400:
        node = frontier.pop()
        if node in seen:
            continue
        seen.add(node)
        if node in roots and node != entity_id:
            return True
        for _rel, other, _edge in bible.out_edges.get(node, ()):
            frontier.append(other)
        for _rel, other, _edge in bible.in_edges.get(node, ()):
            frontier.append(other)
    return False


def _has_prose(entity: dict) -> bool:
    """Does the summary say why, rather than only what category it is?

    Detected by refusing to accept the two shapes that read as complete and carry
    no information: "A named-figure that exists in authored game data" (the
    importer's stub text) and anything that is only the display name.
    """
    summary = str(entity.get("summary", "")).strip()
    if not summary:
        return False
    if "exists in authored game data" in summary:
        return False
    if "this is a gap" in summary:
        return False
    name = str(entity.get("name", "")).strip().lower()
    if summary.lower().rstrip(".") == name.rstrip("."):
        return False
    # A summary with no causal connective is a category, not a cause. Kept to a
    # short list so ordinary prose is not required to use one exact word.
    connectives = (
        " because ",
        " so that ",
        " which is why ",
        " after ",
        " when ",
        " until ",
        " since ",
        " therefore ",
        " so ",
    )
    return any(word in f" {summary.lower()} " for word in connectives)


def score(entity: dict, bible: Bible) -> tuple[int, list[str]]:
    """Higher means "more broken and more worth fixing first"."""
    entity_id = entity["id"]
    reasons: list[str] = []
    total = 0
    if _is_stub(entity):
        total += 5
        reasons.append("still a stub")
    if not _has_cause(bible, entity_id):
        total += 3
        reasons.append("no causal edge explains why it exists")
    if not _has_upstream(bible, entity_id):
        total += 2
        reasons.append("no path to cosmology or history")
    if not _has_prose(entity):
        total += 2
        reasons.append("summary states a category, not a cause")
    return total, reasons


def build_queue(bible: Bible, *, domain: str | None = None, limit: int = 25) -> list[dict]:
    """The ranked queue, interleaved by type so no batch becomes a monoculture."""
    candidates = [
        entity
        for entity in bible.entities.values()
        if domain is None or entity.get("domain") == domain
    ]
    scored = []
    for entity in candidates:
        points, reasons = score(entity, bible)
        if points:
            scored.append((points, entity, reasons))
    scored.sort(key=lambda item: (-item[0], item[1]["id"]))

    # Interleave by type. Round-robin over types ordered by their worst member, so
    # the queue always offers variety even when one type dominates the damage.
    by_type: dict[str, list[tuple[int, dict, list[str]]]] = defaultdict(list)
    for entry in scored:
        by_type[str(entry[1].get("type", "?"))].append(entry)
    order = sorted(by_type, key=lambda kind: (-by_type[kind][0][0], kind))

    queue: list[dict] = []
    index = 0
    while len(queue) < limit and any(by_type[kind] for kind in order):
        kind = order[index % len(order)]
        index += 1
        if not by_type[kind]:
            continue
        points, entity, reasons = by_type[kind].pop(0)
        queue.append(
            {
                "id": entity["id"],
                "domain": entity.get("domain"),
                "type": kind,
                "name": entity.get("name"),
                "score": points,
                "why": reasons,
                "fixed_when": _fixed_when(reasons),
            }
        )
        if len(queue) >= limit:
            break
    return queue


def _fixed_when(reasons: list[str]) -> str:
    """What finishing this looks like, so an agent can tell done from described."""
    if "still a stub" in reasons:
        return (
            "set attributes.lore_depth to sketched/authored, drop the lore-gap tag, "
            "and write the cause"
        )
    if "no causal edge" in reasons:
        return "add a caused_by / requires / depends_on edge to whatever produced it"
    if "no path to cosmology or history" in reasons:
        return "connect it upward so a character walk can reach it"
    return "state the cause in the summary using a causal connective"
