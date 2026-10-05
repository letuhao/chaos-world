extends TestCase

## The ledger is a versioned plain dictionary under `actor.module_data`, so core
## persists it without ever naming a bloodline (ADR 0027). These assert the payload
## round trips through `Actor.to_dict`/`from_dict` and a JSON hop, that a save written
## before the module existed loads clean as empty, that a malformed payload is
## diagnosed rather than partially applied, and that attaching to a restored actor
## re-derives the whole projection from the ledger instead of trusting the payload.

const MODULE_KEY := BloodlineState.MODULE_KEY
const COMMON := &"t_common"
const RARE := &"t_rare"
const FOUNDING := &"t_founding"


func setup() -> void:
	(
		BloodlineFixtureCatalog
		. install(
			[
				BloodlineFixtureCatalog.common(COMMON),
				BloodlineFixtureCatalog.rare(RARE),
				BloodlineFixtureCatalog.founding(FOUNDING),
			]
		)
	)


func teardown() -> void:
	BloodlineFixtureCatalog.teardown()


func _born(actor_id: StringName = &"child") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0})
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, COMMON, 0.9)
	return actor


func _own_sources(actor: Actor) -> Array:
	var out: Array = []
	for modifier in actor.stats._modifiers:
		if BloodlineState.is_own_source(modifier.source):
			out.append(String(modifier.source))
	out.sort()
	return out


func _own_traits(actor: Actor) -> Array:
	var out: Array = []
	# `.to_array()`, not the NameList itself: iterating the live list raises
	# "error calling _iter_next on iterator object", which aborts the test mid-function and
	# is reported as an incomplete run rather than a failure. The sibling
	# `test_bloodline_module.gd` helper already reads it this way.
	for trait_id in actor.traits.to_array():
		# `str()`, not `String()`: this build has no callable `String` constructor for a
		# StringName, so `String(trait_id)` throws — same silent-abort shape.
		if str(trait_id).begins_with(BloodlineState.TRAIT_PREFIX):
			out.append(str(trait_id))
	out.sort()
	return out


func _fingerprint(actor: Actor) -> Dictionary:
	return {
		"state": BloodlineApi.state(actor),
		"traits": _own_traits(actor),
		"sources": _own_sources(actor),
		"max_health": actor.stats.derived(Stat.MAX_HEALTH),
		"awakened": actor.stats.derived(BloodlineStats.AWAKENED_COUNT),
	}


# --- The payload -------------------------------------------------------------


func test_the_ledger_lives_in_the_actors_module_data_as_a_versioned_dictionary() -> void:
	var actor := _born()
	var stored: Dictionary = actor.get_module_data(MODULE_KEY)
	assert_eq(int(stored.get("version", 0)), BloodlineState.SCHEMA_VERSION, "versioned")
	assert_almost_eq(float(stored["lineages"][COMMON]), 0.9, "the concentration is recorded")
	assert_eq(
		(stored["applied"] as Dictionary).keys().size(),
		1,
		"and so is what was projected, so a strip can reverse it"
	)
	assert_eq(BloodlineApi.state(actor), stored, "the facade reports the persisted payload")


func test_a_bloodline_survives_a_payload_round_trip_and_a_json_hop() -> void:
	var actor := _born()
	var before: Dictionary = BloodlineApi.state(actor)
	var payload: Dictionary = actor.to_dict()
	var restored := Actor.from_dict(payload)
	assert_eq(
		restored.get_module_data(MODULE_KEY), before, "the payload carried the ledger verbatim"
	)
	assert_almost_eq(BloodlineApi.purity_of(restored, COMMON), 0.9, "and the concentration")
	var parsed = JSON.parse_string(JSON.stringify(payload))
	assert_ne(parsed, null, "the payload is JSON-safe")
	var from_json := Actor.from_dict(parsed as Dictionary)
	assert_eq(BloodlineApi.state(from_json), before, "JSON round trip")
	assert_almost_eq(
		BloodlineApi.purity_of(from_json, COMMON), 0.9, "and the concentration survives"
	)


