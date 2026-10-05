# 0087 Status application is stage S12 of the spine, on clean landed hits, from a seeded substream

- Status: Proposed
- Date: 2026-10-03
- Extends: ADR 0067 (adds a twelfth stage), ADR 0075, ADR 0069

## Context

ADR 0067 fixes an 11-stage spine and states the shared spine "carries no element
payload — that is the qi mechanism's job" (ADR 0069). That sentence is binding and this
ADR does not contradict it: **S12 carries no element payload either.** It carries a
`StringName` status id the technique already named, exactly as the technique's
`element` is already named at intent (`modules/techniques/technique_def.gd`). The
elemental read — potency from the landed elemental term — happens *inside* S12, not in
the spine, and reads nothing the spine does not already publish.

ADR 0075 already routes environment hazards through `StatusEffect` and
`Actor.tick_statuses`, so a status now has a **required second consumer** beyond
combat. Two producers must obey identical rules or a fight is incoherent.

The design doc proposed "S12 after HP". That placement is right, and it is also the
only one that is right: all four load-bearing orderings in ADR 0067 constrain S12's
position without exception, and two of them are new orderings this stage adds.

## Decision

**S12 is the spine's twelfth stage, LAST, after S11 lifesteal. It runs only on a CLEAN
landed hit.**

- `CombatSpine._spend` returns the `CombatOutcome`; S12 then reads `outcome.is_clean()`
  (`modules/combat_engine/outcome.gd:91`) and the proposal's `effects[]`
  (`contracts/damage_proposal.gd:20,61`), already "applied AFTER health" by ADR 0067.
- **Against ADR 0067's four orderings, all four hold:**
  - *S1 before S2* — untouched. S12 is after S2, so a miss applies nothing.
  - *S2 before S4* — untouched, and S12 inherits it: `is_clean()` is false for a miss,
    so no status is ever applied from a blow that never arrived.
  - *S4 before S6* — untouched.
  - *S7 before S8 before S9* — untouched.
- **Two new orderings, each independently assertable:**
  - *S9 before S12* — status application reads post-HP state, so a defender that died
    of the blow is not burned by it. A death-flagged status is authored on the def, not
    inferred.
  - *S11 before S12* — lifesteal is a separate packet after HP; a status applied before
    it could change `health_regen` mid-packet. S12 is last, so this holds by
    construction.
- **Trigger: a landed hit, an authored `status_chance`, and one seeded draw.** Rejected:
  every hit with no roll (twenty statuses × no resistance read is unanswerable CC);
  on-crit-only (crit caps at 0.75, `core/actor_stats.gd:154`, and is a separate dial from
  element, so it would gate statuses behind a stat that has nothing to do with them).
- **The draw is one `rng.randf()` on a per-hit SUBSTREAM, never the caller's stream and
  never `randf()`.** `status_seed = (hit_seed * 2654435761 + absi(hash(attacker.id ^
  defender.id ^ hit_index))) & 0x7FFFFFFF` — the exact shape
  `LootState._encounter_seed` already uses (`modules/loot/loot_state.gd:612-614`). Three
  draws per landed hit maximum: band, crit, status. `CombatApi.resolve_hit` already
  takes `rng: RandomNumberGenerator = null` (`modules/combat/api.gd:68`); a null rng
  means no draw and no status, never a silent `randf()` fallback of the kind
  `qi_cultivation/advancement.gd:109` uses.
- **Resistance is ADR 0069's formula, read once, not restated.**
  `elem_resist = clampf(element_resistance_<e>/RESIST_DIVISOR - mastery_pen, 0,
  RESIST_CAP)`, then `p_apply = clampf(chance * (1 - Stat.STATUS_RESISTANCE) *
  (1 - elem_resist), P_MIN_APPLY, 1.0)`. One resistance vocabulary in the game; the
  mastery penetration is subtracted **before** the clamp, so it can never amplify past
  `RESIST_CAP`.
- **Every constant lands in `combat_damage.tres` on `CombatTuning`** — `RESIST_DIVISOR`,
  `RESIST_CAP`, `mastery_pen`, `P_MIN_APPLY`, `STATUS_POTENCY_SCALE`,
  `STATUS_POTENCY_FLOOR`. Not one of them is a literal in a `.gd` (ADR 0067).
- **Rejected: `stat_resist + elem_resist`.** The design doc sums the two rates and then
  clamps to `0.0`, which produces a hard `p_apply = 0.0` — status immunity for a
  defender at both caps. The multiplicative form cannot go negative and ADR 0068's
  distributional floor (`P_MIN_APPLY`) is the only place a status can be refused.

## Consequences

- `combat_engine` gains `elements` in `tools/arch/registry.json`, which ADR 0069 already
  mandates and which S12's resistance read makes real. `combat` does **not** need it: the
  spine and S12 live in `combat_engine`, and `CombatApi.resolve_hit` reaches them
  through the facade.
- Two new tests: S9-before-S12 (a dead defender takes no status) and S11-before-S12 (a
  leeched hit still applies its status, and the leech reads a pre-status
  `health_regen`).
- `CombatOutcome` gains no status field. S12's result rides `effects[]`, so
  `to_dict()` stays primitives-only (ADR 0038) and a screen renders it unchanged.
- The status layer **cannot** become a second damage formula: S12 writes no health, and
  every damage number in the game still comes from one spine (BL-0195).
- `P_MIN_APPLY`, `RESIST_DIVISOR` and `STATUS_POTENCY_SCALE` are **provisional** — the
  designs' numbers are reasoned guesses, not measurements. They ship as `Proposed`
  data on the `.tres` and are re-tuned by an edit, never by an ADR.
