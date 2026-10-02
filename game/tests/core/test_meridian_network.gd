extends TestCase

## ADR 0017: MeridianNetwork manages meridian unlock, state, and bonuses.


func test_unlock_for_realm() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	assert_eq(network.get_meridian(&"lung") != null, true, "lung unlocked")
	assert_eq(network.get_meridian(&"liver") != null, false, "liver not yet")
	assert_eq(network.get_meridian(&"du_mai") != null, false, "du_mai not yet")


func test_unlock_progression() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"nascent_soul")
	assert_eq(network.get_meridian(&"lung") != null, true, "lung unlocked")
	assert_eq(network.get_meridian(&"heart") != null, true, "heart unlocked")
	assert_eq(network.get_meridian(&"pericardium") != null, false, "pericardium not yet")


func test_state_transitions() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	assert_eq(network.get_meridian(&"lung").state, &"open", "opened")
	network.expand_meridian(&"lung")
	assert_eq(network.get_meridian(&"lung").state, &"expanded", "expanded")
	network.strengthen_meridian(&"lung")
	assert_eq(network.get_meridian(&"lung").state, &"strengthened", "strengthened")


func test_damage_and_repair() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	network.damage_meridian(&"lung")
	assert_eq(network.get_meridian(&"lung").is_injured(), true, "injured")
	network.repair_meridian(&"lung")
	assert_eq(network.get_meridian(&"lung").state, &"open", "repaired to open")


func test_flow_bonus() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	assert_almost_eq(network.get_flow_bonus(), 0.0, "no flow bonus when closed")
	network.open_meridian(&"lung")
	assert_almost_eq(network.get_flow_bonus(), 0.10, "flow bonus from open")


func test_capacity_bonus() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	assert_almost_eq(network.get_capacity_bonus(), 0.0, "no capacity bonus when open")
	network.expand_meridian(&"lung")
	assert_almost_eq(network.get_capacity_bonus(), 0.05, "capacity bonus from expanded")


func test_power_bonus() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	network.expand_meridian(&"lung")
	assert_almost_eq(network.get_power_bonus(), 0.0, "no power bonus when expanded")
	network.strengthen_meridian(&"lung")
	assert_almost_eq(network.get_power_bonus(), 0.05, "power bonus from strengthened")


func test_injury_reduces_bonus() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	var full_bonus := network.get_flow_bonus()
	network.damage_meridian(&"lung")
	assert_almost_eq(network.get_flow_bonus(), full_bonus * 0.5, "injured reduces flow")


func test_serialization_round_trip() -> void:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	network.expand_meridian(&"lung")
	var restored := MeridianNetwork.from_dict(network.to_dict())
	assert_eq(restored.get_meridian(&"lung").state, &"expanded", "state round trip")
	assert_almost_eq(restored.get_flow_bonus(), network.get_flow_bonus(), "flow round trip")
	assert_almost_eq(
		restored.get_capacity_bonus(), network.get_capacity_bonus(), "capacity round trip"
	)


# --- Resonance (ADR 0017, ADR 0034) -----------------------------------------


## A network with one open, expanded, strengthened lung at refinement 0.
func _trained_network() -> MeridianNetwork:
	var network := MeridianNetwork.new()
	network.unlock_for_realm(&"qi_refining")
	network.open_meridian(&"lung")
	network.expand_meridian(&"lung")
	network.strengthen_meridian(&"lung")
	return network


func test_resonance_starts_inert() -> void:
	var network := MeridianNetwork.new()
	assert_eq(network.resonance_rank, 0, "no rank by default")
	assert_almost_eq(network.resonance_multiplier(), 1.0, "inert multiplier")


func test_resonance_lifts_every_bonus() -> void:
	var base := _trained_network()
	var flow := base.get_flow_bonus()
	var capacity := base.get_capacity_bonus()
	var power := base.get_power_bonus()
	var resonated := _trained_network()
	resonated.set_resonance_rank(12)
	# rank 12 * 0.05 = +60%
	assert_almost_eq(resonated.resonance_multiplier(), 1.6, "rank 12 multiplier")
	assert_almost_eq(resonated.get_flow_bonus(), flow * 1.6, "flow lifted")
	assert_almost_eq(resonated.get_capacity_bonus(), capacity * 1.6, "capacity lifted")
	assert_almost_eq(resonated.get_power_bonus(), power * 1.6, "power lifted")


func test_resonance_increases_monotonically() -> void:
	var network := _trained_network()
	var previous := network.get_power_bonus()
	for rank in range(1, 13):
		network.set_resonance_rank(rank)
		var current := network.get_power_bonus()
		assert_eq(current > previous, true, "rank %d lifts power" % rank)
		previous = current


