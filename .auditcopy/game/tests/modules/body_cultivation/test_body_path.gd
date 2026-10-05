extends TestCase

## ADR 0012: body cultivation path definition — 30 stages on the shared ladder.


func test_path_id() -> void:
	var def := BodyPath.path_def()
	assert_eq(def.id, BodyPath.PATH_ID, "path id")
	assert_eq(def.id, &"body_cultivation", "path id value")


func test_display_name() -> void:
	var def := BodyPath.path_def()
	assert_eq(def.display_name, "Body Cultivation", "display name")


func test_thirty_stages() -> void:
	var def := BodyPath.path_def()
	assert_eq(def.stage_names.size(), 30, "30 stages")


func test_first_stage() -> void:
	var def := BodyPath.path_def()
	assert_eq(def.stage_name(&"qi_refining"), "Skin Tempering", "first stage")


func test_spirit_stage() -> void:
	var def := BodyPath.path_def()
	assert_eq(def.stage_name(&"spirit_sea"), "Gold Body", "spirit stage")


func test_transcendent_stage() -> void:
	var def := BodyPath.path_def()
	assert_eq(def.stage_name(&"dao_ancestor"), "Body of Divinity", "transcendent stage")


func test_resource_ids() -> void:
	var def := BodyPath.path_def()
	assert_eq(def.resource_ids.size(), 1, "one resource")
	assert_eq(def.resource_ids[0], &"body_integrity", "body_integrity resource")
