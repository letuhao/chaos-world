"""The i18n engine: inventory the display strings, assign keys, gate consistency, translate.

- `report`   — read-only inventory of every player-facing string in scope, by domain and
               kind; `--gaps` lists each remaining sink as `path:line kind`.
- `extract`  — assign every rewritable sink a stable key and (with `--write`) rewrite it to
               `L.t(...)` and refresh the `en` catalogs. Dry-run by default, because the
               rewrite is the one step that touches shipped source.
- `baseline` — record the current per-file sink counts so `check` can fail on GROWTH.
- `check`    — the gate. Every referenced key resolves to a row (en exact, locale a subset),
               no catalog holds an orphan, and no UI file gained a sink since the baseline.
               Unmigrated files are inventoried, not failed.
- `export`   — write a per-locale translator template under `build/` (key + English to fill).
- `import`   — turn a filled template into `<owner>.<locale>.tres` subset catalogs.
"""

from __future__ import annotations

import csv
import io
import json
import os
import re
import subprocess
from pathlib import Path

from ..common import REPO_ROOT, ToolError, info, ok, warn
from . import catalog, policy
from .scan import REWRITABLE, Finding, Scan, Unsupported, scan_file

SCOPE_ROOTS = ("game/src/ui", "game/scenes", "game/data")

## The growth guard covers the code we write, not the data we author: a `.gd` sink can be
## fixed with `L.t`, a `.tscn`/`.tres` one cannot yet, so gating growth there would be a
## failure with no recourse.
GUARD_ROOT = "game/src/ui"
GAPS_REL = "game/locale/gaps.json"

## Surfaces a dry run can target, keyed by the kind each produces.
##
## **`sinks` is the only surface safe to `--write`.** A `.tres` display field is READ BY
## GAMEPLAY (`display_name` alone is read in 167 non-UI files — save, socket, settlement, read
## models), so replacing it with a slug corrupts behaviour, not just tests. A `.tscn` literal
## has no call site to carry the English, so `Label.text` returns the raw slug and a panel's
## `summary()` — the repo's UI test contract — would publish a slug. Both stay inventoried and
## are rewritten only with an explicit `--unsafe`, after the reader-side work lands.
SCOPES: dict[str, frozenset[str]] = {
    "sinks": frozenset(
        {"gd_prop_lit", "gd_prop_expr", "gd_return_lit", "gd_const_lit", "gd_const_kw"}
    ),
    "scenes": frozenset({"tscn_lit"}),
    "content": frozenset({"tres_lit"}),
}
SCOPES["all"] = frozenset().union(*SCOPES.values())
## `scenes` rewrites a `.tscn` whose text has no call site, so it refuses a write until a panel
## resolves the key at display. `sinks` and `content` both rewrite safely: both put a KEY in
## the source and the English in that owner's catalog.
UNSAFE_SCOPES = frozenset({"scenes", "all"})

## Every file `extract --write` is about to touch is copied here first, so a botched run is
## restorable without git — the tree is shared with live agents and a path-wide revert is
## forbidden. Gitignored, under `build/`.
BACKUP_ROOT = "build/i18n-backup"


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


def _backup(repo_root: Path, rel: str, text: str) -> None:
    """Copy a file's current bytes under `build/` before the rewrite touches it."""
    target = repo_root / BACKUP_ROOT / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    write_text(target, text)


