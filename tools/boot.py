"""Boot the shipped main scene headlessly and require a clean exit.

The one check the rest of the gate cannot make. `tools test` drives scenes by
calling `_ready()` by hand and never runs a frame, so a fault that only fires
once the engine actually delivers frames is invisible to it: the shell killed
itself on frame 1 of a real boot while the entire suite was green (BL-0359).
The objective is that a player can launch the game and traverse the loop, so the
entry point itself has to be one the gate can fail.
"""

from __future__ import annotations

import re

from . import godot
from .common import GAME_DIR, ToolError, fail, game_exists, ok

# Enough frames for `_ready`, the first layout pass and a few `_process` ticks,
# and about two seconds of wall clock. One frame would not have caught BL-0359's
# neighbourhood of faults; this is deliberately not a soak test either.
BOOT_FRAMES = 30

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


def run(args) -> int:
    if not game_exists():
        raise ToolError("game/project.godot not found; create the Godot project first")
    scene = main_scene()
    result = godot.run_godot(
        [
            "--headless",
            "--path",
            str(GAME_DIR),
            "--quit-after",
            str(args.frames),
            scene,
        ],
        tag="boot",
    )
    if result.returncode != 0:
        # 3221225477 is 0xC0000005, an access violation: the engine died on its
        # own. It writes almost nothing to its log when it does, so name the
        # likely cause rather than leaving a bare exit code to interpret.
        hint = ""
        if result.returncode in (3221225477, -1073741819):
            hint = (
                " (access violation: the engine died mid-boot; read the run log under build/logs/)"
            )
        fail(
            f"the main scene did not boot: {scene} exited {result.returncode} "
            f"after {args.frames} frames{hint}"
        )
        return 1
    ok(f"main scene booted clean: {scene} ({args.frames} frames)")
    return 0
