class_name StoryCatalog
extends RefCounted

## The authored story content tree, loaded once and cached.
##
## Definitions live at `res://data/story/stories/`. Loading mirrors `QuestCatalog`
## exactly: a text scan for `script_class=` first, so a `.tres` belonging to some other
## resource type in the same directory is skipped rather than mis-cast, and a test seam
## so a suite can install exactly the stories it needs instead of depending on which
## files happen to be authored today.
##
## The scan uses `for` over a materialized list, never a `while` over
## `DirAccess.get_next()`: the repo's arch gate fails an unbounded wait in `res://src`,
## and `list_dir_begin()/get_next()` is the shape it is checking for.
##
## ## Why the overlay stack is here from the start
##
## A story is the single most modded content type there is, and a catalog that scans one
## hardcoded root cannot be overlaid. `QuestCatalog` carries the same stack for the same
## reason (ADR 0184 §5): base first, mods in load order, later wins, and an id collision
## that was not declared in `overrides` fails loudly rather than silently replacing a
## shipped story.

const STORIES_ROOT := "res://data/story/stories"
const STORY_SCRIPT_CLASS := "StoryDef"
const STORY_ID_FIELD := "id"
const BASE_OWNER := "base"

static var shared: StoryCatalog = null

## Overlay stack for the story family. Empty means "no mod roots": `_ensure_loaded`
## merges only the authored STORIES_ROOT.
static var _overlay_stack: Array = []

var _defs: Dictionary = {}
var _problems: Array[String] = []
var _loaded: bool = false


## Set the family's overlay stack: ordered rows of `{dir, owner, declared_overrides,
## id_field}`. Later rows overlay earlier ones; an id collision needs a declared override
## on the LATER root or the merge fails loudly (ADR 0240).
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


## The merge stack: the base root as a base-owned row, then the overlay rows in order.
func _merge_stack() -> Array:
	var stack: Array = [
		{
			"dir": STORIES_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": STORY_ID_FIELD
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay (ADR 0184 §5).
func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), STORY_SCRIPT_CLASS, STORY_ID_FIELD)


static func instance() -> StoryCatalog:
	if shared == null:
		shared = StoryCatalog.new()
	return shared


## Every authored story id, canonically ordered.
func story_ids() -> Array[StringName]:
	_ensure_loaded()
	return _sorted_keys(_defs)


## One story definition, or null when the id is unknown. Null rather than a guess: an
## unknown story is a content bug, and inventing one would hide it behind an empty ladder
## that reports itself finished.
func definition(story_id: StringName) -> StoryDef:
	_ensure_loaded()
	return _defs.get(String(story_id))


func has_definition(story_id: StringName) -> bool:
	_ensure_loaded()
	return _defs.has(String(story_id))


## Every authoring complaint the load found, as stable strings. A content guard reads this
## and fails on a non-empty list, so a story whose entry chapter names nothing is reported
## by a tool instead of discovered by a player who cannot start it.
func problems() -> Array[String]:
	_ensure_loaded()
	return _problems.duplicate()


## Test seam: drop every authored story.
func reset() -> void:
	_defs.clear()
	_problems.clear()
	_loaded = false


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("StoryCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var path := String(entry["path"])
		# Pre-scan the text before loading: a directory can hold more than one resource
		# type, and load()ing all of them would put a non-story resource into a dictionary
		# typed as a StoryDef.
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % STORY_SCRIPT_CLASS
		):
			continue
		_absorb(load(path) as StoryDef, path)


## Take one def, refusing the ways a story can be unplayable by NAME rather than dropping
## it. A catalog that silently skips a broken def answers a content question with a
## smaller catalogue and no explanation, which is the failure mode this repo keeps filing.
func _absorb(def: StoryDef, path: String) -> void:
	if def == null:
		_problems.append("%s: not loadable as a StoryDef" % path)
		return
	if def.id == &"":
		_problems.append("%s: a story with no id" % path)
		return
	var key := String(def.id)
	if _defs.has(key):
		_problems.append("%s: duplicate story id '%s'" % [path, key])
		return
	_defs[key] = def
	for problem in def.problems():
		_problems.append("%s: %s" % [path, problem])


## Keys as StringNames ordered by their STRING value, not by `Array.sort()`: the ids are
## interned, so a bare sort can order by load order. The order is what a panel renders, so
## it cannot be allowed to drift between reads.
func _sorted_keys(source: Dictionary) -> Array[StringName]:
	var strings: Array[String] = []
	for key in source.keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out
