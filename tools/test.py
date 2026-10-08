"""Run the Godot test suite headless, optionally filtered to matching suites."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

from . import godot
from .common import GAME_DIR, ToolError, fail, game_exists, warn

RUNNER_REL = "res://tests/run_tests.gd"

# `user://` as Godot resolves it on Windows. The runner mirrors its running tally
# there after every suite, because a GDScript runtime error kills the runner mid-loop
# and the tally it prints at the end never appears -- one agent's in-flight file once
# left a 260-suite run with no pass/fail count at all, which reads exactly like a run
# that measured nothing. Read as a fallback, and always labelled incomplete.
_TALLY_RELPATH = Path("Godot") / "app_userdata" / "Chaos World" / "test-tally.txt"
_RESULTS_RE = re.compile(r"^Results: ", re.MULTILINE)


def _tally_path() -> Path | None:
    appdata = os.environ.get("APPDATA")
    if not appdata:
        return None
    return Path(appdata) / _TALLY_RELPATH


def _read_tally() -> str | None:
    """The last partial tally the runner mirrored, or None if there is none."""
    path = _tally_path()
    if path is None or not path.is_file():
        return None
    try:
        text = path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None
    return text or None


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

# A script that fails to load makes every dependant report "Could not resolve
# class" or "not found in base", so ONE half-written file can print a thousand
# errors whose real cause is one line in one file. Measured: a full run during a
# concurrent edit printed 1070 script errors, all cascading from
# res://src/modules/items/api.gd failing to parse. Counting them and showing the
# first ten is not diagnosis, so the files that failed to LOAD are named first.
LOAD_FAILURE_MARKERS = (
    "Parse Error:",
    "Could not resolve",
    "Compile Error:",
    "at: GDScript::reload",
)

_RES_PATH = re.compile(r"res://[^\s\"':()]+\.gd")


def _load_failure_files(output: str) -> list[str]:
    """Distinct scripts that failed to load, in first-seen order."""
    files: list[str] = []
    for line in output.splitlines():
        if not any(marker in line for marker in LOAD_FAILURE_MARKERS):
            continue
        # `res://` itself contains colons, so match the path as a whole and let
        # the trailing `:LINE` fall outside the pattern. Splitting on ":" would
        # yield "res", and a plain suffix test would drop every `:112` location.
        for path in _RES_PATH.findall(line):
            if path not in files:
                files.append(path)
    return files


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
    parser.add_argument(
        "--out",
        default="",
        metavar="PATH",
        help=(
            "write the run's whole stdout and stderr to PATH. A suite's own `print()`s "
            "reach the terminal the run happened on and nothing else - the launcher's "
            "`-run.out` holds Godot's own log, not the stdout this tool captured - so a "
            "measurement that only prints is unverifiable from any file."
        ),
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
    if args.out:
        # Written BEFORE any failure return: a red run is the one whose output somebody
        # needs, and an artifact written only on success keeps the evidence out of every
        # investigation that mattered.
        target = Path(args.out)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            "exit=%s\n--- STDOUT ---\n%s\n--- STDERR ---\n%s\n"
            % (result.returncode, output, errors),
            encoding="utf-8",
        )
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
        # The runner died before its closing tally, so stdout has no `Results:` line.
        # Its mirrored tally is the only measurement this run produced: report it as
        # the partial count it is, never as a result.
        if not _RESULTS_RE.search(output):
            tally = _read_tally()
            if tally:
                warn(f"  run aborted before printing a total; partial tally: {tally}")
            else:
                warn("  run aborted before printing a total, and no partial tally survived")
        # Name the root cause before the noise: almost every one of these is a
        # dependant of a script that did not load.
        roots = _load_failure_files(output + "\n" + errors)
        if roots:
            warn(
                f"{len(roots)} script(s) failed to LOAD; the errors above are "
                "mostly their dependants:"
            )
            for path in roots[:10]:
                warn(f"  {path}")
            if len(roots) > 10:
                warn(f"  ... and {len(roots) - 10} more")
        for line in aborted[:10]:
            warn(line)
        if len(aborted) > 10:
            warn(f"... and {len(aborted) - 10} more")
        return 1
    return result.returncode
