class_name SoulCatalog
extends RefCounted

## The authored arrival content tree, loaded once and cached (ADR 0130).
##
## Arrival definitions live in `res://data/soul/arrivals/`. Each is an ordinary `.tres`
## carrying a `script_class`, loaded the way `FateCatalog` loads its own tree: a text scan for
## `script_class=` so a `.tres` belonging to some other resource type in the same directory is
## skipped rather than mis-cast. `ContentScan` caps the walk depth, so a directory junction
## pointing back at an ancestor cannot return nothing.
##
## A deleted `.tres` makes its arrival unreachable rather than granting an arrival nothing
## defines, which is why the gate asks this catalog rather than trusting a ledger row.

const ARRIVALS_ROOT := "res://data/soul/arrivals"
const SCRIPT_CLASS := "SoulDef"
const BASE_OWNER := "base"

static var shared: SoulCatalog = null

## Overlay stack for the soul_arrivals family (ADR 0184 §5). Empty means "not
## wired yet": `_ensure_loaded` merges only the authored ARRIVALS_ROOT. When set,
## the overlay roots merge AFTER the base root so mod content is visible, with the
## declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _arrivals: Dictionary = {}
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
			"dir": ARRIVALS_ROOT,
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
	return CatalogOverlay.merge(_merge_stack(), SCRIPT_CLASS, "id")


static func instance() -> SoulCatalog:
	if shared == null:
		shared = SoulCatalog.new()
	return shared


## Every authored arrival id, in gate order: by authored `order`, then by id so a tie never
## depends on which `.tres` the filesystem scan reached first.
func arrival_ids() -> Array[StringName]:
	_ensure_loaded()
	var rows: Array = []
	for arrival_id in _arrivals.keys():
		var def := _arrivals[arrival_id] as SoulDef
		rows.append({"id": arrival_id, "order": def.order})
	# Sorted by the STRING value because `Array.sort()` on a Variant is not specified to
	# order dictionaries, and the gate's answer must not depend on scan order.
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var left := int(a["order"])
			var right := int(b["order"])
			if left != right:
				return left < right
			return String(a["id"]) < String(b["id"])
	)
	var out: Array[StringName] = []
	for row in rows:
		out.append(StringName(row["id"]))
	return out


## One arrival definition, or null when the id is unknown. Null rather than a guess: an
## unknown arrival is a content bug, and inventing a definition would hide it.
func arrival_definition(arrival_id: StringName) -> SoulDef:
	_ensure_loaded()
	return _arrivals.get(String(arrival_id))


## The known-arrival filter `SoulState.normalize` needs, so a save written by a wider content
## build cannot smuggle in an arrival this build does not define.
##
## An EMPTY catalog reports an EMPTY filter, which `normalize` reads as "unanswered question,
## keep everything" — the `DestinyApi._catalog_loaded` problem, where a tree that failed to
## load must be told apart from a build that ships no arrivals at all.
func known_arrivals() -> Dictionary:
	_ensure_loaded()
	var out := {}
	for arrival_id in _arrivals.keys():
		out[String(arrival_id)] = true
	return out


## Whether the tree loaded far enough for a filter derived from it to mean anything.
func is_loaded() -> bool:
	_ensure_loaded()
	return not _arrivals.is_empty()


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("SoulCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as SoulDef
		if def != null and def.is_valid_def():
			_arrivals[String(def.id)] = def
