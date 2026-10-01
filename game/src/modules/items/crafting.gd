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
	# Resolve all outputs before mutating inventory so a failure is atomic.
	var resolved: Array[ItemDef] = []
	for output_id in recipe.outputs:
		var def := load_item(output_id)
		if def == null:
			failed.emit(recipe.id, "unknown_output")
			return false
		resolved.append(def)
	for input_id in recipe.inputs:
		inventory.remove(input_id, 1)
	for def in resolved:
		inventory.add(def, 1)
	crafted.emit(recipe.id)
	return true


## Resolve an ItemDef by id. Items live at res://data/items/<category>/<id>.tres,
## where <category> is the item's own category, so the folder cannot be omitted.
static func load_item(item_id: StringName) -> ItemDef:
	for category in ItemCategory.ALL:
		var path := "res://data/items/%s/%s.tres" % [category, item_id]
		if ResourceLoader.exists(path):
			return load(path) as ItemDef
	return null


func time_required() -> float:
	return _time_required
