class_name StatusCatalog
extends RefCounted

## The authored status content tree, loaded once and cached (ADR 0090).
##
## Definitions live in `res://data/statuses/` as ordinary `.tres` `StatusDef`
## resources, loaded the way `TechniqueCatalog` and `BloodlineCatalog` load theirs:
## a directory walk for `.tres`, a `script_class=` text check so a foreign resource in
## the same folder is skipped rather than mis-cast, then the declared `id` as the key.
## Resolution is by id, never by filename, so renaming a file does not retire a
## technique that authored it.
##
## ## ALL TEN ELEMENTS
##
## Twenty statuses ship: two on each of the ten authored elements. ADR 0090 originally
## withheld the ten tier-2 defs because `ElementDefaults.advanced()` measures strictly
## dominant on every row; **ADR 0110 lifts that clause** now that the `TIER_MASTERY_STEP`
## divisor (`modules/elements/provider.gd`) taxes tier 2 at the provider instead of by
## withholding content. The tier-2 matchup rows were never "fixed" — they are corrected
## where they are read.
##
## The element gate still exists, and it still refuses: an element outside
## [constant StatusDef.AUTHORED_ELEMENTS] is a load-time rejection rather than a status that
## loads and silently never applies. A refused def is still REPORTED by [method rejected] so a
## designer who authors one finds out which file to delete.
##
## Loading is deterministic: files are walked in sorted order and ids are returned
## sorted, so a catalogue report is a fixed list rather than a filesystem artifact.
## Nothing here rolls a die.

## The element-riding catalogue: two statuses on each of the ten authored elements,
## exactly twenty ids, every one of them inflicted by a landed blow that names an element
## (ADR 0090, ADR 0110). Nothing may be added here without a decision, and
## `tests/modules/status/test_status_catalogue.gd` pins the id SET rather than a size.
const STATUSES_ROOT := "res://data/statuses"
const STATUS_SCRIPT_CLASS := "StatusDef"

## The AMBIENT tree: statuses inflicted by the actor STANDING IN something rather than by
## a blow. ADR 0075's environment hazard (`env_scourge`) and ADR 0073's traps are the two
## producers, and their defs are authored by the module that owns the place — which is why
## they live under that module's `res://src/data/` and not here.
##
## ## This is a SECOND namespace, not a second entry in the first
##
## [method status_ids] and [method definition] answer the closed twenty, unchanged and
## with no second opinion. An ambient def is reachable only through
## [method ambient_definition], which is what keeps the set a landed blow can inflict a
## set of ELEMENT-BOUND statuses — the twenty cannot be diluted by a place, and the
## id-pinning test in the status module's own suite stays true without being edited.
##
## ## The two trees are read by ONE loader and ONE gate
##
## Both run the same `StatusDef.problems()` and the same [method _admit], so an ambient
## def gets no softer authoring rules than a catalogue one: it still publishes non-empty
## `mitigation_tags` (ADR 0075 refuses a hazard nothing answers to), still resolves a
## channel, and still carries a positive cadence. What it is exempt from is exactly one
## rule — the element a blow carries — because it is not a blow.
const AMBIENT_SOURCES_ROOT := "res://src/data/statuses"

static var shared: StatusCatalog = null

var _definitions: Dictionary = {}
var _ids: Array[StringName] = []
var _ambient: Dictionary = {}
var _ambient_ids: Array[StringName] = []
var _rejected: Dictionary = {}
var _loaded: bool = false


static func instance() -> StatusCatalog:
	if shared == null:
		shared = StatusCatalog.new()
	return shared


## Drop the cache so an authored file can be re-read in a long session. Tests call
## this after authoring a def in code; the game never needs it, because a `.tres` is
## immutable for the length of a run.
func reload() -> void:
	_definitions.clear()
	_ids.clear()
	_ambient.clear()
	_ambient_ids.clear()
	_rejected.clear()
	_loaded = false


## Every accepted status id, canonically ordered.
func status_ids() -> Array[StringName]:
	_ensure_loaded()
	return _ids.duplicate()


## The definition behind a status id, or null. Null rather than a guess: an unknown
## id is a content or call-site bug, and inventing a definition would hide it.
##
## The CLOSED TWENTY only. An ambient def is not here and never will be — this answers
## "what does a landed blow inflict", and [method ambient_definition] answers "what does
## standing there inflict".
func definition(status_id: StringName) -> StatusDef:
	_ensure_loaded()
	if status_id == &"":
		return null
	return _definitions.get(String(status_id), null)


