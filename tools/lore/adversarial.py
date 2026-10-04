"""Independent audit: challenge the bible rather than extend it.

Every authoring agent in this program is also a source of bias. An agent asked to
write cosmology will make cosmology internally consistent, and internal consistency
is exactly what its own work already had. The checks below are the ones that need
an opponent: they look for claims that are load-bearing, unsupported, or in
tension with each other across batches that never spoke to one another.

This is deliberately separate from `audit.py`. That module asks "is this record
well-formed and are its edges legal". This one asks "is this record TRUE", which no
amount of schema checking can answer, so every finding here is a QUESTION for a
human or an adversarial agent rather than a defect to auto-fix.

Three families, each with a specific failure it catches:

- **Unsourced numbers.** A figure in prose that matches no authored field and no
  authored record. Catches an invented statistic that reads as fact.
- **Cross-batch tension.** Two records, written by different agents, that cannot
  both hold. Catches the case where each batch is internally consistent and the
  inconsistency only exists between them - which is invisible to a per-batch audit.
- **Unsupported authority.** A record that asserts a fact with no causal edge
  behind it. Catches lore that has become decorative.
"""

from __future__ import annotations

import re
from collections import defaultdict

from .model import Bible

# Prose that reads as a claim of authority without being one: "always", "never",
# "the only", "no one", "cannot ever". Each is a universal quantifier, and a
# universal claim in a world with 656 records and 12 empty domains is the kind of
# thing that quietly becomes canon and then contradicts a later batch.
UNIVERSAL_CLAIM = re.compile(
    r"\b(always|never|the only|no one|nobody|without exception|cannot ever|no such)\b",
    re.IGNORECASE,
)

# A number written into prose. Not every one is wrong - "nine provinces" is a name -
# but a number that appears in NO authored field is the one worth asking about.
PROSE_NUMBER = re.compile(r"\b(\d[\d,]*)\b")


# Fields the authored game data actually states. A prose number matching none of
# these has no referent anyone can check.
def _authored_numbers(bible: Bible) -> set[str]:
    numbers: set[str] = set()
    for entity in bible.entities.values():
        attributes = entity.get("attributes")
        if not isinstance(attributes, dict):
            continue
        for value in attributes.values():
            if isinstance(value, bool):
                continue
            if isinstance(value, (int, float)):
                numbers.add(_format_number(value))
            if isinstance(value, list):
                for item in value:
                    if isinstance(item, (int, float)) and not isinstance(item, bool):
                        numbers.add(_format_number(item))
    return numbers


def _format_number(value: float | int) -> str:
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def unsourced_numbers(bible: Bible, *, limit: int = 25) -> list[str]:
    """Numbers in prose with no authored field they could be referring to.

    A legion writing under time pressure invents a plausible figure - "three
    hundred years", "a fourth of the tier" - and it reads as established fact
    because it is in the same voice as everything else. Nothing downstream can
    tell it from a figure the game data states, so it becomes load-bearing by
    accident.
    """
    known = _authored_numbers(bible)
    findings: list[str] = []
    for entity_id, entity in sorted(bible.entities.items()):
        if entity.get("external_ref"):
            continue
        for field in ("summary",):
            text = str(entity.get(field, ""))
            for raw in PROSE_NUMBER.findall(text):
                normalised = raw.replace(",", "")
                if normalised in known or raw in known:
                    continue
                # Ordinals and small counts are almost always part of a name or a
                # list ("nine provinces", "three gates"), not a statistic.
                if len(normalised) <= 2:
                    continue
                findings.append(
                    f"{entity_id}.{field}: the figure {raw!r} matches no authored field "
                    f"in the bible ({len(known)} distinct numbers exist) - is it invented?"
                )
    return findings[:limit]


def universal_claims(bible: Bible, *, limit: int = 20) -> list[str]:
    """Universal quantifiers in authored prose.

    Not wrong in themselves - a setting needs some absolutes - but each one is a
    claim that a later batch will eventually contradict, and the contradiction
    surfaces as two confident sentences rather than as a flag.
    """
    findings: list[str] = []
    for entity_id, entity in sorted(bible.entities.items()):
        if entity.get("external_ref"):
            continue
        text = str(entity.get("summary", ""))
        matches = {match.group(0).lower() for match in UNIVERSAL_CLAIM.finditer(text)}
        if matches:
            findings.append(
                f"{entity_id}: claims {', '.join(sorted(matches))} - an absolute a later "
                "batch must be able to contradict"
            )
    return findings[:limit]


