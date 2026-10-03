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


def _survives(scene: str, frames: int) -> tuple[bool, str]:
    """Phase one: does the engine stay alive at all?

    The half that caught BL-0359, where the shell killed the process on its first
    frame. A scene can fail this and pass the other phase, and the other phase can
    fail while this one passes, which is why both exist.
    """
    result = godot.run_godot(
        ["--headless", "--path", str(GAME_DIR), "--quit-after", str(frames), scene],
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


def _comes_up() -> tuple[bool, str, dict]:
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
        ["--headless", "--path", str(GAME_DIR), "-s", PROBE],
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
    survived, why = _survives(scene, args.frames)
    if survived:
        ok(f"main scene survived {args.frames} frames: {scene}")
    else:
        fail(f"the main scene did not boot: {why}")
        failures.append("crash")
    came_up, why, report = _comes_up()
    if came_up:
        ok("the shell came up with a live route, a bound actor and a mounted screen")
        ok(f"a real nav button press moved the game: {_nav_line(report)}")
        ok(f"a real fight in the running app: {_hunt_line(report)}")
    else:
        fail(f"the main scene booted but is empty: {why}")
        failures.append("empty")
    if failures:
        fail("boot gate failed: " + ", ".join(failures))
        return 1
    return 0
