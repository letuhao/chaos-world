# 0221 A domain is always generated from a template, and a handcrafted room is authored content fed to the generator

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0215 (one room kit, or two systems)
- Amends: ADR 0072 (its "the handcrafted producer does not ship" is CONFIRMED and made permanent, not deferred), ADR 0073 (the kit decision stands; this decides who may use it)
- Fates: the 9 legacy scenes under `game/scenes/domains/` + `game/scenes/worlds/`

## Context

The genre convention is that handcrafted and procedural content are *not two systems but
one content pipeline with two ends*. A designer authors the **pieces**; the game arranges
them into a **place**. A handcrafted level is then just the case where the arrangement was
authored too. What the genre avoids — and what shipped projects get wrong — is a second
pipeline: a separate art set, a separate spawn convention, a separate navigation model, so
that a player can *tell* which one they are in. The tell is the failure, and it is never
worth it because a content team cannot afford two kits.

This repo already refuses that: ADR 0073 made `RoomDef` the single currency, ADR 0072 ships
one `DomainMap` shape. What is open is the **producer**. ADR 0072:24 wrote "the handcrafted
producer does not ship … a handcrafted domain therefore exists only as test data today" —
an accurate description of a *state*, not a decision, which is why BL-0215 stayed open.
Nine scenes now exist that would be its handcrafted producer
(`game/scenes/domains/{mortal_plains,immortal_court,spirit_peaks,transcendent_realm}.tscn`
plus five in `game/scenes/worlds/`), and they bind engine nodes by name.

## Decision

**There is one producer: `DomainGenerator`. A "handcrafted domain" is authored *rooms* fed
to it, never an authored *graph*. The 9 legacy scenes are DELETED, not ported.**

- A handcrafted domain is expressed as a **`DomainTemplateDef` whose `pins` name the rooms a
  human placed and whose `room_pool` is the kit the generator draws the rest from.** That is
  already the shape `ember_grotto.tres` has. "Handcrafted" becomes a *declaration of intent
  in data* — a template pinning every leaf with `requires_full_kit` — not a second code path.
- **There is no `.tscn` → `DomainMap` reader, and none may be added.** A scene is a
  *realization* (ADR 0072: `DomainScene`), never a *source*. The moment a `.tscn` can be read
  into a `DomainMap`, two descriptions of one place exist and can disagree — the ADR 0072
  nav-polygon argument applied one level up.
- **`RoomDef` gains no fields and `DomainTemplateDef` gains no `producer` flag.** Provenance
  lives in the test, not the data — ADR 0072 already refuses that field on `DomainMap`.
- The ADR 0073 parity contract is therefore **satisfied by identity**: one producer means
  parity is the same object. The surviving test is that `DomainMapContract` has no
  privileged input — a seeded map and a hand-built fixture map both pass or both fail it.

### The 9 scenes

Delete all 9. They are unreferenced: `res://scenes/domains/` and `res://scenes/worlds/`
resolve to exactly one repo hit, `tests/modules/domain/test_domain_scene.gd:35`, which names
`DomainScene.tscn` — the *new* scene, not any of the 9. `DomainScene.tscn` stays and keeps
its production path. The marker surface the 9 exercise (`SpawnPoint`, `NPCSpawnPoints`,
`EnemySpawnZones`, `ResourceNodes`, `EntryPoints`, `ExitPoints`, `LocationMarkers`) is **not
ported**: a `DomainMap` already answers "where may I spawn / what is here" through
`RoomDef.actor_spawn_refs`, `RoomDef.fixtures` and `DomainMap.reachable_room_ids()`, so
porting the markers authors the same facts in a second shape.

## Consequences

- **One producer, one kit, one audit rule.** BL-0215 is answered by subtraction: there is no
  second system left to disagree with.
- **The parity test changes shape.** It stops being "two producers agree" (impossible with
  one producer) and becomes "the validator has no privileged input" — a stronger claim at
  less cost.
- **A fixed layout needs no new machinery:** `min_rooms == max_rooms`, a pin per leaf,
  `requires_full_kit`. Determinism is ADR 0072's.
- **Reconciles with BL-0213**, closed 2026-10-04 for `DomainScene.tscn` only, explicitly
  leaving "the 8 LEGACY scenes … a separate, still-orphaned set" open. **This closes that
  remainder** (9 files, not 8 — BL-0213 undercounted). `DomainScene.tscn` is untouched.
- **Trade-off rejected: build the `.tscn` reader.** Rejected because it re-creates two
  descriptions of a place, and because the one thing it buys (a fixed authored layout) is
  bought better by a fully-pinned template — inside the audited content tree, with no second
  geometry path that `tools data audit` cannot see.
- **What would change my mind:** a real domain needing geometry no `RoomDef` can express —
  non-rectilinear rooms, scripted set-pieces, hand-painted terrain. The honest answer then is
  a tile-stamp `fixtures` entry, still not a second producer.

## Not decided here

- Whether a fixed template deserves its own authoring shorthand. It is expressible today; a
  shorthand is convenience, not design.
- The 9 scenes' **art** (`game/assets/world_map/**`). Assets are indexed separately
  (`game/assets/map-asset-index.jsonl`) and outlive the scenes; nothing here retires them.