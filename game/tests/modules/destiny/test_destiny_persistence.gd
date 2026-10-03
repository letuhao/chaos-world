extends TestCase

## The ledger is a versioned plain dictionary under `actor.module_data`, so core
## persists it without ever naming a fate type (ADR 0027). These assert the
## payload round trips through both `Actor.to_dict`/`from_dict` and a JSON hop,
## that a save written before the module existed loads clean as empty, and that
## attaching to a restored actor re-derives the live state from the ledger rather
## than trusting it — which is what makes an earn-only ledger safe to replay.

const MODULE_KEY := DestinyState.MODULE_KEY
const OATH := &"t_oath_breaker"
const PLEDGE := &"t_blood_pledge"
const CHOSEN := &"t_chosen_one"
const DUELS := &"duels_won"


func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.flat_fate(OATH, Stat.DEFENSE_PHYSICAL, 3.0),
				DestinyFixtureCatalog.flat_fate(PLEDGE, Stat.ATTACK_PHYSICAL, 2.0),
			],
			[DestinyFixtureCatalog.plain_destiny(CHOSEN)]
		)
	)


func teardown() -> void:
	DestinyFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	return actor


## An actor who has earned the same things a real one would: a fate for the deed,
## a destiny the story arrived at, and a counter that has been climbing.
func _earned(actor_id: StringName = &"keeper") -> Actor:
	var actor := _hero(actor_id)
	DestinyApi.earn_fate(actor, OATH, "combat")
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	DestinyApi.record(actor, DUELS, 3)
	return actor


# --- The payload -------------------------------------------------------------


func test_the_ledger_lives_in_the_actors_module_data_as_a_versioned_dictionary() -> void:
	var actor := _earned()
	var stored: Dictionary = actor.get_module_data(MODULE_KEY)
	assert_eq(int(stored.get("version", 0)), DestinyState.SCHEMA_VERSION, "versioned")
	var fate: Dictionary = (stored["fates"] as Dictionary)[String(OATH)]
	assert_eq(String(fate["source"]), "combat", "the fate records the system that earned it")
	assert_eq(int(fate["sequence"]) > 0, true, "and when, relative to everything else")
	var destiny: Dictionary = (stored["destinies"] as Dictionary)[String(CHOSEN)]
	assert_eq(String(destiny["bearing"]), "You are bound to t_chosen_one.", "the bearing is kept")
	assert_eq(int(stored["counters"][String(DUELS)]), 3, "the counter is kept")
	assert_eq(DestinyApi.state(actor), stored, "the facade reports the persisted payload")


func test_held_fates_destinies_and_counters_survive_a_payload_round_trip() -> void:
	var actor := _earned()
	var before: Dictionary = DestinyApi.state(actor)
	# A real actor payload round trip: to_dict -> from_dict, no fate type involved.
	var payload: Dictionary = actor.to_dict()
	var restored := Actor.from_dict(payload)
	var carried: Dictionary = restored.get_module_data(MODULE_KEY)
	assert_eq(carried, before, "the payload carried the ledger verbatim")
	assert_eq(DestinyApi.fates(restored), [OATH], "the fate is still held")
	assert_eq(DestinyApi.destinies(restored), [CHOSEN], "so is the destiny")
	assert_eq(DestinyApi.counter(restored, DUELS), 3, "and the counter")
	# It survives a JSON hop, which is what a file-backed save does.
	var parsed = JSON.parse_string(JSON.stringify(payload))
	assert_ne(parsed, null, "the payload is JSON-safe")
	var from_json := Actor.from_dict(parsed as Dictionary)
	assert_eq(DestinyApi.state(from_json), before, "JSON round trip")
	assert_eq(DestinyApi.fates(from_json), [OATH], "the fate survives the hop")
	assert_eq(DestinyApi.counter(from_json, DUELS), 3, "and so does the counter")


