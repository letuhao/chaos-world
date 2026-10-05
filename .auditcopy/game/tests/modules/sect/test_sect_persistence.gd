extends TestCase

## The ledger is a versioned plain dictionary under `actor.module_data`, so core
## persists it without ever naming a sect type (ADR 0027). These assert the payload
## round trips through both `Actor.to_dict`/`from_dict` and a JSON hop, that a save
## written before the module existed loads clean as empty, and that re-attaching a
## restored actor re-derives the projection from the ledger rather than trusting it —
## which is what makes strip-then-rebuild safe to run again and again.
##
## The stress case is at the bottom: `REPLAY_COUNT` replays through the
## strip/rebuild path must land the derived stat exactly where one replay does. A
## projection that fails to strip compounds once per pass, so the total runs away
## within a handful; the count is bounded because AGENTS.md requires a loop to be
## bounded by a named condition, not because a large number proves more than a
## small one.

const MODULE_KEY := SectState.MODULE_KEY
const HOUSE := &"t_house"
const MEMBER := &"t_member"
const STEWARD := &"t_steward"
const RIVAL := &"t_rival_house"

## How many times the strip/rebuild path is replayed before the derived stat is
## compared. One hundred is two orders of magnitude past what a compounding bug
## needs to show itself, and it returns in milliseconds.
const REPLAY_COUNT := 100


func setup() -> void:
	SectFixtureCatalog.install([SectFixtureCatalog.default_sect(), SectFixtureCatalog.rival_sect()])


func teardown() -> void:
	SectFixtureCatalog.teardown()


func _hero(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	SectApi.attach(actor)
	return actor


## A member as a real one would be: sworn, recognised to the authored cap, and
## holding an office whose allowlist the projection is actually using.
func _sworn(actor_id: StringName = &"keeper") -> Actor:
	var actor := _hero(actor_id)
	SectApi.join(actor, HOUSE)
	SectApi.promote(actor, STEWARD, true)
	SectApi.move_standing(actor, 100)
	return actor


# --- The payload -------------------------------------------------------------


func test_the_ledger_lives_in_the_actors_module_data_as_a_versioned_dictionary() -> void:
	var actor := _sworn()
	var stored: Dictionary = actor.get_module_data(MODULE_KEY)
	assert_eq(int(stored.get("version", 0)), SectState.SCHEMA_VERSION, "versioned")
	assert_eq(String(stored["institution"]), String(HOUSE), "the sect is recorded")
	assert_eq(String(stored["position"]), String(STEWARD), "the office is recorded")
	assert_eq(int(stored["standing"]), 100, "and the standing")
	assert_eq(SectApi.state(actor), stored, "the facade reports the persisted payload")
	for container in ["obligation", "fit", "granted_percent"]:
		for key in (stored[container] as Dictionary).keys():
			assert_eq(typeof(key), TYPE_STRING, "%s key is a String in the payload" % container)


func test_a_whole_claim_survives_both_a_payload_round_trip_and_a_json_hop() -> void:
	var actor := _sworn()
	var before: Dictionary = SectApi.state(actor)
	# A real actor payload round trip: to_dict -> from_dict, no sect type involved.
	var payload: Dictionary = actor.to_dict()
	var restored := Actor.from_dict(payload)
	var carried: Dictionary = restored.get_module_data(MODULE_KEY)
	assert_eq(carried, before, "the payload carried the ledger verbatim")
	SectApi.attach(restored)
	assert_eq(SectApi.state(restored), before, "and it still reads the same")
	assert_eq(String(SectApi.state(restored)["position"]), String(STEWARD), "office intact")
	assert_eq(int(SectApi.state(restored)["standing"]), 100, "standing intact")
	# It survives a JSON hop too, which is what a file-backed save actually does.
	var parsed = JSON.parse_string(JSON.stringify(payload))
	assert_ne(parsed, null, "the payload is JSON-safe")
	var from_json := Actor.from_dict(parsed as Dictionary)
	SectApi.attach(from_json)
	assert_eq(SectApi.state(from_json), before, "JSON round trip")
	assert_eq(int(SectApi.state(from_json)["standing"]), 100, "the standing survived the hop")


func test_a_restored_actor_re_derives_the_projection_from_the_ledger_rather_than_trusting_it(
) -> void:
	var actor := _sworn()
	var before := _fingerprint(actor)
	var restored := Actor.from_dict(actor.to_dict())
	# The trait mirror came back in the payload, because core serializes traits.
	# The stat projection did not: modifiers are always rebuilt from the ledger.
	SectApi.attach(restored)
	assert_eq(_fingerprint(restored), before, "the same ledger, traits, modifiers and totals")
	assert_almost_eq(
		SectProjection.contribution(restored, Stat.INSIGHT_GAIN), 0.10, "the full claim is granted"
	)


func test_re_attaching_never_double_counts_a_claim() -> void:
	var actor := _sworn()
	var once := _fingerprint(actor)
	for cycle in 4:
		SectApi.attach(actor)
		assert_eq(_fingerprint(actor), once, "attach %d leaves the actor identical" % cycle)
	assert_eq(_own_modifiers(actor), 1, "one office, one modifier")
	assert_almost_eq(
		SectProjection.contribution(actor, Stat.INSIGHT_GAIN), 0.10, "granted once, not four times"
	)
	# And on a restored actor, which is the case that actually matters: a save is
	# loaded and attached far more often than it is created.
	var restored := Actor.from_dict(actor.to_dict())
	SectApi.attach(restored)
	var restored_once := _fingerprint(restored)
	for cycle in 4:
		SectApi.attach(restored)
		assert_eq(_fingerprint(restored), restored_once, "restored attach %d" % cycle)
	assert_almost_eq(
		SectProjection.contribution(restored, Stat.INSIGHT_GAIN),
		0.10,
		"a restored actor is granted once too"
	)


func test_a_promotion_replayed_many_times_leaves_the_stat_exactly_where_one_leaves_it() -> void:
	var actor := _hero()
	SectApi.join(actor, HOUSE)
	SectApi.move_standing(actor, 100)
	SectApi.promote(actor, STEWARD)
	var expected := actor.stats.derived(Stat.MAX_HEALTH)
	assert_almost_eq(
		SectProjection.contribution(actor, Stat.INSIGHT_GAIN), 0.10, "one promotion, one grant"
	)
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_HEALTH),
		expected,
		"and the derived stat is where one promotion put it"
	)
	# The stress case. REPLAY_COUNT iterations is the bound this loop needs, and
	# the bound is the assertion's own subject: a projection that fails to strip
	# compounds once per pass, so a hundred replays already move the total far
	# enough to catch it. A million was the original figure here and it was wrong
	# on this repo's own terms — AGENTS.md rules that a loop exists to be bounded
	# by a named condition, and an unbounded million is what turns a test into a
	# hang rather than a failure. Repetition count is a tuning value, not a proof.
	for iteration in REPLAY_COUNT:
		SectApi.promote(actor, STEWARD)
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_HEALTH),
		expected,
		"%d replays leave the derived stat exactly where one does" % REPLAY_COUNT
	)
	assert_almost_eq(
		SectProjection.contribution(actor, Stat.INSIGHT_GAIN),
		0.10,
		"and the granted percent never compounded"
	)
	assert_eq(_own_modifiers(actor), 1, "one modifier on the stack, not one per replay")
	assert_eq(actor.traits.to_array(), ["sect:t_house"], "and one membership mirror")


