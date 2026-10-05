extends TestCase

## The loot reward list: one row per drop, every number and every refusal word
## owned by the panel, and the world drop container rendered through the same rows.

const LIST_SCENE := "res://src/ui/panels/loot_reward_list.tscn"

## Every panel this suite instantiated. The runner shares one process across every
## suite, so a panel that is never freed stays resident for the rest of the run —
## and each one is a whole row subtree, so eight leaked panels is hundreds of live
## Controls. Tracked centrally rather than freed at each call site because the
## call sites are interleaved and a test that returns early would skip a free.
var _born: Array[Node] = []


## Free everything `_list()` handed out. Idempotent, so it is safe after an abort.
func teardown() -> void:
	for node in _born:
		if is_instance_valid(node):
			node.free()
	_born.clear()


func _list() -> LootRewardList:
	var scene: PackedScene = load(LIST_SCENE)
	assert_ne(scene, null, "the reward list scene loads")
	var list := scene.instantiate() as LootRewardList
	_born.append(list)
	list.call("_ready")
	return list


func _effect(label: String, value: float, channel: String = "rolled") -> Dictionary:
	return {
		"option_id": &"probe_option",
		"label": label,
		"channel": channel,
		"value": value,
		"unit": &"magnitude",
		"value_min": 1.0,
		"value_max": 9.0,
	}


func _drop(
	drop_id: String, quantity: int = 1, claimed: bool = false, stashed: bool = false
) -> Dictionary:
	return {
		"drop_id": drop_id,
		"def_id": "amulet_iron_sage_eye",
		"display_name": "Iron Sage Eye",
		"category": "equipment",
		"subcategory": "accessory",
		"quantity": quantity,
		"stackable": false,
		"rarity": "rare",
		"realm": "spirit_severing",
		"instance_id": "%s#i0" % drop_id,
		"rolled_count": 2,
		"effect_count": 2,
		"effects": [_effect("Attack Physical", 4.5), _effect("Max Qi", 6.0, "fixed")],
		"claimed": claimed,
		"stashed": stashed,
		"claimable": not claimed and not stashed,
	}


func _reward(drops: Array, pending: int = 2) -> Dictionary:
	return {
		"encounter_id": "loot_ember_vault_domain/loot_ember_vault_warden@1#1",
		"claim_token": "loot_ember_vault_domain/loot_ember_vault_warden@1#1",
		"drop_count": drops.size(),
		"pending_count": pending,
		"claimed_count": maxi(0, drops.size() - pending),
		"stashed_count": 0,
		"settled": false,
		"drops": drops,
	}


func _rows(list: LootRewardList) -> VBoxContainer:
	return list.get_node_or_null("%RewardRows") as VBoxContainer


func _row_node(list: LootRewardList, index: int) -> LootDropRow:
	return _rows(list).get_child(index) as LootDropRow


func test_an_empty_reward_clears_the_list() -> void:
	var list := _list()
	list.show_reward(_reward([_drop("a"), _drop("b")]), true)
	assert_eq(int(list.summary()["row_count"]), 2, "two rows rendered")
	list.show_reward({}, true)
	assert_eq(int(list.summary()["row_count"]), 0, "an empty reward clears the list")
	assert_eq(str(list.summary()["encounter_id"]), "", "and forgets the encounter")


func test_one_row_per_drop_keeps_the_raw_values() -> void:
	var list := _list()
	list.show_reward(_reward([_drop("a", 3), _drop("b", 1, true)]), true)
	var summary := list.summary()
	assert_eq(int(summary["row_count"]), 2, "one row per drop")
	assert_eq(
		str(summary["encounter_id"]),
		"loot_ember_vault_domain/loot_ember_vault_warden@1#1",
		"the encounter"
	)
	assert_eq(str(summary["row_keys"]), '["a", "b"]', "rows are keyed by drop id")
	var first := (summary["rows"] as Array)[0] as Dictionary
	assert_eq(int(first["quantity"]), 3, "the raw quantity travels, unformatted")
	assert_eq(str(first["rarity"]), "rare", "the raw rarity id travels")
	assert_eq(str(first["rarity_label"]), "Rare", "and its display name")
	assert_eq(int(first["rolled_count"]), 2, "the realized affix count travels")
	assert_eq(int(first["effect_line_count"]), 2, "one line per resolved effect")
	assert_eq(bool(first["action_enabled"]), true, "the row's action is live")
	var second := (summary["rows"] as Array)[1] as Dictionary
	assert_eq(bool(second["claimed"]), true, "a claimed drop reads as claimed")
	assert_eq(str(second["status"]), "claimed", "with its own status")
	assert_eq(int(summary["pending_count"]), 1, "one drop still waits")


