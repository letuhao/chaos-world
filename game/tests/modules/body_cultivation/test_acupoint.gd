extends TestCase

## ADR 0015: Huyệt (acupoints) — fill, drain, block, clear, serialization.


func test_fill_and_drain() -> void:
	var point := Acupoint.new()
	point.capacity = 100.0
	point.fill(50.0)
	assert_almost_eq(point.current, 50.0, "fill 50")
	point.drain(20.0)
	assert_almost_eq(point.current, 30.0, "drain 20")


func test_fill_clamps_to_capacity() -> void:
	var point := Acupoint.new()
	point.capacity = 100.0
	point.fill(150.0)
	assert_almost_eq(point.current, 100.0, "clamped to capacity")


func test_drain_clamps_to_zero() -> void:
	var point := Acupoint.new()
	point.capacity = 100.0
	point.fill(50.0)
	point.drain(80.0)
	assert_almost_eq(point.current, 0.0, "clamped to zero")


func test_is_full() -> void:
	var point := Acupoint.new()
	point.capacity = 100.0
	assert_eq(point.is_full(), false, "not full when empty")
	point.fill(100.0)
	assert_eq(point.is_full(), true, "full when at capacity")


func test_block_sets_blocked_and_zeroes_current() -> void:
	var point := Acupoint.new()
	point.capacity = 100.0
	point.fill(80.0)
	point.block()
	assert_eq(point.blocked, true, "blocked flag set")
	assert_almost_eq(point.current, 0.0, "current zeroed on block")


func test_blocked_acupoint_cannot_fill() -> void:
	var point := Acupoint.new()
	point.capacity = 100.0
	point.block()
	point.fill(50.0)
	assert_almost_eq(point.current, 0.0, "blocked acupoint cannot fill")


func test_blocked_acupoint_cannot_drain() -> void:
	var point := Acupoint.new()
	point.capacity = 100.0
	point.fill(50.0)
	point.block()
	# current is already 0 from block; drain should be no-op
	point.drain(10.0)
	assert_almost_eq(point.current, 0.0, "blocked acupoint cannot drain")


func test_clear_block_restores_capacity() -> void:
	var point := Acupoint.new()
	point.capacity = 100.0
	point.block()
	point.clear_block()
	assert_eq(point.blocked, false, "blocked flag cleared")
	assert_almost_eq(point.effective_capacity(), 100.0, "effective capacity restored")


func test_blocked_effective_capacity_is_zero() -> void:
	var point := Acupoint.new()
	point.capacity = 100.0
	assert_almost_eq(point.effective_capacity(), 100.0, "open capacity")
	point.block()
	assert_almost_eq(point.effective_capacity(), 0.0, "blocked capacity is zero")


func test_serialization_round_trip() -> void:
	var point := Acupoint.new()
	point.id = &"minor_0"
	point.tier = Acupoint.MINOR
	point.capacity = 200.0
	point.current = 150.0
	point.quality = 0.8
	var restored := Acupoint.from_dict(point.to_dict())
	assert_eq(restored.id, &"minor_0", "id round trip")
	assert_eq(restored.tier, Acupoint.MINOR, "tier round trip")
	assert_almost_eq(restored.capacity, 200.0, "capacity round trip")
	assert_almost_eq(restored.current, 150.0, "current round trip")
	assert_almost_eq(restored.quality, 0.8, "quality round trip")
	assert_eq(restored.blocked, false, "blocked round trip")


func test_serialization_round_trip_blocked() -> void:
	var point := Acupoint.new()
	point.id = &"major_0"
	point.tier = Acupoint.MAJOR
	point.capacity = 200.0
	point.current = 100.0
	point.quality = 0.6
	point.block()
	var restored := Acupoint.from_dict(point.to_dict())
	assert_eq(restored.id, &"major_0", "id round trip")
	assert_eq(restored.tier, Acupoint.MAJOR, "tier round trip")
	assert_almost_eq(restored.capacity, 200.0, "capacity round trip")
	assert_almost_eq(restored.current, 0.0, "current zeroed by block")
	assert_almost_eq(restored.quality, 0.6, "quality round trip")
	assert_eq(restored.blocked, true, "blocked round trip")


func test_attach_acupoints_creates_minor_points() -> void:
	var actor := Actor.new(&"test", {})
	BodyCultivationApi.attach_acupoints(actor)
	var points := BodyCultivationApi.acupoints(actor)
	assert_eq(points.size(), 36, "36 minor acupoints at realm 0")


func test_attach_acupoints_creates_major_points_at_spirit_tier() -> void:
	var actor := Actor.new(&"test", {})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"spirit_sea"))
	BodyCultivationApi.attach_acupoints(actor)
	var points := BodyCultivationApi.acupoints(actor)
	assert_eq(points.size(), 48, "36 minor + 12 major at Spirit tier")


func test_acupoint_provider_emits_stats() -> void:
	var actor := Actor.new(&"test", {})
	BodyCultivationApi.attach_acupoints(actor)
	var points := BodyCultivationApi.acupoints(actor)
	# Set quality on first point
	var first: Acupoint = points[0]
	first.quality = 0.8
	actor.mark_stats_dirty()
	assert_almost_eq(actor.stats.derived(BodyStats.ACUPOINT_COUNT), 36.0, "open count")
	assert_almost_eq(actor.stats.derived(BodyStats.ACUPOINT_BLOCKED_COUNT), 0.0, "blocked count")
	# Average quality = (0.8 + 35*0.5) / 36 = (0.8 + 17.5) / 36 = 18.3 / 36 = 0.5083...
	var expected_avg := (0.8 + 35.0 * 0.5) / 36.0
	assert_almost_eq(actor.stats.derived(BodyStats.ACUPOINT_QUALITY), expected_avg, "avg quality")


func test_acupoint_provider_blocked_count() -> void:
	var actor := Actor.new(&"test", {})
	BodyCultivationApi.attach_acupoints(actor)
	var points := BodyCultivationApi.acupoints(actor)
	# Block first 3 points
	for i in 3:
		var point: Acupoint = points[i]
		point.block()
	actor.mark_stats_dirty()
	assert_almost_eq(
		actor.stats.derived(BodyStats.ACUPOINT_COUNT), 33.0, "open count after blocking"
	)
	assert_almost_eq(actor.stats.derived(BodyStats.ACUPOINT_BLOCKED_COUNT), 3.0, "blocked count")
