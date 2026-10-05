class_name MaterialArtCatalog
extends RefCounted

## Every authored material art, loaded once from `res://data/body_cultivation/materials`.
##
## ## The catalog is the ONLY place arts are enumerated
##
## The same reason `WeaponKindCatalog` exists: a reader that carried its own list
## would be one `.tres` behind, and the yin-yang test walks THIS list so an art
## with no liability is refused by the gate rather than by review.

const DATA_DIR := "res://data/body_cultivation/materials"

static var _arts: Array[MaterialArtDef] = []
static var _by_id: Dictionary = {}


static func all() -> Array[MaterialArtDef]:
	if _arts.is_empty():
		_load()
	return _arts


static func find(art_id: StringName) -> MaterialArtDef:
	all()
	return _by_id.get(art_id, null)


## The arts this body may practise at `realm_id`.
static func unlocked_at(realm_id: StringName) -> Array[MaterialArtDef]:
	var index := maxi(0, RealmDefaults.ladder().index_of(realm_id))
	var out: Array[MaterialArtDef] = []
	for art in all():
		if art.min_realm_index <= index:
			out.append(art)
	return out


## The distinct materials the shipped arts are practised on. A read model
## publishes this so a panel can render the axis rather than only the rows.
static func materials() -> Array[StringName]:
	var out: Array[StringName] = []
	for art in all():
		if not out.has(art.material):
			out.append(art.material)
	return out


static func _load() -> void:
	_arts = []
	_by_id = {}
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	# The DirAccess terminator: `get_next()` returns "" at the end of a listing,
	# so this cannot outlive the directory's contents.
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(".tres"):
			var art := load("%s/%s" % [DATA_DIR, entry]) as MaterialArtDef
			if art != null and not _by_id.has(art.id):
				_by_id[art.id] = art
				_arts.append(art)
		entry = dir.get_next()
	dir.list_dir_end()
	_arts.sort_custom(func(a: MaterialArtDef, b: MaterialArtDef) -> bool: return a.id < b.id)
