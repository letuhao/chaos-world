# 0151 A refusal names the price it could not pay, by role; the actor under test is the one the app built

- Status: Accepted
- Date: 2026-10-04
- Amends: ADR 0150 (a refusal is named data on the read model), for `mind_cultivation`

## Context

`MindCultivationApi.recover_next` shipped with **zero** callers in `res://src`. The
`mind_<realm>_recovery_elixir` all 30 realms author (ADR 0031) had no way to leave a
player's inventory, and a burn — which blocks the sea's clarity gate — was a
permanent dead end. Nothing reported it:

- Every Mind suite hand-builds an `Actor` and hand-calls `attach_sea`
  (`test_full_traversal.gd`, `mind_gate_probe.gd`, `test_mind_persistence.gd`,
  `test_mind_cultivation_screen.gd`, `test_mind_ascent.gd`). A suite that builds its
  own actor can only report that its own fixture works. The same blind spot hid
  `attach_sea` having **no production caller at all** (BL-0523): no actor the game
  built had a Sea of Consciousness, and 10,186 green assertions called the module
  healthy.
- The second half was worse than dead content. `act_train_next_channel` walked its
  candidates, was refused by each for want of the realm's consumable, and reported
  **"No channel left to train"** — the one sentence that cannot be true, because it
  only reaches that line having found a channel that does not meet the gate.

ADR 0150 already decided the shape: *a refusal a player can reach is named data on
the read model, not a bare bool rendered as one sentence.* Two things were missing to
apply it to mind, and both are decisions.

## Decision

- **A refusal names the price it could not pay, by the realm's authored ROLE** —
  "recovery elixir absent", "channel elixir absent" — never by an item id. Mind's
  facade publishes no elixir id: `summary` carries channels and the gate,
  `preview`'s `costs` carries only the breakthrough pill, and the facade sits at
  `rules.MAX_FACADE_PUBLIC_METHODS`. Restating an id in `ui/` is a second copy of a
  value the seeds own and is free to drift out of step with them; the role is the word
  the authored content and its acquisition are indexed by.
- **The role is forced by elimination, not guessed.** `recover_next` refuses on two
  branches and `train_channel` on four; once the screen has published
  `summary()["channels"][*]["injured"]` in hand, one burn present leaves exactly one
  surviving cause — the elixir. That is the read model answering, which is ADR 0150's
  test, rather than the screen re-deriving the module's rule.
- **The residual gap is recorded, not closed.** Naming the *id* is a facade change
  (a `summary` key, so no 13th verb), and it belongs to whoever owns
  `mind_cultivation/api.gd`. `ui/` may not make it.
- **A cultivation route is proven on the actor the composition root built.** A
  reachability suite navigates the shipped app, asserts the mounted screen is bound
  to `harness.actor` **by identity**, and presses its buttons against that actor. A
  separate structural claim — a production caller for the enrolment verb under
  `src/app/` — catches the drift where every suite still passes because each enrols
  its own fixture.
- **`try_breakthrough` keeps its bare bool.** `test_failure_branches_reachable.gd`
  pins the refusal inventory in both directions, and widening it is a decision about
  the whole cultivation surface, not a screen fix.

## Consequences

- The false message is now impossible: the terminal branch reads a `price` that is
  set only by a candidate the facade actually refused, and the old sentence survives
  only where every candidate already met the gate — where it is true.
- Qi and body still collapse their recovery refusals into "Nothing damaged to
  repair". ADR 0150 names body as its own worst instance; mind is now ahead of both,
  which is a debt on those two screens, not a reason to leave mind wrong.
- The gate this screen reads has a quirk worth knowing: `summary()` reports a
  channel that is not yet unlocked as `injured: true`. Any caller counting burns off
  the read model must filter `state == "unknown"` or it will invoice a hero who has
  never been burned. Recorded, because the facade is not this screen's to change.