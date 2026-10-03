extends TestCase

## The item pipeline, walked through the **mounted** app and its real controls:
##
##   acquire -> roll affixes -> equip -> observe the effective stat change
##   -> socket/imprint -> unequip -> save -> load -> nothing rerolled, nothing
##   duplicated
##
## Every step goes through a facade or a real `Button`, never by constructing item
## state directly. A step whose seam does not exist is a **counted failure** that
## names the seam, never a skipped assertion: `harness.navigate()` returns a note and
## the assertion records it, so the run is red instead of quietly green.
##
## `test_the_full_pipeline_walks_every_step_a_player_would` carries the two steps that
## still need a route — craft and a loot drop — and stays red until the composition
## root publishes one.

const HELM := "armor_iron_helm"
## Where the composition root's file-backed persistence actually writes.
const SAVE_PATH := "user://item_workbench_state.json"
## The screens the routed walk opens. Named by path, never by a private copy of the
## route table: the route id for each is asked of the shipped table at runtime.
const WORKBENCH_SCENE := "res://src/ui/screens/item_workbench.tscn"
const CRAFTING_SCENE := "res://src/ui/screens/crafting_screen.tscn"
const LOOT_SCENE := "res://src/ui/screens/loot_encounter.tscn"
const FORGE_SCENE := "res://src/ui/screens/socket_forge.tscn"
## The composition root's strike deals 25 and the lowest authored boss has 100
## vitality, so four strikes is the whole fight. A cap, not "until it dies": a boss
## that outlasts this is a content bug and must fail rather than spin.
const MAX_STRIKES := 8
## How many bosses the walk will fight before it insists that at least one of
## them paid gear this hero can wear. A cap, not a loop bound: hunting is cheap and
## each boss is one fight, so the walk tries a few routes rather than only the
## first -- a route whose table holds no equipment for this hero pays materials.
const MAX_HUNTS := 4
## The three things a socket transaction costs, and the socket item it seats.
const SOCKET_CONTENT: Array[StringName] = [
	&"socket_rune_mortal_offense",
	&"socket_reagent_mortal_slot_offense",
	&"socket_reagent_mortal_imputation",
]


func setup() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


func _boot() -> SeamHarness:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	return harness


## The first drop the reward is still offering, or `{}` when it offers none.
##
## Read from the screen's own published rows, so the test names the item by what the
## screen says it is rather than by a copy of the loot table.
func _first_claimable(rows: Array) -> Dictionary:
	for row in rows:
		var entry := row as Dictionary
		if bool(entry.get("claimable", false)):
			return entry
	return {}


## The row index of the first drop still claimable, or -1 when there is none.
##
## The row a player presses is found by position in the tree, so the test has to
## name the same position it is about to read rather than assume row 0 is claimable.
## `-1` for "nothing left to press", so a caller can stop rather than keep pressing
## row 0 of a reward it has already taken.
func _claimable_index(rows: Array) -> int:
	for index in rows.size():
		if bool((rows[index] as Dictionary).get("claimable", false)):
			return index
	return -1


## Whether a control is one a player could actually press.
##
## Asked of the control rather than of a rule the test restates: the grade gate and
## the profile gate behind Equip live in the items module, and a test that
## recomputed them would prove its own arithmetic instead of the shipped answer.
func _is_live(control: Button) -> bool:
	return control != null and not control.disabled


## The def ids this actor currently has worn, across every slot.
##
## Which slot an item occupies comes from its subtype, so the honest question is "is
## the drop worn somewhere", not "is it worn in the slot a starter item used to fill".
func _worn_defs(actor: Actor) -> Array[String]:
	var worn: Array[String] = []
	var equipment := ItemsApi.equipment(actor)
	for slot in equipment.all().keys():
		var def := equipment.definition(StringName(slot)) as ItemDef
		if def != null:
			worn.append(String(def.id))
	return worn


# --- The reachable walk ------------------------------------------------------


