class_name Breakthrough
extends RefCounted

## Advances a cultivation path one realm along the shared ladder when its
## BreakthroughCondition is met. The core orchestrates and rescales; per-system
## conditions are supplied by modules (ADR 0003/0005).
##
## `try_advance` also COMMITS the milestone that entering a realm produces, via
## `WorldAnchor.commit`. It used to be two hand-written calls, one each in the body
## and qi resolve paths, and the mind resolve path did not have one — which left
## `actor.ascension` permanently null on that path and `ascension_ok` permanently
## false there: an R29 no player action could ever open. `try_advance` is the one
## call all three paths already reach on success, so the milestone now has one owner
## and no path can forget it (ADR 0018-0021, ADR 0041, and the ADR 0066 shape it
## replaces). `commit` is idempotent, so a path that also commits costs nothing.
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
	WorldAnchor.commit(actor, RealmDefaults.ladder().index_of(next_realm.id))
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


## Resolve the in-progress tribulation with an explicit verdict, returning whether
## the actor is a survivor. A tribulation is only ever resolved by an explicit
## outcome: nothing infers survival from reaching the last phase.
##
## The guard is `outcome == OUTCOME_UNRESOLVED`, NOT `is_complete()` (ADR 0041/0061).
## A record that ran to its last phase is still undecided, and ADR 0041 claimed this
## function idempotent while guarding only on the phases — so a second call re-paid the
## award. Returns the record's STANDING outcome, not the argument: a caller that passed
## `true` for a fight it had already lost is told it lost.
static func resolve_tribulation(actor: Actor, success: bool) -> bool:
	if actor.tribulation == null or not actor.tribulation.is_complete():
		return false
	if actor.tribulation.outcome == Tribulation.OUTCOME_UNRESOLVED:
		actor.tribulation.apply_result(actor, success)
	return actor.tribulation.survived()


## Abandon an in-progress tribulation without resolving it. The waves survived
## are forfeited, so the gate stays closed; nothing is granted and nothing is
## lost, which is what lets a player walk away from a fight they cannot win.
static func cancel_tribulation(actor: Actor) -> void:
	actor.tribulation = null


## The production entry point for the tribulation gate: answer whether `path_id` is
## stopped by a tribulation, and if it is, descend ONE wave of the fight it owes.
##
## THE CALL THAT DESCENDS NEVER OPENS THE GATE. The return is the gate as it stood
## *before* this call, so the survivor a wave wins is opened by the *next* attempt.
## That is what stops the gate from requiring an artifact the same call produces: one
## "face it" press could otherwise win the fight and spend the reward in a single
## step, and a loop over this function would report success on the wave that earned
## the win instead of on the attempt that spends it.
##
## One wave per call, because a tribulation is an encounter with turns rather than
## one opaque check. `rng` makes the deciding roll a caller's choice; null uses the
## engine's.
##
## Path-scoped on purpose: it answers "is THIS path owed a fight", not "is any
## enrolled path owed one". The slot holds one record, so a hero with two paths past
## the Immortal tier is owed the lower of the two gates first.
##
## Below the Immortal tier, and at the top of the ladder where no realm remains, this
## is a no-op that reports true: no tribulation stands in front of that path.
static func face_tribulation(
	actor: Actor, path_id: StringName, rng: RandomNumberGenerator = null
) -> bool:
	var next_index := _next_index(actor, path_id)
	if next_index < 0 or tribulation_ok(actor, next_index):
		return true
	if begin_tribulation(actor, next_index) == null:
		return tribulation_ok(actor, next_index)
	_fight_one_wave(actor, rng)
	return false


## Descend one wave of the fight, which is also where the verdict is taken: charging
## the wave toll and rolling the deciding wave belong to the record, so a caller cannot
## descend a wave for free or decide a fight without paying for it (ADR 0061).
## Re-entered freely: a decided record is left exactly as it stands, which is why
## calling this again on a finished fight is a no-op rather than a second verdict.
static func _fight_one_wave(actor: Actor, rng: RandomNumberGenerator) -> void:
	if actor.tribulation == null:
		return
	actor.tribulation.fight_wave(actor, rng)


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


## ## Past the last realm, nothing is owed
##
## The terminal realm commits the Great world and no realm follows it, so there is
## no next breakthrough for the ascent to gate. A caller that asks about the index
## one past the end is asking about a realm that does not exist, and the honest
## answer is that it owes nothing — not that the actor still has an unwalked ascent
## on the record. Without this the terminal realm reads as permanently owing a
## gate nothing will ever call, which is the same circular gate ADR 0018-0021 and
## ADR 0058 removed twice already.
static func ascension_ok(actor: Actor, next_index: int) -> bool:
	if next_index <= WorldAnchor.COMMIT_MICRO:
		return true
	if next_index >= RealmDefaults.ladder().size():
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
