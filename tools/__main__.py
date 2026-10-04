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
art_fidelity = _load("art_fidelity")
assets = _load("assets")
assets_sweep = _load("assets_sweep")
character_assets = _load("character_assets")
character_bundle_sync = _load("character_bundle_sync")
backlog = _load("backlog")
boot = _load("boot")
check = _load("check")
claim_guard = _load("claim_guard")
cultivation = _load("cultivation")
data = _load("data")
deferred = _load("deferred")
difficulty = _load("difficulty")
export = _load("export")
element_coverage = _load("element_coverage")
fmt = _load("fmt")
gate_reach = _load("gate_reach")
godot_bypass = _load("godot_bypass")
incident = _load("incident")
item_derive = _load("item_derive")
lint = _load("lint")
loop_guard = _load("loop_guard")
lore = _load("lore")
mutation_history = _load("mutation_history_cmd")
# Importing the cases module is what REGISTERS them with the harness, so the load is
# load-bearing rather than an unused name: ruff sees the import as unused and would strip
# it. Assigning it to a name keeps both the import and the lint honest.
selftest_cases = _load("selftest_cases")
selftest = _load("selftest")
map_theme = _load("map_theme")
new_adr = _load("new_adr")
new_module = _load("new_module")
realm_power = _load("realm_power")
run = _load("run")
technique_power = _load("technique_power")
test = _load("test")
ui = _load("ui")
unique_characters = _load("unique_characters")
worth_rewrite = _load("worth_rewrite")

from .common import ToolError, fail  # noqa: E402  (after the task modules load)

COMMANDS = {
    "element_coverage": element_coverage,
    "fmt": fmt,
    "gate_reach": gate_reach,
    "godot_bypass": godot_bypass,
    "lint": lint,
    "loop_guard": loop_guard,
    "lore": lore,
    "mutation_history": mutation_history,
    "selftest": selftest,
    "map_theme": map_theme,
    "arch": arch,
    "art_fidelity": art_fidelity,
    "assets": assets,
    "assets-sweep": assets_sweep,
    "character_assets": character_assets,
    "character_bundle_sync": character_bundle_sync,
    "unique_characters": unique_characters,
    "test": test,
    "boot": boot,
    "check": check,
    "claim_guard": claim_guard,
    "run": run,
    "export": export,
    "ui": ui,
    "new_module": new_module,
    "realm_power": realm_power,
    "technique_power": technique_power,
    "difficulty": difficulty,
    "new_adr": new_adr,
    "deferred": deferred,
    "incident": incident,
    "backlog": backlog,
    "cultivation": cultivation,
    "acquisition": acquisition,
    "item_derive": item_derive,
    "data": data,
    "worth_rewrite": worth_rewrite,
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