func test_a_legacy_payload_with_no_sect_state_loads_cleanly_as_the_empty_ledger() -> void:
	var actor := _sworn()
	var legacy: Dictionary = actor.to_dict()
	legacy["module_data"] = {}
	legacy.erase("item_state")
	var restored := Actor.from_dict(legacy)
	assert_eq(restored.get_module_data(MODULE_KEY), {}, "a legacy payload carries no ledger")
	SectApi.attach(restored)
	var state := SectApi.state(restored)
	assert_eq(int(state["version"]), SectState.SCHEMA_VERSION, "still versioned")
	assert_eq(String(state["institution"]), "", "and empty, not partial")
	assert_eq(String(state["position"]), "", "no invented office either")
	assert_eq(restored.get_module_data(MODULE_KEY)["institution"], "", "written back empty")
	assert_eq(_own_modifiers(restored), 0, "and nothing was projected")
	assert_eq(restored.traits.has(SectState.trait_for(HOUSE)), false, "no membership mirror")


func test_a_payload_naming_a_sect_this_build_does_not_ship_is_refused_rather_than_projected(
) -> void:
	var restored := _hero(&"wide_save")
	(
		restored
		. set_module_data(
			MODULE_KEY,
			{
				"institution": "t_retired_house",
				"position": "t_retired_steward",
				"standing": 80,
				"standing_cap": 100,
				"granted_percent": {"insight_gain": 0.08},
				"applied_standing": 80,
			}
		)
	)
	SectApi.attach(restored)
	# The office is dropped, because this build does not author it. The sect id and
	# the standing stay: a member who earned standing earned it, and losing the
	# authored office must not silently strip what the sect gave them for it.
	var state := SectApi.state(restored)
	assert_eq(String(state["position"]), "", "an unshipped office is dropped")
	assert_eq(int(state["standing"]), 80, "but the standing survives")
	# And nothing projects, because the institution itself is unknown here.
	assert_eq(_own_modifiers(restored), 0, "an unknown sect projects nothing")
	assert_eq(SectProjection.contribution(restored, Stat.INSIGHT_GAIN), 0.0, "and grants nothing")
	# The grant record is cleared, so a later attach has nothing stale to strip.
	assert_eq(state["granted_percent"] as Dictionary, {}, "the stale grant is cleared")
	assert_eq(int(state["applied_standing"]), 0, "and so is the applied standing")


