"""Audit and maintain the item-to-art links in the asset index."""

from __future__ import annotations

import json
import os
import re
import tempfile
from collections import Counter
from pathlib import Path

from .common import GAME_DIR, REPO_ROOT, ToolError, fail, ok

ITEM_ROOT = GAME_DIR / "data" / "items"
INDEX_PATH = GAME_DIR / "assets" / "asset-index.jsonl"
MATCH_FIELDS = {"category", "subcategory", "id_prefix"}


def register(subparsers) -> None:
    parser = subparsers.add_parser("assets", help="audit and maintain item art links")
    actions = parser.add_subparsers(dest="assets_action", required=True)
    report = actions.add_parser("report", help="show item coverage and asset-family distribution")
    report.add_argument("--all", action="store_true", help="show every asset family")
    actions.add_parser("audit", help="fail on missing, stale, or conflicting item art links")
    actions.add_parser("sync", help="refresh item_ids in asset-index.jsonl from item match rules")


def run(args) -> int:
    items = _load_items()
    records = _load_index()
    issues: list[str] = []
    winners = _resolve(items, records, issues)

    if args.assets_action == "sync":
        if issues:
            raise ToolError("cannot sync asset links:\n" + "\n".join(issues))
        _write_links(records, winners)
        ok(f"updated {INDEX_PATH.relative_to(REPO_ROOT).as_posix()} ({len(items)} item seeds)")
        return 0

    linked, link_issues = _read_links(items, records, winners)
    issues.extend(link_issues)
    _print_report(items, records, linked, issues, show_all=getattr(args, "all", False))
    if args.assets_action == "audit":
        if issues:
            fail(f"asset audit failed: {len(issues)} issue(s)")
            return 1
        ok("asset audit complete")
    return 0


def _load_items() -> dict[str, dict[str, str]]:
    items: dict[str, dict[str, str]] = {}
    if not ITEM_ROOT.is_dir():
        raise ToolError(f"item directory not found: {ITEM_ROOT}")
    for path in sorted(ITEM_ROOT.rglob("*.tres")):
        text = path.read_text(encoding="utf-8")
        item_id = _scalar(text, "id")
        category = _scalar(text, "category")
        subcategory = _scalar(text, "subcategory")
        if not item_id or not category or not subcategory:
            raise ToolError(
                f"{path.relative_to(REPO_ROOT)}: item needs id, category, and subcategory"
            )
        if item_id in items:
            raise ToolError(f"duplicate item id '{item_id}'")
        items[item_id] = {"category": category, "subcategory": subcategory}
    return items


def _scalar(text: str, field: str) -> str:
    match = re.search(rf'(?m)^\s*{field}\s*=\s*&"([^"]*)"', text)
    return match.group(1) if match else ""


def _load_index() -> list[dict]:
    if not INDEX_PATH.is_file():
        raise ToolError(f"asset index not found: {INDEX_PATH}")
    records: list[dict] = []
    ids: set[str] = set()
    for line_number, line in enumerate(INDEX_PATH.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ToolError(f"{INDEX_PATH.name}:{line_number}: invalid JSON ({exc.msg})") from exc
        if not isinstance(record, dict):
            raise ToolError(f"{INDEX_PATH.name}:{line_number}: each line must be a JSON object")
        asset_id = record.get("id")
        match = record.get("match")
        if not isinstance(asset_id, str) or not asset_id:
            raise ToolError(f"{INDEX_PATH.name}:{line_number}: missing asset id")
        if asset_id in ids:
            raise ToolError(f"{INDEX_PATH.name}:{line_number}: duplicate asset id '{asset_id}'")
        ids.add(asset_id)
        if record.get("type") != "item_icon" or not isinstance(record.get("path"), str):
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' needs item_icon type and path"
            )
        if not isinstance(match, dict) or not match or set(match) - MATCH_FIELDS:
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' has an invalid match rule"
            )
        if any(not isinstance(value, str) or not value for value in match.values()):
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' has an empty match value"
            )
        asset_path = record["path"]
        if not asset_path.startswith("res://assets/"):
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' path must be under res://assets/"
            )
        local_path = GAME_DIR / asset_path.removeprefix("res://")
        if not local_path.is_file():
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' file is missing: {asset_path}"
            )
        item_ids = record.get("item_ids", [])
        if not isinstance(item_ids, list) or any(not isinstance(value, str) for value in item_ids):
            raise ToolError(
                f"{INDEX_PATH.name}:{line_number}: '{asset_id}' item_ids must be strings"
            )
        records.append(record)
    return records


