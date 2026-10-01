extends TestCase

## ADR 0003/0006: a path overlays the shared ladder and plugs in its model/resources.


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


func test_make_model_defaults_to_ladder() -> void:
	var model := CultivationPathDef.new().make_model()
	assert_eq(model is LadderProgression, true, "defaults to ladder progression")


func test_ensure_resources_creates_path_pools() -> void:
	var def := CultivationPathDef.new()
	var ids: Array[StringName] = [&"qi"]
	def.resource_ids = ids
	var actor := Actor.new(&"hero")
	def.ensure_resources(actor)
	assert_eq(actor.resource(&"qi") != null, true, "path resource created")
