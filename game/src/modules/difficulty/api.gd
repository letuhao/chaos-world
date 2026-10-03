class_name DifficultyApi
extends RefCounted

## Public facade for the `difficulty` module (ADR 0129). Other modules may reference ONLY this
## file (`api.gd`).
##
## ## What difficulty is allowed to move
##
## **A fraction of what the player already holds. Never a magnitude the game computes.** The
## five scalars are all multipliers or caps on player-side quantities; nothing here may scale a
## realm, a cultivation rate, a damage share or a pool maximum. That is not a style preference
## — this repo has three power-shaped tables and a written rule that a fourth needs an ADR,
## because reading one number as two is what produced the realm power ladder in the first place.
## The forbidden list, each entry with the ADR behind it, is in ADR 0129 §Consequences.
##
## ## Why a module and not `core/`
##
## `core/` is for shared math and primitives; `AGENTS.md` forbids feature logic there and
## changing `core/` requires an ADR. A difficulty dial is a player-facing setting with one reason
## to change. And not `app/`: the selected id persists into `module_data`, which is exactly the
## `APP_STATE_MARKERS` shape the arch gate warns about, and `app/` is the composition root that
## wires rather than owns rules.
##
## ## Why `scalars()` is one verb and not five
##
## Fifteen modules already sit at `MAX_FACADE_PUBLIC_METHODS`. A per-scalar getter would spend
## four of twelve slots answering one question, so every consumer reads the row instead.

## The `actor.module_data` key the selection persists under (ADR 0027).
const MODULE_KEY := DifficultyState.MODULE_KEY


## Attach the module to `actor`: restore and normalize whatever a prior `Actor.from_dict`
## carried, so the very first read after a load is the same shape as every other read.
## Idempotent, and safe before a difficulty has been chosen.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(MODULE_KEY, DifficultyState.normalize(actor.get_module_data(MODULE_KEY)))


## Choose `difficulty_id` for `actor`. The one setter.
##
## Refuses `no_actor` and `unknown_difficulty` and names the id back, so a caller cannot
## quietly leave a run on a difficulty nothing defines — which would resolve to the neutral row
## and look like the middle option rather than like a bug.
static func select(actor: Actor, difficulty_id: StringName) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor", "difficulty_id": ""}
	if not DifficultyCatalog.instance().ids().has(difficulty_id):
		return {
			"ok": false,
			"reason": "unknown_difficulty",
			"difficulty_id": String(difficulty_id),
		}
	actor.set_module_data(
		MODULE_KEY, DifficultyState.normalize({"difficulty_id": String(difficulty_id)})
	)
	return {"ok": true, "reason": "", "difficulty_id": String(difficulty_id)}


## The difficulty this actor is playing under. The neutral preset when none was chosen or when
## the actor is null, so every read has an answer.
static func current_id(actor: Actor) -> StringName:
	if actor == null:
		return DifficultyTable.NEUTRAL
	var pending: Dictionary = actor.get_module_data(MODULE_KEY)
	return StringName(DifficultyState.normalize(pending)["difficulty_id"])


## Every scalar a consumer may scale, in ONE read. Primitives only, and `{}` with no actor.
##
## This is the whole consumer contract: a module that needs a difficulty number asks for the
## row and reads the one scalar it cares about. There is deliberately no setter per scalar — a
## consumer could then write a difficulty number into its own arithmetic, which is the second
## power curve this ADR exists to prevent.
static func scalars(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	return DifficultyCatalog.instance().scalars_for(current_id(actor))


## The preset rows as primitives, for a settings screen. Never a `DifficultyTable` handed to
## `ui/`: a screen receives dictionaries, and a Resource would be an edge the gate has not
## granted.
static func views() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for difficulty_id in DifficultyCatalog.instance().ids():
		var row := DifficultyCatalog.instance().scalars_for(difficulty_id)
		var view := {"difficulty_id": String(difficulty_id)}
		for scalar in DifficultyTable.SCALARS:
			view[scalar] = float(row[scalar])
		out.append(view)
	return out


## Content audit: the table is shaped correctly. The same shape the Python guard asserts, so a
## GDScript test can fail on a content error without spawning a tool run.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	var catalog := DifficultyCatalog.instance()
	if not catalog.is_loaded():
		problems.append("difficulty: no authored table loaded")
		return problems
	var rows := catalog.rows()
	for difficulty_id in rows.keys():
		var row = rows[difficulty_id]
		if not (row is Dictionary):
			problems.append("difficulty: %s is not a row" % difficulty_id)
			continue
		for scalar in DifficultyTable.SCALARS:
			if not (row as Dictionary).has(scalar):
				problems.append("difficulty: %s is missing %s" % [difficulty_id, scalar])
				continue
			var value := float((row as Dictionary)[scalar])
			if not is_finite(value):
				problems.append("difficulty: %s.%s is not finite" % [difficulty_id, scalar])
			elif value < DifficultyTable.MIN_SCALAR or value > DifficultyTable.MAX_SCALAR:
				problems.append("difficulty: %s.%s is outside the bounds" % [difficulty_id, scalar])
		for key in (row as Dictionary).keys():
			if not DifficultyTable.SCALARS.has(String(key)):
				problems.append(
					"difficulty: %s carries an unknown column %s" % [difficulty_id, key]
				)
	if not rows.has(String(DifficultyTable.NEUTRAL)):
		problems.append("difficulty: the neutral preset is missing")
	return problems
