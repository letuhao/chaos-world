# 0001 Actor base and derived stat model

- Status: Accepted
- Date: 2026-10-01

## Context

Every actor (player, NPC, spirit beast) needs one shared source of stats for all game logic. Stats must stay consistent, serialize cleanly, and work without the scene tree so combat/cultivation logic is testable headless and not entangled with Godot nodes. Cultivation progression (realms, spirit roots) must scale stats without code changes.

## Decision

- `Actor` is a `core` foundational type (RefCounted, no Node): identity, faction, tags, `realm_id`, `spirit_roots`, `stats`, `vitals`, signals.
- `ActorStats` stores only **base attributes** plus a source-tagged **modifier stack**; **derived stats** are recomputed from `(base, modifiers, realm multipliers, spirit roots)` and never stored as truth.
- Derivation: `derived = clamp((base + flat) * (1 + percent) * mult, 0, cap)`.
- Realm scaling is a **data-driven** table: `RealmDef` is a Godot `Resource` (editor-authored `.tres`); the stat engine consumes plain multiplier inputs, keeping derivation engine-agnostic.
- Base attributes (7): `physique`, `spirit`, `aptitude`, `comprehension`, `agility`, `will`, `fortune`.
- Derived stats (groups): vitals (`max_health`/`max_qi`/`max_stamina`), regen, offense (physical/spiritual attack, crit chance/damage, penetration, attack speed), defense (physical/spiritual defense, evasion, damage reduction, poise, status resistance), mobility (`move_speed`), cultivation (`cultivation_rate`, `qi_absorption`, `breakthrough_chance`, `dao_heart`, `insight_gain`), utility (loot, cooldown/qi-cost reduction), and per-element power/resistance.
- Dimension: **2D** (movement via `godot-2d-movement` + `godot-tilemap`).
- `Actor` serializes with a schema `version` from day one.

## Consequences

- Modules read `Actor`/`ActorStats`; Godot `Node` adapters wrap an `Actor` outside `core`.
- All stat writes go through `ActorStats`; direct mutation is forbidden so derived cannot desync.
- Changing `core/` requires an ADR — this one covers the actor base.
- Full stat formulas live in `core/actor_stats.gd` and are pinned by tests in `game/tests/core/`.
- Adding a realm is authoring a `.tres`, not a code change.
