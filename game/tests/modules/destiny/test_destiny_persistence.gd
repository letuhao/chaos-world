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
## A fate on a third stat, so the fingerprint's `max_health` entry has something
## to disagree about.
const ASCENT := &"t_ascendant_health"


## The catalog holding exactly the ids this suite earns through. Every fate the
## round-trip test earns is named here, so `attach()` never filters an entry the
## test itself put in the ledger.
func setup() -> void:
	(
		DestinyFixtureCatalog
		. install(
			[
				DestinyFixtureCatalog.flat_fate(OATH, Stat.DEFENSE_PHYSICAL, 3.0),
				DestinyFixtureCatalog.flat_fate(PLEDGE, Stat.ATTACK_PHYSICAL, 2.0),
				# A fate on a DIFFERENT stat, so `_fingerprint`'s `max_health` entry
				# compares 150.0 against something other than 150.0. With only the two
				# stats above installed, that entry compared the actor's untouched base
				# total with itself and could not fail.
				DestinyFixtureCatalog.flat_fate(ASCENT, Stat.MAX_HEALTH, 25.0),
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
	DestinyApi.earn_fate(actor, ASCENT, "path")
	DestinyApi.earn_destiny(actor, CHOSEN, "story")
	DestinyApi.record(actor, DUELS, 3)
	return actor


# --- The payload -------------------------------------------------------------


func test_the_ledger_lives_in_the_actors_module_data_as_a_versioned_dictionary() -> void:
	var actor := _earned()
	var stored: Dictionary = actor.get_module_data(MODULE_KEY)
	assert_eq(int(stored.get("version", 0)), DestinyState.SCHEMA_VERSION, "versioned")
	var fate := _entry(stored["fates"], OATH)
	assert_eq(String(fate["source"]), "combat", "the fate records the system that earned it")
	assert_eq(int(fate["sequence"]) > 0, true, "and when, relative to everything else")
	var destiny := _entry(stored["destinies"], CHOSEN)
	assert_eq(String(destiny["bearing"]), "You are bound to t_chosen_one.", "the bearing is kept")
	assert_eq(int((stored["counters"] as Dictionary)[String(DUELS)]), 3, "the counter is kept")
	assert_eq(DestinyApi.state(actor), stored, "the facade reports the persisted payload")


func test_held_fates_destinies_and_counters_survive_a_payload_round_trip() -> void:
	var actor := _earned()
	var before: Dictionary = DestinyApi.state(actor)
	# A real actor payload round trip: to_dict -> from_dict, no fate type involved.
	var payload: Dictionary = actor.to_dict()
	var restored := Actor.from_dict(payload)
	var carried: Dictionary = restored.get_module_data(MODULE_KEY)
	assert_eq(carried, before, "the payload carried the ledger verbatim")
	assert_eq(DestinyApi.fates(restored), _held_fates(), "the fates are still held")
	assert_eq(DestinyApi.destinies(restored), [CHOSEN], "so is the destiny")
	assert_eq(DestinyApi.counter(restored, DUELS), 3, "and the counter")
	# It survives a JSON hop, which is what a file-backed save does.
	var parsed = JSON.parse_string(JSON.stringify(payload))
	assert_ne(parsed, null, "the payload is JSON-safe")
	var from_json := Actor.from_dict(parsed as Dictionary)
	assert_eq(DestinyApi.state(from_json), before, "JSON round trip")
	assert_eq(DestinyApi.fates(from_json), _held_fates(), "the fates survive the hop")
	assert_eq(DestinyApi.counter(from_json, DUELS), 3, "and so does the counter")


## The fates `_earned()` earns, in the canonical order the facade hands them back.
## Canonical, not earned order, so the assertion is about the id list itself rather
## than about which call happened to come first.
func _held_fates() -> Array[StringName]:
	return [ASCENT, OATH]


func test_a_restored_actor_re_derives_the_projection_from_the_ledger_rather_than_trusting_it(
) -> void:
	var actor := _earned()
	var before := _fingerprint(actor)
	var restored := Actor.from_dict(actor.to_dict())
	# The trait mirror came back in the payload, because core serializes traits.
	# The stat projection did not: modifiers are always rebuilt from the ledger.
	DestinyApi.attach(restored)
	assert_eq(_fingerprint(restored), before, "the same ledger, traits, modifiers and totals")
	# The fingerprint is only worth comparing if its entries can differ: a
	# projection that dropped every fate would reproduce the same fingerprint. So
	# the fate on `max_health` has to be visibly moving that derived total. The
	# absolute figure belongs to somebody else — the PHYSIQUE curve and realm
	# scaling both feed it — so what is asserted is that the projection raised it,
	# not what it raised it to. With only DEFENSE_PHYSICAL and ATTACK_PHYSICAL
	# installed, this entry compared the actor's untouched total with itself and
	# could never fail.
	assert_eq(
		DestinyProjection.contribution(actor, Stat.MAX_HEALTH),
		{"flat": 25.0, "percent": 2.5},
		"the max_health fate is on the stack with both of its channels"
	)
	var with_fate := actor.stats.derived(Stat.MAX_HEALTH)
	DestinyProjection.strip(actor)
	var without_fate := actor.stats.derived(Stat.MAX_HEALTH)
	assert_eq(
		float(with_fate) > float(without_fate),
		true,
		"and the derived total genuinely moves, so the fingerprint entry can catch a drift"
	)
	DestinyProjection.apply(actor, DestinyApi.state(actor))
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
	# Both entries here name content the fixture catalog does not ship — `setup()`
	# installs only OATH and PLEDGE — so the catalog filter rejects them on read
	# exactly as it would reject a save from a wider content build. Neither is
	# readable as a fate entry, and neither names content the catalog still ships,
	# so neither can survive into the normalized ledger.
	var partial := _hero(&"partial")
	partial.set_module_data(
		MODULE_KEY,
		{"version": 1, "fates": {"t_oath_breaker": "junk", "t_retired": {"source": "old"}}}
	)
	DestinyApi.attach(partial)
	assert_eq(DestinyApi.fates(partial), [], "neither entry survives")


## One ledger entry, fetched through `.get()` with a shape assertion in front of
## it.
##
## A typed local assigned an unvalidated subscript ABORTS the function it happens
## in, and the runner calls each test with `suite.call(name)` — so the abort looks
## like a test that finished, and every assertion after it is silently skipped
## while the suite still reports green. Fetching defensively turns "the ledger
## does not hold what this test was just told it holds" into a named failure that
## keeps the rest of the test running. Returns `{}` on failure, so the assertions
## that follow also report rather than abort.
func _entry(section, entry_id: StringName) -> Dictionary:
	var id := String(entry_id)
	var entries := section as Dictionary
	var found = entries.get(id, null)
	if found is Dictionary and not (found as Dictionary).is_empty():
		return found as Dictionary
	assert_eq(
		found is Dictionary and not (found as Dictionary).is_empty(),
		true,
		"the ledger holds a readable '%s' entry" % id
	)
	return {}


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