func test_the_panel_owns_every_number_and_the_value_window() -> void:
	var list := _list()
	list.show_reward(_reward([_drop("a", 3)]), true)
	var row := _row_node(list, 0)
	var name_label := row.get_node_or_null("%DropName") as Label
	assert_eq(name_label.text.contains("Iron Sage Eye"), true, "the name is rendered")
	assert_eq(name_label.text.contains("x3"), true, "the panel owns the amount wording")
	var meta := row.get_node_or_null("%DropMeta") as Label
	assert_eq(meta.text.contains("Rare rarity"), true, "the rarity label is the panel's vocabulary")
	assert_eq(meta.text.contains("realm spirit_severing"), true, "and the roll realm is shown")
	var effects := row.get_node_or_null("%DropEffects") as VBoxContainer
	assert_eq(effects.get_child_count(), 2, "both effect lines are rendered")
	var first := String((effects.get_child(0) as Label).text)
	assert_eq(first.contains("(1.00 - 9.00)"), true, "the window the roll was legal from is shown")
	assert_eq(first.contains("[rolled]"), true, "the channel is shown")
	assert_eq(String((effects.get_child(1) as Label).text).contains("[fixed]"), true, "per channel")
	var instance := row.get_node_or_null("%DropInstance") as Label
	assert_eq(
		instance.text.contains("2 rolled affix(es)"), true, "the affix count is the panel's wording"
	)


func test_a_refusal_is_reported_on_the_row_it_belongs_to() -> void:
	var list := _list()
	list.show_reward(_reward([_drop("a")]), true)
	list.report_outcome("a", "inventory_full", &"error")
	var summary := list.summary()
	assert_eq(
		String(summary["message"]).contains("Inventory full"),
		true,
		"the refusal wording is the panel's"
	)
	assert_eq(String(summary["tone"]), "error", "and it carries the tone")
	list.report_outcome("a", "drop_already_claimed", &"error")
	assert_eq(
		String(list.summary()["message"]).ends_with("Already taken"),
		true,
		"each reason has its own wording, and the message names the drop"
	)
	list.report_outcome("a", "world_drops_full", &"error")
	assert_eq(
		String(list.summary()["message"]).contains("world drops are full"), true, "the bounded case"
	)


func test_take_all_is_only_offered_when_there_is_something_to_take() -> void:
	var list := _list()
	list.show_reward(_reward([_drop("a")], 1), true)
	assert_eq(bool(list.summary()["take_all_enabled"]), true, "offered while a drop waits")
	list.show_reward(_reward([_drop("a", 1, true)], 0), true)
	assert_eq(
		bool(list.summary()["take_all_enabled"]), false, "not offered once the reward is settled"
	)
	list.show_reward(_reward([_drop("a")], 1), false)
	assert_eq(
		bool(list.summary()["take_all_enabled"]), false, "not offered when pickup is disabled"
	)


func test_the_world_drop_container_renders_through_the_same_rows() -> void:
	var list := _list()
	var stashed := _drop("a", 2)
	stashed["stashed"] = true
	stashed["claimable"] = false
	stashed["stash_id"] = "a"
	list.show_stashes([stashed], true)
	var summary := list.summary()
	assert_eq(str(summary["mode"]), "stashed", "the list is in its stash mode")
	assert_eq(int(summary["stashed_count"]), 1, "the drop reads as stashed")
	assert_eq(bool(summary["take_all_enabled"]), false, "there is nothing to take all in the world")
	var row := (summary["rows"] as Array)[0] as Dictionary
	assert_eq(str(row["action"]), "Reclaim", "the row offers the reclaim action")
	assert_eq(str(row["stash_id"]), "a", "and is addressable by its stash id")
	assert_eq(
		String((_row_node(list, 0).get_node_or_null("%DropAction") as Button).text),
		"Reclaim",
		"and the button says so"
	)


