class_name ActorFactory
extends RefCounted

## Composition root for actors: the only place that knows concrete module providers
## and registers them with an actor (ADR 0002, dependency inversion).


static func build(id: StringName, base: Dictionary = {}) -> Actor:
	var actor := Actor.new(id, base)
	# Core health and stamina pools exist for every actor; capacities follow the
	# derived stats, so an item that raises max_health never refills (ADR 0025).
	actor.attach_core_resources()
	return actor


static func with_dual_cultivation(actor: Actor) -> Actor:
	DualCultivationApi.attach(actor)
	return actor


static func with_fertility(actor: Actor, species: SpeciesDef = null) -> Actor:
	FertilityApi.attach(actor, species)
	return actor


## Enrol an actor in the body path and give it an acupoint layout. The only
## place that knows the attach order (ADR 0002, ADR 0012/0023).
static func with_body_cultivation(actor: Actor, rank_id: StringName = &"qi_refining") -> Actor:
	actor.set_path(PathState.new(BodyPath.PATH_ID, rank_id))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	BodyTraining.synchronize(actor)
	return actor
