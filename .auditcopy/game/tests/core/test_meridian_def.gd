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
