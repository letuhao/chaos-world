class_name MindMasteryState
extends RefCounted

## The live mastery ledger: two tracks, each a vector of use-counters keyed by the
## authored mind vocabulary. A plain component, saved through the actor's own
## component bag like `SeaOfConsciousness` — NOT `module_data`, for the reason
## `StatusRuntime` states: a status is session-only because a designer retune must
## never silently rewrite an old save, and a mastery number derived from uses is
## the same shape of "recomputable from what happened" with nothing hidden in it.
##
## ## Why a component and not a stat
##
## Because mastery is not a stat a build allocs: it is a RECORD of what this mind
## has done. A stat is read from attributes and modifiers; this is read from its
## own counters and is written by exactly one verb. Putting it in `ActorStats`
## would have made a ledger a derived value, and a derived value recomputed from
## attributes is precisely the tech-tree shape this design refuses.
##
## ## The ladder
##
## ```
## threshold(n) = (n + 1) * THRESHOLD_STEP          uses to reach step n+1
## level        = uses / threshold(level_step)       normalised to [0, 1]
## ```
##
## So an entry costs the SAME number of uses regardless of which track it is in,
## and the two tracks share one curve because a second authored number would drift
## (the same reason `RealmRate` is one curve for all three cultivation paths). What
## DIFFERENTIATES the tracks is not the ladder — it is the two spend currencies in
## `MindMastery`, which is where the design's actual difference lives.
##
## ## `bank` is the ONLY writer, and it is bounded by construction
##
## There is no `while` and no per-earn walk of the ladder: [method bank] adds uses
## and [method level] computes the step from them arithmetically, so a ledger with
## a million uses costs the same as one with ten. That is deliberate — the loop that
## "advances a level until the counter stops" is the shape `test_no_unbounded_wait`
## cannot see terminate from the outside, and it is the shape the 67 GB run had.

## The ladder step, as a share of the track's own cap.
##
## ## WHY IT IS RESTATED AND NOT ALIASED
##
## The obvious spelling is `const THRESHOLD_STEP := MindMastery.THRESHOLD_STEP`, and
## it is a parse error: `MindMastery` is a global class whose own body references this
## module's `MindMasteryState`, and a const initializer that needs a class resolution
## the class is still being declared in fails to compile — which cascaded into every
## dependant of this file before it was spelled.
##
## So the two are separate literals with a GUARD rather than an alias:
## `test_mind_mastery_streams.gd::test_the_two_ladder_steps_are_one_number` asserts
## they are equal. One authored number with a test, rather than one number and a
## compiler feature that would have worked.
const THRESHOLD_STEP := 0.04

## `track -> {key -> uses}`. A plain Dictionary keyed by `StringName`, never an
## array: a caller reads a track by name and an entry by the authored vocabulary id
## it was earned against, so a track or an id added later cannot renumber anything
## that already ships.
var uses: Dictionary = {}


func _init(p_uses: Dictionary = {}) -> void:
	if not p_uses.is_empty():
		uses = _normalized(p_uses)


## Bank uses against one track and one key. THE only writer, and there is no
## ceiling on the counter itself: the ladder is computed from it arithmetically, so
## an over-trained entry reads `1.0` level rather than needing a clamp-and-repeat.
func bank(track: StringName, key: StringName, amount: float) -> void:
	if amount <= 0.0 or track == &"" or key == &"":
		return
	var lane := _lane(track)
	var current := float(lane.get(key, 0.0))
	lane[key] = maxf(0.0, current + amount)
	uses[track] = lane


## The uses banked against one entry. `0.0` for an entry nothing has touched, which
## is the honest answer for an actor who has never used this channel — and NOT
## "no such entry", because a build that has never projected `intent` and one whose
## `intent` mastery was reset are different facts a screen must be able to tell.
func uses_of(track: StringName, key: StringName) -> float:
	var lane := _lane(track)
	return float(lane.get(key, 0.0))


## The uses required to reach the NEXT ladder step from here, or `0.0` at the cap.
## Published so a screen can render a bar without recomputing the ladder, and so a
## test can assert the loop terminated rather than trusting the level.
func uses_to_next(track: StringName, key: StringName) -> float:
	var held := uses_of(track, key)
	var step := int(floor(held / THRESHOLD_STEP)) + 1
	var threshold := float(step) * THRESHOLD_STEP
	return maxf(0.0, threshold - held)


