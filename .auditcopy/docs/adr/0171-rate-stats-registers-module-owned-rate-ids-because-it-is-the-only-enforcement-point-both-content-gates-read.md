# 0171 RATE_STATS registers module-owned rate ids, because it is the only enforcement point both content gates read

- Status: Accepted
- Date: 2026-10-04
- Amends: ADR 0022, ADR 0068

## Context

`Stat.RATE_STATS` exists to refuse a FLAT on a rate: `ActorStats._put` resolves
`(base + flat) * (1 + percent)`, so `+10` on a 0..1 baseline means 1000%. ADR 0039 put
every such id there; ADR 0022 removed `damage_reduction` (baseline `0.0`).

It was hand-written over core's ids, and that is where BL-0675 lived. ADR 0071 renamed
`critical_chance`/`dodge_chance` into `mind_focus_chance`/`mind_avoidance`, both rate
baselines, and the registration had nowhere to follow: a `FLAT` on either validated clean
and applied as `(0.05 + 10.0) = 1005%`.

A module cannot fix this itself, and neither can a per-module mirror:

- `CombatStats.RATE_IDS` is the shape a module would use, and ADR 0068 says so. But it is
  the SUBJECT of a shape test, not an enforcement point. No content gate reads it.
- The two gates that DO enforce read `Stat.RATE_STATS` and nothing else:
  `modules/status/status_def.gd:372` (a `StatusDef` FLAT) and `tools/data.py:2085`
  (`_resolve_rate_stats`, a fate FLAT). ADR 0022's "derive membership from the baselines"
  and ADR 0068's "do not add dynamic ids to RATE_STATS" point the same way, and the two
  are only reconcilable if the module-owned set reaches the one list that gates read.

## Decision

- `Stat.RATE_STATS` registers every rate-shaped id that authored content can target, and
  membership is a claim about SHAPE, never about ownership. Nothing in it gives core a
  dial on a module's id.
- A module-owned id is declared as a const in `contracts/stat.gd` as well as in its
  module, because that is the only file `tools/data.py` can resolve a name against. It is
  a second spelling site, so it is CHECKED, not trusted:
  `tests/contracts/test_rate_stats_registration.gd` asserts every registration has a live
  baseline in `res://src`, which is what fails when a rename moves the id.
- `RATE_STATS` stays ONE flat array literal. `tools/data.py:2085` extracts it with
  `\[(.*?)\]`; concatenating two arrays would hide every entry after the first `]` from
  the fate gate.
- Membership is tested against the BASELINE, never against the `unit:` an option
  declares. That field is self-declared and wrong on 13 shipped options: `move_speed`
  (`100.0 + agility * 2.0`), `penetration` (`spirit * 0.5`) and all ten
  `element_resistance_<e>` (`maxf(0.0, affinity * 0.5 + will * 0.2)`) are magnitudes that
  declare `unit: "rate"`. Registering them would refuse legal content.
- Two guards that INFERRED ownership from this list now probe a real `ActorStats`
  instead, because a list can only report what someone remembered to put in it. That is
  the same repair BL-0362 made to the combat guard, where the list comparison passed a
  real `penetration` collision because core's derived ids are in no list at all.

## Consequences

- Registered: the nine module-owned rates reachable from an option target, plus core's
  ten. `mind_focus_chance` is registered though no option targets it yet, because it is
  the id BL-0675 is named for and its omission is the rename evidence.
- `tools data audit`'s fate gate gains them for free: `_resolve_rate_stats` already
  resolves a const name against this file, so no tool change was needed. `_valid_stats`
  also reads this file, so a fate may now name a module stat at all — previously any
  `mind_avoidance` key was refused as an unknown stat.
- The per-module rate set stays the right SHAPE for a shape test (`CombatStats.RATE_IDS`
  and its form), and stays the wrong PLACE for enforcement. A future
  `core.is_rate(id)` that aggregates module-published sets would let both be right; it is
  a `core/` change and is not made here.
- Still open: a PERCENT on a stat whose baseline is identically zero passes every gate
  here and still grants nothing. That is ADR 0022's trap, unchanged.