# 0875 crit-resist-damage is a zero-baseline share and the hit contest complements evasion

- Status: Accepted
- Date: 2026-10-06

## Context

- ADR 0215 added `CRIT_RESIST_DAMAGE` published as `1.0 + will * 0.004` and registered it in `Stat.RATE_STATS`, copying `CRIT_DAMAGE`'s multiplier shape.
- The consumer subtracts: `CombatSpine._crit_damage` reads `crit_damage * (1 - CRIT_RESIST_DAMAGE)`.
- The same change rewrote `landed_chance` as `accuracy / (accuracy + evasion)` while `CombatStats.contest` answers the zero-sum pair with `0.0`.
- Result: every crit multiplied to zero on every actor, and every stock-pair blow missed at S2. 13 assertions across four `combat_engine` suites failed.

## Decision

- `CRIT_RESIST_DAMAGE` is a SHARE resisted, baseline `will * 0.004` (`0.0` resists nothing, `1.0` refuses the crit). Removed from `Stat.RATE_STATS`: on a `0.0` baseline PERCENT is the ADR 0022 no-op and FLAT is the only legal form.
- `landed_chance` reads the defender's share and complements it: `1.0 - contest_of(EVASION, target, ACCURACY, attacker)`. Identical to the plain ratio whenever the sum is positive; correct at the zero-sum pair (`1.0`, a landed blow).
- Parry, block and crit-CHANCE keep the plain ratio: there `0.0` correctly means the event does not happen.

## Consequences

- `tests/modules/combat_engine`: 6000 passed, 0 failed. No fixture was touched; the previously-red assertions are the tests.
- `tests/contracts/test_rate_stats_registration.gd` derives membership from baseline expressions, so the two halves cannot drift apart again.
- A `1.0` baseline is the correct reading of a MULTIPLIER and a wrong reading of anything subtracted from `1.0`; an id with `RESIST` in its name and a subtraction at its consumer is a share.
