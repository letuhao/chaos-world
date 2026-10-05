extends TestCase

## A socket payload is not something a body wears, and the shipped ones prove it.
##
## Every socket item in the content tree is `equipment`-category with its options
## on the EQUIPPED channel, because that is the channel a socket slot resolves
## through. That made wearing one directly a bypass: no slot opened, no reagent
## spent, no host, no imputation cap — just the gem's full fixed signature on the
## wearer. The authored slot rule closes it by ruling the payload's subtype to no
## wearable slot at all, and `Equipment.equip` refuses it on its own named branch.
##
## Both halves are asserted separately. Non-trivial: the payload's own options are
## worth real numbers, so the refusal is not cosmetic. Satisfiable: every slot the
## rule does offer is refused with the same reason, so there is no slot that lets
## the payload through by accident.


## Every shipped socket payload, resolved through the module's own namespace.
func _payloads() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for def in SocketContent.tagged(SocketPolicy.SOCKET_ITEM_TAG):
		out.append(def)
	return out


func _hero() -> Actor:
	var actor := Actor.new(&"socket_bearer", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 10.0})
	ItemsApi.attach(actor, 32)
	return actor


## The hole, closed: no shipped socket payload may be worn into any slot, and each
## refusal names the unwearable branch rather than a slot mismatch the rule never
## offered.
func test_no_shipped_socket_payload_can_be_worn_into_any_slot() -> void:
	var payloads := _payloads()
	assert_ne(payloads.is_empty(), true, "the socket namespace ships payloads")
	for def in payloads:
		assert_eq(
			def.is_equipment(),
			true,
			"%s is equipment-category, which is what put wearing it within reach" % def.id
		)
		assert_eq(
			SocketPolicy.is_socket_item(def), true, "%s is tagged as a socket payload" % def.id
		)
		assert_eq(
			def.is_wearable(),
			false,
			(
				"%s: the authored slot rule rules subtype '%s' to no wearable slot"
				% [def.id, def.subcategory]
			)
		)
		var actor := _hero()
		ItemsApi.inventory(actor).add(def, 1)
		for slot in Equipment.SLOTS:
			assert_eq(
				ItemsApi.equip_item(actor, slot, def),
				false,
				"%s is refused in slot '%s'" % [def.id, slot]
			)
			assert_eq(
				ItemsApi.equipment(actor).last_refusal(),
				Equipment.REASON_UNWEARABLE,
				"%s in '%s' names the unwearable branch" % [def.id, slot]
			)


## The refusal is not cosmetic. Each payload's fixed options are worth real
## numbers on the equipped channel, so if the rule ever loosens again the payoff
## is a live stat and not an inert item. Measured by asking what the payload would
## contribute, and then confirming a refused equip moves nothing.
func test_a_refused_payload_contributes_nothing_although_its_own_options_are_worth_stat() -> void:
	for def in _payloads():
		var worth := 0.0
		for effect in def.effects(null):
			var value := float(effect.get("value", 0.0))
			if absf(value) > 0.0:
				worth += absf(value)
		assert_ne(
			worth,
			0.0,
			(
				(
					"%s: its options are worth real numbers on the '%s' channel, so wearing it would "
					+ "have been a real bypass rather than a harmless one"
				)
				% [def.id, def.activation()]
			)
		)
		var actor := _hero()
		ItemsApi.inventory(actor).add(def, 1)
		var before := (
			actor.stats.derived(Stat.ATTACK_PHYSICAL) + actor.stats.derived(Stat.DEFENSE_PHYSICAL)
		)
		for slot in Equipment.SLOTS:
			ItemsApi.equip_item(actor, slot, def)
		assert_almost_eq(
			actor.stats.derived(Stat.ATTACK_PHYSICAL) + actor.stats.derived(Stat.DEFENSE_PHYSICAL),
			before,
			"%s: no slot applied anything" % def.id
		)
		assert_eq(
			actor.stats.modifier_count(),
			0,
			"%s: and no modifier reached the stat stack from any slot" % def.id
		)


## The gate has an exit, not just walls: the payload is wearable exactly where the
## socket program puts it, and a seated payload applies through the host while the
## host is worn. Without this the refusal could be a blanket ban that quietly
## deleted the feature.
func test_a_payload_still_applies_when_seated_in_a_socket_on_a_worn_host() -> void:
	var host_def := Crafting.resolve(&"accessory_iron_bangle")
	assert_ne(host_def, null, "the starter bangle resolves")
	var actor := Actor.new(&"socket_bearer", {Stat.PHYSIQUE: 14.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.add_resource(ResourcePool.new(&"qi", 60.0))
	actor.add_resource(ResourcePool.new(&"stamina", 50.0))
	ItemsApi.attach(actor, 32)
	SocketApi.attach(actor)
	_advance_to_tier(actor, 2)
	ItemsApi.inventory(actor).add(host_def, 1)
	ItemsApi.inventory(actor).add(
		SocketApi.resolve_content(&"socket_reagent_mortal_slot_offense"), 2
	)
	ItemsApi.inventory(actor).add(SocketApi.resolve_content(&"socket_reagent_mortal_imputation"), 2)
	# The bangle rather than the helm, deliberately: a `rare` host carries a socket
	# slot and a `common` one carries none, so the helm would refuse with
	# `cap_reached` and this would prove nothing.
	assert_eq(ItemsApi.equip_item(actor, Equipment.ACCESSORY_A, host_def), true, "the host is worn")
	var host: ItemInstance = ItemsApi.equipment(actor).equipped(Equipment.ACCESSORY_A)
	assert_ne(host, null, "and holds an instance")

	var payload := SocketApi.resolve_content(&"socket_rune_mortal_offense")
	var gem := ItemsApi.generate(actor, payload, 3311)
	assert_ne(gem, null, "the payload is acquired through the items facade")
	var before := actor.stats.derived(Stat.ATTACK_PHYSICAL)

	var opened := SocketApi.create_slot(
		actor, host.instance_id, &"socket_reagent_mortal_slot_offense"
	)
	assert_eq(bool(opened.get("ok", false)), true, "a slot opens: %s" % opened.get("reason", ""))
	var imputed := SocketApi.impute_slot(
		actor, host.instance_id, 0, &"socket_reagent_mortal_imputation"
	)
	assert_eq(
		bool(imputed.get("ok", false)), true, "and is imputed: %s" % imputed.get("reason", "")
	)
	var seated := SocketApi.insert_socket(actor, host.instance_id, 0, gem.instance_id)
	assert_eq(bool(seated.get("ok", false)), true, "and seats: %s" % seated.get("reason", ""))

	assert_eq(
		actor.stats.derived(Stat.ATTACK_PHYSICAL) > before,
		true,
		(
			"the payload reaches the stat through the socket it was seated in: %s -> %s"
			% [before, actor.stats.derived(Stat.ATTACK_PHYSICAL)]
		)
	)


## Selected by TIER and never by position: the ladder's order is authored data and
## a retier must not silently turn this into a no-op.
func _advance_to_tier(actor: Actor, tier: int) -> void:
	var target := &""
	for realm in RealmDefaults.ladder().realms():
		if int((realm as RealmDef).tier) >= tier:
			target = (realm as RealmDef).id
			break
	if target == &"":
		return
	actor.set_path(PathState.new(PathState.BODY, target))
