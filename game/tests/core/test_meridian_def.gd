extends TestCase

## ADR 0017: MeridianDef is a data-driven resource for meridian definitions.


func test_meridian_def_properties() -> void:
	var def := MeridianDef.new()
	def.id = &"lung"
	def.display_name = "Lung"
	def.type = &"primary"
	def.tier = 0
	def.capacity_bonus = 0.05
	def.flow_bonus = 0.10
	def.power_bonus = 0.05
	assert_eq(def.id, &"lung", "id")
	assert_eq(def.display_name, "Lung", "display_name")
	assert_eq(def.type, &"primary", "type")
	assert_eq(def.tier, 0, "tier")
	assert_almost_eq(def.capacity_bonus, 0.05, "capacity_bonus")
	assert_almost_eq(def.flow_bonus, 0.10, "flow_bonus")
	assert_almost_eq(def.power_bonus, 0.05, "power_bonus")


func test_meridian_defaults_count() -> void:
	var defs := MeridianDefaults.all()
	assert_eq(defs.size(), 20, "20 meridians")


func test_meridian_defaults_types() -> void:
	var defs := MeridianDefaults.all()
	var primary_count := 0
	var extraordinary_count := 0
	for def in defs:
		if def.type == MeridianDefaults.PRIMARY:
			primary_count += 1
		elif def.type == MeridianDefaults.EXTRAORDINARY:
			extraordinary_count += 1
	assert_eq(primary_count, 12, "12 primary")
	assert_eq(extraordinary_count, 8, "8 extraordinary")


func test_meridian_defaults_tiers() -> void:
	var defs := MeridianDefaults.all()
	for def in defs:
		if def.type == MeridianDefaults.PRIMARY:
			assert_eq(def.tier < 9, true, "primary tier < 9")
		else:
			assert_eq(def.tier >= 9, true, "extraordinary tier >= 9")


## BL-0272: the authored files ARE the loader's source. Every file under the loader's
## own directory must come back from `all()`, keyed by its filename — the claim that
## makes "adding a meridian is a file" true, and the guard that turns a file which
## fails to load into a red rather than a silent 19.
func test_the_loaded_set_equals_the_authored_files() -> void:
	var paths := ContentScan.files_under(MeridianDefaults.DIR)
	assert_eq(paths.size(), 20, "the authored corpus is twenty files")
	var loaded := {}
	for def in MeridianDefaults.all():
		loaded[def.id] = true
	assert_eq(
		loaded.size(),
		paths.size(),
		"every authored file loads: %d of %d" % [loaded.size(), paths.size()]
	)
	for path in paths:
		var file_id := StringName(path.get_file().get_basename())
		assert_eq(loaded.has(file_id), true, "%s loads and is keyed by its filename" % path)


## The order is ID-KEYED, not `DirAccess` iteration order: `ContentScan` sorts, and a
## consumer that scans for the first wounded channel must get the same answer on every
## platform. Asserting the sequence, not just the set, is what pins that.
func test_the_loaded_order_is_the_sorted_filename_order() -> void:
	var paths := ContentScan.files_under(MeridianDefaults.DIR)
	var defs := MeridianDefaults.all()
	assert_eq(defs.size(), paths.size(), "same corpus")
	for index in range(defs.size()):
		assert_eq(
			String(defs[index].id),
			paths[index].get_file().get_basename(),
			"position %d is the %s file" % [index, paths[index].get_file()]
		)
