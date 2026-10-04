"""Fail when a mutation probe is CARRIED BY A SHIPPED REF or STAGED IN THE INDEX, which the
tree guard cannot see.

`game/tests/arch_rules/test_no_stranded_mutation.gd` reads `res://src` and `res://tests` off
disk, so a probe that reached a commit is undetectable by it: the checkout is clean, the
marker is in the ref, and every later run passes. In INC-0013 (BL-0615) a probe deleted the
first term of a nine-term conjunction gating all 29 Mind realm boundaries, and the shared
index swept it into a commit nobody had staged. The working tree was correct the whole time,
which is exactly why nobody noticed - everyone saw a right gate while the ref stayed broken.

Git is unreachable from GDScript at test time, so the tree half lives in the suite and this
ref half lives here. Two more reasons it belongs here: `git grep` reads a ref's blobs in one
subprocess (~140ms for both roots), and a check whose safety depends on booting Godot would
invert the reason `tools/godot.py` exists (INC-0004, INC-0005).

## The gate is a function of CURRENT STATE, and that is the whole design

The first version of this tool asked a different question: "did ANY commit ever introduce a
marker" (`git log --all -S`). That question cannot be satisfied. History is immutable, so the
moment a single probe is ever committed the answer is permanently yes and the check is
permanently red. It shipped that way: it reported two historical probes forever and
`tools check` could not pass again, which makes a guard worth exactly nothing - worse than
absent, because a permanently-red gate is a gate people learn to ignore. **A guard must be a
function of state that can change, or it is not a guard.** So `carried()` asks the only
question that can go green: does a shipped ref's TIP carry a marker?

That still catches BL-0615 at the moment it happened. The ref tip carried the marker while the
working tree was clean, so this was red exactly when the incident was live - before the
repair, not after. And it goes green the moment the file is repaired, which is what makes it
usable every commit rather than once.

## Shipped refs only, so the answer is the same on every machine

`git log --all` also walks `refs/stash` and the agent-local namespaces this repo accumulates
(`refs/recovery/stash-*`, `refs/codex/turn-diffs/checkpoints/*`). Those are transient local
state, absent from every clone, so a verdict that depends on them is not reproducible: the
same commit is clean for a colleague and red here. `shipped_refs()` therefore ALLOWLISTS
`refs/heads/` and `refs/remotes/` - the refs that are the repository. An allowlist, not a
denylist, so a new agent tool inventing a namespace cannot silently widen or narrow the
guard. `skipped_ref_namespaces()` names what was left out, so the blind spot is printed
rather than assumed.

## Prose that NAMES a mutation is not a probe, and the cut between them is adjacency

A shipped tip legitimately writes about its own mutation tests. `MUTATION-A`/`MUTATION-B` are
ids that outlive the probe and end up in the sentence explaining which assertion each one
defended, and three lines in `test_mind_stat_reachability.gd` are exactly that. Matching them
left the gate permanently red on FALSE POSITIVES - the same "a permanently-red gate is a gate
people learn to ignore" failure the state-not-history design exists to avoid, arriving by the
other door: the gate was red, the tree was correct, and the next person to hit it deletes it.

There is no lexical difference between the two things, so the cut has to be positional.
`is_documentation()` draws it at the marker's own offset:

- **Nothing but whitespace before it** - documentation. In GDScript that position is a
  multi-line string, and a tombstone string is a tombstone.
- **Code before it** - a live probe. `if not is_bound() and false:  # MUTATION-M6` is
  BL-0615's shape and nothing here may touch it.
- **Inside a comment** - live only when the marker is the comment's FIRST content. `#MUT-1`,
  `# MUT-1 removed` and `## MUT-1` are a probe LABELLED; `## ... MUT-B (the defence
  published)` is a sentence mentioning one.

Adjacency is the shape a probe author actually uses, because a probe comment exists to be
found by grepping it: the marker goes first. Prose puts the id where the sentence needs it.

This is deliberately NOT "ignore comments": `var x := 1  # MUT-1` carries a comment before
the marker too, and code in front of it, and stays red. What it gives up is a probe that is
ONLY a comment mentioning a mutation mid-sentence - byte-identical to the prose it now
clears, so no line-shaped rule can have both. `_live_marker` walks every match on the line
rather than `search`ing once, because a line can carry a documentation match first and a live
one after it.

`sweep()` keeps using `_marker_in()`, which is adjacency-blind on purpose: `report` is
forensic, so naming every line that ever held a marker is what makes it useful for locating
the commit, and it never gates.

## The INDEX, because a fix-forward revert repairs the worktree and leaves the index wrong

The ref half above is one commit too late: it goes red once the probe is IN history, when the
cheapest fix is no longer deleting the line that is about to ship. On 2026-10-04 that window was
one commit wide and real - `MUTATION-LOOTWORLDFULL` sat in the index of
`game/src/modules/loot/loot_state.gd`, staged by a second agent's `git add` while the probe was
still live, and the file read `MM` where its author's own edit predicted `M`. It was caught by
reading `git diff --cached`, not by any guard.

Reading the worktree harder does not close that window, which is the trap. A fix-forward revert
writes the correct line to the file and leaves the staged copy alone, so `git diff` shows the fix,
the tree reads clean, and the index still carries the probe - only `--cached` tells the two apart.
So `staged()` reads the INDEX (`git grep --cached`) and never touches disk.

It classifies with the SAME `_live_marker` the ref half uses. That is not tidiness: a second marker
grammar is a second opinion, and the two layers would then disagree about what a probe is, which
is the one failure this module's design exists to prevent. A staged probe and prose that NAMES one
are separated by exactly the cut `is_documentation` draws, so the false positives that once pinned
this gate permanently red cannot arrive through the new door either.

`carried()` puts the index findings FIRST, ahead of every tip, because those are the ones about
to become history and the ones a truncated report must not drop. When HEAD already carries a
probe the index matches it and both report it: two facts, not one. A guard that suppressed the
second because the first had fired would be a guard that stopped counting.

## What this deliberately does NOT catch

MARKED probes only, exactly like the tree guard. A probe that deletes a function, renames a
symbol or inverts a comparison and writes no marker leaves nothing to find and no text scan
could find it; that remains a finding to report, never a coin to re-roll. Nor does it scan
`res://data` (authored `.tres` carry no comments to mark), `game/tools/`, or `tools/` -
outside `res://`, and Python. Neither guard makes this suite mutation-complete.
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .common import REPO_ROOT

#: The repository this sweep reads. A module global rather than a local so a test can point
#: the guard at a fixture repository: `carried()` and `sweep()` shell out to git, and without
#: a seam the only way to test them is against the real history - which is how the first
#: version of this tool shipped reporting `ok` on a repo that contained a committed probe.
REPO: Path = REPO_ROOT

# `MUTAT` + `ION`, assembled so this file does not match itself.
MARKER = "MUTAT" + "ION"

#: One or more SPACES OR TABS, and deliberately not `\s`: `\s` also matches a newline, so a
#: `\s`-based shape can match a token at the end of one line against a token at the start of
#: the next, which the GDScript guard - line-bounded by construction - cannot do. Filtering
#: per line below makes these five shapes exactly the tree guard's, so the two halves of this
#: guard cannot drift apart.
GAP = r"[ \t]+"
ALNUM = r"[A-Za-z0-9]"

#: The five shapes as REGEXES, mirroring `test_no_stranded_mutation.gd`'s `SHAPES` exactly,
#: and used to read a line's text.
SHAPES: tuple[str, ...] = (
    rf"{MARKER}-{ALNUM}",
    rf"{MARKER}{GAP}PROBE",
    rf"#{GAP}{MARKER}",
    rf"//{GAP}{MARKER}",
    rf"XXX{GAP}MUTAT",
)

#: The same five as ONE alternation, for a single pass over a candidate line.
SHAPE_RE = re.compile("|".join(f"(?:{shape})" for shape in SHAPES))

#: The literals git searches for itself, one cheap pass, before `SHAPE_RE` decides. Every
#: shape above contains one of these, so the pre-filter cannot hide a real marker; and they
#: are deliberately BROAD, because on this tree the pre-filter also returns the guard's own
#: documentation (`test_no_stranded_mutation.gd` transcribes "# --- MUTATION 1: ..." as a
#: near-miss). That is the intended division of labour: git is fast and blunt, `SHAPE_RE` is
#: slow and precise, and precision belongs last.
GREP_PATTERNS: tuple[str, ...] = (MARKER, rf"XXX{GAP}MUTAT")

#: The roots, as they appear in git pathspecs, plus the extension. Same two roots the tree
#: guard walks, and same `.gd` only - `*.gd` is matched ACROSS directories in a git
#: pathspec, so `game/src/*.gd` covers every nested file.
GUARDED: tuple[str, ...] = ("game/src/*.gd", "game/tests/*.gd")

#: The refs that ARE the repository, for everyone, on every machine. Everything else in
#: `refs/` here is local: `refs/stash`, the `refs/recovery/stash-*` snapshots and the
#: `refs/codex/turn-diffs/checkpoints/*` tree an agent harness leaves behind. Sweeping those
#: makes the verdict depend on invisible local state (INC-0013's second probe was a dropped
#: stash, reachable only through `refs/recovery/*`).
SHIPPED_REFS: tuple[str, ...] = ("refs/heads/", "refs/remotes/")

#: Directories under `refs/` that exist for one machine rather than for the repository.
AGENT_LOCAL_NAMESPACES: tuple[str, ...] = (
    "refs/stash",
    "refs/recovery/",
    "refs/codex/",
    "refs/paseo/",
    "refs/worktree/",
    "refs/bisect/",
    "refs/notes/",
    "refs/rewritten/",
    "refs/original/",
    "refs/filter-repo/",
)

#: The label an index finding carries in `CarriedMarker.ref`. Not a ref and never resolved as
#: one - it exists so `describe()` prints `INDEX:game/src/...:42` and the reader can tell at a
#: glance that the content is staged rather than shipped. The real `git grep` prefix for the
#: index is empty, so this is the one place the two readers differ and it is a display concern
#: only; nothing classifies on it.
INDEX_REF = "INDEX"

#: The comment introducers GDScript uses. `##`, `###` and `#!` are the same one repeated, so
#: a run of `#` is skipped rather than compared against a single character.
COMMENT_OPENERS: tuple[str, ...] = ("//", "#")

#: How much of a finding's own line to echo. Long enough to show the code in front of the
#: marker - which is what makes the liveness call auditable - and short enough that a
#: minified line cannot flood the report.
SNIPPET_LIMIT = 72

#: Named findings per tip, then only counted, so a ref carrying hundreds cannot produce a
#: wall of output where the first few are what matter.
MAX_REPORTED = 12


@dataclass(frozen=True)
class CarriedMarker:
    """One LIVE marker present in the tree of one shipped ref's tip."""

    ref: str
    path: str
    line: int
    shape: str
    text: str

    def describe(self) -> str:
        snippet = self.text.strip()
        if len(snippet) > SNIPPET_LIMIT:
            snippet = snippet[: SNIPPET_LIMIT - 3] + "..."
        return f"{self.ref}:{self.path}:{self.line}  ({self.shape})  {snippet}"


