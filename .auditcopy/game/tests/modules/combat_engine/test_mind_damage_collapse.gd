extends "res://tests/modules/combat_engine/mind_damage_fixture.gd"

## ADR 0071's two COMBAT TICKS: rupture bleed (the ONLY thing on the mind path that
## moves health) and collapse (the only thing that costs the defender their sea tier).
##
## They are split from `test_mind_damage.gd` for the same reason qi's were split: the
## gdlint ceiling is 20 public methods per suite, and these are a different subject --
## they read sea STATE over TIME rather than computing a hit's erosion. Neither is a
## hit: `CombatSpine` has no stage for either, and ADR 0071 adds none, exactly as ADR
## 0070's `BodyDamage.decay` is separate for the same reason.
##
## Both take `delta` as a PARAMETER and never read a wall clock, so a replay bleeds
## exactly as it was driven.

# --- property 3: health moves ONLY above the rupture threshold ------------------


## Below `RUPTURE_THRESHOLD`, `tick_rupture` costs EXACTLY `0.0`. This is the floor of
## safety qi (ADR 0069) and body (ADR 0070) do not have -- a mind duel cannot chip a
## defender who has not been pushed past the threshold.
##
## Looped right up to the threshold so the boundary is inclusive: at exactly the
## threshold the bleed is zero, and one hair above it is not.
func test_below_the_rupture_threshold_health_is_exactly_flat() -> void:
	var threshold := _tuning.rupture_threshold
	assert_almost_eq(threshold, 0.7, "ADR 0071's RUPTURE_THRESHOLD is 0.70")
	for turbulence in [0.0, 0.1, 0.5, 0.69, threshold]:
		var actor := _defender(0.0, 0.0)
		var sea := _sea_of(actor)
		sea.turbulence = turbulence
		var health := actor.resource(&"health") as ResourcePool
		var before := health.current
		var result := _rupture(sea, actor, 1.0)
		assert_almost_eq(
			float(result[MindDamage.KEY_HP_LOSS]),
			0.0,
			"turbulence %s costs exactly 0.0 health" % str(turbulence)
		)
		assert_eq(result[MindDamage.KEY_BLEEDING], false, "and is not reported as bleeding")
		assert_eq(health.current, before, "and the health pool is byte-identical")


## Above the threshold, the ADR's formula exactly:
## `hp_loss = max_health * RUPTURE_BLEED * (turbulence - threshold) / (1 - threshold) * delta`.
##
## Asserted at several headrooms and at a full second, and against the pool's own
## `maximum` rather than a restated 1000.0 -- the formula reads the pool, so the test
## does too.
func test_above_the_rupture_threshold_health_moves_by_the_adrs_formula() -> void:
	var threshold := _tuning.rupture_threshold
	for turbulence in [0.8, 0.85, 0.9, 1.0]:
		var actor := _defender(0.0, 0.0)
		var sea := _sea_of(actor)
		sea.turbulence = turbulence
		var health := actor.resource(&"health") as ResourcePool
		var maximum := health.maximum
		var before := health.current
		var delta := 1.0
		var result := _rupture(sea, actor, delta)
		var expected: float = (
			maximum * _tuning.rupture_bleed * (turbulence - threshold) / (1.0 - threshold) * delta
		)
		assert_almost_eq(
			float(result[MindDamage.KEY_HP_LOSS]),
			expected,
			"turbulence %s bleeds the ADR's formula" % str(turbulence)
		)
		assert_eq(
			result[MindDamage.KEY_BLEEDING], true, "turbulence %s is bleeding" % str(turbulence)
		)
		assert_almost_eq(before - health.current, expected, "and the health pool actually spent it")
	# At full turbulence the bleed is RUPTURE_BLEED of the whole pool per second -- the
	# authored ceiling, and the reason a mind duel disarms rather than kills.
	var actor := _defender(0.0, 0.0)
	var sea := _sea_of(actor)
	sea.turbulence = 1.0
	var health := actor.resource(&"health") as ResourcePool
	var full := _rupture(sea, actor, 1.0)
	assert_almost_eq(
		float(full[MindDamage.KEY_HP_LOSS]),
		health.maximum * _tuning.rupture_bleed,
		"at turbulence 1.0 the bleed is RUPTURE_BLEED of the whole pool per second"
	)


## The threshold is INCLUSIVE: at exactly `RUPTURE_THRESHOLD` the bleed is zero, and
## one hair above it is not. That boundary is what "moves ONLY above the threshold" means
## and it is the boundary a rebalance would move.
func test_the_threshold_is_inclusive_and_bleeds_immediately_above_it() -> void:
	var actor := _defender(0.0, 0.0)
	var sea := _sea_of(actor)
	var threshold := _tuning.rupture_threshold
	sea.turbulence = threshold
	assert_almost_eq(
		float(_rupture(sea, actor, 1.0)[MindDamage.KEY_HP_LOSS]),
		0.0,
		"AT the threshold is exactly zero"
	)
	sea.turbulence = threshold + 0.0001
	assert_eq(
		float(_rupture(sea, actor, 1.0)[MindDamage.KEY_HP_LOSS]) > 0.0,
		true,
		"one hair ABOVE it bleeds"
	)


