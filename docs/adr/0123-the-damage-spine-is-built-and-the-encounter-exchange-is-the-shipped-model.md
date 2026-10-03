# 0123 The damage spine is built and the encounter exchange is the shipped model

- Status: Accepted
- Date: 2026-10-03
- Supersedes: ADR 0077 "The damage spine and the three mechanisms are designed, not built"
  (`docs/adr/0077-the-damage-spine-and-the-three-mechanisms-are-designed-not-built.md`)
- Partly supersedes: ADR 0076 "An encounter is a stat-resolved exchange, and a boss can
  win" (`docs/adr/0076-an-encounter-is-a-stat-resolved-exchange-and-a-boss-can-win.md`)
- Re-measures: ADR 0069 "Qi damage is an elemental share, never a blended payload"
  (`docs/adr/0069-qi-damage-is-an-elemental-share-never-a-blended-payload.md`)

## Context

Four Accepted ADRs disagreed and two were demonstrably false against the tree.
Measured by grep over `game/src`, `game/tests`, `game/data`:

- ADR 0077 ruled the spine "designed, not built" and tabulated nine symbols at 0 hits.
  All nine now exist. It is superseded, not corrected.
- ADR 0069's `element_share`, `RESIST_DIVISOR`, `CombatTuning` now exist and are used.
- `combat` and `combat_engine` are two live models, not one.

## Decision

**The damage model is one spine plus one encounter layer, and both ship. Neither is
adopted over the other; they answer different questions and neither calls the other.**

- **CURRENT — the spine.** `CombatSpine.resolve_hit` (`modules/combat_engine/spine.gd`)
  runs S1-S11 plus S12. Nine stages are shared; S4/S5 are the `DamageMechanism` seam.
  S1-S12 tokens are present and independent; `mechanism_slot.gd`, `contracts/
  damage_mechanism.gd`, `contracts/damage_proposal.gd`, `combat_tuning.gd` and
  `combat_damage.tres` all ship. `QiDamage` implements the seam and computes ADR 0069's
  formula, including `match` between the elemental term and mitigation.
- **CURRENT — the exchange.** `CombatDamage.resolve_hit` (`modules/combat/damage.gd`)
  returns a share of the target's own pool, clamped `[MIN_SHARE, 1.0]`. ADR 0076 is
  still true for the model it claims, so it is only partly superseded: its claim that
  this is "the whole damage model" is not.
- **The two never call each other.** `combat` calls `CombatEngineApi.tuning()` for
  status math only. `combat_engine` never names `combat`, `loot` or `ui`.
- **`combat_engine` has no production entry point.** `CombatEngineApi.resolve_hit` and
  `bind_mechanism` have zero callers in `game/src` outside their own module; the only
  mention is a docblock example at `modules/techniques/technique_casting.gd:35`.
  The spine is reached only from `game/tests/modules/combat_engine/`. So the spine is
  built and specified, and unwired.
- **The player's only fight is the exchange.** `ui/screens/loot_encounter.gd:124`
  calls `CombatApi.exchange`.

## Consequences

- ADR 0077 is dead and must not be cited: its premise is inverted. Reading it as
  current costs a rebuild of code that exists.
- The registry under-declares the one real edge: `combat` reads `CombatEngineApi` but
  `registry.json` omits `combat_engine` from `combat.deps`. `tools arch` passes anyway
  because `BARE_REF_UNITS` (`tools/arch/rules.py:60`) excludes `modules/*`, so the edge
  is invisible to the gate. Reported, not fixed; correcting it is a registry change.
- BL-0209 and BL-0095 stay open and are now misstated: the spine exists but is unwired,
  which is not "implemented nowhere". BL-0233's risk has landed as fact, not threat.
- ADR 0069's tier-2 dominance defect and its realm-invariance fix are still open and
  still unbuilt; nothing here decides them.
- Body and mind mechanisms remain absent: `QiDamage` is the only `DamageMechanism` in
  `game/src`, so ADR 0070/0071 are design only.