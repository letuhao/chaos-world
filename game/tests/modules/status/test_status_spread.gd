extends TestCase

## ADR 0902 (P9, BL-0925): contagion. The mandatory counterexamples: the hop cap stops
## an A -> B -> A loop, the ICD window refuses a re-hop until it elapses, the roll gates
## each candidate independently, and the source host is never re-infected.

const PROBE := &"probe_contagion"


func setup() -> void:
	_forget(PROBE)
	StatusApi.set_icd_default(0.0)
	StatusEvents.shared().clear_log()


func teardown() -> void:
	_forget(PROBE)
	StatusApi.set_icd_default(0.0)
	StatusEvents.shared().clear_log()


func _forget(probe_id: StringName) -> void:
	StatusCatalog.instance()._rejected.erase(String(probe_id))
	StatusCatalog.instance()._definitions.erase(String(probe_id))
	var ids: Array[StringName] = StatusCatalog.instance()._ids.filter(
		func(candidate: StringName) -> bool: return candidate != probe_id
	)
	StatusCatalog.instance()._ids = ids


func _def(chance: float, max_hops: int, icd: float, with_config: bool = true) -> StatusDef:
	var def := StatusDef.new()
	def.id = PROBE
	def.element = &"metal"
	def.kind = &"contagion"
	def.scope = &"combat"
	# COEXIST, so each hop is its OWN instance and the hop depth travels per instance —
	# a refresh-stacked def would merge a hop back into the original and the loop could
	# not be traced.
	def.stacking = &"coexist"
	def.duration = 60.0
	def.magnitude_unit = &"element_power"
	def.magnitude_cap = 5.0
	def.tick_interval = 1.0
	def.mitigation_tags = [&"affinity", &"technique", &"pill"]
	def.payload = {
		"mechanic": &"bleed",
		"text": "test contagion",
		"pool": &"health",
		"share_per_pulse": 0.05,
		"modifiers": [{"stat": &"damage_reduction", "op": &"flat", "value": -0.1}],
	}
	if with_config:
		def.payload["spread"] = {"chance": chance, "max_hops": max_hops, "icd": icd}
	return def


func _actor(id: StringName) -> Actor:
	return ActorFactory.build(id, {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})


func test_a_hop_applies_to_a_candidate_and_never_to_the_source() -> void:
	assert_eq(StatusCatalog.instance().register(_def(1.0, 2, 0.0)), true, "the probe is admitted")
	var source := _actor(&"spread_a")
	var other := _actor(&"spread_b")
	var applied := StatusApi.apply(source, PROBE, 1.0)
	var instance := int(applied.get("instance_id", 0))
	var rows := StatusApi.spread_status(
		source, instance, [source, other], 1.0, CombatTestKit.rng(7)
	)
	assert_eq(rows.size(), 1, "one candidate row")
	assert_eq(String(rows[0]["host"]), "spread_b", "the OTHER host")
	assert_eq(other.has_status(PROBE), true, "which now carries the def")
	assert_eq(source.statuses.size(), 1, "and the source host was never re-infected")
	assert_eq(StatusSpread.hop_of(other.statuses[0]), 1, "the child carries hop 1")


