extends TestCase

## A save taken at the top of the ladder, from a body that got there by play.
##
## The round trip this replaces started its actor at `spirit_sea`, wrote
## `set_resonance_rank(6)` by hand — an R19 value on an R11 body that no player
## can reach — and asserted refinement ">= 8". So it proved a save carries a
## payload someone assembled, not one the game produced. Everything below is
## reached through `BodyPlayFixture`, and every expectation is a value the
## ladder's own data says the body must have.
##
## What it covers that nothing else does:
##   - the last three CELESTIAL acupoint, which unlock at ladder index 27
##   - the reservoir's MAXIMUM, not just its current value
##   - a channel's depth at the standing realm's own ceiling
##   - an UNREPAIRED injury, saved mid-wound: a save that quietly healed a body
##     would erase the entire cost of a failed breakthrough

var _play: BodyPlayFixture


func setup() -> void:
	_play = BodyPlayFixture.new()


## The deepest refinement any channel on the body has reached.
func _deepest(actor: Actor) -> int:
	var deepest := 0
	for channel in actor.meridians.get_all_meridians():
		deepest = maxi(deepest, channel.refinement)
	return deepest


func _tier_count(actor: Actor, tier: StringName) -> int:
	var found := 0
	for point in BodyCultivationApi.acupoints(actor):
		if point.tier == tier:
			found += 1
	return found


## The snapshot with the two slots this module does not own removed.
##
## `module_data` holds the RAW acupoint and milestone dictionaries `Actor.from_dict`
## parks for the module to rebuild: empty on a live body, populated on a freshly
## loaded one, so comparing them compares the load sequence rather than the body.
## `item_state` is the items module's payload entirely. Neither is dropped
## silently — the typed acupoint set, the channels, the reservoir, the path and the
## milestone ledger are each compared directly, and each is rebuilt FROM those
## raw slots, so a slot that failed to travel would show up there.
func _body_only(snapshot: Dictionary) -> Dictionary:
	var out := snapshot.duplicate(true)
	var payload: Dictionary = out.get("payload", {})
	payload.erase("item_state")
	payload.erase("module_data")
	return out


## A body climbed from R1 to the top of the Mortal-to-Transcendent run by play,
## then compared field by field against its own save.
func test_a_save_at_the_transcendent_tier_round_trips_every_layer() -> void:
	var actor := _play.climb_to(&"qi_refining", &"transcendent")
	var rank: StringName = actor.path(BodyPath.PATH_ID).rank_id
	assert_eq(rank, &"transcendent", "climbed from R1 to R28 through public actions")
	var home := BodyRealmSeed.for_realm(rank)
	assert_ne(home, null, "the standing realm has a seed")
	# Celestial acupoint open at ladder index 18; the last three open at 27. A body
	# at index 27 holds every tier, and an earlier round trip could not.
	assert_eq(
		BodyCultivationApi.acupoints(actor).size(),
		60,
		"every acupoint tier is open, celestial included"
	)
	assert_eq(_tier_count(actor, &"celestial"), 12, "all 12 celestial acupoint are held")
	# Depth is what this realm demanded on entry: its own requirement, one step
	# under its ceiling. Nothing in this realm can buy the step above that, which
	# is why the deepest channel must sit exactly on the floor.
	assert_eq(
		_deepest(actor),
		home.required_refinement,
		"trained to the depth this realm demanded (%d)" % _deepest(actor)
	)
	assert_eq(
		_deepest(actor) < home.refinement_cap,
		true,
		"and one step under this realm's cap of %d" % home.refinement_cap
	)
	var next_seed := _play.seed_for(actor)
	assert_ne(next_seed, null, "there is a realm above this one")
	assert_eq(
		next_seed.required_refinement,
		home.refinement_cap,
		"the next realm demands exactly this realm's cap"
	)
	assert_eq(actor.meridians.resonance_rank, home.resonance_rank, "resonance earned")
	var pool := _play.reservoir(actor)
	assert_ne(pool, null, "the body carries a reservoir")
	assert_eq(pool.maximum, home.integrity_maximum, "the reservoir is sized by its realm")
	var before := _body_only(_play.snapshot(actor))
	var restored := BodyPlayFixture.load_save(actor.to_dict())
	var differences := _play.diff(before, _body_only(_play.snapshot(restored)), "actor")
	assert_eq(differences.is_empty(), true, "the save lost state: %s" % "; ".join(differences))
	# The restored body is a body the game can still act on, not just a payload
	# that compares equal: it holds every acupoint, its channels are intact, and the
	# reservoir is bound to it again.
	assert_eq(
		BodyCultivationApi.acupoints(restored).size(),
		60,
		"the restored body still has every acupoint"
	)
	assert_eq(_deepest(restored), _deepest(actor), "and the same channel depth")
	assert_eq(restored.meridians.resonance_rank, home.resonance_rank, "and its resonance")
	assert_almost_eq(
		_play.reservoir(restored).maximum, home.integrity_maximum, "and its reservoir size"
	)


