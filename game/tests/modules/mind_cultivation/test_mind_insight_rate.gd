extends TestCase

## BL-0165: the mind path's insight rate is priced by core's `Stat.INSIGHT_GAIN`,
## the same stat body and qi both multiply by.
##
## Comprehension is a SHARED base attribute. `core/actor_stats.gd` derives
## `INSIGHT_GAIN = 1.0 + comprehension * 0.01`, sect offices grant a PERCENT on it,
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

## Cultivation work per measurement. Sized so the comprehension delta is far above
## float noise and far below the sea's capacity, so one sitting cannot be clamped
## or truncated by the reservoir.
const WORK := 200.0

## Tolerance for a ratio of two measured deltas. Both deltas come from the same
## float arithmetic on the same actor shape, so this is slack for accumulation
## order, not for a real difference: a dropped multiplier moves the ratio to 1.0.
const RATIO_TOLERANCE := 0.0001


func _actor(comprehension: float = 0.0) -> Actor:
	var actor := Actor.new(
		&"mind_insight", {Stat.COMPREHENSION: comprehension, MindStats.SEA_CAPACITY: 1000.0}
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


## The stat is not merely honoured, it is the ONLY thing that varies: the rate has
## to rise with comprehension, because `INSIGHT_GAIN` is `1.0 + comprehension *
## 0.01`. Read before and after a comprehension floor and the ratio between the two
## measured rates must equal the ratio between the two published stat values.
##
## The published values are cross-checked, not the source of the expectation: the
## behavioural assertions above already fix the multiplier's identity, so this one
## only pins that the curve the mind path rides is core's curve.
func test_the_rate_rises_with_comprehension_along_the_shared_curve() -> void:
	var low_comprehension := 0.0
	var high_comprehension := 500.0
	var low_rate := _measured_rate(low_comprehension)
	var high_rate := _measured_rate(high_comprehension)
	assert_eq(high_rate > low_rate, true, "the shared stat rises with comprehension")
	assert_almost_eq(
		high_rate / low_rate,
		_published_insight_gain(high_comprehension) / _published_insight_gain(low_comprehension),
		"and the mind path rides core's curve, not one of its own",
		RATIO_TOLERANCE
	)


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
	var source := FileAccess.get_file_as_string("res://src/modules/mind_cultivation/training.gd")
	assert_ne(source, "", "training.gd is readable")
	assert_eq(
		source.contains("Stat.INSIGHT_GAIN"),
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
