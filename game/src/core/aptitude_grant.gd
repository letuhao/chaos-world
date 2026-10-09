class_name AptitudeGrant
extends Resource

## The aptitude GRANT table (ADR 0883): what an actor has BUILT resolves into aptitude
## points. One row per major — `{path, posture, per_realm}` — where a started path's
## REALMS CROSSED (`ladder_index`, not "index + 1": the first realm is where a path
## starts, not something it built) times `per_realm` is split evenly across the posture's
## four aptitudes.
##
## ## The three majors ARE the three postures
##
## body -> force, qi -> finesse, mind -> bastion, so a build's posture is a READ over what
## it advanced (Keepverse's `DominantPosture`, ties -> none), never a stored field and
## never a pick.
##
## ## Nothing is user-picked, and that is the verb
##
## [method apply] REPLACES the actor's aptitude store from the build. It is called at the
## two stages a build changes identity: BREAKTHROUGH (`Breakthrough.try_advance`, the one
## success site all three majors reach) and technique learn (the techniques module, which
## adds `technique_points` into the dominant posture). There is no spend verb anywhere.

const TABLE_PATH := "res://src/core/aptitude_grants.tres"

## The shipped table's own cache. A `static var` belongs with `const`s and before
## `@export`s (gdlint's `class-definitions-order`), so it is declared here rather than
## beside [method shipped].
static var _shipped: AptitudeGrant = null


## One row per major: `{path: StringName, posture: StringName, per_realm: float}`.
@export var rows: Array[Dictionary] = []
## What ONE learned technique adds, into the DOMINANT posture's four aptitudes (split
## evenly). `0.0` means techniques grant nothing.
@export var technique_points: float = 0.0


## The shipped table, loaded once. `null` only when the resource cannot load, which the
## table's own test refuses — a shipped game always has one.
static func shipped() -> AptitudeGrant:
	if _shipped == null:
		_shipped = load(TABLE_PATH) as AptitudeGrant
	return _shipped


## Points per aptitude from the MAJORS alone: for every row whose path the actor has
## started, `realms_crossed * per_realm` split across the row's posture — and a path that
## has not crossed a realm yet grants NOTHING, because the first realm is where a path
## starts rather than something a build did. An unstarted path, an unknown path, a rank
## off the ladder and a malformed row each grant nothing here too — none of them is an
## error, because all of them are states a build can legitimately be in.
func resolve(actor: Actor) -> Dictionary:
	var points := {}
	if actor == null:
		return points
	var ladder := RealmDefaults.ladder()
	for row in rows:
		var path_id := StringName(row.get("path", &""))
		var posture := StringName(row.get("posture", &""))
		var per_realm := float(row.get("per_realm", 0.0))
		if not Aptitude.POSTURES.has(posture):
			continue
		if not is_finite(per_realm) or per_realm <= 0.0:
			continue
		var state := actor.path(path_id)
		if state == null or not state.is_started():
			continue
		var index := ladder.index_of(state.rank_id)
		if index <= 0:
			continue
		_split_into(points, posture, float(index) * per_realm)
	return points


## The posture a points dictionary LEADS with, or `&""` when none leads — Keepverse's
## `DominantPosture` rule: ties resolve to none rather than to an arbitrary winner,
## because inventing a winner out of a tie would assert a build identity nobody chose.
static func dominant_posture(points: Dictionary) -> StringName:
	var totals := {}
	for id in points.keys():
		var posture := Aptitude.posture_of(StringName(id))
		if posture == &"":
			continue
		totals[posture] = float(totals.get(posture, 0.0)) + maxf(0.0, float(points[id]))
	var best := 0.0
	for posture in totals.keys():
		best = maxf(best, float(totals[posture]))
	var leaders: Array[StringName] = []
	for posture in Aptitude.POSTURES:
		if best > 0.0 and is_equal_approx(float(totals.get(posture, 0.0)), best):
			leaders.append(posture)
	return leaders[0] if leaders.size() == 1 else &""


## Resolve the build and REPLACE the actor's aptitude store with it.
func apply(actor: Actor) -> void:
	if actor == null or actor.stats == null:
		return
	actor.stats.set_aptitudes(resolve(actor))


static func _split_into(points: Dictionary, posture: StringName, total: float) -> void:
	var each := total / float(Aptitude.PER_POSTURE)
	for id in Aptitude.in_posture(posture):
		points[id] = float(points.get(id, 0.0)) + each
