"""Run the Godot test suite headless."""

from __future__ import annotations

from . import godot
from .common import GAME_DIR, ToolError, game_exists

RUNNER_REL = "res://tests/run_tests.gd"


def register(subparsers) -> None:
    subparsers.add_parser("test", help="run the Godot test suite headless")


def run(args) -> int:
    if not game_exists():
        raise ToolError("game/project.godot not found; cannot run tests")
    runner = GAME_DIR / "tests" / "run_tests.gd"
    if not runner.is_file():
        raise ToolError(f"no test runner at {runner}")
    godot.find_godot()
    # Populate .godot/ on a fresh checkout so class_name types resolve.
    import_result = godot.run_godot(["--headless", "--path", str(GAME_DIR), "--import"])
    if import_result.returncode != 0:
        raise ToolError(f"Godot import failed with exit code {import_result.returncode}")
    result = godot.run_godot(["--headless", "--path", str(GAME_DIR), "-s", RUNNER_REL])
    return result.returncode
