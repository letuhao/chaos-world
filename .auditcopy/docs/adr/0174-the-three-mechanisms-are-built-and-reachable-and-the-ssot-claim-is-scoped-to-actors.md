# 0174 The three mechanisms are BUILT and REACHABLE, and the SSOT claim is scoped to actors

- Status: Accepted
- Date: 2026-10-04
- Supersedes: none. ADR 0123's two-model Decision is correct and stands verbatim.
- Amends: ADR 0123's four status bullets; ADR 0133's "single source of truth" scope;
  ADR 0126's "the spine is not adopted" and "nothing binds `BodyDamage`/`MindDamage`";
  ADR 0110's element gate
- Re-measures: ADR 0077 (dead), ADR 0069, ADR 0070, ADR 0071, ADR 0087, ADR 0105
- Settles: ADR 0087, ADR 0105, ADR 0110 and ADR 0126 were `Proposed`; all four shipped.

## Context

Four Accepted ADRs describe the combat program mid-build. Every "not built", "no production
entry point" and "still open and still unbuilt" claim in them is now false, and the two
structural claims are still true. A reader following them re-attempts finished work and
re-opens closed defects. ADR 0123 decided the split — one spine plus one encounter layer,
both ship, neither calls the other — and this ADR does not touch it. What is stale is its
evidence, not its ruling.

## Decision

**The engine is built, wired and reachable. `combat_engine` is the SSOT for damage between
two `Actor`s; the share model remains correct for boss encounters.**

- **`CombatBoot.install` is called from production** (`item_workbench_app.gd:541`) and
  installs BOTH resolvers (`combat_boot.gd:511-512`). The technique screen routes a hit
  through `CombatBoot.resolve_hit` (`item_workbench_app.gd:957-962`); `PlayerAdapter.attack`
  lands its blow through `CombatBoot.strike` -> `duel_blow` -> `resolve_hit`
  (`combat_boot.gd:616`). Both end at `CombatSpine.resolve_hit` (`combat_engine/api.gd:87`).
- **All THREE mechanisms ship and all three are selectable per hit.** `body_damage.gd:2` and
  `mind_damage.gd:2` are `extends DamageMechanism` beside `qi_damage.gd:2`.
  `mechanism_for_hit` (`combat_boot.gd:347`) picks from the ATTACKING TECHNIQUE's path
  (ADR 0161) gated on the attacker's components, and `ctx_builder_for`
  (`combat_boot.gd:871`) carries the authored inputs, so `element_share`, `aim_meridian` and
  `mind_kind` reach `ctx.data` in play.
- **ADR 0069 is CLOSED except for its own two accepted defects.** `element_share` ships
  (`technique_def.gd:127`, authored in 23 `.tres`) and `RESIST_DIVISOR`/`RESIST_CAP`
  (`combat_damage.tres:15-16`). The realm-invariance MULT ships
  (`elements/api.gd:112-122`), proven by `test_qi_damage_realm.gd:16`; the tier-2 mastery
  divisor ships (`elements/provider.gd:47,83`), proven bit-for-bit by
  `test_qi_damage_realm.gd:209,229`. The blend-rejection proof is CONFIRMED and now ASSERTED
  (`test_qi_damage.gd:257-317`): mean `0.950000`, blend span `0.625..1.25` = 2.0x against a
  single element's 3.0x.
- **ADR 0070 and ADR 0071 are BUILT.** Wounds persist at `Actor.SCHEMA_VERSION = 5`
  (`core/actor.gd:22`, ADR 0140) and the three per-tick consequences run from the composition
  root (`status_loop.gd:177,186,190`). `blocked_mult` is `1.6` (`combat_damage.tres:100`), so a
  jam strictly outranks a max-quality point as ADR 0070 requires. `mind_deviation` is a real
  `StatusEffect` (`mind_damage.gd:410`) and the BL-0114 renames shipped (`stat.gd:88-89`).

## Consequences

- **ADR 0133's "SSOT" is true of the actor path and FALSE as a blanket claim.** Boss
  encounters still resolve through `CombatApi.exchange` -> `CombatDamage.resolve_hit`
  (`ui/screens/loot_encounter.gd:239`; 0123 and 0133 both cite `:124`), by ADR 0123's design.
  Reconciling the two is not open; whether the SPINE's numbers need normalising for
  non-boss targets is, and no ADR claims they do.
- **The registry still under-declares the one real edge.** `combat` reads
  `CombatEngineApi.tuning()` (`combat/exchange.gd:336,502`) and `registry.json:34-41` omits
  `combat_engine` from `combat.deps`. Reported, not fixed.
- **STILL OPEN — realm vs authored vitality.** qi grows ~979x R1->R30 against authored boss
  vitality spanning ~20x (40->800); `combat_boot.gd:562-568` measures the engine doing
  14.1% of a boss's pool at R1 and 2032% at R30. CONTENT-side; needs an owner decision.
  qi/body is bounded at 0.59..3.27 and asserted only as a BOUND
  (`test_cross_mechanism_balance.gd:533-543`), never as a constant.
- **STILL OPEN — no authored `named` body aim.** `aim_meridian` ships
  (`technique_def.gd:143`) and zero `.tres` under `game/data/techniques/` sets it, so every
  authored body technique resolves `random`. The export without the content.
- **STILL OPEN — ADR 0071's formula/prose mismatch.** Its formula block writes
  `g = base*(1-mit)*coh*...`, so its "40% always lands" prose is not what the code does:
  `mind_damage.gd:238` is `base * coherence * focused / capacity`, with `mitigation` applied
  at S5 on the effects (`mind_damage.gd:194-207`). The 40% floors the DEFENCE term only
  (`defense_floor`, `mind_damage.gd:269`); coherence runs 1.0 -> 0.5 BELOW it. The shipped
  code is right; ADR 0071's wording still needs an amendment.
- **STILL OPEN — ADR 0069's two accepted defects stand.** `element_resistance_<e>` stays
  realm-flat by decision, and `ElementDefaults.advanced()` still has empty `generates`
  (`default_elements.gd:30-32`): the divisor taxes tier-2 MASTERY, it does not fix a row
  mean.
- **ADR 0071's "never subtracts health" stays qualified by ADR 0162**: a landed mind hit
  pays the shared S8 chip floor. ADR 0087 and ADR 0105 are Accepted in substance — S12 runs
  on the spine (`spine.gd:164-178`, after S11 as it required) AND the exchange applies a
  status (`combat/exchange.gd:327-374`). ADR 0077 is dead; its only live use as a fact is
  ADR 0080:75 ("`combat` is two dead files") where `modules/combat/` is now six `.gd` files.
