extends TestCase

## The SHIPPED domain content, end to end — the suite the audit was missing.
##
## ADR 0073 makes `RoomDef` the shared kit and ADR 0074 makes every inhabitant an
## `Actor` minted by one constructor. Both claims are structural: a room may NAME an
## inhabitant that nothing ships, and `DomainSpawner._resolve` then mints nothing at
## all (domain_spawner.gd:190). That defect is invisible to every other domain suite,
## because each of them builds its own catalogue inline (test_domain_spawner.gd:68) and
## never asks what is authored on disk.
##
## So this suite reads the CONTENT TREE, never a hand-built fixture, and asserts the
## four claims that only shipped content can be wrong about:
##
##  1. every authored room loads and satisfies `DomainMapContract` for its band;
##  2. **every `inhabitant_id` any authored room names resolves to a real
##     `InhabitantDef` on disk** — this is the test that would have caught the
##     zero-defect;
##  3. every authored fixture carries the keys the one shared shape defines, and a
##     hazard publishes `mitigation_tags`;
##  4. every authored template generates a map that passes the contract AND, spawned
##     against a catalogue built from the SHIPPED tree, mints exactly `sum(count)`.
##
## Nothing here reads a fixture to decide a mechanism — the runtime consumer of
## `RoomDef.fixtures` is another agent's job. This suite is the contract that authored
## content and that consumer will agree on.

# ── the shipped content ───────────────────────────────────────────────────────

## The shipped room and template kits, read from disk rather than named. A tenth room
## or a fourth template added under those directories must be covered without editing
## this file — the same rule `test_domain_generator.gd:83` follows for `TEMPLATE_PATHS`.
const ROOM_DIR := "res://src/data/domains/rooms"
const TEMPLATE_DIR := "res://src/data/domains/templates"

## `DomainApi.INHABITANT_DIR` (`game/src/modules/domain/api.gd:33`), restated because
## the string is the SUBJECT of the claim rather than a dependency on the facade.
const INHABITANT_DIR := "res://src/data/domains/inhabitants"

## WHY the authored fixture shape is documented here and not beside the data: **a `#`
## comment inside a `.tres` `[resource]` block silently drops every property after it.**
## Found by bisection while authoring this kit — two files identical except for one
## comment line before `fixtures = ...` load fixtures as `[]` and lose every other
## later property, with no error and no warning. That is why every `.tres` under
## `game/src/data/domains/` carries zero `#` lines, and why the reasoning for each
## authored fixture lives in this suite rather than next to the fixture.
##
## What each key means, per kind:
##
## - `trap` — telegraphs for `telegraph_s`, fires ONCE, then is spent. It hurts THROUGH
##   `status_id` at `damage_share` per pulse for `duration_s`, never by a direct
##   subtraction (ADR 0075), and publishes the levers that reduce it. Tagged `trap_vein`.
##   Authored: `ash_gate_vein`, `ash_chamber_vein`, `ash_chamber_collapse`,
##   `storm_gallery_arc`, `storm_gallery_vent`.
## - `puzzle` — a formation of `nodes` (the five phases) that must be struck in the
##   authored `sequence`. A wrong node costs `wrong_status_id`, never health, because a
##   puzzle that kills you is a second fight wearing a costume. Tagged
##   `puzzle_formation`. Authored: `ash_arena_formation`, a water/wood/fire/metal
##   ordering, which is generating order and deliberately not the 五行 相生 order, so the
##   solution cannot be guessed from the sequence the phases are usually listed in.
## - `treasure` — ROOM-TYPE WEIGHTED, and what gates it is the shape: a `key_item_id`
##   names a key the player must hold (`treasure_keyed` — `ash_furnace_hoard`,
##   `ash_heart_hoard`); an empty key with no `treasure_boss_sealed` is open to anyone
##   who survives (`treasure_unkeyed` — `ash_camp_offering`, `tide_vault_hoard`); and
##   `treasure_boss_sealed` is gated by the fight itself (`ash_heart_hoard`, the core
##   whose only resident is the boss). `requires_realm` is an ORDINAL on the shared
##   ladder, never a magnitude curve, matching `ResourceNodeDef.realm` (ADR 0097).
##
## `ash_floor` — the room a run OPENS in — authors an EMPTY `fixtures` array on
## purpose, stated here because a `.tres` cannot say it in itself. The first trap a
## player meets is one they chose to walk past in `ash_gate`; a hazard in the entry
## floor is content nobody opted into.
const FIXTURE_SHAPE_NOTE := ""

## The rooms the kit author has DELIBERATELY retired, `room_id -> reason`.
##
## A retired room is a third legitimate answer to "how may this content be reachable?":
## authored, carried in a template's `room_pool`, or deleted with a reason. What is not
## legitimate is the state the kit shipped in — three `.tres` under `rooms/` that no
## template's `room_pool` and no `pins` names, so `DomainGenerator` could never place
## them and their treasure, puzzle and trap content was unreachable by any player.
##
## **Retiring is only honest while it is written down.** An id that stops being placed
## and is not named here is indistinguishable from the defect this ledger exists to end,
## so the list is the guard's other half: a room must be carried OR retired, never
## merely forgotten. Delete an entry once its `.tres` leaves `rooms/` — a reason for a
## room that no longer exists is noise that outlives the room.
const RETIRED_ROOMS: Dictionary = {}