func test_the_mounted_surfaces_walk_acquire_roll_equip_and_persist() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var workbench := harness.workbench
	var actor := harness.actor

	# ACQUIRE + ROLL. Pick the iron helm the starter kit holds and press Generate: a
	# real Button press, which the action bar turns into a facade call, which rolls a
	# fresh realization and acquires it as its own row.
	# The claim is about the STARTER KIT being present, not about the bag holding
	# exactly that many rows: other systems grant rows too, and pinning an absolute
	# count breaks every time one of them does. The starter kit is proven by the
	# helm being selectable below, and the growth is proven as a delta, which is
	# what survives a peer adding a fourth starter item mid-session.
	var before := workbench.summary() as Dictionary
	assert_eq(int(before["row_count"]) > 0, true, "the bag opens holding the authored starter kit")
	var helm_row := harness.row_of_def(workbench, HELM)
	assert_ne(helm_row, -1, "the iron helm is a selectable inventory row")
	assert_eq(harness.pick_row(workbench, helm_row), true, "the helm row is picked")
	assert_eq(harness.press(workbench, "%GenerateButton"), true, "Generate is a live control")
	var acquired := workbench.summary() as Dictionary
	assert_eq(
		int(acquired["row_count"]),
		int(before["row_count"]) + 1,
		"pressing Generate acquired one more distinct item"
	)
	var detail: Dictionary = acquired["detail"]
	assert_eq(int(detail["rolled_count"]), 1, "it carries the one roll its definition asks for")
	assert_eq(
		(detail["rolled_lines"] as Array).size(),
		1,
		"and the detail panel renders the realized affix, not only its count"
	)
	assert_eq(String(acquired["tone"]), "ok", "the outcome is reported")

	# EQUIP. The helm's subtype is `armor`, so the screen routes it to the armor slot.
	var defense_before := actor.stats.derived(Stat.DEFENSE_PHYSICAL)
	assert_eq(harness.pick_row(workbench, helm_row), true, "the helm row is still picked")
	assert_eq(harness.press(workbench, "%EquipButton"), true, "Equip is a live control")
	var equipped := ItemsApi.equipment(actor).equipped(&"armor")
	assert_ne(equipped, null, "the armor slot holds an instance after the press")
	var defense_after := actor.stats.derived(Stat.DEFENSE_PHYSICAL)
	assert_eq(
		defense_after > defense_before, true, "the equipped item raised the actor's effective armor"
	)
	# The delta is not a literal: the hero also draws defense from its enrolled
	# cultivation paths, so only the item's own authored contribution is pinned here.
	assert_eq(
		defense_after - defense_before >= _declared_defense(equipped),
		true,
		"and the rise covers the item's authored fixed defense"
	)

	# SOCKET + IMPRINT + SEAT, on the forge screen the app itself mounted.
	var forged := _walk_the_forge(harness)
	assert_eq(int(forged["slot_count"]), 1, "the opened slot is on the host")
	assert_eq(bool(forged["slot_occupied"]), true, "and a socket item is seated in it")
	assert_eq(
		int(((forged["slots"] as Dictionary)["0"] as Dictionary)["imputed_count"]) > 0,
		true,
		"and the slot carries its own imputed modifier"
	)

	# SAVE / LOAD through the file-backed callables the composition root injected.
	var signature := equipped.stacking_signature()
	var rows_before_save := int((workbench.summary() as Dictionary)["row_count"])
	# Instances only: an instance's row key is its id and survives a load, while a
	# stack's key is a realization signature `deserialize` does not replay.
	var keys_before_save := _row_keys(workbench)
	assert_eq(harness.press(workbench, "%SaveButton"), true, "Save is a live control")
	assert_eq(FileAccess.file_exists(SAVE_PATH), true, "and it reached the injected file")
	assert_eq(harness.press(workbench, "%LoadButton"), true, "Load is a live control")

	# NOTHING REROLLED, NOTHING DUPLICATED. The realized roll and the derived stat
	# must be the ones that were saved: an append-instead-of-replace deserialize
	# duplicates rows, and a reroll-on-load changes the signature.
	var restored := ItemsApi.equipment(actor).equipped(&"armor")
	assert_ne(restored, null, "the equipped item is still equipped after a load")
	assert_eq(restored.stacking_signature(), signature, "the realized roll was not rerolled")
	assert_almost_eq(
		actor.stats.derived(Stat.DEFENSE_PHYSICAL),
		defense_after,
		"and the effective stat is identical"
	)
	assert_eq(
		int((workbench.summary() as Dictionary)["row_count"]),
		rows_before_save,
		"loading replaces item state, so the row count is unchanged"
	)
	assert_eq(_row_keys(workbench), keys_before_save, "and every row is the same realization")
	assert_eq(harness.press(workbench, "%LoadButton"), true, "a second load is accepted")
	assert_eq(
		int((workbench.summary() as Dictionary)["row_count"]),
		rows_before_save,
		"loading twice still cannot duplicate an item"
	)

	# UNEQUIP. Press Unequip and the bonus is removed exactly once.
	assert_eq(harness.press(workbench, "%UnequipButton"), true, "Unequip is a live control")
	assert_almost_eq(
		actor.stats.derived(Stat.DEFENSE_PHYSICAL), defense_before, "the bonus is gone"
	)
	assert_eq(ItemsApi.equipment(actor).equipped(&"armor"), null, "and the slot is empty")


