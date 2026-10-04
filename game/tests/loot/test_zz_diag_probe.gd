extends TestCase

## TEMPORARY DIAGNOSTIC - mirrors `tools/boot_probe.gd`'s claim half so the numbers
## can be read. Deleted once the cause is named.

## The probe's press budget for one fight's reward (`MAX_DROPS_PER_REWARD`).
const PROBE_PRESSES := 8
## How many bosses the ember run at the lowest band holds.
const EMBER_BOSS_COUNT := 3

var _rig: LootScreenRig = null


func setup() -> void:
	_rig = LootScreenRig.new()


func teardown() -> void:
	_rig.release()


func _report(lines: Array) -> void:
	print("DIAG| ", " | ".join(lines))


func _first_action(view: LootEncounterScreen) -> Button:
	var list := view.get_node_or_null("%RewardList") as LootRewardList
	if list == null:
		return null
	var rows := list.get_node_or_null("%RewardRows") as VBoxContainer
	if rows == null or rows.get_child_count() < 1:
		return null
	return rows.get_child(0).get_node_or_null("%DropAction") as Button


## The probe's `_collect_pending` + `_why_still_pending`, verbatim in shape.
func _collect(view: LootEncounterScreen, pending_before: int) -> Array:
	var pending := pending_before
	var presses := 0
	while presses < PROBE_PRESSES:
		presses += 1
		if pending <= 0:
			break
		var action := _first_action(view)
		if action == null:
			_report(["no-control", "presses=%d" % presses, "pending=%d" % pending])
			break
		action.pressed.emit()
		pending = int(view.summary()["pending_drops"])
	return [pending, presses]


func test_diag_one_ember_run() -> void:
	var actor := _rig.hero()
	var view := _rig.screen(actor)
	_rig.enter_domain(view, LootScreenRig.EMBER_DOMAIN, LootScreenRig.EMBER_TIER)
	var fights := 0
	while fights < EMBER_BOSS_COUNT:
		fights += 1
		var dead := _rig.defeat_boss(view)
		if dead == "":
			break
		var before := int(view.summary()["pending_drops"])
		var got := _collect(view, before)
		var state := view.summary()
		_report(
			[
				"fight=%d" % fights,
				"listed=%s" % String(state["reward_encounter_id"]),
				"rows=%s" % str(_listed_rows(view)),
				"before=%d" % before,
				"after=%d" % int(got[0]),
				"presses=%d" % int(got[1]),
				"rewards=%d" % int(state["reward_count"]),
				"claimed=%d" % int(state["claimed_encounters"]),
				"stash=%d" % int(state["world_drop_count"]),
				"bag=%d" % int(_bag_rows(actor)),
				"msg=%s" % String(state["message"]),
			]
		)
	assert_eq(true, true, "diagnostic")


func _listed_rows(view: LootEncounterScreen) -> Array:
	var rows: Array = []
	for row in (view.summary().get("reward", {}) as Dictionary).get("rows", []) as Array:
		var entry := row as Dictionary
		rows.append(
			(
				"%s:%s:%s"
				% [
					String(entry.get("drop_id", "")),
					String(entry.get("status", "")),
					String(entry.get("action_enabled", "true"))
				]
			)
		)
	return rows


func _bag_rows(actor: Actor) -> int:
	var inventory := ItemsApi.inventory(actor)
	return 0 if inventory == null else inventory.used_slots()
