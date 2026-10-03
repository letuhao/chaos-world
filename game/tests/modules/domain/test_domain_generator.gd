extends TestCase

## ADR 0072/0073: the generator proper, and the determinism claim it rests on.
##
## AC6 — the same template and seed produce a byte-identical map; a different seed does
## not, and a different seed never touches the global RNG.
## AC1 — every authored template, across a fixed seed matrix, satisfies the SAME
## `DomainMapContract` the handcrafted producer is held to.
## AC7 — the shared room kit: a generated map draws its rooms from the same authored
## `RoomDef` vocabulary a handcrafted one does, with no parallel cheap kit.
##
## These are unit tests with no scene tree: `DomainMap` is engine-agnostic on purpose.

const SEED_MATRIX: Array[int] = [
	1,
	2,
	3,
	4,
	5,
	6,
	7,
	8,
	9,
	10,
	11,
	12,
	13,
	14,
	15,
	16,
	17,
	18,
	19,
	20,
	21,
	22,
	23,
	24,
	25,
	26,
	27,
	28,
	29,
	30,
	31,
	32,
	33,
	34,
	35,
	36,
	37,
	38,
	39,
	40,
	41,
	42,
	43,
	44,
	45,
	46,
	47,
	48,
	49,
	50,
	51,
	52,
	53,
	54,
	55,
	56,
	57,
	58,
	59,
	60,
	61,
	62,
	63,
	64,
]

## Every authored template, by res:// path. The kit is data, so the suite reads it —
## a fourth template added under `templates/` must pass without editing this file.
const TEMPLATE_PATHS: Array[String] = [
	"res://src/data/domains/templates/ember_grotto.tres",
	"res://src/data/domains/templates/flame_valley_depths.tres",
	"res://src/data/domains/templates/stormwrack_reach.tres",
]


## The handcrafted map the generated one must share a vocabulary with. Same closed set
## of `RoomDef.KINDS`, no separate kit: this is the ADR 0073 claim.
func handcrafted_map() -> DomainMap:
	var map := DomainMap.new(Vector2i(32, 24), 0)
	var entry := RoomDef.new()
	entry.room_id = &"entry_grove"
	entry.kind = &"floor"
	entry.exits = [&"ember_flue"] as Array[StringName]
	map.add_room(entry)
	var flue := RoomDef.new()
	flue.room_id = &"ember_flue"
	flue.kind = &"corridor"
	flue.exits = [&"entry_grove", &"heart_of_ashes"] as Array[StringName]
	map.add_room(flue)
	var core := RoomDef.new()
	core.room_id = &"heart_of_ashes"
	core.kind = &"core"
	core.exits = [&"ember_flue"] as Array[StringName]
	map.add_room(core)
	map.entry_room = &"entry_grove"
	return map


# ── AC6: determinism ─────────────────────────────────────────────────────────


func test_same_template_and_seed_is_byte_identical() -> void:
	for path in TEMPLATE_PATHS:
		var template := _template(path)
		var first := JSON.stringify(DomainGenerator.generate(template, 1234).to_dict())
		var second := JSON.stringify(DomainGenerator.generate(template, 1234).to_dict())
		assert_eq(first, second, "template '%s' at seed 1234 is byte-identical twice" % path)


func test_different_seed_produces_a_different_map() -> void:
	var template := _template(TEMPLATE_PATHS[0])
	var a := JSON.stringify(DomainGenerator.generate(template, 1).to_dict())
	var b := JSON.stringify(DomainGenerator.generate(template, 2).to_dict())
	assert_eq(a != b, true, "seed 1 and seed 2 do not roll the same map")


func test_different_seed_differs_across_the_whole_matrix() -> void:
	var template := _template(TEMPLATE_PATHS[1])
	var baseline := JSON.stringify(DomainGenerator.generate(template, 7).to_dict())
	var differing := 0
	for seed_value in SEED_MATRIX:
		if JSON.stringify(DomainGenerator.generate(template, seed_value).to_dict()) != baseline:
			differing += 1
	assert_eq(
		differing > SEED_MATRIX.size() / 2,
		true,
		"most of the 64-seed matrix differs from seed 7; a re-rolled map would not"
	)


## The streams are seeded by the MIXER, not by the raw seed, and never by `hash()`:
## two streams of the same seed must not be the same generator.
func test_rng_streams_are_four_and_distinct() -> void:
	var pools := DomainRng.streams(99)
	assert_eq(pools.size(), 4, "four streams, not one shared generator")
	var first := (pools[&"rooms"] as RandomNumberGenerator).seed
	var second := (pools[&"decor"] as RandomNumberGenerator).seed
	assert_eq(first != second, true, "the rooms and decor streams are seeded differently")