## Open a socket, impute it and seat a socket item in it by pressing the forge
## screen's own action buttons, on the screen the app mounted over the workbench.
func _walk_the_forge(harness: SeamHarness) -> Dictionary:
	var actor := harness.actor
	# Reach the forge the way a player does: through its route, not by asking the
	# composition root for a screen by hand.
	var moved := harness.navigate(SeamHarness.route_for_scene(FORGE_SCENE))
	assert_eq(moved["ok"], true, "the forge route opens: %s" % moved["note"])
	if not bool(moved["ok"]):
		return {}
	var forge := harness.live_screen()
	# Acquire what the transactions cost, through the two facades that own them.
	for item_id in SOCKET_CONTENT:
		var def := SocketApi.resolve_content(item_id)
		assert_ne(def, null, "%s resolves through the socket facade" % item_id)
		if def == null:
			continue
		assert_ne(
			ItemsApi.generate(actor, def, 7100 + absi(int(item_id.hash())) % 89),
			null,
			"%s was acquired through ItemsApi.generate" % item_id
		)
	harness.app.call("refresh_socket_screen")
	var view := forge.summary() as Dictionary
	assert_ne(String(view["host_instance_id"]), "", "the forge names the host it is showing")

	# Each action is only offered once the program says the player may take it, so a
	# refused control cannot be reported as a working one.
	for pair in [
		[&"create_slot", &"can_create"],
		[&"impute_slot", &"can_impute"],
		[&"insert_socket", &"can_insert"],
	]:
		var action_id: StringName = pair[0]
		var offer: StringName = pair[1]
		assert_eq(
			bool((forge.summary() as Dictionary)[offer]),
			true,
			"the forge offers '%s' before the player presses it" % action_id
		)
		assert_eq(
			harness.action(forge, action_id),
			true,
			"'%s' is a live control on the mounted forge" % action_id
		)
	return forge.summary() as Dictionary


## The row keys of the inventory's *instances*. An instance's key is its instance id,
## so it is stable across a save/load; a stack's key is its realization signature,
## which `ItemsApi.deserialize` does not replay (a real persistence gap in stacks, not
## something a test should assert as correct).
func _row_keys(node: Node) -> Array:
	var panel := node.get_node_or_null("%InventoryPanel") as InventoryPanel
	if panel == null:
		return []
	var summary := panel.summary() as Dictionary
	var keys: Array = summary["row_keys"]
	var inventory := ItemsApi.inventory(panel.get("_actor") as Actor)
	if inventory == null:
		return []
	var out: Array = []
	for key in keys:
		if inventory.find_instance(StringName(String(key))) != null:
			out.append(String(key))
	return out


## The physical defense an instance's own definition declares as a fixed modifier.
## Read from the item rather than written as a literal, so a retune of the content
## does not turn this into a stale expectation.
func _declared_defense(instance: ItemInstance) -> float:
	if instance == null or instance.def_ref == null:
		return 0.0
	for effect in instance.def_ref.fixed_modifiers:
		var entry := effect as Dictionary
		if StringName(entry.get("option_id", "")) == &"core_defense_physical":
			return float(entry.get("value", 0.0))
	return 0.0


# --- The full walk, including the two steps that need a route ---------------


## Fight one boss on `domain_index` and claim everything it pays.
##
## Every step is a shipped control: the domain selector, Enter, Strike until the
## boss falls, Leave, then the reward row's own Pick up. Returns the def ids the
## hunt delivered, so the caller can look for one it can equip.
func _hunt_once(harness: SeamHarness, loot: Node, domain_index: int) -> Array[String]:
	# The selector is a dropdown, so `choose` selects and emits like a click does.
	harness.choose(loot, "%DomainOption", domain_index)
	assert_eq(harness.press(loot, "%EnterButton"), true, "Enter domain is a live control")
	assert_eq(bool((loot.summary() as Dictionary)["in_domain"]), true, "a boss is live")
	# A small, explicit cap rather than "strike until it dies": the app's strike
	# damage is 25 and the lowest authored boss has 100 vitality, so four strikes is
	# the whole fight. If a boss ever outlasts that, the content is wrong and this
	# fails loudly instead of spinning (AGENTS.md, disk-safety rule).
	var strikes := 0
	while bool(((loot.summary() as Dictionary)["enabled"] as Dictionary)["strike"]):
		strikes += 1
		if strikes > MAX_STRIKES:
			assert_eq(true, false, "the boss outlived %d strikes" % MAX_STRIKES)
			break
		harness.press(loot, "%StrikeButton")
	var defeated := loot.summary() as Dictionary
	assert_eq(bool(defeated["in_domain"]), false, "the boss was defeated by repeated strikes")
	assert_eq(int(defeated["reward_count"]) > 0, true, "and its reward is listed")
	assert_eq(int(defeated["pending_drops"]) > 0, true, "with drops the player has not claimed yet")
	var pending := int(defeated["pending_drops"])
	assert_eq(harness.press(loot, "%LeaveButton"), true, "Leave domain is a live control")
	var out := loot.summary() as Dictionary
	assert_eq(bool(out["in_domain"]), false, "nobody is in a domain")
	assert_eq(
		int(out["pending_drops"]),
		pending,
		"leaving keeps the unclaimed reward, so nothing was lost on the way out"
	)
	assert_eq(
		int((out["reward"] as Dictionary)["row_count"]) > 0,
		true,
		"and the reward panel still lists every drop"
	)
	return _claim_every_drop(harness, loot, pending)


