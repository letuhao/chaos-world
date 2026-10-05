extends TestCase

## The ITEM WORKBENCH surface, driven through the buttons a player presses.
##
## `test_item_workbench.gd` holds the screen object and calls `act_use()`,
## `act_equip()`, `act_unequip()` and `act_generate()` directly. That proves the
## handler works; it proves nothing about whether the RENDERED button reaches it.
## A button that was never connected to `action_requested` renders, sits lit, and
## does nothing, and every one of those direct calls stays green.
##
## So every case here names the control it presses (`%UseButton`, `%EquipButton`,
## `%UnequipButton`, `%GenerateButton`, `%SaveButton`, `%LoadButton`, and the
## `%ItemList` row a click selects), and asserts an OBSERVABLE OUTCOME: the pool
## rose, the effective stat moved, the bag gained or lost a row, the slot emptied.
## Never merely that a press returned true.
##
## ## Why every hero carries a second item
##
## Equipping removes the item from the bag, so a one-item bag empties and the
## screen drops its selection — at which point it greys out the whole action row,
## Unequip and Save/Load included (BL-0905, filed: those three do not depend on a
## selection and must not be gated by one). A suite that proved Unequip on an
## empty bag would be proving a defect. So each hero carries a second, unrelated
## item, which is also the realistic case: a bag always holds more than the thing
## under the cursor.
##
## Nothing here assumes a starter kit: a real boot currently opens on an empty bag
## (BL-0904), so every hero stocks what it needs through the facade.

## An authored mortal weapon. The grade gate admits `mortal` for a hero on no
## cultivation path, and its authored `core_attack_physical` modifier is what the
## observable stat delta is measured against.
const WEAPON := &"blade_iron"
## An authored consumable whose only authored option is `restore_health`, so Use
## has a real effect to apply and the hero's health pool is the observable
## outcome. Deliberately NOT a `*_recovery_elixir`: those are ruled progression
## inputs, and `ItemUse.spend_gate` refuses them as `progression_input` because
## the cultivation path is the only thing allowed to spend one (BL-0110).
const DRAUGHT := &"F46_mortal_grainery_attack_speed_evasion_fortune"
## An authored progression input: a consumable whose whole use the cultivation
## path owns. `ItemActionRules` still offers the Use control for it (it only
## mirrors the channel and the carried check), so this is the case where the
## control is lit, the press lands, and the FACADE is what refuses.
const PIL := &"body_body_integration_recovery_elixir"
## The stat the weapon's authored modifier lands on.
const ATTACK := Stat.ATTACK_PHYSICAL

var _rig: ItemSurfaceRig = null
var _vault: ItemSurfaceRig.Vault = null


func setup() -> void:
	# A per-SUITE floor, so it is the SMALLEST body here: the two-assertion control
	# presence case. It catches a body that died mid-way, which records neither a
	# pass nor a failure and so reports green while having skipped its proof.
	expect_assertions(2)
	_rig = ItemSurfaceRig.new()
	_vault = ItemSurfaceRig.Vault.new()


func teardown() -> void:
	_rig.release()


## A hero holding the weapon AND an unrelated second item, so equipping the first
## does not empty the bag and grey out the row the remaining actions live on.
func _hero_with_weapon(seed_value: int) -> Actor:
	var actor := _rig.hero()
	assert_ne(_rig.acquire(actor, WEAPON, seed_value), null, "the weapon is acquired")
	assert_eq(_rig.stock_authored(actor, DRAUGHT, 1), true, "a second item keeps the bag non-empty")
	return actor


## The workbench, mounted and bound to `actor`, with Save/Load pointed at an
## in-memory vault.
func _workbench(actor: Actor) -> ItemWorkbench:
	var view := _rig.screen(ItemSurfaceRig.WORKBENCH_SCENE) as ItemWorkbench
	if view == null:
		return null
	view.setup(actor, _vault.save, _vault.load_state)
	return view


## Pick a bag row by the def it offers and confirm the click landed, so a failing
## case names the selection rather than the action that followed it.
func _select(screen: ItemWorkbench, def_id: String) -> bool:
	var row := _rig.row_of_def(screen, def_id)
	if row == -1:
		return false
	return _rig.pick_row(screen, row)


## The restoration an authored consumable declares, read from its own definition
## rather than written as a literal, so a retune of the content does not turn this
## into a stale expectation.
func _authored_restore(def_id: StringName) -> float:
	var def := Crafting.resolve(def_id)
	if def == null:
		return 0.0
	for effect in def.fixed_modifiers:
		var entry := effect as Dictionary
		if StringName(entry.get("option_id", "")) == &"restore_health":
			return float(entry.get("value", 0.0))
	return 0.0


# --- Use: a live control that consumes a unit and moves a pool ---------------


