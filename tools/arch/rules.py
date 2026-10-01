"""Boundary policy (rarely changes) and the machine-managed module registry.

`registry.json` is written by `tools new_module`; do not hand-edit it unless the
tool is unavailable. Policy below is the single source of truth for `tools arch`.

Limitation: cross-module edges are detected from `res://` references and
`extends <ClassName>` declarations. Bare typed references (`var x: Foo`) are not
yet resolved; rely on `res://`/`extends` for load-bearing dependencies.
"""

from __future__ import annotations

import json
from pathlib import Path

REGISTRY_PATH = Path(__file__).resolve().parent / "registry.json"

FACADE_FILENAME = "api.gd"

# Layer -> units it may depend on. "*" means "any unit, subject to facade rules".
LAYER_DEPS: dict[str, set[str]] = {
    "app": {"*"},
    "core": {"core", "contracts"},
    "contracts": {"contracts"},
}

# Units that may only be referenced from within themselves.
PRIVATE_UNITS = frozenset({"app"})

# Dependencies granted to a newly scaffolded module.
DEFAULT_MODULE_DEPS = ("core", "contracts")

# ISP: maximum public methods a module facade (`api.gd`) may expose.
MAX_FACADE_PUBLIC_METHODS = 12

# SRP signal: a script longer than this warns (does not fail the gate).
LINE_BUDGET = 400


def load_registry() -> dict[str, list[str]]:
    if not REGISTRY_PATH.is_file():
        return {}
    data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    modules = data.get("modules", {})
    return {name: list(entry.get("deps", [])) for name, entry in modules.items()}


def save_registry(modules: dict[str, list[str]]) -> None:
    payload = {
        "version": 1,
        "modules": {name: {"deps": sorted(deps)} for name, deps in sorted(modules.items())},
    }
    REGISTRY_PATH.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
