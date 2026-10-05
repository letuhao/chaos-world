class_name MindAnchor
extends RefCounted

## High-tier anchor policy for the Mind path (ADR 0024). Realms 19-30 keep
## growing the same Thức Hải and the same twenty channels; the "anchor" is the
## physiological commitment a tier demands, not a second reservoir.
##
## A tier COMMITS an anchor and the boundaries after it GATE on it. The gate is
## deliberately NOT satisfied by the commit: a commit creates the world, while a gate
## additionally demands the anchor REINFORCED, which is the resonance milestone
## (`MindTraining.strengthen_anchor`) and costs the realm's channel elixir. Two
## separate acts, so a demanded stage can be false: an actor that has entered the tier
## which commits an anchor has not yet earned the right to leave the next one.
##
## Before that rule the commit satisfied the very gate that permitted it and five
## high-tier boundaries were permanently open — R20, R23 and R26 (the trial) and
## R29/R30 (a Micro world that `app` hands out at the first realm already
## satisfies). The advertised difficulty did not exist.
##
## The TRIAL that clause named is gone (ADR 0172). Both commits stamped the trial
## flag on the line after creating the anchor, so `anchor_created` implied it and the
## conjunct no code could fail. Reinforcement is the one paid clause, and it is paid
## with a verb; the trial was paid by nothing and gated nothing.
##
##   R19  commits the Seed inside world   (demands nothing)
##   R20  demands the Seed anchor reinforced
##   R21  demands the Seed anchor reinforced
##   R22  commits the Pocket inside world (demands nothing)
##   R23  demands the Pocket anchor reinforced
##   R24  demands the Pocket anchor reinforced
##   R25  commits the Inner inside world  (demands nothing)
##   R26  demands the Inner anchor reinforced
##   R27  demands the Inner anchor reinforced
##   R28  commits the Micro world         (demands the Inner anchor reinforced)
##   R29  demands the Micro world R28 built, and the Inner anchor reinforced
##   R30  commits the Great world         (demands the same)

## The ladder indices at which each anchor is committed. These are the SAME numbers
## `commit()` matches on, named once so a caller never restates an index and drifts
## from the policy: the schedule above is authored data, and a test or a screen that
## hard-codes 18 to mean "Seed" re-derives the table instead of reading it.
const COMMIT_SEED := 18
const COMMIT_POCKET := 21
const COMMIT_INNER := 24
const COMMIT_MICRO := 27
const COMMIT_GREAT := 29
## The first boundary that gates on a created world rather than an inside world.
const FIRST_MICRO_GATE := 28

## Anchor stages an actor must already have committed.
const STAGE_NONE := &"none"
const STAGE_SEED_ANCHOR := &"seed_anchor"
const STAGE_POCKET_ANCHOR := &"pocket_anchor"
const STAGE_INNER_ANCHOR := &"inner_anchor"
const STAGE_MICRO_WORLD := &"micro_world"

## The law a Transcendent breakthrough imprints on the world it builds, and the
## value it is imprinted at. `app` hands a first-realm actor a Micro world and
## `WorldState.is_stable` accepts its default, so `tier` and stability cannot tell a
## world a breakthrough built from one nobody built; naming the artifact can
## (ADR 0058's rule, applied to the API core offers).
const MICRO_WORLD_LAW := &"mind_micro_world"
const LAW_STRENGTH := 1.0


## The anchor stage required before entering the realm at `target_index`
## (0-based, matching the shared ladder).
static func required_stage(target_index: int) -> StringName:
	match target_index:
		COMMIT_SEED, COMMIT_POCKET, COMMIT_INNER:
			# The tier that commits an anchor never demands one of its own.
			return STAGE_NONE
		FIRST_MICRO_GATE, COMMIT_GREAT:
			# R29 and R30 both gate on the created world R28 built. R30 is also the
			# tier that commits the Great world, so it must not demand that one.
			return STAGE_MICRO_WORLD
		_:
			if target_index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
				return STAGE_NONE
			if target_index <= COMMIT_POCKET:
				return STAGE_SEED_ANCHOR
			if target_index <= COMMIT_INNER:
				return STAGE_POCKET_ANCHOR
			return STAGE_INNER_ANCHOR


