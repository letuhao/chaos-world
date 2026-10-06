class_name TechniqueGate
extends RefCounted

## What decides whether a technique may be LEARNED (ADR 0059).
##
## This gate reads `PathState` and `RealmDefaults` directly, both of which live in
## `contracts/` and `core/`, so it breaks no boundary. It deliberately does NOT
## grow a cultivation facade: ADR 0059 records that the dependency runs one way —
## this module learns about the paths, and the path modules learn nothing about
## techniques.
##
## Three readings, one per kind of technique:
##
##   path-exclusive — the technique's own path must be at the floor. A qi
##                    technique gated on "best path" would be learnable by an
##                    actor at R30 body and R3 qi, which is precisely the build
##                    the path-typed slots exist to make a mistake.
##   DUAL           — BOTH of its paths at the floor. Not an either/or: an
##                    either/or reading lets an actor hold a qi+body technique
##                    while at R30 qi and R1 body, which makes the other path
##                    free and deletes the only cost a dual build pays (DEF-0099).
##   SHARED         — `min_realm_index`, the best path, and never a path key.


## The actor's ordinal on one path, from `PathState.rank_id` read off the shared
## ladder. 0 when the actor is not on that path at all, so an unstarted path can
## never satisfy a floor.
static func path_ordinal(actor: Actor, path_id: StringName) -> int:
	if actor == null or path_id == &"":
		return 0
	# `Actor.path` returns a Variant, so the state is bound through a typed
	# parameter. Inferred straight into `:=`, `state.rank_id` below has no set
	# type and the whole class fails to resolve.
	var state: PathState = actor.path(path_id)
	if state == null or state.rank_id == &"":
		return 0
	return maxi(0, RealmDefaults.ladder().index_of(state.rank_id))


## The highest ordinal the actor has reached on any path — the "any path" gate
## `ItemRequirement.min_realm_index` uses, and the one a SHARED technique uses.
static func best_ordinal(actor: Actor) -> int:
	var best := 0
	for path_id in PathState.ALL:
		best = maxi(best, path_ordinal(actor, path_id))
	return best


## Every unmet requirement, each naming the gate that refused so a panel can say
## which path is short without re-deriving anything. Empty means learnable.
static func unmet(actor: Actor, def: TechniqueDef) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []
	if actor == null or def == null:
		return problems
	# Tier floor from the grade. Read from the best path, like any other realm gate.
	var tier := TechniquePolicy.tier_of(actor.realm())
	if tier < def.required_tier():
		(
			problems
			. append(
				{
					"kind": &"tier",
					"id": &"realm",
					"required": def.required_tier(),
					"actual": tier,
					"label": "Requires realm tier %d" % def.required_tier(),
				}
			)
		)
	# A SHARED technique is gated on the best path and never on a path key.
	var shared_floor := 0 if def.requirement == null else int(def.requirement.min_realm_index)
	if shared_floor > 0 and best_ordinal(actor) < shared_floor:
		(
			problems
			. append(
				{
					"kind": &"realm",
					"id": &"realm",
					"required": shared_floor,
					"actual": best_ordinal(actor),
					"label": "Requires realm %d" % shared_floor,
				}
			)
		)
	# Path floors. Every named path must individually reach its own.
	for path_id in def.min_path_realm.keys():
		var required := int(def.min_path_realm[path_id])
		if required <= 0:
			continue
		var actual := path_ordinal(actor, StringName(path_id))
		if actual >= required:
			continue
		(
			problems
			. append(
				{
					"kind": &"path_realm",
					"id": StringName(path_id),
					"required": required,
					"actual": actual,
					"label": "Requires %s realm %d (you are at %d)" % [path_id, required, actual],
				}
			)
		)
	# Meridian channels and huyệt. Read from `Actor.meridians`, which is core state
	# rather than a module component (ADR 0057), so this needs no facade either.
	if not def.required_meridians.is_empty():
		for meridian_id in def.required_meridians:
			var channel := actor.meridians.get_meridian(meridian_id)
			if channel != null and channel.meets(def.required_channel_state):
				continue
			(
				problems
				. append(
					{
						"kind": &"meridian",
						"id": meridian_id,
						"required": String(def.required_channel_state),
						"actual": "" if channel == null else String(channel.state),
						"label":
						"Requires channel %s at %s" % [meridian_id, def.required_channel_state],
					}
				)
			)
	if not def.required_acupoints.is_empty():
		# Read through the actor's own raw module data rather than the body module's
		# acupoint types: `Actor` already serializes them as plain dictionaries, so
		# this crosses no boundary and names no sibling class.
		var points: Dictionary = actor.get_module_data(&"acupoints")
		for point_id in def.required_acupoints:
			# `Dictionary.get` returns a Variant, so the tier is read into a typed
			# local before being narrowed. Inferred straight into `StringName(...)`
			# it is an untyped inference, which this project treats as an error.
			var raw_tier: Variant = (points.get(String(point_id), {}) as Dictionary).get("tier", "")
			var reached := StringName(raw_tier)
			if _tier_rank(reached) >= _tier_rank(def.required_acupoint_tier):
				continue
			(
				problems
				. append(
					{
						"kind": &"acupoint",
						"id": point_id,
						"required": String(def.required_acupoint_tier),
						"actual": reached,
						"label":
						"Requires huyệt %s at tier %s" % [point_id, def.required_acupoint_tier],
					}
				)
			)
	# Attribute and base-resource gates, reused unchanged from ItemRequirement.
	# They read base allocation only, so a technique cannot fund its own gate.
	if def.requirement != null:
		problems.append_array(def.requirement.unmet(actor))
	return problems


## Whether `def` is learnable by `actor` right now. A path-exclusive technique
## defaults its floor to its own path's ordinal 0, which is "no floor" — the grade
## is what decides the realm then, exactly as for an item.
static func may_learn(actor: Actor, def: TechniqueDef) -> bool:
	return unmet(actor, def).is_empty()


## The price of learning `def` at the actor's own realm ordinal: the ladder at the
## ordinal where the actor actually stands, times the grade band.
static func learn_price_for(actor: Actor, def: TechniqueDef) -> float:
	var index := best_ordinal(actor)
	return TechniqueScales.learn_price(def.grade, index)


## Acupoint tiers are ordered names, not numbers, so a required tier and an actual
## tier compare as a rank. The tier names are data, so they are spelled once here
## rather than borrowed from a sibling module's constants — reading the body
## module's `Acupoint` class here would be a cross-module edge for three words. An
## unknown rank is 0, which any named floor beats, so an unreadable tier is never
## "good enough".
static func _tier_rank(tier: StringName) -> int:
	match tier:
		&"minor":
			return 1
		&"major":
			return 2
		&"celestial":
			return 3
		_:
			return 0
