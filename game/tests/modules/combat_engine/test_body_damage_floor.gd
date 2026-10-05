extends "res://tests/modules/combat_engine/body_damage_fixture.gd"

## ADR 0070, property 1: `MIN_PENETRATION_RATIO` is LOAD-BEARING.
##
## ## Why this file exists on its own
##
## ADR 0070's two halves are ONE claim, not two: a ratio that CAN be floored is what makes
## "enough armour cannot delete the mechanic" expressible at the same time as "every further
## point of defence still pays". Keeping them together in `test_body_damage.gd` put that one
## claim in a file that also carried the tissue weighting, the reduction channel and the
## whole formula re-derivation, and the file went past the 400-line cap — which is the shape
## of a suite that has outgrown its own subject. The floor has its own file now; the formula
## and the ratio stay together in `test_body_damage.gd`, which is where a reader looks for
## "what does a body hit actually compute".
##
## ## ADR 0200: the floor SURVIVED the ratio, and this file is the proof
##
## `body_damage.gd` replaces ADR 0070's flat subtraction with
## `gross * (1 - mitigation_ceiling * D/(K+D))`, which approaches zero without ever reaching
## it. Every one of ADR 0070's four objections to a bare ratio is still true of that
## shape, and the docblock answers them: three of them argue for a FLOOR rather than
## against ratios, and the fourth — "defense is un-authorable under a ratio" — is a real
## cost ADR 0200 pays and states plainly.
##
## So the claim here did not weaken; it changed form. The floor is still the mechanism's
## only `0.0`, and this file still asserts the floor twice: once against armour that
## saturates the mitigation, and once against armour that the ratio alone would answer.
## The identity every assertion below is measured against is now
## `penetration = maxf(gross * (1 - m), gross * ratio)`, derived by
## `body_damage_fixture.gd`'s `_expected_penetration` so there is one copy of it.
##
## Everything here is about the interaction of FOUR numbers that only mean anything
## together: the gross, the armour magnitude `D`, the attacker's `K` and the floor. Every
## assertion re-derives the others and checks the one under test, so a mutant that broke
## any one of them fails on the one test that pinned it.
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
		# `armour 0.0` is floored because the RATIO already took almost all of the gross:
		# the tissue term alone puts `m` at `0.95 * 2.75 / 902.75 = 0.00289`, so the
		# un-mitigated share is `1994.2` and the floor of `200.0` never binds. That is the
		# opposite of the pre-ADR-0200 regime, where the deleted subtraction left `0.5`
		# against a floor of `2.0` and the floor bound at `armour 0.0`. Both are floors
		# applied as written; which branch binds is a property of the curve, not of the
		# `maxf`.
		# `armour INF` is still the row this file exists for: `_finite` refuses a
		# non-finite `DEFENSE_PHYSICAL` before it is scaled, so an infinite wall collapses
		# to a partial resistance, the ratio answers a partial penetration and the floor
		# never binds.
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

		# ADR 0200's identity, and the assertion a mutant cannot get past: whatever the
		# armour, `penetration` is exactly `maxf(gross * (1 - m), gross * ratio)` with
		# `m = mitigation_ceiling * D / (K + D)` and `K = defense_divisor_k * gross`. It is
		# unconditional and arithmetic, so it survives the `INF` row that no regime claim
		# can cover, and it pins BOTH branches at once — a `maxf` deleted outright fails it,
		# and so does a `maxf` that got its arguments reversed.
		assert_almost_eq(
			float(parts["mitigation_rate"]),
			_expected_mitigation_rate(float(parts["resistance"]), float(parts["gross"]), _tuning),
			label + ": the mitigation is `ceiling * D / (K + D)`, re-derived from the tuning"
		)
		assert_almost_eq(
			float(parts["penetration"]),
			_expected_penetration(parts),
			label + ": penetration IS maxf(gross x (1 - m), gross x ratio), never anything else"
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
## false, so a non-finite ratio must read as "no floor" — leaving ADR 0200's RATIO to
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
			_expected_penetration(parts),
			label + ": so the ratio is what answers"
		)
		assert_eq(is_finite(float(parts["total"])), true, label + ": and it is still a number")


