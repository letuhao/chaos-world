"""Launch the game (or editor)."""

from __future__ import annotations

from . import godot
from .common import GAME_DIR, ToolError, game_exists


def register(subparsers) -> None:
    parser = subparsers.add_parser("run", help="launch the game")
    parser.add_argument("--editor", action="store_true", help="open the Godot editor instead")


def run(args) -> int:
    if not game_exists():
        raise ToolError("game/project.godot not found; create the Godot project first")
    cmd = ["--path", str(GAME_DIR)]
    if args.editor:
        cmd.append("--editor")
    return godot.run_godot(cmd).returncode
