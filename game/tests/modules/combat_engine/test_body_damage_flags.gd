extends "res://tests/modules/combat_engine/body_damage_fixture.gd"

## ADR 0070: ONE FLAG, OPPOSITE MEANINGS — the identity of the body path.
##
## ## The two flags
##
## - `Acupoint.blocked` is a LOST INVESTMENT for the cultivator (`AcupointSet.open_count`
##   drops and `average_quality` ignores the point) and simultaneously the BEST AIM POINT
##   for the attacker at `BLOCKED_MULT`. An inversion no other path has.
## - `MeridianState.injured` halves the channel's AGGREGATE bonus for EVERY path
##   through `get_bonus() == 0.5` AND raises the damage taken there through
##   `injured_mult_step`.
##
## "That inversion is the identity of the path", so it is worth its own file: both halves
## of both flags have to be asserted against the SHIPPED body vocabulary (`AcupointSet`,
## `MeridianState`, `MeridianNetwork`) rather than against a boolean the mechanism keeps
## itself, or the claim reduces to "the `.gd` has a field called `blocked`".
##
## The formula, the floor and the subtraction are in `test_body_damage.gd`; aim, wounds
## and degradation are in `test_body_damage_aim.gd` and `test_body_damage_wounds.gd`.

# --- `Acupoint.blocked` --------------------------------------------------------


