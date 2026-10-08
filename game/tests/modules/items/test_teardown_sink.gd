extends TestCase

## The sink, published and wired (BL-0921).
##
## The bag is 24 slots, eight authored subtypes compete for five wearable slots, and the
## drop tables GUARANTEE wearables - so a player accumulates equipment with nowhere to put
## it. [ItemTeardown] has owned the whole rule since it shipped (nine named refusals, worn
## and unique and set-member and socketed and enchanted pieces protected) and had NO
## production caller: `items/api.gd` published no teardown verb at all, so the rule was
## unreachable from every screen and every test that was not the rule's own.
##
## ## What this suite asserts, and what it deliberately does not
##
## The rule's nine refusals are the rule module's own suite. What was missing is the two
## halves this file covers: the FACADE verb (the rule cannot be called from outside the
## module without one) and the WIRING (a verb nobody calls is the shape the ledger keeps
## filing). The wiring is read off the SOURCE, the way `test_dialogue_boot_wiring.gd` reads
## the composition root - a peer deleting the dispatch line fails here instead of shipping
## a button that does nothing.

const BAR_GD := "res://src/ui/panels/action_bar.gd"
const BAR_TSCN := "res://src/ui/panels/action_bar.tscn"
const SCREEN := "res://src/ui/screens/item_workbench.gd"

## A mortal wearable the drop tables actually pay - named in the boot probe's own claim
## list, so this fixture is a drop a player has held rather than an item invented here.
const WEARABLE := &"D9_mortal_windstride_greave"


func _hero(actor_id: StringName = &"t_teardown_sink") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	ItemsApi.attach(actor)
	return actor


# --- The facade publishes the rule --------------------------------------------


## A verb per reader, and the refusal set re-exported so a caller can name the rule it
## broke without reaching into the module.
func test_the_facade_publishes_the_sink_and_its_refusals() -> void:
	var refusals := ItemsApi.teardown_refusals()
	assert_eq(refusals.size() > 0, true, "the facade re-exports the closed refusal set")
	assert_eq(
		refusals.has(ItemTeardown.REASON_EQUIPPED),
		true,
		"including the one that names the fix: a worn piece comes off first"
	)


## THE assertion: a carried wearable leaves the bag and its materials arrive. Both halves,
## because a teardown that removed the item and paid nothing is the defect the sink exists
## to prevent, and one that paid without removing is a duplication bug.
func test_a_carried_wearable_breaks_down_and_pays_material() -> void:
	var actor := _hero()
	var def := Crafting.resolve(WEARABLE)
	assert_ne(def, null, "'%s' resolves, so the fixture is authored content" % WEARABLE)
	var instance := ItemsApi.generate(actor, def, 7)
	assert_ne(instance, null, "the fixture wearable is acquired as a real instance")
	var inventory := ItemsApi.inventory(actor)
	assert_eq(
		inventory.find_by_instance_id(instance.instance_id) != null,
		true,
		"and it is in the bag before the press"
	)
	var answer := ItemsApi.teardown(actor, instance.instance_id)
	assert_eq(bool(answer["ok"]), true, "the break-down is accepted: %s" % str(answer))
	assert_eq(String(answer["reason"]), "", "an accepted break-down carries no refusal reason")
	assert_eq(int(answer["units"]) > 0, true, "and it pays at least one material: %s" % str(answer))
	assert_eq(inventory.find_by_instance_id(instance.instance_id), null, "the piece left the bag")
	assert_eq(
		inventory.has(StringName(String(answer["material_id"])), int(answer["units"])),
		true,
		"and the materials it paid are in the bag, at the count it reported"
	)


## The read a bar greys a row from. Both are one call into the rule, so the only thing
## that can drift is this suite; what must hold is that the READ is free of side effects,
## or a panel that renders every frame would spend the piece it was merely describing.
func test_the_preview_changes_nothing() -> void:
	var actor := _hero(&"t_teardown_preview")
	var def := Crafting.resolve(WEARABLE)
	var instance := ItemsApi.generate(actor, def, 11)
	var inventory := ItemsApi.inventory(actor)
	var before := inventory.used_slots()
	var preview := ItemsApi.teardown_preview(actor, instance.instance_id)
	assert_eq(
		bool(preview.get("ok", false)),
		true,
		"the preview answers with the same shape the press would: %s" % str(preview)
	)
	assert_eq(inventory.used_slots(), before, "and the bag is untouched by asking")
	assert_eq(
		inventory.find_by_instance_id(instance.instance_id) != null,
		true,
		"the piece is still carried"
	)


## A body that is not there is refused rather than crashing: every other item verb
## null-checks its actor, and this one is called from a screen whose actor can be unset.
func test_a_null_actor_is_refused_by_name() -> void:
	var answer := ItemsApi.teardown(null, &"whatever")
	assert_eq(bool(answer.get("ok", false)), false, "there is no bag to break anything down from")
	assert_eq(
		String(answer.get("reason", "")),
		ItemTeardown.REASON_NO_ACTOR,
		"and the refusal names the rule it broke"
	)


# --- The wiring ---------------------------------------------------------------


## A verb nobody calls is the shape this entry is about, so the bar's own table and the
## screen's own dispatch are read from the source: this is what makes the sink REACHABLE
## rather than merely published.
func test_the_action_bar_offers_the_sink_and_the_screen_dispatches_it() -> void:
	var bar := FileAccess.get_file_as_string(BAR_GD)
	assert_ne(bar, "", "%s ships, so this is not a silent skip" % BAR_GD)
	assert_eq(
		bar.contains('&"teardown"'),
		true,
		"the action bar's ACTIONS table carries the verb, so a button can be lit for it"
	)
	assert_eq(
		bar.contains("%TeardownButton"), true, "and the bar binds the control it is offered through"
	)
	var scene := FileAccess.get_file_as_string(BAR_TSCN)
	assert_eq(
		scene.contains('name="TeardownButton"'),
		true,
		"the scene ships the button, or the table entry is a dead row"
	)
	var screen := FileAccess.get_file_as_string(SCREEN)
	assert_eq(
		screen.contains("act_teardown()"),
		true,
		"and the workbench screen acts on the request instead of ignoring it"
	)
	assert_eq(
		screen.contains("ItemsApi.teardown("),
		true,
		"through the facade, so the screen never names a module"
	)
