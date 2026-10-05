class_name MechanismSlot
extends RefCounted

## Where a `DamageMechanism` is bound on an actor (ADR 0067). Component id
## `&"damage_mechanism"` — the seam the whole three-mechanism design turns on.
##
## ## Why this file exists at all
##
## The alternative is a bare `actor.component(&"damage_mechanism") as DamageMechanism`.
## `Actor.component()` returns `RefCounted`, so the `as` on null is SILENT, and it
## surfaces three stages later as "the mechanism did nothing" — an attacker with no
## mechanism bound silently deals a crit's worth of zero through every shared stage
## and the bug surfaces as a balance problem, not as a missing binding. That is the
## defect class a spine with three pluggable paths cannot afford, so the lookup FAILS
## LOUDLY and names the actor that has nothing bound.
##
## It is also not a `Dictionary` of callables. A dictionary has no name, so the repo
## rule "any script implementing a `contracts/` interface must pass the same contract
## tests" would have nothing to point at: a per-path mechanism as a lambda cannot be
## tested against `contracts/damage_mechanism.gd`, it can only be tested against
## whatever the caller happened to write. A named class with two virtuals is what makes
## "every mechanism ships the same contract tests" a thing an agent can be held to.
##
## ## Not a bare component lookup either
##
## `actor.component()` returns `RefCounted` precisely so core never imports a module
## type. This file is the module that names its own type, so the downcast lives here,
## once, where the failure is loud — and the `as` on a wrong-typed component is caught
## here instead of three stages downstream.
##
## ## `contracts` is in `BARE_REF_UNITS`, so the edge IS enforced
##
## Naming `DamageMechanism` from `modules/combat/` is a real dependency, which is the
## point: the seam is one declared edge, not a convention. `combat` already declares
## `contracts`, so binding costs no registry change.

## The component id. One string, owned here, so no caller spells it.
const COMPONENT_ID := &"damage_mechanism"


## Bind `mechanism` to `actor`. Re-binding replaces: the slot holds one mechanism,
## because one actor fights one way, and a second binding is a re-attachment (an item
## swap, a path change) rather than an accumulation.
static func bind(actor: Actor, mechanism: DamageMechanism) -> void:
	assert(actor != null, "MechanismSlot.bind: actor is null")
	assert(
		mechanism != null, "MechanismSlot.bind: %s was bound a null mechanism" % String(actor.id)
	)
	actor.set_component(COMPONENT_ID, mechanism)


## The mechanism bound to `actor`, or null when there is none. The non-loud read, for a
## caller that genuinely wants to know — `CombatApi.mechanism_of` refuses a null
## instead of returning one, but a preview asking "is anyone bound?" needs this.
static func peek(actor: Actor) -> DamageMechanism:
	if actor == null:
		return null
	return actor.component(COMPONENT_ID) as DamageMechanism


## The mechanism bound to `actor`. FAILS LOUDLY when there is none.
##
## A mechanism is not optional: without one the spine has nothing to run at S4 and S5,
## and every shared stage downstream multiplies a number nothing produced. Asserting
## here names the actor that is unbound, which is the only piece of information
## available at the point the information still exists.
##
## `has_mechanism` is the escape hatch for the caller that must handle both, and it is
## the ONLY sanctioned way to ask — so "was anything bound" is a decision a caller
## makes deliberately rather than an exception it happens to catch.
static func of(actor: Actor) -> DamageMechanism:
	var mechanism := peek(actor)
	assert(
		mechanism != null,
		"MechanismSlot.of: actor '%s' has no %s bound" % [String(actor.id), String(COMPONENT_ID)]
	)
	return mechanism


## Whether `actor` has something bound. The loud read's companion, never its
## replacement: `of` is what production code calls.
static func has_mechanism(actor: Actor) -> bool:
	return peek(actor) != null


## Unbind, restoring the "not bound" state the loud read refuses. Used by a path
## change that takes a cultivator out of combat entirely; production code that merely
## wants to know should ask [method has_mechanism].
static func clear(actor: Actor) -> void:
	if actor != null:
		actor.set_component(COMPONENT_ID, null)
