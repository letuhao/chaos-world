"""Scaffold a feature module and register its boundary dependencies."""

from __future__ import annotations

import re

from .arch import rules
from .common import MODULES_DIR, REPO_ROOT, TESTS_DIR, ToolError, info, ok

NAME_RE = re.compile(r"^[a-z][a-z0-9_]*$")
RESERVED = frozenset(
    {"app", "core", "contracts", "scenes", "assets", "tests", "addons", "tools", "docs"}
)

FACADE_TEMPLATE = """class_name {cls}
extends RefCounted

## Public facade for the `{name}` module.
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.
"""


def register(subparsers) -> None:
    parser = subparsers.add_parser("new_module", help="scaffold a module and register it")
    parser.add_argument("name", help="module name in lower_snake_case")
    # ## Declare the edge where the author is definitely paying attention (DEF-0287)
    #
    # `BARE_REF_UNITS` in tools/arch/rules.py excludes `modules/*`, so a bare
    # module-to-module reference is neither a boundary violation nor a cycle edge and
    # `tools arch` prints `ok` with the edge absent. The registry entry is the ONLY
    # record of it. Declaring it at scaffold time is the one moment the author is
    # certainly reading this command; without the flag, ADR 0134 §2's "declare the
    # dep in registry.json" is a hand edit to a JSON file discoverable only by reading
    # ADR prose.
    #
    # Repeatable, and comma-separated inside either value, so
    # `--deps destiny --deps items,loot` and `--deps destiny,items,loot` agree
    # (INC-0037).
    parser.add_argument(
        "--deps",
        action="append",
        default=[],
        metavar="<mod>[,<mod>...]",
        help=(
            "sibling modules this module will reference through their facades "
            "(repeatable; comma-separated); recorded in tools/arch/registry.json"
        ),
    )


def _class_name(name: str) -> str:
    return "".join(part.capitalize() for part in name.split("_")) + "Api"


def run(args) -> int:
    name = args.name
    if not NAME_RE.match(name) or name in RESERVED:
        raise ToolError(
            f"invalid module name '{name}'; use lower_snake_case and avoid reserved dirs"
        )

    module_dir = MODULES_DIR / name
    if module_dir.exists():
        raise ToolError(f"module directory already exists: {module_dir}")

    registry = rules.load_registry()
    if name in registry:
        raise ToolError(f"module already registered: {name}")

    module_dir.mkdir(parents=True)
    facade = module_dir / rules.FACADE_FILENAME
    facade.write_text(FACADE_TEMPLATE.format(cls=_class_name(name), name=name), encoding="utf-8")

    tests_dir = TESTS_DIR / "modules" / name
    tests_dir.mkdir(parents=True, exist_ok=True)
    (tests_dir / ".gitkeep").write_text("", encoding="utf-8")

    registry[name] = list(rules.DEFAULT_MODULE_DEPS)
    rules.save_registry(registry)

    ok(f"created module '{name}'")
    info(f"  {facade.relative_to(REPO_ROOT).as_posix()}")
    info(f"  {tests_dir.relative_to(REPO_ROOT).as_posix()}/")
    info(f"  registered in {rules.REGISTRY_PATH.relative_to(REPO_ROOT).as_posix()}")
    info(f"next: add tests and wire '{name}' into app/")
    return 0
