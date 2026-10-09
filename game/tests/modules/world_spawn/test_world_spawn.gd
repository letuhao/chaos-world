extends TestCase

## Tests for the `world_spawn` module: durable location selection (ADR 0113).
##
## The two properties that matter and are easy to lose are (1) the durable id
## survives an `Actor.to_dict()` / `from_dict()` round-trip, and (2) a seeded
## random pick is a SELECTION that repeats — not a generator, and not a dice roll.


func _actor(id: StringName = &"player") -> Actor:
	var actor := Actor.new(id)
	WorldSpawnApi.attach(actor)
	return actor


## Every authored location id currently on disk, for the "the pool is real
## content" assertions rather than a hardcoded four.
func _authored_count() -> int:
	return WorldApi.locations(null).size()


func test_attach_is_idempotent() -> void:
	var actor := Actor.new(&"player")
	WorldSpawnApi.attach(actor)
	var first := actor.get_module_data(WorldSpawnApi.MODULE_KEY)
	WorldSpawnApi.attach(actor)
	assert_eq(actor.get_module_data(WorldSpawnApi.MODULE_KEY), first, "attach twice is stable")


func test_attach_on_null_actor_is_a_no_op() -> void:
	WorldSpawnApi.attach(null)
	assert_eq(true, true, "attach(null) did not crash")


func test_current_before_any_selection_is_nowhere() -> void:
	var actor := _actor()
	var view := WorldSpawnApi.current(actor)
	assert_eq(view["located"], false, "an unmoved actor is nowhere in particular")
	assert_eq(view["location_id"], "", "and carries no location id")
	assert_eq(view["visits"], 0, "and has visited nothing")


func test_selected_moves_the_actor() -> void:
	var actor := _actor()
	var answer := WorldSpawnApi.selected(actor, &"mortal_plains")
	assert_eq(answer["ok"], true, "explicit selection accepted")
	assert_eq(answer["location_id"], "mortal_plains", "the named location is returned")
	assert_eq(WorldSpawnApi.current(actor)["location_id"], "mortal_plains", "ledger moved")
	assert_eq(WorldSpawnApi.current(actor)["tier"], "mortal_world", "tier came from the .tres")
	assert_eq(WorldSpawnApi.current(actor)["faction_id"], "body_dao", "faction from the .tres")
	assert_eq(WorldSpawnApi.current(actor)["source"], "explicit", "source recorded")


func test_selected_refuses_an_unknown_location() -> void:
	var actor := _actor()
	var answer := WorldSpawnApi.selected(actor, &"no_such_place")
	assert_eq(answer["ok"], false, "unknown id refused")
	assert_eq(answer["reason"], "unknown_location", "refusal is named")
	assert_eq(answer["location_id"], "no_such_place", "the bad id comes back")
	assert_eq(WorldSpawnApi.current(actor)["located"], false, "ledger untouched")


func test_selected_refuses_a_null_actor() -> void:
	var answer := WorldSpawnApi.selected(null, &"mortal_plains")
	assert_eq(answer["ok"], false, "no actor refused")
	assert_eq(answer["reason"], "no_actor", "refusal is named")


func test_selected_counts_a_visit() -> void:
	var actor := _actor()
	WorldSpawnApi.selected(actor, &"mortal_plains")
	WorldSpawnApi.selected(actor, &"mortal_plains")
	assert_eq(WorldSpawnApi.current(actor)["visits"], 2, "revisiting counts")


func test_selected_refuses_an_empty_location_id() -> void:
	var actor := _actor()
	var answer := WorldSpawnApi.selected(actor, &"")
	assert_eq(answer["ok"], false, "empty id is not a place")
	assert_eq(answer["reason"], "unknown_location", "refusal is named")


# --- determinism -------------------------------------------------------------


func test_random_is_repeatable_for_one_seed() -> void:
	var first := _actor(&"seeded_player")
	var second := _actor(&"seeded_player")
	var one := WorldSpawnApi.random(first, &"", &"", 4242)
	var two := WorldSpawnApi.random(second, &"", &"", 4242)
	assert_eq(one["ok"], true, "first pick succeeded")
	assert_eq(two["ok"], true, "second pick succeeded")
	assert_eq(one["location_id"], two["location_id"], "same seed, same location")
	assert_eq(one["seed"], 4242, "the seed is echoed back, not swallowed")


func test_random_is_repeatable_on_one_actor() -> void:
	# The property that matters at runtime: calling it twice does not reroll.
	var actor := _actor(&"stable_player")
	var one := WorldSpawnApi.random(actor, &"", &"", 77)
	var two := WorldSpawnApi.random(actor, &"", &"", 77)
	assert_eq(one["location_id"], two["location_id"], "the same actor and seed agree")


