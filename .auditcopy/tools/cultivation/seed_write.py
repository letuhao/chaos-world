"""Decide what a seed generator would do to a file it already wrote.

Both seed tasks end the same way: they build the COMPLETE map of intended
`relative path -> bytes` first, then touch the disk. That ordering is what makes
drift detectable at all, and this module is where the decision lives so the two
generators cannot hold two different answers to "is this file current?".

## Would-rewrite vs already-correct

The generator knows what it intends to say about a file, so the states are
separated by one exact comparison of the bytes it holds in memory against the
bytes on disk:

- **unchanged** - the file is present and identical. A quiet no-op. This is the
  state an unmodified tree is in, and it must stay silent: a generator that
  speaks on every healthy run is one nobody reads.
- **drift** - the file is present and differs, and the generator authors every
  property the file carries. `--force` may rewrite it; the default fails. This is
  DEF-0033: a corrected generator that silently disagrees with its own committed
  output, which is invisible until something is actually wrong.
- **protected** - the file is present and differs, and it carries properties the
  generator does NOT emit. See below; `--force` refuses these outright.
- **create** - the file is absent.

The comparison is total and exact, so there is no heuristic and no tolerance to
tune: `==` on the encoded text answers it, and a file that is byte-identical is
current by definition.

## Why `--force` is not a blind overwrite

This is the half that matters, and it was not a guess: measured against the
shipped corpus, 240 of 410 `seed` files and 450 of 660 `seed_systems` files
already differ from what their generator writes. Most of that is the ITEM SCHEMA
having outgrown the generator - committed items carry `fixed_modifiers`,
`rarity`, `realm` and `roll_spec`, which no generator emits. A `--force` that
overwrote those would DELETE authored properties it has no value for, across
420 item files, and report success while doing it.

So `--force` writes a file only when the generator authors every property the
file carries. If the file holds a property the generator does not produce, the
file has outgrown the generator, the generator cannot express what should replace
it, and overwriting is data loss rather than a fix. That case is refused under
every flag. It is the "never overwrite a hand-authored file" rule, and it is
decidable from the two texts alone - no manifest, no marker, no git.

A generator bug fix is still re-appliable, which is what DEF-0033 asked for:
when the fix makes the generator emit the property the file already has, the key
sets agree and `--force` proceeds normally.

## What each mode does

- default: drift AND protected both FAIL, naming the file and the unified diff.
  Silence here is what let the drift hide in the first place. Nothing is written.
- `--dry-run`: report every class, write nothing, exit 0. A guard nobody can
  preview is an obstacle, so the preview has to be a mode and not a promise.
- `--force`: rewrite `drift`, printing every diff it applies, and SKIP
  `protected` — naming each one and the properties it would have deleted.

`--force` skips rather than aborting on a protected file deliberately. Aborting
was measured to be useless: on the shipped corpus 150 outgrown items blocked all
90 safe rewrites, so the flag could never succeed on any real tree and would have
been deleted on first use. Partial application, with the residue named, is both
useful and safe. It exits 0 because the operation it was asked to do succeeded;
the skipped files are reported by name, so the residue is visible rather than
assumed away.

## The invariant this preserves

`seed.py` is a BOOTSTRAP. The `.tres` is the authored artefact the runtime reads
and the balance lives in; the generator is a mirror of it (DEF-0084 corrected the
FORMULAS to reproduce the shipped seeds, not the reverse). `--force` therefore
adds no new licence: it only makes the bootstrap's intent explicit about files
the generator itself emitted and fully understands. A path this generator does
not emit is never a candidate, under any flag, so no hand-authored file can be
reached by it.
"""

from __future__ import annotations

import difflib
import re
from dataclasses import dataclass, field
from pathlib import Path

from ..common import ToolError, fail, info, ok, warn

# A top-level Godot property: `name = value` in column 0. Section headers
# (`[gd_resource ...]`, `[ext_resource ...]`) open with `[` and cannot match,
# and a nested `key = value` is indented, so this reads the file's own property
# surface and nothing else.
_PROPERTY = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*) = ", re.M)


def properties(text: str) -> set[str]:
    """The property names a `.tres` declares at the top level."""
    return set(_PROPERTY.findall(text))


@dataclass
class Plan:
    """One classification per path the generator emits. Bounded by `files`."""

    root: Path
    create: list[str] = field(default_factory=list)
    unchanged: list[str] = field(default_factory=list)
    drift: list[str] = field(default_factory=list)
    protected: list[str] = field(default_factory=list)

    @property
    def offending(self) -> list[str]:
        """Paths the default mode must fail on. Both are the file's disagreement."""
        return self.drift + self.protected

    @property
    def clean(self) -> bool:
        return not self.offending


