"""The Lore Bible tool: `uv run python -m tools lore <command>`.

Canonical world data, deliberately NOT shaped like the engine. `game/data/*.tres`
is authored content and this index is the world that content comes from; where they
overlap, a lore record carries an `external_ref` to the `.tres` it absorbs, so the
correspondence is checkable without the bible depending on the game existing.

The commands exist to make one rule enforceable rather than aspirational: **search
before you create**. An agent that has not run `lore search` and `lore gaps` has
no way to know whether the thing it is inventing already exists, and a bible that
accumulates a second Ironpact is worse than one with a single Ironpact, because
the duplicate is invisible unless something measures for it. `brief` therefore
embeds the current state of a domain into the agent's task, and `audit` measures
structure rather than volume.
"""

from __future__ import annotations

import json

from ..common import ToolError, fail, info, ok
from . import ingest
from .analysis import (
    causal_chain,
    hubs_and_leaves,
    readiness,
    resolve_shot,
    search,
    show,
    summarise,
    traverse,
)
from .audit import audit as run_audit
from .audit import (
    audit_notes,
    contradictions,
    diversity,
    domain_coverage,
    duplicate_names,
    gaps,
    shared_labels,
    structural_duplicates,
)
from .brief import write_brief
from .model import LORE_ROOT, load_bible


def register(subparsers) -> None:
    parser = subparsers.add_parser("lore", help="query, validate and extend the Lore Bible")
    actions = parser.add_subparsers(dest="action", required=True)

    actions.add_parser("validate", help="fail on any schema, reference or structural problem")
    actions.add_parser("report", help="counts per domain, relation mix, coverage and depth")
    actions.add_parser("gaps", help="deterministic work queue: what is missing and why")
    actions.add_parser("audit", help="contradictions, duplicates and isolation")
    actions.add_parser("labels", help="imported entities that share a display name")
    actions.add_parser("coverage", help="per-domain depth and diversity, worst first")
    actions.add_parser("hubs", help="the most and least connected entities, and component count")

    find = actions.add_parser("search", help="find entities by id, name, tag or summary")
    find.add_argument("query")
    find.add_argument("--limit", type=int, default=20)
    find.add_argument("--domain")

    one = actions.add_parser("show", help="resolve one entity with its incident relationships")
    one.add_argument("id")

    walk = actions.add_parser("traverse", help="bounded breadth-first walk from an entity")
    walk.add_argument("id")
    walk.add_argument("--depth", type=int, default=2)
    walk.add_argument("--rel", action="append", help="restrict to these relation types")
    walk.add_argument("--direction", choices=("both", "out", "in"), default="both")

    chain = actions.add_parser("chain", help="walk backwards along causation: why does this exist")
    chain.add_argument("id")
    chain.add_argument("--depth", type=int, default=4)

    ready = actions.add_parser("readiness", help="can a character's context be walked end to end")
    ready.add_argument("chain", help="character | conflict | lineage")

    brief = actions.add_parser("brief", help="write an agent brief for a domain")
    brief.add_argument("domain")
    brief.add_argument("--batch", required=True, help="unique batch id; also the edge shard name")
    brief.add_argument("--focus", default="")

    register_cmd = actions.add_parser("domain", help="list registered domains")
    register_cmd.add_argument("--list", action="store_true", default=True)

    # The authored-game importer is a module with its own argparse fragment
    # because it also needs to be runnable as its own task (`lore_ingest`), which
    # keeps the migration a first-class, separately invokable step.
    ingest_parser = actions.add_parser("ingest", help="import authored game data as lore records")
    ingest_parser.add_argument(
        "--dry-run", action="store_true", help="report what would import and write nothing"
    )