## One seed across every template: the byte-identity and matrix claims belong to
## `test_domain_generator.gd`. This suite asks a different question — does the CONTENT
## populate a domain — and one fixed seed answers it for all three templates at once.
const CONTENT_SEED := 20261003

## The three authored fixture kinds, closed so an unrecognised kind is a failure
## rather than something this suite quietly skips.
const FIXTURE_KINDS: Array[String] = ["trap", "puzzle", "treasure"]

## The tags that make a fixture discoverable from a room's content rather than from
## its filename (ADR 0073: `tags` drive the encounter roster and hazard placement from
## ONE source, never a post-hoc heuristic).
const FIXTURE_TAGS: Array[String] = ["trap_vein", "puzzle_formation", "treasure_keyed"]

## The keys EVERY fixture carries, whatever its kind. One shape for all three kinds is
## the whole point: content and a future reader cannot disagree about the shape if
## there is only one.
const FIXTURE_KEYS: Array[String] = [
	"fixture_id",
	"kind",
	"tags",
	"position",
	"bounds",
	"reward_item_id",
	"reward_count",
	"key_item_id",
	"requires_realm",
	"telegraph_s",
	"damage_share",
	"status_id",
	"duration_s",
	"mitigation_tags",
]

## A puzzle is the one kind with its own keys, because it is the one kind with an
## internal shape a reader has to know: which nodes exist, and in what order.
const PUZZLE_KEYS: Array[String] = ["nodes", "sequence", "wrong_status_id"]

## The contract problems each room is KNOWN to carry, named rather than waived.
##
## **EMPTY, and empty on purpose.** It used to hold `{&"ash_gate": 1}`: `ash_gate`
## authored a `cinder_hound` at role `mob` (hostile, `DomainRoles.HOSTILE_ROLES`) AND
## an `ember_pilgrim` at role `rival_cultivator` (not hostile, a different set), and
## `_roster_fits_band` (`domain_map_contract.gd:130-144`) admits only `npc` and
## `rival_cultivator` in `social`, only hostile roles everywhere else, and NO refs at
## all in `empty`. No band value admitted that roster, so no band value fixed it.
##
## The waiver is retired rather than merely widened, because a waiver is the failure
## mode this suite exists to detect: an unknown count would let the COUNT hide a
## second, different problem in the same room. The content now satisfies the contract
## on its own — `ash_gate` (band `contact`) authors the hostile mob alone, and the
## pilgrim moved to `ash_camp`, whose band `social` admits a rival cultivator — so a
## key added here has to be one a reviewer can defend against a real defect.
##
## Band semantics remain `domain_map_contract.gd`'s to decide. Should a future author
## want a room to hold a rival cultivator AND a fight, the answer is a per-ROLE
## presence rule THERE, not a value waived here.
const KNOWN_DEFECTS: Dictionary = {}

## The seeds the reachability guard walks. `test_domain_generator.gd` holds its own
## determinism and contract claims over a 64-seed matrix and this suite reuses that
## number rather than inventing a second width: the leaf COUNT is what decides whether
## a pool this size is fully dealt, and a matrix is the only way to see a def crowded
## out by a single shallow roll. Bounded by `REACHABILITY_SEED_COUNT` itself.
const REACHABILITY_SEED_COUNT := 64


## Every `while` below is over a directory listing, which `DirAccess.get_next()`
## terminates with `""` — the bounded form `tests/arch_rules/test_no_unbounded_wait.gd`
## rule 2 accepts. Nothing here waits on game state.
func _tres_files(dir_path: String) -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return names
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with(".") and not dir.current_is_dir() and entry.ends_with(".tres"):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


## The shipped rooms, sorted by file name so the walk is a property of the tree and
## not of a directory listing's order.
func _authored_rooms() -> Array[RoomDef]:
	var out: Array[RoomDef] = []
	for file_name in _tres_files(ROOM_DIR):
		var room := load("%s/%s" % [ROOM_DIR, file_name]) as RoomDef
		if room != null:
			out.append(room)
	return out


## The shipped inhabitants as a `DomainSpawner` catalogue, keyed by `String` exactly
## as a loader would key them — `spawn_map` reads `inhabitant_id` off a ref as a
## `StringName` and `_resolve` tries both key types for that reason
## (domain_spawner.gd:272).
func _inhabitant_catalogue() -> Dictionary:
	var out: Dictionary = {}
	for file_name in _tres_files(INHABITANT_DIR):
		var def := load("%s/%s" % [INHABITANT_DIR, file_name]) as InhabitantDef
		if def != null:
			out[String(def.inhabitant_id)] = def
	return out


## `{room_id, fixture}` for every fixture in every shipped room, in canonical room and
## authored order so the walks above are a property of the tree.
func _authored_fixtures() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room in _authored_rooms():
		for fixture in room.fixtures:
			out.append({"room_id": String(room.room_id), "fixture": fixture})
	return out


