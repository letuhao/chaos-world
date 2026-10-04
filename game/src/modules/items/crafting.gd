class_name Crafting
extends RefCounted

## Crafting system (DEF-0021): consumes inputs, produces outputs (ADR 0007/0008).
## Station + time gating: recipes require a station; crafting takes time.
## Material `craft_potency` / `craft_yield` properties are the real consumer of the
## crafted activation channel (ADR 0028): inputs raise output quality and can
## yield an extra unit.

signal crafted(recipe_id: StringName)
signal failed(recipe_id: StringName, reason: String)

## Extra-output chance from input potency, capped so potency cannot run away.
const MAX_EXTRA_YIELD_CHANCE := 0.5
## Roots that hold authored item definitions. A feature module that owns its own
## item namespace adds a root here, so one stable-id resolver serves the whole
## game: inventory, crafting, the generator and loot all agree (ADR 0007).
const ITEM_ROOTS: Array[String] = [
	"res://data/items",
	"res://data/sets/items",
	"res://data/socket",
]

## Overlay stack for the item family (ADR 0184 §5). Empty means "not wired
## yet": `resolve` keeps its exact pre-overlay scan and nothing here runs. The
## default stack is the authored ITEM_ROOTS as base-owned rows with no declared
## overrides, which merges to the same id set the scan finds — the pilot's
## byte-identical guarantee, pinned in this module's test suite.
static var _overlay_stack: Array = []
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


## Deterministic craft: input potency is read, but no random extra yield is
## rolled. A caller that wants the extra-output roll passes its own stream
## through `craft_with`, so a plain craft never depends on the global RNG.
func craft(recipe: RecipeDef, inventory: Inventory) -> bool:
	return craft_with(null, recipe, inventory) == OK


## Transactional craft. Resolves outputs and rolls extra yield *before* mutating
## the inventory, so an unknown output or a full inventory consumes nothing.
func craft_with(rng: RandomNumberGenerator, recipe: RecipeDef, inventory: Inventory) -> Error:
	if not can_craft(recipe, inventory):
		failed.emit(recipe.id, "missing_inputs_or_station")
		return ERR_DOES_NOT_EXIST
	var resolved: Array[ItemDef] = []
	for output_id in recipe.outputs:
		var def := resolve(output_id)
		if def == null:
			failed.emit(recipe.id, "unknown_output")
			return ERR_FILE_NOT_FOUND
		resolved.append(def)
	var potency := _input_potency(recipe)
	var extra := _extra_yield(potency, rng)
	# Confirm every produced unit fits before consuming anything.
	if not _fits(inventory, resolved, extra):
		failed.emit(recipe.id, "inventory_full")
		return ERR_OUT_OF_MEMORY
	for input_id in recipe.inputs:
		inventory.remove(input_id, 1)
	for def in resolved:
		inventory.add(def, 1)
	if extra > 0 and not resolved.is_empty():
		inventory.add(resolved[0], extra)
	crafted.emit(recipe.id)
	return OK


## Crafting potency contributed by the recipe's inputs. Rolled materials raise
## it, so a better roll is a materially better craft input.
static func _input_potency(recipe: RecipeDef) -> float:
	var total := 0.0
	for input_id in recipe.inputs:
		var def := resolve(input_id)
		if def == null:
			continue
		total += ItemEffects.property_value(ItemEffects.resolve(def), OptionTarget.CRAFT_POTENCY)
	return total


## Extra output chance from total input potency, capped so potency cannot run
## away. Bounded policy shared with the audit, never a UI-only check.
static func _extra_yield(potency: float, rng: RandomNumberGenerator) -> int:
	if rng == null:
		return 0
	var chance := clampf(potency * 0.01, 0.0, MAX_EXTRA_YIELD_CHANCE)
	return 1 if rng.randf() < chance else 0


## Resolve an ItemDef by id from the item content trees. Supports the nested
## category layout and rejects ambiguous ids rather than guessing.
static func resolve(item_id: StringName) -> ItemDef:
	if item_id == &"":
		return null
	for root in ITEM_ROOTS:
		var direct := "%s/%s/%s.tres" % [root, _category_of(item_id), item_id]
		if ResourceLoader.exists(direct):
			return load(direct) as ItemDef
	for root in ITEM_ROOTS:
		var found := _scan(root, item_id)
		if found.size() == 1:
			return load(found[0]) as ItemDef
	return null


static func _category_of(item_id: StringName) -> String:
	for category in ItemCategory.ALL:
		if String(item_id).begins_with(String(category).substr(0, 1)):
			return String(category)
	return String(ItemCategory.MISC)


static func _scan(root: String, item_id: StringName) -> Array[String]:
	var wanted := String(item_id) + ".tres"
	var out: Array[String] = []
	for path in ContentScan.files_under(root):
		if path.get_file() == wanted:
			out.append(path)
	return out


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides}`. Later rows overlay earlier ones; an id collision needs
## a declared override on the LATER root or the merge fails loudly.
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


## The stack `overlay_merge` walks: the configured one, or the authored roots.
static func overlay_roots() -> Array:
	if _overlay_stack.is_empty():
		var rows: Array = []
		for root in ITEM_ROOTS:
			rows.append({"dir": root, "owner": "base", "declared_overrides": []})
		return rows
	return _overlay_stack


## Merge the family's overlay stack into one id-keyed catalog (ADR 0184).
## Returns CatalogOverlay.merge's dictionary unchanged: `{ok, reason, detail,
## merged, paths, owners}`.
static func overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(overlay_roots(), "ItemDef")


## Resolve one ItemDef through the overlay merge. Null when the id is absent;
## a stack with an undeclared collision pushes the merge's named detail and
## returns null — never a silent overwrite.
static func resolve_overlay(item_id: StringName) -> ItemDef:
	var merged := overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("Crafting: %s" % String(merged.get("detail", "")))
		return null
	var path := String(merged["paths"].get(String(item_id), ""))
	if path == "":
		return null
	return load(path) as ItemDef


static func load_item(item_id: StringName) -> ItemDef:
	return resolve(item_id)


func _fits(inventory: Inventory, outputs: Array[ItemDef], extra: int) -> bool:
	var probe := inventory.snapshot()
	for def in outputs:
		if probe.add(def, 1) > 0:
			return false
	if extra > 0 and not outputs.is_empty() and probe.add(outputs[0], extra) > 0:
		return false
	return true


func time_required() -> float:
	return _time_required
