# 0218 Keyed, realm-gated and boss-sealed are three treasure shapes and each is bought by a different currency

- Status: Accepted
- Date: 2026-10-05
- Resolves: the third BL-0848 half — which gate shape belongs where
- Depends on: ADR 0217 (both tests), ADR 0216 (what a fixture pays)

## Context

ADR 0073 froze the fixture vocabulary to three kinds (`trap`, `puzzle`, `treasure`) and
ADR 0217 fixed the two tests every gate must pass. Neither says which of the three gate
*shapes* a designer should reach for, and the corpus shows the cost of leaving that open:
five fixtures, three gate shapes, two of them mislabelled, and the one tagged
`treasure_boss_sealed` tagged by hand rather than enforced by anything.

`ash_heart_hoard` carries `tags = [treasure_keyed, treasure_boss_sealed, deep]` and an
**empty** `key_item_id` (`ash_heart.tres:29`). `treasure_keyed` is simply false — nothing
about that hoard is keyed. The tag set is being used as free-text description, which is
the same failure ADR 0073 forbids for room tags ("never a post-hoc heuristic").

## Decision

**Three shapes, three currencies, and the shape is chosen by what the player has already
spent by the time they arrive.**

| Shape | Costs | Appropriate when | Refusal to show |
|---|---|---|---|
| **KEYED** — `key_item_id` | **an item, earlier** | the player has been somewhere else first | `missing_key` |
| **REALM-GATED** — `requires_realm` | **time** | the prize is below the player and would be wasted on them | `realm_below_the_floor` |
| **BOSS-SEALED** — the fight | **blood, and a one-shot** | the prize IS the fight's reward | nothing — the boss is the door |

1. **KEYED is a bargain about sequence.** It answers "you came back with the thing you
   needed." Use it when the domain has more than one place to be, and the key lives in
   one of them. A key that is craftable for pocket change is not a key; it is a formality,
   and ADR 0217's SATISFIABLE test is where that gets caught.

2. **REALM-GATED is a bargain about timing.** It answers "you are early." Use it as a
   **ceiling, never a floor, on a deep prize**: it stops a Foundation cultivator from
   looting the deepest relic in the game, which would flatten the ladder faster than any
   balance number. It never belongs on a mid-tier container, where it is just a wall on
   content the player could already use.

3. **BOSS-SEALED is a bargain about risk and it is the only shape that may not be a
   separate gate at all.** A boss's reward belongs to the boss's **loot table**
   (`LootTier.boss_tables`), where it is already earned, already realized at defeat time,
   and already subject to ADR 0166. A `treasure_boss_sealed` *fixture* is a second
   reward for the same fight, authored in a shape that bypasses every one of those
   guarantees. **Decision: `treasure_boss_sealed` is not a gate shape. A boss's prize is
   its table. The core room's hoard is for what the boss was guarding, not for the boss.**

4. **A treasure fixture carries AT MOST ONE gate.** Keyed *and* realm-gated on the same
   container is two walls on one box, and the second is invisible to the player because
   the first is what stops them. `ash_furnace_hoard` carries both today
   (`ash_furnace.tres:29`) and must drop one.

5. **`treasure_unkeyed` is the tag for "no gate", and it is honest.** An open container is
   a legitimate authored choice (ADR 0217). What is illegitimate is an *empty*
   `key_item_id` under a `treasure_keyed` tag.

## Consequences

- `ash_heart_hoard` loses `treasure_keyed`, keeps `requires_realm: core_formation` as a
  ceiling on the deepest prize in the domain, and its tag set becomes true.
- `ash_furnace_hoard` keeps its key (it is the sequence bargain — the key is craftable, so
  the gate is on *having gone and made it*, not on luck) and **loses its realm floor**,
  because the two are redundant walls.
- The **`treasure_boss_sealed` vocabulary leaves the room fixtures**. Boss prizes are
  `LootTier` tables; a tag that only a hand-editor applies is a tag that will be wrong
  somewhere. `test_domain_content.gd:619` reads it today and must change with the data.
- The shape a fixture uses is visible to the player through `DomainFixtures.telegraph`
  (`domain_fixtures.gd:290-319`), which already publishes `key_item_id` and
  `requires_realm` — no new read model is needed to render "this needs a key" or "you are
  too early".

## Rejected

- **Keep `treasure_boss_sealed` as a third shape with a real gate.** Rejected: it is a
  reward for the fight, and the fight already has a reward channel with realization,
  seeding and ADR 0166 already applied. Authoring around it buys nothing and costs all of
  it.
- **Stack all three gates on the deepest hoard.** Rejected for the plain reason the player
  experiences: three requirements is a wall, and a wall is not a bargain.
- **Drop `requires_realm` from fixtures entirely** and let the band gate depth. Rejected:
  the band gates the *fight*, not the *container*, and a Foundation player who wandered
  into a deep room should meet a container they cannot open — that refusal is the signal
  that the room is not for them yet.