## The core actor spine, injected so a spawned inhabitant is assembled the way `app/`
## assembles one (`DomainSpawner.set_minter`). The default minter does this too;
## installing it explicitly keeps the claim under test about CONTENT.
func _core_minter(def_id: StringName, base: Dictionary) -> Actor:
	var actor := Actor.new(def_id, base)
	actor.attach_core_resources()
	DomainSpawner.attach_high_tier(actor)
	return actor


## A placement the spawner can always answer, standing in for the scene's own. The
## claim is about the COUNT, so the point only has to be a real `Vector2`.
##
## `_room_id` is the spawner's room discriminator and this fixture reads no room:
## distinct rooms would need distinct points, and every claim made through this
## callable is a COUNT. Prefixed rather than dropped so the signature stays the one
## `DomainSpawner.spawn_map` calls, the same convention
## `test_domain_spawner._position_of` already uses.
func _position_of(_room_id: StringName, ref_id: String, index: int) -> Vector2:
	return Vector2(float(index) * 16.0, float(ref_id.length()))


func setup() -> void:
	DomainSpawner.set_minter(Callable(self, "_core_minter"))


func teardown() -> void:
	# The runner calls this after EVERY test, and `set_minter` is process-wide state:
	# left installed, it leaks into whatever suite runs next.
	DomainSpawner.set_minter(Callable())


# ── 1. the authored rooms load and pass the contract ──────────────────────────


## Each authored room is held to the contract INSIDE a two-room map, because
## `_problems_for_rooms` is the half of `assert_valid` a room can fail on its own; the
## exit and connectivity halves belong to the generated map, asserted in section 4.
##
## The room is ROUND-TRIPPED before it is added, never handed over as loaded:
## `ResourceLoader` caches a `.tres`, so writing an exit onto the shared instance would
## persist into every later test in this file and into every suite that runs after it.
##
## `KNOWN_DEFECTS` is read BEFORE the assertion rather than being left as a known
## failure. Writing `assert_eq(problems.size(), 1, ...)` to go green would let the count
## itself hide a second, different problem in the same room; this way the suite is green
## AND still fails loudly the moment that room breaks a second way. See
## `_pre_known_defects` for why `ash_gate` is on the list at all.
func test_every_authored_room_loads_and_passes_the_contract() -> void:
	var rooms := _authored_rooms()
	assert_eq(rooms.is_empty(), false, "the shipped room kit is not empty")
	for room in rooms:
		assert_eq(
			room.room_id != &"",
			true,
			"a shipped room authors an id (%s)" % room.resource_path.get_file()
		)
		var problems := DomainMapContract.assert_valid(_scratch_map(room))
		assert_eq(
			problems.size(),
			_pre_known_defects(room),
			"room '%s' passes the contract: %s" % [String(room.room_id), ", ".join(problems)]
		)


func _pre_known_defects(room: RoomDef) -> int:
	return int(KNOWN_DEFECTS.get(room.room_id, 0))


## A two-room map: a COPY of the room under test, and a plain `empty`-band neighbour
## it exits to. Both directions are declared, because `_problems_for_connectivity`
## walks from `entry` and an unreachable room is a failure that has nothing to do with
## the room's own content. The neighbour carries no refs, so the `empty` band is legal.
func _scratch_map(room: RoomDef) -> DomainMap:
	var map := DomainMap.new(Vector2i(64, 48), 0)
	var copy := RoomDef.from_dict(room.to_dict())
	copy.exits = [] as Array[StringName]
	var neighbour_id := StringName("%s_neighbour" % String(room.room_id))
	map.add_room(copy)
	var neighbour := RoomDef.new()
	neighbour.room_id = neighbour_id
	neighbour.kind = &"floor"
	neighbour.roster_band = &"empty"
	neighbour.exits = [copy.room_id] as Array[StringName]
	map.add_room(neighbour)
	copy.exits = [neighbour_id] as Array[StringName]
	map.entry_room = copy.room_id
	return map


# ── 2. every named inhabitant RESOLVES — the test the audit was missing ────────


## **The defect this suite exists for.** Every `inhabitant_id` an authored room names
## must be a def that SHIPS. `DomainSpawner.spawn_map` refuses an unresolvable ref by
## name and mints nothing (domain_spawner.gd:183), so a room naming nothing resolves
## to an empty room with no assertion anywhere catching it.
func test_every_named_inhabitant_resolves_to_a_shipped_def() -> void:
	var catalogue := _inhabitant_catalogue()
	assert_eq(catalogue.is_empty(), false, "the shipped inhabitant catalogue is not empty")
	var unresolved: Array[String] = []
	for room in _authored_rooms():
		for ref in room.actor_spawn_refs:
			var inhabitant_id := String(ref.get("inhabitant_id", ""))
			if not catalogue.has(inhabitant_id):
				unresolved.append(
					(
						"room '%s' ref '%s' names '%s'"
						% [String(room.room_id), String(ref.get("ref_id", "")), inhabitant_id]
					)
				)
	assert_eq(
		unresolved.is_empty(),
		true,
		(
			"every authored inhabitant_id resolves to a shipped InhabitantDef; unresolved: %s"
			% ", ".join(unresolved)
		)
	)


