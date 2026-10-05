class_name RecipeCatalog
extends RefCounted

## The recipes the crafting route offers (ADR 0043, DEF-0067).
##
## `ItemsApi` is at its 12-method cap and publishes no recipe catalog, so *which*
## recipes are listed is a composition-root decision. This one is data-driven and
## needs no curation: a recipe is offered exactly when the hero already holds every
## one of its inputs. The list is therefore the set of crafts that would succeed
## right now, it grows with the inventory instead of being capped at an arbitrary
## number, and no rule about what a player *should* be able to make is invented
## here.
##
## The screen receives plain dictionaries carrying the `RecipeDef` under
## `resource`, because `ui/` may not name an items type (ADR 0043).
##
## Cost: reading all ~4600 authored recipes takes a few seconds, paid once on the
## first time the crafting route is opened and cached for the rest of the process.
## It is the price of there being no catalog API to ask.

const RECIPE_ROOT := "res://data/recipes"
## Enough rows to fill the screen's list several times over. The screen renders at
## most what it has rows for, so a larger cap would only cost time.
const MAX_OFFERED := 64

## Scanned once per process. `load()` is itself cached by the resource loader, so
## re-opening the crafting screen is a directory walk and a handful of held-item
## checks rather than a full re-read of the content tree.
static var _index: Array[Dictionary] = []
static var _scanned: bool = false


## The recipes this actor can craft now, as plain dictionaries with a `resource`
## entry the facade accepts. Empty when the hero holds no recipe input at all,
## which is reported rather than padded with something uncraftable.
static func offerable(actor: Actor) -> Array[Dictionary]:
	if actor == null:
		return []
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return []
	_ensure_index()
	var out: Array[Dictionary] = []
	for row in _index:
		if _holds_all(inventory, row.get("inputs", [])):
			out.append(row)
		if out.size() >= MAX_OFFERED:
			break
	return out


## How many recipes the content tree holds. Reported so a caller can tell "nothing
## is craftable yet" apart from "the tree is empty".
static func scanned_count() -> int:
	_ensure_index()
	return _index.size()


static func _holds_all(inventory: Inventory, inputs: Array) -> bool:
	if inputs.is_empty():
		return false
	for input_id in inputs:
		if inventory.count(StringName(input_id)) <= 0:
			return false
	return true


static func _ensure_index() -> void:
	if _scanned:
		return
	_scanned = true
	var dir := DirAccess.open(RECIPE_ROOT)
	if dir == null:
		push_error("RecipeCatalog: no recipe tree at %s" % RECIPE_ROOT)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var row := _read("%s/%s" % [RECIPE_ROOT, file_name])
			if not row.is_empty():
				_index.append(row)
		file_name = dir.get_next()
	dir.list_dir_end()


## One recipe as the screen wants it. A resource that fails to load is dropped, so a
## single bad file cannot empty the whole list.
##
## `inputs` and `outputs` are `Array[StringName]`, not `Array[String]`: that is the
## shape `CraftingScreen` declares for them, and a screen's typed parameters are a
## contract rather than a hint.
static func _read(path: String) -> Dictionary:
	var recipe := load(path) as RecipeDef
	if recipe == null or recipe.id == &"" or recipe.inputs.is_empty():
		return {}
	var inputs: Array[StringName] = recipe.inputs.duplicate()
	var outputs: Array[StringName] = recipe.outputs.duplicate()
	return {
		"id": String(recipe.id),
		"display_name": recipe.display_name,
		"station": String(recipe.station),
		"inputs": inputs,
		"outputs": outputs,
		"resource": recipe,
	}
