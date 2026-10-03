class_name StatusLoop
extends RefCounted

## The composition root's status tick (ADR 0089). Wiring, not rules: `app/` owns the
## clock and calls [method StatusApi.tick_statuses]; the `status` module owns what
## ticking means.
##
## ## Why this file exists
##
## Measured 2026-10-02, `Actor.tick_statuses` had ZERO production callers — only
## `tests/core/test_actor_statuses.gd:18,26`. No DoT could tick, no status could
## expire, ADR 0075's environment hazard had nothing to ride, and ADR 0071's
## `mind_deviation` was a label. A status system nobody can tick is decoration.
##
## ## One caller, one clock
##
## `InputHandler.tick` was that caller, and ADR 0056's deletion of the prototype
## took it with it: the game now has no per-frame driver at all. This loop is the
## wire the next one is meant to call, and it deliberately hangs off nothing rather
## than inventing a clock — a `Node` with `_process` would be a second, and ADR 0056
## forbids a stateful system in `app/`; this holds no state of its own, only the
## actor it ticks, so it is wiring the way `ActorFactory` and `ScreenRoutes` are.
## Restoring a caller is DEF-0111's shape: an explicit `periods`/frame delta from
## whoever owns time, never a wall clock read in here.
##
## ## Session-only
##
## Nothing here persists. ADR 0089: statuses never enter `Actor.to_dict()` and
## `SCHEMA_VERSION` stays 4, so a save carries no status and loading an older save is
## unaffected.

var _actor: Actor


func _init(actor: Actor = null) -> void:
	_actor = actor


## Adopt an actor after construction, for a caller that built the loop first. The
## loop stays a pure wire either way.
func attach(actor: Actor) -> void:
	_actor = actor


func actor() -> Actor:
	return _actor


## Advance every status on the actor by `delta`. Call this from the frame driver
## that already exists; never from a loop of your own.
##
## Social bonds decay on this same call, deliberately. A relationship that faded on a
## different clock from a status that expired would be a relationship whose timing nobody
## could reason about, and this loop is already the composition root's only time wire
## (ADR 0089, ADR 0091).
func tick(delta: float) -> Dictionary:
	if _actor == null:
		return {"ok": false, "reason": "no_actor", "ticked": 0, "damage": 0.0, "expired": 0}
	var result := StatusApi.tick_statuses(_actor, delta)
	result["bonds"] = NpcBoot.tick(_actor, delta)
	return result


## COMBAT-scope statuses are cleared on combat exit, by the same caller that ticks
## them (ADR 0089). CULTIVATION-scope statuses are never purged by combat state.
func exit_combat() -> Array[String]:
	return StatusApi.clear_combat_scope(_actor)
