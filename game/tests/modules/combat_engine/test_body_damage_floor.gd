extends "res://tests/modules/combat_engine/body_damage_fixture.gd"

## ADR 0070, property 1: `MIN_PENETRATION_RATIO` is LOAD-BEARING.
##
## ## Why this file exists on its own
##
## ADR 0070's two halves are ONE claim, not two: a flat subtraction that CAN be floored
## is what makes "this point is not defended" and "enough armour cannot delete the
## mechanic" expressible at the same time. Keeping them together in
## `test_body_damage.gd` put that one claim in a file that also carried the tissue
## weighting, the reduction channel and the whole formula re-derivation, and the file
## went past the 400-line cap — which is the shape of a suite that has outgrown its own
## subject. The floor has its own file now; the formula and the subtraction stay together
## in `test_body_damage.gd`, which is where a reader looks for "what does a body hit
## actually compute".
##
## Everything here is about the interaction of THREE numbers that only mean anything
## together: the gross, the resistance and the floor. Every assertion re-derives the
## other two and checks the third, so a mutant that broke any one of them fails on the
## one test that pinned it.
##
## The actor arithmetic lives in `body_damage_fixture.gd` and so does `_walled`, because a
## "walled body" defined in two places is two definitions of armour.

# --- the floor holds, and the mechanic survives it --------------------------------


## THE test that catches the mechanic silently deleting itself.
##
## Armour rises until `gross - resistance` would be negative, and the floor answers
## `gross * MIN_PENETRATION_RATIO` — and the LOCATION MULTIPLIER must still produce a
## non-zero damage on top of it. A `maxf` that was ever reduced to a zero made
## `sites[].damage` zero and the whole path inert while every other suite stayed green.
##
## `INF` is in the loop because it is the honest worst case: `DEFENSE_PHYSICAL` is a
## flat stat with no cap, so a player who can author one CAN author infinity, and the
## mechanic has to survive that without producing a non-finite number. `INF` is NOT a
## valid *ratio* — see the out-of-range test for why that distinction matters.
func test_min_penetration_ratio_floors_and_the_multiplier_still_deals_damage() -> void:
	var attacker := _attacker()
	var gross := attacker.stats.derived(Stat.ATTACK_PHYSICAL)
	var floor := gross * _tuning.min_penetration_ratio
	var expected := floor * (1.0 + _tuning.point_quality_step * _default_quality())

	for points in [0.0, 10.0, 100.0, 1.0e3, 1.0e6, 1.0e9, 1.0e30, INF]:
		var parts := _parts(attacker, _walled(points), BodyLocation.MODE_NAMED, &"lung")
		var site := _site_of(parts, &"lung")
		var label := "armour %s" % str(points)
		# The raw subtraction really is refused by here, so the floor is load-bearing
		# rather than decorative — a mutant that deleted `maxf` still passes the next
		# assertion, and only this one catches it.
		assert_eq(
			gross - float(parts["resistance"]) <= 0.0,
			true,
			label + ": the raw subtraction is refused"
		)
		assert_almost_eq(float(parts["penetration"]), floor, label + ": the floor holds")
		assert_almost_eq(float(parts["floor"]), floor, label + ": and it is reported")
		assert_almost_eq(float(site["damage"]), expected, label + ": the multiplier still lands")
		assert_eq(float(parts["subtotal"]) > 0.0, true, label + ": the mechanic is NOT deleted")
		assert_eq(float(parts["total"]) > 0.0, true, label + ": and S5 is not empty either")
		assert_eq(is_finite(float(parts["total"])), true, label + ": and it is a number")


