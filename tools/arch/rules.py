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
FAMILIES_PATH = Path(__file__).resolve().parent / "families.json"

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
    # The gather surface (ADR 0097 + BL-0204). The audit that found the economy
    # program "wired to itself" also found the two halves of foraging had no
    # player surface at all: sixteen authored `ResourceNodeDef` `.tres`, a yield
    # table covering every one of them, `HoldingsApi.claim` and
    # `ForageApi.harvest` green in every suite -- and `tools data.py` counting
    # `ForageApi.harvest(` as a production call site because
    # `app/forage_action.gd` exists, while no screen, no button and no nav route
    # ever called it. `HoldingsApi.claim` had NO production caller at all, so a
    # node was never held and `ForageAction.workable` could never be true: the
    # harvest verb was reachable from nothing.
    #
    # Two grants, because the slice has two halves and they read two modules:
    #   - `holdings` needs NO module dependency. `HoldingsApi.summary(actor)` is
    #     already the facade's primitives-only read model: every node's holder,
    #     `vacant`, `condition`, `resting`, `accrued`, `contested`, `kind`,
    #     `yield_per_period` and `upkeep_per_period`, plus the whole authored
    #     `catalog` view. A node row needs nothing else, which is the same shape
    #     `race`, `destiny` and `custody` carry, and it is why no `items` edge is
    #     granted either: the yield is a ledger line, never items (BL-0191).
    #   - `forage` needs NO module dependency either. `ForageApi` declares
    #     `["contracts", "core", "holdings"]` and publishes `yieldable_node_ids`,
    #     `yields` and `has_granter` -- a read model, not a rule. The one
    #     MUTATING verb, `harvest`, is reached through `ForageAction.gather`,
    #     and `ForageAction` is an `app/` type, a `PRIVATE_UNIT`, so the screen
    #     cannot name it: the harvest is injected as a `Callable` at the route
    #     mount, exactly as `QuestScreen.bind_quests` takes the quest commit and
    #     `SoulHearthScreen.bind_soul` takes the save status. That is why this
    #     grant buys a READ and not a verb.
    "holdings": [],
    "forage": [],
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
    # The conversation surface (ADR 0862). A dialogue panel is a read of the facade
    # plus the one verb a conversation has: `current` publishes the node and its
    # choices as primitives, and `choose` moves the actor's OWN dialogue row — the
    # module's own state, never another module's ledger, so this is the `clan` shape
    # (`ClanApi.join` is pressed straight from `clan_screen`) rather than the `quest`
    # bridge shape. Granted with no module dependency: `dialogue` declares only
    # `contracts` and `core` in registry.json, and a conversation reads nothing else.
    "dialogue": [],
    # A doctrine board (the `doctrine` module). A board screen is a pure read of the
    # facade on the same shape as the quest journal: `available`, `boards`, `price` and
    # `summary` all return primitive dicts, and a board row carries its own label, cost
    # and effect rather than making the panel price anything. Granted with no module
    # reach for the reason `quest` and `custody` carry none — a screen that renders a
    # doctrine reaches nothing else, because the stat a row grants is applied through
    # `Actor.add_status` (core) rather than by the panel naming `items`.
    #
    # The COMMIT is not here, and the reason is the one `quest` records: `ui/` may not
    # name `app/`, so a doctrine screen takes `earn` and `redeem` as injected `Callable`s
    # from the composition root, exactly as `QuestScreen.bind_quests` takes the quest
    # commit from `QuestProgram` (ADR 0143's bridge).
    "doctrine": [],
    # The soul and hearth surface (ADR 0127 / 0129 / 0146). Two grants, and the
    # split between them is the design rather than an accident:
    #   - `difficulty` reads no sibling module and stores nothing a screen must
    #     re-derive: `views()` is already a primitives-only preset table and
    #     `select` is the one setter, so a settings surface reads the table and
    #     writes the id and owes no rule. Empty, for the same reason `race`,
    #     `custody` and `quest` are empty.
    #   - `anchor` needs `items` for exactly the reason `loot` does: `cost_of`
    #     publishes an item requirement and the row must print what is still
    #     missing, so the raise is gated on the bag the player actually holds.
    # Neither grant reaches `soul` and neither reaches `save`: the soul and the
    # save arrive the ADR 0143 way, as Callables the composition root hands over,
    # so `ui/` gains no edge into a module that must not be read by name. The save
    # in particular is NOT grantable: ADR 0128 makes its player-facing surface a
    # status line, and `test_no_shipped_caller_can_name_the_backup_slot` is the
    # guard that keeps "the player cannot choose to load the backup" a rule.
    "difficulty": [],
    "anchor": ["items"],
    # The combat readout (ADR 0174). `CombatOutcome.to_dict()` is the engine's own
    # primitives-only read model (ADR 0038) and nothing in `ui/` consumed it: a wound,
    # a necrosis, a sea demotion, a reflected hit, a crit and a parry were all
    # invisible to a player because the engine computed them and no screen rendered
    # them. This grant is the same shape as `status` (ADR 0106) and for the same
    # reason: the read model already exists and is already primitives-only, so a
    # readout panel adds no edge it would need. Granted with NO module dependency --
    # `combat_engine` declares `core` and `contracts` in registry.json and reads no
    # sibling module, so `ui/` gains nothing it could not already reach.
    #
    # **The grant is for the READ side only, and the engine's own facade is the whole
    # of it.** `ui/` may call `CombatEngineApi.breakdown`/`summary`/`band` and nothing
    # else: naming `CombatSpine`, `CombatOutcome`, `MechanismSlot` or any mechanism
    # from `ui/` is still a facade-rule violation, because only `api.gd` is a facade.
    # That is the same limit `techniques` carries and the reason it carries it --
    # a screen that can name a mechanism can reach anything else it likes through the
    # same import.
    "combat_engine": [],
    # The collection surface (unlocks, history, heterosis readout). Four screens
    # render `CollectionApi.summary` / `history` and nothing else: the read model
    # is already primitives-only, so a screen adds no edge it would need.
    # Granted with NO module dependency -- `collection` reads its siblings
    # through its own facade, never through `ui/`, which is the same reason
    # `race`, `quest` and `custody` carry none.
    "collection": [],
}

