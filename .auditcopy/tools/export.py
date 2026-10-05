"""Export a build for a named Godot preset."""

from __future__ import annotations

from . import godot
from .common import GAME_DIR, ToolError, game_exists


def register(subparsers) -> None:
    parser = subparsers.add_parser("export", help="export a build")
    parser.add_argument("preset", help="export preset name from game/export_presets.cfg")


def run(args) -> int:
    if not game_exists():
        raise ToolError("game/project.godot not found; create the Godot project first")
    cmd = ["--headless", "--path", str(GAME_DIR), "--export-release", args.preset]
    return godot.run_godot(cmd).returncode
