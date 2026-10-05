class_name TechniqueEffects
extends RefCounted

## What a passive technique contributes while it is equipped, and how that
## contribution reaches the actor exactly once (ADR 0054).
##
## A passive technique is a thin new consumer of the existing modifier pipeline, not
## a fork of it: `passive_options` is `ItemDef.fixed_modifiers` verbatim, so
## `ItemEffects.stat_modifiers` / `resource_modifiers` turn an authored technique
## row into `StatModifier`s with no new code path, and the modifier's own rules —
## base allocation untouched, derived recomposition, exact-source removal — all
## transfer for free.
##
## Never a `StatProvider`. A provider is recomputed on every read, has no
## per-provider removal, and a provider owning a stat id OVERRIDES the modifier
## pipeline's value for that id — so a provider-backed technique would make the
## whole actor's stat ownership depend on which of several techniques is equipped.
##
## The source tag is `technique:<id>`: a namespaced prefix, never a bare id. This is
## the one genuine hazard in the design, because `remove_modifiers_from` is a linear
## exact-string filter with no prefix matching, so two owners sharing a tag
## annihilate each other silently. A bare technique id could also collide with
## `&"realm"` or an equipment instance id.

const SOURCE_PREFIX := "technique:"


## The modifier source that owns every contribution from one technique.
static func source_for(technique_id: StringName) -> StringName:
	return StringName("%s%s" % [TechniqueEffects.SOURCE_PREFIX, technique_id])


## Replace one technique's whole passive contribution: remove its source in full,
## then add it again. Rebuilding any number of times therefore cannot accumulate
## drift — this is the proven `SocketEffects.apply` shape, copied deliberately.
static func apply(actor: Actor, technique_id: StringName, effects: Array[Dictionary]) -> void:
	if actor == null or technique_id == &"":
		return
	var source := source_for(technique_id)
	actor.stats.remove_modifiers_from(source)
	for modifier in ItemEffects.stat_modifiers(effects, source):
		actor.stats.add_modifier(modifier)
	for modifier in ItemEffects.resource_modifiers(effects, source):
		actor.stats.add_modifier(modifier)
	actor.mark_stats_dirty()


## Remove one technique's contribution entirely.
static func clear(actor: Actor, technique_id: StringName) -> void:
	apply(actor, technique_id, [])


## The stat and resource modifiers `effects` produce under `source`, without
## applying them. Lets a caller count what a contribution will be, exactly as
## `SocketEffects` exposes `contribution` for inspection.
static func modifiers_of(effects: Array[Dictionary], source: StringName) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	out.append_array(ItemEffects.stat_modifiers(effects, source))
	out.append_array(ItemEffects.resource_modifiers(effects, source))
	return out


## How many modifiers a technique's contribution is worth right now. Zero for
## anything that is not equipped and not suspended, which is the observable form of
## ADR 0054's suspension rule.
##
## Read by asking the CATALOG what the contribution is worth, not by walking the
## actor's modifier stack: `ActorStats` exposes no per-source accessor, and widening
## `core/` for a test-only reading would need its own ADR (AGENTS.md OCP step 4).
## The two answers agree whenever the stack is in sync — `apply` is called with
## exactly this `modifiers_of` output — and this one cannot throw on a method that
## does not exist.
static func applied_count(actor: Actor, technique_id: StringName) -> int:
	if actor == null or technique_id == &"":
		return 0
	# Not equipped, or equipped but suspended: contributes nothing either way, and
	# that is exactly what ADR 0054 says a suspension means.
	var slots := TechniquesApi.slots(actor)
	if not slots.is_equipped(technique_id):
		return 0
	var upkeep := actor.component(TechniquesApi.UPKEEP_COMPONENT) as TechniqueUpkeep
	if upkeep != null and upkeep.is_suspended(technique_id):
		return 0
	var def := TechniqueCatalog.instance().definition(technique_id)
	if def == null:
		return 0
	var entry := TechniquesApi.codex(actor).entry(technique_id)
	var effects := def.effects() if entry == null else entry.effects_for(def)
	return modifiers_of(effects, source_for(technique_id)).size()
