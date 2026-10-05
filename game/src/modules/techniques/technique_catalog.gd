class_name TechniqueCatalog
extends RefCounted

## The authored technique content tree, loaded once and cached.
##
## Definitions live in `res://data/techniques/` as ordinary `.tres` `TechniqueDef`
## resources. The module is its own content namespace, exactly like the sets module
## and the socket module: a technique is content this module owns, so a lookup here
## never guesses and never reaches into a sibling's tree.
##
## Resolution is by id only. The authored `id` field is the save key (ADR 0056), so
## a file whose id disagrees with its filename is resolved by the id the save
## actually stored, and a renamed file with an unchanged id keeps working.

const TECHNIQUES_ROOT := "res://data/techniques"
const TECHNIQUE_SCRIPT_CLASS := "TechniqueDef"
const TECHNIQUE_ID_FIELD := "id"
const BASE_OWNER := "base"

static var shared: TechniqueCatalog = null

## Overlay stack for the techniques family (ADR 0184 §5). Empty means "not
## wired yet": `_ensure_loaded` merges only the authored TECHNIQUES_ROOT. When
## set, the overlay roots merge AFTER the base root so mod content is visible,
## with the declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _definitions: Dictionary = {}
## item id -> the technique id delivered by it, from every def's `delivered_by`.
## Built with the definitions and never on its own, so the two maps cannot describe
## different content (DEF-0203).
var _deliveries: Dictionary = {}
var _loaded: bool = false


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides, id_field}`. Later rows overlay earlier ones; an id
## collision needs a declared override on the LATER root or the merge fails
## loudly (ADR 0240).
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


## The directories to scan: base root first, then overlay roots in order.
## Used by the lazy per-id load in `definition`, not by `_ensure_loaded`.
func _scan_roots() -> Array[String]:
	var out: Array[String] = [TECHNIQUES_ROOT]
	for row in _overlay_stack:
		var dir := String(row.get("dir", ""))
		if dir != "":
			out.append(dir)
	return out


## The merge stack: the base root as a base-owned row, then the overlay rows
## in order. The base row carries the family's default id_field so the merge
## reads the correct property even when an overlay row omits it.
func _merge_stack() -> Array:
	var stack: Array = [
		{
			"dir": TECHNIQUES_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": TECHNIQUE_ID_FIELD,
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay (ADR 0184 §5).
## Returns CatalogOverlay.merge's dictionary unchanged: `{ok, reason, detail,
## merged, paths, owners}`.
func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), TECHNIQUE_SCRIPT_CLASS, TECHNIQUE_ID_FIELD)


static func instance() -> TechniqueCatalog:
	if shared == null:
		shared = TechniqueCatalog.new()
	return shared


## Register a definition in code, for a caller that composes techniques rather than
## loading them from the content tree. Later registration wins, so a test or a
## quest reward can override an authored row without touching the file.
func register(def: TechniqueDef) -> void:
	if def == null or def.id == &"":
		return
	_definitions[String(def.id)] = def
	if def.delivered_by != &"":
		_deliveries[String(def.delivered_by)] = def.id


## Every known technique id, canonically ordered.
func technique_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _definitions.keys():
		out.append(StringName(key))
	out.sort()
	return out


## The definition behind a technique id, or null. Loading is lazy per id, so an
## empty content tree costs nothing and a save naming an unknown id simply
## rehydrates as "known but contentless" rather than failing.
func definition(technique_id: StringName) -> TechniqueDef:
	if technique_id == &"":
		return null
	_ensure_loaded()
	var id := String(technique_id)
	if _definitions.has(id):
		return _definitions[id]
	# Lazy per-id load: check base root first, then overlay roots in order.
	for root in _scan_roots():
		var direct := "%s/%s.tres" % [root, id]
		if ResourceLoader.exists(direct):
			var def := load(direct) as TechniqueDef
			if def != null:
				_adopt(def)
				return def
	return null


## The technique a manual `item_id` delivers, or null.
##
## [method TechniqueDef.delivered_by] is the authored answer, so this is an EXPLICIT
## claim rather than a name match: the only way a manual resolves is a def that says
## it teaches it. An id no def claims returns null and the caller refuses
## `unknown_technique`, which is the guard DEF-0203 exists to keep — a second way to
## be FOUND, never a second way to be GUESSED.
func delivers(item_id: StringName) -> TechniqueDef:
	if item_id == &"":
		return null
	_ensure_loaded()
	var technique_id: StringName = StringName(_deliveries.get(String(item_id), ""))
	if technique_id != &"":
		return definition(technique_id)
	# A manual whose id IS a technique id still resolves, so a hand-authored pair
	# that already agrees needs no `delivered_by` and no migration. The reverse —
	# a def whose id is never a manual — is deliberately not a fallback: a
	# technique nobody can find would be a loadout row nothing can occupy.
	return definition(item_id)


func has(technique_id: StringName) -> bool:
	return definition(technique_id) != null


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("TechniqueCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as TechniqueDef
		if def != null and def.id != &"":
			_adopt(def)


## Take one definition into BOTH maps. Every path into the catalog goes through here
## — the directory scan and the lazy per-id load — because a def indexed without its
## `delivered_by` would be findable by id and unreachable by manual, which is exactly
## the half-built state DEF-0203 describes.
func _adopt(def: TechniqueDef) -> void:
	_definitions[String(def.id)] = def
	if def.delivered_by != &"":
		_deliveries[String(def.delivered_by)] = def.id
