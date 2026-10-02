extends TestCase

## The first two slot transactions (ADR 0025/0026): opening a socket costs
## exactly one reagent and stops at the item's rarity cap, and an empty slot's
## own modifiers are realized from the socket slot pool and belong to the slot.

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


## How many effects a slot's own imprint carries, read from the ledger. The
## persisted slot stores the effects as an array; `imputed_count` is the
## read-model key the UI shows, so a ledger-level assertion counts the array.
func _imputed(actor: Actor, host: ItemInstance, index: int) -> Array:
	return ((_slots(actor, host)[index] as Dictionary)["imputed"] as Array).duplicate()


# --- Slot creation ------------------------------------------------------------


func test_slot_creation_consumes_exactly_one_reagent() -> void:
	var actor := _actor()
	var host := _acquire(actor, _host_def(), 101)
	_give(actor, REAGENT_OFFENSE, 3)
	var result := SocketApi.create_slot(actor, host.instance_id, REAGENT_OFFENSE)
	assert_eq(bool(result["ok"]), true, "slot opened: %s" % result["reason"])
	assert_eq(_held(actor, REAGENT_OFFENSE), 2, "exactly one reagent spent")
	assert_eq(_slots(actor, host).size(), 1, "one slot recorded")
	assert_eq(
		String((_slots(actor, host)[0] as Dictionary)["kind"]), "offense", "kind from the reagent"
	)


func test_slot_creation_refuses_a_second_slot_at_the_rarity_cap() -> void:
	var actor := _actor()
	var host := _acquire(actor, _host_def(&"rare"), 102)
	assert_eq(SocketPolicy.slot_cap(&"rare"), 1, "a rare item carries one socket")
	_give(actor, REAGENT_OFFENSE, 4)
	assert_eq(
		bool(SocketApi.create_slot(actor, host.instance_id, REAGENT_OFFENSE)["ok"]), true, "first"
	)
	var refused := SocketApi.create_slot(actor, host.instance_id, REAGENT_OFFENSE)
	assert_eq(bool(refused["ok"]), false, "second refused")
	assert_eq(String(refused["reason"]), "cap_reached", "the gameplay reason")
	assert_eq(_held(actor, REAGENT_OFFENSE), 3, "nothing consumed at the cap")
	assert_eq(_slots(actor, host).size(), 1, "still one slot")

	var legend := _acquire(actor, _host_def(&"legendary"), 103)
	assert_eq(SocketPolicy.slot_cap(&"legendary"), 2, "a legendary item carries two sockets")
	assert_eq(
		bool(SocketApi.create_slot(actor, legend.instance_id, REAGENT_OFFENSE)["ok"]), true, "one"
	)
	assert_eq(
		bool(SocketApi.create_slot(actor, legend.instance_id, REAGENT_OFFENSE)["ok"]), true, "two"
	)
	var at_cap := SocketApi.create_slot(actor, legend.instance_id, REAGENT_OFFENSE)
	assert_eq(String(at_cap["reason"]), "cap_reached", "refused at the cap")
	assert_eq(_slots(actor, legend).size(), 2, "still two slots")
	assert_eq(_held(actor, REAGENT_OFFENSE), 1, "nothing consumed at the cap")


func test_slot_creation_refuses_without_the_reagent_and_consumes_nothing() -> void:
	var actor := _actor()
	var host := _acquire(actor, _host_def(), 104)
	assert_eq(_held(actor, REAGENT_OFFENSE), 0, "no reagent carried")
	var refused := SocketApi.create_slot(actor, host.instance_id, REAGENT_OFFENSE)
	assert_eq(String(refused["reason"]), "missing_cost", "the gameplay reason")
	assert_eq(_slots(actor, host).size(), 0, "no slot opened")
	var unknown := SocketApi.create_slot(actor, host.instance_id, &"socket_not_a_reagent")
	assert_eq(String(unknown["reason"]), "unknown_reagent", "an unknown reagent is refused")
	assert_eq(
		SocketApi.create_slot(actor, &"nobody", REAGENT_OFFENSE)["reason"],
		"unknown_parent",
		"no host"
	)


# --- Imputation ---------------------------------------------------------------


func test_imputed_effects_belong_to_the_slot_and_survive_the_gem() -> void:
	var actor := _actor()
	var host := _acquire(actor, _host_def(), 201)
	_open_offense_slot(actor, host)
	var imputed := _impute(actor, host, 0)
	assert_eq(bool(imputed["ok"]), true, "imputed: %s" % imputed["reason"])
	assert_eq(_held(actor, REAGENT_IMPUTE), 0, "exactly one reagent spent")
	var stored: Array = (_slots(actor, host)[0] as Dictionary)["imputed"]
	assert_eq(stored.is_empty(), false, "the slot carries its own effects")

	var gem := _acquire(actor, _gem_def("offense"), 202)
	assert_eq(
		bool(SocketApi.insert_socket(actor, host.instance_id, 0, gem.instance_id)["ok"]),
		true,
		"inserted"
	)
	assert_eq(
		(_slots(actor, host)[0] as Dictionary)["imputed"],
		stored,
		"inserting a gem leaves the slot's own effects untouched"
	)
	assert_eq(bool(SocketApi.extract_socket(actor, host.instance_id, 0)["ok"]), true, "extracted")
	assert_eq(
		(_slots(actor, host)[0] as Dictionary)["imputed"],
		stored,
		"extracting the gem leaves the slot's own effects untouched"
	)


func test_imputation_refuses_a_slot_that_already_carries_its_cap() -> void:
	var actor := _actor()
	var host := _acquire(actor, _host_def(), 203)
	_open_offense_slot(actor, host)
	assert_eq(bool(_impute(actor, host, 0)["ok"]), true, "imputed once")
	assert_eq(_imputed(actor, host, 0).size(), SocketPolicy.IMPRINT_CAP, "the slot is at its cap")
	_give(actor, REAGENT_IMPUTE, 2)
	var again := SocketApi.impute_slot(actor, host.instance_id, 0, REAGENT_IMPUTE)
	assert_eq(String(again["reason"]), "imprint_cap_reached", "a slot carries at most its cap")
	assert_eq(_held(actor, REAGENT_IMPUTE), 2, "nothing consumed")

	# A second host proves the slot's effects are the slot's own: imputing a
	# different slot on a different item never reads the first one's state.
	var carried := _imputed(actor, host, 0)
	var second := _acquire(actor, _host_def(), 204)
	_open_offense_slot(actor, second)
	assert_eq(bool(_impute(actor, second, 0)["ok"]), true, "the other slot imputes independently")
	assert_eq(_imputed(actor, host, 0), carried, "the first slot is untouched")


func test_imputation_refuses_a_slot_index_the_item_does_not_have() -> void:
	var actor := _actor()
	var host := _acquire(actor, _host_def(), 206)
	_give(actor, REAGENT_IMPUTE, 1)
	assert_eq(
		String(SocketApi.impute_slot(actor, host.instance_id, 0, REAGENT_IMPUTE)["reason"]),
		"no_slot",
		"there is no slot to impute"
	)
	assert_eq(_held(actor, REAGENT_IMPUTE), 1, "nothing consumed")
