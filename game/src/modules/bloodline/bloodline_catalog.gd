class_name BloodlineCatalog
extends RefCounted

## The authored lineage content tree, loaded once and cached.
##
## Lineage definitions live in `res://data/bloodlines/` and are ordinary `.tres`
## resources carrying a `script_class`, loaded the same way `RaceCatalog` loads its
## tree: a text scan for `script_class=` so a `.tres` belonging to some other resource
## type in the same directory is skipped rather than mis-cast.

const BLOODLINES_ROOT := "res://data/bloodlines"
const BLOODLINE_SCRIPT_CLASS := "BloodlineDef"

static var shared: BloodlineCatalog = null

var _bloodlines: Dictionary = {}
var _loaded: bool = false


static func instance() -> BloodlineCatalog:
	if shared == null:
		shared = BloodlineCatalog.new()
	return shared


## Every authored lineage id, canonically ordered.
func bloodline_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _bloodlines.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One lineage definition, or null when the id is unknown. Null rather than a guess:
## an unknown lineage is a content bug, and inventing a definition would hide it.
func bloodline_definition(bloodline_id: StringName) -> BloodlineDef:
	_ensure_loaded()
	return _bloodlines.get(String(bloodline_id))


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in _scan(BLOODLINES_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % BLOODLINE_SCRIPT_CLASS
		):
			continue
		var def := load(path) as BloodlineDef
		if def != null and def.id != &"":
			_bloodlines[String(def.id)] = def


func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
