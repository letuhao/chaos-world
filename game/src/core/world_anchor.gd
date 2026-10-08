class_name WorldAnchor
extends RefCounted

## High-tier milestone schedule shared by every cultivation path (ADR 0018-0021,
## 0058). A breakthrough *commits* the anchor its own tier produces, and the next
## tier gates on that commitment. Requiring a realm's own anchor as its prerequisite
## would be circular and therefore unsatisfiable: nothing can create an inside
## world before the breakthrough that needs one. That circularity is why R19-R30
## used to be reachable only by tests writing success flags directly.
##
## Every gate here reads a NAMED ARTIFACT — a law, a layer, a stamp, or a walked
## ascent — never a bare tier or a bare stability flag. `app/main.gd` hands a
## first-realm actor a Micro world that is already stable, and `InsideWorld` starts
## at 0.5 against a 0.5 threshold, so the flags alone opened R19-R30 on a bare actor
## and no tier could fail.
##
## The Mind path carries its own richer stage policy (`MindAnchor`); this class is
## the path-agnostic floor that Body and Qi share, and it is what
## `Breakthrough.tier_gates_met` consults.

## Ladder indices (0-based) at which a breakthrough commits a milestone.
const COMMIT_SEED := 18
const COMMIT_POCKET := 21
const COMMIT_INNER := 24
## Entering R28 (index 27) is the first Transcendent realm, so it is where the
## Micro world and the *start* of an ascension are produced. It walks no step:
## `ascend` is what finishes the ascent, and the gate the ascent opens sits on the
## next tier, so letting this breakthrough finish it would be circular again.
const COMMIT_MICRO := 27
const COMMIT_GREAT := 29

## Laws a committed inside world is stamped with, one per committed tier. A band
## reads the law its own tier's *predecessor* imprinted, so the law a band needs is
## never written by the band that demands it.
const LAW_EARTH := &"earth"
const LAW_HEAVEN := &"heaven"
const LAW_PRIMORDIAL := &"primordial"
const LAW_TRANSCENDENT := &"transcendent"
## Every law is imprinted at full strength. A law is a named marker, not a dial:
## `stage_met` asks "is this law here", so a partial value would be a second,
## unwritten threshold.
const LAW_STRENGTH := 1.0

## Abilities a committed milestone grants. Granted once, by the breakthrough that
## produced the milestone.
const ABILITY_WORLD_CREATION := &"world_creation"
const ABILITY_GREAT_WORLD := &"great_world"

## Inside-world tier committed at each anchor index.
const TIER_BY_COMMIT := {
	COMMIT_SEED: InsideWorld.SEED,
	COMMIT_POCKET: InsideWorld.POCKET,
	COMMIT_INNER: InsideWorld.INNER,
}

## Law each committed inside-world tier imprints.
const LAW_BY_COMMIT := {
	COMMIT_SEED: LAW_EARTH,
	COMMIT_POCKET: LAW_HEAVEN,
	COMMIT_INNER: LAW_PRIMORDIAL,
}

## Space each inside-world tier commits. A higher tier is a bigger world, not the
## same one relabelled.
const SIZE_BY_TIER := {InsideWorld.SEED: 1.0, InsideWorld.POCKET: 2.0, InsideWorld.INNER: 3.0}

## Ability each Transcendent milestone grants.
const ABILITY_BY_COMMIT := {
	COMMIT_MICRO: ABILITY_WORLD_CREATION,
	COMMIT_GREAT: ABILITY_GREAT_WORLD,
}

## The wording `ascension_unmet` reports when no ascent has begun.
const NO_ASCENT := "LOC_CORE_A5BD955D5A"

## Ceiling on the stability raises a construction step takes. It names the failure
## it catches — a CREATED world whose stability cannot reach the `is_stable`
## threshold — and is never the reason a milestone commits: 0.1 a step clears any
## shortfall a fresh world can have, so the bound is headroom, not a budget. Only
## the created world needs it; an INSIDE world's constructor default is already at
## the threshold and nothing lowers it (ADR 0172).
##
## That same fact is why `InsideWorld.strengthen_anchor` no longer raises stability:
## its 0.1 never reached `Tribulation.PREPARATION_FLOOR` through
## `Tribulation._arena_quality` (BL-0830). Do not restore it as headroom — it was not
## headroom, it was a second number nothing could fail on.
const STABILITY_GUARD := 6