## And the count is real rather than an artefact of a partial scan: the ids the rooms
## name and the defs that ship are the same set, so no `.tres` sits unused and none is
## doing duty for two species.
func test_the_authored_roster_and_the_shipped_defs_are_the_same_set() -> void:
	var catalogue := _inhabitant_catalogue()
	var named: Dictionary = {}
	for room in _authored_rooms():
		for ref in room.actor_spawn_refs:
			named[String(ref.get("inhabitant_id", ""))] = true
	assert_eq(
		named.size(),
		catalogue.size(),
		"every shipped def is placed by an authored room, and every named id is shipped"
	)
	assert_eq(named.size() >= 9, true, "the nine species the rooms name all ship")


## A def's identity is its `inhabitant_id`, not its filename, and a duplicated id
## would let the catalogue silently shadow one species with another.
func test_shipped_inhabitant_ids_are_unique_and_self_naming() -> void:
	var seen: Dictionary = {}
	for file_name in _tres_files(INHABITANT_DIR):
		var def := load("%s/%s" % [INHABITANT_DIR, file_name]) as InhabitantDef
		if def == null:
			continue
		assert_eq(
			seen.has(String(def.inhabitant_id)),
			false,
			"'%s' is not defined twice" % String(def.inhabitant_id)
		)
		seen[String(def.inhabitant_id)] = true
		assert_eq(
			file_name.get_basename(),
			String(def.inhabitant_id),
			"'%s' is named for the id it defines" % file_name
		)
		assert_eq(def.display_name.is_empty(), false, "'%s' carries a display name" % file_name)
	assert_eq(seen.size() >= 9, true, "at least nine distinct species ship")


## A CULTIVATING role with no realm is refused by the spawner outright
## (domain_spawner.gd:88), so a shipped def that claims to cultivate must name a realm
## the shared ladder knows — otherwise every room placing it spawns nothing.
func test_every_cultivating_def_names_a_real_ladder_realm() -> void:
	var ladder := RealmDefaults.ladder()
	for file_name in _tres_files(INHABITANT_DIR):
		var def := load("%s/%s" % [INHABITANT_DIR, file_name]) as InhabitantDef
		if def == null or not def.cultivates:
			continue
		assert_eq(
			ladder.has(def.realm_id),
			true,
			"'%s' cultivates at a real realm, not '%s'" % [file_name, String(def.realm_id)]
		)


## `hostile` is the def's OPT-IN and the role is the PERMISSION (`domain_roles.gd:38`);
## a def that sets it for a role which cannot be hostile is authored noise, and one
## that forgets it for a role which is leaves a mob that walks past you.
func test_hostility_agrees_with_the_role_the_rooms_assign() -> void:
	var by_id := _inhabitant_catalogue()
	for room in _authored_rooms():
		for ref in room.actor_spawn_refs:
			var inhabitant_id := String(ref.get("inhabitant_id", ""))
			var def := by_id.get(inhabitant_id, null) as InhabitantDef
			if def == null:
				continue
			var role := StringName(ref.get("role", ""))
			assert_eq(
				def.hostile,
				DomainRoles.is_hostile(role),
				(
					"'%s' hostility matches the '%s' role room '%s' assigns it"
					% [inhabitant_id, String(role), String(room.room_id)]
				)
			)


## Magnitude, not class: a mob is a smaller number than the mini-boss it shares a room
## with, and the mini-boss a smaller number than the boss. ADR 0074 forbids reaching
## for a subclass here, so the ONLY place the ordering can live is `base`.
func test_mobs_are_weaker_than_minibosses_which_are_weaker_than_bosses() -> void:
	var by_id := _inhabitant_catalogue()
	var mobs: Array[float] = []
	var minibosses: Array[float] = []
	var bosses: Array[float] = []
	for room in _authored_rooms():
		for ref in room.actor_spawn_refs:
			var def := by_id.get(String(ref.get("inhabitant_id", "")), null) as InhabitantDef
			if def == null:
				continue
			var physique := float(def.base.get(Stat.PHYSIQUE, 0.0))
			match StringName(ref.get("role", "")):
				DomainRoles.MOB:
					mobs.append(physique)
				DomainRoles.MINIBOSS:
					minibosses.append(physique)
				DomainRoles.BOSS:
					bosses.append(physique)
	assert_eq(mobs.is_empty(), false, "the shipped rooms author at least one mob")
	assert_eq(minibosses.is_empty(), false, "and at least one miniboss")
	assert_eq(bosses.is_empty(), false, "and at least one boss")
	assert_eq(
		max_of(mobs) < min_of(minibosses),
		true,
		"a mob's physique tops out below the weakest miniboss's"
	)
	assert_eq(max_of(minibosses) < min_of(bosses), true, "and every miniboss below the boss's")


# ── 3. the authored fixtures carry the shared shape ───────────────────────────


