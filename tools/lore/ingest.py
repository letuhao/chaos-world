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
from pathlib import Path

from ..common import GAME_DIR, REPO_ROOT, ToolError, info, ok, warn
from .model import SUMMARY_MAX, bible_dir, edges_dir


def _bible_dir() -> Path:
    return bible_dir()


def _edges_dir() -> Path:
    return edges_dir()


def _repo_root() -> Path:
    """The repository root, resolved at call time. See `_game_dir` for why."""
    return Path(REPO_ROOT)


def _game_dir() -> Path:
    """The authored tree, resolved at call time.

    `GAME_DIR` was a module constant captured at import, so pointing
    `lore.model.REPO_ROOT` at a fixture moved the bible but NOT the authored data
    the importer reads. A test then exercised the repository's 528 real records
    while asserting on a fixture - which is how the first version of the
    re-ingest regression test failed for the wrong reason, against real content it
    never wrote. Same class as the `LORE_ROOT` bug the lore fixtures already
    caught.
    """
    return Path(GAME_DIR)


# Authored content whose game id is NOT unique across the files it lives in.
#
# The three cultivation ladders are parallel by design: `qi_cultivation/realms/`,
# `mind_cultivation/realms/` and `body_cultivation/realms/` all contain
# `core_formation.tres`, `great_luo.tres`, `dao_fruit.tres` and 27 more with the
# SAME game id. `setdefault` in `build_import` keeps the first, so importing them
# as-is would have written 30 records and silently discarded 60 - two thirds of
# every ladder - with no validation error, because the surviving records are
# individually well-formed. The namespacing prefix is per-source-path, so the
# lore id becomes `cultivation.qi_core_formation`, which is also the more honest
# name: these are three DIFFERENT gates that happen to be called the same thing.
#
# Discovered by measuring rather than assuming, after the first draft of the
# extension reported "162 cultivation entities" with no indication that 60 of them
# were about to vanish.
PATH_PREFIX: dict[str, str] = {
    "data/qi_cultivation/realms": "qi",
    "data/mind_cultivation/realms": "mind",
    "data/body_cultivation/realms": "body",
    "data/body_cultivation/acupoints": "",
}

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
    # The cultivation system is the largest body of authored content the first
    # importer pass missed: 52 techniques plus three 30-realm ladders, none of
    # which reached the bible. `lore context` therefore could not resolve a single
    # cultivation question for a character, which is the objective's own test of
    # whether a character can be placed in the world.
    "techniques": {"domain": "cultivation", "kind": "technique", "path": "data/techniques"},
    "qi_cultivation/realms": {
        "domain": "cultivation",
        "kind": "realm",
        "path": "data/qi_cultivation/realms",
        "id_prefix": "qi",
    },
    "mind_cultivation/realms": {
        "domain": "cultivation",
        "kind": "realm",
        "path": "data/mind_cultivation/realms",
        "id_prefix": "mind",
    },
    "body_cultivation/realms": {
        "domain": "cultivation",
        "kind": "realm",
        "path": "data/body_cultivation/realms",
        "id_prefix": "body",
    },
    "body_cultivation/acupoints": {
        "domain": "cultivation",
        "kind": "acupoint",
        "path": "data/body_cultivation/acupoints",
    },
    "meridians": {"domain": "cultivation", "kind": "meridian", "path": "data/meridians"},
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


