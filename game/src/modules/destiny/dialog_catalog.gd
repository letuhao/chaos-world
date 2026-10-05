class_name DialogCatalog
extends RefCounted

## The authored dialog content tree, loaded once and cached.
##
## Dialog definitions live in `res://data/dialog/dialogues/`. Loading mirrors
## `FateCatalog`: a text scan for `script_class=` first, so a `.tres` belonging
## to some other resource type in the same directory is skipped rather than
## mis-cast.

const DIALOGUES_ROOT := "res://data/dialog/dialogues"
const DIALOG_SCRIPT_CLASS := "DialogDef"

static var shared: DialogCatalog = null

var _dialogs: Dictionary = {}
var _loaded: bool = false


static func instance() -> DialogCatalog:
	if shared == null:
		shared = DialogCatalog.new()
	return shared


## Every authored dialog id, canonically ordered.
func dialog_ids() -> Array[StringName]:
	_ensure_loaded()
	return _sorted_keys(_dialogs)


## One dialog definition, or null when the id is unknown.
func definition(dialog_id: StringName) -> DialogDef:
	_ensure_loaded()
	return _dialogs.get(String(dialog_id))


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in ContentScan.files_under(DIALOGUES_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % DIALOG_SCRIPT_CLASS
		):
			continue
		var def := load(path) as DialogDef
		if def != null and def.id != &"":
			_dialogs[String(def.id)] = def


func _sorted_keys(source: Dictionary) -> Array[StringName]:
	var strings: Array[String] = []
	for key in source.keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out
