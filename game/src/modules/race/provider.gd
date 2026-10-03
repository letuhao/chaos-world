class_name RaceProvider
extends StatProvider

## Contributes the module's own stat vocabulary from the actor's body plan: what it
## can reach, how long it lives, how many paths it can still cultivate, and how
## strongly it asserts in a contested conception.
##
## **Pure, by construction.** Every value is read from the `race_def` component the
## facade attached — never from the catalog. That matters beyond style: a provider runs
## on every cache miss, and a catalog lookup per stat query would make a stat read
## depend on mutable module state and defeat the caching `ActorStats` already does.
##
## It deliberately does NOT re-derive `percent_modifiers`: the projection already applies
## those to the shared derived-stat pipeline, and contributing them here as well would
## count them twice — which is exactly the bug ADR 0026 exists to prevent.

## Authored affinity values are read as a plain magnitude on an authored scale of
## 0.0 to 10.0, where 10.0 is the strongest body in the tree. The affinity scale is
## otherwise unbounded, so nothing in the repo fixes the number for us; this is the one
## place the choice is made and it is deliberately small — a race that grants a large
## number would swamp whatever an item later adds to the same map. The count below is
## what the module actually contributes, so a badly-scaled authored value can never leak
## into the shared pipeline.
const MAX_AFFINITY_COUNT := 10.0


func contribute(context: StatContext) -> Dictionary:
	var def := context.component(RaceProjection.DEF_COMPONENT) as RaceDef
	if def == null:
		return {}
	return {
		RaceStats.REALM_CEILING: float(def.realm_ceiling),
		RaceStats.LIFESPAN: maxf(0.0, def.lifespan),
		RaceStats.PATH_COUNT: float(PathState.ALL.size() - def.closed_paths.size()),
		RaceStats.AFFINITY_COUNT: minf(float(def.affinities.size()), MAX_AFFINITY_COUNT),
		RaceStats.DOMINANCE: clampf(def.dominance, 0.0, 1.0),
		RaceStats.MANIFESTATION_THRESHOLD: clampf(def.manifestation_threshold, 0.0, 1.0),
	}
