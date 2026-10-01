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


static func tribulation_ok(actor: Actor, next_index: int) -> bool:
	if next_index < IMMORTAL_REALM_THRESHOLD:
		return true
	return actor.tribulation != null and actor.tribulation.is_complete()


static func inside_world_ok(actor: Actor, next_index: int) -> bool:
	if next_index < IMMORTAL_REALM_THRESHOLD:
		return true
	return actor.inside_world != null and actor.inside_world.is_stable()


static func world_ok(actor: Actor, next_index: int) -> bool:
	if next_index < TRANSCENDENT_REALM_THRESHOLD:
		return true
	return actor.world != null and actor.world.is_stable()


static func ascension_ok(actor: Actor, next_index: int) -> bool:
	if next_index < TRANSCENDENT_REALM_THRESHOLD:
		return true
	return actor.ascension != null and actor.ascension.is_complete()


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
