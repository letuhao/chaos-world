# 0114 A fact that happens is a beat, and a beat is resolved once by one director

- Status: Accepted
- Date: 2026-10-03
- Depends on: ADR 0113 (one fact ledger)
- Amends: ADR 0085 (a conflict is a declaration and a prize), ADR 0093 (publish an event contract)
- Resolves: BL-0054 (first slice)

## Context

With one ledger (ADR 0113) there is still no rule about *who decides* that a thing happened, and
three existing subsystems already collide on that question:

- `NpcStageDef.advance_after: int` (`npc_stage_def.gd:32`) says a zero stage is advanced "only by
  an explicit call from **the system that owns the story beat**". That system does not exist, and
  `NpcApi.advance_stage` / `NpcApi.tally` have **zero callers**.
- `NationApi.declare_war` / `resolve_conflict` (`nation/api.gd:300,339`) fully implement ADR 0085's
  declaration-with-a-declared-prize, and also have **zero callers**. ADR 0085 explicitly refuses to
  let the political layer own a clock, so someone else must call it.
- `WorldApi.trigger_conflict` (`world/api.gd:208`) is the only verb in the game named "trigger", and
  it is a ten-line stability subtraction with no registry, no conditions and no callbacks.

If a quest module, an event module and a story module each answer "a beat happened" with their own
dispatcher, the repo gets three dispatchers, three notions of "already fired", and three
definitions of "once". ADR 0085 already paid for the arithmetic half of this mistake by refusing
the conflict layer a damage formula; the dispatch half is unpriced.

ADR 0077 is the standing warning: five Accepted ADRs describing a spine, a `DamageMechanism` seam
and a `CombatTuning` resource, and **not one named symbol existed**. An ADR that describes a
director without a director is that failure repeated.

## Decision

**A fact that happens is a beat. A beat is offered to one director, and the director resolves it
exactly once.**

- **`WorldBeat` is a value object in `core/world_beat.gd`**, beside `WorldFact`: a plain dictionary
  is refused, because a beat carries `id`, `fact`, `amount`, `actor_id` and `source`, and a bare
  dictionary is how ADR 0067 refused to model a damage payload.
- **A beat is `{id: StringName, fact: StringName, amount: int, source: String}`** — a *proposal that
  something happened*. It is never itself the record. The ledger is the only truth; a beat is the
  claim about it.
- **`BeatSink` is a `contracts/` interface**, not a module, for the same reason
  `DamageMechanism` is (`contracts/damage_mechanism.gd`): the repo rule is "any script implementing
  a `contracts/` interface must pass the same contract tests", and a `Dictionary` of callables has
  no name to point that at.
- **A director is a `RefCounted` holding a `BeatSink`**, installed into the composition root in
  `app/`. It is **not** an autoload and **not** a module facade: a module may not reach the director
  (that is the ADR 0084/0093 direction — announce, never request), and the director may not reach
  modules' internals.
- **Once is a property of the ledger, not of the beat.** `WorldFactLedger.record()` is monotone, so
  "did this beat already fire" is answerable only by *counting*: a beat with `id == &"killed_boar"`
  and `amount == 1` that has already fired is indistinguishable from one that did not. Therefore
  **a beat's `id` MUST be unique per occurrence** — the caller mints `&"killed_boar@3"` for the
  third boar — and the ledger records occurrence ids under a count. This is the honest cost of
  "once": the caller names the occurrence, not the dispatcher.
- **Resolution is: offer the beat, then let the sink decide.** `director.offer(beat)` walks
  registered `BeatHandler`s in priority order, calls `handles(beat) -> bool`, and the first
  handler that claims it returns an outcome. A claimed beat is recorded; an unclaimed beat is
  recorded too, because a fact that happened is true whether or not a handler cared. **Recording is
  not dispatching** — this is the distinction that keeps the ledger honest.
- **A handler never mutates.** It returns a proposal; the director applies. This is ADR 0067's
  "a mechanism returns a proposal" applied to narrative, and it is what lets a test assert the
  decision without asserting the side effect.
- **No handler owns a clock and no handler owns a module's internals.** Time-driven beats come
  from a caller that owns the moment (DEF-0111); combat-derived beats come from the place combat
  decides (DEF-0105). The director only routes.

## Consequences

- Three zero-caller seams (`NpcApi.advance_stage`, `NpcApi.tally`, `NationApi.resolve_conflict`)
  get **one** caller each, at the one place that owns their decision, instead of three subsystems
  each inventing a dispatcher.
- The `source` field on every beat is the audit trail DEF-0105/0107/0108 ask for: `"combat"`,
  `"quest:<id>"`, `"event:<id>"`. That is exactly the string `DestinyApi.earn_fate(actor, fate_id,
  source)` already accepts, so a fate is granted by the **owner of the moment**, not by the director.
- **The once-rule forces callers to name occurrences**, which is stricter than "fire when X is
  true" and is the price of not keeping a second dispatch ledger. A beat id that repeats is a
  caller bug and the ledger will show it as a count, not a distinct event.
- `core` gains `world_beat.gd`; `contracts` gains `beat_sink.gd`. Neither may reference a module,
  and neither is reachable as a facade, so no registry change is required.
- **A director with zero handlers is not a stub** — it is a recorder. That is the property that lets
  the quest module ship first and the event module wire in later without a rewrite.
- Deferred: the `decision_answered` half of `NpcEvents` (`npc_events.gd:34`) is a *question*
  directed at a consumer, and a beat sink is not that. It stays dead and stays recorded rather than
  being conflated with a beat.