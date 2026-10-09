class_name QiBreakthroughTransaction
extends RefCounted

## Breakthrough transaction for Qi Cultivation (ADR 0011/0014/0024).
## Implements preview and execution with atomic cost policy.
##
## Preview returns structured unmet conditions and costs without consuming
## anything. Execution validates all conditions, consumes the pill, and
## rolls for success/failure. On failure, applies deviation consequences.

const _ITEMS := preload("res://src/modules/items/api.gd")
## The element gate's mastery read, through the elements facade (ADR 0004's "master
## elements to rise"): the qi path names no element stat of its own.
const _ELEMENTS := preload("res://src/modules/elements/api.gd")
## The foundation record's write (BL-0951): the realm being left gets its perfection
## snapshotted at departure, through the foundation facade like every other module edge.
const _FOUNDATION := preload("res://src/modules/foundation/api.gd")
## How hard a failed breakthrough cracks the dao heart (BL-0932). This path's number,
## not core's: the deviation is the qi path's failure shape, and `QiTraining.recover`
## spends the realm's recovery elixir to mend whatever a deviation left behind.
const HEART_CRACK_ON_DEVIATION := 2.0


## Preview the breakthrough. Returns a dictionary with:
## - can_attempt: bool
## - target_realm: String
## - unmet_conditions: Array[String]
## - costs: Dictionary
## - chance: float (0.0-1.0)
static func preview(actor: Actor) -> Dictionary:
	var result := {
		"can_attempt": false,
		"target_realm": "",
		"unmet_conditions": [],
		"costs": {},
		"chance": 0.0,
	}
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		result["unmet_conditions"].append("no_qi_path")
		return result
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		result["unmet_conditions"].append("max_realm_reached")
		return result
	result["target_realm"] = target.id
	var seed := QiRealmSeed.for_realm(target.id)
	if seed == null:
		result["unmet_conditions"].append("no_seed_for_target")
		return result
	var dantian := QiAccess.dantian(actor)
	if dantian == null:
		result["unmet_conditions"].append("no_dantian")
		return result

	# Check all conditions
	if state.progress < seed.progress_required:
		result["unmet_conditions"].append("insufficient_progress")
	if actor.stats.derived(Stat.COMPREHENSION) < seed.comprehension_required:
		result["unmet_conditions"].append("insufficient_comprehension")
	if dantian.quality < seed.dantian_quality_required:
		result["unmet_conditions"].append("insufficient_quality")
	if dantian.ratio(actor) < seed.dantian_fill_required:
		result["unmet_conditions"].append("dantian_not_full")
	if dantian.injured:
		result["unmet_conditions"].append("dantian_injured")
	if not _ITEMS.has_item(actor, seed.breakthrough_item):
		result["unmet_conditions"].append("missing_breakthrough_item")
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if not seed.channel_met(channel):
			result["unmet_conditions"].append("channel_not_ready:%s" % meridian_id)
	# ADR 0004's "master elements to rise". The same predicate the condition enforces
	# (`QiRealmSeed.element_mastery_met`), so the reported gate is the enforced gate
	# (ADR 0044) and a panel quoting this list quotes the truth.
	if not seed.element_mastery_met(_ELEMENTS.total_mastery(actor)):
		result["unmet_conditions"].append("insufficient_element_mastery")
	# Tier gates. These delegate to the same `Breakthrough` predicates `execute`
	# enforces, so the preview can never disagree with the transaction about
	# whether a realm is enterable (ADR 0032).
	if not Breakthrough.tribulation_ok(actor, target.index):
		result["unmet_conditions"].append("tribulation_not_complete")
	if not Breakthrough.inside_world_ok(actor, target.index):
		result["unmet_conditions"].append("inside_world_not_stable")
	if not Breakthrough.world_ok(actor, target.index):
		result["unmet_conditions"].append("world_not_stable")
	if not Breakthrough.ascension_ok(actor, target.index):
		result["unmet_conditions"].append("ascension_not_complete")
	if not Breakthrough.dao_heart_ok(actor, target.index):
		result["unmet_conditions"].append("dao_heart_too_low")
	# BL-0951: the foundation wall. The carried foundation (the mean perfection of every
	# realm left) must clear the target seed's authored floor; below it the refusal is
	# NAMED and shown here, one attempt ahead of the wall, so it is a cost the player can
	# read rather than a trap.
	if not _foundation_ok(actor, target):
		result["unmet_conditions"].append("foundation_insufficient")

	# BL-0833: the ascension trio the tier-gate block above already gates on, PUBLISHED
	# here so a screen renders the stage, the dao level and completion from the one
	# preview it consumes. `Breakthrough.ascension_ok` reads the ascension OBJECT, so
	# these provider-published stats were read by nothing before this line.
	result["ascension_stage"] = actor.stats.derived(&"ascension_stage")
	result["ascension_dao_level"] = actor.stats.derived(&"ascension_dao_level")
	result["ascension_complete"] = actor.stats.derived(&"ascension_complete")

	# Calculate chance. Reads the dantian and nothing else (ADR 0051's rule).
	result["chance"] = QiChance.of(dantian)
	result["can_attempt"] = result["unmet_conditions"].is_empty()
	result["costs"] = {
		"breakthrough_item": seed.breakthrough_item,
	}
	return result


