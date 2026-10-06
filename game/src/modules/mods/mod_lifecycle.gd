class_name ModLifecycle
extends RefCounted

## Manages mod lifecycle hooks (ADR 0184 §6 extension).
##
## Hooks are registered by event name and fired when the game loop reaches
## the corresponding point. The lifecycle manager is deliberately simple:
## it stores callables by event and fires them in registration order. A
## hook that throws does not prevent later hooks from firing — the error
## is reported and the next hook runs.
##
## Events: on_load, on_unload, on_enable, on_disable, on_update, on_save,
## on_load_save.

## All registered hooks, keyed by event name.
var _hooks: Dictionary = {}


## Register a callable for an event. The callable is appended to the event's
## list, so multiple mods can hook the same event.
func add_hook(event: String, callable: Callable) -> void:
	if not _hooks.has(event):
		_hooks[event] = []
	(_hooks[event] as Array).append(callable)


## Fire all hooks registered for an event. Hooks are called in registration
## order. A hook that throws is reported and the next hook still fires.
func fire(event: String) -> void:
	if not _hooks.has(event):
		return
	for callable in _hooks[event]:
		if not callable.is_valid():
			continue
		callable.call()


## All hooks registered for an event, as an Array of Callables.
func hooks_for(event: String) -> Array:
	if not _hooks.has(event):
		return []
	return (_hooks[event] as Array).duplicate()


## Whether any hooks are registered for an event.
func has_hooks(event: String) -> bool:
	return _hooks.has(event) and not (_hooks[event] as Array).is_empty()


## Remove all hooks for an event.
func clear(event: String) -> void:
	_hooks.erase(event)


## Remove all hooks for all events.
func clear_all() -> void:
	_hooks.clear()
