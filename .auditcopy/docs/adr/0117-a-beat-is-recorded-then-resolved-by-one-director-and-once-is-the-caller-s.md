# 0117 A beat is recorded, then resolved by one director, and "once" is the caller's

- **Status**: accepted
- **Amends**: ADR 0114 (a beat is resolved once by one director)
- **Amends**: ADR 0113 (one fact ledger) — the record step now has one intended implementation

## Context

ADR 0114 was accepted with `contracts/beat_sink.gd` and `core/world_beat.gd` present and
**no director**. `BeatSink` had zero implementers and zero callers. `WorldBeat` had zero
production references; production built a `Dictionary`. `EventBeatWriter` recorded beats
from inside the `event` module while consulting nobody, and the only caller of
`QuestApi.advance` in the repository was a test.

ADR 0114's own Context names this failure, citing ADR 0077: an ADR that describes a
director without a director. It happened anyway, and it shipped as live defects —
including `QuestFactReader` reading the ledger at the wrong depth, so **no quest step
could ever be satisfied**, and `QuestState.finish` writing `completed = 0` into a field
every reader tested with `> 0`, so completion was never *once* and `advance()` re-paid on
every call.

`BeatSink` was also **unimplementable as written**, which is why nothing implemented it:
`handles` took one argument, but a beat names nobody and a fact ledger is per-actor. The
first sink widened it to `(beat, actor)` — and a widened signature is not an override of
anything.

## Decision

Every decision in ADR 0114 **stands**. It is amended, not superseded: the beat as a value
object, `BeatSink` as a named contract rather than a dictionary of callables, "once is a
property of the ledger", and "a handler never mutates" all survived contact with the code.
What was wrong was that nobody built it. Superseding a decision that turned out to be
correct, when the actual defect was non-implementation, would destroy the reasoning that
produced it.

- **`BeatSink.handles` / `resolve` take `(beat, context)`.** `context` is the beat's owner,
  typed `Variant` because `contracts/` may not name `core`. It defaults to null, so the base
  stays a usable no-op. Rejected: binding the actor at construction, which hands every sink
  a mutable collaborator and makes "a sink mutates nothing" a promise about a stateful class.
- **`resolve` must carry `claimed` and `reason`, and may carry JSON-safe detail.** A sink that
  could only say "yes" would force the director to re-derive the answer from module internals
  it is forbidden to reach. The director copies detail but never lets a sink overwrite what
  it recorded.
- **The director is `app/beat_director.gd`** — `RefCounted`, not an autoload, not a facade, the
  same shape as `StatusLoop` (ADR 0089). Modules never reach it; `app/` wires sinks into it.
- **Record, then resolve.** A sink proposes against the ledger, so the ledger must already
  carry the beat. Resolving first decides a crossing step against a count that does not yet
  include it. Measured: with the order reversed, a beat whose fact completes a quest step
  does not complete the quest.
- **Recording is not dispatching.** A beat is recorded exactly once whether or not a sink
  claimed it — a fact that happened is true whether or not a handler cared.
- **One beat reaches exactly one decision.** Sinks are consulted in registration order, the
  first claim wins, later sinks are not asked, and a claim is not a veto.

### The director holds no registry of applied occurrence ids

This is the one place I overruled the brief I gave the agent, on its evidence.

I asked it to prove that offering the same beat twice is refused by name. It declined, and
was right. A monotone ledger can answer *how many times*; it can never answer *has this
specific occurrence been counted*. An id registry would be a **session-only second copy of a
truth `WorldFact` already owns**, and would disagree with the ledger after the first
save/load — ADR 0066's failure mode under a new name.

Measured, not asserted: adding such a registry turned **1 assertion red out of 60**, and that
one assertion is the test documenting the cost. Its worst side effect — refusing an
occurrence *after* re-recording its fact, so the ledger double-counts while the report says
`already_fired` — was caught by **nothing**. A guard this invisible is not a guard.

What the director owes a caller instead is the occurrence id in its report, so the caller can
key its own once-check before offering. `WorldBeat.coerce` is the single place a beat is read
from either spelling, because `contracts/` may not name `core` and every sink was otherwise
re-deriving the nesting by hand.

## Consequences

- The contract suite runs against the base **and** every real sink, because a contract suite
  that exercises only the abstract base measures nothing.
- **`event` is not yet on the director, and its ledger writer is duplicated.**
  `event/EventFacts` is a second implementation of `core/WorldFact` over the same
  `world_facts` key, and the two normalisers silently truncate each other: a `WorldFact`
  write deletes `sequence`, an `EventFacts` write deletes `since` — and `since` is what a
  "exactly once" gate reads. Reducing `EventFacts` to a read-only projection is owed and is
  blocked on `event/api.gd` loading at all.
- `EventApi` has **zero production callers**, so no module owns the moment ADR 0114 requires.
  The composition root that calls it is still owed.
- Once a boot path owns a moment, a beat's fate/destiny grant is a call of **the owner of the
  moment**, never the director's (ADR 0114's consequence, unchanged).