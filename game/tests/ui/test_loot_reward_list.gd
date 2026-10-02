extends TestCase

## The loot reward list: one row per drop, every number and every refusal word
## owned by the panel, and the world drop container rendered through the same rows.

const LIST_SCENE := "res://src/ui/panels/loot_reward_list.tscn"


func _list() -> LootRewardList:
	var scene: PackedScene = load(LIST_SCENE)
	assert_ne(scene, null, "the reward list scene loads")
	var list := scene.instantiate() as LootRewardList
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
	list.pickup_requested.connect(func(drop_id: String) -> void: picked.append(drop_id))
	list.take_all_requested.connect(func(encounter_id: String) -> void: taken.append(encounter_id))
	var reward := _reward([_drop("a"), _drop("b")], 2)
	list.show_reward(reward, true)
	(_row_node(list, 1).get_node_or_null("%DropAction") as Button).pressed.emit()
	assert_eq(str(picked), '["b"]', "the pressed drop id is what is reported")
	(list.get_node_or_null("%TakeAllButton") as Button).pressed.emit()
	assert_eq(str(taken), '["%s"]' % reward["encounter_id"], "take all names the encounter")


func test_focus_lands_on_a_live_action() -> void:
	var list := _list()
	list.show_reward(_reward([_drop("a")], 1), true)
	list.focus_initial()
	assert_eq(bool(list.summary()["take_all_enabled"]), true, "there is a live action to land on")
