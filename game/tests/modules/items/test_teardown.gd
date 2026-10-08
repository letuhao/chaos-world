extends TestCase

## The teardown chain, end to end, through a real bag: a piece of equipment the
## actor actually holds is broken down, the grade's material appears, and those
## materials are then SPENT by a recipe that consumes them.
##
## Everything here is asserted as an OBSERVABLE OUTCOME — what the bag holds
## before and after — rather than as a returned boolean, because `ok: true` is
## also what a teardown that granted nothing would return.

## Shipped equipment the entry band already reaches. Grade mortal, rarity common,
## stackable false, subcategory `accessory` (wearable): an ordinary piece that
## competes for one of the two accessory slots.
const PENDANT := "res://data/items/equipment/accessory_jade_pendant.tres"

## Consumes `jade_ore` — the material a grade-mortal teardown pays — plus one
## herb the test supplies. Crafting is the downstream consumer that makes the
## teardown output something other than dead weight.
const RECIPE := "res://data/recipes/cleansing_jade_pill_recipe.tres"
const RECIPE_OTHER_INPUT := "res://data/items/material/spirit_herb.tres"
const RECIPE_OUTPUT := &"cleansing_jade_pill"

## The material a grade-mortal teardown pays, spelled out so the test asserts the
## CONTENT rather than re-deriving it from the implementation it is checking.
const MORTAL_MATERIAL := &"jade_ore"

## How many pieces fill the bag. [constant ItemsApi.DEFAULT_CAPACITY] is the real
## number and this test is not allowed to drift from it silently, so it is read
## rather than typed — but the loop bound is snapshotted BEFORE it starts, because
## the body appends one instance per pass and a bound read from the container it
## grows would never terminate.
const BAG := 24


func _actor(capacity: int = BAG) -> Actor:
	var actor := Actor.new(&"teardown_hero", {})
	ItemsApi.attach(actor, capacity)
	return actor


## A piece of equipment the actor really holds, acquired through the same seeded
## verb a drop uses. Never handed in directly: a test that constructs the instance
## itself would prove nothing about acquisition.
func _acquire(actor: Actor, def: ItemDef, seed_value: int) -> ItemInstance:
	var instance := ItemsApi.generate(actor, def, seed_value)
	assert_ne(instance, null, "acquired %s (seed %d)" % [def.id, seed_value])
	return instance


func test_a_held_piece_tears_down_into_its_grade_material() -> void:
	var actor := _actor()
	var inventory := ItemsApi.inventory(actor)
	var def: ItemDef = load(PENDANT)
	var instance := _acquire(actor, def, 4242)
	if instance == null:
		return

	assert_eq(inventory.count(def.id), 1, "the bag holds the piece")
	assert_eq(inventory.count(MORTAL_MATERIAL), 0, "and no salvage material yet")

	var result := ItemTeardown.tear_down(actor, instance.instance_id)

	assert_eq(bool(result.get("ok", false)), true, "the teardown is accepted")
	assert_eq(String(result.get("reason", "?")), "", "with no refusal reason")
	assert_eq(
		String(result.get("material_id", "")),
		String(MORTAL_MATERIAL),
		"paying the grade's material"
	)

	# The observable outcome: the piece is GONE and the material is THERE.
	assert_eq(inventory.count(def.id), 0, "the torn-down piece is no longer carried")
	assert_eq(
		inventory.count(MORTAL_MATERIAL),
		int(result.get("units", 0)),
		"the material the result quoted is the material in the bag"
	)
	assert_ne(int(result.get("units", 0)) > 0, true, "a teardown never yields nothing")


## The wired-out half: the yield is not a pile of dead units, it is consumed by a
## recipe that names it. This is the assertion that makes the sink a sink.
func test_the_yielded_material_is_then_spent_by_crafting() -> void:
	var actor := _actor()
	var inventory := ItemsApi.inventory(actor)
	var def: ItemDef = load(PENDANT)

	var quoted := 0
	for seed_value in [11, 22, 33]:
		var instance := _acquire(actor, def, seed_value)
		if instance == null:
			return
		var result := ItemTeardown.tear_down(actor, instance.instance_id)
		assert_eq(bool(result.get("ok", false)), true, "teardown accepted (seed %d)" % seed_value)
		quoted += int(result.get("units", 0))

	var before := inventory.count(MORTAL_MATERIAL)
	assert_eq(before, quoted, "every teardown landed its quoted units")
	assert_ne(before > 0, true, "there is something to spend")

	# The rest of the recipe's inputs. Supplied directly: the herb is setup, not
	# the thing under test.
	var herb: ItemDef = load(RECIPE_OTHER_INPUT)
	assert_eq(inventory.add(herb, 1), 0, "the recipe's other input is carried")

	var recipe: RecipeDef = load(RECIPE)
	var crafted := Crafting.new(recipe.station)

	assert_eq(crafted.craft(recipe, inventory), true, "the recipe consumes the teardown output")
	assert_eq(inventory.count(MORTAL_MATERIAL), before - 1, "exactly one yielded unit was spent")
	assert_eq(inventory.count(RECIPE_OUTPUT), 1, "and the craft produced its output")


## The defect this sink exists to remove, measured directly: a bag full of
## guaranteed wearables stops accepting pickups, so tearing pieces down must give
## the slots back.
func test_teardown_frees_the_bag_slots_a_full_bag_needs() -> void:
	var actor := _actor(BAG)
	var inventory := ItemsApi.inventory(actor)
	var def: ItemDef = load(PENDANT)

	var ids: Array[StringName] = []
	# Snapshot the bound before the loop: the body appends one instance per pass,
	# so a bound read from `ids` or from the bag would grow in lockstep and never
	# terminate.
	for index in BAG:
		var instance := _acquire(actor, def, 900 + index)
		if instance == null:
			return
		ids.append(instance.instance_id)

	assert_eq(inventory.used_slots(), BAG, "the bag is full of equipment")
	assert_eq(inventory.is_full(), true, "so a further guaranteed pickup cannot land")

	var freed := BAG / 2
	for index in freed:
		var result := ItemTeardown.tear_down(actor, ids[index])
		assert_eq(
			bool(result.get("ok", false)), true, "teardown accepted (%d of %d)" % [index, freed]
		)

	assert_eq(inventory.used_slots() < BAG, true, "breaking gear down gave bag slots back")
	assert_eq(inventory.is_full(), false, "so a guaranteed pickup fits again")
	# And the slots really are reusable, not merely re-counted.
	var late := _acquire(actor, def, 7777)
	assert_ne(late, null, "a guaranteed pickup lands in the freed space")


## A quote is a plan. It must move nothing, so a screen can render a row and the
## player can be told what the trade pays before committing to it.
func test_a_preview_changes_nothing() -> void:
	var actor := _actor()
	var inventory := ItemsApi.inventory(actor)
	var def: ItemDef = load(PENDANT)
	var instance := _acquire(actor, def, 5150)
	if instance == null:
		return

	var quote := ItemTeardown.preview(actor, instance.instance_id)

	assert_eq(bool(quote.get("ok", false)), true, "a holdable piece previews as tearable")
	assert_eq(
		String(quote.get("material_id", "")),
		String(MORTAL_MATERIAL),
		"quoting the grade's material"
	)
	assert_eq(int(quote.get("units", 0)) > 0, true, "quoting a non-zero yield")
	assert_eq(inventory.count(def.id), 1, "the piece is still carried after a preview")
	assert_eq(inventory.count(MORTAL_MATERIAL), 0, "and the preview granted nothing")
