extends TestCase

## ADR 0001: base attributes are truth; derived stats recompute from base + modifiers.


func test_base_attributes_default_to_zero() -> void:
	var stats := ActorStats.new()
	assert_almost_eq(stats.get_base(Stat.PHYSIQUE), 0.0, "default physique")
	assert_almost_eq(stats.derived(Stat.MAX_HEALTH), 50.0, "base max health")


func test_derived_from_base() -> void:
	var stats := ActorStats.new({Stat.PHYSIQUE: 10.0})
	assert_almost_eq(stats.derived(Stat.MAX_HEALTH), 150.0, "max health from physique")


func test_flat_modifier() -> void:
	var stats := ActorStats.new({Stat.PHYSIQUE: 10.0})
	stats.add_modifier(StatModifier.new(Stat.MAX_HEALTH, Stat.Op.FLAT, 25.0, &"gear"))
	assert_almost_eq(stats.derived(Stat.MAX_HEALTH), 175.0, "flat modifier")


func test_percent_modifier() -> void:
	var stats := ActorStats.new({Stat.PHYSIQUE: 10.0})
	stats.add_modifier(StatModifier.new(Stat.MAX_HEALTH, Stat.Op.PERCENT, 0.5, &"buff"))
	assert_almost_eq(stats.derived(Stat.MAX_HEALTH), 225.0, "percent modifier")


func test_mult_modifier() -> void:
	var stats := ActorStats.new({Stat.PHYSIQUE: 10.0})
	stats.add_modifier(StatModifier.new(Stat.MAX_HEALTH, Stat.Op.MULT, 2.0, &"form"))
	assert_almost_eq(stats.derived(Stat.MAX_HEALTH), 300.0, "mult modifier")


func test_remove_modifiers_by_source() -> void:
	var stats := ActorStats.new({Stat.PHYSIQUE: 10.0})
	stats.add_modifier(StatModifier.new(Stat.MAX_HEALTH, Stat.Op.FLAT, 25.0, &"gear"))
	stats.remove_modifiers_from(&"gear")
	assert_almost_eq(stats.derived(Stat.MAX_HEALTH), 150.0, "modifier removed")
	assert_eq(stats.modifier_count(), 0, "modifier count")


func test_derived_clamps_at_zero() -> void:
	var stats := ActorStats.new()
	stats.add_modifier(StatModifier.new(Stat.MAX_HEALTH, Stat.Op.FLAT, -1000.0, &"curse"))
	assert_almost_eq(stats.derived(Stat.MAX_HEALTH), 0.0, "clamped at zero")
