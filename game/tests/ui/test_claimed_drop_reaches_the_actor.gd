extends TestCase

## The claim -> equip -> sheet walk, driven by the controls of BOTH surfaces.
##
## Three surfaces meet here, and each has its own control the claim depends on:
##
##   - `loot_encounter` — a domain selector, `Enter`, `Strike`, and the reward
##     row's own `Pick up` button. Driven through [LootScreenRig], which is the
##     repo's existing control-driven harness for that surface.
##   - `item_workbench` — the `%ItemList` row a click selects, then `Equip`.
##   - `character_screen` — no buttons at all; the observable outcome is the
##     figure its sheet prints for the stat the equipped item feeds.
##
## Why this is its own suite: each link is proven separately elsewhere (the loot
## rig's own pipeline, `test_item_workbench.gd` at the handler, `test_item_pipeline.gd`
## through the mounted app) and the CHAIN is proven nowhere bottom-up. A chain whose
## links are each green can still be unreachable: the drop can arrive as a stack the
## equip gate cannot see, the row can be unselectable, the button can be dark, and
## every per-link suite stays green while a player holds gear they cannot wear.
##
## The drop is the ember vault warden's GUARANTEED entry, so what the fight pays is
## content, not a gamble: the table authors that row as `guaranteed = true`, and a
## re-roll of the content cannot turn this suite into a coin flip.
##
## No starter kit is assumed anywhere: a real boot currently opens on an empty bag
## (BL-0904), so the hero is the rig's and every row arrives through a claim.

const CLAIMED := "amulet_iron_sage_eye"
## The stat the guaranteed drop's own authored modifier feeds.
const FED := Stat.MAX_QI

var _rig: ItemSurfaceRig = null
var _loot: LootScreenRig = null


func setup() -> void:
	expect_assertions(3)
	_rig = ItemSurfaceRig.new()
	_loot = LootScreenRig.new()


func teardown() -> void:
	# `release()` on both: the workbench and sheet screens are Nodes and must be
	# freed, and the loot rig's screens are the heaviest in the program. Idempotent,
	# so a test that aborted mid-way still leaves nothing mounted.
	_rig.release()
	_loot.release()


## One hero, fought and claimed through the loot screen's controls and then mounted
## on the workbench, so both surfaces read the SAME actor. Returns the workbench.
func _claimed_workbench(actor: Actor) -> ItemWorkbench:
	var view := _loot.screen(actor)
	assert_ne(view, null, "the loot screen mounts")
	assert_eq(_loot.enter_domain(view, LootScreenRig.EMBER_DOMAIN), true, "Enter is pressed")
	var encounter := _loot.defeat_boss(view)
	assert_ne(encounter, "", "the warden falls to repeated Strike presses")
	var pending := int(view.summary()["pending_drops"])
	assert_eq(pending > 0, true, "and the fight paid drops")
	# Take all, through the reward list's own button. Bounded by the panel's own
	# limit and it stops the moment a pass moves nothing, so a screen whose controls
	# do nothing ends the drain instead of spinning.
	_loot.take_everything(view)
	assert_eq(
		ItemsApi.has_item(actor, StringName(CLAIMED)),
		true,
		"the observable outcome of the claim: the warden's guaranteed drop is in the bag"
	)
	var workbench := _rig.screen(ItemSurfaceRig.WORKBENCH_SCENE) as ItemWorkbench
	workbench.setup(actor)
	return workbench


## The sheet the player reads, mounted on the same actor.
func _sheet(actor: Actor) -> CharacterScreen:
	var screen := _rig.screen(ItemSurfaceRig.CHARACTER_SCENE) as CharacterScreen
	screen.setup(actor)
	return screen


## The figure the sheet PRINTS for `stat`, read from the rendered row rather than
## from the screen's own derived map, because the printed row is what a player
## looks at. Named by the sheet's label, since rows are labelled not keyed by id.
func _printed(sheet: CharacterScreen, stat: StringName) -> float:
	var label := StatPresenter.label_for(stat)
	for name in (sheet.summary()["vitals"] as Dictionary).keys():
		var row: Dictionary = (sheet.summary()["vitals"] as Dictionary)[name]
		if String(name) == label:
			return float(row.get("current", 0.0))
	return -1.0


# --- The chain ---------------------------------------------------------------


## The whole walk: fight, claim, equip, and read the figure off the sheet. The
## final assertion is the only one that matters — the drop left a boss, went
## through two screens' controls, and moved a number on the sheet.
func test_a_claimed_drop_is_equipped_by_a_press_and_shows_on_the_sheet() -> void:
	var actor := _loot.hero()
	var sheet := _sheet(actor)
	var printed_before := _printed(sheet, FED)
	assert_ne(printed_before, -1.0, "the sheet prints the stat the drop feeds")
	var workbench := _claimed_workbench(actor)
	var row := _rig.row_of_def(workbench, CLAIMED)
	assert_ne(row, -1, "the claimed drop is a selectable bag row")
	assert_eq(_rig.pick_row(workbench, row), true, "the row is picked by a click")
	assert_eq(
		_rig.button(workbench, "%EquipButton").disabled,
		false,
		"Equip is offered: a drop that arrived as a stack would be refused here"
	)
	assert_eq(_rig.press(workbench, "%EquipButton"), true, "the Equip control is pressable")
	assert_eq(
		ItemsApi.equipment(actor).equipped(&"accessory_a") != null,
		true,
		"the observable outcome: the claimed drop is worn"
	)
	workbench.refresh()
	# The sheet repaints on its own lifecycle hook (`on_screen_shown`, which the
	# stack calls); off a stack the same repaint is `refresh()`. Without it the
	# sheet would still be showing the figure it drew before the press.
	sheet.refresh()
	var printed_after := _printed(sheet, FED)
	assert_eq(
		printed_after > printed_before,
		true,
		"and the sheet now prints the higher figure, so the player can see the gear took"
	)


