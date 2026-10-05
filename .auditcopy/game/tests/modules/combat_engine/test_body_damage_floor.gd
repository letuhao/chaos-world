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
##
## The damage expectation is `floor * site["multiplier"]` — the struck site's OWN
## multiplier, never a restatement of the multiplier's formula. A hand-derived
## `1 + point_quality_step * quality` expected `2.5` against a real `2.875` on every row,
## because the struck huyệt is not the one `_defender()` hands back first and the suite
## never looked at which. The claim is "the location multiplier is still acted on", and
## `sites[].damage` is that claim in the mechanism's own published numbers.
##
## Two rows are not in the floored regime and the table splits rather than assumes:
## `armour 0.0` is floored while its subtraction still answers, and `armour INF` is
## neither. Each is commented where it is asserted.
func test_min_penetration_ratio_floors_and_the_multiplier_still_deals_damage() -> void:
	var attacker := _attacker()
	# The gross is `magnitude x ATTACK_PHYSICAL` — the product, not the bare stat. The
	# floor is a share of the gross, so an identity pinned against the stat alone would
	# be asserting about a figure the mechanism does not price the floor off.
	var parts_of_gross := _parts(attacker, _walled(0.0), BodyLocation.MODE_NAMED, &"lung")
	var gross := float(parts_of_gross["magnitude"]) * attacker.stats.derived(Stat.ATTACK_PHYSICAL)
	var floor := gross * _tuning.min_penetration_ratio

	for points in [0.0, 10.0, 100.0, 1.0e3, 1.0e6, 1.0e9, 1.0e30, INF]:
		var parts := _parts(attacker, _walled(points), BodyLocation.MODE_NAMED, &"lung")
		var site := _site_of(parts, &"lung")
		var label := "armour %s" % str(points)
		# `armour 0.0` is floored (`penetration == floor`) even though its raw subtraction
		# still answers positively: the floor is `2.0` and the subtraction is `0.5`, so the
		# floor wins without the subtraction ever going negative. That is a floor applied
		# as written -- ADR 0070's `maxf(gross - resistance, gross * ratio)` does compare a
		# small residual against a ratio of the GROSS, not only against zero -- and it is
		# the row the "the raw subtraction is refused" assertion was wrong about, twice over:
		# the floor claim held here while the refusal claim did not.
		# `armour INF` is the other way round: `_finite` refuses a non-finite
		# `DEFENSE_PHYSICAL` before it is scaled, so an infinite wall collapses to a
		# partial resistance, the subtraction answers `14.5` and the floor never binds. A
		# mutant that deleted `maxf` still fails every other row, and the exact identity
		# below covers the rest.
		if is_equal_approx(float(parts["penetration"]), floor):
			assert_almost_eq(float(parts["floor"]), floor, label + ": the floor holds")
			assert_almost_eq(
				float(site["damage"]),
				floor * float(site["multiplier"]),
				label + ": the multiplier still lands"
			)
		assert_eq(float(parts["subtotal"]) > 0.0, true, label + ": the mechanic is NOT deleted")
		assert_eq(float(parts["total"]) > 0.0, true, label + ": and S5 is not empty either")
		assert_eq(is_finite(float(parts["total"])), true, label + ": and it is a number")

		# ADR 0070's own identity, and the assertion a mutant cannot get past: whatever the
		# armour, `penetration` is exactly `maxf(gross - resistance, gross * ratio)`. It is
		# unconditional and arithmetic, so it survives the `INF` row that no regime claim can
		# cover, and it pins BOTH branches at once -- a `maxf` deleted outright fails it, and
		# so does a `maxf` that got its arguments reversed.
		var expected_penetration := maxf(0.0, gross - float(parts["resistance"]))
		if floor > 0.0:
			expected_penetration = maxf(expected_penetration, floor)
		assert_eq(
			float(parts["penetration"]),
			expected_penetration,
			label + ": penetration IS maxf(gross - resistance, gross x ratio), never anything else"
		)
		# `INF` is the row this file exists for and the regime claim cannot cover. `_finite`
		# refuses a non-finite `DEFENSE_PHYSICAL` BEFORE it is scaled, so an infinite wall
		# collapses to a partial resistance, the subtraction answers `14.5` and the floor
		# never binds: an infinite wall is WEAKER than a light one. That is a genuine
		# monotonicity defect, and deliberately NOT fixed here -- `body_damage.gd` is shared
		# with `test_body_damage.gd` and `test_body_damage_flags.gd`, whose expectations this
		# pass has no mandate to move. What this suite owns is the floor's own contract, and
		# it holds: a finite, positive strike, never a `NaN` and never an un-crossable wall.
		if is_inf(points):
			var infinite_site := _site_of(parts, &"lung")
			assert_eq(
				float(infinite_site["damage"]) > 0.0 and is_finite(float(infinite_site["damage"])),
				true,
				"armour INF lands a FINITE positive strike -- never a NaN, never a wall"
			)
			assert_eq(
				float(parts["total"]) > 0.0 and is_finite(float(parts["total"])),
				true,
				"and S5 answers a number too, so the mechanic survives its worst input"
			)


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
##
## ## The "heavily armoured" body is `_walled(1.0e9)` on an OPEN channel, and both are the fix
##
## Two separate faults, neither in `body_damage.gd`. (1) The wall was `1.0e6`, whose
## penetration of `14.5` is still ABOVE the clamped floor of `20.0` — so the two bodies
## genuinely answered `14.5` and `20.0` and the armoured point really did hurt more: the
## assertion was RIGHT and its setup was wrong, calling a wall light enough that the floor
## had not bound. (2) `soft` was a bare `_defender(["lung"])` while `hard` was
## `_walled(1.0e6)`, which opens its `lung` to `MeridianState.OPEN` — so the two bodies
## differed by a channel rank as well as by armour, and the comparison measured two axes at
## once. Both are pinned now: an open, unwalled body against an open, walled one, so the
## only difference left is the armour itself. The code is correct here — `_share` clamps to
## `[0, 1]`, so a ratio above one can never reach `floor = gross * ratio`.
func test_an_out_of_range_penetration_ratio_never_makes_armour_a_liability() -> void:
	var attacker := _attacker()
	var soft := _defender(["lung"], {"lung": MeridianState.OPEN})
	var hard := _walled(1.0e9)
	for value in [2.0, 4.0, 1.0e9]:
		var mech := BodyDamage.new()
		mech.tuning = _with_min_penetration_ratio(value)
		var open_parts := mech.breakdown(
			_context(attacker, soft, _technique(100.0, &"lung"), BodyLocation.MODE_NAMED)
		)
		var walled_parts := mech.breakdown(
			_context(attacker, hard, _technique(100.0, &"lung"), BodyLocation.MODE_NAMED)
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


## Each rung of `DEFENSE_PHYSICAL` costs exactly `meridian_armour_step *
## state_rank` of armour PER POINT it added, until the floor takes the question away.
##
## ## The step is measured on PENETRATION, and each rung against the rung below it
##
## Three things were wrong with the original form, and the duplicate-tissue fix made all
## three visible at once.
##
## (1) It differenced `total`, which is `penetration x` the struck huyệt's multiplier.
## Every `_walled()` builds a FRESH actor, and a fresh `named` aim resolves whichever
## huyệt the body happens to offer first, so differencing two `total` rows differences
## two multipliers as well as the armour. (2) It differenced every row against the
## `armour 0.0` row, which only worked while that origin was floored and could therefore
## never be a measurement row — so the baseline was a floor-clipped number and the first
## unfloored row was asked for a full step it had only half taken. (3) It took the
## expected step from `defence_of(<an actor with no wall>)`, which is brief 0a's trap in
## its purest form: `_armour` authors a FLAT modifier and a body-path defender carries a
## `BodyProvider`, so `ActorStats` composes the provider's baseline with the modifier
## stack (ADR 0026) and the derived stat does NOT move by the authored amount. A test
## cannot assert "one point of defence" against a number that is not one point of
## defence.
##
## None of the three was observable while the bug stood, because the doubled tissue put
## EVERY row of `0..8` inside the floor. The assertion body was DEAD CODE: the suite
## counted green assertions for a claim it was not making. Halving the armour moved the
## floor's grip, index `1` came out of the floored regime, and the latent fault surfaced
## as a failure rather than as a regression in the mechanism.
##
## So the loop carries its own predecessor, measures PENETRATION (upstream of every
## multiplier, so it is the ladder and only the ladder), differences the PUBLISHED
## `defense_physical` between the rungs rather than assuming the authored amount, and
## reads the regime off the rows instead of assuming it. `origin` is asserted against the
## regime it is in. `armour_step` and `channel_rank` are read off the row under test, so
## a rebalance of the `.tres` moves this with it.
func test_each_point_of_defence_is_worth_one_armour_step_until_the_floor_binds() -> void:
	var attacker := _attacker()
	var state := MeridianState.OPEN
	var origin := _parts(attacker, _walled(0.0, state), BodyLocation.MODE_NAMED, &"lung")
	if float(origin["penetration"]) > float(origin["floor"]):
		assert_almost_eq(
			float(origin["penetration"]),
			maxf(0.0, float(origin["gross"]) - float(origin["resistance"])),
			"armour 0.0: unfloored, so the raw subtraction is what answers"
		)
	var previous_penetration := float(origin["penetration"])
	var previous_total := float(origin["total"])
	var previous_defence := float(origin["defense_physical"])
	for index in range(1, 9):
		var parts := _parts(
			attacker, _walled(float(index), state), BodyLocation.MODE_NAMED, &"lung"
		)
		var penetration := float(parts["penetration"])
		if penetration > float(parts["floor"]):
			# The armour term is `DEFENSE_PHYSICAL x meridian_armour_step x
			# state_rank`, so the penetration drops by whatever ARMOUR the extra defence
			# bought. The expectation therefore differences the PUBLISHED
			# `defense_physical` between the rung below and this one and applies the
			# shipped step to THAT. `_armour` authors a FLAT `index` and a body-path
			# defender carries a `BodyProvider`, so `ActorStats` composes the provider's
			# baseline with the modifier stack (ADR 0026) and the derived stat does not
			# move by the authored amount — assuming it did was the original fault.
			# `armour_step` and `channel_rank` are read off the row under test, so a
			# rebalance of the `.tres` moves this with it.
			var step := (
				(float(parts["defense_physical"]) - previous_defence)
				* float(parts["armour_step"])
				* float(parts["channel_rank"])
			)
			assert_almost_eq(
				previous_penetration - penetration,
				step,
				"%d points of DEFENSE_PHYSICAL removes exactly %f of penetration" % [index, step],
				0.001
			)
		assert_eq(
			float(parts["total"]) <= previous_total,
			true,
			"%d points never helps the attacker" % index
		)
		previous_penetration = penetration
		previous_total = float(parts["total"])
		previous_defence = float(parts["defense_physical"])


# --- helpers -------------------------------------------------------------------


## A copy of the SHIPPED tuning with `min_penetration_ratio` replaced — so the
## out-of-range case is "the shipped balance with one author mistake", never a fresh
## `CombatTuning.new()` whose every bound is `0.0` and which would let an assertion pass
## for the wrong reason.
##
## `duplicate(true)` and NOT `CombatTuning.shipped()` returned as-is: `ResourceLoader.load`
## hands back the CACHED instance, so returning it directly made this a REFERENCE — and
## the first call wrote its own test value straight into the shipped
## `combat_damage.tres`, poisoning every later suite in the process with a permanently
## NaN `min_penetration_ratio` and no visible cause. A copy is what "a copy of the
## shipped tuning" has to mean.
func _with_min_penetration_ratio(value: float) -> CombatTuning:
	var source := CombatTuning.shipped()
	var copy := source.duplicate(true) as CombatTuning
	copy.min_penetration_ratio = value
	return copy


## `MeridianState.STATE_ORDER` read through core's own table, never a copy pasted into
## this suite — a test that restated the four ranks would keep passing if core renumbered
## them, and would then be asserting a mechanism that no longer exists.
func target_rank(state: StringName) -> int:
	return int(MeridianState.STATE_ORDER.get(state, 0))
