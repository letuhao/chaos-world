# 0046 World tier system

- Status: Accepted
- Date: 2026-10-02

## Context

ADR 0005 unified all cultivation on a 30-realm ladder (Mortal 1-9, Spirit 10-18, Immortal 19-27, Transcendent 28-30). ADR 0019 defines world creation for the Transcendent tier. The game needs four world tiers mapped to these realm bands so world content scales with cultivation progress.

## Decision

- Four world tiers, each mapped to a realm band:
  - `mortal_world` — Mortal World (凡界) — realms 1-9 — world seeds germinate, karma accumulates
  - `spirit_world` — Spirit World (灵界) — realms 10-18 — world laws manifest, six paths operate
  - `immortal_world` — Immortal World (仙界) — realms 19-27 — Heavenly Court governs, world evolution visible
  - `transcendent_world` — Transcendent World (道界) — realms 28-30 — Dao accessible, worlds created/destroyed
- Each tier defines: law_slots, available_life_forms, upkeep_rate range, time_flow range, size range.
- Tier is stored on `WorldState.tier` and gates all property ranges, law slots, and functions (ADR 0019).
- Higher tiers unlock more law slots, life forms, and larger size ranges.

## Consequences

- World tier is the primary gating axis for world content.
- Adding a tier is authoring a `.tres` + updating `WorldTierDef`, not code.
- Tier ranges are contiguous and non-overlapping: 1-9, 10-18, 19-27, 28-30.
