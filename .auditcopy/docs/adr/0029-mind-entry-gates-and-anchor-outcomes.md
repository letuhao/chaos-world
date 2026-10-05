# 0029 Mind entry gates are source-realm based and anchors are committed outcomes

- Status: Accepted
- Date: 2026-10-02

## Context

ADR 0024 gave Mind the same seed → prepare → attempt shape as Qi and Body, and it asserted
"channel requirements follow the realm being left" so preparation is always achievable. Two
gates in the shipped code still contradicted that, and both made the ladder untraversable
past the point where they first applied.

First, the entry condition compared the sea against the **target** realm's clarity and purity
targets. Those targets are raised by the target realm's own sea catalyst
(`MindTraining.strengthen_sea`), which can only be used *after* entering that realm, so while
still in realm R−1 the sea caps at R−1's target. Requiring R's target before entering R is
circular: R1 → R2 was unreachable because `strengthen_sea` in R1 maxes clarity at 0.40 while
R2 demanded 0.42.

Second, the high-tier gate required an already-stable `InsideWorld` for every Immortal+ target,
but the Seed anchor is created *by* advancing to R19. Requiring the outcome of the attempt as a
precondition of the same attempt is the same class of bug, and it would have made R18 → R19
unreachable.

Two supporting facts surfaced at the same time. The Mind path gated entry on a comprehension
floor but had no comprehension source at all, so R22's floor of 1110 was unsatisfiable. And
`synchronize` drained the shared `mind_power` pool and refilled it from the value it had just
zeroed, so no stored mind power survived any tick — the reservoir could never fill.

## Decision

- **Entry into R checks R−1's completed milestones; R's own targets are earned after entry.**
  `MindBreakthroughCondition` takes the source realm's profile for clarity, purity and channel
  requirements, and the target profile only for the pill and the progress bar. This makes ADR
  0024's "channel requirements follow the realm being left" hold for the sea as well.
- **Anchors are committed outcomes, never prerequisites.** `MindAnchor` owns the R19–R30
  policy: R19/R22/R25/R28/R30 commit the Seed, Pocket, Inner, Micro and Great anchors on
  success, while R20/R21, R23/R24, R26/R27 and R29 require the anchor an *earlier* realm
  committed. Each requirement therefore references a real prior result, and no tier requires
  its own anchor.
- **Cultivation work is the Mind path's only insight source.** `MindTraining.cultivate`
  converts work into comprehension at `INSIGHT_RATE`, so every authored comprehension floor has
  an attainable source. A threshold that nothing can reach is an invalid gate, not a hard gate.
- **The reservoir keeps a single maximum.** `SeaOfConsciousness.is_full` compares against the
  shared pool's maximum, and `synchronize` only re-derives that maximum. `ResourcePool`
  `.set_maximum` already clamps `current` downward without granting energy, so synchronize no
  longer touches stored mind power at all.
- **A breakthrough is an attempt, not a call.** `MindAdvancement.preview` consumes nothing;
  `start` validates, spends the realm pill exactly once, and persists one `MindAttempt` per actor;
  `resolve_attempt` rolls *that* record into an award or a deviation. A second `start` is refused
  while an attempt is active, and `try_breakthrough` stays as the one-shot wrapper. The record keeps
  the chance it was committed against, so a reloaded attempt resolves as it was paid for.
- **The award is keyed on the attempt, not on progress.** `outcome_granted` on the record is the
  only once-only guard; resolving a granted attempt reports the same result and grants nothing
  more. The previous guarantee was incidental — it fell out of `Breakthrough.try_advance` zeroing
  `state.progress`, which a save/load or a UI turn could not preserve.

## Alternatives rejected

- Keep the target-based gate and grant the sea's targets earlier. This reaches R2 by having the
  R1 profile raise clarity past its own authored target, which discards the authored ladder and
  makes the profile a decoration.
- Use the shared `Breakthrough.tier_gates_met` unchanged for the Mind path. Its `inside_world_ok`
  check is a precondition of an anchor the attempt itself creates, so it cannot express
  "first creation" without a special case per system.
- Add a second insight source or let items grant comprehension. Comprehension is a
  cultivation-earned floor; an item that sells it removes the work the floor exists to gate.

## Consequences

- The full 30-realm Mind ladder is traversable through public actions alone, which
  `tests/modules/mind_cultivation/test_full_traversal.gd` asserts end to end, including that
  R18 → R19 and R27 → R28 have no circular prerequisite and that R30 refuses to advance.
- Mind entry now has one reviewable rule (source-realm milestones) instead of two overlapping
  ones, and `MindAdvancement.preview` reports exactly what the condition enforces.
- Reattaching, syncing, equipping or reloading no longer destroys or grants stored mind power,
  so the reservoir is a real budget rather than a per-tick recomputation.
- The anchor policy is Mind-owned and reads `InsideWorld`/`WorldState`/`AscensionState` through
  core. Core keeps ownership of that state and gained no Mind-typed *fields*: the persisted
  attempt rides as a raw dictionary. Sea serialization is the one exception and predates this
  work -- `Actor.to_dict`/`from_dict` reference `SeaOfConsciousness` directly, matching the
  existing acupoint/body-progress precedent in the same file. `tools arch` does not catch a
  `core/` file importing a module class through a global `class_name`, so that boundary
  rests on review rather than the checker.
- Defensible cost: entry requirements are stated one realm behind, so the UI must show the
  *current* realm's milestones as the preparation targets, not the next realm's.
- `Actor.SCHEMA_VERSION` is 4: the attempt rides in its own `mind_attempt` slot as a raw dictionary
  (core never imports the module's attempt class), and `from_dict` dispatches on the version so a
  v2 payload loads with no sea and no attempt. `tests/modules/mind_cultivation/` covers the
  lifecycle and the round trip; `preview` reports the active attempt id so a UI can show that an
  attempt is already in flight instead of offering a second one.
