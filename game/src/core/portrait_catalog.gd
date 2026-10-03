class_name PortraitCatalog
extends RefCounted

## The authored portrait tree, loaded once and cached (ADR 0131).
##
## Definitions live in `res://data/portraits/`, loaded the way `FateCatalog` loads its own: a
## text scan for `script_class=` so a `.tres` of another resource type in the same directory is
## skipped rather than mis-cast. `ContentScan` caps the walk depth, so a junction pointing back
## at an ancestor cannot return nothing.

const ROOT := "res://data/portraits"
const SCRIPT_CLASS := "PortraitDef"

static var shared: PortraitCatalog = null

var _portraits: Dictionary = {}
var _loaded: bool = false


static func instance() -> PortraitCatalog:
	if shared == null:
		shared = PortraitCatalog.new()
	return shared


## Every authored portrait id, sorted. `DirAccess` scan order is not stable and a codex listing
## them must not reorder itself between reads.
func ids() -> Array[StringName]:
	_ensure_loaded()
	var strings: Array[String] = []
	for key in _portraits.keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


## One portrait definition, or null when the id is unknown. Null rather than a guess: an
## unknown portrait is a content bug, and inventing a definition would hide it.
func portrait_definition(portrait_id: StringName) -> PortraitDef:
	_ensure_loaded()
	return _portraits.get(String(portrait_id))


## The first portrait authored for `race_id`, in id order, or null when that body plan has no
## face of its own.
##
## Deterministic by construction: ids are sorted before the first match is taken, so two NPCs of
## the same race never get different faces between two runs.
func for_race(race_id: StringName) -> PortraitDef:
	_ensure_loaded()
	for portrait_id in ids():
		var def := _portraits[portrait_id] as PortraitDef
		if def != null and def.race_id == race_id:
			return def
	return null


## The fallback face. Null only when the content tree failed to load, which `PortraitResolver`
## treats as a wiring fault rather than as a portrait.
func placeholder() -> PortraitDef:
	_ensure_loaded()
	return _portraits.get(String(PortraitDef.PLACEHOLDER))


## Whether the tree loaded far enough for a lookup to mean anything. An empty tree is not a
## build that ships no portraits, it is a build whose content is missing, and the two must not
## read the same way.
func is_loaded() -> bool:
	_ensure_loaded()
	return not _portraits.is_empty()


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in ContentScan.files_under(ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains('script_class="%s"' % SCRIPT_CLASS):
			continue
		var def := load(path) as PortraitDef
		if def != null and def.is_valid_def():
			_portraits[String(def.id)] = def