def _matches(match: dict, item_id: str, item: dict[str, str]) -> bool:
    return all(
        key == "id_prefix"
        and item_id.startswith(value)
        or key != "id_prefix"
        and item.get(key) == value
        for key, value in match.items()
    )


def _specificity(match: dict) -> tuple[int, int, int]:
    # An id_prefix rule overrides category/subcategory rules; longer prefixes win.
    prefix = match.get("id_prefix", "")
    return (bool(prefix), len(prefix), bool(match.get("subcategory")))


def _resolve(
    items: dict[str, dict[str, str]], records: list[dict], issues: list[str]
) -> dict[str, str]:
    winners: dict[str, str] = {}
    for item_id, item in items.items():
        matches = [record for record in records if _matches(record["match"], item_id, item)]
        if not matches:
            issues.append(f"item {item_id}: no matching asset family")
            continue
        best_score = max(_specificity(record["match"]) for record in matches)
        best = [record for record in matches if _specificity(record["match"]) == best_score]
        if len(best) != 1:
            issues.append(
                f"item {item_id}: ambiguous asset families {', '.join(r['id'] for r in best)}"
            )
            continue
        winners[item_id] = best[0]["id"]
    return winners


def _read_links(
    items: dict[str, dict[str, str]], records: list[dict], winners: dict[str, str]
) -> tuple[dict[str, str], list[str]]:
    linked: dict[str, str] = {}
    issues: list[str] = []
    for record in records:
        asset_id = record["id"]
        for item_id in record.get("item_ids", []):
            if item_id not in items:
                issues.append(f"asset {asset_id}: stale item link '{item_id}'")
                continue
            previous = linked.get(item_id)
            if previous:
                issues.append(f"item {item_id}: linked to both {previous} and {asset_id}")
            else:
                linked[item_id] = asset_id
            expected = winners.get(item_id)
            if expected and expected != asset_id:
                issues.append(f"item {item_id}: links to {asset_id}, rule resolves to {expected}")
    for item_id in sorted(items.keys() - linked.keys()):
        issues.append(f"item {item_id}: missing asset link")
    for item_id in sorted(linked.keys() - winners.keys()):
        issues.append(f"item {item_id}: linked without a unique matching rule")
    return linked, issues


def _write_links(records: list[dict], winners: dict[str, str]) -> None:
    assignments: dict[str, list[str]] = {record["id"]: [] for record in records}
    for item_id, asset_id in winners.items():
        assignments[asset_id].append(item_id)
    for record in records:
        record["item_ids"] = sorted(assignments[record["id"]])
    content = "".join(
        json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n" for record in records
    )
    INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", newline="\n", dir=INDEX_PATH.parent, delete=False
        ) as temporary:
            temporary.write(content)
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, INDEX_PATH)
    finally:
        if temporary_path and temporary_path.exists():
            temporary_path.unlink()


def _print_report(
    items: dict[str, dict[str, str]],
    records: list[dict],
    linked: dict[str, str],
    issues: list[str],
    *,
    show_all: bool,
) -> None:
    counts = Counter(linked.values())
    used = sum(counts.get(record["id"], 0) > 0 for record in records)
    print(
        f"item seeds: {len(items)} | linked: {len(linked)} | gaps: {len(items) - len(linked)} "
        f"| asset families: {len(records)} | used: {used} | unused: {len(records) - used}"
    )
    distribution = [record for record in records if show_all or counts.get(record["id"], 0) > 0]
    distribution.sort(key=lambda value: (-counts.get(value["id"], 0), value["id"]))
    shown = distribution if show_all else distribution[:20]
    print(f"items per asset family (showing {len(shown)} of {len(distribution)} used):")
    for record in shown:
        print(f"  {record['id']}: {counts.get(record['id'], 0)}")
    if len(shown) < len(distribution):
        print(f"  ... {len(distribution) - len(shown)} more (pass --all)")
    if issues:
        print(f"issues: {len(issues)}")
        for issue in issues[:30]:
            print(f"  - {issue}")
        if len(issues) > 30:
            print(f"  ... {len(issues) - 30} more")
