extends "res://tests/modules/event/event_director_fixture.gd"

## End-to-end proof that the ambient-fact -> event-trigger chain works.
##
## The chain under test:
##
##   WorldPulse._advance(periods)
##     -> _offer_ambient(horizon)          // calls WorldAmbient.due(actor, horizon)
##     -> WorldAmbient.due(actor, horizon) // returns facts whose at_period <= horizon
##     -> WorldPulse.offer(fact, 1, AMBIENT_SOURCE)
##     -> BeatDirector.offer(actor, beat)  // records to WorldFact, then consults sinks
##     -> WorldFact.record(actor, fact, amount)
##
## Then when _open_available runs:
##
##   EventApi.available(actor)
##     -> EventGate.evaluate(actor, def.trigger)
##     -> _has_fact(actor, requirement)    // reads EventFacts.count_of(actor, fact_id)
##
## This file proves each link and the whole chain together.

const AMBIENT_STORM := &"storm_front_sighted"
const AMBIENT_VOID_SEAM := &"void_seam_sounded"
const AMBIENT_TOURNAMENT := &"tournament_called"
const AMBIENT_SECT_WAR := &"sect_war_called"

const TIDE_EVENT := &"beast_tide_of_the_mortal_plains"


## The production composition root's world, built the way
## `app/item_workbench_app.gd` builds it.
func _world(actor: Actor) -> WorldPulse:
	return WorldPulse.new(actor, BeatDirector.new())


# --- 1. Ambient facts reach the ledger --------------------------------------


func test_ambient_facts_reach_the_ledger_after_advance() -> void:
	var actor := _actor(&"mortal_plains")
	var pulse := _world(actor)

	assert_eq(WorldFact.count(actor, AMBIENT_STORM), 0, "no storm front sighted yet")
	assert_eq(WorldFact.count(actor, AMBIENT_VOID_SEAM), 0, "no void seam sounded yet")

	pulse.advance_periods(1)

	assert_eq(
		WorldFact.count(actor, AMBIENT_STORM),
		1,
		"storm_front_sighted reached the ledger after one period"
	)
	assert_eq(
		WorldFact.count(actor, AMBIENT_VOID_SEAM),
		0,
		"void_seam_sounded is not due until period 2"
	)

	pulse.advance_periods(1)

	assert_eq(
		WorldFact.count(actor, AMBIENT_VOID_SEAM),
		1,
		"void_seam_sounded reached the ledger after two periods"
	)


func test_all_roster_facts_reach_the_ledger_after_four_periods() -> void:
	var actor := _actor(&"mortal_plains")
	var pulse := _world(actor)

	pulse.advance_periods(4)

	for fact in [AMBIENT_STORM, AMBIENT_VOID_SEAM, AMBIENT_TOURNAMENT, AMBIENT_SECT_WAR]:
		assert_eq(
			WorldFact.count(actor, fact),
			1,
			"ambient fact '%s' is in the ledger after four periods" % fact
		)


# --- 2. EventGate.evaluate passes -------------------------------------------


func test_event_gate_passes_once_ambient_fact_is_in_ledger() -> void:
	var actor := _actor(&"mortal_plains")

	var def := EventCatalog.instance().event_definition(TIDE_EVENT)

	var gate_before := EventGate.evaluate(actor, def.trigger)
	assert_eq(bool(gate_before.get("ok", false)), false, "gate refuses before the fact")

	# Put the fact in the ledger directly (not via advance, so the event stays closed)
	_remember(actor, AMBIENT_STORM)

	var gate_after := EventGate.evaluate(actor, def.trigger)
	assert_eq(
		bool(gate_after.get("ok", false)),
		true,
		"gate passes once the ambient fact is in the ledger"
	)


# --- 3. EventApi.begin succeeds ---------------------------------------------


func test_event_api_begin_succeeds_after_ambient_fact() -> void:
	var actor := _actor(&"mortal_plains")

	var refused := EventApi.begin(actor, TIDE_EVENT)
	assert_eq(bool(refused.get("ok", false)), false, "begin refuses before the ambient fact")
	assert_eq(
		String(refused.get("reason", "")),
		EventState.R_TRIGGER_UNMET,
		"with trigger_unmet"
	)

	# Put the fact in the ledger directly (not via advance, so the event stays closed)
	_remember(actor, AMBIENT_STORM)

	var opened := EventApi.begin(actor, TIDE_EVENT)
	assert_eq(
		bool(opened.get("ok", false)),
		true,
		"begin succeeds once the ambient fact is in the ledger"
	)


# --- 4. EventApi.available returns it ---------------------------------------


func test_event_api_available_includes_event_after_ambient_fact() -> void:
	var actor := _actor(&"mortal_plains")

	assert_eq(
		_available_ids(actor).has(String(TIDE_EVENT)),
		false,
		"event is not available before the ambient fact"
	)

	# Put the fact in the ledger directly (not via advance, so the event stays closed)
	_remember(actor, AMBIENT_STORM)

	assert_eq(
		_available_ids(actor).has(String(TIDE_EVENT)),
		true,
		"event is available once the ambient fact is in the ledger"
	)


# --- 5. The full chain in one test ------------------------------------------


func test_full_chain_ambient_fact_to_open_event() -> void:
	var actor := _actor(&"mortal_plains")
	var pulse := _world(actor)

	# Before: nothing has happened
	assert_eq(WorldFact.count(actor, AMBIENT_STORM), 0, "no ambient fact yet")

	var def := EventCatalog.instance().event_definition(TIDE_EVENT)
	assert_eq(bool(EventGate.evaluate(actor, def.trigger).get("ok", false)), false, "gate refuses")
	assert_eq(_available_ids(actor).has(String(TIDE_EVENT)), false, "not available")
	assert_eq(bool(EventApi.begin(actor, TIDE_EVENT).get("ok", false)), false, "begin refuses")

	# Advance the world one period — this records the ambient fact AND opens the event
	pulse.advance_periods(1)

	# After: the whole chain has fired
	assert_eq(WorldFact.count(actor, AMBIENT_STORM), 1, "ambient fact in ledger")
	assert_eq(bool(EventGate.evaluate(actor, def.trigger).get("ok", false)), true, "gate passes")
	# The pulse opens the event on the same pull, so it is now ACTIVE (not just available)
	assert_eq(_stage_id(actor, TIDE_EVENT), "moving", "event is open on its first stage")
	assert_eq(bool(EventApi.begin(actor, TIDE_EVENT).get("ok", false)), false, "begin refuses: already active")
	assert_eq(
		String(EventApi.begin(actor, TIDE_EVENT).get("reason", "")),
		"already_active",
		"with already_active"
	)
