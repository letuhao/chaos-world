"""Boundary policy (rarely changes) and the machine-managed module registry.

`registry.json` is written by `tools new_module`; do not hand-edit it unless the
tool is unavailable. Policy below is the single source of truth for `tools arch`.

Cross-module edges come from three detectors: `res://` references, `extends
<ClassName>`, and — for the units in `BARE_REF_UNITS` only — bare typed
references (`var x: Foo`, `Foo.method()`). `res://`/`extends` are always on;
`BARE_REF_UNITS` is what the resolver is trusted to do without false positives.

Limitation that remains: `BARE_REF_UNITS` excludes `core/` and `modules/*`, so a
bare reference out of those units is not a load-bearing edge the gate sees. It is
reported as an unresolved count rather than enforced — see
`enforce.unresolved_bare_edges`.
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
    "ui": {"core", "contracts"},
}

# Units that may only be referenced from within themselves.
PRIVATE_UNITS = frozenset({"app"})

# Units whose bare typed references are resolved as real cross-unit edges.
# Measured over the whole tree, each addition below costs 0 reported violations.
#
# `ui/` is here because it is held to the facade rule: a panel calls the facade by
# name (`BodyTraining.cultivate(...)`) with no `res://` and no `extends`, so the
# rule is unenforceable without the bare resolver.
#
# `app/` is the composition root and may depend on anything, so every edge it
# declares is legal by construction and resolution can only *confirm* it - it can
# never contradict LAYER_DEPS. That makes widening here risk-free by design.
#
# `contracts/` is the leaf layer and may depend on nothing at all, so a bare
# reference out of it to any other unit is unconditionally a violation. There is
# no legitimate shape the resolver could misread, and the repo currently has none.
#
# `core/` and `modules/*` are deliberately NOT here. Measured, a bare scan there
# is a wall of false positives: `core/actor.gd` legitimately casts to `Dantian`
# (qi_cultivation) and `SeaOfConsciousness` (mind_cultivation) to restore a save,
# and the item-consuming modules legitimately name `ItemDef`, `ItemInstance`,
# `ItemRarity` and `OptionCatalog` while routing every *call* through `ItemsApi`.
# A resolver that reads a type annotation as a dependency cannot tell a restore
# path from a gameplay path. Enforcing it would demand `preload()` ceremony in
# files that are correct today, so it stays documented-instead-of-enforced.
BARE_REF_UNITS = frozenset({"ui", "app", "contracts"})

# `ui/` is a pure consumer of gameplay modules: it may reach a module only
# through that module's facade (`api.gd`), and only if the dependency is
# declared here. This is what lets a UI program and a gameplay program run in
# parallel without either one silently owning the other's internals.
# `ui/` may never reference `app/` (boot/wiring) or any other `ui/` layer rule.
UI_MODULES: dict[str, list[str]] = {
    "items": [],
    "body_cultivation": ["items"],
    "mind_cultivation": ["items"],
    "qi_cultivation": ["items"],
    "dual_cultivation": [],
    "fertility": ["dual_cultivation"],
    "elements": [],
    "combat": [],
    "world": [],
    "socket": ["items"],
    "set_bonus": ["items"],
    "loot": ["items"],
    # Declared ahead of the module: a technique is a namespaced stat modifier whose
    # authored content reads item requirements, so `ui/` needs the same reach into
    # `items` that body_cultivation and qi_cultivation already have. The directory
    # may not exist yet — a registered-but-absent module is a warning, not a
    # failure, so the permission can be granted in the wave before the body.
    "techniques": ["items"],
    # Fate and destiny are earned, never chosen, and a destiny codex is a pure
    # read of the facade. Granted with no module dependency: the fate tree reads
    # nothing from other modules.
    "destiny": [],
    # Lineage stack (ADR 0062/0063/0064). `ui/` may read race, bloodline and clan,
    # but only through each facade: a bloodline screen needs the actor's race to
    # label a lineage, and a clan screen needs the founding bloodline to name what
    # the clan recognises. These are reads of already-declared module deps, not new
    # reach — `clan` declares `race` and `bloodline` for exactly this reason.
    "race": [],
    "bloodline": ["race"],
    "clan": ["bloodline", "race"],
    # Institution stack (ADR 0083/0084). A sect screen reads the player's claim, a
    # nation screen reads the board of offices, and both need to label a member's
    # standing with the institution that holds it — so `sect` declares `clan` and
    # `nation` declares `sect` for that read, exactly as `clan` declares `race`.
    # Granted ahead of the body: a registered-but-absent module is a warning, not a
    # failure, so the permission can land in the wave before the screens do.
    "sect": ["clan"],
    "nation": ["sect", "clan"],
    # Market (ADR 0100). A shop panel and a floor panel are pure reads of the facade, and a
    # shop screen has to price what it shows, so `market` declares `economy` for exactly the
    # reason `loot` declares `items`. Granted in the same change as the body, so the
    # permission is never ahead of a screen that needs it.
    "market": ["economy"],
    # Custody (ADR 0104). A custody panel reads only the facade: the claim's holder, term and
    # periods are all keys inside `summary()`, and the subject's name is resolved by the panel
    # through the same catalog seam `app/` wires for `npc`. No module reach is needed, so the
    # grant is empty — the same reason `race` and `destiny` carry none.
    "custody": [],
    # The heavenly tribulation gates the Immortal tier on the SHARED ladder, so all
    # three paths read the same predicate and a tribulation screen is not a body,
    # qi or mind screen. Granted with no module dependency: the fight is priced off
    # core state on the actor, never off a path's own resources.
    "heavenly_tribulation": [],
    # Status readout (ADR 0106). A burn is invisible until something shows it, and a
    # status row is a pure read of the facade: the id, its remaining time, its scope
    # and its pulse count are already inside `summary()`, so the fight screen can show
    # what is eating the player's health without owning a rule. Granted with no module
    # reach for the same reason `race` and `custody` carry none — the status module
    # reads no sibling module, and a readout therefore adds no edge it would need.
    "status": [],
    # The quest journal (ADR 0113 / ADR 0114 / ADR 0143). A quest screen is a pure
    # read of the facade: `offered`, `active`, `steps`, `gates_for` and `summary`
    # all return primitive dicts, and every step count comes out of the shared
    # `WorldFact` ledger rather than a counter the UI owns. Granted with no module
    # dependency for the same reason `race` and `custody` carry none — the quest
    # module declares `core` and `contracts` in registry.json and reads no sibling
    # module, so a journal adds no edge it would need. The COMMIT is not here: `ui/`
    # may not name `app/`, so `QuestScreen` takes its accept verb as a `Callable`
    # from `QuestProgram` (ADR 0143's bridge), and that file is the only thing in
    # `src/` that calls `QuestApi.accept`.
    "quest": [],
}

# Dependencies granted to a newly scaffolded module.
DEFAULT_MODULE_DEPS = ("core", "contracts")

# ISP: maximum public methods a module facade (`api.gd`) may expose.
MAX_FACADE_PUBLIC_METHODS = 12

# SRP signal: a script longer than this warns (does not fail the gate).
LINE_BUDGET = 400

# --- Placement conventions (warnings, never failures) -----------------------
#
# Each of these is a convention the repo follows by practice and by ADR, with no
# hard rule behind it. They warn instead of failing so that a prototype file that
# predates the convention cannot turn the gate red on an unrelated change; the
# gate's job is to say "this is where the architecture is drifting", not to make
# an agent's first move on a new file a rebuild.

# An authored content type is a `Resource` subclass: the thing an author fills in
# as a `.tres`. The repo's own precedent is 28 of them — 23 in the module that
# owns the content and 5 in `core/` for cross-cutting foundation data, and 0 in
# `contracts/`. `contracts/` is for dependency-free interfaces, value objects and
# event/signal contracts; an authored `Resource` there is a feature's state
# machine filed as a contract, which is where a save schema goes to grow without a
# module ever owning it. No `.tres` anywhere in this repo binds a `contracts/`
# script, so nothing was authored against it.
#
# Kept as prefixes rather than an explicit module list: a new module is a home by
# construction, and `enforce.resource_home_warnings` measures the count on the pass
# so the number in its message cannot drift from the tree.
RESOURCE_HOME_UNITS = ("core", "modules")

# The composition root wires; it does not own gameplay state. `app/` legitimately
# holds `main.gd`, `actor_factory.gd`, `item_workbench_app.gd` and
# `world_entry.gd`, all of which hold references and constants and never state.
# A *stateful* system in `app/` is different: it keeps a slot array, a cooldown
# table or a persistence key, so the rules that own that data live outside the
# module that would change to fix it. `APP_STATE_MARKERS` is the narrow set of
# declarations that mean state rather than wiring, and the heuristic requires two
# independent ones so a single `tick` on a controller cannot trip it.
APP_STATE_MARKERS: tuple[tuple[str, str], ...] = (
    ("persistence", r"\b(?:set_module_data|get_module_data)\s*\("),
    # Godot's own callbacks are underscore-prefixed (`_process`, `_physics_process`),
    # while a feature's decay loop is a plain `tick`. Both are "advanced by time
    # rather than called by a caller", so both match; the leading underscores are
    # optional so the engine spelling is not silently invisible to the check.
    ("tick-loop", r"^\s*(?:static\s+)?func\s+_?(?:tick|process|physics_process)\s*\("),
)
# A typed member array is state only when the element type is a class this repo
# defines. `Array[Marker2D]` is a bound node list; `Array[SkillDef]` is a feature's
# authored content, and the distinction is the one that matters.
#
# Both member patterns are anchored to column zero on purpose. A `var` inside a
# function body is a local, not a member: `player_adapter.gd` reads two of them
# out of a save blob (`var pos: Array = data.get(...)`), and an unanchored match
# counted its deserialization locals as a feature state table and flagged a file the
# checker is supposed to leave alone.
APP_UNSHAPED_ARRAY_RE = r"^(?:var|@onready\s+var)\s+\w+\s*:\s*Array\s*(?:=|$)"
APP_CONTENT_ARRAY_RE = r"^(?:var|@onready\s+var)\s+\w+\s*:\s*Array\[(?!\s*$)([A-Z]\w*)\]"


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