## The ladder STEP an entry has reached — the integer index, NOT the normalised
## level. Exposed because it is the honest answer to "how far along is this" and
## because a level of `0.97` and a level of `0.03` are the same step while a test
## that compared levels alone could not tell them apart.
func step_of(track: StringName, key: StringName) -> int:
	return int(floor(uses_of(track, key) / THRESHOLD_STEP))


## The NORMALISED level for one entry, in `[0, 1]`: progress through the current
## step. `1.0` only when the entry is exactly on a step boundary, which is the
## `status_bonus` ceiling and the reason a mastery-maxed track still cannot make a
## contest certain — see `MindMastery.status_bonus`.
##
## Arithmetic, never a loop: `level = (held - step * STEP) / STEP`, with the step
## read from the same `THRESHOLD_STEP` the counter is divided by, so the two cannot
## disagree about where a step is.
func level(track: StringName, key: StringName) -> float:
	var held := uses_of(track, key)
	if held <= 0.0:
		return 0.0
	var step := float(step_of(track, key)) * THRESHOLD_STEP
	if step <= 0.0:
		return 0.0
	return clampf((held - step) / THRESHOLD_STEP, 0.0, 1.0)


## Every entry of one track, as `{key, uses, step, level, to_next}`. Sorted by key
## so a screen's row order is the same twice, and PRIMITIVES ONLY (AGENTS.md's
## testable contract) so no caller ever touches this object.
func rows_of(track: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lane := _lane(track)
	var keys := lane.keys()
	keys.sort()
	for key in keys:
		var id := StringName(key)
		(
			out
			. append(
				{
					"key": String(id),
					"uses": uses_of(track, id),
					"step": step_of(track, id),
					"level": level(track, id),
					"to_next": uses_to_next(track, id),
				}
			)
		)
	return out


## The JSON-safe payload a save carries. String keys throughout, because
## `Actor.to_dict` converts only its OWN keys and a `StringName` reaching the save
## would break the round trip (ADR 0027).
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for track in MindMastery.TRACKS:
		var rows: Array = []
		for row in rows_of(track):
			rows.append(row)
		out[String(track)] = {"entries": rows}
	return out


## Restore from [method to_dict]. A track or an entry the save names but this tree
## does not know is KEPT rather than dropped: a ledger that silently discards a
## future track's uses would make a downgrade lose progress with no error, which is
## the wrong failure. What is dropped is a malformed one — a non-numeric use count —
## because a ledger that banks `NaN` poisons every level derived from it.
static func from_dict(data: Dictionary) -> MindMasteryState:
	var state := MindMasteryState.new()
	if typeof(data) != TYPE_DICTIONARY:
		return state
	for track in MindMastery.TRACKS:
		var lane: Dictionary = {}
		var raw: Variant = (data as Dictionary).get(String(track), {})
		if raw is Dictionary:
			var entries: Variant = (raw as Dictionary).get("entries", [])
			if entries is Array:
				for entry in entries as Array:
					if not (entry is Dictionary):
						continue
					var key := StringName((entry as Dictionary).get("key", &""))
					var counted := float((entry as Dictionary).get("uses", 0.0))
					if key == &"" or not is_finite(counted) or counted <= 0.0:
						continue
					lane[key] = counted
		state.uses[track] = lane
	return state


func _lane(track: StringName) -> Dictionary:
	var existing: Variant = uses.get(track)
	if existing is Dictionary:
		return existing as Dictionary
	var fresh: Dictionary = {}
	uses[track] = fresh
	return fresh


## The constructor's copy, through the same filter `from_dict` applies — a caller
## passing a hand-built dictionary gets the same guarantees as a restored save.
static func _normalized(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for track in MindMastery.TRACKS:
		var lane: Dictionary = {}
		var raw: Variant = source.get(track, source.get(String(track), {}))
		if raw is Dictionary:
			for key in (raw as Dictionary).keys():
				var counted := float((raw as Dictionary)[key])
				if counted > 0.0 and is_finite(counted):
					lane[StringName(key)] = counted
		out[track] = lane
	return out
