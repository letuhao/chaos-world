class_name EncounterCatalog
extends RefCounted

## The authored encounter/prophecy content tree, loaded once and cached.
##
## Encounter definitions live in `res://data/encounter/encounters/`, prophecy
## definitions in `res://data/encounter/prophecies/`. Both are ordinary `.tres`
## resources carrying a `script_class`, loaded the same way `FateCatalog` loads
## its tree: a text scan for `script_class=` so a `.tres` belonging to some other
## resource type in the same directory is skipped rather than mis-cast.

const ENCOUNTERS_ROOT := "res://data/encounter/encounters"
const PROPHECIES_ROOT := "res://data/encounter/prophecies"
const ENCOUNTER_SCRIPT_CLASS := "EncounterDef"
const PROPHECY_SCRIPT_CLASS := "ProphecyDef"

static var shared: EncounterCatalog = null

var _encounters: Dictionary = {}
var _prophecies: Dictionary = {}
var _loaded: bool = false


static func instance() -> EncounterCatalog:
	if shared == null:
		shared = EncounterCatalog.new()
	return shared


## Every authored encounter id, canonically ordered.
func encounter_ids() -> Array[StringName]:
	_ensure_loaded()
	return _sorted_keys(_encounters)


## Every authored prophecy id, canonically ordered.
func prophecy_ids() -> Array[StringName]:
	_ensure_loaded()
	return _sorted_keys(_prophecies)


## One encounter definition, or null when the id is unknown.
func encounter_definition(encounter_id: StringName) -> EncounterDef:
	_ensure_loaded()
	return _encounters.get(String(encounter_id))


## One prophecy definition, or null when the id is unknown.
func prophecy_definition(prophecy_id: StringName) -> ProphecyDef:
	_ensure_loaded()
	return _prophecies.get(String(prophecy_id))


## Every prophecy that hints at `fate_id`. At most one (uniqueness gate).
func prophecies_hinting_at(fate_id: StringName) -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for prophecy_id in prophecy_ids():
		var def := prophecy_definition(prophecy_id)
		if def != null and def.hint_fate_id == fate_id:
			out.append(prophecy_id)
	return out


## Validate the uniqueness gate: no two prophecies hint at the same fate.
## Returns an array of problem strings; empty means clean.
func validate_uniqueness() -> Array[String]:
	_ensure_loaded()
	var problems: Array[String] = []
	var seen: Dictionary = {}
	for prophecy_id in prophecy_ids():
		var def := prophecy_definition(prophecy_id)
		if def == null:
			continue
		if def.hint_fate_id == &"":
			problems.append("prophecy %s: hints at no fate" % String(prophecy_id))
			continue
		if seen.has(String(def.hint_fate_id)):
			problems.append(
				(
					"prophecy %s: hints at fate '%s', already hinted by prophecy %s"
					% [
						String(prophecy_id),
						String(def.hint_fate_id),
						String(seen[String(def.hint_fate_id)])
					]
				)
			)
		else:
			seen[String(def.hint_fate_id)] = prophecy_id
	return problems


## Keys as StringNames ordered by their STRING value, not by `Array.sort()`.
func _sorted_keys(source: Dictionary) -> Array[StringName]:
	var strings: Array[String] = []
	for key in source.keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_encounters()
	_load_prophecies()


func _load_encounters() -> void:
	for path in _scan(ENCOUNTERS_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % ENCOUNTER_SCRIPT_CLASS
		):
			continue
		var def := load(path) as EncounterDef
		if def != null and def.id != &"":
			_encounters[String(def.id)] = def


func _load_prophecies() -> void:
	for path in _scan(PROPHECIES_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % PROPHECY_SCRIPT_CLASS
		):
			continue
		var def := load(path) as ProphecyDef
		if def != null and def.id != &"":
			_prophecies[String(def.id)] = def


func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
