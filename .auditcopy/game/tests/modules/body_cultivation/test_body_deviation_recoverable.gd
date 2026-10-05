extends TestCase

## BL-0286: a failed breakthrough must be recoverable. It was not.
##
## `BodyDeviationJam.random_open` — the fallback for a FAILED attempt — picked
## from every open huyệt, and `BodyTraining.recover` resolves the channel before it
## looks at the blockage. A jam on a meridian the actor has NOT unlocked therefore
## had no way out: `recover` refused it (no channel), `strengthen` refused it (no
## channel, so no elixir clears it either), `cultivate` skips a blocked point, and
## `BodyBreakthroughCondition._acupoints_ready` still graded its quality. One
## unlucky failure could end the path.
##
## The eligibility rule is asserted directly against the two doors, because the
## unfiltered one is the fallback and no amount of rolling reaches it
## deterministically. The rule is not "the first huyệt on a torn channel": it is
## "a huyệt whose meridian is ON the actor's network", and every assertion here
## states that.

const SWEEP_SEEDS := 8


func _actor_at(realm_id: StringName) -> Actor:
	var actor := Actor.new(&"recoverable", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, realm_id))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor, 32)
	BodyTraining.synchronize(actor)
	return actor


func _blocked(points: AcupointSet) -> Array[Acupoint]:
	var out: Array[Acupoint] = []
	for point in points.points:
		if point.blocked:
			out.append(point)
	return out


func _assert_jams_are_clearable(actor: Actor, where: String) -> int:
	var points: AcupointSet = actor.component(&"acupoints")
	var blocked := _blocked(points)
	for point in blocked:
		var meridian_id := AcupointDefaults.meridian_of(point.id)
		assert_ne(
			actor.meridians.get_meridian(meridian_id),
			null,
			(
				"%s jammed %s on %s, which the actor has not unlocked"
				% [where, String(point.id), String(meridian_id)]
			)
		)
	return blocked.size()


func _unmet(actor: Actor) -> Array:
	return BodyBreakthroughCondition.new().describe_unmet(actor, actor.path(BodyPath.PATH_ID))


## Whether any unmet condition names `fragment`. The wound and the jam are two
## lines on the gate and one must not be able to hide the other.
func _named(actor: Actor, fragment: String) -> bool:
	for message in _unmet(actor):
		if String(message).contains(fragment):
			return true
	return false


## Every bonus the network can pay: flow, capacity and power. A tear shows up in
## it and a jam does not, which is why they are asserted separately.
func _all_bonus(network: MeridianNetwork) -> float:
	return network.get_flow_bonus() + network.get_capacity_bonus() + network.get_power_bonus()


# --- Door 1: the unfiltered fallback ---------------------------------------


## The fallback that caused it: over every realm and several rolls, the huyệt it
## jams is always on a meridian the actor owns.
##
## R1 is where the old pool was worst: all 36 minor huyệt exist at ladder index 0
## and 24 of them sit on the eight primary meridians that only unlock at index 3
## and 6. Two thirds of that pool was unplayable.
func test_the_random_jam_never_lands_on_a_meridian_the_actor_lacks() -> void:
	var checked := 0
	for realm_def in RealmDefaults.ladder().realms():
		var actor := _actor_at(realm_def.id)
		var points: AcupointSet = actor.component(&"acupoints")
		for seed_index in SWEEP_SEEDS:
			for point in points.points:
				point.clear_block()
			BodyDeviationJam.random_open(actor, points, BodyPlayFixture.rng(seed_index + 1))
			checked += 1
			assert_eq(
				_assert_jams_are_clearable(actor, "R%d/%d" % [realm_def.index + 1, seed_index]),
				1,
				"every realm can still produce exactly one jam"
			)
	assert_eq(checked, 30 * SWEEP_SEEDS, "swept every realm")


