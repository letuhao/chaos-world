class_name SetCatalog
extends RefCounted

## The authored set/unique content tree, loaded once and cached.
##
## Set definitions live in `res://data/sets/`, the item definitions the sets and
## uniques are made of live in `res://data/sets/items/`, and the unique drop
## routes live in `res://data/sets/unique_routes.jsonl`. The item definitions
## are ordinary `ItemDef` resources: they resolve through the master option
## catalog exactly like any other item, and they fall back to the items
## module's single game-wide resolver so a set may also name content that lives
## in the main `data/items/` tree.

const SETS_ROOT := "res://data/sets"
const ITEMS_ROOT := "res://data/sets/items"
const ROUTES_PATH := "res://data/sets/unique_routes.jsonl"
const SET_SCRIPT_CLASS := "SetDef"

static var shared: SetCatalog = null

var _sets: Dictionary = {}
var _definitions: Dictionary = {}
var _routes: Dictionary = {}
var _loaded: bool = false


static func instance() -> SetCatalog:
	if shared == null:
		shared = SetCatalog.new()
	return shared


## Every authored set id, canonically ordered.
func set_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _sets.keys():
		out.append(StringName(key))
	out.sort()
	return out


func set_definition(set_id: StringName) -> SetDef:
	_ensure_loaded()
	return _sets.get(String(set_id))


## The definition behind a set member, a unique, or any other item id. Prefers
## this module's own tree, then the items module's resolver, so there is one
## lookup and never a guess.
func definition(item_id: StringName) -> ItemDef:
	_ensure_loaded()
	var id := String(item_id)
	if _definitions.has(id):
		return _definitions[id]
	var direct := "%s/%s.tres" % [ITEMS_ROOT, id]
	var def: ItemDef = null
	if ResourceLoader.exists(direct):
		def = load(direct) as ItemDef
	if def == null:
		def = Crafting.resolve(item_id)
	if def != null:
		_definitions[id] = def
	return def


## The declared drop route for a unique, or `{}` when it has none. Read the same
## row from `unique_routes.jsonl` if a consumer needs the raw declaration.
func route(unique_id: StringName) -> Dictionary:
	_ensure_loaded()
	return _routes.get(String(unique_id), {})


## Every unique the content tree declares, canonically ordered.
func unique_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _routes.keys():
		out.append(StringName(key))
	out.sort()
	return out


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_sets()
	_load_items()
	_load_routes()


func _load_sets() -> void:
	for path in _scan(SETS_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		var text := FileAccess.get_file_as_string(path)
		if not text.contains('script_class="%s"' % SET_SCRIPT_CLASS):
			continue
		var def := load(path) as SetDef
		if def != null and def.id != &"":
			_sets[String(def.id)] = def


func _load_items() -> void:
	for path in _scan(ITEMS_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		var def := load(path) as ItemDef
		if def != null and def.id != &"":
			_definitions[String(def.id)] = def


## One JSON object per line. Keys: `unique_id`, `set_id`, `boss_id`, `domain_id`,
## `route_realm`, `min_rarity`, `drop_weight`, `slot`.
func _load_routes() -> void:
	if not FileAccess.file_exists(ROUTES_PATH):
		push_error("SetCatalog: unique route index missing at %s" % ROUTES_PATH)
		return
	var json := JSON.new()
	for line in FileAccess.get_file_as_string(ROUTES_PATH).split("\n"):
		line = line.strip_edges()
		if line.is_empty():
			continue
		if json.parse(line) != OK or not json.data is Dictionary:
			push_error("SetCatalog: malformed unique route row: %s" % line)
			continue
		var row: Dictionary = json.data
		var unique_id := StringName(OptionCatalog.text_field(row, "unique_id"))
		if unique_id != &"":
			_routes[String(unique_id)] = row


func _scan(root: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(root):
		return out
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				out.append_array(_scan(path))
			else:
				out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
