extends TestCase

## ADR 0014: Dantian qi storage — fill, drain, damage, heal, serialization.
## Dantian owns structural state; current/capacity live in the qi ResourcePool.


func _actor() -> Actor:
	var actor := Actor.new(&"test", {QiStats.DANTIAN_CAPACITY: 100.0})
	QiCultivationApi.attach(actor)
	# The shared qi pool starts full; empty it so fill/drain start from zero.
	actor.resource(QiStats.QI).change(-actor.resource(QiStats.QI).current)
	return actor


func test_fill_and_drain() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.set_structural_capacity(100.0)
	dantian.fill(actor, 50.0)
	assert_almost_eq(dantian.current(actor), 50.0, "fill 50")
	dantian.drain(actor, 20.0)
	assert_almost_eq(dantian.current(actor), 30.0, "drain 20")


func test_fill_clamps_to_capacity() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.set_structural_capacity(100.0)
	dantian.fill(actor, 150.0)
	assert_almost_eq(dantian.current(actor), 100.0, "clamped to capacity")


func test_drain_clamps_to_zero() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.set_structural_capacity(100.0)
	dantian.fill(actor, 50.0)
	dantian.drain(actor, 80.0)
	assert_almost_eq(dantian.current(actor), 0.0, "clamped to zero")


func test_is_full() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.set_structural_capacity(100.0)
	assert_eq(dantian.is_full(actor), false, "not full when empty")
	dantian.fill(actor, 100.0)
	assert_eq(dantian.is_full(actor), true, "full when at capacity")


func test_damage_reduces_effective_capacity() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.set_structural_capacity(100.0)
	dantian.damage()
	assert_eq(dantian.injured, true, "injured flag set")
	assert_almost_eq(dantian.effective_capacity(), 75.0, "effective capacity reduced by 25%")


func test_damage_clamps_current() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.set_structural_capacity(100.0)
	dantian.fill(actor, 100.0)
	dantian.damage(actor)
	assert_almost_eq(dantian.current(actor), 75.0, "current clamped to effective capacity")


func test_heal_restores_capacity() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.set_structural_capacity(100.0)
	dantian.damage()
	dantian.heal()
	assert_eq(dantian.injured, false, "injured flag cleared")
	assert_almost_eq(dantian.effective_capacity(), 100.0, "effective capacity restored")


func test_serialization_round_trip() -> void:
	var dantian := Dantian.new()
	dantian.tier = Dantian.MIDDLE
	dantian.set_structural_capacity(200.0)
	dantian.set_quality(0.8)
	dantian.damage()
	var restored := Dantian.from_dict(dantian.to_dict())
	assert_eq(restored.tier, Dantian.MIDDLE, "tier round trip")
	assert_almost_eq(restored.structural_capacity, 200.0, "capacity round trip")
	assert_almost_eq(restored.quality, 0.8, "quality round trip")
	assert_eq(restored.injured, true, "injured round trip")


## The dantian is attached by the one production call, not by a second one a
## composition root has to remember: `QiCultivationApi.attach` creates it (ADR
## 0095). Nothing in `app/` ever called the separate `attach_dantian`, so every qi
## actor the game built had none and the whole path refused every action.
func test_attaching_the_path_attaches_the_dantian_from_the_base_attribute() -> void:
	var actor := Actor.new(&"test", {QiStats.DANTIAN_CAPACITY: 50.0})
	var dantian := QiAccess.attach_dantian(actor)
	assert_almost_eq(dantian.structural_capacity, 50.0, "capacity from base attribute")


func test_attach_dantian_is_idempotent() -> void:
	var actor := Actor.new(&"test", {QiStats.DANTIAN_CAPACITY: 50.0})
	var dantian1 := QiAccess.attach_dantian(actor)
	var dantian2 := QiAccess.attach_dantian(actor)
	assert_eq(dantian1 == dantian2, true, "same instance returned")


## And through the facade itself, so the guarantee is the production one.
func test_the_facade_attach_leaves_the_actor_ready() -> void:
	var actor := Actor.new(&"test", {QiStats.DANTIAN_CAPACITY: 50.0})
	QiCultivationApi.attach(actor)
	var dantian := QiAccess.dantian(actor)
	assert_ne(dantian, null, "attach created the dantian")
	assert_almost_eq(dantian.structural_capacity, 50.0, "from the base attribute")
	assert_ne(actor.resource(QiCultivationApi.QI), null, "and the reservoir")


func test_dantian_provider_emits_stats() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.fill(actor, 100.0)
	actor.mark_stats_dirty()
	assert_almost_eq(actor.stats.derived(QiStats.DANTIAN_CAPACITY), 100.0, "provider capacity")
	assert_almost_eq(actor.stats.derived(QiStats.DANTIAN_QUALITY), 0.5, "provider quality")
	assert_almost_eq(actor.stats.derived(QiStats.DANTIAN_FULL), 1.0, "provider full")


func test_dantian_provider_damage_reduces_capacity() -> void:
	var actor := _actor()
	var dantian := QiAccess.dantian(actor)
	dantian.damage()
	actor.mark_stats_dirty()
	assert_almost_eq(actor.stats.derived(QiStats.DANTIAN_CAPACITY), 75.0, "damaged capacity")