## Claim every drop still owed, one reward row at a time, and return their def ids.
##
## The panel lists ONE reward at a time, and claiming the last drop of the listed
## reward retires that encounter -- its payload moves to the claim ledger so nothing
## can address it again -- and the next reward slides into its place. That is why
## "the row now reads as claimed" is NOT observable here: a fully claimed encounter
## does not stay on screen to be read. What is observable is the ledger the screen
## counts and the bag the item lands in.
##
## `owed` is the count read BEFORE the loop and never inside it: the body appends
## one def per claim, so a bound read from the growing list rises in lockstep.
func _claim_every_drop(harness: SeamHarness, loot: Node, owed: int) -> Array[String]:
	var claimed_defs: Array[String] = []
	var ledger := int((loot.summary() as Dictionary)["claimed_encounters"])
	while claimed_defs.size() < owed:
		var live := loot.summary() as Dictionary
		if int(live["pending_drops"]) <= 0:
			break
		var rows := (live["reward"] as Dictionary).get("rows", []) as Array
		var index := _claimable_index(rows)
		if index < 0:
			break
		assert_eq(
			harness.press_drop_action(loot, index), true, "the drop row's Pick up control is live"
		)
		claimed_defs.append(String((rows[index] as Dictionary).get("def_id", "")))
	assert_eq(
		claimed_defs.size(),
		owed,
		"every drop the fight paid was claimed through the reward list's own row action"
	)
	var claimed := loot.summary() as Dictionary
	assert_eq(int(claimed["pending_drops"]), 0, "so nothing is still owed to the player")
	assert_eq(
		int(claimed["claimed_encounters"]) > ledger,
		true,
		"and the encounters moved to the claim ledger the screen counts"
	)
	# The reward list reports what the pickup did, and an accepted claim carries no
	# reason to report, so the outcome line used to render as a bare "Name: " -- the
	# one action that turns a boss into gear saying nothing at all. The wording is the
	# panel's to choose, so what is asserted is that it names what happened rather
	# than trailing off after a separator.
	var outcome := String((claimed["reward"] as Dictionary)["message"])
	assert_eq(outcome.ends_with(":"), false, "and it says what the pickup did: '%s'" % outcome)
	return claimed_defs


