class_name ActorAffinity
extends RefCounted

## One actor's standing with everyone else: the relationships table and the affinities
## map beside it.
##
## ## Why this is not code in `actor.gd`
##
## `core/` is the shared stat/actor foundation every module names, so its public surface is
## load-bearing and the twenty-method cap in `gdlintrc` is a real constraint rather than a
## taste. Three of `Actor`'s members were never about the ACTOR: they are about this actor
## RELATIVE TO OTHERS. Neither is identity, stats, resources, statuses or paths — the
## foundation `core/` is named for — and all three are pure data with one writer each. This
## is the same split [StatusRegistry] already makes for statuses, [ActorPools] for pools
## and [ActorSave] for the save stamp: the actor keeps the fields, and the rule about the
## field lives beside it so there is exactly one place to change it.
##
## ## It is a DELEGATE, never a subclass, and the edge is ONE-WAY
##
## `Actor` has no subclass in this repo — `tests/modules/domain/test_domain_spawner.gd`
## asserts there is none — so nothing inherits a member this file moved. The helpers here
## read and write the actor's PUBLIC fields (`relationships`, `affinities`, `paths`) and
## ask the actor for exactly one thing, `mark_stats_dirty()`. So `Actor` -> `ActorAffinity`
## is the only edge in the pair. Never the reverse: a mutual class reference is what breaks
## compilation.
##
## ## What this file deliberately does NOT own
##
## Nothing was renamed and nothing moved off a caller. `set_relationship` /
## `affinity_with` / `set_affinity` stay declared on `Actor` and still answer there — this
## is where their bodies went, not their doors.

## The actor these rows belong to. Held weakly and used only to dirty the derived stats,
## exactly as [StatusRegistry] does, so a cycle cannot keep a body alive past its save.
var _actor_ref: WeakRef


func _init(actor: Actor) -> void:
	_actor_ref = weakref(actor)


## Record `affinity` toward `partner_id`, and dirty the derived stats that read it.
##
## **Dirtying is the whole reason this is not a bare table write.** A relationship feeds
## the derived stats through `StatContext`, so a write that skipped the invalidator would
## leave every derived figure reading a value no longer on the actor — a table that agrees
## with itself and disagrees with the actor.
func set_relationship(actor: Actor, partner_id: StringName, affinity: float) -> void:
	actor.relationships[partner_id] = affinity
	_dirty(actor)


## The standing this actor holds toward `partner_id`, `0.0` for someone it has never met.
##
## `0.0` rather than an error: an unknown partner is an actor nobody has met yet, and
## that is a number rather than a failure.
func affinity_with(actor: Actor, partner_id: StringName) -> float:
	return float(actor.relationships.get(partner_id, 0.0))


## Set the element affinity `element_id` to `value`.
##
## The affinities map publishes its OWN `changed` signal, which [StatsInvalidator] is
## already connected to from `_init` — so this needs no dirtying of its own and must not
## gain one: a second invalidation for one write would rebuild the same stat cache twice.
## That asymmetry against [method set_relationship] is deliberate and is why the two
## cannot be one method.
func set_affinity(actor: Actor, element_id: StringName, value: float) -> void:
	actor.affinities.set_value(element_id, value)


## An actor mid-construction has no stats, and a relationship written against nothing is
## not worth a crash; the same allowance [StatusRegistry] makes.
func _dirty(actor: Actor) -> void:
	if actor != null and actor.stats != null:
		actor.mark_stats_dirty()
