class_name WeaponCounter
extends RefCounted

## The defence side of the pairing, and the guard that a weapon is never a strict
## best response (AGENTS.md: "no mechanic may be a strict best response").
##
## ## Why this is a separate table and not a field on the kind
##
## A weapon that can only be answered by reading the weapon's own `.tres` is a
## counter nobody can enumerate, so the pairing rule would be a review note rather
## than a gate. Here a defence names the demands it blunts and the demand it
## feeds, which lets `answer_of` answer "what beats this kind" from ONE list and
## lets `test_weapon_kinds_have_a_counter` refuse a kind nothing answers.
##
## ## The defence does not reduce the number; it eats the DEMAND
##
## `blunts` is a pair of demand ids. A guard trained against mass is not a bigger
## number than the maul: it is a body that is not paying the maul's bill, so the
## maul's practice buys less. That is why two kinds cannot be reduced to a single
## power ranking, and why the answer is a body to train rather than an item to buy.

const GUARD := &"guard"
const WARD := &"ward"
const FOOTING := &"footing"
const INTERCEPT := &"intercept"

## Defence id -> the demand it feeds (the body that answers by training) and the
## demands it blunts (the bodies it denies).
##
## ## Why the sets OVERLAP and CROSS, and why that is the design
##
## One demand per defence would make `answer_of` a permutation, and a permutation is
## not a counter: `greatsword` (MASS) and `chainwhip` (SPEED) would each be answered
## by exactly one defence while `tower_shield` (BRACE) was answered by nothing at
## all — a body nothing can beat, the failure AGENTS.md's yin-yang rule names. So a
## defence covers SEVERAL bodies and those covers cross: BALANCE is answered by
## `ward` and `intercept`, PRECISION by `footing` and `intercept`. The overlap is what
## `test_no_weapon_is_a_strict_best_response` reads, because every kind must be
## answered by something that does NOT answer at least one other kind.
const TABLE := {
	GUARD: {"blunts": [WeaponDemand.LEVERAGE, WeaponDemand.MASS], "feeds": WeaponDemand.BRACE},
	WARD:
	{
		"blunts": [WeaponDemand.MASS, WeaponDemand.SPEED, WeaponDemand.BRACE],
		"feeds": WeaponDemand.PRECISION,
	},
	FOOTING:
	{"blunts": [WeaponDemand.BALANCE, WeaponDemand.PRECISION], "feeds": WeaponDemand.BALANCE},
	INTERCEPT: {"blunts": [WeaponDemand.PRECISION], "feeds": WeaponDemand.SPEED},
}

const ALL: Array[StringName] = [GUARD, WARD, FOOTING, INTERCEPT]


## The demands `counter_id` blunts, or `[]` for a defence nothing declares.
static func blunts(counter_id: StringName) -> Array:
	var entry: Dictionary = TABLE.get(counter_id, {})
	var out: Array = []
	for demand in entry.get("blunts", []):
		out.append(StringName(demand))
	return out


## The demand a defender trains to answer `counter_id`, or `&""`.
static func feeds(counter_id: StringName) -> StringName:
	var entry: Dictionary = TABLE.get(counter_id, {})
	return entry.get("feeds", &"")


## The defence that answers `demand`, or `&""` when no authored defence blunts
## it. **`""` is a defect, not a rarity** — a demand nothing answers is a body
## that cannot be beaten, which is the exact failure AGENTS.md's yin-yang rule
## names — so the shipped set is written so this never returns empty and
## `test_every_demand_has_a_counter` proves it.
static func answer_of(demand: StringName) -> StringName:
	for counter_id in ALL:
		if blunts(counter_id).has(demand):
			return counter_id
	return &""
