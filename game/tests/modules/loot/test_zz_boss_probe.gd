extends TestCase


func test_probe_storm_phoenix_resolve() -> void:
	for tier_index in [0, 1, 2]:
		var boss := &"amulet_storm_phoenix"
		var table := LootContent.instance().table_for_boss(boss, tier_index)
		print("PROBE tier ", tier_index, " table: ", table.id if table != null else "null")
		if table == null:
			continue
		var context := LootResolver.make_context(&"qi_refining", &"common", boss, {})
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		var resolved := LootResolver.resolve(table, context, rng)
		print("PROBE tier ", tier_index, " plans: ", (resolved["plans"] as Array).size(), " warnings: ", resolved["warnings"])
	assert_eq(true, true, "probe")
