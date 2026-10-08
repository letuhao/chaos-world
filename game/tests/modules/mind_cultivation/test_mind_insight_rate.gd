extends TestCase

## BL-0165: the mind path's insight rate is priced by core's `Stat.INSIGHT_GAIN`,
## the same stat body and qi both multiply by.
##
## Comprehension is a SHARED base attribute. `core/actor_stats.gd` derives
## `INSIGHT_GAIN = 1.0 + will * 0.01` (BL-0822: it was `1.0 + comprehension * 0.01`, which
## made the rate a function of the quantity it grows), sect offices grant a PERCENT on it,
## races and items carry it, and all three cultivation paths add to the same
## number. `MindTraining._grant_insight` used to add `gain * INSIGHT_RATE` and
## nothing else, so every one of those sources silently did nothing for the one
## path whose entry gate IS comprehension.
##
## ## Every assertion here is a DIFFERENCE between two actors, not a value.
##
## A value assertion would have to restate the rate — and restating it means
## either pasting a magic number or calling the implementation's own helper, which
## is the mistake this repo has shipped green tests for before. Instead each test
## varies exactly one input and measures the consequence: if the shared stat is
## ignored, the two deltas are equal and these fail. `INSIGHT_RATE` stays the
## module's own coefficient on CULTIVATION WORK; the multiplier is core's, and
## `INSIGHT_RATE` cancels out of every ratio below.

const RANK := &"qi_refining"

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

## Cultivation work per measurement. Sized so the comprehension delta is far above
## float noise and far below the sea's capacity, so one sitting cannot be clamped
## or truncated by the reservoir.
const WORK := 200.0

## Tolerance for a ratio of two measured deltas. Both deltas come from the same
## float arithmetic on the same actor shape, so this is slack for accumulation
## order, not for a real difference: a dropped multiplier moves the ratio to 1.0.
const RATIO_TOLERANCE := 0.0001


func _actor(comprehension: float = 0.0, will: float = 2.0) -> Actor:
	var actor := Actor.new(
		&"mind_insight",
		{Stat.COMPREHENSION: comprehension, Stat.WILL: will, MindStats.SEA_CAPACITY: 1000.0}
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, RANK))
	actor.meridians.unlock_for_realm(RANK)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	MindTraining.synchronize(actor)
	return actor


## The comprehension ONE sitting of `work` adds, as a difference. Absolute
## comprehension is never read: what matters is how much this sitting moved it.
func _comprehension_gained_by_cultivation(work: float, insight_percent: float = 0.0) -> float:
	var actor := _actor()
	if insight_percent != 0.0:
		actor.stats.add_modifier(
			StatModifier.new(Stat.INSIGHT_GAIN, Stat.Op.PERCENT, insight_percent, &"test:insight")
		)
	var before := actor.stats.get_base(Stat.COMPREHENSION)
	assert_eq(MindTraining.cultivate(actor, work), true, "cultivation applied")
	return actor.stats.get_base(Stat.COMPREHENSION) - before


## ## BL-0822, the whole runaway in one assertion: the same sitting pays the same, whatever
## ## the actor already holds.
##
## `INSIGHT_GAIN` used to be `1.0 + comprehension * 0.01` while the gain is
## `work * INSIGHT_RATE * INSIGHT_GAIN`, so an actor holding more comprehension gained MORE
## per sitting: `dC = k(1 + 0.01 C)` is exponential in C, not linear in the work, and the
## measured result was comprehension compounding to 2.1e+37. A rate that reads the stock it
## grows diverges by construction, whatever coefficient it carries.
##
## The two deltas must therefore be EQUAL. A reintroduced feedback makes the richer actor's
## delta larger, which is the direction the old implementation failed in, so this test does
## not merely pin today's number - it pins the SHAPE.
func test_the_gain_does_not_depend_on_the_comprehension_already_held() -> void:
	var poor := _actor(0.0)
	var rich := _actor(5000.0)
	var before_poor := poor.stats.get_base(Stat.COMPREHENSION)
	var before_rich := rich.stats.get_base(Stat.COMPREHENSION)
	assert_eq(MindTraining.cultivate(poor, WORK), true, "the empty-handed actor cultivates")
	assert_eq(MindTraining.cultivate(rich, WORK), true, "and so does the well-read one")
	var gain_poor := poor.stats.get_base(Stat.COMPREHENSION) - before_poor
	var gain_rich := rich.stats.get_base(Stat.COMPREHENSION) - before_rich
	assert_eq(gain_poor > 0.0, true, "the sitting pays something at all: %f" % gain_poor)
	assert_almost_eq(
		gain_rich,
		gain_poor,
		"5000 comprehension already held buys no more per sitting than none",
		maxf(RATIO_TOLERANCE * gain_poor, 0.0001)
	)


## The first and load-bearing one: a PERCENT on the shared stat must move the mind
## path's comprehension gain by that PERCENT. With the multiplier absent both
## actors gain the same amount and the ratio is 1.0 — this is the mutation the
## fix is proved against.
func test_an_insight_gain_bonus_scales_the_mind_path_proportionally() -> void:
	var plain := _comprehension_gained_by_cultivation(WORK)
	var doubled := _comprehension_gained_by_cultivation(WORK, 1.0)
	assert_ne(plain, 0.0, "one sitting earns comprehension at all")
	assert_almost_eq(doubled, plain * 2.0, "double the stat, double the gain", RATIO_TOLERANCE)


