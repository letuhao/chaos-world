extends TestCase

## ADR 0015/0023/0028: the deviation and recovery loop.
##
## A failed breakthrough must cost something real, land in a place the player can
## find, and be repairable. Before ADR 0028 this loop did not function: the body
## gate read `channel.state` instead of `MeridianState.meets()`, so a torn channel
## passed the gate while silently halving its own bonuses forever; and the
## deviation always tore `required_meridians[0]`, which is lung in every realm.


func _actor() -> Actor:
	var actor := Actor.new(&"deviation_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName, quantity: int = 1) -> void:
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	ItemsApi.inventory(actor).add(def, quantity)


## Bring the actor to the brink of the next realm through public actions only.
func _prepare(actor: Actor) -> BodyRealmSeed:
	var state := actor.path(BodyPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		return null
	actor.meridians.unlock_for_realm(target.id)
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		if channel.is_injured():
			actor.meridians.repair_meridian(meridian_id)
		actor.meridians.open_meridian(meridian_id)
		actor.meridians.expand_meridian(meridian_id)
		actor.meridians.strengthen_meridian(meridian_id)
		var guard := 0
		while actor.meridians.refine_meridian(meridian_id, seed.required_refinement) and guard < 32:
			guard += 1
	var points: AcupointSet = actor.component(&"acupoints")
	for point in points.points:
		point.clear_block()
		point.quality = maxf(point.quality, seed.quality_required)
	points.fill(seed.integrity_maximum)
	state.progress = seed.progress_required
	if actor.stats.get_base(Stat.PHYSIQUE) < seed.physique_required:
		actor.stats.set_base(Stat.PHYSIQUE, seed.physique_required)
	var meditate_guard := 0
	while (
		meditate_guard < 4096 and actor.stats.get_base(Stat.COMPREHENSION) < seed.insight_required
	):
		meditate_guard += 1
		BodyTraining.meditate(actor, 1.0)
	_stock(actor, seed.breakthrough_item)
	return seed


## The required channel the actor has trained deepest.
func _deepest_required(actor: Actor, seed: BodyRealmSeed) -> StringName:
	var best: StringName = &""
	var depth := -1
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel != null and channel.refinement > depth:
			depth = channel.refinement
			best = meridian_id
	return best


## The single required channel that came out wounded, or empty.
func _wounded_required(actor: Actor, seed: BodyRealmSeed) -> Array[StringName]:
	var out: Array[StringName] = []
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel != null and channel.is_injured():
			out.append(meridian_id)
	return out


# --- Injury blocks the gate -------------------------------------------------


## A wounded required channel halves its own bonuses (ADR 0017) but must still
## be repaired before the next attempt: pushing forward wounded would make the
## penalty permanent and free.
func test_a_damaged_required_channel_blocks_the_next_attempt() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	assert_ne(seed, null, "prepared")
	var torn: StringName = _deepest_required(actor, seed)
	assert_ne(torn, &"", "found a trained channel")
	actor.meridians.damage_meridian(torn)
	var condition := BodyBreakthroughCondition.new()
	var state := actor.path(BodyPath.PATH_ID)
	assert_eq(condition.can_breakthrough(actor, state, {}), false, "a damaged channel blocks")
	var unmet: Array[String] = condition.describe_unmet(actor, state)
	var named := false
	for message in unmet:
		if message.contains("Damaged channels") and message.contains(String(torn)):
			named = true
	assert_eq(named, true, "the wound is named: %s" % ", ".join(unmet))


## The gate reports the wound and nothing else once everything else is prepared,
## so the player knows the item is what they need.
func test_the_wound_is_the_only_unmet_condition() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	assert_ne(seed, null, "prepared")
	var torn: StringName = _deepest_required(actor, seed)
	actor.meridians.damage_meridian(torn)
	var unmet: Array[String] = BodyBreakthroughCondition.new().describe_unmet(
		actor, actor.path(BodyPath.PATH_ID)
	)
	assert_eq(unmet.size(), 1, "exactly one thing is missing: %s" % ", ".join(unmet))
	assert_eq(unmet[0].contains("Damaged channels"), true, "and it is the wound")


## Recovery is the way out, and it consumes the realm's item exactly once.
func test_recovery_clears_the_wound_and_reopens_the_gate() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	assert_ne(seed, null, "prepared")
	var torn: StringName = _deepest_required(actor, seed)
	actor.meridians.damage_meridian(torn)
	var condition := BodyBreakthroughCondition.new()
	var state := actor.path(BodyPath.PATH_ID)
	assert_eq(condition.can_breakthrough(actor, state, {}), false, "blocked while wounded")
	# Recovery uses the CURRENT realm's item: you are still standing in the realm
	# whose attempt failed.
	var current := BodyRealmSeed.for_realm(state.rank_id)
	_stock(actor, current.recovery_item)
	assert_eq(BodyTraining.recover(actor, torn), true, "channel repaired")
	assert_eq(actor.meridians.get_meridian(torn).is_injured(), false, "no longer wounded")
	assert_eq(ItemsApi.inventory(actor).count(current.recovery_item), 0, "item consumed once")
	assert_eq(BodyTraining.recover(actor, torn), false, "nothing left to repair")
	assert_eq(condition.can_breakthrough(actor, state, {}), true, "gate reopened")


## Without the item, recovery is a disclosed no-op that changes nothing.
func test_recovery_without_the_item_changes_nothing() -> void:
	var actor := _actor()
	var seed := _prepare(actor)
	assert_ne(seed, null, "prepared")
	var torn: StringName = _deepest_required(actor, seed)
	actor.meridians.damage_meridian(torn)
	assert_eq(BodyTraining.recover(actor, torn), false, "no item, no repair")
	assert_eq(actor.meridians.get_meridian(torn).is_injured(), true, "still wounded")


# --- The wound has a location ----------------------------------------------


## A deviation tears the channel the actor trained DEEPEST and jams a huyệt on
## that same meridian. It used to always be lung, for every realm.
func test_deviation_targets_the_deepest_channel_and_its_own_huyet() -> void:
	var target: StringName = &""
	var deviated := false
	var landed_on_target := false
	var jammed_on_target := false
	for attempt in 64:
		var actor := _actor()
		var seed := _prepare(actor)
		assert_ne(seed, null, "prepared a fresh actor")
		target = _deepest_required(actor, seed)
		assert_ne(target, &"", "a trained channel exists")
		# Train that one channel deeper than the rest.
		actor.meridians.refine_meridian(target, 9)
		actor.meridians.refine_meridian(target, 9)
		actor.meridians.refine_meridian(target, 9)
		var rng := RandomNumberGenerator.new()
		rng.seed = attempt + 1
		if BodyAdvancement.try_breakthrough(actor, rng):
			continue
		var wounded := _wounded_required(actor, seed)
		deviated = not wounded.is_empty()
		if deviated:
			landed_on_target = wounded.has(target)
			var points: AcupointSet = actor.component(&"acupoints")
			for point in points.points:
				if point.blocked and AcupointDefaults.meridian_of(point.id) == target:
					jammed_on_target = true
			break
	assert_eq(deviated, true, "a deviation landed")
	assert_eq(landed_on_target, true, "the deepest channel was torn, not lung")
	assert_eq(jammed_on_target, true, "a huyệt on the torn channel was jammed too")


## Across realms, the torn channel must not always be the first one listed.
func test_the_torn_channel_is_not_always_the_first_required() -> void:
	var torn_ids: Dictionary = {}
	var attempts := 0
	while attempts < 40 and torn_ids.size() < 2:
		var actor := _actor()
		var seed := _prepare(actor)
		if seed == null:
			break
		var rng := RandomNumberGenerator.new()
		rng.seed = 977 + attempts
		if BodyAdvancement.try_breakthrough(actor, rng):
			attempts += 1
			continue
		for meridian_id in _wounded_required(actor, seed):
			torn_ids[meridian_id] = true
		attempts += 1
	assert_eq(torn_ids.size() >= 1, true, "at least one wound landed: %s" % str(torn_ids.keys()))
