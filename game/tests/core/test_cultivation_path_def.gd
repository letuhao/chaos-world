extends TestCase

## ADR 0006: a path's stage names overlay the shared ladder and fall back to it.


func test_stage_name_falls_back_to_realm() -> void:
	var def := CultivationPathDef.new()
	assert_eq(def.stage_name(&"qi_refining"), "Qi Refining", "fallback to realm name")
	assert_eq(def.stage_name(&"unknown"), "unknown", "unknown id returns the id")


func test_stage_name_overlay() -> void:
	var def := CultivationPathDef.new()
	var names: Array[String] = ["Alpha", "Beta"]
	def.stage_names = names
	assert_eq(def.stage_name(&"qi_refining"), "Alpha", "index 0")
	assert_eq(def.stage_name(&"foundation"), "Beta", "index 1")
	assert_eq(def.stage_name(&"core_formation"), "Core Formation", "beyond overlay falls back")
