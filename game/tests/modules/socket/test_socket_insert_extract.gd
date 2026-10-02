extends TestCase

## Moving a socket item into and out of a slot (ADR 0025/0026): identity is
## preserved in both directions, the rejections change nothing, and the worn
## contribution is applied exactly once with no drift across repeated cycles.

const HOST_REALM := &"qi_refining"
const REAGENT_OFFENSE := &"socket_reagent_mortal_slot_offense"
const REAGENT_DEFENSE := &"socket_reagent_mortal_slot_defense"
const REAGENT_IMPUTE := &"socket_reagent_mortal_imputation"


func _actor(capacity: int = 24) -> Actor:
	var actor := Actor.new(&"socket_bearer", {Stat.PHYSIQUE: 14.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.add_resource(ResourcePool.new(&"qi", 60.0))
	actor.add_resource(ResourcePool.new(&"stamina", 50.0))
	ItemsApi.attach(actor, capacity)
	SocketApi.attach(actor)
	return actor


## A hand-authored host so a test controls rarity and realm exactly. The shipped
## content is exercised separately, through the generator.
func _host_def(rarity: StringName = &"rare") -> ItemDef:
	var def := ItemDef.new()
	def.id = &"socket_test_blade"
	def.display_name = "Socket Test Blade"
	def.category = ItemCategory.EQUIPMENT
	def.subcategory = ItemSubtype.WEAPON
	def.grade = ItemGrade.SPIRIT
	def.stackable = false
	def.rarity = rarity
	def.realm = HOST_REALM
	def.roll_spec = {"count": ItemRarity.affix_count(rarity), "contexts": ["prefix", "postfix"]}
	def.fixed_modifiers = [{"option_id": &"core_attack_physical", "value": 5.0}]
	return def


## A hand-authored socket item: a real item definition with its own rarity,
## realm and rolled options, tagged so the socket program recognises it.
func _gem_def(kind: String, rarity: StringName = &"magic") -> ItemDef:
	var def := ItemDef.new()
	def.id = StringName("socket_test_gem_%s" % kind)
	def.display_name = "Socket Test %s" % kind
	def.category = ItemCategory.EQUIPMENT
	def.subcategory = &"gem"
	def.grade = ItemGrade.SPIRIT
	def.stackable = false
	def.rarity = rarity
	def.realm = HOST_REALM
	def.tags = [&"socket_item", StringName("socket_kind:%s" % kind)]
	def.roll_spec = {"count": ItemRarity.affix_count(rarity), "contexts": ["prefix", "postfix"]}
	def.fixed_modifiers = [{"option_id": &"core_attack_physical", "value": 3.0}]
	return def


func _acquire(actor: Actor, def: ItemDef, seed_value: int) -> ItemInstance:
	var instance := ItemsApi.generate(actor, def, seed_value)
	assert_ne(instance, null, "acquired %s" % def.id)
	return instance


func _give(actor: Actor, def_id: StringName, quantity: int) -> void:
	var def := SocketApi.resolve_content(def_id)
	assert_ne(def, null, "%s resolves" % def_id)
	assert_eq(ItemsApi.inventory(actor).add(def, quantity), 0, "%s carried" % def_id)


func _held(actor: Actor, def_id: StringName) -> int:
	return ItemsApi.inventory(actor).count(def_id)


func _slots(actor: Actor, host: ItemInstance) -> Array:
	return SocketApi.socket_state(actor)["parents"].get(String(host.instance_id), {}).get(
		"slots", []
	)


func _open_offense_slot(actor: Actor, host: ItemInstance) -> Dictionary:
	_give(actor, REAGENT_OFFENSE, 1)
	return SocketApi.create_slot(actor, host.instance_id, REAGENT_OFFENSE)


func _impute(actor: Actor, host: ItemInstance, index: int) -> Dictionary:
	_give(actor, REAGENT_IMPUTE, 1)
	return SocketApi.impute_slot(actor, host.instance_id, index, REAGENT_IMPUTE)


## The instance the actor carries under `instance_id`. `Inventory.find_instance`
## matches on the definition id despite its name, so an identity lookup scans the
## carried instances instead.
func _instance(actor: Actor, instance_id: String) -> ItemInstance:
	for instance in ItemsApi.inventory(actor).instances():
		if String(instance.instance_id) == instance_id:
			return instance
	return null


func _carries(actor: Actor, instance_id: StringName) -> bool:
	return _instance(actor, String(instance_id)) != null


func _modifier_delta(effects: Array) -> int:
	return (
		ItemEffects.stat_modifiers(effects, &"probe").size()
		+ ItemEffects.resource_modifiers(effects, &"probe").size()
	)


# --- Insert / extract ---------------------------------------------------------


func test_insert_then_extract_returns_the_same_instance_unrerolled() -> void:
	var actor := _actor()
	var host := _acquire(actor, _host_def(), 301)
	_open_offense_slot(actor, host)
	_impute(actor, host, 0)
	# `imputed_count` is a read-model key the ledger never stores, so a ledger-level
	# assertion reads the effects array the ledger really keeps.
	var carried: Array = (_slots(actor, host)[0] as Dictionary)["imputed"]
	assert_eq(carried.size(), SocketPolicy.IMPRINT_CAP, "the slot is imprinted")
	var gem := _acquire(actor, _gem_def("offense"), 302)
	var gem_id := String(gem.instance_id)
	var signature := gem.stacking_signature()
	var seed_value := gem.seed
	var rolled := gem.rolled.size()

	var inserted := SocketApi.insert_socket(actor, host.instance_id, 0, gem.instance_id)
	assert_eq(bool(inserted["ok"]), true, "inserted: %s" % inserted["reason"])
	assert_eq(_carries(actor, gem.instance_id), false, "the gem left the bag")
	assert_eq(
		String((_slots(actor, host)[0] as Dictionary)["gem"]["instance_id"]),
		gem_id,
		"the slot holds the same instance"
	)

	var extracted := SocketApi.extract_socket(actor, host.instance_id, 0)
	assert_eq(bool(extracted["ok"]), true, "extracted: %s" % extracted["reason"])
	var returned := _instance(actor, gem_id)
	assert_ne(returned, null, "the gem is back in the inventory")
	assert_eq(String(returned.instance_id), gem_id, "the same instance id")
	assert_eq(returned.stacking_signature(), signature, "not rerolled")
	assert_eq(returned.seed, seed_value, "the realization provenance is unchanged")
	assert_eq(returned.rolled.size(), rolled, "the same realized affixes")
	assert_eq(
		Dictionary((_slots(actor, host)[0] as Dictionary)["gem"]).is_empty(),
		true,
		"the slot is empty again"
	)
	assert_eq(
		(_slots(actor, host)[0] as Dictionary)["imputed"], carried, "the imputation is intact"
	)


func test_an_occupied_slot_is_rejected_with_no_state_change() -> void:
	var actor := _actor()
	var host := _acquire(actor, _host_def(), 303)
	_open_offense_slot(actor, host)
	var first := _acquire(actor, _gem_def("offense"), 304)
	var second := _acquire(actor, _gem_def("offense"), 305)
	assert_eq(
		bool(SocketApi.insert_socket(actor, host.instance_id, 0, first.instance_id)["ok"]),
		true,
		"first"
	)
	var before := _slots(actor, host)
	var refused := SocketApi.insert_socket(actor, host.instance_id, 0, second.instance_id)
	assert_eq(String(refused["reason"]), "slot_occupied", "the gameplay reason")
	assert_eq(_slots(actor, host), before, "the slot did not change")
	assert_ne(_carries(actor, second.instance_id), null, "the second gem is still carried")


func test_an_incompatible_slot_is_rejected_with_no_state_change() -> void:
	var actor := _actor()
	var host := _acquire(actor, _host_def(), 306)
	_open_offense_slot(actor, host)
	var defense := _acquire(actor, _gem_def("defense"), 307)
	var before := _slots(actor, host)
	var refused := SocketApi.insert_socket(actor, host.instance_id, 0, defense.instance_id)
	assert_eq(String(refused["reason"]), "incompatible_slot", "the gameplay reason")
	assert_eq(_slots(actor, host), before, "the slot did not change")
	assert_ne(_carries(actor, defense.instance_id), null, "the gem is still carried")


func test_a_recursive_socket_is_rejected_with_no_state_change() -> void:
	var actor := _actor()
	var host := _acquire(actor, _host_def(), 308)
	_open_offense_slot(actor, host)
	var gem := _acquire(actor, _gem_def("offense"), 309)
	_give(actor, REAGENT_OFFENSE, 2)
	# A socket item is never a socket host, so nesting is refused outright.
	var refused := SocketApi.create_slot(actor, gem.instance_id, REAGENT_OFFENSE)
	assert_eq(String(refused["reason"]), "recursive_socket", "the gameplay reason")
	assert_eq(_held(actor, REAGENT_OFFENSE), 2, "nothing consumed")
	assert_eq(
		SocketApi.socket_state(actor)["parents"].has(String(gem.instance_id)),
		false,
		"no state written"
	)


func test_extracting_into_a_full_inventory_keeps_the_gem_in_its_slot() -> void:
	var actor := _actor(3)
	var host := _acquire(actor, _host_def(), 310)
	var gem := _acquire(actor, _gem_def("offense"), 311)
	_give(actor, REAGENT_OFFENSE, 1)
	assert_eq(ItemsApi.inventory(actor).used_slots(), 3, "host, gem and reagent fill the bag")
	assert_eq(
		bool(SocketApi.create_slot(actor, host.instance_id, REAGENT_OFFENSE)["ok"]),
		true,
		"slot opened"
	)
	assert_eq(
		bool(SocketApi.insert_socket(actor, host.instance_id, 0, gem.instance_id)["ok"]),
		true,
		"inserted"
	)
	assert_eq(ItemsApi.inventory(actor).used_slots(), 1, "only the host is left in the bag")
	ItemsApi.inventory(actor).add(_filler(311), 1)
	ItemsApi.inventory(actor).add(_filler(312), 1)
	assert_eq(ItemsApi.inventory(actor).is_full(), true, "the bag refilled")
	var before := _slots(actor, host)
	var refused := SocketApi.extract_socket(actor, host.instance_id, 0)
	assert_eq(String(refused["reason"]), "inventory_full", "the gameplay reason")
	assert_eq(_slots(actor, host), before, "the gem is still socketed")
	assert_eq(
		SocketApi.extract_socket(actor, host.instance_id, 1)["reason"],
		"slot_empty",
		"and only one slot"
	)


## A distinct non-stackable filler, so filling the bag costs one slot each.
func _filler(seed_value: int) -> ItemDef:
	var def := ItemDef.new()
	def.id = StringName("socket_test_filler_%d" % seed_value)
	def.category = ItemCategory.MISC
	def.stackable = false
	return def


# --- Equipped contribution ----------------------------------------------------


func test_equipped_stats_include_slot_and_gem_contributions_exactly_once() -> void:
	var actor := _actor()
	var host_def := _host_def()
	var host := _acquire(actor, host_def, 401)
	assert_eq(ItemsApi.equip_item(actor, Equipment.WEAPON, host_def), true, "equipped")
	var parent_modifiers := actor.stats.modifier_count()
	var attack_before := actor.stats.derived(Stat.ATTACK_PHYSICAL)
	var before_derived := actor.stats.derived_all()

	_open_offense_slot(actor, host)
	_impute(actor, host, 0)
	var ledger := actor.component(SocketApi.LEDGER_COMPONENT) as SocketLedger
	var imputed := SocketEffects.contribution(ledger, host.instance_id)
	assert_eq((imputed as Array).is_empty(), false, "the worn slot contributes")
	assert_eq(
		actor.stats.modifier_count() - parent_modifiers,
		_modifier_delta(imputed),
		"the slot's effects are applied exactly once"
	)
	var attack_imputed := actor.stats.derived(Stat.ATTACK_PHYSICAL)
	# Every slot modifier that lands on a stat the actor actually derives moves it
	# by exactly its flat value, which is what "applied exactly once" means at the
	# stat pipeline rather than only in the modifier stack.
	for effect in imputed:
		var stat_id := StringName(effect.get("target_id", &""))
		if not before_derived.has(stat_id):
			continue
		if StringName(effect.get("op", &"FLAT")) != &"FLAT":
			continue
		assert_almost_eq(
			actor.stats.derived(stat_id),
			float(before_derived[stat_id]) + float(effect.get("value", 0.0)),
			"the slot moved %s by exactly its own value" % stat_id
		)

	var gem := _acquire(actor, _gem_def("offense"), 402)
	assert_eq(
		bool(SocketApi.insert_socket(actor, host.instance_id, 0, gem.instance_id)["ok"]),
		true,
		"inserted"
	)
	var both := SocketEffects.contribution(ledger, host.instance_id)
	assert_eq(
		actor.stats.modifier_count() - parent_modifiers,
		_modifier_delta(both),
		"slot and gem together are applied exactly once each"
	)
	assert_eq(
		actor.stats.derived(Stat.ATTACK_PHYSICAL) > attack_imputed,
		true,
		"the gem adds its own contribution"
	)
	var attack_both := actor.stats.derived(Stat.ATTACK_PHYSICAL)

	assert_eq(bool(SocketApi.extract_socket(actor, host.instance_id, 0)["ok"]), true, "extracted")
	assert_almost_eq(
		actor.stats.derived(Stat.ATTACK_PHYSICAL),
		attack_imputed,
		"removing the gem removes only its part"
	)
	assert_eq(
		_modifier_delta(SocketEffects.contribution(ledger, host.instance_id)),
		_modifier_delta(imputed),
		"the extract left the slot's own contribution in place"
	)
	assert_eq(attack_both > attack_imputed, true, "the gem was the difference")


func test_repeated_insert_and_extract_does_not_drift() -> void:
	var actor := _actor()
	var host_def := _host_def()
	var host := _acquire(actor, host_def, 501)
	assert_eq(ItemsApi.equip_item(actor, Equipment.WEAPON, host_def), true, "equipped")
	_open_offense_slot(actor, host)
	_impute(actor, host, 0)
	var baseline_modifiers := actor.stats.modifier_count()
	var baseline_attack := actor.stats.derived(Stat.ATTACK_PHYSICAL)
	for cycle in 3:
		var gem := _acquire(actor, _gem_def("offense"), 600 + cycle)
		assert_eq(
			bool(SocketApi.insert_socket(actor, host.instance_id, 0, gem.instance_id)["ok"]),
			true,
			"inserted on cycle %d" % cycle
		)
		assert_eq(
			bool(SocketApi.extract_socket(actor, host.instance_id, 0)["ok"]), true, "extracted"
		)
		assert_eq(
			actor.stats.modifier_count(),
			baseline_modifiers,
			"the modifier stack returns to its baseline on cycle %d" % cycle
		)
		assert_almost_eq(
			actor.stats.derived(Stat.ATTACK_PHYSICAL),
			baseline_attack,
			"the stat returns to its baseline on cycle %d" % cycle
		)


func test_unequipping_removes_the_socket_contribution() -> void:
	var actor := _actor()
	var host_def := _host_def()
	var host := _acquire(actor, host_def, 701)
	assert_eq(ItemsApi.equip_item(actor, Equipment.WEAPON, host_def), true, "equipped")
	_open_offense_slot(actor, host)
	_impute(actor, host, 0)
	var worn := actor.stats.modifier_count()
	var gem := _acquire(actor, _gem_def("offense"), 702)
	assert_eq(
		bool(SocketApi.insert_socket(actor, host.instance_id, 0, gem.instance_id)["ok"]),
		true,
		"inserted"
	)
	assert_eq(actor.stats.modifier_count() > worn, true, "the gem added modifiers while worn")
	assert_eq(bool(ItemsApi.unequip_to_inventory(actor, Equipment.WEAPON)), true, "unequipped")
	var ledger := actor.component(SocketApi.LEDGER_COMPONENT) as SocketLedger
	var contribution := SocketEffects.contribution(ledger, host.instance_id)
	assert_eq(actor.stats.modifier_count(), 0, "an unworn host contributes nothing at all")
	assert_eq(bool(ItemsApi.equip_item(actor, Equipment.WEAPON, host_def)), true, "equipped again")
	assert_eq(
		actor.stats.modifier_count(),
		_modifier_delta(SocketPolicy.effects_of(host)) + _modifier_delta(contribution),
		"re-equipping restores the host and its socket contribution exactly once"
	)


func test_the_imprint_cap_is_per_slot_not_per_item() -> void:
	var actor := _actor()
	var host := _acquire(actor, _host_def(&"legendary"), 801)
	_open_offense_slot(actor, host)
	_open_offense_slot(actor, host)
	assert_eq(_slots(actor, host).size(), 2, "two slots")
	_give(actor, REAGENT_IMPUTE, 4)
	assert_eq(
		bool(SocketApi.impute_slot(actor, host.instance_id, 0, REAGENT_IMPUTE)["ok"]),
		true,
		"the first slot imputes"
	)
	assert_eq(
		bool(SocketApi.impute_slot(actor, host.instance_id, 1, REAGENT_IMPUTE)["ok"]),
		true,
		"the second slot imputes from its own budget"
	)
	for slot_entry in _slots(actor, host):
		assert_eq(
			(slot_entry["imputed"] as Array).size(),
			SocketPolicy.IMPRINT_CAP,
			"every slot carries its own imprint"
		)
	var spent := _held(actor, REAGENT_IMPUTE)
	var at_cap := SocketApi.impute_slot(actor, host.instance_id, 1, REAGENT_IMPUTE)
	assert_eq(String(at_cap["reason"]), "imprint_cap_reached", "a full slot refuses")
	assert_eq(_held(actor, REAGENT_IMPUTE), spent, "nothing consumed at the cap")