## `delta` scales the bleed LINEARLY and is always a parameter -- never a wall-clock read,
## so a replay bleeds exactly as it was driven. A zero or negative `delta` costs nothing.
func test_delta_scales_the_bleed_linearly_and_never_goes_negative() -> void:
	var actor := _defender(0.0, 0.0)
	var sea := _sea_of(actor)
	sea.turbulence = 1.0
	var health := actor.resource(&"health") as ResourcePool
	var per_second := float(_rupture(sea, actor, 1.0)[MindDamage.KEY_HP_LOSS])
	# Half a second costs half as much.
	var half_actor := _defender(0.0, 0.0)
	var half_sea := _sea_of(half_actor)
	half_sea.turbulence = 1.0
	var half := float(_rupture(half_sea, half_actor, 0.5)[MindDamage.KEY_HP_LOSS])
	assert_almost_eq(half, per_second * 0.5, "the bleed is linear in delta")
	# A non-positive delta is not a backwards heal.
	var idle := _rupture(sea, actor, 0.0)
	assert_almost_eq(float(idle[MindDamage.KEY_HP_LOSS]), 0.0, "a 0.0 delta costs nothing")
	# Health never goes below zero across a long rupture.
	for _tick in 100:
		_rupture(sea, actor, 1.0)
	assert_eq(health.current >= 0.0, true, "health is never driven negative by the bleed")


# --- property 7 (collapse half): collapse demotes the sea, leaves health untouched --


## The collapse: `turbulence == 1.0` held for `RUPTURE_COLLAPSE_TIME` CONTINUOUS seconds
## demotes the sea ONE TIER, resets `structural_capacity` to that tier's floor, floors
## `clarity` at `COLLAPSE_CLARITY_FLOOR`, and applies `mind_deviation`. **The loser is
## disarmed for a minute, not killed.**
##
## Driven one second at a time across exactly the ADR's window, so the accumulation is
## the real continuous timer and not a single hand-set delta.
func test_collapse_demotes_the_sea_and_leaves_health_untouched() -> void:
	var window := _tuning.rupture_collapse_time
	assert_almost_eq(window, 3.0, "ADR 0071's RUPTURE_COLLAPSE_TIME is 3.0 continuous seconds")
	var actor := _defender(0.0, 0.0)
	var sea := _sea_of(actor)
	sea.turbulence = 1.0
	var health := actor.resource(&"health") as ResourcePool
	var before_health := health.current
	assert_eq(sea.tier, TIER_SHALLOW, "the sea starts at the shallowest tier")

	# Drive the timer one second at a time. The accumulator is the CALLER's (ADR 0071:
	# this module may not add a field to a component it does not own), so the suite keeps
	# it and feeds it back -- which is what a combat tick does.
	var held := 0.0
	var collapsed: Dictionary = {}
	for _tick in 4:
		var result := MindDamage.tick_collapse(sea, actor, 1.0, held)
		held = float(result[MindDamage.KEY_HELD])
		if bool(result[MindDamage.KEY_COLLAPSED]):
			collapsed = result
			break

	assert_eq(bool(collapsed.get(MindDamage.KEY_COLLAPSED, false)), true, "the sea collapsed")
	assert_eq(String(collapsed[MindDamage.KEY_FROM_TIER]), String(TIER_SHALLOW), "from shallow")
	assert_eq(String(collapsed[MindDamage.KEY_TO_TIER]), String(TIER_DEEP), "to deep")
	# One tier down the ladder -- not two, and not a new invented tier (hole 8).
	assert_eq(sea.tier, TIER_DEEP, "the sea's tier was demoted exactly one step")
	# Structural capacity reset to that tier's authored floor.
	assert_almost_eq(
		sea.structural_capacity,
		_tuning.collapse_capacity_floors.get(String(TIER_DEEP), 0.0),
		"structural_capacity reset to the demoted tier's floor"
	)
	# Clarity floored at COLLAPSE_CLARITY_FLOOR -- how much breakthrough progress it cost.
	assert_almost_eq(
		sea.clarity, _tuning.collapse_clarity_floor, "clarity floored at the collapse floor"
	)
	# The disarm is a real StatusEffect applied to the actor, with the ADR's duration.
	assert_eq(
		String(collapsed[&"deviation"]),
		String(MindDamage.DEVIATION_STATUS),
		"mind_deviation applied"
	)
	assert_eq(
		actor.has_status(MindDamage.DEVIATION_STATUS), true, "and the actor really carries it"
	)
	# AND THE LOVER'S HEALTH IS UNTOUCHED: a collapse disarms, it does not kill.
	assert_eq(health.current, before_health, "a collapse leaves health byte-identical")