## The reservoir's maximum is a MAGNITUDE the body path owns, and it is the one
## pool field a naive round trip drops: `current` is easy to compare, `maximum`
## is set from a seed on every synchronize and never compared.
func test_the_reservoir_maximum_survives_a_save() -> void:
	var actor := _play.actor()
	assert_ne(_play.prepare(actor), null, "prepared through public actions")
	var expected := _play.reservoir(actor).maximum
	assert_ne(expected, 0.0, "sanity: the reservoir is sized")
	var restored := BodyPlayFixture.load_save(actor.to_dict())
	assert_almost_eq(_play.reservoir(restored).maximum, expected, "the reservoir ceiling survived")
	# And it is still BOUND to the acupoint set, so filling the body fills the
	# reservoir the restored body reads.
	var restored_points: AcupointSet = restored.component(&"acupoints")
	assert_ne(restored_points, null, "the restored body has a acupoint set")
	restored_points.fill(1.0)
	assert_almost_eq(
		_play.reservoir(restored).current, expected, "filling moved the restored reservoir"
	)


## An unrepaired injury is saved mid-wound and comes back still blocking. A save
## that healed it would make a failed breakthrough free, and a load that dropped
## the flag would make every wound cosmetic.
func test_an_unrepaired_injury_survives_a_save_and_still_blocks() -> void:
	var actor := _play.actor()
	assert_ne(_play.prepare(actor), null, "prepared through public actions")
	# Read the network's power bonus while the body is whole: a wound halves its
	# own channel's share (ADR 0017), so this is the number the restored body
	# must NOT report if the injury travelled, and the one it must report if it
	# was silently healed.
	var whole := actor.meridians.get_power_bonus()
	assert_eq(_play.deviate(actor), true, "an attempt deviated")
	var torn := &""
	for channel in actor.meridians.get_all_meridians():
		if channel.is_injured():
			torn = channel.id
	assert_ne(torn, &"", "the deviation tore a channel")
	var wounded := actor.meridians.get_power_bonus()
	assert_eq(wounded < whole, true, "a wound costs the network power (%f < %f)" % [wounded, whole])
	var restored := BodyPlayFixture.load_save(actor.to_dict())
	var restored_channel := restored.meridians.get_meridian(torn)
	assert_ne(restored_channel, null, "the torn channel is on the restored body")
	assert_eq(restored_channel.is_injured(), true, "and it is still wounded")
	assert_almost_eq(
		restored.meridians.get_power_bonus(),
		wounded,
		"and the restored network is wounded exactly as much as the saved one",
		0.0001
	)
	# And the gate still names it, so the player is told to go and heal it.
	var unmet := BodyBreakthroughCondition.new().describe_unmet(
		restored, restored.path(BodyPath.PATH_ID)
	)
	var named := false
	for message in unmet:
		if message.contains("Damaged channels") and message.contains(String(torn)):
			named = true
	assert_eq(named, true, "the wound is still a gate: %s" % ", ".join(unmet))
	# Recovery through the public action closes it, which is what makes the saved
	# wound a cost rather than a dead end.
	var current := BodyRealmSeed.for_realm(restored.path(BodyPath.PATH_ID).rank_id)
	_play.stock(restored, current.recovery_item)
	assert_eq(BodyTraining.recover(restored, torn), true, "the wound was healed")
	assert_eq(restored.meridians.get_meridian(torn).is_injured(), false, "and it is gone")


