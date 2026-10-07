extends TestCase

## ADR 0902 (P10/P11/P15): the apply-chance shape and the authored tuning keys.
##
## The SHAPE claim is byte-identity: with the shipped `combat_damage.tres` the linear
## default must reproduce the pre-shape formula exactly — `clampf(0.5 + delta / (2 *
## status_rate_scale), 0, 1)` — and every other key must be a reachable, authored dial.
## The guard half reads the SHIPPED resource text, so "added in code, forgotten in data"
## is RED here rather than a silent default (P15=B).

## Every port key T6 added, required to be authored in the shipped resource.
const REQUIRED_KEYS: Array[String] = [
	"status_apply_shape",
	"status_apply_offset",
	"status_apply_steepness",
	"status_apply_scale_by_category",
	"status_apply_steepness_by_category",
	"status_tier_power_weight",
]
const TUNING_PATH := "res://src/modules/combat_engine/combat_damage.tres"


## `shipped()` returns a DUPLICATE of the cached resource, so a test may mutate it.
func _shipped() -> CombatTuning:
	return CombatTestKit.shipped()


## The chance at a chosen net advantage: a POSITIVE delta rides the attacker's
## `status.power.omni`; a NEGATIVE one rides the defender's elemental resist term, which
## `apply_chance` reads as a positive value (a negative power channel does not survive
## the stat's derived read, and a defender-side resist is how a deficit occurs in play).
func _chance(tuning: CombatTuning, delta: float, categories: Array = []) -> float:
	var attacker := CombatTestKit.actor(&"shaper")
	var target := CombatTestKit.actor(&"shaped")
	var elem_resist := 0.0
	if delta > 0.0:
		attacker.stats.add_modifier(
			CombatStats.rate_modifier(
				StringName(tuning.status_power_prefix + "omni"), delta, &"test"
			)
		)
	elif delta < 0.0:
		elem_resist = -delta
	return StatusApply.apply_chance(
		attacker,
		target,
		tuning,
		1.0,
		&"",
		&"",
		&"",
		elem_resist,
		StatusApply.SCOPE_COMBAT,
		&"",
		categories
	)


func test_every_port_key_is_authored_in_the_shipped_resource() -> void:
	var text := FileAccess.get_file_as_string(TUNING_PATH)
	assert_ne(text.is_empty(), true, "the shipped tuning resource is readable")
	for key in REQUIRED_KEYS:
		assert_eq(
			text.contains("\n%s = " % key),
			true,
			"'%s' is authored in combat_damage.tres, not merely defaulted in code" % key
		)


func test_the_shipped_defaults_are_the_realm_invariant_linear_reading() -> void:
	var tuning := _shipped()
	assert_eq(tuning.status_apply_shape, &"linear", "the shipped shape is the linear parity-half")
	assert_almost_eq(tuning.status_apply_offset, 0.0, "no offset is authored", 1e-9)
	assert_almost_eq(tuning.status_apply_steepness, 1.0, "the sigmoid dial starts neutral", 1e-9)
	assert_almost_eq(tuning.status_tier_power_weight, 0.0, "the tier knob is off", 1e-9)
	assert_eq(tuning.status_apply_scale_by_category.is_empty(), true, "no category overrides")
	assert_eq(tuning.status_apply_steepness_by_category.is_empty(), true, "and none for steepness")


## THE byte-identity row: the shipped tuning through the new shape code equals the
## pre-shape formula, at deltas either side of parity and past both clamps.
func test_the_linear_default_reproduces_the_pre_shape_formula() -> void:
	var tuning := _shipped()
	var scale := tuning.status_rate_scale
	for delta in [-3.0, -0.7, 0.0, 0.25, 1.0, 4.0]:
		var expected := clampf(
			clampf(0.5 + delta / (2.0 * scale), 0.0, 1.0), tuning.status_min_apply, 1.0
		)
		assert_almost_eq(
			_chance(tuning, delta),
			expected,
			"delta %s reads the shipped arithmetic" % str(delta),
			1e-9
		)


func test_the_sigmoid_shape_moves_the_curve_but_keeps_the_neutral_point() -> void:
	var tuning := _shipped()
	tuning.status_apply_shape = &"sigmoid"
	assert_almost_eq(_chance(tuning, 0.0), 0.5, "the neutral point stays parity", 1e-9)
	var linear := _shipped()
	assert_eq(
		absf(_chance(tuning, 1.0) - _chance(linear, 1.0)) > 1e-6,
		true,
		"a nonzero delta reads differently under the sigmoid"
	)


func test_the_offset_shifts_the_neutral_point() -> void:
	var tuning := _shipped()
	tuning.status_apply_offset = 0.25
	assert_almost_eq(_chance(tuning, 0.0), 0.25, "the offset lowers the neutral reading", 1e-9)
	assert_almost_eq(_chance(tuning, 0.25), 0.5, "and the offset's own value reads parity", 1e-9)


func test_a_category_override_replaces_the_scale_for_its_category() -> void:
	var tuning := _shipped()
	tuning.status_apply_scale_by_category = {"burning": 0.25}
	assert_almost_eq(
		_chance(tuning, -0.1), 0.4, "the base scale reads the shipped arithmetic", 1e-9
	)
	assert_almost_eq(
		_chance(tuning, -0.1, [&"burning"]), 0.3, "the category's scale takes over", 1e-9
	)
	assert_almost_eq(
		_chance(tuning, -0.1, [&"chilling"]), 0.4, "an absent category keeps the base", 1e-9
	)


## The tier knob is OFF and the gap it would fold is zero for two realmless actors —
## so the shipped reading cannot move, and the cross-realm MEASUREMENT (T10) owns any
## nonzero weight.
func test_the_tier_knob_is_off_and_folds_no_gap_without_realm_power() -> void:
	var tuning := _shipped()
	assert_almost_eq(tuning.status_tier_power_weight, 0.0, "off by default", 1e-9)
	tuning.status_tier_power_weight = 1.0
	var attacker := CombatTestKit.actor(&"tier_a")
	var target := CombatTestKit.actor(&"tier_b")
	var plain := StatusApply.apply_chance(attacker, target, _shipped(), 1.0, &"", &"", &"", 0.0)
	var weighted := StatusApply.apply_chance(attacker, target, tuning, 1.0, &"", &"", &"", 0.0)
	assert_almost_eq(weighted, plain, "two realmless actors have no gap to fold", 1e-9)
