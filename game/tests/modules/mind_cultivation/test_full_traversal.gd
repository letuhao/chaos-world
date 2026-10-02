extends TestCase

## Full R1->R30 traversal (ADR 0013/0016/0024/0029/0035). Every advance goes
## through the public facade: prepare -> start -> resolve. The test controls only
## RNG and elapsed work; it never sets rank, channel states, anchors, success
## flags, or path progress. Items are resolved from the authored content tree so
## the walk also proves each realm's content exists.
##
## The walk runs once and is cached, so the anchor assertions reuse it rather
## than replaying thirty realms each time.

## R1 is the starting realm, so advancing through the ladder is 29 transitions.
const TRANSITIONS := 29

static var _cached: Actor = null


func _actor() -> Actor:
	var actor := (
		Actor
		. new(
			&"traversal_hero",
			{
				Stat.COMPREHENSION: 0.0,
				Stat.WILL: 50.0,
				Stat.SPIRIT: 50.0,
				MindStats.PERCEPTION: 50.0,
				MindStats.MENTAL_CLARITY: 50.0,
			}
		)
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 500)
	MindTraining.synchronize(actor)
	return actor


## Stock a real authored item rather than a fabricated stub. Resolving through
## the item tree is what proves the profile's content exists and is loadable.
func _stock(actor: Actor, def_id: StringName) -> void:
	if def_id.is_empty():
		return
	var def := Crafting.resolve(def_id)
	assert_ne(def, null, "authored item %s exists" % def_id)
	if def == null:
		return
	var guard := 0
	while not ItemsApi.has_item(actor, def_id) and guard < 64:
		ItemsApi.inventory(actor).add(def, 1)
		guard += 1


## Train every channel the source realm requires with the source realm's channel
## elixir, repairing injury first. Eligibility (unlock) and opening (train) stay
## separate: a realm award exposes channels, training opens them.
func _train_required_channels(actor: Actor, source_seed: MindRealmSeed) -> void:
	var target_rank: int = MeridianState.STATE_ORDER.get(source_seed.required_channel_state, 0)
	for meridian_id in source_seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		if channel.is_injured():
			actor.meridians.repair_meridian(meridian_id)
		while MeridianState.STATE_ORDER.get(channel.state, 0) < target_rank:
			_stock(actor, source_seed.training_item)
			if not MindTraining.train_channel(actor, meridian_id):
				break
			channel = actor.meridians.get_meridian(meridian_id)


## Fight and win the tribulation for the realm being entered, through the
## production entry points only (ADR 0041). Finishing the phases is not enough:
## a gate opens only for a decided win, so the fight must be resolved as well.
func _survive_tribulation(actor: Actor, target: RealmDef) -> void:
	if target.index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
		return
	if Breakthrough.tribulation_ok(actor, target.index):
		return
	if Breakthrough.begin_tribulation(actor, target.index) == null:
		return
	var guard := 0
	while Breakthrough.advance_tribulation(actor) and guard < 128:
		guard += 1
	assert_eq(Breakthrough.resolve_tribulation(actor, true), true, "tribulation won")


