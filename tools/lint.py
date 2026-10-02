"""Lint GDScript and Python."""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

from .common import GAME_DIR, info, warn
from .common import run as run_cmd

# The headless runner discovers tests by name (`get_method_list()` filtered on
# `test_`), so every test case is necessarily a public method. A suite with more
# than 20 cases would trip gdlint's max-public-methods rule for doing exactly
# what the framework requires. The rule is enforced on `game/src/` and lifted
# for `game/tests/`.
SRC_DIR = GAME_DIR / "src"
TESTS_DIR = GAME_DIR / "tests"
RELAXED_TEST_RULES = {"max-public-methods": 1000}


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
        if SRC_DIR.is_dir():
            returncode |= run_cmd([gdlint, str(SRC_DIR)], check=False).returncode
        if TESTS_DIR.is_dir():
            returncode |= _lint_tests(gdlint)
    else:
        warn("gdlint not found; run `uv sync` to install it")

    return returncode


def _lint_tests(gdlint: str) -> int:
    """Lint the test tree with max-public-methods lifted.

    gdlint reads its rule set from `gdlintrc` in the current directory, so this
    runs from a temporary directory rather than writing config into the repo.
    """
    with tempfile.TemporaryDirectory() as tmp:
        config = Path(tmp) / "gdlintrc"
        if not _write_relaxed_config(gdlint, tmp, config):
            warn("could not build a relaxed gdlint config; test lint skipped")
            return 0
        return subprocess.run(  # noqa: S603
            [gdlint, str(TESTS_DIR)], cwd=tmp, text=True, check=False
        ).returncode


def _write_relaxed_config(gdlint: str, workdir: str, config: Path) -> bool:
    """Dump gdlint's defaults into `workdir`, then relax the test-only rules."""
    defaults = subprocess.run(  # noqa: S603
        [gdlint, "-d"], cwd=workdir, text=True, capture_output=True, check=False
    )
    dumped = Path(workdir) / "gdlintrc"
    if defaults.returncode != 0 or not dumped.is_file():
        return False
    lines = []
    for line in dumped.read_text(encoding="utf-8").splitlines():
        key = line.split(":", 1)[0].strip()
        lines.append(f"{key}: {RELAXED_TEST_RULES[key]}" if key in RELAXED_TEST_RULES else line)
    config.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return True
