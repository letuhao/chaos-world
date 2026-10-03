extends TestCase

## Item state must survive a save/load round trip *whole*.
##
## `serialize` used to write stacks and instances but not the inventory's
## capacity, so `attach` rebuilt a default-sized inventory and every stack past
## that size was silently dropped on load: no error, no failed assertion, a
## session's work deleted. A test that only asserts "it loaded" cannot see that,
## so these assert the count and the specific ids.

## Enough distinct stackable defs to overflow a default inventory with room to
## spare, so the overflow is unambiguous rather than borderline.
const OVERFLOW := 30
## The capacity a fresh actor is built at, and therefore the number of stacks a
## load must not silently lose.
const WIDE := 64


func setup() -> void:
	pass


## A bag holding more stacks than a default inventory can hold must come back
## whole. This is the regression guard for the truncation: it fails loudly on the
## count *and* names the ids that went missing.
func test_a_bag_larger_than_the_default_capacity_round_trips_whole() -> void:
	var defs := _stackable_defs(OVERFLOW)
	assert_eq(defs.size(), OVERFLOW, "the content set offers enough distinct stackables")

	var saved := Actor.new(&"saved", {})
	ItemsApi.attach(saved, WIDE)
	var saved_inv := ItemsApi.inventory(saved)
	for def in defs:
		saved_inv.add(def, 1)
	assert_eq(saved_inv.used_slots(), OVERFLOW, "the bag really does overflow a default inventory")
	assert_eq(
		saved_inv.used_slots() > ItemsApi.DEFAULT_CAPACITY,
		true,
		"and it overflows by construction, so this test is not vacuous"
	)

	var payload := ItemsApi.serialize(saved)
	assert_eq(
		int(payload["inventory"].get("capacity", 0)),
		WIDE,
		"the payload records the capacity the bag was actually using"
	)

	# A fresh actor is what a load really gets: attached at the default, with no
	# knowledge of how big the bag had grown.
	var loaded := Actor.new(&"loaded", {})
	ItemsApi.attach(loaded)
	ItemsApi.deserialize(loaded, payload)

	var loaded_inv := ItemsApi.inventory(loaded)
	assert_eq(
		loaded_inv.used_slots(),
		OVERFLOW,
		"a load rebuilt the bag big enough to hold everything it had"
	)
	assert_eq(
		loaded_inv.used_slots() > ItemsApi.DEFAULT_CAPACITY,
		true,
		"the restored bag is still wider than a default one"
	)

	var ids := _stack_ids(loaded_inv)
	for def in defs:
		assert_eq(ids.has(String(def.id)), true, "stack '%s' survived the load" % def.id)
	assert_eq(
		loaded_inv.count(defs[OVERFLOW - 1].id),
		1,
		"and the last stack in is present with its quantity"
	)


## An older save predates the capacity key. It must load at the default without
## crashing, and must not be treated as a corrupt payload.
func test_an_older_save_without_a_capacity_key_falls_back_to_the_default() -> void:
	var saved := Actor.new(&"saved", {})
	ItemsApi.attach(saved, WIDE)
	var saved_inv := ItemsApi.inventory(saved)
	for def in _stackable_defs(4):
		saved_inv.add(def, 1)
	var payload := ItemsApi.serialize(saved)

	var legacy: Dictionary = payload.duplicate(true)
	legacy["inventory"].erase("capacity")
	legacy["version"] = ItemsApi.SCHEMA_VERSION - 1

	var loaded := Actor.new(&"loaded", {})
	ItemsApi.attach(loaded)
	ItemsApi.deserialize(loaded, legacy)

	assert_eq(
		ItemsApi.inventory(loaded).capacity,
		ItemsApi.DEFAULT_CAPACITY,
		"a save with no recorded capacity builds a default-sized bag"
	)
	assert_eq(ItemsApi.inventory(loaded).used_slots(), 4, "and its contents are still restored")


## The item-state payload is versioned and migrated rather than reinterpreted,
## the way the actor's own payload is. Version 2 is the one that omitted
## `capacity`, so migrating it forward must supply the default rather than zero —
## asserted through `deserialize`, which is the only path a load actually takes.
func test_the_payload_is_versioned_and_migrates_forward() -> void:
	var saved := Actor.new(&"saved", {})
	ItemsApi.attach(saved, WIDE)
	var saved_inv := ItemsApi.inventory(saved)
	var defs := _stackable_defs(3)
	for def in defs:
		saved_inv.add(def, 1)
	var current := ItemsApi.serialize(saved)

	assert_eq(
		int(current["version"]),
		ItemsApi.SCHEMA_VERSION,
		"the payload carries the module's own schema version"
	)
	assert_eq(int(current["version"]), 3, "which is the version that records capacity")

	var previous: Dictionary = current.duplicate(true)
	previous["version"] = 2
	previous["inventory"].erase("capacity")

	var loaded := Actor.new(&"loaded", {})
	ItemsApi.attach(loaded)
	ItemsApi.deserialize(loaded, previous)

	assert_eq(
		ItemsApi.inventory(loaded).capacity,
		ItemsApi.DEFAULT_CAPACITY,
		"a version 2 payload migrates forward to the default capacity it omitted"
	)
	var ids := _stack_ids(ItemsApi.inventory(loaded))
	for def in defs:
		assert_eq(ids.has(String(def.id)), true, "'%s' still restored from a v2 save" % def.id)