def run(args) -> int:
    action = args.action
    if action == "ingest":
        if getattr(args, "dry_run", False):
            domains, edges, counts = ingest.build_import()
            ok(f"dry run: would import {sum(counts.values())} entities and {len(edges)} edges")
            for domain, count in sorted(counts.items()):
                ok(f"  {domain}: {count}")
            return 0
        return ingest.write_import()
    if action == "brief":
        write_brief(load_bible(), args.domain, batch=args.batch, focus=args.focus)
        return 0
    if action == "domain":
        bible = load_bible()
        info(f"lore root: {LORE_ROOT.relative_to(LORE_ROOT.parents[1]).as_posix()}")
        info(f"{len(bible.registry.domains)} domains, {len(bible.registry.relations)} relations")
        for name, spec in sorted(bible.registry.domains.items()):
            count = len(bible.by_domain().get(name, []))
            info(f"  {name:<16} {count:>5} entities   {spec['file']}")
        return 0

    bible = load_bible()

    if action == "validate":
        findings = run_audit(bible)
        for note in audit_notes(bible):
            info(f"note  {note}")
        if findings:
            for finding in findings:
                fail(finding)
            fail(f"lore validation failed: {len(findings)} issue(s)")
            return 1
        ok(f"lore bible valid: {len(bible.entities)} entities, {len(bible.edges)} edges")
        return 0

    if action == "report":
        return _report(bible)
    if action == "gaps":
        return _gaps(bible, args)
    if action == "audit":
        return _audit(bible)
    if action == "labels":
        findings = shared_labels(bible)
        if not findings:
            ok("no shared labels")
            return 0
        info(f"{len(findings)} label(s) shared by imported entities:")
        for finding in findings:
            info(f"  {finding}")
        return 0
    if action == "coverage":
        return _coverage(bible)
    if action == "hubs":
        payload = hubs_and_leaves(bible)
        info(f"graph components: {payload['components']}")
        info("most connected:")
        for row in payload["hubs"]:
            info(f"  {row['degree']:>4}  {row['id']}")
        info("least connected:")
        for row in payload["leaves"]:
            info(f"  {row['degree']:>4}  {row['id']}")
        return 0
    if action == "search":
        return _search(bible, args)
    if action == "show":
        print(
            json.dumps(
                show(bible, resolve_shot(bible, args.id)["id"]), indent=2, ensure_ascii=False
            )
        )
        return 0
    if action == "traverse":
        rels = set(args.rel) if args.rel else None
        payload = traverse(
            bible,
            resolve_shot(bible, args.id)["id"],
            rels=rels,
            depth=args.depth,
            direction=args.direction,
        )
        return _print_layers(payload)
    if action == "chain":
        payload = causal_chain(bible, resolve_shot(bible, args.id)["id"], depth=args.depth)
        return _print_chains(payload)
    if action == "readiness":
        payload = readiness(bible, args.chain)
        for hop in payload["hops"]:
            mark = "ok " if hop["ok"] else "GAP"
            info(f"  [{mark}] {hop['from']:<14} -> {hop['to']:<14} {hop['edges']:>5} edges")
        if payload["complete"]:
            ok(f"readiness chain {args.chain!r} is fully connected")
            return 0
        missing = [f"{h['from']}->{h['to']}" for h in payload["hops"] if not h["ok"]]
        fail(f"readiness chain {args.chain!r} breaks at: {', '.join(missing)}")
        return 1
    raise ToolError(f"unknown lore action {action}")


def _coverage(bible) -> int:
    """Domains ordered by how much work they need, not alphabetically.

    A coverage table sorted by name is a table you read once. Sorted by gap it is a
    queue: the emptiest, most monocultural domain is first, which is the order the
    next wave should be briefed in.
    """
    stats = diversity(bible)
    coverage = domain_coverage(bible)
    rows = []
    for domain, entry in stats.items():
        gap = 0.0 if entry["entities"] else 1.0
        if entry["monocultural"]:
            gap += 0.5
        rows.append((gap, domain, entry))
    rows.sort(key=lambda row: (-row[0], row[1]))
    info(f"{'domain':<16} {'ents':>5} {'stub':>5} {'auth':>5} {'typeH':>6} {'tagH':>6} {'deg':>5}")
    for gap, domain, entry in rows:
        cov = coverage[domain]
        marker = "  <-- needs work" if gap else ""
        info(
            f"{domain:<16} {entry['entities']:>5} {cov['stub']:>5} {cov['authored']:>5} "
            f"{entry['type_entropy']:>6.2f} {entry['tag_entropy']:>6.2f} "
            f"{entry['edge_density']:>5.1f}{marker}"
        )
    return 0