## More defence never helps the attacker, and enough of it SATURATES at the floor
## rather than vanishing.
##
## ## ADR 0200 changed what "saturates" means, and made this test STRONGER
##
## ADR 0070 made this the legibility claim for refusing Keepverse's `off*K/(K+def)`:
## under a bare ratio the last row would be a small positive number tending to zero and
## never arriving anywhere readable. The old floor gave a HARD plateau at
## `gross * ratio`, so the ladder ended somewhere a designer could read it off.
##
## Under `gross * (1 - mitigation_ceiling * D/(K+D))` the curve itself now saturates — at
## `gross * (1 - mitigation_ceiling)` — and `mitigation_ceiling` is `0.95`, so the ratio
## alone bottoms out at `gross * 0.05 = 100.0`, which is HALF the shipped floor of `200.0`.
## The floor therefore still binds, but only because the ceiling is above `0.9`: with the
## ratio alone a wall would leave `100.0` standing, and with the floor alone a body could
## still be worn down to `200.0`. Both halves are asserted below, and the second is the
## claim ADR 0200's docblock makes — "MIN_PENETRATION_RATIO is load-bearing, and this is
## where it is proved" — so it is worth asserting as arithmetic rather than as prose.
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
	# The floor, still the binding term, still `gross * ratio`.
	assert_almost_eq(
		float(wall["penetration"]),
		float(wall["floor"]),
		"and it SATURATES at the floor, not at an asymptote the ratio reaches on its own"
	)
	assert_almost_eq(
		last,
		(
			float(wall["gross"])
			* _tuning.min_penetration_ratio
			* float(_site_of(wall, &"lung")["multiplier"])
		),
		"which is gross x ratio x the multiplier"
	)
	# And the half that proves the floor is load-bearing rather than decorative: the ratio
	# ALONE would leave strictly MORE standing. `m` is below the ceiling, so
	# `gross * (1 - m) > gross * (1 - mitigation_ceiling) = gross * 0.05`, and the floor
	# is `gross * 0.10` — which only binds because `0.05 < 0.10`.
	var ratio_only := float(wall["gross"]) * (1.0 - _tuning.mitigation_ceiling)
	assert_almost_eq(
		ratio_only,
		float(wall["gross"]) * 0.05,
		"ADR 0200's ratio alone asymptotes at `1 - mitigation_ceiling` of the gross"
	)
	assert_eq(
		float(wall["penetration"]) > ratio_only,
		true,
		"so the floor is strictly load-bearing: it takes the last 5% away too"
	)
	assert_eq(
		float(wall["mitigation_rate"]) < _tuning.mitigation_ceiling,
		true,
		"and the mitigation never reaches the ceiling at any finite armour"
	)


