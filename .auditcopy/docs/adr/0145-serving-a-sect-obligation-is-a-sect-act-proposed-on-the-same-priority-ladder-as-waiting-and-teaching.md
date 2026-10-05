# Serving a sect obligation is a sect act proposed on the same priority ladder

Closes DEF-0196. No `core/` change; `InstitutionClaim` is unchanged.

## Status

Accepted.

## Context

`sect` gained a real verb, `SectDuty.serve(actor, periods)`, which pays every open
obligation line and records one `oaths_discharged` per line brought to **zero**. It is
correct, tested and mutation-proven.

It has **no production caller**. `game/src/app/institution_resolver.gd:146` dispatches a
**closed** `match` over `SectAct.VERBS`, and `sect_act.gd:48` reads:

```
const VERBS: Array[StringName] = [VERB_WAIT_OFFICE, VERB_TEACH]
```

So the world settles institutions by waiting for a vacancy and by teaching a lesson. When
neither applies the sect does nothing — and paying a term of duty is never proposed. The
consequence is not "a verb nobody calls", it is that **obligation debt can only ever
accrue**. `join` opens `duty_<sect>` and `instruction_<sect>` lines and nothing ever
discharges them, so `InstitutionClaim.settled()` is permanently false for every member.

That was DEF-0196, and it was a live balance bug before this ADR: a tier that models
obligation and never discharges it.

## Decision

**Serving duty is a third `SectAct` verb, proposed on the same ladder** — not an
`app/`-only intent, and not a default branch.

- `SectAct.VERB_SERVE := "serve_duty"` joins `VERBS`.
- `SectAct.intent` proposes it when the actor **owes something and no vacancy and no lesson
  apply**. It is last on the ladder precisely because waiting for an office and teaching are
  the outcomes a sect actively pursues, while serving a term is what happens when neither
  is open.
- `institution_resolver._resolve` gains the matching `match` arm and calls `SectDuty.serve`.

## Why not the alternatives

**A default branch in `_resolve`.** The comment at `institution_resolver.gd:136-138` says the
verb set is closed on purpose: a default would "silently execute the wrong verb", and both
`tests/arch_rules` and `test_nation_act.gd` read that line. A default is the one shape that
defeats it.

**An `app/`-only intent.** Then `SectAct` would not know duty is servable, and every other
caller of the ladder — the resolver, a headless probe, the UI drive — would need the same
branch repeated. The ladder is the single place that decides what a sect does with a period,
so the proposal belongs there.

**Widening `SectApi` to 13.** It sits at exactly `rules.MAX_FACADE_PUBLIC_METHODS` and
`test_sect_no_power.gd:129` pins the exact list. The repo already answered this at
`institution_resolver.gd:100-104`: when the facade is full, **fold the work into a
component** rather than widen the surface. `SectDuty` is that component, and `app/` naming
it follows the recorded precedent.

## Consequences

- `oaths_discharged` gains a real producer, so the `need: 3` quest gate can open — and
  `tools gate_reach check` turns it from `dead_gate` to satisfied **because the verb becomes
  reachable**, which is the census's whole point (it measures reachability, not declaration).
- Serving is a **proposal**, not an entitlement: a member with a vacancy open still waits,
  and a member who owes nothing gets nothing. The ladder's priority order is the design.
- Three `need: 3` gates were red on a **tool** limitation rather than a missing producer;
  `tools/gate_reach.py` now measures a code-owned producer's ceiling by whether its verb is
  reachable from production code, so an unwired verb stays red and wiring it turns the gate
  green for the real reason.
- The four destiny counters mapped from these facts stay at 0, and this ADR does not fix
  that. `DestinyProjection.on_beat_earned` is reached only from `BeatDirector.offer`, which
  module-owned producers bypass by design. Recorded as its own open item rather than folded
  in here.