func test_the_hop_cap_stops_an_ab_ba_loop() -> void:
	assert_eq(StatusCatalog.instance().register(_def(1.0, 2, 0.0)), true, "the probe is admitted")
	var a := _actor(&"spread_a")
	var b := _actor(&"spread_b")
	var first := StatusApi.apply(a, PROBE, 1.0)
	assert_eq(
		(
			StatusApi
			. spread_status(a, int(first.get("instance_id", 0)), [b], 1.0, CombatTestKit.rng(7))
			. size()
		),
		1,
		"hop 1 lands on b"
	)
	assert_eq(StatusSpread.hop_of(b.statuses[0]), 1, "b's instance is hop 1")
	# b hops back to a: hop 1 < max_hops 2, so the round trip itself is legal…
	assert_eq(
		(
			StatusApi
			. spread_status(b, int(b.statuses[0].instance_id), [a], 1.0, CombatTestKit.rng(7))
			. size()
		),
		1,
		"hop 2 returns to a"
	)
	assert_eq(a.statuses.size(), 2, "a now carries the original and the hop-2 child")
	var child := a.statuses[1]
	assert_eq(StatusSpread.hop_of(child), 2, "the child is hop 2")
	# …and the NEXT hop is refused, which is the loop stopping at the authored ceiling.
	assert_eq(
		StatusApi.spread_status(a, int(child.instance_id), [b], 1.0, CombatTestKit.rng(7)).size(),
		0,
		"hop 3 exceeds max_hops 2 and never rolls"
	)
	# The hard cap holds even if a caller drives `hop` directly.
	assert_eq(
		(
			StatusSpread
			. hop(
				a, _def(1.0, 4, 0.0), [b], 1.0, CombatTestKit.rng(7), StatusSpread.MAX_HOP_DEPTH + 1
			)
			. size()
		),
		0,
		"the constant is the ceiling nothing exceeds"
	)


func test_the_icd_window_refuses_until_it_elapses() -> void:
	assert_eq(StatusCatalog.instance().register(_def(1.0, 2, 5.0)), true, "the probe is admitted")
	var source := _actor(&"spread_a")
	var other := _actor(&"spread_b")
	var applied := StatusApi.apply(source, PROBE, 1.0)
	var instance := int(applied.get("instance_id", 0))
	# The window opens at ARRIVAL (Keepverse's `LastSpread` is written by the apply), so
	# the first hop waits out the ICD too.
	assert_eq(
		StatusApi.spread_status(source, instance, [other], 1.0, CombatTestKit.rng(7)).size(),
		0,
		"nothing hops inside the arrival window"
	)
	StatusApi.tick_statuses(source, 5.0)
	assert_eq(
		StatusApi.spread_status(source, instance, [other], 1.0, CombatTestKit.rng(7)).size(),
		1,
		"the first hop fires once the window elapses"
	)
	assert_eq(
		StatusApi.spread_status(source, instance, [other], 1.0, CombatTestKit.rng(7)).size(),
		0,
		"a second hop inside the fresh window is refused"
	)
	StatusApi.tick_statuses(source, 5.0)
	assert_eq(
		StatusApi.spread_status(source, instance, [other], 1.0, CombatTestKit.rng(7)).size(),
		1,
		"and past it the hop fires again"
	)


func test_the_roll_gates_each_candidate_independently() -> void:
	assert_eq(StatusCatalog.instance().register(_def(0.5, 2, 0.0)), true, "the probe is admitted")
	var source := _actor(&"spread_a")
	var applied := StatusApi.apply(source, PROBE, 1.0)
	var instance := int(applied.get("instance_id", 0))
	var targets: Array = [_actor(&"spread_b"), _actor(&"spread_c"), _actor(&"spread_d")]
	assert_eq(
		StatusApi.spread_status(source, instance, targets, 0.0, CombatTestKit.rng(7)).size(),
		0,
		"a closed chance rolls nothing"
	)
	assert_eq(
		StatusApi.spread_status(source, instance, targets, 1.0, CombatTestKit.rng(7)).size(),
		targets.size(),
		"and a certain one reaches every candidate"
	)


func test_a_contagion_kind_without_its_config_is_refused() -> void:
	assert_eq(
		StatusCatalog.instance().register(_def(1.0, 2, 0.0, false)),
		false,
		"a contagion kind with no payload.spread is refused"
	)
	var reason := ""
	for entry in StatusCatalog.instance().rejected():
		if String(entry.get("id", "")) == String(PROBE):
			reason = String(entry.get("reason", ""))
	assert_eq(reason.contains("payload.spread"), true, "and the reason names the missing config")