## Every fixture in every shipped room carries the full shared key set. A fixture that
## omits `mitigation_tags` is readable as a hazard with no named counterplay, which is
## the ADR 0075 rule the contract enforces for a ZONE and nothing yet enforced here.
func test_every_authored_fixture_carries_the_shared_shape() -> void:
	var fixtures := _authored_fixtures()
	assert_eq(fixtures.is_empty(), false, "the shipped rooms author at least one fixture")
	for entry in fixtures:
		var fixture: Dictionary = entry["fixture"]
		var missing := _missing_shape(fixture)
		assert_eq(
			missing.is_empty(),
			true,
			(
				"fixture '%s' in room '%s' carries the shared shape; missing: %s"
				% [
					String(fixture.get("fixture_id", "")),
					String(entry["room_id"]),
					", ".join(missing),
				]
			)
		)


## A HAZARD publishes its counterplay. `trap` and `puzzle` both cost a player
## something, so both must name the lever that reduces it — the ADR 0075 rule applied
## to the fixture surface the audit left empty.
func test_every_hazard_publishes_a_non_affinity_lever() -> void:
	var hazards := 0
	for entry in _authored_fixtures():
		var fixture: Dictionary = entry["fixture"]
		var kind := StringName(fixture.get("kind", ""))
		if kind != &"trap" and kind != &"puzzle":
			continue
		hazards += 1
		var fixture_id := String(fixture.get("fixture_id", ""))
		var levers: Array = fixture.get("mitigation_tags", [])
		assert_eq(
			levers.is_empty(),
			false,
			"fixture '%s' is a '%s' and publishes no mitigation_tags" % [fixture_id, String(kind)]
		)
		var non_affinity := false
		for lever in levers:
			assert_eq(
				EnvironmentZoneDef.LEVERS.has(StringName(lever)),
				true,
				"fixture '%s' mitigation_tag '%s' names a real lever" % [fixture_id, String(lever)]
			)
			if StringName(lever) != EnvironmentZoneDef.LEVER_AFFINITY:
				non_affinity = true
		assert_eq(
			non_affinity,
			true,
			(
				(
					"fixture '%s' is mitigated by affinity alone, so a player with the wrong "
					% fixture_id
				)
				+ "spirit root has no authored counterplay"
			)
		)
	assert_eq(hazards > 0, true, "at least one hazard ships")


## ADR 0075: a hazard hurts THROUGH a status, never by subtracting health. A trap with
## no `status_id`, or with a `damage_share` and nothing to carry it, is the bespoke
## damage channel the ADR forbids.
func test_every_trap_telegraphs_then_hurts_through_a_status() -> void:
	var traps := 0
	for entry in _authored_fixtures():
		var fixture: Dictionary = entry["fixture"]
		if StringName(fixture.get("kind", "")) != &"trap":
			continue
		traps += 1
		var fixture_id := String(fixture.get("fixture_id", ""))
		assert_eq(
			String(fixture.get("status_id", "")) != "",
			true,
			(
				(
					"trap '%s' carries a status_id; a trap that subtracts health directly is "
					% fixture_id
				)
				+ "the bespoke channel ADR 0075 forbids"
			)
		)
		assert_eq(
			float(fixture.get("telegraph_s", 0.0)) > 0.0,
			true,
			"trap '%s' telegraphs before it fires" % fixture_id
		)
		assert_eq(
			float(fixture.get("damage_share", 0.0)) > 0.0,
			true,
			"trap '%s' authors the damage share its status spends" % fixture_id
		)
		assert_eq(
			float(fixture.get("duration_s", 0.0)) > 0.0,
			true,
			"trap '%s' authors how long the status runs" % fixture_id
		)
		assert_eq(
			_tagged(fixture, &"trap_vein"), true, "trap '%s' is marked trap_vein" % fixture_id
		)
	assert_eq(traps > 0, true, "at least one trap ships")


## A puzzle's whole shape is the nodes and the ORDER they must be struck in. A sequence
## naming a node the formation does not carry can never be solved, and a wrong strike
## must cost a STATUS rather than health.
func test_every_puzzle_has_an_order_a_player_can_actually_solve() -> void:
	var puzzles := 0
	for entry in _authored_fixtures():
		var fixture: Dictionary = entry["fixture"]
		if StringName(fixture.get("kind", "")) != &"puzzle":
			continue
		puzzles += 1
		var fixture_id := String(fixture.get("fixture_id", ""))
		var nodes: Array = fixture.get("nodes", [])
		var sequence: Array = fixture.get("sequence", [])
		assert_eq(nodes.is_empty(), false, "puzzle '%s' authors its nodes" % fixture_id)
		assert_eq(sequence.size(), nodes.size(), "puzzle '%s' sequences every node" % fixture_id)
		for node in sequence:
			assert_eq(
				nodes.has(node),
				true,
				"puzzle '%s' sequences node '%s', which it places" % [fixture_id, String(node)]
			)
		assert_eq(
			_distinct(sequence).size(),
			sequence.size(),
			"puzzle '%s' strikes each node once" % fixture_id
		)
		assert_eq(
			String(fixture.get("wrong_status_id", "")) != "",
			true,
			"puzzle '%s' costs a status for a wrong node, never health" % fixture_id
		)
		assert_eq(
			_tagged(fixture, &"puzzle_formation"),
			true,
			"puzzle '%s' is marked puzzle_formation" % fixture_id
		)
	assert_eq(puzzles > 0, true, "at least one puzzle ships")


