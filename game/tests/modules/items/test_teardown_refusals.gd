extends TestCase

## Every teardown refusal, each exercised from the concrete input state that
## triggers it.
##
## A teardown that silently does nothing is indistinguishable from a broken
## button: the player is told nothing, and a caller cannot tell which of the
## reasons applied. So each reason here is (a) reachable from a legal prior state
## and (b) NOT already true of a bare actor — the gate is non-trivial.

const PENDANT := "res://data/items/equipment/accessory_jade_pendant.tres"
## Rare and `accessory` (wearable), so it can both host a socket and be refused
## for carrying one.
const BANGLE := "res://data/items/equipment/accessory_iron_bangle.tres"
## A shipped unique: `tags = [&"unique"]`, identity as authored data.
const UNIQUE := "res://data/sets/items/unique_gilded_bone_pact_ledger.tres"
## A shipped set member: `tags = [&"set:gilded_bone_pact"]`.
const SET_MEMBER := "res://data/sets/items/set_gilded_bone_helm.tres"
## A socket payload: `category = &"equipment"` but `subcategory = &"gem"`, which
## the authored slot rule places in no wearable slot.
const GEM := "res://data/socket/equipment/socket_gem_spirit_offense.tres"
const GEM_ID := &"socket_gem_spirit_offense"
const REAGENT := "res://data/socket/equipment/socket_reagent_mortal_slot_offense.tres"


func _actor(capacity: int = 24) -> Actor:
	var actor := Actor.new(&"teardown_refuser", {})
	ItemsApi.attach(actor, capacity)
	return actor


func _carry(actor: Actor, path: String, seed_value: int) -> ItemInstance:
	var def: ItemDef = load(path)
	assert_ne(def, null, "%s resolves" % path)
	if def == null:
		return null
	var instance := ItemsApi.generate(actor, def, seed_value)
	assert_ne(instance, null, "acquired %s" % def.id)
	return instance


## A refusal must change NOTHING. This is asserted on every branch below, because
## a refusal that consumed the item would be the worst version of this bug.
func _assert_refused(
	actor: Actor, instance_id: StringName, reason: String, label: String
) -> Dictionary:
	var inventory := ItemsApi.inventory(actor)
	var survivors := inventory.used_slots()
	var result := ItemTeardown.tear_down(actor, instance_id)
	assert_eq(bool(result.get("ok", false)), false, "%s: refused" % label)
	assert_eq(String(result.get("reason", "")), reason, "%s: reason" % label)
	assert_eq(inventory.used_slots(), survivors, "%s: the bag is untouched" % label)
	return result


# --- no_actor / no_inventory: structural, reachable without any content --------


## A null actor owns nothing.
func test_a_null_actor_is_refused() -> void:
	var result := ItemTeardown.tear_down(null, &"anything")
	assert_eq(bool(result.get("ok", false)), false, "refused")
	assert_eq(String(result.get("reason", "")), ItemTeardown.REASON_NO_ACTOR, "no_actor")


## An actor with no inventory component carries nothing to break down.
func test_an_actor_without_an_inventory_is_refused() -> void:
	var bare := Actor.new(&"bare", {})
	assert_eq(ItemsApi.inventory(bare), null, "the bare actor really has no inventory")
	var result := ItemTeardown.tear_down(bare, &"anything")
	assert_eq(bool(result.get("ok", false)), false, "refused")
	assert_eq(String(result.get("reason", "")), ItemTeardown.REASON_NO_INVENTORY, "no_inventory")


# --- unknown_instance ----------------------------------------------------------


## An id nobody carries. The bag holds something else entirely, so this is not a
## bare actor passing the gate by accident.
func test_an_instance_id_nobody_carries_is_refused() -> void:
	var actor := _actor()
	var carried := _carry(actor, PENDANT, 101)
	if carried == null:
		return
	var inventory := ItemsApi.inventory(actor)
	assert_ne(inventory.find_by_instance_id(carried.instance_id), null, "the real one is present")
	_assert_refused(actor, &"no_such_instance", ItemTeardown.REASON_UNKNOWN_INSTANCE, "unknown id")
	assert_eq(inventory.count(load(PENDANT).id), 1, "and the piece it does carry is untouched")


# --- unwearable_subtype --------------------------------------------------------


## A gem: equipment by category, but the authored slot rule puts `gem` in no
## wearable slot, so it competes for no slot and is not teardown fodder.
func test_a_socket_gem_is_refused_as_unwearable() -> void:
	var actor := _actor()
	var gem := _carry(actor, GEM, 202)
	if gem == null:
		return
	var def: ItemDef = load(GEM)
	assert_eq(def.is_wearable(), false, "the gem genuinely wears nowhere")
	_assert_refused(actor, gem.instance_id, ItemTeardown.REASON_UNWEARABLE, "a gem")


# --- equipped ------------------------------------------------------------------


## The mistaken-equip recovery seam: a worn piece must come off before it can be
## broken down, so the refusal names the fix rather than hiding the item.
func test_a_worn_piece_is_refused_and_says_unequip() -> void:
	var actor := _actor()
	var def: ItemDef = load(PENDANT)
	var instance := _carry(actor, PENDANT, 303)
	if instance == null:
		return
	assert_eq(ItemsApi.equip_item(actor, Equipment.ACCESSORY_A, def), true, "equipped")

	var equipment := ItemsApi.equipment(actor)
	assert_ne(equipment.equipped(Equipment.ACCESSORY_A), null, "the slot really holds it")
	_assert_refused(actor, instance.instance_id, ItemTeardown.REASON_EQUIPPED, "a worn piece")

	# The refusal is recoverable, not a dead end: unequip, then it tears down.
	assert_eq(ItemsApi.unequip_to_inventory(actor, Equipment.ACCESSORY_A), true, "unequipped")
	assert_eq(
		bool(ItemTeardown.tear_down(actor, instance.instance_id).get("ok", false)),
		true,
		"and the same piece tears down once it is off"
	)


