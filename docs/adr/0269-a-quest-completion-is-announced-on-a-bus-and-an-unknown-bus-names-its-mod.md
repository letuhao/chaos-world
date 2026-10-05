# 0269 A quest completion is announced on a bus and an unknown bus names its mod

- Status: Accepted
- Date: 2026-10-05
- Extends: ADR 0242 (events bus wiring for mods), ADR 0184 decision 8 (never skip silently)
- Refines: ADR 0242 decision 4 (an unknown bus is skipped without crashing)

## Context

- Every bus in `contracts/` was an institution or polity domain. A registrable System
  (ADR 0267) is *action*-shaped, so it had nothing to subscribe to at all.
- `QuestApi.advance` and `QuestApi.complete` returned `{ok, completed, paid, unspent}`
  to their caller and emitted nothing. The only way to learn a quest had finished was to
  poll `QuestApi.summary()` from a screen, which fires the reward on screen-OPEN rather
  than on completion and puts game logic in the UI refresh path.
- ADR 0242 decision 2 hands a bus out as `SomeEvents.new()` for five of the eight buses.
  A fresh object per lookup is an instance nothing holds and nothing emits on, so a
  subscriber is connected FOREVER — `is_connected` says yes — while no signal ever fires.

## Decision

1. **`contracts/quest_events.gd` exists.** Three signals, primitives only, each announcing
   a fact already written: `quest_accepted`, `quest_completed` (from `_complete`, the one
   place completion is decided, so the once-guard is the announcement's guard), and
   `quest_refused` (from `_refuse`, the one place a refusal is built). No `Resource`, no
   `Actor`, no authored content — ADR 0114's `BeatSink` line, and what
   `DamageProposal.is_primitive_effect` refuses at construction.
2. **`shared()`, not a facade accessor and not a fresh instance.** A mod names the bus
   CLASS, and ADR 0242 resolves it in `app/`'s factory table; a static on the contract lets
   that table reach the instance with no module edge, because `contracts/` is the leaf
   layer. A fresh instance is rejected outright: it is a subscription that can never fire.
   `QuestApi.events()` (the `ConflictApi` shape) is rejected as legal-but-worse — it grows
   a facade already over `LINE_BUDGET` and makes the table name a module where it
   otherwise names only contracts.
3. **No "offered" signal.** An offer is re-derived on every call and `summary()` reaches
   it too, so a signal there would fire on screen-open — the defect, from the other side.
4. **An unknown bus still does not fail a boot** (ADR 0242 decision 4 is unchanged) **and is
   no longer silent.** Each unresolvable bus is `push_warning`-ed naming the bus AND the
   mod, and recorded on `_unresolved_buses` so the skip is assertable. The mod id is
   stamped onto each row by `ModRuntime.finalize`, the only place that knows which context
   a row came from.

## Consequences

- A System whose entire economy is one quest subscription now has a signal that fires on
  completion, and a bus name that resolves to the instance `QuestApi` publishes on.
- Adding a bus is one entry in `_resolve_events_bus`; a `shared()` on the contract is what
  makes that entry live rather than decorative.
- **Recorded, not fixed here:** the five ADR 0242 decision-2 entries still returning
  `new()` — `WorldEvents`, `DestinyEvents`, `NationEvents`, `SectEvents`,
  `HoldingsEvents` — are dead subscriptions for the same reason, and each owning facade
  already publishes a singleton (`EventApi.events()`, `DestinyApi.events()`,
  `HoldingsApi.events()`, and the `sect`/`nation` projections). Routing them is the same
  one-line change per entry, on a wider slice.
- Guards: `tests/contracts/test_quest_events.gd` (singleton, primitive-only arguments,
  every declared signal has a producer), `tests/modules/quest/test_quest_events_emitted.gd`
  (emission, once-guard, and that a read announces nothing),
  `tests/app/test_unknown_bus_warning.gd` (resolution by identity, and the named warning).