class_name TechniqueAffixCatalog
extends RefCounted

## The technique affix pool: every affix that may appear on a manual.
##
## Loaded from `res://data/techniques/technique_affixes.jsonl`. Each affix
## targets a technique-legal option and carries a value, an exclusivity group,
## and an authored/rolled flag.
##
## Also supports code registration for tests and quest rewards, following the
## same pattern as `TechniqueCatalog.register`.

const AFFIX_PATH := "res://data/techniques/technique_affixes.jsonl"

static var shared: TechniqueAffixCatalog = null

var _affixes: Dictionary = {}  # id -> TechniqueAffix
var _by_option: Dictionary = {}  # option_id -> Array[TechniqueAffix]
var _loaded: bool = false


static func instance() -> TechniqueAffixCatalog:
	if shared == null:
		shared = TechniqueAffixCatalog.new()
	return shared


## Register an affix in code, for a caller that composes affixes rather than
## loading them from the content tree. Later registration wins.
func register(affix: TechniqueAffix) -> void:
	if affix == null or affix.id == &"":
		return
	_ensure_loaded()
	_adopt(affix)


## Clear all registered affixes. Used by tests to isolate affix state.
func clear() -> void:
	_affixes.clear()
	_by_option.clear()
	_loaded = false


## Every affix targeting `option_id`, canonically ordered by id.
func affixes_for(option_id: StringName) -> Array[TechniqueAffix]:
	_ensure_loaded()
	var out: Array[TechniqueAffix] = []
	for affix in _by_option.get(String(option_id), []):
		out.append(affix)
	out.sort_custom(
		func(a: TechniqueAffix, b: TechniqueAffix) -> bool: return String(a.id) < String(b.id)
	)
	return out


## Every registered affix, canonically ordered by id.
func all_affixes() -> Array[TechniqueAffix]:
	_ensure_loaded()
	var out: Array[TechniqueAffix] = []
	for key in _affixes.keys():
		out.append(_affixes[key])
	out.sort_custom(
		func(a: TechniqueAffix, b: TechniqueAffix) -> bool: return String(a.id) < String(b.id)
	)
	return out


func _adopt(affix: TechniqueAffix) -> void:
	_affixes[String(affix.id)] = affix
	var option_id := String(affix.target_option_id)
	if not _by_option.has(option_id):
		_by_option[option_id] = []
	# Remove any existing affix with the same id (last-wins).
	var existing: Array = _by_option[option_id]
	for i in range(existing.size() - 1, -1, -1):
		if String(existing[i].id) == String(affix.id):
			existing.remove_at(i)
	existing.append(affix)


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(AFFIX_PATH):
		return
	var json := JSON.new()
	for line in FileAccess.get_file_as_string(AFFIX_PATH).split("\n"):
		line = line.strip_edges()
		if line.is_empty():
			continue
		if json.parse(line) == OK and json.data is Dictionary:
			_adopt(_from_dict(json.data))


func _from_dict(data: Dictionary) -> TechniqueAffix:
	var affix := TechniqueAffix.new()
	affix.id = StringName(data.get("id", ""))
	affix.display_name = String(data.get("display_name", ""))
	affix.description = String(data.get("description", ""))
	affix.target_type = int(data.get("target_type", 0))
	affix.target_option_id = StringName(data.get("target_option_id", ""))
	affix.target_stat = StringName(data.get("target_stat", ""))
	affix.target_property = StringName(data.get("target_property", ""))
	affix.value = float(data.get("value", 0.0))
	affix.exclusive_group = StringName(data.get("exclusive_group", ""))
	affix.authored = bool(data.get("authored", true))
	affix.rarity = StringName(data.get("rarity", "common"))
	return affix
