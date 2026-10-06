# 0900 mental_clarity retires: perception carries the mind's offence and will the defence

- Status: Accepted
- Date: 2026-10-07

## Context

`mind_cultivation` declared two base attributes and NEITHER had a content allocator: no
`RaceDef.base_attributes` in `game/data` names `perception` or `mental_clarity`, so ADR
0183 made both read `Stat.WILL` through a fallback on every stock actor. `mental_clarity`
was moved only by one active option (`cult_mental_clarity`) and the four equipped passives
that carried it.

The batch-A vocabulary review (A3) found three clarity names — `sea_clarity` (a stat BL-0163
had already deleted; the truth is the `SeaOfConsciousness.clarity` component), `mind_clarity`
(the live crit-contest offence half, ADR 0215) and `mental_clarity`. The first approved
resolution, "merge it into `sea_clarity`", was measured unimplementable: the target is a
deleted id and a source scan keeps it deleted. A corrected pick (A3a-2) retired the
attribute instead.

## Decision

`mental_clarity` retires. Its reads split by ROLE, not by name:

- **Offence reads → `perception`.** `MENTAL_ATTACK = perception * 3.5`;
  `MIND_TECHNIQUE_POWER = perception * 2.5 * technique_factor * (1 + meridian_power)`;
  every mastery OFFENCE half and `mind_composure_intent` read `perception`, with ADR 0183's
  `will` fallback kept for stock bodies.
- **Defence reads → `will`.** `MENTAL_DEFENSE = will * 2.5`; `ILLUSION_RESISTANCE =
  will * 0.006`; the five non-intent mastery DEFENCE halves keep reading `will`.

A stock body reads `perception == will`, so every stock-actor number is unchanged; only
authored builds move. The id stays DECLARED as a tombstone (the `MIND_AVOIDANCE` pattern);
`cult_mental_clarity` becomes `deprecated` and its four technique carriers
(`passive_clear_mind`, `passive_echo_resonance`, `dual_qi_mind_both_eyes_open`,
`dual_body_mind_unbroken_centre`) merge their grant into `cult_perception`; the presenter
entry is removed; the ledger row becomes `legacy`.

## Consequences

- The mind path now has TWO inputs with distinct jobs: `perception` imposes and answers
  `intent`; `will` refuses. The mastery track's only non-symmetry survives, re-keyed from
  "intent answered by clarity" to "intent answered by perception".
- One recorded claim is retired WITH the attribute: "a perception-based build is not
  automatically the best CC caller". Perception IS the offence attribute now — that is the
  trade the owner chose over renaming the attribute.
- The fixtures that pinned the old formulas were re-keyed in the same change:
  `test_mind_provider` (70.0 / 25.0 / 0.06), `test_mind_power_curve`'s constants, the
  illusion row (`will 200.0 → 1.2`), the mastery intent test, and the two fixtures that
  built the attribute. `test_mind_mastery_streams.gd`'s three unqualified
  `earn_mastery(...)` calls were qualified to `MindStatusApi.earn_mastery` so the suite
  loads again (the stale `mind-mastery-slice` claim is noted; the tree was clean).
- The status-port questionnaire consumes `perception` and `will` as the mind inputs it
  finds; nothing in `docs/backlog.jsonl` is owed by this ADR.
