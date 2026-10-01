"""Run the Godot test suite headless."""

from __future__ import annotations

from . import godot
from .common import GAME_DIR, ToolError, game_exists, warn

RUNNER_REL = "res://tests/run_tests.gd"


def register(subparsers) -> None:
    subparsers.add_parser("test", help="run the Godot test suite headless")


def run(args) -> int:
    if not game_exists():
        warn("game/project.godot not found; skipping tests")
        return 0
    runner = GAME_DIR / "tests" / "run_tests.gd"
    if not runner.is_file():
        raise ToolError(f"no test runner at {runner}")
    try:
        godot.find_godot()
    except ToolError as exc:
        warn(f"{exc} Skipping tests.")
        return 0
    # Populate .godot/ on a fresh checkout so class_name types resolve.
    godot.run_godot(["--headless", "--path", str(GAME_DIR), "--import"])
    result = godot.run_godot(["--headless", "--path", str(GAME_DIR), "-s", RUNNER_REL])
    return result.returncode
