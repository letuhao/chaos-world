class_name MeridianState
extends RefCounted

## Per-meridian runtime state (ADR 0017). One instance per meridian on an actor.
## Injury is an independent recoverable flag — it does not erase structural attainment.

const CLOSED := &"closed"
const OPEN := &"open"
const EXPANDED := &"expanded"
const STRENGTHENED := &"strengthened"

## Progression order of the four forward states. Injury is not a state: it is the
## separate `injured` flag, so a wounded channel keeps its rank and fails
## `meets()` on the flag instead.
const STATE_ORDER := {CLOSED: 0, OPEN: 1, EXPANDED: 2, STRENGTHENED: 3}

var id: StringName
var state: StringName = &"closed"
var tier: int = 0
## Training depth within `strengthened`. Cultivation training raises this past
## the base state up to a per-realm cap (ADR 0023/0024).
var refinement: int = 0
var capacity_bonus: float = 0.0
var flow_bonus: float = 0.0
var power_bonus: float = 0.0
## Recoverable injury flag. When true, bonuses are halved but structural state persists.
var injured: bool = false


func is_open() -> bool:
	return state != &"closed"


func is_injured() -> bool:
	return injured


## True when this channel has reached `required` or better and is not injured.
func meets(required: StringName) -> bool:
	if injured:
		return false
	return int(STATE_ORDER.get(state, 0)) >= int(STATE_ORDER.get(required, 0))


func state_rank() -> int:
	return int(STATE_ORDER.get(state, 0))


func get_bonus() -> float:
	if injured:
		return 0.5
	return 1.0


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"state": String(state),
		"tier": tier,
		"refinement": refinement,
		"capacity_bonus": capacity_bonus,
		"flow_bonus": flow_bonus,
		"power_bonus": power_bonus,
		"injured": injured,
	}


static func from_dict(data: Dictionary) -> MeridianState:
	var state := MeridianState.new()
	state.id = StringName(data.get("id", ""))
	state.state = StringName(data.get("state", "closed"))
	state.tier = int(data.get("tier", 0))
	state.refinement = int(data.get("refinement", 0))
	state.capacity_bonus = float(data.get("capacity_bonus", 0.0))
	state.flow_bonus = float(data.get("flow_bonus", 0.0))
	state.power_bonus = float(data.get("power_bonus", 0.0))
	state.injured = bool(data.get("injured", false))
	return state
