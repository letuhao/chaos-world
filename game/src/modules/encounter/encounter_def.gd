class_name EncounterDef
extends Resource

## One authored encounter: a random fate opportunity during exploration.
##
## An encounter is a data-driven event that triggers based on location and
## fate-held conditions. It offers a fate choice (1 of 2) and may drop a
## prophecy item. Encounters are earn-only — no purchase, no cheat (ADR 0065).
##
## The encounter system creates emergent storytelling: players explore the world,
## trigger encounters, and make fate choices that shape their destiny.

## Trigger types (closed vocabulary):
##   &"location" — triggers when the player is at a specific location
##   &"fate_held" — triggers when the player holds a specific fate
##   &"fate_missing" — triggers when the player does NOT hold a specific fate
##   &"always" — always eligible (subject to weight and cooldown)
const TRIGGER_LOCATION := &"location"
const TRIGGER_FATE_HELD := &"fate_held"
const TRIGGER_FATE_MISSING := &"fate_missing"
const TRIGGER_ALWAYS := &"always"

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## The trigger condition type (one of the TRIGGER_* constants)
@export var trigger_type: StringName = TRIGGER_ALWAYS
## The trigger value: location_id for TRIGGER_LOCATION, fate_id for fate triggers
@export var trigger_value: StringName = &""
## Relative spawn probability (higher = more likely)
@export var weight: float = 1.0
## Turns before this encounter can trigger again (0 = no cooldown)
@export var cooldown: int = 0
## Fates offered as choices (1-2). Each is a fate_id from the destiny catalog.
@export var fate_choices: Array[StringName] = []
## Prophecy item dropped after resolution (empty = no prophecy)
@export var prophecy_id: StringName = &""
## Whether this encounter can only be seen once (true) or repeats (false)
@export var unique: bool = true


func is_visible() -> bool:
	return id != &""


## Whether this encounter's trigger condition is met for the given actor.
func trigger_met(actor: Actor, current_location: StringName = &"") -> bool:
	match trigger_type:
		TRIGGER_LOCATION:
			return current_location == trigger_value
		TRIGGER_FATE_HELD:
			return DestinyApi.has_fate(actor, trigger_value)
		TRIGGER_FATE_MISSING:
			return not DestinyApi.has_fate(actor, trigger_value)
		TRIGGER_ALWAYS:
			return true
	return false
