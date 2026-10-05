class_name WeaponKindCatalog
extends RefCounted

## Every authored weapon kind, loaded once from `res://data/body_cultivation/weapons`.
##
## ## The catalog is the ONLY place kinds are enumerated
##
## A test, a read model and the use loop all ask this, so a new `.tres` is
## reachable the moment it lands and no reader carries a list that could fall one
## behind. `data/tools arch` cannot see a kind nobody references, which is
## exactly why the yin-yang tests walk THIS list rather than a hand-written one.

const DATA_DIR := "res://data/body_cultivation/weapons"
const BASE_OWNER := "base"

static var _kinds: Array[WeaponKindDef] = []
static var _by_id: Dictionary = {}

## Overlay stack for the body_weapons family (ADR 0184 §5). Empty means "not
## wired yet": `_load` merges only the authored DATA_DIR. When set, the overlay
## roots merge AFTER the base root so mod content is visible, with the
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


static func all() -> Array[WeaponKindDef]:
	if _kinds.is_empty():
		_load()
	return _kinds


## The kind with this id, or null when the id names nothing. A null is the
## honest answer for a `.tres` that was renamed: the use loop refuses rather than
## silently paying out on an undefined demand.
static func find(kind_id: StringName) -> WeaponKindDef:
	all()
	return _by_id.get(kind_id, null)


## The kinds this body may wield at `realm_id`, in authored order. A gate, not a
## filter on power: `min_realm_index` says when a body may HOLD the kind.
static func unlocked_at(realm_id: StringName) -> Array[WeaponKindDef]:
	var index := maxi(0, RealmDefaults.ladder().index_of(realm_id))
	var out: Array[WeaponKindDef] = []
	for kind in all():
		if kind.min_realm_index <= index:
			out.append(kind)
	return out


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for kind in all():
		out.append(kind.id)
	return out


static func _load() -> void:
	_kinds = []
	_by_id = {}
	for root in _scan_roots():
		_load_dir(root)
	# Authored order, not directory order: a read model renders these, and
	# `DirAccess` makes no promise about listing order.
	_kinds.sort_custom(func(a: WeaponKindDef, b: WeaponKindDef) -> bool: return a.id < b.id)


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
			var kind := load("%s/%s" % [dir_path, entry]) as WeaponKindDef
			if kind != null and not _by_id.has(kind.id):
				_by_id[kind.id] = kind
				_kinds.append(kind)
		entry = dir.get_next()
	dir.list_dir_end()