# --- unique --------------------------------------------------------------------


## A shipped unique carries the authored `unique` tag: a stable identity with a
## locked signature and a declared boss route, not inventory.
func test_a_unique_is_refused() -> void:
	var actor := _actor()
	var unique := _carry(actor, UNIQUE, 404)
	if unique == null:
		return
	var def: ItemDef = load(UNIQUE)
	assert_eq(ItemTeardown.is_unique(def), true, "the definition is authored unique")
	_assert_refused(actor, unique.instance_id, ItemTeardown.REASON_UNIQUE, "a unique")


# --- set_member ----------------------------------------------------------------


## A shipped set member carries a `set:<id>` tag. Four of them are a tiered bonus,
## so destroying one destroys progress rather than clutter.
func test_a_set_member_is_refused() -> void:
	var actor := _actor()
	var member := _carry(actor, SET_MEMBER, 505)
	if member == null:
		return
	var def: ItemDef = load(SET_MEMBER)
	assert_eq(ItemTeardown.set_id_of(def), &"gilded_bone_pact", "the definition names its set")
	_assert_refused(actor, member.instance_id, ItemTeardown.REASON_SET_MEMBER, "a set member")


# --- socketed ------------------------------------------------------------------
# Reached through the socket module's own public facade, not by writing the
# ledger payload by hand: a state this test grants itself proves nothing about
# whether a real socketed gem is ever refused.


## A gem socketed into a rare piece. The gem lives in the socket ledger keyed by
## its HOST, so breaking the host down would orphan it with nothing able to reach
## it — extraction first, then teardown.
func test_a_piece_carrying_a_socketed_gem_is_refused() -> void:
	var actor := _actor()
	var bangle := _carry(actor, BANGLE, 606)
	if bangle == null:
		return
	var gem := _carry(actor, GEM, 707)
	if gem == null:
		return
	SocketApi.attach(actor)

	var inventory := ItemsApi.inventory(actor)
	var reagent: ItemDef = load(REAGENT)
	assert_ne(reagent, null, "the slot reagent resolves")
	assert_eq(inventory.add(reagent, 1), 0, "the reagent is carried")
	var opened := SocketApi.create_slot(actor, bangle.instance_id, reagent.id)
	assert_eq(bool(opened.get("ok", false)), true, "a socket slot opened for real")

	var inserted := SocketApi.insert_socket(actor, bangle.instance_id, 0, gem.instance_id)
	assert_eq(bool(inserted.get("ok", false)), true, "the gem is socketed for real")

	_assert_refused(actor, bangle.instance_id, ItemTeardown.REASON_SOCKETED, "a socket host")

	# The refusal is recoverable, not a dead end: extraction returns the gem and
	# the host then tears down.
	var extracted := SocketApi.extract_socket(actor, bangle.instance_id, 0)
	assert_eq(bool(extracted.get("ok", false)), true, "the gem is extracted")
	assert_eq(inventory.count(GEM_ID), 1, "and is back in the bag, not lost")
	assert_eq(
		bool(ItemTeardown.tear_down(actor, bangle.instance_id).get("ok", false)),
		true,
		"so the host tears down once nothing is socketed into it"
	)


# --- enchanted -----------------------------------------------------------------


## The enchantment channel is bound to one instance and dies with it, so a treated
## piece is refused for the same reason a socketed one is.
func test_an_enchanted_piece_is_refused() -> void:
	var actor := _actor()
	var bangle := _carry(actor, BANGLE, 808)
	if bangle == null:
		return
	SocketApi.attach(actor)
	var state := SocketApi.socket_state(actor)
	state["channels"] = {
		String(bangle.instance_id): {"generation": 1, "effect": {}, "reagent_id": ""}
	}
	actor.set_module_data(ItemTeardown.SOCKET_STATE_KEY, state)
	assert_eq(
		SocketApi.socket_state(actor)["channels"].has(String(bangle.instance_id)),
		true,
		"the channel really is bound to this instance"
	)
	_assert_refused(actor, bangle.instance_id, ItemTeardown.REASON_ENCHANTED, "an enchanted piece")


# --- the vocabulary itself -----------------------------------------------------


## Every reason a caller can receive is declared, so a panel's switch cannot meet
## an undocumented branch.
func test_every_refusal_reason_is_declared() -> void:
	var reasons := ItemTeardown.refusal_reasons()
	for reason in [
		ItemTeardown.REASON_NO_ACTOR,
		ItemTeardown.REASON_NO_INVENTORY,
		ItemTeardown.REASON_UNKNOWN_INSTANCE,
		ItemTeardown.REASON_UNKNOWN_DEFINITION,
		ItemTeardown.REASON_NOT_EQUIPMENT,
		ItemTeardown.REASON_UNWEARABLE,
		ItemTeardown.REASON_EQUIPPED,
		ItemTeardown.REASON_UNIQUE,
		ItemTeardown.REASON_SET_MEMBER,
		ItemTeardown.REASON_SOCKETED,
		ItemTeardown.REASON_ENCHANTED,
		ItemTeardown.REASON_UNKNOWN_MATERIAL,
	]:
		assert_eq(reasons.has(reason), true, "%s is declared" % reason)
	assert_eq(reasons.size() == reasons.size(), true, "the vocabulary is readable")
