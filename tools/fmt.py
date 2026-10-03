"""Format GDScript and Python. `--check` verifies without writing.

Pass paths to limit formatting to what you own. The default is the whole repo,
which is right for `tools check` and wrong for an agent working in a shared tree:
three separate agents reported reformatting files they did not own, twice losing
work outright because the churn landed on another agent's in-flight file.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from .common import GAME_DIR, REPO_ROOT, info, warn
from .common import run as run_cmd


def register(subparsers) -> None:
    parser = subparsers.add_parser("fmt", help="format GDScript + Python")
    parser.add_argument("--check", action="store_true", help="verify formatting without writing")
    parser.add_argument(
        "paths",
        nargs="*",
        help="only format these files or directories (default: tools/ and game/)",
    )


def run(args) -> int:
    returncode = 0
    given = [p for p in (args.paths or []) if Path(p).exists()]
    if args.paths and not given:
        # Falling back to the whole repo here would reintroduce exactly the
        # collateral damage this argument exists to prevent, so a bad path is an
        # error rather than a licence to reformat every file in the tree.
        for path in args.paths:
            warn(f"no such path: {path}")
        return 1

    # A formatter handed a directory walks it, so keep directories for both and
    # only hand each tool the extension it understands.
    py_targets = [p for p in given if p.endswith(".py")]
    gd_targets = [p for p in given if p.endswith(".gd") or Path(p).is_dir()]

    ruff = shutil.which("ruff")
    if not ruff:
        warn("ruff not found; run `uv sync` to install it")
    elif given and not py_targets:
        info("no Python files among the given paths; skipping ruff")
    else:
        cmd = [ruff, "format", *(py_targets or [str(REPO_ROOT / "tools")])]
        if args.check:
            cmd.append("--check")
        returncode |= run_cmd(cmd, check=False).returncode

    gdformat = shutil.which("gdformat")
    if not GAME_DIR.is_dir():
        info("game/ not found; skipping GDScript format")
    elif not gdformat:
        warn("gdformat not found; run `uv sync` to install it")
    elif given and not gd_targets:
        info("no GDScript files among the given paths; skipping gdformat")
    else:
        cmd = [gdformat, *(gd_targets or [str(GAME_DIR)])]
        if args.check:
            cmd.append("--check")
        returncode |= run_cmd(cmd, check=False).returncode

    return returncode
