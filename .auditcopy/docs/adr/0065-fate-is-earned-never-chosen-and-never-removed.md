# 0065 Fate is earned, never chosen, and never removed

- Status: Accepted
- Date: 2026-10-02
- Amends: ADR 0026 (one modifier application stage), ADR 0027 (module_data payload)
- Consistent with: ADR 0002, ADR 0044

## Context

A player accumulates consequences. Some should be stat modifiers they can read and
some should be narrative identity they can be gated behind. Nothing here needed a
new stat pipeline, a save field, or a new kind of equipped slot.

## Decision

- **Fate is earned, never chosen, never equipped, never removed.** There is no slot
  to fill, no picker to open, and no revoke path: not for a penalty, not for a
  reset, not for a debug tool. Nothing in the module removes anything.
  `normalize()` may drop an entry only when it is unreadable or names content the
  catalog no longer ships — never because the player did something.
- **A ledger, not direct stat writes.** `destiny_state` under `actor.module_data`
  is the single source of truth; `DestinyProjection` rebuilds every modifier and
  trait from it. So restore, replay and re-attach cannot double-count or drift.
- **No second stat composer.** Fate calls `actor.stats.add_modifier` exactly as an
  authored trait does. A parallel fold would make every aggregation rule learn about
  fate twice.
- **The gate is data.** Six closed verbs: `has_fate`, `has_destiny`, `counter`,
  `all_of`, `any_of`, `none_of`. An unknown verb or a malformed requirement refuses
  closed and names itself. Refuse-with-cause, never silently open.
- **The trait mirror.** `destiny:`-namespaced ids in `Actor.traits` exist so
  `StatContext.has_trait()` works for future consumers. The ledger stays
  authoritative; the mirror is derived and rebuilt on every attach.
- **Signals live on an instance, not on the contract class.** `DestinyEvents`
  declares the four signals but a GDScript signal belongs to an object, and a
  facade is a namespace of statics — so `DestinyApi` cannot emit them. The bus is
  one `DestinyEvents.new()` held at `DestinyProjection.events()`, and nothing
  outside the module emits through it. It is deliberately **not** on the facade:
  the facade is already at its twelve-method cap, so a thirteenth method for a bus
  would have meant dropping something real. `WorldEvents` declares the same shape
  of idea; the `event` module has since given it an emitter (`WorldEventBus`,
  `event/api.gd:197,333,338,425`), so it is now a working precedent (ADR 0136).
- **Exclusivity is permanent.** A destiny closes its `group` for good. It is not a
  swap, and no later fate can reopen it.
- **Ids are plain, and separation is structural.** A fate id is `oath_of_the_empty_hand`,
  not `fate.oath_of_the_empty_hand`. Fate and destiny ids live in their own catalogs
  (`res://data/destiny/fates`, `res://data/destiny/destinies`) and are resolved only
  through `FateCatalog`, so an id never has to carry its type. Do **not** extend the
  `quest:` namespace: of the 233 `.tres` under `game/data/items/quest/`, 62 already
  carry a `quest:<id>` source and 34 distinct ids are named that way — every one of
  them a quest the catalog does not define. Fate sharing that prefix would read as a
  working reference and silently grant nothing.
- **Content is gated, not warned.** `data audit` fails the build on a bad stat id, a
  FLAT modifier on a rate stat, or a dangling cross-reference. Nothing re-reads a
  `.tres` field after load, so without that gate a typo ships a fate that does nothing.

## Consequences

- The earn path is wired, not empty. Quest completion calls `earn_fate` /
  `earn_destiny` from the one place `QuestApi` marks a quest complete, and world
  events call both from `EventPrize` under `"event:<event_id>"`. Both source strings
  name the *source*, never the fate id, so fate keeps its own catalog. Combat (kills,
  duels) and the cultivation breakthrough paths are still unbuilt and grant nothing.
- `app/item_workbench_app.gd` calls `DestinyApi.attach(actor)`, so the composition
  root — not fate — decides when the ledger exists. Birth grants nothing and can
  never grant anything.
- A fate-gated quest or event is authored and opens today: `QuestApi` and `EventGate`
  both read `DestinyApi.gate`, and `EventGate` delegates the three fate verbs verbatim
  rather than re-evaluating them, so there is exactly one fate evaluator in the repo.
- A consume/clear fate affordance is refused by this ADR and is recorded as
  deferred, so a future agent finds the decision instead of re-litigating it.
- What ships and is verifiable today: the ledger, the gate evaluator, the codex screen,
  and 17 fates with 5 destinies behind them. **The earned bonuses are NOT verifiable
  today** — an earlier draft of this line claimed they were, and that was wrong. No
  player can earn anything: `QuestApi.accept` and `EventApi.set_location` have no
  production caller, so no quest is ever accepted and no event ever opens (DEF-0183).
  The earn and grant paths themselves are sound and tested; they have nothing to fire
  from. **Remaining seams.** `quest` calls `DestinyApi` but does not declare `destiny` in
  `tools/arch/registry.json`, and `BARE_REF_UNITS` excludes `modules/*` so the arch
  gate cannot see the edge; and `FateDef.counters` is authored but never read back,
  nor written — no `DestinyApi.record()` call site exists, so the `counter` verb has zero
  authored content and every counter gate is vacuous (DEF-0121, DEF-0181).
- **The consumer contract is a separate decision.** The twelve verbs a consumer may
  call, the registry rule a consumer MUST satisfy, the measured earn-source matrix,
  and the refusal contract are recorded in **ADR 0134**. This ADR owns the invariant;
  ADR 0134 owns the surface. An item or unique that grants a fate is decided by
  **ADR 0135**; the signal bus a consumer may observe is decided by **ADR 0136**.