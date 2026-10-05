"""Launch the game (or editor)."""

from __future__ import annotations

from . import godot
from .common import GAME_DIR, ToolError, game_exists


def register(subparsers) -> None:
    parser = subparsers.add_parser("run", help="launch the game")
    parser.add_argument("--editor", action="store_true", help="open the Godot editor instead")
    parser.add_argument("--headless", action="store_true", help="no window; boot smoke check")
    parser.add_argument(
        "--quit-after",
        type=int,
        default=0,
        help="exit after N frames (headless smoke check); 0 runs until closed",
    )


def run(args) -> int:
    if not game_exists():
        raise ToolError("game/project.godot not found; create the Godot project first")
    cmd = []
    if args.headless:
        cmd.append("--headless")
    cmd += ["--path", str(GAME_DIR)]
    if args.editor:
        cmd.append("--editor")
    if args.quit_after > 0:
        cmd += ["--quit-after", str(args.quit_after)]
    return godot.run_godot(cmd).returncode