def plan(root: Path, files: dict[str, str]) -> Plan:
    """Classify every intended file. Never writes, never reads outside `files`.

    The walk is bounded by the generator's own map: one visit per emitted path,
    and the map is built from a fixed realm ladder, so there is no count that
    grows while the loop runs (INC-0002).
    """
    result = Plan(root=root)
    for relative in sorted(files):
        path = root / relative
        intended = files[relative]
        if not path.exists():
            result.create.append(relative)
            continue
        current = path.read_text(encoding="utf-8")
        if current == intended:
            result.unchanged.append(relative)
            continue
        # A property the generator cannot express is authored content. Writing
        # our version would delete it, so this is not drift we may resolve.
        if properties(current) - properties(intended):
            result.protected.append(relative)
        else:
            result.drift.append(relative)
    return result


def diff_for(root: Path, relative: str, intended: str) -> str:
    """Unified diff of on-disk -> intended, so the message shows the difference."""
    path = root / relative
    current = path.read_text(encoding="utf-8").splitlines(keepends=True)
    return "".join(
        difflib.unified_diff(
            current,
            intended.splitlines(keepends=True),
            fromfile=f"{relative} (on disk)",
            tofile=f"{relative} (generator)",
            n=1,
        )
    )


def _describe(result: Plan) -> str:
    return (
        f"{len(result.create)} to create, {len(result.unchanged)} already current, "
        f"{len(result.drift)} rewritable, {len(result.protected)} protected"
    )


def _show(root: Path, relative: str, files: dict[str, str]) -> None:
    fail(f"  {relative}")
    info(diff_for(root, relative, files[relative]))


def apply(
    files: dict[str, str],
    root: Path,
    *,
    label: str,
    force: bool = False,
    dry_run: bool = False,
) -> int:
    """Write what the generator emits, subject to the drift rule. Returns an exit code."""
    result = plan(root, files)

    if dry_run:
        # Always exit 0: this is the preview that makes the failure usable, and a
        # report that fails is the obstacle the preview exists to remove.
        for relative in result.drift:
            info(f"would rewrite  {relative}")
        for relative in result.protected:
            info(f"REFUSED       {relative} (declares a property the generator does not emit)")
        for relative in result.create:
            info(f"would create  {relative}")
        ok(f"[dry-run] {label}: {_describe(result)}; wrote nothing")
        return 0

    if result.drift and not force or result.protected and not force:
        fail(
            f"{label}: {_describe(result)}. The generator disagrees with committed output;"
            " seeding has not touched anything."
        )
        limit = 5
        if result.drift and not force:
            fail(f"{len(result.drift)} file(s) the generator fully authors -- fix or --force:")
            for relative in result.drift[:limit]:
                _show(root, relative, files)
            if len(result.drift) > limit:
                fail(f"  ... and {len(result.drift) - limit} more")
        if result.protected:
            fail(
                f"{len(result.protected)} file(s) declare a property this generator does not"
                " emit, so overwriting them would delete authored content. --force will NOT"
                " touch these; the generator has to be taught the property first:"
            )
            for relative in result.protected[:limit]:
                _show(root, relative, files)
            if len(result.protected) > limit:
                fail(f"  ... and {len(result.protected) - limit} more")
        raise ToolError(
            f"{label}: {len(result.offending)} file(s) disagree with the generator."
            " Review with --dry-run; --force rewrites only the"
            f" {len(result.drift)} it fully authors."
        )

    written = 0
    if result.drift:
        # --force reached here, so every one of these is a file the generator
        # authors in full. Announce each diff before writing it: the value of
        # --force is that the change is never invisible.
        for relative in result.drift:
            info(f"rewriting {relative} (--force)")
            info(diff_for(root, relative, files[relative]))
            (root / relative).write_text(files[relative], encoding="utf-8")
            written += 1
    for relative in result.create:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(files[relative], encoding="utf-8")
        written += 1

    # A skipped file is reported, never swallowed, and never blocks the rewrites
    # it CAN do: refusing the whole run because one file outgrew the generator
    # would make `--force` permanently unable to succeed, and a flag that can
    # never run is one that gets deleted. It is listed by name, so the residue
    # is visible rather than assumed away.
    if result.protected:
        for relative in result.protected[:5]:
            extra = sorted(
                properties((root / relative).read_text(encoding="utf-8"))
                - properties(files[relative])
            )
            warn(
                f"refused {relative}: carries propert{'y' if len(extra) == 1 else 'ies'} the"
                f" generator does not emit ({', '.join(extra)})"
            )
        if len(result.protected) > 5:
            warn(f"  ... and {len(result.protected) - 5} more refused")
        warn(
            f"{len(result.protected)} file(s) still disagree with the generator and were NOT"
            " touched; the generator has to learn those properties first"
        )

    if written:
        ok(f"{label}: wrote {written} resource(s); {_describe(result)}")
    else:
        # The healthy case stays quiet but is never silent: an unchanged corpus
        # IS the result, and "created 0" alone reads like the task did nothing.
        ok(f"{label}: no changes ({_describe(result)})")
    return 0
