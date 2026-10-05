# An event beat is OFFERED to the director and recorded by whoever claims it

Supersedes nothing. Completes ADR 0114's chain and makes ADR 0117 true rather than
aspirational. Supersedes the DEF-0171 claim that `EventApi.advance` can never have a
production caller.

## Status

Accepted.

## Context

`BeatDirector` exists, is tested, and was instantiated nowhere. An agent wired it at
boot (`app/world_pulse.gd` -> `BeatDirector` -> `QuestBeatHandler` + `EventBeatSink`),
so the plumbing is live. Driving it showed `claimed: 0`: the beats a world event
produces are **never seen by the director at all**.

The cause is a seam that does not exist. `event/api.gd:561` calls
`EventBeatWriter.offer`, which calls `WorldFact.record` directly. The module records
its own beat and never offers it outward. So `EventBeatSink` is registered,
reachable, and decorative.

The naive fix — have the director re-record the beat — is wrong, and provably so:
`WorldFact.record` is monotone, so a second record double-counts. That is why the
seam has to be an *offer*, not a second write.

## Decision

The event module **offers** each beat; it does not record it.

`EventApi` gains one injected `Callable` (the `NpcApi.set_minter` inversion
precedent, `actor_factory.gd:140`), set once from `app/`. At `api.gd:561` the module
calls the offerer when one is registered and falls back to its own
`EventBeatWriter.offer` when none is. The fallback is deliberate: the module's own
suites drive it without a director present, and must stay green.

`WorldPulse` therefore claims each beat exactly once, and `EventBeatSink` stops being
decorated.

## Consequences

- **ADR 0117 becomes true.** "Recorded then resolved by one director" was aspirational
  while the module recorded directly; after this, exactly one director resolves each
  beat.
- **No occurrence-id registry is introduced.** That is the constraint that makes this
  cheap: the offer is fire-and-forget and idempotent by construction, because only
  the claiming path records.
- **A new seam is a new failure mode.** If the offerer is registered but its sink
  declines, the beat is lost. The module's fallback covers the un-registered case, not
  the declined case; the director's contract must be that it always dispatches every
  offer to at least one sink.
- **`EventApi.attach` was the wrong integration surface** and is not the seam. It
  writes an empty ledger and grants nothing.
- Still open afterwards: no player-facing affordance calls `advance_one_period()` or
  reads `world_summary()`, so the world tick is reachable from the composition root and
  from nothing else. `ui/` needs a route and a panel.
