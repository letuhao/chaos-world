"""Drive a UI screen headlessly and report its state as JSON (ADR 0039).

The screen's own `summary()` is the report, so an LLM reads exactly what the
player sees. Every action goes through the screen's public `act_*` methods, which
call module facades, so the CLI cannot reach state a player could not.
"""

from __future__ import annotations

import json
from typing import Any

from . import godot
from .common import GAME_DIR, ToolError, info, ok

DRIVER = "res://tools/ui_driver.gd"
PREFIX = "UIJSON "


def register(subparsers) -> None:
    parser = subparsers.add_parser("ui", help="drive a UI screen headlessly")
    sub = parser.add_subparsers(dest="ui_command", required=True)

    drive = sub.add_parser("drive", help="run a screen through a list of commands")
    drive.add_argument("--screen", required=True, help="res:// path to the screen scene")
    drive.add_argument(
        "--path",
        dest="actor_path",
        default="",
        choices=["", "body", "qi", "mind"],
        help="cultivation path to enrol the actor on",
    )
    drive.add_argument(
        "--fresh",
        action="store_true",
        help="discard any saved session and start from a clean actor",
    )
    drive.add_argument(
        "--technique",
        default="",
        metavar="ID",
        help=(
            "fire a shipped TechniqueDef .tres by id instead of the "
            "driver's synthetic drill swing, so a drive can measure "
            "AUTHORED content (aim_meridian, element, mind_kind)"
        ),
    )
    drive.add_argument(
        "--cmd",
        action="append",
        default=[],
        metavar="VERB",
        help=(
            "a summary/refresh/focus_initial, an act_<verb>, or one of "
            "call:<method>[=arg], grant:<item_id>, realm:<rank_id>; "
            "repeatable, runs in order"
        ),
    )

    sub.add_parser("screens", help="list the screens the UI program ships")


def run(args) -> int:
    if args.ui_command == "screens":
        return _screens()
    return _drive(args)


def _screens() -> int:
    """Every screen scene in the UI program, so a caller can discover what exists."""
    screens = sorted((GAME_DIR / "src" / "ui" / "screens").glob("*.tscn"))
    for scene in screens:
        info(f"res://src/ui/screens/{scene.name}")
    ok(f"{len(screens)} screen(s)")
    return 0


def _drive(args) -> int:
    screen = args.screen
    if not screen.startswith("res://"):
        screen = f"res://{screen.lstrip('/')}"
    local = GAME_DIR / screen[len("res://") :]
    if not local.is_file():
        raise ToolError(f"screen scene not found: {screen}")

    cmd = [
        "--headless",
        "--path",
        str(GAME_DIR),
        "-s",
        DRIVER,
        "--",
        "--screen",
        screen,
    ]
    if args.actor_path:
        cmd += ["--path", args.actor_path]
    if args.technique:
        cmd += ["--technique", args.technique]
    if args.fresh:
        cmd.append("--fresh")
    for verb in args.cmd:
        cmd += ["--cmd", verb]

    result = godot.run_godot(cmd, capture=True)
    events = _events(result.stdout or "")
    if not events:
        # No JSON means the driver never reached its first emit: a load error or a
        # parse failure. Surface the engine output rather than an empty report.
        for line in (result.stdout or "").splitlines():
            info(line)
        for line in (result.stderr or "").splitlines():
            info(line)
        raise ToolError("driver produced no output; see the engine log above")
    for event in events:
        print(json.dumps(event))
    ok(f"{len(events)} event(s) from {screen}")
    return result.returncode


def _events(stdout: str) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for line in stdout.splitlines():
        if not line.startswith(PREFIX):
            continue
        try:
            events.append(json.loads(line[len(PREFIX) :]))
        except json.JSONDecodeError:
            continue
    return events
