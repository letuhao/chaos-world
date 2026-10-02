"""Locate and invoke the Godot 4.7.x binary."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from .common import REPO_ROOT, ToolError, info

CONFIG_FILE = REPO_ROOT / ".godot-bin"


def find_godot() -> str:
    """Resolve Godot from GODOT_BIN, the local .godot-bin file, or PATH; fail loudly."""
    env = os.environ.get("GODOT_BIN")
    if env:
        path = Path(env)
        if path.is_file():
            return str(path)
        raise ToolError(f"GODOT_BIN points to a missing file: {env}")
    if CONFIG_FILE.is_file():
        configured = CONFIG_FILE.read_text(encoding="utf-8").strip()
        if configured:
            path = Path(configured)
            if path.is_file():
                return str(path)
            raise ToolError(f".godot-bin points to a missing file: {configured}")
    found = shutil.which("godot") or shutil.which("godot4")
    if found:
        return found
    raise ToolError(
        "Godot binary not found. Set GODOT_BIN or write its path to .godot-bin "
        "(a Godot 4.7.x executable)."
    )


def run_godot(args: list[str], capture: bool = False) -> subprocess.CompletedProcess:
    """Invoke Godot. With `capture`, stdout is returned instead of streamed."""
    cmd = [find_godot(), *args]
    info("$ " + " ".join(cmd))
    return subprocess.run(cmd, text=True, capture_output=capture)
