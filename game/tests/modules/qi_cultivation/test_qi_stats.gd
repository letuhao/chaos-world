extends TestCase

## ADR 0011: QiStats constants — resource ids, base attributes, derived stats.


func test_resource_ids() -> void:
	assert_eq(QiStats.QI, &"qi", "qi resource id")
	assert_eq(QiStats.QI_PURITY, &"qi_purity", "qi_purity resource id")


func test_base_attribute_ids() -> void:
	assert_eq(QiStats.QI_AFFINITY, &"qi_affinity", "qi_affinity id")
	assert_eq(QiStats.QI_CONTROL, &"qi_control", "qi_control id")
	assert_eq(QiStats.DANTIAN_CAPACITY, &"dantian_capacity", "dantian_capacity id")


func test_derived_stat_ids() -> void:
	assert_eq(QiStats.QI_REGEN_RATE, &"qi_regen_rate", "qi_regen_rate id")
	assert_eq(QiStats.QI_ABSORPTION, &"qi_absorption", "qi_absorption id")
	assert_eq(QiStats.TECHNIQUE_COST_REDUCTION, &"technique_cost_reduction", "cost reduction id")
	assert_eq(QiStats.TECHNIQUE_POWER, &"technique_power", "technique_power id")
	assert_eq(QiStats.FLIGHT_SPEED, &"flight_speed", "flight_speed id")
	assert_eq(QiStats.QI_SENSE_RANGE, &"qi_sense_range", "qi_sense_range id")
