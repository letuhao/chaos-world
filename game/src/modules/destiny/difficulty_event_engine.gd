class_name DifficultyEventEngine
extends RefCounted

## Computes the total difficulty modifier from all held fates (ADR 0404).
##
## This is a pure read from the ledger — no state is stored. The engine walks
## every held fate, collects its difficulty events, and sums the magnitudes
## per event type. The result is a dictionary of `event_type -> total_modifier`.
##
## The engine does NOT apply the modifier to any system. It exposes the
## numbers so consumers (combat, social) can read them through the destiny
## facade and apply them to their own arithmetic.

## The closed event type vocabulary. A consumer may read these and nothing else.
const EVENT_TYPES: Array[StringName] = [
	&"enemy_spawn",
	&"social_difficulty",
	&"combat_difficulty",
]


## Every difficulty event from all held fates, as an array of dictionaries.
## Each entry is `{fate_id, event_type, magnitude, description}`.
static func active_events(actor: Actor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if actor == null:
		return out
	var ledger := DestinyState.normalize(actor.get_module_data(DestinyState.MODULE_KEY))
	for fate_id in DestinyState.fate_ids(ledger):
		var def := FateCatalog.instance().fate_definition(fate_id)
		if def == null:
			continue
		for event in def.difficulty_events:
			if not (event is Dictionary):
				continue
			var entry := event as Dictionary
			(
				out
				. append(
					{
						"fate_id": String(fate_id),
						"event_type": StringName(entry.get("event_type", &"")),
						"magnitude": float(entry.get("magnitude", 0.0)),
						"description": String(entry.get("description", "")),
					}
				)
			)
	return out


## The total difficulty modifier per event type, as a dictionary of
## `event_type -> float`. Only event types with a non-zero total are included.
static func modifiers(actor: Actor) -> Dictionary:
	var out := {}
	if actor == null:
		return out
	for event in active_events(actor):
		var event_type := StringName(event["event_type"])
		if not EVENT_TYPES.has(event_type):
			continue
		var key := String(event_type)
		out[key] = float(out.get(key, 0.0)) + float(event["magnitude"])
	return out


## The total difficulty modifier for one event type, or 0.0 when no held
## fate declares an event of that type.
static func modifier_for(actor: Actor, event_type: StringName) -> float:
	return float(modifiers(actor).get(String(event_type), 0.0))


## Whether any held fate declares a difficulty event of `event_type`.
static func has_event_type(actor: Actor, event_type: StringName) -> bool:
	return modifier_for(actor, event_type) != 0.0