## Down as well as up: a floor raised above zero is read too, so this is not a
## one-directional special case for bonuses.
func test_a_reduced_insight_gain_scales_the_mind_path_downwards() -> void:
	var plain := _comprehension_gained_by_cultivation(WORK)
	var halved := _comprehension_gained_by_cultivation(WORK, -0.5)
	assert_almost_eq(halved, plain * 0.5, "half the stat, half the gain", RATIO_TOLERANCE)


## ## The rate is FLAT in the stock it grows, and MOVES with the attribute.
##
## This test used to assert the opposite - `high_rate > low_rate`, with comprehension the
## only input varied - and it was the runaway's own guard: a green suite pinning
## `1.0 + comprehension * 0.01` is how `dC = k(1 + 0.01 C)` survived long enough to reach
## 2.1e+37 (BL-0822). A rate that reads the stock it grows diverges by construction, so the
## assertion is now the invariant that kills the class rather than the coefficient that
## caused it.
##
## The published values are still cross-checked rather than trusted: the behavioural
## assertions above fix the multiplier's identity, and this one pins that what the mind
## path RIDES is core's curve and not one of its own.
func test_the_rate_is_flat_in_comprehension() -> void:
	var low_rate := _measured_rate(0.0)
	var high_rate := _measured_rate(500.0)
	assert_almost_eq(
		high_rate,
		low_rate,
		"500 comprehension already held buys no higher a rate than none",
		maxf(RATIO_TOLERANCE * low_rate, 0.0001)
	)
	assert_almost_eq(
		high_rate / low_rate,
		_published_insight_gain(500.0) / _published_insight_gain(0.0),
		"and the mind path rides core's curve, not one of its own",
		RATIO_TOLERANCE
	)


## And it is not flat in EVERYTHING, or the feedback could have been removed by deleting
## the rate instead of repairing it: more `will` is a faster rate, which is what makes
## `insight_gain` an attribute on the mind path's own axis (ADR 0013 sources `dao_heart`
## from `will`) rather than a constant.
func test_a_higher_will_reads_faster() -> void:
	var plain := _rate_at_will(2.0)
	var strong := _rate_at_will(40.0)
	assert_eq(
		strong > plain,
		true,
		"a stronger will reads faster: %f at will 40 vs %f at will 2" % [strong, plain]
	)


## The rate one sitting pays, at a given `will`, on an actor holding no comprehension: the
## only input that moves is the attribute the rate is derived from.
func _rate_at_will(will: float) -> float:
	var actor := _actor(0.0, will)
	var before := actor.stats.get_base(Stat.COMPREHENSION)
	var progress_before := actor.path(MindPath.PATH_ID).progress
	assert_eq(MindTraining.cultivate(actor, WORK), true, "cultivation applied at will %f" % will)
	var work_done := actor.path(MindPath.PATH_ID).progress - progress_before
	assert_ne(work_done, 0.0, "the sitting really did work")
	return (actor.stats.get_base(Stat.COMPREHENSION) - before) / work_done


## Insight per unit of cultivation work, measured through the production action at
## a given starting comprehension. `gain` is the realm rate times the flow bonus,
## and both are the same for the two measurements, so dividing them out is exact.
func _measured_rate(comprehension: float) -> float:
	var actor := _actor(comprehension)
	var before := actor.stats.get_base(Stat.COMPREHENSION)
	var progress_before := actor.path(MindPath.PATH_ID).progress
	assert_eq(
		MindTraining.cultivate(actor, WORK), true, "cultivation applied at %f" % comprehension
	)
	var work_done := actor.path(MindPath.PATH_ID).progress - progress_before
	assert_ne(work_done, 0.0, "the sitting really did work")
	return (actor.stats.get_base(Stat.COMPREHENSION) - before) / work_done


## The shared rate on an actor holding `comprehension`, read from the stat itself
## rather than recomputed from core's formula — so this cross-check cannot pass by
## restating the very expression it is checking.
func _published_insight_gain(comprehension: float) -> float:
	var actor := _actor(comprehension)
	return actor.stats.derived(Stat.INSIGHT_GAIN)


## The call-site guard, the same shape `tests/core/test_realm_rate.gd` uses for the
## shared realm curve: a path that quietly stopped reading the shared stat would
## still satisfy every behavioural test above if the modifiers those tests apply
## were removed from the tree, and the failure would then be invisible. Naming the
## read is what makes "mind reads the shared insight rate" a fact about the source.
func test_the_mind_path_reads_the_shared_insight_rate() -> void:
	assert_eq(
		Probe.module_code("training.gd").contains("Stat.INSIGHT_GAIN"),
		true,
		"the insight grant reads the shared rate rather than a local one"
	)


## And the parity that makes it one rate in the game: body and qi price their
## comprehension gain off `Stat.INSIGHT_GAIN` too, so a PERCENT granted to a
## cultivator lands the same on all three paths. Read from source for the same
## reason as above — a shared number cannot be compared across modules by value,
## only by being read from one place.
func test_all_three_cultivation_paths_read_the_shared_insight_rate() -> void:
	for path_dir in ["body_cultivation", "qi_cultivation", "mind_cultivation"]:
		var source := FileAccess.get_file_as_string("res://src/modules/%s/training.gd" % path_dir)
		assert_ne(source, "", "%s/training.gd is readable" % path_dir)
		assert_eq(
			source.contains("Stat.INSIGHT_GAIN"),
			true,
			"%s prices comprehension gain off the shared rate" % path_dir
		)
