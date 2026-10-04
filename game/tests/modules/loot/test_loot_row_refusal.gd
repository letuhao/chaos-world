extends TestCase

## A press on a row the screen is not showing, and the verdict the screen publishes for
## every press it does take.
##
## Two facts that are one defect seen from two sides. `LootRewardList` POOLS its rows, so
## a hidden row keeps the `drop_id` it was last given, and a reader that resolves a
## control by NAME rather than by what is on screen -- a boot probe, a scripted walk --
## finds one of those first. `act_take_all` has always refused that press as
## `stale_reward`; `act_pickup` did not, so it reached the state layer and came back
## `unknown_drop` with no owner. And because every one of those refusals reads the same
## way from the outside ("nothing was collected"), the screen has to publish WHICH one it
## was, or a reader is left inferring the cause from a count that never moved.

var _rig: LootScreenRig = null


func setup() -> void:
	_rig = LootScreenRig.new()


## Free whatever the rig minted. Idempotent, so a suite that returned early is still safe
## to tear down; the runner shares one process across every suite.
func teardown() -> void:
	if _rig != null:
		_rig.release()
		_rig = null


## A press naming a drop the reward list is not showing is refused BY NAME, before the
## facade is asked to do anything, and the world is left exactly as it was.
##
## The press is delivered on the list's own signal, which is what a pooled row does: a
## row that is no longer in `_rows` is hidden but still holds its last `drop_id`, and
## pressing its control reaches this screen carrying a drop from a payload that has
## already been retired. Reproducing that through the widget tree would mean depending on
## how many drops two payloads happened to mint; the signal IS the seam.
func test_a_press_naming_a_drop_the_list_is_not_showing_is_refused_by_name() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var dead := _rig.defeat_boss(view)
	assert_ne(dead, "", "the first boss was defeated")
	var before := view.summary()
	assert_ne(int(before["pending_drops"]), 0, "and it left a drop waiting")

	var list := view.get_node_or_null("%RewardList") as LootRewardList
	assert_ne(list, null, "the reward list is mounted")
	var shown := list.summary().get("row_keys", []) as Array
	assert_eq(shown.is_empty(), false, "and it is showing rows")
	var retired := "retired/payload#d0"
	assert_eq(shown.has(retired), false, "the pressed drop is not one of them")

	list.row_action_requested.emit(retired)
	var refused := view.summary()
	assert_eq(
		String(refused["message"]),
		"Rejected: stale_reward",
		"the press is refused by the screen that owns the routing"
	)
	assert_eq(String(refused["last_reason"]), "stale_reward", "and the reason is published")
	assert_eq(bool(refused["last_ok"]), false, "as a refusal, not a success")
	assert_eq(
		int(refused["pending_drops"]),
		int(before["pending_drops"]),
		"so nothing was collected, rather than some other drop being taken instead"
	)
	assert_eq(int(refused["claimed_encounters"]), 0, "and the encounter's claim is still unspent")


## The facade's own verdict reaches `summary()` for every pickup outcome, so one run can
## tell the refusals apart.
##
## These are the two that used to be indistinguishable from the outside: a full bag with
## room in the world container PARKS the drop and succeeds, and a full bag with a full
## container REFUSES it. Both leave a count that does not move in the way a reader
## expects, and both used to be reported as `inventory_full`, so "the drop is in the
## world" was printed for a drop that was nowhere.
func test_the_screen_publishes_the_facades_verdict_for_each_pickup_outcome() -> void:
	var parking := _rig.hero(1)
	_fill_inventory(parking)
	var parked_view := _rig.screen(parking)
	_rig.enter_domain(parked_view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	_rig.defeat_boss(parked_view)
	assert_eq(_rig.pick_up_row(parked_view, 0), true, "the row's Pick up control drives it")
	var parked := parked_view.summary()
	assert_eq(bool(parked["last_ok"]), true, "a parked drop is a success, and says so")
	assert_eq(
		String(parked["last_reason"]),
		LootState.ERR_INVENTORY_FULL,
		"naming the bag, because the bag is what has no room"
	)

	var jammed := _rig.hero(1)
	_fill_inventory(jammed)
	_fill_world_container(jammed)
	var jammed_view := _rig.screen(jammed)
	_rig.enter_domain(jammed_view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	for _boss in LootScreenRig.EMBER_BOSS_COUNT:
		_rig.defeat_boss(jammed_view)
	var owed := _claimable_rows(jammed_view)
	assert_eq(owed.is_empty(), false, "and there is still a drop to press")
	if owed.is_empty():
		# Everything below is about what a press REPORTS, so there is nothing to report
		# about; stop here rather than index past the end of the list.
		return

	_rig.pick_up_row(jammed_view, int(owed[0]))
	var refused := jammed_view.summary()
	assert_eq(bool(refused["last_ok"]), false, "a refused pickup is not a success")
	assert_eq(
		String(refused["last_reason"]),
		LootState.ERR_WORLD_FULL,
		"naming the container, because nothing was parked"
	)
	assert_ne(
		String(refused["last_reason"]),
		String(parked["last_reason"]),
		"so the two are separable in one run, which is the whole point"
	)


## Park `WORLD_DROP_CAPACITY` drops in the world container as a legal prior state -- the
## shape a player reaches by overflowing a long series of earlier fights. Writes module
## state directly because no single run fills the container, and fabricates no loot.
func _fill_world_container(actor: Actor) -> void:
	var state := LootState.normalize(actor.get_module_data(LootState.MODULE_KEY))
	var stashes: Array = []
	for index in LootState.WORLD_DROP_CAPACITY:
		(
			stashes
			. append(
				{
					"stash_id": "prior_s%d" % index,
					"encounter_id": "prior/encounter",
					"drop_id": "prior/d%d" % index,
				}
			)
		)
	state["world_drops"] = stashes
	actor.set_module_data(LootState.MODULE_KEY, state)


## Fill the bag. The bound is `capacity`, read once before the loop, and the counter is
## advanced unconditionally: re-reading `used_slots()` each pass is the shape that grows
## with the thing it tests. `armor_iron_helm` is not stackable, so one `add` spends one
## slot and the bag really is full afterwards rather than one item into a bigger bag.
func _fill_inventory(actor: Actor) -> void:
	var inventory := ItemsApi.inventory(actor)
	var def := Crafting.resolve(&"armor_iron_helm")
	if def == null or inventory == null:
		return
	var slots := inventory.capacity
	var spent := 0
	while spent < slots:
		spent += 1
		inventory.add(def, 1)


## The row indices of the listed reward that are still claimable.
func _claimable_rows(view: LootEncounterScreen) -> Array:
	var out: Array = []
	var rows := view.summary().get("reward", {}) as Dictionary
	for index in (rows.get("rows", []) as Array).size():
		if bool(((rows.get("rows", []) as Array)[index] as Dictionary)["claimable"]):
			out.append(index)
	return out
