class_name CombatApi
extends RefCounted

## Public facade for the `combat` module.

const SHIELD_COMPONENT := &"shield"


static func attach_shield(actor: Actor, maximum: float) -> Shield:
	var shield := Shield.new(&"shield", maximum)
	actor.set_component(SHIELD_COMPONENT, shield)
	return shield


static func shield(actor: Actor) -> Shield:
	return actor.component(SHIELD_COMPONENT)
