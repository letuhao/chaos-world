extends TestCase

## ADR 0095: the qi channel ladder is a real ladder.
##
## Before this, all 30 qi seeds demanded `required_channel_state = open` and nothing
## more, so `expand`, `strengthen` and `refine` were never required by any gate,
## `channel_refinement_cap` was read by a branch that could not run, and the whole
## meridian ladder was dead data behind a flat demand.
##
## Both directions are asserted at all 29 boundaries, because asserting only one of
## them is how ADR 0036 shipped 28 unplayable transitions:
##
## - REACHABLE: from the strongest pre-state a player standing in realm R can hold
##   through public actions, every gate on R+1 is satisfied.
## - DISCRIMINATING: an actor that has done nothing fails the channel gate at every
##   one of the 29 boundaries. A gate a bare actor already passes is a formality, and
##   8 of the body's early realms were one until somebody audited it.

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

const PATH := QiPath.PATH_ID

## The first realm that asks for channel depth. Depth is unreachable below
## `strengthened`, so the ladder cannot ask for it earlier than this.
const FIRST_DEPTH_REALM := 4

# --- The authored schedule --------------------------------------------------


## The ladder is authored data, and the shape a future editor must keep is: the
## demand never falls, the cap rises one per realm, and the cap is always at least
## the next realm's demand. That last clause is the reachability rule, written once
## over all 30 rather than 29 times in a traversal.
func test_the_channel_demand_never_falls_and_the_cap_rises_every_realm() -> void:
	var realms := RealmDefaults.ladder().realms()
	var previous_rank := -1
	for index in range(realms.size()):
		var here := QiRealmSeed.for_realm(realms[index].id)
		assert_ne(here, null, "seed for %s" % realms[index].id)
		if here == null:
			continue
		var rank := int(MeridianState.STATE_ORDER.get(here.required_channel_state, 0))
		assert_eq(rank >= previous_rank, true, "demand never falls at %s" % realms[index].id)
		assert_eq(
			here.channel_refinement_cap, index + 1, "cap is one per realm at %s" % realms[index].id
		)
		if index + 1 >= realms.size():
			continue
		var after := QiRealmSeed.for_realm(realms[index + 1].id)
		assert_ne(after, null, "seed for %s" % realms[index + 1].id)
		if after != null:
			assert_eq(
				after.required_channel_refinement <= here.channel_refinement_cap,
				true,
				(
					"%s demands depth %d but %s only offers %d"
					% [
						realms[index + 1].id,
						after.required_channel_refinement,
						realms[index].id,
						here.channel_refinement_cap,
					]
				)
			)
		previous_rank = rank


## Every realm authors both halves of the channel gate. A seed left at the depth
## default of 0 while demanding `strengthened` is this ADR's own defect written
## into new content.
func test_every_realm_authors_a_channel_gate_that_can_fail() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		assert_ne(seed, null, "seed for %s" % realm.id)
		if seed == null:
			continue
		assert_ne(seed.required_channel_state, MeridianState.CLOSED, "demand for %s" % realm.id)
		assert_eq(seed.required_meridians.is_empty(), false, "channels for %s" % realm.id)
		assert_eq(
			seed.required_channel_refinement <= seed.channel_refinement_cap,
			true,
			"%s demands depth past its own cap" % realm.id
		)
		if seed.required_channel_refinement <= 0:
			continue
		assert_eq(
			seed.required_channel_state,
			MeridianState.STRENGTHENED,
			"%s asks for depth %d" % [realm.id, seed.required_channel_refinement]
		)


## Depth is only reachable on a strengthened channel — `MeridianNetwork.
## refine_meridian` refuses anything else — so a seed demanding depth below
## `strengthened` would be unsatisfiable by construction rather than by tuning.
func test_depth_is_never_demanded_below_strengthened() -> void:
	var asking := 0
	for realm in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null or seed.required_channel_refinement <= 0:
			continue
		asking += 1
		assert_eq(
			seed.required_channel_state,
			MeridianState.STRENGTHENED,
			(
				"%s demands depth %d below %s"
				% [realm.id, seed.required_channel_refinement, seed.required_channel_state]
			)
		)
	assert_eq(asking > 0, true, "the ladder asks for depth somewhere")


