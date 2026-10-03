extends TestCase

## Full-inventory safety: a pickup that cannot fit must never lose a drop and never
## spend a claim (rule E5).
##
## The bounded world drop container is the overflow, `Reclaim` is the way back, and a
## full container refuses the pickup outright — which means the drop has to still be
## there afterwards, and taking it must still work once room is made.

var _rig: LootScreenRig = null


func setup() -> void:
	_rig = LootScreenRig.new()


## One slot, already spent, and a drop that needs one: the pickup overflows to the
## world instead of failing, the claim is untouched, and the drop is in the stash.
func test_a_full_inventory_overflows_to_the_world_and_keeps_the_claim() -> void:
	var actor := _rig.hero(1)
	_fill_inventory(actor)
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var dead := _rig.defeat_boss(view)
	var listed := _rig.listed_reward(view)
	var rows := listed["rows"] as Array
	assert_eq(rows.is_empty(), false, "the payload has a row to take")

	assert_eq(_rig.pick_up_row(view, 0), true, "the row's Pick up control drives the pickup")
	var world := view.summary()
	assert_eq(
		int(world["world_drop_count"]), 1, "the drop overflowed into the world drop container"
	)
	var stashed := world["stashed"] as Dictionary
	assert_eq(String(stashed["mode"]), "stashed", "the stash list is in its stash mode")
	assert_eq(int(stashed["row_count"]), 1, "with the drop listed")
	assert_eq(String((stashed["rows"] as Array)[0]["action"]), "Reclaim", "offered for reclaim")
	assert_eq(
		int((world["reward"] as Dictionary)["row_count"]),
		rows.size(),
		"and no drop was discarded: the reward still lists all of them"
	)
	assert_eq(int(world["claimed_encounters"]), 0, "while the encounter's claim is still unspent")
	assert_eq(
		bool(LootApi.reward(actor, dead)["ok"]),
		true,
		"so the payload is still claimable at the facade"
	)


## `Reclaim` puts the drop back in the inventory with the realization the payload was
## built with, and only then is the claim settled.
func test_reclaim_delivers_the_overflowed_drop_with_its_rolls_intact() -> void:
	var actor := _rig.hero(1)
	_fill_inventory(actor)
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var dead := _rig.defeat_boss(view)
	var listed := _rig.listed_reward(view)
	var row := (listed["rows"] as Array)[0] as Dictionary
	var realized := _rig.realized_for(actor, dead, String(row["drop_id"]))

	assert_eq(_rig.pick_up_row(view, 0), true, "the pickup overflows")
	assert_eq(int(view.summary()["world_drop_count"]), 1, "the drop is in the world")

	# Make room, then reclaim through the stash list's own control.
	ItemsApi.inventory(actor).clear()
	assert_eq(_rig.reclaim_row(view, 0), true, "the Reclaim control exists")
	var after := view.summary()
	assert_eq(
		String(after["message"]).begins_with("Rejected:"),
		false,
		"and the reclaim was not refused: %s" % String(after["message"])
	)
	assert_eq(int(after["world_drop_count"]), 0, "the world drop container is empty again")

	var carried := _rig.carried_drop(actor, row)
	assert_ne(carried.is_empty(), true, "the exact realized drop is in the inventory")
	assert_eq(String(carried.get("rarity", "")), String(realized["rarity"]), "rarity intact")
	assert_eq(String(carried.get("realm", "")), String(realized["realm"]), "realm intact")
	assert_eq(
		carried.get("rolled", []),
		realized["rolled"],
		"and the rolled affixes survived the round trip"
	)

	# The payload settles only once nothing is left owing, so empty the inventory again
	# before taking what is still waiting.
	ItemsApi.inventory(actor).clear()
	var owed := _claimable_rows(view)
	for index in owed:
		_rig.pick_up_row(view, int(index))
	var settled := view.summary()
	assert_eq(int(settled["pending_drops"]), 0, "and no drop of that payload is still waiting")
	assert_eq(int(settled["claimed_encounters"]), 1, "so the claim settled, and only now")
	assert_eq(bool(LootApi.reward(actor, dead)["ok"]), false, "and the claim is now spent")