## Commit the milestone a successful breakthrough into `target_index` produces.
## Idempotent: a milestone that already committed does not re-create, re-grow, or
## re-grant anything, so a repeated commit cannot be a second, larger artifact.
static func commit(actor: Actor, target_index: int) -> void:
	if TIER_BY_COMMIT.has(target_index):
		_commit_inside_world(actor, TIER_BY_COMMIT[target_index], LAW_BY_COMMIT[target_index])
		return
	if target_index == COMMIT_MICRO:
		_commit_micro_world(actor)
		return
	if target_index == COMMIT_GREAT:
		_commit_great_world(actor)


## True when every milestone committed strictly *before* `target_index` is in
## place, so the realm can be entered. Never requires the realm's own milestone, and
## never checks the ascent — `Breakthrough.ascension_ok` owns that gate, and R30's own
## breakthrough commits the Great world, so a schedule entry there would be circular.
static func stage_met(actor: Actor, target_index: int) -> bool:
	if target_index <= COMMIT_SEED:
		return true
	if target_index <= COMMIT_POCKET:
		return _inside_met(actor, InsideWorld.SEED, LAW_EARTH)
	if target_index <= COMMIT_INNER:
		return _inside_met(actor, InsideWorld.POCKET, LAW_HEAVEN)
	if target_index <= COMMIT_MICRO:
		return _inside_met(actor, InsideWorld.INNER, LAW_PRIMORDIAL)
	if target_index <= COMMIT_GREAT:
		return _world_met(actor)
	return false


## Walk ONE step of the Transcendent ascent: one stage, one dao level, and one
## step's comprehension. Four steps reach the caps and the fifth is refused, so
## `while WorldAnchor.ascend(actor)` terminates on the state rather than on a
## caller-supplied bound.
##
## A core entry point, as ADR 0041 placed the tribulation's: the ascent belongs to no
## single path — every path carries the same `AscensionState` — so no facade serves
## it, and `ui` may call `core` directly. Refused when no ascent has begun: the
## ritual needs the Transcendent breakthrough that begins it, and an ascent invented
## on demand would be a gate that opens itself.
static func ascend(actor: Actor) -> bool:
	if actor == null or actor.ascension == null:
		return false
	return actor.ascension.ascend()


## The part of the ascent this actor has not walked, or "" when there is nothing
## left. The preview wording, so a screen reports the rule `Breakthrough.ascension_ok`
## enforces instead of restating the requirement (ADR 0034). Only meaningful above
## `COMMIT_MICRO`, which is the band whose gate reads the ascent at all.
static func ascension_unmet(actor: Actor) -> String:
	# A SENTINEL, not a sentence: three UI suites assert this value is published UNTOUCHED and
	# only the wording on screen is withheld, so the key must not be resolved here.
	if actor == null or actor.ascension == null:
		return NO_ASCENT
	var remaining := actor.ascension.steps_remaining()
	if remaining <= 0:
		return ""
	return (
		"Walk the ascent: %d of %d steps to walk"
		% [
			remaining,
			AscensionState.ASCENT_STEPS,
		]
	)


## Highest inside-world milestone committed so far, or empty.
static func inside_tier(actor: Actor) -> StringName:
	if actor.inside_world == null:
		return &""
	return actor.inside_world.tier


# --- Internals -------------------------------------------------------------


## Create or grow the inside world this tier commits, then stamp it. Growth happens
## only on a tier change, so re-committing the tier the actor already carries cannot
## inflate it — that is what makes the milestone one artifact rather than a ratchet.
static func _commit_inside_world(actor: Actor, tier: StringName, law_id: StringName) -> void:
	if actor.inside_world == null or actor.inside_world.tier != tier:
		actor.inside_world = InsideWorld.new(tier)
		actor.inside_world.expand_size(float(SIZE_BY_TIER[tier]) - actor.inside_world.size)
	actor.inside_world.add_law(law_id, LAW_STRENGTH)
	actor.inside_world.create_anchor()
	# The commit creates the anchor. It must NOT reinforce it.
	#
	# Reinforcement is the one clause a commit may never grant, because it is what the
	# NEXT realm's gate demands: `MindAnchor._inside_ok` requires `anchor_strengthened`,
	# and `MindTraining.strengthen_anchor` is the only production route to it. While this
	# line stamped that flag, `Breakthrough.try_advance` -- which calls
	# `WorldAnchor.commit` for every path at breakthrough.gd:56 -- paid the Mind anchor
	# gate with the very breakthrough the gate was supposed to govern. The stage read
	# open, the resonance milestone was never paid, and the tier milestones were
	# decorative.
	#
	# Nothing outside `mind_cultivation` reads this flag: core's own `_inside_met` checks
	# the law and the stability, not the anchor. So dropping it costs body and qi nothing
	# and hands the mind tier its gate back.
	_mirror(actor, &"inside_world", actor.inside_world)