## ADR 0070's first inversion, both halves on one actor. The SAME `blocked` bool is a
## lost investment for the cultivator AND the best aim point on the channel for the
## attacker.
##
## The cultivator's half is asserted against the real `AcupointSet` methods, so the claim
## is "the shipped body vocabulary excludes a jammed huyệt from its own average" and not
## "a dictionary somewhere says so". The average RISING when the best point is jammed is
## the observable that makes "excluded" true: a set that averaged over every point would
## fall.
func test_a_jammed_huyet_is_a_lost_investment_and_the_best_aim_point() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var points_on_target: AcupointSet = target.component(&"acupoints")
	var points := _points_on(target, &"lung")
	assert_eq(points.size() > 1, true, "the lung really carries several huyệt")
	# Start from a body where one point is strictly the best, so jamming it must both
	# drop the average and hand the attacker a bigger number than it had.
	points[0].quality = 0.9
	points[1].quality = 0.1
	var open_count := points_on_target.open_count()
	var average_before := points_on_target.average_quality()
	var clean := _site_of(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung"), &"lung")
	assert_eq(String(clean["point_id"]), String(points[0].id), "aim found the best point")

	points[0].block()

	# --- the cultivator's half: a lost investment ---
	assert_eq(points_on_target.open_count(), open_count - 1, "open_count dropped by one")
	assert_eq(points_on_target.blocked_count(), 1, "and it is reported as blocked")
	var average_after := points_on_target.average_quality()
	assert_eq(
		average_after < average_before,
		true,
		(
			"average_quality EXCLUDES the jammed point, so it fell: %f -> %f"
			% [average_before, average_after]
		)
	)
	assert_almost_eq(
		average_after,
		(average_before * float(points.size()) - 0.9) / float(points.size() - 1),
		"and it is the mean of exactly the survivors"
	)

	# --- the attacker's half: the best aim point on the channel ---
	var site := _site_of(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung"), &"lung")
	assert_eq(String(site["point_id"]), String(points[0].id), "aim still finds the jammed node")
	assert_almost_eq(float(site["multiplier"]), _tuning.blocked_mult, "at BLOCKED_MULT")
	assert_eq(
		_tuning.blocked_mult > 1.0 + _tuning.point_quality_step,
		true,
		"and BLOCKED_MULT exceeds even a maximum-quality point, so a jam can be found"
	)
	# A jam is worth MORE here than the quality term ever is, at any authored quality.
	assert_eq(
		float(site["multiplier"]) > 1.0 + _tuning.point_quality_step,
		true,
		"the flag outranks a full point of quality -- which is the inversion"
	)


## The jam is decided by the FLAG, not by the quality behind it: jamming a huyệt whose
## quality is `0.0` still raises the multiplier above a max-quality open one, and
## clearing the jam restores the quality term exactly.
##
## `random` aim can therefore answer "it found the jammed Lung node", which is the read
## ADR 0070 says a player is owed, and this is the assertion that makes that claim
## mechanical rather than decorative.
func test_the_jam_not_the_quality_is_what_makes_a_point_the_best_aim() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	var points := _points_on(target, &"lung")
	points[0].quality = 1.0
	points[1].quality = 0.0

	var clean := _site_of(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung"), &"lung")
	assert_eq(String(clean["point_id"]), String(points[0].id), "a max-quality point is the best")
	assert_almost_eq(
		float(clean["multiplier"]), 1.0 + _tuning.point_quality_step, "at 1 + quality_step"
	)

	points[1].block()
	var jammed := _site_of(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung"), &"lung")
	assert_eq(
		String(jammed["point_id"]),
		String(points[1].id),
		"a jammed ZERO-quality point outranks a max-quality open one"
	)
	assert_almost_eq(float(jammed["multiplier"]), _tuning.blocked_mult, "at BLOCKED_MULT")
	assert_eq(
		float(jammed["multiplier"]) > float(clean["multiplier"]),
		true,
		"so the flag, not the quality, is the better aim point"
	)

	# Clearing the jam is the ONLY way back — decay does not repair (ADR 0070).
	points[1].clear_block()
	var cleared := _site_of(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung"), &"lung")
	assert_eq(String(cleared["point_id"]), String(points[0].id), "the max-quality point answers")
	assert_almost_eq(
		float(cleared["multiplier"]),
		1.0 + _tuning.point_quality_step,
		"and the quality term is exactly where it was"
	)


## The quality term is clamped into `[0, 1]` on read, so a hand-edited acupoint can never
## be BOTH the best aim point and a damage REDUCER — the sign rule S9's one flip depends
## on, and the one way a `.tres` edit could turn an advantage into a liability.
func test_a_hand_edited_quality_can_neither_reduce_a_hit_nor_exceed_the_share() -> void:
	var attacker := _attacker()
	for quality in [-5.0, -0.001, 0.0, 0.5, 1.0, 4.0, 1.0e9, INF, NAN]:
		var target := _defender(["lung"], {"lung": MeridianState.OPEN})
		_points_on(target, &"lung")[0].quality = quality
		var parts := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
		var site := _site_of(parts, &"lung")
		var label := "quality %s" % str(quality)
		assert_eq(float(site["multiplier"]) >= 1.0, true, label + ": never a reducer")
		assert_eq(
			float(site["multiplier"]) <= 1.0 + _tuning.point_quality_step,
			true,
			label + ": never above the authored step"
		)
		assert_eq(is_finite(float(parts["total"])), true, label + ": and the hit is a number")
		assert_eq(float(parts["total"]) >= 0.0, true, label + ": and non-negative")


## `BLOCKED_MULT` below 1.0 would INVERT the identity of a lost investment: a point the
## cultivator lost would become a place that takes less damage, so a jam would be an
## upgrade. Clamped non-negative on read, and asserted as the relational claim — "a jam
## is never worse than the point it replaced" — rather than as a restated constant.
func test_a_blocked_multiplier_below_one_never_turns_a_lost_investment_into_a_shield() -> void:
	var attacker := _attacker()
	for value in [0.0, 0.25, 0.99, -3.0]:
		var target := _defender(["lung"], {"lung": MeridianState.OPEN})
		_points_on(target, &"lung")[0].block()
		var mech := BodyDamage.new()
		mech.tuning = _shipped_with(&"blocked_mult", value)
		var parts := mech.breakdown(
			_context(attacker, target, _technique(100.0, &"lung"), BodyLocation.MODE_NAMED)
		)
		var clean := mech.breakdown(
			_context(
				attacker, _defender(["lung"]), _technique(100.0, &"lung"), BodyLocation.MODE_NAMED
			)
		)
		assert_almost_eq(
			float(_site_of(parts, &"lung")["multiplier"]),
			maxf(0.0, value),
			"BLOCKED_MULT %s is clamped non-negative" % str(value)
		)
		assert_eq(
			float(parts["total"]) >= float(clean["total"]),
			true,
			"BLOCKED_MULT %s never makes a jammed point safer than an open one" % str(value)
		)
	# The shipped value is on the right side of the identity, and the shipped point
	# quality step is on the right side too — `random` aim can only "find the jam" if
	# BLOCKED_MULT outranks `1 + point_quality_step`, which the tuning documents.
	assert_eq(
		_tuning.blocked_mult > 1.0 + _tuning.point_quality_step,
		true,
		"the shipped BLOCKED_MULT outranks a maximum-quality point"
	)


## Necrosis JAMS a point rather than damaging one, so the flag the attacker reads is the
## flag the ledger writes. Asserted through the two together so a jam written by a
## different code path than the one `random` aim reads would be visible.
func test_a_jam_written_anywhere_is_the_jam_a_random_aim_finds() -> void:
	var attacker := _attacker()
	var target := _defender([], {})
	var points := _points_on(target, &"lung")
	points[0].block()
	# `random` over the whole body now lands on the lung, because the jam outranks every
	# other channel's site.
	var parts := _parts(attacker, target, BodyLocation.MODE_RANDOM)
	assert_eq(
		String(parts["sites"][0]["meridian_id"]),
		"lung",
		"a random aim finds the jammed channel, whichever channel it is on"
	)
	assert_almost_eq(
		float(parts["sites"][0]["multiplier"]),
		_tuning.blocked_mult,
		"and strikes it at BLOCKED_MULT"
	)


# --- `MeridianState.injured` ---------------------------------------------------


## ADR 0070's second inversion, on ONE `MeridianState` object so the pair cannot be
## satisfied by two different flags:
##
## - halves the channel's AGGREGATE bonus for EVERY path (`get_bonus() == 0.5`), which is
##   what a wound is FOR; and
## - RAISES the damage taken there, by `injured_mult_step` on the channel multiplier.
##
## The damage figure is re-derived rather than compared for "greater", so the claim is
## that the INJURED STEP and nothing else moved the channel multiplier — the whole
## channel multiplier is read back off the site row and divided out.
func test_injured_halves_the_aggregate_bonus_and_raises_the_damage_taken_there() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.EXPANDED})
	var channel := target.meridians.get_meridian(&"lung")
	assert_eq(channel.get_bonus(), 1.0, "an uninjured channel pays its full bonus")
	var before := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
	var before_site := _site_of(before, &"lung")
	assert_almost_eq(
		float(before_site["channel_multiplier"]),
		1.0 + _tuning.channel_mult_step * float(channel.state_rank()),
		"and the channel multiplier is 1 + step x rank"
	)

	# The EXISTING core verb, which is what `BodyWounds` calls at WOUND_THRESHOLD.
	target.meridians.damage_meridian(&"lung")
	assert_eq(channel.injured, true, "the flag is set")
	assert_eq(channel.get_bonus(), 0.5, "and the aggregate bonus is halved for EVERY path")
	assert_eq(channel.state_rank(), MeridianState.EXPANDED, "the structural state survives")
	var after := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
	var after_site := _site_of(after, &"lung")

	assert_almost_eq(
		float(after_site["channel_multiplier"]),
		float(before_site["channel_multiplier"]) + _tuning.injured_mult_step,
		"and the channel multiplier rose by exactly injured_mult_step"
	)
	assert_almost_eq(
		float(after_site["point_multiplier"]),
		float(before_site["point_multiplier"]),
		"while the POINT multiplier did not move at all"
	)
	assert_almost_eq(
		float(after["total"]) / float(before["total"]),
		float(after_site["channel_multiplier"]) / float(before_site["channel_multiplier"]),
		"so the damage rose by exactly the channel multiplier's share"
	)
	assert_eq(float(after["total"]) > float(before["total"]), true, "damage taken ROSE")
	assert_almost_eq(float(after["gross"]), float(before["gross"]), "against the same attacker")

	# The penalty and the reward are the SAME flag, so repairing removes both — which is
	# why ADR 0070 routes the repair through the ADR 0031 recovery item rather than
	# letting decay undo it.
	target.meridians.repair_meridian(&"lung")
	assert_eq(channel.get_bonus(), 1.0, "the repair restores the bonus")
	assert_almost_eq(
		float(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")["total"]),
		float(before["total"]),
		"and the multiplier with it"
	)


## Injury does not change the ARMOUR: `damage_meridian` preserves `state_rank`, and ADR
## 0070 prices armour by the RANK. So injury is purely a multiplier on the attacker's
## side here, which is what makes it a clean inversion rather than a second defence dial
## wearing one.
func test_injury_preserves_the_rank_and_therefore_the_armour() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.STRENGTHENED})
	var parts := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
	target.meridians.damage_meridian(&"lung")
	var injured := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
	assert_almost_eq(float(injured["resistance"]), float(parts["resistance"]), "armour unchanged")
	assert_almost_eq(
		float(injured["penetration"]), float(parts["penetration"]), "so the penetration is"
	)
	assert_almost_eq(
		float(injured["channel_rank"]), float(parts["channel_rank"]), "and the reported rank is"
	)
	assert_eq(float(injured["total"]) > float(parts["total"]), true, "only the multiplier moved")


## `injured_mult_step` is a MULTIPLIER STEP, so a negative authored value would make an
## injured channel a place that takes LESS — the same inversion failure `blocked_mult`
## would suffer. Clamped non-negative on read, and asserted relationally.
func test_a_negative_injured_multiplier_never_makes_an_injury_a_refuge() -> void:
	var attacker := _attacker()
	for value in [0.0, -0.5, -10.0]:
		var target := _defender(["lung"], {"lung": MeridianState.EXPANDED})
		target.meridians.damage_meridian(&"lung")
		var mech := BodyDamage.new()
		mech.tuning = _shipped_with(&"injured_mult_step", value)
		var parts := mech.breakdown(
			_context(attacker, target, _technique(100.0, &"lung"), BodyLocation.MODE_NAMED)
		)
		var site := _site_of(parts, &"lung")
		assert_almost_eq(
			float(site["channel_multiplier"]),
			1.0 + _tuning.channel_mult_step * MeridianState.STATE_ORDER[MeridianState.EXPANDED],
			"injured_mult_step %s contributes NOTHING to the multiplier" % str(value)
		)
		assert_eq(
			float(site["multiplier"]) >= 1.0,
			true,
			"injured_mult_step %s never drops a channel below the neutral" % str(value)
		)
	# The shipped value raises the multiplier, which is the property the step exists for.
	assert_eq(_tuning.injured_mult_step > 0.0, true, "the shipped step is a real reward")


## Training a channel makes it a BIGGER target as well as a harder one —
## `channel_mult_step` is deliberately the other side of `meridian_armour_step` and not
## the same sign. So a fully trained channel takes more damage than an untrained one at
## the same floor, which is the decision a body build actually makes.
func test_training_a_channel_makes_it_a_bigger_target_and_a_harder_one() -> void:
	var attacker := _attacker()
	var previous := 0.0
	for state in [MeridianState.OPEN, MeridianState.EXPANDED, MeridianState.STRENGTHENED]:
		var parts := _parts(
			attacker, _defender(["lung"], {"lung": state}), BodyLocation.MODE_NAMED, &"lung"
		)
		var site := _site_of(parts, &"lung")
		var rank := float(target_rank(state))
		assert_almost_eq(
			float(site["channel_multiplier"]),
			1.0 + _tuning.channel_mult_step * rank,
			"%s: the multiplier is 1 + step x rank" % String(state)
		)
		assert_almost_eq(
			float(parts["resistance"]),
			(
				float(parts["defense_physical"]) * _tuning.meridian_armour_step * rank
				+ float(parts["tissue"])
			),
			"%s: and the armour is defence x step x rank, plus tissue" % String(state)
		)
		assert_eq(
			float(site["multiplier"]) >= previous,
			true,
			"%s: a trained channel is a bigger target" % String(state)
		)
		previous = float(site["multiplier"])


# --- helpers -------------------------------------------------------------------


## `MeridianState.STATE_ORDER` read through core's own table, never a copy pasted into
## this suite — a test that restated the four ranks would keep passing if core renumbered
## them, and would then be asserting a mechanism that no longer exists.
func target_rank(state: StringName) -> int:
	return int(MeridianState.STATE_ORDER.get(state, 0))


## A copy of the SHIPPED tuning with one field replaced — so an out-of-range case is "the
## shipped balance with one author mistake" rather than a bare `CombatTuning.new()` whose
## every bound is `0.0` and which would let the assertion pass for the wrong reason.
func _shipped_with(field: StringName, value: float) -> CombatTuning:
	var copy := CombatTuning.shipped()
	copy.set(field, value)
	return copy
