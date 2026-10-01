class_name MeridianState
extends RefCounted

## Per-meridian runtime state (ADR 0017). One instance per meridian on an actor.

const CLOSED := &"closed"
const OPEN := &"open"
const EXPANDED := &"expanded"
const STRENGTHENED := &"strengthened"
const DAMAGED := &"damaged"

## Progression order of the four forward states. A damaged channel reports 0 so
## it never satisfies a "at least this state" requirement.
const STATE_ORDER := {CLOSED: 0, OPEN: 1, EXPANDED: 2, STRENGTHENED: 3, DAMAGED: 0}

var id: StringName
var state: StringName = &"closed"
var tier: int = 0
## Training depth within `strengthened`. Cultivation training raises this past
## the base state up to a per-realm cap (ADR 0023/0024).
var refinement: int = 0
var capacity_bonus: float = 0.0
var flow_bonus: float = 0.0
var power_bonus: float = 0.0


func is_open() -> bool:
	return state != &"closed"


func is_damaged() -> bool:
	return state == &"damaged"


## True when this channel has reached `required` or better and is not damaged.
func meets(required: StringName) -> bool:
	if is_damaged():
		return false
	return int(STATE_ORDER.get(state, 0)) >= int(STATE_ORDER.get(required, 0))


func state_rank() -> int:
	return int(STATE_ORDER.get(state, 0))


func get_bonus() -> float:
	if state == &"damaged":
		return 0.5
	return 1.0
