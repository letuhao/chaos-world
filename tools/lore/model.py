"""Registry, loading, and structural validation for the Lore Bible.

The Lore Bible is canonical data, not game data. It deliberately does NOT mirror
the engine's schemas: `game/data/*.tres` is the current authored content and this
index is the world that content is supposed to come from. Where the two overlap,
an entity carries an `external_ref` naming the authored resource it absorbs, so
the correspondence is checkable in both directions and deleting `game/` cannot
delete the world.

Two shapes, deliberately:

- **Entities are sharded by domain** (`lore/bible/<domain>.jsonl`). A domain is
  the unit of ownership: one authoring agent owns one file, so two agents never
  write the same bytes.
- **Edges are sharded by batch** (`lore/edges/<batch>.jsonl`). Edges are what
  every agent needs to write and what nobody owns, so a per-batch append-only
  shard is what makes parallel authoring safe. The tool concatenates them.

The alternative - one big index every agent rewrites - loses writes silently
under concurrency, and a lore bible that silently drops half a wave is worse
than no bible, because it looks complete.
"""

from __future__ import annotations

import json
import math
import re
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from ..common import REPO_ROOT, ToolError

LORE_ROOT = REPO_ROOT / "lore"
BIBLE_DIR = LORE_ROOT / "bible"
EDGES_DIR = LORE_ROOT / "edges"
PROSE_DIR = LORE_ROOT / "prose"
REGISTRY_PATH = LORE_ROOT / "registry.json"

SLUG_RE = re.compile(r"^[a-z0-9]+(?:[_-][a-z0-9]+)*$")
# A summary is an index entry, not a dossier. The ceiling is what keeps a domain
# file greppable by an agent with a 32k window; long-form prose belongs in
# `lore/prose/`, which the loader never reads.
SUMMARY_MAX = 480


@dataclass(frozen=True)
class Relation:
    name: str
    inverse: str
    kind: str
    exclusive_with: tuple[str, ...]
    blurb: str


@dataclass
class Registry:
    raw: dict
    relations: dict[str, Relation] = field(default_factory=dict)

    @property
    def domains(self) -> dict[str, dict]:
        return self.raw["domains"]

    @property
    def statuses(self) -> tuple[str, ...]:
        return tuple(self.raw["statuses"])

    @property
    def entity_required(self) -> tuple[str, ...]:
        return tuple(self.raw["entity_required"])

    def inverse(self, rel: str) -> str:
        relation = self.relations.get(rel)
        return relation.inverse if relation else rel

    def exclusive_status_pairs(self) -> list[tuple[str, str]]:
        return [tuple(pair) for pair in self.raw.get("exclusive_statuses", [])]


def registry_path() -> Path:
    """Resolved at call time, for the same reason `bible_dir` is."""
    return LORE_ROOT / "registry.json"


def load_registry() -> Registry:
    path = registry_path()
    if not path.is_file():
        raise ToolError(f"lore registry missing: {path}")
    raw = json.loads(path.read_text(encoding="utf-8"))
    relations = {
        name: Relation(
            name=name,
            inverse=spec["inverse"],
            kind=spec["kind"],
            exclusive_with=tuple(spec.get("exclusive_with", ())),
            blurb=spec.get("blurb", ""),
        )
        for name, spec in raw.get("relations", {}).items()
    }
    return Registry(raw=raw, relations=relations)


@dataclass
class Edge:
    source: str
    rel: str
    target: str
    status: str
    since: str
    note: str
    origin: str

    def as_dict(self) -> dict:
        out: dict = {"from": self.source, "rel": self.rel, "to": self.target}
        if self.status:
            out["status"] = self.status
        if self.since:
            out["since"] = self.since
        if self.note:
            out["note"] = self.note
        return out