## The fallback is reachable in play only once every huyệt on the torn channel is
## already blocked. Force that: pre-block lung's huyệt, then jam "on lung".
func test_the_fallback_reached_through_a_torn_channel_is_also_clearable() -> void:
	var actor := _actor_at(&"qi_refining")
	var points: AcupointSet = actor.component(&"acupoints")
	var lung_points := 0
	for point in points.points:
		if AcupointDefaults.meridian_of(point.id) == &"lung":
			lung_points += 1
			point.block()
	assert_eq(lung_points > 0, true, "lung has huyệt to exhaust")
	BodyDeviationJam.on_channel(actor, points, &"lung", BodyPlayFixture.rng(3))
	assert_eq(_assert_jams_are_clearable(actor, "forced fallback"), lung_points + 1, "it fell back")


## The second door, and the one the fallback's own filter cannot catch.
##
## Deleting `on_channel`'s "is this meridian on the network" check leaves the whole
## suite green: `_deepest_required_channel` cannot return a meridian the actor
## lacks today, so through `_deviate` the line is unreachable and therefore
## unpinned. It still has to stay, because a meridian with no channel on it can
## have huyệt bound to it — without the check `on_channel` jams those directly and
## the fallback's filter never runs. This asks for exactly that request.
func test_a_jam_asked_for_on_a_meridian_the_actor_lacks_falls_back() -> void:
	var actor := _actor_at(&"qi_refining")
	var points: AcupointSet = actor.component(&"acupoints")
	assert_eq(actor.meridians.get_meridian(&"liver"), null, "liver is not on an R1 network")
	var liver_points := 0
	for point in points.points:
		if AcupointDefaults.meridian_of(point.id) == &"liver":
			liver_points += 1
	assert_eq(liver_points > 0, true, "but R1 holds huyệt on liver")
	BodyDeviationJam.on_channel(actor, points, &"liver", BodyPlayFixture.rng(5))
	var blocked := _blocked(points)
	assert_eq(blocked.size(), 1, "exactly one jam")
	assert_eq(
		AcupointDefaults.meridian_of(blocked[0].id) != &"liver",
		true,
		"and not on liver, so the request fell back to the eligible pool"
	)
	assert_eq(
		_assert_jams_are_clearable(actor, "asked-for locked meridian"), 1, "and it is clearable"
	)


## The pool the rule depends on is never empty, so the rule cannot quietly make
## failure free. The minor tier always covers the four index-0 primary meridians,
## so an actor holding any huyệt at all holds a clearable one.
##
## The count is reported, not asserted equal to the set: an R1 actor holds 36
## huyệt and only 12 are clearable, which is BL-0286's other half — 24 huyệt it
## is graded on and can neither train nor heal individually. Closing THAT needs
## the huyệt data (`tools/cultivation/seed.py` writes `unlock_index = 0` on every
## minor point), not a rule.
func test_every_realm_keeps_a_clearable_jam_pool() -> void:
	for realm_def in RealmDefaults.ladder().realms():
		var actor := _actor_at(realm_def.id)
		var points: AcupointSet = actor.component(&"acupoints")
		var eligible := 0
		for point in points.points:
			if actor.meridians.get_meridian(AcupointDefaults.meridian_of(point.id)) != null:
				eligible += 1
		assert_eq(
			eligible > 0,
			true,
			(
				"R%d: %d of %d huyệt are clearable, which must never be zero"
				% [realm_def.index + 1, eligible, points.points.size()]
			)
		)


# --- The whole loop, through public actions ---------------------------------


