extends TestCase

## ADR 0902 (P6=C): ONE actor-scoped counter store with two key spaces. The semantics
## are Keepverse's measured `RecordCounterHit`: `n += hits`, a crossing answers true,
## `reset_on_burst` keeps the residual (`n % every_hits`), the latch form keeps the
## total and fires on every later hit, and coalesced hits (`hits = N`) advance by N
## with ONE burst per call.
##
## The two spaces are exercised through the FACADE verbs: `record_counter_hit`
## (grant | scope) and `record_instance_hit` (the handle `StatusRegistry` minted, so
## coexist siblings count independently).

const PROBE := &"probe_counter"
const SCOPE := &"encounter"


func setup() -> void:
	_forget(PROBE)
	StatusApi.set_icd_default(0.0)
	StatusEvents.shared().clear_log()


func teardown() -> void:
	_forget(PROBE)
	StatusApi.set_icd_default(0.0)
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


func _def(counter: Dictionary = {}) -> StatusDef:
	var def := StatusDef.new()
	def.id = PROBE
	def.element = &"metal"
	def.kind = &"dot"
	def.scope = &"combat"
	def.stacking = &"refresh"
	def.duration = 1.0
	def.magnitude_unit = &"element_power"
	def.magnitude_cap = 5.0
	def.tick_interval = 1.0
	def.mitigation_tags = [&"affinity", &"technique", &"pill"]
	def.payload = {
		"mechanic": &"bleed",
		"text": "test counter",
		"pool": &"health",
		"share_per_pulse": 0.05,
		"modifiers": [{"stat": &"damage_reduction", "op": &"flat", "value": -0.1}],
		"counter": counter,
	}
	return def


func _register(counter: Dictionary = {}) -> void:
	assert_eq(StatusCatalog.instance().register(_def(counter)), true, "the probe def is admitted")