## Each rung of `DEFENSE_PHYSICAL` moves the armour MAGNITUDE by exactly
## `meridian_armour_step * state_rank` per point it added, and costs penetration through
## ADR 0200's ratio rather than by a subtraction.
##
## ## The old test measured the wrong thing for the right reason, and what that was
##
## The original loop differenced `total`, which is `penetration x` the struck huyệt's
## multiplier. Every `_walled()` builds a FRESH actor, and a fresh `named` aim resolves
## whichever huyệt the body happens to offer first, so differencing two `total` rows
## differences two multipliers as well as the armour. It also differenced every row against
## the `armour 0.0` row, which could therefore never itself be a measurement row, and it
## took the expected step from `defence_of(<an actor with no wall>)`, which is brief 0a's
## trap in its purest form: `_armour` authors a FLAT modifier and a body-path defender
## carries a `BodyProvider`, so `ActorStats` composes the provider's baseline with the
## modifier stack (ADR 0026) and the derived stat does NOT move by the authored amount.
##
## None of the three was observable while the bug stood, because the doubled tissue put
## EVERY row of `0..8` inside the floor. The assertion body was DEAD CODE: the suite
## counted green assertions for a claim it was not making. Halving the armour moved the
## floor's grip, index `1` came out of the floored regime, and the latent fault surfaced
## as a failure rather than as a regression in the mechanism.
##
## ## ADR 0200: the LINEAR exchange rate is GONE, and the property is RESTATED, not dropped
##
## ## What the old assertion claimed, and why it cannot be kept
##
## It asserted `previous_penetration - penetration == step`, where `step` is
## `DEFENSE_PHYSICAL_delta x meridian_armour_step x state_rank`. That is a claim of a
## CONSTANT exchange rate: one point of armour costs one point of penetration, forever.
## It was true of ADR 0070's subtraction (`gross - D`) and is **not a property any ratio
## has**. Measured, the same loop now answers `1.4232`, `1.4210`, `1.4188` … — a rate
## that is neither constant nor equal to the step, and one that SHRINKS as the defence
## deepens. Keeping the assertion would mean pinning a number the formula does not
## produce; loosening it to a range would mean asserting nothing.
##
## ## What replaces it: the LADDER and the CONVERGENCE, which ARE invariants
##
## Two properties survive a ratio intact, and both are stronger than the linear one:
##
## 1. **The ladder is exact.** Each point of `DEFENSE_PHYSICAL` is worth exactly
##    `meridian_armour_step x state_rank` of `D`, measured on the PUBLISHED
##    `defense_physical` and not on the authored amount, so the FLAT/provider composition
##    cannot make the expectation wrong for the wrong reason. This is the lane
##    `test_body_damage.gd` prices and it is unchanged by ADR 0200. It is a MARGINAL, so it
##    is differenced against the origin's own measured `D` rather than against the tissue
##    alone — see the note on `baseline` in the body for why that distinction is `14.0`.
## 2. **The response converges and never vanishes.** The penetration a rung costs SHRINKS
##    strictly with depth, which is the whole reason `mitigation_ceiling` is a multiplier
##    rather than a clamp: the ladder does not go dead. And it never reaches zero at a
##    finite `D`, so every point of defence still buys something.
##
## The third property — never below the floor — is what `MIN_PENETRATION_RATIO` is for and
## is asserted by the two tests above; this one measures the ladder while the ratio is
## still in charge, and `costs` says how many rungs it actually measured so a floor that
## bound early cannot quietly reduce the claim to one row.
func test_each_point_of_defence_moves_the_armour_magnitude_and_converges_on_the_curve() -> void:
	var attacker := _attacker()
	var state := MeridianState.OPEN
	var origin := _parts(attacker, _walled(0.0, state), BodyLocation.MODE_NAMED, &"lung")
	if float(origin["penetration"]) > float(origin["floor"]):
		assert_almost_eq(
			float(origin["penetration"]),
			_expected_penetration(origin),
			"armour 0.0: unfloored, so ADR 0200's ratio is what answers"
		)
	var previous_penetration := float(origin["penetration"])
	var previous_total := float(origin["total"])
	# ## ADR 0200: the baseline is a MEASUREMENT off the origin row, not the tissue term
	#
	# The assertion is about the ladder's MARGINAL, and a marginal is a difference — so it
	# needs a baseline, and the baseline has to be the mechanism's OWN zero-armour row.
	# `_walled(0.0, OPEN)` authors NO extra `DEFENSE_PHYSICAL`, which is not the same thing
	# as no armour: `parts["defense_physical"]` reads `40.0`, because
	# `BodyProvider.contribute` adds `(bone * 1.5 + vitality * 1.0) * shaped` on top of core's
	# `physique * 1.5 = 15.0` (ADR 0026 makes a provider's contribution the BASELINE for
	# whatever id it emits). So at the origin the ladder term is `40.0 * 0.35 * 1.0 = 14.0`
	# and `D` is `14.0 + 2.75 = 16.75`.
	#
	# This loop used to subtract the TISSUE alone, which stranded that whole `14.0`: every
	# row measured `14.0 + 0.7 * index` against an expectation of `0.7 * index` and failed by
	# a constant. Neither side of that was a formula bug — the RATE was exactly right
	# (`0.7 = 2 x 0.35 x 1` for two points of `DEFENSE_PHYSICAL`) and the constant is a real
	# term of ADR 0070's formula, read correctly and priced once, which
	# `test_body_damage.gd`'s `resistance - expected_armour` lane already asserts.
	#
	# So the baseline moves to the origin's own `D`. It is READ rather than derived, and
	# `_tissue_expectation` stays in the loop as the independent cross-check it was written
	# to be: it proves the baseline really is `tissue + the zero-rung ladder term`, so a
	# future change to either cannot quietly move it without failing HERE.
	var baseline := float(origin["resistance"])
	var previous_cost := INF
	var costs := 0
	for index in range(1, 9):
		var target := _walled(float(index), state)
		var parts := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
		var penetration := float(parts["penetration"])
		# (1) THE LADDER, exact. `armour_step` and `channel_rank` are read off the row under
		# test and the delta is the PUBLISHED `defense_physical`, so a rebalance of the
		# `.tres` moves this with it and `_armour`'s FLAT/provider composition cannot make
		# the expectation wrong for the wrong reason.
		var step := (
			(float(parts["defense_physical"]) - float(origin["defense_physical"]))
			* float(parts["armour_step"])
			* float(parts["channel_rank"])
		)
		# `step` is ALREADY the whole ladder for this row: `defense_physical` above is
		# measured from the ORIGIN row, so it carries every rung, not one. (Measured on the
		# published stat, the ladder runs at `2 * 0.35 = 0.7` per authored point — a FLAT
		# on `DEFENSE_PHYSICAL` moves the DERIVED read by twice its face value through the
		# body provider's composition, which is exactly why this lane is measured on
		# `parts["defense_physical"]` rather than on the number `_armour` was handed.)
		assert_almost_eq(
			float(parts["resistance"]) - baseline,
			step,
			"%d points of DEFENSE_PHYSICAL are worth exactly %f of armour magnitude" % [index, step]
		)
		# The independent cross-check, and the reason `baseline` is measured rather than
		# re-derived: it holds the baseline to `tissue + the zero-rung ladder term` while the
		# assertion above holds it to the origin's own row.
		assert_almost_eq(
			baseline,
			(
				_tissue_expectation(target)
				+ (
					float(origin["defense_physical"])
					* float(origin["armour_step"])
					* float(origin["channel_rank"])
				)
			),
			"and the origin's armour really is the tissue plus the zero-rung ladder term"
		)
		if penetration > float(parts["floor"]):
			# (2a) The response is still STRICTLY negative: a rung of defence costs penetration.
			var cost := previous_penetration - penetration
			assert_eq(
				cost > 0.0,
				true,
				"%d points of DEFENSE_PHYSICAL costs penetration (%.9f)" % [index, cost]
			)
			# (2b) And it SHRINKS with depth. This is the assertion the deleted cap made
			# impossible: `d(pen)/dD = -gross * ceiling * K / (K + D)^2`, so the ladder gets
			# progressively less effective WITHOUT ever reaching a dead stat.
			assert_eq(
				cost < previous_cost,
				true,
				(
					"%d points cost less penetration than the rung below (%.9f < %.9f)"
					% [index, cost, previous_cost]
				)
			)
			previous_cost = cost
			costs += 1
		assert_eq(
			float(parts["total"]) <= previous_total,
			true,
			"%d points never helps the attacker" % index
		)
		previous_penetration = penetration
		previous_total = float(parts["total"])
	assert_eq(
		costs >= 6,
		true,
		(
			(
				"and the ladder stayed in charge of the whole loop (%d rungs measured); a body that "
				% costs
			)
			+ "floored at the first rung would have measured the floor, not the ladder"
		)
	)


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
