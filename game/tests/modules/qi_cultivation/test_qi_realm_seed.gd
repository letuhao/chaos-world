extends TestCase

## ADR 0024: the generated qi-cultivation data contract — one realm seed per
## realm, and the meridians and items each seed references.


func _seed_for_next(actor: Actor) -> QiRealmSeed:
	var state := actor.path(QiPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	return QiRealmSeed.for_realm(target.id)


# --- Seed data -------------------------------------------------------------


func test_every_realm_has_a_seed() -> void:
	for realm in RealmDefaults.ladder().realms():
		assert_eq(QiRealmSeed.for_realm(realm.id) != null, true, "seed for %s" % realm.id)


func test_seed_defines_both_items_and_channels() -> void:
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	assert_eq(seed != null, true, "seed loaded")
	assert_ne(seed.breakthrough_item, &"", "has breakthrough item")
	assert_ne(seed.training_item, &"", "has training item")
	assert_eq(seed.required_meridians.is_empty(), false, "requires channels")


func test_seed_channels_exist_in_the_network() -> void:
	var known: Array[StringName] = []
	for def in MeridianDefaults.all():
		known.append(def.id)
	for realm in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		for meridian_id in seed.required_meridians:
			assert_eq(known.has(meridian_id), true, "channel %s exists" % meridian_id)


func test_seed_items_exist_in_content() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		for item_id in [seed.breakthrough_item, seed.training_item]:
			var path := "res://data/items/consumable/%s.tres" % item_id
			assert_eq(ResourceLoader.exists(path), true, "item %s exists" % item_id)


## ADR 0165 deleted `dantian_tier`, so this is the half of that ruling the data can
## carry: no qi seed declares a dantian tier any more. A re-added field with no gate
## reading it is the exact defect DEF-0228 recorded, and the module guard
## (`test_qi_ruling_q1_no_dantian_tier.gd`) is what fails the build on one.
func test_no_seed_declares_a_dantian_tier() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		var path := "res://data/qi_cultivation/realms/%s.tres" % realm.id
		var text := FileAccess.get_file_as_string(path)
		assert_eq(
			text.contains("dantian_tier"),
			false,
			"%s declares dantian_tier, a ladder nothing gates on (ADR 0165)" % realm.id
		)


## ADR 0036's reachability rule, on the data: a seed describes the realm being
## ENTERED, so every channel it requires must already be unlocked by the realm the
## actor is leaving. Unlocking at the target's own index is one tier too loose — it
## would pass a seed demanding a channel that appears only in the realm being
## entered, which is exactly how 28 of 29 qi transitions became unplayable.
func test_seed_never_requires_an_unopened_channel() -> void:
	var known: Dictionary = {}
	for def in MeridianDefaults.all():
		known[def.id] = def.tier
	var realms := RealmDefaults.ladder().realms()
	# R1 is the STARTING realm: nobody enters it, so its seed's gate is never applied
	# and there is no realm below it to unlock from. Its channels are checked against
	# its own index instead, so the content is still covered rather than skipped.
	var start := QiRealmSeed.for_realm(realms[0].id)
	if start != null:
		for meridian_id in start.required_meridians:
			assert_eq(
				int(known.get(meridian_id, 99)) <= 0,
				true,
				"%s needs %s, which unlocks at index 0" % [realms[0].id, meridian_id]
			)
	for index in range(1, realms.size()):
		var seed := QiRealmSeed.for_realm(realms[index].id)
		if seed == null:
			continue
		var source := index - 1
		for meridian_id in seed.required_meridians:
			assert_eq(known.has(meridian_id), true, "%s is a known channel" % meridian_id)
			if not known.has(meridian_id):
				continue
			assert_eq(
				int(known[meridian_id]) <= source,
				true,
				(
					"%s needs %s, which unlocks at index %d, and %s is entered from index %d"
					% [
						realms[index].id,
						meridian_id,
						int(known[meridian_id]),
						realms[index].id,
						source,
					]
				)
			)


## Every realm authors a channel gate that can actually fail, and a depth that is
## reachable from the realm below's cap (ADR 0095). All 30 seeds demanded `open`
## before this, which made `expand`, `strengthen` and `refine` unreachable and
## `channel_refinement_cap` a branch that could not run.
func test_every_realm_authors_a_rising_channel_gate() -> void:
	var realms := RealmDefaults.ladder().realms()
	var previous_cap := 0
	for index in range(realms.size()):
		var seed := QiRealmSeed.for_realm(realms[index].id)
		assert_ne(seed, null, "seed for %s" % realms[index].id)
		if seed == null:
			continue
		assert_ne(
			seed.required_channel_state, MeridianState.CLOSED, "demand for %s" % realms[index].id
		)
		assert_eq(
			seed.channel_refinement_cap,
			index + 1,
			"the cap rises one per realm at %s" % realms[index].id
		)
		assert_eq(
			seed.channel_refinement_cap > previous_cap,
			true,
			"and never falls at %s" % realms[index].id
		)
		previous_cap = seed.channel_refinement_cap
		if index + 1 >= realms.size():
			continue
		var after := QiRealmSeed.for_realm(realms[index + 1].id)
		if after != null:
			assert_eq(
				after.required_channel_refinement <= seed.channel_refinement_cap,
				true,
				(
					"%s demands depth %d but %s only offers %d"
					% [
						realms[index + 1].id,
						after.required_channel_refinement,
						realms[index].id,
						seed.channel_refinement_cap,
					]
				)
			)


## The depth gate is only satisfiable on a strengthened channel, so a seed that
## asked for depth below `strengthened` would be unsatisfiable by construction.
func test_depth_is_never_demanded_below_strengthened() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null or seed.required_channel_refinement <= 0:
			continue
		assert_eq(
			seed.required_channel_state,
			MeridianState.STRENGTHENED,
			"%s demands depth %d" % [realm.id, seed.required_channel_refinement]
		)


# --- Channel state comparison ----------------------------------------------


func test_meets_compares_forward_states() -> void:
	var channel := MeridianState.new()
	channel.state = MeridianState.OPEN
	assert_eq(channel.meets(MeridianState.OPEN), true, "open meets open")
	assert_eq(channel.meets(MeridianState.EXPANDED), false, "open does not meet expanded")
	channel.state = MeridianState.EXPANDED
	assert_eq(channel.meets(MeridianState.OPEN), true, "expanded meets open")
	assert_eq(channel.meets(MeridianState.EXPANDED), true, "expanded meets expanded")
	channel.state = MeridianState.STRENGTHENED
	assert_eq(channel.meets(MeridianState.EXPANDED), true, "strengthened meets expanded")


func test_injured_channel_meets_nothing() -> void:
	var channel := MeridianState.new()
	channel.state = MeridianState.STRENGTHENED
	channel.injured = true
	assert_eq(channel.meets(MeridianState.CLOSED), false, "injured never satisfies")
	assert_eq(channel.meets(MeridianState.STRENGTHENED), false, "injured meets nothing")
	# Injury is recoverable and does not erase structural attainment.
	assert_eq(channel.state_rank(), 3, "injured keeps its structural rank")


func test_tier_gates_are_permissive_below_immortal() -> void:
	var actor := Actor.new(&"hero")
	# Index 0 targets the first Spirit realm: no tier gate applies yet.
	assert_eq(Breakthrough.tier_gates_met(actor, 0), true, "no gates at Mortal")
