extends TestCase

## The ledger is a versioned plain dictionary under `actor.module_data`, so core
## persists it without ever naming a race (ADR 0027). These assert the payload round
## trips through `Actor.to_dict`/`from_dict` and a JSON hop, that a save written before
## the module existed loads clean as empty, and that attaching to a restored actor
## re-derives the live projection from the ledger rather than trusting the payload.

const MODULE_KEY := RaceState.MODULE_KEY
const STONE := &"t_stone"
const TIDE := &"t_tide"
const BASE := &"t_base"


func setup() -> void:
	(
		RaceFixtureCatalog
		. install(
			[
				RaceFixtureCatalog.capped(STONE, &"mind_cultivation", 8, Stat.PHYSIQUE),
				RaceFixtureCatalog.closed(TIDE, &"body_cultivation", 0.5),
				RaceFixtureCatalog.closed(BASE, &"mind_cultivation", 0.2),
			],
			BASE
		)
	)


func teardown() -> void:
	RaceFixtureCatalog.teardown()


func _born(race_id: StringName, actor_id: StringName = &"child") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	RaceApi.attach(actor)
	RaceApi.set_race(actor, race_id)
	return actor


func _fingerprint(actor: Actor) -> Dictionary:
	var sources: Array = []
	for modifier in actor.stats._modifiers:
		if RaceState.is_own_source(modifier.source):
			sources.append(String(modifier.source))
	sources.sort()
	return {
		"race": String(RaceApi.race_of(actor)),
		"traits": actor.traits.to_array(),
		"base": actor.stats.base_dict(),
		"affinities": actor.affinities.to_dict(),
		"sources": sources,
		"max_health": actor.stats.derived(Stat.MAX_HEALTH),
		"ceiling": actor.stats.derived(RaceStats.REALM_CEILING),
	}


# --- The payload -------------------------------------------------------------


func test_the_ledger_lives_in_the_actors_module_data_as_a_versioned_dictionary() -> void:
	var actor := _born(STONE)
	var stored: Dictionary = actor.get_module_data(MODULE_KEY)
	assert_eq(int(stored.get("version", 0)), RaceState.SCHEMA_VERSION, "versioned")
	assert_eq(String(stored["race"]), String(STONE), "the race is recorded")
	assert_eq(String(stored["applied_race"]), String(STONE), "and so is what was projected")
	assert_eq(
		RaceState.grants(stored, STONE)["attributes"],
		{"physique": 4.0},
		"the base-attribute grant is remembered, because a strip needs it"
	)
	assert_eq(RaceApi.state(actor), stored, "the facade reports the persisted payload")


func test_a_race_survives_a_payload_round_trip_and_a_json_hop() -> void:
	var actor := _born(STONE)
	var before: Dictionary = RaceApi.state(actor)
	var payload: Dictionary = actor.to_dict()
	var restored := Actor.from_dict(payload)
	assert_eq(
		restored.get_module_data(MODULE_KEY), before, "the payload carried the ledger verbatim"
	)
	assert_eq(RaceApi.race_of(restored), STONE, "the race is still the actor's")
	var parsed = JSON.parse_string(JSON.stringify(payload))
	assert_ne(parsed, null, "the payload is JSON-safe")
	var from_json := Actor.from_dict(parsed as Dictionary)
	assert_eq(RaceApi.state(from_json), before, "JSON round trip")
	assert_eq(RaceApi.race_of(from_json), STONE, "and the race survives the hop")


func test_a_restored_actor_re_derives_the_projection_from_the_ledger() -> void:
	var actor := _born(STONE)
	var before := _fingerprint(actor)
	var restored := Actor.from_dict(actor.to_dict())
	# Base attributes DO come back in the payload, because core serializes them. The
	# affinity grants and the stat projection do not. Attaching must therefore be
	# careful: re-granting an affinity already restored would double it, and the
	# ledger's grant record is what keeps the rebuild exact.
	RaceApi.attach(restored)
	assert_eq(_fingerprint(restored), before, "the same ledger, traits, bases and totals")
	RaceApi.attach(restored)
	assert_eq(_fingerprint(restored), before, "and re-attaching never doubles a grant")