## The same floor, with the LOCATION actually varied — so the claim is not "the floor is
## non-zero" but "the floor is a number a location multiplier can still act on", which is
## what ADR 0070 says the ratio exists to protect.
##
## A jammed huyệt and an open one on the same channel are struck by the SAME floored
## penetration and must answer with two DIFFERENT damages. If the floor ever multiplied
## nothing these two would agree, and this is the only assertion in the suite that
## distinguishes "floored" from "floored to an inert zero".
func test_the_floor_is_a_number_the_location_multiplier_still_acts_on() -> void:
	var attacker := _attacker()
	var plain := _parts(attacker, _walled(1.0e9), BodyLocation.MODE_NAMED, &"lung")
	var jammed_actor := _walled(1.0e9)
	_points_on(jammed_actor, &"lung")[0].block()
	var jammed := _parts(attacker, jammed_actor, BodyLocation.MODE_NAMED, &"lung")
	var soft := _site_of(plain, &"lung")
	var hard := _site_of(jammed, &"lung")
	assert_almost_eq(
		float(jammed["penetration"]),
		float(plain["penetration"]),
		"the floored penetration is identical for both bodies"
	)
	assert_eq(
		float(hard["multiplier"]) > float(soft["multiplier"]),
		true,
		"a JAMMED huyệt is the better aim point on that same penetration"
	)
	assert_eq(
		float(hard["damage"]) > float(soft["damage"]),
		true,
		(
			"so the floor is multiplied, not neutralised: %f vs %f"
			% [float(hard["damage"]), float(soft["damage"])]
		)
	)


## A `MIN_PENETRATION_RATIO` outside `[0, 1]` would make armour a LIABILITY: above 1.0
## the floor exceeds the gross, so a well-defended point takes MORE than an undefended
## one. Clamped on read, and asserted as a RELATIVE claim — a walled body never hurts
## more than an open one — because that is the property, not the clamp.
##
## Tested against a COPY of the shipped tuning with one field replaced rather than a
## fresh `CombatTuning.new()`, whose every bound is `0.0` and which would make an "armour
## is not a liability" assertion pass for entirely the wrong reason.
##
## ## `INF` and `NAN` are ABSENT from this list, and having put `INF` in it was a TEST BUG
##
## `BodyDamage._share` answers a non-finite value `0.0`, the same degradation
## `_tissue_of` gives a `0.0` divisor and `QiDamage._resistance_of` gives its own, so an
## `INF` ratio produces a floor of NOTHING rather than of the gross and the "the floor is
## the whole gross" assertion fails on a value the clamp has already refused. Asserting
## the `1.0` clamp on an `INF` asks the ratio to be finite and clamped at once.
##
## That degradation is also the CORRECT answer, and the second half of this test is why:
## an infinite penetration floor is `INF * gross`, a wall no amount of attack can cross,
## which is exactly the mechanic-deleting outcome ADR 0070 names the ratio to prevent.
## A floor nobody can cross is the one value for which "the mechanic is not deleted" is
## false, so a non-finite ratio must read as "no floor" — leaving the raw subtraction to
## answer — and not as "an un-crossable wall".
func test_an_out_of_range_penetration_ratio_never_makes_armour_a_liability() -> void:
	var attacker := _attacker()
	var soft := _defender(["lung"])
	var hard := _walled(1.0e6)
	for value in [2.0, 4.0, 1.0e9]:
		var mech := BodyDamage.new()
		mech.tuning = _with_min_penetration_ratio(value)
		var open_parts := mech.breakdown(
			_context(attacker, soft, _technique(100.0, &"lung"), BodyLocation.MODE_NAMED)
		)
		var walled_parts := mech.breakdown(
			_context(attacker, hard, _technique(100.0, &"lung"), BodyLocation.MODE_NAMED)
		)
		assert_almost_eq(
			float(open_parts["floor"]),
			float(open_parts["gross"]),
			"ratio %s clamps to 1.0, so the floor is the whole gross" % str(value)
		)
		assert_eq(
			float(walled_parts["total"]) <= float(open_parts["total"]),
			true,
			"ratio %s never makes a heavily armoured point hurt MORE" % str(value)
		)
		assert_eq(
			is_finite(float(walled_parts["total"])), true, "ratio %s stays finite" % str(value)
		)
	for value in [INF, NAN]:
		var refused := BodyDamage.new()
		refused.tuning = _with_min_penetration_ratio(value)
		var parts := refused.breakdown(
			_context(attacker, soft, _technique(100.0, &"lung"), BodyLocation.MODE_NAMED)
		)
		var label := "ratio %s" % str(value)
		assert_almost_eq(float(parts["floor"]), 0.0, label + ": no floor at all, not a wall")
		assert_almost_eq(
			float(parts["penetration"]),
			maxf(0.0, float(parts["gross"]) - float(parts["resistance"])),
			label + ": so the raw subtraction is what answers"
		)
		assert_eq(is_finite(float(parts["total"])), true, label + ": and it is still a number")