## A jammed acupoint is the other half of a deviation's wound, and it lives on a
## different object than the injured channel — a payload that carried the flag on
## `MeridianState` and not on `Acupoint` would lose it silently, and a load that
## dropped it would make the blockage free.
func test_a_jammed_huyet_survives_a_save() -> void:
	var actor := _play.actor()
	assert_ne(_play.prepare(actor), null, "prepared through public actions")
	assert_eq(_play.deviate(actor), true, "an attempt deviated")
	var jammed := &""
	for point in BodyCultivationApi.acupoints(actor):
		if point.blocked:
			jammed = point.id
	assert_ne(jammed, &"", "the deviation jammed a acupoint")
	var restored := BodyPlayFixture.load_save(actor.to_dict())
	var restored_point: Acupoint = null
	for point in BodyCultivationApi.acupoints(restored):
		if point.id == jammed:
			restored_point = point
	assert_ne(restored_point, null, "the jammed acupoint is on the restored body")
	assert_eq(restored_point.blocked, true, "and it is still jammed")
	# Recovery through the public action clears it, which is what makes the saved
	# jam a cost rather than a dead end.
	var current := BodyRealmSeed.for_realm(restored.path(BodyPath.PATH_ID).rank_id)
	_play.stock(restored, current.recovery_item)
	var meridian := AcupointDefaults.meridian_of(jammed)
	assert_ne(meridian, &"", "the jam names a channel")
	assert_eq(BodyTraining.recover(restored, meridian), true, "the jam was healed")
	assert_eq(restored_point.blocked, false, "and the acupoint is open again")


## A milestone ledger earned across 28 realms must not be re-awarded on load.
## `BodyProgress` reads its own `completed` list, so a load that reconstructed it
## from the actor payload alone would pay the physique bonus a second time for
## every realm the body ever trained in.
func test_a_high_save_does_not_reaward_its_milestones() -> void:
	var actor := _play.climb_to(&"qi_refining", &"transcendent")
	var progress: BodyProgress = actor.component(&"body_progress")
	assert_ne(progress, null, "the body tracks its milestones")
	assert_eq(progress.completed.is_empty(), false, "a climbed body has milestones")
	var physique := actor.stats.get_base(Stat.PHYSIQUE)
	var restored := BodyPlayFixture.load_save(actor.to_dict())
	assert_almost_eq(
		restored.stats.get_base(Stat.PHYSIQUE), physique, "load paid no second time", 0.0001
	)
	var restored_progress: BodyProgress = restored.component(&"body_progress")
	assert_ne(restored_progress, null, "the ledger came back")
	assert_eq(
		restored_progress.completed.size(),
		progress.completed.size(),
		"every milestone is still recorded"
	)
	# Training in the standing realm must not pay the SAME milestone twice.
	#
	# This used to assert "training again pays nothing", i.e. that the first
	# strengthen after the load changed nothing at all. That is false by design:
	# entering a realm does not mark its milestone — `BodyTraining.strengthen`
	# says so, and marking on entry "would make the bonus free" (ADR 0023) — and
	# `climb_to` stops the instant it enters its stop realm, so the standing
	# realm's milestone is legitimately unpaid and the first channel step there
	# earns it. The once-only guarantee is real and is what this asserts: a second
	# pass over the same channels adds nothing, and the ledger gains no duplicate.
	# (The wrong expectation was intermittent, not constant: the amount depends on
	# which realm the climb stopped in.)
	var home := BodyRealmSeed.for_realm(restored.path(BodyPath.PATH_ID).rank_id)
	for meridian_id in home.required_meridians:
		_play.stock(restored, home.strengthening_item)
		BodyTraining.strengthen(restored, meridian_id)
	var after_first := restored.stats.get_base(Stat.PHYSIQUE)
	assert_eq(
		after_first - physique >= 0.0,
		true,
		"training never takes physique away (%.4f -> %.4f)" % [physique, after_first]
	)
	for meridian_id in home.required_meridians:
		_play.stock(restored, home.strengthening_item)
		BodyTraining.strengthen(restored, meridian_id)
	assert_almost_eq(
		restored.stats.get_base(Stat.PHYSIQUE), after_first, "a second pass pays nothing"
	)
	assert_eq(restored_progress.completed.count(home.id), 1, "and the milestone is recorded once")
