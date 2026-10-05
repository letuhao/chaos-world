class_name NpcPersona
extends RefCounted

## A COMPOSED npc — everything a minor npc needs, assembled at the moment of interaction
## and held nowhere (ADR 0253).
##
## ## **This is a value, not a record. Nothing about it is persisted.**
##
## `NpcMinorComposer` builds one per interaction and it is dropped when the interaction
## ends. There is no key, no ledger row, no `module_data` write — which is what makes a
## minor npc cost nothing while unobserved AND makes them unable to be remembered across
## visits. The second half is not a compromise: ADR 0092 makes persistence the ONE
## question a tier answers, so a minor who persisted would have become tracked.

## The composed name. NOT `npc_id`: a composed minor has no stable id in the catalog and
## must never acquire one, because the roster is keyed on it.
var display_name: String = ""

## How they carry themselves. Printed by a panel as-is.
var manner: String = ""

## Where the composition decided they belong, and what they are doing there.
var location_id: StringName = &""
var activity: String = ""

## One composed opinion about the PLACE they are standing in. The rule that makes this
## read as a person rather than a random name: **the opinion is derived from the place
## and from the tier, never rolled free.**
var opinion_stance: StringName = NpcOpinionDef.STANCE_INDIFFERENT
var opinion_prose: String = ""
var opinion_subject: StringName = &""

## One generic body tell, chosen by the same place-and-tier rule.
var tell_verb: StringName = &"nods_once"
var tell_body: String = ""
var tell_consequence: StringName = &"accepts"

## The tuned scale this persona was composed at, 0..100.
var power_scale: float = 0.0


## The read model, PRIMITIVES ONLY (ADR 0038): a panel tests this dictionary and nothing
## in it names a `Resource`.
func to_dict() -> Dictionary:
	return {
		"display_name": display_name,
		"manner": manner,
		"location_id": String(location_id),
		"activity": activity,
		"opinion_stance": String(opinion_stance),
		"opinion_subject": String(opinion_subject),
		"opinion_prose": opinion_prose,
		"tell_verb": String(tell_verb),
		"tell_body": tell_body,
		"tell_consequence": String(tell_consequence),
		"power_scale": power_scale,
	}


## A composed persona has no stable id and MUST NOT acquire one. This is the seam a
## future change would reach for, so it says the refusal out loud rather than leaving a
## blank field to be filled in.
func has_persistent_id() -> bool:
	return false