def orphaned_authority(bible: Bible, *, limit: int = 20) -> list[str]:
    """Well-written records that assert a fact with nothing behind it.

    Degree alone would be a bad signal - a seed or a ruin legitimately has few
    edges. So this only fires when a record is BOTH richly written and causally
    inert, which is the combination that means lore has become decorative: it reads
    like an authority on a subject and is referenced by nothing.
    """
    findings: list[str] = []
    for entity_id, entity in sorted(bible.entities.items()):
        if entity.get("external_ref"):
            continue
        attributes = entity.get("attributes")
        prose_keys = len(attributes) if isinstance(attributes, dict) else 0
        if prose_keys < 4:
            continue
        causal = {
            "caused",
            "caused_by",
            "requires",
            "depends_on",
            "influenced_by",
            "originated_from",
            "founded_by",
            "descended_from",
        }
        has_causal = any(
            rel in causal for rel, _other, _edge in bible.out_edges.get(entity_id, ())
        ) or any(
            bible.registry.inverse(rel) in causal
            for rel, _other, _edge in bible.in_edges.get(entity_id, ())
        )
        degree = bible.degree(entity_id)
        if not has_causal and degree >= 4:
            findings.append(
                f"{entity_id}: {prose_keys} attributes and {degree} edges, but nothing "
                "causes it and it causes nothing - it reads like an authority on its "
                "subject and is grounded in no history"
            )
    return findings[:limit]


def cross_batch_tensions(bible: Bible) -> list[str]:
    """Records written by different batches that cannot both be right.

    Found by cross-referencing two things no per-batch check compares: which records
    make a claim ABOUT another record, and whether the graph says the same thing.
    An agent that says "the Ironpact controls the harbour" and an agent that gives
    the harbour to somebody else have each written something internally consistent.
    """
    findings: list[str] = []
    # A `controls` or `member_of` edge plus a summary that names a different holder
    # is the common shape of this: prose and graph disagreeing across a batch line.
    for entity_id, entity in sorted(bible.entities.items()):
        if entity.get("external_ref"):
            continue
        holders = {
            other
            for rel, other, _edge in bible.out_edges.get(entity_id, ())
            if rel in {"controls", "member_of"}
        }
        if not holders:
            continue
        names = {str(bible.entities.get(holder, {}).get("name", "")).lower() for holder in holders}
        text = str(entity.get("summary", "")).lower()
        for holder_name in sorted(n for n in names if len(n) > 3):
            if holder_name not in text:
                continue
    # The disagreement itself: a summary that names an organisation as holding a
    # place, where the graph records somebody else holding it.
    claimable = {"controls", "member_of", "located_in"}
    for entity_id, entity in sorted(bible.entities.items()):
        if entity.get("external_ref"):
            continue
        holders = {
            other for rel, other, _edge in bible.out_edges.get(entity_id, ()) if rel in claimable
        }
        if not holders:
            continue
        text = str(entity.get("summary", "")).lower()
        holder_names = {
            str(bible.entities.get(holder, {}).get("name", "")).lower() for holder in holders
        }
        # Every organisation and race in the bible is a candidate rival holder.
        # Only a name that reads as a HOLDER is a rival. A culture or a race name
        # inside a descriptive phrase is not asserting anything about who holds a
        # place, so excluding them removes the loudest false positives.
        rivals = {
            str(other.get("name", "")).lower()
            for other in bible.entities.values()
            if other.get("domain") in {"organizations", "civilizations"}
            and str(other.get("name", ""))
        }
        # Substring matching produced false positives immediately: "unwritten" is
        # inside "unwritten law", and "emberblood" is inside "emberblood-bearing",
        # so a sentence about an ABSENCE of a law read as a rival holder of a
        # region. Whole-phrase matching with word boundaries is the difference
        # between a finding and noise, and noise here costs a writer an hour.
        named = {
            name for name in rivals if len(name) > 6 and re.search(rf"\b{re.escape(name)}\b", text)
        }
        named -= holder_names
        if named:
            findings.append(
                f"{entity_id}: the summary names {', '.join(sorted(named))} but the graph "
                f"records {', '.join(sorted(holder_names))} - prose and edges disagree, and "
                "they were written by different batches"
            )
    return findings


def batch_report(bible: Bible) -> dict[str, dict]:
    """How much each authoring batch contributed, and how deeply it connects.

    Reported because an objective satisfied by one agent's output is a different
    claim from one satisfied by twelve, and the difference should be visible rather
    than asserted.
    """
    by_batch: dict[str, dict] = defaultdict(
        lambda: {"entities": 0, "edges": 0, "prose": 0, "domains": set()}
    )
    for entity in bible.entities.values():
        author = str((entity.get("provenance") or {}).get("author", "unknown"))
        row = by_batch[author]
        row["entities"] += 1
        row["domains"].add(str(entity.get("domain")))
    for edge in bible.edges:
        author = edge.origin.removesuffix(".jsonl") or "unknown"
        by_batch[author]["edges"] += 1
    for row in by_batch.values():
        row["domains"] = sorted(row["domains"])
    return dict(sorted(by_batch.items()))


def audit(bible: Bible) -> dict[str, list[str]]:
    return {
        "unsourced numbers": unsourced_numbers(bible),
        "universal claims": universal_claims(bible),
        "orphaned authority": orphaned_authority(bible),
        "cross-batch tensions": cross_batch_tensions(bible),
    }


def summary_line(bible: Bible) -> str:
    counts = {name: len(findings) for name, findings in audit(bible).items()}
    return ", ".join(f"{name}={count}" for name, count in sorted(counts.items()))
