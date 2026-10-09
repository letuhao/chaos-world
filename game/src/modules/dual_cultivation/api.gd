class_name DualCultivationApi
extends RefCounted

## Public facade for the `dual_cultivation` module.
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.

# Public ids other modules may depend on.
const CHARM := DualCultivationStats.CHARM
const FERTILITY := DualCultivationStats.FERTILITY
const POTENCY := DualCultivationStats.POTENCY


static func attach(actor: Actor) -> void:
	_ensure_resources(actor)
	actor.stats.add_provider(DualCultivationProvider.new())
	_sync_essence(actor)


static func succubus_path() -> CultivationPathDef:
	return SuccubusPath.path_def()


## The dual-cultivation aid (BL-0951 / ADR 0939, S13): exchange cultivation with a partner —
## the actor's scarred realm mends by exactly what the partner's perfection there loses.
## `DualCultivationAid` owns the equal-transfer rule (the one transfer amount, bounded on
## both sides), the essence price, and the time cost; this names it.
static func dual_aid(actor: Actor, partner: Actor, realm_id: StringName = &"") -> Dictionary:
	return DualCultivationAid.aid(actor, partner, realm_id)


static func _ensure_resources(actor: Actor) -> void:
	_add_pool(actor, DualCultivationStats.ESSENCE, true)
	_add_pool(actor, DualCultivationStats.DESIRE, false)
	_add_pool(actor, DualCultivationStats.CORRUPTION, false)
	_add_pool(actor, DualCultivationStats.YIN, false)
	_add_pool(actor, DualCultivationStats.YANG, false)


static func _add_pool(actor: Actor, id: StringName, full: bool) -> void:
	if actor.resource(id) != null:
		return
	var pool := ResourcePool.new(id, 100.0)
	if not full:
		pool.current = 0.0
	actor.add_resource(pool)


static func _sync_essence(actor: Actor) -> void:
	var essence := actor.resource(DualCultivationStats.ESSENCE)
	if essence != null:
		essence.set_maximum(actor.stats.derived(DualCultivationStats.ESSENCE_CAPACITY))
		essence.current = essence.maximum
		actor.mark_stats_dirty()
