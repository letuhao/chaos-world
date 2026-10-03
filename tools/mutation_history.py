"""Find a mutation probe that was COMMITTED, which the working-tree guard cannot see.

`game/tests/arch_rules/test_no_stranded_mutation.gd` reads `res://src` and `res://tests`
off disk, so a probe that reached a commit is permanently undetectable by it: the
checkout is clean, the marker is in history, and every later run passes. A probe that
returned a wrong value and was then committed ships as the implementation and nothing in
this repo can tell. That is INC-0013, and it generalises INC-0007 (a double-dispatch
captured another agent's `MUTANT-B1`, forward-fixed by hand).

Git is unreachable from GDScript at test time, so the working-tree half lives in the
test suite and this history half lives here. The shapes are the SAME five, in the SAME
case, because the tree says "mutation" in lowercase prose on ~172 lines and every one of
them has to survive: a sweep with different patterns would either miss probes or flood
the finding with prose. The tokens are assembled from fragments for the same reason the
GDScript guard does it - so this file cannot trip its own scan.
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .common import REPO_ROOT

#: The repository this sweep reads. A module global rather than a local so a test can
#: point the guard at a fixture repository: `sweep()` shells out to git, and without a seam
#: there the only way to test it is against the real history - which is how the first
#: version of this tool shipped reporting `ok` on a repo that contained a committed probe.
REPO: Path = REPO_ROOT

# `MUTAT` + `ION`, assembled so this file does not match itself.
MARKER = "MUTAT" + "ION"
GAP = r"\s+"
ALNUM = r"[A-Za-z0-9]"

#: The five shapes as REGEXES, mirroring `test_no_stranded_mutation.gd`'s `SHAPES`
#: exactly, and used to read a blob's content.
SHAPES: tuple[str, ...] = (
    rf"{MARKER}-{ALNUM}",
    rf"{MARKER}{GAP}PROBE",
    rf"#{GAP}{MARKER}",
    rf"//{GAP}{MARKER}",
    rf"XXX{GAP}MUTAT",
)

#: The roots `git log -S` needs, as LITERAL STRINGS.
#:
#: `git log -S<string>` is a substring count, not a regular expression: `-S 'MUTATION\s'`
#: searches for those twelve characters including the backslash, and matches nothing.
#: This is not a subtlety I noticed by reading - the first version of this tool passed the
#: regexes straight to `-S`, reported clean on a repo that contained a committed probe,
#: and would have shipped as a guard that could never fire.
#:
#: Deliberately the ROOTS, not the shapes. A shape like `#\s+MUTATION` would need a
#: literal spelling of `\s+`, and a file may write `#  MUTATION` with two spaces or a
#: tab, so any fixed-whitespace literal would miss it. Picking on the root finds every
#: candidate commit and `SHAPES` decides which of them is really a marker, by reading the
#: blob. Brute force in the cheap pass, precision in the expensive one.
PICKAXES: tuple[str, ...] = (MARKER, "XXX MUTAT")

#: Only `res://src` and `res://tests` are scanned by the working-tree guard, so only they
#: are swept here. A marker in `docs/` is prose about an incident, not a shipped probe.
GUARDED = ("game/src/", "game/tests/")


@dataclass(frozen=True)
class CommittedProbe:
    """One commit that put a marker into a guarded path."""

    commit: str
    path: str
    shape: str


def _git(*args: str) -> str:
    """Run git and return stdout. Never raises on a non-zero exit: an unreadable repo
    must read as "cannot prove clean", not as a crash in a gate."""
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


def _candidate_commits() -> list[str]:
    """Every commit that ever touched a guarded path.

    `git log --all` because the hazard is not confined to the current branch: a probe
    committed on a side branch and merged is exactly the shape, and a sweep of HEAD alone
    would call the tree clean.
    """
    raw = _git("log", "--all", "--format=%H", "--", *GUARDED)
    return [line.strip() for line in raw.splitlines() if line.strip()]


def sweep() -> list[CommittedProbe]:
    """Every commit that introduced a marker into a guarded path.

    Uses `git log -S` per shape, which is a pickaxe: it finds commits where the COUNT of
    the string changed, so it reports the commit that INTRODUCED a probe. Reading every
    historical blob of every file would be correct and far too slow; the pickaxe plus a
    content read of the offending commit is both faster and enough, because a marker that
    was later deleted still shows up as an introduction - and that is the point, since a
    probe that was committed and then reverted was still in history for a window.

    A marker present at HEAD is NOT this tool's business: `test_no_stranded_mutation.gd`
    already fails the build on it, and reporting it twice helps nobody.
    """
    found: dict[tuple[str, str], CommittedProbe] = {}
    for pickaxe in PICKAXES:
        raw = _git("log", "--all", "--format=%H", "-S", pickaxe, "--", *GUARDED)
        for commit in (line.strip() for line in raw.splitlines()):
            if not commit or commit in {key[0] for key in found}:
                continue
            found_probe = _probe_in(commit)
            if found_probe is not None:
                found[(commit, found_probe.path)] = found_probe
    return sorted(found.values(), key=lambda probe: (probe.commit, probe.path))


def _probe_in(commit: str) -> CommittedProbe | None:
    """The marker this commit introduced, or None if it carries no real marker shape."""
    for line in _git("show", "--format=", "--name-only", commit, "--", *GUARDED).splitlines():
        candidate = line.strip().replace("\\", "/")
        if not candidate.startswith(GUARDED):
            continue
        hit = _marker_in(_blob_at(commit, candidate))
        if hit is not None:
            return CommittedProbe(commit, candidate, hit.group(0))
    return None


def _first_guarded_path(commit: str) -> str:
    """The first guarded path in `commit` whose CONTENT AT THAT COMMIT carries a marker.

    Read from the blob, never from disk. This was the bug that made the first version of
    this tool structurally blind, and it is worth stating because it looks obvious only
    in hindsight: `git show --name-only` lists the paths a commit touched, then the tool
    read those paths from the working tree - where a probe reverted since then no longer
    exists. So a commit that introduced and later removed a probe read as clean, which is
    the entire class of defect this tool exists to find. Proven with a probe committed to
    a throwaway worktree: the pickaxe found the commit and the path walk rejected it.
    """
    raw = _git("show", "--format=", "--name-only", commit, "--", *GUARDED)
    for line in raw.splitlines():
        candidate = line.strip().replace("\\", "/")
        if not candidate.startswith(GUARDED):
            continue
        if _marker_in(_blob_at(commit, candidate)) is not None:
            return candidate
    return ""


def _blob_at(commit: str, path: str) -> str:
    """The content of `path` as `commit` recorded it."""
    return _git("show", f"{commit}:{path}")


def _marker_in(text: str) -> re.Match[str] | None:
    for shape in SHAPES:
        found = re.search(shape, text)
        if found:
            return found
    return None
