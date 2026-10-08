class_name ActorPools
extends RefCounted

## One actor's resource pools, and the three rules that keep them sized correctly.
##
## ## Why this is not code in `actor.gd`
##
## `core/` is the shared stat/actor foundation every module names, so its public surface is
## load-bearing and the twenty-method cap in `gdlintrc` is a real constraint rather than a
## taste. A pool is a value with three rules on it — create it once, size it from the
## derived capacity, and never let a resize re-enter the stat invalidator — and none of
## those three is about the actor's identity, its statuses or its save. This is the same
## split [StatusRegistry] already makes for statuses: the actor keeps the field and the
## verbs, and the rules live beside it so a fourth kind of pool has one place to obey them.
##
## ## It holds the actor's OWN dictionary BY REFERENCE, never a copy
##
## `Actor.resources` is a public field that modules read and write directly, so this object
## is the same map the actor holds rather than a shadow of it. A copy would go stale the
## instant anything wrote the field directly.
##
## ## It is a DELEGATE, never a subclass
##
## `Actor` has no subclass in this repo — `tests/modules/domain/test_domain_spawner.gd`
## asserts there is none — so every caller keeps reaching `add_resource`,
## `attach_core_resources` and `resource` by the names it has always used. The actor
## forwards here and the edge is ONE-WAY (`Actor` -> `ActorPools`), never the reverse:
## a mutual class reference is what breaks compilation.

## The pools core owns because it owns the stats behind them (ADR 0025), mapped to the
## derived stat that expresses their capacity. Core owns health and stamina; modules add
## their own pools.
const CORE_POOL_STATS := {
	&"health": Stat.MAX_HEALTH,
	&"stamina": Stat.MAX_STAMINA,
}

## Whether a resize is already in progress. Lives here beside the one write that sets it so
## the guard and the thing it guards cannot drift apart.
var _syncing: bool = false

var _actor_ref: WeakRef


func _init(actor: Actor, _resources: Dictionary) -> void:
	_actor_ref = weakref(actor)


## Add `pool` and make a change to it dirty the derived stats. **Guarded**: an unguarded
## connect is a second handler per call, so a pool attached twice would fire the invalidator
## twice for one write and rebuild the same stat cache twice.
func add(resources: Dictionary, pool: ResourcePool, invalidator: StatsInvalidator) -> void:
	resources[pool.id] = pool
	if not pool.changed.is_connected(invalidator.on_changed):
		pool.changed.connect(invalidator.on_changed)
	var actor: Actor = _actor_ref.get_ref()
	if actor != null:
		actor.mark_stats_dirty()


## Create the core health and stamina pools if absent and size them from the current derived
## capacities. A fresh pool starts full; later capacity changes never refill, because
## `set_maximum` only clamps the current value.
func attach_core(resources: Dictionary, stats: ActorStats, invalidator: StatsInvalidator) -> void:
	for pool_id in CORE_POOL_STATS:
		if resources.has(pool_id):
			continue
		add(
			resources,
			ResourcePool.new(pool_id, stats.derived(CORE_POOL_STATS[pool_id])),
			invalidator
		)
	sync_core(resources, stats, invalidator)


## Resize the core pools to the derived capacities, preserving current values.
##
## **Guarded, because a pool's `changed` signal re-enters `mark_stats_dirty`** and the sync
## would otherwise recurse forever. The re-entrancy flag is what makes the resize a single
## pass: without it a stat that reads a core pool cannot be resized at all.
func sync_core(resources: Dictionary, stats: ActorStats, _invalidator: StatsInvalidator) -> void:
	if _syncing:
		return
	_syncing = true
	for pool_id in CORE_POOL_STATS:
		var pool := resources.get(pool_id) as ResourcePool
		if pool == null:
			continue
		var regen_id := Stat.HEALTH_REGEN if pool_id == &"health" else Stat.STAMINA_REGEN
		pool.regen = stats.derived(regen_id)
		pool.set_maximum(stats.derived(CORE_POOL_STATS[pool_id]))
	_syncing = false


## Fill every core pool to its current maximum: the verb a freshly MINTED body uses.
##
## `sync_core` deliberately only CLAMPS `current` when a capacity changes (ADR 0025: an
## item that raises `max_health` never refills), so a body whose capacity rose during
## CONSTRUCTION would otherwise enter play at its old figure: the pool is created at the
## unscaled `MAX_HEALTH` before any path exists, every realm enrolment then raises the
## capacity, and `current` stays where it was born. The actor-vs-actor census measured
## exactly that — 250 / 381425 at R30 — and the sixty-second anchor collapsed to a single
## blow (DEF-0384).
##
## This is for a MINT and nothing else. NOT a restore (whose `current` is the save), NOT
## an equip (ADR 0025), NOT a breakthrough (a lived body keeps its wounds).
func refill_core(resources: Dictionary) -> void:
	for pool_id in CORE_POOL_STATS:
		var pool := resources.get(pool_id) as ResourcePool
		if pool != null:
			pool.change(pool.maximum - pool.current)
