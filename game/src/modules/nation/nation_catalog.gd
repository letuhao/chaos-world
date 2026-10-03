class_name NationCatalog
extends RefCounted

## The authored nation content tree, loaded once and cached.
##
## Definitions live in `res://data/nation/` and are ordinary `.tres` resources
## carrying a `script_class`, loaded the way `RaceCatalog` loads its tree: a text
## scan for `script_class=` so a `.tres` of some other resource type sitting in the
## same directory is skipped rather than mis-cast.
##
## Nothing here is a `WorldLocationDef` and nothing here is a sect type. A
## `NationTerritoryDef` names its places as plain ids, because the nation module
## declares no `world` and no `clan` dependency and a `.tres` reference would be a
## `res://` edge the boundary checker reads as a real one.

const NATIONS_ROOT := "res://data/nation"
const NATION_SCRIPT_CLASS := "NationDef"
const TERRITORY_SCRIPT_CLASS := "NationTerritoryDef"
const TUNING_PATH := "res://src/modules/nation/nation_tuning.tres"

static var shared: NationCatalog = null

var _nations: Dictionary = {}
var _territories: Dictionary = {}
var _tuning: NationTuning = null
var _loaded: bool = false


static func instance() -> NationCatalog:
	if shared == null:
		shared = NationCatalog.new()
	return shared


## Every authored nation id, canonically ordered.
func nation_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _nations.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One nation definition, or null when the id is unknown. Null rather than a guess:
## an unknown nation is a content bug, and inventing a definition would hide it.
func nation_definition(nation_id: StringName) -> NationDef:
	_ensure_loaded()
	return _nations.get(String(nation_id))


## Every authored territory id, canonically ordered.
func territory_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _territories.keys():
		out.append(StringName(key))
	out.sort()
	return out


## One territory definition, or null when the id is unknown.
func territory_definition(territory_id: StringName) -> NationTerritoryDef:
	_ensure_loaded()
	return _territories.get(String(territory_id))


## The office definitions one nation authors, keyed by office id. **Every seat is
## present, including one with a `""` holder**: a vacancy is a row whose value is
## absent (ADR 0083), so a caller must be handed the seat to discover that nobody
## fills it, rather than discovering its absence by lookup failure.
func office_definitions(nation_id: StringName) -> Dictionary:
	var def := nation_definition(nation_id)
	var out := {}
	if def == null:
		return out
	for office_id in def.office_ids():
		var office := def.office_definition(office_id)
		if office != null:
			out[String(office_id)] = office
	return out


## The content ids the build ships, as a filter `NationState.normalize` reads.
## Claims and seats naming anything else are dropped rather than persisted.
func known_ids() -> Dictionary:
	_ensure_loaded()
	var out := {}
	for territory_id in _territories.keys():
		out[String(territory_id)] = true
	for nation_id in _nations.keys():
		var def: NationDef = _nations[nation_id]
		for office_id in def.office_ids():
			out[String(office_id)] = true
		for territory_id in def.territory_ids:
			out[String(territory_id)] = true
	return out


## The shipped tuning. Loaded from the `.tres`, never built in code, so a rebalance
## is a data edit (ADR 0067).
func tuning() -> NationTuning:
	_ensure_loaded()
	if _tuning == null:
		_tuning = NationTuning.shipped()
	return _tuning


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in _scan(NATIONS_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		var body := FileAccess.get_file_as_string(path)
		if body.contains('script_class="%s"' % NATION_SCRIPT_CLASS):
			var def := load(path) as NationDef
			if def != null and def.id != &"":
				_nations[String(def.id)] = def
		elif body.contains('script_class="%s"' % TERRITORY_SCRIPT_CLASS):
			var territory := load(path) as NationTerritoryDef
			if territory != null and territory.id != &"":
				_territories[String(territory.id)] = territory


func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
