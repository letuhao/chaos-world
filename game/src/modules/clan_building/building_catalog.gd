class_name BuildingCatalog
extends RefCounted

## The authored building content tree, loaded once and cached.
##
## Building definitions live in `res://data/clan_buildings/` and are ordinary
## `.tres` resources carrying a `script_class`, loaded the same way
## `ClanCatalog` loads its tree.

const BUILDINGS_ROOT := "res://data/clan_buildings"
const BUILDING_SCRIPT_CLASS := "BuildingDef"
const BASE_OWNER := "base"

static var shared: BuildingCatalog = null

static var _overlay_stack: Array = []

var _buildings: Dictionary = {}
var _loaded: bool = false


static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


func _merge_stack() -> Array:
	var stack: Array = [
		{
			"dir": BUILDINGS_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": "id",
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), BUILDING_SCRIPT_CLASS, "id")


static func instance() -> BuildingCatalog:
	if shared == null:
		shared = BuildingCatalog.new()
	return shared


## Every authored building id, canonically ordered.
func building_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _buildings.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One building definition, or null when the id is unknown.
func building_definition(building_id: StringName) -> BuildingDef:
	_ensure_loaded()
	return _buildings.get(String(building_id))


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("BuildingCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as BuildingDef
		if def != null and def.id != &"":
			_buildings[String(def.id)] = def
