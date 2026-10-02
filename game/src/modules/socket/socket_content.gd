class_name SocketContent
extends RefCounted

## Definition lookup for the socket subsystem's own content namespace.
##
## The items module's `Crafting.resolve` is the whole game's stable resolver and
## is always tried first, so anything in `data/items` keeps resolving exactly as
## it does for every other caller. Only ids the main tree does not know fall
## through to `data/socket`, which is where socket items, reagents and gems live.
## An ambiguous id resolves to null rather than guessing.

const ROOT := "res://data/socket"


## The authored definition for `item_id`, or null when nothing defines it.
static func resolve(item_id: StringName) -> ItemDef:
	if item_id == &"":
		return null
	var known := Crafting.resolve(item_id)
	if known != null:
		return known
	return _scan(item_id)


## Every authored socket-namespace id, canonically ordered. Content and tooling
## read the namespace through this so the folder layout stays an implementation
## detail of the module.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	_walk(ROOT, out)
	out.sort()
	return out


## Definitions whose tag carries `tag`, canonically ordered by id. Used to build
## the reagent and socket-item lists a player can actually spend and insert.
static func tagged(tag: StringName) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for item_id in ids():
		var def := resolve(item_id)
		if def != null and def.tags.has(tag):
			out.append(def)
	return out


static func _scan(item_id: StringName) -> ItemDef:
	var found: Array[String] = []
	_collect(ROOT, String(item_id), found)
	if found.size() != 1:
		return null
	return load(found[0]) as ItemDef


static func _walk(path: String, out: Array[StringName]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var child := path.path_join(entry)
			if dir.current_is_dir():
				_walk(child, out)
			elif entry.ends_with(".tres"):
				out.append(StringName(entry.trim_suffix(".tres")))
		entry = dir.get_next()
	dir.list_dir_end()


static func _collect(path: String, item_id: String, found: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var child := path.path_join(entry)
			if dir.current_is_dir():
				_collect(child, item_id, found)
			elif entry == item_id + ".tres":
				found.append(child)
		entry = dir.get_next()
	dir.list_dir_end()