func test_random_without_a_seed_is_derived_from_the_actor() -> void:
	var first := _actor(&"derived_player")
	var second := _actor(&"derived_player")
	var one := WorldSpawnApi.random(first)
	var two := WorldSpawnApi.random(second)
	assert_eq(one["ok"], true, "unseeded pick succeeded")
	assert_eq(one["seed"], WorldSpawnState.seed_from_actor(first), "seed comes from the actor")
	assert_eq(one["location_id"], two["location_id"], "the same actor lands in the same place")


func test_random_seed_is_not_read_from_a_clock_or_global_rng() -> void:
	# Reads the source, because the failure is invisible in an assertion: a
	# `randf()` here would still make two same-seed calls agree within a frame.
	var script := FileAccess.get_file_as_string("res://src/modules/world_spawn/api.gd")
	# Strip comments before the search: this file's own docstrings NAME `randf()`
	# to state that it is never called, so a raw substring search would fail on
	# the very prose documenting the rule.
	var code := ""
	for line in script.split("\n"):
		var trimmed := String(line).strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash_at := line.find("#")
		code += (line.substr(0, hash_at) if hash_at >= 0 else line) + "\n"
	assert_eq(code.contains("randf("), false, "no global rng draw in the facade")
	assert_eq(script.contains("Time.get_ticks"), false, "no clock read in the facade")


func test_random_respects_the_tier_filter() -> void:
	var actor := _actor()
	var answer := WorldSpawnApi.random(actor, &"immortal_world", &"", 11)
	assert_eq(answer["ok"], true, "filtered pick succeeded")
	assert_eq(answer["state"]["tier"], "immortal_world", "the pick is in the named tier")
	assert_eq(answer["location_id"], "immortal_court", "only one location ships that tier")


func test_random_respects_the_faction_filter() -> void:
	var actor := _actor()
	var answer := WorldSpawnApi.random(actor, &"", &"qi_dao", 13)
	assert_eq(answer["ok"], true, "filtered pick succeeded")
	assert_eq(answer["state"]["faction_id"], "qi_dao", "the pick carries the named faction")


func test_random_combines_both_filters() -> void:
	var actor := _actor()
	var answer := WorldSpawnApi.random(actor, &"immortal_world", &"mind_dao", 19)
	assert_eq(answer["ok"], true, "both filters together still find content")
	assert_eq(answer["location_id"], "immortal_court", "and land on the one match")


func test_random_refuses_a_filter_that_names_nothing() -> void:
	var actor := _actor()
	var answer := WorldSpawnApi.random(actor, &"mortal_world", &"mind_dao", 5)
	assert_eq(answer["ok"], false, "a filter with no authored match refuses")
	assert_eq(answer["reason"], "no_candidates", "refusal is named")
	assert_eq(answer["tier"], "mortal_world", "the filters come back for the caller")
	assert_eq(WorldSpawnApi.current(actor)["located"], false, "and nothing was written")


func test_random_refuses_a_null_actor() -> void:
	var answer := WorldSpawnApi.random(null, &"", &"", 1)
	assert_eq(answer["ok"], false, "no actor refused")
	assert_eq(answer["reason"], "no_actor", "refusal is named")


func test_random_never_invents_a_location() -> void:
	# ADR 0113: a random map is a SELECTION from authored content. Every id the
	# pick can return must exist in the pool it drew from.
	var actor := _actor()
	var pool: Array[String] = []
	for entry in WorldSpawnApi.catalog(actor):
		pool.append(String(entry["location_id"]))
	assert_eq(pool.is_empty(), false, "the authored pool is not empty")
	for seed_value in range(1, 12):
		var answer := WorldSpawnApi.random(actor, &"", &"", seed_value)
		assert_eq(
			pool.has(String(answer["location_id"])),
			true,
			"seed %d picked authored content" % seed_value
		)


func test_random_reaches_more_than_one_place_over_many_seeds() -> void:
	# Guards the opposite failure: a "deterministic" pick that always returns the
	# first row is deterministic and useless.
	var actor := _actor()
	var seen: Dictionary = {}
	for seed_value in range(1, 40):
		seen[String(WorldSpawnApi.random(actor, &"", &"", seed_value)["location_id"])] = true
	assert_eq(seen.size() > 1, true, "different seeds can reach different places")


# --- catalog -----------------------------------------------------------------


