extends TestCase

## ADR 0003/0005: breakthrough advances a path one realm when its condition is met.


class AlwaysCondition:
	extends BreakthroughCondition

	func can_breakthrough(_actor: Actor, _state: PathState, _context: Dictionary) -> bool:
		return true


class NeverCondition:
	extends BreakthroughCondition

	func can_breakthrough(_actor: Actor, _state: PathState, _context: Dictionary) -> bool:
		return false


func test_breakthrough_requires_condition() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"qi_refining"))
	assert_eq(Breakthrough.try_advance(actor, &"qi", NeverCondition.new()), false, "blocked")
	assert_eq(actor.path(&"qi").rank_id, &"qi_refining", "unchanged")


func test_breakthrough_advances_and_rescales() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.set_path(PathState.new(&"qi", &"qi_refining"))
	assert_eq(Breakthrough.try_advance(actor, &"qi", AlwaysCondition.new()), true, "advanced")
	assert_eq(actor.path(&"qi").rank_id, &"foundation", "next realm")
	assert_eq(actor.path(&"qi").stage, 1, "stage incremented")
	assert_almost_eq(actor.stats.derived(Stat.MAX_HEALTH), 165.0, "realm scaling applied")


func test_no_breakthrough_past_the_top() -> void:
	var actor := Actor.new(&"hero")
	actor.set_path(PathState.new(&"qi", &"primordial_origin"))
	assert_eq(Breakthrough.try_advance(actor, &"qi", AlwaysCondition.new()), false, "top realm")


func test_breakthrough_without_condition_is_allowed() -> void:
	var actor := Actor.new(&"hero")
	actor.set_path(PathState.new(&"qi", &"qi_refining"))
	assert_eq(Breakthrough.try_advance(actor, &"qi"), true, "no condition required by core")