@dataclass
class Bible:
    registry: Registry
    entities: dict[str, dict] = field(default_factory=dict)
    edges: list[Edge] = field(default_factory=list)
    # id -> list of (rel, other_id, edge). Both directions are indexed because
    # traversal in both directions is the common case and an inverse lookup per
    # hop is the sort of thing that gets forgotten in one code path.
    out_edges: dict[str, list[tuple[str, str, Edge]]] = field(
        default_factory=lambda: defaultdict(list)
    )
    in_edges: dict[str, list[tuple[str, str, Edge]]] = field(
        default_factory=lambda: defaultdict(list)
    )

    def neighbours(self, entity_id: str) -> list[tuple[str, str, str]]:
        """(rel, other_id, direction) for every incident edge."""
        found: list[tuple[str, str, str]] = []
        for rel, other, _edge in self.out_edges.get(entity_id, ()):
            found.append((rel, other, "out"))
        for rel, other, _edge in self.in_edges.get(entity_id, ()):
            found.append((self.registry.inverse(rel), other, "in"))
        return found

    def degree(self, entity_id: str) -> int:
        return len(self.out_edges.get(entity_id, ())) + len(self.in_edges.get(entity_id, ()))

    def by_domain(self) -> dict[str, list[dict]]:
        grouped: dict[str, list[dict]] = {name: [] for name in self.registry.domains}
        for entity in self.entities.values():
            grouped.setdefault(entity.get("domain", "?"), []).append(entity)
        return grouped

    def tags(self) -> Counter:
        counter: Counter = Counter()
        for entity in self.entities.values():
            for tag in entity.get("tags", []) or []:
                if isinstance(tag, str):
                    counter[tag] += 1
        return counter

    def types(self) -> dict[str, Counter]:
        counter: dict[str, Counter] = defaultdict(Counter)
        for entity in self.entities.values():
            counter[entity.get("domain", "?")][entity.get("type", "?")] += 1
        return counter


def bible_dir() -> Path:
    """The entity directory, derived from LORE_ROOT at call time.

    Deliberately a function rather than a module constant: `selftest` points
    LORE_ROOT at a temporary tree, and a constant captured at import time keeps
    reading the repository no matter what the test asks for. That failure is
    silent and total - a fixture asserting on the real bible passes while testing
    nothing - so every path is resolved through here.
    """
    return LORE_ROOT / "bible"


def edges_dir() -> Path:
    return LORE_ROOT / "edges"


def _read_jsonl(path: Path, *, origin: str) -> list[dict]:
    rows: list[dict] = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip():
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ToolError(f"{origin}:{number}: invalid JSON ({exc.msg})") from exc
        if not isinstance(row, dict):
            raise ToolError(f"{origin}:{number}: each line must be a JSON object")
        rows.append(row)
    return rows


def load_bible() -> Bible:
    registry = load_registry()
    bible = Bible(registry=registry)
    entities_dir = bible_dir()
    if not entities_dir.is_dir():
        return bible
    for path in sorted(entities_dir.glob("*.jsonl")):
        for row in _read_jsonl(path, origin=path.name):
            entity_id = row.get("id")
            if isinstance(entity_id, str):
                bible.entities[entity_id] = row
    edges_root = edges_dir()
    if edges_root.is_dir():
        for path in sorted(edges_root.glob("*.jsonl")):
            for row in _read_jsonl(path, origin=f"edges/{path.name}"):
                source, rel, target = row.get("from"), row.get("rel"), row.get("to")
                if not all(isinstance(value, str) for value in (source, rel, target)):
                    raise ToolError(f"edges/{path.name}: an edge needs from, rel and to strings")
                edge = Edge(
                    source=source,
                    rel=rel,
                    target=target,
                    status=str(row.get("status", "")),
                    since=str(row.get("since", "")),
                    note=str(row.get("note", "")),
                    origin=path.name,
                )
                bible.edges.append(edge)
                bible.out_edges[source].append((rel, target, edge))
                bible.in_edges[target].append((rel, source, edge))
    return bible


# --- structural validation --------------------------------------------------


def validate_entities(bible: Bible) -> list[str]:
    """Shape only. Whether the lore is any good is the audit agents' problem."""
    issues: list[str] = []
    registry = bible.registry
    statuses = set(registry.statuses)
    seen: dict[str, str] = {}
    for path, entity in sorted(bible.entities.items()):
        label = entity.get("id", path)
        for field_name in registry.entity_required:
            if field_name not in entity:
                issues.append(f"{label}: missing required field {field_name!r}")
        entity_id = entity.get("id")
        if not isinstance(entity_id, str) or "." not in entity_id:
            issues.append(f"{label}: id must be namespaced as <domain>.<slug>")
            continue
        domain = entity.get("domain")
        prefix, _, slug = entity_id.partition(".")
        if domain not in registry.domains:
            issues.append(f"{label}: domain {domain!r} is not registered")
        if domain != prefix:
            issues.append(f"{label}: id prefix {prefix!r} disagrees with domain {domain!r}")
        if not SLUG_RE.match(slug):
            issues.append(f"{label}: id slug {slug!r} must be lowercase with - or _ separators")
        if entity_id in seen:
            issues.append(f"{label}: duplicate id, also defined in {seen[entity_id]}")
        else:
            seen[entity_id] = label
        if not _text(entity.get("name"), limit=120):
            issues.append(f"{label}: needs a name of at most 120 characters")
        summary = entity.get("summary")
        if not isinstance(summary, str) or not summary.strip():
            issues.append(f"{label}: needs a summary")
        elif len(summary) > SUMMARY_MAX:
            issues.append(
                f"{label}: summary is {len(summary)} characters, over the {SUMMARY_MAX} "
                "index ceiling; move the detail to lore/prose/ and link it"
            )
        if not _slug_list(entity.get("type")):
            issues.append(f"{label}: type must be a single lowercase slug")
        tags = entity.get("tags")
        if not isinstance(tags, list) or any(not _slug(tag) for tag in tags):
            issues.append(f"{label}: tags must be a list of lowercase slugs")
        if entity.get("status") not in statuses:
            issues.append(f"{label}: status {entity.get('status')!r} is not registered")
        if not isinstance(entity.get("attributes"), dict):
            issues.append(f"{label}: attributes must be an object")
        provenance = entity.get("provenance")
        if not isinstance(provenance, dict) or not _text(provenance.get("author")):
            issues.append(f"{label}: provenance needs an author, so a wave can be audited later")
        reference = entity.get("external_ref")
        if reference is not None and not isinstance(reference, dict):
            issues.append(f"{label}: external_ref must be an object or absent")
        depth = (
            entity.get("attributes", {}).get("lore_depth")
            if isinstance(entity.get("attributes"), dict)
            else None
        )
        if depth is not None and depth not in {"stub", "sketched", "authored"}:
            issues.append(
                f"{label}: attributes.lore_depth {depth!r} must be stub, sketched or authored"
            )
    return issues


