class_name AnchorCatalog
extends RefCounted

## The authored anchor content tree, loaded once and cached (ADR 0132).
##
## Definitions live in `res://data/anchor/anchors/`, loaded the way `FateCatalog` loads its own:
## a text scan for `script_class=` so a `.tres` of another resource type in the same directory
## is skipped rather than mis-cast. `ContentScan` caps the walk depth, so a junction pointing
## back at an ancestor cannot return nothing.

const ROOT := "res://data/anchor/anchors"
const SCRIPT_CLASS := "AnchorDef"
const BASE_OWNER := "base"

static var shared: AnchorCatalog = null

## Overlay stack for the anchors family (ADR 0184 §5). Empty means "not wired
## yet": `_ensure_loaded` merges only the authored ROOT. When set, the overlay
## roots merge AFTER the base root so mod content is visible, with the
## declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _anchors: Dictionary = {}
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
			"dir": ROOT,
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


static func instance() -> AnchorCatalog:
	if shared == null:
		shared = AnchorCatalog.new()
	return shared


## Every authored anchor id, sorted. `DirAccess` scan order is not stable and a screen listing
## them must not reorder itself between reads.
func ids() -> Array[StringName]:
	_ensure_loaded()
	var strings: Array[String] = []
	for key in _anchors.keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


## One anchor definition, or null when the id is unknown. Null rather than a guess: an unknown
## anchor is a content bug, and inventing a definition would hide it.
func anchor_definition(anchor_id: StringName) -> AnchorDef:
	_ensure_loaded()
	return _anchors.get(String(anchor_id))


## The known-anchor filter `AnchorState.normalize` needs.
##
## An EMPTY catalog reports an EMPTY filter, which `normalize` reads as "unanswered question,
## keep everything" — so a tree that failed to load is told apart from a build that ships no
## anchors at all, the `DestinyApi._catalog_loaded` problem.
func known_anchors() -> Dictionary:
	_ensure_loaded()
	var out := {}
	for anchor_id in _anchors.keys():
		out[String(anchor_id)] = true
	return out


## Whether the tree loaded far enough for a filter derived from it to mean anything.
func is_loaded() -> bool:
	_ensure_loaded()
	return not _anchors.is_empty()


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("AnchorCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as AnchorDef
		if def != null and def.is_valid_def():
			_anchors[String(def.id)] = def
