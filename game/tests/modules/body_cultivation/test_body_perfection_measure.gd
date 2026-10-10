extends TestCase

## DEF-0402, MEASURED: the body's authored `min_foundation` floors are inert, and this is
## WHY, from numbers rather than from prose.
##
## ## The measurement
##
## A GATE-STOPPED walk (`train_channel` with `depth_cap = the target's required_refinement`)
## departs at perfection 0.70 (core_formation) rising to 1.00 (dao_ancestor), while the
## floors it must clear are 0.05..0.80. So even the MINIMAL legal walk clears every floor,
## and the wall never bites on the body path. A SATURATED walk reads 1.0000 everywhere.
##
## ## The mechanism (enriched, and it is not a step size)
##
## Perfection = `(quality - target.quality_required) / (source.quality_target -
## target.quality_required)`, a 0.07-wide band. The MANDATORY work — the next realm's
## channel gate, ~5..9 presses, each of which ALSO trains the acupoints 0.02 — already
## carries the acupoints most of the way across that band before the gate is met. The band
## is simply narrower than the mandatory overshoot, so there is nothing left for the
## OPTIONAL chase to buy and no floor left to fail.
##
## ## The fix this measurement points at (a CONTENT pass, not this test)
##
## Widen the gate->ceiling band so the mandatory gate leaves a real chase: lower each seed's
## `quality_required` or raise its `quality_target`, and/or slow the per-press acupoint step
## so the channel gate is met with the acupoints nearer the floor. Either changes all 30
## seeds and the body traversal, so it is its own slice — this test PINS the current
## measurement so that slice has a before/after to move.
##
## The assertion is a RELATIONSHIP (a gate-stopped walk clears the floor), not a literal, so
## a content change that widens the band flips it red and names the work.

const Play := preload("res://tests/modules/body_cultivation/body_play_fixture.gd")

## One mid-ladder and one deep realm: the two ends of the measured range.
const REALMS: Array[StringName] = [&"core_formation", &"dao_ancestor"]


func test_a_gate_stopped_walk_still_clears_the_body_floor() -> void:
	var play := Play.new()
	for at in REALMS:
		var target := RealmDefaults.ladder().next(at)
		assert_ne(target, null, "%s has a realm above it" % at)
		if target == null:
			continue
		var seed := BodyRealmSeed.for_realm(target.id)
		assert_ne(seed, null, "%s authors a seed" % target.id)
		if seed == null:
			continue
		var stopped: Actor = play.actor(at)
		for meridian_id in seed.required_meridians:
			play.train_channel(stopped, meridian_id, seed, seed.required_refinement)
		var perfection := BodyCultivationApi.departure_perfection(stopped, target.id)
		assert_eq(
			perfection >= seed.min_foundation,
			true,
			(
				(
					"%s: a gate-stopped walk departs at %.4f against a floor of %.4f, so the "
					% [at, perfection, seed.min_foundation]
				)
				+ "floor does NOT bite. This is DEF-0402's measurement; the fix is a content "
				+ "pass that widens the gate->ceiling band (see this file's docstring)."
			)
		)
		assert_eq(
			perfection >= 0.5,
			true,
			(
				"%s: the mandatory gate alone carries the acupoints past half the band " % at
				+ "(%.4f), which is why the chase buys almost nothing" % perfection
			)
		)
