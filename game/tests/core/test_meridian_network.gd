extends TestCase

## ADR 0017: MeridianNetwork manages meridian unlock, state, and bonuses.


## A provider that reads the network the way ADR 0057 prescribes, so this suite can
## watch the whole chain rather than a version counter: a mutation with no verb after
## it, and a published stat that moved anyway.
##
## The absent case gets its OWN stat id rather than a number beside the bonus. An
## untrained network really does answer `0.0`, so folding "no network" into the same
## number is what made the payout silently vanish before ADR 0057.
class NetworkPowerReader:
	extends StatProvider

	var calls: int = 0

	func contribute(context: StatContext) -> Dictionary:
		calls += 1
		var network := context.meridian_network()
		if network == null:
			return {&"meridian_power_absent": 1.0}
		return {&"meridian_power": network.get_power_bonus()}


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
	# The gate is reported CLAUSE BY CLAUSE, not as one omnibus "Immortal tier
	# gates" line: a player told only that a gate exists cannot act on it, because
	# the tribulation is fought somewhere else entirely, the inside world is grown by
	# training, and the ascent is walked. So the thing asserted here is that exactly
	# ONE clause is unmet and that it is the tribulation — the one an actor at this
	# tier cannot satisfy from inside the body path.
	var only_the_gate := unmet.size() == 1 and unmet[0].contains("tribulation")
	assert_eq(only_the_gate, true, "the tier gate is the only thing unmet: %s" % ", ".join(unmet))
	assert_eq(
		BodyAdvancement.try_breakthrough(actor, RandomNumberGenerator.new()),
		false,
		"the body path refuses to cross the Immortal gate"
	)
	assert_eq(state.rank_id, &"spirit_ascension", "rank unchanged")


## `Actor._init` must connect `meridians.changed` to the stats invalidator, exactly
## as it already does for traits and affinities. The connect used to live only in
## `from_dict`, so on a normally constructed actor `_emit_changed` invalidated
## nothing and any meridian mutation without a following `mark_stats_dirty` served
## a stale power bonus (ADR 0057).
func test_meridian_mutation_invalidates_stats_on_a_fresh_actor() -> void:
	var actor := Actor.new(&"fresh", {Stat.PHYSIQUE: 10.0})
	# Warm the provider cache so a later read has to recompute to be correct.
	actor.mark_stats_dirty()
	actor.stats.derived(Stat.MAX_HEALTH)
	var before := actor.stats._version
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	assert_eq(
		actor.stats._version > before, true, "touching the network marked the actor's stats dirty"
	)


## The end-to-end shape of ADR 0057, and the strongest thing this suite can say: the
## wiring is not merely present, it works. A provider handed the context, reading the
## network the prescribed way, is asked AGAIN and publishes the trained network after
## a mutation that no body verb follows. Every earlier test here observes one link;
## this one observes the chain.
func test_a_provider_reading_the_network_sees_a_mutation_with_no_verb_after_it() -> void:
	var actor := Actor.new(&"wired_provider", {Stat.PHYSIQUE: 10.0})
	var reader := NetworkPowerReader.new()
	actor.stats.add_provider(reader)
	assert_almost_eq(
		actor.stats.derived(&"meridian_power"), 0.0, "an untrained network pays nothing"
	)
	var calls_before := reader.calls
	# No body verb, no mark_stats_dirty, no provider churn: only the network moves.
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	# Read BEFORE counting: a provider runs lazily inside `derived`, so the call
	# count is evidence only once the read that would trigger it has happened.
	var published := actor.stats.derived(&"meridian_power")
	assert_eq(reader.calls > calls_before, true, "the provider was asked again")
	assert_almost_eq(
		published, actor.meridians.get_power_bonus(), "and it published the trained network"
	)
	assert_almost_eq(
		actor.stats.derived(&"meridian_power_absent"),
		0.0,
		"an actor's context is never the absent case"
	)


## The `_init` half of the wiring, read from the other end: the context a provider
## is handed must already carry the network, not wait for a save to supply one.
## ADR 0057 §Consequences — `component(&"meridians")` answers null for every actor
## `Actor` builds, so this accessor is the only read that resolves.
func test_a_fresh_actor_context_already_carries_its_network() -> void:
	var actor := Actor.new(&"wired", {Stat.PHYSIQUE: 10.0})
	assert_eq(
		actor.stats._context.meridian_network(),
		actor.meridians,
		"the context built by _init holds the network _init made"
	)
	assert_eq(actor.component(&"meridians"), null, "and the network is not a module component")


## Replacing the field is the hazard the from_dict re-point exists for, and the
## `meridians` setter covers every assignment rather than only the one in
## `from_dict`. A context left on the discarded object is the same class of bug as
## never connecting the signal: a stat served off a network the actor moved off.
func test_swapping_the_field_re_points_the_context() -> void:
	var actor := Actor.new(&"swapped", {Stat.PHYSIQUE: 10.0})
	var original := actor.meridians
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")

	actor.meridians = MeridianNetwork.from_dict(original.to_dict())
	assert_eq(
		actor.stats._context.meridian_network(), actor.meridians, "the context followed the field"
	)
	assert_ne(
		actor.stats._context.meridian_network(), original, "and let go of the discarded object"
	)
	# And the connect followed too, so the new object invalidates on its own.
	var before := actor.stats._version
	actor.meridians.open_meridian(&"spleen")
	assert_eq(actor.stats._version > before, true, "the replacement is wired to the invalidator")


## **null is not a network worth zero.** The two states are distinguishable, which is
## the whole point: an absent network says the owner has none, while a network nobody
## trained is a real object answering 0.0. A provider that cannot tell them apart
## turns the first into the second, which is the quiet zero ADR 0057 exists to end.
func test_an_absent_network_reads_as_null_not_as_a_zero_bonus() -> void:
	var bare := StatContext.new({}, {}, NameList.new(), AffinityMap.new(), {}, {})
	assert_eq(bare.meridian_network(), null, "a context built for no network says so")
	assert_eq(
		Actor.new(&"trained").stats._context.meridian_network() != null,
		true,
		"an actor's context is never the absent case"
	)
	assert_almost_eq(
		Actor.new(&"untrained").meridians.get_power_bonus(), 0.0, "an untrained network IS zero"
	)


## The restored network REPLACES the one `_init` built, so the stat context must be
## re-pointed at it. Reading the discarded object would be the same class of bug as
## never connecting the signal at all.
func test_stat_context_reads_the_restored_network_not_the_discarded_one() -> void:
	var actor := Actor.new(&"restored", {Stat.PHYSIQUE: 10.0})
	var original := actor.meridians
	actor.meridians.unlock_for_realm(&"qi_refining")
	# State steps are ordered: closed -> open -> expanded -> strengthened.
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	var expected := actor.meridians.get_power_bonus()
	assert_eq(expected > 0.0, true, "the original network has power")

	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(restored.meridians != original, true, "the restored network is a new object")
	assert_eq(
		restored.stats._context.meridian_network(),
		restored.meridians,
		"the context is re-pointed at the restored network"
	)
	assert_ne(
		restored.stats._context.meridian_network(),
		original,
		"and no longer holds the discarded object"
	)
	assert_almost_eq(
		restored.meridians.get_power_bonus(), expected, "power survived the round trip"
	)


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
