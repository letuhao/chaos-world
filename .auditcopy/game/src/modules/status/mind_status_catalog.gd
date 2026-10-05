class_name MindStatusCatalog
extends RefCounted

## The authored mind-status tree, loaded once and cached — the same
## loader-and-one-gate shape `StatusCatalog` is for the twenty.
##
## ## A SECOND NAMESPACE beside the element catalogue, not an entry in it
##
## `res://data/statuses` is the closed twenty and a test pins that id SET, so a
## mind status cannot be added there without breaking a claim another module owns.
## `res://src/data/mind_statuses` is its own tree under the module that inflicts
## it, and [method ids] answers only that tree. Neither catalogue can reach the
## other's defs, so "what does a landed elemental blow inflict" and "what does a
## mind cultivator impose" stay two questions with two answers.
##
## ## Loaded in SORTED order, deterministically
##
## The same reason `StatusCatalog._scan` sorts: a designer reading a defect report
## must get the same list twice, and `[method problems]` joins across defs so the
## ORDER of that join is the order a message is built in.
##
## ## The PAIRING is checked across the whole tree, not per file
##
## A def can name a counterpart this file has never seen — it loads alphabetically
## after its pair. So `_pairing_defects` runs over the SET once the walk is done,
## which is the same cross-def class `StatusCatalog._landed_blow_collisions` handles
## for the twenty and refuses rather than tie-breaks.

const MIND_ROOT := "res://src/data/mind_statuses"
const DEF_SCRIPT_CLASS := "MindStatusDef"

## The three classes, as the ids a caller asks for. Not every id is in all three:
## `expression_ids` is the two channels and `composure_ids` is their answers, so
## "what can this build project" and "what can answer it" are separate questions.
const ROLE_CONTROL := MindVocabulary.ROLE_CONTROL
const ROLE_EXPRESSION := MindVocabulary.ROLE_EXPRESSION
const ROLE_COMPOSURE := MindVocabulary.ROLE_COMPOSURE

static var shared: MindStatusCatalog = null

var _definitions: Dictionary = {}
var _ids: Array[StringName] = []
var _rejected: Dictionary = {}
var _loaded: bool = false


static func instance() -> MindStatusCatalog:
	if shared == null:
		shared = MindStatusCatalog.new()
	return shared


## Drop the cache so an authored file can be re-read in a long session. Tests call
## this after authoring a def in code; the game never needs it, because a `.tres`
## is immutable for the length of a run.
func reload() -> void:
	_definitions.clear()
	_ids.clear()
	_rejected.clear()
	_loaded = false


## Every accepted id, canonically ordered.
func ids() -> Array[StringName]:
	_ensure_loaded()
	return _ids.duplicate()


## One def, or null. Null rather than a guess: an unknown id is a content or
## call-site bug and inventing a definition would hide it.
func definition(status_id: StringName) -> MindStatusDef:
	_ensure_loaded()
	if status_id == &"":
		return null
	return _definitions.get(String(status_id), null)


func has(status_id: StringName) -> bool:
	return definition(status_id) != null


## Every id of one role, canonically ordered. A caller building a menu wants the
## channels or the answers, never the union — the union is a list of everything a
## mind cultivator can do to someone, which is not a question anyone asks.
func ids_of_role(role: StringName) -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for status_id in _ids:
		var def := _definitions[String(status_id)] as MindStatusDef
		if def != null and def.role == role:
			out.append(status_id)
	return out


## Every id projecting or answering `channel`. An `expression` and its `composure`
## are the two halves of one pair, so one question names both and a screen that
## wants "everything about the voice channel" gets exactly that.
func ids_of_channel(channel: StringName) -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for status_id in _ids:
		var def := _definitions[String(status_id)] as MindStatusDef
		if def != null and def.channel() == channel:
			out.append(status_id)
	return out


## Ids whose defs exist on disk but were refused, with the reason. Reported rather
## than dropped, because the failure the gate prevents is a status nobody can see.
func rejected() -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for status_id in _sorted_keys(_rejected.keys()):
		out.append({"id": status_id, "reason": String(_rejected[status_id])})
	return out


## Every defect that must stop a def from reaching play, across the whole tree.
## The per-def half is `MindStatusDef.problems()`; the two cross-def halves are
## the PAIRING and the duplicate id, both of which cannot live in it.
func problems() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for status_id in _sorted_keys(_definitions.keys()):
		for problem in (_definitions[status_id] as MindStatusDef).problems():
			out.append("%s: %s" % [String(status_id), problem])
	out.append_array(_pairing_defects())
	return out


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in ContentScan.files_under(MIND_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains('script_class="%s"' % DEF_SCRIPT_CLASS):
			continue
		var def := load(path) as MindStatusDef
		if def == null or def.id == &"":
			continue
		_admit(def, path)


func _admit(def: MindStatusDef, origin: String) -> bool:
	var key := String(def.id)
	var found := def.problems()
	if not found.is_empty():
		_rejected[key] = "%s (%s)" % [String(found[0]), origin]
		return false
	if _definitions.has(key):
		_rejected[key] = "duplicate id, also defined at %s" % origin
		return false
	_definitions[key] = def
	_ids.append(def.id)
	_ids.sort()
	return true


## ## The yin-yang gate, and why it is CROSS-def
##
## An `expression` names the `composure` that answers it and a `composure` names
## the `expression` it answers, but neither can check the other at load time: the
## pair lives in two files and this loader visits them in alphabetical order, so the
## first one to load would be judging a tree half-built.
##
## So the pairing is checked ONCE over the settled set, and an unpaired half is
## REFUSED rather than reported as a warning. A projectile nobody can answer is the
## same defect class as a status with empty `mitigation_tags`, which ADR 0075
## already refuses rather than ships.
func _pairing_defects() -> Array[String]:
	var out: Array[String] = []
	for status_id in _sorted_keys(_definitions.keys()):
		var def := _definitions[status_id] as MindStatusDef
		var pair := def.counterpart_id()
		if pair == &"":
			continue
		if pair == def.id:
			out.append("%s: names ITSELF as its own counterpart" % String(status_id))
			continue
		var other := _definitions.get(String(pair), null) as MindStatusDef
		if other == null:
			out.append(
				(
					"%s names counterpart '%s', which is not a mind status in this tree"
					% [String(status_id), String(pair)]
				)
			)
			continue
		if other.role == def.role:
			out.append(
				(
					(
						"%s (%s) is paired with %s, which is also a %s; a pair is an expression "
						+ "and its composure"
					)
					% [String(status_id), String(def.role), String(pair), String(other.role)]
				)
			)
			continue
		if other.counterpart_id() != def.id:
			(
				out
				. append(
					(
						(
							"%s names counterpart '%s' but that def names '%s' instead: a pair must "
							+ "point at each other, or one side is unpaired in a way no single file sees"
						)
						% [String(status_id), String(pair), String(other.counterpart_id())]
					)
				)
			)
	return out


## Deterministic iteration over a Dictionary's keys.
func _sorted_keys(keys: Array) -> Array:
	var out: Array = keys.duplicate()
	out.sort()
	return out
