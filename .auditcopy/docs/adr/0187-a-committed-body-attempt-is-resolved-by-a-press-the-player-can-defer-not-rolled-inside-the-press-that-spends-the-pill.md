# A committed body attempt is resolved by a press the player can defer

Supersedes ADR 0150's open consequence. No `core/` or `contracts/` change.

## Status

Accepted.

## Context

`BodyCultivationApi.begin_breakthrough` / `resolve_breakthrough` are the documented
**durable, save-spanning** half of the breakthrough lifecycle. They had zero production
callers: `attempt_breakthrough` ran both halves inside one call, so no state a player could
produce ever had an attempt in flight. `panel_state.attempt` was permanently `""`, a save
taken mid-attempt was impossible, and the facade's promise that a panel "offers resolve
rather than a fresh breakthrough" was unimplemented.

The fork was real: build the affordance, or delete the claim.

## Decision

**Build the affordance.** Breakthrough is **two presses**: commit an attempt, then resolve
it. The attempt is durable — it survives the save envelope, so a player who quits mid-
attempt resumes the same one.

The affordance rides `panel_state` (`attempt` plus `attempt_outcome`), not a new verb.
`BodyCultivationApi` is verified at **12/12** public methods and a 13th fails `tools arch`,
so this is forced rather than chosen, and it is exactly what ADR 0150 prescribes for a
facade at the cap.

One control serves both halves. They are mutually exclusive by construction —
`KIND_ATTEMPT_IN_FLIGHT` forbids a fresh attempt — so a second button would be dead most of
the time, and a `.tscn` node is not this slice's to add.

## Consequences

- **Breakthrough is now two presses, and that is the cost.** It is the only shape in which a
  committed attempt can outlive its session.
- **`attempt_breakthrough` now has zero production callers.** It remains the transactional
  primitive and the proof that the one-press path still works for a player who never defers.
  A verb kept for its transaction and its tests, not for a caller, is a real cost of this
  shape and is recorded rather than glossed.
- **A null rng now matters.** It degrades to `rng_state = 0`, so every body breakthrough
  rolls the same number — previously invisible, now a shipped player-facing roll. Recorded as
  DEF-0250; the fix is a separate decision because roughly six tests deliberately construct
  an rng-less actor.
- **An audit assertion went red by construction.** `test_failure_branches_reachable.gd`
  asserted zero callers for both halves; that was correct when written and is wrong now.
  It should be inverted to assert the *shape*, so it survives either fork (DEF-0249).
- Rejected: a second Resolve button (better for a tribulation that must fight a wave, but it
  needs a `.tscn` change and one control is better UX); leaving the record committed when the
  trial cannot run (the player is then stuck — breakthrough refused by the lockout, resolve a
  no-op); a `committed: bool` beside `attempt` (a second field for one fact is the drift
  ADR 0150 warns about).