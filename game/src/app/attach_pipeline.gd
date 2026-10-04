class_name AttachPipeline
extends RefCounted

## Ordered attach phases with named hook slots (ADR 0184 §6).
##
## The composition root builds one pipeline per boot with one phase per attach
## step; a mod's attach hook is staked to a phase NAME through
## `RegistrationContext.add_attach_hook` and fires when the pipeline runs that
## phase. The pipeline is a wiring container and nothing more: it holds no
## game state, no clocks and no feature arrays — only the order and the hook
## slots, so `app/`'s state scanners read it as wiring (ADR 0002).
##
## ## Hook semantics
##
## A hook added with `before = true` runs immediately BEFORE its phase's own
## `run`; the default (`before = false`) runs immediately AFTER it. Both fire
## inside the same phase visit, in registration order, and both receive the
## actor the pipeline is run against.
##
## ## Empty callables
##
## W2 stakes an empty `Callable()` for every manifest attach hook (the mod's
## own entry point binds the real one in W3+). An empty or invalid Callable is
## SKIPPED, never an error, so a stub cannot break a boot; a valid one is
## called. This is the tolerance that lets the through-path exist before any
## real mod exists to bind it.

## The ordered phases. Each row is `{name: StringName, run: Callable,
## before: Array[Callable], after: Array[Callable]}`; the hook arrays are
## written only through `add_hook` so a caller cannot smuggle a slot the
## pipeline did not open.
var _phases: Array[Dictionary] = []


## Append one phase to the end of the order. `run` is called with the actor
## when the pipeline runs; it is the phase's own attach step.
func add_phase(name: StringName, run: Callable) -> void:
	_phases.append({"name": name, "run": run, "before": [], "after": []})


## Stake `hook` to the phase named `phase_name`. Returns true when the phase
## existed and the hook was registered. An unknown phase is a NAMED LOUD
## ERROR — `push_error` naming the missing phase — and returns false, so the
## caller can refuse the registration (ADR 0184 §8: a manifest error aborts
## boot with a named cause, never a silent skip).
func add_hook(phase_name: StringName, hook: Callable, before: bool = false) -> bool:
	for phase in _phases:
		if String(phase["name"]) == String(phase_name):
			var slot: Array = phase["before"] if before else phase["after"]
			slot.append(hook)
			return true
	push_error("AttachPipeline: no phase named '%s' — attach hook refused" % String(phase_name))
	return false


## Run every phase in declared order: each phase's before-hooks, the phase
## itself, then its after-hooks. Bounded by the phase count — one pass over
## `_phases`, no re-entry.
func run(actor) -> void:
	for phase in _phases:
		_fire(phase["before"], actor)
		(phase["run"] as Callable).call(actor)
		_fire(phase["after"], actor)


## Call each valid hook with the actor. An empty or invalid Callable (the W2
## stub) is skipped rather than called, so a boot never dies on a hook no mod
## has bound yet.
func _fire(hooks: Array, actor) -> void:
	for hook in hooks:
		var callable := hook as Callable
		if callable.is_valid():
			callable.call(actor)
