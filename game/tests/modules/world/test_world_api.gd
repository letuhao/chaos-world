extends TestCase

## ADR 0019: WorldApi facade tests.

# ── Helpers ──────────────────────────────────────────────────────────────────


func _make_actor() -> Actor:
	return Actor.new(&"player", {Stat.PHYSIQUE: 20.0})


func _make_actor_with_world() -> Actor:
	var actor := _make_actor()
	actor.world = WorldState.new(&"micro", 10.0, 0.8)
	return actor


# ── tier() ───────────────────────────────────────────────────────────────────


func test_tier_null_actor() -> void:
	assert_eq(WorldApi.tier(null), "", "null actor returns empty string")


func test_tier_no_world() -> void:
	var actor := _make_actor()
	assert_eq(WorldApi.tier(actor), "", "no world returns empty string")


func test_tier_with_world() -> void:
	var actor := _make_actor_with_world()
	assert_eq(WorldApi.tier(actor), "micro", "returns tier string")


# ── laws() ───────────────────────────────────────────────────────────────────


func test_laws_null_actor() -> void:
	assert_eq(WorldApi.laws(null).size(), 0, "null actor returns empty array")


func test_laws_no_world() -> void:
	var actor := _make_actor()
	assert_eq(WorldApi.laws(actor).size(), 0, "no world returns empty array")


func test_laws_with_world_empty() -> void:
	var actor := _make_actor_with_world()
	assert_eq(WorldApi.laws(actor).size(), 0, "world with no laws returns empty array")


func test_laws_with_world_has_laws() -> void:
	var actor := _make_actor_with_world()
	actor.world.add_law(WorldLawState.new(&"gravity", WorldLawState.PHYSICAL, 2.0))
	var laws := WorldApi.laws(actor)
	assert_eq(laws.size(), 1, "one law returned")
	assert_eq(laws[0]["law_id"], "gravity", "law_id correct")
	assert_eq(laws[0]["group"], "physical", "group correct")
	assert_eq(laws[0]["value"], 2.0, "value correct")


# ── inhabitants() ────────────────────────────────────────────────────────────


func test_inhabitants_null_actor() -> void:
	assert_eq(WorldApi.inhabitants(null).size(), 0, "null actor returns empty array")


func test_inhabitants_no_world() -> void:
	var actor := _make_actor()
	assert_eq(WorldApi.inhabitants(actor).size(), 0, "no world returns empty array")


func test_inhabitants_with_world_empty() -> void:
	var actor := _make_actor_with_world()
	assert_eq(
		WorldApi.inhabitants(actor).size(), 0, "world with no inhabitants returns empty array"
	)


func test_inhabitants_with_world_has_inhabitants() -> void:
	var actor := _make_actor_with_world()
	actor.world.add_inhabitant(InhabitantRef.new(&"spirit_beast", InhabitantRef.BEAST, 5, 0.7))
	var inhabitants := WorldApi.inhabitants(actor)
	assert_eq(inhabitants.size(), 1, "one inhabitant returned")
	assert_eq(inhabitants[0]["inhabitant_id"], "spirit_beast", "inhabitant_id correct")
	assert_eq(inhabitants[0]["type"], "beast", "type correct")
	assert_eq(inhabitants[0]["count"], 5, "count correct")


# ── resources() ──────────────────────────────────────────────────────────────


func test_resources_null_actor() -> void:
	assert_eq(WorldApi.resources(null).size(), 0, "null actor returns empty dict")


func test_resources_no_world() -> void:
	var actor := _make_actor()
	assert_eq(WorldApi.resources(actor).size(), 0, "no world returns empty dict")


func test_resources_with_world() -> void:
	var actor := _make_actor_with_world()
	actor.world.resources[&"herbs"] = 50.0
	var res := WorldApi.resources(actor)
	assert_eq(res.size(), 1, "one resource returned")
	assert_eq(res[&"herbs"], 50.0, "resource value correct")


# ── locations() ──────────────────────────────────────────────────────────────


func test_locations_returns_all() -> void:
	var locations := WorldApi.locations(null)
	assert_eq(locations.size(), 4, "four locations returned")


func test_locations_structure() -> void:
	var locations := WorldApi.locations(null)
	var first: Dictionary = locations[0]
	assert_eq(first.has("location_id"), true, "has location_id")
	assert_eq(first.has("display_name"), true, "has display_name")
	assert_eq(first.has("tier"), true, "has tier")
	assert_eq(first.has("faction_id"), true, "has faction_id")
	assert_eq(first.has("resources"), true, "has resources")
	assert_eq(first.has("inhabitant_types"), true, "has inhabitant_types")
	assert_eq(first.has("danger_level"), true, "has danger_level")