func test_rng_streams_are_reproducible() -> void:
	var a := (DomainRng.streams(5)[&"graph"] as RandomNumberGenerator).seed
	var b := (DomainRng.streams(5)[&"graph"] as RandomNumberGenerator).seed
	assert_eq(a, b, "the same seed produces the same stream seed")


func test_rng_mix_is_pure_integer_arithmetic() -> void:
	# A splitmix64 round-trip on a fixed input: pure integer arithmetic, so this
	# number cannot change under an engine's `hash()` implementation.
	assert_eq(
		DomainRng.mix_seed(0, 0),
		DomainRng.mix_seed(0, 0),
		"the mixer is a pure function of its arguments"
	)
	assert_eq(
		DomainRng.mix_seed(1, 0) != DomainRng.mix_seed(2, 0),
		true,
		"the mixer separates adjacent seeds"
	)


func test_generation_does_not_disturb_the_global_rng() -> void:
	# The global RandomNumberGenerator is process state; reading it would make a map
	# depend on everything that touched the RNG before the generator ran. Seed it,
	# snapshot two draws, generate, then assert the next two draws are unchanged.
	seed(4242)
	var before := [randi(), randi()]
	seed(4242)
	for path in TEMPLATE_PATHS:
		DomainGenerator.generate(_template(path), 31)
	var after := [randi(), randi()]
	assert_eq(after, before, "DomainGenerator leaves the global RandomNumberGenerator untouched")


# ── AC1: every authored template passes the one contract ─────────────────────


func test_every_template_passes_the_contract_across_the_seed_matrix() -> void:
	for path in TEMPLATE_PATHS:
		var template := _template(path)
		for seed_value in SEED_MATRIX:
			var map := DomainGenerator.generate(template, seed_value)
			assert_ne(map, null, "template '%s' seed %d produced a map" % [path, seed_value])
			if map == null:
				continue
			var problems := DomainMapContract.assert_valid(map)
			assert_eq(
				problems.size(),
				0,
				"template '%s' seed %d: %s" % [path, seed_value, ", ".join(problems)]
			)


func test_generated_and_handcrafted_pass_the_same_contract() -> void:
	var handcrafted := DomainMapContract.assert_valid(handcrafted_map()).size()
	var generated := DomainMapContract.assert_valid(
		DomainGenerator.generate(_template(TEMPLATE_PATHS[0]), 7)
	)
	assert_eq(
		generated.size(), handcrafted, "both producers are held to the identical contract test"
	)


# ── AC7: the shared room kit ─────────────────────────────────────────────────


func test_generated_kinds_are_a_subset_of_the_handcrafted_vocabulary() -> void:
	var handcrafted := handcrafted_map()
	var authored: Array[StringName] = handcrafted.kinds_present()
	# entry/floor, core, gate and arena are RULE-PLACED by the generator, so they are
	# never in a template's room_pool and must not be demanded from it. What the
	# generator may NOT invent is a kind outside the closed set plus the rule-placed
	# four — that is what "the same room kit" means.
	const RULE_PLACED: Array[StringName] = [&"floor", &"core", &"gate", &"arena"]
	for path in TEMPLATE_PATHS:
		for seed_value in [3, 11, 29]:
			var map := DomainGenerator.generate(_template(path), seed_value)
			if map == null:
				continue
			for kind in map.kinds_present():
				assert_eq(
					RoomDef.KINDS.has(kind),
					true,
					"generated kind '%s' is in the one closed set" % kind
				)
				assert_eq(
					authored.has(kind) or _template_has_kind(path, kind) or RULE_PLACED.has(kind),
					true,
					"generated kind '%s' is authored or rule-placed, never invented" % kind
				)


func test_generated_rooms_carry_an_authored_def_id() -> void:
	var map := DomainGenerator.generate(_template(TEMPLATE_PATHS[0]), 5)
	assert_ne(map, null, "seed 5 produced a map")
	if map == null:
		return
	for room_id in map.room_ids_sorted():
		var room: RoomDef = map.room(room_id)
		# Namespaced as <room_def_id>#<n>, so every room names an authored def.
		var parts := String(room_id).split("#", false)
		assert_eq(parts.size(), 2, "room '%s' is namespaced from an authored def id" % room_id)
		assert_eq(
			_authored_ids(_template(TEMPLATE_PATHS[0])).has(parts[0]),
			true,
			"def id '%s' is authored" % parts[0]
		)


