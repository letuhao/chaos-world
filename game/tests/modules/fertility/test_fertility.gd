extends TestCase

## ADR 0002: fertility owns conception -> gestation -> birth and offspring inheritance.


func _parent(id: StringName, fertility: float, potency: float) -> Actor:
	var actor := (
		Actor
		. new(
			id,
			{
				Stat.PHYSIQUE: 10.0,
				Stat.SPIRIT: 10.0,
				Stat.APTITUDE: 10.0,
				Stat.COMPREHENSION: 10.0,
				Stat.WILL: 10.0,
				Stat.FORTUNE: 10.0,
				DualCultivationApi.FERTILITY: fertility,
				DualCultivationApi.POTENCY: potency,
			}
		)
	)
	FertilityApi.attach(actor)
	return actor


func test_conception_on_low_roll() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	assert_eq(FertilityApi.try_conceive(mother, father, 0.0), true, "conceived")
	assert_eq(mother.has_status(FertilityStats.PREGNANCY), true, "pregnancy status")


func test_conception_blocked_on_high_roll() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	assert_eq(FertilityApi.try_conceive(mother, father, 1.0), false, "no conception")


func test_cannot_conceive_while_pregnant() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	FertilityApi.try_conceive(mother, father, 0.0)
	assert_eq(FertilityApi.try_conceive(mother, father, 0.0), false, "already pregnant")


func test_gestation_reaches_labor_and_birth() -> void:
	var mother := _parent(&"mother", 20.0, 10.0)
	var father := _parent(&"father", 10.0, 20.0)
	FertilityApi.try_conceive(mother, father, 0.0)
	FertilityApi.advance(mother, 0.1, null)
	var born: Array[Actor] = []
	for _i in 200:
		born = FertilityApi.advance(mother, 1.0, null)
		if not born.is_empty():
			break
	assert_eq(born.size(), 1, "one offspring")
	assert_almost_eq(born[0].stats.get_base(Stat.PHYSIQUE), 12.0, "inherited physique")


func test_offspring_inherits_both_parents() -> void:
	var mother := Actor.new(&"mother", {Stat.PHYSIQUE: 10.0})
	var father := Actor.new(&"father", {Stat.PHYSIQUE: 20.0})
	var base := FertilityApi.inherit_base(mother, father, 1.0)
	assert_almost_eq(float(base[Stat.PHYSIQUE]), 15.0, "averaged parents")
