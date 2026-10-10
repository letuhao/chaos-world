extends TestCase

## DEF-0402, after the step fix: the body's mandatory gate no longer saturates the acupoints,
## so the OPTIONAL chase buys something and the authored floors bite.
##
## ## What was wrong, and the fix that worked
##
## `BodyTraining._train_points` raised the acupoints 0.02 per `strengthen` press, and the
## press ALSO advances the channel — so a realm whose `refinement_cap` is high (the deep
## realms run to 29, ~31 presses to the gate) carried the acupoints 0.62 past their 0.5
## start and SATURATED them at the ceiling before the gate was met. A gate-stopped walk then
## departed at 0.74..1.00 and cleared every floor. The fix is `POINT_TRAINING_STEP = 0.01`:
## the mandatory gate now leaves the acupoints at/near the gate floor, so a gate-stopped walk
## departs low and the floors (0.05..0.80) bite, while a saturated walk still reaches 1.0000.
##
## **Raising `quality_target` was tried first and REJECTED:** widening the band that way also
## raised the breakthrough chance, and `test_realm_profile.gd` caught it (72 failures) — the
## ceiling is priced against the best quality a trained body can hold. The step is the fix
## that touches neither the ceiling nor the chance band.
##
## ## What this pins
##
## The CHASE MATTERS: a gate-stopped walk departs strictly below a saturated one, on every
## realm, and below half the band. A change that re-saturates the acupoints turns this red.

const Play := preload("res://tests/modules/body_cultivation/body_play_fixture.gd")

## One mid-ladder realm whose floor is low (the walk clears) and one deep realm.
const REALMS: Array[StringName] = [&"core_formation", &"dao_ancestor"]


func test_the_chase_matters_after_the_band_widened() -> void:
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
		var saturated: Actor = play.actor(at)
		for meridian_id in seed.required_meridians:
			play.train_channel(saturated, meridian_id, seed)
		var gate_stopped := BodyCultivationApi.departure_perfection(stopped, target.id)
		var full := BodyCultivationApi.departure_perfection(saturated, target.id)
		assert_eq(
			gate_stopped < full,
			true,
			(
				(
					"%s: a gate-stopped walk departs at %.4f, strictly below the saturated "
					% [at, gate_stopped]
				)
				+ "%.4f — the optional chase buys something again (band %s)" % [full, target.id]
			)
		)
		assert_eq(
			gate_stopped < 0.5,
			true,
			(
				(
					"%s: the mandatory gate leaves most of the band open (%.4f), so the floors "
					% [at, gate_stopped]
				)
				+ "above it bite"
			)
		)
