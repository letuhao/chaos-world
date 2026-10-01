"""Shared paths, output helpers, and process execution for the tool bundle."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
GAME_DIR = REPO_ROOT / "game"
SRC_DIR = GAME_DIR / "src"
MODULES_DIR = SRC_DIR / "modules"
TESTS_DIR = GAME_DIR / "tests"
DOCS_DIR = REPO_ROOT / "docs"
ADR_DIR = DOCS_DIR / "adr"
ARCH_DIR = Path(__file__).resolve().parent / "arch"
REGISTRY_PATH = ARCH_DIR / "registry.json"


class ToolError(RuntimeError):
    """An expected, user-facing failure."""


def info(message: str) -> None:
    print(message)


def ok(message: str) -> None:
    print(f"ok   {message}")


def warn(message: str) -> None:
    print(f"warn {message}", file=sys.stderr)


def fail(message: str) -> None:
    print(f"fail {message}", file=sys.stderr)


def run(cmd, *, cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess:
    """Run a subprocess, echoing the command. Raises ToolError on non-zero when checked."""
    printable = " ".join(str(part) for part in cmd)
    info(f"$ {printable}")
    result = subprocess.run(
        [str(part) for part in cmd],
        cwd=str(cwd) if cwd else None,
        text=True,
    )
    if check and result.returncode != 0:
        raise ToolError(f"command failed ({result.returncode}): {printable}")
    return result


def game_exists() -> bool:
    return (GAME_DIR / "project.godot").is_file()
