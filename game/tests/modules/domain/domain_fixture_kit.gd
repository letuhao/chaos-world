extends TestCase

## Shared kit for the two domain-fixture suites. NOT a suite itself: the runner
## discovers `test_*.gd` only, so this file is never executed on its own.
##
## It exists for exactly the reason `body_damage_fixture.gd` does: the authored-room
## readers, the map builder and the fixture id constants are ONE copy, because a
## second copy drifts and a drift here is invisible -- every suite would still be
## green against its own copy of a question about the shipped content.
##
## Both suites `extends` this file, so `teardown()` -- which owns the process-wide
## `DomainFixtures.set_minter` reset the runner requires after EVERY test -- and every
## builder stay reachable from each half of the split.

# ── the shipped content ───────────────────────────────────────────────────────

const ROOM_DIR := "res://src/data/domains/rooms"

## The three kinds `DomainFixtures.KINDS` closes over. A fourth kind someone authors
## fails here rather than becoming a fixture the game walks past.
const KINDS: Array[String] = ["trap", "puzzle", "treasure"]

## The doors the cases below open, so a reader can see which authored shape is under
## test without opening the `.tres`.
const UNKEYED := &"ash_camp_offering"
const KEYED := &"ash_furnace_hoard"
const REALM_GATED := &"ash_heart_hoard"
const PUZZLE := &"ash_arena_formation"
const TRAP := &"ash_chamber_vein"
const UNPUBLISHED_LEVER := &"ash_chamber_collapse"

## Long enough to clear every authored `telegraph_s` — the shipped kit's loudest is
## `ash_chamber_collapse` at 1.6 — in one step, for the cases that only care that the
## window CLOSED rather than where its edge sits.
const PAST_TELEGRAPH := 99.0


## `EnvironmentField.hazard_cadence`, read through a function rather than a `const`
## because a static call is not a constant expression. A DOT with no interval pays
## nothing (`status_registry.gd:168`), so this is the cadence a trap's status must pulse
## on, and it is read off the hazard def rather than restated as a literal here.
func _cadence() -> float:
	return EnvironmentField.hazard_cadence()


## Every `.tres` under `dir_path`, sorted. The `while` is the `DirAccess.get_next()`
## terminator, the bounded form `tests/arch_rules/test_no_unbounded_wait.gd` rule 2
## accepts.
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


## The shipped rooms, ROUND-TRIPPED rather than handed over as loaded. `ResourceLoader`
## caches a `.tres`, so mutating the shared instance would persist into every later
## test — the same reason `test_domain_content.gd:235` copies before it edits.
func _authored_rooms() -> Array[RoomDef]:
	var out: Array[RoomDef] = []
	for file_name in _tres_files(ROOM_DIR):
		var room := load("%s/%s" % [ROOM_DIR, file_name]) as RoomDef
		if room != null:
			out.append(RoomDef.from_dict(room.to_dict()))
	return out


## `{room_id, fixture}` for every fixture in every shipped room, in canonical room and
## authored order, so the walks are a property of the tree and not of a listing order.
func _authored_fixtures() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room in _authored_rooms():
		for fixture in room.fixtures:
			out.append({"room_id": String(room.room_id), "fixture": fixture})
	return out


## The authored fixture `fixture_id` lives on, as `{room_id, fixture}`. An empty
## dictionary is a loud miss at the call site rather than a silent null, because a
## fixture this suite cannot find is a test that would pass by asserting nothing.
func _find(fixture_id: StringName) -> Dictionary:
	for entry in _authored_fixtures():
		if StringName((entry["fixture"] as Dictionary).get("fixture_id", "")) == fixture_id:
			return entry
	return {}


## The authored dictionary for `fixture_id`, asserted found rather than returned
## quietly.
func _authored(fixture_id: StringName) -> Dictionary:
	var found := _find(fixture_id)
	if found.is_empty():
		push_error("test_domain_fixtures: no shipped fixture named '%s'" % String(fixture_id))
		return {}
	return found["fixture"] as Dictionary


## The authored room `fixture_id` lives in.
func _room_of(fixture_id: StringName) -> StringName:
	return StringName(String(_find(fixture_id)["room_id"]))


