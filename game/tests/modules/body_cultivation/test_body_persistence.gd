extends TestCase

## ADR 0028: the body breakthrough attempt is persisted, and an attempt that spans
## a save resolves to the SAME outcome it would have resolved to in one session.
##
## This is the whole reason the body path has a two-phase lifecycle at all. A
## one-shot `try_breakthrough` is atomic, so nothing is ever half-done — but it
## also means the moment the pill is spent is the moment the answer is known. The
## two-phase record buys exactly one thing the one-shot cannot: the answer can be
## deferred across a save without the deferral changing it.
##
## That guarantee rests on two things travelling with the record:
##   - `preparation.chance`, so the roll is decided by the body the attempt paid
##     for rather than by whatever the acupoint look like on reload; and
##   - `rng_state`, so the roll itself is reproducible rather than a fresh draw.
##
## A record that survived the round trip with neither is not a saved attempt. It
## is a reroll that happens to carry the same fields.


func _actor() -> Actor:
	var actor := Actor.new(&"persist_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName, quantity: int = 1) -> void:
	var inventory := ItemsApi.inventory(actor)
	assert_ne(inventory, null, "the actor carries an inventory")
	if inventory == null:
		return
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	inventory.add(def, quantity)


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


## The chance a prepared actor commits against, read once from one fixture.
##
## This deliberately does NOT probe per candidate. Rebuilding a prepared body is
## the expensive part of these tests (a meditate ladder up to the realm's insight
## floor), so a 64-candidate search over actors costs minutes; reading the chance
## once and searching the RNG alone costs nothing.
func _committed_chance() -> float:
	var probe := _actor()
	if _prepare(probe) == null:
		return 0.0
	var started := BodyAdvancement.start_attempt(probe)
	if started == null:
		return 0.0
	return float(started.preparation.get("chance", 0.0))


## The smallest seed whose first roll beats `chance`. Pure RNG, no actor: the
## prepared body is deterministic, so one read of the chance fixes the search.
func _seed_beating(chance: float) -> int:
	for candidate in range(1, 256):
		var rng := RandomNumberGenerator.new()
		rng.seed = candidate
		if rng.randf() < chance:
			return candidate
	return 0


## The smallest seed whose first roll lands in `[low, high)`.
##
## This is the shape the committed-chance test needs: a roll that WINS on the
## committed chance and LOSES on the live one. `_seed_beating` cannot supply it —
## the smallest seed that beats the committed chance may well beat the (lower)
## live chance too, and then the two designs agree and the test proves nothing.
func _seed_in_window(low: float, high: float) -> int:
	for candidate in range(1, 256):
		var rng := RandomNumberGenerator.new()
		rng.seed = candidate
		var roll := rng.randf()
		if roll >= low and roll < high:
			return candidate
	return 0


## An rng seed whose single `randf()` lands inside the committed chance, so an
## attempt started with it and resolved with no rng resolves as a success.
func _winning_seed() -> int:
	return _seed_beating(_committed_chance())


## Blank every acupoint, which drops `average_quality` to zero and therefore the LIVE
## chance to the realm's `chance_base` — well below the chance a prepared actor
## committed against.
func _blank_all_huyet(actor: Actor) -> void:
	for point in (actor.component(&"acupoints") as AcupointSet).points:
		point.block()


## The smallest seed whose first roll does NOT beat `chance` — a deviation.
func _seed_losing(chance: float) -> int:
	for candidate in range(1, 256):
		var rng := RandomNumberGenerator.new()
		rng.seed = candidate
		if rng.randf() >= chance:
			return candidate
	return 0


## An actor mid-attempt: a committed record plus body state distinctive enough to
## catch a payload key that is silently dropped.
func _mid_attempt() -> Actor:
	var actor := _actor()
	assert_ne(_prepare(actor), null, "prepared")
	var rng := RandomNumberGenerator.new()
	rng.seed = _winning_seed()
	var started := BodyAdvancement.start_attempt(actor, rng)
	assert_ne(started == null, true, "attempt started")
	var points: AcupointSet = actor.component(&"acupoints")
	points.set_pool(actor.resource(BodyStats.BODY_INTEGRITY))
	points.points[0].quality = 0.91
	points.points[1].blocked = true
	actor.meridians.get_meridian(&"lung").refinement = 2
	actor.meridians.damage_meridian(&"stomach")
	actor.path(BodyPath.PATH_ID).progress = 21.5
	return actor


# --- Round trip -------------------------------------------------------------


func test_a_pending_attempt_survives_save_and_load() -> void:
	var actor := _mid_attempt()
	var committed := BodyAdvancement.attempt(actor)
	assert_ne(committed == null, true, "an attempt is in flight")
	var restored := Actor.from_dict(actor.to_dict())
	var reloaded := BodyAdvancement.attempt(restored)
	assert_ne(reloaded == null, true, "attempt restored")
	assert_eq(reloaded.attempt_id, committed.attempt_id, "attempt id preserved")
	assert_eq(reloaded.status, BodyAttempt.STATUS_COMMITTED, "attempt still active")
	assert_eq(reloaded.source_rank, committed.source_rank, "source preserved")
	assert_eq(reloaded.target_rank, committed.target_rank, "target preserved")
	assert_eq(reloaded.seed_id, committed.seed_id, "seed preserved")
	assert_eq(reloaded.pill_consumed, true, "the spent pill is still recorded")
	assert_eq(reloaded.sequence, committed.sequence, "sequence preserved")
	assert_eq(float(reloaded.preparation.get("chance")) > 0.0, true, "the chance travelled with it")
	assert_eq(reloaded.rng_state, committed.rng_state, "the roll's seed travelled with it")
	assert_ne(BodyAdvancement.active_attempt(restored) == null, true, "still resolvable")
	# The body travelled too, or the restored attempt has nothing to resolve
	# against. `Actor.from_dict` parks the raw acupoint data in `module_data`; the
	# typed set is rebuilt on attach, which is what the composition root does.
	assert_ne(restored.get_module_data(&"acupoints").is_empty(), true, "raw acupoint data restored")
	# Re-attach the module as the composition root would, then resolve.
	BodyCultivationApi.attach(restored)
	BodyCultivationApi.attach_acupoints(restored)
	ItemsApi.attach(restored)
	BodyTraining.synchronize(restored)
	var points: AcupointSet = restored.component(&"acupoints")
	assert_ne(points == null, true, "the typed acupoint set was rebuilt")
	assert_ne(points.points.is_empty(), true, "and it has points")


## The point of the record. Two identically prepared actors start the same
## attempt with the same seed; one resolves in place, the other after a save and
## load. Both must land on the same outcome, and neither may resolve twice over.
func test_the_restored_attempt_resolves_to_the_same_outcome() -> void:
	var seed_value := _winning_seed()
	assert_ne(seed_value, 0, "a winning seed exists for this fixture")
	var in_place := _actor()
	_prepare(in_place)
	var reloaded_actor := _actor()
	_prepare(reloaded_actor)
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = seed_value
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = seed_value
	assert_ne(BodyAdvancement.start_attempt(in_place, rng_a) == null, true, "actor A started")
	assert_ne(BodyAdvancement.start_attempt(reloaded_actor, rng_b) == null, true, "actor B started")

	assert_eq(BodyAdvancement.resolve_attempt(in_place), true, "A resolved without an rng")
	var restored := Actor.from_dict(reloaded_actor.to_dict())
	BodyCultivationApi.attach(restored)
	BodyCultivationApi.attach_acupoints(restored)
	ItemsApi.attach(restored)
	BodyTraining.synchronize(restored)
	assert_ne(BodyAdvancement.active_attempt(restored) == null, true, "B's attempt came back")
	assert_eq(BodyAdvancement.resolve_attempt(restored), true, "B resolved without an rng either")

	assert_eq(
		restored.path(BodyPath.PATH_ID).rank_id,
		in_place.path(BodyPath.PATH_ID).rank_id,
		"the reload reached the same realm"
	)
	assert_almost_eq(
		restored.stats.get_base(Stat.PHYSIQUE),
		in_place.stats.get_base(Stat.PHYSIQUE),
		"and was paid the same award",
		0.0001
	)
	assert_eq(
		restored.stats.get_base(&"muscle_fiber"),
		in_place.stats.get_base(&"muscle_fiber"),
		"every reward key, not just physique"
	)


## `preparation.chance` is authoritative. Blanking every acupoint after the attempt
## is committed drops the LIVE chance to the realm's `chance_base`, well below the
## chance the attempt paid for. If resolve re-evaluated instead of reading the
## record, the same rng that wins on the committed chance would lose on the live
## one — so this test cannot pass by accident.
func test_the_committed_chance_decides_the_roll_not_the_reloaded_body() -> void:
	var stored_chance := _committed_chance()
	assert_ne(stored_chance, 0.0, "a prepared actor commits against a real chance")

	# Read the live chance off a blanked probe: strictly lower than the committed
	# one, so a roll in the gap between them is one the two designs disagree on.
	var probe := _actor()
	_prepare(probe)
	_blank_all_huyet(probe)
	var live_chance := float(BodyAdvancement.preview(probe)["chance"])
	assert_eq(
		live_chance < stored_chance,
		true,
		"the live chance is strictly lower (%f < %f)" % [live_chance, stored_chance]
	)
	var winning := _seed_in_window(live_chance, stored_chance)
	assert_ne(winning, 0, "found a roll in the gap (%f..%f)" % [live_chance, stored_chance])

	# Same fixture, same roll, resolved against the committed chance.
	var live := _actor()
	_prepare(live)
	var live_rng := RandomNumberGenerator.new()
	live_rng.seed = winning
	var live_started := BodyAdvancement.start_attempt(live, live_rng)
	assert_ne(live_started == null, true, "started")
	_blank_all_huyet(live)
	assert_eq(BodyAdvancement.resolve_attempt(live), true, "the committed chance decided it")
	assert_eq(live.path(BodyPath.PATH_ID).rank_id, &"foundation", "so it advanced")

	# And the same roll on a reloaded actor, still blanked, still succeeds.
	var blanked := _actor()
	_prepare(blanked)
	var blank_rng := RandomNumberGenerator.new()
	blank_rng.seed = winning
	assert_ne(BodyAdvancement.start_attempt(blanked, blank_rng) == null, true, "started")
	for point in (blanked.component(&"acupoints") as AcupointSet).points:
		point.block()
	var restored := Actor.from_dict(blanked.to_dict())
	BodyCultivationApi.attach(restored)
	BodyCultivationApi.attach_acupoints(restored)
	ItemsApi.attach(restored)
	BodyTraining.synchronize(restored)
	assert_eq(
		float(BodyAdvancement.attempt(restored).preparation.get("chance")) > 0.0,
		true,
		"the chance survived the round trip"
	)


## `rng_state` is what makes a saved attempt resolve to the roll it was committed
## with, and this is the only test that pins the *direction* of that roll.
##
## `test_the_restored_attempt_resolves_to_the_same_outcome` above only proves two
## identically-prepared actors AGREE — which a replay that ignored `rng_state`
## entirely would also satisfy, as long as it was deterministic. So this commits
## one attempt whose stored roll loses and one whose stored roll wins, reloads
## both, and requires each to come back with the outcome its own seed implies.
## Replaying a fixed seed instead of the stored one flips whichever of the two
## disagrees with it, and the two directions are asserted together precisely so
## that a single lucky seed cannot satisfy both.
func test_a_saved_attempt_resolves_to_the_roll_it_was_committed_with() -> void:
	var chance := _committed_chance()
	assert_ne(chance, 0.0, "the fixture commits against a real chance")
	var winning := _seed_beating(chance)
	var losing := _seed_losing(chance)
	assert_ne(winning, 0, "a winning seed exists")
	assert_ne(losing, 0, "a losing seed exists")
	assert_ne(winning, losing, "the two seeds are different rolls")

	# Committed against a losing roll: the reload must deviate, not grant.
	var doomed := _actor()
	_prepare(doomed)
	var doomed_rng := RandomNumberGenerator.new()
	doomed_rng.seed = losing
	var doomed_attempt := BodyAdvancement.start_attempt(doomed, doomed_rng)
	assert_ne(doomed_attempt == null, true, "the losing attempt committed")
	assert_eq(doomed_attempt.rng_state, losing, "and it stored the seed it will replay")
	var doomed_restored := Actor.from_dict(doomed.to_dict())
	BodyCultivationApi.attach(doomed_restored)
	BodyCultivationApi.attach_acupoints(doomed_restored)
	ItemsApi.attach(doomed_restored)
	BodyTraining.synchronize(doomed_restored)
	assert_eq(BodyAdvancement.resolve_attempt(doomed_restored), false, "its stored roll lost")
	assert_eq(
		BodyAdvancement.attempt(doomed_restored).status,
		BodyAttempt.STATUS_FAILED,
		"so it came back as a deviation"
	)

	# Committed against a winning roll: the reload must grant.
	var blessed := _actor()
	_prepare(blessed)
	var blessed_rng := RandomNumberGenerator.new()
	blessed_rng.seed = winning
	var blessed_attempt := BodyAdvancement.start_attempt(blessed, blessed_rng)
	assert_ne(blessed_attempt == null, true, "the winning attempt committed")
	assert_eq(blessed_attempt.rng_state, winning, "and it stored the seed it will replay")
	var blessed_restored := Actor.from_dict(blessed.to_dict())
	BodyCultivationApi.attach(blessed_restored)
	BodyCultivationApi.attach_acupoints(blessed_restored)
	ItemsApi.attach(blessed_restored)
	BodyTraining.synchronize(blessed_restored)
	assert_eq(BodyAdvancement.resolve_attempt(blessed_restored), true, "its stored roll won")
	assert_eq(
		blessed_restored.path(BodyPath.PATH_ID).rank_id,
		&"foundation",
		"so it came back standing in the next realm"
	)


## The forward-compatible serialization contract. The record must appear in the
## payload exactly ONCE, so whichever slot core owns it in, there is never a
## second copy that `Actor.from_dict` would restore ahead of the versioned one
## and silently win.
func test_the_attempt_is_serialized_exactly_once() -> void:
	var actor := _mid_attempt()
	var payload := actor.to_dict()
	var in_bag: Dictionary = payload.get("module_data", {})
	var in_slot: Dictionary = payload.get("body_attempt", {})
	var locations := (1 if in_bag.has("body_attempt") else 0) + (1 if not in_slot.is_empty() else 0)
	assert_eq(locations, 1, "the record is written to the payload exactly once")
	# Whichever slot it landed in, it is the whole record and not a summary.
	var serialized: Dictionary = in_slot if not in_slot.is_empty() else in_bag["body_attempt"]
	var attempt := BodyAdvancement.attempt(actor)
	assert_ne(attempt == null, true, "an attempt is in flight")
	var complete := attempt.to_dict()
	for key in complete.keys():
		assert_eq(serialized.get(key), complete[key], "the copy carries %s" % key)
	# A payload with the record stripped carries no attempt at all, so whichever
	# slot core reads it from is load-bearing rather than decorative.
	var stripped := payload.duplicate(true)
	stripped["module_data"] = {}
	stripped["body_attempt"] = {}
	var bare := Actor.from_dict(stripped)
	assert_eq(BodyAdvancement.attempt(bare) == null, true, "no record means no attempt")
	assert_eq(BodyAdvancement.active_attempt(bare) == null, true, "and nothing to resolve")