## A treasure is ROOM-TYPE WEIGHTED, and the three shapes are told apart by what gates
## them: a key you must hold, nothing at all, or the boss standing in the way. A
## treasure that gates on nothing reads the same as one that gates on a fight.
func test_treasure_is_weighted_by_room_type_and_says_what_gates_it() -> void:
	var keyed := 0
	var unkeyed := 0
	var boss_sealed := 0
	for entry in _authored_fixtures():
		var fixture: Dictionary = entry["fixture"]
		if StringName(fixture.get("kind", "")) != &"treasure":
			continue
		var fixture_id := String(fixture.get("fixture_id", ""))
		assert_eq(
			String(fixture.get("reward_item_id", "")) != "",
			true,
			"treasure '%s' pays something out" % fixture_id
		)
		assert_eq(
			int(fixture.get("reward_count", 0)) > 0,
			true,
			"treasure '%s' authors how much it pays" % fixture_id
		)
		if String(fixture.get("key_item_id", "")) != "":
			keyed += 1
			assert_eq(
				_tagged(fixture, &"treasure_keyed"),
				true,
				"treasure '%s' is keyed, so it says so" % fixture_id
			)
		elif _tagged(fixture, &"treasure_boss_sealed"):
			boss_sealed += 1
		else:
			unkeyed += 1
			assert_eq(
				_tagged(fixture, &"treasure_unkeyed"),
				true,
				"treasure '%s' is unkeyed, so it says so" % fixture_id
			)
		# A realm gate is an ORDINAL on the shared ladder, never a magnitude curve
		# (`ResourceNodeDef.realm`, ADR 0097), so a def naming one names a REAL realm.
		var realm := String(fixture.get("requires_realm", ""))
		if realm != "":
			assert_eq(
				RealmDefaults.ladder().has(StringName(realm)),
				true,
				"treasure '%s' gates on a real ladder realm, not '%s'" % [fixture_id, realm]
			)
	assert_eq(keyed > 0, true, "at least one treasure is KEYED")
	assert_eq(unkeyed > 0, true, "at least one treasure is UNKEYED")
	assert_eq(boss_sealed > 0, true, "at least one treasure is SEALED BEHIND A BOSS")


## The three kinds the requirement names all exist in the shipped kit, and each is
## discoverable by its tag rather than only by a filename nobody reads.
func test_all_three_fixture_kinds_ship_and_are_tagged() -> void:
	var by_kind: Dictionary = {}
	for entry in _authored_fixtures():
		var fixture: Dictionary = entry["fixture"]
		var kind := String(fixture.get("kind", ""))
		assert_eq(
			FIXTURE_KINDS.has(kind),
			true,
			(
				"fixture '%s' is one of the three authored kinds"
				% String(fixture.get("fixture_id", ""))
			)
		)
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1
	for kind in FIXTURE_KINDS:
		assert_eq(
			int(by_kind.get(kind, 0)) > 0,
			true,
			"the shipped kit authors at least one '%s' fixture" % kind
		)
	var fixtures := _authored_fixtures()
	for tag in FIXTURE_TAGS:
		var found := false
		for entry in fixtures:
			if _tagged(entry["fixture"], StringName(tag)):
				found = true
		assert_eq(found, true, "a shipped fixture carries the '%s' tag" % tag)


## Every fixture is JSON-clean and round-trips. `RoomDef.to_dict` duplicates each
## fixture verbatim (room_def.gd:117), so a leaked `Vector2i` or `StringName` reaches a
## save file and breaks it without breaking a single assertion above.
func test_every_authored_fixture_round_trips_through_json() -> void:
	var fixtures := _authored_fixtures()
	assert_eq(fixtures.is_empty(), false, "the shipped kit authors fixtures at all")
	for entry in fixtures:
		var fixture: Dictionary = entry["fixture"]
		var parsed: Variant = JSON.parse_string(JSON.stringify(fixture))
		assert_eq(
			parsed is Dictionary,
			true,
			(
				(
					"fixture '%s' is JSON-clean: a leaked Vector2i or StringName would break "
					% String(fixture.get("fixture_id", ""))
				)
				+ "every save it rides in"
			)
		)


# ── 4. the end-to-end proof: authored content populates a domain ──────────────


## **The end-to-end claim.** For each shipped template: generate a map, hold it to the
## contract, then spawn it against a catalogue built from the SHIPPED inhabitant tree.
## The minted count must equal `sum(count)` over the map's own refs — no more (a
## placeholder minted for an unresolvable ref) and no fewer (a ref silently skipped).
##
## With zero `InhabitantDef`s on disk this assertion read 0 against a roster of 12 and
## failed loudly, which is exactly what an invisible defect should do.
func test_every_template_spawns_every_actor_it_authored() -> void:
	var catalogue := _inhabitant_catalogue()
	var templates := _tres_files(TEMPLATE_DIR)
	assert_eq(templates.is_empty(), false, "the shipped template kit is not empty")
	for file_name in templates:
		var template := load("%s/%s" % [TEMPLATE_DIR, file_name]) as DomainTemplateDef
		assert_ne(template, null, "template '%s' loads" % file_name)
		if template == null:
			continue
		var map := DomainGenerator.generate(template, CONTENT_SEED)
		assert_ne(map, null, "template '%s' generates a map at seed %d" % [file_name, CONTENT_SEED])
		if map == null:
			continue
		var problems := DomainMapContract.assert_valid(map)
		assert_eq(
			problems.size(),
			0,
			"template '%s' seed %d: %s" % [file_name, CONTENT_SEED, ", ".join(problems)]
		)
		var expected := _expected_population(map)
		var spawned := DomainSpawner.spawn_map(map, catalogue, Callable(self, "_position_of"))
		assert_eq(
			spawned.size(),
			expected,
			(
				"template '%s' seed %d mints one Actor per authored inhabitant (%d)"
				% [file_name, CONTENT_SEED, expected]
			)
		)


