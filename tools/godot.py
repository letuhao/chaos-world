"""Locate and invoke the Godot 4.7.x binary."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from .common import ToolError, info


def find_godot() -> str:
    """Return the Godot executable path from GODOT_BIN or PATH, or fail loudly."""
    env = os.environ.get("GODOT_BIN")
    if env:
        path = Path(env)
        if path.is_file():
            return str(path)
        raise ToolError(f"GODOT_BIN points to a missing file: {env}")
    found = shutil.which("godot") or shutil.which("godot4")
    if found:
        return found
    raise ToolError(
        "Godot binary not found. Set GODOT_BIN to the absolute path of a Godot 4.7.x executable."
    )


def run_godot(args: list[str]) -> subprocess.CompletedProcess:
    cmd = [find_godot(), *args]
    info("$ " + " ".join(cmd))
    return subprocess.run(cmd, text=True)
