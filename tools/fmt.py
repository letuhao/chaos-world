"""Format GDScript and Python. `--check` verifies without writing."""

from __future__ import annotations

import shutil

from .common import GAME_DIR, info, warn
from .common import run as run_cmd


def register(subparsers) -> None:
    parser = subparsers.add_parser("fmt", help="format GDScript + Python")
    parser.add_argument("--check", action="store_true", help="verify formatting without writing")


def run(args) -> int:
    returncode = 0

    ruff = shutil.which("ruff")
    if ruff:
        cmd = [ruff, "format", "tools"]
        if args.check:
            cmd.append("--check")
        returncode |= run_cmd(cmd, check=False).returncode
    else:
        warn("ruff not found; run `uv sync` to install it")

    gdformat = shutil.which("gdformat")
    if not GAME_DIR.is_dir():
        info("game/ not found; skipping GDScript format")
    elif gdformat:
        cmd = [gdformat, str(GAME_DIR)]
        if args.check:
            cmd.append("--check")
        returncode |= run_cmd(cmd, check=False).returncode
    else:
        warn("gdformat not found; run `uv sync` to install it")

    return returncode
