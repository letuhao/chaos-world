# 0149 The codex subscribes to the earned-fate bus, and a counter moves only where a fact is written

- Status: Accepted
- Date: 2026-10-03
- Supersedes in part: ADR 0136 (the bus is observed, not reserved)
- Depends on: ADR 0065 (earn-only), ADR 0134 (the consumer surface), ADR 0093 (signals announce)

> **ADR 0148 carries this same decision and is the canonical copy.** Two agents filed it
> independently while a third was editing `docs/adr/`, and the numbering tool handed out two
> numbers for one decision. Neither file is deleted — an ADR is immutable once accepted, and
> an agent may already have read either. ADR 0149 is kept as an exact duplicate so a reader
> who lands on either number finds the same decision.

> **Corrected in place, 2026-10-05: the writer enumeration below was incomplete.** It read
> "the director, `CombatFacts`, `ClanFacts`, `SectFacts`, `EventBeatWriter`, and
> `CharacterCreationFlow`" — **six**, and it presented itself as exhaustive.
> `app/soul_death.gd` (ADR 0130's `soul_died`) and `app/item_workbench_app.gd` (the birth's
> `child_born`) are also writers. **The count is EIGHT**: `BeatDirector`, `CombatFacts`,
> `ClanFacts`, `SectFacts`, `EventBeatWriter`, `CharacterCreationFlow`, `SoulDeath`,
> `ItemWorkbenchApp`. Measured 2026-10-05: `tests/arch_rules/test_fact_ledger_writers.gd`
> walks `res://src`, finds eight files whose CODE calls `WorldFact.record`, and asserts exact
> array equality against its `KNOWN_WRITERS`. **The decision below is unchanged and is not what
> was wrong** — the chokepoint is still `WorldFact.record`, for the reason given, and a hook
> installed in `core` is still reached by every one of the eight. `ItemWorkbenchApp` is worth
> naming explicitly because it is a composition root rather than a domain module: a reader who
> assumed writers are domain modules would not have looked there. The same correction is
> recorded in the canonical copy, ADR 0148, since this file is kept as its exact duplicate and
> the two must not drift apart again.

## Context

ADR 0136 decided the earned-fate bus was "deliberately reserved and currently unobserved,
because nothing in `game/src` connects to any of them." That was wrong when written, and an
audit caught it: `ui/screens/destiny_screen.gd` subscribes to `fate_earned` and
`destiny_earned` in `_connect_events()` and repaints on both, raising a notice so an earn
that lands on another hero is counted rather than painted onto the wrong ledger. ADR 0136 is
kept as the trace; this one states the contract as the code actually is.

The same audit found the mirror-image error on the counter side. ADR 0136-era work claimed
`COUNTER_FACTS` was "dispatched from `BeatDirector`, wiring 8 fact-to-counter pairs." The
dispatch exists, and **0 of the 8 rows can fire in production.** `BeatDirector.offer` has one
production caller — `app/world_pulse.gd:227` — which offers only `PERIOD_FACT` and
`WorldAmbient` roster facts, and neither appears in `COUNTER_FACTS`. Every real producer
calls `WorldFact.record` directly.

## Decision

- **The bus is observed by exactly one consumer, the codex.** `fate_earned` and
  `destiny_earned` are consumed by `destiny_screen.gd`; `counter_changed` and `gate_failed`
  have no `game/src` subscriber today. `gate_failed` fires once per *evaluation*, so any
  consumer that polls `gate()` to render a locked row emits one per row per repaint: it is a
  telemetry signal, never a player-facing refusal.
- **A counter moves where a FACT IS WRITTEN, not where a beat is dispatched.**
  `WorldFact.record` is the single verb that writes the fact ledger — its own docstring says
  so — and every producer reaches it: the director, `CombatFacts`, `ClanFacts`, `SectFacts`,
  `EventBeatWriter`, `CharacterCreationFlow`, `SoulDeath` and `ItemWorkbenchApp`. **Eight**,
  per the correction above; the enumeration is pinned by
  `tests/arch_rules/test_fact_ledger_writers.gd` rather than restated here. That is therefore
  the only chokepoint at which a counter can be moved for every writer without a second
  dispatcher.
- **`core/` publishes a hook slot; `app/` installs the destiny dispatch into it.** The hook
  must not make `core/` name `destiny` — `core/` may not depend on `modules/` at all, and
  `tools arch` enforces it. The dependency direction stays `app/` → `destiny`.
- **A refused write moves nothing.** The hook fires only on `ok: true`, so a beat with
  `amount <= 0`, an empty id, or a null actor cannot move a counter and cannot lower one.

## Consequences

- **The counter verb is live only for facts with a producer.** Three ids in `COUNTER_FACTS`
  (`vigil_broken`, `bound_name_called`, `mountain_circled_once`) have no producer anywhere in
  `game/src` and stay at 0 until their owning module writes them (DEF-0105, DEF-0106).
- **A `counter` gate can still be authored against an unwired id and will read 0 forever.**
  Nothing rejects it today. `data audit` must fail a `counter` gate naming an id with no
  `COUNTER_FACTS` row; that check is owed and is the next thing to add.
- **`FateDef.counters` is still documentation.** 16 of 17 fates declare it and no code reads
  it, so the field's own claim that declaring a counter "keeps the gate answerable" is false.
  It is recorded rather than fixed here (DEF-0168).
- **The earn-only invariant is unaffected.** The hook moves a counter and announces an earn;
  it never grants, removes, or re-grants anything. `strip()` remains reachable only from
  `apply()`.

## Why this is recorded rather than quietly fixed

ADR 0136's error was a negative claim ("nothing connects") that was never executed, only
read. The lesson generalises: **a claim about what is NOT wired needs to be executed to be
trusted, exactly as much as a claim about what is.** The audit that caught this one also
caught a deferral of mine that asserted 9 unwritten quest step facts when 6 of them had live
writers — the same shape of error, in prose.
