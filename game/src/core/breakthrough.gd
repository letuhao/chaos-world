class_name Breakthrough
extends RefCounted

## Advances a cultivation path one realm along the shared ladder when its
## BreakthroughCondition is met. The core orchestrates and rescales; per-system
## conditions are supplied by modules (ADR 0003/0005).
##
## For Immortal+ tiers the ladder is gated by the systems built in ADR 0018
## (inside world), ADR 0019 (world creation), ADR 0020 (tribulation) and ADR
## 0021 (ascension). Use try_advance_gated to apply every applicable gate; the
## single-gate helpers below are for isolated checks and tests.

## First realm index of the Immortal tier (ADR 0005: realms 19-27, 1-based).
const IMMORTAL_REALM_THRESHOLD := 18
## First realm index of the Transcendent tier (ADR 0005: realms 28-30, 1-based).
const TRANSCENDENT_REALM_THRESHOLD := 27


static func can_advance(
	actor: Actor,
	path_id: StringName,
	condition: BreakthroughCondition = null,
	context: Dictionary = {}
) -> bool:
	var state := actor.path(path_id)
	if state == null:
		return false
	if condition != null and not condition.can_breakthrough(actor, state, context):
		return false
	return RealmDefaults.ladder().next(state.rank_id) != null


static func try_advance(
	actor: Actor,
	path_id: StringName,
	condition: BreakthroughCondition = null,
	context: Dictionary = {}
) -> bool:
	if not can_advance(actor, path_id, condition, context):
		return false
	var state := actor.path(path_id)
	var next_realm := RealmDefaults.ladder().next(state.rank_id)
	state.rank_id = next_realm.id
	state.stage += 1
	state.progress = 0.0
	RealmScaling.apply(actor)
	actor.path_advanced.emit(path_id, next_realm.id)
	return true


# --- Gate predicates -------------------------------------------------------
# Each returns true when its own requirement holds for the target realm, or
# when that tier does not require it.


## Survive the tribulation fought for the realm being entered (ADR 0020). One
## survivor unlocks only its own gate: a tribulation bound to another realm, or
## to none at all (legacy payload), must be re-fought. A fight that merely ran to
## its last phase has not been survived either: only a decided win opens a gate.
static func tribulation_ok(actor: Actor, next_index: int) -> bool:
	if next_index < IMMORTAL_REALM_THRESHOLD:
		return true
	if actor.tribulation == null or not actor.tribulation.survived():
		return false
	return actor.tribulation.matches_realm(_realm_id_at(next_index))


## Begin the tribulation for the realm this actor is about to enter, binding it
## to that realm (ADR 0032). This is the production entry point: without it a
## high-tier gate can never be satisfied, because nothing else constructs a
## bound tribulation. Lives beside `tribulation_ok` so the rule that consumes a
## survivor and the way to earn one cannot drift apart.
##
## Returns the started tribulation, or null when the next realm needs none or a
## bound one is already in progress. Re-beginning an unfinished tribulation
## would discard the waves already survived, so the caller must `advance_tribulation`
## to completion, `cancel_tribulation`, or let the save carry it.
static func begin_tribulation(actor: Actor, next_index: int) -> Tribulation:
	if next_index < IMMORTAL_REALM_THRESHOLD:
		return null
	if actor.tribulation != null and not actor.tribulation.is_complete():
		return actor.tribulation
	# A decided record is replaced: the survivor of one realm must not stand in for
	# the next, and a fresh fight is the only way to earn that one.
	var tribulation := Tribulation.new()
	tribulation.start(actor, _realm_id_at(next_index))
	actor.tribulation = tribulation
	return tribulation


## Advance the in-progress tribulation by one wave. Returns true while the
## tribulation is still running, false once it is complete or there is none.
static func advance_tribulation(actor: Actor) -> bool:
	if actor.tribulation == null or actor.tribulation.is_complete():
		return false
	actor.tribulation.advance_wave()
	return not actor.tribulation.is_complete()


## Fight the in-progress tribulation to its end, returning whether the actor
## survived. Applies the result (ADR 0020) and clears it, so the gate is left
## to `tribulation_ok`. A tribulation is only ever resolved by an explicit
## outcome: nothing infers survival from reaching the last phase.
static func resolve_tribulation(actor: Actor, success: bool) -> bool:
	if actor.tribulation == null or not actor.tribulation.is_complete():
		return false
	actor.tribulation.apply_result(actor, success)
	return success


