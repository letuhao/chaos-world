# 0103 The ascent is walked and the tribulation is fought

- Status: Accepted
- Date: 2026-10-03
- Amends: ADR 0058 (walked ascent), ADR 0041 (tribulation durability), ADR 0044 (preview and execute)

## Context

Two entry points reached the top of the ladder and neither had been reviewed as a
pair. `WorldAnchor.ascend(actor)` walks the Transcendent ascent; `Breakthrough
.face_tribulation(actor, path_id, rng)` descends a heavenly tribulation. Both were
uncommitted work destroyed together by a bulk revert, which is the signature of two
things coupled by accident rather than by design: they were both named "the verb
that moves you up", and nobody had said which ladder either one walks.

They walk different ladders, and that is the whole disagreement this settles.

- `ascend` walks the four steps of one artifact — `AscensionState`, carried on the
  actor, owned by no path.
- `face_tribulation` walks the waves of one fight, for one realm, on the single
  `actor.tribulation` slot.
- Neither walks the realm ladder. `Breakthrough.try_advance` does, and
  `Breakthrough.tier_gates_met` is the one gate both feed.

Three defects made the pair unusable rather than merely undecided.

- `WorldAnchor._complete_ascension` finished the ascent inside `commit(27)`, feeding
  the very gate (`Breakthrough.ascension_ok`) the breakthrough sits behind (ADR 0058).
- `_commit_created_world` raised stability by a fixed `+0.2`. A step is not a
  construction: a created world destabilised below `WorldState.STABILITY_THRESHOLD` is
  promoted past it and can never gate R29 again, because no later commit exists for
  R29 — the tier whose gate this milestone is. A traversal then stalls at R28 and
  trips its guard, which is the runaway-loop shape AGENTS.md forbids.
- Nothing in `src/` calls `ascend`, so R29 and R30 are unreachable in play on the two
  paths that read `ascension_ok`. ADR 0058 recorded that gap and could not close it:
  the verb belongs to a path facade or `ui/`, and its change touched neither.

## Decision

- **`ascend` is a shared, path-agnostic verb on a shared artifact.** It asks no path
  anything, because there is nothing to ask: the ascent has one owner and every path
  carries the same `AscensionState`. It never gates a realm — `Breakthrough
  .ascension_ok` owns that gate — and never walks the ladder. It takes one stage, one
  dao level and one step's comprehension per call, and refuses a fifth, so a
  `while ascend(actor)` terminates on the state and not on a caller's bound.
  `commit(27)` begins the ascent (names the dao, grants one ability) and walks no
  step; `commit(29)` grants its ability and walks none either.
- **A committed milestone CONVERGES stability to the threshold; it does not take a
  step toward it.** Same rule as the inside world, same reason: the commit's contract
  is "this exists and is stable", and a fixed increment satisfies that only when the
  input already nearly did. It is also idempotent, because an already-stable world
  takes zero steps.
- **`face_tribulation` stays in `core`, beside `tribulation_ok`** (ADR 0041's
  placement: `ui` may call `core`, and no facade serves a mechanic shared by three
  paths). It is path-SCOPED — "is THIS path owed a fight" — because the slot holds one
  record and a hero with two paths past the tier owes the lower gate first. It reads
  the gate and never writes it.
- **The call that descends never opens the gate.** The return is the gate as it stood
  *before* the call, so a survivor is opened by the *next* attempt. Without that, one
  press would win the fight and spend the reward in a single step, and a loop over the
  verb would report success on the wave that earned the win.
- **The roll is core's, in one file.** `TribulationEndurance` is the single answer to
  "how often does this actor survive a tribulation", for the reason ADR 0066 gave
  `RealmRate`: `core` cannot reach the `heavenly_tribulation` module, so a roll owned
  only there is unreachable from the gate that reads it. Its five constants are
  `TribulationFight`'s, unchanged.
- **The record persists on the actor with its verdict** (ADR 0041). An unfinished
  fight resumes on the wave and at the rating it stopped at; a decided win survives a
  save; a decided loss is REPLACED by the next attempt, so the same realm can be
  re-fought.
- **A tribulation failure costs the body and cannot strand it.** `_apply_failure`
  damages meridians, the dantian and the dao heart, and jams nothing: an acupoint is
  never marked by this path, so a lost fight cannot inherit a recovery rule the actor
  cannot currently reach.

Rejected: *each path owns its own ascension* — the ascent is one artifact on the
actor; three copies would be the ADR 0066 failure and would leave `actor.ascension`
meaning three things. Rejected: *`ascend` inside `Breakthrough`* — it owns no realm,
so putting it beside the ladder's only mover is the coupling that destroyed it.
Rejected: *let `commit(27)` finish the ascent* — circular, one realm earlier than the
defect ADR 0058 killed. Rejected: *put the roll in a module and inject it* — the
composition root that would inject it is `app/`, and a gate that is shut until someone
wires a seam is the unopenable gate this whole slice exists to remove.

## Consequences

- `tests/core/test_high_tier_traversal.gd` walks R1→R30 on all three path ids using
  only shipped verbs, and asserts per path that all twelve high-tier transitions
  started with the gate shut and earned it, and that R30 refuses every entry point.
- `WorldAnchor.ascension_unmet` is the preview wording, so a screen reports the
  shortfall instead of restating the rule (ADR 0044).
- **Obligation, not done:** `TribulationFight.endurance` and `_verdict` are now a
  second copy of `TribulationEndurance`. Their own file says they were written to be
  replaced by a core that owns the roll, so the deletion is owed and needs an owner of
  `src/modules/heavenly_tribulation/**`. Nothing enforces it: no gate can see a
  duplicate.
- **Blocking dependency, outside this change:** nothing calls `WorldAnchor.ascend`, so
  `tests/modules/body_cultivation/test_full_traversal.gd` stops at R28→R29 and reports
  `Immortal tier gates not met (tribulation, inside world, ascension)`. The qi and
  mind traversals pass because the qi's traversal walks the ascent and Mind substitutes
  `MindAnchor`. Closing it means an `ascend` verb on a path facade or a UI screen.
- `WorldState` gained `origin_index`, `STRUCTURE_LAYER` and `get_layer`, and
  `ActorFactory` still does not register the three core providers, so
  `test_world_anchor.gd`'s provider readouts stay red.
- `tests/core/test_tribulation_fight.gd` and `test_tribulation_once.gd` still name a
  `Tribulation` surface (`WAVES_BY_TIER`, `WAVE_TOLL`, `PREPARATION_*`,
  `fight_wave`) that no longer exists anywhere. That is a forward spec for a core
  migration of the roll, not this slice's contract, and it is left as found.