# --- Reachable -------------------------------------------------------------


## THE test. At all 29 boundaries, from a pre-state earned through public actions
## alone, the channel gate is satisfiable. A gate above what the realm below can
## train to is exactly the defect that made 28 of 29 qi transitions unplayable
## before ADR 0036, and only walking the ladder catches it.
func test_every_channel_gate_is_reachable_from_the_realm_below() -> void:
	var checked := 0
	for realm in RealmDefaults.ladder().realms():
		var target := Probe.target_seed_after(realm.id)
		if target == null:
			continue
		var actor := Probe.prepared(realm.id, target)
		for meridian_id in target.required_meridians:
			var channel := actor.meridians.get_meridian(meridian_id)
			assert_ne(channel, null, "%s unlocked at %s" % [meridian_id, realm.id])
			if channel == null:
				continue
			assert_eq(channel.is_injured(), false, "%s repaired for %s" % [meridian_id, realm.id])
			assert_eq(
				channel.meets(target.required_channel_state),
				true,
				"%s reached %s for %s" % [meridian_id, target.required_channel_state, realm.id]
			)
			assert_eq(
				channel.refinement >= target.required_channel_refinement,
				true,
				(
					"%s reached depth %d (it holds %d) for %s"
					% [
						meridian_id,
						target.required_channel_refinement,
						channel.refinement,
						realm.id,
					]
				)
			)
		checked += 1
	assert_eq(checked, Probe.BOUNDARY_COUNT, "every boundary on the ladder was checked")


# --- Discriminating --------------------------------------------------------


## The other direction, and the one a flat `open` demand silently failed: an actor
## that has done nothing must fail the channel gate everywhere. Every channel a
## fresh network holds is `closed` at refinement 0.
func test_every_channel_gate_fails_for_an_actor_that_has_done_nothing() -> void:
	var checked := 0
	for realm in RealmDefaults.ladder().realms():
		var target := Probe.target_seed_after(realm.id)
		if target == null:
			continue
		var actor := Probe.fresh_actor(realm.id)
		var unmet := 0
		for meridian_id in target.required_meridians:
			var channel := actor.meridians.get_meridian(meridian_id)
			assert_ne(channel, null, "%s unlocked at %s" % [meridian_id, realm.id])
			if channel != null and not target.channel_met(channel):
				unmet += 1
		assert_eq(unmet > 0, true, "a bare actor already passes the gate for %s" % realm.id)
		checked += 1
	assert_eq(checked, Probe.BOUNDARY_COUNT, "every boundary on the ladder was checked")


## The depth half specifically: a channel carried all the way to `strengthened` and
## no deeper is refused by every realm that asks for depth. Without this a suite
## that stopped at the state ladder would stay green while the depth gate did
## nothing at all.
func test_depth_alone_is_enforced_once_a_realm_asks_for_it() -> void:
	var checked := 0
	for index in range(FIRST_DEPTH_REALM, RealmDefaults.ladder().realms().size()):
		var realms := RealmDefaults.ladder().realms()
		var target := Probe.target_seed_after(realms[index - 1].id)
		var source := QiRealmSeed.for_realm(realms[index - 1].id)
		assert_ne(target, null, "target seed for %s" % realms[index].id)
		assert_ne(source, null, "source seed for %s" % realms[index - 1].id)
		if target == null or source == null or target.required_channel_refinement <= 0:
			continue
		checked += 1
		var actor := Probe.fresh_actor(realms[index - 1].id)
		var meridian_id := target.required_meridians[0]
		# Climb to the demanded state through the verb, and stop there.
		var climbed := 0
		var channel := actor.meridians.get_meridian(meridian_id)
		var wanted := int(MeridianState.STATE_ORDER.get(target.required_channel_state, 0))
		while climbed < Probe.CLIMB_BOUND and channel.state_rank() < wanted:
			climbed += 1
			Probe.stock(actor, source.training_item, 1)
			if not QiCultivationApi.train_channel(actor, meridian_id):
				break
			channel = actor.meridians.get_meridian(meridian_id)
		assert_eq(
			channel.state_rank(), wanted, "climbed to the demanded state for %s" % realms[index].id
		)
		assert_eq(channel.refinement, 0, "and no deeper")
		assert_eq(
			target.channel_met(channel),
			false,
			(
				"depth 0 must not satisfy the depth-%d gate for %s"
				% [target.required_channel_refinement, realms[index].id]
			)
		)
	assert_eq(checked > 0, true, "some realm asks for depth")