## Reclaiming into a still-full inventory refuses and keeps the drop where it was: no
## discard, no claim spent.
func test_a_refused_reclaim_keeps_the_drop_and_the_claim() -> void:
	var actor := _rig.hero(1)
	_fill_inventory(actor)
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	_rig.defeat_boss(view)
	assert_eq(_rig.pick_up_row(view, 0), true, "the pickup overflows")
	var before := view.summary()

	assert_eq(_rig.reclaim_row(view, 0), true, "the Reclaim control exists")
	var refused := view.summary()
	assert_eq(String(refused["message"]), "Rejected: inventory_full", "the reclaim is refused")
	assert_eq(
		int(refused["world_drop_count"]), int(before["world_drop_count"]), "the drop stayed put"
	)
	assert_eq(int(refused["claimed_encounters"]), 0, "and the encounter's claim is still unspent")
	assert_eq(
		int((refused["reward"] as Dictionary)["row_count"]) > 0,
		true,
		"so the drop is still reachable in the reward too"
	)


## When the world container is full too, the pickup is refused outright: the container
## does not grow, the drop is not discarded, and no claim is spent — so making room and
## pressing the same control again still works.
##
## The full container is a *prior state*, not something this run produces: one
## three-boss run at the shallow band owes fewer drops than the container holds, so
## draining it can never fill it. `LootState.WORLD_DROP_CAPACITY` and the refusal it
## causes are proved at the facade in `test_the_world_drop_container_is_bounded`; what
## this suite owes the screen is that the player is told, rather than left pressing a
## button that quietly does nothing.
func test_a_full_world_container_refuses_without_discarding_or_spending() -> void:
	var actor := _rig.hero(1)
	_fill_inventory(actor)
	_fill_world_container(actor)
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	for _boss in LootScreenRig.EMBER_BOSS_COUNT:
		_rig.defeat_boss(view)

	var full := view.summary()
	assert_eq(
		bool(full["world_drops_full"]),
		true,
		"the bounded world drop container reads as full before anything is offered to it"
	)
	assert_eq(
		int(full["world_drop_count"]), LootState.WORLD_DROP_CAPACITY, "at exactly its capacity"
	)

	var owed := _claimable_rows(view)
	assert_eq(owed.is_empty(), false, "and there is still a drop waiting to be taken")
	if owed.is_empty():
		# Nothing left to press: every assertion below is about what a press does, so
		# stop here rather than index past the end and lose the ones that were fine.
		return

	var drops_before := int(_rig.listed_reward(view)["row_count"])
	_rig.pick_up_row(view, owed[0] as int)
	var refused := view.summary()
	assert_eq(String(refused["message"]), "Rejected: inventory_full", "the pickup is refused")
	assert_eq(String(refused["tone"]), "error", "with the error tone, so it reads as a refusal")
	assert_eq(
		int(refused["world_drop_count"]),
		LootState.WORLD_DROP_CAPACITY,
		"the container did not grow past its bound"
	)
	assert_eq(
		int(_rig.listed_reward(view)["row_count"]),
		drops_before,
		"the drop was not discarded: it is still listed in the reward"
	)
	assert_eq(int(refused["claimed_encounters"]), 0, "and not one claim was spent by the refusal")

	# The refusal cost nothing: make room and press the same control again on a drop that
	# is still genuinely waiting.
	ItemsApi.inventory(actor).clear()
	var waiting := _claimable_rows(view)
	assert_eq(waiting.is_empty(), false, "a drop is still waiting to be taken")
	if waiting.is_empty():
		return
	var pending_before := int(view.summary()["pending_drops"])
	_rig.pick_up_row(view, int(waiting[0]))
	var retried := view.summary()
	assert_eq(
		int(retried["pending_drops"]),
		pending_before - 1,
		"so the very same pickup goes through once there is room"
	)


## Park `WORLD_DROP_CAPACITY` drops in the world container as a legal prior state —
## the same shape a player reaches by overflowing a long series of earlier fights.
## This writes module state directly because there is no play that fills the container
## inside one run; it fabricates no loot, every stash names an encounter the player is
## already owed.
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


## Spend every inventory slot, so every pickup has to overflow.
func _fill_inventory(actor: Actor) -> void:
	var inventory := ItemsApi.inventory(actor)
	var def := Crafting.resolve(&"armor_iron_helm")
	if def != null:
		inventory.add(def, 1)


## The row indices of the listed reward that are still claimable.
func _claimable_rows(view: LootEncounterScreen) -> Array:
	var out: Array = []
	var rows := _rig.listed_reward(view)["rows"] as Array
	for index in rows.size():
		if bool((rows[index] as Dictionary)["claimable"]):
			out.append(index)
	return out