func test_a_restored_actor_re_derives_the_projection_from_the_ledger() -> void:
	var actor := _born()
	var before := _fingerprint(actor)
	var restored := Actor.from_dict(actor.to_dict())
	# Stat modifiers and traits are NOT core state, so a restored actor arrives with a
	# ledger and nothing else. Attaching is what rebuilds the live actor from it.
	BloodlineApi.attach(restored)
	assert_eq(_fingerprint(restored), before, "the same ledger, traits and totals")
	BloodlineApi.attach(restored)
	assert_eq(_fingerprint(restored), before, "and re-attaching never doubles a grant")


func test_a_legacy_payload_with_no_bloodline_state_loads_cleanly_as_the_empty_ledger() -> void:
	var actor := _born()
	var legacy: Dictionary = actor.to_dict()
	legacy["module_data"] = {}
	var restored := Actor.from_dict(legacy)
	assert_eq(restored.get_module_data(MODULE_KEY), {}, "a legacy payload carries no ledger")
	BloodlineApi.attach(restored)
	var state := BloodlineApi.state(restored)
	assert_eq(int(state["version"]), BloodlineState.SCHEMA_VERSION, "still versioned")
	assert_eq(state["lineages"] as Dictionary, {}, "and empty, not partial")
	assert_almost_eq(BloodlineApi.purity_of(restored, COMMON), 0.0, "nothing is carried")
	assert_eq(BloodlineApi.awake(restored), [], "and nothing is awake")


# --- normalize ---------------------------------------------------------------


func test_normalize_drops_an_entry_naming_content_the_catalog_no_longer_ships() -> void:
	var payload := {
		"version": 1,
		"lineages": {String(RARE): 0.9, "t_retired_line": 0.8},
		"applied": {String(RARE): [String(BloodlineState.trait_for(RARE))]},
	}
	var normalized := BloodlineState.normalize(
		payload, {String(COMMON): true, String(FOUNDING): true}
	)
	assert_eq(normalized["lineages"] as Dictionary, {}, "both entries name dropped content")
	# `applied` is deliberately NOT filtered: that contribution is still sitting on the
	# actor and has to be subtracted, which is exactly when it matters.
	assert_eq(
		(normalized["applied"] as Dictionary).keys().size(),
		1,
		"but the applied one is kept, so nothing is stranded"
	)


func test_a_live_ledger_is_kept_whole_while_its_content_ships() -> void:
	var actor := _born()
	var stored: Dictionary = actor.get_module_data(MODULE_KEY)
	# Re-reading a live payload through the catalog filter must be lossless, or a save
	# round trip would quietly strip the `applied` record the projection needs in order
	# to reverse itself.
	assert_eq(BloodlineState.normalize(stored, {String(COMMON): true}), stored, "kept whole")
	var dropped := BloodlineState.normalize(stored, {String(RARE): true})
	assert_eq(dropped["lineages"] as Dictionary, {}, "the identity entry goes with its definition")
	assert_eq((dropped["applied"] as Dictionary).keys().size(), 1, "but the applied one survives")


func test_every_purity_is_clamped_to_the_unit_interval_on_the_way_in() -> void:
	var normalized := BloodlineState.normalize(
		{"version": 1, "lineages": {String(COMMON): 4.0, String(RARE): -2.0}}
	)
	assert_almost_eq(float(normalized["lineages"][COMMON]), 1.0, "an over-pure entry is capped")
	assert_almost_eq(float(normalized["lineages"][RARE]), 0.0, "and a negative one floors")