## The cap is the binding ceiling, and reaching it is refused WITHOUT spending the
## elixir. `train_channel` used to consume the item and return true even when
## `refine_meridian` had nothing left to do, which made the realm's channel elixir
## an unbounded sink with no progress behind it.
func test_training_past_the_cap_is_refused_and_costs_no_elixir() -> void:
	var realm_id := RealmDefaults.ladder().realms()[FIRST_DEPTH_REALM].id
	var seed := QiRealmSeed.for_realm(realm_id)
	var actor := Probe.fresh_actor(realm_id)
	var meridian_id := seed.required_meridians[0]
	var guard := 0
	var ceiling := seed.channel_refinement_cap + 1
	var channel := actor.meridians.get_meridian(meridian_id)
	while (
		guard < Probe.CLIMB_BOUND + ceiling
		and (
			channel.state != MeridianState.STRENGTHENED
			or channel.refinement < seed.channel_refinement_cap
		)
	):
		guard += 1
		Probe.stock(actor, seed.training_item, 1)
		if not QiCultivationApi.train_channel(actor, meridian_id):
			break
		channel = actor.meridians.get_meridian(meridian_id)
	assert_eq(channel.state, MeridianState.STRENGTHENED, "climbed to strengthened")
	assert_eq(channel.refinement, seed.channel_refinement_cap, "deepened to the realm cap")
	Probe.stock(actor, seed.training_item, 1)
	var held := ItemsApi.inventory(actor).count(seed.training_item)
	assert_eq(QiCultivationApi.train_channel(actor, meridian_id), false, "refused past the cap")
	assert_eq(
		ItemsApi.inventory(actor).count(seed.training_item), held, "and the refusal cost no elixir"
	)
	assert_eq(
		actor.meridians.get_meridian(meridian_id).refinement,
		seed.channel_refinement_cap,
		"the channel did not move"
	)


# --- Preview and execute agree ---------------------------------------------


