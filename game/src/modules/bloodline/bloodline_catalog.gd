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
const BASE_OWNER := "base"

static var shared: BloodlineCatalog = null

## Overlay stack for the bloodlines family (ADR 0184 §5). Empty means "not
## wired yet": `_ensure_loaded` merges only the authored BLOODLINES_ROOT. When
## set, the overlay roots merge AFTER the base root so mod content is visible,
## with the declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _bloodlines: Dictionary = {}
var _loaded: bool = false


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides, id_field}`. Later rows overlay earlier ones; an id
## collision needs a declared override on the LATER root or the merge fails
## loudly (ADR 0240).
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


## The merge stack: the base root as a base-owned row, then the overlay rows
## in order. The base row carries the family's default id_field so the merge
## reads the correct property even when an overlay row omits it.
func _merge_stack() -> Array:
	var stack: Array = [
		{
			"dir": BLOODLINES_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": "id",
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay (ADR 0184 §5).
## Returns CatalogOverlay.merge's dictionary unchanged: `{ok, reason, detail,
## merged, paths, owners}`.
func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), BLOODLINE_SCRIPT_CLASS, "id")


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
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("BloodlineCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as BloodlineDef
		if def != null and def.id != &"":
			_bloodlines[String(def.id)] = def


func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
