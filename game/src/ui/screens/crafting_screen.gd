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

## The three things a recipe can be to this screen. `CRAFT_UNKNOWN` exists so a
## refusal is never painted as an offer -- see `_craft_state`.
const CRAFT_READY := &"ready"
const CRAFT_SHORT := &"short"
const CRAFT_UNKNOWN := &"unknown"

var _recipes: Array = []
var _selected: StringName = &""
var _list: VBoxContainer = null
var _detail: Label = null
var _status: Label = null
## id -> {quantity, name}, memoised for one refresh. Cleared in `_refresh_view`
## because it is a snapshot of the actor's inventory, and a stale name or a stale
## held count on the crafting screen is a wrong figure.
var _stock_cache: Dictionary = {}
## The clock seam (ADR 0167, BL-0815): the composition root's craft verb, so a craft pays
## world time. Null on a screen built without one (a headless driver), where the craft
## falls back to the facade and is free — the unwired path, never the production one.
var _bridge: CraftingBridge = null


## Install the composition root's craft seam. A screen that never receives one still lists
## and crafts, but does so through `ItemsApi` directly — which is the free path this bridge
## exists to replace in production.
func set_bridge(bridge: CraftingBridge) -> void:
	_bridge = bridge


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
##
## Strictly "could": a recipe whose state is UNKNOWN is not reported craftable. The
## screen has no actor until `setup` runs, and an empty missing-list used to read as
## "nothing missing" -- so a screen that had not been given an actor advertised
## every recipe as craftable. A player who pressed one got a refusal, having been
## told it would work.
func craftable_ids() -> Array[String]:
	var out: Array[String] = []
	for recipe in _recipes:
		if _craft_state(StringName(recipe.get("id", ""))) == CRAFT_READY:
			out.append(String(recipe.get("id", "")))
	return out


## Whether a recipe can be crafted *right now*, as opposed to being merely offered.
## False while the state is unknown.
func is_craftable(recipe_id: StringName) -> bool:
	return _craft_state(recipe_id) == CRAFT_READY


## One of `CRAFT_READY`, `CRAFT_SHORT`, `CRAFT_UNKNOWN`.
##
## Three states, not two. The screen's whole job is to let a player decide whether
## to spend materials, so "I cannot tell" and "yes, go ahead" must not render the
## same. `_missing_of` alone cannot express the difference: with no actor it has no
## inventory to read and returned an empty list, which is the same value a
## fully-stocked recipe returns.
func _craft_state(recipe_id: StringName) -> StringName:
	if _actor == null:
		return CRAFT_UNKNOWN
	var recipe := _recipe(recipe_id)
	if recipe.is_empty():
		return CRAFT_UNKNOWN
	return CRAFT_READY if _missing_of(recipe_id).is_empty() else CRAFT_SHORT


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
	# A craft is an ACTION, so it pays world time (ADR 0167, BL-0815). The clock is `app/`'s
	# and this screen may not name it, so the composition root's craft verb arrives through
	# the bridge; the screen asks and never owns time. A screen built without a bridge (a
	# headless driver) falls back to the facade and is free — the unwired path, which the
	# composition root replaces on every crafting route.
	if _bridge != null and _bridge.has(&"craft"):
		if not bool(_bridge.call_action(&"craft", [resource]).get("ok", false)):
			set_message("Crafting failed", TONE_ERROR)
			refresh()
			return false
	elif not ItemsApi.craft(resource, ItemsApi.inventory(_actor)):
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
	_stock_cache.clear()
	_fill_rows()
	if _detail != null:
		_detail.text = L.t(_detail_text())
	if _status != null:
		_status.text = L.t(_message)


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
		var label := String(recipe.get("display_name", ""))
		row.text = L.t(label if not label.is_empty() else String(recipe_id))
		row.disabled = false
		row.tooltip_text = L.t(_row_hint(recipe_id))
		row.button_pressed = recipe_id == _selected
		index += 1
	# Leftover rows from a longer previous offer are hidden, never destroyed.
	while index < capacity:
		var extra := _list.get_child(index) as Button
		if extra != null:
			extra.visible = false
		index += 1


## What a row's tooltip says about its inputs. The three states are worded apart on
## purpose: a row that said "Ready" while holding nothing, or while the screen could
## not read the inventory, told the player to spend materials on a refusal.
func _row_hint(recipe_id: StringName) -> String:
	match _craft_state(recipe_id):
		CRAFT_READY:
			return L.t("LOC_UI_SCREENS_20C7C5522F")
		CRAFT_SHORT:
			var missing := _missing_of(recipe_id)
			return L.t("LOC_UI_SCREENS_B4BAA63FDA") % ", ".join(_display_names(missing))
		_:
			return L.t("LOC_UI_SCREENS_1BADD5A415")


