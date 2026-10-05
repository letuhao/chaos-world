# 0222 `world_entry.gd` is deleted, and its frozen fixture becomes a shape any node-list file may have

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0214, and the live half of BL-0679
- Depends on: ADR 0221 (the 9 scenes go), ADR 0072 (a scene realizes, never sources)

## Context

`game/src/app/world_entry.gd` (196 lines) is a `Node2D` base that binds seven authored node
groups by name and publishes them. Measured:

- **Two production readers, both guarded to null.** `WorldStage._world_entry`
  (`world_stage.gd:529-532`) casts `_player.get_parent()` and `_register_nodes`
  (`:539-547`) returns early when it is null. With no scene extending the class in
  production, both are dead arms — `world_stage.gd:13` says so in its own docstring.
- **Nine unreferenced scenes extend it** (`game/scenes/worlds/*.tscn:3`,
  `game/scenes/domains/*.tscn:3` — `[ext_resource ... world_entry.gd]`), all deleted by
  ADR 0221. After that deletion its last referrers are gone.
- **One test constructs it by hand** (`tests/app/test_world_stage.gd:107-121`) to prove
  `mount` clamps an authored `SpawnPoint` past the bounds — a test that creates the thing it
  claims to be integrating with.
- **An arch test freezes its source shape.** `test_arch_rules.gd:111-121` transcribes nine
  lines verbatim as `WORLD_ENTRY`, and that fixture is load-bearing twice over: it is listed
  among "the legitimate app wiring files are not flagged" (`:405-414`) and it pins
  "a bound node array is wiring not a feature state table" (`:417-429`), whose docstring
  names `world_entry.gd` as the exemplar.

BL-0214 recorded the choice as blocked because "reviving it means editing a frozen shape".
That framing is the trap: the freeze is **not** a claim that the file is right. It is a
fixture for a *heuristic* (`app_state_signals`: "a member `Array` with no element type, or
one typed by a class THIS repo defines, counts as a `state-table` signal"). The heuristic is
right; the file it uses as its illustration is not load-bearing as a file.

## Decision

**Delete `world_entry.gd`. Keep the rule. Replace the fixture's provenance, not the rule.**

1. **Delete the file and its `class_name`.** Nothing in production may reference it after
   ADR 0221; `WorldStage` keeps its null-guarded arms, which cost nothing and are exactly
   right for a body parented to nothing.
2. **The arch fixture becomes SYNTHETIC and says so.** `WORLD_ENTRY` is renamed
   `ENGINE_NODE_LISTS` (or similar) and its docstring states: *"a transcription of a shape
   `app/` may hold — an engine-typed node list is wiring, not a state table. It was
   transcribed from `world_entry.gd`, deleted by ADR 0222; the shape it pins still ships in
   `app/domain_scene.gd`."* This is the ADR 0188 rule verbatim: **a guard that names a file
   expires with the file, and it expires RED.**
3. **Every assertion that used the fixture keeps using it**, with identical content. The
   `app_state_signals` rule, the "legitimate wiring" list and the "bound node array" case
   all still pass — because they are testing a *shape*, and the shape still has a real
   instance (`app/domain_scene.gd` binds engine node lists for the same reason).
4. **`tests/app/test_world_stage.gd:107-121` is repointed**, not deleted: it must still prove
   `mount` clamps an authored spawn, so it mounts a purpose-built `Node2D` stub exposing the
   one method `WorldStage` actually calls. If `WorldStage`'s only coupling to `WorldEntry` is
   `spawn_position()` + `resource_nodes()`, that is the whole interface and it should be an
   explicit seam, not a cast to a class that no longer exists.

### What must NOT happen

**The frozen fixture must not be deleted, and `test_arch_rules.gd` must not be edited to stop
checking.** Removing the fixture would delete the `state-table` heuristic's only negative
case that is not synthetic, and the heuristic would then have no exemplar in real code. ADR
0188 already lost one guard to exactly this move.

## Consequences

- **The shape is separated from the file**, which was the actual hazard: a future agent
  reading `world_entry.gd` was reading an *illustration* of a rule and inheriting a whole
  scene-base architecture from it. That is the same confusion ADR 0221 removes from the
  scene side.
- **`WorldStage`'s coupling to a scene base becomes explicit.** Today `_world_entry()` is a
  cast to a dead class; after this it is either a `Callable` seam or a local `Node2D` stub
  protocol. Either is a smaller surface than a 196-line inherited base.
- **BL-0679 closes its live half**: "`PlayerAdapter` is orphaned and `WorldEntry` is a base
  no scene extends" — the second clause is resolved here. The first (`PlayerAdapter`
  production wiring) is **not** resolved by this ADR and stays open.
- **Trade-off rejected: revive `WorldEntry` as the domain scene base.** Rejected because
  `DomainScene` already ships, is realized from a `DomainMap`, and documents at
  `domain_scene.gd:27-33` precisely why it is a sibling and not a subclass — a handcrafted
  marker-binder has no notion of a map built from data. Reviving would resurrect the *scene*
  base that ADR 0221 removes.
- **Trade-off rejected: keep the file as an unused base "for later".** ADR 0188: a published
  member with no non-test caller is DELETED. This is the file-level version of the same rule.
- **What would change my mind:** a *second* consumer that needs authored marker groups for a
  non-domain reason — e.g. a hand-authored hub town that is not a domain at all. Then the base
  earns itself, and it should be born fresh with a name that says what it is, not revived
  under a name that says "world".

## Migration order (not a code change; the sequence for whoever takes it)

1. ADR 0221 lands (scenes deleted) → `world_entry.gd` has no `.tscn` referrers.
2. Rename the fixture, add the provenance line. Assertions unchanged.
3. Repoint `test_world_stage.gd` to a stub.
4. Delete `world_entry.gd`; repoint `WorldStage`'s two arms.
5. `uv run python -m tools test --suite arch_rules` and `--suite world_stage`.