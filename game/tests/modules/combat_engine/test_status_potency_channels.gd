extends TestCase

## ADR 0885: the potency split — `status.intensity.*` scales the MAGNITUDE,
## `status.duration.*` the TIME, each against its `*Reduction` counterpart through
## `net = clampf(1 + delta / status_net_factor_scale, min, max)`; parity is `1.0`, so a
## request with no split channels writes the same status the pre-split code wrote. The
## immunity tags land on top: `status.immune.<tag>` refuses, `status.immuneReduction.<tag>`
## blunts both factors.

const _TITLE := &"test_poison"
const _KIND := &"dot"

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


func _attr(actor: Actor, id_prefix: String, suffix: String, value: float) -> void:
	actor.stats.add_modifier(
		CombatStats.rate_modifier(StringName(id_prefix + suffix), value, &"test")
	)


func _open_attacker() -> Actor:
	var attacker := CombatTestKit.quiet_actor(&"hero")
	# Saturated accuracy so the band roll ALWAYS lands clean (ADR 0877's trigger), because
	# every case here is about S12's own arithmetic and never about the band.
	attacker.stats.add_modifier(CombatStats.rate_modifier(CombatStats.ACCURACY, 1.0, &"test"))
	_attr(attacker, _tuning.status_power_prefix, "omni", float(_tuning.status_rate_scale) * 4.0)
	return attacker


func _request(extra: Dictionary = {}) -> Dictionary:
	var request := {
		"id": _TITLE,
		"chance": 1.0,
		"element": &"fire",
		"kind": _KIND,
		"duration": 10.0,
		"potency": 1.0,
		"scope": String(StatusApply.SCOPE_COMBAT),
	}
	for key in extra.keys():
		request[key] = extra[key]
	return request


func _resolve(
	attacker: Actor, target: Actor, request: Dictionary, seed_value: int = 11
) -> Dictionary:
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 25.0
	MechanismSlot.bind(attacker, mechanism)
	var rng := CombatTestKit.rng(seed_value)
	var technique := CombatTestKit.technique(100.0)
	var outcome := CombatSpine.resolve_hit(attacker, target, technique, _tuning, rng)
	var ctx := AttackContext.new(attacker, target, technique, _tuning)
	ctx.set_data(StatusApply.REQUEST_KEY, request)
	return StatusApply.apply(attacker, target, _tuning, ctx, outcome, rng, technique, 0)


func test_parity_writes_the_same_status_the_pre_split_code_wrote() -> void:
	var target := CombatTestKit.actor(&"target")
	var result := _resolve(_open_attacker(), target, _request())
	assert_eq(bool(result[StatusApply.APPLIED]), true, "the open gate lands")
	assert_almost_eq(float(result[&"intensity_net"]), 1.0, "parity reads 1.0")
	assert_almost_eq(float(result[&"duration_net"]), 1.0, "on both factors")
	assert_almost_eq(float(result[&"potency"]), 1.0, "so the authored magnitude is untouched")


func test_the_intensity_channel_scales_the_magnitude() -> void:
	var attacker := _open_attacker()
	_attr(attacker, _tuning.status_intensity_prefix, "omni", 1.0)
	var target := CombatTestKit.actor(&"target")
	var result := _resolve(attacker, target, _request())
	assert_almost_eq(float(result[&"intensity_net"]), 2.0, "one scale of intensity doubles it")
	assert_almost_eq(float(result[&"potency"]), 2.0, "so the magnitude doubles")


func test_the_duration_channel_scales_the_time_and_never_the_magnitude() -> void:
	var attacker := _open_attacker()
	_attr(attacker, _tuning.status_duration_prefix, "omni", 1.0)
	var target := CombatTestKit.actor(&"target")
	var result := _resolve(attacker, target, _request())
	assert_almost_eq(float(result[&"duration_net"]), 2.0, "one scale of duration doubles it")
	assert_almost_eq(float(result[&"potency"]), 1.0, "and the magnitude is untouched")


func test_a_reduction_channel_floors_the_intensity_and_refuses_by_name() -> void:
	var target := CombatTestKit.actor(&"target")
	_attr(
		target,
		_tuning.status_intensity_reduction_prefix,
		"omni",
		float(_tuning.status_net_factor_scale)
	)
	var result := _resolve(_open_attacker(), target, _request())
	assert_eq(bool(result[StatusApply.APPLIED]), false, "a net factor at the floor refuses")
	assert_eq(
		String(result[StatusApply.REFUSED]),
		String(StatusApply.REFUSE_NO_POTENCY),
		"by name, before any roll"
	)


func test_an_immunity_tag_refuses_outright() -> void:
	var target := CombatTestKit.actor(&"target")
	_attr(target, _tuning.status_immune_prefix, "holy", 1.0)
	var result := _resolve(_open_attacker(), target, _request({"immunity_tags": [&"holy"]}))
	assert_eq(bool(result[StatusApply.APPLIED]), false, "a full immunity refuses")
	assert_eq(
		String(result[StatusApply.REFUSED]), String(StatusApply.REFUSE_IMMUNE), "by its own name"
	)


func test_a_partial_immunity_blunts_both_factors() -> void:
	var target := CombatTestKit.actor(&"target")
	_attr(target, _tuning.status_immune_reduction_prefix, "holy", 0.5)
	var result := _resolve(_open_attacker(), target, _request({"immunity_tags": [&"holy"]}))
	assert_eq(bool(result[StatusApply.APPLIED]), true, "half of an immunity does not refuse")
	assert_almost_eq(float(result[&"intensity_net"]), 0.5, "the magnitude is halved")
	assert_almost_eq(float(result[&"duration_net"]), 0.5, "and so is the time")


func test_the_net_factor_clamps_at_the_authored_ceiling() -> void:
	var attacker := _open_attacker()
	_attr(attacker, _tuning.status_intensity_prefix, "omni", 1.0e6)
	var target := CombatTestKit.actor(&"target")
	var result := _resolve(attacker, target, _request())
	assert_almost_eq(
		float(result[&"intensity_net"]),
		float(_tuning.status_max_net_factor),
		"the ceiling is an OUTPUT bound (ADR 0200)"
	)