## The authored catalogs reach the read: every row names its faction and tier by the
## defs' OWN display keys, not by an invented string, so the two catalogs have a
## production reader (BL-0227).
func test_locations_carry_the_authored_faction_and_tier_names() -> void:
	var locations := WorldApi.locations(null)
	assert_eq(locations.size() > 0, true, "the corpus ships locations to name")
	for row in locations:
		var loc := row as Dictionary
		assert_eq(
			String(loc.get("faction_name", "")),
			WorldDefIndex.display_name(&"faction", StringName(loc.get("faction_id", ""))),
			"the faction name is the authored def's own key"
		)
		assert_ne(String(loc.get("faction_name", "")), "", "and it is not empty")
		assert_eq(
			String(loc.get("tier_name", "")),
			WorldDefIndex.display_name(&"tier", StringName(loc.get("tier", ""))),
			"the tier name is the authored def's own key"
		)


# ── create_world() ───────────────────────────────────────────────────────────


func test_create_world_null_actor() -> void:
	var result := WorldApi.create_world(null, &"micro", 10.0)
	assert_eq(result["ok"], false, "null actor fails")
	assert_eq(result["reason"], "no_actor", "reason is no_actor")


func test_create_world_invalid_tier() -> void:
	var actor := _make_actor()
	var result := WorldApi.create_world(actor, &"invalid", 10.0)
	assert_eq(result["ok"], false, "invalid tier fails")
	assert_eq(result["reason"], "invalid_tier", "reason is invalid_tier")


func test_create_world_negative_size() -> void:
	var actor := _make_actor()
	var result := WorldApi.create_world(actor, &"micro", -5.0)
	assert_eq(result["ok"], false, "negative size fails")
	assert_eq(result["reason"], "invalid_size", "reason is invalid_size")


func test_create_world_zero_size() -> void:
	var actor := _make_actor()
	var result := WorldApi.create_world(actor, &"micro", 0.0)
	assert_eq(result["ok"], false, "zero size fails")
	assert_eq(result["reason"], "invalid_size", "reason is invalid_size")


func test_create_world_valid() -> void:
	var actor := _make_actor()
	var result := WorldApi.create_world(actor, &"small", 50.0)
	assert_eq(result["ok"], true, "valid creation succeeds")
	assert_eq(result["tier"], "small", "tier in result")
	assert_eq(result["size"], 50.0, "size in result")
	assert_eq(actor.world != null, true, "world assigned to actor")
	assert_eq(actor.world.tier, &"small", "world tier correct")
	assert_eq(actor.world.size, 50.0, "world size correct")


# ── add_law() ────────────────────────────────────────────────────────────────


func test_add_law_null_actor() -> void:
	var result := WorldApi.add_law(null, &"gravity", 2.0)
	assert_eq(result["ok"], false, "null actor fails")
	assert_eq(result["reason"], "no_actor", "reason is no_actor")


func test_add_law_no_world() -> void:
	var actor := _make_actor()
	var result := WorldApi.add_law(actor, &"gravity", 2.0)
	assert_eq(result["ok"], false, "no world fails")
	assert_eq(result["reason"], "no_world", "reason is no_world")


func test_add_law_zero_value() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.add_law(actor, &"gravity", 0.0)
	assert_eq(result["ok"], false, "zero value fails")
	assert_eq(result["reason"], "invalid_value", "reason is invalid_value")


func test_add_law_negative_value() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.add_law(actor, &"gravity", -1.0)
	assert_eq(result["ok"], false, "negative value fails")
	assert_eq(result["reason"], "invalid_value", "reason is invalid_value")


func test_add_law_valid() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.add_law(actor, &"gravity", 2.0)
	assert_eq(result["ok"], true, "valid law succeeds")
	assert_eq(result["law_id"], "gravity", "law_id in result")
	assert_eq(result["value"], 2.0, "value in result")
	assert_eq(actor.world.laws.size(), 1, "law added to world")
	assert_eq(actor.world.laws[0].law_id, &"gravity", "law_id correct on world")


# ── add_inhabitant() ─────────────────────────────────────────────────────────


func test_add_inhabitant_null_actor() -> void:
	var result := WorldApi.add_inhabitant(null, &"beast", &"beast", 5)
	assert_eq(result["ok"], false, "null actor fails")
	assert_eq(result["reason"], "no_actor", "reason is no_actor")


