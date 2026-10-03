class_name SocialBondClass
extends RefCounted

## The ordered relationship ladder (ADR 0076). **A class is derived from a bond's axes
## and is never stored**, so two actors who both fought the same boss cannot disagree
## about what that made them, and no save file carries a class that its axes contradict.
##
## The ladder is bidirectional and total: every bond resolves to exactly one class, so
## `classify` has no "unknown" branch to fall through.

const STRANGER := &"stranger"
const ACQUAINTANCE := &"acquaintance"
const FRIEND := &"friend"
const CONFIDANT := &"confidant"
const SWORN := &"sworn"
const SUSPECT := &"suspect"
const HOSTILE := &"hostile"
const GRUDGE := &"grudge"
const NEMESIS := &"nemesis"

## Ordered positive then negative, so a UI can walk the ladder without a lookup table.
const POSITIVE: Array[StringName] = [STRANGER, ACQUAINTANCE, FRIEND, CONFIDANT, SWORN]
const NEGATIVE: Array[StringName] = [HOSTILE, GRUDGE, NEMESIS]
const ALL: Array[StringName] = [
	STRANGER,
	ACQUAINTANCE,
	FRIEND,
	CONFIDANT,
	SWORN,
	SUSPECT,
	HOSTILE,
	GRUDGE,
	NEMESIS,
]

## Standing thresholds. `stranger` and `suspect` are the neutral band around zero.
const ACQUAINTANCE_AT := 1.0
const FRIEND_AT := 6.0
const CONFIDANT_AT := 14.0
const SUSPECT_AT := -1.0
const HOSTILE_AT := -4.0
const GRUDGE_AT := -10.0
const NEMESIS_AT := -16.0

## How many *distinct* causes a bond needs before it can be a friend. The two-and-distinct
## rule is what stops a merchant being farmed: one generous cause repeated is not a
## friendship.
const FRIEND_DISTINCT_CAUSES := 2

## Trust a bond needs alongside standing to be a confidant.
const CONFIDANT_TRUST := 0.5


## The class for a bond with the given axes.
##
## `distinct_causes` counts how many different authored causes have ever moved this bond,
## which is why it is a parameter and not a stored counter: it is an input to the
## classification, derived from the cause ledger, not an opinion held about the actor.
##
## **The distinct-cause rule caps the whole positive ladder, not just the friend step.**
## It is easy to write this so a large standing skips the guard and returns `friend` — and
## that is exactly the gift-spam hole: one generous cause repeated twenty times is a high
## total and a single distinct reason, so it stays an acquaintance.
static func classify(standing: float, trust: float, distinct_causes: int) -> StringName:
	if standing <= SUSPECT_AT:
		return _classify_negative(standing)
	if distinct_causes < FRIEND_DISTINCT_CAUSES:
		# Not enough distinct reasons to be a friend, however large the total. One
		# generous cause repeated twenty times is a high total and a single reason, so
		# it tops out at an acquaintance — that is the whole anti-farm rule.
		return ACQUAINTANCE if standing >= ACQUAINTANCE_AT else STRANGER
	if standing >= CONFIDANT_AT:
		return CONFIDANT if trust >= CONFIDANT_TRUST else FRIEND
	if standing >= FRIEND_AT:
		return FRIEND
	if standing >= ACQUAINTANCE_AT:
		return ACQUAINTANCE
	return STRANGER


static func _classify_negative(standing: float) -> StringName:
	if standing <= NEMESIS_AT:
		return NEMESIS
	if standing <= GRUDGE_AT:
		return GRUDGE
	if standing <= HOSTILE_AT:
		return HOSTILE
	return SUSPECT


## Whether `bond_class` is at least as close as `target`. Used by `SocialGate` so a
## requirement reads as "friend or better" rather than an author enumerating the ladder.
static func at_least(bond_class: StringName, target: StringName) -> bool:
	if bond_class == target:
		return true
	if NEGATIVE.has(bond_class):
		# A negative class is never "at least" a positive one, and vice versa.
		return NEGATIVE.has(target) and NEGATIVE.find(bond_class) >= NEGATIVE.find(target)
	return POSITIVE.has(target) and POSITIVE.find(bond_class) >= POSITIVE.find(target)


## A one-line human label for a class, used by a panel through the facade.
static func label(bond_class: StringName) -> String:
	match bond_class:
		STRANGER:
			return "Stranger"
		ACQUAINTANCE:
			return "Acquaintance"
		FRIEND:
			return "Friend"
		CONFIDANT:
			return "Confidant"
		SWORN:
			return "Sworn"
		SUSPECT:
			return "Suspect"
		HOSTILE:
			return "Hostile"
		GRUDGE:
			return "Grudge"
		NEMESIS:
			return "Nemesis"
	return "Stranger"
