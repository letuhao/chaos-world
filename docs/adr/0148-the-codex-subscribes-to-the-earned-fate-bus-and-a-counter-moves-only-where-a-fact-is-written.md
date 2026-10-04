# 0148 The codex subscribes to the earned-fate bus, and a counter moves only where a fact is written

- Status: Accepted
- Date: 2026-10-04
- Supersedes in part: ADR 0136 (the bus is observed, not reserved)
- Depends on: ADR 0065 (earn-only), ADR 0134 (the consumer surface), ADR 0093 (signals announce)

> **A note on this file's number.** ADR 0149 carries the same title. Two agents
> independently filed this decision while a third was editing `docs/adr/`, and the tool
> handed out two numbers for one decision. Rather than delete an ADR — which the repo
> forbids once accepted, and which would lose whichever record an agent had already read —
> 0149 is kept as an exact duplicate and this one is the canonical copy. A future agent
> finding either will find the same decision. The ADR-numbering race is itself recorded on
> DEF-0113; the lesson generalises to *any* machine-allocated number in a shared tree.

> **Corrected in place, 2026-10-05: the writer enumeration below was incomplete.** It read
> "every real producer (`CombatFacts`, `ClanFacts`, `SectFacts`, `EventBeatWriter`,
> `CharacterCreationFlow`)" — **five**, and it presented itself as exhaustive. `app/soul_death.gd`
> (ADR 0130's `soul_died`, added by a later change) and `app/item_workbench_app.gd` (the birth's
> `child_born`) are also writers. **The count is EIGHT**:
> `BeatDirector`, `CombatFacts`, `ClanFacts`, `SectFacts`, `EventBeatWriter`,
> `CharacterCreationFlow`, `SoulDeath`, `ItemWorkbenchApp`. Measured 2026-10-05:
> `tests/arch_rules/test_fact_ledger_writers.gd` walks `res://src`, finds eight files whose
> CODE calls `WorldFact.record`, and asserts exact array equality against its
> `KNOWN_WRITERS`. **The decision below is unchanged and is not what was wrong** — the chokepoint
> is still `WorldFact.record`, still for the reason given, and a hook installed in `core` is
> still reached by every one of the eight. What was wrong is the enumeration, and the reason it
> matters is recorded in this ADR's own closing section: an incomplete list here read as an
> exhaustive one, which is the same "negative claim that was never executed" error this file
> was filed about. `ItemWorkbenchApp` is worth naming explicitly because it is a composition
> root rather than a domain module — a reader who assumed writers are domain modules would not
> have gone looking there, which is precisely why it was missed.

## Context

ADR 0136 decided the earned-fate bus was "deliberately reserved and currently unobserved,
because nothing in `game/src` connects to any of them." That was wrong when written, and an
audit caught it: `ui/screens/destiny_screen.gd` subscribes to `fate_earned` and
`destiny_earned` in `_connect_events()` and repaints on both, counting an earn that landed on
another hero rather than painting it onto the wrong ledger. ADR 0136 is kept as the trace.

The same audit found the mirror-image error on the counter side. Work had claimed
`COUNTER_FACTS` was "dispatched from `BeatDirector`, wiring 8 fact-to-counter pairs." The
dispatch existed, and **0 of the 8 rows could fire**: `BeatDirector.offer` has one production
caller, and it offers only `PERIOD_FACT` and `WorldAmbient` roster facts — neither of which
appears in `COUNTER_FACTS`. Every real producer (`CombatFacts`, `ClanFacts`, `SectFacts`,
`EventBeatWriter`, `CharacterCreationFlow`, `SoulDeath`, `ItemWorkbenchApp`) calls
`WorldFact.record` directly.

## Decision

- **The bus is observed by exactly one consumer, the codex.** `fate_earned` and
  `destiny_earned` are consumed; `counter_changed` and `gate_failed` have no `game/src`
  subscriber today. `gate_failed` fires once per *evaluation*, so any consumer that polls
  `gate()` to render a locked row emits one per row per repaint: telemetry, never a
  player-facing refusal.
- **A counter moves where a FACT IS WRITTEN, not where a beat is dispatched.**
  `WorldFact.record` is the single verb that writes the fact ledger — its own docstring says
  so — and every producer reaches it. It is therefore the only chokepoint at which a counter
  can move for all of them without a second dispatcher. **All eight** of them, per the
  correction above; the enumeration is pinned by `tests/arch_rules/test_fact_ledger_writers.gd`
  rather than restated here, which is why that test's `KNOWN_WRITERS` is the list to read.
- **`core/` publishes a hook slot; `app/` installs the destiny dispatch into it.** The hook
  must not make `core/` name `destiny`: `core/` may not depend on `modules/`, and `tools arch`
  enforces it. The direction stays `app/` → `destiny`.
- **The hook fires only on `ok: true`**, so a beat with `amount <= 0`, an empty id or a null
  actor cannot move a counter and cannot lower one.
- **Exactly one dispatch site.** Because the hook already covers the director's own write,
  the director must NOT also call the bridge directly — two calls for one occurrence is a
  double-count, and counters are monotonic and never refundable (ADR 0065), so the error is
  invisible *and* irreversible.

## Consequences

- **The counter verb is live only for facts with a producer.** Three ids in `COUNTER_FACTS`
  (`vigil_broken`, `bound_name_called`, `mountain_circled_once`) have no producer anywhere in
  `game/src` and stay at 0 until their owning module writes them (DEF-0105, DEF-0106).
  `breakthroughs` has no row at all.
- **A `counter` gate can be authored against an unwired id and will read 0 forever.** Nothing
  rejects it today. `data audit` must fail a `counter` gate naming an id with no
  `COUNTER_FACTS` row; that check is owed.
- **`FateDef.counters` is still documentation.** 16 of 17 fates declare it and no code reads
  it, so its claim that declaring a counter "keeps the gate answerable" is false (DEF-0168).
- **The earn-only invariant is unaffected.** The hook moves a counter and announces an earn;
  it never grants, removes or re-grants anything, and `strip()` remains reachable only from
  `apply()`.

## Why this is recorded rather than quietly fixed

ADR 0136's error was a *negative* claim — "nothing connects" — that was never executed, only
read. The lesson generalises: **a claim about what is NOT wired needs executing to be
trusted, exactly as much as a claim about what is.** The audit that caught this one also
caught a deferral asserting nine unwritten quest step facts when six had live writers, and a
facade table listing a method that had been retired at the cap. All three were prose that had
drifted from code while reading as authoritative.