def _dirty(repo_root: Path, rels: list[str]) -> list[str]:
    """Target files with uncommitted changes.

    A claimed path is not a CLEAN path (INC-0041): rewriting a dirty one sweeps a concurrent
    agent's work, so a migration reports these and refuses rather than losing someone's edits.
    """
    if not rels:
        return []
    result = subprocess.run(
        ["git", "status", "--porcelain", "--", *rels],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return []
    dirty: list[str] = []
    for line in result.stdout.splitlines():
        path = line[3:].strip().strip('"')
        if path:
            dirty.append(path)
    return dirty


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
    slug = finding.key or catalog.slug_for(finding.prefix, finding.english)
    if finding.kind in ("tscn_lit", "tres_lit"):
        # A scene value or a data field holds the bare key; the reader (a panel via L.t, or a
        # Control's auto-translate at draw) is what resolves it.
        return f'"{slug}"'
    # The English lives in the catalog, not at the call site (ADR 0918), so a text change is
    # a data change and a mod can override the key without editing src.
    return f'{policy.RESOLVER}("{slug}")'


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


def _load_catalogs(repo_root: Path) -> dict[str, dict[str, str]]:
    """Every catalog under `game/locale`, keyed by stem (`<owner>` or `<owner>.<locale>`)."""
    out: dict[str, dict[str, str]] = {}
    locale_dir = repo_root / catalog.CATALOG_DIR
    if locale_dir.is_dir():
        for path in sorted(locale_dir.glob("*.tres")):
            out[path.stem] = catalog.load(path)
    return out


def _catalog_parts(stem: str) -> tuple[str, str]:
    """`<owner>.<locale>` -> `(owner, locale)`; `<owner>` -> `(owner, "en")`."""
    if "." in stem:
        owner, _dot, locale = stem.rpartition(".")
        return owner, locale
    return stem, "en"


def _report(args) -> int:
    repo_root = Path(args.repo_root)
    scope = getattr(args, "scope", "sinks")
    by_kind: dict[str, int] = {}
    by_domain: dict[str, int] = {}
    unsupported = 0
    migrated = 0
    gaps: list[Finding] = []
    manual: list[Unsupported] = []
    for _rel, result in scan_all(repo_root):
        if result.migrated:
            migrated += 1
        unsupported += len(result.unsupported)
        manual.extend(result.unsupported)
        for finding in result.findings:
            by_kind[finding.kind] = by_kind.get(finding.kind, 0) + 1
            by_domain[finding.prefix] = by_domain.get(finding.prefix, 0) + 1
            if getattr(args, "gaps", False) and finding.kind in SCOPES[scope]:
                gaps.append(finding)
    info(f"in scope: {migrated} file(s) already use {policy.RESOLVER}")
    for kind in sorted(by_kind):
        info(f"  {kind:<14} {by_kind[kind]}")
    for domain in sorted(by_domain):
        info(f"  {domain:<14} {by_domain[domain]}")
    info(f"  unsupported (needs a human): {unsupported}")
    for name in ("sinks", "scenes", "content"):
        total = sum(count for kind, count in by_kind.items() if kind in SCOPES[name])
        info(f"  surface {name:<8} {total}")
    if getattr(args, "gaps", False):
        info(f"[{scope}] gaps: {len(gaps)}")
        for finding in sorted(gaps, key=lambda f: (f.rel, f.line)):
            label = finding.english or "L.t(...)"
            info(f"  {finding.rel}:{finding.line}  {finding.kind}  {label}")
        manual_sinks = [item for item in manual if item.rel.startswith("game/src/ui/")]
        info(f"[manual] {len(manual_sinks)} UI sink(s) the tool will not rewrite:")
        for item in sorted(manual_sinks, key=lambda u: (u.rel, u.line)):
            info(f"  {item.rel}:{item.line}  {item.reason}")
    return 0


def _extract(args) -> int:
    repo_root = Path(args.repo_root)
    write = bool(args.write)
    only = tuple(getattr(args, "only", []) or [])
    scope = getattr(args, "scope", "sinks")
    kinds = SCOPES[scope]
    if write and scope in UNSAFE_SCOPES and not getattr(args, "unsafe", False):
        raise ToolError(
            f"refusing to --write scope '{scope}': a .tscn literal has no call site to carry "
            "the English, so a panel's summary() would publish a key. Move the scene text into "
            "the panel first, then pass --unsafe."
        )
    scans = scan_all(repo_root)
    existing = _load_catalogs(repo_root)
    rows: dict[str, dict[str, str]] = {}
    for rel, result in scans:
        domain = policy.domain_of(rel)
        if domain is None:
            continue
        for use in result.uses:
            # The OWNER comes from the file that references the key, never from the key text:
            # `LOC_UI_PANELS_…` and `LOC_DESTINY_<id>_<field>` both carry underscores, so a key
            # cannot be split back into (owner, rest). The path is authoritative.
            owner = domain.catalog
            # A 1-arg call has no English in source; its row already lives in the owner catalog,
            # so preserve it rather than dropping it as an orphan.
            english = use.english or existing.get(owner, {}).get(use.key, "")
            if english:
                rows.setdefault(owner, {})[use.key] = english
    planned: list[tuple[str, Path, str, list[Finding]]] = []
    total = 0
    files = 0
    for rel, result in scans:
        if only and not any(needle in rel for needle in only):
            continue
        targets = [f for f in result.findings if f.kind in kinds]
        if not targets:
            continue
        total += len(targets)
        files += 1
        rewrites: list[Finding] = []
        for finding in targets:
            if finding.english:
                owner = finding.catalog
                taken = dict(existing.get(owner, {}))
                taken.update(rows.get(owner, {}))
                if not finding.key:
                    # A `.gd`/`.tscn` key is assigned here; a `.tres` content key was already
                    # DERIVED from the def id + field by the scanner, so the row and the data
                    # agree without reading the catalog.
                    finding.key = catalog.assign_key(finding.prefix, finding.english, taken)
                rows.setdefault(owner, {})[finding.key] = finding.english
            rewrites.append(finding)
        if rewrites:
            planned.append((rel, repo_root / rel, read_text(repo_root / rel), rewrites))
    info(f"[{scope}] {total} string(s) in {files} file(s)")
    if not write:
        if getattr(args, "preview", False):
            for rel, _path, text, targets in planned:
                for finding in sorted(targets, key=lambda f: f.start):
                    before = text[finding.start : finding.end]
                    info(f"  {rel}:{finding.line}  {before} -> {_replacement(finding, before)}")
        else:
            for rel, _path, _text, targets in planned:
                info(f"  {rel}  {len(targets)} sink(s)")
        for owner, values in sorted(rows.items()):
            info(f"  catalog {owner}.tres  {len(values)} row(s)")
        info("dry run: pass --write to rewrite source (sinks) and refresh the catalogs")
        return 0
    for rel, path, text, targets in planned:
        _backup(repo_root, rel, text)
        write_text(path, _apply(text, targets))
        info(f"rewrote {rel} ({len(targets)})")
    # The catalog is exactly what the tree references: every existing `L.t` plus every row
    # this rewrite introduced. An English edit therefore drops the dead row on the next run
    # rather than leaving an orphan `check` would flag.
    for owner, values in sorted(rows.items()):
        target = catalog.catalog_path(repo_root, owner)
        if catalog.save(target, values):
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
    catalogs = _load_catalogs(repo_root)
    referenced: dict[str, set[str]] = {}
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
            # The owner is the REFERENCING file's owner, never parsed from the key text — both
            # `LOC_UI_PANELS_…` and `LOC_DESTINY_<id>_<field>` contain underscores.
            referenced.setdefault(domain.catalog, set()).add(use.key)
            if use.english and not _key_matches(use.key, use.english):
                warn(f"{rel}:{use.line}: key {use.key} does not hash {use.english!r}")
                problems += 1
        # A `.tres` FIELD still holding English is a migration gap, not a gate failure: like an
        # unmigrated UI sink it is inventoried by `report --gaps`, and once the field holds a
        # KEY it arrives above as a `use` and is verified. `check` fails only what is migrated.

    # Every referenced owner must have an EN catalog carrying its keys exactly. A LOCALE catalog
    # may be a SUBSET — an untranslated key is owner-demand work, not a failure — but holds no
    # orphan. A row is not required to hash to its key (the key is stable, ADR 0918).
    for owner, keys in sorted(referenced.items()):
        on_disk = catalogs.get(owner, {})
        for key in sorted(keys - set(on_disk)):
            warn(f"{owner}.tres is missing {key} - run extract --write")
            problems += 1
    for stem, rows in sorted(catalogs.items()):
        owner, _locale = _catalog_parts(stem)
        for key in sorted(set(rows) - referenced.get(owner, set())):
            warn(f"{stem}.tres has orphan row {key} that no source derives - drop it")
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


def _export(args) -> int:
    """Write a translator template for one locale into `build/` — the list of strings to fill.

    A TEMPLATE, not a committed catalog: it carries every key with its English so a translator
    can fill the `translation` column. It lives under the gitignored `build/` so the repo never
    grows a per-language copy of the English. The result comes back through [func _import].
    """
    repo_root = Path(args.repo_root)
    locale = args.locale
    scans = scan_all(repo_root)
    catalogs = _load_catalogs(repo_root)
    reference: dict[str, dict[str, str]] = {}
    for rel, result in scans:
        domain = policy.domain_of(rel)
        if domain is None:
            continue
        for use in result.uses:
            owner = domain.catalog
            english = use.english or catalogs.get(owner, {}).get(use.key, "")
            if english:
                reference.setdefault(owner, {})[use.key] = english
        for finding in result.findings:
            # An UNMIGRATED content field: include it so a translator sees the whole list,
            # even before the sweep has written the key into the data.
            if finding.kind == "tres_lit" and finding.english:
                reference.setdefault(finding.catalog, {})[finding.key] = finding.english
    target = repo_root / "build" / "i18n" / f"{locale}.csv"
    target.parent.mkdir(parents=True, exist_ok=True)
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(["key", "owner", "english", "translation"])
    count = 0
    for owner in sorted(reference):
        for key in sorted(reference[owner]):
            writer.writerow([key, owner, reference[owner][key], ""])
            count += 1
    write_text(target, buffer.getvalue())
    ok(f"wrote {target.relative_to(repo_root).as_posix()} ({count} string(s) for '{locale}')")
    return 0


def _import(args) -> int:
    """Apply a filled template: every row with a non-empty `translation` becomes a row in
    `<owner>.<locale>.tres`. An untranslated row is left out, so the file stays a subset."""
    repo_root = Path(args.repo_root)
    locale = args.locale
    source = Path(args.csv)
    if not source.is_file():
        raise ToolError(f"{source} not found")
    by_owner: dict[str, dict[str, str]] = {}
    with source.open("r", encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            key = (row.get("key") or "").strip()
            owner = (row.get("owner") or "").strip()
            value = (row.get("translation") or "").strip()
            if not key or not owner or not value:
                continue
            by_owner.setdefault(owner, {})[key] = value
    for owner, values in sorted(by_owner.items()):
        target = catalog.catalog_path(repo_root, owner, locale)
        merged = catalog.load(target)
        merged.update(values)
        if catalog.save(target, merged, locale):
            info(f"wrote {target.relative_to(repo_root).as_posix()} ({len(merged)})")
    ok(f"imported {len(by_owner)} catalog(s) for '{locale}'")
    return 0


def _preflight(args) -> int:
    """Whether the migration's target files are safe to rewrite right now.

    Fails when any target carries uncommitted changes, so a migration never sweeps a
    concurrent agent's in-flight edit (INC-0041). Run this before every `extract --write`.
    """
    repo_root = Path(args.repo_root)
    scope = getattr(args, "scope", "sinks")
    kinds = SCOPES[scope]
    planned = [
        (rel, [finding for finding in result.findings if finding.kind in kinds])
        for rel, result in scan_all(repo_root)
    ]
    planned = [(rel, targets) for rel, targets in planned if targets]
    total = sum(len(targets) for _rel, targets in planned)
    info(f"[{scope}] {total} sink(s) in {len(planned)} file(s)")
    dirty = _dirty(repo_root, [rel for rel, _targets in planned])
    if dirty:
        warn(f"{len(dirty)} target file(s) carry uncommitted changes - do NOT migrate them:")
        for rel in dirty:
            warn(f"  {rel}")
        return 1
    ok(f"every target file is clean against HEAD; --write is safe ({len(planned)} files)")
    return 0


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "i18n",
        help="translation catalogs: report, extract, baseline, check, export, import",
    )
    actions = parser.add_subparsers(dest="action", required=True)
    for name, help_text in (
        ("report", "inventory player-facing strings (read-only)"),
        ("preflight", "check the target files are clean before a migration"),
        ("extract", "assign keys and rewrite call sites"),
        ("baseline", "record sink counts so check fails on growth"),
        ("check", "gate: catalogs agree with source, and no sink grew"),
        ("export", "write a translator template for a locale (build/i18n/<loc>.csv)"),
        ("import", "apply a filled template into <owner>.<locale>.tres"),
    ):
        action = actions.add_parser(name, help=help_text)
        action.add_argument("--repo-root", default=str(REPO_ROOT), help="repository root")
        if name in ("export", "import"):
            action.add_argument("--locale", required=True, help="locale code, e.g. vi")
        if name == "import":
            action.add_argument("csv", help="a filled template from `i18n export`")
        if name in ("report", "preflight", "extract"):
            action.add_argument(
                "--scope",
                choices=sorted(SCOPES),
                default="sinks",
                help="surface: sinks (safe to write), scenes, content, all",
            )
        if name == "report":
            action.add_argument("--gaps", action="store_true", help="list each gap")
        if name == "extract":
            action.add_argument("--write", action="store_true", help="apply the rewrite")
            action.add_argument("--preview", action="store_true", help="print every change")
            action.add_argument(
                "--unsafe",
                action="store_true",
                help="allow --write on scenes/content (see the refusal message)",
            )
            action.add_argument(
                "--only",
                action="append",
                default=[],
                help="restrict to paths containing this substring; repeatable",
            )


def run(args) -> int:
    if args.action == "report":
        return _report(args)
    if args.action == "preflight":
        return _preflight(args)
    if args.action == "extract":
        return _extract(args)
    if args.action == "baseline":
        return _baseline(args)
    if args.action == "check":
        return _check(args)
    if args.action == "export":
        return _export(args)
    if args.action == "import":
        return _import(args)
    raise ToolError(f"unknown i18n action: {args.action}")
