class_name TraitDef
extends Resource

## Data-driven trait: modifiers applied to an actor. Add a trait by authoring a
## `.tres`, not code (ADR 0002).

@export var id: StringName = &""
@export var display_name: String = ""
@export var flat_modifiers: Dictionary = {}
@export var percent_modifiers: Dictionary = {}
@export var tags: Array[StringName] = []


func build_modifiers() -> Array[StatModifier]:
	var modifiers: Array[StatModifier] = []
	for key in flat_modifiers.keys():
		modifiers.append(
			StatModifier.new(StringName(key), Stat.Op.FLAT, float(flat_modifiers[key]), id)
		)
	for key in percent_modifiers.keys():
		modifiers.append(
			StatModifier.new(StringName(key), Stat.Op.PERCENT, float(percent_modifiers[key]), id)
		)
	return modifiers


func apply(actor: Actor) -> void:
	for modifier in build_modifiers():
		actor.stats.add_modifier(modifier)
	if not actor.traits.has(id):
		actor.traits.append(id)


func remove(actor: Actor) -> void:
	actor.stats.remove_modifiers_from(id)
	actor.traits.erase(id)
