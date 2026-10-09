extends TestCase

## ADR 0015/0023: acupoint (acupoints) — block, clear, serialization.
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


## The set mediates the shared body reservoir rather than handing the pool out,
## so wiring is proved through the verbs: `fill`/`drain` return false until
## `synchronize` has pointed the set at the actor's body_integrity resource.
func test_acupoint_set_fill_and_drain_the_shared_pool() -> void:
	var actor := Actor.new(&"test", {})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"qi_refining"))
	BodyCultivationApi.attach(actor)
	# `attach_acupoints` builds the set but points it at no pool; only
	# `synchronize` resolves the actor's body_integrity resource into it. That gap
	# is what these verbs must refuse to touch.
	BodyCultivationApi.attach_acupoints(actor)
	var points: AcupointSet = actor.component(&"acupoints")
	assert_eq(points.drain(1.0), false, "no pool wired, so no drain")
	assert_eq(points.fill(1.0), false, "no pool wired, so no fill")

	BodyTraining.synchronize(actor)
	var integrity: ResourcePool = actor.resource(BodyStats.BODY_INTEGRITY)
	var full := integrity.current
	assert_almost_eq(integrity.ratio(), 1.0, "the pool starts full")

	assert_eq(points.drain(50.0), true, "drain accepted")
	# Relative to `full`, not to an authored maximum: the realm seed owns that
	# number and this test must not fail when it is retuned.
	assert_almost_eq(integrity.current, full - 50.0, "drain removed from the pool")
	assert_eq(integrity.ratio() < 1.0, true, "no longer full after the drain")

	assert_eq(points.fill(30.0), true, "fill accepted")
	assert_almost_eq(integrity.current, full - 20.0, "fill added to the pool")

	# A rejected amount must leave the balance alone rather than half-apply.
	assert_eq(points.fill(0.0), false, "zero fill rejected")
	assert_eq(points.drain(-5.0), false, "negative drain rejected")
	assert_almost_eq(integrity.current, full - 20.0, "balance untouched by rejected verbs")