## Entering R28 builds the Micro world and BEGINS the ascent. It walks no step and
## grants no dao level, because the gate the finished ascent opens sits on R29 and
## R30: a breakthrough that finished its own prerequisite would open it for free.
static func _commit_micro_world(actor: Actor) -> void:
	if actor.inside_world != null:
		actor.inside_world.add_law(LAW_TRANSCENDENT, LAW_STRENGTH)
	_commit_created_world(actor, WorldState.MICRO)
	_begin_ascent(actor)


## Entering R30 raises the tier and grants its ability. It walks no step either, and
## it never rewrites the stamp: the world it promotes is still the one R28 built.
static func _commit_great_world(actor: Actor) -> void:
	_commit_created_world(actor, WorldState.GREAT)
	if actor.ascension == null:
		actor.ascension = AscensionState.new()
	actor.ascension.add_ability(ABILITY_BY_COMMIT[COMMIT_GREAT])


## Build or promote the created world. The stamp and the structure layer are written
## only when absent, so the R30 breakthrough cannot re-stamp a world R28 built and a
## repeated commit cannot add a second structure layer.
##
## Stability CONVERGES to the threshold rather than taking a fixed step toward it, the
## same rule `_commit_inside_world` follows and for the same reason. A fixed `+0.2`
## is a step, not a construction: a world destabilised below the threshold by a
## conflict is promoted past it, and the actor can never reach it again — no later
## commit exists for R29, whose gate is this milestone. Converging makes the commit
## idempotent as well as sufficient, because a world that is already stable takes zero
## steps where a fixed increment takes one every time.
static func _commit_created_world(actor: Actor, tier: StringName) -> void:
	if actor.world == null:
		actor.world = WorldState.new(WorldState.MICRO)
	if actor.world.origin_index < 0:
		actor.world.origin_index = COMMIT_MICRO
	if actor.world.get_layer(WorldState.STRUCTURE_LAYER) == null:
		actor.world.add_layer(WorldLayerState.new(WorldState.STRUCTURE_LAYER, "Structure", 1.0))
	actor.world.tier = tier
	var guard := 0
	while not actor.world.is_stable() and guard < STABILITY_GUARD:
		guard += 1
		actor.world.stability = clampf(actor.world.stability + 0.1, 0.0, 1.0)
	_mirror(actor, &"world", actor.world)


## Name the dao the ascent is walked into and grant the milestone's one ability.
static func _begin_ascent(actor: Actor) -> void:
	if actor.ascension == null:
		actor.ascension = AscensionState.new()
	actor.ascension.dao_type = LAW_TRANSCENDENT
	actor.ascension.add_ability(ABILITY_BY_COMMIT[COMMIT_MICRO])


## An inside world counts once it carries the tier's law AND is stable. The law is
## read alongside the tier because a tier is a label a world can be handed, and the
## law is what the breakthrough that grew it left behind.
static func _inside_met(actor: Actor, tier: StringName, law_id: StringName) -> bool:
	var inside := actor.inside_world
	if inside == null or inside.tier != tier:
		return false
	if inside.get_law(law_id) != LAW_STRENGTH:
		return false
	return inside.is_stable()


## A created world counts once a breakthrough built it — which is what the stamp and
## the structure layer say together — and it is still stable. Tier and stability
## alone cannot: `app/main.gd` hands a first-realm actor a stable Micro world, so
## those two made R29 unfailable (ADR 0058).
static func _world_met(actor: Actor) -> bool:
	var world := actor.world
	if world == null or not world.is_stable():
		return false
	if world.origin_index != COMMIT_MICRO:
		return false
	return world.get_layer(WorldState.STRUCTURE_LAYER) != null


## Mirror a committed world into `Actor.components`, which is where every
## `StatProvider` reads it. `Actor` registers `ascension` from its own setter but
## leaves the two created worlds as plain fields, so without this the registered
## providers read null (ADR 0058).
static func _mirror(actor: Actor, id: StringName, value: RefCounted) -> void:
	if value != null:
		actor.components[id] = value
