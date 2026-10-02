# 0041 A tribulation opens a gate only by being decided, and a decided win is durable

- Status: Accepted
- Date: 2026-10-02
- Amends: ADR 0020 (tribulation phases), ADR 0032 (realm binding)
- Resolves: DEF-0052

## Context

ADR 0032 bound a tribulation to the realm it was fought for, and ADR 0020 gave it four phases
ending in `AFTERMATH`. Neither said what *counts* as having passed, and the audit behind DEF-0052
found that nothing outside a test could start a fight at all — so the rule had never been exercised
by play.

Supplying the missing entry points (`Breakthrough.begin_tribulation` / `advance_tribulation` /
`resolve_tribulation` / `cancel_tribulation`, beside the existing `tribulation_ok`) exposed two
defects that the phase machine alone had hidden:

- **Reaching the last phase was indistinguishable from surviving.** `tribulation_ok` asked
  `is_complete()`, which is just "phase == AFTERMATH". A fight run to its end but never decided
  opened the gate, so the player advanced through R19+ without ever having survived anything, and
  without `_apply_failure` — the only code that applies defeat consequences — ever running.
- **A survivor could not survive a save.** `apply_result` set `actor.tribulation = null`. That was
  reasonable while the record held no verdict, but once it *was* the verdict, resolving the fight
  destroyed the only proof the gate had been earned. Save and reload silently re-closed it.

## Decision

- **A tribulation carries an explicit `outcome`:** `unresolved`, `survived`, or `failed`. `start`
  and deserialization reset it to `unresolved`; only `apply_result` sets it.
- **`tribulation_ok` requires `survived()`**, which is `is_complete() and outcome == SURVIVED`.
  Running, finished-but-undecided, and decided-but-lost all fail the gate.
- **`apply_result` keeps the record on the actor** and clears only the verdict's ambiguity. The next
  realm needs its own fight, so `begin_tribulation` replaces a decided record rather than reusing
  it. `cancel_tribulation` is the only path that discards one, forfeiting the waves survived and
  granting nothing.
- **`outcome` is serialized.** A payload written before outcomes existed loads `unresolved`, so an
  old save is re-decided rather than inheriting a win it never recorded.
- **The entry points live in core, not on a module facade.** `ui` already depends on `core`
  (`rules.LAYER_DEPS`), and every cultivation system shares one tribulation. Putting `begin` on
  three facades would have pushed all of them past the 12-method ISP cap to serve one mechanic that
  belongs to no single module.

## Consequences

- `_apply_failure` is now reachable from production, so defeat consequences actually land.
- A gate earned by a decided win stays earned across saves; a win can no longer evaporate.
- Resolving is deliberately not idempotent: `resolve_tribulation` requires an unresolved, complete
  record, so a second call cannot re-apply rewards.
- `actor.tribulation` is a *verdict* as well as an in-progress fight, so any future code that reads
  it must decide which question it is asking. `is_complete()` answers "did the phases finish";
  `survived()` answers "did the player win".