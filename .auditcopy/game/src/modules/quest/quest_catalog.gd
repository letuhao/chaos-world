class_name QuestCatalog
extends RefCounted

## The authored quest content tree, loaded once and cached.
##
## Quest definitions live at `res://data/quest/quests/`. Loading mirrors
## `FateCatalog`: a text scan for `script_class=` first, so a `.tres` belonging
## to some other resource type in the same directory is skipped rather than
## mis-cast, and a test seam so a suite can install exactly the quests it needs
## instead of depending on which files happen to be authored today.
##
## The scan uses `for` over a materialized list, never a `while` over
## `DirAccess.get_next()`: the repo's arch gate fails an unbounded wait in
## `res://src`, and `list_dir_begin()/get_next()` is the shape it is checking for.

const QUESTS_ROOT := "res://data/quest/quests"
const QUEST_SCRIPT_CLASS := "QuestDef"

static var shared: QuestCatalog = null

## Overlay stack for the quest family (ADR 0184 §5). Empty means "not wired
## yet": `_ensure_loaded` scans only the authored QUESTS_ROOT. When set, the
## overlay roots are scanned AFTER the base root so mod content is visible.
static var _overlay_stack: Array = []

var _defs: Dictionary = {}
var _loaded: bool = false


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides}`. Later rows overlay earlier ones.
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


## The directories to scan: base root first, then overlay roots in order.
func _scan_roots() -> Array[String]:
	var out: Array[String] = [QUESTS_ROOT]
	for row in _overlay_stack:
		var dir := String(row.get("dir", ""))
		if dir != "":
			out.append(dir)
	return out


static func instance() -> QuestCatalog:
	if shared == null:
		shared = QuestCatalog.new()
	return shared


## Every authored quest id, canonically ordered.
func quest_ids() -> Array[StringName]:
	_ensure_loaded()
	return _sorted_keys(_defs)


## One quest definition, or null when the id is unknown. Null rather than a
## guess: an unknown quest is a content bug, and inventing a definition would
## hide it behind an empty quest that completes instantly.
func definition(quest_id: StringName) -> QuestDef:
	_ensure_loaded()
	return _defs.get(String(quest_id))


func has_definition(quest_id: StringName) -> bool:
	_ensure_loaded()
	return _defs.has(String(quest_id))


## Every quest of one kind, canonically ordered. `""` returns an empty array: an
## empty kind is a content bug, not "all kinds".
##
## The authoring-side reader of `QuestDef.kind`. The runtime reader is
## `QuestApi.offered`, which offers only `authored` quests; this is the query a
## panel or a tooling script uses to ask what the tree holds of each origin.
func defs_of_kind(kind: StringName) -> Array[QuestDef]:
	var out: Array[QuestDef] = []
	for quest_id in quest_ids():
		var def := definition(quest_id)
		if def != null and def.kind == kind:
			out.append(def)
	return out


## Test seam: drop every authored quest.
func reset() -> void:
	_defs.clear()
	_loaded = false


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for root in _scan_roots():
		for path in _scan(root):
			if not path.get_file().ends_with(".tres"):
				continue
			if not FileAccess.get_file_as_string(path).contains(
				'script_class="%s"' % QUEST_SCRIPT_CLASS
			):
				continue
			var def := load(path) as QuestDef
			if def != null and def.id != &"":
				_defs[String(def.id)] = def


## Keys as StringNames ordered by their STRING value, not by `Array.sort()`: the
## ids are interned, so a bare sort can order by load order. The order is what a
## panel renders, so it cannot be allowed to drift between reads.
func _sorted_keys(source: Dictionary) -> Array[StringName]:
	var strings: Array[String] = []
	for key in source.keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


## Every `.tres`-eligible path under `root`. The directory listing is bounded by
## what is on disk and each level is materialized into an `Array`, so the walk
## has a `for` and a real size instead of an open-ended cursor.
##
## Delegates to `ContentScan`, which is the single depth-capped implementation
## every catalog shares. The local recursion this replaced had no depth cap, so a
## symlink loop would have recursed until the stack died.
func _scan(root: String) -> Array[String]:
	return ContentScan.files_under_unsorted(root)
