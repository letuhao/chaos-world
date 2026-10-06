extends TestCase

## ADR 0884: the status gate is a flat power-vs-resist contest — `status.power.omni` /
## `.<kind>` / `.<status_id>` against the `status.resist.` counterparts and
## `status.resist.<element>` — read through the centered linear clamp: parity reads `0.5`,
## and `+/- status_rate_scale` of net advantage reads certainty / zero.

const _TITLE := &"test_status"
const _KIND := &"dot"

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


func _power(actor: Actor, id: StringName, value: float) -> void:
	actor.stats.add_modifier(CombatStats.rate_modifier(id, value, &"test"))


func _chance(attacker: Actor, target: Actor, element: StringName = &"") -> float:
	return StatusApply.apply_chance(attacker, target, _tuning, 1.0, _TITLE, _KIND, element, 0.0)


func test_parity_reads_half_and_the_advantage_reads_the_rate_scale() -> void:
	var plain := CombatTestKit.actor(&"plain")
	var open := CombatTestKit.actor(&"open")
	_power(open, StringName(_tuning.status_power_prefix + "omni"), _tuning.status_rate_scale)
	assert_almost_eq(_chance(null, plain), 0.5, "parity reads half")
	assert_almost_eq(_chance(open, plain), 1.0, "one rate scale of power reads certainty")


func test_each_of_the_three_offense_channels_is_read() -> void:
	var target := CombatTestKit.actor(&"target")
	for suffix in [&"omni", _KIND, _TITLE]:
		var attacker := CombatTestKit.actor(&"attacker")
		_power(
			attacker,
			StringName(_tuning.status_power_prefix + String(suffix)),
			float(_tuning.status_rate_scale) * 2.0
		)
		assert_almost_eq(_chance(attacker, target), 1.0, "channel %s counts" % String(suffix))


func test_the_resist_channels_take_the_chance_down_and_the_floor_holds() -> void:
	var attacker := CombatTestKit.actor(&"attacker")
	_power(
		attacker, StringName(_tuning.status_power_prefix + "omni"), float(_tuning.status_rate_scale)
	)
	for suffix in [&"omni", _KIND, _TITLE]:
		var target := CombatTestKit.actor(&"target")
		_power(
			target,
			StringName(_tuning.status_resist_prefix + String(suffix)),
			float(_tuning.status_rate_scale) * 2.0
		)
		assert_almost_eq(
			_chance(attacker, target),
			float(_tuning.status_min_apply),
			"resist channel %s takes the gate to the floor" % String(suffix)
		)


func test_the_element_channel_reads_the_status_s_own_element_only() -> void:
	var attacker := CombatTestKit.actor(&"attacker")
	_power(
		attacker, StringName(_tuning.status_power_prefix + "omni"), float(_tuning.status_rate_scale)
	)
	var warded := CombatTestKit.actor(&"warded")
	_power(
		warded,
		StringName(_tuning.status_resist_prefix + "fire"),
		float(_tuning.status_rate_scale) * 2.0
	)
	assert_almost_eq(
		_chance(attacker, warded, &"fire"),
		float(_tuning.status_min_apply),
		"the fire stance answers a fire status"
	)
	assert_almost_eq(_chance(attacker, warded, &"water"), 1.0, "and never another element")


func test_an_unauthored_prefix_leaves_the_gate_at_parity() -> void:
	var bare := CombatTestKit.shipped()
	bare.status_power_prefix = ""
	bare.status_resist_prefix = ""
	var attacker := CombatTestKit.actor(&"attacker")
	_power(attacker, &"status.power.omni", 99.0)
	assert_almost_eq(
		StatusApply.apply_chance(attacker, null, bare, 1.0, _TITLE, _KIND, &"", 0.0),
		0.5,
		"no prefix, no channels: parity"
	)
