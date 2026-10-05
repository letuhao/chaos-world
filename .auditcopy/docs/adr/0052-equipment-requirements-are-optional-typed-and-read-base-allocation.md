# 0052 Equipment requirements are optional, typed, and read base allocation

- Status: Accepted
- Date: 2026-10-02

## Context

An exceptional item could be worn by a weak actor for free, so exceptional items needed a
demand. The risk is the opposite failure: a demand applied by the system rather than asked
for by the item, which taxes ordinary loot and makes the player's reward a lock instead of a
choice. Adapted from Keepverse's `equipment-requirement-maintenance.md`.

Two details are easy to get wrong and expensive when wrong.

**A requirement must not be satisfiable by the thing it requires.** If the check reads a
derived stat, then equipping the item grants the stat it demands and the requirement passes
on the second equip — a gate that is a no-op for the only actor who matters.

**Upkeep is an obligation, not a gate.** If failing to pay unequips the item, then spending
in combat strips gear mid-fight, and a player can never opt out of a cost they cannot afford.

## Decision

- **Requirements are opt-in.** `ItemDef.requirement` is null by default and rarity never
  implies demand. An empty profile means no restriction, so ordinary loot stays unrestricted.
- **Four independent profiles**, which may combine: `min_realm_index` (a realm ordinal read
  off `RealmDefaults.ladder()`, so it is never a private level-to-cost curve),
  `fixed_minimums` (minimum base value for named attributes), `ratio_minimums` (a minimum
  SHARE of the actor's base allocation across the stats named, so an item favours a build
  rather than a large number), and `upkeep` (a resource drained per interval).
- **Every check reads base attributes and base resource pools.** `ActorStats.get_base`, never
  `derived`. This is what makes rule (1) structural rather than a rule to remember.
- **The floor takes the best path**, so an item never demands one specific cultivation system.
- **Upkeep SUSPENDS an item; it never unequips and never blocks an equip.** An item that
  cannot pay stays equipped and contributes nothing. Suspension is per slot, so paying one
  item's upkeep does not reactivate another's. An `upkeep_reserve` keeps a payment from
  chipping an actor to zero and suspending on the tick that empties the pool.
- `unmet(actor)` returns every unmet requirement for a panel, so a screen never has to
  re-derive them.

## Consequences

- Both load-bearing rules are pinned by tests that were mutation-checked: granting 10,000
  derived WILL through a modifier must NOT satisfy a requirement on WILL, and an unaffordable
  upkeep must leave the item equipped with no effects.
- The realm floor is an ordinal, so breakthroughs inside a realm do not raise an actor over a
  realm floor. That is deliberate: a floor names a realm, and letting stage count buy the item
  would reintroduce the composed index that named a deleted concept.
- Panels get `unmet()` rather than re-implementing the profile rules.
