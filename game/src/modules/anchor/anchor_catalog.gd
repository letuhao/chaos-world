class_name AnchorCatalog
extends RefCounted

## The authored anchor content tree, loaded once and cached (ADR 0132).
##
## Definitions live in `res://data/anchor/anchors/`, loaded the way `FateCatalog` loads its own:
## a text scan for `script_class=` so a `.tres` of another resource type in the same directory
## is skipped rather than mis-cast. `ContentScan` caps the walk depth, so a junction pointing
## back at an ancestor cannot return nothing.

const ROOT := "res://data/anchor/anchors"
const SCRIPT_CLASS := "AnchorDef"

static var shared: AnchorCatalog = null

var _anchors: Dictionary = {}
var _loaded: bool = false


static func instance() -> AnchorCatalog:
	if shared == null:
		shared = AnchorCatalog.new()
	return shared


## Every authored anchor id, sorted. `DirAccess` scan order is not stable and a screen listing
## them must not reorder itself between reads.
func ids() -> Array[StringName]:
	_ensure_loaded()
	var strings: Array[String] = []
	for key in _anchors.keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


## One anchor definition, or null when the id is unknown. Null rather than a guess: an unknown
## anchor is a content bug, and inventing a definition would hide it.
func anchor_definition(anchor_id: StringName) -> AnchorDef:
	_ensure_loaded()
	return _anchors.get(String(anchor_id))


## The known-anchor filter `AnchorState.normalize` needs.
##
## An EMPTY catalog reports an EMPTY filter, which `normalize` reads as "unanswered question,
## keep everything" — so a tree that failed to load is told apart from a build that ships no
## anchors at all, the `DestinyApi._catalog_loaded` problem.
func known_anchors() -> Dictionary:
	_ensure_loaded()
	var out := {}
	for anchor_id in _anchors.keys():
		out[String(anchor_id)] = true
	return out


## Whether the tree loaded far enough for a filter derived from it to mean anything.
func is_loaded() -> bool:
	_ensure_loaded()
	return not _anchors.is_empty()


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in ContentScan.files_under(ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains('script_class="%s"' % SCRIPT_CLASS):
			continue
		var def := load(path) as AnchorDef
		if def != null and def.is_valid_def():
			_anchors[String(def.id)] = def
