# 0170 a world advances in stages and a stage marks stale what it did not reconcile

- Status: Proposed
- Date: 2026-10-04
- Depends on: ADR 0168 (a coarse tick is a bucket, folded never replayed), ADR 0117 (one director, one beat), ADR 0113 (one monotone fact ledger), ADR 0114, ADR 0072 (a domain is a map), ADR 0089 / DEF-0111 (the caller owns time)

## Context

The world must span several scales of place at once — the player's immediate radius, a district, a map, a world, many worlds — and a month should disturb a district while a year disturbs a map. **The repo has no spatial concept to hang any of that on.** Measured across `game/src`: `sector`, `radius`, `area_of_effect` — zero hits. `region` exists only as Godot `NavigationRegion2D` scene nodes in `app/domain_scene.gd` (pathfinding). `scope` always means something else: `StatusDef.scope` (`modules/status/status_def.gd:174`). `stale` is refusal vocabulary — `nation_state.gd:123` `OUTCOME_STALEMATE` — never staleness of world state.

And the world advances **globally and instantly**. `WorldPulse._advance` (`app/world_pulse.gd:324-357`) hands the SAME period count to `EventApi` (`:342`) and to `InstitutionResolver` (`:349`), then runs `for index in periods:` (`:353`), so the whole world reacts on every pull. The cost grows with the size of the world, not with what the player can see. The three institution tiers already differ only in FREQUENCY and never in SCOPE — `NEAR/DISTANT/STRATEGIC_PERIODS = 1/4/16` (`app/institution_resolver.gd:48-50`), selected by `_every(total, step)` (`:159`).

