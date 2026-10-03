"""Fail when a mutation probe is CARRIED BY A SHIPPED REF, which the tree guard cannot see.

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

#: Named findings per tip, then only counted, so a ref carrying hundreds cannot produce a
#: wall of output where the first few are what matter.
MAX_REPORTED = 12


@dataclass(frozen=True)
class CarriedMarker:
    """One marker present in the tree of one shipped ref's tip."""

    ref: str
    path: str
    line: int
    shape: str

    def describe(self) -> str:
        return f"{self.ref}:{self.path}:{self.line}  ({self.shape})"


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


def carried() -> list[CarriedMarker]:
    """Every marker carried by a shipped ref's TIP. This is what `check` gates on.

    One `git grep` per tip: git walks that tree and returns only the lines holding a root
    literal, so nothing here reads thousands of blobs one subprocess at a time, and the
    whole two-root sweep of `main` costs ~140ms. The line is then filtered through
    `SHAPE_RE`, which is what keeps the guard's own documentation and the tree's ~172 lines of
    lower-case prose about mutation testing out of the findings.
    """
    found: list[CarriedMarker] = []
    for ref in shipped_refs():
        for path, number, text in _candidate_lines(ref):
            hit = SHAPE_RE.search(text)
            if hit is not None:
                found.append(CarriedMarker(ref, path, number, hit.group(0)))
    return found


def _candidate_lines(ref: str) -> list[tuple[str, int, str]]:
    """`(path, line, text)` for every pre-filter hit in `ref`'s tree under `GUARDED`."""
    raw = _git(
        "grep",
        "-n",
        "-I",
        "-E",
        *_pattern_args(),
        ref,
        "--",
        *GUARDED,
    )
    prefix = f"{ref}:"
    hits: list[tuple[str, int, str]] = []
    for entry in raw.splitlines():
        # `<ref>:<path>:<line>:<text>`. The ref prefix is stripped by LENGTH rather than
        # split, so a path or a marker containing a colon cannot shift the columns.
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
    for shape in SHAPES:
        found = re.search(shape, text)
        if found:
            return found
    return None