func test_a_restored_actor_re_derives_the_projection_from_the_ledger_rather_than_trusting_it(
) -> void:
	var actor := _earned()
	var before := _fingerprint(actor)
	var restored := Actor.from_dict(actor.to_dict())
	# The trait mirror came back in the payload, because core serializes traits.
	# The stat projection did not: modifiers are always rebuilt from the ledger.
	DestinyApi.attach(restored)
	assert_eq(_fingerprint(restored), before, "the same ledger, traits, modifiers and totals")
	# Attaching again must not double anything: the projection strips before it
	# rebuilds, so a replayed attach is free of consequence.
	DestinyApi.attach(restored)
	DestinyApi.attach(restored)
	assert_eq(_fingerprint(restored), before, "and re-attaching never doubles a fate")
	assert_eq(
		DestinyProjection.contribution(restored, Stat.DEFENSE_PHYSICAL),
		{"flat": 3.0, "percent": 0.3},
		"one fate, once, with its flat and percent channels kept apart"
	)


func test_a_legacy_payload_with_no_destiny_state_loads_cleanly_as_the_empty_ledger() -> void:
	var actor := _earned()
	var legacy: Dictionary = actor.to_dict()
	legacy["module_data"] = {}
	legacy.erase("item_state")
	var restored := Actor.from_dict(legacy)
	assert_eq(restored.get_module_data(MODULE_KEY), {}, "a legacy payload carries no ledger")
	DestinyApi.attach(restored)
	var state := DestinyApi.state(restored)
	assert_eq(int(state["version"]), DestinyState.SCHEMA_VERSION, "still versioned")
	assert_eq(state["fates"] as Dictionary, {}, "and empty, not partial")
	assert_eq(restored.get_module_data(MODULE_KEY)["fates"] as Dictionary, {}, "written back empty")
	assert_eq(DestinyApi.fates(restored), [], "nothing is held")
	assert_eq(_destiny_modifiers(restored), 0, "and nothing was projected")


func test_an_unreadable_ledger_is_diagnosed_as_empty_rather_than_partially_applied() -> void:
	for payload in [
		{"version": 1, "fates": "not a dictionary"},
		{"version": 1, "counters": {"duels_won": -3}},
		{"version": 1, "fates": {"t_oath_breaker": {"sequence": 1}}},
	]:
		var restored := _hero(&"corrupt")
		restored.set_module_data(MODULE_KEY, payload)
		DestinyApi.attach(restored)
		var state := DestinyApi.state(restored)
		assert_eq(state["fates"] as Dictionary, {}, "rejected payload %s" % [payload])
		assert_eq(state["counters"] as Dictionary, {}, "including its counters")
	# The entry that the live catalog still ships is kept even out of a malformed
	# payload: unreadable neighbours do not condemn the ones beside them.
	var partial := _hero(&"partial")
	partial.set_module_data(
		MODULE_KEY,
		{"version": 1, "fates": {"t_oath_breaker": "junk", "t_retired": {"source": "old"}}}
	)
	DestinyApi.attach(partial)
	assert_eq(DestinyApi.fates(partial), [], "neither entry is readable")


## Everything a numeric drift assertion needs: the held ids, the stat sources on
## the stack, the trait mirror and the two derived totals the fixture fates move.
func _fingerprint(actor: Actor) -> Dictionary:
	return {
		"fates": DestinyApi.fates(actor),
		"destinies": DestinyApi.destinies(actor),
		"traits": actor.traits.to_array(),
		"sources": _destiny_sources(actor),
		"defense": DestinyProjection.contribution(actor, Stat.DEFENSE_PHYSICAL),
		"attack": DestinyProjection.contribution(actor, Stat.ATTACK_PHYSICAL),
		"derived_defense": actor.stats.derived(Stat.DEFENSE_PHYSICAL),
		"max_health": actor.stats.derived(Stat.MAX_HEALTH),
	}


## Every stat-modifier source this module currently owns.
func _destiny_sources(actor: Actor) -> Array:
	var out: Array = []
	for modifier in actor.stats._modifiers:
		if DestinyState.is_own_source(modifier.source):
			out.append(String(modifier.source))
	out.sort()
	return out


## How many stat modifiers this module currently owns.
func _destiny_modifiers(actor: Actor) -> int:
	return DestinyProjection.modifier_count(actor)
