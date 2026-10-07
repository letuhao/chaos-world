extends TestCase

## ADR 0902 (T13, decision 8): the persistence MEASUREMENT. Statuses do not ride the
## actor save at all (ADR 0089 — `Actor.to_dict` emits no `statuses` key), so the state
## the port added is transient WITH them: the counter/meter store, grant handles and the
## ICD clock. Nothing here needs a schema change; this suite is the evidence decision 8
## names, beside `test_status_round_trip.gd`.

const GRANT := &"g-transient"


func setup() -> void:
	StatusApi.set_icd_default(0.0)


func teardown() -> void:
	StatusApi.set_icd_default(0.0)


func _actor() -> Actor:
	return ActorFactory.build(&"persist_probe", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})


func test_the_new_runtime_state_is_transient_across_a_save() -> void:
	var actor := _actor()
	var applied := StatusApi.apply(actor, &"fire_immolation", 1.0, -1.0, GRANT)
	assert_eq(bool(applied.get("ok", false)), true, "a granted status lands")
	var instance_id := int(applied.get("instance_id", 0))
	assert_eq(
		StatusApi.record_counter_hit(actor, GRANT, &"encounter", 3, true),
		false,
		"a counter advances"
	)
	assert_eq(
		StatusApi.record_meter_value(actor, instance_id, 2.0, true, 0.5), false, "a meter fills"
	)
	var payload := actor.to_dict()
	var text := JSON.stringify(payload)
	assert_eq(text.contains("g-transient"), false, "the grant handle does not ride the save")
	assert_eq(text.contains("counters"), false, "no counter table rides it")
	var restored := Actor.from_dict(payload)
	assert_eq(restored != null, true, "the actor round-trips")
	assert_eq(restored.statuses.size(), 0, "and carries no status (ADR 0089: session-only)")
	var counters := StatusApi.counter_snapshot(restored)
	assert_eq(
		(counters["grant"] as Dictionary).is_empty(), true, "the restored grant space is empty"
	)
	assert_eq((counters["instance"] as Dictionary).is_empty(), true, "and so is the instance space")


func test_the_icd_clock_is_not_a_saved_field() -> void:
	var actor := _actor()
	StatusApi.set_icd_default(5.0)
	assert_eq(
		bool(StatusApi.apply(actor, &"fire_immolation", 1.0).get("ok", false)), true, "it lands"
	)
	StatusApi.set_icd_default(0.0)
	var text := JSON.stringify(actor.to_dict())
	assert_eq(text.contains("icd"), false, "no ICD clock rides the save")
	# And the clock never leaks ACROSS actors: a fresh one is outside any window.
	var fresh := _actor()
	assert_eq(
		bool(StatusApi.apply(fresh, &"fire_immolation", 1.0).get("ok", false)),
		true,
		"a fresh actor is outside every window"
	)


func test_the_blessing_door_leaves_no_saved_trace_either() -> void:
	var actor := _actor()
	assert_eq(
		bool(StatusApi.apply_cultivation(actor, &"wood_bloom", 1.0, -1.0, GRANT).get("ok", false)),
		true,
		"a granted blessing lands"
	)
	var text := JSON.stringify(actor.to_dict())
	assert_eq(text.contains("g-transient"), false, "and its grant handle is just as transient")
