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

## How many *distinct kinds of act* a bond needs before it can be a friend.
##
## Counting distinct CAUSES was not enough, and the difference is the whole rule: a
## merchant's ledger usually offers several gift-tier causes (`gifted_item`, a favour
## repaid, a debt forgiven), so two of them clear a two-CAUSE bar while both are the same
## act — buying something. A friendship has to rest on two different KINDS (`gift` and
## `combat`, `gift` and `oath`), so the count is taken over `SocialCauseDef.kind`.
const FRIEND_DISTINCT_CAUSES := 2

## Trust a bond needs alongside standing to be a confidant.
const CONFIDANT_TRUST := 0.5

## The rung the AXES must have earned before a promoting cause can lift a bond to the top
## of the ladder. `sworn` is the top, so the rung below it is the only answer today; naming
## it rather than inlining `CONFIDANT` is what makes the rule readable as "an oath is built
## ON TOP OF a confidence", which is the claim a reviewer has to be able to check.
const PROMOTION_MIN_CLASS := CONFIDANT


## The class for a bond with the given axes.
##
## `distinct_causes` counts how many different KINDS of act have ever moved this bond,
## which is why it is a parameter and not a stored counter: it is an input to the
## classification, derived from the cause ledger, not an opinion held about the actor.
##
## `promoted_to` is the class a qualifying cause has promised this bond (`BL-0659`). It is
## a CEILING, never an outcome, and it is deliberately checked LAST: see
## `_promoted_class` for why an oath cannot be bought by the very act that promises it.
##
## **The distinct-cause rule caps the whole positive ladder, not just the friend step.**
## It is easy to write this so a large standing skips the guard and returns `friend` — and
## that is exactly the gift-spam hole: one generous cause repeated twenty times is a high
## total and a single distinct reason, so it stays an acquaintance.
static func classify(
	standing: float, trust: float, distinct_causes: int, promoted_to: StringName = &""
) -> StringName:
	if standing <= SUSPECT_AT:
		return _classify_negative(standing)
	if distinct_causes < FRIEND_DISTINCT_CAUSES:
		# Not enough distinct reasons to be a friend, however large the total. One
		# generous cause repeated twenty times is a high total and a single reason, so
		# it tops out at an acquaintance — that is the whole anti-farm rule. **A promotion
		# cannot outrun it either**, because this branch returns before any promotion is
		# read: a single sworn act is one kind of act, so it is not even a friendship.
		return ACQUAINTANCE if standing >= ACQUAINTANCE_AT else STRANGER
	var earned := _ladder_class(standing, trust)
	return _promoted_class(earned, promoted_to)


## The class the AXES alone earn — the whole ladder except `sworn`, which no total buys.
static func _ladder_class(standing: float, trust: float) -> StringName:
	if standing >= CONFIDANT_AT:
		return CONFIDANT if trust >= CONFIDANT_TRUST else FRIEND
	if standing >= FRIEND_AT:
		return FRIEND
	if standing >= ACQUAINTANCE_AT:
		return ACQUAINTANCE
	return STRANGER


## ## Why a promotion is checked against the axes and not trusted on its own
##
## `promoted_to` arrives from an authored cause (`SocialCauseDef.promotes_to`), so the
## tempting implementation is to return it outright — and that turns the top of a
## relationship ladder into a thing a third purchase triggers. Three conditions, and each
## one closes a different hole:
##
## 1. **The axes must already have earned `PROMOTION_MIN_CLASS`.** A bond that is a friend
##    is a friend; an oath is what a friendship becomes, not what a gift upgrades it into.
##    This is the load-bearing one: it is the difference between "shared a brotherhood
##    after years of standing" and "shared a brotherhood, so the whole ladder is void".
## 2. **The promotion may only lift, never lower.** A class derived from a ledger that a
##    second, lesser cause can demote is not derived, it is negotiated.
## 3. **It may never exceed the rung the cause named.** An authored `promotes_to` is a
##    ceiling an author sets; `sworn` is the top, so this also rejects an id that is not
##    on the positive ladder at all rather than returning a class `at_least` cannot place.
##
## Every one of these is a comparison on the ladder, so the function stays total: a bond
## always resolves to exactly one class and there is still no "unknown" branch.
static func _promoted_class(earned: StringName, promoted_to: StringName) -> StringName:
	if not POSITIVE.has(promoted_to):
		return earned
	if POSITIVE.find(promoted_to) <= POSITIVE.find(earned):
		return earned
	if POSITIVE.find(earned) < POSITIVE.find(PROMOTION_MIN_CLASS):
		return earned
	return promoted_to


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
			return L.t("LOC_SOCIAL_5D60331830")
		ACQUAINTANCE:
			return L.t("LOC_SOCIAL_81E76E5BA6")
		FRIEND:
			return L.t("LOC_SOCIAL_2394299D6F")
		CONFIDANT:
			return L.t("LOC_SOCIAL_6D556D0E00")
		SWORN:
			return L.t("LOC_SOCIAL_A8BD065BA2")
		SUSPECT:
			return L.t("LOC_SOCIAL_AB646FBF43")
		HOSTILE:
			return L.t("LOC_SOCIAL_49CE5DE18C")
		GRUDGE:
			return L.t("LOC_SOCIAL_C0C7A8485B")
		NEMESIS:
			return L.t("LOC_SOCIAL_C10C9355D2")
	return L.t("LOC_SOCIAL_5D60331830")
