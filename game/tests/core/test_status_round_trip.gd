extends TestCase

## ADR 0103: an Actor round-trips its statuses. `Actor.to_dict` omitted them, so any actor
## restored from a payload came back with depleted pools and full health — a save that lies.
## A captive stored as a payload is exactly the actor this breaks.


func _status(id: StringName, remaining: float) -> StatusEffect:
	var status := StatusEffect.new(id, remaining)
	status.magnitude = 12.5
	status.kind = StatusEffect.Kind.CONTROL
	status.scope = StatusEffect.Scope.CULTIVATION
	status.mitigation_tags.append(&"purge")
	status.source = &"test"
	status.stacks = 2
	status.tick_elapsed = 1.5
	status.payload = {"note": "kept"}
	return status


func test_a_status_round_trips_through_an_actor() -> void:
	var actor := Actor.new(&"carrier", {})
	actor.add_status(_status(&"bound_mark", 30.0))
	var restored := Actor.from_dict(actor.to_dict())
	var status := restored._statuses.find(&"bound_mark")
	assert_eq(status != null, true, "the status survived the round trip")
	if status == null:
		return
	assert_almost_eq(status.magnitude, 12.5, "magnitude survived")
	assert_almost_eq(status.remaining, 30.0, "remaining survived")
	assert_eq(status.kind, StatusEffect.Kind.CONTROL, "the kind survived")
	assert_eq(status.scope, StatusEffect.Scope.CULTIVATION, "the scope survived")
	assert_eq(status.stacks, 2, "the stack count survived")
	assert_almost_eq(status.tick_elapsed, 1.5, "tick progress survived")
	assert_eq(status.has_mitigation(), true, "the purge lever survived")
	assert_eq(String(status.mitigation_tags[0]), "purge", "and named itself")
	assert_eq(status.source, &"test", "the source survived")
	assert_eq(String(status.payload.get("note", "")), "kept", "and module payload survived")


func test_an_actor_with_no_statuses_still_round_trips() -> void:
	var actor := Actor.new(&"plain", {})
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(restored.statuses.size(), 0, "an actor with no statuses carries none")


func test_a_save_written_before_this_key_still_loads() -> void:
	# The key is absent on every existing save, so absence must mean "no statuses" rather
	# than a failure. This is the compatibility case that matters on day one.
	var restored := Actor.from_dict({"id": "legacy", "base": {}})
	assert_eq(restored != null, true, "a legacy payload loads")
	assert_eq(restored.statuses.size(), 0, "and carries no statuses")


func test_a_malformed_status_is_dropped_not_fatal() -> void:
	# One bad entry must not fail the whole actor: a captive restored from a payload with a
	# corrupt status should come back without it, not not come back at all.
	var restored := (
		Actor
		. from_dict(
			{
				"id": "wounded",
				"base": {},
				"statuses": [{"no_id_here": true}, "not a dictionary", {"id": "real_one"}],
			}
		)
	)
	assert_eq(restored != null, true, "the actor still loads")
	assert_eq(restored.statuses.size(), 1, "only the well-formed status survived")
	assert_eq(restored._statuses.find(&"real_one") != null, true, "and it is the right one")


func test_two_statuses_of_one_id_restore_as_one() -> void:
	# Restoring through the registry's merge rule, not around it: two entries of one id
	# collapse to the single instance the merge would have produced live.
	var restored := (
		Actor
		. from_dict(
			{
				"id": "double",
				"base": {},
				"statuses":
				[
					{"id": "twin", "stacks": 2, "magnitude": 4.0},
					{"id": "twin", "stacks": 3, "magnitude": 6.0},
				],
			}
		)
	)
	assert_eq(restored.statuses.size(), 1, "two entries of one id collapse to one instance")
	var status := restored._statuses.find(&"twin")
	if status != null:
		assert_almost_eq(status.magnitude, 6.0, "and it kept the stronger magnitude")


func test_the_status_payload_is_json_safe() -> void:
	var actor := Actor.new(&"json", {})
	actor.add_status(_status(&"tagged", 5.0))
	var payload: Variant = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_eq(typeof(payload), TYPE_DICTIONARY, "the actor payload is JSON-safe")
	var rows: Array = (payload as Dictionary)["statuses"]
	assert_eq(rows.size(), 1, "the status survived JSON")
	var row: Dictionary = rows[0]
	assert_eq(typeof(row["id"]), TYPE_STRING, "the id is a String, not a StringName")
	assert_eq(typeof(row["source"]), TYPE_STRING, "and so is the source")