func test_catalog_lists_every_authored_location() -> void:
	var actor := _actor()
	assert_eq(WorldSpawnApi.catalog(actor).size(), _authored_count(), "the catalog is the pool")


func test_catalog_is_sorted_by_location_id() -> void:
	# The determinism of `random` depends on this: a `DirAccess` scan is not a
	# stable order, so the sort is load-bearing and not cosmetic.
	var actor := _actor()
	var pool := WorldSpawnApi.catalog(actor)
	var previous := ""
	for entry in pool:
		var location_id := String(entry["location_id"])
		assert_eq(location_id > previous, true, "'%s' sorts after '%s'" % [location_id, previous])
		previous = location_id


func test_catalog_filters_by_tier() -> void:
	var pool := WorldSpawnApi.catalog(_actor(), &"spirit_world", &"")
	assert_eq(pool.size(), 1, "one location ships the spirit tier")
	assert_eq(pool[0]["location_id"], "spirit_peaks", "and it is the expected one")


func test_catalog_filters_by_faction() -> void:
	var pool := WorldSpawnApi.catalog(_actor(), &"", &"mind_dao")
	assert_eq(pool.size(), 2, "two locations ship the mind faction")
	for entry in pool:
		assert_eq(entry["faction_id"], "mind_dao", "every row carries the filter")


func test_catalog_filters_tier_and_faction_together() -> void:
	var pool := WorldSpawnApi.catalog(_actor(), &"transcendent_world", &"mind_dao")
	assert_eq(pool.size(), 1, "the combined filter narrows to one")
	assert_eq(pool[0]["location_id"], "transcendent_realm", "and names it")


func test_catalog_is_empty_for_a_filter_nothing_matches() -> void:
	assert_eq(WorldSpawnApi.catalog(_actor(), &"mortal_world", &"qi_dao").size(), 0, "no rows")


func test_catalog_rows_are_primitives_only() -> void:
	for entry in WorldSpawnApi.catalog(_actor()):
		for key in entry.keys():
			assert_eq(_is_primitive(entry[key]), true, "catalog value is primitive: %s" % key)


# --- persistence -------------------------------------------------------------


func test_current_survives_an_actor_round_trip() -> void:
	var actor := _actor()
	WorldSpawnApi.selected(actor, &"spirit_peaks")
	var restored := Actor.from_dict(actor.to_dict())
	var view := WorldSpawnApi.current(restored)
	assert_eq(view["location_id"], "spirit_peaks", "the durable id survived the save")
	assert_eq(view["tier"], "spirit_world", "and the denormalised row with it")
	assert_eq(view["danger_level"], 5, "and the authored danger")
	assert_eq(view["visits"], 1, "and the visit count")


func test_random_pick_survives_an_actor_round_trip() -> void:
	var actor := _actor()
	var answer := WorldSpawnApi.random(actor, &"", &"", 909)
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(
		WorldSpawnApi.current(restored)["location_id"],
		String(answer["location_id"]),
		"the rolled location is the durable one"
	)


func test_attach_after_a_load_preserves_the_location() -> void:
	var actor := _actor()
	WorldSpawnApi.selected(actor, &"immortal_court")
	var restored := Actor.from_dict(actor.to_dict())
	WorldSpawnApi.attach(restored)
	assert_eq(WorldSpawnApi.current(restored)["location_id"], "immortal_court", "attach kept it")


func test_a_hand_edited_payload_does_not_break_a_read() -> void:
	# A save is untrusted input: the ledger normalizes rather than trusting.
	var actor := _actor()
	actor.set_module_data(WorldSpawnApi.MODULE_KEY, {"location_id": 42, "danger_level": 3})
	var view := WorldSpawnApi.current(actor)
	# A location id is a `StringName`/`String` in the authored pool, so an int is
	# UNREADABLE rather than coercible. Coercing it would mint the durable id
	# "42", a location no `.tres` backs and no `selected` could ever mount.
	assert_eq(view["location_id"], "", 'an int location id reads as absent, never as "42"')
	assert_eq(view["located"], false, "so the actor is nowhere rather than somewhere invalid")
	assert_eq(view["danger_level"], 3, "and an int danger still reads back as an int")


func test_module_data_is_the_only_place_the_id_lives() -> void:
	# ADR 0113: `core` is not extended without an ADR, and `WorldState` is the
	# realm-creation ability, not the playfield.
	var actor := _actor()
	WorldSpawnApi.selected(actor, &"mortal_plains")
	assert_eq(actor.world, null, "no created-world state was abused to hold a place")
	assert_eq(actor.inside_world, null, "nor an inside-world")
	assert_eq(actor.module_data.has(WorldSpawnApi.MODULE_KEY), true, "module_data holds it")


