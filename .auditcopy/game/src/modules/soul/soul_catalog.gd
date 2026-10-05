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

static var shared: SoulCatalog = null

var _arrivals: Dictionary = {}
var _loaded: bool = false


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
	for path in ContentScan.files_under(ARRIVALS_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains('script_class="%s"' % SCRIPT_CLASS):
			continue
		var def := load(path) as SoulDef
		if def != null and def.is_valid_def():
			_arrivals[String(def.id)] = def
