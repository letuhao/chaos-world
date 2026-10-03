class_name BodyDeviationJam
extends RefCounted

## WHERE a failed breakthrough puts its blockage (ADR 0015/0023).
##
## Split out of `BodyAdvancement` because "where the wound lands" and "run the
## attempt lifecycle" are two reasons to change: the attempt record, the chance
## roll and the tier gates moved several times without any of this moving.
##
## The one rule this file exists to state: **a deviation may only jam a huyệt the
## actor can clear.** `BodyTraining.recover` repairs through a channel, so a jam
## on a meridian the actor has not unlocked has no channel to resolve and no
## elixir that clears it (`strengthen` refuses it for the same reason),
## `cultivate` skips a blocked point, and `BodyBreakthroughCondition._acupoints_ready`
## still grades its quality. That is a permanent deadlock, and it was reachable:
## the fallback used to pick from EVERY open point, and the huyệt data grants all
## 36 minor points at ladder index 0 across 12 primary meridians of which 8
## unlock only at index 3 and 6 — two thirds of the R1 pool was unplayable.


## Jam the huyệt bound to `meridian_id`, so both halves of the wound sit on the
## same channel and the damage has a location the player can be shown. Falls back
## to any eligible huyệt when the torn meridian has none open.
static func on_channel(
	actor: Actor, points: AcupointSet, meridian_id: StringName, rng: RandomNumberGenerator
) -> void:
	if meridian_id != &"" and actor.meridians.get_meridian(meridian_id) != null:
		var linked: Array[Acupoint] = []
		for point in points.points:
			if not point.blocked and AcupointDefaults.meridian_of(point.id) == meridian_id:
				linked.append(point)
		if not linked.is_empty():
			linked[_index(rng, linked.size())].block()
			return
	random_open(actor, points, rng)


## Jam any eligible open huyệt. Eligible means its meridian is ON the actor's
## network; the pool is never empty while the actor holds any huyệt, because the
## minor tier always covers the four index-0 primary meridians.
static func random_open(actor: Actor, points: AcupointSet, rng: RandomNumberGenerator) -> void:
	var open: Array[Acupoint] = []
	for point in points.points:
		if not point.blocked and actor.meridians.get_meridian(meridian_of(point)) != null:
			open.append(point)
	if open.is_empty():
		return
	open[_index(rng, open.size())].block()


static func meridian_of(point: Acupoint) -> StringName:
	return AcupointDefaults.meridian_of(point.id)


static func _index(rng: RandomNumberGenerator, size: int) -> int:
	return randi() % size if rng == null else rng.randi_range(0, size - 1)
