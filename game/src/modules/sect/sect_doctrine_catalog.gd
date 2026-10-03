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

static var shared: SectDoctrineCatalog = null

var _doctrines: Dictionary = {}
var _loaded: bool = false


static func instance() -> SectDoctrineCatalog:
	if shared == null:
		shared = SectDoctrineCatalog.new()
	return shared


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
	for path in _scan(DOCTRINES_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % DOCTRINE_SCRIPT_CLASS
		):
			continue
		var def := load(path) as SectDoctrineDef
		if def == null or def.id == &"":
			continue
		_doctrines[String(def.id)] = def


func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
