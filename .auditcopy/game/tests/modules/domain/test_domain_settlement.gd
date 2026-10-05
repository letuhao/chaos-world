extends TestCase

## ADR 0163: the settlement seam. A sect-in-a-domain is a `RoomDef` of
## `kind = settlement` carrying a typed ref; this suite proves the seam resolves that
## ref, refuses an unknown one BY NAME, reports primitives only, and never writes to
## an `Actor`.
##
## Every case here is a READ. The seam has no mutating verb, so "an `Actor` is never
## mutated by a read" is asserted against the whole actor payload rather than against
## a field this file happens to know about.

# ── fixtures ─────────────────────────────────────────────────────────────────

## The catalog the injected lookup stands in for. A real `SectApi` adapter is
## `app/`'s job; the seam only needs something that answers
## `Callable(sect_id) -> {sect_id, display_name}` or `{}`.
const KNOWN: Array[StringName] = [&"cinder_order", &"tide_court"]

## The `typeof` values JSON can carry. Named once so the walker below reads as a
## question ("is this one of these?") rather than as a restatement of the match arms.
const PRIMITIVE_TYPES: Array[int] = [
	TYPE_NIL,
	TYPE_BOOL,
	TYPE_INT,
	TYPE_FLOAT,
	TYPE_STRING,
]


func _lookup() -> Callable:
	return _resolve


func _resolve(sect_id: StringName) -> Dictionary:
	if not KNOWN.has(sect_id):
		return {}
	return {"sect_id": String(sect_id), "display_name": "%s Hall" % String(sect_id)}


func _ref(sect_id: StringName, ref_kind: StringName = DomainSettlement.REF_KIND_SECT) -> Dictionary:
	return {
		"fixture_id": String(sect_id),
		"kind": DomainSettlement.FIXTURE_KIND,
		"ref_kind": ref_kind,
		"ref_id": String(sect_id),
	}


func _spawn(ref_id: String, inhabitant_id: String, role: String, count: int = 1) -> Dictionary:
	return {"ref_id": ref_id, "inhabitant_id": inhabitant_id, "role": role, "count": count}


func _room(
	room_id: StringName,
	kind: StringName,
	exits: Array[StringName],
	fixtures: Array = [],
	spawns: Array = []
) -> RoomDef:
	var room := RoomDef.new()
	room.room_id = room_id
	room.kind = kind
	room.exits = exits
	room.display_name = "%s Hall" % String(room_id)
	room.fixtures.assign(fixtures)
	room.actor_spawn_refs.assign(spawns)
	return room


## A two-room map: a settlement holding a sect ref, plus a gate so the exit graph is
## legal. `settlement_fixtures` is handed in per case so each one can author its own
## refs without a shared default standing in for an assertion.
func _map(settlement_fixtures: Array = [], settlement_spawns: Array = []) -> DomainMap:
	var map := DomainMap.new(Vector2i(24, 18), 909)
	var camp := _room(
		&"ash_camp",
		DomainSettlement.KIND_SETTLEMENT,
		[&"gate"] as Array[StringName],
		settlement_fixtures,
		settlement_spawns
	)
	map.add_room(camp)
	map.add_room(_room(&"gate", &"gate", [&"ash_camp"] as Array[StringName]))
	map.entry_room = &"ash_camp"
	return map


func _actor() -> Actor:
	return Actor.new(&"settlement_tester", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})


func _in_domain(settlement_fixtures: Array = [], settlement_spawns: Array = []) -> Actor:
	var actor := _actor()
	DomainApi.enter(actor, _map(settlement_fixtures, settlement_spawns), &"ember_hollow")
	return actor


## Installed for EVERY case and torn down after each one, so no case can pass on an
## injection the previous case left behind — the same reason `DomainFixtures`' tests
## track what they mint. `teardown` runs after every test, including an early return.
func setup() -> void:
	DomainSettlement.set_institution_lookup(_lookup())


func teardown() -> void:
	DomainSettlement.set_institution_lookup(Callable())


# ── the ref resolves ─────────────────────────────────────────────────────────


func test_a_settlement_resolves_its_ref_to_the_institution() -> void:
	var actor := _in_domain([_ref(&"cinder_order")])
	var result := DomainSettlement.summary(actor, &"ash_camp")
	assert_eq(result.get("ok"), true, "the ref resolves: %s" % str(result))
	assert_eq(result.get("reason"), "", "and there is no refusal to name")
	assert_eq(result.get("ref_kind"), "sect", "the ref names its kind")
	assert_eq(result.get("ref_id"), "cinder_order", "and the institution by id")
	assert_eq(
		(result.get("institution") as Dictionary).get("display_name"),
		"cinder_order Hall",
		"the catalog answered who that id is"
	)


