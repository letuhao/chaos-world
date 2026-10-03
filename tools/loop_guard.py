"""`uv run python -m tools loop_guard` — refuse a command that cannot terminate.

## Why

INC-0021: a sub-agent composed this one-liner to move a PNG into the repo.

    uv run python -c "...; data=b''.join(iter(lambda: sys.stdin.readline().strip().encode(),
    b'END_IMAGE_DATA')); ..."

It never terminated. `readline()` returns `''` forever once stdin hits EOF, and
`''.strip().encode()` is `b''`, which can **never** equal the `b'END_IMAGE_DATA'`
sentinel — so `iter()`'s stop condition is unreachable and `b''.join()` appended a
fresh `b''` on every pass. Eleven and a half gigabytes resident, 42 GB commit,
9067 s of CPU, all of it in a process that had already written its output file.

The shape is worth naming precisely, because it is not a general "infinite loop":

    iter(callable, sentinel)

terminates only if `callable()` can *return* `sentinel`. That holds when the
callable is a generator that yields the sentinel, or an iterator's own `__next__`
hitting a real terminator. It does **not** hold when the callable transforms the
value on the way out. `readline().strip().encode()` maps EOF's `''` to `b''`, so
if the sentinel is anything else — a marker string, a padded token — the loop is
already infinite on the first call, before any real data arrives.

## Why this is a guard and not a lint rule

Every existing guard is scoped to something addressable: `test_no_unbounded_wait.gd`
reads `res://src`, `RAM_CEILING_BYTES` watches a Godot launched through
`tools/godot.py`. This one reads the **command line**. A loop that exists only
inside a string an agent typed is invisible to every other guard in the repo, and
INC-0019 closed the file-borne half of this class while leaving this half open.

So this is a pre-flight check: run it before a command that builds or pipes, and
it refuses the specific unwritable-to-a-file shapes rather than trying to prove
anything about arbitrary Python.

## What it deliberately does not do

It is not a Python interpreter, and it does not claim to be. It catches the
`iter(callable, sentinel)` shape and the two adjacent ones that produce the same
runaway, both of which are decidable from the source text. A loop written any
other way is `test_no_unbounded_wait.gd`'s problem if it lives in a file, and
this tool's problem only when an agent is composing it inline — which the
loop-awareness rule in AGENTS.md covers.
"""

from __future__ import annotations

import re
import sys

from .common import fail, ok

#: `iter(<callable>, <sentinel>)` — the shape INC-0021 died on.
_ITER_SENTINEL = re.compile(r"iter\(\s*lambda\s*:[^,]+,\s*(?P<sentinel>[^)]+)\)")

#: A `readline()` whose result is transformed before it can equal a bytes sentinel.
#: The transform is what makes EOF unreachable: '' -> b'' -> never b'MARKER'.
_READLINE_TRANSFORM = re.compile(
    r"readline\(\)\s*\)?\s*\.\s*(strip|decode|encode|replace|split)\(",
)

#: The safe shape we point at instead. Reading until the empty line terminates by
#: construction because EOF *is* the empty line.
_SAFE_SHAPE_HINT = (
    "read until the empty line instead: `for line in sys.stdin:` then `if not "
    "line.strip(): break`. EOF yields '' which IS the terminator, so the loop "
    "cannot outrun its own input."
)

#: Each finding is (why-it-never-terminates, how-to-write-it-terminating).
_SHAPES: tuple[tuple[str, str, str], ...] = (
    (
        "iter(lambda: ..., <sentinel>) where the callable TRANSFORMS a readline() "
        "result. At EOF readline() returns '', and the transform yields b'' or '', "
        "which cannot equal a marker sentinel — so the stop condition is "
        "unreachable and the loop is infinite from its first call (INC-0021).",
        _SAFE_SHAPE_HINT,
        "iter-sentinel-unreachable",
    ),
    (
        "iter(<lambda>, <sentinel>) over a bytes sentinel where the callable can "
        "only ever produce a transformed value. iter() stops when its callable "
        "RETURNS the sentinel; a transforming callable never does.",
        _SAFE_SHAPE_HINT,
        "iter-sentinel-unreachable",
    ),
    (
        "a while-loop reading stdin with no length bound and no EOF test. "
        "sys.stdin at EOF is not an error and not distinct — readline() returns "
        "'' forever, so the condition never flips and nothing is ever written "
        "(INC-0019).",
        "Bound it: `for line in sys.stdin:` iterates to EOF and cannot overrun.",
        "unbounded-stdin-while",
    ),
)


def _findings(source: str) -> list[tuple[str, str, str]]:
    """Every non-terminating shape in `source`, as (why, fix, rule id)."""
    found: list[tuple[str, str, str]] = []
    seen: set[str] = set()

    for match in _ITER_SENTINEL.finditer(source):
        if not _READLINE_TRANSFORM.search(match.group(0)):
            continue
        # A sentinel that is itself an empty bytes literal terminates, because
        # ''.strip().encode() IS b''. Only a marker is unreachable.
        if re.fullmatch(r"\s*b?['\"]['\"]\s*", match.group("sentinel")):
            continue
        rule = _SHAPES[0]
        if rule[2] not in seen:
            found.append(rule)
            seen.add(rule[2])

    if re.search(r"while\s+True\s*:\s*(?:.|\n){0,400}?readline\(", source):
        rule = _SHAPES[2]
        if rule[2] not in seen:
            found.append(rule)
            seen.add(rule[2])

    return found


def check_command(argv: list[str]) -> list[tuple[str, str, str]]:
    """Findings for every inline Python script in an argv."""
    found: list[tuple[str, str, str]] = []
    for token in argv:
        if not token:
            continue
        found.extend(_findings(token))
    return found


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "loop_guard", help="refuse a command containing a non-terminating loop"
    )
    # NOT `--command`: the dispatcher reads `args.command` to pick the subcommand, so
    # that name is taken and would be overwritten by the subcommand's own value.
    parser.add_argument(
        "--argv",
        default=None,
        help="the command line to inspect, as a single string",
    )


def run(args) -> int:
    if args.argv is None:
        fail("loop_guard needs --argv '<the command to inspect>'")
        return 1
    findings = check_command([args.argv])
    if not findings:
        ok(f"no unbounded loop shape in the command ({len(args.argv)} chars inspected)")
        return 0
    fail(f"{len(findings)} non-terminating loop shape(s) in the command")
    for why, fix, rule in findings:
        print(f"  [{rule}]\n    why: {why}\n    fix: {fix}", file=sys.stderr)
    print(
        "  This is INC-0021: a loop that cannot terminate burns CPU and RAM while "
        "writing nothing, so no log-based ceiling can see it.",
        file=sys.stderr,
    )
    return 1