func test_the_list_reports_the_action_that_was_pressed() -> void:
	var list := _list()
	var picked: Array = []
	var taken: Array = []
	list.row_action_requested.connect(func(drop_id: String) -> void: picked.append(drop_id))
	list.take_all_requested.connect(func(encounter_id: String) -> void: taken.append(encounter_id))
	var reward := _reward([_drop("a"), _drop("b")], 2)
	list.show_reward(reward, true)
	(_row_node(list, 1).get_node_or_null("%DropAction") as Button).pressed.emit()
	assert_eq(str(picked), '["b"]', "the pressed drop id is what is reported")
	(list.get_node_or_null("%TakeAllButton") as Button).pressed.emit()
	assert_eq(str(taken), '["%s"]' % reward["encounter_id"], "take all names the encounter")


## A row press reports itself in STASH mode too.
##
## The list used to `return` early when `_mode == &"stashed"`, so a `Reclaim` button
## was rendered, enabled, and inert: `act_reclaim` was unreachable and the entire
## world-drop-container overflow branch — the one that tells a player their stash is
## full — had no way to fire. The list does not know what its buttons mean; the
## screen does, by choosing which signal to wire.
func test_a_stashed_row_press_is_reported_too() -> void:
	var list := _list()
	var acted: Array = []
	list.row_action_requested.connect(func(drop_id: String) -> void: acted.append(drop_id))
	var stashed := _drop("a")
	stashed["stashed"] = true
	stashed["stash_id"] = "a"
	list.show_stashes([stashed], true)
	(_row_node(list, 0).get_node_or_null("%DropAction") as Button).pressed.emit()
	assert_eq(str(acted), '["a"]', "a Reclaim press is reported, not swallowed")


## Rebuilding must not destroy the row that is mid-emission.
##
## The old `_build` freed every row and made new ones, so pressing a button freed the
## very node still inside its own `action_requested` emission -- Godot's "Attempted
## to free a locked object", 14 times in a run. Worse, it *masked* the resulting
## script errors, which is how a broken mutation elsewhere in this screen's tests
## stayed green. Rows are pooled and reused, so nothing is freed at all.
func test_a_rebuild_never_frees_the_row_that_is_pressing() -> void:
	var list := _list()
	# An Array, not an int: a GDScript lambda captures a local BY VALUE, so
	# `presses += 1` would bump the lambda's own copy and this test would count zero
	# presses no matter how many happened.
	var presses: Array = []
	list.row_action_requested.connect(func(_drop_id: String) -> void: presses.append(1))
	list.show_reward(_reward([_drop("a"), _drop("b")], 2), true)
	# Press, and let the handler rebuild the list under the emitter's feet.
	(_row_node(list, 0).get_node_or_null("%DropAction") as Button).pressed.emit()
	assert_eq(presses.size(), 1, "the press reached the screen")
	# Now shrink the list: the surplus row must survive as a hidden pooled row.
	list.show_reward(_reward([_drop("a")], 1), true)
	assert_eq(int(list.summary()["row_count"]), 1, "the list shrank")
	# And grow it again: the pooled row comes back rather than a new one appearing.
	list.show_reward(_reward([_drop("a"), _drop("b")], 2), true)
	assert_eq(int(list.summary()["row_count"]), 2, "and grew back")
	(_row_node(list, 1).get_node_or_null("%DropAction") as Button).pressed.emit()
	assert_eq(presses.size(), 2, "a reused row still reports its press")


func test_focus_lands_on_a_live_action() -> void:
	var list := _list()
	list.show_reward(_reward([_drop("a")], 1), true)
	list.focus_initial()
	assert_eq(bool(list.summary()["take_all_enabled"]), true, "there is a live action to land on")


