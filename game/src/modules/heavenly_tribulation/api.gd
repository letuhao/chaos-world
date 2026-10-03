class_name HeavenlyTribulationApi
extends RefCounted

## Public facade for the `heavenly_tribulation` module.
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.
##
## One read model and three verbs, and nothing else. The tribulation gate is a
## gate on the SHARED ladder — `Breakthrough.tribulation_ok` is read by the body,
## qi and mind breakthrough conditions alike — so it cannot live inside any one
## of them. Filing it under a path would make the other two depend on that path's
## facade or re-implement the fight, which is the triplication ADR 0066 exists to
## prevent. This module is the single owner; a path reaches it the same way the UI
## does.
##
## No path is named here and none is needed: the module asks which realm the
## actor is owed a fight for from the actor's own enrolled paths.

# --- Read model ---------------------------------------------------------------


## Everything a tribulation screen renders, as primitives. Empty when no actor
## is bound or no path is enrolled.
##
## `owed` is the answer to "is a tribulation owed at all"; `gate_open` is the
## gate itself, read through core's predicate; `chance` is the share of fights
## this actor survives, published by core's one curve (`TribulationEndurance`) so
## the odds a player reads are the odds the fight is decided on.
static func state(actor: Actor) -> Dictionary:
	return TribulationFight.state(actor)


# --- Actions ------------------------------------------------------------------


## Begin the tribulation owed, bound to the realm it is owed for. `{"ok": false,
## "reason": R}` when none is owed or a fight is already in progress — the
## refusal shape the institution vocabulary uses, so a vacancy is never a silent
## no-op.
static func begin(actor: Actor) -> Dictionary:
	return TribulationFight.begin(actor)


## Fight one wave. The wave that brings the record to its last phase also decides
## it, so `decided` reports a verdict rather than a phase.
static func fight_wave(actor: Actor) -> Dictionary:
	return TribulationFight.fight_wave(actor, null)


## Fight on until the record is decided. Bounded by the module's wave guard,
## which names the phase machine that failed to converge.
static func fight_to_verdict(actor: Actor) -> Dictionary:
	return TribulationFight.fight_to_verdict(actor, null)


## Walk away from a fight without deciding it. The waves fought are forfeited, so
## the gate stays shut and nothing is gained or lost. False once the fight is
## decided.
static func withdraw(actor: Actor) -> bool:
	return TribulationFight.withdraw(actor)
