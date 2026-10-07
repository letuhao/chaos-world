class_name WorldmapAssets
extends RefCounted

## The asset registry the generator selects from: the shipped
## `map-asset-index.jsonl` read at runtime and indexed by metadata
## (environment, category, archetype) rather than by hard-coded path. Adding
## an asset pack later means shipping index rows — no core change.
##
## Each entry keeps only what generation needs: `id`, `path`, `category`,
## `archetype`, `footprint` (`Vector2i` cells), `collision`, `pivot`,
## `status`. Loaded once per process; `reload()` exists for tests.

const INDEX_PATH := "res://assets/map-asset-index.jsonl"

static var _entries: Array = []
static var _loaded := false


## Every entry for an environment, in index order.
static func for_environment(environment: String) -> Array:
	_ensure_loaded()
	var out: Array = []
	for entry in _entries:
		if String((entry as Dictionary).get("environment", "")) == environment:
			out.append(entry)
	return out


## Entries matching environment + category + archetype, generated only.
static func matching(environment: String, category: String, archetype: String) -> Array:
	_ensure_loaded()
	var out: Array = []
	for entry in _entries:
		var row := entry as Dictionary
		if (
			String(row.get("environment", "")) == environment
			and String(row.get("category", "")) == category
			and String(row.get("archetype", "")) == archetype
			and String(row.get("status", "")) == "generated"
		):
			out.append(row)
	return out


## Every generated entry with an archetype, whatever its category. Terrain
## cells name archetypes like `water_feature.stream` that live outside
## `ground_tile` — selecting by category would render them as holes.
static func by_archetype(environment: String, archetype: String) -> Array:
	_ensure_loaded()
	var out: Array = []
	for entry in _entries:
		var row := entry as Dictionary
		if (
			String(row.get("environment", "")) == environment
			and String(row.get("archetype", "")) == archetype
			and String(row.get("status", "")) == "generated"
		):
			out.append(row)
	return out


## Every environment id present in the index, sorted.
static func environments() -> Array:
	_ensure_loaded()
	var seen := {}
	for entry in _entries:
		seen[String((entry as Dictionary).get("environment", ""))] = true
	var out := seen.keys()
	out.sort()
	return out


static func count() -> int:
	_ensure_loaded()
	return _entries.size()


static func reload() -> void:
	_entries.clear()
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(INDEX_PATH):
		push_error("WorldmapAssets: no index at %s" % INDEX_PATH)
		return
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if file == null:
		push_error("WorldmapAssets: cannot open %s" % INDEX_PATH)
		return
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if not (parsed is Dictionary):
			continue
		var row := parsed as Dictionary
		var fp = row.get("footprint_cells", [1, 1])
		(
			_entries
			. append(
				{
					"id": String(row.get("id", "")),
					"path": String(row.get("path", "")),
					"category": String(row.get("category", "")),
					"archetype": String(row.get("archetype", "")),
					"environment": String(row.get("environment", "")),
					"footprint":
					(
						Vector2i(int(fp[0]), int(fp[1]))
						if fp is Array and fp.size() >= 2
						else Vector2i.ONE
					),
					"collision": String(row.get("collision", "none")),
					"pivot": String(row.get("pivot", "center")),
					"status": String(row.get("status", "")),
				}
			)
		)