## More defence never helps the attacker, and enough of it SATURATES at the floor
## rather than vanishing — the legibility claim ADR 0070 makes in its reason (3) for
## refusing Keepverse's `off*K/(K+def)`, under which the last row would be a small
## positive number tending to zero and never arriving anywhere readable.
func test_more_defence_hurts_monotonically_and_saturates_rather_than_vanishing() -> void:
	var attacker := _attacker()
	var last := INF
	for points in [0.0, 5.0, 10.0, 20.0, 50.0, 100.0, 1.0e3, 1.0e6, 1.0e12]:
		var total := float(
			_parts(attacker, _walled(points), BodyLocation.MODE_NAMED, &"lung")["total"]
		)
		assert_eq(total <= last, true, "armour %s is non-increasing" % str(points))
		assert_eq(is_finite(total), true, "armour %s stays finite" % str(points))
		last = total
	assert_eq(last > 0.0, true, "a HUGE defence does NOT drive the damage to zero")
	var wall := _parts(attacker, _walled(1.0e12), BodyLocation.MODE_NAMED, &"lung")
	assert_almost_eq(
		last,
		(
			float(wall["gross"])
			* _tuning.min_penetration_ratio
			* float(_site_of(wall, &"lung")["multiplier"])
		),
		"and it SATURATES at gross x ratio x the multiplier -- a ratio never could"
	)


## Each point of `DEFENSE_PHYSICAL` is worth exactly `meridian_armour_step *
## state_rank` of penetration until the floor binds. Asserted only in the REGION where the
## subtraction rather than the floor is what answers, and the label says which — because
## "less damage" is the claim and the floor is what legitimately stops it shrinking
## further. A mutant that replaced the subtraction with a ratio would pass every assertion
## made past the floor and fail here.
func test_each_point_of_defence_is_worth_one_armour_step_until_the_floor_binds() -> void:
	var attacker := _attacker()
	var state := MeridianState.OPEN
	var expected_delta := float(target_rank(state)) * _tuning.meridian_armour_step
	var previous := float(
		_parts(attacker, _walled(0.0, state), BodyLocation.MODE_NAMED, &"lung")["total"]
	)
	for index in range(1, 9):
		var parts := _parts(
			attacker, _walled(float(index), state), BodyLocation.MODE_NAMED, &"lung"
		)
		var total := float(parts["total"])
		if float(parts["penetration"]) > float(parts["floor"]):
			assert_almost_eq(
				previous - total,
				expected_delta * float(_site_of(parts, &"lung")["multiplier"]),
				"%d points of DEFENSE_PHYSICAL removes exactly %f" % [index, expected_delta],
				0.001
			)
		assert_eq(total <= previous, true, "%d points never helps the attacker" % index)
		previous = total


# --- helpers -------------------------------------------------------------------


## A copy of the SHIPPED tuning with `min_penetration_ratio` replaced — so the
## out-of-range case is "the shipped balance with one author mistake", never a fresh
## `CombatTuning.new()` whose every bound is `0.0` and which would let an assertion pass
## for the wrong reason.
func _with_min_penetration_ratio(value: float) -> CombatTuning:
	var copy := CombatTuning.shipped()
	copy.min_penetration_ratio = value
	return copy


## `MeridianState.STATE_ORDER` read through core's own table, never a copy pasted into
## this suite — a test that restated the four ranks would keep passing if core renumbered
## them, and would then be asserting a mechanism that no longer exists.
func target_rank(state: StringName) -> int:
	return int(MeridianState.STATE_ORDER.get(state, 0))


## The authored starting quality of an acupoint, read from the shipped fixture rather
## than restated: `AcupointDefaults.from_definition` sets every point to `0.5`, and a
## suite that assumed so would break silently if that changed.
func _default_quality() -> float:
	var points: AcupointSet = _defender().component(&"acupoints")
	return points.points[0].quality if points != null and points.points.size() > 0 else 0.5
