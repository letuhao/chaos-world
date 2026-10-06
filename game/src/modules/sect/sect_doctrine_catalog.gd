class_name SectDoctrineCatalog
extends RefCounted

## The authored doctrine tree, loaded once and cached beside `SectCatalog`.
##
## ## A SEPARATE SCAN, never a second half of `SectCatalog`'s
##
## `SectCatalog._ensure_loaded` filters on `script_class="SectDef"`, so a
## `SectDoctrineDef` sitting in the same tree is skipped rather than mis-cast. Two
## independent scans are what lets both types ship under `res://data/sect/` — the
## one rule ADR 0083 and ADR 0084 leave no room to bend is that a definition is a
## `.tres` and adding a school of thought must never be a code change (BL-0186).
##
## **An absent directory is empty, not a crash**, exactly as `SectCatalog` treats a
## missing sect tree: the first doctrine is authored in the same change that reads
## it, and a catalog that raised on a missing tree would make the suite unrunnable
## at the moment someone is building the first one.
##
## Nothing about a doctrine is a known-content FILTER. Fit, standing and office are
## dropped by `SectState.normalize` against ids that still have to exist; a fit a
## sect can still read, from a doctrine the build has since retired, is a member's
## own transmission and dropping it would take that away — which is the same
## conservative answer `DestinyState` makes across unrelated fates and destinies.

## `res://data/sect/doctrines` — the authored doctrine definitions.
const DOCTRINES_ROOT := "res://data/sect/doctrines"
## The `script_class` a `.tres` must declare to be read as a doctrine.
const DOCTRINE_SCRIPT_CLASS := "SectDoctrineDef"
## The def property holding this family's id.
const DOCTRINE_ID_FIELD := "id"
## The owner tag for the base content root.
const BASE_OWNER := "base"

static var shared: SectDoctrineCatalog = null

## Overlay stack for the sect_doctrines family (ADR 0184 §5). Empty means "not
## wired yet": `_ensure_loaded` merges only the authored DOCTRINES_ROOT. When
## set, the overlay roots merge AFTER the base root so mod content is visible,
## with the declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _doctrines: Dictionary = {}
var _loaded: bool = false


static func instance() -> SectDoctrineCatalog:
	if shared == null:
		shared = SectDoctrineCatalog.new()
	return shared


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
			"dir": DOCTRINES_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": DOCTRINE_ID_FIELD,
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay (ADR 0184 §5).
## Returns CatalogOverlay.merge's dictionary unchanged: `{ok, reason, detail,
## merged, paths, owners}`.
func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), DOCTRINE_SCRIPT_CLASS, DOCTRINE_ID_FIELD)


## Every authored doctrine id, canonically ordered.
func doctrine_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _doctrines.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One doctrine, or null when the id is unknown. Null rather than a guess: a
## doctrine nothing defines teaches nothing, and inventing one would let a caller
## pass a gate its content never authored.
func doctrine(doctrine_id: StringName) -> SectDoctrineDef:
	_ensure_loaded()
	if doctrine_id == &"":
		return null
	return _doctrines.get(String(doctrine_id))


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("SectDoctrineCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as SectDoctrineDef
		if def != null and def.id != &"":
			_doctrines[String(def.id)] = def


func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