func test_add_inhabitant_no_world() -> void:
	var actor := _make_actor()
	var result := WorldApi.add_inhabitant(actor, &"beast", &"beast", 5)
	assert_eq(result["ok"], false, "no world fails")
	assert_eq(result["reason"], "no_world", "reason is no_world")


func test_add_inhabitant_zero_count() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.add_inhabitant(actor, &"beast", &"beast", 0)
	assert_eq(result["ok"], false, "zero count fails")
	assert_eq(result["reason"], "invalid_count", "reason is invalid_count")


func test_add_inhabitant_negative_count() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.add_inhabitant(actor, &"beast", &"beast", -1)
	assert_eq(result["ok"], false, "negative count fails")
	assert_eq(result["reason"], "invalid_count", "reason is invalid_count")


func test_add_inhabitant_valid() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.add_inhabitant(actor, &"spirit_beast", &"beast", 5)
	assert_eq(result["ok"], true, "valid inhabitant succeeds")
	assert_eq(result["inhabitant_id"], "spirit_beast", "inhabitant_id in result")
	assert_eq(result["type"], "beast", "type in result")
	assert_eq(result["count"], 5, "count in result")
	assert_eq(actor.world.inhabitants.size(), 1, "inhabitant added to world")
	assert_eq(actor.world.inhabitants[0].inhabitant_id, &"spirit_beast", "inhabitant_id correct")


# ── pay_upkeep() ─────────────────────────────────────────────────────────────


func test_pay_upkeep_null_actor() -> void:
	var result := WorldApi.pay_upkeep(null, 10.0)
	assert_eq(result["ok"], false, "null actor fails")
	assert_eq(result["reason"], "no_actor", "reason is no_actor")


func test_pay_upkeep_no_world() -> void:
	var actor := _make_actor()
	var result := WorldApi.pay_upkeep(actor, 10.0)
	assert_eq(result["ok"], false, "no world fails")
	assert_eq(result["reason"], "no_world", "reason is no_world")


func test_pay_upkeep_zero_amount() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.pay_upkeep(actor, 0.0)
	assert_eq(result["ok"], false, "zero amount fails")
	assert_eq(result["reason"], "invalid_amount", "reason is invalid_amount")


func test_pay_upkeep_negative_amount() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.pay_upkeep(actor, -5.0)
	assert_eq(result["ok"], false, "negative amount fails")
	assert_eq(result["reason"], "invalid_amount", "reason is invalid_amount")


func test_pay_upkeep_insufficient_qi() -> void:
	var actor := _make_actor_with_world()
	actor.world.upkeep_rate = 10.0
	var result := WorldApi.pay_upkeep(actor, 5.0)
	assert_eq(result["ok"], false, "insufficient qi fails")
	assert_eq(result["reason"], "insufficient_qi", "reason is insufficient_qi")
	assert_eq(result["required"], 10.0, "required in result")
	assert_eq(result["provided"], 5.0, "provided in result")


func test_pay_upkeep_exact_qi() -> void:
	var actor := _make_actor_with_world()
	actor.world.upkeep_rate = 10.0
	var result := WorldApi.pay_upkeep(actor, 10.0)
	assert_eq(result["ok"], true, "exact qi succeeds")
	assert_eq(result["amount"], 10.0, "amount in result")
	assert_eq(result["upkeep_rate"], 10.0, "upkeep_rate in result")


func test_pay_upkeep_sufficient_qi() -> void:
	var actor := _make_actor_with_world()
	actor.world.upkeep_rate = 5.0
	var result := WorldApi.pay_upkeep(actor, 15.0)
	assert_eq(result["ok"], true, "sufficient qi succeeds")
	assert_eq(result["amount"], 15.0, "amount in result")


# ── evolve_world() ───────────────────────────────────────────────────────────


func test_evolve_world_null_actor() -> void:
	var result := WorldApi.evolve_world(null)
	assert_eq(result["ok"], false, "null actor fails")
	assert_eq(result["reason"], "no_actor", "reason is no_actor")


func test_evolve_world_no_world() -> void:
	var actor := _make_actor()
	var result := WorldApi.evolve_world(actor)
	assert_eq(result["ok"], false, "no world fails")
	assert_eq(result["reason"], "no_world", "reason is no_world")


