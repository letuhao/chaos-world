class_name DomainRoles
extends RefCounted

## The CLOSED set of roles an inhabitant of a domain can hold (ADR 0074).
##
## A role is a TAG on `Actor.tags`, never a class: this game has `Actor` as the base for
## every pc, npc and mob, so a mini-boss and a mob differ by magnitude and by tag, never
## by which script they extend. The forbidden pattern is an `if role == "boss"` inside
## damage resolution — the same rule ADR 0067 states for `path_id`, for the same reason:
## mechanisms that branch on role are mechanisms that disagree.
##
## The set is closed so `DomainMapContract` can hard-fail an unknown role rather than
## accepting a typo that spawns an actor nothing can identify.

const MOB := &"mob"
const MINIBOSS := &"miniboss"
const BOSS := &"boss"
const NPC := &"npc"
const RIVAL_CULTIVATOR := &"rival_cultivator"

const ROLES: Array[StringName] = [
	MOB,
	MINIBOSS,
	BOSS,
	NPC,
	RIVAL_CULTIVATOR,
]

## Roles that are hostile to the player on sight. This is a property of CONTENT, read
## from the actor's tags — never a branch inside a damage mechanism.
const HOSTILE_ROLES: Array[StringName] = [MOB, MINIBOSS, BOSS]

## A rival cultivator is a cultivator (ADR 0074): an `Actor` with a real `PathState` and
## the same providers as the player, not a questgiver class with a reduced stat block.
const CULTIVATING_ROLES: Array[StringName] = [BOSS, MINIBOSS, RIVAL_CULTIVATOR]


static func is_valid(role: StringName) -> bool:
	return ROLES.has(role)


static func is_hostile(role: StringName) -> bool:
	return HOSTILE_ROLES.has(role)


## Roles that enrol a cultivation path. An NPC is not automatically a cultivator; the
## def decides, and this only reports what the role permits.
static func cultivates(role: StringName) -> bool:
	return CULTIVATING_ROLES.has(role)
