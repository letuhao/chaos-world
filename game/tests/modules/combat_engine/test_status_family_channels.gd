extends TestCase

## ADR 0902 (P12): `family` and `categories` are two more channel terms on the RESIST
## side (`status.resist.<family>` / `status.resist.<category>`) and two more immunity
## tags (`status.immune.<family>` / `<category>`). The shipped omni/kind/status/element
## resolution is untouched — the terms are ADDITIVE.
##
## The channel half asserts on `StatusApply.apply_chance` DIRECTLY, the deterministic
## door: at parity the apply ROLL is a coin flip, so a resolve-path assertion would be
## measuring the seed as much as the channel. The immunity half goes through the real
## resolve path, because the hard refusal is a property of that entry point.

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


func _attr(actor: Actor, id_prefix: String, suffix: String, value: float) -> void:
	actor.stats.add_modifier(
		CombatStats.rate_modifier(StringName(id_prefix + suffix), value, &"test")
	)


func _chance(family: StringName = &"", categories: Array = [], target: Actor = null) -> float:
	return StatusApply.apply_chance(
		null, target, _tuning, 1.0, &"", &"", &"", 0.0, StatusApply.SCOPE_COMBAT, family, categories
	)


func test_an_empty_request_reads_parity_half() -> void:
	var target := CombatTestKit.actor(&"target")
	assert_almost_eq(_chance(&"", [], target), 0.5, "parity reads half", 1e-6)


## The family term is inert on its own and answers its own channel when authoured.
func test_the_family_channel_lowers_the_chance_and_only_when_authored() -> void:
	var target := CombatTestKit.actor(&"target")
	assert_almost_eq(
		_chance(&"emberkin", [], target), 0.5, "naming a family is not by itself a resist", 1e-6
	)
	_attr(target, _tuning.status_resist_prefix, "emberkin", 0.2)
	assert_almost_eq(
		_chance(&"emberkin", [], target),
		0.3,
		"and its channel lowers the chance by the value over the rate scale",
		1e-6
	)


## Each authored category is its own channel id, for the same reason one mechanism
## never grew two.
func test_each_category_is_its_own_resist_channel() -> void:
	var target := CombatTestKit.actor(&"target")
	_attr(target, _tuning.status_resist_prefix, "burning", 0.2)
	assert_almost_eq(_chance(&"", [&"burning"], target), 0.3, "the category answers", 1e-6)
	assert_almost_eq(
		_chance(&"", [&"chilling"], target),
		0.5,
		"and an unchanneled category reads nothing, so the term is per-id",
		1e-6
	)


## The resolve path, for the hard refusals: an immunity tag refuses before the roll.
func _resolve_for(request: Dictionary, setup_target: Callable = Callable()) -> Dictionary:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	# Saturated accuracy so the BAND never decides these cases: every assertion below
	# is about the immunity the request carries.
	attacker.stats.add_modifier(CombatStats.rate_modifier(CombatStats.ACCURACY, 1.0, &"test"))
	var target := CombatTestKit.actor(&"target")
	if setup_target.is_valid():
		setup_target.call(target)
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 25.0
	MechanismSlot.bind(attacker, mechanism)
	var rng := CombatTestKit.rng(11)
	var technique := CombatTestKit.technique(100.0)
	var outcome := CombatSpine.resolve_hit(attacker, target, technique, _tuning, rng)
	var ctx := AttackContext.new(attacker, target, technique, _tuning)
	ctx.set_data(StatusApply.REQUEST_KEY, request)
	return StatusApply.apply(attacker, target, _tuning, ctx, outcome, rng, technique, 0)


func _request(extra: Dictionary = {}) -> Dictionary:
	var request := {
		"id": &"family_probe",
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


func test_a_family_immunity_refuses_the_status_outright() -> void:
	var result := _resolve_for(
		_request({"family": &"emberkin"}),
		func(target: Actor) -> void: _attr(target, _tuning.status_immune_prefix, "emberkin", 1.0)
	)
	assert_eq(bool(result.get(StatusApply.APPLIED, true)), false, "the family immunity refuses")
	assert_eq(
		String(result.get(StatusApply.REFUSED, "")),
		String(StatusApply.REFUSE_IMMUNE),
		"with the immune reason"
	)


func test_a_category_immunity_refuses_the_status_outright() -> void:
	var result := _resolve_for(
		_request({"categories": [&"burning"]}),
		func(target: Actor) -> void: _attr(target, _tuning.status_immune_prefix, "burning", 1.0)
	)
	assert_eq(bool(result.get(StatusApply.APPLIED, true)), false, "the category immunity refuses")
	assert_eq(
		String(result.get(StatusApply.REFUSED, "")),
		String(StatusApply.REFUSE_IMMUNE),
		"with the immune reason"
	)
