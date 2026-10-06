# 0891 the placeholder families have declared bands and the status contest channels are share space

- Status: Accepted
- Date: 2026-10-06

## Context

- DEF-0344: six families ship as UNMEASURED placeholders — `rate_scale` / `refusal_cap`,
  the aptitude matrix coefficients, the grant budgets, the status gate/net scalars, and
  the potency base still reading `element_power_<e>`. The debt says to move each family
  onto a target one change at a time; nothing said what a target IS, and the balance
  report printed nothing about the families a balance pass owns.
- The matrix resolved `status.power.omni` / `status.intensity.omni` /
  `status.resist.omni` in MAGNITUDE mode (ladder span), while the gate and the net
  factors divide the delta by FIXED scales. The ladder spans 551x across the shipped
  realms, so one build's shares read a delta of 0.05 at R1 and ~27 at R30: past
  `status_rate_scale` the gate saturates and the intensity/duration nets clamp to their
  bounds at every realm but the first. The claim in `aptitude_table.tres` that MAGNITUDE
  keeps the contest realm-invariant was wrong — a difference over a fixed scale is not
  invariant just because both sides scale.

## Decision

- Each family gets a declared BAND, printed by `test_cross_mechanism_balance` with an
  `in` / `OUT -- FINDING` verdict. A band is an ENVELOPE: it names the degenerate state
  the family must not reach, so crossing one is visible without play data. The
  within-band retune stays DEF-0344's open work:
  - `rate_scale` `[0.005, 0.05]` — below the stock magnitudes one point saturates;
    above them realistic gaps read under a tenth.
  - `refusal_cap` `[0.5, 0.99]` — a response removes at least half and never all.
  - matrix `k` `[0.001, 0.5]` — an invisible coefficient, or one that takes over a
    channel at full concentration.
  - matrix `share_exponent` / `contest_span` `[0.5, 2.0]`.
  - grant max/min row ratio `[0.5, 2.0]`; grant `technique_points` / `per_realm`
    `[0.1, 1.0]` (a learned technique worth a tenth to all of one realm-step).
  - `status_rate_scale` `[0.1, 1.0]`, `status_net_factor_scale` `[0.25, 4.0]`,
    `status_min_net_factor` `[0.0, 0.5]`, `status_max_net_factor` `[1.0, 10.0]`.
- FAMILY 5 IS MOVED: the three status channels are CONTEST edges. A contest input is a
  SHARE of the build — the same number at every realm — so the fixed scales read a real
  fraction at R1 and stay readable at R30. The ladder remains where it was decided: on
  the base magnitude, `element_power_<e>`.
- FAMILY 6 IS NOT MOVED, and the report states why in its own line: retiring the
  `element_power` reuse needs an authored per-status base, which no content carries
  (`magnitude_unit` is the shipped authoring). That content wave owns the decision.
- The report prints the gate delta for one fixed allocation at the first and last realm:
  the same number twice is the claim, two numbers is the finding.

## Consequences

- `tests/core/test_aptitude_table.gd::test_the_status_contest_channels_do_not_ride_the_ladder`
  pins the mode; the report prints the measurement (`REALM-INVARIANT` / `DRIFTS`).
- The other five families sit inside their declared bands today; DEF-0344 keeps the
  within-band retune and the family-6 content wave.
- A future retune that crosses a bound — or flips a status channel back to MAGNITUDE —
  is a visible finding, not a silent rebalance.
