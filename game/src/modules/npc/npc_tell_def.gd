class_name NpcTellDef
extends Resource

## ONE authored BODY tell — what the presentation does on APPROACH, before any dialogue
## click (ADR 0253).
##
## ## The body answers a verb, not a menu
##
## The reader this design refuses is "a reaction list the player clicks from". So a tell
## is `{trigger, verb, body, consequence}`: an authored TRIGGER, an authored VERB, an
## authored BODY, and a named consequence the caller can act on.
## `NpcAliveness.tell` matches the trigger against REAL state — the cause ledger, the
## bond class, the daypart slot — and returns the body. A trigger nothing can reach is
## dead authored weight, which is why the triggers are a CLOSED vocabulary the module
## itself publishes and `NpcDef`'s content guard requires every one of them to name.

## The closed trigger vocabulary. The first two are ledgers that already exist; the third
## is the daypart; the fourth is "they have no reason to be wary of you", which is what
## an unspent new npc answers. Declared above the fields because GDScript requires every
## constant to precede every variable (`class-definitions-order`).
const TRIGGER_CAUSE_ID := &"cause_id"
const TRIGGER_BOND_CLASS := &"bond_class"
const TRIGGER_SLOT := &"slot_id"
const TRIGGER_NEW_FACE := &"new_face"
const TRIGGER_ALL: Array[StringName] = [
	TRIGGER_CAUSE_ID, TRIGGER_BOND_CLASS, TRIGGER_SLOT, TRIGGER_NEW_FACE
]

## One of [constant TRIGGER_ALL].
@export var trigger: StringName = TRIGGER_CAUSE_ID

## What this trigger matches. A cause id, a `SocialBondClass` class name, a
## `NpcRoundDef.slot_id`, or the empty id for `new_face`.
@export var matches: StringName = &""

## The verb the body answers to, one hop from the player approaching. Named, not a
## percentage.
@export var verb: StringName = &"steps_back"

## The body, written to be read without a number: "she does not take the cup".
@export var body: String = ""

## The named consequence the CALLER acts on. A mechanism verb, never a UI state.
@export var consequence: StringName = &"refuses"

## A higher number answers this trigger first when several match. Authored, so the
## ordering is content rather than the order an array happened to be filled in.
@export var priority: int = 0

## The tiers this body is a plausible one FOR. **Empty means every tier**, for the same
## reason and with the same rule as `NpcOpinionDef.plausible_tiers`: the tier question is
## answered by the author, not by a branch in the composer.
@export var plausible_tiers: Array[String] = []


func valid() -> bool:
	return TRIGGER_ALL.has(trigger) and not body.is_empty() and verb != &""


func to_dict() -> Dictionary:
	return {
		"trigger": String(trigger),
		"matches": String(matches),
		"verb": String(verb),
		"body": body,
		"consequence": String(consequence),
		"priority": priority,
	}
