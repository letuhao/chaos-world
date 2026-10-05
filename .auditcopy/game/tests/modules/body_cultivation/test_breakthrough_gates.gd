extends TestCase

## Every gate in `BodyBreakthroughCondition`, seen REFUSING.
##
## `test_full_traversal` prepares an actor that satisfies every condition and
## then breaks through, so the suite proved only that the gates let a prepared
## actor through. Three of them could be deleted outright — `_channels_ready`,
## `_acupoints_ready`, and the `body_integrity` ratio check — and every
## assertion in the file still passed, because no test ever watched one of them
## say no.
##
## Each test below prepares an actor through PUBLIC actions only (see
## `body_play_fixture.gd`: cultivate, meditate, strengthen, recover), breaks
## exactly ONE thing, and asserts that `describe_unmet` names that thing *and
## nothing else*. "Nothing else" is the load-bearing half — it is what makes the
## refusal attributable to the one broken condition instead of to a body that
## simply is not ready. The first test is the control that says a fully prepared
## body reports nothing at all.

var _play: BodyPlayFixture


func setup() -> void:
	_play = BodyPlayFixture.new()


func _unmet(actor: Actor) -> Array[String]:
	return BodyBreakthroughCondition.new().describe_unmet(actor, actor.path(BodyPath.PATH_ID))


## The control. Without it every test below would also pass against a body that
## is never ready for any reason at all.
func test_a_body_prepared_by_play_reports_nothing_unmet() -> void:
	var actor := _play.actor()
	assert_ne(_play.seed_for(actor), null, "the ladder names a next realm to prepare for")
	assert_ne(_play.prepare(actor), null, "prepared through public actions")
	var unmet := _unmet(actor)
	assert_eq(unmet.is_empty(), true, "a prepared body is ready: %s" % ", ".join(unmet))
	assert_eq(BodyAdvancement.preview(actor)["ready"], true, "preview agrees with the gate")


# --- Channels --------------------------------------------------------------


## `_channels_ready` requires the required channels to reach `strengthened`.
## Leaving one of them untrained is the only fault here: every other gate is
## still satisfied through play.
func test_an_untrained_required_channel_is_named_and_is_the_only_block() -> void:
	var actor := _play.actor()
	var target := _play.seed_for(actor)
	assert_ne(target, null, "the ladder names a next realm")
	var skip := target.required_meridians[target.required_meridians.size() - 1]
	_play.prepare(actor, skip)
	# The fault is real: that one channel is not strengthened, and every other
	# required channel is. Without this the test would also pass if `prepare`
	# simply trained nothing.
	var channel := actor.meridians.get_meridian(skip)
	assert_eq(channel.state != &"strengthened", true, "%s really is untrained" % skip)
	for meridian_id in target.required_meridians:
		if meridian_id == skip:
			continue
		assert_eq(
			actor.meridians.get_meridian(meridian_id).state,
			&"strengthened",
			"%s was trained anyway" % meridian_id
		)
	var unmet := _unmet(actor)
	assert_eq(unmet.size(), 1, "exactly one thing is missing: %s" % ", ".join(unmet))
	assert_eq(
		unmet[0].contains("Required channels are not trained deep enough"),
		true,
		"and it is the channel gate: %s" % unmet[0]
	)
	assert_eq(BodyAdvancement.preview(actor)["ready"], false, "preview refuses too")


## The channel gate is a DEPTH gate as well as a state gate, and the two clauses
## are separately load-bearing: deleting the `refinement` comparison leaves a
## channel that is strengthened but one step short passing the gate.
func test_a_shallow_required_channel_is_named_and_is_the_only_block() -> void:
	var actor := _play.actor()
	var target := _play.seed_for(actor)
	assert_ne(target, null, "the ladder names a next realm")
	assert_eq(target.required_refinement > 0, true, "the floor is deeper than zero")
	var shallow := target.required_refinement - 1
	_play.prepare(actor, &"", &"", shallow)
	# Every required channel reached `strengthened` and stopped one step short.
	for meridian_id in target.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		assert_eq(channel.state, &"strengthened", "%s reached strengthened" % meridian_id)
		assert_eq(channel.refinement, shallow, "%s stopped one step short" % meridian_id)
	var unmet := _unmet(actor)
	assert_eq(unmet.size(), 1, "exactly one thing is missing: %s" % ", ".join(unmet))
	assert_eq(
		unmet[0].contains("Required channels are not trained deep enough"),
		true,
		"and it is the depth gate: %s" % unmet[0]
	)


