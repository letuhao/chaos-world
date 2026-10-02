class_name CraftingScreen
extends UiScreen

## Crafting screen (ADR 0043). The only place `ItemsApi.craft` is reachable from
## the UI program: every realm pill and elixir is produced by a recipe, so without
## this a player can be told which item a gate wants and have no way to make it
## (DEF-0057).
##
## Recipes are *pushed in*, not discovered. `ItemsApi` is at its 12-method cap and
## publishes no catalog, so deciding how the 4712 authored recipes are listed is a
## gameplay call (DEF-0067). This screen crafts whatever it is given, which keeps
## the UI half of that work done and unblocked whichever route is chosen.
##
## Contract: `summary()` is the testable surface.

var _recipes: Array = []
var _selected: StringName = &""
var _list: VBoxContainer = null
var _detail: Label = null
var _status: Label = null


## Everything this screen displays. Primitives only; `{}` with no actor.
func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	return {
		"recipe_count": _recipes.size(),
		"recipes": _recipe_rows(),
		"selected": String(_selected),
		"craftable": craftable_ids(),
		"inputs": _inputs_of(_selected),
		"outputs": _outputs_of(_selected),
		"missing": _missing_of(_selected),
	}


## Publish the recipes this screen offers, as dictionaries with `id`, `station`,
## `inputs` and `outputs` keys. A caller holding a `RecipeDef` converts it first:
## the screen cannot name that type, because it belongs to the `items` module.
## Safe to call again; the selection is kept if still offered, dropped otherwise.
func set_recipes(recipes: Array) -> void:
	_bind_nodes()
	_recipes.clear()
	for recipe in recipes:
		if recipe is Dictionary and not recipe.is_empty():
			_recipes.append(recipe)
	if not _has(_selected):
		_selected = _first_id()
	refresh()


func _first_id() -> StringName:
	if _recipes.is_empty():
		return &""
	return StringName(_recipes[0].get("id", ""))


## Select a recipe by id and repaint. False when the id is not on offer, so a
## caller can tell a typo from a missing recipe.
func select_recipe(recipe_id: StringName) -> bool:
	_bind_nodes()
	if not _has(recipe_id):
		return false
	_selected = recipe_id
	refresh()
	return true


## Which of the offered recipes the actor could craft right now.
func craftable_ids() -> Array[String]:
	var out: Array[String] = []
	for recipe in _recipes:
		if _missing_of(StringName(recipe.get("id", ""))).is_empty():
			out.append(String(recipe.get("id", "")))
	return out


## Craft the selected recipe through the facade. Returns false and says why when
## the inputs are short; the recipe is never consumed on a refusal.
func act_craft_selected() -> bool:
	_bind_nodes()
	if _actor == null:
		set_message("No actor", TONE_ERROR)
		refresh()
		return false
	var recipe := _recipe(_selected)
	if recipe.is_empty():
		set_message("Select a recipe first", TONE_ERROR)
		refresh()
		return false
	var missing := _missing_of(_selected)
	if not missing.is_empty():
		set_message("Missing %s" % ", ".join(missing), TONE_ERROR)
		refresh()
		return false
	# The facade takes a `RecipeDef`, which `ui/` may not name. So each entry is
	# pushed as a plain dictionary of readable fields plus, under `resource`, the
	# object the facade will accept. A caller that supplies only the readable
	# fields gets a screen that lists and explains the recipe but refuses to
	# craft, rather than one reaching past the facade to build a def
	# (ADR 0043, DEF-0067).
	var resource = recipe.get("resource")
	if resource == null:
		set_message("No craftable recipe resource supplied", TONE_ERROR)
		refresh()
		return false
	if not ItemsApi.craft(resource, ItemsApi.inventory(_actor)):
		set_message("Crafting failed", TONE_ERROR)
		refresh()
		return false
	set_message("Crafted %s" % _first_output(_selected), TONE_OK)
	refresh()
	return true


## Craft a named recipe directly, for a caller that knows what it wants without
## selecting first.
func act_craft(recipe_id: StringName) -> bool:
	if not select_recipe(recipe_id):
		set_message("Unknown recipe %s" % recipe_id, TONE_ERROR)
		refresh()
		return false
	return act_craft_selected()


## Crafting is a deliberate act, so it lands on the first recipe rather than on a
## movement control.
func focus_initial() -> void:
	_bind_nodes()
	if _recipes.is_empty():
		return
	var first := _recipe(_recipes[0].id)
	if first != null:
		_selected = first.id
	_focus_target = "CraftButton"


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _list != null:
		return
	_list = get_node_or_null("%RecipeList") as VBoxContainer
	_detail = get_node_or_null("%DetailLabel") as Label
	_status = get_node_or_null("%StatusLabel") as Label
	var craft_button := get_node_or_null("%CraftButton") as Button
	if craft_button != null and not craft_button.pressed.is_connected(act_craft_selected):
		craft_button.pressed.connect(act_craft_selected)
	if _list == null:
		return
	for child in _list.get_children():
		var button := child as Button
		if button != null and not button.pressed.is_connected(_on_row_pressed):
			button.pressed.connect(_on_row_pressed.bind(button))


