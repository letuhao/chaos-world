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
const BASE_OWNER := "base"

static var _arts: Array[MaterialArtDef] = []
static var _by_id: Dictionary = {}

## Overlay stack for the body_material_arts family (ADR 0184 §5). Empty means
## "not wired yet": `_load` merges only the authored DATA_DIR. When set, the
## overlay roots merge AFTER the base root so mod content is visible, with the
## declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides, id_field}`. Later rows overlay earlier ones; an id
## collision needs a declared override on the LATER root or the merge fails
## loudly (ADR 0240).
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


## The directories to scan: base root first, then overlay roots in order.
static func _scan_roots() -> Array[String]:
	var out: Array[String] = [DATA_DIR]
	for row in _overlay_stack:
		var dir := String(row.get("dir", ""))
		if dir != "":
			out.append(dir)
	return out


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
	for root in _scan_roots():
		_load_dir(root)
	_arts.sort_custom(func(a: MaterialArtDef, b: MaterialArtDef) -> bool: return a.id < b.id)


static func _load_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	# The DirAccess terminator: `get_next()` returns "" at the end of a listing,
	# so this cannot outlive the directory's contents.
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(".tres"):
			var art := load("%s/%s" % [dir_path, entry]) as MaterialArtDef
			if art != null and not _by_id.has(art.id):
				_by_id[art.id] = art
				_arts.append(art)
		entry = dir.get_next()
	dir.list_dir_end()
