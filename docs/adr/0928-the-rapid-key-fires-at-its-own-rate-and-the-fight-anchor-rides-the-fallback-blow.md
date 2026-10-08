# 0928 the rapid key fires at its own rate and the fight anchor rides the fallback blow

- Status: Accepted
- Date: 2026-10-08
- Closes: BL-0933; DEF-0378's retune (its remaining pool-ladder half is DEF-0384)
- Depends on: ADR 0053 (the slot binding), ADR 0055 / 0182 (the technique ladder), ADR 0126

## Context

DEF-0378's ruling fixes the target: a same-realm fight lasts ~60 s at the attacker's
own rate — the heavy blow at ~25 blows / 60 s, and a rapid (right-click) class at
5 hits/s, so 60 s ≥ 300 rapid hits. BL-0933 asks for the rapid key itself.

The re-measurement came first, and it disagreed with the shipped loop twice:

- the census compared one qi hit against the AUTHORED `LootTier.vitality`, a parallel
  stat system the fight never touches — its hits column slid 2.2 → 0.7;
- the live loop held its ~25 blows only because `start_fight` **sized** the opponent's
  pool (`blow x 25`, a `fight_pool` offset), and actor-vs-actor the truth was worse
  than the parallel read: the pools are FLAT (250) at every realm while the fallback
  blow rides the technique ladder (2.7667x), so a deep fight collapsed to **1.6 blows**.

## Decision

- **The rapid key is a third slot kind.** `TechniqueSlots.RAPID`, one at every tier
  (`TechniquePolicy.RAPID_SLOTS`), holding one rapid technique — learn many, equip one.
  `TechniqueDef.rapid` marks the class; a rapid def routes to the key FIRST and alone,
  and a second rapid equip REPLACES the occupant. The published budget becomes
  8/9/10/11.
- **The fight loop reads the technique's own interval, clamped by the loop.**
  `FightLoop.cast_rapid` fires through `TechniqueCasting.activate` (costs, resolver,
  per-technique cooldown, mastery) and the loop's gate reads
  `maxf(def.cooldown, MIN_RAPID_INTERVAL)` — 0.2 s, 5 hits/s, the performance clamp.
  The heavy blow's gate is untouched by a cast, and one clock (`age`) advances both.
- **In a rapid fight the opponent answers on ITS OWN cadence.** `exchange` pairs a
  blow at the anchor's rate, which is fair at ~0.42 blows/s and twelve times unfair at
  5 — so `cast_rapid` spends the opponent's own `_opponent_cooldown`, and the rapid
  class's trade is rate for exposure, not a doubled inbound rate.
- **The anchor rides the fallback blow, not a written pool.** The sizing offset is
  REMOVED: the raw actor pools are the fight's pools, and the loop's fallback blow is
  scaled (`ANCHOR_BLOW_SCALE`, the measured 4.46 blows moved to 25) and normalized
  against the technique ladder so the ratio holds flat at every realm. No pool is
  written to fit — the ruling's "no boss advantage, no duplicated stats".
- **The census measures the real thing**: two same-build `Actor`s, both classes driven
  through the loop's own verbs, asserting the band per rate class.

## Consequences

- **The heavy fight holds at every realm**: 23 blows, R1 → R30, printed by
  `test_damage_vitality_census.gd` (~55 s at the anchor's interval).
- **The rapid class's residual is measured, not hidden**: a rapid art's per-hit rides
  the technique ladder while the pools do not, so its fight shortens 38 s → 22 s across
  the ladder. The census's rapid floor covers the measured drift and its docblock says
  why; reconciling the pools with the ladder is DEF-0384, the one remaining half of the
  ruling's shared-curve retune.
- **The roster is content work, filed**: the key accepts any `rapid` def; the shipped
  arts (one per element, plus manuals, sources and the audit) are DEF-0385.
- **`domain_boot`'s own sizing mirror and the `LootTier` numbers** are the same family
  and are DEF-0384's second half: those tiers are a parallel system this ADR leaves
  standing rather than half-migrating.
