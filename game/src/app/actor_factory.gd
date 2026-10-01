class_name ActorFactory
extends RefCounted

## Composition root for actors: the only place that knows concrete module providers
## and registers them with an actor (ADR 0002, dependency inversion).


static func build(id: StringName, base: Dictionary = {}) -> Actor:
	return Actor.new(id, base)


static func with_dual_cultivation(actor: Actor) -> Actor:
	DualCultivationApi.attach(actor)
	return actor


static func with_fertility(actor: Actor, species: SpeciesDef = null) -> Actor:
	FertilityApi.attach(actor, species)
	return actor
