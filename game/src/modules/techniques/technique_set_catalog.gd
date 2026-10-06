class_name TechniqueSetCatalog
extends RefCounted

## The authored technique-set content tree, loaded once and cached.
##
## Set definitions live in `res://data/techniques/sets/` as ordinary `.tres`
## `TechniqueSet` resources. The module is its own content namespace, exactly
## like the techniques module and the sets module: a technique set is content
## this module owns, so a lookup here never guesses and never reaches into a
## sibling's tree.
##
## Resolution is by id only. The authored `id` field is the save key, so a
## file whose id disagrees with its filename is resolved by the id the save
## actually stored, and a renamed file with an unchanged id keeps working.

const SETS_ROOT := "res://data/techniques/sets"
const SET_SCRIPT_CLASS := "TechniqueSet"
const SET_ID_FIELD := "id"
const BASE_OWNER := "base"

static var shared: TechniqueSetCatalog = null

## Overlay stack for the technique-set family. Empty means "not wired yet":
## `_ensure_loaded` merges only the authored SETS_ROOT. When set, the overlay
## roots merge AFTER the base root so mod content is visible, with the
## declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _sets: Dictionary = {}
var _loaded: bool = false


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides, id_field}`. Later rows overlay earlier ones; an id
## collision needs a declared override on the LATER root or the merge fails
## loudly.
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


## The merge stack: the base root as a base-owned row, then the overlay rows
## in order.
func _merge_stack() -> Array:
	var stack: Array = [
		{
			"dir": SETS_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": SET_ID_FIELD,
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay. Returns
## CatalogOverlay.merge's dictionary unchanged: `{ok, reason, detail, merged,
## paths, owners}`.
func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), SET_SCRIPT_CLASS, SET_ID_FIELD)


static func instance() -> TechniqueSetCatalog:
	if shared == null:
		shared = TechniqueSetCatalog.new()
	return shared


## Every authored set id, canonically ordered.
func set_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _sets.keys():
		out.append(StringName(key))
	out.sort()
	return out


## The definition behind a set id, or null.
func set_definition(set_id: StringName) -> TechniqueSet:
	_ensure_loaded()
	return _sets.get(String(set_id))


## Register a definition in code, for a caller that composes sets rather than
## loading them from the content tree. Later registration wins, so a test or a
## quest reward can override an authored row without touching the file.
func register(set_def: TechniqueSet) -> void:
	if set_def == null or set_def.id == &"":
		return
	_sets[String(set_def.id)] = set_def


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("TechniqueSetCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as TechniqueSet
		if def != null and def.id != &"":
			_sets[String(def.id)] = def
