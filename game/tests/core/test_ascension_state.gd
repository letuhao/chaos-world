extends TestCase

## ADR 0021: AscensionState tests.


func test_ascension_state_defaults() -> void:
	var state := AscensionState.new()
	assert_eq(state.stage, AscensionState.STAGE_DAO_COMPREHENSION, "default stage")
	assert_eq(state.dao_type, &"", "default dao_type is empty")
	assert_eq(state.dao_level, 1, "default dao_level is 1")
	assert_eq(state.comprehension, 0.0, "default comprehension is 0")
	assert_eq(state.abilities.is_empty(), true, "no abilities by default")


func test_ascension_state_custom() -> void:
	var state := AscensionState.new(AscensionState.STAGE_DAO_FUSION, &"fire", 3, 50.0)
	assert_eq(state.stage, AscensionState.STAGE_DAO_FUSION, "custom stage")
	assert_eq(state.dao_type, &"fire", "custom dao_type")
	assert_eq(state.dao_level, 3, "custom dao_level")
	assert_eq(state.comprehension, 50.0, "custom comprehension")


func test_ascension_is_complete() -> void:
	var state := AscensionState.new()
	assert_eq(state.is_complete(), false, "not complete at defaults")
	state.stage = AscensionState.STAGE_TRANSCENDENCE
	assert_eq(state.is_complete(), false, "not complete without max dao_level")
	state.dao_level = AscensionState.MAX_DAO_LEVEL
	assert_eq(state.is_complete(), true, "complete at stage 3 + dao_level 5")


func test_ascension_advance_stage() -> void:
	var state := AscensionState.new()
	assert_eq(state.stage, 1, "initial stage")
	state.advance_stage()
	assert_eq(state.stage, 2, "advanced to stage 2")
	state.advance_stage()
	assert_eq(state.stage, 3, "advanced to stage 3")
	state.advance_stage()
	assert_eq(state.stage, 3, "capped at stage 3")


func test_ascension_improve_dao() -> void:
	var state := AscensionState.new()
	assert_eq(state.dao_level, 1, "initial dao_level")
	state.improve_dao(2)
	assert_eq(state.dao_level, 3, "improved to 3")
	state.improve_dao(10)
	assert_eq(state.dao_level, AscensionState.MAX_DAO_LEVEL, "capped at max")
	state.improve_dao(-10)
	assert_eq(state.dao_level, 1, "floored at 1")


func test_ascension_add_ability() -> void:
	var state := AscensionState.new()
	state.add_ability(&"fireball")
	assert_eq(state.abilities.size(), 1, "ability added")
	assert_eq(state.abilities[0], &"fireball", "ability value")
	state.add_ability(&"fireball")
	assert_eq(state.abilities.size(), 1, "duplicate not added")
	state.add_ability(&"flame_shield")
	assert_eq(state.abilities.size(), 2, "second ability added")


func test_ascension_serialization() -> void:
	var state := AscensionState.new(AscensionState.STAGE_DAO_FUSION, &"sword", 4, 75.0)
	state.add_ability(&"sword_qi")
	state.add_ability(&"sword_domain")
	var data := state.to_dict()
	assert_eq(data["stage"], 2, "stage serialized")
	assert_eq(data["dao_type"], "sword", "dao_type serialized")
	assert_eq(data["dao_level"], 4, "dao_level serialized")
	assert_eq(data["comprehension"], 75.0, "comprehension serialized")
	assert_eq(data["abilities"].size(), 2, "abilities serialized")
	var restored := AscensionState.from_dict(data)
	assert_eq(restored.stage, 2, "stage restored")
	assert_eq(restored.dao_type, &"sword", "dao_type restored")
	assert_eq(restored.dao_level, 4, "dao_level restored")
	assert_eq(restored.comprehension, 75.0, "comprehension restored")
	assert_eq(restored.abilities.size(), 2, "abilities restored")
	assert_eq(restored.abilities[0], &"sword_qi", "ability 0 restored")
	assert_eq(restored.abilities[1], &"sword_domain", "ability 1 restored")


func test_ascension_from_dict_defaults() -> void:
	var state := AscensionState.from_dict({})
	assert_eq(state.stage, 1, "default stage")
	assert_eq(state.dao_type, &"", "default dao_type")
	assert_eq(state.dao_level, 1, "default dao_level")
	assert_eq(state.comprehension, 0.0, "default comprehension")
	assert_eq(state.abilities.is_empty(), true, "no abilities")


func test_actor_ascension_serialization() -> void:
	var actor := Actor.new(&"hero")
	var ascension := AscensionState.new(AscensionState.STAGE_DAO_FUSION, &"fire", 3, 50.0)
	ascension.add_ability(&"fireball")
	actor.ascension = ascension
	var data := actor.to_dict()
	assert_eq(data["ascension"]["stage"], 2, "ascension stage in actor dict")
	var restored := Actor.from_dict(data)
	assert_eq(restored.ascension != null, true, "ascension restored")
	assert_eq(restored.ascension.stage, 2, "stage restored")
	assert_eq(restored.ascension.dao_type, &"fire", "dao_type restored")
	assert_eq(restored.ascension.dao_level, 3, "dao_level restored")
	assert_eq(restored.ascension.comprehension, 50.0, "comprehension restored")
	assert_eq(restored.ascension.abilities.size(), 1, "abilities restored")


func test_breakthrough_with_ascension_below_transcendent() -> void:
	# Dao Fruit (index 25) → Immortal Sovereign (index 26) — below Transcendent, ascension not required
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"dao_fruit"))
	assert_eq(
		Breakthrough.try_advance_with_ascension(actor, &"qi"), true, "advanced without ascension"
	)
	assert_eq(actor.path(&"qi").rank_id, &"immortal_sovereign", "next realm")


func test_breakthrough_with_ascension_requires_ascension_at_transcendent() -> void:
	# Transcendent (index 27) — ascension required
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"transcendent"))
	assert_eq(
		Breakthrough.try_advance_with_ascension(actor, &"qi"), false, "blocked without ascension"
	)
	assert_eq(actor.path(&"qi").rank_id, &"transcendent", "unchanged")


func test_breakthrough_with_ascension_complete_ascension_allows_advance() -> void:
	# Transcendent (index 27) with complete ascension — breakthrough proceeds
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"transcendent"))
	var ascension := AscensionState.new(AscensionState.STAGE_TRANSCENDENCE, &"sword", 5, 100.0)
	actor.ascension = ascension
	assert_eq(
		Breakthrough.try_advance_with_ascension(actor, &"qi"),
		true,
		"advanced with complete ascension"
	)
	assert_eq(actor.path(&"qi").rank_id, &"dao_ancestor", "next realm")


func test_breakthrough_with_ascension_incomplete_ascension_blocks() -> void:
	# Transcendent (index 27) with incomplete ascension — breakthrough blocked
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"transcendent"))
	var ascension := AscensionState.new(AscensionState.STAGE_DAO_COMPREHENSION, &"fire", 1, 10.0)
	actor.ascension = ascension
	assert_eq(
		Breakthrough.try_advance_with_ascension(actor, &"qi"),
		false,
		"blocked with incomplete ascension"
	)
	assert_eq(actor.path(&"qi").rank_id, &"transcendent", "unchanged")