# Dependencies granted to a newly scaffolded module.
DEFAULT_MODULE_DEPS = ("core", "contracts")

# ## Facade WIDTH is not capped; facade FAN-IN is
#
# `MAX_FACADE_PUBLIC_METHODS = 12` is DELETED. It made each module better and the
# codebase worse: 18 of 41 facades sat at exactly 12, so the rule was the
# architecture rather than a pressure on it; it blocked shipping one large
# coherent feature, because a 100-realm expansion is a content change and a
# 12-verb interface rule answers it either by merging unrelated things or by
# inventing a split that means nothing; and it GENERATED five modules that exist
# only as dodge (domain, combat_engine, anchor, world_spawn, socket). A
# constraint that 44% of modules contort to satisfy has stopped being a rule.
# It also had no selftest red path, so it was never proven to fire (INC-0016).
#
# What it was a proxy for is coupling, and coupling is already guarded by the
# facade rule, the `BARE_REF_UNITS` scan and the cycle check — none of which
# depended on the number. The thing the cap could NOT see is the real risk: a
# facade many modules import is a coupling problem at 12 methods or at 30. So
# the replacement measures fan-in, which is what actually predicts a god object.
MAX_FACADE_FAN_IN = 8

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


def load_family_roots() -> dict[str, str]:
    """The content ROOTS the families are declared against (ADR 0233).

    A second root, declared beside the families rather than beside the audit that walks
    it, so the declaration stays one machine-managed file. `game/src/data` exists because
    `domain/api.gd:28-31` put the authored domain content there deliberately: the 160
    legacy `DomainDef` records under `game/data/domains` are a DIFFERENT, older content
    set, and pointing `DATA_ROOT` at both would grade one with the other's schemas.

    Every family with no `root` belongs to `data` — the default is the historical root, so
    adding a second one is purely additive and no existing family changes meaning.
    """
    if not FAMILIES_PATH.is_file():
        return {}
    data = json.loads(FAMILIES_PATH.read_text(encoding="utf-8"))
    roots = data.get("roots", {})
    return {"data": "game/data", **{name: rel for name, rel in roots.items() if name != "data"}}


def load_families() -> dict[str, dict]:
    """The content-family declaration (ADR 0184).

    family -> {data_dir, def_class, module, path?, root?}.

    Read, never hand-edited into a second copy: the gates that walk the content roots
    key off this file so an unknown content family fails loudly instead of being
    silently skipped. A family with no entry here is undeclared content.

    `root` names which of [function load_family_roots]' directories this family lives
    under, and defaults to `data` — the historical single-root shape, unchanged.
    """
    if not FAMILIES_PATH.is_file():
        return {}
    data = json.loads(FAMILIES_PATH.read_text(encoding="utf-8"))
    return data.get("families", {})


def save_registry(modules: dict[str, list[str]]) -> None:
    payload = {
        "version": 1,
        "modules": {name: {"deps": sorted(deps)} for name, deps in sorted(modules.items())},
    }
    REGISTRY_PATH.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
