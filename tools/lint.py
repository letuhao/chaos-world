"""Lint GDScript and Python."""

from __future__ import annotations

import shutil

from .common import GAME_DIR, info, warn
from .common import run as run_cmd


def register(subparsers) -> None:
    subparsers.add_parser("lint", help="lint GDScript + Python")


def run(args) -> int:
    returncode = 0

    ruff = shutil.which("ruff")
    if ruff:
        returncode |= run_cmd([ruff, "check", "tools"], check=False).returncode
    else:
        warn("ruff not found; run `uv sync` to install it")

    gdlint = shutil.which("gdlint")
    if not GAME_DIR.is_dir():
        info("game/ not found; skipping GDScript lint")
    elif gdlint:
        returncode |= run_cmd([gdlint, str(GAME_DIR)], check=False).returncode
    else:
        warn("gdlint not found; run `uv sync` to install it")

    return returncode
