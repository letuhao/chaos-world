extends TestCase

## ADR 0902 (P14): the refusal ORDER, layered because the layers own different facts
## (ADR 0902 §6, decision recorded in T1):
##
##     combat gate:   immunity -> potency floor -> apply roll -> useless magnitude
##     status module: `status_icd` BEFORE the effect lands (its own suite, `test_status_icd`)
##
## and the reason VOCABULARY never renames: `useless_magnitude` joins the closed set
## beside the shipped names rather than replacing one. Each order claim is a case that
## would refuse for TWO reasons at once, so the winner names the order.

const PROBE := &"probe_refusal_order"
const TAG := &"order_tag"

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


func _attr(actor: Actor, id_prefix: String, suffix: String, value: float) -> void:
	actor.stats.add_modifier(
		CombatStats.rate_modifier(StringName(id_prefix + suffix), value, &"test")
	)


func _request(extra: Dictionary = {}) -> Dictionary:
	var request := {
		"id": PROBE,
		"chance": 1.0,
		"element": &"fire",
		"kind": &"dot",
		"duration": 10.0,
		"potency": 1.0,
		"scope": String(StatusApply.SCOPE_COMBAT),
	}
	for key in extra.keys():
		request[key] = extra[key]
	return request


## One landed blow through the real S12 path, with optional attacker/target setup.
func _resolve(
	request: Dictionary,
	setup_attacker: Callable = Callable(),
	setup_target: Callable = Callable(),
	tuning: CombatTuning = null
) -> Dictionary:
	var resolved_tuning := tuning if tuning != null else _tuning
	var attacker := CombatTestKit.quiet_actor(&"order_attacker")
	attacker.stats.add_modifier(CombatStats.rate_modifier(CombatStats.ACCURACY, 1.0, &"test"))
	if setup_attacker.is_valid():
		setup_attacker.call(attacker)
	var target := CombatTestKit.actor(&"order_target")
	if setup_target.is_valid():
		setup_target.call(target)
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 25.0
	MechanismSlot.bind(attacker, mechanism)
	var rng := CombatTestKit.rng(11)
	var technique := CombatTestKit.technique(100.0)
	var outcome := CombatSpine.resolve_hit(attacker, target, technique, resolved_tuning, rng)
	var ctx := AttackContext.new(attacker, target, technique, resolved_tuning)
	ctx.set_data(StatusApply.REQUEST_KEY, request)
	return StatusApply.apply(attacker, target, resolved_tuning, ctx, outcome, rng, technique, 0)


func test_immunity_is_refused_before_the_potency_floor() -> void:
	# Both layers would refuse: an immune tag AND an intensity floor nothing survives.
	var result := _resolve(
		_request({"immunity_tags": [TAG]}),
		Callable(),
		func(target: Actor) -> void:
			_attr(target, _tuning.status_immune_prefix, "order_tag", 1.0)
			_attr(target, _tuning.status_intensity_reduction_prefix, "omni", 1000.0)
	)
	assert_eq(
		String(result.get(StatusApply.REFUSED, "")), "immune", "immunity wins the layered order"
	)


func test_the_potency_floor_is_refused_before_the_roll() -> void:
	# A saturated power would open any roll; the floored intensity refuses first.
	var result := _resolve(
		_request(),
		func(attacker: Actor) -> void: _attr(attacker, _tuning.status_power_prefix, "omni", 1000.0),
		func(target: Actor) -> void:
			_attr(target, _tuning.status_intensity_reduction_prefix, "omni", 1000.0)
	)
	assert_eq(
		String(result.get(StatusApply.REFUSED, "")), "no_potency", "the floor precedes the roll"
	)


func test_the_roll_refuses_when_the_defender_wins_it() -> void:
	# No immunity, no floor — only the seeded roll stands between the blow and the status.
	var result := _resolve(
		_request(),
		Callable(),
		func(target: Actor) -> void: _attr(target, _tuning.status_resist_prefix, "omni", 1000.0)
	)
	assert_eq(
		String(result.get(StatusApply.REFUSED, "")), "resisted", "the roll is the third layer"
	)


## Keepverse's `IsUseless`: zero factored magnitude AND non-positive effective duration.
## Reachability needs BOTH tuning dials at zero — the shipped potency floor (0.1) keeps
## every magnitude positive past the intensity floor and the shipped duration default
## (6.0) keeps every life positive — so the shipped content can never fire this refusal,
## and this test proves the ported predicate with a non-shipped tuning.
func test_a_zero_magnitude_zero_duration_status_is_useless_after_the_roll() -> void:
	var tuning := CombatTestKit.shipped()
	tuning.status_default_duration = 0.0
	tuning.status_potency_floor = 0.0
	var result := _resolve(
		_request({"potency": 0.0, "duration": 0.0}),
		func(attacker: Actor) -> void: _attr(attacker, tuning.status_power_prefix, "omni", 1000.0),
		Callable(),
		tuning
	)
	assert_eq(
		String(result.get(StatusApply.REFUSED, "")),
		"useless_magnitude",
		"zero magnitude and zero duration do nothing, even with the roll won"
	)


func test_a_zero_magnitude_timed_status_still_lands() -> void:
	# The control that makes the row above a REFINEMENT rather than a blanket: a timed
	# zero-magnitude status can still gate or modify stats, so it is not useless.
	var result := _resolve(
		_request({"potency": 0.0, "duration": 0.0}),
		func(attacker: Actor) -> void: _attr(attacker, _tuning.status_power_prefix, "omni", 1000.0)
	)
	assert_eq(
		bool(result.get(StatusApply.APPLIED, false)),
		true,
		"a TIMED zero-magnitude status is not useless"
	)


func test_the_reason_vocabulary_keeps_its_existing_names() -> void:
	assert_eq(StatusApply.REFUSE_IMMUNE, &"immune", "existing reasons never rename")
	assert_eq(StatusApply.REFUSE_NO_POTENCY, &"no_potency", "the floor keeps its name")
	assert_eq(StatusApply.REFUSE_RESISTED, &"resisted", "the roll keeps its name")
	assert_eq(
		StatusApply.REFUSE_USELESS_MAGNITUDE,
		&"useless_magnitude",
		"and the new reason names itself"
	)
