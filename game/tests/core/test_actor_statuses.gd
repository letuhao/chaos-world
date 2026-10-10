extends TestCase

## ADR 0002: statuses and relationships are core extension points.

var _removed: Array[StringName] = []


func _on_removed(status_id: StringName) -> void:
	_removed.append(status_id)


func test_timed_status_expires_and_emits() -> void:
	_removed = []
	var actor := Actor.new(&"hero")
	actor.status_removed.connect(_on_removed)
	actor.add_status(StatusEffect.new(&"burn", 0.5))
	assert_eq(actor.has_status(&"burn"), true, "status present")
	actor.tick_statuses(0.6)
	assert_eq(actor.has_status(&"burn"), false, "status expired")
	assert_eq(_removed.size(), 1, "removed signal emitted")


func test_permanent_status_survives_tick() -> void:
	var actor := Actor.new(&"hero")
	actor.add_status(StatusEffect.new(&"curse"))
	actor.tick_statuses(100.0)
	assert_eq(actor.has_status(&"curse"), true, "permanent status kept")


func test_relationships() -> void:
	var actor := Actor.new(&"hero")
	actor.affinity_rules().set_relationship(actor, &"partner", 42.0)
	assert_almost_eq(actor.affinity_rules().affinity_with(actor, &"partner"), 42.0, "affinity set")
	assert_almost_eq(
		actor.affinity_rules().affinity_with(actor, &"stranger"), 0.0, "unknown affinity"
	)