## One AMBIENT def — a status inflicted by a place rather than by a blow — or null.
## Same refusal shape as [method definition]: null rather than a guess.
func ambient_definition(status_id: StringName) -> StatusDef:
	_ensure_loaded()
	if status_id == &"":
		return null
	return _ambient.get(String(status_id), null)


## Every accepted ambient status id, canonically ordered.
func ambient_ids() -> Array[StringName]:
	_ensure_loaded()
	return _ambient_ids.duplicate()


## One def from EITHER tree, ambient first.
##
## ## Why one answer and not two
##
## The tick path asks "which def pays this instance", and the caller that built the
## instance knows only its id — an ADR 0075 zone mints `env_scourge` from its own
## `.tres` and never asks which tree it came from. Collapsing the lookup here means
## [method StatusApi.resolve] has exactly one lookup rather than a branch, and means a
## def whose module later moves it from `res://src/data` into the catalogue needs no
## caller change.
##
## A CATALOGUE id wins a collision rather than the ambient one, so a future move of
## `env_scourge` into `res://data/statuses` changes nothing for a caller.
func any_definition(status_id: StringName) -> StatusDef:
	var found := definition(status_id)
	if found != null:
		return found
	return ambient_definition(status_id)


func has(status_id: StringName) -> bool:
	return definition(status_id) != null


## Ids whose defs exist on disk but were refused, with the reason. Reported rather
## than dropped, because the failure the ADR prevents is a status nobody can see.
## Returns an empty array for a well-formed tree.
func rejected() -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for status_id in _sorted_keys(_rejected.keys()):
		out.append({"id": status_id, "reason": String(_rejected[status_id])})
	return out


## Every defect that must stop a def from reaching play, across the whole tree.
##
## Two of these are CROSS-def and so cannot live in `StatusDef.problems()`: one
## element naming more than one landed-blow status, and one id authored twice. Both are
## reported here against the ids that caused them, because refusing them HERE means a
## collision is a load-time authoring error like any other — visible through
## [method rejected] — rather than something silently resolved by whichever row the
## catalogue happened to walk first.
func problems() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for status_id in _sorted_keys(_definitions.keys()):
		for problem in (_definitions[status_id] as StatusDef).problems():
			out.append("%s: %s" % [String(status_id), problem])
	# The ambient tree is held to the SAME gate, so it is reported by the same question.
	# A module that only ever ran this over `_definitions` would call a clean hazard tree
	# clean while an authored hazard in it was refused — which is the silence this method
	# exists to prevent, just one namespace over.
	for status_id in _sorted_keys(_ambient.keys()):
		for problem in (_ambient[status_id] as StatusDef).problems():
			out.append("%s: %s" % [String(status_id), problem])
	out.append_array(_landed_blow_collisions())
	return out


## Elements claimed by more than one authored `on_landed_blow` status, one line each.
##
## ## Why a collision is a refusal and never a tie-break
##
## Every tier-1 element ships TWO statuses (ADR 0090), so "the status a landed fire blow
## inflicts" is genuinely ambiguous unless exactly ONE of the pair claims the slot.
## Taking the first in catalogue order would make the game's debuff a function of
## filename alphabetical order — `fire_immolation` before `fire_pyre` today, and reversed
## the moment someone renames a file. So the loader reports the collision instead, and
## [method StatusApi.status_for_element] is only ever asked a question with one answer.
func _landed_blow_collisions() -> Array[String]:
	var claimed: Dictionary = {}
	for status_id in _sorted_keys(_definitions.keys()):
		var def := _definitions[status_id] as StatusDef
		if not def.on_landed_blow:
			continue
		var key := String(def.element)
		var existing: Array = claimed.get(key, [])
		existing.append(String(def.id))
		claimed[key] = existing
	var out: Array[String] = []
	for key in _sorted_keys(claimed.keys()):
		var ids: Array = claimed[key]
		if ids.size() < 2:
			continue
		out.append(
			(
				(
					"element '%s' is claimed by more than one landed-blow status (%s); a blow "
					+ "carries one element, so exactly one may claim it (ADR 0105)"
				)
				% [String(key), String(", ").join(ids)]
			)
		)
	return out


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in _scan(STATUSES_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % STATUS_SCRIPT_CLASS
		):
			continue
		var def := load(path) as StatusDef
		if def == null or def.id == &"":
			continue
		_admit(def, path)
	for path in _scan(AMBIENT_SOURCES_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % STATUS_SCRIPT_CLASS
		):
			continue
		var def := load(path) as StatusDef
		if def == null or def.id == &"":
			continue
		_admit_ambient(def, path)


## Accept a def only if it is well-formed and tier-1. `register` is the escape hatch
## for a caller that composes a status in code (a test, a quest reward): it runs the
## same gate, so a def cannot be injected past the refusal the content tree gets.
func register(def: StatusDef) -> bool:
	if def == null:
		return false
	return _admit(def, "<registered>")


