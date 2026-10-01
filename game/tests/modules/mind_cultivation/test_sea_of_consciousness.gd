extends TestCase

## ADR 0016: Sea of Consciousness — fill, drain, turbulence, calm, serialization.


func test_fill_and_drain() -> void:
	var sea := SeaOfConsciousness.new()
	sea.capacity = 100.0
	sea.fill(50.0)
	assert_almost_eq(sea.current, 50.0, "fill 50")
	sea.drain(20.0)
	assert_almost_eq(sea.current, 30.0, "drain 20")


func test_fill_clamps_to_capacity() -> void:
	var sea := SeaOfConsciousness.new()
	sea.capacity = 100.0
	sea.fill(150.0)
	assert_almost_eq(sea.current, 100.0, "clamped to capacity")


func test_drain_clamps_to_zero() -> void:
	var sea := SeaOfConsciousness.new()
	sea.capacity = 100.0
	sea.fill(50.0)
	sea.drain(80.0)
	assert_almost_eq(sea.current, 0.0, "clamped to zero")


func test_is_full() -> void:
	var sea := SeaOfConsciousness.new()
	sea.capacity = 100.0
	assert_eq(sea.is_full(), false, "not full when empty")
	sea.fill(100.0)
	assert_eq(sea.is_full(), true, "full when at capacity")


func test_add_turbulence() -> void:
	var sea := SeaOfConsciousness.new()
	sea.add_turbulence(0.3)
	assert_almost_eq(sea.turbulence, 0.3, "turbulence 0.3")
	sea.add_turbulence(0.5)
	assert_almost_eq(sea.turbulence, 0.8, "turbulence 0.8")


func test_turbulence_clamps_to_one() -> void:
	var sea := SeaOfConsciousness.new()
	sea.add_turbulence(1.5)
	assert_almost_eq(sea.turbulence, 1.0, "turbulence clamped to 1.0")


func test_calmed_reduces_turbulence() -> void:
	var sea := SeaOfConsciousness.new()
	sea.add_turbulence(0.8)
	sea.calm(0.3)
	assert_almost_eq(sea.turbulence, 0.5, "calm reduces turbulence")


func test_calmed_clamps_to_zero() -> void:
	var sea := SeaOfConsciousness.new()
	sea.add_turbulence(0.3)
	sea.calm(0.5)
	assert_almost_eq(sea.turbulence, 0.0, "calm clamped to zero")


func test_serialization_round_trip() -> void:
	var sea := SeaOfConsciousness.new()
	sea.tier = SeaOfConsciousness.DEEP
	sea.capacity = 200.0
	sea.current = 150.0
	sea.clarity = 0.8
	sea.turbulence = 0.2
	var restored := SeaOfConsciousness.from_dict(sea.to_dict())
	assert_eq(restored.tier, SeaOfConsciousness.DEEP, "tier round trip")
	assert_almost_eq(restored.capacity, 200.0, "capacity round trip")
	assert_almost_eq(restored.current, 150.0, "current round trip")
	assert_almost_eq(restored.clarity, 0.8, "clarity round trip")
	assert_almost_eq(restored.turbulence, 0.2, "turbulence round trip")


func test_attach_sea_sets_capacity_from_base() -> void:
	var actor := Actor.new(&"test", {MindStats.SEA_CAPACITY: 50.0})
	var sea := MindCultivationApi.attach_sea(actor)
	assert_almost_eq(sea.capacity, 50.0, "capacity from base attribute")


func test_sea_provider_emits_stats() -> void:
	var actor := Actor.new(&"test", {MindStats.SEA_CAPACITY: 100.0})
	MindCultivationApi.attach_sea(actor)
	var sea := MindCultivationApi.sea(actor)
	sea.fill(100.0)
	actor.mark_stats_dirty()
	assert_almost_eq(actor.stats.derived(MindStats.SEA_CAPACITY), 100.0, "provider capacity")
	assert_almost_eq(actor.stats.derived(MindStats.SEA_CLARITY), 0.5, "provider clarity")
	assert_almost_eq(actor.stats.derived(MindStats.SEA_TURBULENCE), 0.0, "provider turbulence")
	assert_almost_eq(actor.stats.derived(MindStats.SEA_FULL), 1.0, "provider full")


func test_sea_provider_not_full() -> void:
	var actor := Actor.new(&"test", {MindStats.SEA_CAPACITY: 100.0})
	MindCultivationApi.attach_sea(actor)
	var sea := MindCultivationApi.sea(actor)
	sea.fill(50.0)
	actor.mark_stats_dirty()
	assert_almost_eq(actor.stats.derived(MindStats.SEA_FULL), 0.0, "not full")