## Abandon an in-progress tribulation without resolving it. The waves survived
## are forfeited, so the gate stays closed; nothing is granted and nothing is
## lost, which is what lets a player walk away from a fight they cannot win.
static func cancel_tribulation(actor: Actor) -> void:
	actor.tribulation = null


## Entering R19 *commits* the Seed inside world, so R19 must not require it as a
## prerequisite — that was circular and left the gate permanently unsatisfiable
## for any path that did not hand-forge the flag. The inside world is required
## from the tier after the one that commits it, which `WorldAnchor.stage_met`
## encodes (ADR 0018-0021).
static func inside_world_ok(actor: Actor, next_index: int) -> bool:
	return WorldAnchor.stage_met(actor, next_index)


static func world_ok(actor: Actor, next_index: int) -> bool:
	if next_index <= WorldAnchor.COMMIT_MICRO:
		return true
	return actor.world != null and actor.world.is_stable()


static func ascension_ok(actor: Actor, next_index: int) -> bool:
	if next_index <= WorldAnchor.COMMIT_MICRO:
		return true
	return actor.ascension != null and actor.ascension.is_complete()


## Every tier gate the target realm requires, in one call. Per-system conditions
## delegate here so module code and core cannot drift apart.
static func tier_gates_met(actor: Actor, next_index: int) -> bool:
	return (
		tribulation_ok(actor, next_index)
		and inside_world_ok(actor, next_index)
		and world_ok(actor, next_index)
		and ascension_ok(actor, next_index)
	)


# --- Entry points ----------------------------------------------------------


## Cumulative breakthrough gate. Applies every gate the target realm tier
## requires (ADR 0018/0019/0020/0021):
##   - Immortal+ (next index >= 18): survived tribulation + stable inside world
##   - Transcendent+ (next index >= 27): + stable world + completed ascension
static func try_advance_gated(
	actor: Actor,
	path_id: StringName,
	condition: BreakthroughCondition = null,
	context: Dictionary = {}
) -> bool:
	var next_index := _next_index(actor, path_id)
	if next_index < 0:
		return false
	if not tribulation_ok(actor, next_index):
		return false
	if not inside_world_ok(actor, next_index):
		return false
	if not world_ok(actor, next_index):
		return false
	if not ascension_ok(actor, next_index):
		return false
	return try_advance(actor, path_id, condition, context)


## Advance gated by tribulation survival only (ADR 0020).
static func try_advance_with_tribulation(
	actor: Actor,
	path_id: StringName,
	condition: BreakthroughCondition = null,
	context: Dictionary = {}
) -> bool:
	return _try_with_gate(actor, path_id, condition, context, tribulation_ok)


## Advance gated by a stable inside world only (ADR 0018).
static func try_advance_with_inside_world(
	actor: Actor,
	path_id: StringName,
	condition: BreakthroughCondition = null,
	context: Dictionary = {}
) -> bool:
	return _try_with_gate(actor, path_id, condition, context, inside_world_ok)


## Advance gated by a stable created world only (ADR 0019).
static func try_advance_with_world(
	actor: Actor,
	path_id: StringName,
	condition: BreakthroughCondition = null,
	context: Dictionary = {}
) -> bool:
	return _try_with_gate(actor, path_id, condition, context, world_ok)


## Advance gated by completed ascension only (ADR 0021).
static func try_advance_with_ascension(
	actor: Actor,
	path_id: StringName,
	condition: BreakthroughCondition = null,
	context: Dictionary = {}
) -> bool:
	return _try_with_gate(actor, path_id, condition, context, ascension_ok)


# --- Internals -------------------------------------------------------------


## Index of the realm this path would advance into, or -1 if it cannot advance.
static func _next_index(actor: Actor, path_id: StringName) -> int:
	var state := actor.path(path_id)
	if state == null:
		return -1
	var next_realm := RealmDefaults.ladder().next(state.rank_id)
	if next_realm == null:
		return -1
	return RealmDefaults.ladder().index_of(next_realm.id)


## Realm id at a ladder position, or empty when the position is off-ladder.
static func _realm_id_at(index: int) -> StringName:
	var realms := RealmDefaults.ladder().realms()
	if index < 0 or index >= realms.size():
		return &""
	return realms[index].id


static func _try_with_gate(
	actor: Actor,
	path_id: StringName,
	condition: BreakthroughCondition,
	context: Dictionary,
	gate: Callable
) -> bool:
	var next_index := _next_index(actor, path_id)
	if next_index < 0:
		return false
	if not gate.call(actor, next_index):
		return false
	return try_advance(actor, path_id, condition, context)
