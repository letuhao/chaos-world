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
  of idea but has no emitter and no consumer anywhere in the tree, so it is not a
  working precedent to copy.
- **Exclusivity is permanent.** A destiny closes its `group` for good. It is not a
  swap, and no later fate can reopen it.
- **Ids are plain, and separation is structural.** A fate id is `oath_of_the_empty_hand`,
  not `fate.oath_of_the_empty_hand`. Fate and destiny ids live in their own catalogs
  (`res://data/destiny/fates`, `res://data/destiny/destinies`) and are resolved only
  through `FateCatalog`, so an id never has to carry its type. Do **not** extend the
  `quest:` namespace: the 233 `.tres` under `game/data/items/quest/` already declare
  `sources = [&"quest:main_03"]`-style ids naming quests that do not exist, so a
  `quest:`-prefixed fate would read as a working reference and silently grant nothing.
- **Content is gated, not warned.** `data audit` fails the build on a bad stat id, a
  FLAT modifier on a rate stat, or a dangling cross-reference. Nothing re-reads a
  `.tres` field after load, so without that gate a typo ships a fate that does nothing.

## Consequences

- The earn call sites are deliberately not implemented here. This module is a write
  target, not a listener: combat (kills, duels), the breakthrough paths, quest
  completion and world events each call `DestinyApi.earn_fate()` when they are
  built, and character creation calls `earn_destiny()` once an origin is authored.
  Until then `attach()` only normalizes an empty ledger, so the codex screen reads
  zero and nothing is owed.
- A consume/clear fate affordance is refused by this ADR and is recorded as
  deferred, so a future agent finds the decision instead of re-litigating it.
- A fate-gated quest, story or event cannot be authored yet, because those systems
  do not exist. The gate is an unused surface until they do, which is the shape
  ADR 0030 tolerates only while it stays honest: it is public, tested, and every
  gap is recorded in `docs/deferred.jsonl` with the module that will close it.
- What ships and is verifiable today: the ledger, the six gate verbs, the earned
  bonuses, the codex screen, and 17 fates with 5 destinies behind them. What ships
  empty is the earn path — the codex reads zero for a fresh actor, correctly, because
  nothing has earned anything yet.