## The ambient half of the gate: the SAME [method StatusDef.problems], a separate
## namespace. Split out rather than folded into `_admit` so the only difference between
## a catalogue admission and an ambient one is WHERE the accepted id lands — a second
## `if` inside `_admit` would be one more place for the two to disagree.
##
## ## An ambient def must CLAIM to be ambient, and must NOT claim to ride a blow
##
## The first is `problems()`'s element rule, made conditional on `ambient`. The second is
## this file's: a def in the ambient tree that also sets `on_landed_blow` is an authoring
## contradiction — it would be reachable from `status_for_element` while living outside
## the tree that walk reads, which is a status nothing can find. Refused and REPORTED
## through [method rejected], like every other authoring error here.
func _admit_ambient(def: StatusDef, origin: String) -> bool:
	var key := String(def.id)
	var found := def.problems()
	if not found.is_empty():
		_rejected[key] = "%s (%s)" % [String(found[0]), origin]
		return false
	if not def.ambient:
		_rejected[key] = (
			(
				"an element-riding status authored under the ambient tree %s; a landed blow "
				+ "inflicts one of the catalogue's twenty"
			)
			% origin
		)
		return false
	if def.on_landed_blow:
		_rejected[key] = (
			(
				"claims `on_landed_blow` from the ambient tree %s, so a landed blow would "
				+ "inflict a status the catalogue walk cannot reach"
			)
			% origin
		)
		return false
	if _ambient.has(key) or _definitions.has(key):
		_rejected[key] = "duplicate id, also defined at %s" % origin
		return false
	_ambient[key] = def
	_ambient_ids.append(def.id)
	_ambient_ids.sort()
	return true


func _admit(def: StatusDef, origin: String) -> bool:
	var key := String(def.id)
	var found := def.problems()
	if not found.is_empty():
		_rejected[key] = "%s (%s)" % [String(found[0]), origin]
		_definitions.erase(key)
		_ids.erase(StringName(key))
		return false
	if _definitions.has(key):
		_rejected[key] = "duplicate id, also defined at %s" % origin
		return false
	_definitions[key] = def
	_ids.append(def.id)
	_ids.sort()
	return true


## Deterministic iteration over a Dictionary's keys. `Array.sort()` exists and
## `Array.sorted()` does not, and an unsorted key walk would make `rejected()` report
## in filesystem-insertion order — which is exactly the determinism ADR 0090 asks for.
func _sorted_keys(keys: Array) -> Array:
	var out: Array = keys.duplicate()
	out.sort()
	return out


## The element→status mapping of ADR 0105: the id whose def claims
## [member StatusDef.on_landed_blow] on `element`, or `&""` when nothing does.
##
## ## Why the walk is over SORTED ids
##
## This is the only place the choice between two authored candidates could be resolved,
## so it is resolved on the catalogue's canonical order rather than on the order
## `DirAccess` happened to hand back. `_landed_blow_collisions()` guarantees a well-formed
## tree has at most one candidate per element, so the order is not load-bearing today —
## it is here so that authoring a collision produces a REPORTED defect rather than a
## verdict that depends on the filesystem.
##
## `chance` is the caller's gate and is checked BEFORE the walk: ADR 0087's closed gate
## spends no draw, so an element whose status exists but whose chance is `0.0` is
## answered here rather than at a roll that will not be taken.
func status_for_element(element: StringName, chance: float = 1.0) -> StringName:
	if element == &"" or not is_finite(chance) or chance <= 0.0:
		return &""
	_ensure_loaded()
	var claim := _claimed_by(String(element))
	if claim.size() < 2:
		return StringName(claim[0]) if claim.size() == 1 else &""
	# Reached only by a tree [method problems] would report: report the ambiguity rather
	# than pick a winner, so a collision can never quietly become the shipped debuff.
	_rejected[claim[0]] = (
		"element '%s' is claimed by %s; a landed blow is ambiguous"
		% [String(element), String(", ").join(claim)]
	)
	return &""


## The ids claiming [member StatusDef.on_landed_blow] on `element`, in catalogue order.
## Empty for an element nobody claims; more than one is an authoring defect.
func _claimed_by(element: String) -> Array[String]:
	var out: Array[String] = []
	for status_id in _ids:
		var def := _definitions[String(status_id)] as StatusDef
		if def != null and def.on_landed_blow and String(def.element) == element:
			out.append(String(status_id))
	return out


## Every file under `root`, recursively, in sorted order, so two runs on the same tree
## produce the same catalogue order.
func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
