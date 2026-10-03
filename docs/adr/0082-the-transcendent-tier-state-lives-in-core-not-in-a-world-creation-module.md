# 0082 The Transcendent-tier state lives in core, not in a world_creation module

- Status: Accepted
- Date: 2026-10-03
- Corrects: ADR 0019's module layout and ADR 0021's "`DaoDef` is a module-level resource"
- Consistent with: DEF-0024, DEF-0025, DEF-0026, ADR 0058, ADR 0077

## Context

ADR 0019 specified World Creation as a new module and listed its files. ADR 0021 specified
Transcendent ascension and placed its resource type. Both were written before the code existed and
neither was reconciled afterward, so both name files and locations the tree does not have.

**ADR 0019:22 (`Consequences`) — "**Module**: `game/src/modules/world_creation/` — `api.gd`
(facade), `world_state.gd`, `world_law.gd`, `creation.gd` (5-step process), `tribulation.gd`,
`management.gd`".**

- `game/src/modules/world_creation/` **does not exist.** `modules/` holds 17 entries; there is no
  `world_creation`. `registry.json` has no `world_creation` entry either.
- `creation.gd`, `management.gd` and `world_state.gd` **do not exist anywhere** in `game/`. The
  only `tribulation.gd` is `core/tribulation.gd`, which is the heavenly-tribulation system, not
  world creation's.
- Every state type ADR 0019's data model names is in **`core/`** under a different filename:
  `WorldState` is `class_name WorldState` in `core/world_creation.gd:1`;
  `WorldLawState` in `core/world_law.gd:1`; `WorldLayerState` in `core/world_layer.gd:1`;
  `InhabitantRef` in `core/inhabitant_ref.gd:1`. ADR 0019 named them `world_state.gd`,
  `world_law.gd` and an `InhabitantRef` type with no file at all.

**ADR 0021:62 — "`DaoDef` is a module-level resource."** `DaoDef` is
`class_name DaoDef` in **`core/dao_def.gd:1`**. There is no module owning it.
(The same line's "`AscensionState` lives in `core/` alongside `Actor`" is **correct**:
`core/ascension_state.gd:1`, wired through `Actor.ascension`'s setter at
`core/actor.gd:49-55`.)

## Decision

**The Transcendent tier is `core/` state with `core/` verbs, and `modules/world/` owns the authored
content definitions only.**

- `Actor.inside_world: InsideWorld`, `Actor.world: WorldState` and `Actor.ascension: AscensionState`
  are plain fields on the core actor (`core/actor.gd:47-55`), serialized as `inside_world`,
  `world` and `ascension` payload slots (`actor.gd:226,229,232`). `Actor.SCHEMA_VERSION` is 4.
  ADR 0019's "schema version bump to 2" and ADR 0021's "`SCHEMA_VERSION` bumps to 2" are both
  long overtaken.
- **The gate and the verbs are core, deliberately.** `WorldAnchor` (`core/world_anchor.gd`) owns
  the commit schedule (`COMMIT_SEED 18 / POCKET 21 / INNER 24 / MICRO 27 / GREAT 29`),
  `stage_met`, `ascend`, `ascension_unmet` and `bind_components`. ADR 0041 established the rule
  this follows: a verb shared by all three cultivation systems goes in `core`, not on three
  facades already at the 12-method cap.
- **The five `World*Def` content Resources are in `modules/world/`**, as ADR 0045 specified, and
  the content tree is `game/data/world/{tiers,laws,factions,locations,inhabitants}` — all five
  directories present.
- **What ADR 0019's five-step ritual, upkeep, damage, merge and ascension-to-world-tier are: not
  built.** `WorldState.pay_upkeep` was deleted outright in ADR 0058 (only `WorldApi.pay_upkeep`
  charges, at `modules/world/api.gd:121`), and nothing in `src` calls `WorldAnchor.ascend`.

## Consequences

- **Do not create `modules/world_creation/`.** The types are in `core/`; a new module would
  duplicate them and need a `registry.json` entry to satisfy `tools arch`. If the ritual is ever
  built, it builds on `core/world_creation.gd`.
- **DEF-0025 ("World Creation system (Transcendent tier)", `done`) is half true.** The state and
  the gates exist; the five-step creation process, the upkeep loop and the merge/ascension
  mechanics do not.
- Two gaps remain open and are already recorded elsewhere, not here: `Actor.from_dict` restores
  `inside_world` and `world` without re-mirroring them into `components`, so after a load
  `inside_world_stability` and the world stat go quiet until the next `commit` (ADR 0058's
  "Gap owned elsewhere"); and nothing calls `ascend` (same ADR). `core/world_creation.gd:25` still
  cites `app/main.gd` handing out a bootstrap Micro world — a file that no longer exists (see ADR
  0080).
