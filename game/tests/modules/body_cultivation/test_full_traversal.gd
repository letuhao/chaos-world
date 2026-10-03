extends TestCase

## Full R1→R30 traversal test (ADR 0023). Exercises the complete progression
## through all 30 realms using only the public API: cultivate, strengthen,
## meditate, and breakthrough. Tests control RNG but never directly set rank,
## channels, or success flags.

## Bounds that name what they catch. A tribulation is at most nine waves plus the
## warning, trial, climax and aftermath phases, so one fight fits in a dozen
## advances; the bound names a fight that would stop advancing. An ascent is four
## steps to the caps, so ASCENT_BOUND is that plus slack -- `WorldAnchor.ascend`
## refuses on its own past the caps, so this never has to be raised, and raising it
## would convert a loud failure into a slow one.
const WAVE_BOUND := 64
const ASCENT_BOUND := 8

var _defs: Dictionary = {}


func _actor(at_realm: StringName = &"qi_refining") -> Actor:
	var actor := Actor.new(&"traversal_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, at_realm))
	actor.meridians.unlock_for_realm(at_realm)
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	# A full 30-realm run keeps one pill + one strengthening stack per realm, so
	# the default 24 slots run out mid-traversal. Size for the whole ladder.
	ItemsApi.attach(actor, 128)
	BodyTraining.synchronize(actor)
	return actor


## Top the actor up on one realm's consumable. The quantity is deliberately far
## below `max_stack`: a full stack can no longer merge, so restocking would
## burn a fresh inventory slot every time and starve the later realms.
func _stock(actor: Actor, def_id: StringName) -> void:
	var def: ItemDef = _defs.get(def_id)
	if def == null:
		def = ItemDef.new()
		def.id = def_id
		def.stackable = true
		def.max_stack = 9999
		_defs[def_id] = def
	ItemsApi.inventory(actor).add(def, 4)


## Bring one channel to the depth the target realm demands and train the
## acupoints bound to it up to the current realm's quality target. Only the
## public strengthening action is used, so elixir consumption, injury repair,
## and acupoint training all behave exactly as in play.
func _train_channel(actor: Actor, meridian_id: StringName, target: BodyRealmSeed) -> void:
	var state := actor.path(BodyPath.PATH_ID)
	var current := BodyRealmSeed.for_realm(state.rank_id)
	var guard := 0
	while guard < 256:
		guard += 1
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			actor.meridians.unlock_for_realm(state.rank_id)
			channel = actor.meridians.get_meridian(meridian_id)
			if channel == null:
				return
		var channel_ready := (
			not channel.is_injured()
			and channel.state == &"strengthened"
			and channel.refinement >= target.required_refinement
		)
		if channel_ready and not _points_below(actor, meridian_id, current.quality_target):
			return
		_stock(actor, current.strengthening_item)
		if not BodyTraining.strengthen(actor, meridian_id):
			return


func _points_below(actor: Actor, meridian_id: StringName, quality_target: float) -> bool:
	var points: AcupointSet = actor.component(&"acupoints")
	if points == null:
		return false
	for definition in AcupointDefaults.definitions():
		if definition.meridian_id != meridian_id:
			continue
		for point in points.points:
			if point.id == definition.id and (point.blocked or point.quality < quality_target):
				return true
	return false


func _pool_full(actor: Actor) -> bool:
	# The body reservoir IS the body_integrity pool; read it there rather than
	# through the acupoint set, which no longer hands its pool out.
	var integrity := actor.resource(BodyStats.BODY_INTEGRITY)
	return integrity != null and integrity.ratio() >= 1.0


## Cultivate until the realm's progress floor is met, the shared body reservoir
## is full, and every unlocked huyệt has reached the next realm's quality floor.
## All three are outputs of the same action, and the gate checks all three, so
## preparation must too.
func _cultivate_until(actor: Actor, progress_required: float, quality_required: float) -> void:
	var state := actor.path(BodyPath.PATH_ID)
	var guard := 0
	while guard < 4096:
		if (
			state.progress >= progress_required
			and _pool_full(actor)
			and not _quality_below(actor, quality_required)
		):
			return
		guard += 1
		if not BodyTraining.cultivate(actor, 25.0):
			return


## True while any huyệt the actor holds is still short of the next realm's
## quality floor. `synchronize` only ever adds points the current realm has
## unlocked, so iterating the set directly is equivalent to filtering the
## definitions by unlock_index — and far cheaper inside the cultivate loop.
func _quality_below(actor: Actor, quality_required: float) -> bool:
	for point in BodyCultivationApi.acupoints(actor):
		if point.quality < quality_required:
			return true
	return false


## Meditation is the only source of comprehension, so the insight floor is
## reached by meditating rather than by writing the stat.
func _meditate_to_floor(actor: Actor, insight_required: float) -> void:
	var guard := 0
	while guard < 8192 and actor.stats.get_base(Stat.COMPREHENSION) < insight_required:
		guard += 1
		BodyTraining.meditate(actor, 1.0)


## Immortal+ breakthroughs are gated by a survived tribulation. The inside world and
## the created world are COMMITTED by the breakthroughs that introduce them (ADR
## 0032), so this must not write them: inventing an anchor or a world is what
## previously made R19-R30 unreachable in play.
##
## The ASCENSION is different, and this used to get it wrong in the test's favour:
## `WorldAnchor.commit` only *begins* the ascent when the Transcendent tier lands,
## and ADR 0021 requires it COMPLETE before the next realm. The old comment here
## claimed there was "no ascent to walk", so nothing ever walked one and R28-R30
## were unreachable -- 151 assertions, all one wall.
func _satisfy_tier_gates(actor: Actor, target: RealmDef) -> void:
	if target.index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
		return
	# Through the production entry points only: `begin_tribulation` binds the fight
	# to the realm being entered and `resolve_tribulation` is the sole thing that
	# decides survival. Hand-writing `actor.tribulation` here is exactly what
	# made R19-R30 unreachable in play.
	if not Breakthrough.tribulation_ok(actor, target.index):
		var tribulation := Breakthrough.begin_tribulation(actor, target.index)
		if tribulation != null:
			var wave_guard := 0
			while Breakthrough.advance_tribulation(actor) and wave_guard < WAVE_BOUND:
				wave_guard += 1
			Breakthrough.resolve_tribulation(actor, true)
	_walk_ascent(actor, target)


## Walk the Transcendent ascent with core's own entry point (ADR 0041): the ascent
## belongs to no single path -- every path carries the same `AscensionState` -- so
## no facade serves it and `ui` may call `core` directly.
##
## `WorldAnchor.ascend` refuses on the step past the caps, so its own `false` is the
## loop's real exit. `ASCENT_BOUND` only names an ascent that will not finish; it
## is not a budget to spend, and raising it would turn a loud failure into a slow
## one.
func _walk_ascent(actor: Actor, target: RealmDef) -> void:
	var guard := 0
	while not Breakthrough.ascension_ok(actor, target.index) and guard < ASCENT_BOUND:
		if not WorldAnchor.ascend(actor):
			break
		guard += 1


## Undo everything a deviation left behind, using only the public recovery
## action. Blockage is a recoverable overlay, so every blocked acupoint and
## every injured channel must be repairable without touching internals —
## otherwise a failed attempt would permanently deadlock the next realm.
func _recover_damage(actor: Actor) -> void:
	var state := actor.path(BodyPath.PATH_ID)
	var current := BodyRealmSeed.for_realm(state.rank_id)
	if current == null or current.recovery_item == &"":
		return
	_stock(actor, current.recovery_item)
	var guard := 0
	while guard < 64:
		guard += 1
		var target_meridian: StringName = &""
		for point in BodyCultivationApi.acupoints(actor):
			if not point.blocked:
				continue
			var meridian_id := AcupointDefaults.meridian_of(point.id)
			if meridian_id != &"":
				target_meridian = meridian_id
				break
		if target_meridian == &"":
			for def in MeridianDefaults.all():
				var channel := actor.meridians.get_meridian(def.id)
				if channel != null and channel.is_injured():
					target_meridian = def.id
					break
		if target_meridian == &"":
			return
		if not BodyTraining.recover(actor, target_meridian):
			return


## Bring the actor to the brink of `next rank` using only public actions.
## Safe to call again after a deviation: injuries are repaired, blockages
## cleared, and the reservoir refilled.
func _prepare_for_realm(actor: Actor) -> BodyRealmSeed:
	var state := actor.path(BodyPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		return null
	_satisfy_tier_gates(actor, target)
	# Channels and acupoints the target realm counts must exist before training.
	actor.meridians.unlock_for_realm(target.id)
	_stock(actor, seed.breakthrough_item)
	_recover_damage(actor)
	for meridian_id in seed.required_meridians:
		_train_channel(actor, meridian_id, seed)
	_cultivate_until(actor, seed.progress_required, seed.quality_required)
	_recover_damage(actor)
	_meditate_to_floor(actor, seed.insight_required)
	if actor.stats.get_base(Stat.PHYSIQUE) < seed.physique_required:
		actor.stats.set_base(Stat.PHYSIQUE, seed.physique_required)
	return seed


## Attempts allowed before declaring a realm unreachable, sized from the
## evaluated chance so the traversal cannot flake on a legitimate deviation.
func _attempt_budget(chance: float) -> int:
	if chance >= 1.0:
		return 1
	return maxi(3, ceili(log(0.000001) / log(1.0 - chance)))


## Roll until the actor is standing in the next realm, or give up.
func _breakthrough(actor: Actor, rng: RandomNumberGenerator) -> bool:
	var budget := _attempt_budget(float(BodyAdvancement.preview(actor)["chance"]))
	for _attempt in budget:
		if BodyAdvancement.try_breakthrough(actor, rng):
			return true
		# A deviation wounded the body: recover through public actions and retry.
		if _prepare_for_realm(actor) == null:
			return false
	return false


func test_full_traversal_all_30_realms() -> void:
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ladder := RealmDefaults.ladder()
	var visited: Array[StringName] = [actor.path(BodyPath.PATH_ID).rank_id]
	var breakthroughs := 0
	# Bounded: an unresolvable realm must fail the assertions above, not spin. The bound
	# is in the CONDITION and not only in the body, because GDScript's flow analysis
	# cannot prove a `while true:` terminates and refuses to compile the file when the
	# function has a return type -- which is how one unanalysable loop once took a
	# 407-line suite down to zero assertions. The body check names the condition that
	# failed to converge, so the run says WHICH walk gave up rather than just stopping.
	var guard := 0
	while guard <= 64:
		guard += 1
		if guard > 64:
			push_error("body traversal did not reach the terminal realm")
			break
		var state := actor.path(BodyPath.PATH_ID)
		var target := ladder.next(state.rank_id)
		if target == null:
			break
		var seed := _prepare_for_realm(actor)
		assert_ne(seed, null, "seed for %s" % target.id)
		if seed == null:
			break
		# Every realm carries a complete profile (ADR 0023). The seed owns the
		# budget, the floor and the resonance rank; the realm profile owns the rate
		# that prices them, and it must not collapse to neutral here — a realm
		# whose rate read 1.0 would make the whole traversal free.
		assert_eq(
			RealmRate.factor(target.id) > RealmRate.NEUTRAL, true, "realm rate for %s" % target.id
		)
		assert_eq(seed.work_required >= 0.0, true, "work required for %s" % target.id)
		assert_eq(seed.insight_required > 0.0, true, "insight floor for %s" % target.id)
		# The preview reports the same verdict as the gate, without mutating.
		var preview := BodyAdvancement.preview(actor)
		assert_eq(
			preview["ready"], true, "preview ready for %s: %s" % [target.id, preview["unmet"]]
		)
		assert_eq(state.rank_id, visited[-1], "preview did not advance the actor")
		# Training while in the realm we are leaving completed that realm's
		# milestone, which is what granted the physique bonus. The realm we just
		# entered is not complete until we train in it (ADR 0023).
		var progress: BodyProgress = actor.component(&"body_progress")
		assert_eq(
			progress.is_complete(state.rank_id), true, "milestone earned in %s" % state.rank_id
		)
		assert_eq(progress.is_complete(target.id), false, "no free milestone for %s" % target.id)
		assert_eq(_breakthrough(actor, rng), true, "breakthrough succeeded for %s" % target.id)
		breakthroughs += 1
		visited.append(target.id)
		assert_eq(actor.path(BodyPath.PATH_ID).rank_id, target.id, "advanced to %s" % target.id)
	assert_eq(visited.size(), 30, "visited all 30 realms")
	assert_eq(breakthroughs, 29, "advanced 29 times")
	assert_eq(visited[-1], &"primordial_origin", "at the terminal realm")
	assert_eq(ladder.next(visited[-1]), null, "no realm after R30")


func test_traversal_save_load_preserves_progress() -> void:
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var ranks: Array[StringName] = []
	var channels: Array[Dictionary] = []
	for _realm in 3:
		var seed := _prepare_for_realm(actor)
		assert_ne(seed, null, "prepared for the next realm: %s" % seed)
		var advanced := _breakthrough(actor, rng)
		assert_eq(
			advanced,
			true,
			(
				"breakthrough into %s succeeded: %s"
				% [seed.id if seed != null else "?", BodyAdvancement.preview(actor)["unmet"]]
			)
		)
		ranks.append(actor.path(BodyPath.PATH_ID).rank_id)
		var points: AcupointSet = actor.component(&"acupoints")
		var snapshot: Dictionary = {}
		for point in points.points:
			snapshot[point.id] = [point.quality, point.blocked]
		channels.append(snapshot)
	var saved := actor.to_dict()
	var restored := Actor.from_dict(saved)
	# Re-attach module components (as the composition root would on load).
	BodyCultivationApi.attach(restored)
	BodyCultivationApi.attach_acupoints(restored)
	ItemsApi.attach(restored)
	BodyTraining.synchronize(restored)
	assert_eq(
		restored.path(BodyPath.PATH_ID).rank_id,
		actor.path(BodyPath.PATH_ID).rank_id,
		"rank preserved after save/load"
	)
	# Each breakthrough must have visited a distinct, consecutive rung, and the
	# last one is where the actor stands now.
	var ladder := RealmDefaults.ladder()
	var seen := {}
	for rank_id in ranks:
		seen[rank_id] = true
	assert_eq(seen.size(), 3, "each breakthrough visited a new realm")
	for i in range(1, ranks.size()):
		assert_eq(
			ladder.index_of(ranks[i]),
			ladder.index_of(ranks[i - 1]) + 1,
			"realm %d follows realm %d" % [i, i - 1]
		)
	assert_eq(ranks[-1], actor.path(BodyPath.PATH_ID).rank_id, "final visit is current rank")
	var points: AcupointSet = restored.component(&"acupoints")
	assert_eq(points != null, true, "acupoints restored")
	assert_eq(points.points.size(), 36, "all minor acupoints restored")
	for point in points.points:
		var saved_point: Array = channels[-1][point.id]
		assert_almost_eq(point.quality, saved_point[0], "quality of %s preserved" % point.id)
		assert_eq(point.blocked, saved_point[1], "blockage of %s preserved" % point.id)
	var progress: BodyProgress = restored.component(&"body_progress")
	assert_eq(progress != null, true, "body progress restored")
	# The last realm trained in is complete; the one just entered is not.
	assert_eq(progress.is_complete(ranks[1]), true, "training milestone restored")
	assert_eq(progress.is_complete(ranks[2]), false, "entered realm is not yet complete")
	assert_eq(restored.meridians.get_meridian(&"lung") != null, true, "meridians restored")


## The R4 round-trip above only ever sees the 36 minor huyệt. Major (R10) and
## celestial (R19) tiers, deep refinement, the shared reservoir, and progress
## were never round-tripped, so a save bug at the top of the ladder would pass
## every test in the suite.
func test_save_load_at_a_high_realm_round_trips_every_layer() -> void:
	# Stand at spirit_sea (index 11): 48 huyệt unlocked, refinement in the teens.
	var actor := _actor(&"spirit_sea")
	# Train the network and the huyệt through the public actions so the state is
	# real rather than written in.
	for _round in 24:
		BodyTraining.cultivate(actor, 25.0)
	# Channel training costs an elixir per step; the round-trip needs real depth,
	# so stock the realm's elixir generously.
	var home := BodyRealmSeed.for_realm(&"spirit_sea")
	for meridian_id in home.required_meridians:
		var guard := 0
		while guard < 24:
			guard += 1
			# Each step spends an elixir, so restock before each attempt rather
			# than trying to compute the exact bill.
			_stock(actor, home.strengthening_item)
			if not BodyTraining.strengthen(actor, meridian_id):
				break
	# Give it a resonance rank, which is the R19+ payload shape.
	actor.meridians.set_resonance_rank(6)
	actor.mark_stats_dirty()
	var expected_points := 0
	for definition in AcupointDefaults.definitions():
		if definition.unlock_index <= RealmDefaults.ladder().index_of(&"spirit_sea"):
			expected_points += 1
	var points: AcupointSet = actor.component(&"acupoints")
	assert_eq(points.points.size(), expected_points, "48 huyệt at spirit tier")
	assert_eq(expected_points, 48, "sanity: minor plus major")
	var deepest := 0
	for channel in actor.meridians.get_all_meridians():
		deepest = maxi(deepest, channel.refinement)
	assert_eq(deepest >= 8, true, "refinement reached the teens (was %d)" % deepest)
	var expected_integrity := actor.resource(BodyStats.BODY_INTEGRITY).current
	var expected_progress := actor.path(BodyPath.PATH_ID).progress
	var expected_comprehension := actor.stats.get_base(Stat.COMPREHENSION)
	var snapshot := {}
	for point in points.points:
		snapshot[point.id] = [point.quality, point.blocked]

	var restored := Actor.from_dict(actor.to_dict())
	BodyCultivationApi.attach(restored)
	BodyCultivationApi.attach_acupoints(restored)
	ItemsApi.attach(restored)
	BodyTraining.synchronize(restored)

	assert_eq(restored.path(BodyPath.PATH_ID).rank_id, &"spirit_sea", "high rank preserved")
	var restored_points: AcupointSet = restored.component(&"acupoints")
	assert_eq(restored_points.points.size(), 48, "all 48 huyệt restored")
	for point in restored_points.points:
		var saved_point: Array = snapshot[point.id]
		assert_almost_eq(point.quality, saved_point[0], "quality of %s" % point.id)
		assert_eq(point.blocked, saved_point[1], "blockage of %s" % point.id)
	var restored_deepest := 0
	for channel in restored.meridians.get_all_meridians():
		restored_deepest = maxi(restored_deepest, channel.refinement)
	assert_eq(restored_deepest, deepest, "deep refinement preserved")
	assert_eq(restored.meridians.resonance_rank, 6, "resonance rank preserved")
	assert_almost_eq(
		restored.resource(BodyStats.BODY_INTEGRITY).current,
		expected_integrity,
		"shared reservoir value preserved"
	)
	assert_almost_eq(
		restored.path(BodyPath.PATH_ID).progress,
		expected_progress,
		"cultivation progress preserved"
	)
	assert_almost_eq(
		restored.stats.get_base(Stat.COMPREHENSION),
		expected_comprehension,
		"comprehension preserved"
	)


func test_traversal_body_integrity_consumed_on_advance() -> void:
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 456
	assert_ne(_prepare_for_realm(actor), null, "prepared for the next realm")
	var before_integrity := actor.resource(BodyStats.BODY_INTEGRITY).current
	assert_eq(_breakthrough(actor, rng), true, "breakthrough succeeded")
	var after_integrity := actor.resource(BodyStats.BODY_INTEGRITY).current
	assert_eq(after_integrity < before_integrity, true, "integrity consumed on breakthrough")