## The selected recipe's inputs and outputs, and what is missing, in one block.
## The panel owns the wording; the screen passes ids and counts.
func _detail_text() -> String:
	var recipe := _recipe(_selected)
	if recipe.is_empty():
		return L.t("LOC_UI_SCREENS_975C3AAE95")
	var parts: Array[String] = []
	parts.append("Station: %s" % recipe.get("station", ""))
	parts.append("Makes: %s" % ", ".join(_display_names(recipe.get("outputs", []))))
	parts.append("Costs: %s" % ", ".join(_input_text(recipe)))
	match _craft_state(_selected):
		CRAFT_READY:
			parts.append("Ready to craft")
		CRAFT_SHORT:
			parts.append("Missing: %s" % ", ".join(_display_names(_missing_of(_selected))))
		_:
			# No actor, so no inventory was read. Saying "Ready to craft" here is the
			# defect this branch exists to prevent.
			parts.append("Inputs unknown")
	return "\n".join(parts)


## "qi_refining_pill (3 held)" per input.
##
## The held count is what makes a craft decidable, so this text is the reason the
## screen exists. It MUST survive having no actor: `ItemsApi.inventory` dereferences
## the actor, so calling it with null raised a script error inside the module on
## every refresh of an actor-less screen -- the exact "refusal renders as a crash"
## branch the standard forbids. With no actor the count is unknowable, so the row
## says "held unknown" rather than claiming zero of everything, which would render
## every recipe as craftable.
func _input_text(recipe: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var stock := _stock()
	for input_id in recipe.get("inputs", []):
		var id := StringName(input_id)
		if not stock.has(id):
			out.append("%s (held unknown)" % _display_name(id))
		else:
			out.append("%s (%d held)" % [_display_name(id), int(stock[id].get("quantity", 0))])
	return out


## id -> {quantity, name} for every item any offered recipe names.
##
## Empty when there is no actor, and that emptiness is the signal: it is how
## `_input_text` tells "held unknown" from "held none", so a refusal can never be
## rendered as an offer.
##
## The name lookup goes through the inventory the facade already hands this screen,
## via `definition_of`, with a `Resource`-typed parameter on purpose: naming
## `ItemDef` or `Crafting` from `ui/` is a module reference the arch gate rejects,
## and adding a resolver to `ItemsApi` is impossible anyway -- it is at its
## 12-method cap. Resolving here is what stops the detail pane printing
## `qi_refining_pill` directly beneath a row that reads "Qi Refining Pill".
func _stock() -> Dictionary:
	if not _stock_cache.is_empty():
		return _stock_cache
	if _actor == null:
		return _stock_cache
	var inv := ItemsApi.inventory(_actor)
	if inv == null:
		return _stock_cache
	var held: Dictionary = {}
	for batch in inv.stacks():
		var held_id := StringName(batch.def_id)
		held[held_id] = int(held.get(held_id, 0)) + int(batch.quantity)
	for id in _all_recipe_items():
		var key := StringName(id)
		_stock_cache[key] = {
			"quantity": int(held.get(key, 0)),
			"name": _definition_name(inv.definition_of(key)),
		}
	return _stock_cache


func _definition_name(def: Resource) -> String:
	if def == null:
		return ""
	return String(def.get("display_name"))


## Every item id any offered recipe names, so a cost the player has never held is
## still resolved to a readable name rather than to its id.
func _all_recipe_items() -> Array:
	var out: Array = []
	for recipe in _recipes:
		for key in ["inputs", "outputs"]:
			for id in recipe.get(key, []):
				if not out.has(id):
					out.append(id)
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
					"craftable": is_craftable(StringName(recipe.get("id", ""))),
					"craft_state": String(_craft_state(StringName(recipe.get("id", "")))),
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
## refused. An empty list is what makes a recipe craftable -- but ONLY with an
## actor; `_craft_state` is what callers should read, because this returns `[]` for
## an unknown state too.
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


## Readable names for a list of item ids, joined by the caller.
##
## Takes a plain `Array` on purpose. `recipe.get("outputs", [])` is untyped, so an
## `Array[StringName]` parameter raised "Invalid type ... does not have the same
## element type" every time the detail pane was built -- a runtime type error in the
## one code path that renders what a craft will make.
func _display_names(ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		out.append(_display_name(StringName(id)))
	return out


## The authored display name when one resolves, else the id.
##
## `ItemsApi` is at its 12-method cap and publishes no resolver, so the lookup goes
## through the inventory the screen already holds rather than through a new verb.
## The id is the fallback because it is honest: a row that shows `qi_refining_pill`
## is at least truthful about not knowing the name, where an empty cell would read
## as an item with no name at all.
func _display_name(item_id: StringName) -> String:
	var entry: Dictionary = _stock().get(item_id, {})
	var name := String(entry.get("name", ""))
	return name if not name.is_empty() else String(item_id)


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
