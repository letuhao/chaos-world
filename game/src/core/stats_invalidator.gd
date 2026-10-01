class_name StatsInvalidator
extends RefCounted

## Bridges change signals to an actor's stats without a refcount cycle: it holds
## only a weak reference to the actor, so Actor -> pool -> invalidator -> (weak)
## Actor never keeps the actor alive.

var _actor_ref: WeakRef


func _init(actor: Actor) -> void:
	_actor_ref = weakref(actor)


func on_changed() -> void:
	var actor: Actor = _actor_ref.get_ref()
	if actor != null:
		actor.mark_stats_dirty()
