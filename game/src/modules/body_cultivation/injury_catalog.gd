class_name InjuryCatalog
extends RefCounted

## The authored CATALOG of destructible parts, and the only way a part is named.
##
## ## WHY A CATALOG AND NOT A FIXED LIST
##
## "Destroy and recreate" is only a system if the set of things that can be broken
## is DATA. A `.tres` per part is the repo's own precedent for exactly this —
## `AcupointDef` under `body_cultivation/acupoints` is the same idea at a finer
## granularity — so a new part is an authored file and no `.gd` changes. That is
## also what makes `InjuryDef` a `Resource`: it must be something a designer fills
## in, not something a code path constructs.
##
## ## The `.tres` files are read, never counted
##
## No count of parts appears in any `.gd`, for the reason `BodyLocation` states
## about the huyệt: the shipped catalog's size is content, and a balance pass is
## entitled to move it without touching this module. The directory is enumerated
## once and cached per directory path, so a caller pointing at a different
## directory re-reads rather than answering with another folder's parts.

const DATA_DIR := "res://data/body_cultivation/injuries"
const BASE_OWNER := "base"

static var _defs: Dictionary = {}
static var _cached_dir: String = ""

## Overlay stack for the body_injury_tuning family (ADR 0184 §5). Empty means
## "not wired yet": `all` merges only the authored DATA_DIR. When set, the
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


## Every authored part, keyed by id. An empty dictionary when the directory is
## unreadable, which is a visibly empty system rather than a plausible one.
static func all() -> Dictionary:
	var cached := _defs
	if not cached.is_empty() and _cached_dir == DATA_DIR and _overlay_stack.is_empty():
		return cached
	_defs = {}
	for root in _scan_roots():
		_defs.merge(_load(root), true)
	_cached_dir = DATA_DIR
	return _defs


## Every authored part id, in SORTED order. The sort is on the `String` form
## because `StringName`'s own `<` falls back to a handle comparison for two
## differently-interned equal texts, which would make this order depend on
## allocation rather than on the ids.
static func all_ids() -> Array[StringName]:
	var sorted: Array[String] = []
	for key in all().keys():
		sorted.append(String(key))
	sorted.sort()
	var out: Array[StringName] = []
	for id in sorted:
		out.append(StringName(id))
	return out


## One authored part, or null when the catalog does not carry it. A caller asking
## "is this part real" gets an answer it can refuse on rather than a fabricated
## definition that would degrade a stat nobody named.
static func definition_of(part_id: StringName) -> InjuryDef:
	if part_id == &"":
		return null
	return all().get(String(part_id))


## The parts riding one channel, in sorted id order. Bounded by the authored
## catalog, which this loop reads and does not grow.
static func defs_on_meridian(meridian_id: StringName) -> Array[InjuryDef]:
	var out: Array[InjuryDef] = []
	for entry in all_ids():
		var def := definition_of(entry)
		if def != null and def.meridian_id == meridian_id:
			out.append(def)
	return out


## The parts riding one huyệt, in sorted id order. Bounded by the authored
## catalog, which this loop reads and does not grow.
static func defs_on_point(point_id: StringName) -> Array[InjuryDef]:
	var out: Array[InjuryDef] = []
	for entry in all_ids():
		var def := definition_of(entry)
		if def != null and def.point_id == point_id:
			out.append(def)
	return out


## ## `ResourceLoader.load`, NOT `DirAccess.get_resource`
##
## The same trap `BodyLocation._point_map` documents: Godot 4's `DirAccess` has
## `get_resource_file` (a probe returning a path or `""`) and no `get_resource`,
## and calling the latter raised `Invalid call. Nonexistent function` on EVERY
## entry — so the map silently came back EMPTY for all sixty files. `DirAccess`
## only ever tells you what is THERE; `ResourceLoader` is what loads it.
static func _load(directory: String) -> Dictionary:
	var out: Dictionary = {}
	if directory.is_empty():
		return out
	var dir := DirAccess.open(directory)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	# Bounded by the directory listing: `get_next` returns "" at the end, which is
	# the terminator the loop's own condition tests. Nothing is appended here.
	while entry != "":
		if not entry.begins_with(".") and entry.ends_with(".tres"):
			var res: Variant = ResourceLoader.load("%s/%s" % [directory, entry])
			if res is InjuryDef:
				var def := res as InjuryDef
				if def.id != &"":
					out[String(def.id)] = def
		entry = dir.get_next()
	dir.list_dir_end()
	return out
