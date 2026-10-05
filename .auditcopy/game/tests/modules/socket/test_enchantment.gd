extends TestCase

## The enchantment channel: one replaceable channel per target, a preview that
## changes nothing, an atomic commit that spends exactly once, options this
## module does not author left alone, and idempotence across a save/load round
## trip (ADR 0025/0026/0027).

const REAGENT := &"socket_reagent_mortal_enchantment"


func _actor(capacity: int = 24) -> Actor:
	var actor := Actor.new(&"socket_etcher", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.add_resource(ResourcePool.new(&"qi", 60.0))
	ItemsApi.attach(actor, capacity)
	SocketApi.attach(actor)
	return actor


func _host_def(rarity: StringName = &"rare") -> ItemDef:
	var def := ItemDef.new()
	def.id = &"socket_test_helm"
	def.display_name = "Socket Test Helm"
	def.category = ItemCategory.EQUIPMENT
	def.subcategory = ItemSubtype.ARMOR
	def.grade = ItemGrade.SPIRIT
	def.stackable = false
	def.rarity = rarity
	def.realm = &"qi_refining"
	def.roll_spec = {"count": ItemRarity.affix_count(rarity), "contexts": ["prefix", "postfix"]}
	def.fixed_modifiers = [{"option_id": &"core_defense_physical", "value": 4.0}]
	return def


func _give(actor: Actor, quantity: int) -> void:
	var def := SocketApi.resolve_content(REAGENT)
	assert_ne(def, null, "the enchantment reagent resolves from shipped content")
	ItemsApi.inventory(actor).add(def, quantity)


func _held(actor: Actor) -> int:
	return ItemsApi.inventory(actor).count(REAGENT)


func _channel(actor: Actor, target: StringName) -> Dictionary:
	return SocketApi.socket_state(actor)["channels"].get(String(target), {})


func _host(actor: Actor, seed_value: int = 900) -> ItemInstance:
	var def := _host_def()
	return ItemsApi.generate(actor, def, seed_value)


# --- Preview ------------------------------------------------------------------


func test_preview_reports_outcomes_costs_and_changes_nothing() -> void:
	var actor := _actor()
	var host := _host(actor)
	_give(actor, 3)
	var before_state := SocketApi.socket_state(actor)
	var before_held := _held(actor)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var before_stream := rng.state

	var preview := SocketApi.preview_enchantment(actor, host.instance_id, REAGENT, rng)
	assert_eq(bool(preview["ok"]), true, "a treatment is possible: %s" % preview["reason"])
	assert_eq((preview["permitted"] as Array).is_empty(), false, "permitted outcomes are reported")
	assert_eq((preview["cost"] as Array).size(), 1, "the cost is reported")
	assert_eq(String((preview["cost"] as Array)[0]), String(REAGENT), "and it names the reagent")
	assert_eq(int(preview["generation"]), 0, "no treatment yet")
	assert_eq(int(preview["cap"]), SocketPolicy.enchant_cap(host.rarity), "the cap is reported")
	assert_eq(bool(preview["rolled"]), false, "a preview resolves no value")
	assert_eq(bool(preview["stream_advanced"]), false, "a preview advances no roll stream")
	assert_eq(int(rng.state), before_stream, "the caller's stream is untouched")
	assert_eq(_held(actor), before_held, "no reagent consumed")
	assert_eq(SocketApi.socket_state(actor), before_state, "no state written")
	for entry in preview["permitted"]:
		assert_eq(
			float(entry["value_max"]) >= float(entry["value_min"]), true, "a range is reported"
		)
		assert_ne(String(entry["option_id"]), "", "each outcome names its option")


func test_preview_is_repeatable_and_reports_its_own_refusals() -> void:
	var actor := _actor()
	var host := _host(actor)
	_give(actor, 1)
	var first := SocketApi.preview_enchantment(actor, host.instance_id, REAGENT)
	var second := SocketApi.preview_enchantment(actor, host.instance_id, REAGENT)
	assert_eq(second["permitted"], first["permitted"], "a preview is a pure read")
	var unknown := SocketApi.preview_enchantment(actor, host.instance_id, &"socket_not_a_reagent")
	assert_eq(bool(unknown["ok"]), false, "an unknown reagent is refused")
	assert_eq(String(unknown["reason"]), "unknown_reagent", "with the gameplay reason")
	assert_eq((unknown["permitted"] as Array).is_empty(), true, "and reports no outcomes")
	var no_target := SocketApi.preview_enchantment(actor, &"nobody", REAGENT)
	assert_eq(String(no_target["reason"]), "unknown_target", "no target is named")


# --- Commit -------------------------------------------------------------------


func test_a_commit_applies_once_and_consumes_exactly_one_reagent() -> void:
	var actor := _actor()
	var host := _host(actor)
	_give(actor, 3)
	var result := SocketApi.commit_enchantment(actor, host.instance_id, REAGENT, &"req_1", 104729)
	assert_eq(bool(result["ok"]), true, "treated: %s" % result["reason"])
	assert_eq(_held(actor), 2, "exactly one reagent consumed")
	var channel := _channel(actor, host.instance_id)
	assert_eq(int(channel["generation"]), 1, "one treatment recorded")
	assert_eq(Dictionary(channel["effect"]).is_empty(), false, "the channel carries the effect")
	assert_eq(
		Dictionary(result["effect"]["effect"]), channel["effect"], "the result reports it too"
	)


func test_an_enchantment_replaces_the_channel_rather_than_stacking() -> void:
	var actor := _actor()
	var host := _host(actor)
	_give(actor, 3)
	var first := SocketApi.commit_enchantment(actor, host.instance_id, REAGENT, &"req_1", 1)
	var second := SocketApi.commit_enchantment(actor, host.instance_id, REAGENT, &"req_2", 2)
	assert_eq(bool(second["ok"]), true, "treated again: %s" % second["reason"])
	var channel := _channel(actor, host.instance_id)
	assert_eq(
		Dictionary(channel["effect"]), second["effect"]["effect"], "the channel holds one effect"
	)
	assert_eq(
		Dictionary(second["effect"]["replaced"]),
		first["effect"]["effect"],
		"the replaced effect is reported"
	)
	assert_eq(int(channel["generation"]), 2, "both treatments counted")
	# Only one effect is live on the worn item, whichever it is.
	assert_eq(_held(actor), 1, "two reagents consumed, one per treatment")


func test_locked_options_survive_every_treatment() -> void:
	var actor := _actor()
	var host := _host(actor)
	_give(actor, 3)
	var foreign := SocketPolicy.foreign_option_ids(host)
	assert_eq(foreign.is_empty(), false, "the host carries foreign options")
	for option_id in foreign:
		assert_eq(SocketApi.is_locked_option(host, option_id), true, "%s is locked" % option_id)
	var signature := host.stacking_signature()
	var fixed := (host.def_ref.fixed_modifiers as Array).duplicate(true)

	var preview := SocketApi.preview_enchantment(actor, host.instance_id, REAGENT)
	for entry in preview["locked"]:
		assert_ne(
			(preview["permitted"] as Array).map(func(e): return e["option_id"]).has(entry),
			true,
			"a locked option is never a permitted outcome"
		)

	var result := SocketApi.commit_enchantment(actor, host.instance_id, REAGENT, &"req_1", 7)
	assert_eq(bool(result["ok"]), true, "treated: %s" % result["reason"])
	assert_eq(host.stacking_signature(), signature, "the rolled channel is untouched")
	assert_eq(host.def_ref.fixed_modifiers, fixed, "the fixed channel is untouched")
	for option_id in foreign:
		assert_eq(
			SocketApi.is_locked_option(host, option_id), true, "%s is still locked" % option_id
		)
	var treated := StringName(result["effect"]["effect"]["option_id"])
	assert_eq(
		SocketApi.is_locked_option(host, treated), false, "the authored effect is not locked to us"
	)


func test_insufficient_cost_consumes_nothing() -> void:
	var actor := _actor()
	var host := _host(actor)
	assert_eq(_held(actor), 0, "no reagent carried")
	var before := SocketApi.socket_state(actor)
	var refused := SocketApi.commit_enchantment(actor, host.instance_id, REAGENT, &"req_1", 3)
	assert_eq(String(refused["reason"]), "missing_cost", "the gameplay reason")
	assert_eq(_held(actor), 0, "nothing consumed")
	assert_eq(SocketApi.socket_state(actor), before, "nothing written")
	var preview := SocketApi.preview_enchantment(actor, host.instance_id, REAGENT)
	assert_eq(String(preview["reason"]), "missing_cost", "a preview refuses the same way")


func test_a_full_inventory_consumes_nothing_beyond_the_intended_cost() -> void:
	var actor := _actor(2)
	var host := _host(actor)
	_give(actor, 1)
	assert_eq(ItemsApi.inventory(actor).is_full(), true, "the bag is full")
	var slots_before := ItemsApi.inventory(actor).used_slots()
	var result := SocketApi.commit_enchantment(actor, host.instance_id, REAGENT, &"req_1", 11)
	assert_eq(bool(result["ok"]), true, "a full bag does not block a treatment")
	assert_eq(_held(actor), 0, "exactly the intended cost")
	assert_eq(
		ItemsApi.inventory(actor).used_slots(),
		slots_before - 1,
		"nothing was added to a bag that had no room"
	)


func test_an_exhausted_cap_consumes_nothing() -> void:
	var actor := _actor()
	var host := _host(actor)
	var cap := SocketPolicy.enchant_cap(host.rarity)
	_give(actor, cap + 3)
	for attempt in cap:
		var done := SocketApi.commit_enchantment(
			actor, host.instance_id, REAGENT, StringName("req_%d" % attempt), attempt
		)
		assert_eq(bool(done["ok"]), true, "treatment %d: %s" % [attempt, done["reason"]])
	var held := _held(actor)
	var channel := _channel(actor, host.instance_id)
	var refused := SocketApi.commit_enchantment(actor, host.instance_id, REAGENT, &"req_over", 99)
	assert_eq(String(refused["reason"]), "cap_exhausted", "the gameplay reason")
	assert_eq(_held(actor), held, "nothing consumed at the cap")
	assert_eq(_channel(actor, host.instance_id), channel, "the channel is unchanged")
	var preview := SocketApi.preview_enchantment(actor, host.instance_id, REAGENT)
	assert_eq(String(preview["reason"]), "cap_exhausted", "a preview reports the same cap")


func test_a_repeated_commit_request_does_not_double_apply() -> void:
	var actor := _actor()
	var host := _host(actor)
	_give(actor, 3)
	var first := SocketApi.commit_enchantment(actor, host.instance_id, REAGENT, &"req_1", 555)
	assert_eq(bool(first["ok"]), true, "treated")
	var held := _held(actor)
	var channel := _channel(actor, host.instance_id)
	var replay := SocketApi.commit_enchantment(actor, host.instance_id, REAGENT, &"req_1", 555)
	assert_eq(replay, first, "the recorded result is replayed verbatim")
	assert_eq(_held(actor), held, "a replay charges nothing")
	assert_eq(_channel(actor, host.instance_id), channel, "a replay applies nothing")


func test_a_replayed_commit_stays_idempotent_across_a_save_load_round_trip() -> void:
	var actor := _actor()
	var host := _host(actor)
	_give(actor, 3)
	var first := SocketApi.commit_enchantment(actor, host.instance_id, REAGENT, &"req_1", 777)
	assert_eq(bool(first["ok"]), true, "treated")

	var restored := Actor.from_dict(actor.to_dict())
	ItemsApi.attach(restored)
	SocketApi.attach(restored)
	var restored_host := _carried(restored, String(host.instance_id))
	assert_ne(restored_host, null, "the host survived the round trip")
	var held := ItemsApi.inventory(restored).count(REAGENT)
	var replay := SocketApi.commit_enchantment(
		restored, restored_host.instance_id, REAGENT, &"req_1", 777
	)
	assert_eq(bool(replay["ok"]), true, "the recorded result is still replayed")
	assert_eq(
		(
			SocketApi
			. socket_state(restored)["channels"][String(restored_host.instance_id)]["generation"]
		),
		1,
		"the treatment was not applied a second time"
	)
	assert_eq(ItemsApi.inventory(restored).count(REAGENT), held, "and nothing was charged again")


# --- Equipped contribution ----------------------------------------------------


func test_a_treated_item_contributes_its_enchantment_while_worn() -> void:
	var actor := _actor()
	var host_def := _host_def()
	var host := ItemsApi.generate(actor, host_def, 901)
	assert_eq(ItemsApi.equip_item(actor, Equipment.ARMOR, host_def), true, "equipped")
	_give(actor, 2)
	var before := actor.stats.modifier_count()
	var result := SocketApi.commit_enchantment(actor, host.instance_id, REAGENT, &"req_1", 31)
	assert_eq(bool(result["ok"]), true, "treated: %s" % result["reason"])
	var channel := _channel(actor, host.instance_id)
	var effect: Array[Dictionary] = [channel["effect"]]
	assert_eq(
		actor.stats.modifier_count() - before,
		(
			ItemEffects.stat_modifiers(effect, &"probe").size()
			+ ItemEffects.resource_modifiers(effect, &"probe").size()
		),
		"the enchantment is applied exactly once"
	)
	assert_eq(bool(ItemsApi.unequip_to_inventory(actor, Equipment.ARMOR)), true, "unequipped")
	assert_eq(actor.stats.modifier_count(), 0, "an unworn item contributes nothing at all")


func _modifier_delta(effects: Array) -> int:
	return (
		ItemEffects.stat_modifiers(effects, &"probe").size()
		+ ItemEffects.resource_modifiers(effects, &"probe").size()
	)


## The instance `actor` carries under `instance_id`. `Inventory.find_instance`
## matches on the definition id despite its name, so identity lookups scan the
## carried instances instead.
func _carried(actor: Actor, instance_id: String) -> ItemInstance:
	for instance in ItemsApi.inventory(actor).instances():
		if String(instance.instance_id) == instance_id:
			return instance
	for slot in Equipment.SLOTS:
		var equipped := ItemsApi.equipment(actor).equipped(slot)
		if equipped != null and String(equipped.instance_id) == instance_id:
			return equipped
	return null