func test_the_ref_is_a_plain_id_and_never_a_resource() -> void:
	var actor := _in_domain([_ref(&"tide_court")])
	var result := DomainSettlement.summary(actor, &"ash_camp")
	assert_eq(result.get("ref_id"), "tide_court", "the ref is the id, not a SectDef")
	# The seam crosses into `res://src/modules/sect/` through nothing at all, so a
	# `SectDef` cannot reach a settlement payload even by accident.
	var payload: Variant = JSON.parse_string(JSON.stringify(result))
	assert_eq(payload is Dictionary, true, "the payload survives a JSON round trip")


# ── unknown refs are refused BY NAME ──────────────────────────────────────────


func test_an_unknown_ref_is_refused_by_name_never_a_default() -> void:
	var actor := _in_domain([_ref(&"no_such_sect")])
	var result := DomainSettlement.summary(actor, &"ash_camp")
	assert_eq(result.get("ok"), false, "a sect the catalog does not ship is refused")
	assert_eq(result.get("reason"), DomainSettlement.ERR_UNKNOWN_REF, "named, not defaulted")
	assert_eq(result.get("ref_id"), "no_such_sect", "and it names WHICH id it refused")
	assert_eq(result.has("institution"), false, "no institution is invented to fill the hole")


func test_a_ref_kind_outside_the_closed_set_is_refused_by_name() -> void:
	var actor := _in_domain([_ref(&"cinder_order", &"bloodline")])
	var result := DomainSettlement.summary(actor, &"ash_camp")
	assert_eq(result.get("ok"), false, "an unrecognised ref kind is refused")
	assert_eq(result.get("reason"), DomainSettlement.ERR_UNKNOWN_REF_KIND, "by name")
	assert_eq(result.get("ref_kind"), "bloodline", "naming the word it refused")


func test_a_settlement_authoring_no_ref_is_refused_not_reported_empty() -> void:
	var actor := _in_domain([])
	var result := DomainSettlement.summary(actor, &"ash_camp")
	assert_eq(result.get("ok"), false, "a castle is a settlement with nothing named")
	assert_eq(result.get("reason"), DomainSettlement.ERR_NO_REF, "and says so by name")
	assert_eq(result.get("ref_id", "absent"), "absent", "there is no ref id to invent for it")


func test_a_room_that_is_not_a_settlement_is_refused_by_name() -> void:
	var actor := _in_domain([_ref(&"cinder_order")])
	var result := DomainSettlement.summary(actor, &"gate")
	assert_eq(result.get("ok"), false, "a gate holds no institution")
	assert_eq(result.get("reason"), DomainSettlement.ERR_NOT_SETTLEMENT, "by name")
	assert_eq(result.get("room_kind"), "gate", "naming the kind it refused")


func test_an_ordinary_fixture_is_never_mistaken_for_a_settlement_ref() -> void:
	# A treasure shares the `fixtures` array with the ref. Reading one as the other is
	# the failure this proves does not happen: the ref is matched on BOTH its kind and
	# its `ref_kind`, not on "the room has a fixture with an id".
	var treasure := {
		"fixture_id": &"ash_camp_offering",
		"kind": &"treasure",
		"ref_kind": &"sect",
		"ref_id": &"cinder_order",
	}
	var actor := _in_domain([treasure])
	var result := DomainSettlement.summary(actor, &"ash_camp")
	assert_eq(result.get("ok"), false, "a treasure is not a sect ref")
	assert_eq(result.get("reason"), DomainSettlement.ERR_NO_REF, "the room authors no ref")


func test_outside_a_run_and_on_a_null_actor_are_refused_by_name() -> void:
	assert_eq(
		DomainSettlement.summary(_actor(), &"ash_camp").get("reason"),
		DomainSettlement.ERR_NO_RUN,
		"no active domain"
	)
	assert_eq(
		DomainSettlement.summary(_in_domain([_ref(&"cinder_order")]), &"nowhere").get("reason"),
		DomainSettlement.ERR_NO_RUN,
		"a room the map does not hold"
	)
	assert_eq(
		DomainSettlement.summary(null, &"ash_camp").get("reason"),
		DomainSettlement.ERR_NO_ACTOR,
		"no actor"
	)