## Prepare every prerequisite the entry rules require. Returns the preview so
## callers can assert the attempt is actually legal.
func _prepare(actor: Actor) -> Dictionary:
	var state := actor.path(MindPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return {}
	var target_seed := MindRealmSeed.for_realm(target.id)
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	if target_seed == null or source_seed == null:
		return {}

	actor.meridians.unlock_for_realm(target.id)
	_train_required_channels(actor, source_seed)

	# Both per-realm strengthening milestones must actually complete.
	_stock(actor, source_seed.sea_catalyst)
	assert_eq(MindTraining.strengthen_sea(actor), true, "sea milestone completed")
	_stock(actor, source_seed.training_item)
	# R19 commits the first anchor, so only later high tiers have one to
	# reinforce; at R19 this milestone is a legitimate no-op.
	if target.index > Breakthrough.IMMORTAL_REALM_THRESHOLD:
		assert_eq(MindTraining.strengthen_anchor(actor), true, "resonance milestone completed")

	_survive_tribulation(actor, target)

	var sea := MindCultivationApi.sea(actor)
	while sea.turbulence > 0.0:
		MindTraining.meditate(actor, 1.0)

	# Progress and insight are both earned only through `cultivate`. A full
	# reservoir refuses work, so mind power is spent to make room — the real loop
	# is fill, spend, fill — and the reservoir is topped off last because entry
	# also requires it full.
	var guard := 0
	while (
		guard < 8192
		and (
			state.progress < target_seed.progress_required
			or actor.stats.get_base(Stat.COMPREHENSION) < target_seed.comprehension_required
		)
	):
		guard += 1
		if sea.is_full(actor):
			sea.drain(actor, sea.current(actor))
		if not MindTraining.cultivate(actor, 500.0):
			break
	assert_eq(
		state.progress >= target_seed.progress_required, true, "progress earned for %s" % target.id
	)
	while not sea.is_full(actor) and guard < 16384:
		guard += 1
		if not MindTraining.cultivate(actor, 500.0):
			break

	_stock(actor, target_seed.breakthrough_item)
	return MindAdvancement.preview(actor)


## Attempt until the breakthrough resolves. Preparation is redone only after a
## failure, because a blocked attempt has no effect at all and a failed one loses
## only recoverable state (turbulence, one injured channel).
func _attempt_until_resolved(actor: Actor, rng: RandomNumberGenerator) -> bool:
	if _prepare(actor).is_empty():
		return false
	for attempt in range(60):
		if MindAdvancement.try_breakthrough(actor, rng):
			return true
		_prepare(actor)
	return false


## One canonical walk from R1 to R30, cached for reuse across the suite.
func _walked() -> Actor:
	if _cached != null:
		return _cached
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var steps: Array = []
	for step in range(TRANSITIONS):
		var target := RealmDefaults.ladder().next(actor.path(MindPath.PATH_ID).rank_id)
		if target == null:
			break
		var preview := _prepare(actor)
		# Capture committed high-tier state *before* the attempt: the anchor a
		# realm creates is that attempt's outcome, never its own prerequisite.
		var will_before := actor.stats.get_base(Stat.WILL)
		var anchor_before: StringName = (
			actor.inside_world.tier if actor.inside_world != null else &""
		)
		var world_before: StringName = actor.world.tier if actor.world != null else &""
		var resolved := _attempt_until_resolved(actor, rng)
		# The award must land on the actor, not merely advance the path.
		var awarded := actor.stats.get_base(Stat.WILL) > will_before
		(
			steps
			. append(
				{
					"target": target.id,
					"ready": preview.get("ready", false),
					"conditions": preview.get("conditions", []),
					"resolved": resolved,
					"awarded": awarded,
					"rank": actor.path(MindPath.PATH_ID).rank_id,
					"anchor_before": anchor_before,
					"world_before": world_before,
				}
			)
		)
	actor.set_meta(&"steps", steps)
	_cached = actor
	return actor


func test_full_traversal_all_30_realms() -> void:
	var actor := _walked()
	var steps: Array = actor.get_meta(&"steps")
	assert_eq(steps.size(), TRANSITIONS, "walked every transition to the terminal realm")
	for index in range(steps.size()):
		var step: Dictionary = steps[index]
		assert_eq(step["ready"], true, "R%d entry legal" % [index + 1])
		assert_eq(step["resolved"], true, "resolved %s" % step["target"])
		assert_eq(step["rank"], step["target"], "advanced to %s" % step["target"])
		assert_eq(step["awarded"], true, "awarded for %s" % step["target"])
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, &"primordial_origin", "terminal reached")
	assert_eq(RealmDefaults.ladder().next(&"primordial_origin"), null, "no realm after R30")


func test_r18_to_r19_has_no_circular_prerequisite() -> void:
	var steps: Array = _walked().get_meta(&"steps")
	# Transition 18 is spirit_ascension -> earth_immortal (R18 -> R19).
	var step: Dictionary = steps[17]
	assert_eq(step["target"], &"earth_immortal", "transition 18 targets R19")
	assert_eq(step["anchor_before"], &"", "no inside-world anchor before the R19 attempt")
	assert_eq(step["resolved"], true, "R19 resolved without a prior anchor")
	# R19 committed the Seed anchor, which R20 then sees as a prior commitment.
	assert_eq(steps[18]["anchor_before"], InsideWorld.SEED, "R20 sees the Seed anchor")


