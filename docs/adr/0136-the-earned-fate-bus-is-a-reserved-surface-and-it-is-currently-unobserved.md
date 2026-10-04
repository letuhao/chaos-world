# 0136 The earned-fate bus is a reserved surface, and it is currently unobserved

- Status: **Superseded in part 2026-10-03 by ADR 0137** — the "unobserved" claim was false
  when written. Kept as the trace; read ADR 0137 for the current contract.
- Date: 2026-10-03
- Depends on: ADR 0134 (the consumer surface), ADR 0093 (signals announce, never request)
- Corrects: ADR 0065's reasoning about `WorldEvents` as a precedent

## Context

`contracts/destiny_events.gd` declares four signals. `DestinyProjection.events()` holds one
lazily-built `DestinyEvents` instance, and `DestinyApi` emits three of them (`api.gd:345,351,360`)
plus `gate_failed` (`api.gd:182`). **Nothing in `game/src` connects to any of them.** The only
subscriber in the repository is `game/tests/modules/destiny/test_destiny_earning.gd`.

So the question is whether fate earned is *silent by design* or *silent by omission*. The owner
asked. The answer matters, because a reserved-but-unobserved bus is a legitimate choice and an
owed toast is a different one — and a future agent cannot tell them apart from the code.

## Decision

**The bus is deliberately reserved, and it is currently unobserved. Both statements are part of
the contract, not a caveat on it.**

- **It is wired correctly and completely today.** An emitter, a stable instance, a documented
  shape per signal, and a suite asserting each. What is missing is a *subscriber in the game*,
  which is a feature, not a defect.
- **No toast or codex refresh is owed.** The codex screen (`ui/screens/destiny_screen.gd`) is
  pull-based: it reads `DestinyApi.summary(actor)` when it is mounted or refreshed. It needs no
  signal to be correct, and pushing at it would be a second refresh path. The UI standard is
  that a screen renders state; ADR 0134's split dev cycle says the same.
- **A toast is a decision to be made when something is actually earned.** ADR 0065 already
  records that no player can earn anything today (DEF-0183: `QuestApi.accept` and
  `EventApi.set_location` have no production callers). A notification design authored now would
  be specified against an event that cannot fire.
- **The reservation has a hard condition: the emitter side is frozen.** A signal signature may
  change only by superseding this ADR. The four payloads are what a consumer may rely on:

| Signal | Payload | Relied-on guarantee |
|---|---|---|
| `fate_earned` | `(actor_id, fate_id, source)` | Fired once per fate, ever. A replayed earn never re-emits. `source` names the system that earned it. |
| `destiny_earned` | `(actor_id, destiny_id, source)` | Same exactly-once guarantee. |
| `counter_changed` | `(actor_id, counter_id, amount, total)` | `amount` is the **applied delta**, `total` the value after it. Counters never decrease, so `total` is monotonic. |
| `gate_failed` | `(actor_id, reason, requirement)` | An **observation, never a veto** — the caller was already refused and is not waiting on this signal. Fires only when `actor != null`. |

- **The two guarantees that are easy to get wrong:** `actor_id` is a `String`, not an `Actor`,
  so a consumer holding a stale reference has no way to notice; and `counter_changed` is the
  only signal whose `amount` cannot be re-derived from the ledger afterwards, which is why
  `api.gd:337-360` threads the real delta through `_persist` instead of recomputing it.
- **Connection rules are the repo's, unchanged.** Every `.connect()` is guarded by
  `is_connected()` — an unguarded one is one handler per call on a reused or cached screen.
- **`gate_failed` will be noisy by design.** Any consumer polling `gate()` to render a locked
  row emits one per evaluation, not one per player-visible refusal. A consumer must treat it as
  telemetry, never as something to show, or it will spam. `DestinyGate.evaluate` itself never
  emits — only the `DestinyApi.gate` wrapper does, which is what keeps the pure evaluator
  testable.

## Consequences

- A future consumer's contract is: connect to `DestinyProjection.events()`, filter by
  `actor_id`, and never assume the signal was delivered exactly once per *player* event — only
  once per *earn*. `fate_earned` is once per fate ever; `gate_failed` is once per evaluation.
- ADR 0065 called `WorldEvents` "not a working precedent to copy" because it had no emitter.
  That is now false: `WorldEventBus` (`modules/event/world_event_bus.gd`) emits four of the
  nine declared `WorldEvents` signals from four real call sites (`event/api.gd:197,333,338,425`),
  and the same process-wide-instance rule is what makes both buses behave identically. ADR 0065
  has been corrected in place; the correction does not change its decision.
- When the earn path finally fires in play (DEF-0183), the first thing owed is a check on what
  the player is shown, and the bus is where a codex badge or a toast would attach. Not before.
- If a consumer ever needs a *new* announcement (a fate whose modifier was suppressed, a
  counter that hit a threshold), that is a superseding ADR and a fifth signal — not a second
  bus, and not a `contracts/` change smuggled in.