def validate_edges(bible: Bible) -> list[str]:
    issues: list[str] = []
    registry = bible.registry
    seen: set[tuple[str, str, str]] = set()
    for edge in bible.edges:
        label = f"{edge.source} -{edge.rel}-> {edge.target}"
        if edge.rel not in registry.relations:
            issues.append(f"{label}: relation {edge.rel!r} is not registered")
        if edge.source not in bible.entities:
            issues.append(f"{label}: source does not exist ({edge.origin})")
        if edge.target not in bible.entities:
            issues.append(f"{label}: target does not exist ({edge.origin})")
        if edge.source == edge.target:
            issues.append(f"{label}: an entity cannot bear a relation to itself")
        key = (edge.source, edge.rel, edge.target)
        if key in seen:
            issues.append(f"{label}: duplicate edge ({edge.origin})")
        seen.add(key)
        if edge.since and edge.since not in bible.entities:
            issues.append(f"{label}: since {edge.since!r} is not a known history record")
        if edge.status and edge.status not in set(registry.statuses):
            issues.append(f"{label}: status {edge.status!r} is not registered")
    return issues


def prose_dir() -> Path:
    return LORE_ROOT / "prose"


def validate_external_refs(bible: Bible) -> list[str]:
    """The absorbed canon must still be there.

    An `external_ref` is a promise that a lore entity and an authored `.tres`
    describe the same thing. Nothing enforces that correspondence by itself, and a
    renamed or deleted resource would otherwise leave the bible quietly claiming
    authority over content that no longer exists.
    """
    issues: list[str] = []
    for entity_id, entity in sorted(bible.entities.items()):
        reference = entity.get("external_ref")
        if not isinstance(reference, dict):
            continue
        relative = reference.get("path")
        if not isinstance(relative, str):
            issues.append(f"{entity_id}: external_ref needs a path")
            continue
        path = (REPO_ROOT / relative).resolve()
        if not path.is_relative_to(REPO_ROOT):
            issues.append(f"{entity_id}: external_ref path escapes the repository")
        elif not path.is_file():
            issues.append(
                f"{entity_id}: external_ref path does not exist ({relative}); the repository "
                "root is the one place a path is resolved against, because a fixture tree "
                "has no game/data to point at"
            )
    return issues


def _text(value: object, *, limit: int = 0) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    return len(value) <= limit if limit else True


def _slug(value: object) -> bool:
    return isinstance(value, str) and bool(SLUG_RE.match(value))


def _slug_list(value: object) -> bool:
    return isinstance(value, str) and bool(SLUG_RE.match(value))


def normalised_entropy(counts: Counter) -> float:
    """Shannon entropy over a distribution, scaled to 0..1 by log(k).

    Raw entropy is not comparable across domains: five types spread evenly and
    five types with one dominant look similar until you divide by the maximum the
    domain could achieve. Scaled, 0.0 means one type owns the domain and 1.0 means
    every type is equally common, which is what makes "monoculture" a number
    rather than an opinion.
    """
    total = sum(counts.values())
    kinds = len(counts)
    if total == 0 or kinds <= 1:
        return 0.0
    entropy = -sum((n / total) * math.log(n / total) for n in counts.values() if n)
    return entropy / math.log(kinds)
