extends TestCase

## ADR 0011: Qi Cultivation path definition — 30 stages aligned to the shared ladder.


func test_path_id() -> void:
	var def := QiPath.path_def()
	assert_eq(def.id, QiPath.PATH_ID, "path id")
	assert_eq(def.id, &"qi_cultivation", "path id value")


func test_display_name() -> void:
	var def := QiPath.path_def()
	assert_eq(def.display_name, "Qi Cultivation", "display name")


func test_thirty_stages() -> void:
	var def := QiPath.path_def()
	assert_eq(def.stage_names.size(), 30, "30 stages")


func test_first_stage() -> void:
	var def := QiPath.path_def()
	assert_eq(def.stage_name(&"qi_refining"), "Qi Refining", "first stage")


func test_spirit_stage() -> void:
	var def := QiPath.path_def()
	assert_eq(def.stage_name(&"spirit_sea"), "Spirit Sea", "spirit stage")


func test_immortal_stage() -> void:
	var def := QiPath.path_def()
	assert_eq(def.stage_name(&"golden_immortal"), "Golden Immortal", "immortal stage")


func test_transcendent_stage() -> void:
	var def := QiPath.path_def()
	assert_eq(def.stage_name(&"dao_ancestor"), "Dao Ancestor", "transcendent stage")


func test_resource_ids() -> void:
	var def := QiPath.path_def()
	assert_eq(def.resource_ids.size(), 2, "two resources")
	assert_eq(def.resource_ids[0], &"qi", "qi resource")
	assert_eq(def.resource_ids[1], &"qi_purity", "qi_purity resource")