## A drop the world has already settled must not carry a live control.
##
## The screen's gate (`can_pick_up`) answers "can this actor take anything at all", and it
## was the ONLY thing that decided whether a row's button was enabled. So a payload's
## first row kept a live `Pick up` after the very first press had taken that drop, and
## every later press was refused `drop_already_claimed` with an enabled button and no
## sentence explaining it. A control that cannot act must read as dead.
func test_a_drop_that_cannot_be_taken_carries_a_dead_control() -> void:
	var list := _list()
	var parked := _drop("p", 1, false, true)
	list.show_reward(_reward([_drop("a"), _drop("t", 1, true), parked], 1), true)
	var rows := list.summary()["rows"] as Array
	# One row per drop still: nothing is hidden and nothing is discarded.
	assert_eq(int(list.summary()["row_count"]), 3, "every drop of the payload is still listed")
	assert_eq(
		str(list.summary()["row_keys"]), '["a", "t", "p"]', "settled rows follow the live one"
	)
	for row in rows:
		var entry := row as Dictionary
		var live := String(entry["drop_id"]) == "a"
		assert_eq(
			bool(entry["action_enabled"]),
			live,
			"'%s' carries a %s control" % [String(entry["drop_id"]), "live" if live else "dead"]
		)
	assert_eq(
		String((rows[0] as Dictionary)["status"]),
		"pending",
		"and the row the list opens on is one that is still waiting"
	)


## The same rule in the other mode: a parked drop is reclaimable from the world drop
## container, and that is the only place it is.
func test_a_parked_drop_is_live_in_the_stash_list_and_dead_in_the_reward_list() -> void:
	var list := _list()
	var parked := _drop("p", 2)
	parked["stashed"] = true
	parked["claimable"] = false
	parked["stash_id"] = "p"
	list.show_reward(_reward([parked], 0), true)
	assert_eq(
		bool(((list.summary()["rows"] as Array)[0] as Dictionary)["action_enabled"]),
		false,
		"the reward list cannot take a parked drop back"
	)
	list.show_stashes([parked], true)
	var reclaim := (list.summary()["rows"] as Array)[0] as Dictionary
	assert_eq(str(reclaim["action"]), "Reclaim", "the stash list offers the action that works")
	assert_eq(
		bool(reclaim["action_enabled"]),
		true,
		"and it is live, because the world drop container is where it is addressed"
	)
	# And once reclaimed the row is dead there too, rather than offering it again.
	var settled := _drop("p", 2)
	settled["stashed"] = false
	settled["claimed"] = true
	settled["stash_id"] = "p"
	list.show_stashes([settled], true)
	assert_eq(
		bool(((list.summary()["rows"] as Array)[0] as Dictionary)["action_enabled"]),
		false,
		"a reclaimed drop is not offered again"
	)


## Pressing the TOP control repeatedly drains the payload, which is what a player does
## and what the boot probe does. It could not: the first press took the top row's drop,
## the rebuild put that same now-taken drop back on top, and presses two onward were all
## refused, so the pending count fell by exactly one and then stopped moving.
func test_pressing_the_top_control_drains_the_payload() -> void:
	var list := _list()
	var pressed: Array = []
	list.row_action_requested.connect(func(drop_id: String) -> void: pressed.append(drop_id))
	var ids := ["a", "b", "c"]
	var taken := [false, false, false]
	# The screen, stood in for: the press marks that drop taken and the list repaints,
	# which is what `act_pickup` does through `refresh()`.
	#
	# Bounded by `ids.size()`, read once before the loop -- the body never appends to
	# `ids`, so the walk terminates, and the disabled assertion inside it names the
	# failure: a control that goes dead on a drop nobody has taken fails on its first
	# pass rather than running the bound out.
	var passes := 0
	while passes < ids.size():
		passes += 1
		list.show_reward(_reward(_drops(ids, taken), ids.size() - _taken_count(taken)), true)
		var action := _row_node(list, 0).get_node_or_null("%DropAction") as Button
		assert_eq(action.disabled, false, "pass %d: the top control is live" % passes)
		action.pressed.emit()
		assert_eq(pressed.size(), passes, "pass %d: and the press reached the screen" % passes)
		taken[ids.find(String(pressed[pressed.size() - 1]))] = true
	list.show_reward(_reward(_drops(ids, taken), 0), true)
	assert_eq(str(pressed), '["a", "b", "c"]', "every press took the drop that was on top")
	assert_eq(int(list.summary()["pending_count"]), 0, "so nothing is left waiting")


## One drop per id, `taken[index]` deciding whether that drop is already claimed.
func _drops(ids: Array, taken: Array) -> Array:
	var out: Array = []
	for index in ids.size():
		out.append(_drop(String(ids[index]), 1, bool(taken[index])))
	return out


## How many of `taken` are set.
func _taken_count(taken: Array) -> int:
	var count := 0
	for flag in taken:
		if bool(flag):
			count += 1
	return count
