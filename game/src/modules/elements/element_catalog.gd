class_name ElementCatalog
extends RefCounted

## The authored element catalog (ADR 0184 §5). Reads `res://data/elements`
## the way every peer catalog reads its own tree — `ContentScan.files_under`, a
## `script_class="ElementDef"` text test so a `.tres` of another resource type
## in the same folder is skipped rather than mis-cast, and `load()` per file —
## so the elements a player encounters are content, never a literal.
##
## ## Overlay support (ADR 0184 §5)
##
## `set_overlay_roots` accepts an ordered stack of `{dir, owner,
## declared_overrides, id_field}` rows. The overlay roots are scanned AFTER the
## base root so mod content is visible; later roots overlay earlier ones.
##
## ## Code-defined defaults are separate
##
## `ElementDefaults.all()` returns the code-defined default element set (ADR
## 0004). This catalog scans authored `.tres` files. The two paths are separate:
## defaults are always present, authored files are content a mod may add.

const ELEMENTS_ROOT := "res://data/elements"
const ELEMENT_SCRIPT_CLASS := "ElementDef"
const ELEMENT_ID_FIELD := "id"
const BASE_OWNER := "base"

static var shared: ElementCatalog = null

## Overlay stack for the element family (ADR 0184 §5). Empty means "not wired
## yet": `_ensure_loaded` merges only the authored ELEMENTS_ROOT. When set, the
## overlay roots merge AFTER the base root so mod content is visible, with the
## declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _defs: Dictionary = {}
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
			"dir": ELEMENTS_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": ELEMENT_ID_FIELD
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay (ADR 0184 §5).
## Returns CatalogOverlay.merge's dictionary unchanged: `{ok, reason, detail,
## merged, paths, owners}`.
func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), ELEMENT_SCRIPT_CLASS, ELEMENT_ID_FIELD)


static func instance() -> ElementCatalog:
	if shared == null:
		shared = ElementCatalog.new()
	return shared


## Every authored element id, canonically ordered.
func element_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _defs.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One element definition, or null when the id is unknown. Null rather than a
## guess: an unknown element is a content bug, and inventing a definition
## would hide it.
func definition(element_id: StringName) -> ElementDef:
	_ensure_loaded()
	return _defs.get(String(element_id))


func has_definition(element_id: StringName) -> bool:
	_ensure_loaded()
	return _defs.has(String(element_id))


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("ElementCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as ElementDef
		if def != null and def.id != &"":
			_defs[String(def.id)] = def
