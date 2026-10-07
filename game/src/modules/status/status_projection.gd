class_name StatusProjection
extends RefCounted

## ADR 0902 (P8, BL-0924): the generic projection host — a TRACK (a ladder of stages)
## drives exactly one live projection on a host, and `sync` makes the live set match a
## stage. Ported from Keepverse's `StatusProjectionHost`, adapted to our grant handle.
##
## ## The three rules that make it a host rather than an apply wrapper
##
## 1. **One apply per transition.** The live set is read BEFORE any write, so N calls at
##    an unchanged stage produce exactly one apply. The idempotence is the PRE-READ, never
##    the stacking mode: a re-apply under refresh would still be a fresh instance and a
##    fresh `status_applied`, so "one apply" would hold only in the final state.
## 2. **The grant scopes the track.** Every instance the host writes carries
##    `grant_id_for(actor, track)` — host-scoped and track-named — so withdrawing one
##    track can never reach another track's instance, and `clear_grant` is the withdraw.
## 3. **NO CLOCK.** Nothing here reads time: a projection lives until the next `sync`
##    withdraws it (`duration = -1`, permanent), so it never decays behind the scalar
##    that drives it.
##
## ## A rung is a SET of ids
##
## Keepverse's rung is one id; ours is an `Array[StringName]` because a stage of the age
## track is a PAIR (wear + clarity, AGENTS.md's yin-yang rule). `match` decides how the
## live set is found: `&"prefix"` (ids beginning `<track>_`) or `&"exact"` (the ids of
## rung 0, the boolean shape's single stage).

const MATCH_PREFIX := &"prefix"
const MATCH_EXACT := &"exact"


## The grant id this host writes for `actor`'s `track_id`: host-scoped and track-named,
## exactly the property the Keepverse host asserts at every call.
static func grant_id_for(actor: Actor, track_id: StringName) -> StringName:
	return StringName("projection:%s:%s" % [String(track_id), String(actor.id)])


## The authored rungs' problems, or `[]`. A rung with no ids has nothing to project; an
## id repeated ACROSS rungs makes every stage between the copies unreachable, because
## entering the second copy would read as already-projected and write nothing.
static func rung_problems(rungs: Array) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for index in rungs.size():
		var rung: Variant = rungs[index]
		if not (rung is Array) or (rung as Array).is_empty():
			out.append("rung %d projects no ids" % index)
			continue
		for entry in rung as Array:
			var id := StringName(entry)
			if id == &"":
				out.append("rung %d carries an empty id" % index)
				continue
			if seen.has(id):
				out.append(
					(
						"id '%s' appears on two rungs: a middle stage would be unobservable"
						% String(id)
					)
				)
				continue
			seen[id] = true
	return out


## Make the live projection of `track_id` on `actor` match `stage`. `stage == -1` is the
## withdrawn state (a ladder that climbed back to nothing). Returns primitives only:
## `{change, stage, ids, grant, reason}` with `change` in `applied|withdrew|no_change`.
static func sync(
	actor: Actor, track_id: StringName, stage: int, rungs: Array, match: StringName = MATCH_PREFIX
) -> Dictionary:
	if actor == null:
		return _answer(&"no_change", stage, [], &"", &"no_actor")
	var problems := rung_problems(rungs)
	if not problems.is_empty():
		return _answer(&"no_change", stage, [], &"", StringName(problems[0]))
	if stage < -1 or stage >= rungs.size():
		return _answer(&"no_change", stage, [], &"", &"stage_out_of_range")
	var grant := grant_id_for(actor, track_id)
	var live := _live_ids(actor, track_id, match, rungs)
	var wanted: Array[StringName] = []
	if stage >= 0:
		for entry in rungs[stage] as Array:
			wanted.append(StringName(entry))
	# THE idempotence pre-read: an unchanged answer is decided from live state BEFORE any
	# write, so N syncs at an unchanged stage produce exactly one apply.
	if _same_set(live, wanted):
		return _answer(&"no_change", stage, wanted, grant, &"")
	if not live.is_empty():
		# An explicit withdraw: a projection never expires on its own, so the previous
		# stage's instances go only here (or at `stage == -1`).
		StatusApi.clear_grant(actor, grant)
	if wanted.is_empty():
		return _answer(&"withdrew" if not live.is_empty() else &"no_change", stage, [], grant, &"")
	var applied: Array[StringName] = []
	for id in wanted:
		if _apply_projection(actor, id, grant):
			applied.append(id)
	return _answer(&"applied", stage, applied, grant, &"")


## One projection apply: attacker-less, inert magnitude (`1.0`), permanent (`-1.0`), the
## track's grant. The door follows the DEF's scope, exactly as every other caller picks:
## a cultivation def through `apply_cultivation`, a combat def through `apply`.
static func _apply_projection(actor: Actor, id: StringName, grant: StringName) -> bool:
	var def := StatusCatalog.instance().any_definition(id)
	if def == null:
		return false
	if def.is_combat_scope():
		return bool(StatusApi.apply(actor, id, 1.0, -1.0, grant).get("ok", false))
	return bool(StatusApi.apply_cultivation(actor, id, 1.0, -1.0, grant).get("ok", false))


## The live ids of this track on `actor`, by the chosen match. Bounded `for` over the
## actor's own list. `exact` matches rung 0's ids — the boolean shape's single stage.
static func _live_ids(
	actor: Actor, track_id: StringName, match: StringName, rungs: Array
) -> Array[StringName]:
	var out: Array[StringName] = []
	var prefix := String(track_id) + "_"
	var exact_ids: Array = [] if rungs.is_empty() else (rungs[0] as Array)
	for status in actor.statuses:
		var id := String(status.id)
		if match == MATCH_EXACT:
			if exact_ids.has(status.id):
				out.append(status.id)
		elif id.begins_with(prefix):
			out.append(status.id)
	return out


## Whether two id sets hold the same members, order-insensitive.
static func _same_set(a: Array[StringName], b: Array[StringName]) -> bool:
	if a.size() != b.size():
		return false
	for id in a:
		if not b.has(id):
			return false
	return true


static func _answer(
	change: StringName, stage: int, ids: Array[StringName], grant: StringName, reason: StringName
) -> Dictionary:
	var names: Array[String] = []
	for id in ids:
		names.append(String(id))
	return {
		"change": String(change),
		"stage": stage,
		"ids": names,
		"grant": String(grant),
		"reason": String(reason),
	}
