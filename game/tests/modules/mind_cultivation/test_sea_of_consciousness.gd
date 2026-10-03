extends TestCase

## ADR 0016: Sea of Consciousness — fill, drain, turbulence, calm, serialization.
## The sea reads/mutates the actor's mind_power pool (single reservoir).


func _actor() -> Actor:
	var actor := Actor.new(&"test", {MindStats.SEA_CAPACITY: 100.0})
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	return actor


func test_fill_and_drain() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.set_structural_capacity(100.0)
	sea.fill(actor, 50.0)
	assert_almost_eq(sea.current(actor), 50.0, "fill 50")
	sea.drain(actor, 20.0)
	assert_almost_eq(sea.current(actor), 30.0, "drain 20")


func test_fill_clamps_to_capacity() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.set_structural_capacity(100.0)
	sea.fill(actor, 150.0)
	assert_almost_eq(sea.current(actor), 100.0, "clamped to capacity")


func test_drain_clamps_to_zero() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.set_structural_capacity(100.0)
	sea.fill(actor, 50.0)
	sea.drain(actor, 80.0)
	assert_almost_eq(sea.current(actor), 0.0, "clamped to zero")


func test_is_full() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.set_structural_capacity(100.0)
	assert_eq(sea.is_full(actor), false, "not full when empty")
	sea.fill(actor, 100.0)
	assert_eq(sea.is_full(actor), true, "full when at capacity")


func test_add_turbulence() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.add_turbulence(0.3)
	assert_almost_eq(sea.turbulence, 0.3, "turbulence 0.3")
	sea.add_turbulence(0.5)
	assert_almost_eq(sea.turbulence, 0.8, "turbulence 0.8")


func test_turbulence_clamps_to_one() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.add_turbulence(1.5)
	assert_almost_eq(sea.turbulence, 1.0, "turbulence clamped to 1.0")


func test_calmed_reduces_turbulence() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.add_turbulence(0.8)
	sea.calm(0.3)
	assert_almost_eq(sea.turbulence, 0.5, "calm reduces turbulence")


func test_calmed_clamps_to_zero() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.add_turbulence(0.3)
	sea.calm(0.5)
	assert_almost_eq(sea.turbulence, 0.0, "calm clamped to zero")


func test_serialization_round_trip() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.set_tier(SeaOfConsciousness.DEEP)
	sea.set_structural_capacity(200.0)
	sea.set_clarity(0.8)
	sea.set_purity(0.7)
	sea.add_turbulence(0.2)
	sea.trained_stage = 2
	var restored := SeaOfConsciousness.from_dict(sea.to_dict())
	assert_eq(restored.tier, SeaOfConsciousness.DEEP, "tier round trip")
	assert_almost_eq(restored.structural_capacity, 200.0, "capacity round trip")
	assert_almost_eq(restored.clarity, 0.8, "clarity round trip")
	assert_almost_eq(restored.purity, 0.7, "purity round trip")
	assert_almost_eq(restored.turbulence, 0.2, "turbulence round trip")
	assert_eq(restored.trained_stage, 2, "trained stage round trip")


func test_attach_sea_sets_capacity_from_base() -> void:
	var actor := Actor.new(&"test", {MindStats.SEA_CAPACITY: 50.0})
	var sea := MindCultivationApi.attach_sea(actor)
	assert_almost_eq(sea.structural_capacity, 50.0, "capacity from base attribute")


func test_attach_sea_is_idempotent() -> void:
	var actor := _actor()
	var sea1 := MindCultivationApi.attach_sea(actor)
	var sea2 := MindCultivationApi.attach_sea(actor)
	assert_eq(sea1 == sea2, true, "same sea instance")
	assert_eq(actor.stats.provider_count(), 2, "no duplicate providers")


func test_attach_is_idempotent() -> void:
	var actor := Actor.new(&"test", {})
	MindCultivationApi.attach(actor)
	var after_first := actor.stats.provider_count()
	assert_eq(after_first > 0, true, "attach installs the mind's providers")
	MindCultivationApi.attach(actor)
	# Idempotence is "a second attach adds nothing", not a fixed total. `attach` now
	# installs MindProvider AND SeaProvider (BL-0523), so the old hardcoded 1 described
	# the pre-fix world; asserting the count is unchanged is the property that matters.
	assert_eq(actor.stats.provider_count(), after_first, "no duplicate provider on re-attach")


## The sea's emitted stat surface is capacity, and capacity is the RESERVOIR's
## maximum — the same number `MindTraining.synchronize` sizes the pool from.
## Clarity, turbulence and fullness were DELETED from the surface (BL-0163): the
## first two restated component fields ADR 0071 reads off the component itself,
## and the third was a second definition of "full" that disagreed with
## `is_full` whenever the sea was turbulent. `test_mind_stat_surface.gd` pins the
## id set; this pins the value that survives.
func test_sea_provider_emits_only_the_reservoir_capacity() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.set_structural_capacity(100.0)
	sea.fill(actor, 100.0)
	actor.mark_stats_dirty()
	var emitted: Dictionary = SeaProvider.new().contribute(actor.stats._context)
	assert_eq(emitted.size(), 1, "capacity is the whole sea surface")
	assert_almost_eq(
		float(emitted[MindStats.SEA_CAPACITY]),
		sea.maximum(actor),
		"the reservoir maximum, not a re-derived capacity",
		0.01
	)
	assert_almost_eq(actor.stats.derived(MindStats.SEA_CAPACITY), 100.0, "provider capacity")


## The surviving definition of fullness, stated as a property of the two functions
## that used to disagree about it. With turbulence at 0.4 the sea's USABLE
## capacity is 80 of a 100 reservoir, so a reservoir at 85 saturates `ratio` at
## 1.0 while `is_full` is still false. The deleted `SEA_FULL` stat reported 1.0
## there: "the ratio is saturated" is not "the reservoir is full", and a gate
## reading the stat would have opened on a sea the gate's own rule refuses.
func test_a_turbulent_sea_saturates_its_ratio_without_being_full() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.set_structural_capacity(100.0)
	sea.fill(actor, 85.0)
	sea.add_turbulence(0.4)
	assert_almost_eq(sea.effective_capacity(), 80.0, "turbulence costs a fifth of the sea")
	assert_almost_eq(sea.ratio(actor), 1.0, "85 of 80 usable saturates the ratio")
	assert_eq(sea.is_full(actor), false, "and the reservoir is still not full")
	sea.fill(actor, 15.0)
	assert_eq(sea.is_full(actor), true, "full means the reservoir reached its own maximum")


func test_turbulence_reduces_effective_capacity() -> void:
	var actor := _actor()
	var sea := MindCultivationApi.sea(actor)
	sea.set_structural_capacity(100.0)
	sea.add_turbulence(0.4)
	assert_almost_eq(sea.effective_capacity(), 80.0, "turbulence reduces effective capacity")
