class_name BodyRealmSeed
extends Resource

## One destination realm's preparation, awards, and training ceiling (ADR 0023).
## Expanded with full profile factors: P/C/F/T, quality/integrity targets,
## work requirements, insight floor, resonance rank, and channel training.

@export var id: StringName = &""
@export var breakthrough_item: StringName = &""
@export var strengthening_item: StringName = &""
## Third consumable role: repairs deviation damage (injured channel, blocked
## acupoint). Blockage is a recoverable overlay, so a realm must also carry the
## means to clear it — otherwise a failed attempt is unrecoverable.
@export var recovery_item: StringName = &""
## The realm's labour budget, and the single place it is authored.
## `BodyBreakthroughCondition` gates on `state.progress` against this number and
## `BodyTraining.cultivate` accumulates into that same progress, so the price of a
## breakthrough and the gate that enforces it are one quantity by construction
## rather than two numbers kept equal by hand.
@export var progress_required: float = 100.0
@export var physique_required: float = 10.0
## The huyệt quality floor for entry, and the huyệt quality ceiling training can
## reach in the realm BELOW. They are not the same number, and the difference is
## the player's decision: `_acupoints_ready` demands the floor, `cultivate` pays
## out to the ceiling, and the gap between them is what a breakthrough roll buys.
## Pinning the floor onto the ceiling (as these two used to be, 0.400 and 0.400 at
## R1) left average huyệt quality at the moment of an attempt a single number on
## every realm, so acupoint quality could not enter the roll anywhere.
@export var quality_required: float = 0.5
@export var quality_target: float = 0.5
@export var integrity_target: float = 0.45
@export var required_meridians: Array[StringName] = []
@export var required_refinement: int = 1
@export var refinement_cap: int = 1
@export var integrity_maximum: float = 100.0
@export var rewards: Dictionary = {}
# Insight floor (comprehension requirement for entry).
@export var insight_required: float = 10.0
# Resonance rank (realms 19-30 reinforce the same network).
@export var resonance_rank: int = 0
# Breakthrough risk. `chance_base` is the floor the realm offers and
# `chance_cap` its ceiling; acupoint quality buys certainty between them.
# Neither is derived from comprehension: comprehension is the entry GATE
# (insight_required), so using it for the roll made every attempt from R5 on a
# guaranteed success and left the deviation/recovery system unreachable.
@export var chance_base: float = 0.55
@export var chance_cap: float = 0.95
# Channel training after entry (channels to train while in this realm).
@export var channel_training: Array[StringName] = []

## The labour budget under its profile name. Derived, not authored: this and
## `progress_required` are one number, and publishing both in every `.tres` meant
## the first edit to one of them silently desynced the gate from its own price.
var work_required: float:
	get:
		return progress_required

## The price of one full pass of every huyệt this realm has unlocked, cut from the
## budget against that huyệt count. Derived for the same reason as `work_required`:
## these two were byte-identical in all 30 seeds with no reader anywhere in `src/`,
## and a hand-maintained copy of a cut of the budget has nothing to say that
## computing it does not.
var acupoint_work: float:
	get:
		return _cut_budget(4 * maxi(1, ladder_index()))

## The price of one full pass of every channel step this realm allows, cut from the
## budget against one step per realm reached.
var meridian_work: float:
	get:
		return _cut_budget(4 * (ladder_index() + 1))

## This realm's position on the shared ladder, or 0 when it is not on it. Cached
## because the derived getters above call it and `RealmLadder.index_of` is a scan.
var _index_cache: int = -2


func ladder_index() -> int:
	if _index_cache == -2:
		_index_cache = maxi(0, RealmDefaults.ladder().index_of(id))
	return _index_cache


## The budget divided by `divisor`, rounded to whole labour units. `floorf(x + 0.5)`
## is GDScript's `roundf()`; Python's `round()` is banker's rounding and disagrees on
## an exact .5, which is why the generator's mirror of this rule is
## `ROUND_HALF_UP` rather than `round`.
func _cut_budget(divisor: int) -> float:
	return floorf(progress_required / float(maxi(1, divisor)) + 0.5)


static func for_realm(realm_id: StringName) -> BodyRealmSeed:
	if not RealmDefaults.ladder().has(realm_id):
		return null
	return load("res://data/body_cultivation/realms/%s.tres" % realm_id) as BodyRealmSeed
