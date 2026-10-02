extends TestCase

## Socket state across the actor payload (ADR 0027). The socket subsystem's
## whole ledger lives in `actor.module_data["socket_state"]`, so a save/load round
## trip through `Actor.to_dict()` restores every slot, every inserted gem and
## every enchantment exactly as it was — never rerolled, never duplicated.

const SLOT_REAGENT := &"socket_reagent_mortal_slot_offense"
const INK := &"socket_reagent_mortal_imputation"
const WASH := &"socket_reagent_mortal_enchantment"


func _actor(capacity: int = 24) -> Actor:
	var actor := Actor.new(&"socket_keeper", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	ItemsApi.attach(actor, capacity)
	SocketApi.attach(actor)
	return actor


## Everything this suite persists is shipped content: a save restores
## definitions by id, so an in-memory-only definition cannot survive a round
## trip and a fixture built from one would prove nothing.
func _host_def() -> ItemDef:
	return SocketApi.resolve_content(&"socket_host_rare_blade")


func _gem_def() -> ItemDef:
	return SocketApi.resolve_content(&"socket_rune_mortal_offense")


func _give(actor: Actor, def_id: StringName, quantity: int = 1) -> void:
	var def := SocketApi.resolve_content(def_id)
	assert_ne(def, null, "%s resolves" % def_id)
	ItemsApi.inventory(actor).add(def, quantity)


## Round trip an actor through its own payload, the way a save/load does.
func _reloaded(actor: Actor) -> Actor:
	var payload := actor.to_dict()
	var restored := Actor.from_dict(payload)
	ItemsApi.attach(restored)
	SocketApi.attach(restored)
	return restored


func _build_a_fully_dressed_host(actor: Actor) -> Dictionary:
	var host := ItemsApi.generate(actor, _host_def(), 11)
	_give(actor, SLOT_REAGENT)
	assert_eq(
		bool(SocketApi.create_slot(actor, host.instance_id, SLOT_REAGENT)["ok"]), true, "slot"
	)
	_give(actor, INK)
	assert_eq(bool(SocketApi.impute_slot(actor, host.instance_id, 0, INK)["ok"]), true, "imputed")
	var gem := ItemsApi.generate(actor, _gem_def(), 12)
	assert_eq(
		bool(SocketApi.insert_socket(actor, host.instance_id, 0, gem.instance_id)["ok"]),
		true,
		"inserted"
	)
	_give(actor, WASH)
	assert_eq(
		bool(SocketApi.commit_enchantment(actor, host.instance_id, WASH, &"req_1", 33)["ok"]),
		true,
		"enchanted"
	)
	return {"host": host, "gem": gem}


func test_a_round_trip_restores_every_slot_gem_and_enchantment() -> void:
	var actor := _actor()
	var built := _build_a_fully_dressed_host(actor)
	var host: ItemInstance = built["host"]
	var gem: ItemInstance = built["gem"]
	var before_state := SocketApi.socket_state(actor)

	var restored := _reloaded(actor)
	assert_eq(SocketApi.socket_state(restored), before_state, "the ledger is restored verbatim")
	var restored_host := _carried(restored, String(host.instance_id))
	assert_ne(restored_host, null, "the host is back")
	assert_eq(restored_host.stacking_signature(), host.stacking_signature(), "never rerolled")

	var slot_entry: Dictionary = (
		SocketApi.socket_state(restored)["parents"][String(host.instance_id)]["slots"][0]
	)
	var stored_gem: Dictionary = slot_entry["gem"]
	assert_eq(
		String(stored_gem["instance_id"]), String(gem.instance_id), "the gem kept its identity"
	)
	assert_eq(
		SocketApi.extract_socket(restored, restored_host.instance_id, 0)["ok"], true, "extracted"
	)
	var returned := _carried(restored, String(gem.instance_id))
	assert_ne(returned, null, "the restored gem is movable again")
	assert_eq(returned.stacking_signature(), gem.stacking_signature(), "and unrerolled")


func test_the_restored_socket_still_contributes_while_worn() -> void:
	var actor := _actor()
	var host_def := _host_def()
	var host := ItemsApi.generate(actor, host_def, 21)
	_give(actor, SLOT_REAGENT)
	assert_eq(
		bool(SocketApi.create_slot(actor, host.instance_id, SLOT_REAGENT)["ok"]), true, "slot"
	)
	_give(actor, INK)
	assert_eq(bool(SocketApi.impute_slot(actor, host.instance_id, 0, INK)["ok"]), true, "imputed")

	# Restored, then worn: the socket contribution is rebuilt from the restored
	# ledger, so equip/unequip and a load see the same numbers.
	var restored := _reloaded(actor)
	var restored_host := _carried(restored, String(host.instance_id))
	assert_ne(restored_host, null, "the host is back")
	assert_ne(restored_host.def_ref, null, "with its definition re-resolved")
	assert_eq(ItemsApi.equip_item(restored, Equipment.WEAPON, host_def), true, "equipped")
	var ledger := restored.component(SocketApi.LEDGER_COMPONENT) as SocketLedger
	var contribution := SocketEffects.contribution(ledger, restored_host.instance_id)
	assert_eq(
		restored.stats.modifier_count(),
		_modifier_delta(SocketPolicy.effects_of(restored_host)) + _modifier_delta(contribution),
		"the host and its socket contribution are applied exactly once"
	)
	assert_eq(
		SocketApi.extract_socket(restored, restored_host.instance_id, 0)["reason"],
		"slot_empty",
		"and the restored slot answers with its stored state"
	)


func test_a_legacy_payload_without_socket_state_loads_cleanly() -> void:
	var actor := _actor()
	var host := ItemsApi.generate(actor, _host_def(), 31)
	var payload := actor.to_dict()
	# A save written before the socket subsystem existed carries no socket state.
	payload["module_data"] = {}
	assert_eq(payload.has("socket_state"), false, "core wrote no socket payload")
	var restored := Actor.from_dict(payload)
	ItemsApi.attach(restored)
	SocketApi.attach(restored)
	var state := SocketApi.socket_state(restored)
	assert_eq(int(state["version"]), SocketLedger.VERSION, "an empty ledger at the current shape")
	assert_eq((state["parents"] as Dictionary).is_empty(), true, "no parents")
	assert_eq((state["channels"] as Dictionary).is_empty(), true, "no channels")
	assert_eq((state["requests"] as Dictionary).is_empty(), true, "no recorded requests")
	var restored_host := _carried(restored, String(host.instance_id))
	assert_ne(restored_host, null, "item state still restored")
	# The subsystem is fully usable on a legacy save.
	_give(restored, SLOT_REAGENT)
	assert_eq(
		bool(SocketApi.create_slot(restored, restored_host.instance_id, SLOT_REAGENT)["ok"]),
		true,
		"a slot opens on a legacy save"
	)


func test_loading_twice_replaces_socket_state_instead_of_appending() -> void:
	var actor := _actor()
	var built := _build_a_fully_dressed_host(actor)
	var host: ItemInstance = built["host"]
	var payload := actor.to_dict()
	var first := _reloaded(actor)
	var second := Actor.from_dict(payload)
	ItemsApi.attach(second)
	SocketApi.attach(second)
	assert_eq(
		SocketApi.socket_state(first),
		SocketApi.socket_state(second),
		"a second load reproduces the same ledger"
	)
	var slots: Array = SocketApi.socket_state(second)["parents"][String(host.instance_id)]["slots"]
	assert_eq(slots.size(), 1, "loading never appends a second slot")
	assert_eq(
		int(SocketApi.socket_state(second)["channels"][String(host.instance_id)]["generation"]),
		1,
		"and never a second enchantment"
	)


func _modifier_delta(effects: Array) -> int:
	return (
		ItemEffects.stat_modifiers(effects, &"probe").size()
		+ ItemEffects.resource_modifiers(effects, &"probe").size()
	)


## The instance `actor` owns under `instance_id`. `Inventory.find_instance`
## matches on the definition id despite its name, so identity lookups scan the
## carried and worn instances instead.
func _carried(actor: Actor, instance_id: String) -> ItemInstance:
	for instance in ItemsApi.inventory(actor).instances():
		if String(instance.instance_id) == instance_id:
			return instance
	for slot in Equipment.SLOTS:
		var equipped := ItemsApi.equipment(actor).equipped(slot)
		if equipped != null and String(equipped.instance_id) == instance_id:
			return equipped
	return null
