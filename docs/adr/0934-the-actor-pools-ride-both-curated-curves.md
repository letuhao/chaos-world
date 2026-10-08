# 0934 the actor pools ride both curated curves

- Status: Accepted
- Date: 2026-10-08
- Closes: DEF-0384
- Depends on: ADR 0001/0005 (the realm multiplier), ADR 0055 (the technique ladder), ADR 0200 (magnitudes ride the ladder), ADR 0928 (the anchor's retune), ADR 0932 (the mastery bond)

## Context

DEF-0378's retune left one measured half open. A fight's length is a pool divided by a
per-hit, and the two sides drew from different curves: a technique's per-hit rides TWO
authored ladders — `realm.power` through the actor's scaled attack, and the technique
ladder (`TechniqueMagnitudeTable`, up to 2.7667x, S1's gate) — while the three actor
pools rode `realm.power` alone. The actor-vs-actor census measured the result: the heavy
class held ~23 blows R1→R30 only because `FightLoop._bare_swing` DIVIDED the ladder back
out of its fallback blow, and a rapid art, which cannot divide anything, shortened from
~38 s at R1 to ~22 s at R30.

The ruling also suspected qi_damage's elemental term of being ladder-free. Re-reading the
seam showed it is not: `AttackContext.magnitude` is written from `CombatSpine.base_damage`,
so BOTH of the mechanism's terms already ride the ladder exactly once, and that item is a
pin rather than a fix.

## Decision

- **The three POOL magnitudes ride both curves.** `RealmScaling.apply` writes
  `MAX_HEALTH` / `MAX_QI` / `MAX_STAMINA` a `MULT` of
  `realm.power * TechniqueMagnitudeTable.factor(realm.id)`; the other five scaled stats
  keep `realm.power` alone. The ladder must NOT land on the attack stats: it is already on
  the magnitude side of the ratio, and putting it on both sides would count one realm's
  progress twice. `POOL_STATS` and `SCALED_STATS` are the two named lists.
- **The loop's per-realm normalization is DELETED.** `FightLoop._bare_swing` authors
  `BARE_SWING_MAGNITUDE * ANCHOR_BLOW_SCALE` and lets S1 gate it like every technique;
  `ANCHOR_BLOW_SCALE` alone sets the level (the 4.46-measured blows put back at 25).
- **The census measures the production build.** Its fixture calls
  `ActorFactory.refresh_build` after the paths exist — the same verb a restore funnels
  through — so the printed pools and attacks are the scaled ones, and both rate classes
  assert the SAME 0.5–2.0 band of the sixty-second anchor (the rapid class's extra 0.3
  floor is gone).
- **A provider contribution for a core-owned stat is an ADDITION, applied once.**
  Measuring the census exposed a second double-application: `BodyProvider` re-emitted
  `context.value(id) + bonus` for the four core-owned ids it shapes, and
  `ActorStats._ensure_providers` then multiplied by the modifier bucket ON TOP of a value
  that already contained it — so under `RealmScaling` a body actor's physical attack and
  defense scaled **power²** while its pools scaled power¹ (probe: 40 at R1 → 548.1 at
  spirit_sea → 12,174,466 at the top). The provider now contributes its BONUS, and
  `_ensure_providers` adds a contribution for an id core itself computes
  (`_derived.has(id)`) to the core pass's bucketed figure, with the bucket on the bonus
  once and the flats not re-applied.
- **A MINT ends FULL at its realm's capacity.** The pools are created before any realm
  exists and `sync_core` only CLAMPS `current` (ADR 0025's no-free-heal rule), so a body
  enrolled at R30 entered play at `250 / 381425` — the census's own probe — and the first
  blow ended the fight. `ActorPools.refill_core` / `Actor.refill_core_resources` fill to
  the current maximum, and every public enrolment verb ends on
  `ActorFactory._finish_mint` (`RealmScaling.apply` then the fill). Create-path only: a
  restore comes through `_attach_*` and keeps its saved `current`, and an equip never
  refills.
- **An aptitude edge whose consumer has a FIXED SCALE is CONTEST, never MAGNITUDE.**
  Two rows were ladder magnitudes and both saturated at depth:
  `damage_reduction` (clamped to `damage_reduction_cap`; measured 0.1425 → 2.2978 across
  R21..R30, the blow a defender takes falling to ×0.10) and `amplification` (divided by
  the constant `amp_scale` at S7; with the first corrected, it overshot to a 9-blow
  fight). Both are CONTEST now, with the structural pin in `test_aptitude_table`.
- **Item (b) is pinned, not changed**: `test_qi_damage_realm` asserts the mechanism's
  `magnitude` equals `100 * ladder` at the top realm, so a future mechanism that rebuilt
  a raw magnitude from `technique.magnitude` fails at the seam. The stale
  `AttackContext` docblock ("S1 rate gate (`RealmRate.factor`)") is corrected to the
  ladder gate that actually gates it.

## Consequences

- **The census is FLAT**: 23 heavy blows and 192 rapid hits at every sampled realm,
  R1 → R30, with both classes asserting the same 0.5–2.0 band of the sixty-second
  anchor — the ruling's "exact" target, measured (`test_damage_vitality_census.gd`,
  17/0).
- The absolute pools grow by up to 2.7667x more across the ladder than they did. Nothing
  outside `RealmScaling` reads the pools as an authored constant — both curves are
  authored data (ADR 0055), one file each.
- **The parallel systems reconcile in the same program wave** (DEF-0384(e)):
  `domain_boot`'s survivability offset and the authored `LootTier.vitality` band numbers
  were sized against the old flat pools, so they are re-derived from the actor formula
  rather than left disagreeing with the fight the census measures.
