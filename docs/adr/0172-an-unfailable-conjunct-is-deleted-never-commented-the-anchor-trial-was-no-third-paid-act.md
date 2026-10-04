# 0172 An unfailable conjunct is deleted, never commented: the anchor trial was no third paid act

- Status: Accepted
- Date: 2026-10-04
- Closes: BL-0141
- Amends: ADR 0115 (a commit must never reinforce the anchor it creates), ADR 0024
  (delegation scope)

## Context

`InsideWorld.anchor_trial_passed` was a conjunct of `MindAnchor._inside_ok` that no
legal actor could make false. Both commits stamped it on the line after
`create_anchor()` — `core/world_anchor.gd:169` and
`modules/mind_cultivation/anchor.gd:160` — so `anchor_created` implied it, and
`from_dict` was its only other writer. Two things were untrue at once: the conjunct
constrained nothing, and the shortfall string it guarded,
`"%s anchor trial not passed"`, was unreachable by any player.

ADR 0115 and ADR 0118 already say what the anchor boundary costs. A commit creates
and **never reinforces**; reinforcement is the one clause paid separately, with the
realm's channel elixir, and ADR 0142 fixed the milestone as
`inside_world.anchor_strengthened` alone. Nothing in ADR 0024, 0029, 0115, 0118 or
0142 asks for a second paid act, and no authored content or verb exists for one.

The same commit also carried a `while` convergence loop raising stability toward
`is_stable`'s threshold. Its guard was unsatisfiable when written: an `InsideWorld`
is constructed at exactly the threshold, and no writer anywhere in `res://src` lowers
one (`modules/world/api.gd` lowers a **created** world, which is why
`_commit_created_world` still needs its own loop). So the loop never ran.

## Decision

- **Deleted:** the `anchor_trial_passed` field, `pass_anchor_trial()`, its two call
  sites, its conjunct in `_inside_ok`, and the shortfall branch. Also
  `InsideWorld.anchor_ready()`, which had no caller in `src` or `tests` and read the
  removed field; keeping it would have left an uncalled gate missing the tier and
  stability terms — the ADR 0066 second copy.
- **Kept:** `strengthen_anchor()`'s own `improve_stability(0.1)`. ADR 0142 calls
  raising stability there a genuine unpriced gap, and that verb is live.
- **An unfailable conjunct is deleted, not annotated.** The honest forms are removing
  the term or making it real; a comment explaining why a term cannot fail is still a
  lie in a conjunction.

## The save schema

`InsideWorld.to_dict` wrote the key, so this is a payload change. `Actor.SCHEMA_VERSION`
stays **5**. A bump is for a slot a version *gained* (ADR 0037's attempt, ADR 0140's
wounds); this removes a field that carried no reachable state. An older payload's key
is **ignored, not refused** — `Actor.from_dict`'s own stated rule for every key its
schema dropped. Refusing would be worse than the defect it replaced: every existing
save discarded to protect a boolean nothing read. `SaveMigrate` is not involved, and
must not be: ADR 0128 states a migration must never rewrite an actor payload.
`tests/core/test_no_anchor_trial.gd` asserts both directions, including through
`Actor.to_dict` / `from_dict`.

## Consequences

- `tests/core/test_no_anchor_trial.gd` guards it. **Restoring the conjunct is
  invisible to behaviour** — it changes nothing any actor can do — so the guard is
  mostly SOURCE-reading, like `tests/core/test_realm_rate.gd`, and every scan carries
  an unconditional liveness term. Mutation-proven: restoring the conjunct reads
  `Results: 3647 passed, 7 failed`; restoring the string `3645 passed, 9 failed`;
  restoring the stability loop `3653 passed, 1 failed`.
- The `describe_stage` wording drops "trialled". Nothing asserts the literal.
- `modules/mind_cultivation/training.gd:282` still says a commit "creates, trialls and
  stabilises". Stale prose, recorded rather than edited — not this change's file.