## A payload from a newer build must not be silently downgraded into a shape
## this one misreads. It refuses, and the bag is left as it was.
func test_a_payload_from_a_newer_build_is_refused_rather_than_misread() -> void:
	var future := {"version": ItemsApi.SCHEMA_VERSION + 1, "inventory": {}, "equipment": {}}
	var loaded := Actor.new(&"loaded", {})
	ItemsApi.attach(loaded)
	ItemsApi.deserialize(loaded, future)
	assert_eq(
		ItemsApi.inventory(loaded).used_slots(),
		0,
		"an unknown future payload restores nothing rather than guessing"
	)


## A stack's realized rolls must survive a load. `ItemStack.to_dict` records
## `rolled`, `rarity` and `realm`, so the save already carries them; restoring a
## stack through `Inventory.add` minted a fresh realization and discarded them,
## which quietly re-rolled every stack the player had already rolled.
##
## Asserting the whole signature, not just "it loaded", is the point: a re-roll
## produces a *different* signature, so this cannot pass by accident.
func test_a_stack_comes_back_with_the_rolls_it_was_saved_with() -> void:
	var rollable := _roll_bearing_def()
	assert_ne(rollable, null, "the content set has a stackable def that carries rolls")

	var saved := Actor.new(&"saved", {})
	ItemsApi.attach(saved)
	ItemsApi.inventory(saved).add(rollable, 1)
	var before := _signature_of(saved, rollable.id)
	assert_ne(before, "", "the stack really does carry a realization before the save")

	var payload := ItemsApi.serialize(saved)
	var loaded := Actor.new(&"loaded", {})
	ItemsApi.attach(loaded)
	ItemsApi.deserialize(loaded, payload)

	assert_eq(
		_signature_of(loaded, rollable.id),
		before,
		"the loaded stack carries the same realized rolls, not a fresh roll"
	)
	assert_eq(
		_roll_values(loaded, rollable.id),
		_roll_values(saved, rollable.id),
		"and the same realized values, value for value"
	)


## Repeated loads must be idempotent: loading three times is the same stack, not
## three successive re-rolls that happen to agree.
func test_loading_the_same_save_repeatedly_does_not_wander_the_realization() -> void:
	var rollable := _roll_bearing_def()
	assert_ne(rollable, null, "the content set has a stackable def that carries rolls")

	var saved := Actor.new(&"saved", {})
	ItemsApi.attach(saved)
	ItemsApi.inventory(saved).add(rollable, 1)
	var payload := ItemsApi.serialize(saved)
	var expected := _roll_values(saved, rollable.id)

	var loaded := Actor.new(&"loaded", {})
	ItemsApi.attach(loaded)
	for round in 3:
		ItemsApi.deserialize(loaded, payload)
		assert_eq(
			_roll_values(loaded, rollable.id),
			expected,
			"load round %d restored the saved realization exactly" % (round + 1)
		)


# --- helpers -------------------------------------------------------------


## Distinct stackable def ids from the roots the module itself resolves through,
## so this never depends on a kept list of content.
func _stackable_defs(count: int) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	var seen := {}
	for def_id in _def_ids():
		if seen.has(String(def_id)):
			continue
		seen[String(def_id)] = true
		var def := Crafting.resolve(def_id)
		if def == null or not def.stackable:
			continue
		out.append(def)
		if out.size() >= count:
			break
	return out


func _def_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for root in Crafting.ITEM_ROOTS:
		_scan(root, out)
	return out


func _scan(root: String, out: Array[StringName]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				_scan(path, out)
			elif entry.ends_with(".tres"):
				out.append(StringName(entry.get_basename()))
		entry = dir.get_next()
	dir.list_dir_end()


func _stack_ids(inv: Inventory) -> Array[String]:
	var out: Array[String] = []
	for stack in inv.stacks():
		out.append(String(stack.def_id))
	return out


## A stackable authored def that actually carries realized rolls, so the
## round-trip claim is about real rolls and not about an inert definition.
func _roll_bearing_def() -> ItemDef:
	for def in _stackable_defs(60):
		var probe := Actor.new(&"probe", {})
		ItemsApi.attach(probe)
		ItemsApi.inventory(probe).add(def, 1)
		if not _signature_of(probe, def.id).is_empty():
			return def
	return null


## The saved form of one stack's realization.
func _signature_of(actor: Actor, def_id: StringName) -> String:
	for stack in ItemsApi.inventory(actor).stacks():
		if stack.def_id == def_id:
			return stack.signature()
	return ""


## The realized value of every effect on one stack, so a re-roll cannot pass by
## producing the same numbers in a different order.
func _roll_values(actor: Actor, def_id: StringName) -> Array:
	var out: Array = []
	for stack in ItemsApi.inventory(actor).stacks():
		if stack.def_id != def_id:
			continue
		for effect in stack.rolled:
			out.append([String(effect.get("option_id", "")), float(effect.get("value", 0.0))])
	return out