## ADR 0044: a preview that reports a realm enterable while the transaction refuses
## it is a gate that does not exist. At all 29 boundaries the two must give the same
## answer about readiness, from the same earned pre-state.
##
## R19 is the boundary where the two kinds of answer part. Its only extra gate is
## the tribulation, which is the player's fight, so it closes from a standing start
## at R18 — ADR 0035 makes the inside world the R19 breakthrough's own product, so
## R19 never requires it. From R20 on, the anchors are earned by ENTERING the realm
## the actor stands in, so those boundaries are honestly "not yet" here; the
## traversal is where the high tier is proven end to end.
func test_preview_and_condition_agree_at_every_boundary() -> void:
	var checked := 0
	var ready := 0
	var anchored := 0
	for realm in RealmDefaults.ladder().realms():
		var target_realm := Probe.target_after(realm.id)
		var target := Probe.target_seed_after(realm.id)
		if target == null or target_realm == null:
			continue
		var actor := Probe.prepared(realm.id, target)
		var preview := Probe.preview(actor)
		var condition := QiBreakthroughCondition.new().can_breakthrough(actor, actor.path(PATH), {})
		assert_eq(
			bool(preview["can_attempt"]),
			condition,
			(
				"preview and condition agree entering %s: %s"
				% [target_realm.id, str(preview["unmet_conditions"])]
			)
		)
		if target_realm.index <= Breakthrough.IMMORTAL_REALM_THRESHOLD:
			assert_eq(
				bool(preview["can_attempt"]),
				true,
				(
					"entering %s from %s is reachable: %s"
					% [target_realm.id, realm.id, str(preview["unmet_conditions"])]
				)
			)
			ready += 1
		else:
			# Agreement is the whole claim here. The anchors are not this boundary's
			# to earn, and asserting otherwise would demand a test forge them.
			assert_eq(
				bool(preview["can_attempt"]),
				false,
				(
					"entering %s still waits on the anchor its predecessor commits: %s"
					% [target_realm.id, str(preview["unmet_conditions"])]
				)
			)
			anchored += 1
		checked += 1
	assert_eq(checked, Probe.BOUNDARY_COUNT, "every boundary on the ladder was checked")
	assert_eq(ready, Breakthrough.IMMORTAL_REALM_THRESHOLD, "every boundary into R1..R19 closed")
	assert_eq(anchored, Probe.BOUNDARY_COUNT - ready, "and the rest wait on their anchor")


## A channel one step short of the gate is reported by name, so a screen can tell
## the player WHICH channel is short rather than only that something is. The two
## previews are separate functions and a name that appears in one and not the other
## is the defect ADR 0044 exists to prevent.
func test_a_short_channel_is_reported_by_name_in_both_previews() -> void:
	var realms := RealmDefaults.ladder().realms()
	var realm_id := realms[FIRST_DEPTH_REALM].id
	var source := QiRealmSeed.for_realm(realm_id)
	var target := Probe.target_seed_after(realm_id)
	assert_ne(source, null, "source seed")
	assert_ne(target, null, "target seed")
	var actor := Probe.fresh_actor(realm_id)
	var short := target.required_meridians[target.required_meridians.size() - 1]
	# Train every channel but the last, on one stocked elixir budget, so the only
	# unmet condition is that one.
	assert_eq(
		Probe.stock(actor, source.training_item, Probe.gate_elixir_budget(actor, target) + 1),
		true,
		"elixirs stocked"
	)
	for meridian_id in target.required_meridians:
		if meridian_id == short:
			continue
		assert_eq(Probe.train_to_gate(actor, meridian_id, target), true, "%s trained" % meridian_id)
	var wanted := "channel_not_ready:%s" % short
	for preview in [Probe.preview(actor), QiAdvancement.preview(actor)]:
		var unmet: Array = preview["unmet_conditions"]
		assert_eq(unmet.has(wanted), true, "named in %s" % str(unmet))
	assert_eq(
		bool(Probe.preview(actor)["can_attempt"]),
		false,
		"and the preview refuses while a channel is short"
	)
	assert_eq(
		QiBreakthroughCondition.new().can_breakthrough(actor, actor.path(PATH), {}),
		false,
		"and so does the transaction"
	)
	Probe.stock(actor, source.training_item, Probe.gate_elixir_budget(actor, target) + 1)
	assert_eq(Probe.train_to_gate(actor, short, target), true, "the last one trains too")
	for preview in [Probe.preview(actor), QiAdvancement.preview(actor)]:
		var unmet: Array = preview["unmet_conditions"]
		assert_eq(unmet.has(wanted), false, "no longer named in %s" % str(unmet))
	# The boundary as a whole stays shut on this actor — nothing here earned the
	# work budget, the insight floor, the dantian or the pill — and what this test
	# claims is only that the CHANNEL condition is gone once the channel is trained.
	assert_eq(
		bool(Probe.preview(actor)["can_attempt"]),
		false,
		(
			"and the boundary is still shut on the gates this actor never earned: %s"
			% str(Probe.preview(actor)["unmet_conditions"])
		)
	)