## The acceptance shape: fail, be visibly worse off, pay to recover, advance.
func test_a_failed_attempt_is_worse_off_recoverable_and_then_advances() -> void:
	var play := BodyPlayFixture.new()
	var actor := play.actor(&"qi_refining")
	var seed := play.prepare(actor)
	assert_ne(seed, null, "prepared through public actions")
	var state := actor.path(BodyPath.PATH_ID)
	var points: AcupointSet = actor.component(&"acupoints")
	var progress_before := state.progress
	var essence_before := play.reservoir(actor).current
	var pills := ItemsApi.inventory(actor).count(seed.breakthrough_item)
	assert_eq(pills > 0, true, "the pill was stocked")

	assert_eq(play.deviate(actor), true, "the attempt failed and granted nothing")
	assert_eq(state.rank_id, &"qi_refining", "still in the realm it failed in")
	# Worse off: half the work, a quarter of the reservoir, the pill gone.
	assert_almost_eq(state.progress, progress_before * 0.5, "half the progress", 0.0001)
	assert_eq(play.reservoir(actor).current < essence_before, true, "body essence was torn out")
	assert_eq(
		ItemsApi.inventory(actor).count(seed.breakthrough_item),
		pills - 1,
		"the realm pill was spent and not refunded"
	)
	var jammed := _blocked(points)
	assert_eq(jammed.is_empty(), false, "a huyệt was jammed")
	assert_eq(_assert_jams_are_clearable(actor, "live deviation"), 1, "exactly one jam")
	assert_eq(BodyAdvancement.preview(actor)["ready"], false, "the gate is shut while wounded")

	# Recovering costs the realm's item and clears BOTH halves of the wound.
	var current := BodyRealmSeed.for_realm(state.rank_id)
	play.stock(actor, current.recovery_item)
	var elixirs := ItemsApi.inventory(actor).count(current.recovery_item)
	assert_eq(BodyCultivationApi.recover_next(actor), true, "recovered")
	assert_eq(points.blocked_count(), 0, "no jam is left")
	assert_eq(
		_named(actor, "Damaged channels"),
		false,
		"the wound is closed: %s" % ", ".join(_unmet(actor))
	)
	assert_eq(
		ItemsApi.inventory(actor).count(current.recovery_item),
		elixirs - 1,
		"recovery consumed exactly one item"
	)

	# And the body advances on the retry.
	assert_eq(play.breakthrough(actor, BodyPlayFixture.rng(20_260_301)), true, "advanced")
	assert_eq(state.rank_id, seed.id, "into the realm it was aiming at")


## The halves of the wound are separate consequences, not one number: the jam is
## the body's own overlay, the tear halves that channel's bonuses until it is
## repaired (`MeridianState.get_bonus`).
func test_the_tear_is_a_real_stat_loss_until_it_is_repaired() -> void:
	var play := BodyPlayFixture.new()
	var actor := play.actor(&"qi_refining")
	assert_ne(play.prepare(actor), null, "prepared")
	var points: AcupointSet = actor.component(&"acupoints")
	var network := actor.meridians
	for point in points.points:
		point.quality = 0.62
	var before := _all_bonus(network)
	assert_eq(play.deviate(actor), true, "deviated")
	var after := _all_bonus(network)
	assert_eq(after < before, true, "the tear costs bonus now (%f -> %f)" % [before, after])
	var current := BodyRealmSeed.for_realm(actor.path(BodyPath.PATH_ID).rank_id)
	play.stock(actor, current.recovery_item)
	assert_eq(BodyCultivationApi.recover_next(actor), true, "recovered")
	assert_eq(_all_bonus(network), before, "and repairing the channel pays it back")


## Recovery is not a free button: without the item the wound and the jam both
## stay, and the gate stays shut.
func test_recovery_without_the_item_leaves_the_body_stuck() -> void:
	var play := BodyPlayFixture.new()
	var actor := play.actor(&"qi_refining")
	assert_ne(play.prepare(actor), null, "prepared")
	assert_eq(play.deviate(actor), true, "deviated")
	var points: AcupointSet = actor.component(&"acupoints")
	var blocked_before := points.blocked_count()
	assert_eq(blocked_before > 0, true, "jammed")
	assert_eq(BodyCultivationApi.recover_next(actor), false, "no item, no repair")
	assert_eq(points.blocked_count(), blocked_before, "the jam is still there")
	assert_eq(BodyAdvancement.preview(actor)["ready"], false, "and still blocked")


