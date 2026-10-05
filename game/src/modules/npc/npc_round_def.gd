class_name NpcRoundDef
extends Resource

## ONE authored slot in a major npc's day (ADR 0253).
##
## ## The day is a CLOSED vocabulary of slots and a way of choosing between them
##
## `ADR 0178` already decided that a daypart is a closed presentation vocabulary that
## never carries a duration — so the ratio belongs to the clock (`TimeLadder`) and is
## deliberately absent here. What an author writes is WHICH slot, and the clock owns HOW
## LONG a slot is.
##
## ## The whole point: they are somewhere ELSE when you are not looking
##
## A tracked npc who is always in the room where you left them is furniture. This is the
## data that makes "you missed Elder Wei, he was at the forge" expressible, and it is
## read through the LAZY clock: nothing here moves until somebody looks, and looking is
## the trigger (ADR 0173(c)).

## The authored slot id. A gate and a test name this, never the slot's position.
@export var slot_id: StringName = &""

## The slot's authored order. Strictly increasing, exactly as `NpcStageDef.index` is:
## a slot is addressed by id and ordered by an authored number, never by array position.
@export var index: int = 0

## The verb the hero would SEE them doing. Printed as-is, so it is a presentation
## string and not a mechanic id: nothing gates on this field.
@export var activity: String = ""

## Where they are during this slot. The same `location_id` vocabulary
## `NpcRosterEntry.location_id` already uses, so "where do I go to find this person"
## stays one answer rather than two that can disagree.
@export var location_id: StringName = &""

## The body tell they wear WHILE in this slot — the unprompted one, the one you read
## from across the room. Optional; an empty `tell_id` means this slot has no body of its
## own and the approach tell below answers instead.
@export var tell_id: StringName = &""


func to_dict() -> Dictionary:
	return {
		"slot_id": String(slot_id),
		"index": index,
		"activity": activity,
		"location_id": String(location_id),
		"tell_id": String(tell_id),
	}
