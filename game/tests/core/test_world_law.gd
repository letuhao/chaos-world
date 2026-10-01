extends TestCase

## ADR 0019: WorldLawState tests.


func test_world_law_creation_defaults() -> void:
	var law := WorldLawState.new()
	assert_eq(law.law_id, &"", "default law_id is empty")
	assert_eq(law.group, WorldLawState.SPATIAL, "default group is spatial")
	assert_eq(law.value, 1.0, "default value is 1.0")
	assert_eq(law.locked, false, "default locked is false")


func test_world_law_creation_custom() -> void:
	var law := WorldLawState.new(&"gravity", WorldLawState.PHYSICAL, 2.5)
	assert_eq(law.law_id, &"gravity", "custom law_id")
	assert_eq(law.group, WorldLawState.PHYSICAL, "custom group")
	assert_eq(law.value, 2.5, "custom value")
	assert_eq(law.locked, false, "not locked by default")


func test_world_law_serialization() -> void:
	var law := WorldLawState.new(&"fire_cycle", WorldLawState.ELEMENTAL, 0.8)
	law.locked = true
	var data := law.to_dict()
	assert_eq(data["law_id"], "fire_cycle", "law_id serialized")
	assert_eq(data["group"], "elemental", "group serialized")
	assert_eq(data["value"], 0.8, "value serialized")
	assert_eq(data["locked"], true, "locked serialized")
	var restored := WorldLawState.from_dict(data)
	assert_eq(restored.law_id, &"fire_cycle", "law_id restored")
	assert_eq(restored.group, WorldLawState.ELEMENTAL, "group restored")
	assert_eq(restored.value, 0.8, "value restored")
	assert_eq(restored.locked, true, "locked restored")


func test_world_law_from_dict_defaults() -> void:
	var law := WorldLawState.from_dict({})
	assert_eq(law.law_id, &"", "default law_id")
	assert_eq(law.group, WorldLawState.SPATIAL, "default group")
	assert_eq(law.value, 1.0, "default value")
	assert_eq(law.locked, false, "default locked")
