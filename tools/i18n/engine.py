"""The i18n engine: inventory the display strings, assign slugs, and gate consistency.

Four jobs, and no fifth:

- `report`   — read-only inventory of every player-facing string in scope, by domain and
               kind; `--gaps` lists each remaining sink as `path:line kind`.
- `extract`  — assign every rewritable sink a stable slug and (with `--write`) rewrite it to
               `L.t(...)` and refresh the `en` catalogs. Dry-run by default, because the
               rewrite is the one step that touches shipped source.
- `baseline` — record the current per-file sink counts so `check` can fail on GROWTH.
- `check`    — the gate. It asserts the catalogs agree with the source, every key's hash
               matches its English, a file that already uses `L.t` carries no rewritten-away
               sink, and no UI file gained a sink since the baseline. It does not demand the
               whole tree be migrated at once: unmigrated files are inventoried, not failed.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

from ..common import REPO_ROOT, ToolError, info, ok, warn
from . import catalog, policy
from .scan import LIT_KINDS, REWRITABLE, Finding, Scan, scan_file

SCOPE_ROOTS = ("game/src/ui", "game/scenes", "game/data")

## The growth guard covers the code we write, not the data we author: a `.gd` sink can be
## fixed with `L.t`, a `.tscn`/`.tres` one cannot yet, so gating growth there would be a
## failure with no recourse.
GUARD_ROOT = "game/src/ui"
GAPS_REL = "game/locale/gaps.json"


def iter_files(repo_root: Path):
    """Every in-scope file, walked in a deterministic order a diff can rely on."""
    for root in SCOPE_ROOTS:
        base = repo_root / root
        if not base.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(name for name in dirnames if not name.startswith("."))
            for name in sorted(filenames):
                if not name.endswith((".gd", ".tscn", ".tres")):
                    continue
                path = Path(dirpath) / name
                yield path.relative_to(repo_root).as_posix(), path


def read_text(path: Path) -> str:
    """Read without newline translation, so a rewrite never flips LF to CRLF.

    `Path.read_text`/`write_text` translate `\\n` to the platform separator, and on Windows
    that turns an LF file into a CRLF one on save — a whole-file diff hiding a one-line edit.
    The tool reads and writes bytes-faithful text instead.
    """
    with path.open("r", encoding="utf-8", newline="") as handle:
        return handle.read()


def write_text(path: Path, text: str) -> None:
    """Write without newline translation (see [func read_text])."""
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def scan_all(repo_root: Path) -> list[tuple[str, Scan]]:
    out: list[tuple[str, Scan]] = []
    for rel, path in iter_files(repo_root):
        result = scan_file(rel, read_text(path))
        if result is not None:
            out.append((rel, result))
    return out


def _replacement(finding: Finding, original: str) -> str:
    """The text a sink is rewritten to. `original` is the current source slice of the span."""
    if finding.kind == "gd_const_kw":
        return "var"
    if finding.kind == "gd_prop_expr":
        return f"{policy.RESOLVER}({original})"
    slug = catalog.slug_for(finding.prefix, finding.english)
    return f'{policy.RESOLVER}("{slug}", "{catalog.escape(finding.english)}")'


def _apply(text: str, findings: list[Finding]) -> str:
    """Rewrite each finding back-to-front so earlier offsets stay valid."""
    for finding in sorted(findings, key=lambda f: f.start, reverse=True):
        text = (
            text[: finding.start]
            + _replacement(finding, text[finding.start : finding.end])
            + text[finding.end :]
        )
    return text


def _guard_counts(scans: list[tuple[str, Scan]]) -> dict[str, int]:
    """Sink counts per UI script: the number `check` fails if it GROWS."""
    counts: dict[str, int] = {}
    for rel, result in scans:
        if policy.scope_kind(rel) != "gd" or not rel.startswith(GUARD_ROOT + "/"):
            continue
        if result.findings:
            counts[rel] = len(result.findings)
    return counts


def _write_baseline(repo_root: Path, scans: list[tuple[str, Scan]]) -> bool:
    counts = _guard_counts(scans)
    path = repo_root / GAPS_REL
    text = json.dumps(counts, indent=2, sort_keys=True) + "\n"
    if path.is_file() and read_text(path) == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    write_text(path, text)
    return True


def _report(args) -> int:
    repo_root = Path(args.repo_root)
    by_kind: dict[str, int] = {}
    by_domain: dict[str, int] = {}
    unsupported = 0
    migrated = 0
    gaps: list[Finding] = []
    for _rel, result in scan_all(repo_root):
        if result.migrated:
            migrated += 1
        unsupported += len(result.unsupported)
        for finding in result.findings:
            by_kind[finding.kind] = by_kind.get(finding.kind, 0) + 1
            by_domain[finding.prefix] = by_domain.get(finding.prefix, 0) + 1
            if getattr(args, "gaps", False) and finding.kind in REWRITABLE:
                gaps.append(finding)
    info(f"in scope: {migrated} file(s) already use {policy.RESOLVER}")
    for kind in sorted(by_kind):
        info(f"  {kind:<14} {by_kind[kind]}")
    for domain in sorted(by_domain):
        info(f"  {domain:<14} {by_domain[domain]}")
    info(f"  unsupported (continued expressions): {unsupported}")
    if getattr(args, "gaps", False):
        info(f"rewritable gaps: {len(gaps)}")
        for finding in sorted(gaps, key=lambda f: (f.rel, f.line)):
            label = finding.english or "L.t(...)"
            info(f"  {finding.rel}:{finding.line}  {finding.kind}  {label}")
    return 0


def _extract(args) -> int:
    repo_root = Path(args.repo_root)
    write = bool(args.write)
    only = tuple(getattr(args, "only", []) or [])
    scans = scan_all(repo_root)
    rows: dict[tuple[str, str], dict[str, str]] = {}
    for rel, result in scans:
        domain = policy.domain_of(rel)
        if domain is None:
            continue
        for use in result.uses:
            rows.setdefault((domain.catalog, "en"), {})[use.key] = use.english
    planned: list[tuple[str, Path, str, list[Finding]]] = []
    total = 0
    for rel, result in scans:
        if only and not any(needle in rel for needle in only):
            continue
        targets = [f for f in result.findings if f.kind in REWRITABLE]
        if not targets:
            continue
        total += len(targets)
        for finding in targets:
            if finding.kind in LIT_KINDS:
                key = catalog.slug_for(finding.prefix, finding.english)
                rows.setdefault((finding.catalog, "en"), {})[key] = finding.english
        planned.append((rel, repo_root / rel, read_text(repo_root / rel), targets))
    info(f"{total} sink(s) in {len(planned)} file(s)")
    if not write:
        info("dry run: pass --write to rewrite source and refresh the en catalogs")
        return 0
    for rel, path, text, targets in planned:
        write_text(path, _apply(text, targets))
        info(f"rewrote {rel} ({len(targets)})")
    # The catalog is exactly what the tree references: every existing `L.t` plus every row
    # this rewrite introduced. An English edit therefore drops the dead row on the next run
    # rather than leaving an orphan `check` would flag.
    for (stem, locale), values in sorted(rows.items()):
        target = catalog.catalog_path(repo_root, stem, locale)
        if catalog.save(target, values, locale):
            info(f"wrote {target.relative_to(repo_root).as_posix()} ({len(values)})")
    if _write_baseline(repo_root, scan_all(repo_root)):
        info(f"refreshed {GAPS_REL}")
    ok("extract complete")
    return 0


def _baseline(args) -> int:
    repo_root = Path(args.repo_root)
    if _write_baseline(repo_root, scan_all(repo_root)):
        ok(f"wrote {GAPS_REL}")
    else:
        ok(f"{GAPS_REL} already current")
    return 0


def _key_matches(key: str, english: str) -> bool:
    """Whether a key's hash is the hash of its English (catches a hand-edited or typo'd key)."""
    match = re.match(r"^LOC_(?P<prefix>.+)_(?P<hash>[0-9A-F]+)$", key)
    if match is None:
        return False
    return catalog.slug_for(match.group("prefix"), english) == key


def _check(args) -> int:
    repo_root = Path(args.repo_root)
    problems = 0
    scans = scan_all(repo_root)
    uses_by_stem: dict[str, dict[str, str]] = {}
    seen: dict[str, str] = {}
    for rel, result in scans:
        domain = policy.domain_of(rel)
        if domain is None:
            continue
        if result.migrated:
            leftover = [f for f in result.findings if f.kind in REWRITABLE]
            if leftover:
                warn(
                    f"{rel}: {len(leftover)} sink(s) remain in a file that uses "
                    f"{policy.RESOLVER} - run `tools i18n extract --write`"
                )
                problems += 1
        for use in result.uses:
            previous = seen.get(use.key)
            if previous is not None and previous != use.english:
                warn(f"{rel}:{use.line}: key {use.key} is reused for different text")
                problems += 1
            seen[use.key] = use.english
            if use.english and not _key_matches(use.key, use.english):
                warn(f"{rel}:{use.line}: key {use.key} does not hash {use.english!r}")
                problems += 1
            uses_by_stem.setdefault(domain.catalog, {})[use.key] = use.english

    for stem, expected in sorted(uses_by_stem.items()):
        on_disk = catalog.load(catalog.catalog_path(repo_root, stem))
        for key, english in sorted(expected.items()):
            if key not in on_disk:
                warn(f"{stem}.tres is missing {key} ({english!r}) - run extract --write")
                problems += 1
            elif on_disk[key] != english:
                warn(f"{stem}.tres has {key} as {on_disk[key]!r}, source says {english!r}")
                problems += 1
        for key in sorted(set(on_disk) - set(expected)):
            warn(f"{stem}.tres has orphan row {key} that no source uses - drop it")
            problems += 1

    problems += _check_growth(repo_root, scans)
    if problems:
        warn(f"i18n: {problems} problem(s)")
        return 1
    ok("i18n catalogs agree with source")
    return 0


def _check_growth(repo_root: Path, scans: list[tuple[str, Scan]]) -> int:
    """Fail when a UI script gained a sink since the baseline (new hardcoded text)."""
    path = repo_root / GAPS_REL
    if not path.is_file():
        warn(f"{GAPS_REL} is missing; run `tools i18n baseline` to enable the growth guard")
        return 0
    baseline: dict[str, int] = json.loads(read_text(path))
    problems = 0
    counts = _guard_counts(scans)
    for rel, count in sorted(counts.items()):
        base = int(baseline.get(rel, 0))
        if count > base:
            warn(
                f"{rel}: {count} player-facing sink(s), baseline {base} - "
                "use L.t at the sink instead of hardcoding English"
            )
            problems += 1
        elif count < base:
            warn(f"{rel}: {count} sink(s) below baseline {base} - run `tools i18n baseline`")
    return problems


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "i18n", help="translation catalogs: report, extract, baseline, check"
    )
    actions = parser.add_subparsers(dest="action", required=True)
    for name, help_text in (
        ("report", "inventory player-facing strings (read-only)"),
        ("extract", "assign slugs and rewrite call sites"),
        ("baseline", "record sink counts so check fails on growth"),
        ("check", "gate: catalogs agree with source, and no sink grew"),
    ):
        action = actions.add_parser(name, help=help_text)
        action.add_argument("--repo-root", default=str(REPO_ROOT), help="repository root")
        if name == "report":
            action.add_argument("--gaps", action="store_true", help="list each rewritable sink")
        if name == "extract":
            action.add_argument("--write", action="store_true", help="apply the rewrite")
            action.add_argument(
                "--only",
                action="append",
                default=[],
                help="restrict to paths containing this substring; repeatable",
            )


def run(args) -> int:
    if args.action == "report":
        return _report(args)
    if args.action == "extract":
        return _extract(args)
    if args.action == "baseline":
        return _baseline(args)
    if args.action == "check":
        return _check(args)
    raise ToolError(f"unknown i18n action: {args.action}")
