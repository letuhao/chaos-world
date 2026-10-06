# 0884 the status gate is a flat power-versus-resist contest and parity reads half

- Status: Accepted
- Date: 2026-10-06

## Context

- The owner asked for the full Keepverse status copy, not a minimal variant: the attacker
  half did not exist here at all, and the two defence terms composed multiplicatively
  (`gate * (1 - share) * (1 - elem)`).
- Keepverse's evaluator (`Status/ResistanceEvaluator.cs`) builds `totalPower - totalResist`
  from `status.power.{omni,category,statusId}` against
  `status.resist.{omni,category,statusId}` plus `status.resist.{element}` (the STATUS
  DEF's own tag, never the attacker's), and turns the delta into a chance with a sigmoid
  whose value at parity is exactly `0.5`.
- ADR 0877 locked this tree's trigger shape as the linear clamp; ADR 0200 forbids capping
  an input; ADR 0086 keeps the scope rule for combat-only resistance.

## Decision

- The gate is ONE flat delta over `status_rate_scale`:
  `power = status.power.omni + .<kind> + .<status_id>`;
  `resist = status_defense share [COMBAT only] + elemental_resist + status.resist.<element>
  + .omni + .<kind> + .<status_id>`;
  `p_apply = clampf(0.5 + (power - resist) / (2 * status_rate_scale), 0, 1)`;
  `chance = clampf(gate * p_apply, status_min_apply, 1.0)`.
- PARITY READS HALF, not zero: that is Keepverse's own sigmoid semantics kept on our
  linear clamp. A strict-zero parity would make every shipped status impossible the moment
  its defender held one point of defence, which replaces the feature rather than porting it.
- The category channels use OUR five `StatusDef.KINDS` (`dot`, `stat_modifier`, `control`,
  `amplifier`, `burst`), because that is the vocabulary this tree validates. The SHAPE is
  copied; the nouns are ours.
- Two defence terms are NOT channels: `status_defense` (core's will-derived magnitude
  through its ADR 0200 ratio) is the COMBAT-only dial, and `elemental_resist` (ADR 0069,
  penetration included) is kept — `status.resist.<element>` is the authored stance on top
  of it, because one is computed from `element_defense_<e>` and the other is content.
- `CombatTuning` gains `status_power_prefix` / `status_resist_prefix` (authored strings on
  the `element_power_prefix` pattern — no compile-time edge into `status` or `elements`)
  and `status_rate_scale` (shipped `0.5`; an unmeasured placeholder the balance pass owns).
  A non-positive scale reads parity rather than dividing.
- The request dict gains `kind`, written by `combat_boot._stage_status_request` from the
  def; an absent key simply skips that channel.
- `status_min_apply` is unchanged and is now the ONLY thing between a saturated defence
  total and a hard zero.

## Consequences

- Every status now answers to an attacker half that CONTENT must author: `status.power.*`
  has no producer yet, so the shipped experience reads `gate * (0.5 - share/1.0)` until
  the first `status.power` content lands — the same known-dependency shape ADR 0088
  recorded for `element_power_<e>`.
- ADR 0087's multiplicative composition is superseded FOR THIS GATE; its floor-first,
  never-annihilate principle survives as `status_min_apply`.
- Potency still reads `element_power_<e>` (ADR 0088) — the potency split
  (`status.intensity.*` / `status.duration.*`) is the next slice and supersedes that
  reuse; this ADR does not touch it.
- Tests: `test_status_power_channels.gd` pins the delta arithmetic; the migrated
  `test_status_application.gd`, `test_status_resistance_band.gd` and
  `test_loot_boss_affliction.gd` pin the new readings on the real paths.