## Execute the breakthrough. Returns true on success, false on failure.
## On failure, applies deviation consequences (progress loss, dantian damage,
## channel damage). The pill is consumed regardless of outcome.
##
## This is the production entry point, so it re-validates the full condition
## set rather than trusting the caller to have previewed first. Without that,
## two calls in one frame would advance two realms on a single pill with no
## progress, quality, channels, or tier gates checked.
static func execute(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	# **The body answers first (ADR 0109), and it answers HERE.**
	#
	# This is a precondition, not a modifier: a body plan can stop a breakthrough and
	# can never make one easier. It refuses above every other check and costs the actor
	# nothing — no wave fought, no pill spent, no realm moved — because the refusal
	# returns before `face_tribulation` and before anything is consumed.
	#
	# The check sits in the TRANSACTION rather than in a facade because the transaction
	# is the one call every qi entry point makes. `QiCultivationApi.attempt_breakthrough`
	# and `QiAdvancement.try_breakthrough` both land here, so a gate one layer up left
	# itself bypassable the moment a second caller appeared — and a rule a caller can
	# walk around is not a rule. Two predicates, in the order a player would read them:
	# a path the body plan closes, then a realm above its authored ceiling.
	if not _body_allows(actor):
		return false
	# Face the tribulation owed for this path's next realm BEFORE validating anything
	# (ADR 0061). This is the production entry point that makes R19-R30 reachable by
	# play at all: nothing else in `src/` constructs a `Tribulation`, so without this the
	# gate is a wall only a test can pass. One call fights ONE wave, and the return is
	# discarded because a wave never opens the gate — the survivor is spent by the next
	# attempt. A refusal at R19+ therefore mutates the actor: that is ADR 0061's one
	# disclosed exception to ADR 0044, and nothing is granted and no pill is spent here.
	Breakthrough.face_tribulation(actor, QiPath.PATH_ID, rng)
	var state := actor.path(QiPath.PATH_ID)
	if state == null:
		return false
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return false
	var condition := QiBreakthroughCondition.new()
	if not Breakthrough.can_advance(actor, QiPath.PATH_ID, condition):
		return false
	var seed := QiRealmSeed.for_realm(target.id)
	var dantian := QiAccess.dantian(actor)
	if seed == null or dantian == null:
		return false
	# Consume the pill
	if not _ITEMS.consume_item(actor, seed.breakthrough_item):
		return false
	# Roll for success. The same rule the preview reports: the dantian decides,
	# never a quantity this attempt's own entry gate already pinned (ADR 0051).
	var chance := QiChance.of(dantian)
	var roll := randf() if rng == null else rng.randf()
	if roll >= chance:
		_deviate(actor, state, seed, dantian, rng)
		# BL-0951: the attempt was decided, so a final-band actor burns its last years
		# whether the heavens opened or not. Outside the final band this spends nothing.
		_FOUNDATION.burn_final_attempt(actor)
		return false
	# BL-0951: the realm being LEFT gets its PERFECTION snapshotted — how far past this
	# gate the actor trained, measured by the same static the tribulation's own prep
	# rating reads (one formula, no copy). Captured while `state` still names the realm;
	# the write itself is once per realm, so a replay can never rewrite a spent past.
	var leaving := state.rank_id
	var perfection := Tribulation.formation_depth(
		actor, QiCultivationApi.tribulation_gate_requirement(target.id)
	)
	# Advance through the cumulative tier gate so no Immortal+/Transcendent+ gate
	# can be side-stepped. The condition was validated before the pill was
	# consumed, so it is not re-checked here — re-running it would fail on the
	# already-consumed pill.
	#
	# This runs BEFORE anything is granted or emptied. The gate is the only thing
	# that can still refuse at this point, and a refusal must leave the actor
	# exactly as it was found: no realm, no rewards, no drained reservoir.
	var advanced := Breakthrough.try_advance_gated(actor, QiPath.PATH_ID)
	if not advanced:
		return false
	# The departure is real: record the realm's perfection now (BL-0951). A refusal is
	# impossible by construction — the realm is written once and the actor has just left
	# it — so the call needs no branch.
	_FOUNDATION.snapshot(actor, leaving, perfection)
	for key in seed.rewards:
		var id := StringName(key)
		actor.stats.set_base(id, actor.stats.get_base(id) + float(seed.rewards[key]))
	# The dantian empties into the new realm and is re-sealed at its new capacity.
	var pool := actor.resource(QiStats.QI)
	if pool != null:
		pool.current = 0.0
	QiTraining.synchronize(actor)
	# Nothing here decides a tribulation. `Breakthrough.resolve_tribulation` is the
	# only place a fight is decided and the only place its award is paid, so the
	# consumer of a survivor must not pay again: this used to call
	# `apply_result(actor, true)` on entering a high tier, handing R19 twice the
	# insight for one fight and stacking two `heavenly_blessing` statuses
	# (ADR 0041/0061).
	# Entering a high tier *commits* the milestone it produces; the next tier
	# gates on it (ADR 0018-0021).
	WorldAnchor.commit(actor, target.index)
	actor.mark_stats_dirty()
	# BL-0951: the attempt was decided, so a final-band actor burns its last years.
	# Succeed and the lengthened life may pull the body out of the final band; fail and
	# the burn may finish what the lifespan started, through SoulAge/SoulDeath rather
	# than any new death of its own. Outside the final band this spends nothing.
	_FOUNDATION.burn_final_attempt(actor)
	return true


# --- Internals ---------------------------------------------------------------


## BL-0951: the realm's floor. The carried foundation — the mean perfection of every
## realm the actor has LEFT — must stand at or above the target seed's authored
## `min_foundation`; below it the wall is a named refusal. The preview reports the same
## predicate, so the wall a panel shows is the wall the transaction enforces (ADR 0044),
## one attempt ahead of the refusal.
##
## A missing seed is `false`: a realm whose content cannot be read has no authored floor
## to clear, and letting the attempt through would be a gate nobody wrote.
static func _foundation_ok(actor: Actor, target: RealmDef) -> bool:
	var seed := QiRealmSeed.for_realm(target.id)
	if seed == null:
		return false
	return seed.foundation_met(_FOUNDATION.foundation(actor))


## Whether this actor's body plan permits a qi breakthrough at all (ADR 0109).
##
## It is a PRECONDITION and never a modifier: it reads the gate and returns a
## boolean, and nothing here can widen a chance, lower a threshold, or skip a cost.
##
## An actor with no race takes no restriction. That is deliberate and unchanged: no
## body plan has been authored for it, and gating content on a content gap would lock
## a player out of a path nobody ever denied them (ADR 0109's boundary case).
static func _body_allows(actor: Actor) -> bool:
	if actor == null:
		return false
	if not RaceGate.path_unmet(actor, PathState.QI).is_empty():
		return false
	return RaceGate.realm_ceiling_unmet(actor).is_empty()


static func _deviate(
	actor: Actor, state: PathState, seed: QiRealmSeed, dantian: Dantian, rng: RandomNumberGenerator
) -> void:
	# Qi deviation scars the dantian and burns a channel it depended on.
	state.progress *= 0.5
	dantian.damage()
	dantian.set_quality(maxf(0.0, dantian.quality * 0.5))
	if not seed.required_meridians.is_empty():
		actor.meridians.damage_meridian(
			seed.required_meridians[_pick(rng, seed.required_meridians.size())]
		)
	# And the shock CRACKS the dao heart (BL-0932): the deviation is where the ruling
	# names the crack, and `QiTraining.recover`'s elixir is what mends it. The crack is
	# floored by `DaoHeart.crack`, so no deviation can leave a negative heart.
	DaoHeart.crack(actor, HEART_CRACK_ON_DEVIATION)
	actor.mark_stats_dirty()


static func _pick(rng: RandomNumberGenerator, count: int) -> int:
	if count <= 1:
		return 0
	return randi() % count if rng == null else rng.randi_range(0, count - 1)
