# 0034 Meridian network resonance rank and the additive stat-provider rule

- Status: Accepted
- Date: 2026-10-02
- Supersedes: the resonance commitment in ADR 0017; clarifies the provider
  composition rule in ADR 0026

## Context

ADR 0017 committed to "each resonance rank increases the network's flow/capacity/power
bonuses by a fixed amount", and ADR 0028 authored `resonance_rank` (1..12 for realms
19-30) on all 30 body seeds. Nothing implemented it: the field had zero read sites in
`game/src/`, so a whole realm band had no progression payoff distinct from R1.

Separately, `BodyStats` declared private ids `physical_attack` / `physical_defense` while
the stat pipeline uses `Stat.ATTACK_PHYSICAL` / `Stat.DEFENSE_PHYSICAL`, so body
cultivation granted no combat power anything could read. `BodyStats.MOVE_SPEED` and
`BodyStats.POISE` *were* the core ids, and a provider value becomes the baseline for
whatever id it emits (ADR 0026) — so attaching the body path replaced `100 + agility * 2`
with `0.5`, a 200x drop, and rewrote `poise` on a different axis from attack.

## Decision

- **Resonance is a network-level multiplier.** `MeridianNetwork` gains
  `resonance_rank`, `set_resonance_rank(rank)`, and `resonance_multiplier() =
  1 + RESONANCE_STEP * rank` with `RESONANCE_STEP = 0.05`. `get_flow_bonus`,
  `get_capacity_bonus`, and `get_power_bonus` multiply their aggregate by it. Rank 0 is
  inert; rank 12 lifts every bonus 60%.
- **Resonance never decreases.** `BodyTraining.synchronize` applies
  `max(current, seed.resonance_rank)`, so loading a mid-ladder save cannot strip earned
  resonance and stepping down a realm cannot.
- **Resonance persists.** `MeridianNetwork.to_dict` writes `resonance_rank` and
  `from_dict` restores it. The payload is now `{meridians, resonance_rank}`; `from_dict`
  still accepts the bare per-meridian map so older payloads load.
- **A provider contributes additively to stats it does not own.** `BodyProvider` returns
  `context.value(core_id) + body_bonus` for `ATTACK_PHYSICAL`, `DEFENSE_PHYSICAL`,
  `MOVE_SPEED`, and `POISE`. It returns an absolute value only for ids core never
  produces (`carry_capacity`, `regeneration`, `body_cultivation_power`, and the three
  acupoint read-model ids).
- **One id per concept.** `BodyStats.PHYSICAL_ATTACK`, `PHYSICAL_DEFENSE`, `MOVE_SPEED`,
  and `POISE` are aliases of the core ids, not new ones. A module must never invent a
  private id for a stat the pipeline already owns.

## Consequences

- Realms 19-30 now have a progression curve of their own: 12 ranks lifting the whole
  network, layered on the refinement depth that already existed.
- Body cultivation's combat contribution becomes observable, and attaching the path can
  no longer reduce a core stat. `test_body_provider.gd` asserts that invariant directly
  for all four shared ids.
- A module that wants a *replacement* baseline for a core stat still cannot have one
  without erasing the core formula. That is the intended pressure: core owns the shape of
  its stats, modules own their contribution.
- `core/` changed, so this ADR ships with the change. Contract tests cover the network
  in `game/tests/core/test_meridian_network.gd`.