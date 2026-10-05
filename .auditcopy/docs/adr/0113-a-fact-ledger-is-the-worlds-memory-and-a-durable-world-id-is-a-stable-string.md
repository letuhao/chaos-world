# 0113 A fact ledger is the world's memory, and a durable world id is a stable string

- Status: Accepted
- Date: 2026-10-03
- Amends: ADR 0067 (one spine, one seam), ADR 0060 (a tool must measure what it claims)
- Consistent with: ADR 0027 (instance persistence), ADR 0022 (rate stats are percent)
- Resolves: BL-0054 (first slice)

## Context

An event/quest/story program needs somewhere to remember that the player did something. Four
independent systems already need that memory and none of them can be reused:

- `ItemDef.sources` (`modules/items/item_def.gd:18`) is an exported acquisition-graph field
  populated on **1,697 authored `.tres` files**, and **no code in `game/src` reads it**. Its own
  tooling has already concluded it is inert (`tools/data.py:176`, `tools/acquisition/chain.py:3`).
  The connective tissue is missing; the content is already paid for.
- `DestinyState` (`modules/destiny/destiny_state.gd`) is a ledger under
  `actor.module_data["destiny_state"]` holding `fates`, `destinies`, `counters`, `history`. Its
  `counter` verb is already the documented accrual shape for `duels_won` (DEF-0105).
- `NpcState` (`modules/npc/npc_state.gd`) holds a per-NPC roster with `stage_id` plus tally
  counters, and `NpcStageDef.advance_after` names "the system that owns the story beat" as its
  zero-case caller (`npc_stage_def.gd:30-31`).
- `NationState` and `SectState` each keep their own institutional ledgers.

Four copies of "a thing happened, count it" is the ADR 0066 failure mode: a fourth stat composer
beside `realm_power_table.tres`. A fifth module that invents its own flag store is worse.

The world identity problem is separate and equally real. `WorldState` (`core/world_creation.gd`) is
**not** the playfield — it is the Transcendent-tier ability to create a small realm, holding `tier`,
`size`, `stability`, `laws`, `layers`, `inhabitants`. Its id is a runtime `Actor`, and ADR 0082
moved it to `core` precisely because it is not a world-creation-module concern. Meanwhile ADR 0045
defines five `World*Def` Resources for authored content, and `WorldApi.locations()` is an uncalled
`DirAccess` scan of `res://data/world/locations`. The player's location is not durable anywhere.

## Decision

**One fact ledger in `core`, shared by every system that must remember something.**

- **`WorldFact` is a value object in `core/world_fact.gd`**, not a Resource and not in a module.
  It follows the `InstitutionClaim` precedent (`core/institution_claim.gd`): a `@export`-capable
  value type that must live in `core` because it is reachable as shared foundation data, and `core`
  is a layer, so the cross-module facade rule never applied to it.
- **A fact is `{id: StringName, count: int, since: int}`** and nothing else. It carries **no
  reward, no flag semantics and no effect reference**. A fact is a thing that happened, not a
  thing that grants something.
- **The ledger lives at `actor.module_data["world_facts"]`** (ADR 0027's pattern) under
  `WorldFactLedger`, with `SCHEMA_VERSION`, `normalize()`, `count(id)`, `has(id, need)`, `record()`,
  `to_dict()` / `from_dict()`. JSON-round-trippable, so it survives `Actor.to_dict()`.
- **Monotone only.** `record()` raises a count and never lowers one. ADR 0065's rule — fate is
  earned, never removed — is the house position on remembered things, so a fact cannot be spent,
  spent-again or revoked. A "consumed" thing is a quest step, not a fact.
- **A fact is named by a bare id in one flat namespace.** No `quest:` prefix, mirroring ADR 0065's
  explicit refusal to let fate ids join a namespace that would "read as a working reference and
  silently grant nothing". The `quest:` ids in `ItemDef.sources` are **authoring metadata today**
  and stay that way until a reader exists.
- **Every accrual takes an explicit `amount` from a caller that owns the moment.** No timer, no
  `Time.get_ticks*`, no `get_tree()` in `core` (DEF-0111). The verb is `record(actor, id, amount)`.

**A durable world id is a stable string, and the playfield is a `WorldLocationDef` reference.**

- **`WorldLocationDef.location_id` is the durable world/region id.** It is already authored, already
  `StringName`, already the key `WorldApi.locations()` returns, and ADR 0047 already maps factions
  to locations. The player does not get a generated world id; the player is *at* a location id.
- **Spawning is a selection from an authored pool, not a generator.** `WorldApi.spawn_candidates()`
  returns locations filtered by tier and faction with their danger, so "random map" is a filtered
  deterministic pick from authored content. Rejected: procedural generation of the playfield — ADR
  0072/0073 make a domain's rooms assembled from a shared room kit, and a *handcrafted* domain
  assembles the same kit, so authoring the playfield is a `.tres` edit and randomness is only the
  **selection** among authored candidates.
- **Nothing in `core` reads `WorldLocationDef`.** The content type stays owned by `world`; `core`
  holds the durable *id* concept and `WorldApi` reads the defs. This is ADR 0082's split repeated:
  shared foundation in `core`, authored content in the owning module.

## Consequences

- Four ledgers become one. A quest step, an event trigger, an npc tally and an institutional fact
  all write the same row, so "the player did X" has exactly one home and one serialization.
- **The first reader of `ItemDef.sources` is the acquisition graph walk**, not a quest system. Until
  a runtime consumer exists, `sources` stays authoring metadata and the deferred entry stays open
  — this ADR does not claim to close it.
- `core` grows two files and one `module_data` key. `WorldFact` is reachable from every layer, so
  it must stay dependency-free (ADR 0065 / `contracts` precedent: `core` depends on `contracts`
  only).
- **Adding a fact-gated content type is a content edit**, because a requirement is data
  (`DestinyGate`, `SocialGate`, `BloodlineGate` all share that shape). A gate reading a fact is a
  new verb in one evaluator, not a new system.
- **No second clock.** A fact accrues only when a caller records it, so a "days survived" fact needs
  the clock DEF-0111 has not built. Recorded as deferred, not silently invented.
- Deferred / handed off: the ledger has no consumer until the quest module lands, so it ships as an
  untested-by-consumer primitive. That is deliberate and mirrors how `DestinyState` shipped — but a
  module that must not repeat ADR 0077 (five Accepted ADRs, zero symbols) must pair this ADR with
  the module that reads it.