extends TestCase

## ADR 0021: DaoDef resource tests.


func test_dao_def_defaults() -> void:
	var dao := DaoDef.new()
	assert_eq(dao.id, &"", "default id is empty")
	assert_eq(dao.display_name, "", "default display_name is empty")
	assert_eq(dao.conflicts.is_empty(), true, "no conflicts by default")
	assert_eq(dao.synergies.is_empty(), true, "no synergies by default")
	assert_eq(dao.effects.is_empty(), true, "no effects by default")


func test_dao_def_custom() -> void:
	var dao := DaoDef.new()
	dao.id = &"fire"
	dao.display_name = "Fire Dao"
	dao.conflicts = [&"water"]
	dao.synergies = [&"wood"]
	dao.effects = [&"fire_amp", &"water_cost_reduce"]
	assert_eq(dao.id, &"fire", "id set")
	assert_eq(dao.display_name, "Fire Dao", "display_name set")
	assert_eq(dao.conflicts.size(), 1, "conflicts set")
	assert_eq(dao.conflicts[0], &"water", "conflict value")
	assert_eq(dao.synergies.size(), 1, "synergies set")
	assert_eq(dao.synergies[0], &"wood", "synergy value")
	assert_eq(dao.effects.size(), 2, "effects set")


func test_dao_def_is_resource() -> void:
	var dao := DaoDef.new()
	assert_eq(dao is Resource, true, "DaoDef is a Resource")


func test_dao_def_predefined_types() -> void:
	# Verify all 20+ dao type constants exist
	assert_eq(DaoDef.SWORD, &"sword", "sword constant")
	assert_eq(DaoDef.BLADE, &"blade", "blade constant")
	assert_eq(DaoDef.SPEAR, &"spear", "spear constant")
	assert_eq(DaoDef.FIRE, &"fire", "fire constant")
	assert_eq(DaoDef.WATER, &"water", "water constant")
	assert_eq(DaoDef.WOOD, &"wood", "wood constant")
	assert_eq(DaoDef.METAL, &"metal", "metal constant")
	assert_eq(DaoDef.EARTH, &"earth", "earth constant")
	assert_eq(DaoDef.THUNDER, &"thunder", "thunder constant")
	assert_eq(DaoDef.WIND, &"wind", "wind constant")
	assert_eq(DaoDef.ICE, &"ice", "ice constant")
	assert_eq(DaoDef.SPACE, &"space", "space constant")
	assert_eq(DaoDef.TIME, &"time", "time constant")
	assert_eq(DaoDef.LIFE, &"life", "life constant")
	assert_eq(DaoDef.DEATH, &"death", "death constant")
	assert_eq(DaoDef.SOUL, &"soul", "soul constant")
	assert_eq(DaoDef.FORMATION, &"formation", "formation constant")
	assert_eq(DaoDef.ALCHEMY, &"alchemy", "alchemy constant")
	assert_eq(DaoDef.BEAST, &"beast", "beast constant")
	assert_eq(DaoDef.KARMA, &"karma", "karma constant")
