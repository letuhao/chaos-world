# A body attempt's randomness is one seed drawn at commit and replayed from the record

Generalises to all three cultivation paths. No `core/` or `contracts/` change.

## Status

Accepted.

## Context

A shipped body breakthrough **could not fail**. The facade takes no rng, so
`start_attempt` stored `rng_state = 0` and `resolve_attempt` replayed seed 0, whose first
`randf()` is `0.202272`. The lowest `chance_base` authored anywhere on the 30-realm ladder
is `0.2580` (`primordial_origin.tres:26`). The deviation test is `randf() >= chance`, and
`chance = clamp(chance_base + quality*0.5, 0.05, chance_cap)` — whose floor never binds,
because `chance_base >= 0.2580` everywhere.

So the comparison was false on every realm at every quality. The deviation and recovery
system — a named leg of the acceptance gate — was unreachable in production, and 30 seeds
worth of authored risk was decorative.

The suite was **green**, because `test_body_attempt_survives_the_save.gd` deliberately
asserts only "the invariants that hold whichever way the roll fell, since the facade takes no
generator". That is a weakened assertion, which is worse than no test: it reported the
defect as a property.

## Decision

**One seed is drawn from real entropy at COMMIT and stored in the record; the resolve takes
no generator at all.**

`BodyAttemptRoll` owns it: `seed_for` at commit, `replay` at resolve.

### Why not draw at resolve from the actor's live rng

One line shorter, and wrong. An actor rebuilt from a save has **no live rng**, so the outcome
would be re-rolled rather than resumed — a player could quit to change a result they had
already paid for. That contradicts the entire point of a durable attempt (ADR 0187).

It also made the record a **lie**: `try_breakthrough` passed one rng to *both* halves, so the
commit stored `rng.seed` while the resolve drew from that generator's already-advanced
stream. `test_body_persistence.gd:220-227` passed only because it commits *with* a seed and
resolves *without* one — the diverging shape was untested.

### Why seed 0 is excluded by mask, not by re-drawing

Seed 0 is the one value whose outcome is constant, so excluding it **is** the anti-degeneracy
guarantee. Re-drawing until nonzero is an unbounded retry for a 1-in-2³¹ condition — a loop
that may not terminate, which this repo treats as a defect rather than a style.

## Consequences

- **`P(win) = chance ∈ (0, 0.85]`** on every realm. The upper bound is authored
  (`chance_cap` max 0.85 at `qi_refining`), so failure is possible and success is not
  guaranteed. That is the whole point.
- **The fix generalises and two paths still carry the byte-identical defect**:
  `mind_cultivation/advancement.gd:413` and `:471` carry `rng_state = 0 if rng == null`
  and `generator = rng if rng != null else _replay(committed)`. Recorded for that path; not
  fixed here.
- **A caller's `rng` is now a SEED SOURCE, not the roll's stream.** A caller looping one
  generator replays one roll forever — a trap found in the agent's own fixtures, which now
  re-seed per attempt.
- **`test_r30_is_earned_end_to_end.gd` gained a body walk** (111 → 144 assertions). The
  previous proof drove `Breakthrough` directly and never touched the body's own verb, so it
  proved *core's* ladder was satisfiable and could not bear the terminal-realm leg. Nothing
  it already proved was weakened.
- **A test that asserted "one press resolves it" by coupling to the roll's return value**
  passed only because the roll could not fail. That coupling is a latent flake, not a proof.