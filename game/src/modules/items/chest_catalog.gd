class_name ChestCatalog
extends RefCounted

## The authored chest index, loaded once and cached.
##
## Mirrors `EventCatalog`/`DialogueCatalog`: a text pre-scan for `script_class="ChestDef"`
## before `load()`, so a `.tres` of another resource type in the same directory is skipped
## rather than mis-cast. A duplicated id keeps the FIRST row and is REPORTED — never
## overwritten, because "whichever came last" is indistinguishable from the author's
## intent and would make a chest pay differently on a different machine.

const CHESTS_ROOT := "res://data/chests"
const CHEST_SCRIPT_CLASS := "ChestDef"

static var shared: ChestCatalog = null

var _by_id: Dictionary = {}
var _problems: Array[String] = []
var _loaded: bool = false


static func instance() -> ChestCatalog:
	if shared == null:
		shared = ChestCatalog.new()
	return shared


## Every authored chest id, canonically ordered on TEXT (a `StringName`'s own order is a
## property of which ids interned first in the process — the `NpcState.npc_ids` finding).
func chest_ids() -> Array[StringName]:
	_ensure_loaded()
	var texts: Array[String] = []
	for key in _by_id.keys():
		texts.append(String(key))
	texts.sort()
	var out: Array[StringName] = []
	for text in texts:
		out.append(StringName(text))
	return out


## One chest, or null when the id is unknown.
func definition(chest_id: StringName) -> ChestDef:
	_ensure_loaded()
	return _by_id.get(String(chest_id))


## Every authoring complaint the load found, as stable strings.
func problems() -> Array[String]:
	_ensure_loaded()
	return _problems.duplicate()


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in ContentScan.files_under(CHESTS_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not (
			FileAccess
			. get_file_as_string(path)
			. contains('script_class="%s"' % CHEST_SCRIPT_CLASS)
		):
			continue
		_absorb(load(path) as ChestDef, path)


## Take one def, refusing an unplayable one by NAME rather than dropping it silently.
func _absorb(def: ChestDef, path: String) -> void:
	if def == null:
		return
	if def.id == &"":
		_problems.append("%s: a chest with no id" % path)
		return
	var key := String(def.id)
	if _by_id.has(key):
		_problems.append("%s: duplicate chest id '%s'" % [path, key])
		return
	_by_id[key] = def
	for complaint in def.problems():
		_problems.append("%s: %s" % [path, complaint])