## The spawned actors are the CONTENT's, not stand-ins: every one carries the role the
## room authored, in the canonical order `spawn_map` walks. This is the whole ADR 0074
## claim, made against shipped `.tres` rather than against a hand-built catalogue.
func test_every_spawned_actor_carries_its_authored_role() -> void:
	var template := _template("flame_valley_depths.tres")
	if template == null:
		return
	var map := DomainGenerator.generate(template, CONTENT_SEED)
	assert_ne(map, null, "the deepest shipped template generates a map")
	if map == null:
		return
	var spawned := DomainSpawner.spawn_map(
		map, _inhabitant_catalogue(), Callable(self, "_position_of")
	)
	assert_eq(
		_roles_of_actors(spawned),
		_roles_of_refs(map),
		"the whole roster, one entry per authored instance, in canonical ref order"
	)
	for actor in spawned:
		assert_eq(actor is Actor, true, "a spawned inhabitant is an Actor")


## Generation deep-copies every def, so a fixture authored on the room survives into
## the realized map rather than being dropped by `_copy_def` (domain_generator.gd:920).
## Without this the generated half of a domain would silently lose every hazard.
func test_generated_rooms_carry_their_authored_fixtures() -> void:
	var authored := 0
	for room in _authored_rooms():
		authored += room.fixtures.size()
	assert_eq(authored > 0, true, "the shipped kit authors fixtures at all")
	var template := _template("ember_grotto.tres")
	if template == null:
		return
	var map := DomainGenerator.generate(template, CONTENT_SEED)
	assert_ne(map, null, "the shallowest shipped template generates a map")
	if map == null:
		return
	var carried := 0
	for room_id in map.room_ids_sorted():
		carried += (map.room(room_id) as RoomDef).fixtures.size()
	assert_eq(
		carried > 0,
		true,
		"a generated domain still carries the fixtures its rooms authored (%d on disk)" % authored
	)


# ── 5. every authored room is reachable, or is retired on the record ──────────


## **The rule this suite did not have until three rooms were unreachable: a room the
## kit ships is a room a player can walk into.**
##
## The rooms this guards are named, because the defect was invisible and this is the
## test that would have caught it: `ash_gate` (the threshold trap `ash_gate_vein`),
## `ash_arena` (the only authored PUZZLE, `ash_arena_formation`, and the trial-band
## mini-boss) and `ash_heart` (the only authored `treasure_boss_sealed` hoard and the
## only BOSS roster) were all `.tres` files under `rooms/` that **no template's
## `room_pool` and no `pins` named**. `DomainGenerator` draws unfilled leaves from the
## pool and nowhere else (`_deal`), so those three rooms could never be realized —
## a whole third of the authored treasure, puzzle and trap content that no player
## could reach and no other domain suite could see, because each of those builds its
## own map inline and never asks what the shipped kit carries.
##
## Membership in a `room_pool` is the reachability claim rather than a coincidence of
## it, for the reason ADR 0073 states: the pool IS the shared kit, and a generator
## "picks and places; it does not invent room content". So a def in the pool is placed
## in any map with enough leaves, and a def outside it is placed by nothing. Carrying
## the def is therefore the sufficient condition this asserts, and it is checked per
## template so the failure names WHICH one stopped carrying the room.
func test_every_authored_room_is_carried_by_a_template_or_retired_with_a_reason() -> void:
	var carried: Dictionary = {}
	var by_id: Dictionary = {}
	for file_name in _tres_files(TEMPLATE_DIR):
		var template := load("%s/%s" % [TEMPLATE_DIR, file_name]) as DomainTemplateDef
		assert_ne(template, null, "template '%s' loads" % file_name)
		if template == null:
			continue
		by_id[String(template.template_id)] = template
		var named: Array[String] = []
		for room_def in template.room_pool:
			named.append(String(room_def.room_id))
		# A pin names a def for a STORY room, and `_pinned_defs` refuses one outside the
		# pool (`domain_generator.gd:837`) — so it is a second, independent way a room
		# becomes reachable, and is asserted as such rather than assumed to agree.
		for pin in template.pins:
			if pin != null and pin.room_def != null:
				named.append(String(pin.room_def.room_id))
		for room_id in named:
			carried[room_id] = String(template.template_id)

	## Three distinct ways this rule can be broken, and the failure message has to name
	## which one happened: a room nobody places and nobody retired, a name a template
	## carries that no `.tres` defines (a dangling `ExtResource`, which the generator
	## realizes as a hollow room), and a retirement that names a room which does not
	## exist or gives no reason. Any of those is authoring noise dressed as a decision.
	var unreachable: Array[String] = []
	var dangling: Array[String] = []
	var authored_ids := _authored_room_ids()
	for room_id in carried:
		if not authored_ids.has(String(room_id)):
			dangling.append(
				(
					"template '%s' carries '%s', which no room .tres defines"
					% [String(carried[room_id]), String(room_id)]
				)
			)
	for room_id in authored_ids:
		if carried.has(String(room_id)) or not RETIRED_ROOMS.has(String(room_id)):
			continue
		if String(RETIRED_ROOMS[room_id]).strip_edges().is_empty():
			dangling.append("RETIRED_ROOMS retires '%s' with no reason" % String(room_id))
	for room_id in RETIRED_ROOMS:
		if not authored_ids.has(String(room_id)):
			dangling.append(
				"RETIRED_ROOMS names '%s', which no room .tres defines" % String(room_id)
			)
	for room in _authored_rooms():
		var room_id := String(room.room_id)
		if carried.has(room_id) or RETIRED_ROOMS.has(room_id):
			continue
		unreachable.append(
			(
				("room '%s' is carried by no template and is not in RETIRED_ROOMS; a " % room_id)
				+ "player can never reach it"
			)
		)

	assert_eq(by_id.is_empty(), false, "the authored template kit is not empty")
	assert_eq(unreachable.is_empty(), true, "; ".join(unreachable))
	assert_eq(dangling.is_empty(), true, "; ".join(dangling))


