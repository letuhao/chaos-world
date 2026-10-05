# 0058 High-tier milestones are named artifacts, and an ascension is walked

- Status: Accepted
- Date: 2026-10-03
- Amends: ADR 0032 (anchors committed, not required), ADR 0033 (reachable gates)

## Context

ADR 0032 made the high-tier milestones reachable by committing them on the
breakthrough that produces them. Four things it left behind were storage with
nothing put in them, and two gates could not fail.

1. **The Transcendent gate could not fail.** `app/main.gd:85` hands every player a
   Micro world, `WorldState.is_stable` accepts its default 0.5 against a 0.3
   threshold, and `WorldAnchor._world_met` (`core/world_anchor.gd:116`) read nothing
   else — so `stage_met(28)` and `stage_met(29)` passed at the first realm.
2. **The ascension gate satisfied itself.** `_complete_ascension`
   (`core/world_anchor.gd:99`) walked all three stages in a `while` loop with no
   player action, feeding the very gate (`Breakthrough.ascension_ok`) that the
   breakthrough sits behind.
3. **The law, layer, and ability stores were dead.** `InsideWorld.add_law`,
   `InsideWorld.expand_size`, `WorldState.add_layer`, `WorldState.pay_upkeep`, and
   `AscensionState.add_ability` had no production caller; `pay_upkeep` charged
   nothing, and `AscensionState.comprehension` was written only by its own
   constructor. (`WorldState.add_law` did have one: `WorldApi.add_law`.)
4. **Two providers were never registered.** `AscensionProvider` and
   `InsideWorldProvider` appeared in no composition root, so `ascension_stage`,
   `ascension_comprehension`, and `inside_world_stability` were absent from
   `derived()` on a live actor, before or after a save. `Actor` registers
   `ascension` from its own setter but leaves `inside_world` and `world` as plain
   fields, so the latter two read null even once registered.

## Decision

- **Every committed milestone carries a named artifact, and every gate reads it.**
  Each Immortal tier imprints its own law on the inside world it commits, and
  `stage_met` gates on tier *and* law. The created world is gated on the structure
  layer the Transcendent breakthrough builds plus an `origin_index` stamp naming
  the ladder index that built it; a handed-out bootstrap world has neither. The
  ADR 0032 offset is unchanged — a band requires the milestone committed *before*
  it, never its own.
- **The Transcendent breakthrough begins the ascent; `WorldAnchor.ascend` walks
  it.** `commit(27)` names the dao, grants one ability, and stops. `ascend` takes
  one stage and one dao level per step, four steps to the caps, and refuses a
  fifth. `is_complete` also requires the step count and its comprehension, so a
  hand-written `stage`/`dao_level` cannot open the gate. `stage_met` no longer
  carries an ascent branch: `Breakthrough.ascension_ok` owns that gate, and R30's
  own breakthrough commits the Great world, so a schedule entry there would be
  circular.
- **The repeated cost is the deleted method.** `WorldState.pay_upkeep` is deleted,
  not wired: only `WorldApi.pay_upkeep` can charge upkeep, it re-implements the
  check inline without charging, and it is not in `core`. `add_law`, `add_layer`,
  `expand_size`, `add_ability`, `dao_type`, and `comprehension` all gained the
  `commit` path as their production caller.
- **The three core providers are registered in `ActorFactory`**, and `commit`
  mirrors the two created worlds into `Actor.components`, which is where every
  `StatProvider` reads them.
- **`ascend` and `ascension_unmet` are core entry points**, as ADR 0041 placed the
  tribulation's: no facade serves them, and `ui` may call `core` directly.
  `ascension_unmet` is the preview wording, so a screen reports the rule the gate
  enforces (ADR 0034).

Rejected: *require each tier's own law* — circular by construction, since the
breakthrough that enters R19 is what imprints the Earth law; this is the exact
failure ADR 0032 exists to prevent. Rejected: *let the R30 breakthrough finish the
ascent* — the same circularity, one realm earlier. Rejected: *charge the ascent a
resource* (qi, integrity, an ascension pool) — no pool is carried at the
Transcendent tier by both paths, so the cost would have been a constant.

## Consequences

- `test_world_anchor.gd` proves both directions per band: a bare actor meets no
  band, the legal prior state meets every one, and no commit satisfies its own
  gate. Satisfiability is proved with public actions only — no test writes a rank,
  a world, or an ascension stage to reach a conclusion.
- **Gap owned elsewhere:** `Actor.from_dict` restores `inside_world` and `world`
  without re-mirroring them into `components`, so after a load the two registered
  providers go quiet until the next `commit`. `actor.gd` needs the setter symmetry
  `ascension` already has; until then `ascension_stage` survives a save and the
  other two do not. Unproven — not tested here.
- **Gap owned elsewhere:** nothing in `src` calls `ascend`. The verb the player
  uses belongs to `ui/` or a cultivation facade, neither of which this change could
  touch; `Breakthrough.face_tribulation` is the precedent for that surface
  existing before its caller does.
- `upkeep_rate` now has no payer, and `WorldAnchor.inside_tier` has no caller.
  Both recorded rather than hidden; both are pre-existing or belong to the `world`
  module.
- Mind is untouched — it substitutes `MindAnchor` for `inside_world_ok` and never
  calls `Breakthrough.ascension_ok`, so its ascension still ends at whatever
  `MindAnchor.commit` grants and never reports complete.
- The `while` loop that raises stability to 0.5 in `commit` stays: it floors a
  construction step, not a milestone, and cannot run with a gate open.