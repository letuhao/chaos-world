class_name DialogueCondition
extends Resource

## ONE authored requirement on a choice (ADR 0862).
##
## ## A closed verb set, and why a refusal is a NAME
##
## A gate that could not be met and a gate that was never evaluated must not look the
## same to a player. So `evaluate` answers `{ok, refusal}` and the choice is PUBLISHED
## as locked-with-a-reason rather than dropped: `DialogueChoiceDef.locked` and
## `.refusal` reach the panel, so "she will not tell you that yet" is renderable while
## "she never offers it" is a different sentence.
##
## The verbs are CLOSED ([constant VERBS]) so an authored `.tres` naming one the module
## cannot evaluate is a loud `unknown_condition` refusal rather than a condition that
## silently passes and opens every door behind it.
##
## The subject is a KEY in the actor's variable store, never an arbitrary expression:
## there is no scripting here, and a condition that could compute anything could not be
## checked by a content audit.

## The variable's value is AT OR ABOVE `value`.
const AT_LEAST := &"at_least"
## The variable's value is AT OR BELOW `value`.
const AT_MOST := &"at_most"
## The variable is EQUAL to `value`.
const EQUALS := &"equals"
## The variable is NOT present in the store at all. Distinct from `equals` a default:
## "has never been told" is not "was told nothing".
const UNSET := &"unset"
## The variable is PRESENT, whatever its value.
const SET := &"set"
## The actor's realm sits at or above `realm` on the shared ladder.
const REALM_AT_LEAST := &"realm_at_least"
## The actor's realm sits below `realm` on the shared ladder.
const REALM_BELOW := &"realm_below"

const VERBS: Array[StringName] = [
	AT_LEAST,
	AT_MOST,
	EQUALS,
	UNSET,
	SET,
	REALM_AT_LEAST,
	REALM_BELOW,
]

# --- refusals. Every `ok: false` carries one of these, never an empty string. -----

## The authored requirement is not met and the choice is locked.
const REFUSAL_LOCKED := "locked"
## A comparison named a variable the actor has never had written.
const REFUSAL_NOT_YET_SET := "not_yet_set"
## A comparison named a value of a different type than the variable declares. An
## AUTHORING error: `at_least: 2` against a `String` store is not "not met", it is a
## condition that could never be evaluated and is refused rather than assumed false.
const REFUSAL_TYPE_MISMATCH := "type_mismatch"
## A `realm_*` verb named a realm the shared ladder does not hold.
const REFUSAL_UNKNOWN_REALM := "unknown_realm"
## The actor this condition is evaluated against is null.
const REFUSAL_NO_ACTOR := "no_actor"
## The authored verb is outside the closed vocabulary.
const REFUSAL_UNKNOWN_CONDITION := "unknown_condition"

# --- authored fields -----------------------------------------------------------

## One of [constant VERBS].
@export var verb: StringName = SET

## The variable key this reads. Ignored by the two `realm_*` verbs, which read the
## actor's own realm instead — a plain id rather than a second typed key space.
@export var key: StringName = &""

## The authored threshold or value. Compared through the variable's OWN declared type
## by [DialogueVariables], so an `int` threshold is never compared against a `String`
## that merely looks numeric.
@export var value: Variant = null

## The realm id a `realm_*` verb compares against. Must be a ladder realm; a floor
## naming no realm refuses `unknown_realm`, because a gate that can never open is
## unreachable content dressed as a locked door.
@export var realm: StringName = &""


func valid() -> bool:
	if not VERBS.has(verb):
		return false
	if verb == REALM_AT_LEAST or verb == REALM_BELOW:
		return realm != &""
	return key != &""


## `{ok, refusal}` — `ok` true carries the EMPTY refusal. Never a bare bool: a caller
## rendering a locked choice needs the sentence, and a bool cannot carry one.
func evaluate(variables: DialogueVariables, actor: Actor) -> Dictionary:
	match verb:
		UNSET:
			return _verdict(not variables.has(key), REFUSAL_LOCKED)
		SET:
			return _verdict(variables.has(key), REFUSAL_LOCKED)
		AT_LEAST, AT_MOST, EQUALS:
			return _compare(variables, verb)
		REALM_AT_LEAST:
			return _realm(actor, true)
		REALM_BELOW:
			return _realm(actor, false)
	return _verdict(false, REFUSAL_UNKNOWN_CONDITION)


## The three value-comparing verbs, all through the variable's DECLARED type so an
## `int` store compared with a float threshold behaves identically on every read.
##
## A variable that is not present is UNMET for all three, and says so by the same name
## a present-but-too-small variable does — because `UNSET` is the verb that asks the
## DIFFERENT question "was this ever written", so a gate can never accidentally read an
## absent store as a zero.
func _compare(variables: DialogueVariables, verb_used: StringName) -> Dictionary:
	if not variables.has(key):
		return _verdict(false, REFUSAL_NOT_YET_SET)
	if not variables.matches_type(key, value):
		return _verdict(false, REFUSAL_TYPE_MISMATCH)
	var held := variables.compare(key, value)
	match verb_used:
		AT_LEAST:
			return _verdict(held >= 0, REFUSAL_LOCKED)
		AT_MOST:
			return _verdict(held <= 0, REFUSAL_LOCKED)
		_:
			return _verdict(held == 0, REFUSAL_LOCKED)


## A realm comparison by LADDER INDEX, never by string, so adding a realm is data and a
## locale change cannot reorder the answer — `DomainFixtures._realm_gate` reads it for
## the same reason.
func _realm(actor: Actor, at_least: bool) -> Dictionary:
	var ladder := RealmDefaults.ladder()
	var floor_index := ladder.index_of(realm)
	if floor_index < 0:
		return _verdict(false, REFUSAL_UNKNOWN_REALM)
	if actor == null:
		return _verdict(false, REFUSAL_NO_ACTOR)
	var held := ladder.index_of(actor.realm())
	if at_least:
		return _verdict(held >= floor_index, REFUSAL_LOCKED)
	return _verdict(held < floor_index, REFUSAL_LOCKED)


## The ONE place an answer is shaped, so every refusal on this class is named by
## construction rather than by each caller remembering to.
func _verdict(met: bool, refusal: String) -> Dictionary:
	if met:
		return {"ok": true, "refusal": ""}
	return {"ok": false, "refusal": refusal}
