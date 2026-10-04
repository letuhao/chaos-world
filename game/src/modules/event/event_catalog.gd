class_name EventCatalog
extends RefCounted

## The authored world-event tree, loaded once and cached (BL-0054).
##
## Definitions live in `res://data/event/events/` as ordinary `.tres` `EventDef`
## resources, loaded the way `NationCatalog` and `StatusCatalog` load theirs: a
## directory walk for `.tres`, a `script_class=` text check so a foreign resource in
## the same folder is skipped rather than mis-cast, then the declared `id` as the
## key. **Resolution is by id, never by filename**, so renaming a file does not
## retire an event that authored it.
##
## ## A refused def is REPORTED, and it DESTROYS NOTHING
##
## An event whose `problems()` are non-empty is not entered into the catalog and is
## listed by [method rejected] with its reason. An event that loads and can never
## open is the shape ADR 0077 named: five Accepted ADRs and not one symbol. A
## refusal that is visible is a content bug the author finds; a silent skip is a
## content bug nobody finds.
##
## **Refusing a def is a decision about THAT def, and about nothing else.** This cache
## is one per process and every reader in the game shares it, so a `register` that
## refused by ERASING whatever already held the id handed any caller — a test's
## hand-built probe more often than not — the power to delete shipped content for
## the rest of the run. Both refusal branches leave `_events` alone and say so in
## [method rejected]; the id already in the cache is the one that stays. BL-0747.
##
## ## Nothing here rolls a die
##
## The catalog is deterministic — files walked in sorted order, ids returned in
## STRING order — because "which event is available" is a question about the ledger
## and the content tree, never about filesystem or resource load order.

const EVENTS_ROOT := "res://data/event/events"
const EVENT_SCRIPT_CLASS := "EventDef"

static var shared: EventCatalog = null

## Overlay stack for the event family (ADR 0184 §5). Empty means "not wired
## yet": `_ensure_loaded` scans only the authored EVENTS_ROOT. When set, the
## overlay roots are scanned AFTER the base root so mod content is visible.
static var _overlay_stack: Array = []