## The slot the drop landed in comes from its own subtype, so the honest question
## is "is it worn somewhere", not "is the slot a fixture expected full".
func test_the_claimed_drop_is_worn_in_the_slot_its_subtype_authorises() -> void:
	var actor := _loot.hero()
	var workbench := _claimed_workbench(actor)
	var def := Crafting.resolve(StringName(CLAIMED))
	assert_ne(def, null, "the drop's authored definition resolves")
	_rig.pick_row(workbench, _rig.row_of_def(workbench, CLAIMED))
	_rig.press(workbench, "%EquipButton")
	var allowed := ItemsApi.equipment(actor).slots_for(def)
	assert_eq(allowed.is_empty(), false, "its subtype authorises at least one slot")
	var worn := false
	for slot in allowed:
		var equipped := ItemsApi.equipment(actor).equipped(StringName(slot))
		if equipped != null and String(equipped.def_id) == CLAIMED:
			worn = true
	assert_eq(worn, true, "the drop is worn in one of the slots its subtype authorises")


## A drop the gate refuses must not be equippable, and the refusal has to be the
## CONTROL's state rather than a press that returns false: a lit Equip that can
## only ever be refused is the defect `ItemActionRules` exists to prevent.
func test_a_drop_the_gate_refuses_leaves_equip_dark() -> void:
	var actor := _loot.hero()
	var workbench := _claimed_workbench(actor)
	var claimed: StringName = StringName(CLAIMED)
	var def := Crafting.resolve(claimed)
	# Bind the drop to another hero so the gate has something to refuse that does
	# not depend on which realm the fight happened to pay.
	var gated := ItemGenerator.generate(def, &"bound_elsewhere", _rng(97))
	ItemsApi.inventory(actor).add_instance(gated)
	ItemsApi.equip_item(actor, &"weapon", def)
	var row := _rig.row_of_def(workbench, String(gated.instance_id))
	if row == -1:
		# The listing keys an instance row by its own id, so find it the same way
		# the panel does rather than by def: two instances of one def are two rows.
		row = _row_of_instance(workbench, gated.instance_id)
	assert_ne(row, -1, "the bound copy is a selectable bag row")
	assert_eq(_rig.pick_row(workbench, row), true, "it is picked")
	assert_eq(
		_rig.button(workbench, "%EquipButton").disabled,
		true,
		"Equip is dark: the copy is bound to another hero, so the facade would refuse"
	)
	assert_eq(_rig.press(workbench, "%EquipButton"), false, "and a press on it is refused")
	assert_eq(
		String(workbench.summary()["message"]).is_empty(),
		true,
		"nothing was attempted, so nothing was reported"
	)


# --- The sheet, on its own ---------------------------------------------------


## The sheet is reached by being pushed on a real stack, and it is the only screen
## the stack tells about input. A read-only sheet that is mounted but never pushed
## is unreachable, and no assertion about its rows would notice.
func test_the_sheet_is_reachable_on_the_stack_and_reads_the_live_actor() -> void:
	var actor := _loot.hero()
	var mounted := _rig.stack_with(ItemSurfaceRig.CHARACTER_SCENE)
	var stack := mounted.get("stack") as ScreenStack
	var sheet := mounted.get("screen") as CharacterScreen
	assert_ne(stack, null, "a real stack is mounted")
	assert_ne(sheet, null, "the sheet pushes onto it")
	sheet.setup(actor)
	assert_eq(stack.current(), sheet, "it is the live screen")
	assert_eq(
		stack.summary()["input_names"] as Array,
		[String(sheet.name)],
		"and the only screen the stack forwards input to"
	)
	var printed := _printed(sheet, Stat.MAX_HEALTH)
	assert_ne(printed, -1.0, "the sheet prints the actor's max health from its own pool")
	assert_eq(
		printed,
		actor.resource(&"health").maximum,
		"and that figure is the actor's, not a number the sheet chose"
	)


## The sheet's rows are the SCENE's own `StatRow`s, not rows the screen composed
## for itself. The screen used to ask for `%pool0Row` while the scene declares
## `Pool0Row`, so it bound nothing, drew an empty sheet, and still reported every
## stat in `summary()`. So the claim is about the NODES: the rendered rows are the
## scene's instances.
func test_the_sheet_draws_the_scenes_own_rows() -> void:
	var actor := _loot.hero()
	var sheet := _sheet(actor)
	var list := sheet.get_node_or_null("Layout/Scroll/Stats") as VBoxContainer
	assert_ne(list, null, "the scene composes the sheet's rows into this list")
	var from_scene := 0
	for row in _rig.all_named(list, "Stat0Row"):
		assert_ne(
			row.get_scene_file_path(), "", "the row is an instanced scene, not a bare StatRow"
		)
		from_scene += 1
	assert_eq(from_scene > 0, true, "the scene's own rows are bound and rendered")
	assert_ne(_printed(sheet, Stat.MAX_QI), -1.0, "and one of them carries a printed figure")


# --- Helpers -----------------------------------------------------------------


## The listing row index of the instance `instance_id`, or -1. Asked of the panel's
## own row keys, because an instance row is keyed by its id and two instances of one
## definition are two rows.
func _row_of_instance(workbench: ItemWorkbench, instance_id: StringName) -> int:
	var panel := _rig.find_unique(workbench, "%InventoryPanel") as InventoryPanel
	if panel == null:
		return -1
	var keys: Array = (panel.summary() as Dictionary)["row_keys"]
	return keys.find(String(instance_id))


## A deterministic generator stream, so a realized roll is reproducible without
## depending on the global RNG.
func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng
