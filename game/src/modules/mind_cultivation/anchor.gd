class_name MindAnchor
extends RefCounted

## High-tier anchor policy for the Mind path (ADR 0024). Realms 19-30 keep
## growing the same Thức Hải and the same twenty channels; the "anchor" is the
## physiological commitment a tier demands, not a second reservoir.
##
## Every requirement references a *previously committed* anchor. The anchor a
## breakthrough creates is that same breakthrough's outcome, so no tier ever
## requires its own anchor as a prerequisite:
##
##   R19  commits the Seed anchor    (nothing required before it)
##   R20  requires the Seed anchor created and its trial passed
##   R21  requires the Seed anchor strengthened
##   R22  commits the Pocket anchor
##   R23  requires the Pocket anchor created and its trial passed
##   R24  requires the Pocket anchor strengthened
##   R25  commits the Inner anchor
##   R26  requires the Inner anchor created and its trial passed
##   R27  requires the Inner anchor strengthened
##   R28  commits the Micro world (needs a stable Inner anchor)
##   R29  requires a stable Micro world
##   R30  commits the Great world and completes ascension

## Anchor stages an actor must already have committed.
const STAGE_NONE := &"none"
const STAGE_SEED_TRIAL := &"seed_trial"
const STAGE_SEED_STRENGTHENED := &"seed_strengthened"
const STAGE_POCKET_TRIAL := &"pocket_trial"
const STAGE_POCKET_STRENGTHENED := &"pocket_strengthened"
const STAGE_INNER_TRIAL := &"inner_trial"
const STAGE_INNER_STRENGTHENED := &"inner_strengthened"
const STAGE_MICRO_WORLD := &"micro_world"


## The anchor stage required before entering the realm at `target_index`
## (0-based, matching the shared ladder).
static func required_stage(target_index: int) -> StringName:
	match target_index:
		18:  # R19 earth_immortal — commits the Seed anchor.
			return STAGE_NONE
		19:  # R20 heaven_immortal — Seed anchor created + trial passed.
			return STAGE_SEED_TRIAL
		20:  # R21 golden_immortal — Seed anchor strengthened.
			return STAGE_SEED_STRENGTHENED
		21:  # R22 mystic_immortal — commits the Pocket anchor.
			return STAGE_NONE
		22:  # R23 true_immortal — Pocket anchor created + trial passed.
			return STAGE_POCKET_TRIAL
		23:  # R24 primordial_immortal — Pocket anchor strengthened.
			return STAGE_POCKET_STRENGTHENED
		24:  # R25 great_luo — commits the Inner anchor.
			return STAGE_NONE
		25:  # R26 dao_fruit — Inner anchor created + trial passed.
			return STAGE_INNER_TRIAL
		26:  # R27 immortal_sovereign — Inner anchor strengthened.
			return STAGE_INNER_STRENGTHENED
		27:  # R28 transcendent — commits the Micro world.
			return STAGE_INNER_STRENGTHENED
		28:  # R29 dao_ancestor — requires the Micro world committed at R28.
			return STAGE_MICRO_WORLD
		29:  # R30 primordial_origin — commits the Great world.
			return STAGE_MICRO_WORLD
		_:
			# Realms below the Immortal tier have no anchor requirement at all.
			return STAGE_NONE if target_index < 18 else STAGE_INNER_STRENGTHENED


## True when the actor's committed anchors satisfy `stage`.
static func stage_met(actor: Actor, stage: StringName) -> bool:
	match stage:
		STAGE_SEED_TRIAL:
			return _inside_ok(actor, InsideWorld.SEED, false)
		STAGE_SEED_STRENGTHENED:
			return _inside_ok(actor, InsideWorld.SEED, true)
		STAGE_POCKET_TRIAL:
			return _inside_ok(actor, InsideWorld.POCKET, false)
		STAGE_POCKET_STRENGTHENED:
			return _inside_ok(actor, InsideWorld.POCKET, true)
		STAGE_INNER_TRIAL:
			return _inside_ok(actor, InsideWorld.INNER, false)
		STAGE_INNER_STRENGTHENED:
			return _inside_ok(actor, InsideWorld.INNER, true)
		STAGE_MICRO_WORLD:
			return (
				actor.world != null
				and actor.world.tier == WorldState.MICRO
				and actor.world.is_stable()
			)
		_:
			# STAGE_NONE and anything unknown need no committed anchor.
			return stage == STAGE_NONE


## Human-readable requirement for the UI.
static func describe_stage(stage: StringName) -> String:
	match stage:
		STAGE_NONE:
			return "No prior anchor required"
		STAGE_SEED_TRIAL:
			return "Seed World anchor created and its trial passed"
		STAGE_SEED_STRENGTHENED:
			return "Seed World anchor strengthened and stable"
		STAGE_POCKET_TRIAL:
			return "Pocket World anchor created and its trial passed"
		STAGE_POCKET_STRENGTHENED:
			return "Pocket World anchor strengthened and stable"
		STAGE_INNER_TRIAL:
			return "Inner World anchor created and its trial passed"
		STAGE_INNER_STRENGTHENED:
			return "Inner World anchor strengthened and stable"
		STAGE_MICRO_WORLD:
			return "A stable Micro World"
		_:
			return "Unknown anchor requirement"


## Commit the anchor this breakthrough creates. Idempotent: a realm that already
## committed its anchor does not re-create it.
static func commit(actor: Actor, target_index: int) -> void:
	match target_index:
		18:
			_commit_inside_world(actor, InsideWorld.SEED)
		21:
			_commit_inside_world(actor, InsideWorld.POCKET)
		24:
			_commit_inside_world(actor, InsideWorld.INNER)
		27:
			_commit_micro_world(actor)
		29:
			_commit_great_world(actor)


static func _commit_inside_world(actor: Actor, tier: StringName) -> void:
	if actor.inside_world == null or actor.inside_world.tier != tier:
		actor.inside_world = InsideWorld.new(tier)
	actor.inside_world.create_anchor()
	actor.inside_world.pass_anchor_trial()
	actor.inside_world.improve_stability(0.1)


static func _commit_micro_world(actor: Actor) -> void:
	if actor.world == null:
		actor.world = WorldState.new(WorldState.MICRO)
	actor.world.tier = WorldState.MICRO
	# WorldState owns stability as plain state (ADR 0019); the Mind path only
	# raises it, never reads or reinterprets it.
	actor.world.stability = clampf(actor.world.stability + 0.2, 0.0, 1.0)
	if actor.ascension == null:
		actor.ascension = AscensionState.new()
	actor.ascension.advance_stage()
	actor.ascension.improve_dao(2)


static func _commit_great_world(actor: Actor) -> void:
	if actor.world == null:
		actor.world = WorldState.new(WorldState.MICRO)
	actor.world.tier = WorldState.GREAT
	actor.world.stability = clampf(actor.world.stability + 0.2, 0.0, 1.0)
	if actor.ascension == null:
		actor.ascension = AscensionState.new()
	while actor.ascension.stage < AscensionState.STAGE_TRANSCENDENCE:
		actor.ascension.advance_stage()
	actor.ascension.improve_dao(AscensionState.MAX_DAO_LEVEL)


static func _inside_ok(actor: Actor, tier: StringName, strengthened: bool) -> bool:
	var world := actor.inside_world
	if world == null or world.tier != tier:
		return false
	if not world.anchor_created or not world.anchor_trial_passed:
		return false
	if strengthened and not world.anchor_strengthened:
		return false
	return world.is_stable()