var _events: Dictionary = {}
var _ids: Array[StringName] = []
var _rejected: Dictionary = {}
var _loaded: bool = false


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides}`. Later rows overlay earlier ones.
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


## The directories to scan: base root first, then overlay roots in order.
func _scan_roots() -> Array[String]:
	var out: Array[String] = [EVENTS_ROOT]
	for row in _overlay_stack:
		var dir := String(row.get("dir", ""))
		if dir != "":
			out.append(dir)
	return out


static func instance() -> EventCatalog:
	if shared == null:
		shared = EventCatalog.new()
	return shared


## Drop the cache so an authored file can be re-read in a long session. Tests call
## this after authoring a def in code; the game never needs it, because a `.tres` is
## immutable for the length of a run.
func reload() -> void:
	_events.clear()
	_ids.clear()
	_rejected.clear()
	_loaded = false


## Every accepted event id, canonically ordered.
func event_ids() -> Array[StringName]:
	_ensure_loaded()
	return _ids.duplicate()


## The definition behind an event id, or null. Null rather than a guess: an unknown
## id is a content or call-site bug, and inventing a definition would hide it.
func event_definition(event_id: StringName) -> EventDef:
	_ensure_loaded()
	if event_id == &"":
		return null
	return _events.get(String(event_id), null)


## Whether the build ships this event.
func has(event_id: StringName) -> bool:
	return event_definition(event_id) != null


## Every authored event at `location_id`, canonically ordered. An empty id asks for
## every event that is tied to a place.
func at_location(location_id: StringName) -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for event_id in _ids:
		var def: EventDef = _events[String(event_id)]
		if location_id != &"" and def.location_id != location_id:
			continue
		out.append(event_id)
	return out


## Ids whose defs exist on disk but were refused, with the reason.
func rejected() -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for event_id in _sorted_keys(_rejected.keys()):
		out.append({"id": String(event_id), "reason": String(_rejected[event_id])})
	return out


## Every event id the build ships, keyed by id. The filter `EventState.normalize`
## reads, so a save from a wider content build cannot smuggle in an event the
## current build does not define.
func known_ids() -> Dictionary:
	_ensure_loaded()
	var out := {}
	for event_id in _ids:
		out[String(event_id)] = true
	return out


## Every defect across the whole tree, one line each. A well-formed tree returns an
## empty array, and a test asserting that is the gate: an authored event nobody can
## open is otherwise indistinguishable from one nobody wrote.
func problems() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for event_id in _ids:
		for problem in (_events[String(event_id)] as EventDef).problems():
			out.append("%s: %s" % [String(event_id), problem])
	for event_id in _sorted_keys(_rejected.keys()):
		out.append("%s: rejected (%s)" % [String(event_id), String(_rejected[event_id])])
	return out


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for root in _scan_roots():
		for path in _scan(root):
			if not path.get_file().ends_with(".tres"):
				continue
			if not FileAccess.get_file_as_string(path).contains(
				'script_class="%s"' % EVENT_SCRIPT_CLASS
			):
				continue
			var def := load(path) as EventDef
			if def == null or def.id == &"":
				continue
			_admit(def, path)


## Accept a def only if it is well-formed. `register` is the escape hatch for a
## caller that composes an event in code (a test): it runs the same gate, so a def
## cannot be injected past the refusal the content tree gets.
func register(def: EventDef) -> bool:
	if def == null:
		return false
	return _admit(def, "<registered>")


func _admit(def: EventDef, origin: String) -> bool:
	var key := String(def.id)
	var found := def.problems()
	if not found.is_empty():
		_rejected[key] = "%s (%s)" % [String(found[0]), origin]
		# **The first def for this id is LEFT ALONE.** A malformed def is refused and
		# REPORTED, never traded against whatever is already registered under the id
		# it claims. It used to `_events.erase(key)` and `_ids.erase(...)` here as
		# well, which made `register` a way to DELETE shipped content from a cache
		# every other caller in the process reads: a hand-built probe carrying a typo
		# (an unknown `kind`, a missing `display_name`) reused a catalogued id and
		# removed it for the rest of the run. A refusal is a decision about the def
		# being offered, and nothing else — see `_registered` below for the rule that
		# makes the duplicate branch obey the same thing.
		return false
	if _events.has(key):
		_rejected[key] = "duplicate id, also defined at %s" % origin
		return false
	_events[key] = def
	_ids.append(def.id)
	_ids = _sorted_ids(_ids)
	return true


## `event_ids` canonically ordered BY STRING VALUE.
##
## `Array[StringName].sort()` is not specified to order by the interned string, and
## the ids are interned — measured (BL-0747): the same eight shipped `.tres` files came
## back in a DIFFERENT order from two loads of the same tree, because the order
## followed resource load order rather than the alphabet. Every consumer of this list
## is a decision (`EventApi.available` walks it in order, and the pulse opens the
## first), so an order that drifts with load order is a world that opens a different
## event from one run to the next. `EventState.active_ids` already sorts this way and
## says why; this is the same comparison, applied to the catalog.
func _sorted_ids(ids: Array[StringName]) -> Array[StringName]:
	var strings: Array[String] = []
	for event_id in ids:
		strings.append(String(event_id))
	strings.sort()
	var out: Array[StringName] = []
	for event_id in strings:
		out.append(StringName(event_id))
	return out


## Deterministic iteration over a dictionary's keys: `rejected()` must report in a
## fixed order rather than in filesystem-insertion order, or two runs on one tree
## disagree about what is broken.
func _sorted_keys(keys: Array) -> Array:
	var out: Array = keys.duplicate()
	out.sort()
	return out


## Every file under `root`, recursively, in sorted order. Iterative on purpose: a
## recursive walk is a `while`-shaped wait, and `DirAccess` ordering is only
## deterministic once the list is sorted.
func _scan(root: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var path: String = current.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(path)
			elif entry.ends_with(".tres"):
				out.append(path)
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out
