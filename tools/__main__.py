"""Command dispatcher: `uv run python -m tools <task> [options]`."""

from __future__ import annotations

import argparse
import importlib
import sys


def _load(name: str):
    """Import one task module, naming the file if it will not parse.

    Every task is imported eagerly, so a single syntax error in any module used to
    take the WHOLE CLI down — including `tools test` — with a bare traceback that
    reads like a broken checkout. In a shared tree where several agents write
    files at once, that is almost always a half-written file rather than a real
    regression, and the useful thing to say is which file and that.
    """
    try:
        return importlib.import_module(f".{name}", __package__)
    except (SyntaxError, ImportError) as exc:
        where = getattr(exc, "filename", None) or f"tools/{name}.py"
        print(
            f"error: {where} does not load ({exc}).\n"
            "       If another agent is writing that file right now, wait and "
            "retry; every tools command is unavailable until it loads.",
            file=sys.stderr,
        )
        raise SystemExit(2) from None


acquisition = _load("acquisition")
arch = _load("arch")
assets = _load("assets")
backlog = _load("backlog")
boot = _load("boot")
check = _load("check")
cultivation = _load("cultivation")
data = _load("data")
deferred = _load("deferred")
export = _load("export")
fmt = _load("fmt")
incident = _load("incident")
item_derive = _load("item_derive")
lint = _load("lint")
new_adr = _load("new_adr")
new_module = _load("new_module")
realm_power = _load("realm_power")
run = _load("run")
technique_power = _load("technique_power")
test = _load("test")
ui = _load("ui")

from .common import ToolError, fail  # noqa: E402  (after the task modules load)

COMMANDS = {
    "fmt": fmt,
    "lint": lint,
    "arch": arch,
    "assets": assets,
    "test": test,
    "boot": boot,
    "check": check,
    "run": run,
    "export": export,
    "ui": ui,
    "new_module": new_module,
    "realm_power": realm_power,
    "technique_power": technique_power,
    "new_adr": new_adr,
    "deferred": deferred,
    "incident": incident,
    "backlog": backlog,
    "cultivation": cultivation,
    "acquisition": acquisition,
    "item_derive": item_derive,
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