## Training the last channel through the public action is the way out, and it
## reopens the gate. This is what makes the refusal above a gate rather than a
## dead end.
func test_training_the_missing_channel_reopens_the_gate() -> void:
	var actor := _play.actor()
	var target := _play.seed_for(actor)
	var skip := target.required_meridians[target.required_meridians.size() - 1]
	_play.prepare(actor, skip)
	assert_eq(_unmet(actor).size(), 1, "blocked while the channel is untrained")
	_play.train_channel(actor, skip, target)
	assert_eq(actor.meridians.get_meridian(skip).state, &"strengthened", "now trained")
	assert_eq(_unmet(actor).is_empty(), true, "gate reopened")


# --- Acupoint quality -----------------------------------------------------


## `_acupoints_ready` demands a quality floor on every huyệt the realm has
## unlocked.
##
## The fault is INJECTED, and deliberately so. Cultivation raises every open
## huyệt toward the current realm's ceiling, and that ceiling is authored a
## fixed margin ABOVE the next realm's floor — so on a body that has paid its
## work budget no huyệt can be below the floor, and a huyệt a deviation jams is
## cleared again by the channel training the same gate demands. The clause is a
## defensive invariant, not a reachable player state. Writing the fault is what
## puts it under test at all: with the clause deleted this actor reports ready
## and every other gate in this file still passes.
func test_a_huyet_below_the_quality_floor_is_named_and_is_the_only_block() -> void:
	var actor := _play.actor()
	var target := _play.seed_for(actor)
	assert_ne(target, null, "the ladder names a next realm")
	assert_eq(
		(
			AcupointDefaults.from_definition(AcupointDefaults.definitions()[0]).quality
			< target.quality_required
		),
		true,
		"sanity: an untrained huyệt is below %s's floor" % target.id
	)
	_play.prepare(actor)
	var points := _first_meridian_points(actor)
	assert_eq(points.is_empty(), false, "found a huyệt to starve")
	points[0].quality = target.quality_required - 0.02
	var unmet := _unmet(actor)
	assert_eq(unmet.size(), 1, "exactly one thing is missing: %s" % ", ".join(unmet))
	assert_eq(
		unmet[0].contains("Acupoint quality below the realm requirement"),
		true,
		"and it is the quality gate: %s" % unmet[0]
	)


## Cultivation is the way out of a starved huyệt, through the same public
## action a screen calls. The refusal has to be escapable.
func test_cultivating_reopens_the_quality_gate() -> void:
	var actor := _play.actor()
	var target := _play.seed_for(actor)
	_play.prepare(actor)
	_first_meridian_points(actor)[0].quality = target.quality_required - 0.02
	assert_eq(_unmet(actor).size(), 1, "blocked while the huyệt is starved")
	_play.cultivate_until(actor, target.progress_required, target.quality_required)
	assert_eq(_unmet(actor).is_empty(), true, "gate reopened")


## The gate reads quality, not blockage. That is a real distinction and it is
## load-bearing: a jammed huyệt must not read as "quality below the floor" while
## its quality is fine, or a player repairing a body would be told to redo work
## they had already done.
func test_a_jammed_huyet_alone_is_not_a_block() -> void:
	var actor := _play.actor()
	_play.prepare(actor)
	var jammed := _first_meridian_points(actor)[0]
	assert_eq(jammed.blocked, false, "sanity: nothing is jammed yet")
	jammed.block()
	assert_eq(_unmet(actor).is_empty(), true, "a healthy jammed huyệt blocks nothing")
	# Blockage is still not free, it is just not a gate: the read model reports
	# it and no huyệt disappears from the body.
	var panel := BodyCultivationApi.panel_state(actor)
	assert_eq(panel["blocked"], 1, "the panel reports the jam")
	assert_eq(
		panel["acupoints"], BodyCultivationApi.acupoints(actor).size(), "and no huyệt vanished"
	)