## True when the actor's committed anchors satisfy `stage`.
static func stage_met(actor: Actor, stage: StringName) -> bool:
	match stage:
		STAGE_SEED_ANCHOR:
			return _inside_ok(actor, InsideWorld.SEED)
		STAGE_POCKET_ANCHOR:
			return _inside_ok(actor, InsideWorld.POCKET)
		STAGE_INNER_ANCHOR:
			return _inside_ok(actor, InsideWorld.INNER)
		STAGE_MICRO_WORLD:
			# The deepest stage is the only one with nothing of its own to
			# reinforce, so it takes the last milestone that IS separately paid for:
			# the Inner World anchor. Without it R28's own commit would open this
			# gate, because a created world has no reinforced state to demand.
			return _world_ok(actor) and _inside_ok(actor, InsideWorld.INNER)
		_:
			# STAGE_NONE and anything unknown need no committed anchor.
			return stage == STAGE_NONE


## The part of `stage` this actor has not earned yet, or "" when it has earned it.
## `describe_stage` names the rule; this names the shortfall, so a screen shows what
## is outstanding instead of restating the requirement.
static func outstanding(actor: Actor, stage: StringName) -> String:
	if stage == STAGE_NONE or stage_met(actor, stage):
		return ""
	if stage == STAGE_MICRO_WORLD:
		# Two milestones stand in the way of this stage: the last inside world and
		# the world the Transcendent breakthrough builds. Reported in the order they
		# have to be earned, and never as the wrong one.
		if not _inside_ok(actor, InsideWorld.INNER):
			return _inside_shortfall(actor, InsideWorld.INNER)
		return _world_shortfall(actor)
	return _inside_shortfall(actor, _stage_tier(stage))


## Human-readable requirement for the UI.
static func describe_stage(stage: StringName) -> String:
	match stage:
		STAGE_NONE:
			return "No prior anchor required"
		STAGE_SEED_ANCHOR:
			return "Seed World anchor created and reinforced"
		STAGE_POCKET_ANCHOR:
			return "Pocket World anchor created and reinforced"
		STAGE_INNER_ANCHOR:
			return "Inner World anchor created and reinforced"
		STAGE_MICRO_WORLD:
			return "A Micro World built by a breakthrough, and the Inner World anchor reinforced"
		_:
			return "Unknown anchor requirement"


## Commit the anchor this breakthrough creates. Idempotent: a realm that already
## committed its anchor does not re-create it.
static func commit(actor: Actor, target_index: int) -> void:
	match target_index:
		COMMIT_SEED:
			_commit_inside_world(actor, InsideWorld.SEED)
		COMMIT_POCKET:
			_commit_inside_world(actor, InsideWorld.POCKET)
		COMMIT_INNER:
			_commit_inside_world(actor, InsideWorld.INNER)
		COMMIT_MICRO:
			_commit_created_world(actor, WorldState.MICRO, target_index)
		COMMIT_GREAT:
			_commit_created_world(actor, WorldState.GREAT, target_index)


## Create the inside world this breakthrough produces. It creates the anchor; it never
## REINFORCES it, which is the one clause of a demanded stage the commit cannot
## satisfy for the actor (`_inside_ok`).
static func _commit_inside_world(actor: Actor, tier: StringName) -> void:
	if actor.inside_world == null or actor.inside_world.tier != tier:
		actor.inside_world = InsideWorld.new(tier)
	actor.inside_world.create_anchor()


