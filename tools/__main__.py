"""Command dispatcher: `uv run python -m tools <task> [options]`."""

from __future__ import annotations

import argparse

from . import (
    arch,
    assets,
    backlog,
    check,
    data,
    deferred,
    export,
    fmt,
    lint,
    new_adr,
    new_module,
    run,
    test,
)
from .common import ToolError, fail

COMMANDS = {
    "fmt": fmt,
    "lint": lint,
    "arch": arch,
    "assets": assets,
    "test": test,
    "check": check,
    "run": run,
    "export": export,
    "new_module": new_module,
    "new_adr": new_adr,
    "deferred": deferred,
    "backlog": backlog,
    "data": data,
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="tools", description="Chaos World workflow tools.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for module in COMMANDS.values():
        module.register(subparsers)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return COMMANDS[args.command].run(args)
    except ToolError as exc:
        fail(str(exc))
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
