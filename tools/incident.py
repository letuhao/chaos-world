"""Inspect and maintain the incident log (docs/incidents.jsonl).

Deferred work records what was postponed. This records what ALREADY WENT WRONG,
so a rule that exists can be traced to the failure that wrote it — and so a repeat
of the same shape is recognisable rather than rediscovered from scratch.

Every entry is a resource or a repository hazard that actually occurred here:

  disk     — a run filled the disk (the Godot log rotating at 2 GB/file, unbounded)
  memory   — a run exhausted RAM (67 GB resident, 105 GB commit at ~0.3 GB/s)
  loop     — a run never terminated and had to be killed
  git      — a bulk revert or a path-less checkout destroyed another agent's work

An incident is never closed by deleting it. `done` keeps the trace and names the
guard that now prevents it, because "we fixed it" is not durable information —
"test_no_deferred_free.gd fails the build on the shape" is.
"""

from __future__ import annotations

import json
import re
from datetime import date

from .common import REPO_ROOT, ToolError, info, ok

INCIDENTS_PATH = REPO_ROOT / "docs" / "incidents.jsonl"
FIELDS = ("id", "kind", "title", "status", "impact", "cause", "guard", "created")

## The four shapes that have actually happened in this repo. A closed set on
## purpose: an open-ended `kind` would turn this into prose, and the whole value
## is that `tools incident report --kind memory` is a real query.
KINDS = ("disk", "memory", "loop", "git")

## `status` is not a free field either. `resolved` means a guard now fails the
## build on the shape; `mitigated` means a ceiling bounds it; `watching` means we
## know and have nothing enforcing it yet.
STATUSES = ("resolved", "mitigated", "watching", "open")


def register(subparsers) -> None:
    parser = subparsers.add_parser("incident", help="inspect/maintain docs/incidents.jsonl")
    actions = parser.add_subparsers(dest="incident_action", required=True)

    report = actions.add_parser("report", help="list incidents")
    report.add_argument("--kind", default=None, choices=KINDS)
    report.add_argument("--status", default=None, choices=STATUSES)

    search = actions.add_parser("search", help="search incidents by text")
    search.add_argument("query")

    add = actions.add_parser("add", help="record an incident")
    add.add_argument("--kind", required=True, choices=KINDS)
    add.add_argument("--title", required=True)
    add.add_argument("--impact", default="", help="what it cost")
    add.add_argument("--cause", default="", help="the mechanism, not the symptom")
    add.add_argument("--guard", default="", help="what now fails on this shape")
    add.add_argument("--status", default="open", choices=STATUSES)

    close = actions.add_parser("close", help="record the guard for an incident")
    close.add_argument("id")
    close.add_argument("--guard", required=True, help="what now prevents it")
    close.add_argument(
        "--status", default="resolved", choices=STATUSES, help="how well it is enforced"
    )

    actions.add_parser("validate", help="validate the incident file")


def run(args) -> int:
    action = args.incident_action
    if action == "report":
        return _report(args)
    if action == "search":
        return _search(args)
    if action == "add":
        return _add(args)
    if action == "close":
        return _close(args)
    if action == "validate":
        return _validate()
    raise ToolError(f"unknown incident action: {action}")


def _load() -> list[dict]:
    if not INCIDENTS_PATH.is_file():
        return []
    entries: list[dict] = []
    for lineno, raw in enumerate(INCIDENTS_PATH.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError as exc:
            raise ToolError(f"{INCIDENTS_PATH.name}:{lineno}: invalid JSON: {exc}") from exc
    return entries


def _save(entries: list[dict]) -> None:
    lines = [json.dumps(entry, ensure_ascii=False) for entry in entries]
    INCIDENTS_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _next_id(entries: list[dict]) -> str:
    highest = 0
    for entry in entries:
        match = re.match(r"INC-(\d+)$", str(entry.get("id", "")))
        if match:
            highest = max(highest, int(match.group(1)))
    return f"INC-{highest + 1:04d}"


def _report(args) -> int:
    entries = _load()
    if args.kind:
        entries = [entry for entry in entries if entry.get("kind") == args.kind]
    if args.status:
        entries = [entry for entry in entries if entry.get("status") == args.status]
    _print(entries)
    return 0


def _search(args) -> int:
    needle = args.query.lower()
    matches = [
        entry
        for entry in _load()
        if needle in " ".join(str(entry.get(f, "")) for f in FIELDS).lower()
    ]
    _print(matches)
    return 0


def _add(args) -> int:
    entries = _load()
    entry = {
        "id": _next_id(entries),
        "kind": args.kind,
        "title": args.title,
        "status": args.status,
        "impact": args.impact,
        "cause": args.cause,
        "guard": args.guard,
        "created": date.today().isoformat(),
    }
    entries.append(entry)
    _save(entries)
    ok(f"added {entry['id']}: [{entry['kind']}] {entry['title']}")
    return 0


def _close(args) -> int:
    """Record the guard. The entry is kept, never deleted — the trace is the point."""
    entries = _load()
    for entry in entries:
        if entry.get("id") == args.id:
            entry["guard"] = args.guard
            entry["status"] = args.status
            entry["resolved"] = date.today().isoformat()
            _save(entries)
            ok(f"{args.id} closed as {args.status}")
            return 0
    raise ToolError(f"no incident with id {args.id}")


def _validate() -> int:
    """Fail the build on a malformed incident log, and on an unenforced hazard.

    The second half is the point. An incident left at `open` is honest — but an
    incident with no guard on it is a rule we learned and did not write down, which
    is exactly how the next one happens.
    """
    entries = _load()
    seen: set[str] = set()
    for entry in entries:
        missing = [f for f in ("id", "kind", "title", "status") if not entry.get(f)]
        if missing:
            raise ToolError(f"{entry.get('id', '?')}: missing fields {missing}")
        if entry["id"] in seen:
            raise ToolError(f"duplicate id {entry['id']}")
        seen.add(entry["id"])
        if entry["kind"] not in KINDS:
            raise ToolError(f"{entry['id']}: kind {entry['kind']!r} is not one of {list(KINDS)}")
        if entry["status"] not in STATUSES:
            raise ToolError(
                f"{entry['id']}: status {entry['status']!r} is not one of {list(STATUSES)}"
            )
        # `open` is the only state allowed to lack a guard: it means known and not
        # yet enforced, which is a fact someone must act on. Everything else claims
        # to be handled, so it has to name how.
        if entry["status"] != "open" and not str(entry.get("guard", "")).strip():
            raise ToolError(
                f"{entry['id']}: status {entry['status']!r} but no guard recorded — "
                "say what now fails on this shape"
            )
    ok(f"incidents ok ({len(entries)} entries)")
    return 0


def _print(entries: list[dict]) -> None:
    if not entries:
        info("no matching incidents")
        return
    for entry in entries:
        info(
            "{id}  [{kind}]  [{status}]  {title}".format(
                id=entry.get("id", "?"),
                kind=entry.get("kind", "?"),
                status=entry.get("status", "?"),
                title=entry.get("title", ""),
            )
        )
        for key in ("impact", "cause", "guard"):
            value = str(entry.get(key, ""))
            if value:
                info(f"    {key}: {value}")
