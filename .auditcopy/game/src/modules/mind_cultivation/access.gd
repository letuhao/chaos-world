class_name MindAccess
extends RefCounted

## Module-internal accessors, deliberately NOT on the facade (ADR 0095).
##
## `MindCultivationApi` sits at the 12-method ISP cap
## (`tools/arch/rules.py` `MAX_FACADE_PUBLIC_METHODS`), and `path_def` was one of
## those twelve while nothing outside this module ever called it: its only caller
## in the whole tree is `test_mind_path.gd`. A cap spent on an accessor nobody uses
## is a cap not spent on a verb, so `recover_next` had nowhere to go until this
## file existed. Same pattern as `qi_cultivation/access.gd`: moving it costs
## nothing (`tools arch` counts only `api.gd`) and leaves the facade publishing
## verbs. This mirrors the exact reasoning that freed `attach`'s dantian line
## there — `tools arch` cannot see a module-internal accessor.


static func path_def() -> CultivationPathDef:
	return MindPath.path_def()


## ## The MASTERY LEDGER, moved here from the facade
##
## `mastery` and `attach_mastery` were two of the facade's fourteen public methods
## while `MAX_FACADE_PUBLIC_METHODS` is 12. Both are ACCESSORS over one component key
## rather than verbs, and this file is exactly what an accessor belongs in — the same
## reason `path_def` is here and the same reason `qi_cultivation/access.gd` holds
## `dantian`/`attach_dantian`.
##
## ## Why this is a MOVE and not a deletion
##
## The ledger is load-bearing: `attach` mints it, and `status`'s `MindStatusApi`
## banks into it on every confrontation. Moving it off the facade does not remove it
## from the module, it removes it from the PUBLISHED surface — and the one external
## reader is repointed at this file rather than left to call a verb that no longer
## exists. `MindStatusApi` names this type, not `MindCultivationApi.mastery`, for the
## reason its own docblock already records: `status` may not declare a
## `status -> mind_cultivation` dependency, so a bare class reference is the
## AGENTS.md-sanctioned spelling that keeps the registry honest
## (`BARE_REF_UNITS` excludes `modules/*`).
static func mastery(actor: Actor) -> MindMasteryState:
	if actor == null:
		return null
	return actor.component(MindMastery.STATE_COMPONENT) as MindMasteryState


## Give the actor the two mastery tracks and the composure reserve they are spent
## from. Idempotent, and — as with `attach_sea` — the provider and the pool are
## registered OUTSIDE the "no component yet" branch, because re-attaching IS how a
## restored actor gets its providers back (`Actor.from_dict` restores components
## and never a `StatProvider`).
##
## ## Why the COMPOSURE pool is minted here and not on first use
##
## `MindExpression` reads `MindVocabulary.COMPOSURE_POOL` off the target and treats
## an unbound pool as "no composure to take", which is the right degradation for a
## foreign actor. But a mind cultivator who enrolled on this path and therefore has
## a sea must also have a composure, or the expression track is half-live on every
## actor the game builds — the same defect `attach_sea`'s docblock records for the
## sea, one mechanism over.
##
## Minted at FULL and zero-cost to regenerate: the reserve is drained by
## projections and refilled by the defender's own beat, so it is a fight-time budget
## rather than a cultivation-time one. Full at attach is the honest starting state —
## a body that has never been projected at has all of its composure.
static func attach_mastery(actor: Actor) -> MindMasteryState:
	if actor == null:
		return null
	var existing := mastery(actor)
	if existing == null:
		existing = MindMasteryState.new()
		actor.set_component(MindMastery.STATE_COMPONENT, existing)
	if not has_provider(actor, MindMasteryProvider):
		actor.stats.add_provider(MindMasteryProvider.new())
	add_pool(actor, MindVocabulary.COMPOSURE_POOL, true)
	return existing


## Whether a provider of exactly this script is already registered. The facade's
## `attach`/`attach_sea` share it, so it lives here rather than being written twice:
## `tools arch` counts only `api.gd`, and two copies of this loop are two places a
## future provider id can be added to one of and not the other.
static func has_provider(actor: Actor, type: Script) -> bool:
	for entry in actor.stats._providers:
		if entry.get_script() == type:
			return true
	return false


## Mint a `ResourcePool` under `id` when the actor carries none. `full` is false for
## a resource the actor has to EARN (mind power, awareness start empty) and true for
## one that is a fight-time budget already spent to zero (the composure reserve).
static func add_pool(actor: Actor, id: StringName, full: bool) -> void:
	if actor.resource(id) != null:
		return
	var pool := ResourcePool.new(id, 100.0)
	if not full:
		pool.current = 0.0
	actor.add_resource(pool)
