class_name PortraitIndex
extends RefCounted

## Reads the generated character index into authored portraits (ADR 0131).
##
## ## Why this class exists at all
##
## ADR 0131 promised that the resolver would read authored `.tres` resources and NEVER the
## asset index, so the generator stays optional rather than load-bearing. **That promise is now
## testable in both directions** because the generator has shipped: `tools/character_assets.py`
## writes `game/assets/characters/character-index.jsonl` with a `dialogue_portrait` row per
## character, and every one of those rows carries `race:` and `palette:` tags — the exact fields
## `PortraitDef` authors by hand.
##
## ## So the index is read HERE, and only here
##
## This is the sync step ADR 0131 describes: it turns index rows into something the resolver can
## answer from, and it is the ONLY file in `core/` that opens the index. Delete this class and the
## resolver still works — every actor falls back to a race family or the placeholder — which is
## the property the ADR bought and the reason the resolver itself never names an index.
##
## ## Determinism is the contract
##
## A character is chosen by its id, never by its position in the file, and a race takes the
## FIRST match in SORTED id order. Two runs therefore resolve the same actor to the same face,
## which is what lets a save reload with the face it was created with.

const INDEX_PATH := "user://../assets/characters/character-index.jsonl"
const RACE_TAG := "race:"
const PALETTE_TAG := "palette:"
const BUILD_TAG := "build:"
## The asset slot a dialogue face lives in. A map sprite is a top-down body and is NOT a
## portrait, so reading the wrong slot would give a player a full-body map sprite where a face
## belongs.
const PORTRAIT_SLOT := "dialogue_portrait"

static var shared: PortraitIndex = null
static var _index_root: String = ""

var _rows: Dictionary = {}
var _by_race: Dictionary = {}
var _loaded: bool = false


static func instance() -> PortraitIndex:
	if shared == null:
		shared = PortraitIndex.new()
	return shared


## Point the reader at the generated index. A test overrides it; production uses the default.
##
## Empty restores the authored-content root, so a test cannot leave the singleton pointing at
## its own fixture for the suite after it.
static func set_index_root(path: String) -> void:
	_index_root = path
	if shared != null:
		shared.invalidate()


## Every generated character id, sorted.
func ids() -> Array[StringName]:
	_ensure_loaded()
	var strings: Array[String] = []
	for key in _rows.keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


## The portrait path authored for `character_id`, or `""`.
##
## Returns a PATH rather than a `PortraitDef` on purpose: this class is the bridge from the
## generator's world into the resolver's, and handing a resource across would put an authored
## type on a face the runtime never built.
func portrait_path(character_id: StringName) -> String:
	_ensure_loaded()
	var row = _rows.get(String(character_id))
	if not (row is Dictionary):
		return ""
	var assets := row.get("assets", {}) as Dictionary
	var art = assets.get(PORTRAIT_SLOT)
	if not (art is Dictionary):
		return ""
	if String((art as Dictionary).get("status", "")) != "generated":
		return ""
	return String((art as Dictionary).get("path", ""))


## The first generated character authored for `race_id`, in SORTED id order — never in file
## order, because a `DirAccess`-shaped read is not stable and two runs must not disagree about
## which face a race has.
func character_for_race(race_id: StringName) -> StringName:
	_ensure_loaded()
	var matches: Array[StringName] = _by_race.get(String(race_id), []) as Array[StringName]
	if matches.is_empty():
		return &""
	return matches[0]


## The `race:` tag `character_id` was authored with, or `""`.
func race_of(character_id: StringName) -> StringName:
	_ensure_loaded()
	var row = _rows.get(String(character_id))
	if not (row is Dictionary):
		return &""
	return StringName(_tag_value(row as Dictionary, RACE_TAG))


## The `palette:` tag, which is a theme KEY rather than a pixel value — styling belongs to the
## one theme and a literal colour in content would be a second place to retune it.
func palette_of(character_id: StringName) -> StringName:
	_ensure_loaded()
	var row = _rows.get(String(character_id))
	if not (row is Dictionary):
		return &""
	return StringName(_tag_value(row as Dictionary, PALETTE_TAG))


## The `build:` tag, which is the `form` a `PortraitDef.trait_value("form")` reads.
func form_of(character_id: StringName) -> StringName:
	_ensure_loaded()
	var row = _rows.get(String(character_id))
	if not (row is Dictionary):
		return &""
	return StringName(_tag_value(row as Dictionary, BUILD_TAG))


## Forget what was read. A test calls this after changing the root, because the singleton
## outlives the suite and a stale cache would hand the next suite this suite's rows.
func invalidate() -> void:
	_loaded = false
	_rows.clear()
	_by_race.clear()


## Content audit: every generated row names a portrait slot and a file that exists. A row whose
## art is `pending` or whose path is missing is a content gap, not a runtime fallback — which is
## why this is reported rather than silently skipped.
func validate() -> Array[String]:
	_ensure_loaded()
	var problems: Array[String] = []
	for character_id in _rows.keys():
		var row := _rows[character_id] as Dictionary
		var assets := row.get("assets", {}) as Dictionary
		var art = assets.get(PORTRAIT_SLOT)
		if not (art is Dictionary):
			problems.append("character %s has no %s slot" % [character_id, PORTRAIT_SLOT])
			continue
		var entry := art as Dictionary
		if String(entry.get("status", "")) != "generated":
			problems.append("character %s portrait is %s" % [character_id, entry.get("status", "")])
			continue
		var path := String(entry.get("path", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			problems.append("character %s portrait file is missing: %s" % [character_id, path])
	return problems


# --- Internals -------------------------------------------------------------


## The generated index lives beside the other asset indexes. The root is overridable so a test
## can point at a fixture without copying a 2,000-row file.
static func _root() -> String:
	return (
		_index_root
		if not _index_root.is_empty()
		else "res://assets/characters/character-index.jsonl"
	)


## One tag's value, or `""`. Split on the FIRST colon only, so a value containing a colon is
## not truncated.
static func _tag_value(row: Dictionary, prefix: String) -> String:
	for tag in row.get("tags", []) as Array:
		var name := String(tag)
		if name.begins_with(prefix):
			return name.substr(prefix.length())
	return ""


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var path := _root()
	if not FileAccess.file_exists(path):
		return
	# Read line by line rather than through a JSON array: the file is one object per line and a
	# single malformed line must not cost every other character its face.
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty():
			continue
		var parsed = JSON.parse_string(trimmed)
		if not (parsed is Dictionary):
			continue
		var row := parsed as Dictionary
		var character_id := String(row.get("id", ""))
		if character_id.is_empty():
			continue
		_rows[character_id] = row
		var race := _tag_value(row, RACE_TAG)
		if race.is_empty():
			continue
		var known: Array[StringName] = _by_race.get(race, []) as Array[StringName]
		known.append(StringName(character_id))
		_by_race[race] = known
	# Sorted AFTER collection, so the first match is the lowest id rather than the first line.
	for race in _by_race.keys():
		var matches: Array[StringName] = _by_race[race] as Array[StringName]
		var strings: Array[String] = []
		for match in matches:
			strings.append(String(match))
		strings.sort()
		var ordered: Array[StringName] = []
		for entry in strings:
			ordered.append(StringName(entry))
		_by_race[race] = ordered
