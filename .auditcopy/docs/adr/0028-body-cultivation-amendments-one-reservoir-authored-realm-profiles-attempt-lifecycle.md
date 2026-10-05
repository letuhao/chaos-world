# 0028 Body cultivation amendments: one reservoir, authored realm profiles, attempt lifecycle

- Status: Accepted
- Date: 2026-10-02
- Supersedes: the per-acupoint reservoir and second-axis parts of ADR 0012/0015; the seed
  contract of ADR 0023

## Context

ADR 0015 gave every acupoint its own `body_essence` pool. ADR 0023 seeded 30 realms but left the
gate values hand-picked, so a realm's entry requirement could sit *above* what one realm of training
produces — `quality_required` outran `quality_target`, and realms from R8 on were unreachable through
the public actions. Breakthrough had no attempt identity: costs were spent and outcomes applied in
one call, so nothing was resumable and nothing could be persisted mid-attempt. There was also no
second realm axis, no separate currency, and no caller in `app/`.

> **Amended by ADR 0034** (resonance mechanism, additive stat-provider rule) and corrected in
> place below: the profile factors are now *read* rather than recomputed, `integrity_target`
> is now the enforced gate, `resonance_rank` and the work fields are now load-bearing, and the
> authored chance bounds replace the comprehension-saturated roll.

## Decision

- **One reservoir.** `Acupoint` owns only `id`, `tier`, `quality`, `blocked`. `body_integrity` is the
  single `ResourcePool`; `AcupointSet` mediates it (`set_pool`, `pool`, `total_capacity`, `current`,
  `is_full`, `fill`, `drain`). There is no second realm axis, currency, or skill tree.
- **Reachable gates.** `quality_required(R)` equals `quality_target(R-1)` exactly, and
  `required_refinement(R)` equals `refinement_cap(R-1)`, so every realm is attainable with one realm
  of training. `test_realm_profile.gd` asserts the invariant for all 30 seeds.
- **The seed is the only source of profile truth.** Each seed carries `power_budget` (P),
  `capacity_factor` (C = P^0.85), `throughput_factor` (F = P^0.40), `technique_factor`
  (T = P^0.55), `work_required`, `acupoint_work`, `meridian_work`, `insight_required`,
  `resonance_rank`, `integrity_target`, `chance_base`, `chance_cap`, and `channel_training`.
  `BodyProvider` and `BodyTraining` load them; neither re-derives a factor from constants.
  **P is a reference budget, never a stat multiplier**: T scales attack, defense, poise, and
  body power; F scales move speed and regeneration; C scales carry capacity.
- **`integrity_target` U(R) is the reservoir gate.** The pool must reach U(R) =
  0.45 + 0.015(R−1), not 100%. This gives the single reservoir a per-realm charge target and
  keeps acupoint quality and pool charge as two separate, independently reported conditions.
- **Insight floor is a gate.** `insight_required` (10 + 6(R−1) + 2(R−1)²) is checked against
  `Stat.COMPREHENSION`. `BodyTraining.meditate` is the only source, so comprehension cannot be
  bought with the realm pill.
- **Risk is authored, not derived from the gate.** Breakthrough chance is
  `clamp(chance_base + average_huyệt quality * 0.5, 0.05, chance_cap)`. It deliberately does
  **not** read `Stat.BREAKTHROUGH_CHANCE`, because that stat is driven by comprehension and
  comprehension is the entry gate: `0.1 + 0.01 * insight_required` exceeded the old 0.95 clamp
  from R5 on, so 26 of 29 attempts were certain successes and the deviation loop could not fire.
  `chance_cap` = 0.95 − 0.008(R−1) (floor 0.70) keeps every realm's failure rate meaningful.
- **Work is priced off T.** `work_required` = round(40 · T); `acupoint_work` and
  `meridian_work` divide it by the huyệt and channel counts the realm owes. `progress_required`
  is the same number, so the enforced gate and the authored budget describe one quantity. The
  earlier `(R−1)^1.45` curve made reward-per-labour peak at R9 and collapse 15× by R30.
  One labour tick is one `cultivate(actor, 1.0)` call.
- **Attempt lifecycle.** `BodyAdvancement.preview` never mutates or advances RNG; `start_attempt`
  validates everything, then consumes the pill once and records an attempt
  (`id`, `path_id`, `source`, `target`, `pill`, `status`) in `actor.get_module_data(&"body_attempt")`;
  `resolve_attempt` applies the outcome and clears it. Only one attempt is active per actor, and the
  attempt survives save/load through `Actor.module_data`.