# --- The shared reservoir -------------------------------------------------


## The reservoir gate is a RATIO against the target realm's authored
## `integrity_target`, not "full". Spending the pool is what the breakthrough
## itself spends it through, so this needs no invented state either.
func test_a_spent_reservoir_is_named_and_is_the_only_block() -> void:
	var actor := _play.actor()
	var target := _play.seed_for(actor)
	_play.prepare(actor)
	var pool := _play.reservoir(actor)
	assert_ne(pool, null, "the body carries a reservoir")
	assert_eq(
		pool.ratio() >= target.integrity_target,
		true,
		"sanity: a prepared body meets the %.0f%% target" % (target.integrity_target * 100.0)
	)
	var points: AcupointSet = actor.component(&"acupoints")
	# One whole unit under the target, so the comparison is not a float tie.
	var keep := target.integrity_target * pool.maximum - 1.0
	assert_eq(points.drain(pool.current - keep), true, "spent through the huyệt set")
	assert_eq(pool.ratio() < target.integrity_target, true, "sanity: it really is short")
	var unmet := _unmet(actor)
	assert_eq(unmet.size(), 1, "exactly one thing is missing: %s" % ", ".join(unmet))
	assert_eq(
		unmet[0].contains("Body integrity"), true, "and it is the reservoir gate: %s" % unmet[0]
	)


## The other half of "it is a ratio": a reservoir that is NOT full but is above
## the target must pass. Collapsing the ratio into "must be full" — which is what
## the gate did before `integrity_target` was authored — fails here.
func test_a_reservoir_above_the_target_passes_while_short_of_full() -> void:
	var actor := _play.actor()
	var target := _play.seed_for(actor)
	_play.prepare(actor)
	var pool := _play.reservoir(actor)
	var points: AcupointSet = actor.component(&"acupoints")
	var leave := target.integrity_target * pool.maximum + 1.0
	assert_eq(leave < pool.maximum, true, "sanity: the target is below the ceiling")
	assert_eq(points.drain(pool.current - leave), true, "spent some of the pool")
	assert_eq(pool.ratio() < 1.0, true, "sanity: it really is short of full")
	assert_eq(_unmet(actor).is_empty(), true, "above the target is enough")


## Cultivation refills the pool through the same action that spends it, so the
## refusal above is escapable.
func test_cultivating_reopens_the_reservoir_gate() -> void:
	var actor := _play.actor()
	var target := _play.seed_for(actor)
	_play.prepare(actor)
	var pool := _play.reservoir(actor)
	var points: AcupointSet = actor.component(&"acupoints")
	points.drain(pool.current - target.integrity_target * pool.maximum + 1.0)
	assert_eq(_unmet(actor).size(), 1, "blocked while the pool is spent")
	_play.cultivate_until(actor, target.progress_required, target.quality_required)
	assert_eq(_play.reservoir_full(actor), true, "pool refilled")
	assert_eq(_unmet(actor).is_empty(), true, "gate reopened")


# --- The gates the cheap preparation used to write in ---------------------


## Progress is a gate the earlier `_prepare` helpers wrote straight into the
## actor. A body that has just broken through is the honest state that misses it:
## `Breakthrough.try_advance` zeroes the work budget and the breakthrough spends
## the reservoir, so the realm it just entered starts owing both. Nothing is
## injected — this is the first turn of every new realm.
func test_a_body_that_just_broke_through_owes_its_next_work_budget() -> void:
	var actor := _play.actor()
	assert_ne(_play.prepare(actor), null, "prepared through public actions")
	assert_eq(_play.breakthrough(actor, _rng(7)), true, "broke through by play")
	var target := _play.seed_for(actor)
	assert_ne(target, null, "the ladder names a realm after it")
	assert_eq(actor.path(BodyPath.PATH_ID).progress, 0.0, "the work budget starts empty")
	var unmet := _unmet(actor)
	assert_eq(_names(unmet, "Progress"), true, "the budget is named: %s" % ", ".join(unmet))
	assert_eq(
		_names(unmet, "Body integrity"),
		true,
		"and so is the reservoir the breakthrough spends: %s" % ", ".join(unmet)
	)
	# Cultivation is how a realm is paid for, through the public action.
	_play.cultivate_until(actor, target.progress_required, target.quality_required)
	assert_eq(_names(_unmet(actor), "Progress"), false, "cultivating cleared it")
	assert_eq(_play.reservoir_full(actor), true, "and refilled the reservoir")


