# 0056 A technique is a module-owned Resource, and a runtime system is a module

- Status: Accepted
- Date: 2026-10-02
- Partly superseded by: ADR 0124 "The derived-stat census is 27, and combat now reads ten of
  them" — the "Thirteen of the 25 derived combat stats are unread" claim below is false and
  is superseded, as is the count behind it. Nothing else in this ADR is superseded.

## Context

The repo has an untracked prototype: `contracts/skill_def.gd` (a `Resource` with `@export`
fields) and `app/skill_system.gd` (a stateful slot machine with cooldowns). Neither is reachable
from any scene, any script, or any data file. Together with `input_handler.gd` and
`consumable_system.gd` they are 622 lines of prototype with one consumer: their own tests.

Two placements were on the table: keep the Resource in `contracts/`, or put it in the module that
owns the feature.

The precedent is unambiguous. Thirty authored `Resource` classes exist. Twenty-five live in their
owning `modules/<x>/` directory; five live in `core/` because three or more modules share the
vocabulary. **Zero live in `contracts/`.** No `.tres` anywhere in the repo binds a `contracts/`
script. The nearest prior art is decisive: `DualTechniqueDef` is literally a technique definition,
a `Resource` with `@export` fields, and it lives in
`modules/dual_cultivation/dual_technique_def.gd` beside its `TraitDef`.

`contracts/` holds interfaces, value objects and signal contracts — all `RefCounted`, all
constructed in code, all travelling between modules. `SkillDef` is a content type, authored by a
designer in the inspector and shipped as game data.

`app/` is the composition root: boot, autoloads, wiring. A slot array with cooldown state and a
tick loop is feature logic. Every other runtime system in the repo lives in a module. The
prototype's `_save()` also persists `skill.to_dict()` — the whole authored definition — where
`Equipment`, `BodyAdvancement`, `MindAdvancement` and `ConsumableSystem` all persist an id.

Two things made this drift invisible. `tools arch` never inspects a class's base type, and it
only scans bare typed references inside `ui/`, so an `Array[SkillDef]` in `app/` is invisible to
the checker. And the prototype had no test outside its own.

## Decision

- **A `TechniqueDef` content Resource lives in its owning module**, never in `contracts/`.
  `contracts/` keeps only what is genuinely shared between modules.
- **A runtime per-actor system is a module component**, not a file in `app/`. `app/` wires it;
  it does not implement it. The prototype's slot machine, cooldown handling and persistence move
  into a module behind an `api.gd` facade.
- **Persist ids, not definitions.** A save stores a `StringName` def id and rehydrates. Otherwise
  a designer retuning a cooldown silently rewrites every existing save.
- **A shared interface is a separate decision**, taken only once a second module actually
  consumes techniques. An interface with one implementor and no callers is ceremony.
- **An active technique needs a damage pipeline it does not have.** `combat/api.gd` exposes two
  methods and a shield whose `absorb()` nothing calls. Thirteen of the 25 derived combat stats
  are unread, including the four the 551x realm ladder feeds. This decision fixes *where* the
  system lives; it does not pretend the system can be completed before `DEF-0078` and
  `DEF-0007`.

## The `TechniqueDef` field list

One `Resource` authored as `.tres` in `modules/techniques/`. Every field names a type the
repo already has; nothing here is a new concept.

| Field | Type / default | Reuses |
|---|---|---|
| `id`, `display_name`, `description`, `tags` | `StringName`, `String`, `String`, `Array[StringName]` | `ItemDef`'s identity fields; `id` is the saved key |
| `grade`, `rarity` | `StringName` | `ItemGrade` / `ItemRarity` constants; grade sets the realm floor via `required_tier()`, rarity budgets options and never power |
| `element`, `school` | `StringName`, `Array[StringName]` | a real `ElementDef` id, `""` = unelemental; schools group and search, never gate |
| `active` | `bool = true` | false = passive (ADR 0054) and no cost block |
| `path` | `StringName = PathState.QI` | one of `PathState.ALL`, a `SHARED` value, or `"<a>+<b>"` for DUAL |
| `min_path_realm` | `Dictionary` | `path_id -> min ordinal`; ADR 0059 |
| `requirement` | `ItemRequirement = null` | the base/attribute gates, reused unchanged |
| `required_meridians` + `required_channel_state` | `Array[StringName]` + `StringName` | `QiRealmSeed`'s pair; the state is a `MeridianState` constant |
| `required_acupoints` + `required_acupoint_tier` | `Array[StringName]` + `StringName` | `BodyRealmSeed`'s pair; the tier is an `AcupointDef.tier` |
| `qi_cost`, `stamina_cost`, `cooldown` | `float = 0.0` | drain the existing `qi` / `stamina` pools; cooldown in seconds |
| `upkeep`, `upkeep_interval` | `Dictionary`, `float = 60.0` | `ItemRequirement`'s exact pair |
| `mastery_rungs` | `int = 5` | the per-rung multipliers are ADR 0055 constants, not data, so no sixth rung is authorable |
| `magnitude` | `float = 1.0` | the coefficient ADR 0055's ladder multiplies |
| `passive_options` | `Array[Dictionary]` | `ItemDef.fixed_modifiers` verbatim (`{option_id, value}`); ADR 0054 |

## Consequences

- The technique system gets a facade and a registry entry, and starts within the 12-method cap.
  The prototype already had 10 public methods, so the cap binds immediately.
- The 1363 existing technique items remain valid as acquisition vectors. They are not technique
  *definitions*, and this decision does not require migrating them.
- Because the checker cannot see bare typed refs outside `ui/`, nothing will catch a regression on
  this rule. That risk is the reason this ADR exists rather than a rule.
- Deleting or rewriting the four prototype files is a consequence of this decision, not a
  prerequisite for it.