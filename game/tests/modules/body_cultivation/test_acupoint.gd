extends TestCase

## ADR 0015/0023: Huyệt (acupoints) — block, clear, serialization.
## Body essence is stored in the shared body_integrity pool, not per-acupoint.


func test_block_sets_blocked_flag() -> void:
	var point := Acupoint.new()
	point.block()
	assert_eq(point.blocked, true, "blocked flag set")


func test_clear_block_restores_open_state() -> void:
	var point := Acupoint.new()
	point.block()
	point.clear_block()
	assert_eq(point.blocked, false, "blocked flag cleared")


func test_serialization_round_trip() -> void:
	var point := Acupoint.new()
	point.id = &"minor_0"
	point.tier = Acupoint.MINOR
	point.quality = 0.8
	var restored := Acupoint.from_dict(point.to_dict())
	assert_eq(restored.id, &"minor_0", "id round trip")
	assert_eq(restored.tier, Acupoint.MINOR, "tier round trip")
	assert_almost_eq(restored.quality, 0.8, "quality round trip")
	assert_eq(restored.blocked, false, "blocked round trip")


func test_serialization_round_trip_blocked() -> void:
	var point := Acupoint.new()
	point.id = &"major_0"
	point.tier = Acupoint.MAJOR
	point.quality = 0.6
	point.block()
	var restored := Acupoint.from_dict(point.to_dict())
	assert_eq(restored.id, &"major_0", "id round trip")
	assert_eq(restored.tier, Acupoint.MAJOR, "tier round trip")
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


func test_attach_acupoints_is_idempotent() -> void:
	var actor := Actor.new(&"test", {})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	var points := BodyCultivationApi.acupoints(actor)
	var provider_count := actor.stats.provider_count()
	# Second call must not create a new set or add another provider.
	BodyCultivationApi.attach_acupoints(actor)
	assert_eq(BodyCultivationApi.acupoints(actor).size(), 36, "no duplicate points")
	assert_eq(actor.stats.provider_count(), provider_count, "no duplicate provider")


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


func test_acupoint_set_pool_operations() -> void:
	var actor := Actor.new(&"test", {})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	BodyTraining.synchronize(actor)
	var points: AcupointSet = actor.component(&"acupoints")
	assert_eq(points.pool() != null, true, "pool is set")
	assert_eq(points.is_full(), true, "pool starts full")
	# Drain first, then fill — the pool starts at maximum.
	points.drain(50.0)
	assert_almost_eq(points.current(), 50.0, "drain removes from pool")
	points.fill(30.0)
	assert_almost_eq(points.current(), 80.0, "fill adds to pool")
	assert_eq(points.is_full(), false, "no longer full after drain")