func test_with_no_lookup_installed_a_ref_is_refused_rather_than_called_unknown() -> void:
	# "We could not check" and "this sect does not exist" are DIFFERENT statements.
	# Collapsing them would make an unwired build report every authored sect as a
	# content bug, and the content author would go looking for the wrong defect.
	DomainSettlement.set_institution_lookup(Callable())
	var actor := _in_domain([_ref(&"cinder_order")])
	var result := DomainSettlement.summary(actor, &"ash_camp")
	assert_eq(result.get("ok"), false, "a ref cannot be resolved with no lookup")
	assert_eq(result.get("reason"), DomainSettlement.ERR_NO_LOOKUP, "named as its own reason")
	assert_ne(result.get("reason"), DomainSettlement.ERR_UNKNOWN_REF, "and NOT as an unknown id")
	# Residents do not need the lookup at all, so they still answer.
	assert_eq(
		DomainSettlement.residents(actor, &"ash_camp").get("ok"),
		true,
		"and a castle's residents are readable without any institution bridge"
	)


# ── primitives only ──────────────────────────────────────────────────────────


func test_the_summary_payload_is_json_clean_primitives() -> void:
	var actor := _in_domain(
		[_ref(&"cinder_order")],
		[
			_spawn("elder", "ember_elder", "npc", 1),
			_spawn("rival", "frost_sentinel", "rival_cultivator", 1)
		]
	)
	var summary := DomainSettlement.summary(actor, &"ash_camp")
	var residents := DomainSettlement.residents(actor, &"ash_camp")
	for payload in [summary, residents]:
		var parsed: Variant = JSON.parse_string(JSON.stringify(payload))
		assert_eq(parsed is Dictionary, true, "payload is JSON-clean: %s" % str(payload))
		assert_eq(_holds_no_object(parsed), true, "and carries no Object/Node/Resource")


func test_the_resident_rows_are_ids_and_a_role_tag_never_a_class() -> void:
	var actor := _in_domain(
		[_ref(&"cinder_order")],
		[
			_spawn("vigil", "frost_sentinel", "rival_cultivator", 1),
			_spawn("elder", "ember_elder", "npc", 3),
		]
	)
	var rows := DomainSettlement.residents(actor, &"ash_camp")["residents"] as Array
	assert_eq(rows.size(), 2, "two authored refs, not four rows")
	# Canonical order is by `ref_id`: elder, then vigil.
	assert_eq(rows[0]["ref_id"], "elder", "canonical ref_id order, not authored order")
	assert_eq(rows[0]["count"], 3, "a group is a count, not that many rows")
	assert_eq(rows[1]["role"], "rival_cultivator", "a role is a TAG (ADR 0074), not a class")
	assert_eq(rows[1]["inhabitant_id"], "frost_sentinel", "named by inhabitant id")
	for row in rows:
		assert_eq(
			(row as Dictionary).keys().has("role"), true, "every resident row carries its role tag"
		)
		assert_eq((row as Dictionary).has("actor"), false, "and never an Actor reference")


func test_a_settlement_with_nobody_in_it_reads_as_empty_not_broken() -> void:
	var actor := _in_domain([_ref(&"cinder_order")], [])
	var residents := DomainSettlement.residents(actor, &"ash_camp")
	assert_eq(residents.get("ok"), true, "an empty settlement is a read, not a failure")
	assert_eq(residents.get("count"), 0, "and it reports zero residents")
	assert_eq(residents.get("residents"), [], "with an empty list, never null")


# ── a read never mutates an Actor ────────────────────────────────────────────


func test_no_read_mutates_the_actor() -> void:
	var actor := _in_domain([_ref(&"cinder_order")], [_spawn("elder", "ember_elder", "npc", 1)])
	# The WHOLE payload, not a field this file knows about: a seam that wrote one
	# undocumented key would pass a narrower check and still corrupt a save.
	var before := JSON.stringify(actor.to_dict())
	var before_id := actor.id
	var before_module_data := JSON.stringify(actor.get_module_data(DomainApi.MODULE_KEY))

	DomainSettlement.summary(actor, &"ash_camp")
	DomainSettlement.residents(actor, &"ash_camp")
	# ...and the refusals, which are the reads most likely to have written something
	# on their way out.
	DomainSettlement.summary(actor, &"nowhere")
	DomainSettlement.summary(actor, &"gate")
	DomainSettlement.residents(actor, &"nowhere")
	DomainSettlement.summary(null, &"ash_camp")

	assert_eq(JSON.stringify(actor.to_dict()), before, "the actor payload is byte-identical")
	assert_eq(actor.id, before_id, "and the actor's own identity is untouched")
	assert_eq(
		JSON.stringify(actor.get_module_data(DomainApi.MODULE_KEY)),
		before_module_data,
		"including the domain run state"
	)