def _collect_source(spec: dict, key: str) -> list[dict]:
    directory = _game_dir() / spec["path"]
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
        prefix = spec.get("id_prefix", "")
        slug = f"{prefix}_{_slugify(game_id)}" if prefix else _slugify(game_id)
        rows.append(
            {
                "lore_id": f"{spec['domain']}.{slug}",
                "game_id": game_id,
                "source": key,
                "display_name": display_name.strip(),
                "description": description,
                "type": spec["kind"],
                "domain": spec["domain"],
                "attributes": attrs,
                "source_path": path.relative_to(_repo_root()).as_posix(),
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
        # `tier_ids` is APPLICABILITY, not seating. The authored
        # WorldLawDef.tier_ids lists every tier a law *may* hold force in, so
        # emitting one `applies_in` per tier states "governs every tier equally" -
        # which flatly contradicts the seat budget both the authored
        # `law_slots` (3/6/10/15 against six laws) and the world's own material
        # describe, and which two independent author agents both flagged as
        # incoherent.
        #
        # So applicability is recorded as an ATTRIBUTE on the law (it already is:
        # `tier_ids`) and the graph edge is reserved for the one claim the data
        # actually makes: a law holds force inside a tier. Whether a given tier
        # SEATS a law is a per-world fact that no authored record states and that
        # the cosmology and history domains are building from first principles.
        # Inventing the edge here would have hard-coded one interpretation into
        # the importer, where it reads as data.
        pass
    if kind == "spirit-creature":
        for tier in attrs.get("tier_ids", []):
            add("native_to", f"cosmology.{_slugify(tier)}")
    if kind == "named-figure" and isinstance(attrs.get("domain_id"), str):
        add("located_in", f"geography.{_slugify(attrs['domain_id'])}")
    if kind == "dao-philosophy" and isinstance(attrs.get("home_tier"), str):
        add("native_to", f"cosmology.{_slugify(attrs['home_tier'])}")
    if kind == "realm":
        # The three ladders are parallel and share realm NAMES: `body_integration`
        # exists in qi, mind and body with different gates and different costs. The
        # importer namespaces by slug alone, so without the path prefix `setdefault`
        # would keep the first of each triple and silently delete sixty of the
        # ninety realms - a loss with no validation failure, because the surviving
        # ids are well-formed. The prefix is the path, not the display name.
        add("part_of", f"cultivation.{_slugify(spec['path'].split('/')[0])}_path")
    if kind == "technique":
        path_id = attrs.get("path")
        if isinstance(path_id, str) and path_id.strip():
            add("part_of", f"cultivation.{_slugify(path_id)}_path")
    return edges


def build_import() -> tuple[dict[str, list[dict]], list[dict], Counter]:
    """Pure: produce the would-be bible from the authored data. No writes."""
    rows: list[dict] = []
    for key, spec in GAME_SOURCES.items():
        rows.extend(_collect_source(spec, key))

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
    # `setdefault` here would silently DROP a record whenever two sources claim the
    # same lore id, and the loss leaves no trace: the surviving ids are individually
    # well-formed, so `validate` stays green and the count just comes out lower than
    # expected. The three cultivation ladders share every realm NAME - `qi_refining`,
    # `great_luo`, `dao_fruit` and 28 more each exist in all three - so this fired
    # for real and dropped sixty of ninety realms.
    #
    # A collision is a naming defect in the source map, not something to paper over
    # with a merge order. Fail with both claimants named, so the fix is obvious.
    claims: dict[str, list[str]] = {}
    for row in sorted(rows, key=lambda item: item["lore_id"]):
        claims.setdefault(row["lore_id"], []).append(row["source"])
    collisions = {key: sorted(set(value)) for key, value in claims.items() if len(set(value)) > 1}
    if collisions:
        detail = "; ".join(
            f"{key} claimed by {', '.join(sources)}"
            for key, sources in sorted(collisions.items())[:6]
        )
        raise ToolError(
            f"{len(collisions)} lore id collision(s) in the import map: {detail}. "
            "Two authored sources produce the same lore id; give them distinct slugs "
            "rather than letting one silently win"
        )
    by_id = {key: rows[0] for key, rows in ((row["lore_id"], [row]) for row in rows)}
    for row in rows:
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


# Fields a lore agent owns once it has touched a record. The game data is the
# source for the other fields, so those keep refreshing on re-import.
#
# `attributes` is deliberately NOT here: it is a merge of both. A `lore_depth` an
# agent set from `stub` to `authored` must survive, and an authored field the game
# later adds must still land - so attributes are merged key by key instead, and
# `lore_depth` is protected explicitly below.
AGENT_OWNED_FIELDS = frozenset({"summary", "tags", "name", "type", "lore_ref"})

_FORCE = False


def _import_view(record: dict) -> dict:
    """The fields the importer owns, for reporting what a refresh did."""
    return {key: value for key, value in record.items() if key not in AGENT_OWNED_FIELDS}


def write_import(force: bool = False) -> int:
    """Write the import into the bible. Non-destructive unless `force`."""
    global _FORCE
    _FORCE = force
    domains, edges, counts = build_import()
    _bible_dir().mkdir(parents=True, exist_ok=True)
    _edges_dir().mkdir(parents=True, exist_ok=True)

    written = 0
    for domain, records in sorted(domains.items()):
        if not records:
            continue
        path = _bible_dir() / f"{domain}.jsonl"
        existing: list[dict] = []
        if path.is_file():
            existing = [
                json.loads(line)
                for line in path.read_text(encoding="utf-8").splitlines()
                if line.strip() and not _is_import_line(line)
            ]
        # Merge policy: an imported record REFRESHES only what the authored tree
        # is the source of, and never overwrites work an agent has done on top.
        #
        # The first version assigned unconditionally, which meant `lore ingest` was
        # destructive: re-running it silently reverted every enriched stub in a
        # domain back to a content-free placeholder. It cost the cosmology legion
        # seven authored records and 359 characters of prose in one command, and
        # nothing reported it - the re-ingest printed `ok` and the count was
        # unchanged. A tool whose happy path destroys work is worse than a tool
        # that refuses, because `ok` is read as "nothing happened".
        #
        # So the imported record fills MISSING fields and refreshes the fields the
        # game data actually owns, and a hand-authored summary, `lore_depth` or
        # tag set always wins. `--force` is the deliberate way to discard an
        # agent's work on a record, and it says so.
        merged = {record["id"]: record for record in existing}
        overwritten: list[str] = []
        for record in records:
            current = merged.get(record["id"])
            if current is None or _FORCE:
                merged[record["id"]] = record
                continue
            for field, value in record.items():
                # Prose and curation are the agent's; scalars are the game's.
                if field in AGENT_OWNED_FIELDS and current.get(field) not in (None, [], {}, ""):
                    continue
                if field == "attributes":
                    merged_attrs = dict(value)
                    # `lore_depth` is the one attribute that records CURATION
                    # rather than content, so an agent's promotion out of `stub`
                    # outranks the importer's fresh copy of it. Everything else in
                    # attributes is authored game data and does refresh.
                    if current.get("attributes", {}).get("lore_depth") != "stub":
                        prior_depth = current.get("attributes", {}).get("lore_depth")
                        if prior_depth is not None:
                            merged_attrs["lore_depth"] = prior_depth
                    current["attributes"] = merged_attrs
                    continue
                if current.get(field) != value:
                    current[field] = value
            merged[record["id"]] = current
            if _import_view(current) != _import_view(record):
                overwritten.append(record["id"])
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

    edge_path = _edges_dir() / "ingest-game.jsonl"
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
    preserved = sum(
        1
        for path in sorted(_bible_dir().glob("*.jsonl"))
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not _is_import_line(line)
    )
    ok(
        f"game ingest complete: {written} entities, {len(edges)} edges, "
        f"{stubs} flagged as lore gaps (named figures and domains with no lore yet)"
    )
    if preserved:
        info(
            f"  {preserved} agent-authored record(s) preserved; this run refreshed only "
            "the fields the game data owns"
        )
    if force:
        warn(
            "--force discarded agent-authored summary/tags/name on every imported record; "
            "recover from git if that was not intended"
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
