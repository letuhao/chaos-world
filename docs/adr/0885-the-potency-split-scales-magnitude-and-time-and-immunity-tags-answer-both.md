# 0885 the potency split scales magnitude and time and immunity tags answer both

- Status: Accepted
- Date: 2026-10-06

## Context

- ADR 0884 made the status GATE a flat power-vs-resist contest. Keepverse's evaluator has
  a second phase the port had not reached: independent DURATION and INTENSITY potency
  terms on top of the shared delta, plus immunity tags.
- Keepverse's shape (`ResistanceEvaluator.ComputePotencyDelta` / `ComputeNetFactor`):
  `delta = base + attacker(status.{family}.omni + .{category} + .{id}) −
  defender(status.{family}Reduction.omni + .{category} + .{id})`, then
  `net = clamp(1 + delta / NetFactorScale, MinNetFactor, MaxNetFactor)` — linear, `1.0`
  at parity — with `effectiveMagnitude = base * intensityNet` and
  `effectiveDuration = base * durationNet`. Tags: `status.immune.<tag> >= 1` refuses,
  and each `status.immuneReduction.<tag>` multiplies `(1 - reduction)` into BOTH factors.
- The constants live in Keepverse's own tuning file, which is not in this clone. The
  SHAPE is copied; the values here are our placeholders.

## Decision

- Four new channel families, authored-prefix strings on `CombatTuning` and read through
  the same `_channel_total` the gate uses: `status.intensity.` /
  `status.intensityReduction.` and `status.duration.` / `status.durationReduction.`,
  each `omni` + `kind` + `status_id`.
- `net = clampf(1 + delta / status_net_factor_scale, status_min_net_factor,
  status_max_net_factor)`. Shipped: scale `1.0`, min `0.0`, max `3.0` — all placeholders.
  The clamps are OUTPUT bounds (ADR 0200's rule); a non-positive scale reads parity.
- `_written` multiplies the magnitude by the intensity factor and the time by the
  duration factor, and the result row carries both factors for a readout. PARITY IS
  `1.0`, so a request with no split channels authored writes the same status the
  pre-split code wrote — the copy is additive at its baseline, and every existing suite
  keeps measuring what it was.
- The intensity floor refuses BEFORE the roll with the existing `no_potency` reason:
  a status that would land at zero intensity does nothing, which is what refused means.
- Immunity: the request carries `immunity_tags` (writers take them from
  `StatusDef.immunity_tags`, a new defaulted content field); a defender at
  `status.immune.<tag> >= 1.0` refuses with its own named reason, BEFORE the roll; each
  `status.immuneReduction.<tag>` blunts both factors — Keepverse's §6
  "partial immunity scales both axes", never one selectively.
- **The BASE magnitude still reads `element_power_<e>` (ADR 0088's reuse) and the
  request's authored `potency`, and that is a deliberate, recorded incompleteness:**
  retiring the reuse means deciding what a status's authored base IS, and no status
  carries one yet (`magnitude_unit = element_power` is the shipped authoring). The split
  is what makes the new channels real; the base-source decision lands with the content
  wave and is tracked as deferred work, not left implicit.

## Consequences

- `status.power.*`, `status.intensity.*`, `status.duration.*` and the immune families
  all have readers now; none has a producer in shipped content yet, which is the same
  known-dependency shape ADR 0088 recorded for `element_power_<e>`.
- The pre-split status behaviour is bit-for-bit preserved when no split channel is
  authored, so this change cannot silently rebalance the catalogue.
- Tests: `test_status_potency_channels.gd` pins parity, both axes, the reduction floor,
  both immunity halves and the ceiling.
