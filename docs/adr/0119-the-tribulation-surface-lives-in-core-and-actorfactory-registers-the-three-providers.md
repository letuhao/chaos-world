# 0119 The tribulation surface lives in core and ActorFactory registers the three providers

- **Status**: accepted
- **Supersedes**: ADR 0103 (two false consequences only; its Decision stands)

## Context

ADR 0103's Consequences close with two claims the code contradicts. Both were written
after its Decision had already been implemented, which is why both are wrong: the
Decision did the very thing the Consequences then denied.

- **`WAVES_BY_TIER`, `WAVE_TOLL`, `PREPARATION_AIDS`, `PREPARATION_FLOOR` and
  `fight_wave` "no longer exist anywhere"** (0103:105-108). They exist, in the place
  ADR 0103's own Decision ordered they go (`core`, "The roll is core's, in one file",
  0103:62-66): `core/tribulation.gd:51,71,81,84,147`.
- **"`ActorFactory` still does not register the three core providers, so
  `test_world_anchor.gd`'s provider readouts stay red"** (0103:102-104). All three are
  registered at `app/actor_factory.gd:55-57`, which is what ADR 0058:55 decided.

So the "forward spec for a core migration" 0103 deferred is not deferred — it shipped,
and `tests/core/test_tribulation_mechanism.gd:67-79` asserts the migrated names are
present, turning a silent revert of `tribulation.gd` red instead of a load warning.

## Decision

- **ADR 0103's Consequences are superseded on both points. Its Decision is unchanged.**
  The tribulation surface is `core`'s and is live; the three providers are registered
  in the composition root; `test_world_anchor.gd`'s provider readouts are not red for
  the reason given.
- **A consequence that denies its own ADR's Decision is a defect, not a caveat.** An ADR
  is read as a map of the tree. "No longer exists anywhere" told the next agent the
  tests referencing it were dead weight to delete, when the surface was load-bearing.

Rejected: *edit 0103's two bullets in place* — accepted ADRs are immutable, and a
corrected claim that never appears in a numbered ADR is indistinguishable from one that
was never checked. Rejected: *treat the surface as stale and delete it* — it is pinned
by a live test and is the only fight implementation.

## Consequences

- Verify with `Select-String -Path game/src/core/tribulation.gd -Pattern
  'WAVES_BY_TIER|WAVE_TOLL|PREPARATION_AIDS|PREPARATION_FLOOR|fight_wave'` and the
  matching pattern on `game/src/app/actor_factory.gd -Pattern 'Provider.new\(\)'`.
- **Still owed, still separate:** ADR 0103's `TribulationFight.endurance` / `_verdict`
  duplicate. Untouched here — that is a `modules/heavenly_tribulation/**` deletion and
  belongs with the tribulation unification, not with a correction of record.