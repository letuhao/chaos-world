# 0133 Combat engine is the single source of truth for damage

- Status: Accepted
- Date: 2026-10-03

## Context

**Two combat modules exist and only one is real.** `game/src/modules/combat_engine/` is
15 `.gd` files: a 12-stage spine (`spine.gd`), a band roll (`band.gd`), a shield gate,
reflect, leech, status application (`status_apply.gd`, S12), tuning in `combat_damage.tres`,
and three damage mechanisms — `qi_damage.gd`, `body_damage.gd` with `body_location.gd` and
`body_wounds.gd`, and `mind_damage.gd`. `game/src/modules/combat/` is 5 `.gd` files:
`CombatApi`, `CombatDamage`, `CombatDuel`, `CombatDuelHit`, `CombatExchange`, and its damage
model is share-of-pool (ADR 0076).

Both are live and neither calls the other's damage path. `combat` calls
`CombatEngineApi.tuning()` once (`exchange.gd:272`), for status math only; `combat_engine`
names neither `combat`, `loot` nor `ui`. `registry.json` declares `combat_engine:
["contracts", "core"]` against `combat: ["contracts", "core", "loot", "status"]`.

The cost is concrete. `ui/screens/loot_encounter.gd:124` calls `CombatApi.exchange`, so a
**boss fight resolves through `combat`'s share model**. A **player-vs-player hit resolves
through `combat_engine`** — `app/combat_boot.gd:82` binds `QiDamage`,
`app/item_workbench_app.gd:359` calls `CombatEngineApi.breakdown`. Two damage paths.

**ADR 0077 is false now.** It tabulated `damage_mechanism`, `DamageProposal`,
`CombatTuning`, `combat_damage`, `RESIST_DIVISOR`, `element_share` and the necrosis
thresholds at 0 occurrences and ruled the spine "designed, not built". Every one exists.
BL-0221 already says so: *"Do not treat 0077 as current truth."*

## Decision

**`combat_engine` is the SSOT for damage resolution. Damage arithmetic lives in exactly one
place. `combat` becomes an encounter layer, reconciled or removed afterwards.**

- **The spine owns resolution.** Every hit resolves through `CombatSpine.resolve_hit`.
  `CombatDamage.resolve_hit` stops being a damage model; its `BASE_SHARE`, `MIN_SHARE` and
  `POWER_CEILING` arithmetic is retired.
- **`combat` is reduced to what it uniquely owns**: who is fought, what the fight is worth,
  and the persisted loss record (`CombatDuel` on `module_data["combat_duel"]`, ADR 0027's
  pattern). `exchange()` survives as the encounter verb.
- **The spine binds the mechanism; nothing falls back.** `CombatSpine` already reads
  `MechanismSlot.of(attacker)`. A hit with no mechanism bound is a wiring fault.
- **ADR 0077 is superseded, not corrected** — ADRs are immutable, so its stale table stands
  and this ADR names it dead. ADR 0123's "both ship" is superseded on priority, not fact.

## Consequences

- **Three mechanisms coexist with no declared edge between them.** `combat_engine` declares
  `["contracts", "core"]` and names no class of `elements` and no cultivation module.
  `ElementRules` is **injected** as `ctx.data["element_rules"]` (`qi_damage.gd:100`), held
  as a `Variant`, and `combat_tuning.gd` keeps the `elements` stat-id prefixes as `String`s
  not `StringName`s. That injection is how one module hosts three divergent damage models
  without the registry lying or the mechanisms importing each other.
- **Three mechanisms on one ladder and one spine is the point of the program.** Two damage
  models is the one way to guarantee they never diverge.
- **The 551x-vs-12x question is OPEN and this ADR does not settle it.** `combat_engine`
  scales `ATTACK_PHYSICAL` by authored realm power, `1.0` to `551.46`
  (`core/realm_power_table.tres:37`), while authored boss vitality spans **40-800 across
  320 `game/data/loot` encounters** — a 20x span, not the 12x `combat`'s docstrings claim.
  `combat`'s share model exists to solve that desync, and MERGE-DECISION.md ruled its
  `clampf(MIN_SHARE, 1.0)` an immunity delete. What would settle it: a measured
  cross-mechanism balance report at both ends of the ladder.
- **`combat`'s docstrings now contradict this ADR in three places**, recorded not edited:
  `damage.gd:12` and `exchange.gd:24` claim vitality spans `40-520` and `12x` (measured
  40-800, 20x); `api.gd:19` says *"A shield is a wave the spine does not have yet"* while
  `spine.gd:70` already declares `SHIELD_COMPONENT` and runs S9's absorb.
- **BL-0209, BL-0221, BL-0222 and DEF-0095 are re-worded, not closed.** The spine exists,
  is wired from `app/`, and has three mechanisms; "implemented nowhere" is false.
- `Actor.SCHEMA_VERSION` stays **4**. Nothing here changes a persisted shape.