# --- summary -----------------------------------------------------------------


func test_summary_reports_the_location_and_the_pool() -> void:
	var actor := _actor()
	WorldSpawnApi.selected(actor, &"mortal_plains")
	var s := WorldSpawnApi.summary(actor)
	assert_eq(s["has_actor"], true, "summary knows it has an actor")
	assert_eq(s["actor_id"], "player", "and names it")
	assert_eq(s["location_id"], "mortal_plains", "and where the player is")
	assert_eq(s["candidate_count"], _authored_count(), "and how big the pool is")
	assert_eq(s["persisted"], true, "the ledger is written to module_data")


func test_summary_on_a_null_actor() -> void:
	var s := WorldSpawnApi.summary(null)
	assert_eq(s["has_actor"], false, "no actor is reported, not a crash")
	assert_eq(s["candidate_count"], 0, "and no pool is claimed")


func test_summary_is_primitives_only() -> void:
	var actor := _actor()
	WorldSpawnApi.selected(actor, &"spirit_peaks")
	_assert_primitives(WorldSpawnApi.summary(actor), "summary")


func test_current_is_primitives_only() -> void:
	var actor := _actor()
	WorldSpawnApi.selected(actor, &"spirit_peaks")
	_assert_primitives(WorldSpawnApi.current(actor), "current")


func test_random_answer_is_primitives_only() -> void:
	var actor := _actor()
	_assert_primitives(WorldSpawnApi.random(actor, &"", &"", 31), "random")


func test_selected_is_the_explicit_pick() -> void:
	var actor := _actor()
	var answer := WorldSpawnApi.selected(actor, &"transcendent_realm")
	assert_eq(answer["ok"], true, "selected moves")
	assert_eq(answer["location_id"], "transcendent_realm", "to the named place")
	assert_eq(WorldSpawnApi.current(actor)["location_id"], "transcendent_realm", "ledger agrees")


# The unknown-location refusal is asserted in full above, in
# `test_selected_refuses_an_unknown_location`. A second function of that name
# (a `set_current` test renamed by 39cebcfb3) was a parse error: GDScript refuses
# a duplicate function name, and the whole suite failed to LOAD, taking its
# dependants with it.

# --- internals ---------------------------------------------------------------


func test_pick_index_is_stable_for_one_seed() -> void:
	for seed_value in range(1, 25):
		assert_eq(
			WorldSpawnState.pick_index(4, seed_value),
			WorldSpawnState.pick_index(4, seed_value),
			"seed %d draws the same index twice" % seed_value
		)


func test_pick_index_stays_inside_the_pool() -> void:
	for seed_value in range(1, 60):
		var index := WorldSpawnState.pick_index(3, seed_value)
		assert_eq(index >= 0 and index < 3, true, "index %d is inside 0..2" % index)


func test_pick_index_refuses_an_empty_pool() -> void:
	assert_eq(WorldSpawnState.pick_index(0, 5), -1, "an empty pool has no index to draw")


func test_pick_index_treats_a_zero_seed_as_seeded() -> void:
	# Godot reads `rng.seed = 0` as "randomise", so an undisplaced zero would make
	# the seed argument silently meaningless.
	assert_eq(WorldSpawnState.pick_index(4, 0), WorldSpawnState.pick_index(4, 0), "stable")
	var actor := _actor(&"zero_seed_actor")
	assert_eq(WorldSpawnState.seed_from_actor(actor) != 0, true, "the derived seed is never zero")


func test_seed_from_actor_is_stable_and_actor_specific() -> void:
	assert_eq(
		WorldSpawnState.seed_from_actor(_actor(&"alpha")),
		WorldSpawnState.seed_from_actor(_actor(&"alpha")),
		"the same actor id derives the same seed"
	)
	assert_eq(
		(
			WorldSpawnState.seed_from_actor(_actor(&"alpha"))
			!= WorldSpawnState.seed_from_actor(_actor(&"beta"))
		),
		true,
		"different actors do not share a seed"
	)


func _is_primitive(value: Variant) -> bool:
	var kind := typeof(value)
	return (
		kind == TYPE_ARRAY
		or kind == TYPE_FLOAT
		or kind == TYPE_INT
		or kind == TYPE_STRING
		or kind == TYPE_BOOL
	)


func _assert_primitives(payload: Dictionary, label: String) -> void:
	for key in payload.keys():
		assert_eq(_is_primitive(payload[key]), true, "%s value is primitive: %s" % [label, key])