- **Recoverable failure.** A deviation halves progress, jams a huyệt, tears a channel, and costs
  integrity. The torn channel is the required one the actor trained *deepest* (the old
  `required_meridians[0]` always chose lung), and the jammed huyệt is bound to that same
  meridian, so the wound has one location. Nothing is destroyed permanently:
  `BodyTraining.recover` spends the realm's `recovery_item` to heal the channel and clear the
  blockage on its huyệt.
- **Injury blocks the gate.** The meridian requirement uses `MeridianState.meets(STRENGTHENED)`,
  which honours the recoverable `injured` overlay. Comparing `channel.state` directly let a
  wounded channel pass while silently halving its own bonuses forever — qi and mind both used
  `meets()`, body was the outlier.
- **Milestones grant something.** Training while in a realm completes that realm's milestone and
  grants a once-only physique bonus of `integrity_maximum * 0.02`. Marking the milestone on
  *entry* would make the bonus free. Loading a save restores the marker without re-awarding.
- **No unguarded advance.** Both success paths call `Breakthrough.try_advance_gated`, so the
  ADR 0018–0021 tier gates cannot be side-stepped. It runs before the pool drain, because a full
  pool is itself a condition.
- **Milestones.** `BodyProgress` records realms whose strengthening is complete, so entering a
  realm twice does not repeat its bonus. It persists under `body_progress`.
- **App and UI wiring.** `ActorFactory.with_body_cultivation` is the composition root;
  `scenes/Main.tscn` boots one body cultivator and mounts `BodyCultivationPanel`
  (`src/ui/screens/`). The panel is a pure consumer of the facade — it renders
  `BodyCultivationApi.panel_state()` and calls facade actions only, never module internals.

## Consequences

- `test_full_traversal.gd` walks R1→R30 through cultivate / strengthen / meditate / breakthrough
  only, sweeping RNG seeds and re-preparing after each deviation. It asserts profile completeness,
  preview agreement, one rank step per attempt, and that the milestone belongs to the realm just
  trained in rather than the one just entered.
- `test_breakthrough_attempt.gd` covers the preview/start/resolve lifecycle, milestone grants,
  risk independence from comprehension, and resonance.
- `test_realm_profile.gd` asserts every authored formula *and* the properties that were wrong
  before: reachability of the entry gate, `progress_required == work_required`, a chance ceiling
  below 1.0 at every realm, and reward-per-labour stable within 2× across the ladder.
- `tools cultivation report` prints the whole ladder as the game resolves it, including the
  chance range per realm; `tools cultivation validate` fails when a gate is unreachable, a
  referenced item/recipe/meridian is missing, the gate and budget disagree, or any realm's chance
  ceiling would make the deviation loop unreachable.
- Body-only play remains viable: no qi or mind realm is required to enter any body realm.
- **New huyệt tiers spawn untrained.** A major point created on entering R10, or a celestial one on
  entering R19, arrives at quality 0.5 against a standing requirement that may be higher. This is
  intended: the gate for R+1 covers every point unlocked at or below the current realm, so a fresh
  tier is work to do, not a gift. Spawning a point already at the requirement would delete it.
  The cost is that `average_quality` — and therefore breakthrough chance — dips when a new tier
  joins. That dip is the price of a visible new goal.
- Acupoint capacity is a derived view of the shared pool, not an independently saved balance.
- `Actor.SCHEMA_VERSION` is 3: acupoints, body progress, and the attempt ride in `module_data` so
  `core/` never imports module classes.

## Known gaps this ADR does not close

- **Acquisition is gated on DEF-0022.** Every pill, elixir, and recovery elixir is crafted from a
  gathered herb plus a boss-only guardian core, and no boss/loot runtime exists, so R2+ is
  unobtainable in play. The craft chain is structurally verified; realm-relative *obtainability*
  is unprovable until DEF-0022 lands.
- **Domain families are undecided (DEF-0050).** The content is 30 one-realm domains; the
  10-families-of-3 grouping was specified and never built.
- **Grade taxonomy collapses (DEF-0051).** Body items use 4 of the 6 declared grades.
- **R19+ tier gates have no body-side driver.** `Tribulation.start`/`advance_wave` have no caller
  in `src/`, so the Immortal+ gates are satisfied in tests but not in play.