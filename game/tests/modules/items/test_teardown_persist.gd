extends TestCase

## A teardown must survive a save/load round trip.
##
## The point is not merely that the item and its material both reappear — that
## would pass even if teardown had never run. It is that the RESULT of the teardown
## is what persists: the torn-down equipment is still gone after a load (a load
## must not resurrect it), the material is still there at the quantity the
## teardown paid, and the material is still SPENDABLE after the load rather than
## becoming an inert row.

const PENDANT := "res://data/items/equipment/accessory_jade_pendant.tres"
const MORTAL_MATERIAL := &"jade_ore"
const RECIPE := "res://data/recipes/cleansing_jade_pill_recipe.tres"
const RECIPE_OTHER_INPUT := "res://data/items/material/spirit_herb.tres"
const RECIPE_OUTPUT := &"cleansing_jade_pill"


func _actor(capacity: int = 24, id: StringName = &"persisted") -> Actor:
	var actor := Actor.new(id, {})
	ItemsApi.attach(actor, capacity)
	return actor


func test_the_result_of_a_teardown_round_trips_through_a_load() -> void:
	var saved := _actor()
	var def: ItemDef = load(PENDANT)
	var instance := ItemsApi.generate(saved, def, 31337)
	assert_ne(instance, null, "acquired the piece")

	var torn_id := instance.instance_id
	var result := ItemTeardown.tear_down(saved, torn_id)
	assert_eq(bool(result.get("ok", false)), true, "the teardown was accepted")
	var units := int(result.get("units", 0))
	assert_ne(units > 0, true, "it paid something")

	var saved_inv := ItemsApi.inventory(saved)
	assert_eq(saved_inv.count(def.id), 0, "the piece is gone before the save")
	assert_eq(saved_inv.count(MORTAL_MATERIAL), units, "the material is there before the save")

	var payload := ItemsApi.serialize(saved)
	# Serialized EXACTLY once: the material appears as one stack, not two. A
	# teardown that granted the same units by two paths would read the same
	# through `count` and this is the assertion that sees it.
	var stacks: Array = payload["inventory"]["stacks"]
	var material_stacks := 0
	for stack in stacks:
		if StringName(stack.get("def_id", "")) == MORTAL_MATERIAL:
			material_stacks += 1
	assert_eq(material_stacks, 1, "the yield is one stack in the payload, written once")

	# A fresh actor is what a load really gets.
	var loaded := _actor(24, &"loaded")
	ItemsApi.deserialize(loaded, payload)
	var loaded_inv := ItemsApi.inventory(loaded)

	assert_eq(loaded_inv.count(MORTAL_MATERIAL), units, "the yielded material survived the load")
	assert_eq(loaded_inv.count(def.id), 0, "the torn-down piece was not resurrected by the load")

	# And the material is still real after the load: a recipe consumes it.
	var herb: ItemDef = load(RECIPE_OTHER_INPUT)
	assert_eq(loaded_inv.add(herb, 1), 0, "the recipe's other input is carried")
	var recipe: RecipeDef = load(RECIPE)
	var crafting := Crafting.new(recipe.station)
	assert_eq(crafting.craft(recipe, loaded_inv), true, "the loaded material is spendable")
	assert_eq(
		loaded_inv.count(MORTAL_MATERIAL), units - 1, "and spending it really removed a unit"
	)
	assert_eq(loaded_inv.count(RECIPE_OUTPUT), 1, "producing the recipe's output")


## The refusal half of persistence: a refused teardown must leave a bag whose saved
## state still holds the piece, so a refused action cannot quietly cost a player
## gear across a save boundary either.
func test_a_refused_teardown_leaves_the_piece_in_the_save() -> void:
	var saved := _actor()
	var unique: ItemDef = load("res://data/sets/items/unique_gilded_bone_pact_ledger.tres")
	var instance := ItemsApi.generate(saved, unique, 515)
	assert_ne(instance, null, "acquired the unique")

	var result := ItemTeardown.tear_down(saved, instance.instance_id)
	assert_eq(bool(result.get("ok", false)), false, "the unique is refused")
	assert_eq(String(result.get("reason", "")), ItemTeardown.REASON_UNIQUE, "as unique")

	var payload := ItemsApi.serialize(saved)
	var loaded := _actor(24, &"loaded")
	ItemsApi.deserialize(loaded, payload)
	assert_eq(
		ItemsApi.inventory(loaded).count(unique.id), 1, "the unique is still held after the load"
	)


## The teardown adds no serialized state of its own. Both sides of the trade are
## inventory contents, so `serialize` already covers them — and if a future author
## gave teardown its own payload key, this assertion would not notice. It pins the
## shape of the payload instead: exactly the three sections `serialize` writes.
func test_a_teardown_adds_no_payload_section_of_its_own() -> void:
	var saved := _actor()
	var def: ItemDef = load(PENDANT)
	var instance := ItemsApi.generate(saved, def, 99)
	assert_ne(instance, null, "acquired the piece")
	assert_eq(
		bool(ItemTeardown.tear_down(saved, instance.instance_id).get("ok", false)), true, "torn down"
	)
	var payload := ItemsApi.serialize(saved)
	var sections: Array = payload.keys()
	sections.sort()
	var expected: Array = ["equipment", "inventory", "version"]
	expected.sort()
	assert_eq(sections, expected, "the payload is exactly the sections serialize already wrote")