func test_an_unreadable_ledger_is_diagnosed_as_empty_rather_than_partially_applied() -> void:
	for payload in [
		{"version": 1, "lineages": "not a dictionary"},
		{"version": 1, "lineages": {String(COMMON): "pure enough"}},
		{"version": 1, "lineages": {String(COMMON): [0.5]}},
		{"version": 1, "lineages": {"": 0.5}},
		{"version": 1, "applied": 17},
		{"version": 1, "applied": {String(COMMON): {"not": "a list"}}},
	]:
		var restored := Actor.new(&"corrupt", {Stat.PHYSIQUE: 10.0})
		restored.set_module_data(MODULE_KEY, payload)
		BloodlineApi.attach(restored)
		var state := BloodlineApi.state(restored)
		assert_eq(state["lineages"] as Dictionary, {}, "rejected payload %s" % [payload])
		assert_eq(BloodlineApi.awake(restored), [], "and nothing is awake for %s" % [payload])
		assert_almost_eq(
			restored.stats.derived(Stat.MAX_HEALTH), 150.0, "and nothing was projected"
		)


func test_a_single_bad_entry_is_dropped_without_discarding_the_rest_of_the_ledger() -> void:
	# One unreadable number is not evidence that the whole dictionary is corrupt, and
	# losing a valid lineage with it would silently strip a real power.
	var normalized := BloodlineState.normalize(
		{"version": 1, "lineages": {String(COMMON): 0.9, String(RARE): {}, String(FOUNDING): 0.5}}
	)
	assert_eq((normalized["lineages"] as Dictionary).keys().size(), 2, "the readable two survive")
	assert_almost_eq(float(normalized["lineages"][COMMON]), 0.9, "and keep their values")


func test_normalize_never_touches_an_absent_payload() -> void:
	assert_eq(
		BloodlineState.normalize({}),
		BloodlineState.empty(),
		"an absent payload is the empty ledger"
	)
	assert_eq(BloodlineState.empty()["lineages"] as Dictionary, {}, "with no lineage")
	assert_eq(BloodlineApi.state(null), BloodlineState.empty(), "and so does a null actor")


func test_source_and_trait_ids_are_namespaced_so_a_rebuild_can_find_them() -> void:
	assert_eq(String(BloodlineState.source_for(RARE)), "bloodline:t_rare", "the modifier source")
	assert_eq(String(BloodlineState.trait_for(RARE)), "bloodline:t_rare", "the trait mirror id")
	assert_eq(
		BloodlineState.is_own_source(BloodlineState.source_for(RARE)), true, "recognised as ours"
	)
	assert_eq(BloodlineState.is_own_source(&"race:stoneborn"), false, "and a sibling's is not")


func test_the_ledger_answers_the_questions_the_rest_of_the_module_asks() -> void:
	var actor := _born()
	BloodlineApi.set_purity(actor, RARE, 0.2)
	BloodlineApi.set_purity(actor, FOUNDING, 0.8)
	var ledger := BloodlineApi.state(actor)
	# Canonical order is ALPHABETICAL, which is what `BloodlineState.lineage_ids` sorts on
	# and what every sibling ledger does. It is not tier order: `t_rare` sorts before
	# `t_common`, and a ledger that ordered by tier would need to know each lineage's tier
	# to read itself.
	assert_eq(
		BloodlineState.lineage_ids(ledger),
		[FOUNDING, RARE, COMMON],
		"every carried lineage, in canonical (sorted) order"
	)
	assert_eq(BloodlineState.awake_ids(ledger), [FOUNDING, COMMON], "and the awake ones")
	assert_almost_eq(BloodlineState.peak(ledger), 0.9, "the strongest")
	assert_almost_eq(BloodlineState.mean(ledger), 1.9 / 3.0, "and the mean")
	assert_almost_eq(
		float(BloodlineState.with_purity(ledger, RARE, 9.0)["lineages"][RARE]),
		1.0,
		"and a write is clamped"
	)


func test_with_purity_will_not_smuggle_in_content_nothing_defines() -> void:
	# `with_purity` is used by the facade's single-lineage write, and it must not be a
	# back door around the catalog check that write already performs.
	var actor := _born()
	BloodlineApi.set_purity(actor, &"t_never_authored", 1.0)
	assert_eq(BloodlineApi.state(actor)["lineages"].has(&"t_never_authored"), false, "refused")
