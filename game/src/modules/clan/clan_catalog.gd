class_name ClanCatalog
extends RefCounted

## The authored clan content tree, loaded once and cached.
##
## Clan definitions live in `res://data/clans/` and are ordinary `.tres` resources
## carrying a `script_class`, loaded the same way `RaceCatalog` loads its tree: a text
## scan for `script_class=` so a `.tres` belonging to some other resource type in the
## same directory is skipped rather than mis-cast.

const CLANS_ROOT := "res://data/clans"
const CLAN_SCRIPT_CLASS := "ClanDef"

static var shared: ClanCatalog = null

var _clans: Dictionary = {}
var _loaded: bool = false


static func instance() -> ClanCatalog:
	if shared == null:
		shared = ClanCatalog.new()
	return shared


## Every authored clan id, canonically ordered.
func clan_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _clans.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One clan definition, or null when the id is unknown. Null rather than a guess: an
## unknown clan is a content bug, and inventing a definition would hide it.
func clan_definition(clan_id: StringName) -> ClanDef:
	_ensure_loaded()
	return _clans.get(String(clan_id))


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in _scan(CLANS_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % CLAN_SCRIPT_CLASS
		):
			continue
		var def := load(path) as ClanDef
		if def != null and def.id != &"":
			_clans[String(def.id)] = def


func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
