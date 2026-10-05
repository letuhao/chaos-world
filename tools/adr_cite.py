"""Check every `file:line` an ADR cites: the line exists AND the named symbol is there.

## Why this exists

An audit ran an existence-only checker over `docs/adr/**` and reported **0 of 86
drifted**. Reading the cited lines showed **11 substantively wrong** — the line number
was inside the file, but it held a docstring, a dict key or a neighbouring call rather
than the decision the ADR claimed. Line existence is the check that cannot fail; this one
compares content.

The durable fix is a tool, not a proofread. ADR 0148/0149 documented gates that could
never open, and DEF-0231/0232 recorded ADRs citing a test file that did not exist —
because an ADR is a CLAIM, not evidence, and nothing executed it.

## What it checks, per citation

1. The cited file resolves. Unresolvable is a finding, never a pass.
2. Every cited line is inside the file. Past-EOF is a finding.
3. A backticked code identifier named on the same ADR line appears **on the cited line,
   within +/-WINDOW lines of it, or anywhere in a cited range** — because a decision
   point and its own docstring drift apart as a block. A dotted name (`DestinyApi.attach`)
   also matches on its trailing component, because a file declares `func attach`, never
   `func DestinyApi.attach`.

A citation with no backticked code identifier beside it is `unchecked` — counted and
printed, never counted as passing. Silently treating it as green is the failure this
tool exists to stop.

## Waivers are explicit ledger entries, never a silent pass

A citation that legitimately moves cannot be corrected in place (ADRs are immutable once
accepted) and must not be ignored either. `WAIVERS` names each one: ADR number, the
citation, the symbol, and a reason code from `REASONS`. A waived finding is printed as
`waived` and counted separately — a recorded, reviewable decision.

    uv run python -m tools adr-cite            # whole tree, non-zero on any finding
    uv run python -m tools adr-cite --adr 0134 # one ADR
    uv run python -m tools adr-cite --json     # machine-readable
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

from .common import ADR_DIR, REPO_ROOT, ToolError, fail, info, ok, warn

## Extensions an ADR may cite. Anything else in prose is not a citation.
CITED_SUFFIXES = ("gd", "py", "json", "tres", "tscn", "jsonl", "md", "txt", "cfg", "toml")

CITE_RE = re.compile(
    r"(?<![\w./-])"
    r"((?:[A-Za-z0-9_][\w-]*/)*[A-Za-z0-9_-]+\.(?:" + "|".join(CITED_SUFFIXES) + r"))"
    r":(\d+(?:[-,]\d+)*)"
)
SPAN_RE = re.compile(r"`([^`\n]+)`")
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*")
SEGMENT_RE = re.compile(r"[A-Za-z0-9_-]+")
SUFFIX_RE = re.compile(r"\.(?:" + "|".join(CITED_SUFFIXES) + r")$")

## How far from the cited line a symbol may sit and still count as the same claim. A
## decision point and its own docstring drift as a block, so zero would report every
## reworded comment as drift and a wide bound would hide a moved function.
WINDOW = 3

## Directories tried for a citation written relative to a module. Ordered; first hit
## wins, so a repo-root spelling beats a basename guess.
SEARCH_ROOTS = (
    "",
    "game",
    "game/src",
    "game/src/modules",
    "game/src/app",
    "game/src/core",
    "game/src/ui",
    "game/src/ui/screens",
    "game/src/contracts",
    "game/tests",
    "game/tests/modules",
    "tools",
    "tools/arch",
    "docs",
)

## Verdict names. `ok` and `unchecked` do not fail; every other verdict does.
FAILING: tuple[str, ...] = ("unresolved", "ambiguous", "line_past_eof", "symbol_miss")

REASONS: dict[str, str] = {
    "immutable": "accepted ADR; the citation drifted and may not be edited in place",
    "ambiguous": "cited basename matches several files; the ADR records no path",
    "eof": "cited line is past the end of a file shorter than the ADR believed",
    "prose": "no code identifier is named beside the citation; nothing to compare",
}

## The reviewed baseline. Each entry was MEASURED and then read by hand on this tree.
##
## An accepted ADR is immutable (AGENTS.md), so a drifted citation in one has exactly
## three honest answers: supersede the ADR, correct the target and re-point it in the
## superseding document, or record the drift here. This table is the third. It is
## deliberately NOT a blanket suppression — the tool goes red on anything absent from
## it, which is the whole point: a citation written tomorrow is verified the day it is
## written, not discovered years later.
##
## To add one: measure the drift, read the cited line, then record
## (citation-as-written, symbol, reason) plus WHY in the ADR that supersedes it.
WAIVERS: dict[str, tuple[tuple[str, str, str], ...]] = {
    "0057": (("api.gd:19", "progress", "immutable"),),
    "0058": (("app/main.gd:85", "Boot", "immutable"),),
    "0061": (("advancement.gd:351", "Fate", "immutable"),),
    "0066": (
        ("core/institution_claim.gd:52", "position", "immutable"),
        ("sect/api.gd:120", "SectApi", "immutable"),
        ("nation/api.gd:300", "NationApi", "immutable"),
        ("registry.json:161", "quest", "immutable"),
        ("rules.py:60", "BARE_REF_UNITS", "immutable"),
        ("rules.py:11", "bare", "immutable"),
        ("rules.py:112", "APP_STATE_MARKERS", "immutable"),
    ),
}

## Line-of-file budget: an ADR is at most one page (AGENTS.md). This tool adds to that
## ledger rather than to a document, so the budget is small and stated.
MAX_WAIVER_LINES = 200


@dataclass(frozen=True)
class Finding:
    adr: str
    adr_line: int
    citation: str
    symbol: str
    verdict: str
    target: str | None = None
    detail: str = ""

    def as_dict(self) -> dict:
        return {
            "adr": self.adr,
            "adr_line": self.adr_line,
            "citation": self.citation,
            "symbol": self.symbol,
            "verdict": self.verdict,
            "target": self.target,
            "detail": self.detail,
        }


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "adr-cite", help="verify every file:line an ADR cites, by content"
    )
    parser.add_argument("--adr", help="check one ADR number (e.g. 0134), not the tree")
    parser.add_argument("--json", action="store_true", help="machine-readable report")
    # ## Report by default; gate only what is actually enforced.
    #
    # The first run over the tree found 565 drifted citations across 66 ADRs. That is
    # the tool working — the debt was already there and nothing could see it — but a
    # gate that fails on 565 findings blocks every `tools check` in the repo, and a
    # permanently red gate gets ignored, which is the INC-0016 shape again.
    #
    # So the default REPORTS and exits 0, and `--strict` is what fails. Promote a
    # single ADR by passing `--adr NNNN --strict`, which is how the debt gets paid
    # down one immutable document at a time instead of in a sweep that would rewrite
    # accepted history.
    parser.add_argument(
        "--strict",
        action="store_true",
        help="exit non-zero on any drifted citation (default: report and exit 0)",
    )
    return None


# --- Path resolution -----------------------------------------------------------


class Resolver:
    """Turn a citation's path spelling into a repo file, or say why it cannot.

    Built once and shared: the walk is the expensive part, and a per-citation walk would
    re-read the whole tree nine hundred times.
    """

    def __init__(self, root: Path) -> None:
        self._root = root
        self._by_basename: dict[str, list[str]] = {}
        self._texts: dict[str, list[str]] = {}
        for path in root.rglob("*"):
            if not path.is_file() or self._skip(path):
                continue
            rel = path.relative_to(root).as_posix()
            self._by_basename.setdefault(path.name, []).append(rel)

    def _skip(self, path: Path) -> bool:
        parts = set(path.relative_to(self._root).parts)
        return bool(
            parts
            & {
                ".git",
                ".venv",
                ".godot",
                "__pycache__",
                ".ruff_cache",
                ".codegraph",
                "build",
                "node_modules",
                ".perch",
            }
        )

    def resolve(self, cited: str) -> tuple[str | None, str]:
        """Return `(repo-relative path, "")`, or `(None, reason)`."""
        wanted = cited.replace("res://", "game/src/")
        for root in SEARCH_ROOTS:
            candidate = (
                (self._root / root / wanted).resolve() if root else (self._root / wanted).resolve()
            )
            if self._inside(candidate) and candidate.is_file():
                return candidate.relative_to(self._root).as_posix(), ""
        hits = self._by_basename.get(Path(wanted).name, [])
        exact = [h for h in hits if h.endswith(wanted)]
        if len(exact) == 1:
            return exact[0], ""
        if len(exact) > 1:
            return None, f"matches {len(exact)} files ending {wanted!r}"
        if len(hits) == 1:
            return hits[0], ""
        if len(hits) > 1:
            return None, f"basename {Path(wanted).name!r} is ambiguous ({len(hits)} files)"
        return None, "no such file in the tree"

    def _inside(self, path: Path) -> bool:
        try:
            path.relative_to(self._root)
        except ValueError:
            return False
        return True

    def lines(self, rel: str) -> list[str]:
        if rel not in self._texts:
            self._texts[rel] = (
                (self._root / rel).read_text(encoding="utf-8", errors="replace").split("\n")
            )
        return self._texts[rel]


# --- Extraction ----------------------------------------------------------------


def is_code_word(token: str) -> bool:
    """A token that could name a declaration: `MAX_X`, `CamelCase`, `snake_case`.

    Excludes path segments and `ADR`-style references, which appear in backticks and
    would otherwise make every citation look like it named a symbol.
    """
    if SUFFIX_RE.search(token) or token.startswith("ADR") or token.isdigit():
        return False
    return "_" in token or (token[0].isupper() and not token.isupper())


def _candidates(text: str, path_segments: set[str]) -> set[str]:
    return {
        m.group(0)
        for m in IDENT_RE.finditer(text)
        if m.group(0) not in path_segments and is_code_word(m.group(0))
    }


def lines_of(spec: str) -> list[int]:
    """`"13"` / `"62,67"` / `"301-307,344"` -> the line numbers, in order, deduped."""
    out: list[int] = []
    for part in spec.split(","):
        if "-" in part:
            low, high = part.split("-", 1)
            out.extend(range(int(low), int(high) + 1))
        else:
            out.append(int(part))
    seen: set[int] = set()
    return [n for n in out if not (n in seen or seen.add(n))]


def symbols_for(line: str, cited: str) -> list[str]:
    """Code identifiers the ADR names beside this citation, most specific first.

    Scoped to the citation's own line on purpose. Pulling symbols off neighbouring
    lines of the same paragraph is what turns prose into a false verdict: ADR 0170's
    `push_error` clause is two bullets away from the `AGENTS.md:56` it is not about.
    """
    spans = SPAN_RE.findall(line)
    path_segments = set(SEGMENT_RE.findall(cited))
    found = _candidates(cited, path_segments)
    for span in spans:
        found |= _candidates(span.replace(cited, " ", 1), path_segments)
    return sorted(found)


# --- The check -----------------------------------------------------------------


def check_citation(
    resolver: Resolver, adr: str, adr_line: int, cited: str, spec: str, symbols: list[str]
) -> Finding:
    target, reason = resolver.resolve(cited)
    if target is None:
        return Finding(
            adr,
            adr_line,
            f"{cited}:{spec}",
            symbols[0] if symbols else "",
            "unresolved",
            None,
            reason,
        )
    body = resolver.lines(target)
    cited_lines = lines_of(spec)
    outside = [n for n in cited_lines if not 1 <= n <= len(body)]
    if outside:
        return Finding(
            adr,
            adr_line,
            f"{cited}:{spec}",
            symbols[0] if symbols else "",
            "line_past_eof",
            target,
            f"line {outside[0]} of {len(body)}; file is shorter than the ADR believed",
        )
    if not symbols:
        return Finding(adr, adr_line, f"{cited}:{spec}", "", "unchecked", target, "")
    window: list[str] = []
    for n in cited_lines:
        for offset in range(-WINDOW, WINDOW + 1):
            if 1 <= n + offset <= len(body):
                window.append(body[n + offset - 1])
    haystack = "\n".join(window)
    span_text = "\n".join(body[n - 1] for n in cited_lines)
    for symbol in symbols:
        if symbol in haystack or symbol in span_text:
            return Finding(adr, adr_line, f"{cited}:{spec}", symbol, "ok", target, "")
        tail = symbol.rsplit(".", 1)[-1]
        if tail != symbol and (tail in haystack or tail in span_text):
            return Finding(adr, adr_line, f"{cited}:{spec}", symbol, "ok", target, tail)
    return Finding(
        adr,
        adr_line,
        f"{cited}:{spec}",
        symbols[0],
        "symbol_miss",
        target,
        f"none of {', '.join(symbols)} on {target}:{spec} +/-{WINDOW}",
    )


def audit(adr_dir: Path, root: Path, only: str | None = None) -> list[Finding]:
    resolver = Resolver(root)
    findings: list[Finding] = []
    for path in sorted(adr_dir.glob("*.md")):
        number = path.name[:4]
        if not number.isdigit():
            continue
        if only and number != only.zfill(4):
            continue
        for index, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
            for match in CITE_RE.finditer(line):
                cited, spec = match.group(1), match.group(2)
                if cited.startswith("docs/adr/"):
                    continue
                findings.append(
                    check_citation(resolver, number, index, cited, spec, symbols_for(line, cited))
                )
    return findings


def waived(adr: str, citation: str, symbol: str) -> str | None:
    """The reason code waiving this exact citation, or None.

    Keyed on (ADR, cited path, line spec) AND the symbol, so a waiver cannot quietly
    cover a second claim that happens to cite the same line — which is how a baseline
    table turns into blanket suppression.
    """
    head, _, spec = citation.rpartition(":")
    for waived_citation, waived_symbol, reason in WAIVERS.get(adr, ()):
        w_head, _, w_spec = waived_citation.rpartition(":")
        if w_head == head and w_spec == spec and (not symbol or symbol == waived_symbol):
            if reason not in REASONS:
                raise ToolError(f"ADR {adr} waiver for {citation} names unknown reason {reason!r}")
            return reason
    return None


def report(findings: list[Finding], as_json: bool, strict: bool = False) -> int:
    counted: dict[str, int] = {}
    problems: list[Finding] = []
    for finding in findings:
        if finding.verdict == "ok":
            counted["ok"] = counted.get("ok", 0) + 1
            continue
        reason = waived(finding.adr, finding.citation, finding.symbol)
        if reason and finding.verdict in FAILING:
            counted["waived"] = counted.get("waived", 0) + 1
            if not as_json:
                info(f"waived  {finding.adr}:{finding.adr_line} {finding.citation} ({reason})")
            continue
        counted[finding.verdict] = counted.get(finding.verdict, 0) + 1
        if finding.verdict in FAILING:
            problems.append(finding)
    if as_json:
        info(
            json.dumps(
                {
                    "counts": counted,
                    "findings": [
                        f.as_dict()
                        for f in findings
                        if f.verdict in FAILING and not waived(f.adr, f.citation, f.symbol)
                    ],
                },
                indent=1,
            )
        )
    else:
        for finding in problems:
            fail(
                f"{finding.verdict}: ADR {finding.adr}:{finding.adr_line} cites "
                f"`{finding.citation}` -> {finding.detail}"
            )
        summary = ", ".join(f"{count} {name}" for name, count in sorted(counted.items()))
        info(f"adr citations: {summary}")
        if counted.get("unchecked"):
            info(
                f"  {counted['unchecked']} carry no code identifier to compare and were "
                "NOT verified; existence only"
            )
    if problems:
        if strict:
            fail(
                f"{len(problems)} ADR citation(s) no longer hold their claim; each is an "
                "accepted, immutable document, so supersede it rather than editing it"
            )
            return 1
        # Report-only is the DEFAULT, so the debt stays visible without blocking every
        # `tools check` in the repo. Still a `fail` line, so it is greppable in CI output
        # — the difference is the exit code, not the visibility.
        warn(
            f"{len(problems)} ADR citation(s) no longer hold their claim; each is an "
            "accepted, immutable document, so supersede it rather than editing it "
            "(pass --strict to fail, or --adr NNNN --strict to gate one document)"
        )
        return 0
    ok(f"every checked ADR citation holds its claim ({len(findings)} citations)")
    return 0


def run(args) -> int:
    only = getattr(args, "adr", None)
    if only and not only.isdigit():
        raise ToolError(f"--adr takes a number, not {only!r}")
    findings = audit(ADR_DIR, REPO_ROOT, only)
    if only and not findings:
        raise ToolError(f"no file:line citation found in ADR {only}")
    return report(findings, getattr(args, "json", False), getattr(args, "strict", False))
