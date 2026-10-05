class_name WorldLocationCatalog
extends RefCounted

## The authored world location catalog (ADR 0184 §5). Reads
## `res://data/world/locations` the way every peer catalog reads its own tree —
## `ContentScan.files_under`, a `script_class="WorldLocationDef"` text test so
## a `.tres` of another resource type in the same folder is skipped rather than
## mis-cast, and `load()` per file — so the locations a player visits are
## content, never a literal.
##
## ## Overlay support (ADR 0184 §5)
##
## `set_overlay_roots` accepts an ordered stack of `{dir, owner,
## declared_overrides, id_field}` rows. The overlay roots are scanned AFTER the
## base root so mod content is visible; later roots overlay earlier ones. The
## `id_field` on each row names the def property holding the location id when
## it is not "location_id" (the default for WorldLocationDef).

const LOCATIONS_ROOT := "res://data/world/locations"
const LOCATION_SCRIPT_CLASS := "WorldLocationDef"
const LOCATION_ID_FIELD := "location_id"
const BASE_OWNER := "base"

static var shared: WorldLocationCatalog = null

## Overlay stack for the world location family (ADR 0184 §5). Empty means "not
## wired yet": `_ensure_loaded` merges only the authored LOCATIONS_ROOT. When
## set, the overlay roots merge AFTER the base root so mod content is visible,
## with the declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _defs: Dictionary = {}
var _loaded: bool = false


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides, id_field}`. Later rows overlay earlier ones; an id
## collision needs a declared override on the LATER root or the merge fails
## loudly (ADR 0240).
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


static func instance() -> WorldLocationCatalog:
	if shared == null:
		shared = WorldLocationCatalog.new()
	return shared


## Every authored location id, canonically ordered.
func location_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _defs.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One location definition, or null when the id is unknown. Null rather than a
## guess: an unknown location is a content bug, and inventing a definition
## would hide it.
func definition(location_id: StringName) -> WorldLocationDef:
	_ensure_loaded()
	return _defs.get(String(location_id))


func has_definition(location_id: StringName) -> bool:
	_ensure_loaded()
	return _defs.has(String(location_id))


## The merge stack: the base root as a base-owned row, then the overlay rows
## in order. The base row carries the family's default id_field so the merge
## reads the correct property even when an overlay row omits it.
func _merge_stack() -> Array:
	var stack: Array = [
		{
			"dir": LOCATIONS_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": LOCATION_ID_FIELD,
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay (ADR 0184 §5).
## Returns CatalogOverlay.merge's dictionary unchanged: `{ok, reason, detail,
## merged, paths, owners}`.
func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), LOCATION_SCRIPT_CLASS, LOCATION_ID_FIELD)


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("WorldLocationCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as WorldLocationDef
		if def != null and def.location_id != &"":
			_defs[String(def.location_id)] = def