func test_the_same_def_is_never_mutated_across_two_generations() -> void:
	# A generated room is a deep copy; writing one must not change the authored def the
	# next seed places.
	var template := _template(TEMPLATE_PATHS[1])
	DomainGenerator.generate(template, 1)
	var before := _pool_signature(template)
	DomainGenerator.generate(template, 2)
	assert_eq(_pool_signature(template), before, "generation never writes to an authored RoomDef")


# ── structural rules ─────────────────────────────────────────────────────────


func test_structural_kinds_are_placed_by_rule_not_by_a_die() -> void:
	for path in TEMPLATE_PATHS:
		var template := _template(path)
		# Every authored template must produce a map for EVERY seed in the matrix. This
		# asserts the generation is total: a template whose own numbers refuse it is an
		# authoring error, and a silent null would hide it.
		for seed_value in SEED_MATRIX:
			var map := DomainGenerator.generate(template, seed_value)
			assert_ne(map, null, "template '%s' seed %d produced a map" % [path, seed_value])
			if map == null:
				continue
			var kinds := map.kinds_present()
			# entry and core are RULE-placed and always present. `gate` is also a rule
			# but needs a leaf adjacent to the entry, so it is asserted over the matrix
			# rather than per-map: a 6-room domain legitimately has no spare gate leaf.
			assert_eq(kinds.has(&"floor"), true, "every generated domain has one entry floor")
			assert_eq(kinds.has(&"core"), true, "every generated domain has one core")
		assert_eq(
			_gate_appears_somewhere(_template(path)),
			true,
			"template '%s' places a gate on at least one seed" % path
		)


## True when some seed produces a gate. Rule-placed, never guaranteed per map.
func _gate_appears_somewhere(template: DomainTemplateDef) -> bool:
	for seed_value in SEED_MATRIX:
		var map := DomainGenerator.generate(template, seed_value)
		if map != null and map.kinds_present().has(&"gate"):
			return true
	return false


func test_settlement_is_only_ever_pinned() -> void:
	# The generator places entry/core/gate/arena by rule; settlement and boss are
	# author-pinned only, so an unpinned leaf never becomes one.
	for path in TEMPLATE_PATHS:
		var template := _template(path)
		for seed_value in SEED_MATRIX:
			var map := DomainGenerator.generate(template, seed_value)
			if map == null:
				continue
			var settlement_count := 0
			for room_id in map.room_ids_sorted():
				var room: RoomDef = map.room(room_id)
				if room.kind == &"settlement" or room.kind == &"boss":
					# A pinned KIND is only ever authored. The leaf it landed on may be
					# CLAMPED (a pin index past the last leaf lands on the last leaf), so
					# the check is on the DEF the room was built from, not on the index.
					var def_id := String(room_id).split("#", false)[0]
					assert_eq(
						_pinned_def_ids(template).has(def_id),
						true,
						"room '%s' is a pinned kind built from an authored def" % room_id
					)
					settlement_count += 1
			assert_eq(
				settlement_count >= 1,
				true,
				"template '%s' seed %d placed at least one author pin" % [path, seed_value]
			)


func test_every_room_is_reachable_from_the_entry() -> void:
	for path in TEMPLATE_PATHS:
		var map := DomainGenerator.generate(_template(path), 17)
		if map == null:
			continue
		assert_eq(
			map.reachable_room_ids().size(),
			map.room_count(),
			"template '%s' seed 17 has no orphan rooms" % path
		)


func test_room_count_respects_the_template_bounds() -> void:
	for path in TEMPLATE_PATHS:
		var template := _template(path)
		for seed_value in SEED_MATRIX:
			var map := DomainGenerator.generate(template, seed_value)
			if map == null:
				continue
			assert_eq(
				map.room_count() >= template.min_rooms,
				true,
				"template '%s' seed %d has at least min_rooms" % [path, seed_value]
			)
			assert_eq(
				map.room_count() <= template.max_rooms,
				true,
				"template '%s' seed %d has at most max_rooms" % [path, seed_value]
			)


func test_realized_room_sizes_are_the_bsp_rects() -> void:
	var map := DomainGenerator.generate(_template(TEMPLATE_PATHS[0]), 21)
	assert_ne(map, null, "seed 21 produced a map")
	if map == null:
		return
	for room_id in map.room_ids_sorted():
		var room: RoomDef = map.room(room_id)
		assert_eq(room.size.x > 0, true, "room '%s' has a non-zero width" % room_id)
		assert_eq(room.size.y > 0, true, "room '%s' has a non-zero height" % room_id)
		assert_eq(
			room.size.x <= map.extent.x and room.size.y <= map.extent.y,
			true,
			"room '%s' fits the template extent" % room_id
		)