func _actor() -> Actor:
	var actor := Actor.new(&"counter_probe", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	actor.attach_core_resources()
	return actor


# --- the arithmetic, in the grant space -----------------------------------------


func test_a_grant_counter_answers_only_when_it_crosses() -> void:
	var actor := _actor()
	assert_eq(
		StatusApi.record_counter_hit(actor, &"g1", SCOPE, 3, true),
		false,
		"one of three is not a crossing"
	)
	assert_eq(
		StatusApi.record_counter_hit(actor, &"g1", SCOPE, 3, true),
		false,
		"two of three is not either"
	)
	assert_eq(StatusApi.record_counter_hit(actor, &"g1", SCOPE, 3, true), true, "three crosses")
	var counters := StatusApi.counter_snapshot(actor)
	assert_eq(
		int((counters["grant"] as Dictionary).get("g1|encounter", -1)),
		0,
		"and the cycle restarts from zero"
	)


func test_the_residual_survives_a_coalesced_burst() -> void:
	var actor := _actor()
	assert_eq(
		StatusApi.record_counter_hit(actor, &"g1", SCOPE, 3, true, 5),
		true,
		"five coalesced hits cross a three-step meter once"
	)
	var counters := StatusApi.counter_snapshot(actor)
	assert_eq(
		int((counters["grant"] as Dictionary).get("g1|encounter", -1)),
		2,
		"and the residual (5 % 3) is kept rather than eaten"
	)


func test_the_latch_form_keeps_the_total_and_fires_on_every_later_hit() -> void:
	var actor := _actor()
	assert_eq(StatusApi.record_counter_hit(actor, &"g1", SCOPE, 2, false), false, "one of two")
	assert_eq(StatusApi.record_counter_hit(actor, &"g1", SCOPE, 2, false), true, "two crosses")
	assert_eq(
		StatusApi.record_counter_hit(actor, &"g1", SCOPE, 2, false),
		true,
		"and a latch that has crossed answers again on the next hit"
	)
	var counters := StatusApi.counter_snapshot(actor)
	assert_eq(
		int((counters["grant"] as Dictionary).get("g1|encounter", -1)),
		3,
		"with the running total kept"
	)


func test_an_empty_grant_is_refused_rather_than_counted_against_nothing() -> void:
	var actor := _actor()
	assert_eq(
		StatusApi.record_counter_hit(actor, &"", SCOPE, 3, true), false, "no grant, no counter"
	)
	var counters := StatusApi.counter_snapshot(actor)
	assert_eq((counters["grant"] as Dictionary).is_empty(), true, "and nothing was written")


func test_clear_grant_sweeps_the_prefix_and_leaves_a_sibling_grant() -> void:
	var actor := _actor()
	StatusApi.record_counter_hit(actor, &"g1", SCOPE, 3, true)
	StatusApi.record_counter_hit(actor, &"g2", SCOPE, 3, true)
	var cleared := StatusApi.clear_grant(actor, &"g1")
	assert_eq(bool(cleared.get("ok", false)), true, "the grant clears")
	var counters := StatusApi.counter_snapshot(actor)
	var grant_space := counters["grant"] as Dictionary
	assert_eq(grant_space.has("g1|encounter"), false, "its counter went with it")
	assert_eq(
		int(grant_space.get("g2|encounter", -1)), 1, "and the sibling grant's counter is untouched"
	)


# --- the instance space ----------------------------------------------------------


func test_an_instance_counter_dies_with_its_instance() -> void:
	_register()
	var actor := _actor()
	var applied := StatusApi.apply(actor, PROBE, 1.0)
	var instance_id := int(applied.get("instance_id", 0))
	assert_eq(instance_id > 0, true, "the status landed with a handle")
	assert_eq(StatusApi.record_instance_hit(actor, instance_id, 2, true), false, "one of two")
	var counters := StatusApi.counter_snapshot(actor)
	assert_eq(
		int((counters["instance"] as Dictionary).get(instance_id, -1)),
		1,
		"the instance space counts by handle"
	)
	# The probe's duration is one second; one tick past it expires the instance and
	# the module's own prune must drop the count with it.
	StatusApi.tick_statuses(actor, 2.0)
	counters = StatusApi.counter_snapshot(actor)
	assert_eq(
		(counters["instance"] as Dictionary).is_empty(),
		true,
		"a left instance leaves no count for a successor to inherit"
	)


# --- the landed-blow verb --------------------------------------------------------


func test_a_def_without_an_authored_counter_makes_the_landed_blow_a_no_op() -> void:
	_register()
	var actor := _actor()
	var applied := StatusApi.apply(actor, PROBE, 1.0)
	var entry := {
		"applied": true,
		"status_id": String(PROBE),
		"instance_id": int(applied.get("instance_id", 0)),
	}
	assert_eq(
		StatusApi.record_landed_blow(actor, entry), false, "no payload.counter, nothing to count"
	)
	assert_eq(
		(StatusApi.counter_snapshot(actor)["instance"] as Dictionary).is_empty(),
		true,
		"and no record was written"
	)


func test_the_landed_blow_advances_the_authored_instance_counter() -> void:
	_register({"every_hits": 2, "reset_on_burst": true})
	var actor := _actor()
	var applied := StatusApi.apply(actor, PROBE, 1.0)
	var instance_id := int(applied.get("instance_id", 0))
	var entry := {
		"applied": true,
		"status_id": String(PROBE),
		"instance_id": instance_id,
	}
	assert_eq(StatusApi.record_landed_blow(actor, entry), false, "the first blow counts one")
	assert_eq(StatusApi.record_landed_blow(actor, entry), true, "the second crosses")
	assert_eq(
		int((StatusApi.counter_snapshot(actor)["instance"] as Dictionary).get(instance_id, -1)),
		0,
		"and the cycle kept the residual"
	)


func test_the_summary_publishes_both_counter_spaces() -> void:
	_register()
	var actor := _actor()
	assert_eq(StatusApi.record_counter_hit(actor, &"g1", SCOPE, 3, true), false, "a grant hit")
	var applied := StatusApi.apply(actor, PROBE, 1.0)
	assert_eq(
		StatusApi.record_instance_hit(actor, int(applied.get("instance_id", 0)), 2, true),
		false,
		"and an instance hit"
	)
	var report := StatusApi.summary(actor)
	assert_eq(report.has("counters"), true, "the counters ride the report")
	var counters := report["counters"] as Dictionary
	assert_eq(
		int((counters["grant"] as Dictionary).get("g1|encounter", -1)),
		1,
		"the grant space is published"
	)
	assert_eq((counters["instance"] as Dictionary).size(), 1, "and so is the instance space")


## The crossing PAYS (ADR 0902, P6): the accumulated hits discharge as one pulse of the
## def's own channel, on the same store the counters live in.
func test_the_crossing_discharges_one_pulse_of_its_own_channel() -> void:
	_register({"every_hits": 2, "reset_on_burst": true})
	var actor := ActorFactory.build(&"counter_discharge", {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	var applied := StatusApi.apply(actor, PROBE, 2.0)
	var instance_id := int(applied.get("instance_id", 0))
	var before := actor.resource(&"health").current
	var entry := {"applied": true, "status_id": String(PROBE), "instance_id": instance_id}
	assert_eq(StatusApi.record_landed_blow(actor, entry), false, "the first blow counts")
	assert_almost_eq(actor.resource(&"health").current, before, "and pays nothing", 1e-9)
	assert_eq(StatusApi.record_landed_blow(actor, entry), true, "the second crosses")
	assert_eq(
		actor.resource(&"health").current < before,
		true,
		"and the crossing discharges one pulse of the def's own channel"
	)