## Build the created world a Transcendent breakthrough produces. The LAW it imprints
## is what the R29/R30 gate reads, because a world handed out at the first realm is
## Micro-sized and stable already and carries no law (ADR 0058's rule).
static func _commit_created_world(actor: Actor, tier: StringName, _built_at: int) -> void:
	if actor.world == null:
		actor.world = WorldState.new(WorldState.MICRO)
	actor.world.tier = tier
	if actor.world.get_law(MICRO_WORLD_LAW) == null:
		actor.world.add_law(WorldLawState.new(MICRO_WORLD_LAW, WorldLawState.SPATIAL, LAW_STRENGTH))
	if tier == WorldState.MICRO:
		actor.world.stability = clampf(actor.world.stability + 0.2, 0.0, 1.0)
		if actor.ascension == null:
			actor.ascension = AscensionState.new()
		actor.ascension.advance_stage()
		actor.ascension.improve_dao(2)
	else:
		_finish_ascent(actor)


## The Great world completes the ascent. Bounded by the number of stages core
## defines rather than by a `while` on state that cannot converge past it.
static func _finish_ascent(actor: Actor) -> void:
	if actor.ascension == null:
		actor.ascension = AscensionState.new()
	for step in range(AscensionState.STAGE_TRANSCENDENCE):
		if actor.ascension.stage >= AscensionState.STAGE_TRANSCENDENCE:
			break
		actor.ascension.advance_stage()
	actor.ascension.improve_dao(AscensionState.MAX_DAO_LEVEL)


## An inside world counts once the tier that created it was committed AND
## reinforced. A world that merely exists does not: `anchor_strengthened` is what
## `MindTraining.strengthen_anchor` pays for and what no commit grants.
##
## Every conjunct here is falsifiable by a state a player can legally reach, which is
## the property the removed trial conjunct failed: `anchor_created` implied the trial
## flag, so that term could not be false and constrained nothing (ADR 0172).
static func _inside_ok(actor: Actor, tier: StringName) -> bool:
	var world := actor.inside_world
	if world == null or world.tier != tier:
		return false
	if not world.anchor_created:
		return false
	if not world.anchor_strengthened:
		return false
	return world.is_stable()


## A created world counts once a breakthrough built it and it imprinted the law the
## Transcendent tier commits. The law is read instead of the tier and the stability,
## because a world handed out at the first realm is Micro-sized and stable already.
static func _world_ok(actor: Actor) -> bool:
	var world := actor.world
	if world == null or world.tier != WorldState.MICRO:
		return false
	if world.get_law(MICRO_WORLD_LAW) == null:
		return false
	return world.is_stable()


static func _inside_shortfall(actor: Actor, tier: StringName) -> String:
	if tier == &"":
		return describe_stage(STAGE_NONE)
	var label := _tier_name(tier)
	var world := actor.inside_world
	if world == null:
		return "No %s anchor committed yet" % label
	if world.tier != tier:
		return "%s anchor not committed (the actor holds a %s world)" % [label, world.tier]
	if not world.anchor_created:
		return "%s anchor not created" % label
	if not world.anchor_strengthened:
		return "%s anchor not reinforced (spend the realm's channel elixir)" % label
	return "%s anchor unstable" % label


static func _world_shortfall(actor: Actor) -> String:
	var world := actor.world
	if world == null:
		return "No Micro World built"
	if world.tier != WorldState.MICRO:
		return "Micro World not built (the created world is a %s world)" % world.tier
	if world.get_law(MICRO_WORLD_LAW) == null:
		return "Micro World not built by a breakthrough"
	return "Micro World unstable"


static func _stage_tier(stage: StringName) -> StringName:
	match stage:
		STAGE_SEED_ANCHOR:
			return InsideWorld.SEED
		STAGE_POCKET_ANCHOR:
			return InsideWorld.POCKET
		STAGE_INNER_ANCHOR:
			return InsideWorld.INNER
		_:
			return &""


static func _tier_name(tier: StringName) -> String:
	match tier:
		InsideWorld.SEED:
			return "Seed World"
		InsideWorld.POCKET:
			return "Pocket World"
		InsideWorld.INNER:
			return "Inner World"
		_:
			return "Unknown"
