extends TestCase

## ADR 0021/0057: AscensionState tests. The ascent is walked with `ascend`; no
## test writes `stage`, `dao_level`, or `steps` to reach a conclusion, because
## writing them is exactly the state the gate must refuse.


func test_ascension_state_defaults() -> void:
	var state := AscensionState.new()
	assert_eq(state.stage, AscensionState.STAGE_DAO_COMPREHENSION, "default stage")
	assert_eq(state.dao_type, &"", "default dao_type is empty")
	assert_eq(state.dao_level, 1, "default dao_level is 1")
	assert_eq(state.comprehension, 0.0, "default comprehension is 0")
	assert_eq(state.steps, 0, "no steps walked")
	assert_eq(state.abilities.is_empty(), true, "no abilities by default")


func test_ascension_state_custom() -> void:
	var state := AscensionState.new(AscensionState.STAGE_DAO_FUSION, &"fire", 3, 50.0, 2)
	assert_eq(state.stage, AscensionState.STAGE_DAO_FUSION, "custom stage")
	assert_eq(state.dao_type, &"fire", "custom dao_type")
	assert_eq(state.dao_level, 3, "custom dao_level")
	assert_eq(state.comprehension, 50.0, "custom comprehension")
	assert_eq(state.steps, 2, "custom steps")


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


## The ascent ladder itself: four steps take stage 1/dao 1 to the caps, the fifth
## is refused, and each step is a strict increase over the last.
func test_ascension_ascend_walks_the_whole_ladder() -> void:
	var state := AscensionState.new()
	var ladder := [
		[2, 2],
		[3, 3],
		[3, 4],
		[3, 5],
	]
	for expected in ladder:
		assert_eq(state.is_complete(), false, "not finished before the last step")
		assert_eq(state.ascend(), true, "step taken")
		assert_eq(state.stage, expected[0], "stage after the step")
		assert_eq(state.dao_level, expected[1], "dao_level after the step")
	assert_eq(state.is_complete(), true, "finished at four steps")
	assert_eq(state.ascend(), false, "refuses a step past the top")
	assert_eq(state.steps, AscensionState.ASCENT_STEPS, "step count capped")
	assert_eq(
		state.comprehension,
		AscensionState.REQUIRED_COMPREHENSION,
		"comprehension is one step's share per step"
	)


func test_ascension_is_not_complete_before_the_last_step() -> void:
	var state := AscensionState.new()
	var guard := 0
	while not state.is_complete() and guard < 16:
		guard += 1
		state.ascend()
	assert_eq(state.steps_remaining(), 0, "nothing left to walk")
	var walked := state.steps
	state.ascend()
	assert_eq(state.steps, walked, "a finished ascent takes no further step")


## A hand-written stage and dao level must not open the gate on their own: the
## step count and the comprehension are what a walk leaves behind.
func test_ascension_stage_and_dao_alone_do_not_complete() -> void:
	var state := AscensionState.new(AscensionState.STAGE_TRANSCENDENCE, &"sword", 5, 400.0)
	assert_eq(state.stage, AscensionState.STAGE_TRANSCENDENCE, "stage at the cap")
	assert_eq(state.dao_level, AscensionState.MAX_DAO_LEVEL, "dao_level at the cap")
	assert_eq(state.is_complete(), false, "no steps walked")
	var guard := 0
	while not state.is_complete() and guard < 16:
		guard += 1
		state.ascend()
	assert_eq(state.is_complete(), true, "complete only after the walk")
	assert_eq(state.steps, AscensionState.ASCENT_STEPS, "which took the whole ladder")


func test_ascension_serialization() -> void:
	var state := AscensionState.new(AscensionState.STAGE_DAO_FUSION, &"sword", 4, 200.0, 2)
	state.add_ability(&"sword_qi")
	state.add_ability(&"sword_domain")
	var data := state.to_dict()
	assert_eq(data["stage"], 2, "stage serialized")
	assert_eq(data["dao_type"], "sword", "dao_type serialized")
	assert_eq(data["dao_level"], 4, "dao_level serialized")
	assert_eq(data["comprehension"], 200.0, "comprehension serialized")
	assert_eq(data["steps"], 2, "steps serialized")
	assert_eq(data["abilities"].size(), 2, "abilities serialized")
	var restored := AscensionState.from_dict(data)
	assert_eq(restored.stage, 2, "stage restored")
	assert_eq(restored.dao_type, &"sword", "dao_type restored")
	assert_eq(restored.dao_level, 4, "dao_level restored")
	assert_eq(restored.comprehension, 200.0, "comprehension restored")
	assert_eq(restored.steps, 2, "steps restored")
	assert_eq(restored.abilities.size(), 2, "abilities restored")
	assert_eq(restored.abilities[0], &"sword_qi", "ability 0 restored")
	assert_eq(restored.abilities[1], &"sword_domain", "ability 1 restored")


