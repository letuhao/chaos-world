"""Run the Godot test suite headless, optionally filtered to matching suites."""

from __future__ import annotations

import sys

from . import godot
from .common import GAME_DIR, ToolError, fail, game_exists, warn

RUNNER_REL = "res://tests/run_tests.gd"

# A GDScript runtime error aborts the function it happens in and returns to the
# caller. The runner calls each test with `suite.call(name)`, so an abort looks
# exactly like a test that finished - and the suite still reports its remaining
# assertions, so it reports green while silently skipping everything after the
# abort. That is not theoretical: removing four dead seed fields dropped 711
# assertions across body_cultivation and nothing reported a failure.
#
# The two are distinguishable on stderr. A failed assertion goes through
# `push_error` and prints `ERROR: res://...`; an aborted test prints
# `SCRIPT ERROR:`. Godot exposes no GDScript hook for `push_error`, so this is
# enforced here, where stderr is already captured.
SCRIPT_ERROR_PREFIXES = ("SCRIPT ERROR:", "USER SCRIPT ERROR:")


def _error_lines(output: str) -> list[str]:
    return [
        line.strip()
        for line in output.splitlines()
        if line.lstrip().startswith(SCRIPT_ERROR_PREFIXES)
    ]


def register(subparsers) -> None:
    parser = subparsers.add_parser("test", help="run the Godot test suite headless")
    parser.add_argument(
        "--suite",
        default="",
        metavar="SUBSTRING",
        help="only run suites whose res:// path contains this; repeatable is not needed",
    )
    parser.add_argument(
        "--skip-import",
        action="store_true",
        help="skip the --import pass (only safe when .godot/ is already populated)",
    )


def run(args) -> int:
    if not game_exists():
        raise ToolError("game/project.godot not found; cannot run tests")
    runner = GAME_DIR / "tests" / "run_tests.gd"
    if not runner.is_file():
        raise ToolError(f"no test runner at {runner}")
    godot.find_godot()
    if not args.skip_import:
        # Populate .godot/ on a fresh checkout so class_name types resolve.
        import_result = godot.run_godot(["--headless", "--path", str(GAME_DIR), "--import"])
        if import_result.returncode != 0:
            raise ToolError(f"Godot import failed with exit code {import_result.returncode}")
    cmd = ["--headless", "--path", str(GAME_DIR), "-s", RUNNER_REL]
    if args.suite:
        cmd += ["--", "--suite", args.suite]
    result = godot.run_godot(cmd, capture=True)
    output = result.stdout or ""
    errors = result.stderr or ""
    # Re-emit so a captured run still reads like a streamed one.
    print(output, end="")
    if errors:
        print(errors, end="", file=sys.stderr)
    aborted = _error_lines(output + "\n" + errors)
    if aborted:
        fail(
            f"{len(aborted)} script error(s) aborted a test mid-function; those tests "
            "reported no failure, so the run above is incomplete"
        )
        for line in aborted[:10]:
            warn(line)
        if len(aborted) > 10:
            warn(f"... and {len(aborted) - 10} more")
        return 1
    return result.returncode
