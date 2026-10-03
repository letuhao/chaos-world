class_name TechniqueCatalog
extends RefCounted

## The authored technique content tree, loaded once and cached.
##
## Definitions live in `res://data/techniques/` as ordinary `.tres` `TechniqueDef`
## resources. The module is its own content namespace, exactly like the sets module
## and the socket module: a technique is content this module owns, so a lookup here
## never guesses and never reaches into a sibling's tree.
##
## Resolution is by id only. The authored `id` field is the save key (ADR 0056), so
## a file whose id disagrees with its filename is resolved by the id the save
## actually stored, and a renamed file with an unchanged id keeps working.

const TECHNIQUES_ROOT := "res://data/techniques"
const TECHNIQUE_SCRIPT_CLASS := "TechniqueDef"

static var shared: TechniqueCatalog = null

var _definitions: Dictionary = {}
var _loaded: bool = false


static func instance() -> TechniqueCatalog:
	if shared == null:
		shared = TechniqueCatalog.new()
	return shared


## Register a definition in code, for a caller that composes techniques rather than
## loading them from the content tree. Later registration wins, so a test or a
## quest reward can override an authored row without touching the file.
func register(def: TechniqueDef) -> void:
	if def == null or def.id == &"":
		return
	_definitions[String(def.id)] = def


## Every known technique id, canonically ordered.
func technique_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _definitions.keys():
		out.append(StringName(key))
	out.sort()
	return out


## The definition behind a technique id, or null. Loading is lazy per id, so an
## empty content tree costs nothing and a save naming an unknown id simply
## rehydrates as "known but contentless" rather than failing.
func definition(technique_id: StringName) -> TechniqueDef:
	if technique_id == &"":
		return null
	_ensure_loaded()
	var id := String(technique_id)
	if _definitions.has(id):
		return _definitions[id]
	var direct := "%s/%s.tres" % [TECHNIQUES_ROOT, id]
	var def: TechniqueDef = null
	if ResourceLoader.exists(direct):
		def = load(direct) as TechniqueDef
	if def != null:
		_definitions[id] = def
	return def


func has(technique_id: StringName) -> bool:
	return definition(technique_id) != null


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not DirAccess.dir_exists_absolute(TECHNIQUES_ROOT):
		return
	var dir := DirAccess.open(TECHNIQUES_ROOT)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not entry.begins_with(".") and entry.ends_with(".tres"):
			var def := load("%s/%s" % [TECHNIQUES_ROOT, entry]) as TechniqueDef
			if def != null and def.id != &"":
				_definitions[String(def.id)] = def
		entry = dir.get_next()
	dir.list_dir_end()
