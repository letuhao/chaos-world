# 0053 A technique is a codex entry, not an item and not a slot

- Status: Accepted
- Date: 2026-10-02

## Context

The `technique` item category holds 1363 authored `ItemDef`s routed to `ItemActivation.LEARNED`.
Studying one today calls `ItemUse._apply_learned`, which grants flat base attributes once and
forgets the item. The category has no identity: 100% of files use the same 10 fields, ids are
template concatenations of stat names, and every item draws from the same option pool as
equipment. Two techniques are interchangeable by construction.

The obvious fix — a technique *is* an equipped slot — collapses three separate decisions into
one, and each fails differently.

- **Learning is acquisition.** It is gated by realm, paid for in a path resource, and spent from
  a codex. It happens off-combat and should never be reversible by accident.
- **Equipping is a build choice.** It is limited, reversible for free, and re-decided per fight.
- **Mastery is a long investment.** It accumulates through use and competes with the realm
  ladder for the same progress resource.

Collapsing them means a single mis-click unequips a permanent investment, and a slot limit
silently deletes a technique the player paid real currency for.

The genre convention agrees: known set and equipped set are deliberately different sizes, and
the gap between them is the entire design space.

## Decision

- **Three states, three owners of truth.** An `ItemDef` delivers a technique, is consumed, and
  is gone. A `CodexEntry` is permanent, path-gated, and unlimited. A `Slot` is a limited,
  typed, swappable binding from codex to actor.
- **Losing a slot never loses the technique.** Unequip and slot overflow return the entry to the
  codex. There is no code that deletes a `CodexEntry`.
- **Slots are typed by path**, not one flat pool: fixed small counts for qi, body and mind, plus
  universal slots that grow with realm tier. A loadout is therefore a statement about which path
  is being bet on, and every learned technique is an implicit argument for retiring another.
- **Path-exclusive techniques are the default.** A shared technique is equippable anywhere, draws
  from whichever path has slack, and carries a weaker ceiling. Dual-path behaviour is the
  exception that makes a dual-cultivator interesting without making it strictly better.
  A DUAL technique requires **both** of its paths at the gate — see ADR 0059.
- **Separate the hold gate from the strength gate.** A realm gate decides what may be *learned*;
  mastery decides how good it is. Realm alone never makes a technique strong, so an old
  technique at high mastery stays competitive with a fresh unlock.
- **Technique content is a module-owned Resource.** A `TechniqueDef` lives beside its feature in
  `modules/<x>/`, never in `contracts/`. See ADR 0056.

## Numbers

Slots are read from the actor's realm **tier**, so all 30 realms resolve through four
published rows (`RealmDefaults.ladder().tier_of()`), never from a ladder index.

| Tier | Realm ordinals | qi | body | mind | universal | total |
|---|---|---|---|---|---|---|
| 1 Mortal | 1-9 | 3 | 2 | 2 | 0 | 7 |
| 2 Spirit | 10-18 | 3 | 2 | 2 | 1 | 8 |
| 3 Immortal | 19-27 | 3 | 2 | 2 | 2 | 9 |
| 4 Transcendent | 28-30 | 3 | 2 | 2 | 3 | 10 |

- Per-path counts are **fixed for the whole ladder**: qi 3, body 2, mind 2. Only the
  universal pool grows, by one per tier.
- A `SHARED` technique takes a **universal** slot. It never takes a path slot, so
  spending a universal slot on a shared technique is a real cost against path depth.
- The equipped set is 7-10 entries against an unbounded codex. The 1363 existing technique
  items alone are a 136x larger known set at R30, and even a codex holding every one of
  them leaves 97% of the corpus unequipped. That gap is the design space.

## Consequences

- Learning, equipping and mastery are separately testable and separately persisted.
- The item is purely an acquisition vector, so technique content can be dropped, crafted,
  quested or inherited without the codex caring which.
- Because the codex is unbounded and slots are not, every technique must be worth a slot. That
  is a content obligation, and it is what keeps stat-stick manuals out of the identity layer.
- Slot counts are per path, so the three cultivation modules each need a published slot count and
  a way to read the actor's path rank. The existing "take the best path" helper does not serve
  this — a path-scoped gate must read one path's rank.