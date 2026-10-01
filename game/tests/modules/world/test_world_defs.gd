extends TestCase

## ADR 0008: boss and domain content defs load and cross-reference.


func test_boss_def_loads() -> void:
	var boss := load("res://data/bosses/flame_dragon.tres")
	assert_eq(boss is BossDef, true, "loads BossDef")
	assert_eq(boss.domain_id, &"flame_valley", "domain")
	assert_eq(boss.loot.has(&"dragon_core"), true, "loot")


func test_domain_def_loads() -> void:
	var domain := load("res://data/domains/flame_valley.tres")
	assert_eq(domain is DomainDef, true, "loads DomainDef")
	assert_eq(domain.boss_ids.has(&"flame_dragon"), true, "boss")
