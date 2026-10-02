class_name WorldAnchor
extends RefCounted

## High-tier milestone schedule shared by every cultivation path (ADR 0018-0021).
##
## A breakthrough *commits* the anchor its own tier produces, and the next tier
## gates on that commitment. Requiring a realm's own anchor as its prerequisite
## would be circular and therefore unsatisfiable: nothing can create an inside
## world before the breakthrough that needs one. That circularity is why R19-R30
## used to be reachable only by tests writing success flags directly.
##
## The Mind path carries its own richer stage policy (`MindAnchor`); this class
## is the path-agnostic floor that Body and Qi share, and it is what
## `Breakthrough.tier_gates_met` consults.

## Ladder indices (0-based) at which a breakthrough commits a milestone.
const COMMIT_SEED := 18
const COMMIT_POCKET := 21
const COMMIT_INNER := 24
## Entering R28 (index 27) is the first Transcendent realm, so it is where the
## Micro world and a *completed* ascension are produced. Requiring a completed
## ascension to enter R28 while R28 is what completes it would be circular again,
## so the gate lands on the next tier instead.
const COMMIT_MICRO := 27
const COMMIT_GREAT := 29

## Inside-world tier committed at each anchor index.
const TIER_BY_COMMIT := {
	COMMIT_SEED: InsideWorld.SEED,
	COMMIT_POCKET: InsideWorld.POCKET,
	COMMIT_INNER: InsideWorld.INNER,
}


## Commit the milestone a successful breakthrough into `target_index` produces.
## Idempotent: a tier that already committed does not re-create or re-raise it.
static func commit(actor: Actor, target_index: int) -> void:
	if TIER_BY_COMMIT.has(target_index):
		_commit_inside_world(actor, TIER_BY_COMMIT[target_index])
	elif target_index == COMMIT_MICRO:
		_commit_micro_world(actor)
	elif target_index == COMMIT_GREAT:
		_commit_great_world(actor)


## True when every milestone committed strictly *before* `target_index` is in
## place, so the realm can be entered. Never requires the realm's own milestone.
static func stage_met(actor: Actor, target_index: int) -> bool:
	if target_index <= COMMIT_SEED:
		return true
	if target_index <= COMMIT_POCKET:
		return _inside_trial_met(actor, InsideWorld.SEED)
	if target_index <= COMMIT_INNER:
		return _inside_trial_met(actor, InsideWorld.POCKET)
	if target_index <= COMMIT_MICRO:
		return _inside_trial_met(actor, InsideWorld.INNER)
	if target_index <= COMMIT_GREAT:
		return _world_met(actor)
	return _ascension_met(actor)


## Highest inside-world milestone committed so far, or empty.
static func inside_tier(actor: Actor) -> StringName:
	if actor.inside_world == null:
		return &""
	return actor.inside_world.tier


static func _commit_inside_world(actor: Actor, tier: StringName) -> void:
	if actor.inside_world == null or actor.inside_world.tier != tier:
		actor.inside_world = InsideWorld.new(tier)
	actor.inside_world.create_anchor()
	actor.inside_world.pass_anchor_trial()
	# `is_stable` needs stability >= 0.5; a fresh Seed starts at 0.5 and the
	# higher tiers start lower, so raise until the milestone counts as stable.
	while actor.inside_world.stability < 0.5:
		actor.inside_world.improve_stability(0.1)
	actor.inside_world.strengthen_anchor()


static func _commit_micro_world(actor: Actor) -> void:
	if actor.world == null:
		actor.world = WorldState.new(WorldState.MICRO)
	actor.world.tier = WorldState.MICRO
	actor.world.stability = clampf(actor.world.stability + 0.2, 0.0, 1.0)
	# The Transcendent tier opens with a finished ascension, so the gate on it
	# lands on the *next* realm rather than on this one.
	_complete_ascension(actor)


static func _commit_great_world(actor: Actor) -> void:
	if actor.world == null:
		actor.world = WorldState.new(WorldState.MICRO)
	actor.world.tier = WorldState.GREAT
	actor.world.stability = clampf(actor.world.stability + 0.2, 0.0, 1.0)
	_complete_ascension(actor)


static func _complete_ascension(actor: Actor) -> void:
	if actor.ascension == null:
		actor.ascension = AscensionState.new()
	var guard := 0
	while not actor.ascension.is_complete() and guard < 8:
		guard += 1
		actor.ascension.advance_stage()
		actor.ascension.improve_dao(1)


static func _inside_trial_met(actor: Actor, tier: StringName) -> bool:
	var inside := actor.inside_world
	if inside == null or inside.tier != tier:
		return false
	return inside.is_stable()


static func _world_met(actor: Actor) -> bool:
	return actor.world != null and actor.world.is_stable()


static func _ascension_met(actor: Actor) -> bool:
	return actor.ascension != null and actor.ascension.is_complete()
