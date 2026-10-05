# 0200 Mitigation is a ratio of two magnitudes, so a capped percent may never be authored

- Status: Proposed
- Date: 2026-10-05

## Context

Every defense stat in the game is a PERCENT with a hard cap, and every one of them is a
fixed fraction of the fight that never moves. Measured on the shipped tree:

| Stat | Where | Ceiling | Effect at R30 |
| --- | --- | --- | --- |
| `RESIST_CAP` | `combat_tuning.gd`, read at `qi_damage.gd:174` | 0.75 | qi mitigation stops at 75% forever |
| `MENTAL_DEFENSE_CAP` | `combat_tuning.gd`, read at `mind_damage.gd:11` | 0.6 | 40% of every mind strike always lands |
| `ILLUSION_RESISTANCE_CAP` | `combat_tuning.gd` | 0.8 | OBSCURE has a floor it cannot pass |
| `STATUS_RESISTANCE` | `actor_stats.gd:186`, `minf(0.8, will*0.003)` | 0.8 | needs `will >= 250`; authored `base_will` tops out at 54.9 (DEF-0262) |
| `EVASION` | `actor_stats.gd:184`, `minf(0.6, …)` | 0.6 | a qi build cannot be missed more than 60% of the time |
| `CRIT_CHANCE` | `actor_stats.gd:178`, `minf(0.75, …)` | 0.75 | crit is a solved fraction past R3 |
| `MIN_PENETRATION_RATIO` | `body_damage.gd:15` | 0.10 | 10% of every body strike always lands |

The cause is ASYMMETRIC REALM SCALING, not the percent itself. `realm_scaling.gd:14-22`
scales exactly seven ids — the four attack/defense halves plus hp, qi and stamina. Nothing
scales `element_resistance_<e>` (contributed only by `elements/provider.gd:67` as
`affinity * 0.5 + will * 0.2`) or `status_resistance`. So the attacker's elemental power
rides the 551x ladder while the defender's elemental mitigation stays where it was authored:
by R3 the defense term is noise, and the cap is what a designer reads as "the mitigation
number".

The failure is not that the ceiling is 0.75. It is that a ceiling is an authored constant
bounding an INPUT. Inputs are what must grow: an attacker's offense has to climb 551x, and
anything that cannot climb with it stops mattering.

## Decision

**Mitigation is DERIVED from a pair of magnitudes. The percent is an output and is never
authored.**

```
K = defense_divisor_k · offense            # 0.45, scales with the ATTACKER
m = mitigation_ceiling · D / (K + D)       # mitigation_ceiling = 0.95, authored
damage = offense · (1 - m)
```

`D` is the defender's mitigation MAGNITUDE (`element_defense_<e>`, `status_defense`, or the
mechanism's own defense half). Three properties carry the decision, each of which the
current model cannot have:

1. **Scale-invariant.** Double offense and defense together and `K` doubles with them, so
   the mitigated FRACTION is unchanged. A constant divisor meeting two growing numbers is
   the defect that makes mitigation collapse to zero at depth.
2. **Asymptotic, and the ceiling is a MULTIPLIER not a clamp.** `m` approaches
   `mitigation_ceiling` and never reaches it, so every further point of defense still helps.
   `min(0.95, D/(K+D))` would be the same dead stat one number higher — the exact failure
   this ADR exists to remove.
3. **Never crosses zero, so no negative-damage clamp is needed.** The curve is positive for
   every `D >= 0`.

**Negative defense MIRRORS rather than clamps**, so a body cultivator under a debuff is a
glass cannon and the fiction stays mechanically true:

```
m = mitigation_ceiling · (2 - K / (K + |D|))     # D < 0
```

Both branches give exactly `mitigation_ceiling` at `D == 0`, so the function is continuous
there. Missing this branch is how a glass cannon silently exceeds its own ceiling.

**Penetration is a bounded reciprocal ON THE DEFENSE VALUE**, never a subtraction from the
damage — `body_damage.gd:15` currently subtracts from `gross`, which is dimensionally wrong:

```
D_eff = D · 1 / (1 + max(0, pen) / pierce_scale)
```

Bounded in `(0, 1]`: penetration can push defense arbitrarily close to zero and never grants
negative defense, which would turn mitigation into a second damage source.

**The governing principle: bound the OUTPUT, never the INPUT.** A ratio or a sigmoid output
is naturally inside `(0, 1)` and needs no clamp. An authored percent is a ceiling on an
input, and inputs are what must grow. The status gate follows the same rule:
`status_resistance` becomes `status_defense`, a magnitude feeding a sigmoid over
`(offender_power - defender_defense)` — output bounded, inputs free.

### What dies

`RESIST_CAP` · `MENTAL_DEFENSE_CAP` · `ILLUSION_RESISTANCE_CAP` · the `minf(0.8, …)` on
`STATUS_RESISTANCE` · the `minf(0.6, …)` on `EVASION` · the `minf(0.75, …)` on `CRIT_CHANCE`
· `element_resistance_<e>` as a percent, replaced by `element_defense_<e>` as a magnitude.

### What stays, and why the distinction is not arbitrary

`ATTACK_SPEED` (2.5), `COOLDOWN_REDUCTION` (0.4) and `QI_COST_REDUCTION` (0.5) keep their
ceilings. Those cap DEGENERATE STACKING on axes that do not scale with realm: an unbounded
attack speed is a broken game, not a power-creep problem, and removing those ceilings costs a
player nothing that the ladder would otherwise have given them. "Remove all percent caps" read
literally would delete both classes and the game would ship with instantaneous everything.
The test applied: *a cap on a mitigation or defense axis dies, because that axis must scale;
a cap on a rate axis stays, because rate is not what power creep rides.*

`MIN_PENETRATION_RATIO` survives as body's "this strike is refused" floor, because ADR 0070's
premise is that body is the ONE mechanism allowed a `0.0`.

## Consequences

- `CombatTuning` gains `mitigation_ceiling` (0.95) and `defense_divisor_k` (0.45), and loses
  `resist_cap`. Both are authored DATA, so a balance pass is a `.tres` edit, never a `.gd`
  edit.
- `element_defense_<e>` replaces `element_resistance_<e>`; the ten `ward_*_ward.tres` items
  that author the old id are re-authored against the new one. This is the defect
  `tools/element_coverage.py` already reports as a magnitude-window failure.
- Every resistance-like half moves onto `RealmScaling.SCALED_STATS`, which is what makes the
  mitigation grow WITH the ladder instead of being authored flat against it.
- `contracts/stat.gd`'s `RATE_STATS` loses the ids whose caps die, so a FLAT modifier on them
  becomes legal content. `tests/contracts/test_rate_stats_registration.gd` gates that list and
  must be updated in the same change.
- **Contests must read normalized SHARE, not absolute points** — decided in ADR 0215, not here.
  A sigmoid over `(atk - def)` makes the gap between two actors grow with realm, at which point
  the sigmoid saturates and every contest becomes deterministic at depth — measured in the
  source design as a cycle collapsing from ~65% per arrow to 0/100 by ladder index 300. That is
  a separate regime from mitigation and needs a separate rule; it is load-bearing, because
  without it the magnitudes above still produce a dead ladder.
- Ported from the sibling design's `DivisiveMitigation`; the shapes are identical, the stat
  vocabulary is ours.
