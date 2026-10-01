"""Inspect and maintain the feature/module backlog (docs/backlog.jsonl)."""

from __future__ import annotations

import json
import re
from datetime import date

from .common import REPO_ROOT, ToolError, info, ok

BACKLOG_PATH = REPO_ROOT / "docs" / "backlog.jsonl"
FIELDS = ("id", "area", "title", "status", "source", "completed", "next")


def register(subparsers) -> None:
    parser = subparsers.add_parser("backlog", help="inspect/maintain docs/backlog.jsonl")
    actions = parser.add_subparsers(dest="backlog_action", required=True)

    report = actions.add_parser("report", help="list backlog items")
    report.add_argument("--status", default=None, help="filter by status")
    report.add_argument("--area", default=None, help="filter by area")
    report.add_argument("--open", action="store_true", help="only items not done")

    search = actions.add_parser("search", help="search backlog items by text")
    search.add_argument("query")

    add = actions.add_parser("add", help="add a backlog item")
    add.add_argument("--area", required=True)
    add.add_argument("--title", required=True)
    add.add_argument("--source", default="manual")
    add.add_argument("--next", dest="next_step", default="")

    done = actions.add_parser("done", help="mark a backlog item done")
    done.add_argument("id")

    update = actions.add_parser("update", help="update fields on a backlog item")
    update.add_argument("id")
    update.add_argument("--status", default=None)
    update.add_argument("--title", default=None)
    update.add_argument("--area", default=None)
    update.add_argument("--source", default=None)
    update.add_argument("--next", dest="next_step", default=None)

    actions.add_parser("validate", help="validate the backlog file")


def run(args) -> int:
    action = args.backlog_action
    if action == "report":
        return _report(args)
    if action == "search":
        return _search(args)
    if action == "add":
        return _add(args)
    if action == "done":
        return _done(args)
    if action == "update":
        return _update(args)
    if action == "validate":
        return _validate()
    raise ToolError(f"unknown backlog action: {action}")


def _load() -> list[dict]:
    if not BACKLOG_PATH.is_file():
        return []
    entries: list[dict] = []
    for lineno, raw in enumerate(BACKLOG_PATH.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError as exc:
            raise ToolError(f"{BACKLOG_PATH.name}:{lineno}: invalid JSON: {exc}") from exc
    return entries


def _save(entries: list[dict]) -> None:
    lines = [json.dumps(entry, ensure_ascii=False) for entry in entries]
    BACKLOG_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _next_id(entries: list[dict]) -> str:
    highest = 0
    for entry in entries:
        match = re.match(r"BL-(\d+)$", str(entry.get("id", "")))
        if match:
            highest = max(highest, int(match.group(1)))
    return f"BL-{highest + 1:04d}"


def _report(args) -> int:
    entries = _load()
    if args.status:
        entries = [entry for entry in entries if entry.get("status") == args.status]
    if args.area:
        entries = [entry for entry in entries if entry.get("area") == args.area]
    if args.open:
        entries = [entry for entry in entries if entry.get("status") != "done"]
    _print(entries)
    return 0


def _search(args) -> int:
    needle = args.query.lower()
    matches: list[dict] = []
    for entry in _load():
        haystack = " ".join(str(entry.get(field, "")) for field in FIELDS).lower()
        if needle in haystack:
            matches.append(entry)
    _print(matches)
    return 0


def _add(args) -> int:
    entries = _load()
    entry = {
        "id": _next_id(entries),
        "area": args.area,
        "title": args.title,
        "status": "todo",
        "source": args.source,
        "next": args.next_step,
    }
    entries.append(entry)
    _save(entries)
    ok(f"added {entry['id']}: {entry['title']}")
    return 0


def _done(args) -> int:
    entries = _load()
    for entry in entries:
        if entry.get("id") == args.id:
            entry["status"] = "done"
            entry["completed"] = date.today().isoformat()
            _save(entries)
            ok(f"{args.id} marked done")
            return 0
    raise ToolError(f"no backlog item with id {args.id}")


def _update(args) -> int:
    entries = _load()
    for entry in entries:
        if entry.get("id") == args.id:
            if args.status is not None:
                entry["status"] = args.status
            if args.title is not None:
                entry["title"] = args.title
            if args.area is not None:
                entry["area"] = args.area
            if args.source is not None:
                entry["source"] = args.source
            if args.next_step is not None:
                entry["next"] = args.next_step
            _save(entries)
            ok(f"{args.id} updated")
            return 0
    raise ToolError(f"no backlog item with id {args.id}")


def _validate() -> int:
    entries = _load()
    seen: set[str] = set()
    for entry in entries:
        missing = [field for field in ("id", "area", "title", "status") if not entry.get(field)]
        if missing:
            raise ToolError(f"{entry.get('id', '?')}: missing fields {missing}")
        if entry["id"] in seen:
            raise ToolError(f"duplicate id {entry['id']}")
        seen.add(entry["id"])
    ok(f"backlog ok ({len(entries)} items)")
    return 0


def _print(entries: list[dict]) -> None:
    if not entries:
        info("no matching backlog items")
        return
    for entry in entries:
        header = "{id}  [{status}]  {area}  {title}".format(
            id=entry.get("id", "?"),
            status=entry.get("status", "?"),
            area=entry.get("area", "?"),
            title=entry.get("title", ""),
        )
        info(header)
        for key in ("source", "next", "completed"):
            value = entry.get(key)
            if value:
                info(f"    {key}: {value}")