## A meridian with nothing wrong on it is still a disclosed no-op.
func test_recover_refuses_a_meridian_with_nothing_wrong() -> void:
	var play := BodyPlayFixture.new()
	var actor := play.actor(&"qi_refining")
	assert_ne(play.prepare(actor), null, "prepared")
	var current := BodyRealmSeed.for_realm(actor.path(BodyPath.PATH_ID).rank_id)
	play.stock(actor, current.recovery_item)
	var elixirs := ItemsApi.inventory(actor).count(current.recovery_item)
	assert_eq(BodyTraining.recover(actor, &"lung"), false, "nothing to repair")
	assert_eq(
		ItemsApi.inventory(actor).count(current.recovery_item),
		elixirs,
		"and the item was not consumed"
	)


# --- The state a save can still carry ---------------------------------------


## The dead end this fixes, stated exactly.
##
## `BodyBreakthroughCondition._acupoints_ready` demands `quality_required` on
## every huyệt the realm has unlocked, `BodyTraining.cultivate` SKIPS a blocked
## one, and no other action can raise it when its meridian is locked. So a blocked
## huyệt that sits below the floor, on a meridian the actor does not own, can
## never meet the gate — and `recover` used to refuse exactly that state.
##
## The state reaches a live actor through a save: `blocked` travels through
## `Acupoint.from_dict` untouched, and the huyệt data grants minor points at
## ladder index 0 on meridians that unlock at index 3 and 6.
func test_a_saved_jam_on_a_locked_meridian_is_still_freeable() -> void:
	var play := BodyPlayFixture.new()
	var actor := play.actor(&"qi_refining")
	var seed := play.prepare(actor)
	assert_ne(seed, null, "prepared")
	var state := actor.path(BodyPath.PATH_ID)
	var points: AcupointSet = actor.component(&"acupoints")
	# liver is a primary meridian that unlocks at ladder index 6, so it is absent
	# from an R1 actor's network while the minor huyệt on it exist.
	var legacy: Acupoint = null
	for point in points.points:
		if AcupointDefaults.meridian_of(point.id) == &"liver":
			legacy = point
			break
	assert_ne(legacy, null, "R1 holds huyệt on liver")
	assert_eq(actor.meridians.get_meridian(&"liver"), null, "but not liver itself")
	legacy.quality = seed.quality_required - 0.05
	legacy.block()
	assert_eq(
		_named(actor, "Acupoint quality"),
		true,
		"a below-floor huyệt on a locked meridian shuts the quality gate"
	)

	# It travels through a save, which is how an actor comes to carry one.
	var restored := BodyPlayFixture.load_save(actor.to_dict())
	var carried: Acupoint = null
	for point in BodyCultivationApi.acupoints(restored):
		if point.id == legacy.id:
			carried = point
			break
	assert_eq(carried != null and carried.blocked, true, "the save carried the jam")
	assert_eq(restored.meridians.get_meridian(&"liver"), null, "and still no liver channel")

	var current := BodyRealmSeed.for_realm(restored.path(BodyPath.PATH_ID).rank_id)
	play.stock(restored, current.recovery_item)
	var elixirs := ItemsApi.inventory(restored).count(current.recovery_item)
	assert_eq(BodyTraining.recover(restored, &"liver"), true, "the huyệt is freed")
	assert_eq(carried.blocked, false, "and unblocked")
	assert_eq(
		ItemsApi.inventory(restored).count(current.recovery_item),
		elixirs - 1,
		"and the migration still costs the item"
	)
	# Freed means trainable again: the gate is no longer shut by a huyệt nothing
	# can touch.
	play.cultivate_until(restored, seed.progress_required, seed.quality_required)
	assert_eq(_named(restored, "Acupoint quality"), false, "and it trains again")


## The same, without the item: the migration path charges too, so it is not a way
## to clear a jam for free.
func test_a_saved_jam_on_a_locked_meridian_still_needs_the_item() -> void:
	var play := BodyPlayFixture.new()
	var actor := play.actor(&"qi_refining")
	var points: AcupointSet = actor.component(&"acupoints")
	for point in points.points:
		if AcupointDefaults.meridian_of(point.id) == &"liver":
			point.block()
			break
	assert_eq(BodyTraining.recover(actor, &"liver"), false, "no item, no repair")
	assert_eq(points.blocked_count(), 1, "the jam is still there")
