extends TestCase

## The reusable socket slot row (ADR 0038). It renders one slot's own modifiers
## visibly apart from the socket item seated in it, and it is the only place in
## the socket UI that formats a number.

const ROW_SCENE := "res://src/ui/panels/socket_slot_row.tscn"


func _row() -> SocketSlotRow:
	var row: SocketSlotRow = load(ROW_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(row)
	return row


func _effect(option_id: String, value: float, low: float, high: float) -> Dictionary:
	return {
		"option_id": StringName(option_id),
		"label": option_id.capitalize(),
		"target_type": &"stat",
		"target_id": &"attack_physical",
		"op": &"FLAT",
		"unit": &"magnitude",
		"value": value,
		"value_min": low,
		"value_max": high,
	}


func _slot() -> Dictionary:
	return {
		"index": 0,
		"kind": "offense",
		"imputed": [_effect("socket_hit", 4.0, 1.0, 10.0)],
		"imputed_count": 1,
		"occupied": true,
		"gem_instance_id": "rune_1",
		"gem_def_id": "socket_rune_mortal_offense",
		"gem_display_name": "Crude Offensive Rune",
		"gem_rarity": "common",
		"gem_effects": [_effect("gem_hit", 2.5, 1.0, 10.0)],
		"gem_enchantment": {},
	}


func test_an_empty_row_reports_no_slot() -> void:
	var row := _row()
	row.show_slot({})
	var view := row.summary()
	assert_eq(bool(view["has_slot"]), false, "no slot")
	assert_eq(int(view["index"]), -1, "no index")
	assert_eq(int(view["imputed_count"]), 0, "no slot modifiers")
	assert_eq(String(view["head"]), "", "no header")
	row.free()


func test_a_slot_is_rendered_as_two_distinct_sets_of_modifiers() -> void:
	var row := _row()
	row.show_slot(_slot())
	var view := row.summary()
	assert_eq(bool(view["has_slot"]), true, "the slot is shown")
	assert_eq(int(view["index"]), 0, "its index is reported")
	assert_eq(String(view["kind"]), "offense", "its kind is reported")
	assert_eq(bool(view["occupied"]), true, "its occupancy is reported")
	assert_eq(int(view["imputed_count"]), 1, "the slot's own modifiers")
	assert_eq(int(view["gem_effect_count"]), 1, "the socket item's own modifiers")
	assert_eq(
		int(view["effect_line_count"]),
		int(view["imputed_count"]) + int(view["gem_effect_count"]),
		"both sets are counted separately"
	)
	assert_eq(
		(view["imputed_lines"] as Array) == (view["gem_lines"] as Array),
		false,
		"the two sets are never the same rows"
	)
	assert_eq(String(view["gem_display_name"]), "Crude Offensive Rune", "the socket item is named")
	assert_eq(String(view["gem_enchantment_line"]), "", "and carries no enchantment of its own")
	row.free()


func test_the_panel_owns_every_number_a_slot_shows() -> void:
	var row := _row()
	row.show_slot(_slot())
	var view := row.summary()
	var slot_line := String((view["imputed_lines"] as Array)[0])
	assert_eq(slot_line.contains("4.00"), true, "the realized value is formatted here")
	assert_eq(slot_line.contains("1.00 - 10.00"), true, "and its window with it")
	assert_eq(String(view["head"]).contains("1"), true, "the slot number is formatted here")
	row.free()


func test_a_gem_enchantment_is_shown_apart_from_the_gem_itself() -> void:
	var slot := _slot()
	slot["gem_enchantment"] = _effect("etched_hit", 1.5, 1.0, 10.0)
	var row := _row()
	row.show_slot(slot)
	var view := row.summary()
	assert_ne(String(view["gem_enchantment_line"]), "", "the gem's own treatment is shown")
	assert_eq(
		(view["gem_lines"] as Array).has(String(view["gem_enchantment_line"])),
		false,
		"and is not folded into the gem's own modifiers"
	)
	assert_eq(
		int(view["effect_line_count"]),
		int(view["imputed_count"]) + int(view["gem_effect_count"]) + 1,
		"the treatment counts as its own row"
	)
	row.free()


func test_showing_an_empty_slot_clears_the_previous_one() -> void:
	var row := _row()
	row.show_slot(_slot())
	assert_eq(int(row.summary()["imputed_count"]), 1, "a slot is shown")
	row.show_slot({})
	assert_eq(int(row.summary()["imputed_count"]), 0, "clearing leaves nothing stale behind")
	row.free()