func test_evolve_world_micro_to_small() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.evolve_world(actor)
	assert_eq(result["ok"], true, "evolution succeeds")
	assert_eq(result["old_tier"], "micro", "old_tier correct")
	assert_eq(result["new_tier"], "small", "new_tier correct")
	assert_eq(actor.world.tier, &"small", "world tier updated")


func test_evolve_world_small_to_great() -> void:
	var actor := _make_actor_with_world()
	actor.world.tier = &"small"
	var result := WorldApi.evolve_world(actor)
	assert_eq(result["ok"], true, "evolution succeeds")
	assert_eq(result["new_tier"], "great", "new_tier correct")
	assert_eq(actor.world.tier, &"great", "world tier updated")


func test_evolve_world_max_tier() -> void:
	var actor := _make_actor_with_world()
	actor.world.tier = &"great"
	var result := WorldApi.evolve_world(actor)
	assert_eq(result["ok"], false, "max tier fails")
	assert_eq(result["reason"], "max_tier", "reason is max_tier")


# ── merge_world() ────────────────────────────────────────────────────────────


func test_merge_world_null_actor() -> void:
	var result := WorldApi.merge_world(null, null)
	assert_eq(result["ok"], false, "null actor fails")
	assert_eq(result["reason"], "no_actor", "reason is no_actor")


func test_merge_world_no_target() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.merge_world(actor, null)
	assert_eq(result["ok"], false, "null target fails")
	assert_eq(result["reason"], "no_target", "reason is no_target")


func test_merge_world_no_world() -> void:
	var actor := _make_actor()
	var target := _make_actor_with_world()
	var result := WorldApi.merge_world(actor, target)
	assert_eq(result["ok"], false, "no world fails")
	assert_eq(result["reason"], "no_world", "reason is no_world")


func test_merge_world_no_target_world() -> void:
	var actor := _make_actor_with_world()
	var target := _make_actor()
	var result := WorldApi.merge_world(actor, target)
	assert_eq(result["ok"], false, "no target world fails")
	assert_eq(result["reason"], "no_target_world", "reason is no_target_world")


func test_merge_world_insufficient_will() -> void:
	var actor := _make_actor_with_world()
	actor.world.will_strength = 0.5
	var target := _make_actor_with_world()
	target.world.will_strength = 0.8
	var result := WorldApi.merge_world(actor, target)
	assert_eq(result["ok"], false, "insufficient will fails")
	assert_eq(result["reason"], "insufficient_will", "reason is insufficient_will")


func test_merge_world_valid() -> void:
	var actor := _make_actor_with_world()
	actor.world.will_strength = 1.0
	var target := _make_actor_with_world()
	target.world.will_strength = 0.5
	target.world.size = 20.0
	var result := WorldApi.merge_world(actor, target)
	assert_eq(result["ok"], true, "valid merge succeeds")
	assert_eq(result["result_size"], 30.0, "result_size correct")
	assert_eq(actor.world.size, 30.0, "world size updated")


# ── trigger_conflict() ───────────────────────────────────────────────────────


func test_trigger_conflict_null_actor() -> void:
	var result := WorldApi.trigger_conflict(null, &"war", 0.5)
	assert_eq(result["ok"], false, "null actor fails")
	assert_eq(result["reason"], "no_actor", "reason is no_actor")


func test_trigger_conflict_no_world() -> void:
	var actor := _make_actor()
	var result := WorldApi.trigger_conflict(actor, &"war", 0.5)
	assert_eq(result["ok"], false, "no world fails")
	assert_eq(result["reason"], "no_world", "reason is no_world")


func test_trigger_conflict_invalid_id() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.trigger_conflict(actor, &"", 0.5)
	assert_eq(result["ok"], false, "empty conflict_id fails")
	assert_eq(result["reason"], "invalid_conflict_id", "reason is invalid_conflict_id")


func test_trigger_conflict_invalid_severity() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.trigger_conflict(actor, &"war", 0.0)
	assert_eq(result["ok"], false, "zero severity fails")
	assert_eq(result["reason"], "invalid_severity", "reason is invalid_severity")


func test_trigger_conflict_valid() -> void:
	var actor := _make_actor_with_world()
	var result := WorldApi.trigger_conflict(actor, &"war", 0.5)
	assert_eq(result["ok"], true, "valid conflict succeeds")
	assert_eq(result["conflict_id"], "war", "conflict_id in result")
	assert_eq(result["severity"], 0.5, "severity in result")
	assert_eq(result["stability_impact"], 0.05, "stability_impact correct")
	assert_eq(actor.world.stability, 0.75, "stability reduced")