## A row press selects the recipe it was composed for. The row's position in the
## list is its index into the offered recipes, so no per-row binding is needed.
func _on_row_pressed(button: Button) -> void:
	var index := 0
	for child in _list.get_children():
		if child == button:
			break
		index += 1
	if index < _recipes.size():
		_selected = StringName(_recipes[index].get("id", ""))
		refresh()


func _refresh_view() -> void:
	_bind_nodes()
	_fill_rows()
	if _detail != null:
		_detail.text = _detail_text()
	if _status != null:
		_status.text = _message


## One row per offered recipe, composed in the scene and reused across refreshes.
func _fill_rows() -> void:
	if _list == null:
		return
	var capacity := _list.get_child_count()
	var index := 0
	while index < capacity and index < _recipes.size():
		var row := _list.get_child(index) as Button
		if row == null:
			index += 1
			continue
		var recipe: Dictionary = _recipes[index]
		var recipe_id := StringName(recipe.get("id", ""))
		var missing := _missing_of(recipe_id)
		var label := String(recipe.get("display_name", ""))
		row.text = label if not label.is_empty() else String(recipe_id)
		row.disabled = false
		row.tooltip_text = "Missing %s" % ", ".join(missing) if not missing.is_empty() else "Ready"
		row.button_pressed = recipe_id == _selected
		index += 1
	# Leftover rows from a longer previous offer are hidden, never destroyed.
	while index < capacity:
		var extra := _list.get_child(index) as Button
		if extra != null:
			extra.visible = false
		index += 1


## The selected recipe's inputs and outputs, and what is missing, in one block.
## The panel owns the wording; the screen passes ids and counts.
func _detail_text() -> String:
	var recipe := _recipe(_selected)
	if recipe.is_empty():
		return "No recipe selected"
	var parts: Array[String] = []
	parts.append("Station: %s" % recipe.get("station", ""))
	parts.append("Makes: %s" % ", ".join(_display_names(recipe.get("outputs", []))))
	parts.append("Costs: %s" % ", ".join(_input_text(recipe)))
	var missing := _missing_of(_selected)
	if missing.is_empty():
		parts.append("Ready to craft")
	else:
		parts.append("Missing: %s" % ", ".join(missing))
	return "\n".join(parts)


func _input_text(recipe: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var inv := ItemsApi.inventory(_actor)
	for input_id in recipe.get("inputs", []):
		var held := 0 if inv == null else inv.count(input_id)
		out.append("%s (%d held)" % [_display_name(input_id), held])
	return out


func _recipe_rows() -> Array:
	var recipes: Array = []
	for recipe in _recipes:
		(
			recipes
			. append(
				{
					"id": String(recipe.get("id", "")),
					"station": String(recipe.get("station", "")),
					"inputs": _id_list(recipe.get("inputs", [])),
					"outputs": _id_list(recipe.get("outputs", [])),
					"selected": StringName(recipe.get("id", "")) == _selected,
					"craftable": _missing_of(StringName(recipe.get("id", ""))).is_empty(),
				}
			)
		)
	return recipes


func _inputs_of(recipe_id: StringName) -> Array:
	var recipe := _recipe(recipe_id)
	return [] if recipe.is_empty() else _id_list(recipe.get("inputs", []))


func _outputs_of(recipe_id: StringName) -> Array:
	var recipe := _recipe(recipe_id)
	return [] if recipe.is_empty() else _id_list(recipe.get("outputs", []))


## The input ids the actor is short of, which is the whole reason a craft is
## refused. An empty list is what makes a recipe craftable.
func _missing_of(recipe_id: StringName) -> Array[String]:
	var recipe := _recipe(recipe_id)
	if recipe.is_empty() or _actor == null:
		return []
	var inputs: Array = recipe.get("inputs", [])
	var inv := ItemsApi.inventory(_actor)
	if inv == null:
		return _id_list(inputs)
	var out: Array[String] = []
	for input_id in inputs:
		var held := inv.count(input_id)
		if held <= 0:
			out.append(String(input_id))
	return out


func _id_list(ids: Array[StringName]) -> Array:
	var out: Array = []
	for id in ids:
		out.append(String(id))
	return out


## Prefer the definition's display name, because an item id is not something a
## player reads. `ItemsApi` is at its 12-method cap and publishes no resolver, so
## this stays on the id; a composition root may push a naming callable if a screen
## should show friendly names (ADR 0043).
func _display_names(ids: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		out.append(String(id))
	return out


func _display_name(item_id: StringName) -> String:
	return String(item_id)


func _first_output(recipe_id: StringName) -> String:
	var recipe := _recipe(recipe_id)
	if recipe == null:
		return String(recipe_id)
	var outputs: Array = recipe.get("outputs", [])
	return String(outputs[0]) if not outputs.is_empty() else String(recipe_id)


## Recipes are held as plain dictionaries, not as `RecipeDef`: that type belongs to
## the `items` module and `ui/` may only reach a module through its facade. The
## composition root converts, or pushes the resource itself and this reads the
## same field names.
func _recipe(recipe_id: StringName) -> Dictionary:
	for recipe in _recipes:
		if StringName(recipe.get("id", "")) == recipe_id:
			return recipe
	return {}


func _has(recipe_id: StringName) -> bool:
	return not _recipe(recipe_id).is_empty()
