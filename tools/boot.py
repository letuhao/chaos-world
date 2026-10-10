"""Boot the shipped main scene headlessly and require a clean exit.

The one check the rest of the gate cannot make. `tools test` drives scenes by
calling `_ready()` by hand and never runs a frame, so a fault that only fires
once the engine actually delivers frames is invisible to it: the shell killed
itself on frame 1 of a real boot while the entire suite was green (BL-0359).
The objective is that a player can launch the game and traverse the loop, so the
entry point itself has to be one the gate can fail.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from . import godot
from .common import GAME_DIR, ToolError, fail, game_exists, ok

# Enough frames for `_ready`, the first layout pass and a few `_process` ticks,
# and about two seconds of wall clock. One frame would not have caught BL-0359's
# neighbourhood of faults; this is deliberately not a soak test either.
BOOT_FRAMES = 30

# Mounts the real main scene and reports what it built. Lives in `game/tools/`
# because it has to run inside the engine, which means `res://`.
PROBE = "res://tools/boot_probe.gd"
REPORT_PREFIX = "BOOTJSON "

_MAIN_SCENE = re.compile(r'^\s*run/main_scene\s*=\s*"([^"]+)"', re.MULTILINE)


def main_scene() -> str:
    """The scene `project.godot` actually launches, read from the file.

    Hardcoding it here would let the check drift onto a different scene than the
    one a player gets, which is the exact failure the check exists to prevent.
    """
    text = (GAME_DIR / "project.godot").read_text(encoding="utf-8")
    match = _MAIN_SCENE.search(text)
    if match is None:
        raise ToolError("game/project.godot declares no run/main_scene; nothing to boot")
    return match.group(1)


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "boot", help="boot the main scene headlessly; non-zero if it does not come up"
    )
    parser.add_argument(
        "--frames",
        type=int,
        default=BOOT_FRAMES,
        help=f"frames to run before exiting (default {BOOT_FRAMES})",
    )
    parser.add_argument(
        "--out",
        default="",
        metavar="PATH",
        help=(
            "write the probe's own report to PATH as JSON. The human summary this tool "
            "prints and the probe's `BOOTJSON` line BOTH fail to reach an artifact: the "
            "launcher's `-run.out` holds Godot's own log, not the stdout the tool "
            "captured. A run was therefore verifiable only from the terminal it happened "
            "to be printed to, which is how a stale verdict survived in this gate."
        ),
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help=(
            "hand the engine `--verbose`, which is what names the classes in the "
            "exit-leak report (`N ObjectDB instances were leaked at exit`). Without it "
            "the count is unattributable, and BL-0724 could only record a hypothesis; "
            "with it the warning either names autoload-owned singletons (not a defect) "
            "or a Control from `game/src` (a real leak)."
        ),
    )


def _survives(scene: str, frames: int, verbose: bool) -> tuple[bool, str]:
    """Phase one: does the engine stay alive at all?

    The half that caught BL-0359, where the shell killed the process on its first
    frame. A scene can fail this and pass the other phase, and the other phase can
    fail while this one passes, which is why both exist.

    The scene is NOT passed as a positional argument. Godot already launches
    `run/main_scene` from project.godot when none is given, and naming it on the
    command line took a different path through the engine: that form died with an
    access violation and a two-line log while `tools run` booted the same scene
    cleanly for sixty frames. A gate that reports a crash the player would never
    see is worse than no gate, because it sends whoever reads it hunting a fault
    in the game instead of in the gate.
    """
    result = godot.run_godot(
        ["--headless", "--path", str(GAME_DIR), "--quit-after", str(frames)]
        + (["--verbose"] if verbose else []),
        tag="boot",
    )
    if result.returncode == 0:
        return True, ""
    # 3221225477 is 0xC0000005 on Windows: the engine died on its own. It writes
    # almost nothing to its log when it does, so say so rather than leaving a bare
    # exit code to interpret.
    hint = ""
    if result.returncode in (3221225477, -1073741819):
        hint = " (access violation: the engine died mid-boot; read the run log under build/logs/)"
    return False, f"{scene} exited {result.returncode} after {frames} frames{hint}"


def _comes_up(verbose: bool) -> tuple[bool, str, dict]:
    """Phase two: does the shell come up with something on it, and can it be moved?

    Surviving is not arriving. `ItemWorkbenchApp._ready` returns quietly when it
    cannot find `%ScreenStack` or the root route will not load, and every one of
    those still exits 0 with a blank window. Coming up is not navigable either: a
    bar whose buttons render and do nothing is the same blank window from a
    player's seat. So the probe mounts the real scene, asks it to describe itself,
    then presses a real nav button and checks it landed on the route that slot
    advertises.

    Returns the report as well as the verdict, so the pass message can name where
    the press went. A gate that only says "ok" makes it impossible to tell a working
    press from a check that quietly stopped looking.
    """
    result = godot.run_godot(
        ["--headless", "--path", str(GAME_DIR), "-s", PROBE] + (["--verbose"] if verbose else []),
        capture=True,
        tag="bootprobe",
    )
    report = _parse_report(result.stdout) or {}
    if not report:
        return (
            False,
            f"{PROBE} printed no BOOTJSON line (exit {result.returncode});"
            " the probe never finished",
            {},
        )
    if not report.get("ok", False):
        return (
            False,
            str(report.get("why", "the shell came up empty-handed for an unnamed reason")),
            report,
        )
    return True, "", report


def _nav_line(report: dict) -> str:
    """One line naming where the probe's button press took the game.

    Printed on success because it is the evidence, not just the verdict: a gate that
    only says "ok" makes it impossible to tell a working press from a check that
    quietly stopped looking.
    """
    nav = report.get("nav", {})
    if not isinstance(nav, dict) or not nav.get("ok", False):
        return ""
    return f"{nav.get('from', '?')} -> {nav.get('to', '?')}"


def _hunt_line(report: dict) -> str:
    """One line naming what the probe's fight actually minted.

    The primary loop is not "the screen opened" but "damage landed, the pool emptied
    and a reward came out". Printing the counts makes that checkable by eye, and a
    reward of zero becomes visible rather than something inferred from an "ok".
    """
    hunt = report.get("hunt", {})
    if not isinstance(hunt, dict) or not hunt.get("ok", False):
        return ""
    return (
        f"{hunt.get('strikes', '?')} strikes killed the boss;"
        f" {hunt.get('reward_count', '?')} rewards minted,"
        f" {hunt.get('pending_drops', '?')} drops pending"
    )


def _claim_line(report: dict) -> str:
    """One line naming what the collected drop did to the bag.

    Minting a reward is not the loop finishing. A reward the player cannot collect is
    a number on a screen, so this reports the bag before and after the pickup press:
    the drop has to become an item the workbench lists, or the fight fed nothing.
    """
    claim = report.get("claim", {})
    if not isinstance(claim, dict) or not claim.get("ok", False):
        return ""
    return (
        f"pending {claim.get('pending_before', '?')} -> {claim.get('pending_after', '?')}"
        f"; the bag grew {claim.get('rows_at_boot', '?')} -> {claim.get('rows_now', '?')} rows"
    )


def _parse_report(stdout: str | None) -> dict | None:
    for line in (stdout or "").splitlines():
        marker = line.find(REPORT_PREFIX)
        if marker >= 0:
            try:
                parsed = json.loads(line[marker + len(REPORT_PREFIX) :])
            except json.JSONDecodeError:
                return None
            return parsed if isinstance(parsed, dict) else None
    return None


def run(args) -> int:
    if not game_exists():
        raise ToolError("game/project.godot not found; create the Godot project first")
    scene = main_scene()
    failures: list[str] = []
    survived, why = _survives(scene, args.frames, args.verbose)
    if survived:
        ok(f"main scene survived {args.frames} frames: {scene}")
    else:
        fail(f"the main scene did not boot: {why}")
        failures.append("crash")
    came_up, why, report = _comes_up(args.verbose)
    if came_up:
        ok("the shell came up with a live route, a bound actor and a mounted screen")
        ok(f"a real nav button press moved the game: {_nav_line(report)}")
        ok(f"a real fight in the running app: {_hunt_line(report)}")
        ok(f"the drop was collected through the reward list: {_claim_line(report)}")
    else:
        fail(f"the main scene booted but is empty: {why}")
        failures.append("empty")
    artifact = {
        "ok": not failures,
        "scene": scene,
        "frames": args.frames,
        "survived": survived,
        "came_up": came_up,
        "why": why,
        "failures": failures,
        "report": report,
    }
    if args.out:
        _write_report(args.out, artifact)
    if failures:
        fail("boot gate failed: " + ", ".join(failures))
        return 1
    return 0


def _write_report(path: str, artifact: dict) -> None:
    """Persist the verdict and the probe's own report, so a run outlives its terminal.

    The write happens BEFORE the failure return, deliberately: a red run is the one
    whose numbers somebody needs, and an artifact written only on success would keep
    the probe's evidence out of every investigation that mattered.
    """
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(artifact, indent=2, sort_keys=True), encoding="utf-8")
    ok(f"wrote the boot report to {target}")