## The authored `room_id`s this template carries, through either door — its `room_pool`
## or a `pins` entry. Bounded by the two arrays; no loop whose bound is derived from
## anything but the template's own content.
func _carried_ids(template: DomainTemplateDef) -> Dictionary:
	var out: Dictionary = {}
	for room_def in template.room_pool:
		out[String(room_def.room_id)] = true
	for pin in template.pins:
		if pin != null and pin.room_def != null:
			out[String(pin.room_def.room_id)] = true
	return out


## The authored def ids a generated map actually built, as the part of each namespaced
## room id before the `#`.
func _built_def_ids(map: DomainMap) -> Dictionary:
	var out: Dictionary = {}
	for room_id in map.room_ids_sorted():
		out[String(room_id).split("#", false)[0]] = true
	return out


## Every authored `room_id`, read from the shipped rooms rather than named. A second
## reader of the same tree in this file would be a copy that could drift; this one is
## the list both the reachability guard and its dangling-reference check ask.
func _authored_room_ids() -> Dictionary:
	var out: Dictionary = {}
	for room in _authored_rooms():
		out[String(room.room_id)] = true
	return out


# ── helpers ──────────────────────────────────────────────────────────────────


func _template(file_name: String) -> DomainTemplateDef:
	return load("%s/%s" % [TEMPLATE_DIR, file_name]) as DomainTemplateDef


## `sum(count)` over the map's refs — what the map AUTHORED, read off the map itself so
## the assertion cannot be satisfied by the thing under test.
func _expected_population(map: DomainMap) -> int:
	var total := 0
	for ref in map.spawn_refs():
		total += int(ref.get("count", 1))
	return total


## The roles a map's refs name, one entry per authored INSTANCE, in `spawn_map`'s order.
func _roles_of_refs(map: DomainMap) -> Array[String]:
	var out: Array[String] = []
	for ref in map.spawn_refs():
		var role := String(ref.get("role", ""))
		for _instance in int(ref.get("count", 1)):
			out.append(role)
	return out


## The same shape, read off the minted actors.
func _roles_of_actors(actors: Array[Actor]) -> Array[String]:
	var out: Array[String] = []
	for actor in actors:
		out.append(String(DomainSpawner.role_of(actor)))
	return out


## The shared shape's keys `fixture` is missing, plus the puzzle's own when it is one.
func _missing_shape(fixture: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for key in FIXTURE_KEYS:
		if not fixture.has(key):
			missing.append(key)
	if StringName(fixture.get("kind", "")) == &"puzzle":
		for key in PUZZLE_KEYS:
			if not fixture.has(key):
				missing.append(key)
	return missing


## Whether an authored fixture carries `tag`. A `Dictionary` has no `has_tag` — that is
## `RoomDef`'s and `InhabitantDef`'s — so the membership question is asked of the
## `tags` array the shape actually defines.
func _tagged(fixture: Dictionary, tag: StringName) -> bool:
	var tags: Array = fixture.get("tags", [])
	return tags.has(tag) or tags.has(String(tag))


## The unique values in `values`, first-seen order. A bounded `for`; there is no
## `Array.uniq` in this GDScript and hand-rolling it keeps the assertion readable.
func _distinct(values: Array) -> Array:
	var out: Array = []
	for value in values:
		if not out.has(value):
			out.append(value)
	return out


func max_of(values: Array[float]) -> float:
	var out := 0.0
	for value in values:
		out = maxf(out, value)
	return out


func min_of(values: Array[float]) -> float:
	var out := INF
	for value in values:
		out = minf(out, value)
	return out