Three place identities ship, none joined: `WorldLocationDef.location_id` (`modules/world/world_location_def.gd:6-13`, four `.tres`, one per world tier, ADR 0113's durable id stated verbatim at `world_spawn_state.gd:8`); `RoomDef.room_id` (map-unique, keyed in `DomainMap.rooms` `domain_map.gd:69`, adjacency from `RoomDef.exits` `room_def.gd:73`); `DomainDef.id` (`modules/world/domain_def.gd:6-8` — three fields, no grid, no link to a location).

## Decision

**A coarse stage does not walk every place in the world. It MARKS the world stale at that tier's resolution, and a place is RECONCILED only when someone needs it to be.** Three triggers, and no fourth: **(a)** the player is inside it, **(b)** authored content references it, **(c)** a coarse consumer asks. This is **lazy, demand-driven reconciliation**.

- **Scope identity is `WorldLocationDef.location_id`.** Nothing new is authored and nothing new is keyed.
  - It is already the durable world/region id (ADR 0113), already in the save (`world_spawn_state.gd:8`), already the key `app/` wires on (`world_stage.gd:464` compares the stage's `location_id` against the spawn ledger).
  - `RoomDef.room_id` is **map-unique**, so the same id names different rooms in two different maps and it cannot key a world-scale scope; it is retained as the INNER scope — what the player is standing in, reached through the domain facade.
  - `DomainDef.id` is one scale by itself (160 authored rows, ADR 0072) and a place in the world need not be a domain; it is the right scope for (b), not the key for the world.
  - **Never a spatial grid.** `DomainMap.extent: Vector2i` (`domain_map.gd:66`) is the GENERATOR's grid and is `Vector2i.ZERO` on a handcrafted map — `domain_minimap.gd:218` `_bounds` exists because a minimap sized from `extent` collapses. And `domain_paths.gd:15` states the layout is a pure function of the map with nothing this file is permitted to add (symmetric adjacency enforced at `:352`). A stored coordinate is a second description of a place that can disagree with the first.
  - This ADR does NOT claim a location IS one scale. `tier` names the resolution; a consumer needing something finer narrows by what it already holds.

- **Staleness is a per-tier stamp held by the owner of time, in `core/reconcile_stamp.gd`** — `location_id -> {tier -> last folded count}`, integers, beside `RealmRate` and `TimeLadder` (ADR 0168's argument: `core/` is a layer, so this costs zero new arch edges).
  - **Not a `WorldFact` field.** A fact is a thing that happened and record only raises (ADR 0113); a place folded to period 40 and then period 12 is a position on the ladder, not a monotone fact, and a mutable field on the ledger would make every reader decide whether it is fresh.
  - **Not in `app/`.** `app/` holds no ledger — `WorldPulse`'s own fields are counts with the reason at `world_pulse.gd:139-141` ("A count, not a table"), and `APP_STATE_MARKERS` forbids a state table (`domain_scene.gd:72-78`).
  - **It is derived and discardable, and that is the whole argument for it.** Delete the stamp and the next reconcile is simply a full pass. A ledger that can be wrong forever is a hazard; a stamp that is wrong only until the next reconcile is a cache.

- **One shared cap, and exceeding it fails loudly.** A reconcile pass clamps through `RowBudget.cap()` — "one shared helper rather than six local constants, because the value only means something as a single number: six independently-chosen caps would drift, and the one that matters is the smallest" (`core/row_budget.gd:17-20`). Precedent for bounding a per-place work list: `MAX_INTERACTABLES := 64` (`app/world_stage.gd:76`), re-checked at every append (`:481`, `:487`) "so a catalog that grew by a thousand rows still costs a bounded read" (`:457`).
  - **A reconcile that truncates reports nothing the player can see, and that is why it refuses instead.** `RowBudget` truncates a *screen* and says "N of M" (`row_budget.gd:14-16`, `truncated()`). A truncated reconcile leaves a place silently stale, and the player walks into a district that believes it is a decade old. So the cap is enforced by a `push_error` naming the place, the tier and the count, and the pass returns refused (AGENTS.md:56, :75: "If the exit condition cannot be met, make the feature fail loudly instead").
  - **The worklist is built before the loop and mutated by neither**, the shape `tests/arch_rules/test_no_unbounded_wait.gd` accepts. Scope descent is **iterative over an explicit worklist** so that rule can see it, and carries its own depth cap anyway, because that scan cannot see recursion (AGENTS.md:54; `core/content_scan.gd:22` `MAX_DEPTH := 32`).

- **A place returning to scope is FOLDED, never replayed** — ADR 0168's rule applied to scope, which this ADR references and does not restate. One bucket per tier crossed, divided by `_every`'s shape (`institution_resolver.gd:159`), one call per consumer.
  - **It must not re-offer facts those beats already recorded.** `world_pulse.gd:59-64` already pays for that hazard: a module-recorded beat re-offered "would write one occurrence twice because the ledger is monotone", which is why such facts are counted and never re-offered. `BeatDirector` records BEFORE it resolves (`beat_director.gd:133-135`), so a replayed beat writes a second occurrence AND pays a second grant — and the ledger has no refund. The ledger's count is authoritative for how much happened at a place; a reconcile READS it and never rewrites it. `WorldPulse.offer` remains the one offer point (`world_pulse.gd:68`, sinks at `:180-181`).
  - **Reconciliation changes what a place HAS BECOME, never what it PROMISES.** `DomainMinimap._zones` is deliberately NOT fogged (`domain_minimap.gd:179`) because a hazard must be visible before you stand in it, and its `Tier { ROOM, MINIBOSS, BOSS }` (`:29`) is ADR 0073's promise. Those previews read authored data, which no reconcile touches — otherwise "visible before you stand in it" and "stale until you stand in it" are the same sentence.

### Refused, with the trigger that would justify each

- **A mutable staleness field on `WorldFact`.** Trigger: none foreseeable — it is a second writer on the one monotone truth.
- **An authored `stale` field on `WorldLocationDef`.** Trigger: never — a `.tres` is the world's initial state (ADR 0050), never its state.
- **A per-place table in `app/`.** Trigger: never in this shape; `APP_STATE_MARKERS` forbids it (`domain_scene.gd:72-78`).
- **Stored coordinates or a sector grid.** Trigger: never — `domain_paths.gd:15`, `domain_map.gd:66`.
- **A middle-scope value object in `core/`.** Trigger: locations ship four rows, one per world tier, and a month must disturb a *district* — if a scope between a location and its own rooms is ever needed, add `core/scope_id.gd` as an id, never as a grid.
- **A reconcile-everything sweep on load.** Trigger: never — that is the global instant advance this ADR replaces, moved to a different moment.

### This inherits, and does not reopen

No `Time.get_ticks*` outside `app/` (ADR 0089, DEF-0111): a reconcile is triggered by a caller, never by a timer. **Zero new frame drivers** (`tests/app/test_status_clock.gd:222-230` pins three). `app/` wires and counts and holds no ledger. `WorldPulse.offer` stays the one beat offer point; `WorldFact` stays monotone. Coarse spans fold, never expand (ADR 0173, which supersedes ADR 0168's fixed ladder; the fold rule itself is inherited).

### The epoch: rewriting history without un-recording a fact

**A world carries an epoch. "Cleared" means the epoch advanced, never that a fact was withdrawn.** A Transcendent cultivator's retreat can span 10^9 years, during which lower worlds age, sect lineages rise and die whole, and some places are destroyed outright. The ledger records every one of those occurrences and they stay recorded; what changes is which epoch's state they describe.

- **A place's current state is DERIVED from (ledger, epoch)** — never stored as a mutable field, and never a decrement. `WorldFact` is monotone by design (ADR 0113: a fact is a thing that happened, `record` only raises) and ADR 0065 makes "fate is earned, never removed" a house rule. A negative write would break both.
- **Occurrences carry an epoch, so the ledger stays monotone while history still rewrites.** `founded_temple@1`, `temple_destroyed@1`, `founded_temple@2` are three true things, not one thing recorded, erased, and recorded again. The epoch a reader resolves against decides which occurrences still apply.
- **A destroyed world is RETIRED, not deleted.** It stops being current and a successor carries the next epoch. Nothing is ever un-recorded, so a save written in epoch 1 still reads correctly after the world has been rebuilt.
- **This is the reconcile stamp's sibling, and both answer "what is a place NOW" rather than "what happened."** The stamp says how stale a place is; the epoch says which history it is currently living. Same owner, same `core/` home, same discardability — delete the epoch and the world resolves to epoch 1, which is a full pass rather than a corruption.
- **What an epoch advance costs: the same budget as any other span** (ADR 0173's fixed event budget `C`). A billion-year skip does not get an unbounded number of events because it destroyed a world; it gets `C`. Exceeding it fails loudly rather than truncating.

## Consequences

- **A coarse crossing is O(1) in places.** One stamp write per magnitude and ZERO places visited. A reconcile is **O(places asked about)**, capped at `RowBudget.cap()`, and each place costs O(magnitudes crossed × consumers) by ADR 0173's fold rule. **A million-year sleep costs a handful of integer divisions and one stamp write per place asked about** — it leaves the rest of the world uniformly stale, which is a flag rather than a walk. Cost is independent of world size AND of elapsed time.
- Adding a scale of place costs a `.tres` row (`game/data/world/locations/*.tres`), not code — the same price ADR 0173 charges per named magnitude.
- **A place nobody visits stays authored and stale forever.** Accepted: nothing is owed to a place nothing reads.
- **Four locations ship today, and four cannot prove the middle scale.** A district between a location and its rooms is recorded here rather than silently absorbed, because `core/scope_id.gd` is a real edit to decide later.
- **Deferred, not decided here:** where the stamp and the epoch persist. Both are session state today, exactly like `_elapsed` — "a conversion buffer, not a save" (`world_pulse.gd:127-129`) — and the persistence home for coarse world time is owed to a follow-up ADR (ADR 0128).