class_name RaceCatalog
extends RefCounted

## The authored race content tree, loaded once and cached.
##
## Race definitions live in `res://data/races/` and are ordinary `.tres` resources
## carrying a `script_class`, loaded the same way `FateCatalog` loads its tree: a text
## scan for `script_class=` so a `.tres` belonging to some other resource type in the
## same directory is skipped rather than mis-cast.

const RACES_ROOT := "res://data/races"
const RACE_SCRIPT_CLASS := "RaceDef"
const RACE_ID_FIELD := "id"
const BASE_OWNER := "base"

static var shared: RaceCatalog = null

## Overlay stack for the race family (ADR 0184 §5). Empty means "not wired
## yet": `_ensure_loaded` merges only the authored RACES_ROOT. When set, the
## overlay roots merge AFTER the base root so mod content is visible, with the
## declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _races: Dictionary = {}
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
			"dir": RACES_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": RACE_ID_FIELD,
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay (ADR 0184 §5).
## Returns CatalogOverlay.merge's dictionary unchanged: `{ok, reason, detail,
## merged, paths, owners}`.
func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), RACE_SCRIPT_CLASS, RACE_ID_FIELD)


static func instance() -> RaceCatalog:
	if shared == null:
		shared = RaceCatalog.new()
	return shared


## Every authored race id, canonically ordered.
func race_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _races.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One race definition, or null when the id is unknown. Null rather than a guess: an
## unknown race is a content bug, and inventing a definition would hide it.
func race_definition(race_id: StringName) -> RaceDef:
	_ensure_loaded()
	return _races.get(String(race_id))


## The race a contested conception falls back to when no parent's race clears its
## manifestation threshold. A `baseline` tag, because the fallback is content: a build
## that wants a different default authors it, rather than the code naming an id.
##
## Resolution falls back through the first sorted race id, so the answer is still
## defined when nothing is tagged. An empty catalog yields `&""` and says so rather
## than inventing a definition.
func baseline_race() -> StringName:
	_ensure_loaded()
	var ids := race_ids()
	for race_id in ids:
		var def := _races.get(String(race_id)) as RaceDef
		if def != null and def.tags.has(RaceDef.BASELINE_TAG):
			return race_id
	return ids[0] if not ids.is_empty() else &""


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("RaceCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as RaceDef
		if def != null and def.id != &"":
			_races[String(def.id)] = def
