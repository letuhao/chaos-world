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
# The ADR citation checker: an ADR is a CLAIM, not evidence, so nothing else in the
# tree executes the file:line one makes. Registered here and reached from `check`
# like any other gate; imported under a name so ruff reads the import as used.
adr_cite = _load("adr_cite")
adr_cite_selftest = _load("adr_cite_selftest")
arch = _load("arch")
# The facade-constant guard lives inside the arch package but registers its own
# subcommand, because it is a gate in its own right: `tools check` reaches it
# through `arch`, and a human can ask the question alone.
facade_constants = _load("arch.facade_constants")
# A Python guard is unreachable from the GDScript suite, so nothing asserts it
# still goes RED unless its cases are loaded. `selftest_cases` is the cases
# module that wires `tools selftest run`, and a guard with no red path is a
# guard that was never tested (INC-0016). Assigned to a name so ruff reads the
# import as used rather than stripping it.
facade_constants_selftest = _load("arch.facade_constants_selftest")
# The VERB census (ADR 0188). Same reason and the same shape as the constant guard
# above, and it is a separate gate in its own right: `tools check` reaches it
# through `arch`, and a human can ask the question alone.
no_caller_verbs = _load("arch.no_caller_verbs")
no_caller_verbs_selftest = _load("arch.no_caller_verbs_selftest")
# Same reason, and the same reason `race_from_lore` keeps its cases in their own module rather than
# in `selftest_cases.py`: that file is shared and busy, so an append there cannot be committed
# without sweeping another session's in-flight cases (INC-0041), and an uncommittable red path is
# not a red path.
png_provenance = _load("png_provenance")
png_provenance_selftest = _load("png_provenance_selftest")
race_from_lore = _load("race_from_lore")
race_from_lore_selftest = _load("race_from_lore_selftest")
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
domain = _load("domain")
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
portrait_fallback = _load("portrait_fallback")
realm_power = _load("realm_power")
run = _load("run")
technique_power = _load("technique_power")
test = _load("test")
ui = _load("ui")
unique_characters = _load("unique_characters")
worth_rewrite = _load("worth_rewrite")

from .common import ToolError, fail  # noqa: E402  (after the task modules load)

COMMANDS = {
    "adr-cite": adr_cite,
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
    "facade_constants": facade_constants,
    "no_caller_verbs": no_caller_verbs,
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
    "png_provenance": png_provenance,
    "portrait_fallback": portrait_fallback,
    "race_from_lore": race_from_lore,
    "realm_power": realm_power,
    "technique_power": technique_power,
    "difficulty": difficulty,
    "new_adr": new_adr,
    "deferred": deferred,
    "domain": domain,
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