func test_an_unreadable_ledger_is_diagnosed_as_empty_rather_than_partially_applied() -> void:
	# Rule, in two halves, because the difference between them is the whole point.
	#
	# A field that IS the claim — `institution`, `position`, `standing` — arriving
	# as the wrong type is not a ledger with one bad field. Coercing it would
	# invent a membership and a standing out of bytes, so the whole payload is
	# refused and the member reads as unaffiliated.
	for payload in [
		{"version": 1, "institution": "t_house", "standing": "many"},
		{"version": 1, "institution": {"not": "text"}, "position": "t_steward"},
	]:
		var restored := _hero(&"corrupt")
		restored.set_module_data(MODULE_KEY, payload)
		SectApi.attach(restored)
		assert_eq(
			String(SectApi.state(restored)["institution"]), "", "rejected payload %s" % [payload]
		)

	# The maps beside the claim are the other half. An unreadable `obligation`,
	# `fit` or `granted_percent` is one unusable line beside three good fields, so
	# it drops that map and KEEPS the member's earned standing. Taking standing
	# away because an unrelated line went bad is the worse failure — the member
	# did not do anything to lose it.
	for payload in [
		{"version": 1, "institution": "t_house", "position": "t_steward", "standing": 30, "fit": 3},
		{
			"version": 1,
			"institution": "t_house",
			"position": "t_steward",
			"standing": 30,
			"obligation": "no",
		},
		{
			"version": 1,
			"institution": "t_house",
			"position": "t_steward",
			"standing": 30,
			"granted_percent": ["not", "a", "map"],
		},
	]:
		var restored := _hero(&"partial")
		restored.set_module_data(MODULE_KEY, payload)
		SectApi.attach(restored)
		var kept := SectApi.state(restored)
		assert_eq(String(kept["institution"]), "t_house", "readable fields survive %s" % [payload])
		assert_eq(String(kept["position"]), "t_steward", "including the office")
		assert_eq(int(kept["standing"]), 30, "including the earned standing")
		# The dropped map is dropped empty, never left holding the unreadable
		# value: a later attach must not find an array where a map belongs.
		assert_eq(kept["fit"] as Dictionary, {}, "and the unreadable map reads empty")
		assert_eq(kept["obligation"] as Dictionary, {}, "whichever map it was")


func test_leaving_a_sect_closes_the_claim_and_a_new_one_opens_clean() -> void:
	var actor := _sworn()
	assert_eq(bool(SectApi.leave(actor)["ok"]), true, "leaving is always permitted")
	var empty := SectApi.state(actor)
	assert_eq(String(empty["institution"]), "", "the claim is closed")
	assert_eq(String(empty["position"]), "", "and so is the office")
	assert_eq(_own_modifiers(actor), 0, "nothing is left projected")
	assert_eq(actor.traits.has(SectState.trait_for(HOUSE)), false, "nor a membership mirror")
	# A new sect is a new claim: standing does not travel with the member.
	assert_eq(bool(SectApi.join(actor, RIVAL)["ok"]), true, "so another join is legal")
	var fresh := SectApi.state(actor)
	assert_eq(String(fresh["institution"]), String(RIVAL), "sworn to the rival house")
	assert_eq(int(fresh["standing"]), 0, "at standing zero, as a new claim starts")
	assert_eq(int(fresh["standing_cap"]), 80, "under the rival house's authored cap")


# --- Helpers -----------------------------------------------------------------


func ledger(actor: Actor) -> Dictionary:
	return SectApi.state(actor)


## Everything a drift assertion needs: the claim, the membership mirror, this
## module's modifiers, and the derived totals the office's allowlist moves.
func _fingerprint(actor: Actor) -> Dictionary:
	return {
		"institution": String(ledger(actor)["institution"]),
		"position": String(ledger(actor)["position"]),
		"standing": int(ledger(actor)["standing"]),
		"standing_cap": int(ledger(actor)["standing_cap"]),
		"granted_percent": ledger(actor)["granted_percent"],
		"traits": actor.traits.to_array(),
		"modifiers": _own_modifiers(actor),
		"insight": SectProjection.contribution(actor, Stat.INSIGHT_GAIN),
		"max_health": actor.stats.derived(Stat.MAX_HEALTH),
		"defense": actor.stats.derived(Stat.DEFENSE_PHYSICAL),
	}


func _own_modifiers(actor: Actor) -> int:
	var total := 0
	for modifier in actor.stats._modifiers:
		if SectState.is_own_source(modifier.source):
			total += 1
	return total