## The observable half of Use. A button wired to nothing leaves the pool exactly
## where it was and the row still lit, so the pool figure is the only thing that
## tells the two apart. The expected figure is the ITEM'S OWN authored
## restoration, read from its definition, so a pass means the right item acted.
func test_pressing_use_applies_the_items_own_restoration() -> void:
	var actor := _rig.hero()
	var restore := _authored_restore(DRAUGHT)
	assert_ne(restore, 0.0, "the draught declares a restoration to apply")
	assert_eq(_rig.stock_authored(actor, DRAUGHT, 2), true, "the draught enters the bag")
	var screen := _workbench(actor)
	# An empty pool, so the rise is the item's and not a clamp refusing to move.
	actor.resource(&"health").current = 0.0
	assert_eq(_select(screen, String(DRAUGHT)), true, "the draught row is picked")
	assert_eq(_rig.button(screen, "%UseButton").disabled, false, "Use is offered for a consumable")
	assert_eq(_rig.press(screen, "%UseButton"), true, "the Use control is pressable")
	assert_eq(
		actor.resource(&"health").current >= restore,
		true,
		(
			"the observable outcome: the pool rose by at least the item's own authored "
			+ (
				"restoration, so the press acted on the item that was picked (got %f, authored %f)"
				% [actor.resource(&"health").current, restore]
			)
		)
	)
	assert_eq(ItemsApi.inventory(actor).count(DRAUGHT), 1, "and exactly one unit was consumed")


## The control is lit and the press lands, and the FACADE is what refuses. A
## progression input is owned by the cultivation path, so a press must leave both
## the pool and the bag untouched — and say so, rather than destroying the only
## copy of the price of an attempt (BL-0110).
func test_a_refused_press_consumes_nothing_and_names_the_ownership() -> void:
	var actor := _rig.hero()
	assert_eq(_rig.stock_authored(actor, PIL, 1), true, "the pill enters the bag")
	var screen := _workbench(actor)
	actor.resource(&"health").current = 10.0
	assert_eq(_select(screen, String(PIL)), true, "the pill row is picked")
	assert_eq(
		_rig.button(screen, "%UseButton").disabled,
		false,
		"Use is offered: the gate is not the panel's"
	)
	assert_eq(_rig.press(screen, "%UseButton"), true, "the press reaches the facade")
	assert_eq(
		ItemsApi.inventory(actor).count(PIL),
		1,
		"the observable outcome: the pill survives a press the path owns"
	)
	assert_almost_eq(actor.resource(&"health").current, 10.0, "and nothing was applied")
	assert_eq(
		String(screen.summary()["message"]),
		"Rejected: progression_input",
		"the refusal names the ownership rather than reading as a no-op"
	)


# --- Equip / Unequip: the observable stat delta ------------------------------


## Equip, read as a stat the actor can fight with. `derived()` is read before and
## after rather than recomputed, so the claim is that the PRESS moved the actor.
func test_pressing_equip_fills_the_slot_and_raises_the_effective_stat() -> void:
	var actor := _hero_with_weapon(4242)
	var screen := _workbench(actor)
	var before := actor.stats.derived(ATTACK)
	assert_eq(_select(screen, String(WEAPON)), true, "the weapon row is picked")
	assert_eq(_rig.button(screen, "%EquipButton").disabled, false, "Equip is offered")
	assert_eq(_rig.press(screen, "%EquipButton"), true, "the Equip control is pressable")
	var worn := ItemsApi.equipment(actor).equipped(&"weapon")
	assert_ne(worn, null, "the weapon slot holds an instance after the press")
	assert_eq(
		actor.stats.derived(ATTACK) > before,
		true,
		"the observable outcome: the effective attack rose, so the press equipped it"
	)
	assert_eq(ItemsApi.has_item(actor, WEAPON), false, "and it left the bag")


## Unequip, read the same way. A dark Unequip that quietly did nothing would leave
## the delta above in place forever, so the delta has to come back down to exactly
## where it started.
func test_pressing_unequip_empties_the_slot_and_removes_the_bonus() -> void:
	var actor := _hero_with_weapon(4343)
	var screen := _workbench(actor)
	var before := actor.stats.derived(ATTACK)
	_select(screen, String(WEAPON))
	_rig.press(screen, "%EquipButton")
	assert_eq(actor.stats.derived(ATTACK) > before, true, "the weapon is worn")
	assert_eq(_rig.button(screen, "%UnequipButton").disabled, false, "Unequip is offered")
	assert_eq(_rig.press(screen, "%UnequipButton"), true, "the Unequip control is pressable")
	assert_eq(ItemsApi.equipment(actor).equipped(&"weapon"), null, "the slot is empty")
	assert_almost_eq(
		actor.stats.derived(ATTACK),
		before,
		"the bonus is gone: a handler wired to nothing would have left it in place"
	)
	assert_eq(ItemsApi.has_item(actor, WEAPON), true, "and the weapon is carried again")


# --- Generate: the control that mints an item -------------------------------


