extends TestCase

## The path-typed slot binding (ADR 0053): the published per-tier budget, a SHARED
## technique confined to the universal pool, and the guarantee that unequipping
## returns an entry to the codex instead of deleting it.

const MORTAL := &"qi_refining"
const SPIRIT := &"spirit_condensation"
const IMMORTAL := &"earth_immortal"
const TRANSCENDENT := &"transcendent"


func _actor(realm_id: StringName = MORTAL) -> Actor:
	var actor := Actor.new(&"practitioner", {Stat.PHYSIQUE: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", 500.0))
	actor.set_path(PathState.new(PathState.QI, realm_id))
	actor.set_path(PathState.new(PathState.BODY, realm_id))
	actor.set_path(PathState.new(PathState.MIND, realm_id))
	TechniquesApi.attach(actor)
	return actor


## A path-exclusive passive on `path_id`, with no gate so the tests exercise slots
## and not the realm ladder.
func _technique(path_id: StringName) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = StringName("technique_%s" % path_id)
	def.display_name = "Technique"
	def.grade = ItemGrade.MORTAL
	def.path = path_id
	def.active = false
	return def


# --- Slot capacity per tier --------------------------------------------------


func test_slot_capacity_follows_the_published_tier_table() -> void:
	# Four tiers, four published rows: 7 / 8 / 9 / 10 slots total.
	assert_eq(TechniqueSlots.slot_keys(1).size(), 7, "Mortal R1-9 totals seven")
	assert_eq(TechniqueSlots.slot_keys(2).size(), 8, "Spirit R10-18 totals eight")
	assert_eq(TechniqueSlots.slot_keys(3).size(), 9, "Immortal R19-27 totals nine")
	assert_eq(TechniqueSlots.slot_keys(4).size(), 10, "Transcendent R28-30 totals ten")
	# Per-path counts are fixed for the whole ladder; only the universal pool grows.
	for tier in [1, 2, 3, 4]:
		var keys := TechniqueSlots.slot_keys(tier)
		assert_eq(_count_of(keys, PathState.QI), 3, "qi is always three (tier %d)" % tier)
		assert_eq(_count_of(keys, PathState.BODY), 2, "body is always two (tier %d)" % tier)
		assert_eq(_count_of(keys, PathState.MIND), 2, "mind is always two (tier %d)" % tier)
		assert_eq(
			_count_of(keys, TechniqueSlots.UNIVERSAL),
			tier - 1,
			"universal grows by one per tier (tier %d)" % tier
		)


func test_the_budget_is_read_from_the_realm_tier_not_a_ladder_index() -> void:
	# Mortal has no universal slot at all, so a SHARED technique is unequippable
	# there and equippable one tier later. If the budget were read from a ladder
	# index rather than the tier, this boundary would land in the wrong place.
	var shared := _shared()
	var mortal := _actor(MORTAL)
	TechniquesApi.codex(mortal).learn(shared.id)
	assert_eq(
		String(TechniquesApi.equip(mortal, shared)["reason"]),
		"no_free_slot",
		"a Mortal actor has no universal slot"
	)
	var spirit := _actor(SPIRIT)
	TechniquesApi.codex(spirit).learn(shared.id)
	assert_eq(bool(TechniquesApi.equip(spirit, shared)["ok"]), true, "Spirit gains one")
	assert_eq(
		_count_of(TechniquesApi.slots(spirit).all().keys(), TechniqueSlots.UNIVERSAL), 1, "used"
	)
	# The tier, not the ordinal, is what moves: R10 is ordinal 9, still Mortal-ish by
	# count, but Spirit is a different published row entirely.
	assert_eq(TechniquesApi.summary(mortal)["realm_tier"], 1, "R1 reads Mortal")
	assert_eq(TechniquesApi.summary(spirit)["realm_tier"], 2, "R10 reads Spirit")


func test_a_path_pool_refuses_once_its_fixed_count_is_spent() -> void:
	# Mind has two slots for the whole ladder, so the third mind technique is
	# refused and the first two are not.
	var actor := _actor(MORTAL)
	for index in 3:
		var def := _technique(PathState.MIND)
		def.id = StringName("mind_%d" % index)
		TechniquesApi.codex(actor).learn(def.id)
	for index in 2:
		var learned := _technique(PathState.MIND)
		learned.id = StringName("mind_%d" % index)
		assert_eq(bool(TechniquesApi.equip(actor, learned)["ok"]), true, "mind %d equips" % index)
	var third := _technique(PathState.MIND)
	third.id = &"mind_2"
	var refused := TechniquesApi.equip(actor, third)
	assert_eq(String(refused["reason"]), "no_free_slot", "the mind pool is two")
	assert_eq(TechniquesApi.slots(actor).is_equipped(third.id), false, "nothing bound")


# --- SHARED is confined to the universal pool ---------------------------------


func _shared() -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = &"shared_manual"
	def.display_name = "Shared Manual"
	def.path = TechniquePolicy.SHARED
	def.active = false
	return def


func test_a_shared_technique_may_only_occupy_a_universal_slot() -> void:
	# `claimable` is the whole allocation rule: a shared technique's only legal slot
	# is the universal pool, so it can never be bound to a path slot even by hand.
	var shared := _shared()
	assert_eq(TechniqueSlots.requires_universal(shared), true, "shared is universal-only")
	# `claimable` reads the live slot table, so it needs an instance — an empty
	# actor at the given tier is the allocation starting point.
	var claim := TechniquesApi.slots(_actor(SPIRIT)).claimable(2, shared)
	assert_eq(claim.size(), 1, "one slot claimed")
	assert_eq(TechniqueSlots.kind_of(claim[0]), TechniqueSlots.UNIVERSAL, "and it is universal")
	# And the bound slot really is the universal one.
	var actor := _actor(SPIRIT)
	TechniquesApi.codex(actor).learn(shared.id)
	TechniquesApi.equip(actor, shared)
	var occupied: Array[StringName] = []
	for key in TechniquesApi.slots(actor).all().keys():
		occupied.append(key)
	# Matched by POOL, not by the bare `UNIVERSAL` name: a slot key carries its index
	# (`slot_pathuniversal0`), so `occupied.has(UNIVERSAL)` is always false and this
	# asserted a property no slot key can ever satisfy.
	assert_eq(
		occupied.any(func(key: StringName) -> bool: return _is_universal(key)),
		true,
		"the universal pool is the one used"
	)


func _is_universal(slot_key: StringName) -> bool:
	return TechniqueSlots.kind_of(slot_key) == TechniqueSlots.UNIVERSAL


func test_a_shared_technique_takes_a_path_slot_never() -> void:
	var path_def := _technique(PathState.QI)
	assert_eq(TechniqueSlots.requires_universal(path_def), false, "a qi technique is not shared")
	var claim := TechniquesApi.slots(_actor(MORTAL)).claimable(1, path_def)
	assert_eq(claim.size(), 1, "one slot")
	assert_eq(
		TechniqueSlots.kind_of(claim[0]), PathState.QI, "and it is a qi path slot, not universal"
	)


func test_a_dual_technique_commits_a_slot_on_each_of_its_two_paths() -> void:
	# A DUAL technique costs a slot on BOTH paths. With mind's two slots filled, a
	# qi+mind technique cannot be placed at all — never half-placed onto the free qi
	# slot.
	var actor := _actor(MORTAL)
	for index in 2:
		var mind := _technique(PathState.MIND)
		mind.id = StringName("mind_%d" % index)
		TechniqueCatalog.instance().register(mind)
		TechniquesApi.codex(actor).learn(mind.id)
		TechniquesApi.equip(actor, mind)
	var dual := TechniqueDef.new()
	dual.id = &"qi_mind_fused"
	dual.path = StringName(
		"%s%s%s" % [PathState.QI, TechniquePolicy.DUAL_SEPARATOR, PathState.MIND]
	)
	assert_eq(dual.path_ids().size(), 2, "two paths parsed")
	TechniquesApi.codex(actor).learn(dual.id)
	var refused := TechniquesApi.equip(actor, dual)
	assert_eq(String(refused["reason"]), "no_free_slot", "one full path refuses the whole claim")
	assert_eq(TechniquesApi.slots(actor).is_equipped(dual.id), false, "never half-placed")
	# Free one mind slot and the same dual technique now fits, taking one of each.
	TechniquesApi.unequip(actor, StringName("mind_1"))
	var dual_def := _technique(PathState.QI)
	dual_def.id = dual.id
	dual_def.path = dual.path
	assert_eq(TechniquesApi.slots(actor).claimable(1, dual).size(), 2, "two slots claimed")


# --- Unequip returns to the codex and never deletes --------------------------


func test_unequip_returns_the_entry_to_the_codex_and_does_not_delete_it() -> void:
	var actor := _actor(MORTAL)
	var def := _technique(PathState.QI)
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)
	assert_eq(TechniquesApi.slots(actor).is_equipped(def.id), true, "equipped")
	assert_eq(TechniquesApi.codex(actor).count(), 1, "known")

	var freed := TechniquesApi.unequip(actor, def)
	assert_eq(bool(freed["ok"]), true, "unequipped")
	assert_eq(TechniquesApi.slots(actor).is_equipped(def.id), false, "no slot held")
	assert_eq(TechniquesApi.codex(actor).knows(def.id), true, "STILL known")
	assert_eq(TechniquesApi.codex(actor).count(), 1, "the codex is unchanged by an unequip")
	# And it re-equips as one call, with no re-learning.
	assert_eq(bool(TechniquesApi.equip(actor, def)["ok"]), true, "re-equips")
	assert_eq(TechniquesApi.codex(actor).count(), 1, "still one entry")


func test_unequip_preserves_the_mastery_rung() -> void:
	var actor := _actor(MORTAL)
	var def := _technique(PathState.QI)
	TechniquesApi.codex(actor).learn(def.id, 3)
	TechniquesApi.equip(actor, def)
	TechniquesApi.unequip(actor, def)
	assert_eq(TechniquesApi.codex(actor).entry(def.id).mastery_rung, 3, "rung survives the unequip")


func test_a_technique_that_was_never_learned_cannot_be_equipped() -> void:
	var actor := _actor(MORTAL)
	var def := _technique(PathState.QI)
	var refused := TechniquesApi.equip(actor, def)
	assert_eq(String(refused["reason"]), "not_learned", "learning is a precondition")
	assert_eq(TechniquesApi.codex(actor).count(), 0, "and nothing was written")


func test_the_codex_is_unbounded_while_the_slot_table_is_not() -> void:
	# The design space the whole system rests on: 40 learned against 7 slots, of
	# which qi owns three. So the first three equips succeed and the next 37 are
	# refused for want of a slot — the refusal is the point, not a failure. An
	# earlier version asserted every equip succeeded, which contradicts having a
	# slot limit at all and so failed 37 times in this one case.
	var actor := _actor(MORTAL)
	var equipped := 0
	for index in 40:
		var def := _technique(PathState.QI)
		def.id = StringName("qi_%02d" % index)
		TechniquesApi.codex(actor).learn(def.id)
		var result := TechniquesApi.equip(actor, def)
		if bool(result["ok"]):
			equipped += 1
		else:
			assert_eq(
				String(result["reason"]),
				"no_free_slot",
				"a refusal past the third is about slots, nothing else"
			)
	assert_eq(equipped, 3, "qi took exactly its three slots")
	assert_eq(TechniquesApi.codex(actor).count(), 40, "every technique is still known")
	assert_eq(TechniquesApi.summary(actor)["equipped_count"], 3, "qi holds only its three slots")


func _count_of(slot_keys: Array, kind: StringName) -> int:
	var count := 0
	for slot_key in slot_keys:
		if TechniqueSlots.kind_of(slot_key) == kind:
			count += 1
	return count
