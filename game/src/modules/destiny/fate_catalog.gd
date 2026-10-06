class_name FateCatalog
extends RefCounted

## The authored fate/destiny content tree, loaded once and cached.
##
## Fate definitions live in `res://data/destiny/fates/`, destiny definitions in
## `res://data/destiny/destinies/`. Both are ordinary `.tres` resources carrying
## a `script_class`, loaded the same way `SetCatalog` loads its tree: a text scan
## for `script_class=` so a `.tres` belonging to some other resource type in the
## same directory is skipped rather than mis-cast.

const FATES_ROOT := "res://data/destiny/fates"
const DESTINIES_ROOT := "res://data/destiny/destinies"
const FATE_SCRIPT_CLASS := "FateDef"
const DESTINY_SCRIPT_CLASS := "DestinyDef"
const FATE_ID_FIELD := "id"
const BASE_OWNER := "base"

static var shared: FateCatalog = null

## Overlay stack for the fates family (ADR 0184 §5). Empty means "not wired
## yet": `_ensure_loaded` merges only the authored roots. When set, the
## overlay roots merge AFTER the base roots so mod content is visible, with
## the declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _fates: Dictionary = {}
var _destinies: Dictionary = {}
var _loaded: bool = false


static func instance() -> FateCatalog:
	if shared == null:
		shared = FateCatalog.new()
	return shared


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides, id_field}`. Later rows overlay earlier ones; an id
## collision needs a declared override on the LATER root or the merge fails
## loudly (ADR 0240).
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


## The merge stack for one root: the base root as a base-owned row, then the
## overlay rows in order. The base row carries the family's default id_field
## so the merge reads the correct property even when an overlay row omits it.
func _merge_stack_for(base_root: String) -> Array:
	var stack: Array = [
		{
			"dir": base_root,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": FATE_ID_FIELD,
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay (ADR 0184 §5).
## FateCatalog owns TWO roots (fates + destinies) with two script classes, so
## the merge runs twice and the results are combined. Returns a dictionary
## with `ok`, `reason`, `detail`, and the two merge results under `fates` and
## `destinies`.
func _overlay_merge() -> Dictionary:
	var fates_merged := CatalogOverlay.merge(
		_merge_stack_for(FATES_ROOT), FATE_SCRIPT_CLASS, FATE_ID_FIELD
	)
	var destinies_merged := CatalogOverlay.merge(
		_merge_stack_for(DESTINIES_ROOT), DESTINY_SCRIPT_CLASS, FATE_ID_FIELD
	)
	return {
		"ok": bool(fates_merged.get("ok", false)) and bool(destinies_merged.get("ok", false)),
		"reason": "",
		"detail": "",
		"fates": fates_merged,
		"destinies": destinies_merged,
	}


## Every authored fate id, canonically ordered.
func fate_ids() -> Array[StringName]:
	_ensure_loaded()
	return _sorted_keys(_fates)


## Every authored destiny id, canonically ordered.
func destiny_ids() -> Array[StringName]:
	_ensure_loaded()
	return _sorted_keys(_destinies)


## Keys as StringNames ordered by their STRING value, not by `Array.sort()`.
## A catalog id list is what a codex renders in, so the order must not depend on
## which `.tres` the filesystem scan happened to reach first.
func _sorted_keys(source: Dictionary) -> Array[StringName]:
	var strings: Array[String] = []
	for key in source.keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


## One fate definition, or null when the id is unknown. Null rather than a guess:
## an unknown fate is a content bug, and inventing a definition would hide it.
func fate_definition(fate_id: StringName) -> FateDef:
	_ensure_loaded()
	return _fates.get(String(fate_id))


## One destiny definition, or null when the id is unknown.
func destiny_definition(destiny_id: StringName) -> DestinyDef:
	_ensure_loaded()
	return _destinies.get(String(destiny_id))


## Every destiny in one exclusivity group, canonically ordered. `""` returns an
## empty array — an empty group is not "all destinies", because an unauthored
## group would otherwise silently make every destiny exclusive.
func destinies_in_group(group: StringName) -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	# An empty group means "this destiny is never exclusive", so it has no
	# members. Returning them would make every ungated destiny look exclusive
	# to anything that asked for the empty group.
	if group == &"":
		return out
	for destiny_id in destiny_ids():
		# Through the typed accessor, not `_destinies.get()`: a raw Dictionary
		# lookup returns Variant, and inferring from a Variant is a warning this
		# project treats as an error. It also duplicated destiny_definition().
		var def := destiny_definition(destiny_id)
		if def != null and def.group == group:
			out.append(destiny_id)
	return out


## Every id a gate may name for this destiny: itself plus its authored aliases.
## Kept in the catalog rather than the facade so the alias set is answerable
## without growing a facade that is already near its cap.
func destiny_gate_ids(destiny_id: StringName) -> Array[StringName]:
	var def := destiny_definition(destiny_id)
	if def == null:
		return []
	var out: Array[StringName] = [destiny_id]
	for alias in def.gate_aliases:
		if not out.has(alias):
			out.append(alias)
	return out


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("FateCatalog: %s" % String(merged.get("detail", "")))
		return
	var fates_merged: Dictionary = merged["fates"]
	for entry in fates_merged["merged"]:
		var def := load(String(entry["path"])) as FateDef
		if def != null and def.id != &"":
			_fates[String(def.id)] = def
	var destinies_merged: Dictionary = merged["destinies"]
	for entry in destinies_merged["merged"]:
		var def := load(String(entry["path"])) as DestinyDef
		if def != null and def.id != &"":
			_destinies[String(def.id)] = def


func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
