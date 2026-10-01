class_name Crafting
extends RefCounted

## Crafting system (DEF-0021): consumes inputs, produces outputs (ADR 0007/0008).
## Station + time gating: recipes require a station; crafting takes time.

signal crafted(recipe_id: StringName)
signal failed(recipe_id: StringName, reason: String)

var _station: StringName = &""
var _time_required: float = 0.0


func _init(p_station: StringName = &"", p_time_required: float = 0.0) -> void:
	_station = p_station
	_time_required = p_time_required


func can_craft(recipe: RecipeDef, inventory: Inventory) -> bool:
	if recipe.station != _station:
		return false
	for input_id in recipe.inputs:
		if not inventory.has(input_id):
			return false
	return true


func craft(recipe: RecipeDef, inventory: Inventory) -> bool:
	if not can_craft(recipe, inventory):
		failed.emit(recipe.id, "missing_inputs_or_station")
		return false
	for input_id in recipe.inputs:
		inventory.remove(input_id, 1)
	for output_id in recipe.outputs:
		var def := load("res://data/items/%s.tres" % output_id)
		if def is ItemDef:
			inventory.add(def, 1)
	crafted.emit(recipe.id)
	return true


func time_required() -> float:
	return _time_required
