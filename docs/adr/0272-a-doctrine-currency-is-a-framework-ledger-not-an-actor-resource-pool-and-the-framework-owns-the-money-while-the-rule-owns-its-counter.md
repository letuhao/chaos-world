# 0272 A doctrine currency is a framework ledger, and the framework owns the money while the rule owns its counter

- Status: Proposed
- Date: 2026-10-06

## Context

`contracts/doctrine_rule.gd` (ADR 0267) says a System's pools are "the SAME ids
`CultivationPathDef.resource_ids` already creates lazily through `ensure_resources(actor)`".
Measured, that promise cannot be kept and the arithmetic is why:

- `ResourcePool.change` clamps to `maximum` (`contracts/resource_pool.gd:28`).
- `CultivationPathDef.ensure_resources` mints a declared pool with `maximum = 0.0`
  (`core/cultivation_path_def.gd:44`).

So `change(+amount)` on any pool created through that seam is `clampf(amount, 0.0, 0.0)` — a
guaranteed `0.0`, whatever the id. A pool that cannot accumulate cannot be a currency, and a
doctrine currency must accumulate: a System you have not spent from still holds what you
farmed. A doctrine that earned into `qi` or `integrity` would also be a second writer for a
capped stat, which is a magnitude table wearing a currency's name.

## Decision

`modules/doctrine/` ships three files and eleven facade verbs.

1. **The balance is a framework ledger at the rule's own `data_key()`, not a `ResourcePool`.**
   `DoctrineLedger` owns `version`, `joined`, `balance`, `balances`, `earnings`, `redemptions`.
   `balance` mirrors the FIRST declared pool so a single-currency System reads one number;
   `balances` is authoritative for a System that declares more than one.
2. **Every key the framework writes is `String`.** `Actor.to_dict` converts the OUTER
   `module_data` key and nothing else (`core/actor.gd:397`), so an inner `StringName` key
   returns as a `String` and the map reads empty after a reload. `owned` is passed through
   verbatim because it is the rule's map.
3. **The rule owns `points`, `points_max` and `owned`; the framework owns the money.** That
   split is what keeps ADR 0267's one-writer rule true while the rule advances its own
   counter inside `redeem`. **No verb writes a counter**, so a test that wants a million
   levels seeds the ledger the way the rule would.
4. **`earn` arbitrates: the largest claim on an occurrence takes it**, ties to the earliest
   registration. `amount` is the only scalar a proposal carries, so the biggest one is the
   biggest claim, and the answer does not depend on registry order. `redeem` needs no arbiter
   — one press, one row, one transaction.
5. **`redeem` reads the quote BEFORE the rule's writer.** `redeem` grants through
   `Actor.add_status` the instant it is called, so booking afterwards and discovering a short
   balance would leave a free row. The ledger is debited the ROW's `amount`, not the rule's
   reported `spent`, so a rule cannot under-report its own cost.
6. **`leave` is destructive**: it forfeits the counter, the bands it reached and every unspent
   coin. A leave that kept them would be a free bank. It does NOT reverse a grant — nothing
   in the tree removes a `StatusEffect` but the status layer, which is DEF-0321's removal half
   and out of this slice.
7. **`attach` is a gate, not a lookup table**, and it refuses by one of
   `DoctrineRule.REASONS` because that set is closed: an unnamed System, a duplicate id, a row
   missing a `ROW_KEYS` entry, a non-primitive payload, a row spending an undeclared pool, a
   priced row naming no pool, a declared pool no row spends (yin-yang), a pool that is
   `ActorPools.CORE_POOL_STATS`, and a `progress`/`tier_for`/`earn`/`price` payload missing a
   declared key. `price` is checked against a row that EXISTS, because `{}` is correct for a
   row the System does not sell.
8. **A missing row is resolved BEFORE the opt-in** in both `price` and `redeem`, so a row that
   does not exist reads as `{}` and never as a refusal (ADR 0083).
9. **Nothing in the module ticks, reads a clock or reaches the scene tree** (DEF-0111). Every
   accrual is one caller-initiated `earn`.

## Consequences

- **The resource-id gap is NARROWED, not closed.** `attach` now fails loudly on an empty id, a
  duplicate, a core-reserved id, a row spending an undeclared pool, and a pool with no sink.
  What it cannot catch is a pool id that is a typo of a *different System's* id — there is
  still no list of valid resource ids anywhere in the repo (six modules hardcode their own in
  code; `CultivationPathDef.resource_ids` is populated in code, never from data), and building
  that list is a decision about which module owns the vocabulary, not a check this module may
  bolt on. `summary()` publishes the declared union so the vocabulary is at least readable.
- **`registry.json` declares `destiny, economy, items, quest` and this slice uses none of
  them.** The permission was granted ahead of the body, the same way `UI_MODULES` grants
  `techniques` its `items` reach. `economy` in particular is unusable as a doctrine currency:
  its numéraire is an item, and `ItemsApi` is already at fan-in 11 against a cap of 8.
- **`ModuleRegistry.BASE_DEPS` gains `doctrine`.** It is a static mirror of `registry.json`
  and `doctrine` was absent, which failed `tools arch` and
  `test_module_registry::test_seed_list_resolves_in_registry.json`. `conflict` is missing from
  the same mirror and is not this slice's to fix.
- **No candidate System ships.** All eight shapes are supportable; the empty registry, one
  System, several Systems and an inert System with no rows are all tested states.
- **A name collides with `sect`.** `SectDoctrineDef` is a school's TEACHING (BL-0186), and
  this is a practitioner's own transmitted rules. Different concepts, same word.