func test_the_read_is_repeatable_and_does_not_drift() -> void:
	var actor := _in_domain([_ref(&"cinder_order")], [_spawn("elder", "ember_elder", "npc", 1)])
	var first := JSON.stringify(DomainSettlement.residents(actor, &"ash_camp"))
	var second := JSON.stringify(DomainSettlement.residents(actor, &"ash_camp"))
	assert_eq(first, second, "reading twice gives the identical answer")


# ── the seam stays a seam ────────────────────────────────────────────────────


func test_the_seam_names_no_institution_class_and_adds_no_facade_method() -> void:
	# `domain` declares `core` + `contracts` only, and `BARE_REF_UNITS` excludes
	# `modules/*`, so a bare `SectApi` here would report ZERO arch violations while
	# still being a real cross-module edge. The grep is the guard `tools arch` cannot
	# be, and it mirrors what `test_sect_social_edge.gd` does for `social`.
	# CODE lines only: the class's own docblock names these classes to say it does not
	# reference them, and a grep over prose would fail the file for explaining itself.
	for line in _code_lines("res://src/modules/domain/domain_settlement.gd"):
		assert_eq(line.contains("SectApi"), false, "no bare SectApi reference: %s" % line)
		assert_eq(line.contains("SectDef"), false, "no bare SectDef reference: %s" % line)
		assert_eq(line.contains("res://src/modules/"), false, "no cross-module path: %s" % line)

	# And the facade is untouched: this file is reachable without a thirteenth verb.
	var facade: String = (load("res://src/modules/domain/api.gd") as GDScript).source_code
	assert_eq(facade.contains("DomainSettlement"), false, "the 12-method facade is not grown")


func test_the_injected_lookup_is_the_only_way_in_and_it_is_installable() -> void:
	var actor := _in_domain([_ref(&"cinder_order")])
	# The seam holds the CALLABLE, not the answer: swapping it swaps the whole
	# institution catalog, which is what makes `app/` the right place to wire it.
	DomainSettlement.set_institution_lookup(
		func(_id: StringName) -> Dictionary:
			return {"sect_id": "stubbed", "display_name": "Swapped"}
	)
	var result := DomainSettlement.summary(actor, &"ash_camp")
	assert_eq(result.get("ok"), true, "a different lookup answers")
	assert_eq(
		(result.get("institution") as Dictionary).get("sect_id"),
		"stubbed",
		"and the seam reports what the lookup said, not what it knew"
	)


# ── helpers ──────────────────────────────────────────────────────────────────


## The CODE lines of a script, with `##` comments and blank lines dropped.
##
## A docblock is prose that happens to sit in a script, and this repo's docblocks name
## the classes a file deliberately does NOT touch. Grepping raw source would therefore
## fail `domain_settlement.gd` for explaining its own boundary — so the comment is
## stripped first and only what would actually be COMPILED is searched.
func _code_lines(path: String) -> Array[String]:
	var source: String = (load(path) as GDScript).source_code
	var out: Array[String] = []
	for raw in source.split("\n"):
		var line := String(raw).strip_edges()
		if line.begins_with("#") or line.is_empty():
			continue
		out.append(line)
	return out


## Whether a JSON-parsed payload still holds anything but primitives. A `StringName`,
## `Vector2i` or `Resource` all stringify into JSON differently from a plain value, so
## this walks the parsed tree rather than trusting the round trip to have failed.
func _holds_no_object(value: Variant) -> bool:
	match typeof(value):
		TYPE_DICTIONARY:
			for key in (value as Dictionary).keys():
				if not _holds_no_object(key):
					return false
				if not _holds_no_object((value as Dictionary)[key]):
					return false
			return true
		TYPE_ARRAY:
			for item in value as Array:
				if not _holds_no_object(item):
					return false
			return true
		_:
			# Every primitive JSON can carry, and nothing else. A `StringName`,
			# `Vector2i` or `Resource` reaches the default arm and is reported.
			return typeof(value) in PRIMITIVE_TYPES
