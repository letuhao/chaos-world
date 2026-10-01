"""Run the full gate in order: fmt --check, lint, arch, test."""

from __future__ import annotations

import subprocess
import sys

from .common import REPO_ROOT, fail, info, ok

STEPS: tuple[tuple[str, list[str]], ...] = (
    ("fmt", ["--check"]),
    ("lint", []),
    ("arch", []),
    ("deferred", ["validate"]),
    ("data", ["audit"]),
    ("test", []),
)


def register(subparsers) -> None:
    parser = subparsers.add_parser("check", help="run fmt --check, lint, arch, test in order")
    parser.add_argument("--keep-going", action="store_true", help="run all steps after a failure")


def run(args) -> int:
    failed: list[str] = []
    for name, extra in STEPS:
        info(f"== {name} ==")
        result = subprocess.run(
            [sys.executable, "-m", "tools", name, *extra],
            cwd=str(REPO_ROOT),
        )
        if result.returncode != 0:
            failed.append(name)
            if not args.keep_going:
                break
    if failed:
        fail("gate failed: " + ", ".join(failed))
        return 1
    ok("all checks passed")
    return 0
