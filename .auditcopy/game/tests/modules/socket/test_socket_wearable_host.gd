extends TestCase

## The socket leg of the pipeline: open -> impute -> seat -> the stat moves.
##
## This is a GATE, and both halves are asserted separately because they fail
## independently:
##
## - **Non-trivial.** A socket-capable host is `rare` or better (a `common` item
##   carries none), and every socket-capable host in the content set is `earth`
##   grade or above except a set piece and a unique. So a hero on the first realm
##   tier owns nothing that can be socketed, and a `cap_reached` refusal is the
##   correct answer rather than a bug.
## - **Satisfiable.** Tier 2 clears the `earth` grade gate, and a tier-2 hero
##   wearing the starter `accessory_iron_bangle` carries a real socket slot. That
##   is a legal prior state a player reaches by cultivating, not a test fixture.
##
## Neither half is proved by the other, so both are asserted here. Nothing raises
## a tier without saying so: the tier-2 tests name the reason they need it.

const BANGLE := &"accessory_iron_bangle"
const HELM := &"armor_iron_helm"
const REAGENT := &"socket_reagent_mortal_slot_offense"
const IMPUTATION := &"socket_reagent_mortal_imputation"
const RUNE := &"socket_rune_mortal_offense"


## A hero carrying the authored starter kit, at the given realm tier. Tier 1 is
## the first tier a hero reaches once a cultivation path is enrolled; tier 2 is
## one step further. A hero on no path is tier 0, which no authored grade admits,
## so the path is set here rather than left implicit.
func _starter(tier: int = 1) -> Actor:
	var actor := Actor.new(&"smith", {Stat.PHYSIQUE: 14.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	actor.add_resource(ResourcePool.new(&"qi", 60.0))
	actor.add_resource(ResourcePool.new(&"stamina", 50.0))
	ItemsApi.attach(actor, 24)
	SocketApi.attach(actor)
	_advance_to_tier(actor, tier)
	for def_id in [HELM, BANGLE]:
		var def := Crafting.resolve(def_id)
		if def != null:
			ItemsApi.inventory(actor).add(def, 1)
	return actor


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


func _tier_of(actor: Actor) -> int:
	return RealmDefaults.ladder().tier_of(actor.realm())


## Both offence ids, because a socket may land on either and the assertion must
## not quietly read only one.
func _offense(actor: Actor) -> float:
	return actor.stats.derived(Stat.ATTACK_PHYSICAL) + actor.stats.derived(Stat.ATTACK_SPIRITUAL)


## GATE, non-trivial: on the first tier the hero CAN wear a host, but a `common`
## host can never carry a socket, so the forge skips it and names the one item in
## the bag that can actually host one. The forge therefore never points at an
## inert item — it points at a host the hero's tier has not reached yet.
func test_a_tier_one_hero_can_wear_a_host_and_the_forge_names_a_real_socket_host() -> void:
	var actor := _starter(1)
	assert_eq(_tier_of(actor), 1, "the starting hero is on the first realm tier")

	var helm := Crafting.resolve(HELM)
	assert_ne(helm, null, "the starter helm resolves")
	assert_eq(
		helm.required_tier() <= _tier_of(actor),
		true,
		"and the hero's tier meets the host's grade gate, so it is legal to wear"
	)
	assert_eq(ItemsApi.equip_item(actor, Equipment.ARMOR, helm), true, "the hero wears the host")

	var view := SocketApi.panel_state(actor)
	assert_ne(view.is_empty(), true, "the forge has something to show")
	var parent: Dictionary = view.get("parent", {})
	var host := Crafting.resolve(StringName(String(parent.get("def_id", ""))))
	assert_ne(host, null, "the forge names a host that resolves")
	assert_eq(
		SocketPolicy.slot_cap(host.rarity) > 0,
		true,
		(
			(
				"the forge names a host that can actually host sockets (rarity '%s'), never an "
				+ "item the transaction would refuse"
			)
			% host.rarity
		)
	)
	assert_eq(
		host.required_tier() <= _tier_of(actor),
		false,
		"which is a higher-tier host, so at tier 1 the forge points at something not yet wearable"
	)


## GATE, non-trivial, other side: a `common` host carries no socket at all, so a
## first-tier hero is refused with a NAMED reason rather than a silent no-op.
func test_a_first_tier_hero_is_refused_a_socket_because_common_hosts_carry_none() -> void:
	var actor := _starter(1)
	var helm := Crafting.resolve(HELM)
	assert_eq(ItemsApi.equip_item(actor, Equipment.ARMOR, helm), true, "the host is worn")
	var host: ItemInstance = ItemsApi.equipment(actor).equipped(Equipment.ARMOR)
	ItemsApi.inventory(actor).add(SocketApi.resolve_content(REAGENT), 2)

	assert_eq(
		SocketPolicy.slot_cap(host.def_ref.rarity),
		0,
		"a common host carries no socket, which is why the tier-1 answer is a refusal"
	)
	var refused := SocketApi.create_slot(actor, host.instance_id, REAGENT)
	assert_eq(bool(refused.get("ok", true)), false, "so opening one is refused")
	assert_ne(
		String(refused.get("reason", "")),
		"",
		"and the refusal names the condition that failed to converge"
	)


## GATE, satisfiable: tier 2 clears the `earth` grade gate, so the starter bangle
## becomes both wearable AND socket-capable, and the whole transaction closes.
func test_at_tier_two_the_starter_bangle_carries_a_socket_and_the_leg_closes() -> void:
	var actor := _starter(2)
	var bangle := Crafting.resolve(BANGLE)
	assert_eq(
		bangle.required_tier() <= _tier_of(actor),
		true,
		"tier 2 is exactly the tier the bangle's grade asks for"
	)
	assert_eq(
		ItemsApi.equip_item(actor, Equipment.ACCESSORY_A, bangle),
		true,
		"so the hero can wear the one starter item that carries a socket"
	)
	var host: ItemInstance = ItemsApi.equipment(actor).equipped(Equipment.ACCESSORY_A)
	assert_ne(host, null, "the worn host is an instance we can address")
	assert_eq(
		SocketPolicy.slot_cap(host.def_ref.rarity),
		1,
		"a rare host carries one socket, which is what makes the leg reachable"
	)


## The whole leg, end to end, on that satisfiable state: spend the reagents, seat
## the socket, and read the authored contribution off the stat it should move.
func test_a_socket_seated_on_a_worn_host_reaches_the_stat() -> void:
	var actor := _starter(2)
	var bangle := Crafting.resolve(BANGLE)
	ItemsApi.equip_item(actor, Equipment.ACCESSORY_A, bangle)
	var host: ItemInstance = ItemsApi.equipment(actor).equipped(Equipment.ACCESSORY_A)

	for id in [REAGENT, IMPUTATION]:
		var def := SocketApi.resolve_content(id)
		assert_ne(def, null, "%s resolves through the socket facade" % id)
		if def == null:
			return
		ItemsApi.inventory(actor).add(def, 2)
	var socket := ItemsApi.generate(actor, SocketApi.resolve_content(RUNE), 5150)
	assert_ne(socket, null, "the socket item is acquired through the items facade")

	var before := _offense(actor)
	var reagents_before := ItemsApi.inventory(actor).count(REAGENT)

	var opened := SocketApi.create_slot(actor, host.instance_id, REAGENT)
	assert_eq(
		bool(opened.get("ok", false)),
		true,
		"a slot opens on the worn host: %s" % opened.get("reason", "")
	)
	assert_eq(
		ItemsApi.inventory(actor).count(REAGENT),
		reagents_before - 1,
		"and it costs exactly one reagent"
	)

	var imputed := SocketApi.impute_slot(actor, host.instance_id, 0, IMPUTATION)
	assert_eq(
		bool(imputed.get("ok", false)), true, "the slot is imputed: %s" % imputed.get("reason", "")
	)
	var seated := SocketApi.insert_socket(actor, host.instance_id, 0, socket.instance_id)
	assert_eq(
		bool(seated.get("ok", false)), true, "the socket is seated: %s" % seated.get("reason", "")
	)

	assert_eq(
		_offense(actor) > before,
		true,
		"the seated socket reaches the hero's stat: %s -> %s" % [before, _offense(actor)]
	)


## The contribution is the socket's alone: taking the host off takes it with it,
## so the number above is the socket and not a side effect of the transaction.
func test_unequipping_the_host_takes_the_socket_contribution_with_it() -> void:
	var actor := _starter(2)
	var bangle := Crafting.resolve(BANGLE)
	ItemsApi.equip_item(actor, Equipment.ACCESSORY_A, bangle)
	for id in [REAGENT, IMPUTATION]:
		ItemsApi.inventory(actor).add(SocketApi.resolve_content(id), 2)
	var socket := ItemsApi.generate(actor, SocketApi.resolve_content(RUNE), 6161)
	var host: ItemInstance = ItemsApi.equipment(actor).equipped(Equipment.ACCESSORY_A)

	SocketApi.create_slot(actor, host.instance_id, REAGENT)
	SocketApi.impute_slot(actor, host.instance_id, 0, IMPUTATION)
	SocketApi.insert_socket(actor, host.instance_id, 0, socket.instance_id)
	var seated := _offense(actor)

	assert_eq(
		ItemsApi.unequip_to_inventory(actor, Equipment.ACCESSORY_A), true, "the host comes off"
	)
	assert_eq(
		ItemsApi.equipment(actor).equipped(Equipment.ACCESSORY_A), null, "and the slot is empty"
	)
	assert_eq(
		_offense(actor) < seated,
		true,
		"and the socket's contribution leaves with it: %s -> %s" % [seated, _offense(actor)]
	)