func test_a_legacy_payload_with_no_race_state_loads_cleanly_as_the_empty_ledger() -> void:
	var actor := _born(STONE)
	var legacy: Dictionary = actor.to_dict()
	legacy["module_data"] = {}
	legacy.erase("item_state")
	var restored := Actor.from_dict(legacy)
	assert_eq(restored.get_module_data(MODULE_KEY), {}, "a legacy payload carries no ledger")
	RaceApi.attach(restored)
	var state := RaceApi.state(restored)
	assert_eq(int(state["version"]), RaceState.SCHEMA_VERSION, "still versioned")
	assert_eq(String(state["race"]), "", "and empty, not partial")
	assert_eq(RaceApi.race_of(restored), &"", "nothing is assigned")
	assert_eq(RaceApi.race_definition(restored), null, "and no definition resolves")


func test_normalize_drops_an_entry_naming_content_the_catalog_no_longer_ships() -> void:
	var payload := {
		"version": 1,
		"race": String(STONE),
		"applied_race": String(STONE),
		"granted": {String(STONE): {"attributes": {"physique": 4.0}}},
	}
	var normalized := RaceState.normalize(payload, {"t_tide": true, "t_base": true})
	assert_eq(String(normalized["race"]), "", "the retired race is dropped from identity")
	# `applied_race` is deliberately NOT filtered: that contribution is still sitting
	# on the actor and has to be subtracted, which is exactly when it matters.
	assert_eq(String(normalized["applied_race"]), String(STONE), "but the applied one is kept")
	assert_eq(normalized["granted"] as Dictionary, {}, "and a grant with no definition goes")


func test_a_live_grant_record_is_kept_whole_and_dropped_only_with_its_definition() -> void:
	var actor := _born(STONE)
	var stored: Dictionary = actor.get_module_data(MODULE_KEY)
	# Re-reading a live payload through the catalog filter must be lossless while the
	# definition ships, or a save round trip would quietly strip the grant record the
	# projection needs in order to reverse itself.
	var kept := RaceState.normalize(stored, {String(STONE): true})
	assert_eq(kept, stored, "kept whole while the definition ships")
	var dropped := RaceState.normalize(stored, {String(TIDE): true})
	assert_eq(String(dropped["race"]), "", "the identity entry is dropped without it")
	assert_eq(String(dropped["applied_race"]), String(STONE), "the applied one survives")
	assert_eq(dropped["granted"] as Dictionary, {}, "and the grant goes with the definition")


func test_an_unreadable_ledger_is_diagnosed_as_empty_rather_than_partially_applied() -> void:
	for payload in [
		{"version": 1, "race": 42},
		{"version": 1, "granted": "not a dictionary"},
		{"version": 1, "granted": {String(STONE): "junk"}},
		{"version": 1, "granted": {String(STONE): {"attributes": {"physique": "many"}}}},
		{"version": 1, "race": String(STONE), "applied_race": 17},
	]:
		var restored := Actor.new(&"corrupt", {Stat.PHYSIQUE: 10.0})
		restored.set_module_data(MODULE_KEY, payload)
		RaceApi.attach(restored)
		var state := RaceApi.state(restored)
		assert_eq(String(state["race"]), "", "rejected payload %s" % [payload])
		assert_eq(String(state["applied_race"]), "", "including the applied race")
		assert_eq(state["granted"] as Dictionary, {}, "including its grants")
		assert_eq(restored.stats.get_base(Stat.PHYSIQUE), 10.0, "and nothing was projected")


func test_normalize_never_touches_an_absent_payload() -> void:
	assert_eq(RaceState.normalize({}), RaceState.empty(), "an absent payload is the empty ledger")
	assert_eq(String(RaceState.empty()["race"]), "", "with no race")
	assert_eq(RaceApi.state(null), RaceState.empty(), "and so does a null actor")


func test_source_and_trait_ids_are_namespaced_so_a_rebuild_can_find_them() -> void:
	assert_eq(String(RaceState.source_for(STONE)), "race:t_stone", "the modifier source")
	assert_eq(String(RaceState.trait_for(STONE)), "race:t_stone", "the trait mirror id")
	assert_eq(RaceState.is_own_source(RaceState.source_for(STONE)), true, "recognised as ours")
	assert_eq(RaceState.is_own_source(&"destiny:oath"), false, "and a sibling's is not")