func test_the_full_pipeline_walks_every_step_a_player_would() -> void:
	var harness := _boot()
	if harness.boot_error != "":
		return
	var actor := harness.actor

	# ACQUIRE + ROLL, on the workbench route.
	var workbench_route := SeamHarness.route_for_scene(WORKBENCH_SCENE)
	var opened := harness.navigate(workbench_route)
	assert_eq(opened["ok"], true, "the workbench route opens: %s" % opened["note"])
	if not bool(opened["ok"]):
		return
	var workbench := harness.mounted(WORKBENCH_SCENE) as ItemWorkbench
	assert_ne(workbench, null, "the workbench is the mounted screen")
	var helm_row := harness.row_of_def(workbench, HELM)
	assert_ne(helm_row, -1, "the iron helm is offered")
	assert_eq(harness.pick_row(workbench, helm_row), true, "and is picked")
	assert_eq(harness.press(workbench, "%GenerateButton"), true, "Generate acquires a roll")
	assert_eq(
		int((workbench.summary() as Dictionary)["detail"]["rolled_count"]),
		1,
		"the acquired item carries a realized affix"
	)

	# CRAFT, on the crafting route.
	var crafted := harness.navigate(SeamHarness.route_for_scene(CRAFTING_SCENE))
	assert_eq(crafted["ok"], true, "the crafting route opens: %s" % crafted["note"])
	var crafting := harness.mounted(CRAFTING_SCENE)
	assert_ne(crafting, null, "the crafting screen is the mounted screen")
	# A reachable screen that offers nothing is reachable but not usable, so an empty
	# recipe list is a failure rather than a neutral observation.
	assert_eq(
		int((crafting.summary() as Dictionary)["recipe_count"]) > 0,
		true,
		(
			"the crafting route opens with recipes to craft; the starter hero holds none of "
			+ "the inputs, so the route leads to an empty screen"
		)
	)
	var before_craft := int((workbench.summary() as Dictionary)["row_count"])
	assert_eq(harness.press(crafting, "%CraftButton"), true, "Craft is a live control")
	assert_eq(
		int((workbench.summary() as Dictionary)["row_count"]) >= before_craft,
		true,
		"a crafted result never destroys what the player already carried"
	)

	# OBTAIN A DROP, on the loot route.
	var hunted := harness.navigate(SeamHarness.route_for_scene(LOOT_SCENE))
	assert_eq(hunted["ok"], true, "the loot route opens: %s" % hunted["note"])
	var loot := harness.mounted(LOOT_SCENE)
	assert_ne(loot, null, "the loot screen is the mounted screen")
	assert_eq(bool((loot.summary() as Dictionary)["in_domain"]), false, "no boss is live yet")

	# HUNT until a boss pays GEAR this hero can wear, then equip that.
	#
	# One hunt cannot promise it, and the reason is content, not wiring. What a route
	# pays is authored data: a route whose table holds no equipment for this hero's
	# standing pays materials and consumables instead -- a food and a token, on the
	# tree this was written against. Asserting "the drop is wearable" after a single
	# hunt would be asserting a fact about the corpus rather than about the pipeline, and
	# would go red the next time the item corpus is regenerated. So the walk hunts down
	# the domain list the way a player does and stops at the first boss that pays
	# something equippable. The loop is capped by MAX_HUNTS, never by the size of the
	# list it is walking.
	var hunt_budget := mini(MAX_HUNTS, maxi(1, int((loot.summary() as Dictionary)["domain_count"])))
	var claimed_defs: Array[String] = []
	var drop_def := ""
	var hunt := 0
	while drop_def.is_empty() and hunt < hunt_budget:
		claimed_defs.append_array(_hunt_once(harness, loot, hunt))
		# Equip the first claimed drop the workbench's own Equip control accepts. Not
		# every drop a fight pays is wearable: the authored grade gate (ADR 0007) refuses
		# gear above the actor's realm tier, so the choice is asked of the shipped
		# control rather than of a rule this test would be restating.
		assert_eq(harness.navigate(workbench_route)["ok"], true, "back to the workbench by route")
		for def_id in claimed_defs:
			var row := harness.row_of_def(workbench, def_id)
			assert_ne(row, -1, "the claimed drop '%s' is in the bag" % def_id)
			if row == -1:
				continue
			assert_eq(
				harness.pick_row(workbench, row), true, "the claimed drop '%s' is picked" % def_id
			)
			if not _is_live(harness.button(workbench, "%EquipButton")):
				continue
			drop_def = def_id
			break
		hunt += 1
		if drop_def.is_empty():
			assert_eq(
				harness.navigate(SeamHarness.route_for_scene(LOOT_SCENE))["ok"],
				true,
				"and back to the loot route to hunt again"
			)

	assert_ne(
		drop_def,
		"",
		(
			(
				"a boss within %d hunts paid gear this hero can wear; Equip was live for "
				+ "none of %s"
			)
			% [hunt_budget, str(claimed_defs)]
		)
	)

	# Equip the CLAIMED drop, not a starter item. The iron helm is already in the bag
	# before the fight, so equipping it would prove the bag works and prove nothing
	# about acquisition; the objective's loop is "receive a boss drop -> equip it".
	assert_eq(harness.press(workbench, "%EquipButton"), true, "Equip is live")
	# The drop itself is now worn, in whatever slot its subtype declares. This is the
	# assertion the starter helm could never make: the item on the actor came out of a
	# boss, not out of the starting kit.
	assert_eq(
		_worn_defs(actor).has(drop_def),
		true,
		"the boss drop '%s' is the item now equipped, not a starter item" % drop_def
	)
	assert_eq(harness.press(workbench, "%SaveButton"), true, "Save is live")
	assert_eq(harness.press(workbench, "%LoadButton"), true, "Load is live")
	# Asked as "is it still worn", not "is the armor slot full": the slot a drop occupies
	# comes from its subtype, so a drop this fight paid may be an accessory.
	assert_eq(_worn_defs(actor).has(drop_def), true, "the equipped drop survived the round trip")
