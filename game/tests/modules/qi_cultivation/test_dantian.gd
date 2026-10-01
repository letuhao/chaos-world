extends TestCase

## ADR 0014: Dantian qi storage — fill, drain, damage, heal, serialization.


func test_fill_and_drain() -> void:
	var dantian := Dantian.new()
	dantian.capacity = 100.0
	dantian.fill(50.0)
	assert_almost_eq(dantian.current, 50.0, "fill 50")
	dantian.drain(20.0)
	assert_almost_eq(dantian.current, 30.0, "drain 20")


func test_fill_clamps_to_capacity() -> void:
	var dantian := Dantian.new()
	dantian.capacity = 100.0
	dantian.fill(150.0)
	assert_almost_eq(dantian.current, 100.0, "clamped to capacity")


func test_drain_clamps_to_zero() -> void:
	var dantian := Dantian.new()
	dantian.capacity = 100.0
	dantian.fill(50.0)
	dantian.drain(80.0)
	assert_almost_eq(dantian.current, 0.0, "clamped to zero")


func test_is_full() -> void:
	var dantian := Dantian.new()
	dantian.capacity = 100.0
	assert_eq(dantian.is_full(), false, "not full when empty")
	dantian.fill(100.0)
	assert_eq(dantian.is_full(), true, "full when at capacity")


func test_damage_reduces_effective_capacity() -> void:
	var dantian := Dantian.new()
	dantian.capacity = 100.0
	dantian.damage()
	assert_eq(dantian.damaged, true, "damaged flag set")
	assert_almost_eq(dantian.effective_capacity(), 75.0, "effective capacity reduced by 25%")


func test_damage_clamps_current() -> void:
	var dantian := Dantian.new()
	dantian.capacity = 100.0
	dantian.fill(100.0)
	dantian.damage()
	assert_almost_eq(dantian.current, 75.0, "current clamped to effective capacity")


func test_heal_restores_capacity() -> void:
	var dantian := Dantian.new()
	dantian.capacity = 100.0
	dantian.damage()
	dantian.heal()
	assert_eq(dantian.damaged, false, "damaged flag cleared")
	assert_almost_eq(dantian.effective_capacity(), 100.0, "effective capacity restored")


func test_serialization_round_trip() -> void:
	var dantian := Dantian.new()
	dantian.tier = Dantian.MIDDLE
	dantian.capacity = 200.0
	dantian.current = 150.0
	dantian.quality = 0.8
	dantian.damage()
	var restored := Dantian.from_dict(dantian.to_dict())
	assert_eq(restored.tier, Dantian.MIDDLE, "tier round trip")
	assert_almost_eq(restored.capacity, 200.0, "capacity round trip")
	assert_almost_eq(restored.current, 150.0, "current round trip")
	assert_almost_eq(restored.quality, 0.8, "quality round trip")
	assert_eq(restored.damaged, true, "damaged round trip")


func test_attach_dantian_sets_capacity_from_base() -> void:
	var actor := Actor.new(&"test", {QiStats.DANTIAN_CAPACITY: 50.0})
	var dantian := QiCultivationApi.attach_dantian(actor)
	assert_almost_eq(dantian.capacity, 50.0, "capacity from base attribute")


func test_dantian_provider_emits_stats() -> void:
	var actor := Actor.new(&"test", {QiStats.DANTIAN_CAPACITY: 100.0})
	QiCultivationApi.attach_dantian(actor)
	var dantian := QiCultivationApi.dantian(actor)
	dantian.fill(100.0)
	actor.mark_stats_dirty()
	assert_almost_eq(actor.stats.derived(QiStats.DANTIAN_CAPACITY), 100.0, "provider capacity")
	assert_almost_eq(actor.stats.derived(QiStats.DANTIAN_QUALITY), 0.5, "provider quality")
	assert_almost_eq(actor.stats.derived(QiStats.DANTIAN_FULL), 1.0, "provider full")


func test_dantian_provider_damage_reduces_capacity() -> void:
	var actor := Actor.new(&"test", {QiStats.DANTIAN_CAPACITY: 100.0})
	QiCultivationApi.attach_dantian(actor)
	var dantian := QiCultivationApi.dantian(actor)
	dantian.damage()
	actor.mark_stats_dirty()
	assert_almost_eq(actor.stats.derived(QiStats.DANTIAN_CAPACITY), 75.0, "damaged capacity")
