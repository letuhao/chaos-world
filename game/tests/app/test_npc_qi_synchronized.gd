extends TestCase

## BL-0696: an npc was ENROLLED on the qi path and never SYNCHRONIZED, so its qi
## state was `QiCultivationApi.attach`'s fresh defaults rather than what its realm
## implies. `ActorFactory.spawn_npc` wrote the path and called `attach` itself
## (`actor_factory.gd:377-378` before the fix) instead of routing through the
## private `_attach_qi` verb every other qi entry point uses, and `_attach_qi` is
## where `QiTraining.synchronize` lives (`actor_factory.gd:269-273`).
##
## Why it hid. `qi_refining` — the ladder's first realm and `spawn_npc`'s own
## default `rank_id` — happens to AGREE with the defaults: its seed authors
## `dantian_capacity = 100.0`, and
## `QiCultivationApi._ensure_resources` mounts the reservoir at
## `ResourcePool.new(QI, 100.0)`. So a fixture that mints at the default realm
## cannot tell a synchronized actor from an unsynchronized one. Every assertion
## here is therefore made at a realm where the two differ.
##
## What `synchronize` owns, and what these assert: meridian unlocks
## (`meridian_network.unlock_for_realm`), the dantian's structural capacity from
## the realm seed, and the reservoir ceiling
## (`training.gd:10-28`).
##
## ## `channel_refinement_cap` is NOT one of the four
## `channel_refinement_cap` is never WRITTEN onto an actor — `train_channel`
## (`:175`) and `can_train_channel` (`:241`) read it live off
## `QiRealmSeed.for_realm(state.rank_id)`. So an unsynchronized npc already
## reported the right cap, and the audit's premise that synchronize "sets" it is
## wrong. The last test pins that as a non-defect, so nobody re-derives it and
## re-opens this finding a third time.

## Chosen because it disagrees with every default on all three counts: a 600.0
## capacity against the pool's 100.0, an `upper` dantian against the component's
## `lower`, and a cap of 21 elixirs of depth against the component's 0. R1 is the
## realm that hides this; this one cannot.
const REALM := &"golden_immortal"


## An npc minted the way `NpcApi.set_minter` and `EconomyBoot._subject_minter`
## mint one: no authored `NpcDef`, the realm supplied positionally. Nothing below
## attaches, synchronizes or seeds anything by hand — anything this test needs is
## something the factory owes its caller, so a failure cannot be blamed on an
## under-provisioned actor.
func _npc() -> Actor:
	return ActorFactory.spawn_npc(null, &"rival_cultivator", REALM)


func test_npc_qi_state_follows_the_realm_it_was_minted_at() -> void:
	var actor := _npc()
	assert_eq(
		String(actor.path(QiPath.PATH_ID).rank_id),
		String(REALM),
		"the npc is on the realm it was minted at"
	)
	var seed := QiRealmSeed.for_realm(REALM)
	assert_ne(seed, null, "and that realm publishes a qi seed to synchronize against")

	## The dantian is the path's vessel; `synchronize` sizes it from the seed and
	## scales it by the meridian network's capacity bonus, so the two halves move
	## together and an unsynchronized actor has the wrong one by construction.
	var dantian := QiTestKit.dantian(actor)
	assert_ne(dantian, null, "the npc carries a dantian")
	if seed == null or dantian == null:
		return
	var expected_capacity: float = (
		seed.dantian_capacity * (1.0 + actor.meridians.get_capacity_bonus())
	)
	assert_almost_eq(
		dantian.structural_capacity,
		expected_capacity,
		"the dantian is sized by synchronize from the realm seed, not from the base stat"
	)
	# `synchronize:27` caps the reservoir at the dantian's effective capacity, so a
	# dantian sized right with a pool left at its own default is still a path that
	# cannot hold what its vessel can.
	assert_almost_eq(
		actor.resource(QiStats.QI).maximum,
		dantian.effective_capacity(),
		"the qi reservoir is capped to the dantian synchronize sized"
	)


## The unlocks. Counted from `unlock_for_realm`'s OWN rule (`tier <= realm index`)
## rather than pasted, so a retuned meridian ladder is a named failure and not a
## silent no-op. `for` over the fixed 20 `MeridianDefaults`, never a `while` on a
## container the body grows.
func test_npc_meridians_are_unlocked_up_to_its_realm() -> void:
	var actor := _npc()
	var realm_index := RealmDefaults.ladder().index_of(REALM)
	var expected := 0
	for def in MeridianDefaults.all():
		if def.tier <= realm_index:
			expected += 1
	assert_eq(
		actor.meridians.get_all_meridians().size(),
		expected,
		"every meridian the realm unlocks is present on the network"
	)
	# The gate's own named channels are what downstream reads, and an empty network
	# makes `get_meridian` return null for every one of them — which is how an
	# unsynchronized npc reported a cap it could never reach.
	var seed := QiRealmSeed.for_realm(REALM)
	if seed == null:
		return
	for meridian_id in seed.required_meridians:
		assert_ne(
			actor.meridians.get_meridian(meridian_id),
			null,
			"the channel %s the realm's gate names is unlocked" % meridian_id
		)


## The cap, asserted as a NON-defect so this finding is not re-derived a third
## time: it is read off the seed at the moment it is asked for, so it agrees with
## the realm whether or not `synchronize` ever ran. What synchronize DOES owe is
## the channel existing — `can_train_channel` refuses a null channel outright
## (`training.gd:232`), so an empty network made the cap unreachable, not wrong.
func test_npc_channel_refinement_cap_is_the_realm_cap_on_read() -> void:
	var actor := _npc()
	var seed := QiRealmSeed.for_realm(REALM)
	if seed == null:
		return
	var channel := actor.meridians.get_meridian(seed.required_meridians[0])
	assert_ne(channel, null, "the gate's first channel exists, so its cap is askable")
	if channel == null:
		return
	channel.state = MeridianState.STRENGTHENED
	channel.refinement = seed.channel_refinement_cap
	assert_eq(
		QiTraining.can_train_channel(actor, seed.required_meridians[0]),
		false,
		"a channel at the realm's own cap has nothing left to learn"
	)
	channel.refinement = seed.channel_refinement_cap - 1
	assert_eq(
		QiTraining.can_train_channel(actor, seed.required_meridians[0]),
		true,
		"and one elixir short of it still owes depth"
	)


## `spawn_npc` is a constructor and may be called twice on the same subject, so
## the synchronize it now performs must be idempotent. `synchronize` overwrites
## capacity and the pool ceiling and only ADDS a missing meridian
## (`meridian_network.gd:34`), so a second call is a no-op — asserted, because
## `ActorStats.add_provider` appends UNGUARDED and a future edit that made
## synchronize additive would stack a second copy silently.
func test_synchronizing_twice_changes_nothing() -> void:
	var actor := _npc()
	var dantian := QiTestKit.dantian(actor)
	var meridians := actor.meridians.get_all_meridians().size()
	var capacity: float = dantian.structural_capacity
	var ceiling: float = actor.resource(QiStats.QI).maximum
	var providers := actor.stats.provider_count()
	QiTraining.synchronize(actor)
	assert_eq(actor.meridians.get_all_meridians().size(), meridians, "no second meridian is added")
	assert_almost_eq(dantian.structural_capacity, capacity, "capacity is unchanged")
	assert_almost_eq(
		actor.resource(QiStats.QI).maximum, ceiling, "the reservoir ceiling is unchanged"
	)
	assert_eq(
		actor.stats.provider_count(), providers, "and no second provider is appended by the repeat"
	)