@dataclass(frozen=True)
class CommittedProbe:
    """One commit that put a marker into a guarded path. FORENSIC ONLY - see `sweep()`."""

    commit: str
    path: str
    shape: str


def _git(*args: str) -> str:
    """Run git and return stdout, or `""` on any failure.

    Never raises: an unreadable repo must read as "cannot prove clean" rather than as a
    traceback out of a gate. `readable()` is what turns that into an actual verdict - a
    silent `""` here is indistinguishable from a clean tree, which is the anti-vacuity trap
    this file has already fallen into once.
    """
    try:
        done = subprocess.run(
            ("git", *args),
            cwd=REPO,
            capture_output=True,
            text=True,
            timeout=300,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return done.stdout if done.returncode == 0 else ""


def readable() -> bool:
    """True when git answers about this repository at all.

    The anti-vacuity term. Every function below returns an empty result when git fails, so
    without this a broken or missing repository reads as "no probes found" - a guard that
    reports `ok` because it looked at nothing, which is the failure mode this repo keeps
    producing. `check` fails when this is False.
    """
    return _git("rev-parse", "--git-dir").strip() != ""


def shipped_refs() -> list[str]:
    """The tips that make up the repository as every other clone sees them."""
    refs = [
        line.strip()
        for line in _git("for-each-ref", "--format=%(refname)", *SHIPPED_REFS).splitlines()
        if line.strip()
    ]
    # A detached HEAD is not under refs/, so an allowlist of namespaces would miss it, and a
    # probe committed while detached is exactly the case where nobody is watching the branch.
    if _git("symbolic-ref", "-q", "HEAD").strip() == "":
        refs.append("HEAD")
    return refs


def skipped_ref_namespaces() -> list[str]:
    """The local namespaces deliberately left out, so the blind spot is printed not assumed."""
    names = [line.strip() for line in _git("for-each-ref", "--format=%(refname)").splitlines()]
    found = [
        name
        for name in AGENT_LOCAL_NAMESPACES
        if any(candidate == name or candidate.startswith(name) for candidate in names)
    ]
    return found


def staged() -> list[CarriedMarker]:
    """Every LIVE marker held by the git INDEX under `GUARDED`. One commit from history.

    Read with `git grep --cached`, so the answer depends on the staged blobs and not on the
    working tree - which is the entire point (see the module docstring): after a fix-forward
    revert the file on disk is correct and the staged copy is still the probe, so every reader
    that opens the file reports clean and this one does not.

    `_live_marker` is the ref half's classifier, not a second grammar, so the index and the tips
    cannot drift apart about what counts as a probe. `carried()` calls this, so a staged probe
    fails `tools check` before it is ever committed.
    """
    found: list[CarriedMarker] = []
    for path, number, text in _staged_lines():
        hit = _live_marker(text)
        if hit is not None:
            found.append(CarriedMarker(INDEX_REF, path, number, hit.group(0), text))
    return found


def carried() -> list[CarriedMarker]:
    """Every LIVE marker the repository is holding: the INDEX first, then each shipped ref's TIP.

    This is what `check` gates on. Both halves matter and they are not the same question: a tip
    carrying a probe is already history (BL-0615), and an index carrying one is the commit that
    has not been made yet (2026-10-04, `MUTATION-LOOTWORLDFULL`) - the cheaper failure to catch
    and the only one a ref-tip read misses.

    One `git grep` per tip and one over the index: git walks that tree and returns only the lines
    holding a root literal, so nothing here reads thousands of blobs one subprocess at a time.
    The line is then filtered through `_live_marker`, which is what keeps the guard's own
    documentation, the tree's lower-case prose about mutation testing, and the shipped prose that
    NAMES a mutation id mid-sentence out of the findings.
    """
    found = staged()
    for ref in shipped_refs():
        for path, number, text in _candidate_lines(ref):
            hit = _live_marker(text)
            if hit is not None:
                found.append(CarriedMarker(ref, path, number, hit.group(0), text))
    return found


def is_documentation(line: str, start: int) -> bool:
    """True when the marker at `start` is prose that NAMES a mutation rather than a probe.

    Three cases, and the reasoning for each is in the module docstring. Line-bounded by
    construction: the only slice is `line[:start]`, and every branch returns, so this has no
    loop to bound.
    """
    before = line[:start].strip()
    if not before:
        return True
    if not before.startswith(COMMENT_OPENERS):
        # Code in front of the marker: BL-0615's shape, whatever else the line also holds.
        return False
    # `##` and `###` are one introducer repeated, so skip the whole run, then the gap.
    opener = 2 if before.startswith("//") else len(before) - len(before.lstrip("#"))
    # Comment text in front of the marker means the comment is TALKING ABOUT a mutation.
    return bool(before[opener:].strip())


def _live_marker(text: str) -> re.Match[str] | None:
    """The first LIVE marker on `text`, or None when the line only talks about one.

    `finditer`, not `search`: a line can carry a documentation match first and a live one
    after it, and taking the first match would clear it. Bounded by the match count on a
    finite line, and a malformed shape matches nothing at all rather than looping.
    """
    for hit in SHAPE_RE.finditer(text):
        if not is_documentation(text, _root_offset(hit)):
            return hit
    return None


def _root_offset(hit: re.Match[str]) -> int:
    """Where the marker token itself starts, not where the match starts.

    The two comment shapes include the introducer (`# MUTATION`, `// MUTATION`), so
    `hit.start()` points at the `#` and every commented marker then reads as documentation -
    the tree guard's own `#MUTATION-M1` and the shipped probes alike. `XXX MUTAT` carries no
    root token, so a miss means the match already begins at the marker.
    """
    inside = hit.group(0).find(MARKER)
    return hit.start() + (inside if inside >= 0 else 0)


def _candidate_lines(ref: str) -> list[tuple[str, int, str]]:
    """`(path, line, text)` for every pre-filter hit in `ref`'s tree under `GUARDED`."""
    return _parse_hits(
        _git("grep", "-n", "-I", "-E", *_pattern_args(), ref, "--", *GUARDED),
        f"{ref}:",
    )


def _staged_lines() -> list[tuple[str, int, str]]:
    """`(path, line, text)` for every pre-filter hit in the INDEX under `GUARDED`.

    `--cached` reads the staged blobs, so this does not care what is on disk. That is not a
    performance note, it is the property `staged()` is built on: the incident this closes had a
    CORRECT file on disk and the probe in the index, so a worktree reader sees nothing.

    No tree argument, hence an empty output prefix: `git grep --cached` prints `path:line:text`
    where the ref reader prints `ref:path:line:text`. The parse below takes that prefix as an
    argument, so there is one parser rather than two and the columns cannot drift apart.
    """
    return _parse_hits(
        _git("grep", "--cached", "-n", "-I", "-E", *_pattern_args(), "--", *GUARDED),
        "",
    )


def _parse_hits(raw: str, prefix: str) -> list[tuple[str, int, str]]:
    """`git grep` output as `(path, line, text)`, skipping `prefix` and anything malformed."""
    hits: list[tuple[str, int, str]] = []
    for entry in raw.splitlines():
        # `<ref>:<path>:<line>:<text>`, with `<ref>` absent for the index. The prefix is
        # stripped by LENGTH rather than split, so a path or a marker containing a colon cannot
        # shift the columns.
        if not entry.startswith(prefix):
            continue
        rest = entry[len(prefix) :]
        path, colon, remainder = rest.partition(":")
        number, _, text = remainder.partition(":")
        # A malformed line is skipped, never raised on: this runs inside a gate, and a
        # traceback out of `tools check` is indistinguishable to the reader from the guard
        # being broken.
        if not colon or not number.isdigit():
            continue
        hits.append((path, int(number), text))
    return hits


def _pattern_args() -> list[str]:
    """`-e <pattern>` for each pre-filter literal."""
    args: list[str] = []
    for pattern in GREP_PATTERNS:
        args.extend(("-e", pattern))
    return args


def sweep() -> list[CommittedProbe]:
    """Every commit that ever introduced a marker into a guarded path.

    FORENSIC ONLY, and it is deliberately not the gate. History is immutable, so this
    question has a permanently-yes answer the first time a probe is ever committed - which is
    why `check` gates on `carried()` instead. What this is good for is the question the gate
    cannot answer: a tip carrying a probe was clean ten commits ago, and this says which
    commit introduced it.

    `git log -S` is a substring COUNT, not a regular expression, and only the roots are
    passed to it: `-S 'MUTATION\\s'` searches for those twelve characters including the
    backslash and matches nothing. Not a subtlety noticed by reading - the first version of
    this tool passed the regexes straight to `-S`, reported clean on a repo containing a
    committed probe, and would have shipped as a guard that could never fire. The roots find
    every candidate commit; `SHAPE_RE` decides which is really a marker.
    """
    refs = shipped_refs()
    if not refs:
        return []
    found: dict[tuple[str, str], CommittedProbe] = {}
    for pickaxe in (MARKER, "XXX MUTAT"):
        raw = _git("log", "--format=%H", "-S", pickaxe, *refs, "--", *GUARDED)
        for commit in (line.strip() for line in raw.splitlines()):
            if not commit or commit in {key[0] for key in found}:
                continue
            probe = _probe_in(commit)
            if probe is not None:
                found[(commit, probe.path)] = probe
    return sorted(found.values(), key=lambda probe: (probe.commit, probe.path))


def _probe_in(commit: str) -> CommittedProbe | None:
    """The marker this commit introduced, or None if it carries no real marker shape.

    Read from the BLOB at that commit, never from disk. That is the whole ballgame: a commit
    that introduced and later removed a probe read as clean when the tool read the working
    tree, which is the entire class of defect it exists to find.
    """
    for path in _paths_in(commit):
        hit = _marker_in(_blob_at(commit, path))
        if hit is not None:
            return CommittedProbe(commit, path, hit.group(0))
    return None


def _paths_in(commit: str) -> list[str]:
    """The guarded paths `commit` touched, forward-slashed whatever the platform wrote."""
    raw = _git("show", "--format=", "--name-only", commit, "--", *GUARDED)
    paths = []
    for line in raw.splitlines():
        candidate = line.strip().replace("\\", "/")
        if candidate.endswith(".gd") and candidate.startswith(("game/src/", "game/tests/")):
            paths.append(candidate)
    return paths


def _blob_at(commit: str, path: str) -> str:
    """The content of `path` as `commit` recorded it."""
    return _git("show", f"{commit}:{path}")


def _marker_in(text: str) -> re.Match[str] | None:
    """The first marker SHAPE anywhere in `text`, adjacency-blind.

    Deliberately NOT `is_documentation`. This is the forensic reader: `sweep()` uses it to
    name every line a commit ever held a marker on, and for that question "the shape is in
    here" is the right answer even when the line is prose - narrowing it would hide the very
    commit a reader is hunting. The gate is `carried()`, which asks the sharper question.
    """
    for shape in SHAPES:
        found = re.search(shape, text)
        if found:
            return found
    return None
