# 0163 A settlement room names an institution by id and an inner world is a domain template

- Status: Accepted
- Date: 2026-10-04
- Amends: ADR 0073 (its open collision is now decided; its room-kit decision stands)

## Context

The requirement was: *"other place like sect, castle can be inside a domain, it also can
become a inner world."* ADR 0073 promised this is **one** concept — a room of `kind =
settlement` — and left one collision open: `InsideWorld` and `WorldState` already exist
in `core/`, so is a walkable inner world a new thing or those two? BL-0219 tracked it.
Nothing implemented either half.

What those two classes actually are, which their names do not suggest:

- `InsideWorld` (`core/inside_world.gd`) is a **milestone record**, not a place. Nine
  scalars (`tier`, `size`, `stability`, `qi_density`, `time_flow`) plus a `laws` dict,
  committed by `WorldAnchor.commit` at a realm index. It has no rooms, no graph, no
  coordinates, and `InsideWorldProvider` reads exactly one field of it —
  `inside_world_qi_density` — as a stat.
- `WorldState` (`core/world_creation.gd`) is the **same shape one tier higher**
  (Transcendent): plus `laws[]`, `layers[]`, `inhabitants[]`, `resources`,
  `upkeep_rate`. `layers` are `WorldLayerState` — an id, a name, a `size_ratio` and a
  list of law ids. A layer is a **band of a created world, not a walkable room**: it
  carries no graph, no rooms and no exits, and `WorldAnchor` uses one layer's *presence*
  as proof a breakthrough built the world at all.

So there is no inner world to walk and nothing that could become one. The collision is
not two classes fighting over one name — it is a milestone ledger that was never a
place, and a room kit that already can hold the place.

## Decision

**1. A sect-in-a-domain is a `RoomDef` of `kind = settlement` carrying a TYPED, STRING-
KEYED ref. The reference is to `SectDef.id` — a `StringName`, never a `SectDef`
sub-resource.** Rejected: an `@export var sect: SectDef` on `RoomDef`, because it makes
`domain` depend on `sect` in the authored data as well as in code, and `domain` declares
`core` + `contracts` only.

- The ref rides the **existing `fixtures` array** as `{"kind": &"settlement_ref",
  "fixture_id": <sect_id>, "ref_kind": &"sect", "ref_id": <sect_id>}`. The array is
  already authored, already `to_dict`'d, already JSON-round-tripped, and already the
  place a room names a thing that lives outside it. **Adding an exported field to
  `RoomDef` was rejected**: `RoomDef` is the closed kit ADR 0073 froze, and the `audit`
  walks `fixtures` by `fixture_id` already.
- `ref_kind` is a **closed set of one** (`sect`) so a second kind is a content error
  rather than a silently accepted word.
- An unknown ref is **refused BY NAME** (`unknown_settlement_ref`), never defaulted to
  the nearest sect or an empty one. This is `DomainSpawner`'s rule for an unknown
  inhabitant, applied to an institution.
- A settlement names a sect; **a castle is the same room kind with `ref_kind` empty** —
  a settlement is a place, a sect is one thing that may hold it. One kind, two payloads.

**2. An inner world is (a): a domain template whose rooms are settlements.** It is NOT
(b) a map that replaces the actor's `WorldState` and NOT (c) a map that is a view over
it. Rejected:

- **(b) replacing `WorldState`** would put a `DomainMap` inside a save-shaped ledger that
  `WorldAnchor.stage_met` gates realms on, so a walk would have to be a breakthrough
  milestone. `WorldState`'s gates read `tier`, `origin_index`, `stability` and layer
  presence — none of which a room graph can supply.
- **(c) viewing over `WorldState`** was the tempting read of "one concept", but it makes
  the walk a *projection* of numbers that exist to gate a realm, so a room would owe its
  geometry to a realm ladder index. That is a second hierarchy.

**The collision resolves by DECOUPLING, not by mapping.** An inner world is a
`DomainTemplateDef` whose `pins` are settlement rooms (already the shape
`ember_grotto.tres` has). `InsideWorld` and `WorldState` stay exactly what they are —
milestone ledgers — and are **not** read by this seam. **Binding the two, if it is ever
wanted, is a one-way write from a `WorldState` milestone into a run's `domain_id`, and
belongs to `app/`, not to `domain`.** That is out of scope (below), not prohibited.

**3. `DomainSettlement` is a READ-ONLY LOOKUP, not a system.** It answers "what does
this settlement hold, and who is in it" in primitives, and writes nothing — not to the
`Actor`, not to `module_data`, not to the ref. It names the reference and reports it.

## Consequences

- **The seam is real and small**: `DomainSettlement.summary(actor, room_id)` and
  `.resident(actor, room_id)`. One file, no facade change (`DomainApi` is at its 12-method
  cap), no `registry.json` change, no new dep. It reaches `sect` through `SectApi`
  **injected as a `Callable`**, the same `DomainSpawner.set_minter` / `DomainFixtures.
  set_minter` seam, because `domain` may not name `SectApi` at all.
- **A role stays a tag.** Residents come from the room's own `actor_spawn_refs`
  (`DomainSpawner`), canonical order, `role`/`count`/ids only. No sect roster is read
  into it: the roster is `sect`'s ledger, and a second copy is the ADR 0066 failure mode.
- **Unblocking, not delivery.** BL-0219 stays `todo`; the `next` step is the sect
  simulator. This ADR decides the *seam* a simulator plugs into.

### OUT OF SCOPE for the first slice — a future agent must not read this as a mandate

1. Any sect simulator, roster, economy, politics or succession in a domain.
2. Reading `SectApi.summary()`'s roster/treasury — deliberately not done.
3. `InsideWorld` / `WorldState` being read, written, or mapped. Untouched.
4. Walking an inner world: entering one, generating from it, or binding it to a
   `WorldState` milestone. The template is authored content, not a runtime link.
5. A `settlement` room **spawning** a sect, founding one, or moving regard. A ref names;
   it does not act.
6. New room kinds (`castle`, `sect_headquarters`) or a second `ref_kind`.
7. Editing `RoomDef`, `DomainApi`, or any `game/src/data/**`.

## Rejected, summarised

| Question | Chosen | Rejected |
| --- | --- | --- |
| Where a sect lives | `fixtures` entry `kind=settlement_ref`, `ref_kind=sect`, ref = `SectDef.id` `StringName` | an `@export var sect: SectDef` on `RoomDef` (cross-module authored dep); a new `SettlementDef` resource (parallel hierarchy) |
| What an inner world is | (a) a domain template of settlement rooms | (b) replaces `WorldState`; (c) a view over it |
| How it reads `sect` | injected `Callable`, `DomainSpawner.set_minter` precedent | a bare `SectApi` reference (invisible cycle, `BARE_REF_UNITS`) |
| Unknown ref | refused by name, `unknown_settlement_ref` | default to nearest sect, or `{}` (a silent default reads as "no sect") |