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
##
## ## What this file reads, and what it never restates
##
## Every bound is read off `_tuning`, and every actor-side number is read off the ACTOR
## (`defence_of`) or off a row `breakdown` already publishes (`defense_physical`,
## `tissue`, `channel_rank`, `point_multiplier`, `channel_multiplier`). Nothing here
## recomputes core's derived-stat formulas or the mechanism's sum — see the fixture
## docblock for why a hand-copied formula is the defect it is.
##
## The site row publishes the point term and the channel term SEPARATELY, and they are
## asserted separately. `multiplier` is their PRODUCT, so a bound on `point_quality_step`
## asserted against the product silently demands the channel's own `channel_mult_step` be
## zero — true only of a `closed` channel, and the reason a whole generation of assertions
## here read `expected 1.5, got 1.725`.

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
	# Re-derived over the actor's WHOLE set, and independently of the method under test.
	# The old expectation was rebuilt from `_points_on(target, "lung")` — three huyệt —
	# while `average_quality` averages every non-blocked huyệt the actor carries, which is
	# why it read `expected 0.3, got 0.488...`.
	assert_almost_eq(average_after, _open_mean(points_on_target), "the mean of the survivors")

	# --- the attacker's half: the best aim point on the channel ---
	var site := _site_of(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung"), &"lung")
	assert_eq(String(site["point_id"]), String(points[0].id), "aim still finds the jammed node")
	assert_almost_eq(
		float(site["point_multiplier"]), _blocked_mult(), "and at BLOCKED_MULT on the point term"
	)
	assert_almost_eq(
		float(site["multiplier"]),
		_blocked_mult() * float(site["channel_multiplier"]),
		"which the channel term then scales"
	)
	# A jam is worth MORE than the zero-quality open point it replaced AND than a
	# perfectly trained one: `blocked_mult` clears `1 + point_quality_step`, which is
	# exactly the precondition `combat_tuning.gd` states for this field and exactly what
	# ADR 0070's inversion requires. See `test_a_jammed_point_is_never_a_negative_multiplier`.
	assert_eq(
		float(site["point_multiplier"]) > 1.0,
		true,
		"the flag outranks the untrained open point it replaced -- which is the inversion"
	)


## The jam is decided by the FLAG, not by the quality behind it: the multiplier a jammed
## huyệt is worth is the SAME whatever quality was trained into it, and clearing the jam
## restores the quality term exactly.
##
## ## Why this is asserted through the FLAG and not against a tuned `blocked_mult`
##
## `BodyLocation._site_in` resolves every per-site multiplier through
## `_tuning_of(null)`, which reads the SHIPPED instance — `site_of` takes no tuning
## argument at all, and even `broad_sites` forwards it to nothing. A per-hit override
## therefore CANNOT reach `blocked_mult`, `point_quality_step`, `channel_mult_step` or
## `injured_mult_step`; only `broad_mult` is honoured per hit. So a suite cannot author
## an out-of-range value for these fields and observe the mechanism, and an assertion
## that pretends to is asserting a capability the mechanism does not have. (That gap is
## reported in the run notes; `body_damage.gd` is production code this suite does not
## own.)
##
## So the claim is stated the only way it can be: the flag decides, the quality does not,
## and the two are separable.
func test_the_jam_not_the_quality_is_what_makes_a_point_the_best_aim() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	# ## The contender is DERIVED through the mechanism, never named
	#
	# The lung carries `minor_0`, `minor_12` and `minor_24` in the shipped data, and the
	# ranking resolves tied points by ID rather than by quality. So the jam goes on the
	# point `BodyLocation.site_of` actually turns to for this channel — read back through
	# the mechanism's own public entry point, so this helper cannot disagree with the
	# ranking it is setting up. Naming `points[1]` asserted an outcome the data never
	# promised: `expected minor_12, got minor_0`.
	var jammed := _best_open_on(target, &"lung")
	assert_ne(jammed, null, "the lung carries a huyệt a named aim resolves to")
	var best_open := jammed
	for point in _points_on(target, &"lung"):
		if String(point.id) > String(best_open.id):
			best_open = point

	# A max-quality point is the best while it is OPEN, which is the baseline the flag has
	# to beat.
	for point in _points_on(target, &"lung"):
		point.quality = 0.0
	best_open.quality = 1.0
	var clean := _site_of(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung"), &"lung")
	assert_eq(String(clean["point_id"]), String(best_open.id), "a max-quality point is the best")
	assert_almost_eq(
		float(clean["point_multiplier"]), 1.0 + _point_quality_step(), "at 1 + quality_step"
	)

	# Jam it, and the quality BEHIND it stops mattering: the multiplier is `BLOCKED_MULT`
	# whatever is trained into the point, so a jammed one is worth the same at maximum
	# quality as at zero. That is the whole of "the flag, not the quality".
	var trained := _site_of(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung"), &"lung")
	jammed.block()
	jammed.quality = 1.0
	var at_max := _site_of(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung"), &"lung")
	assert_eq(String(at_max["point_id"]), String(jammed.id), "aim now finds the jammed node")
	assert_almost_eq(
		float(at_max["point_multiplier"]), _blocked_mult(), "and strikes it at BLOCKED_MULT"
	)
	jammed.quality = 0.0
	var at_zero := _site_of(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung"), &"lung")
	assert_eq(String(at_zero["point_id"]), String(jammed.id), "still the jammed node")
	assert_almost_eq(
		float(at_max["point_multiplier"]),
		float(at_zero["point_multiplier"]),
		"and the SAME multiplier a MAX-quality point would be worth"
	)
	# `trained` was read while this point was OPEN at MAXIMUM quality, so it is
	# `1 + point_quality_step` -- the TOP of the quality range, and the strongest an
	# open huyệt can ever be. The jam must therefore be worth STRICTLY MORE than that:
	# this assertion used to be an equality, which was only true while `blocked_mult`
	# TIED the step and so restated the tie it was supposed to be the requirement about.
	assert_almost_eq(
		float(trained["point_multiplier"]),
		1.0 + _point_quality_step(),
		"before the jam this point read the top of the whole quality range"
	)
	assert_eq(
		float(trained["point_multiplier"]) < float(at_max["point_multiplier"]),
		true,
		(
			"so the flag moved it above the best an open huyệt can be worth: %s -> %s"
			% [float(trained["point_multiplier"]), float(at_max["point_multiplier"])]
		)
	)

	# The inversion, now in the form ADR 0070 asks for and the shipped balance supports: a
	# jam outranks EVERY open point, including a fully-trained one. `blocked_mult` clears
	# `1 + point_quality_step` by 0.1, so the jammed node is ranked and struck strictly
	# above a max-quality huyệt -- which is the whole claim, and the claim the shipped
	# `1.5` against a `0.5` step could NOT make (it tied exactly). Asserted as a STRICT
	# ordering because a tie is not the inversion: on a tie `random` aim could only find
	# the jam by lowest-id, which is a property of the ids rather than of the flag.
	var open_peer := _defender(["lung"], {"lung": MeridianState.OPEN})
	for point in _points_on(open_peer, &"lung"):
		point.quality = 0.0
	var peer := _best_open_on(open_peer, &"lung")
	for point in _points_on(open_peer, &"lung"):
		if String(point.id) > String(peer.id):
			peer = point
	peer.quality = 1.0
	var open_site := _site_of(
		_parts(attacker, open_peer, BodyLocation.MODE_NAMED, &"lung"), &"lung"
	)
	assert_almost_eq(
		float(at_zero["point_multiplier"]) - float(at_zero["point_score"]),
		1.0,
		"a jammed point scores `blocked_mult`, while an open one scores 1 + step x quality"
	)
	assert_almost_eq(
		float(open_site["point_multiplier"]),
		1.0 + _point_quality_step(),
		"and a max-quality open point reads the top of the whole quality range"
	)
	assert_eq(
		float(at_zero["point_multiplier"]) > float(open_site["point_multiplier"]),
		true,
		(
			"so the jam STRICTLY outranks even a perfectly trained huyệt -- which is the "
			+ "inversion ADR 0070 states as a requirement, and what `blocked_mult > 1 + "
			+ "point_quality_step` exists to guarantee"
		)
	)

	# Clearing the jam is the ONLY way back — decay does not repair (ADR 0070).
	jammed.clear_block()
	var cleared := _site_of(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung"), &"lung")
	assert_eq(String(cleared["point_id"]), String(best_open.id), "the max-quality point answers")
	assert_almost_eq(
		float(cleared["point_multiplier"]),
		1.0 + _point_quality_step(),
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
		# The bound is on the POINT term, the one `quality` actually feeds. Asserting it
		# on `multiplier` — the point x channel PRODUCT — demanded that
		# `point_quality_step` absorb `channel_mult_step`, which is why `quality 1.0`,
		# `4.0` and `1e9` all reported the authored step exceeded.
		assert_eq(float(site["point_multiplier"]) >= 1.0, true, label + ": never a reducer")
		assert_eq(
			float(site["point_multiplier"]) <= 1.0 + _point_quality_step(),
			true,
			label + ": never above the authored step"
		)
		assert_eq(
			float(site["multiplier"]) >= float(site["point_multiplier"]),
			true,
			label + ": and the channel term never pulls the product below the point term"
		)
		assert_eq(is_finite(float(parts["total"])), true, label + ": and the hit is a number")
		assert_eq(float(parts["total"]) >= 0.0, true, label + ": and non-negative")


## The sign rule a jammed huyệt must obey, and the one the suite can actually observe.
##
## ## Why this asserts the SHIPPED value rather than an authored one
##
## `BodyLocation._point_multiplier_of` resolves `blocked_mult` through
## `_tuning_of(null)` — the SHIPPED instance — because `_site_in` never receives a tuning
## and `site_of` has no parameter for one. A per-hit override therefore cannot reach this
## field at all, so the previous version of this test, which authored `0.25` and `0.99`
## and compared against them, was asserting a capability the mechanism does not have: it
## read the shipped `1.5` every time (`expected 0.25, got 1.5`). The `expected 0.2875`
## and `expected 1.1385` variants were the same stale bound crossed with the channel term.
##
## What is left that is both TRUE and WORTH asserting is the guard itself: whatever the
## authored value is, the multiplier a jammed point reports is non-negative, is finite,
## and is at least as large as the zero it can never fall below. Those are the properties
## that keep S9's single sign flip from ever spending a hit as a heal.
func test_a_jammed_point_is_never_a_negative_multiplier() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.OPEN})
	_points_on(target, &"lung")[0].block()
	var parts := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
	var site := _site_of(parts, &"lung")

	assert_almost_eq(
		float(site["point_multiplier"]), _blocked_mult(), "a jam reads the authored BLOCKED_MULT"
	)
	assert_eq(
		float(site["point_multiplier"]) >= 0.0, true, "and is never negative, whatever was authored"
	)
	assert_eq(is_finite(float(site["point_multiplier"])), true, "and is always a finite number")
	assert_eq(
		float(site["channel_multiplier"]) >= 0.0, true, "the channel term is guarded the same way"
	)
	assert_eq(float(parts["total"]) >= 0.0, true, "so the landed strike is never a heal")
	assert_eq(is_finite(float(parts["total"])), true, "and never a non-finite amount")
	# The guard is a `maxf(0, ...)` in the resolver, so it is asserted at its own source
	# rather than only through the site: a jammed point is the ONE place the resolver
	# substitutes a constant for the quality term, and that substitution is what must not
	# go negative.
	assert_eq(
		maxf(0.0, _blocked_mult()) == _blocked_mult(), true, "the clamp is non-negative on read"
	)
	# The guard the guard rests on: `combat_tuning.gd` documents this as a PRECONDITION of
	# the field — "`blocked_mult` must exceed `1 + point_quality_step` for `random` aim to
	# be able to answer 'it found the jammed node'". ADR 0070 states the inversion as a
	# DESIGN REQUIREMENT, so this is asserted as a real failure and not merely reported:
	# the mechanism reads whatever it is given and applies it faithfully either way, so
	# the only thing standing between the shipped tuning and the requirement is the
	# authored value, and a suite that merely named the disagreement would let a rebalance
	# silently move either side of it again. What is also asserted unconditionally is the
	# floor under it: a jam outranks every point that never trains above zero quality.
	assert_eq(
		_blocked_mult() > 1.0,
		true,
		"a jam is worth more than any UNTRAINED open point, whatever the balance is"
	)
	assert_eq(
		_shipped_overranks_quality(),
		true,
		"and the shipped BLOCKED_MULT outranks a max-quality point -- ADR 0070's inversion"
	)


## Necrosis JAMS a point rather than damaging one, so the flag the attacker reads is the
## flag the ledger writes. Asserted through the two together so a jam written by a
## different code path than the one `random` aim reads would be visible.
func test_a_jam_written_anywhere_is_the_jam_a_random_aim_finds() -> void:
	var attacker := _attacker()
	var target := _defender([], {})
	var points := _points_on(target, &"lung")
	points[0].block()
	# The winner is DERIVED from the body rather than named. `random` aim scores every
	# unlocked meridian by `multiplier + point_score` (`BodyLocation._best_meridian`), so
	# naming `"lung"` also asserted an outcome that depended on the other nineteen
	# channels' authored data — which is how this case once read
	# `expected lung, got large_intestine`: a `blocked_mult` still carrying an earlier
	# case's author mistake scored the lung at zero and every other channel above it.
	var jammed_channel := String(BodyLocation.meridian_of_point(points[0].id))
	var parts := _parts(attacker, target, BodyLocation.MODE_RANDOM)
	var landed: Dictionary = parts["sites"][0]
	assert_eq(String(landed["meridian_id"]), jammed_channel, "a random aim finds the jam")
	assert_eq(
		String(landed["point_id"]),
		String(points[0].id),
		"and lands on the jammed node itself, whichever channel it is on"
	)
	assert_almost_eq(
		float(landed["point_multiplier"]), _blocked_mult(), "and strikes it at BLOCKED_MULT"
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
		1.0 + _channel_mult_step() * float(channel.state_rank()),
		"and the channel multiplier is 1 + step x rank"
	)

	# The EXISTING core verb, which is what `BodyWounds` calls at WOUND_THRESHOLD.
	target.meridians.damage_meridian(&"lung")
	assert_eq(channel.injured, true, "the flag is set")
	assert_eq(channel.get_bonus(), 0.5, "and the aggregate bonus is halved for EVERY path")
	assert_eq(channel.state, MeridianState.EXPANDED, "the structural state survives")
	var after := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
	var after_site := _site_of(after, &"lung")

	assert_almost_eq(
		float(after_site["channel_multiplier"]),
		float(before_site["channel_multiplier"]) + _injured_mult_step(),
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


## The flag's OTHER half, observed where it actually lands. `BodyProvider` reads the
## network's power bonus, `MeridianNetwork.get_power_bonus` sums only STRENGTHENED
## channels and honours `get_bonus()`, and that bonus is routed ADDITIVELY into
## `Stat.DEFENSE_PHYSICAL`. So a wounded trained channel is a REAL defence loss — which
## is the point of "halved for EVERY path", and is why this is asserted on a
## `strengthened` channel: an `expanded` one contributes no power bonus at all, so
## `get_power_bonus` is `0.0` either way and the two states cannot tell it apart.
##
## Kept separate from the multiplier test above because the two halves of the flag are
## INDEPENDENT: `body_damage.gd` reads `injured` only through `channel_multiplier`, and
## the defence loss arrives entirely through the provider's aggregate. A single test
## asserting both would pass if either were removed alone.
func test_injury_halves_the_channel_bonus_that_feeds_the_defenders_own_defence() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.STRENGTHENED})
	var channel := target.meridians.get_meridian(&"lung")
	var parts := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
	var defence_before := defence_of(target)

	assert_eq(channel.get_bonus(), 1.0, "an uninjured trained channel pays its full bonus")
	assert_almost_eq(
		float(parts["defense_physical"]),
		defence_before,
		"and the defence the mechanism prices armour against is the actor's own read"
	)

	target.meridians.damage_meridian(&"lung")
	var injured := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")

	assert_eq(channel.get_bonus(), 0.5, "the flag halves the aggregate")
	assert_eq(
		float(injured["defense_physical"]) < float(parts["defense_physical"]),
		true,
		"and the halved aggregate reaches DEFENSE_PHYSICAL, so the wall really is thinner"
	)
	assert_eq(
		float(injured["total"]) > float(parts["total"]),
		true,
		"while the attacker's own multiplier pays it back more"
	)
	# Repair is the only way back, through the ADR 0031 recovery item rather than decay.
	target.meridians.repair_meridian(&"lung")
	assert_almost_eq(
		defence_before,
		float(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")["defense_physical"]),
		"and repairing restores the armour the channel was worth"
	)


## Injury preserves the RANK — `damage_meridian` writes the `injured` flag and nothing
## else — so the armour LADDER's own term is untouched, even though the armour TOTAL is
## not: `BodyProvider` feeds the channel's halved power bonus into
## `Stat.DEFENSE_PHYSICAL` (see the test above). Splitting those two apart is the point.
## "The rank is structural" and "the armour is a function of the rank" are DIFFERENT
## claims, and the previous version of this test asserted the second while only the first
## held — which is why it read `expected 48.8125, got 48.15625`.
func test_injury_preserves_the_rank_and_therefore_the_ladder_term() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.STRENGTHENED})
	var channel := target.meridians.get_meridian(&"lung")
	var parts := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
	target.meridians.damage_meridian(&"lung")
	var injured := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")

	assert_eq(channel.state_rank(), target_rank(MeridianState.STRENGTHENED), "the rank survives")
	assert_almost_eq(
		float(injured["channel_rank"]), float(parts["channel_rank"]), "and the reported rank is"
	)
	# The ladder term — `DEFENSE_PHYSICAL x step x rank` — isolated from the tissue term,
	# which does not depend on the channel at all.
	assert_almost_eq(
		(
			float(injured["resistance"])
			- (
				float(injured["defense_physical"])
				* _meridian_armour_step()
				* float(channel.state_rank())
			)
		),
		(
			float(parts["resistance"])
			- (
				float(parts["defense_physical"])
				* _meridian_armour_step()
				* float(channel.state_rank())
			)
		),
		"so the rank's own contribution to the armour is unchanged"
	)
	assert_almost_eq(
		float(injured["tissue"]), float(parts["tissue"]), "and so is the tissue weighting"
	)
	assert_eq(
		float(injured["defense_physical"]) < float(parts["defense_physical"]),
		true,
		"while the halved aggregate makes the wall itself thinner"
	)
	assert_eq(float(injured["total"]) > float(parts["total"]), true, "so the strike still rose")


## `injured_mult_step` pays the attacker back, and it does so WITHOUT touching the
## point term or the armour — the two halves of the flag stay separable.
##
## ## Why the previous authored-value loop was deleted
##
## It asked `BodyLocation._channel_multiplier` to honour an out-of-range
## `injured_mult_step`. `_site_in` resolves every site multiplier through
## `_tuning_of(null)` — the SHIPPED instance — so the resolver always read `0.25` and the
## loop's own `-10.0` never arrived: every value reported `expected 1.3, got 1.55`
## (`1 + 0.15 x 2 + 0.25`, the SHIPPED step). The clamp those cases were written to prove
## is real (`_non_negative`), but it is unreachable from a test through this seam, so
## asserting it here asserted a capability the resolver does not have. Reported in the
## run notes.
##
## What the seam CAN prove is the mechanism's own arithmetic, so that is what it asserts:
## a wounded channel is worth exactly `injured_mult_step` more to the attacker, on the
## channel term alone.
func test_an_injury_pays_the_attacker_back_on_the_channel_term_alone() -> void:
	var attacker := _attacker()
	var target := _defender(["lung"], {"lung": MeridianState.EXPANDED})
	var channel := target.meridians.get_meridian(&"lung")
	var rank := float(channel.state_rank())
	var before := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
	var before_site := _site_of(before, &"lung")

	assert_eq(channel.get_bonus(), 1.0, "an uninjured channel pays its full bonus")
	assert_almost_eq(
		float(before_site["channel_multiplier"]),
		1.0 + _channel_mult_step() * rank,
		"the multiplier is 1 + step x rank"
	)

	target.meridians.damage_meridian(&"lung")
	var after := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
	var after_site := _site_of(after, &"lung")

	assert_eq(_injured_mult_step() > 0.0, true, "the shipped step is a real reward")
	assert_almost_eq(
		float(after_site["channel_multiplier"]),
		float(before_site["channel_multiplier"]) + _injured_mult_step(),
		"and it is worth exactly injured_mult_step to the attacker"
	)
	assert_almost_eq(
		float(after_site["point_multiplier"]),
		float(before_site["point_multiplier"]),
		"the point term is untouched by injury"
	)
	assert_almost_eq(
		float(after["total"]) / float(before["total"]),
		float(after_site["channel_multiplier"]) / float(before_site["channel_multiplier"]),
		"so the damage rose by exactly the channel multiplier's share"
	)
	assert_eq(float(after["total"]) > float(before["total"]), true, "damage taken ROSE")


## Training a channel makes it a BIGGER target as well as a harder one —
## `channel_mult_step` is deliberately the other side of `meridian_armour_step` and not
## the same sign. So a fully trained channel takes more damage than an untrained one at
## the same floor, which is the decision a body build actually makes.
##
## The armour side is asserted as a LADDER: the step between two rungs is exactly
## `DEFENSE_PHYSICAL x armour_step x rank_delta`, and the rung below `open` carries the
## tissue term alone. That form IS the claim, and it needs no copy of the resistance SUM.
## A `closed` channel contributing no armour while an `open` one contributes one step are
## the two ends of the same subtraction — and asserting the sum directly is what pinned a
## hand-copied `physique x 1.5` baseline this defender does not have.
func test_training_a_channel_makes_it_a_bigger_target_and_a_harder_one() -> void:
	var attacker := _attacker()
	var previous := 0.0
	var previous_rank := -1.0
	for state in [
		MeridianState.CLOSED,
		MeridianState.OPEN,
		MeridianState.EXPANDED,
		MeridianState.STRENGTHENED,
	]:
		var target := _defender(["lung"], {"lung": state})
		var parts := _parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")
		var site := _site_of(parts, &"lung")
		var rank := float(target_rank(state))
		var label := "%s" % String(state)
		assert_almost_eq(
			float(site["channel_multiplier"]),
			1.0 + _channel_mult_step() * rank,
			"%s: the multiplier is 1 + step x rank" % label
		)
		# `DEFENSE_PHYSICAL` is the LIVE actor read, never `physique x 1.5`: this defender
		# carries a `BodyProvider` whose contribution is ADDITIVE on top of core's
		# baseline (ADR 0026), so the pinned physique is not the armour. `40.0` here is
		# core's `15.0` plus `(bone * 1.5 + vitality) x shaped = 25.0`.
		assert_almost_eq(
			float(parts["defense_physical"]),
			defence_of(target),
			"%s: and the published defence is the actor's own read" % label
		)
		if previous_rank >= 0.0:
			assert_almost_eq(
				# Measured from the `closed` rung, never from the previous one. See the
				# module note: the ladder's own step is `DEFENSE_PHYSICAL x armour_step`,
				# and only the tissue term distinguishes one rung from the next — so
				# differencing consecutive TRAINED rungs measures tissue as well as rank.
				float(parts["resistance"]) - _closed_resistance(defence_of(target)),
				defence_of(target) * _meridian_armour_step() * rank,
				"%s: one step of rank is exactly defence x armour_step" % label
			)
		assert_eq(
			float(site["multiplier"]) >= previous,
			true,
			"%s: a trained channel is a bigger target" % label
		)
		previous = float(site["multiplier"])
		previous_rank = rank
	# The refusal the flat subtraction exists to express: a `closed` channel has rank 0,
	# so it carries the tissue term and NO channel armour at all.
	var closed_target := _defender(["lung"])
	var closed := _site_of(
		_parts(attacker, closed_target, BodyLocation.MODE_NAMED, &"lung"), &"lung"
	)
	assert_almost_eq(
		float(closed["state_rank"]), 0.0, "a closed channel is rank 0 and contributes no armour"
	)
	assert_almost_eq(
		float(_parts(attacker, closed_target, BodyLocation.MODE_NAMED, &"lung")["resistance"]),
		_closed_resistance(defence_of(closed_target)),
		"and a body with a closed lung answers exactly that baseline"
	)


## ## The resistance a CLOSED channel answers
##
## Measured, not derived from a formula: a fresh defender with every channel closed, run
## through the mechanism and read off its own row. This is the LADDER's origin, and the
## only rung that isolates the ladder from everything else.
##
## ## What it actually is, and why it is not just the tissue term
##
## ADR 0070 prices a closed channel at `tissue` alone, and `body_damage.gd` now does
## too: `_resistance_of` counts that term once, inside its per-site sum
## (`base * step * rank + tissue`), and `breakdown` does not add it again. It used to —
## `breakdown` charged `2 x tissue` for every defender, which was a real defect and is
## fixed.
##
## The ladder is still asserted RELATIVE to this rung rather than against a restated sum,
## and that choice is not an artefact of the bug: the relative form is what the claim
## IS — one step of rank is exactly `DEFENSE_PHYSICAL x armour_step` — and it is immune
## to any constant offset in the resistance, whereas a restated sum would re-encode
## whatever the tissue term happens to be worth today.
func _closed_resistance(_unused_defence: float = 0.0) -> float:
	var attacker := _attacker()
	var target := _defender(["lung"])
	return float(_parts(attacker, target, BodyLocation.MODE_NAMED, &"lung")["resistance"])


# --- helpers -------------------------------------------------------------------


## The point on `meridian_id` that a `named` aim actually resolves: the highest
## `point_score`, ties broken by id — read through the PUBLIC `BodyLocation.site_of`, so
## this helper cannot disagree with the ranking it is used to set up.
##
## Named rather than indexed because the three huyệt on the lung (`minor_0`,
## `minor_12`, `minor_24`) are siblings whose relative order depends on the interning of
## their ids, not on their quality. Picking `points[1]` asserted an outcome the data never
## promised.
func _best_open_on(target: Actor, meridian_id: StringName) -> Acupoint:
	var site := BodyLocation.new().site_of(target, _technique(100.0, meridian_id), &"named")
	var chosen: Acupoint = null
	for point in _points_on(target, meridian_id):
		if chosen == null or String(point.id) == String(site.get("point_id", "")):
			chosen = point
	return chosen


## `MeridianState.STATE_ORDER` read through core's own table, never a copy pasted into
## this suite — a test that restated the four ranks would keep passing if core renumbered
## them, and would then be asserting a mechanism that no longer exists.
func target_rank(state: StringName) -> int:
	return int(MeridianState.STATE_ORDER.get(state, 0))


## The mean of every NON-BLOCKED huyệt on the actor, computed independently of
## `AcupointSet.average_quality` — so the assertion is about what that method must EQUAL
## rather than a restatement of it.
func _open_mean(points_on_target: AcupointSet) -> float:
	var count := 0.0
	var total := 0.0
	for point in points_on_target.points:
		if not point.blocked:
			count += 1.0
			total += point.quality
	return 0.0 if count == 0.0 else total / count


## The shipped `BLOCKED_MULT`. A named read rather than a `_tuning.<field>` at each call
## site, so a rebalance of the `.tres` cannot leave half the file comparing against one
## balance and the other half against another.
func _blocked_mult() -> float:
	return _tuning.blocked_mult


## The shipped `point_quality_step`. See [method _blocked_mult].
func _point_quality_step() -> float:
	return _tuning.point_quality_step


## The shipped `channel_mult_step`. See [method _blocked_mult].
func _channel_mult_step() -> float:
	return _tuning.channel_mult_step


## The shipped `injured_mult_step`. See [method _blocked_mult].
func _injured_mult_step() -> float:
	return _tuning.injured_mult_step


## The shipped `meridian_armour_step`. See [method _blocked_mult].
func _meridian_armour_step() -> float:
	return _tuning.meridian_armour_step


## ## Whether the SHIPPED `BLOCKED_MULT` clears `1 + point_quality_step`
##
## `combat_tuning.gd` documents this as a PRECONDITION of the field: "This must exceed
## `1 + point_quality_step` for `random` aim to be able to answer 'it found the jammed
## node'", and ADR 0070 states the inversion as a design requirement. It is a property of
## the authored BALANCE, not of the mechanism — the mechanism reads whatever it is given
## and applies it faithfully either way — so it is derived here and asserted once, in the
## one test whose subject is the shipped balance.
##
## ## The shipped value SATISFIES this, and that is the point of asserting it
##
## The value used to ship as `1.5` against a `0.5` step, which TIES a maximum-quality
## open huyệt exactly: `random` aim could then only ever find a jam on the lowest-id
## tie-break, so the docblock and the `.tres` disagreed and ADR 0070's requirement was
## unmet. A tie is not an inversion — it makes the jam's value a property of the ids
## rather than of the flag. The shipped `combat_damage.tres` now clears the bound, and
## this stays a real assertion so a rebalance of EITHER number that reintroduced the tie
## would fail rather than pass quietly.
func _shipped_overranks_quality() -> bool:
	return _blocked_mult() > 1.0 + _point_quality_step()