## Comprehension has exactly one source, meditation, so a body that never
## meditated is missing the insight floor with nothing injected at all. This is
## the default state of a fresh actor.
func test_a_body_that_never_meditated_is_missing_its_insight_floor() -> void:
	var bare := _play.actor()
	var target := _play.seed_for(bare)
	assert_eq(bare.stats.get_base(Stat.COMPREHENSION), 0.0, "sanity: nothing meditated")
	var unmet := _unmet(bare)
	assert_eq(_names(unmet, "Comprehension"), true, "the floor is named: %s" % ", ".join(unmet))
	assert_eq(
		unmet.has("Comprehension %d/%d" % [0, int(target.insight_required)]),
		true,
		"with the numbers in the message: %s" % ", ".join(unmet)
	)
	# And meditation is the way out, through the public action.
	_play.meditate_to(bare, target.insight_required)
	assert_eq(_names(_unmet(bare), "Comprehension"), false, "meditating cleared it")


## Physique only ever rises in play (realm rewards and training milestones), so
## the fault has to be written. That is the point of stating it: the gate reads
## a base stat the rest of the module spends a whole ladder raising, and nothing
## else can ever lower it.
func test_a_body_below_its_physique_floor_is_named() -> void:
	var actor := _play.actor()
	var target := _play.seed_for(actor)
	_play.prepare(actor)
	actor.stats.set_base(Stat.PHYSIQUE, target.physique_required - 1.0)
	var unmet := _unmet(actor)
	assert_eq(unmet.size(), 1, "exactly one thing is missing: %s" % ", ".join(unmet))
	assert_eq(
		unmet[0].contains(
			"Physique %d/%d" % [int(target.physique_required) - 1, int(target.physique_required)]
		),
		true,
		"and it is the physique gate: %s" % unmet[0]
	)


## The realm pill is a gate too, and `start_attempt` must refuse without
## spending one.
func test_a_body_without_the_realm_pill_is_named_and_costs_nothing() -> void:
	var actor := _play.actor()
	var target := _play.seed_for(actor)
	_play.prepare(actor)
	var inventory := ItemsApi.inventory(actor)
	var held := inventory.count(target.breakthrough_item)
	assert_eq(held > 0, true, "sanity: the pill was stocked")
	# Bounded by what was counted, not by a `while` on the inventory: a loop
	# whose exit condition is "the stack is gone" and which cannot empty it is
	# exactly the shape that burns a disk.
	for _pill in held:
		inventory.remove(target.breakthrough_item, 1)
	var unmet := _unmet(actor)
	assert_eq(unmet.size(), 1, "exactly one thing is missing: %s" % ", ".join(unmet))
	assert_eq(unmet[0], "Missing breakthrough pill", "and it is the pill")
	var refused := BodyAdvancement.start_attempt(actor)
	assert_eq(refused == null, true, "an attempt is refused, got [%s]" % str(refused))
	assert_eq(inventory.count(target.breakthrough_item), 0, "and no pill was spent")


# --- Helpers --------------------------------------------------------------


## The huyệt on the first channel the set holds — always a minor one, always on
## a channel the realm owns, so a fault placed here is one the game can clear.
func _first_meridian_points(actor: Actor) -> Array[Acupoint]:
	var points := BodyCultivationApi.acupoints(actor)
	if points.is_empty():
		return []
	var out: Array[Acupoint] = []
	for point in points:
		if AcupointDefaults.meridian_of(point.id) == AcupointDefaults.meridian_of(points[0].id):
			out.append(point)
	return out


func _names(unmet: Array[String], fragment: String) -> bool:
	for message in unmet:
		if message.contains(fragment):
			return true
	return false


## A seeded generator, so a breakthrough's outcome is the same on every run and
## a failure is never "an unlucky stream".
func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng
