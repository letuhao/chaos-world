extends TestCase

## ADR 0001/0002/0003: resources clamp, paths expose a realm, serialization round-trips.


func test_resource_pool_clamps() -> void:
	var pool := ResourcePool.new(&"qi", 100.0)
	pool.change(150.0)
	assert_almost_eq(pool.current, 100.0, "clamped to max")
	pool.change(-150.0)
	assert_almost_eq(pool.current, 0.0, "clamped to zero")


func test_actor_resource_lookup() -> void:
	var actor := Actor.new(&"hero")
	actor.add_resource(ResourcePool.new(&"qi", 50.0))
	assert_almost_eq(actor.resource(&"qi").maximum, 50.0, "resource max")
	assert_eq(actor.resource(&"missing"), null, "missing resource")


func test_actor_realm_from_primary_path() -> void:
	var actor := Actor.new(&"hero")
	actor.set_path(PathState.new(&"qi", &"refining"))
	assert_eq(actor.realm(), &"refining", "primary realm")


func test_actor_round_trip() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 12.0})
	actor.display_name = "Hero"
	actor.add_resource(ResourcePool.new(&"qi", 50.0))
	actor.set_path(PathState.new(&"qi", &"refining"))
	var restored := Actor.from_dict(actor.to_dict())
	assert_eq(restored.id, actor.id, "id round trip")
	assert_eq(restored.display_name, actor.display_name, "name round trip")
	assert_almost_eq(restored.stats.get_base(Stat.PHYSIQUE), 12.0, "base round trip")
	assert_eq(restored.realm(), &"refining", "realm round trip")
