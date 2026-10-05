# 0118 The Mind path's anchor clause is additive to the shared tier gates, never a substitute

- **Status**: accepted
- **Amends**: ADR 0024 (delegation scope), ADR 0058 (consequence note)
- **Closes**: BL-0351

## Context

ADR 0024 decided, in one sentence that was under-read for a long time: *"Tier gates stay
in core. Qi and Body call `Breakthrough.tier_gates_met`. Mind delegates its high-tier
**anchor** requirement to `MindAnchor` instead."* That delegates **one clause**.

`MindBreakthroughCondition._anchor_ready` came to read `tribulation_ok` **and**
`MindAnchor.stage_met` — all four shared gates replaced by one of them — while
`MindAdvancement.resolve_attempt` advanced through the **ungated** `Breakthrough.try_advance`.
ADR 0058 recorded the consequence as a gap, not a decision ("never calls
`Breakthrough.ascension_ok`, so its ascension … never reports complete"), and ADR 0112 named
it as the reason a mutation deleting the shared commit stayed invisible.

Measured on one actor at ladder index 28, with every other requirement paid through
production actions: `tribulation_ok`, `world_ok` and `inside_world_ok` all read **true** —
but `world_ok` and `inside_world_ok` only *incidentally*, satisfied by the central
`WorldAnchor.commit` inside `try_advance` (ADR 0112). **`ascension_ok` was the only genuinely
bypassed gate**, and it is the one that matters.

### The relationship is ORTHOGONAL, measured — not subset, not superset

Into the Seed boundary the shared schedule is **open** and `MindAnchor` **shut**, because a
commit may not reinforce the anchor it gates. Into the Pocket and Inner boundaries the
reverse, because `MindAnchor.required_stage` names `STAGE_NONE` on the tier mind commits on.
The two gate on different artifacts — a **walked ritual and named laws** versus a
**physiological milestone paid with the realm's channel elixir** — so neither can express the
other. Collapsing mind onto the shared schedule would have deleted the reinforcement
requirement. It was not deleted.

## Decision

- **A path's high-tier gate is the shared schedule AND that path's own clause.** Anything a
  path owns is an additional `and`, never a replacement. **A delegation is scoped to the
  clause it names.**
- **Mind keeps `MindAnchor` as its anchor clause.** The anchor a breakthrough commits is that
  attempt's own outcome and cannot be its precondition. That is the one clause the shared
  schedule has no term for, and it is paid separately.
- **Mind advances through `Breakthrough.try_advance_gated`, and re-reads the gates before it
  rolls.** `start` spends the realm pill on the strength of the condition, so a gate checked
  only after the spend bills the player for a breakthrough that never happens. The pre-roll
  re-read leaves the record **cancelled** rather than **failed**, so a stale gate costs no roll
  and no deviation.
- **A refusal leaves the actor exactly as found.** The award and the drain follow the advance,
  as on body and qi — previously the sea drained *before* a gate that could not refuse.
- **A gate is reported in core's own words.** Every path publishes its four shared gates under
  the same keys with core's predicates as values, and the ascent clause is
  `WorldAnchor.ascension_unmet`. The shared implementation of the clause *list* belongs in
  `core/breakthrough.gd`; **three copies of the vocabulary is the ADR 0066 shape this file
  exists to stop.**

## Consequences

- Mind is stopped at R28 by four deliberate `ascend` steps — a real requirement that body and
  qi already met. **That verb had no mind-side caller**, so the screen needed the button body
  already had; until it landed, the gate was visible but not actionable, which is a
  soft-lock rather than a difficulty.
- `tests/modules/mind_cultivation/test_full_traversal.gd` must walk the ascent, or it measures
  a player who cannot finish.
- `tests/core/test_high_tier_traversal.gd` has been playing mind through `try_advance_gated`
  since it was written — **which is why the production divergence survived the suite.** The
  core suite and production disagreed, and the core suite was the more correct of the two.
- The claim is load-bearing on the mind path: deleting the shared `WorldAnchor.commit` turns
  `tests/modules/mind_cultivation/test_mind_shared_tier_gates.gd` **111 assertions red**.