func test_resonance_clamps_negative_ranks() -> void:
	var network := MeridianNetwork.new()
	network.set_resonance_rank(-4)
	assert_eq(network.resonance_rank, 0, "negative rank clamps to zero")


func test_resonance_round_trips_in_saves() -> void:
	var network := _trained_network()
	network.set_resonance_rank(7)
	var restored := MeridianNetwork.from_dict(network.to_dict())
	assert_eq(restored.resonance_rank, 7, "rank restored")
	assert_almost_eq(
		restored.get_power_bonus(), network.get_power_bonus(), "power survives the round trip"
	)


## The ADR 0018-0021 tier gates are advisory by construction: `try_advance` is
## public and will happily walk the body path past every one of them. This test
## exists so the gap is documented rather than accidental — it asserts what
## currently happens, and fails loudly if core ever starts enforcing the gate
## (at which point this test should be replaced with the stronger assertion).
func test_unguarded_try_advance_bypasses_the_immortal_tier_gate() -> void:
	var actor := Actor.new(&"gate_bypasser")
	actor.set_path(PathState.new(&"body_cultivation", &"spirit_ascension"))
	# Index 18 is the first Immortal realm, so this crosses the tribulation and
	# inside-world gates. The actor has neither.
	var target := RealmDefaults.ladder().next(&"spirit_ascension")
	assert_ne(target, null, "a target exists")
	assert_eq(actor.tribulation, null, "no tribulation survived")
	assert_eq(Breakthrough.tribulation_ok(actor, target.index), false, "gate is closed")
	assert_eq(
		Breakthrough.try_advance(actor, &"body_cultivation"),
		true,
		"unguarded try_advance still crosses it: the gate is advisory, not enforced"
	)


## The body module must never take that path. Its condition calls
## `tier_gates_met` directly, so the gate is enforced there.
func test_body_condition_refuses_the_bypass() -> void:
	var actor := Actor.new(&"gate_refuser", {Stat.PHYSIQUE: 999.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"spirit_ascension"))
	actor.meridians.unlock_for_realm(&"earth_immortal")
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	# Satisfy everything the body path owns, so only the tier gate can refuse.
	var target := RealmDefaults.ladder().next(&"spirit_ascension")
	var seed := BodyRealmSeed.for_realm(target.id)
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		actor.meridians.open_meridian(meridian_id)
		actor.meridians.expand_meridian(meridian_id)
		actor.meridians.strengthen_meridian(meridian_id)
		var guard := 0
		while actor.meridians.refine_meridian(meridian_id, seed.required_refinement) and guard < 32:
			guard += 1
	var points: AcupointSet = actor.component(&"acupoints")
	for point in points.points:
		point.clear_block()
		point.quality = maxf(point.quality, seed.quality_required)
	points.fill(seed.integrity_maximum)
	var state := actor.path(BodyPath.PATH_ID)
	state.progress = seed.progress_required
	var meditate_guard := 0
	while (
		meditate_guard < 4096 and actor.stats.get_base(Stat.COMPREHENSION) < seed.insight_required
	):
		meditate_guard += 1
		BodyTraining.meditate(actor, 1.0)
	var def := ItemDef.new()
	def.id = seed.breakthrough_item
	def.stackable = true
	def.max_stack = 9
	ItemsApi.inventory(actor).add(def, 1)
	# Everything the body owns is met; the Immortal gate still must refuse.
	var condition := BodyBreakthroughCondition.new()
	var unmet: Array[String] = condition.describe_unmet(actor, state)
	var only_the_gate := unmet.size() == 1 and unmet[0].contains("Immortal tier gates")
	assert_eq(only_the_gate, true, "the tier gate is the only thing unmet: %s" % ", ".join(unmet))
	assert_eq(
		BodyAdvancement.try_breakthrough(actor, RandomNumberGenerator.new()),
		false,
		"the body path refuses to cross the Immortal gate"
	)
	assert_eq(state.rank_id, &"spirit_ascension", "rank unchanged")


## The pre-ADR-0034 payload was a bare per-meridian map. Old saves must still
## load rather than being read as a meridian named "resonance_rank".
func test_legacy_bare_meridian_payload_still_loads() -> void:
	var legacy := {
		"lung":
		{
			"id": "lung",
			"state": "strengthened",
			"tier": 0,
			"refinement": 2,
			"injured": false,
		}
	}
	var restored := MeridianNetwork.from_dict(legacy)
	assert_eq(restored.get_meridian(&"lung") != null, true, "legacy meridian loaded")
	assert_eq(restored.get_meridian(&"lung").refinement, 2, "legacy refinement loaded")
	assert_eq(restored.resonance_rank, 0, "legacy payload has no resonance")
