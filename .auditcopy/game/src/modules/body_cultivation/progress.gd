class_name BodyProgress
extends RefCounted

## Tracks which realms have completed their strengthening milestone (ADR 0023).
##
## A milestone is the once-only payoff for *training while in* a realm: the first
## channel step taken there. Completing it grants a permanent physique bonus
## scaled to the realm's reservoir, which is what makes the marker load-bearing
## rather than a write-only flag. Completing it twice grants nothing.
##
## Core serializes this component by reading `completed` directly, so there is no
## `to_dict` here to keep in step.

## Physique granted per completed milestone, as a fraction of the realm's
## `integrity_maximum`. At R1 that is +2 physique, at R30 about +7.8.
const MILESTONE_PHYSIQUE_RATIO := 0.02

var completed: Array[StringName] = []


## Whether this realm's milestone has been completed. The idempotency guard that
## makes the physique bonus once-only.
func is_complete(realm_id: StringName) -> bool:
	return completed.has(realm_id)


## Mark the realm complete and grant its one-time bonus. Returns true when this
## call was the one that completed it, so callers can react to the reward.
func mark_complete(actor: Actor, seed: BodyRealmSeed) -> bool:
	if seed == null or is_complete(seed.id):
		return false
	completed.append(seed.id)
	_grant(actor, seed)
	return true


## The once-only reward for completing a realm's milestone. Private because the
## bonus must not be reachable without recording the marker: an exposed grant
## would let a caller re-award physique on every load.
func _grant(actor: Actor, seed: BodyRealmSeed) -> void:
	if actor == null or seed == null:
		return
	var bonus := seed.integrity_maximum * MILESTONE_PHYSIQUE_RATIO
	actor.stats.set_base(Stat.PHYSIQUE, actor.stats.get_base(Stat.PHYSIQUE) + bonus)
	actor.mark_stats_dirty()


## Accepts either the component shape (`{"completed": [...]}`) or the actor
## payload shape (`{realm_id: true}`), which is what `Actor.to_dict` writes so
## core never needs this type.
static func from_dict(data: Dictionary) -> BodyProgress:
	var progress := BodyProgress.new()
	for realm_id in data.get("completed", []):
		progress.completed.append(StringName(realm_id))
	for key in data.keys():
		if key == "completed":
			continue
		if bool(data[key]):
			progress._mark_complete_only(StringName(key))
	return progress


## Append without granting. Loading a save must not re-award bonuses.
func _mark_complete_only(realm_id: StringName) -> void:
	if not completed.has(realm_id):
		completed.append(realm_id)