## One tick SHORT does nothing. The continuous window is the ADR's, so a sea held at full
## turbulence for `window - 1` seconds has NOT collapsed, and a demotion a single second
## early is a defect.
func test_one_tick_short_of_the_window_does_nothing() -> void:
	var actor := _defender(0.0, 0.0)
	var sea := _sea_of(actor)
	sea.turbulence = 1.0
	var held := 0.0
	var collapsed := false
	var step := 0.5
	# Accumulate to one second short of the window, in half-second ticks.
	while held < _tuning.rupture_collapse_time - step:
		var result := MindDamage.tick_collapse(sea, actor, step, held)
		held = float(result[MindDamage.KEY_HELD])
		if bool(result[MindDamage.KEY_COLLAPSED]):
			collapsed = true
			break
	assert_eq(collapsed, false, "one tick short of the window does NOT collapse")
	assert_eq(sea.tier, TIER_SHALLOW, "and the tier is untouched")
	assert_almost_eq(held, _tuning.rupture_collapse_time - step, "the timer stopped one tick short")


## Dropping turbulence RESETS the timer -- continuity is what makes `meditate` a real
## answer rather than a second resource to manage (ADR 0071).
##
## Two seconds at full turbulence, then calm the sea and start again: the timer resets to
## zero on the calm tick, so the two accumulated seconds do not count toward the next
## window.
func test_dropping_turbulence_resets_the_collapse_timer() -> void:
	var actor := _defender(0.0, 0.0)
	var sea := _sea_of(actor)
	sea.turbulence = 1.0
	# Two seconds at full turbulence -- under the window, so nothing collapsed.
	var first := MindDamage.tick_collapse(sea, actor, 1.0, 0.0)
	assert_almost_eq(float(first[MindDamage.KEY_HELD]), 1.0, "one second is held")
	var second := MindDamage.tick_collapse(sea, actor, 1.0, float(first[MindDamage.KEY_HELD]))
	assert_almost_eq(float(second[MindDamage.KEY_HELD]), 2.0, "two seconds is held")
	# Calm the sea (this is what `meditate` does) and tick again -- the timer resets.
	sea.calm(1.0)
	var calm := MindDamage.tick_collapse(sea, actor, 1.0, float(second[MindDamage.KEY_HELD]))
	assert_almost_eq(float(calm[MindDamage.KEY_HELD]), 0.0, "a calmed sea resets the timer")
	assert_eq(bool(calm[MindDamage.KEY_COLLAPSED]), false, "and does not collapse")
	# Starting over, two more seconds is still not the window -- the reset was real.
	sea.turbulence = 1.0
	var restarted := MindDamage.tick_collapse(sea, actor, 1.0, 0.0)
	assert_almost_eq(float(restarted[MindDamage.KEY_HELD]), 1.0, "the window restarted from zero")


## A sea already at the bottom of the ladder (`vast`) has no successor and is REFUSED,
## and the timer resets rather than accumulating into a collapse that can never fire
## (hole 8). A demotion past `vast` would be a cultivation decision this module may not
## make.
func test_a_sea_at_the_bottom_of_the_ladder_is_never_demoted_past_vast() -> void:
	var actor := _defender(0.0, 0.0)
	var sea := _sea_of(actor)
	sea.set_tier(TIER_VAST)
	sea.turbulence = 1.0
	var held := 0.0
	for _tick in 6:
		var result := MindDamage.tick_collapse(sea, actor, 1.0, held)
		held = float(result[MindDamage.KEY_HELD])
		assert_eq(bool(result[MindDamage.KEY_COLLAPSED]), false, "vast is never demoted past")
	assert_eq(sea.tier, TIER_VAST, "the tier stays vast")
	assert_almost_eq(held, 0.0, "and the timer resets rather than accumulating")


## A null sea or a null actor is a supported state: the tick declines rather than
## crashing a combat loop (the same degradation every absent read on the file gives).
func test_rupture_and_collapse_degrade_on_null_arguments() -> void:
	var actor := _defender(0.0, 0.0)
	var sea := _sea_of(actor)
	sea.turbulence = 1.0
	assert_almost_eq(
		float(_rupture(null, actor, 1.0)[MindDamage.KEY_HP_LOSS]), 0.0, "a null sea bleeds nothing"
	)
	assert_almost_eq(
		float(_rupture(sea, null, 1.0)[MindDamage.KEY_HP_LOSS]), 0.0, "a null actor bleeds nothing"
	)
	var collapse := MindDamage.tick_collapse(null, actor, 1.0, 0.0)
	assert_eq(bool(collapse[MindDamage.KEY_COLLAPSED]), false, "a null sea does not collapse")