func test_r27_to_r28_has_no_circular_prerequisite() -> void:
	var steps: Array = _walked().get_meta(&"steps")
	# Transition 27 is immortal_sovereign -> transcendent (R27 -> R28).
	var step: Dictionary = steps[26]
	assert_eq(step["target"], &"transcendent", "transition 27 targets R28")
	assert_eq(step["world_before"], &"", "no created world before the R28 attempt")
	assert_eq(step["resolved"], true, "R28 resolved without a prior world")
	# R28 committed the Micro world, which R29 then requires.
	assert_eq(steps[27]["world_before"], WorldState.MICRO, "R29 sees the Micro world")


func test_r30_refuses_another_advance() -> void:
	var steps: Array = _walked().get_meta(&"steps")
	assert_eq(steps[steps.size() - 1]["rank"], &"primordial_origin", "walk ended at R30")
	var actor := _actor()
	actor.set_path(PathState.new(MindPath.PATH_ID, &"primordial_origin"))
	var preview := MindAdvancement.preview(actor)
	assert_eq(preview.get("ready"), false, "R30 cannot advance further")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(MindAdvancement.try_breakthrough(actor, rng), false, "advance refused at R30")


func test_blocked_attempt_has_no_effect() -> void:
	var actor := _actor()
	# No pill, no work, untrained channels: nothing may be consumed or granted.
	var will_before := actor.stats.get_base(Stat.WILL)
	var rank_before := actor.path(MindPath.PATH_ID).rank_id
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	assert_eq(MindAdvancement.try_breakthrough(actor, rng), false, "blocked attempt refused")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, rank_before, "rank unchanged")
	assert_eq(actor.stats.get_base(Stat.WILL), will_before, "no reward granted")


## A deviation is mental failure: the realm is kept, the sea clouds, and one
## channel is injured. All of it must be recoverable at the same realm.
func test_failure_is_recoverable_without_a_higher_realm() -> void:
	# Find a seed whose roll loses, so the deviation path runs deterministically
	# instead of depending on luck. Each probe is fully prepared, so the roll is
	# the only thing deciding the outcome. Tests own RNG.
	var failing_seed := 0
	for candidate in range(1, 64):
		var probe := _actor()
		_prepare(probe)
		var trial := RandomNumberGenerator.new()
		trial.seed = candidate
		if not MindAdvancement.try_breakthrough(probe, trial):
			failing_seed = candidate
			break
	assert_eq(failing_seed > 0, true, "found a deterministic losing roll")

	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	_prepare(actor)
	var rng := RandomNumberGenerator.new()
	rng.seed = failing_seed
	assert_eq(MindAdvancement.try_breakthrough(actor, rng), false, "the attempt deviated")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, &"qi_refining", "failure kept the rank")
	assert_eq(sea.turbulence > 0.0, true, "the deviation clouded the sea")
	assert_eq(
		sea.effective_capacity() < sea.structural_capacity,
		true,
		"turbulence shrank usable capacity"
	)
	# Meditation is the Mind system's recovery and needs no higher realm.
	while sea.turbulence > 0.0:
		MindTraining.meditate(actor, 1.0)
	assert_eq(sea.turbulence, 0.0, "meditation clears turbulence")
	assert_eq(sea.effective_capacity(), sea.structural_capacity, "usable capacity restored")
	# The deviation injured a channel; training repairs it and keeps attainment.
	var source_seed := MindRealmSeed.for_realm(&"qi_refining")
	var injured := 0
	for def in MeridianDefaults.all():
		var channel := actor.meridians.get_meridian(def.id)
		if channel == null or not channel.is_injured():
			continue
		injured += 1
		var state_before: StringName = channel.state
		_stock(actor, source_seed.training_item)
		assert_eq(MindTraining.train_channel(actor, def.id), true, "training repairs %s" % def.id)
		var repaired := actor.meridians.get_meridian(def.id)
		assert_eq(repaired.is_injured(), false, "no longer injured")
		assert_eq(repaired.state, state_before, "structural attainment preserved")
	assert_eq(injured > 0, true, "the deviation burned a channel")
	# Recovery is complete enough to attempt and succeed again.
	_prepare(actor)
	var retry := RandomNumberGenerator.new()
	retry.seed = 42
	assert_eq(MindAdvancement.try_breakthrough(actor, retry), true, "retry after recovery")
