# 0215 A contest is a ratio of two shares, so no realm gap can make a god certain

- Status: Proposed
- Date: 2026-10-05

## Context

ADR 0200 removes the capped percent from **mitigation**. It does not, and cannot, fix the
**rate** contests — hit, crit, and status-apply — because those are a different kind of
number and fail differently.

The shipped rate contests are absolute differences with a constant divisor:
`actor_stats.gd:178` caps `CRIT_CHANCE` at 0.75, `:184` caps `EVASION` at 0.6, and
`combat_tuning.gd`'s `status_gate_chance` gates the whole status application. The old design
in `chaos-backend-service/docs/combat-core/02_Damage_System_Design.md:153` used the same
shape — `p_parry = sigmoid(scale * (parry_rate_def - parry_break_att))` — with `scale` a
constant.

Deleting the caps does not fix that. With a constant divisor and a difference that grows with
the ladder, the sigmoid **saturates**: once the gap exceeds a few multiples of `scale`, every
roll is a certainty. A R30 cultivator against a R3 one lands every hit, crits every hit and
applies every status, because nothing in the formula can express "faster than the eye".

That is the defect, and it is worse than the capped percent it replaced. A cap at least leaves
a sliver of contest; saturation removes the contest entirely while leaving the numbers looking
reasonable. The source design measured exactly this collapse: a build cycle that held near 65%
per arrow at ladder index 100 fell to 0/100 by index 300, and the fix was to make contests read
a **normalized share** rather than an absolute count.

## Decision

**A rate contest is a RATIO of two uncapped magnitudes. Neither side is a percent, and no
absolute difference of the same quantity ever enters the formula.**

```
p = offense_rate / (offense_rate + defense_rate)
```

Both halves are unbounded magnitudes — `CRIT_CHANCE` with `CRIT_RESIST`, `ACCURACY` with
`EVASION`, `MIND_CLARITY` with `MIND_VEIL`, `PARRY_RATE` with `PARRY_BREAK`. Four properties
follow, and each replaces something that is currently wrong:

1. **It cannot saturate.** `p` is strictly inside `(0, 1)` for every finite pair, so a
   stronger attacker moves it toward 1 asymptotically and never arrives. Doubling both halves
   leaves it **exactly** unchanged, which is what makes a contest mean the same thing at R3
   and at R30.
2. **Neither half needs a cap**, so `minf(0.75, …)` and `minf(0.6, …)` are deleted rather
   than re-tuned. A cap on a contest half is the ADR 0200 defect in its second uniform: the
   defender's ceiling loses by construction as the ladder rises.
3. **At parity every actor sits at 0.5**, so a realm gap alone grants nothing. Two actors of
   equal investment contest evenly at every depth; only the *allocation* differs. This is
   what stops a god from being unable to miss a mortal — not a nerf, but the absence of a
   term that would make certainty the default.
4. **There is no scale constant to retune**, which removes the one dial that was silently
   making contests more or less decisive per mechanic.

The sigmoid is not deleted, it is **demoted**: where a designer wants a decisive contest that
approaches the ratio's reading, `sigmoid(k · (offense - defense) / (offense + defense))` is
available, and the `· (o + d)` denominator is what keeps it scale-free. A bare sigmoid over
`(o - d)` is the defect this exists to remove and must not be reintroduced.

**This is a rate decision and does not touch magnitudes.** Damage and mitigation stay on ADR
0200's divisive curve; only hit/crit/status-apply/avoidance move to the ratio.

## Consequences

- `CRIT_CHANCE`, `EVASION`, `MIND_FOCUS_CHANCE`, `MIND_AVOIDANCE` and `ILLUSION_RESISTANCE`
  become unbounded magnitudes with a named counterpart each. Every `minf(...)` cap on them
  goes.
- New stat ids: `CRIT_RESIST`, `CRIT_RESIST_DAMAGE`, `ACCURACY`, `MIND_VEIL`, plus the
  `MIND_CLARITY` offense half. Each ships in the same change as its counterpart — the yin-yang
  rule in `AGENTS.md` makes a half without a partner a defect, not a pending item.
- `contracts/stat.gd`'s `RATE_STATS` is the gate on this change and must be updated in the
  same commit; `tests/contracts/test_rate_stats_registration.gd` pins that list.
- Per-element crit is a **suffixed** variant of the same pair (`element_crit_<e>` /
  `element_crit_resist_<e>`), generated from the element table by prefix, never hand-listed —
  a hand list is how a new element silently loses its crit channels.
- **The realm gap is now expressed only through magnitudes.** Damage and mitigation carry it.
  A stronger cultivator hits harder, not more surely. That is the intended reading of power
  in this game and it is a deliberate change from a design where realm bought accuracy.
- `element_coverage`'s assertion that exactly one status per element claims `on_landed_blow`
  is unaffected; this ADR adds no producers.