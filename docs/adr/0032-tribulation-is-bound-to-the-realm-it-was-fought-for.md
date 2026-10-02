# 0032 Tribulation is bound to the realm it was fought for

- Status: Accepted
- Date: 2026-10-02
- Amends: ADR 0020 ("Data model")

## Context

ADR 0020 made tribulation the risk that gives Immortal+ breakthroughs their stakes, and
`Tribulation.start(actor, realm_id)` already consumed `realm_id` to scale difficulty and wave count
— but never stored it. `Breakthrough.tribulation_ok` therefore asked only
`actor.tribulation.is_complete()`.

One survivor was therefore a permanent key to every gate from R19 to R30: fight once at
`earth_immortal`, then walk the Immortal and Transcendent tiers untouched. The state is also not
spent on failure — `MindAdvancement.try_breakthrough` applies it only on success — so a survivor that
outlived a failed attempt stayed on the actor indefinitely, and nothing in the ladder could tell a
stale one from a current one.

ADR 0020's data model listed the serialized fields without `realm_id`, so old payloads have none.

## Decision

- **`Tribulation.realm_id` binds the survivor to the realm it was fought for.** `start()` sets it;
  `to_dict()` writes it and `from_dict()` restores it.
- **`Tribulation.matches_realm(realm_id)` owns the comparison**, so `breakthrough.gd` never compares
  raw ids. `tribulation_ok` is `complete and matches_realm(realm)` — both conditions, no tolerance.
- **A tribulation with an empty `realm_id` unlocks nothing.** That covers both a payload written
  before this binding and one that was never started. Re-fighting is cheap and re-fightable; a
  survivor silently vouching for a realm it was never fought at is the exact bug this fixes, so the
  lenient reading is the unsafe one. Rejected, deliberately.
- **Gates below the Immortal threshold stay unconditional.** The binding only decides whether a
  tribulation counts, never whether one is required.

## Consequences

- A failed Immortal+ breakthrough no longer leaves a reusable key: the leftover survivor opens its
  own realm's gate and nothing else, so the next attempt must fight again.
- Saves written before this change load as unbound and make the player re-fight the tribulation in
  progress once. One-time cost, no persistent state loss.
- `mind_cultivation/test_full_traversal.gd` short-circuits its re-fight on `tribulation_ok`. It was
  an optimization that quietly relied on the old unbounded behaviour; it now re-fights per realm and
  still walks R1→R30.
- Gates that bypass `Breakthrough.tribulation_ok` and test `is_complete()` directly
  (`qi_cultivation/advancement.gd`, `qi_cultivation/breakthrough_transaction.gd`) are still
  unbounded and must route through `tribulation_ok` or call `matches_realm` themselves.