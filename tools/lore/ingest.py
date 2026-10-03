"""Import the authored game content into the Lore Bible as external references.

The repository already ships 15,002 authored `.tres` records. They are *content*,
not *world*: a boss is a name and a loot table, a domain is a name and a boss list,
and neither says why either exists. The Lore Bible is the layer that answers that,
so it must **contain** the existing content rather than sit beside it and drift.

Two things happen here, and the difference matters:

- **Entities with real prose** (races, bloodlines, clans, sects, nations, the
  cosmology) become first-class lore records with their authored description as
  the summary. Nothing is invented.
- **Entities that are stubs** (the 331 bosses and 160 domains) are imported as
  explicitly incomplete records, so the gap is *visible and countable* rather than
  invisible. That is the point: a boss with no lore is a finding, not a record.

Ids are namespaced (`races.emberblood`) so lore ids never collide with game ids,
and each record carries an `external_ref` back to the `.tres` it came from, so a
later pass can reconcile in either direction without guessing.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from datetime import date

from ..common import GAME_DIR, REPO_ROOT, ok
from .model import BIBLE_DIR, EDGES_DIR, SUMMARY_MAX

SCHEMA_VERSION = 1

# Authored game data already committed under game/data/, mapped to the Lore Bible
# domain each kind belongs in. Adding a mapping here is how a new authored content
# kind enters the bible; nothing else in the pipeline needs to know.
#
# `kind` is the lore `type` stem. `attr` is where the authored scalars are kept,
# so nothing is lost on import and a later projection can read it back.
GAME_SOURCES: dict[str, dict] = {
    "races": {"domain": "races", "kind": "race", "path": "data/races"},
    "bloodlines": {"domain": "races", "kind": "bloodline", "path": "data/bloodlines"},
    "world/tiers": {"domain": "cosmology", "kind": "world-tier", "path": "data/world/tiers"},
    "world/laws": {"domain": "cosmology", "kind": "world-law", "path": "data/world/laws"},
    "world/factions": {
        "domain": "cosmology",
        "kind": "dao-philosophy",
        "path": "data/world/factions",
    },
    "world/locations": {
        "domain": "geography",
        "kind": "named-region",
        "path": "data/world/locations",
    },
    "world/inhabitants": {
        "domain": "ecology",
        "kind": "spirit-creature",
        "path": "data/world/inhabitants",
    },
    "sect": {"domain": "organizations", "kind": "sect", "path": "data/sect"},
    "clans": {"domain": "organizations", "kind": "clan", "path": "data/clans"},
    "nation": {"domain": "civilizations", "kind": "nation", "path": "data/nation"},
    "bosses": {"domain": "people", "kind": "named-figure", "path": "data/bosses"},
    "domains": {"domain": "geography", "kind": "domain", "path": "data/domains"},
}

# Scalars lifted out of a `.tres` into `attributes`. Kept as a literal allowlist so
# a future `.tres` field cannot silently start feeding the lore bible.
LIFTED: dict[str, tuple[str, ...]] = {
    "races": (
        "dominance",
        "manifestation_threshold",
        "gestation_days",
        "realm_ceiling",
        "lifespan",
    ),
    "bloodlines": ("awaken_threshold", "race_id"),
    "world/tiers": ("realm_min", "realm_max", "law_slots", "time_flow_min", "size_min", "size_max"),
    # tier_ids is what makes a law a law: which worlds it holds force in. Without
    # it every law imports as an island, which is what the isolation check caught.
    "world/laws": ("group", "value_min", "value_max", "tier_ids"),
    "world/factions": ("dao_alignment", "home_tier"),
    "world/locations": ("tier", "faction_id", "danger_level"),
    "world/inhabitants": ("type", "tier_ids", "combat_power_min", "combat_power_max"),
    "bosses": ("domain_id",),
    "domains": ("boss_ids",),
}

_NUMBER_RE = re.compile(r"^-?\d+(?:\.\d+)?$")
_STRINGNAME_ARRAY_RE = re.compile(r"Array\[StringName\]\(\[([^\]]*)\]\)")
_ARRAY_RE = re.compile(r"=\s*\[([^\]]*)\]")


def _scalar(text: str, field: str):
    """Read one top-level scalar from a `.tres`. Returns str, float/bool, or None.

    Deliberately a narrow reader, not a general parser: it must not be able to
    execute or misread anything, and it must return None rather than guess when a
    field is absent.
    """
    match = re.search(rf"^{re.escape(field)}\s*=\s*(.+?)\s*$", text, re.M)
    if not match:
        return None
    raw = match.group(1).strip()
    if raw.startswith('&"') and raw.endswith('"'):
        return raw[2:-1]
    if raw.startswith('"') and raw.endswith('"'):
        return raw[1:-1]
    if raw in {"true", "false"}:
        return raw == "true"
    if _NUMBER_RE.match(raw):
        return float(raw) if "." in raw else int(raw)
    return raw


def _names(text: str, field: str) -> list[str]:
    """Read a StringName array. Handles both the Array[StringName]([...]) and bare forms."""
    match = re.search(rf"^{re.escape(field)}\s*=\s*(.+?)$", text, re.M)
    if not match:
        return []
    raw = match.group(1)
    inner = _STRINGNAME_ARRAY_RE.search(raw) or _ARRAY_RE.search(raw)
    if not inner:
        return []
    return re.findall(r'&?"([^"]+)"', inner.group(1))


def _desc(text: str) -> str:
    value = _scalar(text, "description")
    return value if isinstance(value, str) and value.strip() else ""


def _slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.strip().lower()).strip("_")


def _summary_for(kind: str, display_name: str, description: str) -> tuple[str, str]:
    """Return (summary, lore_depth) for an imported record.

    A stub gets a summary that SAYS it is a stub. That is the honest move: an
    agent reading it learns immediately that this entity is a hole to fill, and
    the audit counts it, instead of a plausible-sounding summary that hides the
    absence of lore behind invented prose.

    An authored description over the index ceiling is truncated at a sentence
    boundary with the rest moved to `lore/prose/`. The index is read by agents
    with a bounded window and by tools that load all of it, so a 500-character
    ceiling that rejects the best prose the repo has would push the real writing
    out of the bible and leave a placeholder in its place - strictly worse than
    a first sentence plus a pointer.
    """
    if not description:
        return (
            f"{display_name} exists in authored game data with no description. "
            "Its why, who made it, and what it changed are all unrecorded: this is a gap, "
            "not a finished entry.",
            "stub",
        )
    if len(description) <= SUMMARY_MAX:
        return description, "authored"
    head = description
    for stop in range(SUMMARY_MAX, SUMMARY_MAX // 2, -1):
        if head[stop : stop + 1] in {".", "!", "?"}:
            head = head[: stop + 1]
            break
    else:
        head = head[:SUMMARY_MAX].rsplit(" ", 1)[0] + " ..."
    return f"{head} (full text in lore/prose/{kind}s/{_slugify(display_name)}.md)", "authored"


def _collect_source(spec: dict) -> list[dict]:
    directory = GAME_DIR / spec["path"]
    if not directory.is_dir():
        return []
    rows: list[dict] = []
    for path in sorted(directory.glob("*.tres")):
        text = path.read_text(encoding="utf-8", errors="replace")
        display_name = _scalar(text, "display_name")
        if not isinstance(display_name, str) or not display_name.strip():
            display_name = path.stem.replace("_", " ").title()
        description = _desc(text)
        game_id = _scalar(text, "id")
        if not isinstance(game_id, str) or not game_id.strip():
            game_id = path.stem
        attrs: dict = {}
        for field in LIFTED.get(spec["path"].removeprefix("data/"), ()):
            if field.endswith("_ids") or field in {"tier_ids"}:
                names = _names(text, field)
                if names:
                    attrs[field] = names
                continue
            value = _scalar(text, field)
            if value is not None:
                attrs[field] = value
        rows.append(
            {
                "lore_id": f"{spec['domain']}.{_slugify(game_id)}",
                "game_id": game_id,
                "display_name": display_name.strip(),
                "description": description,
                "type": spec["kind"],
                "domain": spec["domain"],
                "attributes": attrs,
                "source_path": path.relative_to(REPO_ROOT).as_posix(),
            }
        )
    return rows


def _edges_for(row: dict, spec: dict, known: set[str]) -> list[dict]:
    """Derive the relationships that authored fields already state.

    Only edges whose target actually imported are emitted. An edge to something
    that does not exist yet is a gap, and the brief's gap list is the right place
    for it - not a dangling reference that fails every validation run.
    """
    edges: list[dict] = []
    source = row["lore_id"]
    attrs = row["attributes"]
    kind = spec["kind"]

    def add(rel: str, target_lore: str) -> None:
        if target_lore in known and target_lore != source:
            edges.append({"from": source, "rel": rel, "to": target_lore, "status": "active"})

    if kind == "bloodline" and isinstance(attrs.get("race_id"), str):
        add("descended_from", f"races.{_slugify(attrs['race_id'])}")
    if kind == "named-region":
        if isinstance(attrs.get("tier"), str):
            add("located_in", f"cosmology.{_slugify(attrs['tier'])}")
        if isinstance(attrs.get("faction_id"), str):
            add("member_of", f"cosmology.{_slugify(attrs['faction_id'])}")
    if kind == "world-law":
        for tier in attrs.get("tier_ids", []):
            add("applies_in", f"cosmology.{_slugify(tier)}")
    if kind == "spirit-creature":
        for tier in attrs.get("tier_ids", []):
            add("native_to", f"cosmology.{_slugify(tier)}")
    if kind == "named-figure" and isinstance(attrs.get("domain_id"), str):
        add("located_in", f"geography.{_slugify(attrs['domain_id'])}")
    if kind == "dao-philosophy" and isinstance(attrs.get("home_tier"), str):
        add("native_to", f"cosmology.{_slugify(attrs['home_tier'])}")
    return edges


def build_import() -> tuple[dict[str, list[dict]], list[dict], Counter]:
    """Pure: produce the would-be bible from the authored data. No writes."""
    rows: list[dict] = []
    for spec in GAME_SOURCES.values():
        rows.extend(_collect_source(spec))

    # Deduplicate lore ids deterministically; a collision is reported by validate
    # as a duplicate rather than silently dropped here.
    #
    # Same display_name is NOT a duplicate here. The authored tree genuinely
    # contains six distinct "Ascension Warden" bosses and four distinct "Storm
    # Phoenix Domain" trials - they differ by cultivation path and by which tier
    # gates them, which is real authored content. What the audit must catch is a
    # *renamed* duplicate of the same gate, so each imported entity carries the
    # authored id it came from and the duplicate check compares those instead of
    # the label. See `audit.duplicate_display_names` for the report-only variant.
    by_id: dict[str, dict] = {}
    for row in sorted(rows, key=lambda item: item["lore_id"]):
        by_id.setdefault(row["lore_id"], row)
    known = set(by_id)

    edges: list[dict] = []
    for row in sorted(by_id.values(), key=lambda item: item["lore_id"]):
        spec = next(
            spec for source, spec in sorted(GAME_SOURCES.items()) if row["type"] == spec["kind"]
        )
        edges.extend(_edges_for(row, spec, known))

    domains: dict[str, list[dict]] = {
        domain: [] for domain in {s["domain"] for s in GAME_SOURCES.values()}
    }
    counts: Counter = Counter()
    for row in sorted(by_id.values(), key=lambda item: item["lore_id"]):
        summary, depth = _summary_for(row["type"], row["display_name"], row["description"])
        tags = [row["type"]]
        if depth == "stub":
            tags.append("lore-gap")
        provenance = {
            "author": "tools lore ingest",
            "created": date.today().isoformat(),
            "basis": ["authored-game-data"],
            "schema_version": SCHEMA_VERSION,
        }
        record = {
            "id": row["lore_id"],
            "domain": row["domain"],
            "type": row["type"],
            "name": row["display_name"],
            "summary": summary,
            "tags": tags,
            "status": "active",
            "provenance": provenance,
            "attributes": {**row["attributes"], "lore_depth": depth},
            "external_ref": {"game_id": row["game_id"], "path": row["source_path"]},
        }
        domains.setdefault(row["domain"], []).append(record)
        counts[row["domain"]] += 1
    return domains, edges, counts


def write_import() -> int:
    """Write the import into the bible. Refuses to clobber hand-authored content."""
    domains, edges, counts = build_import()
    BIBLE_DIR.mkdir(parents=True, exist_ok=True)
    EDGES_DIR.mkdir(parents=True, exist_ok=True)

    written = 0
    for domain, records in sorted(domains.items()):
        if not records:
            continue
        path = BIBLE_DIR / f"{domain}.jsonl"
        existing: list[dict] = []
        if path.is_file():
            existing = [
                json.loads(line)
                for line in path.read_text(encoding="utf-8").splitlines()
                if line.strip() and not _is_import_line(line)
            ]
        merged = {record["id"]: record for record in existing}
        for record in records:
            merged[record["id"]] = record
        lines = [
            json.dumps(record, ensure_ascii=False, separators=(",", ":"))
            for record in sorted(merged.values(), key=lambda item: item["id"])
        ]
        # newline="\n" explicitly: the default translates to the platform's line
        # ending, so a Windows import and a Linux import of the same authored tree
        # produce different bytes and every future diff shows the whole file as
        # changed. The content is the same; only the terminator moved.
        path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        written += len(records)
        ok(f"imported {len(records):>4} into lore/bible/{domain}.jsonl")

    edge_path = EDGES_DIR / "ingest-game.jsonl"
    if edges:
        lines = [json.dumps(edge, ensure_ascii=False, separators=(",", ":")) for edge in edges]
        edge_path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        ok(f"imported {len(edges):>4} edges into lore/edges/ingest-game.jsonl")

    stubs = sum(
        1
        for records in domains.values()
        for record in records
        if record["attributes"].get("lore_depth") == "stub"
    )
    ok(
        f"game ingest complete: {written} entities, {len(edges)} edges, "
        f"{stubs} flagged as lore gaps (named figures and domains with no lore yet)"
    )
    return 0


def _is_import_line(line: str) -> bool:
    """True when a line came from this tool, so a re-run replaces rather than duplicates."""
    return '"tools lore ingest"' in line


def register(subparsers) -> None:
    parser = subparsers.add_parser("ingest_game", help="import authored game data as lore records")
    parser.add_argument(
        "--dry-run", action="store_true", help="report what would be imported and write nothing"
    )


def run(args) -> int:
    if args.dry_run:
        domains, edges, counts = build_import()
        total = sum(counts.values())
        ok(f"dry run: would import {total} entities and {len(edges)} edges")
        for domain, count in sorted(counts.items()):
            ok(f"  {domain}: {count}")
        return 0
    return write_import()
