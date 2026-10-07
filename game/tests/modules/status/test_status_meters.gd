extends TestCase

## ADR 0902 (P2/P7): the two ACCUMULATOR kinds over ONE accumulator with two sources.
## `counter` fills from hit counts (T4's landed-blow path and `record_counter_hit`);
## `meter` fills from VALUE events — the amounts its own pulses pay, fed by the tick
## loop — and both live in `StatusCounters`: the same store, the same residual rule.
##
## `UnityCc` is NOT a kind here: our `control` kind is the crowd-control endpoint
## (ADR 0902, P2), and `contagion` waits for spread (P9).

const PROBE_COUNTER := &"probe_kind_counter"
const PROBE_METER := &"probe_kind_meter"
const PROBE_BAD_COUNTER := &"probe_bad_counter"
const PROBE_BAD_METER := &"probe_bad_meter"

var _watcher: Callable = Callable()


func setup() -> void:
	for probe in [PROBE_COUNTER, PROBE_METER, PROBE_BAD_COUNTER, PROBE_BAD_METER]:
		_forget(probe)
	StatusEvents.shared().clear_log()


func teardown() -> void:
	if _watcher.is_valid() and StatusEvents.shared().status_meter_fired.is_connected(_watcher):
		StatusEvents.shared().status_meter_fired.disconnect(_watcher)
	_watcher = Callable()
	for probe in [PROBE_COUNTER, PROBE_METER, PROBE_BAD_COUNTER, PROBE_BAD_METER]:
		_forget(probe)
	StatusEvents.shared().clear_log()


## Both halves of a registration undone — the pattern `test_status_refusals.gd` uses,
## because `StatusCatalog` is a process-wide singleton.
func _forget(probe_id: StringName) -> void:
	StatusCatalog.instance()._rejected.erase(String(probe_id))
	StatusCatalog.instance()._definitions.erase(String(probe_id))
	var ids: Array[StringName] = StatusCatalog.instance()._ids.filter(
		func(candidate: StringName) -> bool: return candidate != probe_id
	)
	StatusCatalog.instance()._ids = ids


func _def(id: StringName, kind: StringName, unit: StringName, extra: Dictionary = {}) -> StatusDef:
	var def := StatusDef.new()
	def.id = id
	def.element = &"metal"
	def.kind = kind
	def.scope = &"combat"
	def.stacking = &"refresh"
	def.duration = 10.0
	def.magnitude_unit = unit
	def.magnitude_cap = 5.0
	def.tick_interval = 1.0
	def.mitigation_tags = [&"affinity", &"technique", &"pill"]
	def.payload = {
		"mechanic": &"bleed",
		"text": "test meter",
		"pool": &"health",
		"share_per_pulse": 0.05,
		"modifiers": [{"stat": &"damage_reduction", "op": &"flat", "value": -0.1}],
	}
	for key in extra.keys():
		def.payload[key] = extra[key]
	return def


## A root-built actor: the meter's pulses need the `health` pool the composition
## builds, exactly as `test_status_tick.gd` reads it.
func _actor() -> Actor:
	return ActorFactory.build(&"meter_probe", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})


func _rejected_reason(status_id: StringName) -> String:
	for entry in StatusCatalog.instance().rejected():
		if String(entry.get("id", "")) == String(status_id):
			return String(entry.get("reason", ""))
	return ""


func _watch_meter_fired(hits: Array) -> void:
	_watcher = (func(
		host_id: StringName, status_id: StringName, instance_id: int, amount: float
	) -> void:
		hits.append({"host": host_id, "id": status_id, "instance": instance_id, "amount": amount}))
	StatusEvents.shared().status_meter_fired.connect(_watcher)


func test_the_vocabulary_admits_both_accumulator_kinds() -> void:
	assert_eq(
		StatusCatalog.instance().register(
			_def(PROBE_COUNTER, &"counter", &"health_share", {"counter": {"every_hits": 2}})
		),
		true,
		"a counter kind with its config is admitted"
	)
	assert_eq(
		StatusCatalog.instance().register(
			_def(PROBE_METER, &"meter", &"health_share", {"meter": {"every": 1.0}})
		),
		true,
		"a meter kind with its config is admitted"
	)
	var actor := _actor()
	assert_eq(
		bool(StatusApi.apply(actor, PROBE_COUNTER, 1.0).get("ok", false)), true, "the counter lands"
	)
	assert_eq(
		actor.statuses[0].kind, StatusEffect.Kind.COUNTER, "and maps to the COUNTER effect kind"
	)
	assert_eq(
		bool(StatusApi.apply(actor, PROBE_METER, 1.0).get("ok", false)), true, "the meter lands"
	)
	assert_eq(actor.statuses[1].kind, StatusEffect.Kind.METER, "and maps to the METER effect kind")


func test_a_counter_kind_without_its_config_is_refused_by_name() -> void:
	assert_eq(
		StatusCatalog.instance().register(_def(PROBE_BAD_COUNTER, &"counter", &"health_share")),
		false,
		"a counter kind with nothing to count is refused"
	)
	assert_eq(
		_rejected_reason(PROBE_BAD_COUNTER).contains("payload.counter"),
		true,
		"and the reason names the missing config"
	)


