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
##
## **`LIFESPAN` is the one stat here that is NOT a plain read of `def`.** ADR 0169
## makes it the EFFECTIVE lifespan — the authored baseline scaled by the realm-tier
## multiplier from `core/realm_lifespan_table.tres` — and the whole arithmetic lives
## in `RealmLifespan.effective_lifespan_for`. This module contributes the CALL and
## nothing else, so the one authored baseline and the one tier row meet in exactly
## one place in the repository; a second `def.lifespan * 10.0` typed here would be
## numerically identical on day one and free to drift on day two, which is the
## ADR 0116 mutation, and `tests/core/test_realm_lifespan_table.gd` reads SOURCE
## to catch it. The raw baseline stays readable off `RaceDef` and is deliberately
## not a second stat.

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
		RaceStats.LIFESPAN: RealmDefaults.LIFESPAN.effective_lifespan_for(_actor_for(context)),
		RaceStats.PATH_COUNT: float(PathState.ALL.size() - def.closed_paths.size()),
		RaceStats.AFFINITY_COUNT: minf(float(def.affinities.size()), MAX_AFFINITY_COUNT),
		RaceStats.DOMINANCE: clampf(def.dominance, 0.0, 1.0),
		RaceStats.MANIFESTATION_THRESHOLD: clampf(def.manifestation_threshold, 0.0, 1.0),
	}


## The actor `RealmLifespan.effective_lifespan_for` can read.
##
## **A one-collection bridge, and the reason it is spelled rather than reimplemented.**
## `StatContext` is a read-only VIEW and deliberately not a back-reference to its
## actor (`contracts/stat_context.gd:1-5`), so the provider cannot hand core the
## actor it is contributing for. What core's read actually needs is `paths` — that
## is all `RealmScaling.highest_realm` walks — plus the `race_def` component this
## context already carries, so a probe carrying `paths` and `components` is
## sufficient and nothing else is duplicated.
##
## Rebuilding the tier lookup HERE instead would be a second ladder read inside a
## provider, which is the exact shape `tests/core/test_realm_rate.gd:304` refuses:
## the provider's only legitimate per-realm factor is the one shared primitive. So
## the read is delegated whole, and the tier can only be resolved one way.
func _actor_for(context: StatContext) -> Actor:
	var probe := Actor.new(&"race_lifespan_probe")
	probe.paths = context.paths
	probe.components = context.components
	return probe