## Generate is the one action that has no prior item to act on, so its observable
## outcome is the BAG growing by a row the listing then shows.
func test_pressing_generate_acquires_a_row_the_listing_shows() -> void:
	var actor := _rig.hero()
	assert_ne(_rig.acquire(actor, WEAPON, 4444), null, "the weapon is acquired")
	var screen := _workbench(actor)
	assert_eq(_select(screen, String(WEAPON)), true, "the weapon row is picked")
	var before := int(screen.summary()["row_count"])
	assert_eq(_rig.button(screen, "%GenerateButton").disabled, false, "Generate is offered")
	assert_eq(_rig.press(screen, "%GenerateButton"), true, "the Generate control is pressable")
	assert_eq(
		int(screen.summary()["row_count"]),
		before + 1,
		"the observable outcome: the listing gained a row"
	)
	assert_eq(
		ItemsApi.inventory(actor).instances().size(),
		2,
		"and the bag holds two distinct instances of the same definition"
	)


## Two presses, two realizations. A handler that minted the same instance twice
## would pass the count above and fail here.
func test_two_generates_produce_two_distinct_instances() -> void:
	var actor := _rig.hero()
	_rig.acquire(actor, WEAPON, 4545)
	var screen := _workbench(actor)
	_rig.pick_row(screen, _rig.row_of_def(screen, String(WEAPON)))
	assert_eq(_rig.press(screen, "%GenerateButton"), true, "the first Generate is pressable")
	assert_eq(_rig.press(screen, "%GenerateButton"), true, "so is the second")
	var ids := {}
	for instance in ItemsApi.inventory(actor).instances():
		ids[String(instance.instance_id)] = true
	assert_eq(ids.size(), 3, "every instance keeps its own identity")
	assert_eq(int(screen.summary()["row_count"]), 3, "and each one is its own listing row")


# --- Save / Load: the persistence controls -----------------------------------


## The round trip through the two rendered buttons. The observable outcome is that
## a realization survives Save and Load unchanged: an append-instead-of-replace
## deserialize duplicates rows, and a reroll-on-load changes the signature.
func test_save_and_load_pressed_as_buttons_preserve_the_realized_roll() -> void:
	var actor := _hero_with_weapon(4646)
	var screen := _workbench(actor)
	_select(screen, String(WEAPON))
	_rig.press(screen, "%EquipButton")
	var signature: String = ItemsApi.equipment(actor).equipped(&"weapon").stacking_signature()
	var rows := int(screen.summary()["row_count"])
	assert_eq(_rig.button(screen, "%SaveButton").disabled, false, "Save is offered")
	assert_eq(_rig.press(screen, "%SaveButton"), true, "the Save control is pressable")
	assert_eq(_vault.payload.is_empty(), false, "and it reached the injected callable")
	assert_eq(_rig.press(screen, "%LoadButton"), true, "the Load control is pressable")
	assert_eq(
		String(ItemsApi.equipment(actor).equipped(&"weapon").stacking_signature()),
		signature,
		"the observable outcome: the realized roll was not rerolled by the round trip"
	)
	assert_eq(
		int(screen.summary()["row_count"]),
		rows,
		"loading replaces item state, so the bag cannot have grown a duplicate"
	)


## Save pressed twice and loaded once more still cannot duplicate an item.
func test_loading_twice_cannot_duplicate_a_row() -> void:
	var actor := _hero_with_weapon(4747)
	var screen := _workbench(actor)
	var rows := int(screen.summary()["row_count"])
	_rig.press(screen, "%SaveButton")
	assert_eq(_rig.press(screen, "%LoadButton"), true, "the first Load is pressable")
	assert_eq(_rig.press(screen, "%LoadButton"), true, "a second Load is accepted")
	assert_eq(int(screen.summary()["row_count"]), rows, "the listing is unchanged by both")


## The controls exist and are wired at all. Without this, a case above could fail
## for a reason that has nothing to do with the action it is about.
func test_the_action_controls_are_present_on_the_mounted_screen() -> void:
	var screen := _workbench(_rig.hero())
	var present := 0
	for control in [
		"%UseButton",
		"%EquipButton",
		"%UnequipButton",
		"%GenerateButton",
		"%SaveButton",
		"%LoadButton"
	]:
		var button := _rig.button(screen, control)
		assert_ne(button, null, "%s is on the screen" % control)
		if button != null:
			present += 1
	assert_eq(present, 6, "every action control the surface offers is on the screen")


# --- The control a player cannot press ---------------------------------------


## A dead control is the defect this file exists for, so the negative case is
## stated: an EQUIPMENT item has no Use verb, so the Use button must be dark for
## it, and pressing a disabled control is refused rather than counted as a press.
func test_use_is_dark_for_an_equipment_row_and_a_press_on_it_is_refused() -> void:
	var actor := _rig.hero()
	_rig.acquire(actor, WEAPON, 4848)
	_rig.stock_authored(actor, DRAUGHT, 1)
	var screen := _workbench(actor)
	assert_eq(_select(screen, String(WEAPON)), true, "the equipment row is picked")
	assert_eq(
		_rig.button(screen, "%UseButton").disabled,
		true,
		"an EQUIPMENT item has no Use verb, so the control must not be offered"
	)
	assert_eq(_rig.press(screen, "%UseButton"), false, "and a press on it is refused")
	assert_eq(ItemsApi.has_item(actor, WEAPON), true, "the item is untouched by the refused press")
