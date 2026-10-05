class_name NpcStageProjection
extends RefCounted

## Applies an npc's current stage to their actor (ADR 0077).
##
## **Strip then apply, always in that order.** An actor moving from stage 1 to stage 2 must
## lose stage 1's magnitudes before stage 2's land, or the two stack and a late-game boss
## becomes a late-game boss plus everything it used to be.
##
## Magnitudes land under the `npc_stage:` source, exactly once, and are never derived from
## the realm power curve — a stage is an authored entity scale like a realm seed's
## `integrity_maximum`, and scaling it from a shared curve would be the double-scaling
## trap ADR 0050 warns about.

const SOURCE_PREFIX := "npc_stage:"


static func source_for(stage_id: StringName) -> StringName:
	return StringName(SOURCE_PREFIX + String(stage_id))


## Remove every stage-granted modifier and trait mirror this module owns. Leaves an
## actor's own build, and everything another module granted, untouched.
##
## **Removes by prefix, one modifier at a time.** `ActorStats.remove_modifiers_from`
## takes an exact `StringName`, and every stage has its own source (`npc_stage:<id>`), so
## passing the bare prefix removes nothing and stage magnitudes stack into a runaway
## product. Core's verb is exact-match by design — a module owning a namespaced family
## has to walk its own list rather than ask core to grow a prefix match.
static func strip(actor: Actor) -> void:
	if actor == null:
		return
	var kept: Array[StatModifier] = []
	for modifier in actor.stats._modifiers:
		if not _is_own_source(modifier.source):
			kept.append(modifier)
	actor.stats._modifiers = kept
	actor.stats.mark_dirty()
	for trait_id in _mirrored_traits(actor):
		actor.traits.remove(trait_id)


## Apply `stage_def`'s magnitudes and trait mirrors. A null def strips and stops, so
## calling this with no stage is the safe way to clear an actor.
static func apply(actor: Actor, stage_def: NpcStageDef) -> void:
	strip(actor)
	if actor == null or stage_def == null:
		return
	var source := source_for(stage_def.stage_id)
	for stat_id in stage_def.stat_multipliers.keys():
		actor.stats.add_modifier(
			StatModifier.new(
				stat_id, Stat.Op.MULT, float(stage_def.stat_multipliers[stat_id]), source
			)
		)
	actor.traits.add(stage_def.tag_id())
	for tag in stage_def.tags:
		actor.traits.add(StringName("%s:%s" % [String(stage_def.stage_id), String(tag)]))


## The sum of this module's own contributions to `stat_id`, for a test that asserts a
## stage applied exactly once rather than twice.
static func contribution(actor: Actor, stat_id: StringName) -> float:
	if actor == null:
		return 0.0
	var total := 1.0
	for modifier in actor.stats._modifiers:
		if _is_own_source(modifier.source):
			if modifier.stat == stat_id and modifier.op == Stat.Op.MULT:
				total *= float(modifier.value)
	return total


## Whether a modifier source belongs to this module. One predicate so `strip` and
## `contribution` can never disagree about which modifiers are ours.
static func _is_own_source(source: StringName) -> bool:
	return source != null and String(source).begins_with(SOURCE_PREFIX)


static func _mirrored_traits(actor: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	for trait_id in actor.traits.values():
		if String(trait_id).begins_with("npc_stage:"):
			out.append(trait_id)
	return out
