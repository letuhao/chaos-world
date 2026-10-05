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
const QUEST_ID_FIELD := "id"
const BASE_OWNER := "base"

static var shared: QuestCatalog = null

## Overlay stack for the quest family (ADR 0184 §5). Empty means "not wired
## yet": `_ensure_loaded` merges only the authored QUESTS_ROOT. When set, the
## overlay roots merge AFTER the base root so mod content is visible, with the
## declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _defs: Dictionary = {}
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
			"dir": QUESTS_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": QUEST_ID_FIELD
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay (ADR 0184 §5).
## Returns CatalogOverlay.merge's dictionary unchanged: `{ok, reason, detail,
## merged, paths, owners}`.
func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), QUEST_SCRIPT_CLASS, QUEST_ID_FIELD)


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
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("QuestCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as QuestDef
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