## A map over the SHIPPED rooms, every one reachable and every exit declared, so
## `DomainMapContract.assert_valid` passes and `DomainApi.enter` accepts it. The kit's
## rooms declare no exits of their own (`ash_arena.tres` has none), so connectivity is
## rebuilt here rather than asserted against a map that cannot be entered.
##
## `ash_gate`'s roster is NORMALISED rather than reproduced: it authors a `cinder_hound`
## at role `mob` (hostile) AND an `ember_pilgrim` at role `rival_cultivator` (not), which
## no band admits — `test_domain_content.gd:113-139` pins that as a known CONTENT defect
## whose fix belongs in the content, in a file this task does not own. `DomainApi.enter`
## refusing the map outright would leave this suite measuring nothing, so the
## non-hostile refs are dropped and the cost is RE-PROVED rather than assumed:
## `_map_carries_every_fixture` asserts the map still holds every authored fixture.
func _map() -> DomainMap:
	return _map_with_replacement()


## [method _map], with ONE room swapped for `replacement` when it shares that room's id.
## Extracted for the case that must enter a map holding a deliberately broken room: a
## single-room map is refused by the contract (`has no exit at all, so a run could never
## be left`), so a scratch map is the whole ring with one defect — the same topology the
## kit proves enterable, one room different.
func _map_with_replacement(replacement: RoomDef = null) -> DomainMap:
	var map := DomainMap.new(Vector2i(64, 48), 4242)
	var rooms := _authored_rooms()
	for index in rooms.size():
		# A ring, not a chain: a `previous`/`following` pair on every room leaves nobody
		# unreachable, which is the half of the contract a fixture case would otherwise
		# trip over for reasons unconnected to fixtures.
		var copy := rooms[index]
		if replacement != null and copy.room_id == replacement.room_id:
			copy = replacement
		copy.exits = (
			[
				rooms[(index - 1 + rooms.size()) % rooms.size()].room_id,
				rooms[(index + 1) % rooms.size()].room_id,
			]
			as Array[StringName]
		)
		var kept: Array[Dictionary] = []
		for ref in copy.actor_spawn_refs:
			if String(ref.get("role", "")) != DomainRoles.RIVAL_CULTIVATOR:
				kept.append(ref)
		copy.actor_spawn_refs = kept
		map.add_room(copy)
	map.entry_room = rooms[0].room_id
	return map


func _actor(realm_id: StringName = &"qi_refining") -> Actor:
	var actor := Actor.new(&"fixture_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(PathState.QI, realm_id))
	actor.attach_core_resources()
	return actor


## Enter the shipped kit, so every case starts inside a real run rather than against a
## hand-built fixture room.
func _in_domain(realm_id: StringName = &"qi_refining") -> Actor:
	var actor := _actor(realm_id)
	DomainApi.enter(actor, _map(), &"ember_hollow")
	return actor


## The top of the shared ladder, named through the data because a ladder's length is
## content. An actor here is at or above every floor the kit can author.
func _ladder_ceiling() -> StringName:
	var realms := RealmDefaults.ladder().realms()
	return realms[realms.size() - 1].id if not realms.is_empty() else &"qi_refining"


func _install(keys: Callable, granter: Callable) -> void:
	DomainFixtures.set_minter(keys, granter)


## `keys` answering `reach` for `key_item_id` and nothing for anything else, plus a
## `granter` recording every delivery into `granted` — an Array the caller owns, which
## a closure captures by reference. The recorded row carries the SEED the fixture
## derived, which is the third argument's meaning (ADR 0216 §4), not a count.
func _keyed(granted: Array, key_item_id: StringName, reach: float) -> void:
	_install(
		func(_actor_arg: Actor, item_id: StringName) -> float:
			return reach if item_id == key_item_id else 0.0,
		func(_actor_arg: Actor, item_id: StringName, seed: int) -> int:
			granted.append({"item_id": String(item_id), "seed": seed})
			return 0
	)


func teardown() -> void:
	# `set_minter` is process-wide state and the runner calls this after EVERY test, so
	# a bridge left installed leaks into whatever suite runs next — the same reason
	# `test_domain_content.gd:224` restores its own.
	DomainFixtures.set_minter(Callable(), Callable())


# ── helpers ──────────────────────────────────────────────────────────────────


## The unique values in `values`, first-seen order. A bounded `for`; there is no
## `Array.uniq` in this GDScript and hand-rolling it keeps the assertion readable.
func _distinct(values: Array) -> Array:
	var out: Array = []
	for value in values:
		if not out.has(value):
			out.append(value)
	return out


## The three verbs as `Callable`s, so one loop can ask "does EVERY verb refuse a fixture
## outside a run" rather than repeating the assertion three times.
func _arm_verb(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	return DomainFixtures.arm(actor, room_id, fixture_id, 0.0)


func _attempt_verb(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	return DomainFixtures.attempt(actor, room_id, fixture_id, &"")


func _claim_verb(actor: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	return DomainFixtures.claim(actor, room_id, fixture_id)