func test_a_meter_kind_without_its_config_is_refused_by_name() -> void:
	assert_eq(
		StatusCatalog.instance().register(_def(PROBE_BAD_METER, &"meter", &"health_share")),
		false,
		"a meter kind with nothing to fill toward is refused"
	)
	assert_eq(
		_rejected_reason(PROBE_BAD_METER).contains("payload.meter"),
		true,
		"and the reason names the missing config"
	)


func test_both_sources_share_one_store_and_one_residual_rule() -> void:
	var actor := _actor()
	assert_eq(
		StatusApi.record_counter_hit(actor, &"g1", &"encounter", 3, true),
		false,
		"the counted source takes one of three"
	)
	assert_eq(StatusApi.record_meter_value(actor, 7, 2.0, true, 0.75), false, "0.75 of 2.0")
	assert_eq(StatusApi.record_meter_value(actor, 7, 2.0, true, 0.75), false, "1.50 of 2.0")
	assert_eq(StatusApi.record_meter_value(actor, 7, 2.0, true, 0.75), true, "2.25 crosses")
	var counters := StatusApi.counter_snapshot(actor)
	assert_eq(
		int((counters["grant"] as Dictionary).get("g1|encounter", -1)),
		1,
		"the counted source is in the same store"
	)
	assert_almost_eq(
		float((counters["instance"] as Dictionary).get(7, -1.0)),
		0.25,
		"and the value source kept its float residual (2.25 modulo 2.0)",
		1e-6
	)


func test_a_meter_status_fills_from_the_values_its_pulses_pay() -> void:
	assert_eq(
		StatusCatalog.instance().register(
			_def(
				PROBE_METER,
				&"meter",
				&"health_share",
				{"meter": {"every": 0.25, "reset_on_burst": true}}
			)
		),
		true,
		"the meter is admitted"
	)
	var actor := _actor()
	var hits: Array = []
	_watch_meter_fired(hits)
	var applied := StatusApi.apply(actor, PROBE_METER, 2.0)
	assert_eq(bool(applied.get("ok", false)), true, "the meter lands")
	var instance_id := int(applied.get("instance_id", 0))
	# One pulse pays `magnitude * share_per_pulse` = 2.0 * 0.05 = 0.1, and the tick
	# loop feeds that value into the SAME accumulator the counters use. The crossing
	# tick ALSO discharges one extra pulse (ADR 0902, P7), so the drops are measured.
	StatusApi.tick_statuses(actor, 1.0)
	var before := actor.resource(&"health").current
	StatusApi.tick_statuses(actor, 1.0)
	var plain_drop := before - actor.resource(&"health").current
	before = actor.resource(&"health").current
	StatusApi.tick_statuses(actor, 1.0)
	var crossing_drop := before - actor.resource(&"health").current
	assert_eq(hits.size(), 1, "0.30 crosses once")
	assert_eq(
		crossing_drop > plain_drop,
		true,
		"and the crossing discharged an extra pulse of its own channel"
	)
	var hit: Dictionary = hits[0]
	assert_eq(String(hit["id"]), "probe_kind_meter", "naming the meter that crossed")
	assert_eq(int(hit["instance"]), instance_id, "with the live handle")
	var counters := StatusApi.counter_snapshot(actor)
	assert_almost_eq(
		float((counters["instance"] as Dictionary).get(instance_id, -1.0)),
		0.05,
		"and the residual (0.30 modulo 0.25) is kept",
		1e-6
	)


func test_a_counter_status_advances_from_the_landed_blow_row() -> void:
	assert_eq(
		StatusCatalog.instance().register(
			_def(
				PROBE_COUNTER,
				&"counter",
				&"health_share",
				{"counter": {"every_hits": 2, "reset_on_burst": true}}
			)
		),
		true,
		"the counter is admitted"
	)
	var actor := _actor()
	var applied := StatusApi.apply(actor, PROBE_COUNTER, 1.0)
	var instance_id := int(applied.get("instance_id", 0))
	var entry := {"applied": true, "status_id": String(PROBE_COUNTER), "instance_id": instance_id}
	assert_eq(StatusApi.record_landed_blow(actor, entry), false, "the first landed blow counts one")
	assert_eq(StatusApi.record_landed_blow(actor, entry), true, "the second crosses")
	assert_eq(
		int((StatusApi.counter_snapshot(actor)["instance"] as Dictionary).get(instance_id, -1)),
		0,
		"and the cycle kept the residual"
	)


func test_the_two_new_kinds_survive_a_save_round_trip() -> void:
	var effect := StatusEffect.new(&"probe_saved")
	effect.kind = StatusEffect.Kind.METER
	var restored := StatusEffect.from_dict(effect.to_dict())
	assert_eq(restored.kind, StatusEffect.Kind.METER, "the meter kind round-trips as its own value")
	effect.kind = StatusEffect.Kind.COUNTER
	restored = StatusEffect.from_dict(effect.to_dict())
	assert_eq(restored.kind, StatusEffect.Kind.COUNTER, "and so does the counter kind")