def _report(bible) -> int:
    payload = summarise(bible)
    info(f"LORE BIBLE  {payload['entities']} entities, {payload['edges']} edges")
    info("")
    info(f"{'domain':<16} {'ents':>5} {'types':>6} {'tagH':>6} {'deg':>6}")
    for domain, stats in sorted(payload["domains"].items()):
        info(
            f"{domain:<16} {stats['entities']:>5} {stats['types']:>6} "
            f"{stats['tag_entropy']:>6.2f} {stats['avg_degree']:>6.1f}"
        )
    info("")
    info("status mix: " + ", ".join(f"{k}={v}" for k, v in payload["statuses"].items()))
    info("relation mix:")
    for rel, count in sorted(payload["relations"].items(), key=lambda kv: (-kv[1], kv[0])):
        info(f"  {rel:<20} {count:>5}")
    return 0


def _gaps(bible, args) -> int:
    domain = getattr(args, "domain", None)
    findings = gaps(bible)
    if domain:
        findings = [finding for finding in findings if domain in finding]
    if not findings:
        ok("no gaps detected")
        return 0
    info(f"{len(findings)} gap(s):")
    for finding in findings:
        info(f"  {finding}")
    return 0


def _audit(bible) -> int:
    sections = {
        "contradiction": contradictions(bible),
        "duplicate name": duplicate_names(bible),
        "structural duplicate": structural_duplicates(bible),
    }
    total = 0
    for title, findings in sections.items():
        if not findings:
            ok(f"{title}: none")
            continue
        total += len(findings)
        info(f"{title}: {len(findings)}")
        for finding in findings[:25]:
            info(f"    {finding}")
        if len(findings) > 25:
            info(f"    ... and {len(findings) - 25} more")
    if total:
        fail(f"audit found {total} issue(s)")
        return 1
    ok("no contradictions, duplicate names or structural duplicates")
    return 0


def _search(bible, args) -> int:
    hits = search(bible, args.query, limit=args.limit, domain=args.domain)
    if not hits:
        info(f"no match for {args.query!r}")
        return 0
    for score, entity, why in hits:
        info(
            f"{score:>4} {why:<9} {entity['id']:<44} {entity.get('name', '')} "
            f"[{entity.get('domain')}/{entity.get('type')}]"
        )
    return 0


def _print_layers(payload) -> int:
    info(f"{payload['root']}: {payload['visited']} entities within depth {payload['depth']}")
    if payload["truncated"]:
        fail("traversal hit its visit ceiling and was truncated; narrow it with --rel")
    current = None
    for layer in payload["layers"]:
        if layer["depth"] != current:
            current = layer["depth"]
            info(f"  depth {current}")
        via = f"  <-{layer['via']}- {layer['from']}" if layer.get("via") else ""
        info(f"    {layer['id']:<44} {layer['name']}{via}")
    return 0


def _print_chains(payload) -> int:
    info(f"causal ancestry of {payload['root']} ({len(payload['roots'])} chain(s)):")
    for index, trail in enumerate(payload["roots"], 1):
        if not trail:
            info(f"  {index}. (no recorded cause - this entity is a root)")
            continue
        info(f"  {index}.")
        for step in trail:
            info(f"     -{step['rel']:<16} {step['id']:<40} {step['name']}")
    if payload["truncated"]:
        fail("chain walk hit its ceiling and was truncated")
    return 0