## A payload written before `steps` existed carries only the comprehension it
## accumulated; the walk it records is that much work over one step's share.
func test_ascension_from_dict_without_steps_keeps_the_walk() -> void:
	var state := AscensionState.from_dict({"stage": 3, "dao_level": 5, "comprehension": 300.0})
	assert_eq(state.steps, 3, "three steps' worth of comprehension restored")
	assert_eq(state.is_complete(), false, "and it is still three steps short")


func test_ascension_from_dict_defaults() -> void:
	var state := AscensionState.from_dict({})
	assert_eq(state.stage, 1, "default stage")
	assert_eq(state.dao_type, &"", "default dao_type")
	assert_eq(state.dao_level, 1, "default dao_level")
	assert_eq(state.comprehension, 0.0, "default comprehension")
	assert_eq(state.steps, 0, "default steps")
	assert_eq(state.abilities.is_empty(), true, "no abilities")


## A completed ascent must survive a save: `steps` is the count the gate reads, so
## a payload that dropped it would silently re-close the Transcendent gate.
func test_actor_ascension_serialization() -> void:
	var actor := Actor.new(&"hero")
	var ascension := AscensionState.new()
	var ascended := 0
	while not ascension.is_complete() and ascended <= AscensionState.ASCENT_STEPS:
		assert_eq(ascension.ascend(), true, "ascend step taken")
		ascended += 1
	ascension.add_ability(&"fireball")
	actor.ascension = ascension
	var data := actor.to_dict()
	assert_eq(data["ascension"]["steps"], AscensionState.ASCENT_STEPS, "steps in actor dict")
	var restored := Actor.from_dict(data)
	assert_eq(restored.ascension != null, true, "ascension restored")
	assert_eq(restored.ascension.stage, 3, "stage restored")
	assert_eq(restored.ascension.dao_level, AscensionState.MAX_DAO_LEVEL, "dao_level restored")
	assert_eq(restored.ascension.steps, AscensionState.ASCENT_STEPS, "steps restored")
	assert_eq(restored.ascension.is_complete(), true, "the gate stays open across a save")
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
	# Transcendent (index 27) → Dao Ancestor (index 28) — ascension required
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"transcendent"))
	assert_eq(
		Breakthrough.try_advance_with_ascension(actor, &"qi"), false, "blocked without ascension"
	)
	assert_eq(actor.path(&"qi").rank_id, &"transcendent", "unchanged")


## The walked ascent opens the gate; the same realm with a hand-written stage and
## dao level does not. Both directions of one gate, same prior state otherwise.
func test_breakthrough_with_ascension_complete_ascension_allows_advance() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"transcendent"))
	actor.ascension = AscensionState.new(AscensionState.STAGE_TRANSCENDENCE, &"sword", 5, 400.0)
	assert_eq(
		Breakthrough.try_advance_with_ascension(actor, &"qi"),
		false,
		"a hand-written stage and dao level are not a walked ascent"
	)
	assert_eq(actor.path(&"qi").rank_id, &"transcendent", "unchanged")
	var walked := 0
	while WorldAnchor.ascend(actor) and walked < AscensionState.ASCENT_STEPS + 1:
		walked += 1
	assert_eq(
		Breakthrough.try_advance_with_ascension(actor, &"qi"),
		true,
		"advanced after walking the ascent"
	)
	assert_eq(actor.path(&"qi").rank_id, &"dao_ancestor", "next realm")


func test_breakthrough_with_ascension_incomplete_ascension_blocks() -> void:
	# Transcendent (index 27) → Dao Ancestor (index 28) with one step walked
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"transcendent"))
	actor.ascension = AscensionState.new()
	assert_eq(WorldAnchor.ascend(actor), true, "one step walked")
	assert_eq(
		Breakthrough.try_advance_with_ascension(actor, &"qi"),
		false,
		"blocked part-way up the ascent"
	)
	assert_eq(actor.path(&"qi").rank_id, &"transcendent", "unchanged")