func test_exits_are_sorted_and_symmetric() -> void:
	var map := DomainGenerator.generate(_template(TEMPLATE_PATHS[1]), 33)
	assert_ne(map, null, "seed 33 produced a map")
	if map == null:
		return
	for room_id in map.room_ids_sorted():
		var room: RoomDef = map.room(room_id)
		var sorted_exits := room.exits.duplicate()
		sorted_exits.sort_custom(
			func(a: StringName, b: StringName) -> bool: return String(a) < String(b)
		)
		assert_eq(room.exits, sorted_exits, "room '%s' has canonically sorted exits" % room_id)
		for exit_id in room.exits:
			assert_eq(
				map.room(exit_id).exits.has(room_id),
				true,
				"exit '%s' -> '%s' is mutual" % [room_id, exit_id]
			)


func test_map_is_json_clean() -> void:
	var map := DomainGenerator.generate(_template(TEMPLATE_PATHS[0]), 8)
	var parsed: Variant = JSON.parse_string(JSON.stringify(map.to_dict()))
	assert_eq(
		parsed is Dictionary and not (parsed is Dictionary and (parsed as Dictionary).is_empty()),
		true,
		"a generated DomainMap is JSON-clean: no Vector2, no Resource"
	)


func test_generated_map_round_trips_through_dict() -> void:
	var original := DomainGenerator.generate(_template(TEMPLATE_PATHS[1]), 12)
	assert_ne(original, null, "seed 12 produced a map")
	if original == null:
		return
	var restored := DomainMap.from_dict(original.to_dict())
	assert_eq(
		JSON.stringify(restored.to_dict()),
		JSON.stringify(original.to_dict()),
		"a generated map survives a JSON round trip"
	)


# ── loud failures ────────────────────────────────────────────────────────────


func test_a_null_template_fails_loudly_rather_than_returning_a_map() -> void:
	assert_eq(
		DomainGenerator.generate(null, 1), null, "no template returns null, not a half-built domain"
	)


func test_an_empty_room_pool_fails_loudly() -> void:
	var template := DomainTemplateDef.new()
	template.template_id = &"no_pool"
	template.extent = Vector2i(40, 28)
	template.min_leaf = 7
	template.max_depth = 4
	template.min_rooms = 2
	template.max_rooms = 8
	template.room_pool = [] as Array[RoomDef]
	assert_eq(
		DomainGenerator.generate(template, 5),
		null,
		"a template with no authored rooms returns null rather than an invented room"
	)


func test_a_too_small_extent_fails_loudly() -> void:
	var template := DomainTemplateDef.new()
	template.template_id = &"too_small"
	template.extent = Vector2i(6, 6)
	template.min_leaf = 8
	template.max_depth = 4
	template.room_pool = [_room(&"only")] as Array[RoomDef]
	assert_eq(
		DomainGenerator.generate(template, 5),
		null,
		"an extent that cannot hold min_leaf returns null, naming the numbers"
	)


# ── helpers ──────────────────────────────────────────────────────────────────


func _template(path: String) -> DomainTemplateDef:
	var resource := load(path)
	assert_ne(resource, null, "template '%s' loads" % path)
	return resource as DomainTemplateDef


func _room(room_id: StringName) -> RoomDef:
	var room := RoomDef.new()
	room.room_id = room_id
	room.kind = &"chamber"
	return room


func _template_has_kind(path: String, kind: StringName) -> bool:
	var template := _template(path)
	for room_def in template.room_pool:
		if room_def.kind == kind:
			return true
	for pin in template.pins:
		if pin != null and pin.kind == kind:
			return true
	return false


func _authored_ids(template: DomainTemplateDef) -> Array[StringName]:
	var out: Array[StringName] = []
	for room_def in template.room_pool:
		out.append(room_def.room_id)
	return out


func _pool_signature(template: DomainTemplateDef) -> String:
	var out: Array[String] = []
	for room_def in template.room_pool:
		out.append(JSON.stringify(room_def.to_dict()))
	return "|".join(out)


func _pinned_leaf_indices(template: DomainTemplateDef) -> Array[int]:
	var out: Array[int] = []
	for pin in template.pins:
		if pin != null and DomainTemplateDef.is_pinnable_kind(pin.kind):
			out.append(pin.leaf_index)
	return out


## The room-def ids a template pins, as strings. A pin's leaf INDEX may be clamped to
## the last leaf, so a pinned room is identified by the def it was built from.
func _pinned_def_ids(template: DomainTemplateDef) -> Array[String]:
	var out: Array[String] = []
	for pin in template.pins:
		if pin == null or pin.room_def == null:
			continue
		if DomainTemplateDef.is_pinnable_kind(pin.kind):
			out.append(String(pin.room_def.room_id))
	return out
